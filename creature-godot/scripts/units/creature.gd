class_name Creature
extends Node3D

@onready var body_root: Node3D = $Body
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var health_bar: Node3D = $HealthBar
@onready var health_fill: MeshInstance3D = $HealthBar/Fill
@onready var sleep_fx: Node3D = $SleepFX
@onready var spawn_fx: Node3D = $SpawnFX

const SEGMENT_ROT := Vector3(90, 0, 0)

# Capsules laid horizontally along +Z (head at front). Overlap hides gaps.
const SEGMENT_SPECS: Array[Dictionary] = [
	{"z": 0.38, "radius": 0.1, "length": 0.3, "shade": 1.06},
	{"z": 0.16, "radius": 0.13, "length": 0.34, "shade": 1.0},
	{"z": -0.08, "radius": 0.14, "length": 0.36, "shade": 0.97},
	{"z": -0.32, "radius": 0.12, "length": 0.32, "shade": 0.92},
	{"z": -0.5, "radius": 0.07, "length": 0.22, "shade": 0.86},
]

var creature_id: String = ""
var creature_name: String = "Creature"
var creature_color: Color = GameConfig.DEFAULT_CREATURE_COLOR
var appearance: String = "worm"
var grid_pos := Vector2(8, 6)
var size_level := 1
var is_asleep := false
var is_player := false
var is_remote := false
var is_moving := false
var is_spawning := false

var _move_dir := Vector2.ZERO
var _move_target: Vector2 = Vector2(-1, -1)
var _path: Array[Vector2] = []
var _walk_phase := 0.0
var _spawn_t := 0.0
var _breath_phase := 0.0
var _body_scale := 1.0
var _remote_target := Vector2.ZERO
var _segments: Array[MeshInstance3D] = []
var _eyes: Array[MeshInstance3D] = []

func _ready() -> void:
	_style_selection_ring()
	sleep_fx.visible = false
	spawn_fx.visible = false
	health_bar.visible = false

func setup(data: Dictionary) -> void:
	creature_id = data.get("id", str(get_instance_id()))
	set_meta("creature_id", creature_id)
	creature_name = str(data.get("name", GameConfig.DEFAULT_CREATURE_NAME)).substr(0, GameConfig.NAME_MAX_LEN)
	creature_color = data.get("color", GameConfig.DEFAULT_CREATURE_COLOR)
	appearance = "worm"
	grid_pos = Vector2(data.get("x", 8.0), data.get("y", 6.0))
	size_level = int(data.get("size_level", 1))
	is_player = data.get("is_player", false)
	is_remote = data.get("is_remote", false)
	is_asleep = data.get("is_asleep", false)
	_apply_appearance()
	_update_transform(true, 0.0)
	health_bar.visible = false
	selection_ring.visible = is_player
	if is_player:
		is_spawning = true
		spawn_fx.visible = true
		_spawn_t = 0.0
		scale = Vector3(0.01, 0.01, 0.01)
	elif is_remote:
		_remote_target = grid_pos
		scale = Vector3.ONE * _body_scale
	if creature_id != "preview" and creature_id != "portrait":
		GameState.register_creature(self, data, is_player)

func _style_selection_ring() -> void:
	if not selection_ring:
		return
	selection_ring.visible = false
	var rmat := StandardMaterial3D.new()
	rmat.albedo_color = Color(0.15, 0.95, 0.45, 0.55)
	rmat.emission_enabled = true
	rmat.emission = Color(0.1, 0.75, 0.35)
	rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	selection_ring.material_override = rmat

func _apply_appearance() -> void:
	if not body_root:
		return
	_clear_body_children()
	_segments.clear()
	_eyes.clear()
	_body_scale = 0.92 + (size_level - 1) * 0.08
	body_root.rotation_degrees = Vector3.ZERO
	body_root.position = Vector3.ZERO
	body_root.scale = Vector3.ONE * _body_scale
	for spec in SEGMENT_SPECS:
		_segments.append(_add_segment(spec))
	_add_alien_eyes()
	_reset_body_pose()

func _clear_body_children() -> void:
	for ch in body_root.get_children():
		body_root.remove_child(ch)
		ch.queue_free()

func _segment_rest_position(spec: Dictionary) -> Vector3:
	return Vector3(0.0, spec.radius * 0.92, spec.z)

func _add_segment(spec: Dictionary) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = spec.radius
	capsule.height = maxf(spec.length, spec.radius * 2.4)
	mesh_inst.mesh = capsule
	mesh_inst.rotation_degrees = SEGMENT_ROT
	mesh_inst.position = _segment_rest_position(spec)
	var shade: float = spec.shade
	var mat := StandardMaterial3D.new()
	var base := creature_color
	mat.albedo_color = Color(
		base.r * shade,
		base.g * shade,
		base.b * shade,
		1.0
	)
	mat.roughness = 0.82
	mat.metallic = 0.02
	mat.rim_enabled = true
	mat.rim = 0.25
	mat.rim_tint = 0.35
	body_root.add_child(mesh_inst)
	mesh_inst.material_override = mat
	return mesh_inst

func _add_alien_eyes() -> void:
	if _segments.is_empty():
		return
	var head_spec: Dictionary = SEGMENT_SPECS[0]
	var head_z: float = head_spec.z
	var head_y: float = head_spec.radius * 0.92
	for side in [-1.0, 1.0]:
		var eye := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.04
		sphere.height = 0.08
		eye.mesh = sphere
		eye.position = Vector3(side * 0.075, head_y + 0.05, head_z + 0.14)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.12, 0.85, 0.78)
		mat.emission_enabled = true
		mat.emission = Color(0.08, 0.55, 0.5)
		mat.emission_energy_multiplier = 1.8
		eye.material_override = mat
		body_root.add_child(eye)
		_eyes.append(eye)

func _reset_body_pose() -> void:
	if not body_root:
		return
	body_root.rotation_degrees = Vector3.ZERO
	body_root.position = Vector3.ZERO
	body_root.scale = Vector3.ONE * _body_scale
	for i in _segments.size():
		var seg := _segments[i]
		var spec: Dictionary = SEGMENT_SPECS[i]
		seg.position = _segment_rest_position(spec)
		seg.rotation_degrees = SEGMENT_ROT
	for eye in _eyes:
		eye.scale = Vector3.ONE
	rotation.x = 0.0

func _apply_slither(_delta: float) -> void:
	if _segments.is_empty():
		return
	var wave := sin(_walk_phase * 5.5)
	for i in _segments.size():
		var seg := _segments[i]
		var spec: Dictionary = SEGMENT_SPECS[i]
		var phase := _walk_phase * 5.5 + float(i) * 0.85
		var wiggle := sin(phase)
		var ripple := cos(phase * 0.7)
		var rest := _segment_rest_position(spec)
		seg.position = Vector3(
			ripple * 0.02,
			rest.y + abs(wiggle) * 0.012,
			rest.z + wiggle * 0.035
		)
		seg.rotation_degrees = SEGMENT_ROT + Vector3(wiggle * 7.0, ripple * 5.0, 0)
	body_root.position.y = abs(sin(_walk_phase * 6.0)) * 0.01
	rotation.x = wave * 0.04

func _process(delta: float) -> void:
	if is_remote:
		_process_remote(delta)
		return

	if is_spawning:
		_spawn_t += delta
		var p := clampf(_spawn_t / 1.2, 0.0, 1.0)
		var emerge := clampf((p - 0.35) / 0.65, 0.0, 1.0)
		scale = Vector3.ONE * maxf(0.01, _body_scale * emerge)
		position.y = emerge * 0.1
		if body_root:
			body_root.position.y = sin(_spawn_t * 8.0) * 0.01 * emerge
		if p >= 1.0:
			is_spawning = false
			spawn_fx.visible = false
			position.y = 0.0
			_reset_body_pose()
			if _move_target.x >= 0:
				_replan_path()
		return

	if is_asleep:
		_breath_phase += delta
		var breath := sin(_breath_phase * 2.2) * 0.03
		scale = Vector3.ONE * _body_scale * (1.0 + breath)
		if body_root:
			body_root.rotation_degrees = Vector3(0, sin(_breath_phase * 1.4) * 3.0, 0)
		sleep_fx.visible = true
	else:
		sleep_fx.visible = false
		rotation.x = 0.0

	if is_moving:
		_advance_along_path(delta)
	else:
		_move_dir = Vector2.ZERO
		if not is_asleep:
			_reset_body_pose()

	_update_transform(false, delta)

func _update_transform(snap: bool, delta: float) -> void:
	if creature_id == "preview":
		return
	var wp := GameConfig.tile_to_world(grid_pos)
	position.x = wp.x
	position.z = wp.z
	if snap:
		position.y = 0.0
	if not is_asleep and is_moving and _move_dir.length_squared() > 0.0001:
		var target_rot := atan2(_move_dir.x, _move_dir.y)
		rotation.y = lerp_angle(rotation.y, target_rot, 0.18 if snap else delta * 14.0)

func set_move_target(target: Vector2) -> void:
	if is_asleep:
		return
	_move_target = target
	if is_player:
		GameState.note_player_input()
	if is_spawning:
		return
	_replan_path()

func _replan_path() -> void:
	if _move_target.x < 0:
		return
	_path = GridNav.find_path(
		grid_pos,
		_move_target,
		GameState.blocked_tiles,
		GameState.get_unit_tiles(creature_id)
	)
	if _path.is_empty():
		if _has_reached_target():
			_move_target = Vector2(-1, -1)
		is_moving = false
		return
	is_moving = true

func _advance_along_path(delta: float) -> void:
	if _path.is_empty():
		_finish_path()
		return

	var waypoint := _path[0]
	var to_waypoint := waypoint - grid_pos
	var dist := to_waypoint.length()
	var step := delta * GameConfig.MOVE_TILES_PER_SEC

	if dist <= 0.001:
		_path.remove_at(0)
		if _path.is_empty():
			_finish_path()
		return

	if step >= dist:
		grid_pos = waypoint
		_path.remove_at(0)
		_move_dir = to_waypoint / dist
		_walk_phase += delta * 12.0
		_apply_slither(delta)
		_sync_player_position(false)
		if _path.is_empty():
			_finish_path()
		return

	_move_dir = to_waypoint / dist
	grid_pos += _move_dir * step
	_walk_phase += delta * 12.0
	_apply_slither(delta)
	_sync_player_position(false)

func _sync_player_position(flush_now: bool) -> void:
	if not is_player or creature_id.is_empty():
		return
	NetworkService.save_creature_position(creature_id, grid_pos.x, grid_pos.y, flush_now)
	GameState.player_data["x"] = grid_pos.x
	GameState.player_data["y"] = grid_pos.y

func _finish_path() -> void:
	is_moving = false
	_reset_body_pose()
	_sync_player_position(true)
	if _has_reached_target():
		_move_target = Vector2(-1, -1)
	elif _move_target.x >= 0:
		_replan_path()

func _stop_movement() -> void:
	is_moving = false
	_path.clear()
	_reset_body_pose()

func _has_reached_target() -> bool:
	if _move_target.x < 0:
		return true
	return grid_pos.distance_to(_move_target) <= 0.35

func fall_asleep() -> void:
	if is_asleep:
		return
	is_asleep = true
	_stop_movement()
	_move_target = Vector2(-1, -1)

func wake_up() -> void:
	if not is_asleep:
		return
	is_asleep = false

func apply_network_patch(patch: Dictionary) -> void:
	if patch.has("x") and patch.has("y"):
		grid_pos = Vector2(float(patch.x), float(patch.y))
		_update_transform(true, 0.0)
	if patch.has("size_level"):
		size_level = int(patch.size_level)
		_apply_appearance()

func apply_remote_state(row: Dictionary) -> void:
	var target := Vector2(float(row.get("x", grid_pos.x)), float(row.get("y", grid_pos.y)))
	_remote_target = target
	var new_name := str(row.get("name", creature_name)).substr(0, GameConfig.NAME_MAX_LEN)
	if new_name != creature_name:
		creature_name = new_name
	var new_level := int(row.get("size_level", size_level))
	if new_level != size_level:
		size_level = new_level
		_apply_appearance()
	var new_color := GameConfig.color_from_hex(str(row.get("color", "")))
	if new_color != creature_color:
		creature_color = new_color
		_apply_appearance()

func _process_remote(delta: float) -> void:
	var to_target := _remote_target - grid_pos
	var dist := to_target.length()
	if dist > 0.02:
		var step := minf(dist, delta * GameConfig.MOVE_TILES_PER_SEC * 1.5)
		grid_pos += to_target / dist * step
		is_moving = true
		_move_dir = to_target / dist
		_walk_phase += delta * 10.0
		_apply_slither(delta)
	else:
		grid_pos = _remote_target
		is_moving = false
		_move_dir = Vector2.ZERO
		_reset_body_pose()
	_update_transform(false, delta)

func _exit_tree() -> void:
	if is_player and not creature_id.is_empty():
		NetworkService.save_creature_position(creature_id, grid_pos.x, grid_pos.y, true)
	if GameState.creatures.has(creature_id):
		GameState.unregister_creature(creature_id)
