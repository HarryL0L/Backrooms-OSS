class_name LucidCity
extends RefCounted
## L.U.C.I.D. stage 3: what a city level needs (docs/LUCID.md, "stage 3").
##
## - The street grid (GRID) that the lamps, the far ground shader
##   (lucid_ground.gdshader) and the backdrop all follow, and its lamps
##   (grid_lamps), so a lamp is in the same place whether it is baked, a
##   sprite or a pool in the ground shader.
## - Surf: geometry for baking, tessellated so a vertex every metre or so
##   carries the light (sidewalk polygons with curb arcs clipped cell by
##   cell, walls, boxes, cylinders).
## - bake(): per-vertex light in engine units (E / pi) for a set of
##   surfaces, in layers: every street lamp (direct with shadow rays, plus
##   their bounce off what the gather rays hit), and one natural layer per
##   light state (the sky through a cosine-weighted gather that also sees
##   the lit windows and the lamp-lit ground around, and the moon with a
##   shadow ray), the sky visibility (the open part of the hemisphere), and
##   the three switchable lamps that matter most with their shares
##   (relightable, as stage 2). Runs offline (tools/lucid/city_bake.gd)
##   with the level's colliders in a physics space; the result is an
##   ArrayMesh with custom vertex arrays that lucid_city.gdshader reads.
## - Probe grids (light for moving things, light_at) from the same rays.
## - MultiMesh builders: backdrop buildings (lucid_blocks.gdshader) and
##   point lights (lucid_points.gdshader).
## - push_sky(): the state-blended sky to the city shaders' globals.

## The plan: avenues run along Z every AVENUE_EVERY metres, streets along X
## every STREET_EVERY; carriageway half widths and building lines (half the
## right of way). Lane 3.5 m, parking lane 2.5 m; avenue: 4 lanes + 2
## parking = 19 m carriageway, 5.5 m sidewalks; street: 2 + 2 = 12 m, 4 m
## sidewalks. Curbs 150 mm, corner radius 4.5 m.
const GRID := {"avenue_every": 110.0, "street_every": 80.0, "avenue_road": 9.5, "avenue_line": 15.0,
		"street_road": 6.0, "street_line": 10.0, "curb": 0.15, "corner_r": 4.5}
## Avenue lamps: LED 100 W heads 10 m up on 2.5 m arms from poles 0.6 m
## behind the curb, opposite pairs every 35 m (spacing / height 3.5);
## street lamps: HPS 150 W, 8 m up on 1.5 m arms, pairs at 25, 55, 85 m
## into each block.
const AVENUE_LAMP := {"fx": "led_street_100w", "llf": 0.9, "h": 10.0, "arm": 2.5, "every": 35.0, "first": 17.5}
const STREET_LAMP := {"fx": "sodium_hps_150w", "llf": 0.8, "h": 8.0, "arm": 1.5, "at": [25.0, 55.0, 85.0]}


## The grid's lamps whose heads fall inside `rect` (XZ, level space):
## [{pos (head), pole (foot), fx, llf, street (bool)}]. `avenues` /
## `streets` false leave that kind out.
static func grid_lamps(rect: Rect2, avenues := true, streets := true) -> Array:
	var out := []
	var ae: float = GRID.avenue_every
	var se: float = GRID.street_every
	if avenues:
		var head_x: float = GRID.avenue_road + 0.6 - AVENUE_LAMP.arm
		for i in range(floori(rect.position.x / ae) - 1, ceili(rect.end.x / ae) + 2):
			var xc := i * ae
			var k0 := floori((rect.position.y - AVENUE_LAMP.first) / AVENUE_LAMP.every)
			var k1 := ceili((rect.end.y - AVENUE_LAMP.first) / AVENUE_LAMP.every)
			for k in range(k0, k1 + 1):
				var z: float = AVENUE_LAMP.first + k * AVENUE_LAMP.every
				for s in [-1.0, 1.0]:
					var head := Vector3(xc + s * head_x, AVENUE_LAMP.h, z)
					if rect.has_point(Vector2(head.x, head.z)):
						out.append({"pos": head, "pole": Vector3(xc + s * (GRID.avenue_road + 0.6), 0.0, z),
								"fx": AVENUE_LAMP.fx, "llf": AVENUE_LAMP.llf, "street": false})
	if streets:
		var head_z: float = GRID.street_road + 0.6 - STREET_LAMP.arm
		for j in range(floori(rect.position.y / se) - 1, ceili(rect.end.y / se) + 2):
			var zc := j * se
			for i in range(floori(rect.position.x / ae) - 1, ceili(rect.end.x / ae) + 1):
				for a in STREET_LAMP.at:
					var x: float = i * ae + a
					for s in [-1.0, 1.0]:
						var head := Vector3(x, STREET_LAMP.h, zc + s * head_z)
						if rect.has_point(Vector2(head.x, head.z)):
							out.append({"pos": head, "pole": Vector3(x, 0.0, zc + s * (GRID.street_road + 0.6)),
									"fx": STREET_LAMP.fx, "llf": STREET_LAMP.llf, "street": true})
	return out


# -------------------------------------------------------------- geometry ---

## Geometry to bake: triangles with flat normals, vertices shared where
## position and normal agree (so the bake is smooth and the count small).
class Surf:
	extends RefCounted
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	var _keys := {}

	func vert(p: Vector3, nn: Vector3) -> int:
		var key := Vector4i(roundi(p.x * 200.0), roundi(p.y * 200.0), roundi(p.z * 200.0),
				roundi(nn.x * 4.0) * 100 + roundi(nn.y * 4.0) * 10 + roundi(nn.z * 4.0))
		if _keys.has(key):
			return _keys[key]
		var i := v.size()
		v.append(p)
		n.append(nn)
		_keys[key] = i
		return i

	## A triangle facing `nn` (wound for Godot's front faces).
	func tri(a: Vector3, b: Vector3, c: Vector3, nn: Vector3) -> void:
		var ia := vert(a, nn)
		var ib := vert(b, nn)
		var ic := vert(c, nn)
		if (b - a).cross(c - a).dot(nn) > 0.0:
			idx.append_array([ia, ic, ib])
		else:
			idx.append_array([ia, ib, ic])

	## A parallelogram o, o + a, o + b, split into cells of at most `step`
	## metres, facing `nn` (default a x b).
	func quad(o: Vector3, a: Vector3, b: Vector3, step := 1.0, nn := Vector3.ZERO) -> void:
		if nn == Vector3.ZERO:
			nn = a.cross(b).normalized()
		var na := maxi(1, ceili(a.length() / step))
		var nb := maxi(1, ceili(b.length() / step))
		for i in na:
			for j in nb:
				var p00 := o + a * (float(i) / na) + b * (float(j) / nb)
				var p10 := o + a * (float(i + 1) / na) + b * (float(j) / nb)
				var p01 := o + a * (float(i) / na) + b * (float(j + 1) / nb)
				var p11 := o + a * (float(i + 1) / na) + b * (float(j + 1) / nb)
				tri(p00, p10, p11, nn)
				tri(p00, p11, p01, nn)

	## An axis-aligned box (centre, size); `faces`: which to make (+x -x
	## +y -y +z -z as a 6-bool array, default all but the bottom). `steps`:
	## cell size for the sides and the top.
	func box(c: Vector3, s: Vector3, step := 1.0, faces := [true, true, true, false, true, true]) -> void:
		var h := s * 0.5
		if faces[0]:
			quad(c + Vector3(h.x, -h.y, -h.z), Vector3(0, 0, s.z), Vector3(0, s.y, 0), step, Vector3.RIGHT)
		if faces[1]:
			quad(c + Vector3(-h.x, -h.y, -h.z), Vector3(0, 0, s.z), Vector3(0, s.y, 0), step, Vector3.LEFT)
		if faces[2]:
			quad(c + Vector3(-h.x, h.y, -h.z), Vector3(s.x, 0, 0), Vector3(0, 0, s.z), step, Vector3.UP)
		if faces[3]:
			quad(c + Vector3(-h.x, -h.y, -h.z), Vector3(s.x, 0, 0), Vector3(0, 0, s.z), step, Vector3.DOWN)
		if faces[4]:
			quad(c + Vector3(-h.x, -h.y, h.z), Vector3(s.x, 0, 0), Vector3(0, s.y, 0), step, Vector3.BACK)
		if faces[5]:
			quad(c + Vector3(-h.x, -h.y, -h.z), Vector3(s.x, 0, 0), Vector3(0, s.y, 0), step, Vector3.FORWARD)

	## A box turned about Y by `yaw` (no tessellation finer than `step`);
	## its bottom too with `bottom` (anything seen from under it).
	func box_rot(c: Vector3, s: Vector3, yaw: float, step := 1.0, bottom := false) -> void:
		var b := Basis(Vector3.UP, yaw)
		var h := s * 0.5
		var ax := b.x * s.x
		var ay := b.y * s.y
		var az := b.z * s.z
		var o := c - b.x * h.x - b.y * h.y - b.z * h.z
		quad(o + ax, az, ay, step, b.x)
		quad(o, az, ay, step, -b.x)
		quad(o + ay, ax, az, step, b.y)
		quad(o + az, ax, ay, step, b.z)
		quad(o, ax, ay, step, -b.z)
		if bottom:
			quad(o, ax, az, step, -b.y)

	## A vertical cylinder (pole) from `base` up `h`, radius r, `sides` facets.
	func cyl(base: Vector3, r: float, h: float, sides := 8, step := 2.0) -> void:
		var nh := maxi(1, ceili(h / step))
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var am := (a0 + a1) * 0.5
			var nn := Vector3(cos(am), 0.0, sin(am))
			var p0 := Vector3(cos(a0) * r, 0.0, sin(a0) * r)
			var p1 := Vector3(cos(a1) * r, 0.0, sin(a1) * r)
			for j in nh:
				var y0 := h * j / nh
				var y1 := h * (j + 1) / nh
				tri(base + p0 + Vector3(0, y0, 0), base + p1 + Vector3(0, y0, 0), base + p1 + Vector3(0, y1, 0), nn)
				tri(base + p0 + Vector3(0, y0, 0), base + p1 + Vector3(0, y1, 0), base + p0 + Vector3(0, y1, 0), nn)

	## A flat polygon (XZ, level space) at height y, facing up, clipped
	## into cells of `step` metres (so long thin triangles never carry
	## the light across metres). `minus`: polygons cut out of it.
	func poly(pts: PackedVector2Array, y: float, step := 1.0, minus: Array = []) -> void:
		var lo := pts[0]
		var hi := pts[0]
		for p in pts:
			lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
			hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
		for i in range(floori(lo.x / step), ceili(hi.x / step)):
			for j in range(floori(lo.y / step), ceili(hi.y / step)):
				var x0 := i * step
				var z0 := j * step
				var cell := PackedVector2Array([Vector2(x0, z0), Vector2(x0 + step, z0),
						Vector2(x0 + step, z0 + step), Vector2(x0, z0 + step)])
				var pieces: Array = Geometry2D.intersect_polygons(cell, pts)
				for m in minus:
					var next := []
					for pc in pieces:
						next.append_array(Geometry2D.clip_polygons(pc, m))
					pieces = next
				for pc in pieces:
					var t := Geometry2D.triangulate_polygon(pc)
					for k in range(0, t.size(), 3):
						var a: Vector2 = pc[t[k]]
						var b: Vector2 = pc[t[k + 1]]
						var c: Vector2 = pc[t[k + 2]]
						tri(Vector3(a.x, y, a.y), Vector3(b.x, y, b.y), Vector3(c.x, y, c.y), Vector3.UP)

	## A vertical strip along the polyline a -> b from y0 to y1, facing `nn`.
	func wall(a: Vector2, b: Vector2, y0: float, y1: float, nn: Vector3, step := 1.0) -> void:
		quad(Vector3(a.x, y0, a.y), Vector3(b.x - a.x, 0, b.y - a.y), Vector3(0, y1 - y0, 0), step, nn)

	func size() -> int:
		return v.size()


## A sidewalk corner: the quadrant (sx, sz = +-1) of the crossing of the
## avenue at x = xc and the street at z = zc, from the curbs out to the
## building lines, `reach_x` / `reach_z` metres along the street / avenue
## from the crossing. Returns [polygon, curb polyline] (XZ).
static func corner_walk(xc: float, zc: float, sx: float, sz: float, reach_x: float, reach_z: float) -> Array:
	var ar: float = GRID.avenue_road
	var sr: float = GRID.street_road
	var al: float = GRID.avenue_line
	var sl: float = GRID.street_line
	var r: float = GRID.corner_r
	var curb := PackedVector2Array()
	curb.append(Vector2(ar, reach_z))
	var c := Vector2(ar + r, sr + r)
	for i in 9:
		var a := PI + PI * 0.5 * i / 8.0
		curb.append(c + Vector2(cos(a), sin(a)) * r)
	curb.append(Vector2(reach_x, sr))
	var poly := curb.duplicate()
	poly.append(Vector2(reach_x, sl))
	poly.append(Vector2(al, sl))
	poly.append(Vector2(al, reach_z))
	var out := []
	for pl in [poly, curb]:
		var q := PackedVector2Array()
		for p in pl:
			q.append(Vector2(xc + p.x * sx, zc + p.y * sz))
		if sx * sz < 0.0:
			q.reverse()
		out.append(q)
	return out


# ------------------------------------------------------------------ bake ---

## Bakes per-vertex light for `surfs` ({name: Surf}) into an ArrayMesh
## (one surface per name, named so). `lamps`: [{pos, dir (default down),
## fx, llf, idx (switchable slot index 0..31, -1 steady)}]; `states`: two
## Lucid.STATES names (A, B); `space`: a physics space holding every
## occluder, each collider's meta "lucid" = {albedo, emit_a, emit_b
## (cd/m2 Colors of lit windows on it), shop_h, shop_a, shop_b} for the
## gather. `rays`: gather rays per vertex.
static func bake(surfs: Dictionary, lamps: Array, states: Array, space: PhysicsDirectSpaceState3D, rays := 48,
		progress := Callable()) -> ArrayMesh:
	var ctx := _context(lamps, states, space, rays)
	var mesh := ArrayMesh.new()
	var done := 0
	var total := 0
	for k in surfs:
		total += (surfs[k] as Surf).size()
	for name in surfs:
		var s: Surf = surfs[name]
		if s.idx.is_empty():
			continue
		var c0 := PackedByteArray()
		var c1 := PackedByteArray()
		var c2 := PackedByteArray()
		var c3 := PackedByteArray()
		c0.resize(s.v.size() * 8)
		c1.resize(s.v.size() * 8)
		c2.resize(s.v.size() * 8)
		c3.resize(s.v.size() * 4)
		var raws := []
		for i in s.v.size():
			raws.append(_bake_point(ctx, s.v[i], s.n[i], i))
			done += 1
			if progress.is_valid() and done % 2000 == 0:
				progress.call(done, total)
		_denoise(s, raws)
		for i in s.v.size():
			var r := _finish(raws[i])
			var o := i * 8
			for ch in 4:
				c0.encode_half(o + ch * 2, r.c0[ch])
				c1.encode_half(o + ch * 2, r.c1[ch])
				c2.encode_half(o + ch * 2, r.c2[ch])
			for ch in 4:
				c3[i * 4 + ch] = clampi(roundi(r.c3[ch] * 255.0), 0, 255)
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = s.v
		arr[Mesh.ARRAY_NORMAL] = s.n
		arr[Mesh.ARRAY_INDEX] = s.idx
		arr[Mesh.ARRAY_CUSTOM0] = c0
		arr[Mesh.ARRAY_CUSTOM1] = c1
		arr[Mesh.ARRAY_CUSTOM2] = c2
		arr[Mesh.ARRAY_CUSTOM3] = c3
		var fmt := (Mesh.ARRAY_CUSTOM_RGBA_HALF << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGBA_HALF << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGBA_HALF << Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT) \
				| (Mesh.ARRAY_CUSTOM_RGBA8_UNORM << Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT)
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr, [], {}, fmt)
		mesh.surface_set_name(mesh.get_surface_count() - 1, name)
	return mesh


## What every bake point needs: lamp colours, the states' sky and moon,
## the gather's directions.
static func _context(lamps: Array, states: Array, space: PhysicsDirectSpaceState3D, rays: int) -> Dictionary:
	var ls := []
	for l in lamps:
		var fx: Dictionary = Lucid.FIXTURES[l.fx]
		ls.append({"pos": l.pos, "dir": l.get("dir", Vector3.DOWN), "m": float(fx.get("m", 0.0)),
				"c": Lucid.light_engine(fx, float(l.get("llf", 1.0))), "idx": int(l.get("idx", -1))})
	var st := []
	for sn in states:
		var s: Dictionary = Lucid.STATES[sn]
		var md := Lucid.sky_dir(s.moon_alt, s.moon_az)
		st.append({"s": s, "moon_dir": md,
				"moon": Lucid.kelvin_rgb(s.moon_k) * Lucid.lux_to_engine(s.moon_lux),
				"sky_up": Lucid.sky_illuminance(s, Vector3.UP, 12) * (1.0 / (PI * Lucid.UNIT_NITS)),
				"sky_side": Lucid.sky_illuminance(s, Vector3.RIGHT, 12) * (1.0 / (PI * Lucid.UNIT_NITS))})
	# Cosine-weighted directions (Hammersley), rotated per vertex.
	var dirs := []
	for i in rays:
		var u1 := (i + 0.5) / rays
		var u2 := _radical(i)
		var r := sqrt(u1)
		var phi := TAU * u2
		dirs.append(Vector3(r * cos(phi), sqrt(maxf(1.0 - u1, 0.0)), r * sin(phi)))
	var q := PhysicsRayQueryParameters3D.new()
	q.collide_with_areas = false
	return {"lamps": ls, "states": st, "space": space, "dirs": dirs, "q": q}


static func _radical(i: int) -> float:
	var b := i
	var f := 0.5
	var r := 0.0
	while b > 0:
		if b & 1:
			r += f
		b >>= 1
		f *= 0.5
	return r


static func _ray(ctx: Dictionary, a: Vector3, b: Vector3) -> Dictionary:
	var q: PhysicsRayQueryParameters3D = ctx.q
	q.from = a
	q.to = b
	return (ctx.space as PhysicsDirectSpaceState3D).intersect_ray(q)


## Unoccluded lamp light (engine E / pi) at a point: for the gather's hits.
static func _lamps_open(ctx: Dictionary, p: Vector3, n: Vector3) -> Color:
	var e := Color(0, 0, 0)
	for l in ctx.lamps:
		var d: Vector3 = l.pos - p
		var r2 := d.length_squared()
		if r2 > 3600.0:
			continue
		var dn := d / sqrt(r2)
		var cr := n.dot(dn)
		if cr <= 0.0:
			continue
		var ce: float = -dn.dot(l.dir)
		var em := 1.0 if l.m <= 0.0 else (pow(ce, l.m) if ce > 0.0 else 0.0)
		e += (l.c as Color) * (em * cr / maxf(r2, 1.0))
	return e


static func _bake_point(ctx: Dictionary, p: Vector3, n: Vector3, salt: int) -> Dictionary:
	var o := p + n * 0.03
	# Direct light of each lamp, with a shadow ray.
	var direct := []
	var lamps_e := Color(0, 0, 0)
	for l in ctx.lamps:
		var d: Vector3 = l.pos - p
		var r2 := d.length_squared()
		if r2 > 4900.0:
			continue
		var dn := d / sqrt(r2)
		var cr := n.dot(dn)
		if cr <= 0.0:
			continue
		var ce: float = -dn.dot(l.dir)
		var em := 1.0 if l.m <= 0.0 else (pow(ce, l.m) if ce > 0.0 else 0.0)
		if em <= 0.0:
			continue
		var e: Color = (l.c as Color) * (em * cr / r2)
		if Lucid.lum(e) < 1e-7:
			continue
		if not _ray(ctx, o, l.pos - dn * 0.25).is_empty():
			continue
		lamps_e += e
		direct.append([Lucid.lum(e), l.idx])
	# The gather: cosine-weighted rays over the hemisphere round n.
	var t1 := (Vector3.UP if absf(n.y) < 0.9 else Vector3.RIGHT).cross(n).normalized()
	var t2 := n.cross(t1)
	var rot := fposmod(float(hash(Vector3i(roundi(p.x * 20.0), roundi(p.y * 20.0), roundi(p.z * 20.0)))) * 0.61803, TAU)
	var cr_ := cos(rot)
	var sr_ := sin(rot)
	var nat := [Color(0, 0, 0), Color(0, 0, 0)]
	var bounce := Color(0, 0, 0)
	var open := 0.0
	var dirs: Array = ctx.dirs
	for dv: Vector3 in dirs:
		var lx := dv.x * cr_ - dv.z * sr_
		var lz := dv.x * sr_ + dv.z * cr_
		var w := (t1 * lx + n * dv.y + t2 * lz).normalized()
		var hit := _ray(ctx, o, o + w * 1500.0)
		if hit.is_empty():
			open += 1.0
			for si in 2:
				nat[si] += Lucid.sky_nits(ctx.states[si].s, w) / Lucid.UNIT_NITS
			continue
		var info: Dictionary = (hit.collider as Object).get_meta("lucid", {}) if hit.collider else {}
		var hp: Vector3 = hit.position
		var hn: Vector3 = hit.normal
		var alb: float = info.get("albedo", 0.3)
		# What the hit surface sends back: its lamp light, its own share of
		# sky and moon (half its sky, as a street canyon's wall gets), and
		# the mean luminance of its lit windows.
		bounce += _lamps_open(ctx, hp, hn) * alb
		var shop: bool = hp.y < float(info.get("shop_h", 0.0))
		for si in 2:
			var s: Dictionary = ctx.states[si]
			var sky: Color = s.sky_up if hn.y > 0.5 else s.sky_side
			var e: Color = sky * 0.5 + (s.moon as Color) * maxf(hn.dot(s.moon_dir), 0.0) * 0.5
			var win: Color = info.get("shop_a" if si == 0 else "shop_b", Color(0, 0, 0)) if shop \
					else info.get("emit_a" if si == 0 else "emit_b", Color(0, 0, 0))
			nat[si] += e * alb + win / Lucid.UNIT_NITS
	var k := 1.0 / dirs.size()
	bounce *= k
	open *= k
	var moon := [Color(0, 0, 0), Color(0, 0, 0)]
	for si in 2:
		nat[si] *= k
		var s: Dictionary = ctx.states[si]
		var cm := n.dot(s.moon_dir)
		if cm > 0.0 and Lucid.lum(s.moon) > 0.0 and _ray(ctx, o, o + s.moon_dir * 2000.0).is_empty():
			moon[si] = (s.moon as Color) * cm
	return {"p": p, "n": n, "direct": lamps_e, "list": direct, "bounce": bounce, "gath": nat, "moon": moon, "open": open}


## The gather (bounce, sky, windows) carries the noise of a few dozen rays
## that may or may not hit a small bright shopfront: averaged over the
## vertices of the same surface within 1.6 m facing the same way (the
## gathered light varies slowly; the direct light and the moon, which
## carry the sharp shadows, are left alone).
static func _denoise(s: Surf, raws: Array) -> void:
	var cell := 1.6
	var grid := {}
	for i in raws.size():
		var p: Vector3 = raws[i].p
		var key := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		if not grid.has(key):
			grid[key] = []
		grid[key].append(i)
	var out := []
	for i in raws.size():
		var r: Dictionary = raws[i]
		var p: Vector3 = r.p
		var n: Vector3 = r.n
		var key := Vector3i(floori(p.x / cell), floori(p.y / cell), floori(p.z / cell))
		var wsum := 0.0
		var b := Color(0, 0, 0)
		var g0 := Color(0, 0, 0)
		var g1 := Color(0, 0, 0)
		var op := 0.0
		for dx in range(-1, 2):
			for dy in range(-1, 2):
				for dz in range(-1, 2):
					var k := key + Vector3i(dx, dy, dz)
					if not grid.has(k):
						continue
					for j in grid[k]:
						var q: Dictionary = raws[j]
						if (q.n as Vector3).dot(n) < 0.9:
							continue
						var d2 := (q.p as Vector3).distance_squared_to(p)
						if d2 > cell * cell:
							continue
						var w := exp(-d2 / (0.5 * cell * cell))
						wsum += w
						b += (q.bounce as Color) * w
						g0 += (q.gath[0] as Color) * w
						g1 += (q.gath[1] as Color) * w
						op += float(q.open) * w
		out.append([b / wsum, g0 / wsum, g1 / wsum, op / wsum])
	for i in raws.size():
		raws[i].bounce = out[i][0]
		raws[i].gath = [out[i][1], out[i][2]]
		raws[i].open = out[i][3]


## A baked point's vertex data from its parts.
static func _finish(r: Dictionary) -> Dictionary:
	var lamps_e: Color = r.direct
	var direct: Array = r.list
	var open: float = r.open
	var nat := [(r.gath[0] as Color) + (r.moon[0] as Color), (r.gath[1] as Color) + (r.moon[1] as Color)]
	var lamps_all := lamps_e + (r.bounce as Color)
	# Slots: the three switchable lamps giving this point the most light.
	direct.sort_custom(func(a: Array, b: Array) -> bool: return a[0] > b[0])
	var slot_i := [0.0, 0.0, 0.0]
	var slot_s := [0.0, 0.0, 0.0]
	var total := maxf(Lucid.lum(lamps_all), 1e-9)
	var used := 0
	for dd in direct:
		if used >= 3:
			break
		if int(dd[1]) < 0:
			continue
		slot_i[used] = float(dd[1]) / 255.0
		slot_s[used] = clampf(float(dd[0]) / total, 0.0, 1.0)
		used += 1
	var a: Color = nat[0]
	var b: Color = nat[1]
	return {"c0": [lamps_all.r, lamps_all.g, lamps_all.b, open], "c1": [a.r, a.g, a.b, slot_s[0]],
			"c2": [b.r, b.g, b.b, slot_s[1]], "c3": [slot_i[0], slot_i[1], slot_i[2], slot_s[2]]}


## Light for moving things: probes on a grid (XZ `rect`, `step` m) at
## height y above `floor_y` (a Callable p -> floor height, or a float),
## each the mean of the six axis directions' light: [lamps rgb, A rgb, B
## rgb] x points, as a PackedFloat32Array (row-major, x fastest).
static func bake_probes(rect: Rect2, step: float, floor_y: Variant, y: float, lamps: Array, states: Array,
		space: PhysicsDirectSpaceState3D, rays := 16) -> PackedFloat32Array:
	var ctx := _context(lamps, states, space, rays)
	var nx := ceili(rect.size.x / step) + 1
	var nz := ceili(rect.size.y / step) + 1
	var out := PackedFloat32Array()
	out.resize(nx * nz * 9)
	var axes := [Vector3.RIGHT, Vector3.LEFT, Vector3.UP, Vector3.DOWN, Vector3.BACK, Vector3.FORWARD]
	for j in nz:
		for i in nx:
			var px := rect.position.x + i * step
			var pz := rect.position.y + j * step
			var fy: float = floor_y.call(Vector3(px, 0, pz)) if floor_y is Callable else float(floor_y)
			var p := Vector3(px, fy + y, pz)
			var acc := [Color(0, 0, 0), Color(0, 0, 0), Color(0, 0, 0)]
			for ax in axes:
				var r := _finish(_bake_point(ctx, p, ax, 0))
				acc[0] += Color(r.c0[0], r.c0[1], r.c0[2])
				acc[1] += Color(r.c1[0], r.c1[1], r.c1[2])
				acc[2] += Color(r.c2[0], r.c2[1], r.c2[2])
			var o := (j * nx + i) * 9
			for l in 3:
				var c: Color = acc[l] / 6.0
				out[o + l * 3] = c.r
				out[o + l * 3 + 1] = c.g
				out[o + l * 3 + 2] = c.b
	return out


# ---------------------------------------------------------- instancing ---

## A unit box (x, z in -0.5..0.5, y in 0..1, no bottom) for the backdrop.
static func unit_box() -> ArrayMesh:
	var s := Surf.new()
	s.box(Vector3(0, 0.5, 0), Vector3.ONE, 2.0)
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = s.v
	arr[Mesh.ARRAY_NORMAL] = s.n
	arr[Mesh.ARRAY_INDEX] = s.idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Backdrop buildings as one MultiMesh: [{pos (base centre), size, custom
## (Vector4: seed, kind code, storey, bay)}].
static func block_multimesh(list: Array, mesh: Mesh) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = list.size()
	for i in list.size():
		var b: Dictionary = list[i]
		mm.set_instance_transform(i, Transform3D(Basis.from_scale(b.size), b.pos))
		mm.set_instance_custom_data(i, Color(b.custom.x, b.custom.y, b.custom.z, b.custom.w))
	return mm


## Point lights as one MultiMesh of quads: [{pos, cd, rgb (luminance 1),
## kind (+ phase), r (m), near (m: give way to lens geometry under it)}].
static func point_multimesh(list: Array) -> MultiMesh:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = true
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	mm.mesh = q
	mm.instance_count = list.size()
	for i in list.size():
		var p: Dictionary = list[i]
		mm.set_instance_transform(i, Transform3D(Basis(), p.pos))
		mm.set_instance_color(i, p.rgb)
		mm.set_instance_custom_data(i, Color(p.cd, p.get("kind", 0.0), p.get("r", 0.2), p.get("near", 0.0)))
	return mm


## A MultiMeshInstance3D with a custom AABB covering everything (the
## point shader moves vertices, the blocks are big).
static func instance(mm: MultiMesh, mat: Material, parent: Node3D) -> MultiMeshInstance3D:
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	var aabb := mm.get_aabb()
	mi.custom_aabb = aabb.grow(30.0)
	return mi


# ------------------------------------------------------------------- sky ---

## Blends two states' sky (Lucid.sky_uniforms) by t and pushes it to the
## city shaders' globals (engine units).
static func push_sky(a: Dictionary, b: Dictionary, t: float) -> Dictionary:
	var ua := Lucid.sky_uniforms(a)
	var ub := Lucid.sky_uniforms(b)
	var k := 1.0 / Lucid.UNIT_NITS
	var zen: Color = (ua.zenith as Color).lerp(ub.zenith, t) * k
	var hor: Color = (ua.horizon as Color).lerp(ub.horizon, t) * k
	var glow: Color = (ua.glow as Color).lerp(ub.glow, t) * k
	var gd: Vector3 = (ua.glow_dir as Vector3).lerp(ub.glow_dir, t).normalized()
	var h0 := lerpf(ua.h0, ub.h0, t)
	RenderingServer.global_shader_parameter_set("lucid_sky_zenith", Vector4(zen.r, zen.g, zen.b, h0))
	RenderingServer.global_shader_parameter_set("lucid_sky_horizon", Vector4(hor.r, hor.g, hor.b, 0.0))
	RenderingServer.global_shader_parameter_set("lucid_sky_glow", Vector4(glow.r, glow.g, glow.b, 0.0))
	RenderingServer.global_shader_parameter_set("lucid_sky_glow_dir", Vector4(gd.x, gd.y, gd.z, 0.0))
	return {"zenith": zen, "horizon": hor, "glow": glow, "h0": h0}
