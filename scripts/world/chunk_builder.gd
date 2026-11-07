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
const T := 0.15                  # half wall thickness (30 cm walls, as in the 2002 photo)
const SPACING := 1.2             # target vertex spacing on walls
## Per-pixel lightmaps (off in the Potato preset: cheaper generation).
static var lightmaps := true
## Pool water grid per cell (displaceable by ripples); 4 in Potato.
static var water_sub := 16
## Volumetric-looking sun shafts in the sun galleries (off in Potato).
static var god_rays := true
## Lightmap texel spacing multiplier (smaller is sharper, but slower to
## bake and heavier; no preset changes it).
static var lm_scale := 1.0
## Realistic: bake corner occlusion on walls too.
static var wall_ao := false
## Realistic: trim geometry (skirting boards, door casings, the ceiling's
## T-bar grid, light fittings with a rim).
static var detail := false
## Also bake which way the light comes from (directional lightmap), so
## normal-mapped detail responds to the baked light. Only the shaders'
## `photoreal` paths read it, which no preset turns on (too heavy per pixel
## for phones), so it stays off.
static var dir_lm := false
## Realistic: two-bounce radiosity on the cell grid (see _compute_gi) instead
## of the fake bounce term.
static var gi := false
## Realistic: a cheap camera's view of the light. Stronger falloff between
## the lamps (bright under a troffer, darker halfway to the next), less
## ambient fill and deeper contact shadows where walls meet floor and
## ceiling and in corners. All baked, nothing at draw time.
static var contrast := false
## Glow quads around the light fixtures (light_halo.gdshader); off, none are
## built, so nothing reads the depth buffer.
static var halos := true
## L.U.C.I.D. (Realistic, see Lucid and docs/LUCID.md): every fixture emits
## its real flux (WorldGen.LUCID_FIXTURE), the bake stores illuminance in
## engine units (Lucid.lux_to_engine), bounce light comes only from the
## radiosity (gi, needed) with all bounces, and contact occlusion darkens
## only the bounce light. Replaces `contrast` and the fake ambient/bounce.
static var lucid := false
## Lucid: how far a fixture's light is gathered (m). Must stay within the
## chunk margin (M + 0.5 cells) so neighbouring chunks agree at the seams.
const LUCID_RADIUS := 9.5
## Lucid stage 2, relightable bake: each lightmapped face keeps up to SLOTS
## switchable (flickering) lamps apart from the rest of its light. The
## lightmap holds the light with every lamp on (rgb) and the share of slot 0
## (alpha); the lightmap_seed texture holds the shares of slots 1 and 2
## (RG8); the face's vertices carry the slots' lamp indices (CUSTOM0). A
## lamp's share is its direct light plus its own bounce light, so the walls,
## ceiling and carpet round a flickering lamp dim with it. Lamp index =
## (gx & 127) + 128 (gz & 127), a texel of the lamp state texture
## (ChunkManager, `lucid_lamps`).
const SLOTS := 3
const LAMP_GRID := 128
## Lucid: the radiosity gathers patches exactly (subdivided form factors)
## within GI_NEAR cells of a probe; the solid angle left over (open halls
## going on beyond) is filled with the radiance of the outermost ring.
const GI_NEAR := 3
## Lucid: direct light from beyond the per-texel window (LUCID_RADIUS) as an
## analytic tail: the local fixture density carried on to infinity in each
## of TAIL_SECTORS directions that are open, per cell at two heights.
const TAIL_SECTORS := 16
## Diagnostics: lamp cells left out of the bake (as if dead), for checking
## the runtime slots against an exact rebake (_test/lucid_shots.gd PROBE=1).
static var kill_cells := []
const LM_W := 256                # lightmap atlas width (texels)
const LM_TEXEL := 0.4            # lightmap texel spacing on floors and walls (m)
const LM_TEXEL_CEIL := 0.8       # ... on ceilings (lit from below, smooth anyway)
const LM_TEXEL_SUN := 0.15       # ... on sun gallery floors (sharp sun patches)

enum {
	MAT_WALLPAPER, MAT_CARPET, MAT_CEILING_TILE, MAT_POOL_TILE, MAT_WATER,
	MAT_CONC_WALL, MAT_CONC_FLOOR, MAT_CONC_CEIL, MAT_LIGHT, MAT_CRATE,
	MAT_CHROME, MAT_SHAFT, MAT_PIPE, MAT_BRICK, MAT_GRIME, MAT_OUTLET, MAT_HALO, MAT_TRIM, MAT_GARAGE_FLOOR, MAT_GARAGE_COLUMN, MAT_BLOCK_WALL, MAT_RACK, MAT_COUNT
}
## Materials whose shaders read the per-chunk lightmap.
const LIGHTMAPPED := [MAT_WALLPAPER, MAT_CARPET, MAT_CEILING_TILE, MAT_POOL_TILE, MAT_CONC_WALL,
		MAT_CONC_FLOOR, MAT_CONC_CEIL, MAT_BRICK, MAT_GRIME, MAT_GARAGE_FLOOR, MAT_GARAGE_COLUMN, MAT_BLOCK_WALL]
const WALL_MAT := [MAT_WALLPAPER, MAT_POOL_TILE, MAT_BLOCK_WALL, MAT_WALLPAPER, MAT_GRIME, MAT_CONC_WALL]
const FLOOR_MAT := [MAT_CARPET, MAT_POOL_TILE, MAT_CONC_FLOOR, MAT_CARPET, MAT_BRICK, MAT_GARAGE_FLOOR]
const CEIL_MAT := [MAT_CEILING_TILE, MAT_POOL_TILE, MAT_CONC_CEIL, MAT_CEILING_TILE, MAT_GRIME, MAT_CONC_CEIL]
const PANEL_SIZE := [Vector2(1.22, 0.62), Vector2(0.62, 0.62), Vector2(1.7, 0.24), Vector2(1.22, 0.62), Vector2(0.6, 0.6), Vector2(1.3, 0.12)]
const SKY_SIZE := 1.8
const HALO_SIZE := [1.2, 1.5, 1.6, 1.2, 1.1, 1.0]
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
var _lightmaps: bool
var _water_sub: int
var _god_rays: bool
var _lm_scale: float
var _wall_ao: bool
var _contrast: bool
var _halos: bool
var _detail: bool
var _dir_lm: bool
var _gi: bool
var _lucid: bool
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
var lexp := PackedFloat32Array()      # Lucid: cos^m exponent of each light's distribution
var lid := PackedInt32Array()         # Lucid: lamp state texel of a switchable light, -1 = steady
var _swv_d := PackedFloat32Array()    # Lucid: per light, its direct part of the last shade() (r+g+b), switchable lights only
var _swv_b := PackedFloat32Array()    # ... and its bounce part
var _swl := PackedInt32Array()        # ... the lights set in them
var _face_ids := Color()              # Lucid: the slot lamp indices of the face just baked
var _fmap := PackedInt32Array()       # Lucid: light -> its place in the face being baked, -1 = none
var _ind := Color()                   # Lucid: the bounce part of the last shade()
var cand := []
var cache := {}
var bufs := []
var col := PackedVector3Array()
var _seed := 0.0
var _cur_cell := Vector2.ZERO
var _no_sun := false
# Lightmap atlas (RGBA half floats, shelf packed, grows downwards).
var lm_bytes := PackedByteArray()
## Per texel: which flickering lamp (seed - 1, 16 bit) its flicker share follows.
var lm_seed_bytes := PackedByteArray()
## Per texel (dir_lm): where the baked light mostly comes from, RGBA8.
var lm_dir_bytes := PackedByteArray()
var _ldir := Vector3.ZERO          # set by shade(): light-weighted direction
# Bounce field (gi): indirect light at the cell corners, (W+1)^2.
var _gi_ready := false
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
	# The settings this chunk is built with. Chunks build on worker threads,
	# and the statics can change (graphics preset) while one is half done.
	_lightmaps = lightmaps
	_water_sub = water_sub
	_god_rays = god_rays
	_lm_scale = lm_scale
	_wall_ao = wall_ao
	_contrast = contrast
	_halos = halos
	_detail = detail
	_dir_lm = dir_lm
	_gi = gi
	_lucid = lucid and gi
	if _lucid:
		_contrast = false
	rx0 = coord.x * N - M
	rz0 = coord.y * N - M


# -------------------------------------------------------------- accessors ---

func bio(i: int, j: int) -> int:
	return biome[(i + 1) + (j + 1) * (W + 2)]


func edge_v(lx: int, lz: int) -> int:
	if lx < 0 or lx > W or lz < 0 or lz >= W:
		return _edge_far(true, lx, lz)
	return ev[lx + lz * (W + 1)]


func edge_h(lx: int, lz: int) -> int:
	if lx < 0 or lx >= W or lz < 0 or lz > W:
		return _edge_far(false, lx, lz)
	return eh[lx + lz * W]


var _far_edges := {}

## Edges outside the chunk's margin: open, except for Lucid, whose far
## light traces (_compute_tail) look further: asked of WorldGen and cached.
func _edge_far(vert: bool, lx: int, lz: int) -> int:
	if not _lucid:
		return 0
	var key := Vector3i(lx, lz, 1 if vert else 0)
	if _far_edges.has(key):
		return _far_edges[key]
	var gx := rx0 + lx
	var gz := rz0 + lz
	var e: int
	if vert:
		e = gen.edge_kind(gx, gz, true, gen.biome_at(gx - 1, gz), gen.biome_at(gx, gz))
	else:
		e = gen.edge_kind(gz, gx, false, gen.biome_at(gx, gz - 1), gen.biome_at(gx, gz))
	_far_edges[key] = e
	return e


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
	if _gi and _lightmaps:
		_compute_gi()
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
	var out := {"coord": coord, "surfaces": surfaces, "collision": col, "lightmap": _lm_image(), "lightmap_seed": _lm_seed_image()}
	if _dir_lm:
		out["lightmap_dir"] = _lm_dir_image()
	if _lucid and _gi_ready:
		out["probes"] = _interior_probes()
		_light_grid(out)
	if _lucid:
		# The switchable lamps this chunk's light depends on: gx, gz, seed.
		var lamps := PackedFloat32Array()
		for k in lpos.size():
			if lid[k] >= 0:
				lamps.append_array([floorf(lpos[k].x / CELL), floorf(lpos[k].z / CELL), lseed[k]])
		out["lamps"] = lamps
	return out


## Lucid: the light arriving at each of this chunk's cells from each axis
## direction (the radiosity's ambient cubes, E / pi in engine units, which
## is also the mean luminance seen looking that way): N x N x 6, for the
## camera's metering and for lighting things that move (ChunkManager.light_probe).
func _interior_probes() -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(N * N * 6)
	for j in N:
		for i in N:
			var k := (M + i) + (M + j) * W
			for f in 6:
				out[(i + j * N) * 6 + f] = _probe[k * 6 + f] if k * 6 + f < _probe.size() else Color(0, 0, 0)
	return out


## Lucid: the probe grid for things that move (stage 2). Per chunk cell, two
## points (GRID_Y above the floor: knee and head height), each an ambient
## cube of all the light arriving there (+x -x +y -y +z -z, E / pi in engine
## units): direct from the fixtures it can see, the far tail and the bounce.
## Also the two switchable lamps that give it most, as a lamp index and
## their share of each of the 12 values (`grid_slots`, 26 floats per cell),
## and which sides of the cell are walled (`grid_walls`: 1 W, 2 E, 4 N, 8 S),
## so sampling never blends through a wall (ChunkManager.light_cube).
const GRID_Y := [0.5, 1.7]


func _light_grid(out: Dictionary) -> void:
	var grid := PackedColorArray()
	grid.resize(N * N * 12)
	var slots := PackedFloat32Array()
	slots.resize(N * N * 26)
	var walls := PackedByteArray()
	walls.resize(N * N)
	var floors := PackedFloat32Array()
	floors.resize(N * N)
	var zero := Color(0, 0, 0)
	for j in N:
		for i in N:
			var li := M + i
			var lj := M + j
			var k := li + lj * W
			var ci := i + j * N
			walls[ci] = (1 if edge_v(li, lj) == WorldGen.E_WALL else 0) | (2 if edge_v(li + 1, lj) == WorldGen.E_WALL else 0) \
					| (4 if edge_h(li, lj) == WorldGen.E_WALL else 0) | (8 if edge_h(li, lj + 1) == WorldGen.E_WALL else 0)
			floors[ci] = fl(li, lj)
			if solid[k] == 1:
				continue
			var lam := {}       # light -> 12 floats (r+g+b per value)
			var tot := PackedFloat32Array()
			tot.resize(12)
			for lv in 2:
				var p := Vector3((rx0 + li + 0.5) * CELL, fl(li, lj) + GRID_Y[lv], (rz0 + lj + 0.5) * CELL)
				var cube := [zero, zero, zero, zero, zero, zero]
				for l in _candidates(li, lj):
					var d := lpos[l] - p
					var d2 := d.length_squared()
					var dd := sqrt(d2)
					if dd >= lrad[l]:
						continue
					var m := lexp[l]
					var cosr := d.y / dd
					if m > 0.0 and cosr <= 0.0:
						continue
					if not _visible(lpos[l].x / CELL - rx0, lpos[l].z / CELL - rz0, lpos[l].y, li + 0.5, lj + 0.5, p.y):
						continue
					var e := (pow(cosr, m) if m > 0.0 else 1.0) / maxf(d2, 0.04) * (1.0 - smoothstep(lrad[l] * 0.75, lrad[l], dd))
					var dn := d / dd
					var w := [maxf(dn.x, 0.0), maxf(-dn.x, 0.0), maxf(dn.y, 0.0), maxf(-dn.y, 0.0), maxf(dn.z, 0.0), maxf(-dn.z, 0.0)]
					var c := lcol[l] * e
					var cs := c.r + c.g + c.b
					for a in 6:
						cube[a] += c * w[a]
					if lid[l] >= 0:
						if not lam.has(l):
							var z := PackedFloat32Array()
							z.resize(12)
							lam[l] = z
						var arr: PackedFloat32Array = lam[l]
						for a in 6:
							arr[lv * 6 + a] += cs * w[a]
						lam[l] = arr
				var tf := _lv_t(k, p.y, true)
				var tb := _lv_t(k, p.y, false)
				for a in 6:
					var far := _far[k * 12 + a].lerp(_far[k * 12 + 6 + a], tf)
					var bnc := _gi2[k * 12 + a].lerp(_gi2[k * 12 + 6 + a], tb)
					cube[a] += far + bnc
					grid[ci * 12 + lv * 6 + a] = cube[a]
					tot[lv * 6 + a] = cube[a].r + cube[a].g + cube[a].b
					# Each switchable lamp's own part of the bounce.
					if _cell_sw[k] != null:
						var grp := 0 if a == 2 else (1 if a == 3 else 2)
						var bl := bnc.r + bnc.g + bnc.b
						for l in _cell_sw[k]:
							if not lam.has(l):
								var z := PackedFloat32Array()
								z.resize(12)
								lam[l] = z
							var arr: PackedFloat32Array = lam[l]
							arr[lv * 6 + a] += bl * _cell_sw[k][l][grp]
							lam[l] = arr
			# The two lamps that give this cell the most light.
			var order := lam.keys()
			var sums := {}
			for l in order:
				var sm := 0.0
				for x in lam[l]:
					sm += x
				sums[l] = sm
			order.sort_custom(func(x, y) -> bool: return sums[x] > sums[y])
			for q in mini(order.size(), 2):
				var l: int = order[q]
				var o := ci * 26 + q * 13
				slots[o] = lid[l]
				for a in 12:
					slots[o + 1 + a] = clampf(lam[l][a] / tot[a], 0.0, 1.0) if tot[a] > 0.0 else 0.0
	out["grid"] = grid
	out["grid_slots"] = slots
	out["grid_walls"] = walls
	out["grid_floor"] = floors


## Diagnostics (Lucid): the illuminance the bake computes at world point
## `p` on a surface facing `nrm`, as {lux, direct, indirect} (lux, the
## luminance-weighted value). Builds the chunk's lights and radiosity, not
## its geometry. `off`: lamp cells switched off as the runtime does it
## (their direct and bounce parts taken out, Lucid only).
static func probe(g: WorldGen, p: Vector3, nrm: Vector3, off := []) -> Dictionary:
	var cb := ChunkBuilder.new(g, ChunkManager.chunk_of(p))
	cb._compute_layout()
	cb._compute_lights()
	if cb._gi:
		cb._compute_gi()
	var c := cb.shade(p + nrm * 0.02, nrm)
	var ind := cb._ind if cb._lucid else Color(0, 0, 0)
	if cb._lucid and not off.is_empty():
		for k in cb.lpos.size():
			if cb.lid[k] >= 0 and off.has(Vector2i(floori(cb.lpos[k].x / CELL), floori(cb.lpos[k].z / CELL))):
				var tl := c.r + c.g + c.b
				var dl: float = cb._swv_d[k]
				var bl: float = cb._swv_b[k]
				if tl > 0.0:
					c = c * (1.0 - (dl + bl) / tl)
				var il := ind.r + ind.g + ind.b
				if il > 0.0:
					ind = ind * (1.0 - bl / il)
	var ku := Lucid.engine_to_lux(1.0) if cb._lucid else 1.0
	return {"lux": Lucid.lum(c) * ku, "direct": (Lucid.lum(c) - Lucid.lum(ind)) * ku, "indirect": Lucid.lum(ind) * ku}


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
		lm_seed_bytes.resize(lm_bytes.size() / 4)
		if _dir_lm:
			lm_dir_bytes.resize(lm_bytes.size() / 2)
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


func _lm_seed_image() -> Image:
	var h := _lm_y + _lm_shelf
	if h == 0:
		return null
	h = (h + 3) & ~3
	var bytes := lm_seed_bytes.slice(0, h * LM_W * 2)
	if bytes.size() < h * LM_W * 2:
		bytes.resize(h * LM_W * 2)
	return Image.create_from_data(LM_W, h, false, Image.FORMAT_RG8, bytes)


func _lm_dir_image() -> Image:
	var h := _lm_y + _lm_shelf
	if h == 0:
		return null
	h = (h + 3) & ~3
	var bytes := lm_dir_bytes.slice(0, h * LM_W * 4)
	if bytes.size() < h * LM_W * 4:
		bytes.resize(h * LM_W * 4)
	return Image.create_from_data(LM_W, h, false, Image.FORMAT_RGBA8, bytes)


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
			if not kill_cells.is_empty() and kill_cells.has(Vector2i(rx0 + i, rz0 + j)):
				s = WorldGen.L_DEAD
			if s == WorldGen.L_SKY:
				light_at[i + j * W] = lpos.size()
				lpos.push_back(Vector3((rx0 + i + 0.5) * CELL, ce(i, j) - 0.03, (rz0 + j + 0.5) * CELL))
				if _lucid:
					var fx: Dictionary = Lucid.FIXTURES.skylight
					lcol.push_back(Lucid.light_engine(fx))
					lexp.push_back(fx.m)
					lrad.push_back(LUCID_RADIUS)
				else:
					lcol.push_back(WorldGen.SKY_COLOR * WorldGen.SKY_POWER)
					lrad.push_back(WorldGen.SKY_RADIUS)
				lseed.push_back(0.0)
				lid.push_back(-1)
			elif s == WorldGen.L_ON or s == WorldGen.L_FLICKER:
				light_at[i + j * W] = lpos.size()
				lpos.push_back(Vector3((rx0 + i + 0.5) * CELL, ce(i, j) - 0.03, (rz0 + j + 0.5) * CELL))
				if _lucid:
					# The fixture's real peak intensity (cd) as E / pi at 1 m.
					var fx: Dictionary = Lucid.FIXTURES[WorldGen.LUCID_FIXTURE[b]]
					lcol.push_back(Lucid.light_engine(fx, WorldGen.LUCID_LLF[b]))
					lexp.push_back(fx.m)
					lrad.push_back(LUCID_RADIUS)
				else:
					lcol.push_back(WorldGen.LIGHT_COLOR[b] * (WorldGen.LIGHT_POWER[b] * WorldGen.LIGHT_REACH[b]))
					lrad.push_back(WorldGen.LIGHT_RADIUS[b])
				lseed.push_back(gen.light_seed(rx0 + i, rz0 + j) if s == WorldGen.L_FLICKER else 0.0)
				lid.push_back(lamp_index(rx0 + i, rz0 + j) if _lucid and s == WorldGen.L_FLICKER else -1)
	_swv_d.resize(lpos.size())
	_swv_b.resize(lpos.size())


## Lucid: a lamp's texel in the lamp state texture.
static func lamp_index(gx: int, gz: int) -> int:
	return (gx & (LAMP_GRID - 1)) + LAMP_GRID * (gz & (LAMP_GRID - 1))


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
				if absf(along - 0.5) * CELL > WorldGen.DOOR_W[e] * 0.5 or y > WorldGen.DOOR_H[e] \
						or (e == WorldGen.E_WINDOW and y < WorldGen.WIN_Y0):
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
				if absf(along - 0.5) * CELL > WorldGen.DOOR_W[e] * 0.5 or y > WorldGen.DOOR_H[e] \
						or (e == WorldGen.E_WINDOW and y < WorldGen.WIN_Y0):
					return false
			cj += sj
			tmz += tdz
	return true


## How far along the segment a to b (as _visible) the first wall or door
## frame stops it, as a fraction (2.0: nothing does).
func _block_t(ax: float, az: float, ay: float, bx: float, bz: float, by: float) -> float:
	var ci := floori(ax)
	var cj := floori(az)
	var steps := absi(floori(bx) - ci) + absi(floori(bz) - cj)
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
		var t := minf(tmx, tmz)
		var e: int
		var along: float
		if tmx < tmz:
			e = edge_v(ci + (1 if si > 0 else 0), cj)
			along = az + dz * t - cj
			ci += si
			tmx += tdx
		else:
			e = edge_h(ci, cj + (1 if sj > 0 else 0))
			along = ax + dx * t - ci
			cj += sj
			tmz += tdz
		if e != 0:
			if e == WorldGen.E_WALL:
				return t
			var y := ay + (by - ay) * t
			if absf(along - 0.5) * CELL > WorldGen.DOOR_W[e] * 0.5 or y > WorldGen.DOOR_H[e] \
					or (e == WorldGen.E_WINDOW and y < WorldGen.WIN_Y0):
				return t
	return 2.0


## Irradiance at a point. rgb = light, a = share coming from a flickering lamp
## (whose seed is left in `_seed`).
func shade(p: Vector3, nrm: Vector3) -> Color:
	if _lucid:
		return _shade_lucid(p, nrm)
	var li := floori(p.x / CELL) - rx0
	var lj := floori(p.z / CELL) - rz0
	_seed = 0.0
	if li < 0 or lj < 0 or li >= W or lj >= W:
		return Color(0.02, 0.02, 0.02, 0.0)
	var b := bio(li, lj)
	var amb: Color = WorldGen.AMBIENT[b]
	var fall := 0.15
	var gain := 1.0
	if _contrast:
		amb *= 0.4
		fall = 0.42
		gain = 1.45
	var bt: Color = WorldGen.BOUNCE_TINT[b]
	var r := amb.r
	var g := amb.g
	var bl := amb.b
	var u := p.x / CELL - rx0
	var v := p.z / CELL - rz0
	var tot := 0.0
	var fl_amt := 0.0
	var fl_best := 0.0
	var dacc := Vector3.ZERO
	var bounce_k := 0.0 if _direct_only else (0.12 if (_gi and _gi_ready) else 1.0)
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
		var att := w / (1.0 + d2 * fall) * gain
		if (not _face_on or _face_vis[k] == 2) and not _visible(lp.x / CELL - rx0, lp.z / CELL - rz0, lp.y, u, v, p.y):
			continue
		var ndl := (nrm.x * dx + nrm.y * dy + nrm.z * dz) / d
		var e := 0.25 + 0.75 * maxf(dy / d, 0.0)
		var direct := maxf(ndl, 0.0) * e * att
		var bounce := att * 0.32 * bounce_k
		var c := lcol[k]
		r += c.r * (direct + bt.r * bounce)
		g += c.g * (direct + bt.g * bounce)
		bl += c.b * (direct + bt.b * bounce)
		var lum := (direct + bounce) * (c.r + c.g + c.b)
		tot += lum
		dacc += Vector3(dx, dy, dz) * (direct * (c.r + c.g + c.b) / d)
		if lseed[k] > 0.0:
			fl_amt += lum
			if lum > fl_best:
				fl_best = lum
				_seed = lseed[k]
	if b == WorldGen.POOL and gen.gallery(rx0 + li, rz0 + lj):
		# Daylight: sky light bouncing around the white tiles, plus direct sun
		# where it comes through a window.
		var sc := WorldGen.SUN_COLOR
		var sky := 0.5 + 0.12 * maxf(nrm.y, 0.0)
		var sun := 0.0
		var sd := -WorldGen.SUN_TRAVEL.normalized()
		var ndl := nrm.x * sd.x + nrm.y * sd.y + nrm.z * sd.z
		if ndl > 0.0 and not _no_sun and _sunlit(u, v, p.y):
			sun = ndl * WorldGen.SUN_POWER
		r += sc.r * (sky + sun)
		g += sc.g * (sky + sun)
		bl += sc.b * (sky + sun)
		tot += (sky + sun) * 3.0
		dacc += sd * sun * 3.0 + Vector3.UP * sky
	if _gi and _gi_ready and not _direct_only:
		var ind := _gi_sample(u, v, nrm)
		if b == WorldGen.DARK:   # (legacy bake only)
			ind *= 0.3          # the Unlit Halls stay dark
		r += ind.r
		g += ind.g
		bl += ind.b
		tot += ind.r + ind.g + ind.b
	_ldir = dacc
	var share := fl_amt / tot if tot > 0.0 else 0.0
	return Color(r, g, bl, share)


## Lucid: the same, in real units. Direct light from each fixture by the
## inverse square law and its cos^m distribution, E = I0 cos^m(te) cos(tr)
## / d^2 (faded out over the last quarter of LUCID_RADIUS, where the far
## tail of the probes takes over, see _compute_tail), daylight in lux, and
## the bounce from the radiosity. No ambient floor and no fake bounce term.
## Returns E / pi in engine units; the bounce part is left in `_ind`
## (contact occlusion applies to it only, see _ao_mix), and each switchable
## lamp's direct and bounce parts in `_swv_d` / `_swv_b` (listed in `_swl`).
## Alpha: the share of
## the strongest switchable lamp (direct + bounce), whose seed is `_seed`.
func _shade_lucid(p: Vector3, nrm: Vector3) -> Color:
	var li := floori(p.x / CELL) - rx0
	var lj := floori(p.z / CELL) - rz0
	_seed = 0.0
	_ind = Color(0, 0, 0, 0)
	for l in _swl:
		_swv_d[l] = 0.0
		_swv_b[l] = 0.0
	_swl.resize(0)
	if li < 0 or lj < 0 or li >= W or lj >= W:
		return Color(0, 0, 0, 0)
	var b := bio(li, lj)
	var r := 0.0
	var g := 0.0
	var bl := 0.0
	var u := p.x / CELL - rx0
	var v := p.z / CELL - rz0
	var tot := 0.0
	var dacc := Vector3.ZERO
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
		var ndl := (nrm.x * dx + nrm.y * dy + nrm.z * dz) / d
		if ndl <= 0.0:
			continue
		var m := lexp[k]
		var ce := dy / d
		if m > 0.0 and ce <= 0.0:
			continue
		if (not _face_on or _face_vis[k] == 2) and not _visible(lp.x / CELL - rx0, lp.z / CELL - rz0, lp.y, u, v, p.y):
			continue
		var e := (ce if m == 1.0 else (pow(ce, m) if m > 0.0 else 1.0)) * ndl / maxf(d2, 0.04)
		e *= 1.0 - smoothstep(rad * 0.75, rad, d)
		var c := lcol[k]
		r += c.r * e
		g += c.g * e
		bl += c.b * e
		var lum := e * (c.r + c.g + c.b)
		tot += lum
		dacc += Vector3(dx, dy, dz) * (lum / d)
		if lid[k] >= 0:
			_swv_d[k] = lum
			_swl.push_back(k)
	if b == WorldGen.POOL and gen.gallery(rx0 + li, rz0 + lj):
		# Daylight through the windows: diffuse skylight on everything, and
		# the direct sun beam (Lucid.SUN_LUX on a surface facing it) where
		# it comes through.
		var sky := Lucid.kelvin_rgb(Lucid.SKY_CLEAR_KELVIN, true) * Lucid.lux_to_engine(
				WorldGen.LUCID_GALLERY_SKY * (0.8 + 0.2 * nrm.y))
		var sun := Color(0, 0, 0)
		var sd := -WorldGen.SUN_TRAVEL.normalized()
		var ndl := nrm.x * sd.x + nrm.y * sd.y + nrm.z * sd.z
		if ndl > 0.0 and not _no_sun and _sunlit(u, v, p.y):
			sun = Lucid.kelvin_rgb(Lucid.SUN_KELVIN, true) * Lucid.lux_to_engine(Lucid.SUN_LUX * ndl)
		r += sky.r + sun.r
		g += sky.g + sun.g
		bl += sky.b + sun.b
		var dl := sky.r + sky.g + sky.b + sun.r + sun.g + sun.b
		tot += dl
		dacc += sd * (sun.r + sun.g + sun.b) + Vector3.UP * (sky.r + sky.g + sky.b)
	if _tail_ready:
		# The far fixtures (beyond the per-texel window), and the bounce,
		# from the probes (or as set by _bake_face).
		if not _fld_set:
			_field(u, v, p.y, nrm)
		var ft := _fld_far
		r += ft.r
		g += ft.g
		bl += ft.b
		tot += ft.r + ft.g + ft.b
		dacc += Vector3.UP * (ft.r + ft.g + ft.b) * 0.3
	if _gi_ready and not _direct_only:
		_ind = _fld_ind
		r += _ind.r
		g += _ind.g
		bl += _ind.b
		var il := _ind.r + _ind.g + _ind.b
		tot += il
		if _fld_set:
			for x in _fld_fl.size():
				var k := _fld_fl[x]
				if _fld_sw[x] > 0.0:
					if _swv_d[k] == 0.0:
						_swl.push_back(k)
					_swv_b[k] = _fld_sw[x]
		elif il > 0.0:
			# Each switchable lamp's own share of the bounce light here.
			var grp := 0 if nrm.y > 0.5 else (1 if nrm.y < -0.5 else 2)
			for q in 4:
				var wq := _bw[q] * il
				if wq <= 0.0:
					continue
				var cl: PackedInt32Array = _csw_l[_bk[q]]
				if cl.is_empty():
					continue
				var cs: PackedFloat32Array = _csw_s[_bk[q]]
				for x in cl.size():
					var k := cl[x]
					if _swv_d[k] == 0.0 and _swv_b[k] == 0.0:
						_swl.push_back(k)
					_swv_b[k] += wq * cs[x * 3 + grp]
	_ldir = dacc
	var best := 0.0
	for k in _swl:
		var l := _swv_d[k] + _swv_b[k]
		if l > best:
			best = l
			_seed = lseed[k]
	var share := best / tot if tot > 0.0 else 0.0
	return Color(r, g, bl, share)


## Contact occlusion applied to a shade() result: all of it in the legacy
## bake; with Lucid only the bounce part (a corner hides part of the room
## from a point, not the lamp it can see).
func _ao_mix(light: Color, ao: float) -> Color:
	if _lucid:
		return Color(light.r - _ind.r * (1.0 - ao), light.g - _ind.g * (1.0 - ao), light.b - _ind.b * (1.0 - ao), light.a)
	return Color(light.r * ao, light.g * ao, light.b * ao, light.a)


# ---------------------------------------------------- bounce light (gi) ---
# Radiosity on the cell grid, for colour bleeding and indirect shadows on any
# renderer: every floor, ceiling and wall of every cell is a patch that takes
# the direct light falling on it and reflects it in its own colour. A probe in
# each cell gathers the patches it can see (walls block, so corners and the far
# side of a pillar get less) into an "ambient cube": six colours, one per axis
# direction, so a wall facing a red wall picks up red and the floor picks up
# the ceiling. Two bounces. The result is baked into the lightmaps like the
# direct light, so it costs nothing at runtime.

const GI_RADIUS := 2              # cells a probe gathers from
const GI_STRENGTH := 1.5
## Surface colours for the bounce (what the shaders' textures average to),
## per biome: Yellow Halls, Tiled Baths, Grey Floors, Unlit Halls, Pipeworks.
const ALB_WALL := [Color(0.72, 0.65, 0.34), Color(0.80, 0.85, 0.88), Color(0.50, 0.50, 0.49), Color(0.72, 0.65, 0.34), Color(0.40, 0.35, 0.30), Color(0.50, 0.50, 0.49)]
const ALB_FLOOR := [Color(0.52, 0.41, 0.22), Color(0.78, 0.84, 0.88), Color(0.42, 0.42, 0.41), Color(0.52, 0.41, 0.22), Color(0.46, 0.28, 0.20), Color(0.40, 0.40, 0.39)]
const ALB_CEIL := [Color(0.78, 0.76, 0.66), Color(0.80, 0.85, 0.88), Color(0.45, 0.45, 0.44), Color(0.78, 0.76, 0.66), Color(0.34, 0.31, 0.29), Color(0.45, 0.45, 0.44)]

## Lucid: the measured albedo (Lucid.ALBEDO) of the biome's wall, floor
## and ceiling (`what` 0, 1, 2) where WorldGen.LUCID_ALBEDO names one, so
## the bounce has the colour and strength of the real materials.
func _alb(table: Array, b: int, what: int) -> Color:
	if _lucid:
		var name: String = WorldGen.LUCID_ALBEDO[b][what]
		if name != "":
			return Lucid.ALBEDO[name]
	return table[b]


var _direct_only := false
var _probe := PackedColorArray()      # W*W*6: +x -x +y -y +z -z per cell
var _probe_y := PackedFloat32Array()  # W*W probe heights


func _compute_gi() -> void:
	if _lucid:
		_compute_gi_lucid()
		return
	var ppos := PackedVector3Array()
	var pnrm := PackedVector3Array()
	var parea := PackedFloat32Array()
	var palb := PackedColorArray()
	var pcell := PackedInt32Array()
	var by_cell := []
	by_cell.resize(W * W)
	# Patches, for cells that probes can reach.
	var lo := M - GI_RADIUS - 1
	var hi := M + N + GI_RADIUS + 1
	for j in range(maxi(lo, 0), mini(hi, W)):
		for i in range(maxi(lo, 0), mini(hi, W)):
			if solid[i + j * W] == 1:
				continue
			var list := PackedInt32Array()
			var b := bio(i, j)
			var f := fl(i, j)
			var c := ce(i, j)
			var cx := (rx0 + i + 0.5) * CELL
			var cz := (rz0 + j + 0.5) * CELL
			var A := CELL * CELL
			list.push_back(ppos.size())
			ppos.push_back(Vector3(cx, f + 0.02, cz)); pnrm.push_back(Vector3.UP); parea.push_back(A)
			palb.push_back(_alb(ALB_FLOOR, b, 1)); pcell.push_back(i + j * W)
			list.push_back(ppos.size())
			ppos.push_back(Vector3(cx, c - 0.02, cz)); pnrm.push_back(Vector3.DOWN); parea.push_back(A)
			palb.push_back(_alb(ALB_CEIL, b, 2)); pcell.push_back(i + j * W)
			var h := c - f
			var my := f + h * 0.5
			for side in 4:
				var e: int
				var n: Vector3
				match side:
					0: e = edge_v(i, j); n = Vector3.RIGHT
					1: e = edge_v(i + 1, j); n = Vector3.LEFT
					2: e = edge_h(i, j); n = Vector3.BACK
					_: e = edge_h(i, j + 1); n = Vector3.FORWARD
				if e == WorldGen.E_OPEN:
					continue
				var area := CELL * h
				if e != WorldGen.E_WALL:
					area -= WorldGen.DOOR_W[e] * minf(WorldGen.DOOR_H[e], h)
				if area <= 0.1:
					continue
				list.push_back(ppos.size())
				ppos.push_back(Vector3(cx, my, cz) - n * (CELL * 0.5 - 0.1)); pnrm.push_back(n); parea.push_back(area)
				palb.push_back(_alb(ALB_WALL, b, 0)); pcell.push_back(i + j * W)
			by_cell[i + j * W] = list
	# Direct light on each patch.
	var pe := PackedColorArray()
	pe.resize(ppos.size())
	_direct_only = true
	for k in ppos.size():
		pe[k] = shade(ppos[k] + pnrm[k] * 0.05, pnrm[k])
	_direct_only = false
	# Probes: which patches each sees, and how much towards each cube face.
	var plo := M - 1
	var phi := M + N + 1
	_probe.resize(W * W * 6)
	_probe_y.resize(W * W)
	var links := []
	links.resize(W * W)
	for j in range(plo, phi):
		for i in range(plo, phi):
			if solid[i + j * W] == 1:
				continue
			var py := (fl(i, j) + ce(i, j)) * 0.5
			_probe_y[i + j * W] = py
			var pp := Vector3((rx0 + i + 0.5) * CELL, py, (rz0 + j + 0.5) * CELL)
			var lk := PackedFloat32Array()
			for qj in range(j - GI_RADIUS, j + GI_RADIUS + 1):
				for qi in range(i - GI_RADIUS, i + GI_RADIUS + 1):
					if qi < 0 or qj < 0 or qi >= W or qj >= W or by_cell[qi + qj * W] == null:
						continue
					if (qi != i or qj != j) and not _visible(i + 0.5, j + 0.5, 1.2, qi + 0.5, qj + 0.5, 1.2):
						continue
					for k in by_cell[qi + qj * W]:
						var d := ppos[k] - pp
						var d2 := d.length_squared()
						var dn := d / sqrt(d2)
						var cq := -pnrm[k].dot(dn)
						if cq <= 0.0:
							continue
						var w := parea[k] * cq / (PI * d2 + parea[k])
						# Per axis: sign = which face, size = cosine weight.
						lk.push_back(k)
						lk.push_back(dn.x * w)
						lk.push_back(dn.y * w)
						lk.push_back(dn.z * w)
			links[i + j * W] = lk
	# Two bounces: gather direct-lit patches, then light the patches with
	# that and gather again.
	var pb := PackedColorArray()
	pb.resize(ppos.size())
	for k in ppos.size():
		pb[k] = pe[k] * palb[k]
	_gather(links, pb, plo, phi)
	var first := _probe.duplicate() if _lucid else PackedColorArray()
	for k in ppos.size():
		var ind := _cube(pcell[k], pnrm[k])
		pb[k] = (pe[k] + ind) * palb[k]
	_gather(links, pb, plo, phi)
	if _lucid:
		# All bounces, not two: each further bounce is about the second
		# one times the same ratio (second / first), a geometric series.
		var s1 := 0.0
		var s2 := 0.0
		for k in _probe.size():
			s1 += first[k].r + first[k].g + first[k].b
			s2 += _probe[k].r + _probe[k].g + _probe[k].b
		var ratio := clampf((s2 - s1) / s1, 0.0, 0.8) if s1 > 0.0 else 0.0
		var tail := 1.0 / (1.0 - ratio)
		for k in _probe.size():
			_probe[k] = first[k] + (_probe[k] - first[k]) * tail
	_gi_ready = true


# ------------------------------------------------ Lucid bounce (stage 2) ---
# Probes at two heights per cell (LV_INSET above the floor and below the
# ceiling) gather the patches within GI_NEAR cells with subdivided form
# factors, so near patches are not underestimated; whatever part of the
# hemisphere no patch covers (an open hall going on beyond the gather) is
# filled from the outermost ring's floors and ceilings. Direct light from beyond
# the per-texel window comes from an analytic tail per cell (_compute_tail).
# Each switchable lamp's share of the first bounce is kept per cell, so its
# bounce light can be switched with it.

const LV_INSET := 0.4

var _tail_ready := false
var _far := PackedColorArray()        # W*W*12: far direct, ambient cubes at the floor and the ceiling
var _gi2 := PackedColorArray()        # W*W*12: bounce, ambient cubes at the two probe levels
var _cell_sw := []                    # per cell: {light: [up, down, side] share of the bounce} or null
var _csw_l := []                      # the same per cell as PackedInt32Array lights ...
var _csw_s := []                      # ... and PackedFloat32Array shares (3 per light)
var _bk := PackedInt32Array([0, 0, 0, 0])      # the cells and weights of the last _blend2()
var _bw := PackedFloat32Array([0, 0, 0, 0])
static var _tail_cache := {}            # shared by the chunk threads, under _tail_mutex
static var _tail_mutex := Mutex.new()


## Ambient cube k (12 colours: two levels of +x -x +y -y +z -z) at height
## fraction t between its levels, towards n.
func _cube2(arr: PackedColorArray, k: int, t: float, n: Vector3) -> Color:
	var o := k * 12
	if absf(n.y) > 0.999:
		var fy := 2 if n.y > 0.0 else 3
		return arr[o + fy].lerp(arr[o + 6 + fy], t)
	var ax := 0 if n.x > 0.0 else 1
	var ay := 2 if n.y > 0.0 else 3
	var az := 4 if n.z > 0.0 else 5
	var lo := arr[o + ax] * (n.x * n.x) + arr[o + ay] * (n.y * n.y) + arr[o + az] * (n.z * n.z)
	var hi := arr[o + 6 + ax] * (n.x * n.x) + arr[o + 6 + ay] * (n.y * n.y) + arr[o + 6 + az] * (n.z * n.z)
	return lo.lerp(hi, t)


## The height fraction of y between cell k's two levels: the floor and the
## ceiling for the far tail (`far`), the probe levels for the bounce.
func _lv_t(k: int, y: float, far: bool) -> float:
	var f := floor_y[k]
	var c := ceil_y[k]
	var y0 := f if far else f + LV_INSET
	var y1 := c if far else c - LV_INSET
	return clampf((y - y0) / maxf(y1 - y0, 0.1), 0.0, 1.0)


## The cells round local point (u, v in cells) whose two-level cubes are
## blended there (this cell and its neighbours, never across a wall, as in
## _gi_sample): left in _bk with normalised weights in _bw.
func _blend_w(u: float, v: float) -> void:
	var i := clampi(floori(u), 0, W - 1)
	var j := clampi(floori(v), 0, W - 1)
	var fu := u - i - 0.5
	var fv := v - j - 0.5
	var su := 1 if fu > 0.0 else -1
	var sv := 1 if fv > 0.0 else -1
	var i2 := clampi(i + su, 0, W - 1)
	var j2 := clampi(j + sv, 0, W - 1)
	# Which neighbours are open, per cell and quadrant (cached).
	var ck := (i + j * W) * 4 + (1 if su > 0 else 0) + (2 if sv > 0 else 0)
	var fl_ := _bopen[ck]
	if fl_ == 0:
		var open_u := i2 != i and solid[i2 + j * W] == 0 and edge_v(maxi(i, i2), j) != WorldGen.E_WALL
		var open_v := j2 != j and solid[i + j2 * W] == 0 and edge_h(i, maxi(j, j2)) != WorldGen.E_WALL
		var open_d := open_u and open_v and solid[i2 + j2 * W] == 0 \
				and edge_h(i2, maxi(j, j2)) != WorldGen.E_WALL and edge_v(maxi(i, i2), j2) != WorldGen.E_WALL
		fl_ = 8 | (1 if open_u else 0) | (2 if open_v else 0) | (4 if open_d else 0)
		_bopen[ck] = fl_
	var wu := absf(fu)
	var wv := absf(fv)
	_bk[0] = i + j * W
	_bk[1] = i2 + j * W
	_bk[2] = i + j2 * W
	_bk[3] = i2 + j2 * W
	var w0 := (1.0 - wu) * (1.0 - wv)
	var w1 := wu * (1.0 - wv) if fl_ & 1 else 0.0
	var w2 := (1.0 - wu) * wv if fl_ & 2 else 0.0
	var w3 := wu * wv if fl_ & 4 else 0.0
	var tw := w0 + w1 + w2 + w3
	_bw[0] = w0 / tw
	_bw[1] = w1 / tw
	_bw[2] = w2 / tw
	_bw[3] = w3 / tw


var _bopen := PackedByteArray()
const FIELD_STEP := 4
var _fld_set := false
var _fld_sw := PackedFloat32Array()
var _fld_fl := PackedInt32Array()
var _fld_far := Color()
var _fld_ind := Color()

## The far tail and the bounce at local point (u, v in cells), height y,
## towards n, blended over the cells round it (_blend_w): left in _fld_far
## and _fld_ind.
func _field(u: float, v: float, y: float, n: Vector3) -> void:
	if _bopen.size() != W * W * 4:
		_bopen.resize(W * W * 4)
	_blend_w(u, v)
	var axis := -1
	if absf(n.y) > 0.999:
		axis = 2 if n.y > 0.0 else 3
	elif absf(n.x) > 0.999:
		axis = 0 if n.x > 0.0 else 1
	elif absf(n.z) > 0.999:
		axis = 4 if n.z > 0.0 else 5
	var far := Color(0, 0, 0)
	var ind := Color(0, 0, 0)
	var gi := _gi_ready
	for q in 4:
		var w := _bw[q]
		if w <= 0.0:
			continue
		var k := _bk[q]
		var f := floor_y[k]
		var h := ceil_y[k] - f
		var tf := clampf((y - f) / maxf(h, 0.1), 0.0, 1.0)
		var tb := clampf((y - f - LV_INSET) / maxf(h - 2.0 * LV_INSET, 0.1), 0.0, 1.0)
		var o := k * 12
		if axis >= 0:
			far += _far[o + axis].lerp(_far[o + 6 + axis], tf) * w
			if gi:
				ind += _gi2[o + axis].lerp(_gi2[o + 6 + axis], tb) * w
		else:
			far += _cube2(_far, k, tf, n) * w
			if gi:
				ind += _cube2(_gi2, k, tb, n) * w
	_fld_far = far
	_fld_ind = ind


## The far tail of a fixture grid at height h below it, per unit density
## and unit angle: Vector2(U, H), the irradiance (per unit E / pi at 1 m) on
## a surface facing up and facing the far fixtures horizontally, summed
## over the fixtures the per-texel window leaves out (its complement).
func _tail_int(m: float, h: float, rmax: float) -> Vector2:
	var key := Vector3i(roundi(m * 100.0), roundi(h * 20.0), roundi(rmax))
	_tail_mutex.lock()
	var got: Variant = _tail_cache.get(key)
	_tail_mutex.unlock()
	if got != null:
		return got
	var hh := maxf(key.y / 20.0, 0.01)
	var uu := 0.0
	var ss := 0.0
	var r0 := LUCID_RADIUS * 0.75
	var r := sqrt(maxf(r0 * r0 - hh * hh, 0.0))
	var dr := 0.1
	while r < rmax:
		dr = maxf(0.1, r * 0.02)
		var d2 := r * r + hh * hh
		var d := sqrt(d2)
		var wc := smoothstep(LUCID_RADIUS * 0.75, LUCID_RADIUS, d)
		if wc > 0.0:
			var ce := hh / d
			var e := wc * (pow(ce, m) if m > 0.0 else 1.0) / d2 * r * dr
			uu += e * ce
			ss += e * r / d
		r += dr
	_tail_mutex.lock()
	_tail_cache[key] = Vector2(uu, ss)
	_tail_mutex.unlock()
	return Vector2(uu, ss)


## Per cell, the direct light of the fixtures beyond the per-texel window:
## the local fixture density (lit fixtures per m2 over the open cells in
## the 9 x 9 cells around) carried on in each direction as far as it is
## open (traced to TAIL_REACH: up to the first distance that is blocked, or
## to infinity if none is), like a regular grid of fixtures, as ambient
## cubes at the floor and at the ceiling.
const TAIL_REACH := [7.6, 12.0, 20.0]

func _compute_tail() -> void:
	_far.resize(W * W * 12)
	_far.fill(Color(0, 0, 0))
	var dphi := TAU / TAIL_SECTORS
	# How far each direction is open, traced from the cells round the chunk
	# (the ones its surfaces and probes read); cells further out (patches
	# only) take the nearest of those.
	var ilo := M - 2
	var ihi := M + N + 1
	var reach_of := PackedFloat32Array()
	reach_of.resize(W * W * TAIL_SECTORS)
	for j in range(ilo, ihi + 1):
		for i in range(ilo, ihi + 1):
			if solid[i + j * W] == 1:
				continue
			var ay := minf(2.0, ce(i, j) - 0.2)
			for s in TAIL_SECTORS:
				var phi := (s + 0.5) * dphi
				var cx := cos(phi)
				var cz := sin(phi)
				var far: float = TAIL_REACH[TAIL_REACH.size() - 1] / CELL
				var bt: float = _block_t(i + 0.5, j + 0.5, ay, i + 0.5 + cx * far, j + 0.5 + cz * far, ay) * TAIL_REACH[TAIL_REACH.size() - 1]
				var rmax := 120.0
				for q in TAIL_REACH.size():
					if bt < TAIL_REACH[q]:
						rmax = 0.0 if q == 0 else (TAIL_REACH[q - 1] + TAIL_REACH[q]) * 0.5
						break
				reach_of[(i + j * W) * TAIL_SECTORS + s] = rmax
	for j in W:
		for i in W:
			if solid[i + j * W] == 1:
				continue
			var ri := clampi(i, ilo, ihi)
			var rj := clampi(j, ilo, ihi)
			if solid[ri + rj * W] == 1:
				ri = i
				rj = j
			var nl := 0
			var nc := 0
			var col := Color(0, 0, 0)
			var mx := 0.0
			for dj in range(-4, 5):
				var jj := j + dj
				if jj < 0 or jj >= W:
					continue
				for di in range(-4, 5):
					var ii := i + di
					if ii < 0 or ii >= W or solid[ii + jj * W] == 1:
						continue
					nc += 1
					var l := light_at[ii + jj * W]
					if l >= 0:
						nl += 1
						col += lcol[l]
						mx += lexp[l]
			if nl == 0:
				continue
			var rho := float(nl) / (nc * CELL * CELL)
			col /= nl
			mx /= nl
			var f := fl(i, j)
			var c := ce(i, j)
			var o := (i + j * W) * 12
			for s in TAIL_SECTORS:
				var phi := (s + 0.5) * dphi
				var cx := cos(phi)
				var cz := sin(phi)
				var rmax := reach_of[(ri + rj * W) * TAIL_SECTORS + s]
				if rmax <= 0.0:
					continue
				for lv in 2:
					var t := _tail_int(mx, (c - 0.03) - (f + 0.02 if lv == 0 else c - 0.02), rmax)
					var up := col * (rho * dphi * t.x)
					var side := col * (rho * dphi * t.y)
					var b := o + lv * 6
					_far[b + 2] += up
					_far[b + (0 if cx > 0.0 else 1)] += side * absf(cx)
					_far[b + (4 if cz > 0.0 else 5)] += side * absf(cz)
	_tail_ready = true


## Form factor weights (6: +x -x +y -y +z -z) of patch k seen from point pp:
## the patch split into up to 4 x 4 parts when it is near.
func _ff(pp: Vector3, c: Vector3, du: Vector3, dv: Vector3, n: Vector3, area: float, out: PackedFloat32Array) -> void:
	out.fill(0.0)
	var dist := maxf(pp.distance_to(c), 0.05)
	var size := 2.0 * maxf(du.length(), dv.length())
	var sub := clampi(ceili(size / dist), 1, 4)
	if sub == 1:
		var d := c - pp
		var dn := d / dist
		var cq := -n.dot(dn)
		if cq > 0.0:
			var w := area * cq / (PI * dist * dist + area)
			out[0 if dn.x > 0.0 else 1] = absf(dn.x) * w
			out[2 if dn.y > 0.0 else 3] = absf(dn.y) * w
			out[4 if dn.z > 0.0 else 5] = absf(dn.z) * w
		return
	var da := area / (sub * sub)
	for a in sub:
		var fa := (a + 0.5) / sub * 2.0 - 1.0
		for bb in sub:
			var q := c + du * fa + dv * ((bb + 0.5) / sub * 2.0 - 1.0)
			var d := q - pp
			var d2 := d.length_squared()
			var dn := d / sqrt(d2)
			var cq := -n.dot(dn)
			if cq <= 0.0:
				continue
			var w := da * cq / (PI * d2 + da)
			if dn.x > 0.0: out[0] += dn.x * w
			else: out[1] -= dn.x * w
			if dn.y > 0.0: out[2] += dn.y * w
			else: out[3] -= dn.y * w
			if dn.z > 0.0: out[4] += dn.z * w
			else: out[5] -= dn.z * w


func _compute_gi_lucid() -> void:
	_compute_tail()
	var ppos := PackedVector3Array()
	var pnrm := PackedVector3Array()
	var pdu := PackedVector3Array()
	var pdv := PackedVector3Array()
	var parea := PackedFloat32Array()
	var palb := PackedColorArray()
	var pcell := PackedInt32Array()
	var by_cell := []
	by_cell.resize(W * W)
	var plo := M - 1
	var phi := M + N + 1
	var lo := maxi(plo - GI_NEAR, 0)
	var hi := mini(phi + GI_NEAR, W)
	var hc := CELL * 0.5
	for j in range(lo, hi):
		for i in range(lo, hi):
			if solid[i + j * W] == 1:
				continue
			var list := PackedInt32Array()
			var b := bio(i, j)
			var f := fl(i, j)
			var c := ce(i, j)
			var cx := (rx0 + i + 0.5) * CELL
			var cz := (rz0 + j + 0.5) * CELL
			list.push_back(ppos.size())
			ppos.push_back(Vector3(cx, f + 0.02, cz)); pnrm.push_back(Vector3.UP); parea.push_back(CELL * CELL)
			pdu.push_back(Vector3(hc, 0, 0)); pdv.push_back(Vector3(0, 0, hc))
			palb.push_back(_alb(ALB_FLOOR, b, 1)); pcell.push_back(i + j * W)
			list.push_back(ppos.size())
			ppos.push_back(Vector3(cx, c - 0.02, cz)); pnrm.push_back(Vector3.DOWN); parea.push_back(CELL * CELL)
			pdu.push_back(Vector3(hc, 0, 0)); pdv.push_back(Vector3(0, 0, hc))
			palb.push_back(_alb(ALB_CEIL, b, 2)); pcell.push_back(i + j * W)
			var h := c - f
			for side in 4:
				var e: int
				var n: Vector3
				match side:
					0: e = edge_v(i, j); n = Vector3.RIGHT
					1: e = edge_v(i + 1, j); n = Vector3.LEFT
					2: e = edge_h(i, j); n = Vector3.BACK
					_: e = edge_h(i, j + 1); n = Vector3.FORWARD
				if e == WorldGen.E_OPEN:
					continue
				var area := CELL * h
				if e != WorldGen.E_WALL:
					area -= WorldGen.DOOR_W[e] * minf(WorldGen.DOOR_H[e], h)
				if area <= 0.1:
					continue
				list.push_back(ppos.size())
				ppos.push_back(Vector3(cx, f + h * 0.5, cz) - n * (hc - T)); pnrm.push_back(n); parea.push_back(area)
				pdu.push_back(Vector3(absf(n.z), 0, absf(n.x)) * hc); pdv.push_back(Vector3(0, h * 0.5, 0))
				palb.push_back(_alb(ALB_WALL, b, 0)); pcell.push_back(i + j * W)
			by_cell[i + j * W] = list
	# Direct light on each patch (with the far tail), and each switchable
	# lamp's part of it.
	var np := ppos.size()
	var pe := PackedColorArray()
	pe.resize(np)
	var psw := []
	psw.resize(np)
	_direct_only = true
	for k in np:
		pe[k] = shade(ppos[k] + pnrm[k] * 0.05, pnrm[k])
		if not _swl.is_empty():
			var al := (palb[k].r + palb[k].g + palb[k].b) / 3.0
			var d := {}
			for l in _swl:
				d[l] = _swv_d[l] * al
			psw[k] = d
	_direct_only = false
	# Probes: two levels per cell; which patches each sees, with what weights.
	var probes := PackedInt32Array()     # cell * 2 + level
	var links := []
	var cover := PackedFloat32Array()
	var w6 := PackedFloat32Array()
	w6.resize(6)
	var seen := {}
	for j in range(plo, phi):
		for i in range(plo, phi):
			if solid[i + j * W] == 1:
				continue
			var vis := {}
			for qj in range(j - GI_NEAR, j + GI_NEAR + 1):
				for qi in range(i - GI_NEAR, i + GI_NEAR + 1):
					if qi < 0 or qj < 0 or qi >= W or qj >= W or by_cell[qi + qj * W] == null:
						continue
					var a := i + j * W
					var b := qi + qj * W
					var pair := mini(a, b) * W * W + maxi(a, b)
					if not seen.has(pair):
						seen[pair] = a == b or _visible(i + 0.5, j + 0.5, 1.2, qi + 0.5, qj + 0.5, 1.2)
					if seen[pair]:
						vis[qi + qj * W] = 1.0 if maxi(absi(qi - i), absi(qj - j)) == GI_NEAR else 0.0
			for lv in 2:
				var py := fl(i, j) + LV_INSET if lv == 0 else ce(i, j) - LV_INSET
				var pp := Vector3((rx0 + i + 0.5) * CELL, py, (rz0 + j + 0.5) * CELL)
				var lk := PackedFloat32Array()
				var cv := PackedFloat32Array()      # covered: all, floors, ceilings (6 each)
				cv.resize(18)
				for qk in vis:
					for k in by_cell[qk]:
						_ff(pp, ppos[k], pdu[k], pdv[k], pnrm[k], parea[k], w6)
						if w6[0] + w6[1] + w6[2] + w6[3] + w6[4] + w6[5] <= 0.0:
							continue
						var ty := 1 if pnrm[k].y > 0.5 else (2 if pnrm[k].y < -0.5 else 3)
						lk.push_back(k)
						lk.push_back(ty * vis[qk])
						for a in 6:
							lk.push_back(w6[a])
							cv[a] += w6[a]
							if ty < 3:
								cv[ty * 6 + a] += w6[a]
				probes.push_back((i + j * W) * 2 + lv)
				links.push_back(lk)
				cover.append_array(cv)
	_gi2.resize(W * W * 12)
	_gi2.fill(Color(0, 0, 0))
	_cell_sw.resize(W * W)
	# First bounce, with each lamp's share; then the patches lit by it too.
	var pb := PackedColorArray()
	pb.resize(np)
	for k in np:
		pb[k] = pe[k] * palb[k]
	var sh1 := {}
	_gather2(probes, links, cover, pb, psw, sh1)
	_cell_sw = _shares(sh1, {}, 0.0)
	var first := _gi2.duplicate()
	# Second bounce: the patches lit by the first too, and each lamp's part
	# of that (its own first bounce, by the shares just found).
	var psw2 := []
	psw2.resize(np)
	for k in np:
		var ck := pcell[k]
		var t := 0.0 if pnrm[k].y > 0.5 else (1.0 if pnrm[k].y < -0.5 else 0.5)
		var ind := _cube2(_gi2, ck, t, pnrm[k])
		pb[k] = (pe[k] + ind) * palb[k]
		var grp := 0 if pnrm[k].y > 0.5 else (1 if pnrm[k].y < -0.5 else 2)
		var al := (palb[k].r + palb[k].g + palb[k].b) / 3.0
		var il := (ind.r + ind.g + ind.b) * al
		var d := {}
		if psw[k] != null:
			d = (psw[k] as Dictionary).duplicate()
		if _cell_sw[ck] != null:
			for l in _cell_sw[ck]:
				d[l] = d.get(l, 0.0) + il * _cell_sw[ck][l][grp]
		# (lamps giving a patch under 1 % of its light are left out)
		var cut := (pb[k].r + pb[k].g + pb[k].b) * 0.01
		for l in d.keys():
			if d[l] < cut:
				d.erase(l)
		psw2[k] = d if not d.is_empty() else null
	var sh2 := {}
	_gather2(probes, links, cover, pb, psw2, sh2)
	# Third bounce, then all further ones: each about the third times the
	# ratio of third to second, per probe value (a floor lit through the
	# ceiling gets its light in the second bounce and little in the third;
	# one ratio for all, as in stage 1, over-lit such places).
	var second := _gi2.duplicate()
	for k in np:
		var t := 0.0 if pnrm[k].y > 0.5 else (1.0 if pnrm[k].y < -0.5 else 0.5)
		pb[k] = (pe[k] + _cube2(_gi2, pcell[k], t, pnrm[k])) * palb[k]
	_gather2(probes, links, cover, pb, [], null)
	for k in _gi2.size():
		var b2 := second[k] - first[k]
		var b3 := _gi2[k] - second[k]
		var l2 := b2.r + b2.g + b2.b
		var r := clampf((b3.r + b3.g + b3.b) / l2, 0.0, 0.8) if l2 > 1e-6 else 0.0
		_gi2[k] = second[k] + b3 / (1.0 - r)
	# Each lamp's share of it: its part of the first two bounces.
	_cell_sw = _shares(sh1, sh2, 1.0)
	_csw_l.resize(W * W)
	_csw_s.resize(W * W)
	for ck in W * W:
		var ls := PackedInt32Array()
		var ss := PackedFloat32Array()
		if _cell_sw[ck] != null:
			for l in _cell_sw[ck]:
				# (a lamp giving a cell under 3 % of its bounce is left steady)
				var sh: PackedFloat32Array = _cell_sw[ck][l]
				if maxf(sh[0], maxf(sh[1], sh[2])) >= 0.03:
					ls.push_back(l)
					ss.append_array(sh)
		_csw_l[ck] = ls
		_csw_s[ck] = ss
	# The stage 1 single-level probes (mid height), for light_probe().
	_probe.resize(W * W * 6)
	for k in W * W:
		for a in 6:
			_probe[k * 6 + a] = (_gi2[k * 12 + a] + _gi2[k * 12 + 6 + a]) * 0.5
	_gi_ready = true


## Per cell, each lamp's share of the bounce for surfaces facing up, down
## and sideways ({light: [up, down, side]}), from the per-lamp sums of the
## first gather (`a`) and the second (`b`, first + second bounce) carried on
## as the series `tail` (b empty: the first bounce alone).
func _shares(a: Dictionary, b: Dictionary, tail: float) -> Array:
	var out := []
	out.resize(W * W)
	for ck in a:
		var ta: PackedFloat32Array = a[ck]["_tot"]
		var tb: PackedFloat32Array = b[ck]["_tot"] if b.has(ck) else ta
		var tot := PackedFloat32Array()
		tot.resize(12)
		for x in 12:
			tot[x] = ta[x] + (tb[x] - ta[x]) * tail
		var lights := {}
		for l in a[ck]:
			lights[l] = true
		if b.has(ck):
			for l in b[ck]:
				lights[l] = true
		var d := {}
		for l in lights:
			if typeof(l) == TYPE_STRING:
				continue
			var z := PackedFloat32Array()
			z.resize(12)
			var la: PackedFloat32Array = a[ck].get(l, z)
			var lb: PackedFloat32Array = b[ck].get(l, la) if b.has(ck) else la
			var v := PackedFloat32Array()
			v.resize(12)
			for x in 12:
				v[x] = la[x] + (lb[x] - la[x]) * tail
			var up := v[2] / tot[2] if tot[2] > 0.0 else 0.0
			var dn := v[9] / tot[9] if tot[9] > 0.0 else 0.0
			var sd := 0.0
			var st := 0.0
			for x in [0, 1, 4, 5, 6, 7, 10, 11]:
				sd += v[x]
				st += tot[x]
			d[l] = PackedFloat32Array([clampf(up, 0.0, 1.0), clampf(dn, 0.0, 1.0), clampf(sd / st if st > 0.0 else 0.0, 0.0, 1.0)])
		out[ck] = d
	return out


## One gather of patch radiance `pb` into the two-level probes (_gi2), with
## the uncovered solid angle filled from the outer ring. With `shares`, also
## each switchable lamp's part (from `psw`, per patch {light: luminance}) per
## cell: {light: 12 floats, "_tot": 12 floats}.
func _gather2(probes: PackedInt32Array, links: Array, cover: PackedFloat32Array, pb: PackedColorArray, psw: Array, shares) -> void:
	var zero := Color(0, 0, 0)
	var per_lamp: bool = shares != null
	for q in probes.size():
		var lk: PackedFloat32Array = links[q]
		var a0 := zero
		var a1 := zero
		var a2 := zero
		var a3 := zero
		var a4 := zero
		var a5 := zero
		# The outermost ring's floors and ceilings, per face: radiance x
		# weight, and weight.
		var of := [zero, zero, zero, zero, zero, zero]
		var oc := [zero, zero, zero, zero, zero, zero]
		var ow := PackedFloat32Array()
		ow.resize(12)
		var lam := {}
		var t := 0
		var n := lk.size()
		while t < n:
			var k := int(lk[t])
			var c := pb[k]
			var w0 := lk[t + 2]
			var w1 := lk[t + 3]
			var w2 := lk[t + 4]
			var w3 := lk[t + 5]
			var w4 := lk[t + 6]
			var w5 := lk[t + 7]
			a0 += c * w0
			a1 += c * w1
			a2 += c * w2
			a3 += c * w3
			a4 += c * w4
			a5 += c * w5
			var ty := int(lk[t + 1])
			if ty == 1 or ty == 2:
				var dst: Array = of if ty == 1 else oc
				var wo := (ty - 1) * 6
				for a in 6:
					var w := lk[t + 2 + a]
					if w > 0.0:
						dst[a] += c * w
						ow[wo + a] += w
			if per_lamp and psw[k] != null:
				var d: Dictionary = psw[k]
				for l in d:
					if not lam.has(l):
						var z := PackedFloat32Array()
						z.resize(18)
						lam[l] = z
					var arr: PackedFloat32Array = lam[l]
					var v: float = d[l]
					for a in 6:
						arr[a] += v * lk[t + 2 + a]
						if ty == 1 or ty == 2:
							arr[ty * 6 + a] += v * lk[t + 2 + a]
					lam[l] = arr
			t += 8
		var acc := [a0, a1, a2, a3, a4, a5]
		var ck := probes[q] >> 1
		var lv := probes[q] & 1
		var o := ck * 12 + lv * 6
		# The part of the hemisphere no patch covers: as much of it as an
		# endless floor and ceiling would fill (half each for a face looking
		# sideways, all for one looking at them) is filled with the outer
		# ring's floor and ceiling radiance; never more than is missing.
		var fill_f := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		var fill_c := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
		for a in 6:
			var miss := 1.0 - cover[q * 18 + a]
			if miss > 0.0:
				var inf_f := 1.0 if a == 3 else (0.0 if a == 2 else 0.5)
				var inf_c := 1.0 if a == 2 else (0.0 if a == 3 else 0.5)
				var mf := maxf(inf_f - cover[q * 18 + 6 + a], 0.0) if ow[a] > 0.0 else 0.0
				var mc := maxf(inf_c - cover[q * 18 + 12 + a], 0.0) if ow[6 + a] > 0.0 else 0.0
				var sc := minf(1.0, miss / (mf + mc)) if mf + mc > 0.0 else 0.0
				if mf > 0.0:
					fill_f[a] = mf * sc / ow[a]
					acc[a] += of[a] * fill_f[a]
				if mc > 0.0:
					fill_c[a] = mc * sc / ow[6 + a]
					acc[a] += oc[a] * fill_c[a]
			_gi2[o + a] = acc[a]
		if per_lamp:
			if not shares.has(ck):
				var z := PackedFloat32Array()
				z.resize(12)
				shares[ck] = {"_tot": z}
			var sc: Dictionary = shares[ck]
			var tot: PackedFloat32Array = sc["_tot"]
			for a in 6:
				tot[lv * 6 + a] += acc[a].r + acc[a].g + acc[a].b
			sc["_tot"] = tot
			for l in lam:
				var arr: PackedFloat32Array = lam[l]
				if not sc.has(l):
					var z := PackedFloat32Array()
					z.resize(12)
					sc[l] = z
				var dst: PackedFloat32Array = sc[l]
				for a in 6:
					dst[lv * 6 + a] += arr[a] + arr[6 + a] * fill_f[a] + arr[12 + a] * fill_c[a]
				sc[l] = dst


func _gather(links: Array, pb: PackedColorArray, plo: int, phi: int) -> void:
	for j in range(plo, phi):
		for i in range(plo, phi):
			var lk = links[i + j * W]
			if lk == null:
				continue
			var acc := [Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)]
			var t := 0
			var n: int = lk.size()
			while t < n:
				var c := pb[int(lk[t])]
				var x: float = lk[t + 1]
				var y: float = lk[t + 2]
				var z: float = lk[t + 3]
				if x > 0.0: acc[0] += c * x
				else: acc[1] -= c * x
				if y > 0.0: acc[2] += c * y
				else: acc[3] -= c * y
				if z > 0.0: acc[4] += c * z
				else: acc[5] -= c * z
				t += 4
			var o := (i + j * W) * 6
			var gs := 1.0 if _lucid else GI_STRENGTH
			for f in 6:
				_probe[o + f] = acc[f] * gs


## Bounce light arriving from direction `n` at cell k (ambient cube).
func _cube(k: int, n: Vector3) -> Color:
	var o := k * 6
	if o + 5 >= _probe.size():
		return Color(0, 0, 0)
	var c := _probe[o + (0 if n.x > 0.0 else 1)] * (n.x * n.x)
	c += _probe[o + (2 if n.y > 0.0 else 3)] * (n.y * n.y)
	c += _probe[o + (4 if n.z > 0.0 else 5)] * (n.z * n.z)
	return c


## Bounce light at local point (u, v in cells) with normal n: blends the
## probes of this cell and its neighbours, but never across a wall.
func _gi_sample(u: float, v: float, n: Vector3) -> Color:
	var i := clampi(floori(u), 0, W - 1)
	var j := clampi(floori(v), 0, W - 1)
	var fu := u - i - 0.5
	var fv := v - j - 0.5
	var i2 := clampi(i + (1 if fu > 0.0 else -1), 0, W - 1)
	var j2 := clampi(j + (1 if fv > 0.0 else -1), 0, W - 1)
	var wu := absf(fu)
	var wv := absf(fv)
	var open_u := i2 != i and solid[i2 + j * W] == 0 and edge_v(maxi(i, i2), j) != WorldGen.E_WALL
	var open_v := j2 != j and solid[i + j2 * W] == 0 and edge_h(i, maxi(j, j2)) != WorldGen.E_WALL
	var open_d := open_u and open_v and solid[i2 + j2 * W] == 0 \
			and edge_h(i2, maxi(j, j2)) != WorldGen.E_WALL and edge_v(maxi(i, i2), j2) != WorldGen.E_WALL
	var w0 := (1.0 - wu) * (1.0 - wv)
	var w1 := wu * (1.0 - wv) if open_u else 0.0
	var w2 := (1.0 - wu) * wv if open_v else 0.0
	var w3 := wu * wv if open_d else 0.0
	var c := _cube(i + j * W, n) * w0
	if w1 > 0.0: c += _cube(i2 + j * W, n) * w1
	if w2 > 0.0: c += _cube(i + j2 * W, n) * w2
	if w3 > 0.0: c += _cube(i2 + j2 * W, n) * w3
	return c / (w0 + w1 + w2 + w3)


## True if the sun reaches local point (u, v in cells, y in metres): walks the
## grid toward the sun and needs to leave through a window before hitting a
## wall or the ceiling.
func _sunlit(u: float, v: float, y: float) -> bool:
	var sd := -WorldGen.SUN_TRAVEL.normalized()
	var hl := Vector2(sd.x, sd.z).length()
	var dx := sd.x / hl / CELL          # cells per metre of horizontal travel
	var dz := sd.z / hl / CELL
	var dy := sd.y / hl                 # metres up per metre of horizontal travel
	var ci := floori(u)
	var cj := floori(v)
	var si := 1 if dx > 0.0 else -1
	var sj := 1 if dz > 0.0 else -1
	var tdx := absf(1.0 / dx) if dx != 0.0 else INF
	var tdz := absf(1.0 / dz) if dz != 0.0 else INF
	var tmx := (float(ci + (1 if si > 0 else 0)) - u) / dx if dx != 0.0 else INF
	var tmz := (float(cj + (1 if sj > 0 else 0)) - v) / dz if dz != 0.0 else INF
	for _s in 8:
		var t := minf(tmx, tmz)
		var yy := y + dy * t
		if ci < 0 or cj < 0 or ci >= W or cj >= W or yy >= ce(ci, cj) - 0.02:
			return false
		var e: int
		var along: float
		if tmx < tmz:
			e = edge_v(ci + (1 if si > 0 else 0), cj)
			along = v + dz * t - cj
			ci += si
			tmx += tdx
		else:
			e = edge_h(ci, cj + (1 if sj > 0 else 0))
			along = u + dx * t - ci
			cj += sj
			tmz += tdz
		if e == WorldGen.E_OPEN:
			continue
		if e != WorldGen.E_WINDOW:
			return false
		return absf(along - 0.5) * CELL < WorldGen.DOOR_W[e] * 0.5 and yy > WorldGen.WIN_Y0 and yy < WorldGen.DOOR_H[e]
	return false


func _occl(d: float) -> float:
	return 0.55 + 0.45 * smoothstep(0.0, 0.85, d - T)


## Realistic: inside corners of walls darken softly too (distance to the
## walls at right angles to this one; its own wall is left out).
func _ao_corner(p: Vector3, nrm: Vector3) -> float:
	var u := p.x / CELL - rx0
	var v := p.z / CELL - rz0
	var i := floori(u)
	var j := floori(v)
	var dm := 9.0
	if absf(nrm.z) > 0.5:
		# Wall facing +-Z (a horizontal edge): look at the vertical edges.
		for dj in range(-1, 2):
			for di in range(-1, 3):
				var e := edge_v(i + di, j + dj)
				if e != 0:
					dm = minf(dm, _seg_dist(u - (i + di), v - (j + dj), e))
	else:
		for dj in range(-1, 3):
			for di in range(-1, 2):
				var e := edge_h(i + di, j + dj)
				if e != 0:
					dm = minf(dm, _seg_dist(v - (j + dj), u - (i + di), e))
	return _deepen(0.62 + 0.38 * smoothstep(0.0, 0.7, dm - T))


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
	return _deepen(_occl(dxm) * _occl(dzm))


## Distance (m) from a point to the solid parts of an edge. `across` is the
## offset from the edge line and `along` the position along it, both in cell
## units relative to the edge's start.
func _seg_dist(across: float, along: float, e: int) -> float:
	var da := 0.0
	if e == WorldGen.E_WALL or e == WorldGen.E_WINDOW:
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
	return _deepen((0.62 + 0.38 * smoothstep(0.0, 0.6, y - f)) * (0.8 + 0.2 * smoothstep(0.0, 0.45, c - y)))


## Realistic (contrast): contact shadows twice as deep.
func _deepen(ao: float) -> float:
	return ao * ao if _contrast else ao


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
	if not LIGHTMAPPED.has(mat) or not _lightmaps:
		lm_texel = 0.0
	lm_texel *= _lm_scale
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
				if _lucid:
					light = _face_ids
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
						light = _ao_mix(light, ao)
						light.a = light.a + floorf(_seed)  # pack seed in integer part
						cache[key] = light
					var sd := floorf(light.a)
					light.a -= sd
					_seed = sd
				else:
					light = shade(sp, nrm)
					var ao := _ao_y(p.y, f, c)
					light = _ao_mix(light, ao)
			var t: Vector2
			match uv_mode:
				0:
					t = Vector2(p.x, p.z)
				1:
					t = Vector2(p.z, -p.y)
				_:
					t = Vector2(p.x, -p.y)
			var wet := 0.0
			if mat == MAT_POOL_TILE and nrm.y > 0.5 and p.y > WorldGen.WATER_Y:
				wet = _wetness(p)
			var vi := b.add(p, nrm, tan, t, Vector2(_seed, wet), light)
			if lm_texel > 0.0:
				# Face edges land on texel centres, so filtering never reads a neighbour.
				b.set_lm(vi, Vector2(lm_at.x + 0.5 + us[iu] * (lm_n.x - 1), lm_at.y + 0.5 + vs[jv] * (lm_n.y - 1)))
	var flip := du.cross(dv).dot(nrm) > 0.0
	for jv in vs.size() - 1:
		for iu in nu - 1:
			var a := start + iu + jv * nu
			_tri_quad(b, a, a + 1, a + 1 + nu, a + nu, flip)


## How wet the floor is round a pool (1 at the rim, 0 from ~1 m away): splashed
## and dripped on, the tiles there are glossier. Goes in UV2.y (pool_tile).
func _wetness(p: Vector3) -> float:
	var ci := floori(p.x / CELL) - rx0
	var cj := floori(p.z / CELL) - rz0
	var best := 9.0
	for dj in range(-1, 2):
		for di in range(-1, 2):
			var i := ci + di
			var j := cj + dj
			if i < 0 or j < 0 or i >= W or j >= W or pool[i + j * W] == 0:
				continue
			var x0 := (rx0 + i) * CELL
			var z0 := (rz0 + j) * CELL
			var dx := maxf(maxf(x0 - p.x, p.x - x0 - CELL), 0.0)
			var dz := maxf(maxf(z0 - p.z, p.z - z0 - CELL), 0.0)
			best = minf(best, sqrt(dx * dx + dz * dz))
	return 1.0 - smoothstep(0.0, 1.1, best)


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
	var tseed := PackedFloat32Array()
	tseed.resize(n.x * n.y)
	var done := PackedByteArray()
	done.resize(n.x * n.y)
	var dirs := PackedVector3Array()
	if _dir_lm:
		dirs.resize(n.x * n.y)
	# Lucid: per texel, each switchable lamp's light (direct + bounce), for
	# the face's candidate lamps (`fl`: those it can see, and those in the
	# bounce of the cells it spans), kk floats per texel.
	var fl := PackedInt32Array()
	var swt := PackedFloat32Array()
	var kk := 0
	if _lucid:
		if _fmap.size() != lpos.size():
			_fmap.resize(lpos.size())
			_fmap.fill(-1)
		for l in _face_lights:
			if lid[l] >= 0 and _fmap[l] < 0:
				_fmap[l] = fl.size()
				fl.push_back(l)
		if _gi_ready:
			var lo := Vector2i(floori(minf(p0.x, (p0 + du + dv).x) / CELL) - rx0 - 1, floori(minf(p0.z, (p0 + du + dv).z) / CELL) - rz0 - 1)
			var hi := Vector2i(floori(maxf(p0.x, (p0 + du + dv).x) / CELL) - rx0 + 1, floori(maxf(p0.z, (p0 + du + dv).z) / CELL) - rz0 + 1)
			for cj in range(maxi(lo.y, 0), mini(hi.y, W - 1) + 1):
				for ci in range(maxi(lo.x, 0), mini(hi.x, W - 1) + 1):
					for l in _csw_l[ci + cj * W]:
						if _fmap[l] < 0:
							_fmap[l] = fl.size()
							fl.push_back(l)
		kk = fl.size()
		swt.resize(n.x * n.y * kk)
	# Lucid: the far tail and the bounce (and each lamp's part of it) are
	# smooth, so they are worked out every FIELD_STEP texels and
	# interpolated in between.
	var nodes_u := PackedInt32Array()
	var nodes_v := PackedInt32Array()
	var nfar := PackedColorArray()
	var nind := PackedColorArray()
	var nsw := PackedFloat32Array()
	if _lucid and _tail_ready:
		for t in range(0, n.x - 1, FIELD_STEP):
			nodes_u.push_back(t)
		nodes_u.push_back(n.x - 1)
		for t in range(0, n.y - 1, FIELD_STEP):
			nodes_v.push_back(t)
		nodes_v.push_back(n.y - 1)
		var nn := nodes_u.size() * nodes_v.size()
		nfar.resize(nn)
		nind.resize(nn)
		nsw.resize(nn * kk)
		var grp := 0 if nrm.y > 0.5 else (1 if nrm.y < -0.5 else 2)
		for b in nodes_v.size():
			for a in nodes_u.size():
				var p := p0 + du * (float(nodes_u[a]) / (n.x - 1)) + dv * (float(nodes_v[b]) / (n.y - 1))
				var sp := p + nrm * 0.05
				if ao_mode == 1:
					sp += _nudge(p)
				var ni := a + b * nodes_u.size()
				_field(sp.x / CELL - rx0, sp.z / CELL - rz0, sp.y, nrm)
				nfar[ni] = _fld_far
				nind[ni] = _fld_ind
				var il := _fld_ind.r + _fld_ind.g + _fld_ind.b
				for q in 4:
					var wq := _bw[q] * il
					if wq <= 0.0:
						continue
					var cl: PackedInt32Array = _csw_l[_bk[q]]
					var cs: PackedFloat32Array = _csw_s[_bk[q]]
					for x in cl.size():
						var j := _fmap[cl[x]]
						if j >= 0:
							nsw[ni * kk + j] += wq * cs[x * 3 + grp]
		_fld_sw.resize(kk)
		_fld_fl = fl
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
						if _dir_lm:
							dirs[k] = dirs[u0 + v0 * n.x] + dirs[u1 + v0 * n.x] + dirs[u0 + v1 * n.x] + dirs[u1 + v1 * n.x]
						tseed[k] = maxf(maxf(tseed[u0 + v0 * n.x], tseed[u1 + v0 * n.x]), maxf(tseed[u0 + v1 * n.x], tseed[u1 + v1 * n.x]))
						for x in kk:
							swt[k * kk + x] = (swt[(u0 + v0 * n.x) * kk + x] + swt[(u1 + v0 * n.x) * kk + x]
									+ swt[(u0 + v1 * n.x) * kk + x] + swt[(u1 + v1 * n.x) * kk + x]) * 0.25
						if c00.a >= c11.a and c00.a >= c10.a and c00.a >= c01.a:
							tseed[k] = tseed[u0 + v0 * n.x]
						done[k] = 1
						continue
				var p := p0 + du * (float(tu) / (n.x - 1)) + dv * (float(tv) / (n.y - 1))
				# Same sample point on both sides of an open cell border (so no
				# seams); points on a walled line are moved to the visible side.
				var sp := p + nrm * 0.05
				if ao_mode == 1:
					sp += _nudge(p)
				if nfar.size() > 0:
					# The field here, from the four nodes round this texel.
					var a0 := mini(tu / FIELD_STEP, nodes_u.size() - 2)
					var b0 := mini(tv / FIELD_STEP, nodes_v.size() - 2)
					var fa := float(tu - nodes_u[a0]) / (nodes_u[a0 + 1] - nodes_u[a0])
					var fb := float(tv - nodes_v[b0]) / (nodes_v[b0 + 1] - nodes_v[b0])
					var nu := nodes_u.size()
					var i00 := a0 + b0 * nu
					var w00 := (1.0 - fa) * (1.0 - fb)
					var w10 := fa * (1.0 - fb)
					var w01 := (1.0 - fa) * fb
					var w11 := fa * fb
					_fld_far = nfar[i00] * w00 + nfar[i00 + 1] * w10 + nfar[i00 + nu] * w01 + nfar[i00 + nu + 1] * w11
					_fld_ind = nind[i00] * w00 + nind[i00 + 1] * w10 + nind[i00 + nu] * w01 + nind[i00 + nu + 1] * w11
					for x in kk:
						_fld_sw[x] = nsw[i00 * kk + x] * w00 + nsw[(i00 + 1) * kk + x] * w10 \
								+ nsw[(i00 + nu) * kk + x] * w01 + nsw[(i00 + nu + 1) * kk + x] * w11
					_fld_set = true
				var light := shade(sp, nrm)
				_fld_set = false
				var ao := _ao_xz(sp) if ao_mode == 1 else _ao_y(p.y, f, c)
				if _wall_ao and ao_mode != 1 and absf(nrm.y) < 0.5:
					ao *= _ao_corner(sp, nrm)
				if _seed > 0.0:
					seeds[_seed] = seeds.get(_seed, 0.0) + light.a * (light.r + light.g + light.b)
				vals[k] = _ao_mix(light, ao)
				if kk > 0:
					for l in _swl:
						var x := _fmap[l]
						if x >= 0:
							swt[k * kk + x] = _swv_d[l] + _swv_b[l] * ao
				if _dir_lm:
					dirs[k] = _ldir
				tseed[k] = _seed
				done[k] = 1
	_face_on = false
	# Lucid: the face's slots are the SLOTS switchable lamps that give it the
	# most light; any others stay in the steady light.
	var slot := PackedInt32Array()
	if _lucid:
		var totals := PackedFloat32Array()
		totals.resize(kk)
		for k in n.x * n.y:
			for x in kk:
				totals[x] += swt[k * kk + x]
		var order := range(kk)
		order.sort_custom(func(x, y) -> bool: return totals[x] > totals[y])
		for q in mini(kk, SLOTS):
			if totals[order[q]] > 0.0:
				slot.push_back(order[q])
		_face_ids = Color(0, 0, 0, 0)
		for q in slot.size():
			_face_ids[q] = lid[fl[slot[q]]]
		for l in fl:
			_fmap[l] = -1
	var best := 0.0
	var best_w := 0.0
	for sd in seeds:
		if seeds[sd] > best_w:
			best_w = seeds[sd]
			best = sd
	if _lucid:
		best = 0.0
	for tv in n.y:
		for tu in n.x:
			var cl := vals[tu + tv * n.x]
			var o := ((at.y + tv) * LM_W + at.x + tu) * 8
			lm_bytes.encode_half(o, cl.r)
			lm_bytes.encode_half(o + 2, cl.g)
			lm_bytes.encode_half(o + 4, cl.b)
			if _lucid:
				# Slot shares: of the light with every lamp on, how much is
				# each slot lamp's (alpha, and the two bytes of lightmap_seed).
				var sh := [0.0, 0.0, 0.0]
				var tl := cl.r + cl.g + cl.b
				if tl > 0.0:
					for q in slot.size():
						sh[q] = clampf(swt[(tu + tv * n.x) * kk + slot[q]] / tl, 0.0, 1.0)
				lm_bytes.encode_half(o + 6, sh[0])
				lm_seed_bytes[o / 4] = clampi(roundi(sh[1] * 255.0), 0, 255)
				lm_seed_bytes[o / 4 + 1] = clampi(roundi(sh[2] * 255.0), 0, 255)
			else:
				lm_bytes.encode_half(o + 6, cl.a)
				# The texel's own flickering lamp (0 = none), so neighbouring faces
				# lit by the same lamp flicker together; the shader blends the
				# darkening of neighbouring texels, so there are no hard edges.
				var sd := tseed[tu + tv * n.x]
				lm_seed_bytes.encode_u16(o / 4, clampi(int(sd), 0, 65535))
			if _dir_lm:
				# Direction (0..255 per axis); alpha = how directional the
				# light is (1: one lamp, 0: none, so the shader leaves it).
				var dl := dirs[tu + tv * n.x]
				var dn := dl.normalized() if dl.length() > 0.0001 else nrm
				var od := o / 2
				lm_dir_bytes[od] = clampi(int((dn.x * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
				lm_dir_bytes[od + 1] = clampi(int((dn.y * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
				lm_dir_bytes[od + 2] = clampi(int((dn.z * 0.5 + 0.5) * 255.0 + 0.5), 0, 255)
				lm_dir_bytes[od + 3] = 255 if dl.length() > 0.0001 else 0
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
	# Sun galleries: finer lightmap on the floor so the window-shaped sun
	# patches keep crisp edges.
	var sunny := b == WorldGen.POOL and gen.gallery(gx, gz)
	_grid(FLOOR_MAT[b], Vector3(xa, f, za), Vector3(CELL, 0, 0), Vector3(0, 0, CELL), fr, fr,
			Vector3.UP, Vector3.RIGHT, 0, 1, f, c, LM_TEXEL_SUN if sunny else LM_TEXEL)
	var cr := PackedFloat32Array([0.0, 0.5, 1.0])
	_grid(CEIL_MAT[b], Vector3(xa, c, za), Vector3(CELL, 0, 0), Vector3(0, 0, CELL), cr, cr,
			Vector3.DOWN, Vector3.RIGHT, 0, 1, f, c, LM_TEXEL_CEIL)
	_col_quad(Vector3(xa, f, za), Vector3(xa + CELL, f, za), Vector3(xa + CELL, f, za + CELL), Vector3(xa, f, za + CELL))
	if _detail and CEIL_MAT[b] == MAT_CEILING_TILE:
		_tbar_grid(xa, za, c, gen.light_state(gx, gz, b) != WorldGen.L_NONE, PANEL_SIZE[b])
	if is_pool:
		_emit_water(xa, za)
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
		if _lucid and s == WorldGen.L_DEAD:
			# A dead panel's lens only reflects the room's light.
			var dl := shade(Vector3(cx, y - 0.05, cz), Vector3.DOWN) * Lucid.ALBEDO.diffuser_acrylic
			emit = Color(dl.r, dl.g, dl.b, 0.0)
		elif _lucid:
			# The lens's real luminance (cd/m2) in engine units.
			var fx: Dictionary = Lucid.FIXTURES[WorldGen.LUCID_FIXTURE[b]]
			var lc := Lucid.face_engine(fx, WorldGen.LUCID_LLF[b])
			emit = Color(lc.r, lc.g, lc.b, 0.0)
			if s == WorldGen.L_FLICKER:
				sd = gen.light_seed(gx, gz)
		elif s != WorldGen.L_DEAD:
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
		if _detail and CEIL_MAT[b] == MAT_CEILING_TILE:
			_troffer_rim(cx, cz, sz, c)
		if s != WorldGen.L_DEAD:
			_emit_halo(Vector3(cx, y - 0.05, cz), emit, sd, HALO_SIZE[b])
	# Props.
	if b == WorldGen.GARAGE:
		_emit_garage(gx, gz, xa, za, f, c)
	if b == WorldGen.PIPES:
		_emit_pipes(li, lj, xa, za, c)
	if b == WorldGen.CONCRETE and not is_pool and gen.rack_at(gx, gz):
		_emit_rack(gx, gz, xa, za, f, c)
	elif b == WorldGen.CONCRETE and not is_pool and gen.crates_at(gx, gz):
		_emit_crates(li, lj, xa, za, f, c)


## Car park: a deep beam across the ceiling on every column line, and a
## concrete wheel stop at the back of each parking bay.
func _emit_garage(gx: int, gz: int, xa: float, za: float, f: float, c: float) -> void:
	if posmod(gx, 3) == 0:
		var lo := Vector3(xa - 0.3, c - 0.45, za)
		var hi := Vector3(xa + 0.3, c, za + CELL)
		_emit_box(MAT_CONC_WALL, lo, hi, f, c, false)
		_hface(MAT_CONC_WALL, lo.x, hi.x, lo.z, hi.z, lo.y, false, 1, false)
	if posmod(gz, 4) == 0 and gen.rnd(gx, gz, 66) < 0.85:
		var z0 := za + 0.55
		_emit_box(MAT_CONC_WALL, Vector3(xa + 0.45, f, z0), Vector3(xa + CELL - 0.45, f + 0.12, z0 + 0.16), f, c, true)
		_col_box(Vector3(xa + 0.45, f, z0), Vector3(xa + CELL - 0.45, f + 0.12, z0 + 0.16))


## Pool water surface. Dense (water_sub x water_sub quads per cell) so the
## ripple simulation can displace it, but lit at only 3x3 points per cell and
## interpolated, which keeps the bake cheap.
func _emit_water(xa: float, za: float) -> void:
	var lit: Array[Color] = []
	var sds := PackedFloat32Array()
	# Too coarse for crisp sun patches: those show on the pool floor below.
	_no_sun = true
	for jv in 3:
		for iu in 3:
			var p := Vector3(xa + iu * CELL * 0.5, WorldGen.WATER_Y, za + jv * CELL * 0.5)
			var sp := p + Vector3.UP * 0.05 + _nudge(p)
			var light := shade(sp, Vector3.UP)
			var ao := _ao_xz(sp)
			lit.append(_ao_mix(light, ao))
			sds.push_back(_seed)
	_no_sun = false
	var sub_n := _water_sub
	var b := buf(MAT_WATER)
	var start := b.v.size()
	var n := sub_n + 1
	for jv in n:
		var fv := float(jv) / sub_n * 2.0
		var j0 := mini(int(fv), 1)
		var tv := fv - j0
		for iu in n:
			var fu := float(iu) / sub_n * 2.0
			var i0 := mini(int(fu), 1)
			var tu := fu - i0
			var l := lit[i0 + j0 * 3].lerp(lit[i0 + 1 + j0 * 3], tu).lerp(
					lit[i0 + (j0 + 1) * 3].lerp(lit[i0 + 1 + (j0 + 1) * 3], tu), tv)
			var sd := sds[roundi(fu) + roundi(fv) * 3]
			var p := Vector3(xa + fu * CELL * 0.5, WorldGen.WATER_Y, za + fv * CELL * 0.5)
			b.add(p, Vector3.UP, Vector3.RIGHT, Vector2(p.x, p.z), Vector2(sd, 0.0), l)
	for jv in sub_n:
		for iu in sub_n:
			var a := start + iu + jv * n
			_tri_quad(b, a, a + 1, a + 1 + n, a + n, false)


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


## One bay of racking: orange uprights and beams at 1, 2 and 2.95 m, and on
## each level pallets of boxes, some bays empty.
func _emit_rack(gx: int, gz: int, xa: float, za: float, f: float, c: float) -> void:
	var x0 := xa + 0.65
	var x1 := xa + 1.75
	# Warehouse racking: five levels, up to about 5 m under the 6 m roof.
	var top := minf(f + 5.0, c - 0.6)
	for u in [Vector2(x0, za + 0.03), Vector2(x1 - 0.08, za + 0.03), Vector2(x0, za + CELL - 0.11), Vector2(x1 - 0.08, za + CELL - 0.11)]:
		_emit_box(MAT_RACK, Vector3(u.x, f, u.y), Vector3(u.x + 0.08, top, u.y + 0.08), f, c, true)
	var levels := [f]
	for y in [f + 1.2, f + 2.4, f + 3.6, top - 0.05]:
		if y + 0.4 > c:
			continue
		levels.append(y)
		_emit_box(MAT_RACK, Vector3(x0, y - 0.11, za), Vector3(x0 + 0.06, y, za + CELL), f, c, true)
		_emit_box(MAT_RACK, Vector3(x1 - 0.06, y - 0.11, za), Vector3(x1, y, za + CELL), f, c, true)
	for li in levels.size():
		var y: float = levels[li]
		var room: float = (levels[li + 1] - 0.11 if li + 1 < levels.size() else c) - y - 0.08
		for k in 2:
			var r := gen.rnd(gx * 7 + k, gz * 5 + li, 68)
			if r < 0.3:
				continue
			var z0 := za + 0.16 + k * 1.1
			# The pallet, then a stack of cartons on it.
			_emit_box(MAT_CRATE, Vector3(x0 + 0.05, y, z0), Vector3(x1 - 0.05, y + 0.13, z0 + 1.0), f, c, true)
			var h := minf(0.35 + 0.5 * gen.rnd(gx * 7 + k, gz * 5 + li, 69), room - 0.13)
			if h > 0.15:
				var inset := 0.04 + 0.08 * r
				_emit_box(MAT_CRATE, Vector3(x0 + 0.05 + inset, y + 0.13, z0 + inset), Vector3(x1 - 0.05 - inset, y + 0.13 + h, z0 + 1.0 - inset), f, c, true)
	_col_box(Vector3(x0, f, za), Vector3(x1, top, za + CELL))


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
			if _detail and WALL_MAT[sd[2]] == MAT_WALLPAPER:
				_skirting(axis, sd[1], sd[0], a0 - T, a1 + T, sd[3], sd[4])
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
	if e == WorldGen.E_WINDOW:
		_emit_window(axis, plane, s0, o0, o1, sides, bb, bottom, top)
		return
	for sd in sides:
		var m: int = WALL_MAT[sd[2]]
		var f: float = sd[3]
		var c: float = sd[4]
		_vface(m, axis, sd[1], sd[0], a0, o0, f, c, f, c)
		_vface(m, axis, sd[1], sd[0], o1, a1, f, c, f, c)
		if _detail and m == MAT_WALLPAPER:
			_skirting(axis, sd[1], sd[0], a0 - T, o0 - 0.07, f, c)
			_skirting(axis, sd[1], sd[0], o1 + 0.07, a1 + T, f, c)
			# Archways are plain wallpapered openings; a stairwell's door has
			# its own steel frame.
			if e != WorldGen.E_PASS and not _stair_door(axis, plane, s0):
				_casing(axis, sd[1], sd[0], o0, o1, yb, yt, f, c)
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
		var m: int = MAT_GARAGE_COLUMN if b == WorldGen.GARAGE else WALL_MAT[b]
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
			light = _ao_mix(light, a)
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


## Round tiled column (Tiled Baths).
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
		light = _ao_mix(light, ao)
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


# ------------------------------------------------------- trim (Realistic) ---

## A box-shaped trim piece against a wall face: its front and top (and the
## two ends). axis/face/sgn as in _vface; a0..a1 along the wall, y0..y1 up,
## sticking out `depth` metres into the room.
func _trim_on_wall(axis: int, face: float, sgn: float, a0: float, a1: float, y0: float, y1: float, depth: float,
		f: float, c: float, ends := true) -> void:
	if a1 - a0 < 0.02:
		return
	var out := face + sgn * depth
	var nrm := Vector3(sgn, 0, 0) if axis == 0 else Vector3(0, 0, sgn)
	var P := func(along: float, y: float, off: float) -> Vector3:
		return Vector3(off, y, along) if axis == 0 else Vector3(along, y, off)
	_quad4(MAT_TRIM, P.call(a0, y0, out), P.call(a1, y0, out), P.call(a1, y1, out), P.call(a0, y1, out), nrm, 1 if axis == 0 else 2, f, c)
	_quad4(MAT_TRIM, P.call(a0, y1, face), P.call(a1, y1, face), P.call(a1, y1, out), P.call(a0, y1, out), Vector3.UP, 0, f, c)
	if ends:
		var en := Vector3(0, 0, 1) if axis == 0 else Vector3(1, 0, 0)
		_quad4(MAT_TRIM, P.call(a0, y0, face), P.call(a0, y0, out), P.call(a0, y1, out), P.call(a0, y1, face), -en, 0, f, c)
		_quad4(MAT_TRIM, P.call(a1, y0, face), P.call(a1, y0, out), P.call(a1, y1, out), P.call(a1, y1, face), en, 0, f, c)


func _skirting(axis: int, face: float, sgn: float, a0: float, a1: float, f: float, c: float) -> void:
	_trim_on_wall(axis, face, sgn, a0, a1, f, f + 0.1, 0.014, f, c)


## Whether the wall segment at (plane, s0) is a stairwell's doorway.
func _stair_door(axis: int, plane: float, s0: float) -> bool:
	var line := roundi(plane / CELL)
	var along := floori((s0 + CELL * 0.5) / CELL)
	var b := Vector2i(line, along) if axis == 0 else Vector2i(along, line)
	var a := b - (Vector2i(1, 0) if axis == 0 else Vector2i(0, 1))
	return gen.stair_block_at(a.x, a.y).x != WorldGen.NO_STAIRS or gen.stair_block_at(b.x, b.y).x != WorldGen.NO_STAIRS


## Door casing: a flat frame round the opening on this side of the wall.
func _casing(axis: int, face: float, sgn: float, o0: float, o1: float, yb: float, yt: float, f: float, c: float) -> void:
	const CW := 0.07
	_trim_on_wall(axis, face, sgn, o0 - CW, o0, yb, yt + CW, 0.02, f, c)
	_trim_on_wall(axis, face, sgn, o1, o1 + CW, yb, yt + CW, 0.02, f, c)
	_trim_on_wall(axis, face, sgn, o0, o1, yt, yt + CW, 0.02, f, c, false)


## A flat strip under the ceiling (bottom plus two sides), lit at its two ends
## only: cheap enough for the whole grid.
func _ceiling_strip(x0: float, z0: float, x1: float, z1: float, y: float, drop: float, sides := true) -> void:
	var b := buf(MAT_TRIM)
	var la := shade(Vector3(x0, y - drop - 0.05, z0), Vector3.DOWN)
	var lb := shade(Vector3(x1, y - drop - 0.05, z1), Vector3.DOWN)
	var along_x := absf(x1 - x0) > absf(z1 - z0)
	var hw := 0.012
	var side := Vector3(0, 0, hw) if along_x else Vector3(hw, 0, 0)
	var yb := y - drop
	var A := Vector3(x0, yb, z0)
	var B := Vector3(x1, yb, z1)
	var quads := [[A - side, B - side, B + side, A + side, Vector3.DOWN]]
	if sides:
		quads.append([A - side + Vector3(0, drop, 0), B - side + Vector3(0, drop, 0), B - side, A - side, -side.normalized()])
		quads.append([A + side, B + side, B + side + Vector3(0, drop, 0), A + side + Vector3(0, drop, 0), side.normalized()])
	for q in quads:
		var st := b.v.size()
		var nrm: Vector3 = q[4]
		var tan := Vector3(1, 0, 0) if along_x else Vector3(0, 0, 1)
		for k in 4:
			var p: Vector3 = q[k]
			var l := la if k == 0 or k == 3 else lb
			b.add(p, nrm, tan, Vector2(p.x + p.z, p.y), Vector2(0.0, 0.0), Color(l.r * 0.85, l.g * 0.85, l.b * 0.85, 0.0))
		var p0: Vector3 = q[0]
		_tri_quad(b, st, st + 1, st + 2, st + 3, (q[1] - p0).cross(q[3] - p0).dot(nrm) > 0.0)


## The suspended ceiling's T-bar grid (0.6 m), matching the tile shader's
## pattern; the bar through a light fitting is left out.
func _tbar_grid(xa: float, za: float, c: float, has_light: bool, panel: Vector2) -> void:
	const G := 0.6
	const DROP := 0.012
	var cx := xa + CELL * 0.5
	var cz := za + CELL * 0.5
	for k in 4:
		var x := xa + k * G
		if has_light and absf(x - cx) < panel.x * 0.5 - 0.02:
			_ceiling_strip(x, za, x, cz - panel.y * 0.5, c, DROP, false)
			_ceiling_strip(x, cz + panel.y * 0.5, x, za + CELL, c, DROP, false)
		else:
			_ceiling_strip(x, za, x, za + CELL, c, DROP, false)
	for k in 4:
		var z := za + 0.3 + k * G
		_ceiling_strip(xa, z, xa + CELL, z, c, DROP, false)


## Light fitting (troffer) rim round the panel: the diffuser sits up in a
## metal frame instead of being painted on the ceiling.
func _troffer_rim(cx: float, cz: float, sz: Vector2, c: float) -> void:
	var hx := sz.x * 0.5 + 0.02
	var hz := sz.y * 0.5 + 0.02
	_ceiling_strip(cx - hx, cz - hz, cx + hx, cz - hz, c, 0.035)
	_ceiling_strip(cx - hx, cz + hz, cx + hx, cz + hz, c, 0.035)
	_ceiling_strip(cx - hx, cz - hz, cx - hx, cz + hz, c, 0.035)
	_ceiling_strip(cx + hx, cz - hz, cx + hx, cz + hz, c, 0.035)


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


## Tall window in a sun gallery: a deep tiled reveal around frosted glass
## that glows with daylight, a soft cove where the wall meets the ceiling, and
## a shaft of sunlight falling into the hall on the sunny (+Z) side.
func _emit_window(axis: int, plane: float, s0: float, o0: float, o1: float, sides: Array, bb: int,
		bottom: float, top: float) -> void:
	var a0 := s0 + T
	var a1 := s0 + CELL - T
	var y0 := WorldGen.WIN_Y0
	var y1: float = WorldGen.DOOR_H[WorldGen.E_WINDOW]
	var sun_side := 1.0 if (WorldGen.SUN_TRAVEL.z if axis == 2 else WorldGen.SUN_TRAVEL.x) > 0.0 else -1.0
	for sd in sides:
		var m: int = WALL_MAT[sd[2]]
		var f: float = sd[3]
		var c: float = sd[4]
		_vface(m, axis, sd[1], sd[0], a0, o0, f, c, f, c)
		_vface(m, axis, sd[1], sd[0], o1, a1, f, c, f, c)
		_vface(m, axis, sd[1], sd[0], o0, o1, y1, c, f, c)
		_vface(m, axis, sd[1], sd[0], o0, o1, f, y0, f, c)
		_emit_cove(axis, sd[1], sd[0], s0, s0 + CELL, c, f)
		# Frosted glass: blazing on the sunny side, softer from behind.
		var lit: float = 1.0 if sd[0] == sun_side else 0.45
		var lc := WorldGen.SUN_COLOR * (3.2 * lit)
		var emit := Color(lc.r, lc.g, lc.b, 0.0)
		var pb := buf(MAT_LIGHT)
		var st := pb.v.size()
		var off: float = sd[0] * 0.004
		var nrm := Vector3(sd[0], 0, 0) if axis == 0 else Vector3(0, 0, sd[0])
		for q in [Vector2(o0, y0), Vector2(o1, y0), Vector2(o1, y1), Vector2(o0, y1)]:
			pb.add(_wp(axis, plane, q.x, q.y, off), nrm, Vector3.UP, Vector2(q.x * 0.3, q.y * 0.3), Vector2(0.0, 1.0), emit)
		_tri_quad(pb, st, st + 1, st + 2, st + 3, (_wp(axis, 0, 1, 0, 0) - _wp(axis, 0, 0, 0, 0)).cross(Vector3.UP).dot(nrm) > 0.0)
		if sd[0] == sun_side:
			_emit_halo(_wp(axis, plane, (o0 + o1) * 0.5, (y0 + y1) * 0.5, sd[0] * 0.3), emit * 0.35, 0.0, 2.4)
	# Reveals: jambs, head and sill.
	var other := 2 if axis == 0 else 0
	var mr: int = WALL_MAT[bb]
	_vface(mr, other, o0, 1.0, plane - T, plane + T, y0, y1, y0, y1 + 0.6)
	_vface(mr, other, o1, -1.0, plane - T, plane + T, y0, y1, y0, y1 + 0.6)
	if axis == 0:
		_hface(mr, plane - T, plane + T, o0, o1, y1, false, 1, false)
		_hface(mr, plane - T, plane + T, o0, o1, y0, true, 1, false)
	else:
		_hface(mr, o0, o1, plane - T, plane + T, y1, false, 1, false)
		_hface(mr, o0, o1, plane - T, plane + T, y0, true, 1, false)
	if _god_rays:
		_emit_sun_shaft(axis, plane + sun_side * T, o0, o1, y0, y1)
	_col_wall(axis, plane, a0 - T, a1 + T, bottom, top)


## Quarter-round cove between a wall face and the ceiling (sun galleries).
func _emit_cove(axis: int, face: float, sgn: float, s0: float, s1: float, c: float, f: float) -> void:
	const R := 0.7
	const SEGS := 6
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for k in SEGS + 1:
		var a := PI * 0.5 * k / SEGS          # 0 = on the wall, 90 deg = on the ceiling
		var off := sgn * R * (1.0 - cos(a))
		var y := c - R + R * sin(a)
		var n_off := sgn * cos(a)
		var n := Vector3(n_off, -sin(a), 0) if axis == 0 else Vector3(0, -sin(a), n_off)
		for along in [s0, s1]:
			pos.push_back(_wp(axis, face, along, y, off))
			nrm.push_back(n.normalized())
			uv.push_back(Vector2(along, R * a))
	_smooth_grid(MAT_POOL_TILE, pos, nrm, uv, 2, f, c, false)


## God rays: the window opening swept along the sunlight down to the water,
## drawn as the four sides of that slanted prism with a soft additive shader.
func _emit_sun_shaft(axis: int, face: float, o0: float, o1: float, y0: float, y1: float) -> void:
	var d := WorldGen.SUN_TRAVEL.normalized()
	var end_y := WorldGen.WATER_Y
	var corners := [Vector2(o0, y0), Vector2(o1, y0), Vector2(o1, y1), Vector2(o0, y1)]
	var near := []
	var far := []
	for q in corners:
		var p := _wp(axis, face, q.x, q.y, 0.0)
		near.append(p)
		far.append(p + d * ((q.y - end_y) / -d.y))
	var b := buf(MAT_SHAFT)
	for k in 4:
		var k2 := (k + 1) % 4
		var a: Vector3 = near[k]
		var bb: Vector3 = near[k2]
		var cc: Vector3 = far[k2]
		var dd: Vector3 = far[k]
		var n := (bb - a).cross(dd - a).normalized()
		var st := b.v.size()
		b.add(a, n, Vector3.RIGHT, Vector2(0, 0), Vector2.ZERO, Color())
		b.add(bb, n, Vector3.RIGHT, Vector2(1, 0), Vector2.ZERO, Color())
		b.add(cc, n, Vector3.RIGHT, Vector2(1, 1), Vector2.ZERO, Color())
		b.add(dd, n, Vector3.RIGHT, Vector2(0, 1), Vector2.ZERO, Color())
		_tri_quad(b, st, st + 1, st + 2, st + 3, false)


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
	if _lucid:
		lc = Lucid.face_engine(Lucid.FIXTURES.skylight)
	var emit := Color(lc.r, lc.g, lc.b, 0.0)
	var corners := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]
	for k in 4:
		var o: Vector2 = corners[k]
		pb.add(Vector3(cx + o.x * h, c - 0.01, cz + o.y * h), Vector3.DOWN, Vector3.RIGHT,
				(o + Vector2.ONE) * h, Vector2(0.0, 1.0), emit)
	_tri_quad(pb, st, st + 1, st + 2, st + 3, true)
	_emit_halo(Vector3(cx, c - 0.1, cz), emit * 0.6, 0.0, 5.0)


## Service pipes running along every wall of a Pipeworks corridor.
## Pipe runs along the walls of a Pipeworks cell. Each wall section draws
## its stretch of every pipe and decides what happens at both ends: carry on
## straight into the next section (with a coupling), meet the pipe on the
## perpendicular wall at an inside corner (elbow fitting), or, where the wall
## stops, bend 90 degrees into the wall through a flange. No open pipe ends.
const PIPE_SPECS := [[0.11, -0.32, 0.14], [0.065, -0.6, 0.1], [0.13, 0.3, 0.16]]   # radius, y (neg = from ceiling), offset

func _emit_pipes(li: int, lj: int, xa: float, za: float, c: float) -> void:
	# [edge, axis, plane, dir, along cell index (local), [prev, next] run edges,
	#  [start, end] corner edges]
	var walls := [
		[edge_v(li, lj), 0, xa, 1.0, lj, [edge_v(li, lj - 1), edge_v(li, lj + 1)], [edge_h(li, lj), edge_h(li, lj + 1)], [li, lj - 1, li, lj + 1]],
		[edge_v(li + 1, lj), 0, xa + CELL, -1.0, lj, [edge_v(li + 1, lj - 1), edge_v(li + 1, lj + 1)], [edge_h(li, lj), edge_h(li, lj + 1)], [li, lj - 1, li, lj + 1]],
		[edge_h(li, lj), 2, za, 1.0, li, [edge_h(li - 1, lj), edge_h(li + 1, lj)], [edge_v(li, lj), edge_v(li + 1, lj)], [li - 1, lj, li + 1, lj]],
		[edge_h(li, lj + 1), 2, za + CELL, -1.0, li, [edge_h(li - 1, lj + 1), edge_h(li + 1, lj + 1)], [edge_v(li, lj), edge_v(li + 1, lj)], [li - 1, lj, li + 1, lj]],
	]
	for w in walls:
		if w[0] != WorldGen.E_WALL:
			continue
		var axis: int = w[1]
		var plane: float = w[2]
		var dir: float = w[3]
		var s0 := za if axis == 0 else xa
		var gline := floori(plane / CELL + 0.5)
		var galong: int = (rz0 if axis == 0 else rx0) + int(w[4])
		var nb: Array = w[7]
		for k in PIPE_SPECS.size():
			if not _pipe_on(k, axis, gline, galong):
				continue
			var spec: Array = PIPE_SPECS[k]
			var r: float = spec[0]
			var y: float = c + spec[1] if spec[1] < 0.0 else spec[1]
			var d: float = T + spec[2]             # distance from the wall line
			var ends := []                        # per end: 0 straight, 1 corner, 2 free
			for e in 2:
				var run_ok: bool = w[5][e] == WorldGen.E_WALL and _pipe_cell(nb[e * 2], nb[e * 2 + 1]) \
						and _pipe_on(k, axis, gline, galong + (1 if e == 1 else -1))
				# Partner pipe on the perpendicular wall at this corner.
				var pline: int = (rz0 + lj + e) if axis == 0 else (rx0 + li + e)
				var palong: int = (rx0 + li) if axis == 0 else (rz0 + lj)
				if run_ok:
					ends.append(0)
				elif w[6][e] == WorldGen.E_WALL and _pipe_on(k, 2 - axis, pline, palong):
					ends.append(1)
				else:
					ends.append(2)
			_pipe_run(axis, plane, dir, s0, y, d, r, ends)


## Whether pipe k exists along a wall section (the floor pipe comes and goes
## in runs of 4 cells; the two ceiling pipes are always there).
func _pipe_on(k: int, axis: int, gline: int, galong: int) -> bool:
	if k < 2:
		return true
	return gen.rnd(gline, floori(galong / 4.0), 95 + axis) < 0.6


func _pipe_cell(i: int, j: int) -> bool:
	return bio(i, j) == WorldGen.PIPES and (i < 0 or j < 0 or i >= W or j >= W or solid[i + j * W] == 0)


## One pipe along one wall section, in (along, distance-from-wall) terms.
func _pipe_run(axis: int, plane: float, dir: float, s0: float, y: float, d: float, r: float, ends: Array) -> void:
	var pts := []                     # Vector2(along, distance)
	var rb := r * 1.1                 # bend radius for pipes turning into the wall
	var inset := 0.32
	# Start end.
	match ends[0]:
		0:
			pts.append(Vector2(s0, d))
			_collar(axis, plane, dir, Vector2(s0, d), y, r)
		1:
			pts.append(Vector2(s0 + d, d))
			_ball(_wp(axis, plane, s0 + d, y, d * dir), r * 1.18)
		2:
			# Out of the wall at `e`, then a quarter bend (centre e + rb, d - rb)
			# into the run along the wall.
			var e := s0 + inset
			pts.append(Vector2(e, T - 0.02))
			for q in 5:
				var ph := PI - PI * 0.5 * q / 4.0
				pts.append(Vector2(e + rb + rb * cos(ph), d - rb + rb * sin(ph)))
			_flange(axis, plane, dir, e, y, r)
	# End end.
	match ends[1]:
		0:
			pts.append(Vector2(s0 + CELL, d))
		1:
			pts.append(Vector2(s0 + CELL - d, d))
		2:
			var e := s0 + CELL - inset
			for q in 5:
				var ph := PI * 0.5 - PI * 0.5 * q / 4.0
				pts.append(Vector2(e - rb + rb * cos(ph), d - rb + rb * sin(ph)))
			pts.append(Vector2(e, T - 0.02))
			_flange(axis, plane, dir, e, y, r)
	var path := PackedVector3Array()
	for p2 in pts:
		var wp := _wp(axis, plane, p2.x, y, p2.y * dir)
		if path.is_empty() or path[path.size() - 1].distance_to(wp) > 0.002:
			path.push_back(wp)
	if path.size() >= 2:
		_tube(MAT_PIPE, path, r, 10, 0.0, y + 1.0)


## Coupling ring where two sections of a straight run meet.
func _collar(axis: int, plane: float, dir: float, at: Vector2, y: float, r: float) -> void:
	var a := _wp(axis, plane, at.x - 0.05, y, at.y * dir)
	var b2 := _wp(axis, plane, at.x + 0.05, y, at.y * dir)
	_tube(MAT_PIPE, PackedVector3Array([a, b2]), r * 1.22, 10, 0.0, y + 1.0)
	var t := (b2 - a).normalized()
	_annulus(a, -t, r, r * 1.22)
	_annulus(b2, t, r, r * 1.22)


## Round mounting plate where a pipe goes into the wall.
func _flange(axis: int, plane: float, dir: float, along: float, y: float, r: float) -> void:
	var n := (_wp(axis, plane, along, y, dir) - _wp(axis, plane, along, y, 0.0)).normalized()
	var base := _wp(axis, plane, along, y, (T + 0.002) * dir)
	var top := base + n * 0.025
	_tube(MAT_PIPE, PackedVector3Array([base, top]), r * 1.7, 12, 0.0, y + 1.0)
	_annulus(top, n, r * 0.95, r * 1.7)


## Flat ring (or disc when r0 = 0) facing `n`.
func _annulus(centre: Vector3, n: Vector3, r0: float, r1: float) -> void:
	var ref := Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT
	var u := n.cross(ref).normalized()
	var v := n.cross(u).normalized()
	var segs := 12
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for ring in [r0, r1]:
		for k in segs + 1:
			var a := TAU * k / segs
			pos.push_back(centre + (u * cos(a) + v * sin(a)) * ring)
			nrm.push_back(n)
			uv.push_back(Vector2(a * ring, ring))
	_smooth_grid(MAT_PIPE, pos, nrm, uv, segs + 1, 0.0, centre.y + 1.0, false)


## Ball fitting (elbow joint at inside corners).
func _ball(centre: Vector3, r: float) -> void:
	var segs := 10
	var rings := 6
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	for j in rings + 1:
		var th := PI * j / rings
		for k in segs + 1:
			var a := TAU * k / segs
			var n := Vector3(sin(th) * cos(a), cos(th), sin(th) * sin(a))
			pos.push_back(centre + n * r)
			nrm.push_back(n)
			uv.push_back(Vector2(a * r, th * r))
	_smooth_grid(MAT_PIPE, pos, nrm, uv, segs + 1, 0.0, centre.y + 1.0, false)


## Camera-facing glow quad (expanded in light_halo.gdshader).
func _emit_halo(centre: Vector3, col: Color, sd: float, size: float) -> void:
	if not _halos:
		return
	var hb := buf(MAT_HALO)
	var st := hb.v.size()
	for uv in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]:
		hb.add(centre, Vector3.DOWN, Vector3.RIGHT, uv, Vector2(sd, size), col)
	hb.idx.append_array([st, st + 1, st + 2, st, st + 2, st + 3])
