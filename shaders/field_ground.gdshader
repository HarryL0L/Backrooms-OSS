// Field ground: soft rolling lawn. Vertex height from field_height() (world
// space), normal by finite differences; colour varies in large soft patches.
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/field_common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 grass_a : source_color = vec3(0.36, 0.60, 0.16);
uniform vec3 grass_b : source_color = vec3(0.46, 0.66, 0.20);
uniform vec3 far_color : source_color = vec3(0.50, 0.68, 0.28);

varying vec3 v_wpos;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float detail = 1.0 - smoothstep(400.0, 900.0, length(w.xz - CAMERA_POSITION_WORLD.xz));
	float h = field_height_d(w.xz, detail);
	VERTEX.y = h;
	float e = 0.5;
	float hx = field_height_d(w.xz + vec2(e, 0.0), detail) - field_height_d(w.xz - vec2(e, 0.0), detail);
	float hz = field_height_d(w.xz + vec2(0.0, e), detail) - field_height_d(w.xz - vec2(0.0, e), detail);
	NORMAL = normalize(vec3(-hx / (2.0 * e), 1.0, -hz / (2.0 * e)));
	v_wpos = vec3(w.x, w.y + h, w.z);
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
	col = mix(col, far_color, smoothstep(80.0, 900.0, dist) * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.92;
	SPECULAR = 0.25;
}
