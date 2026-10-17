// Photoreal trim: skirting boards, door casings, the ceiling's T-bar grid,
// light fitting rims. Off-white painted wood/metal, lit per vertex.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.84, 0.82, 0.74);

varying vec3 v_light;
varying vec3 v_wpos;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	v_ps1_aff = vec3(UV * POSITION.w, POSITION.w);
}

void fragment() {
	vec2 uv = ps1_uv(UV);
	float n = texture(noise_fine, uv * vec2(4.0, 9.0)).r;
	float grime = texture(noise_fine, uv * 0.7 + 0.3).r;
	vec3 col = base_color * (0.9 + 0.12 * n) * mix(1.0, 0.82, smoothstep(0.55, 0.8, grime));
	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.4;
	EMISSION = col * v_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.3) + dither(FRAGCOORD.xy);
}
