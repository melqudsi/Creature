class_name GridNav
extends RefCounted

static func in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < GameConfig.MAP_W and tile.y < GameConfig.MAP_H

static func is_blocked(tile: Vector2i, blocked_tiles: Array[Vector2i], unit_tiles: Dictionary) -> bool:
	if not in_bounds(tile):
		return true
	if tile in blocked_tiles:
		return true
	if unit_tiles.has(tile):
		return true
	return false

static func step_toward(from: Vector2, target: Vector2, blocked_tiles: Array[Vector2i], unit_tiles: Dictionary) -> Vector2i:
	var from_i := Vector2i(int(round(from.x)), int(round(from.y)))
	var target_i := Vector2i(int(round(target.x)), int(round(target.y)))
	if from_i == target_i:
		return from_i
	var dx := 0
	var dy := 0
	if from_i.x != target_i.x:
		dx = 1 if target_i.x > from_i.x else -1
	elif from_i.y != target_i.y:
		dy = 1 if target_i.y > from_i.y else -1
	var next := Vector2i(from_i.x + dx, from_i.y + dy)
	if is_blocked(next, blocked_tiles, unit_tiles):
		return from_i
	return next

static func distance(a: Vector2, b: Vector2) -> float:
	return Vector2(a.x - b.x, a.y - b.y).length()
