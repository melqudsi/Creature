extends Node

const DURATION_SEC := 30.0
const CREATURE_COUNT := 20
const PROP_COUNT := 50

@onready var _world_map: WorldMap = get_parent().get_node("WorldMap")

var _active := false
var _time_left := 0.0
var _spawned_creatures: Array[Creature] = []
var _spawned_props: Array[Node3D] = []
var _props_root: Node3D

func is_active() -> bool:
	return _active

func start() -> void:
	if _active:
		return
	_active = true
	_time_left = DURATION_SEC
	_ensure_props_root()
	_spawn_creatures()
	_spawn_props()
	GameState.show_toast("Pain test: %d creatures, %d props for %ds" % [CREATURE_COUNT, PROP_COUNT, int(DURATION_SEC)])

func _process(delta: float) -> void:
	if not _active:
		return
	_time_left -= delta
	if _time_left <= 0.0:
		stop()

func stop() -> void:
	if not _active and _spawned_creatures.is_empty() and _spawned_props.is_empty():
		return
	_active = false
	_time_left = 0.0
	for creature in _spawned_creatures:
		if is_instance_valid(creature):
			GameState.unregister_creature(creature.creature_id)
			creature.queue_free()
	_spawned_creatures.clear()
	for prop in _spawned_props:
		if is_instance_valid(prop):
			prop.queue_free()
	_spawned_props.clear()
	GameState.show_toast("Pain test ended")

func _ensure_props_root() -> void:
	if _props_root and is_instance_valid(_props_root):
		return
	_props_root = Node3D.new()
	_props_root.name = "PainTestProps"
	_world_map.add_child(_props_root)

func _spawn_creatures() -> void:
	for i in CREATURE_COUNT:
		var tile := _random_open_tile()
		var data := {
			"id": "pain_test_%d_%d" % [Time.get_ticks_msec(), i],
			"name": "Pain%d" % i,
			"color": GameConfig.CREATURE_COLORS[randi() % GameConfig.CREATURE_COLORS.size()],
			"appearance": "worm",
			"x": tile.x,
			"y": tile.y,
			"size_level": 1,
			"is_player": false,
		}
		var creature: Creature = WorldMap.CREATURE_SCENE.instantiate() as Creature
		_world_map.creatures_root.add_child(creature)
		creature.setup(data)
		var ai := creature.get_node_or_null("AIController")
		if ai:
			ai.enabled = true
			ai.wander_interval_min = 0.6
			ai.wander_interval_max = 1.8
		_spawned_creatures.append(creature)

func _spawn_props() -> void:
	for i in PROP_COUNT:
		var prop := _make_random_prop()
		prop.name = "PainProp_%d" % i
		_props_root.add_child(prop)
		_spawned_props.append(prop)

func _random_open_tile() -> Vector2i:
	for _attempt in 64:
		var tile := Vector2i(
			randi_range(1, GameConfig.MAP_W - 2),
			randi_range(1, GameConfig.MAP_H - 2)
		)
		if tile in GameState.blocked_tiles:
			continue
		if GameState.get_unit_tiles("").has(tile):
			continue
		return tile
	return Vector2i(GameConfig.MAP_W / 2, GameConfig.MAP_H / 2)

func _make_random_prop() -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var kind := randi() % 4
	var scale := randf_range(0.25, 0.9)

	match kind:
		0:
			var cube := BoxMesh.new()
			cube.size = Vector3.ONE * scale
			mesh_inst.mesh = cube
		1:
			var sphere := SphereMesh.new()
			sphere.radius = scale * 0.5
			sphere.height = scale
			mesh_inst.mesh = sphere
		2:
			var pyramid := PrismMesh.new()
			pyramid.size = Vector3(scale, scale * 1.1, scale)
			mesh_inst.mesh = pyramid
		3:
			var cylinder := CylinderMesh.new()
			cylinder.top_radius = scale * 0.45
			cylinder.bottom_radius = scale * 0.45
			cylinder.height = scale * randf_range(0.8, 1.6)
			mesh_inst.mesh = cylinder

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color.from_hsv(randf(), randf_range(0.35, 0.75), randf_range(0.55, 0.95))
	mat.roughness = randf_range(0.35, 0.95)
	mesh_inst.material_override = mat

	var margin := 1.2
	var y_offset := scale * 0.5
	mesh_inst.position = Vector3(
		randf_range(margin, GameConfig.MAP_W - margin),
		y_offset,
		randf_range(margin, GameConfig.MAP_H - margin)
	)
	mesh_inst.rotation.y = randf() * TAU
	mesh_inst.rotation.x = randf_range(-0.15, 0.15)
	return mesh_inst
