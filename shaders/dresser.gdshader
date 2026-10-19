// The Window Dresser (Dead Mall entity). Baked colour + normal map from the
// Blender sculpt (tools/blender/window_dresser_game.py). Lit like the world:
// `env_light` is the light where it stands, given a direction from above so
// the ribs, cracks and broken shell read, plus the shader flashlight.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap, hint_default_white;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool use_textures = true;
uniform vec3 albedo : source_color = vec3(0.74, 0.68, 0.55);
uniform float roughness = 0.4;
uniform float glow = 0.0;              // emissive parts (eye glints)
uniform vec3 env_light = vec3(0.3);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 col = albedo;
	vec3 n = NORMAL;
	if (use_textures) {
		col = texture(albedo_tex, UV).rgb;
		vec3 nm = texture(normal_tex, UV).xyz * 2.0 - 1.0;
		n = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * nm.z);
		NORMAL = n;
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	// Overhead fluorescent light, a little from the front, and a dim fill.
	float key = max(dot(wn, normalize(vec3(0.2, 1.0, 0.35))), 0.0);
	float shade = 0.28 + 0.9 * key + 0.12 * max(-wn.y, 0.0);
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = 0.45;
	EMISSION = col * env_light * shade + col * flashlight(v_wpos, wn, CAMERA_POSITION_WORLD, 0.55)
			+ col * glow + dither(FRAGCOORD.xy);
}
