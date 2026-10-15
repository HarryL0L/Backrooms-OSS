shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

// Chrome rails, rusty service pipes, plastic fittings.
uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.8);
uniform float metal = 1.0;
uniform float rough = 0.15;
uniform float rust = 0.0;

varying vec3 v_light;
varying vec3 v_wpos;
varying vec3 v_wn;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = NORMAL;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 col = base_color;
	float r = rough;
	if (rust > 0.0) {
		float n = texture(noise_blot, UV * vec2(0.6, 1.3)).r;
		float n2 = texture(noise_fine, UV * 3.0).r;
		float rr = smoothstep(0.45, 0.7, n) * rust;
		col = mix(col * (0.8 + 0.4 * n2), vec3(0.36, 0.17, 0.08) * (0.7 + 0.5 * n2), rr);
		r = mix(r, 0.95, rr);
	}
	// Fake environment reflection: bright above (lights), dark below.
	vec3 v = normalize(v_wpos - CAMERA_POSITION_WORLD);
	vec3 refl = reflect(v, normalize(v_wn));
	float env = mix(0.55, 1.8, smoothstep(-0.3, 0.7, refl.y));
	float streak = pow(max(refl.y, 0.0), 24.0) * 3.0;
	vec3 spec = (v_light + 0.15) * (env + streak) * mix(0.04, 1.0, metal) * (1.0 - r * 0.8);
	ALBEDO = col;
	METALLIC = metal;
	ROUGHNESS = r;
	EMISSION = col * v_light * (1.0 - metal * 0.85) + spec * mix(vec3(1.0), col, metal) + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 1.0 - r) + dither(FRAGCOORD.xy);
}
