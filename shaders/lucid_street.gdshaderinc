// L.U.C.I.D. stage 4: the street after rain, shared by the baked city
// surfaces (lucid_surface.gdshaderinc) and the far ground
// (lucid_ground.gdshader), so the two agree where they meet: wetness and
// puddles, and the street heads' and signals' reflections found by
// arithmetic on the grid (LucidCity.GRID: avenue heads 10 m up at x =
// xc +- 7.6, z = 17.5 + 35 k; street heads 8 m up at 25, 55, 85 m into
// each block, z = zc +- 5.1). Needs lucid_city and lucid_spec.

uniform float wet = 0.0;                 // moisture after rain: 0 dry, 1 soaked (darker, smoother)
uniform float puddles = 0.0;             // how much water stands in the low spots (0 none)
uniform bool gutters = false;            // a road: water collects along the curbs (2 % crossfall)
uniform vec3 lens_led = vec3(0.0);       // lens luminance of an avenue head / a street head (engine units)
uniform vec3 lens_na = vec3(0.0);
uniform vec4 fail_lamp = vec4(55.0, 8.0, 5.1, 1.0);   // the failing head's lens (level space), its level
uniform vec4 sig_pos[8];                 // lit signal lenses (level space)
uniform vec4 sig_rad[8];                 // their luminance (engine units)
uniform vec4 sig_dir[8];                 // the way they face

// After rain (wet = moisture 0..1, film = standing water 0..1), as a
// porous surface takes water (Lagarde 2013): first the pores fill (up to
// wet 0.5), which makes it darker (Lekner & Dorf 1988: light trapped
// under the water, A (1 - r_e)(1 - r_i) / (1 - r_i A) with r_e = 0.066 and
// r_i = 0.472 for water) but leaves it rough; then water lies on it and
// smooths it (to a quarter of its roughness, soaked); a puddle is a flat
// water film (roughness 0.03, F0 0.02) over the darkened surface.
void lucid_wet(inout vec3 col, inout float rough, inout float f0, float moist, float film) {
	moist = max(moist, film);
	col = mix(col, col * 0.493 / (1.0 - 0.472 * col), min(moist * 2.0, 1.0));
	rough = mix(rough * mix(1.0, 0.25, clamp(moist * 2.0 - 1.0, 0.0, 1.0)), 0.03, film);
	f0 = mix(f0, 0.02, film);
}

float lucid_vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lucid_hash(i), lucid_hash(i + vec2(1.0, 0.0)), f.x),
			mix(lucid_hash(i + vec2(0.0, 1.0)), lucid_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// Standing water (0..1) at p (level space, metres): depressions a few
// metres across (value noise, its octaves turned off the grid so no
// square shapes show), and on a road the gutters along the curbs, where
// the 2 % crossfall sends the water. `puddles` sets how much. w: the
// pixel's footprint (metres, the square root of its area): an octave finer
// than it fades to its mean; and the rim is as wide as the mask changes
// across the pixel, so it does not stair-step or crawl far off and at
// grazing views. (Uses derivatives: call it in uniform control flow.)
float puddle(vec2 p, float w) {
	vec3 f = vec3(0.3, 0.93, 3.7);
	vec3 a = vec3(0.6, 0.28, 0.12) * (1.0 - smoothstep(0.25, 1.0, f * w));
	vec2 p2 = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8)) * p;
	vec2 p3 = mat2(vec2(0.28, -0.96), vec2(0.96, 0.28)) * p;
	float low = (lucid_vnoise(p * f.x) - 0.5) * a.x + (lucid_vnoise(p2 * f.y + 7.3) - 0.5) * a.y
			+ (lucid_vnoise(p3 * f.z) - 0.5) * a.z + 0.5;
	if (gutters) {
		float xa = abs(p.x - round(p.x / 110.0) * 110.0);
		float zs = abs(p.y - round(p.y / 80.0) * 80.0);
		float g = 100.0;
		if (xa < 9.5 && zs > 6.0) {
			g = 9.5 - xa;
		}
		if (zs < 6.0 && xa > 9.5) {
			g = min(g, 6.0 - zs);
		}
		low += 0.3 * (1.0 - smoothstep(0.0, 1.0, g));
	}
	float t = 0.78 - 0.22 * puddles;
	float aa = min(fwidth(low), 0.1);
	return smoothstep(t - aa, t + 0.03 + aa, low);
}

// The street heads and the lit signals mirrored at lp (level space): the
// grid's nearest avenue head (10 m up) and street head (8 m up) to where
// the reflected ray meets their height, as rectangular lenses of their
// real luminance, and the eight vehicle signals' lit lenses.
vec3 lamp_reflections(vec3 lp, LucidMirror m) {
	vec3 acc = vec3(0.0);
	vec3 r = m.r;
	if (r.y > 0.01) {
		float t = (10.0 - lp.y) / r.y;
		if (t > 0.0) {
			vec3 q = lp + r * t;
			float xc = round(q.x / 110.0) * 110.0;
			float sx = q.x >= xc ? 1.0 : -1.0;
			vec3 c = vec3(xc + sx * 7.6, 10.0, 17.5 + 35.0 * round((q.z - 17.5) / 35.0));
			acc += lens_led * lucid_emitter_cover(lp, m, c, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.25, 0.125));
		}
		t = (8.0 - lp.y) / r.y;
		if (t > 0.0) {
			vec3 q = lp + r * t;
			float zc = round(q.z / 80.0) * 80.0;
			float sz = q.z >= zc ? 1.0 : -1.0;
			float xl = floor(q.x / 110.0) * 110.0;
			float k = clamp(round((q.x - xl - 25.0) / 30.0), 0.0, 2.0);
			vec3 c = vec3(xl + 25.0 + 30.0 * k, 8.0, zc + sz * 5.1);
			float lv = distance(c.xz, fail_lamp.xz) < 0.5 ? fail_lamp.w : 1.0;
			acc += lens_na * lv * lucid_emitter_cover(lp, m, c, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec2(0.125, 0.2));
		}
		acc *= lucid_sky.z;
	}
	for (int i = 0; i < 8; i++) {
		if (sig_rad[i].a <= 0.0) {
			continue;
		}
		vec3 nn = sig_dir[i].xyz;
		vec3 c = sig_pos[i].xyz;
		// Signal optics: a beam of about +-15 degrees round its axis.
		float beam = max(dot(nn, normalize(lp - c)), 0.0);
		beam *= beam;
		acc += sig_rad[i].rgb * beam * beam * lucid_emitter_cover(lp, m, c, cross(vec3(0.0, 1.0, 0.0), nn), vec3(0.0, 1.0, 0.0), vec2(0.135));
	}
	return acc;
}

