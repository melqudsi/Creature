extends Node3D

@onready var world_map: WorldMap = $WorldMap
@onready var rts_camera: Camera3D = $RTSCamera
@onready var hud: Control = $CanvasLayer/SC2Hud

func _ready() -> void:
	GameState.check_afk_sleep()
	var player: Creature = world_map.get_player_creature()
	if rts_camera.has_method("bind_world_map"):
		rts_camera.bind_world_map(world_map)
	if player:
		rts_camera.set_follow(player)

func _process(_delta: float) -> void:
	GameState.check_afk_sleep()

func _unhandled_input(event: InputEvent) -> void:
	_forward_pointer_input(event)

func _input(event: InputEvent) -> void:
	# Web mobile often delivers taps as emulated mouse before unhandled routing.
	if event is InputEventMouseButton or event is InputEventScreenTouch or event is InputEventScreenDrag:
		_forward_pointer_input(event)

func _forward_pointer_input(event: InputEvent) -> void:
	if not rts_camera.has_method("process_pointer_input"):
		return
	if rts_camera.process_pointer_input(event):
		get_viewport().set_input_as_handled()
