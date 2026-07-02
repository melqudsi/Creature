class_name FormDefs
extends RefCounted

## Central shapeshift-form abstraction (Slice 1 + money carry rules Slice 2).

const ALIEN := "alien"
const ALTIMA := "altima"
const MAGNOLIA := "magnolia_tree"
const POTHOLE := "pothole"
const PROPANE := "propane_tank"
const SHOPPING_CART := "shopping_cart"
const MATA_BUS := "mata_bus"

const DEFAULT_FORM := ALIEN

## Money tiers (Slice 2).
const TIER_STACK := 1
const TIER_BAG := 2
const TIER_VAULT := 3

const FORMS := {
	ALIEN: {"display": "Alien", "speed": 1.0, "radius": 0.35, "kind": "alien", "visual": "alien"},
	ALTIMA: {"display": "Altima", "speed": 3.0, "radius": 0.55, "kind": "vehicle", "visual": "altima"},
	MAGNOLIA: {"display": "Magnolia Tree", "speed": 0.25, "radius": 0.5, "kind": "tree", "visual": "magnolia"},
	POTHOLE: {"display": "Pothole", "speed": 0.2, "radius": 0.5, "kind": "pothole", "visual": "pothole"},
	PROPANE: {"display": "Propane Tank", "speed": 0.5, "radius": 0.45, "kind": "propane", "visual": "propane"},
	SHOPPING_CART: {"display": "Shopping Cart", "speed": 1.4, "radius": 0.42, "kind": "cart", "visual": "cart"},
	MATA_BUS: {"display": "MATA Bus", "speed": 0.85, "radius": 0.75, "kind": "mata_bus", "visual": "mata_bus"},
}

const DEATH_ALTIMA := "You got Altima'd."
const DEATH_ROADKILL := "You became roadkill."
const DEATH_TREE := "You challenged a tree and lost."
const DEATH_POTHOLE := "The pothole won."
const DEATH_PROPANE := "Propane had other plans."
const DEATH_HOUSE := "You crashed into a house."
const DEATH_BUS := "MATA said move."

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
		if form_key == SHOPPING_CART or form_key == ALTIMA:
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
	return out

static func explosion_kills(key: String) -> bool:
	var k := kind(key)
	return k == "alien" or k == "vehicle" or k == "cart" or k == "mata_bus"
