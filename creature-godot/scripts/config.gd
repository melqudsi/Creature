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
const BUILD_ID := "build 2026-07-01c"

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
		"x": MAP_W / 2,
		"y": MAP_H / 2,
		"size_level": 1,
		"is_player": true,
	}

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
