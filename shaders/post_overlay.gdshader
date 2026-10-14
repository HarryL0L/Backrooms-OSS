// Cheap full-screen overlay: animated film grain and vignette.
// Uses plain alpha blending (no screen texture read) so it is nearly free on mobile GPUs.
shader_type canvas_item;

uniform float grain = 0.05;
uniform float vignette = 0.42;

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = (uv - 0.5) * vec2(1.0, 0.85);
	float vig = smoothstep(0.3, 0.78, length(c)) * vignette;
	float t = floor(TIME * 24.0);
	float n = rand(floor(FRAGCOORD.xy * 0.5) + t * 17.13);
	float g = grain;
	float a = vig + g - vig * g;
	vec3 col = mix(vec3(n), vec3(0.0), vig / max(a, 0.001));
	COLOR = vec4(col, a);
}
