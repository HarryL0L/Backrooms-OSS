// L.U.C.I.D. stage 3: the city's ground beyond the part you can walk on
// (one big plane). The street grid (lucid_road_paint) with its lamps lit
// analytically: the lamps stand in a regular pattern (LucidCity.GRID), so
// the few that light a point are found by arithmetic, not by a list:
// along the nearest avenue the four nearest pairs of LED heads, along the
// nearest street the three pairs of its block's sodium heads, each
// E = I0 cos^m(theta) cos(theta) / d^2 with its real I0 and m. Plus the
// state's sky (half of it, between the buildings) and the spill of the
// lit shopfronts on the sidewalks. Unoccluded: the near part is baked.
// Stage 4: wet after rain like the near streets (lucid_street), with the
// same specular: the sky (about half of it open between the buildings)
// and the street heads mirrored.
shader_type spatial;
render_mode unshaded, fog_disabled;
#include "res://shaders/lucid_city.gdshaderinc"
#include "res://shaders/lucid_street.gdshaderinc"

uniform vec3 i_led = vec3(1.0);         // engine colour of an avenue head (E / pi at 1 m)
uniform vec3 i_na = vec3(1.0);          // and of a street head
uniform float m_led = 1.2;
uniform float m_na = 1.2;
uniform vec3 e_sky_up = vec3(0.0005);
uniform vec3 e_spill = vec3(0.003);
uniform float ground_y = 0.0;
uniform vec3 asphalt = vec3(0.094, 0.084, 0.064);   // linear albedos
uniform vec3 walk = vec3(0.30, 0.30, 0.29);

float lamp_e(vec2 d, float h, float m) {
	float r2 = dot(d, d) + h * h;
	float c = h * inversesqrt(r2);
	return pow(c, m + 1.0) / r2;
}

void fragment() {
	vec3 wp = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 p = wp.xz;
	float w = length(fwidth(p));
	float xc = round(p.x / 110.0) * 110.0;
	float zc = round(p.y / 80.0) * 80.0;
	float ax = abs(p.x - xc);
	float az = abs(p.y - zc);
	// Avenue heads: x = xc +- 7.6 (2.5 m arms from poles at the curb),
	// z = 17.5 + 35 k, 10 m up.
	float led = 0.0;
	float k0 = floor((p.y - 17.5) / 35.0);
	for (int k = -1; k <= 2; k++) {
		float lz = 17.5 + 35.0 * (k0 + float(k));
		led += lamp_e(vec2(p.x - xc - 7.6, p.y - lz), 10.0, m_led);
		led += lamp_e(vec2(p.x - xc + 7.6, p.y - lz), 10.0, m_led);
	}
	// Street heads: z = zc +- 5.1, at 25, 55 and 85 m into each block, 8 m up.
	float na = 0.0;
	float xl = floor(p.x / 110.0) * 110.0;
	for (int k = 0; k < 3; k++) {
		float lx = xl + 25.0 + 30.0 * float(k);
		na += lamp_e(vec2(p.x - lx, p.y - zc - 5.1), 8.0, m_na);
		na += lamp_e(vec2(p.x - lx, p.y - zc + 5.1), 8.0, m_na);
	}
	vec3 e = (i_led * led + i_na * na) * lucid_sky.z;
	bool road = ax < 9.5 || az < 6.0;
	bool side = ax < 15.0 || az < 10.0;
	vec3 alb = road ? asphalt : (side ? walk : asphalt * 1.3);
	e += e_sky_up * 0.5;
	if (!road && side) {
		e += e_spill;
	}
	if (road) {
		float py;
		float pw = lucid_road_paint(p, w, py);
		alb = mix(mix(alb, vec3(0.55, 0.54, 0.5), pw), vec3(0.50, 0.36, 0.07), py);
	}
	float n = lucid_hash(floor(p * 0.5));
	alb *= 0.85 + 0.3 * n * smoothstep(1.0, 0.2, w);
	vec3 rad = alb * e;
	float cap = lucid_capturing(PROJECTION_MATRIX);
	if (wet > 0.0 && road && cap < 0.5) {
		float rough = 0.75;
		float fz = 0.04;
		lucid_wet(alb, rough, fz, wet, puddles > 0.0 ? puddle(p) : 0.0);
		vec3 vw = normalize(CAMERA_POSITION_WORLD - wp);
		vec3 up = vec3(0.0, 1.0, 0.0);
		float e_spec = lucid_spec_albedo(vw.y, rough, fz);
		LucidMirror m = lucid_mirror(up, vw, rough);
		vec3 lp = vec3(p.x, wp.y - ground_y, p.y);
		rad = alb * e * (1.0 - e_spec) + (lucid_sky_now(m.r) * 0.45 + lamp_reflections(lp, m)) * e_spec;
	}
	ALBEDO = lucid_finish_at(rad, wp, CAMERA_POSITION_WORLD, cap);
}
