class_name NpcTraffic
extends Node3D

## Ambient NPC traffic: Altimas (mostly) and MATA buses driving both lanes of
## every road, u-turning at road ends. CLIENT-LOCAL — like kills, traffic is
## not synced between players (each client sees its own cars; only whether OUR
## player gets run over matters, matching the kill-matrix networking rule).
##
## A moving NPC vehicle kills exactly what a moving player-driven one would
## (FormDefs.resolve_player_death) — crossing the street is now a hazard.

const TARGET_ALTIMAS := 26
const TARGET_BUSES := 5
const ALTIMA_SPEED := 3.2
const BUS_SPEED := 2.0
## Lanes sit half a tile either side of the divider on a 2-tile road.
const LANE_OFFSET := 0.5

var _vehicles: Array[Dictionary] = []
var _roads: Array[Dictionary] = []

func _ready() -> void:
	# Traffic drives every road, including the bridge deck.
	for r in MemphisLayout.ROADS:
		var rect: Rect2i = r["rect"]
		var horizontal: bool = rect.size.x >= rect.size.y
		_roads.append({
			"rect": rect,
			"horizontal": horizontal,
			"length": rect.size.x if horizontal else rect.size.y,
		})
	for i in TARGET_ALTIMAS:
		_spawn_vehicle(false)
	for i in TARGET_BUSES:
		_spawn_vehicle(true)

func _spawn_vehicle(is_bus: bool) -> void:
	# Weight road choice by length so long roads get proportional traffic.
	var total := 0
	for r in _roads:
		total += int(r["length"])
	var pick := randi_range(0, total - 1)
	var road: Dictionary = _roads[0]
	for r in _roads:
		pick -= int(r["length"])
		if pick < 0:
			road = r
			break
	var dir := 1 if randf() < 0.5 else -1
	var v := {
		"node": _make_node(is_bus),
		"road": road,
		"dir": dir,
		"is_bus": is_bus,
		"speed": BUS_SPEED if is_bus else ALTIMA_SPEED,
		"along": randf_range(1.0, float(road["length"]) - 1.0),
	}
	_vehicles.append(v)
	_place(v, true)

func _make_node(is_bus: bool) -> Node3D:
	var node := Node3D.new()
	node.add_child(ObjectMesh.build("mata_bus" if is_bus else "altima"))
	add_child(node)
	return node

## Axis math: `along` is the distance (tiles) from the road rect's origin along
## its long axis. Right-hand traffic: the lane offset flips with direction.
func _place(v: Dictionary, snap: bool) -> void:
	var road: Dictionary = v["road"]
	var rect: Rect2i = road["rect"]
	var horizontal: bool = road["horizontal"]
	var dir: int = v["dir"]
	var node: Node3D = v["node"]
	var lane := LANE_OFFSET * float(dir)
	var wx: float
	var wz: float
	var yaw: float
	if horizontal:
		wx = (rect.position.x + float(v["along"])) * GameConfig.TILE_SIZE
		wz = (rect.position.y + rect.size.y * 0.5 + lane) * GameConfig.TILE_SIZE
		yaw = atan2(float(dir), 0.0)
	else:
		wx = (rect.position.x + rect.size.x * 0.5 - lane) * GameConfig.TILE_SIZE
		wz = (rect.position.y + float(v["along"])) * GameConfig.TILE_SIZE
		yaw = atan2(0.0, float(dir))
	var target := Vector3(wx, 0.0, wz)
	if snap:
		node.position = target
		node.rotation.y = yaw
	else:
		# Smooth toward the lane target so u-turns arc instead of teleporting
		# sideways into the opposite lane.
		node.position = node.position.lerp(target, 0.14)
		node.rotation.y = lerp_angle(node.rotation.y, yaw, 0.12)

func _process(delta: float) -> void:
	var player := GameState.player_creature
	var check_kills: bool = player != null and is_instance_valid(player) \
		and not player.is_dead and not player.is_spawning
	for v in _vehicles:
		var road: Dictionary = v["road"]
		var length := float(road["length"])
		v["along"] = float(v["along"]) + float(v["speed"]) * float(v["dir"]) * delta
		# U-turn at either end of the road (into the opposite lane).
		if float(v["along"]) >= length - 0.6:
			v["along"] = length - 0.6
			v["dir"] = -1
		elif float(v["along"]) <= 0.6:
			v["along"] = 0.6
			v["dir"] = 1
		_place(v, false)
		if check_kills:
			_check_kill(v, player)

func _check_kill(v: Dictionary, player: Creature) -> void:
	var node: Node3D = v["node"]
	var d := Vector2(node.position.x, node.position.z).distance_to(
		Vector2(player.position.x, player.position.z))
	var vehicle_r := 0.75 if v["is_bus"] else 0.55
	if d > vehicle_r + FormDefs.radius(player.form_key):
		return
	var other_kind := "mata_bus" if v["is_bus"] else "vehicle"
	var res := FormDefs.resolve_player_death(player.form_key, other_kind)
	if res.die:
		if res.explode:
			GameState.explosion_requested.emit(player.position, Creature.EXPLOSION_RADIUS)
		player.apply_death(res.reason, res.explode)
