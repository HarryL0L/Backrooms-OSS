extends SideLevel
## The Stacks: one storage room of a records centre after hours. Two banks
## of high-density mobile shelving fill it wall to wall: twelve double-faced
## mechanical-assist carriages each on flush floor rails between two fixed
## units, cartons of files three to a shelf, seven shelves high, a three-
## spoke handle on every carriage's end panel along the main aisle. Each bank
## has one open aisle; the rest of the room is shelving pressed together.
## Two-lamp strips hang in rows across the ranges on occupancy sensors, and
## each carriage carries an aisle light bar that comes on when its aisle is
## entered. The room's real sizes, masses and light are in
## assets/levels/filing/SPEC.md.
##
## Nobody is turning the handles. Ranges roll by themselves: the frames
## creak, the cartons start to shiver, the aisle light flickers and goes
## out, the handles start to spin and the rails rumble, and the carriages on
## one side of the aisle roll shut at a brisk crank's speed until they meet
## with a clunk, opening the aisle somewhere else. Stand in an aisle too
## long and it shuts on you (catch_player: crushed). The warning and the
## carriages' speed leave time to walk out of any aisle; dawdle and you
## don't. A cart left in bank A's aisle gets shoved aside; papers slide off
## the cartons when a range stops. The way out is the exit door in the north
## wall, behind bank B: through one of its aisles.

const NAME := "Level 1.1 - The Stacks"
const INTRO := "Records nobody will ever ask for. The shelves move on their own."
const DIR := "res://assets/levels/filing/"
const TEX := "res://assets/levels/filing/textures"
const AUD := "res://assets/levels/filing/audio/"
const FILING_SHADER := "res://assets/levels/filing/filing_lit.gdshader"
const FILING_SHADER_CUTOUT := "res://assets/levels/filing/filing_lit_cutout.gdshader"

## Sizes (m), as tools/blender/levels/filing.py (Blender x east, y north).
const IN := 0.0254
const SEC_W := 42 * IN
const NSEC := 6
const END_T := 0.025
const RANGE_L := NSEC * SEC_W + 2 * END_T
const SHELF_D := 15 * IN
const FLUE := 2 * IN
const CAR_W := 2 * SHELF_D + FLUE
const FIX_W := SHELF_D + 0.04
const AISLE := 36 * IN
const NCAR := 12
const WALL_GAP := 0.05
const BANK_W := 2 * FIX_W + NCAR * CAR_W + AISLE
const ROOM_W := BANK_W + 2 * WALL_GAP
const REAR := 42 * IN
const MAIN := 72 * IN
const BANK_Y := [REAR, REAR + RANGE_L + MAIN]
const ROOM_D := 2 * REAR + 2 * RANGE_L + MAIN
const CEIL := 3.2
const MAIN_Y := REAR + RANGE_L + MAIN / 2
const EXIT_X := 10.65
const FIX_L := WALL_GAP + FIX_W
const FIX_R := WALL_GAP + BANK_W - FIX_W
const STACK_H := 2.30
const SHELF_Y0 := 0.14
const SHELF_P := 0.305
const NLEV := 7
const STRIP_X := [1.18, 3.50, 5.81, 8.12, 10.43]
const STRIP_Y := 2.85
## Rows of strips: Blender y, light group (-1: the night light).
const ROWS := [[0.5335, 1], [REAR + 1.61, 1], [REAR + 4.84, 1], [MAIN_Y, 0],
		[REAR + RANGE_L + MAIN + 1.61, 2], [REAR + RANGE_L + MAIN + 4.84, 3], [ROOM_D - 0.5335, 3]]
## L.U.C.I.D. light. Strip: 4500 lm x LLF 0.85 (Lucid strip_t8_2lamp);
## a row of five over 10.47 m is a line source of 1827 lm/m, Lambertian:
## I = 1827 / pi cd/m, stored as cd/(m pi 153.6). Tubes: 6520 cd/m2.
const UNIT := 153.6
const STRIP_LM := 4500.0 * 0.85
const ROW_X := Vector2(0.57, 11.04)
const TUBE_EMIT := 4500.0 * 0.85 / (PI * 2.0 * (TAU * 0.0127 * 1.17)) / 153.6
const EXIT_EMIT := 300.0 / 153.6
## Aisle light bars: 820 lm/m LED (4000 K), a 30 mm diffuser (8700 cd/m2).
const BAR_LM_M := 820.0
const BAR_EMIT := 820.0 / PI / 0.03 / 153.6
## Carriage motion: a brisk crank's 0.11 m/s (powered systems are held to
## 0.076 m/s), reached in 1.2 s; 6:1 drive on 5 in wheels: 0.0665 m per
## turn of the handle. Warning before it moves: 1.0 s.
const VMAX := 0.11
const ACCEL_T := 1.2
const PER_TURN := 0.0665
const WARN_T := 1.0
## Caught when the gap you stand in is narrower than you (0.6 m) plus a bit.
const CRUSH_GAP := 0.64
## The cart (a records truck, 33 x 14 in, 40 in high) in bank A's aisle.
const CART_SIZE := Vector3(0.36, 1.0, 0.84)

var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _events := true
var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _mats: Array[ShaderMaterial] = []
var _shelf_mat: ShaderMaterial
var _light_rgb := Color.WHITE
var _bar_rgb := Color.WHITE
var _base_exposure := 1.0
var _ae := 1.0
var _dirty := true
# Banks: carriage centres, bodies, handles, the open aisle, the motion.
var _cx: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _cars: Array = [[], []]
var _bodies: Array = [[], []]
var _cartons: Array = [[], []]
var _handles: Array = [[], []]
var _hang: Array[PackedFloat32Array] = [PackedFloat32Array(), PackedFloat32Array()]
var _aisle := [6, 6]
var _bars := PackedFloat32Array()
var _fix_bars := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _state := [0, 0]            # 0 idle, 1 warning, 2 moving, 3 stopped, 4 going back
var _st := [0.0, 0.0]           # time in the state
var _grp := [Vector2i.ZERO, Vector2i.ZERO]   # moving carriages (first, last)
var _gdir := [0.0, 0.0]
var _gdist := [0.0, 0.0]        # how far they go
var _gmoved := [0.0, 0.0]
var _gv := [0.0, 0.0]
var _gfrom: Array = [PackedFloat32Array(), PackedFloat32Array()]
var _new_aisle := [0, 0]
var _warn_lit := [false, false]
var _rumble: Array[AudioStreamPlayer3D] = []
var _drive: Array[AudioStreamPlayer3D] = []
var _next_event := 40.0
var _first_b := true
var _first_a := true
var _inside_t := [0.0, 0.0]
var _trigger_t := [0.0, 0.0]
var _crushing := false
var _crush_t := 0.0
# Light groups (0..3): level (0..1), when they struck, preheat glow.
var _grp_on := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _grp_want := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
var _grp_seq: Array = []        # [time, group, level]
var _hums: Array = []           # [player, group]
# The cart, papers.
var _cart: AnimatableBody3D
var _cart_x := 0.0
var _cart_z := 0.0
var _papers: Array = []         # {node, state, t, from, v, ...}
var _paper_i := 0


func _g(b: Vector2, z := 0.0) -> Vector3:
	return Vector3(b.x, LEVEL_Y + z, -b.y)


static func _c(r: float, g: float, b: float) -> Color:
	return Color(r, g, b).linear_to_srgb()


## Bank b's z range (Godot local z): (main-aisle end or south end...) as
## (z0, z1), z0 < z1.
static func bank_z(b: int) -> Vector2:
	var y0: float = BANK_Y[b]
	return Vector2(-(y0 + RANGE_L), -y0)


## The handle end of bank b (z, local): on the main aisle.
static func handle_z(b: int) -> float:
	return bank_z(b).x if b == 0 else bank_z(b).y


static func car_home(i: int, aisle: int) -> float:
	return FIX_L + CAR_W * (i + 0.5) + (AISLE if i >= aisle else 0.0)


# ----------------------------------------------------------------- build ---

func build(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed
	var lm := DIR + "lightmaps/"
	var surfaces := {
		"concrete_floor": {"texture": "concrete_floor", "scale": 0.4, "roughness": 1.0, "specular": 0.5, "normal_depth": 0.5},
		"cmu_paint": {"texture": "cmu_paint", "scale": 1.0 / 1.2192, "roughness": 1.0, "specular": 0.3, "normal_depth": 0.8},
		"slab_paint": {"texture": "slab_paint", "scale": 1.3, "roughness": 1.0, "specular": 0.2, "normal_depth": 0.5},
		"rail": {"color": _c(0.30, 0.30, 0.30), "roughness": 0.35, "metallic": 0.8},
		"rail_gap": {"color": _c(0.03, 0.03, 0.03), "roughness": 0.9},
		"base": {"color": _c(0.04, 0.04, 0.04), "roughness": 0.8},
		"strip_body": {"color": _c(0.80, 0.80, 0.78), "roughness": 0.5},
		"rod": {"color": _c(0.45, 0.46, 0.47), "roughness": 0.5, "metallic": 0.6},
		"pipe_red": {"color": _c(0.38, 0.03, 0.02), "roughness": 0.5},
		"sprinkler": {"color": _c(0.70, 0.66, 0.50), "roughness": 0.35, "metallic": 0.8},
		"galv": {"color": _c(0.45, 0.46, 0.47), "roughness": 0.5, "metallic": 0.6},
		"grille": {"color": _c(0.80, 0.80, 0.78), "roughness": 0.5},
		"grille_dark": {"color": _c(0.02, 0.02, 0.02), "roughness": 0.9},
		"door_steel": {"color": _c(0.28, 0.30, 0.30), "roughness": 0.45},
		"door_frame": {"color": _c(0.20, 0.20, 0.20), "roughness": 0.45, "metallic": 0.3},
		"hardware": {"color": _c(0.55, 0.55, 0.53), "roughness": 0.3, "metallic": 0.9},
		"exit_housing": {"color": _c(0.80, 0.80, 0.78), "roughness": 0.5},
		"exit_face": {"texture": "exit_face", "scale": Vector2(1.0 / 0.30, 1.0 / 0.115), "emit": EXIT_EMIT},
		"sensor": {"color": _c(0.85, 0.85, 0.82), "roughness": 0.4},
		"extinguisher": {"color": _c(0.42, 0.02, 0.02), "roughness": 0.3},
		"black": {"color": _c(0.03, 0.03, 0.03), "roughness": 0.6},
		"logger": {"color": _c(0.75, 0.75, 0.72), "roughness": 0.5},
		"stool": {"color": _c(0.20, 0.30, 0.42), "roughness": 0.45},
		"rubber": {"color": _c(0.03, 0.03, 0.03), "roughness": 0.9},
		"lamp_night": {"color": Color(1, 1, 1), "emit": TUBE_EMIT},
	}
	for g in 4:
		surfaces["lamp_g%d" % g] = {"color": Color(1, 1, 1), "emit": TUBE_EMIT, "group": g}
	load_kit(DIR + "filing_room.glb", lm + "filing_room.png", TEX, surfaces, lm + "filing_room_groups.png")
	# 5000 K strips and a 4000 K bar under a camera balanced a little warm
	# (as a phone leaves fluorescent light).
	var c := Lucid.fixture_rgb(Lucid.FIXTURES.strip_t8_2lamp) * Lucid.wb_gains(4800.0)
	_light_rgb = c / maxf(Lucid.lum(c), 0.001)
	var cb := Lucid.kelvin_rgb(4000.0) * Lucid.wb_gains(4800.0)
	_bar_rgb = cb / maxf(Lucid.lum(cb), 0.001)
	for g in 4:
		set_light_group(g, _light_rgb, 0.0)
	_bars.resize(2 * NCAR)
	_load_sounds()
	_shelf_mat = flat_material({"color": Color(1, 1, 1), "roughness": 0.55, "specular": 0.35}, Color(0.5, 0.5, 0.5),
			Vector4.ZERO, TEX, "carton")
	for b in 2:
		_aisle[b] = _rng.randi_range(3, 9)
	_build_banks()
	_build_cart()
	_build_papers()
	_build_audio()
	_adopt_materials()
	_add_exit()
	environment = make_environment({"background": Color(0, 0, 0), "fog": Color(0, 0, 0), "fog_density": 0.006,
			"exposure": 1.0, "glow": 0.3, "saturation": 0.95, "contrast": 1.03})
	environment.adjustment_color_correction = null
	_base_exposure = environment.tonemap_exposure


## Every level shader material onto the Stacks' shader, with the rows.
func _adopt_materials() -> void:
	var sh: Shader = load(FILING_SHADER)
	var shc: Shader = load(FILING_SHADER_CUTOUT)
	var ra := PackedVector4Array()
	var rb := PackedVector4Array()
	var i_row := STRIP_LM * 5.0 / (ROW_X.y - ROW_X.x) / PI / (PI * UNIT)
	var i_strip := STRIP_LM / 1.22 / PI / (PI * UNIT)
	for r in ROWS:
		var y: float = r[0]
		var g: int = r[1]
		if g == 0:
			# the main aisle's row: the night light (always on) and the rest
			ra.append(Vector4(-y, STRIP_Y, STRIP_X[0] - 0.61, STRIP_X[0] + 0.61))
			rb.append(Vector4(i_strip, -1.0, 0, 0))
			ra.append(Vector4(-y, STRIP_Y, STRIP_X[1] - 0.61, ROW_X.y))
			rb.append(Vector4(i_strip * 4.0 * 1.22 / (ROW_X.y - STRIP_X[1] + 0.61), 0.0, 0, 0))
		else:
			ra.append(Vector4(-y, STRIP_Y, ROW_X.x, ROW_X.y))
			rb.append(Vector4(i_row, float(g), 0, 0))
	var i_bar := BAR_LM_M / PI / (PI * UNIT)
	for m in _kit_mats:
		var sm := m as ShaderMaterial
		if sm == null:
			continue
		var lmode := 1 if sm == _shelf_mat or not bool(sm.get_shader_parameter("has_lightmap")) else 0
		if sm.shader.resource_path == SHADER:
			sm.shader = sh
		elif sm.shader.resource_path == SHADER_CUTOUT:
			sm.shader = shc
		else:
			continue
		sm.set_shader_parameter("origin", Vector3(0, LEVEL_Y, 0))
		sm.set_shader_parameter("lmode", lmode)
		sm.set_shader_parameter("rows_a", ra)
		sm.set_shader_parameter("rows_b", rb)
		sm.set_shader_parameter("row_count", ra.size())
		sm.set_shader_parameter("night_rgb", Vector3(_light_rgb.r, _light_rgb.g, _light_rgb.b))
		sm.set_shader_parameter("bar_rgb", Vector3(_bar_rgb.r, _bar_rgb.g, _bar_rgb.b) * i_bar)
		sm.set_shader_parameter("bar_emit", Vector3(_bar_rgb.r, _bar_rgb.g, _bar_rgb.b) * BAR_EMIT)
		sm.set_shader_parameter("car_half", CAR_W * 0.5)
		sm.set_shader_parameter("stack_h", STACK_H)
		var z0 := bank_z(0)
		var z1 := bank_z(1)
		sm.set_shader_parameter("bank0", Vector4(FIX_L, FIX_R, z0.x, z0.y))
		sm.set_shader_parameter("bank1", Vector4(FIX_L, FIX_R, z1.x, z1.y))
		_mats.append(sm)
	_shelf_mat.set_shader_parameter("vcol", true)
	_push_banks()


func _push_banks() -> void:
	var cx := PackedFloat32Array()
	for b in 2:
		cx.append_array(_cx[b])
	for sm in _mats:
		sm.set_shader_parameter("car_x", cx)
		sm.set_shader_parameter("bar_on", _bars)
		sm.set_shader_parameter("fix_bar", _fix_bars)
	_dirty = false


func _load_sounds() -> void:
	for f in DirAccess.get_files_at(AUD):
		var n := f.trim_suffix(".import")
		if n.ends_with(".ogg") and not _streams.has(n.get_basename()):
			_streams[n.get_basename()] = load(AUD + n)
	for i in 12:
		var a := AudioStreamPlayer3D.new()
		a.bus = "World"
		a.unit_size = 3.0
		a.max_distance = 40.0
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
	add_loop(_streams.get("hvac_loop"), Vector3.INF, -27.0)
	for r in ROWS:
		var a := add_loop(_streams.get("hum_loop"), _g(Vector2(5.8, r[0]), STRIP_Y), -80.0,
				{"unit_size": 2.5, "max_distance": 14.0, "pitch": _rng.randf_range(0.99, 1.01)})
		_hums.append([a, r[1]])
	for b in 2:
		var ru := add_loop(_streams.get("rumble_loop"), _g(Vector2(5.8, BANK_Y[b] + RANGE_L * 0.5), 0.2), -80.0,
				{"unit_size": 5.0, "max_distance": 40.0}) as AudioStreamPlayer3D
		var dr := add_loop(_streams.get("drive_loop"), _g(Vector2(5.8, BANK_Y[b] + (RANGE_L if b == 0 else 0.0)), 1.0),
				-80.0, {"unit_size": 3.0, "max_distance": 30.0}) as AudioStreamPlayer3D
		_rumble.append(ru)
		_drive.append(dr)


# --------------------------------------------------------------- shelving ---

## Merged geometry with vertex colours (linear albedo times AO) and UVs into
## the carton atlas; everything untextured samples its white paper margin.
class Geo:
	var st := SurfaceTool.new()
	const WHITE := Vector2(0.006, 0.76)
	const PAPER := Color(0.80, 0.796, 0.78)

	func _init() -> void:
		st.begin(Mesh.PRIMITIVE_TRIANGLES)

	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, uv := Rect2(), tag := 0.0) -> void:
		# a b c d counter-clockwise seen from the front.
		var n := (b - a).cross(d - a).normalized()
		var uvs := [WHITE, WHITE, WHITE, WHITE]
		if uv.size != Vector2.ZERO:
			uvs = [uv.position + Vector2(0, uv.size.y), uv.position + uv.size, uv.position + Vector2(uv.size.x, 0), uv.position]
		var cc := col
		if uv.size == Vector2.ZERO:
			cc = Color(col.r / PAPER.r, col.g / PAPER.g, col.b / PAPER.b, col.a)
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_color(cc)
			st.set_uv(uvs[idx])
			st.set_uv2(Vector2(tag, 0))
			st.add_vertex([a, b, c, d][idx])

	## A box (centre, size) with a colour per face direction (AO baked in):
	## cols = [top, bottom, +x, -x, +z, -z]; skip faces whose colour alpha < 0.
	func box(ctr: Vector3, size: Vector3, cols: Array, uvs := {}) -> void:
		var h := size * 0.5
		var p := func(sx: float, sy: float, sz: float) -> Vector3: return ctr + Vector3(sx * h.x, sy * h.y, sz * h.z)
		var faces := [
			[p.call(-1, 1, 1), p.call(1, 1, 1), p.call(1, 1, -1), p.call(-1, 1, -1)],      # top (+y)
			[p.call(-1, -1, -1), p.call(1, -1, -1), p.call(1, -1, 1), p.call(-1, -1, 1)],  # bottom
			[p.call(1, -1, 1), p.call(1, -1, -1), p.call(1, 1, -1), p.call(1, 1, 1)],      # +x
			[p.call(-1, -1, -1), p.call(-1, -1, 1), p.call(-1, 1, 1), p.call(-1, 1, -1)],  # -x
			[p.call(-1, -1, 1), p.call(1, -1, 1), p.call(1, 1, 1), p.call(-1, 1, 1)],      # +z
			[p.call(1, -1, -1), p.call(-1, -1, -1), p.call(-1, 1, -1), p.call(1, 1, -1)],  # -z
		]
		for i in 6:
			var c: Color = cols[i]
			if c.a < -0.5:
				continue
			quad(faces[i][0], faces[i][1], faces[i][2], faces[i][3], c, uvs.get(i, Rect2()))

	func commit() -> ArrayMesh:
		return st.commit()


static func _ao(c: Color, k: float, alpha := 1.0) -> Color:
	return Color(c.r * k, c.g * k, c.b * k, alpha)


const STEEL := Color(0.50, 0.49, 0.45)      # powder coat, light putty
const PANEL := Color(0.13, 0.17, 0.18)      # end panel, slate
const TRIM := Color(0.05, 0.05, 0.05)
const SKIP := Color(0, 0, 0, -1)


## One carriage's frame (or a fixed unit's: faces = [+1] or [-1]), local:
## centred on x, z; the handle end at +z.
func _frame_geo(g: Geo, faces: Array, width: float, handle_end: bool, card: int) -> void:
	var L := RANGE_L
	var inner := L - 2 * END_T
	# carriage base (the steel channel frame, wheels inside it)
	g.box(Vector3(0, 0.066, 0), Vector3(width, 0.112, L - 0.01),
			[_ao(TRIM, 0.6), SKIP, _ao(TRIM, 1.0), _ao(TRIM, 1.0), _ao(TRIM, 1.0), _ao(TRIM, 1.0)])
	for s in faces:
		var fx: float = s * width * 0.5
		var back: float = s * (width * 0.5 - SHELF_D)
		var mid := (fx + back) * 0.5
		for k in NLEV + 1:
			var y := SHELF_Y0 + k * SHELF_P
			var top := k == NLEV
			var t := 0.025 if top else 0.022
			# shelf plate: top lit by the gap above it, underside in shadow
			g.box(Vector3(mid, y - t * 0.5, 0), Vector3(SHELF_D, t, inner),
					[_ao(STEEL, 0.75 if not top else 1.0), _ao(STEEL, 0.35), _ao(STEEL, 0.9), _ao(STEEL, 0.9),
					_ao(STEEL, 0.6), _ao(STEEL, 0.6)])
			# the formed front lip (and its label holder strip)
			g.box(Vector3(fx - s * 0.006, y - 0.018, 0), Vector3(0.012, 0.036, inner),
					[_ao(STEEL, 0.9), _ao(STEEL, 0.4), _ao(STEEL, 1.0), _ao(STEEL, 1.0), _ao(STEEL, 0.8), _ao(STEEL, 0.8)])
		# uprights at each section line (the face's posts)
		for j in NSEC + 1:
			var z := -inner * 0.5 + j * SEC_W
			g.box(Vector3(fx - s * 0.016, (SHELF_Y0 + STACK_H) * 0.5, z), Vector3(0.032, STACK_H - SHELF_Y0, 0.035),
					[SKIP, SKIP, _ao(STEEL, 0.95), _ao(STEEL, 0.95), _ao(STEEL, 0.7), _ao(STEEL, 0.7)])
		# the aisle light bar on the canopy's edge: aluminium, diffuser under
		var bx: float = fx + s * 0.0175
		g.box(Vector3(bx, 2.262, 0), Vector3(0.035, 0.025, inner - 0.1),
				[_ao(Color(0.6, 0.6, 0.6), 1.0), Color(0.9, 0.9, 0.9, 0.0), _ao(Color(0.6, 0.6, 0.6), 0.9),
				_ao(Color(0.6, 0.6, 0.6), 0.9), _ao(Color(0.6, 0.6, 0.6), 0.7), _ao(Color(0.6, 0.6, 0.6), 0.7)])
	if faces.size() == 1:
		# a fixed unit's back panel
		var s0: float = -faces[0]
		g.box(Vector3(s0 * (width * 0.5 - 0.02), (SHELF_Y0 + STACK_H) * 0.5, 0), Vector3(0.04, STACK_H - SHELF_Y0, inner),
				[_ao(STEEL, 0.8), SKIP, _ao(STEEL, 0.5), _ao(STEEL, 0.5), SKIP, SKIP])
	# end panels: the handle end's painted panel with trim, the far end's frame
	for e in [1.0, -1.0]:
		var z: float = e * (L * 0.5 - END_T * 0.5)
		var col := PANEL if (e > 0 and handle_end) else STEEL
		g.box(Vector3(0, STACK_H * 0.5, z - e * 0.004), Vector3(width - 0.002, STACK_H, END_T - 0.008),
				[SKIP, SKIP, TRIM, TRIM, _ao(TRIM, 1.0), _ao(TRIM, 1.0)])
		g.box(Vector3(0, (0.112 + STACK_H) * 0.5, z + e * 0.002), Vector3(width - 0.016, STACK_H - 0.13, END_T - 0.004),
				[_ao(col, 1.0), SKIP, _ao(col, 0.9), _ao(col, 0.9), _ao(col, 1.0) if e > 0 else _ao(col, 0.6),
				_ao(col, 1.0) if e < 0 else _ao(col, 0.6)])
		g.box(Vector3(0, STACK_H - 0.01, z + e * 0.003), Vector3(width + 0.004, 0.02, END_T + 0.006),
				[TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
	if handle_end and card != -2:
		var zf := L * 0.5
		# the hub's bearing plate and the label holder (card in it)
		g.box(Vector3(0, 1.06, zf + 0.004), Vector3(0.12, 0.12, 0.008), [TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
		g.box(Vector3(0, 1.62, zf + 0.003), Vector3(0.13, 0.09, 0.006), [TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
		if card >= 0:
			var cu := Rect2(Vector2(0.5 + (card / 24) * 0.25 + (card % 24 % 4) * 0.0625, 0.75 + (card % 24 / 4) * 0.041),
					Vector2(0.0625, 0.041))
			var a := Vector3(-0.055, 1.62 - 0.036, zf + 0.0065)
			g.quad(a, a + Vector3(0.11, 0, 0), a + Vector3(0.11, 0.072, 0), a + Vector3(0, 0.072, 0), Color(1, 1, 1), cu)


## Cartons on one carriage's faces (or a fixed unit's). Returns the mesh.
func _cartons_geo(faces: Array, width: float, rng: RandomNumberGenerator) -> ArrayMesh:
	var g := Geo.new()
	var inner := RANGE_L - 2 * END_T
	const CW := 12.5 * IN
	const CH := 10.25 * IN
	for s in faces:
		var fx: float = s * width * 0.5
		for j in NSEC:
			var z0 := -inner * 0.5 + j * SEC_W + 0.018
			for k in NLEV:
				var y0 := SHELF_Y0 + k * SHELF_P
				var r := rng.randf()
				if r < 0.03:
					continue                               # an empty shelf
				var narrow := r > 0.93                     # document cases
				var n := 7 if narrow else 3
				var w := 4.5 * IN if narrow else CW
				var gap := (SEC_W - 0.036 - n * w) / float(n + 1)
				for m in n:
					if rng.randf() < (0.05 if not narrow else 0.12):
						continue
					var v := rng.randi() % 8
					var white := v == 2 or v == 6 or narrow
					var h := CH if not narrow else 11.75 * IN
					var d := SHELF_D - 0.01
					var pull := rng.randf_range(0.004, 0.03) + (0.06 if rng.randf() < 0.04 else 0.0)
					var front: float = fx - s * pull
					var zc := z0 + gap * (m + 1) + w * (m + 0.5) + rng.randf_range(-0.006, 0.006)
					var tint := rng.randf_range(0.82, 1.08)
					var ctr := Vector3(front - s * d * 0.5, y0 + h * 0.5 + 0.001, zc)
					var size := Vector3(d, h, w)
					var fu := Rect2(Vector2((v % 4) * 0.25, (v / 4) * 0.25), Vector2(0.25, 0.25 * 213.0 / 256.0))
					if narrow:
						fu = Rect2(Vector2(0.25, 0.5), Vector2(0.25, 0.25))
					var su := Rect2(Vector2(0.25 if white else 0.0, 0.5), Vector2(0.25, 0.25))
					var tu := Rect2(Vector2(0.75 if white else 0.5, 0.5), Vector2(0.25, 0.25))
					# AO: the shelf above shades the top of each carton end
					var cf := Color(tint, tint, tint)
					var cols := [_ao(cf, 0.32), SKIP, SKIP, SKIP, _ao(cf, 0.45), _ao(cf, 0.45)]
					var uvs := {0: tu, 4: su, 5: su}
					var fi := 2 if s > 0 else 3
					cols[fi] = _ao(cf, 0.92)
					uvs[fi] = fu
					var tag := rng.randf()
					_box_tagged(g, ctr, size, cols, uvs, tag, s, y0, h)
	return g.commit()


## A carton with its end's AO graded (darker under the shelf above) and a
## tag for its jitter.
func _box_tagged(g: Geo, ctr: Vector3, size: Vector3, cols: Array, uvs: Dictionary, tag: float, s: float, y0: float,
		h: float) -> void:
	var hs := size * 0.5
	var fx := ctr.x + s * hs.x
	# the end (two halves: lit bottom, shaded top)
	var fu: Rect2 = uvs[2 if s > 0 else 3]
	var c: Color = cols[2 if s > 0 else 3]
	var z0 := ctr.z + s * hs.z
	var z1 := ctr.z - s * hs.z
	var ym := ctr.y
	var lo := _ao(c, 1.0)
	var hi := _ao(c, 0.62)
	var uvl := Rect2(fu.position + Vector2(0, fu.size.y * 0.5), Vector2(fu.size.x, fu.size.y * 0.5))
	var uvh := Rect2(fu.position, Vector2(fu.size.x, fu.size.y * 0.5))
	_quad_grad(g, Vector3(fx, ctr.y - hs.y, z0), Vector3(fx, ctr.y - hs.y, z1), Vector3(fx, ym, z1), Vector3(fx, ym, z0),
			lo, _ao(c, 0.85), uvl, tag)
	_quad_grad(g, Vector3(fx, ym, z0), Vector3(fx, ym, z1), Vector3(fx, ctr.y + hs.y, z1), Vector3(fx, ctr.y + hs.y, z0),
			_ao(c, 0.85), hi, uvh, tag)
	# top and the two sides
	var bx := ctr.x - s * hs.x
	var top: Color = cols[0]
	_quad_grad(g, Vector3(fx, ctr.y + hs.y, z0), Vector3(fx, ctr.y + hs.y, z1), Vector3(bx, ctr.y + hs.y, z1),
			Vector3(bx, ctr.y + hs.y, z0), top, _ao(top, 0.4), uvs[0], tag)
	for e in [-1.0, 1.0]:
		var zz: float = ctr.z + e * hs.z
		var a := Vector3(fx, ctr.y - hs.y, zz)
		var b2 := Vector3(bx, ctr.y - hs.y, zz)
		var c2 := Vector3(bx, ctr.y + hs.y, zz)
		var d2 := Vector3(fx, ctr.y + hs.y, zz)
		var sc: Color = cols[4]
		# winding: outward normal along e z
		if (e > 0) == (s > 0):
			_quad_grad(g, b2, a, d2, c2, _ao(sc, 0.3), _ao(sc, 1.0), uvs[4], tag, true)
		else:
			_quad_grad(g, a, b2, c2, d2, _ao(sc, 1.0), _ao(sc, 0.3), uvs[4], tag, true)


## A quad whose colour goes from c0 (a, b edge) to c1 (c, d edge); or, with
## `across`, from c0 at a/d to c1 at b/c.
func _quad_grad(g: Geo, a: Vector3, b: Vector3, c: Vector3, d: Vector3, c0: Color, c1: Color, uv: Rect2, tag: float,
		across := false) -> void:
	var n := (b - a).cross(d - a).normalized()
	var uvs := [uv.position + Vector2(0, uv.size.y), uv.position + uv.size, uv.position + Vector2(uv.size.x, 0), uv.position]
	var cs := [c0, c0, c1, c1] if not across else [c0, c1, c1, c0]
	for idx in [0, 2, 1, 0, 3, 2]:
		g.st.set_normal(n)
		g.st.set_color(cs[idx])
		g.st.set_uv(uvs[idx])
		g.st.set_uv2(Vector2(tag, 0))
		g.st.add_vertex([a, b, c, d][idx])


## The three-spoke handle (hub, spokes, knobs), local: axis along +z.
func _handle_mesh() -> ArrayMesh:
	var g := Geo.new()
	var chrome := Color(0.30, 0.30, 0.30)
	var knob := Color(0.03, 0.03, 0.03)
	g.box(Vector3(0, 0, 0.035), Vector3(0.075, 0.075, 0.05), [chrome, chrome, chrome, chrome, chrome, chrome])
	for i in 3:
		var a := i * TAU / 3.0
		var dir := Vector3(cos(a), sin(a), 0)
		var perp := Vector3(-sin(a), cos(a), 0)
		var r0 := 0.03
		var r1 := 0.185
		var z := 0.05
		var w := 0.017
		var p0 := dir * r0
		var p1 := dir * r1
		# a flat spoke (two faces and edges)
		var up := Vector3(0, 0, 0.012)
		g.quad(p0 - perp * w + Vector3(0, 0, z) + up, p1 - perp * w * 0.6 + Vector3(0, 0, z) + up,
				p1 + perp * w * 0.6 + Vector3(0, 0, z) + up, p0 + perp * w + Vector3(0, 0, z) + up, chrome)
		g.quad(p0 + perp * w + Vector3(0, 0, z) - up, p1 + perp * w * 0.6 + Vector3(0, 0, z) - up,
				p1 - perp * w * 0.6 + Vector3(0, 0, z) - up, p0 - perp * w + Vector3(0, 0, z) - up, _ao(chrome, 0.6))
		for sd in [-1.0, 1.0]:
			var e0: Vector3 = p0 + perp * w * sd + Vector3(0, 0, z)
			var e1: Vector3 = p1 + perp * w * 0.6 * sd + Vector3(0, 0, z)
			if sd > 0:
				g.quad(e0 - up, e0 + up, e1 + up, e1 - up, _ao(chrome, 0.8))
			else:
				g.quad(e0 + up, e0 - up, e1 - up, e1 + up, _ao(chrome, 0.8))
		# the knob, sticking out toward you
		g.box(p1 + Vector3(0, 0, z + 0.04), Vector3(0.024, 0.024, 0.07), [knob, knob, knob, knob, knob, knob])
	return g.commit()


func _mi(mesh: Mesh, parent: Node3D) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _shelf_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	return mi


func _build_banks() -> void:
	var crng := RandomNumberGenerator.new()
	crng.seed = 77
	var variants: Array[ArrayMesh] = []
	for v in 6:
		variants.append(_cartons_geo([1.0, -1.0], CAR_W, crng))
	var fixed_cartons := [_cartons_geo([1.0], FIX_W, crng), _cartons_geo([-1.0], FIX_W, crng)]
	var hmesh := _handle_mesh()
	for b in 2:
		var zc := (bank_z(b).x + bank_z(b).y) * 0.5
		# bank A's handles face north (-z), bank B's south (+z): carriages
		# are built with the handle at +z, bank A's turned round.
		var turn := PI if b == 0 else 0.0
		_cx[b].resize(NCAR)
		_hang[b].resize(NCAR)
		for i in NCAR:
			# (moved by hand in _physics_process: no sync to the physics
			# frame, which would snap it back to where physics last had it)
			var body := AnimatableBody3D.new()
			body.sync_to_physics = false
			var x := car_home(i, _aisle[b])
			_cx[b][i] = x
			body.position = Vector3(x, LEVEL_Y, zc)
			body.rotation.y = turn
			add_child(body)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(CAR_W, STACK_H, RANGE_L)
			cs.shape = bs
			cs.position = Vector3(0, STACK_H * 0.5, 0)
			body.add_child(cs)
			var g := Geo.new()
			_frame_geo(g, [1.0, -1.0], CAR_W, true, b * 24 + i)
			var bm := _mi(g.commit(), body)
			var cm := _mi(variants[_rng.randi() % variants.size()], body)
			if _rng.randf() < 0.5:
				cm.rotation.y = PI
			var hpiv := Node3D.new()
			body.add_child(hpiv)
			hpiv.position = Vector3(0, 1.06, RANGE_L * 0.5)
			var hm := _mi(hmesh, hpiv)
			_hang[b][i] = _rng.randf() * TAU
			hpiv.rotation.z = _hang[b][i]
			_cars[b].append(body)
			_bodies[b].append(bm)
			_cartons[b].append(cm)
			_handles[b].append(hpiv)
		# the fixed single-faced units against the side walls
		for side in 2:
			var fb := StaticBody3D.new()
			add_child(fb)
			var fxc := WALL_GAP + FIX_W * 0.5 if side == 0 else ROOM_W - WALL_GAP - FIX_W * 0.5
			fb.global_position = Vector3(fxc, LEVEL_Y, zc)
			fb.rotation.y = turn
			var cs2 := CollisionShape3D.new()
			var bs2 := BoxShape3D.new()
			bs2.size = Vector3(FIX_W, STACK_H, RANGE_L)
			cs2.shape = bs2
			cs2.position = Vector3(0, STACK_H * 0.5, 0)
			fb.add_child(cs2)
			# facing into the bank: +x for the west unit (turned round in bank A)
			var face := (1.0 if side == 0 else -1.0) * (-1.0 if b == 0 else 1.0)
			var g2 := Geo.new()
			_frame_geo(g2, [face], FIX_W, true, -2)
			var fm := _mi(g2.commit(), fb)
			fm.set_instance_shader_parameter("inst_bar", 0.0)
			var fc := _mi(fixed_cartons[0 if face > 0 else 1], fb)
			fc.name = "fixed_%d_%d" % [b, side]
			_bodies[b].append(fm)


func _build_cart() -> void:
	var g := Geo.new()
	var steel := Color(0.30, 0.31, 0.32)
	var dark := Color(0.03, 0.03, 0.03)
	var sx := CART_SIZE.x
	var sz := CART_SIZE.z
	for y in [0.20, 0.52, 0.84]:
		g.box(Vector3(0, y, 0), Vector3(sx, 0.025, sz), [_ao(steel, 1.0), _ao(steel, 0.4), steel, steel, steel, steel])
		g.box(Vector3(0, y + 0.03, 0), Vector3(sx + 0.004, 0.035, 0.012) + Vector3(0, 0, 0),
				[steel, steel, steel, steel, steel, steel])
	for px in [-1.0, 1.0]:
		for pz in [-1.0, 1.0]:
			g.box(Vector3(px * (sx * 0.5 - 0.012), 0.55, pz * (sz * 0.5 - 0.012)), Vector3(0.024, 0.9, 0.024),
					[steel, steel, steel, steel, steel, steel])
			g.box(Vector3(px * (sx * 0.5 - 0.03), 0.05, pz * (sz * 0.5 - 0.05)), Vector3(0.03, 0.1, 0.1),
					[dark, dark, dark, dark, dark, dark])
	# push handle (a loop at one end)
	g.box(Vector3(0, 1.0, sz * 0.5 - 0.01), Vector3(sx, 0.025, 0.025), [steel, steel, steel, steel, steel, steel])
	# two cartons and a stack of folders on it
	var tu := Rect2(Vector2(0.5, 0.5), Vector2(0.25, 0.25))
	var fu := Rect2(Vector2(0.0, 0.0), Vector2(0.25, 0.208))
	var su := Rect2(Vector2(0.0, 0.5), Vector2(0.25, 0.25))
	var w := Color(1, 1, 1)
	g.box(Vector3(0, 0.84 + 0.13 + 0.015, -0.18), Vector3(0.3, 0.26, 0.38), [_ao(w, 0.9), SKIP, _ao(w, 0.7), _ao(w, 0.7),
			_ao(w, 0.8), _ao(w, 0.8)], {0: tu, 2: su, 3: su, 4: fu, 5: fu})
	g.box(Vector3(0.01, 0.52 + 0.13 + 0.015, 0.2), Vector3(0.3, 0.26, 0.38), [_ao(w, 0.5), SKIP, _ao(w, 0.5), _ao(w, 0.5),
			_ao(w, 0.55), _ao(w, 0.55)], {0: tu, 2: su, 3: su, 4: fu, 5: fu})
	var pu := Rect2(Vector2(0.0, 0.75), Vector2(0.25, 0.25))
	g.box(Vector3(0.0, 0.84 + 0.03 + 0.015, 0.22), Vector3(0.24, 0.03, 0.30), [_ao(w, 1.0), SKIP, _ao(w, 0.8), _ao(w, 0.8),
			_ao(w, 0.8), _ao(w, 0.8)], {0: pu})
	_cart = AnimatableBody3D.new()
	_cart.sync_to_physics = false
	add_child(_cart)
	_mi(g.commit(), _cart)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = CART_SIZE
	cs.shape = bs
	cs.position = Vector3(0, CART_SIZE.y * 0.5, 0)
	_cart.add_child(cs)
	var a: int = _aisle[0]
	_cart_x = _gap_mid(0, a)
	_cart_z = bank_z(0).x + 2.9
	_cart.global_position = Vector3(_cart_x, LEVEL_Y, _cart_z)
	_cart.rotation.y = 0.03


func _gap_mid(b: int, a: int) -> float:
	var xl := FIX_L if a == 0 else _cx[b][a - 1] + CAR_W * 0.5
	var xr := FIX_R if a == NCAR else _cx[b][a] - CAR_W * 0.5
	return (xl + xr) * 0.5


## Sheets of paper (letter, two-sided) that slide off cartons.
func _build_papers() -> void:
	var pu := Rect2(Vector2(0.0, 0.75), Vector2(0.25, 0.25))
	var pu2 := Rect2(Vector2(0.25, 0.75), Vector2(0.25, 0.25))
	for i in 8:
		var g := Geo.new()
		var w := 8.5 * IN * 0.5
		var l := 11.0 * IN * 0.5
		var u: Rect2 = pu if i % 2 == 0 else pu2
		g.quad(Vector3(-w, 0, l), Vector3(w, 0, l), Vector3(w, 0, -l), Vector3(-w, 0, -l), Color(1, 1, 1), u)
		g.quad(Vector3(-w, -0.0005, -l), Vector3(w, -0.0005, -l), Vector3(w, -0.0005, l), Vector3(-w, -0.0005, l),
				Color(0.9, 0.9, 0.9), u)
		var n := Node3D.new()
		add_child(n)
		_mi(g.commit(), n)
		n.visible = false
		_papers.append({"node": n, "state": 0, "t": 0.0, "b": 0, "i": -1})


func _add_exit() -> void:
	# The exit door in the north wall (the rear aisle behind bank B): you
	# stand on its south side (+z). LevelEntrance's own door (frame, leaf,
	# the dark behind it); the ride ends just inside the room, on the floor.
	# (its parts are self-lit by the light there once the rear aisle's
	# strips are on)
	var was := _grp_on.duplicate()
	for g in 4:
		_grp_on[g] = 1.0
	add_exit(Transform3D(Basis(), _g(Vector2(EXIT_X, ROOM_D))), "door", "", {"label": "Open the exit door"})
	_grp_on = was


# --------------------------------------------------------------- the game ---

func on_enter() -> void:
	var cs := get_tree().current_scene
	_events = cs == null or not String(cs.scene_file_path).contains("level_shots")
	# The occupancy sensor over the main aisle sees you come in.
	if _events:
		_switch_on(0, 1.0)


func arrival() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), _g(Vector2(1.0, MAIN_Y)))       # facing east, down the main aisle


func surface_at(_p: Vector3) -> int:
	return Player.SURF_CONCRETE


func camera_far() -> float:
	return 24.0 if low else 32.0


## Concrete and block, but every shelf is full of cardboard: a short, damped room.
func reverb() -> Dictionary:
	return {"room": 0.5, "damp": 0.7, "wet": 0.2}


func light_at(p: Vector3) -> Color:
	var e := _light_level(p)
	return Color(_light_rgb.r * e, _light_rgb.g * e, _light_rgb.b * e)


## Horizontal light (engine units) at p from the rows as they are now and
## the aisle bars, ignoring the shelving's shade (used for the exposure,
## figures and the radar).
func _light_level(p: Vector3) -> float:
	var q := p - Vector3(0, LEVEL_Y, 0)
	var e := 0.0
	var i_row := STRIP_LM * 5.0 / (ROW_X.y - ROW_X.x) / PI / (PI * UNIT)
	for r in ROWS:
		var g: int = r[1]
		var lvl := 1.0 if g < 0 else _grp_on[g]
		var dy := STRIP_Y - q.y
		if dy < 0.05:
			continue
		var dz: float = -r[0] - q.z
		var rr := sqrt(dy * dy + dz * dz)
		var f := _f2(ROW_X.y - q.x, rr) - _f2(ROW_X.x - q.x, rr)
		var w := lvl
		if g == 0:
			w = _grp_on[0] * 0.8 + 0.2       # the night strip is in this row
		e += i_row * dy * dy * f * w
	# in a slot: shaded by the shelving
	for b in 2:
		var z := bank_z(b)
		if q.z > z.x and q.z < z.y and q.y < STACK_H:
			var gap := _gap_at(b, q.x)
			var w := maxf(gap.y - gap.x, 0.0)
			e *= clampf(w / (w + 1.1 * (STACK_H - q.y)) * 1.6, 0.05, 1.0)
			# its bars
			var bl := _bars_of(b, gap)
			e += (bl.x + bl.y) * 0.25
	return e * 1.3 + 0.002


static func _f2(s: float, r: float) -> float:
	var r2 := r * r
	return s / (2.0 * r2 * (s * s + r2)) + atan(s / r) / (2.0 * r2 * r)


## The faces either side of local x in bank b: (xl, xr), and the carriages
## (index or -1 for a fixed unit) as (il, ir) in z, w.
func _gap_at(b: int, x: float) -> Vector4:
	var g := Vector4(FIX_L, FIX_R, -1, -1)
	for i in NCAR:
		var c := _cx[b][i]
		var rf := c + CAR_W * 0.5
		var lf := c - CAR_W * 0.5
		if rf <= x + 0.002 and rf > g.x:
			g.x = rf
			g.z = i
		if lf >= x - 0.002 and lf < g.y:
			g.y = lf
			g.w = i
	return g


func _bars_of(b: int, gap: Vector4) -> Vector2:
	var l := _fix_bars[b * 2] if gap.z < 0 else _bars[b * NCAR + int(gap.z)]
	var r := _fix_bars[b * 2 + 1] if gap.w < 0 else _bars[b * NCAR + int(gap.w)]
	return Vector2(l, r)


func albedo_at(_p: Vector3, n: Vector3) -> Color:
	if n.y > 0.7:
		return Color(0.30, 0.295, 0.28)
	if n.y < -0.7:
		return Color(0.72, 0.72, 0.70)
	return Color(0.38, 0.30, 0.20)


func warm_materials() -> Array[Material]:
	return super()


func save_state() -> Dictionary:
	return {"aisle_a": _aisle[0], "aisle_b": _aisle[1], "first_b": _first_b, "first_a": _first_a,
			"cart_x": _cart_x, "lights": [_grp_on[0], _grp_on[1], _grp_on[2], _grp_on[3]]}


func load_state(d: Dictionary) -> void:
	_aisle[0] = int(d.get("aisle_a", _aisle[0]))
	_aisle[1] = int(d.get("aisle_b", _aisle[1]))
	_first_b = bool(d.get("first_b", true))
	_first_a = bool(d.get("first_a", true))
	for b in 2:
		for i in NCAR:
			_set_car(b, i, car_home(i, _aisle[b]))
	_cart_x = float(d.get("cart_x", _gap_mid(0, _aisle[0])))
	_cart.global_position = Vector3(_cart_x, LEVEL_Y, _cart_z)
	var l: Array = d.get("lights", [])
	for g in mini(l.size(), 4):
		_grp_on[g] = float(l[g])
		_grp_want[g] = _grp_on[g]
		set_light_group(g, _light_rgb, _grp_on[g])
	_dirty = true


func _set_car(b: int, i: int, x: float) -> void:
	_cx[b][i] = x
	var body: Node3D = _cars[b][i]
	body.global_position.x = x
	_dirty = true


# ----------------------------------------------------------------- lights ---

## The occupancy sensor for group g sees motion: relay, ~1.1 s of cathode
## preheat, the lamps strike.
func _switch_on(g: int, delay := 0.0) -> void:
	if _grp_want[g] > 0.5:
		return
	_grp_want[g] = 1.0
	var at := _t + delay
	_grp_seq.append([at, g, -1.0, "relay"])
	_grp_seq.append([at + 0.02, g, 0.004, "ballast_start"])
	_grp_seq.append([at + 1.12, g, 0.6, ""])
	_grp_seq.append([at + 1.2, g, 1.0, ""])
	if _rng.randf() < 0.5:
		var t := at + 1.3
		for i in _rng.randi_range(2, 4):
			_grp_seq.append([t, g, 0.55, ""])
			t += _rng.randf_range(0.04, 0.09)
			_grp_seq.append([t, g, 1.0, ""])
			t += _rng.randf_range(0.08, 0.3)
	_grp_seq.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


func _row_pos(g: int) -> Vector3:
	for r in ROWS:
		if r[1] == g:
			return _g(Vector2(clampf(player.global_position.x if player else 5.8, 1.0, 10.6), r[0]), STRIP_Y)
	return _g(Vector2(5.8, MAIN_Y), STRIP_Y)


func _update_lights() -> void:
	while not _grp_seq.is_empty() and _grp_seq[0][0] <= _t:
		var e: Array = _grp_seq.pop_front()
		var g: int = e[1]
		if e[2] >= 0.0:
			_grp_on[g] = e[2]
		match e[3]:
			"relay":
				_play_at(_streams.get("relay"), _g(Vector2(0.4, MAIN_Y - 1.2), 2.0), -12.0, _rng.randf_range(0.95, 1.05), 3000.0)
			"ballast_start":
				_play_at(_streams.get("ballast_start"), _row_pos(g), -10.0, _rng.randf_range(0.97, 1.03))
	for g in 4:
		set_light_group(g, _light_rgb, _grp_on[g])
	for h in _hums:
		var a: AudioStreamPlayer3D = h[0]
		var g: int = h[1]
		var o := _grp_on[g] if g >= 0 else 1.0
		a.volume_db = linear_to_db(maxf(o, 0.0001)) - 20.0 if o > 0.01 else -80.0


func _set_bar(b: int, gap: Vector4, on: float) -> void:
	var changed := false
	if gap.z < 0:
		changed = changed or _fix_bars[b * 2] != on
		_fix_bars[b * 2] = on
	else:
		changed = changed or _bars[b * NCAR + int(gap.z)] != on
		_bars[b * NCAR + int(gap.z)] = on
	if gap.w < 0:
		changed = changed or _fix_bars[b * 2 + 1] != on
		_fix_bars[b * 2 + 1] = on
	else:
		changed = changed or _bars[b * NCAR + int(gap.w)] != on
		_bars[b * NCAR + int(gap.w)] = on
	if changed:
		_dirty = true
		for k in [int(gap.z), int(gap.w)]:
			if k >= 0:
				(_bodies[b][k] as MeshInstance3D).set_instance_shader_parameter("inst_bar", on)
		if gap.z < 0:
			(_bodies[b][NCAR] as MeshInstance3D).set_instance_shader_parameter("inst_bar", on)
		if gap.w < 0:
			(_bodies[b][NCAR + 1] as MeshInstance3D).set_instance_shader_parameter("inst_bar", on)


## The aisle a bank's open gap is (the one at least AISLE - 0.05 wide).
func _open_gap(b: int) -> Vector4:
	for a in NCAR + 1:
		var xl := FIX_L if a == 0 else _cx[b][a - 1] + CAR_W * 0.5
		var xr := FIX_R if a == NCAR else _cx[b][a] - CAR_W * 0.5
		if xr - xl > 0.3:
			return Vector4(xl, xr, a - 1, a if a < NCAR else -1)
	return Vector4(0, 0, -2, -2)


# ------------------------------------------------------------ bank motion ---

## Starts bank b closing aisle `a` (which side moves: dir +1 the carriages
## west of it move east). `limit`: how far they can go (the cart).
func _start_close(b: int, side: int, limit := AISLE) -> void:
	var a: int = _aisle[b]
	if side > 0:
		_grp[b] = Vector2i(0, a - 1)
		_new_aisle[b] = 0
	else:
		_grp[b] = Vector2i(a, NCAR - 1)
		_new_aisle[b] = NCAR
	if _grp[b].y < _grp[b].x:
		return
	_gdir[b] = float(side)
	_gdist[b] = limit
	_gmoved[b] = 0.0
	_gv[b] = 0.0
	_gfrom[b] = _cx[b].duplicate()
	_state[b] = 1
	_st[b] = 0.0
	_warn_lit[b] = _bar_any(b, _open_gap(b)) > 0.01
	var mid := _g(Vector2(_gap_mid(b, a), BANK_Y[b] + RANGE_L * 0.5), 1.2)
	_play_at(_pick("creak_"), mid, -6.0, _rng.randf_range(0.92, 1.05))


func _group_x(b: int) -> float:
	var g: Vector2i = _grp[b]
	return (_cx[b][g.x] + _cx[b][g.y]) * 0.5


func _update_bank(b: int, delta: float) -> void:
	var s: int = _state[b]
	if s == 0:
		return
	_st[b] += delta
	var g: Vector2i = _grp[b]
	var gx := _group_x(b)
	var mid := _g(Vector2(gx, BANK_Y[b] + RANGE_L * 0.5), 0.3)
	var hz := handle_z(b)
	var near := player.global_position.distance_to(mid)
	match s:
		1:
			# Warning: the aisle bar flickers and goes out, the cartons
			# shiver, the handles twitch.
			var gap := _open_gap(b)
			var k: float = _st[b]
			if gap.z > -1.5 and _warn_lit[b]:
				if k < 0.8:
					_set_bar(b, gap, 1.0 if (k < 0.15 or fmod(k * 13.0, 1.0) > 0.35) else 0.12)
				else:
					_set_bar(b, gap, 0.0)
					_warn_lit[b] = false
					_play_at(_streams.get("led_click"), mid + Vector3(0, 2.0, 0), -10.0)
			for i in range(g.x, g.y + 1):
				var tw := sin(_t * 20.0 + i) * 0.12 * k
				(_handles[b][i] as Node3D).rotation.z = _hang[b][i] + tw
				(_cartons[b][i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", k * 0.6)
			if k >= WARN_T:
				_state[b] = 2
				_st[b] = 0.0
				_play_at(_pick("carton_"), mid + Vector3(0, 1.4, 0), -8.0)
		2, 4:
			var back := s == 4
			var vmax := VMAX if not back else VMAX * 0.6
			_gv[b] = minf(_gv[b] + vmax / ACCEL_T * delta, vmax)
			var step: float = _gv[b] * delta
			var left: float = _gdist[b] - _gmoved[b]
			var done := step >= left
			step = minf(step, left)
			_gmoved[b] += step
			var dx: float = step * _gdir[b] * (-1.0 if back else 1.0)
			for i in range(g.x, g.y + 1):
				_set_car(b, i, _cx[b][i] + dx)
				_hang[b][i] += dx / PER_TURN * TAU * (1.0 if b == 1 else -1.0)
				(_handles[b][i] as Node3D).rotation.z = _hang[b][i]
				(_cartons[b][i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", 0.35 + 0.4 * _gv[b] / VMAX)
			if b == 0 and not back:
				_push_cart(dx)
			var sp: float = _gv[b] / VMAX
			_rumble[b].global_position = mid
			_rumble[b].volume_db = linear_to_db(maxf(sp, 0.0001)) - 4.0
			_rumble[b].pitch_scale = 0.7 + 0.3 * sp
			_drive[b].global_position = Vector3(gx, LEVEL_Y + 1.0, hz)
			_drive[b].volume_db = linear_to_db(maxf(sp, 0.0001)) - 8.0
			_drive[b].pitch_scale = 0.6 + 0.4 * sp
			rumble = 0.006 * sp * clampf(1.0 - near / 9.0, 0.0, 1.0)
			if done:
				_stop_bank(b, back)
		3:
			# Stopped against the cart: a moment, then back the way they came.
			if _st[b] > 2.2:
				_state[b] = 4
				_st[b] = 0.0
				_gmoved[b] = 0.0
				_gdist[b] = _gdist_back(b)
				_gv[b] = 0.0


func _gdist_back(b: int) -> float:
	var g: Vector2i = _grp[b]
	return absf(_cx[b][g.x] - _gfrom[b][g.x])


func _bar_any(b: int, gap: Vector4) -> float:
	if gap.z < -1.5:
		return 0.0
	var v := _bars_of(b, gap)
	return maxf(v.x, v.y)


func _stop_bank(b: int, was_back: bool) -> void:
	var g: Vector2i = _grp[b]
	var gx := _group_x(b)
	var mid := _g(Vector2(gx, BANK_Y[b] + RANGE_L * 0.5), 0.5)
	_rumble[b].volume_db = -80.0
	_drive[b].volume_db = -80.0
	rumble = 0.0
	for i in range(g.x, g.y + 1):
		(_cartons[b][i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", 0.0)
	if was_back:
		_state[b] = 0
		_play_at(_pick("carton_"), mid + Vector3(0, 1.2, 0), -12.0)
		return
	_play_at(_pick("clunk_"), mid, -1.0, _rng.randf_range(0.95, 1.05))
	var near := player.global_position.distance_to(mid)
	shake(clampf(0.03 - near * 0.002, 0.004, 0.03), 0.5)
	# the jolt: a few cartons jump, papers slide off the faces of the new aisle
	_jolt_cartons(b, 0.5)
	if b == 0 and _gdist[b] < AISLE - 0.01:
		# against the cart
		_play_at(_pick("cart_"), Vector3(_cart_x, LEVEL_Y + 0.6, _cart_z), -4.0)
		_drop_papers(b, 2)
		_state[b] = 3
		_st[b] = 0.0
		return
	_aisle[b] = _new_aisle[b]
	_state[b] = 0
	_drop_papers(b, 1 + _rng.randi() % 2)
	_dirty = true


func _jolt_cartons(b: int, amt: float) -> void:
	var g: Vector2i = _grp[b]
	for i in range(g.x, g.y + 1):
		(_cartons[b][i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", amt)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		for i in range(g.x, g.y + 1):
			if is_instance_valid(_cartons[b][i]):
				(_cartons[b][i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", 0.0))


## The cart in bank A's aisle shoved along by the closing face.
func _push_cart(dx: float) -> void:
	var g: Vector2i = _grp[0]
	var face: float
	if _gdir[0] > 0:
		face = _cx[0][g.y] + CAR_W * 0.5
		var need := face - (_cart_x - CART_SIZE.x * 0.5)
		if need > 0.0:
			_cart_x += need
	else:
		face = _cx[0][g.x] - CAR_W * 0.5
		var need2 := (_cart_x + CART_SIZE.x * 0.5) - face
		if need2 > 0.0:
			_cart_x -= need2
	_cart.global_position.x = _cart_x


## How far bank A's carriages can close before the cart stops them.
func _cart_limit(side: int) -> float:
	var a: int = _aisle[0]
	var xl := FIX_L if a == 0 else _cx[0][a - 1] + CAR_W * 0.5
	var xr := FIX_R if a == NCAR else _cx[0][a] - CAR_W * 0.5
	if _cart_x < xl or _cart_x > xr:
		return AISLE
	return (xr - xl) - CART_SIZE.x - 0.004


func _drop_papers(b: int, n: int) -> void:
	var gap := _open_gap(b)
	if gap.z < -1.5:
		gap = Vector4(_gap_mid(b, _aisle[b]) - 0.45, _gap_mid(b, _aisle[b]) + 0.45, 0, 0)
	var z := bank_z(b)
	for k in n:
		var p: Dictionary = _papers[_paper_i]
		_paper_i = (_paper_i + 1) % _papers.size()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var x0: float = gap.x if side > 0 else gap.y
		var lev := _rng.randi_range(2, NLEV - 1)
		var y0 := SHELF_Y0 + lev * SHELF_P - 0.035 + 0.005
		var zz := _rng.randf_range(z.x + 0.6, z.y - 0.6)
		p.state = 1
		p.t = -k * 0.35
		p.from = Vector3(x0 - side * 0.12, LEVEL_Y + y0, zz)
		p.dir = side
		p.yaw = _rng.randf_range(-0.5, 0.5)
		p.f = _rng.randf_range(1.2, 1.9)
		p.b = b
		var n3: Node3D = p.node
		n3.visible = false


func _update_papers(delta: float) -> void:
	for p in _papers:
		var n: Node3D = p.node
		if p.state == 1:
			p.t += delta
			var t: float = p.t
			if t < 0.0:
				continue
			if not n.visible:
				n.visible = true
				_play_at(_pick("paper_"), p.from, -12.0, _rng.randf_range(0.9, 1.1))
			var from: Vector3 = p.from
			var side: float = p.dir
			if t < 0.35:
				# slides out off the carton's front edge, tipping
				var k := t / 0.35
				n.global_position = from + Vector3(side * 0.16 * k * k, 0, 0)
				n.rotation = Vector3(0, p.yaw, -side * 0.6 * k * k)
			else:
				# falls, fluttering: ~0.8 m/s, swaying 0.12 m
				var tf := t - 0.35
				var y := from.y - 0.8 * tf - 0.6 * maxf(0.4 - tf, 0.0) * 0.0
				var sway := sin(tf * TAU * float(p.f)) * 0.12 * minf(tf * 2.0, 1.0)
				var x := from.x + side * (0.16 + 0.35 * (1.0 - exp(-tf * 1.5))) + sway * 0.6
				var land := LEVEL_Y + 0.002
				if y <= land:
					y = land
					p.state = 2
					n.rotation = Vector3(0, p.yaw + tf, 0)
				else:
					n.rotation = Vector3(sin(tf * 5.0) * 0.5, p.yaw + tf * 0.8, -side * 0.6 + cos(tf * TAU * float(p.f)) * 0.6)
				n.global_position = Vector3(x, y, from.z + sin(tf * 3.1) * 0.05)
		elif p.state == 2:
			# under a carriage now? out of sight.
			var b: int = p.b
			var x := n.global_position.x
			for i in NCAR:
				if absf(x - _cx[b][i]) < CAR_W * 0.5 - 0.1:
					n.visible = false
					p.state = 0
					break


# --------------------------------------------------------------- events ---

## Where you are in the banks: (bank, depth into its range) or (-1, 0).
func _where() -> Vector2:
	var q := player.global_position - Vector3(0, LEVEL_Y, 0)
	for b in 2:
		var z := bank_z(b)
		if q.z > z.x and q.z < z.y:
			var hz := handle_z(b)
			return Vector2(b, absf(q.z - hz))
	return Vector2(-1, 0)


func _update_events(delta: float) -> void:
	var q := player.global_position - Vector3(0, LEVEL_Y, 0)
	var w := _where()
	var by := -q.z
	# Lights: the sensors see you.
	if by < REAR + 0.2 or (int(w.x) == 0):
		_switch_on(1)
	if int(w.x) == 1:
		_switch_on(2)
		if w.y > 3.0:
			_switch_on(3)
	if by > ROOM_D - REAR - 0.2:
		_switch_on(3)
	# Aisle bars: on when you're in the aisle or at its mouth.
	for b in 2:
		if _state[b] != 0:
			continue
		var z := bank_z(b)
		var hz := handle_z(b)
		var gap := _gap_at(b, q.x)
		var at_mouth := absf(q.z - hz) < 1.0 and gap.y - gap.x > 0.5
		var inside := q.z > z.x and q.z < z.y
		if (at_mouth or inside) and _bar_any(b, gap) < 0.5 and gap.y - gap.x > 0.5:
			_set_bar(b, gap, 1.0)
			_play_at(_streams.get("led_click"), Vector3(player.global_position.x, LEVEL_Y + 2.2, player.global_position.z), -14.0)
	if not _events:
		return
	# Standing in an aisle: it shuts on you, after a while.
	for b in 2:
		var inside: bool = int(w.x) == b and w.y > 1.0
		if inside and _state[b] == 0:
			_inside_t[b] += delta
			if _trigger_t[b] <= 0.0:
				_trigger_t[b] = (0.9 if (b == 1 and _first_b) else _rng.randf_range(2.6, 6.0))
			var deep_enough: bool = w.y > 2.0 or not (b == 1 and _first_b)
			if deep_enough and _inside_t[b] > _trigger_t[b]:
				_trigger_t[b] = 0.0
				_inside_t[b] = 0.0
				var a: int = _aisle[b]
				var side := 1 if _rng.randf() < 0.5 else -1
				if b == 1 and _first_b:
					side = -1           # the east carriages: the new aisle opens by the exit
					_first_b = false
				if a == 0:
					side = -1
				elif a == NCAR:
					side = 1
				if b == 0:
					_switch_on(1)
					_start_close(0, side, _cart_limit(side))
				else:
					_switch_on(2)
					_start_close(1, side)
		elif not inside:
			_inside_t[b] = 0.0
	# Bank A shoves at its cart the first time you pass its aisle.
	if _first_a and int(w.x) == -1 and absf(q.x - _gap_mid(0, _aisle[0])) < 2.2 and absf(-q.z - MAIN_Y) < 1.2 \
			and _state[0] == 0 and _t > 4.0:
		_first_a = false
		_switch_on(1)
		var side := 1 if _rng.randf() < 0.5 else -1
		if _aisle[0] == 0:
			side = -1
		elif _aisle[0] == NCAR:
			side = 1
		get_tree().create_timer(1.6).timeout.connect(func() -> void:
			if _state[0] == 0:
				_start_close(0, side, _cart_limit(side)))
	# Now and then a range moves while you're out of the banks.
	_next_event -= delta
	if _next_event <= 0.0 and int(w.x) == -1 and _state[0] == 0 and _state[1] == 0 and not _first_b:
		_next_event = _rng.randf_range(28.0, 50.0)
		var b := 1 if _rng.randf() < 0.65 else 0
		var a: int = _aisle[b]
		var side := 1 if _rng.randf() < 0.5 else -1
		if a == 0:
			side = -1
		elif a == NCAR:
			side = 1
		# (never shut the aisle you're standing at the mouth of)
		_switch_on(1 if b == 0 else 2)
		_start_close(b, side, _cart_limit(side) if b == 0 else AISLE)
	elif _next_event <= 0.0:
		_next_event = 5.0


## Caught between two faces (or a face and the cart).
func _check_crush() -> void:
	if _crushing:
		return
	var q := player.global_position - Vector3(0, LEVEL_Y, 0)
	for b in 2:
		if _state[b] != 2:
			continue
		var z := bank_z(b)
		if q.z < z.x + 0.05 or q.z > z.y - 0.05:
			continue
		var gap := _gap_at(b, q.x)
		var w := gap.y - gap.x
		if b == 0 and absf(q.z - _cart_z) < CART_SIZE.z * 0.5 + 0.3 and _cart_x > gap.x and _cart_x < gap.y:
			w -= CART_SIZE.x
		var inside_car := false
		for i in NCAR:
			if absf(q.x - _cx[b][i]) < CAR_W * 0.5 - 0.05:
				inside_car = true
		if w < CRUSH_GAP or inside_car:
			_crush(b)
			return


func _crush(b: int) -> void:
	_crushing = true
	_crush_t = 0.0
	player.controls_enabled = false
	_play_at(_streams.get("crush"), player.global_position + Vector3(0, 1.0, 0), 2.0, 1.0)
	shake(0.06, 1.0)
	rumble = 0.02
	get_tree().create_timer(0.75).timeout.connect(func() -> void:
		_state[b] = 3
		_st[b] = -1000.0
		_rumble[b].volume_db = -80.0
		_drive[b].volume_db = -80.0
		rumble = 0.0
		catch_player(["The handles were still turning when the gap closed.",
				"Somewhere down the range, cartons settled.",
				"The aisle light came on for nobody."]))


func _update_exposure(delta: float) -> void:
	var cam := player.camera.global_position
	var f := -player.camera.global_basis.z
	var l := 0.5 * _light_level(cam - Vector3(0, 0.8, 0)) + 0.5 * _light_level(cam + f * 3.0 - Vector3(0, 0.8, 0))
	var target := clampf(0.42 / maxf(l, 0.002), 0.5, 10.0)
	var rate := 0.6 if target > _ae else 3.0
	_ae = lerpf(_ae, target, 1.0 - exp(-delta * rate))
	environment.tonemap_exposure = _base_exposure * _ae


func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	_update_lights()
	_update_events(delta)
	_update_papers(delta)
	_update_exposure(delta)
	if _dirty:
		_push_banks()


func _physics_process(delta: float) -> void:
	if player == null:
		return
	for b in 2:
		_update_bank(b, delta)
	if _crushing:
		# the ranges keep grinding in a little
		_crush_t += delta
	_check_crush()


# --------------------------------------------------------------- harness ---

## yaw 0 faces north (-Z), 90 west, 180 south, -90 east.
func _view(at: Vector2, yaw_deg: float, pitch := 0.0) -> Transform3D:
	var bas := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(bas, _g(at))


func _lights_on() -> void:
	_grp_seq.clear()
	for g in 4:
		_grp_on[g] = 1.0
		_grp_want[g] = 1.0
	_update_lights()


## Bank b with its aisle at `a`, carriages home (harness).
func _set_aisle(b: int, a: int, close := 0.0) -> void:
	_state[b] = 0
	_aisle[b] = a
	for i in NCAR:
		_set_car(b, i, car_home(i, a))
	if close > 0.0:
		for i in range(a, NCAR):
			_set_car(b, i, _cx[b][i] - close)
	for i in 2 * NCAR:
		_bars[i] = 0.0
	for i in 4:
		_fix_bars[i] = 0.0
	for k in _bodies[b].size():
		(_bodies[b][k] as MeshInstance3D).set_instance_shader_parameter("inst_bar", 0.0)
	_push_banks()


func shots() -> Array:
	var ab: int = _aisle[1]
	var mb := _gap_mid(1, ab)
	var ma := _gap_mid(0, _aisle[0])
	var bz := BANK_Y[1]
	return [
		{"name": "arrival_dark", "transform": _view(Vector2(1.0, MAIN_Y), -90.0, -0.06), "wait": 2.5, "call": func() -> void:
			_grp_seq.clear()
			for g in 4:
				_grp_on[g] = 0.0
			_update_lights()},
		{"name": "arrival", "transform": _view(Vector2(1.0, MAIN_Y), -90.0, -0.06), "wait": 2.5, "call": _lights_on},
		{"name": "handles", "transform": _view(Vector2(mb - 1.6, MAIN_Y - 0.1), -55.0, -0.12), "call": _lights_on},
		{"name": "aisle_b", "transform": _view(Vector2(mb, bz + 0.6), 0.0, -0.04), "call": func() -> void:
			_lights_on()
			_set_bar(1, _gap_at(1, mb), 1.0)},
		{"name": "aisle_b_deep", "transform": _view(Vector2(mb + 0.05, bz + 3.4), 180.0, -0.05), "call": func() -> void:
			_lights_on()
			_set_bar(1, _gap_at(1, mb), 1.0)},
		{"name": "closing", "transform": _view(Vector2(mb - 0.12, bz + 2.4), 0.0, 0.02), "call": func() -> void:
			_lights_on()
			_set_aisle(1, ab, 0.3)},
		{"name": "cart", "transform": _view(Vector2(ma, MAIN_Y - 0.2), 180.0, -0.15), "call": func() -> void:
			_set_aisle(1, ab)
			_lights_on()
			_set_bar(0, _gap_at(0, ma), 1.0)},
		{"name": "rear_exit", "transform": _view(Vector2(4.2, ROOM_D - 0.55), -84.0, -0.02), "call": _lights_on},
		{"name": "ceiling", "transform": _view(Vector2(4.0, MAIN_Y), -70.0, 0.75), "call": _lights_on},
		{"name": "main_west", "transform": _view(Vector2(10.6, MAIN_Y + 0.3), 90.0, -0.05), "call": _lights_on},
	]


## Film: coming in to the dark, the lights striking; along the main aisle,
## bank A shoving its cart; into bank B's aisle, which shuts on you; back
## out, and through the new aisle by the exit to the door.
func film() -> void:
	_events = true
	player.set_flashlight(false)
	for g in 4:
		_grp_on[g] = 0.0
		_grp_want[g] = 0.0
	player.teleport(_g(Vector2(1.0, MAIN_Y)), -PI * 0.5, -0.05)
	_switch_on(0, 0.8)
	await get_tree().create_timer(3.0).timeout
	var ma := _gap_mid(0, _aisle[0])
	await _walk_to(Vector2(ma - 0.25, MAIN_Y - 0.1), 8.0)
	await _turn_to(PI - 0.12, -0.1, 1.0)
	await _until_idle(0, 16.0)
	await get_tree().create_timer(1.0).timeout
	var mb := _gap_mid(1, _aisle[1])
	await _turn_to(-PI * 0.5, -0.05, 0.8)
	await _walk_to(Vector2(mb, MAIN_Y - 0.3), 8.0)
	await _turn_to(0.0, -0.03, 0.6)
	await _walk_to(Vector2(mb, BANK_Y[1] + 2.4), 4.0)
	await get_tree().create_timer(0.7).timeout
	await _turn_to(PI, -0.05, 0.6)
	await _walk_to(Vector2(mb, MAIN_Y - 0.2), 4.0)
	await _turn_to(0.25, -0.05, 0.6)
	await _until_idle(1, 16.0)
	await get_tree().create_timer(0.6).timeout
	var ex := _gap_mid(1, _aisle[1])
	await _walk_to(Vector2(ex, MAIN_Y - 0.3), 6.0)
	await _turn_to(0.0, -0.03, 0.4)
	await _walk_to(Vector2(ex, ROOM_D - 0.6), 6.0)
	await _walk_to(Vector2(EXIT_X, ROOM_D - 0.7), 3.0)
	await _turn_to(0.0, -0.05, 0.5)
	for e in get_tree().get_nodes_in_group("usable"):
		var le := e as LevelEntrance
		if le and le.exit_of == self:
			await le.enter(player)
	await get_tree().create_timer(0.8).timeout


func _until_idle(b: int, limit: float) -> void:
	var t := 0.0
	while (_state[b] != 0 or t < 2.0) and t < limit:
		t += get_process_delta_time()
		await get_tree().process_frame


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


func _walk_to(to: Vector2, limit: float) -> void:
	var t := 0.0
	Input.action_press("move_forward")
	while t < limit:
		var p := player.global_position
		var d := to - Vector2(p.x, -p.z)
		if d.length() < 0.3:
			break
		var want := atan2(-d.x, d.y)
		player.yaw = lerp_angle(player.yaw, want, 0.12)
		player._apply_rotation()
		t += get_process_delta_time()
		await get_tree().process_frame
	Input.action_release("move_forward")
