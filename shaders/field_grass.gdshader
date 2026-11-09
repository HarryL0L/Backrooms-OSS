// The Field's realistic grass (FieldGrass, High and up): one blade per
// MultiMesh instance (a pure translation: its root in the tile), the blade
// a strip (VERTEX.x across, -0.5 .. 0.5; VERTEX.y along, 0 .. 1). Each blade's
// height, facing, stiffness, colour and seed head come from a hash of its
// root (world), so blades keep their looks as the tiles follow you. Meadow
// proportions: 0.2-0.6 m, taller in clumps; a few dry ones; some seed
// heads. Each blade is a circular arc bent by its own droop and by the
// wind (field_wind_at, the one wind field the rain, the sound and the sky
// share): the bend's tangent is the dynamic pressure over the stiffness,
// tan(theta) = (v / v45)^2, so a breeze barely sways it and a 15 m/s gust
// lays it flat; the tips flutter at 2-3 Hz; wet blades are heavier (they
// droop and give way sooner, flutter slower). They lean away from you as you
// walk through them. Blades are kept between r_in and r_out from the camera
// (dithered at both ends, so the LOD rings hand over without a seam).
shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_schlick_ggx;
#include "res://shaders/field_common.gdshaderinc"
#include "res://shaders/field_storm.gdshaderinc"

uniform float r_in = 0.0;
uniform float r_out = 10.0;
uniform float fade = 3.0;
uniform float width = 0.012;
uniform float h_min = 0.2;
uniform float h_max = 0.6;
uniform vec3 green_a : source_color = vec3(0.30, 0.46, 0.14);
uniform vec3 green_b : source_color = vec3(0.42, 0.52, 0.18);
uniform vec3 dry : source_color = vec3(0.58, 0.52, 0.32);
uniform vec3 seed : source_color = vec3(0.50, 0.42, 0.28);

varying vec3 v_col;
varying float v_t;

void vertex() {
	vec3 org = MODEL_MATRIX[3].xyz;
	vec2 rp = org.xz;
	float h1 = field_hash(rp * 13.17 + 0.5);
	float h2 = field_hash(rp * 7.31 + 3.1);
	float h3 = field_hash(rp * 3.71 + 8.2);
	float h4 = field_hash(rp * 21.13 + 1.7);
	vec3 cam = CAMERA_POSITION_WORLD;
	float d = distance(rp, cam.xz);
	bool vis = d >= r_in + (h4 - 0.5) * fade && d < r_out + (h1 - 0.5) * fade;
	// Clumps: taller and denser-looking where the noise is high.
	float clump = field_vnoise(rp * 1.3);
	float hgt = mix(h_min, h_max, clamp(h3 * 0.55 + clump * 0.6 - 0.1, 0.0, 1.0));
	bool has_seed = h3 > 0.92;
	if (has_seed) {
		hgt *= 1.35;
	}
	float ground = FIELD_Y + field_height(rp);
	float face = h1 * 6.2832;
	vec2 fdir = vec2(cos(face), sin(face));
	vec2 sdir = vec2(-fdir.y, fdir.x);
	// The wind on it (at 2 m: the log profile makes it ~half that down in
	// the grass; v45 is quoted for the 2 m wind).
	vec3 wv = field_wind_at(rp);
	float v = length(wv.xy);
	vec2 wd = v > 0.01 ? wv.xy / v : vec2(1.0, 0.0);
	float wet = field_wind.w;
	float v45 = mix(10.0, 8.5, wet) * (0.75 + 0.55 * h2);
	float bw = atan(v * v / (v45 * v45));
	float flut = (0.05 + 0.05 * h4) * min(v / 12.0, 1.4)
			* sin(TIME * 6.2832 * mix(2.8, 2.1, wet) * (0.85 + 0.3 * h3) + h1 * 40.0 + dot(rp, wd) * 0.9);
	float droop = 0.12 + 0.55 * h2 * h2 + 0.18 * wet;
	vec2 b = fdir * droop + wd * (bw + flut);
	// Walking through it: blades lean out of your way.
	vec2 pc = rp - cam.xz;
	float pd = length(pc);
	b += (pd > 0.01 ? pc / pd : vec2(0.0)) * 1.2 * (1.0 - smoothstep(0.2, 0.75, pd));
	float th = min(length(b), 1.5);
	vec2 bd = th > 1e-4 ? normalize(b) : fdir;
	float t = VERTEX.y;
	float ang = th * t;
	float xr = th > 1e-3 ? hgt * (1.0 - cos(ang)) / th : 0.0;
	float yr = th > 1e-3 ? hgt * sin(ang) / th : hgt * t;
	float w = width * (0.7 + 0.6 * h4) * (1.0 - 0.85 * pow(t, 1.6));
	if (has_seed) {
		// A seed head: the top fifth a spike of seeds, thicker.
		w = mix(w * 0.6, width * 2.6, smoothstep(0.78, 0.84, t) * (1.0 - smoothstep(0.96, 1.0, t)));
	}
	vec3 p = vec3(rp.x, ground, rp.y) + vec3(bd.x * xr, yr, bd.y * xr) + vec3(sdir.x, 0.0, sdir.y) * VERTEX.x * w;
	if (!vis) {
		p = vec3(rp.x, ground - 2.0, rp.y);
	}
	VERTEX = p - org;
	vec3 tg = vec3(bd.x * sin(ang), cos(ang), bd.y * sin(ang));
	vec3 n = normalize(cross(vec3(sdir.x, 0.0, sdir.y), tg));
	NORMAL = normalize(mix(n, vec3(0.0, 1.0, 0.0), 0.45));
	// Colour: greens, a few dry blades, paler toward the tip, dark near the
	// root (the canopy shades itself).
	vec3 c = mix(green_a, green_b, h2);
	c = mix(c, dry, smoothstep(0.82, 0.97, h4) * 0.85);
	c *= 0.85 + 0.3 * clump;
	if (has_seed) {
		c = mix(c, seed, smoothstep(0.76, 0.84, t));
	}
	v_col = c * (0.3 + 0.7 * smoothstep(0.0, 0.7, t)) * (1.0 + 0.15 * t);
	v_t = t;
}

void fragment() {
	if (!FRONT_FACING) {
		NORMAL = -NORMAL;
	}
	float wet = field_wind.w;
	ALBEDO = v_col * (1.0 - 0.25 * wet);
	ROUGHNESS = mix(0.62, 0.32, wet);
	SPECULAR = mix(0.3, 0.5, wet);
	// Light through the blades (thin leaves pass ~10-20 % of green light).
	BACKLIGHT = v_col * 0.45;
}
