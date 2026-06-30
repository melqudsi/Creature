extends Control

@onready var name_label: Label = $TopBar/NameLabel
@onready var toast_panel: Panel = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel
@onready var admin_button: Button = $PainTestButton

var _pain_test: Node
var _admin_panel: Panel
var _worm_spin: SpinBox
var _object_spin: SpinBox
var _profiles_list: VBoxContainer

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	toast_panel.visible = false
	admin_button.text = "admin"
	admin_button.pressed.connect(_toggle_admin_panel)
	_build_admin_panel()
	GameState.player_stats_changed.connect(_refresh_stats)
	GameState.toast_requested.connect(_show_toast)
	call_deferred("_refresh_stats")

func bind_pain_test(pain_test: Node) -> void:
	_pain_test = pain_test

func consumes_pointer_at(screen_pos: Vector2) -> bool:
	if admin_button.visible and admin_button.get_global_rect().has_point(screen_pos):
		return true
	if _admin_panel and _admin_panel.visible and _admin_panel.get_global_rect().has_point(screen_pos):
		return true
	return false

func _build_admin_panel() -> void:
	_admin_panel = Panel.new()
	_admin_panel.name = "AdminPanel"
	_admin_panel.visible = false
	_admin_panel.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_admin_panel.offset_left = -330
	_admin_panel.offset_top = 48
	_admin_panel.offset_right = -12
	_admin_panel.offset_bottom = 460
	add_child(_admin_panel)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	_admin_panel.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 8)
	margin.add_child(root)

	var title := Label.new()
	title.text = "ADMIN"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	var worm_row := _make_spin_row("Worms", 0, 100, 20)
	root.add_child(worm_row)
	_worm_spin = worm_row.get_node("Spin") as SpinBox

	var object_row := _make_spin_row("Objects", 0, 250, 50)
	root.add_child(object_row)
	_object_spin = object_row.get_node("Spin") as SpinBox

	var pain_btn := Button.new()
	pain_btn.text = "start pain test"
	pain_btn.pressed.connect(_on_pain_test_pressed)
	root.add_child(pain_btn)

	var profiles_title := Label.new()
	profiles_title.text = "Profiles"
	root.add_child(profiles_title)

	var refresh_btn := Button.new()
	refresh_btn.text = "refresh profiles"
	refresh_btn.pressed.connect(_refresh_profiles)
	root.add_child(refresh_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 210)
	root.add_child(scroll)

	_profiles_list = VBoxContainer.new()
	_profiles_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_profiles_list)

func _make_spin_row(label_text: String, min_value: float, max_value: float, value: float) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(100, 0)
	row.add_child(label)
	var spin := SpinBox.new()
	spin.name = "Spin"
	spin.min_value = min_value
	spin.max_value = max_value
	spin.step = 1
	spin.value = value
	spin.custom_minimum_size = Vector2(100, 0)
	row.add_child(spin)
	return row

func _toggle_admin_panel() -> void:
	_admin_panel.visible = not _admin_panel.visible
	if _admin_panel.visible:
		_refresh_profiles()

func _on_pain_test_pressed() -> void:
	if _pain_test and _pain_test.has_method("start"):
		if _pain_test.is_active():
			GameState.show_toast("Pain test already running")
			return
		_pain_test.start(int(_worm_spin.value), int(_object_spin.value))

func _refresh_profiles() -> void:
	if not _profiles_list:
		return
	for ch in _profiles_list.get_children():
		ch.queue_free()
	var rows := await NetworkService.fetch_all_creatures()
	if rows.is_empty():
		var empty := Label.new()
		empty.text = "No profiles found"
		_profiles_list.add_child(empty)
		return
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		_add_profile_row(row)

func _add_profile_row(row: Dictionary) -> void:
	var creature_id := str(row.get("id", ""))
	var profile_name := str(row.get("name", "Creature"))
	var item := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s  (%s, %s)" % [
		profile_name,
		("%.1f" % float(row.get("x", 0.0))),
		("%.1f" % float(row.get("y", 0.0))),
	]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_child(label)
	var delete_btn := Button.new()
	delete_btn.text = "delete"
	delete_btn.pressed.connect(func(): _delete_profile(creature_id, profile_name))
	item.add_child(delete_btn)
	_profiles_list.add_child(item)

func _delete_profile(creature_id: String, profile_name: String) -> void:
	var ok := await NetworkService.delete_creature_profile(creature_id)
	if ok:
		GameState.show_toast("Deleted profile %s" % profile_name)
	else:
		GameState.show_toast("Could not delete %s" % profile_name)
	_refresh_profiles()

func _refresh_stats() -> void:
	var c = GameState.player_creature
	if not c:
		return
	name_label.text = c.creature_name

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_panel.visible = true
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(func(): toast_panel.visible = false)
