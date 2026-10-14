shader_type spatial;
render_mode unshaded, cull_back;
#include "res://shaders/common.gdshaderinc"

// CUSTOM0.rgb = emitted radiance, UV2 = (flicker seed, 1 if powered)
varying vec3 v_emit;
varying float v_on;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_emit = CUSTOM0.rgb * flicker(UV2.x, world_time);
	v_on = UV2.y;
}

void fragment() {
	// UV is in metres across the panel: fine prismatic diffuser pattern.
	vec2 cells = fract(UV * 45.0) - 0.5;
	float prism = 0.9 + 0.1 * smoothstep(0.5, 0.2, length(cells));
	vec3 lit = v_emit * prism;
	vec3 dead = vec3(0.09, 0.09, 0.085) * prism;
	ALBEDO = mix(dead, lit, v_on) + dither(FRAGCOORD.xy);
}
