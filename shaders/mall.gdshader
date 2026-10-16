// Dead Mall surfaces (tools/blender/mall_kit.py). Lighting is baked in
// Blender (ceiling panels, dusk through the skylights, bounce) into a
// lightmap per section; this adds the surface pattern from world position
// (no texture memory), grime, the shader flashlight and PS1 snapping.
// The lightmap stores sqrt(light / lm_scale).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
// (`lightmap` comes from common.gdshaderinc)

uniform vec3 albedo : source_color = vec3(0.6);
uniform int pattern = 0;     // 0 plain, 1 terrazzo, 2 tiles, 3 ceiling, 4 carpet/fabric, 5 wood, 6 shutter
uniform float roughness = 0.7;
uniform float emit = 0.0;
uniform float grime = 0.35;
uniform float lm_scale = 4.0;
uniform float floor_y = -4000.0;     // the mall's floor height (dirt collects low on walls)

varying vec3 v_wpos;
varying vec3 v_wn;

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
	float low = abs(n.y) < 0.6 ? smoothstep(0.6, 0.0, v_wpos.y - floor_y) : 0.0;
	col *= 1.0 - grime * (0.35 * smoothstep(0.45, 0.85, g) + 0.25 * low);
	vec3 lm = texture(lightmap, UV).rgb;
	vec3 light = lm * lm * lm_scale;
	ALBEDO = col;
	ROUGHNESS = rough;
	SPECULAR = 0.4;
	EMISSION = col * light + albedo * emit + col * flashlight(v_wpos, n, CAMERA_POSITION_WORLD, 1.0 - rough) + dither(FRAGCOORD.xy);
}
