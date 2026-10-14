shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.80, 0.79, 0.50);
uniform vec3 stripe_color : source_color = vec3(0.62, 0.68, 0.64);

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
	float y = -uv.y;
	// Columns of stacked chevrons separated by thin double pinstripes,
	// the classic Level 0 wallpaper.
	const float COL_W = 0.21;
	float cu = fract(uv.x / COL_W);
	float aa = clamp(fwidth(uv.x / COL_W) * 3.0, 0.0, 1.0);
	float chev_v = fract(y / 0.16 + abs(cu - 0.5) * 1.1);
	float chev = smoothstep(0.0, 0.05, chev_v) * smoothstep(0.24, 0.17, chev_v);
	chev *= smoothstep(0.08, 0.14, cu) * smoothstep(0.92, 0.86, cu);
	float pin = smoothstep(0.012, 0.0, abs(cu - 0.015)) + smoothstep(0.012, 0.0, abs(cu - 0.045));
	float pattern = mix(clamp(chev * 0.8 + pin * 0.7, 0.0, 1.0), 0.18, smoothstep(0.15, 0.6, aa));
	vec3 col = mix(base_color, stripe_color, pattern);
	float n = texture(noise_fine, uv * 1.7).r;
	col *= 0.92 + 0.14 * n;
	// Paper strips with faint seams.
	float strip = fract(uv.x / (COL_W * 3.0));
	col *= mix(0.86, 1.0, smoothstep(0.0, 0.004, strip) * smoothstep(1.0, 0.996, strip));
	// Water damage, worse near the floor.
	float blot = texture(noise_blot, uv * vec2(0.12, 0.09)).r;
	float low = smoothstep(1.3, 0.0, y);
	float stain = smoothstep(0.6, 0.78, blot) * (low * 0.8 + 0.15);
	col = mix(col, col * vec3(0.68, 0.62, 0.42), stain * 0.7);
	float tide = smoothstep(0.02, 0.0, abs(blot - 0.62)) * low;
	col = mix(col, col * vec3(0.55, 0.48, 0.3), tide * 0.45);
	col *= mix(0.82, 1.0, smoothstep(0.0, 0.15, y));
	ALBEDO = col;
	ROUGHNESS = 0.8;
	SPECULAR = 0.3;
	NORMAL_MAP = texture(noise_normal, uv * 1.3).rgb;
	NORMAL_MAP_DEPTH = 0.3;
	EMISSION = col * v_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.15) + dither(FRAGCOORD.xy);
}
