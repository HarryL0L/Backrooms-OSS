// L.U.C.I.D.: a lightning channel seen far off (LucidStorm), lit only while
// a stroke lands. Each segment is a camera-facing ribbon (VERTEX: a point of
// the channel, world; NORMAL: the segment; UV.x: the side, UV.y: its share
// of the light, 1 the trunk, less a branch) as wide as the channel's glow or
// 1.5 pixels, whichever is wider, carrying its real light per metre: a line
// source of I' cd/m drawn w metres wide has the radiance I' / w (a gaussian
// across it of that integral). Seen through the haze, the rain and the
// cloud's mist (its core fades into the scud as it climbs into the base,
// the light the air scatters forward a glow round it).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/lucid_city.gdshaderinc"

uniform float intensity = 0.0;   // light per metre of the trunk now (engine units: cd/m / 153.6)
uniform vec3 colour = vec3(1.0); // its colour at luminance 1

varying float v_l;
varying float v_lh;
varying float v_k;
varying float v_u;

// The air scatters what it takes out of the beam mostly forward: HALO of
// it stays within HALO_THETA of the channel (rain drops and the scud's
// droplets, lambda / D ~ 0.05 rad and less), so in rain and mist a bolt is
// a glowing line, its core dimmed.
const float HALO = 0.5;
const float HALO_THETA = 0.03;

void vertex() {
	vec3 p = VERTEX;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(p, cam);
	float mpp = 2.0 * d / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	float wc = max(2.0, mpp * 1.5);
	float wh = max(2.0 * HALO_THETA * d, wc);
	vec3 side = normalize(cross(NORMAL, p - cam));
	// A ribbon three halo widths across: the gaussians' tails.
	p += side * UV.x * wh * 1.5;
	// (The node stands at the world origin: model space is world space.)
	VERTEX = p;
	float tr = exp(-(lucid_air.a + lucid_rain.w) * d - lucid_mist_tau(cam, VERTEX));
	// Peaks of exp(-(x / (w / 2))^2), whose integral across is w sqrt(pi) / 2.
	v_l = intensity * UV.y * tr / (wc * 0.886227);
	v_lh = intensity * UV.y * HALO * (1.0 - tr) / (wh * 0.886227);
	v_k = wh / wc;
	v_u = UV.x;
}

void fragment() {
	float x = v_u * 3.0;
	float xc = x * v_k;
	ALBEDO = lucid_capturing(PROJECTION_MATRIX) > 0.5 ? vec3(0.0)
			: lucid_mesopic(colour * (v_l * exp(-xc * xc) + v_lh * exp(-x * x))) * lucid_exposure.rgb;
}
