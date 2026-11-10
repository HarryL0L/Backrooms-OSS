// Field sky under a tornadic supercell (FieldStorm, docs/FIELD_STORM.md).
// Overhead the anvil (~10 km up, its mammatus near the edge), a surface met
// analytically along the view ray. Toward the storm its cloud mass: the
// dark rain-free base (1.2 km), flat-bottomed, its rim ragged and fraying
// into wisps, and the cloud over the core that its rain falls from; met in
// a few horizontal slices (Beer-Lambert; the storm's shade light, the bright
// sky its thin rim scatters forward, the sun's forward lobe through its
// thinnest fringes, so the rims near the sun glow silver), 8 on High and
// up, 2 on Medium, 1 below. Beyond its western rim the flanking line's
// towers, backlit. The wall cloud hanging under the base round the
// mesocyclone, turning, and the inflow scud racing in under it: analytic.
// Beyond them the clear sky. Then the air along the ray, by steps
// (field_air): the haze and the rain shafts, each lit
// by the storm's shade or by the sun behind the storm where it reaches, so
// the horizon under the base glows, the core's curtain stands grey-green and
// far cloud fades into the haze. A lightning flash lights the base from
// inside (lucid_lightning_sky). Engine units, then the camera's exposure.
shader_type sky;
#include "res://shaders/field_common.gdshaderinc"
#include "res://shaders/lucid_city.gdshaderinc"
#define FIELD_HAS_LUCID
#include "res://shaders/field_storm.gdshaderinc"

uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int steps = 9;
// Slices through the cloud's volume (FieldLevel: 8 on High and up, 2 on
// Medium, 1 on Low and Potato; the flanking line on High and up).
uniform int cloud_steps = 8;
// The layers' brightness against the shade light (field_light).
uniform float base_k = 0.62;
uniform float wall_k = 0.2;
uniform float anvil_k = 1.25;
// The clear sky beyond the storm: zenith and horizon (engine units).
uniform vec3 clear_zenith = vec3(5.0, 9.0, 19.0);
uniform vec3 clear_horizon = vec3(13.0, 16.0, 21.0);
// The ground's albedo far off.
uniform float ground_albedo = 0.11;

// How far over its base the cloud's flanks reach (m), and its extinction
// (1/m): inside a cumulonimbus 0.05-0.2 /m (visibility 20-80 m); this is
// that averaged with the clear gaps between its lumps at the scale of a
// pixel kilometres off.
const float CLOUD_T = 2600.0;
const float CLOUD_SIG = 0.012;
// The angle a pixel spans (rad, ~70 degrees over 720 px): the noise's
// footprint, so octaves finer than a pixel fade instead of aliasing.
const float PIX = 0.0017;

float nz(vec2 p, float scale) {
	return texture(noise, p / scale).r;
}

// Fades a noise octave to its mean as it nears the pixel footprint.
float oct(vec2 p, float scale, float dist, float fade) {
	return mix(nz(p, scale), 0.5, smoothstep(scale * fade * 0.5, scale * fade, dist));
}

// A noise layer at the footprint fp (m): mip-filtered (explicit, so it is
// safe in loops), faded to its mean once its largest features near fp. Its
// features are ~0.11 scale down to ~0.014 scale (from mip 1 up: the map's
// finest octave is a texel wide, and magnified it shows bilinear diamonds).
float nzl(vec2 p, float scale, float fp) {
	float lod = log2(max(fp * 256.0 / scale, 2.3));
	return mix(textureLod(noise, p / scale, lod).r, 0.5, smoothstep(scale * 0.04, scale * 0.11, fp));
}

vec2 rot(vec2 v, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * v.x - s * v.y, s * v.x + c * v.y);
}

float hg(float c, float g) {
	return (1.0 - g * g) / pow(1.0 + g * g - 2.0 * g * c, 1.5);
}

// The storm's cloud mass at (p, h) (0 .. 1): the rain-free base round
// field_cloud_c (flat-bottomed where it is deep, its rim lifting, ragged and
// fraying into wisps; narrower above it, so from under it its rim is the
// base's own) and the cloud over the
// core, whose bottom the rain hides. cov: the smooth cover under the detail
// (how deep inside p is), rain: how much of it is the core's, det: its
// lumps (0 .. 1). q: 0 skips the warp and the fine octave (Medium and
// below).
float cloud_at(vec2 p, float h, float fp, int q, out float cov, out float rain, out float det) {
	float f = (h - field_cloud.x) / CLOUD_T;
	// Warped by a slowly turning field, so the rim folds into lobes and bays
	// instead of following a circle.
	vec2 pw = p;
	if (q > 0) {
		float wa = nzl(p, 16000.0, fp) * 5.0;
		pw += vec2(cos(wa), sin(wa)) * 700.0;
	}
	float rim = nzl(pw, 13000.0, fp);
	float rb = field_cloud.z * (1.0 - 0.1 * smoothstep(0.0, 0.5, f));
	// Far rims softer: the ramps widen with the pixel's footprint.
	float wf = min(fp * 0.003, 0.25);
	float cb = 1.0 - smoothstep(-0.32 - 0.15 * f - wf, 0.14 + wf, (length(pw - field_cloud_c.xy) - rb) / field_cloud.z + (rim - 0.5) * 0.6);
	float cc = 1.0 - smoothstep(-0.3, 0.05, (length(pw - field_core.xy) - field_core.z) / field_core.z + (rim - 0.5) * 0.5);
	cov = max(cb, cc);
	rain = cc * (1.0 - cb);
	det = 0.5;
	if (cov < 0.004) {
		return 0.0;
	}
	// Its lumps turn slowly with the mesocyclone and drift with the storm;
	// shifted a little with height, so the 2D noise reads as 3D while the
	// slices still agree (no stacked outlines); blurred a little past the
	// footprint, so far and grazing rims melt.
	vec2 pd = rot(p - field_meso.xy, field_meso.w * 0.2);
	float fs = fp * 1.5;
	float dn = nzl(pd + vec2(0.3, 0.2) * h, 2600.0, fs);
	if (q > 0) {
		dn = dn * 0.78 + 0.22 * nzl(pd + vec2(-0.4, 0.35) * h + 517.0, 700.0, fs);
	}
	det = dn;
	// Eroded by the detail where it is thin: the rim frays into wisps and
	// holes, its density tapering over a wide band (no threshold), so its
	// opacity ramps smoothly (softer with one octave, whose lumps alone
	// would serrate the rim).
	float sq = q > 0 ? 0.0 : 1.0;
	// (Its lower edge never below zero cover: no density is left where the
	// cover ends, so nothing is cut off there.)
	float d = smoothstep(max(dn * 0.5 - 0.45 - 0.2 * sq - wf, 0.0), dn * 0.5 + 0.6 + 0.2 * sq + wf, cov);
	// The bottom: flat and sharp under the deep base (seen from below),
	// lifting and thinning toward the rim over a band that widens with it
	// (no cut where a slice leaves it), soft over the rain.
	float e = 1.0 - cov;
	float x = h - field_cloud.x - 300.0 * e * e + 200.0 * rain;
	float bottom = smoothstep(-40.0 - 400.0 * e - 400.0 * rain, 5.0 + 300.0 * e + 300.0 * rain, x);
	// Ragged tops where the flanks end.
	float top = 1.0 - smoothstep(0.45, 1.0, f + (dn - 0.5) * 0.6);
	return d * bottom * top;
}

// The cloud mass along the ray from the eye (height ey), through n
// horizontal slices from its base up (crowded near the base; the lowest is
// the flat base itself, so its bottom stays sharp from below, while each
// slice's cover is a smooth field, so its rim dissolves without dither
// noise). Each slice: Beer-Lambert over its thickness along the ray; the
// light it scatters toward the eye is the storm's shade light (darkest on
// the deep underside, brighter up its flanks and in its thin rim, which the
// open sky around lights) plus the sun's two-lobed phase through its thin
// parts where the sun gets past the tower and the anvil (the rims toward the
// sun glow silver). Over the core a slice under the base, its soft bottom
// over the rain. rgb: its light (premultiplied), a: the transmittance; tf:
// its mean distance, weighted by what each slice shows (smooth, so the air
// in front of it does not jump where its opacity builds in another slice).
vec4 cloud_march(vec3 eye, vec3 d, float ey, int n, vec3 bg, out float tf) {
	tf = 1e9;
	if (d.y < 0.004) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	vec2 pm = eye.xz + d.xz * ((field_cloud.x + 600.0 - ey) / d.y);
	// The shade light (not field_shade_at's brighter open ground: the
	// cloud's rim gets its own below), the core's faint green.
	vec2 dc = eye.xz + d.xz * ((field_cloud.x - ey) / d.y) - field_core.xy;
	vec3 sh = field_light.rgb * mix(vec3(1.0), vec3(0.86, 1.0, 0.88), 0.8 * exp(-dot(dc, dc) / (field_core.z * field_core.z * 1.6)));
	float lit = field_lit_sky(pm, field_cloud.x + 600.0, n > 2);
	float c = dot(d, field_sun.xyz);
	// Two lobes: the droplets' strong forward peak, a little back scatter.
	// (E / pi) / 4 x the phase: single scattering; x1.6 for the light
	// scattered more than once.
	vec3 sun = vec3(1.0, 0.95, 0.86) * field_sun.w * 0.25 * 1.6 * (n > 2 ? 0.8 * hg(c, 0.75) + 0.2 * hg(c, -0.2) : hg(c, 0.6)) * lit;
	// Its underside darker where it lowers toward the updraft, in broad
	// soft swirls turning with the mesocyclone.
	vec2 rel = pm - field_meso.xy;
	float r = length(rel);
	float sw = n > 2 ? nzl(rot(rel, -field_meso.w * 0.4), 9000.0, 0.0) : 0.5;
	float under = (0.92 + 0.16 * sw) * (1.0 - 0.15 * (1.0 - smoothstep(1500.0, 5000.0, r)));
	vec3 l = vec3(0.0);
	float tr = 1.0;
	float tw = 0.0;
	float tsum = 0.0;
	float hprev = field_cloud.x - 250.0;
	// Two slices (Medium): the base and one close over it, so its rim is a
	// soft double edge rather than a second shelf.
	float sp = n > 2 ? 1.2 : 3.0;
	for (int i = n > 2 ? -1 : 0; i < n; i++) {
		float k = float(i) / float(n);
		float h = i < 0 ? field_cloud.x - 160.0 : field_cloud.x + CLOUD_T * 0.85 * pow(max(k, 0.0), sp);
		float hn = field_cloud.x + CLOUD_T * 0.85 * pow(float(i + 1) / float(n), sp);
		float ts = (h - ey) / d.y;
		if (ts > 60000.0) {
			break;
		}
		vec3 x = eye + d * ts;
		float cov;
		float rain;
		float det;
		// The footprint on the slice: a pixel stretched along the view by
		// 1 / sin(elevation), so grazing rims blur (and do not alias).
		float dens = cloud_at(x.xz, h, ts * PIX / max(d.y, 0.1), n > 2 ? 1 : 0, cov, rain, det);
		if (i < 0) {
			dens *= rain;
		}
		if (dens > 0.0) {
			float f = clamp((h - field_cloud.x) / CLOUD_T, 0.0, 1.0);
			// The slice's thickness along the ray (the base's own: what lies
			// over its flat bottom up to the next slice).
			// Its extinction follows its density as it tapers (Beer-Lambert:
			// against the bright sky, 4 stops over it, the fringe darkens the
			// sky only as its optical depth climbs from ~1 to ~4, so a
			// linear taper spreads that over the widest band).
			// Its slant path through the slice (at most 300 m of it, 550 m
			// for Medium's deep upper slice: the rim is thinner than they
			// are), but no longer than at 20 degrees: a fringe seen edge-on
			// is thinner than the slice.
			float a = 1.0 - exp(-CLOUD_SIG * dens * min(hn - max(h, hprev), n > 2 ? 300.0 : 550.0) / max(d.y, 0.34));
			// Lumpy underneath: darker where the cloud over it is thicker.
			vec3 s = sh * (base_k * under * (1.25 - 0.5 * det) * (0.8 + 0.2 * dens) + 1.2 * f + 0.5 * (1.0 - cov)) * mix(1.0, 0.8, rain);
			// What lies behind a nearly opaque cloud fades out before the
			// early exit (no step where the exit cuts in).
			l += tr * a * s * smoothstep(0.02, 0.08, tr);
			tw += tr * a;
			tsum += tr * a * ts;
			tr *= 1.0 - a;
			if (tr < 0.02) {
				break;
			}
		}
		hprev = h;
	}
	tf = tw > 1e-4 ? tsum / tw : 1e9;
	tr *= smoothstep(0.02, 0.08, tr);
	// Its thin rim, taken whole along the ray (so no slice's own edge shows
	// as a bright line): the bright sky beyond it scattered forward through
	// it, so the fringe takes the sky's light and dissolves into it, and
	// toward the sun its forward lobe, the silver lining (deep inside the
	// light crosses kilometres of cloud; only the half-transparent fringe
	// lets it through). Zero where the cloud is clear or opaque.
	l += (bg * 0.45 + sun * 0.012) * (1.0 - tr) * tr * 2.0;
	return vec4(l, tr);
}

// The flanking line: the towering cumulus stepping down south-west from the
// main updraft along the rear flank (Doswell & Burgess 1993; Bluestein
// 2013), seen beyond the base's western rim. A vertical sheet along it, met
// analytically: its towers' outline a 2D field (cauliflower tops, flat
// bases, gaps between them), their optical depth the line's width along the
// ray. Lit by the storm's shade from below, the bright sky round it, and the
// sun from behind and to the right through their thin edges (silver). q: 0
// skips the fine octave. rgb: its light, a: its opacity; t: its distance.
vec4 flank_line(vec3 eye, vec3 d, float ey, vec3 bg, int q, out float t) {
	const vec2 FD = vec2(-0.7071, 0.7071);
	const vec2 FN = vec2(0.7071, 0.7071);
	float dn = dot(d.xz, FN);
	t = dot(field_meso.xy - eye.xz, FN) / (abs(dn) > 1e-4 ? dn : 1e-4);
	if (t <= 0.0 || t > 30000.0) {
		return vec4(0.0);
	}
	vec3 x = eye + d * t;
	float u = dot(x.xz - field_meso.xy, FD);
	float h = x.y - FIELD_Y - field_cloud.x;
	if (u < 1500.0 || u > 17000.0 || h < -50.0 || h > 7500.0) {
		return vec4(0.0);
	}
	float fp = t * PIX;
	// Towers ~2.6 km apart, stepping down away from the updraft (each its
	// own height and width, hashed): domed tops, steep sides, flat bases;
	// their outline lumped by the noise (cauliflower). depth: how far inside
	// the nearest one (0 at its edge, 1 at its axis).
	float n = nzl(vec2(u, h) + vec2(1700.0, 0.0), 1800.0, fp);
	if (q > 0) {
		n = n * 0.8 + 0.2 * nzl(vec2(u, h) * 1.1 + 900.0, 600.0, fp);
	}
	float k0 = floor(u / 2600.0);
	float depth = 0.0;
	for (int j = -1; j < 2; j++) {
		float k = k0 + float(j);
		float hk = field_hash(vec2(k, 3.1));
		float ht = 6400.0 * (1.0 - k * 2600.0 / 19000.0) * (0.4 + 0.7 * hk);
		float wk = ht * (0.4 + 0.25 * field_hash(vec2(k, 7.7))) + 300.0;
		float uk = (k + 0.5 + 0.25 * (field_hash(vec2(k, 1.3)) - 0.5)) * 2600.0;
		// A dome: half an ellipse, wider at its foot, its edge lumped.
		vec2 e = vec2((u - uk) / (wk * (1.0 + 0.25 * clamp(1.0 - h / ht, 0.0, 1.0))), max(h, 0.0) / ht);
		depth = max(depth, (1.0 - length(e)) * 2.5 + (n - 0.5) * 1.2);
	}
	float c = smoothstep(0.0, 0.35, depth)
			* pow(smoothstep(-300.0, 1100.0, h + (n - 0.5) * 400.0), 2.0)
			* smoothstep(1500.0, 3500.0, u) * (1.0 - smoothstep(13000.0, 17000.0, u));
	depth = clamp(depth, 0.0, 1.0);
	float tau = 0.005 * c * 2400.0 / max(abs(dn) / max(length(d.xz), 1e-3), 0.3);
	float a = 1.0 - exp(-tau);
	if (a < 0.002) {
		return vec4(0.0);
	}
	float f = clamp(h / 6000.0, 0.0, 1.0);
	float cs = dot(d, field_sun.xyz);
	vec3 sun = vec3(1.0, 0.95, 0.86) * field_sun.w * 0.25 * 1.6 * (0.8 * hg(cs, 0.75) + 0.2 * hg(cs, -0.2))
			* field_lit_sky(x.xz, h + field_cloud.x, q > 0);
	// Backlit: grey-blue inside, the sky's light in its sides, the sun's
	// forward lobe blazing through its thin edges.
	vec3 l = (field_light.rgb * (base_k + 1.6 * f) * (1.25 - 0.5 * depth) + bg * 0.14 * (1.0 - 0.7 * depth)) * (0.7 + 0.6 * n)
			+ sun * exp(-7.0 * depth);
	return vec4(l, a);
}

// The wall cloud: the base lowered round the mesocyclone, turning, hanging
// lowest in its middle (where the funnel comes out of it). Its optical depth
// along the chord the ray cuts through it, dense in its middle, thinning to
// a ragged, soft rim and foot (scud hanging from it); its top is the base.
// rgb: its light, a: its opacity; tw: its distance.
vec4 wall_cloud(vec3 eye, vec3 d, float ey, out float tw) {
	vec2 o = eye.xz - field_meso.xy;
	float a2 = max(dot(d.xz, d.xz), 1e-6);
	tw = -dot(o, d.xz) / a2;
	vec2 cp = o + d.xz * tw;
	float b = length(cp);
	float yw = ey + d.y * tw;
	float u = (yw - field_cloud.x + FIELD_WALL_DROP) / FIELD_WALL_DROP;
	if (tw <= 0.0 || b > FIELD_WALL_R0 * 1.3 || u < -0.9 || u > 1.1) {
		return vec4(0.0);
	}
	float rw = mix(FIELD_WALL_R1, FIELD_WALL_R0, smoothstep(0.0, 1.0, u));
	// Its face: where the ray meets it, in arc length round it (from the
	// side facing you, so the seam is behind it) and height, turning with
	// the mesocyclone.
	vec2 face = cp - d.xz / sqrt(a2) * sqrt(max(rw * rw - b * b, 0.0));
	vec2 te = -o / max(length(o), 1.0);
	float arc = (atan(te.x * face.y - te.y * face.x, dot(te, face)) + atan(te.y, te.x) - field_meso.w * 1.2) * rw;
	float fp = tw * PIX;
	float nn = nzl(vec2(arc, yw), 2200.0, fp) * 0.7 + nzl(vec2(arc, yw) * 1.1 + 311.0, 700.0, fp) * 0.3;
	float x = b / (rw * (1.0 + 0.3 * (nn - 0.5)));
	float chord = 2.0 * rw * sqrt(max(1.0 - x * x, 0.0));
	float core = 1.0 - smoothstep(0.55, 1.05, x);
	float foot = smoothstep(-0.35, 0.4, u + 0.35 * (1.0 - x) + (nn - 0.5) * 0.6) * smoothstep(-0.9, -0.4, u);
	float tau = 0.004 * chord * core * foot;
	// Its top fades out over its last ~150 m into the base behind it (no
	// outline of the drum's top against the base).
	float a = (1.0 - exp(-tau)) * (1.0 - smoothstep(0.7, 1.0, u + (nn - 0.5) * 0.3));
	// The base's own light carried down, darker toward its foot (thicker
	// cloud over it), brighter at its thin rim (the light round it).
	vec3 wl = field_light.rgb * base_k * mix(wall_k / base_k, 1.0, smoothstep(0.0, 1.0, u)) * (0.8 + 0.4 * nn)
			* (1.0 + 0.6 * (1.0 - core) * (1.0 - smoothstep(0.5, 1.0, u))) * 0.85;
	return vec4(wl, a);
}

void sky() {
	vec3 d = EYEDIR;
	vec3 eye = POSITION;
	float ey = eye.y - FIELD_Y;
	vec3 col;
	float dist = 40000.0;
	int n = AT_CUBEMAP_PASS ? 4 : steps;
	if (d.y < -0.0004) {
		// The ground beyond the mesh (the land is flat out there): the
		// storm's shade, the sun where it gets under the storm.
		dist = min(ey / -d.y, 40000.0);
		vec2 g = eye.xz + d.xz * dist;
		float lit = field_lit(g, 0.0);
		vec3 e = field_shade_at(g) * 1.3 + vec3(field_sun.w) * vec3(1.0, 0.95, 0.85) * field_sun.y * lit;
		col = e * ground_albedo * (0.8 + 0.4 * oct(g, 900.0, dist, 30.0));
	} else {
		float el = clamp(d.y, 0.0, 1.0);
		col = mix(clear_horizon, clear_zenith, pow(el, 0.45));
		float ph = field_phase(dot(d, field_sun.xyz));
		col += field_sunair.rgb * ph * 0.25 * (1.0 - el);
		if (d.y > 0.0005) {
			// The anvil: smooth, its edge ragged, mammatus hanging near it.
			float ta = (field_cloud.y - ey) / d.y;
			if (ta < 120000.0) {
				vec2 pa = eye.xz + d.xz * ta;
				float ca = field_anvil_cover(pa);
				float m = oct(pa, 1400.0, ta, 8.0);
				float mam = smoothstep(0.35, 0.95, ca) * (1.0 - smoothstep(0.95, 1.0, ca) * 0.6);
				vec3 al = field_light.rgb * anvil_k * (0.75 + 0.5 * oct(pa, 5200.0, ta, 12.0)) * mix(1.0, 0.55 + 0.9 * m * m, mam * 0.6);
				// Its thin edge glows where the sun is behind it.
				al += field_sunair.rgb * ph * 0.35 * (1.0 - ca) * smoothstep(0.0, 0.3, ca);
				col = mix(col, al, ca);
				dist = mix(dist, min(dist, ta), smoothstep(0.3, 0.7, ca));
			}
		}
		// The flanking line beyond the base's rim (High and up).
		if (cloud_steps > 2) {
			float tl;
			vec4 fl = flank_line(eye, d, ey, col, 1, tl);
			col = mix(col, fl.rgb, fl.a);
			dist = mix(dist, min(dist, tl), fl.a);
		}
		// The cloud mass: the base, its flanks, the core's cloud.
		float tf;
		vec4 cm = cloud_march(eye, d, ey, AT_CUBEMAP_PASS ? min(cloud_steps, 2) : cloud_steps, col, tf);
		col = col * cm.a + cm.rgb;
		// The air beyond shows only through what the cloud lets through:
		// weighted by its transmittance squared, so a nearly opaque base
		// does not leak kilometres of bright sunlit haze into its colour.
		dist = mix(min(dist, tf), dist, cm.a * cm.a);
		// The wall cloud.
		float tw;
		vec4 wc = wall_cloud(eye, d, ey, tw);
		col = mix(col, wc.rgb, wc.a);
		dist = mix(dist, min(dist, tw), wc.a);
		// Inflow scud: ragged wisps ~450 m up racing in under the base
		// toward the wall cloud, lit a little brighter than the base.
		if (d.y > 0.002) {
			float ts = (450.0 - ey) / d.y;
			if (ts < 25000.0) {
				vec2 ps = eye.xz + d.xz * ts;
				vec2 flow = ps + field_wind.xy * TIME * 1.6;
				float k = oct(flow, 520.0, ts, 10.0) * 0.7 + oct(flow, 140.0, ts, 8.0) * 0.3;
				float near = (1.0 - smoothstep(2500.0, 7000.0, length(ps - field_meso.xy))) * field_base_cover(ps);
				float cs = smoothstep(0.58, 0.85, k) * near * 0.8 * (1.0 - smoothstep(6000.0, 12000.0, ts));
				col = mix(col, field_shade_at(ps) * (0.55 + 0.4 * k), cs);
			}
		}
	}
	vec4 air = field_air(eye, d, dist, n);
	col = col * air.a + air.rgb;
	col += lucid_lightning_sky(d);
	COLOR = col * lucid_exposure.rgb;
}
