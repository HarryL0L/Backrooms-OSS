extends Node3D
# Concept mockup of a possible "Dead Mall" level (night, after closing).
# Run: godot --path . res://_test/mall_concept.tscn -- <out.png>

const L := 64.0        # corridor length
const W := 14.0        # corridor width (wall to wall)
const H1 := 4.6        # ground floor height
const H2 := 9.2        # upper floor ceiling
const VOID := 6.0      # width of the open atrium in the middle

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.seed = 4
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.01, 0.015, 0.03)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.30, 0.36)
	env.ambient_light_energy = 0.5
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.7
	env.glow_bloom = 0.05
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.11, 0.13)
	env.fog_density = 0.018
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var floor_m := _m(Color(0.78, 0.72, 0.62), 0.12)       # polished terrazzo
	var wall_m := _m(Color(0.86, 0.83, 0.78), 0.8)
	var ceil_m := _m(Color(0.7, 0.68, 0.64), 0.9)
	var trim_m := _m(Color(0.42, 0.38, 0.33), 0.5)
	var glass_m := _m(Color(0.55, 0.65, 0.7, 0.18), 0.05)
	glass_m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	var dark_m := _m(Color(0.03, 0.03, 0.035), 0.4)
	var shutter_m := _m(Color(0.55, 0.56, 0.57), 0.45, 0.6)
	shutter_m.albedo_texture = _stripes()
	shutter_m.uv1_scale = Vector3(1, 14, 1)
	var plant_m := _m(Color(0.16, 0.30, 0.14), 0.8)
	var pot_m := _m(Color(0.5, 0.36, 0.26), 0.7)

	# Ground floor, side walls, upper floor slabs either side of the atrium.
	_box(floor_m, Vector3(W, 0.2, L), Vector3(0, -0.1, -L * 0.5))
	for sx in [-1.0, 1.0]:
		_box(wall_m, Vector3(0.3, H2, L), Vector3(sx * W * 0.5, H2 * 0.5, -L * 0.5))
		var slab_w := (W - VOID) * 0.5
		var slab_x: float = sx * (VOID * 0.5 + slab_w * 0.5)
		_box(floor_m, Vector3(slab_w, 0.35, L), Vector3(slab_x, H1, -L * 0.5))
		_box(ceil_m, Vector3(slab_w, 0.05, L), Vector3(slab_x, H1 - 0.2, -L * 0.5))
		_box(trim_m, Vector3(0.12, 0.5, L), Vector3(sx * VOID * 0.5, H1 - 0.05, -L * 0.5))
		_box(glass_m, Vector3(0.04, 1.0, L), Vector3(sx * VOID * 0.5, H1 + 0.7, -L * 0.5))
		_box(trim_m, Vector3(0.08, 0.06, L), Vector3(sx * VOID * 0.5, H1 + 1.22, -L * 0.5))
		_box(ceil_m, Vector3(slab_w, 0.2, L), Vector3(slab_x, H2, -L * 0.5))
		# Shopfronts, both floors.
		for lvl in 2:
			var y0 := 0.0 if lvl == 0 else H1 + 0.18
			var z := -2.0
			while z > -L + 6.0:
				var w := rng.randf_range(7.0, 10.0)
				var kind := rng.randi() % 3
				var fx: float = sx * (W * 0.5 - 0.22)
				var zc := z - w * 0.5
				_box(trim_m, Vector3(0.3, 0.6, w), Vector3(fx - sx * 0.08, y0 + 3.6, zc))   # sign band
				_box(trim_m, Vector3(0.2, 3.4, 0.3), Vector3(fx - sx * 0.05, y0 + 1.7, z))   # pilaster
				if kind == 0:
					# Closed roller shutter.
					_box(shutter_m, Vector3(0.08, 3.2, w - 0.6), Vector3(fx, y0 + 1.6, zc))
				else:
					# Dark shop behind glass.
					_box(dark_m, Vector3(0.05, 3.3, w - 0.6), Vector3(fx + sx * 0.6, y0 + 1.65, zc))
					_box(glass_m, Vector3(0.03, 3.3, w - 0.6), Vector3(fx, y0 + 1.65, zc))
				# A few signs still glowing, most dead.
				if rng.randf() < 0.35:
					var sc: Color = [Color(1.0, 0.35, 0.6), Color(0.3, 0.9, 0.85), Color(1.0, 0.75, 0.35)][rng.randi() % 3]
					var sm := _m(sc * 0.2, 0.5)
					sm.emission_enabled = true
					sm.emission = sc
					sm.emission_energy_multiplier = 2.2
					_box(sm, Vector3(0.06, 0.32, w * 0.45), Vector3(fx - sx * 0.25, y0 + 3.6, zc))
				z -= w + 0.4

	# Skylight roof over the atrium: dark night through the glass.
	var sky_m := _m(Color(0.02, 0.04, 0.09), 0.1)
	sky_m.emission_enabled = true
	sky_m.emission = Color(0.03, 0.06, 0.14)
	_box(sky_m, Vector3(VOID, 0.05, L), Vector3(0, H2 + 1.6, -L * 0.5))
	for i in range(0, int(L), 4):
		_box(trim_m, Vector3(VOID + 0.4, 0.18, 0.18), Vector3(0, H2 + 1.5, -float(i)))

	# Dry fountain, planters, benches down the middle.
	var ring := MeshInstance3D.new()
	var cy := CylinderMesh.new()
	cy.top_radius = 2.6
	cy.bottom_radius = 2.7
	cy.height = 0.5
	ring.mesh = cy
	ring.material_override = _m(Color(0.62, 0.6, 0.56), 0.4)
	ring.position = Vector3(0, 0.25, -30)
	add_child(ring)
	_box(_m(Color(0.25, 0.27, 0.27), 0.6), Vector3(4.2, 0.05, 4.2), Vector3(0, 0.45, -30))
	for z in [-12.0, -20.0, -40.0, -48.0]:
		for sx in [-1.0, 1.0]:
			_box(pot_m, Vector3(1.1, 0.7, 1.1), Vector3(sx * 1.6, 0.35, z))
			var leaf := MeshInstance3D.new()
			var sp := SphereMesh.new()
			sp.radius = 0.75
			sp.height = 1.6
			leaf.mesh = sp
			leaf.material_override = plant_m
			leaf.position = Vector3(sx * 1.6, 1.4, z)
			add_child(leaf)
		_box(trim_m, Vector3(0.5, 0.45, 2.2), Vector3(0, 0.22, z - 3.5))

	# Escalator to the upper floor (stopped).
	var esc := Node3D.new()
	esc.position = Vector3(-1.2, 0, -54)
	add_child(esc)
	for i in 22:
		_box(_m(Color(0.35, 0.36, 0.38), 0.4, 0.7), Vector3(1.2, 0.21, 0.4), Vector3(0, 0.1 + i * 0.21, 0.4 * i), esc)
	_box(trim_m, Vector3(0.12, 1.0, 10.0), Vector3(-0.66, 2.6, 4.2), esc).rotation.x = -0.48
	_box(trim_m, Vector3(0.12, 1.0, 10.0), Vector3(0.66, 2.6, 4.2), esc).rotation.x = -0.48

	# Lights: rows of dim downlights, many off; a couple flickering-bright.
	for z in range(-3, -int(L), -6):
		for sx in [-1.0, 1.0]:
			for lvl in 2:
				if rng.randf() < 0.45:
					continue
				var y := H1 - 0.3 if lvl == 0 else H2 - 0.3
				var x: float = sx * (VOID * 0.5 + (W - VOID) * 0.25)
				var l := OmniLight3D.new()
				l.light_color = Color(1.0, 0.86, 0.66)
				l.light_energy = rng.randf_range(0.5, 1.4)
				l.omni_range = 7.0
				l.position = Vector3(x, y, float(z))
				add_child(l)
				var lm := _m(Color(1, 0.9, 0.7), 0.5)
				lm.emission_enabled = true
				lm.emission = Color(1.0, 0.88, 0.68)
				lm.emission_energy_multiplier = 3.0
				_box(lm, Vector3(0.5, 0.04, 0.5), Vector3(x, y + 0.27, float(z)))
	# Moonlight down the atrium.
	var moon := DirectionalLight3D.new()
	moon.light_color = Color(0.45, 0.55, 0.85)
	moon.light_energy = 0.0
	moon.rotation = Vector3(-1.2, 0.3, 0)
	moon.shadow_enabled = true
	add_child(moon)

	# Polished floor: reflections from a probe down the corridor.
	var probe := ReflectionProbe.new()
	probe.size = Vector3(W, H2 + 2.0, L)
	probe.position = Vector3(0, H2 * 0.5, -L * 0.5)
	probe.box_projection = true
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.intensity = 0.8
	add_child(probe)
	var cam := Camera3D.new()
	cam.fov = 70
	cam.position = Vector3(3.6, 1.7, -4.0)
	cam.rotation = Vector3(0.08, 0.12, 0)
	add_child(cam)
	cam.current = true
	await get_tree().process_frame
	for i in 30:
		await get_tree().process_frame
	var args := OS.get_cmdline_user_args()
	get_viewport().get_texture().get_image().save_png(args[0] if args.size() > 0 else "user://mall_concept.png")
	get_tree().quit()


func _m(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


func _box(m: Material, size: Vector3, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var b := BoxMesh.new()
	b.size = size
	mi.mesh = b
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi


func _stripes() -> Texture2D:
	var img := Image.create(4, 8, false, Image.FORMAT_RGB8)
	for y in 8:
		for x in 4:
			var v := 0.55 if y < 6 else 0.25
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)
