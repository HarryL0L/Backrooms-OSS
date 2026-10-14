// Renders the Field's clouds ONCE into a panorama (azimuth x elevation band)
// by raymarching a few big cumulus volumes, lit by the sun with self-shadow.
// Far too heavy to run every frame on a phone; as a one-off bake it's cheap,
// and the sky shader then only does a texture lookup.
shader_type canvas_item;
render_mode unshaded, blend_disabled;
#include "res://shaders/field_common.gdshaderinc"

uniform vec3 sun_dir = vec3(-0.42, 0.68, 0.6);
uniform vec3 horizon_color = vec3(0.42, 0.58, 0.82);
// The bake runs in vertical strips (one per frame) so no single GPU pass is
// long: UV.x spans one strip, starting at strip_u0 with width strip_du.
uniform float strip_u0 = 0.0;
uniform float strip_du = 1.0;

const int NC = 9;
// x, z of the base centre (m), width radius (m), height (m)
const vec4 CL[9] = vec4[](
	vec4(0.0, -15000.0, 5600.0, 9000.0),      // the giant tower ahead, far away
	vec4(-7500.0, -17500.0, 3600.0, 2600.0),  // its foothills
	vec4(7800.0, -16500.0, 3900.0, 3000.0),
	vec4(-7600.0, -6500.0, 1700.0, 1300.0),
	vec4(8200.0, -5600.0, 1600.0, 1200.0),
	vec4(-9500.0, 3500.0, 1900.0, 1500.0),
	vec4(9000.0, 6000.0, 2100.0, 1900.0),
	vec4(1500.0, 11000.0, 2600.0, 2100.0),
	vec4(-4500.0, 10500.0, 1500.0, 1100.0)
);
const float BASE[9] = float[](700.0, 650.0, 700.0, 800.0, 900.0, 780.0, 820.0, 760.0, 900.0);

float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.zyx + 31.32);
	return fract((p.x + p.y) * p.z);
}

float vnoise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash13(i), hash13(i + vec3(1, 0, 0)), f.x),
			mix(hash13(i + vec3(0, 1, 0)), hash13(i + vec3(1, 1, 0)), f.x), f.y),
			mix(mix(hash13(i + vec3(0, 0, 1)), hash13(i + vec3(1, 0, 1)), f.x),
			mix(hash13(i + vec3(0, 1, 1)), hash13(i + vec3(1, 1, 1)), f.x), f.y), f.z);
}

float fbm(vec3 p) {
	float s = 0.0;
	float a = 0.5;
	for (int o = 0; o < 4; o++) {
		s += a * vnoise(p);
		p = p * 2.07 + vec3(1.7, 9.2, 3.1);
		a *= 0.5;
	}
	return s;
}

float h11(float x) {
	return fract(sin(x * 127.1) * 43758.5453);
}

// A cumulus is a union of overlapping lumps (a wide base plus towers stacked
// on it), with billowing noise eating into the surface. Flat base.
float density(int i, vec3 p) {
	vec4 c = CL[i];
	vec3 q = p - vec3(c.x, BASE[i], c.y);
	float y = q.y / c.w;
	if (y < 0.0 || y > 1.15) {
		return 0.0;
	}
	vec3 qs = vec3(q.x / c.z, q.y / c.w, q.z / c.z);    // cloud-relative space
	// Base lump, squashed vertically.
	float d = 0.95 - length(vec3(qs.x, (qs.y - 0.18) * 1.6, qs.z));
	// Towers: random lumps rising toward the top.
	float fi = float(i) * 13.7;
	for (int k = 0; k < 5; k++) {
		float fk = float(k) + fi;
		float ly = 0.3 + 0.62 * h11(fk + 0.3) * (1.0 - 0.15 * float(k));
		vec3 lc = vec3((h11(fk + 1.1) - 0.5) * 0.9 * (1.0 - ly), ly, (h11(fk + 2.3) - 0.5) * 0.9 * (1.0 - ly));
		float lr = 0.32 + 0.28 * h11(fk + 3.7) * (1.0 - ly * 0.5);
		d = max(d, lr - length(vec3(qs.x - lc.x, (qs.y - lc.y) * (c.w / c.z), qs.z - lc.z)));
	}
	// Cauliflower billows at two scales: large rounded bulges, then fine curls.
	vec3 pp = p / (c.z * 0.16) + fi;
	float n1 = fbm(pp);
	float n2 = vnoise(pp * 3.7 + 5.0);
	float dens = d * 3.0 + (n1 - 0.47) * 1.6 + (n2 - 0.5) * 0.35;
	dens *= smoothstep(0.0, 0.025, y);
	return clamp(dens * 5.0, 0.0, 1.0);
}

vec2 sphere(vec3 ro, vec3 rd, vec3 c, float r) {
	vec3 oc = ro - c;
	float b = dot(oc, rd);
	float h = b * b - dot(oc, oc) + r * r;
	if (h < 0.0) {
		return vec2(-1.0);
	}
	h = sqrt(h);
	return vec2(-b - h, -b + h);
}

void fragment() {
	float az = (strip_u0 + UV.x * strip_du - 0.5) * 6.2831853;
	float el = mix(CLOUD_EL_MAX, CLOUD_EL_MIN, UV.y);
	vec3 rd = vec3(cos(el) * sin(az), sin(el), -cos(el) * cos(az));
	vec3 ro = vec3(0.0, 2.0, 0.0);
	vec3 sd = normalize(sun_dir);
	float mu = dot(rd, sd);
	// Henyey-Greenstein mix: bright silver lining toward the sun, soft elsewhere.
	float g1 = 0.55;
	float g2 = -0.2;
	float hg1 = (1.0 - g1 * g1) / pow(1.0 + g1 * g1 - 2.0 * g1 * mu, 1.5);
	float hg2 = (1.0 - g2 * g2) / pow(1.0 + g2 * g2 - 2.0 * g2 * mu, 1.5);
	float phase = mix(hg2, hg1, 0.3) * 0.0796;
	vec3 sun_col = vec3(1.0, 0.97, 0.92) * 6.5;

	float t0s[NC];
	vec2 hit[NC];
	for (int i = 0; i < NC; i++) {
		vec4 c = CL[i];
		hit[i] = sphere(ro, rd, vec3(c.x, BASE[i] + c.w * 0.5, c.y), max(c.z, c.w * 0.6) * 1.2);
		t0s[i] = hit[i].y > 0.0 ? max(hit[i].x, 0.0) : 1e9;
	}
	vec3 L = vec3(0.0);
	float T = 1.0;
	for (int k = 0; k < NC; k++) {
		// Nearest cloud not yet marched (front-to-back compositing).
		int best = -1;
		float bt = 1e8;
		for (int i = 0; i < NC; i++) {
			if (t0s[i] < bt) {
				bt = t0s[i];
				best = i;
			}
		}
		if (best < 0 || T < 0.01) {
			break;
		}
		t0s[best] = 1e9;
		vec4 c = CL[best];
		float ta = max(hit[best].x, 0.0);
		float tb = hit[best].y;
		const int STEPS = 56;
		float dt = (tb - ta) / float(STEPS);
		float sigma = 0.0035;
		for (int s = 0; s < STEPS; s++) {
			float t = ta + (float(s) + 0.5) * dt;
			vec3 p = ro + rd * t;
			float dens = density(best, p);
			if (dens <= 0.001) {
				continue;
			}
			// Light reaching this point from the sun (self-shadowing).
			float od = 0.0;
			float ls = c.z * 0.14;
			for (int j = 1; j <= 4; j++) {
				od += density(best, p + sd * ls * float(j)) * ls;
			}
			float sun_t = exp(-od * sigma * 1.6);
			float powder = 1.0 - exp(-dens * 2.0);
			float hgt = clamp((p.y - BASE[best]) / c.w, 0.0, 1.0);
			vec3 amb = mix(vec3(0.22, 0.29, 0.42), vec3(0.62, 0.68, 0.80), hgt) * 1.15;
			vec3 scat = sun_col * sun_t * phase * mix(0.6, 1.0, powder) * 6.0 + amb;
			float a = 1.0 - exp(-dens * sigma * dt);
			L += T * a * scat;
			T *= 1.0 - a;
			if (T < 0.01) {
				break;
			}
		}
		// Aerial perspective: far clouds fade toward the horizon colour.
		float haze = 1.0 - exp(-bt / 30000.0);
		L = mix(L, horizon_color * (1.0 - T), haze);
	}
	COLOR = vec4(L, 1.0 - T);
}
