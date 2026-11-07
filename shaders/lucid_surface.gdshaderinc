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
// Stage 4 (lucid_spec.gdshaderinc): one physically based specular, taken
// from the diffuse: GGX with the material's F0 and roughness, after rain
// darker and smoother by its wetness (puddles in the low spots); what it
// mirrors is the street heads and the signals (analytic, per pixel), the
// moon (its light node) and everything else from the box-projected
// reflection probe of the part of the street it is in (or the sky model
// times the sky visibility where no probe is).
render_mode specular_schlick_ggx, ambient_light_disabled;
#include "res://shaders/lucid_city.gdshaderinc"
#include "res://shaders/lucid_street.gdshaderinc"
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
uniform float f0 = 0.04;                 // normal reflectance (dielectrics 0.02-0.05)
uniform float rough_tex_mean = 0.6;
uniform vec3 emit_nits = vec3(0.0);      // self-luminous (cd/m2, linear RGB)
uniform vec4 lamp_lvl[8];                // levels of lamps 0..31 (4 per vec4)
uniform bool reflect_env = false;        // sample the probe / sky for the specular (else only the moon)
uniform bool lamp_refl = false;          // mirror the street heads and the signals
uniform bool analytic_emitter = false;   // a lens whose reflections are analytic (dark in probes)
uniform sampler2DArray probe_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform int probe_n = 0;
uniform vec4 probe_c[8];                 // probe centres, box corners (level space)
uniform vec4 probe_lo[8];
uniform vec4 probe_hi[8];                // (lo.w, hi.w: the selecting box's x extent)
uniform vec4 probe_sel[8];               // the selecting box's z extent (x, y) and y extent (z, w)
uniform vec3 ground_origin = vec3(0.0);  // world position of the level's ground origin
uniform bool baked = true;               // false: no vertex bake, lit by const_light (E / pi, engine units)
uniform vec3 const_light = vec3(0.0);
uniform bool road_paint = false;         // the street grid's road paint (lucid_road_paint)

varying vec3 v_light;
varying float v_sky;
varying vec3 v_wpos;
varying vec3 v_wn;
varying float v_f0;

float lvl(float idx) {
	int i = int(idx * 255.0 + 0.5);
	vec4 q = lamp_lvl[clamp(i >> 2, 0, 7)];
	int k = i & 3;
	return k == 0 ? q.x : (k == 1 ? q.y : (k == 2 ? q.z : q.w));
}

// What the environment sends along r from lp: the probe whose box holds
// lp (box-projected), else the sky model times the sky visibility.
vec3 env_reflection(vec3 lp, vec3 r, float rough, float sky_vis) {
	for (int i = 0; i < 8; i++) {
		if (i >= probe_n) {
			break;
		}
		vec3 slo = vec3(probe_lo[i].w, probe_sel[i].z, probe_sel[i].x);
		vec3 shi = vec3(probe_hi[i].w, probe_sel[i].w, probe_sel[i].y);
		if (all(greaterThanEqual(lp, slo - 0.5)) && all(lessThanEqual(lp, shi + 0.5))) {
			vec3 d = lucid_box_dir(lp, r, probe_c[i].xyz, probe_lo[i].xyz, probe_hi[i].xyz);
			return textureLod(probe_tex, vec3(lucid_oct(normalize(d)), float(i)), lucid_probe_lod(rough, 128.0)).rgb;
		}
	}
	return lucid_sky_now(r) * sky_vis;
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
	vec3 nw = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	// After rain (lucid_wet): darker, smoother, puddles in the low spots.
	float fz = f0;
	if (wet > 0.0 || puddles > 0.0) {
		float film = puddles > 0.0 && wn.y > 0.6 ? puddle(lp.xz) : 0.0;
		// Water evens out the texture's roughness variation.
		rough = mix(rough, roughness, wet * 0.7);
		lucid_wet(col, rough, fz, wet, film);
		// The water fills the texture's pits (half its relief left),
		// and a puddle's surface is flat.
		nw = normalize(mix(nw, wn, max(film, wet * 0.5)));
		NORMAL = normalize((VIEW_MATRIX * vec4(nw, 0.0)).xyz);
	}
	vec3 vw = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float e_spec = lucid_spec_albedo(dot(nw, vw), rough, fz);
	float cap = lucid_capturing(PROJECTION_MATRIX);
	vec3 rad = col * v_light * (1.0 - e_spec) + emit_nits / LUCID_UNIT_NITS * (analytic_emitter ? 1.0 - cap : 1.0);
#ifdef WINDOWS
	if (abs(wn.y) < 0.5) {
		float u = abs(wn.x) > abs(wn.z) ? lp.z * sign(wn.x) : -lp.x * sign(wn.z);
		vec3 r = reflect(-vw, wn);
		float fr = lucid_fresnel(0.04, dot(vw, wn)) * win_reflect;
		Facade fc = lucid_facade(u, lp.y, facade.y, facade.x, facade.z, facade.w, shop_band, lucid_reflection(r, lucid_air.rgb * 2.0) * v_sky, fr, win_top);
		rad = rad * (1.0 - fc.glass - fc.frame) + vec3(0.5, 0.49, 0.46) * v_light * fc.frame + fc.emit;
	}
#endif
	// (Not in a probe's capture: the ground's own reflections would only
	// come back as glare round the horizon of its mips.)
	if ((reflect_env || lamp_refl) && cap < 0.5) {
		LucidMirror m = lucid_mirror(nw, vw, rough);
		vec3 spec = reflect_env ? env_reflection(lp, m.r, rough, v_sky) : vec3(0.0);
		if (lamp_refl) {
			spec += lamp_reflections(lp, m);
		}
		rad += spec * e_spec;
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	v_f0 = fz;
	EMISSION = lucid_finish_at(rad, v_wpos, CAMERA_POSITION_WORLD, cap);
}

void light() {
	// The moon's specular (the diffuse is in the bake; the street heads'
	// reflections are analytic, in fragment()).
	if (LIGHT_IS_DIRECTIONAL) {
		// (LIGHT_COLOR is E / pi: Lucid.light_node_cam.)
		SPECULAR_LIGHT += LIGHT_COLOR * ATTENUATION * LUCID_PI * lucid_ggx(NORMAL, VIEW, LIGHT, ROUGHNESS, v_f0);
	}
}
