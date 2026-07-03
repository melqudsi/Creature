extends Camera3D

@export var follow_target: Creature
@export var follow_smooth := 8.0
@export var edge_pan_speed := 12.0
@export var edge_margin := 18
@export var zoom_min := 8.0
@export var zoom_max := 55.0 # Memphis map is 5x the old one; allow a wider overview
@export var zoom_step := 1.0
@export var pinch_zoom_sensitivity := 1.0

const CAMERA_PITCH := deg_to_rad(38.0)
const CAMERA_YAW := deg_to_rad(45.0)

var _focus := Vector3.ZERO
var _desired_distance := 8.0
var _active_touches: Dictionary = {}
var _last_pinch_dist := 0.0
## True once we've issued move for the current one-finger gesture (press or
## release fallback), so emulated-mouse echoes don't double-fire.
var _tap_fired_for_gesture := false
## Last real touch event — used to dedupe emulated mouse clicks that mirror it.
var _last_touch_ms := 0
var _last_touch_pos := Vector2.ZERO

var _world_map: Node

## Mouse-edge panning is a desktop affordance. On touch devices the emulated
## mouse cursor parks wherever the last tap landed, which after a rotation can
## sit inside the edge margin and shove the camera every frame (screen shake).
var _edge_pan_enabled := true

func _ready() -> void:
	projection = PROJECTION_PERSPECTIVE
	fov = 42.0
	_desired_distance = zoom_min
	_edge_pan_enabled = not DisplayServer.is_touchscreen_available()
	GameState.death_zoom_requested.connect(_on_death_zoom)
	GameState.abduction_zoom_requested.connect(_on_abduction_zoom)
	_update_position(true)

## On the local player's death, pull the camera in on the corpse so the respawn
## countdown actually shows what happened (no-op if already zoomed in).
func _on_death_zoom(_world_pos: Vector3) -> void:
	if _desired_distance <= 14.0:
		return
	var tw := create_tween()
	tw.tween_property(self, "_desired_distance", 13.0, 0.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

## During an abduction the beam tops out ~9 units up and the saucer hovers ~5
## above the apex — at close zoom that's entirely above the frame. Pull back
## for the show, then ease back to where the player was.
func _on_abduction_zoom(duration_sec: float) -> void:
	if _desired_distance >= 22.0:
		return
	var prev := _desired_distance
	var tw := create_tween()
	tw.tween_property(self, "_desired_distance", 24.0, 0.6) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_interval(maxf(duration_sec - 1.6, 0.5))
	tw.tween_property(self, "_desired_distance", prev, 1.0) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)

func bind_world_map(world_map: Node) -> void:
	_world_map = world_map

func process_pointer_input(event: InputEvent) -> bool:
	if _is_over_blocking_ui(event):
		return false

	if event is InputEventMagnifyGesture:
		var pinch := event as InputEventMagnifyGesture
		if pinch.factor > 0.0:
			_apply_zoom((1.0 - pinch.factor) * pinch_zoom_sensitivity * 8.0)
		return true

	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		_last_touch_ms = Time.get_ticks_msec()
		_last_touch_pos = touch.position
		if touch.pressed:
			var solo := _active_touches.is_empty()
			# Mobile browsers sometimes drop touch-end; stale entries block retargeting.
			if not solo and not _active_touches.has(touch.index):
				_active_touches.clear()
				solo = true
			_active_touches[touch.index] = touch.position
			_tap_fired_for_gesture = false
			if solo:
				_issue_move_tap(touch.position)
				_tap_fired_for_gesture = true
			if _active_touches.size() >= 2:
				_last_pinch_dist = 0.0
				_update_pinch()
		else:
			var was_solo := _active_touches.size() == 1 and _active_touches.has(touch.index)
			# Fallback: some mobile web builds skip touch-start under load but still
			# deliver touch-end (or press was blocked by a ghost finger in the dict).
			if not _tap_fired_for_gesture and was_solo:
				_issue_move_tap(touch.position)
			_active_touches.erase(touch.index)
			_tap_fired_for_gesture = false
			if _active_touches.size() < 2:
				_last_pinch_dist = 0.0
		return true

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_last_touch_ms = Time.get_ticks_msec()
		_active_touches[drag.index] = drag.position
		if _active_touches.size() >= 2:
			_update_pinch()
		return true

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return false
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_apply_zoom(-zoom_step)
			return true
		if mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_apply_zoom(zoom_step)
			return true
		if mb.button_index == MOUSE_BUTTON_LEFT or mb.button_index == MOUSE_BUTTON_RIGHT:
			if _is_touch_device():
				# Swallow the emulated click that mirrors a ScreenTouch we already
				# handled. Fast mobile taps sometimes arrive as mouse ONLY (no
				# ScreenTouch) — those must NOT be suppressed for 500ms.
				if Time.get_ticks_msec() - _last_touch_ms < 50 \
						and mb.position.distance_to(_last_touch_pos) < 24.0:
					return true
				_issue_move_tap(mb.position)
				return true
			_issue_move_tap(mb.position)
			return true

	return false

func _is_over_blocking_ui(event: InputEvent) -> bool:
	var pos := Vector2.ZERO
	if event is InputEventMouseButton:
		pos = (event as InputEventMouseButton).position
	elif event is InputEventScreenTouch:
		pos = (event as InputEventScreenTouch).position
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position
	else:
		return false
	return pos.x < 330.0 and pos.y < 100.0

func _update_pinch() -> void:
	if _active_touches.size() < 2:
		_last_pinch_dist = 0.0
		return
	var keys := _active_touches.keys()
	var a: Vector2 = _active_touches[keys[0]]
	var b: Vector2 = _active_touches[keys[1]]
	var dist := a.distance_to(b)
	if _last_pinch_dist > 0.0:
		var delta := (_last_pinch_dist - dist) * 0.1 * pinch_zoom_sensitivity
		_apply_zoom(delta)
	_last_pinch_dist = dist

func _is_touch_device() -> bool:
	if DisplayServer.is_touchscreen_available():
		return true
	if not OS.has_feature("web"):
		return false
	var raw: Variant = JavaScriptBridge.eval(
		"window.matchMedia('(pointer: coarse)').matches ? '1' : ''", true)
	return str(raw) == "1"

func _issue_move_tap(screen_pos: Vector2) -> void:
	# event.position is already in viewport space (same coords project_ray_origin
	# expects). Applying get_screen_transform().affine_inverse() was shifting
	# mobile taps upward — tap bottom, ring upper-middle.
	_handle_ground_click(screen_pos)

func _apply_zoom(delta: float) -> void:
	_desired_distance = clampf(_desired_distance + delta, zoom_min, zoom_max)

func _camera_offset() -> Vector3:
	var cp := cos(CAMERA_PITCH)
	var sp := sin(CAMERA_PITCH)
	var sy := sin(CAMERA_YAW)
	var cy := cos(CAMERA_YAW)
	return Vector3(sy * cp, sp, cy * cp) * _desired_distance

func _process(delta: float) -> void:
	_update_aspect_mode()
	if follow_target and is_instance_valid(follow_target):
		var wp := GameConfig.tile_to_world(follow_target.grid_pos)
		_focus = _focus.lerp(Vector3(wp.x, 0, wp.z), delta * follow_smooth)
	else:
		_focus = _focus.lerp(Vector3(GameConfig.MAP_W * 0.5, 0, GameConfig.MAP_H * 0.5), delta * 2.0)

	var pan := Vector2.ZERO
	if _edge_pan_enabled:
		var mp := get_viewport().get_mouse_position()
		var vp := get_viewport().get_visible_rect().size
		if mp.x < edge_margin:
			pan.x -= 1
		elif mp.x > vp.x - edge_margin:
			pan.x += 1
		if mp.y < edge_margin:
			pan.y -= 1
		elif mp.y > vp.y - edge_margin:
			pan.y += 1
	if Input.is_action_pressed("camera_pan_left"):
		pan.x -= 1
	if Input.is_action_pressed("camera_pan_right"):
		pan.x += 1
	if Input.is_action_pressed("camera_pan_up"):
		pan.y -= 1
	if Input.is_action_pressed("camera_pan_down"):
		pan.y += 1
	if pan.length_squared() > 0:
		var right := global_transform.basis.x
		var fwd := -global_transform.basis.z
		right.y = 0
		fwd.y = 0
		right = right.normalized()
		fwd = fwd.normalized()
		_focus += (right * pan.x + fwd * pan.y).normalized() * edge_pan_speed * delta

	_clamp_focus()
	_update_position(false)

func _update_aspect_mode() -> void:
	# In portrait, apply the FOV to the (narrow) width instead of the height so
	# the horizontal view stays as wide as landscape and the extra screen length
	# shows more of the map vertically. Prevents a cramped strip in portrait.
	var vp := get_viewport()
	if vp == null:
		return
	var size := vp.get_visible_rect().size
	var want := Camera3D.KEEP_WIDTH if size.x < size.y else Camera3D.KEEP_HEIGHT
	if keep_aspect != want:
		keep_aspect = want

func _clamp_focus() -> void:
	var half_w := GameConfig.MAP_W * GameConfig.TILE_SIZE * 0.5
	var half_h := GameConfig.MAP_H * GameConfig.TILE_SIZE * 0.5
	_focus.x = clampf(_focus.x, 2.0, half_w * 2.0 - 2.0)
	_focus.z = clampf(_focus.z, 2.0, half_h * 2.0 - 2.0)

func _update_position(_snap: bool) -> void:
	if not is_inside_tree():
		return
	var look_target := _focus + Vector3(0, 0.25, 0)
	global_position = look_target + _camera_offset()
	look_at(look_target, Vector3.UP)

func _handle_ground_click(screen_pos: Vector2) -> void:
	if not follow_target or not follow_target.has_method("set_move_target"):
		return
	if follow_target.get("is_dead") or follow_target.get("is_spawning"):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		cam = self
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var hit: Variant = null

	var space := get_world_3d().direct_space_state
	if space:
		var to := origin + dir * 500.0
		var query := PhysicsRayQueryParameters3D.create(origin, to)
		query.collide_with_areas = false
		query.collide_with_bodies = true
		var result := space.intersect_ray(query)
		if not result.is_empty():
			hit = result.position

	if hit == null:
		var plane := Plane(Vector3.UP, 0)
		hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return

	var tile := Vector2(hit.x / GameConfig.TILE_SIZE, hit.z / GameConfig.TILE_SIZE)
	if GameState.admin_test_mode and follow_target.has_method("admin_teleport_to"):
		follow_target.admin_teleport_to(tile)
	else:
		follow_target.set_move_target(tile)
	GameState.note_player_input()
	if _world_map and _world_map.has_method("show_click_marker"):
		_world_map.show_click_marker(Vector3(hit.x, 0, hit.z))

func set_follow(target: Creature) -> void:
	follow_target = target
	if target:
		var wp := GameConfig.tile_to_world(target.grid_pos)
		_focus = Vector3(wp.x, 0, wp.z)
		_update_position(true)

func screen_to_tile(screen_pos: Vector2) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(-1, -1)
	var origin := cam.project_ray_origin(screen_pos)
	var dir := cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, 0)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector2(-1, -1)
	return Vector2(hit.x / GameConfig.TILE_SIZE, hit.z / GameConfig.TILE_SIZE)
