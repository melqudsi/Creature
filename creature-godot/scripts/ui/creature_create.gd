extends Control

## Onboarding (Slice 7): traditional Log in / Register split, with an
## Android-style 4-dot swipe pattern standing in for a password.
##
## Modes: "choose" (two big buttons) -> "register" (name + color + pattern)
##                                   -> "login"    (name + pattern)

signal profile_ready

@onready var name_edit: LineEdit = $Panel/NameEdit
@onready var color_label: Label = $Panel/ColorLabel
@onready var color_row: GridContainer = $Panel/ColorRow
@onready var mode_row: VBoxContainer = $Panel/ModeRow
@onready var login_mode_btn: Button = $Panel/ModeRow/LoginModeBtn
@onready var register_mode_btn: Button = $Panel/ModeRow/RegisterModeBtn
@onready var pattern_label: Label = $Panel/PatternLabel
@onready var pattern_note: Label = $Panel/PatternNote
@onready var pattern_pad: PatternPad = $Panel/PatternPad
@onready var action_btn: Button = $Panel/ActionBtn
@onready var back_btn: Button = $Panel/BackBtn
@onready var title_label: Label = $Panel/Title
@onready var status_label: Label = $Panel/StatusLabel

const MIN_PATTERN_DOTS := 4
const SWATCH_SELECT_COLOR := Color("#00e5ff")

var _mode := "choose"
## Dark gray is the default selected color on open.
var _color := GameConfig.DEFAULT_CREATURE_COLOR
var _swatches: Array[Button] = []

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	login_mode_btn.pressed.connect(func(): _set_mode("login"))
	register_mode_btn.pressed.connect(func(): _set_mode("register"))
	back_btn.pressed.connect(func(): _set_mode("choose"))
	action_btn.pressed.connect(_on_action)
	name_edit.focus_entered.connect(_on_name_focus_entered)
	name_edit.gui_input.connect(_on_name_gui_input)
	name_edit.text_changed.connect(_on_name_text_changed)
	pattern_pad.pattern_changed.connect(_on_pattern_changed)
	_build_color_swatches()
	_add_build_stamp()
	_set_mode("choose")

func _set_mode(mode: String) -> void:
	_mode = mode
	pattern_pad.clear()
	var choosing := mode == "choose"
	mode_row.visible = choosing
	back_btn.visible = not choosing
	name_edit.visible = not choosing
	pattern_label.visible = not choosing
	pattern_note.visible = not choosing
	pattern_pad.visible = not choosing
	action_btn.visible = not choosing
	color_label.visible = mode == "register"
	color_row.visible = mode == "register"
	match mode:
		"choose":
			title_label.text = "CREATURE"
			_set_status("Log in, or register a new creature.")
		"register":
			title_label.text = "REGISTER"
			pattern_label.text = "CHOOSE A 4 DOT PATTERN"
			pattern_note.text = "You'll enter this pattern to log in — remember it"
			action_btn.text = "REGISTER"
			_set_status("")
			_position_pattern_block(true)
			call_deferred("_focus_name_field")
		"login":
			title_label.text = "LOG IN"
			pattern_label.text = "DRAW YOUR PATTERN"
			pattern_note.text = ""
			action_btn.text = "LOG IN"
			_set_status("")
			_position_pattern_block(false)
			call_deferred("_focus_name_field")

## Login has no color picker, so lift the pattern block into that empty space
## (keeps the panel from feeling bottom-heavy with a big hole in the middle).
func _position_pattern_block(with_colors: bool) -> void:
	var top := 234.0 if with_colors else 110.0
	pattern_label.offset_top = top
	pattern_label.offset_bottom = top + 22.0
	pattern_note.offset_top = top + 22.0
	pattern_note.offset_bottom = top + 42.0
	var pad_top := top + 50.0
	pattern_pad.offset_top = pad_top
	pattern_pad.offset_bottom = pad_top + 220.0
	action_btn.offset_top = pad_top + 238.0
	action_btn.offset_bottom = pad_top + 282.0

func _on_pattern_changed(_pattern: String) -> void:
	if pattern_pad.dot_count() > 0 and pattern_pad.dot_count() < MIN_PATTERN_DOTS:
		_set_status("Pattern needs at least %d dots" % MIN_PATTERN_DOTS)
	else:
		_set_status("")

func _on_action() -> void:
	var n := name_edit.text.strip_edges().to_upper()
	n = n.substr(0, GameConfig.NAME_MAX_LEN)
	if n.is_empty():
		_set_status("Name required")
		return
	if pattern_pad.dot_count() < MIN_PATTERN_DOTS:
		_set_status("Draw a pattern with at least %d dots" % MIN_PATTERN_DOTS)
		return
	action_btn.disabled = true
	var profile: Dictionary
	if _mode == "register":
		_set_status("Registering…")
		profile = await NetworkService.register_profile(n, _color, pattern_pad.pattern())
	else:
		_set_status("Checking pattern…")
		profile = await NetworkService.login_profile(n, pattern_pad.pattern())
	if profile.is_empty():
		_set_status(NetworkService.last_error_text())
		pattern_pad.clear()
		action_btn.disabled = false
		return
	_set_status("Welcome, %s" % profile.get("name", n))
	profile_ready.emit()

## Small, unobtrusive build stamp so the loaded build can be confirmed on the
## onboarding screen (mirrors the stamp in web/custom_shell.html).
func _add_build_stamp() -> void:
	var stamp := Label.new()
	stamp.text = GameConfig.BUILD_ID
	stamp.modulate = Color(1, 1, 1, 0.4)
	stamp.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stamp.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	stamp.offset_left = -160.0
	stamp.offset_top = -22.0
	stamp.offset_right = -8.0
	stamp.offset_bottom = -4.0
	stamp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(stamp)

func _focus_name_field() -> void:
	if name_edit.visible:
		name_edit.grab_focus()

func _on_name_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			name_edit.grab_focus()
			_show_mobile_keyboard()
			# Refocus on the same field won't re-fire focus_entered, so place the
			# caret at the end here too for the touch path.
			call_deferred("_place_caret_end")
			accept_event()

func _on_name_focus_entered() -> void:
	_show_mobile_keyboard()
	# Editing an existing name should start at the end, not the start.
	call_deferred("_place_caret_end")

func _place_caret_end() -> void:
	if is_instance_valid(name_edit):
		name_edit.caret_column = name_edit.text.length()

func _on_name_text_changed(new_text: String) -> void:
	var upper := new_text.to_upper()
	if upper == new_text:
		return
	var caret := name_edit.caret_column
	name_edit.text = upper
	name_edit.caret_column = caret

func _show_mobile_keyboard() -> void:
	if not name_edit.has_focus():
		return
	if OS.has_feature("web"):
		# Place the mobile virtual keyboard's caret at the END of the existing
		# text so the user can immediately backspace/edit/append. Without the
		# cursor args the on-screen keyboard opens at index 0 (prepend-only bug).
		var end := name_edit.text.length()
		DisplayServer.virtual_keyboard_show(
			name_edit.text,
			name_edit.get_global_rect(),
			DisplayServer.KEYBOARD_TYPE_DEFAULT,
			GameConfig.NAME_MAX_LEN,
			end,
			end,
		)

func _build_color_swatches() -> void:
	_swatches.clear()
	for c in GameConfig.CREATURE_COLORS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(46, 46)
		btn.focus_mode = Control.FOCUS_NONE
		btn.set_meta("swatch_color", c)
		btn.pressed.connect(func(): _set_color(c))
		color_row.add_child(btn)
		_swatches.append(btn)
	_update_swatch_selection()

## Style a single swatch; the selected one gets a bright, high-contrast border.
func _apply_swatch_style(btn: Button, c: Color, selected: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = c
	sb.set_corner_radius_all(6)
	if selected:
		sb.set_border_width_all(4)
		sb.border_color = SWATCH_SELECT_COLOR
	else:
		sb.set_border_width_all(2)
		sb.border_color = Color(0.1, 0.1, 0.1, 0.7)
	for s in ["normal", "hover", "pressed", "focus"]:
		btn.add_theme_stylebox_override(s, sb)

func _update_swatch_selection() -> void:
	for btn in _swatches:
		var c: Color = btn.get_meta("swatch_color")
		_apply_swatch_style(btn, c, c == _color)

func _set_color(c: Color) -> void:
	_color = c
	_update_swatch_selection()

func _set_status(message: String) -> void:
	if status_label:
		status_label.text = message
