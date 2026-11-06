shader_type spatial;
// Premultiplied blending: what the water reflects is added on top of the
// pool tiles beneath (which do their own absorption, see pool_tile), and
// ALPHA is only how much of them the reflection hides (the Fresnel term).
render_mode blend_premul_alpha, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx, fog_disabled;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/water.gdshaderinc"

uniform vec3 deep_color : source_color = vec3(0.30, 0.66, 0.66);
uniform float ceiling_y = 4.8;
// Planar reflection rendered by WaterReflection (mirrored camera), 0 = use the cheap fake.
uniform sampler2D reflection_tex : hint_default_black, filter_linear, repeat_disable;
uniform float reflection_on = 0.0;
// Own fog instead of the room's: the pale Tiled Baths fog turned distant water
// grey-white while the white walls barely changed. Water fades into a teal
// haze (as if seen through more water) and a bit more slowly.
uniform vec3 water_fog : source_color = vec3(0.34, 0.44, 0.43);
uniform float water_fog_density = 0.014;

varying vec3 v_light;
varying vec3 v_wpos;
varying vec2 v_wave_slope;

void vertex() {
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 wv = waves(v_wpos.xz, world_time);
	// The surface really moves: lift it by the waves and the simulated ripples.
	float h = wv.x + ripple_height(v_wpos.xz);
	VERTEX.y += h;
	v_wpos.y += h;
	v_wave_slope = wv.yz;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

// PS1 style keeps the old look: a lit, semi-opaque teal film.
void ps1_water(vec3 wpos, vec3 cam, vec3 light, vec2 wave_slope, out vec3 em, out vec3 albedo, out float alpha) {
	vec2 p = wpos.xz;
	vec3 v = normalize(cam - wpos);
	vec3 n1 = texture(noise_normal, p * 0.21 + world_time * vec2(0.012, 0.008)).rgb;
	vec3 n2 = texture(noise_normal, p * 0.17 - world_time * vec2(0.009, 0.013)).rgb;
	vec3 nm = normalize((n1 + n2) - 1.0);
	vec2 slope = wave_slope + ripple_slope(p);
	nm = normalize(vec3(nm.xy - slope * 2.5, nm.z));
	vec3 wn = normalize(vec3(nm.x * 0.012 - slope.x * 1.5, 1.0, nm.y * 0.012 - slope.y * 1.5));
	float fres = water_fresnel(dot(wn, v));
	vec3 refl = ceiling_reflection(wpos, cam, wn, ceiling_y, 0, world_time);
	refl += light * vec3(0.85, 0.92, 0.95) * 0.6;
	refl *= mix(vec3(1.0), deep_color * 1.5, 0.3);
	float fogk = 1.0 - exp(-water_fog_density * length(cam - wpos));
	alpha = clamp(max(0.22 + fres * 0.75, fogk * 1.2), 0.0, 0.97);
	vec3 c = deep_color * light * 0.45 * (1.0 - fres) + refl * min(fres * 1.5 + 0.06, 1.0)
			+ deep_color * flashlight(wpos, wn, cam, 0.95);
	// (Premultiplied: scaled by alpha here.)
	em = mix(c, water_fog * max(light, vec3(0.3)), fogk) * alpha;
	albedo = deep_color * (1.0 - fogk) * alpha;
}

void fragment() {
	vec2 p = v_wpos.xz;
	vec3 cam = CAMERA_POSITION_WORLD;
	vec3 v = normalize(cam - v_wpos);
	ALBEDO = vec3(0.0);
	ROUGHNESS = 0.03;
	SPECULAR = 0.25;   // F0 = 0.02, water
	vec3 em;
	float alpha;
	if (ps1_grid.x > 0.0) {
		vec3 albedo;
		ps1_water(v_wpos, cam, v_light, v_wave_slope, em, albedo, alpha);
		ALBEDO = albedo;
		SPECULAR = 0.7;
	} else {
		// The smooth normal for the broad reflection, with the capillary
		// wrinkles added for the glints of the lights.
		vec2 sb = water_slope(p, world_time, v_wave_slope);
		vec3 wb = normalize(vec3(-sb.x, 1.0, -sb.y));
		vec2 s = sb + water_wrinkles(p, world_time);
		vec3 wn = normalize(vec3(-s.x, 1.0, -s.y));
		NORMAL = normalize((VIEW_MATRIX * vec4(wn, 0.0)).xyz);
		float fres = water_fresnel(dot(wb, v));
		// What the surface mirrors: the room (planar reflection, or the baked
		// light here as a stand-in for the bright tiled walls), and the
		// ceiling lights as small sharp glints, broken up by the wrinkles.
		vec3 room = v_light * vec3(0.85, 0.92, 0.95) * 0.75;
		if (reflection_on > 0.5) {
			// The reflection camera's image is mirrored horizontally (right-handed basis).
			vec2 ruv = vec2(1.0 - SCREEN_UV.x, SCREEN_UV.y) + sb * vec2(-0.3, 0.3);
			room = texture(reflection_tex, clamp(ruv, vec2(0.001), vec2(0.999))).rgb * 1.15;
		}
		// Lights are far brighter than anything else in the room, so even the
		// 2 % reflected looking straight down shows as a bright glint.
		vec3 glint = ceiling_reflection(v_wpos, cam, wn, ceiling_y, 0, world_time);
		// Towards grazing the tiniest wrinkle sends the ray to another lamp
		// far off, which only sparkles: leave that to the room's reflection
		// (mostly; the cheap fake has no lamps of its own).
		float steep = smoothstep(0.12, 0.45, v.y);
		glint *= min(fres * (reflection_on > 0.5 ? 2.0 : 3.5), 1.2) * (reflection_on > 0.5 ? steep : mix(0.35, 1.0, steep));
		em = room * fres + glint + flashlight(v_wpos, wn, cam, 1.0) * 0.1;
		alpha = fres;
		// Far off the room's own fog takes over; over water it is a teal haze.
		float fogk = (1.0 - exp(-water_fog_density * length(cam - v_wpos))) * 0.9;
		em = mix(em, water_fog * max(v_light, vec3(0.3)), fogk);
		alpha = mix(alpha, 1.0, fogk);
	}
	ALPHA = clamp(alpha, 0.0, 1.0);
	EMISSION = em + dither(FRAGCOORD.xy);
}
