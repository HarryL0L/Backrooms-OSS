shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

// CUSTOM0.rgb = emitted radiance, UV2 = (flicker seed, 1 if powered)
varying vec3 v_emit;
varying float v_on;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	// (L.U.C.I.D.: a flickering lamp follows its level in lucid_lamps, as
	// its light in the lightmaps does.)
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	ivec2 cell = ivec2(floor(wp.xz / 2.4));
	float lv = lucid_exposure.a > 0.5 && UV2.x > 0.5 ? lamp_level(float((cell.x & 127) + 128 * (cell.y & 127))) : flicker(UV2.x, world_time);
	v_emit = CUSTOM0.rgb * lv * lucid_exposure.rgb;
	v_on = UV2.y;
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	// UV is in metres across the panel: fine prismatic diffuser pattern.
	vec2 cells = fract(UV * 45.0) - 0.5;
	float prism = 0.9 + 0.1 * smoothstep(0.5, 0.2, length(cells));
	vec3 lit = v_emit * prism;
	// (L.U.C.I.D.: a dead panel carries the room light its lens reflects.)
	vec3 dead = (lucid_exposure.a > 0.5 ? v_emit : vec3(0.09, 0.09, 0.085)) * prism;
	ALBEDO = mix(dead, lit, v_on) + dither(FRAGCOORD.xy);
}
