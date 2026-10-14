shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tile_color : source_color = vec3(0.84, 0.83, 0.74);
uniform vec3 bar_color : source_color = vec3(0.60, 0.58, 0.52);

varying vec3 v_vlight;
varying vec3 v_lm;
varying vec3 v_wpos;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_vlight = baked_light(CUSTOM0, UV2.x, world_time);
	v_lm = vec3(CUSTOM1.xy, flicker(UV2.x, world_time));
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 v_light = lightmap_light(v_vlight, v_lm);
	vec2 uv = UV + vec2(0.0, 0.3);
	vec2 g = uv / 0.6;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * 0.6;
	float h = hash12(cell + 17.0);
	vec3 tile = tile_color * (0.92 + 0.12 * h);
	float sp = texture(noise_fine, uv * 5.0).r;
	tile *= 0.88 + 0.14 * smoothstep(0.3, 0.7, sp);
	// Fissured acoustic tile: small dark pits.
	float pits = texture(noise_fine, uv * 23.0 + h).r;
	tile *= 1.0 - smoothstep(0.66, 0.78, pits) * 0.35;
	// A few water-stained tiles.
	if (h > 0.82) {
		float st = texture(noise_blot, uv * 0.35 + h * 3.0).r;
		float s = smoothstep(0.42, 0.7, st);
		tile = mix(tile, tile * vec3(0.72, 0.6, 0.38), s * 0.85);
		tile = mix(tile, tile * vec3(0.55, 0.45, 0.28), smoothstep(0.02, 0.0, abs(st - 0.5)) * 0.6);
	}
	tile *= mix(0.82, 1.0, smoothstep(0.014, 0.05, edge));
	float aa = clamp((fwidth(g.x) + fwidth(g.y)) * 2.0, 0.0, 1.0);
	float bar = mix(smoothstep(0.016, 0.012, edge), 0.05, smoothstep(0.2, 0.7, aa));
	vec3 col = mix(tile, bar_color, bar);
	// Rare missing tile: a black void into the plenum above.
	if (h > 0.992) {
		col = vec3(0.015);
	}
	ALBEDO = col;
	ROUGHNESS = mix(0.95, 0.4, bar);
	METALLIC = bar * 0.6;
	EMISSION = col * v_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.05) + dither(FRAGCOORD.xy);
}
