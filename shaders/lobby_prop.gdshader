// Bins and buckets in the Lobby (LobbyDetails). Self-lit like the rest of
// the Backrooms: instance colour = surface colour x light where it stands,
// shaded a little by which way the surface faces, plus the flashlight.
// INSTANCE_CUSTOM.r = half the height (both are open at the top, dark inside).
shader_type spatial;
render_mode unshaded;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

instance uniform vec4 tint_light = vec4(0.0);   // single props: colour x light (a > 0: use it)
instance uniform float cloth = 0.0;             // dust sheets: softer folds, darker underneath

varying vec3 v_col;
varying vec3 v_wpos;
varying vec3 v_wn;
varying float v_half;
varying vec3 v_local;
varying vec3 v_ln;

void vertex() {
	v_col = tint_light.a > 0.0 ? tint_light.rgb : COLOR.rgb;
	v_half = INSTANCE_CUSTOM.r;
	v_local = VERTEX;
	v_ln = NORMAL;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	float shade = 0.62 + 0.38 * clamp(v_wn.y * 0.5 + 0.5, 0.0, 1.0);
	if (cloth > 0.5) {
		// Light from the tubes above: tops bright, sides falling off to
		// shadow where the sheet tucks under; long soft folds hanging down.
		shade = 0.28 + 0.72 * pow(clamp(v_wn.y * 0.5 + 0.5, 0.0, 1.0), 1.6);
		float folds = sin(v_wpos.x * 7.0 + sin(v_wpos.z * 2.3) * 2.0) * sin(v_wpos.z * 5.0 + v_wpos.x * 1.7);
		shade *= 0.9 + 0.1 * folds * (1.0 - abs(v_wn.y));
	}
	vec3 base = v_col * shade;
	if (v_half > 0.0 && v_ln.y > 0.9) {
		// Looking in: a thin rim, dark inside.
		base *= 0.28;
	} else if (v_half > 0.0) {
		// Moulded ribs around the side, a lip at the top.
		float ang = atan(v_local.z, v_local.x);
		base *= 0.93 + 0.07 * smoothstep(0.3, 0.9, abs(sin(ang * 8.0)));
		base *= v_local.y > v_half - 0.035 ? 1.12 : 1.0;
	}
	// A darker band near the floor (scuffs).
	base *= mix(0.8, 1.0, smoothstep(0.0, 0.08, v_wpos.y));
	ALBEDO = base + base * flashlight(v_wpos, v_wn, CAMERA_POSITION_WORLD, 0.2) * 2.0 + dither(FRAGCOORD.xy);
}
