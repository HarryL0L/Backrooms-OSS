// The SUV's windows: tinted, see-through (the cabin shows when its light is
// on), with the ceiling tubes sliding across them.
shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/garage_suv.gdshaderinc"

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_car = VERTEX + part_offset;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_wpos);
	if (dot(wn, v) < 0.0) {
		wn = -wn;
	}
	float f = fresnel(wn, v);
	vec3 env = garage_env(v_wpos, reflect(-v, wn));
	vec3 tint = vec3(0.02, 0.025, 0.025) * light;
	ALBEDO = tint + env * mix(0.12, 1.0, f) + flashlight(v_wpos, wn, CAMERA_POSITION_WORLD, 0.95) * 0.15;
	ALPHA = clamp(0.55 + f * 0.45, 0.0, 1.0);
}
