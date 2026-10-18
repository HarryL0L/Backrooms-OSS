// The stairwell shaft (Stairwell): bare concrete and painted walls lit by a
// bulb over every landing and half landing. Self-lit like the rest of the
// Backrooms (no light nodes): Lambert from the bulbs with a short falloff, so
// slabs facing away from a bulb stay dark, plus the flashlight.
shader_type spatial;
render_mode unshaded;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

const int LAMPS = 10;
uniform vec3 lamps[10];            // stairwell-local bulb positions
uniform vec3 tint = vec3(1.0);
uniform float use_tint = 0.0;
uniform float ambient = 0.0;
instance uniform vec3 origin;      // where this stairwell stands

varying vec3 v_col;
varying vec3 v_wpos;
varying vec3 v_wn;

void vertex() {
	v_col = mix(COLOR.rgb, tint, use_tint);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

float hash3(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

void fragment() {
	vec3 lp = v_wpos - origin;
	vec3 light = vec3(0.012, 0.012, 0.011) + ambient;
	for (int i = 0; i < LAMPS; i++) {
		vec3 d = lamps[i] - lp;
		float dist = length(d);
		float att = max(1.0 - dist / 6.5, 0.0);
		att *= att;
		float ndl = max(dot(v_wn, d / max(dist, 0.001)), 0.0);
		// One bulb in the shaft is going: it flickers.
		float fl = i == 3 ? flicker(7.3, world_time) : 1.0;
		light += vec3(1.0, 0.9, 0.74) * 2.4 * att * (0.2 + 0.8 * ndl) * fl;
	}
	// Grime: blotches and darker towards the floor of each landing.
	float g = hash3(floor(lp * 6.0)) * 0.08 + hash3(floor(lp * 1.3)) * 0.12;
	vec3 base = v_col * (0.9 - g);
	ALBEDO = base * (light + flashlight(v_wpos, v_wn, CAMERA_POSITION_WORLD, 0.15)) + dither(FRAGCOORD.xy);
}
