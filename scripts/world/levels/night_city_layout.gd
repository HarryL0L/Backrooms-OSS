extends RefCounted
## The Blue Hour's plan (night_city_level.gd builds it, tools/lucid/city_bake.gd
## bakes it): one crossing of an avenue and a street in an endless city,
## the six-storey brick building on its south-east corner whose roof you
## arrive on, the fire stair down its alley, and the city round it to the
## horizon. Everything here is deterministic (the bake must match), in
## level space: metres, ground at y = 0 at the crossing's centre, X east,
## Z south (Godot's -Z is north). Real sizes and their sources: SPEC.md.

## Floor to floor: the shop floor, then the upper storeys.
const G0 := 4.5
const ST := 3.6
## Building A (yours): x 15..45, z 10..40, roof at G0 + 5 ST.
const A_ROOF := 22.5
const PARAPET := 1.1
const WALK := 0.15
## The fire stair: storey levels from the alley (on the sidewalk's level).
const STAIR_Y := [0.15, 4.5, 8.1, 11.7, 15.3, 18.9, 22.5]
const STAIR_X := Vector2(45.0, 47.5)
const LAND_A := Vector2(12.4, 13.6)     # z of the landings by the street
const LAND_B := Vector2(16.6, 17.8)     # z of the half landings
## Where you may go (the barricades close the rest of the crossing).
const BOUND := Rect2(-86.0, -61.0, 172.0, 122.0)
## The failing sodium lamp (cycles off and on like an old HPS lamp).
const FAILING := Vector3(55.0, 8.0, 5.1)
## The river and its bridge, the elevated road, the two tower clusters.
const RIVER := Vector2(-1700.0, -1450.0)
const BRIDGE_Z := -400.0
const VIADUCT_X := 385.0
const DOWNTOWN := [Vector3(-2350.0, 0.0, -650.0), Vector3(700.0, 0.0, -1350.0)]

## Baked geometry: tile -> {material name -> LucidCity.Surf}.
var tiles := {}
## Collision and bake occluders: {size, xf, meta (gather info), solid
## (collides at run time), occluder (in the bake)}.
var colliders := []
## Walkable ground for run-time collision (triangles, level space).
var ground := PackedVector3Array()
## Lamps in the bake: switchable ones (idx >= 0) and steady ones further out.
var lamps := []
## The backdrop: buildings (LucidCity.block_multimesh entries), lamp
## models within reach, point lights.
var blocks := []
var lamp_models := []
var points := []
## Signal heads at the crossing: {pos, normal, set ("avenue"/"street"/"ped_a"/"ped_s")}.
var heads := []
## Exits and named places (level-space transforms).
var spots := {}
## Material definitions by name (see night_city_level.gd _materials()).
var mats := {}

var _geo := true


## Builds the plan. geometry = false skips the tessellated surfaces (the
## level loads them baked) and keeps everything else.
func build(geometry := true) -> void:
	_geo = geometry
	_define_materials()
	_street()
	_buildings()
	_building_a()
	_stair()
	_roof()
	_crossing_furniture()
	_lamps()
	_backdrop()


func surf(tile: String, mat: String) -> LucidCity.Surf:
	if not tiles.has(tile):
		tiles[tile] = {}
	if not tiles[tile].has(mat):
		tiles[tile][mat] = LucidCity.Surf.new()
	return tiles[tile][mat]


func _col(size: Vector3, pos: Vector3, meta := {}, solid := true, occluder := true, yaw := 0.0) -> void:
	colliders.append({"size": size, "xf": Transform3D(Basis(Vector3.UP, yaw), pos), "meta": meta,
			"solid": solid, "occluder": occluder})


func _col_xf(size: Vector3, xf: Transform3D, meta := {}, solid := true, occluder := true) -> void:
	colliders.append({"size": size, "xf": xf, "meta": meta, "solid": solid, "occluder": occluder})


# --------------------------------------------------------------- materials ---

func _define_materials() -> void:
	# Albedos (linear, the surface's mean): SPEC.md. tex: a texture set in
	# assets/levels/night_city/textures; uv: metres per repeat.
	mats = {
		"road": {"albedo": Color(0.094, 0.086, 0.068), "tex": "asphalt", "uv": 3.0, "rough": 0.55, "gloss": 0.5, "paint": true, "normal": 0.6},
		"alley": {"albedo": Color(0.085, 0.08, 0.07), "tex": "asphalt", "uv": 2.5, "rough": 0.7, "gloss": 0.25},
		"walk": {"albedo": Color(0.30, 0.295, 0.28), "tex": "concrete", "uv": 1.6, "rough": 0.8, "normal": 0.5},
		"curb": {"albedo": Color(0.36, 0.35, 0.33), "tex": "concrete", "uv": 1.0, "rough": 0.7},
		"plaza": {"albedo": Color(0.33, 0.32, 0.30), "tex": "facade_concrete", "uv": 1.2, "rough": 0.6, "gloss": 0.2},
		"roof": {"albedo": Color(0.30, 0.30, 0.29), "tex": "concrete", "uv": 1.2, "rough": 0.85, "normal": 0.6},
		"coping": {"albedo": Color(0.38, 0.37, 0.35), "tex": "concrete", "uv": 0.8, "rough": 0.75},
		"stucco": {"albedo": Color(0.40, 0.39, 0.36), "tex": "facade_concrete", "uv": 2.0, "rough": 0.85},
		"steel": {"albedo": Color(0.07, 0.075, 0.075), "rough": 0.5, "spec": 0.5},
		"steel_light": {"albedo": Color(0.32, 0.33, 0.33), "rough": 0.4, "spec": 0.6},
		"door": {"albedo": Color(0.16, 0.19, 0.2), "rough": 0.45, "spec": 0.5},
		"pole": {"albedo": Color(0.20, 0.21, 0.21), "rough": 0.45, "spec": 0.5},
		"housing": {"albedo": Color(0.30, 0.31, 0.31), "rough": 0.5},
		"signal": {"albedo": Color(0.05, 0.05, 0.04), "rough": 0.5},
		"wood": {"albedo": Color(0.16, 0.11, 0.07), "rough": 0.9},
		"ply": {"albedo": Color(0.28, 0.21, 0.13), "rough": 0.85},
		"barrier": {"albedo": Color(0.55, 0.22, 0.04), "rough": 0.6},
		"barrier_w": {"albedo": Color(0.62, 0.62, 0.6), "rough": 0.5},
		"dumpster": {"albedo": Color(0.035, 0.07, 0.045), "rough": 0.6},
		"hydrant": {"albedo": Color(0.32, 0.04, 0.03), "rough": 0.5},
		"black": {"albedo": Color(0.03, 0.03, 0.03), "rough": 0.6},
		# Facades: windows from lucid_windows (seed, kind, storey, bay), shop band.
		"A_wall": {"albedo": Color(0.33, 0.19, 0.11), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(11, 2, ST, 2.6), "shop": G0, "normal": 0.8, "top": A_ROOF},
		"A_side": {"albedo": Color(0.33, 0.19, 0.11), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(12, 2, ST, 3.9), "shop": 0.0, "normal": 0.8, "top": A_ROOF},
		"brick": {"albedo": Color(0.33, 0.19, 0.11), "tex": "brick", "uv": 2.4, "rough": 0.85, "normal": 0.8},
		"A2_wall": {"albedo": Color(0.36, 0.34, 0.30), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(13, 0, ST, 3.0), "shop": 0.0},
		"B_wall": {"albedo": Color(0.40, 0.38, 0.34), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(21, 0, ST, 3.0), "shop": G0},
		"B_side": {"albedo": Color(0.40, 0.38, 0.34), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(22, 0, ST, 4.2), "shop": 0.0},
		"C1_wall": {"albedo": Color(0.08, 0.09, 0.10), "rough": 0.4, "facade": Vector4(31, 1, 4.2, 1.5), "shop": G0, "spec": 0.6},
		"C2_wall": {"albedo": Color(0.30, 0.20, 0.14), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(32, 2, 3.5, 2.6), "shop": G0},
		"D1_wall": {"albedo": Color(0.42, 0.27, 0.17), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(41, 2, ST, 2.6), "shop": G0},
		"D2_wall": {"albedo": Color(0.45, 0.44, 0.41), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(42, 0, 3.1, 3.0), "shop": G0},
		"E1_wall": {"albedo": Color(0.07, 0.08, 0.09), "rough": 0.35, "facade": Vector4(51, 1, 4.1, 1.5), "shop": 8.2, "spec": 0.6},
		"E2_wall": {"albedo": Color(0.38, 0.36, 0.33), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(52, 0, 3.2, 3.0), "shop": G0},
		"roof_far": {"albedo": Color(0.14, 0.14, 0.14), "rough": 0.9},
		# Emitters (cd/m2 set by the level from Lucid.FIXTURES).
		"lens_led": {"albedo": Color(0.3, 0.3, 0.3), "emit": "led_street_100w"},
		"lens_na": {"albedo": Color(0.3, 0.3, 0.3), "emit": "sodium_hps_150w"},
		"lens_na_failing": {"albedo": Color(0.3, 0.3, 0.3), "emit": "sodium_hps_150w"},
		"bulb": {"albedo": Color(0.5, 0.5, 0.5), "emit": "jelly_jar_60w"},
	}
	for set_name in ["avenue", "street"]:
		for c in ["r", "y", "g"]:
			mats["sig_%s_%s" % [set_name, c]] = {"albedo": Color(0.04, 0.04, 0.04), "rough": 0.3, "signal": true}
	for set_name in ["ped_a", "ped_s"]:
		for c in ["hand", "walk"]:
			mats["%s_%s" % [set_name, c]] = {"albedo": Color(0.03, 0.03, 0.03), "rough": 0.3, "signal": true}


# ------------------------------------------------------------------ street ---

## The two carriageways, the four sidewalk corners with their curbs, the
## plaza and the alley; ground collision with ramps for the curbs.
func _street() -> void:
	var rx := 95.0                       # street: to the next avenues' building lines
	var rz := 70.0                       # avenue: to the next streets' building lines
	var walks := []
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := LucidCity.corner_walk(0.0, 0.0, sx, sz, rx, rz)
			walks.append(c)
	var cross := PackedVector2Array([Vector2(-15, -rz), Vector2(15, -rz), Vector2(15, -10), Vector2(rx, -10),
			Vector2(rx, 10), Vector2(15, 10), Vector2(15, rz), Vector2(-15, rz), Vector2(-15, 10),
			Vector2(-rx, 10), Vector2(-rx, -10), Vector2(-15, -10)])
	var minus := []
	for w in walks:
		minus.append(w[0])
	if _geo:
		surf("street", "road").poly(cross, 0.0, 1.25, minus)
		for w in walks:
			surf("street", "walk").poly(w[0], WALK, 1.0)
			_curb(w[1], w[0])
		# The plaza in front of the tower (south-west corner of the block
		# north-west of the crossing).
		surf("street", "plaza").poly(PackedVector2Array([Vector2(-70, -25), Vector2(-30, -25), Vector2(-30, -70),
				Vector2(-15, -70), Vector2(-15, -10), Vector2(-70, -10)]), WALK, 1.5)
		# The alley beside A, to the hoarding at z = 46.
		surf("a", "alley").poly(PackedVector2Array([Vector2(45, 10), Vector2(51, 10), Vector2(51, 46), Vector2(45, 46)]), WALK, 1.0)
	# Collision: the road plane, the sidewalks raised, their curbs as
	# 0.4 m ramps (a 150 mm step would stop the capsule).
	_tri_quad(Vector3(-200, 0, -200), Vector3(400, 0, 0), Vector3(0, 0, 400))
	for w in walks:
		_walk_collision(w[0], w[1])
	for pl in [PackedVector2Array([Vector2(-70, -25), Vector2(-30, -25), Vector2(-30, -70), Vector2(-15, -70), Vector2(-15, -10), Vector2(-70, -10)]),
			PackedVector2Array([Vector2(45, 10), Vector2(51, 10), Vector2(51, 46), Vector2(45, 46)])]:
		_flat_collision(pl, WALK + 0.002)
	colliders.append({"size": Vector3(400, 1, 400), "xf": Transform3D(Basis(), Vector3(0, -0.5, 0)),
			"meta": {"albedo": 0.09}, "solid": false, "occluder": true})
	# The ends of the sidewalks (where the near ground meets the far).
	if _geo:
		for sx in [-1.0, 1.0]:
			surf("street", "curb").wall(Vector2(sx * rx, 6.0), Vector2(sx * rx, 10.0), 0.0, WALK, Vector3(sx, 0, 0), 2.0)
			surf("street", "curb").wall(Vector2(sx * rx, -10.0), Vector2(sx * rx, -6.0), 0.0, WALK, Vector3(sx, 0, 0), 2.0)
		for sz in [-1.0, 1.0]:
			surf("street", "curb").wall(Vector2(9.5, sz * rz), Vector2(15.0, sz * rz), 0.0, WALK, Vector3(0, 0, sz), 2.0)
			surf("street", "curb").wall(Vector2(-15.0, sz * rz), Vector2(-9.5, sz * rz), 0.0, WALK, Vector3(0, 0, sz), 2.0)


## Curb faces along a polyline, facing the road (away from `walk`).
func _curb(line: PackedVector2Array, walk: PackedVector2Array) -> void:
	var s := surf("street", "curb")
	for i in line.size() - 1:
		var nn := _road_side(line[i], line[i + 1], walk)
		s.wall(line[i], line[i + 1], 0.0, WALK, Vector3(nn.x, 0, nn.y), 1.0)


## The normal of segment a-b pointing out of the polygon `walk`.
func _road_side(a: Vector2, b: Vector2, walk: PackedVector2Array) -> Vector2:
	var d := (b - a).normalized()
	var nn := Vector2(d.y, -d.x)
	if Geometry2D.is_point_in_polygon((a + b) * 0.5 + nn * 0.2, walk):
		nn = -nn
	return nn


func _tri_quad(o: Vector3, a: Vector3, b: Vector3) -> void:
	ground.append_array([o, o + a, o + a + b, o, o + a + b, o + b])


func _flat_collision(pl: PackedVector2Array, y: float) -> void:
	var t := Geometry2D.triangulate_polygon(pl)
	for k in range(0, t.size(), 3):
		for m in 3:
			var p: Vector2 = pl[t[k + m]]
			ground.append(Vector3(p.x, y, p.y))


func _walk_collision(pl: PackedVector2Array, curb: PackedVector2Array) -> void:
	_flat_collision(pl, WALK)
	for i in curb.size() - 1:
		var a := curb[i]
		var b := curb[i + 1]
		var nn := _road_side(a, b, pl)
		var a2 := a + nn * 0.4
		var b2 := b + nn * 0.4
		ground.append_array([Vector3(a.x, WALK, a.y), Vector3(b.x, WALK, b.y), Vector3(b2.x, 0.0, b2.y),
				Vector3(a.x, WALK, a.y), Vector3(b2.x, 0.0, b2.y), Vector3(a2.x, 0.0, a2.y)])


# --------------------------------------------------------------- buildings ---

## A building of the crossing: box x0..x1, z0..z1, h high, its walls with
## `wall` (faces turned to the street) / `side` (the rest), the roof flat.
## `tile`: which bake tile. Steps: finer low down, where lamps light it.
func _block(tile: String, r: Rect2, h: float, wall: String, side: String, faces_street: Array, meta := {}) -> void:
	var x0 := r.position.x
	var z0 := r.position.y
	var x1 := r.end.x
	var z1 := r.end.y
	for mn in [wall, side]:
		if mats[mn].has("facade"):
			mats[mn]["top"] = h
	var m := meta.duplicate()
	if not m.has("albedo"):
		m.albedo = Lucid.lum(mats[wall].albedo)
	_col(Vector3(r.size.x, h, r.size.y), Vector3(r.get_center().x, h * 0.5, r.get_center().y), m)
	if not _geo:
		return
	var walls := [[Vector2(x1, z0), Vector2(x1, z1), Vector3.RIGHT], [Vector2(x0, z1), Vector2(x0, z0), Vector3.LEFT],
			[Vector2(x1, z1), Vector2(x0, z1), Vector3.BACK], [Vector2(x0, z0), Vector2(x1, z0), Vector3.FORWARD]]
	for i in 4:
		var w: Array = walls[i]
		var mat: String = wall if faces_street[i] else side
		var s := surf(tile, mat)
		var lo := minf(14.0, h)
		s.wall(w[0], w[1], 0.0, lo, w[2], 1.5)
		if h > lo:
			s.wall(w[0], w[1], lo, h, w[2], 4.0 if h < 60.0 else 8.0)
	surf(tile, "roof_far").quad(Vector3(x0, h, z0), Vector3(0, 0, z1 - z0), Vector3(x1 - x0, 0, 0), 6.0, Vector3.UP)


func _buildings() -> void:
	# Lit-window luminance (cd/m2) the bake's gather sees on each facade:
	# lit share x glazed share x window luminance (Lucid.FIXTURES).
	var home := Lucid.fixture_rgb(Lucid.FIXTURES.window_home) * (0.3 * 0.2 * 12.0)
	var home_b := home * (0.2 / 0.3)
	var office := Lucid.fixture_rgb(Lucid.FIXTURES.window_office) * (0.2 * 0.65 * 25.0)
	var office_b := office * (0.2 / 0.3)
	var shop := Lucid.fixture_rgb(Lucid.FIXTURES.shopfront) * (0.35 * 0.6 * 40.0)
	var hm := {"emit_a": home, "emit_b": home_b, "shop_h": G0, "shop_a": shop, "shop_b": shop}
	var om := {"emit_a": office, "emit_b": office_b, "shop_h": G0, "shop_a": shop, "shop_b": shop}
	# E W S N: which faces look onto the streets.
	_block("a", Rect2(15, 40, 30, 30), G0 + 3 * ST, "A2_wall", "A2_wall", [true, true, false, false], hm)
	_block("street", Rect2(51, 10, 44, 60), G0 + 8 * ST, "B_wall", "B_side", [false, false, false, true], hm)
	_block("street", Rect2(-45, 10, 30, 60), G0 + 11 * 4.2, "C1_wall", "C1_wall", [true, false, false, true], om)
	_block("street", Rect2(-95, 10, 50, 60), G0 + 4 * 3.5, "C2_wall", "C2_wall", [false, false, false, true], hm)
	_block("street", Rect2(15, -70, 40, 60), G0 + 4 * ST, "D1_wall", "D1_wall", [false, true, true, false], hm)
	_block("street", Rect2(55, -70, 40, 60), G0 + 7 * 3.1, "D2_wall", "D2_wall", [false, false, true, false], hm)
	_block("street", Rect2(-70, -65, 40, 40), 8.2 + 37 * 4.1, "E1_wall", "E1_wall", [true, false, true, false], om)
	_block("street", Rect2(-95, -70, 25, 60), G0 + 5 * 3.2, "E2_wall", "E2_wall", [true, false, true, false], hm)
	_block("street", Rect2(-70, -70, 40, 5), 6.0, "stucco", "stucco", [false, false, true, false])
	_block("street", Rect2(-30, -70, 15, 1), 2.0, "stucco", "stucco", [false, false, false, false])
	spots.tower_top = Vector3(-50, 8.2 + 37 * 4.1, -45)


## Building A: the brick walls (shops on the avenue and the street, the
## alley wall plain), the parapet and its coping, the street door you can
## leave by.
func _building_a() -> void:
	var home := Lucid.fixture_rgb(Lucid.FIXTURES.window_home) * (0.3 * 0.2 * 12.0)
	var shop := Lucid.fixture_rgb(Lucid.FIXTURES.shopfront) * (0.35 * 0.6 * 40.0)
	var meta := {"albedo": 0.21, "emit_a": home, "emit_b": home * 0.63, "shop_h": G0, "shop_a": shop, "shop_b": shop}
	_col(Vector3(30, A_ROOF, 30), Vector3(30, A_ROOF * 0.5, 25), meta)
	if _geo:
		var s := surf("a", "A_wall")
		for w in [[Vector2(15, 40), Vector2(15, 10), Vector3.LEFT], [Vector2(15, 10), Vector2(45, 10), Vector3.FORWARD]]:
			s.wall(w[0], w[1], 0.0, 14.0, w[2], 1.2)
			s.wall(w[0], w[1], 14.0, A_ROOF + PARAPET, w[2], 2.5)
		var si := surf("a", "A_side")
		si.wall(Vector2(45, 10), Vector2(45, 40), 0.0, 14.0, Vector3.RIGHT, 1.2)
		si.wall(Vector2(45, 10), Vector2(45, 40), 14.0, A_ROOF + PARAPET, Vector3.RIGHT, 2.5)
		si.wall(Vector2(45, 40), Vector2(15, 40), G0 + 3 * ST, A_ROOF + PARAPET, Vector3.BACK, 3.0)
	# The parapet (0.3 m brick, 1.1 m over the roof) with a gap on the
	# alley side for the fire stair's top landing.
	var t := 0.3
	var y := A_ROOF + PARAPET * 0.5
	_parapet(Vector3(30, y, 10 + t * 0.5), Vector3(30, PARAPET, t))
	_parapet(Vector3(30, y, 40 - t * 0.5), Vector3(30, PARAPET, t))
	_parapet(Vector3(15 + t * 0.5, y, 25), Vector3(t, PARAPET, 30 - 2 * t))
	var g0 := LAND_A.x
	var g1 := LAND_A.y
	_parapet(Vector3(45 - t * 0.5, y, (10 + t + g0) * 0.5), Vector3(t, PARAPET, g0 - 10 - t))
	_parapet(Vector3(45 - t * 0.5, y, (g1 + 40 - t) * 0.5), Vector3(t, PARAPET, 40 - t - g1))
	# The street door (residents' entrance on the avenue), recessed 0.3 m.
	if _geo:
		var d := surf("a", "door")
		d.quad(Vector3(14.99, WALK, 33.0), Vector3(0, 0, 1.8), Vector3(0, 2.3, 0), 0.6, Vector3.LEFT)
		surf("a", "steel_light").box(Vector3(14.95, WALK + 2.45, 33.9), Vector3(0.12, 0.12, 2.2), 1.0)
	spots.street_door = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(14.98, WALK, 33.9))


func _parapet(c: Vector3, s: Vector3) -> void:
	_col(s, c, {"albedo": 0.21})
	if not _geo:
		return
	var inner := surf("a", "brick")
	var h := s * 0.5
	# Faces turned to the roof (the outer faces are the walls above).
	if s.x < s.z:
		var sign_x := 1.0 if c.x < 30.0 else -1.0
		inner.wall(Vector2(c.x + sign_x * h.x, c.z - h.z), Vector2(c.x + sign_x * h.x, c.z + h.z), A_ROOF, A_ROOF + PARAPET,
				Vector3(sign_x, 0, 0), 1.0)
	else:
		var sign_z := 1.0 if c.z < 25.0 else -1.0
		inner.wall(Vector2(c.x - h.x, c.z + sign_z * h.z), Vector2(c.x + h.x, c.z + sign_z * h.z), A_ROOF, A_ROOF + PARAPET,
				Vector3(0, 0, sign_z), 1.0)
	surf("a", "coping").box(c + Vector3(0, h.y + 0.03, 0), Vector3(s.x + 0.06, 0.06, s.z + 0.06), 1.0,
			[true, true, true, false, true, true])


# ------------------------------------------------------------------- stair ---

## The fire stair in the alley: steel switchback flights up A's east wall,
## two flights a storey (out along the outer lane, back on the inner),
## grating landings, rails 1.07 m high. Collision: a ramp per flight.
func _stair() -> void:
	var xo := Vector2(46.35, 47.45)      # outer lane
	var xi := Vector2(45.1, 46.25)       # inner lane
	var steel := "steel"
	for k in STAIR_Y.size() - 1:
		var y0: float = STAIR_Y[k]
		var y1: float = STAIR_Y[k + 1]
		var hm := (y0 + y1) * 0.5
		_flight(xo, LAND_A.y, LAND_B.x, y0, hm)
		_flight(xi, LAND_B.x, LAND_A.y, hm, y1)
		# Landings (grating plate 50 mm) at the half and the top.
		_landing(Vector3((STAIR_X.x + STAIR_X.y) * 0.5, hm, (LAND_B.x + LAND_B.y) * 0.5), Vector3(STAIR_X.y - STAIR_X.x, 0.05, LAND_B.y - LAND_B.x))
		_landing(Vector3((STAIR_X.x + STAIR_X.y) * 0.5, y1, (LAND_A.x + LAND_A.y) * 0.5), Vector3(STAIR_X.y - STAIR_X.x, 0.05, LAND_A.y - LAND_A.x))
		# Rails: the outer side and the landings' ends; the lanes split.
		_rail(Vector3(STAIR_X.y + 0.02, y0, LAND_A.x), Vector3(STAIR_X.y + 0.02, y1, LAND_B.y), y0, y1, hm)
		_rail_ends(y1, hm)
		_col(Vector3(0.1, y1 - y0 + 1.2, LAND_B.x - LAND_A.y), Vector3(46.3, (y0 + y1) * 0.5 + 0.6, (LAND_A.y + LAND_B.x) * 0.5),
				{}, true, false)
		if _geo:
			surf("a", steel).box(Vector3(46.3, (y0 + hm) * 0.5 + 0.55, (LAND_A.y + LAND_B.x) * 0.5),
					Vector3(0.04, 0.04, LAND_B.x - LAND_A.y), 1.0)
	# A post at each corner, alley floor to the roof.
	if _geo:
		for z in [LAND_A.x, LAND_B.y]:
			surf("a", steel).box(Vector3(STAIR_X.y, (STAIR_Y[0] + A_ROOF + 1.1) * 0.5, z), Vector3(0.1, A_ROOF + 1.1, 0.1), 3.0)
	# Nothing to walk under at the bottom of the first flight.
	_col(Vector3(xo.y - xo.x, 1.0, LAND_B.x - LAND_A.y), Vector3((xo.x + xo.y) * 0.5, 0.5, (LAND_A.y + LAND_B.x) * 0.5),
			{}, true, false)
	# The landing bulbs (caged 60 W jelly jars on A's wall), one a storey.
	for k in range(1, STAIR_Y.size()):
		var y: float = STAIR_Y[k] + 2.3
		lamps.append({"pos": Vector3(45.12, y, 13.0), "fx": "jelly_jar_60w", "llf": 1.0, "bulb": true})
		if _geo:
			_bulb(Vector3(45.12, y, 13.0))
	lamps.append({"pos": Vector3(45.12, 2.6, 18.2), "fx": "jelly_jar_60w", "llf": 1.0, "bulb": true})
	if _geo:
		_bulb(Vector3(45.12, 2.6, 18.2))
	# The alley's end: a plywood hoarding, 2.4 m; a dumpster, bags.
	_col(Vector3(6, 2.4, 0.1), Vector3(48, 1.35, 46.0), {"albedo": 0.2})
	_col(Vector3(1.8, 1.3, 1.1), Vector3(49.9, 0.8, 32.0), {"albedo": 0.06})
	if _geo:
		surf("a", "ply").box(Vector3(48, 1.35, 46.0), Vector3(6, 2.4, 0.06), 1.2)
		for i in 4:
			surf("a", "wood").box(Vector3(45.6 + i * 1.6, 1.35, 46.06), Vector3(0.09, 2.4, 0.09), 1.2)
		surf("a", "dumpster").box(Vector3(49.9, 0.8, 32.0), Vector3(1.8, 1.3, 1.1), 0.6)
		surf("a", "black").box_rot(Vector3(49.6, 0.45, 34.2), Vector3(0.7, 0.6, 0.6), 0.4, 0.5)
		surf("a", "black").box_rot(Vector3(50.3, 0.4, 34.9), Vector3(0.6, 0.5, 0.6), 1.1, 0.5)
	spots.stair_top = Vector3(46.3, A_ROOF, 13.0)


func _flight(x: Vector2, za: float, zb: float, ya: float, yb: float) -> void:
	var run := absf(zb - za)
	var rise := yb - ya
	var n := maxi(roundi(rise / 0.18), 2)
	var dz := (zb - za) / n
	if _geo:
		var s := surf("a", "steel")
		for i in n:
			var z := za + dz * (i + 0.5)
			s.box(Vector3((x.x + x.y) * 0.5, ya + rise * (i + 1) / n - 0.02, z), Vector3(x.y - x.x, 0.04, absf(dz) + 0.02), 2.0)
		# Stringers.
		for xs in [x.x, x.y]:
			var mid := Vector3(xs, (ya + yb) * 0.5 + 0.05, (za + zb) * 0.5)
			var len := sqrt(run * run + rise * rise)
			_beam(s, Transform3D(Basis(Vector3.RIGHT, -atan2(rise, zb - za)), mid), Vector3(0.02, 0.22, len))
	var xf := Transform3D(Basis(Vector3.RIGHT, -atan2(rise, zb - za)), Vector3((x.x + x.y) * 0.5, (ya + yb) * 0.5 - 0.04, (za + zb) * 0.5))
	# (Grating: it lets most light through, so it is no occluder.)
	_col_xf(Vector3(x.y - x.x, 0.08, sqrt(run * run + rise * rise)), xf, {"albedo": 0.08}, true, false)


func _beam(s: LucidCity.Surf, xf: Transform3D, size: Vector3) -> void:
	var h := size * 0.5
	var b := xf.basis
	var o := xf.origin - b.x * h.x - b.y * h.y - b.z * h.z
	s.quad(o + b.x * size.x, b.z * size.z, b.y * size.y, 2.0, b.x)
	s.quad(o, b.z * size.z, b.y * size.y, 2.0, -b.x)
	s.quad(o + b.y * size.y, b.x * size.x, b.z * size.z, 2.0, b.y)


func _landing(c: Vector3, s: Vector3) -> void:
	_col(Vector3(s.x, 0.1, s.z), c - Vector3(0, 0.05, 0), {"albedo": 0.08})
	if _geo:
		surf("a", "steel").box(c - Vector3(0, 0.025, 0), s, 1.0, [true, true, true, true, true, true])


func _rail(_a: Vector3, _b: Vector3, y0: float, y1: float, _hm: float) -> void:
	var x := STAIR_X.y + 0.02
	_col(Vector3(0.06, y1 - y0 + 1.3, LAND_B.y - LAND_A.x), Vector3(x, (y0 + y1) * 0.5 + 0.65, (LAND_A.x + LAND_B.y) * 0.5),
			{}, true, false)
	if _geo:
		var s := surf("a", "steel")
		# Top rail following each flight and the landings, and balusters.
		var hm := (y0 + y1) * 0.5
		s.box(Vector3(x, hm + 1.07, (LAND_B.x + LAND_B.y) * 0.5), Vector3(0.04, 0.04, LAND_B.y - LAND_B.x), 1.0)
		s.box(Vector3(x, y1 + 1.07, (LAND_A.x + LAND_A.y) * 0.5), Vector3(0.04, 0.04, LAND_A.y - LAND_A.x), 1.0)
		var len := sqrt(pow(LAND_B.x - LAND_A.y, 2.0) + pow(hm - y0, 2.0))
		var b := Basis(Vector3.RIGHT, -atan2(hm - y0, LAND_B.x - LAND_A.y))
		_beam(s, Transform3D(b, Vector3(x, (y0 + hm) * 0.5 + 1.07, (LAND_A.y + LAND_B.x) * 0.5)), Vector3(0.04, 0.04, len))
		for i in 7:
			var z := LAND_A.y + (LAND_B.x - LAND_A.y) * (i + 0.5) / 7.0
			var yb := y0 + (hm - y0) * (i + 0.5) / 7.0
			s.box(Vector3(x, yb + 0.53, z), Vector3(0.02, 1.07, 0.02), 2.0, [true, true, false, false, true, true])


func _rail_ends(y1: float, hm: float) -> void:
	# The half landing's far end, and the top landing's street end.
	_col(Vector3(STAIR_X.y - STAIR_X.x, 1.2, 0.06), Vector3((STAIR_X.x + STAIR_X.y) * 0.5, hm + 0.6, LAND_B.y + 0.02), {}, true, false)
	_col(Vector3(STAIR_X.y - STAIR_X.x, 1.2, 0.06), Vector3((STAIR_X.x + STAIR_X.y) * 0.5, y1 + 0.6, LAND_A.x - 0.02), {}, true, false)
	if _geo:
		var s := surf("a", "steel")
		s.box(Vector3((STAIR_X.x + STAIR_X.y) * 0.5, hm + 1.07, LAND_B.y + 0.02), Vector3(STAIR_X.y - STAIR_X.x, 0.04, 0.04), 1.0)
		s.box(Vector3((STAIR_X.x + STAIR_X.y) * 0.5, y1 + 1.07, LAND_A.x - 0.02), Vector3(STAIR_X.y - STAIR_X.x, 0.04, 0.04), 1.0)
		for i in 5:
			var x := STAIR_X.x + (STAIR_X.y - STAIR_X.x) * (i + 0.5) / 5.0
			s.box(Vector3(x, hm + 0.53, LAND_B.y + 0.02), Vector3(0.02, 1.07, 0.02), 2.0, [true, true, false, false, true, true])
			s.box(Vector3(x, y1 + 0.53, LAND_A.x - 0.02), Vector3(0.02, 1.07, 0.02), 2.0, [true, true, false, false, true, true])


func _bulb(p: Vector3) -> void:
	surf("a", "steel").box(p + Vector3(0.05, 0.12, 0), Vector3(0.1, 0.06, 0.14), 0.5)
	surf("a", "bulb").box(p - Vector3(-0.08, 0.02, 0), Vector3(0.11, 0.16, 0.11), 0.5, [true, true, false, true, true, true])


# -------------------------------------------------------------------- roof ---

## A's roof: the membrane, the stair bulkhead with the door you came out
## of and its bulb, a timber water tank on its steel stand, condensers,
## vent stacks.
func _roof() -> void:
	if _geo:
		surf("a", "roof").quad(Vector3(15.3, A_ROOF, 10.3), Vector3(0, 0, 29.4), Vector3(29.4, 0, 0), 1.2, Vector3.UP)
	# Bulkhead: 5 x 5 m, 3 m high; the door in its west face.
	var bh := Rect2(34, 31, 5, 5)
	_col(Vector3(5, 3.0, 5), Vector3(36.5, A_ROOF + 1.5, 33.5), {"albedo": 0.38})
	if _geo:
		var s := surf("a", "stucco")
		s.box(Vector3(bh.get_center().x, A_ROOF + 1.5, bh.get_center().y), Vector3(5, 3, 5), 0.8)
		surf("a", "coping").box(Vector3(36.5, A_ROOF + 3.04, 33.5), Vector3(5.1, 0.08, 5.1), 1.0)
		surf("a", "door").quad(Vector3(33.99, A_ROOF, 33.05), Vector3(0, 0, 0.92), Vector3(0, 2.05, 0), 0.5, Vector3.LEFT)
		surf("a", "steel_light").box(Vector3(33.97, A_ROOF + 1.05, 33.85), Vector3(0.04, 0.04, 0.6), 0.5)
		_bulb(Vector3(33.88, A_ROOF + 2.45, 33.5))
		surf("a", "steel").box(Vector3(33.95, A_ROOF + 2.12, 33.51), Vector3(0.1, 0.06, 1.1), 0.5)
	lamps.append({"pos": Vector3(33.8, A_ROOF + 2.43, 33.5), "fx": "jelly_jar_60w", "llf": 1.0, "bulb": true})
	spots.roof_door = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(33.98, A_ROOF, 33.51))
	spots.arrival = Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.1), Vector3(32.6, A_ROOF, 33.4))
	# Water tank: 4.6 m across, 4.2 m of staves on a 3.2 m steel stand.
	var tc := Vector3(41.6, A_ROOF, 37.0)
	_col(Vector3(4.2, 7.6, 4.2), tc + Vector3(0, 3.8, 0), {"albedo": 0.12})
	if _geo:
		surf("a", "wood").cyl(tc + Vector3(0, 3.2, 0), 2.3, 4.2, 16, 1.5)
		surf("a", "wood").cyl(tc + Vector3(0, 7.4, 0), 2.35, 0.25, 16, 1.0)
		var cone := surf("a", "wood")
		for i in 16:
			var a0 := TAU * i / 16.0
			var a1 := TAU * (i + 1) / 16.0
			var p0 := tc + Vector3(cos(a0) * 2.35, 7.65, sin(a0) * 2.35)
			var p1 := tc + Vector3(cos(a1) * 2.35, 7.65, sin(a1) * 2.35)
			var top := tc + Vector3(0, 8.6, 0)
			var nn := (p1 - p0).cross(top - p0).normalized()
			if nn.y < 0.0:
				nn = -nn
			cone.tri(p0, p1, top, nn)
		var st := surf("a", "steel")
		for dx in [-1.6, 1.6]:
			for dz in [-1.6, 1.6]:
				st.box(tc + Vector3(dx, 1.6, dz), Vector3(0.2, 3.2, 0.2), 1.0)
		st.box(tc + Vector3(0, 3.1, 0), Vector3(4.0, 0.2, 0.25), 1.0)
		st.box(tc + Vector3(0, 3.1, 0), Vector3(0.25, 0.2, 4.0), 1.0)
		for i in 3:
			surf("a", "steel").cyl(tc + Vector3(0, 3.6 + i * 1.3, 0), 2.33, 0.05, 16, 1.0)
	# Condensers and a kitchen exhaust; vent stacks.
	for c in [[Vector3(26.0, 0, 19.0), Vector3(2.2, 1.3, 1.2)], [Vector3(29.0, 0, 19.0), Vector3(2.2, 1.3, 1.2)],
			[Vector3(40.5, 0, 22.0), Vector3(1.6, 1.0, 3.0)]]:
		var p: Vector3 = c[0] + Vector3(0, A_ROOF + c[1].y * 0.5, 0)
		_col(c[1], p, {"albedo": 0.3})
		if _geo:
			surf("a", "steel_light").box(p, c[1], 0.6)
			surf("a", "black").box(p + Vector3(0, c[1].y * 0.5 + 0.01, 0), Vector3(c[1].x * 0.8, 0.02, c[1].z * 0.8), 1.0,
					[false, false, true, false, false, false])
	if _geo:
		for v in [Vector3(19.0, 0, 14.0), Vector3(19.6, 0, 14.0), Vector3(41.0, 0, 37.5)]:
			surf("a", "steel_light").cyl(v + Vector3(0, A_ROOF, 0), 0.08, 1.4, 8, 1.0)


# ------------------------------------------------------- crossing furniture ---

## Signals on the four corners, a bus shelter, a hydrant, the barricades
## that close the crossing off.
func _crossing_furniture() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector2(sx * 11.3, sz * 7.8)
			var base := Vector3(c.x, WALK, c.y)
			_col(Vector3(0.3, 6.0, 0.3), base + Vector3(0, 3.0, 0), {"albedo": 0.2}, true, false)
			if _geo:
				var s := surf("street", "pole")
				s.cyl(base, 0.12, 6.4, 8, 1.6)
				# Mast arm over the avenue towards its centre line.
				s.box(Vector3(c.x * 0.5 + sx * 0.6 * 0.5, 6.2, c.y), Vector3(absf(c.x) - 0.6 + 0.6, 0.14, 0.14), 1.5)
			_head(Vector3(sx * 4.0, 5.5, c.y), Vector3(0, 0, sz), "avenue")
			_head(base + Vector3(0, 3.4, 0) + Vector3(sx * 0.3, 0, 0), Vector3(sx, 0, 0), "street")
			_ped(base + Vector3(-sx * 0.2, 2.5, 0), Vector3(-sx, 0, 0), "ped_a")
			_ped(base + Vector3(0, 2.5, -sz * 0.2), Vector3(0, 0, -sz), "ped_s")
	# A hydrant, a bin, a bus shelter (no advertising) on the avenue.
	if _geo:
		surf("street", "hydrant").cyl(Vector3(13.0, WALK, 22.0), 0.12, 0.65, 8, 0.4)
		surf("street", "hydrant").box(Vector3(13.0, WALK + 0.55, 22.0), Vector3(0.36, 0.1, 0.12), 0.4)
		surf("street", "steel").cyl(Vector3(12.8, WALK, -14.0), 0.28, 0.95, 10, 0.5)
		var sh := surf("street", "steel_light")
		for z in [-38.0, -32.0]:
			for x in [-13.6, -11.6]:
				sh.box(Vector3(x, WALK + 1.2, z), Vector3(0.08, 2.4, 0.08), 1.2)
		sh.box(Vector3(-12.6, WALK + 2.45, -35.0), Vector3(2.4, 0.1, 6.4), 1.0)
		surf("street", "wood").box(Vector3(-13.4, WALK + 0.45, -35.0), Vector3(0.4, 0.06, 4.0), 1.0)
		surf("street", "black").box(Vector3(-13.68, WALK + 1.3, -35.0), Vector3(0.04, 1.6, 5.6), 1.0)
	_col(Vector3(2.4, 2.5, 6.4), Vector3(-12.6, WALK + 1.25, -35.0), {"albedo": 0.2}, true, false)
	# Barricades: where the crossing ends, across road and sidewalks.
	var ends := [[Vector2(BOUND.position.x, 0), true], [Vector2(BOUND.end.x, 0), true],
			[Vector2(0, BOUND.position.y), false], [Vector2(0, BOUND.end.y), false]]
	for e in ends:
		var p: Vector2 = e[0]
		var along_z: bool = e[1]
		var half := 10.0 if along_z else 15.0
		var n := int(half * 2.0 / 2.4)
		for i in n:
			var o := -half + 1.2 + i * 2.4
			var bp := Vector3(p.x, 0.0, o) if along_z else Vector3(o, 0.0, p.y)
			var on_walk := (absf(o) > 6.0) if along_z else (absf(o) > 9.5)
			bp.y = WALK if on_walk else 0.0
			if _geo:
				_barricade(bp, along_z)
		_col(Vector3(0.4, 4.0, half * 2.0) if along_z else Vector3(half * 2.0, 4.0, 0.4), Vector3(p.x, 2.0, p.y), {}, true, false)
	# The alley's hoarding and the plaza's edges close the rest.
	_col(Vector3(0.4, 4.0, 45.0), Vector3(-70.2, 2.0, -47.5), {}, true, false)


func _barricade(p: Vector3, along_z: bool) -> void:
	var yaw := PI * 0.5 if along_z else 0.0
	var b := Basis(Vector3.UP, yaw)
	var s := surf("street", "barrier")
	var w := surf("street", "barrier_w")
	for k in 2:
		var c := p + Vector3(0, 0.75 + k * 0.4, 0)
		s.box_rot(c, Vector3(2.2, 0.18, 0.03), yaw, 1.2)
	for dx in [-0.95, 0.95]:
		w.box_rot(p + b.x * dx + Vector3(0, 0.55, 0), Vector3(0.05, 1.1, 0.5), yaw, 1.2)


func _head(p: Vector3, nn: Vector3, set_name: String) -> void:
	heads.append({"pos": p, "normal": nn, "set": set_name})
	# The lenses' glare (the lens geometry itself is baked; the sprite's
	# core never shows): kinds 2-4 face the avenue, 5-7 the street.
	var fxs := [Lucid.FIXTURES.signal_red, Lucid.FIXTURES.signal_yellow, Lucid.FIXTURES.signal_green]
	for i in 3:
		points.append({"pos": p + Vector3(0, 0.33 - i * 0.33, 0) + nn * 0.05, "cd": fxs[i].peak_cd, "rgb": Lucid.fixture_rgb(fxs[i]),
				"kind": (2.0 if set_name == "avenue" else 5.0) + i, "r": 0.15, "near": 1e5})
	if not _geo:
		return
	var side := Vector3.UP.cross(nn)
	var s := surf("street", "signal")
	s.box_rot(p - nn * 0.12, Vector3(0.36, 1.05, 0.25), atan2(nn.x, nn.z), 0.5)
	var cols := ["r", "y", "g"]
	for i in 3:
		var c := p + Vector3(0, 0.33 - i * 0.33, 0) + nn * 0.011
		var l := surf("street", "sig_%s_%s" % [set_name, cols[i]])
		l.quad(c - side * 0.13 - Vector3(0, 0.13, 0), side * 0.26, Vector3(0, 0.26, 0), 0.3, nn)
		# Visor.
		s.box_rot(c + nn * 0.12 + Vector3(0, 0.14, 0), Vector3(0.3, 0.02, 0.24), atan2(nn.x, nn.z), 0.5)


func _ped(p: Vector3, nn: Vector3, set_name: String) -> void:
	heads.append({"pos": p, "normal": nn, "set": set_name})
	if not _geo:
		return
	var side := Vector3.UP.cross(nn)
	surf("street", "signal").box_rot(p - nn * 0.1, Vector3(0.36, 0.5, 0.2), atan2(nn.x, nn.z), 0.5)
	surf("street", set_name + "_hand").quad(p + nn * 0.001 - side * 0.13 + Vector3(0, 0.0, 0), side * 0.26, Vector3(0, 0.2, 0), 0.3, nn)
	surf("street", set_name + "_walk").quad(p + nn * 0.001 - side * 0.13 - Vector3(0, 0.21, 0), side * 0.26, Vector3(0, 0.2, 0), 0.3, nn)


# ------------------------------------------------------------------- lamps ---

## The crossing's own lamps (from the grid, so the far ground's pools line
## up), switchable in the bake (the failing sodium lamp is one), the steady
## ring beyond, and their poles, arms and heads.
func _lamps() -> void:
	var near := LucidCity.grid_lamps(Rect2(-100, -75, 200, 150))
	var idx := 0
	var bulb_fx: Dictionary = Lucid.FIXTURES.jelly_jar_60w
	for l in lamps:
		l.idx = idx
		idx += 1
		points.append({"pos": l.pos, "cd": Lucid.peak_intensity(bulb_fx), "rgb": Lucid.fixture_rgb(bulb_fx), "kind": 0.0,
				"r": 0.06, "near": 1e5})
	for l in near:
		l.idx = idx
		l.failing = (l.pos as Vector3).distance_to(FAILING) < 0.5
		idx += 1
		lamps.append(l)
		_col(Vector3(0.3, l.pos.y, 0.3), l.pole + Vector3(0, l.pos.y * 0.5 + WALK, 0), {"albedo": 0.2}, true, false)
		if _geo:
			_lamp_geo(l)
	var ring := LucidCity.grid_lamps(Rect2(-150, -130, 300, 260))
	for l in ring:
		var dup := false
		for m in near:
			if (m.pos as Vector3).distance_to(l.pos) < 0.5:
				dup = true
				break
		if not dup:
			l.idx = -1
			lamps.append(l)


func _lamp_geo(l: Dictionary) -> void:
	var pole: Vector3 = l.pole + Vector3(0, WALK, 0)
	var head: Vector3 = l.pos
	var s := surf("street", "pole")
	s.cyl(pole, 0.11, head.y + 0.25 - WALK, 8, 2.0)
	var d := Vector3(head.x - pole.x, 0, head.z - pole.z)
	var len := d.length()
	var dn := d / len
	s.box_rot((pole + head) * 0.5 + Vector3(0, head.y - (pole.y + head.y) * 0.5 + 0.2, 0) - Vector3(0, 0, 0),
			Vector3(0.08, 0.08, len), atan2(dn.x, dn.z), 1.0)
	var led: bool = l.fx == "led_street_100w"
	var hs := Vector3(0.32, 0.12, 0.72) if led else Vector3(0.36, 0.2, 0.75)
	surf("street", "housing").box_rot(head + Vector3(0, 0.08, 0) + dn * 0.1, hs, atan2(dn.x, dn.z), 0.5)
	var lens := "lens_led" if led else ("lens_na_failing" if l.failing else "lens_na")
	var ls := Vector2(0.25, 0.5) if led else Vector2(0.25, 0.4)
	var side := Vector3.UP.cross(dn)
	surf("street", lens).quad(head + dn * 0.1 - side * ls.x * 0.5 - dn * ls.y * 0.5 + Vector3(0, -0.0, 0),
			side * ls.x, dn * ls.y, 0.5, Vector3.DOWN)


# ---------------------------------------------------------------- backdrop ---

## The city round it: the street grid's blocks filled with buildings of a
## height drawn from the distance to two downtowns (towers to 300 m), a
## river with a suspension bridge, an elevated road, lamps and signals.
func _backdrop() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7041
	var ae: float = LucidCity.GRID.avenue_every
	var se: float = LucidCity.GRID.street_every
	var reach := 5500.0
	for i in range(-int(reach / ae), int(reach / ae) + 1):
		for j in range(-int(reach / se), int(reach / se) + 1):
			if i in [-1, 0] and j in [-1, 0]:
				continue                     # the crossing's own four blocks
			var x0 := i * ae + 15.0
			var x1 := i * ae + 95.0
			var z0 := j * se + 10.0
			var z1 := j * se + 70.0
			var cx := (x0 + x1) * 0.5
			var cz := (z0 + z1) * 0.5
			var dist := Vector2(cx, cz).length()
			if dist > reach:
				continue
			if x1 > RIVER.x - 20.0 and x0 < RIVER.y + 20.0:
				continue
			if absf(cx - VIADUCT_X) < 45.0:
				continue
			var dt := 0.0
			for dc in DOWNTOWN:
				var dd := Vector2(cx - dc.x, cz - dc.z).length()
				dt = maxf(dt, exp(-dd * dd / (650.0 * 650.0)))
			# Lots: 2-4 across, 1-2 deep.
			var nx := rng.randi_range(2, 4)
			var nz := rng.randi_range(1, 2)
			for a in nx:
				for b in nz:
					var lx0 := lerpf(x0, x1, float(a) / nx)
					var lx1 := lerpf(x0, x1, float(a + 1) / nx)
					var lz0 := lerpf(z0, z1, float(b) / nz)
					var lz1 := lerpf(z0, z1, float(b + 1) / nz)
					var base := 10.0 + 22.0 * pow(rng.randf(), 2.0)
					var h := base * (1.0 + 10.0 * dt * rng.randf()) + (rng.randf() * 90.0 if rng.randf() < 0.04 else 0.0)
					h = minf(h, 320.0)
					if dist > 1300.0 and h < 50.0:
						continue
					if dist > 2400.0 and h < 100.0:
						continue
					_add_block(rng, Vector3((lx0 + lx1) * 0.5, 0, (lz0 + lz1) * 0.5), Vector2(lx1 - lx0 - 0.4, lz1 - lz0 - 0.4), h)
	_bridge(rng)
	_viaduct(rng)
	_far_lamps()
	_far_signals()


func _add_block(rng: RandomNumberGenerator, c: Vector3, fp: Vector2, h: float) -> void:
	var kind := 1 if h > 60.0 and rng.randf() < 0.85 else (0 if rng.randf() < 0.6 else 2)
	var storey: float = [rng.randf_range(2.9, 3.3), rng.randf_range(3.8, 4.2), rng.randf_range(3.3, 3.8)][kind]
	var bay: float = [3.0, 1.5, 2.6][kind]
	var na := 1 if rng.randf() < 0.5 else 0
	var code := kind + 10 * na + 100
	var seed := rng.randf() * 100.0
	blocks.append({"pos": c, "size": Vector3(fp.x, h, fp.y), "custom": Vector4(seed, code, storey, bay)})
	if Vector2(c.x, c.z).length() < 380.0:
		var lit := 0.3 * 0.2 * 12.0 if kind != 1 else 0.2 * 0.65 * 25.0
		colliders.append({"size": Vector3(fp.x, h, fp.y), "xf": Transform3D(Basis(), c + Vector3(0, h * 0.5, 0)),
				"meta": {"albedo": 0.25, "emit_a": Color(lit, lit * 0.85, lit * 0.65), "emit_b": Color(lit, lit * 0.85, lit * 0.65) * 0.63},
				"solid": false, "occluder": true})
	var top := h
	# Setbacks and crowns on towers.
	if h > 80.0:
		var k := rng.randf_range(0.55, 0.8)
		var h2 := h * rng.randf_range(0.12, 0.3)
		blocks.append({"pos": c + Vector3(0, h, 0), "size": Vector3(fp.x * k, h2, fp.y * k), "custom": Vector4(seed + 0.5, code - 100, storey, bay)})
		top = h + h2
		if h > 160.0 and rng.randf() < 0.6:
			var h3 := rng.randf_range(8.0, 30.0)
			blocks.append({"pos": c + Vector3(0, top, 0), "size": Vector3(fp.x * k * 0.5, h3, fp.y * k * 0.5), "custom": Vector4(seed + 0.7, 9, 4.0, 3.0)})
			top += h3
	# Aircraft warning lights: steady low intensity over 45 m, flashing
	# medium intensity over 150 m (ICAO Annex 14), at the top corners.
	if top > 45.0:
		var fx: Dictionary = Lucid.FIXTURES.aviation_red_flash if top > 150.0 else Lucid.FIXTURES.aviation_red_steady
		var ph := rng.randf()
		var red := Lucid.fixture_rgb(fx)
		var hx := fp.x * 0.3
		var hz := fp.y * 0.3
		for corner in ([Vector3(hx, 0, hz), Vector3(-hx, 0, -hz)] if top > 100.0 else [Vector3.ZERO]):
			points.append({"pos": c + corner + Vector3(0, top + 1.0, 0), "cd": Lucid.peak_intensity(fx), "rgb": red,
					"kind": (1.0 + ph * 0.99) if top > 150.0 else 0.0, "r": 0.15})


func _bridge(rng: RandomNumberGenerator) -> void:
	# A suspension bridge over the river: towers 125 m over the water,
	# deck 30 m up, a main span of 160 m between the towers, necklace
	# lights along the main cables every 8 m, deck lamps every 30 m.
	var z := BRIDGE_Z
	var t1 := -1640.0
	var t2 := -1510.0
	var deck := 30.0
	var tower := 125.0
	blocks.append({"pos": Vector3((RIVER.x + RIVER.y) * 0.5, deck - 2.0, z), "size": Vector3(RIVER.y - RIVER.x + 60.0, 2.0, 24.0), "custom": Vector4(1, 9, 4, 3)})
	for tx in [t1, t2]:
		for dz in [-11.0, 11.0]:
			blocks.append({"pos": Vector3(tx, -5.0, z + dz), "size": Vector3(5.0, tower + 5.0, 4.0), "custom": Vector4(2, 9, 4, 3)})
		blocks.append({"pos": Vector3(tx, tower - 12.0, z), "size": Vector3(4.0, 4.0, 26.0), "custom": Vector4(3, 9, 4, 3)})
		blocks.append({"pos": Vector3(tx, deck + 8.0, z), "size": Vector3(4.0, 3.0, 26.0), "custom": Vector4(3, 9, 4, 3)})
		for dz in [-11.0, 11.0]:
			points.append({"pos": Vector3(tx, tower + 1.0, z + dz), "cd": 32.0, "rgb": Lucid.fixture_rgb(Lucid.FIXTURES.aviation_red_steady), "kind": 0.0, "r": 0.15})
	var white := Lucid.kelvin_rgb(3000.0)
	for dz in [-11.0, 11.0]:
		# Main span: a parabola from the tower tops down to 4 m over the deck.
		for k in 21:
			var u := float(k) / 20.0
			var x := lerpf(t1, t2, u)
			var y := deck + 4.0 + (tower - deck - 4.0) * pow(2.0 * u - 1.0, 2.0)
			points.append({"pos": Vector3(x, y, z + dz), "cd": 60.0, "rgb": white, "kind": 0.0, "r": 0.1})
		# Side spans down to the anchorages on the banks.
		for side in [[t1, RIVER.x - 40.0], [t2, RIVER.y + 40.0]]:
			for k in range(1, 11):
				var u := float(k) / 10.0
				var x := lerpf(side[0], side[1], u)
				var y := lerpf(tower, deck + 2.0, pow(u, 0.8))
				points.append({"pos": Vector3(x, y, z + dz), "cd": 60.0, "rgb": white, "kind": 0.0, "r": 0.1})
		var x := RIVER.x - 40.0
		while x < RIVER.y + 40.0:
			points.append({"pos": Vector3(x, deck + 9.0, z + dz * 0.8), "cd": 2500.0, "rgb": Lucid.kelvin_rgb(4000.0), "kind": 9.02, "r": 0.2})
			x += 30.0
	rng.randf()


func _viaduct(_rng: RandomNumberGenerator) -> void:
	# An elevated expressway on 12 m piers every 30 m, 24 m wide, LED lamps
	# on both parapets every 40 m.
	var h := 12.0
	var z := -4000.0
	blocks.append({"pos": Vector3(VIADUCT_X, h, 0.0), "size": Vector3(24.0, 1.8, 8000.0), "custom": Vector4(4, 9, 4, 3)})
	while z <= 4000.0:
		blocks.append({"pos": Vector3(VIADUCT_X, 0.0, z), "size": Vector3(3.0, h, 3.0), "custom": Vector4(5, 9, 4, 3)})
		z += 30.0
	var led := Lucid.fixture_rgb(Lucid.FIXTURES.led_street_100w)
	var i0 := Lucid.peak_intensity(Lucid.FIXTURES.led_street_100w) * 0.9
	z = -3000.0
	while z <= 3000.0:
		for dx in [-10.0, 10.0]:
			points.append({"pos": Vector3(VIADUCT_X + dx * 0.8, h + 11.8, z), "cd": i0, "rgb": led, "kind": 9.02, "r": 0.25})
		z += 40.0


func _far_lamps() -> void:
	# Every grid lamp out to 2.6 km (avenues) / 1.4 km (streets) as a
	# point; the nearer ones also as lamp models (with lens geometry).
	var led_fx: Dictionary = Lucid.FIXTURES.led_street_100w
	var na_fx: Dictionary = Lucid.FIXTURES.sodium_hps_150w
	var led := Lucid.fixture_rgb(led_fx)
	var na := Lucid.fixture_rgb(na_fx)
	var i_led := Lucid.peak_intensity(led_fx) * LucidCity.AVENUE_LAMP.llf
	var i_na := Lucid.peak_intensity(na_fx) * LucidCity.STREET_LAMP.llf
	for spec in [[2200.0, true, false], [900.0, false, true]]:
		var r: float = spec[0]
		for l in LucidCity.grid_lamps(Rect2(-r, -r, 2.0 * r, 2.0 * r), spec[1], spec[2]):
			var p: Vector3 = l.pos
			if Vector2(p.x, p.z).length() > r:
				continue
			if p.x > RIVER.x - 10.0 and p.x < RIVER.y + 10.0:
				continue
			if absf(p.x - VIADUCT_X) < 30.0 and l.street:
				continue
			if p.distance_to(FAILING) < 0.5:
				continue
			var street: bool = l.street
			points.append({"pos": p, "cd": i_na if street else i_led, "rgb": na if street else led,
					"kind": 9.6 if street else 9.1, "r": 0.2, "near": 70.0})
			var near_rect := Rect2(-100, -75, 200, 150)
			if Vector2(p.x, p.z).length() < 320.0 and not near_rect.has_point(Vector2(p.x, p.z)):
				lamp_models.append(l)


func _far_signals() -> void:
	# The signals at the other crossings along the avenue and the street
	# (and nearby), on a green wave: offset by the travel time at 12 m/s.
	var cols := {"r": Lucid.fixture_rgb(Lucid.FIXTURES.signal_red), "y": Lucid.fixture_rgb(Lucid.FIXTURES.signal_yellow),
			"g": Lucid.fixture_rgb(Lucid.FIXTURES.signal_green)}
	var cd := {"r": 365.0, "y": 910.0, "g": 475.0}
	var ae: float = LucidCity.GRID.avenue_every
	var se: float = LucidCity.GRID.street_every
	for i in range(-18, 19):
		for j in range(-25, 26):
			if i == 0 and j == 0:
				continue
			var x := i * ae
			var z := j * se
			if not (i == 0 or j == 0 or (absi(i) <= 3 and absi(j) <= 4)):
				continue
			if x > RIVER.x - 10.0 and x < RIVER.y + 10.0:
				continue
			var phase := fposmod(-z / 12.0 / 60.0 + x / 12.0 / 60.0 * 0.5, 1.0)
			for sz in [-1.0, 1.0]:
				for k in 3:
					var c: String = ["r", "y", "g"][k]
					points.append({"pos": Vector3(x + sz * 4.0, 5.5 + 0.33 - k * 0.33, z + sz * 7.8), "cd": cd[c], "rgb": cols[c],
							"kind": [2.0, 3.0, 4.0][k] + phase * 0.99, "r": 0.15})
			for sx in [-1.0, 1.0]:
				for k in 3:
					var c: String = ["r", "y", "g"][k]
					points.append({"pos": Vector3(x + sx * 11.6, 3.4 + 0.33 - k * 0.33, z + sx * 7.8), "cd": cd[c], "rgb": cols[c],
							"kind": [5.0, 6.0, 7.0][k] + phase * 0.99, "r": 0.15})
