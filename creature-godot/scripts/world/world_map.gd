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

## Active smoke clouds (Slice 3): row id (or local key) -> {pos, until_msec, node}.
## Everything inside a cloud's radius (remote players + loose money) is hidden.
var _smoke_clouds: Dictionary = {}

## Kill-feed rows already toasted (never repeat a broadcast on later polls).
var _kill_events_seen: Dictionary = {}

## Slice 6: scenery trees by tile (claimable via shapeshift), retired home
## tiles already processed, the Pyramid landmark node, and abduction events
## already played.
var _scenery_trees: Dictionary = {}   # Vector2i -> WorldObject
var _tree_homes_done: Dictionary = {} # row id -> true
var _pyramid_obj: WorldObject = null
var _abductions_seen: Dictionary = {}
## Explosion sync rows already played (transient world_objects type "explosion").
var _explosions_seen: Dictionary = {}
## Chain-reaction guard for the current blast wave (object/creature keys).
var _explosion_chain_guard: Dictionary = {}
var _explosion_chain_depth: int = 0
var _explosion_chain_count: int = 0
const EXPLOSION_CHAIN_MAX := 32

## Slice 7: scenery houses by tile (claimable like trees), retired house home
## tiles, per-player carried loot rows from the latest poll (drives the Steal
## button), and known safe-house claims (owner name -> {id, tile}).
var _scenery_houses: Dictionary = {}     # Vector2i -> WorldObject
var _house_homes_done: Dictionary = {}   # row id -> true
var _carried_rows_by_user: Dictionary = {} # user_id -> Array[{id, tier, type, owner}]
var _safe_houses: Dictionary = {}        # owner name -> {"id": String, "tile": Vector2}

func note_local_authority(object_id: String, secs: float = 6.0) -> void:
	if object_id.is_empty():
		return
	_local_authority[object_id] = Time.get_ticks_msec() + int(secs * 1000.0)

func note_deleted(object_id: String, secs: float = 15.0) -> void:
	if object_id.is_empty():
		return
	_tombstones[object_id] = Time.get_ticks_msec() + int(secs * 1000.0)
	_local_authority.erase(object_id)
	var dead = _shared_objects.get(object_id)
	if dead != null and is_instance_valid(dead):
		dead.queue_free()
	_shared_objects.erase(object_id)

func _prune_invalid_shared_objects() -> void:
	for id in _shared_objects.keys():
		var obj = _shared_objects[id]
		if obj == null or not is_instance_valid(obj):
			_shared_objects.erase(id)

func _get_shared_object(id: String) -> WorldObject:
	var obj = _shared_objects.get(id)
	if obj != null and is_instance_valid(obj):
		return obj
	if _shared_objects.has(id):
		_shared_objects.erase(id)
	return null

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
	_build_landmarks()
	_build_interactive_objects()
	var traffic := NpcTraffic.new()
	traffic.name = "Traffic"
	add_child(traffic)
	GameState.npc_traffic = traffic
	var zoo := ZooAnimals.new()
	zoo.name = "ZooAnimals"
	add_child(zoo)
	GameState.zoo_animals = zoo
	var humans := NpcHumans.new()
	humans.name = "Pedestrians"
	add_child(humans)
	GameState.npc_humans = humans
	# Propane tanks and other blasts ask the world to spawn an explosion here.
	GameState.explosion_requested.connect(spawn_explosion)
	GameState.money_combined.connect(spawn_money_combine_fx)
	GameState.blood_splat_requested.connect(spawn_blood_splat)
	GameState.vehicle_wreck_requested.connect(spawn_vehicle_wreck)
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

## Land plane (east of the river) + the sunken Mississippi, Mud Island, the
## M Bridge, region ground tints and road strips. Land stays at y=0 everywhere
## (movement/collision untouched); the "elevation" is the river sitting ~0.45
## below the bluff with a visible bank wall.
func _build_ground() -> void:
	var land_w := (GameConfig.MAP_W - MemphisLayout.RIVER_W) * GameConfig.TILE_SIZE
	var map_h := GameConfig.MAP_H * GameConfig.TILE_SIZE
	var plane := PlaneMesh.new()
	plane.size = Vector2(land_w, map_h)
	ground.mesh = plane
	ground.position = Vector3(MemphisLayout.RIVER_W + land_w * 0.5, 0, map_h * 0.5)
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

	_build_river()
	_build_mud_island()
	_build_bridge()
	_build_region_tints()
	_build_roads()

func _quad_mat(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 1.0
	return mat

## A flat colored quad covering a tile rect at a given height (region tints,
## road strips). Heights are spaced so overlapping layers never z-fight.
func _add_ground_quad(rect: Rect2i, color: Color, y: float, parent: Node3D, label: String) -> void:
	var quad := MeshInstance3D.new()
	quad.name = label
	var plane := PlaneMesh.new()
	plane.size = Vector2(rect.size.x * GameConfig.TILE_SIZE, rect.size.y * GameConfig.TILE_SIZE)
	quad.mesh = plane
	quad.material_override = _quad_mat(color)
	quad.position = Vector3(
		(rect.position.x + rect.size.x * 0.5) * GameConfig.TILE_SIZE,
		y,
		(rect.position.y + rect.size.y * 0.5) * GameConfig.TILE_SIZE
	)
	parent.add_child(quad)

func _build_river() -> void:
	var root := Node3D.new()
	root.name = "River"
	add_child(root)
	var map_h := GameConfig.MAP_H * GameConfig.TILE_SIZE
	var river_w := MemphisLayout.RIVER_W * GameConfig.TILE_SIZE

	var water := MeshInstance3D.new()
	water.name = "Water"
	var plane := PlaneMesh.new()
	plane.size = Vector2(river_w, map_h)
	water.mesh = plane
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.23, 0.36, 0.48)
	mat.roughness = 0.25
	mat.metallic = 0.1
	water.material_override = mat
	water.position = Vector3(river_w * 0.5, -0.45, map_h * 0.5)
	root.add_child(water)

	# Taps on the water still raycast to a ground point (path ends at the bank).
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(river_w, 0.1, map_h)
	col.shape = shape
	body.add_child(col)
	water.add_child(body)

	# Bluff wall along the east bank.
	var bank := MeshInstance3D.new()
	bank.name = "Bluff"
	var wall := BoxMesh.new()
	wall.size = Vector3(0.3, 0.6, map_h)
	bank.mesh = wall
	bank.material_override = _quad_mat(Color(0.45, 0.38, 0.26))
	bank.position = Vector3(MemphisLayout.RIVER_W * GameConfig.TILE_SIZE - 0.1, -0.3, map_h * 0.5)
	root.add_child(bank)

func _build_mud_island() -> void:
	var rect := MemphisLayout.MUD_ISLAND_RECT
	var island := MeshInstance3D.new()
	island.name = "MudIsland"
	var box := BoxMesh.new()
	# Top at y=0 (walkable height), sides visible above the sunken water.
	box.size = Vector3(rect.size.x * GameConfig.TILE_SIZE, 0.6, rect.size.y * GameConfig.TILE_SIZE)
	island.mesh = box
	island.material_override = _quad_mat(Color(0.34, 0.58, 0.36))
	island.position = Vector3(
		(rect.position.x + rect.size.x * 0.5) * GameConfig.TILE_SIZE,
		-0.3,
		(rect.position.y + rect.size.y * 0.5) * GameConfig.TILE_SIZE
	)
	add_child(island)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	col.shape = shape
	body.add_child(col)
	island.add_child(body)

## The Hernando de Soto "M" Bridge: deck at walkable height over the sunken
## river, rails, piers, and two arch prisms that read as the M.
func _build_bridge() -> void:
	var root := Node3D.new()
	root.name = "Bridge"
	add_child(root)
	var rect := MemphisLayout.BRIDGE_RECT
	var cx := (rect.position.x + rect.size.x * 0.5) * GameConfig.TILE_SIZE
	var cz := (rect.position.y + rect.size.y * 0.5) * GameConfig.TILE_SIZE
	var deck_w := rect.size.x * GameConfig.TILE_SIZE
	var deck_d := rect.size.y * GameConfig.TILE_SIZE

	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(deck_w, 0.2, deck_d)
	deck.mesh = deck_mesh
	deck.material_override = _quad_mat(Color(0.35, 0.36, 0.38))
	deck.position = Vector3(cx, -0.08, cz)
	root.add_child(deck)
	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = deck_mesh.size
	col.shape = shape
	body.add_child(col)
	deck.add_child(body)

	var rail_mat := _quad_mat(Color(0.55, 0.56, 0.6))
	for dz in [-deck_d * 0.5 + 0.1, deck_d * 0.5 - 0.1]:
		var rail := MeshInstance3D.new()
		var rail_mesh := BoxMesh.new()
		rail_mesh.size = Vector3(deck_w, 0.22, 0.12)
		rail.mesh = rail_mesh
		rail.material_override = rail_mat
		rail.position = Vector3(cx, 0.13, cz + dz)
		root.add_child(rail)

	var pier_mat := _quad_mat(Color(0.5, 0.5, 0.52))
	for px in [3.0, 8.0, 13.0]:
		var pier := MeshInstance3D.new()
		var pier_mesh := BoxMesh.new()
		pier_mesh.size = Vector3(0.5, 0.5, deck_d - 0.6)
		pier.mesh = pier_mesh
		pier.material_override = pier_mat
		pier.position = Vector3(px, -0.35, cz)
		root.add_child(pier)

	# The two arches of the "M".
	var arch_mat := _quad_mat(Color(0.88, 0.9, 0.94))
	for ax in [4.2, 11.6]:
		var arch := MeshInstance3D.new()
		var prism := PrismMesh.new()
		prism.size = Vector3(6.4, 1.5, 0.18)
		arch.mesh = prism
		arch.material_override = arch_mat
		arch.position = Vector3(ax, 0.77, cz)
		root.add_child(arch)

	# Center divider + painted name on the deck.
	var stripe := MeshInstance3D.new()
	var stripe_mesh := PlaneMesh.new()
	stripe_mesh.size = Vector2(deck_w, 0.14)
	stripe.mesh = stripe_mesh
	stripe.material_override = _quad_mat(Color(0.82, 0.72, 0.24))
	stripe.position = Vector3(cx, 0.03, cz)
	root.add_child(stripe)
	var lbl := Label3D.new()
	lbl.text = "HERNANDO DE SOTO BR"
	lbl.font_size = 48
	lbl.pixel_size = 0.01
	lbl.modulate = Color(0.95, 0.95, 0.9, 0.9)
	lbl.outline_size = 6
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.position = Vector3(cx, 0.05, cz)
	root.add_child(lbl)

func _build_region_tints() -> void:
	var root := Node3D.new()
	root.name = "RegionTints"
	add_child(root)
	# Earlier regions in the list win label-wise, so draw them ON TOP (higher y)
	# where rects overlap.
	var idx := 0
	for r in MemphisLayout.REGIONS:
		if not r.has("tint"):
			idx += 1
			continue
		var y := 0.030 - float(idx) * 0.001
		_add_ground_quad(r["rect"] as Rect2i, r["tint"] as Color, y, root, str(r["name"]).replace(" ", ""))
		idx += 1

## Roads: asphalt quad + sidewalks (streets only) + dashed yellow center divider
## (two lanes) + flat painted street-name labels. Heights are staggered
## (sidewalk < interstate < street, horizontal < vertical) so crossing quads
## never z-fight at intersections. Divider dashes SKIP intersection tiles and
## the tiles under name labels, so crossings and text stay clean.
func _build_roads() -> void:
	var root := Node3D.new()
	root.name = "Roads"
	add_child(root)
	for r in MemphisLayout.ROADS:
		var kind := str(r["kind"])
		if kind == "bridge":
			continue # built as a real deck in _build_bridge()
		var rect: Rect2i = r["rect"]
		var horizontal := rect.size.x >= rect.size.y
		var color := Color(0.22, 0.22, 0.24) if kind == "interstate" else Color(0.31, 0.31, 0.33)
		var y: float
		if kind == "interstate":
			y = 0.036 if horizontal else 0.038
		else:
			y = 0.044 if horizontal else 0.046
		var label := str(r["name"]).replace(" ", "")
		_add_ground_quad(rect, color, y, root, label)
		if kind == "street":
			_add_sidewalks(rect, horizontal, root)
		var label_alongs := _label_alongs(rect, horizontal)
		_add_road_divider(rect, horizontal, y + 0.004, root, label_alongs)
		_add_road_labels(rect, horizontal, str(r["name"]), label_alongs, root)

## Where along the road (tile offsets from rect origin) name labels sit.
func _label_alongs(rect: Rect2i, horizontal: bool) -> Array[float]:
	var len_tiles := rect.size.x if horizontal else rect.size.y
	var count := maxi(1, int(len_tiles / 26.0))
	var out: Array[float] = []
	for i in count:
		out.append((float(i) + 0.5) * float(len_tiles) / float(count))
	return out

## Dashed yellow center line, one dash per tile — skipping tiles that belong to
## another road (intersections) and a gap around each painted name label.
func _add_road_divider(rect: Rect2i, horizontal: bool, y: float, parent: Node3D, label_alongs: Array[float]) -> void:
	var len_tiles := rect.size.x if horizontal else rect.size.y
	var dash_mat := _quad_mat(Color(0.82, 0.72, 0.24))
	var cx_center := (rect.position.x + rect.size.x * 0.5) * GameConfig.TILE_SIZE
	var cz_center := (rect.position.y + rect.size.y * 0.5) * GameConfig.TILE_SIZE
	for i in len_tiles:
		var along := float(i) + 0.5
		# Gap under the street-name text so the paint doesn't fight the letters.
		var near_label := false
		for la in label_alongs:
			if absf(along - la) < 2.6:
				near_label = true
				break
		if near_label:
			continue
		# Skip intersection tiles (either lane tile inside ANOTHER road's rect).
		var t_a: Vector2i
		var t_b: Vector2i
		if horizontal:
			t_a = Vector2i(rect.position.x + i, rect.position.y)
			t_b = Vector2i(rect.position.x + i, rect.position.y + rect.size.y - 1)
		else:
			t_a = Vector2i(rect.position.x, rect.position.y + i)
			t_b = Vector2i(rect.position.x + rect.size.x - 1, rect.position.y + i)
		if _tile_on_other_road(t_a, rect) or _tile_on_other_road(t_b, rect):
			continue
		var dash := MeshInstance3D.new()
		var plane := PlaneMesh.new()
		plane.size = Vector2(0.55, 0.13) if horizontal else Vector2(0.13, 0.55)
		dash.mesh = plane
		dash.material_override = dash_mat
		if horizontal:
			dash.position = Vector3((rect.position.x + along) * GameConfig.TILE_SIZE, y, cz_center)
		else:
			dash.position = Vector3(cx_center, y, (rect.position.y + along) * GameConfig.TILE_SIZE)
		parent.add_child(dash)

func _tile_on_other_road(tile: Vector2i, own_rect: Rect2i) -> bool:
	for r in MemphisLayout.ROADS:
		var rr: Rect2i = r["rect"]
		if rr == own_rect:
			continue
		if rr.has_point(tile):
			return true
	return false

## Light concrete strips along both edges of a street (future human-NPC turf).
## Drawn BELOW all road asphalt so crossing roads pave over them cleanly.
func _add_sidewalks(rect: Rect2i, horizontal: bool, parent: Node3D) -> void:
	var walk_mat := _quad_mat(Color(0.62, 0.61, 0.58))
	var length := (rect.size.x if horizontal else rect.size.y) * GameConfig.TILE_SIZE
	var half_w := (rect.size.y if horizontal else rect.size.x) * 0.5 * GameConfig.TILE_SIZE
	var offset := half_w + 0.16
	var cx := (rect.position.x + rect.size.x * 0.5) * GameConfig.TILE_SIZE
	var cz := (rect.position.y + rect.size.y * 0.5) * GameConfig.TILE_SIZE
	for side in [-1.0, 1.0]:
		var walk := MeshInstance3D.new()
		walk.name = "Sidewalk"
		var plane := PlaneMesh.new()
		plane.size = Vector2(length, 0.3) if horizontal else Vector2(0.3, length)
		walk.mesh = plane
		walk.material_override = walk_mat
		if horizontal:
			walk.position = Vector3(cx, 0.034, cz + side * offset)
		else:
			walk.position = Vector3(cx + side * offset, 0.034, cz)
		parent.add_child(walk)

## Street names painted flat on the asphalt, repeated along long roads.
func _add_road_labels(rect: Rect2i, horizontal: bool, road_name: String, label_alongs: Array[float], parent: Node3D) -> void:
	for la in label_alongs:
		var lbl := Label3D.new()
		lbl.text = road_name.to_upper()
		lbl.font_size = 64
		lbl.pixel_size = 0.01
		lbl.modulate = Color(0.95, 0.95, 0.9, 0.9)
		lbl.outline_size = 6
		# Lie flat on the road, text running along the road's axis.
		lbl.rotation_degrees = Vector3(-90, 0, 0) if horizontal else Vector3(-90, 90, 0)
		var along := (rect.position.x if horizontal else rect.position.y) + la
		var cx := along * GameConfig.TILE_SIZE if horizontal else (rect.position.x + rect.size.x * 0.5) * GameConfig.TILE_SIZE
		var cz := (rect.position.y + rect.size.y * 0.5) * GameConfig.TILE_SIZE if horizontal else along * GameConfig.TILE_SIZE
		lbl.position = Vector3(cx, 0.065, cz)
		parent.add_child(lbl)

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
## Slice 6: they're also claimable — shapeshifting into one converts it into a
## shared "tree" world object (see Creature._register_claimed_tree).
func _build_trees() -> void:
	for pos in MemphisLayout.tree_tiles():
		var wp := GameConfig.tile_to_world(Vector2(pos))
		var obj := _spawn_world_object("tree_decor", Vector3(wp.x, 0, wp.z), trees_root)
		_scenery_trees[pos] = obj

## A scenery tree that became a shared object (someone shapeshifted into it):
## hide the original everywhere and unblock its tile.
func retire_scenery_tree(tile: Vector2i) -> void:
	GameState.blocked_tiles.erase(tile)
	var obj: WorldObject = _scenery_trees.get(tile)
	if obj and is_instance_valid(obj) and not obj.consumed:
		obj.consume()

## A scenery house that became a shared object (someone shapeshifted into it):
## hide the original everywhere and unblock its tile.
func retire_scenery_house(tile: Vector2i) -> void:
	GameState.blocked_tiles.erase(tile)
	var obj: WorldObject = _scenery_houses.get(tile)
	if obj and is_instance_valid(obj) and not obj.consumed:
		obj.consume()

## Houses are solid and lethal to vehicles that crash into them. Downtown gets
## towers instead, plus the Pyramid landmark at the north end.
## Slice 7: houses are claimable scenery (shapeshift converts one into a shared
## "house" row — see Creature._register_claimed_house).
func _build_buildings() -> void:
	for pos in MemphisLayout.house_tiles():
		var wp := GameConfig.tile_to_world(Vector2(pos))
		_scenery_houses[pos] = _spawn_world_object("house_decor", Vector3(wp.x, 0, wp.z), _buildings_root)
	for pos in MemphisLayout.tower_tiles():
		var wp := GameConfig.tile_to_world(Vector2(pos))
		_spawn_world_object("tower", Vector3(wp.x, 0, wp.z), _buildings_root)
	var pyr := GameConfig.tile_to_world(Vector2(MemphisLayout.PYRAMID_TILE))
	_pyramid_obj = _spawn_world_object("pyramid", Vector3(pyr.x, 0, pyr.z), _buildings_root)

# ---------------------------------------------------------------------------
# Landmarks (Slice 6): U of M, Shelby Farms, the Zoo, Airport + FedEx, Krogers,
# Tom Lee Park. Ground quads + flat labels + big-box structures.
# ---------------------------------------------------------------------------

func _build_landmarks() -> void:
	var root := Node3D.new()
	root.name = "Landmarks"
	add_child(root)
	# University of Memphis: campus lawn + brick halls.
	_add_ground_quad(MemphisLayout.UOFM_RECT, Color(0.36, 0.5, 0.3), 0.032, root, "UofM")
	_add_landmark_label("UNIVERSITY OF MEMPHIS", Vector2(59.5, 41.5), root)
	for t in MemphisLayout.UOFM_BUILDINGS:
		var wp := GameConfig.tile_to_world(Vector2(t))
		_spawn_world_object("campus_hall", Vector3(wp.x, 0, wp.z), _buildings_root)
	# Shelby Farms: park green, one lake, walking trail ring around it.
	_add_ground_quad(MemphisLayout.SHELBY_RECT, Color(0.34, 0.56, 0.3), 0.032, root, "ShelbyFarms")
	_add_landmark_label("SHELBY FARMS", Vector2(102.5, 34.2), root)
	var lakec := MemphisLayout.SHELBY_LAKE_CENTER
	var lake_wp := Vector3(lakec.x * GameConfig.TILE_SIZE, 0.04, lakec.y * GameConfig.TILE_SIZE)
	var lake := MeshInstance3D.new()
	var lake_mesh := CylinderMesh.new()
	lake_mesh.top_radius = MemphisLayout.SHELBY_LAKE_RADIUS * GameConfig.TILE_SIZE
	lake_mesh.bottom_radius = lake_mesh.top_radius
	lake_mesh.height = 0.02
	lake.mesh = lake_mesh
	lake.material_override = _quad_mat(Color(0.16, 0.36, 0.55))
	lake.position = lake_wp
	root.add_child(lake)
	var trail := MeshInstance3D.new()
	var trail_mesh := TorusMesh.new()
	trail_mesh.inner_radius = lake_mesh.top_radius + 0.15
	trail_mesh.outer_radius = lake_mesh.top_radius + 0.5
	trail.mesh = trail_mesh
	trail.material_override = _quad_mat(Color(0.62, 0.54, 0.4))
	trail.scale = Vector3(1, 0.02, 1)
	trail.position = Vector3(lake_wp.x, 0.036, lake_wp.z)
	root.add_child(trail)
	# Memphis Zoo — Egyptian-style entrance, two open-air pens, exhibit animals.
	_build_memphis_zoo(root)
	# Memphis International Airport + FedEx hub: apron, runway, terminal, hub.
	_add_ground_quad(MemphisLayout.AIRPORT_RECT, Color(0.5, 0.5, 0.52), 0.032, root, "Airport")
	_add_ground_quad(MemphisLayout.AIRPORT_RUNWAY, Color(0.2, 0.2, 0.22), 0.04, root, "Runway")
	_add_landmark_label("MEMPHIS INTL AIRPORT", Vector2(65.5, 88.0), root)
	_add_landmark_label("FEDEX HUB", Vector2(69.0, 86.2), root)
	var term_wp := GameConfig.tile_to_world(Vector2(MemphisLayout.AIRPORT_TERMINAL))
	_spawn_world_object("terminal", Vector3(term_wp.x, 0, term_wp.z), _buildings_root)
	var fedex_wp := GameConfig.tile_to_world(Vector2(MemphisLayout.FEDEX_HUB))
	_spawn_world_object("fedex", Vector3(fedex_wp.x, 0, fedex_wp.z), _buildings_root)
	# Runway centerline dashes.
	for i in 6:
		var dash := MeshInstance3D.new()
		var dp := PlaneMesh.new()
		dp.size = Vector2(1.2, 0.1)
		dash.mesh = dp
		dash.material_override = _quad_mat(Color(0.9, 0.9, 0.9))
		dash.position = Vector3((60.0 + i * 2.2), 0.046, 90.5)
		root.add_child(dash)
	# Tom Lee Park: riverfront green below Downtown.
	_add_ground_quad(MemphisLayout.TOM_LEE_RECT, Color(0.32, 0.55, 0.3), 0.032, root, "TomLee")
	_add_landmark_label("TOM LEE PARK", Vector2(18.5, 46.5), root)
	# Krogers: brand box + parking lot pad (parked Altimas/carts are seeded rows).
	for site in MemphisLayout.KROGER_SITES:
		var wp := GameConfig.tile_to_world(Vector2(site))
		_spawn_world_object("kroger", Vector3(wp.x, 0, wp.z), _buildings_root)
		_add_ground_quad(Rect2i(site + Vector2i(-1, 1), Vector2i(5, 2)), Color(0.42, 0.42, 0.44), 0.032, root, "KrogerLot")
		_add_landmark_label("KROGER", Vector2(float(site.x) + 1.0, float(site.y) + 2.6), root)

func _build_memphis_zoo(parent: Node3D) -> void:
	_add_ground_quad(MemphisLayout.ZOO_RECT, Color(0.42, 0.5, 0.32), 0.032, parent, "Zoo")
	_add_ground_quad(MemphisLayout.ZOO_WALKWAY, Color(0.48, 0.44, 0.36), 0.033, parent, "ZooWalk")
	_add_ground_quad(Rect2i(49, 26, 5, 3), Color(0.5, 0.46, 0.36), 0.033, parent, "ZooPlaza")
	for enc in [MemphisLayout.TIGER_ENCLOSURE, MemphisLayout.BEAR_ENCLOSURE]:
		_add_ground_quad(enc, Color(0.52, 0.46, 0.34), 0.034, parent, "ZooPen")
	_add_landmark_label("TIGERS", Vector2(48.9, 24.2), parent)
	_add_landmark_label("GRIZZLIES", Vector2(54.1, 24.2), parent)
	_add_zoo_pen_props(parent)
	_build_zoo_fences(parent)
	_build_zoo_entrance(parent)

func _add_zoo_pen_props(parent: Node3D) -> void:
	var rock_mat := _quad_mat(Color(0.45, 0.42, 0.38))
	var log_mat := _quad_mat(Color(0.42, 0.3, 0.2))
	for center in [
		Vector2(MemphisLayout.TIGER_ENCLOSURE.position) + Vector2(1.6, 1.4),
		Vector2(MemphisLayout.BEAR_ENCLOSURE.position) + Vector2(1.8, 1.7),
	]:
		var rock := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.18
		sm.height = 0.22
		rock.mesh = sm
		rock.material_override = rock_mat
		rock.position = Vector3(center.x, 0.11, center.y)
		parent.add_child(rock)
		var log := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.35, 0.08, 0.16)
		log.mesh = bm
		log.material_override = log_mat
		log.position = Vector3(center.x - 0.32, 0.05, center.y + 0.26)
		log.rotation.y = 0.35
		parent.add_child(log)

func _build_zoo_fences(parent: Node3D) -> void:
	var fence_mat := _quad_mat(Color(0.52, 0.44, 0.32))
	_add_pen_fence(parent, MemphisLayout.TIGER_ENCLOSURE, fence_mat)
	_add_pen_fence(parent, MemphisLayout.BEAR_ENCLOSURE, fence_mat)
	# A short center divider keeps pens visually distinct but does not block the
	# south openings.
	_add_fence_segment(parent, Vector2(51.0, 23.0), Vector2(51.0, 26.2), fence_mat)

func _add_pen_fence(parent: Node3D, rect: Rect2i, mat: StandardMaterial3D) -> void:
	var x0 := float(rect.position.x)
	var x1 := float(rect.end.x)
	var y0 := float(rect.position.y)
	var y1 := float(rect.end.y)
	var gap_center := (x0 + x1) * 0.5
	var gap_half := 0.45
	# North + side rails.
	_add_fence_segment(parent, Vector2(x0, y0), Vector2(x1, y0), mat)
	_add_fence_segment(parent, Vector2(x0, y0), Vector2(x0, y1), mat)
	_add_fence_segment(parent, Vector2(x1, y0), Vector2(x1, y1), mat)
	# South split rails with a centered player/animal opening.
	_add_fence_segment(parent, Vector2(x0, y1), Vector2(gap_center - gap_half, y1), mat)
	_add_fence_segment(parent, Vector2(gap_center + gap_half, y1), Vector2(x1, y1), mat)
	for p in [
		Vector2(x0, y0), Vector2(x1, y0), Vector2(x0, y1), Vector2(x1, y1),
		Vector2(gap_center - gap_half, y1), Vector2(gap_center + gap_half, y1)
	]:
		_add_fence_post(parent, p, mat)

func _add_fence_segment(parent: Node3D, a: Vector2, b: Vector2, mat: StandardMaterial3D) -> void:
	var d := b - a
	var seg_len := d.length()
	if seg_len < 0.04:
		return
	var rail := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(seg_len, 0.2, 0.045)
	rail.mesh = box
	rail.material_override = mat
	var mid := (a + b) * 0.5
	rail.position = Vector3(mid.x, 0.1, mid.y)
	# Box length is along +X, so rotate from X-axis to segment direction.
	rail.rotation.y = -atan2(d.y, d.x)
	parent.add_child(rail)

func _add_fence_post(parent: Node3D, p: Vector2, mat: StandardMaterial3D) -> void:
	var pole := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.07, 0.26, 0.07)
	pole.mesh = pm
	pole.material_override = mat
	pole.position = Vector3(p.x, 0.13, p.y)
	parent.add_child(pole)

func _build_zoo_entrance(parent: Node3D) -> void:
	var gate := Vector2(MemphisLayout.ZOO_GATE_TILE)
	var sand := _quad_mat(Color(0.76, 0.66, 0.46))
	var band_red := _quad_mat(Color(0.6, 0.2, 0.12))
	var band_teal := _quad_mat(Color(0.1, 0.4, 0.36))
	const PYLON_SLANT := 0.28
	const PYLON_H := 1.55
	const PYLON_W := 0.85
	const PYLON_D := 0.65
	const CAP_H := 0.32
	var pz := gate.y + 0.55
	for side in [-1.0, 1.0]:
		var px: float = gate.x + side * 1.35
		var pylon := MeshInstance3D.new()
		var body := BoxMesh.new()
		body.size = Vector3(PYLON_W, PYLON_H, PYLON_D)
		pylon.mesh = body
		pylon.material_override = sand
		pylon.position = Vector3(px, PYLON_H * 0.5, pz)
		parent.add_child(pylon)
		# Sloped cap — same outward angle on both pylons.
		var cap := MeshInstance3D.new()
		var cap_mesh := BoxMesh.new()
		cap_mesh.size = Vector3(PYLON_W + 0.06, CAP_H, PYLON_D + 0.05)
		cap.mesh = cap_mesh
		cap.material_override = sand
		cap.position = Vector3(px + side * 0.04, PYLON_H + CAP_H * 0.42, pz)
		# Both top caps lean the same way (match real entrance styling).
		cap.rotation.x = -PYLON_SLANT
		parent.add_child(cap)
		for row in 2:
			var band := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(PYLON_W + 0.02, 0.07, PYLON_D + 0.02)
			band.mesh = bm
			band.material_override = band_red if row % 2 == 0 else band_teal
			band.position = Vector3(px, 0.42 + row * 0.38, pz + 0.02)
			parent.add_child(band)
	# Lintel beam between pylons.
	var lintel := MeshInstance3D.new()
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(2.05, 0.28, 0.5)
	lintel.mesh = lintel_mesh
	lintel.material_override = sand
	lintel.position = Vector3(gate.x, PYLON_H + 0.05, pz)
	parent.add_child(lintel)
	# Sloped lintel caps matching pylon angle.
	for side in [-1.0, 1.0]:
		var lc := MeshInstance3D.new()
		var lcm := BoxMesh.new()
		lcm.size = Vector3(0.55, CAP_H, 0.52)
		lc.mesh = lcm
		lc.material_override = sand
		lc.position = Vector3(gate.x + side * 1.05, PYLON_H + CAP_H * 0.42, pz)
		lc.rotation.x = -PYLON_SLANT
		parent.add_child(lc)
	# Sign centered on the horizontal entrance beam above the opening.
	var sign := Label3D.new()
	sign.text = "MEMPHIS ZOO"
	sign.font_size = 24
	sign.pixel_size = 0.006
	sign.modulate = Color(0.12, 0.32, 0.68)
	sign.rotation_degrees = Vector3(0, 0, 0)
	# Vertically center on the front beam face and keep slightly proud of it.
	sign.position = Vector3(gate.x, PYLON_H + 0.02, pz + 0.26)
	parent.add_child(sign)

func _add_landmark_label(text: String, tile: Vector2, parent: Node3D) -> void:
	var lbl := Label3D.new()
	lbl.text = text
	lbl.font_size = 56
	lbl.pixel_size = 0.011
	lbl.modulate = Color(1.0, 0.97, 0.85, 0.95)
	lbl.outline_size = 8
	lbl.rotation_degrees = Vector3(-90, 0, 0)
	lbl.position = Vector3(tile.x * GameConfig.TILE_SIZE, 0.07, tile.y * GameConfig.TILE_SIZE)
	parent.add_child(lbl)

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
		0.05, # above the region tint layers (0.018-0.030)
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
			# Claimable scenery: Becoming one converts it into a shared "tree" row.
			return {"kind": "tree", "form_key": FormDefs.TREE, "visual": "tree", "radius": 0.5, "display_name": "Tree"}
		"tree":
			# A formerly-scenery tree that entered the shared object world.
			return {"kind": "tree", "form_key": FormDefs.TREE, "visual": "tree", "radius": 0.5, "display_name": "Tree"}
		"building":
			return {"kind": "building", "form_key": "", "visual": "building", "radius": 0.9, "display_name": "House"}
		"campus_hall":
			return {"kind": "building", "form_key": "", "visual": "campus", "radius": 0.9, "display_name": "University Hall"}
		"house_decor":
			# Claimable scenery: Becoming one converts it into a shared "house" row.
			return {"kind": "building", "form_key": FormDefs.HOUSE, "visual": "building", "radius": 0.9, "display_name": "House"}
		"house":
			# A formerly-scenery house that entered the shared object world.
			return {"kind": "building", "form_key": FormDefs.HOUSE, "visual": "building", "radius": 0.9, "display_name": "House"}
		"tower":
			return {"kind": "building", "form_key": "", "visual": "tower", "radius": 0.85, "display_name": "Tower"}
		"pyramid":
			return {"kind": "building", "form_key": FormDefs.PYRAMID, "visual": "pyramid", "radius": 2.2, "display_name": "The Pyramid"}
		"kroger":
			return {"kind": "building", "form_key": "", "visual": "bigbox", "radius": 1.2, "display_name": "Kroger", "tint": Color(0.12, 0.3, 0.62)}
		"fedex":
			return {"kind": "building", "form_key": "", "visual": "bigbox", "radius": 1.2, "display_name": "FedEx Hub", "tint": Color(0.3, 0.12, 0.5)}
		"terminal":
			return {"kind": "building", "form_key": "", "visual": "bigbox", "radius": 1.2, "display_name": "Airport Terminal", "tint": Color(0.35, 0.4, 0.45)}
		"altima":
			return {"kind": "prop", "form_key": FormDefs.ALTIMA, "visual": "altima", "radius": 0.55, "display_name": "Rusty Altima"}
		"charger":
			return {"kind": "prop", "form_key": FormDefs.CHARGER, "visual": "charger", "radius": 0.55, "display_name": "Dodge Charger With Temp Tags"}
		"truck":
			return {"kind": "prop", "form_key": FormDefs.TRUCK, "visual": "truck", "radius": 0.65, "display_name": "Truck"}
		"atm":
			# Not shapeshiftable — a loot piñata: any vehicle ramming it bursts
			# out 3 money bags (see try_strike_atm), then it reseeds next day.
			return {"kind": "prop", "form_key": "", "visual": "atm", "radius": 0.45, "display_name": "ATM"}
		"magnolia":
			return {"kind": "tree", "form_key": FormDefs.MAGNOLIA, "visual": "magnolia", "radius": 0.5, "display_name": "Small Tree"}
		"propane":
			return {"kind": "propane", "form_key": FormDefs.PROPANE, "visual": "propane", "radius": 0.45, "display_name": "Propane Tank"}
		"bbq_grill":
			return {"kind": "propane", "form_key": FormDefs.BBQ_GRILL, "visual": "bbq_grill", "radius": 0.5, "display_name": "BBQ Grill"}
		"pothole":
			return {"kind": "pothole", "form_key": FormDefs.POTHOLE, "visual": "pothole", "radius": 0.5, "display_name": "Pothole"}
		"cart":
			return {"kind": "cart", "form_key": FormDefs.SHOPPING_CART, "visual": "cart", "radius": 0.4, "display_name": "Shopping Cart"}
		"bus":
			# kind "prop", NOT "mata_bus": a PARKED bus is harmless (only a
			# player-driven bus, resolved via remote creatures, can kill).
			return {"kind": "prop", "form_key": FormDefs.MATA_BUS, "visual": "mata_bus", "radius": 0.75, "display_name": "MATA Bus"}
		"smoker":
			return {"kind": "prop", "form_key": FormDefs.BBQ_SMOKER, "visual": "smoker", "radius": 0.5, "display_name": "BBQ Smoker"}
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
	# Parked vehicles face a pseudo-random direction hashed from their tile —
	# stable across clients/reloads, but no more identical default rotations.
	# (Pop-out overwrites this with the player's actual parked heading.)
	if FormDefs.is_vehicle(obj.form_key):
		obj.rotation.y = _parked_yaw(world_pos)
	return obj

func _parked_yaw(world_pos: Vector3) -> float:
	var t := GameConfig.world_to_tile(world_pos)
	return float(absi(hash(t)) % 6283) * 0.001

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
	_prune_invalid_shared_objects()
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
	var carried_rows_by_user: Dictionary = {}
	var safe_houses: Dictionary = {}
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
			var dead := _get_shared_object(id)
			if dead:
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
		# Smoke clouds are transient FX rows, not props: register (using the row's
		# age so late joiners see the remaining duration), and clean up stale rows
		# whose deployer never got to delete them (death/disconnect).
		if type_key == "smoke_cloud":
			if _smoke_clouds.has(id):
				continue
			var remain := GameConfig.SMOKE_CLOUD_DURATION_SEC - _row_age_sec(row)
			if remain <= 0.5:
				note_deleted(id)
				NetworkService.delete_world_object(id)
			else:
				register_smoke_cloud(id, GameConfig.tile_to_world(tile), remain)
			continue
		# Kill-feed broadcasts: transient message rows, not props. Toast once for
		# everyone except the victim (they already saw their own death message);
		# the victim deletes the row after a few seconds, and we GC stale rows
		# if the victim disconnected before cleanup.
		if type_key == "kill_event":
			if not _kill_events_seen.has(id):
				_kill_events_seen[id] = true
				if str(row.get("possessed_by", "")) != my_uid:
					var msg := _row_owner_name(row)
					if not msg.is_empty():
						GameState.show_toast(msg)
			if _row_age_sec(row) > 20.0:
				note_deleted(id)
				NetworkService.delete_world_object(id)
			continue
		# Pyramid abductions: transient FX rows. Play the beam/ship once, kill
		# our own player if they're in the beam (client-local kill rule), and
		# GC stale rows whose caster never cleaned up.
		if type_key == "abduction":
			if not _abductions_seen.has(id):
				_abductions_seen[id] = true
				_run_abduction(tile, str(row.get("possessed_by", "")) == my_uid)
			if _row_age_sec(row) > 15.0:
				note_deleted(id)
				NetworkService.delete_world_object(id)
			continue
		# Explosions: transient rows broadcast blast position + radius so every
		# client applies lethal radius to their own player and local NPCs.
		if type_key == "explosion":
			if not _explosions_seen.has(id):
				_explosions_seen[id] = true
				# The caster already ran the full blast (FX + scatter); remotes
				# only need damage + FX from the synced row.
				if str(row.get("possessed_by", "")) != my_uid:
					var rad := float(_row_owner_name(row))
					if rad <= 0.0:
						rad = Creature.EXPLOSION_RADIUS
					spawn_explosion(GameConfig.tile_to_world(tile), rad, true)
			if _row_age_sec(row) > 12.0:
				note_deleted(id)
				NetworkService.delete_world_object(id)
			continue
		# Destroyed props awaiting reseed ("reseed:<due-unix>" owner marker):
		# hidden for everyone until the due time, then ANY client moves the row
		# to a fresh home-region tile and clears the marker. The marker lives on
		# the server so the delay survives the destroyer disconnecting.
		var owner_raw := _row_owner_name(row)
		if owner_raw.begins_with("reseed:"):
			if Time.get_unix_time_from_system() >= float(owner_raw.substr(7).to_int()):
				var fresh := GameState.free_drop_tile(
					GameConfig.reseed_tile_for_type(type_key, tile))
				note_local_authority(id)
				NetworkService.update_world_object(id, {
					"x": fresh.x, "y": fresh.y, "state": "idle",
					"possessed_by": null, "owner_name": null,
				})
			var hidden := _get_shared_object(id)
			if hidden:
				hidden.consume()
			continue
		# A claimed scenery tree entered the shared world: hide the original
		# scenery tree at its home tile (encoded in owner_name) for everyone.
		if type_key == "tree" and not _tree_homes_done.has(id):
			var home := _row_owner_name(row)
			if home.begins_with("home:"):
				_tree_homes_done[id] = true
				var parts := home.substr(5).split(",")
				if parts.size() == 2:
					retire_scenery_tree(Vector2i(int(parts[0]), int(parts[1])))
		# Same for claimed scenery houses; their owner_name may also carry a
		# "safe:<NAME>" segment (a claimed personal safe house).
		if type_key == "house":
			if not _house_homes_done.has(id):
				var howner := WorldObject.parse_home_part(_row_owner_name(row))
				if howner.begins_with("home:"):
					_house_homes_done[id] = true
					var hparts := howner.substr(5).split(",")
					if hparts.size() == 2:
						retire_scenery_house(Vector2i(int(hparts[0]), int(hparts[1])))
			var safe_name := WorldObject.parse_safe_owner(_row_owner_name(row))
			if not safe_name.is_empty():
				safe_houses[safe_name] = {"id": id, "tile": tile, "raw": _row_owner_name(row)}
		var state := str(row.get("state", "idle"))
		var possessed_by := str(row.get("possessed_by", ""))
		var possessed := state == "possessed" and not possessed_by.is_empty()
		var carried := state == "carried" and not possessed_by.is_empty()
		# THEFT (Slice 7): the server says another player now hauls something we
		# still think we're carrying — it was stolen right off our back.
		if carried and possessed_by != my_uid and id in locally_carried:
			if pc and is_instance_valid(pc) and pc.has_method("on_money_stolen"):
				pc.on_money_stolen(id, display_name_for_uid(possessed_by))
			locally_carried.erase(id)
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
				# Index the actual rows too — the Steal action needs ids/owners.
				if not carried_rows_by_user.has(possessed_by):
					carried_rows_by_user[possessed_by] = []
				carried_rows_by_user[possessed_by].append(
					{"id": id, "tier": t, "type": type_key, "owner": _row_owner_name(row)})
		# carried by an ABSENT player (disconnected mid-haul) -> render idle
		elif possessed and possessed_by == my_uid:
			# Two cases. (a) Session restore: I reloaded while shapeshifted, so I'm
			# STILL wearing this form but lost the local object link — re-adopt it
			# (otherwise I see my own worn object duplicated at its old spot).
			# (b) I've genuinely popped out and the release PATCH is lagging — show it.
			var cfg_form := str(_object_cfg(type_key).get("form_key", ""))
			if pc and is_instance_valid(pc) and locally_possessed_id.is_empty() \
					and not cfg_form.is_empty() and cfg_form == pc.form_key:
				var adopt := _get_shared_object(id)
				if adopt == null:
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
		var obj := _get_shared_object(id)
		if hide_prop:
			if obj:
				obj.consume()
			continue
		# Idle (or orphaned-possessed): render at its shared position.
		var world_pos := GameConfig.tile_to_world(tile)
		if obj == null:
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
	# A just-claimed/unclaimed house row may be skipped by the local-authority
	# grace window; keep the locally-known entry alive until the PATCH lands.
	for owner in _safe_houses.keys():
		var entry: Dictionary = _safe_houses[owner]
		if _local_authority.has(str(entry.get("id", ""))) and not safe_houses.has(owner):
			safe_houses[owner] = entry
	_carried_rows_by_user = carried_rows_by_user
	_safe_houses = safe_houses
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
		var gone := _get_shared_object(id)
		if gone:
			gone.queue_free()
		_shared_objects.erase(id)

# ---------------------------------------------------------------------------
# Smoke clouds (Slice 3): synced via temporary world_objects rows.
# ---------------------------------------------------------------------------

## Register a smoke cloud (local deploy or seen via poll) and build its visual.
# ---------------------------------------------------------------------------
# Pyramid abduction (Slice 6): beam + ship FX, synced via transient rows.
# ---------------------------------------------------------------------------

const ABDUCTION_RADIUS_TILES := 6.0
const ABDUCTION_FX_SEC := 8.0

## Caster-side entry: play the FX locally right away and remember the row id so
## the next poll doesn't replay it.
func register_abduction(id: String, tile: Vector2) -> void:
	if not id.is_empty():
		_abductions_seen[id] = true
	_run_abduction(tile, true)

## Caster calls this once the shared row id is known (FX already played).
func note_abduction_seen(id: String) -> void:
	if not id.is_empty():
		_abductions_seen[id] = true

## Play the beam/ship and resolve consequences: nearby NPC vehicles get taken,
## and OUR player (if in the beam, not the pyramid itself) gets abducted.
func _run_abduction(tile: Vector2, i_am_caster: bool) -> void:
	var wpos := GameConfig.tile_to_world(tile)
	_spawn_abduction_fx(wpos)
	# If the show is anywhere near our screen, pull the camera back so the beam
	# and saucer (high above the close-zoom frame) are actually visible.
	var me := GameState.player_creature
	if me and is_instance_valid(me):
		var d := Vector2(me.position.x, me.position.z).distance_to(Vector2(wpos.x, wpos.z))
		if d < 24.0 * GameConfig.TILE_SIZE:
			GameState.abduction_zoom_requested.emit(ABDUCTION_FX_SEC)
	var traffic := GameState.npc_traffic
	if traffic != null and is_instance_valid(traffic) and traffic.has_method("abduct_near"):
		traffic.abduct_near(wpos, ABDUCTION_RADIUS_TILES)
	if i_am_caster:
		return
	var player := GameState.player_creature
	if player == null or not is_instance_valid(player) or player.is_dead or player.is_spawning:
		return
	if player.form_key == FormDefs.PYRAMID:
		return # pyramids don't abduct pyramids
	var d := Vector2(player.position.x, player.position.z).distance_to(Vector2(wpos.x, wpos.z))
	if d <= ABDUCTION_RADIUS_TILES * GameConfig.TILE_SIZE:
		player.apply_death(FormDefs.DEATH_ABDUCTED, false)

## The beam: a glowing column from the pyramid apex; the ship: a saucer that
## drops in above it, hovers while the beam runs, then zips away.
func _spawn_abduction_fx(world_pos: Vector3) -> void:
	var root := Node3D.new()
	root.position = Vector3(world_pos.x, 0, world_pos.z)
	add_child(root)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam_mat.albedo_color = Color(0.5, 1.0, 0.7, 0.45)
	beam_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var beam := MeshInstance3D.new()
	var beam_mesh := CylinderMesh.new()
	# Tall column reaching into the sky: at default zoom anything hovering just
	# above the apex is off the top of the frame, so the beam has to be big to
	# read on screen.
	beam_mesh.top_radius = 1.4
	beam_mesh.bottom_radius = 0.5
	beam_mesh.height = 9.0
	beam.mesh = beam_mesh
	beam.material_override = beam_mat
	beam.position = Vector3(0, 2.3 + 4.5, 0)
	beam.scale = Vector3(0.05, 1.0, 0.05)
	root.add_child(beam)
	var ship := Node3D.new()
	var hull := MeshInstance3D.new()
	var hull_mesh := CylinderMesh.new()
	hull_mesh.top_radius = 0.9
	hull_mesh.bottom_radius = 1.6
	hull_mesh.height = 0.5
	hull.mesh = hull_mesh
	hull.material_override = _quad_mat(Color(0.4, 0.44, 0.5))
	ship.add_child(hull)
	var dome := MeshInstance3D.new()
	var dome_mesh := SphereMesh.new()
	dome_mesh.radius = 0.6
	dome_mesh.height = 0.8
	dome.mesh = dome_mesh
	var dome_mat := StandardMaterial3D.new()
	dome_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dome_mat.albedo_color = Color(0.55, 0.95, 0.75, 0.8)
	dome_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dome.material_override = dome_mat
	dome.position = Vector3(0, 0.35, 0)
	ship.add_child(dome)
	ship.position = Vector3(0, 14.0, 0)
	root.add_child(ship)
	var tw := root.create_tween()
	# Ship swoops in low over the apex (a big looming saucer — heights above
	# ~5.5 are out of frame at default zoom), beam blooms, hold, then leaves.
	tw.tween_property(ship, "position:y", 5.0, 0.7).set_ease(Tween.EASE_OUT)
	tw.tween_property(beam, "scale", Vector3(1, 1, 1), 0.4).set_ease(Tween.EASE_OUT)
	tw.tween_interval(ABDUCTION_FX_SEC - 2.1)
	tw.tween_property(beam, "scale", Vector3(0.05, 1.0, 0.05), 0.4).set_ease(Tween.EASE_IN)
	tw.tween_property(ship, "position:y", 30.0, 0.6).set_ease(Tween.EASE_IN)
	tw.tween_callback(root.queue_free)

func register_smoke_cloud(id: String, world_pos: Vector3, duration: float) -> void:
	var key := id if not id.is_empty() else "local_%d" % Time.get_ticks_msec()
	if _smoke_clouds.has(key):
		return
	var node := _make_smoke_node(world_pos)
	add_child(node)
	_smoke_clouds[key] = {
		"pos": world_pos,
		"until": Time.get_ticks_msec() + int(duration * 1000.0),
		"node": node,
	}

## A puffy cluster of soft gray blobs; scales in for a quick "FWOOSH" feel.
func _make_smoke_node(world_pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = Vector3(world_pos.x, 0.0, world_pos.z)
	var r := GameConfig.SMOKE_CLOUD_RADIUS_TILES * GameConfig.TILE_SIZE
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.62, 0.62, 0.64, 0.55)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(world_pos)
	for i in 9:
		var blob := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var br := rng.randf_range(r * 0.35, r * 0.6)
		mesh.radius = br
		mesh.height = br * 1.6
		blob.mesh = mesh
		blob.material_override = mat
		var a := rng.randf() * TAU
		var d := rng.randf_range(0.0, r * 0.62)
		blob.position = Vector3(cos(a) * d, rng.randf_range(0.3, 1.1), sin(a) * d)
		root.add_child(blob)
	root.scale = Vector3.ONE * 0.15
	var tween := create_tween()
	tween.tween_property(root, "scale", Vector3.ONE, 0.45).set_trans(Tween.TRANS_BACK)
	return root

func _in_smoke(world_pos: Vector3) -> bool:
	var r := GameConfig.SMOKE_CLOUD_RADIUS_TILES * GameConfig.TILE_SIZE
	var p := Vector2(world_pos.x, world_pos.z)
	for key in _smoke_clouds:
		var cp: Vector3 = _smoke_clouds[key]["pos"]
		if p.distance_to(Vector2(cp.x, cp.z)) <= r:
			return true
	return false

func _process(delta: float) -> void:
	_update_occlusion_fades(delta)
	_update_smoke_clouds()
	_update_pyramid_visibility()

## While ANY creature is shapeshifted into the Pyramid, the scenery pyramid
## hides (the creature's synced form stands in for it — no duplicate).
func _update_pyramid_visibility() -> void:
	if _pyramid_obj == null or not is_instance_valid(_pyramid_obj) or _pyramid_obj.consumed:
		return
	var claimed := false
	for c in GameState.creatures.values():
		if c != null and is_instance_valid(c) and not c.is_dead and c.form_key == FormDefs.PYRAMID:
			claimed = true
			break
	_pyramid_obj.visible = not claimed

## Fade any tall solid (building/tower/tree/pyramid) that sits between the
## camera and the local player so the player is never hidden behind it.
## Cheap segment test in XZ + a height check, throttled to 10Hz.
var _occ_accum := 0.0

func _update_occlusion_fades(delta: float) -> void:
	_occ_accum += delta
	if _occ_accum < 0.1:
		return
	_occ_accum = 0.0
	var player := GameState.player_creature
	var cam := get_viewport().get_camera_3d() if is_inside_tree() else null
	var have_ray: bool = player != null and is_instance_valid(player) and cam != null
	var a := Vector2.ZERO
	var ab := Vector2.ZERO
	var ab_len2 := 0.0
	var cam_y := 0.0
	var player_y := 0.0
	if have_ray:
		a = Vector2(cam.global_position.x, cam.global_position.z)
		var b := Vector2(player.position.x, player.position.z)
		ab = b - a
		ab_len2 = ab.length_squared()
		cam_y = cam.global_position.y
		player_y = player.position.y + 0.4
	for obj in GameState.world_objects:
		if not is_instance_valid(obj):
			continue
		if obj.kind != "building" and obj.kind != "tree":
			continue
		var fade := false
		if have_ray and ab_len2 > 0.01:
			var o := Vector2(obj.position.x, obj.position.z)
			var t := clampf((o - a).dot(ab) / ab_len2, 0.0, 1.0)
			# Ignore hits basically at the player/camera; only true in-betweens.
			if t > 0.05 and t < 0.97:
				var closest := a + ab * t
				if closest.distance_to(o) < obj.radius + 0.45:
					var ray_h := lerpf(cam_y, player_y, t)
					fade = ray_h < obj.occlusion_height()
		obj.set_occlusion_faded(fade)

## Expire finished clouds and apply concealment: remote players and loose money
## inside any cloud are invisible (the local player always sees themself).
func _update_smoke_clouds() -> void:
	if _smoke_clouds.is_empty():
		return
	var now := Time.get_ticks_msec()
	for key in _smoke_clouds.keys():
		if now > int(_smoke_clouds[key]["until"]):
			var node: Node3D = _smoke_clouds[key]["node"]
			if is_instance_valid(node):
				var tween := create_tween()
				tween.tween_property(node, "scale", Vector3.ONE * 0.05, 0.5)
				tween.tween_callback(node.queue_free)
			_smoke_clouds.erase(key)
	var any_active := not _smoke_clouds.is_empty()
	for uid in _remote_by_user:
		var remote: Creature = _remote_by_user[uid]
		if is_instance_valid(remote):
			remote.visible = not (any_active and _in_smoke(remote.position))
	for obj in GameState.world_objects:
		if is_instance_valid(obj) and obj.is_money() and not obj.consumed:
			obj.visible = not (any_active and _in_smoke(obj.position))
	# All clouds just ended -> one final pass above already restored visibility.

## Seconds since a row's updated_at stamp ("YYYY-MM-DDTHH:MM:SSZ", UTC).
func _row_age_sec(row: Dictionary) -> float:
	var stamp := str(row.get("updated_at", ""))
	if stamp.length() < 19:
		return 0.0
	var then := Time.get_unix_time_from_datetime_string(stamp.substr(0, 19))
	if then <= 0:
		return 0.0
	return maxf(0.0, Time.get_unix_time_from_system() - float(then))

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

## A claimed NPC vehicle becomes a real world object (possessed by the claimer).
## Spawned consumed-side-up by the caller; tracked once the create returns an id.
func materialize_claimed_vehicle(type_key: String, world_pos: Vector3) -> WorldObject:
	_ensure_objects_root()
	return _spawn_world_object(type_key, world_pos, _objects_root)

## Track a locally-created object under its server row id so the next poll
## matches it instead of spawning a duplicate.
func track_shared_object(obj: WorldObject) -> void:
	if obj == null or not is_instance_valid(obj) or obj.object_id.is_empty():
		return
	_shared_objects[obj.object_id] = obj

# ---------------------------------------------------------------------------
# Slice 7 helpers: stealing + safe houses.
# ---------------------------------------------------------------------------

## Player name for a user_id from the remote roster ("Someone" if unknown).
func display_name_for_uid(uid: String) -> String:
	var remote: Creature = _remote_by_user.get(uid)
	if remote and is_instance_valid(remote) and not remote.creature_name.is_empty():
		return remote.creature_name
	return "Someone"

## Money rows a given player is hauling, per the latest poll:
## [{id, tier, type, owner}].
func carried_rows_for(uid: String) -> Array:
	return _carried_rows_by_user.get(uid, [])

## Nearest visible remote player within `radius` (world units of `pos`) who is
## hauling money: {"uid", "name", "rows"} or {}.
func nearest_carrier(pos: Vector2, radius: float) -> Dictionary:
	var best: Dictionary = {}
	var best_d := radius
	for uid in _carried_rows_by_user.keys():
		var rows: Array = _carried_rows_by_user[uid]
		if rows.is_empty():
			continue
		var remote: Creature = _remote_by_user.get(uid)
		if remote == null or not is_instance_valid(remote) or remote.is_dead or not remote.visible:
			continue
		var d := pos.distance_to(Vector2(remote.position.x, remote.position.z))
		if d <= best_d:
			best_d = d
			best = {"uid": uid, "name": remote.creature_name, "rows": rows}
	return best

## Hand the local player a WorldObject instance for a money row they just stole
## (the prop was hidden while the victim carried it, so it may not exist yet).
func claim_carried_object(id: String, type_key: String, world_pos: Vector3) -> WorldObject:
	var obj: WorldObject = _shared_objects.get(id)
	if obj == null or not is_instance_valid(obj):
		_ensure_objects_root()
		obj = _spawn_world_object(type_key, world_pos, _objects_root)
		obj.object_id = id
		_shared_objects[id] = obj
	obj.consume()
	return obj

## {"id": row id, "tile": Vector2} of a player's claimed safe house, or {}.
func safe_house_for(player_name: String) -> Dictionary:
	return _safe_houses.get(player_name, {})

## Record a claim/unclaim locally (instant respawn-choice availability while
## the owner_name PATCH is still in flight).
func note_safe_house(player_name: String, id: String, tile: Vector2, raw: String = "") -> void:
	if id.is_empty():
		_safe_houses.erase(player_name)
	else:
		_safe_houses[player_name] = {"id": id, "tile": tile, "raw": raw}

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
## to the local player and client-local NPCs. Nearby propane tanks / BBQ grills
## (and players wearing those forms) chain-detonate into further blasts.
## `from_sync` is true when another client's broadcast row triggered this —
## skip re-broadcast but still scatter money and propagate the chain locally.
func spawn_explosion(world_pos: Vector3, radius: float, from_sync: bool = false) -> void:
	if _explosion_chain_depth == 0:
		_explosion_chain_guard.clear()
		_explosion_chain_count = 0
	_explosion_chain_depth += 1
	_explosion_chain_count += 1
	if _explosion_chain_count > EXPLOSION_CHAIN_MAX:
		_explosion_chain_depth -= 1
		return
	_play_explosion_fx(world_pos, radius)
	_apply_explosion_hits(world_pos, radius)
	_scatter_money(world_pos, maxf(radius * 1.6, 3.0))
	if not from_sync:
		_broadcast_explosion(world_pos, radius)
	_propagate_explosion_chain(world_pos, radius)
	_explosion_chain_depth -= 1
	if _explosion_chain_depth == 0:
		_explosion_chain_guard.clear()

func _play_explosion_fx(world_pos: Vector3, radius: float) -> void:
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

func _apply_explosion_hits(world_pos: Vector3, radius: float) -> void:
	var player := GameState.player_creature
	if player and is_instance_valid(player) and player.has_method("apply_explosion"):
		player.apply_explosion(world_pos, radius)
	var hum := GameState.npc_humans
	if hum != null and is_instance_valid(hum) and hum.has_method("explosion_hit"):
		hum.explosion_hit(world_pos, radius)
	var zoo := GameState.zoo_animals
	if zoo != null and is_instance_valid(zoo) and zoo.has_method("explosion_hit"):
		zoo.explosion_hit(world_pos, radius)
	var traffic := GameState.npc_traffic
	if traffic != null and is_instance_valid(traffic) and traffic.has_method("explosion_hit"):
		traffic.explosion_hit(world_pos, radius)

## Detonate idle propane / BBQ props and shapeshifted players inside `radius`.
func _propagate_explosion_chain(center: Vector3, radius: float) -> void:
	var origin := Vector2(center.x, center.z)
	var pending: Array = []
	for obj in GameState.world_objects:
		if not is_instance_valid(obj) or obj.consumed:
			continue
		if not FormDefs.is_explosive_kind(obj.kind):
			continue
		var key := _explosion_chain_key_for_object(obj)
		if _explosion_chain_guard.has(key):
			continue
		var opos := Vector2(obj.position.x, obj.position.z)
		if origin.distance_to(opos) > radius + obj.radius:
			continue
		pending.append({"kind": "world", "key": key, "pos": obj.position, "obj": obj})
	for cid in GameState.creatures:
		var c: Creature = GameState.creatures[cid]
		if c == null or not is_instance_valid(c) or c.is_dead or c.is_spawning:
			continue
		if not FormDefs.is_explosive_kind(FormDefs.kind(c.form_key)):
			continue
		var ckey := _explosion_chain_key_for_creature(cid)
		if _explosion_chain_guard.has(ckey):
			continue
		var cpos := Vector2(c.position.x, c.position.z)
		if origin.distance_to(cpos) > radius + FormDefs.radius(c.form_key):
			continue
		pending.append({"kind": "creature", "key": ckey, "pos": c.position, "creature": c})
	for entry in pending:
		_explosion_chain_guard[entry["key"]] = true
		if str(entry["kind"]) == "world":
			_consume_explosive_object(entry["obj"])
		else:
			_detonate_explosive_creature(entry["creature"])
		spawn_explosion(entry["pos"], Creature.EXPLOSION_RADIUS, true)

func _explosion_chain_key_for_object(obj: WorldObject) -> String:
	if not obj.object_id.is_empty():
		return "obj:%s" % obj.object_id
	var t := Vector2i(int(floor(obj.position.x)), int(floor(obj.position.z)))
	return "obj:local:%d,%d" % [t.x, t.y]

func _explosion_chain_key_for_creature(creature_id: String) -> String:
	return "creature:%s" % creature_id

func _consume_explosive_object(obj: WorldObject) -> void:
	if obj == null or not is_instance_valid(obj) or obj.consumed:
		return
	reseed_destroyed_prop(obj)

func _detonate_explosive_creature(c: Creature) -> void:
	if c == null or not is_instance_valid(c) or c.is_dead:
		return
	if c.is_player and c.has_method("apply_death"):
		c.apply_death(FormDefs.DEATH_PROPANE, true)

## A prop was destroyed (exploded propane/grill, busted ATM): hide it now and
## bring it back later at a random open tile in its home region(s) — never
## instantly on the same spot. Shared rows get a "reseed:<due>" owner marker
## (any client finishes the reseed, so it survives disconnects); client-local
## fallback objects use a plain timer.
func reseed_destroyed_prop(obj: WorldObject) -> void:
	if obj == null or not is_instance_valid(obj):
		return
	var type_key := obj.type_key
	var tile := Vector2(GameConfig.world_to_tile(obj.position))
	obj.consume()
	var delay := GameConfig.reseed_delay_for_type(type_key)
	if not obj.object_id.is_empty() and NetworkService.is_online():
		var due := int(Time.get_unix_time_from_system() + delay)
		note_local_authority(obj.object_id)
		NetworkService.update_world_object(obj.object_id, {
			"state": "idle", "possessed_by": null,
			"owner_name": "reseed:%d" % due,
		})
		return
	var timer := get_tree().create_timer(delay)
	timer.timeout.connect(func() -> void:
		if not is_instance_valid(obj):
			return
		var fresh := GameState.free_drop_tile(GameConfig.reseed_tile_for_type(type_key, tile))
		var wp := GameConfig.tile_to_world(fresh)
		obj.respawn_at(wp)
		obj.spawn_world_pos = wp
		obj.spawn_tile = fresh)

# ---------------------------------------------------------------------------
# ATMs (July 6): ram one with any moving vehicle and it bursts into 3 unowned
# money bags, then reseeds in its region the NEXT day (reseed marker flow).
# ---------------------------------------------------------------------------

const ATM_BURST_BAGS := 3

## Live ATM cache, refreshed once per frame — NPC traffic probes every vehicle
## every frame, so scanning the full world-object list each call is too hot.
var _atm_cache: Array = []
var _atm_cache_frame := -1

func _live_atms() -> Array:
	var f := Engine.get_process_frames()
	if int(f) != _atm_cache_frame:
		_atm_cache_frame = int(f)
		_atm_cache = []
		for o in GameState.world_objects:
			var obj := o as WorldObject
			if obj != null and is_instance_valid(obj) and not obj.consumed and obj.type_key == "atm":
				_atm_cache.append(obj)
	return _atm_cache

## Called by the local player's vehicle contacts and by local NPC traffic.
## Returns true when an ATM within reach of `center` (world XZ) burst.
func try_strike_atm(center: Vector2, radius: float) -> bool:
	for o in _live_atms():
		var obj := o as WorldObject
		if obj == null or not is_instance_valid(obj) or obj.consumed:
			continue
		if center.distance_to(Vector2(obj.position.x, obj.position.z)) > radius + obj.radius:
			continue
		_burst_atm(obj)
		return true
	return false

func _burst_atm(obj: WorldObject) -> void:
	var tile := Vector2(GameConfig.world_to_tile(obj.position))
	GameState.show_toast("The ATM burst open!")
	spawn_money_combine_fx(obj.position)
	reseed_destroyed_prop(obj)
	for i in ATM_BURST_BAGS:
		var bag_tile := GameState.free_drop_tile(
			tile + Vector2(randf_range(-1.5, 1.5), randf_range(-1.5, 1.5)))
		_spawn_atm_bag(bag_tile)

func _spawn_atm_bag(tile: Vector2) -> void:
	var wp := GameConfig.tile_to_world(tile)
	if not NetworkService.is_online():
		spawn_money_object("money_bag", wp, "")
		return
	var created: Dictionary = await NetworkService.create_world_object(
		{"type": "money_bag", "x": tile.x, "y": tile.y, "state": "idle"})
	var id := str(created.get("id", ""))
	spawn_money_object("money_bag", wp, "", id)
	if not id.is_empty():
		note_local_authority(id)

func _broadcast_explosion(world_pos: Vector3, radius: float) -> void:
	if not NetworkService.is_online():
		return
	var tile := Vector2(GameConfig.world_to_tile(world_pos))
	var created: Dictionary = await NetworkService.create_world_object({
		"type": "explosion",
		"x": tile.x,
		"y": tile.y,
		"state": "idle",
		"owner_name": str(radius),
		"possessed_by": NetworkService.get_user_id(),
	})
	var id := str(created.get("id", ""))
	if id.is_empty():
		return
	await get_tree().create_timer(12.0).timeout
	note_deleted(id)
	NetworkService.delete_world_object(id)

## Blasts near money: loose stacks get flung to nearby open tiles, and COMBINED
## money breaks DOWN a tier (vault -> two bags, bag -> two stacks). Explosions
## never destroy money (design rule) — they just undo the bundling.
func _scatter_money(world_pos: Vector3, scatter_radius: float) -> void:
	var origin := Vector2(world_pos.x, world_pos.z)
	var hit: Array[WorldObject] = []
	for obj in GameState.world_objects:
		if not is_instance_valid(obj) or obj.consumed or not obj.is_money():
			continue
		if origin.distance_to(Vector2(obj.position.x, obj.position.z)) <= scatter_radius:
			hit.append(obj)
	for obj in hit:
		if obj.tier >= FormDefs.TIER_BAG:
			_demote_money(obj, origin)
		else:
			_fling_money(obj, origin)

## Fling one money object away from the blast to a nearby open tile, and persist
## the new position so every client agrees where it landed.
func _fling_money(obj: WorldObject, origin: Vector2) -> void:
	var away := (Vector2(obj.position.x, obj.position.z) - origin).normalized()
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT.rotated(randf() * TAU)
	var dist := randf_range(1.5, 3.0)
	var cur_tile := Vector2(GameConfig.world_to_tile(obj.position))
	var new_tile := cur_tile + away * dist + Vector2(randf_range(-0.6, 0.6), randf_range(-0.6, 0.6))
	new_tile = GameState.free_drop_tile(new_tile) # never into the river or inside a prop
	var new_pos := GameConfig.tile_to_world(new_tile)
	obj.respawn_at(new_pos)
	obj.spawn_world_pos = new_pos
	obj.spawn_tile = new_tile
	if not obj.object_id.is_empty():
		note_local_authority(obj.object_id)
		NetworkService.drop_money_object(obj.object_id, new_tile.x, new_tile.y, obj.owner_name)

## Split a bag/vault caught in a blast into TWO objects of the tier below, thrown
## to different sides. Bags keep the owner label; stacks are unowned as always.
## Only the client that spawned the explosion runs this (no PATCH race).
func _demote_money(obj: WorldObject, origin: Vector2) -> void:
	var child_tier: int = obj.tier - 1
	var type_key := "money_bag" if child_tier >= FormDefs.TIER_BAG else "money_stack"
	var owner: String = obj.owner_name if child_tier >= FormDefs.TIER_BAG else ""
	var base := Vector2(GameConfig.world_to_tile(obj.position))
	var away := (Vector2(obj.position.x, obj.position.z) - origin).normalized()
	if away.length_squared() < 0.01:
		away = Vector2.RIGHT.rotated(randf() * TAU)
	GameState.show_toast("The blast broke a %s apart!" % FormDefs.tier_display(obj.tier))
	# Remove the source (tombstoned so a stale poll can't resurrect it).
	obj.consume()
	if not obj.object_id.is_empty():
		note_deleted(obj.object_id)
		NetworkService.delete_world_object(obj.object_id)
	obj.queue_free()
	for k in 2:
		var side := away.rotated(deg_to_rad(-45.0 + 90.0 * float(k)) + randf_range(-0.3, 0.3))
		var tile := GameState.free_drop_tile(base + side * randf_range(1.5, 2.8))
		_spawn_demoted_money(type_key, tile, owner)

func _spawn_demoted_money(type_key: String, tile: Vector2, owner: String) -> void:
	var new_id := ""
	if NetworkService.is_online():
		var fields := {"type": type_key, "x": tile.x, "y": tile.y, "state": "idle"}
		if not owner.is_empty():
			fields["owner_name"] = owner
		var created: Dictionary = await NetworkService.create_world_object(fields)
		new_id = str(created.get("id", ""))
	spawn_money_object(type_key, GameConfig.tile_to_world(tile), owner, new_id)

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
	splat.add_child(_flat_blob(puddle, mat, Vector3(0, 0.062, 0)))
	# Scattered droplets around it.
	for i in 5:
		var drop := CylinderMesh.new()
		var r := randf_range(0.05, 0.12)
		drop.top_radius = r
		drop.bottom_radius = r
		drop.height = 0.02
		var ang := randf() * TAU
		var d := randf_range(0.25, 0.55)
		splat.add_child(_flat_blob(drop, mat, Vector3(cos(ang) * d, 0.058, sin(ang) * d)))
	var tween := create_tween()
	tween.tween_interval(4.0)                                # stay vivid for a beat
	tween.tween_property(mat, "albedo_color:a", 0.0, 4.0)   # then fade out
	tween.tween_callback(splat.queue_free)

## A vehicle wreck: body chunks + wheels scatter from the impact and fade away.
func spawn_vehicle_wreck(world_pos: Vector3, form_key: String) -> void:
	var root := Node3D.new()
	root.position = Vector3(world_pos.x, 0.0, world_pos.z)
	add_child(root)
	var is_bus := form_key == FormDefs.MATA_BUS
	var body_col := Color(0.15, 0.28, 0.55) if not is_bus else Color(0.93, 0.94, 0.95)
	var part_mat := StandardMaterial3D.new()
	part_mat.albedo_color = body_col
	part_mat.roughness = 0.55
	var wheel_mat := StandardMaterial3D.new()
	wheel_mat.albedo_color = Color(0.05, 0.05, 0.06)
	wheel_mat.roughness = 0.9
	for i in 4:
		var chunk := BoxMesh.new()
		chunk.size = Vector3(
			randf_range(0.25, 0.55) if not is_bus else randf_range(0.35, 0.75),
			randf_range(0.12, 0.32),
			randf_range(0.25, 0.65) if not is_bus else randf_range(0.4, 0.9),
		)
		var mi := MeshInstance3D.new()
		mi.mesh = chunk
		mi.material_override = part_mat
		root.add_child(mi)
		var ang := randf() * TAU
		var dist := randf_range(0.8, 2.0)
		var end := Vector3(cos(ang) * dist, 0.06, sin(ang) * dist)
		mi.position = Vector3(0, 0.18, 0)
		var tw := root.create_tween()
		tw.set_parallel(true)
		tw.tween_property(mi, "position", end, 0.48).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(mi, "rotation", Vector3(randf(), randf(), randf()) * TAU, 0.48)
	var wheel_count := 4 if not is_bus else 6
	for i in wheel_count:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.14 if not is_bus else 0.17
		wheel.bottom_radius = wheel.top_radius
		wheel.height = 0.1
		var wi := MeshInstance3D.new()
		wi.mesh = wheel
		wi.material_override = wheel_mat
		wi.rotation_degrees = Vector3(0, 0, 90)
		root.add_child(wi)
		var ang := randf() * TAU
		var dist := randf_range(1.0, 2.4)
		var end := Vector3(cos(ang) * dist, 0.08, sin(ang) * dist)
		wi.position = Vector3(0, 0.12, 0)
		var tw := root.create_tween()
		tw.set_parallel(true)
		tw.tween_property(wi, "position", end, 0.52).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		tw.tween_property(wi, "rotation:x", wi.rotation.x + randf_range(5.0, 10.0), 0.52)
	var fade := create_tween()
	fade.tween_interval(1.1)
	fade.tween_method(func(a: float) -> void:
		part_mat.albedo_color.a = a
		wheel_mat.albedo_color.a = a
		var fade_on := a < 0.99
		part_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if fade_on else BaseMaterial3D.TRANSPARENCY_DISABLED
		wheel_mat.transparency = part_mat.transparency,
		1.0, 0.0, 1.3)
	fade.tween_callback(root.queue_free)

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
	click_marker.position = world_pos + Vector3(0, 0.09, 0)
	var tween := create_tween()
	tween.tween_property(click_marker, "scale", Vector3(1.2, 1.2, 1.2), 0.25)
	tween.tween_callback(func(): click_marker.visible = false)
