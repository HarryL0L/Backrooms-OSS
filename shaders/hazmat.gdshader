// Hazmat suit / gear for player models. Lit like the world: the Backrooms
// surfaces carry their (baked) light as emission, so the model gets the
// light level where it stands as `env_light` (set per instance), plus the
// shader flashlight and real-time lights. Optional fabric creases: wavy
// folds wrapping round the limbs, deepest at the joints (UV2.x), as a cheap
// screen-space bump (no extra geometry).
shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform vec3 albedo : source_color = vec3(0.86, 0.68, 0.1);
uniform float roughness = 0.45;
uniform float specular_amt = 0.5;
uniform float wrinkles = 0.0;          // 0 = smooth rubber
uniform vec3 env_light = vec3(0.0);

varying vec3 v_wpos;
varying vec3 v_wnormal;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 col = albedo;
	if (wrinkles > 0.0) {
		// UV.x = around the limb (0..1), UV.y = along it (metres).
		float u = UV.x * 6.2831853;
		float v = UV.y;
		float crease = UV2.x;
		float h1 = sin(v * 44.0 + sin(u * 2.0 + v * 6.0) * 1.1);
		float h2 = sin(v * 27.0 - sin(u * 2.0 + 1.3 + v * 3.0) * 1.4 + 1.7);
		float h3 = sin(u * 4.0 + v * 9.0) * 0.25;
		float h = h1 * 0.55 + h2 * 0.45 + h3 * 0.3;
		float amp = (0.06 + 0.94 * crease * crease) * wrinkles;
		// Sharper valleys than ridges, like folded fabric.
		float hh = (h > 0.0 ? h : -pow(-h, 0.6)) * amp * 0.0018;
		vec3 dpdx = dFdx(VERTEX);
		vec3 dpdy = dFdy(VERTEX);
		vec3 r1 = cross(dpdy, NORMAL);
		vec3 r2 = cross(NORMAL, dpdx);
		float det = dot(dpdx, r1);
		vec3 grad = sign(det) * (dFdx(hh) * r1 + dFdy(hh) * r2);
		NORMAL = normalize(abs(det) * NORMAL - grad);
		col *= 1.0 - 0.14 * amp * smoothstep(0.2, 0.9, -h);
	}
	ALBEDO = col;
	ROUGHNESS = roughness;
	SPECULAR = specular_amt;
	EMISSION = col * env_light + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 1.0 - roughness);
}
