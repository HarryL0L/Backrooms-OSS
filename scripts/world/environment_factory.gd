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


## Photoreal mode's grade: AgX tone mapping (a film-like response that keeps
## highlight colour instead of clipping it), neutral contrast and saturation,
## a gentler bloom. Off: the default stylised look.
static func photoreal_grade(e: Environment, on: bool) -> void:
	if on:
		e.tonemap_mode = Environment.TONE_MAPPER_AGX
		e.tonemap_white = 12.0
		e.adjustment_contrast = 1.04
		e.adjustment_saturation = 1.0
		e.glow_intensity = 0.32
		e.glow_hdr_threshold = 1.35
	else:
		e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		e.tonemap_white = 6.0
		e.adjustment_contrast = 1.06
		e.adjustment_saturation = 0.92
		e.glow_intensity = 0.55
		e.glow_hdr_threshold = 1.1


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
