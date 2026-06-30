extends Node3D

var world_map: Node3D
var rts_camera: Camera3D
var canvas_layer: CanvasLayer
var hud: Control
var pain_test: Node

const ONBOARDING_SCENE := preload("res://scenes/ui/creature_create.tscn")

var _onboarding: Control
var _world_started := false

func _ready() -> void:
	_resolve_scene_nodes()
	await NetworkService.boot()
	_resolve_scene_nodes()
	if GameState.player_data.is_empty():
		_show_onboarding()
		return
	_enter_world()

func _resolve_scene_nodes() -> void:
	var scene_root := get_tree().current_scene if get_tree() else null
	var root := scene_root if scene_root else self
	world_map = root.get_node_or_null("WorldMap") as Node3D
	rts_camera = root.get_node_or_null("RTSCamera") as Camera3D
	canvas_layer = root.get_node_or_null("CanvasLayer") as CanvasLayer
	hud = root.get_node_or_null("CanvasLayer/SC2Hud") as Control
	pain_test = root.get_node_or_null("PainTest")

func _show_onboarding() -> void:
	if hud:
		hud.visible = false
	_onboarding = ONBOARDING_SCENE.instantiate() as Control
	if canvas_layer:
		canvas_layer.add_child(_onboarding)
	else:
		add_child(_onboarding)
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
	_resolve_scene_nodes()
	if not world_map or not rts_camera:
		push_error("Main scene missing WorldMap or RTSCamera; cannot enter world.")
		return
	_world_started = true
	if hud:
		hud.visible = true
	if world_map.has_method("spawn_player"):
		world_map.spawn_player()
	if NetworkService.is_online():
		NetworkService.start_creature_poll(world_map)
	var player: Creature = null
	if world_map.has_method("get_player_creature"):
		player = world_map.get_player_creature()
	if rts_camera.has_method("bind_world_map"):
		rts_camera.bind_world_map(world_map)
	if player:
		rts_camera.set_follow(player)
	if hud and hud.has_method("bind_pain_test"):
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
	if hud and hud.has_method("consumes_pointer_at") and hud.consumes_pointer_at(screen_pos):
		return true
	return false
