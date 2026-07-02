extends SceneTree

## Headless probe: verify Memphis-map pathfinding works (run with
## godot --headless -s scripts/debug/path_probe.gd).

func _init() -> void:
	var blocked := MemphisLayout.blocked_tiles()
	print("blocked tiles: ", blocked.size())
	print("(19,28) blocked: ", blocked.has(Vector2i(19, 28)))
	print("(25,32) blocked: ", blocked.has(Vector2i(25, 32)))
	var t0 := Time.get_ticks_msec()
	var path := GridNav.find_path(Vector2(19, 28), Vector2(25, 32), blocked, {})
	print("path 19,28->25,32: ", path.size(), " pts in ", Time.get_ticks_msec() - t0, "ms: ", path)
	t0 = Time.get_ticks_msec()
	var long_path := GridNav.find_path(Vector2(23, 101), Vector2(150, 20), blocked, {})
	print("dump->I40-east: ", long_path.size(), " pts in ", Time.get_ticks_msec() - t0, "ms")
	t0 = Time.get_ticks_msec()
	var bridge_path := GridNav.find_path(Vector2(19, 28), Vector2(3, 25), blocked, {})
	print("downtown->bridge: ", bridge_path.size(), " pts in ", Time.get_ticks_msec() - t0, "ms")
	quit()
