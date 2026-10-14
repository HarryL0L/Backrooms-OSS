class_name ChunkBuilder
extends RefCounted
## Builds the geometry, baked lighting and collision of one chunk.
##
## Runs entirely on a worker thread and only produces plain packed arrays; the
## main thread turns them into an ArrayMesh + collision shape in a fraction of a
## millisecond. Lighting is baked per vertex (direct light from every fixture in
## range with wall occlusion, a cheap bounce term and contact AO), which looks
## like lightmapped lighting but costs nothing at runtime on mobile GPUs.

const CELL := WorldGen.CELL
const N := WorldGen.CHUNK
const M := 4                     # margin cells (>= max light radius / CELL)
const W := N + 2 * M
const SUB := 3                   # floor / ceiling subdivisions per cell
const T := 0.07                  # half wall thickness
const SPACING := 1.2             # target vertex spacing on walls
const LM_W := 256                # lightmap atlas width (texels)
const LM_TEXEL := 0.4            # lightmap texel spacing on floors and walls (m)
const LM_TEXEL_CEIL := 0.8       # ... on ceilings (lit from below, smooth anyway)

enum {
	MAT_WALLPAPER, MAT_CARPET, MAT_CEILING_TILE, MAT_POOL_TILE, MAT_WATER,
	MAT_CONC_WALL, MAT_CONC_FLOOR, MAT_CONC_CEIL, MAT_LIGHT, MAT_CRATE,
	MAT_CHROME, MAT_SHAFT, MAT_PIPE, MAT_BRICK, MAT_GRIME, MAT_OUTLET, MAT_HALO, MAT_COUNT
}
## Materials whose shaders read the per-chunk lightmap.
const LIGHTMAPPED := [MAT_WALLPAPER, MAT_CARPET, MAT_CEILING_TILE, MAT_POOL_TILE, MAT_CONC_WALL,
		MAT_CONC_FLOOR, MAT_CONC_CEIL, MAT_BRICK, MAT_GRIME]
const WALL_MAT := [MAT_WALLPAPER, MAT_POOL_TILE, MAT_CONC_WALL, MAT_WALLPAPER, MAT_GRIME]
const FLOOR_MAT := [MAT_CARPET, MAT_POOL_TILE, MAT_CONC_FLOOR, MAT_CARPET, MAT_BRICK]
const CEIL_MAT := [MAT_CEILING_TILE, MAT_POOL_TILE, MAT_CONC_CEIL, MAT_CEILING_TILE, MAT_GRIME]
const PANEL_SIZE := [Vector2(1.22, 0.62), Vector2(0.62, 0.62), Vector2(1.7, 0.24), Vector2(1.22, 0.62), Vector2(0.6, 0.6)]
const SKY_SIZE := 1.8
const HALO_SIZE := [1.2, 1.5, 1.6, 1.2, 1.1]
const SUN_DIR := Vector3(0.32, -1.0, 0.22)
const EMIT_SCALE := 1.5


class Buf:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var tg := PackedFloat32Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var c0 := PackedFloat32Array()
	var c1 := PackedFloat32Array()        # lightmap texel coords, (-1, -1) = per-vertex light
	var idx := PackedInt32Array()

	func add(p: Vector3, nrm: Vector3, tan: Vector3, t: Vector2, t2: Vector2, light: Color) -> int:
		v.push_back(p)
		n.push_back(nrm)
		tg.push_back(tan.x)
		tg.push_back(tan.y)
		tg.push_back(tan.z)
		tg.push_back(1.0)
		uv.push_back(t)
		uv2.push_back(t2)
		c0.push_back(light.r)
		c0.push_back(light.g)
		c0.push_back(light.b)
		c0.push_back(light.a)
		c1.push_back(-1.0)
		c1.push_back(-1.0)
		return v.size() - 1

	func set_lm(i: int, t: Vector2) -> void:
		c1[i * 2] = t.x
		c1[i * 2 + 1] = t.y

	func to_arrays() -> Array:
		var a := []
		a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX] = v
		a[Mesh.ARRAY_NORMAL] = n
		a[Mesh.ARRAY_TANGENT] = tg
		a[Mesh.ARRAY_TEX_UV] = uv
		a[Mesh.ARRAY_TEX_UV2] = uv2
		a[Mesh.ARRAY_CUSTOM0] = c0
		a[Mesh.ARRAY_CUSTOM1] = c1
		a[Mesh.ARRAY_INDEX] = idx
		return a


var gen: WorldGen
var coord: Vector2i
var rx0: int
var rz0: int

var biome := PackedByteArray()        # (W+2)^2, cells -1..W
var floor_y := PackedFloat32Array()   # W*W
var ceil_y := PackedFloat32Array()
var pool := PackedByteArray()
var solid := PackedByteArray()
var ev := PackedByteArray()           # vertical edges   lx in 0..W, lz in 0..W-1
var eh := PackedByteArray()           # horizontal edges lx in 0..W-1, lz in 0..W
var light_at := PackedInt32Array()
var lpos := PackedVector3Array()
var lcol := PackedColorArray()
var lrad := PackedFloat32Array()
var lseed := PackedFloat32Array()
var cand := []
var cache := {}
var bufs := []
var col := PackedVector3Array()
var _seed := 0.0
var _cur_cell := Vector2.ZERO
# Lightmap atlas (RGBA half floats, shelf packed, grows downwards).
var lm_bytes := PackedByteArray()
# Per-face light visibility while baking a face: 0 hidden, 1 visible, 2 test
# per texel. Empty when not baking.
var _face_vis := PackedByteArray()
var _face_lights := PackedInt32Array()   # lights that can reach the face being baked
var _face_on := false
var _lm_x := 0
var _lm_y := 0
var _lm_shelf := 0


func _init(p_gen: WorldGen, p_coord: Vector2i) -> void:
	gen = p_gen
	coord = p_coord
	rx0 = coord.x * N - M
	rz0 = coord.y * N - M


# -------------------------------------------------------------- accessors ---

func bio(i: int, j: int) -> int:
	return biome[(i + 1) + (j + 1) * (W + 2)]


func edge_v(lx: int, lz: int) -> int:
	if lx < 0 or lx > W or lz < 0 or lz >= W:
		return 0
	return ev[lx + lz * (W + 1)]


func edge_h(lx: int, lz: int) -> int:
	if lx < 0 or lx >= W or lz < 0 or lz > W:
		return 0
	return eh[lx + lz * W]


func fl(i: int, j: int) -> float:
	return floor_y[i + j * W]


func ce(i: int, j: int) -> float:
	return ceil_y[i + j * W]


func buf(mat: int) -> Buf:
	if bufs[mat] == null:
		bufs[mat] = Buf.new()
	return bufs[mat]


# ------------------------------------------------------------------ build ---

func build() -> Dictionary:
	bufs.resize(MAT_COUNT)
	_compute_layout()
	_compute_lights()
	for j in N:
		for i in N:
			var li := M + i
			var lj := M + j
			_emit_cell(li, lj)
			_emit_edge_v(li, lj)
			_emit_edge_h(li, lj)
			_emit_vertex(li, lj)
	var surfaces := {}
	for m in MAT_COUNT:
		var b: Buf = bufs[m]
		if b != null and b.v.size() > 0:
			surfaces[m] = b.to_arrays()
	return {"coord": coord, "surfaces": surfaces, "collision": col, "lightmap": _lm_image()}


func _lm_alloc(w: int, h: int) -> Vector2i:
	if _lm_x + w > LM_W:
		_lm_x = 0
		_lm_y += _lm_shelf
		_lm_shelf = 0
	var at := Vector2i(_lm_x, _lm_y)
	_lm_x += w
	_lm_shelf = maxi(_lm_shelf, h)
	var need := (_lm_y + _lm_shelf) * LM_W * 8
	if lm_bytes.size() < need:
		lm_bytes.resize(maxi(need, lm_bytes.size() * 2))
	return at


func _lm_image() -> Image:
	var h := _lm_y + _lm_shelf
	if h == 0:
		return null
	h = (h + 3) & ~3
	var bytes := lm_bytes.slice(0, h * LM_W * 8)
	if bytes.size() < h * LM_W * 8:
		bytes.resize(h * LM_W * 8)
	return Image.create_from_data(LM_W, h, false, Image.FORMAT_RGBAH, bytes)


func _compute_layout() -> void:
	biome.resize((W + 2) * (W + 2))
	for j in range(-1, W + 1):
		for i in range(-1, W + 1):
			biome[(i + 1) + (j + 1) * (W + 2)] = gen.biome_at(rx0 + i, rz0 + j)
	floor_y.resize(W * W)
	ceil_y.resize(W * W)
	pool.resize(W * W)
	solid.resize(W * W)
	for j in W:
		for i in W:
			var b := bio(i, j)
			solid[i + j * W] = 1 if gen.is_solid(rx0 + i, rz0 + j, b) else 0
			var p := b == WorldGen.POOL and bio(i - 1, j) == b and bio(i + 1, j) == b \
					and bio(i, j - 1) == b and bio(i, j + 1) == b and gen.pool_noise(rx0 + i, rz0 + j)
			pool[i + j * W] = 1 if p else 0
			floor_y[i + j * W] = WorldGen.POOL_FLOOR if p else 0.0
			ceil_y[i + j * W] = WorldGen.CEIL_H[b]
	ev.resize((W + 1) * W)
	for lz in W:
		for lx in W + 1:
			ev[lx + lz * (W + 1)] = gen.edge_kind(rx0 + lx, rz0 + lz, true, bio(lx - 1, lz), bio(lx, lz))
	eh.resize(W * (W + 1))
	for lz in W + 1:
		for lx in W:
			eh[lx + lz * W] = gen.edge_kind(rz0 + lz, rx0 + lx, false, bio(lx, lz - 1), bio(lx, lz))


func _compute_lights() -> void:
	light_at.resize(W * W)
	cand.resize(W * W)
	for j in W:
		for i in W:
			light_at[i + j * W] = -1
			var b := bio(i, j)
			var s := gen.light_state(rx0 + i, rz0 + j, b)
			if s == WorldGen.L_SKY:
				light_at[i + j * W] = lpos.size()
				lpos.push_back(Vector3((rx0 + i + 0.5) * CELL, ce(i, j) - 0.03, (rz0 + j + 0.5) * CELL))
				lcol.push_back(WorldGen.SKY_COLOR * WorldGen.SKY_POWER)
				lrad.push_back(WorldGen.SKY_RADIUS)
				lseed.push_back(0.0)
			elif s == WorldGen.L_ON or s == WorldGen.L_FLICKER:
				light_at[i + j * W] = lpos.size()
				lpos.push_back(Vector3((rx0 + i + 0.5) * CELL, ce(i, j) - 0.03, (rz0 + j + 0.5) * CELL))
				lcol.push_back(WorldGen.LIGHT_COLOR[b] * WorldGen.LIGHT_POWER[b])
				lrad.push_back(WorldGen.LIGHT_RADIUS[b])
				lseed.push_back(gen.light_seed(rx0 + i, rz0 + j) if s == WorldGen.L_FLICKER else 0.0)


func _candidates(i: int, j: int) -> PackedInt32Array:
	var k := i + j * W
	if cand[k] != null:
		return cand[k]
	var list := PackedInt32Array()
	var cx := (rx0 + i + 0.5) * CELL
	var cz := (rz0 + j + 0.5) * CELL
	for dj in range(-M, M + 1):
		var jj := j + dj
		if jj < 0 or jj >= W:
			continue
		for di in range(-M, M + 1):
			var ii := i + di
			if ii < 0 or ii >= W:
				continue
			var l := light_at[ii + jj * W]
			if l < 0:
				continue
			var dx := maxf(absf(lpos[l].x - cx) - CELL * 0.5, 0.0)
			var dz := maxf(absf(lpos[l].z - cz) - CELL * 0.5, 0.0)
			if dx * dx + dz * dz < lrad[l] * lrad[l]:
				list.push_back(l)
	cand[k] = list
	return list


# --------------------------------------------------------------- lighting ---

## 2D grid walk from the light to the point, testing every wall edge crossed.
## Coordinates are in local cell units (x, z) and metres (y).
func _visible(ax: float, az: float, ay: float, bx: float, bz: float, by: float) -> bool:
	var ci := floori(ax)
	var cj := floori(az)
	var ti := floori(bx)
	var tj := floori(bz)
	var steps := absi(ti - ci) + absi(tj - cj)
	if steps == 0:
		return true
	var dx := bx - ax
	var dz := bz - az
	var si := 1 if dx > 0.0 else -1
	var sj := 1 if dz > 0.0 else -1
	var tmx := INF
	var tdx := INF
	var tmz := INF
	var tdz := INF
	if dx != 0.0:
		tdx = absf(1.0 / dx)
		tmx = (float(ci + (1 if si > 0 else 0)) - ax) / dx
	if dz != 0.0:
		tdz = absf(1.0 / dz)
		tmz = (float(cj + (1 if sj > 0 else 0)) - az) / dz
	for _s in steps:
		if tmx < tmz:
			var line := ci + (1 if si > 0 else 0)
			var e := edge_v(line, cj)
			if e != 0:
				if e == WorldGen.E_WALL:
					return false
				var along := az + dz * tmx - cj
				var y := ay + (by - ay) * tmx
				if absf(along - 0.5) * CELL > WorldGen.DOOR_W[e] * 0.5 or y > WorldGen.DOOR_H[e]:
					return false
			ci += si
			tmx += tdx
		else:
			var line := cj + (1 if sj > 0 else 0)
			var e := edge_h(ci, line)
			if e != 0:
				if e == WorldGen.E_WALL:
					return false
				var along := ax + dx * tmz - ci
				var y := ay + (by - ay) * tmz
				if absf(along - 0.5) * CELL > WorldGen.DOOR_W[e] * 0.5 or y > WorldGen.DOOR_H[e]:
					return false
			cj += sj
			tmz += tdz
	return true


## Irradiance at a point. rgb = light, a = share coming from a flickering lamp
## (whose seed is left in `_seed`).
func shade(p: Vector3, nrm: Vector3) -> Color:
	var li := floori(p.x / CELL) - rx0
	var lj := floori(p.z / CELL) - rz0
	_seed = 0.0
	if li < 0 or lj < 0 or li >= W or lj >= W:
		return Color(0.02, 0.02, 0.02, 0.0)
	var b := bio(li, lj)
	var amb: Color = WorldGen.AMBIENT[b]
	var bt: Color = WorldGen.BOUNCE_TINT[b]
	var r := amb.r
	var g := amb.g
	var bl := amb.b
	var u := p.x / CELL - rx0
	var v := p.z / CELL - rz0
	var tot := 0.0
	var fl_amt := 0.0
	var fl_best := 0.0
	for k in (_face_lights if _face_on else _candidates(li, lj)):
		var lp := lpos[k]
		var dx := lp.x - p.x
		var dy := lp.y - p.y
		var dz := lp.z - p.z
		var d2 := dx * dx + dy * dy + dz * dz
		var rad := lrad[k]
		if d2 >= rad * rad:
			continue
		var d := sqrt(d2) + 0.0001
		var w := 1.0 - d / rad
		w *= w
		var att := w / (1.0 + d2 * 0.15)
		if (not _face_on or _face_vis[k] == 2) and not _visible(lp.x / CELL - rx0, lp.z / CELL - rz0, lp.y, u, v, p.y):
			continue
		var ndl := (nrm.x * dx + nrm.y * dy + nrm.z * dz) / d
		var e := 0.25 + 0.75 * maxf(dy / d, 0.0)
		var direct := maxf(ndl, 0.0) * e * att
		var bounce := att * 0.32
		var c := lcol[k]
		r += c.r * (direct + bt.r * bounce)
		g += c.g * (direct + bt.g * bounce)
		bl += c.b * (direct + bt.b * bounce)
		var lum := (direct + bounce) * (c.r + c.g + c.b)
		tot += lum
		if lseed[k] > 0.0:
			fl_amt += lum
			if lum > fl_best:
				fl_best = lum
				_seed = lseed[k]
	var share := fl_amt / tot if tot > 0.0 else 0.0
	return Color(r, g, bl, share)


func _occl(d: float) -> float:
	return 0.55 + 0.45 * smoothstep(0.0, 0.85, d - T)


## Contact shadow on floors / ceilings next to walls. Uses the true distance
## to nearby wall pieces (door openings excluded), so the shadow wraps around
## wall ends instead of stopping in a hard wedge at the cell border.
func _ao_xz(p: Vector3) -> float:
	var u := p.x / CELL - rx0
	var v := p.z / CELL - rz0
	var i := floori(u)
	var j := floori(v)
	var dxm := 9.0
	var dzm := 9.0
	for dj in range(-1, 2):
		for di in range(-1, 3):
			# Vertical edge on line x = i+di, spanning cell row j+dj.
			var e := edge_v(i + di, j + dj)
			if e != 0:
				dxm = minf(dxm, _seg_dist(u - (i + di), v - (j + dj), e))
	for dj in range(-1, 3):
		for di in range(-1, 2):
			var e := edge_h(i + di, j + dj)
			if e != 0:
				dzm = minf(dzm, _seg_dist(v - (j + dj), u - (i + di), e))
	return _occl(dxm) * _occl(dzm)


## Distance (m) from a point to the solid parts of an edge. `across` is the
## offset from the edge line and `along` the position along it, both in cell
## units relative to the edge's start.
func _seg_dist(across: float, along: float, e: int) -> float:
	var da := 0.0
	if e == WorldGen.E_WALL:
		da = maxf(maxf(-along, along - 1.0), 0.0)
	else:
		# Two wall pieces either side of a centred opening.
		var half: float = WorldGen.DOOR_W[e] * 0.5 / CELL
		var a := absf(along - 0.5)
		if a < half:
			da = half - a
		else:
			da = maxf(a - 0.5, 0.0)
	return sqrt(across * across + da * da) * CELL


func _ao_y(y: float, f: float, c: float) -> float:
	return (0.62 + 0.38 * smoothstep(0.0, 0.6, y - f)) * (0.8 + 0.2 * smoothstep(0.0, 0.45, c - y))


# --------------------------------------------------------------- emitters ---

static func _tri_quad(b: Buf, a: int, bb: int, c: int, d: int, flip: bool) -> void:
	# a=(0,0) bb=(1,0) c=(1,1) d=(0,1). Godot front faces are clockwise.
	if flip:
		b.idx.append_array([a, d, c, a, c, bb])
	else:
		b.idx.append_array([a, bb, c, a, c, d])


## Generic subdivided rectangle. Vertices at p0 + du*us[i] + dv*vs[j].
## ao_mode: 0 = wall (vertical AO using f/c), 1 = floor/ceiling (xz AO).
## lm_texel > 0 bakes the face into the chunk lightmap at that texel spacing
## (smooth per-pixel light); otherwise light is baked per vertex.
func _grid(mat: int, p0: Vector3, du: Vector3, dv: Vector3, us: PackedFloat32Array, vs: PackedFloat32Array,
		nrm: Vector3, tan: Vector3, uv_mode: int, ao_mode: int, f: float, c: float, lm_texel: float = 0.0) -> void:
	var b := buf(mat)
	var start := b.v.size()
	var nu := us.size()
	var lm_at := Vector2i(-1, -1)
	var lm_n := Vector2i.ZERO
	var face_seed := 0.0
	if not LIGHTMAPPED.has(mat):
		lm_texel = 0.0
	if lm_texel > 0.0:
		lm_n = Vector2i(maxi(2, ceili(du.length() / lm_texel - 0.01) + 1), maxi(2, ceili(dv.length() / lm_texel - 0.01) + 1))
		lm_at = _lm_alloc(lm_n.x, lm_n.y)
		face_seed = _bake_face(p0, du, dv, nrm, ao_mode, f, c, lm_at, lm_n)
	for jv in vs.size():
		for iu in nu:
			var p := p0 + du * us[iu] + dv * vs[jv]
			var light := Color(0, 0, 0, 0)
			if lm_texel > 0.0:
				_seed = face_seed
			else:
				var sp := p + nrm * 0.05
				if ao_mode == 1:
					sp += _nudge(p)
					var key := Vector3i(roundi(sp.x * 50.0), roundi(sp.y * 50.0), roundi(sp.z * 50.0))
					if cache.has(key):
						light = cache[key]
					else:
						light = shade(sp, nrm)
						var ao := _ao_xz(sp)
						light = Color(light.r * ao, light.g * ao, light.b * ao, light.a)
						light.a = light.a + floorf(_seed)  # pack seed in integer part
						cache[key] = light
					var sd := floorf(light.a)
					light.a -= sd
					_seed = sd
				else:
					light = shade(sp, nrm)
					var ao := _ao_y(p.y, f, c)
					light = Color(light.r * ao, light.g * ao, light.b * ao, light.a)
			var t: Vector2
			match uv_mode:
				0:
					t = Vector2(p.x, p.z)
				1:
					t = Vector2(p.z, -p.y)
				_:
					t = Vector2(p.x, -p.y)
			var vi := b.add(p, nrm, tan, t, Vector2(_seed, 0.0), light)
			if lm_texel > 0.0:
				# Face edges land on texel centres, so filtering never reads a neighbour.
				b.set_lm(vi, Vector2(lm_at.x + 0.5 + us[iu] * (lm_n.x - 1), lm_at.y + 0.5 + vs[jv] * (lm_n.y - 1)))
	var flip := du.cross(dv).dot(nrm) > 0.0
	for jv in vs.size() - 1:
		for iu in nu - 1:
			var a := start + iu + jv * nu
			_tri_quad(b, a, a + 1, a + 1 + nu, a + nu, flip)


## Decides once per face which lights are hidden from all of it, visible from
## all of it, or need testing per texel, by tracing to a 3x3 grid of points on
## the face. Most lights in the maze are behind walls, so this removes most of
## the per-texel visibility tracing.
func _classify_lights(p0: Vector3, du: Vector3, dv: Vector3, nrm: Vector3, horizontal: bool, trace: bool) -> void:
	_face_vis.resize(lpos.size())
	_face_lights = PackedInt32Array()
	var pts := PackedVector3Array()
	var lights := {}
	for jv in 3:
		for iu in 3:
			var pp := p0 + du * (iu * 0.5) + dv * (jv * 0.5)
			var sp := pp + nrm * 0.05
			if horizontal:
				sp += _nudge(pp)
			pts.push_back(sp)
			var li := floori(sp.x / CELL) - rx0
			var lj := floori(sp.z / CELL) - rz0
			if li >= 0 and lj >= 0 and li < W and lj < W:
				for k in _candidates(li, lj):
					lights[k] = true
	var bmin := p0.min(p0 + du + dv)
	var bmax := p0.max(p0 + du + dv)
	for k in lights:
		var lp := lpos[k]
		if lp.distance_squared_to(lp.clamp(bmin, bmax)) >= lrad[k] * lrad[k]:
			_face_vis[k] = 0
			continue
		if not trace:
			# Small face: only the range test, visibility is traced per texel.
			_face_vis[k] = 2
			_face_lights.push_back(k)
			continue
		var seen := 0
		for sp in pts:
			if _visible(lp.x / CELL - rx0, lp.z / CELL - rz0, lp.y, sp.x / CELL - rx0, sp.z / CELL - rz0, sp.y):
				seen += 1
		_face_vis[k] = 0 if seen == 0 else (1 if seen == pts.size() else 2)
		if seen > 0:
			_face_lights.push_back(k)
	_face_on = true


## Shades every lightmap texel of a face and writes it to the atlas. Returns
## the seed of the flickering lamp that contributes most to the face.
func _bake_face(p0: Vector3, du: Vector3, dv: Vector3, nrm: Vector3, ao_mode: int, f: float, c: float,
		at: Vector2i, n: Vector2i) -> float:
	_classify_lights(p0, du, dv, nrm, ao_mode == 1, n.x * n.y > 24)
	var seeds := {}
	var vals := PackedColorArray()
	vals.resize(n.x * n.y)
	var done := PackedByteArray()
	done.resize(n.x * n.y)
	# Pass 1: every other texel (plus the last row/column). Pass 2: texels in
	# between are interpolated where their neighbours agree, shaded otherwise.
	# Light is smooth almost everywhere, so this roughly halves the cost while
	# keeping shadow and doorway edges exact.
	for pass_i in 2:
		for tv in n.y:
			var ev_v := tv % 2 == 0 or tv == n.y - 1
			for tu in n.x:
				var ev_u := tu % 2 == 0 or tu == n.x - 1
				var k := tu + tv * n.x
				if pass_i == 0:
					if not (ev_u and ev_v):
						continue
				elif done[k] == 1:
					continue
				else:
					var u0 := tu if ev_u else tu - 1
					var u1 := tu if ev_u else tu + 1
					var v0 := tv if ev_v else tv - 1
					var v1 := tv if ev_v else tv + 1
					var c00 := vals[u0 + v0 * n.x]
					var c10 := vals[u1 + v0 * n.x]
					var c01 := vals[u0 + v1 * n.x]
					var c11 := vals[u1 + v1 * n.x]
					var l00 := c00.r + c00.g + c00.b
					var l10 := c10.r + c10.g + c10.b
					var l01 := c01.r + c01.g + c01.b
					var l11 := c11.r + c11.g + c11.b
					var lmax := maxf(maxf(l00, l10), maxf(l01, l11))
					var lmin := minf(minf(l00, l10), minf(l01, l11))
					if lmax - lmin <= 0.05 + lmax * 0.22 and absf(c00.a - c11.a) < 0.1 and absf(c10.a - c01.a) < 0.1:
						vals[k] = (c00 + c10 + c01 + c11) * 0.25
						done[k] = 1
						continue
				var p := p0 + du * (float(tu) / (n.x - 1)) + dv * (float(tv) / (n.y - 1))
				# Same sample point on both sides of an open cell border (so no
				# seams); points on a walled line are moved to the visible side.
				var sp := p + nrm * 0.05
				if ao_mode == 1:
					sp += _nudge(p)
				var light := shade(sp, nrm)
				var ao := _ao_xz(sp) if ao_mode == 1 else _ao_y(p.y, f, c)
				if _seed > 0.0:
					seeds[_seed] = seeds.get(_seed, 0.0) + light.a * (light.r + light.g + light.b)
				vals[k] = Color(light.r * ao, light.g * ao, light.b * ao, light.a)
				done[k] = 1
	for tv in n.y:
		for tu in n.x:
			var cl := vals[tu + tv * n.x]
			var o := ((at.y + tv) * LM_W + at.x + tu) * 8
			lm_bytes.encode_half(o, cl.r)
			lm_bytes.encode_half(o + 2, cl.g)
			lm_bytes.encode_half(o + 4, cl.b)
			lm_bytes.encode_half(o + 6, cl.a)
	_face_on = false
	var best := 0.0
	var best_w := 0.0
	for sd in seeds:
		if seeds[sd] > best_w:
			best_w = seeds[sd]
			best = sd
	return best


## Pushes floor/ceiling shading points that sit on a walled grid line towards
## the centre of the cell being built, so the light sample is taken on the
## visible side of the wall.
func _nudge(p: Vector3) -> Vector3:
	var off := Vector3.ZERO
	var u := p.x / CELL
	var v := p.z / CELL
	if absf(u - roundf(u)) < 0.001:
		var line := roundi(u) - rx0
		if edge_v(line, floori(v + 0.0001) - rz0) != 0 or edge_v(line, floori(v - 0.0001) - rz0) != 0:
			off.x = 0.13 * signf(_cur_cell.x - p.x)
	if absf(v - roundf(v)) < 0.001:
		var line := roundi(v) - rz0
		if edge_h(floori(u + 0.0001) - rx0, line) != 0 or edge_h(floori(u - 0.0001) - rx0, line) != 0:
			off.z = 0.13 * signf(_cur_cell.y - p.z)
	return off


func _span(a: float, b: float, step: float) -> PackedFloat32Array:
	var n := maxi(1, ceili((b - a) / step - 0.01))
	var out := PackedFloat32Array()
	for k in n + 1:
		out.push_back(lerpf(a, b, float(k) / n))
	return out


func _rows(y0: float, y1: float) -> PackedFloat32Array:
	var out := PackedFloat32Array([y0])
	var h := y1 - y0
	if h > 0.7:
		out.push_back(y0 + 0.3)
		var inner := _span(y0 + 0.3, y1 - 0.3, 1.4)
		for k in range(1, inner.size()):
			out.push_back(inner[k])
	out.push_back(y1)
	# Values are absolute heights; convert to fractions for _grid.
	var res := PackedFloat32Array()
	for y in out:
		res.push_back((y - y0) / maxf(h, 0.0001))
	return res


func _fracs(a: float, b: float) -> PackedFloat32Array:
	var n := maxi(1, ceili((b - a) / SPACING - 0.01))
	var out := PackedFloat32Array()
	for k in n + 1:
		out.push_back(float(k) / n)
	return out


## Vertical face on a plane of constant X (axis 0) or Z (axis 2).
## sgn: direction of the normal. a0..a1: range along the other horizontal axis.
func _vface(mat: int, axis: int, plane: float, sgn: float, a0: float, a1: float, y0: float, y1: float, f: float, c: float) -> void:
	if a1 - a0 < 0.001 or y1 - y0 < 0.001:
		return
	var p0: Vector3
	var du: Vector3
	var nrm: Vector3
	if axis == 0:
		p0 = Vector3(plane, y0, a0)
		du = Vector3(0, 0, a1 - a0)
		nrm = Vector3(sgn, 0, 0)
	else:
		p0 = Vector3(a0, y0, plane)
		du = Vector3(a1 - a0, 0, 0)
		nrm = Vector3(0, 0, sgn)
	# Same rows for every face, so wall junction posts shade exactly like the
	# walls they join (fewer rows there showed up as vertical strips).
	var rows := _rows(y0, y1)
	_grid(mat, p0, du, Vector3(0, y1 - y0, 0), _fracs(a0, a1), rows, nrm, du.normalized(),
			1 if axis == 0 else 2, 0, f, c, LM_TEXEL)


## Horizontal rectangle (single subdivision unless big).
func _hface(mat: int, xa: float, xb: float, za: float, zb: float, y: float, up: bool, sub: int, cached: bool) -> void:
	var us := PackedFloat32Array()
	for k in sub + 1:
		us.push_back(float(k) / sub)
	_grid(mat, Vector3(xa, y, za), Vector3(xb - xa, 0, 0), Vector3(0, 0, zb - za), us, us,
			Vector3.UP if up else Vector3.DOWN, Vector3.RIGHT, 0, 1 if cached else 0, y - 1.0, y + 1.0, LM_TEXEL)


func _col_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	col.append_array([a, b, c, a, c, d])


func _col_box(lo: Vector3, hi: Vector3) -> void:
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	_col_quad(p[0], p[1], p[5], p[4])
	_col_quad(p[1], p[2], p[6], p[5])
	_col_quad(p[2], p[3], p[7], p[6])
	_col_quad(p[3], p[0], p[4], p[7])
	_col_quad(p[4], p[5], p[6], p[7])


# ------------------------------------------------------------------ cells ---

func _emit_cell(li: int, lj: int) -> void:
	var b := bio(li, lj)
	var gx := rx0 + li
	var gz := rz0 + lj
	var xa := gx * CELL
	var za := gz * CELL
	var f := fl(li, lj)
	var c := ce(li, lj)
	var is_pool := pool[li + lj * W] == 1
	if solid[li + lj * W] == 1:
		return
	var fr := PackedFloat32Array()
	for k in SUB + 1:
		fr.push_back(float(k) / SUB)
	# Floor and ceiling (cell centre is the reference for _nudge()).
	_cur_cell = Vector2(xa + CELL * 0.5, za + CELL * 0.5)
	_grid(FLOOR_MAT[b], Vector3(xa, f, za), Vector3(CELL, 0, 0), Vector3(0, 0, CELL), fr, fr,
			Vector3.UP, Vector3.RIGHT, 0, 1, f, c, LM_TEXEL)
	var cr := PackedFloat32Array([0.0, 0.5, 1.0])
	_grid(CEIL_MAT[b], Vector3(xa, c, za), Vector3(CELL, 0, 0), Vector3(0, 0, CELL), cr, cr,
			Vector3.DOWN, Vector3.RIGHT, 0, 1, f, c, LM_TEXEL_CEIL)
	_col_quad(Vector3(xa, f, za), Vector3(xa + CELL, f, za), Vector3(xa + CELL, f, za + CELL), Vector3(xa, f, za + CELL))
	if is_pool:
		var half := PackedFloat32Array([0.0, 0.5, 1.0])
		_grid(MAT_WATER, Vector3(xa, WorldGen.WATER_Y, za), Vector3(CELL, 0, 0), Vector3(0, 0, CELL), half, half,
				Vector3.UP, Vector3.RIGHT, 0, 1, f, c)
	# Light fixture.
	var s := gen.light_state(gx, gz, b)
	if s == WorldGen.L_SKY:
		_emit_skylight(xa + CELL * 0.5, za + CELL * 0.5, f, c)
	elif s != WorldGen.L_NONE:
		var sz: Vector2 = PANEL_SIZE[b]
		var cx := xa + CELL * 0.5
		var cz := za + CELL * 0.5
		var y := c - 0.012
		var emit := Color(0.05, 0.05, 0.05, 0.0)
		var sd := 0.0
		if s != WorldGen.L_DEAD:
			var lc: Color = WorldGen.LIGHT_COLOR[b] * (WorldGen.LIGHT_POWER[b] * EMIT_SCALE)
			emit = Color(lc.r, lc.g, lc.b, 0.0)
			if s == WorldGen.L_FLICKER:
				sd = gen.light_seed(gx, gz)
		var pb := buf(MAT_LIGHT)
		var st := pb.v.size()
		var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
		for k in 4:
			var o: Vector2 = corners[k]
			pb.add(Vector3(cx + o.x * sz.x * 0.5, y, cz + o.y * sz.y * 0.5), Vector3.DOWN, Vector3.RIGHT,
					Vector2((o.x + 1.0) * 0.5, (o.y + 1.0) * 0.5) * sz, Vector2(sd, 1.0 if s != WorldGen.L_DEAD else 0.0), emit)
		_tri_quad(pb, st, st + 1, st + 2, st + 3, Vector3(1, 0, 0).cross(Vector3(0, 0, 1)).dot(Vector3.DOWN) > 0.0)
		if s != WorldGen.L_DEAD:
			_emit_halo(Vector3(cx, y - 0.05, cz), emit, sd, HALO_SIZE[b])
	# Props.
	if b == WorldGen.PIPES:
		_emit_pipes(li, lj, xa, za, c)
	if b == WorldGen.CONCRETE and not is_pool and not gen.near_spawn(gx, gz, 2) and gen.rnd(gx, gz, 61) < 0.06:
		_emit_crates(li, lj, xa, za, f, c)


func _emit_crates(li: int, lj: int, xa: float, za: float, f: float, c: float) -> void:
	var gx := rx0 + li
	var gz := rz0 + lj
	var count := 1 + int(gen.rnd(gx, gz, 62) * 3.0)
	for k in count:
		var sx := 0.7 + 0.5 * gen.rnd(gx, gz, 63 + k)
		var sz := 0.6 + 0.5 * gen.rnd(gx, gz, 66 + k)
		var sy := 0.5 + 0.5 * gen.rnd(gx, gz, 69 + k)
		var ox := 0.35 + (CELL - 0.7 - sx) * gen.rnd(gx, gz, 72 + k)
		var oz := 0.35 + (CELL - 0.7 - sz) * gen.rnd(gx, gz, 75 + k)
		var y0 := f
		if k == 2:
			y0 = f + 0.5
		_emit_box(MAT_CRATE, Vector3(xa + ox, y0, za + oz), Vector3(xa + ox + sx, y0 + sy, za + oz + sz), f, c, true)
		_col_box(Vector3(xa + ox, y0, za + oz), Vector3(xa + ox + sx, y0 + sy, za + oz + sz))


func _emit_box(mat: int, lo: Vector3, hi: Vector3, f: float, c: float, top: bool) -> void:
	_vface(mat, 0, lo.x, -1.0, lo.z, hi.z, lo.y, hi.y, f, c)
	_vface(mat, 0, hi.x, 1.0, lo.z, hi.z, lo.y, hi.y, f, c)
	_vface(mat, 2, lo.z, -1.0, lo.x, hi.x, lo.y, hi.y, f, c)
	_vface(mat, 2, hi.z, 1.0, lo.x, hi.x, lo.y, hi.y, f, c)
	if top:
		_hface(mat, lo.x, hi.x, lo.z, hi.z, hi.y, true, 1, false)


# ------------------------------------------------------------------ edges ---

## Vertical edge on line x = li (between cells li-1 and li) at row lj.
func _emit_edge_v(li: int, lj: int) -> void:
	var e := edge_v(li, lj)
	var xw := (rx0 + li) * CELL
	var z0 := (rz0 + lj) * CELL
	var ia := li - 1
	var ib := li
	var fa := fl(ia, lj)
	var fb := fl(ib, lj)
	if e == WorldGen.E_OPEN:
		if absf(fa - fb) > 0.01:
			# Pool rim facing the lower side.
			var low_is_a := fa < fb
			var lo := minf(fa, fb)
			var hi := maxf(fa, fb)
			var b := bio(ia if low_is_a else ib, lj)
			_vface(WALL_MAT[b], 0, xw, -1.0 if low_is_a else 1.0, z0, z0 + CELL, lo, hi, lo, hi + 3.0)
			_col_quad(Vector3(xw, lo, z0), Vector3(xw, lo, z0 + CELL), Vector3(xw, hi, z0 + CELL), Vector3(xw, hi, z0))
			if gen.rnd(rx0 + li, rz0 + lj, 91) < 0.2:
				_emit_ladder(0, xw, -1.0 if low_is_a else 1.0, z0 + CELL * 0.5, lo, hi)
		return
	_emit_wall(0, xw, z0, e, bio(ia, lj), bio(ib, lj), fa, fb, ce(ia, lj), ce(ib, lj))


## Horizontal edge on line z = lj (between cells lj-1 and lj) at column li.
func _emit_edge_h(li: int, lj: int) -> void:
	var e := edge_h(li, lj)
	var zw := (rz0 + lj) * CELL
	var x0 := (rx0 + li) * CELL
	var ja := lj - 1
	var jb := lj
	var fa := fl(li, ja)
	var fb := fl(li, jb)
	if e == WorldGen.E_OPEN:
		if absf(fa - fb) > 0.01:
			var low_is_a := fa < fb
			var lo := minf(fa, fb)
			var hi := maxf(fa, fb)
			var b := bio(li, ja if low_is_a else jb)
			_vface(WALL_MAT[b], 2, zw, -1.0 if low_is_a else 1.0, x0, x0 + CELL, lo, hi, lo, hi + 3.0)
			_col_quad(Vector3(x0, lo, zw), Vector3(x0 + CELL, lo, zw), Vector3(x0 + CELL, hi, zw), Vector3(x0, hi, zw))
			if gen.rnd(rx0 + li, rz0 + lj, 92) < 0.2:
				_emit_ladder(2, zw, -1.0 if low_is_a else 1.0, x0 + CELL * 0.5, lo, hi)
		return
	_emit_wall(2, zw, x0, e, bio(li, ja), bio(li, jb), fa, fb, ce(li, ja), ce(li, jb))


## A wall segment lying on plane `plane` of the given axis, starting at `s0`
## along the other axis. Side A is the negative side, B the positive one.
func _emit_wall(axis: int, plane: float, s0: float, e: int, ba: int, bb: int, fa: float, fb: float, ca: float, cb: float) -> void:
	var a0 := s0 + T
	var a1 := s0 + CELL - T
	var bottom := minf(fa, fb)
	var top := maxf(ca, cb)
	var sides := [[-1.0, plane - T, ba, fa, ca], [1.0, plane + T, bb, fb, cb]]
	if e == WorldGen.E_WALL:
		for sd in sides:
			_vface(WALL_MAT[sd[2]], axis, sd[1], sd[0], a0, a1, sd[3], sd[4], sd[3], sd[4])
			if (sd[2] == WorldGen.LOBBY or sd[2] == WorldGen.DARK) and gen.rnd(floori(plane * 10.0), floori(s0 * 10.0) + int(sd[0]), 93) < 0.08:
				var at := s0 + 0.4 + 1.6 * gen.rnd(floori(plane * 10.0), floori(s0 * 10.0), 94)
				_emit_outlet(axis, sd[1], sd[0], at, sd[3] + 0.32)
		_col_wall(axis, plane, a0 - T, a1 + T, bottom, top)
		return
	var w: float = WorldGen.DOOR_W[e]
	var mid := s0 + CELL * 0.5
	var o0 := mid - w * 0.5
	var o1 := mid + w * 0.5
	var yb := maxf(fa, fb)
	var yt := minf(yb + WorldGen.DOOR_H[e], minf(ca, cb) - 0.05)
	if e == WorldGen.E_ARCH:
		_emit_arch(axis, plane, a0, a1, o0, o1, yb, yt, sides, bb, bottom, top)
		return
	for sd in sides:
		var m: int = WALL_MAT[sd[2]]
		var f: float = sd[3]
		var c: float = sd[4]
		_vface(m, axis, sd[1], sd[0], a0, o0, f, c, f, c)
		_vface(m, axis, sd[1], sd[0], o1, a1, f, c, f, c)
		_vface(m, axis, sd[1], sd[0], o0, o1, yt, c, f, c)
		_vface(m, axis, sd[1], sd[0], o0, o1, f, yb, f, c)
	# Door reveals (jamb sides), lintel underside, sill top.
	var other := 2 if axis == 0 else 0
	var mr: int = WALL_MAT[bb]
	_vface(mr, other, o0, 1.0, plane - T, plane + T, yb, yt, yb, yt + 0.6)
	_vface(mr, other, o1, -1.0, plane - T, plane + T, yb, yt, yb, yt + 0.6)
	# Sill: only where the floors differ, and only over the lower side. The
	# floors already reach the wall line, so a full-width sill would sit
	# exactly on them and z-fight (jagged strips in doorways).
	var sill := absf(fa - fb) > 0.01
	var s_lo := plane - T if fa < fb else plane
	var s_hi := plane if fa < fb else plane + T
	if axis == 0:
		_hface(mr, plane - T, plane + T, o0, o1, yt, false, 1, false)
		if sill:
			_hface(FLOOR_MAT[bb], s_lo, s_hi, o0, o1, yb, true, 1, false)
	else:
		_hface(mr, o0, o1, plane - T, plane + T, yt, false, 1, false)
		if sill:
			_hface(FLOOR_MAT[bb], o0, o1, s_lo, s_hi, yb, true, 1, false)
	_col_wall(axis, plane, a0 - T, o0, bottom, top)
	_col_wall(axis, plane, o1, a1 + T, bottom, top)
	_col_wall(axis, plane, o0, o1, yt, top)
	if yb > bottom + 0.01:
		_col_wall(axis, plane, o0, o1, bottom, yb)


func _col_wall(axis: int, plane: float, a0: float, a1: float, y0: float, y1: float) -> void:
	if axis == 0:
		_col_box(Vector3(plane - T, y0, a0), Vector3(plane + T, y1, a1))
	else:
		_col_box(Vector3(a0, y0, plane - T), Vector3(a1, y1, plane + T))


# --------------------------------------------------------------- vertices ---

func _emit_vertex(li: int, lj: int) -> void:
	var vx := rx0 + li
	var vz := rz0 + lj
	var px := vx * CELL
	var pz := vz * CELL
	var n_v := edge_v(li, lj - 1)
	var s_v := edge_v(li, lj)
	var w_h := edge_h(li - 1, lj)
	var e_h := edge_h(li, lj)
	var f := minf(minf(fl(li - 1, lj - 1), fl(li, lj - 1)), minf(fl(li - 1, lj), fl(li, lj)))
	var c := maxf(maxf(ce(li - 1, lj - 1), ce(li, lj - 1)), maxf(ce(li - 1, lj), ce(li, lj)))
	var b := bio(li, lj)
	var size := gen.pillar_at(vx, vz, b)
	if size < 0.0:
		_emit_column(WALL_MAT[b], px, pz, -size * 0.5, f, c)
		var hr := -size * 0.42
		_col_box(Vector3(px - hr, f, pz - hr), Vector3(px + hr, c, pz + hr))
		return
	if size > 0.0:
		var h := size * 0.5
		var m: int = WALL_MAT[b]
		# Use each face's own floor/ceiling so faces never poke through.
		_vface(m, 0, px - h, -1.0, pz - h, pz + h, f, c, f, c)
		_vface(m, 0, px + h, 1.0, pz - h, pz + h, f, c, f, c)
		_vface(m, 2, pz - h, -1.0, px - h, px + h, f, c, f, c)
		_vface(m, 2, pz + h, 1.0, px - h, px + h, f, c, f, c)
		_col_box(Vector3(px - h, f, pz - h), Vector3(px + h, c, pz + h))
		return
	if n_v == 0 and s_v == 0 and w_h == 0 and e_h == 0:
		return
	var m2: int = WALL_MAT[b]
	if w_h == 0:
		_vface(m2, 0, px - T, -1.0, pz - T, pz + T, f, c, f, c)
	if e_h == 0:
		_vface(m2, 0, px + T, 1.0, pz - T, pz + T, f, c, f, c)
	if n_v == 0:
		_vface(m2, 2, pz - T, -1.0, px - T, px + T, f, c, f, c)
	if s_v == 0:
		_vface(m2, 2, pz + T, 1.0, px - T, px + T, f, c, f, c)


# ------------------------------------------------------------ curved bits ---

## Emits a grid of vertices with individual normals (curved surfaces).
## pos/nrm/uv are row-major with `nu` vertices per row.
func _smooth_grid(mat: int, pos: PackedVector3Array, nrm: PackedVector3Array, uv: PackedVector2Array, nu: int,
		f: float, c: float, ao: bool) -> void:
	var b := buf(mat)
	var start := b.v.size()
	for k in pos.size():
		var p := pos[k]
		var n := nrm[k]
		var light := shade(p + n * 0.05, n)
		if ao:
			var a := _ao_y(p.y, f, c)
			light = Color(light.r * a, light.g * a, light.b * a, light.a)
		var tan := Vector3.UP.cross(n)
		if tan.length_squared() < 0.01:
			tan = Vector3.RIGHT
		b.add(p, n, tan.normalized(), uv[k], Vector2(_seed, 0.0), light)
	var nv := pos.size() / nu
	if nv < 2 or nu < 2:
		return
	var geo := (pos[1] - pos[0]).cross(pos[nu] - pos[0])
	var flip := geo.dot(nrm[0] + nrm[nu + 1]) > 0.0
	for jv in nv - 1:
		for iu in nu - 1:
			var a := start + iu + jv * nu
			_tri_quad(b, a, a + 1, a + 1 + nu, a + nu, flip)


## Round tiled column (Poolrooms).
func _emit_column(mat: int, cx: float, cz: float, r: float, f: float, c: float) -> void:
	var segs := 14
	var ys := _rows(f, c)
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for y_frac in ys:
		var y := lerpf(f, c, y_frac)
		for k in segs + 1:
			var a := TAU * k / segs
			var n := Vector3(cos(a), 0.0, sin(a))
			pos.push_back(Vector3(cx, y, cz) + n * r)
			nrm.push_back(n)
			uv.push_back(Vector2(a * r, -y))
	_smooth_grid(mat, pos, nrm, uv, segs + 1, f, c, true)


## Tube swept along a polyline (pool ladders, pipes).
func _tube(mat: int, path: PackedVector3Array, r: float, segs: int, f: float, c: float) -> void:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var dist := 0.0
	for i in path.size():
		var t: Vector3
		if i == 0:
			t = path[1] - path[0]
		elif i == path.size() - 1:
			t = path[i] - path[i - 1]
		else:
			t = path[i + 1] - path[i - 1]
		t = t.normalized()
		if i > 0:
			dist += path[i].distance_to(path[i - 1])
		var ref := Vector3.UP if absf(t.y) < 0.9 else Vector3.RIGHT
		var u := t.cross(ref).normalized()
		var v := t.cross(u).normalized()
		for k in segs + 1:
			var a := TAU * k / segs
			var n := u * cos(a) + v * sin(a)
			pos.push_back(path[i] + n * r)
			nrm.push_back(n)
			uv.push_back(Vector2(dist, a * r))
	_smooth_grid(mat, pos, nrm, uv, segs + 1, f, c, false)


## Maps (along, y, offset-from-plane) to world space for a wall on `axis`.
static func _wp(axis: int, plane: float, along: float, y: float, off: float) -> Vector3:
	return Vector3(plane + off, y, along) if axis == 0 else Vector3(along, y, plane + off)


func _quad4(mat: int, a: Vector3, b2: Vector3, c2: Vector3, d: Vector3, nrm: Vector3, uv_mode: int, f: float, c: float) -> void:
	var b := buf(mat)
	var start := b.v.size()
	for p in [a, b2, c2, d]:
		var light := shade(p + nrm * 0.05, nrm)
		var ao := _ao_y(p.y, f, c)
		light = Color(light.r * ao, light.g * ao, light.b * ao, light.a)
		var t: Vector2
		match uv_mode:
			0:
				t = Vector2(p.x, p.z)
			1:
				t = Vector2(p.z, -p.y)
			_:
				t = Vector2(p.x, -p.y)
		var tan := Vector3.UP.cross(nrm)
		if tan.length_squared() < 0.01:
			tan = Vector3.RIGHT
		b.add(p, nrm, tan.normalized(), t, Vector2(_seed, 0.0), light)
	_tri_quad(b, start, start + 1, start + 2, start + 3, (b2 - a).cross(d - a).dot(nrm) > 0.0)


## Doorway with a semicircular top and a curved soffit.
func _emit_arch(axis: int, plane: float, a0: float, a1: float, o0: float, o1: float, yb: float, yt: float,
		sides: Array, bb: int, bottom: float, top: float) -> void:
	var r := (o1 - o0) * 0.5
	var mid := (o0 + o1) * 0.5
	var ys := yt - r
	var n := 10
	var uvm := 1 if axis == 0 else 2
	for sd in sides:
		var m: int = WALL_MAT[sd[2]]
		var f: float = sd[3]
		var c: float = sd[4]
		var sgn: float = sd[0]
		var pl: float = sd[1]
		_vface(m, axis, pl, sgn, a0, o0, f, c, f, c)
		_vface(m, axis, pl, sgn, o1, a1, f, c, f, c)
		_vface(m, axis, pl, sgn, o0, o1, f, yb, f, c)
		var nrm := Vector3(sgn, 0, 0) if axis == 0 else Vector3(0, 0, sgn)
		for k in n:
			var t0 := PI - PI * k / n
			var t1 := PI - PI * (k + 1) / n
			var x0 := mid + cos(t0) * r
			var x1 := mid + cos(t1) * r
			var y0 := ys + sin(t0) * r
			var y1 := ys + sin(t1) * r
			_quad4(m, _wp(axis, pl, 0, y0, 0) + _wp(axis, 0, x0, 0, 0), _wp(axis, pl, 0, y1, 0) + _wp(axis, 0, x1, 0, 0),
					_wp(axis, pl, 0, c, 0) + _wp(axis, 0, x1, 0, 0), _wp(axis, pl, 0, c, 0) + _wp(axis, 0, x0, 0, 0), nrm, uvm, f, c)
	# Jamb reveals up to the spring line, then the curved soffit.
	var other := 2 if axis == 0 else 0
	var mr: int = WALL_MAT[bb]
	_vface(mr, other, o0, 1.0, plane - T, plane + T, yb, ys, yb, yt)
	_vface(mr, other, o1, -1.0, plane - T, plane + T, yb, ys, yb, yt)
	for k in n:
		var t0 := PI - PI * k / n
		var t1 := PI - PI * (k + 1) / n
		var tm := (t0 + t1) * 0.5
		var x0 := mid + cos(t0) * r
		var x1 := mid + cos(t1) * r
		var y0 := ys + sin(t0) * r
		var y1 := ys + sin(t1) * r
		var inward := Vector3(0, -sin(tm), 0) + _wp(axis, 0, -cos(tm), 0, 0) * Vector3(1, 0, 1)
		inward = inward.normalized()
		_quad4(mr, _wp(axis, plane, x0, y0, -T), _wp(axis, plane, x1, y1, -T), _wp(axis, plane, x1, y1, T),
				_wp(axis, plane, x0, y0, T), inward, 0, yb, yt + 1.0)
	# Sill only where the floors differ (see _emit_wall), over the lower side.
	var fa: float = sides[0][3]
	var fb: float = sides[1][3]
	if absf(fa - fb) > 0.01:
		var s_lo := plane - T if fa < fb else plane
		var s_hi := plane if fa < fb else plane + T
		if axis == 0:
			_hface(FLOOR_MAT[bb], s_lo, s_hi, o0, o1, yb, true, 1, false)
		else:
			_hface(FLOOR_MAT[bb], o0, o1, s_lo, s_hi, yb, true, 1, false)
	_col_wall(axis, plane, a0 - T, o0, bottom, top)
	_col_wall(axis, plane, o1, a1 + T, bottom, top)
	_col_wall(axis, plane, o0, o1, ys + r * 0.6, top)
	if yb > bottom + 0.01:
		_col_wall(axis, plane, o0, o1, bottom, yb)


## Chrome pool ladder hooked over a rim. `dir` points from the rim into the pool.
func _emit_ladder(axis: int, plane: float, dir: float, along: float, lo: float, hi: float) -> void:
	var prof := [Vector2(0.16, lo + 0.08), Vector2(0.16, hi + 0.55), Vector2(0.12, hi + 0.78), Vector2(0.0, hi + 0.86),
		Vector2(-0.12, hi + 0.8), Vector2(-0.24, hi + 0.62), Vector2(-0.28, hi + 0.35), Vector2(-0.29, hi)]
	for side in [-0.26, 0.26]:
		var path := PackedVector3Array()
		for q in prof:
			path.push_back(_wp(axis, plane, along + side, q.y, q.x * dir))
		_tube(MAT_CHROME, path, 0.024, 8, lo, hi + 1.0)
	for k in 3:
		var y := lo + 0.2 + k * 0.22
		var path2 := PackedVector3Array([_wp(axis, plane, along - 0.26, y, 0.14 * dir), _wp(axis, plane, along + 0.26, y, 0.14 * dir)])
		_tube(MAT_CHROME, path2, 0.02, 6, lo, hi + 1.0)


## Small wall socket plate.
func _emit_outlet(axis: int, plane_face: float, sgn: float, along: float, y: float) -> void:
	var off := sgn * 0.012
	var hw := 0.04
	var hh := 0.065
	var nrm := Vector3(sgn, 0, 0) if axis == 0 else Vector3(0, 0, sgn)
	var uvm := 1 if axis == 0 else 2
	var p := plane_face
	_quad4(MAT_OUTLET, _wp(axis, p, along - hw, y - hh, off), _wp(axis, p, along + hw, y - hh, off),
			_wp(axis, p, along + hw, y + hh, off), _wp(axis, p, along - hw, y + hh, off), nrm, uvm, 0.0, 2.7)


## Skylight: a bright opening pouring warm "sunlight" into the room.
func _emit_skylight(cx: float, cz: float, _f: float, c: float) -> void:
	var h := SKY_SIZE * 0.5
	var pb := buf(MAT_LIGHT)
	var st := pb.v.size()
	var lc := WorldGen.SKY_COLOR * (WorldGen.SKY_POWER * EMIT_SCALE * 1.4)
	var emit := Color(lc.r, lc.g, lc.b, 0.0)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var o: Vector2 = corners[k]
		pb.add(Vector3(cx + o.x * h, c - 0.01, cz + o.y * h), Vector3.DOWN, Vector3.RIGHT,
				(o + Vector2.ONE) * h, Vector2(0.0, 1.0), emit)
	_tri_quad(pb, st, st + 1, st + 2, st + 3, true)
	_emit_halo(Vector3(cx, c - 0.1, cz), emit * 0.6, 0.0, 5.0)


## Service pipes running along every wall of a Pipe Dreams corridor.
func _emit_pipes(li: int, lj: int, xa: float, za: float, c: float) -> void:
	# [edge kind, axis, plane, direction into corridor]
	var walls := [
		[edge_v(li, lj), 0, xa, 1.0], [edge_v(li + 1, lj), 0, xa + CELL, -1.0],
		[edge_h(li, lj), 2, za, 1.0], [edge_h(li, lj + 1), 2, za + CELL, -1.0],
	]
	for w in walls:
		if w[0] != WorldGen.E_WALL:
			continue
		var axis: int = w[1]
		var plane: float = w[2]
		var dir: float = w[3]
		var s0 := za if axis == 0 else xa
		var line := floori(plane / CELL + 0.5)
		var big := [[0.11, c - 0.32, T + 0.14], [0.065, c - 0.6, T + 0.1]]
		if gen.rnd(line, floori(s0 / CELL / 4.0), 95 + axis) < 0.6:
			big.append([0.13, 0.3, T + 0.16])
		for pp in big:
			var r: float = pp[0]
			var y: float = pp[1]
			var o: float = (pp[2] as float) * dir
			_tube(MAT_PIPE, PackedVector3Array([_wp(axis, plane, s0 - 0.02, y, o), _wp(axis, plane, s0 + CELL + 0.02, y, o)]), r, 8, 0.0, c)
			_tube(MAT_PIPE, PackedVector3Array([_wp(axis, plane, s0 + 0.02, y, o), _wp(axis, plane, s0 + 0.1, y, o)]), r * 1.3, 8, 0.0, c)


## Camera-facing glow quad (expanded in light_halo.gdshader).
func _emit_halo(centre: Vector3, col: Color, sd: float, size: float) -> void:
	var hb := buf(MAT_HALO)
	var st := hb.v.size()
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		hb.add(centre, Vector3.DOWN, Vector3.RIGHT, uv, Vector2(sd, size), col)
	hb.idx.append_array([st, st + 1, st + 2, st, st + 2, st + 3])
