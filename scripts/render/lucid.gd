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
	# Stage 3, the city at night. A bare 60 W bulb in a caged "jelly jar"
	# wall fitting over a service door (800 lm, ~75 % through the globe).
	"jelly_jar_60w": {"flux": 600.0, "kelvin": 2800.0, "m": 0.0, "size": Vector2(0.1, 0.1)},
	# Lit windows seen from outside (luminance of the glazed area): an
	# office floor (~500 lux inside, walls and ceiling at 40-80 cd/m2, tinted
	# glass T ~0.3-0.5), a home (warm lamps, curtains), a closed shop's night
	# lighting (displays and security lights, ~40 cd/m2 behind the glass).
	"window_office": {"luminance": 25.0, "kelvin": 4000.0, "m": 1.0, "size": Vector2(1.5, 2.7)},
	"window_home": {"luminance": 12.0, "kelvin": 2900.0, "m": 1.0, "size": Vector2(1.2, 1.5)},
	"shopfront": {"luminance": 40.0, "kelvin": 3500.0, "m": 1.0, "size": Vector2(4.0, 3.0)},
	# Traffic signals, 300 mm LED, on-axis minimum maintained intensity
	# (ITE VTCSH: red 365 cd, yellow 910, green 475) and their chromaticity
	# boxes' centres. Pedestrian heads: the hand 3750 cd/m2, the walking
	# person 2200 cd/m2 (ITE PTCSI).
	"signal_red": {"peak_cd": 365.0, "xy": Vector2(0.692, 0.307), "m": 0.0, "size": Vector2(0.3, 0.3)},
	"signal_yellow": {"peak_cd": 910.0, "xy": Vector2(0.575, 0.423), "m": 0.0, "size": Vector2(0.3, 0.3)},
	"signal_green": {"peak_cd": 475.0, "xy": Vector2(0.170, 0.530), "m": 0.0, "size": Vector2(0.3, 0.3)},
	"ped_hand": {"luminance": 3750.0, "xy": Vector2(0.600, 0.390), "m": 1.0, "size": Vector2(0.15, 0.2)},
	"ped_walk": {"luminance": 2200.0, "kelvin": 6500.0, "m": 1.0, "size": Vector2(0.12, 0.2)},
	# Aircraft warning lights on tall buildings (ICAO Annex 14): medium
	# intensity type B, red, flashing 20-60 per minute, 2000 cd; low
	# intensity type B, red, steady, 32 cd.
	"aviation_red_flash": {"peak_cd": 2000.0, "xy": Vector2(0.70, 0.30), "m": 0.0, "size": Vector2(0.3, 0.3)},
	"aviation_red_steady": {"peak_cd": 32.0, "xy": Vector2(0.70, 0.30), "m": 0.0, "size": Vector2(0.15, 0.15)},
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


## The RGB of a fixture preset's light (its Kelvin and duv, or the
## chromaticity "xy" of a coloured signal), luminance 1.
static func fixture_rgb(fx: Dictionary) -> Color:
	if fx.has("xy"):
		var c := xy_to_rgb(fx.xy)
		var y := lum(c)
		return Color(c.r / y, c.g / y, c.b / y)
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

	## How much of the eye's night shift (mesopic Purkinje shift, see
	## Lucid.mesopic) the picture shows: 0 for footage (a sensor has no
	## rods), up to 1 for what a dark-adapted eye sees. Read by the city
	## shaders through `lucid_sky.y`.
	var night_vision := 0.0

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


## A phone's main camera filming a city at night (stage 3) in its night
## video mode: f/1.8, ISO up to 12800, and four 1/30 s frames merged per
## output frame (what current phones' low-light video does), so an
## effective exposure of up to 1/8 s: EV100 bottoms out at -2.3 (the
## sensor saturates at 0.24 cd/m2). A lit street (0.3-1.5 cd/m2) meters
## well above that and is exposed normally; a roof under the sky and the
## moon (0.01-0.05 cd/m2) is beyond the camera and stays dark, as a night
## should. Like phones in low light, it aims lower than by day (-0.5 EV
## instead of +0.8: a night should look like night, and the lamp pools
## must not burn out) and keeps the brightest spot within 2.5 stops. Auto
## white balance as stage 1.
static func night_camera() -> Camera:
	var c := Camera.new()
	c.aperture = 1.8
	c.iso_max = 12800.0
	c.shutter_max = 1.0 / 8.0
	c.compensation = -0.5
	c.headroom = 2.5
	return c


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


## A real light node's [energy, sRGB colour] for an engine-unit light
## colour `c` under a given camera (for places that run their own camera,
## like the city levels, without making it Lucid.active).
static func light_node_cam(c: Color, cam: Camera) -> Array:
	var e := cam.shader_exposure() if cam != null else Color(1, 1, 1)
	var lin := Color(c.r * e.r, c.g * e.g, c.b * e.b)
	var m := maxf(lin.r, maxf(lin.g, lin.b))
	if m <= 0.0:
		return [0.0, Color.WHITE]
	return [m, Color(lin.r / m, lin.g / m, lin.b / m).linear_to_srgb()]


# ------------------------------------------------- stage 3: sky and night ---

## Sky brightness in mag/arcsec2 to luminance (cd/m2): L = 10.8e4 x
## 10^(-0.4 m) (the conversion used by sky quality meters and Falchi 2016).
static func mag_arcsec2_nits(m: float) -> float:
	return 10.8e4 * pow(10.0, -0.4 * m)


## The natural moonless night sky at the zenith: 22.0 mag/arcsec2, 174
## ucd/m2 (Falchi et al. 2016). A big city's own light, scattered back
## down by the air, makes its zenith 100-200 times brighter.
const SKY_NATURAL_NITS := 0.000174
## Mean luminance of the full moon's disc (cd/m2) and its solid angle
## (0.52 deg across): 0.25 lux = 3900 x 6.4e-5 sr.
const MOON_DISC_SR := 6.4e-5

## Natural light states for baked city levels: the sky (zenith and horizon
## luminance in cd/m2 with their colour temperatures, `h0` the elevation
## scale in radians over which the horizon glow fades into the zenith
## value, plus a directional glow toward `glow_az` for twilight), the moon
## or sun as a directional light (lux on a surface facing it, Kelvin,
## altitude and azimuth in degrees: azimuth from north (-Z) through east
## (+X)), how many windows are lit, the street lamps' level and the haze
## (extinction coefficient of the air, 1/m: 3.912 / visual range).
## Sources and reasoning: docs/LUCID.md (stage 3).
const STATES := {
	# A clear night under a megacity's light dome, the moon up. The zenith
	# at 16.1 mag/arcsec2 (0.04 cd/m2, ~230x natural, the class of the most
	# light-polluted city centres measured: LED and sodium light scattered
	# by molecules, so the zenith is blue: ~11000 K like a moonlit Rayleigh
	# sky); the horizon glow 6x that and warmer (more aerosol in the long
	# path, more sodium from the low streets). Moon nearly full,
	# 20 deg up in the west-south-west: 0.18 lux after extinction. Visual
	# range 12 km.
	"night": {"zenith": 0.04, "zenith_k": 11000.0, "horizon": 0.24, "horizon_k": 4300.0, "h0": 0.22,
		"glow": 0.0, "glow_k": 3000.0, "glow_az": 270.0, "moon_lux": 0.18, "moon_k": 4100.0,
		"moon_alt": 20.0, "moon_az": 255.0, "windows": 0.3, "lamps": 1.0, "haze": 3.3e-4, "stars": 1.0},
	# The blue hour: the sun 5 deg below the horizon in the west. Zenith
	# about 1 cd/m2 and very blue (the ozone Chappuis band), the western
	# horizon a few cd/m2 and orange; about 5 lux on the ground from the sky
	# alone (civil twilight ends at ~3.4 lux). Street lamps already on (photocells switch at 35-70 lux),
	# fewer windows lit. No direct sun.
	"dusk": {"zenith": 1.1, "zenith_k": 15000.0, "horizon": 3.0, "horizon_k": 7000.0, "h0": 0.35,
		"glow": 5.0, "glow_k": 2600.0, "glow_az": 280.0, "moon_lux": 0.0, "moon_k": 4100.0,
		"moon_alt": 20.0, "moon_az": 255.0, "windows": 0.2, "lamps": 1.0, "haze": 1.8e-4, "stars": 0.0},
}


## Unit vector toward a body at `alt_deg` above the horizon, azimuth
## `az_deg` from north (-Z) through east (+X).
static func sky_dir(alt_deg: float, az_deg: float) -> Vector3:
	var a := deg_to_rad(alt_deg)
	var z := deg_to_rad(az_deg)
	return Vector3(sin(z) * cos(a), sin(a), -cos(z) * cos(a))


## Sky luminance (linear RGB whose luminance is cd/m2) of `state` looking
## along `dir` (unit, world space): the zenith value, plus the horizon
## excess fading with elevation as exp(-h / h0), plus the twilight glow
## toward glow_az (cos^4 in azimuth, same fade). Below the horizon: the
## horizon value. The city shaders evaluate the same model
## (lucid_city.gdshaderinc, lucid_sky_nits) from sky_uniforms().
static func sky_nits(state: Dictionary, dir: Vector3) -> Color:
	var u := sky_uniforms(state)
	var h := asin(clampf(dir.y, -1.0, 1.0))
	var t := exp(-maxf(h, 0.0) / float(state.h0))
	var c: Color = u.zenith + (u.horizon - u.zenith) * t
	var g: Vector3 = u.glow_dir
	var flat := Vector2(dir.x, dir.z)
	if flat.length() > 1e-4 and float(state.glow) > 0.0:
		var ca := maxf(flat.normalized().dot(Vector2(g.x, g.z)), 0.0)
		c += (u.glow as Color) * (ca * ca * ca * ca * t)
	return c


## The sky model's uniforms for a state: zenith, horizon and glow radiance
## (Color, luminance in cd/m2), the glow direction, h0, the moon.
static func sky_uniforms(state: Dictionary) -> Dictionary:
	var zk := kelvin_rgb(state.zenith_k, true)
	var hk := kelvin_rgb(state.horizon_k, state.horizon_k >= 4000.0)
	var gk := kelvin_rgb(state.glow_k)
	return {"zenith": zk * float(state.zenith), "horizon": hk * float(state.horizon),
		"glow": gk * float(state.glow), "glow_dir": sky_dir(0.0, state.glow_az), "h0": float(state.h0),
		"moon_dir": sky_dir(state.moon_alt, state.moon_az),
		"moon": kelvin_rgb(state.moon_k) * (float(state.moon_lux) / MOON_DISC_SR)}


## Illuminance (lux, RGB) the whole open sky of `state` gives a surface
## facing `n` (numerical integral of sky_nits x cos).
static func sky_illuminance(state: Dictionary, n: Vector3, steps := 24) -> Color:
	var e := Color(0, 0, 0)
	for i in steps:
		var el := (float(i) + 0.5) / steps * PI * 0.5
		for j in steps * 2:
			var az := (float(j) + 0.5) / (steps * 2) * TAU
			var d := Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))
			var c := maxf(n.dot(d), 0.0)
			if c <= 0.0:
				continue
			var dw := cos(el) * (PI * 0.5 / steps) * (TAU / (steps * 2))
			e += sky_nits(state, d) * (c * dw)
	return e


## The eye's night shift (Purkinje): between 5 and 0.005 cd/m2 (the CIE
## 191:2010 mesopic range) vision hands over from cones to rods, which see
## blue-green better and red not at all, and lose colour. 0 = photopic,
## 1 = scotopic; log-linear between.
static func mesopic(nits: float) -> float:
	return clampf((0.69897 - log(maxf(nits, 1e-6)) / log(10.0)) / 3.0, 0.0, 1.0)


## Rod (scotopic) luminance of a linear RGB colour relative to its
## photopic luminance, normalised so that D65 white is 1: Y (1.33 (1 + (Y
## + Z) / X) - 1.68) / 2.576 (Jensen et al. 2000, "A physically-based
## night sky model"). The scotopic picture is that luminance in the blue
## grey of chromaticity (0.25, 0.25) (Thompson, Shirley & Ferwerda 2002).
static func scotopic(c: Color) -> float:
	var x := 0.4124 * c.r + 0.3576 * c.g + 0.1805 * c.b
	var y := 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
	var z := 0.0193 * c.r + 0.1192 * c.g + 0.9505 * c.b
	if x <= 1e-9:
		return 0.0
	return maxf(y * (1.33 * (1.0 + (y + z) / x) - 1.68) / 2.576, 0.0)


const SCOTOPIC_RGB := Color(0.706, 0.990, 1.966)


## A colour (cd/m2 RGB) as an eye adapted to it sees it, `amount` of the
## way to full night vision (Camera.night_vision).
static func night_shift(c: Color, amount: float) -> Color:
	var s := amount * mesopic(lum(c))
	if s <= 0.0:
		return c
	var v := scotopic(c)
	return c.lerp(SCOTOPIC_RGB * v, s)


## Pushes a level's own camera to the world shaders (lucid_exposure) and
## the night globals (`lucid_sky`: x state blend, y night vision, z lamp
## level, w haze; `lucid_air`: rgb the air's horizon luminance in engine
## units, a the extinction coefficient) without making it Lucid.active (the
## game turns the Backrooms' camera off while you are away).
static func push_level(cam: Camera, blend: float, lamps: float, air: Color, haze: float) -> void:
	var e := cam.shader_exposure()
	RenderingServer.global_shader_parameter_set("lucid_exposure", Vector4(e.r, e.g, e.b, 1.0))
	RenderingServer.global_shader_parameter_set("lucid_sky", Vector4(blend, cam.night_vision, lamps, haze))
	RenderingServer.global_shader_parameter_set("lucid_air", Vector4(air.r / UNIT_NITS, air.g / UNIT_NITS,
			air.b / UNIT_NITS, haze))


## Puts the globals push_level() set back to "off".
static func clear_level() -> void:
	RenderingServer.global_shader_parameter_set("lucid_exposure", Vector4(1, 1, 1, 0))
	RenderingServer.global_shader_parameter_set("lucid_sky", Vector4(0, 0, 1, 0))
	RenderingServer.global_shader_parameter_set("lucid_air", Vector4(0, 0, 0, 0))
	for i in 4:
		RenderingServer.global_shader_parameter_set("lucid_glow%d" % i, Vector4.ZERO)
