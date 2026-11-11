extends SideLevel
## The Endless Stairwell: a concrete service stair in a painted block shaft,
## going down. Two flights a storey round an open well, 7 in risers and
## 11 in treads on a 44 in clear width, steel guards and black handrails,
## safety-yellow nosings, a 3070 fire door on every landing with its vision
## panel, the stair identification sign (STAIR 2, the floor in the middle)
## and the floor number stencilled big on the block beside it, a two-lamp
## wall fixture over each landing and half landing. Sizes, light and their
## sources: assets/levels/stairwell/SPEC.md; the kits:
## tools/blender/levels/stairwell.py.
##
## You come in on B2, the top landing, through its door (from the Stacks'
## STAIR 2, or the STAIRS door on the Backrooms' garage level), and it
## shuts behind you. That door is the way back out (to the Backrooms,
## somewhere else). Down, the floors keep counting, and stop making sense
## (B12, B14; B27 twice; B47, B112...). The lights get fewer the deeper you
## go: failing ballasts, dead fixtures, a battery pack's last glow. A door
## slams somewhere below. Footsteps come up the stair toward you and stop a
## flight and a half short. A hand rests on the guard rail two floors
## down, and it is always two floors down. The landing doors are locked.
## Nothing catches you: this is the dread level. At the bottom (B58 by the
## count, 179 m down) the stair runs down into black water, and walking on
## into it takes you on into the flooded basement (NEXT).
##
## Going back up is honest: every flight you went down is a flight to climb
## (about as long as the descent: no cheap escape), and B2's door lets you
## out. It's a stair, not a trap; the dread is in going on.
##
## It never ends because it isn't built: seven storeys of the one kit stand
## in a fixed stack round you (two above, four below), and when you're more
## than half a storey down (or up) everything moves by exactly one storey:
## you are put back up by one floor height (Player.shift_y) and every
## storey in the stack shows the floor next to the one it showed (its
## numbers, its lamps, its door). The stack is identical storey to storey
## (collision included), so nothing you can see, touch or hear jumps (proved
## by _test/levels/stairwell_test.tscn).

const NAME := "Level 4.1 - The Endless Stairwell"
const INTRO := "B2. B3. B4. It doesn't stop."
const NEXT := "flooded"

const DIR := "res://assets/levels/stairwell/"
const TEX := "res://assets/levels/stairwell/textures"
const AUD := "res://assets/levels/stairwell/audio/"
const SHADER_SW := "res://assets/levels/stairwell/stairwell_lit.gdshader"
const SHADER_SW_CUTOUT := "res://assets/levels/stairwell/stairwell_lit_cutout.gdshader"

## Sizes (m), as tools/blender/levels/stairwell.py (Blender x across the
## shaft, y along the flights from the door wall, z up from the landing).
const IN := 0.0254
const R := 7 * IN
const T := 11 * IN
const NR := 9
const H := 2 * NR * R                 # 3.2004 m floor to floor
const CLEAR := 44 * IN
const FW := CLEAR + 0.05
const WELL := 0.75
const SW := 2 * FW + WELL
const RUN := (NR - 1) * T
const LM := 60 * IN
const LH := 48 * IN
const SL := LM + RUN + LH
const SLAB := 0.2
const GUARD_H := 42 * IN
const DOOR_W := 36 * IN
const DOOR_H := 84 * IN
const DOOR_X := SW / 2
const SIGN_W := 18 * IN
const SIGN_H := 12 * IN
const SIGN_Z := 60 * IN
const SIGN_X := DOOR_X - DOOR_W / 2 - 0.12 - SIGN_W / 2
const STENCIL_X := DOOR_X + DOOR_W / 2 + 0.62
const STENCIL_Z := 1.62
const STENCIL_H := 0.42
const LAMP_Z := DOOR_H + 0.38
const LAMP_HZ := H / 2 + 2.25
## The stair: B2 at the top, the water at B58 (56 storeys, 179 m: about
## three minutes on foot at a walk, see SPEC.md).
const TOP := 2
const BOTTOM := 58
## The stack: storeys j = J0 .. J1 round you (0: the one you're on).
const J0 := -2
const J1 := 4
## Past the half landing by this much before the stack moves a storey (and
## you land this far short of it on the other side: no flip-flop).
const SWAP := H * 0.5 + 0.3
## Water at the bottom: over landing BOTTOM this deep; in it this deep, on
## you go (NEXT).
const WATER_D := 1.2
const EXIT_DEPTH := 0.85
## L.U.C.I.D.: one fixture's light on the landing under it (~140 lux,
## engine units of E / pi at 2.3 m: I0 = 2332 lm x 0.8 / pi cd), for the
## exposure meter and light_at().
const LAMP_I := 0.29 * 2.3 * 2.3
## Lamps (per storey and fixture: 0 landing, 1 half landing).
enum { LAMP_ON, LAMP_FLICKER, LAMP_DIM, LAMP_DEAD }
## Events by storey (the first time you reach it).
const SLAM_AT := [6, 17, 29, 41, 52]
const STEPS_AT := [9, 22, 35, 47]
const HAND_FROM := 7
const HAND_J := 2                     # two floors down

var base := TOP                       # the storey slot 0 shows (you're on it)
var _slots: Array = []
var _rng := RandomNumberGenerator.new()
var _t := 0.0
var _events := true
var _streams := {}
var _pool: Array[AudioStreamPlayer3D] = []
var _pool_i := 0
var _hums: Array[AudioStreamPlayer3D] = []
var _lamp_rgb := Vector3.ONE
var _base_exposure := 1.0
var _ae := 1.0
var _ae_snap := true
var _unit_mats: Array[ShaderMaterial] = []
var _digits_mat: ShaderMaterial
var _hand: Node3D
var _hand_mat: ShaderMaterial
var _hand_state := 0                  # 0 resting, 1 letting go, 2 gone
var _hand_t := 0.0
var _hand_back := 0
var _stare := 0.0
var _water: MeshInstance3D
var _water_mat: ShaderMaterial
var _water_audio: AudioStreamPlayer3D
var _exit_b2: LevelEntrance
var _leaf_mat: ShaderMaterial
var _leaf_meshes: Array[GeometryInstance3D] = []
var _exit_water: LevelEntrance
var _door_t := -1.0
var _died := {}                       # storey * 2 + fixture -> time it died
var _flick := {}                      # storey * 2 + fixture -> until when it flickers (a slam's jolt)
var _seen := {}                       # storeys reached
var _deepest := TOP
var _slam_queue: Array = []           # [time, storey]
var _steps := {}                      # an episode: {u, t_next, n}
var _last_lamp := {}                  # key -> last level (for the flicker sounds)
var _flick_snd_t := 0.0
var _fade: ColorRect
## Tests: rebase count, the last shift.
var rebases := 0
## The film: wade in without going through.
var film_hold_exit := false
## The fixtures' light colour (F17T8/841: 4100 K, under the body cam's 4100 K
## white balance it's near white, a little green).
var _lamp_kelvin := 4100.0


class Slot:
	var j := 0
	var n := -999
	var root: Node3D
	var unit: Node3D
	var top: Node3D
	var body: StaticBody3D
	var top_body: StaticBody3D
	var numbers: MeshInstance3D
	var text := ""
	var meshes: Array[GeometryInstance3D] = []
	var door_use: Node3D


# ----------------------------------------------------------------- build ---

func build(p_seed: int) -> void:
	seed_value = p_seed
	_rng.seed = p_seed
	var c := Lucid.kelvin_rgb(_lamp_kelvin, false, 0.003) * Lucid.wb_gains(4300.0)
	c = c / maxf(Lucid.lum(c), 0.001)
	_lamp_rgb = Vector3(c.r, c.g, c.b)
	_load_sounds()
	var surfaces := {
		"concrete": {"texture": "concrete", "scale": 0.6, "roughness": 1.0, "specular": 0.4, "normal_depth": 0.6},
		"cmu_paint": {"texture": "cmu_paint", "scale": Vector2(1.0 / 1.2192, 1.0 / (H * 0.5)), "roughness": 1.0,
				"specular": 0.3, "normal_depth": 0.9},
		"door_paint": {"texture": "door_paint", "scale": 0.8, "roughness": 1.0, "specular": 0.5, "normal_depth": 0.6},
		"sign_plate": {"texture": "sign_plate", "scale": 1.0, "roughness": 0.5, "specular": 0.4},
		"paint": {"color": Color(1, 1, 1), "roughness": 0.55, "specular": 0.4, "emit": 3103.0 / 153.6},
	}
	var lm := DIR + "lightmaps/"
	var unit := load_kit(DIR + "stair_unit.glb", "", TEX, surfaces, lm + "stair_unit_groups.png")
	var top := load_kit(DIR + "stair_top.glb", "", TEX, surfaces, lm + "stair_top_groups.png")
	var sh: Shader = load(SHADER_SW)
	for m in _kit_mats:
		var sm := m as ShaderMaterial
		if sm == null:
			continue
		sm.shader = sh
		sm.set_shader_parameter("const_light", Vector3.ZERO)
		sm.set_shader_parameter("lamp_rgb", _lamp_rgb)
		_unit_mats.append(sm)
	for k in [unit, top]:
		for mi in (k as Node3D).find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			for s in m.mesh.get_surface_count():
				var src := m.mesh.surface_get_material(s)
				if src and _clean_name(src.resource_name) == "paint":
					(m.get_surface_override_material(s) as ShaderMaterial).set_shader_parameter("kit_vcol", true)
	_digits_mat = flat_material({"color": Color(1, 1, 1), "roughness": 0.8, "specular": 0.2, "cutout": true,
			"texture": "digits"}, Color(0, 0, 0), Vector4(0.10, 0.012, 0.004, 0.012), TEX)
	_digits_mat.shader = load(SHADER_SW_CUTOUT)
	_digits_mat.set_shader_parameter("vcol", true)
	_digits_mat.set_shader_parameter("lamp_rgb", _lamp_rgb)
	_digits_mat.set_shader_parameter("const_light", Vector3.ZERO)
	_digits_mat.set_shader_parameter("flat_shade", 0.0)
	for j in range(J0, J1 + 1):
		_slots.append(_make_slot(j, unit, top))
	unit.queue_free()
	top.queue_free()
	_build_hand()
	_build_water()
	_build_audio()
	# B2's door: the way back (the Backrooms, somewhere else); the water: on.
	_exit_b2 = add_exit(Transform3D(Basis(Vector3.UP, PI), Vector3(DOOR_X, LEVEL_Y, 0.0)), "door", "",
			{"label": "Open the door", "script": "res://scripts/world/levels/stairwell_entrance.gd"})
	_leaf_mat = flat_material({"color": Color(1, 1, 1), "roughness": 1.0, "specular": 0.5, "normal_depth": 0.6,
			"texture": "door_paint", "uv": 1, "scale": 1.25}, Color(0, 0, 0), Vector4(0.16, 0.012, 0.0, 0.012), TEX)
	_leaf_mat.shader = sh
	_leaf_mat.set_shader_parameter("lamp_rgb", _lamp_rgb)
	_leaf_mat.set_shader_parameter("const_light", Vector3.ZERO)
	var leaf: Node3D = _exit_b2.parts.get("leaf")
	if leaf:
		var first := true
		for mi in leaf.find_children("*", "MeshInstance3D", true, false):
			if first:
				(mi as MeshInstance3D).material_override = _leaf_mat     # (the leaf itself; the rest is hardware)
				first = false
			_leaf_meshes.append(mi)
	_exit_water = add_exit(Transform3D(Basis(), Vector3(0, LEVEL_Y - 5000.0, 0)), "none", NEXT, {"walk_in": false})
	environment = make_environment({"background": Color(0, 0, 0), "fog": Color(0, 0, 0), "fog_density": 0.035,
			"exposure": 1.0, "glow": 0.3, "saturation": 0.9, "contrast": 1.04})
	environment.adjustment_color_correction = null
	_base_exposure = environment.tonemap_exposure
	_rebase(TOP, true)


## Where slot j's storey stands (its landing, Godot).
func _slot_origin(j: int) -> Vector3:
	return Vector3(0.0, LEVEL_Y - j * H, 0.0)


## A point of a storey (Blender local: x across, y from the door wall, z up
## from its landing) in slot j's place (Godot).
func _at(j: int, b: Vector3) -> Vector3:
	return _slot_origin(j) + Vector3(b.x, b.z, -b.y)


func _make_slot(j: int, unit: Node3D, top: Node3D) -> Slot:
	var s := Slot.new()
	s.j = j
	s.root = Node3D.new()
	s.root.name = "storey_%d" % (j - J0)
	add_child(s.root)
	s.root.global_position = _slot_origin(j)
	s.unit = unit.duplicate()
	s.top = top.duplicate()
	for k in [s.unit, s.top]:
		s.root.add_child(k)
		(k as Node3D).position = Vector3.ZERO
		for mi in (k as Node3D).find_children("*", "MeshInstance3D", true, false):
			s.meshes.append(mi)
		# (the kits carry no collision: it's made here, below)
		for b in (k as Node3D).find_children("*", "CollisionObject3D", true, false):
			b.queue_free()
	s.body = _unit_body(false)
	s.top_body = _unit_body(true)
	s.root.add_child(s.body)
	s.root.add_child(s.top_body)
	s.numbers = MeshInstance3D.new()
	s.numbers.material_override = _digits_mat
	s.numbers.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	s.root.add_child(s.numbers)
	s.meshes.append(s.numbers)
	var du := _DoorUse.new()
	du.level = self
	du.slot = s
	s.root.add_child(du)
	du.position = Vector3(DOOR_X + DOOR_W / 2 - 0.12, 1.0, 0.05)
	s.door_use = du
	return s


## Collision of a storey (slot frame): the landing, the half landing, the
## two flights as smooth ramps under the nosings (the player walks them as
## a slope, both ways, as the Backrooms' own stairwells), the walls, the
## guards round the well. The top storey: its landing, walls, roof, guard.
func _unit_body(top: bool) -> StaticBody3D:
	var b := StaticBody3D.new()
	b.name = "top_body" if top else "body"
	_bx(b, 0.0, SW, 0.0, LM, -SLAB, 0.0)
	var z1 := H - SLAB
	_bx(b, -0.3, 0.0, -0.3, SL + 0.3, -SLAB, z1)
	_bx(b, SW, SW + 0.3, -0.3, SL + 0.3, -SLAB, z1)
	_bx(b, -0.3, SW + 0.3, -0.3, 0.0, -SLAB, z1)
	_bx(b, -0.3, SW + 0.3, SL, SL + 0.3, -SLAB, z1)
	if top:
		_bx(b, -0.3, SW + 0.3, -0.3, SL + 0.3, H - SLAB, H + 0.2)
		_bx(b, FW - 0.05, SW, LM - 0.05, LM, 0.0, GUARD_H)
		return b
	_bx(b, 0.0, SW, LM + RUN, SL, H / 2 - SLAB, H / 2)
	_ramp(b, SW - FW, SW, LM, 0.0, LM + RUN, H / 2)
	_ramp(b, 0.0, FW, LM + RUN, H / 2, LM, H)
	# guards: along the flights' well edges (sloped), across the well's ends
	_guard(b, SW - FW, SW - FW + 0.05, LM, 0.0, LM + RUN, H / 2)
	_guard(b, FW - 0.05, FW, LM + RUN, H / 2, LM, H)
	_bx(b, FW - 0.05, SW - FW + 0.05, LM - 0.05, LM, 0.0, GUARD_H)
	_bx(b, FW - 0.05, SW - FW + 0.05, LM + RUN, LM + RUN + 0.05, H / 2, H / 2 + GUARD_H)
	return b


## A box (Blender local extents) into body b.
func _bx(b: StaticBody3D, x0: float, x1: float, y0: float, y1: float, z0: float, z1: float) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, z1 - z0, y1 - y0)
	cs.shape = bs
	cs.position = Vector3((x0 + x1) * 0.5, (z0 + z1) * 0.5, -(y0 + y1) * 0.5)
	b.add_child(cs)


## A guard along a flight: a vertical sheet x0..x1 standing GUARD_H + R
## over the line from (ya, za) to (yb, zb) (Blender local), its ends plumb.
func _guard(b: StaticBody3D, x0: float, x1: float, ya: float, za: float, yb: float, zb: float) -> void:
	var pts := PackedVector3Array()
	for x in [x0, x1]:
		for e in [[ya, za], [yb, zb]]:
			pts.append(Vector3(x, e[1] - R, -e[0]))
			pts.append(Vector3(x, e[1] + GUARD_H, -e[0]))
	var cs := CollisionShape3D.new()
	var cp := ConvexPolygonShape3D.new()
	cp.points = pts
	cs.shape = cp
	b.add_child(cs)


## A sloped slab (a flight's walking surface) from (ya, za) to (yb, zb)
## (Blender local), x0..x1 across: its top face through those edges,
## `thick` deep under it.
func _ramp(b: StaticBody3D, x0: float, x1: float, ya: float, za: float, yb: float, zb: float, thick := 0.25) -> void:
	var a := Vector3(0.0, za, -ya)
	var c := Vector3(0.0, zb, -yb)
	var d := c - a
	var length := d.length()
	var ax := d / length                              # along the slope (Godot, in the y-z plane)
	var nrm := Vector3(0.0, ax.z, -ax.y)
	if nrm.y < 0.0:
		nrm = -nrm
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(x1 - x0, thick, length)
	cs.shape = bs
	var mid := (a + c) * 0.5 + Vector3((x0 + x1) * 0.5, 0.0, 0.0) - nrm * thick * 0.5
	cs.transform = Transform3D(Basis(Vector3.RIGHT, nrm, Vector3.RIGHT.cross(nrm)), mid)
	b.add_child(cs)


# --------------------------------------------------------- the floors ---

## What the floor number says on storey n (it stops making sense).
static func label(n: int) -> String:
	if n <= 12:
		return "B%d" % n
	if n <= 26:
		return "B%d" % (n + 1)          # (no 13)
	if n == 27:
		return "B27"                    # (again)
	if n <= 44:
		return "B%d" % n
	var deep := {45: "B47", 46: "B112", 47: "B113", 48: "B47", 49: "B48", 50: "B49", 51: "B9", 52: "B51",
			53: "B52", 54: "B53", 55: "B--", 56: "B--", 57: "B5", 58: "B"}
	return deep.get(n, "B-")


## Shows storey `nb` on slot 0 (the others round it); `force` rebuilds all.
func _rebase(nb: int, force := false) -> void:
	base = nb
	for s in _slots:
		var sl: Slot = s
		var n := base + sl.j
		if n == sl.n and not force:
			continue
		sl.n = n
		var shown := n >= TOP and n <= BOTTOM
		var is_top := n == TOP
		sl.unit.visible = shown and not is_top
		sl.top.visible = shown and is_top
		# (the storey under the water keeps its floor: nobody falls past the bottom)
		var solid := (shown and not is_top) or n == BOTTOM + 1
		sl.body.process_mode = Node.PROCESS_MODE_INHERIT if solid else Node.PROCESS_MODE_DISABLED
		sl.top_body.process_mode = Node.PROCESS_MODE_INHERIT if is_top else Node.PROCESS_MODE_DISABLED
		sl.numbers.visible = shown and n < BOTTOM
		sl.door_use.visible = shown and not is_top and n < BOTTOM
		var txt := label(n) if shown else ""
		if txt != sl.text:
			sl.text = txt
			sl.numbers.mesh = _numbers_mesh(txt) if txt != "" else null
	# B2's door, the hand, the water: where their storeys are now
	var jt := TOP - base
	if jt >= J0 and jt <= J1:
		_exit_b2.global_transform = Transform3D(Basis(Vector3.UP, PI), _at(jt, Vector3(DOOR_X, 0.0, 0.0)))
		_exit_b2.visible = true
	else:
		_exit_b2.global_position = Vector3(0, LEVEL_Y + 5000.0, 0)
		_exit_b2.visible = false
	var jb := BOTTOM - base
	_water.visible = jb >= J0 and jb <= J1
	if _water.visible:
		_water.global_position = _at(jb, Vector3(SW / 2, SL / 2, WATER_D))
		_water_audio.global_position = _water.global_position + Vector3(0, 0.3, 0)
		if not _water_audio.playing:
			_water_audio.play()
	elif _water_audio.playing:
		_water_audio.stop()
	_update_lamps(0.0)


## The stencil on the block and the number on the sign: quads cut from
## the digit strip (B, 0-9, -), black paint and white letters.
func _numbers_mesh(txt: String) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_text_quads(st, txt, Vector3(STENCIL_X, 0.004, STENCIL_Z), STENCIL_H, Color(0.025, 0.025, 0.025))
	_text_quads(st, txt, Vector3(SIGN_X, 0.0085, SIGN_Z + SIGN_H * 0.47), 5 * IN, Color(0.8, 0.81, 0.79))
	return st.commit()


func _text_quads(st: SurfaceTool, txt: String, c: Vector3, h: float, col: Color) -> void:
	var chars := "B0123456789-"
	var w := h * 64.0 / 96.0 * 0.92
	# (read facing the door wall, Godot +z: the letters run toward -x)
	var x := c.x + w * txt.length() * 0.5
	for ch in txt:
		var k := chars.find(ch)
		if k < 0:
			x -= w
			continue
		var u0 := k / 16.0
		var u1 := (k + 1) / 16.0
		# (Blender x across, Godot z = -y; facing +y Blender = -z Godot)
		var p0 := Vector3(x, c.z - h * 0.5, -c.y)
		var p1 := Vector3(x - w, c.z - h * 0.5, -c.y)
		var p2 := Vector3(x - w, c.z + h * 0.5, -c.y)
		var p3 := Vector3(x, c.z + h * 0.5, -c.y)
		for v in [[p0, Vector2(u0, 1)], [p2, Vector2(u1, 0)], [p1, Vector2(u1, 1)],
				[p0, Vector2(u0, 1)], [p3, Vector2(u0, 0)], [p2, Vector2(u1, 0)]]:
			st.set_color(col)
			st.set_normal(Vector3(0, 0, -1))
			st.set_uv(v[1])
			st.add_vertex(v[0])
		x -= w


# ----------------------------------------------------------------- lamps ---

func _h01(a: int, b: int, c: int) -> float:
	var h := hash([seed_value & 0xFFFF, a, b, c])
	return float(h & 0xFFFF) / 65535.0


## What kind of fixture storey n's fixture k is (fewer and worse the deeper).
func lamp_kind(n: int, k: int) -> int:
	if n < TOP or n > BOTTOM:
		return LAMP_DEAD
	if n >= BOTTOM - 1:
		# the bottom: B58's fixtures still burn, on their batteries, over the water
		return LAMP_DIM if n == BOTTOM else LAMP_DEAD
	if n <= 5:
		return LAMP_ON
	var d := float(n - TOP) / float(BOTTOM - TOP)
	var p_dead := clampf(smoothstep(0.1, 0.92, d) * 0.92, 0.0, 0.92)
	var r := _h01(n, k, 1)
	if r < p_dead:
		return LAMP_DEAD
	var r2 := _h01(n, k, 2)
	if r2 < 0.12 + 0.35 * d:
		return LAMP_FLICKER
	if r2 > 1.0 - 0.25 * d:
		return LAMP_DIM
	return LAMP_ON


## How bright storey n's fixture k is now (0..1).
func lamp_level(n: int, k: int) -> float:
	var key := n * 2 + k
	if _died.has(key):
		var since := _t - float(_died[key])
		if since > 0.9 or since < 0.0:
			return 0.0
		return 1.0 if fmod(since * 17.0, 1.0) < 0.45 else 0.06      # its last stutter
	var kind := lamp_kind(n, k)
	var v := 0.0
	match kind:
		LAMP_ON:
			v = 1.0
		LAMP_DIM:
			v = 0.22 + 0.03 * sin(_t * 0.7 + n)
		LAMP_FLICKER:
			v = _flicker(n, k, _t)
	if _flick.has(key) and _t < float(_flick[key]) and v > 0.0:
		v *= 0.0 if fmod(_t * 21.0 + k, 1.0) < 0.5 else 1.0
	return v


## A failing ballast: mostly on; now and then the tubes drop out, stutter,
## glow at the ends and strike again (each fixture its own pattern).
func _flicker(n: int, k: int, t: float) -> float:
	var tt := t + _h01(n, k, 7) * 10.0
	var win := 0.9
	var e := floori(tt / win)
	var f := tt - e * win
	if _h01(n * 131 + e, k, 11) < 0.6:
		return 1.0
	var a := _h01(n * 131 + e, k, 13) * 0.35
	var dur := 0.06 + _h01(n * 131 + e, k, 17) * 0.38
	if f < a:
		return 1.0
	if f < a + dur:
		var s := fmod((f - a) * 19.0, 1.0)
		return 0.0 if s < 0.72 else 0.4
	if f < a + dur + 0.14:
		return 0.12                     # cathode glow before it strikes
	return 1.0


## Every storey's four light multipliers (its fixtures, the storeys either
## side) onto its meshes; the hums; the sounds of a fixture dropping out.
func _update_lamps(_delta: float) -> void:
	var lv := {}
	for n in range(base + J0 - 1, base + J1 + 2):
		lv[n] = Vector2(lamp_level(n, 0), lamp_level(n, 1))
	for s in _slots:
		var sl: Slot = s
		var n := base + sl.j
		var me: Vector2 = lv[n]
		var up: Vector2 = lv[n - 1]
		var dn: Vector2 = lv[n + 1]
		var u := Vector4(me.x, me.y, (up.x + up.y) * 0.5, (dn.x + dn.y) * 0.5)
		for m in sl.meshes:
			m.set_instance_shader_parameter("unit_light", u)
	# hums: storeys -1..1, both fixtures
	var i := 0
	for j in range(-1, 2):
		for k in 2:
			var v: float = lv[base + j][k]
			var a := _hums[i]
			a.volume_db = linear_to_db(maxf(v, 0.0001)) - 15.0
			i += 1
	# a fixture near you dropping out: its ballast ticking and buzzing
	if player and _events:
		var cam := player.camera.global_position
		for j in range(-1, 2):
			for k in 2:
				var n := base + j
				var key := n * 2 + k
				var v: float = lv[n][k]
				var was: float = _last_lamp.get(key, v)
				_last_lamp[key] = v
				if was >= 0.5 and v < 0.5 and _t > _flick_snd_t and lamp_kind(n, k) == LAMP_FLICKER:
					var p := _lamp_pos(j, k)
					if p.distance_to(cam) < 7.0:
						_flick_snd_t = _t + 0.7
						_play_at(_pick("flicker_"), p, -8.0, randf_range(0.95, 1.05))
	if _hand:
		var n := base + HAND_J
		_hand.set_instance_shader_parameter("unit_light", Vector4(lv[n].x, lv[n].y, 0.0, 0.0))
	if _exit_b2 and _exit_b2.visible:
		var lt := lamp_level(TOP, 0)
		(_exit_b2 as Object).call("set_light", 0.5 * lt)
		for m in _leaf_meshes:
			m.set_instance_shader_parameter("unit_light", Vector4(lt, 0.0, 0.0, lamp_level(TOP + 1, 0)))


## A fixture's lens (Godot), slot j, fixture k.
func _lamp_pos(j: int, k: int) -> Vector3:
	if k == 0:
		return _at(j, Vector3(DOOR_X, 0.1, LAMP_Z))
	return _at(j, Vector3(DOOR_X, SL - 0.1, LAMP_HZ))


## Light reaching p (engine units of E / pi): the fixtures near it, by the
## inverse square, with their walls and slabs ignored (exposure, figures).
func _light_level(p: Vector3) -> float:
	var e := 0.0
	var jp := int(round((LEVEL_Y - p.y) / H))
	for j in range(jp - 1, jp + 2):
		if j < J0 or j > J1:
			continue
		for k in 2:
			var l := lamp_level(base + j, k)
			if l <= 0.0:
				continue
			var d2 := maxf(_lamp_pos(j, k).distance_squared_to(p), 0.6)
			e += LAMP_I * l / d2
	return e + 0.002


func light_at(p: Vector3) -> Color:
	var e := _light_level(p)
	return Color(_lamp_rgb.x * e, _lamp_rgb.y * e, _lamp_rgb.z * e)


func albedo_at(_p: Vector3, n: Vector3) -> Color:
	if n.y > 0.7 or n.y < -0.7:
		return Color(0.27, 0.265, 0.25)
	return Color(0.47, 0.465, 0.43)


# ---------------------------------------------------------- the hand ---

## A hand on the guard rail two floors down (U2's guard, part way up),
## the fingers over the rail into the well, a sleeve going back into the
## dark of the flight. One mesh, lit by its storey's fixtures.
func _build_hand() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var skin := Color(0.33, 0.30, 0.275)           # pale, grey, dirty
	var cloth := Color(0.03, 0.03, 0.035)
	var parts := []
	# (local: z along the rail, +x over the well, +y up; the rail's top at 0)
	# the palm across the top of the rail
	parts.append([Vector3(0.075, 0.024, 0.088), Transform3D(Basis(), Vector3(0.0, 0.016, 0.0)), skin])
	# four fingers over the rail into the well, curled down round it
	for f in 4:
		var z := -0.033 + f * 0.022
		var l := 0.034 if f != 3 else 0.028
		parts.append([Vector3(l, 0.018, 0.018), Transform3D(Basis(Vector3.BACK, -0.75), Vector3(0.048, 0.0, z)), skin])
		parts.append([Vector3(0.017, 0.032, 0.017), Transform3D(Basis(Vector3.BACK, -0.25), Vector3(0.066, -0.032, z)), skin])
	# the thumb round the back of the rail
	parts.append([Vector3(0.018, 0.045, 0.02), Transform3D(Basis(Vector3.BACK, 0.35), Vector3(-0.035, -0.012, 0.052)), skin])
	# wrist and bare forearm back over the flight and down, then the sleeve
	parts.append([Vector3(0.26, 0.052, 0.062), Transform3D(Basis(Vector3.BACK, 0.5), Vector3(-0.15, -0.055, 0.0)), skin])
	parts.append([Vector3(0.34, 0.09, 0.09), Transform3D(Basis(Vector3.BACK, 0.62), Vector3(-0.41, -0.215, 0.0)), cloth])
	for pt in parts:
		var bm := BoxMesh.new()
		bm.size = pt[0]
		var arr := bm.get_mesh_arrays()
		var cols := PackedColorArray()
		cols.resize((arr[Mesh.ARRAY_VERTEX] as PackedVector3Array).size())
		cols.fill(pt[2])
		arr[Mesh.ARRAY_COLOR] = cols
		var am := ArrayMesh.new()
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		st.append_from(am, 0, pt[1])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	_hand_mat = flat_material({"color": Color(1, 1, 1), "roughness": 0.7, "specular": 0.3}, Color(0, 0, 0),
			Vector4(0.03, 0.22, 0.0, 0.0))
	_hand_mat.shader = load(SHADER_SW)
	_hand_mat.set_shader_parameter("vcol", true)
	_hand_mat.set_shader_parameter("lamp_rgb", _lamp_rgb)
	_hand_mat.set_shader_parameter("const_light", Vector3(0.004, 0.004, 0.004))
	mi.material_override = _hand_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_hand = mi
	add_child(mi)
	_place_hand(0.0)


## The hand on slot HAND_J's guard (gone: drawn back off the rail by `back`).
func _place_hand(back: float) -> void:
	var y := LM + RUN * 0.76
	var zn := H / 2 + R + (LM + RUN - y) * R / T            # the nosing line (U2)
	var p := _at(HAND_J, Vector3(FW - 0.025, y, zn + GUARD_H + 0.019))
	var slope := atan(R / T)
	# local x across the rail toward the well (Godot +x), along the rail z
	_hand.global_transform = Transform3D(Basis(Vector3.RIGHT, -slope).scaled(Vector3.ONE * 1.1),
			p + Vector3(-back, -back * 0.5, 0.0))


func _update_hand(delta: float) -> void:
	var n := base + HAND_J
	var want := _deepest >= HAND_FROM and n < BOTTOM - 1 and base + HAND_J >= TOP + 1
	if _hand_state == 2 and base >= _hand_back:
		_hand_state = 0
		_place_hand(0.0)
	if not want or _hand_state == 2:
		_hand.visible = false
		return
	_hand.visible = true
	if _hand_state == 0 and _events:
		# stared at: it lets go
		var cam := player.camera.global_transform
		var to := _hand.global_position - cam.origin
		var looking := (-cam.basis.z).dot(to.normalized()) > 0.985 and to.length() < 16.0
		_stare = _stare + delta if looking else maxf(_stare - delta * 0.5, 0.0)
		if _stare > 2.2:
			_hand_state = 1
			_hand_t = 0.0
	elif _hand_state == 1:
		_hand_t += delta
		var k := smoothstep(0.0, 1.0, _hand_t / 0.9)
		_place_hand(k * 0.5)
		if _hand_t > 0.9:
			_hand_state = 2
			_hand_back = base + 2
			_stare = 0.0


# --------------------------------------------------------- the water ---

func _build_water() -> void:
	_water = MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(SW + 0.1, SL + 0.1)
	pm.subdivide_width = 8
	pm.subdivide_depth = 12
	_water.mesh = pm
	_water_mat = ShaderMaterial.new()
	_water_mat.shader = load(DIR + "stairwell_water.gdshader")
	_water_mat.set_shader_parameter("lamp_rgb", _lamp_rgb)
	_water.material_override = _water_mat
	_water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_water)
	_water.visible = false


func water_level_at(p: Vector3) -> float:
	if not _water.visible:
		return -INF
	if p.x < -0.4 or p.x > SW + 0.4 or p.z > 0.4 or p.z < -SL - 0.4:
		return -INF
	return _water.global_position.y


func warm_materials() -> Array[Material]:
	var out := _kit_mats.duplicate()
	out.append(_water_mat)
	return out


# --------------------------------------------------------- the audio ---

func _load_sounds() -> void:
	for f in DirAccess.get_files_at(AUD):
		var n := f.trim_suffix(".import").trim_suffix(".remap")
		if n.ends_with(".ogg") and not _streams.has(n.get_basename()):
			_streams[n.get_basename()] = load(AUD + n)
	for i in 10:
		var a := AudioStreamPlayer3D.new()
		a.bus = "World"
		a.unit_size = 5.0
		a.max_distance = 70.0
		add_child(a)
		_pool.append(a)


func _pick(prefix: String) -> AudioStream:
	var c := []
	for k in _streams:
		if String(k).begins_with(prefix):
			c.append(_streams[k])
	return c[_rng.randi() % c.size()] if not c.is_empty() else null


func _play_at(st: AudioStream, at: Vector3, db := -6.0, pitch := 1.0, unit := 5.0) -> AudioStreamPlayer3D:
	if st == null or not _events:
		return null
	var a := _pool[_pool_i]
	_pool_i = (_pool_i + 1) % _pool.size()
	a.stream = st
	a.volume_db = db
	a.pitch_scale = pitch
	a.unit_size = unit
	a.global_position = at
	a.play()
	return a


func _build_audio() -> void:
	add_loop(_streams.get("shaft_loop"), Vector3.INF, -17.0)
	for j in range(-1, 2):
		for k in 2:
			var a := AudioStreamPlayer3D.new()
			var st: AudioStream = (_streams["hum_loop"] as AudioStream).duplicate()
			(st as AudioStreamOggVorbis).loop = true
			a.stream = st
			a.bus = "World"
			a.unit_size = 1.2
			a.max_distance = 12.0
			a.volume_db = -60.0
			a.pitch_scale = 1.0 + 0.004 * (j * 2 + k)
			add_child(a)
			a.global_position = _lamp_pos(j, k)
			a.play()
			_hums.append(a)
	_water_audio = AudioStreamPlayer3D.new()
	var ws: AudioStream = (_streams["water_loop"] as AudioStream).duplicate()
	(ws as AudioStreamOggVorbis).loop = true
	_water_audio.stream = ws
	_water_audio.bus = "World"
	_water_audio.unit_size = 4.0
	_water_audio.max_distance = 30.0
	_water_audio.volume_db = -8.0
	add_child(_water_audio)


# --------------------------------------------------------------- the game ---

func on_enter() -> void:
	player.can_climb = false            # (no vaulting the guards)
	var cs := get_tree().current_scene
	_events = cs == null or not String(cs.scene_file_path).contains("level_shots")
	_seen[base] = true
	if base == TOP and _events:
		# the door you came through, shutting behind you on its closer
		_door_t = 0.0
		(_exit_b2 as Object).call("set_open", -1.25)


func arrival() -> Transform3D:
	# B2, just in from the door, facing the stair
	return Transform3D(Basis(), _at(TOP - base, Vector3(DOOR_X, 0.85, 0.0)))


func surface_at(_p: Vector3) -> int:
	return Player.SURF_CONCRETE


func camera_far() -> float:
	return 30.0 if low else 42.0


## Concrete and block, top to bottom, nothing soft: long and hard.
func reverb() -> Dictionary:
	return {"room": 0.95, "damp": 0.12, "wet": 0.42}


func save_state() -> Dictionary:
	var died := []
	for k in _died:
		died.append(k)
	return {"base": base, "deepest": _deepest, "died": died, "seen": _seen.keys()}


func load_state(d: Dictionary) -> void:
	_rebase(int(d.get("base", TOP)), true)
	_deepest = int(d.get("deepest", base))
	for k in d.get("died", []):
		_died[int(k)] = -100.0
	for k in d.get("seen", []):
		_seen[int(k)] = true


## The storey you're on (the floor counter: tests).
func storey() -> int:
	return base


## Puts you on storey n's landing (debug / film / tests), as if you'd walked.
func goto_storey(n: int, at := Vector3(SW - FW / 2 - 0.05, LM - 0.45, 0.0), yaw := 0.0) -> void:
	_rebase(clampi(n, TOP, BOTTOM - 1), true)
	_deepest = maxi(_deepest, base)
	_seen[base] = true
	player.teleport(_at(0, at) + Vector3(0, 0.03, 0), yaw)
	_ae_snap = true


## A point of storey n (Blender local of that storey) in the world as the
## stack stands now.
func storey_point(n: int, b: Vector3) -> Vector3:
	return _at(n - base, b)


## Where to walk to next, going down (dir 1) or up (-1) the stair from
## where you are: a point a little further along the route; across a
## landing first if the route goes on from its other side.
func walk_target(dir: int) -> Vector3:
	var p := player.global_position
	var u := _u_of(p)
	var t := route_point(u + 0.07 * dir)
	if absf(t.x - p.x) > 0.45:
		var f := u - floorf(u)
		var yl := LM + RUN + 0.45 if absf(f - 0.5) < 0.2 else LM - 0.42
		return Vector3(t.x, p.y, -yl)
	return t


func _process(delta: float) -> void:
	if player == null:
		return
	_t += delta
	_update_lamps(delta)
	_update_hand(delta)
	_update_events(delta)
	_update_exposure(delta)
	_update_door(delta)
	_water_mat.set_shader_parameter("lamp_pos", _lamp_pos(BOTTOM - base, 0))
	_water_mat.set_shader_parameter("lamp_on", lamp_level(BOTTOM, 0))


func _physics_process(_delta: float) -> void:
	if player == null or _done:
		return
	var y := player.global_position.y - LEVEL_Y
	if not player.busy() and player.is_physics_processing():
		if y < -SWAP and base < BOTTOM:
			_shift(1)
		elif y > SWAP and base > TOP:
			_shift(-1)
	# into the water at the bottom: on into the flooded basement
	if not film_hold_exit and _water.visible and player.water_depth() > EXIT_DEPTH:
		_exit_activated(_exit_water)


## The stack moves a storey: down (+1) or up (-1). You go back up (down) by
## exactly one floor height, and every storey shows its neighbour's floor.
func _shift(dir: int) -> void:
	player.shift_y(H * dir)
	for a in _pool:
		if a.playing:
			a.global_position.y += H * dir
	_rebase(base + dir)
	rebases += 1
	_deepest = maxi(_deepest, base)
	if not _seen.has(base):
		_seen[base] = true
		_first_reach(base)


## Things that happen the first time you get down to a floor.
func _first_reach(n: int) -> void:
	if not _events:
		return
	if SLAM_AT.has(n):
		_slam_queue.append([_t + 2.5 + _rng.randf() * 2.0, n + 3])
	if STEPS_AT.has(n):
		start_steps()
	# a failing fixture just below gives up as you come down to it
	for k in 2:
		if lamp_kind(n + 1, k) == LAMP_FLICKER and _h01(n, k, 31) < 0.45:
			_died[(n + 1) * 2 + k] = _t + 1.2 + _rng.randf() * 1.5
			break


## Footsteps coming up the stair from four floors below.
func start_steps() -> void:
	_steps = {"u": float(base) + 4.2, "t": _t + 0.3, "n": 0}


## A door slamming on storey n (below you).
func slam(n: int) -> void:
	var j := n - base
	var p := _at(j, Vector3(DOOR_X, 0.3, 1.1))
	_play_at(_streams.get("door_slam"), p, 2.0, randf_range(0.96, 1.03), 9.0)
	shake(0.006, 0.7)
	for k in 2:
		_flick[n * 2 + k] = _t + 0.5


func _update_events(delta: float) -> void:
	_flick_snd_t = minf(_flick_snd_t, _t + 1.0)
	for i in range(_slam_queue.size() - 1, -1, -1):
		var q: Array = _slam_queue[i]
		if _t >= float(q[0]):
			_slam_queue.remove_at(i)
			if int(q[1]) - base >= 2:
				slam(int(q[1]))
	for key in _died.keys():
		var t0 := float(_died[key])
		if t0 > _t - delta and t0 <= _t:
			var n := int(key) / 2
			var k := int(key) % 2
			var j := n - base
			if j >= J0 and j <= J1:
				_play_at(_streams.get("lamp_die"), _lamp_pos(j, k), -4.0)
	if not _steps.is_empty():
		var u_me := _u_of(player.global_position)
		# they climb a storey every 5.5 s, a step every 0.5 s, and stop a
		# flight and a half below you
		_steps.u = float(_steps.u) - delta / 5.5
		if float(_steps.u) - u_me < 1.6 or int(_steps.n) > 60:
			_steps = {}
		elif _t >= float(_steps.t):
			_steps.t = _t + 0.5 + _rng.randf() * 0.06
			_steps.n = int(_steps.n) + 1
			var p := route_point(float(_steps.u))
			_play_at(_pick("step_"), p, -9.0 + 2.0 * sin(float(_steps.n)), randf_range(0.94, 1.04), 3.0)


## Where you are along the stair, in storeys (landing n at n.0, the half
## landing below it at n.5), from a world position.
func _u_of(p: Vector3) -> float:
	return float(base) - (p.y - LEVEL_Y) / H


## The point at stair coordinate u (storeys, see _u_of) on the walking line
## down (Godot, as the stack stands now): across the landing to the west,
## down U2, across the half landing, down U1 to the next landing's east.
func route_point(u: float) -> Vector3:
	var n := floori(u)
	var f := u - n
	var xw := FW * 0.5
	var xe := SW - FW * 0.5
	var b: Vector3
	if f < 0.5:
		var k := f / 0.5
		b = Vector3(xw, lerpf(LM, LM + RUN, k), -H * 0.5 * k)
	else:
		var k := (f - 0.5) / 0.5
		b = Vector3(xe, lerpf(LM + RUN, LM, k), -H * 0.5 - H * 0.5 * k)
	return storey_point(n, b)


## The body cam's exposure: meters the light round you.
func _update_exposure(delta: float) -> void:
	var cam := player.camera.global_position
	var f := -player.camera.global_basis.z
	var l := 0.5 * _light_level(cam - Vector3(0, 0.9, 0)) + 0.5 * _light_level(cam + f * 2.5 - Vector3(0, 0.6, 0))
	if player.flashlight_on:
		# the torch on what it's pointing at (2000 cd: E / pi in engine units
		# 4.14 / d^2)
		var q := PhysicsRayQueryParameters3D.create(cam, cam + f * 12.0)
		q.exclude = [player.get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var d: float = cam.distance_to(hit.position) if not hit.is_empty() else 12.0
		l += 4.14 / maxf(d * d, 0.8)
	var target := clampf(1.2 / maxf(l, 0.002), 0.45, 14.0)
	var rate := 0.7 if target > _ae else 3.0
	_ae = lerpf(_ae, target, 1.0 - exp(-delta * rate))
	if _ae_snap:
		_ae = target
		_ae_snap = false
	environment.tonemap_exposure = _base_exposure * _ae


## B2's door shutting behind you on its closer: the sweep (eased, slowing),
## the latch speed's last few degrees, the latch catching.
func _update_door(delta: float) -> void:
	if _door_t < 0.0:
		return
	_door_t += delta
	var a := -1.25
	if _door_t < 0.6:
		a = -1.25
	elif _door_t < 3.6:
		a = lerpf(-1.25, -0.16, smoothstep(0.0, 1.0, (_door_t - 0.6) / 3.0))
	elif _door_t < 4.3:
		a = lerpf(-0.16, 0.0, pow((_door_t - 3.6) / 0.7, 2.0))
	else:
		a = 0.0
		_door_t = -1.0
		_play_at(_streams.get("door_shut"), _exit_b2.global_position + Vector3(0, 1.0, 0), -2.0)
	(_exit_b2 as Object).call("set_open", a)


## A landing door: locked (Use it: the lever stops, the latch knocks).
func try_door(s: Slot) -> String:
	_play_at(_pick("rattle_"), s.root.global_position + Vector3(DOOR_X, 1.0, -0.05), -3.0)
	var n := s.n
	if n >= 30 and _h01(n, 5, 41) < 0.3:
		return "Locked. Something on the other side lets go of the handle."
	if n >= 14 and _h01(n, 5, 43) < 0.2:
		return "Locked. The vision panel is dark."
	return "Locked."


class _DoorUse:
	extends Node3D
	var level: Node
	var slot: RefCounted

	func _ready() -> void:
		add_to_group("usable")

	func use_targets(_p: Player) -> Array:
		if not visible:
			return []
		return [["door", global_position, "Try the door"]]

	func use(_id: String, _p: Player) -> String:
		return level.call("try_door", slot)


# --------------------------------------------------------------- harness ---

## yaw 0 faces into the shaft (north, Godot -Z), 90 west, 180 the door wall.
## (In slot 0: each shot's call puts storey n there first.)
func _view(_n: int, b: Vector3, yaw_deg: float, pitch := 0.0) -> Transform3D:
	var bas := Basis(Vector3.UP, deg_to_rad(yaw_deg)) * Basis(Vector3.RIGHT, pitch)
	return Transform3D(bas, _at(0, b))


func _at_storey(n: int) -> Callable:
	return func() -> void:
		_rebase(n, true)
		_deepest = maxi(_deepest, n)
		_ae_snap = true
		if OS.get_environment("SWDEBUG") != "":
			print("SWDEBUG storey %d water %s at %s level %.2f" % [n, _water.visible, _water.global_position, lamp_level(BOTTOM, 1)])


## Standing on storey n's landing by the guard, looking straight at the hand
## two floors down.
func _look_at_hand() -> Transform3D:
	# (back from the guard: the line passes under its rails, between the
	# balusters, over the landing's edge)
	var feet := _at(0, Vector3(DOOR_X, LM - 0.62, 0.0))
	var eye := feet + Vector3(0, Player.EYE, 0)
	_place_hand(0.0)
	var to := _hand.global_position + Vector3(0.08, 0.0, 0.0) - eye
	var yaw := atan2(-to.x, -to.z)
	var pitch := atan2(to.y, Vector2(to.x, to.z).length())
	return Transform3D(Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch), feet)


## The first storey from n down whose hand (two floors down) has its
## half-landing fixture burning.
func _hand_storey(n: int) -> int:
	for k in range(n, BOTTOM - 6):
		if lamp_kind(k + HAND_J, 1) == LAMP_ON and lamp_kind(k + HAND_J, 0) != LAMP_DEAD:
			return k
	return n


## The first storey from n down whose landing fixture is dead but the next
## floor's burn (the lights thinning: lit floors below a dark one).
func _dark_storey(n: int) -> int:
	for k in range(n, BOTTOM - 3):
		if lamp_kind(k, 0) == LAMP_DEAD and lamp_kind(k, 1) == LAMP_DEAD and lamp_kind(k + 1, 1) != LAMP_DEAD:
			return k
	return n


func shots() -> Array:
	var xe := SW - FW * 0.5
	var xw := FW * 0.5
	var out := [
		{"name": "arrival", "transform": _view(TOP, Vector3(DOOR_X, 0.85, 0.0), 22.0, -0.32), "call": _at_storey(TOP),
				"wait": 2.5},
		{"name": "b2_door", "transform": _view(TOP, Vector3(DOOR_X - 0.3, 1.25, 0.0), 175.0, -0.02), "call": _at_storey(TOP)},
		{"name": "down_flight", "transform": _view(4, Vector3(xw, LM - 0.2, 0.0), 0.0, -0.45), "call": _at_storey(4)},
		{"name": "half_landing", "transform": _view(4, Vector3(DOOR_X, LM + RUN + 0.7, -H * 0.5), 90.0, -0.2),
				"call": _at_storey(4)},
		{"name": "arrive_b14", "transform": _view(13, Vector3(xe, LM + 0.9, 0.3), 180.0, -0.25), "call": _at_storey(13),
				"wait": 2.0},
		{"name": "well_down", "transform": _view(9, Vector3(DOOR_X + 0.05, LM - 0.31, 0.0), 2.0, -1.42),
				"call": _at_storey(9), "wait": 2.5},
		{"name": "well_down2", "transform": _view(9, Vector3(DOOR_X, LM + RUN + 0.33, H * 0.5), 180.0, -1.25),
				"call": _at_storey(9), "wait": 2.0},
		{"name": "well_down3", "transform": _view(9, Vector3(SW - FW + 0.33, LM + 1.2, 0.33), 120.0, -1.1),
				"call": _at_storey(9), "wait": 2.0},
		{"name": "well_up", "transform": _view(9, Vector3(DOOR_X, LM - 0.35, 0.0), 0.0, 1.25), "call": _at_storey(9)},
		{"name": "hand", "transform": _look_at_hand(), "call": _at_storey(_hand_storey(9)), "wait": 2.0},
		{"name": "deep_dark", "transform": _view(34, Vector3(xw, LM - 0.2, 0.0), 0.0, -0.4),
				"call": _at_storey(_dark_storey(30)), "wait": 3.0},
		{"name": "deep_torch", "transform": _view(40, Vector3(xw, LM - 0.2, 0.0), 0.0, -0.4), "call": _at_storey(40),
				"flashlight": true, "wait": 3.0},
		{"name": "b112", "transform": _view(46, Vector3(xe, LM + 0.9, 0.3), 180.0, -0.25), "call": _at_storey(46),
				"flashlight": true, "wait": 2.5},
		{"name": "water", "transform": _view(BOTTOM, Vector3(xe - 0.15, LM + RUN + 0.35, H * 0.5), 180.0, -0.42),
				"call": _at_storey(BOTTOM), "flashlight": false, "wait": 3.0},
		{"name": "water_torch", "transform": _view(BOTTOM, Vector3(xe - 0.15, LM + RUN + 0.35, H * 0.5), 180.0, -0.42),
				"call": _at_storey(BOTTOM), "flashlight": true, "wait": 3.0},
	]
	return out


# ------------------------------------------------------------------ film ---

## Film: B2, the door shutting behind you; down a few flights; B12, then
## B14; at the guard, looking down the well: the hand, two floors down;
## footsteps coming up; deeper, the lights thinning, a door slamming below,
## the torch; B47, B112; the bottom, the stair going down into the water.
func film() -> void:
	print("FILM_START frame %d" % Engine.get_frames_drawn())
	_events = true
	player.set_flashlight(false)
	_fade_layer()
	# B2
	goto_storey(TOP, Vector3(DOOR_X, 0.85, 0.0), 0.0)
	_door_t = 0.0
	(_exit_b2 as Object).call("set_open", -1.25)
	await _fade_to(0.0, 0.8)
	await _wait(1.6)
	await _turn_to(PI, -0.06, 1.4)
	await _wait(1.6)
	await _turn_to(0.15, -0.2, 1.2)
	await _walk_down(1.6)
	await _fade_to(1.0, 0.4)
	# B11 -> B12 -> "B14"
	goto_storey(11, Vector3(SW - FW / 2 - 0.05, LM - 0.45, 0.0), PI * 0.5)
	await _fade_to(0.0, 0.4)
	await _walk_down(1.92)
	await _turn_to(PI, -0.3, 0.8)
	await _wait(1.6)
	await _fade_to(1.0, 0.4)
	# the guard, the well, the hand two floors down; footsteps coming up
	goto_storey(_hand_storey(18), Vector3(DOOR_X, LM - 0.62, 0.0), 0.3)
	_hand_state = 0
	_stare = 0.0
	await _fade_to(0.0, 0.4)
	var hx := _look_at_hand()
	await _turn_to(_yaw_of(hx), _pitch_of(hx), 2.0)
	start_steps()
	await _wait(4.5)
	await _turn_to(0.2, -0.3, 1.2)
	await _fade_to(1.0, 0.4)
	# B31: lights thinning, a door slams below, the torch
	goto_storey(31, Vector3(SW - FW / 2 - 0.05, LM - 0.45, 0.0), PI * 0.5)
	await _fade_to(0.0, 0.4)
	await _walk_down(0.45)
	slam(base + 3)
	await _wait(1.4)
	player.set_flashlight(true)
	await _walk_down(0.5)
	await _fade_to(1.0, 0.4)
	# B44 -> "B47" -> "B112"
	goto_storey(44, Vector3(SW - FW / 2 - 0.05, LM - 0.45, 0.0), PI * 0.5)
	await _fade_to(0.0, 0.4)
	await _walk_down(1.92)
	await _turn_to(PI, -0.3, 0.6)
	await _wait(1.3)
	await _fade_to(1.0, 0.4)
	# the bottom: down to the water, and into it (the exit itself is the
	# flooded basement: the film stops on the threshold)
	player.set_flashlight(false)
	film_hold_exit = true
	goto_storey(BOTTOM - 1, Vector3(SW - FW / 2 - 0.05, LM - 0.45, 0.0), PI * 0.5)
	await _fade_to(0.0, 0.5)
	await _walk_down(0.5)
	await _turn_to(PI - 0.25, -0.42, 1.4)
	await _wait(1.8)
	player.set_flashlight(true)
	await _walk_down(0.34)
	await _turn_to(PI, -0.55, 1.0)
	await _wait(2.0)
	await _fade_to(1.0, 1.0)
	film_hold_exit = false


func _fade_layer() -> void:
	if _fade:
		return
	var layer := CanvasLayer.new()
	layer.layer = 50
	add_child(layer)
	_fade = ColorRect.new()
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.color = Color(0, 0, 0, 1)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


func _fade_to(a: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", a, time)
	await tw.finished


func _wait(s: float) -> void:
	await get_tree().create_timer(s).timeout


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


## Walks down the stair (the player's own physics, a walker steering along
## the route) for `storeys` storeys.
func _walk_down(storeys: float) -> void:
	var u0 := _u_of(player.global_position)
	var goal := u0 + storeys
	var t := 0.0
	Input.action_press("move_forward")
	while _u_of(player.global_position) < goal and t < storeys * 9.0 + 3.0 and not _done:
		var to := walk_target(1) - player.global_position
		var want := atan2(-to.x, -to.z)
		player.yaw = lerp_angle(player.yaw, want, 0.12)
		player.pitch = lerpf(player.pitch, -0.28, 0.05)
		player._apply_rotation()
		t += get_process_delta_time()
		await get_tree().process_frame
	Input.action_release("move_forward")
