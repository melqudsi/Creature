extends Node

@export var enabled := false
@export var wander_interval_min := 2.0
@export var wander_interval_max := 5.0

var _creature: Creature
var _timer := 1.0
var _move_target := Vector2.ZERO

func _ready() -> void:
	_creature = get_parent() as Creature
	_reset_timer()

func _process(delta: float) -> void:
	if not enabled or not is_instance_valid(_creature):
		return
	if _creature.is_asleep or _creature.is_moving:
		return
	_timer -= delta
	if _timer <= 0.0:
		_reset_timer()
		var tx := randi_range(1, GameConfig.MAP_W - 2)
		var ty := randi_range(1, GameConfig.MAP_H - 2)
		_creature.set_move_target(Vector2(tx, ty))

func _reset_timer() -> void:
	_timer = randf_range(wander_interval_min, wander_interval_max)
