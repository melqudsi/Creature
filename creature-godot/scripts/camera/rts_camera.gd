extends Camera3D

@export var follow_target: Creature
@export var follow_smooth := 8.0
@export var edge_pan_speed := 12.0
@export var edge_margin := 18
@export var zoom_min := 8.0
@export var zoom_max := 40.0
@export var zoom_step := 1.0
@export var pinch_zoom_sensitivity := 1.0

const TAP_MOVE_THRESHOLD := 24.0
const CAMERA_PITCH := deg_to_rad(38.0)
const CAMERA_YAW := deg_to_rad(45.0)

var _focus := Vector3.ZERO
var _desired_distance := 8.0
var _active_touches: Dictionary = {}
var _touch_start := Vector2.ZERO
var _touch_moved := false
var _was_pinching := false
var _last_pinch_dist := 0.0
var _last_tap_ms := 0
var _last_tap_pos := Vector2.ZERO

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
	_update_position(true)

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
		if touch.pressed:
			if touch.index == 0:
				_touch_start = touch.position
				_touch_moved = false
				if _active_touches.is_empty():
					_was_pinching = false
			_active_touches[touch.index] = touch.position
			if touch.index == 0 and _active_touches.size() == 1:
				_handle_tap(touch.position, true)
			_update_pinch()
		else:
			_active_touches.erase(touch.index)
			if _active_touches.size() < 2:
				_last_pinch_dist = 0.0
				_was_pinching = false
		return true

	if event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_active_touches[drag.index] = drag.position
		if drag.index == 0 and _active_touches.size() == 1:
			if drag.position.distance_to(_touch_start) > TAP_MOVE_THRESHOLD:
				_touch_moved = true
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
			_handle_tap(mb.position, false)
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
	_was_pinching = true
	var keys := _active_touches.keys()
	var a: Vector2 = _active_touches[keys[0]]
	var b: Vector2 = _active_touches[keys[1]]
	var dist := a.distance_to(b)
	if _last_pinch_dist > 0.0:
		var delta := (_last_pinch_dist - dist) * 0.1 * pinch_zoom_sensitivity
		_apply_zoom(delta)
	_last_pinch_dist = dist

func _viewport_position(screen_pos: Vector2) -> Vector2:
	var vp := get_viewport()
	if vp == null:
		return screen_pos
	return vp.get_screen_transform().affine_inverse() * screen_pos

func _handle_tap(screen_pos: Vector2, from_touch: bool) -> void:
	if _was_pinching or _touch_moved:
		return
	var now := Time.get_ticks_msec()
	if now - _last_tap_ms < 80 and _last_tap_pos.distance_to(screen_pos) < 16.0:
		return
	_last_tap_ms = now
	_last_tap_pos = screen_pos
	var pos := _viewport_position(screen_pos) if from_touch else screen_pos
	_handle_ground_click(pos)

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
	var pos := _viewport_position(screen_pos)
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return Vector2(-1, -1)
	var origin := cam.project_ray_origin(pos)
	var dir := cam.project_ray_normal(pos)
	var plane := Plane(Vector3.UP, 0)
	var hit = plane.intersects_ray(origin, dir)
	if hit == null:
		return Vector2(-1, -1)
	return Vector2(hit.x / GameConfig.TILE_SIZE, hit.z / GameConfig.TILE_SIZE)
