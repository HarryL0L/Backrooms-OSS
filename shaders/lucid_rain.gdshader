// L.U.C.I.D.: falling rain (LucidRain, docs/LUCID.md "Rain"). One mesh of
// quads, one draw: streaks, splashes and drips, all placed here from their
// seeds (no CPU work per drop).
//   VERTEX.xy: the corner (x -1 / 1 across, y 0 the drop .. 1 its trail),
//   VERTEX.z: the kind (0 a falling drop, 1 a splash, 2 a drip, 3 a falling
//   drop near a light), UV, UV2:
//   four seeds.
// Falling drops live in a box round the camera, anchored in the world and
// wrapped (they keep their places as you walk through them), and in boxes
// under the four nearest lights, where they are bright enough to see from
// farther off (the same density: each drawn drop stands for more there). Sizes follow
// Marshall-Palmer above 0.5 mm, fall speeds Gunn-Kinzer (Atlas' fit); each
// drop is drawn as what the camera records in its exposure time: a streak
// v t long (the camera's own motion subtracted), of the drop's width or a
// pixel's, whichever is wider, and as opaque as the drop covers it: the
// share of the exposure it spends on each point times the share of the
// width it fills (D^2 / (length x width)), times how many real drops each
// drawn one stands for. What it shows is what it scatters toward the eye:
// the nearest street heads, bulbs and the lit signals (I cos^m / d^2 times
// the drop's phase function: mostly forward, a little backward), plus the
// surround it refracts. So drops glow in front of and under the lamps and
// are gone against the dark. Splashes: crowns at random spots near the
// camera, there for 60 ms of the exposure. Drips: drops that grow at real
// edges, fall (with air drag) and splash.
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/lucid_city.gdshaderinc"

uniform float lambda = 2.8;               // Marshall-Palmer slope (1/mm) at the rain rate
uniform float drops_per = 270.0;          // real drops (0.5 mm and up) per drawn streak
uniform float shutter = 0.125;            // the camera's exposure time (s)
uniform vec3 cam_vel = vec3(0.0);         // the camera's velocity (m/s, world)
uniform float pix = 0.003;                // a pixel's size at 1 m in the middle of the view (m)
uniform vec3 wind = vec3(1.0, 0.0, 0.4);  // m/s
uniform vec3 box = vec3(14.0, 8.0, 14.0); // the falling drops' volume (m)
uniform float box_lift = 1.5;             // its centre over the camera
uniform vec3 lamp_box = vec3(8.0, 10.0, 8.0);   // more drops round each of the four nearest lights
uniform float lamp_per = 1000.0;          // real drops per drawn one there
uniform float splash_r = 6.0;             // splashes within this of the camera
uniform float splash_k = 8.0;             // real splashes per drawn one
uniform vec3 origin = vec3(0.0);          // the level's origin (world)
uniform vec4 roof = vec4(15.0, 10.0, 45.0, 40.0);   // the roof you can walk on (level x0, z0, x1, z1)
uniform float roof_y = 19.5;
uniform vec4 cover[4];                    // sheltered: x0, z0, x1, z1 (world)
uniform vec4 cover_top = vec4(-1e6);      // under these heights (world)
uniform vec4 lamp_p[8];                   // lights: position (world), w: cos exponent (< 0: all round)
uniform vec4 lamp_i[8];                   // rgb: peak intensity (engine units of E / pi at 1 m), a: its drops' share (< 0: none)
uniform vec4 sig_p[8];                    // lit signal lenses (world)
uniform vec4 sig_i[8];                    // their intensity (engine units of E / pi at 1 m)
uniform vec4 sig_d[8];                    // their axes
uniform vec3 env = vec3(0.0);             // the surround a drop refracts (engine radiance)
uniform vec4 drip_a[12];                  // drip edges: from (world), w: how far they fall
uniform vec4 drip_b[12];                  // to (world), w: > 0 a ring of this radius round drip_a
uniform int drip_n = 0;
uniform float amount = 1.0;               // 0 off .. 1
// Not from the physics, kept for tuning (1: as the physics gives).
uniform float visibility = 1.0;

varying vec3 v_rad;
varying float v_a;
varying vec2 v_uv;
varying float v_cap;
varying float v_kind;

const float G = 9.81;

float hg(float g, float c) {
	return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5);
}

// A raindrop's phase function (normalised to 1 over the sphere, so x 1/4
// with I / d^2 gives its radiance): geometric optics for a water sphere
// sends most light on forward through it (refraction) and a little back
// (reflection, the bows): two Henyey-Greenstein lobes, g 0.85 and -0.3.
float drop_phase(float c) {
	return 0.88 * hg(0.85, c) + 0.12 * hg(-0.3, c);
}

// What a drop at p sends toward the eye (engine radiance): the lights
// (L = I f(theta) / d^2 x phase / 4) and the surround.
vec3 drop_light(vec3 p, vec3 to_eye) {
	// The surround: a drop shows, turned over, what lies behind it over
	// a wide cone (Garg & Nayar 2004): looking up, the sky; level, the lit
	// street and walls as much as the sky; looking down, the street.
	float up = clamp(0.3 - to_eye.y * 1.5, 0.0, 1.0);
	vec3 l = mix(env, lucid_sky_now(-to_eye), up);
	for (int i = 0; i < 8; i++) {
		if (lamp_i[i].a < 0.0) {
			continue;
		}
		vec3 d = p - lamp_p[i].xyz;
		float r2 = max(dot(d, d), 0.04);
		vec3 dn = d * inversesqrt(r2);
		// A street head looks down (I0 cos^m from the nadir); a bulb shines all round.
		float f = lamp_p[i].w < 0.0 ? 1.0 : pow(max(-dn.y, 0.0), lamp_p[i].w);
		l += lamp_i[i].rgb * (f / r2 * drop_phase(dot(dn, to_eye)) * 0.25);
	}
	for (int i = 0; i < 8; i++) {
		if (sig_i[i].a <= 0.0) {
			continue;
		}
		vec3 d = p - sig_p[i].xyz;
		float r2 = max(dot(d, d), 0.04);
		vec3 dn = d * inversesqrt(r2);
		// A signal's beam: about +-15 degrees round its axis.
		float b = max(dot(dn, sig_d[i].xyz), 0.0);
		b *= b;
		b *= b;
		b *= b;
		l += sig_i[i].rgb * (b * b / r2 * drop_phase(dot(dn, to_eye)) * 0.25);
	}
	return l;
}

float ground_at(vec2 xz) {
	vec2 q = xz - origin.xz;
	if (q.x > roof.x && q.x < roof.z && q.y > roof.y && q.y < roof.w) {
		return origin.y + roof_y;
	}
	float ax = abs(q.x - round(q.x / 110.0) * 110.0);
	float az = abs(q.y - round(q.y / 80.0) * 80.0);
	return origin.y + (ax < 9.5 || az < 6.0 ? 0.0 : 0.15);
}

// The top of the shelter over p (or -1e6).
float cover_at(vec3 p) {
	float top = -1e6;
	for (int i = 0; i < 4; i++) {
		if (p.x > cover[i].x && p.x < cover[i].z && p.z > cover[i].y && p.z < cover[i].w && p.y < cover_top[i]) {
			top = max(top, cover_top[i]);
		}
	}
	return top;
}

void vertex() {
	float kind = VERTEX.z;
	vec2 corner = VERTEX.xy;
	vec4 s = vec4(UV, UV2);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 head = cam;
	vec3 tail = cam;
	float dm = 0.001;
	float a = 0.0;
	if (kind < 0.5 || kind > 2.5) {
		// A falling drop: D from Marshall-Palmer above 0.5 mm, its terminal
		// velocity (Atlas et al. 1973's fit to Gunn & Kinzer 1949).
		float dmm = min(0.5 - log(1.0 - s.w * 0.999) / lambda, 4.5);
		float vt = max(9.65 - 10.3 * exp(-0.6 * dmm), 1.0);
		vec3 vel = vec3(0.0, -vt, 0.0) + wind * (0.8 + 0.4 * s.z);
		vec3 c = cam + vec3(0.0, box_lift, 0.0);
		vec3 bx = box;
		int li = 0;
		if (kind > 2.5) {
			// Round one of the four nearest lights (where drops shine).
			li = min(int(s.z * 4.0), 3);
			c = lamp_p[li].xyz + vec3(0.0, -lamp_box.y * 0.5 + 1.0, 0.0);
			bx = lamp_box;
		}
		vec3 p = vec3(s.x, fract(s.y * 7.31 + s.z * 3.17), s.y) * bx * 7.0 + vel * TIME;
		vec3 rel = p - c;
		rel -= bx * floor(rel / bx + 0.5);
		head = c + rel;
		tail = head - (vel - cam_vel) * shutter;
		dm = dmm * 0.001;
		// Thinned toward the box's walls, so nothing pops in or out.
		vec3 e = abs(rel) / (bx * 0.5);
		a = (1.0 - smoothstep(0.7, 1.0, max(e.x, e.z))) * (1.0 - smoothstep(0.75, 1.0, e.y));
		vec3 ec = abs(head - cam - vec3(0.0, box_lift, 0.0)) / (box * 0.5);
		float in_cam = (1.0 - smoothstep(0.7, 1.0, max(ec.x, ec.z))) * (1.0 - smoothstep(0.75, 1.0, ec.y));
		// (A light's drops make up what the camera's box leaves out.)
		a = kind > 2.5 ? a * (1.0 - in_cam) * lamp_per * step(0.0, lamp_p[li].w) * max(lamp_i[li].a, 0.0) : a * drops_per;
		// Not under a shelter: the drop ends on its roof.
		float top = cover_at(head);
		if (top > -1e5) {
			head.y = top;
			tail.y = max(tail.y, top);
			a *= step(0.01, tail.y - head.y);
		}
	} else if (kind < 1.5) {
		// A splash: a crown where a drop lands, at a new spot each cycle.
		float per = mix(0.25, 0.6, s.z);
		float ph = TIME / per + s.w * 17.0;
		float cyc = floor(ph);
		float life = fract(ph) * per;
		float rr = splash_r * sqrt(lucid_hash(vec2(cyc, s.x * 97.0)));
		float an = lucid_hash(vec2(s.y * 53.0, cyc)) * TAU;
		vec2 xz = cam.xz + vec2(cos(an), sin(an)) * rr;
		head = vec3(xz.x, ground_at(xz), xz.y);
		float sz = mix(0.03, 0.06, s.x);
		tail = head + vec3(0.0, sz * 0.7, 0.0);
		dm = sz;
		// There for 60 ms (of a longer exposure: that share of it).
		a = splash_k * step(life, 0.06) * min(0.06 / shutter, 1.0) * step(cover_at(head + vec3(0.0, 0.05, 0.0)), -1e5);
	} else if (drip_n > 0) {
		// A drip: grows on its edge for 0.4 s, falls with air drag (a 4.5 mm
		// drop: 9 m/s terminal), splashes.
		int i = min(int(s.z * float(drip_n)), drip_n - 1);
		vec4 da = drip_a[i];
		vec4 db = drip_b[i];
		const float VT = 9.0;
		float t_land = VT / G * acosh(exp(min(da.w * G / (VT * VT), 20.0)));
		float per = 0.4 + t_land + 0.1 + mix(0.2, 1.4, s.w);
		float ph = TIME / per + s.x * 13.0;
		float cyc = floor(ph);
		float t = fract(ph) * per - 0.4;
		float u = lucid_hash(vec2(cyc, s.y * 71.0 + float(i)));
		vec3 src = db.w > 0.0 ? da.xyz + vec3(cos(u * TAU), 0.0, sin(u * TAU)) * db.w : mix(da.xyz, db.xyz, u);
		dm = 0.0045;
		a = 1.0;
		if (t < 0.0) {
			// Hanging, growing.
			head = src;
			tail = src;
			dm *= sqrt(clamp(t / 0.4 + 1.0, 0.05, 1.0));
		} else if (t < t_land) {
			float y = VT * VT / G * log(cosh(G * t / VT));
			float v = VT * tanh(G * t / VT);
			head = src - vec3(0.0, y, 0.0);
			tail = head + vec3(0.0, min(v * shutter, y), 0.0) + cam_vel * shutter;
		} else if (t < t_land + 0.06) {
			head = src - vec3(0.0, da.w, 0.0);
			tail = head + vec3(0.0, 0.05, 0.0);
			dm = 0.05;
			kind = 1.0;
			a = min(0.06 / shutter, 1.0) * 3.0;
		} else {
			a = 0.0;
		}
	}
	// The quad: along the streak in view space, as wide as the drop or
	// 2.5 pixels (thinner, a streak breaks up into dots once scaled), whichever is wider, its ends capped by half that width.
	vec3 vh = (VIEW_MATRIX * vec4(head, 1.0)).xyz;
	vec3 vtl = (VIEW_MATRIX * vec4(tail, 1.0)).xyz;
	vec3 ax = vtl - vh;
	float len = length(ax);
	vec3 mid = mix(vh, vtl, corner.y);
	float z = max(-mid.z, 0.05);
	float wv = max(dm, 2.5 * z * pix);
	vec3 dir = len > 1e-5 ? ax / len : vec3(0.0, 1.0, 0.0);
	vec3 perp = cross(dir, normalize(mid));
	perp = dot(perp, perp) > 1e-8 ? normalize(perp) : vec3(1.0, 0.0, 0.0);
	vec3 pos = mid + perp * (corner.x * wv * 0.5) + dir * ((corner.y * 2.0 - 1.0) * wv * 0.5);
	POSITION = PROJECTION_MATRIX * vec4(pos, 1.0);
	// Coverage: D^2 spread over the streak's area (len + width) x width.
	// Out of focus (and too big) right at the lens: faded in from 0.3 m.
	a *= (kind > 0.5 && kind < 1.5 ? 0.25 : dm * dm / ((len + wv) * wv)) * smoothstep(0.3, 0.9, z) * amount;
	a *= (1.0 - lucid_capturing(PROJECTION_MATRIX)) * (kind > 0.5 && kind < 2.5 ? 1.0 : visibility);
	v_a = min(a, 0.5);
	v_uv = vec2(corner.x, corner.y);
	v_cap = wv / (len + wv);
	v_kind = kind;
	vec3 wmid = (INV_VIEW_MATRIX * vec4(mid, 1.0)).xyz;
	v_rad = v_a > 0.0 ? lucid_mesopic(drop_light(wmid, normalize(cam - wmid))) * lucid_exposure.rgb : vec3(0.0);
}

void fragment() {
	if (v_a <= 0.0) {
		discard;
	}
	float m;
	if (v_kind > 0.5 && v_kind < 1.5) {
		// A crown: its droplets thrown up and out round the rim.
		vec2 q = vec2(v_uv.x, v_uv.y);
		float rim = abs(abs(q.x) - 0.25 - 0.55 * q.y);
		m = (1.0 - smoothstep(0.0, 0.18, rim)) * (1.0 - q.y);
	} else {
		// Across: the drop's round profile; along: its ends rounded off.
		float x = v_uv.x;
		float e = max(v_cap * 0.5, 1e-3);
		m = max(1.0 - x * x, 0.0) * smoothstep(0.0, e, v_uv.y) * smoothstep(0.0, e, 1.0 - v_uv.y);
	}
	ALBEDO = v_rad;
	ALPHA = v_a * m;
}
