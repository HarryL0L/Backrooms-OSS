// Dead Mall surfaces (tools/blender/mall_kit.py). Lighting is baked in
// Blender (ceiling panels, dusk through the skylights, bounce) into a
// lightmap per section; this adds the surface pattern from world position
// (no texture memory), grime, the shader flashlight and PS1 snapping.
// The lightmap stores sqrt(light / lm_scale).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/lucid_spec.gdshaderinc"
// (`lightmap` comes from common.gdshaderinc)

uniform vec3 albedo : source_color = vec3(0.6);
uniform int pattern = 0;     // 0 plain, 1 terrazzo, 2 tiles, 3 ceiling, 4 carpet/fabric, 5 wood, 6 shutter
uniform float roughness = 0.7;
uniform float emit = 0.0;
uniform float grime = 0.35;
uniform float lm_scale = 4.0;
uniform float floor_y = -4000.0;     // the mall's ground floor (dirt collects low on walls)
uniform float storey_h = 5.0;        // floor to floor, for the floors above
// Realistic: the ceiling light panels seen from above (MallLevel's
// _build_reflections): R = panel cover, G = cover x height above floor_y / 16 m.
uniform sampler2D refl_map : hint_default_black, filter_linear_mipmap_anisotropic, repeat_disable;
uniform vec4 refl_rect = vec4(0.0);  // x0, z0, 1 / width (m), 1 / depth (m); 0 = none
// Realistic (stage 4): measured roughness and normal reflectance (F0) of
// the surface (MallLevel.REAL_SPEC; rough_real < 0 keeps `roughness`), the
// panels' radiance in lightmap units, and the section's reflection probe
// (LucidProbe, box-projected; probe_box_lo.w = 0 none).
uniform float rough_real = -1.0;
uniform float f0 = 0.04;
uniform vec3 panel_rad = vec3(9.0, 8.73, 8.1);
uniform sampler2D probe_tex : hint_default_black, filter_linear_mipmap, repeat_disable;
uniform vec4 probe_c = vec4(0.0);
uniform vec4 probe_box_lo = vec4(0.0);
uniform vec4 probe_box_hi = vec4(0.0);

varying vec3 v_wpos;
varying vec3 v_wn;
varying vec3 v_origin;

// Realistic (L.U.C.I.D. stage 4, lucid_spec.gdshaderinc): the polished
// floors' reflections. The panels are emitters of the radiance the
// lightmap was baked with (Blender emission strength 9, the same units as
// the lightmap's light). Follow the mirrored view ray up to the heights
// where they hang over a storey (3.5 and 4.75 m) and the ceilings of the
// floors above seen through the atrium (about 9 m), and read the panel
// map there over the reflected lobe's footprint on that plane: sigma x
// distance / sin(elevation) along the ray, sigma_across x distance across
// it, so the panels stretch into streaks toward you as on a real polished
// floor. Returns the share of the lobe on a lit panel.
float panel_cover(vec3 wpos, LucidMirror m, float pixm, float de) {
	vec3 r = m.r;
	if (r.y < 0.03) {
		return 0.0;
	}
	float fy = wpos.y - floor_y;
	float lvl = floor(fy / storey_h + 0.5) * storey_h;
	float best = 0.0;
	vec3 hts = vec3(3.5, 4.75, 9.0);
	vec2 dir = normalize(r.xz + vec2(1e-5));
	for (int i = 0; i < 3; i++) {
		float d = (hts[i] + lvl - fy) / r.y;
		vec2 hp = wpos.xz + r.xz * d;
		vec2 uv = (hp - refl_rect.xy) * refl_rect.zw;
		if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
			continue;
		}
		// The footprint's gaussian sigmas on the plane (m); a box filter
		// of about 2.5 sigma reads the same mean.
		float fa = m.sig.x * d / r.y;
		float fc = m.sig.y * d;
		// Never finer than the pixel's own footprint there (no sparkle):
		// the floor pixel's, scaled as the mirror image lies further off.
		float pix = pixm * (1.0 + d / max(de, 0.1)) * refl_rect.z;
		vec2 ga = dir * refl_rect.zw * fa * 2.5;
		vec2 gc = vec2(-dir.y, dir.x) * refl_rect.zw * fc * 2.5;
		ga *= max(1.0, pix / max(length(ga), 1e-6));
		gc *= max(1.0, pix / max(length(gc), 1e-6));
		vec4 s = textureGrad(refl_map, uv, ga, gc);
		if (s.r > 0.002) {
			float h = s.g / s.r * 16.0 - lvl;
			best = max(best, s.r * (1.0 - smoothstep(0.6, 1.2, abs(h - hts[i]))));
		}
	}
	return best;
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_origin = MODEL_MATRIX[3].xyz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 n = normalize(v_wn);
	vec2 pp = abs(n.y) > 0.6 ? v_wpos.xz : (abs(n.x) > abs(n.z) ? v_wpos.zy : v_wpos.xy);
	if (ps1_grid.x > 0.0) {
		pp = floor(pp * 40.0) / 40.0;      // chunky texels, like the rest of PS1 mode
	}
	vec3 col = albedo;
	float rough = roughness;
	if (pattern == 1) {
		// Terrazzo: marble chips in cement, a few bigger ones, polished.
		vec2 c = floor(pp * 70.0);
		float r = hash12(c);
		vec3 chip = mix(vec3(0.82, 0.78, 0.7), vec3(0.32, 0.3, 0.28), step(0.5, hash12(c + 7.1)));
		chip = mix(chip, vec3(0.62, 0.45, 0.35), step(0.86, hash12(c + 3.3)));
		col = mix(col, chip, step(0.6, r) * 0.3);
		col *= 0.9 + 0.1 * vnoise(pp * 9.0);
	} else if (pattern == 2) {
		vec2 g = fract(pp / 0.3);
		float grout = step(0.955, max(g.x, g.y));
		col = mix(col * (0.95 + 0.06 * hash12(floor(pp / 0.3))), vec3(0.35, 0.33, 0.3), grout);
	} else if (pattern == 3) {
		col *= 0.9 + 0.1 * step(0.75, hash12(floor(pp * 70.0)));
		float stain = smoothstep(0.62, 0.8, vnoise(pp * 0.45 + 3.0));
		col = mix(col, col * vec3(0.72, 0.6, 0.42), stain * 0.7);
	} else if (pattern == 4) {
		col *= 0.78 + 0.4 * hash12(floor(pp * 140.0));
	} else if (pattern == 5) {
		float gr = sin(pp.x * 46.0 + vnoise(pp * vec2(2.0, 18.0)) * 5.0);
		col *= 0.86 + 0.14 * gr;
	} else if (pattern == 6) {
		col *= 0.8 + 0.2 * smoothstep(-0.4, 0.8, sin(v_wpos.y * 62.83));
	}
	// Grime: dirt pooling low on walls, blotches everywhere.
	float g = vnoise(pp * 0.6) * 0.6 + vnoise(pp * 2.7) * 0.4;
	float low = abs(n.y) < 0.6 ? smoothstep(0.6, 0.0, mod(v_wpos.y - floor_y + 0.05, storey_h) - 0.05) : 0.0;
	col *= 1.0 - grime * (0.35 * smoothstep(0.45, 0.85, g) + 0.25 * low);
	vec3 lm = texture(lightmap, UV).rgb;
	vec3 light = lm * lm * lm_scale;
	if (pattern == 6) {
		// Shutters: hundreds of thin slats get only a few lightmap texels
		// each and bake too dark; they're out in the concourse light.
		light = max(light, vec3(0.32, 0.31, 0.29));
	}
	vec3 refl = vec3(0.0);
	float keep = 1.0;
	float cap = lucid_capturing(PROJECTION_MATRIX);
	if (realistic > 0.5 && rough_real >= 0.0) {
		rough = rough_real;
		vec3 v = normalize(CAMERA_POSITION_WORLD - v_wpos);
		float e_spec = lucid_spec_albedo(dot(n, v), rough, f0);
		keep = 1.0 - e_spec;
		LucidMirror mr = lucid_mirror(n, v, rough);
		if (probe_box_lo.w > 0.5) {
			vec3 pd = lucid_box_dir(v_wpos, mr.r, v_origin + probe_c.xyz, v_origin + probe_box_lo.xyz, v_origin + probe_box_hi.xyz);
			refl += textureLod(probe_tex, lucid_oct(normalize(pd)), lucid_probe_lod(rough, 128.0)).rgb * e_spec;
		}
		if (refl_rect.z > 0.0 && n.y > 0.6) {
			refl += panel_rad * panel_cover(v_wpos, mr, length(fwidth(v_wpos.xz)), length(CAMERA_POSITION_WORLD - v_wpos)) * e_spec * (1.0 - cap);
		}
	}
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	EMISSION = col * light * keep + albedo * emit * (1.0 - cap * step(1.0, emit)) + col * flashlight(v_wpos, n, CAMERA_POSITION_WORLD, 1.0 - rough) + refl + dither(FRAGCOORD.xy);
}
