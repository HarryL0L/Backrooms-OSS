// The uncovered SUV in the Car Park (assets/garage/suv.glb). See
// garage_suv.gdshaderinc for the lighting.
shader_type spatial;
render_mode unshaded;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/garage_suv.gdshaderinc"
#include "res://shaders/car_light.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.5);
// 0 matte, 1 body paint, 2 chrome, 4 headlamp, 5 tail lamp
uniform int kind = 0;
uniform float gloss = 0.3;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_car = VERTEX + part_offset;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 a = kind == 1 && paint.a > 0.5 ? paint.rgb : albedo;
	vec3 wn = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float shade = car_shade(wn, v_car.y);
	// The cabin is in the roof's shadow.
	shade *= mix(1.0, 0.3, in_cabin(v_car));
	vec3 base = a * light * shade * 1.8;
	vec3 env = garage_env(v_wpos, reflect(-v, wn));

	float f = fresnel(wn, v);
	vec3 col;
	// A broad sheen towards where the light comes from.
	float dl = length(light_dir);
	vec3 rv = reflect(-v, wn);
	float sheen = dl > 0.001 ? pow(max(dot(rv, light_dir / dl), 0.0), 12.0) * min(dl, 1.0) * light : 0.0;
	if (kind == 1) {
		// Clear coat over the paint.
		col = base * (1.0 - f) + env * mix(0.1, 1.0, f) + vec3(0.9, 0.95, 1.0) * sheen * 0.5;
	} else if (kind == 2) {
		col = base * 0.3 + env * a * 1.3 + a * sheen;
	} else if (kind == 4) {
		col = base * 0.6 + env * 0.5 + vec3(1.0, 0.97, 0.9) * 3.0 * lamps;
	} else if (kind == 5) {
		col = base * 0.6 + env * 0.4 + vec3(1.0, 0.06, 0.03) * 1.8 * lamps;
	} else {
		col = base + env * gloss * f;
	}
	col += cabin_light(v_car, a);
	col += a * flashlight(v_wpos, wn, CAMERA_POSITION_WORLD, kind == 1 || kind == 2 ? 0.85 : gloss);
	ALBEDO = col + dither(FRAGCOORD.xy);
}
