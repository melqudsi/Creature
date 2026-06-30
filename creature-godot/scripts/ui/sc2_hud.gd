extends Control

@onready var name_label: Label = $TopBar/NameLabel
@onready var hp_bar: ProgressBar = $TopBar/HPBar
@onready var st_bar: ProgressBar = $TopBar/STBar
@onready var toast_panel: Panel = $ToastPanel
@onready var toast_label: Label = $ToastPanel/ToastLabel

func _ready() -> void:
	theme = preload("res://assets/themes/sc2_theme.tres")
	toast_panel.visible = false
	GameState.player_stats_changed.connect(_refresh_stats)
	GameState.toast_requested.connect(_show_toast)
	call_deferred("_refresh_stats")

func _refresh_stats() -> void:
	var c = GameState.player_creature
	if not c:
		return
	name_label.text = c.creature_name
	hp_bar.value = c.health
	st_bar.value = c.stamina

func _show_toast(msg: String) -> void:
	toast_label.text = msg
	toast_panel.visible = true
	var tween := create_tween()
	tween.tween_interval(4.0)
	tween.tween_callback(func(): toast_panel.visible = false)
