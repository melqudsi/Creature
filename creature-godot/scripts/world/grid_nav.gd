class_name GridNav
extends RefCounted

const NEIGHBORS_8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
	Vector2i(1, 1), Vector2i(1, -1), Vector2i(-1, 1), Vector2i(-1, -1),
]

static func in_bounds(tile: Vector2i) -> bool:
	return tile.x >= 0 and tile.y >= 0 and tile.x < GameConfig.MAP_W and tile.y < GameConfig.MAP_H

static func clamp_tile(tile: Vector2i) -> Vector2i:
	return Vector2i(
		clampi(tile.x, 0, GameConfig.MAP_W - 1),
		clampi(tile.y, 0, GameConfig.MAP_H - 1)
	)

static func is_blocked(tile: Vector2i, blocked_tiles: Dictionary, unit_tiles: Dictionary) -> bool:
	if not in_bounds(tile):
		return true
	if blocked_tiles.has(tile):
		return true
	if unit_tiles.has(tile):
		return true
	return false

static func distance(a: Vector2, b: Vector2) -> float:
	return a.distance_to(b)

static func find_path(
	from: Vector2,
	target: Vector2,
	blocked_tiles: Dictionary,
	unit_tiles: Dictionary
) -> Array[Vector2]:
	var start := Vector2i(int(round(from.x)), int(round(from.y)))
	var goal := clamp_tile(Vector2i(int(round(target.x)), int(round(target.y))))

	if is_blocked(goal, blocked_tiles, unit_tiles):
		goal = nearest_walkable(goal, start, blocked_tiles, unit_tiles)
		if goal.x < 0:
			return []

	if start == goal:
		return []

	var open: Array[Vector2i] = [start]
	var open_lookup: Dictionary = {start: true}
	var came_from: Dictionary = {}
	var g_score: Dictionary = {start: 0.0}
	var f_score: Dictionary = {start: _heuristic(start, goal)}

	while not open.is_empty():
		var current := _pop_lowest(open, f_score)
		open_lookup.erase(current)

		if current == goal:
			var path := _reconstruct_path(came_from, goal)
			return simplify_path(from, path, blocked_tiles, unit_tiles)

		for offset in NEIGHBORS_8:
			var neighbor := current + offset
			if not in_bounds(neighbor):
				continue
			if is_blocked(neighbor, blocked_tiles, unit_tiles) and neighbor != goal:
				continue
			if offset.x != 0 and offset.y != 0:
				if is_blocked(Vector2i(current.x + offset.x, current.y), blocked_tiles, unit_tiles):
					continue
				if is_blocked(Vector2i(current.x, current.y + offset.y), blocked_tiles, unit_tiles):
					continue

			var step_cost := 1.414213562 if offset.x != 0 and offset.y != 0 else 1.0
			var tentative_g: float = g_score[current] + step_cost
			if tentative_g >= g_score.get(neighbor, INF):
				continue

			came_from[neighbor] = current
			g_score[neighbor] = tentative_g
			f_score[neighbor] = tentative_g + _heuristic(neighbor, goal)
			if not open_lookup.has(neighbor):
				open.append(neighbor)
				open_lookup[neighbor] = true

	return []

static func nearest_walkable(
	goal: Vector2i,
	start: Vector2i,
	blocked_tiles: Dictionary,
	unit_tiles: Dictionary
) -> Vector2i:
	if not is_blocked(goal, blocked_tiles, unit_tiles):
		return goal

	var queue: Array[Vector2i] = [goal]
	var visited: Dictionary = {goal: true}
	var best := Vector2i(-1, -1)
	var best_dist := INF

	while not queue.is_empty():
		var tile: Vector2i = queue.pop_front()
		if not is_blocked(tile, blocked_tiles, unit_tiles):
			var dist := Vector2(tile - start).length_squared()
			if dist < best_dist:
				best_dist = dist
				best = tile
			continue
		for offset in NEIGHBORS_8:
			if offset.x != 0 and offset.y != 0:
				continue
			var next := tile + offset
			if not in_bounds(next) or visited.has(next):
				continue
			visited[next] = true
			queue.append(next)

	return best

static func simplify_path(
	from: Vector2,
	path: Array[Vector2],
	blocked_tiles: Dictionary,
	unit_tiles: Dictionary
) -> Array[Vector2]:
	if path.is_empty():
		return path

	var simplified: Array[Vector2] = []
	var anchor_i := Vector2i(int(round(from.x)), int(round(from.y)))
	var index := 0

	while index < path.size():
		var far_index := path.size() - 1
		while far_index > index:
			var far_i := Vector2i(int(round(path[far_index].x)), int(round(path[far_index].y)))
			if has_clear_path(anchor_i, far_i, blocked_tiles, unit_tiles):
				break
			far_index -= 1
		simplified.append(path[far_index])
		anchor_i = Vector2i(int(round(path[far_index].x)), int(round(path[far_index].y)))
		index = far_index + 1

	return simplified

static func has_clear_path(
	from: Vector2i,
	to: Vector2i,
	blocked_tiles: Dictionary,
	unit_tiles: Dictionary
) -> bool:
	if from == to:
		return true
	for tile in _line_tiles(from, to):
		if tile == from or tile == to:
			continue
		if is_blocked(tile, blocked_tiles, unit_tiles):
			return false
	return true

static func _line_tiles(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	var x0 := from.x
	var y0 := from.y
	var x1 := to.x
	var y1 := to.y
	var dx := absi(x1 - x0)
	var dy := -absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx + dy

	while true:
		tiles.append(Vector2i(x0, y0))
		if x0 == x1 and y0 == y1:
			break
		var e2 := err * 2
		if e2 >= dy:
			err += dy
			x0 += sx
		if e2 <= dx:
			err += dx
			y0 += sy

	return tiles

static func _heuristic(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()

static func _reconstruct_path(came_from: Dictionary, goal: Vector2i) -> Array[Vector2]:
	var path: Array[Vector2] = []
	var current := goal
	while came_from.has(current):
		path.push_front(Vector2(current))
		current = came_from[current]
	return path

static func _pop_lowest(open: Array[Vector2i], f_score: Dictionary) -> Vector2i:
	var best_index := 0
	var best_score: float = f_score.get(open[0], INF)
	for i in range(1, open.size()):
		var score: float = f_score.get(open[i], INF)
		if score < best_score:
			best_score = score
			best_index = i
	var node: Vector2i = open[best_index]
	open.remove_at(best_index)
	return node

# Legacy helper — prefer find_path().
static func step_toward(
	from: Vector2,
	target: Vector2,
	blocked_tiles: Dictionary,
	unit_tiles: Dictionary
) -> Vector2i:
	var path := find_path(from, target, blocked_tiles, unit_tiles)
	if path.is_empty():
		return Vector2i(int(round(from.x)), int(round(from.y)))
	var next := path[0]
	return Vector2i(int(round(next.x)), int(round(next.y)))
