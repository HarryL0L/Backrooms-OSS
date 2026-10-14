class_name EnvironmentFactory
extends RefCounted
## Builds the shared Environment. Ambient light is black on purpose: all
## surface lighting is baked into vertices and emitted, real lights (the
## flashlight) are added on top.

const FOG := [Color(0.42, 0.36, 0.20), Color(0.70, 0.80, 0.84), Color(0.10, 0.105, 0.11), Color(0.012, 0.010, 0.006)]
const FOG_DENSITY := [0.030, 0.022, 0.034, 0.05]


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
