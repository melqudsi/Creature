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
		"bbq_grill":
			return _build_bbq_grill()
		"cart":
			return _build_cart()
		"mata_bus":
			return _build_mata_bus()
		"smoker":
			return _build_smoker()
		"charger":
			return _build_charger()
		"truck":
			return _build_truck()
		"atm":
			return _build_atm()
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
		"big_house":
			return _build_big_house()
		"campus":
			return _build_campus_hall()
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
		"human":
			return build_human(random_human_params())
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

static func _build_propane(tank_color: Color = Color(0.82, 0.06, 0.04)) -> Node3D:
	var root := Node3D.new()
	var tank_mat := _mat(tank_color, 0.5, 0.2)
	var tank_mesh := CylinderMesh.new()
	tank_mesh.top_radius = 0.22
	tank_mesh.bottom_radius = 0.22
	tank_mesh.height = 0.5
	root.add_child(_mesh_node(tank_mesh, tank_mat, Vector3(0, 0.28, 0)))
	var dome := SphereMesh.new()
	dome.radius = 0.22
	dome.height = 0.3
	root.add_child(_mesh_node(dome, tank_mat, Vector3(0, 0.53, 0)))
	var valve := CylinderMesh.new()
	valve.top_radius = 0.06
	valve.bottom_radius = 0.06
	valve.height = 0.12
	root.add_child(_mesh_node(valve, _mat(Color(0.5, 0.1, 0.08), 0.6, 0.3), Vector3(0, 0.66, 0)))
	return root

static func _build_bbq_grill() -> Node3D:
	var root := Node3D.new()
	var steel := _mat(Color(0.06, 0.06, 0.065), 0.55, 0.25)
	var hot := _mat(Color(0.78, 0.18, 0.06), 0.7)
	var bowl := BoxMesh.new()
	bowl.size = Vector3(0.75, 0.28, 0.48)
	root.add_child(_mesh_node(bowl, steel, Vector3(0, 0.42, 0)))
	var lid := BoxMesh.new()
	lid.size = Vector3(0.7, 0.16, 0.43)
	root.add_child(_mesh_node(lid, steel, Vector3(0, 0.64, -0.03)))
	var handle := BoxMesh.new()
	handle.size = Vector3(0.38, 0.05, 0.05)
	root.add_child(_mesh_node(handle, hot, Vector3(0, 0.76, -0.16)))
	for x in [-0.24, 0.0, 0.24]:
		var grate := BoxMesh.new()
		grate.size = Vector3(0.04, 0.03, 0.44)
		root.add_child(_mesh_node(grate, _mat(Color(0.78, 0.78, 0.75), 0.35, 0.35), Vector3(x, 0.58, 0)))
	for x in [-0.3, 0.3]:
		for z in [-0.18, 0.18]:
			var leg := CylinderMesh.new()
			leg.top_radius = 0.025
			leg.bottom_radius = 0.025
			leg.height = 0.42
			root.add_child(_mesh_node(leg, steel, Vector3(x, 0.21, z)))
	var tank := _build_propane()
	tank.name = "AttachedPropaneTank"
	tank.scale = Vector3(0.52, 0.52, 0.52)
	tank.position = Vector3(0.52, 0.04, 0.02)
	root.add_child(tank)
	var shelf := BoxMesh.new()
	shelf.size = Vector3(0.22, 0.04, 0.38)
	root.add_child(_mesh_node(shelf, _mat(Color(0.18, 0.18, 0.17), 0.7), Vector3(-0.52, 0.48, 0)))
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
	# No random rotation: houses are snapped to face south or east by the
	# spawner so the door (and Big House windows) always face the camera.
	return root

## Upgraded safe house: two stories, an American gable roof, a front door, and
## FOUR dark windows on the front face. Windows glow gold (with light beams)
## per stored vault — see WorldObject._apply_window_glow().
static func _build_big_house() -> Node3D:
	var root := Node3D.new()
	var wall := _mat(Color.from_hsv(randf_range(0.07, 0.13), 0.2, 0.86), 0.88)
	var trim := _mat(Color(0.95, 0.94, 0.9), 0.85)
	var body := BoxMesh.new()
	body.size = Vector3(1.55, 1.6, 1.3)
	root.add_child(_mesh_node(body, wall, Vector3(0, 0.8, 0)))
	# Gable roof: triangular prism, ridge running along X so the slants face
	# the camera-visible south side.
	var roof := PrismMesh.new()
	roof.size = Vector3(1.5, 0.72, 1.8)
	var roof_mi := _mesh_node(roof, _mat(Color(0.38, 0.11, 0.08), 0.75), Vector3(0, 1.96, 0))
	roof_mi.rotation.y = PI * 0.5
	root.add_child(roof_mi)
	# Eave board under the roof line.
	var eave := BoxMesh.new()
	eave.size = Vector3(1.7, 0.08, 1.45)
	root.add_child(_mesh_node(eave, trim, Vector3(0, 1.62, 0)))
	var chimney := BoxMesh.new()
	chimney.size = Vector3(0.2, 0.6, 0.2)
	root.add_child(_mesh_node(chimney, _mat(Color(0.22, 0.12, 0.1)), Vector3(0.5, 2.1, 0.3)))
	# Front door (front face is -Z; the spawner rotates it toward the camera).
	var door := BoxMesh.new()
	door.size = Vector3(0.3, 0.52, 0.05)
	root.add_child(_mesh_node(door, _mat(Color(0.24, 0.13, 0.07)), Vector3(0, 0.26, -0.66)))
	var knob := SphereMesh.new()
	knob.radius = 0.025
	knob.height = 0.05
	root.add_child(_mesh_node(knob, _mat(Color(0.85, 0.7, 0.3), 0.3, 0.8), Vector3(0.1, 0.28, -0.69)))
	# Four vault-indicator windows: 2 per story, flanking the door column.
	var windows: Array = []
	var slots := [
		Vector2(-0.45, 0.62), Vector2(0.45, 0.62),
		Vector2(-0.45, 1.22), Vector2(0.45, 1.22),
	]
	for i in slots.size():
		var s: Vector2 = slots[i]
		var win := Node3D.new()
		win.name = "Window%d" % i
		win.position = Vector3(s.x, s.y, -0.66)
		var frame := BoxMesh.new()
		frame.size = Vector3(0.36, 0.42, 0.03)
		win.add_child(_mesh_node(frame, trim, Vector3(0, 0, 0.005)))
		var pane_mesh := BoxMesh.new()
		pane_mesh.size = Vector3(0.3, 0.36, 0.04)
		var pane := _mesh_node(pane_mesh, big_house_window_material(false), Vector3.ZERO)
		pane.name = "Pane"
		pane.set_meta("no_fade", true)
		win.add_child(pane)
		# Golden light beam shining out of a lit window (hidden until a vault
		# is stored). Angled slightly downward like light spilling out.
		var beam_mesh := BoxMesh.new()
		beam_mesh.size = Vector3(0.3, 0.34, 1.2)
		var beam := _mesh_node(beam_mesh, _beam_material(), Vector3(0, -0.12, -0.62))
		beam.name = "Beam"
		beam.rotation.x = -0.22
		beam.visible = false
		beam.set_meta("no_fade", true)
		win.add_child(beam)
		root.add_child(win)
		windows.append(win)
	root.set_meta("bh_windows", windows)
	return root

static func big_house_window_material(lit: bool) -> StandardMaterial3D:
	if lit:
		var m := _mat(Color(1.0, 0.85, 0.32), 0.35)
		m.emission_enabled = true
		m.emission = Color(1.0, 0.74, 0.18)
		m.emission_energy_multiplier = 1.8
		return m
	# Dark, slightly reflective glass.
	return _mat(Color(0.07, 0.09, 0.13), 0.25, 0.3)

static func _beam_material() -> StandardMaterial3D:
	var m := _mat(Color(1.0, 0.82, 0.28, 0.34), 0.2)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.emission_enabled = true
	m.emission = Color(1.0, 0.78, 0.22)
	m.emission_energy_multiplier = 1.4
	return m

## University of Memphis hall/dorm: multi-story red-brick block with limestone
## trim, rows of window panes, a flat parapet roof, and a columned entrance —
## reads as campus architecture, not a suburban house.
static func _build_campus_hall() -> Node3D:
	var root := Node3D.new()
	var brick := _mat(Color(0.52, 0.26, 0.18), 0.9)
	var limestone := _mat(Color(0.83, 0.8, 0.72), 0.85)
	var glass := _mat(Color(0.16, 0.22, 0.32), 0.25, 0.25)
	var h := randf_range(1.5, 1.9)
	var body := BoxMesh.new()
	body.size = Vector3(1.55, h, 1.2)
	root.add_child(_mesh_node(body, brick, Vector3(0, h * 0.5, 0)))
	# Limestone base course + parapet cap.
	var base_band := BoxMesh.new()
	base_band.size = Vector3(1.62, 0.16, 1.27)
	root.add_child(_mesh_node(base_band, limestone, Vector3(0, 0.08, 0)))
	var parapet := BoxMesh.new()
	parapet.size = Vector3(1.62, 0.12, 1.27)
	root.add_child(_mesh_node(parapet, limestone, Vector3(0, h + 0.06, 0)))
	# Window rows on the front and back faces (slightly proud of the brick).
	var rows := 2 if h < 1.7 else 3
	for r in rows:
		var wy := 0.42 + float(r) * ((h - 0.6) / float(maxi(rows - 1, 1)))
		for c in 4:
			var wx := -0.57 + float(c) * 0.38
			for side in [-1.0, 1.0]:
				var pane := BoxMesh.new()
				pane.size = Vector3(0.22, 0.3, 0.03)
				root.add_child(_mesh_node(pane, glass, Vector3(wx, wy, side * 0.605)))
	# Columned entrance: two limestone columns + a small pediment on -Z.
	for side in [-1.0, 1.0]:
		var col := CylinderMesh.new()
		col.top_radius = 0.045
		col.bottom_radius = 0.05
		col.height = 0.5
		root.add_child(_mesh_node(col, limestone, Vector3(side * 0.2, 0.25, -0.68)))
	var pediment := BoxMesh.new()
	pediment.size = Vector3(0.56, 0.1, 0.2)
	root.add_child(_mesh_node(pediment, limestone, Vector3(0, 0.55, -0.66)))
	var door := BoxMesh.new()
	door.size = Vector3(0.26, 0.4, 0.04)
	root.add_child(_mesh_node(door, _mat(Color(0.12, 0.24, 0.45), 0.5), Vector3(0, 0.2, -0.61)))
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

static func _build_charger() -> Node3D:
	var root := Node3D.new()
	var body_mat := _mat(Color(0.08, 0.08, 0.1), 0.32, 0.45)
	var trim_mat := _mat(Color(0.55, 0.08, 0.06), 0.42, 0.2)
	var glass_mat := _mat(Color(0.04, 0.09, 0.13), 0.2, 0.5)
	var body := BoxMesh.new()
	body.size = Vector3(0.68, 0.24, 1.22)
	root.add_child(_mesh_node(body, body_mat, Vector3(0, 0.24, 0)))
	var hood := BoxMesh.new()
	hood.size = Vector3(0.66, 0.08, 0.44)
	root.add_child(_mesh_node(hood, trim_mat, Vector3(0, 0.38, 0.32)))
	var cabin := BoxMesh.new()
	cabin.size = Vector3(0.54, 0.18, 0.4)
	root.add_child(_mesh_node(cabin, glass_mat, Vector3(0, 0.47, -0.13)))
	var windshield := BoxMesh.new()
	windshield.size = Vector3(0.52, 0.055, 0.28)
	var ws := _mesh_node(windshield, glass_mat, Vector3(0, 0.5, 0.12))
	ws.rotation.x = 0.48
	root.add_child(ws)
	var rear := BoxMesh.new()
	rear.size = Vector3(0.7, 0.08, 0.25)
	root.add_child(_mesh_node(rear, trim_mat, Vector3(0, 0.36, -0.46)))
	var tag := BoxMesh.new()
	tag.size = Vector3(0.26, 0.09, 0.025)
	root.add_child(_mesh_node(tag, _mat(Color(0.95, 0.9, 0.62), 0.75), Vector3(0, 0.29, -0.625)))
	var wheel_mat := _mat(Color(0.025, 0.025, 0.03), 0.85)
	for wx in [-0.36, 0.36]:
		for wz in [-0.38, 0.4]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.14
			wheel.bottom_radius = 0.14
			wheel.height = 0.1
			var w := _mesh_node(wheel, wheel_mat, Vector3(wx, 0.14, wz))
			w.rotation_degrees = Vector3(0, 0, 90)
			root.add_child(w)
	return root

## Pickup truck: cab up front, open bed in back sized so two vaults fit inside
## (carried vaults render IN the bed — see Creature.update_carried_display).
## Bigger than the Altima/Charger, smaller than a MATA bus.
static func _build_truck() -> Node3D:
	var root := Node3D.new()
	var paint := _mat(Color(0.55, 0.35, 0.12), 0.4, 0.35)   # work-truck brown
	var dark := _mat(Color(0.16, 0.14, 0.12), 0.6, 0.2)
	var glass := _mat(Color(0.1, 0.15, 0.2), 0.2, 0.4)
	# Chassis running the full length.
	var chassis := BoxMesh.new()
	chassis.size = Vector3(0.78, 0.22, 1.8)
	root.add_child(_mesh_node(chassis, paint, Vector3(0, 0.24, 0)))
	# Cab at the front (+Z is forward for vehicle meshes).
	var cab := BoxMesh.new()
	cab.size = Vector3(0.72, 0.32, 0.55)
	root.add_child(_mesh_node(cab, paint, Vector3(0, 0.5, 0.55)))
	var windshield := BoxMesh.new()
	windshield.size = Vector3(0.6, 0.2, 0.06)
	root.add_child(_mesh_node(windshield, glass, Vector3(0, 0.54, 0.85)))
	# Open bed: floor + three low walls (rear stays visually open-ish with a
	# shorter tailgate) so cargo inside reads clearly.
	var bed_floor := BoxMesh.new()
	bed_floor.size = Vector3(0.72, 0.05, 1.1)
	root.add_child(_mesh_node(bed_floor, dark, Vector3(0, 0.36, -0.32)))
	for side in [-1.0, 1.0]:
		var wall := BoxMesh.new()
		wall.size = Vector3(0.05, 0.22, 1.1)
		root.add_child(_mesh_node(wall, paint, Vector3(side * 0.365, 0.46, -0.32)))
	var tailgate := BoxMesh.new()
	tailgate.size = Vector3(0.72, 0.18, 0.05)
	root.add_child(_mesh_node(tailgate, paint, Vector3(0, 0.44, -0.87)))
	var bed_front := BoxMesh.new()
	bed_front.size = Vector3(0.72, 0.22, 0.05)
	root.add_child(_mesh_node(bed_front, paint, Vector3(0, 0.46, 0.24)))
	# Wheels — chunkier than a sedan's.
	var wheel_mat := _mat(Color(0.05, 0.05, 0.06), 0.9)
	for wx in [-0.4, 0.4]:
		for wz in [-0.58, 0.62]:
			var wheel := CylinderMesh.new()
			wheel.top_radius = 0.17
			wheel.bottom_radius = 0.17
			wheel.height = 0.12
			var w := _mesh_node(wheel, wheel_mat, Vector3(wx, 0.17, wz))
			w.rotation_degrees = Vector3(0, 0, 90)
			root.add_child(w)
	return root

## ATM kiosk: freestanding cash machine. Not shapeshiftable — ram it with any
## vehicle and it bursts open (3 money bags), then reseeds the next day.
static func _build_atm() -> Node3D:
	var root := Node3D.new()
	var shell := _mat(Color(0.16, 0.32, 0.5), 0.45, 0.3)
	var face := _mat(Color(0.75, 0.78, 0.8), 0.5, 0.2)
	# Kiosk body with a slightly wider base plinth.
	var base := BoxMesh.new()
	base.size = Vector3(0.5, 0.12, 0.42)
	root.add_child(_mesh_node(base, _mat(Color(0.25, 0.26, 0.28), 0.8), Vector3(0, 0.06, 0)))
	var body := BoxMesh.new()
	body.size = Vector3(0.42, 0.75, 0.34)
	root.add_child(_mesh_node(body, shell, Vector3(0, 0.5, 0)))
	# Angled top hood.
	var hood := BoxMesh.new()
	hood.size = Vector3(0.44, 0.1, 0.38)
	root.add_child(_mesh_node(hood, shell, Vector3(0, 0.9, 0)))
	# "ATM" sign printed on the hood band, above the screen (not a billboard —
	# it reads like real signage on the kiosk face).
	var atm_sign := Label3D.new()
	atm_sign.text = "ATM"
	atm_sign.font_size = 44
	atm_sign.pixel_size = 0.004
	atm_sign.modulate = Color(1.0, 0.95, 0.55)
	atm_sign.outline_size = 10
	atm_sign.outline_modulate = Color(0.04, 0.09, 0.16)
	atm_sign.position = Vector3(0, 0.9, 0.2)
	root.add_child(atm_sign)
	# Screen + keypad + cash slot on the front face (+Z).
	var screen := BoxMesh.new()
	screen.size = Vector3(0.26, 0.2, 0.03)
	root.add_child(_mesh_node(screen, _mat(Color(0.15, 0.85, 0.55), 0.25, 0.0), Vector3(0, 0.68, 0.18)))
	var keypad := BoxMesh.new()
	keypad.size = Vector3(0.26, 0.12, 0.03)
	root.add_child(_mesh_node(keypad, face, Vector3(0, 0.48, 0.18)))
	var slot := BoxMesh.new()
	slot.size = Vector3(0.3, 0.05, 0.03)
	root.add_child(_mesh_node(slot, _mat(Color(0.08, 0.08, 0.1), 0.6), Vector3(0, 0.3, 0.18)))
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
	var steel := _mat(Color(0.28, 0.32, 0.38), 0.35, 0.55)
	var brass := _mat(Color(0.85, 0.72, 0.2), 0.3, 0.6)
	var box := BoxMesh.new()
	box.size = Vector3(0.55, 0.55, 0.55)
	root.add_child(_mesh_node(box, steel, Vector3(0, 0.28, 0)))
	# Door slab standing proud of the front face, with a brass frame line.
	var door := BoxMesh.new()
	door.size = Vector3(0.42, 0.42, 0.04)
	root.add_child(_mesh_node(door, _mat(Color(0.22, 0.26, 0.32), 0.35, 0.6), Vector3(0, 0.28, 0.29)))
	# Round handle wheel you'd spin to open it: brass ring + hub + 4 spokes.
	var ring := TorusMesh.new()
	ring.inner_radius = 0.085
	ring.outer_radius = 0.115
	var r := _mesh_node(ring, brass, Vector3(0, 0.28, 0.33))
	r.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(r)
	var hub := CylinderMesh.new()
	hub.top_radius = 0.035
	hub.bottom_radius = 0.035
	hub.height = 0.07
	var hb := _mesh_node(hub, brass, Vector3(0, 0.28, 0.33))
	hb.rotation_degrees = Vector3(90, 0, 0)
	root.add_child(hb)
	for i in 4:
		var spoke := BoxMesh.new()
		spoke.size = Vector3(0.2, 0.025, 0.025)
		var s := _mesh_node(spoke, brass, Vector3(0, 0.28, 0.33))
		s.rotation_degrees = Vector3(0, 0, 45.0 * float(i))
		root.add_child(s)
	# Small combination dial up on top, off to the side of the wheel.
	var dial := CylinderMesh.new()
	dial.top_radius = 0.06
	dial.bottom_radius = 0.06
	dial.height = 0.035
	var d := _mesh_node(dial, brass, Vector3(0.17, 0.45, 0.3))
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

# ---------------------------------------------------------------------------
# Humans (Slice 9): parameterized so seeded NPCs come in randomized variations.
# Bipeds face -Z at yaw 0 (same convention as the quadrupeds / quadruped_yaw).
# ---------------------------------------------------------------------------

const HUMAN_SKIN_TONES: Array = [
	Color(0.94, 0.80, 0.68), Color(0.87, 0.68, 0.52), Color(0.72, 0.52, 0.36),
	Color(0.55, 0.38, 0.26), Color(0.42, 0.28, 0.18),
]
const HUMAN_SHIRT_COLORS: Array = [
	Color(0.85, 0.2, 0.2), Color(0.2, 0.4, 0.85), Color(0.15, 0.6, 0.3),
	Color(0.9, 0.75, 0.15), Color(0.6, 0.25, 0.7), Color(0.9, 0.5, 0.15),
	Color(0.92, 0.92, 0.9), Color(0.15, 0.15, 0.18), Color(0.95, 0.55, 0.75),
]
const HUMAN_PANTS_COLORS: Array = [
	Color(0.2, 0.28, 0.48), Color(0.12, 0.12, 0.14), Color(0.62, 0.55, 0.4),
	Color(0.35, 0.35, 0.38), Color(0.3, 0.2, 0.14),
]
const HUMAN_SHOE_COLORS: Array = [
	Color(0.92, 0.92, 0.92), Color(0.1, 0.1, 0.12), Color(0.75, 0.15, 0.15),
	Color(0.25, 0.3, 0.55),
]
const HUMAN_HAIR_COLORS: Array = [
	Color(0.08, 0.06, 0.05), Color(0.3, 0.18, 0.08), Color(0.78, 0.62, 0.28),
	Color(0.5, 0.2, 0.1),
]

static func random_human_params() -> Dictionary:
	var female := randf() < 0.5
	return {
		"female": female,
		# Roughly a third of the women hit the town in a crop top + short skirt.
		"skimpy": female and randf() < 0.35,
		"skin": HUMAN_SKIN_TONES.pick_random(),
		"shirt": HUMAN_SHIRT_COLORS.pick_random(),
		"pants": HUMAN_PANTS_COLORS.pick_random(),
		"shoes": HUMAN_SHOE_COLORS.pick_random(),
		"hair": HUMAN_HAIR_COLORS.pick_random(),
	}

## Limb pivot: a Node3D at the joint (hip/shoulder) whose children hang below,
## so rotation.x swings the whole limb naturally (walk cycle / panic wave).
static func _limb(pivot_pos: Vector3, length: float, thick: float, mat: StandardMaterial3D) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = pivot_pos
	var seg := CylinderMesh.new()
	seg.top_radius = thick
	seg.bottom_radius = thick * 0.85
	seg.height = length
	pivot.add_child(_mesh_node(seg, mat, Vector3(0, -length * 0.5, 0)))
	return pivot

static func build_human(p: Dictionary) -> Node3D:
	var root := Node3D.new()
	var female: bool = p.get("female", false)
	var skimpy: bool = p.get("skimpy", false)
	var skin := _mat(p.get("skin", HUMAN_SKIN_TONES[0]) as Color, 0.85)
	var shirt := _mat(p.get("shirt", HUMAN_SHIRT_COLORS[0]) as Color, 0.9)
	var pants := _mat(p.get("pants", HUMAN_PANTS_COLORS[0]) as Color, 0.9)
	var shoes := _mat(p.get("shoes", HUMAN_SHOE_COLORS[0]) as Color, 0.7)
	var hair := _mat(p.get("hair", HUMAN_HAIR_COLORS[0]) as Color, 0.95)

	var hip_y := 0.34
	var shoulder_y := 0.60
	var torso_w := 0.20 if female else 0.26

	# Legs pivot at the hip. Skimpy outfit = bare legs, otherwise pants-colored.
	var leg_mat := skin if skimpy else pants
	for side in [-1.0, 1.0]:
		var leg := _limb(Vector3(side * 0.06, hip_y, 0), 0.30, 0.038, leg_mat)
		leg.name = "LegL" if side < 0.0 else "LegR"
		var shoe := BoxMesh.new()
		shoe.size = Vector3(0.07, 0.045, 0.11)
		leg.add_child(_mesh_node(shoe, shoes, Vector3(0, -0.315, -0.015)))
		root.add_child(leg)

	# Torso. Skimpy = bare midriff + crop top + short skirt; otherwise one shirt.
	if skimpy:
		var midriff := BoxMesh.new()
		midriff.size = Vector3(torso_w * 0.9, 0.10, 0.12)
		root.add_child(_mesh_node(midriff, skin, Vector3(0, hip_y + 0.05, 0)))
		var crop := BoxMesh.new()
		crop.size = Vector3(torso_w, 0.15, 0.13)
		root.add_child(_mesh_node(crop, shirt, Vector3(0, hip_y + 0.185, 0)))
		var skirt := BoxMesh.new()
		skirt.size = Vector3(torso_w + 0.06, 0.09, 0.17)
		root.add_child(_mesh_node(skirt, pants, Vector3(0, hip_y - 0.03, 0)))
	else:
		var torso := BoxMesh.new()
		torso.size = Vector3(torso_w, 0.26, 0.13)
		root.add_child(_mesh_node(torso, shirt, Vector3(0, hip_y + 0.13, 0)))

	# Arms pivot at the shoulder (sleeve + skin hand).
	for side in [-1.0, 1.0]:
		var arm := _limb(Vector3(side * (torso_w * 0.5 + 0.035), shoulder_y, 0), 0.26, 0.032,
			skin if skimpy else shirt)
		arm.name = "ArmL" if side < 0.0 else "ArmR"
		var hand := SphereMesh.new()
		hand.radius = 0.034
		hand.height = 0.068
		arm.add_child(_mesh_node(hand, skin, Vector3(0, -0.27, 0)))
		root.add_child(arm)

	# Head + nose (nose marks the -Z facing side).
	var head := SphereMesh.new()
	head.radius = 0.085
	head.height = 0.17
	root.add_child(_mesh_node(head, skin, Vector3(0, 0.71, 0)))
	var nose := BoxMesh.new()
	nose.size = Vector3(0.025, 0.03, 0.03)
	root.add_child(_mesh_node(nose, skin, Vector3(0, 0.71, -0.09)))

	# Hair: shared male cut (short cap) vs shared female cut (cap + long back).
	var cap := SphereMesh.new()
	cap.radius = 0.09
	cap.height = 0.1
	root.add_child(_mesh_node(cap, hair, Vector3(0, 0.755, 0.008)))
	if female:
		var mane := BoxMesh.new()
		mane.size = Vector3(0.15, 0.2, 0.05)
		root.add_child(_mesh_node(mane, hair, Vector3(0, 0.64, 0.08)))
	return root

## Walk / panic animation for the biped rig built above.
## amount 0..1 scales the swing; panic raises both arms and waves them.
static func animate_biped(root: Node3D, phase: float, amount: float, panic := false) -> void:
	if root == null:
		return
	var swing := sin(phase) * 0.7 * amount
	for limb_name in ["LegL", "LegR", "ArmL", "ArmR"]:
		var limb := root.get_node_or_null(limb_name) as Node3D
		if limb == null:
			continue
		var left: bool = limb_name.ends_with("L")
		var is_arm: bool = limb_name.begins_with("Arm")
		if is_arm and panic:
			# Arms straight up, waving side to side in alternating phase.
			limb.rotation.x = PI * 0.95
			limb.rotation.z = sin(phase * 1.6 + (0.0 if left else PI)) * 0.3
			continue
		limb.rotation.z = 0.0
		# Opposite legs swing together; arms counter-swing their own side's leg.
		var flip := 1.0 if left else -1.0
		limb.rotation.x = swing * flip * (-0.65 if is_arm else 1.0)

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
