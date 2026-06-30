extends Node3D

@onready var world_map: WorldMap = $WorldMap
@onready var rts_camera: Camera3D = $RTSCamera
@onready var hud: Control = $CanvasLayer/SC2Hud
@onready var pain_test: Node = $PainTest

const ONBOARDING_SCENE := preload("res://scenes/ui/creature_create.tscn")

var _onboarding: Control
var _world_started := false

func _ready() -> void:
	await NetworkService.boot()
	if GameState.player_data.is_empty():
		_show_onboarding()
		return
	_enter_world()

func _show_onboarding() -> void:
	hud.visible = false
	_onboarding = ONBOARDING_SCENE.instantiate() as Control
	$CanvasLayer.add_child(_onboarding)
	if _onboarding.has_signal("profile_ready"):
		_onboarding.profile_ready.connect(_on_profile_ready)

func _on_profile_ready() -> void:
	if _onboarding and is_instance_valid(_onboarding):
		_onboarding.queue_free()
	_onboarding = null
	_enter_world()

func _enter_world() -> void:
	if _world_started:
		return
	_world_started = true
	hud.visible = true
	world_map.spawn_player()
	if NetworkService.is_online():
		NetworkService.start_creature_poll(world_map)
	var player: Creature = world_map.get_player_creature()
	if rts_camera.has_method("bind_world_map"):
		rts_camera.bind_world_map(world_map)
	if player:
		rts_camera.set_follow(player)
	if hud.has_method("bind_pain_test"):
		hud.bind_pain_test(pain_test)

func _unhandled_input(event: InputEvent) -> void:
	_forward_pointer_input(event)

func _input(event: InputEvent) -> void:
	# Web mobile often delivers taps as emulated mouse before unhandled routing.
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag:
		_forward_pointer_input(event)

func _forward_pointer_input(event: InputEvent) -> void:
	if _is_ui_pointer_event(event):
		return
	if not rts_camera.has_method("process_pointer_input"):
		return
	if rts_camera.process_pointer_input(event):
		get_viewport().set_input_as_handled()

func _is_ui_pointer_event(event: InputEvent) -> bool:
	var screen_pos := Vector2.ZERO
	if event is InputEventScreenTouch:
		screen_pos = event.position
	elif event is InputEventMouseButton:
		screen_pos = event.position
	else:
		return false
	if _onboarding and is_instance_valid(_onboarding) and _onboarding.visible:
		return true
	if hud.has_method("consumes_pointer_at") and hud.consumes_pointer_at(screen_pos):
		return true
	return false
