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

varying vec3 v_wpos;
varying vec3 v_wn;

vec3 group_light(int g) {
	vec4 l = g == 0 ? level_light_0 : (g == 1 ? level_light_1 : (g == 2 ? level_light_2 : level_light_3));
	return l.rgb * l.a;
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
	light += g.r * group_light(0) + g.g * group_light(1) + g.b * group_light(2) + g.a * group_light(3);
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
			+ dither(FRAGCOORD.xy);
#ifdef CUTOUT
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_cut;
#endif
}
