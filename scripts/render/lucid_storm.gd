class_name LucidStorm
extends Node3D
## L.U.C.I.D.: a night thunderstorm over a city (docs/LUCID.md, "The
## storm"). The level owns one and calls update() every frame; it sets the
## storm's globals (the cloud deck and its mist, `lucid_cloud`; a flash's
## lit patch of cloud and its light on everything, `lucid_lightning_*`;
## the rain's extinction and ring clock in `lucid_rain`) and draws the odd
## visible bolt far off. The level reads `rate` and `wind` for its rain and
## `thunder` (with the distance) to play the thunder.
##
## Real numbers: storm bursts of heavy rain (20-40 mm/h) on a moderate
## 6 mm/h; flashes clustered in them, three intracloud for one to ground
## (Boccippio et al. 2001); a flash to ground is 1-7 return strokes ~60 ms
## apart (Rakov & Uman 2003), some with continuing current; each stroke's
## light, ~8e7 lm s (Krider et al. 1968's optical energy, ~150 lm/W),
## lands in the phone's 1/30 s sub-frame that caught it (its night merge
## rejects the change, so the flash keeps its full brightness for that
## frame: the camera overexposes, it does not adapt that fast). Half of it
## leaves the cloud base, spread over a patch of about its thickness; the
## sky, the ground and the air see that patch through the haze and rain.
## Thunder arrives at 343 m/s from the nearest point of the channel.

signal thunder(dist: float, dir: Vector3)

const BOLT_SHADER := preload("res://shaders/lucid_bolt.gdshader")
const SOUND_SPEED := 343.0
## The deck: its base (m over the street), the extinction inside it (1/m:
## visibility ~130 m in stratus) and the scale height of the scud and wet
## haze under it, thickening exponentially toward the base (m).
const CLOUD_BASE := 400.0
const CLOUD_SIGMA := 0.03
const MIST_H := 80.0
## How fast the deck drifts (m/s; the wind at 400 m in a storm).
const DRIFT := Vector2(9.0, 3.5)
## The camera's sub-frame (s): a stroke lands in one.
const SUBFRAME := 1.0 / 30.0
## A first return stroke's luminous energy (lm s, median; log-normal).
const Q_STROKE := 8.0e7
## The flash's colour: the channel's N II / O I lines (Orville 1968),
## blue-white through the cloud.
const FLASH_K := 8000.0
## A channel's whole length (m), in and under the cloud: the visible bolt
## carries its share of the light per metre.
const CHANNEL := 6000.0

## Rain now (mm/h), the base and the burst's peak.
var rate := 6.0
var base_rate := 6.0
## The wind at street level (m/s), gusting in a burst.
var wind := Vector3(1.0, 0.0, 0.4)
## The burst now (0 lull .. 1 its peak).
var intensity := 0.0
## Settings > Reduce flashing.
var reduce := false
## Lighter work (Potato / Low): coarser integrals, fewer bolt segments.
var low := false
## The level's ground (world y).
var ground_y := 0.0
## The cloud's cover (0 clear .. 1).
var cover := 1.0
## The deck's drift so far (m), for the sky shader; the rings' clock on the
## water (s, faster in heavier rain: more drops land).
var drift := Vector2.ZERO
var rings := 0.0
## The flash now: luminous flux (lm) and its E / pi on an open surface
## facing away (engine units), the extra toward it, its direction.
var flux := 0.0
var e_flash := Color(0, 0, 0)
var e_toward := 0.0
var flash_dir := Vector3.UP
## The lit patch's centre (world) and radiance (cd/m2).
var patch := Vector3.ZERO
var patch_nits := 0.0

var _t := 0.0
var _dt := 0.0
var _rng := RandomNumberGenerator.new()
var _b0 := 90.0
var _b_ramp := 40.0
var _b_hold := 90.0
var _b_fall := 60.0
var _b_peak := 30.0
var _next_ok := 15.0
var _flashes := []
var _thunders := []
var _smooth := 0.0
var _gust := Vector3.ZERO
var _geo_key := Vector4.INF
var _geo := Vector3.ZERO
var _cam := Vector3.ZERO
var _r := 1500.0
var _rb := 4000.0
var _bolt: MeshInstance3D
var _bolt_mat: ShaderMaterial
var _col := Lucid.kelvin_rgb(FLASH_K, true)


func setup(p_seed: int, p_ground_y: float, p_low: bool) -> void:
	_rng.seed = p_seed * 7919 + 13
	ground_y = p_ground_y
	low = p_low
	top_level = true
	global_transform = Transform3D.IDENTITY
	_b0 = _rng.randf_range(40.0, 120.0)
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = BOLT_SHADER
	_bolt_mat.set_shader_parameter("colour", Vector3(_col.r, _col.g, _col.b))
	_bolt = MeshInstance3D.new()
	_bolt.material_override = _bolt_mat
	_bolt.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_bolt.visible = false
	add_child(_bolt)


## The storm a frame on: `cam` the camera (world).
func update(delta: float, cam: Vector3) -> void:
	_dt = maxf(delta, 1e-4)
	_t += delta
	_cam = cam
	drift += DRIFT * delta
	# Bursts: a ramp up, a hold, a fall, then a lull.
	var x := _t - _b0
	if x > _b_ramp + _b_hold + _b_fall:
		_b0 = _t + _rng.randf_range(70.0, 200.0)
		_b_ramp = _rng.randf_range(30.0, 60.0)
		_b_hold = _rng.randf_range(50.0, 150.0)
		_b_fall = _rng.randf_range(45.0, 90.0)
		_b_peak = _rng.randf_range(20.0, 40.0)
		x = _t - _b0
	if x < 0.0:
		intensity = 0.0
	elif x < _b_ramp:
		intensity = smoothstep(0.0, _b_ramp, x)
	elif x < _b_ramp + _b_hold:
		intensity = 1.0
	else:
		intensity = 1.0 - smoothstep(0.0, _b_fall, x - _b_ramp - _b_hold)
	rate = base_rate * pow(_b_peak / base_rate, intensity)
	# Gusts in a burst (a few slow sines): 1 m/s up to 4-5.
	var g := 1.0 + 3.0 * intensity + intensity * (0.8 * sin(_t * 0.37) + 0.6 * sin(_t * 0.91 + 1.3) + 0.4 * sin(_t * 1.7 + 4.0))
	var a := 0.38 + 0.25 * intensity * sin(_t * 0.13)
	wind = Vector3(cos(a), 0.0, sin(a)) * maxf(g, 0.5)
	rings += delta * LucidRain.impacts(rate) / LucidRain.impacts(6.0)
	# Flashes: a Poisson process, more often in a burst.
	var lam := 1.0 / 75.0 + intensity / 12.0
	if reduce:
		lam *= 0.5
	if _t > _next_ok and _rng.randf() < lam * delta:
		var lo := lerpf(5000.0, 1800.0, intensity)
		var hi := lerpf(14000.0, 7000.0, intensity)
		var cg := _rng.randf() < 0.25
		_spawn(_rng.randf() * TAU, exp(lerpf(log(lo), log(hi), _rng.randf())), cg, cg and _rng.randf() < 0.6)
	_flash_now()
	# Thunder due.
	for i in range(_thunders.size() - 1, -1, -1):
		var th: Array = _thunders[i]
		if _t >= th[0]:
			_thunders.remove_at(i)
			thunder.emit(th[1], th[2])
	_push()


## A flash `dist` m away (horizontally, its patch or strike) at azimuth
## `az` (radians from north (-Z) through east (+X)), to ground (cg) or in
## the cloud, with a visible bolt; `delay` s from now. `qa` > 0: a set
## sequence (a first stroke of qa x the median and two more in the next
## 70 ms, 0.15 s of continuing current, two more strokes at 0.32 and
## 0.4 s), so a shot or a film knows its frames.
func flash(az: float, dist: float, cg: bool, bolt := false, delay := 0.0, qa := 0.0) -> void:
	_spawn(az, dist, cg, bolt, delay, qa)


## A burst starting now (QA, the film): `ramp` s up, `hold` s at `peak` mm/h.
func burst(ramp: float, hold: float, peak: float) -> void:
	_b0 = _t
	_b_ramp = ramp
	_b_hold = hold
	_b_peak = peak


## A lull from now on for `secs` s.
func calm(secs: float) -> void:
	_b0 = _t + secs
	_next_ok = _t + secs


func _spawn(az: float, dist: float, cg: bool, bolt: bool, delay := 0.0, qa := 0.0) -> void:
	var t0 := _t + delay
	var dirh := Vector3(sin(az), 0.0, -cos(az))
	var base := ground_y + CLOUD_BASE
	var p0 := Vector3(_cam.x, base, _cam.z) + dirh * dist
	var p1 := p0
	var strokes := []
	var cc := []
	var q1 := Q_STROKE * exp(_rng.randfn(0.0, 0.6))
	var dur := 0.0
	if cg:
		# 1-7 return strokes, geometric-mean gaps of ~60 ms.
		var n := clampi(1 + _poisson(2.5), 1, 7)
		var t := 0.0
		for k in n:
			var q := q1 if k == 0 else q1 * _rng.randf_range(0.2, 0.6)
			strokes.append([t0 + t, q])
			if _rng.randf() < 0.3:
				cc.append([t0 + t + SUBFRAME, t0 + t + SUBFRAME + _rng.randf_range(0.04, 0.2), q1 * 3.0])
			t += clampf(0.06 * exp(_rng.randfn(0.0, 0.45)), 0.02, 0.15)
		dur = t + 0.2
	if qa > 0.0:
		q1 = Q_STROKE * qa
		strokes = [[t0, q1], [t0 + 0.034, q1 * 0.6], [t0 + 0.068, q1 * 0.5], [t0 + 0.32, q1 * 0.4], [t0 + 0.4, q1 * 0.3]]
		cc = [[t0 + 0.1, t0 + 0.25, q1 * 3.0]]
		dur = 0.6
	elif not cg:
		# Intracloud: a run of weaker pulses as the discharge spreads
		# through the cloud, its lit patch moving with it.
		var n := _rng.randi_range(6, 14)
		dur = _rng.randf_range(0.3, 0.8)
		for k in n:
			strokes.append([t0 + dur * (float(k) + _rng.randf() * 0.8) / n, q1 * _rng.randf_range(0.05, 0.25)])
		var m := _rng.randf() * TAU
		p1 = p0 + Vector3(cos(m), 0.0, sin(m)) * _rng.randf_range(2000.0, 6000.0)
	var f := {"t0": t0, "t1": t0 + dur + 0.1, "p0": p0, "p1": p1, "strokes": strokes, "cc": cc,
			"r": 1200.0 if cg else 1800.0, "rb": 4000.0, "bolt": bolt and dist > 2000.0}
	_flashes.append(f)
	_next_ok = t0 + (20.0 if reduce else 4.0)
	# Thunder from the nearest point: the strike, or the channel in the
	# cloud (2-3 km up) for an intracloud flash. Beyond ~16 km none is heard.
	var near := dist if cg else sqrt(dist * dist + 2500.0 * 2500.0)
	if near < 16000.0:
		_thunders.append([t0 + near / SOUND_SPEED, near, dirh])


func _poisson(m: float) -> int:
	var l := exp(-m)
	var k := 0
	var p := 1.0
	while true:
		p *= _rng.randf()
		if p <= l:
			return k
		k += 1
	return k


## Light (lm) landing in the frame that ends now, of length _dt.
func _flash_now() -> void:
	var t0 := _t - _dt
	var phi := 0.0
	var best := {}
	var best_phi := 0.0
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Dictionary = _flashes[i]
		if _t > f.t1 + 0.5:
			_flashes.remove_at(i)
			continue
		var p := 0.0
		for s: Array in f.strokes:
			var ov := minf(s[0] + SUBFRAME, _t) - maxf(s[0], t0)
			if ov > 0.0:
				p += s[1] * ov / (SUBFRAME * _dt)
		for c: Array in f.cc:
			var ov := minf(c[1], _t) - maxf(c[0], t0)
			if ov > 0.0:
				p += c[2] * ov / _dt
		phi += p
		if p > best_phi:
			best_phi = p
			best = f
	# Reduce flashing: the same light spread over a quarter second (no
	# flicker, a tenth of the peak), at half the strength.
	if reduce:
		_smooth += (phi - _smooth) * (1.0 - exp(-_dt / 0.25))
		if _smooth < 1e4:
			_smooth = 0.0
		phi = _smooth * 0.5
	else:
		_smooth = 0.0
	flux = phi
	if not best.is_empty():
		var u := clampf((_t - best.t0) / maxf(best.t1 - best.t0, 1e-3), 0.0, 1.0)
		patch = (best.p0 as Vector3).lerp(best.p1, u)
		_bolt_update(best, best_phi)
	elif not reduce or _smooth < 1.0:
		_bolt.visible = false
	if flux <= 0.0:
		patch_nits = 0.0
		e_flash = Color(0, 0, 0)
		e_toward = 0.0
		_bolt.visible = false
		return
	var r: float = best.get("r", _r)
	var rb: float = best.get("rb", _rb)
	_r = r
	_rb = rb
	# Half of it leaves the base, Lambertian, over the patch's profile:
	# exp(-(r / R)^2) + 0.12 exp(-r / Rb), whose area is pi R^2 + 0.24 pi Rb^2.
	patch_nits = 0.5 * flux / (PI * (PI * r * r + 0.24 * PI * rb * rb))
	var rel := patch - _cam
	flash_dir = rel.normalized()
	var key := Vector4(rel.x, rel.y, rel.z, r)
	if (Vector3(key.x, key.y, key.z) - Vector3(_geo_key.x, _geo_key.y, _geo_key.z)).length() > 150.0 or key.w != _geo_key.w:
		_geo_key = key
		_geo = _geometry(rel, r, rb)
	e_flash = _col * Lucid.lux_to_engine(_geo.x * patch_nits)
	e_toward = _geo.y
	if OS.get_environment("LUCID_DEBUG") != "":
		print("storm: flash %.0f m off, patch %.1f cd/m2, open ground %.2f lux (away), x%.2f toward" % [Vector2(rel.x, rel.z).length(),
				patch_nits, _geo.x * patch_nits, 1.0 + e_toward * flash_dir.dot(Vector3(flash_dir.x, 0, flash_dir.z).normalized())])


## What a patch of radiance 1 cd/m2 at `rel` (from the camera) gives an open
## surface (lux): x facing away from it, y the extra toward it (a share of
## x, per unit of n . d). The sky's integral of lucid_lightning_sky (the
## patch through the air, then the air it lights), done twice.
func _geometry(rel: Vector3, r: float, rb: float) -> Vector3:
	var d := rel.normalized()
	var away := -Vector3(d.x, 0.0, d.z).normalized()
	var toward := -away
	var sig := extinction()
	var air := Vector2.ZERO
	for pass_i in 2:
		var ea := _integrate(rel, r, rb, sig, air, away)
		var et := _integrate(rel, r, rb, sig, air, toward)
		var w := (et / maxf(ea, 1e-9) - 1.0) / maxf(toward.dot(d), 0.05)
		air = Vector2(ea / PI, w)
		if pass_i == 1:
			return Vector3(ea, w, 0.0)
	return Vector3.ZERO


func _integrate(rel: Vector3, r: float, rb: float, sig: float, air: Vector2, n: Vector3) -> float:
	var steps := 5 if low else 7
	var e := 0.0
	var d := rel.normalized()
	for i in steps:
		var el := (float(i) + 0.5) / steps * PI * 0.5
		for j in steps * 2:
			var az := (float(j) + 0.5) / (steps * 2) * TAU
			var w := Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))
			var c := n.dot(w)
			if c <= 0.0:
				continue
			var t := rel.y / maxf(w.y, 0.002)
			var tr := exp(-minf(sig * t, 60.0))
			var q := Vector2(w.x * t - rel.x, w.z * t - rel.z)
			var rr := q.length()
			var l := exp(-(rr * rr) / (r * r)) + 0.12 * exp(-rr / rb)
			var a := air.x * (0.5 + 0.5 * air.y * maxf(w.dot(d), 0.0))
			e += (l * tr + a * (1.0 - tr)) * c * cos(el) * (PI * 0.5 / steps) * (TAU / (steps * 2))
	return e


## The air's extinction the storm adds (1/m): the falling rain's
## geometric cross-section (LucidRain.sigma; its forward diffraction stays
## in the beam), which goes as R^0.63 like the measured extinction in rain.
func extinction() -> float:
	return LucidRain.sigma(rate)


## A flash's light in the sky along dir (cd/m2 RGB), the model of
## lucid_lightning_sky (for the camera's meter).
func sky_nits(dir: Vector3, haze: float) -> Color:
	if flux <= 0.0:
		return Color(0, 0, 0)
	var rel := patch - _cam
	var t := rel.y / maxf(dir.y, 0.002) if dir.y > 0.002 else 1e6
	var tr := exp(-minf((haze + extinction()) * t, 60.0))
	var q := Vector2(dir.x * minf(t, 1e6) - rel.x, dir.z * minf(t, 1e6) - rel.z)
	var rr := q.length()
	var l := exp(-(rr * rr) / (_r * _r)) + 0.12 * exp(-rr / _rb)
	var e := Lucid.engine_to_lux(Lucid.lum(e_flash)) / PI
	var a := e * (0.5 + 0.5 * e_toward * maxf(dir.dot(flash_dir), 0.0))
	return _col * (patch_nits * l * tr + a * (1.0 - tr))


## E / pi (engine units) a flash gives an open surface facing n.
func light(n: Vector3) -> Color:
	return e_flash * (1.0 + e_toward * maxf(n.dot(flash_dir), 0.0))


func _push() -> void:
	var rs := RenderingServer
	rs.global_shader_parameter_set("lucid_cloud", Vector4(ground_y + CLOUD_BASE, cover, CLOUD_SIGMA, MIST_H))
	if flux > 0.0:
		var rel := patch - _cam
		var l := _col * (patch_nits / Lucid.UNIT_NITS)
		rs.global_shader_parameter_set("lucid_lightning_p", Vector4(rel.x, rel.y, rel.z, _r))
		rs.global_shader_parameter_set("lucid_lightning_l", Vector4(l.r, l.g, l.b, _rb))
		rs.global_shader_parameter_set("lucid_lightning_e", Vector4(e_flash.r, e_flash.g, e_flash.b, e_toward))
	else:
		rs.global_shader_parameter_set("lucid_lightning_l", Vector4(0, 0, 0, 4000.0))
		rs.global_shader_parameter_set("lucid_lightning_e", Vector4.ZERO)


## Puts the storm's globals back to "off".
static func clear() -> void:
	RenderingServer.global_shader_parameter_set("lucid_cloud", Vector4(0, 0, 0, 1))
	RenderingServer.global_shader_parameter_set("lucid_lightning_l", Vector4(0, 0, 0, 1))
	RenderingServer.global_shader_parameter_set("lucid_lightning_e", Vector4.ZERO)


# ---------------------------------------------------------------- the bolt ---

## The visible channel under the cloud of a flash to ground far off: built
## when its first stroke lands, lit by the strokes as they land (a few
## frames), dark between them.
func _bolt_update(f: Dictionary, phi: float) -> void:
	if not f.bolt:
		_bolt.visible = false
		return
	if not f.has("mesh"):
		f.mesh = _bolt_mesh(f.p0)
	_bolt.mesh = f.mesh
	# Its light per metre (cd/m): the flux over the whole channel, all round.
	var ip := (phi * (0.5 if reduce else 1.0)) / (4.0 * PI * CHANNEL)
	if reduce:
		ip = _smooth * 0.5 / (4.0 * PI * CHANNEL)
	_bolt_mat.set_shader_parameter("intensity", ip / Lucid.UNIT_NITS)
	_bolt.visible = ip > 0.0


## A tortuous channel from the ground at the strike to the cloud base and
## a little into it (midpoint displacement), with a few branches.
func _bolt_mesh(top: Vector3) -> ArrayMesh:
	var g := Vector3(top.x + _rng.randf_range(-200.0, 200.0), ground_y, top.z + _rng.randf_range(-200.0, 200.0))
	var trunk := _channel(g, top + Vector3(0, 120.0, 0), 4 if low else 6, 0.2)
	var lines := [[trunk, 1.0]]
	for k in _rng.randi_range(2, 4):
		var i := _rng.randi_range(trunk.size() / 3, trunk.size() - 2)
		var a: Vector3 = trunk[i]
		var h := (a.y - ground_y) * _rng.randf_range(0.25, 0.55)
		var m := _rng.randf() * TAU
		var b := a + Vector3(cos(m) * h * 0.8, -h, sin(m) * h * 0.8)
		lines.append([_channel(a, b, 3 if low else 4, 0.25), 0.3])
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var idx := PackedInt32Array()
	for ln in lines:
		var pts: PackedVector3Array = ln[0]
		for i in pts.size() - 1:
			var a: Vector3 = pts[i]
			var b: Vector3 = pts[i + 1]
			var o := v.size()
			for c in 4:
				var at := a if c < 2 else b
				v.append(at)
				nrm.append((b - a).normalized())
				uv.append(Vector2(-1.0 if c % 2 == 0 else 1.0, ln[1]))
			idx.append_array([o, o + 1, o + 2, o + 2, o + 1, o + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	return mesh


func _channel(a: Vector3, b: Vector3, levels: int, rough: float) -> PackedVector3Array:
	var pts := PackedVector3Array([a, b])
	for l in levels:
		var out := PackedVector3Array()
		for i in pts.size() - 1:
			var p: Vector3 = pts[i]
			var q: Vector3 = pts[i + 1]
			var len := p.distance_to(q)
			out.append(p)
			out.append((p + q) * 0.5 + Vector3(_rng.randfn(0.0, 1.0), _rng.randfn(0.0, 0.3), _rng.randfn(0.0, 1.0)) * len * rough)
		out.append(pts[pts.size() - 1])
		pts = out
	return pts
