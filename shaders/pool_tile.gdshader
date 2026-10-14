shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tile_color : source_color = vec3(0.93, 0.94, 0.91);
uniform vec3 grout_color : source_color = vec3(0.62, 0.68, 0.69);
uniform float water_y = -0.16;
uniform float ceiling_y = 4.8;

varying vec3 v_light;
varying vec3 v_wpos;
varying vec3 v_wnormal;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = NORMAL;
}

float caustics(vec2 p, float t) {
	float n1 = texture(noise_fine, p * 0.33 + t * vec2(0.031, 0.022)).r;
	float n2 = texture(noise_fine, p * 0.29 - t * vec2(0.024, 0.035) + 0.5).r;
	return pow(clamp(1.0 - abs(n1 - n2) * 3.5, 0.0, 1.0), 3.0);
}

void fragment() {
	vec2 uv = UV;
	const float TILE = 0.15;
	vec2 g = uv / TILE;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * TILE;
	float h = hash12(cell);
	vec3 tile = tile_color * (0.95 + 0.07 * h);
	if (h > 0.97) {
		tile *= vec3(0.86, 0.95, 1.0);
	}
	// Dark green tiled band along the waterline on walls and columns.
	if (abs(v_wnormal.y) < 0.5 && v_wpos.y < 0.33) {
		tile = vec3(0.15, 0.40, 0.31) * (0.85 + 0.25 * h);
	}
	float grime = texture(noise_blot, uv * 0.2).r;
	float aa = clamp((fwidth(g.x) + fwidth(g.y)) * 2.0, 0.0, 1.0);
	float grout = mix(smoothstep(0.0045, 0.0025, edge), 0.07, smoothstep(0.15, 0.6, aa));
	vec3 gc = grout_color * mix(1.0, 0.75, smoothstep(0.5, 0.75, grime));
	vec3 col = mix(tile, gc, grout);
	col *= 0.95 + 0.08 * texture(noise_fine, uv * 3.0).r;
	float bevel = smoothstep(0.004, 0.02, edge);
	vec3 emission_extra = vec3(0.0);
	float depth = water_y - v_wpos.y;
	if (depth > 0.0) {
		float d = clamp(depth / 0.8, 0.0, 1.0);
		col *= mix(vec3(0.82, 0.97, 1.0), vec3(0.62, 0.9, 0.95), d);
		emission_extra += caustics(v_wpos.xz + v_wpos.y * 0.3, world_time) * v_light * vec3(0.8, 0.95, 1.0) * 0.6;
		emission_extra += col * v_light * 0.25;
	} else if (v_wnormal.y > 0.5) {
		// Polished floor tiles mirror the lights above.
		float fres = 0.04 + 0.5 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		emission_extra += ceiling_reflection(v_wpos, CAMERA_POSITION_WORLD, vec3(0.0, 1.0, 0.0), ceiling_y, 0, world_time) * fres * (1.0 - grout);
	}
	ALBEDO = col * mix(0.85, 1.0, bevel);
	ROUGHNESS = mix(0.07, 0.7, grout);
	SPECULAR = 0.6;
	EMISSION = col * mix(0.85, 1.0, bevel) * v_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.8) + emission_extra + dither(FRAGCOORD.xy);
}
