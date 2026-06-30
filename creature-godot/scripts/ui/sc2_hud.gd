extends Control

@onready var name_label: Label = $TopBar/NameLabel
@onready var toast_panel: Panel = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel
@onready var pain_test_button: Button = $PainTestButton

var _pain_test: Node

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	toast_panel.visible = false
	pain_test_button.pressed.connect(_on_pain_test_pressed)
	GameState.player_stats_changed.connect(_refresh_stats)
	GameState.toast_requested.connect(_show_toast)
	call_deferred("_refresh_stats")

func bind_pain_test(pain_test: Node) -> void:
	_pain_test = pain_test

func consumes_pointer_at(screen_pos: Vector2) -> bool:
	if not pain_test_button.visible:
		return false
	return pain_test_button.get_global_rect().has_point(screen_pos)

func _on_pain_test_pressed() -> void:
	if _pain_test and _pain_test.has_method("start"):
		if _pain_test.is_active():
			return
		_pain_test.start()
		pain_test_button.text = "pain..."
		pain_test_button.disabled = true
		await get_tree().create_timer(30.0).timeout
		pain_test_button.text = "pain test"
		pain_test_button.disabled = false

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
