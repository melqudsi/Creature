class_name MemphisLayout
extends RefCounted

## Memphis-inspired world layout (map buildout pass 1).
##
## The map is a simplified, not-to-scale Memphis: the Mississippi River runs
## down the west edge (sunken ~0.45 units below the land — Memphis sits on a
## bluff), Mud Island pokes out of it near Downtown, and the Hernando de Soto
## "M" Bridge crosses the river before dead-ending at the west map edge.
## I-40 dead-ends at the east map edge. Major real roads divide the regions.
##
## The pre-Memphis 32x24 world (Dump / BBQ Corner / Bus Stop and all seeded
## objects) is embedded intact inside South Memphis at GameConfig.OLD_WORLD_OFFSET.
##
## IMPORTANT: scattered trees/houses are generated from a FIXED seed so every
## client builds the identical world (blocked tiles must match for pathfinding
## and the smoker's near-house check to agree across players).

const RIVER_W := 15 # river covers tiles x 0..14, full map height
const MUD_ISLAND_RECT := Rect2i(6, 22, 8, 23)
const BRIDGE_RECT := Rect2i(0, 24, 16, 3)
## Where the legacy 32x24 world lives now (see GameConfig.OLD_WORLD_OFFSET).
const OLD_WORLD_RECT := Rect2i(20, 80, 32, 24)
## The Memphis Pyramid — hand-placed landmark at the north end of Downtown.
const PYRAMID_TILE := Vector2i(19, 20)

## Ordered: first matching rect wins (sub-zones like The Dump are checked by
## GameConfig.region_for_tile before this list). "tint" quads are layered in
## list order (earlier = drawn on top where rects overlap).
const REGIONS: Array = [
	{"name": "Hernando de Soto Bridge", "rect": Rect2i(0, 24, 16, 3)},
	{"name": "Mud Island", "rect": Rect2i(6, 22, 8, 23)},
	{"name": "Mississippi River", "rect": Rect2i(0, 0, 15, 112)},
	{"name": "Downtown", "rect": Rect2i(15, 18, 19, 30), "tint": Color(0.45, 0.46, 0.42)},
	{"name": "North Memphis", "rect": Rect2i(15, 0, 55, 18), "tint": Color(0.40, 0.52, 0.30)},
	{"name": "Bartlett", "rect": Rect2i(70, 0, 90, 18), "tint": Color(0.37, 0.53, 0.34)},
	{"name": "Midtown", "rect": Rect2i(34, 18, 36, 40), "tint": Color(0.38, 0.55, 0.33)},
	{"name": "East Memphis", "rect": Rect2i(70, 18, 30, 40), "tint": Color(0.42, 0.56, 0.31)},
	{"name": "Cordova", "rect": Rect2i(100, 18, 60, 18), "tint": Color(0.41, 0.54, 0.29)},
	{"name": "Germantown", "rect": Rect2i(100, 36, 60, 34), "tint": Color(0.36, 0.57, 0.33)},
	{"name": "Collierville", "rect": Rect2i(100, 70, 60, 42), "tint": Color(0.39, 0.56, 0.35)},
	{"name": "South Memphis", "rect": Rect2i(15, 48, 85, 64), "tint": Color(0.42, 0.50, 0.30)},
]

## Roads are purely visual (walkable) — they divide regions and aid navigation.
## Every road is 2 tiles wide = two lanes (NPC traffic drives one lane each
## direction, split by the painted divider).
## kind: "interstate" (darker) vs "street"; "bridge" is built as a real 3D deck
## over the water instead of a ground quad.
const ROADS: Array = [
	{"name": "Hernando de Soto Bridge", "rect": Rect2i(0, 24, 16, 3), "kind": "bridge"},
	{"name": "I-40", "rect": Rect2i(15, 18, 145, 2), "kind": "interstate"},
	{"name": "I-240", "rect": Rect2i(16, 56, 54, 2), "kind": "interstate"},
	{"name": "I-240", "rect": Rect2i(68, 18, 2, 40), "kind": "interstate"},
	{"name": "385", "rect": Rect2i(54, 92, 106, 2), "kind": "interstate"},
	{"name": "Poplar Ave", "rect": Rect2i(16, 34, 140, 2), "kind": "street"},
	{"name": "Union Ave", "rect": Rect2i(16, 28, 46, 2), "kind": "street"},
	# Walnut Grove reaches back to E Parkway, which ties it into Union (they
	# connect in the real world; previously disconnected in-game).
	{"name": "Walnut Grove Rd", "rect": Rect2i(60, 24, 70, 2), "kind": "street"},
	{"name": "E Parkway", "rect": Rect2i(60, 24, 2, 6), "kind": "street"},
	{"name": "Summer Ave", "rect": Rect2i(16, 8, 95, 2), "kind": "street"},
	{"name": "Stage Rd", "rect": Rect2i(72, 4, 76, 2), "kind": "street"},
	# Front St sits 4 tiles east of Riverside so sidewalks + a row of Downtown
	# buildings fit between the two (they used to touch).
	{"name": "Front St", "rect": Rect2i(21, 20, 2, 28), "kind": "street"},
	{"name": "Riverside Dr", "rect": Rect2i(15, 20, 2, 32), "kind": "street"},
	{"name": "Elvis Presley Blvd", "rect": Rect2i(54, 58, 2, 54), "kind": "street"},
	{"name": "Winchester Rd", "rect": Rect2i(24, 76, 136, 2), "kind": "street"},
	{"name": "Germantown Rd", "rect": Rect2i(118, 18, 2, 72), "kind": "street"},
	{"name": "Houston Levee Rd", "rect": Rect2i(144, 18, 2, 94), "kind": "street"},
	# Lamar Ave is diagonal in the real world — approximated as a 3-segment
	# staircase from Union down to Winchester. Pothole country.
	{"name": "Lamar Ave", "rect": Rect2i(38, 30, 2, 14), "kind": "street"},
	{"name": "Lamar Ave", "rect": Rect2i(38, 44, 26, 2), "kind": "street"},
	{"name": "Lamar Ave", "rect": Rect2i(62, 46, 2, 30), "kind": "street"},
]

## Per-region procedural scatter (houses/trees/towers). Rects stay inside the
## region and away from region-edge roads; water/roads/old-world/crowding are
## rejected at generation time.
const SCATTER_SPECS: Array = [
	{"rect": Rect2i(16, 2, 53, 15), "houses": 8, "trees": 10},    # North Memphis
	{"rect": Rect2i(19, 21, 15, 26), "towers": 9},                # Downtown core
	{"rect": Rect2i(35, 19, 33, 36), "houses": 10, "trees": 8},   # Midtown
	{"rect": Rect2i(71, 19, 28, 37), "houses": 10, "trees": 8},   # East Memphis
	{"rect": Rect2i(72, 2, 85, 14), "houses": 7, "trees": 7},     # Bartlett
	{"rect": Rect2i(101, 20, 57, 13), "houses": 7, "trees": 6},   # Cordova
	{"rect": Rect2i(101, 37, 57, 31), "houses": 9, "trees": 9},   # Germantown
	{"rect": Rect2i(101, 72, 57, 38), "houses": 7, "trees": 9},   # Collierville
	{"rect": Rect2i(16, 59, 82, 50), "houses": 7, "trees": 8},    # South Memphis
	{"rect": Rect2i(7, 27, 6, 16), "trees": 6},                   # Mud Island park
]

## Overton Park: a hand-placed tree cluster in north Midtown.
const OVERTON_PARK_TREES: Array[Vector2i] = [
	Vector2i(52, 21), Vector2i(54, 22), Vector2i(56, 21),
	Vector2i(52, 23), Vector2i(55, 23), Vector2i(57, 22),
]

# ---------------------------------------------------------------------------
# Landmarks (Slice 6): U of M, Shelby Farms, the Zoo, the Airport + FedEx hub,
# Krogers, Tom Lee Park. Positions approximate the real layout.
# ---------------------------------------------------------------------------

const UOFM_RECT := Rect2i(56, 37, 7, 5)          # south of Poplar, east Midtown
const UOFM_BUILDINGS: Array[Vector2i] = [
	Vector2i(58, 38), Vector2i(61, 38), Vector2i(59, 40),
]
const ZOO_RECT := Rect2i(47, 19, 5, 4)           # Overton Park, north Midtown
const SHELBY_RECT := Rect2i(96, 26, 13, 9)       # off Walnut Grove
const SHELBY_LAKE_CENTER := Vector2(102.5, 30.5)
const SHELBY_LAKE_RADIUS := 2.6
const AIRPORT_RECT := Rect2i(58, 82, 15, 10)     # east of EP Blvd, South Memphis
const AIRPORT_TERMINAL := Vector2i(61, 84)
const FEDEX_HUB := Vector2i(68, 84)
const AIRPORT_RUNWAY := Rect2i(59, 90, 13, 1)
const TOM_LEE_RECT := Rect2i(17, 42, 3, 9)       # riverfront below Downtown
const TOM_LEE_TREES: Array[Vector2i] = [
	Vector2i(17, 44), Vector2i(18, 47), Vector2i(17, 50),
]
## Kroger sites: Midtown, East Memphis, Germantown. Store box + parking lot
## east of it (parked Altimas + carts are seeded there — see slice6 seeds).
const KROGER_SITES: Array[Vector2i] = [
	Vector2i(44, 50), Vector2i(85, 42), Vector2i(122, 58),
]

## Landmark footprints: pre-seeded scatter (houses/trees/towers) inside these
## rects is dropped post-generation. Filtering AFTER generation (instead of
## rejecting during sampling) keeps the RNG draw sequence — and therefore every
## OTHER scatter position — identical to pre-landmark builds.
static func landmark_clear_rects() -> Array:
	var rects: Array = [UOFM_RECT, ZOO_RECT, SHELBY_RECT, AIRPORT_RECT, TOM_LEE_RECT]
	for site in KROGER_SITES:
		rects.append(Rect2i(site - Vector2i(1, 1), Vector2i(6, 4)))
	return rects

## Solid (blocked) landmark structures: campus halls, terminal, FedEx, Krogers.
static func landmark_solid_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	out.append_array(UOFM_BUILDINGS)
	for d in [Vector2i(0, 0), Vector2i(1, 0)]:
		out.append(AIRPORT_TERMINAL + d)
		out.append(FEDEX_HUB + d)
		for site in KROGER_SITES:
			out.append(site + d)
	return out

static func lake_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := int(ceil(SHELBY_LAKE_RADIUS))
	var c := Vector2i(int(SHELBY_LAKE_CENTER.x), int(SHELBY_LAKE_CENTER.y))
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var t := c + Vector2i(dx, dy)
			if Vector2(t) .distance_to(SHELBY_LAKE_CENTER - Vector2(0.5, 0.5)) <= SHELBY_LAKE_RADIUS:
				out.append(t)
	return out

const SCATTER_SEED := 19010 # fixed on purpose — see class docstring

static var _scatter_cache: Dictionary = {}
static var _blocked_cache: Dictionary = {}
static var _tree_cache: Array[Vector2i] = []
static var _house_cache: Array[Vector2i] = []

static func region_name(tile: Vector2) -> String:
	var ti := Vector2i(int(floor(tile.x)), int(floor(tile.y)))
	for r in REGIONS:
		if (r["rect"] as Rect2i).has_point(ti):
			return str(r["name"])
	return "Memphis"

static func is_water(tile: Vector2i) -> bool:
	if tile.x >= RIVER_W:
		return false
	if BRIDGE_RECT.has_point(tile):
		return false
	if MUD_ISLAND_RECT.has_point(tile):
		return false
	return true

static func is_road(tile: Vector2i) -> bool:
	for r in ROADS:
		if (r["rect"] as Rect2i).has_point(tile):
			return true
	return false

static func tree_tiles() -> Array[Vector2i]:
	if _tree_cache.is_empty():
		for p in GameConfig.OLD_WORLD_TREES:
			_tree_cache.append(p + GameConfig.OLD_WORLD_OFFSET)
		_tree_cache.append_array(_scatter()["trees"] as Array[Vector2i])
		_tree_cache.append_array(TOM_LEE_TREES)
	return _tree_cache

## Cached: is_near_building() walks this list every frame (smoker economy).
static func house_tiles() -> Array[Vector2i]:
	if _house_cache.is_empty():
		for p in GameConfig.OLD_WORLD_BUILDINGS:
			_house_cache.append(p + GameConfig.OLD_WORLD_OFFSET)
		_house_cache.append_array(_scatter()["houses"] as Array[Vector2i])
	return _house_cache

static func tower_tiles() -> Array[Vector2i]:
	return _scatter()["towers"] as Array[Vector2i]

## Water + all solid props, as a Dictionary for O(1) pathfinding lookups.
## (The old Array-based blocked list would make A* crawl at this tile count.)
static func blocked_tiles() -> Dictionary:
	if not _blocked_cache.is_empty():
		return _blocked_cache
	var blocked: Dictionary = {}
	for y in GameConfig.MAP_H:
		for x in RIVER_W:
			var t := Vector2i(x, y)
			if is_water(t):
				blocked[t] = true
	for t in tree_tiles():
		blocked[t] = true
	for t in house_tiles():
		blocked[t] = true
	for t in tower_tiles():
		blocked[t] = true
	for t in landmark_solid_tiles():
		blocked[t] = true
	for t in lake_tiles():
		blocked[t] = true
	blocked[PYRAMID_TILE] = true
	_blocked_cache = blocked
	return blocked

static func _scatter() -> Dictionary:
	if not _scatter_cache.is_empty():
		return _scatter_cache
	var rng := RandomNumberGenerator.new()
	rng.seed = SCATTER_SEED
	var used: Dictionary = {}
	var trees: Array[Vector2i] = []
	var houses: Array[Vector2i] = []
	var towers: Array[Vector2i] = []
	used[PYRAMID_TILE] = true
	for t in OVERTON_PARK_TREES:
		trees.append(t)
		used[t] = true
	# Fixed iteration order keeps generation deterministic across clients.
	for spec in SCATTER_SPECS:
		var rect: Rect2i = spec["rect"]
		_fill(rng, rect, int(spec.get("houses", 0)), houses, used)
		_fill(rng, rect, int(spec.get("trees", 0)), trees, used)
		_fill(rng, rect, int(spec.get("towers", 0)), towers, used)
	# Landmarks claim their footprints AFTER generation (see landmark_clear_rects).
	var clear := landmark_clear_rects()
	_scatter_cache = {
		"trees": _outside_rects(trees, clear),
		"houses": _outside_rects(houses, clear),
		"towers": _outside_rects(towers, clear),
	}
	return _scatter_cache

static func _outside_rects(tiles: Array[Vector2i], rects: Array) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for t in tiles:
		var inside := false
		for r in rects:
			if (r as Rect2i).has_point(t):
				inside = true
				break
		if not inside:
			out.append(t)
	return out

static func _fill(rng: RandomNumberGenerator, rect: Rect2i, count: int, out: Array[Vector2i], used: Dictionary) -> void:
	var placed := 0
	var attempts := 0
	while placed < count and attempts < count * 60:
		attempts += 1
		var t := Vector2i(
			rng.randi_range(rect.position.x, rect.end.x - 1),
			rng.randi_range(rect.position.y, rect.end.y - 1)
		)
		if used.has(t) or is_water(t) or is_road(t) or OLD_WORLD_RECT.has_point(t):
			continue
		# Keep a 1-tile orthogonal gap so scatter never walls off a path.
		var crowded := false
		for n in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if used.has(t + n):
				crowded = true
				break
		if crowded:
			continue
		used[t] = true
		out.append(t)
		placed += 1
