class_name LucidRain
extends MeshInstance3D
## L.U.C.I.D.: rain as a camera records it (docs/LUCID.md, "Rain"). One
## mesh, one draw call (shaders/lucid_rain.gdshader): falling drops in a box
## round the camera, splashes round it, drips from given edges. The level
## feeds it every frame (follow()): the camera's exposure time and motion,
## the nearest lights and the lit signals, the surround's light, the
## shelters. Real numbers: Marshall & Palmer (1948) sizes, Gunn & Kinzer
## (1949) fall speeds (Atlas et al. 1973's fit), at the rain rate `rate`.

const SHADER := preload("res://shaders/lucid_rain.gdshader")
## Marshall-Palmer: N(D) = N0 exp(-lambda D), N0 = 8000 /m3/mm,
## lambda = 4.1 R^-0.21 /mm (R in mm/h).
const N0 := 8000.0
## The smallest drop drawn (mm): smaller ones are too faint to see one by one.
const D_MIN := 0.5
## The falling drops' volume round the camera (m), its centre this far up.
const BOX := Vector3(14.0, 12.0, 14.0)
const BOX_LIFT := 4.0
## And round each of the four nearest lights (from 1 m over it down),
## where the drops are brightest.
const LAMP_BOX := Vector3(5.0, 6.0, 5.0)
const SPLASH_R := 6.0
## Drops on the lens: its window (m2, a body camera's ~4 x 3 cm).
const LENS_AREA := 0.0012

## Rain rate (mm/h): moderate rain is 2.5-7.6 (AMS glossary), 6 here.
var rate := 6.0
var wind := Vector3(1.0, 0.0, 0.4)
var material: ShaderMaterial
var covers: Array[AABB] = []
var _streaks := 0
var _splashes := 0
var _drips := 0
var _lamp_drops := 0


## Marshall-Palmer slope (1/mm).
static func mp_lambda(r: float) -> float:
	return 4.1 * pow(r, -0.21)


## Terminal velocity (m/s) of a drop of d mm (Atlas et al. 1973).
static func fall_speed(d: float) -> float:
	return maxf(9.65 - 10.3 * exp(-0.6 * d), 0.0)


## Drops of d_min mm and up in a cubic metre.
static func density(r: float, d_min := D_MIN) -> float:
	var l := mp_lambda(r)
	return N0 / l * exp(-l * d_min)


## Drops of d_min mm and up landing on a square metre a second
## (integral of N(D) v(D) with Atlas' fit).
static func impacts(r: float, d_min := 1.0) -> float:
	var l := mp_lambda(r)
	return N0 * (9.65 * exp(-l * d_min) / l - 10.3 * exp(-(l + 0.6) * d_min) / (l + 0.6))


## The drops' scattering coefficient (1/m): their geometric cross-section,
## integral of N(D) pi D^2 / 4 (diffraction stays within a hair of the
## forward direction).
static func sigma(r: float) -> float:
	var l := mp_lambda(r)
	return N0 * PI / 4.0 * 2.0 / (l * l * l) * 1e-6


## Builds the mesh: `streaks` falling drops round the camera, `splashes`,
## `drips`, `lamp_drops` falling drops round the four nearest lights (fewer
## on a weak phone).
func setup(streaks: int, splashes: int, drips: int, lamp_drops: int, origin: Vector3) -> void:
	_streaks = streaks
	_splashes = splashes
	_drips = drips
	_lamp_drops = lamp_drops
	var n := streaks + splashes + drips + lamp_drops
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	v.resize(n * 4)
	uv.resize(n * 4)
	uv2.resize(n * 4)
	idx.resize(n * 6)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12
	for q in n:
		var kind := 0.0 if q < streaks else (1.0 if q < streaks + splashes else (2.0 if q < streaks + splashes + drips else 3.0))
		var s := Vector4(rng.randf(), rng.randf(), rng.randf(), rng.randf())
		if kind == 2.0:
			s.z = (q - streaks - splashes + 0.5) / float(drips)
		for c in 4:
			v[q * 4 + c] = Vector3(-1.0 if c % 2 == 0 else 1.0, float(c >> 1), kind)
			uv[q * 4 + c] = Vector2(s.x, s.y)
			uv2[q * 4 + c] = Vector2(s.z, s.w)
		var b := q * 4
		var o := q * 6
		idx[o] = b
		idx[o + 1] = b + 1
		idx[o + 2] = b + 2
		idx[o + 3] = b + 2
		idx[o + 4] = b + 1
		idx[o + 5] = b + 3
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	# Placed in the shader round the camera: never culled.
	m.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	mesh = m
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	material = ShaderMaterial.new()
	material.shader = SHADER
	# After every other transparent thing: a sky dome round the camera
	# (depth_draw_never puts it in the transparent pass, sorted nearest)
	# would otherwise be drawn over the drops in front of it.
	material.render_priority = Material.RENDER_PRIORITY_MAX
	material_override = material
	var l := mp_lambda(rate)
	var drawn := float(streaks) / (BOX.x * BOX.y * BOX.z)
	_param("lambda", l)
	_param("drops_per", density(rate) / drawn)
	_param("lamp_box", LAMP_BOX)
	_param("lamp_per", density(rate) * LAMP_BOX.x * LAMP_BOX.y * LAMP_BOX.z * 4.0 / maxf(lamp_drops, 1.0))
	# Splashes: drops of 1 mm and up, each drawn crown standing for this
	# many (a crown lasts its 60 ms; one is drawn every 0.25-0.6 s).
	_param("splash_k", impacts(rate) * PI * SPLASH_R * SPLASH_R / (splashes / 0.425) if splashes > 0 else 0.0)
	_param("box", BOX)
	_param("box_lift", BOX_LIFT)
	_param("splash_r", SPLASH_R)
	_param("wind", wind)
	_param("origin", origin)


func _param(key: String, val: Variant) -> void:
	material.set_shader_parameter(key, val)


## Shelters (world boxes): no rain falls into them.
func set_covers(boxes: Array[AABB]) -> void:
	covers = boxes
	var r := PackedVector4Array()
	var t := Vector4(-1e6, -1e6, -1e6, -1e6)
	for i in 4:
		if i < boxes.size():
			var b := boxes[i]
			r.append(Vector4(b.position.x, b.position.z, b.end.x, b.end.z))
			t[i] = b.end.y
		else:
			r.append(Vector4(0, 0, 0, 0))
	_param("cover", r)
	_param("cover_top", t)


## Drip edges: [from, to, fall] (world; to == from with a radius > 0: a ring).
func set_drips(edges: Array) -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	for e in edges:
		var p0: Vector3 = e[0]
		var p1: Vector3 = e[1]
		a.append(Vector4(p0.x, p0.y, p0.z, float(e[2])))
		b.append(Vector4(p1.x, p1.y, p1.z, float(e[3]) if e.size() > 3 else 0.0))
	_param("drip_a", a)
	_param("drip_b", b)
	_param("drip_n", mini(edges.size(), 12))


## Under a shelter (world point)?
func covered(p: Vector3, margin := 0.0) -> bool:
	for b in covers:
		if p.x > b.position.x + margin and p.x < b.end.x - margin and p.z > b.position.z + margin \
				and p.z < b.end.z - margin and p.y < b.end.y:
			return true
	return false


## Each frame: the camera, its exposure time (s) and velocity (m/s), how
## much rain (0..1).
func follow(c: Camera3D, shutter: float, cam_vel: Vector3, amount: float) -> void:
	# A pixel's size at 1 m (the 3D view's own resolution).
	var vp := c.get_viewport()
	var h := float(vp.get_visible_rect().size.y) * vp.scaling_3d_scale
	_param("pix", 2.0 / (c.get_camera_projection().y.y * maxf(h, 1.0)))
	_param("shutter", shutter)
	_param("cam_vel", cam_vel)
	_param("amount", amount)


## The lights a drop scatters: [world position, cos exponent (< 0 all
## round), engine intensity Color] (8 at most), and the surround's
## radiance (engine units).
func set_lights(lights: Array, env: Color) -> void:
	var p := PackedVector4Array()
	var c := PackedVector4Array()
	for i in 8:
		if i < lights.size():
			var l: Array = lights[i]
			var at: Vector3 = l[0]
			var col: Color = l[2]
			p.append(Vector4(at.x, at.y, at.z, float(l[1])))
			c.append(Vector4(col.r, col.g, col.b, 1.0 if col.r + col.g + col.b > 0.0 else 0.0))
		else:
			p.append(Vector4.ZERO)
			c.append(Vector4.ZERO)
	_param("lamp_p", p)
	_param("lamp_i", c)
	_param("env", Vector3(env.r, env.g, env.b))


## The lit signal lenses: world positions, engine intensities, axes.
func set_signals(pos: PackedVector4Array, inten: PackedVector4Array, dirs: PackedVector4Array) -> void:
	_param("sig_p", pos)
	_param("sig_i", inten)
	_param("sig_d", dirs)


## Drops arriving on a lens a second: the visible drops (0.5 mm and up)
## swept through its window by the rain's velocity relative to it (n: the
## way the lens looks, v_cam: its velocity).
func lens_rate(n: Vector3, v_cam: Vector3) -> float:
	var v := Vector3(wind.x, -fall_speed(1.0), wind.z) - v_cam
	return density(rate) * maxf(-v.dot(n), 0.0) * LENS_AREA
