class_name WorldObject
extends Node3D

## A single interactive / solid thing in the world: a tree, a building, a
## landfill prop, or a shapeshiftable object (Rusty Altima, small tree, pothole,
## propane tank...). Every WorldObject registers itself in GameState.world_objects
## so the player can cheaply scan for collisions, kill-matrix contacts, and
## shapeshift targets each frame.
##
## `kind`    - kill-matrix category (tree / pothole / propane / building / prop)
## `form_key`- FormDefs key you Become from it, or "" if not shapeshiftable
## `visual`  - ObjectMesh key for its appearance
## `radius`  - collision radius (world units)

var kind := "prop"
var form_key := ""
var visual := "trash"
var radius := 0.4
var display_name := "Object"
var consumed := false
var spawn_world_pos := Vector3.ZERO

## Shared-state identity (Fix 3). When this object is backed by a row in the
## Supabase `public.world_objects` table, `object_id` is its uuid and `type_key`
## is the config key used to rebuild it (altima/magnolia/propane/pothole/...).
## `spawn_tile` is the home tile (grid space) it returns to after a death.
## Purely client-local fallback objects leave `object_id` empty and never sync.
var object_id := ""
var type_key := ""
var spawn_tile := Vector2.ZERO

var _tint := Color(0.6, 0.6, 0.6)

func configure(cfg: Dictionary) -> void:
	kind = cfg.get("kind", "prop")
	form_key = cfg.get("form_key", "")
	visual = cfg.get("visual", "trash")
	radius = cfg.get("radius", 0.4)
	display_name = cfg.get("display_name", "Object")
	_tint = cfg.get("tint", _tint)

func _ready() -> void:
	_build_visual()
	GameState.register_world_object(self)

func _exit_tree() -> void:
	GameState.unregister_world_object(self)

func _build_visual() -> void:
	for ch in get_children():
		ch.queue_free()
	add_child(ObjectMesh.build(visual, _tint))

## Set both the current position and the point this object returns to when it
## respawns after being consumed by a shapeshifter.
func set_spawn_position(pos: Vector3) -> void:
	position = pos
	spawn_world_pos = pos
	spawn_tile = Vector2(GameConfig.world_to_tile(pos))

func is_shapeshiftable() -> bool:
	return not form_key.is_empty()

## Hidden + inert while a player is shapeshifted into it.
func consume() -> void:
	consumed = true
	visible = false

func respawn_at(pos: Vector3) -> void:
	position = pos
	consumed = false
	visible = true
