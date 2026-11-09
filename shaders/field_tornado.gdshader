// The Field's tornado (FieldStorm): its condensation funnel (part 0) and
// the debris cloud whirling round its foot (part 1), each one strip of
// camera-facing quads bent along its axis (VERTEX.x: the side, -1 / 1;
// VERTEX.y: up the axis, 0 .. 1). Drawn as what a cylinder of cloud
// droplets (or dust) looks like: its optical depth along the chord through
// it, so the middle is dense and the edges thin and ragged; its texture
// turns round the axis (the condensation bands sliding across), rises a
// little, twists. A cone tapering from the wall cloud, or a rope bending in
// the wind as it dies. Lit by the storm's shade, the bright air behind it
// showing through and round its thin edges; seen through the haze and the
// rain between (field_air, per vertex): kilometres off it is soft and grey.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/field_common.gdshaderinc"
#include "res://shaders/field_storm.gdshaderinc"

uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int part = 0;
uniform vec3 foot = vec3(0.0);     // the ground under it (world)
uniform float top_h = 700.0;       // the wall cloud's foot over it (m)
uniform float r_top = 300.0;       // the funnel's radius there (m)
uniform float r_bot = 80.0;        // ... at the ground
uniform float shape = 1.6;         // how it tapers (higher: thin until near the top)
uniform float bend = 25.0;         // sideways bow (m)
uniform float bend_ph = 0.0;
uniform vec2 tilt = vec2(100.0, 0.0);  // the top's offset from the foot (m)
uniform float cond = 0.05;         // the condensation ends this far up (0 .. 1)
uniform float spin = 0.0;          // how far it has turned (rad)
uniform float presence = 1.0;
uniform float debris_r = 220.0;
uniform float debris_h = 180.0;

varying float v_x;
varying float v_v;
varying float v_w;
varying float v_h;
varying vec4 v_air;
varying vec3 v_shade;
varying vec3 v_back;

vec3 axis_at(float v) {
	if (part == 1) {
		return foot + vec3(0.0, v * debris_h - 12.0, 0.0);
	}
	vec2 td = length(tilt) > 1.0 ? normalize(tilt) : vec2(1.0, 0.0);
	vec2 bd = vec2(-td.y, td.x);
	vec2 off = tilt * pow(v, 1.4)
			+ bd * bend * sin(3.14159 * v) * sin(bend_ph + v * 2.2)
			+ td * bend * 0.45 * sin(6.2832 * v + bend_ph * 1.3) * v * (1.0 - v) * 4.0;
	return foot + vec3(off.x, v * top_h, off.y);
}

float width_at(float v) {
	if (part == 1) {
		return debris_r * (0.5 + 0.65 * sqrt(v)) * (1.0 - 0.35 * v * v);
	}
	// Flaring into the wall cloud at its top.
	return r_bot + (r_top - r_bot) * pow(v, shape) + r_top * 0.7 * smoothstep(0.86, 1.0, v);
}

void vertex() {
	vec3 cam = CAMERA_POSITION_WORLD;
	float sx = VERTEX.x;
	float v = VERTEX.y;
	vec3 a = axis_at(v);
	vec3 tg = normalize(axis_at(min(v + 0.01, 1.0)) - axis_at(max(v - 0.01, 0.0)));
	vec3 to_cam = normalize(cam - a);
	vec3 side = normalize(cross(tg, to_cam));
	float w = width_at(v);
	VERTEX = a + side * sx * w * 1.3;
	v_x = sx * 1.3;
	v_v = v;
	v_w = w;
	v_h = part == 1 ? debris_h : top_h;
	vec3 dir = -to_cam;
	float d = distance(a, cam);
	v_air = field_air(cam, dir, d, 6);
	v_shade = field_shade_at(a.xz);
	// What is behind it: the air beyond, lit by the sun where it reaches.
	vec2 far = a.xz + normalize(dir.xz) * 9000.0;
	v_back = field_shade_at(far) + field_sunair.rgb * field_phase(dot(dir, field_sun.xyz)) * field_lit(far, 0.0) * 0.5;
}

void fragment() {
	float x = v_x;
	float ax = abs(x);
	float chord = sqrt(max(1.0 - x * x, 0.0));
	float u = asin(clamp(x, -1.0, 1.0));
	float circ = part == 1 ? 2.0 : 3.0;
	float s = (u + spin * (part == 1 ? 0.7 : 1.0)) / 6.2832 * circ;
	float hy = v_v * v_h;
	// Bands sliding round it, rising and twisting a little.
	float n1 = texture(noise, vec2(s + hy * 0.0009, hy / 520.0 - spin * 0.015)).r;
	float n2 = texture(noise, vec2(s * 3.1 + 0.37, hy / 150.0 - spin * 0.03)).r;
	float dens = 0.45 + 0.95 * n1 + 0.35 * (n2 - 0.5);
	float edge = 1.0 + 0.2 * (n2 - 0.5) + 0.14 * (n1 - 0.5);
	float body = 1.0 - smoothstep(edge - 0.22, edge, ax);
	float tau = dens * chord * v_w * (part == 1 ? 0.016 : 0.022);
	float alpha = (1.0 - exp(-tau)) * body;
	vec3 l;
	if (part == 0) {
		// The condensation reaches down to cond (ragged), and merges into
		// the wall cloud at its top.
		alpha *= smoothstep(cond - 0.03, cond + 0.09, v_v + (n1 - 0.5) * 0.08);
		alpha *= 1.0 - 0.3 * smoothstep(0.9, 1.0, v_v);
		// Droplets lit by the storm's shade, darker in the dense middle; the
		// bright air behind glows through the thin edges. Lower down it takes
		// the dust's colour.
		vec3 c = v_shade * (0.42 + 0.3 * n1) * (1.0 - 0.35 * chord) * mix(1.0, 0.6, smoothstep(0.7, 1.0, v_v));
		c += v_back * 0.35 * (1.0 - chord) * exp(-tau * 0.5);
		vec3 dust = vec3(0.82, 0.72, 0.6);
		l = mix(c, c * dust, 1.0 - smoothstep(0.0, 0.3, v_v));
	} else {
		alpha *= (1.0 - smoothstep(0.45, 1.0, v_v + (n1 - 0.5) * 0.45)) * smoothstep(0.0, 0.06, v_v);
		l = v_shade * vec3(0.7, 0.6, 0.48) * (0.55 + 0.5 * n1);
	}
	alpha *= presence;
	ALBEDO = (l * v_air.a + v_air.rgb) * lucid_exposure.rgb;
	ALPHA = clamp(alpha, 0.0, 1.0);
}
