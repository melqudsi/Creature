class_name ObjectMesh
extends RefCounted

## Procedural, mobile-cheap meshes for shapeshift forms and world objects.
## One factory so a form's mesh and its world-object source look identical
## (e.g. the "altima" you Become looks like the Rusty Altima on the ground).
##
## `build()` returns a Node3D subtree meant to be parented under a Creature's
## Body node or a WorldObject. `tint` is used where a form should reflect the
## player's chosen color (currently only the alien, drawn elsewhere).

static func build(visual: String, tint: Color = Color(0.6, 0.6, 0.6)) -> Node3D:
	match visual:
		"altima":
			return _build_altima()
		"magnolia":
			return _build_tree(Color(0.36, 0.25, 0.15), Color(0.85, 0.55, 0.72))
		"tree":
			return _build_tree(Color(0.36, 0.25, 0.15), Color(0.18, 0.48, 0.22))
		"pothole":
			return _build_pothole()
		"propane":
			return _build_propane()
		"cart":
			return _build_cart()
		"mata_bus":
			return _build_mata_bus()
		"smoker":
			return _build_smoker()
		"money_stack":
			return _build_money_stack()
		"money_bag":
			return _build_money_bag()
		"vault":
			return _build_vault()
		"cone":
			return _build_cone()
		"building":
			return _build_building()
		"tower":
			return _build_tower()
		"pyramid":
			return _build_pyramid()
		"bigbox":
			return _build_bigbox(tint)
		"tiger":
			return _build_tiger()
		"bear":
			return _build_bear()
		_:
			return _build_trash()

static func _mat(color: Color, rough := 0.8, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metal
	return m

static func _mesh_node(mesh: Mesh, mat: StandardMaterial3D, pos: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	return mi

static func _build_altima() -> Node3D:
	var root := Node3D.new()
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.6, 0.28, 1.05)
	root.add_child(_mesh_node(body_mesh, _mat(Color(0.15, 0.28, 0.55), 0.35, 0.45), Vector3(0, 0.26, 0)))
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(0.5, 0.24, 0.55)
	root.add_child(_mesh_node(cabin_mesh, _mat(Color(0.1, 0.18, 0.38), 0.3, 0.5), Vector3(0, 0.48, -0.02)))
	# Rusty patch so the "Rusty Altima" reads as junk before you steal it.
	var rust_mesh := BoxMesh.new()
	rust_mesh.size = Vector3(0.62, 0.14, 0.3)
	root.add_child(_mesh_node(rust_mesh, _mat(Color(0.45, 0.28, 0.15), 0.95), Vector3(0, 0.22, 0.38)))
	var wheel_mat := _mat(Color(0.05, 0.05, 0.06), 0.9)
	for wx in [-0.3, 0.3]:
		for wz in [-0.34, 0.34]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.13
			wheel.bottom_radius = 0.13
			wheel.height = 0.1
			var w := _mesh_node(wheel, wheel_mat, Vector3(wx, 0.13, wz))
			w.rotation_degrees = Vector3(0, 0, 90)
			root.add_child(w)
	return root

static func _build_tree(trunk_col: Color, leaf_col: Color) -> Node3D:
	var root := Node3D.new()
	var trunk_mesh := BoxMesh.new()
	trunk_mesh.size = Vector3(0.25, 0.6, 0.25)
	root.add_child(_mesh_node(trunk_mesh, _mat(trunk_col), Vector3(0, 0.3, 0)))
	var foliage_mesh := BoxMesh.new()
	foliage_mesh.size = Vector3(0.9, 0.55, 0.9)
	root.add_child(_mesh_node(foliage_mesh, _mat(leaf_col), Vector3(0, 0.75, 0)))
	return root

static func _build_pothole() -> Node3D:
	var root := Node3D.new()
	# A flat dark patch of broken asphalt, barely above the ground.
	var ring_mesh := CylinderMesh.new()
	ring_mesh.top_radius = 0.5
	ring_mesh.bottom_radius = 0.5
	ring_mesh.height = 0.06
	root.add_child(_mesh_node(ring_mesh, _mat(Color(0.12, 0.12, 0.13), 0.98), Vector3(0, 0.03, 0)))
	var hole_mesh := CylinderMesh.new()
	hole_mesh.top_radius = 0.34
	hole_mesh.bottom_radius = 0.34
	hole_mesh.height = 0.02
	root.add_child(_mesh_node(hole_mesh, _mat(Color(0.02, 0.02, 0.02), 1.0), Vector3(0, 0.07, 0)))
	return root

static func _build_propane() -> Node3D:
	var root := Node3D.new()
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 0.22
	tank_mesh.bottom_radius = 0.22
	tank_mesh.height = 0.5
	root.add_child(_mesh_node(tank_mesh, _mat(Color(0.85, 0.82, 0.2), 0.5, 0.2), Vector3(0, 0.28, 0)))
	var dome := SphereMesh.new()
	dome.radius = 0.22
	dome.height = 0.3
	root.add_child(_mesh_node(dome, _mat(Color(0.85, 0.82, 0.2), 0.5, 0.2), Vector3(0, 0.53, 0)))
	var valve := CylinderMesh.new()
	valve.top_radius = 0.06
	valve.bottom_radius = 0.06
	valve.height = 0.12
	root.add_child(_mesh_node(valve, _mat(Color(0.5, 0.1, 0.08), 0.6, 0.3), Vector3(0, 0.66, 0)))
	return root

static func _build_cart() -> Node3D:
	var root := Node3D.new()
	var basket := BoxMesh.new()
	basket.size = Vector3(0.42, 0.3, 0.55)
	root.add_child(_mesh_node(basket, _mat(Color(0.75, 0.75, 0.8), 0.4, 0.6), Vector3(0, 0.35, 0)))
	var handle := BoxMesh.new()
	handle.size = Vector3(0.42, 0.28, 0.05)
	root.add_child(_mesh_node(handle, _mat(Color(0.7, 0.2, 0.2), 0.5), Vector3(0, 0.42, -0.3)))
	return root

static func _build_cone() -> Node3D:
	var root := Node3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.02
	cone.bottom_radius = 0.2
	cone.height = 0.42
	root.add_child(_mesh_node(cone, _mat(Color(0.95, 0.4, 0.05), 0.7), Vector3(0, 0.21, 0)))
	var base := BoxMesh.new()
	base.size = Vector3(0.34, 0.05, 0.34)
	root.add_child(_mesh_node(base, _mat(Color(0.9, 0.35, 0.05), 0.7), Vector3(0, 0.03, 0)))
	return root

static func _build_building() -> Node3D:
	var root := Node3D.new()
	var base_mesh := BoxMesh.new()
	base_mesh.size = Vector3(1.45, 0.85, 1.25)
	root.add_child(_mesh_node(base_mesh, _mat(Color.from_hsv(randf_range(0.05, 0.12), 0.28, 0.78), 0.88), Vector3(0, 0.425, 0)))
	var roof_mesh := BoxMesh.new()
	roof_mesh.size = Vector3(1.75, 0.18, 1.5)
	root.add_child(_mesh_node(roof_mesh, _mat(Color(0.44, 0.12, 0.08), 0.72), Vector3(0, 0.95, 0)))
	var chimney_mesh := BoxMesh.new()
	chimney_mesh.size = Vector3(0.18, 0.35, 0.18)
	root.add_child(_mesh_node(chimney_mesh, _mat(Color(0.22, 0.12, 0.1)), Vector3(0.42, 1.18, 0.22)))
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.28, 0.45, 0.04)
	root.add_child(_mesh_node(door_mesh, _mat(Color(0.23, 0.13, 0.07)), Vector3(0, 0.225, -0.65)))
	root.rotation.y = [0.0, PI * 0.5, PI, PI * 1.5][randi() % 4]
	return root

## Downtown office tower: tall box with window bands, randomized height/shade.
static func _build_tower() -> Node3D:
	var root := Node3D.new()
	var h := randf_range(2.2, 3.6)
	var body := BoxMesh.new()
	body.size = Vector3(1.35, h, 1.15)
	var shade := Color.from_hsv(randf_range(0.55, 0.62), 0.12, randf_range(0.55, 0.75))
	root.add_child(_mesh_node(body, _mat(shade, 0.6, 0.1), Vector3(0, h * 0.5, 0)))
	var band_mat := _mat(Color(0.16, 0.22, 0.3), 0.25, 0.2)
	var y := 0.5
	while y < h - 0.3:
		var band := BoxMesh.new()
		band.size = Vector3(1.4, 0.12, 1.2)
		root.add_child(_mesh_node(band, band_mat, Vector3(0, y, 0)))
		y += 0.55
	var roof := BoxMesh.new()
	roof.size = Vector3(0.5, 0.25, 0.5)
	root.add_child(_mesh_node(roof, _mat(Color(0.25, 0.27, 0.3), 0.7), Vector3(0.2, h + 0.12, 0.1)))
	return root

## The Memphis Pyramid: a shiny 4-sided pyramid (cylinder with 4 radial segs).
## Wide squat base — the real landmark reads as massive, not needle-tall.
static func _build_pyramid() -> Node3D:
	var root := Node3D.new()
	var pyr := CylinderMesh.new()
	pyr.top_radius = 0.0
	pyr.bottom_radius = 2.85
	pyr.height = 2.35
	pyr.radial_segments = 4
	var node := _mesh_node(pyr, _mat(Color(0.75, 0.78, 0.82), 0.25, 0.75), Vector3(0, 1.18, 0))
	node.rotation.y = PI * 0.25
	root.add_child(node)
	var base := BoxMesh.new()
	base.size = Vector3(5.6, 0.18, 5.6)
	root.add_child(_mesh_node(base, _mat(Color(0.4, 0.42, 0.45), 0.8), Vector3(0, 0.09, 0)))
	return root

## Big-box store/warehouse (Kroger, FedEx hub, airport terminal): wide flat
## slab with a colored sign band across the front. `tint` = brand color.
static func _build_bigbox(tint: Color) -> Node3D:
	var root := Node3D.new()
	var wall_mat := _mat(Color(0.78, 0.76, 0.72), 1.0, 0.0)
	var slab := BoxMesh.new()
	slab.size = Vector3(2.6, 1.0, 1.5)
	root.add_child(_mesh_node(slab, wall_mat, Vector3(0.5, 0.5, 0)))
	# Sign band sits ON TOP of the slab (no overlap — overlap caused z-fighting
	# / white roof shimmer when the camera moved).
	var band := BoxMesh.new()
	band.size = Vector3(2.62, 0.24, 1.52)
	root.add_child(_mesh_node(band, _mat(tint, 0.85, 0.0), Vector3(0.5, 1.12, 0)))
	var door := BoxMesh.new()
	door.size = Vector3(0.7, 0.55, 0.05)
	root.add_child(_mesh_node(door, _mat(Color(0.2, 0.26, 0.3), 0.3, 0.0), Vector3(0.5, 0.28, 0.76)))
	return root

static func _build_mata_bus() -> Node3D:
	var root := Node3D.new()
	# White body, raised enough that the wheels sit under it and read clearly.
	var body_mesh := BoxMesh.new()
	body_mesh.size = Vector3(0.95, 0.55, 2.2)
	root.add_child(_mesh_node(body_mesh, _mat(Color(0.93, 0.94, 0.95), 0.45, 0.1), Vector3(0, 0.5, 0)))
	# MATA green horizontal stripe wrapping the sides (slightly wider than the
	# body so it visibly stands proud of the white panels).
	var stripe := BoxMesh.new()
	stripe.size = Vector3(1.0, 0.14, 2.1)
	root.add_child(_mesh_node(stripe, _mat(Color(0.08, 0.55, 0.28), 0.5), Vector3(0, 0.42, 0)))
	# Dark side-window band above the stripe.
	var windows := BoxMesh.new()
	windows.size = Vector3(0.97, 0.16, 1.55)
	root.add_child(_mesh_node(windows, _mat(Color(0.12, 0.16, 0.2), 0.25, 0.3), Vector3(0, 0.62, -0.15)))
	# Windshield: protrudes from the front face so it's actually visible.
	var windshield := BoxMesh.new()
	windshield.size = Vector3(0.8, 0.3, 0.07)
	root.add_child(_mesh_node(windshield, _mat(Color(0.14, 0.2, 0.26), 0.2, 0.35), Vector3(0, 0.58, 1.09)))
	# Wheels: pushed out past the body sides so they aren't buried.
	var wheel_mat := _mat(Color(0.05, 0.05, 0.06), 0.9)
	for wx in [-0.5, 0.5]:
		for wz in [-0.78, 0.78]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.17
			wheel.bottom_radius = 0.17
			wheel.height = 0.12
			var w := _mesh_node(wheel, wheel_mat, Vector3(wx, 0.17, wz))
			w.rotation_degrees = Vector3(0, 0, 90)
			root.add_child(w)
	return root

## BBQ smoker trailer: big black barrel on a trailer frame, offset firebox,
## a tall chimney, and two wheels — reads as "Memphis BBQ rig" at a glance.
static func _build_smoker() -> Node3D:
	var root := Node3D.new()
	var steel := _mat(Color(0.08, 0.08, 0.09), 0.55, 0.35)
	# Trailer frame + hitch bar.
	var frame := BoxMesh.new()
	frame.size = Vector3(0.5, 0.06, 0.85)
	root.add_child(_mesh_node(frame, _mat(Color(0.2, 0.2, 0.22), 0.8, 0.2), Vector3(0, 0.22, 0.05)))
	var hitch := BoxMesh.new()
	hitch.size = Vector3(0.08, 0.06, 0.35)
	root.add_child(_mesh_node(hitch, _mat(Color(0.25, 0.25, 0.27), 0.8, 0.2), Vector3(0, 0.22, -0.5)))
	# Main barrel (horizontal along the trailer).
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.24
	barrel.bottom_radius = 0.24
	barrel.height = 0.7
	var b := _mesh_node(barrel, steel, Vector3(0, 0.48, 0.08))
	b.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(b)
	# Offset firebox at the back.
	var firebox := BoxMesh.new()
	firebox.size = Vector3(0.3, 0.3, 0.28)
	root.add_child(_mesh_node(firebox, steel, Vector3(0, 0.36, 0.52)))
	# Chimney with a red-hot lid handle accent.
	var chimney := CylinderMesh.new()
	chimney.top_radius = 0.05
	chimney.bottom_radius = 0.05
	chimney.height = 0.45
	root.add_child(_mesh_node(chimney, steel, Vector3(0, 0.85, 0.45)))
	var handle := BoxMesh.new()
	handle.size = Vector3(0.4, 0.04, 0.06)
	root.add_child(_mesh_node(handle, _mat(Color(0.65, 0.15, 0.1), 0.6), Vector3(0, 0.74, 0.08)))
	# Wheels.
	var wheel_mat := _mat(Color(0.05, 0.05, 0.06), 0.9)
	for wx in [-0.28, 0.28]:
		var wheel := CylinderMesh.new()
		wheel.top_radius = 0.14
		wheel.bottom_radius = 0.14
		wheel.height = 0.09
		var w := _mesh_node(wheel, wheel_mat, Vector3(wx, 0.14, 0.15))
		w.rotation_degrees = Vector3(0, 0, 90)
		root.add_child(w)
	return root

static func _build_money_stack() -> Node3D:
	var root := Node3D.new()
	for i in 3:
		var bill := BoxMesh.new()
		bill.size = Vector3(0.32, 0.04, 0.18)
		var mi := _mesh_node(bill, _mat(Color(0.45, 0.78, 0.38), 0.6), Vector3(0, 0.06 + i * 0.045, 0))
		mi.rotation_degrees = Vector3(0, float(i) * 8.0, 0)
		root.add_child(mi)
	return root

static func _build_money_bag() -> Node3D:
	var root := Node3D.new()
	var bag := SphereMesh.new()
	bag.radius = 0.22
	bag.height = 0.38
	root.add_child(_mesh_node(bag, _mat(Color(0.72, 0.55, 0.18), 0.75), Vector3(0, 0.22, 0)))
	var tie := BoxMesh.new()
	tie.size = Vector3(0.12, 0.06, 0.12)
	root.add_child(_mesh_node(tie, _mat(Color(0.35, 0.22, 0.08)), Vector3(0, 0.38, 0)))
	return root

static func _build_vault() -> Node3D:
	var root := Node3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.55, 0.55)
	root.add_child(_mesh_node(box, _mat(Color(0.28, 0.32, 0.38), 0.35, 0.55), Vector3(0, 0.28, 0)))
	var dial := CylinderMesh.new()
	dial.top_radius = 0.08
	dial.bottom_radius = 0.08
	dial.height = 0.04
	var d := _mesh_node(dial, _mat(Color(0.85, 0.72, 0.2), 0.3, 0.6), Vector3(0, 0.58, 0.22))
	d.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(d)
	return root

## Animate quadruped legs on meshes built by _build_tiger / _build_bear.
## `amount` 0 = idle, 1 = full stride.
static func quadruped_yaw(move: Vector2) -> float:
	if move.length_squared() < 0.0001:
		return 0.0
	# Meshes face -Z at yaw 0; add PI so the head leads the walk direction.
	return atan2(move.x, move.y) + PI

static func animate_quadruped(root: Node3D, phase: float, amount: float) -> void:
	if root == null or amount <= 0.01:
		return
	var swing := sin(phase) * 0.55 * amount
	for leg_name in ["LegFL", "LegFR", "LegBL", "LegBR"]:
		var leg := root.get_node_or_null(leg_name) as MeshInstance3D
		if leg == null:
			continue
		var front: bool = leg_name.contains("F")
		var phase_off := PI if front else 0.0
		leg.rotation.x = sin(phase + phase_off) * swing

static func _leg_node(pos: Vector3, color: Color, thick := 0.06, tall := 0.22) -> MeshInstance3D:
	var leg_mesh := CylinderMesh.new()
	leg_mesh.top_radius = thick
	leg_mesh.bottom_radius = thick * 0.85
	leg_mesh.height = tall
	var leg := _mesh_node(leg_mesh, _mat(color), pos + Vector3(0, tall * 0.5, 0))
	leg.name = "Leg"
	return leg

static func _build_tiger() -> Node3D:
	var root := Node3D.new()
	var orange := _mat(Color(0.92, 0.48, 0.12), 0.75)
	var stripe := _mat(Color(0.08, 0.05, 0.04), 0.95)
	# Slim body — noticeably smaller than the bear.
	var body := BoxMesh.new()
	body.size = Vector3(0.26, 0.16, 0.48)
	root.add_child(_mesh_node(body, orange, Vector3(0, 0.22, 0.0)))
	var head := BoxMesh.new()
	head.size = Vector3(0.16, 0.14, 0.18)
	root.add_child(_mesh_node(head, orange, Vector3(0, 0.28, -0.28)))
	# Vertical stripes along the body.
	for i in 5:
		var s := BoxMesh.new()
		s.size = Vector3(0.03, 0.14, 0.44)
		root.add_child(_mesh_node(s, stripe, Vector3(-0.1 + i * 0.05, 0.22, 0.0)))
	for i in 3:
		var hs := BoxMesh.new()
		hs.size = Vector3(0.025, 0.1, 0.06)
		root.add_child(_mesh_node(hs, stripe, Vector3(-0.06 + i * 0.06, 0.28, -0.26)))
	var tail := BoxMesh.new()
	tail.size = Vector3(0.04, 0.04, 0.16)
	var tail_n := _mesh_node(tail, orange, Vector3(0, 0.24, 0.26))
	tail_n.rotation.x = 0.2
	root.add_child(tail_n)
	var leg_defs := [
		["LegFL", Vector3(-0.1, 0.0, -0.14)],
		["LegFR", Vector3(0.1, 0.0, -0.14)],
		["LegBL", Vector3(-0.1, 0.0, 0.12)],
		["LegBR", Vector3(0.1, 0.0, 0.12)],
	]
	for def in leg_defs:
		var leg := _leg_node(def[1], Color(0.92, 0.48, 0.12), 0.045, 0.28)
		leg.name = def[0]
		root.add_child(leg)
	return root

static func _build_bear() -> Node3D:
	var root := Node3D.new()
	var brown := _mat(Color(0.4, 0.26, 0.14), 0.85)
	var body := BoxMesh.new()
	body.size = Vector3(0.5, 0.32, 0.56)
	root.add_child(_mesh_node(body, brown, Vector3(0, 0.32, 0.0)))
	var head := SphereMesh.new()
	head.radius = 0.17
	head.height = 0.28
	root.add_child(_mesh_node(head, brown, Vector3(0, 0.46, -0.32)))
	var snout := BoxMesh.new()
	snout.size = Vector3(0.11, 0.09, 0.1)
	root.add_child(_mesh_node(snout, _mat(Color(0.32, 0.2, 0.1)), Vector3(0, 0.42, -0.44)))
	var leg_defs := [
		["LegFL", Vector3(-0.18, 0.0, -0.17)],
		["LegFR", Vector3(0.18, 0.0, -0.17)],
		["LegBL", Vector3(-0.18, 0.0, 0.15)],
		["LegBR", Vector3(0.18, 0.0, 0.15)],
	]
	for def in leg_defs:
		var leg := _leg_node(def[1], Color(0.4, 0.26, 0.14), 0.08, 0.26)
		leg.name = def[0]
		root.add_child(leg)
	return root

static func _build_trash() -> Node3D:
	var root := Node3D.new()
	var pile := SphereMesh.new()
	pile.radius = 0.32
	pile.height = 0.44
	root.add_child(_mesh_node(pile, _mat(Color(0.28, 0.26, 0.22), 0.95), Vector3(0, 0.18, 0)))
	var bag := BoxMesh.new()
	bag.size = Vector3(0.3, 0.28, 0.28)
	var b := _mesh_node(bag, _mat(Color(0.1, 0.1, 0.12), 0.7), Vector3(0.18, 0.16, 0.1))
	b.rotation_degrees = Vector3(0, 25, 12)
	root.add_child(b)
	return root
