extends RefCounted
## The Blue Hour's plan (night_city_level.gd builds it, tools/lucid/city_bake.gd
## bakes it): one crossing of an avenue and a street in an endless city,
## the six-storey brick building on its south-east corner whose roof you
## arrive on, the fire stair down its alley, and the city round it to the
## horizon. Everything here is deterministic (the bake must match), in
## level space: metres, ground at y = 0 at the crossing's centre, X east,
## Z south (Godot's -Z is north). Real sizes and their sources: SPEC.md.

## Floor to floor: the shop floor (retail, 4.5 m), then the upper storeys
## of the brick walk-ups (pre-war apartments: a 3.0 m ceiling and a 0.3 m
## floor) and of the concrete apartment block (3.1 m, CTBUH's residential
## floor to floor).
const G0 := 4.5
const ST := 3.3
const ST_B := 3.1
## Building A (yours): x 15..45, z 10..40, roof at G0 + 5 ST.
const A_ROOF := G0 + 5.0 * ST
const PARAPET := 1.1
const WALK := 0.15
## The fire stair: storey levels from the alley (on the sidewalk's level).
const STAIR_Y := [WALK, G0, G0 + ST, G0 + 2.0 * ST, G0 + 3.0 * ST, G0 + 4.0 * ST, A_ROOF]
const STAIR_X := Vector2(45.0, 47.5)
const LAND_A := Vector2(12.4, 13.6)     # z of the landings by the street
const LAND_B := Vector2(16.6, 17.8)     # z of the half landings
## Treads 0.3 m everywhere (IBC 1011.5.2: 11 in, 279 mm, or more; risers
## 7 in, 178 mm, or less): a flight between the landings has 10 (risers
## 0.15 m a storey up), the alley's first flight starts 0.9 m further
## north, under the first floor landing, with 13 (25 risers of 0.174 m up
## the 4.35 m to the first floor).
const TREAD := 0.3
const STAIR_FOOT := 12.7
## The residents' street door: a pair of 0.915 x 2.13 m leaves (36 x 84 in)
## under a transom, in its own bay of the avenue front (z 30..35: no
## shopfront there; A_wall's u runs along -z).
const DOOR_Z := 32.5
const DOOR_BAY := Vector2(-35.0, -30.0)
## Where you may go (the barricades close the rest of the crossing).
const BOUND := Rect2(-86.0, -61.0, 172.0, 122.0)
## The failing sodium lamp (cycles off and on like an old HPS lamp).
const FAILING := Vector3(55.0, 8.0, 5.1)
## The river and its bridge, the elevated road, the two tower clusters.
const RIVER := Vector2(-1700.0, -1450.0)
const BRIDGE_Z := -400.0
const VIADUCT_X := 385.0
const DOWNTOWN := [Vector3(-2350.0, 0.0, -650.0), Vector3(700.0, 0.0, -1350.0)]
## Every face of a box (Surf.box leaves out the bottom, which nothing
## standing on the ground shows; anything over the eye needs it).
const ALL := [true, true, true, true, true, true]

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
		"road": {"albedo": Color(0.094, 0.086, 0.068), "tex": "asphalt", "uv": 3.0, "rough": 0.75, "wet": 1.0, "puddles": 0.5,
				"gutters": true, "lamps": true, "paint": true, "normal": 0.6},
		"alley": {"albedo": Color(0.085, 0.08, 0.07), "tex": "asphalt", "uv": 2.5, "rough": 0.8, "wet": 0.9, "puddles": 0.75, "lamps": true},
		"walk": {"albedo": Color(0.30, 0.295, 0.28), "tex": "concrete", "uv": 1.6, "rough": 0.8, "wet": 0.55, "puddles": 0.12,
				"lamps": true, "normal": 0.5, "untile": true},
		"curb": {"albedo": Color(0.36, 0.35, 0.33), "tex": "concrete", "uv": 1.0, "rough": 0.7, "wet": 0.55, "lamps": true},
		"plaza": {"albedo": Color(0.33, 0.32, 0.30), "tex": "facade_concrete", "uv": 1.2, "rough": 0.6, "wet": 0.6, "puddles": 0.3, "lamps": true, "untile": true},
		"roof": {"albedo": Color(0.30, 0.30, 0.29), "tex": "concrete", "uv": 1.2, "rough": 0.85, "wet": 0.5, "puddles": 0.45, "normal": 0.6, "untile": true},
		"coping": {"albedo": Color(0.38, 0.37, 0.35), "tex": "concrete", "uv": 0.8, "rough": 0.75, "wet": 0.4},
		"stucco": {"albedo": Color(0.40, 0.39, 0.36), "tex": "facade_concrete", "uv": 2.0, "rough": 0.85},
		"steel": {"albedo": Color(0.07, 0.075, 0.075), "rough": 0.5, "f0": 0.04},
		"steel_light": {"albedo": Color(0.32, 0.33, 0.33), "rough": 0.4, "f0": 0.04},
		"door": {"albedo": Color(0.16, 0.19, 0.2), "rough": 0.45, "f0": 0.04},
		"pole": {"albedo": Color(0.20, 0.21, 0.21), "rough": 0.45, "f0": 0.04},
		"housing": {"albedo": Color(0.30, 0.31, 0.31), "rough": 0.5},
		"signal": {"albedo": Color(0.05, 0.05, 0.04), "rough": 0.5},
		"wood": {"albedo": Color(0.16, 0.11, 0.07), "rough": 0.9},
		"ply": {"albedo": Color(0.28, 0.21, 0.13), "rough": 0.85},
		"barrier": {"albedo": Color(0.55, 0.22, 0.04), "rough": 0.6},
		"barrier_w": {"albedo": Color(0.62, 0.62, 0.6), "rough": 0.5},
		"dumpster": {"albedo": Color(0.035, 0.07, 0.045), "rough": 0.6},
		"hydrant": {"albedo": Color(0.32, 0.04, 0.03), "rough": 0.5},
		"black": {"albedo": Color(0.03, 0.03, 0.03), "rough": 0.6},
		# Facades: windows from lucid_windows (seed, kind, storey, bay), shop
		# band. Bays divide each wall from corner to corner (win_mask.x
		# shifts the grid where one bay can't fit two faces), so no window
		# or shopfront (5 m) is cut by a corner.
		"A_wall": {"albedo": Color(0.33, 0.19, 0.11), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(11, 2, ST, 2.5), "shop": G0, "normal": 0.8,
				"top": A_ROOF + PARAPET, "shop_mask": DOOR_BAY},
		# The alley wall: its storeys are A's (sills 0.8 m over floors 4.5 +
		# 3.3 n), a window by each of the fire stair's floor landings (the
		# way out onto it) and none behind its flights and half landings
		# (win_mask: u shift, no windows from u to u, v shift), the shop
		# floor's back wall blank (its "shop band", in the shifted v, all
		# masked).
		"A_side": {"albedo": Color(0.33, 0.19, 0.11), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(12, 2, ST, 3.9), "normal": 0.8,
				"shop": ST + 0.05, "shop_mask": Vector2(-1000.0, 1000.0),
				"top": A_ROOF + PARAPET, "win_mask": Vector4(3.9 * 3.5 - 13.0, 14.0, 19.2, ST + 0.85 - (G0 + 0.8))},
		"brick": {"albedo": Color(0.33, 0.19, 0.11), "tex": "brick", "uv": 2.4, "rough": 0.85, "normal": 0.8},
		"A2_wall": {"albedo": Color(0.36, 0.34, 0.30), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(13, 0, ST, 10.0 / 3.0), "shop": 0.0},
		"B_wall": {"albedo": Color(0.40, 0.38, 0.34), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(21, 0, ST_B, 2.75), "shop": G0,
				"win_mask": Vector4(4.0, 0.0, 0.0, 0.0)},
		"B_side": {"albedo": Color(0.40, 0.38, 0.34), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(22, 0, ST_B, 4.0), "shop": 0.0,
				"win_mask": Vector4(2.0, 0.0, 0.0, 0.0)},
		"C1_wall": {"albedo": Color(0.08, 0.09, 0.10), "rough": 0.4, "facade": Vector4(31, 1, 4.2, 1.25), "shop": G0, "f0": 0.04},
		"C2_wall": {"albedo": Color(0.30, 0.20, 0.14), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(32, 2, 3.5, 2.5), "shop": G0},
		"D1_wall": {"albedo": Color(0.42, 0.27, 0.17), "tex": "brick", "uv": 2.4, "rough": 0.85, "facade": Vector4(41, 2, ST, 2.5), "shop": G0},
		"D2_wall": {"albedo": Color(0.45, 0.44, 0.41), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(42, 0, 3.1, 40.0 / 13.0), "shop": G0,
				"win_mask": Vector4(-5.0 / 13.0, 0.0, 0.0, 0.0)},
		"E1_wall": {"albedo": Color(0.07, 0.08, 0.09), "rough": 0.35, "facade": Vector4(51, 1, 4.1, 1.25), "shop": 8.2, "f0": 0.04},
		"E2_wall": {"albedo": Color(0.38, 0.36, 0.33), "tex": "facade_concrete", "uv": 2.4, "rough": 0.85, "facade": Vector4(52, 0, 3.2, 2.5), "shop": G0},
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
	_block("street", Rect2(51, 10, 44, 60), G0 + 8 * ST_B, "B_wall", "B_side", [false, false, false, true], hm)
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
		# Over the roof, the parapet's outer face stops at the gap to the
		# fire stair's top landing.
		si.wall(Vector2(45, 10), Vector2(45, 40), 14.0, A_ROOF, Vector3.RIGHT, 2.5)
		si.wall(Vector2(45, 10), Vector2(45, LAND_A.x), A_ROOF, A_ROOF + PARAPET, Vector3.RIGHT, 2.5)
		si.wall(Vector2(45, LAND_A.y), Vector2(45, 40), A_ROOF, A_ROOF + PARAPET, Vector3.RIGHT, 2.5)
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
	if _geo:
		# The brick ends of the parapet either side of the gap, and a
		# concrete threshold across it (the roof's edge to the landing).
		for e in [[g0, Vector3.BACK], [g1, Vector3.FORWARD]]:
			surf("a", "brick").quad(Vector3(45 - t, A_ROOF, e[0]), Vector3(t, 0, 0), Vector3(0, PARAPET, 0), 1.0, e[1])
		surf("a", "coping").box(Vector3(45 - t * 0.5, A_ROOF + 0.01, (g0 + g1) * 0.5), Vector3(t, 0.02, g1 - g0), 1.0)
		# Precast coping, 60 mm, 50 mm proud of both faces: the long runs
		# over the street and the back, the side runs butted between them
		# (no overlaps, so no two tops fight for the same pixels).
		var cy := A_ROOF + PARAPET + 0.03
		var cs := Vector3(0.0, 0.06, t + 0.1)
		for z in [10 + t * 0.5, 40 - t * 0.5]:
			surf("a", "coping").box(Vector3(30, cy, z), Vector3(30.1, cs.y, cs.z), 1.0, ALL)
		var z0 := 10 + t + 0.05
		var z1 := 40 - t - 0.05
		for r in [[15 + t * 0.5, z0, z1], [45 - t * 0.5, z0, g0], [45 - t * 0.5, g1, z1]]:
			surf("a", "coping").box(Vector3(r[0], cy, (r[1] + r[2]) * 0.5), Vector3(cs.z, cs.y, r[2] - r[1]), 1.0, ALL)
	# The street door (residents' entrance on the avenue): two leaves, the
	# transom's dark glass over them, a steel lintel.
	if _geo:
		var d := surf("a", "door")
		d.quad(Vector3(14.99, WALK, DOOR_Z - 0.915), Vector3(0, 0, 1.83), Vector3(0, 2.13, 0), 0.6, Vector3.LEFT)
		surf("a", "black").quad(Vector3(14.99, WALK + 2.19, DOOR_Z - 0.915), Vector3(0, 0, 1.83), Vector3(0, 0.45, 0), 0.6, Vector3.LEFT)
		surf("a", "steel_light").box(Vector3(14.97, WALK + 2.16, DOOR_Z), Vector3(0.05, 0.06, 1.83), 1.0, ALL)
		surf("a", "steel_light").box(Vector3(14.95, WALK + 2.7, DOOR_Z), Vector3(0.12, 0.12, 2.1), 1.0, ALL)
	spots.street_door = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(14.98, WALK, DOOR_Z))


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


# ------------------------------------------------------------------- stair ---

## The fire stair in the alley: a steel switchback up A's east wall, two
## flights a storey (out along the outer lane, back on the inner), as a
## real one is put together: channel stringers 180 mm deep with open
## grating treads between them (one riser fewer than the flight's rises,
## the last one up onto the landing), landings of grating in a channel
## frame on a ledger angle bolted to the wall and on four steel columns,
## knee braces under the half landings, guards 1.07 m high (top rail, mid
## rail, pickets) on every open side and a handrail on the wall. Collision:
## a ramp per flight.
func _stair() -> void:
	var xo := Vector2(46.35, 47.45)      # outer lane
	var xi := Vector2(45.1, 46.25)       # inner lane
	for k in STAIR_Y.size() - 1:
		var y0: float = STAIR_Y[k]
		var y1: float = STAIR_Y[k + 1]
		# The half landing where the risers of the two flights split the
		# storey evenly (the first flight is longer: more of them).
		var za := STAIR_FOOT if k == 0 else LAND_A.y
		var nb := roundi((LAND_B.x - za) / TREAD) + 1
		var nt := roundi((LAND_B.x - LAND_A.y) / TREAD) + 1
		var hm := y0 + (y1 - y0) * nb / (nb + nt)
		_flight(xo, za, LAND_B.x, y0, hm)
		_flight(xi, LAND_B.x, LAND_A.y, hm, y1)
		# Landings (grating, 30 mm, in their frames) at the half and the top.
		_landing(Vector3((STAIR_X.x + STAIR_X.y) * 0.5, hm, (LAND_B.x + LAND_B.y) * 0.5), Vector3(STAIR_X.y - STAIR_X.x, 0.05, LAND_B.y - LAND_B.x), true)
		_landing(Vector3((STAIR_X.x + STAIR_X.y) * 0.5, y1, (LAND_A.x + LAND_A.y) * 0.5), Vector3(STAIR_X.y - STAIR_X.x, 0.05, LAND_A.y - LAND_A.x), false)
		# Guards: the outer side and the landings' ends; between the lanes.
		_rail(y0, y1, hm, za, k == 0, k == STAIR_Y.size() - 2)
		_rail_ends(y1, hm)
		_col(Vector3(0.1, y1 - y0 + 1.2, LAND_B.x - LAND_A.y), Vector3(46.3, (y0 + y1) * 0.5 + 0.6, (LAND_A.y + LAND_B.x) * 0.5),
				{}, true, false)
	if _geo:
		var s := surf("a", "steel")
		# Columns (80 mm square tube) at the landings' outer corners, from
		# the alley to the top guard, on base plates.
		var top: float = STAIR_Y[STAIR_Y.size() - 1] + 1.1
		for z in [LAND_A.x + 0.04, LAND_A.y - 0.04, LAND_B.x + 0.04, LAND_B.y - 0.04]:
			s.box(Vector3(STAIR_X.y - 0.04, (WALK + top) * 0.5, z), Vector3(0.08, top - WALK, 0.08), 3.0)
			s.box(Vector3(STAIR_X.y - 0.04, WALK + 0.01, z), Vector3(0.2, 0.02, 0.2), 1.0)
	# Nothing to walk under the first flight: a block under it from where
	# it is 1.1 m up (its top stays under the treads) to the half landing.
	var n0 := roundi((LAND_B.x - STAIR_FOOT) / TREAD) + 1
	var n1 := roundi((LAND_B.x - LAND_A.y) / TREAD) + 1
	var r0 := (LAND_B.x - STAIR_FOOT) / ((STAIR_Y[1] - STAIR_Y[0]) * n0 / (n0 + n1))
	var zb0 := STAIR_FOOT + (1.1 - WALK) * r0
	_col(Vector3(xo.y - xo.x, 1.0, LAND_B.x - zb0), Vector3((xo.x + xo.y) * 0.5, 0.5, (zb0 + LAND_B.x) * 0.5),
			{}, true, false)
	# The landing bulbs (caged 60 W jelly jars on A's wall over the window
	# out onto each floor landing, under the landing above), and one at the
	# foot of the stair.
	for k in range(1, STAIR_Y.size() - 1):
		var y: float = STAIR_Y[k] + ST - 0.5
		lamps.append({"pos": Vector3(45.12, y, 13.0), "fx": "jelly_jar_60w", "llf": 1.0, "bulb": true})
		if _geo:
			_bulb(Vector3(45.0, y, 13.0), Vector3.RIGHT)
	lamps.append({"pos": Vector3(45.12, 2.5, 19.0), "fx": "jelly_jar_60w", "llf": 1.0, "bulb": true})
	if _geo:
		_bulb(Vector3(45.0, 2.5, 19.0), Vector3.RIGHT)
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


## A flight up the lane x (its edges) from z = za, y = ya to zb, yb: two
## channel stringers, the treads between them (bar grating with a nosing
## angle; open risers), TREAD deep, the collision ramp.
func _flight(x: Vector2, za: float, zb: float, ya: float, yb: float) -> void:
	var run := absf(zb - za)
	var rise := yb - ya
	var n := maxi(roundi(run / TREAD) + 1, 2)
	var dz := (zb - za) / (n - 1)
	var sg := signf(zb - za)
	if _geo:
		var s := surf("a", "steel")
		var w := x.y - x.x - 0.1
		var xc := (x.x + x.y) * 0.5
		var tb := (absf(dz) - 0.04 - 2.0 * 0.025) / 3.0
		for i in n - 1:
			var y := ya + rise * (i + 1) / n
			var z := za + dz * (i + 0.5)
			# Three bars of grating with gaps you see through.
			for j in 3:
				var zj := z + sg * (j - 1) * (tb + 0.025)
				s.box(Vector3(xc, y - 0.015, zj), Vector3(w, 0.03, tb), 2.0, [false, false, true, true, true, true])
			# The nosing angle (50 x 50 mm) at the front edge.
			s.box(Vector3(xc, y - 0.03, z - sg * (absf(dz) * 0.5 - 0.035)), Vector3(w, 0.06, 0.03), 2.0, [false, false, false, true, true, true])
		# Stringers: 200 x 50 mm channels at the lane's edges, their tops
		# 40 mm over the nosing line, from landing frame to landing frame.
		for xs in [x.x + 0.025, x.y - 0.025]:
			_bar(s, Vector3(xs, ya + rise / n - 0.06, za), Vector3(xs, yb - 0.06, zb), Vector2(0.05, 0.2))
	var xf := Transform3D(Basis(Vector3.RIGHT, -atan2(rise, zb - za)), Vector3((x.x + x.y) * 0.5, (ya + yb) * 0.5 - 0.04, (za + zb) * 0.5))
	# (Grating: it lets most light through, so it is no occluder.)
	_col_xf(Vector3(x.y - x.x, 0.08, sqrt(run * run + rise * rise)), xf, {"albedo": 0.08}, true, false)


## A straight steel member from a to b (its centre line), size.x wide
## (level), size.y deep: its four long faces.
func _bar(s: LucidCity.Surf, a: Vector3, b: Vector3, size: Vector2) -> void:
	var d := (b - a).normalized()
	var side := d.cross(Vector3.UP)
	if side.length() < 0.01:
		side = Vector3.RIGHT
	side = side.normalized()
	var up := side.cross(d).normalized()
	var hw := side * size.x * 0.5
	var hh := up * size.y * 0.5
	var l := b - a
	var step := 2.0
	s.quad(a + hw - hh, l, hh * 2.0, step, side)
	s.quad(a - hw - hh, l, hh * 2.0, step, -side)
	s.quad(a - hw + hh, l, hw * 2.0, step, up)
	s.quad(a - hw - hh, l, hw * 2.0, step, -up)


## A landing: the grating deck, its frame (150 mm channels round it, the
## wall side a ledger angle on anchor plates), knee braces from the wall
## under a half landing (no window there).
func _landing(c: Vector3, s: Vector3, braces: bool) -> void:
	_col(Vector3(s.x, 0.1, s.z), c - Vector3(0, 0.05, 0), {"albedo": 0.08})
	if not _geo:
		return
	var st := surf("a", "steel")
	var h := s * 0.5
	# The deck: 50 mm bars from the wall out, 35 mm apart, on two bearers.
	var inner := Vector2(s.x - 0.12, s.z - 0.12)
	var nb := int(inner.y / 0.085)
	for i in nb:
		var z := c.z - inner.y * 0.5 + (i + 0.5) * inner.y / nb
		st.box(Vector3(c.x, c.y - 0.015, z), Vector3(inner.x, 0.03, inner.y / nb - 0.035), 1.0, [false, false, true, true, true, true])
	for dx in [-inner.x / 6.0, inner.x / 6.0]:
		st.box(Vector3(c.x + dx, c.y - 0.06, c.z), Vector3(0.05, 0.06, inner.y), 1.0, [true, true, false, true, false, false])
	# Frame: the two ends (wall to outer edge) and the outer side.
	for dz in [-h.z + 0.03, h.z - 0.03]:
		st.box(Vector3(c.x, c.y - 0.075, c.z + dz), Vector3(s.x, 0.15, 0.06), 1.0, ALL)
	st.box(Vector3(c.x + h.x - 0.03, c.y - 0.075, c.z), Vector3(0.06, 0.15, s.z - 0.12), 1.0, ALL)
	# The ledger on the wall and its anchor plates.
	st.box(Vector3(c.x - h.x + 0.03, c.y - 0.05, c.z), Vector3(0.06, 0.1, s.z - 0.12), 1.0, ALL)
	for dz in [-h.z + 0.15, h.z - 0.15]:
		st.box(Vector3(c.x - h.x + 0.005, c.y - 0.1, c.z + dz), Vector3(0.01, 0.2, 0.2), 1.0, [true, false, true, true, true, true])
	if braces:
		for dz in [-h.z + 0.03, h.z - 0.03]:
			var foot := Vector3(c.x - h.x + 0.03, c.y - 1.5, c.z + dz)
			_bar(st, foot, Vector3(c.x + h.x - 0.9, c.y - 0.15, c.z + dz), Vector2(0.05, 0.05))
			st.box(foot + Vector3(-0.025, 0.0, 0.0), Vector3(0.01, 0.2, 0.15), 1.0, [true, false, true, true, true, true])


## A guard 1.07 m high along a path of points on the walking line (the
## nosings, the decks): top rail, a bottom rail, 12 mm square pickets 0.1 m
## apart (IBC 1015.4: no opening a 4 in, 102 mm, sphere passes).
func _guard(pts: Array, first_post := true) -> void:
	var s := surf("a", "steel")
	for i in pts.size() - 1:
		var a: Vector3 = pts[i]
		var b: Vector3 = pts[i + 1]
		_bar(s, a + Vector3(0, 1.07, 0), b + Vector3(0, 1.07, 0), Vector2(0.04, 0.04))
		_bar(s, a + Vector3(0, 0.1, 0), b + Vector3(0, 0.1, 0), Vector2(0.025, 0.025))
		var hz := Vector2(b.x - a.x, b.z - a.z).length()
		var m := maxi(ceili(hz / 0.1), 1)
		# (Only a picket's two faces across the guard: its 12 mm edges add
		# nothing seen from anywhere, and there are a thousand of them.)
		var faces := [false, false, false, false, true, true] if absf(b.x - a.x) > absf(b.z - a.z) else [true, true, false, false, false, false]
		for j in m:
			var p := a.lerp(b, (j + 0.5) / m)
			s.box(p + Vector3(0, 0.53, 0), Vector3(0.012, 1.06, 0.012), 2.0, faces)
	for p in ([pts[0], pts[pts.size() - 1]] if first_post else [pts[pts.size() - 1]]):
		s.box(p + Vector3(0, 0.545, 0), Vector3(0.04, 1.09, 0.04), 2.0, [true, true, true, false, true, true])


func _rail(y0: float, y1: float, hm: float, za: float, first: bool, last: bool) -> void:
	var x := STAIR_X.y + 0.02
	_col(Vector3(0.06, y1 - y0 + 1.3, LAND_B.y - LAND_A.x), Vector3(x, (y0 + y1) * 0.5 + 0.65, (LAND_A.x + LAND_B.y) * 0.5),
			{}, true, false)
	if not _geo:
		return
	# The outer side: the floor landing, up the outer flight and round the
	# half landing (and the top landing's side).
	var xg := STAIR_X.y - 0.04
	var outer := [Vector3(xg, y0, za), Vector3(xg, hm, LAND_B.x), Vector3(xg, hm, LAND_B.y)]
	if not first:
		outer.push_front(Vector3(xg, y0, LAND_A.x))
	_guard(outer)
	if last:
		_guard([Vector3(xg, y1, LAND_A.x), Vector3(xg, y1, LAND_A.y)])
	# Between the lanes (each flight has a drop to the other lane's): one
	# plane of guards, the lower flight's up to the half landing, the upper
	# flight's back from it.
	_guard([Vector3(46.3, y0, za), Vector3(46.3, hm, LAND_B.x), Vector3(46.3, y1, LAND_A.y)], first)
	# The inner flight's handrail on the wall (0.86 m over the nosings) on
	# brackets.
	var s := surf("a", "steel")
	var a := Vector3(45.08, hm + 0.86, LAND_B.x)
	var b := Vector3(45.08, y1 + 0.86, LAND_A.y)
	_bar(s, a, b, Vector2(0.04, 0.04))
	for t in [0.15, 0.5, 0.85]:
		var p := a.lerp(b, t)
		s.box(Vector3(45.03, p.y - 0.04, p.z), Vector3(0.06, 0.02, 0.02), 1.0, ALL)


func _rail_ends(y1: float, hm: float) -> void:
	# The half landing's far end, and the top landing's street end.
	_col(Vector3(STAIR_X.y - STAIR_X.x, 1.2, 0.06), Vector3((STAIR_X.x + STAIR_X.y) * 0.5, hm + 0.6, LAND_B.y + 0.02), {}, true, false)
	_col(Vector3(STAIR_X.y - STAIR_X.x, 1.2, 0.06), Vector3((STAIR_X.x + STAIR_X.y) * 0.5, y1 + 0.6, LAND_A.x - 0.02), {}, true, false)
	if _geo:
		_guard([Vector3(STAIR_X.x + 0.05, hm, LAND_B.y - 0.03), Vector3(STAIR_X.y - 0.08, hm, LAND_B.y - 0.03)])
		_guard([Vector3(STAIR_X.x + 0.05, y1, LAND_A.x + 0.03), Vector3(STAIR_X.y - 0.08, y1, LAND_A.x + 0.03)])


## A caged jelly-jar bulb on a wall (the face at `wall`, facing `out`):
## anchor plate, arm, cage cap, the glass 0.12 m out and 0.1 m down.
func _bulb(wall: Vector3, out: Vector3) -> void:
	var st := surf("a", "steel")
	var g := wall + out * 0.12
	st.box(wall + out * 0.01 + Vector3(0, 0.1, 0), Vector3(0.02, 0.14, 0.12) if out.x != 0.0 else Vector3(0.12, 0.14, 0.02), 0.5, ALL)
	st.box(wall + out * 0.07 + Vector3(0, 0.15, 0), (Vector3(0.12, 0.03, 0.03) if out.x != 0.0 else Vector3(0.03, 0.03, 0.12)), 0.5, ALL)
	st.box(g + Vector3(0, 0.11, 0), Vector3(0.13, 0.05, 0.13), 0.5, ALL)
	surf("a", "bulb").box(g, Vector3(0.11, 0.16, 0.11), 0.5, [true, true, false, true, true, true])


## A flat disc (a cap, a tank's floor) of `sides` facets facing nn (up or down).
func _disc(s: LucidCity.Surf, c: Vector3, r: float, sides: int, nn: Vector3) -> void:
	for i in sides:
		var a0 := TAU * i / sides
		var a1 := TAU * (i + 1) / sides
		s.tri(c, c + Vector3(cos(a0) * r, 0, sin(a0) * r), c + Vector3(cos(a1) * r, 0, sin(a1) * r), nn)


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
		surf("a", "coping").box(Vector3(36.5, A_ROOF + 3.04, 33.5), Vector3(5.1, 0.08, 5.1), 1.0, ALL)
		surf("a", "door").quad(Vector3(33.99, A_ROOF, 33.05), Vector3(0, 0, 0.92), Vector3(0, 2.05, 0), 0.5, Vector3.LEFT)
		surf("a", "steel_light").box(Vector3(33.97, A_ROOF + 1.05, 33.85), Vector3(0.04, 0.04, 0.6), 0.5)
		_bulb(Vector3(34.0, A_ROOF + 2.45, 33.5), Vector3.LEFT)
		surf("a", "steel").box(Vector3(33.95, A_ROOF + 2.12, 33.51), Vector3(0.1, 0.06, 1.1), 0.5, ALL)
		# A steel ladder up the bulkhead's north face to its roof (rails
		# 0.46 m apart on brackets 0.18 m off the wall, rungs every 0.3 m,
		# the rails carried 1.07 m over the top to hold on to).
		var lx := 37.6
		var lz := 30.82
		var lt := A_ROOF + 3.08 + 1.07
		var ld := surf("a", "steel")
		for dx in [-0.23, 0.23]:
			ld.box(Vector3(lx + dx, (A_ROOF + lt) * 0.5, lz), Vector3(0.06, lt - A_ROOF, 0.02), 1.5, ALL)
			for y in [A_ROOF + 0.6, A_ROOF + 2.7]:
				ld.box(Vector3(lx + dx, y, (lz + 31.0) * 0.5), Vector3(0.05, 0.05, 31.0 - lz), 1.0, ALL)
		for i in 10:
			ld.box(Vector3(lx, A_ROOF + 0.3 + i * 0.3, lz), Vector3(0.46, 0.025, 0.025), 1.0, ALL)
	_col(Vector3(0.6, 4.15, 0.22), Vector3(37.6, A_ROOF + 2.08, 30.88), {}, true, false)
	lamps.append({"pos": Vector3(33.88, A_ROOF + 2.45, 33.5), "fx": "jelly_jar_60w", "llf": 1.0, "bulb": true})
	spots.roof_door = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(33.98, A_ROOF, 33.51))
	spots.arrival = Transform3D(Basis(Vector3.UP, PI * 0.5 + 0.1), Vector3(32.6, A_ROOF, 33.4))
	# Water tank: 4.6 m across, 4.2 m of staves on a 3.2 m steel stand.
	var tc := Vector3(41.6, A_ROOF, 37.0)
	_col(Vector3(4.2, 7.6, 4.2), tc + Vector3(0, 3.8, 0), {"albedo": 0.12})
	if _geo:
		surf("a", "wood").cyl(tc + Vector3(0, 3.2, 0), 2.3, 4.2, 16, 1.5)
		_disc(surf("a", "wood"), tc + Vector3(0, 3.2, 0), 2.3, 16, Vector3.DOWN)
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
		st.box(tc + Vector3(0, 3.1, 0), Vector3(4.0, 0.2, 0.25), 1.0, ALL)
		st.box(tc + Vector3(0, 3.1, 0), Vector3(0.25, 0.2, 4.0), 1.0, ALL)
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
		# (Capped: an open pipe end shows the sky through it from above.)
		for v in [Vector3(19.0, 0, 14.0), Vector3(19.6, 0, 14.0), Vector3(42.5, 0, 28.0)]:
			surf("a", "steel_light").cyl(v + Vector3(0, A_ROOF, 0), 0.08, 1.4, 8, 1.0)
			_disc(surf("a", "steel_light"), v + Vector3(0, A_ROOF + 1.4, 0), 0.08, 8, Vector3.UP)


# ------------------------------------------------------- crossing furniture ---

## Signals on the four corners, a bus shelter, a hydrant, the barricades
## that close the crossing off.
func _crossing_furniture() -> void:
	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			var c := Vector2(sx * 11.3, sz * 7.8)
			var base := Vector3(c.x, WALK, c.y)
			_col(Vector3(0.36, 6.0, 0.36), base + Vector3(0, 3.0, 0), {"albedo": 0.2}, true, false)
			# Heads on the far side of the crossing (MUTCD 4D.13, 4D.14:
			# 12-55 m past the stop line, traffic keeps right): the corner
			# on an approach's far right carries a mast arm over its lanes
			# (the head 5.5 m up, its bottom 5.0 m over the road: 4.6 m or
			# more), the one on its far left a second head on the pole (its
			# bottom 3.4 m up), facing back across the crossing. Here the
			# avenue's arm or the street's, as the corner falls.
			var avenue_arm: bool = sx == -sz
			var tip := Vector3(sx * 3.5, 6.2, c.y) if avenue_arm else Vector3(c.x, 6.2, sz * 1.75)
			var arm_n := Vector3(0, 0, -sz) if avenue_arm else Vector3(-sx, 0, 0)
			var pole_n := Vector3(-sx, 0, 0) if avenue_arm else Vector3(0, 0, -sz)
			if _geo:
				# A 0.33 m pole, 6.4 m; the arm (0.18 m) out to the head, a
				# hanger down to it.
				var s := surf("street", "pole")
				s.cyl(base, 0.165, 6.4, 8, 1.6)
				_disc(s, base + Vector3(0, 6.4, 0), 0.165, 8, Vector3.UP)
				var mid := (Vector3(c.x, 6.2, c.y) + tip) * 0.5
				var len := Vector2(tip.x - c.x, tip.z - c.y).length() + 0.3
				s.box(mid, Vector3(len, 0.18, 0.18) if avenue_arm else Vector3(0.18, 0.18, len), 1.5, ALL)
				s.box(tip + Vector3(0, -0.12, 0), Vector3(0.06, 0.12, 0.06), 1.0, ALL)
			_head(tip + Vector3(0, -0.7, 0) + arm_n * 0.12, arm_n, "avenue" if avenue_arm else "street")
			_head(base + Vector3(0, 3.95, 0) + pole_n * 0.42, pole_n, "street" if avenue_arm else "avenue")
			# Pedestrian heads on the pole, each to the crossing it faces
			# across, under the vehicle heads (bottom 2.2 m up: MUTCD 4E.08,
			# 2.1-3.0 m).
			_ped(base + Vector3(-sx * 0.4, 2.58, 0), Vector3(-sx, 0, 0), "ped_a")
			_ped(base + Vector3(0, 2.58, -sz * 0.4), Vector3(0, 0, -sz), "ped_s")
	# A hydrant 0.6 m behind the curb (body 0.2 m, 0.8 m high, the hose
	# nozzles either side), a litter basket, a bus shelter (no advertising)
	# on the avenue.
	if _geo:
		var hy := surf("street", "hydrant")
		hy.cyl(Vector3(10.15, WALK, 22.0), 0.1, 0.72, 8, 0.4)
		hy.cyl(Vector3(10.15, WALK + 0.72, 22.0), 0.125, 0.06, 8, 0.4)
		_disc(hy, Vector3(10.15, WALK + 0.78, 22.0), 0.125, 8, Vector3.UP)
		hy.box(Vector3(10.15, WALK + 0.5, 22.0), Vector3(0.12, 0.1, 0.42), 0.4, ALL)
		hy.box(Vector3(10.0, WALK + 0.48, 22.0), Vector3(0.12, 0.14, 0.14), 0.4, ALL)
		hy.cyl(Vector3(10.15, WALK, 22.0), 0.15, 0.05, 8, 0.4)
		surf("street", "steel").cyl(Vector3(12.8, WALK, -14.0), 0.28, 0.95, 10, 0.5)
		var sh := surf("street", "steel_light")
		for z in [-38.0, -32.0]:
			for x in [-13.6, -11.6]:
				sh.box(Vector3(x, WALK + 1.2, z), Vector3(0.08, 2.4, 0.08), 1.2)
		sh.box(Vector3(-12.6, WALK + 2.45, -35.0), Vector3(2.4, 0.1, 6.4), 1.0, ALL)
		surf("street", "wood").box(Vector3(-13.4, WALK + 0.45, -35.0), Vector3(0.4, 0.06, 4.0), 1.0)
		surf("street", "black").box(Vector3(-13.68, WALK + 1.3, -35.0), Vector3(0.04, 1.6, 5.6), 1.0)
	# (Its back panel, roof and bench: you can stand under it out of the rain.)
	_col(Vector3(0.1, 2.5, 6.4), Vector3(-13.68, WALK + 1.25, -35.0), {"albedo": 0.2}, true, false)
	_col(Vector3(2.4, 0.1, 6.4), Vector3(-12.6, WALK + 2.45, -35.0), {"albedo": 0.2}, true, false)
	_col(Vector3(0.4, 0.48, 4.0), Vector3(-13.4, WALK + 0.24, -35.0), {"albedo": 0.2}, true, false)
	for z in [-38.0, -32.0]:
		_col(Vector3(0.08, 2.4, 0.08), Vector3(-11.6, WALK + 1.2, z), {}, true, false)
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


## A Type 3 barricade, as at a road closure (MUTCD 6F.68): three rails
## 200 mm deep, the top one's top 1.55 m up (1.5 m or more), 2.2 m long.
func _barricade(p: Vector3, along_z: bool) -> void:
	var yaw := PI * 0.5 if along_z else 0.0
	var b := Basis(Vector3.UP, yaw)
	var s := surf("street", "barrier")
	var w := surf("street", "barrier_w")
	for k in 3:
		var c := p + Vector3(0, 0.75 + k * 0.35, 0)
		s.box_rot(c, Vector3(2.2, 0.2, 0.03), yaw, 1.2)
	for dx in [-0.95, 0.95]:
		w.box_rot(p + b.x * dx + Vector3(0, 0.8, 0), Vector3(0.05, 1.6, 0.5), yaw, 1.2)


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
	s.box_rot(p - nn * 0.12, Vector3(0.36, 1.05, 0.25), atan2(nn.x, nn.z), 0.5, true)
	var cols := ["r", "y", "g"]
	for i in 3:
		var c := p + Vector3(0, 0.33 - i * 0.33, 0) + nn * 0.011
		var l := surf("street", "sig_%s_%s" % [set_name, cols[i]])
		l.quad(c - side * 0.135 - Vector3(0, 0.135, 0), side * 0.27, Vector3(0, 0.27, 0), 0.3, nn)
		# Visor.
		s.box_rot(c + nn * 0.12 + Vector3(0, 0.14, 0), Vector3(0.3, 0.02, 0.24), atan2(nn.x, nn.z), 0.5, true)


## A pedestrian head: two 300 mm sections (the hand over the walking
## person), symbols 0.28 m high (MUTCD 4E.07: 9 in, 229 mm, or more where
## the far curb is over 60 ft off).
func _ped(p: Vector3, nn: Vector3, set_name: String) -> void:
	heads.append({"pos": p, "normal": nn, "set": set_name})
	if not _geo:
		return
	var side := Vector3.UP.cross(nn)
	surf("street", "signal").box_rot(p - nn * 0.1, Vector3(0.36, 0.74, 0.2), atan2(nn.x, nn.z), 0.5, true)
	surf("street", set_name + "_hand").quad(p + nn * 0.001 - side * 0.14 + Vector3(0, 0.045, 0), side * 0.28, Vector3(0, 0.28, 0), 0.3, nn)
	surf("street", set_name + "_walk").quad(p + nn * 0.001 - side * 0.14 - Vector3(0, 0.325, 0), side * 0.28, Vector3(0, 0.28, 0), 0.3, nn)


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
	_disc(s, Vector3(pole.x, head.y + 0.25, pole.z), 0.11, 8, Vector3.UP)
	var d := Vector3(head.x - pole.x, 0, head.z - pole.z)
	var len := d.length()
	var dn := d / len
	var led: bool = l.fx == "led_street_100w"
	var hs := Vector3(0.32, 0.12, 0.72) if led else Vector3(0.36, 0.2, 0.75)
	# The housing just over its lens, the arm running into its top.
	var hy := head.y + 0.005 + hs.y * 0.5
	s.box_rot(Vector3((pole.x + head.x) * 0.5, hy + hs.y * 0.5 - 0.04, (pole.z + head.z) * 0.5),
			Vector3(0.08, 0.08, len), atan2(dn.x, dn.z), 1.0, true)
	surf("street", "housing").box_rot(Vector3(head.x, hy, head.z) + dn * 0.1, hs, atan2(dn.x, dn.z), 0.5, true)
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
	# Aircraft warning lights (ICAO Annex 14 6.2.3, FAA AC 70/7460-1M
	# ch. 4): steady low intensity red on the roofs of 30-45 m buildings
	# (some of them: those near the flight paths), flashing medium
	# intensity red (40 a minute) over 45 m, at the top corners.
	if top > 45.0 or (top > 30.0 and fposmod(seed * 7.31, 1.0) < 0.3):
		var fx: Dictionary = Lucid.FIXTURES.aviation_red_flash if top > 45.0 else Lucid.FIXTURES.aviation_red_steady
		var ph := rng.randf() if top > 45.0 else 0.0
		var red := Lucid.fixture_rgb(fx)
		var hx := fp.x * 0.3
		var hz := fp.y * 0.3
		for corner in ([Vector3(hx, 0, hz), Vector3(-hx, 0, -hz)] if top > 100.0 else [Vector3.ZERO]):
			points.append({"pos": c + corner + Vector3(0, top + 1.0, 0), "cd": Lucid.peak_intensity(fx), "rgb": red,
					"kind": (1.0 + ph * 0.99) if top > 45.0 else 0.0, "r": 0.15})


func _bridge(rng: RandomNumberGenerator) -> void:
	# A suspension bridge over the 250 m river: a 220 m main span between
	# towers 10 m out from the banks, side spans of 55 m to the anchorages
	# where the streets meet the banks, the deck 30 m over the water (a
	# navigation clearance), the cables' sag 26 m (1:8.5; suspension
	# bridges 1:8 to 1:12), so the towers stand 60 m over the water, 30 m
	# over the deck (Manhattan Bridge: 448 m span, towers 102 m). Necklace
	# lights along the main cables, deck lamps every 30 m.
	var z := BRIDGE_Z
	var t1 := RIVER.x + 10.0
	var t2 := RIVER.y - 10.0
	var a1 := t1 - 55.0
	var a2 := t2 + 55.0
	var deck := 30.0
	var tower := 60.0
	blocks.append({"pos": Vector3((a1 + a2) * 0.5, deck - 2.0, z), "size": Vector3(a2 - a1, 2.0, 24.0), "custom": Vector4(1, 9, 4, 3)})
	for tx in [t1, t2]:
		for dz in [-11.0, 11.0]:
			blocks.append({"pos": Vector3(tx, -5.0, z + dz), "size": Vector3(5.0, tower + 5.0, 4.0), "custom": Vector4(2, 9, 4, 3)})
		blocks.append({"pos": Vector3(tx, tower - 6.0, z), "size": Vector3(4.0, 3.0, 26.0), "custom": Vector4(3, 9, 4, 3)})
		blocks.append({"pos": Vector3(tx, deck + 6.0, z), "size": Vector3(4.0, 2.5, 26.0), "custom": Vector4(3, 9, 4, 3)})
		# (Over 45 m: medium intensity, flashing.)
		var fx: Dictionary = Lucid.FIXTURES.aviation_red_flash
		for dz in [-11.0, 11.0]:
			points.append({"pos": Vector3(tx, tower + 1.0, z + dz), "cd": Lucid.peak_intensity(fx), "rgb": Lucid.fixture_rgb(fx),
					"kind": 1.0 + rng.randf() * 0.99, "r": 0.15})
	var white := Lucid.kelvin_rgb(3000.0)
	for dz in [-11.0, 11.0]:
		# Main span: a parabola from the tower tops down to 4 m over the deck.
		for k in 21:
			var u := float(k) / 20.0
			var x := lerpf(t1, t2, u)
			var y := deck + 4.0 + (tower - deck - 4.0) * pow(2.0 * u - 1.0, 2.0)
			points.append({"pos": Vector3(x, y, z + dz), "cd": 60.0, "rgb": white, "kind": 0.0, "r": 0.1})
		# Side spans down to the anchorages on the banks.
		for side in [[t1, a1], [t2, a2]]:
			for k in range(1, 11):
				var u := float(k) / 10.0
				var x := lerpf(side[0], side[1], u)
				var y := lerpf(tower, deck + 2.0, pow(u, 0.8))
				points.append({"pos": Vector3(x, y, z + dz), "cd": 60.0, "rgb": white, "kind": 0.0, "r": 0.1})
		var x := a1
		while x < a2:
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
			# The mast arm heads (as at the crossing: the avenue's from the
			# north-east and south-west corners, the street's from the
			# others; the pole heads are left out this far).
			for s in [-1.0, 1.0]:
				for k in 3:
					var c: String = ["r", "y", "g"][k]
					points.append({"pos": Vector3(x + s * 3.5, 5.5 + 0.33 - k * 0.33, z - s * 7.68), "cd": cd[c], "rgb": cols[c],
							"kind": [2.0, 3.0, 4.0][k] + phase * 0.99, "r": 0.15})
					points.append({"pos": Vector3(x + s * 11.18, 5.5 + 0.33 - k * 0.33, z + s * 1.75), "cd": cd[c], "rgb": cols[c],
							"kind": [5.0, 6.0, 7.0][k] + phase * 0.99, "r": 0.15})
