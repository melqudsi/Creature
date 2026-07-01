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
var _web_request_pending := false
var _web_request_result: Dictionary = {}
var _world_map: Node
var _poll_accum := 0.0
var _poll_in_flight := false
var _last_fetch_count := -1

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
	_poll_in_flight = false
	if _world_map and is_instance_valid(_world_map) and _world_map.has_method("sync_remote_creatures"):
		_world_map.sync_remote_creatures(rows)

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
	var path := "/rest/v1/creatures?name=eq.%s&select=*&limit=1" % profile_name.uri_encode()
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
	var cleaned_name := profile_name.strip_edges().substr(0, GameConfig.NAME_MAX_LEN)
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
		var claimed := await claim_creature(existing)
		if not claimed.is_empty():
			GameState.player_data = db_row_to_player_data(claimed)
			_log("Claimed profile '%s' for current session" % cleaned_name)
			return GameState.player_data
		_log("Claim failed for '%s' (temporary profile migration may be missing)" % cleaned_name)
		return {}

	var row := _new_creature_row(get_user_id(), cleaned_name, color)
	var created := await create_creature(row)
	if created.is_empty():
		_log("Create profile failed for '%s'" % cleaned_name)
		return {}
	GameState.player_data = db_row_to_player_data(created)
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

func claim_creature(row: Dictionary) -> Dictionary:
	var id := str(row.get("id", ""))
	if id.is_empty() or get_user_id().is_empty():
		return {}
	var patch := {
		"user_id": get_user_id(),
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
	_log("Delete returned zero rows and profile still exists for %s (RLS migration may be missing)" % creature_id)
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

func db_row_to_player_data(row: Dictionary, for_player: bool = true) -> Dictionary:
	var color := GameConfig.color_from_hex(str(row.get("color", "")))
	return {
		"id": str(row.get("id", "")),
		"user_id": str(row.get("user_id", "")),
		"name": str(row.get("name", GameConfig.DEFAULT_CREATURE_NAME)),
		"color": color,
		"appearance": "worm",
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
	_web_request_pending = true
	_web_request_result = {}
	var cb := JavaScriptBridge.create_callback(_on_web_request_done)
	net.runRequest(_method_name(method), url, JSON.stringify(headers_obj), body, cb)
	while _web_request_pending:
		await get_tree().process_frame
	return _parse_js_http_result(_web_request_result)

func _on_web_request_done(args: Array) -> void:
	if args.is_empty():
		_web_request_result = {"ok": false, "status": 0, "body": "Empty JS callback"}
	else:
		var parsed = JSON.parse_string(str(args[0]))
		_web_request_result = parsed if typeof(parsed) == TYPE_DICTIONARY else {"ok": false, "status": 0, "body": "Bad JS JSON"}
	_web_request_pending = false

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
