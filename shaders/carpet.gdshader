shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.50, 0.46, 0.28);

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
	vec2 uv = UV;
	float n1 = texture(noise_fine, uv * 2.1).r;
	float n2 = texture(noise_fine, uv * 11.3 + 0.37).r;
	float loops = texture(noise_fine, uv * 37.0 + 0.71).r;
	float blot = texture(noise_blot, uv * 0.085).r;
	vec3 col = base_color * (0.86 + 0.24 * n1) * (0.84 + 0.22 * n2) * (0.85 + 0.25 * loops);
	// Damp, musty patches: darker, browner and slightly glossy.
	float damp = smoothstep(0.62, 0.8, blot);
	col = mix(col, col * vec3(0.66, 0.6, 0.46), damp * 0.6);
	float worn = smoothstep(0.35, 0.2, texture(noise_blot, uv * 0.21 + 0.5).r);
	col = mix(col, col * vec3(1.08, 1.04, 0.95), worn * 0.4);
	ALBEDO = col;
	ROUGHNESS = mix(0.98, 0.55, damp);
	SPECULAR = mix(0.2, 0.45, damp);
	NORMAL_MAP = texture(noise_normal, uv * 3.0).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	EMISSION = col * v_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.1) + dither(FRAGCOORD.xy);
}
