class_name WorldMap
extends Node3D

@onready var ground: MeshInstance3D = $Ground
@onready var trees_root: Node3D = $Trees
@onready var creatures_root: Node3D = $Creatures
@onready var click_marker: MeshInstance3D = $ClickMarker

const CREATURE_SCENE := preload("res://scenes/units/creature.tscn")

var _remote_by_user: Dictionary = {} # user_id -> Creature

func _ready() -> void:
	_build_ground()
	_build_trees()
	click_marker.visible = false

func spawn_player() -> void:
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
