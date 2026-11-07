// L.U.C.I.D. stage 3: distant lights as point sources (a MultiMesh of
// quads): street lamp heads by the thousand, aircraft warning lights,
// traffic signals down the avenues. Each sprite carries its source's real
// intensity I (cd) and spreads it over a camera-facing gaussian disc no
// smaller than about a pixel, with peak luminance I / (pi r^2 / 4), so what
// lands on the sensor is the source's real flux at that distance whatever
// the resolution: far lamps fade by the inverse square law and the air
// (lucid_finish), near ones clip and bloom like real ones.
// Instance colour (COLOR): rgb at luminance 1. INSTANCE_CUSTOM: x intensity (cd),
// y kind + phase (0 steady, 1 aircraft beacon flashing 40/min, 2-4 signal
// red / yellow / green facing the avenue, 5-7 facing the street, 9 a
// street lamp: I = I0 (cos^1.2 of the angle from straight down + the
// phase x 0.2 of light its housing and lens scatter sideways: ~2 % for a
// flat LED lens, ~12 % for a sodium drop lens; seen from above only that),
// z physical radius (m), w distance (m) under which the sprite gives way
// to the lamp's own lens geometry (0 never).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/lucid_city.gdshaderinc"

uniform float cycle = 60.0;          // signal cycle (s)
uniform float clock = 0.0;           // the level's signal clock (s), so near and far heads agree

// The lens's veiling glare: GLARE of the light reaching the camera is
// scattered into a halo round the source, profile 1 / (1 + (theta /
// THETA0)^2)^1.5 (its integral over the image plane is 2 pi THETA0^2), so
// bright lamps get the soft halo they have in photos, with the energy it
// really carries (phone lenses scatter a few percent).
const float GLARE = 0.03;
const float THETA0 = 0.004;

varying float v_l;
varying float v_rc;
varying float v_tail;
varying float v_rt;
varying vec3 v_col;
varying float v_d;

float signal_on(float kind, float s) {
	if (kind < 1.5) {
		return 1.0;
	}
	if (kind < 4.5) {
		// Facing the avenue: green 0-30 s, yellow 30-34, red after.
		float st = s < 30.0 ? 4.0 : (s < 34.0 ? 3.0 : 2.0);
		return step(abs(st - kind), 0.1);
	}
	// Facing the street: red until 36 s, green 36-56, yellow 56-60.
	float st2 = s < 36.0 ? 5.0 : (s < 56.0 ? 7.0 : 6.0);
	return step(abs(st2 - kind), 0.1);
}

void vertex() {
	vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(c, cam);
	float mpp = 2.0 * d / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float rc = max(INSTANCE_CUSTOM.z, mpp * 0.9);
	float kind = floor(INSTANCE_CUSTOM.y);
	float phase = fract(INSTANCE_CUSTOM.y);
	float on = 1.0;
	if (kind > 0.5 && kind < 1.5) {
		// Medium-intensity beacon: a 0.5 s flash every 1.5 s, with a short rise.
		float t = fract(TIME / 1.5 + phase) * 1.5;
		on = smoothstep(0.0, 0.08, t) * (1.0 - smoothstep(0.42, 0.55, t));
	} else if (kind > 1.5 && kind < 7.5) {
		on = signal_on(kind, fract(clock / cycle + phase) * cycle);
	} else if (kind > 8.5) {
		float cd = max((c.y - cam.y) / max(d, 0.01), 0.0);
		on = pow(cd, 1.2) + phase * 0.2;
	}
	float i = INSTANCE_CUSTOM.x * on;
	if (kind < 0.5 || kind > 8.5) {
		i *= lucid_sky.z;
	}
	float fade = INSTANCE_CUSTOM.w > 0.0 ? smoothstep(INSTANCE_CUSTOM.w, INSTANCE_CUSTOM.w * 1.6, d) : 1.0;
	// Air between: Koschmieder's transmittance (no airlight on a sprite).
	float tr = exp(-lucid_air.a * d);
	float e_cam = i * tr / max(d * d, 1.0);
	float tail = GLARE * e_cam / (6.2831853 * THETA0 * THETA0) / LUCID_UNIT_NITS;
	float r = rc;
	if (tail * lucid_exposure.g > 0.03) {
		r = max(rc, THETA0 * 14.0 * d);
	}
	vec3 right = INV_VIEW_MATRIX[0].xyz;
	vec3 up = INV_VIEW_MATRIX[1].xyz;
	vec3 wp = c + (right * VERTEX.x + up * VERTEX.y) * 2.0 * r;
	POSITION = PROJECTION_MATRIX * VIEW_MATRIX * vec4(wp, 1.0);
	v_l = (1.0 - GLARE) * i * tr * fade / (rc * rc * 0.7853982) / LUCID_UNIT_NITS;
	v_rc = rc / r;
	v_tail = r > rc ? tail : 0.0;
	v_rt = r / d / THETA0;
	v_col = COLOR.rgb;
	v_d = d;
	UV = VERTEX.xy * 2.0;
}

void fragment() {
	float q = length(UV);
	float qc = q / v_rc;
	float k = q * v_rt;
	float h = 1.0 + k * k;
	float l = v_l * exp(-4.0 * qc * qc) + v_tail / (h * sqrt(h)) * (1.0 - smoothstep(0.75, 1.0, q));
	// Not in reflection probes: a point source is a single huge texel there,
	// and the lamps' reflections are analytic (lucid_street).
	ALBEDO = lucid_capturing(PROJECTION_MATRIX) > 0.5 ? vec3(0.0) : lucid_mesopic(v_col * l) * lucid_exposure.rgb;
}
