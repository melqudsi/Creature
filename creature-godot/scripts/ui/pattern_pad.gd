class_name PatternPad
extends Control

## Android-style swipe pattern pad (Slice 7 onboarding): a 3x3 grid of dots the
## player drags across to draw their "password". No numbers, just dots.
##
## Emits pattern_changed after every completed drag. The pattern is exposed as
## a dash-joined dot-index string ("0-4-8-5", indices row-major 0..8), which is
## what gets hashed — never store the raw pattern anywhere.

signal pattern_changed(pattern: String)

const GRID := 3
const DOT_RADIUS := 9.0
const HIT_RADIUS := 34.0
const LINE_COLOR := Color("#00e5ff")
const DOT_COLOR := Color(0.35, 0.55, 0.62)
const DOT_SELECTED_COLOR := Color("#00e5ff")

var _selected: Array[int] = []
var _dragging := false
var _cursor := Vector2.ZERO

func _ready() -> void:
	custom_minimum_size = Vector2(240, 240)
	mouse_filter = Control.MOUSE_FILTER_STOP

func pattern() -> String:
	var parts: Array[String] = []
	for i in _selected:
		parts.append(str(i))
	return "-".join(parts)

func dot_count() -> int:
	return _selected.size()

func clear() -> void:
	_selected.clear()
	_dragging = false
	queue_redraw()
	pattern_changed.emit("")

func _dot_pos(index: int) -> Vector2:
	var cell := size / float(GRID)
	var gx := index % GRID
	@warning_ignore("integer_division")
	var gy := index / GRID
	return Vector2(cell.x * (float(gx) + 0.5), cell.y * (float(gy) + 0.5))

func _gui_input(event: InputEvent) -> void:
	# Touch arrives as emulated mouse events on Controls, so handling mouse
	# covers both desktop and mobile.
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_selected.clear()
				_dragging = true
				_cursor = mb.position
				_try_select(mb.position)
			else:
				_dragging = false
				queue_redraw()
				pattern_changed.emit(pattern())
			accept_event()
	elif event is InputEventMouseMotion and _dragging:
		_cursor = (event as InputEventMouseMotion).position
		_try_select(_cursor)
		queue_redraw()
		accept_event()

func _try_select(pos: Vector2) -> void:
	for i in GRID * GRID:
		if _selected.has(i):
			continue
		if pos.distance_to(_dot_pos(i)) <= HIT_RADIUS:
			# Auto-include a skipped middle dot (real pattern locks do this):
			# swiping corner-to-corner through the center selects the center too.
			if not _selected.is_empty():
				var mid := _midpoint_dot(_selected[_selected.size() - 1], i)
				if mid >= 0 and not _selected.has(mid):
					_selected.append(mid)
			_selected.append(i)
			queue_redraw()
			return

## The dot exactly between a and b on the grid, or -1 if they aren't aligned
## with a single dot between them.
func _midpoint_dot(a: int, b: int) -> int:
	var ax := a % GRID
	@warning_ignore("integer_division")
	var ay := a / GRID
	var bx := b % GRID
	@warning_ignore("integer_division")
	var by := b / GRID
	if (ax + bx) % 2 != 0 or (ay + by) % 2 != 0:
		return -1
	@warning_ignore("integer_division")
	var mx := (ax + bx) / 2
	@warning_ignore("integer_division")
	var my := (ay + by) / 2
	var mid := my * GRID + mx
	return mid if mid != a and mid != b else -1

func _draw() -> void:
	# Connection trail first (under the dots).
	for k in range(1, _selected.size()):
		draw_line(_dot_pos(_selected[k - 1]), _dot_pos(_selected[k]), LINE_COLOR, 4.0, true)
	if _dragging and not _selected.is_empty():
		draw_line(_dot_pos(_selected[_selected.size() - 1]), _cursor, LINE_COLOR * Color(1, 1, 1, 0.5), 3.0, true)
	for i in GRID * GRID:
		var p := _dot_pos(i)
		if _selected.has(i):
			draw_circle(p, DOT_RADIUS + 5.0, DOT_SELECTED_COLOR * Color(1, 1, 1, 0.25))
			draw_circle(p, DOT_RADIUS, DOT_SELECTED_COLOR)
		else:
			draw_circle(p, DOT_RADIUS, DOT_COLOR)
