class_name CreatureEyes
extends Node3D

@export var left_eye: Node3D
@export var right_eye: Node3D
@export var left_pupil: Node3D
@export var right_pupil: Node3D
@export var left_lid: MeshInstance3D
@export var right_lid: MeshInstance3D

var look := Vector2.ZERO
var blink := 0.0
var next_blink := 3.0
var idle_timer := 0.0
var idle_target := Vector2.ZERO
var screen_look_timer := 10.0
var sleep_phase := 0.0
var is_asleep := false
var move_dir := Vector2.ZERO
var is_player := false
var owner_creature: Creature = null

const PUPIL_MAX := 0.04

func _ready() -> void:
	if left_eye == null and has_node("LeftEye"):
		left_eye = get_node("LeftEye")
		right_eye = get_node("RightEye")
		left_pupil = get_node("LeftEye/Pupil")
		right_pupil = get_node("RightEye/Pupil")
		left_lid = get_node("LeftEye/Lid")
		right_lid = get_node("RightEye/Lid")

func setup(player: bool, owner: Creature) -> void:
	is_player = player
	owner_creature = owner

func set_asleep(asleep: bool) -> void:
	is_asleep = asleep
	if asleep:
		blink = 1.0

func set_move_dir(dir: Vector2) -> void:
	move_dir = dir

func update_eyes(delta: float, others: Array) -> void:
	if is_asleep:
		blink = 1.0
		sleep_phase += delta
		_update_lids()
		return

	next_blink -= delta
	if next_blink <= 0.0:
		blink = 1.0
		if next_blink <= -0.12:
			blink = 0.0
			next_blink = randf_range(2.0, 5.0)
	elif blink > 0.0 and next_blink > -0.12:
		blink = minf(1.0, blink + delta * 8.0)

	var target := Vector2.ZERO
	if move_dir.length_squared() > 0.01:
		target = move_dir.normalized()
	else:
		var nearest: Creature = null
		var nearest_d := 4.0
		if owner_creature:
			for o in others:
				if not o is Creature:
					continue
				var other: Creature = o
				if other == owner_creature or not is_instance_valid(other):
					continue
				var d: float = owner_creature.grid_pos.distance_to(other.grid_pos)
				if d < nearest_d:
					nearest_d = d
					nearest = other
		if nearest:
			var diff: Vector2 = nearest.grid_pos - owner_creature.grid_pos
			target = diff.normalized()
		else:
			idle_timer -= delta
			if idle_timer <= 0.0:
				idle_timer = randf_range(1.5, 3.5)
				idle_target = Vector2(randf_range(-1, 1), randf_range(-1, 1))
			target = idle_target
			if is_player:
				screen_look_timer -= delta
				if screen_look_timer <= 0.0:
					screen_look_timer = randf_range(10.0, 20.0)
					target = Vector2(0, -0.85)

	var smooth := 12.0 if move_dir.length_squared() > 0.01 else 4.0
	look = look.lerp(target, delta * smooth)
	_apply_pupils()
	_update_lids()

func _apply_pupils() -> void:
	if left_pupil:
		left_pupil.position.x = look.x * PUPIL_MAX
		left_pupil.position.y = look.y * PUPIL_MAX
	if right_pupil:
		right_pupil.position.x = look.x * PUPIL_MAX
		right_pupil.position.y = look.y * PUPIL_MAX

func _update_lids() -> void:
	var closed := is_asleep or blink >= 0.95
	var scale_y := 1.0 if not closed else 0.15
	if left_lid:
		left_lid.scale.y = scale_y
	if right_lid:
		right_lid.scale.y = scale_y

func get_sleep_phase() -> float:
	return sleep_phase
