extends SideLevel
## The Crawlspace: the supply trunk above an office floor's suspended
## ceiling. Galvanised rectangular duct, 36 x 30 in clear inside, in 5 ft
## sections with sealed transverse joints and cross-broken panels; tees,
## mitred elbows with turning vanes (one torn half out, so you can get round;
## one whole, so you can't), access doors, an insulated run with liner pins,
## an opposed-blade damper with a tube-axial fan behind it, and 24 x 12 in
## eggcrate registers in the duct floor looking down through the ceiling into
## empty offices that are still lit. You crawl the whole way (there is no
## room to do anything else) with your torch.
##
## What happens: the sheet metal pops as warm air comes through (a run of
## pops travelling along the duct at the air's speed, dust shaken off the
## seams), the air comes in pulses, dust hangs in the torch beam, the fan
## behind the damper spins up when you get near and the damper blades
## shudder, something crawls in the parallel duct keeping pace with you,
## a light below fails, an occupancy sensor sees something in an empty
## office, and a pale hand pulls back round a bend ahead. The way out is the
## return grille at the far end: push it out and drop into the office.
##
## Layout and real-world sizes: assets/levels/crawlspace/SPEC.md (and
## tools/blender/levels/crawlspace.py, which builds the kits).

const NAME := "Level 2.1 - The Crawlspace"
const INTRO := "Hot air. Sheet metal. No room to turn round."
const DIR := "res://assets/levels/crawlspace/"
const TEX := "res://assets/levels/crawlspace/textures"

## Sizes (m), as the Blender script.
const W := 0.9144
const H := 0.762
const SECTION := 1.524
const CEIL := -0.15 - 0.015875
const ROOM_H := 2.7432
## Air speed in the trunk (m/s): the warm front that sets off the pops.
const AIR_SPEED := 6.0
## Fan: 28 in tube-axial, direct drive.
const FAN_RPM := 1725.0
const FAN_R := 0.3556
## The torch's output in here (its beam is the game's; a hand-held LED torch
## of a few hundred lumens, a hand's length from sheet metal, needs less
## than the open Backrooms give it to keep from burning out the view).
const TORCH := 0.45

## The network (Blender XY: x east, y north), as the Blender script.
const NODES := {
	"n0": Vector2(0, 0), "n1": Vector2(0, 12), "n2": Vector2(0, 24), "n3": Vector2(-10, 24),
	"fan_end": Vector2(-10, 15), "n5": Vector2(-10, 36), "w_end": Vector2(-17, 36), "n6": Vector2(4, 36),
	"s_end": Vector2(4, 29), "n7": Vector2(4, 46), "n8": Vector2(9, 12), "n8_end": Vector2(9, 18),
}
## Ducts you can get along (the n8 -> n8_end stub is behind whole vanes).
const EDGES := [["n0", "n1"], ["n1", "n2"], ["n2", "n3"], ["n3", "fan_end"], ["n3", "n5"], ["n5", "w_end"],
		["n5", "n6"], ["n6", "s_end"], ["n6", "n7"], ["n1", "n8"]]
## Registers (Blender XY), the light group of the office under each (-1
## always on, -2 dark).
const REGISTERS := [[Vector2(0, 5.5), -1], [Vector2(5, 12), -2], [Vector2(-5, 24), -1], [Vector2(-10, 16), 1],
		[Vector2(-10, 31), 0], [Vector2(-2, 36), 2], [Vector2(4, 44), 3], [Vector2(9, 15.6), -2]]
const EXIT_AT := Vector2(4, 44)
const DAMPER_Y := 20.6
const FAN_Y := 18.2
## The parallel duct (hidden) beside n3 -> n5, 1.3 m west of it.
const TWIN_X := -11.35
const CCT := Color(1.0, 0.95, 0.88)        # 4000 K

var _o := Vector3(0.0, LEVEL_Y, 0.0)
var _rng := RandomNumberGenerator.new()
var _events := true
var _t := 0.0
var _torch_energy := -1.0
# Sounds.
var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _foley: AudioStreamPlayer
var _air: AudioStreamPlayer
var _air_db := -21.0
var _pulse_t := 6.0
var _pulse := 0.0
var _pulse_len := 4.0
# Pops.
var _pop_next := 14.0
var _pops: Array = []            # [time, position, near]
var _big_pop_done := false
# Dust.
var _motes: CPUParticles3D
var _mote_mat: ShaderMaterial
var _puff: CPUParticles3D
# Fan and damper.
var _fan: Node3D
var _fan_blades: MeshInstance3D
var _fan_blur: MeshInstance3D
var _blur_mat: StandardMaterial3D
var _fan_speed := 0.3            # rev/s (windmilling in the draught)
var _fan_target := 0.3
var _fan_angle := 0.0
var _fan_state := 0              # 0 idle, 1 armed, 2 running, 3 coasting
var _fan_t := 0.0
var _fan_audio: AudioStreamPlayer3D
var _fan_loop: AudioStreamPlayer3D
var _damper_blades: Array[Node3D] = []
var _damper_open := 0.85         # rad: set about half open (balanced)
# The twin duct.
var _twin_state := 0             # 0 waiting, 1 pacing, 2 stopped, 3 done
var _twin_steps := 0
var _twin_last_step := 0.0
var _twin_t := 0.0
var _twin_queue: Array = []      # [time, stream, pos, db]
# Lights below.
var _faulty := 1.0
var _faulty_t := 5.0
var _faulty_seq: Array = []      # [time, level]
var _occupancy := 0.0
var _occ_state := 0
var _occ_t := 0.0
# The hand.
var _hand: EntityBody
var _hand_state := 0             # 0 waiting, 1 hesitating, 2 withdrawing, 3 gone
var _hand_t := 0.0
var _hand_from := Vector3.ZERO
var _hand_pose := 0.0
var _hand_audio: AudioStreamPlayer3D
# The exit grille.
var _grille: Node3D
var _exit: LevelEntrance


func _g(b: Vector2, z := 0.0) -> Vector3:
	return _o + Vector3(b.x, z, -b.y)


# ----------------------------------------------------------------- build ---

func build(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed
	var lm := DIR + "lightmaps/"
	var galv := {"texture": "duct_galv", "scale": 1.0, "metallic": 0.6, "roughness": 0.55, "specular": 0.55,
			"normal_depth": 0.6}
	var surfaces := {
		"duct_galv": galv,
		"duct_top": galv.merged({"texture": "duct_top"}, true),
		"duct_floor": {"texture": "duct_floor", "scale": 1.0, "metallic": 0.2, "roughness": 1.0, "specular": 0.45,
				"normal_depth": 0.5},
		"vane": galv,
		"mastic": {"color": Color(0.55, 0.57, 0.58), "roughness": 0.95, "specular": 0.25},
		"liner": {"texture": "liner", "scale": 2.0, "roughness": 1.0, "specular": 0.2},
		"liner_pin": {"color": Color(0.32, 0.32, 0.31), "roughness": 0.7, "metallic": 0.3},
		"grille": {"color": Color(0.86, 0.86, 0.84), "roughness": 0.45, "specular": 0.5},
		"gasket": {"color": Color(0.05, 0.05, 0.05), "roughness": 0.8},
		"fan_paint": {"color": Color(0.27, 0.31, 0.30), "roughness": 0.55},
		"carpet": {"texture": "carpet", "scale": 0.5, "roughness": 1.0, "specular": 0.2},
		"ceiling_tile": {"texture": "ceiling_tile", "scale": 1.0 / (6.0 * 0.6096), "roughness": 1.0, "specular": 0.2},
		"wall_paint": {"texture": "wall_paint", "scale": Vector2(0.35, 0.7), "roughness": 1.0, "specular": 0.3},
		"base": {"color": Color(0.1, 0.1, 0.1), "roughness": 0.8},
		"door": {"color": Color(0.6, 0.56, 0.5), "roughness": 0.6},
		"door_frame": {"color": Color(0.28, 0.28, 0.29), "roughness": 0.5, "metallic": 0.3},
		"troffer_frame": {"color": Color(0.85, 0.85, 0.84), "roughness": 0.5},
		"plate": {"color": Color(0.9, 0.89, 0.86), "roughness": 0.6},
		"entry_glow": {"color": Color(0.78, 0.68, 0.42), "roughness": 0.9},
		"lamp": {"color": Color(1.0, 0.98, 0.94), "emit": 5.0},
		"screw": {"color": Color(0.55, 0.55, 0.53), "roughness": 0.35, "metallic": 0.8},
		"dust": {"texture": "duct_floor", "color": Color(0.95, 0.92, 0.88), "scale": 1.0, "roughness": 1.0,
				"specular": 0.2},
		"tape": {"color": Color(0.7, 0.71, 0.72), "roughness": 0.3, "metallic": 0.7},
		"cable_tie": {"color": Color(0.08, 0.08, 0.08), "roughness": 0.6},
		"laminate": {"color": Color(0.6, 0.57, 0.52), "roughness": 0.5},
		"desk_metal": {"color": Color(0.22, 0.22, 0.23), "roughness": 0.5, "metallic": 0.4},
		"chair_fabric": {"color": Color(0.07, 0.07, 0.08), "roughness": 0.95},
		"cabinet": {"color": Color(0.66, 0.65, 0.6), "roughness": 0.5, "metallic": 0.2},
		"monitor": {"color": Color(0.02, 0.02, 0.02), "roughness": 0.25, "specular": 0.6},
		"whiteboard": {"color": Color(0.9, 0.9, 0.88), "roughness": 0.2, "specular": 0.6},
	}
	for g in 4:
		surfaces["lamp_g%d" % g] = {"color": Color(1.0, 0.98, 0.94), "emit": 5.0, "group": g}
	# (each kit is one mesh spanning the network, so no low_view_range: it
	# would hide the whole kit by its centre; the far plane and fog do it)
	low_view_range = 0.0
	load_kit(DIR + "crawl_rooms.glb", lm + "crawl_rooms.png", TEX, surfaces, lm + "crawl_rooms_groups.png")
	load_kit(DIR + "crawl_duct.glb", lm + "crawl_duct.png", TEX, surfaces, lm + "crawl_duct_groups.png")
	set_light_group(0, CCT, 1.0)
	set_light_group(1, CCT, 1.0)
	set_light_group(2, CCT, 0.0)
	set_light_group(3, CCT, 1.0)
	_load_sounds()
	_build_fan()
	_build_grille()
	_build_dust()
	_build_hand()
	_build_audio()
	# The way out: the return grille at the far end (an exit with no look of
	# its own: open_exit() plays the grille and the drop). Its prompt sits on
	# the grille (LevelEntrance puts it 1.05 m up and 0.08 m out).
	var at := _g(EXIT_AT, 0.06)
	_exit = add_exit(Transform3D(Basis(), at - Vector3(0.0, 1.05, 0.08)), "none", "",
			{"label": "Push the grille out", "walk_in": false})
	environment = make_environment({"background": Color(0, 0, 0), "fog": Color(0.012, 0.011, 0.01),
			"fog_density": 0.05, "exposure": 1.15, "glow": 0.2, "saturation": 0.92})
	# Let the torch's hot spot on sheet metal a hand's length away roll off
	# instead of clipping.
	environment.tonemap_white = maxf(environment.tonemap_white, 6.0)


func _load_sounds() -> void:
	for f in DirAccess.get_files_at(DIR + "audio"):
		var n := f.trim_suffix(".import")
		if n.ends_with(".ogg") and not _streams.has(n.get_basename()):
			_streams[n.get_basename()] = load(DIR + "audio/" + n)
	for i in 8:
		var a := AudioStreamPlayer3D.new()
		a.bus = "World"
		a.unit_size = 2.0
		a.max_distance = 30.0
		a.attenuation_filter_cutoff_hz = 9000.0
		add_child(a)
		_pool.append(a)
	_foley = AudioStreamPlayer.new()
	_foley.bus = "World"
	add_child(_foley)


func _pick(prefix: String) -> AudioStream:
	var list: Array = []
	for k in _streams:
		if String(k).begins_with(prefix) and (prefix.contains("heavy") or not String(k).contains("heavy")):
			list.append(_streams[k])
	return list[_rng.randi() % list.size()] if not list.is_empty() else null


## A one-shot at a place (from the pool).
func _play_at(st: AudioStream, at: Vector3, db := -6.0, pitch := 1.0, filter := 9000.0) -> AudioStreamPlayer3D:
	if st == null:
		return null
	var a := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	a.stream = st
	a.volume_db = db
	a.pitch_scale = pitch
	a.attenuation_filter_cutoff_hz = filter
	a.global_position = at
	a.play()
	return a


func _build_audio() -> void:
	# The trunk's air (everywhere) and the distant air handler.
	_air = add_loop(_streams.get("air_loop"), Vector3.INF, _air_db) as AudioStreamPlayer
	add_loop(_streams.get("duct_hum"), Vector3.INF, -24.0, {"pitch": 0.9})
	# Each register: air through it, and the office's lights humming below.
	for r in REGISTERS:
		var p := _g(r[0], 0.05)
		add_loop(_streams.get("grille_air"), p, -19.0, {"unit_size": 1.2, "max_distance": 9.0,
				"pitch": _rng.randf_range(0.9, 1.1)})
		var g: int = r[1]
		if g == 0:
			add_loop(_streams.get("flicker_loop"), _g(r[0], -0.5), -16.0, {"unit_size": 1.5, "max_distance": 12.0,
					"filter": 3500.0})
		elif g != -2:
			add_loop(_streams.get("room_hum"), _g(r[0], -0.5), -25.0, {"unit_size": 1.5, "max_distance": 10.0,
					"filter": 3000.0})
	_fan_loop = add_loop(_streams.get("fan_loop"), _g(Vector2(-10, FAN_Y)), -80.0,
			{"unit_size": 3.0, "max_distance": 30.0}) as AudioStreamPlayer3D
	_fan_audio = AudioStreamPlayer3D.new()
	_fan_audio.bus = "World"
	_fan_audio.unit_size = 3.0
	_fan_audio.max_distance = 30.0
	add_child(_fan_audio)
	_fan_audio.global_position = _g(Vector2(-10, FAN_Y), 0.38)
	_hand_audio = AudioStreamPlayer3D.new()
	_hand_audio.bus = "World"
	_hand_audio.unit_size = 2.5
	add_child(_hand_audio)


## Boxes merged into one mesh (one draw call): [size, Transform3D] each.
static func _boxes(list: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in list:
		var bm := BoxMesh.new()
		bm.size = b[0]
		st.append_from(bm, 0, b[1])
	st.generate_tangents()
	return st.commit()


## The damper's blades and the fan's rotor (the frames are in the kit).
func _build_fan() -> void:
	var dark := Color(0.035, 0.035, 0.035)
	var blade_m := flat_material({"texture": "duct_galv", "metallic": 0.35, "roughness": 0.9, "scale": 0.6},
			dark, Vector4(0.0, 0.06, 0.0, 0.0), TEX)
	# Opposed-blade damper: five 6 in blades on 1/2 in shafts, alternate
	# blades turning opposite ways.
	var dc := _g(Vector2(-10, DAMPER_Y))
	for i in 5:
		var piv := Node3D.new()
		add_child(piv)
		piv.global_position = dc + Vector3(0.0, 0.0254 + (i + 0.5) * (H - 0.0508) / 5.0, 0.0)
		var mi := MeshInstance3D.new()
		# (Shut, a blade stands across the duct: 152 mm high, 1.6 mm thick,
		# its edges folded for stiffness.)
		mi.mesh = _boxes([[Vector3(W - 0.06, 0.1524, 0.0016), Transform3D()],
				[Vector3(W - 0.04, 0.0127, 0.0127), Transform3D()],
				[Vector3(W - 0.06, 0.01, 0.006), Transform3D(Basis(), Vector3(0, 0.071, 0.002))],
				[Vector3(W - 0.06, 0.01, 0.006), Transform3D(Basis(), Vector3(0, -0.071, -0.002))]])
		mi.material_override = blade_m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		piv.add_child(mi)
		piv.set_meta("dir", 1.0 if i % 2 == 0 else -1.0)
		_damper_blades.append(piv)
	# Rotor: hub and six pitched blades, on the motor shaft facing the damper.
	_fan = Node3D.new()
	add_child(_fan)
	_fan.global_position = _g(Vector2(-10, FAN_Y + 0.06), H * 0.5)
	var rotor := []
	rotor.append([Vector3(0.16, 0.16, 0.09), Transform3D()])
	for k in 6:
		var a := TAU * k / 6.0
		var tw := Basis(Vector3.RIGHT, 0.42)     # blade pitch
		var xf := Transform3D(Basis(Vector3.BACK, a) * tw, Basis(Vector3.BACK, a) * Vector3(0.2, 0.0, 0.0))
		rotor.append([Vector3(0.27, 0.11, 0.004), xf])
	_fan_blades = MeshInstance3D.new()
	_fan_blades.mesh = _boxes(rotor)
	_fan_blades.material_override = flat_material({"color": Color(0.5, 0.52, 0.5), "roughness": 0.4,
			"metallic": 0.3}, dark, Vector4(0.0, 0.1, 0.0, 0.0))
	_fan_blades.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fan.add_child(_fan_blades)
	# Spinning fast, the blades are a blur.
	_fan_blur = MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = FAN_R - 0.04
	disc.bottom_radius = FAN_R - 0.04
	disc.height = 0.004
	disc.radial_segments = 24
	disc.rings = 1
	_fan_blur.mesh = disc
	_fan_blur.rotation = Vector3(PI * 0.5, 0, 0)
	_blur_mat = StandardMaterial3D.new()
	_blur_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blur_mat.albedo_color = Color(0.42, 0.44, 0.42, 0.0)
	_blur_mat.roughness = 0.5
	_blur_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_fan_blur.material_override = _blur_mat
	_fan_blur.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_fan_blur.visible = false
	_fan.add_child(_fan_blur)


## The exit's return grille (24 x 24 in, fixed bars at 45 deg on 3/4 in
## centres), a moving part: it sits in the ceiling below the duct floor.
func _build_grille() -> void:
	var s := 0.6096
	var fr := 0.03175
	var dep := 0.0254
	var parts := []
	for sx in [-1.0, 1.0]:
		parts.append([Vector3(s + 2 * fr, 0.004, fr), Transform3D(Basis(), Vector3(0, -0.002, sx * (s * 0.5 + fr * 0.5)))])
		parts.append([Vector3(fr, 0.004, s), Transform3D(Basis(), Vector3(sx * (s * 0.5 + fr * 0.5), -0.002, 0))])
		parts.append([Vector3(s, dep, 0.003), Transform3D(Basis(), Vector3(0, dep * 0.5, sx * s * 0.5))])
		parts.append([Vector3(0.003, dep, s), Transform3D(Basis(), Vector3(sx * s * 0.5, dep * 0.5, 0))])
	var n := int(s / 0.01905)
	for i in n:
		var z := -s * 0.5 + (i + 0.5) * s / n
		parts.append([Vector3(s, dep, 0.0025), Transform3D(Basis(Vector3.RIGHT, deg_to_rad(45.0)), Vector3(0, dep * 0.5, z))])
	_grille = Node3D.new()
	add_child(_grille)
	_grille.global_position = _g(EXIT_AT, CEIL - 0.004)
	var mi := MeshInstance3D.new()
	mi.mesh = _boxes(parts)
	mi.material_override = flat_material({"color": Color(0.86, 0.86, 0.84), "roughness": 0.45},
			Color(0.06, 0.06, 0.06), Vector4(0.0, 0.0, 0.0, 0.55))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_grille.add_child(mi)


func _build_dust() -> void:
	_mote_mat = ShaderMaterial.new()
	_mote_mat.shader = load(DIR + "dust_mote.gdshader")
	var q := QuadMesh.new()
	q.size = Vector2(0.004, 0.004)
	_motes = CPUParticles3D.new()
	_motes.mesh = q
	_motes.material_override = _mote_mat
	_motes.amount = 90 if low else 220
	_motes.lifetime = 9.0
	_motes.preprocess = 9.0
	_motes.local_coords = false
	_motes.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_motes.emission_box_extents = Vector3(1.4, 0.36, 1.4)
	_motes.direction = Vector3(0, 1, 0)
	_motes.spread = 180.0
	_motes.initial_velocity_min = 0.0
	_motes.initial_velocity_max = 0.02
	_motes.gravity = Vector3(0, -0.004, 0)
	_motes.damping_min = 0.0
	_motes.damping_max = 0.01
	_motes.scale_amount_min = 0.5
	_motes.scale_amount_max = 1.6
	_motes.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_motes.visibility_aabb = AABB(Vector3(-50, -5, -50), Vector3(100, 10, 100))
	add_child(_motes)
	# Dust shaken off a seam by a pop (one shot, moved where it's needed).
	var q2 := QuadMesh.new()
	q2.size = Vector2(0.006, 0.006)
	_puff = CPUParticles3D.new()
	_puff.mesh = q2
	_puff.material_override = _mote_mat
	_puff.amount = 60 if low else 140
	_puff.lifetime = 4.0
	_puff.one_shot = true
	_puff.explosiveness = 0.85
	_puff.emitting = false
	_puff.local_coords = false
	_puff.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_puff.emission_box_extents = Vector3(0.42, 0.005, 0.03)
	_puff.direction = Vector3(0, -1, 0)
	_puff.spread = 35.0
	_puff.initial_velocity_min = 0.05
	_puff.initial_velocity_max = 0.25
	_puff.gravity = Vector3(0, -0.25, 0)
	_puff.damping_min = 0.3
	_puff.damping_max = 0.6
	_puff.scale_amount_min = 0.4
	_puff.scale_amount_max = 1.4
	_puff.visibility_aabb = AABB(Vector3(-2, -2, -2), Vector3(4, 4, 4))
	add_child(_puff)


## The pale one in the south spur off n6, lying on its front with its left
## arm round the corner and its hand flat on the junction's floor.
func _build_hand() -> void:
	_hand = add_figure(Transform3D(), "crawler", Color(0.75, 0.74, 0.72))
	# Not a clean dummy: skin gone grey-yellow and grimed with duct dust,
	# matte (it is only ever glimpsed, at the edge of the beam).
	for m in _hand._mats:
		m.set_shader_parameter("roughness", 0.95)
		var t: Color = m.get_shader_parameter("tint")
		m.set_shader_parameter("tint", Color(t.r * 0.6, t.g * 0.57, t.b * 0.5, t.a))
	_hand_from = _g(Vector2(4.2, 33.75), 0.15)
	_place_hand(0.0, 0.0)
	_hand.set_env_light(Color(0.05, 0.05, 0.05))


## Lying face down, head north. back: how far it has been pulled back (m);
## lift: the arm coming up off the floor as it goes.
func _place_hand(back: float, lift: float) -> void:
	var y_axis := Vector3(0, 0, -1)       # its head: north
	var z_axis := Vector3(0, -1, 0)       # its front: the floor
	var x_axis := y_axis.cross(z_axis)    # its left: west
	var roll := sin(back * 5.0) * 0.06 * clampf(back, 0.0, 1.0)
	var bas := Basis(x_axis, y_axis, z_axis).rotated(y_axis, roll)
	_hand.global_transform = Transform3D(bas, _hand_from + Vector3(0, 0, back))
	_hand_pose = lift


func _pose_hand() -> void:
	if _hand == null or _hand.skeleton == null:
		return
	var l := _hand_pose
	_hand._aim_all({
		"pelvis": Vector3(0, 1, 0), "spine_01": Vector3(0, 1, 0.02), "spine_02": Vector3(0, 1, 0.03),
		"spine_03": Vector3(0, 1, 0.0), "neck_01": Vector3(0, 1, 0.25), "head": Vector3(0.1, 0.6, 1.0),
		# Left arm (its left is west): up past the head and round the corner.
		"upperarm_l": Vector3(0.45 + 0.1 * l, 1, 0.12 - 0.1 * l), "lowerarm_l": Vector3(0.55, 1, 0.2 - 0.25 * l),
		"hand_l": Vector3(1.0, 0.35, 0.5 - 0.6 * l),
		# Right arm by its side, legs straight out behind.
		"upperarm_r": Vector3(-0.15, -1, 0.1), "lowerarm_r": Vector3(-0.08, -1, 0.15), "hand_r": Vector3(-0.05, -1, 0.3),
		"thigh_l": Vector3(0.06, -1, 0), "calf_l": Vector3(0.04, -1, -0.05), "foot_l": Vector3(0, -0.3, -1),
		"thigh_r": Vector3(-0.06, -1, 0), "calf_r": Vector3(-0.04, -1, -0.05), "foot_r": Vector3(0, -0.3, -1),
	})


# --------------------------------------------------------------- the game ---

func on_enter() -> void:
	player.force_crawl = true
	_torch_energy = player.flashlight.light_energy
	player.flashlight.light_energy = _torch_energy * TORCH
	player.footstep.connect(_on_step)
	var cs := get_tree().current_scene
	_events = cs == null or not String(cs.scene_file_path).contains("level_shots")


func on_leave() -> void:
	if player and _torch_energy >= 0.0:
		player.flashlight.light_energy = _torch_energy
	if player and player.footstep.is_connected(_on_step):
		player.footstep.disconnect(_on_step)


func arrival() -> Transform3D:
	return Transform3D(Basis(), _g(Vector2(0, 0.05)))     # facing north (-Z)


func wants_flashlight() -> bool:
	return true


func surface_at(_p: Vector3) -> int:
	return Player.SURF_METAL


func camera_far() -> float:
	return 18.0 if low else 30.0


## Sheet metal: a small, bright, ringing box.
func reverb() -> Dictionary:
	return {"room": 0.28, "damp": 0.15, "wet": 0.34}


func light_at(p: Vector3) -> Color:
	var c := Color(0.012, 0.012, 0.012)
	for r in REGISTERS:
		var g: int = r[1]
		if g == -2:
			continue
		var k := 1.0
		if g == 0:
			k = _faulty
		elif g == 2:
			k = _occupancy
		var d := p.distance_to(_g(r[0], 0.2))
		c += Color(0.3, 0.29, 0.27) * k * exp(-d * d * 1.6)
	return c


func albedo_at(_p: Vector3, _n: Vector3) -> Color:
	return Color(0.5, 0.52, 0.54)


func warm_materials() -> Array[Material]:
	var out := super()
	out.append(_mote_mat)
	out.append(_blur_mat)
	out.append_array(EntityBody.warm_materials())
	return out


func save_state() -> Dictionary:
	return {"twin": _twin_state, "hand": _hand_state >= 2, "big_pop": _big_pop_done}


func load_state(d: Dictionary) -> void:
	_twin_state = 3 if int(d.get("twin", 0)) > 0 else 0
	_big_pop_done = bool(d.get("big_pop", false))
	if d.get("hand", false):
		_hand_state = 3
		_hand.visible = false


## Where you are in the network (Blender XY) and which way you face.
func _me() -> Vector2:
	var p := player.global_position - _o
	return Vector2(p.x, -p.z)


func _facing() -> Vector2:
	var f := -player.camera.global_basis.z
	return Vector2(f.x, -f.z).normalized()


func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	_update_dust(delta)
	_update_air(delta)
	_update_fan(delta)
	_update_lights(delta)
	_update_hand(delta)
	_update_twin(delta)
	_update_pops(delta)


# -------------------------------------------------------------- crawling ---

## Your own crawl on sheet metal: each pull, an elbow or knee knocks the
## panel (and now and then the panel under you gives with a dull pop).
func _on_step(_surface: int, _strength: float) -> void:
	if not player.crawling:
		return
	_foley.stream = _pick("crawl_")
	_foley.volume_db = _rng.randf_range(-13.0, -9.0)
	_foley.pitch_scale = _rng.randf_range(0.9, 1.08)
	_foley.play()
	if _rng.randf() < 0.45:
		_play_at(_pick("brush_"), player.global_position + Vector3.UP * 0.2, -20.0, _rng.randf_range(0.9, 1.1))
	if _rng.randf() < 0.07:
		_play_at(_pick("flex_"), player.global_position + Vector3.DOWN * 0.05, -17.0, _rng.randf_range(0.8, 1.0), 2500.0)
		shake(0.003, 0.35)
	if _twin_state == 1:
		_twin_steps += 1
		_twin_last_step = _t
		var p := _me()
		_twin_queue.append([_t + _rng.randf_range(0.16, 0.26), _pick("knock_"),
				_g(Vector2(TWIN_X, p.y + 0.5), 0.25), -9.0 + _rng.randf_range(-2.0, 1.0)])


# ------------------------------------------------------------------- air ---

## The air comes in pulses (a VAV box hunting upstream): it swells for a few
## seconds, the dust drifts harder, then it settles.
func _update_air(delta: float) -> void:
	_pulse_t -= delta
	if _pulse_t <= 0.0:
		_pulse_t = _rng.randf_range(9.0, 18.0)
		_pulse_len = _rng.randf_range(3.0, 5.5)
		_pulse = 0.0001
	if _pulse > 0.0:
		_pulse += delta / _pulse_len
		if _pulse >= 1.0:
			_pulse = 0.0
	var env := _pulse_env()
	if _air:
		_air.volume_db = _air_db + env * 5.0
		_air.pitch_scale = 1.0 + env * 0.06
	_motes.gravity = Vector3(0, -0.004, 0) + _duct_dir() * (0.004 + env * 0.03)


func _pulse_env() -> float:
	var e := sin(clampf(_pulse, 0.0, 1.0) * PI)
	return e * e


## The duct you're in (world direction of the air: away from n0).
func _duct_dir() -> Vector3:
	var e := _nearest_edge(_me())
	var a: Vector2 = NODES[e[0]]
	var b: Vector2 = NODES[e[1]]
	var d := (b - a).normalized()
	return Vector3(d.x, 0.0, -d.y)


func _nearest_edge(p: Vector2) -> Array:
	var best: Array = EDGES[0]
	var bd := INF
	for e in EDGES:
		var a: Vector2 = NODES[e[0]]
		var b: Vector2 = NODES[e[1]]
		var q := Geometry2D.get_closest_point_to_segment(p, a, b)
		var d := q.distance_to(p)
		if d < bd:
			bd = d
			best = e
	return best


# ------------------------------------------------------------------ dust ---

func _update_dust(_delta: float) -> void:
	var cam := player.camera.global_transform
	_motes.global_position = cam.origin + (-cam.basis.z) * 1.0
	_motes.global_position.y = _o.y + H * 0.5
	var fl := player.flashlight.global_transform
	_mote_mat.set_shader_parameter("torch_pos", fl.origin)
	_mote_mat.set_shader_parameter("torch_dir", -fl.basis.z)
	_mote_mat.set_shader_parameter("torch_on", 1.0 if player.flashlight_on else 0.0)


# ------------------------------------------------------------------ pops ---

## Every so often warm air reaches a stretch of duct and the panels pop one
## after another as the front passes, at the air's speed: a run of pops
## coming at you down the duct, past you, and away.
func _update_pops(delta: float) -> void:
	if not _events:
		return
	var me := _me()
	if not _big_pop_done and absf(me.x) < 0.5 and me.y > 17.0 and me.y < 21.0:
		_big_pop_done = true
		_start_pops(true)
	_pop_next -= delta
	if _pop_next <= 0.0:
		_pop_next = _rng.randf_range(18.0, 34.0)
		_start_pops(false)
	var i := 0
	while i < _pops.size():
		var p: Array = _pops[i]
		if _t >= p[0]:
			_pop(p[1], p[2])
			_pops.remove_at(i)
		else:
			i += 1


func _start_pops(big: bool) -> void:
	# The joints along your duct, from well upwind of you to past you.
	var e := _nearest_edge(_me())
	var a: Vector2 = NODES[e[0]]
	var b: Vector2 = NODES[e[1]]
	var d := (b - a).normalized()
	var me := _me()
	var s0 := (me - a).dot(d)
	var length := a.distance_to(b)
	var first := s0 - (9.0 if big else _rng.randf_range(4.0, 10.0))
	var last := s0 + (6.0 if big else _rng.randf_range(2.0, 6.0))
	var s := W * 0.5 + ceilf((maxf(first, 0.5) - W * 0.5) / SECTION) * SECTION
	var t0 := _t + 0.3
	while s < minf(last, length - 0.5):
		if big or _rng.randf() < 0.75:
			var at := a + d * s
			var near := absf(s - s0) < 1.2
			_pops.append([t0 + (s - first) / AIR_SPEED + _rng.randf_range(-0.05, 0.05),
					_g(at, H - 0.02), near])
		s += SECTION


func _pop(at: Vector3, near: bool) -> void:
	var d := at.distance_to(player.camera.global_position)
	if near or d < 1.3:
		_play_at(_pick("bang_"), at, -4.0, _rng.randf_range(0.85, 1.05))
		_play_at(_pick("pop_"), at, -6.0, _rng.randf_range(0.8, 1.0))
		shake(0.012, 0.5)
		_puff.global_position = at
		_puff.restart()
	else:
		_play_at(_pick("pop_"), at, -5.0, _rng.randf_range(0.82, 1.15))
		if d < 4.0:
			shake(0.003, 0.25)


# ---------------------------------------------------------------- the fan ---

## Behind the damper a tube-axial fan windmills in the draught. Get near and
## its motor starts (1725 rpm, up to speed in a few seconds), the damper
## blades shudder in the suction, the light behind it is chopped by the
## blades; then it cuts out and coasts down.
func _update_fan(delta: float) -> void:
	var me := _me()
	var near := absf(me.x + 10.0) < 0.6 and me.y < 23.6 and me.y > DAMPER_Y
	match _fan_state:
		0:
			if near and _events:
				_fan_state = 1
				_fan_t = 1.2
		1:
			_fan_t -= delta
			if _fan_t <= 0.0:
				_fan_state = 2
				_fan_t = 14.0
				_fan_target = FAN_RPM / 60.0
				_fan_audio.stream = _streams.get("fan_start")
				_fan_audio.volume_db = -3.0
				_fan_audio.play()
				_play_at(_pick("knock_heavy"), _g(Vector2(-10, DAMPER_Y), 0.4), -12.0, 0.7, 2500.0)
		2:
			_fan_t -= delta
			if _fan_t <= 0.0:
				_fan_state = 3
				_fan_target = 0.3
				_fan_t = 40.0
		3:
			_fan_t -= delta
			if _fan_t <= 0.0 and not near:
				_fan_state = 0
	# Motor torque spins it up quickly (time constant ~1.6 s); coasting down
	# is slower (~7 s), as a real rotor on its bearings.
	var tau := 1.6 if _fan_target > _fan_speed else 7.0
	_fan_speed += (_fan_target - _fan_speed) * (1.0 - exp(-delta / tau))
	if _fan_state <= 1:
		_fan_speed = 0.3 + 0.12 * sin(_t * 0.7) + 0.4 * _pulse_env()
	_fan_angle = fmod(_fan_angle + _fan_speed * TAU * delta, TAU)
	var k := clampf(inverse_lerp(4.0, 12.0, _fan_speed), 0.0, 1.0)
	_fan.rotation = Vector3.ZERO
	_fan.rotate_object_local(Vector3.BACK, _fan_angle)
	_fan_blades.visible = k < 0.98
	_fan_blur.visible = k > 0.02
	_blur_mat.albedo_color.a = 0.75 * k
	# Running loop: in as it comes up to speed.
	var run := clampf(_fan_speed / (FAN_RPM / 60.0), 0.0, 1.0)
	_fan_loop.volume_db = linear_to_db(maxf(run * run, 0.0001)) - 6.0
	_fan_loop.pitch_scale = 0.6 + 0.4 * run
	# The damper: it flutters in the draught and shudders when the fan pulls.
	var shudder := 0.01 + 0.05 * run
	for i in _damper_blades.size():
		var b := _damper_blades[i]
		var n := sin(_t * (17.0 + i * 3.1)) * 0.6 + sin(_t * (29.0 + i * 1.7)) * 0.4
		b.rotation.x = float(b.get_meta("dir")) * (_damper_open + n * shudder + 0.04 * _pulse_env())
	# The plant room's light through the blades (light group 1): slowly
	# chopped by each blade passing, steady (and dimmer) once it's a blur.
	var blade := 0.5 + 0.5 * cos(_fan_angle * 6.0)
	var chop := lerpf(0.55 + 0.45 * blade, 0.72, k)
	set_light_group(1, CCT, chop)
	if run > 0.3:
		rumble = 0.0015 * run * clampf(1.0 - me.distance_to(Vector2(-10, FAN_Y)) / 6.0, 0.0, 1.0)
	elif rumble > 0.0:
		rumble = 0.0


# ------------------------------------------------------------ lights below ---

func _update_lights(delta: float) -> void:
	# The faulty office (group 0): a failing lamp, mostly on; now and then it
	# stutters, sometimes drops out and its ballast tries to restart it.
	_faulty_t -= delta
	if _faulty_t <= 0.0 and _faulty_seq.is_empty():
		_faulty_t = _rng.randf_range(5.0, 13.0)
		var t := _t
		var n := _rng.randi_range(3, 8)
		for i in n:
			t += _rng.randf_range(0.03, 0.12)
			_faulty_seq.append([t, _rng.randf_range(0.0, 0.25)])
			t += _rng.randf_range(0.02, 0.1)
			_faulty_seq.append([t, _rng.randf_range(0.75, 1.0)])
		if _rng.randf() < 0.35:
			t += 0.05
			_faulty_seq.append([t, 0.0])
			t += _rng.randf_range(1.0, 2.5)
			_faulty_seq.append([t, -1.0])         # restart: the starter's sound
			for i in 3:
				t += _rng.randf_range(0.25, 0.5)
				_faulty_seq.append([t, 0.6])
				t += _rng.randf_range(0.05, 0.12)
				_faulty_seq.append([t, 0.0])
			t += 0.3
			_faulty_seq.append([t, 1.0])
	while not _faulty_seq.is_empty() and _t >= float(_faulty_seq[0][0]):
		var lv: float = _faulty_seq[0][1]
		_faulty_seq.pop_front()
		if lv < 0.0:
			_play_at(_streams.get("ballast_start"), _g(REGISTERS[4][0], -0.4), -12.0, 1.0, 3500.0)
		else:
			_faulty = lv
	set_light_group(0, CCT, _faulty)
	# The occupancy sensor (group 2): the office is dark; pass over it and
	# a moment later its lights come on. Nobody is in there.
	var reg: Vector2 = REGISTERS[5][0]
	match _occ_state:
		0:
			if _events and _me().distance_to(reg) < 2.6:
				_occ_state = 1
				_occ_t = 1.1
		1:
			_occ_t -= delta
			if _occ_t <= 0.0:
				_occ_state = 2
				_occ_t = 0.0
				_play_at(_pick("knock_1"), _g(reg, -0.8), -26.0, 2.2, 3000.0)   # the relay
		2:
			_occ_t += delta
			_occupancy = 0.35 if _occ_t < 0.06 else 1.0
			if _occ_t > 45.0:
				_occ_state = 3
		3:
			_occupancy = maxf(_occupancy - delta * 0.6, 0.0)
	set_light_group(2, CCT, _occupancy)


# --------------------------------------------------------------- the hand ---

func _update_hand(delta: float) -> void:
	if _hand == null or _hand_state >= 3:
		return
	_hand.update(delta)
	var me := _me()
	match _hand_state:
		0:
			var d := me.distance_to(NODES["n6"])
			var in_run := absf(me.y - 36.0) < 0.5 and me.x < 3.5 and me.x > -3.0
			var look := _facing().dot(Vector2(1, 0)) > 0.85
			if _events and in_run and ((d < 5.5 and look and player.flashlight_on) or d < 2.8):
				_hand_state = 1
				_hand_t = 0.0
			# The fingers move a little on the metal.
			_hand_pose = 0.04 * sin(_t * 0.9) * sin(_t * 2.3)
		1:
			# Caught in the light: a beat, the fingers tighten, then it goes.
			_hand_t += delta
			_hand_pose = -0.12 * smoothstep(0.1, 0.4, _hand_t)
			if _hand_t > 0.6:
				_hand_state = 2
				_hand_t = 0.0
				_hand_audio.stream = _streams.get("drag")
				_hand_audio.volume_db = -6.0
				_hand_audio.play()
				_play_at(_pick("brush_"), _hand.global_position + Vector3(0, 0.2, -1.7), -10.0, 0.8)
		2:
			# Snatched back: accelerates hard, the hand dragging flat, the arm
			# lifting as the elbow comes round the corner; slows out of sight.
			_hand_t += delta
			var k := clampf(_hand_t / 0.85, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			e = lerpf(k * k * k, e, k)
			var back := 2.8 * e
			_place_hand(back, clampf(back * 1.6, 0.0, 1.0))
			_hand_audio.global_position = _hand.global_position + Vector3(0, 0.2, -1.4)
			if _hand_t > 1.0:
				_hand_state = 3
				_hand.visible = false
				var a := _play_at(_streams.get("creak_crawl"), _g(Vector2(4, 31.5), 0.3), -8.0, 0.95, 4000.0)
				if a:
					create_tween().tween_property(a, "global_position", _g(Vector2(4, 29.2), 0.3), 6.0)
	_pose_hand()
	_hand.set_env_light(light_at(_hand.global_position) + Color(0.02, 0.02, 0.02))


# -------------------------------------------------------- the twin duct ---

## Beside the run from n3 to n5 there's another duct, a hand's width of air
## between them. Crawl along and something in it crawls with you, a knock
## for each of your pulls, a beat behind. Stop, and it goes on two more,
## then stops too. Then one bang, right beside you.
func _update_twin(delta: float) -> void:
	var me := _me()
	var in_run := absf(me.x + 10.0) < 0.6 and me.y > 25.0 and me.y < 35.4
	match _twin_state:
		0:
			if _events and in_run and me.y > 25.6 and me.y < 30.0:
				_twin_state = 1
				_twin_last_step = _t
		1:
			if not in_run:
				_twin_state = 3
				# It goes on ahead and away.
				for i in 4:
					_twin_queue.append([_t + 0.5 + i * 0.55, _pick("knock_"), _g(Vector2(TWIN_X, me.y + 2.0 + i * 0.6), 0.25),
							-12.0 - i * 3.0])
			elif _twin_steps > 4 and _t - _twin_last_step > 1.2:
				_twin_state = 2
				_twin_t = 0.0
				for i in 2:
					_twin_queue.append([_t + 0.1 + i * 0.62, _pick("knock_"), _g(Vector2(TWIN_X, me.y + 0.9 + i * 0.35), 0.25),
							-10.0])
		2:
			_twin_t += delta
			if _twin_t > 4.2:
				_twin_state = 3
				_twin_queue.append([_t, _streams.get("knock_heavy"), _g(Vector2(TWIN_X + 0.15, me.y + 0.3), 0.4), -2.0])
				shake(0.008, 0.6)
	while not _twin_queue.is_empty() and _t >= float(_twin_queue[0][0]):
		var q: Array = _twin_queue.pop_front()
		_play_at(q[1], q[2], q[3], _rng.randf_range(0.85, 1.0), 1800.0)


# -------------------------------------------------------------- the exit ---

## Push the grille out: it swings down on its last clip, drops into the
## office and clatters on the carpet; you let yourself down through the
## hole by your arms and drop.
func open_exit() -> void:
	var hole := _g(EXIT_AT)
	var pdone := {"d": false}
	if _exit:
		_exit.busy = true
	# Over the grille, looking down at it (a ride switches your collision
	# off: back on after it, so you stay on the duct floor while you shove).
	player.ride(PackedVector3Array([player.camera.global_position, hole + Vector3(0, 0.42, 0.42)]), player.yaw, 0.7,
			func() -> void: pdone.d = true, -1.1)
	while not pdone.d:
		await get_tree().process_frame
	player.stand_up()
	_play_at(_streams.get("grille_kick"), hole + Vector3(0, -0.1, 0), -2.0, 1.0)
	shake(0.01, 0.3)
	# Hinged on its north edge, it swings down (two hard shoves).
	var piv := Node3D.new()
	add_child(piv)
	piv.global_position = _grille.global_position + Vector3(0, 0, -0.335)
	_grille.reparent(piv)
	var tw := create_tween()
	tw.tween_property(piv, "rotation:x", 0.35, 0.18).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(piv, "rotation:x", 0.22, 0.25).set_trans(Tween.TRANS_SINE)
	tw.tween_property(piv, "rotation:x", 1.25, 0.3).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tw.tween_property(piv, "rotation:x", 1.05, 0.22).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished
	_play_at(_pick("knock_2"), _grille.global_position, -8.0, 1.4)
	_grille.reparent(self)
	# The clip lets go: it falls the 2.74 m (0.75 s), tumbling, and lands.
	var start := _grille.global_transform
	var fall_t := sqrt(2.0 * ROOM_H / 9.81)
	var land := Transform3D(Basis(Vector3.UP, 0.4) * Basis(Vector3.RIGHT, 0.06), _g(EXIT_AT + Vector2(0.25, -0.5), CEIL - ROOM_H + 0.012))
	var t := 0.0
	while t < fall_t:
		t += get_process_delta_time()
		var k := clampf(t / fall_t, 0.0, 1.0)
		var pos := start.origin.lerp(land.origin, k)
		pos.y = lerpf(start.origin.y, land.origin.y, k * k)
		var q := start.basis.get_rotation_quaternion().slerp(land.basis.get_rotation_quaternion(), k)
		var tumble := Basis(Vector3.RIGHT, sin(k * PI) * 0.9)
		_grille.global_transform = Transform3D(Basis(q) * tumble, pos)
		await get_tree().process_frame
	_grille.global_transform = land
	_play_at(_streams.get("grille_land"), land.origin, -1.0, 0.9)
	var bounce := create_tween()
	bounce.tween_property(_grille, "position:y", _grille.position.y + 0.06, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	bounce.tween_property(_grille, "position:y", _grille.position.y, 0.12).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	bounce.tween_callback(func() -> void: _play_at(_streams.get("grille_land"), land.origin, -12.0, 1.15))
	await get_tree().create_timer(0.5).timeout
	# Legs through first, then hang from the edge, then drop.
	pdone.d = false
	var down := PackedVector3Array([player.camera.global_position, hole + Vector3(0, 0.25, 0.05),
			hole + Vector3(0, -0.35, 0), hole + Vector3(0, CEIL - 0.45, 0)])
	_play_at(_pick("brush_"), hole, -8.0, 0.9)
	player.ride(down, player.yaw, 1.6, func() -> void: pdone.d = true, -1.0)
	while not pdone.d:
		await get_tree().process_frame
	pdone.d = false
	player.force_crawl = false
	var floor_y := CEIL - ROOM_H
	player.ride(PackedVector3Array([player.camera.global_position, hole + Vector3(0, floor_y + 1.62 - 0.25, 0.1)]),
			player.yaw, 0.42, func() -> void: pdone.d = true, -0.35)
	while not pdone.d:
		await get_tree().process_frame
	_play_at(_pick("crawl_"), hole + Vector3(0, floor_y + 0.1, 0), 0.0, 0.7)
	shake(0.03, 0.4)
	player.stand_up()
	await get_tree().create_timer(0.35).timeout


# --------------------------------------------------------------- harness ---

func _view(at: Vector2, yaw_deg: float, pitch := 0.0, z := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(b, _g(at, z))


## yaw 0 faces north (-Z), 90 west, 180 south, -90 east.
func shots() -> Array:
	return [
		{"name": "arrival", "transform": _view(Vector2(0, 0.6), 0.0), "crawl": true, "flashlight": true},
		{"name": "behind", "transform": _view(Vector2(0, 1.4), 180.0), "crawl": true, "flashlight": true},
		{"name": "register", "transform": _view(Vector2(0, 4.4), 0.0, -0.45), "crawl": true, "flashlight": true},
		{"name": "register_down", "transform": _view(Vector2(0.05, 5.15), 0.0, -1.25), "crawl": true, "flashlight": false},
		{"name": "joints", "transform": _view(Vector2(0, 13.2), 0.0, -0.05), "crawl": true, "flashlight": true},
		{"name": "elbow_torn", "transform": _view(Vector2(0.05, 22.1), 0.0, -0.08), "crawl": true, "flashlight": true},
		{"name": "vanes_full", "transform": _view(Vector2(7.2, 12), -90.0, -0.05), "crawl": true, "flashlight": true},
		{"name": "damper", "transform": _view(Vector2(-10, 22.3), 180.0, -0.05), "crawl": true, "flashlight": true},
		{"name": "liner", "transform": _view(Vector2(-8.2, 36), -90.0, -0.05), "crawl": true, "flashlight": true},
		{"name": "hand", "transform": _view(Vector2(1.6, 36), -90.0, -0.1), "crawl": true, "flashlight": true},
		{"name": "exit", "transform": _view(Vector2(4, 42.7), 0.0, -0.55), "crawl": true, "flashlight": true},
		{"name": "vanes_close", "transform": _view(Vector2(0.12, 23.62), 40.0, -0.15), "crawl": true, "flashlight": true},
		{"name": "register_angle", "transform": _view(Vector2(0, 4.75), 0.0, -0.75), "crawl": true, "flashlight": false},
		{"name": "room_up", "transform": _view(Vector2(0.4, 4.0), 0.0, 0.75, CEIL - ROOM_H), "flashlight": false},
		{"name": "hand_check", "transform": _view(Vector2(4, 36.3), 180.0, -0.2), "crawl": true, "flashlight": true},
		{"name": "office_below", "transform": _view(Vector2(1.9, 41.5), -40.0, -0.1, CEIL - ROOM_H), "flashlight": false},
	]


## Film: the first register with a run of pops; the fan spinning up behind
## the damper; the hand round the bend; the way out.
func film() -> void:
	_events = true
	_pop_next = 9999.0
	player.force_crawl = true
	player.set_flashlight(true)
	player.teleport(_g(Vector2(0, 2.0)), 0.0, -0.1)
	await get_tree().create_timer(0.6).timeout
	_start_pops(true)
	await _crawl_to(Vector2(0, 6.8), 8.0)
	await get_tree().create_timer(1.0).timeout
	player.teleport(_g(Vector2(-10, 23.4)), PI, -0.06)
	await _crawl_to(Vector2(-10, 21.25), 5.0)
	await get_tree().create_timer(9.0).timeout
	player.teleport(_g(Vector2(0.9, 36)), -PI * 0.5, -0.1)
	await _crawl_to(Vector2(2.3, 36), 4.0)
	await get_tree().create_timer(2.5).timeout
	player.teleport(_g(Vector2(4, 41.6)), 0.0, -0.3)
	await _crawl_to(Vector2(4, 42.6), 3.0)
	await open_exit()
	await get_tree().create_timer(1.5).timeout


## Crawls (the forward key, steering towards it) until within 0.25 m of
## `to` or `limit` seconds pass.
func _crawl_to(to: Vector2, limit: float) -> void:
	var t := 0.0
	Input.action_press("move_forward")
	while t < limit:
		var d := to - _me()
		if d.length() < 0.25:
			break
		var want := atan2(-d.x, d.y)
		player.yaw = lerp_angle(player.yaw, want, 0.1)
		player._apply_rotation()
		t += get_process_delta_time()
		await get_tree().process_frame
	Input.action_release("move_forward")
