// L.U.C.I.D. stage 4: the one specular model of every L.U.C.I.D. surface
// (docs/LUCID.md, "stage 4").
//
// Microfacets with the GGX (Trowbridge-Reitz) distribution, Smith's
// height-correlated visibility and Schlick's Fresnel with the material's
// real F0 (dielectrics 0.02-0.05, water 0.02). Roughness is perceptual:
// alpha = roughness^2. What the specular reflects is taken from the
// diffuse (times 1 - its directional albedo), so the two never add up to
// more than the light that came in.
//
// Three sources of specular light, all in the same units as the bake:
// - Emitters the level knows (troffers, street heads, signals): their
//   reflection is evaluated analytically per pixel as the share of the
//   reflected lobe the emitter covers (lucid_emitter_cover) times its
//   luminance and the lobe's directional albedo. The lobe is a gaussian
//   about the mirror direction, sqrt(2) alpha wide in the plane of
//   incidence and cos(theta_v) times that across it (a tilt of the
//   microfacet normal turns the reflection by twice the tilt in that
//   plane, by 2 cos(theta_v) times it across), so the reflections of
//   lamps on a glossy floor stretch into streaks toward the viewer.
// - The environment: a box-projected (parallax-corrected) probe sampled
//   at the mip whose texel matches the lobe (lucid_probe).
// - The real light nodes (moon, flashlight): GGX per light (lucid_ggx).

#ifndef LUCID_SPEC
#define LUCID_SPEC

const float LUCID_PI = 3.14159265;

// 1 while a reflection probe captures (LucidProbe): the emitters whose
// reflections are worked out analytically go dark, so nothing is
// reflected twice.
global uniform float lucid_capture;

// 1 in a probe's capture views (lucid_capture on and a 90 degree square
// projection, which no player camera has), else 0.
float lucid_capturing(mat4 proj) {
	return lucid_capture * step(abs(proj[0][0] - 1.0), 0.001) * step(abs(abs(proj[1][1]) - 1.0), 0.001);
}

// Schlick: reflectance at cos theta for a dielectric of normal reflectance f0.
float lucid_schlick(float f0, float c) {
	float m = 1.0 - clamp(c, 0.0, 1.0);
	float m2 = m * m;
	return f0 + (1.0 - f0) * m2 * m2 * m;
}

// BRDF x cos for a light of unit illuminance (normal to it) from l:
// D (GGX) x V (Smith, height-correlated) x F (Schlick) x cos.
float lucid_ggx(vec3 n, vec3 v, vec3 l, float rough, float f0) {
	vec3 h = normalize(v + l);
	float ndl = clamp(dot(n, l), 0.0, 1.0);
	float ndv = clamp(dot(n, v), 1e-3, 1.0);
	float ndh = clamp(dot(n, h), 0.0, 1.0);
	float a = rough * rough;
	float a2 = a * a;
	float dd = ndh * ndh * (a2 - 1.0) + 1.0;
	float d = a2 / (LUCID_PI * dd * dd);
	float vis = 0.5 / (ndl * sqrt(ndv * ndv * (1.0 - a2) + a2) + ndv * sqrt(ndl * ndl * (1.0 - a2) + a2) + 1e-5);
	return d * vis * lucid_schlick(f0, dot(v, h)) * ndl;
}

// The directional albedo of the specular lobe (the split-sum DFG term):
// how much of uniform incoming light the lobe reflects at this view, for
// F0 = f0. Karis' analytic fit for mobile (2014), within a few per cent.
float lucid_spec_albedo(float ndv, float rough, float f0) {
	const vec4 c0 = vec4(-1.0, -0.0275, -0.572, 0.022);
	const vec4 c1 = vec4(1.0, 0.0425, 1.04, -0.04);
	vec4 r = rough * c0 + c1;
	float a004 = min(r.x * r.x, exp2(-9.28 * max(ndv, 0.0))) * r.x + r.y;
	vec2 ab = vec2(-1.04, 1.04) * a004 + r.zw;
	return clamp(f0 * ab.x + ab.y, 0.0, 1.0);
}

// The reflected lobe's angular widths (gaussian sigma, radians): x in the
// plane of incidence, y across it.
vec2 lucid_lobe(float ndv, float rough) {
	float a = rough * rough * 1.414;
	return vec2(a, a * clamp(ndv, 0.03, 1.0));
}

// erf by tanh (within 0.02).
float lucid_erf(float x) {
	return tanh(1.2025 * x);
}

// The share of a gaussian of width s centred at o that falls in [-e, e].
float lucid_box(float o, float e, float s) {
	float k = 0.7071 / max(s, 1e-5);
	return 0.5 * (lucid_erf((o + e) * k) - lucid_erf((o - e) * k));
}

// Mirror frame at a point: the reflected ray r, `ti` in the plane of
// incidence (perpendicular to r) and `to` across it.
struct LucidMirror {
	vec3 r;
	vec3 ti;
	vec3 to;
	vec2 sig;      // lobe widths (radians), widened by the pixel's footprint
	float ndv;
};

LucidMirror lucid_mirror(vec3 n, vec3 v, float rough) {
	LucidMirror m;
	m.ndv = clamp(dot(n, v), 1e-3, 1.0);
	m.r = reflect(-v, n);
	vec3 to = cross(n, m.r);
	float lo = length(to);
	m.to = lo > 1e-4 ? to / lo : normalize(cross(n, abs(n.y) < 0.9 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0)));
	m.ti = cross(m.r, m.to);
	// The pixel's own angular footprint keeps a mirror from aliasing (a
	// flat mirror turns the reflection as much as the view turns; taken
	// from the view, not r, so a bump map's noise does not widen it).
	float pix = length(fwidth(v)) * 0.5;
	vec2 s = lucid_lobe(m.ndv, rough);
	m.sig = sqrt(s * s + vec2(pix * pix));
	return m;
}

// The share of the lobe that a flat emitter covers: a rectangle centred
// at c with half sizes hs along the unit vectors a1, a2 (its normal is
// cross(a1, a2), facing the side it lights; a disc: hs = radius x 0.886,
// the square of the same area). Small-angle: the emitter's angular extent
// in the lobe's frame, its area kept, convolved with the gaussian lobe.
float lucid_emitter_cover(vec3 p, LucidMirror m, vec3 c, vec3 a1, vec3 a2, vec2 hs) {
	vec3 d = c - p;
	float dist = length(d);
	d /= dist;
	float cr = dot(d, m.r);
	if (cr <= 0.0) {
		return 0.0;
	}
	vec3 ln = cross(a1, a2);
	float face = -dot(ln, d);
	if (face <= 0.0) {
		return 0.0;
	}
	vec2 o = vec2(dot(d, m.ti), dot(d, m.to)) / cr;
	// Cheap reject: more than 4.5 sigma (plus the emitter) away.
	float ext = max(hs.x, hs.y) / dist;
	if (abs(o.x) > 4.5 * m.sig.x + ext || abs(o.y) > 4.5 * m.sig.y + ext) {
		return 0.0;
	}
	// Its axes as seen from p (projected across the line of sight), then
	// its half extents along the lobe's two axes, scaled to keep its solid
	// angle (a rectangle seen obliquely is a parallelogram).
	vec3 b1 = (a1 - d * dot(a1, d)) * hs.x;
	vec3 b2 = (a2 - d * dot(a2, d)) * hs.y;
	vec2 e = vec2(abs(dot(b1, m.ti)) + abs(dot(b2, m.ti)), abs(dot(b1, m.to)) + abs(dot(b2, m.to))) / dist;
	e *= clamp(sqrt(hs.x * hs.y * face / max(e.x * e.y * dist * dist, 1e-12)), 0.5, 1.0);
	return lucid_box(o.x, e.x, m.sig.x) * lucid_box(o.y, e.y, m.sig.y);
}

// ---------------------------------------------------------------- probes ---
// A reflection probe: an octahedral map of the radiance round a point
// (engine units), its mips box-filtered, sampled box-projected: the
// reflected ray is followed to the probe's box (the room, the street
// canyon) and the map is read toward that point from the probe's centre.

vec2 lucid_oct(vec3 d) {
	d /= abs(d.x) + abs(d.y) + abs(d.z);
	vec2 o = d.y >= 0.0 ? d.xz : (1.0 - abs(d.zx)) * vec2(d.x >= 0.0 ? 1.0 : -1.0, d.z >= 0.0 ? 1.0 : -1.0);
	return o * 0.5 + 0.5;
}

// Where the ray p + t r leaves the box (bmin, bmax), as a direction from
// the probe's centre c.
vec3 lucid_box_dir(vec3 p, vec3 r, vec3 c, vec3 bmin, vec3 bmax) {
	vec3 rr = vec3(abs(r.x) < 1e-5 ? 1e-5 : r.x, abs(r.y) < 1e-5 ? 1e-5 : r.y, abs(r.z) < 1e-5 ? 1e-5 : r.z);
	vec3 t1 = (bmax - p) / rr;
	vec3 t2 = (bmin - p) / rr;
	vec3 tf = max(t1, t2);
	float t = max(min(min(tf.x, tf.y), tf.z), 0.0);
	return p + r * t - c;
}

// The same for a crossing: the open space is the union of two street
// canyons (the slabs slab.x < x < slab.y and slab.z < z < slab.w), capped
// by the box (bmin, bmax). The ray leaves it where it has left both, i.e.
// where it meets a corner block's wall, not a box 60 m off (which smeared
// the corner shopfronts across the crossing's wet asphalt).
vec3 lucid_plus_dir(vec3 p, vec3 r, vec3 c, vec3 bmin, vec3 bmax, vec4 slab) {
	vec3 rr = vec3(abs(r.x) < 1e-5 ? 1e-5 : r.x, abs(r.y) < 1e-5 ? 1e-5 : r.y, abs(r.z) < 1e-5 ? 1e-5 : r.z);
	vec3 tf = max((bmax - p) / rr, (bmin - p) / rr);
	float tb = min(min(tf.x, tf.y), tf.z);
	vec2 tx = (slab.xy - p.x) / rr.x;
	vec2 tz = (slab.zw - p.z) / rr.z;
	vec2 ix = vec2(min(tx.x, tx.y), max(tx.x, tx.y));   // in / out of each slab
	vec2 iz = vec2(min(tz.x, tz.y), max(tz.x, tz.y));
	// Starting in one slab: it leaves that one, unless it is then in the
	// other, which it leaves later.
	float ta = ix.y;
	if (iz.x <= ta && iz.y > ta) {
		ta = iz.y;
	}
	float tc = iz.y;
	if (ix.x <= tc && ix.y > tc) {
		tc = ix.y;
	}
	float t = p.x > slab.x && p.x < slab.y ? ta : tc;
	return p + r * clamp(t, 0.0, max(tb, 0.0)) - c;
}

// The mip whose texel (an octahedral map `size` texels across: 3.5 / size
// radians) matches the lobe's width; never sharper than mip 1 (a probe is
// captured at 64 px a face and seen box-projected from elsewhere than its
// centre: its finest texels would show as blocks).
float lucid_probe_lod(float rough, float size) {
	float s = rough * rough * 1.414;
	return max(log2(s * size / 3.5), 1.0);
}

#endif
