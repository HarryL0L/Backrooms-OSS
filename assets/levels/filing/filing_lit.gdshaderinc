// The Stacks' surfaces: the side levels' shader (shaders/level_lit.gdshaderinc,
// copied here unchanged but for the light) with light that follows the
// moving shelving. The kit (the room) keeps its bake; the shelving, which
// moves, is lit analytically from the same strip rows and the aisle light
// bars. Regenerate from the framework's include if it changes (SPEC.md).
//
//  - The rows: each row of 4 ft strips is a Lambertian line source along x
//    (intensity per metre, engine units); a surface's irradiance is the
//    exact integral over the part of the row it can see. In a slot between
//    two shelving faces (xl, xr) under the top of storage (stack_h) only the
//    part of the row seen through the slot's top or its open end counts.
//  - The aisle bars: an LED bar under each carriage's canopy edge on each
//    face, a line source along z aimed down into the aisle.
//  - Bounce: a share of the open floor's light, times how open the slot is.
//  - lmode 0 (the baked room): the bake (made without the shelving) times
//    the ratio of the slot's light to the open room's, so the floor of an
//    open aisle darkens as it would, plus the bars. lmode 1: all analytic.
//  - vcol: albedo times the vertex colour (the shelving's colours with its
//    ambient occlusion baked in); alpha < 0.5 marks an aisle bar's diffuser.
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
// (`lightmap`, the colour lightmap, comes from common.gdshaderinc)

uniform vec3 albedo : source_color = vec3(0.6);
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_normal = false;
uniform float normal_depth = 1.0;
uniform int uv_mode = 0;              // 0 mesh UV * uv_scale, 1 world projection (uv_scale m per repeat)
uniform vec2 uv_scale = vec2(1.0);
uniform float roughness = 0.7;
uniform float metallic = 0.0;
uniform float specular = 0.4;
uniform float emit = 0.0;             // self-lit (a lamp's diffuser), times its group's light
uniform int emit_group = -1;          // the light group the lamp belongs to (-1: always on)
uniform bool has_lightmap = false;
uniform vec3 const_light = vec3(0.5);
// Without a lightmap: faces shaded a little by which way they face (floors
// fullest, walls less, ceilings least), so flat-lit boxes still read as
// solid. 0 = perfectly even.
uniform float flat_shade = 0.0;
uniform float lm_scale = 4.0;
uniform sampler2D group_map : hint_default_black, filter_linear, repeat_disable;
uniform bool has_group_map = false;
uniform float group_scale = 4.0;
uniform vec4 group_mix = vec4(0.0);
uniform float alpha_cut = 0.5;
global uniform vec4 level_light_0;
global uniform vec4 level_light_1;
global uniform vec4 level_light_2;
global uniform vec4 level_light_3;

varying vec3 v_wpos;
varying vec3 v_wn;

vec3 group_light(int g) {
	vec4 l = g == 0 ? level_light_0 : (g == 1 ? level_light_1 : (g == 2 ? level_light_2 : level_light_3));
	return l.rgb * l.a;
}

// ------------------------------------------------------------- The Stacks ---
uniform vec3 origin = vec3(0.0, -8000.0, 0.0);
uniform int lmode = 0;
uniform bool vcol = false;
uniform float car_x[24];
uniform float bar_on[24];
uniform float fix_bar[4];
uniform vec4 bank0 = vec4(0.471, 11.141, -7.518, -1.067);
uniform vec4 bank1 = vec4(0.471, 11.141, -15.798, -9.347);
uniform float car_half = 0.4065;
uniform float stack_h = 2.30;
uniform vec4 rows_a[8];
uniform vec4 rows_b[8];
uniform int row_count = 0;
uniform vec3 night_rgb = vec3(1.0);
uniform vec3 bar_rgb = vec3(0.5);
uniform vec3 bar_emit = vec3(50.0);
uniform float bounce = 0.3;
instance uniform float inst_bar = 0.0;
instance uniform float inst_shake = 0.0;

float f2(float s, float r) {
	float r2 = r * r;
	return s / (2.0 * r2 * (s * s + r2)) + atan(s / r) / (2.0 * r2 * r);
}

float g1(float a, float b, float r) {
	return 0.5 * (1.0 / (a * a + r * r) - 1.0 / (b * b + r * r));
}

// Integral over s in [a, b] of max(ns * s, 0) / (s^2 + r^2)^2.
float side_int(float a, float b, float ns, float r) {
	if (ns > 0.0) {
		float lo = max(a, 0.0);
		return lo < b ? ns * g1(lo, b, r) : 0.0;
	}
	float hi = min(b, 0.0);
	return a < hi ? ns * g1(a, hi, r) : 0.0;
}

vec4 bank_of(int b) {
	return b == 0 ? bank0 : bank1;
}

// The slot a point of bank b is in (after stepping off its own face):
// returns (xl, xr, bar on the left face, bar on the right face).
vec4 find_gap(int b, float px) {
	vec4 bk = bank_of(b);
	float x = clamp(px, bk.x, bk.y);
	for (int i = 0; i < 12; i++) {
		float c = car_x[b * 12 + i];
		if (abs(x - c) < car_half) {
			x = x >= c ? c + car_half : c - car_half;
		}
	}
	vec4 g = vec4(bk.x, bk.y, fix_bar[b * 2], fix_bar[b * 2 + 1]);
	for (int i = 0; i < 12; i++) {
		float c = car_x[b * 12 + i];
		float rf = c + car_half;
		float lf = c - car_half;
		if (rf <= x + 0.002 && rf > g.x) {
			g.x = rf;
			g.z = bar_on[b * 12 + i];
		}
		if (lf >= x - 0.002 && lf < g.y) {
			g.y = lf;
			g.w = bar_on[b * 12 + i];
		}
	}
	return g;
}

// The strip rows' light at p (normal n), seen through the slot (xl, xr) of
// a bank spanning z0..z1 if `slot`; `open_e` gets the rows' unoccluded light
// on a horizontal surface there (luminance), for the bounce.
vec3 rows_light(vec3 p, vec3 n, bool slot, vec2 sx, vec2 sz, out float open_e) {
	vec3 sum = vec3(0.0);
	open_e = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= row_count) {
			break;
		}
		vec4 ra = rows_a[i];
		vec4 rb = rows_b[i];
		float dy = ra.y - p.y;
		if (dy < 0.02) {
			continue;
		}
		float dz = ra.x - p.z;
		float r = sqrt(dy * dy + dz * dz);
		float oa = ra.z - p.x;
		float ob = ra.w - p.x;
		float sa = oa;
		float sb = ob;
		if (slot && p.y < stack_h) {
			float te = (stack_h - p.y) / dy;
			if (dz > 0.0) {
				te = min(te, (sz.y - p.z) / dz);
			} else if (dz < 0.0) {
				te = min(te, (sz.x - p.z) / dz);
			}
			te = max(te, 0.002);
			sa = max(sa, (sx.x - p.x) / te);
			sb = min(sb, (sx.y - p.x) / te);
		}
		vec3 c = rb.y < -0.5 ? night_rgb : group_light(int(rb.y));
		float e = 0.0;
		if (sb > sa) {
			float nyz = n.y * dy + n.z * dz;
			e = dy * (max(nyz, 0.0) * (f2(sb, r) - f2(sa, r)) + side_int(sa, sb, n.x, r));
		}
		sum += rb.x * e * c;
		open_e += rb.x * dy * dy * (f2(ob, r) - f2(oa, r)) * dot(c, vec3(0.3, 0.59, 0.11));
	}
	return sum;
}

// One aisle bar (along z, x = bx, aimed toward sgn x and down) at p.
float bar_light(vec3 p, vec3 n, float bx, float sgn, vec2 sz) {
	vec2 v = vec2(bx - p.x, stack_h - 0.05 - p.y);
	if (v.y < 0.005) {
		return 0.0;
	}
	vec2 ne = normalize(vec2(sgn, -1.0));
	float ce = max(-dot(ne, v), 0.0);
	float r = length(v);
	float sa = sz.x - p.z;
	float sb = sz.y - p.z;
	float np = n.x * v.x + n.y * v.y;
	return ce * (max(np, 0.0) * (f2(sb, r) - f2(sa, r)) + side_int(sa, sb, n.z, r));
}

// How open a slot is above / at its ends (0 shut, 1 open room).
float slot_open(vec3 p, vec2 sx, vec2 sz) {
	float w = max(sx.y - sx.x, 0.0);
	float d = max(stack_h - p.y, 0.0);
	float f = w / (w + 1.1 * d + 0.001);
	float dend = min(p.z - sz.x, sz.y - p.z);
	return max(f, exp(-max(dend, 0.0) / (0.25 + w)) * step(0.01, w));
}

// The light at p (local) with normal n: the shelving's (analytic), or the
// bake's correction (lmode 0). Returns light to add (rgb) and, in `ratio`,
// what to multiply the bake by.
vec3 stacks_light(vec3 p, vec3 n, out float ratio) {
	ratio = 1.0;
	vec3 add = vec3(0.0);
	vec3 q = p + n * 0.03;
	bool any_slot = false;
	vec2 gx = vec2(-1000.0, 1000.0);
	vec2 gz = vec2(0.0);
	for (int b = 0; b < 2; b++) {
		vec4 bk = bank_of(b);
		float out_z = max(bk.z - q.z, q.z - bk.w);
		if (out_z > 3.5) {
			continue;
		}
		vec4 g = find_gap(b, q.x);
		vec2 sz = bk.zw;
		float mask = 1.0;
		if (out_z > 0.0) {
			// out in an aisle: the bars' light only comes out of the open slot's end
			mask = smoothstep(-0.1, 0.25, min(q.x - (g.x - out_z * 0.7), (g.y + out_z * 0.7) - q.x));
			mask *= step(0.05, g.y - g.x);
		} else if (q.y < stack_h) {
			any_slot = true;
			gx = g.xy;
			gz = sz;
		}
		if (mask > 0.0 && g.y - g.x > 0.02) {
			float e = g.z * bar_light(q, n, g.x + 0.035, 1.0, sz) + g.w * bar_light(q, n, g.y - 0.035, -1.0, sz);
			add += bar_rgb * e * mask;
		}
	}
	float open_e;
	vec3 direct = rows_light(q, n, any_slot, gx, gz, open_e);
	float f = any_slot ? slot_open(q, gx, gz) : 1.0;
	vec3 amb = vec3(bounce * open_e * f * (0.55 + 0.45 * max(n.y, 0.0)));
	if (lmode == 0) {
		if (any_slot) {
			float o2;
			vec3 open_direct = rows_light(q, n, false, gx, gz, o2);
			float num = dot(direct, vec3(0.3, 0.59, 0.11)) + amb.r;
			float den = dot(open_direct, vec3(0.3, 0.59, 0.11)) + bounce * open_e * (0.55 + 0.45 * max(n.y, 0.0));
			ratio = (num + 0.0005) / (den + 0.0005);
		}
		return add;
	}
	return direct + amb + add;
}

void vertex() {
	if (inst_shake > 0.0) {
		float h = UV2.x * 61.0;
		VERTEX += vec3(sin(TIME * 31.0 + h) * 0.006, abs(sin(TIME * 23.0 + h * 1.7)) * 0.004, sin(TIME * 17.0 + h * 0.6) * 0.003) * inst_shake;
	}
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 wn = normalize(v_wn);
	vec2 uv;
	if (uv_mode == 1) {
		vec2 pp = abs(wn.y) > 0.6 ? v_wpos.xz : (abs(wn.x) > abs(wn.z) ? v_wpos.zy : v_wpos.xy);
		uv = pp / max(uv_scale, vec2(0.001));
	} else {
		uv = UV * uv_scale;
	}
	if (ps1_grid.x > 0.0) {
		// Chunky texels, like the rest of PS1 mode (an eighth of the texture's).
		vec2 ts = max(vec2(textureSize(albedo_tex, 0)) * 0.125, vec2(4.0));
		uv = (floor(uv * ts) + 0.5) / ts;
	}
	vec4 tex = texture(albedo_tex, uv);
	vec3 col = albedo * tex.rgb;
	bool bar = false;
	if (vcol) {
		col *= COLOR.rgb;
		bar = COLOR.a < 0.5;
	}
	float rough = clamp(roughness * texture(rough_tex, uv).g, 0.02, 1.0);
	vec3 n_view = NORMAL;
	if (use_normal) {
		n_view = nmap_normal(texture(normal_tex, uv).rgb, normal_depth, uv_frame(NORMAL, VERTEX, uv));
		NORMAL = n_view;
	}
	vec3 light = const_light * mix(1.0, 0.72 + 0.28 * (wn.y * 0.5 + 0.5) - 0.08 * abs(wn.x), flat_shade);
	if (has_lightmap) {
		vec3 lm = texture(lightmap, UV2).rgb;
		light = lm * lm * lm_scale;
	}
	vec4 g = group_mix;
	if (has_group_map) {
		vec4 gm = texture(group_map, UV2);
		g = gm * gm * group_scale;
	}
	light += g.r * group_light(0) + g.g * group_light(1) + g.b * group_light(2) + g.a * group_light(3);
	float ratio;
	vec3 sl = stacks_light(v_wpos - origin, wn, ratio);
	if (lmode == 1) {
		light = sl;
	} else {
		light = light * ratio + sl;
	}
	// Potato: the darkest places lifted a little (see dark_lift).
	float lum = dot(light, vec3(0.3, 0.59, 0.11));
	light += vec3(1.0, 0.95, 0.84) * dark_lift * (1.0 - smoothstep(0.0, 0.45, lum));
	vec3 lamp = emit_group >= 0 ? group_light(emit_group) : vec3(1.0);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic;
	SPECULAR = specular;
	EMISSION = col * light + col * emit * lamp + col * flashlight(v_wpos, n_world, CAMERA_POSITION_WORLD, 1.0 - rough)
			+ (bar ? bar_emit * inst_bar : vec3(0.0)) + dither(FRAGCOORD.xy);
#ifdef CUTOUT
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
#endif
}
