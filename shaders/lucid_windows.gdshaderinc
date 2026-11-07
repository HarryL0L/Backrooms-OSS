// L.U.C.I.D. stage 3: procedural facades with lit windows (included by
// lucid_facade.gdshader and lucid_blocks.gdshader, after lucid_city).
//
// A facade is a grid of storeys and bays above an optional shop band.
// Each window is lit or not by a hash (offices light whole floors, homes
// single windows), with the share of lit windows from the light state
// (Lucid.STATES windows, blended). A lit window is an emitter of the
// luminance a real one has seen from outside (Lucid.FIXTURES window_*,
// engine units in win_*_rad), with its room behind it (a ceiling lamp,
// furniture, curtains or blinds); an unlit one mirrors what is in front of
// it by Fresnel (near facades: the reflection probe and the street heads)
// over a dark room, a blind or curtains lit by the street through it.
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
	float frame;     // share that is window frame, sash bars and sill (lit like the wall, paler)
	vec3 emit;       // what the glass sends (engine units), already times `glass`
	float sharp;     // 1 where the windows are resolved (their edges blend as the eye sees them)
};

float aa_box(float x, float a, float b, float w) {
	float m = clamp((x - a) / w + 0.5, 0.0, 1.0) * clamp((b - x) / w + 0.5, 0.0, 1.0);
	return mix(m, b - a, smoothstep(0.35, 1.0, w));
}

// Wall, frames and glass put together. Where the windows are resolved
// their edges are blended in the camera's output (each colour exposed and
// compressed as x / (1 + x) before the coverage weights, then expanded):
// a window 50 times brighter than its wall otherwise keeps a hard,
// stair-stepped edge however its coverage is anti-aliased, since a pixel a
// third covered is already white. Far off, where the pattern hands over to
// its mean, the plain (linear) mix keeps the facade's mean luminance.
vec3 lucid_facade_mix(vec3 wall, vec3 frame, Facade f) {
	vec3 lin = wall * (1.0 - f.glass - f.frame) + frame * f.frame + f.emit;
	if (f.sharp <= 0.0 || f.glass + f.frame < 1e-4) {
		return lin;
	}
	float k = max(lucid_exposure.g, 1e-6);
	vec3 g = f.emit / max(f.glass, 1e-4);
	vec3 t = wall * k / (1.0 + wall * k) * (1.0 - f.glass - f.frame) + frame * k / (1.0 + frame * k) * f.frame
			+ g * k / (1.0 + g * k) * f.glass;
	vec3 per = t / max(vec3(1.0) - t, vec3(1e-3)) / k;
	return mix(lin, per, f.sharp);
}

// What hangs behind a pane (h, h2: the window's hashes; iu, iv: 0..1 across
// and up the glass; amb: the light falling on the wall outside, E / pi,
// which also lights what is just behind the glass; room: the radiance of
// the lit room, 0 when its lights are off). Dark rooms are not black:
// blinds and curtains catch the street's light through the glass (twice
// through it: 0.8), a bare room shows its floor and furniture dimly.
vec3 lucid_behind(float h, float h2, float iu, float iv, vec3 amb, vec3 room, float w) {
	vec3 dark = amb * (0.03 + 0.06 * smoothstep(0.6, 0.0, iv)) * 0.8;
	// A quarter of the dark rooms have a light on further in (a hall's,
	// through a door): a dim warm slot.
	float hall = step(0.75, fract(h2 * 23.1)) * step(abs(iu - 0.15 - 0.7 * fract(h2 * 41.7)), 0.09) * step(iv, 0.75);
	dark += win_home_rad * vec3(1.08, 0.97, 0.82) * 0.05 * hall * step(dot(room, vec3(1.0)), 0.0);
	// Furniture against the light: a sofa back or a desk, a lamp shade.
	float fh = 0.18 + 0.2 * h2;
	float furn = smoothstep(fh + 0.02, fh - 0.02, iv) * step(abs(iu - 0.2 - 0.6 * fract(h2 * 7.3)), 0.3);
	vec3 lit = room * (1.0 - 0.6 * furn);
	// A ceiling lamp in half the rooms, a bright patch over the window head.
	float lamp = step(0.5, fract(h2 * 3.7)) * smoothstep(0.2, 0.0, length(vec2((iu - fract(h2 * 11.0) * 0.6 - 0.2) * 1.4, iv - 0.95)));
	lit += room * lamp * 2.5;
	vec3 r = lit + dark;
	if (h < 0.3) {
		// A blind let down to somewhere between a third and all of the way,
		// its slats (fading out once smaller than a pixel).
		float drop = 0.35 + 0.65 * fract(h * 17.3);
		float cov = smoothstep(1.0 - drop - 0.01, 1.0 - drop + 0.01, iv);
		float slat = mix(0.85 + 0.15 * sin(iv * 120.0), 0.92, smoothstep(0.003, 0.01, w));
		vec3 blind = vec3(0.47, 0.45, 0.41) * slat * amb * 0.8 + room * 0.4 * slat;
		r = mix(r, blind, cov);
	} else if (h < 0.6) {
		// Curtains: closed with a gap in a dark room, drawn to the sides in
		// a lit one; folds; one of a few fabrics, lit through by the room.
		vec3 fab = h2 < 0.25 ? vec3(0.42, 0.36, 0.27) : (h2 < 0.5 ? vec3(0.28, 0.07, 0.06)
				: (h2 < 0.75 ? vec3(0.16, 0.19, 0.22) : vec3(0.18, 0.22, 0.13)));
		float open_w = max(dot(room, vec3(1.0)), 0.0) > 0.0 ? 0.3 + 0.15 * h2 : 0.04 + 0.1 * h2;
		float cov = smoothstep(open_w - 0.02, open_w + 0.02, abs(iu - 0.5));
		float fold = mix(0.7 + 0.3 * sin(iu * 75.0 + h2 * 6.0), 0.85, smoothstep(0.004, 0.012, w));
		vec3 cur = fab * fold * (amb * 0.8 + room * 0.6 / max(dot(fab, vec3(0.333)), 0.05) * 0.5);
		r = mix(r, cur, cov);
	}
	return r;
}

// u: metres along the wall; v: metres above the ground; kind 0 home, 1
// office (curtain wall), 2 masonry; g0 the shop band's height (0 none).
// refl: what unlit glass mirrors (engine units); amb: the light on the
// wall (E / pi); top: the wall's top (no windows in the parapet's 0.9 m
// under it).
Facade lucid_facade(float u, float v, float kind, float seed, float storey, float bay, float g0, vec3 refl, float fres, float top, vec3 amb) {
	Facade f;
	f.sharp = 0.0;
	if (v > top - 0.9) {
		// The parapet over the top floor.
		f.glass = 0.0;
		f.frame = 0.0;
		f.emit = vec3(0.0);
		return f;
	}
	float lit_frac = mix(lit_a, lit_b, lucid_sky.x);
	float fres_w = fres;
	// Curtain walls are solar-control glass (reflectance ~0.25 rather than
	// a plain pane's 0.04-0.08): they mirror the city more than they show
	// their dark rooms.
	if (kind > 0.5 && kind < 1.5) {
		fres_w = min(fres * 3.0, 0.6);
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
		// Inside (stage 4: a real luminance range, not a flat panel, so the
		// camera's exposure shows detail): the night lights in a row under
		// the ceiling (small, ~8x the mean, they clip as in a photo), the
		// ceiling and the top of the back wall lit by them, shelves of
		// goods down the back (each lot its own colour and shade, the
		// uprights and the shelf edges in shadow), a dim floor and a dark
		// counter. Mean ~0.6 of the fixture's luminance (the bake's gather
		// still sees the fixture's full mean: a few % more bounce).
		float in_v = v / (g0 * 0.78);
		float in_u = (fu - 0.06) / 0.88;
		float lamp = step(abs(fract(in_u * 3.0) - 0.5), 0.17) * smoothstep(0.86, 0.88, in_v) * smoothstep(0.96, 0.94, in_v);
		// (Goods: packs ~0.1 m wide in lots of a few, each lot a colour, lit
		// from above: brighter on top, in the shelf over it's shadow below.)
		float gx = in_u * 44.0 + h * 3.0;
		float gy = in_v * 5.5;
		float hl = lucid_hash(vec2(floor(gx / 3.0), floor(gy)) + vec2(bi * 13.0, seed));
		float hp = lucid_hash(vec2(floor(gx), floor(gy) + 0.5) + vec2(bi, seed * 3.0));
		vec3 goods = mix(vec3(0.8), vec3(0.4 + 0.9 * hl, 0.4 + 0.9 * fract(hl * 5.3), 0.4 + 0.9 * fract(hl * 9.1)), 0.45)
				* (0.3 + 0.5 * hl + 0.25 * hp) * (0.45 + 0.55 * smoothstep(0.1, 0.75, fract(gy)));
		float gap = step(fract(gx), 0.1) * 0.5 + step(fract(gy), 0.12) + step(0.85, fract(gy)) * 0.6;
		float shelf = mix(1.0, 0.2, min(gap, 1.0));
		vec3 back = in_v > 0.15 && in_v < 0.8 ? goods * shelf * 1.2 : vec3(1.0);
		float grad = 0.18 + 0.82 * smoothstep(0.0, 0.95, in_v) * smoothstep(0.0, 0.95, in_v);
		float counter = fu > 0.3 && fu < 0.7 && in_v < 0.3 ? 0.25 : 1.0;
		vec3 shop = win_shop_rad * var * (grad * back * counter * 0.95 + lamp * 8.0) + refl * fres;
		vec3 avg = win_shop_rad * 0.9 * 0.35;
		float far = smoothstep(0.35, 1.0, max(wu, wv));
		// A closed one: a roller shutter (ribbed steel, lit like the wall).
		float rib = 0.75 + 0.25 * sin(v * 62.8);
		f.glass = m * mix(lit, 1.0, far);
		f.frame = m * (1.0 - lit) * (1.0 - far) * rib;
		f.emit = mix(shop * lit, avg, far) * m;
		f.sharp = 1.0 - far;
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
	// The openings in metres (across the bay, up from the floor), so they
	// keep their real size whatever the storey: a home's 1.2 x 1.5 m on a
	// 0.9 m sill; a masonry building's tall double-hung sash 1.1 m wide on
	// a 0.85 m sill, up to 2.0 m tall with a lintel and the floor over it
	// (0.7 m or more); a curtain wall's 1.5 m modules with 64 mm mullions,
	// vision glass from the floor to a 2.9 m ceiling and the spandrel over
	// the plenum and the slab edge.
	vec4 r = kind < 0.5 ? vec4(0.5 - 0.6 / bay, 0.5 + 0.6 / bay, 0.9 / storey, min(2.4, storey - 0.5) / storey)
			: (kind < 1.5 ? vec4(0.032 / bay, 1.0 - 0.032 / bay, 0.1 / storey, min(2.9, storey - 1.0) / storey)
			: vec4(0.5 - 0.55 / bay, 0.5 + 0.55 / bay, 0.85 / storey, (0.85 + clamp(storey - 1.55, 1.5, 2.0)) / storey));
	float m = aa_box(fu, r.x, r.y, wu) * aa_box(fv, r.z, r.w, wv);
	bool office = kind > 0.5 && kind < 1.5;
	// A 70 mm frame round it and a 120 mm sill under it (not on curtain
	// walls); sash bars: a double-hung window's meeting rail, a home's
	// casement pair's mullion.
	float fu_w = 0.07 / bay;
	float fv_w = 0.07 / storey;
	float fr = office ? 0.0
			: max(aa_box(fu, r.x - fu_w, r.y + fu_w, wu) * aa_box(fv, r.z - fv_w * 1.7, r.w + fv_w, wv) - m, 0.0);
	float in_v = (fv - r.z) / (r.w - r.z);
	float in_u = (fu - r.x) / (r.y - r.x);
	if (!office) {
		float wiu = wu / (r.y - r.x);
		float wiv = wv / (r.w - r.z);
		float rail = 0.045 / (storey * (r.w - r.z));
		float bars = aa_box(in_v, 0.55 - rail, 0.55 + rail, wiv);
		if (kind < 0.5) {
			float mull = 0.03 / (bay * (r.y - r.x));
			bars = max(bars, aa_box(in_u, 0.5 - mull, 0.5 + mull, wiu));
		}
		bars *= 1.0 - smoothstep(0.15, 0.4, w);
		fr += m * bars;
		m *= 1.0 - bars;
	}
	float h = lucid_hash(vec2(bi * 1.37 + seed * 91.7, fl * 7.13 + seed * 13.1));
	float hf = lucid_hash(vec2(fl * 3.1 + seed * 57.3, seed * 2.7 + 3.0));
	float floor_on = office ? step(hf, lit_frac * 0.6) : 0.0;
	float p_lit = office ? mix(lit_frac * 0.2, 0.85, floor_on) : lit_frac;
	float lit = step(h, p_lit);
	vec3 base = office ? win_office_rad : win_home_rad;
	// A home's lamps are warmer or cooler, some windows show a TV's blue.
	float hv = lucid_hash(vec2(h * 13.7, fl + bi * 0.37));
	vec3 tint = office ? vec3(1.0) : mix(vec3(1.08, 0.97, 0.82), vec3(0.9, 1.0, 1.15), step(0.8, hv));
	float var = (0.45 + 1.2 * hv) * (office ? 1.0 : (hv > 0.93 ? 0.25 : 1.0));
	vec3 room = base * tint * var * (0.65 + 0.7 * in_v) * lit;
	vec3 e;
	if (office) {
		// Open plan: the ceiling's rows of troffers, desks and partitions
		// darker below; unlit, the dark floor plate by the city's light.
		float trof = step(0.5, fract(in_u * 1.0 + 0.25)) * smoothstep(0.86, 0.88, in_v) * smoothstep(0.95, 0.93, in_v);
		float desk = smoothstep(0.27, 0.23, in_v) * (0.5 + 0.5 * step(0.5, fract(in_u * 2.0 + hv)));
		e = refl * fres_w + (room * (1.0 - 0.45 * desk) * 0.92 + base * lit * trof * 2.5 + amb * 0.02 * 0.8) * (1.0 - fres_w);
	} else {
		float hb = lucid_hash(vec2(bi * 4.1 + seed, fl * 1.7));
		float h2 = lucid_hash(vec2(bi * 2.3 + seed * 1.3, fl * 5.9 + 1.0));
		e = refl * fres_w + lucid_behind(hb, h2, in_u, in_v, amb, room, w) * (1.0 - fres_w);
	}
	// Windows too small to resolve: cells of 2, 4, 8... bays (and floors),
	// so a far facade still sparkles like a photo of one instead of going
	// flat, and never shimmers. Where only one way is too small (a facade
	// seen edge on, or straight up), the windows along it blend to their
	// mean instead: whole cells lit or not would draw stripes (and so do
	// cells much longer one way than the other).
	float gu = exp2(max(ceil(log2(wu * 1.2)), 0.0));
	float gv = exp2(max(ceil(log2(wv * 1.2)), 0.0));
	vec3 dark = refl * fres_w + amb * 0.05 * (1.0 - fres_w);
	if (gu > 1.5 || gv > 1.5) {
		float cu = floor(u / (bay * gu));
		float cv = floor(vv / (storey * gv));
		float hc = lucid_hash(vec2(cu * 1.37 + seed * 91.7 + gu * 0.31, cv * 7.13 + seed * 13.1 + gv * 0.17));
		float pa = office ? (lit_frac * 0.6 * 0.85 + (1.0 - lit_frac * 0.6) * lit_frac * 0.2) : lit_frac;
		float p = gv > 1.5 ? pa : p_lit;
		// Each cell lit or not with the windows' probability: the same
		// mean, and the speckle a camera sees in a far lit facade.
		float frac = gu > 1.5 && gv > 1.5 && max(gu, gv) <= 2.0 * min(gu, gv) ? step(hc, p) : p;
		float au = gu > 1.5 ? (r.y - r.x) : aa_box(fu, r.x, r.y, wu);
		float av = gv > 1.5 ? (r.w - r.z) : aa_box(fv, r.z, r.w, wv);
		m = au * av;
		e = mix(dark, base * tint * 0.95, frac);
		fr = 0.0;
	}
	f.frame = fr;
	f.glass = m;
	f.emit = e * m;
	f.sharp = 1.0 - smoothstep(0.15, 0.5, w);
	return f;
}
