// Soft glow around each light fixture, standing in for volumetric fog on the
// Mobile renderer. Each halo is a camera-facing quad built in the vertex shader:
// VERTEX is the fixture centre, UV the corner (0..1), UV2 = (flicker seed, size).
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, depth_test_disabled, cull_disabled, skip_vertex_transform, shadows_disabled, fog_disabled;
#include "res://shaders/common.gdshaderinc"

uniform float strength = 0.07;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest;

varying vec3 v_col;
varying float v_fade;
varying vec3 v_centre;

void vertex() {
	vec3 centre = VERTEX;
	vec4 vp = MODELVIEW_MATRIX * vec4(centre, 1.0);
	v_centre = vp.xyz;
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
	// The glow is drawn without depth testing (like camera bloom), so walls
	// never cut hard edges into it. Instead the whole halo fades when the
	// fixture itself is hidden: compare the scene depth around the fixture's
	// screen position with the fixture's own distance.
	vec4 cp = PROJECTION_MATRIX * vec4(v_centre, 1.0);
	float vis = 0.0;
	if (cp.w > 0.0) {
		vec2 cuv = cp.xy / cp.w * 0.5 + 0.5;
		float cdist = -v_centre.z;
		vec2 px = 1.5 / VIEWPORT_SIZE;
		for (int k = 0; k < 5; k++) {
			vec2 o = k == 0 ? vec2(0.0) : vec2(k == 1 ? 1.0 : (k == 2 ? -1.0 : 0.0), k == 3 ? 1.0 : (k == 4 ? -1.0 : 0.0));
			vec2 suv = clamp(cuv + o * px, vec2(0.0), vec2(1.0));
			float d = texture(depth_tex, suv).r;
#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
			vec3 ndc = vec3(suv, d) * 2.0 - 1.0;
#else
			vec3 ndc = vec3(suv * 2.0 - 1.0, d);
#endif
			vec4 sv = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
			vis += step(cdist - 0.35, -sv.z / sv.w);
		}
		vis *= 0.2;
		// Fixtures just off screen can't be tested; let them fade out.
		vec2 edge = min(cuv, 1.0 - cuv);
		vis *= smoothstep(-0.05, 0.02, min(edge.x, edge.y));
	}
	ALBEDO = v_col * g * strength * v_fade * vis;
}
