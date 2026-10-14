shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.47, 0.47, 0.45);
// 0 = wall (formwork panels), 1 = floor (joints, puddles), 2 = ceiling
uniform int kind = 0;
uniform float ceiling_y = 3.6;

varying vec3 v_light;
varying vec3 v_wpos;

void vertex() {
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float n1 = texture(noise_fine, uv * 1.3).r;
	float n2 = texture(noise_fine, uv * 7.0 + 0.3).r;
	float blot = texture(noise_blot, uv * 0.11).r;
	vec3 col = base_color * (0.8 + 0.3 * n1) * (0.92 + 0.12 * n2);
	col = mix(col, col * vec3(0.8, 0.78, 0.74), smoothstep(0.45, 0.75, blot) * 0.6);
	float rough = 0.88;
	vec3 extra = vec3(0.0);
	if (kind == 0) {
		float y = -uv.y;
		vec2 panel = vec2(uv.x / 1.2, y / 0.6);
		vec2 pf = fract(panel);
		float line = min(min(pf.x, 1.0 - pf.x) * 1.2, min(pf.y, 1.0 - pf.y) * 0.6);
		col *= mix(0.8, 1.0, smoothstep(0.0, 0.008, line));
		vec2 tie = (fract(panel + 0.5) - 0.5) * vec2(1.2, 0.6);
		col *= mix(0.35, 1.0, smoothstep(0.012, 0.02, length(tie)));
		float streak = texture(noise_fine, vec2(uv.x * 1.9, y * 0.05)).r;
		col *= 1.0 - smoothstep(0.58, 0.8, streak) * 0.25;
		col *= mix(0.7, 1.0, smoothstep(0.0, 0.4, y));
	} else if (kind == 1) {
		vec2 j = fract(uv / 4.8);
		float joint = min(min(j.x, 1.0 - j.x), min(j.y, 1.0 - j.y)) * 4.8;
		col *= mix(0.55, 1.0, smoothstep(0.004, 0.01, joint));
		// Painted guide line.
		float stripe = abs(fract(uv.x / 7.2) - 0.5) * 7.2;
		col = mix(col, vec3(0.62, 0.53, 0.16) * (0.7 + 0.3 * n1), step(stripe, 0.06) * step(0.35, n2) * 0.8);
		float puddle = smoothstep(0.6, 0.66, texture(noise_blot, uv * 0.07 + 0.2).r);
		col = mix(col, col * 0.45, puddle);
		rough = mix(0.8, 0.04, puddle);
		float fres = 0.05 + 0.6 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		extra = ceiling_reflection(v_wpos, CAMERA_POSITION_WORLD, vec3(0.0, 1.0, 0.0), ceiling_y, 1, world_time) * fres * puddle;
		extra += v_light * 0.12 * puddle * fres;
	} else {
		col *= 0.75;
		vec2 b = fract(uv / 2.4);
		col *= mix(0.75, 1.0, smoothstep(0.0, 0.02, min(b.x, 1.0 - b.x)));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	NORMAL_MAP = texture(noise_normal, uv * 0.9).rgb;
	NORMAL_MAP_DEPTH = 0.6;
	EMISSION = col * v_light + extra + dither(FRAGCOORD.xy);
}
