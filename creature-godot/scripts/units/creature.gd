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

## Shapeshift interaction tuning.
const INTERACT_RADIUS := 1.15   # how close to a world object to offer "Become"
const SHAPESHIFT_TIME := 1.0    # seconds to hold near an object to transform
const OBJECT_RESPAWN_DELAY := 3.0 # object reappears this long after you die as it
const EXPLOSION_RADIUS := 2.2
const ALTIMA_BURST_MULT := 2.2
const ALTIMA_BURST_TIME := 2.0
const ALTIMA_BURST_COOLDOWN := 6.0
## Vehicles drive noticeably faster on asphalt than cutting across grass.
const ROAD_SPEED_MULT := 1.35
## Movement easing: seconds-ish to reach full speed from a stop, and the
## distance (tiles) over which we brake into the final destination.
const MOVE_ACCEL_RATE := 3.0
const MOVE_DECEL_DIST := 0.28
## Remote position jumps larger than this (tiles) are treated as a teleport
## (death/respawn) and SNAP instead of interpolating, so other players don't see
## a dead player smoothly "walk" back to the dump.
const REMOTE_SNAP_TILES := 3.0
## Death flow: hold on the corpse for a beat, then a 3-2-1 countdown before the
## respawn teleport, so the player can actually see what killed them.
const RESPAWN_DEATH_PAUSE := 0.9
const RESPAWN_COUNTDOWN := 3
## How long a kill-feed broadcast row lives before the victim's client deletes it.
const KILL_FEED_TTL_SEC := 6.0
## Slice 7: how close (world units) to a carrying player to offer "Steal", and
## how long the respawn-choice buttons wait before defaulting to The Dump.
const STEAL_RADIUS := 1.3
const RESPAWN_CHOICE_TIMEOUT := 12.0

var creature_id: String = ""
var creature_name: String = "Creature"
var creature_color: Color = GameConfig.DEFAULT_CREATURE_COLOR
var appearance: String = "worm"
## Current shapeshift form (FormDefs key). "alien" is the default worm.
var form_key: String = FormDefs.ALIEN
var grid_pos := Vector2(8, 6)
var size_level := 1
var is_asleep := false
var is_player := false
var is_remote := false
var is_moving := false
var is_spawning := false
var is_dead := false

# Shapeshift state (player only).
var _active_object: WorldObject = null       # object currently "worn" as a form
var _nearby_object: WorldObject = null       # closest shapeshiftable object in range
var _shapeshift_candidate: WorldObject = null # object we're mid-transform into
var _nearby_npc: Dictionary = {}             # closest claimable (stopped) NPC vehicle
var _shapeshift_npc: Dictionary = {}         # NPC vehicle we're mid-transform into
var _shapeshifting := false
var _shapeshift_t := 0.0
var _last_prompt_can := false
var _last_prompt_name := ""
# Altima speed-burst special.
var _burst_t := 0.0
var _burst_cd := 0.0
# Pyramid abduction cooldown (Slice 6).
var _abduct_cd := 0.0
# Slice 7: respawn destination picked by the death-choice buttons ("" = waiting).
var _respawn_choice := ""
# BBQ Smoker (Slice 3): smoke-cloud cooldown + parked money-generation timer.
var _smoke_cd := 0.0
var _smoker_gen_t := 0.0
var _smoker_hint_shown := false

## Slice 2 money carrying (player-driven). Each entry is
## {"obj": WorldObject, "id": String, "tier": int}. Carried money is hidden as a
## ground prop and rendered as loot attached to this creature (`_carried_root`).
var _carried: Array[Dictionary] = []
var _carried_root: Node3D = null
## How close (world units) money must be to pick up / to auto-combine on drop.
const MONEY_PICKUP_RADIUS := 1.35
const MONEY_COMBINE_RADIUS := 1.5

var _move_dir := Vector2.ZERO
var _move_target: Vector2 = Vector2(-1, -1)
var _path: Array[Vector2] = []
## 0..1 ease factor: ramps up from a standstill and brakes near the destination.
var _speed_ease := 0.0
var _walk_phase := 0.0
var _spawn_t := 0.0
var _breath_phase := 0.0
var _idle_phase := 0.0
var _phase_offset := 0.0
var _remote_facing := 0.0
var _body_scale := 1.0
var _remote_target := Vector2.ZERO
var _segments: Array[MeshInstance3D] = []
var _eyes: Array[MeshInstance3D] = []

func _ready() -> void:
	_resolve_child_refs()
	_style_selection_ring()
	if sleep_fx:
		sleep_fx.visible = false
	if spawn_fx:
		spawn_fx.visible = false
	if health_bar:
		health_bar.visible = false

func _resolve_child_refs() -> void:
	body_root = get_node_or_null("Body") as Node3D
	selection_ring = get_node_or_null("SelectionRing") as MeshInstance3D
	health_bar = get_node_or_null("HealthBar") as Node3D
	health_fill = get_node_or_null("HealthBar/Fill") as MeshInstance3D
	sleep_fx = get_node_or_null("SleepFX") as Node3D
	spawn_fx = get_node_or_null("SpawnFX") as Node3D

func setup(data: Dictionary) -> void:
	_resolve_child_refs()
	creature_id = data.get("id", str(get_instance_id()))
	set_meta("creature_id", creature_id)
	creature_name = str(data.get("name", GameConfig.DEFAULT_CREATURE_NAME)).substr(0, GameConfig.NAME_MAX_LEN)
	creature_color = data.get("color", GameConfig.DEFAULT_CREATURE_COLOR)
	appearance = "worm"
	var incoming_form := str(data.get("form", FormDefs.ALIEN))
	form_key = incoming_form if FormDefs.is_valid(incoming_form) else FormDefs.ALIEN
	grid_pos = Vector2(data.get("x", 8.0), data.get("y", 6.0))
	size_level = int(data.get("size_level", 1))
	is_player = data.get("is_player", false)
	is_remote = data.get("is_remote", false)
	is_asleep = data.get("is_asleep", false)
	# Desync idle animations so multiple creatures don't breathe/sway in lockstep.
	_phase_offset = randf() * TAU
	apply_form(form_key)
	_update_transform(true, 0.0)
	if health_bar:
		health_bar.visible = false
	if selection_ring:
		selection_ring.visible = is_player
	if is_player:
		is_spawning = true
		if spawn_fx:
			spawn_fx.visible = true
		_spawn_t = 0.0
		scale = Vector3(0.01, 0.01, 0.01)
	elif is_remote:
		_remote_target = grid_pos
		scale = Vector3.ONE * _body_scale
		# Stable, per-creature randomized facing so idle remotes don't all
		# point the same way (kept fixed unless they actually walk).
		_remote_facing = _random_facing_for(str(data.get("user_id", creature_id)))
		rotation.y = _remote_facing
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

## Rebuild the visible body for the current form. Alien draws the procedural
## worm; every other form uses a shared ObjectMesh so it matches its world-object
## source. Safe to call at setup and whenever the form/color/size changes.
func apply_form(key: String) -> void:
	if not FormDefs.is_valid(key):
		key = FormDefs.ALIEN
	form_key = key
	if not body_root:
		_resolve_child_refs()
	if not body_root:
		return
	_clear_body_children()
	_segments.clear()
	_eyes.clear()
	_body_scale = 0.92 + (size_level - 1) * 0.08
	body_root.rotation_degrees = Vector3.ZERO
	body_root.position = Vector3.ZERO
	body_root.scale = Vector3.ONE * _form_body_scale()
	if FormDefs.is_alien(form_key):
		for spec in SEGMENT_SPECS:
			_segments.append(_add_segment(spec))
		_add_alien_eyes()
	else:
		body_root.add_child(ObjectMesh.build(FormDefs.visual(form_key), creature_color))
	_reset_body_pose()
	if is_player and creature_id != "preview" and creature_id != "portrait":
		GameState.form_changed.emit(form_key)
		if not creature_id.is_empty():
			NetworkService.save_creature_form(creature_id, form_key)
		GameState.player_data["form"] = form_key

func is_alien_form() -> bool:
	return FormDefs.is_alien(form_key)

## Server id of the shared object this player is currently wearing ("" if none).
## Used by the world-object sync as the LOCAL authority so a just-possessed /
## just-popped object doesn't flicker during the ~1.5s server round-trip.
func possessed_object_id() -> String:
	if _active_object and is_instance_valid(_active_object):
		return _active_object.object_id
	return ""

## Scale applied to body_root for the current form.
##
## The creature ROOT node is itself scaled by `_body_scale` (spawn anim / remote
## setup), so a mesh under body_root ends up at root*body scale. The alien worm
## was tuned for that doubled factor, but object forms share the SAME ObjectMesh
## as their world-object source (which renders at scale 1.0). To make a
## shapeshifted object match its Rusty Altima / tree / propane prop 1:1, we
## cancel the root scale on body_root for non-alien forms.
func _form_body_scale() -> float:
	if FormDefs.is_alien(form_key):
		return _body_scale
	return 1.0 / maxf(_body_scale, 0.01)

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
	body_root.scale = Vector3.ONE * _form_body_scale()
	for i in _segments.size():
		var seg := _segments[i]
		var spec: Dictionary = SEGMENT_SPECS[i]
		seg.position = _segment_rest_position(spec)
		seg.rotation_degrees = SEGMENT_ROT
	for eye in _eyes:
		eye.scale = Vector3.ONE
	rotation.x = 0.0

func _apply_slither(_delta: float) -> void:
	if not is_alien_form() or _segments.is_empty():
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

## Local/player idle: a gentle vertical "breathing" undulation. Slower and much
## lower amplitude than _apply_slither; never translates the creature itself.
func _apply_idle_local(delta: float) -> void:
	if not is_alien_form() or _segments.is_empty():
		return
	_idle_phase += delta
	var t := _idle_phase * 1.8 + _phase_offset
	for i in _segments.size():
		var seg := _segments[i]
		var spec: Dictionary = SEGMENT_SPECS[i]
		var phase := t + float(i) * 0.45
		var breath := sin(phase)
		var rest := _segment_rest_position(spec)
		seg.position = Vector3(rest.x, rest.y + breath * 0.006, rest.z)
		seg.rotation_degrees = SEGMENT_ROT + Vector3(breath * 2.0, 0.0, 0.0)
	body_root.position.y = (sin(t) * 0.5 + 0.5) * 0.008
	rotation.x = 0.0

## Remote/offline idle: a distinctly different lateral "sway" (side-to-side
## traveling wave + yaw) at a slower rhythm and larger amplitude than the local
## idle, so resting remote players read differently. Never touches rotation.y so
## the randomized facing from setup() is preserved.
func _apply_idle_remote(delta: float) -> void:
	if not is_alien_form() or _segments.is_empty():
		return
	_idle_phase += delta
	var t := _idle_phase * 1.1 + _phase_offset
	for i in _segments.size():
		var seg := _segments[i]
		var spec: Dictionary = SEGMENT_SPECS[i]
		var phase := t + float(i) * 0.9
		var sway := sin(phase)
		var rest := _segment_rest_position(spec)
		seg.position = Vector3(sway * 0.02, rest.y, rest.z)
		seg.rotation_degrees = SEGMENT_ROT + Vector3(0.0, sway * 6.0, 0.0)
	body_root.position.y = 0.0
	rotation.x = 0.0

## Deterministic facing derived from a per-creature key (user id) so it stays
## stable across frames/syncs while still varying between creatures.
func _random_facing_for(key: String) -> float:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	return rng.randf() * TAU

func _process(delta: float) -> void:
	if is_remote:
		_process_remote(delta)
		return

	# Dead players linger as a corpse through the respawn countdown — no input,
	# no movement, no interactions until _respawn_at* sets is_spawning.
	if is_dead:
		_stop_movement()
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

	if _burst_t > 0.0:
		_burst_t = maxf(0.0, _burst_t - delta)
	if _burst_cd > 0.0:
		_burst_cd = maxf(0.0, _burst_cd - delta)
	if _smoke_cd > 0.0:
		_smoke_cd = maxf(0.0, _smoke_cd - delta)
	if _abduct_cd > 0.0:
		_abduct_cd = maxf(0.0, _abduct_cd - delta)

	if is_moving:
		_advance_along_path(delta)
	else:
		_move_dir = Vector2.ZERO
		if not is_asleep:
			_apply_idle_local(delta)

	_update_transform(false, delta)

	if is_player and not is_asleep:
		_update_player_interactions(delta)

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
	if is_dead or is_spawning:
		return
	if is_asleep:
		return
	# The Pyramid does not move.
	if FormDefs.speed_mult(form_key) <= 0.0:
		if is_player:
			GameState.show_toast("The Pyramid does not move")
		return
	# A claimed safe house is rooted in place until its owner unclaims it.
	if form_key == FormDefs.HOUSE and _active_object and is_instance_valid(_active_object) \
			and not _active_object.safe_owner.is_empty():
		if is_player:
			GameState.show_toast("Safe house is rooted — unclaim it to move")
		return
	_move_target = target
	_path.clear()
	if is_moving:
		_speed_ease = maxf(_speed_ease, 0.92)
	if is_player:
		GameState.note_player_input()
		_update_local_player_data()
	_replan_path()

func _replan_path() -> void:
	if _move_target.x < 0:
		return
	# Vehicles (Altima) and the MATA Bus are reckless: they ignore other units in
	# pathfinding so they can ram aliens / drive into tree & pothole traps (kills
	# resolve via proximity). They still route around solid trees/buildings.
	var units: Dictionary = {} if FormDefs.ignores_units(form_key) else GameState.get_unit_tiles(creature_id)
	_path = GridNav.find_path(
		grid_pos,
		_move_target,
		GameState.blocked_tiles,
		units
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
	var step := delta * _current_speed() * _move_ease(delta)

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
		_update_local_player_data()
		if _path.is_empty():
			_finish_path()
		return

	_move_dir = to_waypoint / dist
	grid_pos += _move_dir * step
	_walk_phase += delta * 12.0
	_apply_slither(delta)
	_update_local_player_data()

func _update_local_player_data() -> void:
	if not is_player:
		return
	GameState.player_data["x"] = grid_pos.x
	GameState.player_data["y"] = grid_pos.y

func _sync_player_position(flush_now: bool) -> void:
	if not is_player or creature_id.is_empty():
		return
	_update_local_player_data()
	if flush_now:
		NetworkService.save_creature_position(creature_id, grid_pos.x, grid_pos.y, true)

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
	_speed_ease = 0.0
	_reset_body_pose()

## Tiny accel from a stop + decel into the final destination — pure feel, keeps
## taps from reading as instant velocity snaps.
func _move_ease(delta: float) -> float:
	_speed_ease = minf(1.0, _speed_ease + delta * MOVE_ACCEL_RATE)
	var ease_out := 1.0
	if not _path.is_empty():
		var remaining := grid_pos.distance_to(_path[_path.size() - 1])
		if remaining < MOVE_DECEL_DIST:
			ease_out = maxf(0.82, remaining / MOVE_DECEL_DIST)
	return minf(_speed_ease, ease_out)

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
		apply_form(form_key)

func apply_remote_state(row: Dictionary) -> void:
	var target := Vector2(float(row.get("x", grid_pos.x)), float(row.get("y", grid_pos.y)))
	# A big jump means this player teleported (respawned at the dump), not walked.
	# Snap immediately instead of lerping so remotes don't glide across the map.
	# Fast forms (Altima) legitimately cover more tiles per poll, so the snap
	# threshold scales with the form's speed — otherwise a driving Altima would
	# "teleport" every poll and never actually run anyone over.
	var snap_tiles := maxf(REMOTE_SNAP_TILES, FormDefs.speed_mult(form_key) * GameConfig.POLL_OTHERS_SEC * 1.6)
	if grid_pos.distance_to(target) > snap_tiles:
		grid_pos = target
		_remote_target = target
		is_moving = false
		_move_dir = Vector2.ZERO
		_update_transform(true, 0.0)
	_remote_target = target
	var new_name := str(row.get("name", creature_name)).substr(0, GameConfig.NAME_MAX_LEN)
	if new_name != creature_name:
		creature_name = new_name
	var needs_rebuild := false
	var new_level := int(row.get("size_level", size_level))
	if new_level != size_level:
		size_level = new_level
		needs_rebuild = true
	var new_color := GameConfig.color_from_hex(str(row.get("color", "")))
	if new_color != creature_color:
		creature_color = new_color
		needs_rebuild = true
	# Render the remote player in their current synced form (defaults to alien if
	# the "form" column doesn't exist yet — see NetworkService form handling).
	var new_form := str(row.get("form", FormDefs.ALIEN))
	if not FormDefs.is_valid(new_form):
		new_form = FormDefs.ALIEN
	if new_form != form_key:
		form_key = new_form
		needs_rebuild = true
	if needs_rebuild:
		apply_form(form_key)

func _process_remote(delta: float) -> void:
	var to_target := _remote_target - grid_pos
	var dist := to_target.length()
	if dist > 0.02:
		# Interpolate at least as fast as the remote's form actually moves, or a
		# fast Altima permanently lags its server position and can't hit anyone.
		var catch_up := maxf(1.5, FormDefs.speed_mult(form_key) * 1.6)
		var step := minf(dist, delta * GameConfig.MOVE_TILES_PER_SEC * catch_up)
		grid_pos += to_target / dist * step
		is_moving = true
		_move_dir = to_target / dist
		_walk_phase += delta * 10.0
		_apply_slither(delta)
	else:
		grid_pos = _remote_target
		is_moving = false
		_move_dir = Vector2.ZERO
		_apply_idle_remote(delta)
	_update_transform(false, delta)

# ---------------------------------------------------------------------------
# Forms: movement speed, collisions, shapeshifting, death (player-local).
# ---------------------------------------------------------------------------

func _current_speed() -> float:
	var mult := FormDefs.speed_mult(form_key)
	if _burst_t > 0.0:
		mult *= ALTIMA_BURST_MULT
	# Asphalt bonus: vehicles cruise faster when actually driving on a road.
	if FormDefs.is_vehicle(form_key) \
			and MemphisLayout.is_road(Vector2i(int(floor(grid_pos.x)), int(floor(grid_pos.y)))):
		mult *= ROAD_SPEED_MULT
	mult *= _carry_speed_factor()
	return GameConfig.MOVE_TILES_PER_SEC * mult

## Carrying money makes you "heavier and harder to move" — the heavier the loot
## (bag > stack, vault heaviest), the bigger the slowdown.
func _carry_speed_factor() -> float:
	if _carried.is_empty():
		return 1.0
	_prune_carried()
	var weight := 0.0
	for entry in _carried:
		weight += FormDefs.tier_weight(int(entry.get("tier", 0)))
	return clampf(1.0 / (1.0 + 0.35 * weight), 0.2, 1.0)

## Drop stale carried entries whose world object was freed (e.g. another client
## combined/deleted the shared row). Without this the phantom weight slows the
## player forever and the Drop button can't clear it.
func _prune_carried() -> void:
	var pruned := false
	for i in range(_carried.size() - 1, -1, -1):
		var obj: WorldObject = _carried[i].get("obj")
		if obj == null or not is_instance_valid(obj):
			_carried.remove_at(i)
			pruned = true
	if pruned:
		update_carried_display(carried_tiers())

func _world_xz() -> Vector2:
	return Vector2(position.x, position.z)

func _pyramid_claimed() -> bool:
	for c in GameState.creatures.values():
		if c != null and is_instance_valid(c) and not c.is_dead and c.form_key == FormDefs.PYRAMID:
			return true
	return false

## Per-frame player scan: find the nearest shapeshift target (for the "Become"
## prompt), advance an in-progress shapeshift, and resolve client-local kills.
func _update_player_interactions(delta: float) -> void:
	if is_spawning or is_dead:
		return
	_scan_shapeshift_target()
	_update_shapeshift_progress(delta)
	_resolve_contacts()
	_update_smoker_economy(delta)

func _scan_shapeshift_target() -> void:
	_nearby_object = null
	_nearby_npc = {}
	# Can only Become while an alien (pop out first to change form).
	if is_alien_form():
		var my := _world_xz()
		var best_d := INTERACT_RADIUS
		for obj in GameState.world_objects:
			if not is_instance_valid(obj) or obj.consumed or not obj.is_shapeshiftable():
				continue
			# Only one Pyramid pilot at a time.
			if obj.form_key == FormDefs.PYRAMID and _pyramid_claimed():
				continue
			# A claimed safe house belongs to its owner alone.
			if not obj.safe_owner.is_empty() and obj.safe_owner != creature_name:
				continue
			var d := my.distance_to(Vector2(obj.position.x, obj.position.z))
			if d <= best_d:
				best_d = d
				_nearby_object = obj
		# No prop in range? A stopped NPC vehicle (braking for us) is claimable.
		if _nearby_object == null:
			var traffic := GameState.npc_traffic
			if traffic != null and is_instance_valid(traffic):
				_nearby_npc = traffic.claimable_vehicle(my)
	var can := _nearby_object != null or not _nearby_npc.is_empty()
	var display := ""
	if _nearby_object != null:
		display = FormDefs.display(_nearby_object.form_key)
	elif not _nearby_npc.is_empty():
		display = GameState.npc_traffic.vehicle_display(_nearby_npc)
	if can != _last_prompt_can or display != _last_prompt_name:
		_last_prompt_can = can
		_last_prompt_name = display
		GameState.interaction_changed.emit(can, display)

func _update_shapeshift_progress(delta: float) -> void:
	if not _shapeshifting:
		return
	# Cancel if the target vanished, drove off, or we wandered out of range.
	if not _shapeshift_npc.is_empty():
		if _nearby_npc != _shapeshift_npc or not GameState.npc_traffic.is_vehicle_claimable(_shapeshift_npc):
			_shapeshifting = false
			_shapeshift_t = 0.0
			_shapeshift_npc = {}
			return
	elif not is_instance_valid(_shapeshift_candidate) or _shapeshift_candidate.consumed or _nearby_object != _shapeshift_candidate:
		_shapeshifting = false
		_shapeshift_t = 0.0
		return
	_shapeshift_t += delta
	if _shapeshift_t >= SHAPESHIFT_TIME:
		if not _shapeshift_npc.is_empty():
			_complete_npc_shapeshift()
		else:
			_complete_shapeshift()

## Called by the HUD "Become" button. Begins the ~1s hold-to-transform timer.
func begin_shapeshift() -> void:
	if not is_player or is_dead or not is_alien_form():
		return
	if _nearby_object != null and is_instance_valid(_nearby_object):
		_shapeshift_candidate = _nearby_object
		_shapeshift_npc = {}
	elif not _nearby_npc.is_empty():
		_shapeshift_candidate = null
		_shapeshift_npc = _nearby_npc
	else:
		return
	_shapeshifting = true
	_shapeshift_t = 0.0

func _complete_shapeshift() -> void:
	var obj := _shapeshift_candidate
	_shapeshifting = false
	_shapeshift_t = 0.0
	_shapeshift_candidate = null
	if obj == null or not is_instance_valid(obj) or obj.consumed:
		return
	_stop_movement()
	_move_target = Vector2(-1, -1)
	_active_object = obj
	obj.consume() # world object disappears while we wear its form
	# Mark the shared object as possessed by us so every client hides its
	# standalone prop (our synced form + position now represents it — no
	# duplicate). No-op for client-local fallback objects (empty object_id).
	if not obj.object_id.is_empty():
		NetworkService.possess_world_object(obj.object_id, NetworkService.get_user_id())
	elif obj.type_key == "tree_decor":
		# Scenery tree claim: it enters the shared object world (possessed by
		# us), and every client hides + unblocks the original scenery tree.
		_register_claimed_tree(obj)
	elif obj.type_key == "house_decor":
		# Scenery house claim: same pattern as trees (Slice 7).
		_register_claimed_house(obj)
	if obj.form_key == FormDefs.PYRAMID:
		# You ARE the Pyramid now. Stand exactly where it stands.
		position = obj.spawn_world_pos
		grid_pos = Vector2(GameConfig.world_to_tile(position))
	apply_form(obj.form_key)
	# Whatever the new form can't legally hold falls to the ground here.
	_revalidate_carried_for_form()
	if form_key == FormDefs.PYRAMID:
		GameState.show_toast("You became The Pyramid")
	else:
		GameState.show_toast("You became a %s" % FormDefs.display(form_key))

## A claimed scenery tree becomes a shared "tree" row (possessed by us) whose
## owner_name carries the home tile — other clients use it to hide + unblock
## the original scenery tree. From then on the tree lives as a normal shared
## object (walk it somewhere and pop out: it stays there for everyone).
func _register_claimed_tree(obj: WorldObject) -> void:
	var home := Vector2i(obj.spawn_tile)
	var wm := GameState.world_map
	if wm and is_instance_valid(wm) and wm.has_method("retire_scenery_tree"):
		wm.retire_scenery_tree(home)
	obj.type_key = "tree"
	if not NetworkService.is_online():
		return
	var created: Dictionary = await NetworkService.create_world_object({
		"type": "tree", "x": obj.spawn_tile.x, "y": obj.spawn_tile.y,
		"state": "possessed", "possessed_by": NetworkService.get_user_id(),
		"owner_name": "home:%d,%d" % [home.x, home.y],
	})
	var new_id := str(created.get("id", ""))
	if new_id.is_empty() or not is_instance_valid(obj):
		return
	obj.object_id = new_id
	if wm and is_instance_valid(wm) and wm.has_method("track_shared_object"):
		wm.track_shared_object(obj)
	# Popped out (or died) before the create landed? Release the row now.
	if _active_object != obj:
		var t := Vector2(GameConfig.world_to_tile(obj.position))
		NetworkService.release_world_object(new_id, t.x, t.y)

## A claimed scenery house becomes a shared "house" row (possessed by us) whose
## owner_name carries the home tile — other clients use it to hide + unblock
## the original scenery house. Walk it somewhere, pop out, and it stays there
## for everyone (see also the safe-house claim in _toggle_house_claim).
func _register_claimed_house(obj: WorldObject) -> void:
	var home := Vector2i(obj.spawn_tile)
	var wm := GameState.world_map
	if wm and is_instance_valid(wm) and wm.has_method("retire_scenery_house"):
		wm.retire_scenery_house(home)
	obj.type_key = "house"
	if not NetworkService.is_online():
		return
	var created: Dictionary = await NetworkService.create_world_object({
		"type": "house", "x": obj.spawn_tile.x, "y": obj.spawn_tile.y,
		"state": "possessed", "possessed_by": NetworkService.get_user_id(),
		"owner_name": "home:%d,%d" % [home.x, home.y],
	})
	var new_id := str(created.get("id", ""))
	if new_id.is_empty() or not is_instance_valid(obj):
		return
	obj.object_id = new_id
	obj.owner_name = "home:%d,%d" % [home.x, home.y]
	if wm and is_instance_valid(wm) and wm.has_method("track_shared_object"):
		wm.track_shared_object(obj)
	# Popped out (or died) before the create landed? Release the row now.
	if _active_object != obj:
		var t := Vector2(GameConfig.world_to_tile(obj.position))
		NetworkService.release_world_object(new_id, t.x, t.y)

## Claiming a stopped NPC vehicle: the local NPC despawns and a SHARED world
## object is born in its place, already possessed by us — so it persists (and
## is visible parked) for everyone once we pop out.
func _complete_npc_shapeshift() -> void:
	var v := _shapeshift_npc
	_shapeshifting = false
	_shapeshift_t = 0.0
	_shapeshift_npc = {}
	_shapeshift_candidate = null
	var traffic := GameState.npc_traffic
	if traffic == null or not is_instance_valid(traffic) or not traffic.is_vehicle_claimable(v):
		return
	_stop_movement()
	_move_target = Vector2(-1, -1)
	var is_bus: bool = v.get("is_bus", false)
	var vpos: Vector3 = traffic.vehicle_world_pos(v)
	var tile := Vector2(GameConfig.world_to_tile(vpos))
	traffic.claim_vehicle(v)
	var type_key := "bus" if is_bus else "altima"
	var wm := GameState.world_map
	var obj: WorldObject = null
	if wm and is_instance_valid(wm) and wm.has_method("materialize_claimed_vehicle"):
		obj = wm.materialize_claimed_vehicle(type_key, GameConfig.tile_to_world(tile))
	if obj == null:
		return
	obj.consume()
	_active_object = obj
	apply_form(obj.form_key)
	_revalidate_carried_for_form()
	GameState.show_toast("You became a %s" % FormDefs.display(form_key))
	# Register the new shared row in the background (snappy transform first).
	_register_claimed_vehicle(obj, type_key, tile)

func _register_claimed_vehicle(obj: WorldObject, type_key: String, tile: Vector2) -> void:
	if not NetworkService.is_online():
		return
	var created: Dictionary = await NetworkService.create_world_object({
		"type": type_key, "x": tile.x, "y": tile.y,
		"state": "possessed", "possessed_by": NetworkService.get_user_id(),
	})
	var new_id := str(created.get("id", ""))
	if new_id.is_empty() or not is_instance_valid(obj):
		return
	obj.object_id = new_id
	var wm := GameState.world_map
	if wm and is_instance_valid(wm) and wm.has_method("track_shared_object"):
		wm.track_shared_object(obj)
	# Popped out (or died) before the create landed? Release the row right away
	# so the server doesn't hold a phantom possession.
	if _active_object != obj:
		var t := Vector2(GameConfig.world_to_tile(obj.position))
		NetworkService.release_world_object(new_id, t.x, t.y)

## Re-link a shared object we already possess on the server (session restore:
## the player reloaded while shapeshifted, so the local _active_object reference
## was lost but the server row still says we're wearing it). Without this the
## player sees their own worn object duplicated at its old spot.
func adopt_possessed_object(obj: WorldObject) -> void:
	if not is_player or obj == null or not is_instance_valid(obj):
		return
	_active_object = obj
	obj.consume()

## Called by the HUD "Pop Out" button. Returns to alien; the worn object
## reappears next to us.
func pop_out() -> void:
	if not is_player or is_dead or is_alien_form():
		return
	_stop_movement()
	var was_pyramid := form_key == FormDefs.PYRAMID
	# A claimed safe house is rooted: like the Pyramid, it stays exactly where
	# it stands and the alien steps off beside it.
	var was_rooted := was_pyramid or (form_key == FormDefs.HOUSE \
		and _active_object and is_instance_valid(_active_object) \
		and not _active_object.safe_owner.is_empty())
	var drop_tile := GameConfig.safe_drop_tile(grid_pos + Vector2(0.9, 0.0))
	if _active_object and is_instance_valid(_active_object):
		if was_rooted:
			# Stays exactly where it stood; the alien steps off instead.
			_active_object.respawn_at(_active_object.spawn_world_pos)
			if not was_pyramid and not _active_object.object_id.is_empty():
				_note_local_authority(_active_object.object_id)
				NetworkService.release_world_object(_active_object.object_id,
					_active_object.spawn_tile.x, _active_object.spawn_tile.y)
		else:
			# Drop the object just beside us at our CURRENT location and leave it
			# there. In shared mode this writes the new position + idle state to
			# the server, so it persists for everyone (survives our disconnect).
			_active_object.respawn_at(GameConfig.tile_to_world(drop_tile))
			if not _active_object.object_id.is_empty():
				_note_local_authority(_active_object.object_id)
				NetworkService.release_world_object(_active_object.object_id, drop_tile.x, drop_tile.y)
	_active_object = null
	if was_rooted:
		# Step out of the rooted structure's tile onto open ground.
		var out_tile := GameState.free_drop_tile(grid_pos + Vector2(1.2, 0.6))
		position = GameConfig.tile_to_world(out_tile)
		grid_pos = out_tile
	# Carried loot stays with the vehicle we popped out of — the alien walks
	# away empty-handed (a cart's stacks stay AT the cart, not on the alien).
	if not _carried.is_empty():
		_drop_carried_entries(_carried.duplicate(), drop_tile)
		_carried.clear()
		update_carried_display([])
	apply_form(FormDefs.ALIEN)
	GameState.show_toast("Popped out to alien")

## Form specials: Altima speed burst; BBQ Smoker smoke cloud; Propane detonate.
func use_special() -> void:
	if not is_player or is_dead:
		return
	if form_key == FormDefs.ALTIMA and _burst_cd <= 0.0:
		_burst_t = ALTIMA_BURST_TIME
		_burst_cd = ALTIMA_BURST_COOLDOWN
		GameState.show_toast("Speed burst!")
	elif form_key == FormDefs.BBQ_SMOKER:
		if _smoke_cd > 0.0:
			GameState.show_toast("Smoker recharging (%ds)" % int(ceil(_smoke_cd)))
		else:
			_deploy_smoke_cloud()
	elif form_key == FormDefs.PROPANE:
		_detonate_propane()
	elif form_key == FormDefs.PYRAMID:
		if _abduct_cd > 0.0:
			GameState.show_toast("The Pyramid recharges (%ds)" % int(ceil(_abduct_cd)))
		else:
			_trigger_abduction()
	elif form_key == FormDefs.HOUSE:
		_toggle_house_claim()

const ABDUCTION_COOLDOWN_SEC := 45.0

## The Pyramid's alien-glyph special: beam to the sky, ship swoops in, and
## everything near the Pyramid (NPCs and players) gets abducted. Synced to all
## clients via a transient "abduction" world_objects row (smoke-cloud pattern).
func _trigger_abduction() -> void:
	_abduct_cd = ABDUCTION_COOLDOWN_SEC
	var tile := grid_pos
	var wm := GameState.world_map
	# Play the FX locally FIRST (instant feedback) — the shared row only exists
	# so other clients replay it, so it can trail behind.
	if wm and is_instance_valid(wm) and wm.has_method("register_abduction"):
		wm.register_abduction("", tile)
	if not NetworkService.is_online():
		return
	var created: Dictionary = await NetworkService.create_world_object({
		"type": "abduction", "x": tile.x, "y": tile.y,
		"state": "possessed", "possessed_by": NetworkService.get_user_id(),
	})
	var id := str(created.get("id", ""))
	if id.is_empty():
		return
	# We already played it — never replay our own row off the poll.
	if wm and is_instance_valid(wm) and wm.has_method("note_abduction_seen"):
		wm.note_abduction_seen(id)
	await get_tree().create_timer(10.0).timeout
	_note_deleted(id)
	NetworkService.delete_world_object(id)

# ---------------------------------------------------------------------------
# Safe houses (Slice 7).
# ---------------------------------------------------------------------------

## HUD label for the house special button (state-dependent claim toggle).
func house_special_label() -> String:
	if _active_object and is_instance_valid(_active_object) \
			and _active_object.safe_owner == creature_name:
		return "Unclaim Safe House"
	return "Claim Safe House"

## Toggle the worn house between free-roaming and claimed-personal-safe-house.
## Claimed = rooted in place, only the owner may wear it, and it becomes a
## respawn option on death. One safe house per player: claiming a new one
## releases the previous claim.
func _toggle_house_claim() -> void:
	var obj := _active_object
	if obj == null or not is_instance_valid(obj):
		return
	if obj.object_id.is_empty():
		GameState.show_toast("House still syncing — try again in a second")
		return
	var wm := GameState.world_map
	if obj.safe_owner == creature_name:
		# Unclaim: strip the safe segment, keep the home segment.
		obj.owner_name = WorldObject.parse_home_part(obj.owner_name)
		obj.set_safe_owner("")
		_note_local_authority(obj.object_id)
		NetworkService.update_world_object(obj.object_id,
			{"owner_name": obj.owner_name if not obj.owner_name.is_empty() else null})
		if wm and is_instance_valid(wm) and wm.has_method("note_safe_house"):
			wm.note_safe_house(creature_name, "", Vector2.ZERO)
		GameState.show_toast("Safe house unclaimed — it can move again")
		return
	if not obj.safe_owner.is_empty():
		GameState.show_toast("This is %s's safe house" % obj.safe_owner)
		return
	# Release any previous safe house (one per player).
	if wm and is_instance_valid(wm) and wm.has_method("safe_house_for"):
		var prev: Dictionary = wm.safe_house_for(creature_name)
		var prev_id := str(prev.get("id", ""))
		if not prev_id.is_empty() and prev_id != obj.object_id:
			var prev_home := WorldObject.parse_home_part(str(prev.get("raw", "")))
			NetworkService.update_world_object(prev_id,
				{"owner_name": prev_home if not prev_home.is_empty() else null})
	var parts: Array[String] = []
	var home_part := WorldObject.parse_home_part(obj.owner_name)
	if not home_part.is_empty():
		parts.append(home_part)
	parts.append("safe:%s" % creature_name)
	obj.owner_name = "|".join(parts)
	obj.set_safe_owner(creature_name)
	_stop_movement()
	_move_target = Vector2(-1, -1)
	_note_local_authority(obj.object_id)
	# Root the row at our CURRENT tile so respawns and other clients see the
	# claimed spot, not the stale pre-walk position.
	var here := Vector2(GameConfig.world_to_tile(position))
	obj.spawn_world_pos = GameConfig.tile_to_world(here)
	obj.spawn_tile = here
	NetworkService.update_world_object(obj.object_id,
		{"owner_name": obj.owner_name, "x": here.x, "y": here.y})
	if wm and is_instance_valid(wm) and wm.has_method("note_safe_house"):
		wm.note_safe_house(creature_name, obj.object_id, here, obj.owner_name)
	GameState.show_toast("Safe house claimed! It's rooted until you unclaim it")

## Manual propane detonation: the blast scatters/demotes nearby money and, per
## the design rule, the tank's pilot goes with it. The worn tank returns to its
## home spot via the normal death release.
func _detonate_propane() -> void:
	# Die FIRST (with the funnier self-detonation message), THEN blast: the death
	# drops any carried money at the spot and the blast then scatters it.
	apply_death(FormDefs.DEATH_SELF_DETONATE, true)
	GameState.explosion_requested.emit(position, EXPLOSION_RADIUS)

# ---------------------------------------------------------------------------
# BBQ Smoker (Slice 3): smoke cover + parked money generation.
# ---------------------------------------------------------------------------

## Drop a synced smoke cloud at our tile. Everyone sees it via a temporary
## world_objects row; we delete the row when the cloud ends (stale rows from a
## deployer who vanished get cleaned up by any client on poll).
func _deploy_smoke_cloud() -> void:
	_smoke_cd = GameConfig.SMOKE_CLOUD_COOLDOWN_SEC
	var tile := grid_pos
	var wpos := GameConfig.tile_to_world(tile)
	GameState.show_toast("Smoke cloud!")
	var wm := GameState.world_map
	var id := ""
	if NetworkService.is_online():
		var created: Dictionary = await NetworkService.create_world_object(
			{"type": "smoke_cloud", "x": tile.x, "y": tile.y, "state": "idle"})
		id = str(created.get("id", ""))
	if wm and is_instance_valid(wm) and wm.has_method("register_smoke_cloud"):
		wm.register_smoke_cloud(id, wpos, GameConfig.SMOKE_CLOUD_DURATION_SEC)
	if not id.is_empty():
		await get_tree().create_timer(GameConfig.SMOKE_CLOUD_DURATION_SEC).timeout
		_note_deleted(id)
		NetworkService.delete_world_object(id)

## The smoker only earns while PARKED NEAR HOUSES — an active, defendable spot
## (BBQ Corner is built for it), not a passive money faucet. A world-wide cap on
## loose stacks keeps the map from flooding.
func _update_smoker_economy(delta: float) -> void:
	if form_key != FormDefs.BBQ_SMOKER:
		_smoker_gen_t = 0.0
		_smoker_hint_shown = false
		return
	if is_moving or is_asleep:
		_smoker_gen_t = 0.0
		return
	if not GameConfig.is_near_building(grid_pos, GameConfig.SMOKER_NEAR_HOUSE_TILES):
		_smoker_gen_t = 0.0
		if not _smoker_hint_shown:
			_smoker_hint_shown = true
			GameState.show_toast("Park near houses to sell BBQ")
		return
	_smoker_gen_t += delta
	if _smoker_gen_t < GameConfig.SMOKER_GEN_INTERVAL_SEC:
		return
	_smoker_gen_t = 0.0
	if _count_world_stacks() >= GameConfig.MONEY_STACK_WORLD_CAP:
		GameState.show_toast("Market's flooded — combine some money first")
		return
	_generate_money_stack()

## Every money-stack object in the local world (idle AND carried both count
## toward the economy cap).
func _count_world_stacks() -> int:
	var n := 0
	for obj in GameState.world_objects:
		if is_instance_valid(obj) and obj.tier == FormDefs.TIER_STACK:
			n += 1
	return n

## Spawn a fresh stack on a tile right beside the smoker (synced when online).
func _generate_money_stack() -> void:
	var offs: Array[Vector2] = [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1), Vector2(1, 1), Vector2(-1, 1)]
	var tile: Vector2 = GameState.free_drop_tile(grid_pos + offs[randi() % offs.size()])
	GameState.show_toast("BBQ sold — fresh money stack!")
	var new_id := ""
	if NetworkService.is_online():
		var created := await NetworkService.create_world_object(
			{"type": "money_stack", "x": tile.x, "y": tile.y, "state": "idle"})
		new_id = str(created.get("id", ""))
	var wm := GameState.world_map
	if wm and is_instance_valid(wm) and wm.has_method("spawn_money_object"):
		wm.spawn_money_object("money_stack", GameConfig.tile_to_world(tile), "", new_id)

# ---------------------------------------------------------------------------
# Money: pick up / carry / drop / combine / ownership (Slice 2, player-local).
# ---------------------------------------------------------------------------

## Tell the world map our local change to this object is authoritative for a few
## seconds (ignore stale poll rows while the PATCH is in flight — anti-flicker).
func _note_local_authority(object_id: String) -> void:
	var wm := GameState.world_map
	if wm and is_instance_valid(wm) and wm.has_method("note_local_authority"):
		wm.note_local_authority(object_id)

func _note_deleted(object_id: String) -> void:
	var wm := GameState.world_map
	if wm and is_instance_valid(wm) and wm.has_method("note_deleted"):
		wm.note_deleted(object_id)

## Ids of the money objects this player is currently carrying (world-object sync
## uses this as the LOCAL authority so carried props don't flicker on the poll).
func carried_object_ids() -> Array:
	var ids: Array = []
	for entry in _carried:
		var id := str(entry.get("id", ""))
		if not id.is_empty():
			ids.append(id)
	return ids

func carried_tiers() -> Array:
	var tiers: Array = []
	for entry in _carried:
		tiers.append(int(entry.get("tier", 0)))
	return tiers

func is_carrying() -> bool:
	return not _carried.is_empty()

## True if there is an eligible money object nearby we're allowed to pick up right
## now (drives the HUD "Pick Up" button visibility).
func can_pick_up_now() -> bool:
	return _nearest_pickup() != null

## HUD Pick Up button label — names what's about to be grabbed ("Pick Up Money Bag").
func pickup_label() -> String:
	var obj := _nearest_pickup()
	if obj == null:
		return "Pick Up"
	return "Pick Up %s" % FormDefs.tier_display(obj.tier)

## HUD Drop button label — says "Combine" when the drop is going to merge with a
## same-tier money object (either one on the ground nearby, or a second one we're
## carrying), so the player knows what's about to happen.
func drop_label() -> String:
	if _carried.is_empty():
		return "Drop"
	var counts: Dictionary = {}
	for entry in _carried:
		var t := int(entry.get("tier", 0))
		if t < FormDefs.TIER_STACK or t >= FormDefs.TIER_VAULT:
			continue
		counts[t] = int(counts.get(t, 0)) + 1
		if int(counts[t]) >= 2: # two carried same-tier items merge on drop
			return "Combine → %s" % FormDefs.tier_display(t + 1)
	var my := _world_xz()
	for obj in GameState.world_objects:
		if not is_instance_valid(obj) or obj.consumed or not obj.is_money():
			continue
		if not counts.has(obj.tier):
			continue
		if my.distance_to(Vector2(obj.position.x, obj.position.z)) <= MONEY_COMBINE_RADIUS:
			return "Combine → %s" % FormDefs.tier_display(obj.tier + 1)
	return "Drop"

## Nearest idle money object within reach that this form may carry given its
## current load. Returns null if none is eligible.
func _nearest_pickup() -> WorldObject:
	if not is_player or is_dead or is_spawning:
		return null
	var my := _world_xz()
	var best: WorldObject = null
	var best_d := MONEY_PICKUP_RADIUS
	var tiers := carried_tiers()
	for obj in GameState.world_objects:
		if not is_instance_valid(obj) or obj.consumed or not obj.is_money():
			continue
		if not FormDefs.carry_check(form_key, tiers, obj.tier).ok:
			continue
		var d := my.distance_to(Vector2(obj.position.x, obj.position.z))
		if d <= best_d:
			best_d = d
			best = obj
	return best

## Nearest money object of ANY tier within reach (used to explain why a pickup was
## refused, e.g. "Alien can't carry a vault").
func _nearest_money_any() -> WorldObject:
	var my := _world_xz()
	var best: WorldObject = null
	var best_d := MONEY_PICKUP_RADIUS
	for obj in GameState.world_objects:
		if not is_instance_valid(obj) or obj.consumed or not obj.is_money():
			continue
		var d := my.distance_to(Vector2(obj.position.x, obj.position.z))
		if d <= best_d:
			best_d = d
			best = obj
	return best

## HUD "Pick Up" button: grab the nearest eligible money object.
func pick_up_nearest() -> void:
	if not is_player or is_dead or is_spawning or is_asleep:
		return
	var obj := _nearest_pickup()
	if obj == null:
		var near := _nearest_money_any()
		if near and is_instance_valid(near):
			GameState.show_toast(FormDefs.carry_check(form_key, carried_tiers(), near.tier).reason)
		else:
			GameState.show_toast("No money in reach")
		return
	# Slice 7: grabbing another player's labeled bag/vault re-brands it to the
	# taker on the spot — and everyone hears about it.
	var prev_owner := obj.owner_name
	var switched := obj.tier >= FormDefs.TIER_BAG and not prev_owner.is_empty() \
		and prev_owner != creature_name and not creature_name.is_empty()
	if switched:
		obj.set_money_owner(creature_name)
	_carried.append({"obj": obj, "id": obj.object_id, "tier": obj.tier})
	obj.carried_by = NetworkService.get_user_id()
	obj.consume() # hidden as a ground prop; now drawn as attached loot
	if not obj.object_id.is_empty():
		_note_local_authority(obj.object_id)
		NetworkService.carry_world_object(obj.object_id, NetworkService.get_user_id(),
			creature_name if switched else "")
	update_carried_display(carried_tiers())
	if switched:
		GameState.show_toast("Took %s's %s — it's yours now" % [prev_owner, FormDefs.tier_display(obj.tier)])
		_broadcast_toast_event("%s snatched %s's %s!" % [creature_name, prev_owner, FormDefs.tier_display(obj.tier)])
	else:
		GameState.show_toast("Picked up a %s" % FormDefs.tier_display(obj.tier))

# ---------------------------------------------------------------------------
# Stealing from carrying players (Slice 7).
# ---------------------------------------------------------------------------

## Nearest remote player in reach hauling something this form can take:
## {"uid", "name", "rows"} or {}.
func _steal_target() -> Dictionary:
	if not is_player or is_dead or is_spawning:
		return {}
	var wm := GameState.world_map
	if wm == null or not is_instance_valid(wm) or not wm.has_method("nearest_carrier"):
		return {}
	return wm.nearest_carrier(_world_xz(), STEAL_RADIUS)

## Highest-tier row of theirs that our form's carry rules allow right now.
func _stealable_row(rows: Array) -> Dictionary:
	var best: Dictionary = {}
	for r in rows:
		var t := int(r.get("tier", 0))
		if not FormDefs.carry_check(form_key, carried_tiers(), t).ok:
			continue
		if best.is_empty() or t > int(best.get("tier", 0)):
			best = r
	return best

func can_steal_now() -> bool:
	var target := _steal_target()
	return not target.is_empty() and not _stealable_row(target.get("rows", [])).is_empty()

func steal_label() -> String:
	var target := _steal_target()
	if target.is_empty():
		return "Steal"
	var row := _stealable_row(target.get("rows", []))
	if row.is_empty():
		return "Steal"
	return "Steal %s" % FormDefs.tier_display(int(row.get("tier", 0)))

## HUD "Steal" button: yank the best carriable money row off the nearest
## carrying player. Ownership switches to us; everyone gets the toast.
func steal_from_nearest() -> void:
	if not is_player or is_dead or is_spawning or is_asleep:
		return
	var target := _steal_target()
	if target.is_empty():
		return
	var row := _stealable_row(target.get("rows", []))
	if row.is_empty():
		GameState.show_toast("Can't carry anything they're holding")
		return
	var id := str(row.get("id", ""))
	var tier := int(row.get("tier", 0))
	var victim := str(target.get("name", "Someone"))
	var wm := GameState.world_map
	var obj: WorldObject = wm.claim_carried_object(id, str(row.get("type", "money_stack")), position)
	obj.carried_by = NetworkService.get_user_id()
	var switched := tier >= FormDefs.TIER_BAG
	if switched:
		obj.set_money_owner(creature_name)
	_carried.append({"obj": obj, "id": id, "tier": tier})
	_note_local_authority(id)
	NetworkService.carry_world_object(id, NetworkService.get_user_id(),
		creature_name if switched else "")
	update_carried_display(carried_tiers())
	GameState.show_toast("Stole %s's %s!" % [victim, FormDefs.tier_display(tier)])
	_broadcast_toast_event("%s stole %s's %s!" % [creature_name, victim, FormDefs.tier_display(tier)])

## The world sync detected that another player's carry PATCH took one of OUR
## carried rows (they stole it): let go locally and break the news.
func on_money_stolen(object_id: String, thief_name: String) -> void:
	for i in _carried.size():
		if str(_carried[i].get("id", "")) != object_id:
			continue
		var tier := int(_carried[i].get("tier", 0))
		_carried.remove_at(i)
		update_carried_display(carried_tiers())
		GameState.show_toast("%s stole your %s!" % [thief_name, FormDefs.tier_display(tier)])
		return

## HUD "Drop" button: set every carried money object down at our current tile,
## claim ownership if we hauled someone's bag/vault into a claim zone, then try to
## combine matching tiers that land close together.
func drop_all() -> void:
	if _carried.is_empty():
		return
	var base_tile := grid_pos
	var in_claim_zone := GameConfig.is_in_landfill(base_tile)
	var dropped: Array[WorldObject] = []
	var i := 0
	for entry in _carried:
		var obj: WorldObject = entry.get("obj")
		if obj == null or not is_instance_valid(obj):
			i += 1
			continue
		var drop_tile := GameState.free_drop_tile(base_tile + _drop_offset(i))
		i += 1
		var wp := GameConfig.tile_to_world(drop_tile)
		# Claim: hauling a bag/vault you don't own into the landfill steals it.
		var new_owner := ""
		if obj.tier >= FormDefs.TIER_BAG and in_claim_zone and obj.owner_name != creature_name and not creature_name.is_empty():
			new_owner = creature_name
			GameState.show_toast("Claimed the %s!" % FormDefs.tier_display(obj.tier))
		obj.carried_by = ""
		if not new_owner.is_empty():
			obj.set_money_owner(new_owner)
		obj.respawn_at(wp)
		obj.spawn_world_pos = wp
		obj.spawn_tile = drop_tile
		if not obj.object_id.is_empty():
			_note_local_authority(obj.object_id)
			# Preserve the existing owner label when we aren't claiming.
			NetworkService.drop_money_object(obj.object_id, drop_tile.x, drop_tile.y, obj.owner_name)
		dropped.append(obj)
	_carried.clear()
	update_carried_display([])
	_run_combines(dropped)

## Small fan-out so multiple dropped items don't stack on the exact same spot.
func _drop_offset(index: int) -> Vector2:
	var ring := [Vector2(0, 0), Vector2(0.7, 0), Vector2(-0.7, 0), Vector2(0, 0.7), Vector2(0, -0.7)]
	return ring[index % ring.size()]

## Place a list of carried entries on the ground around `base_tile` as idle world
## objects (owner labels preserved; no claim, no combine). Shared helper for
## pop-out / form-change overflow drops.
func _drop_carried_entries(entries: Array, base_tile: Vector2) -> void:
	var i := 0
	for entry in entries:
		var obj: WorldObject = entry.get("obj")
		if obj == null or not is_instance_valid(obj):
			i += 1
			continue
		var drop_tile := GameState.free_drop_tile(base_tile + _drop_offset(i))
		i += 1
		var wp := GameConfig.tile_to_world(drop_tile)
		obj.carried_by = ""
		obj.respawn_at(wp)
		obj.spawn_world_pos = wp
		obj.spawn_tile = drop_tile
		if not obj.object_id.is_empty():
			_note_local_authority(obj.object_id)
			NetworkService.drop_money_object(obj.object_id, drop_tile.x, drop_tile.y, obj.owner_name)

## After a form change, re-check every carried item against the new form's carry
## rules (incrementally); anything that no longer fits drops at our feet.
func _revalidate_carried_for_form() -> void:
	if _carried.is_empty():
		return
	var kept: Array[Dictionary] = []
	var kept_tiers: Array = []
	var overflow: Array = []
	for entry in _carried:
		var t := int(entry.get("tier", 0))
		if FormDefs.carry_check(form_key, kept_tiers, t).ok:
			kept.append(entry)
			kept_tiers.append(t)
		else:
			overflow.append(entry)
	if overflow.is_empty():
		return
	_drop_carried_entries(overflow, grid_pos)
	_carried = kept
	update_carried_display(carried_tiers())
	GameState.show_toast("Dropped loot this form can't carry")

## After a drop, repeatedly merge any two same-tier idle money objects that ended
## up close together (Stack+Stack=Bag, Bag+Bag=Vault). Client-local authority.
func _run_combines(dropped: Array) -> void:
	var guard := 0
	while guard < 12:
		guard += 1
		var pair := _find_combine_pair()
		if pair.is_empty():
			return
		await _combine_pair(pair[0], pair[1])

## Find two combinable idle money objects (same tier < Vault) within range of each
## other. Returns [a, b] or [].
func _find_combine_pair() -> Array:
	var money: Array = []
	for obj in GameState.world_objects:
		if not is_instance_valid(obj) or obj.consumed or not obj.is_money():
			continue
		if obj.tier < FormDefs.TIER_STACK or obj.tier >= FormDefs.TIER_VAULT:
			continue
		money.append(obj)
	for a in money.size():
		for b in range(a + 1, money.size()):
			var oa: WorldObject = money[a]
			var ob: WorldObject = money[b]
			if oa.tier != ob.tier:
				continue
			if oa.position.distance_to(ob.position) <= MONEY_COMBINE_RADIUS:
				return [oa, ob]
	return []

## Merge two money objects into one of the next tier at their midpoint, stamped
## with this player's ownership. The two sources are removed and the higher-tier
## object is created (synced when online, local otherwise).
func _combine_pair(a: WorldObject, b: WorldObject) -> void:
	if a == null or b == null or not is_instance_valid(a) or not is_instance_valid(b):
		return
	var new_tier: int = a.tier + 1
	var mid_world: Vector3 = (a.position + b.position) * 0.5
	var mid_tile := GameState.free_drop_tile(Vector2(GameConfig.world_to_tile(mid_world)))
	mid_world = GameConfig.tile_to_world(mid_tile)
	var type_key := _money_type_key(new_tier)
	var owner := creature_name
	_remove_money_object(a)
	_remove_money_object(b)
	GameState.money_combined.emit(mid_world)
	GameState.show_toast("Combined into a %s" % FormDefs.tier_display(new_tier))
	var new_id := ""
	if NetworkService.is_online():
		var fields := {"type": type_key, "x": mid_tile.x, "y": mid_tile.y, "state": "idle"}
		if new_tier >= FormDefs.TIER_BAG:
			fields["owner_name"] = owner
		var created := await NetworkService.create_world_object(fields)
		new_id = str(created.get("id", ""))
	# Spawn locally right away for snappy feedback (matched by id on the next poll).
	if GameState.world_map and is_instance_valid(GameState.world_map) and GameState.world_map.has_method("spawn_money_object"):
		GameState.world_map.spawn_money_object(type_key, mid_world, owner, new_id)

func _money_type_key(tier: int) -> String:
	match tier:
		FormDefs.TIER_BAG: return "money_bag"
		FormDefs.TIER_VAULT: return "vault"
		_: return "money_stack"

func _money_visual_for_tier(tier: int) -> String:
	match tier:
		FormDefs.TIER_BAG: return "money_bag"
		FormDefs.TIER_VAULT: return "vault"
		_: return "money_stack"

## Remove a money object from the world (delete its shared row + free the node).
func _remove_money_object(obj: WorldObject) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	# Mark consumed immediately so it's excluded from any further combine scan
	# during the async create round-trip (queue_free only frees next idle frame).
	obj.consume()
	if not obj.object_id.is_empty():
		# Tombstone BEFORE the async DELETE: a poll arriving mid-flight must not
		# resurrect the row (that's how one combine yielded two bags).
		_note_deleted(obj.object_id)
		NetworkService.delete_world_object(obj.object_id)
	obj.queue_free()

## Rebuild the stack of loot floating above this creature from a list of tiers.
## Used by the local player (own carry) and by world_map for visible remotes.
func update_carried_display(tiers: Array) -> void:
	if _carried_root and is_instance_valid(_carried_root):
		_carried_root.queue_free()
		_carried_root = null
	if tiers.is_empty():
		return
	_carried_root = Node3D.new()
	_carried_root.name = "CarriedLoot"
	add_child(_carried_root)
	# Carried loot renders at full world size (it used to shrink to half size,
	# which made a hauled vault look like pocket change).
	var y := 0.9
	for tier in tiers:
		var node := ObjectMesh.build(_money_visual_for_tier(int(tier)))
		node.position = Vector3(0, y, 0)
		_carried_root.add_child(node)
		y += 0.7

## Drop every carried money object at the death location as idle world objects
## (ownership preserved — killers/others can then grab it). No combine on death.
func _drop_carried_on_death() -> void:
	if _carried.is_empty():
		update_carried_display([])
		return
	var i := 0
	for entry in _carried:
		var obj: WorldObject = entry.get("obj")
		if obj == null or not is_instance_valid(obj):
			i += 1
			continue
		var drop_tile := GameState.free_drop_tile(grid_pos + _drop_offset(i))
		i += 1
		var wp := GameConfig.tile_to_world(drop_tile)
		obj.carried_by = ""
		obj.respawn_at(wp)
		obj.spawn_world_pos = wp
		obj.spawn_tile = drop_tile
		if not obj.object_id.is_empty():
			_note_local_authority(obj.object_id)
			# Keep the previous owner label — dying doesn't launder stolen money.
			NetworkService.drop_money_object(obj.object_id, drop_tile.x, drop_tile.y, obj.owner_name)
	_carried.clear()
	update_carried_display([])

## Resolve client-local kills against world objects and remote creatures. We
## only ever decide whether OUR OWN player dies (see NETWORKING notes): remote
## players resolve their own deaths on their own client.
func _resolve_contacts() -> void:
	var my := _world_xz()
	var my_r := FormDefs.radius(form_key)
	# World objects (trees, potholes, propane, buildings...).
	for obj in GameState.world_objects:
		if not is_instance_valid(obj) or obj.consumed:
			continue
		var d := my.distance_to(Vector2(obj.position.x, obj.position.z))
		if d > my_r + obj.radius:
			continue
		var res := FormDefs.resolve_player_death(form_key, obj.kind)
		if res.die:
			if res.explode:
				GameState.explosion_requested.emit(obj.position, EXPLOSION_RADIUS)
				# The propane tank is consumed by the blast and respawns later
				# (shared objects reappear from the next poll; local ones on timer).
				obj.consume()
				if obj.object_id.is_empty():
					_schedule_object_respawn(obj, obj.spawn_world_pos)
			apply_death(res.reason, res.explode)
			return
	# Remote creatures (their form is synced; a remote Altima can squish us).
	for id in GameState.creatures:
		var c: Creature = GameState.creatures[id]
		if c == self or not is_instance_valid(c):
			continue
		var d := my.distance_to(Vector2(c.position.x, c.position.z))
		if d > my_r + FormDefs.radius(c.form_key):
			continue
		var other_kind := FormDefs.kind(c.form_key)
		# A stopped vehicle is harmless: walking up to a parked Altima/bus is
		# safe; you only die if it actually runs you over (it's moving).
		if (other_kind == "vehicle" or other_kind == "mata_bus") and not c.is_moving:
			continue
		var res := FormDefs.resolve_player_death(form_key, other_kind)
		if res.die:
			if res.explode:
				GameState.explosion_requested.emit(position, EXPLOSION_RADIUS)
			# A remote player did this — credit them in the kill feed.
			apply_death(res.reason, res.explode, c.creature_name)
			return

## Called by the world when an explosion goes off. Applies its lethal radius to
## THIS player only (client-local); aliens and vehicles nearby die.
func apply_explosion(world_pos: Vector3, radius: float) -> void:
	if not is_player or is_dead or is_spawning:
		return
	if not FormDefs.explosion_kills(form_key):
		return
	var d := _world_xz().distance_to(Vector2(world_pos.x, world_pos.z))
	if d <= radius:
		apply_death(FormDefs.DEATH_PROPANE, true)

## Death + respawn as alien at the landfill. Kills are non-punishing.
## The corpse lingers at the death spot through a short pause + 3-2-1 countdown
## (with the camera zoomed in) so the player actually sees what happened.
## `killer_name` (when known, i.e. a remote player did it) feeds the kill feed.
func apply_death(reason: String, exploded: bool = false, killer_name: String = "") -> void:
	if is_dead:
		return
	var died_form := form_key
	var died_as_vehicle := FormDefs.is_vehicle(died_form)
	is_dead = true
	# A squished alien (or cart rider) leaves a blood splat where it happened.
	# Explosions have their own FX; potholes/trees "wreck", they don't squish.
	var my_kind := FormDefs.kind(died_form)
	if not exploded and (my_kind == "alien" or my_kind == "cart"):
		GameState.blood_splat_requested.emit(position)
	# Drop any carried money at the death location as idle world objects (synced),
	# so killers/other players can grab it — central to the revenge/steal loop.
	_drop_carried_on_death()
	if not reason.is_empty():
		GameState.show_toast(reason)
	GameState.add_admin_log("Player died: %s (form %s)" % [reason, form_key])
	_broadcast_kill_feed(reason, killer_name)

	# If we died while shapeshifted, the worn object returns to its home spot.
	# Shared objects release on the server (visible to everyone); client-local
	# fallback objects use the old delayed local respawn.
	if _active_object and is_instance_valid(_active_object):
		if not _active_object.object_id.is_empty():
			NetworkService.release_world_object(
				_active_object.object_id, _active_object.spawn_tile.x, _active_object.spawn_tile.y)
			_active_object.respawn_at(_active_object.spawn_world_pos)
		else:
			_schedule_object_respawn(_active_object, _active_object.spawn_world_pos)
	_active_object = null
	_shapeshifting = false
	_shapeshift_candidate = null
	_burst_t = 0.0

	# Pop back to alien immediately (wreck/corpse reads as the alien form).
	apply_form(FormDefs.ALIEN)
	_stop_movement()
	_move_target = Vector2(-1, -1)
	if died_as_vehicle and not exploded:
		GameState.vehicle_wreck_requested.emit(position, died_form)
	GameState.death_zoom_requested.emit(position)
	_run_respawn_countdown()

## Fire-and-forget coroutine: hold on the corpse, count down, then respawn.
## Safe-house owners get a destination choice (buttons in the HUD); everyone
## else goes straight back to The Dump.
func _run_respawn_countdown() -> void:
	await get_tree().create_timer(RESPAWN_DEATH_PAUSE).timeout
	for i in RESPAWN_COUNTDOWN:
		GameState.show_toast("Respawning in %d…" % (RESPAWN_COUNTDOWN - i))
		await get_tree().create_timer(1.0).timeout
	var safe := _my_safe_house()
	if safe.is_empty():
		_respawn_at_landfill()
		return
	_respawn_choice = ""
	GameState.respawn_choice_requested.emit(true)
	var waited := 0.0
	while _respawn_choice.is_empty() and waited < RESPAWN_CHOICE_TIMEOUT:
		await get_tree().create_timer(0.2).timeout
		waited += 0.2
	GameState.respawn_choice_requested.emit(false)
	if _respawn_choice == "safe":
		var tile: Vector2 = safe.get("tile", GameConfig.LANDFILL_CENTER)
		_respawn_at(GameState.free_drop_tile(tile + Vector2(1.0, 0.6)))
	else:
		_respawn_at_landfill()

## Called by the HUD respawn-choice buttons ("safe" or "dump").
func choose_respawn(choice: String) -> void:
	_respawn_choice = choice

func _my_safe_house() -> Dictionary:
	var wm := GameState.world_map
	if wm and is_instance_valid(wm) and wm.has_method("safe_house_for"):
		return wm.safe_house_for(creature_name)
	return {}

## Broadcast this death to everyone's kill feed via a short-lived world_objects
## row (the smoke-cloud trick — no new table, rides the existing poll). Other
## clients toast the message once; we delete the row a few seconds later, and
## any client garbage-collects stale rows whose owner never got to delete them.
func _broadcast_kill_feed(reason: String, killer_name: String) -> void:
	if not is_player or creature_name.is_empty() or not NetworkService.is_online():
		return
	var msg := reason
	if msg.begins_with("You "):
		msg = creature_name + msg.substr(3) # "You got Altima'd." -> "MOE got Altima'd."
	else:
		msg = "%s died. %s" % [creature_name, msg] # "MOE died. The pothole won."
	if not killer_name.is_empty():
		msg = "%s by %s." % [msg.trim_suffix("."), killer_name]
	_broadcast_toast_event(msg)

## Toast `msg` on every other player's screen via a short-lived kill_event row
## (author excluded — they get their own local toast). Fire-and-forget.
func _broadcast_toast_event(msg: String) -> void:
	if not NetworkService.is_online() or msg.is_empty():
		return
	var created: Dictionary = await NetworkService.create_world_object({
		"type": "kill_event",
		"x": grid_pos.x, "y": grid_pos.y,
		"state": "possessed",
		"possessed_by": NetworkService.get_user_id(),
		"owner_name": msg,
	})
	var id := str(created.get("id", ""))
	if id.is_empty():
		return
	await get_tree().create_timer(KILL_FEED_TTL_SEC).timeout
	_note_deleted(id)
	NetworkService.delete_world_object(id)

## Relocate to the landfill and play the emerge animation (which also grants a
## brief invulnerability window since interactions skip while spawning).
func _respawn_at_landfill() -> void:
	_respawn_at(GameConfig.landfill_spawn_tile())

func _respawn_at(tile: Vector2) -> void:
	grid_pos = tile
	_stop_movement()
	_move_target = Vector2(-1, -1)
	_update_transform(true, 0.0)
	is_spawning = true
	_spawn_t = 0.0
	if spawn_fx:
		spawn_fx.visible = true
	scale = Vector3(0.01, 0.01, 0.01)
	_sync_player_position(true)
	is_dead = false

func _schedule_object_respawn(obj: WorldObject, pos: Vector3) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var timer := get_tree().create_timer(OBJECT_RESPAWN_DELAY)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(obj):
			obj.respawn_at(pos))

func _exit_tree() -> void:
	if is_player and not creature_id.is_empty():
		NetworkService.save_creature_position(creature_id, grid_pos.x, grid_pos.y, true)
	if GameState.creatures.has(creature_id):
		GameState.unregister_creature(creature_id)
