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
var health := 100
var stamina := 10
var size_level := 1
var is_asleep := false
var is_player := false
var is_moving := false
var is_spawning := false

var _move_from := Vector2.ZERO
var _move_to := Vector2.ZERO
var _move_t := 0.0
var _move_dir := Vector2.ZERO
var _move_target: Vector2 = Vector2(-1, -1)
var _walk_phase := 0.0
var _spawn_t := 0.0
var _breath_phase := 0.0
var _body_scale := 1.0
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
	health = int(data.get("health", 100))
	stamina = int(data.get("stamina", 10))
	size_level = int(data.get("size_level", 1))
	is_player = data.get("is_player", false)
	is_asleep = data.get("is_asleep", false)
	_apply_appearance()
	_update_transform(true)
	_update_health_bar()
	health_bar.visible = false
	selection_ring.visible = is_player
	if is_player:
		is_spawning = true
		spawn_fx.visible = true
		_spawn_t = 0.0
		scale = Vector3(0.01, 0.01, 0.01)
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
		_move_t += delta * GameConfig.MOVE_TILES_PER_SEC
		var t := clampf(_move_t, 0.0, 1.0)
		var ease := t * t * (3.0 - 2.0 * t)
		grid_pos = _move_from.lerp(_move_to, ease)
		_walk_phase += delta * 12.0
		_move_dir = (_move_to - _move_from).normalized()
		_apply_slither(delta)
		if t >= 1.0:
			grid_pos = _move_to
			is_moving = false
			_reset_body_pose()
			spend_stamina(GameConfig.STAMINA_PER_TILE)
			if is_player:
				NetworkService.update_creature(creature_id, {"x": grid_pos.x, "y": grid_pos.y, "stamina": stamina})
	else:
		_move_dir = Vector2.ZERO
		if not is_asleep:
			_reset_body_pose()
		if not is_asleep and _move_target.x >= 0:
			_try_step_toward_target()

	_update_transform(false)

	if is_player and not is_moving:
		GameState.tick_player_stamina(delta, false)

func _update_transform(snap: bool) -> void:
	if creature_id == "preview":
		return
	var wp := GameConfig.tile_to_world(grid_pos)
	position.x = wp.x
	position.z = wp.z
	if snap:
		position.y = 0.0
	if not is_asleep and is_moving:
		rotation.y = atan2(_move_dir.x, _move_dir.y)

func set_move_target(target: Vector2) -> void:
	if is_asleep:
		return
	_move_target = target
	if is_player:
		GameState.note_player_input()
	if is_spawning:
		return

func _try_step_toward_target() -> void:
	if stamina < GameConfig.STAMINA_PER_TILE:
		_move_target = Vector2(-1, -1)
		return
	var my_id: String = creature_id
	var next := GridNav.step_toward(
		grid_pos, _move_target,
		GameState.blocked_tiles,
		GameState.get_unit_tiles(my_id)
	)
	if Vector2(next) == grid_pos.round():
		if Vector2i(int(round(grid_pos.x)), int(round(grid_pos.y))) == Vector2i(int(round(_move_target.x)), int(round(_move_target.y))):
			_move_target = Vector2(-1, -1)
		return
	_begin_move(Vector2(next))

func _begin_move(next: Vector2) -> void:
	if is_moving or is_asleep:
		return
	_move_from = grid_pos
	_move_to = next
	_move_t = 0.0
	is_moving = true

func set_stamina(value: int) -> void:
	stamina = clampi(value, 0, GameConfig.STAMINA_MAX)
	if is_player:
		GameState.player_stats_changed.emit()

func spend_stamina(amount: int) -> void:
	set_stamina(stamina - amount)

func take_damage(amount: int) -> void:
	health = maxi(0, health - amount)
	_update_health_bar()
	if health <= 0 and not is_player:
		var id: String = creature_id
		queue_free()
		GameState.unregister_creature(id)

func grow_from_eat() -> void:
	size_level += 1
	health = mini(100, health + 10)
	_apply_appearance()

func fall_asleep() -> void:
	if is_asleep:
		return
	is_asleep = true
	if size_level > 1:
		size_level -= 1
		_apply_appearance()
	if is_player:
		NetworkService.update_creature(creature_id, {"is_asleep": true, "size_level": size_level})

func wake_up() -> void:
	if not is_asleep:
		return
	is_asleep = false
	if is_player:
		NetworkService.update_creature(creature_id, {"is_asleep": false})

func apply_network_patch(patch: Dictionary) -> void:
	if patch.has("health"):
		health = int(patch.health)
	if patch.has("stamina"):
		stamina = int(patch.stamina)
	if patch.has("size_level"):
		size_level = int(patch.size_level)
		_apply_appearance()
	_update_health_bar()

func _update_health_bar() -> void:
	if not health_fill:
		return
	var ratio := float(health) / 100.0
	health_fill.scale.x = maxf(0.02, ratio)
	var mat := StandardMaterial3D.new()
	if ratio > 0.6:
		mat.albedo_color = Color(0.2, 0.9, 0.3)
	elif ratio > 0.3:
		mat.albedo_color = Color(0.95, 0.85, 0.2)
	else:
		mat.albedo_color = Color(0.95, 0.25, 0.2)
	health_fill.material_override = mat

func _exit_tree() -> void:
	if GameState.creatures.has(creature_id):
		GameState.unregister_creature(creature_id)
