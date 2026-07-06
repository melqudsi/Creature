class_name NpcHumans
extends Node3D

## Ambient human NPCs (Slice 9). CLIENT-LOCAL, like traffic and zoo animals:
## each client sees its own pedestrians; only whether OUR player interacts
## (eats / becomes / squishes one) matters.
##
## Behavior:
## - Most humans walk the sidewalk lanes that flank every street. At a lane
##   end (or a random whim) they turn, hop onto a crossing sidewalk, or step
##   off into the grass for a while — no back-and-forth ping-pong loops.
## - Some are full-time roamers wandering open ground.
## - Calm humans NEVER path onto a road tile. Panicked humans forget that
##   rule entirely — and NPC traffic does not brake for them.
## - Panic: an ALIEN-form creature inside their forward vision cone sends
##   them sprinting away, arms up. Approach from behind and they never see
##   you. Players disguised as vehicles/objects/humans don't scare anyone.
## - They die to anything lethal: NPC vehicles, moving player vehicles and
##   buses, moving player zoo predators, and explosions. A replacement
##   spawns elsewhere so the population holds.

const TARGET_HUMANS := 40
const WALK_SPEED := 0.55
const PANIC_SPEED := 1.75
const CLAIM_RADIUS := 1.35
## Squished/eaten humans reseed elsewhere after a while; a shapeshift claim
## backfills faster since nothing gory happened.
const RESPAWN_DELAY_KILL := 14.0
const RESPAWN_DELAY_CLAIM := 4.0
## Vision: distance (tiles) and half-angle of the forward cone.
const VIEW_DIST := 4.5
const VIEW_HALF_ANGLE_DEG := 70.0
## Once spooked they keep running at least this long after losing sight.
const PANIC_LINGER_SEC := 2.6
const PAUSE_MIN := 0.8
const PAUSE_MAX := 2.6
## Fraction of the population that roams open ground instead of sidewalks.
const ROAMER_SHARE := 0.3
## Sidewalks sit 1.16 tiles off the road centerline (world_map._add_sidewalks).
const LANE_OFFSET := 1.16

var _humans: Array[Dictionary] = []
var _lanes: Array[Dictionary] = []

func _ready() -> void:
	_build_lanes()
	for i in TARGET_HUMANS:
		_spawn_human()

## One walkable lane per sidewalk strip: two per street, along its long axis.
## `cross` is the fixed tile coordinate on the short axis.
func _build_lanes() -> void:
	for r in MemphisLayout.ROADS:
		if str(r.get("kind", "")) != "street":
			continue
		var rect: Rect2i = r["rect"]
		var horizontal := rect.size.x >= rect.size.y
		var center := (float(rect.position.y) + float(rect.size.y) * 0.5) if horizontal \
			else (float(rect.position.x) + float(rect.size.x) * 0.5)
		for side in [-1.0, 1.0]:
			_lanes.append({
				"horizontal": horizontal,
				"start": float(rect.position.x if horizontal else rect.position.y),
				"length": float(rect.size.x if horizontal else rect.size.y),
				# -0.5: lane math runs in fractional TILE coords (tile_to_world
				# adds the half-tile), but the sidewalk strip is drawn at
				# road-center ± offset in WORLD coords.
				"cross": center - 0.5 + side * LANE_OFFSET,
			})

func _lane_point(lane: Dictionary, along: float) -> Vector2:
	if lane["horizontal"]:
		return Vector2(float(lane["start"]) + along, float(lane["cross"]))
	return Vector2(float(lane["cross"]), float(lane["start"]) + along)

func _spawn_human() -> void:
	# Weight lane choice by length so long streets get proportional foot traffic.
	var total := 0.0
	for l in _lanes:
		total += float(l["length"])
	var pick := randf() * total
	var lane: Dictionary = _lanes[0]
	for l in _lanes:
		pick -= float(l["length"])
		if pick <= 0.0:
			lane = l
			break
	var along := randf_range(0.5, float(lane["length"]) - 0.5)
	var tile := _lane_point(lane, along)
	var params := ObjectMesh.random_human_params()
	var node := Node3D.new()
	var mesh := ObjectMesh.build_human(params)
	node.add_child(mesh)
	add_child(node)
	var wp := GameConfig.tile_to_world(tile)
	node.position = Vector3(wp.x, 0, wp.z)
	var roamer := randf() < ROAMER_SHARE
	var h := {
		"params": params,
		"node": node,
		"mesh": mesh,
		"mode": "roam" if roamer else "sidewalk",
		"roamer": roamer,          # full-time roamer vs sidewalk walker on a detour
		"lane": lane,
		"along": along,
		"dir": 1 if randf() < 0.5 else -1,
		"target": tile,            # roam-mode destination (tile coords)
		"detour_t": 0.0,           # roam time left before rejoining a sidewalk
		"whim_t": randf_range(6.0, 16.0),
		"wait": randf_range(0.0, 1.5),
		"phase": randf() * TAU,
		"panic_t": 0.0,
		"flee_dir": Vector2.ZERO,
		"facing": Vector2(0, 1),
		"moving": false,
	}
	if roamer:
		h["target"] = _pick_roam_target(tile)
	_humans.append(h)

func _process(delta: float) -> void:
	for h in _humans:
		_update_panic(h, delta)
		if float(h["panic_t"]) > 0.0:
			_move_panic(h, delta)
		elif str(h["mode"]) == "sidewalk":
			_move_sidewalk(h, delta)
		else:
			_move_roam(h, delta)
		_update_facing(h, delta)
		_animate(h, delta)
		_check_kills()

# ---------------------------------------------------------------------------
# Movement
# ---------------------------------------------------------------------------

func _human_tile(h: Dictionary) -> Vector2:
	var node: Node3D = h["node"]
	return Vector2(node.position.x, node.position.z) / GameConfig.TILE_SIZE - Vector2(0.5, 0.5)

func _step(h: Dictionary, move_tiles: Vector2, delta: float, speed: float) -> void:
	var node: Node3D = h["node"]
	var dist := move_tiles.length()
	if dist < 0.0001:
		h["moving"] = false
		return
	var step_len := minf(speed * delta, dist)
	var move := move_tiles / dist * step_len
	node.position.x += move.x * GameConfig.TILE_SIZE
	node.position.z += move.y * GameConfig.TILE_SIZE
	h["moving"] = true
	h["facing"] = move / step_len if step_len > 0.0 else move_tiles / dist
	h["facing"] = (h["facing"] as Vector2).normalized()
	h["phase"] = float(h["phase"]) + delta * (13.0 if speed > WALK_SPEED * 1.5 else 9.0)

func _move_sidewalk(h: Dictionary, delta: float) -> void:
	var wait := float(h["wait"])
	if wait > 0.0:
		h["wait"] = wait - delta
		h["moving"] = false
		return
	# Random whim: leave the sidewalk for a stroll in the grass.
	h["whim_t"] = float(h["whim_t"]) - delta
	if float(h["whim_t"]) <= 0.0:
		h["whim_t"] = randf_range(8.0, 20.0)
		_start_detour(h)
		return
	var lane: Dictionary = h["lane"]
	var along := float(h["along"]) + WALK_SPEED * float(h["dir"]) * delta
	if along <= 0.4 or along >= float(lane["length"]) - 0.4:
		_on_lane_end(h)
		return
	h["along"] = along
	if lane["horizontal"]:
		h["facing"] = Vector2(float(h["dir"]), 0.0)
	else:
		h["facing"] = Vector2(0.0, float(h["dir"]))
	var here := _human_tile(h)
	var to := _lane_point(lane, along) - here
	_step(h, to, delta, WALK_SPEED * 1.5)

## End of the sidewalk: hop to a crossing lane, wander off, or turn around.
func _on_lane_end(h: Dictionary) -> void:
	var here := _human_tile(h)
	var roll := randf()
	if roll < 0.45:
		var next := _nearby_lane(here, h["lane"] as Dictionary)
		if not next.is_empty():
			_switch_lane(h, next, here)
			return
	if roll < 0.75:
		_start_detour(h)
		return
	h["dir"] = -int(h["dir"])
	h["along"] = clampf(float(h["along"]), 0.5, float((h["lane"] as Dictionary)["length"]) - 0.5)
	h["wait"] = randf_range(PAUSE_MIN, PAUSE_MAX)

## A different lane passing within ~2 tiles of `here` (a sidewalk junction).
func _nearby_lane(here: Vector2, current: Dictionary) -> Dictionary:
	var options: Array[Dictionary] = []
	for l in _lanes:
		if l == current:
			continue
		var along := _closest_along(l, here)
		if _lane_point(l, along).distance_to(here) <= 2.2:
			options.append(l)
	if options.is_empty():
		return {}
	var choice: Dictionary = options.pick_random()
	return choice

func _closest_along(lane: Dictionary, tile: Vector2) -> float:
	var raw := (tile.x if lane["horizontal"] else tile.y) - float(lane["start"])
	return clampf(raw, 0.5, float(lane["length"]) - 0.5)

func _switch_lane(h: Dictionary, lane: Dictionary, here: Vector2) -> void:
	h["lane"] = lane
	h["along"] = _closest_along(lane, here)
	h["dir"] = 1 if randf() < 0.5 else -1
	h["mode"] = "sidewalk"

func _start_detour(h: Dictionary) -> void:
	var target := _pick_roam_target(_human_tile(h))
	h["mode"] = "roam"
	h["target"] = target
	h["detour_t"] = randf_range(6.0, 14.0)

func _move_roam(h: Dictionary, delta: float) -> void:
	var wait := float(h["wait"])
	if wait > 0.0:
		h["wait"] = wait - delta
		h["moving"] = false
		return
	if not bool(h["roamer"]):
		h["detour_t"] = float(h["detour_t"]) - delta
		if float(h["detour_t"]) <= 0.0 and _try_rejoin_sidewalk(h):
			return
	var here := _human_tile(h)
	var to: Vector2 = (h["target"] as Vector2) - here
	if to.length() < 0.15:
		h["wait"] = randf_range(PAUSE_MIN, PAUSE_MAX)
		h["target"] = _pick_roam_target(here)
		h["moving"] = false
		return
	_step(h, to, delta, WALK_SPEED)

## A nearby open-ground destination: in bounds, off roads, not inside a solid.
func _pick_roam_target(near: Vector2) -> Vector2:
	for attempt in 14:
		var cand := near + Vector2(randf_range(-5.0, 5.0), randf_range(-5.0, 5.0))
		cand.x = clampf(cand.x, 1.0, float(GameConfig.MAP_W) - 2.0)
		cand.y = clampf(cand.y, 1.0, float(GameConfig.MAP_H) - 2.0)
		if _walkable_calm_path(near, cand):
			return cand
	return near

## Straight-line check: every sampled tile must be open ground (no road, no
## water, no solid props). Calm humans reroute rather than jaywalk. If the
## walk STARTS on a road (they calmed down mid-crossing), the leading road
## tiles are exempt so they can finish stepping off it.
func _walkable_calm_path(from: Vector2, to: Vector2) -> bool:
	var leaving_road := MemphisLayout.is_road(Vector2i(int(floor(from.x)), int(floor(from.y))))
	var dist := from.distance_to(to)
	var steps := maxi(int(dist * 2.0), 1)
	for i in steps + 1:
		var t := from.lerp(to, float(i) / float(steps))
		var tile := Vector2i(int(floor(t.x)), int(floor(t.y)))
		if GameState.blocked_tiles.has(tile):
			return false
		if MemphisLayout.is_road(tile):
			if not leaving_road:
				return false
		else:
			leaving_road = false
	return true

func _try_rejoin_sidewalk(h: Dictionary) -> bool:
	var here := _human_tile(h)
	var best: Dictionary = {}
	var best_d := 6.0
	for l in _lanes:
		var p := _lane_point(l, _closest_along(l, here))
		var d := here.distance_to(p)
		if d < best_d and _walkable_calm_path(here, p):
			best_d = d
			best = l
	if best.is_empty():
		h["detour_t"] = randf_range(4.0, 8.0)
		return false
	_switch_lane(h, best, here)
	return true

# ---------------------------------------------------------------------------
# Panic (alien in the vision cone)
# ---------------------------------------------------------------------------

func _update_panic(h: Dictionary, delta: float) -> void:
	var node: Node3D = h["node"]
	var here := Vector2(node.position.x, node.position.z)
	var threat := _visible_alien(h, here)
	if threat != Vector2.INF:
		h["panic_t"] = PANIC_LINGER_SEC
		h["flee_dir"] = (here - threat).normalized()
		if (h["flee_dir"] as Vector2).length_squared() < 0.001:
			h["flee_dir"] = Vector2.RIGHT.rotated(randf() * TAU)
	elif float(h["panic_t"]) > 0.0:
		h["panic_t"] = float(h["panic_t"]) - delta
		if float(h["panic_t"]) <= 0.0:
			# Calmed down: whatever ground they're on, wander somewhere sane.
			h["mode"] = "roam"
			h["target"] = _pick_roam_target(_human_tile(h))
			h["wait"] = randf_range(0.4, 1.2)

## World-XZ position of the nearest ALIEN-form creature inside this human's
## forward vision cone, or Vector2.INF. Shapeshifted players don't register.
func _visible_alien(h: Dictionary, here: Vector2) -> Vector2:
	var facing: Vector2 = h["facing"]
	var cone_cos := cos(deg_to_rad(VIEW_HALF_ANGLE_DEG))
	var best := Vector2.INF
	var best_d := VIEW_DIST * GameConfig.TILE_SIZE
	for id in GameState.creatures:
		var c: Creature = GameState.creatures[id]
		if not is_instance_valid(c) or c.is_dead or c.is_spawning:
			continue
		if not FormDefs.is_alien(c.form_key):
			continue
		var cpos := Vector2(c.position.x, c.position.z)
		var to := cpos - here
		var d := to.length()
		if d > best_d or d < 0.001:
			continue
		if facing.normalized().dot(to / d) < cone_cos:
			continue
		best_d = d
		best = cpos
	return best

func _move_panic(h: Dictionary, delta: float) -> void:
	var here := _human_tile(h)
	var base: Vector2 = h["flee_dir"]
	# Steer around solids/water/map edge — roads are fair game while panicking.
	# Try the flee heading first, then fan out left/right up to a full u-turn.
	var dir := base
	for angle in [0.0, PI / 4.0, -PI / 4.0, PI / 2.0, -PI / 2.0, PI * 0.75, -PI * 0.75, PI]:
		var cand := base.rotated(angle)
		var probe := here + cand * 0.8
		var tile := Vector2i(int(floor(probe.x)), int(floor(probe.y)))
		var off_map: bool = probe.x < 1.0 or probe.y < 1.0 \
			or probe.x > float(GameConfig.MAP_W) - 2.0 or probe.y > float(GameConfig.MAP_H) - 2.0
		if not off_map and not GameState.blocked_tiles.has(tile):
			dir = cand
			break
	h["flee_dir"] = dir
	# Facing follows the run, so re-spotting the chaser uses the new cone.
	_step(h, dir * 2.0, delta, PANIC_SPEED)

func _animate(h: Dictionary, _delta: float) -> void:
	var mesh: Node3D = h.get("mesh")
	if mesh == null or not is_instance_valid(mesh):
		return
	var moving: bool = h.get("moving", false)
	var panic: bool = float(h["panic_t"]) > 0.0
	ObjectMesh.animate_biped(mesh, float(h["phase"]), 1.0 if moving else 0.06, panic)

func _update_facing(h: Dictionary, delta: float) -> void:
	if not h.get("moving", false):
		return
	var node: Node3D = h["node"]
	if node == null or not is_instance_valid(node):
		return
	var f: Vector2 = h["facing"]
	if f.length_squared() < 0.0001:
		return
	var target := atan2(f.x, f.y) + PI
	node.rotation.y = lerp_angle(node.rotation.y, target, clampf(delta * 14.0, 0.0, 1.0))

# ---------------------------------------------------------------------------
# Deaths (anything lethal)
# ---------------------------------------------------------------------------

func predator_hit(predator_form: String, pos: Vector2) -> bool:
	for h in _humans.duplicate():
		var node: Node3D = h["node"]
		if not is_instance_valid(node):
			continue
		var d := pos.distance_to(Vector2(node.position.x, node.position.z))
		if d <= FormDefs.radius(predator_form) + FormDefs.radius(FormDefs.HUMAN):
			_kill_human(h)
			return true
	return false

## A moving player vehicle or MATA bus ran over a pedestrian.
func squish_hit(vehicle_key: String, pos: Vector2) -> bool:
	for h in _humans.duplicate():
		var node: Node3D = h["node"]
		if not is_instance_valid(node):
			continue
		var d := pos.distance_to(Vector2(node.position.x, node.position.z))
		if d <= FormDefs.radius(vehicle_key) + FormDefs.radius(FormDefs.HUMAN):
			_kill_human(h)
			return true
	return false

func _check_kills() -> void:
	var traffic := GameState.npc_traffic
	if traffic != null and is_instance_valid(traffic) and traffic.has_method("hits_position_at_speed"):
		for h in _humans.duplicate():
			var node: Node3D = h["node"]
			if is_instance_valid(node) and traffic.hits_position_at_speed(node.position, 0.3):
				_kill_human(h)
	var player := GameState.player_creature
	if player == null or not is_instance_valid(player) or player.is_dead or player.is_spawning:
		return
	if player.is_moving and FormDefs.is_vehicle(player.form_key):
		squish_hit(player.form_key, Vector2(player.position.x, player.position.z))
	elif player.is_moving and FormDefs.is_zoo_animal(player.form_key):
		predator_hit(player.form_key, Vector2(player.position.x, player.position.z))

func explosion_hit(world_pos: Vector3, radius: float) -> void:
	var center := Vector2(world_pos.x, world_pos.z)
	for h in _humans.duplicate():
		var node: Node3D = h["node"]
		if not is_instance_valid(node):
			continue
		if center.distance_to(Vector2(node.position.x, node.position.z)) <= radius:
			_kill_human(h)

## Any lethal end (squished, eaten, blown up): blood splat + delayed reseed.
func _kill_human(h: Dictionary) -> void:
	var idx := _humans.find(h)
	if idx < 0:
		return
	var node: Node3D = h["node"]
	if is_instance_valid(node):
		GameState.blood_splat_requested.emit(node.position)
		node.queue_free()
	_humans.remove_at(idx)
	_respawn_later(RESPAWN_DELAY_KILL)

func _respawn_later(delay: float) -> void:
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self) and _humans.size() < TARGET_HUMANS:
			_spawn_human())

# ---------------------------------------------------------------------------
# Player interactions (Become Human / Eat Human)
# ---------------------------------------------------------------------------

func claimable_human(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := CLAIM_RADIUS * GameConfig.TILE_SIZE
	for h in _humans:
		var node: Node3D = h["node"]
		if not is_instance_valid(node):
			continue
		var d := pos.distance_to(Vector2(node.position.x, node.position.z))
		if d < best_d:
			best_d = d
			best = h
	return best

func human_display(h: Dictionary) -> String:
	return "" if h.is_empty() else FormDefs.display(FormDefs.HUMAN)

func human_world_pos(h: Dictionary) -> Vector3:
	var node: Node3D = h["node"]
	return node.position if is_instance_valid(node) else Vector3.ZERO

func human_params(h: Dictionary) -> Dictionary:
	return h.get("params", {})

func is_human_claimable(h: Dictionary) -> bool:
	return not h.is_empty() and _humans.has(h)

## Shapeshift claim: the NPC vanishes (the player now wears their look) and a
## replacement spawns elsewhere so the streets stay populated.
func claim_human(h: Dictionary) -> void:
	var idx := _humans.find(h)
	if idx < 0:
		return
	var node: Node3D = h["node"]
	if is_instance_valid(node):
		node.queue_free()
	_humans.remove_at(idx)
	_respawn_later(RESPAWN_DELAY_CLAIM)

## Alien snack: blood splat + replacement spawn.
func eat_human(h: Dictionary) -> bool:
	if not is_human_claimable(h):
		return false
	_kill_human(h)
	return true
