// Poly Haven's covered car (assets/garage) in the Car Park. Self-lit like the
// rest of the Backrooms: the light where it stands (instance uniform), shaded
// by which way the cloth faces and where the lights are, with the hem in
// shadow (car_light.gdshaderinc), the cover's own normal map for its folds,
// plus the flashlight.
shader_type spatial;
render_mode unshaded;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/car_light.gdshaderinc"

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform float has_normal = 1.0;
instance uniform float light = 0.5;

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 a = texture(albedo_tex, UV).rgb;
	vec3 nv = NORMAL;
	if (has_normal > 0.5) {
		vec3 nm = texture(normal_tex, UV).xyz * 2.0 - 1.0;
		nv = normalize(TANGENT * nm.x + BINORMAL * nm.y + NORMAL * nm.z);
	}
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(nv, 0.0)).xyz);
	float shade = car_shade(wn, v_wpos.y);
	ALBEDO = a * light * shade * 1.8 + a * flashlight(v_wpos, wn, CAMERA_POSITION_WORLD, 0.1) + dither(FRAGCOORD.xy);
}
