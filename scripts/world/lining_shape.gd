class_name LiningShape
extends RefCounted
## Builds the height map of "The Lining": a face pressing out through the
## wallpaper, and (a separate layer) two hands pressed flat beside it.
## Capsule shapes, then the paper relaxed over them like a membrane glued back
## to the wall (so it tents only locally), then facial detail. Subtle on
## purpose: the horror is in recognising it at all.
## Output: RGBF image, r = face height (m), g = cavity, b = hands height (m).
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


## An ordinary face, slightly turned, pressed into the paper.
func _face(p: Vector2) -> float:
	var q := p - Vector2(0.0, 1.66)
	var ang := 0.1
	q = Vector2(q.x * cos(ang) - q.y * sin(ang), q.x * sin(ang) + q.y * cos(ang))
	var f := 0.0
	f += 0.018 * exp(-pow(q.x / 0.012, 2.0) - pow((q.y + 0.005) / 0.028, 2.0))          # nose
	f += 0.006 * exp(-pow(q.x / 0.05, 2.0) - pow((q.y - 0.042) / 0.012, 2.0))           # brow
	for sx in [-1.0, 1.0]:
		f -= 0.009 * exp(-pow((q.x - sx * 0.03) / 0.016, 2.0) - pow((q.y - 0.02) / 0.012, 2.0))   # eye hollows
	f -= 0.012 * exp(-pow(q.x / 0.022, 2.0) - pow((q.y + 0.058) / 0.014, 2.0))          # slightly open mouth
	f += 0.005 * exp(-pow(q.x / 0.03, 2.0) - pow((q.y + 0.1) / 0.014, 2.0))             # chin
	return f


func _build() -> Image:
	# Layer 1: the face (head, a hint of neck and shoulders).
	_cap(Vector2(0.0, 1.64), Vector2(0.0, 1.69), 0.085, 0.06)       # head
	_cap(Vector2(0.0, 1.5), Vector2(0.0, 1.56), 0.045, 0.012)       # neck
	_cap(Vector2(-0.18, 1.42), Vector2(0.18, 1.42), 0.06, 0.008)    # shoulders, barely
	var face := _layer(true)
	# Layer 2: hands pressed flat either side of the face (shown sometimes).
	_parts.clear()
	for side in [-1.0, 1.0]:
		var palm := Vector2(side * 0.24, 1.7 + side * 0.04)
		_cap(palm - Vector2(0, 0.03), palm + Vector2(0, 0.025), 0.04, 0.03)
		for f in 5:
			var ang: float = deg_to_rad(-40.0 + f * 20.0) * side
			var dirv := Vector2(sin(ang), cos(ang))
			var flen: float = [0.08, 0.11, 0.12, 0.11, 0.09][f]
			if f == 0:
				dirv = Vector2(-side * 0.9, 0.25).normalized()
				flen = 0.075
			_cap(palm + dirv * 0.03, palm + dirv * (0.03 + flen), 0.011, 0.026)
	var hands := _layer(false)
	var nu := RES.x
	var nv := RES.y
	var img := Image.create(nu, nv, false, Image.FORMAT_RGBF)
	for j in nv:
		for i in nu:
			var k := i + j * nu
			var tot := face[k] + hands[k]
			var b := tot
			if i >= 2 and j >= 2 and i < nu - 2 and j < nv - 2:
				b = (face[k - 2] + face[k + 2] + face[k - 2 * nu] + face[k + 2 * nu] + face[k]) * 0.2 \
						+ (hands[k - 2] + hands[k + 2] + hands[k - 2 * nu] + hands[k + 2 * nu] + hands[k]) * 0.2
			var cav := clampf((b - tot) * 45.0, 0.0, 0.5)
			var edge := minf(minf(i, nu - 1 - i), minf(j, nv - 1 - j))
			var fade := clampf(edge / 3.0, 0.0, 1.0)
			# Image rows go top to bottom; the shader maps y up accordingly.
			img.set_pixel(i, nv - 1 - j, Color(face[k] * fade, cav * fade, hands[k] * fade))
	return img


## Height of the current parts with the paper relaxed over them;
## `with_face` adds the facial detail.
func _layer(with_face: bool) -> PackedFloat32Array:
	var nu := RES.x
	var nv := RES.y
	var raw := PackedFloat32Array()
	raw.resize(nu * nv)
	for j in nv:
		for i in nu:
			raw[i + j * nu] = _relief(_pos(i, j))
	var hgt := raw.duplicate()
	for it in 16:
		var nh := hgt.duplicate()
		for j in range(1, nv - 1):
			for i in range(1, nu - 1):
				var k := i + j * nu
				nh[k] = maxf(raw[k], (hgt[k - 1] + hgt[k + 1] + hgt[k - nu] + hgt[k + nu]) * 0.25 * 0.92)
		hgt = nh
	if with_face:
		for j in nv:
			for i in nu:
				hgt[i + j * nu] = maxf(hgt[i + j * nu] + _face(_pos(i, j)), 0.0)
	return hgt


func _pos(i: int, j: int) -> Vector2:
	return Vector2(-SIZE.x * 0.5 + SIZE.x * i / (RES.x - 1), SIZE.y * j / (RES.y - 1))
