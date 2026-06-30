class_name GameConfig
extends RefCounted

## Shared constants ported from js/game.js

const MAP_W := 20
const MAP_H := 15
const TILE_SIZE := 1.0

const MOVE_TILES_PER_SEC := 1.0

const NAME_MAX_LEN := 10

const DEFAULT_CREATURE_COLOR := Color(0.22, 0.22, 0.26, 1.0)
const DEFAULT_CREATURE_NAME := "Creature"

const TREE_POSITIONS: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(16, 4), Vector2i(5, 10),
	Vector2i(14, 11), Vector2i(9, 2), Vector2i(12, 13),
]

const CREATURE_COLORS: Array[Color] = [
	Color("#f48fb1"), Color("#81d4fa"), Color("#a5d6a7"),
	Color("#fff176"), Color("#ce93d8"), Color("#ffab91"),
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
	if hex.is_empty():
		return DEFAULT_CREATURE_COLOR
	return Color.from_string(hex, DEFAULT_CREATURE_COLOR)

## Future Supabase (Phase 5)
const SUPABASE_URL := "https://gimlaqcnfdbzwdaitfec.supabase.co"
const SUPABASE_ANON_KEY := "sb_publishable_k7dql39Flel10idLrETV_g_u-JMYczq"

static func tile_to_world(tile: Vector2) -> Vector3:
	return Vector3(tile.x * TILE_SIZE + TILE_SIZE * 0.5, 0.0, tile.y * TILE_SIZE + TILE_SIZE * 0.5)

static func world_to_tile(world: Vector3) -> Vector2i:
	return Vector2i(int(floor(world.x / TILE_SIZE)), int(floor(world.z / TILE_SIZE)))
