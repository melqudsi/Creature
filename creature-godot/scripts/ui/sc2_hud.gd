extends Control

@onready var name_label: Label = $TopBar/NameLabel
@onready var toast_panel: Panel = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel
@onready var admin_button: Button = $PainTestButton
@onready var become_button: Button = $ActionBar/BecomeButton
@onready var special_button: Button = $ActionBar/SpecialButton
@onready var pop_button: Button = $ActionBar/PopOutButton
@onready var pickup_button: Button = $ActionBar/PickUpButton
@onready var drop_button: Button = $ActionBar/DropButton
@onready var region_label: Label = $RegionLabel

var _last_region := ""

var _pain_test: Node
var _admin_panel: Panel
var _worm_spin: SpinBox
var _object_spin: SpinBox
var _profiles_list: VBoxContainer
var _logs_text: TextEdit

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	toast_panel.visible = false
	admin_button.text = "admin"
	admin_button.visible = false
	admin_button.pressed.connect(_toggle_admin_panel)
	_build_admin_panel()
	_setup_action_buttons()
	GameState.player_stats_changed.connect(_refresh_stats)
	GameState.toast_requested.connect(_show_toast)
	GameState.admin_log_added.connect(_append_log_line)
	GameState.interaction_changed.connect(_on_interaction_changed)
	GameState.form_changed.connect(_on_form_changed)
	if region_label:
		region_label.text = ""
	call_deferred("_refresh_stats")

## Keep the bottom-left region label in sync with where the player is standing.
## Cheap: only touches the label when the region name actually changes.
func _process(_delta: float) -> void:
	if not region_label:
		return
	var c = GameState.player_creature
	if not c or not is_instance_valid(c):
		if _last_region != "":
			_last_region = ""
			region_label.text = ""
		return
	var region := GameConfig.region_for_tile(c.grid_pos)
	if region != _last_region:
		_last_region = region
		region_label.text = region
	_update_money_buttons(c)

## Show "Pick Up" when eligible money is in reach and "Drop" while carrying. Kept
## cheap: only toggles the buttons when the state actually changes.
func _update_money_buttons(c: Creature) -> void:
	if not pickup_button or not drop_button:
		return
	var can_pick: bool = c.can_pick_up_now() and not c.is_dead
	if pickup_button.visible != can_pick:
		pickup_button.visible = can_pick
	var carrying: bool = c.is_carrying()
	if drop_button.visible != carrying:
		drop_button.visible = carrying

func _setup_action_buttons() -> void:
	become_button.visible = false
	special_button.visible = false
	pop_button.visible = false
	pickup_button.visible = false
	drop_button.visible = false
	become_button.focus_mode = Control.FOCUS_NONE
	special_button.focus_mode = Control.FOCUS_NONE
	pop_button.focus_mode = Control.FOCUS_NONE
	pickup_button.focus_mode = Control.FOCUS_NONE
	drop_button.focus_mode = Control.FOCUS_NONE
	become_button.pressed.connect(_on_become_pressed)
	special_button.pressed.connect(_on_special_pressed)
	pop_button.pressed.connect(_on_pop_pressed)
	pickup_button.pressed.connect(_on_pickup_pressed)
	drop_button.pressed.connect(_on_drop_pressed)

func _player_form() -> String:
	var c = GameState.player_creature
	if c and is_instance_valid(c):
		return c.form_key
	return FormDefs.ALIEN

## "Become <X>" appears only while an alien is standing near a shapeshift target.
func _on_interaction_changed(can_become: bool, form_display: String) -> void:
	var show := can_become and FormDefs.is_alien(_player_form())
	become_button.visible = show
	if show:
		become_button.text = "Become %s" % form_display

## Toggle Pop Out / Special when the player's form changes.
func _on_form_changed(form_key: String) -> void:
	var alien := FormDefs.is_alien(form_key)
	pop_button.visible = not alien
	match form_key:
		FormDefs.ALTIMA:
			special_button.visible = true
			special_button.text = "Speed Burst"
		FormDefs.BBQ_SMOKER:
			special_button.visible = true
			special_button.text = "Smoke Cloud"
		_:
			special_button.visible = false
	if not alien:
		become_button.visible = false

func _on_become_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("begin_shapeshift"):
		c.begin_shapeshift()

func _on_pop_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("pop_out"):
		c.pop_out()

func _on_special_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("use_special"):
		c.use_special()

func _on_pickup_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("pick_up_nearest"):
		c.pick_up_nearest()

func _on_drop_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("drop_all"):
		c.drop_all()

func bind_pain_test(pain_test: Node) -> void:
	_pain_test = pain_test

func consumes_pointer_at(screen_pos: Vector2) -> bool:
	if admin_button.visible and admin_button.get_global_rect().has_point(screen_pos):
		return true
	if _admin_panel and _admin_panel.visible and _admin_panel.get_global_rect().has_point(screen_pos):
		return true
	for btn in [become_button, special_button, pop_button, pickup_button, drop_button]:
		if btn and btn.visible and btn.get_global_rect().has_point(screen_pos):
			return true
	return false

func _build_admin_panel() -> void:
	_admin_panel = Panel.new()
	_admin_panel.name = "AdminPanel"
	_admin_panel.visible = false
	_admin_panel.anchor_left = 0.03
	_admin_panel.anchor_top = 0.08
	_admin_panel.anchor_right = 0.97
	_admin_panel.anchor_bottom = 0.95
	_admin_panel.offset_left = 0
	_admin_panel.offset_top = 0
	_admin_panel.offset_right = 0
	_admin_panel.offset_bottom = 0
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

	var money_row := HBoxContainer.new()
	money_row.add_theme_constant_override("separation", 8)
	root.add_child(money_row)
	var remove_money_btn := Button.new()
	remove_money_btn.text = "remove all money"
	remove_money_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	remove_money_btn.pressed.connect(_on_remove_all_money_pressed)
	money_row.add_child(remove_money_btn)
	var spawn_stacks_btn := Button.new()
	spawn_stacks_btn.text = "spawn 5 stacks"
	spawn_stacks_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_stacks_btn.pressed.connect(_on_spawn_stacks_pressed)
	money_row.add_child(spawn_stacks_btn)

	var reset_objects_btn := Button.new()
	reset_objects_btn.text = "reset ALL world objects"
	reset_objects_btn.pressed.connect(_on_reset_objects_pressed)
	root.add_child(reset_objects_btn)

	var profiles_title := Label.new()
	profiles_title.text = "Profiles"
	root.add_child(profiles_title)

	var refresh_btn := Button.new()
	refresh_btn.text = "refresh profiles"
	refresh_btn.pressed.connect(_refresh_profiles)
	root.add_child(refresh_btn)

	var clear_session_btn := Button.new()
	clear_session_btn.text = "clear session / reload"
	clear_session_btn.pressed.connect(_clear_session_and_reload)
	root.add_child(clear_session_btn)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 210)
	root.add_child(scroll)

	_profiles_list = VBoxContainer.new()
	_profiles_list.add_theme_constant_override("separation", 4)
	scroll.add_child(_profiles_list)

	var logs_title := Label.new()
	logs_title.text = "Logs"
	root.add_child(logs_title)

	_logs_text = TextEdit.new()
	_logs_text.editable = false
	_logs_text.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_logs_text.custom_minimum_size = Vector2(0, 160)
	_logs_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_logs_text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_logs_text.scroll_fit_content_height = false
	root.add_child(_logs_text)
	_refresh_logs()

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

func _is_admin_player() -> bool:
	var c = GameState.player_creature
	return c != null and c.creature_name.to_upper() == "MOE"

func _toggle_admin_panel() -> void:
	# Guard: only MOE may open the admin panel, even if the button was somehow hit.
	if not _is_admin_player():
		_admin_panel.visible = false
		return
	_admin_panel.visible = not _admin_panel.visible
	if _admin_panel.visible:
		_refresh_profiles()
		_refresh_logs()

func _on_remove_all_money_pressed() -> void:
	if not NetworkService.is_online():
		GameState.show_toast("Offline — can't touch shared money")
		return
	var n: int = await NetworkService.admin_delete_all_money()
	GameState.show_toast("Removed %d money objects" % n)

func _on_spawn_stacks_pressed() -> void:
	if not NetworkService.is_online():
		GameState.show_toast("Offline — can't spawn shared money")
		return
	var created: Array = await NetworkService.admin_spawn_money_stacks(5)
	GameState.show_toast("Spawned %d money stacks" % created.size())

func _on_reset_objects_pressed() -> void:
	if not NetworkService.is_online():
		GameState.show_toast("Offline — can't reset shared objects")
		return
	var ok: bool = await NetworkService.admin_reset_world_objects()
	GameState.show_toast("World objects reset" if ok else "Reset failed — see logs")

func _clear_session_and_reload() -> void:
	NetworkService.clear_saved_session()
	GameState.player_data.clear()
	GameState.player_creature = null
	get_tree().reload_current_scene()

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
		GameState.show_toast("Could not delete %s - check logs" % profile_name)
	_refresh_profiles()

func _refresh_logs() -> void:
	if not _logs_text:
		return
	var text := ""
	for line in GameState.admin_logs:
		text += line + "\n"
	_logs_text.text = text

func _append_log_line(line: String) -> void:
	if not _logs_text:
		return
	_logs_text.text += line + "\n"
	_logs_text.set_caret_line(_logs_text.get_line_count())

func _refresh_stats() -> void:
	var c = GameState.player_creature
	if not c:
		admin_button.visible = false
		return
	name_label.text = c.creature_name
	admin_button.visible = _is_admin_player()
	if not admin_button.visible and _admin_panel and _admin_panel.visible:
		_admin_panel.visible = false

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_panel.visible = true
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(func(): toast_panel.visible = false)
