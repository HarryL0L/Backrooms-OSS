shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform vec3 deep_color : source_color = vec3(0.30, 0.66, 0.66);
uniform float ceiling_y = 4.8;
// Planar reflection rendered by WaterReflection (mirrored camera), 0 = use the cheap fake.
uniform sampler2D reflection_tex : hint_default_black, filter_linear, repeat_disable;
uniform float reflection_on = 0.0;
// Interactive ripples (WaterRipples): r = height (m) on a grid that follows the player.
uniform sampler2D ripple_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec3 ripple_rect = vec3(0.0, 0.0, 16.0);   // grid min corner x, z and size (m)
uniform float ripple_on = 0.0;

varying vec3 v_light;
varying vec3 v_wpos;

void vertex() {
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = v_wpos.xz;
	vec3 n1 = texture(noise_normal, p * 0.21 + world_time * vec2(0.012, 0.008)).rgb;
	vec3 n2 = texture(noise_normal, p * 0.17 - world_time * vec2(0.009, 0.013)).rgb;
	vec3 nm = normalize((n1 + n2) - 1.0);
	// Ripple slope from the simulated height field.
	vec2 slope = vec2(0.0);
	if (ripple_on > 0.5) {
		vec2 ruv = (p - ripple_rect.xy) / ripple_rect.z;
		if (ruv.x > 0.0 && ruv.y > 0.0 && ruv.x < 1.0 && ruv.y < 1.0) {
			vec2 px = 1.0 / vec2(textureSize(ripple_tex, 0));
			float texel = ripple_rect.z * px.x;
			slope.x = texture(ripple_tex, ruv + vec2(px.x, 0.0)).r - texture(ripple_tex, ruv - vec2(px.x, 0.0)).r;
			slope.y = texture(ripple_tex, ruv + vec2(0.0, px.y)).r - texture(ripple_tex, ruv - vec2(0.0, px.y)).r;
			slope /= 2.0 * texel;
			nm = normalize(vec3(nm.xy - slope * 2.5, nm.z));
		}
	}
	NORMAL_MAP = nm * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 0.35;
	vec3 wn = normalize(vec3(nm.x * 0.012 - slope.x * 1.5, 1.0, nm.y * 0.012 - slope.y * 1.5));
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float fres = 0.02 + 0.98 * pow(1.0 - clamp(dot(wn, v), 0.0, 1.0), 5.0);
	vec3 refl = ceiling_reflection(v_wpos, CAMERA_POSITION_WORLD, wn, ceiling_y, 0, world_time);
	refl += v_light * vec3(0.85, 0.92, 0.95) * 0.6;
	if (reflection_on > 0.5) {
		// The reflection camera's image is mirrored horizontally (right-handed basis).
		vec2 ruv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + nm.xy * vec2(-0.025, 0.035) + slope * vec2(-0.22, 0.22);
		vec3 planar = texture(reflection_tex, clamp(ruv, vec2(0.001), vec2(0.999))).rgb * 1.25;
		refl = mix(refl, planar, 0.92);
		fres = max(fres, 0.12);
	}
	ALBEDO = deep_color;
	ALPHA = clamp(0.22 + fres * 0.75, 0.0, 0.97);
	ROUGHNESS = 0.03;
	SPECULAR = 0.7;
	EMISSION = deep_color * v_light * 0.45 * (1.0 - fres) + refl * min(fres * 1.5 + 0.06, 1.0) + deep_color * flashlight(v_wpos, wn, CAMERA_POSITION_WORLD, 0.95) + dither(FRAGCOORD.xy);
}
