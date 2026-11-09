// Foliage of the lone tree in the Field: clustered spheres pushed in and out
// by noise so the crown reads as clumps of leaves against the sky. The crown
// sways and its leaves toss in the storm's wind (field_wind_at).
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/field_storm.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 leaf_dark : source_color = vec3(0.05, 0.11, 0.03);
uniform vec3 leaf_light : source_color = vec3(0.17, 0.30, 0.07);
uniform float base_y = -2000.0;   // the trunk's foot (world y)

varying vec3 v_w;

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float n = textureLod(noise_fine, w.xz * 0.11 + w.y * 0.09, 0.0).r;
	float n2 = textureLod(noise_fine, w.zy * 0.31 + w.x * 0.05, 0.0).r;
	VERTEX += NORMAL * ((n - 0.5) * 1.1 + (n2 - 0.5) * 0.45);
	// The crown leans with the wind's pressure (~v^2) and its gusts, the
	// leaves toss faster.
	vec3 wv = field_wind_at(w.xz);
	float hh = max(w.y - base_y, 0.0);
	vec2 sway = wv.xy * length(wv.xy) * 0.00009 * hh * hh / 10.0;
	sway += wv.xy * 0.012 * sin(TIME * 5.0 + n * 30.0 + w.x);
	VERTEX += (inverse(mat3(MODEL_MATRIX)) * vec3(sway.x, 0.0, sway.y));
	v_w = w;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	float n = texture(noise_fine, v_w.xz * 0.7 + v_w.y * 0.5).r;
	float clump = texture(noise_fine, v_w.xy * 0.18 + v_w.z * 0.11).r;
	ALBEDO = mix(leaf_dark, leaf_light, smoothstep(0.25, 0.8, n * 0.6 + clump * 0.5));
	ROUGHNESS = 1.0;
	// A little light through the leaves on the sunny side.
	BACKLIGHT = vec3(0.12, 0.2, 0.05);
}
