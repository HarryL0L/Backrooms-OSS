shader_type spatial;
// Soft volumetric-looking shaft of sunlight below a skylight.
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 shaft_color : source_color = vec3(1.0, 0.9, 0.72);
uniform float strength = 0.07;

varying vec3 v_wpos;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float edge = pow(abs(dot(normalize(NORMAL), normalize(VIEW))), 3.0);
	float fall = mix(1.0, 0.0, UV.y) * smoothstep(0.0, 0.12, UV.y);
	float side = smoothstep(0.0, 0.5, UV.x) * smoothstep(1.0, 0.5, UV.x);
	float dust = 0.75 + 0.5 * texture(noise_fine, v_wpos.xz * 0.4 + vec2(0.0, v_wpos.y * 0.2) + world_time * 0.01).r;
	float near_fade = smoothstep(0.4, 2.5, length(v_wpos - CAMERA_POSITION_WORLD));
	ALBEDO = shaft_color * strength * edge * fall * side * dust * near_fade;
}
