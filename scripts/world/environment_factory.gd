class_name EnvironmentFactory
extends RefCounted
## Builds the shared Environment. Ambient light is black on purpose: all
## surface lighting is baked into vertices and emitted, real lights (the
## flashlight) are added on top.

const FOG := [Color(0.42, 0.42, 0.26), Color(0.80, 0.86, 0.84), Color(0.17, 0.15, 0.11), Color(0.012, 0.010, 0.006), Color(0.03, 0.025, 0.02), Color(0.05, 0.055, 0.06)]
const FOG_DENSITY := [0.026, 0.018, 0.05, 0.05, 0.06, 0.04]
const FOG_ENERGY := [0.45, 0.55, 0.4, 0.4, 0.4, 0.4]
const VOL_DENSITY := [0.012, 0.008, 0.035, 0.02, 0.035, 0.02]


## Forward+ only effects. Ambient light stays black (baked lighting is emitted),
## so SSIL picks up the bounce from those emissive surfaces.
static func apply_ultra(e: Environment, ssr: bool, ssao: bool, ssil: bool, vol: bool) -> void:
	e.ssr_enabled = ssr
	e.ssr_max_steps = 56
	e.ssr_fade_in = 0.1
	e.ssr_fade_out = 2.0
	e.ssr_depth_tolerance = 0.25
	e.ssao_enabled = ssao
	e.ssao_radius = 1.1
	e.ssao_intensity = 1.8
	e.ssao_power = 1.6
	e.ssao_light_affect = 0.4
	e.ssil_enabled = ssil
	e.ssil_radius = 3.5
	e.ssil_intensity = 0.9
	e.volumetric_fog_enabled = vol
	e.volumetric_fog_density = VOL_DENSITY[0]
	e.volumetric_fog_albedo = FOG[0]
	e.volumetric_fog_anisotropy = 0.55
	e.volumetric_fog_length = 48.0
	e.volumetric_fog_detail_spread = 2.0
	e.volumetric_fog_ambient_inject = 0.0


## Realistic without L.U.C.I.D. (lightmaps off; Lucid's camera replaces all
## of this otherwise): what the camera does with each place's light, per biome
## (Yellow Halls, Tiled Baths, Grey Floors, Unlit Halls, Pipeworks, Car
## Park). White balance: a cheap camera lets the Lobby's yellow walls pull
## everything warm (even the ceiling tiles look cream), while big, dim or
## night spaces come out cool and blue-teal. Black: where the darkest tones
## land (a little above black is the muddy, low-range look of a compact
## camera; zero crushes the shadows like a phone at night). Exposure: no
## auto-brightening in the dark, the dim places stay underexposed.
const REAL_WHITE := [Color(1.0, 0.96, 0.84), Color(0.90, 0.97, 1.0), Color(0.94, 0.97, 1.0),
		Color(0.82, 0.93, 1.0), Color(1.0, 0.96, 0.88), Color(0.84, 0.95, 1.0)]
const REAL_BLACK := [Color(0.035, 0.03, 0.018), Color(0.0, 0.006, 0.01), Color(0.008, 0.009, 0.01),
		Color(0.0, 0.004, 0.008), Color(0.01, 0.008, 0.006), Color(0.0, 0.005, 0.008)]
const REAL_EXPOSURE := [1.3, 0.85, 0.85, 0.8, 0.9, 0.72]
## The same for the night spaces outside the Backrooms (the Dead Mall, the
## side levels): cool and underexposed, like the phone photo of an empty
## mall at night.
const NIGHT_WHITE := Color(0.78, 0.91, 1.0)
const NIGHT_BLACK := Color(0.0, 0.004, 0.008)

static var _luts := {}


## The camera's tone curve and white balance as a colour correction ramp
## (applied per channel after tone mapping: a lookup per pixel in the tone
## mapping pass the image goes through anyway). Cached.
static func camera_lut(white: Color, black: Color) -> Texture2D:
	var key := str(white) + str(black)
	if _luts.has(key):
		return _luts[key]
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.1, 0.5, 1.0])
	# A toe: the bottom tenth sinks towards `black` (shadows go muddy or
	# crush), then the balance tints everything towards `white`.
	g.colors = PackedColorArray([black, black.lerp(white * 0.06, 0.5), white * 0.5, white])
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	t.use_hdr = true        # float texels: 8-bit ones band visibly in the shadows
	_luts[key] = t
	return t


## Veiling glare as a colour correction ramp: `flare` (linear light) added
## to every pixel's linear value (the ramp is looked up in display space,
## so it is built through the sRGB curve). Cached.
static func flare_lut(flare: Color) -> Texture2D:
	var key := "flare" + str(flare)
	if _luts.has(key):
		return _luts[key]
	var g := Gradient.new()
	var offs := PackedFloat32Array()
	var cols := PackedColorArray()
	for k in 17:
		var x := float(k) / 16.0
		var lin := Color(x, x, x).srgb_to_linear()
		offs.push_back(x)
		cols.push_back(Color(minf(lin.r + flare.r, 1.0), minf(lin.g + flare.g, 1.0), minf(lin.b + flare.b, 1.0)).linear_to_srgb())
	g.offsets = offs
	g.colors = cols
	var t := GradientTexture1D.new()
	t.gradient = g
	t.width = 256
	t.use_hdr = true
	_luts[key] = t
	return t


## The Realistic preset's grade, like a phone or compact camera's own
## processing: AgX tone mapping (bright tubes clip to white like a real
## sensor instead of to a flat colour), slightly muted colour and a tight,
## faint bloom (a real lens only blooms right around a tube). The bloom also
## skips its widest blur levels, two passes fewer. Off: the default stylised
## look. `biome`: whose camera balance and exposure (see REAL_WHITE).
static func realistic_grade(e: Environment, on: bool, biome := 0) -> void:
	if on and ChunkBuilder.lucid:
		lucid_grade(e)
	elif on:
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
		e.tonemap_white = 8.0
		e.adjustment_contrast = 1.0
		e.adjustment_saturation = 0.85
		e.adjustment_color_correction = camera_lut(REAL_WHITE[biome], REAL_BLACK[biome])
		e.glow_intensity = 0.2
		e.glow_bloom = 0.0
		e.glow_hdr_threshold = 1.6
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
		e.set_glow_level(1, 1.0)
		e.set_glow_level(2, 0.4)
		e.set_glow_level(3, 0.0)
		e.set_glow_level(4, 0.0)
	else:
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		e.tonemap_white = 6.0
		e.adjustment_contrast = 1.06
		e.adjustment_saturation = 0.92
		e.adjustment_color_correction = null
		e.glow_intensity = 0.55
		e.glow_bloom = 0.03
		e.glow_hdr_threshold = 1.1
		e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
		e.set_glow_level(1, 1.0)
		e.set_glow_level(2, 0.8)
		e.set_glow_level(3, 0.6)
		e.set_glow_level(4, 0.3)


## L.U.C.I.D. (Realistic): the camera's image pipeline once exposure and
## white balance are done (in the world shaders, see Lucid). AgX maps the
## exposed scene values (1.0 = sensor saturation, so a lit troffer at ~15
## clips to white and mid grey sits at ~0.18) with its standard white
## point. Saturation x1.15 is a phone's "standard" picture profile (camera
## JPEG engines boost colour over the sensor's colorimetric rendering,
## which AgX gives); there is no tint, the colour cast comes from the
## lights' and the camera's Kelvin.
## The only post grade is veiling glare: a lens scatters a small share of
## the image's light over the whole frame, lifting black a little towards
## the scene's own colour (LUCID_FLARE of the mean, here the yellow walls).
## The bloom is a lens's tight glow around what clips (threshold 1.0, the
## sensor's saturation), without the two widest blur levels.
const LUCID_FLARE := 0.03

static func lucid_grade(e: Environment) -> void:
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_agx_white = 16.29
	e.tonemap_agx_contrast = 1.25
	e.adjustment_contrast = 1.0
	e.adjustment_saturation = 1.15
	var wall: Color = Lucid.ALBEDO.wallpaper_yellow_aged
	e.adjustment_color_correction = flare_lut(wall * (LUCID_FLARE / Lucid.lum(wall) * 0.1))
	e.glow_intensity = 0.25
	e.glow_bloom = 0.0
	e.glow_hdr_threshold = 1.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 0.4)
	e.set_glow_level(3, 0.0)
	e.set_glow_level(4, 0.0)


## The same camera for the other levels' own environments: call it last on
## a finished Environment. `night` (the Dead Mall, side levels): the cool,
## underexposed balance, exposure times `exposure`. Without it (the Field's
## daylight) only the tone mapping, colour and bloom change.
static func realistic_level(e: Environment, night := true, exposure := 0.7) -> void:
	if not Settings.is_realistic():
		return
	e.tonemap_mode = Environment.TONE_MAPPER_AGX
	e.tonemap_white = 8.0
	e.adjustment_enabled = true
	e.adjustment_contrast = minf(e.adjustment_contrast, 1.03)
	e.adjustment_saturation *= 0.92
	e.glow_intensity *= 0.8
	e.glow_bloom = 0.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	for i in 7:
		e.set_glow_level(i, [0.0, 1.0, 0.4, 0.0, 0.0, 0.0, 0.0][i])
	if night:
		e.adjustment_color_correction = camera_lut(NIGHT_WHITE, NIGHT_BLACK)
		e.tonemap_exposure *= exposure


static func make() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color.BLACK
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK
	e.ambient_light_energy = 0.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	e.tonemap_exposure = 1.0
	e.tonemap_white = 6.0
	e.glow_enabled = true
	e.glow_intensity = 0.55
	e.glow_strength = 1.0
	e.glow_bloom = 0.03
	e.glow_hdr_threshold = 1.1
	e.glow_hdr_scale = 2.0
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.set_glow_level(0, 0.0)
	e.set_glow_level(1, 1.0)
	e.set_glow_level(2, 0.8)
	e.set_glow_level(3, 0.6)
	e.set_glow_level(4, 0.3)
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = FOG[0]
	e.fog_light_energy = 0.4
	e.fog_density = FOG_DENSITY[0]
	e.fog_sky_affect = 0.0
	e.adjustment_enabled = true
	e.adjustment_brightness = 1.0
	e.adjustment_contrast = 1.06
	e.adjustment_saturation = 0.92
	return e
