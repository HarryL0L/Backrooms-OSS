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
## The deck: a cumulonimbus base (m over the street; thunderstorm bases
## are mostly 1-2 km up in humid mid-latitudes: WMO International Cloud
## Atlas, Craven et al. 2002), the extinction inside it (1/m: visibility
## ~130 m in cloud) and the scale height of the wet haze under it,
## thickening exponentially toward the base (m).
const CLOUD_BASE := 1200.0
const CLOUD_SIGMA := 0.03
const MIST_H := 60.0
## The scud (pannus) hanging under it: ragged wisps between SCUD.x and
## SCUD.y m over the street (round the tower tops), soft over SCUD.z m at
## the bottom and top, SCUD.w extinction inside one (1/m: visibility ~370
## m) over about a third of the sky and a veil of a quarter of it between
## (two octaves of value noise over ~700 m, lucid_mist_tau): the tower tops
## fade into it, a far bolt dims behind a wisp.
const SCUD := Vector4(200.0, 430.0, 70.0, 0.008)
## How fast the deck and its scud drift (m/s; the wind under the base).
const DRIFT := Vector2(9.0, 3.5)
## The camera's sub-frame (s): a stroke lands in one.
const SUBFRAME := 1.0 / 30.0
## A first return stroke's luminous energy (lm s, median; log-normal).
const Q_STROKE := 8.0e7
## The flash's colour (linear RGB, luminance 1 once normalised). The
## channel's visible light is mostly lines: N II from the blue to the
## green, Halpha (656 nm) in the red, O I and N I further out (Orville 1968,
## Orville & Henderson 1984); a camera's red and blue channels both catch
## strong lines: its core saturates to white, the glare round it
## violet-pink (BOLT_RGB). The cloud it lights from inside and the air round it a
## violet (FLASH_RGB); under the city's warm white balance (~4300 K) both
## read as in night photographs of lightning. Far off through kilometres
## of haze and rain its glow is a neutral grey (BOLT_FAR, blue-grey on the
## screen).
const FLASH_RGB := Color(1.15, 0.42, 0.85)
const BOLT_RGB := Color(2.4, 0.55, 0.85)
const BOLT_FAR := Color(0.75, 0.68, 0.68)
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
## Tall towers' lightning rods (world), the level's: a bolt now and then
## strikes one 1.5-6 km off.
var towers := PackedVector3Array()

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
var _col := FLASH_RGB / Lucid.lum(FLASH_RGB)
var _segs := 0
var _line_a := Vector4.ZERO
var _line_b := Vector4.ZERO


func setup(p_seed: int, p_ground_y: float, p_low: bool) -> void:
	_rng.seed = p_seed * 7919 + 13
	ground_y = p_ground_y
	low = p_low
	top_level = true
	global_transform = Transform3D.IDENTITY
	_b0 = _rng.randf_range(40.0, 120.0)
	_bolt_mat = ShaderMaterial.new()
	_bolt_mat.shader = BOLT_SHADER
	var c := BOLT_RGB / Lucid.lum(BOLT_RGB)
	var fa := BOLT_FAR / Lucid.lum(BOLT_FAR)
	_bolt_mat.set_shader_parameter("colour", Vector3(c.r, c.g, c.b))
	_bolt_mat.set_shader_parameter("far", Vector3(fa.r, fa.g, fa.b))
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
		var lo := lerpf(5000.0, 1500.0, intensity)
		var hi := lerpf(14000.0, 7000.0, intensity)
		var cg := _rng.randf() < 0.25
		var dist := exp(lerpf(log(lo), log(hi), _rng.randf()))
		var az := _rng.randf() * TAU
		# In a burst, now and then a strike ~1 km off.
		if cg and intensity > 0.5 and _rng.randf() < 0.06:
			dist = _rng.randf_range(800.0, 1300.0)
		# A visible channel to ground within ~7 km (beyond, the haze takes
		# it); one in six of those to a tall tower's rod 1.5-6 km off; an
		# intracloud flash within 8 km now and then shows its spider
		# channels along the base.
		var bolt := (dist < 7000.0 and _rng.randf() < 0.85) if cg else (dist < 8000.0 and _rng.randf() < 0.3)
		var rod := Vector3.INF
		if cg and bolt and _rng.randf() < 0.17:
			rod = _pick_tower(1500.0, 6000.0)
		_spawn(az, dist, cg, bolt, 0.0, 0.0, rod)
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


## A flash to ground striking `at` (world: a tower's rod) with its bolt,
## as flash() (QA, the film).
func strike(at: Vector3, delay := 0.0, qa := 0.0) -> void:
	if at != Vector3.INF:
		_spawn(0.0, 0.0, true, true, delay, qa, at)


## A tower's rod `lo`-`hi` m off (horizontally), or INF.
func _pick_tower(lo: float, hi: float) -> Vector3:
	var ok := []
	for t in towers:
		var d := Vector2(t.x - _cam.x, t.z - _cam.z).length()
		if d > lo and d < hi:
			ok.append(t)
	return Vector3.INF if ok.is_empty() else ok[_rng.randi() % ok.size()]


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


func _spawn(az: float, dist: float, cg: bool, bolt: bool, delay := 0.0, qa := 0.0, at := Vector3.INF) -> void:
	var t0 := _t + delay
	var dirh := Vector3(sin(az), 0.0, -cos(az))
	var base := ground_y + CLOUD_BASE
	var g := Vector3(_cam.x, ground_y, _cam.z) + dirh * dist
	if at != Vector3.INF:
		g = at
		dirh = Vector3(at.x - _cam.x, 0.0, at.z - _cam.z)
		dist = dirh.length()
		dirh /= maxf(dist, 1.0)
	# The channel leaves the base up to a third of its height to the side
	# of the strike (a slanting bolt); the patch is lit round that point.
	var top := g
	if cg:
		var m := _rng.randf() * TAU
		top += Vector3(cos(m), 0.0, sin(m)) * _rng.randf_range(0.0, 0.35) * CLOUD_BASE
	var p0 := Vector3(top.x, base, top.z)
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
			"r": 1200.0 if cg else 1800.0, "rb": 4000.0, "bolt": bolt, "cg": cg}
	# Thunder from the nearest point: the strike, or the channel in the
	# cloud (2-3 km up) for an intracloud flash. Beyond ~16 km none is heard.
	var near := dist if cg else sqrt(dist * dist + 2500.0 * 2500.0)
	if bolt:
		# The channel, built now (once): its nearest point gives the thunder.
		var paths := _bolt_paths(p0 + Vector3(0.0, 250.0, 0.0), g, cg, _cam.distance_to(g))
		f.mesh = _bolt_mesh(paths, g if cg else Vector3.INF)
		var tr: PackedVector3Array = paths[0].p
		f.line = [tr[0], tr[tr.size() - 1]]
		if cg:
			for q in tr:
				near = minf(near, _cam.distance_to(q))
	_flashes.append(f)
	_next_ok = t0 + (20.0 if reduce else 4.0)
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
	var best_first := 0.0
	for i in range(_flashes.size() - 1, -1, -1):
		var f: Dictionary = _flashes[i]
		if _t > f.t1 + 0.5:
			_flashes.remove_at(i)
			continue
		var p := 0.0
		var first := 0.0
		for s: Array in f.strokes:
			var ov := minf(s[0] + SUBFRAME, _t) - maxf(s[0], t0)
			if ov > 0.0:
				p += s[1] * ov / (SUBFRAME * _dt)
				if s == f.strokes[0]:
					first = p
		for c: Array in f.cc:
			var ov := minf(c[1], _t) - maxf(c[0], t0)
			if ov > 0.0:
				p += c[2] * ov / _dt
		phi += p
		if p > best_phi:
			best_phi = p
			best = f
			best_first = first
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
		_bolt_update(best, best_phi, best_first / best_phi if best.cg else 1.0)
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
	rs.global_shader_parameter_set("lucid_scud", Vector4(ground_y + SCUD.x, ground_y + SCUD.y, SCUD.z, SCUD.w * cover))
	# The air round a lit channel (lucid_bolt_sky): its ends from the
	# camera and its light per metre.
	rs.global_shader_parameter_set("lucid_bolt_a", _line_a if _bolt.visible else Vector4.ZERO)
	rs.global_shader_parameter_set("lucid_bolt_b", _line_b)
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
	RenderingServer.global_shader_parameter_set("lucid_scud", Vector4(0, 1, 1, 0))
	RenderingServer.global_shader_parameter_set("lucid_bolt_a", Vector4.ZERO)
	RenderingServer.global_shader_parameter_set("lucid_lightning_l", Vector4(0, 0, 0, 1))
	RenderingServer.global_shader_parameter_set("lucid_lightning_e", Vector4.ZERO)


# ---------------------------------------------------------------- the bolt ---

## Tortuosity: at every scale (the leader's 40-110 m steps, then halved
## down to ~1.3 pixels) a segment turns off its parent's chord by an angle
## drawn from an exponential (mostly a little, now and then a sharp kink;
## at most 50 degrees), so the path is self-similar: its segments deviate
## from the mean path by ~16 degrees on average whatever their length, as
## Hill (1968) measured on photographs over 5-70 m segments. LEAD_KINK the
## leader's steps (rad, mean), KINK each halving.
const LEAD_KINK := 0.2
const KINK := 0.1
const KINK_MAX := 0.87
## No more branches once a bolt has this many segments (a third on Potato
## and Low).
const SEG_BUDGET := 2400


## The visible channels of a flash with a bolt: built when it fires, lit
## by its strokes as they land (a few frames), dark between them; the
## branches only in the first stroke (the stepped leader's channels, lit
## once), the trunk by every stroke and its continuing current.
func _bolt_update(f: Dictionary, phi: float, share: float) -> void:
	if not f.bolt:
		_bolt.visible = false
		return
	_bolt.mesh = f.mesh
	# Its light per metre (cd/m): the flux over the whole channel, all round.
	var ip := phi / (4.0 * PI * CHANNEL)
	if reduce:
		ip = _smooth * 0.5 / (4.0 * PI * CHANNEL)
		share = 0.5
	_bolt_mat.set_shader_parameter("intensity", ip / Lucid.UNIT_NITS)
	_bolt_mat.set_shader_parameter("branches", share)
	_bolt_mat.set_shader_parameter("soft", 0.7 if reduce else 0.0)
	_bolt.visible = ip > 0.0
	var a: Vector3 = f.line[0] - _cam
	var b: Vector3 = f.line[1] - _cam
	_line_a = Vector4(a.x, a.y, a.z, ip / Lucid.UNIT_NITS)
	_line_b = Vector4(b.x, b.y, b.z, 0.0)


## A flash's channels as polylines [{p: its points (world), b: the
## brightness at each (1 the trunk at the ground), br: 1 a branch, lit by
## the first stroke only}]. To ground (cg): the trunk from `top` (in the
## cloud) down to `g`, a stepped leader's walk; branches off its upper two
## thirds spreading sideways and down, sub-branches off them, each fainter,
## most ending in mid-air; in one flash in three spider channels running
## along the base. In the cloud: only the spiders. `dist` (m) sets the
## finest segment (~1.3 pixels at 70 degrees over 720 px).
func _bolt_paths(top: Vector3, g: Vector3, cg: bool, dist: float) -> Array:
	var fine := clampf(dist * 0.0025, 6.0, 16.0) * (2.0 if low else 1.0)
	var base := ground_y + CLOUD_BASE
	var paths := []
	_segs = 0
	if cg:
		var h := top.y - g.y
		var trunk := _refine(_leader(top, Vector3.DOWN, h * 2.0, clampf(h / 14.0, 40.0, 110.0), g, 0.0), fine)
		var b := PackedFloat32Array()
		for q in trunk:
			# Brightest low down, where the return stroke's current is
			# highest, fading up the channel.
			b.append(lerpf(1.0, 0.55, clampf((q.y - g.y) / h, 0.0, 1.0)))
		paths.append({"p": trunk, "b": b, "br": 0.0})
		_segs += trunk.size()
		var n1 := _rng.randi_range(3, 6) if low else _rng.randi_range(7, 12)
		for k in n1:
			# More near the top (the leader branched as it came down).
			var i := int(pow(_rng.randf(), 1.5) * 0.65 * (trunk.size() - 1))
			_branch(paths, trunk, i, b[i] * _rng.randf_range(0.12, 0.35), h * _rng.randf_range(0.2, 0.7), 1, fine, 1.0)
	if not cg or _rng.randf() < 0.33:
		var start := Vector3(top.x, base - 200.0, top.z)
		var bs := 0.6 if not cg else 0.3
		for k in (1 if low else _rng.randi_range(1, 3)):
			if k > 0 and _segs > SEG_BUDGET:
				break
			var m := _rng.randf() * TAU
			var len := _rng.randf_range(1500.0, 4500.0)
			var pts := _refine(_leader(start, Vector3(cos(m), 0.0, sin(m)), len, clampf(len / 14.0, 60.0, 200.0), Vector3.INF, 0.0, base - 210.0),
					fine * 1.5)
			var b := PackedFloat32Array()
			for j in pts.size():
				b.append(bs * lerpf(1.0, 0.25, float(j) / pts.size()))
			paths.append({"p": pts, "b": b, "br": 1.0 if cg else 0.0})
			_segs += pts.size()
			for s in (1 if low else _rng.randi_range(2, 5)):
				var j := int(_rng.randf_range(0.1, 0.8) * (pts.size() - 1))
				_branch(paths, pts, j, b[j] * 0.5, len * _rng.randf_range(0.15, 0.35), 2, fine * 1.5, 1.0 if cg else 0.0, base - 210.0)
	return paths


## A branch off `parent` at its point i: `len` m, starting `b0` bright and
## fading to a sixth at its tip (in mid-air, or at the ground), turned
## 35-75 degrees off the parent and drooping (or held near the height
## `hold`: a spider's), with sub-branches of its own (generation `gen`);
## `br` 1 if lit by the first stroke only.
func _branch(paths: Array, parent: PackedVector3Array, i: int, b0: float, len: float, gen: int, fine: float, br: float, hold := INF) -> void:
	if _segs > SEG_BUDGET / (3 if low else 1):
		return
	var a: Vector3 = parent[i]
	var d := _turn((parent[mini(i + 1, parent.size() - 1)] - parent[maxi(i - 1, 0)]).normalized(), _rng.randf_range(0.6, 1.3))
	if hold == INF:
		d.y = minf(d.y, -0.05)
	d = d.normalized()
	var pts := _refine(_leader(a, d, len, clampf(len / 8.0, 10.0, 90.0), Vector3.INF, 0.035 if hold == INF else 0.0, hold), fine)
	for j in pts.size():
		if pts[j].y < ground_y + 2.0:
			pts.resize(maxi(j, 2))
			break
	var b := PackedFloat32Array()
	for j in pts.size():
		b.append(b0 * lerpf(1.0, 0.16, float(j) / pts.size()))
	paths.append({"p": pts, "b": b, "br": br})
	_segs += pts.size()
	if gen < (2 if low else 3):
		for k in _rng.randi_range(0, 2 if gen == 1 else 1):
			var j := int(_rng.randf_range(0.1, 0.7) * (pts.size() - 1))
			_branch(paths, pts, j, b[j] * _rng.randf_range(0.35, 0.5), len * _rng.randf_range(0.2, 0.5), gen + 1, fine, br, hold)


## The leader's coarse walk from a: steps of ~`step` m, each turned off the
## mean path by an exponential angle of mean LEAD_KINK; the mean path
## heads for `target` (re-aimed every step; the walk ends on it), or else
## starts along `dir` and bends slowly, sinking by `sink` a step (a branch)
## or held near the height `hold` (a spider), for `len` m.
func _leader(a: Vector3, dir: Vector3, len: float, step: float, target: Vector3, sink: float, hold := INF) -> PackedVector3Array:
	var pts := PackedVector3Array([a])
	var p := a
	var mean := dir
	var run := 0.0
	while run < len:
		if target != Vector3.INF:
			var to := target - p
			if to.length() < step * 1.3:
				break
			mean = to.normalized()
		else:
			mean = _turn(mean, absf(_rng.randfn(0.0, 0.12)))
			mean.y -= sink
			if hold != INF:
				mean.y = clampf((hold - p.y) / 300.0, -0.25, 0.25)
			mean = mean.normalized()
		var s := step * _rng.randf_range(0.5, 1.5)
		p += _turn(mean, _kink(LEAD_KINK)) * s
		pts.append(p)
		run += s
	if target != Vector3.INF:
		pts.append(target)
	return pts


## Each segment halved until under 2 x `fine` m, its midpoint pushed aside
## so both halves turn off the chord by an exponential angle of mean KINK.
func _refine(pts: PackedVector3Array, fine: float) -> PackedVector3Array:
	var out := pts
	var longest := INF
	while longest > fine * 2.0:
		longest = 0.0
		var nx := PackedVector3Array()
		for i in out.size() - 1:
			var p: Vector3 = out[i]
			var q: Vector3 = out[i + 1]
			var l := p.distance_to(q)
			nx.append(p)
			if l > fine * 1.5:
				var m := (p + q) * 0.5 + _perp((q - p) / l) * (0.5 * l * tan(_kink(KINK)))
				nx.append(m)
				longest = maxf(longest, maxf(p.distance_to(m), m.distance_to(q)))
		nx.append(out[out.size() - 1])
		out = nx
	return out


func _kink(mean: float) -> float:
	return minf(-log(1.0 - _rng.randf() * 0.9999) * mean, KINK_MAX)


## A random unit vector at right angles to v.
func _perp(v: Vector3) -> Vector3:
	return v.cross(Vector3.UP if absf(v.y) < 0.9 else Vector3.RIGHT).normalized().rotated(v, _rng.randf() * TAU)


## v turned by `ang` (rad) about a random axis at right angles to it.
func _turn(v: Vector3, ang: float) -> Vector3:
	return v.rotated(_perp(v), ang)


## The channels as camera-facing ribbons, two vertices a point, joined at
## the kinks (NORMAL: the channel's mean direction there; UV: the side and the
## brightness; UV2.x: 1 a branch), and a glow at the strike `g` (UV2.y 1,
## UV its corner): one surface, one draw call.
func _bolt_mesh(paths: Array, g: Vector3) -> ArrayMesh:
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for ph: Dictionary in paths:
		var pts: PackedVector3Array = ph.p
		var b: PackedFloat32Array = ph.b
		var n := pts.size()
		for i in n:
			# The ribbon's sides follow the channel's direction over a few
			# segments: a ribbon many times wider than a segment would fan
			# out at every kink if it turned with each one.
			var t := (pts[mini(i + 4, n - 1)] - pts[maxi(i - 4, 0)]).normalized()
			for side in [-1.0, 1.0]:
				v.append(pts[i])
				nrm.append(t)
				uv.append(Vector2(side, b[i]))
				uv2.append(Vector2(ph.br, 0.0))
			if i > 0:
				var o := v.size() - 4
				idx.append_array([o, o + 1, o + 2, o + 2, o + 1, o + 3])
	if g != Vector3.INF:
		var o := v.size()
		for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			v.append(g + Vector3(0.0, 10.0, 0.0))
			nrm.append(Vector3.UP)
			uv.append(c)
			uv2.append(Vector2(0.0, 1.0))
		idx.append_array([o, o + 1, o + 2, o + 2, o + 1, o + 3])
	if OS.get_environment("LUCID_DEBUG") != "":
		print("storm: bolt %d channels, %d segments" % [paths.size(), idx.size() / 6])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_TEX_UV] = uv
	arr[Mesh.ARRAY_TEX_UV2] = uv2
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	mesh.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	return mesh
