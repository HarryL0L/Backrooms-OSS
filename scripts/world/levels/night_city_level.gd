extends SideLevel
## The Blue Hour: an endless modern city stopped in the middle of a clear
## night. Every street lamp is on, thousands of windows are lit, the
## signals still cycle through green, yellow and red for nobody; no
## people, no cars, only the hum. You come out of a roof door onto a
## six-storey brick roof at a crossing, can walk down the fire stair in
## the alley to the crossing itself, and leave by the roof door or the
## building's street door (both back to the Backrooms). Everything past
## the barricades is the city to the horizon.
##
## The testbed of L.U.C.I.D. stage 3 (docs/LUCID.md): the roamable part is
## baked per vertex (tools/lucid/city_bake.gd: street lamps with shadows,
## a night and a dusk state with the sky through a gather and the moon,
## sky visibility, relightable slots), the backdrop is instanced boxes with
## procedural windows, analytic lamp pools in the ground and thousands of
## point-source lamps, all in real units under a phone camera filming at
## night (Lucid.night_camera). The blue is the real colour of a light-
## polluted moonlit sky under a white balance set by the street lamps and
## windows, plus the eye's mesopic shift. Plan: night_city_layout.gd;
## sizes and sources: assets/levels/night_city/SPEC.md.

const NAME := "Level 12.1 - The Blue Hour"
const INTRO := "Every light in the city is on. There is nobody left to have switched them on."
const NEXT := ""
const ENTRANCES := [{"kind": "wall", "biomes": ["CONCRETE", "LOBBY"], "floors": [2, 99], "look": "roof", "sign": "ROOF",
		"label": "Go up to the roof", "chance": 0.35}]

const DIR := "res://assets/levels/night_city/"
const LAYOUT := preload("res://scripts/world/levels/night_city_layout.gd")
const CITY := preload("res://shaders/lucid_city.gdshader")
const FACADE := preload("res://shaders/lucid_facade.gdshader")
const BLOCKS := preload("res://shaders/lucid_blocks.gdshader")
const GROUND := preload("res://shaders/lucid_ground.gdshader")
const POINTS := preload("res://shaders/lucid_points.gdshader")
const SKY := preload("res://shaders/lucid_sky.gdshader")
const STATE_A := "night"
const STATE_B := "dusk"
## The photo textures' linear means (detail averages 1) and roughness means.
const TEX_MEAN := {"asphalt": [Color(0.0936, 0.0844, 0.0645), 0.745], "concrete": [Color(0.4817, 0.4817, 0.4817), 0.516],
		"facade_concrete": [Color(0.609, 0.6162, 0.487), 0.495], "brick": [Color(0.4878, 0.2994, 0.1493), 0.595]}
## How much of the eye's night shift the picture shows (Camera.night_vision).
const NIGHT_VISION := 0.5
## The signal cycle (s): avenue green 0-30, yellow 30-34, all red 34-36,
## street green 36-56, yellow 56-60. Walk for the parallel crossing with
## the green, the hand flashing for the last 4 s of it (ITE / MUTCD style).
const CYCLE := 60.0
## A failing high pressure sodium lamp's cycle (s): on, the arc drops out
## as the lamp's voltage climbs, cools 45 s, restrikes dim and pinkish and
## warms up over 75 s.
const FAIL_ON := 80.0
const FAIL_OFF := 45.0
const FAIL_WARM := 75.0
const REAL_LIGHTS := 4

## Debug: the light state blend (0 night, 1 dusk); < 0 = the level's own (night).
static var force_blend := -1.0

var lay: RefCounted
var city: Node3D
var cam: Lucid.Camera
var mats := {}                  # name -> ShaderMaterial (baked surfaces)
var blend := 0.0
var clock := 0.0
var lamp_lvl := PackedFloat32Array()
var _block_mat: ShaderMaterial
var _ground_mat: ShaderMaterial
var _points_mat: ShaderMaterial
var _sky_mat: ShaderMaterial
var _lamp_mats: Array[ShaderMaterial] = []
var _sky: MeshInstance3D
var _moon: DirectionalLight3D
var _lights: Array[SpotLight3D] = []
var _light_lamp: Array[int] = []
var _light_t := 0.0
var _probes := []
var _fail_idx := -1
var _fail_t := 0.0
var _meter_spots := []
var _meter_i := 0
var _meter_ctx := {}
var _shape_meta := []
var _sounds := {}
var _aps: Array[AudioStreamPlayer3D] = []
var _buzz: AudioStreamPlayer3D
var _siren_t := 40.0
var _baked := false


func build(p_seed: int) -> void:
	seed_value = p_seed
	clock = float(p_seed % 600)
	_fail_t = float(p_seed % 97)
	cam = Lucid.night_camera()
	cam.night_vision = NIGHT_VISION
	lamp_lvl.resize(32)
	lamp_lvl.fill(1.0)
	_baked = ResourceLoader.exists(DIR + "bake/street.res") and ResourceLoader.exists(DIR + "bake/a.res")
	lay = LAYOUT.new()
	lay.build(not _baked)
	city = Node3D.new()
	city.name = "City"
	add_child(city)
	city.position = Vector3(0.0, LEVEL_Y, 0.0)
	_materials()
	_near()
	_collision()
	_backdrop()
	_lamps_real()
	_sky_dome()
	_load_probes()
	for l in lay.lamps:
		if l.get("failing", false):
			_fail_idx = l.idx
	fall_kill = 7.0
	environment = _environment()
	_build_audio()
	var roof: Transform3D = lay.spots.roof_door
	add_exit(Transform3D(roof.basis, city.to_global(roof.origin)), "none", "", {"label": "Go back down the stairs"})
	var door: Transform3D = lay.spots.street_door
	add_exit(Transform3D(door.basis, city.to_global(door.origin)), "none", "", {"label": "Go back inside"})
	_update(0.0)


# ---------------------------------------------------------------- materials ---

func _materials() -> void:
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	var st_a: Dictionary = Lucid.STATES[STATE_A]
	var st_b: Dictionary = Lucid.STATES[STATE_B]
	for name in lay.mats:
		var d: Dictionary = lay.mats[name]
		var sm := ShaderMaterial.new()
		sm.shader = FACADE if d.has("facade") else CITY
		sm.set_shader_parameter("albedo", (d.albedo as Color))
		sm.set_shader_parameter("roughness", d.get("rough", 0.7))
		sm.set_shader_parameter("specular", d.get("spec", 0.5))
		sm.set_shader_parameter("sky_gloss", d.get("gloss", 0.0))
		sm.set_shader_parameter("road_paint", d.get("paint", false))
		sm.set_shader_parameter("ground_origin", o)
		sm.set_shader_parameter("baked", _baked)
		sm.set_shader_parameter("const_light", Color(1, 1, 1) * Lucid.lux_to_engine(2.0))
		if d.has("tex"):
			var t: String = d.tex
			var dir := DIR + "textures/"
			sm.set_shader_parameter("albedo_tex", load(dir + t + "_diff.jpg"))
			sm.set_shader_parameter("rough_tex", load(dir + t + "_rough.jpg"))
			sm.set_shader_parameter("tex_mean", TEX_MEAN[t][0])
			sm.set_shader_parameter("rough_tex_mean", TEX_MEAN[t][1])
			sm.set_shader_parameter("uv_scale", d.get("uv", 2.0))
			if d.has("normal") and not low:
				sm.set_shader_parameter("normal_tex", load(dir + t + "_nor.jpg"))
				sm.set_shader_parameter("use_normal", true)
				sm.set_shader_parameter("normal_depth", d.normal)
		if d.has("emit"):
			var fx: Dictionary = Lucid.FIXTURES[d.emit]
			sm.set_shader_parameter("emit_nits", Lucid.fixture_rgb(fx) * Lucid.face_luminance(fx))
		if d.has("facade"):
			sm.set_shader_parameter("facade", d.facade)
			sm.set_shader_parameter("shop_band", d.get("shop", 0.0))
			sm.set_shader_parameter("win_top", d.get("top", 1000.0))
			_window_params(sm, st_a, st_b)
		mats[name] = sm
		_kit_mats.append(sm)


func _window_params(sm: ShaderMaterial, a: Dictionary, b: Dictionary) -> void:
	for k in [["win_office_rad", "window_office"], ["win_home_rad", "window_home"], ["win_shop_rad", "shopfront"]]:
		var fx: Dictionary = Lucid.FIXTURES[k[1]]
		sm.set_shader_parameter(k[0], Lucid.fixture_rgb(fx) * (Lucid.face_luminance(fx) / Lucid.UNIT_NITS))
	sm.set_shader_parameter("lit_a", a.windows)
	sm.set_shader_parameter("lit_b", b.windows)


## The baked tiles (or, without a bake, the plan's geometry lit flat).
func _near() -> void:
	for tile in ["street", "a"]:
		var mesh: ArrayMesh
		if _baked:
			mesh = load(DIR + "bake/" + tile + ".res")
		else:
			push_warning("night_city: no bake in %sbake/ (run tools/lucid/city_bake.tscn); lighting is flat" % DIR)
			mesh = ArrayMesh.new()
			for m in lay.tiles[tile]:
				var s: LucidCity.Surf = lay.tiles[tile][m]
				var arr := []
				arr.resize(Mesh.ARRAY_MAX)
				arr[Mesh.ARRAY_VERTEX] = s.v
				arr[Mesh.ARRAY_NORMAL] = s.n
				arr[Mesh.ARRAY_INDEX] = s.idx
				mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
				mesh.surface_set_name(mesh.get_surface_count() - 1, m)
		var mi := MeshInstance3D.new()
		mi.name = "Tile_" + tile
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		city.add_child(mi)
		for i in mesh.get_surface_count():
			var n := mesh.surface_get_name(i)
			if mats.has(n):
				mi.set_surface_override_material(i, mats[n])


func _collision() -> void:
	var body := StaticBody3D.new()
	body.name = "Collision"
	city.add_child(body)
	for c in lay.colliders:
		if not c.solid:
			continue
		_shape_meta.append(c.meta)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c.size
		cs.shape = bs
		cs.transform = c.xf
		body.add_child(cs)
	var gs := CollisionShape3D.new()
	var cp := ConcavePolygonShape3D.new()
	cp.set_faces(lay.ground)
	gs.shape = cp
	body.add_child(gs)


# ----------------------------------------------------------------- backdrop ---

func _backdrop() -> void:
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	# Buildings, in sectors (8 directions x near / far) so most are culled.
	_block_mat = ShaderMaterial.new()
	_block_mat.shader = BLOCKS
	_block_mat.set_shader_parameter("ground_y", LEVEL_Y)
	_window_params(_block_mat, Lucid.STATES[STATE_A], Lucid.STATES[STATE_B])
	_kit_mats.append(_block_mat)
	var box := LucidCity.unit_box()
	var blocks: Array = lay.blocks
	if low:
		# Potato / Low: past 900 m only the towers (the skyline stays).
		blocks = blocks.filter(func(e: Dictionary) -> bool:
			return Vector2(e.pos.x, e.pos.z).length() < 900.0 or e.size.y + e.pos.y > 80.0)
	for list in _sectors(blocks, 900.0).values():
		var mi := LucidCity.instance(LucidCity.block_multimesh(list, box), _block_mat, city)
		mi.name = "Blocks"
	# The ground beyond the crossing.
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = GROUND
	_ground_mat.set_shader_parameter("ground_y", LEVEL_Y)
	_ground_mat.set_shader_parameter("i_led", Lucid.light_engine(Lucid.FIXTURES.led_street_100w, LucidCity.AVENUE_LAMP.llf))
	_ground_mat.set_shader_parameter("i_na", Lucid.light_engine(Lucid.FIXTURES.sodium_hps_150w, LucidCity.STREET_LAMP.llf))
	_ground_mat.set_shader_parameter("asphalt", Color(0.094, 0.086, 0.068))
	_ground_mat.set_shader_parameter("walk", Color(0.3, 0.295, 0.28))
	_ground_mat.set_shader_parameter("e_spill", Lucid.fixture_rgb(Lucid.FIXTURES.shopfront) * Lucid.lux_to_engine(2.0))
	_kit_mats.append(_ground_mat)
	var plane := PlaneMesh.new()
	plane.size = Vector2(14000, 14000)
	var g := MeshInstance3D.new()
	g.mesh = plane
	g.material_override = _ground_mat
	g.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	g.position = Vector3(0, -0.03, 0)
	city.add_child(g)
	# Lamp models (pole, arm, head, lens) for the grid lamps within 320 m.
	var led_list := []
	var na_list := []
	for l in lay.lamp_models:
		var p: Vector3 = l.pole
		var h: Vector3 = l.pos
		var d := Vector3(h.x - p.x, 0.0, h.z - p.z).normalized()
		var xf := Transform3D(Basis(Vector3.UP, atan2(d.x, d.z)), p + Vector3(0, LucidCity.GRID.curb, 0))
		(na_list if l.street else led_list).append(xf)
	for spec in [[led_list, LucidCity.AVENUE_LAMP, "led_street_100w"], [na_list, LucidCity.STREET_LAMP, "sodium_hps_150w"]]:
		if (spec[0] as Array).is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _lamp_model(spec[1], spec[2])
		mm.instance_count = spec[0].size()
		for i in spec[0].size():
			mm.set_instance_transform(i, spec[0][i])
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		city.add_child(mi)
	# Point lights: lamps, beacons, signals, bridge necklaces.
	_points_mat = ShaderMaterial.new()
	_points_mat.shader = POINTS
	_points_mat.set_shader_parameter("cycle", CYCLE)
	_kit_mats.append(_points_mat)
	for list in _sectors(lay.points, 1e9).values():
		LucidCity.instance(LucidCity.point_multimesh(list), _points_mat, city)
	# Far-field lighting numbers for the blocks (worked out once).
	_block_mat.set_shader_parameter("e_street_led", _facade_light(true))
	_block_mat.set_shader_parameter("e_street_na", _facade_light(false))


## Splits instance entries ({pos, ...}) into 8 directions x (nearer /
## further than `ring`) for culling.
func _sectors(list: Array, ring: float) -> Dictionary:
	var out := {}
	for e in list:
		var p: Vector3 = e.pos
		var s := int(fposmod(atan2(p.z, p.x) / TAU * 8.0, 8.0)) + (8 if Vector2(p.x, p.z).length() > ring else 0)
		if not out.has(s):
			out[s] = []
		out[s].append(e)
	return out


## Vertical illuminance (E / pi, engine units) at the foot of a facade on
## an avenue (LED) or a street (sodium) from its lamp rows: the far field
## the backdrop's lower floors get.
func _facade_light(avenue: bool) -> Color:
	var fx: Dictionary = Lucid.FIXTURES.led_street_100w if avenue else Lucid.FIXTURES.sodium_hps_150w
	var c := Lucid.light_engine(fx, LucidCity.AVENUE_LAMP.llf if avenue else LucidCity.STREET_LAMP.llf)
	var m: float = fx.m
	var e := 0.0
	var p := Vector3(15.0, 4.0, 0.0) if avenue else Vector3(0.0, 4.0, 10.0)
	var nn := Vector3(-1, 0, 0) if avenue else Vector3(0, 0, -1)
	for k in range(-6, 7):
		for s in [-1.0, 1.0]:
			var lp := Vector3(s * 7.6, 10.0, 17.5 + 35.0 * k) if avenue else Vector3(25.0 + 30.0 * k, 8.0, s * 5.1)
			var d := lp - p
			var r2 := d.length_squared()
			var dn := d / sqrt(r2)
			var ce := maxf(-dn.y, 0.0)
			e += pow(ce, m) * maxf(nn.dot(dn), 0.0) / r2
	return c * e


func _lamp_model(spec: Dictionary, fx_name: String) -> ArrayMesh:
	var h: float = spec.h
	var arm: float = spec.arm
	var s := LucidCity.Surf.new()
	s.cyl(Vector3.ZERO, 0.11, h + 0.25, 6, h)
	s.box(Vector3(0, h + 0.2, arm * 0.5), Vector3(0.08, 0.08, arm), 4.0)
	s.box(Vector3(0, h + 0.08, arm + 0.1), Vector3(0.34, 0.15, 0.72), 2.0)
	var lens := LucidCity.Surf.new()
	lens.quad(Vector3(-0.13, h - 0.001, arm - 0.15), Vector3(0.26, 0, 0), Vector3(0, 0, 0.45), 1.0, Vector3.DOWN)
	var mesh := ArrayMesh.new()
	var lit := ShaderMaterial.new()
	lit.shader = CITY
	lit.set_shader_parameter("albedo", Color(0.25, 0.26, 0.26))
	lit.set_shader_parameter("baked", false)
	var fx: Dictionary = Lucid.FIXTURES[fx_name]
	lit.set_shader_parameter("const_light", Lucid.fixture_rgb(fx) * Lucid.lux_to_engine(5.0))
	var lm := ShaderMaterial.new()
	lm.shader = CITY
	lm.set_shader_parameter("albedo", Color(0.3, 0.3, 0.3))
	lm.set_shader_parameter("baked", false)
	lm.set_shader_parameter("emit_nits", Lucid.fixture_rgb(fx) * Lucid.face_luminance(fx))
	for pair in [[s, lit], [lens, lm]]:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pair[0].v
		arr[Mesh.ARRAY_NORMAL] = pair[0].n
		arr[Mesh.ARRAY_INDEX] = pair[0].idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, pair[1])
		_kit_mats.append(pair[1])
		_lamp_mats.append(pair[1])
	return mesh


func _sky_dome() -> void:
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = SKY
	_kit_mats.append(_sky_mat)
	var sm := SphereMesh.new()
	sm.radius = 7000.0
	sm.height = 14000.0
	sm.radial_segments = 32
	sm.rings = 16
	_sky = MeshInstance3D.new()
	_sky.mesh = sm
	_sky.material_override = _sky_mat
	_sky.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_sky.extra_cull_margin = 16384.0
	add_child(_sky)
	_moon = DirectionalLight3D.new()
	_moon.shadow_enabled = false
	_moon.light_specular = 1.0
	add_child(_moon)


## The nearest few lamps as real lights (their highlights on the damp
## street; they also light anything not baked, like other players).
func _lamps_real() -> void:
	var n := REAL_LIGHTS if not low else 2
	for i in n:
		var l := SpotLight3D.new()
		l.spot_range = 40.0
		l.spot_angle = 75.0
		l.spot_angle_attenuation = 0.6
		l.spot_attenuation = 2.0
		l.shadow_enabled = false
		l.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
		l.visible = false
		add_child(l)
		_lights.append(l)
		_light_lamp.append(-1)


func _load_probes() -> void:
	if not ResourceLoader.exists(DIR + "bake/probes.res"):
		return
	var r: Resource = load(DIR + "bake/probes.res")
	_probes = r.get_meta("grids", [])


## The natural part only (the blended states) of the probe light round p.
func _natural(p: Vector3) -> Color:
	return _probe(p, false)


## The baked light (E / pi, engine units) round p (level space), from the
## probe grids: lamps at their levels plus the blended states.
func _probe(p: Vector3, with_lamps := true) -> Color:
	for g in _probes:
		var rect: Rect2 = g.rect
		var fy: float = g.floor
		if p.y < fy - 1.0 or not rect.grow(1.0).has_point(Vector2(p.x, p.z)):
			continue
		if fy > 0.0 and p.y < fy - 0.5:
			continue
		var step: float = g.step
		var nx := ceili(rect.size.x / step) + 1
		var nz := ceili(rect.size.y / step) + 1
		var fx := clampf((p.x - rect.position.x) / step, 0.0, nx - 1.001)
		var fz := clampf((p.z - rect.position.y) / step, 0.0, nz - 1.001)
		var data: PackedFloat32Array = g.data
		var acc := Color(0, 0, 0)
		for dz in 2:
			for dx in 2:
				var w := (1.0 - absf(fx - floorf(fx) - dx)) * (1.0 - absf(fz - floorf(fz) - dz))
				var o := ((floori(fz) + dz) * nx + floori(fx) + dx) * 9
				var lamps := Color(data[o], data[o + 1], data[o + 2])
				var a := Color(data[o + 3], data[o + 4], data[o + 5])
				var b := Color(data[o + 6], data[o + 7], data[o + 8])
				acc += ((lamps if with_lamps else Color(0, 0, 0)) + a.lerp(b, blend)) * w
		return acc
	var s := Lucid.sky_illuminance(Lucid.STATES[STATE_A], Vector3.UP, 6)
	return s * (0.5 / (PI * Lucid.UNIT_NITS))


# -------------------------------------------------------------- environment ---

func _environment() -> Environment:
	var e := make_environment({"background": Color.BLACK, "fog_density": 0.0})
	e.fog_enabled = false
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	EnvironmentFactory.lucid_grade(e)
	e.tonemap_exposure = float(Settings.get_value("graphics/brightness"))
	# Veiling glare: 3 % of the frame's mean, which at night is the lamps'
	# and windows' light (warm-neutral).
	e.adjustment_enabled = true
	e.adjustment_color_correction = EnvironmentFactory.flare_lut(Color(0.0011, 0.001, 0.0009))
	e.glow_enabled = bool(Settings.get_value("graphics/bloom"))
	e.glow_intensity = 0.35
	e.glow_hdr_threshold = 1.0
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 0.6)
	e.set_glow_level(3, 0.25)
	e.ssao_enabled = false
	e.ssil_enabled = false
	e.sdfgi_enabled = false
	e.volumetric_fog_enabled = false
	return e


func camera_far() -> float:
	return 9000.0


func reverb() -> Dictionary:
	return {"room": 0.45, "damp": 0.65, "wet": 0.12}


func arrival() -> Transform3D:
	var t: Transform3D = lay.spots.arrival
	return Transform3D(t.basis, city.to_global(t.origin) if city else t.origin + Vector3(0, LEVEL_Y, 0))


func surface_at(p: Vector3) -> int:
	var q := p - Vector3(0.0, LEVEL_Y, 0.0)
	if q.x > 45.0 and q.x < 47.6 and q.z > 12.3 and q.z < 17.9 and q.y > 0.4:
		return Player.SURF_METAL
	return Player.SURF_CONCRETE


func albedo_at(p: Vector3, _n: Vector3) -> Color:
	var q := p - Vector3(0.0, LEVEL_Y, 0.0)
	return Color(0.09, 0.086, 0.07) if q.y < 0.1 else Color(0.3, 0.29, 0.28)


func light_at(p: Vector3) -> Color:
	var e := _probe(p - Vector3(0.0, LEVEL_Y, 0.0))
	var x := cam.shader_exposure()
	return Color(minf(e.r * x.r, 1.0), minf(e.g * x.g, 1.0), minf(e.b * x.b, 1.0))


func on_enter() -> void:
	player.can_climb = false
	_update(0.0)


func on_leave() -> void:
	Lucid.clear_level()


func _exit_tree() -> void:
	Lucid.clear_level()


func save_state() -> Dictionary:
	return {"clock": clock, "fail": _fail_t}


func load_state(d: Dictionary) -> void:
	clock = float(d.get("clock", clock))
	_fail_t = float(d.get("fail", _fail_t))


# ------------------------------------------------------------------ runtime ---

func _process(delta: float) -> void:
	_update(delta)


func _update(delta: float) -> void:
	if cam == null:
		return
	clock += delta
	blend = force_blend if force_blend >= 0.0 else 0.0
	var a: Dictionary = Lucid.STATES[STATE_A]
	var b: Dictionary = Lucid.STATES[STATE_B]
	_failing_lamp(delta)
	_signals()
	# The camera: meter, white balance, then everything that follows it.
	if player != null and player.camera != null:
		_meter(delta)
	var sky := LucidCity.push_sky(a, b, blend)
	var haze := lerpf(a.haze, b.haze, blend)
	Lucid.push_level(cam, blend, 1.0, (sky.horizon as Color) * Lucid.UNIT_NITS, haze)
	var e_up := Lucid.sky_illuminance(a, Vector3.UP, 8).lerp(Lucid.sky_illuminance(b, Vector3.UP, 8), blend) * (1.0 / (PI * Lucid.UNIT_NITS))
	var e_side := Lucid.sky_illuminance(a, Vector3.RIGHT, 8).lerp(Lucid.sky_illuminance(b, Vector3.RIGHT, 8), blend) * (1.0 / (PI * Lucid.UNIT_NITS))
	var ma := Lucid.kelvin_rgb(a.moon_k) * Lucid.lux_to_engine(a.moon_lux)
	var mb := Lucid.kelvin_rgb(b.moon_k) * Lucid.lux_to_engine(b.moon_lux)
	var moon_e := ma.lerp(mb, blend)
	var md := Lucid.sky_dir(a.moon_alt, a.moon_az)
	_block_mat.set_shader_parameter("e_sky_up", e_up)
	_block_mat.set_shader_parameter("e_sky_side", e_side)
	_block_mat.set_shader_parameter("e_moon", moon_e)
	_block_mat.set_shader_parameter("moon_dir", md)
	_ground_mat.set_shader_parameter("e_sky_up", e_up)
	_points_mat.set_shader_parameter("clock", clock)
	var su := Lucid.sky_uniforms(a)
	_sky_mat.set_shader_parameter("moon_dir", md)
	_sky_mat.set_shader_parameter("moon_rad", (su.moon as Color) * ((1.0 - blend) / Lucid.UNIT_NITS))
	_sky_mat.set_shader_parameter("moon_e", moon_e)
	_sky_mat.set_shader_parameter("stars", lerpf(a.stars, b.stars, blend))
	if player != null and player.camera != null:
		_sky.global_position = player.camera.global_position
	# The moon's highlight as a directional light.
	var mn := Lucid.light_node_cam(moon_e, cam)
	_moon.light_energy = mn[0]
	_moon.light_color = mn[1]
	_moon.visible = mn[0] > 0.0
	_moon.look_at_from_position(Vector3.ZERO, -md, Vector3.UP if absf(md.y) < 0.99 else Vector3.BACK)
	_real_lights(delta)


## Program exposure and auto white balance from nine spots across the view
## (one ray every frame): what each sees, in cd/m2 and colour: a baked
## surface (its albedo times the probe light there), the sky (the model),
## or the city beyond the colliders (its mean: windows, lamps, dark walls).
func _meter(delta: float) -> void:
	if _meter_spots.is_empty():
		_meter_spots.resize(9)
		_meter_spots.fill(null)
	var c := player.camera
	var gx := (_meter_i % 3) - 1
	var gy := (_meter_i / 3) - 1
	var dir := (-c.global_basis.z + c.global_basis.x * (gx * 0.45) + c.global_basis.y * (gy * 0.25)).normalized()
	var from := c.global_position
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * 400.0)
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	var col: Color
	if not hit.is_empty():
		# The lamps' light on that surface (unoccluded, at their levels)
		# plus the state's natural light there (probes).
		var p: Vector3 = hit.position - Vector3(0.0, LEVEL_Y, 0.0)
		var nn: Vector3 = hit.normal
		var si: int = hit.get("shape", -1)
		var meta: Dictionary = _shape_meta[si] if si >= 0 and si < _shape_meta.size() else {}
		var alb := 0.09 if p.y < 0.1 and nn.y > 0.7 else float(meta.get("albedo", 0.3))
		if nn.y > 0.7:
			alb = maxf(alb, 0.3) if p.y > 1.0 else alb
		if _meter_ctx.is_empty():
			_meter_ctx = LucidCity._context(lay.lamps, [STATE_A, STATE_B], null, 1)
		var e := LucidCity._lamps_open(_meter_ctx, p, nn) if p.y < 12.0 else Color(0, 0, 0)
		# (Lit windows are light sources: like a phone's matrix metering, it
		# exposes for the lit surfaces and lets the windows clip.)
		col = (e + _natural(p)) * (alb * Lucid.UNIT_NITS)
	elif dir.y < 0.06:
		col = Lucid.kelvin_rgb(3300.0) * 0.25
	else:
		var a: Dictionary = Lucid.STATES[STATE_A]
		var b: Dictionary = Lucid.STATES[STATE_B]
		col = Lucid.sky_nits(a, dir).lerp(Lucid.sky_nits(b, dir), blend)
	_meter_spots[_meter_i] = col
	_meter_i = (_meter_i + 1) % 9
	var logsum := 0.0
	var n := 0
	var peak := 0.0
	var rgb := Color(0, 0, 0)
	for s in _meter_spots:
		if s == null:
			continue
		var l := maxf(Lucid.lum(s), 1e-5)
		logsum += log(l)
		peak = maxf(peak, l)
		rgb += s
		n += 1
	if n == 0:
		return
	cam.meter(exp(logsum / n), delta, peak)
	if OS.get_environment("LUCID_DEBUG") != "" and Engine.get_process_frames() % 60 == 0:
		print("lucid: avg %.3f peak %.3f cd/m2 -> EV %.2f (t %.4f iso %d) wb %d K" % [exp(logsum / n), peak, cam.ev100, cam.shutter, cam.iso, cam.wb_kelvin])
	# The colour of what it sees -> CCT (McCamy 1992) -> partial AWB.
	cam.balance(_cct(rgb), delta)
	if n == 9:
		cam.settle()


static func _cct(c: Color) -> float:
	var x := 0.4124 * c.r + 0.3576 * c.g + 0.1805 * c.b
	var y := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var z := 0.0193 * c.r + 0.1192 * c.g + 0.9505 * c.b
	var s := x + y + z
	if s <= 1e-9:
		return 5500.0
	var cx := x / s
	var cy := y / s
	var nn := (cx - 0.3320) / (0.1858 - cy)
	return clampf(449.0 * nn * nn * nn + 3525.0 * nn * nn + 6823.3 * nn + 5520.33, 1700.0, 15000.0)


## The failing sodium lamp: on, out, cooling, a dim pinkish restrike,
## warming up to orange. Its slot level dims its baked pool exactly.
func _failing_lamp(delta: float) -> void:
	if _fail_idx < 0:
		return
	_fail_t = fposmod(_fail_t + delta, FAIL_ON + FAIL_OFF + FAIL_WARM)
	var t := _fail_t
	var lvl := 1.0
	var tint := Color(1, 1, 1)
	var was := lamp_lvl[_fail_idx]
	if t < FAIL_ON:
		# The last seconds before it drops out: unsteady.
		if t > FAIL_ON - 4.0:
			lvl = 0.75 + 0.25 * sin(t * 37.0) * sin(t * 13.0)
	elif t < FAIL_ON + FAIL_OFF:
		lvl = 0.0
	else:
		var k := (t - FAIL_ON - FAIL_OFF) / FAIL_WARM
		lvl = 0.04 + 0.96 * smoothstep(0.0, 1.0, k)
		# Warm-up: the xenon and mercury glow first (bluish pink), the
		# sodium's orange comes in as it heats.
		tint = Color(0.75, 0.85, 1.6).lerp(Color(1, 1, 1), smoothstep(0.1, 0.8, k))
		if was <= 0.001 and _buzz:
			_play_once("restrike", _buzz.global_position, -8.0)
	lamp_lvl[_fail_idx] = lvl
	if absf(was - lvl) > 0.0005:
		_push_levels()
	var fx: Dictionary = Lucid.FIXTURES.sodium_hps_150w
	var e := Lucid.fixture_rgb(fx) * Lucid.face_luminance(fx) * lvl
	mats.lens_na_failing.set_shader_parameter("emit_nits", Color(e.r * tint.r, e.g * tint.g, e.b * tint.b))
	if _buzz:
		_buzz.volume_db = -22.0 + 10.0 * lvl if lvl > 0.01 else -80.0


func _push_levels() -> void:
	var arr := PackedVector4Array()
	for i in 8:
		arr.append(Vector4(lamp_lvl[i * 4], lamp_lvl[i * 4 + 1], lamp_lvl[i * 4 + 2], lamp_lvl[i * 4 + 3]))
	for n in mats:
		(mats[n] as ShaderMaterial).set_shader_parameter("lamp_lvl", arr)


## Signal phase at time t (s into the cycle) for a head set.
static func signal_state(s: float, set_name: String) -> String:
	match set_name:
		"avenue":
			return "g" if s < 30.0 else ("y" if s < 34.0 else "r")
		"street":
			return "r" if s < 36.0 else ("g" if s < 56.0 else "y")
		"ped_a":
			# Crossing the avenue: with the street's green.
			if s >= 36.0 and s < 48.0:
				return "walk"
			if s >= 48.0 and s < 56.0:
				return "flash"
			return "hand"
		"ped_s":
			if s < 22.0:
				return "walk"
			if s < 30.0:
				return "flash"
			return "hand"
	return ""


func _signals() -> void:
	var s := fposmod(clock, CYCLE)
	var cols := {"r": Lucid.FIXTURES.signal_red, "y": Lucid.FIXTURES.signal_yellow, "g": Lucid.FIXTURES.signal_green}
	for set_name in ["avenue", "street"]:
		var on := signal_state(s, set_name)
		for c in ["r", "y", "g"]:
			var fx: Dictionary = cols[c]
			# 300 mm lens: luminance = I / area.
			var lum: float = fx.peak_cd / (PI * 0.15 * 0.15) if c == on else 0.0
			mats["sig_%s_%s" % [set_name, c]].set_shader_parameter("emit_nits", Lucid.fixture_rgb(fx) * lum)
	for set_name in ["ped_a", "ped_s"]:
		var st := signal_state(s, set_name)
		var hand_on := st == "hand" or (st == "flash" and fmod(s, 1.0) < 0.5)
		var hfx: Dictionary = Lucid.FIXTURES.ped_hand
		var wfx: Dictionary = Lucid.FIXTURES.ped_walk
		mats[set_name + "_hand"].set_shader_parameter("emit_nits", Lucid.fixture_rgb(hfx) * (hfx.luminance if hand_on else 0.0))
		mats[set_name + "_walk"].set_shader_parameter("emit_nits", Lucid.fixture_rgb(wfx) * (wfx.luminance if st == "walk" else 0.0))
	# Accessible signal sounds: a locator tick every second, a rapid tick
	# while a crossing has its walk.
	var walking := signal_state(s, "ped_a") == "walk" or signal_state(s, "ped_s") == "walk"
	for p in _aps:
		var want: AudioStream = _sounds.get("aps_walk" if walking else "aps_locate")
		if want and p.stream != want:
			p.stream = want
			p.play()


func _real_lights(delta: float) -> void:
	if player == null:
		return
	_light_t -= delta
	var me := player.global_position - Vector3(0.0, LEVEL_Y, 0.0)
	if _light_t <= 0.0:
		_light_t = 0.4
		var cand := []
		for l in lay.lamps:
			if int(l.get("idx", -1)) < 0 or l.get("bulb", false):
				continue
			cand.append([(l.pos as Vector3).distance_squared_to(me), int(l.idx)])
		cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		for i in _lights.size():
			_light_lamp[i] = cand[i][1] if i < cand.size() else -1
	for i in _lights.size():
		var idx := _light_lamp[i]
		var l := _lights[i]
		if idx < 0:
			l.visible = false
			continue
		var lamp: Dictionary = {}
		for x in lay.lamps:
			if int(x.get("idx", -1)) == idx:
				lamp = x
				break
		var c := Lucid.light_engine(Lucid.FIXTURES[lamp.fx], float(lamp.llf)) * lamp_lvl[idx]
		var ln := Lucid.light_node_cam(c, cam)
		l.light_energy = ln[0]
		l.light_color = ln[1]
		l.global_position = city.to_global(lamp.pos - Vector3(0, 0.05, 0))
		l.visible = ln[0] > 0.0


# -------------------------------------------------------------------- audio ---

func _build_audio() -> void:
	for n: String in ["city_hum", "wind_high", "siren_far", "lamp_buzz", "aps_locate", "aps_walk", "restrike"]:
		var path := DIR + "audio/" + n + ".ogg"
		if ResourceLoader.exists(path):
			_sounds[n] = load(path)
	for n in ["aps_locate", "aps_walk"]:
		if _sounds.has(n):
			var st: AudioStreamOggVorbis = (_sounds[n] as AudioStreamOggVorbis).duplicate()
			st.loop = true
			_sounds[n] = st
	if _sounds.has("city_hum"):
		add_loop(_sounds.city_hum, Vector3.INF, -9.0)
	if _sounds.has("wind_high"):
		var w := add_loop(_sounds.wind_high, city.to_global(Vector3(30, 30, 25)), -6.0, {"unit_size": 30.0, "max_distance": 120.0})
		w.name = "wind"
	if _sounds.has("lamp_buzz"):
		_buzz = add_loop(_sounds.lamp_buzz, city.to_global(lay.FAILING), -18.0, {"unit_size": 2.5, "max_distance": 30.0}) as AudioStreamPlayer3D
	for h in lay.heads:
		if h.set != "ped_a":
			continue
		var p := AudioStreamPlayer3D.new()
		p.bus = "World"
		p.unit_size = 2.0
		p.max_distance = 25.0
		p.volume_db = -14.0
		p.stream = _sounds.get("aps_locate")
		add_child(p)
		p.global_position = city.to_global(h.pos)
		if p.stream:
			p.play()
		_aps.append(p)


func _play_once(n: String, at: Vector3, db: float) -> void:
	if not _sounds.has(n):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[n]
	p.bus = "World"
	p.volume_db = db
	p.unit_size = 6.0
	p.max_distance = 400.0
	add_child(p)
	p.global_position = at
	p.play()
	p.finished.connect(p.queue_free)


func _physics_process(delta: float) -> void:
	# Now and then a siren far off across the city, never closer.
	_siren_t -= delta
	if _siren_t <= 0.0:
		var rng := RandomNumberGenerator.new()
		rng.seed = hash(int(clock * 10.0)) ^ seed_value
		_siren_t = rng.randf_range(70.0, 160.0)
		var a := rng.randf() * TAU
		if player:
			_play_once("siren_far", player.global_position + Vector3(cos(a), 0.05, sin(a)) * 300.0, -4.0)


# --------------------------------------------------------------------- shots ---

func _view(at: Vector3, yaw_deg: float, pitch_deg := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	return Transform3D(b, at + Vector3(0.0, LEVEL_Y, 0.0))


## Yaw 0 looks north (-Z), 90 west, 180 south, 270 east.
func shots() -> Array:
	return [
		{"name": "arrival", "transform": arrival(), "wait": 3.0},
		{"name": "roof_edge", "transform": _view(Vector3(15.9, 22.5, 10.9), 45.0, -22.0), "wait": 4.0},
		{"name": "roof_skyline", "transform": _view(Vector3(20.0, 22.5, 20.0), 70.0, 4.0), "wait": 4.0},
		{"name": "roof_north", "transform": _view(Vector3(25.0, 22.5, 12.0), 5.0, 2.0), "wait": 4.0},
		{"name": "roof_tank", "transform": _view(Vector3(31.0, 22.5, 24.0), 220.0, 8.0), "wait": 4.0},
		{"name": "stair", "transform": _view(Vector3(46.9, 11.7, 13.0), 20.0, -10.0), "wait": 4.0},
		{"name": "alley", "transform": _view(Vector3(48.0, 0.15, 30.0), 10.0, 3.0), "wait": 4.0},
		{"name": "street_corner", "transform": _view(Vector3(12.0, 0.15, 12.0), 0.0, 4.0), "wait": 4.0},
		{"name": "avenue_south", "transform": _view(Vector3(3.0, 0.0, -20.0), 180.0, 2.0), "wait": 4.0},
		{"name": "street_west", "transform": _view(Vector3(30.0, 0.15, 8.0), 90.0, 3.0), "wait": 4.0},
		{"name": "plaza_tower", "transform": _view(Vector3(-20.0, 0.15, -15.0), 45.0, 30.0), "wait": 4.0},
		{"name": "failing_lamp", "transform": _view(Vector3(40.0, 0.15, 8.5), 280.0, 12.0), "wait": 4.0},
	]


## The harness's film: out of the roof door, to the parapet over the
## crossing, along the roof to the stair, down two storeys of it, then the
## crossing from the street.
func film() -> void:
	var t := arrival()
	player.teleport(t.origin, _yaw_of(t))
	await get_tree().create_timer(2.0).timeout
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	await _ride([o + Vector3(28, 24.1, 30), o + Vector3(20, 24.1, 20), o + Vector3(17, 24.1, 13)], deg_to_rad(55.0), 7.0, -0.35)
	await _ride([o + Vector3(17.2, 24.1, 13.2)], deg_to_rad(100.0), 3.0, 0.05)
	await _ride([o + Vector3(30, 24.1, 15), o + Vector3(43, 24.1, 13.1), o + Vector3(46.0, 24.1, 13.0)], deg_to_rad(250.0), 6.0, -0.1)
	await _ride([o + Vector3(46.9, 24.1, 13.4), o + Vector3(46.9, 22.4, 16.4), o + Vector3(46.3, 22.4, 17.2),
			o + Vector3(45.7, 22.4, 16.4), o + Vector3(45.7, 20.6, 13.8)], deg_to_rad(10.0), 8.0, -0.2)
	await _ride([o + Vector3(30, 1.75, 8.0), o + Vector3(10, 1.75, 4.0), o + Vector3(0, 1.75, 0)], deg_to_rad(90.0), 9.0, 0.05)
	await _ride([o + Vector3(0, 1.75, -0.5)], deg_to_rad(180.0), 4.0, 0.08)
	await _ride([o + Vector3(0, 1.75, -1.0)], deg_to_rad(330.0), 4.0, 0.15)


func _ride(eyes: Array, yaw: float, time: float, pitch: float) -> void:
	var path := PackedVector3Array([player.camera.global_position])
	for e in eyes:
		path.append(e)
	var st := {"done": false}
	player.ride(path, yaw, time, func() -> void: st.done = true, pitch)
	while not st.done and is_inside_tree():
		await get_tree().process_frame
