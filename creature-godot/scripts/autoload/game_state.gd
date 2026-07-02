extends Node

signal creature_registered(creature: Creature, is_player: bool)
signal creature_removed(creature_id: String)
signal toast_requested(message: String)
signal player_stats_changed
signal admin_log_added(message: String)

## Slice 1 gameplay signals.
## form_changed        - the local player changed shapeshift form (FormDefs key)
## interaction_changed  - a "Become <X>" prompt should show/hide in the HUD
## explosion_requested  - something asked the world to spawn an explosion FX +
##                        apply its lethal radius (propane tank, etc.)
signal form_changed(form_key: String)
signal interaction_changed(can_become: bool, form_display: String)
signal explosion_requested(world_pos: Vector3, radius: float)
signal money_combined(world_pos: Vector3)
signal blood_splat_requested(world_pos: Vector3)

var creatures: Dictionary = {} # id -> Creature
var player_creature: Creature = null
var player_data: Dictionary = {}
## The active WorldMap (set in WorldMap._ready). Lets gameplay code spawn shared
## objects (e.g. a combined money object) without a hard scene-path dependency.
var world_map: Node = null
var blocked_tiles: Array[Vector2i] = []
var admin_logs: Array[String] = []
## Interactive/solid props (trees, buildings, shapeshift sources). Scanned by the
## local player each frame for collisions/kills/shapeshift prompts.
var world_objects: Array[WorldObject] = []

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

func register_world_object(obj: WorldObject) -> void:
	if not world_objects.has(obj):
		world_objects.append(obj)

func unregister_world_object(obj: WorldObject) -> void:
	world_objects.erase(obj)

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
