class_name FormDefs
extends RefCounted

## Central shapeshift-form abstraction (Slice 1).
##
## A "form" is what the player currently is (alien by default, or a world object
## they shapeshifted into). Each form has a movement speed multiplier, a
## collision radius, a visual mesh key, and a "kind" used by the kill matrix.
##
## Slice 2/3 can add more forms here (money-carrying, extra vehicles) without
## touching the creature/collision code: add a key to FORMS + a mesh branch in
## ObjectMesh + (optionally) rules in resolve_player_death().

const ALIEN := "alien"
const ALTIMA := "altima"
const MAGNOLIA := "magnolia_tree"
const POTHOLE := "pothole"
const PROPANE := "propane_tank"

const DEFAULT_FORM := ALIEN

## speed = multiplier on GameConfig.MOVE_TILES_PER_SEC
## radius = collision/kill radius in world units (TILE_SIZE = 1.0)
## kind  = kill-matrix category (alien / vehicle / tree / pothole / propane)
## visual = ObjectMesh key (alien is drawn procedurally by Creature itself)
const FORMS := {
	ALIEN: {"display": "Alien", "speed": 1.0, "radius": 0.35, "kind": "alien", "visual": "alien"},
	ALTIMA: {"display": "Altima", "speed": 3.0, "radius": 0.55, "kind": "vehicle", "visual": "altima"},
	MAGNOLIA: {"display": "Magnolia Tree", "speed": 0.25, "radius": 0.5, "kind": "tree", "visual": "magnolia"},
	POTHOLE: {"display": "Pothole", "speed": 0.2, "radius": 0.5, "kind": "pothole", "visual": "pothole"},
	PROPANE: {"display": "Propane Tank", "speed": 0.5, "radius": 0.45, "kind": "propane", "visual": "propane"},
}

## Funny death lines (verbatim from the design doc).
const DEATH_ALTIMA := "You got Altima'd."
const DEATH_ROADKILL := "You became roadkill."
const DEATH_TREE := "You challenged a tree and lost."
const DEATH_POTHOLE := "The pothole won."
const DEATH_PROPANE := "Propane had other plans."
const DEATH_BUILDING := "MATA said move."

static func is_valid(key: String) -> bool:
	return FORMS.has(key)

static func get_cfg(key: String) -> Dictionary:
	return FORMS.get(key, FORMS[ALIEN])

static func display(key: String) -> String:
	return get_cfg(key).display

static func speed_mult(key: String) -> float:
	return get_cfg(key).speed

static func radius(key: String) -> float:
	return get_cfg(key).radius

static func kind(key: String) -> String:
	return get_cfg(key).kind

static func visual(key: String) -> String:
	return get_cfg(key).visual

static func is_alien(key: String) -> bool:
	return key == ALIEN or key.is_empty() or not FORMS.has(key)

static func is_vehicle(key: String) -> bool:
	return kind(key) == "vehicle"

## Resolve whether MY player dies from touching something of `other_kind`.
## Kills are CLIENT-LOCAL: we only ever decide whether our own player dies (see
## the NETWORKING notes in the handoff). `other_kind` is the kill-matrix kind of
## the thing we touched (a world object's kind, or a remote creature's form kind).
##
## Returns {die: bool, explode: bool, reason: String}.
static func resolve_player_death(my_key: String, other_kind: String) -> Dictionary:
	var out := {"die": false, "explode": false, "reason": ""}
	match kind(my_key):
		"vehicle": # Altima (Phase 1 vehicle)
			match other_kind:
				"tree":
					out.die = true
					out.reason = DEATH_TREE
				"pothole":
					out.die = true
					out.reason = DEATH_POTHOLE
				"building":
					out.die = true
					out.reason = DEATH_BUILDING
				"propane":
					out.die = true
					out.explode = true
					out.reason = DEATH_PROPANE
		"alien":
			match other_kind:
				"vehicle":
					out.die = true
					out.reason = DEATH_ALTIMA if randf() < 0.5 else DEATH_ROADKILL
		"propane": # I'm the propane tank; a vehicle hitting me sets me off
			match other_kind:
				"vehicle":
					out.die = true
					out.explode = true
					out.reason = DEATH_PROPANE
		# tree / pothole forms have no self-death in Phase 1 (they kill vehicles,
		# but that is resolved on the vehicle's own client).
	return out

## Which forms an explosion is lethal to (aliens and vehicles per the doc).
static func explosion_kills(key: String) -> bool:
	var k := kind(key)
	return k == "alien" or k == "vehicle"
