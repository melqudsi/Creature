class_name GameConfig
extends RefCounted

## Shared constants ported from js/game.js

## Memphis map (see scripts/world/memphis_layout.gd for the region/road layout).
## At 1 tile/sec an alien crosses east-west in ~2:40 — the target scale.
const MAP_W := 160
const MAP_H := 112
const TILE_SIZE := 1.0

## The original 32x24 world (Dump, BBQ Corner, Bus Stop + seeded objects) is
## embedded intact inside South Memphis at this tile offset. Legacy creature
## positions saved on the old map are remapped by this on session restore.
const OLD_WORLD_OFFSET := Vector2i(20, 80)

const MOVE_TILES_PER_SEC := 1.0
const POLL_OTHERS_SEC := 1.5

const NAME_MAX_LEN := 10

const DEFAULT_CREATURE_COLOR := Color(0.22, 0.22, 0.26, 1.0)
const DEFAULT_CREATURE_NAME := "Creature"

## Visible build stamp so a loaded build can be identified at a glance.
## Keep this in sync with the build-stamp string in web/custom_shell.html.
const BUILD_ID := "build 2026-07-11a"

## Landfill Dump: the spawn/respawn zone (now inside South Memphis — old-world
## coords + OLD_WORLD_OFFSET). All new players and respawns appear here.
const LANDFILL_CENTER := Vector2(23, 101)
const LANDFILL_RECT := Rect2i(20, 96, 9, 8)

## Named sub-zones (Slice 3), offset into South Memphis with the old world.
const BBQ_CORNER_RECT := Rect2i(31, 84, 7, 6)
const BUS_STOP_RECT := Rect2i(46, 98, 6, 6)

## BBQ Smoker economy (Slice 3). The smoker only generates money while a player
## is possessing it AND it's parked near a house — an active, defendable choice,
## not a passive faucet.
const SMOKER_GEN_INTERVAL_SEC := 18.0
const SMOKER_NEAR_HOUSE_TILES := 3.0

## Smoke cloud special (BBQ Smoker): synced to everyone as a temporary
## world_objects row; hides remote players + loose money inside the radius.
const SMOKE_CLOUD_DURATION_SEC := 10.0
const SMOKE_CLOUD_COOLDOWN_SEC := 20.0
const SMOKE_CLOUD_RADIUS_TILES := 3.0

## Legacy hand-placed props in OLD-WORLD coordinates (offset into South Memphis
## via OLD_WORLD_OFFSET by MemphisLayout.tree_tiles()/house_tiles()).
const OLD_WORLD_TREES: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(7, 4), Vector2i(12, 2), Vector2i(18, 5),
	Vector2i(25, 3), Vector2i(29, 8), Vector2i(5, 10), Vector2i(10, 13),
	Vector2i(16, 11), Vector2i(22, 14), Vector2i(28, 17),
	Vector2i(13, 21), Vector2i(20, 20), Vector2i(27, 22), Vector2i(30, 14),
]

const OLD_WORLD_BUILDINGS: Array[Vector2i] = [
	Vector2i(6, 6), Vector2i(14, 7), Vector2i(23, 9),
	Vector2i(8, 17), Vector2i(18, 16), Vector2i(26, 19),
]

## Dark gray is intentionally first (and the default swatch on the spawn screen).
const CREATURE_COLORS: Array[Color] = [
	DEFAULT_CREATURE_COLOR,
	Color("#ef5350"), Color("#ff7043"), Color("#ffca28"),
	Color("#66bb6a"), Color("#26a69a"), Color("#29b6f6"),
	Color("#5c6bc0"), Color("#ab47bc"), Color("#ec407a"),
	Color("#8d6e63"), Color("#eceff1"),
]

static func default_player_data() -> Dictionary:
	return {
		"id": "",
		"name": DEFAULT_CREATURE_NAME,
		"color": DEFAULT_CREATURE_COLOR,
		"appearance": "worm",
		"form": "alien",
		"x": LANDFILL_CENTER.x,
		"y": LANDFILL_CENTER.y,
		"size_level": 1,
		"is_player": true,
	}

## A slightly scattered open tile near the landfill center so multiple spawns /
## respawns don't stack on the exact same spot.
static func landfill_spawn_tile() -> Vector2:
	var ox := randi_range(-1, 1)
	var oy := randi_range(-1, 1)
	var t := LANDFILL_CENTER + Vector2(ox, oy)
	t.x = clampf(t.x, 1.0, MAP_W - 2.0)
	t.y = clampf(t.y, 1.0, MAP_H - 2.0)
	return t

## Interactive/shapeshiftable world objects: starter junk at the landfill plus a
## few road traps out in the open so the kill matrix is testable solo.
## Tiles are OLD-WORLD coordinates, offset into South Memphis here.
## Each entry is {"key": <object key>, "tile": Vector2}. See WorldObject configs
## in world_map.gd for what each key does.
static func interactive_objects() -> Array:
	return [
		# --- Landfill Dump starter objects (spawn zone stays clear of hazards) ---
		{"key": "altima", "tile": _old(Vector2(6, 20))},
		{"key": "cart", "tile": _old(Vector2(2, 22))},
		{"key": "cone", "tile": _old(Vector2(4, 23))},
		{"key": "bus", "tile": _old(Vector2(29, 21))},
		{"key": "smoker", "tile": _old(Vector2(12, 6))},
		# --- Road / open-world traps (solo-testable) ---
		{"key": "pothole", "tile": _old(Vector2(16, 12))},
		{"key": "magnolia", "tile": _old(Vector2(12, 9))},
		{"key": "altima", "tile": _old(Vector2(24, 13))},
	]

## Slice 5 road hazards + street food: potholes seeded on roads (Lamar Ave gets
## a beating — it's Lamar), BBQ trailers in Midtown and Downtown. Tiles are
## world coordinates (NOT old-world offsets). Pothole tiles sit in a lane of
## the road they belong to; trailer tiles are nudged to a free tile at seed time.
static func slice5_seed_objects() -> Array:
	return [
		# --- Lamar Ave: pothole country ---
		{"key": "pothole", "tile": Vector2(38, 33)},
		{"key": "pothole", "tile": Vector2(39, 37)},
		{"key": "pothole", "tile": Vector2(38, 41)},
		{"key": "pothole", "tile": Vector2(45, 44)},
		{"key": "pothole", "tile": Vector2(51, 45)},
		{"key": "pothole", "tile": Vector2(57, 44)},
		{"key": "pothole", "tile": Vector2(62, 50)},
		{"key": "pothole", "tile": Vector2(63, 58)},
		{"key": "pothole", "tile": Vector2(62, 66)},
		{"key": "pothole", "tile": Vector2(63, 72)},
		# --- A scattering on other roads ---
		{"key": "pothole", "tile": Vector2(30, 34)},   # Poplar
		{"key": "pothole", "tile": Vector2(74, 35)},   # Poplar
		{"key": "pothole", "tile": Vector2(112, 34)},  # Poplar
		{"key": "pothole", "tile": Vector2(26, 29)},   # Union
		{"key": "pothole", "tile": Vector2(42, 8)},    # Summer
		{"key": "pothole", "tile": Vector2(88, 9)},    # Summer
		{"key": "pothole", "tile": Vector2(64, 77)},   # Winchester
		{"key": "pothole", "tile": Vector2(118, 76)},  # Winchester
		{"key": "pothole", "tile": Vector2(55, 70)},   # Elvis Presley
		# --- BBQ trailers (smokers): Midtown x2, Downtown x2 ---
		{"key": "smoker", "tile": Vector2(47, 31), "free": true},
		{"key": "smoker", "tile": Vector2(58, 40), "free": true},
		{"key": "smoker", "tile": Vector2(24, 31), "free": true},
		{"key": "smoker", "tile": Vector2(28, 42), "free": true},
	]

## Slice 6: every Kroger gets a lived-in parking lot — two parked Altimas and
## two stray shopping carts. World coordinates (lot sits just south of the box).
## Altimas never spawn in Germantown / Collierville (suburbs rule), so those
## Kroger lots only get carts.
static func slice6_seed_objects() -> Array:
	var out: Array = []
	for site in MemphisLayout.KROGER_SITES:
		var s := Vector2(site)
		if not is_in_burbs(s):
			out.append({"key": "altima", "tile": s + Vector2(-1, 1)})
			out.append({"key": "altima", "tile": s + Vector2(2, 1)})
		out.append({"key": "cart", "tile": s + Vector2(0, 2)})
		out.append({"key": "cart", "tile": s + Vector2(3, 1)})
	return out

## Slice 8: explosives/cars/trees distribution pass.
## - Propane lives only in North Memphis and Midtown.
## - BBQ grills are near a sparse subset of houses (not every house).
## - Chargers are South Memphis-only.
## - Magnolias are spread across the board as shapeshift targets.
static func slice8_seed_objects() -> Array:
	var out: Array = [
		# Propane: North Memphis + Midtown only.
		{"key": "propane", "tile": Vector2(23, 6), "free": true},
		{"key": "propane", "tile": Vector2(45, 12), "free": true},
		{"key": "propane", "tile": Vector2(42, 31), "free": true},
		{"key": "propane", "tile": Vector2(63, 49), "free": true},
		# Dodge Chargers: South Memphis only.
		{"key": "charger", "tile": Vector2(34, 86), "free": true},
		{"key": "charger", "tile": Vector2(57, 80), "free": true},
		{"key": "charger", "tile": Vector2(84, 70), "free": true},
		# Magnolia shapeshift targets across the larger map.
		{"key": "magnolia", "tile": Vector2(22, 14), "free": true},
		{"key": "magnolia", "tile": Vector2(52, 14), "free": true},
		{"key": "magnolia", "tile": Vector2(83, 13), "free": true},
		{"key": "magnolia", "tile": Vector2(123, 12), "free": true},
		{"key": "magnolia", "tile": Vector2(27, 39), "free": true},
		{"key": "magnolia", "tile": Vector2(55, 52), "free": true},
		{"key": "magnolia", "tile": Vector2(88, 54), "free": true},
		{"key": "magnolia", "tile": Vector2(128, 45), "free": true},
		{"key": "magnolia", "tile": Vector2(31, 72), "free": true},
		{"key": "magnolia", "tile": Vector2(76, 88), "free": true},
		{"key": "magnolia", "tile": Vector2(120, 84), "free": true},
		{"key": "magnolia", "tile": Vector2(148, 103), "free": true},
	]
	var houses := MemphisLayout.house_tiles()
	var grill_count := 0
	for i in houses.size():
		if i % 5 != 1:
			continue
		var h := Vector2(houses[i])
		out.append({"key": "bbq_grill", "tile": h + Vector2(1, 0), "free": true})
		grill_count += 1
		if grill_count >= 10:
			break
	return out

## Slice 9: ATMs (one per playable region) and parked Trucks (Bartlett /
## East Memphis only). ATMs burst into 3 money bags when a vehicle rams them,
## then reseed in the same region the next day.
static func slice9_seed_objects() -> Array:
	var out: Array = []
	for entry in money_spawn_regions():
		out.append({"key": "atm", "tile": random_open_tile_in_rect(entry["rect"] as Rect2i, true)})
	for region in ["Bartlett", "East Memphis"]:
		var rect := region_rect(str(region))
		for _i in 3:
			out.append({"key": "truck", "tile": random_open_tile_in_rect(rect, true)})
	return out

static func region_rect(region: String) -> Rect2i:
	for r in MemphisLayout.REGIONS:
		if str(r.get("name", "")) == region:
			return r["rect"] as Rect2i
	# Fallback: the central playable area.
	return Rect2i(15, 18, 130, 90)

## Germantown + Collierville: no Altima / Charger spawns out in the suburbs.
static func is_in_burbs(tile: Vector2) -> bool:
	var reg := MemphisLayout.region_name(tile)
	return reg == "Germantown" or reg == "Collierville"

# ---------------------------------------------------------------------------
# Destroyed-prop reseeding (July 6 balance pass): a destroyed prop (exploded
# propane/grill, busted ATM) comes back at a RANDOM open tile inside its home
# region(s) after a delay — never instantly on the same spot. Shared rows carry
# a "reseed:<due-unix>" owner_name marker so the delay survives disconnects.
# ---------------------------------------------------------------------------

const PROP_RESEED_DELAY_SEC := 30.0
## ATMs only spawn once per day.
const ATM_RESEED_DELAY_SEC := 86400.0

static func reseed_delay_for_type(type_key: String) -> float:
	return ATM_RESEED_DELAY_SEC if type_key == "atm" else PROP_RESEED_DELAY_SEC

## Where a destroyed prop of this type reseeds. Home regions mirror the seed
## rules: propane in North Memphis/Midtown, grills near houses, Chargers in
## South Memphis, Trucks in Bartlett/East Memphis, Altimas anywhere but the
## suburbs, everything else (incl. ATMs) in the region it was destroyed in.
static func reseed_tile_for_type(type_key: String, current_tile: Vector2) -> Vector2:
	match type_key:
		"propane":
			var reg: Variant = ["North Memphis", "Midtown"].pick_random()
			return random_open_tile_in_rect(region_rect(str(reg)))
		"bbq_grill":
			var houses := MemphisLayout.house_tiles()
			if not houses.is_empty():
				var h: Vector2i = houses.pick_random()
				return safe_drop_tile(Vector2(h) + Vector2(1, 0))
			return random_open_tile()
		"charger":
			return random_open_tile_in_rect(region_rect("South Memphis"))
		"truck":
			var treg: Variant = ["Bartlett", "East Memphis"].pick_random()
			return random_open_tile_in_rect(region_rect(str(treg)), true)
		"altima":
			return random_open_tile_no_burbs()
		"atm":
			return random_open_tile_in_rect(
				region_rect(MemphisLayout.region_name(current_tile)), true)
		_:
			return random_open_tile_in_rect(region_rect(MemphisLayout.region_name(current_tile)))

static func random_open_tile_no_burbs() -> Vector2:
	for _i in 12:
		var t := random_open_tile()
		if not is_in_burbs(t):
			return t
	return LANDFILL_CENTER + Vector2(2, 0)

## Starter money piles (Slice 2) — a few stacks in every playable region.
static func money_seed_objects() -> Array:
	var out: Array = []
	for entry in money_spawn_regions():
		var rect: Rect2i = entry["rect"]
		for _i in 2:
			out.append({"key": "money_stack", "tile": random_open_tile_in_rect(rect)})
	return out

## Playable Memphis regions where money should appear (river + bridge excluded).
static func money_spawn_regions() -> Array:
	var out: Array = []
	for r in MemphisLayout.REGIONS:
		var name := str(r.get("name", ""))
		if name == "Mississippi River" or name == "Hernando de Soto Bridge":
			continue
		out.append({"name": name, "rect": r["rect"] as Rect2i})
	return out

## Pick a walkable tile inside one region rect. `avoid_roads` keeps parked
## vehicles / ATMs off the asphalt (NPC traffic would plow into them).
static func random_open_tile_in_rect(rect: Rect2i, avoid_roads := false) -> Vector2:
	var blocked := MemphisLayout.blocked_tiles()
	for _attempt in 48:
		var ti := Vector2i(
			randi_range(rect.position.x, rect.end.x - 1),
			randi_range(rect.position.y, rect.end.y - 1)
		)
		if blocked.has(ti) or MemphisLayout.is_water(ti):
			continue
		if avoid_roads and MemphisLayout.is_road(ti):
			continue
		return Vector2(ti)
	var center := rect.get_center()
	return Vector2(center)

## A random walkable tile anywhere on the map (used for admin spawns / top-up).
static func random_open_tile() -> Vector2:
	var regions := money_spawn_regions()
	if regions.is_empty():
		return LANDFILL_CENTER + Vector2(2, 0)
	var entry: Dictionary = regions.pick_random()
	return random_open_tile_in_rect(entry["rect"] as Rect2i)

static func _old(tile: Vector2) -> Vector2:
	return tile + Vector2(OLD_WORLD_OFFSET)

## Clamp a drop/scatter position to the map AND keep it out of the river —
## money flung into the water would be unreachable forever.
static func safe_drop_tile(tile: Vector2) -> Vector2:
	var t := Vector2(
		clampf(tile.x, 1.0, MAP_W - 2.0),
		clampf(tile.y, 1.0, MAP_H - 2.0)
	)
	var ti := Vector2i(int(floor(t.x)), int(floor(t.y)))
	if not MemphisLayout.is_water(ti):
		return t
	var safe := GridNav.nearest_walkable(ti, ti, MemphisLayout.blocked_tiles(), {})
	if safe.x >= 0:
		return Vector2(safe)
	return LANDFILL_CENTER

## Purely decorative trash piles that dress up the landfill.
static func trash_pile_tiles() -> Array:
	return [_old(Vector2(1, 19)), _old(Vector2(2, 20)), _old(Vector2(5, 23)), _old(Vector2(1, 22)), _old(Vector2(0, 18))]

static func color_to_hex(color: Color) -> String:
	return "#%02x%02x%02x" % [int(color.r * 255), int(color.g * 255), int(color.b * 255)]

static func color_from_hex(hex: String) -> Color:
	var s := hex.strip_edges()
	if s.is_empty():
		return DEFAULT_CREATURE_COLOR
	if not s.begins_with("#"):
		s = "#" + s
	if not Color.html_is_valid(s):
		return DEFAULT_CREATURE_COLOR
	return Color.from_string(s, DEFAULT_CREATURE_COLOR)

## Future Supabase (Phase 5)
const SUPABASE_URL := "https://gimlaqcnfdbzwdaitfec.supabase.co"
const SUPABASE_ANON_KEY := "sb_publishable_k7dql39Flel10idLrETV_g_u-JMYczq"

static func tile_to_world(tile: Vector2) -> Vector3:
	return Vector3(tile.x * TILE_SIZE + TILE_SIZE * 0.5, 0.0, tile.y * TILE_SIZE + TILE_SIZE * 0.5)

static func world_to_tile(world: Vector3) -> Vector2i:
	return Vector2i(int(floor(world.x / TILE_SIZE)), int(floor(world.z / TILE_SIZE)))

## True while a tile is inside the Landfill Dump spawn zone.
static func is_in_landfill(tile: Vector2) -> bool:
	return LANDFILL_RECT.has_point(Vector2i(int(floor(tile.x)), int(floor(tile.y))))

## Shared-world rows that should not live in the spawn zone (legacy seeds).
static func is_landfill_junk_row(row: Dictionary) -> bool:
	var t := str(row.get("type", ""))
	if t != "pothole" and t != "magnolia" and t != "propane" and t != "tree":
		return false
	var x := float(row.get("x", -999.0))
	var y := float(row.get("y", -999.0))
	return is_in_landfill(Vector2(x, y))

## Map a world/tile position to a human-readable region name for the HUD.
## Sub-zones (The Dump / BBQ Corner / Bus Stop) win over the big Memphis regions.
static func region_for_tile(tile: Vector2) -> String:
	var ti := Vector2i(int(floor(tile.x)), int(floor(tile.y)))
	if is_in_landfill(tile):
		return "The Dump"
	if BBQ_CORNER_RECT.has_point(ti):
		return "BBQ Corner"
	if BUS_STOP_RECT.has_point(ti):
		return "Bus Stop"
	return MemphisLayout.region_name(tile)

## True when a tile is within `max_tiles` of any house or downtown tower
## (smoker money generation).
static func is_near_building(tile: Vector2, max_tiles: float) -> bool:
	for b in MemphisLayout.house_tiles():
		if tile.distance_to(Vector2(b)) <= max_tiles:
			return true
	for b in MemphisLayout.tower_tiles():
		if tile.distance_to(Vector2(b)) <= max_tiles:
			return true
	return false
