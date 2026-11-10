// A grille's core drawn analytically on one quad (the crawlspace's eggcrate
// registers, the exit's bar grille and the entry's sidewall grille): a slab
// `depth` deep, under the quad's face (local +Y is the "top" side, the
// slab runs down to -depth), crossed by thin walls every `pitch` along
// local X and/or Z (0 = no walls across that axis), leaning `slant`
// (tan of the lean, dX/d(depth)) for a bar grille's angled bars.
//
// Per pixel it follows the view ray through the slab: where it gets
// through, the quad is transparent (what is behind shows: the lit office
// below, or the duct above); where it hits a wall, that wall is shaded by
// where on it the ray lands (light comes in from both open faces and dies
// away into the cells), lit by the torch like any surface. The see-through
// share is filtered over the pixel's footprint and goes to its mean far
// off, so the fine core neither shimmers nor stair-steps without MSAA
// (it replaces ~1200 sub-texel strips whose bake came out black).
//
// Light values are linear Vector3 / Vector4 (never Color: Godot converts a
// Color for a vec3/vec4 uniform from sRGB, see docs/LUCID.md).
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, diffuse_burley, specular_schlick_ggx, shadows_disabled;
#include "res://shaders/common.gdshaderinc"

uniform vec2 pitch = vec2(0.0127, 0.0127);
uniform float depth = 0.0127;
uniform vec2 slant = vec2(0.0);
uniform float thick = 0.0005;
uniform vec3 albedo : source_color = vec3(0.8);
uniform float roughness = 0.5;
uniform float metallic = 0.0;
// Light reaching the slab through its top and bottom faces (E / pi, the
// level shader's units), plus each light group's share (as group_mix).
uniform vec3 light_top = vec3(0.01);
uniform vec3 light_bottom = vec3(0.3);
uniform vec4 groups_top = vec4(0.0);
uniform vec4 groups_bottom = vec4(0.0);
// Many grilles in one mesh (one draw): each quad's bottom light in its
// vertex COLOR (rgb) and its groups' shares in CUSTOM0, instead of the two
// uniforms above.
uniform bool per_vertex = false;
// How much of a face's light still reaches the far end of a wall.
uniform float reach = 0.12;
global uniform vec4 level_light_0;
global uniform vec4 level_light_1;
global uniform vec4 level_light_2;
global uniform vec4 level_light_3;

varying vec3 v_local;
varying vec3 v_cam;
varying vec3 v_bottom;
varying vec4 v_groups;

vec3 grp(vec4 g) {
	return g.x * level_light_0.rgb * level_light_0.a + g.y * level_light_1.rgb * level_light_1.a
			+ g.z * level_light_2.rgb * level_light_2.a + g.w * level_light_3.rgb * level_light_3.a;
}

void vertex() {
	v_local = VERTEX;
	v_cam = (inverse(MODEL_MATRIX) * vec4(CAMERA_POSITION_WORLD, 1.0)).xyz;
	v_bottom = per_vertex ? COLOR.rgb : light_bottom;
	v_groups = per_vertex ? CUSTOM0 : groups_bottom;
}

// Share of a box filter of width w round c (periodic, period 1) inside [lo, hi].
float cover(float c, float w, float lo, float hi) {
	if (hi <= lo) {
		return 0.0;
	}
	float a = c - 0.5 * w;
	float b = c + 0.5 * w;
	float s = 0.0;
	for (int k = -1; k <= 1; k++) {
		float o = float(k);
		s += max(min(b, hi + o) - max(a, lo + o), 0.0);
	}
	return clamp(s / max(w, 1e-5), 0.0, 1.0);
}

void fragment() {
	vec3 v = normalize(v_local - v_cam);
	bool above = v_cam.y > v_local.y;
	float vy = (abs(v.y) < 1e-4 ? 1e-4 : v.y);
	// Across each axis: where in its cell the ray enters (c, in cells), how
	// far it moves across the cell over the slab's depth (dlt, signed, from
	// the entry face), and the see-through share.
	vec2 xz = vec2(v_local.x, v_local.z);
	vec2 vxz = vec2(v.x, v.z);
	float hit = 2.0;          // where along the depth the first wall is hit (0 entry .. 1 exit), >1 none
	int axis = -1;
	bool edge = false;
	float pass = 1.0;
	float far_k = 0.0;
	for (int i = 0; i < 2; i++) {
		if (pitch[i] <= 0.0) {
			continue;
		}
		float s = (-vxz[i] / vy - slant[i]) * depth / pitch[i];
		float u_top = xz[i] / pitch[i];
		float u_in = above ? u_top : u_top + s;
		float dlt = above ? s : -s;
		float c = fract(u_in);
		float e = 0.5 * thick / pitch[i];
		// The open interval for the entry point: inside the walls at entry
		// and still inside at exit.
		float lo = max(e, e - dlt);
		float hi = min(1.0 - e, 1.0 - e - dlt);
		// (the pixel's footprint across the cells, a little widened: cover()
		// is a box filter, so the mean only takes over near a cell a pixel)
		float w = length(vec2(dFdx(u_top), dFdy(u_top))) * 1.5;
		float k = smoothstep(0.5, 1.0, w);
		pass *= mix(cover(c, w, lo, hi), max(hi - lo, 0.0), k);
		far_k = max(far_k, k);
		// The first wall this axis puts in the way.
		float hi_ = 2.0;
		bool ed = false;
		if (c < e || c > 1.0 - e) {
			hi_ = 0.0;
			ed = true;
		} else if (dlt > 1e-5) {
			hi_ = (1.0 - e - c) / dlt;
		} else if (dlt < -1e-5) {
			hi_ = (c - e) / -dlt;
		}
		if (hi_ < hit) {
			hit = hi_;
			axis = i;
			edge = ed;
		}
	}
	// The wall's light where the ray lands on it (g: 0 top face .. 1 bottom
	// face), from both open faces, dying away into the cell.
	// (A cell wall sees less and less of a face's opening the further from
	// it: about the square of the distance's complement, down to `reach`;
	// far off, the mean over the wall, reach + (1 - reach) / 3.)
	float g = clamp(above ? hit : 1.0 - hit, 0.0, 1.0);
	vec3 top = light_top + grp(groups_top);
	vec3 bot = v_bottom + grp(v_groups);
	float wt = reach + (1.0 - reach) * (1.0 - g) * (1.0 - g);
	float wb = reach + (1.0 - reach) * g * g;
	float wm = reach + (1.0 - reach) / 3.0;
	// Its normal (local), facing the ray: a wall across axis i (leaning), or
	// the end face of the walls at the entry.
	vec3 n = vec3(0.0, above ? 1.0 : -1.0, 0.0);
	if (axis >= 0 && !edge && far_k < 0.99) {
		vec3 wn = axis == 0 ? vec3(1.0, slant.x, 0.0) : vec3(0.0, slant.y, 1.0);
		wn = normalize(wn);
		n = dot(wn, v) > 0.0 ? -wn : wn;
	}
	// A face turned towards one opening takes more of its light (a leaning
	// bar's face towards you, from your side; upright walls see both alike).
	float fy = mix(clamp(0.5 + 0.5 * n.y, 0.0, 1.0), 0.5, far_k);
	vec3 light = top * mix(wt, wm, far_k) * (0.3 + 1.4 * fy) + bot * mix(wb, wm, far_k) * (1.7 - 1.4 * fy);
	vec3 wpos = (MODEL_MATRIX * vec4(v_local - vec3(0.0, depth * clamp(hit, 0.0, 1.0) * (above ? 1.0 : 0.0), 0.0), 1.0)).xyz;
	vec3 n_world = normalize((MODEL_MATRIX * vec4(n, 0.0)).xyz);
	float lum = dot(light, vec3(0.3, 0.59, 0.11));
	light += vec3(1.0, 0.95, 0.84) * dark_lift * (1.0 - smoothstep(0.0, 0.45, lum));
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);
	EMISSION = albedo * light + albedo * flashlight(wpos, n_world, CAMERA_POSITION_WORLD, 1.0 - roughness) + dither(FRAGCOORD.xy);
	ALPHA = clamp(1.0 - pass, 0.0, 1.0);
}
