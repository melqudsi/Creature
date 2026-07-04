class_name NpcTraffic
extends Node3D

## Ambient NPC traffic: Altimas (mostly) and MATA buses driving both lanes of
## every road, u-turning at road ends. CLIENT-LOCAL — like kills, traffic is
## not synced between players (each client sees its own cars; only whether OUR
## player gets run over matters, matching the kill-matrix networking rule).
##
## A moving NPC vehicle kills exactly what a moving player-driven one would
## (FormDefs.resolve_player_death) — crossing the street is now a hazard.
##
## Slice 5: vehicles BRAKE for a player standing in their lane. While one is
## stopped an alien can shapeshift into it (it converts into a shared world
## object). But NPC drivers have Memphis patience: block one too long and it
## drives THROUGH you.

const TARGET_ALTIMAS := 26
const TARGET_BUSES := 5
const ALTIMA_SPEED := 3.2
const BUS_SPEED := 2.0
## Lanes sit half a tile either side of the divider on a 2-tile road.
const LANE_OFFSET := 0.5

## How far ahead (tiles) a vehicle scans for a player in its lane.
const STOP_LOOKAHEAD := 2.4
## Lateral distance from the lane line that still counts as "in the way".
const STOP_LATERAL := 0.8
## How long a vehicle waits at a full stop before driving through the player.
const PATIENCE_SEC := 8.5
const ACCEL := 2.6         # tiles/s^2 pulling away
const BRAKE := 7.0         # tiles/s^2 stopping (must out-brake STOP_LOOKAHEAD)
## Below this speed a vehicle is harmless and claimable (matches the
## "parked vehicles are safe" rule).
const SAFE_SPEED := 0.35
## An alien must be this close to a stopped vehicle to Become it.
const CLAIM_RADIUS := 1.6

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
		"cur_speed": 0.0,
		"wait": 0.0,
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
	var player_ok: bool = player != null and is_instance_valid(player) \
		and not player.is_dead and not player.is_spawning
	for v in _vehicles:
		var road: Dictionary = v["road"]
		var length := float(road["length"])
		# Brake for a live player in our lane — until patience runs out, then
		# the driver leans on the horn and goes (squish rule).
		var blocked := player_ok and _player_in_path(v, player)
		var target_speed: float = float(v["speed"])
		if blocked:
			v["wait"] = float(v["wait"]) + delta
			if float(v["wait"]) < PATIENCE_SEC:
				target_speed = 0.0
		else:
			v["wait"] = 0.0
		var cur := float(v["cur_speed"])
		if cur < target_speed:
			cur = minf(cur + ACCEL * delta, target_speed)
		else:
			cur = maxf(cur - BRAKE * delta, target_speed)
		v["cur_speed"] = cur
		v["along"] = float(v["along"]) + cur * float(v["dir"]) * delta
		# U-turn at either end of the road (into the opposite lane).
		if float(v["along"]) >= length - 0.6:
			v["along"] = length - 0.6
			v["dir"] = -1
		elif float(v["along"]) <= 0.6:
			v["along"] = 0.6
			v["dir"] = 1
		_place(v, false)
		# A crawling/stopped vehicle is harmless (parked-vehicle rule).
		if player_ok and cur > SAFE_SPEED:
			_check_kill(v, player)

## True when the player stands within the vehicle's forward stopping zone.
func _player_in_path(v: Dictionary, player: Creature) -> bool:
	var node: Node3D = v["node"]
	var road: Dictionary = v["road"]
	var dir := float(v["dir"])
	var ahead: float
	var lateral: float
	if road["horizontal"]:
		ahead = (player.position.x - node.position.x) * dir
		lateral = absf(player.position.z - node.position.z)
	else:
		ahead = (player.position.z - node.position.z) * dir
		lateral = absf(player.position.x - node.position.x)
	var front := 0.75 if v["is_bus"] else 0.55
	return ahead > front * 0.5 and ahead < STOP_LOOKAHEAD * GameConfig.TILE_SIZE \
		and lateral < STOP_LATERAL * GameConfig.TILE_SIZE

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

# ---------------------------------------------------------------------------
# Claiming (shapeshift into a stopped NPC vehicle)
# ---------------------------------------------------------------------------

## The nearest fully-stopped vehicle within CLAIM_RADIUS of `pos` (world XZ),
## or {} if none. The dict is a live internal entry — pass it to claim_vehicle.
func claimable_vehicle(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := CLAIM_RADIUS * GameConfig.TILE_SIZE
	for v in _vehicles:
		if float(v["cur_speed"]) > SAFE_SPEED * 0.5:
			continue
		var node: Node3D = v["node"]
		var d := pos.distance_to(Vector2(node.position.x, node.position.z))
		if d < best_d:
			best_d = d
			best = v
	return best

func vehicle_display(v: Dictionary) -> String:
	return "MATA Bus" if v.get("is_bus", false) else "Altima"

func vehicle_world_pos(v: Dictionary) -> Vector3:
	var node: Node3D = v["node"]
	return node.position

func is_vehicle_claimable(v: Dictionary) -> bool:
	return not v.is_empty() and _vehicles.has(v) and float(v["cur_speed"]) <= SAFE_SPEED

## Remove the NPC from local traffic (the claimer converts it into a shared
## world object) and respawn a fresh one elsewhere so traffic density holds.
func claim_vehicle(v: Dictionary) -> void:
	var idx := _vehicles.find(v)
	if idx < 0:
		return
	_vehicles.remove_at(idx)
	var node: Node3D = v["node"]
	if is_instance_valid(node):
		node.queue_free()
	_spawn_vehicle(bool(v["is_bus"]))

## Pyramid abduction: vehicles near the beam get taken. Each rises into the sky
## (tween) and a replacement spawns elsewhere so traffic density holds.
func abduct_near(world_pos: Vector3, radius_tiles: float) -> void:
	var center := Vector2(world_pos.x, world_pos.z)
	var r := radius_tiles * GameConfig.TILE_SIZE
	for v in _vehicles.duplicate():
		var node: Node3D = v["node"]
		if not is_instance_valid(node):
			continue
		if center.distance_to(Vector2(node.position.x, node.position.z)) > r:
			continue
		var idx := _vehicles.find(v)
		if idx >= 0:
			_vehicles.remove_at(idx)
		var tw := node.create_tween()
		tw.set_parallel(true)
		tw.tween_property(node, "position:y", 9.0, 2.2).set_ease(Tween.EASE_IN)
		tw.tween_property(node, "rotation:y", node.rotation.y + TAU * 1.5, 2.2)
		tw.tween_property(node, "scale", Vector3(0.1, 0.1, 0.1), 2.2).set_ease(Tween.EASE_IN)
		tw.chain().tween_callback(node.queue_free)
		_spawn_vehicle(bool(v["is_bus"]))

## True when any NPC vehicle moving fast enough would hit `world_pos`.
func hits_position_at_speed(world_pos: Vector3, radius: float) -> bool:
	var center := Vector2(world_pos.x, world_pos.z)
	for v in _vehicles:
		if float(v["cur_speed"]) <= SAFE_SPEED:
			continue
		var node: Node3D = v["node"]
		if not is_instance_valid(node):
			continue
		var vehicle_r := 0.75 if v.get("is_bus", false) else 0.55
		if center.distance_to(Vector2(node.position.x, node.position.z)) <= vehicle_r + radius:
			return true
	return false

