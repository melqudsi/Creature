extends Control

@onready var name_label: Label = $TopBar/NameLabel
@onready var toast_panel: Panel = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel
@onready var menu_button: Button = $MenuButton
@onready var announce_button: Button = $AnnounceButton
@onready var house_button: Button = $ActionBar/HouseButton
@onready var become_button: Button = $ActionBar/BecomeButton
@onready var special_button: Button = $ActionBar/SpecialButton
@onready var pop_button: Button = $ActionBar/PopOutButton
@onready var pickup_button: Button = $ActionBar/PickUpButton
@onready var drop_button: Button = $ActionBar/DropButton
@onready var steal_button: Button = $ActionBar/StealButton
@onready var eat_button: Button = $ActionBar/EatButton
@onready var region_label: Label = $RegionLabel
@onready var move_hint: Label = $MoveHint
@onready var top_bar: Panel = $TopBar

const HELP_TEXT := "You crash landed on Earth. Place called Memphis. Lucky you.\nTap to move around and explore the area.\nShape shift into stuff by getting close to them.\nDon't forget to collect Money Stacks and combine them.\nGood luck, have fun, and don't die"
const HELP_GOLD := Color(1.0, 0.76, 0.16)

var _last_region := ""
var _move_hint_deadline := 0
## Slice 7: respawn-destination choice (safe house vs The Dump), built in code.
var _respawn_panel: VBoxContainer
var _help_button: Button
var _help_panel: Panel
var _help_label: Label

var _pain_test: Node
var _main: Node
var _admin_panel: Panel
var _worm_spin: SpinBox
var _object_spin: SpinBox
var _profiles_list: VBoxContainer
var _logs_text: TextEdit
var _test_mode_toggle: CheckButton
var _announce_input: LineEdit
## Top-left menu dropdown (Sign Out + MOE-only Admin).
var _menu_panel: PanelContainer
var _menu_admin_btn: Button
## Announcement popup + latest broadcast ({"id", "message"}).
var _announce_panel: PanelContainer
var _announce_label: Label
var _latest_announcement: Dictionary = {}

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	toast_panel.visible = false
	menu_button.focus_mode = Control.FOCUS_NONE
	menu_button.text = ""
	menu_button.icon = _make_hamburger_icon()
	menu_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	menu_button.pressed.connect(_toggle_menu)
	announce_button.focus_mode = Control.FOCUS_NONE
	announce_button.icon = _make_speaker_icon()
	announce_button.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_button.visible = false # appears once an announcement exists
	announce_button.pressed.connect(_show_announcement)
	_build_menu_dropdown()
	_build_announcement_popup()
	_build_help_overlay()
	_build_admin_panel()
	_setup_action_buttons()
	NetworkService.announcement_received.connect(_on_announcement_received)
	GameState.player_stats_changed.connect(_refresh_stats)
	GameState.toast_requested.connect(_show_toast)
	GameState.admin_log_added.connect(_append_log_line)
	GameState.interaction_changed.connect(_on_interaction_changed)
	GameState.form_changed.connect(_on_form_changed)
	GameState.respawn_choice_requested.connect(_on_respawn_choice_requested)
	_build_respawn_choice()
	if region_label:
		region_label.text = ""
		region_label.add_theme_font_size_override("font_size", 22)
	call_deferred("_refresh_stats")
	# Inset the whole HUD away from iPhone notch/rounded corners/home bar in
	# installed-PWA mode. Insets change on rotation (size_changed) and can
	# settle late on iOS launch, so re-apply a few times after startup.
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	for delay in [0.5, 1.5, 3.0]:
		get_tree().create_timer(delay).timeout.connect(_apply_safe_area)

func _toggle_menu() -> void:
	GameState.note_player_input()
	_menu_panel.visible = not _menu_panel.visible

func _build_menu_dropdown() -> void:
	_menu_panel = PanelContainer.new()
	_menu_panel.name = "MenuDropdown"
	_menu_panel.visible = false
	_menu_panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_menu_panel.offset_left = 12.0
	_menu_panel.offset_top = 70.0
	_menu_panel.offset_right = 196.0
	add_child(_menu_panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	_menu_panel.add_child(vb)
	var sign_out := Button.new()
	sign_out.text = "Sign Out"
	sign_out.custom_minimum_size = Vector2(176, 52)
	sign_out.focus_mode = Control.FOCUS_NONE
	sign_out.pressed.connect(func() -> void:
		_menu_panel.visible = false
		_on_exit_pressed())
	vb.add_child(sign_out)
	_menu_admin_btn = Button.new()
	_menu_admin_btn.text = "Admin"
	_menu_admin_btn.custom_minimum_size = Vector2(176, 52)
	_menu_admin_btn.focus_mode = Control.FOCUS_NONE
	_menu_admin_btn.visible = false # MOE only (kept in sync by _refresh_stats)
	_menu_admin_btn.pressed.connect(func() -> void:
		_menu_panel.visible = false
		_toggle_admin_panel())
	vb.add_child(_menu_admin_btn)

# ---------------------------------------------------------------------------
# Announcements: popup with OK + a loudspeaker button to re-read the latest.
# ---------------------------------------------------------------------------

func _build_announcement_popup() -> void:
	# PanelContainer so the popup grows to fit the message (fixed wrap width,
	# any height); _center_announcement_panel() re-centers it after layout.
	_announce_panel = PanelContainer.new()
	_announce_panel.name = "AnnouncementPanel"
	_announce_panel.visible = false
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.045, 0.94)
	style.border_color = HELP_GOLD
	style.set_border_width_all(2)
	style.set_corner_radius_all(12)
	_announce_panel.add_theme_stylebox_override("panel", style)
	add_child(_announce_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 26)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_right", 26)
	margin.add_theme_constant_override("margin_bottom", 18)
	_announce_panel.add_child(margin)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	margin.add_child(vb)
	var title := Label.new()
	title.text = "ANNOUNCEMENT"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 24)
	title.modulate = HELP_GOLD
	vb.add_child(title)
	_announce_label = Label.new()
	_announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_announce_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_announce_label.custom_minimum_size = Vector2(500, 0)
	_announce_label.add_theme_font_size_override("font_size", 22)
	_announce_label.modulate = Color(1.0, 0.96, 0.82)
	vb.add_child(_announce_label)
	var ok := Button.new()
	ok.text = "OK"
	ok.custom_minimum_size = Vector2(140, 52)
	ok.focus_mode = Control.FOCUS_NONE
	ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	ok.pressed.connect(_on_announcement_ok)
	vb.add_child(ok)

## Shrink the popup to its (new) content size, then center it on screen.
## Runs a frame after the text changes so the wrapped-label height is final.
func _center_announcement_panel() -> void:
	if _announce_panel == null or not _announce_panel.visible:
		return
	_announce_panel.reset_size()
	await get_tree().process_frame
	if _announce_panel == null or not _announce_panel.visible:
		return
	_announce_panel.position = (size - _announce_panel.size) * 0.5

func _on_announcement_received(id: String, message: String) -> void:
	_latest_announcement = {"id": id, "message": message}
	announce_button.visible = true
	# Auto-pop only when this broadcast hasn't been acknowledged on this device.
	if NetworkService.seen_announcement_id() != id:
		_show_announcement()

func _show_announcement() -> void:
	GameState.note_player_input()
	if _latest_announcement.is_empty():
		return
	_announce_label.text = str(_latest_announcement.get("message", ""))
	_announce_panel.visible = true
	_center_announcement_panel()

func _on_announcement_ok() -> void:
	_announce_panel.visible = false
	if not _latest_announcement.is_empty():
		NetworkService.mark_announcement_seen(str(_latest_announcement.get("id", "")))

## Three-bar menu icon (drawn in code — the theme font may lack ≡/☰ glyphs).
func _make_hamburger_icon() -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := Color(0.92, 0.94, 0.98)
	for row in [6, 11, 16]:
		for x in range(3, 21):
			for y in range(row, row + 3):
				img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

## Handheld megaphone icon: rear body + horn + pistol-grip handle, drawn in
## code (the default font has no emoji glyphs).
func _make_speaker_icon() -> ImageTexture:
	var img := Image.create(24, 24, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var col := HELP_GOLD
	# Rear body (rect) + horn (expanding triangle) pointing right; the speaker
	# sits high so the handle fits underneath.
	for x in range(3, 9):
		for y in range(8, 15):
			img.set_pixel(x, y, col)
	for x in range(9, 16):
		var half := 3 + int(float(x - 9) * 0.8)
		for y in range(11 - half, 12 + half):
			img.set_pixel(x, clampi(y, 0, 23), col)
	# Pistol-grip handle hanging below the rear body, slanted slightly forward.
	for i in 8:
		var hx := 5 + int(float(i) * 0.5)
		for w in 3:
			img.set_pixel(clampi(hx + w, 0, 23), clampi(15 + i, 0, 23), col)
	# Sound waves: three dashed arcs off the horn mouth.
	for i in 3:
		var x := 17 + i * 2
		var span := 4 + i * 3
		for y in range(11 - span, 12 + span, 2 + i):
			img.set_pixel(clampi(x, 0, 23), clampi(y, 0, 23), col)
	return ImageTexture.create_from_image(img)

func _build_help_overlay() -> void:
	_help_button = Button.new()
	_help_button.name = "HelpButton"
	_help_button.text = "?"
	_help_button.custom_minimum_size = Vector2(52, 52)
	_help_button.focus_mode = Control.FOCUS_NONE
	_help_button.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_help_button.offset_left = -26.0
	_help_button.offset_top = 12.0
	_help_button.offset_right = 26.0
	_help_button.offset_bottom = 64.0
	_help_button.add_theme_color_override("font_color", HELP_GOLD)
	_help_button.add_theme_color_override("font_hover_color", HELP_GOLD)
	_help_button.add_theme_color_override("font_pressed_color", HELP_GOLD)
	_help_button.add_theme_font_size_override("font_size", 30)
	_style_help_button()
	_help_button.button_down.connect(_show_help_text)
	_help_button.button_up.connect(_hide_help_text)
	add_child(_help_button)

	_help_panel = Panel.new()
	_help_panel.name = "HelpPanel"
	_help_panel.visible = false
	_help_panel.set_anchors_preset(Control.PRESET_CENTER)
	_help_panel.offset_left = -280.0
	_help_panel.offset_top = -130.0
	_help_panel.offset_right = 280.0
	_help_panel.offset_bottom = 130.0
	_help_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.02, 0.03, 0.045, 0.88)
	panel_style.border_color = HELP_GOLD
	panel_style.set_border_width_all(2)
	panel_style.set_corner_radius_all(12)
	_help_panel.add_theme_stylebox_override("panel", panel_style)
	add_child(_help_panel)

	_help_label = Label.new()
	_help_label.text = HELP_TEXT
	_help_label.modulate = Color(1.0, 0.96, 0.82)
	_help_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_help_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_help_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_help_label.add_theme_font_size_override("font_size", 22)
	_help_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_help_label.offset_left = 22.0
	_help_label.offset_top = 18.0
	_help_label.offset_right = -22.0
	_help_label.offset_bottom = -18.0
	_help_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_help_panel.add_child(_help_label)

func _style_help_button() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.03, 0.035, 0.045, 0.92)
	normal.border_color = HELP_GOLD
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(26)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(0.08, 0.07, 0.04, 0.95)
	var pressed := normal.duplicate() as StyleBoxFlat
	pressed.bg_color = Color(0.16, 0.11, 0.02, 0.98)
	for state in ["normal", "disabled", "focus"]:
		_help_button.add_theme_stylebox_override(state, normal)
	_help_button.add_theme_stylebox_override("hover", hover)
	_help_button.add_theme_stylebox_override("pressed", pressed)

func _show_help_text() -> void:
	if _help_panel:
		_help_panel.visible = true

func _hide_help_text() -> void:
	if _help_panel:
		_help_panel.visible = false

## Shift the full-rect HUD root inward by the browser's safe-area insets
## (notch, rounded corners, home indicator). CSS px are converted to design
## units: the short viewport side always equals 720 design units (see
## project.godot stretch settings), so design = css * 720 / min(vw, vh).
func _apply_safe_area() -> void:
	if not OS.has_feature("web"):
		return
	var raw: Variant = JavaScriptBridge.eval(
		"window.CreatureNet && window.CreatureNet.getSafeAreaJson ? window.CreatureNet.getSafeAreaJson() : ''", true)
	if typeof(raw) != TYPE_STRING or str(raw).is_empty():
		return
	var parsed: Variant = JSON.parse_string(str(raw))
	if typeof(parsed) != TYPE_DICTIONARY:
		return
	var d: Dictionary = parsed
	var short_side: float = minf(float(d.get("vw", 0.0)), float(d.get("vh", 0.0)))
	if short_side <= 0.0:
		return
	var to_design: float = 720.0 / short_side
	offset_left = float(d.get("left", 0.0)) * to_design
	offset_top = float(d.get("top", 0.0)) * to_design
	offset_right = -float(d.get("right", 0.0)) * to_design
	offset_bottom = -float(d.get("bottom", 0.0)) * to_design

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
	_update_move_hint(c)
	_update_money_buttons(c)

func _update_move_hint(c: Creature) -> void:
	if not move_hint or not move_hint.visible:
		return
	if c and c.is_moving:
		if _move_hint_deadline == 0:
			_move_hint_deadline = Time.get_ticks_msec() + 4000
	if _move_hint_deadline > 0 and Time.get_ticks_msec() >= _move_hint_deadline:
		move_hint.visible = false

## Show "Pick Up <thing>" when eligible money is in reach and "Drop"/"Combine"
## while carrying. Kept cheap: only touches the buttons when state changes.
func _update_money_buttons(c: Creature) -> void:
	if not pickup_button or not drop_button:
		return
	var can_pick: bool = c.can_pick_up_now() and not c.is_dead
	if pickup_button.visible != can_pick:
		pickup_button.visible = can_pick
	if can_pick:
		var pick_text: String = c.pickup_label()
		if pickup_button.text != pick_text:
			pickup_button.text = pick_text
	var carrying: bool = c.is_carrying()
	if drop_button.visible != carrying:
		drop_button.visible = carrying
	if carrying:
		var drop_text: String = c.drop_label()
		if drop_button.text != drop_text:
			drop_button.text = drop_text
	# Steal appears next to a remote player who's hauling loot we can take.
	var can_steal: bool = c.can_steal_now() and not c.is_dead
	if steal_button.visible != can_steal:
		steal_button.visible = can_steal
	if can_steal:
		var steal_text: String = c.steal_label()
		if steal_button.text != steal_text:
			steal_button.text = steal_text
	# Eat Human appears next to Become Human when an alien stands by an NPC.
	var can_eat: bool = c.has_method("can_eat_human_now") and c.can_eat_human_now()
	if eat_button and eat_button.visible != can_eat:
		eat_button.visible = can_eat
	# House context action: Upgrade House / Take Vault / Rob.
	var act: Dictionary = c.house_action() if c.has_method("house_action") else {}
	var show_house: bool = not act.is_empty() and not c.is_dead
	if house_button.visible != show_house:
		house_button.visible = show_house
	if show_house:
		var house_label := str(act.get("label", ""))
		if house_button.text != house_label:
			house_button.text = house_label
	# The house special toggles between Claim/Unclaim as state changes.
	if c.form_key == FormDefs.HOUSE:
		var house_text: String = c.house_special_label()
		if special_button.text != house_text:
			special_button.text = house_text

func _setup_action_buttons() -> void:
	become_button.visible = false
	special_button.visible = false
	pop_button.visible = false
	pickup_button.visible = false
	drop_button.visible = false
	steal_button.visible = false
	eat_button.visible = false
	house_button.visible = false
	become_button.focus_mode = Control.FOCUS_NONE
	special_button.focus_mode = Control.FOCUS_NONE
	pop_button.focus_mode = Control.FOCUS_NONE
	pickup_button.focus_mode = Control.FOCUS_NONE
	drop_button.focus_mode = Control.FOCUS_NONE
	steal_button.focus_mode = Control.FOCUS_NONE
	eat_button.focus_mode = Control.FOCUS_NONE
	house_button.focus_mode = Control.FOCUS_NONE
	become_button.pressed.connect(_on_become_pressed)
	special_button.pressed.connect(_on_special_pressed)
	pop_button.pressed.connect(_on_pop_pressed)
	pickup_button.pressed.connect(_on_pickup_pressed)
	drop_button.pressed.connect(_on_drop_pressed)
	steal_button.pressed.connect(_on_steal_pressed)
	eat_button.pressed.connect(_on_eat_pressed)
	house_button.pressed.connect(_on_house_pressed)

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
		FormDefs.PROPANE, FormDefs.BBQ_GRILL:
			special_button.visible = true
			special_button.text = "Detonate"
		FormDefs.PYRAMID:
			# Illegible alien glyphs — what does it do? Press it and find out.
			special_button.visible = true
			special_button.text = "ΞΘΨΔ"
		FormDefs.HOUSE:
			special_button.visible = true
			special_button.text = "Claim Safe House"
		FormDefs.MEMPHIS_BEAR:
			special_button.visible = true
			special_button.text = "Climb Tree"
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

func _on_house_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("do_house_action"):
		c.do_house_action()

func _on_drop_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("drop_all"):
		c.drop_all()

func _on_steal_pressed() -> void:
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("steal_from_nearest"):
		c.steal_from_nearest()

func _on_eat_pressed() -> void:
	GameState.note_player_input()
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("eat_nearest_human"):
		c.eat_nearest_human()

# ---------------------------------------------------------------------------
# Respawn destination choice (Slice 7): shown after the death countdown when
# the player owns a claimed safe house.
# ---------------------------------------------------------------------------

func _build_respawn_choice() -> void:
	_respawn_panel = VBoxContainer.new()
	_respawn_panel.name = "RespawnChoice"
	_respawn_panel.visible = false
	_respawn_panel.set_anchors_preset(Control.PRESET_CENTER)
	_respawn_panel.offset_left = -130.0
	_respawn_panel.offset_right = 130.0
	_respawn_panel.offset_top = -70.0
	_respawn_panel.offset_bottom = 70.0
	_respawn_panel.add_theme_constant_override("separation", 14)
	var title := Label.new()
	title.text = "RESPAWN AT:"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn_panel.add_child(title)
	var safe_btn := Button.new()
	safe_btn.text = "Safe House"
	safe_btn.custom_minimum_size = Vector2(260, 52)
	safe_btn.focus_mode = Control.FOCUS_NONE
	safe_btn.pressed.connect(func(): _choose_respawn("safe"))
	_respawn_panel.add_child(safe_btn)
	var dump_btn := Button.new()
	dump_btn.text = "The Dump"
	dump_btn.custom_minimum_size = Vector2(260, 52)
	dump_btn.focus_mode = Control.FOCUS_NONE
	dump_btn.pressed.connect(func(): _choose_respawn("dump"))
	_respawn_panel.add_child(dump_btn)
	add_child(_respawn_panel)

func _on_respawn_choice_requested(show: bool) -> void:
	_respawn_panel.visible = show

func _choose_respawn(choice: String) -> void:
	_respawn_panel.visible = false
	var c = GameState.player_creature
	if c and is_instance_valid(c) and c.has_method("choose_respawn"):
		c.choose_respawn(choice)

func bind_pain_test(pain_test: Node) -> void:
	_pain_test = pain_test

func bind_main(main: Node) -> void:
	_main = main

func _on_exit_pressed() -> void:
	GameState.note_player_input()
	if _main and is_instance_valid(_main) and _main.has_method("logout_to_onboarding"):
		_main.logout_to_onboarding()
	elif _main and is_instance_valid(_main):
		_main.get_tree().reload_current_scene()

func consumes_pointer_at(screen_pos: Vector2) -> bool:
	if menu_button and menu_button.get_global_rect().has_point(screen_pos):
		return true
	if announce_button and announce_button.visible and announce_button.get_global_rect().has_point(screen_pos):
		return true
	if _menu_panel and _menu_panel.visible and _menu_panel.get_global_rect().has_point(screen_pos):
		return true
	if _announce_panel and _announce_panel.visible and _announce_panel.get_global_rect().has_point(screen_pos):
		return true
	if _help_button and _help_button.get_global_rect().has_point(screen_pos):
		return true
	if _help_panel and _help_panel.visible and _help_panel.get_global_rect().has_point(screen_pos):
		return true
	if _admin_panel and _admin_panel.visible and _admin_panel.get_global_rect().has_point(screen_pos):
		return true
	for btn in [become_button, special_button, pop_button, pickup_button, drop_button, steal_button, eat_button, house_button]:
		if btn and btn.visible and btn.get_global_rect().has_point(screen_pos):
			return true
	if _respawn_panel and _respawn_panel.visible and _respawn_panel.get_global_rect().has_point(screen_pos):
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

	# Close button pinned to the panel's top-right corner (above the content).
	var close_btn := Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(48, 48)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	close_btn.offset_left = -56.0
	close_btn.offset_top = 8.0
	close_btn.offset_right = -8.0
	close_btn.offset_bottom = 56.0
	close_btn.pressed.connect(func() -> void: _admin_panel.visible = false)
	_admin_panel.add_child(close_btn)

	_test_mode_toggle = CheckButton.new()
	_test_mode_toggle.text = "Test mode (tap to teleport)"
	_test_mode_toggle.button_pressed = GameState.admin_test_mode
	_test_mode_toggle.toggled.connect(_on_test_mode_toggled)
	root.add_child(_test_mode_toggle)

	var worm_row := _make_spin_row("Worms", 0, 100, 100)
	root.add_child(worm_row)
	_worm_spin = worm_row.get_node("Spin") as SpinBox

	var object_row := _make_spin_row("Objects", 0, 250, 250)
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
	spawn_stacks_btn.text = "spawn 20 stacks"
	spawn_stacks_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	spawn_stacks_btn.pressed.connect(_on_spawn_stacks_pressed)
	money_row.add_child(spawn_stacks_btn)

	var reset_objects_btn := Button.new()
	reset_objects_btn.text = "reset ALL world objects"
	reset_objects_btn.pressed.connect(_on_reset_objects_pressed)
	root.add_child(reset_objects_btn)

	# Broadcast an announcement to every player (popup with OK on their end).
	var announce_row := HBoxContainer.new()
	announce_row.add_theme_constant_override("separation", 8)
	root.add_child(announce_row)
	_announce_input = LineEdit.new()
	_announce_input.placeholder_text = "announcement message"
	_announce_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	announce_row.add_child(_announce_input)
	var broadcast_btn := Button.new()
	broadcast_btn.text = "broadcast"
	broadcast_btn.pressed.connect(_on_broadcast_pressed)
	announce_row.add_child(broadcast_btn)

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
	var created: Array = await NetworkService.admin_spawn_money_stacks(20)
	GameState.show_toast("Spawned %d money stacks" % created.size())

func _on_test_mode_toggled(enabled: bool) -> void:
	if not _is_admin_player():
		GameState.admin_test_mode = false
		if _test_mode_toggle:
			_test_mode_toggle.button_pressed = false
		return
	GameState.admin_test_mode = enabled
	GameState.show_toast("Test mode: tap to teleport" if enabled else "Test mode off")

func _on_reset_objects_pressed() -> void:
	if not NetworkService.is_online():
		GameState.show_toast("Offline — can't reset shared objects")
		return
	var ok: bool = await NetworkService.admin_reset_world_objects()
	GameState.show_toast("World objects reset" if ok else "Reset failed — see logs")

func _on_broadcast_pressed() -> void:
	if not _is_admin_player():
		return
	var msg := _announce_input.text.strip_edges()
	if msg.is_empty():
		GameState.show_toast("Type an announcement first")
		return
	if not NetworkService.is_online():
		GameState.show_toast("Offline — can't broadcast")
		return
	var ok: bool = await NetworkService.create_announcement(msg)
	GameState.show_toast("Announcement broadcast!" if ok else "Broadcast failed — see logs")
	if ok:
		_announce_input.text = ""

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
	label.text = "%s  -  %s" % [profile_name, _format_last_login(str(row.get("last_active", "")))]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	item.add_child(label)
	var delete_btn := Button.new()
	delete_btn.text = "delete"
	delete_btn.pressed.connect(func(): _delete_profile(creature_id, profile_name))
	item.add_child(delete_btn)
	_profiles_list.add_child(item)

## Supabase `last_active` (ISO 8601 UTC) → "YYYY-MM-DD HH:MM" in device-local
## time for the admin profile list.
func _format_last_login(iso: String) -> String:
	if iso.is_empty() or iso == "<null>":
		return "never"
	# Trim fractional seconds / timezone suffix; Supabase stores UTC.
	var trimmed := iso
	for sep in [".", "+", "Z"]:
		var idx := trimmed.find(sep)
		if idx >= 0:
			trimmed = trimmed.substr(0, idx)
	var unix := Time.get_unix_time_from_datetime_string(trimmed)
	if unix <= 0:
		return iso
	unix += int(Time.get_time_zone_from_system().get("bias", 0)) * 60
	var stamp := Time.get_datetime_string_from_unix_time(unix).replace("T", " ")
	return stamp.substr(0, 16) # drop the seconds

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
		if _menu_admin_btn:
			_menu_admin_btn.visible = false
		return
	name_label.text = c.creature_name
	if top_bar and name_label:
		var fs := name_label.get_theme_font_size("font_size")
		var font := name_label.get_theme_font("font")
		if font:
			var text_w := font.get_string_size(
				name_label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
			top_bar.offset_right = top_bar.offset_left + clampf(text_w + 24.0, 120.0, 180.0)
	# Admin lives in the menu dropdown now — MOE only.
	if _menu_admin_btn:
		_menu_admin_btn.visible = _is_admin_player()
	if not _is_admin_player() and _admin_panel and _admin_panel.visible:
		_admin_panel.visible = false

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_panel.visible = true
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(func(): toast_panel.visible = false)
