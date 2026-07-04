class_name ZooAnimals
extends Node3D

## Memphis Zoo exhibit animals — client-local NPCs that wander their pens,
## can be shapeshifted into, and respawn at the zoo when killed or eaten.

const WANDER_SPEED_TIGER := 0.45
const WANDER_SPEED_BEAR := 0.28
const WANDER_PAUSE_MIN := 1.5
const WANDER_PAUSE_MAX := 3.8
const CLAIM_RADIUS := 1.35
const RESPAWN_DELAY := 3.0

var _animals: Array[Dictionary] = []

func _ready() -> void:
	ensure_exhibit(FormDefs.MEMPHIS_TIGER, MemphisLayout.TIGER_ENCLOSURE)
	ensure_exhibit(FormDefs.MEMPHIS_BEAR, MemphisLayout.BEAR_ENCLOSURE)

func ensure_exhibit(form_key: String, enc: Rect2i) -> void:
	for a in _animals:
		if str(a.get("form_key", "")) == form_key:
			return
	_spawn_animal(form_key, enc)

func _spawn_animal(form_key: String, enc: Rect2i) -> void:
	var home := MemphisLayout.zoo_enclosure_center(enc)
	var node := Node3D.new()
	var mesh := ObjectMesh.build(FormDefs.visual(form_key))
	node.add_child(mesh)
	add_child(node)
	var wp := GameConfig.tile_to_world(home)
	node.position = Vector3(wp.x, 0, wp.z)
	_animals.append({
		"form_key": form_key,
		"enc": enc,
		"home": home,
		"node": node,
		"mesh": mesh,
		"target": home,
		"wait": randf_range(0.4, 1.6),
		"walk_phase": randf() * TAU,
		"is_moving": false,
		"speed": WANDER_SPEED_TIGER if form_key == FormDefs.MEMPHIS_TIGER else WANDER_SPEED_BEAR,
	})

func _process(delta: float) -> void:
	for a in _animals:
		_update_wander(a, delta)
		_animate_legs(a, delta)
	_check_player_kills()
	_check_vehicle_kills()

func _update_wander(a: Dictionary, delta: float) -> void:
	var node: Node3D = a["node"]
	if not is_instance_valid(node):
		return
	var wait := float(a["wait"])
	if wait > 0.0:
		a["wait"] = wait - delta
		a["is_moving"] = false
		return
	var target: Vector2 = a["target"]
	var pos := Vector2(node.position.x, node.position.z)
	var to := target - pos
	var dist := to.length()
	if dist < 0.1:
		a["wait"] = randf_range(WANDER_PAUSE_MIN, WANDER_PAUSE_MAX)
		a["is_moving"] = false
		a["target"] = _random_point_in_enclosure(a["enc"] as Rect2i)
		return
	var step := float(a["speed"]) * delta
	var move := to / dist * minf(step, dist)
	node.position.x += move.x
	node.position.z += move.y
	a["is_moving"] = true
	a["walk_phase"] = float(a["walk_phase"]) + delta * 11.0
	# Use normalized heading so tiny per-frame movement still rotates correctly.
	node.rotation.y = ObjectMesh.quadruped_yaw(move.normalized())

func _animate_legs(a: Dictionary, _delta: float) -> void:
	var mesh: Node3D = a.get("mesh")
	if mesh == null or not is_instance_valid(mesh):
		return
	var moving: bool = a.get("is_moving", false)
	ObjectMesh.animate_quadruped(mesh, float(a["walk_phase"]), 1.0 if moving else 0.08)

func _random_point_in_enclosure(enc: Rect2i) -> Vector2:
	return Vector2(
		randf_range(float(enc.position.x) + 0.55, float(enc.end.x) - 0.55),
		randf_range(float(enc.position.y) + 0.55, float(enc.end.y) - 0.55)
	)

func claimable_animal(pos: Vector2) -> Dictionary:
	var best: Dictionary = {}
	var best_d := CLAIM_RADIUS
	for a in _animals:
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			continue
		var d := pos.distance_to(Vector2(node.position.x, node.position.z))
		if d < best_d:
			best_d = d
			best = a
	return best

func animal_display(a: Dictionary) -> String:
	if a.is_empty():
		return ""
	return FormDefs.display(str(a.get("form_key", "")))

func animal_world_pos(a: Dictionary) -> Vector3:
	var node: Node3D = a["node"]
	return node.position if is_instance_valid(node) else Vector3.ZERO

func is_animal_claimable(a: Dictionary) -> bool:
	return not a.is_empty() and _animals.has(a)

func claim_animal(a: Dictionary) -> void:
	var idx := _animals.find(a)
	if idx < 0:
		return
	var node: Node3D = a["node"]
	if is_instance_valid(node):
		node.queue_free()
	_animals.remove_at(idx)

func release_animal(form_key: String, enc: Rect2i) -> void:
	ensure_exhibit(form_key, enc)

func predator_hit(predator_form: String, pos: Vector2) -> bool:
	for a in _animals.duplicate():
		var fk: String = str(a.get("form_key", ""))
		if fk == predator_form:
			continue
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			continue
		var d := pos.distance_to(Vector2(node.position.x, node.position.z))
		if d <= FormDefs.radius(predator_form) + FormDefs.radius(fk):
			_kill_npc_animal(a)
			return true
	return false

func _check_player_kills() -> void:
	var player := GameState.player_creature
	if player == null or not is_instance_valid(player) or player.is_dead or player.is_spawning:
		return
	if not FormDefs.is_alien(player.form_key):
		return
	var my := Vector2(player.position.x, player.position.z)
	for a in _animals:
		if not a.get("is_moving", false):
			continue
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			continue
		var d := my.distance_to(Vector2(node.position.x, node.position.z))
		var r := FormDefs.radius(str(a["form_key"])) + FormDefs.radius(player.form_key)
		if d > r:
			continue
		var res := FormDefs.resolve_player_death(player.form_key, FormDefs.kind(str(a["form_key"])))
		if res.die:
			player.apply_death(res.reason, false, animal_display(a))
			return

func _check_vehicle_kills() -> void:
	var traffic := GameState.npc_traffic
	if traffic != null and is_instance_valid(traffic):
		for a in _animals.duplicate():
			var node: Node3D = a["node"]
			if not is_instance_valid(node):
				continue
			if traffic.has_method("hits_position_at_speed"):
				if traffic.hits_position_at_speed(node.position, 0.38):
					_kill_npc_animal(a)
					continue
	var player := GameState.player_creature
	if player == null or not is_instance_valid(player) or player.is_dead:
		return
	if not FormDefs.is_vehicle(player.form_key) and player.form_key != FormDefs.MATA_BUS:
		return
	if not player.is_moving:
		return
	for a in _animals.duplicate():
		var node: Node3D = a["node"]
		if not is_instance_valid(node):
			continue
		var d := Vector2(player.position.x, player.position.z).distance_to(
			Vector2(node.position.x, node.position.z))
		if d <= FormDefs.radius(player.form_key) + FormDefs.radius(str(a["form_key"])):
			_kill_npc_animal(a)

func _kill_npc_animal(a: Dictionary) -> void:
	var idx := _animals.find(a)
	if idx < 0:
		return
	var form_key: String = a["form_key"]
	var enc: Rect2i = a["enc"]
	var node: Node3D = a["node"]
	if is_instance_valid(node):
		GameState.blood_splat_requested.emit(node.position)
		node.queue_free()
	_animals.remove_at(idx)
	var timer := get_tree().create_timer(RESPAWN_DELAY)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(self):
			ensure_exhibit(form_key, enc))
