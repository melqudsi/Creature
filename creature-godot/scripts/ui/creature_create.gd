extends Control

signal profile_ready

@onready var name_edit: LineEdit = $Panel/NameEdit
@onready var cute_btn: Button = $Panel/AppearanceRow/CuteBtn
@onready var ugly_btn: Button = $Panel/AppearanceRow/UglyBtn
@onready var summon_btn: Button = $Panel/SummonBtn
@onready var color_row: GridContainer = $Panel/ColorRow
@onready var appearance_row: HBoxContainer = $Panel/AppearanceRow
@onready var status_label: Label = get_node_or_null("Panel/StatusLabel") as Label

var _appearance := "cute"
## Dark gray is the default selected color on open.
var _color := GameConfig.DEFAULT_CREATURE_COLOR
var _swatches: Array[Button] = []

const SWATCH_SELECT_COLOR := Color("#00e5ff")

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	appearance_row.visible = false
	cute_btn.pressed.connect(func(): _set_appearance("cute"))
	ugly_btn.pressed.connect(func(): _set_appearance("ugly"))
	summon_btn.pressed.connect(_on_summon)
	name_edit.focus_entered.connect(_on_name_focus_entered)
	name_edit.gui_input.connect(_on_name_gui_input)
	name_edit.text_changed.connect(_on_name_text_changed)
	_build_color_swatches()
	_add_build_stamp()
	call_deferred("_focus_name_field")

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
		# Signature (Godot 4.7): virtual_keyboard_show(existing_text, position,
		#   type = KEYBOARD_TYPE_DEFAULT, max_length = -1,
		#   cursor_start = -1, cursor_end = -1)
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
		btn.custom_minimum_size = Vector2(52, 52)
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

func _set_appearance(app: String) -> void:
	_appearance = app

func _set_color(c: Color) -> void:
	_color = c
	_update_swatch_selection()

func _on_summon() -> void:
	var n := name_edit.text.strip_edges().to_upper()
	n = n.substr(0, GameConfig.NAME_MAX_LEN)
	if n.is_empty():
		_set_status("Name required")
		return
	summon_btn.disabled = true
	_set_status("Checking profile...")
	var profile := await NetworkService.register_or_claim_profile(n, _color)
	if profile.is_empty():
		_set_status("Could not create or claim '%s' - open admin to see why" % n)
		summon_btn.disabled = false
		return
	_set_status("Welcome, %s" % profile.get("name", n))
	profile_ready.emit()

func _set_status(message: String) -> void:
	if status_label:
		status_label.text = message
