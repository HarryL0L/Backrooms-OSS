class_name LucidMeter
extends RefCounted
## L.U.C.I.D.: the camera's light meter in the Backrooms. Like a phone's
## matrix metering it looks at a grid of spots across the view and averages
## their luminance logarithmically (centre weighted), so a few lamps in
## frame don't darken the shot and a dark corner gets brighter exposure.
##
## Each spot's luminance is worked out the way the light really gets there:
## the ray's hit, its surface albedo (Lucid.ALBEDO), the illuminance from
## the real fixtures it can see (inverse square, cos^m, a ray to each
## fixture for occlusion), the baked bounce light arriving there (the
## chunk's light probe) and the flashlight's beam. One spot per call, so
## the cost is a handful of physics rays a frame.

## Spots across the view: (yaw, pitch) offsets in radians, weight.
const SPOTS := [[0.0, 0.0, 3.0], [-0.42, 0.0, 1.0], [0.42, 0.0, 1.0], [0.0, -0.3, 1.5], [0.0, 0.3, 1.0],
		[-0.42, -0.3, 1.0], [0.42, -0.3, 1.0], [-0.42, 0.3, 0.7], [0.42, 0.3, 0.7]]
## Fixtures this many cells around a spot are tested for its direct light.
const REACH := 2

var gen: WorldGen
var chunks: ChunkManager
var _log := PackedFloat32Array()
var _have := PackedByteArray()
var _next := 0


func _init(p_gen: WorldGen, p_chunks: ChunkManager) -> void:
	gen = p_gen
	chunks = p_chunks
	_log.resize(SPOTS.size())
	_have.resize(SPOTS.size())


## Measures the next spot. `basis`: the camera's; `flash`: [position,
## direction] of a lit flashlight or []. `exclude`: RIDs the rays skip.
func step(space: PhysicsDirectSpaceState3D, eye: Vector3, basis: Basis, flash: Array, exclude: Array[RID]) -> void:
	var sp: Array = SPOTS[_next]
	var i := _next
	_next = (_next + 1) % SPOTS.size()
	var dir := (basis * Vector3(sin(sp[0]), sin(sp[1]), -1.0)).normalized()
	var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 30.0)
	q.exclude = exclude
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		_have[i] = 0
		return
	var p: Vector3 = hit.position
	var n: Vector3 = hit.normal
	var c := gen.cell_of(p - n * 0.05)
	var b := gen.biome_at(c.x, c.y)
	var what := 1 if n.y > 0.6 else (2 if n.y < -0.6 else 0)
	var alb := _albedo(b, what)
	# Direct light from the fixtures this spot can see.
	var e := 0.0
	var from := p + n * 0.05
	for dz in range(-REACH, REACH + 1):
		for dx in range(-REACH, REACH + 1):
			var gx := c.x + dx
			var gz := c.y + dz
			var lb := gen.biome_at(gx, gz)
			var s := gen.light_state(gx, gz, lb)
			if s != WorldGen.L_ON and s != WorldGen.L_FLICKER:
				continue
			var fx: Dictionary = Lucid.FIXTURES[WorldGen.LUCID_FIXTURE[lb]]
			var lp := Vector3((gx + 0.5) * WorldGen.CELL, WorldGen.CEIL_H[lb] - 0.05, (gz + 0.5) * WorldGen.CELL)
			var to := lp - from
			var d := to.length()
			var ee := Lucid.illuminance(Lucid.peak_intensity(fx) * WorldGen.LUCID_LLF[lb], fx.m, to.y / d, n.dot(to) / d, d)
			if ee <= 0.0:
				continue
			var vq := PhysicsRayQueryParameters3D.create(from, lp)
			vq.exclude = exclude
			if space.intersect_ray(vq).is_empty():
				e += ee
	# The flashlight's beam.
	if flash.size() == 2:
		var fp: Vector3 = flash[0]
		var to := p - fp
		var d := to.length()
		var fx: Dictionary = Lucid.FIXTURES.flashlight
		var cone := smoothstep(cos(deg_to_rad(fx.spill)), cos(deg_to_rad(fx.beam)), to.dot(flash[1]) / d)
		e += fx.peak_cd * cone * maxf(-n.dot(to) / d, 0.0) / maxf(d * d, 0.04)
	# The bounce light the bake gathered there (E / pi, engine units).
	var pr := chunks.light_probe(p + n * 0.3, n)
	var bounce := Lucid.engine_to_lux(Lucid.lum(pr)) if pr.a >= 0.0 else e * (WorldGen.LUCID_INTERREFLECT - 1.0)
	var nits := Lucid.luminance(alb, e + bounce)
	_log[i] = log(maxf(nits, 1e-3)) / log(2.0)
	_have[i] = 1


## The metered scene luminance (cd/m2): the weighted log average of the
## spots, or -1 before any spot has been measured.
func luminance() -> float:
	var s := 0.0
	var w := 0.0
	for i in SPOTS.size():
		if _have[i] == 1:
			s += _log[i] * SPOTS[i][2]
			w += SPOTS[i][2]
	return pow(2.0, s / w) if w > 0.0 else -1.0


## The brightest spot's luminance (cd/m2), -1 if none.
func peak() -> float:
	var m := -INF
	for i in SPOTS.size():
		if _have[i] == 1:
			m = maxf(m, _log[i])
	return pow(2.0, m) if m > -INF else -1.0


func _albedo(b: int, what: int) -> float:
	var name: String = WorldGen.LUCID_ALBEDO[b][what]
	if name != "":
		return Lucid.lum(Lucid.ALBEDO[name])
	var t: Array = [ChunkBuilder.ALB_WALL, ChunkBuilder.ALB_FLOOR, ChunkBuilder.ALB_CEIL][what]
	return Lucid.lum(t[b])
