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
	# Head tilted hard to one side, jaw dropped far too low.
	var q := p - Vector2(0.06, 1.70)
	var ang := 0.42
	q = Vector2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang))
	var f := 0.0
	f += 0.02 * exp(-pow(q.x / 0.012, 2.0) - pow((q.y + 0.0) / 0.03, 2.0))               # thin nose
	f += 0.016 * exp(-pow(q.x / 0.055, 2.0) - pow((q.y - 0.05) / 0.011, 2.0))           # heavy brow
	for sx in [-1.0, 1.0]:
		f += 0.012 * exp(-pow((q.x - sx * 0.045) / 0.016, 2.0) - pow((q.y + 0.03) / 0.014, 2.0))  # gaunt cheekbones
		f -= 0.03 * exp(-pow((q.x - sx * 0.029) / 0.016, 2.0) - pow((q.y - 0.026) / 0.014, 2.0))  # deep eye sockets
	# The scream: a tall gaping mouth pulled downward.
	f -= 0.055 * exp(-pow(q.x / 0.02, 2.0) - pow((q.y + 0.11) / 0.06, 2.0))
	f += 0.012 * exp(-pow(q.x / 0.026, 2.0) - pow((q.y + 0.2) / 0.016, 2.0))            # chin, far down
	return f


## Rib ridges and a sunken belly on the torso.
func _ribs(p: Vector2) -> float:
	var f := 0.0
	if absf(p.x - 0.02) < 0.14:
		var across := 1.0 - pow((p.x - 0.02) / 0.14, 2.0)
		for k in 6:
			var ry := 1.38 - k * 0.055 - absf(p.x - 0.02) * 0.35
			f += 0.0045 * across * exp(-pow((p.y - ry) / 0.012, 2.0))
		f -= 0.02 * across * exp(-pow((p.y - 0.98) / 0.09, 2.0))                         # sunken belly
	return f


func _build() -> Image:
	# Almost human, but wrong: stretched neck and limbs, skeletal chest, tilted
	# head, one shoulder hiked up, fingers far too long, and a third hand.
	_cap(Vector2(0.05, 1.63), Vector2(0.075, 1.78), 0.08, 0.1)      # head (elongated, tilted)
	_cap(Vector2(0.02, 1.43), Vector2(0.045, 1.6), 0.035, 0.04)     # long thin neck
	_cap(Vector2(0.02, 1.08), Vector2(0.02, 1.36), 0.13, 0.035)     # narrow chest
	_cap(Vector2(0.02, 0.82), Vector2(0.02, 1.02), 0.09, 0.015)     # hollow belly
	_cap(Vector2(-0.16, 1.36), Vector2(0.2, 1.44), 0.045, 0.035)    # shoulders, right one hiked up
	_cap(Vector2(-0.16, 1.35), Vector2(-0.31, 1.66), 0.032, 0.04)   # left upper arm
	_cap(Vector2(-0.31, 1.66), Vector2(-0.27, 2.06), 0.026, 0.055)  # left forearm, too long
	_cap(Vector2(0.2, 1.43), Vector2(0.37, 1.74), 0.032, 0.04)      # right upper arm
	_cap(Vector2(0.37, 1.74), Vector2(0.34, 2.2), 0.026, 0.06)      # right forearm, too long
	var palms := [[Vector2(-0.27, 2.12), -1.0, 1.0], [Vector2(0.34, 2.26), 1.0, 1.0],
			[Vector2(0.31, 1.52), 1.0, 0.8]]                         # third hand beside the head
	for pd in palms:
		var palm: Vector2 = pd[0]
		var side: float = pd[1]
		var sc: float = pd[2]
		_cap(palm - Vector2(0, 0.03) * sc, palm + Vector2(0, 0.025) * sc, 0.036 * sc, 0.08)
		for f in 5:
			var ang: float = deg_to_rad(-40.0 + f * 20.0) * side
			var dirv := Vector2(sin(ang), cos(ang))
			var flen: float = [0.13, 0.17, 0.19, 0.17, 0.14][f] * sc
			if f == 0:
				dirv = Vector2(-side * 0.9, 0.3).normalized()
				flen = 0.11 * sc
			# Two joints per finger, the tip bent slightly: spidery.
			var mid := palm + dirv * (0.03 + flen * 0.55)
			var tip := mid + dirv.rotated(0.18 * side) * flen * 0.45
			_cap(palm + dirv * 0.03, mid, 0.011 * sc, 0.075)
			_cap(mid, tip, 0.009 * sc, 0.07)
	_cap(Vector2(-0.05, 0.15), Vector2(-0.045, 0.8), 0.045, 0.01)    # legs, barely there
	_cap(Vector2(0.09, 0.15), Vector2(0.085, 0.8), 0.045, 0.01)

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
			hgt[i + j * nu] = maxf(hgt[i + j * nu] + _face(_pos(i, j)) + _ribs(_pos(i, j)), 0.0)
	# Fade to exactly zero at the border so the wall around it is untouched.
	var img := Image.create(nu, nv, false, Image.FORMAT_RGF)
	for j in nv:
		for i in nu:
			var k := i + j * nu
			var b := hgt[k]
			if i >= 2 and j >= 2 and i < nu - 2 and j < nv - 2:
				b = (hgt[k - 2] + hgt[k + 2] + hgt[k - 2 * nu] + hgt[k + 2 * nu] + hgt[k]) * 0.2
			var cav := clampf((b - hgt[k]) * 40.0, 0.0, 0.6)
			# Damp, darkened paper spreading around it, and small dark tears
			# where the fingertips strain the paper.
			var pp := _pos(i, j)
			var damp := clampf(raw[k] * 6.0, 0.0, 0.18) + 0.1 * exp(-pow((pp.y - 1.4) / 0.7, 2.0) - pow(pp.x / 0.45, 2.0))
			cav = clampf(cav + damp + _tears(pp), 0.0, 0.85)
			var edge := minf(minf(i, nu - 1 - i), minf(j, nv - 1 - j))
			var fade := clampf(edge / 3.0, 0.0, 1.0)
			# Image rows go top to bottom; the shader maps y up accordingly.
			img.set_pixel(i, nv - 1 - j, Color(hgt[k] * fade, cav * fade, 0.0))
	return img


func _tears(p: Vector2) -> float:
	var t := 0.0
	for c in [Vector2(-0.33, 2.33), Vector2(-0.18, 2.3), Vector2(0.43, 2.47), Vector2(0.27, 2.45), Vector2(0.45, 1.72)]:
		var d: Vector2 = p - c
		# Thin slits, a little slanted.
		var u: Vector2 = d.rotated(0.6)
		t += 0.6 * exp(-pow(u.x / 0.03, 2.0) - pow(u.y / 0.0035, 2.0))
	return t


func _pos(i: int, j: int) -> Vector2:
	return Vector2(-SIZE.x * 0.5 + SIZE.x * i / (RES.x - 1), SIZE.y * j / (RES.y - 1))
