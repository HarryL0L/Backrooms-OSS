// The shadow a parked car leaves on the floor: ambient occlusion under the
// body (nothing reaches there from the ceiling), darkest at the tyres, and
// fading out around it. Multiplies whatever the floor is lit with.
shader_type spatial;
render_mode unshaded, blend_mul, depth_draw_never, cull_back, fog_disabled;

uniform vec2 size = vec2(3.6, 6.4);       // plane size (x, z)
uniform vec2 body = vec2(0.9, 2.2);       // half extents of the car
uniform vec2 wheels = vec2(0.78, 1.32);   // tyre contact points (half track, half base)
// Light-facing side: the shadow leans away from the lights (plane space).
instance uniform vec2 lean = vec2(0.0);
instance uniform float strength = 1.0;

float box(vec2 p, vec2 b, float r) {
	vec2 d = abs(p) - b + r;
	return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

void fragment() {
	vec2 p = (UV - 0.5) * size;
	vec2 q = p - lean * 0.25;
	// Dense right under the body, a soft penumbra spreading out from it.
	float sd = box(q, body, 0.4);
	float under = (1.0 - smoothstep(-0.5, 0.15, sd)) * 0.55 + exp(-max(sd, 0.0) * 3.2) * 0.45;
	under *= 1.0 - smoothstep(0.6, 1.0, max(abs(p.x) / (size.x * 0.5), abs(p.y) / (size.y * 0.5)));
	float tyres = 0.0;
	for (int i = 0; i < 4; i++) {
		vec2 w = wheels * vec2(i % 2 == 0 ? 1.0 : -1.0, i < 2 ? 1.0 : -1.0);
		vec2 d = (p - w) / vec2(0.16, 0.34);
		tyres = max(tyres, exp(-dot(d, d)));
	}
	float occ = clamp(under * 0.62 + tyres * 0.3, 0.0, 0.85) * strength;
	ALBEDO = vec3(1.0 - occ);
}
