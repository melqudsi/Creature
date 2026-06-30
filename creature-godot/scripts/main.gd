extends Node3D

@onready var world_map: WorldMap = $WorldMap
@onready var rts_camera: Camera3D = $RTSCamera
@onready var hud: Control = $CanvasLayer/SC2Hud
@onready var pain_test: Node = $PainTest

func _ready() -> void:
	await NetworkService.boot()
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
	if hud.has_method("consumes_pointer_at") and hud.consumes_pointer_at(screen_pos):
		return true
	return false
