class_name GameConfig
extends RefCounted

## Shared constants ported from js/game.js

const MAP_W := 20
const MAP_H := 15
const TILE_SIZE := 1.0

const MOVE_TILES_PER_SEC := 1.0
const STAMINA_PER_TILE := 1
const STAMINA_MAX := 10
const STAMINA_REGEN_PER_SEC := 1.0
const AFK_SLEEP_SEC := 45.0

const FIGHT_RANGE := 1.2
const EAT_RANGE := 1.1
const FIGHT_DAMAGE := 15
const FIGHT_STAMINA := 2
const EAT_STAMINA := 3

const NAME_MAX_LEN := 10

const TREE_POSITIONS: Array[Vector2i] = [
	Vector2i(3, 3), Vector2i(16, 4), Vector2i(5, 10),
	Vector2i(14, 11), Vector2i(9, 2), Vector2i(12, 13),
]

const CREATURE_COLORS: Array[Color] = [
	Color("#f48fb1"), Color("#81d4fa"), Color("#a5d6a7"),
	Color("#fff176"), Color("#ce93d8"), Color("#ffab91"),
]

## Future Supabase (Phase 5)
const SUPABASE_URL := "https://gimlaqcnfdbzwdaitfec.supabase.co"
const SUPABASE_ANON_KEY := "sb_publishable_k7dql39Flel10idLrETV_g_u-JMYczq"

static func tile_to_world(tile: Vector2) -> Vector3:
	return Vector3(tile.x * TILE_SIZE + TILE_SIZE * 0.5, 0.0, tile.y * TILE_SIZE + TILE_SIZE * 0.5)

static func world_to_tile(world: Vector3) -> Vector2i:
	return Vector2i(int(floor(world.x / TILE_SIZE)), int(floor(world.z / TILE_SIZE)))
