shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.52, 0.40, 0.25);

varying vec3 v_light;
varying vec3 v_wpos;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	float n = texture(noise_fine, uv * vec2(0.6, 6.0)).r;
	vec3 col = base_color * (0.82 + 0.3 * n);
	float tape = step(abs(fract(uv.x / 0.97) - 0.5), 0.05);
	col = mix(col, vec3(0.62, 0.55, 0.42), tape * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.9;
	EMISSION = col * v_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.1) + dither(FRAGCOORD.xy);
}
