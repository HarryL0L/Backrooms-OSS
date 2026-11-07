class_name Lucid
extends RefCounted
## L.U.C.I.D. (Light-Unit Calibrated Indirect & Direct lighting): real light
## units, real fixtures, a real camera. Lights emit their measured luminous
## flux, the bake computes illuminance from it (lux), surfaces reflect it by
## their measured albedo, and a camera model (EV100, white balance in Kelvin)
## turns the resulting luminance into the image, so the right picture falls
## out of correct maths instead of per-place fudge factors. See docs/LUCID.md.
##
## Engine units: the bake, the vertex light and the emissive panels store
## luminance divided by UNIT_NITS, the luminance a camera at EV100 =
## STORE_EV100 maps to 1.0. Baked light on a surface is stored as E / pi
## (the luminance a perfectly white Lambertian surface would have under
## illuminance E); the shaders multiply it by their albedo. The camera's
## own exposure is then applied in the world shaders as a multiplier
## relative to STORE_EV100 (the global shader parameter `lucid_exposure`),
## so the frame buffer always holds display-range values (the Mobile
## renderer's buffer has little headroom) whatever the scene's real level.

## Storage exposure: a typical lit interior. 1 engine unit = UNIT_NITS cd/m2.
const STORE_EV100 := 7.0
## Luminance (cd/m2) that a camera exposed at STORE_EV100 maps to 1.0:
## L_max = 78 / (S q) * N^2 / t = 1.2 * 2^EV100 (ISO 2720 saturation-based
## sensitivity, lens transmittance q = 0.65; Lagarde & de Rousiers 2014).
const UNIT_NITS := 153.6
## Reflected-light meter calibration constant (ISO 2720, K = 12.5 cd s/m2).
const METER_K := 12.5

## Light distributions: peak intensity I0 (cd, straight down or along the
## beam) from flux, for I(theta) = I0 cos^m(theta).
enum { DIST_LAMBERT, DIST_ISOTROPIC, DIST_COSINE_POWER, DIST_BEAM }

## Real fixtures. flux: lumens leaving the fixture (lamp lumens x ballast
## factor x fixture efficiency); kelvin: correlated colour temperature;
## m: exponent of the cos^m intensity distribution (1 = Lambertian lensed
## troffer, 0 = bare bulb in all directions); size: emitting area (m);
## beam: half angle of the hot spot (degrees). Sources in docs/LUCID.md.
const FIXTURES := {
	# 2 x 4 ft recessed lensed troffer, 3 x F32T8 (2850 lm each), electronic
	# ballast BF 0.88, 80 % fixture efficiency: 3 x 2850 x 0.88 x 0.80.
	# Triphosphor fluorescent sits a little above the black-body line
	# (duv ~ +0.003: the faint green of office light in photos).
	"troffer_t8_3lamp": {"flux": 6020.0, "kelvin": 4100.0, "duv": 0.003, "m": 1.0, "size": Vector2(1.22, 0.61)},
	# 2 x 4 ft LED troffer / flat panel (typical catalogue 4000 lm, 4000 K).
	"troffer_led_2x4": {"flux": 4000.0, "kelvin": 4000.0, "m": 1.0, "size": Vector2(1.22, 0.61)},
	# 2 x 2 ft LED panel (typical 3300 lm, 5000 K).
	"panel_led_2x2": {"flux": 3300.0, "kelvin": 5000.0, "m": 1.0, "size": Vector2(0.61, 0.61)},
	# 2 x 4 ft troffer, 2 x F40T12 warm white with aged, darkened lamps.
	"troffer_t12_dim": {"flux": 1500.0, "kelvin": 3000.0, "duv": 0.004, "m": 1.0, "size": Vector2(1.22, 0.61)},
	# Linear high bay, 6 x F54T5HO (5000 lm each), BF 1.0, 85 % efficient.
	"highbay_t5ho_6lamp": {"flux": 25500.0, "kelvin": 3500.0, "m": 1.6, "size": Vector2(1.2, 0.35)},
	# 4 ft industrial strip, 2 x F32T8 5000 K, BF 0.88, 90 % efficient.
	"strip_t8_2lamp": {"flux": 4500.0, "kelvin": 5000.0, "duv": 0.003, "m": 1.0, "size": Vector2(1.22, 0.1)},
	# Bare 60 W / 100 W incandescent A19 bulbs.
	"incandescent_60w": {"flux": 800.0, "kelvin": 2800.0, "m": 0.0, "size": Vector2(0.06, 0.06)},
	"incandescent_100w": {"flux": 1600.0, "kelvin": 2850.0, "m": 0.0, "size": Vector2(0.06, 0.06)},
	# Car park / street: 150 W high pressure sodium (16000 lm lamp, 75 %
	# luminaire efficiency); 100 W LED street lamp (130 lm/W).
	"sodium_hps_150w": {"flux": 12000.0, "kelvin": 2100.0, "m": 1.2, "size": Vector2(0.4, 0.25)},
	"led_street_100w": {"flux": 13000.0, "kelvin": 4000.0, "m": 1.2, "size": Vector2(0.5, 0.25)},
	# Handheld LED flashlight: 200 lm, 2000 cd peak (10 cd/lm, a cheap
	# reflector), hot spot half angle 10 degrees, spill to 30.
	"flashlight": {"flux": 200.0, "kelvin": 6000.0, "m": 0.0, "peak_cd": 2000.0, "beam": 10.0, "spill": 30.0},
	# A ceiling opening onto bright sky (diffuse daylight, ~3000 cd/m2 seen
	# through it), 1.8 m square.
	"skylight": {"luminance": 3000.0, "kelvin": 5500.0, "m": 1.0, "size": Vector2(1.8, 1.8)},
}

## Natural light, illuminance on a surface facing it (lux) and colour.
const SUN_LUX := 100000.0          # direct beam, clear day, high sun
const SUN_KELVIN := 5500.0
const SKY_CLEAR_LUX := 15000.0     # diffuse skylight, clear day (horizontal)
const SKY_CLEAR_KELVIN := 10000.0
const SKY_OVERCAST_LUX := 2000.0   # dull overcast midday (1000 - 25000)
const SKY_OVERCAST_KELVIN := 6500.0
const MOON_LUX := 0.25             # full moon, clear night
const MOON_KELVIN := 4100.0
## Typical maintained illuminance targets (lux), for validation.
const TARGET_OFFICE := 500.0        # EN 12464-1 offices (300 - 500 common)
const TARGET_CORRIDOR := 100.0      # EN 12464-1 circulation areas
const TARGET_CAR_PARK := 75.0       # EN 12464-1 parking traffic lanes
const TARGET_STREET := 15.0         # residential street, average

## Measured-plausible diffuse albedo (linear, mean over the surface, CIE Y
## in parentheses in the comments). Sources in docs/LUCID.md.
const ALBEDO := {
	"wallpaper_yellow_aged": Color(0.58, 0.49, 0.14),     # (0.47) aged mid-yellow paper, LRV ~45-55
	"carpet_tan_damp": Color(0.14, 0.095, 0.04),          # (0.10) tan loop pile, dirty and damp: LRV ~8-15
	"ceiling_tile_aged": Color(0.76, 0.74, 0.65),         # (0.74) mineral fibre LR 0.82-0.85 new, yellowed
	"trim_offwhite": Color(0.62, 0.59, 0.48),             # (0.59) painted off-white skirting
	"concrete": Color(0.35, 0.35, 0.33),                  # (0.35) weathered grey concrete
	"pool_tile_white": Color(0.75, 0.80, 0.82),           # (0.79) glazed white tile
	"diffuser_acrylic": Color(0.45, 0.45, 0.45),          # prismatic lens seen unlit (reflects ~half)
}


# ------------------------------------------------------------- photometry ---

## Peak intensity (cd) of a fixture preset: the I0 of I = I0 cos^m(theta),
## whose integral over the lower hemisphere is the flux: I0 = flux (m + 1) / 2 pi.
static func peak_intensity(fx: Dictionary) -> float:
	if fx.has("peak_cd"):
		return fx.peak_cd
	if fx.has("luminance"):
		var s: Vector2 = fx.size
		return fx.luminance * s.x * s.y
	var m: float = fx.m
	if m <= 0.0:
		return fx.flux / (4.0 * PI)       # bare bulb: the whole sphere
	return fx.flux * (m + 1.0) / TAU


## Flux (lm) of a preset (luminance-defined ones: pi L A, Lambertian).
static func flux(fx: Dictionary) -> float:
	if fx.has("flux"):
		return fx.flux
	var s: Vector2 = fx.size
	return PI * fx.luminance * s.x * s.y


## Mean luminance (cd/m2) of a fixture's emitting face seen from below.
static func face_luminance(fx: Dictionary) -> float:
	if fx.has("luminance"):
		return fx.luminance
	var s: Vector2 = fx.size
	return peak_intensity(fx) / (s.x * s.y)


## Illuminance (lux) at distance d from a source of peak intensity i0 with
## a cos^m distribution: E = I0 cos^m(theta_e) cos(theta_r) / d^2.
static func illuminance(i0: float, m: float, cos_emit: float, cos_recv: float, d: float) -> float:
	if cos_recv <= 0.0 or (m > 0.0 and cos_emit <= 0.0):
		return 0.0
	return i0 * (pow(cos_emit, m) if m > 0.0 else 1.0) * cos_recv / maxf(d * d, 1e-4)


## Luminance of a Lambertian surface (cd/m2): L = albedo E / pi.
static func luminance(albedo: float, lux: float) -> float:
	return albedo * lux / PI


## Engine units of a luminance (cd/m2), and of the "white surface" luminance
## E / pi that the bake stores for illuminance E (lux).
static func nits_to_engine(nits: float) -> float:
	return nits / UNIT_NITS


static func lux_to_engine(lux: float) -> float:
	return lux / (PI * UNIT_NITS)


static func engine_to_lux(v: float) -> float:
	return v * PI * UNIT_NITS


# ------------------------------------------------------------------ colour ---

## CIE 1931 xy of a black body at `kelvin` (Kim et al. 2002 cubic spline of
## the Planckian locus, 1667 - 25000 K, error < 1e-3).
static func planck_xy(kelvin: float) -> Vector2:
	var t := clampf(kelvin, 1667.0, 25000.0)
	var t2 := t * t
	var t3 := t2 * t
	var x: float
	if t < 4000.0:
		x = -0.2661239e9 / t3 - 0.2343589e6 / t2 + 0.8776956e3 / t + 0.179910
	else:
		x = -3.0258469e9 / t3 + 2.1070379e6 / t2 + 0.2226347e3 / t + 0.240390
	var y: float
	if t < 2222.0:
		y = -1.1063814 * x * x * x - 1.34811020 * x * x + 2.18555832 * x - 0.20219683
	elif t < 4000.0:
		y = -0.9549476 * x * x * x - 1.37418593 * x * x + 2.09137015 * x - 0.16748867
	else:
		y = 3.0817580 * x * x * x - 5.87338670 * x * x + 3.75112997 * x - 0.37001483
	return Vector2(x, y)


## CIE xy of daylight (the D illuminant series) at `kelvin`, 4000 - 25000 K.
static func daylight_xy(kelvin: float) -> Vector2:
	var t := clampf(kelvin, 4000.0, 25000.0)
	var x: float
	if t <= 7000.0:
		x = 0.244063 + 0.09911e3 / t + 2.9678e6 / (t * t) - 4.6070e9 / (t * t * t)
	else:
		x = 0.237040 + 0.24748e3 / t + 1.9018e6 / (t * t) - 2.0064e9 / (t * t * t)
	return Vector2(x, -3.0 * x * x + 2.87 * x - 0.275)


## Linear sRGB (Rec. 709 primaries, D65 white) of chromaticity xy at
## luminance Y = 1. Out-of-gamut channels are clipped at 0.
static func xy_to_rgb(xy: Vector2) -> Color:
	var X := xy.x / xy.y
	var Z := (1.0 - xy.x - xy.y) / xy.y
	var r := 3.2404542 * X - 1.5371385 - 0.4985314 * Z
	var g := -0.9692660 * X + 1.8760108 + 0.0415560 * Z
	var b := 0.0556434 * X - 0.2040259 + 1.0572252 * Z
	return Color(maxf(r, 0.0), maxf(g, 0.0), maxf(b, 0.0))


## Linear RGB of a light at colour temperature `kelvin`, luminance 1 (so a
## light's colour and its photometric strength stay separate). Lamps follow
## the Planckian locus; daylight=true uses the daylight locus. `duv`: the
## distance above (+, greenish) or below (-, pinkish) the black-body line
## in CIE 1960 uv, as lamp data sheets give it.
static func kelvin_rgb(kelvin: float, daylight := false, duv := 0.0) -> Color:
	var xy := daylight_xy(kelvin) if daylight and kelvin >= 4000.0 else planck_xy(kelvin)
	if duv != 0.0:
		var uv := _xy_to_uv(xy)
		var t := _xy_to_uv(planck_xy(kelvin * 1.01)) - _xy_to_uv(planck_xy(kelvin * 0.99))
		var nrm := Vector2(-t.y, t.x).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		uv += nrm * duv
		var d := 2.0 * uv.x - 8.0 * uv.y + 4.0
		xy = Vector2(3.0 * uv.x / d, 2.0 * uv.y / d)
	return xy_to_rgb(xy)


static func _xy_to_uv(xy: Vector2) -> Vector2:
	var d := -2.0 * xy.x + 12.0 * xy.y + 3.0
	return Vector2(4.0 * xy.x / d, 6.0 * xy.y / d)


## The RGB of a fixture preset's light (its Kelvin and duv), luminance 1.
static func fixture_rgb(fx: Dictionary) -> Color:
	return kelvin_rgb(fx.kelvin, false, fx.get("duv", 0.0))


## Camera white balance gains for a camera set to `kelvin`: a grey card lit
## by light of that temperature comes out neutral (diagonal von Kries
## scaling in linear RGB, what a camera's raw processing does). Luminance
## of that card is kept.
static func wb_gains(kelvin: float) -> Color:
	var w := kelvin_rgb(kelvin)
	return Color(1.0 / maxf(w.r, 1e-3), 1.0 / maxf(w.g, 1e-3), 1.0 / maxf(w.b, 1e-3))


static func mired(kelvin: float) -> float:
	return 1.0e6 / kelvin


static func lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b


## Engine colour of a light: its temperature's RGB (luminance 1) times its
## peak intensity as E / pi at 1 m, in engine units. The bake multiplies by
## cos^m(theta_e) cos(theta_r) / d^2.
static func light_engine(fx: Dictionary, scale := 1.0) -> Color:
	return fixture_rgb(fx) * (lux_to_engine(peak_intensity(fx)) * scale)


## The emitting face of a fixture as an engine-unit emission colour.
static func face_engine(fx: Dictionary, scale := 1.0) -> Color:
	return fixture_rgb(fx) * (nits_to_engine(face_luminance(fx)) * scale)


# ------------------------------------------------------------------ camera ---

## A physical camera: exposure as EV100 from aperture, shutter and ISO, a
## phone-like program auto exposure (metering, limits, slow adaptation) and
## white balance in Kelvin (auto white balance that, like a phone's, only
## corrects part of a warm light's cast).
class Camera:
	extends RefCounted
	## Fixed aperture (f-number), like a phone or body camera.
	var aperture := 2.0
	## Shutter limits (s): video at 30 fps cannot expose longer than 1/30.
	var shutter_min := 1.0 / 8000.0
	var shutter_max := 1.0 / 30.0
	## ISO limits: above iso_max it just stays underexposed (dim places stay
	## dark instead of being brightened into noise).
	var iso_min := 50.0
	var iso_max := 1600.0
	## Exposure compensation (stops), what the camera's metering aims for.
	var compensation := 0.0
	## Highlight protection (stops): the brightest metered spot is kept at
	## most this far over the metered average's exposure, like a phone's
	## matrix metering not letting a lit face or a torch spot burn out.
	var headroom := 3.0
	## How fast exposure follows the meter (stops per second at most, eased).
	var adapt_rate := 1.6
	## Auto white balance: the share (in mired) of a light's shift away from
	## the camera's neutral that it corrects. Phones keep some of the warmth
	## of indoor light.
	var awb_strength := 0.5
	var awb_neutral := 5500.0
	var awb_min := 2800.0
	var awb_max := 7500.0

	var ev100 := STORE_EV100
	var shutter := 1.0 / 60.0
	var iso := 100.0
	var wb_kelvin := 5500.0
	var _first := true

	## EV100 of explicit settings: log2(N^2 / t) - log2(S / 100).
	static func ev_of(n: float, t: float, s: float) -> float:
		return log(n * n / t) / log(2.0) - log(s / 100.0) / log(2.0)

	func ev_min() -> float:
		return ev_of(aperture, shutter_max, iso_max)

	func ev_max() -> float:
		return ev_of(aperture, shutter_min, iso_min)

	## The EV100 a reflected-light meter picks for a scene of average
	## luminance `nits`: N^2/t = L S / K.
	static func metered_ev(nits: float) -> float:
		return log(maxf(nits, 1e-4) * 100.0 / METER_K) / log(2.0)

	## Feeds the meter (average scene luminance, cd/m2, and optionally its
	## brightest spot) and eases the exposure towards it within the
	## camera's limits.
	func meter(nits: float, delta: float, peak := -1.0) -> void:
		var want := metered_ev(nits) - compensation
		if peak > 0.0:
			want = maxf(want, metered_ev(peak) - compensation - headroom)
		var target := clampf(want, ev_min(), ev_max())
		if _first:
			ev100 = target
		else:
			var k := 1.0 - exp(-2.5 * delta)
			ev100 += clampf((target - ev100) * k, -adapt_rate * delta, adapt_rate * delta)
		_program()

	## Program mode: the lowest ISO, the shutter as long as allowed, then ISO.
	func _program() -> void:
		var n2 := aperture * aperture
		iso = iso_min
		shutter = clampf(n2 / pow(2.0, ev100 + log(iso / 100.0) / log(2.0)), shutter_min, shutter_max)
		iso = clampf(100.0 * n2 / (shutter * pow(2.0, ev100)), iso_min, iso_max)

	## Auto white balance towards a scene lit at `scene_kelvin`.
	func balance(scene_kelvin: float, delta: float) -> void:
		var mn := Lucid.mired(awb_neutral)
		var target := clampf(1.0e6 / (mn + (Lucid.mired(scene_kelvin) - mn) * awb_strength), awb_min, awb_max)
		if _first:
			wb_kelvin = target
		else:
			var m := Lucid.mired(wb_kelvin)
			m += (Lucid.mired(target) - m) * (1.0 - exp(-1.5 * delta))
			wb_kelvin = 1.0e6 / m

	func settle() -> void:
		_first = false

	## Scene-luminance multiplier: L (cd/m2) x exposure() = value fed to
	## the tone mapper (1.0 = the sensor's saturation, Lagarde 2014).
	func exposure() -> float:
		return 1.0 / (1.2 * pow(2.0, ev100))

	## The multiplier the world shaders apply to engine units (which are
	## stored for STORE_EV100), with the white balance gains.
	func shader_exposure() -> Color:
		var k := pow(2.0, STORE_EV100 - ev100)
		var g := Lucid.wb_gains(wb_kelvin)
		return Color(g.r * k, g.g * k, g.b * k, 1.0)


## The camera exposing the Backrooms right now (null: Lucid is off, or the
## player is in a place lit the old way). Real lights read it to scale
## their energy like the baked light (see Player, FixtureLights).
static var active: Camera = null


## Sets the world shaders' exposure (and white balance) multiplier and the
## shader flashlight's intensity; null: Lucid off (multiplier 1, the legacy
## look).
static func push(cam: Camera) -> void:
	active = cam
	var e := cam.shader_exposure() if cam != null else Color(1, 1, 1, 0)
	RenderingServer.global_shader_parameter_set("lucid_exposure", Vector4(e.r, e.g, e.b, e.a))
	var f := light_engine(FIXTURES.flashlight)
	RenderingServer.global_shader_parameter_set("lucid_flash", Vector4(f.r, f.g, f.b, 0.0))


## A real light node's energy and colour for an engine-unit light colour
## `c` (E / pi at 1 m, Lucid.light_engine) under the active camera: Godot
## lights (non-physical units, inverse square with attenuation 2) give
## albedo x energy x colour x cos / d^2. Returns [energy, sRGB colour].
static func light_node(c: Color) -> Array:
	var e := active.shader_exposure() if active != null else Color(1, 1, 1)
	var lin := Color(c.r * e.r, c.g * e.g, c.b * e.b)
	var m := maxf(lin.r, maxf(lin.g, lin.b))
	if m <= 0.0:
		return [0.0, Color.WHITE]
	return [m, Color(lin.r / m, lin.g / m, lin.b / m).linear_to_srgb()]
