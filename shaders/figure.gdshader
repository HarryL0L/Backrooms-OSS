// The people (and things) in the Backrooms: downloaded figures with their
// own textures, lit like the world. Backrooms surfaces carry their baked
// light as emission, so a figure is given the light level where it stands
// as `env_light` (per material copy, not an instance uniform: old Mali
// drivers drop those), plus the shader flashlight. Hair cards and lashes
// are cut out by alpha.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx, cull_disabled;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness = 0.7;
uniform float alpha_cut = 0.0;     // > 0 for hair, lashes
uniform vec3 env_light = vec3(0.0);
// L.U.C.I.D.: the probe grid's ambient cube where it stands (env_cube_light).
uniform mat3 env_pos = mat3(0.0);
uniform mat3 env_neg = mat3(0.0);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec4 t = texture(albedo_tex, UV) * tint;
	if (alpha_cut > 0.0 && t.a < alpha_cut) {
		discard;
	}
	vec3 col = t.rgb;
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.3;
	vec3 n = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	EMISSION = col * (env_light + env_cube_light(env_pos, env_neg, n)) * lucid_exposure.rgb + col * flashlight(v_wpos, n, CAMERA_POSITION_WORLD, 1.0 - roughness);
}
