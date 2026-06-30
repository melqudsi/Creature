extends Control

@onready var name_edit: LineEdit = $Panel/NameEdit
@onready var preview_viewport: SubViewport = $Panel/PreviewFrame/PreviewViewport
@onready var preview_camera: Camera3D = $Panel/PreviewFrame/PreviewViewport/PreviewCamera
@onready var cute_btn: Button = $Panel/AppearanceRow/CuteBtn
@onready var ugly_btn: Button = $Panel/AppearanceRow/UglyBtn
@onready var summon_btn: Button = $Panel/SummonBtn
@onready var color_row: HBoxContainer = $Panel/ColorRow

var _appearance := "cute"
var _color := GameConfig.CREATURE_COLORS[0]
var _preview_creature: Creature

const CREATURE_SCENE := preload("res://scenes/units/creature.tscn")

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	cute_btn.pressed.connect(func(): _set_appearance("cute"))
	ugly_btn.pressed.connect(func(): _set_appearance("ugly"))
	summon_btn.pressed.connect(_on_summon)
	name_edit.focus_entered.connect(_on_name_focus_entered)
	name_edit.gui_input.connect(_on_name_gui_input)
	_build_color_swatches()
	_spawn_preview()
	preview_camera.current = true
	call_deferred("_focus_name_field")

func _focus_name_field() -> void:
	name_edit.grab_focus()

func _on_name_gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			name_edit.grab_focus()
			_show_mobile_keyboard()
			accept_event()

func _on_name_focus_entered() -> void:
	_show_mobile_keyboard()

func _show_mobile_keyboard() -> void:
	if not name_edit.has_focus():
		return
	if OS.has_feature("web"):
		DisplayServer.virtual_keyboard_show(name_edit.text, name_edit.get_global_rect())

func _build_color_swatches() -> void:
	for c in GameConfig.CREATURE_COLORS:
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(32, 32)
		btn.focus_mode = Control.FOCUS_NONE
		var sb := StyleBoxFlat.new()
		sb.bg_color = c
		sb.set_corner_radius_all(4)
		sb.set_border_width_all(2)
		sb.border_color = Color(0.2, 0.2, 0.2, 0.8)
		btn.add_theme_stylebox_override("normal", sb)
		btn.add_theme_stylebox_override("hover", sb)
		btn.add_theme_stylebox_override("pressed", sb)
		btn.add_theme_stylebox_override("focus", sb)
		btn.pressed.connect(func(): _set_color(c))
		color_row.add_child(btn)

func _clear_preview_creature() -> void:
	for ch in preview_viewport.get_children():
		if ch is Camera3D or ch is DirectionalLight3D:
			continue
		ch.queue_free()

func _spawn_preview() -> void:
	_clear_preview_creature()
	_preview_creature = CREATURE_SCENE.instantiate() as Creature
	preview_viewport.add_child(_preview_creature)
	_preview_creature.setup.call_deferred({
		"id": "preview",
		"name": "Prev",
		"color": _color,
		"appearance": _appearance,
		"x": 0, "y": 0,
		"is_player": false,
	})

func _set_appearance(app: String) -> void:
	_appearance = app
	if _preview_creature:
		_preview_creature.appearance = app
		_preview_creature._apply_appearance()

func _set_color(c: Color) -> void:
	_color = c
	if _preview_creature:
		_preview_creature.creature_color = c
		_preview_creature._apply_appearance()

func _on_summon() -> void:
	var n := name_edit.text.strip_edges()
	if n.is_empty():
		n = "Blob"
	n = n.substr(0, GameConfig.NAME_MAX_LEN)
	var row := {
		"id": "local_player",
		"name": n,
		"color": _color,
		"appearance": _appearance,
		"x": GameConfig.MAP_W / 2,
		"y": GameConfig.MAP_H / 2,
		"health": 100,
		"stamina": 10,
		"size_level": 1,
		"is_player": true,
	}
	GameState.player_data = row
	NetworkService.create_creature(row)
	get_tree().change_scene_to_file("res://scenes/main.tscn")
