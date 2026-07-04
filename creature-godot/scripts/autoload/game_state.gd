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
signal vehicle_wreck_requested(world_pos: Vector3, form_key: String)
## The local player died: the camera should zoom in on the death spot so the
## player can see what killed them during the respawn countdown.
signal death_zoom_requested(world_pos: Vector3)

## An abduction is playing nearby: the camera should pull back so the sky beam
## and ship (which sit far above the normal close-zoom frame) are visible.
signal abduction_zoom_requested(duration_sec: float)

## Slice 7: the dead player owns a safe house, so the HUD should show (true) or
## hide (false) the "Safe House / The Dump" respawn choice buttons.
signal respawn_choice_requested(show: bool)

var creatures: Dictionary = {} # id -> Creature
var player_creature: Creature = null
var player_data: Dictionary = {}
## The active WorldMap (set in WorldMap._ready). Lets gameplay code spawn shared
## objects (e.g. a combined money object) without a hard scene-path dependency.
var world_map: Node = null
## The ambient NPC traffic controller (set in WorldMap._ready). The player scans
## it for stopped vehicles that can be claimed via shapeshift.
var npc_traffic: Node = null
## Memphis Zoo exhibit animals (client-local wander + shapeshift targets).
var zoo_animals: Node = null
## Solid tiles (water/trees/houses/towers) as a Dictionary (Vector2i -> true)
## for O(1) pathfinding lookups — the Memphis map has thousands of them.
var blocked_tiles: Dictionary = {}
var admin_logs: Array[String] = []
## Last time the local player did anything (move, tap, HUD button). Used for
## idle auto-logout.
var last_player_input_ms: int = 0
## MOE admin: tap-to-teleport instead of pathfinding (set from admin panel).
var admin_test_mode := false
## Interactive/solid props (trees, buildings, shapeshift sources). Scanned by the
## local player each frame for collisions/kills/shapeshift prompts.
var world_objects: Array[WorldObject] = []

func _ready() -> void:
	blocked_tiles = MemphisLayout.blocked_tiles()

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
	last_player_input_ms = Time.get_ticks_msec()
	if player_creature and player_creature.is_asleep:
		player_creature.wake_up()

func show_toast(msg: String) -> void:
	toast_requested.emit(msg)

## Where to set money (or any prop) down: near `base`, in bounds, out of the
## water, and NOT inside a solid object (the vault-inside-an-Altima bug). Money
## objects don't count as blockers — dropping near money is how combines work.
func free_drop_tile(base: Vector2) -> Vector2:
	var first := GameConfig.safe_drop_tile(base)
	if _drop_tile_clear(first):
		return first
	for ring in [0.9, 1.5, 2.2]:
		for k in 8:
			var dir := Vector2.RIGHT.rotated(TAU * float(k) / 8.0)
			var cand := GameConfig.safe_drop_tile(base + dir * float(ring))
			if _drop_tile_clear(cand):
				return cand
	return first

func _drop_tile_clear(tile: Vector2) -> bool:
	if GridNav.is_blocked(Vector2i(int(floor(tile.x)), int(floor(tile.y))), blocked_tiles, {}):
		return false
	var wp := GameConfig.tile_to_world(tile)
	var at := Vector2(wp.x, wp.z)
	for obj in world_objects:
		if not is_instance_valid(obj) or obj.consumed or obj.is_money():
			continue
		if at.distance_to(Vector2(obj.position.x, obj.position.z)) < obj.radius + 0.45:
			return false
	return true

func add_admin_log(msg: String) -> void:
	var stamp := Time.get_time_string_from_system()
	var line := "[%s] %s" % [stamp, msg]
	admin_logs.append(line)
	if admin_logs.size() > 80:
		admin_logs.pop_front()
	admin_log_added.emit(line)
