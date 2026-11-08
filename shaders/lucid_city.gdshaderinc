// L.U.C.I.D. stage 3: what every city shader shares (docs/LUCID.md).
//
// Values are scene-referred engine units (luminance / 153.6 cd/m2, see
// Lucid.UNIT_NITS) until lucid_finish(), which adds the air between the
// surface and the eye (Koschmieder: transmittance exp(-sigma d), the rest
// is the horizon's airlight), applies the eye's night shift (mesopic
// Purkinje shift, Lucid.night_shift) on the absolute luminance, then the
// camera's exposure and white balance (lucid_exposure).

#include "res://shaders/lucid_spec.gdshaderinc"

global uniform vec4 lucid_exposure;   // rgb: 2^(7 - EV100) x white balance gains
global uniform vec4 lucid_sky;        // x: state blend (0 = A, 1 = B), y: night vision, z: lamp level, w: haze
global uniform vec4 lucid_air;        // rgb: horizon airlight (engine units), a: extinction (1/m)
// The sky now (state-blended, engine units): rgb radiance; zenith.a = h0,
// glow.a unused, glow_dir.xyz toward the twilight glow.
global uniform vec4 lucid_sky_zenith;
global uniform vec4 lucid_sky_horizon;
global uniform vec4 lucid_sky_glow;
global uniform vec4 lucid_sky_glow_dir;

const float LUCID_UNIT_NITS = 153.6;
const vec3 LUCID_SCOTOPIC = vec3(0.706, 0.990, 1.966);

float lucid_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float lucid_hash3(vec3 p) {
	return lucid_hash(p.xy + vec2(p.z * 17.13, p.z * 3.71));
}

// The eye's night shift (see Lucid.mesopic / Lucid.scotopic).
vec3 lucid_mesopic(vec3 c) {
	float k = lucid_sky.y;
	if (k <= 0.0) {
		return c;
	}
	float x = dot(c, vec3(0.4124, 0.3576, 0.1805));
	float y = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float z = dot(c, vec3(0.0193, 0.1192, 0.9505));
	float nits = max(y * LUCID_UNIT_NITS, 1e-6);
	float s = k * clamp((0.69897 - log(nits) * 0.4342945) / 3.0, 0.0, 1.0);
	float v = max(y * (1.33 * (1.0 + (y + z) / max(x, 1e-9)) - 1.68) / 2.576, 0.0);
	return mix(c, LUCID_SCOTOPIC * v, s);
}

// Air between the eye and a point d metres away.
vec3 lucid_air_light(vec3 c, float d) {
	float t = exp(-lucid_air.a * d);
	return c * t + lucid_air.rgb * (1.0 - t);
}

// Scene-referred engine units -> the value for the frame buffer (AgX after).
vec3 lucid_finish(vec3 c, float d) {
	return lucid_mesopic(lucid_air_light(c, d)) * lucid_exposure.rgb;
}

// Stage 4: the haze lit by the four nearest street lamps (globals
// lucid_glow0..3: xyz the lens (world), w its peak intensity as engine
// units of E / pi at 1 m, positive an LED head, negative a sodium head;
// lucid_glow_led / _na their colours). Single scattering along the view
// ray from the eye to the point d away, for a point source of intensity
// I0 cos^1.2 (taken at the ray's closest point, h from the lamp) in air of
// scattering coefficient 0.9 x the extinction (urban aerosol, albedo 0.9),
// with a Henyey-Greenstein phase (g = 0.6):
//   L = sigma_s I p (atan((d - tc) / h) + atan(tc / h)) / h
// (the extinction over a few tens of metres, under 1 %, is left out). As
// strong as the real haze makes it: at 12 km visibility a faint glow a
// metre or so round each head, no halo beyond.
global uniform vec4 lucid_glow0;
global uniform vec4 lucid_glow1;
global uniform vec4 lucid_glow2;
global uniform vec4 lucid_glow3;
global uniform vec4 lucid_glow_led;
global uniform vec4 lucid_glow_na;

vec3 lucid_glow_one(vec4 g, vec3 cam, vec3 vd, float d) {
	if (g.w == 0.0) {
		return vec3(0.0);
	}
	vec3 lc = g.xyz - cam;
	float tc = dot(lc, vd);
	vec3 pc = vd * tc - lc;                  // from the lamp to the closest point
	float h = max(length(pc), 0.15);
	float ce = max(-pc.y / h, 0.0);          // emission angle (heads look down)
	vec3 ld = pc / h;
	float cs = dot(ld, -vd);                 // scattering angle: toward the eye
	const float G = 0.6;
	float ph = (1.0 - G * G) / (4.0 * 3.14159265 * pow(1.0 + G * G + 2.0 * G * cs, 1.5));
	float ang = atan((d - tc) / h) + atan(tc / h);
	return (g.w > 0.0 ? lucid_glow_led.rgb : lucid_glow_na.rgb) * (abs(g.w) * pow(ce, 1.2) * ph * ang / h);
}

vec3 lucid_airglow(vec3 wpos, vec3 cam) {
	vec3 dv = wpos - cam;
	float d = length(dv);
	vec3 vd = dv / max(d, 1e-4);
	vec3 s = lucid_glow_one(lucid_glow0, cam, vd, d) + lucid_glow_one(lucid_glow1, cam, vd, d)
			+ lucid_glow_one(lucid_glow2, cam, vd, d) + lucid_glow_one(lucid_glow3, cam, vd, d);
	// x pi: engine intensity is I0 / (pi UNIT_NITS).
	return s * (0.9 * lucid_air.a * 3.14159265);
}

// lucid_finish for a point at wpos seen from cam, with the lamps' airglow.
// cap: lucid_capturing(PROJECTION_MATRIX); a probe captures engine units
// (no airglow, night shift or exposure: the surface that mirrors it adds
// those along its own view).
vec3 lucid_finish_at(vec3 c, vec3 wpos, vec3 cam, float cap) {
	float d = length(wpos - cam);
	if (cap > 0.5) {
		return lucid_air_light(c, d);
	}
	return lucid_mesopic(lucid_air_light(c, d) + lucid_airglow(wpos, cam)) * lucid_exposure.rgb;
}

// The physical sky (Lucid.sky_nits): zenith, horizon excess fading with
// elevation over h0, a twilight glow toward glow_dir. Radiances in cd/m2.
vec3 lucid_sky_nits(vec3 dir, vec3 zen, vec3 hor, vec3 glow, vec3 glow_dir, float h0) {
	float h = asin(clamp(dir.y, -1.0, 1.0));
	float t = exp(-max(h, 0.0) / h0);
	vec3 c = zen + (hor - zen) * t;
	vec2 f = dir.xz;
	float fl = length(f);
	if (fl > 1e-4) {
		float ca = max(dot(f / fl, normalize(glow_dir.xz)), 0.0);
		c += glow * (ca * ca * ca * ca * t);
	}
	return c;
}

// The sky now along dir (engine units).
vec3 lucid_sky_now(vec3 dir) {
	return lucid_sky_nits(dir, lucid_sky_zenith.rgb, lucid_sky_horizon.rgb, lucid_sky_glow.rgb,
			lucid_sky_glow_dir.xyz, max(lucid_sky_zenith.a, 0.01));
}

// What a window or a glass wall mirrors along r: the sky above, and
// below a few degrees the city itself, its mean luminance with the speckle
// of its lit windows (hashed on the reflected direction), so glass at night
// shows other buildings' lights. `city`: the city's mean radiance near the
// horizon (engine units).
vec3 lucid_reflection(vec3 r, vec3 city) {
	vec3 sky = lucid_sky_now(r);
	float below = smoothstep(0.12, -0.02, r.y);
	vec2 a = vec2(atan(r.x, r.z) * 28.0, r.y * 70.0);
	float sp = step(0.8, lucid_hash(floor(a))) * 1.6;
	return mix(sky, city * (0.6 + sp), below);
}

// Fresnel (Schlick) for a dielectric of reflectance f0 at cos theta.
float lucid_fresnel(float f0, float c) {
	float m = 1.0 - clamp(c, 0.0, 1.0);
	float m2 = m * m;
	return f0 + (1.0 - f0) * m2 * m2 * m;
}

// ------------------------------------------------------- the street grid ---
// The city's plan (LucidCity.GRID, the same numbers): avenues along Z every
// 110 m (carriageway +-9.5 m, building line +-15 m), streets along X every
// 80 m (+-6 m, +-10 m). Road paint (retro-reflective, aged): white lane
// lines, stop lines and crosswalks at every corner, yellow centre lines.
// Returns the white paint's coverage at p (metres, ground plane) and the
// yellow's in `yellow`, box-filtered over the pixel's footprint w (metres
// per pixel along x and z: fwidth(p)), so a line seen down the road stays
// sharp across and its dashes do not crawl, and far off it fades to its
// mean coverage instead of a bright band.
float lucid_stripe(float x, float c, float half_w, float w) {
	float d = abs(x - c);
	w = max(w, 1e-4);
	return clamp((min(d + 0.5 * w, half_w) - max(d - 0.5 * w, -half_w)) / w, 0.0, 1.0);
}

// A pulse train (on where fract(x) < duty; x and the footprint w in
// periods), box-filtered: the difference of its integral across w.
float lucid_pulse(float x, float duty, float w) {
	w = max(w, 1e-4);
	float a = x - 0.5 * w;
	float b = x + 0.5 * w;
	float fa = floor(a) * duty + min(fract(a), duty);
	float fb = floor(b) * duty + min(fract(b), duty);
	return clamp((fb - fa) / w, 0.0, 1.0);
}

float lucid_zebra(float x, float w) {
	// 0.6 m bars on 1.2 m centres (centred on x = 0).
	return lucid_pulse(x / 1.2 - 0.25, 0.5, w / 1.2);
}

float lucid_road_paint(vec2 p, vec2 w, out float yellow) {
	float xa = p.x - round(p.x / 110.0) * 110.0;      // across the avenue
	float zs = p.y - round(p.y / 80.0) * 80.0;        // across the street
	float ax = abs(xa);
	float az = abs(zs);
	float paint = 0.0;
	yellow = 0.0;
	if (ax < 9.5 && az > 10.0) {
		// Avenue: dashed lane lines (3 m dash, 9 m gap: MUTCD 3A.06) at
		// +-3.5, the double yellow centre line (two 100 mm lines 100 mm
		// apart), the parking lane's 100 mm edge line, stop lines (0.4 m)
		// 1.2 m short of the crosswalk across the lanes coming towards the
		// crossing (traffic keeps right: the east half south of it).
		float dash = lucid_pulse(p.y / 12.0, 0.25, w.y / 12.0);
		paint = max(paint, lucid_stripe(ax, 3.5, 0.06, w.x) * dash);
		yellow = lucid_stripe(ax, 0.1, 0.05, w.x);
		paint = max(paint, lucid_stripe(ax, 7.0, 0.05, w.x));
		paint = max(paint, lucid_stripe(az, 11.0, 0.2, w.y) * step(ax, 7.0) * step(0.0, xa * zs));
	}
	if (az < 6.0 && ax > 15.0) {
		// Street: a dashed yellow centre line, the parking lanes' edge
		// lines, stop lines (the south half west of the crossing).
		float dash = lucid_pulse(p.x / 12.0, 0.25, w.x / 12.0);
		yellow = lucid_stripe(az, 0.0, 0.06, w.y) * dash;
		paint = max(paint, lucid_stripe(az, 3.5, 0.05, w.y));
		paint = max(paint, lucid_stripe(ax, 15.4, 0.2, w.x) * step(az, 3.5) * step(0.0, -xa * zs));
	}
	// Crosswalks (3 m, continental: 0.6 m bars on 1.2 m centres, along the
	// traffic) from curb to curb, round the corners' 4.5 m radius.
	float r = 4.5;
	if (az > 6.6 && az < 9.6 && ax < 9.5 + r - sqrt(max(r * r - (az - 10.5) * (az - 10.5), 0.0)) - 0.3) {
		paint = max(paint, lucid_zebra(xa, w.x));
	}
	if (ax > 10.6 && ax < 13.6 && az < 6.0 + r - sqrt(max(r * r - (ax - 14.0) * (ax - 14.0), 0.0)) - 0.3) {
		paint = max(paint, lucid_zebra(zs, w.y));
	}
	paint = max(paint - yellow, 0.0);
	return paint;
}
