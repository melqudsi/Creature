class_name WorldObject
extends Node3D

var kind := "prop"
var form_key := ""
var visual := "trash"
var radius := 0.4
var display_name := "Object"
var consumed := false
var spawn_world_pos := Vector3.ZERO

var object_id := ""
var type_key := ""
var spawn_tile := Vector2.ZERO

## Money (Slice 2): tier 1/2/3, owner label, carrier user id when state=carried.
var tier := 0
var owner_name := ""
var carried_by := ""
## Safe house (Slice 7): player name parsed from an owner_name "safe:<NAME>"
## segment. A claimed safe house is rooted and only its owner may wear it.
var safe_owner := ""
## Big House (Slice 10): "big" flag, "vaults:N" stored count, and
## "robbed:<unix>:<NAME>" cooldown segments (all inside owner_name).
var is_big := false
var stored_vaults := 0
var robbed_unix := 0
var robbed_by := ""
var _house_state_seen := false

var _tint := Color(0.6, 0.6, 0.6)
var _owner_label: Label3D

func configure(cfg: Dictionary) -> void:
	kind = cfg.get("kind", "prop")
	form_key = cfg.get("form_key", "")
	visual = cfg.get("visual", "trash")
	radius = cfg.get("radius", 0.4)
	display_name = cfg.get("display_name", "Object")
	tier = int(cfg.get("tier", 0))
	_tint = cfg.get("tint", _tint)

func apply_row(row: Dictionary) -> void:
	if row.has("owner_name"):
		var v: Variant = row.get("owner_name")
		# JSON null must clear the label; str(null) would be "<null>".
		if kind == "building":
			# Keep the raw string (home:x,y|safe:NAME) so claim/unclaim patches
			# can preserve the home segment; the label shows only the safe owner.
			owner_name = str(v).strip_edges() if typeof(v) == TYPE_STRING else ""
			set_safe_owner(parse_safe_owner(owner_name))
			apply_house_state()
		else:
			set_money_owner(v if typeof(v) == TYPE_STRING else "")
	carried_by = str(row.get("possessed_by", "")) if str(row.get("state", "")) == "carried" else ""

## owner_name for houses is "home:x,y", "safe:NAME", or "home:x,y|safe:NAME".
static func parse_safe_owner(owner_string: String) -> String:
	for seg in owner_string.split("|"):
		if seg.begins_with("safe:"):
			return seg.substr(5)
	return ""

static func parse_home_part(owner_string: String) -> String:
	for seg in owner_string.split("|"):
		if seg.begins_with("home:"):
			return seg
	return ""

# ---------------------------------------------------------------------------
# Big House segments. owner_name examples:
#   "home:12,40|safe:MOE|big|vaults:2"
#   "home:12,40|big|vaults:0|robbed:1720000000:JUNE"   (unclaimed Big House)
# ---------------------------------------------------------------------------

static func parse_big_house(owner_string: String) -> bool:
	for seg in owner_string.split("|"):
		if seg == "big":
			return true
	return false

static func parse_stored_vaults(owner_string: String) -> int:
	for seg in owner_string.split("|"):
		if seg.begins_with("vaults:"):
			return clampi(int(seg.substr(7)), 0, 4)
	return 0

## {"unix": int, "by": String} from a "robbed:<unix>:<NAME>" segment.
static func parse_robbed(owner_string: String) -> Dictionary:
	for seg in owner_string.split("|"):
		if seg.begins_with("robbed:"):
			var bits := seg.split(":")
			return {
				"unix": int(bits[1]) if bits.size() > 1 else 0,
				"by": str(bits[2]) if bits.size() > 2 else "",
			}
	return {"unix": 0, "by": ""}

## Replace (or remove, when `segment` is empty) the part starting with
## `prefix`, preserving every other segment. Used to build owner_name PATCHes.
static func set_owner_segment(owner_string: String, prefix: String, segment: String) -> String:
	var parts: Array[String] = []
	for seg in owner_string.split("|"):
		if seg.is_empty() or seg.begins_with(prefix):
			continue
		parts.append(seg)
	if not segment.is_empty():
		parts.append(segment)
	return "|".join(parts)

## Re-parse the Big House segments after owner_name changed. Swaps the visual
## when a house upgrades, refreshes window glow, and toasts the owner when a
## robbery lands while they're watching. Public: local actors (upgrade/deposit/
## rob) call it right after patching owner_name for instant feedback.
func apply_house_state() -> void:
	var was_big := is_big
	var prev_robbed := robbed_unix
	var seen := _house_state_seen
	_house_state_seen = true
	is_big = parse_big_house(owner_name)
	stored_vaults = parse_stored_vaults(owner_name)
	var rob := parse_robbed(owner_name)
	robbed_unix = int(rob.get("unix", 0))
	robbed_by = str(rob.get("by", ""))
	if is_big != was_big:
		visual = "big_house" if is_big else "building"
		_build_visual()
	if is_big:
		_apply_window_glow()
	if seen and robbed_unix > prev_robbed and not robbed_by.is_empty():
		var pc: Node = GameState.player_creature
		var me: String = pc.creature_name if pc != null and is_instance_valid(pc) else ""
		if not me.is_empty() and safe_owner == me and robbed_by != me:
			GameState.show_toast("%s robbed your Big House!" % robbed_by)

## Light up one window (plus its golden beam) per stored vault so everyone can
## see how loaded the house is.
func _apply_window_glow() -> void:
	for ch in get_children():
		if not ch.has_meta("bh_windows"):
			continue
		var windows: Array = ch.get_meta("bh_windows")
		for i in windows.size():
			var w: Node = windows[i]
			if w == null or not is_instance_valid(w):
				continue
			var lit: bool = i < stored_vaults
			var pane := w.get_node_or_null("Pane") as MeshInstance3D
			if pane:
				pane.material_override = ObjectMesh.big_house_window_material(lit)
			var beam := w.get_node_or_null("Beam") as Node3D
			if beam:
				beam.visible = lit

func set_safe_owner(name: String) -> void:
	safe_owner = name.strip_edges()
	_refresh_owner_label()

func _ready() -> void:
	_build_visual()
	GameState.register_world_object(self)

func _exit_tree() -> void:
	GameState.unregister_world_object(self)

func _build_visual() -> void:
	for ch in get_children():
		ch.queue_free()
	# The label was among the freed children (queue_free is deferred, so the
	# reference still looks valid) — drop it so the refresh builds a new one.
	_owner_label = null
	add_child(ObjectMesh.build(visual, _tint))
	_refresh_owner_label()

func set_spawn_position(pos: Vector3) -> void:
	position = pos
	spawn_world_pos = pos
	spawn_tile = Vector2(GameConfig.world_to_tile(pos))

func is_shapeshiftable() -> bool:
	return not form_key.is_empty() and tier == 0

func is_money() -> bool:
	return tier > 0

func set_money_owner(name: String) -> void:
	owner_name = name.strip_edges()
	_refresh_owner_label()

func _refresh_owner_label() -> void:
	var is_safe_house := not safe_owner.is_empty()
	var is_owned_money := tier >= FormDefs.TIER_BAG and not owner_name.is_empty()
	if not is_safe_house and not is_owned_money:
		if _owner_label and is_instance_valid(_owner_label):
			_owner_label.visible = false
		return
	if _owner_label == null or not is_instance_valid(_owner_label):
		_owner_label = Label3D.new()
		_owner_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_owner_label.font_size = 32
		_owner_label.position = Vector3(0, 0.95, 0)
		_owner_label.modulate = Color(1.0, 0.92, 0.35)
		add_child(_owner_label)
	if is_safe_house:
		_owner_label.text = "%s's Big House" % safe_owner if is_big else "%s's Safe House" % safe_owner
		_owner_label.position = Vector3(0, 2.6 if is_big else 1.9, 0)
		_owner_label.modulate = Color(0.55, 1.0, 0.7)
	else:
		var thing := "Money Bag" if tier == FormDefs.TIER_BAG else "Vault"
		_owner_label.text = "%s's %s" % [owner_name, thing]
	_owner_label.visible = not consumed

func consume() -> void:
	consumed = true
	visible = false
	if _owner_label and is_instance_valid(_owner_label):
		_owner_label.visible = false

func respawn_at(pos: Vector3) -> void:
	position = pos
	consumed = false
	visible = true
	carried_by = ""
	_refresh_owner_label()

# ---------------------------------------------------------------------------
# Occlusion fade: when this object sits between the camera and the player, the
# world fades it to ~30% alpha so the player stays visible behind buildings.
# ---------------------------------------------------------------------------

var _occlusion_faded := false

## Approximate visual height, used to test whether the camera->player sight
## line actually passes through this object (tall towers occlude from far away,
## small props never do).
func occlusion_height() -> float:
	match visual:
		"tower":
			return 3.6
		"pyramid":
			return 4.5
		"building":
			return 1.4
		"big_house":
			return 2.3
		"tree", "magnolia":
			return 2.0
		_:
			return 0.9

func set_occlusion_faded(faded: bool) -> void:
	if faded == _occlusion_faded:
		return
	_occlusion_faded = faded
	_apply_fade(self, faded)

func _apply_fade(node: Node, faded: bool) -> void:
	for ch in node.get_children():
		if ch.has_meta("no_fade"):
			# Window panes / light beams manage their own materials (glow +
			# transparency); stomping them here would break the effect.
			continue
		if ch is MeshInstance3D:
			var mi := ch as MeshInstance3D
			var mat := mi.material_override as StandardMaterial3D
			if mat:
				mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA if faded else BaseMaterial3D.TRANSPARENCY_DISABLED
				mat.albedo_color.a = 0.3 if faded else 1.0
			# Drop the shadow too, or the see-through spot stays dark.
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if faded \
				else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		_apply_fade(ch, faded)
