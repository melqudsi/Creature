extends Node

signal creature_registered(creature: Creature, is_player: bool)
signal creature_removed(creature_id: String)
signal toast_requested(message: String)
signal player_stats_changed
signal admin_log_added(message: String)

var creatures: Dictionary = {} # id -> Creature
var player_creature: Creature = null
var player_data: Dictionary = {}
var blocked_tiles: Array[Vector2i] = []
var admin_logs: Array[String] = []

func _ready() -> void:
	for pos in GameConfig.TREE_POSITIONS:
		blocked_tiles.append(pos)
	for pos in GameConfig.BUILDING_POSITIONS:
		blocked_tiles.append(pos)

func register_creature(creature: Creature, data: Dictionary, is_player: bool = false) -> void:
	var id: String = data.get("id", str(creature.get_instance_id()))
	creature.set_meta("creature_id", id)
	creatures[id] = creature
	if is_player:
		player_creature = creature
		player_data = data.duplicate(true)
		player_stats_changed.emit()
	creature_registered.emit(creature, is_player)

func unregister_creature(creature_id: String) -> void:
	creatures.erase(creature_id)
	creature_removed.emit(creature_id)

func get_unit_tiles(exclude_id: String = "") -> Dictionary:
	var tiles := {}
	for id in creatures:
		if id == exclude_id:
			continue
		var c: Creature = creatures[id]
		if not is_instance_valid(c):
			continue
		tiles[Vector2i(int(round(c.grid_pos.x)), int(round(c.grid_pos.y)))] = id
	return tiles

func note_player_input() -> void:
	if player_creature and player_creature.is_asleep:
		player_creature.wake_up()

func show_toast(msg: String) -> void:
	toast_requested.emit(msg)

func add_admin_log(msg: String) -> void:
	var stamp := Time.get_time_string_from_system()
	var line := "[%s] %s" % [stamp, msg]
	admin_logs.append(line)
	if admin_logs.size() > 80:
		admin_logs.pop_front()
	admin_log_added.emit(line)
