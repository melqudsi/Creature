class_name GameConfig
extends RefCounted

## Shared constants ported from js/game.js

const MAP_W := 32
const MAP_H := 24
const TILE_SIZE := 1.0

const MOVE_TILES_PER_SEC := 1.0
const POLL_OTHERS_SEC := 1.5

const NAME_MAX_LEN := 10

const DEFAULT_CREATURE_COLOR := Color(0.22, 0.22, 0.26, 1.0)
const DEFAULT_CREATURE_NAME := "Creature"

## Visible build stamp so a loaded build can be identified at a glance.
## Keep this in sync with the build-stamp string in web/custom_shell.html.
const BUILD_ID := "build 2026-07-02e"

## Landfill Dump: the spawn/respawn zone (bottom-left corner). All new players
## and all respawns appear here. LANDFILL_RECT (tile x, y, w, h) is used for the
## ground tint marker.
const LANDFILL_CENTER := Vector2(3, 21)
const LANDFILL_RECT := Rect2i(0, 16, 9, 8)

## Named map regions (Slice 3): BBQ Corner hosts the smoker spawn near the
## houses; Bus Stop is where the MATA Bus parks.
const BBQ_CORNER_RECT := Rect2i(11, 4, 7, 6)
const BUS_STOP_RECT := Rect2i(26, 18, 6, 6)

## BBQ Smoker economy (Slice 3). The smoker only generates money while a player
## is possessing it AND it's parked near a house — an active, defendable choice,
## not a passive faucet. The world stack cap keeps the map from flooding.
const SMOKER_GEN_INTERVAL_SEC := 18.0
const SMOKER_NEAR_HOUSE_TILES := 3.0
const MONEY_STACK_WORLD_CAP := 20

## Smoke cloud special (BBQ Smoker): synced to everyone as a temporary
## world_objects row; hides remote players + loose money inside the radius.
const SMOKE_CLOUD_DURATION_SEC := 10.0
const SMOKE_CLOUD_COOLDOWN_SEC := 20.0
const SMOKE_CLOUD_RADIUS_TILES := 3.0

const TREE_POSITIONS: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(7, 4), Vector2i(12, 2), Vector2i(18, 5),
	Vector2i(25, 3), Vector2i(29, 8), Vector2i(5, 10), Vector2i(10, 13),
	Vector2i(16, 11), Vector2i(22, 14), Vector2i(28, 17), Vector2i(4, 19),
	Vector2i(13, 21), Vector2i(20, 20), Vector2i(27, 22), Vector2i(30, 14),
]

const BUILDING_POSITIONS: Array[Vector2i] = [
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
## Each entry is {"key": <object key>, "tile": Vector2}. See WorldObject configs
## in world_map.gd for what each key does.
static func interactive_objects() -> Array:
	return [
		# --- Landfill Dump starter objects ---
		{"key": "altima", "tile": Vector2(6, 20)},
		{"key": "magnolia", "tile": Vector2(2, 18)},
		{"key": "propane", "tile": Vector2(6, 22)},
		{"key": "pothole", "tile": Vector2(7, 19)},
		{"key": "cart", "tile": Vector2(2, 22)},
		{"key": "cone", "tile": Vector2(4, 23)},
		{"key": "bus", "tile": Vector2(29, 21)},
		{"key": "smoker", "tile": Vector2(12, 6)},
		# --- Road / open-world traps (solo-testable) ---
		{"key": "pothole", "tile": Vector2(16, 12)},
		{"key": "propane", "tile": Vector2(21, 11)},
		{"key": "magnolia", "tile": Vector2(12, 9)},
		{"key": "altima", "tile": Vector2(24, 13)},
	]

## Starter money piles (Slice 2) — merged into shared seed on first poll / upgrade.
static func money_seed_objects() -> Array:
	return [
		{"key": "money_stack", "tile": Vector2(3, 20)},
		{"key": "money_stack", "tile": Vector2(5, 19)},
		{"key": "money_stack", "tile": Vector2(14, 8)},
		{"key": "money_stack", "tile": Vector2(18, 15)},
		{"key": "money_stack", "tile": Vector2(22, 12)},
	]

## A random walkable tile away from trees/buildings (used by admin money spawns).
static func random_open_tile() -> Vector2:
	for _attempt in 24:
		var t := Vector2(float(randi_range(2, MAP_W - 3)), float(randi_range(2, MAP_H - 3)))
		var ti := Vector2i(int(t.x), int(t.y))
		if TREE_POSITIONS.has(ti) or BUILDING_POSITIONS.has(ti):
			continue
		return t
	return LANDFILL_CENTER + Vector2(2, 0)

## Purely decorative trash piles that dress up the landfill.
static func trash_pile_tiles() -> Array:
	return [Vector2(1, 19), Vector2(2, 20), Vector2(5, 23), Vector2(1, 22), Vector2(0, 18)]

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

## Map a world/tile position to a human-readable region name for the HUD.
static func region_for_tile(tile: Vector2) -> String:
	var ti := Vector2i(int(floor(tile.x)), int(floor(tile.y)))
	if is_in_landfill(tile):
		return "The Dump"
	if BBQ_CORNER_RECT.has_point(ti):
		return "BBQ Corner"
	if BUS_STOP_RECT.has_point(ti):
		return "Bus Stop"
	return "Memphis"

## True when a tile is within `max_tiles` of any house (smoker money generation).
static func is_near_building(tile: Vector2, max_tiles: float) -> bool:
	for b in BUILDING_POSITIONS:
		if tile.distance_to(Vector2(b)) <= max_tiles:
			return true
	return false
