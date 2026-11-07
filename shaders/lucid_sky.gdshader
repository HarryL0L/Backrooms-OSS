// L.U.C.I.D. stage 3: the physical night sky on a dome round the camera.
// The sky model (lucid_sky_now, Lucid.sky_nits) in real luminance; the
// moon as a disc of its real luminance (E_moon / 6.4e-5 sr, so the
// directional light and the disc agree), with the aerosols' forward
// scattering round it (the aureole, ~5 % of its light within a few
// degrees); stars brighter than magnitude 3.5 as point sources of their
// real illuminance (2.54e-6 lux x 10^(-0.4 m)), dimmed by the air mass,
// spread over a pixel. Most of them drown in the city's glow, as they do.
shader_type spatial;
render_mode unshaded, cull_front, depth_draw_never, fog_disabled, shadows_disabled;
#include "res://shaders/lucid_city.gdshaderinc"

uniform vec3 moon_dir = vec3(0.0, 0.5, 0.8);
uniform vec3 moon_rad = vec3(0.0);      // disc radiance, engine units
uniform vec3 moon_e = vec3(0.0);        // its illuminance as E / pi, engine units (for the aureole)
uniform float stars = 1.0;

varying vec3 v_dir;

void vertex() {
	v_dir = (MODEL_MATRIX * vec4(VERTEX, 0.0)).xyz;
}

void fragment() {
	vec3 dir = normalize(v_dir);
	vec3 rad = lucid_sky_now(dir);
	float pix = max(length(fwidth(dir)), 1e-5);
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
		rad += moon_rad * disc * maria * (0.85 + 0.15 * sqrt(max(1.0 - r * r, 0.0)));
	}
	// Aureole: E x 0.05 spread as exp(-theta / 0.035) (2 pi a^2 sr).
	rad += moon_e * 3.14159 * 0.05 * exp(-th / 0.035) / (6.2832 * 0.035 * 0.035) * step(0.0, moon_dir.y);
	if (stars > 0.0 && dir.y > 0.0) {
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
			rad += sc * l / LUCID_UNIT_NITS * stars;
		}
	}
	ALBEDO = lucid_mesopic(rad) * lucid_exposure.rgb;
}
