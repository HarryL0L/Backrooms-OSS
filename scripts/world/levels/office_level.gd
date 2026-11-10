extends SideLevel
## The Dimming Floor: one floor of an open-plan office building after hours.
## 120 x 60 ft of carpet tiles under a 9 ft T-bar ceiling, 48 workstations in
## clusters of six, lateral files and a copier down the spine, black glass all
## round (nothing outside, not even the city), the core on the west with the
## stair. Ninety three-lamp troffers in fifteen switched banks, lit at their
## real output (L.U.C.I.D. units: see assets/levels/office/SPEC.md).
##
## You come down through a return grille from the duct above (the Crawlspace
## leads here; you land under the hole, the grille on the carpet beside you)
## or in through the suite door. The floor's lighting panel only believes
## you're there while you keep still: walk, and the banks behind you go out
## one after another (the relay panel clunking in the electrical closet, the
## tubes ticking off), from the far end toward you; stop, and they come back
## from the far end with a programmed-start ballast's second of cathode glow,
## the lamps striking one by one, a weak one stuttering. Each time they stop
## a little closer to you, leaving a dark gap behind you, and in the gap
## something stands that's never there in the light. A chair rolls out of a
## workstation by itself; a monitor wakes as you pass; a phone rings in a
## dark corner; the printer warms up. The way out is the stair door (EXIT)
## in the west wall.

const NAME := "Level 6.1 - The Dimming Floor"
const INTRO := "The lights go out behind you. Don't look back."
const DIR := "res://assets/levels/office/"
const TEX := "res://assets/levels/office/textures"
const AUD := "res://assets/levels/office/audio/"
const OFFICE_SHADER := "res://assets/levels/office/office_lit.gdshader"
const OFFICE_SHADER_CUTOUT := "res://assets/levels/office/office_lit_cutout.gdshader"

## Sizes (m), as tools/blender/levels/office.py (Blender x east, y north).
const CEIL := 2.7432
const PLATE := Vector2(36.576, 18.288)
const SPINE_Y := 9.144
const NBANK := 15
const BANK_X0 := 1.524
const BANK_P := 2.4384
const HOLE := Vector2(34.44, 8.84)
const STAIR := Vector2(0.0, 15.65)
const SUITE := Vector2(0.0, 9.9)
const ELEC := Vector2(0.0, 3.6)
const DOOR_W := 0.9144
const DOOR_H := 2.1336
const COPIER := Vector2(22.6, 9.144)
## The level's own chair (rolls) and monitor (wakes): x, y, rotation.
const CHAIR_AT := Vector3(22.5544, 12.4890, 5.5429)
const MONITOR_AT := Vector3(13.7558, 4.8105, 0.0)
const DESK_H := 0.7366
## Troffer lens luminance: 6020 lm x LLF 0.85, Lambertian, over 1.22 x
## 0.61 m = 2190 cd/m2, in engine units (cd/m2 / 153.6).
const LENS_EMIT := 14.27
const EXIT_EMIT := 300.0 / 153.6
const WALLPACK_EMIT := 1500.0 / PI / 0.06 / 153.6
## Light from one bank on the work plane (engine units of E / pi) at x
## metres from its column: A (h^2 / (h^2 + x^2))^2, a Lambertian row seen
## from below (h = 2.4 m); with all 15 on ~0.8 (~390 lux), as the bake.
const BANK_A := 0.5
const BANK_H := 2.4
## The far-light strip (see office_lit.gdshaderinc).
const FAR_X0 := -2.0
const FAR_LEN := 40.96
## How long you have to stand still before the lights come back, and the
## dark gap (in banks) they leave behind you each time.
const STILL_WAIT := 2.6
## (then 3, 2, 1, 0 over again). It shows itself only in a gap of two or
## more banks: one dark column between lit ones isn't dark.
const GAPS := [4, 3, 2, 1, 0]

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _events := true
var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _hums: Array[AudioStreamPlayer3D] = []
var _office_mats: Array[ShaderMaterial] = []
var _bank_img: Image
var _bank_tex: ImageTexture
var _far_img: Image
var _far_tex: ImageTexture
var _light_rgb := Color.WHITE
var _base_exposure := 1.0
var _ae := 1.0
# Banks: lit lamps (0..3, fractions while a lamp flickers), run-up, cathode
# glow, and what's scheduled.
var _lamps := PackedFloat32Array()
var _glow := PackedFloat32Array()
var _on_at := PackedFloat32Array()      # time the bank's lamps struck (run-up)
var _bank_busy := PackedFloat32Array()  # until when a sequence owns the bank
var _seq: Array = []                    # [time, bank, lamps, glow, sound]
var _active := false                    # the switching has started
var _dir := -1.0
var _dir_t := 0.0
var _still := 0.0
var _moving := 0.0
var _off_next := 0.0
var _relight_queue: Array = []          # [time, bank]
var _relighting := false
var _cycle := 0
var _gap := 4
# The figure.
var _fig: EntityBody
var _fig_state := 0                     # 0 hidden, 1 standing in the dark
var _fig_bank := -1
var _fig_x := 0.0
var _fig_seen := 0.0
# The chair, the monitor, the stair door, events.
var _chair: Node3D
var _chair_mats: Array[ShaderMaterial] = []
var _chair_state := 0                   # 0 waiting, 1 rolling, 2 done
var _chair_t := 0.0
var _chair_from := Vector3.ZERO
var _chair_to := Vector3.ZERO
var _chair_audio: AudioStreamPlayer3D
var _monitor_mats: Array[ShaderMaterial] = []
var _screen: MeshInstance3D
var _screen_mat: StandardMaterial3D
var _screen_light: OmniLight3D
var _screen_on := 0.0
var _screen_want := 0.0
var _screen_t := -100.0
var _leaf: Node3D
var _leaf_mats: Array[ShaderMaterial] = []
var _exit: LevelEntrance
var _phone_next := 40.0
var _phone_rings := 0
var _phone_at := Vector3.ZERO
var _printer_done := false
var _dust: CPUParticles3D
var _dust_mat: StandardMaterial3D
var _grille_arrival := true


func _g(b: Vector2, z := 0.0) -> Vector3:
	return Vector3(b.x, LEVEL_Y + z, -b.y)


static func _c(r: float, g: float, b: float) -> Color:
	# Linear albedo -> the sRGB the shader's source_color uniform expects.
	return Color(r, g, b).linear_to_srgb()


static func bank_x(k: int) -> float:
	return BANK_X0 + k * BANK_P


# ----------------------------------------------------------------- build ---

func build(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed
	var lm := DIR + "lightmaps/"
	var surfaces := {
		"carpet": {"texture": "carpet", "scale": 1.0 / 1.2192, "roughness": 1.0, "specular": 0.2, "normal_depth": 0.7},
		"ceiling_tile": {"texture": "ceiling_tile", "scale": 1.0 / 3.6576, "roughness": 1.0, "specular": 0.2},
		"wall_paint": {"texture": "wall_paint", "scale": 0.5, "roughness": 1.0, "specular": 0.3, "normal_depth": 0.4},
		"panel_fabric": {"texture": "panel_fabric", "scale": 2.0, "roughness": 1.0, "specular": 0.2},
		"laminate": {"texture": "laminate", "scale": 0.8, "roughness": 0.8, "specular": 0.45, "normal_depth": 0.3},
		"blinds": {"texture": "blinds", "scale": 1.0, "roughness": 0.7, "specular": 0.35},
		"base": {"color": _c(0.05, 0.05, 0.05), "roughness": 0.8},
		"panel_trim": {"color": _c(0.30, 0.30, 0.29), "roughness": 0.5},
		"desk_metal": {"color": _c(0.10, 0.10, 0.10), "roughness": 0.5, "metallic": 0.3},
		"pedestal": {"color": _c(0.33, 0.32, 0.30), "roughness": 0.5},
		"monitor": {"color": _c(0.025, 0.025, 0.027), "roughness": 0.35, "specular": 0.5},
		"screen": {"color": _c(0.012, 0.012, 0.014), "roughness": 0.1, "specular": 0.6},
		"keyboard": {"color": _c(0.03, 0.03, 0.03), "roughness": 0.6},
		"chair_fabric": {"color": _c(0.035, 0.035, 0.04), "roughness": 1.0},
		"chair_base": {"color": _c(0.04, 0.04, 0.04), "roughness": 0.4},
		"troffer_frame": {"color": _c(0.80, 0.80, 0.78), "roughness": 0.5},
		"grille": {"color": _c(0.80, 0.80, 0.78), "roughness": 0.5},
		"grille_dark": {"color": _c(0.02, 0.02, 0.02), "roughness": 0.9},
		"galv": {"color": _c(0.45, 0.46, 0.47), "roughness": 0.5, "metallic": 0.3},
		"exit_housing": {"color": _c(0.80, 0.80, 0.78), "roughness": 0.5},
		"exit_led": {"color": Color(1.0, 0.22, 0.12), "emit": EXIT_EMIT},
		"door_steel": {"color": _c(0.30, 0.31, 0.30), "roughness": 0.45},
		"door_wood": {"color": _c(0.30, 0.20, 0.12), "roughness": 0.5},
		"door_frame": {"color": _c(0.20, 0.20, 0.20), "roughness": 0.45, "metallic": 0.3},
		"hardware": {"color": _c(0.55, 0.55, 0.53), "roughness": 0.3, "metallic": 0.9},
		"glass_window": {"color": Color(0.06, 0.07, 0.08)},
		"mullion": {"color": _c(0.035, 0.032, 0.03), "roughness": 0.35, "metallic": 0.5},
		"sill": {"color": _c(0.45, 0.44, 0.42), "roughness": 0.4},
		"convector": {"color": _c(0.52, 0.50, 0.46), "roughness": 0.5},
		"convector_grille": {"color": _c(0.03, 0.03, 0.03), "roughness": 0.7},
		"cabinet": {"color": _c(0.33, 0.32, 0.30), "roughness": 0.5, "metallic": 0.2},
		"copier": {"color": _c(0.55, 0.54, 0.51), "roughness": 0.5},
		"copier_dark": {"color": _c(0.05, 0.05, 0.05), "roughness": 0.5},
		"paper": {"color": _c(0.80, 0.80, 0.78), "roughness": 0.9},
		"floor_box": {"color": _c(0.30, 0.29, 0.27), "roughness": 0.4, "metallic": 0.7},
		"concrete": {"color": _c(0.35, 0.34, 0.32), "roughness": 0.9},
		"cmu_paint": {"color": _c(0.55, 0.54, 0.50), "roughness": 0.9},
		"stair_steel": {"color": _c(0.12, 0.12, 0.12), "roughness": 0.6, "metallic": 0.4},
		"sign_plate": {"color": _c(0.08, 0.08, 0.09), "roughness": 0.5},
		"sprinkler": {"color": _c(0.85, 0.84, 0.80), "roughness": 0.4, "metallic": 0.5},
		"bin": {"color": _c(0.06, 0.06, 0.06), "roughness": 0.6},
		"bin_blue": {"color": _c(0.02, 0.06, 0.16), "roughness": 0.6},
		"lamp_night": {"texture": "lens", "emit": LENS_EMIT, "roughness": 0.3},
		"wallpack": {"color": Color(1, 1, 1), "emit": WALLPACK_EMIT},
	}
	for g in 4:
		surfaces["lamp_g%d" % g] = {"texture": "lens", "emit": LENS_EMIT, "group": g, "roughness": 0.3}
	low_view_range = 0.0
	load_kit(DIR + "office_west.glb", lm + "office_west.png", TEX, surfaces, lm + "office_west_groups.png")
	load_kit(DIR + "office_east.glb", lm + "office_east.png", TEX, surfaces, lm + "office_east_groups.png")
	# 4100 K lamps (F32T8/841) under a camera white balanced for the room
	# (as a phone's AWB leaves fluorescent light: a touch warm).
	var c := Lucid.fixture_rgb(Lucid.FIXTURES.troffer_t8_3lamp) * Lucid.wb_gains(4500.0)
	_light_rgb = c / maxf(Lucid.lum(c), 0.001)
	for g in 4:
		set_light_group(g, _light_rgb, 1.0)
	_bank_img = Image.create(16, 1, false, Image.FORMAT_RGBA8)
	_bank_tex = ImageTexture.create_from_image(_bank_img)
	_far_img = Image.create(64, 1, false, Image.FORMAT_RGBA8)
	_far_tex = ImageTexture.create_from_image(_far_img)
	_lamps.resize(NBANK)
	_glow.resize(NBANK)
	_on_at.resize(NBANK)
	_bank_busy.resize(NBANK)
	for k in NBANK:
		_lamps[k] = 3.0
		_on_at[k] = -100.0
	_load_sounds()
	_build_chair()
	_build_monitor()
	_build_door()
	_build_dust()
	_build_figure()
	_build_audio()
	_adopt_materials()
	_update_banks()
	environment = make_environment({"background": Color(0, 0, 0), "fog": Color(0.0, 0.0, 0.0),
			"fog_density": 0.004, "exposure": 1.0, "glow": 0.3, "saturation": 0.95, "contrast": 1.02})
	# (no night colour cast: the body cam white balances for the room)
	environment.adjustment_color_correction = null
	_base_exposure = environment.tonemap_exposure


## The kit's (and our flat) materials onto the bank-switching shader.
func _adopt_materials() -> void:
	var sh: Shader = load(OFFICE_SHADER)
	var shc: Shader = load(OFFICE_SHADER_CUTOUT)
	for m in _kit_mats:
		var sm := m as ShaderMaterial
		if sm == null:
			continue
		if sm.shader.resource_path == SHADER:
			sm.shader = sh
		elif sm.shader.resource_path == SHADER_CUTOUT:
			sm.shader = shc
		else:
			continue
		sm.set_shader_parameter("bank_tex", _bank_tex)
		sm.set_shader_parameter("bank_count", NBANK)
		sm.set_shader_parameter("bank_x0", BANK_X0)
		sm.set_shader_parameter("bank_pitch", BANK_P)
		sm.set_shader_parameter("far_tex", _far_tex)
		sm.set_shader_parameter("far_x0", FAR_X0)
		sm.set_shader_parameter("far_len", FAR_LEN)
		_office_mats.append(sm)


func _load_sounds() -> void:
	for f in DirAccess.get_files_at(AUD):
		var n := f.trim_suffix(".import")
		if n.ends_with(".ogg") and not _streams.has(n.get_basename()):
			_streams[n.get_basename()] = load(AUD + n)
	for i in 10:
		var a := AudioStreamPlayer3D.new()
		a.bus = "World"
		a.unit_size = 3.0
		a.max_distance = 45.0
		add_child(a)
		_pool.append(a)


func _pick(prefix: String) -> AudioStream:
	var list: Array = []
	for k in _streams:
		if String(k).begins_with(prefix):
			list.append(_streams[k])
	return list[_rng.randi() % list.size()] if not list.is_empty() else null


func _play_at(st: AudioStream, at: Vector3, db := -6.0, pitch := 1.0, filter := 12000.0) -> AudioStreamPlayer3D:
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
	add_loop(_streams.get("hvac_loop"), Vector3.INF, -26.0)
	# Each bank hums (heard within a few metres), loudness by its output.
	for k in NBANK:
		var a := add_loop(_streams.get("hum_loop"), _g(Vector2(bank_x(k), SPINE_Y), CEIL - 0.2), -80.0,
				{"unit_size": 2.0, "max_distance": 14.0, "pitch": _rng.randf_range(0.99, 1.01)}) as AudioStreamPlayer3D
		_hums.append(a)
	_chair_audio = AudioStreamPlayer3D.new()
	_chair_audio.bus = "World"
	_chair_audio.unit_size = 3.0
	_chair_audio.stream = _streams.get("chair_roll")
	add_child(_chair_audio)


## Boxes merged into one mesh (one draw call): [size, Transform3D] each.
static func _boxes(list: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for b in list:
		var bm := BoxMesh.new()
		bm.size = b[0]
		st.append_from(bm, 0, b[1])
	st.generate_normals()
	return st.commit()


func _mesh(mesh: Mesh, mat: Material, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


## The task chair that rolls: the kit's chair (24 in five-star base, gas
## lift, 19 in seat), as boxes. Godot space, facing +Z... built to match the
## Blender chair (its front is Blender +y = Godot -Z).
func _build_chair() -> void:
	_chair = Node3D.new()
	add_child(_chair)
	var fabric := flat_material({"color": _c(0.035, 0.035, 0.04), "roughness": 1.0})
	var base := flat_material({"color": _c(0.04, 0.04, 0.04), "roughness": 0.4, "specular": 0.5})
	_chair_mats = [fabric, base]
	var parts: Array = []
	for i in 5:
		var a := i * TAU / 5.0
		var d := Vector3(cos(a), 0, -sin(a))
		parts.append([Vector3(0.30, 0.03, 0.04), Transform3D(Basis(Vector3.UP, a), d * 0.15 + Vector3(0, 0.07, 0))])
		parts.append([Vector3(0.04, 0.045, 0.03), Transform3D(Basis(Vector3.UP, a), d * 0.30 + Vector3(0, 0.0225, 0))])
	parts.append([Vector3(0.05, 0.36, 0.05), Transform3D(Basis(), Vector3(0, 0.24, 0))])
	parts.append([Vector3(0.2, 0.05, 0.22), Transform3D(Basis(), Vector3(0, 0.405, 0))])
	parts.append([Vector3(0.06, 0.32, 0.035), Transform3D(Basis(Vector3.RIGHT, 0.1), Vector3(0, 0.56, 0.25))])
	for s in [-1.0, 1.0]:
		parts.append([Vector3(0.03, 0.2, 0.05), Transform3D(Basis(), Vector3(s * 0.27, 0.56, 0.02))])
		parts.append([Vector3(0.07, 0.025, 0.25), Transform3D(Basis(), Vector3(s * 0.27, 0.67, 0.0))])
	_mesh(_boxes(parts), base, _chair)
	var cushions := [[Vector3(0.50, 0.08, 0.48), Transform3D(Basis(), Vector3(0, 0.47, -0.02))],
			[Vector3(0.46, 0.52, 0.07), Transform3D(Basis(Vector3.RIGHT, 0.14), Vector3(0, 0.86, 0.29))]]
	_mesh(_boxes(cushions), fabric, _chair)
	_chair.global_transform = Transform3D(Basis(Vector3.UP, CHAIR_AT.z), _g(Vector2(CHAIR_AT.x, CHAIR_AT.y)))
	_chair_from = _chair.global_position
	# Out through the workstation's opening into the spine aisle.
	_chair_to = _g(Vector2(22.95, 10.75))


## The monitor that wakes (the kit's 24 in monitor) with its screen.
func _build_monitor() -> void:
	var root := Node3D.new()
	add_child(root)
	root.global_transform = Transform3D(Basis(Vector3.UP, MONITOR_AT.z), _g(Vector2(MONITOR_AT.x, MONITOR_AT.y), DESK_H))
	var body := flat_material({"color": _c(0.025, 0.025, 0.027), "roughness": 0.35, "specular": 0.5})
	_monitor_mats = [body]
	# (Blender +y is Godot -Z: the screen faces -Z here)
	_mesh(_boxes([[Vector3(0.22, 0.015, 0.18), Transform3D(Basis(), Vector3(0, 0.0075, 0))],
			[Vector3(0.05, 0.30, 0.025), Transform3D(Basis(), Vector3(0, 0.16, 0.045))],
			[Vector3(0.541, 0.323, 0.035), Transform3D(Basis(), Vector3(0, 0.36, 0.02))]]), body, root)
	_screen_mat = StandardMaterial3D.new()
	_screen_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var grad := GradientTexture2D.new()
	var gr := Gradient.new()
	gr.set_color(0, Color(0.10, 0.16, 0.30))
	gr.set_color(1, Color(0.02, 0.04, 0.09))
	grad.gradient = gr
	grad.fill = GradientTexture2D.FILL_RADIAL
	grad.fill_from = Vector2(0.5, 0.45)
	grad.fill_to = Vector2(1.1, 1.0)
	grad.width = 64
	grad.height = 64
	_screen_mat.albedo_texture = grad
	_screen_mat.albedo_color = Color(0, 0, 0)
	var q := QuadMesh.new()
	q.size = Vector2(0.527, 0.297)
	_screen = _mesh(q, _screen_mat, root)
	_screen.position = Vector3(0, 0.365, 0.0012)
	_screen.rotation.y = PI
	_screen.material_override = _screen_mat
	_screen_light = OmniLight3D.new()
	_screen_light.light_color = Color(0.55, 0.65, 1.0)
	_screen_light.omni_range = 2.2
	_screen_light.light_energy = 0.0
	_screen_light.shadow_enabled = false
	_screen_light.visible = false
	root.add_child(_screen_light)
	_screen_light.position = Vector3(0, 0.36, -0.35)


## The stair door's leaf (36 x 84 in hollow metal, panic bar on this side,
## a closer), hinged on its north jamb, opening into the stair; and the exit.
func _build_door() -> void:
	var paint := flat_material({"color": _c(0.30, 0.31, 0.30), "roughness": 0.45, "specular": 0.45})
	var steel := flat_material({"color": _c(0.55, 0.55, 0.53), "roughness": 0.3, "metallic": 0.9})
	var dark := flat_material({"color": _c(0.03, 0.03, 0.035), "roughness": 0.1, "specular": 0.6})
	_leaf_mats = [paint, steel, dark]
	_leaf = Node3D.new()
	add_child(_leaf)
	_leaf.global_position = _g(Vector2(-0.06, STAIR.y + DOOR_W * 0.5))
	var w := DOOR_W - 0.01
	_mesh(_boxes([[Vector3(0.045, DOOR_H - 0.01, w), Transform3D(Basis(), Vector3(0, DOOR_H * 0.5, w * 0.5))]]), paint, _leaf)
	_mesh(_boxes([[Vector3(0.05, 0.05, 0.78), Transform3D(Basis(), Vector3(0.07, 0.98, w * 0.5 + 0.02))],
			[Vector3(0.04, 0.08, 0.06), Transform3D(Basis(), Vector3(0.045, 0.98, 0.1))],
			[Vector3(0.04, 0.08, 0.06), Transform3D(Basis(), Vector3(0.045, 0.98, w - 0.08))],
			[Vector3(0.05, 0.06, 0.3), Transform3D(Basis(), Vector3(0.05, DOOR_H - 0.12, 0.2))]]), steel, _leaf)
	_mesh(_boxes([[Vector3(0.05, 0.6, 0.1), Transform3D(Basis(), Vector3(0, 1.45, w * 0.72))]]), dark, _leaf)
	var col := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(0.1, DOOR_H, DOOR_W)
	cs.shape = bs
	cs.position = Vector3(0, DOOR_H * 0.5, DOOR_W * 0.5)
	col.add_child(cs)
	_leaf.add_child(col)
	# The landing behind it (the kit draws it but has no floor to stand on
	# there): the ride through the door ends on it, and you'd drop through
	# it into the dark while the screen fades.
	var land := StaticBody3D.new()
	var lcs := CollisionShape3D.new()
	var lbs := BoxShape3D.new()
	lbs.size = Vector3(3.05, 0.2, 3.8)
	lcs.shape = lbs
	land.add_child(lcs)
	add_child(land)
	land.global_position = _g(Vector2(-1.675, STAIR.y - 0.3), -0.1)
	_exit = add_exit(Transform3D(Basis(Vector3.UP, PI * 0.5), _g(STAIR)), "none", "",
			{"label": "Take the stairs", "walk_in": false})


## Grit and fibre still drifting down from the open grille when you land.
func _build_dust() -> void:
	_dust = CPUParticles3D.new()
	_dust.amount = 70
	_dust.lifetime = 5.0
	_dust.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_dust.emission_box_extents = Vector3(0.28, 0.02, 0.28)
	_dust.direction = Vector3.DOWN
	_dust.spread = 25.0
	_dust.initial_velocity_min = 0.05
	_dust.initial_velocity_max = 0.25
	_dust.gravity = Vector3(0, -0.35, 0)
	_dust.damping_min = 0.4
	_dust.damping_max = 1.2
	_dust.scale_amount_min = 0.4
	_dust.scale_amount_max = 1.4
	_dust.local_coords = false
	var q := QuadMesh.new()
	q.size = Vector2(0.006, 0.006)
	_dust_mat = StandardMaterial3D.new()
	_dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	_dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_dust_mat.albedo_color = Color(0.30, 0.29, 0.27, 0.7)
	q.material = _dust_mat
	_dust.mesh = q
	add_child(_dust)
	_dust.global_position = _g(HOLE, CEIL - 0.02)
	_dust.emitting = false


func _build_figure() -> void:
	_fig = add_figure(Transform3D(Basis(), _g(Vector2(30, 8))), "tall", Color(0.16, 0.16, 0.17), 1.0)
	_fig.visible = false
	_fig.move(0.0)


# --------------------------------------------------------------- the game ---

func on_enter() -> void:
	var cs := get_tree().current_scene
	_events = cs == null or not String(cs.scene_file_path).contains("level_shots")
	if _grille_arrival:
		_land()


## Landed under the grille: the jolt, grit still coming down.
func _land() -> void:
	shake(0.025, 0.35)
	_dust.emitting = true
	_dust.restart()
	_play_at(_streams.get("debris"), _g(HOLE, CEIL - 0.1), -10.0)
	get_tree().create_timer(14.0).timeout.connect(func() -> void:
		if is_instance_valid(_dust):
			_dust.emitting = false)


func on_leave() -> void:
	pass


## Under the open grille (from the duct: the Crawlspace's way out), or just
## inside the suite door when you came in through it from the Backrooms.
func arrival() -> Transform3D:
	_grille_arrival = true
	if player and player.global_position.y > LEVEL_Y + 1000.0:
		for n in get_tree().get_nodes_in_group("usable"):
			var e := n as LevelEntrance
			if e and e.exit_of == null and e.dest == "office" \
					and e.global_position.distance_to(player.global_position) < 5.0:
				_grille_arrival = false
				break
	if not _grille_arrival:
		return Transform3D(Basis(Vector3.UP, -PI * 0.5), _g(SUITE + Vector2(1.0, 0.0)))   # facing east
	return Transform3D(Basis(Vector3.UP, PI * 0.5), _g(HOLE))      # facing west, down the spine


func surface_at(p: Vector3) -> int:
	return Player.SURF_CONCRETE if p.x < -0.1 else Player.SURF_CARPET


func camera_far() -> float:
	return 30.0 if low else 48.0


## Carpet, acoustic tile and fabric panels: a dead, short room.
func reverb() -> Dictionary:
	return {"room": 0.45, "damp": 0.8, "wet": 0.16}


func light_at(p: Vector3) -> Color:
	var e := _light_level(p)
	return Color(_light_rgb.r * e, _light_rgb.g * e, _light_rgb.b * e)


## Work-plane light (engine E / pi) at p from the banks as they are now,
## the night light by the stair and the stair's wall pack.
func _light_level(p: Vector3) -> float:
	var e := 0.0
	if _lamps.size() == NBANK:
		for k in NBANK:
			var o := _out(k)
			if o > 0.001:
				e += o * _bank_light(p.x - bank_x(k))
	var dn := Vector2(p.x - bank_x(0), -p.z - 16.46).length()
	e += 0.12 * exp(-dn * dn / 6.0)
	if p.x < 0.0:
		e += 0.25
	return e + 0.002


static func _bank_light(dx: float) -> float:
	var q := BANK_H * BANK_H / (BANK_H * BANK_H + dx * dx)
	return BANK_A * q * q


func albedo_at(p: Vector3, n: Vector3) -> Color:
	if n.y > 0.7:
		return Color(0.06, 0.066, 0.08)
	if n.y < -0.7:
		return Color(0.8, 0.8, 0.78)
	return Color(0.35, 0.35, 0.36)


func warm_materials() -> Array[Material]:
	var out := super()
	out.append(_screen_mat)
	out.append(_dust_mat)
	out.append_array(EntityBody.warm_materials())
	return out


func save_state() -> Dictionary:
	return {"cycle": _cycle, "chair": _chair_state == 2, "printer": _printer_done}


func load_state(d: Dictionary) -> void:
	_cycle = int(d.get("cycle", 0))
	_gap = _gap_for(_cycle)
	_printer_done = bool(d.get("printer", false))
	if d.get("chair", false):
		_chair_state = 2
		_chair.global_position = _chair_to
	_grille_arrival = false


# ----------------------------------------------------------------- banks ---

## A bank's output now (0..1): lit lamps, the fluorescent run-up from cold
## (about 90 % at strike, full after ~20 s).
func _out(k: int) -> float:
	var run := clampf(0.9 + 0.1 * (_t - _on_at[k]) / 20.0, 0.9, 1.0)
	return _lamps[k] / 3.0 * run


func _update_banks() -> void:
	var warm := Color(1.0, 0.45, 0.18)
	for k in 16:
		var c := Color(0, 0, 0, 1)
		if k < NBANK:
			var o := _out(k)
			c = Color(o, o, o, 1.0) + warm * _glow[k]
			c.a = 1.0
		_bank_img.set_pixel(k, 0, Color(clampf(c.r, 0, 1), clampf(c.g, 0, 1), clampf(c.b, 0, 1), 1.0))
	_bank_tex.update(_bank_img)
	# The far light: banks more than 2.5 banks off (the bake carries the
	# rest), with its bounce (x 1.6).
	for i in 64:
		var x := FAR_X0 + (i + 0.5) * FAR_LEN / 64.0
		var u := (x - BANK_X0) / BANK_P
		var f := 0.0
		for k in NBANK:
			if absf(k - u) > 2.5:
				f += _out(k) * _bank_light(x - bank_x(k)) * 1.6
		var v := sqrt(clampf(f / 0.1, 0.0, 1.0))
		_far_img.set_pixel(i, 0, Color(v, v, v, 1.0))
	_far_tex.update(_far_img)
	for k in mini(NBANK, _hums.size()):
		var o := _out(k)
		_hums[k].volume_db = linear_to_db(maxf(o, 0.0001)) - 15.0 if o > 0.01 else -80.0
		if _glow[k] > 0.0:
			_hums[k].volume_db = linear_to_db(_glow[k] * 3.0) - 22.0


func _bank_pos(k: int) -> Vector3:
	return _g(Vector2(bank_x(k), clampf(-(player.global_position.z if player else -SPINE_Y), 1.5, 16.8)), CEIL - 0.1)


## Kills bank k: the contactor drops out in the electrical closet, the
## tubes tick off; now and then a weak one blinks once more.
func _bank_off(k: int) -> void:
	var t := _t
	_bank_busy[k] = t + 0.6
	_seq.append([t, k, -1.0, 0.0, "relay"])
	_seq.append([t + 0.03, k, 0.0, 0.0, "tube_off"])
	if _rng.randf() < 0.35:
		_seq.append([t + 0.13, k, 1.0, 0.0, "zap"])
		_seq.append([t + 0.19, k, 0.0, 0.0, ""])
		if _rng.randf() < 0.5:
			_seq.append([t + 0.36, k, 0.6, 0.0, ""])
			_seq.append([t + 0.40, k, 0.0, 0.0, ""])
	_sort_seq()


## Starts bank k: relay in, ~1.1 s of cathode preheat (the lamp ends glow
## orange), then the three lamps strike one after another (programmed-start
## ballast); a worn lamp sometimes stutters before it holds.
func _bank_on(k: int, at: float) -> void:
	var v := _rng.randi() % 2
	var strikes := [1.12, 1.19 + 0.05 * v, 1.33]
	_bank_busy[k] = at + 3.0
	_seq.append([at, k, -1.0, 0.0, "relay"])
	_seq.append([at + 0.02, k, 0.0, 0.0, "ballast_start_%d" % (v + 1)])
	for i in 8:
		_seq.append([at + 0.1 + i * 0.13, k, 0.0, 0.002 + 0.0006 * i, ""])
	_seq.append([at + strikes[0], k, 1.0, 0.0, "strike"])
	_seq.append([at + strikes[1], k, 2.0, 0.0, ""])
	if _rng.randf() < 0.4:
		var t: float = at + strikes[2]
		for i in _rng.randi_range(3, 6):
			_seq.append([t, k, 3.0, 0.0, "zap"])
			t += _rng.randf_range(0.03, 0.09)
			_seq.append([t, k, 2.0, 0.0, ""])
			t += _rng.randf_range(0.05, 0.35)
		_seq.append([t, k, 3.0, 0.0, "strike"])
	else:
		_seq.append([at + strikes[2], k, 3.0, 0.0, "strike"])
	_sort_seq()


func _sort_seq() -> void:
	_seq.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _run_seq() -> void:
	while not _seq.is_empty() and _seq[0][0] <= _t:
		var e: Array = _seq.pop_front()
		var k: int = e[1]
		if e[2] >= 0.0:
			if e[4] == "strike" and _lamps[k] < 0.5:
				_on_at[k] = _t          # (the run-up starts with the first strike)
			_lamps[k] = e[2]
			_glow[k] = e[3]
		var pos := _bank_pos(k)
		match e[4]:
			"relay":
				_play_at(_pick("relay_"), _g(ELEC + Vector2(-1.2, 0.0), 1.8), -4.0, _rng.randf_range(0.95, 1.05), 2500.0)
			"tube_off":
				_play_at(_pick("tube_off_"), pos, -10.0, _rng.randf_range(0.95, 1.05))
			"zap":
				_play_at(_pick("zap_"), pos, -12.0, _rng.randf_range(0.9, 1.1))
			"":
				pass
			"strike":
				pass
			_:
				_play_at(_streams.get(e[4]), pos, -9.0, _rng.randf_range(0.97, 1.03))


## Where you are, in banks (fractional), and which banks are behind you.
func _my_bank() -> float:
	return (player.global_position.x - BANK_X0) / BANK_P


func _behind(k: int, margin: float) -> bool:
	return (float(k) - _my_bank()) * _dir < -margin


func _update_switching(delta: float) -> void:
	var v := player.velocity
	var speed := Vector2(v.x, v.z).length()
	if speed > 0.6:
		_moving += delta
		_still = 0.0
		if absf(v.x) > 0.5 and signf(v.x) != _dir:
			_dir_t += delta
			if _dir_t > 0.6:
				_dir = signf(v.x)
				_dir_t = 0.0
		else:
			_dir_t = 0.0
	else:
		_still += delta
		_moving = 0.0
	if not _active:
		# The floor is still, all lit, until you've walked a few metres.
		if player.global_position.distance_to(_g(HOLE)) > 4.0 and _grille_arrival or not _grille_arrival and _t > 6.0:
			_active = true
			_off_next = _t + 0.8
		return
	# Walking: the banks behind you go, from the far end toward you.
	if _moving > 0.3:
		_relight_queue.clear()
		_relighting = false
		if _t >= _off_next:
			var far := -1
			var far_d := -1.0
			for k in NBANK:
				if _lamps[k] > 0.5 and _bank_busy[k] <= _t and _behind(k, 1.15):
					var d := absf(float(k) - _my_bank())
					if d > far_d:
						far_d = d
						far = k
			if far >= 0:
				_bank_off(far)
				_off_next = _t + _rng.randf_range(0.45, 0.85)
	# Standing still: they come back from the far end, stopping short of you.
	if _still > STILL_WAIT and not _relighting:
		var dark: Array = []
		for k in NBANK:
			if _lamps[k] < 0.5 and _bank_busy[k] <= _t:
				dark.append(k)
		if not dark.is_empty():
			var me := _my_bank()
			dark.sort_custom(func(a: int, b: int) -> bool: return absf(a - me) > absf(b - me))
			var n := maxi(dark.size() - _gap, 0)
			var at := _t
			for i in n:
				_relight_queue.append([at, dark[i]])
				at += _rng.randf_range(0.6, 1.05)
			_relighting = true
			# The middle of the gap that stays dark (the banks nearest you).
			_fig_bank = -1
			if _gap >= 2 and dark.size() - n >= 2:
				var xs := 0.0
				for i in range(n, dark.size()):
					xs += bank_x(dark[i])
				_fig_x = xs / float(dark.size() - n)
				_fig_bank = dark[(n + dark.size() - 1) >> 1]
	if _relighting:
		while not _relight_queue.is_empty() and _relight_queue[0][0] <= _t:
			var r: Array = _relight_queue.pop_front()
			_bank_on(r[1], _t)
		if _relight_queue.is_empty() and _still > STILL_WAIT:
			# All that will come back has been started: the gap shrinks next time.
			_relighting = false
			_still = -1000.0        # (until you move again)
			_cycle += 1
			if _fig_bank >= 0:
				_show_figure(_fig_x)
			_gap = _gap_for(_cycle)


func _gap_for(cycle: int) -> int:
	return GAPS[cycle] if cycle < GAPS.size() else [3, 2, 1, 0][(cycle - GAPS.size()) % 4]


# ---------------------------------------------------------------- figure ---

## It stands in the dark gap behind you, at the edge of the light that came
## back, turned toward you. It is never there in the light.
func _show_figure(x: float) -> void:
	var py := -player.global_position.z
	var y := 10.35 if py > SPINE_Y else 7.95
	_fig.global_position = _g(Vector2(x, y))
	_face_figure()
	_fig.set_env_light(Color(0.0, 0.0, 0.0))
	_fig.visible = true
	_fig_state = 1
	_fig_seen = 0.0


func _face_figure() -> void:
	var to := player.global_position - _fig.global_position
	_fig.rotation.y = atan2(to.x, to.z)


func _update_figure(delta: float) -> void:
	if _fig_state != 1:
		return
	_fig.update(delta)
	var to := player.global_position - _fig.global_position
	to.y = 0.0
	var head_to := atan2(to.x, to.z) - _fig.rotation.y
	_fig.head_yaw = lerpf(_fig.head_yaw, wrapf(head_to, -PI, PI) * 0.8, 1.0 - exp(-delta * 2.0))
	var lit := _light_level(_fig.global_position) * 0.4
	_fig.set_env_light(Color(lit, lit, lit) * 0.15)
	var gone := false
	if _light_level(_fig.global_position) > 0.3:
		gone = true                             # the light reached it: nothing there
	if to.length() < 4.0:
		gone = true
	if player.flashlight_on:
		var f := -player.camera.global_basis.z
		var d := (_fig.global_position + Vector3(0, 1.4, 0)) - player.camera.global_position
		if d.length() < 18.0 and f.dot(d.normalized()) > cos(deg_to_rad(18.0)):
			gone = true
	if gone:
		_vanish()


func _vanish() -> void:
	# A blink of the lit banks behind it (a zap), and it's gone.
	_fig_state = 0
	var k := clampi(roundi((_fig.global_position.x - BANK_X0) / BANK_P - _dir), 0, NBANK - 1)
	if _lamps[k] > 2.5:
		_seq.append([_t, k, 0.0, 0.0, "zap"])
		_seq.append([_t + 0.12, k, 3.0, 0.0, ""])
		_sort_seq()
	get_tree().create_timer(0.05).timeout.connect(func() -> void: _fig.visible = false)


# ---------------------------------------------------------------- events ---

func _update_chair(delta: float) -> void:
	_set_flat_light(_chair_mats, _chair.global_position)
	if _chair_state == 0:
		var p := player.global_position
		if _events and p.x < 26.5 and p.x > 22.8 and absf(-p.z - SPINE_Y) < 3.0:
			_chair_state = 1
			_chair_t = 0.0
			_chair_audio.global_position = _chair.global_position + Vector3(0, 0.3, 0)
			_chair_audio.volume_db = -6.0
			_chair_audio.play()
	elif _chair_state == 1:
		# Casters on carpet: v0 0.95 m/s, slowing at ~0.35 m/s2 (rolling
		# resistance), a slow swivel as it goes.
		_chair_t += delta
		var d := _chair_from.distance_to(_chair_to)
		var a := 0.95 * 0.95 / (2.0 * d)
		var s := minf(0.95 * _chair_t - 0.5 * a * _chair_t * _chair_t, d)
		var k := s / d
		_chair.global_position = _chair_from.lerp(_chair_to, k)
		_chair.rotation.y = CHAIR_AT.z + 0.7 * k * (2.0 - k)
		_chair_audio.global_position = _chair.global_position + Vector3(0, 0.3, 0)
		if _chair_t > 0.95 / a:
			_chair_state = 2


func _set_flat_light(mats: Array, at: Vector3) -> void:
	var c := light_at(at)
	for m in mats:
		(m as ShaderMaterial).set_shader_parameter("const_light", Vector3(c.r, c.g, c.b))


func _update_monitor(delta: float) -> void:
	_set_flat_light(_monitor_mats, _screen.global_position)
	var d := player.global_position.distance_to(_screen.global_position)
	if _screen_want < 0.5 and d < 3.6 and _t - _screen_t > 30.0 and _events:
		_screen_want = 1.0
		_screen_t = _t
		_play_at(_streams.get("monitor_wake"), _screen.global_position, -12.0)
	elif _screen_want > 0.5 and _t - _screen_t > 25.0 and d > 7.0:
		_screen_want = 0.0
	# The backlight comes up over ~0.4 s (a small flash as the panel inits).
	var rate := 3.0 if _screen_want > _screen_on else 6.0
	_screen_on = move_toward(_screen_on, _screen_want, delta * rate)
	var flash := 0.6 * exp(-(_t - _screen_t) * 6.0) if _screen_want > 0.5 else 0.0
	var e := _screen_on + flash
	_screen_mat.albedo_color = Color(e, e, e)
	_screen_light.visible = e > 0.01
	_screen_light.light_energy = 0.35 * e


func _update_events(delta: float) -> void:
	var p := player.global_position
	# The printer by the copier warms up when you first come near it.
	if not _printer_done and _events and p.distance_to(_g(COPIER)) < 7.0:
		_printer_done = true
		_play_at(_streams.get("printer_start"), _g(Vector2(24.0, SPINE_Y), 0.9), -10.0)
	# A phone rings somewhere dark, four times, now and then.
	if _events:
		_phone_next -= delta
		if _phone_next <= 0.0:
			if _phone_rings == 0:
				var best := Vector3.INF
				for i in 12:
					var c := _g(Vector2(_rng.randf_range(2.0, 34.0), [4.5, 13.7][_rng.randi() % 2]), 0.8)
					if _light_level(c) < 0.05 and c.distance_to(p) > 9.0:
						best = c
						break
				if best.is_finite():
					_phone_at = best
					_phone_rings = 4
			if _phone_rings > 0:
				_play_at(_streams.get("phone_ring"), _phone_at, -9.0, 1.0, 5000.0)
				_phone_rings -= 1
				_phone_next = 4.0 if _phone_rings > 0 else _rng.randf_range(55.0, 90.0)
			else:
				_phone_next = 10.0


## The body cam's auto exposure: meters the light round you and where
## you're looking, opens up (to about 2 stops) in the dark, slowly.
func _update_exposure(delta: float) -> void:
	var cam := player.camera.global_position
	var f := -player.camera.global_basis.z
	var l := 0.5 * _light_level(cam) + 0.5 * _light_level(cam + f * 3.0)
	var target := clampf(0.8 / maxf(l, 0.002), 0.75, 12.0)
	var rate := 0.6 if target > _ae else 3.0
	_ae = lerpf(_ae, target, 1.0 - exp(-delta * rate))
	environment.tonemap_exposure = _base_exposure * _ae


func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	_run_seq()
	if _events:
		_update_switching(delta)
	_update_banks()
	_update_figure(delta)
	_update_chair(delta)
	_update_monitor(delta)
	_update_events(delta)
	_update_exposure(delta)
	_set_flat_light(_leaf_mats, _leaf.global_position + Vector3(0.4, 1.0, 0))


# ------------------------------------------------------------------ exit ---

func open_exit() -> void:
	if _exit:
		_exit.busy = true
	var door := _g(STAIR)
	_play_at(_streams.get("door_open"), door + Vector3(0, 1.0, 0), -4.0)
	var tw := create_tween()
	tw.tween_property(_leaf, "rotation:y", -1.55, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	var pdone := {"d": false}
	await get_tree().create_timer(0.25).timeout
	player.ride(PackedVector3Array([player.camera.global_position, door + Vector3(0.55, 1.58, 0.0),
			door + Vector3(-0.6, 1.55, -0.1)]), PI * 0.5, 1.5, func() -> void: pdone.d = true, -0.18)
	while not pdone.d:
		await get_tree().process_frame
	player.stand_up()


# --------------------------------------------------------------- harness ---

## yaw 0 faces north (-Z), 90 west, 180 south, -90 east.
func _view(at: Vector2, yaw_deg: float, pitch := 0.0, z := 0.0) -> Transform3D:
	var b := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(b, _g(at, z))


## For the harness: bank k lit (3) or dark (0) in a pattern, at once.
func _set_banks(f: Callable) -> void:
	_seq.clear()
	for k in NBANK:
		_lamps[k] = f.call(k)
		_glow[k] = 0.0
		_on_at[k] = -100.0
	_update_banks()


func shots() -> Array:
	var all_on := func() -> void: _set_banks(func(_k: int) -> float: return 3.0)
	return [
		{"name": "arrival", "transform": _view(HOLE, 90.0, -0.12), "call": func() -> void:
			all_on.call()
			_land()},
		{"name": "arrival_up", "transform": _view(HOLE + Vector2(-1.3, 0.25), -80.0, 0.85), "call": all_on},
		{"name": "arrival_grille", "transform": _view(HOLE + Vector2(0.4, 0.2), 100.0, -0.75), "call": all_on},
		{"name": "spine", "transform": _view(Vector2(31.0, 8.2), 90.0, -0.02), "call": all_on},
		{"name": "cubicles", "transform": _view(Vector2(14.6, 7.7), 165.0, -0.3), "call": func() -> void:
			all_on.call()
			_screen_want = 1.0
			_screen_on = 1.0
			_screen_t = _t},
		{"name": "perimeter", "transform": _view(Vector2(20.0, 1.2), 70.0, 0.0), "call": all_on},
		{"name": "behind", "transform": _view(Vector2(19.5, 8.3), -90.0, 0.0), "call": func() -> void:
			_set_banks(func(k: int) -> float: return 3.0 if k <= 8 or k >= 13 else 0.0)
			_dir = -1.0
			_fig_bank = 11
			_show_figure(bank_x(11) - 0.2)},
		{"name": "relight", "transform": _view(Vector2(26.0, 10.3), -95.0, 0.05), "wait": 0.4, "call": func() -> void:
			_fig.visible = false
			_fig_state = 0
			_set_banks(func(k: int) -> float: return 3.0 if k <= 10 or k == 14 else 0.0)
			_glow[12] = 0.012
			_lamps[13] = 1.0},
		{"name": "dark", "transform": _view(Vector2(24.0, 10.2), -90.0, 0.0), "wait": 2.5, "call": func() -> void:
			_set_banks(func(k: int) -> float: return 3.0 if k <= 7 else 0.0)},
		{"name": "chair", "transform": _view(Vector2(25.5, 9.6), 75.0, -0.2), "call": func() -> void:
			all_on.call()
			_chair.global_position = _chair_from.lerp(_chair_to, 0.6)
			_chair.rotation.y = CHAIR_AT.z + 0.5},
		{"name": "exit", "transform": _view(Vector2(5.5, 14.2), 102.0, 0.05), "call": all_on},
	]


## Film: landing under the grille; walking west, the banks dying behind;
## stopping and looking back as they come back with the gap and what stands
## in it; the chair; the monitor; out through the stair door.
func film() -> void:
	_events = true
	_set_banks(func(_k: int) -> float: return 3.0)
	_active = false
	_cycle = 0
	_gap = 3
	player.set_flashlight(false)
	player.teleport(_g(HOLE), PI * 0.5, 0.9)
	_land()
	await get_tree().create_timer(0.8).timeout
	await _turn_to(PI * 0.5, -0.05, 2.0)
	await _walk_to(Vector2(20.5, 8.0), 9.0)
	await _turn_to(-PI * 0.5, 0.0, 1.6)
	await get_tree().create_timer(10.0).timeout
	await _turn_to(PI * 0.5, -0.05, 1.2)
	await _walk_to(Vector2(14.3, 7.6), 6.0)
	await _turn_to(PI * 0.92, -0.32, 1.2)
	await get_tree().create_timer(2.5).timeout
	player.teleport(_g(Vector2(3.2, 17.2)), PI * 0.5 + 0.5, -0.05)
	await get_tree().create_timer(1.0).timeout
	await _walk_to(Vector2(0.75, 16.2), 4.0)
	await _turn_to(PI * 0.5, -0.05, 0.6)
	await open_exit()
	await get_tree().create_timer(1.0).timeout


func _turn_to(yaw: float, pitch: float, time: float) -> void:
	var y0 := player.yaw
	var p0 := player.pitch
	var t := 0.0
	while t < time:
		t += get_process_delta_time()
		var k := smoothstep(0.0, 1.0, t / time)
		player.yaw = lerp_angle(y0, yaw, k)
		player.pitch = lerpf(p0, pitch, k)
		player._apply_rotation()
		await get_tree().process_frame


## Walks (the forward key, steering toward it) until within 0.3 m of `to`.
func _walk_to(to: Vector2, limit: float) -> void:
	var t := 0.0
	Input.action_press("move_forward")
	while t < limit:
		var p := player.global_position
		var d := to - Vector2(p.x, -p.z)
		if d.length() < 0.3:
			break
		var want := atan2(-d.x, d.y)
		player.yaw = lerp_angle(player.yaw, want, 0.08)
		player._apply_rotation()
		t += get_process_delta_time()
		await get_tree().process_frame
	Input.action_release("move_forward")
