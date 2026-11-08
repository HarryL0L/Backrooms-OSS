// L.U.C.I.D. stage 3: the physical night sky on a dome round the camera.
// The sky model (lucid_sky_now, Lucid.sky_nits) in real luminance; the
// moon as a disc of its real luminance (E_moon / 6.4e-5 sr, so the
// directional light and the disc agree), with the aerosols' forward
// scattering round it (the aureole, ~5 % of its light within a few
// degrees); stars brighter than magnitude 3.5 as point sources of their
// real illuminance (2.54e-6 lux x 10^(-0.4 m)), dimmed by the air mass,
// spread over a pixel. Most of them drown in the city's glow, as they do.
// The storm (LucidStorm): the overcast deck at its base height (lucid_cloud),
// lit from below by the city: the sky model's luminance with the deck's soft
// structure (a few octaves of value noise on the plane of its base,
// drifting with the wind, faded to their mean where they near the pixel),
// brighter over the two downtowns and darker over the river, all seen
// through the haze and the rain (Koschmieder: the structure fades into the
// airlight toward the horizon). It hides the stars and the moon. A flash
// lights a patch of it from inside (lucid_lightning_sky), showing the
// deck's lumps against the light.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
#include "res://shaders/lucid_city.gdshaderinc"

uniform vec3 moon_dir = vec3(0.0, 0.5, 0.8);
uniform vec3 moon_rad = vec3(0.0);      // disc radiance, engine units
uniform vec3 moon_e = vec3(0.0);        // its illuminance as E / pi, engine units (for the aureole)
uniform float stars = 1.0;
uniform vec4 downtown = vec4(-2350.0, -650.0, 700.0, -1350.0);  // the two downtowns (world x, z, x, z)
uniform vec2 river = vec2(-1700.0, -1450.0);                    // the river's banks (world x)
uniform vec2 drift = vec2(0.0);                                 // how far the deck has drifted (m)
uniform int octaves = 4;

float cloud_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(lucid_hash(i), lucid_hash(i + vec2(1.0, 0.0)), f.x),
			mix(lucid_hash(i + vec2(0.0, 1.0)), lucid_hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

// The deck's structure at p (metres on its base): about -0.5 .. 0.5, mean 0;
// octaves whose wavelength nears four footprints `foot` fade to their mean.
float cloud_fbm(vec2 p, float foot) {
	float a = 0.5;
	float s = 0.0;
	float n = 0.0;
	float f = 1.0 / 1400.0;
	mat2 rot = mat2(vec2(0.8, 0.6), vec2(-0.6, 0.8));
	for (int i = 0; i < 5; i++) {
		if (i >= octaves) {
			break;
		}
		s += a * (1.0 - smoothstep(0.12, 0.25, foot * f)) * (cloud_noise(p * f) - 0.5);
		n += a;
		p = rot * p + vec2(17.3, -9.1);
		f *= 2.6;
		a *= 0.55;
	}
	return s / max(n, 1e-3) * 1.6;
}

varying vec3 v_dir;

void vertex() {
	v_dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(v_dir);
	vec3 rad = lucid_sky_steady(dir);
	vec3 flash = lucid_lightning_sky(dir);
	float pix = max(length(fwidth(dir)), 1e-5);
	float cover = lucid_cloud.y;
	if (cover > 0.0 && dir.y > 0.0) {
		vec3 cam = CAMERA_POSITION_WORLD;
		float t = max(lucid_cloud.x - cam.y, 1.0) / max(dir.y, 0.002);
		vec2 p = cam.xz + dir.xz * t;
		float foot = pix * t / max(dir.y, 0.03);
		float tr = exp(-min((lucid_air.a + lucid_rain.w) * t, 60.0));
		float n = cloud_fbm(p + drift, foot);
		// The city under it: the two downtowns' towers send more light up,
		// the river none.
		vec2 d1 = (p - downtown.xy) / 1300.0;
		vec2 d2 = (p - downtown.zw) / 1300.0;
		float rc = (p.x - 0.5 * (river.x + river.y)) / (0.5 * (river.y - river.x) + 250.0);
		float under = 1.0 + 0.6 * (exp(-dot(d1, d1)) + exp(-dot(d2, d2))) - 0.35 * exp(-rc * rc);
		// Thicker lumps reflect more of it back down; a flash inside shows
		// them dark against its light.
		rad *= mix(1.0, max(1.0 + 1.3 * n, 0.3) * under, tr * cover);
		flash *= mix(1.0, max(1.0 - 0.9 * n, 0.2), tr * cover);
	}
	rad += flash;
	// The moon: 0.26 deg radius, a little limb darkening and dark maria.
	float cm = dot(dir, normalize(moon_dir));
	float th = acos(clamp(cm, -1.0, 1.0));
	float rm = 0.00454;
	if (th < rm * 1.5 + pix) {
		vec3 t1 = normalize(cross(moon_dir, vec3(0.0, 1.0, 0.0)));
		vec3 t2 = cross(t1, normalize(moon_dir));
		vec2 q = vec2(dot(dir, t1), dot(dir, t2)) / rm;
		float r = length(q);
		float disc = clamp((1.0 - r) * rm / pix + 0.5, 0.0, 1.0);
		float maria = 1.0 - 0.28 * smoothstep(0.5, 0.2, length(q - vec2(-0.25, 0.2))) - 0.2 * smoothstep(0.35, 0.1, length(q - vec2(0.3, -0.15)));
		rad += moon_rad * disc * maria * (0.85 + 0.15 * sqrt(max(1.0 - r * r, 0.0))) * (1.0 - cover);
	}
	// Aureole: E x 0.05 spread as exp(-theta / 0.035) (2 pi a^2 sr).
	rad += moon_e * 3.14159 * 0.05 * exp(-th / 0.035) / (6.2832 * 0.035 * 0.035) * step(0.0, moon_dir.y) * (1.0 - cover);
	if (stars * (1.0 - cover) > 0.0 && dir.y > 0.0) {
		float el = asin(dir.y);
		float az = atan(dir.x, -dir.z);
		vec2 cell = vec2(az, el) / 0.0174533;
		vec2 ci = floor(cell);
		float h = lucid_hash(ci + 17.0);
		if (h < 0.0073) {
			vec2 off = vec2(lucid_hash(ci + 3.1), lucid_hash(ci + 9.7));
			vec2 sp = (ci + 0.15 + 0.7 * off) * 0.0174533;
			vec3 sd = vec3(cos(sp.y) * sin(sp.x), sin(sp.y), -cos(sp.y) * cos(sp.x));
			float a = acos(clamp(dot(dir, sd), -1.0, 1.0));
			float mag = 3.5 + log(max(h / 0.0073, 1e-4)) * 0.4342945 / 0.46;
			float airmass = 1.0 / max(sin(sp.y) + 0.025, 0.03);
			float e = 2.54e-6 * pow(10.0, -0.4 * mag) * exp(-0.3 * airmass);
			float s = max(pix * 0.8, 0.0002);
			float l = e / (3.14159 * s * s) * exp(-(a * a) / (s * s));
			float k = lucid_hash(ci + 5.5);
			vec3 sc = k < 0.3 ? vec3(1.15, 1.0, 0.8) : (k > 0.8 ? vec3(0.85, 0.95, 1.2) : vec3(1.0));
			rad += sc * l / LUCID_UNIT_NITS * stars * (1.0 - cover);
		}
	}
	// (The haze round the nearest street heads: lucid_airglow.)
	ALBEDO = lucid_capturing(PROJECTION_MATRIX) > 0.5 ? rad : lucid_mesopic(rad + lucid_airglow(CAMERA_POSITION_WORLD + dir * 5000.0, CAMERA_POSITION_WORLD)) * lucid_exposure.rgb;
}
