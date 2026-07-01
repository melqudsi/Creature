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
		"cone":
			return _build_cone()
		"building":
			return _build_building()
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
