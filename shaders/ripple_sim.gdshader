// One step of the water ripple simulation (2D wave equation on a height
// field). Runs in a SubViewport, ping-ponging between two of them:
// prev_tex holds r = height now, g = height one step ago.
shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D prev_tex : filter_nearest, repeat_disable;
// The grid follows the player in whole texels; this step's shift (uv units).
uniform vec2 shift = vec2(0.0);
// (c * dt / dx)^2, kept below 0.5 for stability.
uniform float k = 0.1;
uniform float damping = 0.985;
// Disturbances: xy = uv, z = radius (uv), w = strength (m).
uniform vec4 drops[8];
uniform int drop_count = 0;

float h_at(vec2 uv) {
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) {
		return 0.0;
	}
	return texture(prev_tex, uv).r;
}

void fragment() {
	vec2 uv = UV + shift;
	vec2 px = 1.0 / vec2(textureSize(prev_tex, 0));
	float h = h_at(uv);
	float hp = (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) ? 0.0 : texture(prev_tex, uv).g;
	float lap = h_at(uv + vec2(px.x, 0.0)) + h_at(uv - vec2(px.x, 0.0))
			+ h_at(uv + vec2(0.0, px.y)) + h_at(uv - vec2(0.0, px.y)) - 4.0 * h;
	float hn = (2.0 * h - hp + k * lap) * damping;
	for (int i = 0; i < drop_count; i++) {
		vec2 d = UV - drops[i].xy;
		float r = drops[i].z;
		hn += drops[i].w * exp(-dot(d, d) / (r * r));
	}
	// Absorb waves at the border so nothing reflects off the edge of the grid.
	float e = min(min(UV.x, UV.y), min(1.0 - UV.x, 1.0 - UV.y));
	float edge = smoothstep(0.0, 0.08, e);
	COLOR = vec4(clamp(hn * edge, -1.0, 1.0), h * edge, 0.0, 1.0);
}
