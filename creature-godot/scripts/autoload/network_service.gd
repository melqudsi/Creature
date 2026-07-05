extends Node

## Supabase REST client for Godot — mirrors js/api.js (session + creature row).

const SESSION_PATH := "user://supabase_session.json"
const POSITION_SAVE_INTERVAL := 1.5
## DB check constraint only allows cute/ugly until migration-godot-session.sql is applied.
const DB_APPEARANCE := "cute"
## Supabase access tokens (JWTs) expire after ~60 min. Refresh proactively well
## before that so long sessions never hit "JWT expired" mid-game; a reactive
## retry-on-401 in _rest_request_raw covers stragglers (e.g. after device sleep).
const JWT_REFRESH_INTERVAL_SEC := 2400.0
## Keep last_active fresh even when the player stands still, so the online-only
## creature poll filter (PRESENCE_WINDOW_SEC) never hides idle-but-connected
## players or frees their possessed objects.
const PRESENCE_HEARTBEAT_SEC := 60.0
## Poll filter: only creatures active in the last N seconds count as online.
## Must be comfortably larger than PRESENCE_HEARTBEAT_SEC + save latency.
const PRESENCE_WINDOW_SEC := 150

var _session: Dictionary = {}
var _online := false
var _last_error := ""
var _save_timer := 0.0
## Web-bridge requests are concurrent (poll + position save + money PATCHes can
## overlap); each in-flight request gets its own id so responses can't cross.
var _web_request_seq := 0
var _web_request_results: Dictionary = {}   # request id -> parsed result
var _web_request_callbacks: Dictionary = {} # request id -> JS callback (kept alive)
var _world_map: Node
var _poll_accum := 0.0
var _poll_in_flight := false
var _last_fetch_count := -1
## Whether the Supabase `creatures` table has the `form` column yet (added by
## supabase/migration-forms.sql). We learn this by inspecting fetched rows and
## only WRITE `form` once we know the column exists, so the client degrades
## gracefully (no crashes / broken writes) on a DB that hasn't run the migration.
var _form_column_available := false
## Shared/persistent interactive world objects (Fix 3). We only enable syncing
## after a successful fetch proves the `public.world_objects` table exists; if the
## migration hasn't been run the client degrades to client-local objects.
var _world_objects_available := false
var _world_objects_checked := false
var _world_objects_missing_logged := false
var _owner_name_column_available := false
var _slice2_seed_attempted := false
## Smart money floor (Slice 9): next Time.get_ticks_msec() the auto top-up may run.
var _money_topup_next_ms := 0
var _jwt_refresh_t := 0.0
var _heartbeat_t := 0.0
var _refresh_in_flight := false
var _last_refresh_unix := 0.0
## True once we've seen at least one creature row and learned which optional
## columns exist; until then the poll uses select=* (see _creature_select_columns).
var _creature_columns_probed := false
var _pattern_hash_column_available := false
var _resume_profile: Dictionary = {}

func _log(msg: String) -> void:
	GameState.add_admin_log(msg)

func _uses_web_bridge() -> bool:
	return OS.has_feature("web") and _web_net() != null

func _web_net() -> Object:
	if not OS.has_feature("web"):
		return null
	var win = JavaScriptBridge.get_interface("window")
	if win == null:
		return null
	var net = win.CreatureNet
	if net == null:
		return null
	return net

func _process(delta: float) -> void:
	if _online:
		_save_timer += delta
		if _save_timer >= POSITION_SAVE_INTERVAL:
			_save_timer = 0.0
			_autosave_player_position()
	if _online and _world_map and is_instance_valid(_world_map):
		_poll_accum += delta
		if _poll_accum >= GameConfig.POLL_OTHERS_SEC and not _poll_in_flight:
			_poll_accum = 0.0
			_poll_remote_creatures()
	if _online:
		_jwt_refresh_t += delta
		if _jwt_refresh_t >= JWT_REFRESH_INTERVAL_SEC:
			_jwt_refresh_t = 0.0
			_refresh_session_in_background()
		_heartbeat_t += delta
		if _heartbeat_t >= PRESENCE_HEARTBEAT_SEC:
			_heartbeat_t = 0.0
			_touch_presence()

## Proactive JWT refresh so a session older than ~1h keeps working.
func _refresh_session_in_background() -> void:
	if _refresh_in_flight:
		return
	_refresh_in_flight = true
	var ok := await _try_refresh_session()
	_refresh_in_flight = false
	if not ok:
		_log("Proactive session refresh failed: %s" % _last_error)

## Mark the local player dirty so the next save flush touches last_active,
## keeping them visible in other clients' online-only polls while idle.
func _touch_presence() -> void:
	var pc: Creature = GameState.player_creature
	if pc == null or not is_instance_valid(pc):
		return
	if pc.creature_id.is_empty():
		return
	_autosave_player_position()

func start_creature_poll(world_map: Node) -> void:
	_world_map = world_map
	_poll_accum = GameConfig.POLL_OTHERS_SEC
	_log("Started creature poll")
	_poll_remote_creatures()

## `online_only` (the poll path) filters to creatures active in the last
## PRESENCE_WINDOW_SEC and trims columns — this keeps per-poll egress flat no
## matter how many stale profiles accumulate. Admin tools pass false to list
## every profile ever created (needed for stale-profile cleanup).
func fetch_all_creatures(online_only: bool = false) -> Array:
	var path := "/rest/v1/creatures?select=*"
	if online_only:
		var cutoff_unix := int(Time.get_unix_time_from_system()) - PRESENCE_WINDOW_SEC
		var cutoff := Time.get_datetime_string_from_unix_time(cutoff_unix) + "Z"
		path = "/rest/v1/creatures?select=%s&last_active=gte.%s" % [
			_creature_select_columns(), cutoff.uri_encode()]
	var resp := await _rest_request(HTTPClient.METHOD_GET, path)
	if not resp.ok:
		_log("fetch_all_creatures failed: %s" % resp.error)
		push_warning("fetch_all_creatures failed: %s" % resp.error)
		return []
	if typeof(resp.data) == TYPE_ARRAY:
		var rows: Array = resp.data
		if not rows.is_empty() and typeof(rows[0]) == TYPE_DICTIONARY:
			_note_row_columns(rows[0])
			_creature_columns_probed = true
		if rows.size() != _last_fetch_count:
			_last_fetch_count = rows.size()
			_log("Fetched %d creature rows" % _last_fetch_count)
		return rows
	return []

## Poll payload trim: only the columns the client actually renders. The first
## fetch uses select=* so optional columns (form) are detected before we commit
## to naming them — explicitly selecting a missing column would fail the query
## on an un-migrated DB instead of degrading gracefully.
func _creature_select_columns() -> String:
	if not _creature_columns_probed:
		return "*"
	var cols := "id,user_id,name,color,x,y,size_level"
	if _form_column_available:
		cols += ",form"
	return cols

func _poll_remote_creatures() -> void:
	if not _online or _world_map == null or not is_instance_valid(_world_map):
		return
	_poll_in_flight = true
	var rows: Array = await fetch_all_creatures(true)
	if _world_map and is_instance_valid(_world_map) and _world_map.has_method("sync_remote_creatures"):
		_world_map.sync_remote_creatures(rows)
	# Poll shared world objects on the same cadence (creatures first so the
	# possession-liveness check sees the freshest creature set).
	await _poll_world_objects()
	_poll_in_flight = false

# ---------------------------------------------------------------------------
# Shared / persistent interactive world objects (Fix 3).
# ---------------------------------------------------------------------------

## Poll the shared world_objects table (if it exists), seeding it the first time
## if it's empty, then hand the rows to the world map to reconcile.
func _poll_world_objects() -> void:
	if not _online or _world_map == null or not is_instance_valid(_world_map):
		return
	var res := await fetch_world_objects()
	if res.get("missing", false):
		_world_objects_available = false
		if not _world_objects_missing_logged:
			_world_objects_missing_logged = true
			_log("world_objects table not found — interactive objects stay client-local. Run supabase/migration-world-objects.sql to enable shared/persistent objects.")
		return
	if not res.get("ok", false):
		return
	_world_objects_available = true
	var rows: Array = res.get("rows", [])
	for row in rows:
		if typeof(row) == TYPE_DICTIONARY:
			_note_world_row_columns(row)
	if not _world_objects_checked:
		_world_objects_checked = true
		if rows.is_empty():
			var created := await seed_world_objects(_build_world_object_seed())
			if not created.is_empty():
				rows = created
			else:
				return
			if not _world_objects_available:
				return
	else:
		await _maybe_seed_slice2_objects(rows)
	if _world_map and is_instance_valid(_world_map) and _world_map.has_method("sync_world_objects"):
		_world_map.sync_world_objects(rows)
	await _maybe_topup_money_stacks(rows)

## GET all shared world objects. Returns {ok, missing, rows}; `missing` is true
## when the table doesn't exist yet (so the caller can degrade gracefully).
func fetch_world_objects() -> Dictionary:
	if not _online:
		return {"ok": false, "missing": false, "rows": []}
	var resp := await _rest_request(HTTPClient.METHOD_GET, "/rest/v1/world_objects?select=*")
	if not resp.ok:
		if _looks_like_missing_table(str(resp.error)):
			return {"ok": false, "missing": true, "rows": []}
		return {"ok": false, "missing": false, "rows": []}
	var data: Variant = resp.data
	return {"ok": true, "missing": false, "rows": data if typeof(data) == TYPE_ARRAY else []}

func _looks_like_missing_table(err: String) -> bool:
	var e := err.to_lower()
	return e.find("42p01") >= 0 \
		or e.find("pgrst205") >= 0 \
		or e.find("does not exist") >= 0 \
		or e.find("could not find the table") >= 0 \
		or e.find("not find the table") >= 0

## Build the initial shared object set from the client config (tile coords).
func _build_world_object_seed() -> Array:
	var out: Array = []
	out.append_array(_seed_rows_from_entries(GameConfig.interactive_objects()))
	out.append_array(_seed_rows_from_entries(GameConfig.money_seed_objects()))
	out.append_array(_slice5_seed_rows())
	out.append_array(_slice6_seed_rows())
	out.append_array(_slice8_seed_rows())
	return out

func _seed_rows_from_entries(entries: Array) -> Array:
	var out: Array = []
	for entry in entries:
		var tile: Vector2 = entry["tile"]
		if entry.get("free", false):
			tile = _free_seed_tile(tile)
		out.append({"type": str(entry["key"]), "x": tile.x, "y": tile.y, "state": "idle"})
	return out

func _free_seed_tile(tile: Vector2) -> Vector2:
	tile = GameConfig.safe_drop_tile(tile)
	var ti := Vector2i(int(tile.x), int(tile.y))
	if MemphisLayout.blocked_tiles().has(ti):
		var open := GridNav.nearest_walkable(ti, ti, MemphisLayout.blocked_tiles(), {})
		if open.x >= 0:
			tile = Vector2(open)
	return tile

## Slice 6 rows: parked Altimas + carts in the Kroger lots.
func _slice6_seed_rows() -> Array:
	return _seed_rows_from_entries(GameConfig.slice6_seed_objects())

func _slice8_seed_rows() -> Array:
	return _seed_rows_from_entries(GameConfig.slice8_seed_objects())

## Slice 5 rows (road potholes, Midtown/Downtown BBQ trailers). Entries flagged
## "free" get nudged off blocked tiles (scattered houses/trees) at seed time.
func _slice5_seed_rows() -> Array:
	return _seed_rows_from_entries(GameConfig.slice5_seed_objects())

## Top-up seed for worlds created before the current slice: if money/bus
## (Slice 2) or the BBQ smoker (Slice 3) are missing, append them once (no wipe).
func _maybe_seed_slice2_objects(rows: Array) -> void:
	if _slice2_seed_attempted or not _world_objects_available:
		return
	var found := _note_seed_types(rows, {
		"money": false, "bus": false, "smoker": false, "slice5": false, "slice6": false,
		"slice8": false, "slice8_grill": false, "slice8_charger": false,
	})
	if found.money and found.bus and found.smoker and found.slice5 and found.slice6 and found.slice8:
		_slice2_seed_attempted = true
		return
	_slice2_seed_attempted = true
	# Anti-duplication: two clients booting at once would both notice the gap and
	# both seed. Wait a random beat, re-fetch, and only seed what's STILL missing.
	await get_tree().create_timer(randf_range(0.4, 2.2)).timeout
	var recheck := await fetch_world_objects()
	if not recheck.get("ok", false):
		return
	found = _note_seed_types(recheck.get("rows", []), found)
	var to_add: Array = []
	if not found.money:
		to_add.append_array(GameConfig.money_seed_objects())
	if not found.bus:
		to_add.append({"key": "bus", "tile": Vector2(29, 21)})
	if not found.smoker:
		to_add.append({"key": "smoker", "tile": Vector2(12, 6)})
	var payload: Array = []
	for entry in to_add:
		var tile: Vector2 = entry["tile"]
		payload.append({"type": str(entry["key"]), "x": tile.x, "y": tile.y, "state": "idle"})
	if not found.slice5:
		payload.append_array(_slice5_seed_rows())
	if not found.slice6:
		payload.append_array(_slice6_seed_rows())
	if not found.slice8:
		payload.append_array(_slice8_seed_rows())
	if payload.is_empty():
		return
	var created := await seed_world_objects(payload)
	if not created.is_empty():
		_log("Top-up seeded %d world objects (money/bus/smoker/slice5/slice6/slice8)" % created.size())

# ---------------------------------------------------------------------------
# Smart money floor (Slice 9): keep a minimum number of loose stacks in play.
# ---------------------------------------------------------------------------

## Minimum idle (uncarried, uncombined) money stacks scattered on the board.
const MONEY_STACK_FLOOR := 12
## How often each client re-evaluates the floor.
const MONEY_TOPUP_INTERVAL_MS := 60_000

## Combines, vault hoarding, and safe-house stockpiling steadily drain loose
## stacks from the map; this reseeds the difference at random open tiles so
## fresh players always find starter money. Throttled + jittered per client,
## with a fresh recount before seeding, so two clients rarely double-seed.
func _maybe_topup_money_stacks(rows: Array) -> void:
	if not _online or not _world_objects_available:
		return
	var now := Time.get_ticks_msec()
	if _money_topup_next_ms == 0:
		# First check is deferred + jittered so clients that boot together
		# don't all evaluate the floor on the same poll.
		_money_topup_next_ms = now + randi_range(15_000, 45_000)
		return
	if now < _money_topup_next_ms:
		return
	_money_topup_next_ms = now + MONEY_TOPUP_INTERVAL_MS + randi_range(0, 30_000)
	if _count_idle_money_stacks(rows) >= MONEY_STACK_FLOOR:
		return
	# Below the floor: recount from a FRESH fetch to close the race window
	# (another client may have just topped up).
	var recheck := await fetch_world_objects()
	if not recheck.get("ok", false):
		return
	var count := _count_idle_money_stacks(recheck.get("rows", []))
	if count >= MONEY_STACK_FLOOR:
		return
	var payload: Array = []
	for i in MONEY_STACK_FLOOR - count:
		var tile := GameConfig.random_open_tile()
		payload.append({"type": "money_stack", "x": tile.x, "y": tile.y, "state": "idle"})
	var created := await seed_world_objects(payload)
	if not created.is_empty():
		_log("Money floor: auto-seeded %d stacks (%d -> %d)" % [created.size(), count, MONEY_STACK_FLOOR])

func _count_idle_money_stacks(rows: Array) -> int:
	var n := 0
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		if str(row.get("type", "")) == "money_stack" and str(row.get("state", "idle")) == "idle":
			n += 1
	return n

func _note_seed_types(rows: Array, found: Dictionary) -> Dictionary:
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var t := str(row.get("type", ""))
		if t == "money_stack" or t == "money_bag" or t == "vault":
			found.money = true
		elif t == "bus":
			found.bus = true
		elif t == "smoker":
			found.smoker = true
			# Slice 5 marker: a smoker parked OUTSIDE the old South Memphis world
			# (Midtown/Downtown trailers) means the slice-5 seed already ran.
			if float(row.get("y", 999.0)) < 60.0:
				found.slice5 = true
		elif t == "cart":
			# Slice 6 marker: a cart outside the old world = Kroger lots seeded.
			if float(row.get("y", 999.0)) < 70.0:
				found.slice6 = true
		elif t == "bbq_grill":
			found.slice8_grill = true
			found.slice8 = bool(found.get("slice8_charger", false))
		elif t == "charger":
			found.slice8_charger = true
			found.slice8 = bool(found.get("slice8_grill", false))
	return found

func _note_world_row_columns(row: Dictionary) -> void:
	if not _owner_name_column_available and row.has("owner_name"):
		_owner_name_column_available = true

## POST the seed rows (array body) and return the created rows (with ids).
func seed_world_objects(rows: Array) -> Array:
	if not _online or rows.is_empty():
		return []
	var resp := await _rest_request_raw(
		HTTPClient.METHOD_POST,
		"/rest/v1/world_objects",
		JSON.stringify(rows),
		PackedStringArray(["Prefer: return=representation"])
	)
	if not resp.ok:
		if _looks_like_missing_table(str(resp.error)):
			_world_objects_available = false
		_log("seed_world_objects failed: %s" % resp.error)
		push_warning("seed_world_objects failed: %s" % resp.error)
		return []
	_log("Seeded %d shared world objects" % rows.size())
	if typeof(resp.data) == TYPE_ARRAY:
		return resp.data
	return []

func update_world_object(object_id: String, patch: Dictionary) -> void:
	if not _online or object_id.is_empty() or not _world_objects_available:
		return
	var body := patch.duplicate(true)
	body["updated_at"] = _iso_now()
	var path := "/rest/v1/world_objects?id=eq.%s" % object_id.uri_encode()
	var resp := await _rest_request(HTTPClient.METHOD_PATCH, path, body)
	if not resp.ok:
		_log("update_world_object failed: %s" % resp.error)
		push_warning("update_world_object failed: %s" % resp.error)

## Mark an object possessed by a player (hidden as a standalone prop everywhere).
func possess_world_object(object_id: String, user_id: String) -> void:
	update_world_object(object_id, {"state": "possessed", "possessed_by": user_id})

## Drop an object back into the world at tile (x, y) as idle (visible to all).
func release_world_object(object_id: String, x: float, y: float) -> void:
	update_world_object(object_id, {"state": "idle", "possessed_by": null, "x": x, "y": y})

## `owner_name` (when set) re-brands the loot in the same PATCH — picking up or
## stealing another player's bag/vault switches ownership to the taker.
func carry_world_object(object_id: String, user_id: String, owner_name: String = "") -> void:
	var patch := {"state": "carried", "possessed_by": user_id}
	if _owner_name_column_available and not owner_name.is_empty():
		patch["owner_name"] = owner_name
	update_world_object(object_id, patch)

func drop_money_object(object_id: String, x: float, y: float, owner_name: String) -> void:
	var patch := {"state": "idle", "possessed_by": null, "x": x, "y": y}
	if _owner_name_column_available:
		patch["owner_name"] = owner_name if not owner_name.is_empty() else null
	update_world_object(object_id, patch)

func create_world_object(fields: Dictionary) -> Dictionary:
	if not _online or not _world_objects_available:
		return {}
	var body := fields.duplicate(true)
	body["updated_at"] = _iso_now()
	if not _owner_name_column_available:
		body.erase("owner_name")
	var resp := await _rest_request_raw(
		HTTPClient.METHOD_POST,
		"/rest/v1/world_objects",
		JSON.stringify(body),
		PackedStringArray(["Prefer: return=representation"])
	)
	if not resp.ok:
		_log("create_world_object failed: %s" % resp.error)
		return {}
	if typeof(resp.data) == TYPE_ARRAY and not resp.data.is_empty():
		return resp.data[0]
	if typeof(resp.data) == TYPE_DICTIONARY:
		return resp.data
	return {}

func delete_world_object(object_id: String) -> void:
	if not _online or object_id.is_empty() or not _world_objects_available:
		return
	var path := "/rest/v1/world_objects?id=eq.%s" % object_id.uri_encode()
	await _rest_request(HTTPClient.METHOD_DELETE, path)

## ADMIN: delete every money object (all tiers) for everyone. Returns the count.
func admin_delete_all_money() -> int:
	if not _online or not _world_objects_available:
		return 0
	var headers := PackedStringArray(["Prefer: return=representation"])
	var resp := await _rest_request(
		HTTPClient.METHOD_DELETE,
		"/rest/v1/world_objects?type=in.(money_stack,money_bag,vault)",
		{},
		headers
	)
	if not resp.ok:
		_log("admin_delete_all_money failed: %s" % resp.error)
		return 0
	var n: int = resp.data.size() if typeof(resp.data) == TYPE_ARRAY else 0
	_log("ADMIN: deleted %d money objects" % n)
	return n

## ADMIN: nuke the ENTIRE shared world_objects table and re-seed it fresh from
## the full client seed list. Heals any stuck rows
## (orphaned possession/carry, duplicates, drifted positions).
func admin_reset_world_objects() -> bool:
	if not _online or not _world_objects_available:
		return false
	var resp := await _rest_request(
		HTTPClient.METHOD_DELETE,
		"/rest/v1/world_objects?id=not.is.null"
	)
	if not resp.ok:
		_log("admin_reset_world_objects delete failed: %s" % resp.error)
		return false
	var created := await seed_world_objects(_build_world_object_seed())
	_log("ADMIN: reset world objects (%d re-seeded)" % created.size())
	return not created.is_empty()

## ADMIN: seed `count` fresh money stacks at random open tiles. Returns created rows.
func admin_spawn_money_stacks(count: int) -> Array:
	if not _online or not _world_objects_available or count <= 0:
		return []
	var payload: Array = []
	for i in count:
		var tile := GameConfig.random_open_tile()
		payload.append({"type": "money_stack", "x": tile.x, "y": tile.y, "state": "idle"})
	var created := await seed_world_objects(payload)
	if not created.is_empty():
		_log("ADMIN: spawned %d money stacks" % created.size())
	return created

func is_online() -> bool:
	return _online

func get_user_id() -> String:
	return str(_session.get("user_id", ""))

func clear_saved_session() -> void:
	_session.clear()
	_online = false
	GameState.player_data.clear()
	GameState.player_creature = null
	_resume_profile.clear()
	if _uses_web_bridge():
		_web_net().clearSessionJson()
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	_log("Cleared saved session; reload to show onboarding")

## Leave the world for onboarding but keep the Supabase auth session so
## "Continue as …" works after the X button or idle exit.
func exit_to_onboarding() -> void:
	GameState.player_data.clear()
	GameState.player_creature = null
	_resume_profile.clear()
	_log("Exited to onboarding (session preserved)")

func boot() -> void:
	_last_error = ""
	GameState.player_data.clear()
	GameState.player_creature = null
	_resume_profile.clear()
	var ok := await _boot_online()
	if ok:
		if _resume_profile.is_empty():
			_log("No profile for this session; showing onboarding")
		else:
			_log("Session has profile for %s — onboarding with Continue" % _resume_profile.get("name", "Creature"))
		return
	_online = false
	var msg := "Could not reach server — starting locally"
	if not _last_error.is_empty():
		msg = "%s (%s)" % [msg, _short_error(_last_error)]
	GameState.show_toast(msg)
	_log(msg)
	push_warning("NetworkService boot failed: %s" % _last_error)

func _short_error(err: String) -> String:
	if err.length() <= 72:
		return err
	return err.substr(0, 69) + "..."

func _boot_online() -> bool:
	if not await ensure_auth():
		_last_error = "Could not sign in anonymously"
		return false
	_online = true
	var user_id := get_user_id()
	if user_id.is_empty():
		_last_error = "Auth succeeded but user id was empty"
		return false
	var row := await fetch_my_creature(user_id)
	if not row.is_empty():
		_resume_profile = db_row_to_player_data(row)
	else:
		_log("Authenticated session has no creature row")
	return true

## Profile tied to this auth session (for "Continue as …" on onboarding).
func get_resume_profile() -> Dictionary:
	return _resume_profile

func _resume_profile_name() -> String:
	if _resume_profile.is_empty():
		return ""
	return _clean_profile_name(str(_resume_profile.get("name", "")))

## On explicit manual auth (Log in/Register), allow switching away from the
## saved "Continue as X" session without requiring browser site-data clearing.
func _ensure_manual_auth_session(target_name: String, force_switch: bool = false) -> bool:
	var resume_name := _resume_profile_name()
	var need_switch := force_switch and not resume_name.is_empty()
	if not need_switch and not resume_name.is_empty() and not target_name.is_empty():
		need_switch = resume_name != target_name
	if need_switch:
		_log("Manual auth switching session from '%s' to '%s'" % [resume_name, target_name if not target_name.is_empty() else "new profile"])
		_session.clear()
		_online = false
		_resume_profile.clear()
		if _uses_web_bridge():
			_web_net().clearSessionJson()
		if FileAccess.file_exists(SESSION_PATH):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	if not _online and not await _boot_online():
		return false
	return true

## Skip manual login when the session already has a creature row.
func continue_resume_profile() -> Dictionary:
	if _resume_profile.is_empty():
		return {}
	GameState.player_data = _resume_profile.duplicate(true)
	_resume_profile.clear()
	_log("Continued as '%s'" % GameState.player_data.get("name", "Creature"))
	return GameState.player_data

func ensure_auth() -> bool:
	if await _try_refresh_session():
		return true
	return await _sign_in_anonymous()

func fetch_my_creature(user_id: String) -> Dictionary:
	var path := "/rest/v1/creatures?user_id=eq.%s&select=*&limit=1" % user_id.uri_encode()
	var resp := await _rest_request(HTTPClient.METHOD_GET, path)
	if not resp.ok:
		_last_error = "fetch creature: %s" % resp.error
		_log("fetch_my_creature failed: %s" % resp.error)
		push_warning("fetch_my_creature failed: %s" % resp.error)
		return {}
	var rows: Variant = resp.data
	if typeof(rows) != TYPE_ARRAY or rows.is_empty():
		return {}
	var row: Dictionary = rows[0]
	_note_row_columns(row)
	return row

func fetch_creature_by_name(profile_name: String) -> Dictionary:
	# Names are stored/matched in ALL CAPS (Postgres eq is case-sensitive).
	var query_name := profile_name.strip_edges().to_upper()
	var path := "/rest/v1/creatures?name=eq.%s&select=*&limit=1" % query_name.uri_encode()
	var resp := await _rest_request(HTTPClient.METHOD_GET, path)
	if not resp.ok:
		_last_error = "fetch creature by name: %s" % resp.error
		_log("fetch_creature_by_name failed: %s" % resp.error)
		push_warning("fetch_creature_by_name failed: %s" % resp.error)
		return {}
	var rows: Variant = resp.data
	if typeof(rows) != TYPE_ARRAY or rows.is_empty():
		return {}
	var row: Dictionary = rows[0]
	_note_row_columns(row)
	return row

func fetch_creature_by_id(creature_id: String) -> Dictionary:
	var path := "/rest/v1/creatures?id=eq.%s&select=*&limit=1" % creature_id.uri_encode()
	var resp := await _rest_request(HTTPClient.METHOD_GET, path)
	if not resp.ok:
		_log("fetch_creature_by_id failed: %s" % resp.error)
		push_warning("fetch_creature_by_id failed: %s" % resp.error)
		return {}
	var rows: Variant = resp.data
	if typeof(rows) != TYPE_ARRAY or rows.is_empty():
		return {}
	return rows[0]

# ---------------------------------------------------------------------------
# Pattern-lock onboarding (Slice 7): Register creates a fresh profile guarded
# by a swipe-pattern hash; Login verifies the pattern before claiming the row
# for the current anonymous session. Friendly lock, not real security.
# ---------------------------------------------------------------------------

## Human-readable last error for onboarding status labels.
func last_error_text() -> String:
	return _short_error(_last_error) if not _last_error.is_empty() else "Something went wrong"

## sha256 of name + dot sequence ("0-4-8-5"). The raw pattern is never stored.
static func pattern_hash_for(profile_name: String, pattern: String) -> String:
	return ("creature:%s:%s" % [profile_name, pattern]).sha256_text()

## Uppercase + trim, exactly how names are stored and queried.
static func _clean_profile_name(profile_name: String) -> String:
	return profile_name.strip_edges().to_upper().substr(0, GameConfig.NAME_MAX_LEN)

## REGISTER: the name must be free; the new row carries the pattern hash.
## Returns player_data on success, {} on failure (_last_error says why).
func register_profile(profile_name: String, color: Color, pattern: String) -> Dictionary:
	var cleaned_name := _clean_profile_name(profile_name)
	if cleaned_name.is_empty():
		_last_error = "Name required"
		return {}
	if not await _ensure_manual_auth_session(cleaned_name, true):
		var local := GameConfig.default_player_data()
		local["name"] = cleaned_name
		local["color"] = color
		GameState.player_data = local
		_log("Offline profile created locally for %s" % cleaned_name)
		return local
	var existing := await fetch_creature_by_name(cleaned_name)
	if not existing.is_empty():
		_last_error = "'%s' is taken — log in instead" % cleaned_name
		return {}
	var row := _new_creature_row(get_user_id(), cleaned_name, color)
	row["pattern_hash"] = pattern_hash_for(cleaned_name, pattern)
	var created := await create_creature(row)
	if created.is_empty() and _last_error.contains("pattern_hash"):
		# Column not migrated yet: register without the lock (degrade gracefully).
		_log("pattern_hash column missing — run supabase/migration-pattern-lock.sql. Registering without a lock.")
		row.erase("pattern_hash")
		created = await create_creature(row)
	if created.is_empty():
		_log("Create profile failed for '%s'" % cleaned_name)
		return {}
	_note_row_columns(created)
	if _pattern_hash_column_available:
		var expected := pattern_hash_for(cleaned_name, pattern)
		var saved := ""
		if created.get("pattern_hash") != null:
			saved = str(created.get("pattern_hash")).strip_edges()
		if saved.is_empty() or saved != expected:
			_last_error = "Pattern lock failed to save — run migration-pattern-lock.sql"
			_log("Register: pattern_hash not persisted for '%s'" % cleaned_name)
			return {}
	GameState.player_data = db_row_to_player_data(created)
	# Keep the exact chosen color in-session regardless of DB round-trip quirks.
	GameState.player_data["color"] = color
	_resume_profile.clear()
	_log("Registered profile '%s'" % cleaned_name)
	return GameState.player_data

## LOGIN: verify the pattern against the stored hash, then claim the row for
## this session. Pre-pattern profiles (hash empty/column missing) log straight
## in; if the column exists, the entered pattern becomes their lock.
func login_profile(profile_name: String, pattern: String) -> Dictionary:
	var cleaned_name := _clean_profile_name(profile_name)
	if cleaned_name.is_empty():
		_last_error = "Name required"
		return {}
	if not await _ensure_manual_auth_session(cleaned_name):
		_last_error = "Offline — can't log in"
		return {}
	var existing := await fetch_creature_by_name(cleaned_name)
	if existing.is_empty():
		_last_error = "No profile named '%s' — register instead" % cleaned_name
		return {}
	_note_row_columns(existing)
	if pattern.strip_edges().is_empty():
		_last_error = "Pattern required"
		return {}
	var stored_hash := ""
	if existing.get("pattern_hash") != null:
		stored_hash = str(existing.get("pattern_hash")).strip_edges()
	var entered_hash := pattern_hash_for(cleaned_name, pattern)
	if _pattern_hash_column_available:
		if not stored_hash.is_empty() and stored_hash != entered_hash:
			_last_error = "Wrong pattern"
			_log("Login rejected: pattern mismatch for '%s'" % cleaned_name)
			return {}
	elif not stored_hash.is_empty() and stored_hash != entered_hash:
		_last_error = "Wrong pattern"
		return {}
	var patch := {
		"user_id": get_user_id(),
		"last_active": _iso_now(),
		"updated_at": _iso_now(),
	}
	if _pattern_hash_column_available and stored_hash.is_empty():
		# First login after migration: adopt the pattern drawn now.
		patch["pattern_hash"] = entered_hash
	var id := str(existing.get("id", ""))
	var claimed := await _patch_creature_returning("/rest/v1/creatures?id=eq.%s" % id.uri_encode(), patch)
	if claimed.is_empty():
		var claim_hint := "Login claim failed for '%s'." % cleaned_name
		if not _last_error.is_empty():
			claim_hint += " Last error: %s." % _short_error(_last_error)
		claim_hint += " Claiming by name needs supabase/migration-temp-profile-admin.sql (policy creatures_temp_claim_by_name)."
		_log(claim_hint)
		_last_error = "Login failed — see admin log"
		return {}
	GameState.player_data = db_row_to_player_data(claimed)
	_resume_profile.clear()
	_log("Logged in as '%s'" % cleaned_name)
	return GameState.player_data

func create_creature(row: Dictionary) -> Dictionary:
	var headers_extra := PackedStringArray(["Prefer: return=representation"])
	var resp := await _rest_request(HTTPClient.METHOD_POST, "/rest/v1/creatures", row, headers_extra)
	if not resp.ok:
		_last_error = "create creature: %s" % resp.error
		_log("create_creature failed: %s" % resp.error)
		push_warning("create_creature failed: %s" % resp.error)
		return {}
	if typeof(resp.data) == TYPE_ARRAY and not resp.data.is_empty():
		return resp.data[0]
	if typeof(resp.data) == TYPE_DICTIONARY:
		return resp.data
	return {}

func claim_creature(row: Dictionary, color: Color = GameConfig.DEFAULT_CREATURE_COLOR) -> Dictionary:
	var id := str(row.get("id", ""))
	if id.is_empty() or get_user_id().is_empty():
		return {}
	var patch := {
		"user_id": get_user_id(),
		"color": GameConfig.color_to_hex(color),
		"last_active": _iso_now(),
		"updated_at": _iso_now(),
	}
	return await _patch_creature_returning("/rest/v1/creatures?id=eq.%s" % id.uri_encode(), patch)

func delete_creature_profile(creature_id: String) -> bool:
	if not _online or creature_id.is_empty():
		_log("Delete skipped: offline or missing id")
		return false
	var headers_extra := PackedStringArray(["Prefer: return=representation"])
	var resp := await _rest_request(
		HTTPClient.METHOD_DELETE,
		"/rest/v1/creatures?id=eq.%s" % creature_id.uri_encode(),
		{},
		headers_extra
	)
	if not resp.ok:
		_log("delete_creature_profile failed: %s" % resp.error)
		push_warning("delete_creature_profile failed: %s" % resp.error)
		return false
	if typeof(resp.data) == TYPE_ARRAY and not resp.data.is_empty():
		_log("Deleted profile id %s" % creature_id)
		return true
	var still_exists := await fetch_creature_by_id(creature_id)
	if still_exists.is_empty():
		_log("Deleted profile id %s (verified by re-fetch)" % creature_id)
		return true
	_log("Delete returned zero rows and profile %s still exists. RLS is blocking the delete. Run supabase/migration-temp-profile-admin.sql in the Supabase SQL editor (adds policy creatures_temp_admin_delete) to allow admin deletes." % creature_id)
	return false

func update_creature(id: String, patch: Dictionary) -> void:
	if not _online or id.is_empty():
		return
	var path := "/rest/v1/creatures?id=eq.%s" % id.uri_encode()
	var body := patch.duplicate(true)
	body["updated_at"] = _iso_now()
	var resp := await _rest_request(HTTPClient.METHOD_PATCH, path, body)
	if not resp.ok:
		_log("update_creature failed: %s" % resp.error)
		push_warning("update_creature failed: %s" % resp.error)

func _patch_creature_returning(path: String, patch: Dictionary) -> Dictionary:
	var headers_extra := PackedStringArray(["Prefer: return=representation"])
	var resp := await _rest_request(HTTPClient.METHOD_PATCH, path, patch, headers_extra)
	if not resp.ok:
		_last_error = "patch creature: %s" % resp.error
		_log("_patch_creature_returning failed: %s" % resp.error)
		push_warning("_patch_creature_returning failed: %s" % resp.error)
		return {}
	if typeof(resp.data) == TYPE_ARRAY and not resp.data.is_empty():
		return resp.data[0]
	if typeof(resp.data) == TYPE_DICTIONARY:
		return resp.data
	return {}

func save_creature_position(creature_id: String, x: float, y: float, flush_now: bool = false) -> void:
	if not _online or creature_id.is_empty():
		return
	if flush_now:
		update_creature(creature_id, {
			"x": x,
			"y": y,
			"last_active": _iso_now(),
		})
		return
	# Non-flush calls are ignored — position sync runs on POSITION_SAVE_INTERVAL
	# via _autosave_player_position(), decoupled from tap-to-move.

## Push the live player position to Supabase on the fixed interval. Movement and
## tap-to-move never wait on this — they update grid_pos locally every frame.
func _autosave_player_position() -> void:
	var pc: Creature = GameState.player_creature
	if pc == null or not is_instance_valid(pc) or pc.creature_id.is_empty():
		return
	update_creature(pc.creature_id, {
		"x": pc.grid_pos.x,
		"y": pc.grid_pos.y,
		"last_active": _iso_now(),
	})

func has_form_column() -> bool:
	return _form_column_available

## Learn whether the `form` column exists by looking at any fetched/returned row.
func _note_row_columns(row: Dictionary) -> void:
	if not _form_column_available and typeof(row) == TYPE_DICTIONARY and row.has("form"):
		_form_column_available = true
		_log("Detected `form` column — form sync enabled")
	if not _pattern_hash_column_available and typeof(row) == TYPE_DICTIONARY and row.has("pattern_hash"):
		_pattern_hash_column_available = true
		_log("Detected `pattern_hash` column — pattern lock enabled")

## Persist the player's current shapeshift form. No-op (graceful) until we know
## the `form` column exists, so writes never fail on an un-migrated DB.
func save_creature_form(creature_id: String, form_key: String) -> void:
	if not _online or creature_id.is_empty() or not _form_column_available:
		return
	update_creature(creature_id, {"form": form_key})

func db_row_to_player_data(row: Dictionary, for_player: bool = true) -> Dictionary:
	_note_row_columns(row)
	var color := GameConfig.color_from_hex(str(row.get("color", "")))
	var form := str(row.get("form", "alien"))
	var x := float(row.get("x", GameConfig.LANDFILL_CENTER.x))
	var y := float(row.get("y", GameConfig.LANDFILL_CENTER.y))
	# (The legacy 32x24-map position remap that used to live here is gone: it
	# false-positived on the whole north-Downtown/Pyramid/Mud Island corner,
	# teleporting anyone parked there to South Memphis on reload. Old-map saves
	# migrated days ago and self-healed via the spawn/heartbeat flush.)
	return {
		"id": str(row.get("id", "")),
		"user_id": str(row.get("user_id", "")),
		"name": str(row.get("name", GameConfig.DEFAULT_CREATURE_NAME)),
		"color": color,
		"appearance": "worm",
		"form": form,
		"x": clampf(x, 0.0, GameConfig.MAP_W - 1.0),
		"y": clampf(y, 0.0, GameConfig.MAP_H - 1.0),
		"size_level": int(row.get("size_level", 1)),
		"is_player": for_player,
		"is_remote": not for_player,
	}

func creature_to_dict(creature: Creature) -> Dictionary:
	return {
		"id": creature.get_meta("creature_id"),
		"name": creature.creature_name,
		"color": GameConfig.color_to_hex(creature.creature_color),
		"appearance": creature.appearance,
		"x": creature.grid_pos.x,
		"y": creature.grid_pos.y,
		"size_level": creature.size_level,
	}

func _new_creature_row(user_id: String, profile_name: String = "", color: Color = GameConfig.DEFAULT_CREATURE_COLOR) -> Dictionary:
	var defaults := GameConfig.default_player_data()
	var final_name := profile_name if not profile_name.is_empty() else str(defaults["name"])
	return {
		"user_id": user_id,
		"name": final_name,
		"color": GameConfig.color_to_hex(color),
		"appearance": DB_APPEARANCE,
		"x": defaults["x"],
		"y": defaults["y"],
		"health": 100,
		"stamina": 10,
		"size_level": 1,
		"is_asleep": false,
	}

func _try_refresh_session() -> bool:
	var stored := _load_session_file()
	var refresh_token: String = str(stored.get("refresh_token", ""))
	if refresh_token.is_empty():
		return false
	var resp := await _auth_request(
		"/auth/v1/token?grant_type=refresh_token",
		{"refresh_token": refresh_token}
	)
	if not resp.ok:
		_last_error = "session refresh: %s" % resp.error
		return false
	_apply_auth_response(resp.data)
	if get_user_id().is_empty() or str(_session.get("access_token", "")).is_empty():
		_last_error = "Auth response missing user or token"
		return false
	return true

func _sign_in_anonymous() -> bool:
	var resp := await _auth_request("/auth/v1/signup", {})
	if not resp.ok:
		_last_error = "anonymous sign-in: %s" % resp.error
		return false
	_apply_auth_response(resp.data)
	if get_user_id().is_empty() or str(_session.get("access_token", "")).is_empty():
		_last_error = "Anonymous sign-in missing user or token"
		return false
	return true

func _apply_auth_response(data: Dictionary) -> void:
	if data.is_empty():
		return
	var user: Variant = data.get("user", {})
	var user_id := ""
	if typeof(user) == TYPE_DICTIONARY:
		user_id = str(user.get("id", ""))
	_session = {
		"access_token": str(data.get("access_token", "")),
		"refresh_token": str(data.get("refresh_token", "")),
		"user_id": user_id,
	}
	_last_refresh_unix = Time.get_unix_time_from_system()
	_save_session_file()

func _auth_request(path: String, body: Dictionary) -> Dictionary:
	return await _request(
		HTTPClient.METHOD_POST,
		GameConfig.SUPABASE_URL + path,
		_api_headers(false),
		JSON.stringify(body)
	)

func _rest_request(method: int, path: String, body: Dictionary = {}, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var payload := "" if body.is_empty() else JSON.stringify(body)
	return await _rest_request_raw(method, path, payload, extra_headers)

## All REST traffic funnels through here so an expired JWT (HTTP 401) triggers
## one refresh + retry instead of silently failing until the page is reloaded.
## Headers are rebuilt on retry so the fresh access token is used.
func _rest_request_raw(method: int, path: String, payload: String, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var resp := await _send_rest(method, path, payload, extra_headers)
	if not resp.ok and str(resp.get("error", "")).begins_with("HTTP 401"):
		if await _refresh_for_retry():
			resp = await _send_rest(method, path, payload, extra_headers)
	return resp

func _send_rest(method: int, path: String, payload: String, extra_headers: PackedStringArray) -> Dictionary:
	var headers := _api_headers(true)
	for h in extra_headers:
		headers.append(h)
	return await _request(method, GameConfig.SUPABASE_URL + path, headers, payload)

## Refresh the session for a 401 retry. Deduplicates concurrent callers: if a
## refresh is already in flight (or just finished), reuse its outcome instead
## of burning extra token-refresh requests (rate limit: 1800/hour/IP).
func _refresh_for_retry() -> bool:
	while _refresh_in_flight:
		await get_tree().process_frame
	if Time.get_unix_time_from_system() - _last_refresh_unix < 30.0:
		return true # token was just refreshed (by us or another caller) — retry with it
	_refresh_in_flight = true
	var ok := await _try_refresh_session()
	_refresh_in_flight = false
	if ok:
		_jwt_refresh_t = 0.0
		_log("Recovered from expired JWT (refreshed mid-session)")
	return ok

func _request(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	if _uses_web_bridge():
		return await _request_via_web_bridge(method, url, headers, body)
	var http := HTTPRequest.new()
	add_child(http)
	var err := http.request(url, headers, method, body)
	if err != OK:
		http.queue_free()
		return {"ok": false, "error": "HTTPRequest failed (%s)" % err}
	var result: Array = await http.request_completed
	http.queue_free()
	return _parse_http_result(result)

func _request_via_web_bridge(method: int, url: String, headers: PackedStringArray, body: String) -> Dictionary:
	var net := _web_net()
	if net == null:
		return {"ok": false, "error": "CreatureNet JS bridge missing"}
	var headers_obj := {}
	for h in headers:
		var sep := h.find(": ")
		if sep > 0:
			headers_obj[h.substr(0, sep)] = h.substr(sep + 2)
	_web_request_seq += 1
	var rid := _web_request_seq
	var cb := JavaScriptBridge.create_callback(func(args: Array) -> void:
		var parsed: Variant = null
		if not args.is_empty():
			parsed = JSON.parse_string(str(args[0]))
		if typeof(parsed) != TYPE_DICTIONARY:
			parsed = {"ok": false, "status": 0, "body": "Bad JS JSON"}
		_web_request_results[rid] = parsed)
	_web_request_callbacks[rid] = cb # keep a ref or the JS callback is GC'd
	net.runRequest(_method_name(method), url, JSON.stringify(headers_obj), body, cb)
	while not _web_request_results.has(rid):
		await get_tree().process_frame
	var result: Dictionary = _web_request_results[rid]
	_web_request_results.erase(rid)
	_web_request_callbacks.erase(rid)
	return _parse_js_http_result(result)

func _method_name(method: int) -> String:
	match method:
		HTTPClient.METHOD_GET: return "GET"
		HTTPClient.METHOD_POST: return "POST"
		HTTPClient.METHOD_PATCH: return "PATCH"
		HTTPClient.METHOD_PUT: return "PUT"
		HTTPClient.METHOD_DELETE: return "DELETE"
		_: return "GET"

func _parse_js_http_result(payload: Dictionary) -> Dictionary:
	var status := int(payload.get("status", 0))
	var body_text := str(payload.get("body", ""))
	if status == 0:
		return {"ok": false, "error": body_text if not body_text.is_empty() else "Browser network error (CORS or offline)"}
	if status < 200 or status >= 300:
		return {"ok": false, "error": "HTTP %d: %s" % [status, body_text]}
	if body_text.is_empty():
		return {"ok": true, "data": {}}
	var parsed = JSON.parse_string(body_text)
	if parsed == null:
		return {"ok": false, "error": "Invalid JSON response"}
	return {"ok": true, "data": parsed}

func _parse_http_result(result: Array) -> Dictionary:
	var response_code: int = int(result[1])
	var body_bytes: PackedByteArray = result[3]
	if response_code < 200 or response_code >= 300:
		var err_text := body_bytes.get_string_from_utf8()
		return {"ok": false, "error": "HTTP %d: %s" % [response_code, err_text]}
	if body_bytes.is_empty():
		return {"ok": true, "data": {}}
	var parsed = JSON.parse_string(body_bytes.get_string_from_utf8())
	if parsed == null:
		return {"ok": false, "error": "Invalid JSON response"}
	return {"ok": true, "data": parsed}

func _api_headers(use_user_token: bool) -> PackedStringArray:
	var headers := PackedStringArray([
		"Content-Type: application/json",
		"apikey: %s" % GameConfig.SUPABASE_ANON_KEY,
	])
	if use_user_token and not str(_session.get("access_token", "")).is_empty():
		headers.append("Authorization: Bearer %s" % str(_session.get("access_token", "")))
	else:
		headers.append("Authorization: Bearer %s" % GameConfig.SUPABASE_ANON_KEY)
	return headers

func _load_session_file() -> Dictionary:
	if _uses_web_bridge():
		var raw := str(_web_net().getSessionJson())
		if not raw.is_empty():
			var parsed_web = JSON.parse_string(raw)
			if typeof(parsed_web) == TYPE_DICTIONARY:
				return parsed_web
	if not FileAccess.file_exists(SESSION_PATH):
		return {}
	var file := FileAccess.open(SESSION_PATH, FileAccess.READ)
	if file == null:
		return {}
	var parsed = JSON.parse_string(file.get_as_text())
	file.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		return parsed
	return {}

func _save_session_file() -> void:
	var json := JSON.stringify(_session)
	if _uses_web_bridge():
		_web_net().saveSessionJson(json)
	var file := FileAccess.open(SESSION_PATH, FileAccess.WRITE)
	if file == null:
		return
	file.store_string(json)
	file.close()

func _iso_now() -> String:
	var dt := Time.get_datetime_dict_from_system(true)
	return "%04d-%02d-%02dT%02d:%02d:%02dZ" % [
		dt.year, dt.month, dt.day, dt.hour, dt.minute, dt.second
	]
