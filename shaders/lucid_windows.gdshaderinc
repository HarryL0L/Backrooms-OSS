// L.U.C.I.D. stage 3: procedural facades with lit windows (included by
// lucid_facade.gdshader and lucid_blocks.gdshader, after lucid_city).
//
// A facade is a grid of storeys and bays above an optional shop band.
// Each window is lit or not by a hash (offices light whole floors, homes
// single windows), with the share of lit windows from the light state
// (Lucid.STATES windows, blended). A lit window is an emitter of the
// luminance a real one has seen from outside (Lucid.FIXTURES window_*,
// engine units in win_*_rad); an unlit one mirrors the sky by Fresnel.
// Once a window is smaller than a pixel or so the pattern hands over to
// its expected value (no shimmer): the same mean luminance, as a camera
// would integrate it.

uniform vec3 win_office_rad = vec3(0.163);   // 25 cd/m2, 4000 K (set by the level)
uniform vec3 win_home_rad = vec3(0.078);     // 12 cd/m2, 2900 K
uniform vec3 win_shop_rad = vec3(0.26);      // 40 cd/m2, 3500 K
uniform float lit_a = 0.35;                  // lit share in state A
uniform float lit_b = 0.22;                  // and in state B

struct Facade {
	float glass;     // share of the pixel that is glass
	float frame;     // share that is window frame and sill (lit like the wall, paler)
	vec3 emit;       // what the glass sends (engine units), already times `glass`
};

float aa_box(float x, float a, float b, float w) {
	float m = clamp((x - a) / w + 0.5, 0.0, 1.0) * clamp((b - x) / w + 0.5, 0.0, 1.0);
	return mix(m, b - a, smoothstep(0.35, 1.0, w));
}

// u: metres along the wall; v: metres above the ground; kind 0 home, 1
// office (curtain wall), 2 masonry; g0 the shop band's height (0 none).
// refl: the sky radiance mirrored by unlit glass (engine units); top: the
// roof's height (no windows in the parapet's 0.9 m under it).
Facade lucid_facade(float u, float v, float kind, float seed, float storey, float bay, float g0, vec3 refl, float fres, float top) {
	Facade f;
	if (v > top - 0.9) {
		// The parapet over the top floor.
		f.glass = 0.0;
		f.frame = 0.0;
		f.emit = vec3(0.0);
		return f;
	}
	float lit_frac = mix(lit_a, lit_b, lucid_sky.x);
	vec3 dark = refl * fres + vec3(0.003) / LUCID_UNIT_NITS;
	// Curtain walls are solar-control glass (reflectance ~0.25 rather than
	// a plain pane's 0.04-0.08): they mirror the city more than they show
	// their dark rooms.
	if (kind > 0.5 && kind < 1.5) {
		dark = refl * min(fres * 4.0, 0.6) + vec3(0.003) / LUCID_UNIT_NITS;
	}
	if (g0 > 0.0 && v < g0) {
		// Shopfronts: 5 m bays of glass, lit (left on) or behind a shutter.
		float sb = 5.0;
		float wu = max(fwidth(u) / sb, 1e-4);
		float wv = max(fwidth(v) / g0, 1e-4);
		float bi = floor(u / sb);
		float fu = fract(u / sb);
		float m = aa_box(fu, 0.06, 0.94, wu) * aa_box(v / g0, 0.08, 0.78, wv);
		float h = lucid_hash(vec2(bi * 1.91 + seed * 31.3, seed * 5.7 + 11.0));
		float lit = step(h, 0.35);
		float var = 0.6 + 0.9 * lucid_hash(vec2(h * 7.3, bi));
		// Inside: brighter towards the ceiling and the back, a dark counter.
		float in_v = v / (g0 * 0.78);
		vec3 shop = win_shop_rad * var * (0.55 + 0.6 * in_v) * (fu > 0.3 && fu < 0.7 && in_v < 0.3 ? 0.35 : 1.0);
		vec3 avg = win_shop_rad * 0.9 * 0.35;
		float far = smoothstep(0.35, 1.0, max(wu, wv));
		// A closed one: a roller shutter (ribbed steel, lit like the wall).
		float rib = 0.75 + 0.25 * sin(v * 62.8);
		f.glass = m * mix(lit, 1.0, far);
		f.frame = m * (1.0 - lit) * (1.0 - far) * rib;
		f.emit = mix(shop * lit, avg, far) * m;
		return f;
	}
	float vv = v - g0;
	float wu = max(fwidth(u) / bay, 1e-4);
	float wv = max(fwidth(vv) / storey, 1e-4);
	float w = max(wu, wv);
	float fl = floor(vv / storey);
	float fv = fract(vv / storey);
	float bi = floor(u / bay);
	float fu = fract(u / bay);
	vec4 r = kind < 0.5 ? vec4(0.3, 0.7, 0.3, 0.8) : (kind < 1.5 ? vec4(0.03, 0.97, 0.27, 0.96) : vec4(0.29, 0.71, 0.25, 0.82));
	float m = aa_box(fu, r.x, r.y, wu) * aa_box(fv, r.z, r.w, wv);
	// A 70 mm frame round it and a 120 mm sill under it (not on curtain walls).
	float fu_w = 0.07 / bay;
	float fv_w = 0.07 / storey;
	float fr = kind > 0.5 && kind < 1.5 ? 0.0
			: max(aa_box(fu, r.x - fu_w, r.y + fu_w, wu) * aa_box(fv, r.z - fv_w * 1.7, r.w + fv_w, wv) - m, 0.0);
	float h = lucid_hash(vec2(bi * 1.37 + seed * 91.7, fl * 7.13 + seed * 13.1));
	float hf = lucid_hash(vec2(fl * 3.1 + seed * 57.3, seed * 2.7 + 3.0));
	bool office = kind > 0.5 && kind < 1.5;
	float floor_on = office ? step(hf, lit_frac * 0.6) : 0.0;
	float p_lit = office ? mix(lit_frac * 0.2, 0.85, floor_on) : lit_frac;
	float lit = step(h, p_lit);
	vec3 base = office ? win_office_rad : win_home_rad;
	// A home's lamps are warmer or cooler, some windows show a TV's blue.
	float hv = lucid_hash(vec2(h * 13.7, fl + bi * 0.37));
	vec3 tint = office ? vec3(1.0) : mix(vec3(1.08, 0.97, 0.82), vec3(0.9, 1.0, 1.15), step(0.8, hv));
	float var = (0.45 + 1.2 * hv) * (office ? 1.0 : (hv > 0.93 ? 0.25 : 1.0));
	float in_v = (fv - r.z) / (r.w - r.z);
	// Inside: the ceiling's lit band at the top, curtains or blinds half drawn.
	float blind = lucid_hash(vec2(bi * 4.1 + seed, fl * 1.7)) < 0.3 ? 0.35 : 1.0;
	vec3 lit_rad = base * tint * var * (0.65 + 0.7 * in_v) * mix(blind, 1.0, step(0.55, in_v));
	vec3 e = mix(dark, lit_rad, lit);
	// Windows too small to resolve: cells of 2, 4, 8... bays (and floors),
	// so a far facade still sparkles like a photo of one instead of going
	// flat, and never shimmers.
	float gu = exp2(max(ceil(log2(wu * 1.2)), 0.0));
	float gv = exp2(max(ceil(log2(wv * 1.2)), 0.0));
	if (gu > 1.5 || gv > 1.5) {
		float cu = floor(u / (bay * gu));
		float cv = floor(vv / (storey * gv));
		float hc = lucid_hash(vec2(cu * 1.37 + seed * 91.7 + gu * 0.31, cv * 7.13 + seed * 13.1 + gv * 0.17));
		float pa = office ? (lit_frac * 0.6 * 0.85 + (1.0 - lit_frac * 0.6) * lit_frac * 0.2) : lit_frac;
		float p = gv > 1.5 ? pa : p_lit;
		// Each cell lit or not with the windows' probability: the same
		// mean, and the speckle a camera sees in a far lit facade.
		float frac = step(hc, p);
		float au = gu > 1.5 ? (r.y - r.x) : aa_box(fu, r.x, r.y, wu);
		float av = gv > 1.5 ? (r.w - r.z) : aa_box(fv, r.z, r.w, wv);
		m = au * av;
		e = mix(dark, base * tint * 0.95, frac);
		fr = 0.0;
	}
	f.frame = fr;
	f.glass = m;
	f.emit = e * m;
	return f;
}
