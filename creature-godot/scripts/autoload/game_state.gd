extends Node

signal creature_registered(creature: Creature, is_player: bool)
signal creature_removed(creature_id: String)
signal toast_requested(message: String)
signal player_stats_changed

var creatures: Dictionary = {} # id -> Creature
var player_creature: Creature = null
var player_data: Dictionary = {}
var blocked_tiles: Array[Vector2i] = []
var _last_input_time: float = 0.0
var _stamina_regen_acc: float = 0.0

func _ready() -> void:
	for pos in GameConfig.TREE_POSITIONS:
		blocked_tiles.append(pos)
	if player_data.is_empty():
		player_data = GameConfig.default_player_data()

func register_creature(creature: Creature, data: Dictionary, is_player: bool = false) -> void:
	var id: String = data.get("id", str(creature.get_instance_id()))
	creature.set_meta("creature_id", id)
	creatures[id] = creature
	if is_player:
		player_creature = creature
		player_data = data.duplicate(true)
		_last_input_time = Time.get_ticks_msec() / 1000.0
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
	_last_input_time = Time.get_ticks_msec() / 1000.0
	if player_creature and player_creature.is_asleep:
		player_creature.wake_up()

func tick_player_stamina(delta: float, is_moving: bool) -> void:
	if not player_creature:
		return
	var stamina: int = player_creature.stamina
	if is_moving:
		_stamina_regen_acc = 0.0
		return
	if player_creature.is_asleep:
		_stamina_regen_acc = 0.0
		return
	if stamina >= GameConfig.STAMINA_MAX:
		return
	_stamina_regen_acc += delta * GameConfig.STAMINA_REGEN_PER_SEC
	if _stamina_regen_acc >= 1.0:
		var gain := int(_stamina_regen_acc)
		_stamina_regen_acc -= float(gain)
		player_creature.set_stamina(mini(GameConfig.STAMINA_MAX, stamina + gain))
		player_stats_changed.emit()

func check_afk_sleep() -> void:
	if not player_creature:
		return
	var now := Time.get_ticks_msec() / 1000.0
	if now - _last_input_time > GameConfig.AFK_SLEEP_SEC:
		if not player_creature.is_asleep:
			player_creature.fall_asleep()

func show_toast(msg: String) -> void:
	toast_requested.emit(msg)
