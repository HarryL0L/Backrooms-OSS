extends SideLevel
## The Stacks: a records centre's storage floor after hours, about 1030 m2
## behind 8 in block fire-barrier walls. Five storage bays and a sorting
## room off two 72 in service corridors, every bay filled wall to wall with
## mechanical-assist mobile shelving: carriages of cartons on flush floor
## rails, a three-spoke handle on every end panel. The open aisles are the
## only ways through the bays, and nobody is turning the handles.
##
## The floor plan is tools/blender/levels/filing_layout.py (written out as
## filing_layout.gd); its real sizes, masses and light are in
## assets/levels/filing/SPEC.md. You come in through Bay 1's archive door
## (the room the Stacks once was); the way out is the exit door on the far
## side of Bay 4, the dark bay, lit only by its aisle bars and four strips
## on occupancy sensors that time out behind you. Three ways lead there:
## through Bay 2's long east-west aisles, through a fire door from corridor
## A that opens straight onto Bay 4's range ends (only when an aisle lines
## up with it), or through Bay 3 and corridor B. Signs on the doors, range
## cards on every end panel and floor plans ("YOU ARE HERE"; one of them an
## old revision) are what you find your way by. The other way on is STAIR 2
## at the far end of corridor B (as deep in the maze as the exit: corridor B
## is reached only through Bay 3's or Bay 4's moving shelving): the service
## stair down into Level 4.1, the Endless Stairwell. So you choose: escape
## through the exit, or go down. Corridor A's EXIT sign points the other way,
## at STAIR 1, which is locked (where the old plan in Bay 2 still has the exit).
##
## Ranges roll by themselves: the frames creak, the cartons shiver, the
## aisle light flickers out, the handles spin, the rails rumble, and the
## carriages between the closing aisle and the one opening roll together
## (as cranking one end of a real run does) until they meet with a clunk.
## Stand in an aisle too long and it shuts on you (catch_player: crushed),
## but the warning always leaves the time to walk out of it at a walk
## (_warn_for), and a bank always has an aisle open: no route is shut for
## good (proved by _test/levels/filing_maze_test.tscn). In Bay 4 something
## knocks from inside the shut shelving, keeping pace with you.

const LAYOUT := preload("res://scripts/world/levels/filing_layout.gd")
const NAME := "Level 1.1 - The Stacks"
const INTRO := "Records nobody will ever ask for. The shelves move on their own."
const DIR := "res://assets/levels/filing/"
const TEX := "res://assets/levels/filing/textures"
const AUD := "res://assets/levels/filing/audio/"
const FILING_SHADER := "res://assets/levels/filing/filing_lit.gdshader"
const FILING_SHADER_CUTOUT := "res://assets/levels/filing/filing_lit_cutout.gdshader"

## Sizes (m), as tools/blender/levels/filing_layout.py.
const IN := 0.0254
const SEC_W := 42 * IN
const END_T := 0.025
const SHELF_D := 15 * IN
const FLUE := 2 * IN
const CAR_W := 2 * SHELF_D + FLUE
const FIX_W := SHELF_D + 0.04
const AISLE := 36 * IN
const CEIL := 3.2
const STACK_H := 2.30
const SHELF_Y0 := 0.14
const SHELF_P := 0.305
const NLEV := 7
const STRIP_Y := 2.85
## L.U.C.I.D. light. Strip: 4500 lm x LLF 0.85 (Lucid strip_t8_2lamp); a
## row of strips is a Lambertian line source of its lumens over its length,
## I = (lm / m) / pi cd/m, stored as cd/(m pi 153.6). Tubes: 6520 cd/m2.
const UNIT := 153.6
const STRIP_LM := 4500.0 * 0.85
const TUBE_EMIT := 4500.0 * 0.85 / (PI * 2.0 * (TAU * 0.0127 * 1.17)) / 153.6
const EXIT_EMIT := 300.0 / 153.6
## Aisle light bars: 820 lm/m LED (4000 K), a 30 mm diffuser (8700 cd/m2);
## on with motion in the aisle, off 20 s after you leave it.
const BAR_LM_M := 820.0
const BAR_EMIT := 820.0 / PI / 0.03 / 153.6
const BAR_TIMEOUT := 20.0
## Carriage motion: a brisk crank's 0.11 m/s (powered systems are held to
## 0.076 m/s), reached in 1.2 s; 6:1 drive on 5 in wheels: 0.0665 m per
## turn of the handle.
const VMAX := 0.11
const ACCEL_T := 1.2
const PER_TURN := 0.0665
## Fair warning: before a closing aisle is narrower than you (CRUSH_GAP),
## you can react (REACT) and walk (WALK) out of its furthest point to an
## open end; never less than WARN_MIN of creaking and flicker.
const WALK := 2.6
const REACT := 1.5
const WARN_MIN := 1.5
const CRUSH_GAP := 0.64
const SAFETY := 0.3
## The cart (a records truck, 33 x 14 in, 40 in high).
const CART_SIZE := Vector3(0.36, 1.0, 0.84)
## At most this many banks move at once, floor-wide.
const MAX_MOVING := 2
## The walk grid (tests, the film): cell size (m), the player's radius.
const GRID := 0.25
const PLAYER_R := 0.3


## A room or corridor of the plan.
class Cell:
	var id := ""
	var name := ""
	var kind := ""
	var rect := Rect2()             # Blender x, y
	var ax := Vector2(1, 0)         # the frame: the carriages' motion (Godot x, z)
	var timeout := 120.0
	var dark := false
	var root: Node3D
	var kit: Node3D
	var mats: Array[ShaderMaterial] = []
	var shelf: ShaderMaterial
	var banks: Array = []
	var rows: Array = []            # {lz, x0, x1, i, g, a, b (Godot xz)}
	var sensors := {}               # group -> Array[Rect2] (Blender)
	var grp_on := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var grp_want := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
	var grp_seen := PackedFloat32Array([-1e9, -1e9, -1e9, -1e9])
	var seq: Array = []             # [time, group, level, sound]
	var portals: Array = []         # {to: Cell, a: Vector2, b: Vector2} (Godot x, z)
	var objs: Array = []            # [GeometryInstance3D, Rect2 (Godot x, z)]
	var hum: AudioStreamPlayer3D
	var dirty := true
	var lit_dirty := true
	var shown := -1
	var spills: Array = []          # {to: Cell (the room the light comes from), p: Vector3 local, n: Vector3 local, src: Vector3 world, area}

	func az() -> Vector2:
		return Vector2(-ax.y, ax.x)


## A bank of mobile shelving: n carriages between two fixed units. Local
## frame: x along the motion (the cell's frame), z along the ranges.
class Bank:
	var cell: Cell
	var bi := 0                     # in its cell
	var gi := 0                     # floor-wide
	var name := ""
	var label := ""
	var n := 12
	var nsec := 6
	var L := 6.451
	var xl := 0.0                   # the fixed units' faces
	var xr := 0.0
	var z0 := 0.0
	var z1 := 0.0
	var hz := 0.0                   # the handle end
	var fz := 0.0                   # the far end
	var rear := "aisle"
	var yaw := 0.0
	var sx := 1.0
	var card0 := 0
	var gated: Array = []           # [x0, x1]: fire doors at the far end
	var cx := PackedFloat32Array()
	var bodies: Array = []
	var meshes: Array = []
	var full := PackedByteArray()
	var variant := PackedInt32Array()
	var hang := PackedFloat32Array()
	var bars := PackedFloat32Array()
	var bar_t := PackedFloat32Array()
	var fix_bars := PackedFloat32Array([0.0, 0.0])
	var fix_t := PackedFloat32Array([0.0, 0.0])
	var fixed: Array = []
	var state := 0                  # 0 idle, 1 warning, 2 moving, 3 stopped (cart), 4 going back
	var st := 0.0
	var grp := Vector2i.ZERO
	var gdir := 0.0
	var gdist := 0.0
	var gmoved := 0.0
	var gv := 0.0
	var gfrom := PackedFloat32Array()
	var close_gap := 0
	var open_gap := 0
	var warn := 1.5
	var warn_lit := false
	var rumble: AudioStreamPlayer3D
	var drive: AudioStreamPlayer3D
	var inside_t := 0.0
	var trigger_t := 0.0
	var log_i := -1
	var nopen := 1


var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _events := true
var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _light_rgb := Color.WHITE
var _bar_rgb := Color.WHITE
var _base_exposure := 1.0
var _ae := 1.0
var _cells := {}
var _cell_list: Array = []
var _banks: Array = []
var _variants := {}
var _cur: Cell
var _ppos := Vector3.ZERO
## Tests: no sound, no catch (crushes counted), the player stands where told.
var sim := false
var sim_crushes := 0
## Every close: {b, c, t0 (warning), warn, tm (moving), tc (narrower than CRUSH_GAP), w}.
var events_log: Array = []
var _next_event := 10.0
var _first_b := true
var _first_a := true
var _first_r5 := true
var _crushing := false
var _cart: AnimatableBody3D
var _cart_bank: Bank
var _cart_x := 0.0
var _cart_z := 0.0
var _papers: Array = []
var _paper_i := 0
var _knock_from := Vector3.INF
var _knock_t := 0.0
var _still_t := 0.0
var _last_kp := Vector3.ZERO
var _sensors := true
var _spill_dirty := true
var _ae_snap := false
var _hum_cell: Cell
var _grid_static := PackedByteArray()
var _gw := 0
var _gh := 0
var _gx0 := -4.6
var _gy0 := -0.4


func _g(b: Vector2, z := 0.0) -> Vector3:
	return Vector3(b.x, LEVEL_Y + z, -b.y)


static func _c(r: float, g: float, b: float) -> Color:
	return Color(r, g, b).linear_to_srgb()


static func _v2(a: Array) -> Vector2:
	return Vector2(float(a[0]), float(a[1]))


## Local frame of a cell -> world (Godot).
func _world(c: Cell, x: float, z: float, y := 0.0) -> Vector3:
	var p := c.ax * x + c.az() * z
	return Vector3(p.x, LEVEL_Y + y, p.y)


func _local(c: Cell, p: Vector3) -> Vector2:
	var q := Vector2(p.x, p.z)
	return Vector2(q.dot(c.ax), q.dot(c.az()))


static func range_l(nsec: int) -> float:
	return nsec * SEC_W + 2 * END_T


# ----------------------------------------------------------------- build ---

func build(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed
	var c := Lucid.fixture_rgb(Lucid.FIXTURES.strip_t8_2lamp) * Lucid.wb_gains(4800.0)
	_light_rgb = c / maxf(Lucid.lum(c), 0.001)
	var cb := Lucid.kelvin_rgb(4000.0) * Lucid.wb_gains(4800.0)
	_bar_rgb = cb / maxf(Lucid.lum(cb), 0.001)
	_load_sounds()
	var D: Dictionary = LAYOUT.DATA
	for id in D.cells:
		_build_cell(id, D.cells[id])
	_build_banks(D)
	for d in D.doors:
		if d.kind == "door" or d.kind == "gated":
			var span := _door_span(d)
			var a: Cell = _cells[d.a]
			var b: Cell = _cells[d.b]
			a.portals.append({"to": b, "a": span[0], "b": span[1]})
			b.portals.append({"to": a, "a": span[0], "b": span[1]})
			for k in 2:
				var rc: Cell = a if k == 0 else b
				var sc: Cell = b if k == 0 else a
				var cc := _v2(d.c)
				var into := (rc.rect.get_center() - cc)
				into = Vector2(signf(into.x), 0) if d.axis == "y" else Vector2(0, signf(into.y))
				var pw := _g(cc - into * 0.6, 1.07)      # (a source just behind the opening)
				var nw := Vector3(into.x, 0, -into.y)
				var srcw := _g(cc - into * 0.9, 1.0)
				rc.spills.append({"from": sc, "p": Vector3(_local(rc, pw).x, 1.07, _local(rc, pw).y),
						"n": Vector3(_local(rc, nw + Vector3(0, LEVEL_Y, 0)).x, 0, _local(rc, nw + Vector3(0, LEVEL_Y, 0)).y),
						"src": srcw, "area": float(d.w) * 2.13})
	for cl in _cell_list:
		_build_signs(cl)
	_build_carts(D)
	_build_papers()
	_build_audio()
	for cl in _cell_list:
		_adopt(cl)
	_add_exit()
	_cur = _cells["R1"]
	environment = make_environment({"background": Color(0, 0, 0), "fog": Color(0, 0, 0), "fog_density": 0.006,
			"exposure": 1.0, "glow": 0.3, "saturation": 0.95, "contrast": 1.03})
	environment.adjustment_color_correction = null
	_base_exposure = environment.tonemap_exposure


## The opening's ends (Godot x, z).
func _door_span(d: Dictionary) -> Array:
	var cc := _v2(d.c)
	var h: float = float(d.w) * 0.5
	var a := cc - Vector2(h, 0) if d.axis == "x" else cc - Vector2(0, h)
	var b := cc + Vector2(h, 0) if d.axis == "x" else cc + Vector2(0, h)
	return [Vector2(a.x, -a.y), Vector2(b.x, -b.y)]


func _build_cell(id: String, d: Dictionary) -> void:
	var c := Cell.new()
	c.id = id
	c.name = d.name
	c.kind = d.kind
	var r: Array = d.rect
	c.rect = Rect2(r[0], r[1], r[2] - r[0], r[3] - r[1])
	c.ax = Vector2(float(d.ax[0]), -float(d.ax[1]))
	c.timeout = d.timeout
	c.dark = d.get("dark", false)
	c.root = Node3D.new()
	c.root.name = "cell_" + id
	add_child(c.root)
	_cells[id] = c
	_cell_list.append(c)
	var lm := DIR + "lightmaps/"
	var surfaces := {
		"concrete_floor": {"texture": "concrete_floor", "scale": 0.4, "roughness": 1.0, "specular": 0.5, "normal_depth": 0.5},
		"cmu_paint": {"texture": "cmu_paint", "scale": 1.0 / 1.2192, "roughness": 1.0, "specular": 0.3, "normal_depth": 0.8},
		"slab_paint": {"texture": "slab_paint", "scale": 1.3, "roughness": 1.0, "specular": 0.2, "normal_depth": 0.5},
		"exit_face": {"texture": "exit_face", "scale": Vector2(1.0 / 0.30, 1.0 / 0.115), "emit": EXIT_EMIT},
		"sorter_wood": {"texture": "sorter_wood", "scale": 1.0, "roughness": 0.6, "specular": 0.4, "normal_depth": 0.6},
		"paint": {"color": Color(1, 1, 1), "roughness": 0.6, "specular": 0.35, "emit": TUBE_EMIT},
	}
	var before := _kit_mats.size()
	var grp := lm + "filing_%s_groups.png" % id
	c.kit = load_kit(DIR + "filing_%s.glb" % id, lm + "filing_%s.png" % id, TEX, surfaces,
			grp if ResourceLoader.exists(grp) else "")
	c.kit.reparent(c.root)
	for i in range(before, _kit_mats.size()):
		if _kit_mats[i] is ShaderMaterial:
			c.mats.append(_kit_mats[i])
	for mi in c.kit.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			if src and _clean_name(src.resource_name) == "paint":
				(m.get_surface_override_material(s) as ShaderMaterial).set_shader_parameter("kit_vcol", true)
	c.shelf = flat_material({"color": Color(1, 1, 1), "roughness": 0.55, "specular": 0.35}, Color(0.5, 0.5, 0.5),
			Vector4.ZERO, TEX, "carton")
	c.shelf.set_shader_parameter("label_tex", load(TEX + "/labels_diff.png"))
	c.mats.append(c.shelf)
	# strip rows, in the cell's frame
	for row in LAYOUT.DATA.rows:
		if row.cell != id:
			continue
		var a := _v2(row.a)
		var b := _v2(row.b)
		var n: int = row.n
		var xs := PackedFloat32Array()
		for k in n:
			var p := a.lerp(b, (k + 0.5) / n)
			xs.append(Vector2(p.x, -p.y).dot(c.ax))
		var x0 := xs[0]
		var x1 := xs[0]
		for x in xs:
			x0 = minf(x0, x)
			x1 = maxf(x1, x)
		x0 -= 0.61
		x1 += 0.61
		var ag := Vector2(a.x, -a.y)
		c.rows.append({"lz": ag.dot(c.az()), "x0": x0, "x1": x1, "g": int(row.g),
				"i": n * STRIP_LM / (x1 - x0) / PI / (PI * UNIT)})
	var sens: Dictionary = LAYOUT.DATA.sensors.get(id, {})
	for g in sens:
		var list: Array[Rect2] = []
		for rr in sens[g]:
			list.append(Rect2(rr[0], rr[1], rr[2] - rr[0], rr[3] - rr[1]))
		c.sensors[int(g)] = list


## Every level shader material of a cell onto the Stacks' shader, with the
## cell's frame, rows, banks and light.
func _adopt(c: Cell) -> void:
	var sh: Shader = load(FILING_SHADER)
	var shc: Shader = load(FILING_SHADER_CUTOUT)
	var ra := PackedVector4Array()
	var rb := PackedVector4Array()
	for r in c.rows:
		ra.append(Vector4(r.lz, STRIP_Y, r.x0, r.x1))
		rb.append(Vector4(r.i, float(r.g), 0, 0))
	var i_bar := BAR_LM_M / PI / (PI * UNIT)
	for sm in c.mats:
		if sm.shader.resource_path == SHADER:
			sm.shader = sh
		elif sm.shader.resource_path == SHADER_CUTOUT:
			sm.shader = shc
		var lmode := 1 if sm == c.shelf or not bool(sm.get_shader_parameter("has_lightmap")) else 0
		sm.set_shader_parameter("origin", Vector3(0, LEVEL_Y, 0))
		sm.set_shader_parameter("frame_ax", c.ax)
		sm.set_shader_parameter("lmode", lmode)
		sm.set_shader_parameter("rows_a", ra)
		sm.set_shader_parameter("rows_b", rb)
		sm.set_shader_parameter("row_count", mini(ra.size(), 8))
		sm.set_shader_parameter("night_rgb", Vector3(_light_rgb.r, _light_rgb.g, _light_rgb.b))
		sm.set_shader_parameter("bar_rgb", Vector3(_bar_rgb.r, _bar_rgb.g, _bar_rgb.b) * i_bar)
		sm.set_shader_parameter("bar_emit", Vector3(_bar_rgb.r, _bar_rgb.g, _bar_rgb.b) * BAR_EMIT)
		sm.set_shader_parameter("car_half", CAR_W * 0.5)
		sm.set_shader_parameter("stack_h", STACK_H)
		sm.set_shader_parameter("nbank", c.banks.size())
		sm.set_shader_parameter("label_card", Vector2(64.0 / 1024.0, 42.0 / 1024.0))
		for k in c.banks.size():
			var bk: Bank = c.banks[k]
			sm.set_shader_parameter("bank%d" % k, Vector4(bk.xl, bk.xr, bk.z0, bk.z1))
			sm.set_shader_parameter("bank_n%d" % k, bk.n)
	c.shelf.set_shader_parameter("vcol", true)
	c.dirty = true
	c.lit_dirty = true
	_push_cell(c)


func _push_cell(c: Cell) -> void:
	if c.dirty:
		var cx := PackedFloat32Array()
		var bo := PackedFloat32Array()
		var fb := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		for k in c.banks.size():
			var bk: Bank = c.banks[k]
			cx.append_array(bk.cx)
			bo.append_array(bk.bars)
			fb[k * 2] = bk.fix_bars[0]
			fb[k * 2 + 1] = bk.fix_bars[1]
		cx.resize(32)
		bo.resize(32)
		for sm in c.mats:
			sm.set_shader_parameter("car_x", cx)
			sm.set_shader_parameter("bar_on", bo)
			sm.set_shader_parameter("fix_bar", fb)
		c.dirty = false
	if c.lit_dirty:
		var rl := PackedVector4Array()
		for g in 4:
			rl.append(Vector4(_light_rgb.r, _light_rgb.g, _light_rgb.b, c.grp_on[g]))
		for sm in c.mats:
			sm.set_shader_parameter("room_light", rl)
		c.lit_dirty = false


func _load_sounds() -> void:
	for f in DirAccess.get_files_at(AUD):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.ends_with(".ogg") and not _streams.has(n.get_basename()):
			_streams[n.get_basename()] = load(AUD + n)
	for i in 14:
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
	if st == null or sim:
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
	for c in _cell_list:
		var cl: Cell = c
		if cl.rows.is_empty():
			continue
		cl.hum = add_loop(_streams.get("hum_loop"), _world(cl, 0, 0, STRIP_Y), -80.0,
				{"unit_size": 2.5, "max_distance": 14.0, "pitch": _rng.randf_range(0.99, 1.01)}) as AudioStreamPlayer3D
		cl.hum.stop()
	for b in _banks:
		var bk: Bank = b
		bk.rumble = add_loop(_streams.get("rumble_loop"), Vector3(0, LEVEL_Y, 0), -80.0,
				{"unit_size": 5.0, "max_distance": 40.0}) as AudioStreamPlayer3D
		bk.drive = add_loop(_streams.get("drive_loop"), Vector3(0, LEVEL_Y, 0), -80.0,
				{"unit_size": 3.0, "max_distance": 30.0}) as AudioStreamPlayer3D
		bk.rumble.stop()
		bk.drive.stop()


# --------------------------------------------------------------- shelving ---

## Merged geometry with vertex colours (linear albedo times AO) and UVs into
## the carton atlas; everything untextured samples its white paper margin.
## UV2: x a carton's jitter hash, y the part (0 frame, 1 carton, 2 handle,
## 3 range card, 4 sign: see filing_lit.gdshaderinc).
class Geo:
	var st := SurfaceTool.new()
	var part := 0.0
	var off := Vector3.ZERO
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
		var pts := [a + off, b + off, c + off, d + off]
		for idx in [0, 2, 1, 0, 3, 2]:
			st.set_normal(n)
			st.set_color(cc)
			st.set_uv(uvs[idx])
			st.set_uv2(Vector2(tag, part))
			st.add_vertex(pts[idx])

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
## centred on x, z; the handle end at +z. `shut`: only what shows when both
## its sides are pressed against neighbours (the base, the end panels).
func _frame_geo(g: Geo, faces: Array, width: float, handle_end: bool, card: bool, L: float, nsec: int,
		shut := false) -> void:
	var inner := L - 2 * END_T
	g.part = 0.0
	# carriage base (the steel channel frame, wheels inside it)
	g.box(Vector3(0, 0.066, 0), Vector3(width, 0.112, L - 0.01),
			[_ao(TRIM, 0.6), SKIP, _ao(TRIM, 1.0), _ao(TRIM, 1.0), _ao(TRIM, 1.0), _ao(TRIM, 1.0)])
	if not shut:
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
			for j in nsec + 1:
				var z := -inner * 0.5 + j * SEC_W
				g.box(Vector3(fx - s * 0.016, (SHELF_Y0 + STACK_H) * 0.5, z), Vector3(0.032, STACK_H - SHELF_Y0, 0.035),
						[SKIP, SKIP, _ao(STEEL, 0.95), _ao(STEEL, 0.95), _ao(STEEL, 0.7), _ao(STEEL, 0.7)])
			# the aisle light bar on the canopy's edge: aluminium, diffuser under
			var bx: float = fx + s * 0.0175
			g.box(Vector3(bx, 2.262, 0), Vector3(0.035, 0.025, inner - 0.1),
					[_ao(Color(0.6, 0.6, 0.6), 1.0), Color(0.9, 0.9, 0.9, 0.0), _ao(Color(0.6, 0.6, 0.6), 0.9),
					_ao(Color(0.6, 0.6, 0.6), 0.9), _ao(Color(0.6, 0.6, 0.6), 0.7), _ao(Color(0.6, 0.6, 0.6), 0.7)])
		if faces.size() == 2:
			# the back stops between the two faces (seen past an empty shelf)
			g.box(Vector3(0, (SHELF_Y0 + STACK_H) * 0.5, 0), Vector3(0.006, STACK_H - SHELF_Y0, inner),
					[SKIP, SKIP, _ao(STEEL, 0.22), _ao(STEEL, 0.22), SKIP, SKIP])
		if faces.size() == 1:
			# a fixed unit's back panel
			var s0: float = -faces[0]
			g.box(Vector3(s0 * (width * 0.5 - 0.02), (SHELF_Y0 + STACK_H) * 0.5, 0), Vector3(0.04, STACK_H - SHELF_Y0, inner),
					[_ao(STEEL, 0.8), SKIP, _ao(STEEL, 0.5), _ao(STEEL, 0.5), SKIP, SKIP])
	else:
		# the canopy, seen from a doorway's height over the shut run
		g.box(Vector3(0, STACK_H - 0.0125, 0), Vector3(width, 0.025, inner), [_ao(STEEL, 1.0), SKIP, SKIP, SKIP, SKIP, SKIP])
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
	if handle_end and card:
		var zf := L * 0.5
		# the hub's bearing plate and the label holder (its card: part 3)
		g.box(Vector3(0, 1.06, zf + 0.004), Vector3(0.12, 0.12, 0.008), [TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
		g.box(Vector3(0, 1.62, zf + 0.003), Vector3(0.13, 0.09, 0.006), [TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
		g.part = 3.0
		var a := Vector3(-0.055, 1.62 - 0.036, zf + 0.0065)
		g.quad(a, a + Vector3(0.11, 0, 0), a + Vector3(0.11, 0.072, 0), a + Vector3(0, 0.072, 0), Color(1, 1, 1),
				Rect2(0, 0, 1, 1))
		g.part = 2.0
		g.off = Vector3(0, 1.06, zf)
		_handle_geo(g)
		g.off = Vector3.ZERO
		g.part = 0.0


## Cartons on a carriage's faces (or a fixed unit's), into g (part 1).
func _cartons_geo(g: Geo, faces: Array, width: float, rng: RandomNumberGenerator, L: float, nsec: int) -> void:
	g.part = 1.0
	var inner := L - 2 * END_T
	const CW := 12.5 * IN
	const CH := 10.25 * IN
	for s in faces:
		var fx: float = s * width * 0.5
		for j in nsec:
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
					var cf := Color(tint, tint, tint)
					var cols := [_ao(cf, 0.32), SKIP, SKIP, SKIP, _ao(cf, 0.45), _ao(cf, 0.45)]
					var uvs := {0: tu, 4: su, 5: su}
					var fi := 2 if s > 0 else 3
					cols[fi] = _ao(cf, 0.92)
					uvs[fi] = fu
					_box_tagged(g, ctr, size, cols, uvs, rng.randf(), s)
	g.part = 0.0


## A carton with its end's AO graded (darker under the shelf above) and a
## tag for its jitter.
func _box_tagged(g: Geo, ctr: Vector3, size: Vector3, cols: Array, uvs: Dictionary, tag: float, s: float) -> void:
	var hs := size * 0.5
	var fx := ctr.x + s * hs.x
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
		g.st.set_uv2(Vector2(tag, g.part))
		g.st.add_vertex([a, b, c, d][idx])


## The three-spoke handle (hub, spokes, knobs), local: axis along +z, into g
## (at g.off).
func _handle_geo(g: Geo) -> void:
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
		g.box(p1 + Vector3(0, 0, z + 0.04), Vector3(0.024, 0.024, 0.07), [knob, knob, knob, knob, knob, knob])


## The carriage meshes for a range length: six full ones (frame, cartons,
## handle, card), the shut one, the two fixed units'.
func _variants_for(nsec: int) -> Dictionary:
	if _variants.has(nsec):
		return _variants[nsec]
	var L := range_l(nsec)
	var crng := RandomNumberGenerator.new()
	crng.seed = 77 + nsec
	var full: Array[ArrayMesh] = []
	for v in 6:
		var g := Geo.new()
		_frame_geo(g, [1.0, -1.0], CAR_W, true, true, L, nsec)
		_cartons_geo(g, [1.0, -1.0], CAR_W, crng, L, nsec)
		full.append(g.commit())
	var gs := Geo.new()
	_frame_geo(gs, [1.0, -1.0], CAR_W, true, true, L, nsec, true)
	var fixed := []
	for face in [1.0, -1.0]:
		var gf := Geo.new()
		_frame_geo(gf, [face], FIX_W, true, false, L, nsec)
		_cartons_geo(gf, [face], FIX_W, crng, L, nsec)
		fixed.append(gf.commit())
	var d := {"full": full, "shut": gs.commit(), "fixed": fixed}
	_variants[nsec] = d
	return d


func _build_banks(D: Dictionary) -> void:
	var card := 0
	for bd in D.banks:
		var bk := Bank.new()
		var c: Cell = _cells[bd.cell]
		bk.cell = c
		bk.bi = c.banks.size()
		bk.gi = _banks.size()
		bk.name = bd.name
		bk.label = bd.label
		bk.n = bd.n
		bk.nsec = bd.nsec
		bk.L = range_l(bk.nsec)
		bk.rear = bd.rear
		bk.card0 = card
		card += bk.n
		c.banks.append(bk)
		_banks.append(bk)
		var o := _v2(bd.o)
		var og := Vector2(o.x, -o.y)
		var evb := _v2(bd.ev)
		var evg := Vector2(evb.x, -evb.y)
		var lx0 := og.dot(c.ax)
		bk.xl = lx0 + FIX_W
		bk.xr = lx0 + 2 * FIX_W + bk.n * CAR_W + (bd.aisles as Array).size() * AISLE - FIX_W
		var oz := og.dot(c.az())
		var sv := evg.dot(c.az())
		bk.hz = oz + sv * bk.L
		bk.fz = oz
		bk.z0 = minf(bk.hz, bk.fz)
		bk.z1 = maxf(bk.hz, bk.fz)
		bk.yaw = atan2(evg.x, evg.y)
		bk.sx = signf(Vector2(cos(bk.yaw), -sin(bk.yaw)).dot(c.ax))
		for d in D.doors:
			if d.kind == "gated" and d.b == c.id:
				var span := _door_span(d)
				var a: float = (span[0] as Vector2).dot(c.ax)
				var b: float = (span[1] as Vector2).dot(c.ax)
				bk.gated.append([minf(a, b), maxf(a, b)])
		bk.nopen = (bd.aisles as Array).size()
		var open := _random_open(bk)
		bk.cx.resize(bk.n)
		bk.hang.resize(bk.n)
		bk.bars.resize(bk.n)
		bk.bar_t.resize(bk.n)
		bk.full.resize(bk.n)
		bk.full.fill(2)
		bk.variant.resize(bk.n)
		var vs := _variants_for(bk.nsec)
		var zc := (bk.z0 + bk.z1) * 0.5
		for i in bk.n:
			# (moved by hand in _physics_process: no sync to the physics frame)
			var body := AnimatableBody3D.new()
			body.sync_to_physics = false
			bk.cx[i] = _home(bk, i, open)
			add_child(body)
			body.global_position = _world(c, bk.cx[i], zc)
			body.rotation.y = bk.yaw
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(CAR_W, STACK_H, bk.L)
			cs.shape = bs
			cs.position = Vector3(0, STACK_H * 0.5, 0)
			body.add_child(cs)
			var mi := MeshInstance3D.new()
			mi.material_override = c.shelf
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			body.add_child(mi)
			bk.variant[i] = _rng.randi() % 6
			bk.hang[i] = _rng.randf() * TAU
			mi.mesh = vs.shut
			mi.set_instance_shader_parameter("inst_card", float(bk.card0 + i))
			mi.set_instance_shader_parameter("inst_hang", bk.hang[i])
			mi.set_instance_shader_parameter("inst_bar", 0.0)
			bk.bodies.append(body)
			bk.meshes.append(mi)
		for i in bk.n:
			_update_variant(bk, i)
		# the fixed single-faced units at the ends
		for side in 2:
			var fb := StaticBody3D.new()
			c.root.add_child(fb)
			var fxc := bk.xl - FIX_W * 0.5 if side == 0 else bk.xr + FIX_W * 0.5
			fb.global_position = _world(c, fxc, zc)
			fb.rotation.y = bk.yaw
			var cs2 := CollisionShape3D.new()
			var bs2 := BoxShape3D.new()
			bs2.size = Vector3(FIX_W, STACK_H, bk.L)
			cs2.shape = bs2
			cs2.position = Vector3(0, STACK_H * 0.5, 0)
			fb.add_child(cs2)
			var face := bk.sx if side == 0 else -bk.sx
			var fm := MeshInstance3D.new()
			fm.mesh = vs.fixed[0 if face > 0 else 1]
			fm.material_override = c.shelf
			fm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			fm.set_instance_shader_parameter("inst_bar", 0.0)
			fb.add_child(fm)
			bk.fixed.append(fm)
			c.objs.append([fm, _rect_g(c, fxc, zc, FIX_W, bk.L)])


## Where a bank's aisles start (spread out; a new layout each seed).
func _random_open(bk: Bank) -> Array:
	if bk.cell.id == "R1":
		return [_rng.randi_range(3, 9)]
	var open := []
	var k := bk.nopen
	for j in k:
		var lo := int(float(bk.n + 1) * j / k) + (1 if j > 0 else 0)
		var hi := int(float(bk.n + 1) * (j + 1) / k) - 1
		open.append(_rng.randi_range(lo, maxi(lo, hi)))
	return open


## Tests: the floor as if just built with seed s (shelving, cart, first-time
## events, the log).
func sim_reset(s: int) -> void:
	_rng.seed = s
	_t = 0.0
	_next_event = 3.0
	_first_b = true
	_first_a = true
	events_log.clear()
	sim_crushes = 0
	for b in _banks:
		var bk: Bank = b
		bk.state = 0
		bk.inside_t = 0.0
		bk.trigger_t = 0.0
		bk.log_i = -1
		var open := _random_open(bk)
		for i in bk.n:
			_set_car(bk, i, _home(bk, i, open))
		for i in bk.n:
			_update_variant(bk, i)
	if _cart_bank:
		var a: int = open_gaps(_cart_bank)[0]
		_cart_x = (_gap(_cart_bank, a).x + _gap(_cart_bank, a).y) * 0.5
		_cart.global_position = _world(_cart_bank.cell, _cart_x, _cart_z)


## A carriage's home: carriages pressed together, `open` the open gaps.
func _home(bk: Bank, i: int, open: Array) -> float:
	var x := bk.xl + CAR_W * (i + 0.5)
	for a in open:
		if int(a) <= i:
			x += AISLE
	return x


## The rect (Godot x, z) of a box centred at local (x, z), w across, l along.
func _rect_g(c: Cell, x: float, z: float, w: float, l: float) -> Rect2:
	var p := Vector2(x, z)
	var r := Rect2()
	var first := true
	for k in 4:
		var q := p + Vector2((w if k % 2 == 0 else -w) * 0.5, (l if k < 2 else -l) * 0.5)
		var gq := c.ax * q.x + c.az() * q.y
		if first:
			r = Rect2(gq, Vector2.ZERO)
			first = false
		else:
			r = r.expand(gq)
	return r


## Gap g of bank bk: (left face, right face) in local x.
func _gap(bk: Bank, g: int) -> Vector2:
	var a := bk.xl if g == 0 else bk.cx[g - 1] + CAR_W * 0.5
	var b := bk.xr if g == bk.n else bk.cx[g] - CAR_W * 0.5
	return Vector2(a, b)


func open_gaps(bk: Bank) -> Array:
	var out := []
	for g in bk.n + 1:
		var w := _gap(bk, g)
		if w.y - w.x > 0.3:
			out.append(g)
	return out


## The gap local x is in (-1: inside a carriage).
func _gap_index(bk: Bank, x: float) -> int:
	for g in bk.n + 1:
		var w := _gap(bk, g)
		if x >= w.x - 0.002 and x <= w.y + 0.002:
			return g
	return -1


## The faces either side of local x in bank bk: (xl, xr), and the
## carriages (index, or -1 for a fixed unit) in z, w.
func _gap_at(bk: Bank, x: float) -> Vector4:
	var g := Vector4(bk.xl, bk.xr, -1, -1)
	for i in bk.n:
		var c := bk.cx[i]
		var rf := c + CAR_W * 0.5
		var lf := c - CAR_W * 0.5
		if rf <= x + 0.002 and rf > g.x:
			g.x = rf
			g.z = i
		if lf >= x - 0.002 and lf < g.y:
			g.y = lf
			g.w = i
	return g


## Full mesh when either side of carriage i is open, the shut one otherwise.
func _update_variant(bk: Bank, i: int) -> void:
	if i < 0 or i >= bk.n:
		return
	var open := _gap(bk, i).y - _gap(bk, i).x > 0.02 or _gap(bk, i + 1).y - _gap(bk, i + 1).x > 0.02
	var want := 1 if open else 0
	if bk.full[i] == want and (bk.meshes[i] as MeshInstance3D).mesh != null:
		return
	bk.full[i] = want
	var vs := _variants_for(bk.nsec)
	(bk.meshes[i] as MeshInstance3D).mesh = vs.full[bk.variant[i]] if open else vs.shut


func _set_car(bk: Bank, i: int, x: float) -> void:
	bk.cx[i] = x
	var body: Node3D = bk.bodies[i]
	body.global_position = _world(bk.cell, x, (bk.z0 + bk.z1) * 0.5)
	bk.cell.dirty = true


# ------------------------------------------------------------ signs, props ---

## The cell's signs (door signs, range signs, floor plans with their "you are
## here" dot, arrows) as one mesh in the labels atlas; cartons on the
## sorting tables.
func _build_signs(c: Cell) -> void:
	var g := Geo.new()
	g.part = 4.0
	var at: Dictionary = LAYOUT.DATA.atlas
	var pw: Array = LAYOUT.DATA.plan_world
	var pp: Array = LAYOUT.DATA.plan_px
	var any := false
	for s in LAYOUT.DATA.signs:
		if s.cell != c.id:
			continue
		var img: String = s.img
		var key := img
		if img.begins_with("plan:"):
			key = "plan_old" if img == "plan:old" else "plan"
		if not at.has(key):
			continue
		var r: Array = at[key]
		var uv := Rect2(r[0] / 1024.0, r[1] / 1024.0, r[2] / 1024.0, r[3] / 1024.0)
		var ctr := Vector3(s.c[0], s.c[2], -s.c[1])
		var nrm := Vector3(s.n[0], 0, -s.n[1])
		var right := Vector3.UP.cross(nrm)
		var w: float = s.size[0]
		var h: float = s.size[1]
		var a := ctr - right * w * 0.5 - Vector3.UP * h * 0.5
		g.quad(a, a + right * w, a + right * w + Vector3.UP * h, a + Vector3.UP * h, Color(1, 1, 1), uv)
		# a thin frame behind it
		g.part = 0.0
		var fc := ctr - nrm * 0.004
		g.box(fc, Vector3(absf(right.x) * (w + 0.02) + absf(nrm.x) * 0.006, h + 0.02,
				absf(right.z) * (w + 0.02) + absf(nrm.z) * 0.006), [TRIM, TRIM, TRIM, TRIM, TRIM, TRIM])
		g.part = 4.0
		if img.begins_with("plan:"):
			# you are here: the sign's own place on the plan
			var sc := minf(float(pp[2]) / (float(pw[2]) - float(pw[0])), float(pp[3]) / (float(pw[3]) - float(pw[1])))
			var px: float = float(pp[0]) + (float(s.c[0]) - float(pw[0])) * sc
			var py: float = float(pp[1]) + float(pp[3]) - (float(s.c[1]) - float(pw[1])) * sc
			var off := right * (px / 512.0 - 0.5) * w + Vector3.UP * (0.5 - py / 366.0) * h + nrm * 0.002
			var dr: Array = at["dot"]
			var duv := Rect2(dr[0] / 1024.0, dr[1] / 1024.0, dr[2] / 1024.0, dr[3] / 1024.0)
			var ds := 0.022
			var da := ctr + off - right * ds * 0.5 - Vector3.UP * ds * 0.5
			g.quad(da, da + right * ds, da + right * ds + Vector3.UP * ds, da + Vector3.UP * ds, Color(1, 1, 1), duv)
		any = true
	if c.id == "R2":
		# a few cartons and a stack of files on the sorting tables
		g.part = 0.0
		var tu := Rect2(Vector2(0.5, 0.5), Vector2(0.25, 0.25))
		var fu := Rect2(Vector2(0.0, 0.0), Vector2(0.25, 0.208))
		var su := Rect2(Vector2(0.0, 0.5), Vector2(0.25, 0.25))
		var pu := Rect2(Vector2(0.0, 0.75), Vector2(0.25, 0.25))
		var wc := Color(1, 1, 1)
		for b in [[14.6, 11.55, 0.1], [15.05, 11.7, -0.06], [15.75, 13.5, 0.3], [14.4, 13.7, 0.0]]:
			var p := Vector3(b[0], 0.76 + 0.13, -b[1])
			g.box(p, Vector3(0.38, 0.26, 0.31), [_ao(wc, 0.9), SKIP, _ao(wc, 0.7), _ao(wc, 0.7), _ao(wc, 0.8),
					_ao(wc, 0.8)], {0: tu, 2: fu, 3: fu, 4: su, 5: su})
		g.box(Vector3(15.5, 0.76 + 0.02, -11.5), Vector3(0.24, 0.04, 0.3), [_ao(wc, 1.0), SKIP, _ao(wc, 0.8),
				_ao(wc, 0.8), _ao(wc, 0.8), _ao(wc, 0.8)], {0: pu})
		any = true
	if not any:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = g.commit()
	mi.material_override = c.shelf
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	c.root.add_child(mi)
	mi.position = Vector3(0, LEVEL_Y, 0)


func _cart_mesh() -> ArrayMesh:
	var g := Geo.new()
	var steel := Color(0.30, 0.31, 0.32)
	var dark := Color(0.03, 0.03, 0.03)
	var sx := CART_SIZE.x
	var sz := CART_SIZE.z
	for y in [0.20, 0.52, 0.84]:
		g.box(Vector3(0, y, 0), Vector3(sx, 0.025, sz), [_ao(steel, 1.0), _ao(steel, 0.4), steel, steel, steel, steel])
		g.box(Vector3(0, y + 0.03, 0), Vector3(sx + 0.004, 0.035, 0.012), [steel, steel, steel, steel, steel, steel])
	for px in [-1.0, 1.0]:
		for pz in [-1.0, 1.0]:
			g.box(Vector3(px * (sx * 0.5 - 0.012), 0.55, pz * (sz * 0.5 - 0.012)), Vector3(0.024, 0.9, 0.024),
					[steel, steel, steel, steel, steel, steel])
			g.box(Vector3(px * (sx * 0.5 - 0.03), 0.05, pz * (sz * 0.5 - 0.05)), Vector3(0.03, 0.1, 0.1),
					[dark, dark, dark, dark, dark, dark])
	g.box(Vector3(0, 1.0, sz * 0.5 - 0.01), Vector3(sx, 0.025, 0.025), [steel, steel, steel, steel, steel, steel])
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
	return g.commit()


func _build_carts(D: Dictionary) -> void:
	var mesh := _cart_mesh()
	for cd in D.carts:
		var c: Cell = _cells[cd.cell]
		var body: PhysicsBody3D
		if cd.has("bank"):
			_cart = AnimatableBody3D.new()
			_cart.sync_to_physics = false
			body = _cart
		else:
			body = StaticBody3D.new()
		add_child(body)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = c.shelf
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		body.add_child(mi)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = CART_SIZE
		cs.shape = bs
		cs.position = Vector3(0, CART_SIZE.y * 0.5, 0)
		body.add_child(cs)
		if cd.has("bank"):
			_cart_bank = c.banks[int(cd.bank)]
			var bk := _cart_bank
			var a: int = open_gaps(bk)[0]
			_cart_x = (_gap(bk, a).x + _gap(bk, a).y) * 0.5
			_cart_z = bk.hz + signf(bk.fz - bk.hz) * 2.9
			_cart.global_position = _world(c, _cart_x, _cart_z)
			_cart.rotation.y = 0.03
		else:
			body.global_position = _g(_v2(cd.c))
			body.rotation.y = float(cd.yaw)
			c.objs.append([mi, Rect2(Vector2(cd.c[0], -cd.c[1]) - Vector2(0.5, 0.5), Vector2(1, 1))])


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
		var n := MeshInstance3D.new()
		n.mesh = g.commit()
		n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(n)
		n.visible = false
		_papers.append({"node": n, "state": 0, "t": 0.0, "bank": null})


func _add_exit() -> void:
	# The exit door in Bay 4's north wall: you stand on its south side.
	# LevelEntrance's own door (frame, leaf, the dark behind it); the ride
	# ends just inside the room, on the floor.
	var r5: Cell = _cells["R5"]
	var was := r5.grp_on.duplicate()
	for g in 4:
		r5.grp_on[g] = 1.0
	add_exit(Transform3D(Basis(), _g(_v2(LAYOUT.DATA.exit))), "door", "", {"label": "Open the exit door"})
	r5.grp_on = was
	# STAIR 2, at the far (north) end of corridor B: the service stair, down
	# into the stairwell (Level 4.1), arriving on its top landing, B2. Its
	# sign is the Stacks' own (the door signs in the labels atlas).
	var c3: Cell = _cells["C3"]
	was = c3.grp_on.duplicate()
	for g in 4:
		c3.grp_on[g] = 1.0
	var st := add_exit(Transform3D(Basis(), _g(_v2(LAYOUT.DATA.stair))), "door", "stairwell",
			{"label": "Take the stairs down"})
	c3.grp_on = was
	# (lit as the baked doors round it are: the framework door's self-light
	# from light_at alone leaves it black under the corridor's strips)
	for m in st._mats.values():
		var sm := m as StandardMaterial3D
		if sm and sm.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED:
			sm.emission = sm.albedo_color * 0.55


# --------------------------------------------------------------- the game ---

func on_enter() -> void:
	var cs := get_tree().current_scene
	_events = cs == null or not String(cs.scene_file_path).contains("level_shots")
	if _events:
		# Bay 1's main aisle sensor sees you come in.
		_switch_on(_cells["R1"], 0, 1.0)


func arrival() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), _g(_v2(LAYOUT.DATA.arrival)))   # facing east down the main aisle


func surface_at(_p: Vector3) -> int:
	return Player.SURF_CONCRETE


func camera_far() -> float:
	return 26.0 if low else 34.0


## Concrete and block, but every shelf is full of cardboard: short, damped.
func reverb() -> Dictionary:
	if _cur and _cur.kind == "corridor":
		return {"room": 0.6, "damp": 0.5, "wet": 0.25}
	return {"room": 0.5, "damp": 0.7, "wet": 0.2}


func light_at(p: Vector3) -> Color:
	var e := _light_level(p)
	return Color(_light_rgb.r * e, _light_rgb.g * e, _light_rgb.b * e)


func cell_at(bp: Vector2) -> Cell:
	var best: Cell = null
	var bd := INF
	for c in _cell_list:
		var cl: Cell = c
		var r := cl.rect
		var dx := maxf(maxf(r.position.x - bp.x, bp.x - r.end.x), 0.0)
		var dy := maxf(maxf(r.position.y - bp.y, bp.y - r.end.y), 0.0)
		var d := dx * dx + dy * dy
		if d < bd:
			bd = d
			best = cl
	return best


## Horizontal light (engine units) at p from the rows as they are now and
## the aisle bars, with the shelving's shade where p is in a slot (the
## exposure, figures and the radar).
func _light_level(p: Vector3) -> float:
	var c := cell_at(Vector2(p.x, -p.z))
	if c == null:
		return 0.002
	var q := _local(c, p)
	var y := p.y - LEVEL_Y
	var e := 0.0
	for r in c.rows:
		var g: int = r.g
		var lvl := 1.0 if g < 0 else c.grp_on[g]
		if lvl <= 0.001:
			continue
		var dy := STRIP_Y - y
		if dy < 0.05:
			continue
		var dz: float = r.lz - q.y
		var rr := sqrt(dy * dy + dz * dz)
		var f := _f2(r.x1 - q.x, rr) - _f2(r.x0 - q.x, rr)
		e += float(r.i) * dy * dy * f * lvl
	for b in c.banks:
		var bk: Bank = b
		if q.y > bk.z0 and q.y < bk.z1 and y < STACK_H:
			var gap := _gap_at(bk, q.x)
			var w := maxf(gap.y - gap.x, 0.0)
			e *= clampf(w / (w + 1.1 * (STACK_H - y)) * 1.6, 0.05, 1.0)
			var bl := _bars_of(bk, gap)
			e += (bl.x + bl.y) * 0.25
	return e * 1.3 + 0.002


static func _f2(s: float, r: float) -> float:
	var r2 := r * r
	return s / (2.0 * r2 * (s * s + r2)) + atan(s / r) / (2.0 * r2 * r)


func _bars_of(bk: Bank, gap: Vector4) -> Vector2:
	var l := bk.fix_bars[0] if gap.z < 0 else bk.bars[int(gap.z)]
	var r := bk.fix_bars[1] if gap.w < 0 else bk.bars[int(gap.w)]
	return Vector2(l, r)


func albedo_at(_p: Vector3, n: Vector3) -> Color:
	if n.y > 0.7:
		return Color(0.30, 0.295, 0.28)
	if n.y < -0.7:
		return Color(0.72, 0.72, 0.70)
	return Color(0.38, 0.30, 0.20)


func save_state() -> Dictionary:
	var banks := []
	for b in _banks:
		var bk: Bank = b
		var og := open_gaps(bk)
		if bk.state == 1 or bk.state == 2:
			og.erase(bk.close_gap)
			if not og.has(bk.open_gap):
				og.append(bk.open_gap)
			og.sort()
		banks.append(og)
	var lights := {}
	for c in _cell_list:
		var cl: Cell = c
		lights[cl.id] = [cl.grp_want[0], cl.grp_want[1], cl.grp_want[2], cl.grp_want[3]]
	return {"banks": banks, "first_b": _first_b, "first_a": _first_a, "cart_x": _cart_x, "lights": lights}


func load_state(d: Dictionary) -> void:
	_first_b = bool(d.get("first_b", true))
	_first_a = bool(d.get("first_a", true))
	var banks: Array = d.get("banks", [])
	for k in mini(banks.size(), _banks.size()):
		var bk: Bank = _banks[k]
		var og: Array = banks[k]
		if og.is_empty():
			continue
		bk.state = 0
		for i in bk.n:
			_set_car(bk, i, _home(bk, i, og))
		for i in bk.n:
			_update_variant(bk, i)
	if _cart_bank:
		_cart_x = float(d.get("cart_x", _cart_x))
		_cart.global_position = _world(_cart_bank.cell, _cart_x, _cart_z)
	var lights: Dictionary = d.get("lights", {})
	for id in lights:
		if not _cells.has(id):
			continue
		var c: Cell = _cells[id]
		var l: Array = lights[id]
		for g in mini(l.size(), 4):
			c.grp_on[g] = float(l[g])
			c.grp_want[g] = c.grp_on[g]
			c.grp_seen[g] = 0.0
		c.lit_dirty = true


# ----------------------------------------------------------------- lights ---

## The occupancy sensor for group g of cell c sees motion: relay, ~1.1 s of
## cathode preheat, the lamps strike.
func _switch_on(c: Cell, g: int, delay := 0.0) -> void:
	c.grp_seen[g] = _t + delay
	if c.grp_want[g] > 0.5:
		return
	c.grp_want[g] = 1.0
	var at := _t + delay
	c.seq.append([at, g, -1.0, "relay"])
	c.seq.append([at + 0.02, g, 0.004, "ballast_start"])
	c.seq.append([at + 1.12, g, 0.6, ""])
	c.seq.append([at + 1.2, g, 1.0, ""])
	if _rng.randf() < 0.5:
		var t := at + 1.3
		for i in _rng.randi_range(2, 4):
			c.seq.append([t, g, 0.55, ""])
			t += _rng.randf_range(0.04, 0.09)
			c.seq.append([t, g, 1.0, ""])
			t += _rng.randf_range(0.08, 0.3)
	c.seq.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])


## The sensor timed out: the relay drops, the lamps go out.
func _switch_off(c: Cell, g: int) -> void:
	c.grp_want[g] = 0.0
	var keep: Array = []
	for e in c.seq:
		if int(e[1]) != g:
			keep.append(e)
	c.seq = keep
	c.seq.append([_t, g, 0.0, "relay"])


func _row_pos(c: Cell, g: int) -> Vector3:
	var pl := _local(c, _ppos)
	for r in c.rows:
		if r.g == g:
			return _world(c, clampf(pl.x, r.x0, r.x1), r.lz, STRIP_Y)
	return _ppos


func _update_lights() -> void:
	for cc in _cell_list:
		var c: Cell = cc
		while not c.seq.is_empty() and c.seq[0][0] <= _t:
			var e: Array = c.seq.pop_front()
			var g: int = e[1]
			if e[2] >= 0.0:
				c.grp_on[g] = e[2]
				c.lit_dirty = true
			match e[3]:
				"relay":
					_play_at(_streams.get("relay"), _row_pos(c, g), -14.0, _rng.randf_range(0.95, 1.05), 3000.0)
				"ballast_start":
					_play_at(_streams.get("ballast_start"), _row_pos(c, g), -10.0, _rng.randf_range(0.97, 1.03))
		# time-outs
		for g in 4:
			if c.grp_want[g] > 0.5 and _t - c.grp_seen[g] > c.timeout:
				_switch_off(c, g)
		# the aisle bars time out too
		for b in c.banks:
			var bk: Bank = b
			if bk.state != 0:
				continue
			for i in bk.n:
				if bk.bars[i] > 0.5 and _t - bk.bar_t[i] > BAR_TIMEOUT:
					bk.bars[i] = 0.0
					(bk.meshes[i] as MeshInstance3D).set_instance_shader_parameter("inst_bar", 0.0)
					c.dirty = true
			for s in 2:
				if bk.fix_bars[s] > 0.5 and _t - bk.fix_t[s] > BAR_TIMEOUT:
					bk.fix_bars[s] = 0.0
					(bk.fixed[s] as MeshInstance3D).set_instance_shader_parameter("inst_bar", 0.0)
					c.dirty = true
		if c.lit_dirty:
			_spill_dirty = true
		if c.dirty or c.lit_dirty:
			_push_cell(c)
	if _spill_dirty:
		_push_spills()
	_update_hum()


## The light through every doorway: the luminance of the room beyond near
## the opening (its horizontal light times a mean albedo of 0.4), over the
## opening's area.
func _push_spills() -> void:
	_spill_dirty = false
	for cc in _cell_list:
		var c: Cell = cc
		var sp := PackedVector4Array()
		var sn := PackedVector4Array()
		for s in c.spills:
			var l := _light_level(s.src) * 0.4
			var p: Vector3 = s.p
			var n: Vector3 = s.n
			sp.append(Vector4(p.x, p.y, p.z, l * float(s.area) / PI))
			sn.append(Vector4(n.x, n.y, n.z, 0.0))
		sp.resize(8)
		sn.resize(8)
		for sm in c.mats:
			sm.set_shader_parameter("spill_p", sp)
			sm.set_shader_parameter("spill_n", sn)
			sm.set_shader_parameter("spill_count", mini(c.spills.size(), 8))


## One ballast hum, from the nearest lit strip of the room you're in.
func _update_hum() -> void:
	if sim or _cur == null:
		return
	if _hum_cell != _cur:
		if _hum_cell and _hum_cell.hum:
			_hum_cell.hum.stop()
		_hum_cell = _cur
	var c := _cur
	if c.hum == null:
		return
	var pl := _local(c, _ppos)
	var best := INF
	var at := Vector3.ZERO
	var lvl := 0.0
	for r in c.rows:
		var o := 1.0 if r.g < 0 else c.grp_on[r.g]
		if o < 0.01:
			continue
		var x := clampf(pl.x, r.x0, r.x1)
		var d := Vector2(x - pl.x, float(r.lz) - pl.y).length()
		if d < best:
			best = d
			at = _world(c, x, r.lz, STRIP_Y)
			lvl = o
	if lvl <= 0.01:
		c.hum.stop()
		return
	if not c.hum.playing:
		c.hum.play()
	c.hum.global_position = at
	c.hum.volume_db = linear_to_db(lvl) - 20.0


## Bank bk's bars either side of a gap (its faces) on or off.
func _set_bar(bk: Bank, gap: Vector4, on: float) -> void:
	var changed := false
	for side in 2:
		var k := int(gap.z) if side == 0 else int(gap.w)
		if k < 0:
			var fs := 0 if side == 0 else 1
			if bk.fix_bars[fs] != on:
				changed = true
				bk.fix_bars[fs] = on
				(bk.fixed[fs] as MeshInstance3D).set_instance_shader_parameter("inst_bar", on)
			bk.fix_t[fs] = _t
		else:
			if bk.bars[k] != on:
				changed = true
				bk.bars[k] = on
				(bk.meshes[k] as MeshInstance3D).set_instance_shader_parameter("inst_bar", on)
			bk.bar_t[k] = _t
	if changed:
		bk.cell.dirty = true


func _bar_any(bk: Bank, gap: Vector4) -> float:
	if gap.z < -1.5:
		return 0.0
	var v := _bars_of(bk, gap)
	return maxf(v.x, v.y)


func _gap_vec(bk: Bank, g: int) -> Vector4:
	var w := _gap(bk, g)
	return Vector4(w.x, w.y, g - 1, g if g < bk.n else -1)


# ------------------------------------------------------------ bank motion ---

## The closed gaps a bank can open by closing gap c: the run of carriages
## pressed together either side of it, up to the next open gap.
func _targets(bk: Bank, c: int) -> Array:
	var og := open_gaps(bk)
	var out := []
	var g := c - 1
	while g >= 0 and not og.has(g):
		out.append(g)
		g -= 1
	g = c + 1
	while g <= bk.n and not og.has(g):
		out.append(g)
		g += 1
	return out


## Can you get out of gap g at the far end (a rear aisle, or a fire door
## that lines up with it)?
func _far_open(bk: Bank, g: int) -> bool:
	if bk.rear == "aisle":
		return true
	var w := _gap(bk, g)
	for r in bk.gated:
		if minf(w.y, r[1]) - maxf(w.x, r[0]) > 0.7:
			return true
	return false


## How long a close of gap c must warn for: the furthest anyone in it can be
## from an open end, at a walk, after reacting, minus the time until the gap
## is narrower than a person.
func _warn_for(bk: Bank, c: int, dist: float) -> float:
	var reach := bk.L * 0.5 if _far_open(bk, c) else bk.L
	var w0 := _gap(bk, c).y - _gap(bk, c).x
	var tm := _time_to_close(minf(w0, dist), w0 - CRUSH_GAP)
	return maxf(WARN_MIN, reach / WALK + REACT + SAFETY - tm)


## Time from rest until the carriages have closed `d` (accelerating to VMAX
## over ACCEL_T); INF if they stop short of it (limit).
static func _time_to_close(limit: float, d: float) -> float:
	if d > limit:
		return INF
	var a := VMAX / ACCEL_T
	var d_acc := 0.5 * a * ACCEL_T * ACCEL_T
	if d <= d_acc:
		return sqrt(2.0 * d / a)
	return ACCEL_T + (d - d_acc) / VMAX


## Starts bank bk closing gap c and opening gap o (the carriages between roll
## together). `limit`: how far they can go (the cart).
func _start_move(bk: Bank, c: int, o: int, limit := INF) -> void:
	if c == o or bk.state != 0:
		return
	var w := _gap(bk, c).y - _gap(bk, c).x
	if o < c:
		bk.grp = Vector2i(o, c - 1)
		bk.gdir = 1.0
	else:
		bk.grp = Vector2i(c, o - 1)
		bk.gdir = -1.0
	bk.close_gap = c
	bk.open_gap = o
	bk.gdist = minf(w, limit)
	bk.gmoved = 0.0
	bk.gv = 0.0
	bk.gfrom = bk.cx.duplicate()
	bk.state = 1
	bk.st = 0.0
	bk.warn = _warn_for(bk, c, bk.gdist)
	bk.warn_lit = _bar_any(bk, _gap_vec(bk, c)) > 0.01
	events_log.append({"b": bk.gi, "c": c, "o": o, "t0": _t, "warn": bk.warn, "w": w, "far": _far_open(bk, c)})
	bk.log_i = events_log.size() - 1
	var mid := _world(bk.cell, (_gap(bk, c).x + _gap(bk, c).y) * 0.5, (bk.z0 + bk.z1) * 0.5, 1.2)
	_play_at(_pick("creak_"), mid, -6.0, _rng.randf_range(0.92, 1.05))
	# the room's sensors see the motion
	if bk.cell == _cur and not bk.cell.dark:
		for g in bk.cell.sensors:
			for r in bk.cell.sensors[g]:
				var bc := Vector2(mid.x, -mid.z)
				if (r as Rect2).grow(1.0).has_point(bc):
					_switch_on(bk.cell, g)


func _group_x(bk: Bank) -> float:
	return (bk.cx[bk.grp.x] + bk.cx[bk.grp.y]) * 0.5


func _update_bank(bk: Bank, delta: float) -> void:
	var s := bk.state
	if s == 0:
		return
	bk.st += delta
	var g := bk.grp
	var gx := _group_x(bk)
	var mid := _world(bk.cell, gx, (bk.z0 + bk.z1) * 0.5, 0.3)
	var near := _ppos.distance_to(mid)
	match s:
		1:
			# Warning: the aisle bar flickers and goes out, the cartons
			# shiver, the handles twitch.
			var gap := _gap_vec(bk, bk.close_gap)
			var k: float = bk.st
			if bk.warn_lit:
				if k < bk.warn - 0.2:
					_set_bar(bk, gap, 1.0 if (k < 0.15 or fmod(k * 13.0, 1.0) > 0.35) else 0.12)
				else:
					_set_bar(bk, gap, 0.0)
					bk.warn_lit = false
					_play_at(_streams.get("led_click"), mid + Vector3(0, 2.0, 0), -10.0)
			var amt := minf(k / bk.warn, 1.0)
			if not sim:
				for i in range(g.x, g.y + 1):
					var tw := sin(_t * 20.0 + i) * 0.12 * amt
					var mi := bk.meshes[i] as MeshInstance3D
					mi.set_instance_shader_parameter("inst_hang", bk.hang[i] + tw)
					mi.set_instance_shader_parameter("inst_shake", amt * 0.6)
			if k >= bk.warn:
				bk.state = 2
				bk.st = 0.0
				if bk.log_i >= 0:
					events_log[bk.log_i]["tm"] = _t
				_play_at(_pick("carton_"), mid + Vector3(0, 1.4, 0), -8.0)
				if not sim:
					bk.rumble.play()
					bk.drive.play()
		2, 4:
			var back := s == 4
			var vmax := VMAX if not back else VMAX * 0.6
			bk.gv = minf(bk.gv + vmax / ACCEL_T * delta, vmax)
			var step: float = bk.gv * delta
			var left: float = bk.gdist - bk.gmoved
			var done := step >= left
			step = minf(step, left)
			bk.gmoved += step
			var dx: float = step * bk.gdir * (-1.0 if back else 1.0)
			for i in range(g.x, g.y + 1):
				_set_car(bk, i, bk.cx[i] + dx)
				bk.hang[i] += dx / PER_TURN * TAU * bk.sx
				if not sim:
					var mi := bk.meshes[i] as MeshInstance3D
					mi.set_instance_shader_parameter("inst_hang", bk.hang[i])
					mi.set_instance_shader_parameter("inst_shake", 0.35 + 0.4 * bk.gv / VMAX)
			for i in range(g.x - 1, g.y + 2):
				_update_variant(bk, i)
			if bk == _cart_bank and not back:
				_push_cart(bk, dx)
			if not back and bk.log_i >= 0 and not events_log[bk.log_i].has("tc"):
				var w := _gap(bk, bk.close_gap)
				if w.y - w.x < CRUSH_GAP:
					events_log[bk.log_i]["tc"] = _t
			if not sim:
				var sp: float = bk.gv / VMAX
				bk.rumble.global_position = mid
				bk.rumble.volume_db = linear_to_db(maxf(sp, 0.0001)) - 4.0
				bk.rumble.pitch_scale = 0.7 + 0.3 * sp
				bk.drive.global_position = _world(bk.cell, gx, bk.hz, 1.0)
				bk.drive.volume_db = linear_to_db(maxf(sp, 0.0001)) - 8.0
				bk.drive.pitch_scale = 0.6 + 0.4 * sp
				rumble = 0.006 * sp * clampf(1.0 - near / 9.0, 0.0, 1.0)
			if done:
				_stop_bank(bk, back)
		3:
			# Stopped against the cart: a moment, then back the way they came.
			if bk.st > 2.2:
				bk.state = 4
				bk.st = 0.0
				bk.gmoved = 0.0
				bk.gdist = absf(bk.cx[g.x] - bk.gfrom[g.x])
				bk.gv = 0.0
				if not sim:
					bk.rumble.play()
					bk.drive.play()


func _stop_bank(bk: Bank, was_back: bool) -> void:
	var g := bk.grp
	var mid := _world(bk.cell, _group_x(bk), (bk.z0 + bk.z1) * 0.5, 0.5)
	if not sim:
		bk.rumble.stop()
		bk.drive.stop()
		rumble = 0.0
		for i in range(g.x, g.y + 1):
			(bk.meshes[i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", 0.0)
	if was_back:
		bk.state = 0
		_play_at(_pick("carton_"), mid + Vector3(0, 1.2, 0), -12.0)
		return
	_play_at(_pick("clunk_"), mid, -1.0, _rng.randf_range(0.95, 1.05))
	var near := _ppos.distance_to(mid)
	if not sim:
		if near < 14.0:
			shake(clampf(0.03 - near * 0.002, 0.004, 0.03), 0.5)
		_jolt_cartons(bk, 0.5)
	if bk == _cart_bank and bk.gdist < _gap_width_was(bk) - 0.01:
		_play_at(_pick("cart_"), _world(bk.cell, _cart_x, _cart_z, 0.6), -4.0)
		_drop_papers(bk, bk.close_gap, 2)
		bk.state = 3
		bk.st = 0.0
		return
	bk.state = 0
	if bk.cell == _cur:
		_drop_papers(bk, bk.open_gap, 1 + _rng.randi() % 2)


func _gap_width_was(bk: Bank) -> float:
	if bk.log_i >= 0:
		return float(events_log[bk.log_i]["w"])
	return AISLE


func _jolt_cartons(bk: Bank, amt: float) -> void:
	var g := bk.grp
	for i in range(g.x, g.y + 1):
		(bk.meshes[i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", amt)
	get_tree().create_timer(0.25).timeout.connect(func() -> void:
		for i in range(g.x, g.y + 1):
			if is_instance_valid(bk.meshes[i]):
				(bk.meshes[i] as MeshInstance3D).set_instance_shader_parameter("inst_shake", 0.0))


## The cart in Bay 1 bank A's aisle shoved along by the closing face.
func _push_cart(bk: Bank, _dx: float) -> void:
	var g := bk.grp
	if bk.gdir > 0:
		var face := bk.cx[g.y] + CAR_W * 0.5
		var need := face - (_cart_x - CART_SIZE.x * 0.5)
		if need > 0.0 and _cart_x > face - 0.5:
			_cart_x += need
	else:
		var face2 := bk.cx[g.x] - CAR_W * 0.5
		var need2 := (_cart_x + CART_SIZE.x * 0.5) - face2
		if need2 > 0.0 and _cart_x < face2 + 0.5:
			_cart_x -= need2
	_cart.global_position = _world(bk.cell, _cart_x, _cart_z)


## How far bank bk can close gap c before the cart stops it.
func _cart_limit(bk: Bank, c: int) -> float:
	var w := _gap(bk, c)
	if bk != _cart_bank or _cart_x < w.x or _cart_x > w.y:
		return INF
	return (w.y - w.x) - CART_SIZE.x - 0.004


func _drop_papers(bk: Bank, gi: int, n: int) -> void:
	if sim:
		return
	var w := _gap(bk, gi)
	if w.y - w.x < 0.3:
		var m := (w.x + w.y) * 0.5
		w = Vector2(m - 0.45, m + 0.45)
	for k in n:
		var p: Dictionary = _papers[_paper_i]
		_paper_i = (_paper_i + 1) % _papers.size()
		var side := 1.0 if _rng.randf() < 0.5 else -1.0
		var x0: float = w.x if side > 0 else w.y
		var lev := _rng.randi_range(2, NLEV - 1)
		var y0 := SHELF_Y0 + lev * SHELF_P - 0.035 + 0.005
		var zz := _rng.randf_range(bk.z0 + 0.6, bk.z1 - 0.6)
		p.state = 1
		p.t = -k * 0.35
		p.bank = bk
		p.from = Vector2(x0 - side * 0.12, zz)
		p.y0 = y0
		p.dir = side
		p.yaw = _rng.randf_range(-0.5, 0.5)
		p.f = _rng.randf_range(1.2, 1.9)
		var n3: MeshInstance3D = p.node
		n3.material_override = bk.cell.shelf
		n3.visible = false


func _update_papers(delta: float) -> void:
	for p in _papers:
		var n: MeshInstance3D = p.node
		if p.state == 0:
			continue
		var bk: Bank = p.bank
		var c := bk.cell
		if p.state == 1:
			p.t += delta
			var t: float = p.t
			if t < 0.0:
				continue
			var from: Vector2 = p.from
			var side: float = p.dir
			var y0: float = p.y0
			if not n.visible:
				n.visible = true
				_play_at(_pick("paper_"), _world(c, from.x, from.y, y0), -12.0, _rng.randf_range(0.9, 1.1))
			var bas := Basis(Vector3.UP, atan2(c.ax.y, c.ax.x) * -1.0)
			if t < 0.35:
				var k := t / 0.35
				n.global_position = _world(c, from.x + side * 0.16 * k * k, from.y, y0)
				n.basis = bas * Basis.from_euler(Vector3(0, p.yaw, -side * 0.6 * k * k))
			else:
				var tf := t - 0.35
				var y := y0 - 0.8 * tf
				var sway := sin(tf * TAU * float(p.f)) * 0.12 * minf(tf * 2.0, 1.0)
				var x := from.x + side * (0.16 + 0.35 * (1.0 - exp(-tf * 1.5))) + sway * 0.6
				if y <= 0.002:
					y = 0.002
					p.state = 2
					n.basis = bas * Basis.from_euler(Vector3(0, p.yaw + tf, 0))
				else:
					n.basis = bas * Basis.from_euler(Vector3(sin(tf * 5.0) * 0.5, p.yaw + tf * 0.8,
							-side * 0.6 + cos(tf * TAU * float(p.f)) * 0.6))
				n.global_position = _world(c, x, from.y + sin(tf * 3.1) * 0.05, y)
		elif p.state == 2:
			# under a carriage now? out of sight.
			var x := _local(c, n.global_position).x
			for i in bk.n:
				if absf(x - bk.cx[i]) < CAR_W * 0.5 - 0.1:
					n.visible = false
					p.state = 0
					break


# --------------------------------------------------------------- events ---

## Where you are in a bank: depth from its nearer end, or -1 if not in it.
func _depth_in(bk: Bank, q: Vector2) -> float:
	if q.y <= bk.z0 or q.y >= bk.z1 or q.x < bk.xl - FIX_W or q.x > bk.xr + FIX_W:
		return -1.0
	return minf(q.y - bk.z0, bk.z1 - q.y)


func _update_events(delta: float) -> void:
	var p := _ppos
	var bp := Vector2(p.x, -p.z)
	var c := cell_at(bp)
	_cur = c
	# Lights: the sensors see you.
	if _sensors:
		for g in c.sensors:
			for r in c.sensors[g]:
				if (r as Rect2).has_point(bp):
					_switch_on(c, g)
	var q := _local(c, p)
	# Aisle bars: on when you're in the aisle or at its mouth.
	for b in c.banks:
		var bk: Bank = b
		if bk.state != 0:
			continue
		var gap := _gap_at(bk, q.x)
		if gap.y - gap.x < 0.5 or q.x < bk.xl or q.x > bk.xr:
			continue
		var at_mouth := absf(q.y - bk.hz) < 1.0 or (_far_open(bk, _gap_index(bk, q.x)) and absf(q.y - bk.fz) < 1.0)
		var inside := q.y > bk.z0 and q.y < bk.z1
		if at_mouth or inside:
			if _bar_any(bk, gap) < 0.5:
				_play_at(_streams.get("led_click"), Vector3(p.x, LEVEL_Y + 2.2, p.z), -14.0)
			_set_bar(bk, gap, 1.0)
	if not _events:
		return
	# Standing in an aisle: it shuts on you, after a while.
	for b in c.banks:
		var bk: Bank = b
		var depth := _depth_in(bk, q)
		var gi := _gap_index(bk, q.x)
		var open := gi >= 0 and _gap(bk, gi).y - _gap(bk, gi).x > 0.5
		var first := bk.cell.id == "R1" and bk.name == "B" and _first_b
		if depth > 1.0 and open and bk.state == 0:
			bk.inside_t += delta
			if bk.trigger_t <= 0.0:
				bk.trigger_t = 0.9 if first else _rng.randf_range(2.6, 6.0)
			if (depth > 2.0 or not first) and bk.inside_t > bk.trigger_t:
				bk.trigger_t = 0.0
				bk.inside_t = 0.0
				var ts := _targets(bk, gi)
				if ts.is_empty():
					continue
				var o: int = ts[_rng.randi() % ts.size()]
				if first:
					_first_b = false
					o = bk.n if ts.has(bk.n) else ts.max()   # the east carriages: the new aisle by the door
				_start_move(bk, gi, o, _cart_limit(bk, gi))
		elif depth < 0.0 or not open:
			bk.inside_t = 0.0
	# Bay 1 bank A shoves at its cart the first time you pass its aisle.
	if _first_a and _cart_bank and c == _cart_bank.cell and _t > 4.0:
		var bk := _cart_bank
		if absf(q.x - _cart_x) < 2.2 and absf(q.y - bk.hz) < 1.6 and _depth_in(bk, q) < 0.0 and bk.state == 0:
			_first_a = false
			var ci := _gap_index(bk, _cart_x)
			get_tree().create_timer(1.6).timeout.connect(func() -> void:
				var ts := _targets(bk, ci)
				if bk.state == 0 and not ts.is_empty():
					_start_move(bk, ci, ts[_rng.randi() % ts.size()], _cart_limit(bk, ci)))
	_update_scheduler(delta, c, q)
	if c.id == "R5":
		_update_knocks(delta, c, q)


## Now and then a range moves on its own somewhere on the floor, more often
## near you; never one you're standing in (that only shuts with its warning
## when you dawdle), never more than MAX_MOVING at once.
func _update_scheduler(delta: float, c: Cell, q: Vector2) -> void:
	_next_event -= delta
	if _next_event > 0.0:
		return
	_next_event = _rng.randf_range(6.0, 13.0)
	var moving := 0
	for b in _banks:
		if (b as Bank).state != 0:
			moving += 1
	if moving >= MAX_MOVING:
		_next_event = 2.0
		return
	var near := {}
	near[c] = 4.0
	for pt in c.portals:
		near[pt.to] = 2.0
	var cand: Array = []
	var total := 0.0
	for b in _banks:
		var bk: Bank = b
		if bk.state != 0:
			continue
		if bk.cell == c and _depth_in(bk, q) >= 0.0:
			continue
		if bk.cell.id == "R1" and _first_b:
			continue
		var w: float = near.get(bk.cell, 1.0)
		if bk == _cart_bank:
			w *= 0.3
		cand.append([bk, w])
		total += w
	if cand.is_empty():
		return
	var r := _rng.randf() * total
	var pick: Bank = cand[0][0]
	for e in cand:
		r -= float(e[1])
		if r <= 0.0:
			pick = e[0]
			break
	var og := open_gaps(pick)
	var cg: int = og[_rng.randi() % og.size()]
	var ts := _targets(pick, cg)
	if ts.is_empty():
		return
	var o: int = ts[_rng.randi() % ts.size()]
	# now and then line an aisle up with a fire door
	if not pick.gated.is_empty() and _rng.randf() < 0.45:
		for t in ts:
			if _would_align(pick, cg, t):
				o = t
				break
	_start_move(pick, cg, o, _cart_limit(pick, cg))


## Would opening gap o (closing c) put an aisle in front of a fire door?
func _would_align(bk: Bank, c: int, o: int) -> bool:
	var w := _gap(bk, c).y - _gap(bk, c).x
	var a: float
	var b: float
	if o < c:
		a = bk.xl if o == 0 else bk.cx[o - 1] + CAR_W * 0.5
		b = a + w
	else:
		b = bk.xr if o == bk.n else bk.cx[o] - CAR_W * 0.5
		a = b - w
	for r in bk.gated:
		if minf(b, r[1]) - maxf(a, r[0]) > 0.7:
			return true
	return false


## Bay 4: knocking from inside the shut shelving beside you, a step ahead of
## you as you walk the main aisle; stop, and it knocks once more right by you,
## then waits.
func _update_knocks(delta: float, c: Cell, q: Vector2) -> void:
	if sim or c.banks.is_empty():
		return
	var bk: Bank = c.banks[0]
	if _depth_in(bk, q) >= 0.0 or absf(q.y - bk.hz) > 2.6:
		_knock_from = Vector3.INF
		return
	if _first_r5:
		_first_r5 = false
		_knock_t = 4.0
		_knock_from = _ppos
		return
	if _knock_from == Vector3.INF:
		_knock_from = _ppos
	_knock_t -= delta
	var step := Vector2(_ppos.x - _last_kp.x, _ppos.z - _last_kp.z).length()
	_last_kp = _ppos
	_still_t = 0.0 if step > 0.3 * delta else _still_t + delta
	if _knock_t > 0.0:
		return
	var moved := Vector2(_ppos.x - _knock_from.x, _ppos.z - _knock_from.z)
	var walked := moved.length()
	var ahead := 0.0
	if walked > 1.4:
		ahead = signf(moved.dot(c.ax)) * 0.6
	elif _still_t < 3.5:
		return
	# into the nearest shut carriage at that x, a metre and a half in
	var x := q.x + ahead
	var best := -1
	for i in bk.n:
		var gl := _gap(bk, i).y - _gap(bk, i).x
		var gr := _gap(bk, i + 1).y - _gap(bk, i + 1).x
		if gl < 0.05 and gr < 0.05 and (best < 0 or absf(bk.cx[i] - x) < absf(bk.cx[best] - x)):
			best = i
	if best < 0:
		return
	var z := bk.hz + signf(bk.fz - bk.hz) * 1.5
	_play_at(_pick("knock_"), _world(c, bk.cx[best], z, _rng.randf_range(0.6, 1.5)), -9.0 if walked > 1.4 else -5.0,
			_rng.randf_range(0.93, 1.05), 2500.0)
	_knock_from = _ppos
	_knock_t = _rng.randf_range(1.7, 3.2) if walked > 1.4 else 9.0
	_still_t = 0.0


## Caught between two faces (or a face and the cart).
func _check_crush() -> void:
	if _crushing:
		return
	var p := _ppos
	var c := cell_at(Vector2(p.x, -p.z))
	var q := _local(c, p)
	for b in c.banks:
		var bk: Bank = b
		if bk.state != 2:
			continue
		if q.y < bk.z0 + 0.05 or q.y > bk.z1 - 0.05:
			continue
		var gap := _gap_at(bk, q.x)
		var w := gap.y - gap.x
		if bk == _cart_bank and absf(q.y - _cart_z) < CART_SIZE.z * 0.5 + 0.3 and _cart_x > gap.x and _cart_x < gap.y:
			w -= CART_SIZE.x
		var inside_car := false
		for i in bk.n:
			if absf(q.x - bk.cx[i]) < CAR_W * 0.5 - 0.05:
				inside_car = true
		if w < CRUSH_GAP or inside_car:
			_crush(bk)
			return


func _crush(bk: Bank) -> void:
	if sim:
		sim_crushes += 1
		_crushing = true
		return
	_crushing = true
	player.controls_enabled = false
	_play_at(_streams.get("crush"), player.global_position + Vector3(0, 1.0, 0), 2.0, 1.0)
	shake(0.06, 1.0)
	rumble = 0.02
	get_tree().create_timer(0.75).timeout.connect(func() -> void:
		bk.state = 3
		bk.st = -1000.0
		bk.rumble.stop()
		bk.drive.stop()
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
	if _ae_snap:
		_ae = target
		_ae_snap = false
	environment.tonemap_exposure = _base_exposure * _ae


# ------------------------------------------------------------- visibility ---

## Only the room you're in and what you can see of the others through their
## doorways (a 2D portal pass, the view clipped by each opening), and in
## those only the shelving inside the view through the opening.
func _update_visibility() -> void:
	var cam := player.camera.global_position
	var cp := Vector2(cam.x, cam.z)
	var f3 := -player.camera.global_basis.z
	var fwd := Vector2(f3.x, f3.z)
	if fwd.length() < 0.05:
		fwd = Vector2(-sin(player.yaw), -cos(player.yaw))
	fwd = fwd.normalized()
	var cur := cell_at(Vector2(cam.x, -cam.z))
	var vp := get_viewport().get_visible_rect().size
	var aspect := vp.x / maxf(vp.y, 1.0)
	var fov := deg_to_rad(player.camera.fov)
	var half := fov * 0.5 if player.camera.keep_aspect == Camera3D.KEEP_WIDTH else atan(tan(fov * 0.5) * aspect)
	half = minf(half + deg_to_rad(14.0), PI)
	var vis := {cur: [[-PI, PI]]}
	var queue := [[cur, -half, half, 0, null]]
	while not queue.is_empty():
		var e: Array = queue.pop_front()
		var cl: Cell = e[0]
		for pt in cl.portals:
			var to: Cell = pt.to
			if to == e[4]:
				continue
			var a: Vector2 = pt.a
			var b: Vector2 = pt.b
			var lo: float
			var hi: float
			if _seg_dist(cp, a, b) < 0.7:
				lo = -half
				hi = half
			else:
				var aa := fwd.angle_to(a - cp)
				var ab := fwd.angle_to(b - cp)
				if absf(aa - ab) > PI:
					continue
				lo = maxf(minf(aa, ab), e[1])
				hi = minf(maxf(aa, ab), e[2])
				if hi <= lo:
					continue
			if not vis.has(to):
				vis[to] = []
			(vis[to] as Array).append([lo, hi])
			if int(e[3]) < 3:
				queue.append([to, lo, hi, int(e[3]) + 1, cl])
	for cc in _cell_list:
		var c: Cell = cc
		var shown := 0 if not vis.has(c) else (2 if c == cur else 1)
		if shown != c.shown:
			c.root.visible = shown > 0
		c.shown = shown
		for o in c.objs:
			(o[0] as Node3D).visible = shown == 2 or (shown == 1 and _in_view(cp, fwd, o[1], vis[c]))
		for b in c.banks:
			var bk: Bank = b
			var zc := (bk.z0 + bk.z1) * 0.5
			for i in bk.n:
				var mi := bk.meshes[i] as MeshInstance3D
				mi.visible = shown == 2 or (shown == 1 and _in_view(cp, fwd, _rect_g(c, bk.cx[i], zc, CAR_W, bk.L),
						vis[c]))


static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


static func _in_view(cp: Vector2, fwd: Vector2, r: Rect2, spans: Array) -> bool:
	if r.grow(0.3).has_point(cp):
		return true
	var lo := INF
	var hi := -INF
	for k in 4:
		var q := Vector2(r.position.x if k % 2 == 0 else r.end.x, r.position.y if k < 2 else r.end.y)
		var a := fwd.angle_to(q - cp)
		lo = minf(lo, a)
		hi = maxf(hi, a)
	if hi - lo > PI:
		return true
	for s in spans:
		if hi >= float(s[0]) and lo <= float(s[1]):
			return true
	return false


func _process(delta: float) -> void:
	if player == null:
		return
	if not sim:
		_ppos = player.global_position
		_t += delta
		_update_events(delta)
		_update_lights()
		_update_papers(delta)
		_update_exposure(delta)
		_update_visibility()


func _physics_process(delta: float) -> void:
	if player == null or sim:
		return
	for b in _banks:
		_update_bank(b, delta)
	_check_crush()


## Tests: one step of the floor's logic with you standing at `at` (no
## physics, no sound, crushes counted in sim_crushes).
func sim_step(at: Vector3, dt: float) -> void:
	sim = true
	_ppos = at
	_t += dt
	_update_events(dt)
	for b in _banks:
		_update_bank(b, dt)
	_crushing = false
	_check_crush()
	for c in _cell_list:
		var cl: Cell = c
		cl.seq.clear()


# ------------------------------------------------------------ walk grid ---
# A grid over the floor (GRID m cells, Blender x, y): 1 where a person
# (PLAYER_R) can stand. The tests flood-fill it per shelving state; the film
# and the exit test walk along it.

func grid_size() -> Vector2i:
	if _gw == 0:
		var x1 := _gx0
		var y1 := _gy0
		for c in _cell_list:
			x1 = maxf(x1, (c as Cell).rect.end.x + 0.4)
			y1 = maxf(y1, (c as Cell).rect.end.y + 0.4)
		_gw = int(ceil((x1 - _gx0) / GRID))
		_gh = int(ceil((y1 - _gy0) / GRID))
	return Vector2i(_gw, _gh)


func grid_pos(i: int) -> Vector2:
	return Vector2(_gx0 + (i % _gw + 0.5) * GRID, _gy0 + (i / _gw + 0.5) * GRID)


func grid_index(bp: Vector2) -> int:
	grid_size()
	var x := int(floor((bp.x - _gx0) / GRID))
	var y := int(floor((bp.y - _gy0) / GRID))
	if x < 0 or y < 0 or x >= _gw or y >= _gh:
		return -1
	return y * _gw + x


func _grid_fill(m: PackedByteArray, r: Rect2, v: int) -> void:
	var x0 := maxi(int(ceil((r.position.x - _gx0) / GRID - 0.5)), 0)
	var x1 := mini(int(floor((r.end.x - _gx0) / GRID - 0.5)), _gw - 1)
	var y0 := maxi(int(ceil((r.position.y - _gy0) / GRID - 0.5)), 0)
	var y1 := mini(int(floor((r.end.y - _gy0) / GRID - 0.5)), _gh - 1)
	for y in range(y0, y1 + 1):
		var row := y * _gw
		for x in range(x0, x1 + 1):
			m[row + x] = v


## Blender rect of a box at a bank's local (x, z), w across, l along.
func _rect_b(c: Cell, x: float, z: float, w: float, l: float) -> Rect2:
	var r := _rect_g(c, x, z, w, l)
	return Rect2(r.position.x, -r.end.y, r.size.x, r.size.y)


## Where a person can stand with the shelving as it is now (1 free).
func grid_free() -> PackedByteArray:
	grid_size()
	if _grid_static.is_empty():
		var m := PackedByteArray()
		m.resize(_gw * _gh)
		m.fill(0)
		for c in _cell_list:
			_grid_fill(m, (c as Cell).rect.grow(-PLAYER_R), 1)
		for d in LAYOUT.DATA.doors:
			if d.kind != "door" and d.kind != "gated":
				continue
			var cc := _v2(d.c)
			var h: float = float(d.w) * 0.5 - PLAYER_R
			var r := Rect2(cc.x - h, cc.y - 0.5, 2 * h, 1.0) if d.axis == "x" else Rect2(cc.x - 0.5, cc.y - h, 1.0, 2 * h)
			_grid_fill(m, r, 1)
			if d.has("leaf_rect"):
				var lr: Array = d.leaf_rect
				_grid_fill(m, Rect2(lr[0], lr[1], lr[2] - lr[0], lr[3] - lr[1]).grow(PLAYER_R), 0)
		for pr in LAYOUT.DATA.props:
			var pc := _v2(pr.c)
			var ps := _v2(pr.size)
			_grid_fill(m, Rect2(pc - ps * 0.5, ps).grow(PLAYER_R), 0)
		for cd in LAYOUT.DATA.carts:
			if cd.has("c"):
				var big := maxf(CART_SIZE.x, CART_SIZE.z)
				_grid_fill(m, Rect2(_v2(cd.c) - Vector2(big, big) * 0.5, Vector2(big, big)).grow(PLAYER_R), 0)
		for b in _banks:
			var bk: Bank = b
			var zc := (bk.z0 + bk.z1) * 0.5
			for side in 2:
				var fxc := bk.xl - FIX_W * 0.5 if side == 0 else bk.xr + FIX_W * 0.5
				_grid_fill(m, _rect_b(bk.cell, fxc, zc, FIX_W, bk.L).grow(PLAYER_R), 0)
		_grid_static = m
	var f := _grid_static.duplicate()
	for b in _banks:
		var bk: Bank = b
		var zc := (bk.z0 + bk.z1) * 0.5
		for i in bk.n:
			_grid_fill(f, _rect_b(bk.cell, bk.cx[i], zc, CAR_W, bk.L).grow(PLAYER_R), 0)
	if _cart_bank:
		_grid_fill(f, _rect_b(_cart_bank.cell, _cart_x, _cart_z, CART_SIZE.x, CART_SIZE.z).grow(PLAYER_R), 0)
	return f


## Steps (4-neighbour, GRID m each) from every free cell to the nearest of
## `from` (-1: can't get there).
func grid_bfs(free: PackedByteArray, from: PackedInt32Array) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(free.size())
	dist.fill(-1)
	var q := PackedInt32Array()
	q.resize(free.size())
	var head := 0
	var tail := 0
	for s in from:
		if s >= 0 and free[s] == 1 and dist[s] < 0:
			dist[s] = 0
			q[tail] = s
			tail += 1
	var w := _gw
	var n := free.size()
	while head < tail:
		var i := q[head]
		head += 1
		var d := dist[i] + 1
		var x := i % w
		if x > 0 and free[i - 1] == 1 and dist[i - 1] < 0:
			dist[i - 1] = d
			q[tail] = i - 1
			tail += 1
		if x < w - 1 and free[i + 1] == 1 and dist[i + 1] < 0:
			dist[i + 1] = d
			q[tail] = i + 1
			tail += 1
		if i >= w and free[i - w] == 1 and dist[i - w] < 0:
			dist[i - w] = d
			q[tail] = i - w
			tail += 1
		if i + w < n and free[i + w] == 1 and dist[i + w] < 0:
			dist[i + w] = d
			q[tail] = i + w
			tail += 1
	return dist


## The free cells in front of the exit door.
func grid_exit(free: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	var e := _v2(LAYOUT.DATA.exit)
	for dx in range(-3, 4):
		for dy in range(1, 5):
			var i := grid_index(e + Vector2(dx * GRID, -dy * GRID))
			if i >= 0 and free[i] == 1:
				out.append(i)
	return out


## The free cells in front of STAIR 2's door (the way down to the stairwell).
func grid_stair(free: PackedByteArray) -> PackedInt32Array:
	var out := PackedInt32Array()
	var e := _v2(LAYOUT.DATA.stair)
	for dx in range(-2, 3):
		for dy in range(1, 5):
			var i := grid_index(e + Vector2(dx * GRID, -dy * GRID))
			if i >= 0 and free[i] == 1:
				out.append(i)
	return out


## Every bank (for tests).
func banks() -> Array:
	return _banks


func bank_info(bk: Bank) -> Dictionary:
	return {"cell": bk.cell.id, "name": bk.name, "n": bk.n, "L": bk.L, "state": bk.state, "close": bk.close_gap,
			"xl": bk.xl, "xr": bk.xr, "z0": bk.z0, "z1": bk.z1, "hz": bk.hz, "far": bk.rear}


## The Blender rect a bank's ranges cover (for tests).
func bank_rect(bk: Bank) -> Rect2:
	return _rect_b(bk.cell, (bk.xl + bk.xr) * 0.5, (bk.z0 + bk.z1) * 0.5, bk.xr - bk.xl, bk.L)


# --------------------------------------------------------------- harness ---

## yaw 0 faces north (-Z), 90 west, 180 south, -90 east.
func _view(at: Vector2, yaw_deg: float, pitch := 0.0) -> Transform3D:
	var bas := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(bas, _g(at))


## Every light in the cells on (or off).
func _lights(on: float, only: Array = []) -> void:
	_sensors = false
	_ae_snap = true
	for cc in _cell_list:
		var c: Cell = cc
		c.seq.clear()
		for g in 4:
			var o := on if only.is_empty() or only.has(c.id) else 0.0
			c.grp_on[g] = o
			c.grp_want[g] = o
			c.grp_seen[g] = _t + 1e6 if o > 0.5 else -1e9
		c.lit_dirty = true
		_push_cell(c)
	_push_spills()


func _lights_on() -> void:
	_lights(1.0)


## Bank of a cell with its open gaps at `open`; optionally the gaps right of
## the first one `close` m narrower (harness).
func _set_open(cid: String, bi: int, open: Array, close := 0.0) -> void:
	var bk: Bank = _cells[cid].banks[bi]
	bk.state = 0
	for i in bk.n:
		_set_car(bk, i, _home(bk, i, open))
	if close > 0.0:
		for i in range(int(open[0]), bk.n):
			if i < bk.n and (open.size() < 2 or i < int(open[1])):
				_set_car(bk, i, bk.cx[i] - close)
	for i in bk.n:
		_update_variant(bk, i)
		bk.bars[i] = 0.0
		(bk.meshes[i] as MeshInstance3D).set_instance_shader_parameter("inst_bar", 0.0)
	_push_cell(bk.cell)


## The middle of gap g (Blender) of a bank whose open gaps will be `open`,
## `depth` m in from its handle end.
func _gap_planned(cid: String, bi: int, open: Array, g: int, depth: float) -> Vector2:
	var c: Cell = _cells[cid]
	var bk: Bank = c.banks[bi]
	var a := bk.xl if g == 0 else _home(bk, g - 1, open) + CAR_W * 0.5
	var p := _world(c, a + AISLE * 0.5, bk.hz + signf(bk.fz - bk.hz) * depth)
	return Vector2(p.x, -p.z)


## The middle of a bank's gap g (Blender), `depth` m in from its handle end.
func _gap_in(cid: String, bi: int, g: int, depth: float) -> Vector2:
	var bk: Bank = _cells[cid].banks[bi]
	return _gap_point(cid, bi, g, bk.hz + signf(bk.fz - bk.hz) * depth)


## The middle of bank bk's gap g (Blender), at local z.
func _gap_point(cid: String, bi: int, g: int, z: float) -> Vector2:
	var c: Cell = _cells[cid]
	var bk: Bank = c.banks[bi]
	var w := _gap(bk, g)
	var p := _world(c, (w.x + w.y) * 0.5, z)
	return Vector2(p.x, -p.z)


func _bar_gap(cid: String, bi: int, g: int) -> void:
	var bk: Bank = _cells[cid].banks[bi]
	_set_bar(bk, _gap_vec(bk, g), 1.0)
	bk.bar_t.fill(_t + 1e6)
	bk.fix_t.fill(_t + 1e6)
	_push_cell(bk.cell)


func shots() -> Array:
	if OS.get_environment("SWEEP") != "":
		return _sweep_shots(float(OS.get_environment("SWEEP")))
	var D: Dictionary = LAYOUT.DATA
	var ar := _v2(D.arrival)
	var r1b: Bank = _cells["R1"].banks[1]
	var ab: int = open_gaps(r1b)[0]
	var mb := _gap_in("R1", 1, ab, 0.6)
	var r5: Bank = _cells["R5"].banks[0]
	return [
		{"name": "arrival_dark", "transform": _view(ar, -90.0, -0.06), "wait": 2.5, "call": func() -> void: _lights(0.0)},
		{"name": "arrival", "transform": _view(ar, -90.0, -0.06), "wait": 2.5, "call": func() -> void: _lights(1.0)},
		{"name": "aisle_b", "transform": _view(mb, 0.0, -0.04), "call": func() -> void:
			_lights_on()
			_bar_gap("R1", 1, ab)},
		{"name": "closing", "transform": _view(_gap_in("R1", 1, ab, 2.4) + Vector2(-0.12, 0), 0.0, 0.02),
			"call": func() -> void:
				_lights_on()
				_set_open("R1", 1, [ab], 0.3)},
		{"name": "corridor_a", "transform": _view(Vector2(9.6, 17.98), -90.0, -0.03), "call": func() -> void:
			_set_open("R1", 1, [ab])
			_lights_on()},
		{"name": "fire_door", "transform": _view(Vector2(18.55, 17.6), 0.0, -0.05), "call": func() -> void:
			_lights_on()
			_set_open("R5", 0, [3, 14])},
		{"name": "fire_door_open", "transform": _view(Vector2(18.55, 17.6), 0.0, -0.05), "call": func() -> void:
			_lights_on()
			_set_open("R5", 0, [6, 14])
			_bar_gap("R5", 0, 6)},
		{"name": "sorting", "transform": _view(Vector2(15.4, 16.2), 168.0, -0.12), "call": _lights_on},
		{"name": "plan", "transform": _view(Vector2(8.6, 17.55), 0.0, -0.12), "call": _lights_on},
		{"name": "bay3", "transform": _view(Vector2(R3X0 + 0.9, 8.43), -90.0, -0.04), "call": _lights_on},
		{"name": "bay3_aisle", "transform": _view(_gap_in("R3", 1, open_gaps(_cells["R3"].banks[1])[1], 0.5), 0.0, -0.03),
			"call": func() -> void:
				_lights_on()
				_bar_gap("R3", 1, open_gaps(_cells["R3"].banks[1])[1])},
		{"name": "bay2_aisle", "transform": _view(_gap_in("R4", 0, open_gaps(_cells["R4"].banks[0])[0], -0.5), -90.0, -0.03),
				"call": func() -> void:
					_lights_on()
					_bar_gap("R4", 0, open_gaps(_cells["R4"].banks[0])[0])},
		{"name": "bay4_dark", "transform": _view(Vector2(13.4, 28.64), -90.0, -0.03), "wait": 2.5, "call": func() -> void:
			_lights(0.0)
			var c5: Cell = _cells["R5"]
			c5.grp_on[0] = 1.0
			c5.grp_on[1] = 1.0
			c5.lit_dirty = true
			_push_cell(c5)},
		{"name": "bay4_aisle", "transform": _view(_gap_planned("R5", 0, [9, 20], 9, -0.5), 180.0, -0.04),
			"wait": 2.5, "call": func() -> void:
				_lights(0.0)
				_set_open("R5", 0, [9, 20])
				_bar_gap("R5", 0, 9)},
		{"name": "exit", "transform": _view(Vector2(21.5, 28.9), -60.0, 0.0), "wait": 2.5, "call": func() -> void:
			_lights(0.0)
			var c5: Cell = _cells["R5"]
			c5.grp_on[1] = 1.0
			c5.grp_on[2] = 1.0
			c5.lit_dirty = true
			_push_cell(c5)},
		{"name": "corridor_b", "transform": _view(Vector2(36.14, 9.6), 0.0, -0.03), "call": _lights_on},
		{"name": "stair2", "transform": _view(Vector2(36.14, 24.8), 0.0, 0.02), "call": _lights_on},
		{"name": "stair1", "transform": _view(Vector2(-1.2, 17.98), 90.0, 0.0), "call": _lights_on},
	]


const R3X0 := 19.2


## QA (SWEEP=<step m> level_shots): every `step` m over the floor where a
## person can stand, four ways, all lights on, for the worst draw calls.
func _sweep_shots(step: float) -> Array:
	var out: Array = []
	var free := grid_free()
	var k := 0
	for c in _cell_list:
		var r: Rect2 = (c as Cell).rect
		var y := r.position.y + step * 0.5
		while y < r.end.y:
			var x := r.position.x + step * 0.5
			while x < r.end.x:
				var i := grid_index(Vector2(x, y))
				var best := -1
				for dy in range(-6, 7):
					for dx in range(-6, 7):
						var j := grid_index(Vector2(x + dx * GRID, y + dy * GRID))
						if j >= 0 and free[j] == 1 and (best < 0 or absi(dx) + absi(dy) < absi(best % 100 - 50) + absi(best / 100 - 50)):
							best = (dy + 50) * 100 + dx + 50
				if best >= 0:
					i = grid_index(Vector2(x + (best % 100 - 50) * GRID, y + (best / 100 - 50) * GRID))
					var at := grid_pos(i)
					for yaw in [0.0, 90.0, 180.0, -90.0]:
						var sh := {"name": "sw%03d_%s" % [k, (c as Cell).id], "transform": _view(at, yaw, -0.03),
								"wait": 0.3}
						if k == 0:
							sh["call"] = _lights_on
						out.append(sh)
						k += 1
				x += step
			y += step
	return out


# ------------------------------------------------------------------ film ---

## Film: Bay 1 in the dark, the lights striking; into bank B's aisle, which
## shuts on you (the near miss, out at a walk); corridor A, a fire door that
## opens onto shelving as the range rolls; Bay 4 in the dark, the knocking,
## lights going out behind you; the exit.
func film() -> void:
	if OS.get_environment("FILM") == "stair":
		await _film_stair()
		return
	_events = true
	player.set_flashlight(false)
	_lights(0.0)
	_sensors = true
	_next_event = 1e9           # (no range moves but the ones the film shows)
	var ar := _v2(LAYOUT.DATA.arrival)
	player.teleport(_g(ar), -PI * 0.5, -0.05)
	_switch_on(_cells["R1"], 0, 0.8)
	await get_tree().create_timer(3.0).timeout
	var r1b: Bank = _cells["R1"].banks[1]
	_first_a = false
	var ab: int = open_gaps(r1b)[0]
	var mb := _gap_in("R1", 1, ab, 0.3)
	await _walk_to(Vector2(mb.x, ar.y + 0.3), 8.0)
	await _turn_to(0.0, -0.03, 0.6)
	await _walk_to(_gap_in("R1", 1, ab, 2.6), 4.0)
	# the warning: a look at it, then turn and walk out as the gap narrows
	await _until(func() -> bool: return r1b.state == 1, 4.0)
	await _turn_to(0.35, 0.0, 0.8)
	await get_tree().create_timer(1.0).timeout
	await _turn_to(PI, -0.05, 0.4)
	await _walk_to(Vector2(mb.x, ar.y + 0.2), 4.0)
	await _turn_to(0.2, -0.05, 0.6)
	await _until(func() -> bool: return r1b.state == 0, 16.0)
	await get_tree().create_timer(0.5).timeout
	var ex := _gap_in("R1", 1, open_gaps(r1b)[0], 0.3)
	await _turn_to(-PI * 0.5, -0.03, 0.5)
	await _walk_to(Vector2(ex.x, ar.y + 0.3), 6.0)
	await _turn_to(0.0, -0.03, 0.5)
	await _walk_to(Vector2(ex.x, 16.35), 6.0)
	await _turn_to(atan2(-(10.65 - ex.x), 0.0001) if absf(10.65 - ex.x) > 0.2 else 0.0, -0.03, 0.4)
	await _walk_to(Vector2(10.65, 16.35), 3.0)
	await _turn_to(0.0, -0.03, 0.4)
	var r5: Bank = _cells["R5"].banks[0]
	_set_open("R5", 0, [3, 14])
	await _walk_to(Vector2(10.65, 17.9), 2.0)
	# corridor A: the fire door onto Bay 4's shelving, the range rolling past it
	await _walk_to(Vector2(18.55, 17.85), 8.0)
	await _turn_to(0.0, -0.04, 0.6)
	_switch_on(_cells["R5"], 0)
	await get_tree().create_timer(0.8).timeout
	_start_move(r5, 3, 6)
	await _until(func() -> bool: return r5.state == 0, 16.0)
	await get_tree().create_timer(0.4).timeout
	await _walk_to(Vector2(18.55, 19.6), 2.0)
	await _walk_to(Vector2(18.55, 28.7), 6.0)
	await _turn_to(-PI * 0.5, -0.04, 0.6)
	_first_r5 = false
	_knock_t = 1.0
	await _walk_to(Vector2(23.8, 28.7), 6.0)
	await _turn_to(0.0, -0.05, 0.5)
	await _walk_to(Vector2(24.6, 29.0), 2.0)
	for e in get_tree().get_nodes_in_group("usable"):
		var le := e as LevelEntrance
		if le and le.exit_of == self and le.dest == "":
			await le.enter(player)
	await get_tree().create_timer(0.8).timeout


## FILM=stair: up corridor B to STAIR 2 at its far end, and through it (the
## opening of the stairwell's film).
func _film_stair() -> void:
	print("FILM_START frame %d" % Engine.get_frames_drawn())
	_events = false
	player.set_flashlight(false)
	_lights_on()
	var sx: float = LAYOUT.DATA.stair[0]
	var sy: float = LAYOUT.DATA.stair[1]
	player.teleport(_g(Vector2(sx, 19.5)), 0.0, -0.02)
	await get_tree().create_timer(1.5).timeout
	await _walk_to(Vector2(sx, sy - 1.6), 6.0)
	await _turn_to(0.0, 0.08, 0.8)
	await get_tree().create_timer(1.2).timeout
	await _walk_to(Vector2(sx, sy - 0.9), 2.0)
	for e in get_tree().get_nodes_in_group("usable"):
		var le := e as LevelEntrance
		if le and le.exit_of == self and le.dest == "stairwell":
			await le.enter(player)
	await get_tree().create_timer(0.6).timeout


func _until(cond: Callable, limit: float) -> void:
	var t := 0.0
	while not cond.call() and t < limit:
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
		player.yaw = lerp_angle(player.yaw, want, 0.25)
		player._apply_rotation()
		t += get_process_delta_time()
		await get_tree().process_frame
	Input.action_release("move_forward")
