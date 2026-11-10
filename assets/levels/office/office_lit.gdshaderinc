// The Dimming Floor's surfaces: the side levels' shader
// (shaders/level_lit.gdshaderinc, copied here unchanged but for the light
// groups) with switchable banks. The floor's 15 troffer columns are 15
// banks; bank k was baked into light group k % 4. Per pixel, each group's
// light is taken as coming from the nearest bank of that group (along x),
// blended over the half-way zone between two of them, and multiplied by
// that bank's own state (bank_tex: texel k = rgb output 0..1). So 15 banks
// switch, flicker and start up separately with the framework's four group
// channels. Emitters (the lenses) follow their own bank the same way.
// Regenerate from the framework's include if it changes (see SPEC.md).
// Side level surfaces (SideLevel.load_kit / SideLevel.lit_material): the
// Dead Mall's shader (mall.gdshader) made general, for real textures.
//
//  - Colour: `albedo` times an optional albedo texture, on the mesh's own UV
//    (times `uv_scale` repeats) or projected from world position (uv_mode 1,
//    `uv_scale` = metres per repeat, no UVs needed). Optional normal and
//    roughness maps (a Poly Haven _arm map works too: roughness is green).
//  - Light: baked in Blender (tools/blender/level_kit.py) into a colour
//    lightmap on UV2, stored as sqrt(light / lm_scale). Without one
//    (procedural or moving parts) the surface gets `const_light`.
//  - Light groups: an optional second lightmap on UV2 whose R, G, B, A are
//    four grey bakes of four banks of lights, each times its group's global
//    colour * intensity (level_light_0..3: rgb colour, a intensity, set by
//    SideLevel.set_light_group), so a level can switch, dim and flicker
//    baked banks of light at run time. Without a group map, `group_mix` says
//    how much of each group lights the surface (flat).
//  - Real-time lights (a passing train's windows, the flashlight) add on
//    top, through the normal lighting: the baked light goes in EMISSION and
//    there is no ambient.
//  - PS1 style snaps vertices and texels; the shader flashlight (no light
//    nodes on the low presets) and Potato's dark lift work as in the
//    Backrooms.
// A cutout variant (level_lit_cutout.gdshader) adds alpha testing (grating,
// mesh fences, chain link) from the albedo texture's alpha.
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
uniform sampler2D bank_tex : hint_default_white, filter_nearest, repeat_disable;
uniform int bank_count = 15;
uniform float bank_x0 = 1.524;
uniform float bank_pitch = 2.4384;
// The banks' far light (beyond the two nearest of each group, which the
// bake carries): a 64 x 1 strip along x (far_x0 .. far_x0 + far_len), its
// value = sqrt(E / pi / 0.1), engine units, set by the level each frame.
uniform sampler2D far_tex : hint_default_black, filter_linear, repeat_disable;
uniform float far_x0 = -2.0;
uniform float far_len = 40.96;

varying vec3 v_wpos;
varying vec3 v_wn;

vec3 bank_state(int k) {
	return (k < 0 || k >= bank_count) ? vec3(-1.0) : texelFetch(bank_tex, ivec2(k, 0), 0).rgb;
}

vec3 group_light(int g) {
	vec4 l = g == 0 ? level_light_0 : (g == 1 ? level_light_1 : (g == 2 ? level_light_2 : level_light_3));
	return l.rgb * l.a;
}

// Group g's light at world x: its nearest bank's state (blended between the
// two nearest banks of the group half way between them).
vec3 group_bank(int g, float x) {
	float m = ((x - bank_x0) / bank_pitch - float(g)) * 0.25;
	float m0 = floor(m);
	float t = smoothstep(0.3, 0.7, m - m0);
	vec3 a = bank_state(g + 4 * int(m0));
	vec3 b = bank_state(g + 4 * int(m0) + 4);
	if (a.x < 0.0) { a = b; }
	if (b.x < 0.0) { b = a; }
	return max(mix(a, b, t), vec3(0.0)) * group_light(g);
}

void vertex() {
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
	float bx = v_wpos.x;
	light += g.r * group_bank(0, bx) + g.g * group_bank(1, bx) + g.b * group_bank(2, bx) + g.a * group_bank(3, bx);
	float fl = texture(far_tex, vec2(clamp((bx - far_x0) / far_len, 0.0, 1.0), 0.5)).r;
	light += fl * fl * 0.1 * group_light(0) * (0.75 + 0.25 * max(wn.y, 0.0));
	// Potato: the darkest places lifted a little (see dark_lift).
	float lum = dot(light, vec3(0.3, 0.59, 0.11));
	light += vec3(1.0, 0.95, 0.84) * dark_lift * (1.0 - smoothstep(0.0, 0.45, lum));
	vec3 lamp = emit_group >= 0 ? group_bank(emit_group, bx) : vec3(1.0);
	vec3 n_world = normalize((INV_VIEW_MATRIX * vec4(n_view, 0.0)).xyz);
	ALBEDO = col;
	ROUGHNESS = rough;
	METALLIC = metallic;
	SPECULAR = specular;
	EMISSION = col * light + col * emit * lamp + col * flashlight(v_wpos, n_world, CAMERA_POSITION_WORLD, 1.0 - rough)
			+ dither(FRAGCOORD.xy);
#ifdef CUTOUT
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
#endif
}
