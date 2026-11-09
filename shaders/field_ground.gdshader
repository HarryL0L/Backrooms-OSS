// Field ground: soft rolling lawn. Vertex height from field_height() (world
// space), normal by finite differences; colour varies in large soft patches.
// Under the storm (field_storm.gdshaderinc): darker when wet, lighter where
// a gust lays the grass over (a sheen sweeping with the wind), sunlit in
// patches far off where the sun gets under the storm, and seen through the
// air between (the haze and the rain shafts, per vertex: FOG). With the
// realistic grass (High and up, `blades`) the ground near you is the thatch
// under the blades and far off takes their mean colour.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/field_common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/field_storm.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.36, 0.60, 0.16);
uniform vec3 grass_b : source_color = vec3(0.46, 0.66, 0.20);
uniform vec3 far_color : source_color = vec3(0.50, 0.68, 0.28);
uniform float blades = 0.0;
uniform vec3 thatch : source_color = vec3(0.16, 0.2, 0.08);
uniform vec3 blade_mean : source_color = vec3(0.34, 0.5, 0.17);
uniform float blade_far = 70.0;
uniform int air_steps = 6;
// The lawn's colours were picked for the old sunny look; real grass
// reflects ~0.1 of the light (its green peak ~0.15).
uniform float albedo_k = 0.5;

varying vec3 v_wpos;
varying vec4 v_air;
varying float v_lit;
varying float v_gust;
varying vec3 v_n;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float detail = 1.0 - smoothstep(400.0, 900.0, length(w.xz - CAMERA_POSITION_WORLD.xz));
	float h = field_height_d(w.xz, detail);
	VERTEX.y = h;
	float e = 0.5;
	float hx = field_height_d(w.xz + vec2(e, 0.0), detail) - field_height_d(w.xz - vec2(e, 0.0), detail);
	float hz = field_height_d(w.xz + vec2(0.0, e), detail) - field_height_d(w.xz - vec2(0.0, e), detail);
	NORMAL = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	v_n = NORMAL;
	v_wpos = vec3(w.x, w.y + h, w.z);
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 dv = v_wpos - cam;
	float d = length(dv);
	v_air = field_air(cam, dv / max(d, 1e-3), d, air_steps);
	v_lit = d > 150.0 ? field_lit(v_wpos.xz, h) : 0.0;
	v_gust = d < 250.0 ? field_wind_at(v_wpos.xz).z - 1.0 : 0.0;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec2 p = v_wpos.xz;
	float big = texture(noise_blot, p * 0.004).r;
	float mid = texture(noise_blot, p * 0.031 + 0.37).r;
	vec3 col = mix(grass_a, grass_b, smoothstep(0.35, 0.65, big));
	col *= 0.88 + 0.2 * mid;
	// Fine blade texture, faded out with distance to avoid shimmer.
	float dist = length(v_wpos - CAMERA_POSITION_WORLD);
	float fine = texture(noise_fine, p * 1.7).r * 0.6 + texture(noise_fine, p * 6.3).r * 0.4;
	col *= mix(0.82 + 0.3 * fine, 1.0, smoothstep(6.0, 40.0, dist));
	col = mix(col, far_color, smoothstep(80.0, 900.0, dist) * 0.6) * albedo_k;
	if (blades > 0.5) {
		// Under the blades: their thatch; past them, their mean colour.
		float under = 1.0 - smoothstep(blade_far * 0.6, blade_far * 1.3, dist);
		col = mix(blade_mean * (0.85 + 0.3 * big), thatch * (0.8 + 0.4 * fine), under);
	}
	// A gust lays the grass over: more of the blades' pale sides show.
	col *= 1.0 + 0.16 * clamp(v_gust, -0.6, 1.0) * (1.0 - smoothstep(120.0, 250.0, dist));
	// Wet: darker (water fills the gaps, less light scattered back), glossier.
	float wet = field_wind.w;
	col *= 1.0 - 0.28 * wet;
	ALBEDO = col;
	ROUGHNESS = mix(0.92, 0.55, wet);
	SPECULAR = mix(0.25, 0.4, wet);
	// The sun where it gets under the storm (far patches).
	vec3 sun = vec3(field_sun.w) * vec3(1.0, 0.95, 0.85) * max(dot(normalize(v_n), field_sun.xyz), 0.0) * v_lit;
	EMISSION = col * sun * lucid_exposure.rgb;
	float a = 1.0 - v_air.a;
	FOG = vec4(a > 1e-4 ? v_air.rgb / a * lucid_exposure.rgb : vec3(0.0), a);
}
