shader_type spatial;
// Soft volumetric-looking shaft of sunlight (sun gallery windows). Drawn on
// the sides of a slanted prism: UV.x runs across a side, UV.y from the window
// (0) to where it meets the water (1).
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled, fog_disabled;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 shaft_color : source_color = vec3(1.0, 0.96, 0.88);
uniform float strength = 0.22;

varying vec3 v_wpos;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 1.5);
	float fall = mix(1.0, 0.45, UV.y) * smoothstep(0.0, 0.06, UV.y) * smoothstep(1.0, 0.9, UV.y);
	float side = smoothstep(0.0, 0.5, UV.x) * smoothstep(1.0, 0.5, UV.x);
	float dust = 0.75 + 0.5 * texture(noise_fine, v_wpos.xz * 0.4 + vec2(0.0, v_wpos.y * 0.2) + world_time * 0.01).r;
	// Looking down a hall you see through the sides of every shaft in the row;
	// fading distant ones keeps the stack from adding up to a white sheet.
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float near_fade = smoothstep(0.6, 4.5, dist) * (1.0 - smoothstep(8.0, 22.0, dist));
	ALBEDO = shaft_color * strength * edge * fall * side * dust * near_fade;
}
