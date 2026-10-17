shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.80, 0.79, 0.50);
uniform vec3 stripe_color : source_color = vec3(0.62, 0.68, 0.64);

varying vec3 v_vlight;
varying vec3 v_lm;
varying vec3 v_wpos;

// "The Lining": a figure pressed out through the wallpaper (LiningEntity).
// pos.xyz = base centre on the wall surface, pos.w = how far it pushes (0 = off).
global uniform vec4 lining_pos;
global uniform vec4 lining_right;
global uniform vec4 lining_normal;
global uniform sampler2D lining_tex;   // r = face height (m), g = cavity, b = hands height (m)
const vec2 LINING_SIZE = vec2(1.4, 2.7);

// Face plus hands (lining_right.w = how far the hands are showing).
float lining_h(vec2 t) {
	vec4 m = texture(lining_tex, t);
	return m.r + m.b * lining_right.w;
}

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_vlight = baked_light(CUSTOM0, UV2.x, world_time);
	v_lm = vec3(CUSTOM1.xy, flicker(UV2.x, world_time));
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	v_ps1_aff = vec3(UV * POSITION.w, POSITION.w);
}

void fragment() {
	vec3 v_light = lightmap_light(v_vlight, v_lm);
	vec2 uv = ps1_uv(UV);
	float lin_k = 1.0;     // shading of The Lining's bulge (also applied to the flashlight)
	if (lining_pos.w > 0.001) {
		vec3 rel = v_wpos - lining_pos.xyz;
		vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec2 q = vec2(dot(rel, lining_right.xyz), rel.y);
		vec2 tuv = vec2(q.x / LINING_SIZE.x + 0.5, 1.0 - q.y / LINING_SIZE.y);
		if (abs(dot(rel, lining_normal.xyz)) < 0.03 && dot(wn, lining_normal.xyz) > 0.9
				&& tuv.x > 0.0 && tuv.x < 1.0 && tuv.y > 0.0 && tuv.y < 1.0) {
			// Slow breathing: the paper swells and settles.
			float s = lining_pos.w * (0.78 + 0.22 * sin(world_time * 1.25));
			vec2 px = 1.0 / vec2(textureSize(lining_tex, 0));
			vec4 hm = texture(lining_tex, tuv);
			hm.r = lining_h(tuv);
			float hx = (lining_h(tuv + vec2(px.x, 0.0)) - lining_h(tuv - vec2(px.x, 0.0)))
					/ (2.0 * px.x * LINING_SIZE.x) * s;
			float hy = (lining_h(tuv - vec2(0.0, px.y)) - lining_h(tuv + vec2(0.0, px.y)))
					/ (2.0 * px.y * LINING_SIZE.y) * s;
			vec3 up = vec3(0.0, 1.0, 0.0);
			vec3 nb = normalize(lining_normal.xyz - hx * lining_right.xyz - hy * up);
			// Shade the bulge as the room light (from above, in front) would.
			vec3 L = normalize(lining_normal.xyz * 0.55 + up * 0.85);
			float flat_l = 0.45 + 0.55 * max(dot(lining_normal.xyz, L), 0.0);
			lin_k = (0.45 + 0.55 * max(dot(nb, L), 0.0)) / flat_l * (1.0 - hm.g * s);
			v_light *= lin_k;
			// The paper's pattern stretches over the shape.
			uv += vec2(hx, -hy) * hm.r * s * 0.6;
			NORMAL = normalize((VIEW_MATRIX * vec4(nb, 0.0)).xyz);
		}
	}
	float y = -uv.y;
	// Columns of stacked chevrons separated by thin double pinstripes,
	// the classic yellow-halls wallpaper.
	const float COL_W = 0.21;
	float cu = fract(uv.x / COL_W);
	float aa = clamp(fwidth(uv.x / COL_W) * 3.0, 0.0, 1.0);
	float chev_v = fract(y / 0.16 + abs(cu - 0.5) * 1.1);
	float chev = smoothstep(0.0, 0.05, chev_v) * smoothstep(0.24, 0.17, chev_v) * 0.75;
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
	EMISSION = col * v_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.15) * mix(1.0, lin_k, 0.75) + dither(FRAGCOORD.xy);
}
