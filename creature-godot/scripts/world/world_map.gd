class_name WorldMap
extends Node3D

@onready var ground: MeshInstance3D = $Ground
@onready var trees_root: Node3D = $Trees
@onready var creatures_root: Node3D = $Creatures
@onready var click_marker: MeshInstance3D = $ClickMarker

const CREATURE_SCENE := preload("res://scenes/units/creature.tscn")

var _remote_by_user: Dictionary = {} # user_id -> Creature
var _buildings_root: Node3D
var _objects_root: Node3D
var _last_remote_log := Vector2i(-1, -1)

## Shared/persistent interactive world objects (Fix 3).
## `_shared_objects` maps a Supabase world_objects row id -> its WorldObject node.
## `_fallback_interactive` holds the client-config objects we build at boot so the
## game works offline / before the table exists; they're swapped out for the
## shared set the first time a world_objects poll succeeds.
## `_known_user_ids` is the set of user_ids seen in the latest creature poll, used
## to decide whether a "possessed" object's controller is still present.
var _shared_objects: Dictionary = {}
var _fallback_interactive: Array[WorldObject] = []
var _shared_active := false
var _known_user_ids: Dictionary = {}
## Anti-flicker: object ids we changed locally (drop/pickup) get a grace window
## during which stale server rows are ignored (the PATCH is still in flight).
## `_tombstones` are ids we deleted locally (combines) — never resurrect those
## from a stale poll, which is what produced duplicate money bags.
var _local_authority: Dictionary = {} # object_id -> expiry msec
var _tombstones: Dictionary = {}      # object_id -> expiry msec

func note_local_authority(object_id: String, secs: float = 6.0) -> void:
	if object_id.is_empty():
		return
	_local_authority[object_id] = Time.get_ticks_msec() + int(secs * 1000.0)

func note_deleted(object_id: String, secs: float = 15.0) -> void:
	if object_id.is_empty():
		return
	_tombstones[object_id] = Time.get_ticks_msec() + int(secs * 1000.0)
	_local_authority.erase(object_id)

func _expire_grace_maps() -> void:
	var now := Time.get_ticks_msec()
	for id in _local_authority.keys():
		if now > int(_local_authority[id]):
			_local_authority.erase(id)
	for id in _tombstones.keys():
		if now > int(_tombstones[id]):
			_tombstones.erase(id)

func _ready() -> void:
	GameState.world_map = self
	_resolve_child_roots()
	_ensure_buildings_root()
	_ensure_objects_root()
	_build_ground()
	_build_landfill()
	_build_trees()
	_build_buildings()
	_build_interactive_objects()
	# Propane tanks and other blasts ask the world to spawn an explosion here.
	GameState.explosion_requested.connect(spawn_explosion)
	GameState.money_combined.connect(spawn_money_combine_fx)
	GameState.blood_splat_requested.connect(spawn_blood_splat)
	if click_marker:
		click_marker.visible = false

func _resolve_child_roots() -> void:
	ground = get_node_or_null("Ground") as MeshInstance3D
	trees_root = get_node_or_null("Trees") as Node3D
	creatures_root = get_node_or_null("Creatures") as Node3D
	click_marker = get_node_or_null("ClickMarker") as MeshInstance3D
	if trees_root == null:
		trees_root = Node3D.new()
		trees_root.name = "Trees"
		add_child(trees_root)
	if creatures_root == null:
		creatures_root = Node3D.new()
		creatures_root.name = "Creatures"
		add_child(creatures_root)

func spawn_player() -> void:
	_resolve_child_roots()
	var data := GameState.player_data
	if data.is_empty():
		data = GameConfig.default_player_data()
		GameState.player_data = data
	var player: Creature = CREATURE_SCENE.instantiate() as Creature
	creatures_root.add_child(player)
	player.setup(data)

func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GameConfig.MAP_W * GameConfig.TILE_SIZE, GameConfig.MAP_H * GameConfig.TILE_SIZE)
	ground.mesh = plane
	ground.position = Vector3(GameConfig.MAP_W * 0.5, 0, GameConfig.MAP_H * 0.5)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.54, 0.32)
	mat.roughness = 0.95
	ground.material_override = mat

	var body := StaticBody3D.new()
	body.name = "GroundBody"
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(plane.size.x, 0.2, plane.size.y)
	col.shape = shape
	body.add_child(col)
	ground.add_child(body)

func _ensure_buildings_root() -> void:
	_buildings_root = get_node_or_null("Buildings") as Node3D
	if _buildings_root:
		return
	_buildings_root = Node3D.new()
	_buildings_root.name = "Buildings"
	add_child(_buildings_root)

func _ensure_objects_root() -> void:
	_objects_root = get_node_or_null("WorldObjects") as Node3D
	if _objects_root:
		return
	_objects_root = Node3D.new()
	_objects_root.name = "WorldObjects"
	add_child(_objects_root)

## Decorative forest trees are solid (nav routes around them via blocked_tiles)
## and count as "tree" for the kill matrix (a car that reaches one wrecks).
func _build_trees() -> void:
	for pos in GameConfig.TREE_POSITIONS:
		var wp := GameConfig.tile_to_world(Vector2(pos))
		_spawn_world_object("tree_decor", Vector3(wp.x, 0, wp.z), trees_root)

## Houses are solid and lethal to vehicles that crash into them.
func _build_buildings() -> void:
	for pos in GameConfig.BUILDING_POSITIONS:
		var wp := GameConfig.tile_to_world(Vector2(pos))
		_spawn_world_object("building", Vector3(wp.x, 0, wp.z), _buildings_root)

## Interactive/shapeshiftable objects (landfill starter junk + road traps).
## These are the CLIENT-CONFIG fallback set: they render immediately (offline or
## before the shared table exists). Once the Supabase world_objects table answers
## a poll, `sync_world_objects()` swaps this set for the shared/persistent one.
func _build_interactive_objects() -> void:
	for entry in GameConfig.interactive_objects():
		var tile: Vector2 = entry["tile"]
		var wp := GameConfig.tile_to_world(tile)
		var obj := _spawn_world_object(str(entry["key"]), Vector3(wp.x, 0, wp.z), _objects_root)
		_fallback_interactive.append(obj)

## The Landfill Dump spawn zone: a tinted ground patch + scattered trash piles.
func _build_landfill() -> void:
	var rect := GameConfig.LANDFILL_RECT
	var tint := MeshInstance3D.new()
	tint.name = "LandfillTint"
	var plane := PlaneMesh.new()
	plane.size = Vector2(rect.size.x * GameConfig.TILE_SIZE, rect.size.y * GameConfig.TILE_SIZE)
	tint.mesh = plane
	tint.position = Vector3(
		(rect.position.x + rect.size.x * 0.5) * GameConfig.TILE_SIZE,
		0.02,
		(rect.position.y + rect.size.y * 0.5) * GameConfig.TILE_SIZE
	)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.34, 0.29, 0.19)
	mat.roughness = 1.0
	tint.material_override = mat
	add_child(tint)
	for tile in GameConfig.trash_pile_tiles():
		var wp := GameConfig.tile_to_world(tile)
		_spawn_world_object("trash", Vector3(wp.x, 0, wp.z), _objects_root)

## Per-object configuration. `kind` drives the kill matrix; `form_key` (when set)
## makes the object shapeshiftable; `visual` picks the ObjectMesh.
func _object_cfg(key: String) -> Dictionary:
	match key:
		"tree_decor":
			return {"kind": "tree", "form_key": "", "visual": "tree", "radius": 0.5, "display_name": "Tree"}
		"building":
			return {"kind": "building", "form_key": "", "visual": "building", "radius": 0.9, "display_name": "House"}
		"altima":
			return {"kind": "prop", "form_key": FormDefs.ALTIMA, "visual": "altima", "radius": 0.55, "display_name": "Rusty Altima"}
		"magnolia":
			return {"kind": "tree", "form_key": FormDefs.MAGNOLIA, "visual": "magnolia", "radius": 0.5, "display_name": "Small Tree"}
		"propane":
			return {"kind": "propane", "form_key": FormDefs.PROPANE, "visual": "propane", "radius": 0.45, "display_name": "Propane Tank"}
		"pothole":
			return {"kind": "pothole", "form_key": FormDefs.POTHOLE, "visual": "pothole", "radius": 0.5, "display_name": "Pothole"}
		"cart":
			return {"kind": "cart", "form_key": FormDefs.SHOPPING_CART, "visual": "cart", "radius": 0.4, "display_name": "Shopping Cart"}
		"bus":
			# kind "prop", NOT "mata_bus": a PARKED bus is harmless (only a
			# player-driven bus, resolved via remote creatures, can kill).
			return {"kind": "prop", "form_key": FormDefs.MATA_BUS, "visual": "mata_bus", "radius": 0.75, "display_name": "MATA Bus"}
		"money_stack":
			return {"kind": "prop", "form_key": "", "visual": "money_stack", "radius": 0.35, "display_name": "Money Stack", "tier": FormDefs.TIER_STACK}
		"money_bag":
			return {"kind": "prop", "form_key": "", "visual": "money_bag", "radius": 0.45, "display_name": "Money Bag", "tier": FormDefs.TIER_BAG}
		"vault":
			return {"kind": "prop", "form_key": "", "visual": "vault", "radius": 0.55, "display_name": "Vault", "tier": FormDefs.TIER_VAULT}
		"cone":
			return {"kind": "prop", "form_key": "", "visual": "cone", "radius": 0.3, "display_name": "Road Cone"}
		_:
			return {"kind": "prop", "form_key": "", "visual": "trash", "radius": 0.4, "display_name": "Trash Pile"}

func _spawn_world_object(key: String, world_pos: Vector3, parent: Node3D) -> WorldObject:
	var obj := WorldObject.new()
	obj.configure(_object_cfg(key))
	obj.type_key = key
	parent.add_child(obj)
	obj.set_spawn_position(world_pos)
	return obj

# ---------------------------------------------------------------------------
# Shared / persistent interactive objects (Fix 3).
# ---------------------------------------------------------------------------

## Reconcile the local interactive objects with the shared Supabase state. Called
## on the same ~1.5s cadence as the creature poll. Rows carry {id, type, x, y
## (tile space), state, possessed_by}. A "possessed" object whose controller is a
## currently-present creature is hidden (that player's synced form represents it,
## so there's no duplicate); otherwise it renders idle at its last position (so it
## persists where it was dropped, and survives a controller disconnect).
func sync_world_objects(rows: Array) -> void:
	_activate_shared_objects()
	_expire_grace_maps()
	var my_uid := NetworkService.get_user_id()
	# LOCAL possession is authoritative for my own object so a just-become /
	# just-popped object doesn't flicker while the possess/release PATCH is in
	# flight (~1.5s). Overrides whatever the server row currently says about me.
	var locally_possessed_id := ""
	var locally_carried: Dictionary = {}
	var pc: Creature = GameState.player_creature
	if pc and is_instance_valid(pc) and pc.has_method("possessed_object_id"):
		locally_possessed_id = pc.possessed_object_id()
	if pc and is_instance_valid(pc) and pc.has_method("carried_object_ids"):
		for cid in pc.carried_object_ids():
			locally_carried[str(cid)] = true
	var carried_tiers_by_user: Dictionary = {}
	var seen: Dictionary = {}
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var id := str(row.get("id", ""))
		if id.is_empty():
			continue
		# We deleted this row locally (combine); the server DELETE may still be in
		# flight. Never resurrect it — that's how two stacks became two bags.
		if _tombstones.has(id):
			var dead: WorldObject = _shared_objects.get(id)
			if dead and is_instance_valid(dead):
				dead.queue_free()
			_shared_objects.erase(id)
			continue
		seen[id] = true
		# We just changed this object locally (drop/pickup) and our PATCH may not
		# have landed yet — trust local state, ignore the stale server row.
		if _local_authority.has(id):
			continue
		var type_key := str(row.get("type", "trash"))
		var tile := Vector2(float(row.get("x", 0.0)), float(row.get("y", 0.0)))
		var state := str(row.get("state", "idle"))
		var possessed_by := str(row.get("possessed_by", ""))
		var possessed := state == "possessed" and not possessed_by.is_empty()
		var carried := state == "carried" and not possessed_by.is_empty()
		# Decide whether to hide the standalone prop (a possessing player's synced
		# form stands in for it, or carried money floats above the carrier).
		var hide_prop := false
		if id == locally_possessed_id:
			hide_prop = true # I'm wearing it right now (local truth beats server lag)
		elif id in locally_carried:
			hide_prop = true # I'm hauling it (local carry beats server lag)
		elif carried and possessed_by == my_uid:
			# Server says I carry it but I don't (stale row after a crash/reload,
			# or a lost PATCH). Render it idle AND repair the server row, so other
			# players stop seeing it floating above my head forever.
			hide_prop = false
			note_local_authority(id)
			NetworkService.drop_money_object(id, tile.x, tile.y, _row_owner_name(row))
		elif carried and _known_user_ids.has(possessed_by):
			hide_prop = true
			var t := FormDefs.tier_for_type(type_key)
			if t > 0:
				if not carried_tiers_by_user.has(possessed_by):
					carried_tiers_by_user[possessed_by] = []
				carried_tiers_by_user[possessed_by].append(t)
		# carried by an ABSENT player (disconnected mid-haul) -> render idle
		elif possessed and possessed_by == my_uid:
			# Two cases. (a) Session restore: I reloaded while shapeshifted, so I'm
			# STILL wearing this form but lost the local object link — re-adopt it
			# (otherwise I see my own worn object duplicated at its old spot).
			# (b) I've genuinely popped out and the release PATCH is lagging — show it.
			var cfg_form := str(_object_cfg(type_key).get("form_key", ""))
			if pc and is_instance_valid(pc) and locally_possessed_id.is_empty() \
					and not cfg_form.is_empty() and cfg_form == pc.form_key:
				var adopt: WorldObject = _shared_objects.get(id)
				if adopt == null or not is_instance_valid(adopt):
					adopt = _spawn_world_object(type_key, GameConfig.tile_to_world(tile), _objects_root)
					adopt.object_id = id
					_shared_objects[id] = adopt
				adopt.spawn_world_pos = GameConfig.tile_to_world(tile)
				adopt.spawn_tile = tile
				pc.adopt_possessed_object(adopt)
				locally_possessed_id = id
				continue
			hide_prop = false # popped out; server row is just lagging — show it
		elif possessed and _known_user_ids.has(possessed_by):
			hide_prop = true # a remote player we can see is wearing it
		# else: idle, or possessed by an absent controller -> render idle
		var obj: WorldObject = _shared_objects.get(id)
		if hide_prop:
			if obj and is_instance_valid(obj):
				obj.consume()
			continue
		# Idle (or orphaned-possessed): render at its shared position.
		var world_pos := GameConfig.tile_to_world(tile)
		if obj == null or not is_instance_valid(obj):
			obj = _spawn_world_object(type_key, world_pos, _objects_root)
			obj.object_id = id
			_shared_objects[id] = obj
		else:
			obj.object_id = id
			obj.respawn_at(world_pos)
		# Home = current shared position, so a death drop / respawn returns it to
		# where the world last agreed it was.
		obj.spawn_world_pos = world_pos
		obj.spawn_tile = tile
		if obj.has_method("apply_row"):
			obj.apply_row(row)
	# Remote players: show loot floating above them from shared carry state.
	for uid in _remote_by_user.keys():
		var remote: Creature = _remote_by_user[uid]
		if not is_instance_valid(remote):
			continue
		if uid == my_uid:
			continue
		var tiers: Array = carried_tiers_by_user.get(uid, [])
		if remote.has_method("update_carried_display"):
			remote.update_carried_display(tiers)
	# Drop local shared objects that no longer exist server-side (skip any the
	# local player is currently wearing, which are legitimately consumed).
	for id in _shared_objects.keys():
		if seen.has(id):
			continue
		var gone: WorldObject = _shared_objects[id]
		if is_instance_valid(gone):
			gone.queue_free()
		_shared_objects.erase(id)

## owner_name straight from a row can be JSON null; str(null) would give "<null>".
func _row_owner_name(row: Dictionary) -> String:
	var v: Variant = row.get("owner_name")
	return v if typeof(v) == TYPE_STRING else ""

## Spawn a freshly-combined money object into the world for immediate feedback.
## If `object_id` is set (an online create returned a row id), it's tracked in the
## shared set so the next poll matches it by id instead of duplicating it.
func spawn_money_object(type_key: String, world_pos: Vector3, owner_name: String, object_id: String = "") -> void:
	_ensure_objects_root()
	# Don't double-spawn if a poll already materialized this id.
	if not object_id.is_empty() and _shared_objects.has(object_id):
		var existing: WorldObject = _shared_objects[object_id]
		if is_instance_valid(existing):
			existing.set_money_owner(owner_name)
			return
	var obj := _spawn_world_object(type_key, world_pos, _objects_root)
	obj.object_id = object_id
	obj.set_money_owner(owner_name)
	if not object_id.is_empty():
		_shared_objects[object_id] = obj

## Swap the client-config fallback objects for the shared set exactly once, the
## first time a world_objects poll succeeds. Keeps any fallback object the player
## is currently wearing (consumed) so an in-progress shapeshift isn't yanked away.
func _activate_shared_objects() -> void:
	if _shared_active:
		return
	_shared_active = true
	for obj in _fallback_interactive:
		if is_instance_valid(obj) and not obj.consumed:
			obj.queue_free()
	_fallback_interactive.clear()

## Spawn a big, bright, clearly-visible explosion FX and apply its lethal radius
## to the local player (client-local; cross-client blast damage is NOT synced in
## Slice 1). A fireball sphere + a quick white flash shell + an OmniLight burst so
## it reads at a glance even in daylight and at any zoom.
func spawn_explosion(world_pos: Vector3, radius: float) -> void:
	var origin := world_pos + Vector3(0, 0.5, 0)
	var peak := maxf(radius, 1.5)

	# Fireball core (unshaded + emissive so it stays bright regardless of lighting).
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 0.35
	core_mesh.height = 0.7
	core.mesh = core_mesh
	var core_mat := StandardMaterial3D.new()
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	core_mat.albedo_color = Color(1.0, 0.62, 0.15, 0.95)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.45, 0.1)
	core_mat.emission_energy_multiplier = 6.0
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override = core_mat
	core.position = origin
	add_child(core)

	# Bright white flash shell that pops fast and fades.
	var flash := MeshInstance3D.new()
	var flash_mesh := SphereMesh.new()
	flash_mesh.radius = 0.35
	flash_mesh.height = 0.7
	flash.mesh = flash_mesh
	var flash_mat := StandardMaterial3D.new()
	flash_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	flash_mat.albedo_color = Color(1.0, 0.95, 0.8, 0.9)
	flash_mat.emission_enabled = true
	flash_mat.emission = Color(1.0, 0.9, 0.7)
	flash_mat.emission_energy_multiplier = 8.0
	flash_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash.material_override = flash_mat
	flash.position = origin
	add_child(flash)

	# A real light burst for extra punch (single one-shot omni light is cheap).
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.6, 0.25)
	light.light_energy = 6.0
	light.omni_range = peak * 4.0
	light.position = origin
	add_child(light)

	var tween := create_tween()
	tween.set_parallel(true)
	# Core swells slowly and fades over ~0.85s.
	tween.tween_property(core, "scale", Vector3.ONE * peak * 2.6, 0.85)
	tween.tween_property(core_mat, "albedo_color:a", 0.0, 0.85)
	# Flash snaps out bigger and vanishes fast.
	tween.tween_property(flash, "scale", Vector3.ONE * peak * 3.2, 0.25)
	tween.tween_property(flash_mat, "albedo_color:a", 0.0, 0.3)
	tween.tween_property(light, "light_energy", 0.0, 0.5)
	tween.chain().tween_callback(func() -> void:
		core.queue_free()
		flash.queue_free()
		light.queue_free())

	var player := GameState.player_creature
	if player and is_instance_valid(player) and player.has_method("apply_explosion"):
		player.apply_explosion(world_pos, radius)

## A squished alien leaves a blood splat: one main puddle + a few random droplet
## blobs, all flat against the ground, fading away over several seconds.
func spawn_blood_splat(world_pos: Vector3) -> void:
	var splat := Node3D.new()
	splat.position = Vector3(world_pos.x, 0.0, world_pos.z)
	add_child(splat)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.04, 0.04, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Main puddle.
	var puddle := CylinderMesh.new()
	puddle.top_radius = 0.3
	puddle.bottom_radius = 0.3
	puddle.height = 0.02
	splat.add_child(_flat_blob(puddle, mat, Vector3(0, 0.035, 0)))
	# Scattered droplets around it.
	for i in 5:
		var drop := CylinderMesh.new()
		var r := randf_range(0.05, 0.12)
		drop.top_radius = r
		drop.bottom_radius = r
		drop.height = 0.02
		var ang := randf() * TAU
		var d := randf_range(0.25, 0.55)
		splat.add_child(_flat_blob(drop, mat, Vector3(cos(ang) * d, 0.03, sin(ang) * d)))
	var tween := create_tween()
	tween.tween_interval(4.0)                                # stay vivid for a beat
	tween.tween_property(mat, "albedo_color:a", 0.0, 4.0)   # then fade out
	tween.tween_callback(splat.queue_free)

func _flat_blob(mesh: Mesh, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi

## Quick green sparkle when two money piles combine into the next tier.
func spawn_money_combine_fx(world_pos: Vector3) -> void:
	var origin := world_pos + Vector3(0, 0.55, 0)
	var burst := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.25
	mesh.height = 0.5
	burst.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.35, 1.0, 0.45, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 0.85, 0.35)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	burst.material_override = mat
	burst.position = origin
	add_child(burst)
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(burst, "scale", Vector3.ONE * 2.2, 0.35)
	tween.tween_property(mat, "albedo_color:a", 0.0, 0.4)
	tween.chain().tween_callback(burst.queue_free)

func get_player_creature() -> Creature:
	return GameState.player_creature

func sync_remote_creatures(rows: Array) -> void:
	var player_uid := NetworkService.get_user_id()
	var seen: Dictionary = {}
	var known: Dictionary = {}
	var remote_count := 0
	for row in rows:
		if typeof(row) != TYPE_DICTIONARY:
			continue
		var uid := str(row.get("user_id", ""))
		if not uid.is_empty():
			known[uid] = true
		if uid.is_empty() or uid == player_uid:
			continue
		remote_count += 1
		seen[uid] = true
		if _remote_by_user.has(uid):
			var existing: Creature = _remote_by_user[uid]
			if is_instance_valid(existing):
				existing.apply_remote_state(row)
			continue
		var data := NetworkService.db_row_to_player_data(row, false)
		var remote: Creature = CREATURE_SCENE.instantiate() as Creature
		creatures_root.add_child(remote)
		remote.setup(data)
		_remote_by_user[uid] = remote
	for uid in _remote_by_user.keys():
		if seen.has(uid):
			continue
		var creature: Creature = _remote_by_user[uid]
		if is_instance_valid(creature):
			creature.queue_free()
		_remote_by_user.erase(uid)
	_known_user_ids = known
	var current_log := Vector2i(remote_count, _remote_by_user.size())
	if current_log != _last_remote_log:
		_last_remote_log = current_log
		GameState.add_admin_log("Remote sync: %d other profiles, %d visible" % [remote_count, _remote_by_user.size()])

func show_click_marker(world_pos: Vector3) -> void:
	click_marker.visible = true
	click_marker.position = world_pos + Vector3(0, 0.05, 0)
	var tween := create_tween()
	tween.tween_property(click_marker, "scale", Vector3(1.2, 1.2, 1.2), 0.25)
	tween.tween_callback(func(): click_marker.visible = false)
