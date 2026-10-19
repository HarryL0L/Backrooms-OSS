shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.47, 0.47, 0.45);
// 0 = wall (formwork panels), 1 = floor (joints, puddles), 2 = ceiling
uniform int kind = 0;
uniform float ceiling_y = 3.6;

varying vec3 v_vlight;
varying vec3 v_lm;
varying vec3 v_wpos;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_vlight = baked_light(CUSTOM0, UV2.x, world_time);
	v_lm = vec3(CUSTOM1.xy, flicker(UV2.x, world_time));
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	v_ps1_aff = vec3(UV * POSITION.w, POSITION.w);
}

// Brick pavers: 1 on a brick, 0 down in the mortar (running bond, as below).
float brick_height(vec2 uv) {
	vec2 b = uv / vec2(0.2, 0.1);
	b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
	vec2 bf = fract(b);
	float joint = min(min(bf.x, 1.0 - bf.x) * 0.2, min(bf.y, 1.0 - bf.y) * 0.1);
	return smoothstep(0.003, 0.011, joint);
}

void fragment() {
	vec3 v_light = lightmap_light(v_vlight, v_lm);
	vec2 uv = ps1_uv(UV);
	mat3 tbn = uv_frame(NORMAL, VERTEX, uv);
	vec3 bnorm = NORMAL;
	if (kind == 4 && photoreal > 0.5) {
		// Parallax: the pavers stand proud of sunken mortar joints.
		vec3 vt = normalize(vec3(dot(VIEW, tbn[0]), dot(VIEW, tbn[1]), dot(VIEW, NORMAL)));
		vec2 stp = -vt.xy / max(vt.z, 0.25) * 0.014 / 10.0;
		float layer = 0.0;
		for (int i = 0; i < 10; i++) {
			if (layer >= 1.0 - brick_height(uv)) {
				break;
			}
			uv += stp;
			layer += 0.1;
		}
		float e = 0.004;
		float hx = brick_height(uv + vec2(e, 0.0)) - brick_height(uv - vec2(e, 0.0));
		float hy = brick_height(uv + vec2(0.0, e)) - brick_height(uv - vec2(0.0, e));
		bnorm = normalize(tbn * vec3(-hx * 0.9, -hy * 0.9, 1.0));
	}
	float n1 = texture(noise_fine, uv * 1.3).r;
	float n2 = texture(noise_fine, uv * 7.0 + 0.3).r;
	float blot = texture(noise_blot, uv * 0.11).r;
	vec3 col = base_color * (0.8 + 0.3 * n1) * (0.92 + 0.12 * n2) * photo_detail(uv);
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
	} else if (kind == 3) {
		// Grimy service tunnel concrete with rust streaks and red scrawls.
		float y = -uv.y;
		col *= vec3(0.62, 0.58, 0.53);
		float streak = texture(noise_fine, vec2(uv.x * 2.7, y * 0.04)).r;
		col = mix(col, vec3(0.2, 0.12, 0.07), smoothstep(0.55, 0.85, streak) * 0.55);
		col *= mix(0.55, 1.0, smoothstep(0.0, 0.6, y));
		float scrawl_zone = smoothstep(0.62, 0.7, texture(noise_blot, uv * 0.05 + 3.1).r);
		float lines = smoothstep(0.03, 0.0, abs(texture(noise_fine, uv * vec2(1.4, 1.1)).r - 0.5)) * scrawl_zone;
		col = mix(col, vec3(0.35, 0.03, 0.02), lines * 0.8 * step(0.6, y) * step(y, 2.0));
		rough = 0.92;
	} else if (kind == 4) {
		// Worn brick pavers in a running bond.
		vec2 b = uv / vec2(0.2, 0.1);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 bf = fract(b);
		vec2 bi = floor(b);
		float joint = min(min(bf.x, 1.0 - bf.x) * 0.2, min(bf.y, 1.0 - bf.y) * 0.1);
		float hb = hash12(bi);
		vec3 brick = mix(vec3(0.36, 0.16, 0.1), vec3(0.24, 0.13, 0.1), hb) * (0.75 + 0.4 * n2);
		float baa = clamp((fwidth(b.x) + fwidth(b.y)) * 1.5, 0.0, 1.0);
		col = mix(mix(vec3(0.12, 0.11, 0.1), brick, smoothstep(0.004, 0.009, joint)), vec3(0.25, 0.13, 0.09) * 0.9, smoothstep(0.2, 0.7, baa));
		float wet = smoothstep(0.58, 0.7, blot);
		col *= mix(1.0, 0.6, wet);
		rough = mix(0.85, 0.2, wet);
	} else if (kind == 5) {
		// Car park floor: power-floated slab, painted bays and lanes, oil.
		// Rows of 4 cells (9.6 m): two cells of bays, two of lane.
		vec2 p = uv;
		float rz = mod(p.y, 9.6);
		float px = mod(p.x, 2.4);
		vec3 paint = vec3(0.86, 0.85, 0.78) * (0.75 + 0.25 * n1);
		float wear = step(0.3, n2);
		// Bay dividers, from the back of the bay to its front.
		float divider = step(min(px, 2.4 - px), 0.05) * step(0.25, rz) * step(rz, 4.75);
		// Lane centre: a dashed yellow line.
		float dash = step(abs(rz - 7.2), 0.06) * step(mod(p.x, 3.0), 1.6);
		// Arrows down the lane now and then.
		vec2 a = vec2(mod(p.x, 14.4) - 7.2, rz - 7.2 + 1.0);
		float shaft = step(abs(a.y), 0.08) * step(-1.0, a.x) * step(a.x, 0.4);
		float head = step(0.4, a.x) * step(a.x, 1.0) * step(abs(a.y), (1.0 - a.x) * 0.55);
		col = mix(col, paint, max(divider, max(shaft, head)) * wear * 0.85);
		col = mix(col, vec3(0.7, 0.58, 0.12) * (0.75 + 0.25 * n1), dash * wear * 0.85);
		// Oil where engines stood (middle of the bays).
		float oil = smoothstep(0.55, 0.75, texture(noise_blot, uv * 0.45 + 1.7).r) * step(1.2, rz) * step(rz, 3.8)
				* step(0.5, px) * step(px, 1.9);
		col = mix(col, col * 0.35, oil * 0.8);
		rough = mix(0.75, 0.2, oil);
	} else if (kind == 6) {
		// Car park column: concrete with a worn yellow-and-black band low down.
		float y = -uv.y;
		col *= 0.9;
		float band = step(0.1, y) * step(y, 1.05);
		float stripe = step(0.5, fract((uv.x + y) * 2.2));
		vec3 hz = mix(vec3(0.08, 0.08, 0.07), vec3(0.78, 0.62, 0.12), stripe) * (0.8 + 0.25 * n1);
		col = mix(col, hz, band * step(0.25, n2) * 0.9);
	} else {
		col *= 0.75;
		vec2 b = fract(uv / 2.4);
		col *= mix(0.75, 1.0, smoothstep(0.0, 0.02, min(b.x, 1.0 - b.x)));
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	vec3 nm = photo_nmap(uv, texture(noise_normal, uv * 0.9).rgb);
	float bump = 1.0;
	if (kind == 4 && photoreal > 0.5) {
		NORMAL = bnorm;
		bump = baked_bump(v_lm, bnorm, tbn[2], VIEW_MATRIX);
	} else {
		NORMAL_MAP = nm;
		NORMAL_MAP_DEPTH = 0.6;
		bump = baked_bump(v_lm, nmap_normal(nm, 1.0, tbn), NORMAL, VIEW_MATRIX);
	}
	EMISSION = col * v_light * bump + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 1.0 - rough) + extra + dither(FRAGCOORD.xy);
}
