extends Node

## Supabase REST client for Godot — mirrors js/api.js (session + creature row).

const SESSION_PATH := "user://supabase_session.json"
const POSITION_SAVE_INTERVAL := 1.5
## DB check constraint only allows cute/ugly until migration-godot-session.sql is applied.
const DB_APPEARANCE := "cute"

var _session: Dictionary = {}
var _online := false
var _last_error := ""
var _save_creature_id := ""
var _save_pos := Vector2.ZERO
var _save_dirty := false
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
	if _save_dirty and _online:
		_save_timer += delta
		if _save_timer >= POSITION_SAVE_INTERVAL:
			_save_timer = 0.0
			_flush_position_save()
	if _online and _world_map and is_instance_valid(_world_map):
		_poll_accum += delta
		if _poll_accum >= GameConfig.POLL_OTHERS_SEC and not _poll_in_flight:
			_poll_accum = 0.0
			_poll_remote_creatures()

func start_creature_poll(world_map: Node) -> void:
	_world_map = world_map
	_poll_accum = GameConfig.POLL_OTHERS_SEC
	_log("Started creature poll")
	_poll_remote_creatures()

func fetch_all_creatures() -> Array:
	var resp := await _rest_request(HTTPClient.METHOD_GET, "/rest/v1/creatures?select=*")
	if not resp.ok:
		_log("fetch_all_creatures failed: %s" % resp.error)
		push_warning("fetch_all_creatures failed: %s" % resp.error)
		return []
	if typeof(resp.data) == TYPE_ARRAY:
		if int(resp.data.size()) != _last_fetch_count:
			_last_fetch_count = int(resp.data.size())
			_log("Fetched %d creature rows" % _last_fetch_count)
		return resp.data
	return []

func _poll_remote_creatures() -> void:
	if not _online or _world_map == null or not is_instance_valid(_world_map):
		return
	_poll_in_flight = true
	var rows: Array = await fetch_all_creatures()
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
	for entry in GameConfig.interactive_objects():
		var tile: Vector2 = entry["tile"]
		out.append({"type": str(entry["key"]), "x": tile.x, "y": tile.y, "state": "idle"})
	for entry in GameConfig.money_seed_objects():
		var tile: Vector2 = entry["tile"]
		out.append({"type": str(entry["key"]), "x": tile.x, "y": tile.y, "state": "idle"})
	return out

## Top-up seed for worlds created before the current slice: if money/bus
## (Slice 2) or the BBQ smoker (Slice 3) are missing, append them once (no wipe).
func _maybe_seed_slice2_objects(rows: Array) -> void:
	if _slice2_seed_attempted or not _world_objects_available:
		return
	var found := _note_seed_types(rows, {"money": false, "bus": false, "smoker": false})
	if found.money and found.bus and found.smoker:
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
	if to_add.is_empty():
		return
	var payload: Array = []
	for entry in to_add:
		var tile: Vector2 = entry["tile"]
		payload.append({"type": str(entry["key"]), "x": tile.x, "y": tile.y, "state": "idle"})
	var created := await seed_world_objects(payload)
	if not created.is_empty():
		_log("Top-up seeded %d world objects (money/bus/smoker)" % created.size())

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
	return found

func _note_world_row_columns(row: Dictionary) -> void:
	if not _owner_name_column_available and row.has("owner_name"):
		_owner_name_column_available = true

## POST the seed rows (array body) and return the created rows (with ids).
func seed_world_objects(rows: Array) -> Array:
	if not _online or rows.is_empty():
		return []
	var headers := _api_headers(true)
	headers.append("Prefer: return=representation")
	var resp := await _request(
		HTTPClient.METHOD_POST,
		GameConfig.SUPABASE_URL + "/rest/v1/world_objects",
		headers,
		JSON.stringify(rows)
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

func carry_world_object(object_id: String, user_id: String) -> void:
	update_world_object(object_id, {"state": "carried", "possessed_by": user_id})

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
	var headers := _api_headers(true)
	headers.append("Prefer: return=representation")
	var resp := await _request(
		HTTPClient.METHOD_POST,
		GameConfig.SUPABASE_URL + "/rest/v1/world_objects",
		headers,
		JSON.stringify(body)
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
## the client config (interactive objects + money + bus). Heals any stuck rows
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
	if _uses_web_bridge():
		_web_net().clearSessionJson()
	if FileAccess.file_exists(SESSION_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SESSION_PATH))
	_log("Cleared saved session; reload to show onboarding")

func boot() -> void:
	_last_error = ""
	GameState.player_data.clear()
	GameState.player_creature = null
	var ok := await _boot_online()
	if ok:
		if GameState.player_data.is_empty():
			_log("No profile for this session; showing onboarding")
		else:
			_log("Restored profile for %s" % GameState.player_data.get("name", "Creature"))
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
		GameState.player_data = db_row_to_player_data(row)
	else:
		_log("Authenticated session has no creature row")
	return true

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
	return rows[0]

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
	return rows[0]

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

func register_or_claim_profile(profile_name: String, color: Color) -> Dictionary:
	# Force ALL CAPS so lookups/stores are consistent and case-variant duplicates
	# ("Bob" vs "boB") can't be created; both stored value and query are uppercased.
	var cleaned_name := profile_name.strip_edges().to_upper().substr(0, GameConfig.NAME_MAX_LEN)
	if cleaned_name.is_empty():
		cleaned_name = GameConfig.DEFAULT_CREATURE_NAME
	if not _online and not await _boot_online():
		var local := GameConfig.default_player_data()
		local["name"] = cleaned_name
		local["color"] = color
		GameState.player_data = local
		_log("Offline profile created locally for %s" % cleaned_name)
		return local

	var existing := await fetch_creature_by_name(cleaned_name)
	if not existing.is_empty():
		_log("Attempting to claim existing profile '%s'" % cleaned_name)
		var claimed := await claim_creature(existing, color)
		if not claimed.is_empty():
			GameState.player_data = db_row_to_player_data(claimed)
			# The chosen color is authoritative for this session; do not depend on
			# the DB round-trip (a claimed row may carry a stale/previous color).
			GameState.player_data["color"] = color
			_log("Claimed profile '%s' for current session" % cleaned_name)
			return GameState.player_data
		var claim_hint := "Claim failed for '%s'." % cleaned_name
		if not _last_error.is_empty():
			claim_hint += " Last error: %s." % _short_error(_last_error)
		claim_hint += " To reclaim an existing profile by name, run supabase/migration-temp-profile-admin.sql in the Supabase SQL editor (adds policy creatures_temp_claim_by_name)."
		_log(claim_hint)
		return {}

	var row := _new_creature_row(get_user_id(), cleaned_name, color)
	var created := await create_creature(row)
	if created.is_empty():
		_log("Create profile failed for '%s'" % cleaned_name)
		return {}
	GameState.player_data = db_row_to_player_data(created)
	# Keep the exact chosen color in-session regardless of DB round-trip quirks.
	GameState.player_data["color"] = color
	_log("Created profile '%s'" % cleaned_name)
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
	_save_creature_id = creature_id
	_save_pos = Vector2(x, y)
	if flush_now:
		_save_dirty = false
		_save_timer = 0.0
		update_creature(creature_id, {
			"x": x,
			"y": y,
			"last_active": _iso_now(),
		})
		return
	_save_dirty = true

func has_form_column() -> bool:
	return _form_column_available

## Learn whether the `form` column exists by looking at any fetched/returned row.
func _note_row_columns(row: Dictionary) -> void:
	if not _form_column_available and typeof(row) == TYPE_DICTIONARY and row.has("form"):
		_form_column_available = true
		_log("Detected `form` column — form sync enabled")

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
	return {
		"id": str(row.get("id", "")),
		"user_id": str(row.get("user_id", "")),
		"name": str(row.get("name", GameConfig.DEFAULT_CREATURE_NAME)),
		"color": color,
		"appearance": "worm",
		"form": form,
		"x": clampf(float(row.get("x", GameConfig.MAP_W / 2)), 0.0, GameConfig.MAP_W - 1.0),
		"y": clampf(float(row.get("y", GameConfig.MAP_H / 2)), 0.0, GameConfig.MAP_H - 1.0),
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

func _flush_position_save() -> void:
	if not _save_dirty or _save_creature_id.is_empty():
		return
	_save_dirty = false
	_save_timer = 0.0
	await update_creature(_save_creature_id, {
		"x": _save_pos.x,
		"y": _save_pos.y,
		"last_active": _iso_now(),
	})

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
	_save_session_file()

func _auth_request(path: String, body: Dictionary) -> Dictionary:
	return await _request(
		HTTPClient.METHOD_POST,
		GameConfig.SUPABASE_URL + path,
		_api_headers(false),
		JSON.stringify(body)
	)

func _rest_request(method: int, path: String, body: Dictionary = {}, extra_headers: PackedStringArray = PackedStringArray()) -> Dictionary:
	var headers := _api_headers(true)
	for h in extra_headers:
		headers.append(h)
	var payload := "" if body.is_empty() else JSON.stringify(body)
	return await _request(method, GameConfig.SUPABASE_URL + path, headers, payload)

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
