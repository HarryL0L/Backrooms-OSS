// L.U.C.I.D.: a lightning flash's channels (LucidStorm), lit only while a
// stroke lands. Each channel is a strip of camera-facing ribbons joined at
// its kinks (VERTEX: a point of the channel, world; NORMAL: its mean
// direction there; UV.x: the side, UV.y: its brightness, 1 the trunk at
// the ground; UV2.x: 1 a branch, lit by the first stroke only), carrying
// its real light per metre: a line source of I' cd/m drawn w metres wide
// has the radiance I' / w (a profile across it of that integral). Three
// profiles across it: the core (the channel is a few centimetres across,
// drawn 1.2 pixels wide: it saturates), the lens's glare round it (a few
// pixels white, then the channel's violet-pink), and the haze's forward
// lobe (violet-pink near, the far haze's blue-grey far off). The strike's
// glow is a camera-facing square (UV2.y 1). All seen through the haze, the
// rain and the cloud's mist and scud (Koschmieder: farther bolts fainter,
// softer and greyer; behind a scud wisp the core dims).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled, shadows_disabled;
#include "res://shaders/lucid_city.gdshaderinc"

uniform float intensity = 0.0;   // the trunk's light per metre now (engine units: cd/m / 153.6)
uniform float branches = 1.0;    // the branches' share of it now (1 in the first stroke, 0 in later ones)
uniform float soft = 0.0;        // Reduce flashing: the share of the core spread into its glow
uniform vec3 colour = vec3(1.0); // the channel's colour at luminance 1
uniform vec3 far = vec3(1.0);    // its glow's far off

// The lens and sensor spread GLARE of the light round the core, a line
// spread falling off as 1 / (1 + (x / w)^2) with w GLARE_PX pixels (a
// lens's point spread has a power-law tail): the saturated core shows
// several pixels wide, its colour in the fringe.
const float GLARE = 0.06;
const float GLARE_PX = 1.5;
// What the air takes out of the beam is scattered: the rain drops'
// diffraction stays within the core (lambda / D ~ 5e-4 rad: LucidRain's
// extinction leaves it out), the rest goes wide (the air round the
// channel and the cloud it lights, lucid_lightning_sky) but for a forward
// lobe, HALO of what the air and the mist take within HALO_THETA (rad,
// 1/e) of the channel (the haze, ~40 % of the extinction, scatters ~1 %
// within half a degree).
const float HALO = 0.004;
const float HALO_THETA = 0.01;
// The strike: the channel's foot lights the wet ground round it: a
// vertical line of I' cd/m over the ground gives it I' / rho lux at rho, so
// within GROUND m it takes 2 pi I' GROUND lm; the ground (albedo ~0.1,
// seen at a low angle) sends back GROUND_I x I' cd, spread over GROUND m.
const float GROUND = 30.0;
const float GROUND_I = 2.0;

varying vec3 v_core;
varying vec3 v_glare;
varying vec3 v_halo;
varying vec3 v_w;
varying vec2 v_x;
varying float v_sprite;

void vertex() {
	vec3 p = VERTEX;
	vec3 cam = INV_VIEW_MATRIX[3].xyz;
	float d = distance(p, cam);
	float mpp = 2.0 * d / (abs(PROJECTION_MATRIX[1][1]) * VIEWPORT_SIZE.y);
	// Half widths (m): the core (1/e), the glare's w, the halo (1/e).
	float wc = max(0.04, mpp * 0.6);
	float wg = mpp * GLARE_PX;
	float wh = max(HALO_THETA * d, mpp);
	float tr = exp(-(lucid_air.a + lucid_rain.w) * d - lucid_mist_tau(cam, p));
	float sc = HALO * (1.0 - tr);
	vec3 hc = mix(far, colour, sqrt(tr));
	float k = intensity * mix(1.0, branches, UV2.x);
	v_sprite = UV2.y;
	v_w = vec3(wc, wg, wh);
	if (UV2.y > 0.5) {
		float rs = 0.5 * max(GROUND, 2.0 * wh);
		p += (INV_VIEW_MATRIX[0].xyz * UV.x + INV_VIEW_MATRIX[1].xyz * UV.y) * rs * 3.0;
		v_x = UV * 3.0;
		v_halo = hc * k * GROUND_I * (tr + sc) / (3.14159 * rs * rs);
		v_core = vec3(0.0);
		v_glare = vec3(0.0);
	} else {
		// A ribbon wide enough for the halo's and the glare's tails.
		float half_w = max(2.5 * wh, 14.0 * mpp);
		vec3 side = normalize(cross(NORMAL, p - cam));
		p += side * UV.x * half_w;
		k *= UV.y;
		v_x = vec2(UV.x * half_w, 0.0);
		// Peaks: exp(-(x / w)^2) integrates to w sqrt(pi), 1 / (1 + (x / w)^2)
		// to w pi.
		v_core = colour * k * tr * (1.0 - GLARE) * (1.0 - soft) / (wc * 1.772454);
		v_glare = colour * k * tr * GLARE / (wg * 3.14159);
		v_halo = hc * k * (sc + tr * (1.0 - GLARE) * soft) / (wh * 1.772454);
	}
	// (The node stands at the world origin: model space is world space.)
	VERTEX = p;
}

void fragment() {
	vec3 c;
	if (v_sprite > 0.5) {
		c = v_halo * exp(-dot(v_x, v_x));
	} else {
		vec3 x = v_x.x / v_w;
		x *= x;
		c = v_core * exp(-x.x) + v_glare / (1.0 + x.y) + v_halo * exp(-x.z);
	}
	ALBEDO = lucid_capturing(PROJECTION_MATRIX) > 0.5 ? vec3(0.0) : lucid_mesopic(c) * lucid_exposure.rgb;
}
