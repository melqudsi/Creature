class_name WorldMap
extends Node3D

@onready var ground: MeshInstance3D = $Ground
@onready var trees_root: Node3D = $Trees
@onready var creatures_root: Node3D = $Creatures
@onready var click_marker: MeshInstance3D = $ClickMarker

const CREATURE_SCENE := preload("res://scenes/units/creature.tscn")

var _remote_by_user: Dictionary = {} # user_id -> Creature
var _buildings_root: Node3D

func _ready() -> void:
	_resolve_child_roots()
	_ensure_buildings_root()
	_build_ground()
	_build_trees()
	_build_buildings()
	if click_marker:
		click_marker.visible = false

func _resolve_child_roots() -> void:
	ground = get_node_or_null("Ground") as MeshInstance3D
	trees_root = get_node_or_null("Trees") as Node3D
	creatures_root = get_node_or_null("Creatures") as Node3D
	click_marker = get_node_or_null("ClickMarker") as MeshInstance3D
	if trees_root == null:
		trees_root = Node3D.new()
		trees_root.name = "Trees"
		add_child(trees_root)
	if creatures_root == null:
		creatures_root = Node3D.new()
		creatures_root.name = "Creatures"
		add_child(creatures_root)

func spawn_player() -> void:
	_resolve_child_roots()
	var data := GameState.player_data
	if data.is_empty():
		data = GameConfig.default_player_data()
		GameState.player_data = data
	var player: Creature = CREATURE_SCENE.instantiate() as Creature
	creatures_root.add_child(player)
	player.setup(data)

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GameConfig.MAP_W * GameConfig.TILE_SIZE, GameConfig.MAP_H * GameConfig.TILE_SIZE)
	ground.mesh = plane
	ground.position = Vector3(GameConfig.MAP_W * 0.5, 0, GameConfig.MAP_H * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.54, 0.32)
	mat.roughness = 0.95
	ground.material_override = mat

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(plane.size.x, 0.2, plane.size.y)
	col.shape = shape
	body.add_child(col)
	ground.add_child(body)

func _build_trees() -> void:
	for pos in GameConfig.TREE_POSITIONS:
		var tree := _make_tree()
		trees_root.add_child(tree)
		var wp := GameConfig.tile_to_world(Vector2(pos))
		tree.position = Vector3(wp.x, 0, wp.z)

func _ensure_buildings_root() -> void:
	_buildings_root = get_node_or_null("Buildings") as Node3D
	if _buildings_root:
		return
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)

func _build_buildings() -> void:
	for pos in GameConfig.BUILDING_POSITIONS:
		var building := _make_building()
		_buildings_root.add_child(building)
		var wp := GameConfig.tile_to_world(Vector2(pos))
		building.position = Vector3(wp.x, 0, wp.z)

func _make_tree() -> Node3D:
	var root := Node3D.new()
	var trunk := MeshInstance3D.new()
	var trunk_mesh := BoxMesh.new()
	trunk_mesh.size = Vector3(0.25, 0.6, 0.25)
	trunk.mesh = trunk_mesh
	trunk.position.y = 0.3
	var tm := StandardMaterial3D.new()
	tm.albedo_color = Color(0.36, 0.25, 0.15)
	trunk.material_override = tm
	root.add_child(trunk)
	var foliage := MeshInstance3D.new()
	var fm := BoxMesh.new()
	fm.size = Vector3(0.9, 0.55, 0.9)
	foliage.mesh = fm
	foliage.position.y = 0.75
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(0.18, 0.48, 0.22)
	foliage.material_override = fmat
	root.add_child(foliage)
	return root

func _make_building() -> Node3D:
	var root := Node3D.new()
	var base := MeshInstance3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.45, 0.85, 1.25)
	base.mesh = base_mesh
	base.position.y = 0.425
	var base_mat := StandardMaterial3D.new()
	base_mat.albedo_color = Color.from_hsv(randf_range(0.05, 0.12), 0.28, 0.78)
	base_mat.roughness = 0.88
	base.material_override = base_mat
	root.add_child(base)

	var roof := MeshInstance3D.new()
	var roof_mesh := PrismMesh.new()
	roof_mesh.size = Vector3(1.7, 0.65, 1.45)
	roof.mesh = roof_mesh
	roof.position.y = 1.12
	roof.rotation_degrees.z = 90.0
	var roof_mat := StandardMaterial3D.new()
	roof_mat.albedo_color = Color(0.44, 0.12, 0.08)
	roof_mat.roughness = 0.72
	roof.material_override = roof_mat
	root.add_child(roof)

	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.28, 0.45, 0.04)
	door.mesh = door_mesh
	door.position = Vector3(0, 0.225, -0.65)
	var door_mat := StandardMaterial3D.new()
	door_mat.albedo_color = Color(0.23, 0.13, 0.07)
	door.material_override = door_mat
	root.add_child(door)
	root.rotation.y = [0.0, PI * 0.5, PI, PI * 1.5][randi() % 4]
	return root

func get_player_creature() -> Creature:
	return GameState.player_creature

func sync_remote_creatures(rows: Array) -> void:
	var player_uid := NetworkService.get_user_id()
	var seen: Dictionary = {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var uid := str(row.get("user_id", ""))
		if uid.is_empty() or uid == player_uid:
			continue
		seen[uid] = true
		if _remote_by_user.has(uid):
			var existing: Creature = _remote_by_user[uid]
			if is_instance_valid(existing):
				existing.apply_remote_state(row)
			continue
		var data := NetworkService.db_row_to_player_data(row, false)
		var remote: Creature = CREATURE_SCENE.instantiate() as Creature
		creatures_root.add_child(remote)
		remote.setup(data)
		_remote_by_user[uid] = remote
	for uid in _remote_by_user.keys():
		if seen.has(uid):
			continue
		var creature: Creature = _remote_by_user[uid]
		if is_instance_valid(creature):
			creature.queue_free()
		_remote_by_user.erase(uid)

func show_click_marker(world_pos: Vector3) -> void:
	click_marker.visible = true
	click_marker.position = world_pos + Vector3(0, 0.05, 0)
	var tween := create_tween()
	tween.tween_property(click_marker, "scale", Vector3(1.2, 1.2, 1.2), 0.25)
	tween.tween_callback(func(): click_marker.visible = false)
