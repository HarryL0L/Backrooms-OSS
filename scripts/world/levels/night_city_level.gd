extends SideLevel
## The Blue Hour: an endless modern city stopped in the middle of a stormy
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
## an overcast and a dusk state with the sky through a gather, sky
## visibility, relightable slots), the backdrop is instanced boxes with
## procedural windows, analytic lamp pools in the ground and thousands of
## point-source lamps, all in real units under a phone camera filming at
## night (Lucid.night_camera). A thunderstorm (LucidStorm): an overcast
## lit orange-grey from below by the city, the tower tops lost in its
## scud, rain that comes in heavy bursts, lightning far off with its
## thunder. Plan: night_city_layout.gd; sizes and sources:
## assets/levels/night_city/SPEC.md.

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
## The baked light states (tools/lucid/city_bake.gd bakes these two;
## "night", the clear moonlit sky, is in Lucid.STATES too).
const STATE_A := "overcast"
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
## Lights used nearest-first fade out over this many metres before the
## next nearest takes their place (_fade_weights).
const FADE_BAND := 6.0
## Stage 4: the street heads' lens luminance (engine units), for their
## analytic reflections (the same as the lenses drawn).
var _lens_led := Lucid.fixture_rgb(Lucid.FIXTURES.led_street_100w) * (Lucid.face_luminance(Lucid.FIXTURES.led_street_100w) / Lucid.UNIT_NITS)
var _lens_na := Lucid.fixture_rgb(Lucid.FIXTURES.sodium_hps_150w) * (Lucid.face_luminance(Lucid.FIXTURES.sodium_hps_150w) / Lucid.UNIT_NITS)
## Reflection probes (LucidProbe), level space: centre, box (lo, hi), in
## the order a surface looks for the box it is in: the alley, the roof,
## the crossing, the avenue north and south, the street east and west. A
## box's walls are the building lines; where the street runs on, its end
## is far off (the street seen down its length is far away).
const PROBES := [[Vector3(48, 1.7, 28), Vector3(45, 0, 10), Vector3(51, 23, 46)],
		[Vector3(30, LAYOUT.A_ROOF + 1.7, 25), Vector3(15, LAYOUT.A_ROOF, 10), Vector3(45, 60, 40)],
		[Vector3(0, 1.7, 0), Vector3(-15, 0, -10), Vector3(15, 30, 10)],
		[Vector3(0, 1.7, -35), Vector3(-15, 0, -400), Vector3(15, 30, -10)],
		[Vector3(0, 1.7, 35), Vector3(-15, 0, 10), Vector3(15, 30, 400)],
		[Vector3(40, 1.7, 0), Vector3(15, 0, -10), Vector3(400, 30, 10)],
		[Vector3(-40, 1.7, 0), Vector3(-400, 0, -10), Vector3(-15, 30, 10)]]
## The box a probe projects onto, where it differs from the one that
## selects it: the crossing is open four ways (its streets run on 400 m).
const PROBE_PROJECT := {2: [Vector3(-400, 0, -400), Vector3(400, 30, 400)]}
## Probes projected onto two crossing canyons (lucid_plus_dir: the
## selecting box's x and z extents are the avenue's and the street's
## building lines), so the corner blocks' walls are where they stand.
const PROBE_PLUS := [2]
## The near tiles' ground (level XZ: the crossing's road and sidewalks to
## the next building lines, the corner blocks): the far ground has a hole
## here. Under them, 3 cm below the road, a phone's depth test let it
## through, a frame at a time, over the whole road (its 14 km triangles'
## depth is interpolated with too little precision): the road's probe
## reflections, signals and rings went out and came back as you walked.
const NEAR_GROUND := Rect2(-95.0, -70.0, 190.0, 140.0)
var probe_bytes := 0
var probe_ms := 0
var _sig_key := ""

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
var _light_cand: Array[Dictionary] = []
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
## Rain (LucidRain, docs/LUCID.md "Rain"): it never stops raining in the
## Blue Hour, harder in the storm's bursts (Settings > Rain turns it off).
var _rain: LucidRain
var _rain_on := false
var _rain_t := 0.0
var _cam_prev := Vector3.INF
var _cam_vel := Vector3.ZERO
var _rain_snd: AudioStreamPlayer
var _rain_db := 0.0
var _rain_nodes: Array[Node] = []
var _rain_heads := []
## The storm (LucidStorm, docs/LUCID.md "The storm"): the cloud deck, the
## bursts, the lightning, the thunder.
var _storm: LucidStorm
var _wind: Node
var _haze := 0.0
## Scale reference (QA only): grey 1.75 m people where proportions are
## judged, in debug builds with QA_FIGURES=1 in the environment (never in
## the shipped level). Level space (y: on what), facing (yaw, degrees; 0
## north, 90 west).
const QA_SPOTS := {"lamp_av": [Vector3(10.7, 0.15, 18.3), 200.0], "lamp_st": [Vector3(25.6, 0.15, 7.3), 160.0],
		"door": [Vector3(14.55, 0.15, 33.6), 270.0], "shop": [Vector3(14.0, 0.15, 27.5), 90.0],
		"landing": [Vector3(46.6, 7.8, 13.0), 300.0], "corner": [Vector3(11.0, 0.15, 9.0), 150.0],
		"cross_av": [Vector3(4.0, 0.0, 8.1), 90.0], "cross_st": [Vector3(12.1, 0.0, 3.0), 0.0],
		"parapet": [Vector3(20.0, 21.0, 10.75), 180.0], "bulkhead": [Vector3(33.4, 21.0, 34.4), 120.0],
		"shelter": [Vector3(-12.2, 0.15, -34.0), 270.0], "alley": [Vector3(48.5, 0.15, 24.0), 20.0],
		"hydrant": [Vector3(10.9, 0.15, 21.4), 250.0]}
var _qa_bodies: Array[EntityBody] = []


func build(p_seed: int) -> void:
	seed_value = p_seed
	clock = float(p_seed % 600)
	_fail_t = float(p_seed % 97)
	cam = Lucid.night_camera()
	cam.night_vision = NIGHT_VISION
	_baked = ResourceLoader.exists(DIR + "bake/street.res") and ResourceLoader.exists(DIR + "bake/a.res")
	lay = LAYOUT.new()
	lay.build(not _baked)
	# One level per lamp (the bake's 32 relightable slots are the first;
	# the real lights may pick any of the crossing's lamps).
	lamp_lvl.resize(maxi(32, lay.lamps.size()))
	lamp_lvl.fill(1.0)
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
	_build_storm()
	_load_probes()
	if _baked:
		_capture_probes.call_deferred()
	for l in lay.lamps:
		if l.get("failing", false):
			_fail_idx = l.idx
	# The lamps' levels from the start (the shaders' default is 0: every
	# switchable head's share of the light was missing until the failing
	# head first flickered, a minute or more in, and then came on at once).
	_push_levels()
	fall_kill = 7.0
	environment = _environment()
	_build_audio()
	_rain_settings()
	Settings.changed.connect(_rain_settings)
	Settings.changed.connect(_storm_settings)
	_storm_settings()
	_qa_figures()
	var roof: Transform3D = lay.spots.roof_door
	add_exit(Transform3D(roof.basis, city.to_global(roof.origin)), "none", "", {"label": "Go back down the stairs"})
	var door: Transform3D = lay.spots.street_door
	add_exit(Transform3D(door.basis, city.to_global(door.origin)), "none", "", {"label": "Go back inside"})
	_update(0.0)


# ---------------------------------------------------------------- materials ---

## Sets a shader parameter, a Color as a plain Vector3. (Godot converts a
## Color given to a vec3 / vec4 uniform from sRGB to linear: a measured
## albedo of 0.30 arrived as 0.073 and a lens of 36 000 cd/m2 as 10^15.
## None of the city's uniforms are sRGB colours.)
static func _sp(m: ShaderMaterial, key: String, v: Variant) -> void:
	if v is Color:
		var c: Color = v
		m.set_shader_parameter(key, Vector3(c.r, c.g, c.b))
	else:
		m.set_shader_parameter(key, v)


func _materials() -> void:
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	var st_a: Dictionary = Lucid.STATES[STATE_A]
	var st_b: Dictionary = Lucid.STATES[STATE_B]
	for name in lay.mats:
		var d: Dictionary = lay.mats[name]
		var sm := ShaderMaterial.new()
		sm.shader = FACADE if d.has("facade") else CITY
		_sp(sm, "albedo", (d.albedo as Color))
		_sp(sm, "roughness", d.get("rough", 0.7))
		# Stage 4: F0, wetness after rain, what it mirrors.
		_sp(sm, "f0", d.get("f0", 0.04))
		_sp(sm, "wet", d.get("wet", 0.0))
		_sp(sm, "puddles", d.get("puddles", 0.0))
		_sp(sm, "gutters", d.get("gutters", false))
		_sp(sm, "reflect_env", float(d.get("wet", 0.0)) > 0.0)
		_sp(sm, "lamp_refl", d.get("lamps", false))
		_sp(sm, "analytic_emitter", String(name).begins_with("lens_") or String(name).begins_with("sig_"))
		_sp(sm, "lens_led", _lens_led)
		_sp(sm, "lens_na", _lens_na)
		_sp(sm, "road_paint", d.get("paint", false))
		_sp(sm, "untile", d.get("untile", false))
		if float(d.get("wet", 0.0)) > 0.0:
			_rain_covers(sm)
		_sp(sm, "ground_origin", o)
		_sp(sm, "baked", _baked)
		_sp(sm, "const_light", Color(1, 1, 1) * Lucid.lux_to_engine(2.0))
		if d.has("tex"):
			var t: String = d.tex
			var dir := DIR + "textures/"
			_sp(sm, "albedo_tex", load(dir + t + "_diff.jpg"))
			_sp(sm, "rough_tex", load(dir + t + "_rough.jpg"))
			_sp(sm, "tex_mean", TEX_MEAN[t][0])
			_sp(sm, "rough_tex_mean", TEX_MEAN[t][1])
			_sp(sm, "uv_scale", d.get("uv", 2.0))
			if d.has("normal") and not low:
				_sp(sm, "normal_tex", load(dir + t + "_nor.jpg"))
				_sp(sm, "use_normal", true)
				_sp(sm, "normal_depth", d.normal)
		if d.has("emit"):
			var fx: Dictionary = Lucid.FIXTURES[d.emit]
			_sp(sm, "emit_nits", Lucid.fixture_rgb(fx) * Lucid.face_luminance(fx))
		if d.has("facade"):
			_sp(sm, "facade", d.facade)
			_sp(sm, "shop_band", d.get("shop", 0.0))
			_sp(sm, "win_top", d.get("top", 1000.0))
			_sp(sm, "win_mask", d.get("win_mask", Vector4.ZERO))
			_sp(sm, "shop_mask", d.get("shop_mask", Vector2.ZERO))
			_window_params(sm, st_a, st_b)
		mats[name] = sm
		_kit_mats.append(sm)


func _window_params(sm: ShaderMaterial, a: Dictionary, b: Dictionary) -> void:
	for k in [["win_office_rad", "window_office"], ["win_home_rad", "window_home"], ["win_shop_rad", "shopfront"]]:
		var fx: Dictionary = Lucid.FIXTURES[k[1]]
		_sp(sm, k[0], Lucid.fixture_rgb(fx) * (Lucid.face_luminance(fx) / Lucid.UNIT_NITS))
	_sp(sm, "lit_a", a.windows)
	_sp(sm, "lit_b", b.windows)


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
	_sp(_block_mat, "ground_y", LEVEL_Y)
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
	_sp(_ground_mat, "ground_y", LEVEL_Y)
	_sp(_ground_mat, "i_led", Lucid.light_engine(Lucid.FIXTURES.led_street_100w, LucidCity.AVENUE_LAMP.llf))
	_sp(_ground_mat, "i_na", Lucid.light_engine(Lucid.FIXTURES.sodium_hps_150w, LucidCity.STREET_LAMP.llf))
	_sp(_ground_mat, "asphalt", Color(0.094, 0.086, 0.068))
	_sp(_ground_mat, "walk", Color(0.3, 0.295, 0.28))
	_sp(_ground_mat, "e_spill", Lucid.fixture_rgb(Lucid.FIXTURES.shopfront) * Lucid.lux_to_engine(2.0))
	_sp(_ground_mat, "wet", lay.mats.road.wet)
	_sp(_ground_mat, "puddles", lay.mats.road.puddles)
	_sp(_ground_mat, "gutters", true)
	_sp(_ground_mat, "lens_led", _lens_led)
	_sp(_ground_mat, "lens_na", _lens_na)
	_kit_mats.append(_ground_mat)
	var g := MeshInstance3D.new()
	g.mesh = _ground_ring(7000.0, NEAR_GROUND.grow(-0.25))
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
	_sp(_points_mat, "cycle", CYCLE)
	_sp(_points_mat, "halos", not low)
	_kit_mats.append(_points_mat)
	for list in _sectors(lay.points, 1e9).values():
		LucidCity.instance(LucidCity.point_multimesh(list), _points_mat, city)
	# Far-field lighting numbers for the blocks (worked out once).
	_sp(_block_mat, "e_street_led", _facade_light(true))
	_sp(_block_mat, "e_street_na", _facade_light(false))


## A flat square (half size `half`, XZ, facing up) round a rectangular
## hole: four strips, the north and south ones the full width.
static func _ground_ring(half: float, hole: Rect2) -> ArrayMesh:
	var x0 := hole.position.x
	var z0 := hole.position.y
	var x1 := hole.end.x
	var z1 := hole.end.y
	var v := PackedVector3Array()
	for q: Rect2 in [Rect2(-half, -half, half * 2.0, z0 + half), Rect2(-half, z1, half * 2.0, half - z1),
			Rect2(-half, z0, x0 + half, z1 - z0), Rect2(x1, z0, half - x1, z1 - z0)]:
		var a := Vector3(q.position.x, 0.0, q.position.y)
		var b := Vector3(q.end.x, 0.0, q.position.y)
		var c := Vector3(q.end.x, 0.0, q.end.y)
		var d := Vector3(q.position.x, 0.0, q.end.y)
		v.append_array([a, b, c, a, c, d])
	var n := PackedVector3Array()
	n.resize(v.size())
	n.fill(Vector3.UP)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


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
			# (The head looks down: its emission angle is that of the ray
			# from it down to the wall, -dn. Taken as dn this was always 0
			# and no street light reached the backdrop.)
			var ce := maxf(dn.y, 0.0)
			e += pow(ce, m) * maxf(nn.dot(dn), 0.0) / r2
	return c * e


func _lamp_model(spec: Dictionary, fx_name: String) -> ArrayMesh:
	var h: float = spec.h
	var arm: float = spec.arm
	var s := LucidCity.Surf.new()
	s.cyl(Vector3.ZERO, 0.11, h + 0.25, 6, h)
	s.box(Vector3(0, h + 0.2, arm * 0.5), Vector3(0.08, 0.08, arm), 4.0, LAYOUT.ALL)
	s.box(Vector3(0, h + 0.08, arm + 0.1), Vector3(0.34, 0.15, 0.72), 2.0, LAYOUT.ALL)
	var lens := LucidCity.Surf.new()
	lens.quad(Vector3(-0.13, h - 0.001, arm - 0.15), Vector3(0.26, 0, 0), Vector3(0, 0, 0.45), 1.0, Vector3.DOWN)
	var mesh := ArrayMesh.new()
	var lit := ShaderMaterial.new()
	lit.shader = CITY
	_sp(lit, "albedo", Color(0.25, 0.26, 0.26))
	_sp(lit, "baked", false)
	var fx: Dictionary = Lucid.FIXTURES[fx_name]
	_sp(lit, "const_light", Lucid.fixture_rgb(fx) * Lucid.lux_to_engine(5.0))
	var lm := ShaderMaterial.new()
	lm.shader = CITY
	_sp(lm, "albedo", Color(0.3, 0.3, 0.3))
	_sp(lm, "baked", false)
	_sp(lm, "emit_nits", Lucid.fixture_rgb(fx) * Lucid.face_luminance(fx))
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
	# Before every other transparent thing (depth_draw_never puts the dome in
	# the transparent pass, sorted nearest: it was drawn over the far lights
	# against the sky, their halos in the mist and the lightning bolt).
	_sky_mat.render_priority = -1
	_kit_mats.append(_sky_mat)
	var sm := SphereMesh.new()
	sm.radius = 7000.0
	sm.height = 14000.0
	sm.radial_segments = 32
	sm.rings = 16
	# The deck over the two downtowns and the river (level space = world x, z).
	var dt: Array = LAYOUT.DOWNTOWN
	_sp(_sky_mat, "downtown", Vector4(dt[0].x, dt[0].z, dt[1].x, dt[1].z))
	_sp(_sky_mat, "river", LAYOUT.RIVER)
	_sp(_sky_mat, "octaves", 2 if low else 4)
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
	for k in [["lucid_glow_led", "led_street_100w"], ["lucid_glow_na", "sodium_hps_150w"]]:
		var rgb := Lucid.fixture_rgb(Lucid.FIXTURES[k[1]])
		RenderingServer.global_shader_parameter_set(k[0], Vector4(rgb.r, rgb.g, rgb.b, 0.0))
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
	var e := _probe(p - Vector3(0.0, LEVEL_Y, 0.0)) + (_storm.light(Vector3.UP) * 0.5 if _storm != null else Color(0, 0, 0))
	var x := cam.shader_exposure()
	return Color(minf(e.r * x.r, 1.0), minf(e.g * x.g, 1.0), minf(e.b * x.b, 1.0))


func on_enter() -> void:
	player.can_climb = false
	_rain_globals()
	_update(0.0)


func on_leave() -> void:
	Lucid.clear_level()
	LucidStorm.clear()
	HUD.lens_rain = 0.0
	HUD.lens_wipe = true


func _exit_tree() -> void:
	Lucid.clear_level()
	LucidStorm.clear()
	HUD.lens_rain = 0.0


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
	if not _qa_bodies.is_empty():
		_qa_light()
	# The storm a frame on (the deck, the bursts, a flash), then the camera:
	# meter, white balance, then everything that follows it.
	var haze := lerpf(a.haze, b.haze, blend)
	_haze = haze
	if _storm != null:
		_storm.cover = lerpf(a.get("cloud", 0.0), b.get("cloud", 0.0), blend)
		var eye := player.camera.global_position if player != null and player.camera != null else city.to_global(Vector3(25, 1.7, 25))
		_storm.update(delta, eye)
		_sp(_sky_mat, "drift", _storm.drift)
	if player != null and player.camera != null:
		_meter(delta)
	var sky := LucidCity.push_sky(a, b, blend)
	Lucid.push_level(cam, blend, 1.0, (sky.horizon as Color) * Lucid.UNIT_NITS, haze)
	var e_up := Lucid.sky_illuminance(a, Vector3.UP, 8).lerp(Lucid.sky_illuminance(b, Vector3.UP, 8), blend) * (1.0 / (PI * Lucid.UNIT_NITS))
	var e_side := Lucid.sky_illuminance(a, Vector3.RIGHT, 8).lerp(Lucid.sky_illuminance(b, Vector3.RIGHT, 8), blend) * (1.0 / (PI * Lucid.UNIT_NITS))
	var ma := Lucid.kelvin_rgb(a.moon_k) * Lucid.lux_to_engine(a.moon_lux)
	var mb := Lucid.kelvin_rgb(b.moon_k) * Lucid.lux_to_engine(b.moon_lux)
	var moon_e := ma.lerp(mb, blend)
	var md := Lucid.sky_dir(a.moon_alt, a.moon_az)
	_sp(_block_mat, "e_sky_up", e_up)
	_sp(_block_mat, "e_sky_side", e_side)
	_sp(_block_mat, "e_moon", moon_e)
	_sp(_block_mat, "moon_dir", md)
	_sp(_ground_mat, "e_sky_up", e_up)
	_sp(_points_mat, "clock", clock)
	var su := Lucid.sky_uniforms(a)
	_sp(_sky_mat, "moon_dir", md)
	_sp(_sky_mat, "moon_rad", (su.moon as Color) * ((1.0 - blend) / Lucid.UNIT_NITS))
	_sp(_sky_mat, "moon_e", moon_e)
	_sp(_sky_mat, "stars", lerpf(a.stars, b.stars, blend))
	if player != null and player.camera != null:
		_sky.global_position = player.camera.global_position
	# The moon's highlight as a directional light.
	var mn := Lucid.light_node_cam(moon_e, cam)
	_moon.light_energy = mn[0]
	_moon.light_color = mn[1]
	_moon.visible = mn[0] > 0.0
	_moon.look_at_from_position(Vector3.ZERO, -md, Vector3.UP if absf(md.y) < 0.99 else Vector3.BACK)
	_real_lights(delta)
	_rain_update(delta)
	if _wind is AudioStreamPlayer3D and _storm != null:
		(_wind as AudioStreamPlayer3D).volume_db = -6.0 + 9.0 * _storm.intensity


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
		# (A flash: about half the sky is open round a surface.)
		var fl := _storm.light(nn) * 0.5 if _storm != null else Color(0, 0, 0)
		col = (e + _natural(p) + fl) * (alb * Lucid.UNIT_NITS)
		# Stage 4: wet ground after rain mirrors the lamps (the meter sees
		# that too; the shaders' roughness after the water: road 0.19,
		# damp sidewalks ~0.75), and darkens (Lekner & Dorf: ~0.55).
		if nn.y > 0.7 and p.y < 12.0:
			var rough := 0.19 if p.y < 0.1 else 0.75
			col = col * 0.55 + _lamps_spec(p, nn, -dir, rough) * Lucid.UNIT_NITS
	elif dir.y < 0.06:
		col = Lucid.kelvin_rgb(3300.0) * 0.25
	else:
		var a: Dictionary = Lucid.STATES[STATE_A]
		var b: Dictionary = Lucid.STATES[STATE_B]
		col = Lucid.sky_nits(a, dir).lerp(Lucid.sky_nits(b, dir), blend)
		if _storm != null:
			col += _storm.sky_nits(dir, _haze)
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


## The lamps' specular reflection (engine units) at p seen along v (toward
## the eye): GGX, Smith, Schlick (F0 0.04), each lens as a small sphere
## (its angular radius added to alpha, Karis 2013) so a mirror spot is not
## a spike.
func _lamps_spec(p: Vector3, n: Vector3, v: Vector3, rough: float) -> Color:
	var out := Color(0, 0, 0)
	var a0 := rough * rough
	var ndv := maxf(n.dot(v), 1e-3)
	for l in _meter_ctx.lamps:
		var d: Vector3 = l.pos - p
		var r2 := d.length_squared()
		if r2 > 2500.0:
			continue
		var dist := sqrt(r2)
		var ld := d / dist
		var ndl := n.dot(ld)
		var ce: float = -ld.dot(l.dir)
		if ndl <= 0.0 or (l.m > 0.0 and ce <= 0.0):
			continue
		var em := 1.0 if l.m <= 0.0 else pow(ce, l.m)
		var a := minf(a0 + 0.25 / dist, 1.0)
		var a2 := a * a
		var h := (v + ld).normalized()
		var ndh := maxf(n.dot(h), 0.0)
		var dd := ndh * ndh * (a2 - 1.0) + 1.0
		var dn := a2 / (PI * dd * dd)
		var vis := 0.5 / (ndl * sqrt(ndv * ndv * (1.0 - a2) + a2) + ndv * sqrt(ndl * ndl * (1.0 - a2) + a2) + 1e-5)
		var f := 0.04 + 0.96 * pow(1.0 - clampf(v.dot(h), 0.0, 1.0), 5.0)
		# E / pi normal to the lamp -> radiance: x pi x BRDF x cos.
		out += (l.c as Color) * (em / r2 * PI * dn * vis * f * ndl)
	return out


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
	_sp(mats.lens_na_failing, "emit_nits", Color(e.r * tint.r, e.g * tint.g, e.b * tint.b))
	if _buzz:
		_buzz.volume_db = -22.0 + 10.0 * lvl if lvl > 0.01 else -80.0


func _push_levels() -> void:
	var arr := PackedVector4Array()
	for i in 8:
		arr.append(Vector4(lamp_lvl[i * 4], lamp_lvl[i * 4 + 1], lamp_lvl[i * 4 + 2], lamp_lvl[i * 4 + 3]))
	# The failing head's lens (its reflections follow it).
	var fail := Vector4(LAYOUT.FAILING.x, LAYOUT.FAILING.y, LAYOUT.FAILING.z - 0.1, lamp_lvl[_fail_idx] if _fail_idx >= 0 else 1.0)
	for n in mats:
		_sp((mats[n] as ShaderMaterial), "lamp_lvl", arr)
		_sp((mats[n] as ShaderMaterial), "fail_lamp", fail)
	_sp(_ground_mat, "fail_lamp", fail)


## Stage 4: the reflection probes, captured once the level is in the tree
## (LucidProbe: all of them in one go, two frames, with the street heads'
## and signals' lenses dark in them: their reflections are analytic).
func _capture_probes() -> void:
	await get_tree().process_frame
	if not is_inside_tree():
		return
	var t0 := Time.get_ticks_msec()
	var origins := []
	for pr in PROBES:
		origins.append(city.to_global(pr[0]))
	var faces: Array = await LucidProbe.capture(self, origins, LucidProbe.capture_environment(), 3000.0)
	if not is_inside_tree():
		return
	var maps: Array[Image] = []
	for f in faces:
		maps.append(LucidProbe.octahedral(f))
	var tex := LucidProbe.array_texture(maps)
	var pc := PackedVector4Array()
	var lo := PackedVector4Array()
	var hi := PackedVector4Array()
	var sel_z := PackedVector4Array()
	for k in PROBES.size():
		var pr: Array = PROBES[k]
		var box: Array = PROBE_PROJECT.get(k, [pr[1], pr[2]])
		# lo.w / hi.w and probe_sel: the selecting box (x; z, y).
		pc.append(Vector4(pr[0].x, pr[0].y, pr[0].z, 1.0 if k in PROBE_PLUS else 0.0))
		lo.append(Vector4(box[0].x, box[0].y, box[0].z, pr[1].x))
		hi.append(Vector4(box[1].x, box[1].y, box[1].z, pr[2].x))
		sel_z.append(Vector4(pr[1].z, pr[2].z, pr[1].y, pr[2].y))
	for n in mats:
		var sm := mats[n] as ShaderMaterial
		_sp(sm, "probe_tex", tex)
		_sp(sm, "probe_n", PROBES.size())
		_sp(sm, "probe_c", pc)
		_sp(sm, "probe_lo", lo)
		_sp(sm, "probe_hi", hi)
		_sp(sm, "probe_sel", sel_z)
	probe_bytes = LucidProbe.bytes(maps)
	probe_ms = Time.get_ticks_msec() - t0
	print("night_city probes: %d, %d KB, %d ms" % [maps.size(), probe_bytes / 1024, probe_ms])


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
			_sp(mats["sig_%s_%s" % [set_name, c]], "emit_nits", Lucid.fixture_rgb(fx) * lum)
	for set_name in ["ped_a", "ped_s"]:
		var st := signal_state(s, set_name)
		var hand_on := st == "hand" or (st == "flash" and fmod(s, 1.0) < 0.5)
		var hfx: Dictionary = Lucid.FIXTURES.ped_hand
		var wfx: Dictionary = Lucid.FIXTURES.ped_walk
		_sp(mats[set_name + "_hand"], "emit_nits", Lucid.fixture_rgb(hfx) * (hfx.luminance if hand_on else 0.0))
		_sp(mats[set_name + "_walk"], "emit_nits", Lucid.fixture_rgb(wfx) * (wfx.luminance if st == "walk" else 0.0))
	# Stage 4: the lit lens of each vehicle head, for its reflections.
	var key := signal_state(s, "avenue") + signal_state(s, "street")
	if key != _sig_key:
		_sig_key = key
		var sp := PackedVector4Array()
		var sr := PackedVector4Array()
		var sd := PackedVector4Array()
		for h in lay.heads:
			if h.set != "avenue" and h.set != "street":
				continue
			var on := signal_state(s, h.set)
			var i: int = ["r", "y", "g"].find(on)
			var fx: Dictionary = cols[on]
			var lum: float = fx.peak_cd / (PI * 0.15 * 0.15) / Lucid.UNIT_NITS
			var c: Vector3 = h.pos + Vector3(0, 0.33 - i * 0.33, 0) + (h.normal as Vector3) * 0.011
			var rgb := Lucid.fixture_rgb(fx) * lum
			sp.append(Vector4(c.x, c.y, c.z, 0.0))
			sr.append(Vector4(rgb.r, rgb.g, rgb.b, 1.0))
			sd.append(Vector4(h.normal.x, h.normal.y, h.normal.z, 0.0))
		for n in ["road", "alley", "walk", "curb", "plaza"]:
			var sm := mats[n] as ShaderMaterial
			_sp(sm, "sig_pos", sp)
			_sp(sm, "sig_rad", sr)
			_sp(sm, "sig_dir", sd)
		if _rain != null:
			# The rain: the same lenses as intensities (I = luminance x area), in world space.
			var wp := PackedVector4Array()
			var wi := PackedVector4Array()
			for i in sp.size():
				wp.append(sp[i] + Vector4(0.0, LEVEL_Y, 0.0, 0.0))
				wi.append(sr[i] * (PI * 0.15 * 0.15 / PI))
			_rain.set_signals(wp, wi, sd)
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
		# The few nearest heads (two more than there are lights) ...
		var all := []
		for l in lay.lamps:
			if int(l.get("idx", -1)) < 0 or l.get("bulb", false):
				continue
			all.append([(l.pos as Vector3).distance_squared_to(me), l])
		all.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		_light_cand.clear()
		for i in mini(all.size(), _lights.size() + 2):
			_light_cand.append(all[i][1])
	# ... and each frame the lights go to the nearest of them, each faded by
	# how much nearer it is than the first one left out (_fade_weights): a
	# light and its haze glow no longer pop on and off when the nearest
	# four change as you walk past a pair of heads.
	var cand := []
	for l: Dictionary in _light_cand:
		cand.append([(l.pos as Vector3).distance_squared_to(me), l])
	cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
	var w := _fade_weights(cand, _lights.size())
	for i in _lights.size():
		var l := _lights[i]
		if i >= w.size() or w[i] <= 0.0:
			l.visible = false
			RenderingServer.global_shader_parameter_set("lucid_glow%d" % i, Vector4.ZERO)
			continue
		var lamp: Dictionary = cand[i][1]
		var idx := int(lamp.idx)
		var c := Lucid.light_engine(Lucid.FIXTURES[lamp.fx], float(lamp.llf)) * (lamp_lvl[idx] * w[i])
		var ln := Lucid.light_node_cam(c, cam)
		l.light_energy = ln[0]
		l.light_color = ln[1]
		l.global_position = city.to_global(lamp.pos - Vector3(0, 0.05, 0))
		l.visible = ln[0] > 0.0
		# Stage 4: the haze it lights (lucid_airglow): peak intensity as
		# engine units, negative for sodium.
		var led: bool = lamp.fx == "led_street_100w"
		RenderingServer.global_shader_parameter_set("lucid_glow%d" % i, Vector4(l.global_position.x, l.global_position.y,
				l.global_position.z, Lucid.lum(c) * (1.0 if led else -1.0)))


## How much of each of the `n` nearest lights to use, from `cand` ([distance
## squared, ...] sorted nearest first): full until it is FADE_BAND metres
## from being as far as the first one left out, then fading to nothing
## there, so the set of nearest lights changes without a light popping.
static func _fade_weights(cand: Array, n: int) -> PackedFloat32Array:
	var w := PackedFloat32Array()
	w.resize(mini(n, cand.size()))
	var edge: float = sqrt(cand[n][0]) if cand.size() > n else INF
	for i in w.size():
		w[i] = clampf((edge - sqrt(cand[i][0])) / FADE_BAND, 0.0, 1.0)
	return w

# --------------------------------------------------------------------- rain ---

## Where no rain falls (level space): under the bus shelter's roof, the
## fire stair (its top landing over the rest), the water tank on its stand.
func _cover_boxes() -> Array[AABB]:
	var roof: float = LAYOUT.A_ROOF
	return [AABB(Vector3(-13.8, -1.0, -38.2), Vector3(2.4, LAYOUT.WALK + 3.4, 6.4)),
			AABB(Vector3(45.0, -1.0, 12.4), Vector3(2.6, roof + 1.0, 5.4)),
			AABB(Vector3(39.25, roof - 1.0, 34.65), Vector3(4.7, 8.6, 4.7))]


func _rain_covers(sm: ShaderMaterial) -> void:
	var r := PackedVector4Array()
	var t := Vector4(-1e6, -1e6, -1e6, -1e6)
	var boxes := _cover_boxes()
	for i in 4:
		if i < boxes.size():
			r.append(Vector4(boxes[i].position.x, boxes[i].position.z, boxes[i].end.x, boxes[i].end.z))
			t[i] = boxes[i].end.y
		else:
			r.append(Vector4.ZERO)
	_sp(sm, "rain_cover", r)
	_sp(sm, "rain_cover_top", t)


## Rain on or off (Settings > Rain); Potato and Low get a lighter rain.
func _rain_settings() -> void:
	var on := bool(Settings.get_value("graphics/rain"))
	if on == _rain_on:
		return
	_rain_on = on
	if on and _rain == null:
		_build_rain()
	if _rain != null:
		_rain.visible = on
	for n in _rain_nodes:
		if n is AudioStreamPlayer3D:
			(n as AudioStreamPlayer3D).playing = on
		elif n is AudioStreamPlayer:
			(n as AudioStreamPlayer).playing = on
	_rain_globals()


func _rain_globals() -> void:
	var sig := LucidRain.sigma(_rain.rate) if _rain != null else 0.0
	# x: the drops' scattering in the lamps' airglow (half their
	# cross-section: their phase function, g ~0.8, sends about half as much
	# sideways as the haze's g = 0.6); y: rings on the water; z: the rings'
	# clock (faster in a burst); w: the rain's extinction (its geometric
	# cross-section: the diffraction stays in the beam), with the haze's.
	var rings := _storm.rings if _storm != null else 0.0
	RenderingServer.global_shader_parameter_set("lucid_rain", Vector4(sig * 0.5, 1.0, rings, sig) if _rain_on else Vector4.ZERO)
	if not _rain_on:
		HUD.lens_rain = 0.0


func _build_rain() -> void:
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	var roof: float = LAYOUT.A_ROOF
	var w: float = LAYOUT.WALK
	_rain = LucidRain.new()
	_rain.name = "Rain"
	add_child(_rain)
	if low:
		_rain.setup(1500, 200, 96, 500, o)
	else:
		_rain.setup(4000, 600, 240, 1600, o)
	_sp(_rain.material, "roof_y", roof)
	var boxes: Array[AABB] = []
	for b in _cover_boxes():
		boxes.append(AABB(b.position + o, b.size))
	_rain.set_covers(boxes)
	# Drips from real edges: [from, to, fall (m)] (level space; a ring:
	# centre twice and its radius). The shelter roof's two long edges, under
	# the stair's lowest landing and half landing (through the grating), the
	# four signal mast arms, the tank roof's eaves, the parapet's coping over
	# the avenue and the street, the bulkhead's coping over its door.
	var hm := (LAYOUT.STAIR_Y[0] + LAYOUT.STAIR_Y[1]) * 0.5
	var edges := [[Vector3(-11.42, w + 2.4, -38.1), Vector3(-11.42, w + 2.4, -31.9), 2.4],
			[Vector3(-13.78, w + 2.4, -38.1), Vector3(-13.78, w + 2.4, -31.9), 2.4],
			[Vector3(45.2, LAYOUT.G0 - 0.1, 13.0), Vector3(47.4, LAYOUT.G0 - 0.1, 13.0), LAYOUT.G0 - 0.1 - w],
			[Vector3(45.2, hm - 0.1, 17.2), Vector3(47.4, hm - 0.1, 17.2), hm - 0.1 - w],
			[Vector3(11.3, 6.11, -7.8), Vector3(3.5, 6.11, -7.8), 6.1],
			[Vector3(-11.3, 6.11, 7.8), Vector3(-3.5, 6.11, 7.8), 6.1],
			[Vector3(11.3, 6.11, 7.8), Vector3(11.3, 6.11, 1.75), 6.1],
			[Vector3(-11.3, 6.11, -7.8), Vector3(-11.3, 6.11, -1.75), 6.1],
			[Vector3(41.6, roof + 7.6, 37.0), Vector3(41.6, roof + 7.6, 37.0), 7.6, 2.4],
			[Vector3(14.9, roof + 1.1, 10.5), Vector3(14.9, roof + 1.1, 39.5), roof + 1.1 - w],
			[Vector3(15.5, roof + 1.1, 9.9), Vector3(44.5, roof + 1.1, 9.9), roof + 1.1 - w],
			[Vector3(33.92, roof + 3.0, 31.1), Vector3(33.92, roof + 3.0, 35.9), 3.0]]
	for e in edges:
		e[0] += o
		e[1] += o
	_rain.set_drips(edges)
	_sig_key = ""


## Each frame: the camera's exposure and motion, the lights near it, the
## lens and the sound under cover.
func _rain_update(delta: float) -> void:
	if not _rain_on or _rain == null or player == null or player.camera == null:
		return
	var c := player.camera.global_position
	if _cam_prev.is_finite() and delta > 0.0:
		var v := (c - _cam_prev) / delta
		# (A teleport is not motion; it starts a clean lens.)
		if v.length() > 15.0:
			v = Vector3.ZERO
			HUD.lens_wipe = true
		_cam_vel = _cam_vel.lerp(v, minf(delta * 8.0, 1.0))
	_cam_prev = c
	# The storm's rain now (its bursts) and wind (its gusts).
	if _storm != null:
		_rain.set_rate(_storm.rate, _storm.wind)
	_rain_globals()
	# The camera's exposure time (at night its four merged 1/30 s frames:
	# 1/8 s, so a drop draws a streak v / 8 long).
	_rain.follow(player.camera, clampf(cam.shutter, 1.0 / 500.0, 1.0 / 8.0), _cam_vel.limit_length(8.0), float(OS.get_environment("RAIN_GAIN")) if OS.has_environment("RAIN_GAIN") else 1.0)
	var me := c - Vector3(0.0, LEVEL_Y, 0.0)
	_rain_t -= delta
	if _rain_t <= 0.0:
		_rain_t = 0.4
		# The eight nearest lights: the four nearest street heads first, each
		# kept in its slot while it stays among them (drops fall round them),
		# then the next nearest lights (heads at their levels, bulbs).
		var cand := []
		for i in lay.lamps.size():
			var l: Dictionary = lay.lamps[i]
			if l.get("fx", "") != "":
				cand.append([(l.pos as Vector3).distance_squared_to(me), i])
		cand.sort_custom(func(x: Array, y: Array) -> bool: return x[0] < y[0])
		var heads := []
		var head_edge := INF
		for cd in cand:
			if not lay.lamps[cd[1]].get("bulb", false):
				if heads.size() < 4:
					heads.append(cd[1])
				else:
					head_edge = sqrt(cd[0])
					break
		var slots := [-1, -1, -1, -1]
		for k in 4:
			if k < _rain_heads.size() and heads.has(_rain_heads[k]):
				slots[k] = _rain_heads[k]
		for hd in heads:
			if not slots.has(hd):
				slots[slots.find(-1)] = hd
		_rain_heads = slots
		var order := slots.duplicate()
		var edge := INF
		for cd in cand:
			if order.has(cd[1]):
				continue
			if order.size() >= 8:
				edge = sqrt(cd[0])
				break
			order.append(cd[1])
		# Each faded as it nears the first left out (_fade_weights): the next
		# lights' scatter, and the drops round a head (it keeps its light
		# while it is among the eight), so neither pops in or out.
		var lights := []
		for k in order.size():
			var li: int = order[k]
			if li < 0:
				lights.append([Vector3.ZERO, -1.0, Color(0, 0, 0), 0.0])
				continue
			var l: Dictionary = lay.lamps[li]
			var fx: Dictionary = Lucid.FIXTURES[l.fx]
			var lv: float = lamp_lvl[int(l.idx)] if int(l.get("idx", -1)) >= 0 else 1.0
			var m: float = fx.get("m", 0.0)
			var fade := clampf(((head_edge if k < 4 else edge) - me.distance_to(l.pos)) / FADE_BAND, 0.0, 1.0)
			lights.append([city.to_global(l.pos), m if m > 0.0 else -1.0,
					Lucid.light_engine(fx, float(l.get("llf", 1.0))) * (lv if k < 4 else lv * fade), fade if k < 4 else 1.0])
		# The surround a drop refracts: the light round it on surfaces of ~0.2.
		_rain.set_lights(lights, _probe(me) * 0.2)
	var under := _rain.covered(c, -0.3)
	# Drops on the body cam's lens (none under cover).
	HUD.lens_rain = 0.0 if under else _rain.lens_rate(-player.camera.global_transform.basis.z, _cam_vel)
	if _rain_snd:
		_rain_db = lerpf(_rain_db, -6.0 if under else 0.0, minf(delta * 3.0, 1.0))
		# Louder in a burst: the drops' impacts go about as the rate.
		_rain_snd.volume_db = -8.0 + _rain_db + 10.0 * log(_rain.rate / 6.0) / log(10.0)


# -------------------------------------------------------------------- storm ---

## Thunder recordings (procedural placeholders, tools/lucid/night_city_thunder.py)
## by distance class: [name, the distance it was made for (m), up to (m)].
const THUNDER := [["thunder_near", 1600.0, 2600.0], ["thunder_mid", 4000.0, 6500.0], ["thunder_far", 9000.0, 1e9]]


func _build_storm() -> void:
	_storm = LucidStorm.new()
	_storm.name = "Storm"
	add_child(_storm)
	_storm.setup(seed_value, LEVEL_Y, low)
	_storm.thunder.connect(_thunder)
	# The towers over 150 m: a bolt now and then strikes one's rod (a few
	# metres over its top).
	var rods := PackedVector3Array()
	for b: Dictionary in lay.blocks:
		if b.pos.y + b.size.y > 150.0:
			rods.append(b.pos + Vector3(0.0, b.size.y + LEVEL_Y + 6.0, 0.0))
	_storm.towers = rods
	if OS.get_environment("QA_STORM") == "1" or OS.get_environment("QA_BOLTS") == "1":
		_storm.calm(1e5)


## Settings > Reduce flashing: the flashes' light spread over a quarter
## second (no flicker), dimmer and half as often.
func _storm_settings() -> void:
	if _storm != null:
		_storm.reduce = bool(Settings.get_value("gameplay/reduce_flashing"))


## Thunder arriving `dist` m from the flash's nearest point, from `dir`:
## the recording of its distance class (near: a crack then the rumble;
## far: a low roll, the highs gone), 6 dB down for each doubling of the
## distance (spherical spreading; the air's absorption is in the class).
func _thunder(dist: float, dir: Vector3) -> void:
	if player == null:
		return
	var cls: Array = THUNDER[THUNDER.size() - 1]
	for c: Array in THUNDER:
		if dist < float(c[2]):
			cls = c
			break
	var names := []
	for k in [1, 2]:
		var n := "%s_%d" % [cls[0], k]
		if not _sounds.has(n) and ResourceLoader.exists(DIR + "audio/" + n + ".ogg"):
			_sounds[n] = load(DIR + "audio/" + n + ".ogg")
		if _sounds.has(n):
			names.append(n)
	if names.is_empty():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[names[randi() % names.size()]]
	p.bus = "World"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	# (Thunder 2 km off is ~30 dB over heavy rain: well over the loops.)
	p.volume_db = 9.0 + 20.0 * log(float(cls[1]) / dist) / log(10.0)
	add_child(p)
	p.global_position = player.camera.global_position + dir * 40.0 + Vector3(0, 15.0, 0)
	p.play()
	p.finished.connect(p.queue_free)


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
	# Rain (procedural placeholders, see LICENSE.md): everywhere, quieter
	# under cover; pattering on the metal of the shelter roof, the fire
	# stair's landings and the tank's hoops; drips off the shelter and the
	# stair.
	for n: String in ["rain", "rain_metal"]:
		if ResourceLoader.exists(DIR + "audio/" + n + ".ogg"):
			_sounds[n] = load(DIR + "audio/" + n + ".ogg")
	if _sounds.has("rain"):
		_rain_snd = add_loop(_sounds.rain, Vector3.INF, -8.0) as AudioStreamPlayer
		_rain_nodes.append(_rain_snd)
	if _sounds.has("rain_metal"):
		for at in [Vector3(-12.6, 2.6, -35.0), Vector3(46.2, 4.6, 13.0), Vector3(46.2, 11.2, 15.0), Vector3(46.2, 17.8, 13.0)]:
			_rain_nodes.append(add_loop(_sounds.rain_metal, city.to_global(at), -12.0, {"unit_size": 2.0, "max_distance": 25.0}))
	for at in [Vector3(-11.4, 0.3, -35.0), Vector3(46.3, 0.3, 13.0)]:
		_rain_nodes.append(add_loop("drip", city.to_global(at), -16.0, {"unit_size": 1.5, "max_distance": 15.0}))
	for n in _rain_nodes:
		if n is AudioStreamPlayer3D:
			(n as AudioStreamPlayer3D).playing = false
		elif n is AudioStreamPlayer:
			(n as AudioStreamPlayer).playing = false
	if _sounds.has("wind_high"):
		var w := add_loop(_sounds.wind_high, city.to_global(Vector3(30, 30, 25)), -6.0, {"unit_size": 30.0, "max_distance": 120.0})
		w.name = "wind"
		_wind = w
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

static func _qa() -> bool:
	return OS.is_debug_build() and OS.get_environment("QA_FIGURES") == "1"


## The entity rig at a person's proportions (the crawler's mesh in its
## rest pose, unstretched: 1.68 m, scaled to 1.75 m), grey, lit by the
## probes (brighter than real, to be seen).
func _qa_figures() -> void:
	if not _qa():
		return
	for q in QA_SPOTS.values():
		var b := EntityBody.new()
		b.who = "crawler"
		b.tint = Color(0.55, 0.55, 0.55)
		b.scale = Vector3.ONE * (1.75 / 1.681)
		city.add_child(b)
		b.position = q[0]
		b.rotation.y = deg_to_rad(q[1]) + PI
		_qa_bodies.append(b)


func _qa_light() -> void:
	for b in _qa_bodies:
		var c := light_at(b.global_position + Vector3.UP * 1.2)
		b.set_env_light(Color(maxf(c.r, 0.04), maxf(c.g, 0.04), maxf(c.b, 0.04)) * 1.5)


func _view(at: Vector3, yaw_deg: float, pitch_deg := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
	return Transform3D(b, at + Vector3(0.0, LEVEL_Y, 0.0))


## Yaw 0 looks north (-Z), 90 west, 180 south, 270 east.
func shots() -> Array:
	var roof: float = LAYOUT.A_ROOF
	var sy: Array = LAYOUT.STAIR_Y
	if OS.get_environment("QA_STORM") == "1":
		return _storm_shots()
	if OS.get_environment("QA_BOLTS") == "1":
		return _bolt_shots()
	return [
		{"name": "arrival", "transform": arrival(), "wait": 3.0},
		{"name": "roof_edge", "transform": _view(Vector3(15.9, roof, 10.9), 45.0, -22.0), "wait": 4.0},
		{"name": "roof_skyline", "transform": _view(Vector3(20.0, roof, 20.0), 70.0, 4.0), "wait": 4.0},
		{"name": "roof_north", "transform": _view(Vector3(25.0, roof, 12.0), 5.0, 2.0), "wait": 4.0},
		{"name": "roof_tank", "transform": _view(Vector3(31.0, roof, 24.0), 220.0, 8.0), "wait": 4.0},
		{"name": "stair", "transform": _view(Vector3(46.9, sy[3], 13.0), 20.0, -10.0), "wait": 4.0},
		{"name": "alley", "transform": _view(Vector3(48.0, 0.15, 30.0), 10.0, 3.0), "wait": 4.0},
		{"name": "street_corner", "transform": _view(Vector3(12.0, 0.15, 12.0), 0.0, 4.0), "wait": 4.0},
		{"name": "avenue_south", "transform": _view(Vector3(3.0, 0.0, -20.0), 180.0, 2.0), "wait": 4.0},
		{"name": "street_west", "transform": _view(Vector3(30.0, 0.15, 8.0), 90.0, 3.0), "wait": 4.0},
		{"name": "plaza_tower", "transform": _view(Vector3(-20.0, 0.15, -15.0), 45.0, 30.0), "wait": 4.0},
		{"name": "failing_lamp", "transform": _view(Vector3(40.0, 0.15, 8.5), 280.0, 12.0), "wait": 4.0},
		# QA close-ups: the bulkhead, the parapet's corner, the fire stair
		# from its top, middle and bottom, the sky overhead, windows.
		{"name": "qa_bulkhead", "transform": _view(Vector3(31.0, roof, 31.0), 300.0, 5.0), "wait": 3.0},
		{"name": "qa_door", "transform": _view(Vector3(32.6, roof, 33.4), 270.0, 20.0), "wait": 3.0},
		{"name": "qa_parapet", "transform": _view(Vector3(43.6, roof, 11.4), 330.0, -8.0), "wait": 3.0},
		{"name": "qa_stair_top", "transform": _view(Vector3(46.3, roof, 13.0), 180.0, -55.0), "wait": 3.0},
		{"name": "qa_stair_top2", "transform": _view(Vector3(44.0, roof, 12.8), 250.0, -35.0), "wait": 3.0},
		{"name": "qa_stair_mid_up", "transform": _view(Vector3(46.9, sy[3], 13.0), 160.0, 55.0), "wait": 3.0},
		{"name": "qa_stair_mid_dn", "transform": _view(Vector3(46.9, sy[3], 13.0), 180.0, -45.0), "wait": 3.0},
		{"name": "qa_stair_win", "transform": _view(Vector3(46.0, sy[2] + 2.35, 15.4), 95.0, 5.0), "wait": 3.0},
		{"name": "qa_stair_bot_up", "transform": _view(Vector3(49.0, 0.15, 16.0), 0.0, 60.0), "wait": 3.0},
		{"name": "qa_stair_side", "transform": _view(Vector3(50.5, 0.15, 24.0), 20.0, 25.0), "wait": 3.0},
		{"name": "qa_sky_up", "transform": _view(Vector3(5.0, 0.15, 5.0), 0.0, 89.0), "wait": 3.0},
		{"name": "qa_sky_up2", "transform": _view(Vector3(25.0, roof, 25.0), 300.0, 70.0), "wait": 3.0},
		{"name": "qa_sky_arms", "transform": _view(Vector3(2.0, 0.0, 9.0), 90.0, 80.0), "wait": 3.0},
		{"name": "qa_win_shop", "transform": _view(Vector3(13.0, 0.15, 24.0), 270.0, 5.0), "wait": 3.0},
		{"name": "qa_win_B", "transform": _view(Vector3(47.5, sy[2], 16.4), 270.0, 10.0), "wait": 3.0},
		{"name": "qa_win_D1", "transform": _view(Vector3(20.0, 0.15, -8.5), 0.0, 25.0), "wait": 3.0},
		{"name": "qa_backdrop", "transform": _view(Vector3(85.0, 0.15, 9.0), 270.0, 12.0), "wait": 3.0},
	] + (_scale_shots() if _qa() else []) + (_ground_shots() if OS.get_environment("QA_GROUND") == "1" else []) \
			+ (_rain_shots() if OS.get_environment("QA_RAIN") == "1" else [])


## Storm QA views (QA_STORM=1; the storm calm unless a shot calls for it;
## run with --fixed-fps 30 so a flash lands in the saved frame): the avenue
## to the north-north-east downtown and its towers in the scud, the roof
## skyline to the west downtown, the deck overhead, a far flash to ground
## with its bolt in the west-north-west (just before, during, just after),
## a nearer flash lighting the city from the crossing (before, during),
## the crossing in a burst's heavy rain.
func _storm_shots() -> Array:
	var roof: float = LAYOUT.A_ROOF
	var calm := func() -> void: _storm.calm(1e5)
	var far := func(lead: float) -> Callable:
		return func() -> void:
			_storm.calm(1e5)
			_storm.flash(deg_to_rad(5.0), 2200.0, true, true, 3.0 + lead, 1.0)
	var near := func(lead: float) -> Callable:
		return func() -> void:
			_storm.calm(1e5)
			_storm.flash(deg_to_rad(320.0), 1800.0, true, false, 3.0 + lead, 1.0)
	var heavy := func() -> void:
		_storm.burst(0.5, 1000.0, 35.0)
	return [
		{"name": "st_avenue", "transform": _view(Vector3(2.0, 0.0, -24.0), 345.0, 14.0), "wait": 3.0, "call": calm},
		{"name": "st_skyline", "transform": _view(Vector3(20.0, roof, 20.0), 70.0, 6.0), "wait": 3.0, "call": calm},
		{"name": "st_towers", "transform": _view(Vector3(28.0, roof, 14.0), 333.0, 10.0), "wait": 3.0, "call": calm},
		{"name": "st_towers_w", "transform": _view(Vector3(18.0, roof, 26.0), 75.0, 10.0), "wait": 3.0, "call": calm},
		{"name": "st_deck", "transform": _view(Vector3(25.0, roof, 25.0), 300.0, 55.0), "wait": 3.0, "call": calm},
		{"name": "st_flash_0", "transform": _view(Vector3(28.0, roof, 14.0), 350.0, 6.0), "wait": 3.0, "call": far.call(0.25)},
		{"name": "st_flash_1", "transform": _view(Vector3(28.0, roof, 14.0), 350.0, 6.0), "wait": 3.0, "call": far.call(-0.03)},
		{"name": "st_flash_2", "transform": _view(Vector3(28.0, roof, 14.0), 350.0, 6.0), "wait": 3.0, "call": far.call(-0.75)},
		{"name": "st_city_0", "transform": _view(Vector3(6.0, 0.0, 6.0), 20.0, 8.0), "wait": 3.0, "call": near.call(0.25)},
		{"name": "st_city_1", "transform": _view(Vector3(6.0, 0.0, 6.0), 20.0, 8.0), "wait": 3.0, "call": near.call(-0.03)},
		{"name": "st_heavy", "transform": _view(Vector3(6.0, 0.0, 6.0), 40.0, 2.0), "wait": 5.0, "call": heavy},
	]


## Bolt QA views (QA_BOLTS=1, --fixed-fps 30): flashes to ground forced
## to land their first stroke as the frame is saved, from the roof (the
## north-north-east downtown), the avenue (north, south) and the street
## (west), 1-6 km off,
## one onto a tower's rod, one ~1 km off, an intracloud flash's spiders;
## the last three a later stroke of the same flash (the trunk alone).
func _bolt_shots() -> Array:
	var roof: float = LAYOUT.A_ROOF
	var bolt := func(az: float, dist: float, lead := 0.0) -> Callable:
		return func() -> void:
			_storm.calm(1e5)
			_storm.flash(deg_to_rad(az), dist, true, true, 2.0 - 0.03 + lead, 1.0)
	var rod := func() -> void:
		_storm.calm(1e5)
		_storm.strike(_rod_toward(25.0), 1.97, 1.0)
	var spider := func() -> void:
		_storm.calm(1e5)
		_storm.flash(deg_to_rad(350.0), 4000.0, false, true, 1.97, 1.0)
	var n := Vector3(28.0, roof, 14.0)
	var av := Vector3(2.0, 0.0, -24.0)
	var st := Vector3(30.0, 0.15, 8.0)
	return [
		{"name": "b_roof_n3", "transform": _view(n, 350.0, 12.0), "wait": 2.0, "call": bolt.call(15.0, 3000.0)},
		{"name": "b_roof_n5", "transform": _view(n, 350.0, 12.0), "wait": 2.0, "call": bolt.call(355.0, 5000.0)},
		{"name": "b_roof_n2", "transform": _view(n, 350.0, 14.0), "wait": 2.0, "call": bolt.call(30.0, 2000.0)},
		{"name": "b_roof_nw4", "transform": _view(n, 20.0, 12.0), "wait": 2.0, "call": bolt.call(335.0, 4000.0)},
		{"name": "b_roof_ne6", "transform": _view(n, 330.0, 10.0), "wait": 2.0, "call": bolt.call(40.0, 6000.0)},
		{"name": "b_roof_rod", "transform": _view(n, 335.0, 12.0), "wait": 2.0, "call": rod},
		{"name": "b_roof_near", "transform": _view(n, 350.0, 22.0), "wait": 2.0, "call": bolt.call(0.0, 1000.0)},
		{"name": "b_spider", "transform": _view(n, 350.0, 20.0), "wait": 2.0, "call": spider},
		{"name": "b_av_3", "transform": _view(av, 345.0, 20.0), "wait": 2.0, "call": bolt.call(12.0, 3000.0)},
		{"name": "b_av_15", "transform": _view(av, 345.0, 16.0), "wait": 2.0, "call": bolt.call(5.0, 1500.0)},
		{"name": "b_av_s", "transform": _view(av, 180.0, 12.0), "wait": 2.0, "call": bolt.call(175.0, 3500.0)},
		{"name": "b_st_w", "transform": _view(st, 90.0, 12.0), "wait": 2.0, "call": bolt.call(272.0, 2500.0)},
		{"name": "b_stroke2", "transform": _view(n, 350.0, 12.0), "wait": 2.0, "call": bolt.call(15.0, 3000.0, -0.045)},
		{"name": "b_stroke4", "transform": _view(n, 350.0, 12.0), "wait": 2.0, "call": bolt.call(15.0, 3000.0, -0.32)},
		{"name": "b_after", "transform": _view(n, 350.0, 12.0), "wait": 2.0, "call": bolt.call(15.0, 3000.0, -0.52)},
	]


## The tallest tower's rod over 1.2 km off within 15 degrees of azimuth
## `az` (degrees from north through east) seen from the roof.
func _rod_toward(az: float) -> Vector3:
	var best := Vector3.INF
	for t in _storm.towers:
		var d := Vector2(t.x - 28.0, t.z - 14.0)
		if d.length() > 1200.0 and absf(wrapf(rad_to_deg(atan2(d.x, -d.y)) - az, -180.0, 180.0)) < 15.0 and (best == Vector3.INF or t.y > best.y):
			best = t
	return best


## Rain QA views (QA_RAIN=1): the crossing, the avenue grazing, under an
## avenue head looking up into its cone, the alley, the roof, under the bus
## shelter, on the fire stair.
func _rain_shots() -> Array:
	var sy: Array = LAYOUT.STAIR_Y
	return [
		{"name": "r_cross", "transform": _view(Vector3(6.0, 0.0, 6.0), 40.0, 2.0), "wait": 3.0},
		{"name": "r_graze", "transform": _view(Vector3(4.0, 0.0, -12.0), 0.0, -4.0), "wait": 3.0},
		{"name": "r_lamp", "transform": _view(Vector3(5.5, 0.0, 25.0), 10.0, 18.0), "wait": 3.0},
		{"name": "r_alley", "transform": _view(Vector3(48.0, 0.15, 30.0), 10.0, 3.0), "wait": 3.0},
		{"name": "r_roof", "transform": _view(Vector3(25.0, LAYOUT.A_ROOF, 22.0), 300.0, 0.0), "wait": 3.0},
		{"name": "r_shelter", "transform": _view(Vector3(-12.5, 0.15, -34.0), 270.0, 2.0), "wait": 3.0},
		{"name": "r_stair", "transform": _view(Vector3(46.9, sy[3], 13.0), 20.0, -10.0), "wait": 3.0},
	]


## Ground QA views (QA_GROUND=1): the asphalt, its paint and puddles, the
## sidewalks and curbs, from standing, looking down and grazing, at the
## crossing, in the alley, from the roof, and where the near street meets
## the far ground.
func _ground_shots() -> Array:
	var roof: float = LAYOUT.A_ROOF
	return [
		{"name": "g_down", "transform": _view(Vector3(3.0, 0.0, -20.0), 180.0, -50.0), "wait": 3.0},
		{"name": "g_graze_av", "transform": _view(Vector3(4.0, 0.0, -12.0), 0.0, -4.0), "wait": 3.0},
		{"name": "g_graze_av_s", "transform": _view(Vector3(-3.0, 0.0, 14.0), 180.0, -6.0), "wait": 3.0},
		{"name": "g_cross", "transform": _view(Vector3(7.0, 0.0, 8.0), 225.0, -14.0), "wait": 3.0},
		{"name": "g_cross2", "transform": _view(Vector3(-6.0, 0.0, -4.0), 300.0, -10.0), "wait": 3.0},
		{"name": "g_street_e", "transform": _view(Vector3(22.0, 0.0, -2.0), 270.0, -5.0), "wait": 3.0},
		{"name": "g_walk", "transform": _view(Vector3(12.0, 0.15, 40.0), 0.0, -12.0), "wait": 3.0},
		{"name": "g_curb", "transform": _view(Vector3(10.5, 0.15, -30.0), 180.0, -25.0), "wait": 3.0},
		{"name": "g_alley", "transform": _view(Vector3(48.0, 0.15, 14.0), 180.0, -18.0), "wait": 3.0},
		{"name": "g_roof", "transform": _view(Vector3(25.0, roof, 22.0), 300.0, -30.0), "wait": 3.0},
		{"name": "g_roof_dn", "transform": _view(Vector3(20.0, roof, 10.8), 0.0, -55.0), "wait": 3.0},
		{"name": "g_far_n", "transform": _view(Vector3(2.0, 0.0, -50.0), 0.0, -3.0), "wait": 3.0},
		{"name": "g_far_w", "transform": _view(Vector3(-70.0, 0.0, 2.0), 90.0, -3.0), "wait": 3.0},
		{"name": "g_plaza", "transform": _view(Vector3(-25.0, 0.15, -15.0), 230.0, -12.0), "wait": 3.0},
	]


## Scale reference views (QA_FIGURES=1): each figure from a person's
## standing spot nearby (feet), looking at its chest.
func _scale_shots() -> Array:
	var views := {"lamp_av": Vector3(13.0, 0.15, 27.0), "lamp_st": Vector3(34.0, 0.15, 8.6), "door": Vector3(11.2, 0.15, 29.0),
			"shop": Vector3(10.5, 0.15, 23.5), "landing": Vector3(50.0, 0.15, 6.0), "corner": Vector3(2.0, 0.0, 18.0),
			"cross_av": Vector3(-6.0, 0.0, 14.0), "cross_st": Vector3(20.0, 0.15, -6.5), "parapet": Vector3(24.0, 21.0, 15.0),
			"bulkhead": Vector3(28.0, 21.0, 31.0), "shelter": Vector3(-10.5, 0.15, -25.0), "alley": Vector3(48.5, 0.15, 31.0),
			"hydrant": Vector3(14.0, 0.15, 25.0)}
	var out := []
	for k in views:
		var at: Vector3 = views[k]
		var t: Vector3 = QA_SPOTS[k][0] + Vector3(0, 1.2, 0)
		var d := t - (at + Vector3(0, 1.62, 0))
		var yaw := rad_to_deg(atan2(-d.x, -d.z))
		var pitch := rad_to_deg(atan2(d.y, Vector2(d.x, d.z).length()))
		out.append({"name": "scale_" + k, "transform": _view(at, yaw, pitch), "wait": 3.0})
	return out


## The harness's film: out of the roof door, to the parapet over the
## crossing, along the roof to the stair, down two storeys of it, then the
## crossing from the street.
func film() -> void:
	if OS.get_environment("QA_STORM") == "1":
		await _film_storm()
		return
	if OS.get_environment("QA_BOLTS") == "1":
		await _film_bolts()
		return
	if OS.get_environment("QA_RAIN") == "1":
		await _film_rain()
		return
	var t := arrival()
	player.teleport(t.origin, _yaw_of(t))
	await get_tree().create_timer(2.0).timeout
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	var roof: float = LAYOUT.A_ROOF + 1.6
	var sy: Array = LAYOUT.STAIR_Y
	var half: float = (sy[5] + sy[6]) * 0.5 + 1.7
	await _ride([o + Vector3(28, roof, 30), o + Vector3(20, roof, 20), o + Vector3(17, roof, 13)], deg_to_rad(55.0), 7.0, -0.35)
	await _ride([o + Vector3(17.2, roof, 13.2)], deg_to_rad(100.0), 3.0, 0.05)
	await _ride([o + Vector3(30, roof, 15), o + Vector3(43, roof, 13.1), o + Vector3(46.0, roof, 13.0)], deg_to_rad(250.0), 6.0, -0.1)
	await _ride([o + Vector3(46.9, roof, 13.4), o + Vector3(46.9, half, 16.4), o + Vector3(46.3, half, 17.2),
			o + Vector3(45.7, half, 16.4), o + Vector3(45.7, sy[5] + 1.7, 13.8)], deg_to_rad(10.0), 8.0, -0.2)
	await _ride([o + Vector3(30, 1.75, 8.0), o + Vector3(10, 1.75, 4.0), o + Vector3(0, 1.75, 0)], deg_to_rad(90.0), 9.0, 0.05)
	await _ride([o + Vector3(0, 1.75, -0.5)], deg_to_rad(180.0), 4.0, 0.08)
	await _ride([o + Vector3(0, 1.75, -1.0)], deg_to_rad(330.0), 4.0, 0.15)


## The rain film (QA_RAIN=1, ~40 s): under the bus shelter looking out at
## the rain beyond its roof and the drips off its edge, out into the rain
## to the avenue head, up into its cone, down at the rings in a puddle,
## then along the avenue to the crossing's signals.
func _film_rain() -> void:
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	var e: float = LAYOUT.WALK + (1.38 if Player.human_eye() else 1.62)
	player.teleport(o + Vector3(-12.9, LAYOUT.WALK, -35.0), deg_to_rad(270.0))
	await get_tree().create_timer(5.0).timeout
	await _ride([o + Vector3(-12.6, e, -34.6)], deg_to_rad(300.0), 3.0, 0.1)
	await _ride([o + Vector3(-10.2, e, -33.0), o + Vector3(-8.5, e - LAYOUT.WALK, -30.0)], deg_to_rad(330.0), 5.0, 0.05)
	await _ride([o + Vector3(-8.3, e - LAYOUT.WALK, -27.5)], deg_to_rad(345.0), 4.0, 0.55)
	await _ride([o + Vector3(-8.0, e - LAYOUT.WALK, -26.0)], deg_to_rad(20.0), 4.0, -0.75)
	# (Rides chained: between them the player has no collision.)
	await _ride([o + Vector3(-7.9, e - LAYOUT.WALK, -25.7)], deg_to_rad(28.0), 3.0, -0.7)
	await _ride([o + Vector3(-7.0, e - LAYOUT.WALK, -20.0), o + Vector3(-5.0, e - LAYOUT.WALK, -14.0)], deg_to_rad(10.0), 7.0, 0.0)
	await _ride([o + Vector3(-3.0, e - LAYOUT.WALK, -9.0)], deg_to_rad(330.0), 5.0, 0.12)
	await _ride([o + Vector3(-2.0, e - LAYOUT.WALK, -7.0)], deg_to_rad(60.0), 4.0, 0.05)


## The storm film (QA_STORM=1, ~45 s, record with --fixed-fps 30): on the
## roof in moderate rain looking north-north-east at the downtown's towers
## in the scud as a burst starts and the rain thickens; a flash to ground
## 2.4 km off in the north, its bolt under the base, its thunder 7 s later;
## to the parapet over the crossing; a strong flash (three times the
## median) 1.8 km off in the north-west lights the city, its thunder 5 s
## after; then up at the deck as it rolls.
func _film_storm() -> void:
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	var e: float = LAYOUT.A_ROOF + (1.38 if Player.human_eye() else 1.62)
	_storm.calm(1e5)
	player.teleport(o + Vector3(28.0, LAYOUT.A_ROOF, 16.0), deg_to_rad(345.0))
	await get_tree().create_timer(2.0).timeout
	_storm.burst(16.0, 1000.0, 35.0)
	_storm.flash(deg_to_rad(5.0), 2400.0, true, true, 5.0, 1.0)
	await _ride([o + Vector3(27.5, e, 13.5)], deg_to_rad(352.0), 9.0, 0.1)
	await _ride([o + Vector3(20.0, e, 12.0)], deg_to_rad(59.0), 8.0, -0.3)
	_storm.flash(deg_to_rad(320.0), 1800.0, true, false, 5.0, 3.0)
	await _ride([o + Vector3(17.5, e, 11.5)], deg_to_rad(59.0), 7.0, -0.3)
	await _ride([o + Vector3(17.3, e, 11.4)], deg_to_rad(50.0), 7.0, -0.12)
	await _ride([o + Vector3(17.6, e, 12.0)], deg_to_rad(20.0), 7.0, 0.6)
	await _ride([o + Vector3(18.0, e, 12.5)], deg_to_rad(340.0), 5.0, 0.1)


## The bolt film (QA_BOLTS=1, ~22 s, --fixed-fps 30): on the roof in a
## burst's rain looking north at the downtown's towers: a flash to ground
## 3 km off behind them (five strokes), one 5 km off to the north-west,
## one onto a tower's rod, a turn to the west downtown for one 2 km off,
## then one ~1 km off with its crack 3 s later.
func _film_bolts() -> void:
	var o := Vector3(0.0, LEVEL_Y, 0.0)
	var e: float = LAYOUT.A_ROOF + (1.38 if Player.human_eye() else 1.62)
	_storm.calm(1e5)
	_storm.burst(0.5, 1000.0, 25.0)
	player.teleport(o + Vector3(28.0, LAYOUT.A_ROOF, 14.0), deg_to_rad(350.0))
	await _ride([o + Vector3(28.0, e, 14.0)], deg_to_rad(350.0), 1.0, 0.2)
	_storm.flash(deg_to_rad(15.0), 3000.0, true, true, 1.0)
	_storm.flash(deg_to_rad(330.0), 5000.0, true, true, 4.5)
	_storm.strike(_rod_toward(25.0), 8.0)
	await _ride([o + Vector3(27.8, e, 14.1)], deg_to_rad(345.0), 10.0, 0.2)
	await _ride([o + Vector3(24.0, e, 18.0)], deg_to_rad(75.0), 3.0, 0.15)
	_storm.flash(deg_to_rad(290.0), 2000.0, true, true, 0.8)
	_storm.flash(deg_to_rad(300.0), 1000.0, true, true, 4.5)
	await _ride([o + Vector3(23.8, e, 18.2)], deg_to_rad(70.0), 9.0, 0.3)


func _ride(eyes: Array, yaw: float, time: float, pitch: float) -> void:
	var path := PackedVector3Array([player.camera.global_position])
	for e in eyes:
		path.append(e)
	var st := {"done": false}
	player.ride(path, yaw, time, func() -> void: st.done = true, pitch)
	while not st.done and is_inside_tree():
		await get_tree().process_frame
