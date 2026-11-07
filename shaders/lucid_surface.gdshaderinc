// L.U.C.I.D. stage 3: a baked city surface (streets, roofs, stairs, the
// walls you can walk up to): lucid_city.gdshader, and with WINDOWS
// defined lucid_facade.gdshader, the same with lit windows. The light was baked per vertex by LucidCity
// (tools/lucid/city_bake.gd), in engine units (E / pi):
//   CUSTOM0: rgb every street lamp's light (direct + its bounce), a sky visibility
//   CUSTOM1: rgb natural light of state A (night: sky, moon, lit windows), a slot share 0
//   CUSTOM2: rgb natural light of state B (dusk), a slot share 1
//   CUSTOM3: slot lamp indices / 255 (rgb), a slot share 2
// Light = lamps x (1 - dot(shares, 1 - slot levels)) x lamp level
//       + mix(state A, state B, blend).
// Real lights (the nearest few lamps, the moon) only add their specular
// highlight (light()), so nothing is lit twice.
render_mode specular_schlick_ggx, ambient_light_disabled;
#include "res://shaders/lucid_city.gdshaderinc"
#ifdef WINDOWS
#include "res://shaders/lucid_windows.gdshaderinc"
uniform vec4 facade = vec4(0.0, 2.0, 3.0, 3.0);   // seed, kind, storey (m), bay (m)
uniform float shop_band = 0.0;                   // shop band height (m), 0 none
uniform float win_reflect = 0.9;
uniform float win_top = 1000.0;                  // the roof's height (m)
#endif

uniform vec3 albedo = vec3(0.35);         // linear (a measured albedo)
uniform sampler2D albedo_tex : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tex_mean = vec3(1.0);       // the texture's linear mean: detail averages 1
uniform bool use_normal = false;
uniform float normal_depth = 1.0;
uniform float uv_scale = 2.0;            // metres per texture repeat (world projected)
uniform float roughness = 0.8;
uniform float specular = 0.5;
uniform float rough_tex_mean = 0.6;
uniform vec3 emit_nits = vec3(0.0);      // self-luminous (cd/m2, linear RGB)
uniform vec4 lamp_lvl[8];                // levels of lamps 0..31 (4 per vec4)
uniform float sky_gloss = 0.0;           // how much the sky's reflection shows (wet / glossy)
uniform vec3 ground_origin = vec3(0.0);  // world position of the level's ground origin
uniform bool baked = true;               // false: no vertex bake, lit by const_light (E / pi, engine units)
uniform vec3 const_light = vec3(0.0);
uniform bool road_paint = false;         // the street grid's road paint (lucid_road_paint)

varying vec3 v_light;
varying float v_sky;
varying vec3 v_wpos;
varying vec3 v_wn;

float lvl(float idx) {
	int i = int(idx * 255.0 + 0.5);
	vec4 q = lamp_lvl[clamp(i >> 2, 0, 7)];
	int k = i & 3;
	return k == 0 ? q.x : (k == 1 ? q.y : (k == 2 ? q.z : q.w));
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 shares = vec3(CUSTOM1.a, CUSTOM2.a, CUSTOM3.a);
	vec3 levels = vec3(lvl(CUSTOM3.r), lvl(CUSTOM3.g), lvl(CUSTOM3.b));
	vec3 lamps = CUSTOM0.rgb * max(1.0 - dot(shares, vec3(1.0) - levels), 0.0) * lucid_sky.z;
	v_light = lamps + mix(CUSTOM1.rgb, CUSTOM2.rgb, lucid_sky.x);
	v_sky = CUSTOM0.a;
	if (!baked) {
		v_light = const_light;
		v_sky = 0.5;
	}
}

void fragment() {
	vec3 wn = normalize(v_wn);
	vec3 lp = v_wpos - ground_origin;
	vec2 pp = abs(wn.y) > 0.6 ? lp.xz : (abs(wn.x) > abs(wn.z) ? lp.zy : lp.xy);
	vec2 uv = pp / uv_scale;
	vec3 col = albedo * texture(albedo_tex, uv).rgb / max(tex_mean, vec3(0.001));
	float rough = clamp(roughness * texture(rough_tex, uv).g / rough_tex_mean, 0.05, 1.0);
	if (road_paint) {
		float pw = lucid_road_paint(lp.xz, length(fwidth(lp.xz)));
		col = mix(col, vec3(0.55, 0.54, 0.50), pw);
		rough = mix(rough, 0.6, pw);
	}
	if (use_normal) {
		vec3 nt = texture(normal_tex, uv).rgb * 2.0 - 1.0;
		nt.xy *= normal_depth;
		vec3 t = abs(wn.y) > 0.6 ? vec3(1.0, 0.0, 0.0) : (abs(wn.x) > abs(wn.z) ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0));
		vec3 b = abs(wn.y) > 0.6 ? vec3(0.0, 0.0, 1.0) : vec3(0.0, 1.0, 0.0);
		NORMAL = normalize((VIEW_MATRIX * vec4(normalize(t * nt.x + b * nt.y + wn * nt.z), 0.0)).xyz);
	}
	vec3 rad = col * v_light + emit_nits / LUCID_UNIT_NITS;
#ifdef WINDOWS
	if (abs(wn.y) < 0.5) {
		float u = abs(wn.x) > abs(wn.z) ? lp.z * sign(wn.x) : -lp.x * sign(wn.z);
		vec3 vw = normalize(v_wpos - CAMERA_POSITION_WORLD);
		vec3 r = reflect(vw, wn);
		float fr = lucid_fresnel(0.04, dot(-vw, wn)) * win_reflect;
		Facade fc = lucid_facade(u, lp.y, facade.y, facade.x, facade.z, facade.w, shop_band, lucid_reflection(r, lucid_air.rgb * 2.0) * v_sky, fr, win_top);
		rad = rad * (1.0 - fc.glass - fc.frame) + vec3(0.5, 0.49, 0.46) * v_light * fc.frame + fc.emit;
	}
#endif
	// The open sky mirrored by a damp surface (its share of the sky only).
	if (sky_gloss > 0.0) {
		vec3 vw = normalize(v_wpos - CAMERA_POSITION_WORLD);
		vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
		vec3 r = reflect(vw, nw);
		float f = lucid_fresnel(0.04, dot(-vw, nw)) * (1.0 - rough) * sky_gloss;
		rad += lucid_sky_now(r) * f * v_sky;
	}
	float d = length(v_wpos - CAMERA_POSITION_WORLD);
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = specular;
	EMISSION = lucid_finish(rad, d);
}

void light() {
	// Specular only (the diffuse is in the bake): GGX, Smith, Schlick.
	vec3 h = normalize(VIEW + LIGHT);
	float ndl = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
	float ndh = clamp(dot(NORMAL, h), 0.0, 1.0);
	float ndv = clamp(dot(NORMAL, VIEW), 0.001, 1.0);
	float a = ROUGHNESS * ROUGHNESS;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float dist = a2 / (PI * dd * dd);
	float vis = 0.5 / (ndl * sqrt(ndv * ndv * (1.0 - a2) + a2) + ndv * sqrt(ndl * ndl * (1.0 - a2) + a2) + 1e-5);
	float f = lucid_fresnel(0.08 * specular, dot(VIEW, h));
	SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * (PI * ndl * dist * vis * f);
}
