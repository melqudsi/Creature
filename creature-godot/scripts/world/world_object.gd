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
		set_money_owner(v if typeof(v) == TYPE_STRING else "")
	carried_by = str(row.get("possessed_by", "")) if str(row.get("state", "")) == "carried" else ""

func _ready() -> void:
	_build_visual()
	GameState.register_world_object(self)

func _exit_tree() -> void:
	GameState.unregister_world_object(self)

func _build_visual() -> void:
	for ch in get_children():
		ch.queue_free()
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
	if tier < FormDefs.TIER_BAG or owner_name.is_empty():
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
