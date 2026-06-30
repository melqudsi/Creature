extends Node

## Local-first stub mirroring js/api.js — Supabase in Phase 5.

var _session: Dictionary = {"user": {"id": "local_player"}}
var _saved_creature: Dictionary = {}

func ensure_auth() -> Dictionary:
	return _session

func fetch_my_creature(_user_id: String) -> Dictionary:
	if _saved_creature.is_empty():
		return {}
	return _saved_creature.duplicate(true)

func fetch_all_creatures() -> Array:
	var out: Array = []
	for id in GameState.creatures:
		var c: Creature = GameState.creatures[id]
		if is_instance_valid(c):
			out.append(creature_to_dict(c))
	return out

func fetch_map_objects() -> Array:
	var out: Array = []
	for pos in GameConfig.TREE_POSITIONS:
		out.append({"type": "tree", "x": pos.x, "y": pos.y})
	return out

func create_creature(row: Dictionary) -> Dictionary:
	_saved_creature = row.duplicate(true)
	if not _saved_creature.has("id"):
		_saved_creature["id"] = "local_%d" % Time.get_ticks_msec()
	save_creature_to_disk()
	return _saved_creature.duplicate(true)

func update_creature(_id: String, patch: Dictionary) -> void:
	for k in patch:
		_saved_creature[k] = patch[k]
	if GameState.player_creature:
		GameState.player_creature.apply_network_patch(patch)
	save_creature_to_disk()

func delete_creature(_id: String) -> void:
	_saved_creature.clear()
	save_creature_to_disk()

func record_eaten_event(_victim_user_id: String, _attacker_name: String) -> void:
	pass

func fetch_unread_events(_user_id: String) -> Array:
	return []

func mark_events_read(_ids: Array) -> void:
	pass

func creature_to_dict(creature: Creature) -> Dictionary:
	return {
		"id": creature.get_meta("creature_id"),
		"name": creature.creature_name,
		"color": creature.creature_color,
		"appearance": creature.appearance,
		"x": creature.grid_pos.x,
		"y": creature.grid_pos.y,
		"health": creature.health,
		"stamina": creature.stamina,
		"size_level": creature.size_level,
		"is_asleep": creature.is_asleep,
	}

func save_creature_to_disk() -> void:
	var f := FileAccess.open("user://creature_save.json", FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(_saved_creature))
		f.close()

func load_creature_from_disk() -> Dictionary:
	if not FileAccess.file_exists("user://creature_save.json"):
		return {}
	var f := FileAccess.open("user://creature_save.json", FileAccess.READ)
	if not f:
		return {}
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) == TYPE_DICTIONARY:
		_saved_creature = parsed
		return parsed.duplicate(true)
	return {}
