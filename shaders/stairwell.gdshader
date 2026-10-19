// The stairwell shaft (Stairwell): painted concrete-block walls with a dado
// that follows the stairs, bare concrete slabs and steps with worn treads,
// lit by a bulkhead light over every landing and half landing. Self-lit like
// the rest of the Backrooms (no light nodes): Lambert from the lights with a
// short falloff, soft occlusion where walls meet floors and in the corners,
// plus the flashlight.
shader_type spatial;
render_mode unshaded;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

const int LAMPS = 10;
uniform vec3 lamps[10];            // stairwell-local light positions
uniform vec3 tint = vec3(1.0);
uniform float use_tint = 0.0;
uniform float ambient = 0.0;
// The shaft's plan (Stairwell constants): inner wall faces, landing and half
// landing edges, the wall between the flights, floor height.
uniform float w0 = 0.165;
uniform float sx = 7.2;
uniform float sz = 4.8;
uniform float land = 1.55;
uniform float mid = 5.535;
uniform float split = 2.4;
uniform float floor_h = 4.0;
instance uniform vec3 origin;      // where this stairwell stands

varying vec3 v_col;
varying float v_kind;              // COLOR.a: 1 wall, 0.6 concrete, 0.4 nosing, 0.2 fittings
varying vec3 v_wpos;
varying vec3 v_wn;

void vertex() {
	v_col = mix(COLOR.rgb, tint, use_tint);
	v_kind = use_tint > 0.5 ? 0.2 : COLOR.a;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

float h31(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

// Smooth value noise (no blocky steps).
float vnoise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(h31(i), h31(i + vec3(1, 0, 0)), f.x), mix(h31(i + vec3(0, 1, 0)), h31(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(h31(i + vec3(0, 0, 1)), h31(i + vec3(1, 0, 1)), f.x), mix(h31(i + vec3(0, 1, 1)), h31(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	return vnoise(p) * 0.5 + vnoise(p * 2.03) * 0.3 + vnoise(p * 4.1) * 0.2;
}

// Height of the stairs or landing under a point (shaft-local), relative to
// the storey: flight A (the door side) runs down from the landing to the
// half landing, flight B back down to the next landing.
float under(vec3 p) {
	float run = mid - land;
	float f = p.z < split
			? -clamp((p.x - land) / run, 0.0, 1.0) * floor_h * 0.5
			: -floor_h * 0.5 - clamp((mid - p.x) / run, 0.0, 1.0) * floor_h * 0.5;
	return f;
}

void fragment() {
	vec3 lp = v_wpos - origin;
	vec3 n = v_wn;
	// How high above the stairs or landing below this point is.
	float f = under(lp);
	float storey = floor((lp.y - f + 0.02) / floor_h);
	float h = lp.y - storey * floor_h - f;
	// Distance to the nearest outer wall (corners and edges get less light).
	float dw = min(min(lp.x - w0, sx - w0 - lp.x), min(lp.z - w0, sz - w0 - lp.z));
	float ds = abs(lp.z - split) - 0.07;          // the wall between the flights
	if (lp.x > land && lp.x < mid) {
		dw = min(dw, ds);
	}
	vec3 col = v_col;
	float k = v_kind;
	float grain = fbm(lp * 7.0);
	float blot = fbm(lp * 0.9 + 3.0);
	if (k > 0.9) {
		// Painted concrete block: 0.4 x 0.2 m in a running bond.
		vec2 uv = vec2(abs(n.x) > 0.5 ? lp.z : lp.x, lp.y);
		vec2 b = uv / vec2(0.4, 0.2);
		b.x += step(1.0, mod(floor(b.y), 2.0)) * 0.5;
		vec2 bf = fract(b);
		float joint = min(min(bf.x, 1.0 - bf.x) * 0.4, min(bf.y, 1.0 - bf.y) * 0.2);
		float fw = fwidth(uv.y) * 1.5;
		float mortar = 1.0 - smoothstep(0.003, 0.009 + fw, joint);
		bool lower = h < 1.05;
		vec3 paint = lower ? vec3(0.34, 0.37, 0.34) : vec3(0.64, 0.62, 0.57);
		col = paint * (0.93 + 0.1 * grain) * (0.97 + 0.06 * h31(floor(vec3(b, storey))));
		col *= 1.0 - mortar * 0.18;
		// The line along the top of the dado, following the stairs.
		col = mix(col, vec3(0.2, 0.22, 0.2), (1.0 - smoothstep(0.0, 0.02, abs(h - 1.05))) * 0.85);
		// Scuffs low down, a little grime where hands go.
		col *= 1.0 - smoothstep(0.62, 0.8, blot) * 0.12;
		col *= mix(0.86, 1.0, smoothstep(0.0, 0.25, h));
	} else if (k > 0.5) {
		// Concrete: slabs, steps, the soffits under the flights.
		col = vec3(0.47, 0.46, 0.44) * (0.82 + 0.3 * grain);
		col = mix(col, col * vec3(0.85, 0.83, 0.8), smoothstep(0.5, 0.75, blot) * 0.6);
		if (n.y > 0.5) {
			// Treads: worn paler and smoother down the walking line.
			float lane = lp.z < split ? (lp.z - w0) / (split - w0) : (lp.z - split) / (sz - w0 - split);
			float wear = exp(-pow((lane - 0.5) * 3.0, 2.0));
			col = mix(col, col * 1.12, wear * 0.5);
			col *= 0.92;
		}
	} else if (k > 0.3) {
		col = vec3(0.62, 0.52, 0.16) * (0.75 + 0.3 * grain);     // anti-slip nosing
	} else {
		col = v_col * (0.9 + 0.15 * grain);
	}
	// Ambient occlusion: walls darken where they meet the floor below,
	// floors darken along the walls, everything in the corners.
	float ao = 1.0;
	if (abs(n.y) < 0.5) {
		ao *= mix(0.55, 1.0, smoothstep(0.0, 0.5, h));
	} else if (n.y > 0.5) {
		ao *= mix(0.6, 1.0, smoothstep(0.0, 0.45, dw));
	} else {
		ao *= mix(0.7, 1.0, smoothstep(0.0, 0.6, dw));
	}
	ao *= mix(0.75, 1.0, smoothstep(0.0, 0.35, dw + step(0.5, abs(n.y))));
	vec3 light = vec3(0.012, 0.012, 0.011) + ambient;
	for (int i = 0; i < LAMPS; i++) {
		vec3 d = lamps[i] - lp;
		float dist = length(d);
		float att = max(1.0 - dist / 7.0, 0.0);
		att *= att;
		float ndl = max(dot(n, d / max(dist, 0.001)), 0.0);
		light += vec3(1.0, 0.9, 0.74) * 1.75 * att * (0.25 + 0.75 * ndl);
	}
	ALBEDO = col * (light * ao + flashlight(v_wpos, n, CAMERA_POSITION_WORLD, 0.15)) + dither(FRAGCOORD.xy);
}
