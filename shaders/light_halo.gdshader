// Soft glow around each light fixture, standing in for volumetric fog on the
// Mobile renderer. Each halo is a camera-facing quad built in the vertex shader:
// VERTEX is the fixture centre, UV the corner (0..1), UV2 = (flicker seed, size).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
#include "res://shaders/common.gdshaderinc"

uniform float strength = 0.07;

varying vec3 v_col;
varying float v_fade;

void vertex() {
	vec3 centre = VERTEX;
	vec4 vp = MODELVIEW_MATRIX * vec4(centre, 1.0);
	float size = UV2.y;
	// Pull the quad towards the camera so it doesn't clip into the ceiling.
	float dist = length(vp.xyz);
	vp.xyz += normalize(-vp.xyz) * min(size * 0.5, dist * 0.5);
	vp.xy += (UV - 0.5) * size;
	VERTEX = vp.xyz;
	v_col = CUSTOM0.rgb * flicker(UV2.x, world_time);
	// Fade very close (inside the glow) and far away (fog takes over).
	v_fade = smoothstep(0.8, 3.0, dist) * (1.0 - smoothstep(35.0, 60.0, dist));
	if (CAMERA_POSITION_WORLD.y < REFLECT_PLANE) {
		v_fade *= 0.6;
	}
}

void fragment() {
	vec2 c = UV - 0.5;
	float r = length(c) * 2.0;
	float g = exp(-r * r * 4.0) * (1.0 - smoothstep(0.85, 1.0, r));
	ALBEDO = v_col * g * strength * v_fade;
}
