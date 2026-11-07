// L.U.C.I.D. stage 3: the city's backdrop buildings, thousands of boxes
// in a few MultiMeshes (a unit box, base at y = 0, scaled per instance).
// INSTANCE_CUSTOM: x seed, y kind + 10 x lamp type (0 LED, 1 sodium) +
// 100 x shops, z storey height (m), w bay width (m).
//
// Not baked: lit analytically by the state's far field (set by the level
// from Lucid.STATES, engine units E / pi): the sky on roofs and on walls
// (half of it hidden by the neighbours), the street lamps' light washing
// the lower floors (falling off with height above the 10 m lamp heads),
// and the moon on the faces turned to it, more on the upper floors that
// clear the street canyon. Windows as in lucid_windows.gdshaderinc.
shader_type spatial;
render_mode unshaded, fog_disabled;
#include "res://shaders/lucid_city.gdshaderinc"
#include "res://shaders/lucid_windows.gdshaderinc"

uniform vec3 e_sky_up = vec3(0.0005);
uniform vec3 e_sky_side = vec3(0.0003);
uniform vec3 e_moon = vec3(0.0003);
uniform vec3 moon_dir = vec3(0.0, 0.5, 0.8);
uniform vec3 e_street_led = vec3(0.01);
uniform vec3 e_street_na = vec3(0.01);
uniform float ground_y = 0.0;

varying vec4 v_custom;
varying vec3 v_wpos;
varying vec3 v_wn;
varying vec3 v_size;
varying float v_base;
varying float v_top;

void vertex() {
	v_custom = INSTANCE_CUSTOM;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_base = MODEL_MATRIX[3].y - ground_y;
	v_top = v_base + length(MODEL_MATRIX[1].xyz);
}

void fragment() {
	vec3 wn = normalize(v_wn);
	float seed = v_custom.x;
	float code = v_custom.y;
	float kind = mod(code, 10.0);
	float na = mod(floor(code / 10.0), 10.0);
	float shops = floor(code / 100.0);
	float v = v_wpos.y - ground_y;
	float h1 = lucid_hash(vec2(seed * 3.7, 1.3));
	vec3 vw = v_wpos - CAMERA_POSITION_WORLD;
	float d = length(vw);
	vw /= d;
	vec3 rad;
	if (wn.y > 0.5) {
		// A flat roof: dark membrane or gravel under the sky and the moon.
		vec3 roof = vec3(0.13, 0.13, 0.135) * (0.7 + 0.6 * h1);
		rad = roof * (e_sky_up + e_moon * max(moon_dir.y, 0.0));
	} else {
		vec3 wall = kind > 0.5 && kind < 1.5 ? vec3(0.09, 0.1, 0.11) * (0.8 + 0.5 * h1)
				: mix(vec3(0.42, 0.40, 0.36), vec3(0.30, 0.20, 0.14), step(0.55, h1)) * (0.7 + 0.5 * lucid_hash(vec2(seed, 7.7)));
		vec3 street = mix(e_street_led, e_street_na, na);
		float sv = exp(-max(v - 6.0, 0.0) / 9.0);
		float clear = smoothstep(10.0, 60.0, v);
		vec3 e = e_sky_side * (0.45 + 0.4 * clear) + street * sv + e_moon * max(dot(wn, moon_dir), 0.0) * (0.25 + 0.75 * clear);
		float u = abs(wn.x) > abs(wn.z) ? v_wpos.z * sign(wn.x) : -v_wpos.x * sign(wn.z);
		vec3 r = reflect(vw, wn);
		float fr = lucid_fresnel(0.04, dot(-vw, wn)) * 0.9;
		Facade fc = lucid_facade(u, v, kind, seed, v_custom.z, v_custom.w, shops > 0.5 && v_base < 0.5 ? 4.5 : 0.0,
				lucid_reflection(r, lucid_air.rgb * 2.0) * (0.4 + 0.6 * clear), fr, v_top);
		rad = wall * e * (1.0 - fc.glass - fc.frame) + vec3(0.5, 0.49, 0.46) * e * fc.frame + fc.emit;
	}
	ALBEDO = lucid_finish(rad, d);
}
