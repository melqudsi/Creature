class_name FormDefs
extends RefCounted

## Central shapeshift-form abstraction (Slice 1 + money carry rules Slice 2).

const ALIEN := "alien"
const ALTIMA := "altima"
const MAGNOLIA := "magnolia_tree"
const POTHOLE := "pothole"
const PROPANE := "propane_tank"
const BBQ_GRILL := "bbq_grill"
const SHOPPING_CART := "shopping_cart"
const MATA_BUS := "mata_bus"
const BBQ_SMOKER := "bbq_smoker"
const CHARGER := "dodge_charger_temp_tags"
const TREE := "tree"
const PYRAMID := "pyramid"
const HOUSE := "house"
const MEMPHIS_TIGER := "memphis_tiger"
const MEMPHIS_BEAR := "memphis_bear"
const HUMAN := "human"

const DEFAULT_FORM := ALIEN

## Money tiers (Slice 2).
const TIER_STACK := 1
const TIER_BAG := 2
const TIER_VAULT := 3

const FORMS := {
	ALIEN: {"display": "Alien", "speed": 1.0, "radius": 0.35, "kind": "alien", "visual": "alien"},
	ALTIMA: {"display": "Altima", "speed": 3.0, "radius": 0.55, "kind": "vehicle", "visual": "altima"},
	MAGNOLIA: {"display": "Magnolia Tree", "speed": 0.5, "radius": 0.5, "kind": "tree", "visual": "magnolia"},
	POTHOLE: {"display": "Pothole", "speed": 0.45, "radius": 0.5, "kind": "pothole", "visual": "pothole"},
	PROPANE: {"display": "Propane Tank", "speed": 0.8, "radius": 0.45, "kind": "propane", "visual": "propane"},
	BBQ_GRILL: {"display": "BBQ Grill", "speed": 1.15, "radius": 0.5, "kind": "propane", "visual": "bbq_grill"},
	SHOPPING_CART: {"display": "Shopping Cart", "speed": 1.6, "radius": 0.42, "kind": "cart", "visual": "cart"},
	MATA_BUS: {"display": "MATA Bus", "speed": 1.3, "radius": 0.75, "kind": "mata_bus", "visual": "mata_bus"},
	BBQ_SMOKER: {"display": "BBQ Smoker", "speed": 0.9, "radius": 0.5, "kind": "smoker", "visual": "smoker"},
	CHARGER: {"display": "Dodge Charger With Temp Tags", "speed": 3.8, "radius": 0.55, "kind": "vehicle", "visual": "charger"},
	TREE: {"display": "Tree", "speed": 0.5, "radius": 0.5, "kind": "tree", "visual": "tree"},
	# The Pyramid does not move. The Pyramid abducts.
	PYRAMID: {"display": "The Pyramid", "speed": 0.0, "radius": 2.2, "kind": "building", "visual": "pyramid"},
	# A walking house. Slow, uncrushable, claimable as a personal safe house
	# (claimed = rooted in place until unclaimed).
	HOUSE: {"display": "House", "speed": 0.4, "radius": 0.9, "kind": "building", "visual": "building"},
	# Memphis Zoo predators — tiger runs at boosted-Altima speed; bear is slower
	# but can perch on trees (creature.gd).
	MEMPHIS_TIGER: {"display": "Memphis Tiger", "speed": 6.6, "radius": 0.32, "kind": "zoo_tiger", "visual": "tiger"},
	MEMPHIS_BEAR: {"display": "Memphis Grizzly Bear", "speed": 1.1, "radius": 0.44, "kind": "zoo_bear", "visual": "bear"},
	# Human disguise (Slice 9). Slightly quicker than the alien worm, but soft:
	# dies to vehicles, buses, zoo predators, and explosions like anyone else.
	HUMAN: {"display": "Human", "speed": 1.2, "radius": 0.3, "kind": "human", "visual": "human"},
}

const DEATH_ALTIMA := "You got Altima'd."
const DEATH_ROADKILL := "You became roadkill."
const DEATH_TREE := "You challenged a tree and lost."
const DEATH_POTHOLE := "The pothole won."
const DEATH_PROPANE := "Propane had other plans."
const DEATH_HOUSE := "You crashed into a house."
const DEATH_BUS := "MATA said move."
const DEATH_SELF_DETONATE := "You detonated. On purpose. Respect."
const DEATH_ABDUCTED := "You got abducted. Enjoy the mothership."
const DEATH_TIGER := "The Memphis Tiger had you for lunch."
const DEATH_BEAR := "The Memphis Grizzly Bear had you for lunch."
const DEATH_ANIMAL_VEHICLE := "Roadkill at the zoo."
const DEATH_ANIMAL_FIGHT := "Nature is metal at the Memphis Zoo."
const DEATH_HUMAN_VEHICLE := "Jaywalking in Memphis. Bold."
const DEATH_HUMAN_EATEN := "Something ate you. It wasn't from around here."

static func is_zoo_animal(key: String) -> bool:
	return key == MEMPHIS_TIGER or key == MEMPHIS_BEAR

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
	var k := kind(key)
	return k == "vehicle" or k == "mata_bus"

## Altima and MATA Bus pathfind through other creatures (kills resolve on contact).
static func ignores_units(key: String) -> bool:
	return is_vehicle(key)

static func tier_for_type(type_key: String) -> int:
	match type_key:
		"money_bag": return TIER_BAG
		"vault": return TIER_VAULT
		"money_stack": return TIER_STACK
		_: return 0

static func tier_display(tier: int) -> String:
	match tier:
		TIER_BAG: return "Money Bag"
		TIER_VAULT: return "Vault"
		TIER_STACK: return "Money Stack"
		_: return "Loot"

static func tier_weight(tier: int) -> float:
	match tier:
		TIER_VAULT: return 3.0
		TIER_BAG: return 2.0
		TIER_STACK: return 1.0
		_: return 0.0

## Can this form pick up another object of `new_tier` given what's already carried?
static func carry_check(form_key: String, carried_tiers: Array, new_tier: int) -> Dictionary:
	var fail := func(reason: String) -> Dictionary:
		return {"ok": false, "reason": reason}
	var ok := {"ok": true, "reason": ""}
	var count := carried_tiers.size()
	var has_bag := carried_tiers.has(TIER_BAG)
	var has_vault := carried_tiers.has(TIER_VAULT)
	var stack_count := 0
	for t in carried_tiers:
		if int(t) == TIER_STACK:
			stack_count += 1

	if new_tier == TIER_VAULT:
		if form_key != MATA_BUS:
			return fail.call("%s can't carry a vault" % display(form_key))
		if count > 0:
			return fail.call("Bus already hauling loot")
		return ok

	if new_tier == TIER_BAG:
		if form_key == ALIEN:
			if count >= 1:
				return fail.call("Alien can only carry one item")
			return ok
		if form_key == SHOPPING_CART or form_key == ALTIMA or form_key == CHARGER or form_key == BBQ_SMOKER:
			if count >= 1:
				return fail.call("%s can carry one bag OR stacks, not both" % display(form_key))
			return ok
		if form_key == MATA_BUS:
			if has_vault:
				return fail.call("Vault fills the bus")
			if count >= 3:
				return fail.call("Bus is full of bags")
			return ok
		return fail.call("%s can't carry a bag" % display(form_key))

	if new_tier == TIER_STACK:
		if has_bag or has_vault:
			return fail.call("Already carrying heavier loot")
		match form_key:
			ALIEN:
				if count >= 1:
					return fail.call("Alien can only carry one stack")
				return ok
			SHOPPING_CART:
				if stack_count >= 4:
					return fail.call("Cart is full")
				return ok
			ALTIMA:
				if stack_count >= 3:
					return fail.call("Altima is full")
				return ok
			CHARGER:
				if stack_count >= 3:
					return fail.call("Charger is full")
				return ok
			BBQ_SMOKER:
				if stack_count >= 2:
					return fail.call("Smoker is full")
				return ok
			_:
				return fail.call("%s can't carry stacks" % display(form_key))

	return fail.call("Unknown loot type")

static func resolve_player_death(my_key: String, other_kind: String) -> Dictionary:
	var out := {"die": false, "explode": false, "reason": ""}
	match kind(my_key):
		"vehicle":
			match other_kind:
				"tree":
					out.die = true
					out.reason = DEATH_TREE
				"pothole":
					out.die = true
					out.reason = DEATH_POTHOLE
				"building":
					out.die = true
					out.reason = DEATH_HOUSE
				"propane":
					out.die = true
					out.explode = true
					out.reason = DEATH_PROPANE
				"mata_bus":
					out.die = true
					out.reason = DEATH_BUS
		"mata_bus":
			match other_kind:
				"tree":
					out.die = true
					out.reason = DEATH_TREE
				"building":
					out.die = true
					out.reason = DEATH_HOUSE
				"propane":
					out.die = true
					out.explode = true
					out.reason = DEATH_PROPANE
			# Potholes don't faze a bus — it's a Memphis bus.
		"alien":
			match other_kind:
				"vehicle":
					out.die = true
					out.reason = DEATH_ALTIMA if randf() < 0.5 else DEATH_ROADKILL
				"mata_bus":
					out.die = true
					out.reason = DEATH_BUS
				"zoo_tiger":
					out.die = true
					out.reason = DEATH_TIGER
				"zoo_bear":
					out.die = true
					out.reason = DEATH_BEAR
		"cart":
			match other_kind:
				"vehicle":
					out.die = true
					out.reason = DEATH_ROADKILL
				"mata_bus":
					out.die = true
					out.reason = DEATH_BUS
		"propane":
			match other_kind:
				"vehicle", "mata_bus":
					out.die = true
					out.explode = true
					out.reason = DEATH_PROPANE
		"smoker":
			# Per the design PDF, an Altima can't kill the smoker (it's vulnerable
			# to THEFT, not squishing) — only a moving bus or an explosion can.
			match other_kind:
				"mata_bus":
					out.die = true
					out.reason = DEATH_BUS
		"zoo_tiger", "zoo_bear":
			match other_kind:
				"vehicle", "mata_bus":
					out.die = true
					out.reason = DEATH_ANIMAL_VEHICLE
				"zoo_tiger", "zoo_bear":
					out.die = true
					out.reason = DEATH_ANIMAL_FIGHT
		"human":
			match other_kind:
				"vehicle":
					out.die = true
					out.reason = DEATH_HUMAN_VEHICLE
				"mata_bus":
					out.die = true
					out.reason = DEATH_BUS
				"zoo_tiger":
					out.die = true
					out.reason = DEATH_TIGER
				"zoo_bear":
					out.die = true
					out.reason = DEATH_BEAR
	return out

static func explosion_kills(key: String) -> bool:
	# Explosive props are crowd-control: any player-controlled form caught in
	# the blast dies, including trees/houses/potholes and future forms.
	return is_valid(key)
