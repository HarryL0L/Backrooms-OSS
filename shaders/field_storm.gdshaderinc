// The Field's supercell (FieldStorm, docs/FIELD_STORM.md): what the sky, the
// ground, the grass, the tornado and the rain share, so the wind, the rain
// and the light are one field everywhere. Distances in metres, the world's
// xz; heights over the Field's datum (FIELD_Y). Radiances in L.U.C.I.D.
// engine units (cd/m2 / 153.6) before the camera's exposure.
// FieldStorm.wind_at() / rain_at() are the GDScript copies (the rain's
// rate and slant, the sound): keep them the same.

const float FIELD_Y = -2000.0;

// The camera's exposure (L.U.C.I.D.), unless lucid_city.gdshaderinc (which
// declares it) came first: then define FIELD_HAS_LUCID before this.
#ifndef FIELD_HAS_LUCID
global uniform vec4 lucid_exposure;
#endif

// xy: the mean wind at 2 m (m/s, the storm's inflow), z: how far the air
// has moved (m: the gusts ride on it), w: how wet everything is (0 .. 1).
global uniform vec4 field_wind;
// A rain band sweeping over the field: xy a point on its axis, z the
// direction it moves (rad), w its peak rate (mm/h).
global uniform vec4 field_band;
// The precipitation core: xy its centre, z its radius (m), w its peak rate.
global uniform vec4 field_core;
// The mesocyclone: xy its centre (the tornado's wall cloud), z the
// tornado's presence (0 .. 1), w how far it has turned (rad).
global uniform vec4 field_meso;
// Toward the sun (unit).
global uniform vec4 field_sun;
// rgb: the air and the sky under the storm in its shade (engine units),
// a: the haze's extinction (1/m).
global uniform vec4 field_light;
// rgb: what sunlit air adds (engine units, at the phase function's mean).
global uniform vec4 field_sunair;
// x: the base's height, y: the anvil's, z: the base's radius, w: the anvil's.
global uniform vec4 field_cloud;
// xy: the base's centre, zw: the anvil's.
global uniform vec4 field_cloud_c;

// A rain band's half width (m) and half length, how far its gust front runs ahead of it
// (m), the outflow behind that front (m/s).
const float FIELD_BAND_W = 1400.0;
const float FIELD_BAND_L = 3200.0;   // its length (1/e half, along it)
const float FIELD_BAND_A = -1800.0;  // its middle off your line (east of you)
const float FIELD_FRONT = 2600.0;
const float FIELD_OUTFLOW = 17.0;
// Turbulence intensity (gust spread / mean) in the inflow and the outflow.
const float FIELD_TI_IN = 0.32;
const float FIELD_TI_OUT = 0.5;
// The rear flank's rain wrapping round the tornado: its offset from the
// mesocyclone (m), radius, rate (mm/h).
const vec2 FIELD_HOOK = vec2(900.0, 500.0);
const float FIELD_HOOK_R = 1400.0;
const float FIELD_HOOK_RATE = 7.0;
// The storm's tower (the updraft column, which shades the field from the
// sun behind it): offset from the mesocyclone, radius, top (m).
const vec2 FIELD_TOWER = vec2(-950.0, -2400.0);
const float FIELD_TOWER_R = 5200.0;
const float FIELD_TOWER_TOP = 13000.0;
// The wall cloud: radius at the base, at its foot, how far it hangs (m).
const float FIELD_WALL_R0 = 1500.0;
const float FIELD_WALL_R1 = 1050.0;
const float FIELD_WALL_DROP = 600.0;

float field_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float field_vnoise(vec2 q) {
	vec2 i = floor(q);
	vec2 f = fract(q);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(field_hash(i), field_hash(i + vec2(1.0, 0.0)), f.x),
			mix(field_hash(i + vec2(0.0, 1.0)), field_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

vec2 field_band_n() {
	return vec2(cos(field_band.z), sin(field_band.z));
}

// Rain (mm/h) falling at p: the core, the hook round the tornado, the band
// (cells along it).
float field_rain_at(vec2 p) {
	// Rain shafts have edges: each cell falls off to nothing at its rim.
	float r = field_core.w * (1.0 - smoothstep(0.25, 1.0, length(p - field_core.xy) / field_core.z));
	r += FIELD_HOOK_RATE * (1.0 - smoothstep(0.2, 1.0, length(p - field_meso.xy - FIELD_HOOK) / FIELD_HOOK_R));
	vec2 n = field_band_n();
	vec2 q = p - field_band.xy;
	float s = dot(q, n);
	float along = dot(q, vec2(-n.y, n.x));
	float cells = (0.62 + 0.38 * sin(along * 0.0019 + 1.3) * sin(along * 0.00071 + s * 0.0011 + 0.4))
			* exp(-(along - FIELD_BAND_A) * (along - FIELD_BAND_A) / (FIELD_BAND_L * FIELD_BAND_L));
	return r + field_band.w * exp(-s * s / (FIELD_BAND_W * FIELD_BAND_W)) * cells;
}

// The rain's extinction (1/m): Marshall-Palmer drops' geometric cross
// section (LucidRain.sigma).
float field_rain_sigma(float r) {
	if (r < 0.05) {
		return 0.0;
	}
	float l = 4.1 * pow(r, -0.21);
	return 0.0125664 / (l * l * l);
}

// The mean wind at p (m/s at 2 m): the inflow, turned to the band's cold
// outflow behind its gust front. w: how far into the outflow (0 .. 1).
vec3 field_wind_mean(vec2 p) {
	vec2 n = field_band_n();
	float s = dot(p - field_band.xy, n);
	float o = smoothstep(FIELD_BAND_W * 0.2 + FIELD_FRONT, FIELD_BAND_W * 0.2, s)
			* smoothstep(-3.5 * FIELD_BAND_W, -0.8 * FIELD_BAND_W, s) * clamp(field_band.w / 25.0, 0.0, 1.0);
	return vec3(mix(field_wind.xy, n * FIELD_OUTFLOW, o), o);
}

// The wind at p (m/s at 2 m): the mean times its gusts, which are waves
// riding on the air at its own speed (Taylor's frozen turbulence: gust
// fronts sweep across the grass at the wind speed), 14-85 m long, mostly
// across the wind, in packets ~420 m apart. z: the gust factor.
vec3 field_wind_at(vec2 p) {
	vec3 m = field_wind_mean(p);
	float sp = length(m.xy);
	vec2 d = sp > 0.01 ? m.xy / sp : vec2(1.0, 0.0);
	vec2 e = vec2(-d.y, d.x);
	float x = field_wind.z;
	float g = 0.5 * sin(dot(d, p) * 0.0739 - x * 0.0739 + 0.3)
			+ 0.3 * sin(dot(d * 0.94 + e * 0.34, p) * 0.1337 - x * 0.1337 + 2.1)
			+ 0.2 * sin(dot(d * 0.96 - e * 0.3, p) * 0.2417 - x * 0.2417 + 4.0)
			+ 0.12 * sin(dot(d * 0.83 + e * 0.56, p) * 0.4488 - x * 0.4488 + 5.3);
	float env = 0.5 + 0.5 * sin(dot(d, p) * 0.01496 - x * 0.01496 + 0.7);
	float ti = mix(FIELD_TI_IN, FIELD_TI_OUT, m.z);
	float k = max(1.0 + ti * g * (0.5 + env), 0.15);
	return vec3(m.xy * k, k);
}

// A cloud layer's cover at p: a disc with a ragged edge.
float field_disc(vec2 p, vec2 c, float r, float rag) {
	float n = field_vnoise(p * 0.00032) * 0.62 + field_vnoise(p * 0.0011 + 7.0) * 0.38;
	return 1.0 - smoothstep(r * (1.0 - rag), r * (1.0 + rag * 0.4), length(p - c) + (n - 0.5) * r * rag * 1.6);
}

float field_base_cover(vec2 p) {
	return field_disc(p, field_cloud_c.xy, field_cloud.z, 0.2);
}

float field_anvil_cover(vec2 p) {
	return field_disc(p, field_cloud_c.zw, field_cloud.w, 0.18);
}

// Sunlight reaching p at height y (0 .. 1) past the storm's tower; with
// anvil, under the anvil too (not the base: the sky's cloud shades itself).
float field_lit_sky(vec2 p, float y, bool anvil_too) {
	vec3 s = field_sun.xyz;
	float sl = max(length(s.xz), 1e-3);
	vec2 sd = s.xz / sl;
	float tn = s.y / sl;
	vec2 c = field_meso.xy + FIELD_TOWER - p;
	float tc = dot(c, sd);
	float b = length(c - sd * tc);
	float tower = 0.0;
	if (b < FIELD_TOWER_R * 1.1) {
		float ti = tc - sqrt(max(FIELD_TOWER_R * FIELD_TOWER_R - b * b, 0.0));
		if (tc + FIELD_TOWER_R > 0.0) {
			tower = (1.0 - smoothstep(FIELD_TOWER_R * 0.8, FIELD_TOWER_R * 1.1, b))
					* (1.0 - smoothstep(FIELD_TOWER_TOP * 0.8, FIELD_TOWER_TOP, y + max(ti, 0.0) * tn));
		}
	}
	if (!anvil_too) {
		return 1.0 - tower;
	}
	float anvil = field_anvil_cover(p + sd * max(field_cloud.y - y, 0.0) / tn);
	return (1.0 - tower) * (1.0 - anvil * 0.92);
}

// Sunlight reaching p at height y (0 .. 1): not behind the storm's tower,
// nor under the base's or the anvil's shadow.
float field_lit(vec2 p, float y) {
	vec3 s = field_sun.xyz;
	float sl = max(length(s.xz), 1e-3);
	float base = field_base_cover(p + s.xz / sl * max(field_cloud.x - y, 0.0) / (s.y / sl));
	return field_lit_sky(p, y, true) * (1.0 - base);
}

// The air's own light at p in the shade: brighter where no base hangs
// over it (only the thinner anvil), darker in the core's rain.
vec3 field_shade_at(vec2 p) {
	float under = field_base_cover(p);
	vec2 dc = p - field_core.xy;
	float core = exp(-dot(dc, dc) / (field_core.z * field_core.z * 1.6));
	float rain = field_rain_at(p);
	vec3 l = field_light.rgb * (1.0 + 1.4 * (1.0 - under)) * (1.0 - 0.5 * smoothstep(2.0, 45.0, rain));
	// The core's faint green (deep cloud and rain over it).
	return mix(l, l * vec3(0.86, 1.0, 0.88), core * 0.8);
}

// Henyey-Greenstein, g 0.55, normalised to a mean of 1 over the sphere.
float field_phase(float c) {
	const float G = 0.55;
	return (1.0 - G * G) / pow(1.0 + G * G - 2.0 * G * c, 1.5);
}

// The air between the eye and dist along dir (Koschmieder, by steps): the
// haze and the rain's extinction, lit by the shade or the sun where it is.
// jitter (0 .. 1): where in each step it is sampled (0.5 the middle; the
// sky dithers it per pixel so no step edges show). rgb: the airlight, a:
// the transmittance.
vec4 field_air(vec3 eye, vec3 dir, float dist, int steps, float jitter) {
	float ph = field_phase(dot(dir, field_sun.xyz));
	vec3 l = vec3(0.0);
	float t = 1.0;
	float prev = 0.0;
	const float K = 3.0;
	float ek = exp(K) - 1.0;
	vec2 wd = field_wind.xy / max(length(field_wind.xy), 0.1);
	// Step ends at dist (e^(K i / steps) - 1) / (e^K - 1), by products.
	float er = exp(K / float(steps));
	float ej = exp(K * jitter / float(steps));
	float e0 = 1.0;
	for (int i = 1; i <= steps; i++) {
		float s = dist * (e0 * er - 1.0) / ek;
		float mid = dist * (e0 * ej - 1.0) / ek;
		e0 *= er;
		vec3 q = eye + dir * mid;
		float y = q.y - FIELD_Y;
		// The rain hangs from the cloud: it thins into the base's soft
		// bottom over its last few hundred metres instead of ending at a line.
		float top = smoothstep(field_cloud.x + 150.0, field_cloud.x - 350.0, y);
		float rain = top > 0.0 ? field_rain_at(q.xz) * top : 0.0;
		// Rain shafts: soft streaks in the world (~600 m across, kilometres
		// tall, leaning a little downwind), at low contrast; they average
		// out along the ray, so the curtain stays a veil.
		float shaft = field_vnoise(vec2(dot(q.xz, vec2(-wd.y, wd.x)) * 0.0016 + y * 0.0004, y * 0.0003 + 7.0));
		float sr = field_rain_sigma(rain) * mix(1.0, 0.7 + 0.6 * shaft, smoothstep(1500.0, 5000.0, mid));
		float sh = field_light.a * exp(-max(y, 0.0) / 2500.0);
		float sig = sh + sr;
		float tr = exp(-sig * (s - prev));
		// Sunlit air: the haze's forward lobe (the sun's colour) and the
		// air's own Rayleigh blue all round.
		vec3 src = field_shade_at(q.xz) + field_sunair.rgb * (ph + vec3(0.16, 0.26, 0.5)) * field_lit(q.xz, y);
		l += t * (1.0 - tr) * src;
		t *= tr;
		prev = s;
	}
	return vec4(l, t);
}
