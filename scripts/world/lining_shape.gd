class_name LiningShape
extends RefCounted
## Builds the height map of "The Lining": a figure pressed out through the
## wallpaper, arms raised, palms flat, face pushed into the paper with an open
## mouth. Capsule anatomy, then the paper relaxed over it like a membrane that
## is glued back to the wall (so it tents only locally), then face detail.
## Output: RGF image, r = height (m), g = cavity (darkening of hollows).
## The wallpaper shader samples it (see shaders/wallpaper.gdshader).

const SIZE := Vector2(1.4, 2.7)     # metres covered (x across the wall, y up)
const RES := Vector2i(112, 216)

var _parts := []


static func build() -> Image:
	return LiningShape.new()._build()


func _cap(a: Vector2, b: Vector2, r: float, h: float) -> void:
	_parts.append([a, b, r, h])


func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)


func _relief(p: Vector2) -> float:
	var h := 0.0
	for c in _parts:
		var r: float = c[2]
		var d := _seg_d(p, c[0], c[1])
		if d < r * 1.6:
			var k := clampf(1.0 - (d / r) * (d / r), 0.0, 1.0)
			var v: float = c[3] * sqrt(k) + c[3] * 0.25 * exp(-pow(d / r, 2.0) * 1.5)
			h = maxf(h, v) + 0.12 * minf(h, v)
	return maxf(h, 0.0)


func _face(p: Vector2) -> float:
	var q := p - Vector2(0.035, 1.64)
	q = Vector2(q.x * cos(0.12) - q.y * sin(0.12), q.x * sin(0.12) + q.y * cos(0.12))
	var f := 0.0
	f += 0.022 * exp(-pow(q.x / 0.014, 2.0) - pow((q.y + 0.005) / 0.032, 2.0))          # nose
	f += 0.012 * exp(-pow(q.x / 0.06, 2.0) - pow((q.y - 0.045) / 0.012, 2.0))           # brow
	for sx in [-1.0, 1.0]:
		f += 0.008 * exp(-pow((q.x - sx * 0.042) / 0.02, 2.0) - pow((q.y + 0.02) / 0.016, 2.0))   # cheeks
		f -= 0.016 * exp(-pow((q.x - sx * 0.03) / 0.017, 2.0) - pow((q.y - 0.022) / 0.012, 2.0))  # eye hollows
	f -= 0.03 * exp(-pow(q.x / 0.022, 2.0) - pow((q.y + 0.06) / 0.028, 2.0))           # open mouth
	f += 0.01 * exp(-pow(q.x / 0.03, 2.0) - pow((q.y + 0.105) / 0.015, 2.0))           # chin
	return f


func _build() -> Image:
	_cap(Vector2(0.035, 1.62), Vector2(0.03, 1.69), 0.085, 0.1)     # head (pushed hardest)
	_cap(Vector2(0.03, 1.47), Vector2(0.03, 1.55), 0.045, 0.045)    # neck
	_cap(Vector2(0.02, 1.08), Vector2(0.02, 1.33), 0.15, 0.04)      # chest
	_cap(Vector2(0.02, 0.85), Vector2(0.02, 1.05), 0.12, 0.022)     # belly
	_cap(Vector2(-0.17, 1.39), Vector2(0.21, 1.39), 0.055, 0.04)    # shoulders
	_cap(Vector2(-0.18, 1.38), Vector2(-0.33, 1.63), 0.04, 0.045)   # left upper arm
	_cap(Vector2(-0.33, 1.63), Vector2(-0.29, 1.92), 0.035, 0.06)   # left forearm
	_cap(Vector2(0.22, 1.38), Vector2(0.38, 1.66), 0.04, 0.045)     # right upper arm
	_cap(Vector2(0.38, 1.66), Vector2(0.36, 2.02), 0.035, 0.065)    # right forearm (higher)
	for side in [-1.0, 1.0]:
		var palm: Vector2 = Vector2(-0.29, 1.98) if side < 0.0 else Vector2(0.36, 2.08)
		_cap(palm - Vector2(0, 0.035), palm + Vector2(0, 0.025), 0.042, 0.085)
		for f in 5:
			var ang: float = deg_to_rad(-48.0 + f * 24.0) * side
			var dirv := Vector2(sin(ang), cos(ang))
			var flen: float = [0.075, 0.105, 0.115, 0.105, 0.085][f]
			if f == 0:
				dirv = Vector2(-side * 0.95, 0.1).normalized()
				flen = 0.08
			_cap(palm + dirv * 0.035, palm + dirv * (0.035 + flen), 0.015, 0.075)
	_cap(Vector2(-0.06, 0.2), Vector2(-0.05, 0.85), 0.06, 0.012)     # legs, barely there
	_cap(Vector2(0.1, 0.2), Vector2(0.09, 0.85), 0.06, 0.012)

	var nu := RES.x
	var nv := RES.y
	var raw := PackedFloat32Array()
	raw.resize(nu * nv)
	for j in nv:
		for i in nu:
			raw[i + j * nu] = _relief(_pos(i, j))
	# Paper relaxed over the body; glue pulls it back to the wall.
	var hgt := raw.duplicate()
	for it in 22:
		var nh := hgt.duplicate()
		for j in range(1, nv - 1):
			for i in range(1, nu - 1):
				var k := i + j * nu
				nh[k] = maxf(raw[k], (hgt[k - 1] + hgt[k + 1] + hgt[k - nu] + hgt[k + nu]) * 0.25 * 0.93)
		hgt = nh
	for j in nv:
		for i in nu:
			hgt[i + j * nu] = maxf(hgt[i + j * nu] + _face(_pos(i, j)), 0.0)
	# Fade to exactly zero at the border so the wall around it is untouched.
	var img := Image.create(nu, nv, false, Image.FORMAT_RGF)
	for j in nv:
		for i in nu:
			var k := i + j * nu
			var b := hgt[k]
			if i >= 2 and j >= 2 and i < nu - 2 and j < nv - 2:
				b = (hgt[k - 2] + hgt[k + 2] + hgt[k - 2 * nu] + hgt[k + 2 * nu] + hgt[k]) * 0.2
			var cav := clampf((b - hgt[k]) * 40.0, 0.0, 0.6)
			var edge := minf(minf(i, nu - 1 - i), minf(j, nv - 1 - j))
			var fade := clampf(edge / 3.0, 0.0, 1.0)
			# Image rows go top to bottom; the shader maps y up accordingly.
			img.set_pixel(i, nv - 1 - j, Color(hgt[k] * fade, cav * fade, 0.0))
	return img


func _pos(i: int, j: int) -> Vector2:
	return Vector2(-SIZE.x * 0.5 + SIZE.x * i / (RES.x - 1), SIZE.y * j / (RES.y - 1))
