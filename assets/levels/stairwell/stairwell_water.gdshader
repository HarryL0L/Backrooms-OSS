// The water at the bottom of the Endless Stairwell: black, still but for a
// slow shiver, the one fixture still burning above it reflected in it
// (an analytic glint of `lamp_pos`, streaked by the ripples), the torch's
// beam on it (the shader flashlight, as the other surfaces); it lets
// nothing through. L.U.C.I.D. engine units, like stairwell_lit.
shader_type spatial;
render_mode cull_disabled, unshaded;
#include "res://shaders/common.gdshaderinc"

uniform vec3 lamp_pos = vec3(0.0);
uniform float lamp_on = 0.0;
uniform vec3 lamp_rgb = vec3(1.0);
// the lens, as seen in the water: its luminance (engine units) and size
uniform float lamp_emit = 20.2;

uniform vec3 deep = vec3(0.004, 0.0065, 0.006);

varying vec3 v_wpos;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 ripple_n(vec2 p, float t) {
	vec2 g = vec2(0.0);
	g += vec2(0.8, 0.3) * cos(dot(p, vec2(5.1, 1.9)) + t * 0.9) * 0.016;
	g += vec2(-0.4, 0.9) * cos(dot(p, vec2(-2.3, 6.7)) - t * 1.3) * 0.012;
	g += vec2(0.6, -0.7) * cos(dot(p, vec2(9.0, -7.5)) + t * 1.9) * 0.007;
	g += vec2(0.2, 1.0) * cos(dot(p, vec2(17.0, 11.0)) - t * 2.6) * 0.004;
	return normalize(vec3(-g.x, 1.0, -g.y));
}

void fragment() {
	vec3 n = ripple_n(v_wpos.xz, TIME);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float fres = 0.02 + 0.98 * pow(1.0 - max(dot(n, v), 0.0), 5.0);
	// the lamp's glint: the reflected view ray against the lens (a 0.66 x
	// 0.15 m wall fixture facing +z at lamp_pos), its luminance times Fresnel
	vec3 r = reflect(-v, n);
	vec3 tl = lamp_pos - v_wpos;
	float d = length(tl);
	float glint = 0.0;
	if (r.z > 0.001) {
		float t = (lamp_pos.z - v_wpos.z) / r.z;
		vec2 q = abs((v_wpos + r * t).xy - lamp_pos.xy);
		glint = (1.0 - smoothstep(0.29, 0.36, q.x)) * (1.0 - smoothstep(0.05, 0.1, q.y));
	}
	float ca = dot(r, tl / max(d, 0.001));
	float halo = pow(max(ca, 0.0), 120.0) * 0.06;
	vec3 refl = lamp_rgb * lamp_on * lamp_emit * (glint + halo) * fres;
	// what it lets through of the lamp's light (it is black and deep)
	vec3 lit = deep * lamp_rgb * lamp_on * 0.6 / max(d * d * 0.15, 0.3);
	// the torch: a little into the black, its hot spot mirrored (the
	// reflected ray against the beam: a glint where it would bounce to you)
	vec3 fl = flashlight(v_wpos, n, CAMERA_POSITION_WORLD, 0.0) * 0.04;
	vec3 tf = flash_pos - v_wpos;
	float df = length(tf);
	float cf = dot(r, tf / max(df, 0.001));
	float beam = smoothstep(flash_params.z, flash_params.w, dot(-tf / max(df, 0.001), flash_dir));
	vec3 fspec = flash_params.x > 0.5 ? lucid_flash.rgb * beam * pow(max(cf, 0.0), 60.0) * fres * 6.0 / max(df * df, 0.3) : vec3(0.0);
	// the shaft's dim walls in it, broken by the ripples
	vec3 env = lamp_rgb * lamp_on * 0.16 * fres * (0.75 + 10.0 * (n.x + n.z));
	vec3 col = lit + refl + fl + fspec + env;
	ALBEDO = col + vec3(dither(FRAGCOORD.xy));
}
