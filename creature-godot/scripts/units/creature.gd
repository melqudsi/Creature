class_name Creature
extends Node3D

@onready var body_mesh: MeshInstance3D = $Body
@onready var fangs: Node3D = $Body/Fangs
@onready var eyes: CreatureEyes = $Eyes
@onready var selection_ring: MeshInstance3D = $SelectionRing
@onready var health_bar: Node3D = $HealthBar
@onready var health_fill: MeshInstance3D = $HealthBar/Fill
@onready var sleep_fx: Node3D = $SleepFX
@onready var spawn_fx: Node3D = $SpawnFX

var creature_id: String = ""
var creature_name: String = "Blob"
var creature_color: Color = Color.PINK
var appearance: String = "cute"
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

func _ready() -> void:
	selection_ring.visible = false
	if selection_ring:
		var rmat := StandardMaterial3D.new()
		rmat.albedo_color = Color(0.1, 1.0, 0.35, 0.85)
		rmat.emission_enabled = true
		rmat.emission = Color(0.1, 0.8, 0.3)
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		selection_ring.material_override = rmat
	sleep_fx.visible = false
	spawn_fx.visible = false
	if health_bar:
		health_bar.visible = not is_player
	if creature_id == "preview":
		selection_ring.visible = false
		if health_bar:
			health_bar.visible = false
		position = Vector3(0, 0.35, 0)

func setup(data: Dictionary) -> void:
	creature_id = data.get("id", str(get_instance_id()))
	set_meta("creature_id", creature_id)
	creature_name = str(data.get("name", "Blob")).substr(0, GameConfig.NAME_MAX_LEN)
	creature_color = data.get("color", Color.PINK)
	appearance = data.get("appearance", "cute")
	grid_pos = Vector2(data.get("x", 8.0), data.get("y", 6.0))
	health = int(data.get("health", 100))
	stamina = int(data.get("stamina", 10))
	size_level = int(data.get("size_level", 1))
	is_player = data.get("is_player", false)
	is_asleep = data.get("is_asleep", false)
	_apply_appearance()
	_update_transform(true)
	_update_health_bar()
	if eyes:
		eyes.setup(is_player, self)
		eyes.set_asleep(is_asleep)
	selection_ring.visible = is_player
	if is_player:
		is_spawning = true
		spawn_fx.visible = true
		_spawn_t = 0.0
		scale = Vector3(0.01, 0.01, 0.01)
	if creature_id != "preview" and creature_id != "portrait":
		GameState.register_creature(self, data, is_player)

func _apply_appearance() -> void:
	if not body_mesh:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = creature_color
	mat.roughness = 0.55
	mat.metallic = 0.15
	body_mesh.material_override = mat
	if fangs:
		fangs.visible = appearance == "ugly"
	if appearance == "cute":
		body_mesh.mesh = _make_cute_mesh()
	else:
		body_mesh.mesh = _make_ugly_mesh()
	var s := 0.55 + (size_level - 1) * 0.08
	scale = Vector3.ONE * s

func _make_cute_mesh() -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = 0.38
	m.height = 0.72
	return m

func _make_ugly_mesh() -> BoxMesh:
	var m := BoxMesh.new()
	m.size = Vector3(0.72, 0.55, 0.62)
	return m

func _process(delta: float) -> void:
	if is_spawning:
		_spawn_t += delta
		var p := clampf(_spawn_t / 1.2, 0.0, 1.0)
		var emerge := clampf((p - 0.35) / 0.65, 0.0, 1.0)
		var s := (0.55 + (size_level - 1) * 0.08) * emerge
		scale = Vector3.ONE * maxf(0.01, s)
		position.y = emerge * 0.15
		if p >= 1.0:
			is_spawning = false
			spawn_fx.visible = false
			position.y = 0.0
		return

	if is_asleep:
		_breath_phase += delta
		var breath := sin(_breath_phase * 2.2) * 0.06
		var base_s := 0.55 + (size_level - 1) * 0.08
		scale = Vector3.ONE * base_s * (1.0 + breath)
		rotation.z = sin(_breath_phase * 1.4) * 0.12
		sleep_fx.visible = true
	else:
		sleep_fx.visible = false
		rotation.z = 0.0

	if is_moving:
		_move_t += delta * GameConfig.MOVE_TILES_PER_SEC
		var t := clampf(_move_t, 0.0, 1.0)
		var ease := t * t * (3.0 - 2.0 * t)
		grid_pos = _move_from.lerp(_move_to, ease)
		_walk_phase += delta * 10.0
		_move_dir = (_move_to - _move_from).normalized()
		if t >= 1.0:
			grid_pos = _move_to
			is_moving = false
			spend_stamina(GameConfig.STAMINA_PER_TILE)
			if is_player:
				NetworkService.update_creature(creature_id, {"x": grid_pos.x, "y": grid_pos.y, "stamina": stamina})
	else:
		_move_dir = Vector2.ZERO
		if not is_asleep and _move_target.x >= 0:
			_try_step_toward_target()

	_update_transform(false)
	if eyes:
		eyes.set_move_dir(_move_dir)
		eyes.set_asleep(is_asleep)
		var others: Array = []
		for id in GameState.creatures:
			others.append(GameState.creatures[id])
		eyes.update_eyes(delta, others)

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
	if eyes:
		eyes.set_asleep(true)
	if is_player:
		NetworkService.update_creature(creature_id, {"is_asleep": true, "size_level": size_level})

func wake_up() -> void:
	if not is_asleep:
		return
	is_asleep = false
	if eyes:
		eyes.set_asleep(false)
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
