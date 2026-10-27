// Jumpscare overlay (HUD.scare): a white flash and torn, rolling static.
shader_type canvas_item;

uniform float flash = 0.0;
uniform float noise = 0.0;

float h(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	float t = floor(TIME * 30.0);
	// Horizontal tears: whole bands shifted and brightened.
	float band = h(vec2(floor(UV.y * 40.0), t));
	float tear = step(0.86, band);
	float n = h(floor(UV * vec2(320.0, 180.0)) + t * 7.3);
	float roll = smoothstep(0.0, 0.08, abs(fract(UV.y + TIME * 1.7) - 0.5));
	vec3 col = vec3(n) * (0.6 + 0.4 * tear);
	float a = noise * (0.35 * n + 0.45 * tear) * roll;
	COLOR = vec4(mix(col, vec3(1.0, 0.98, 0.95), flash), clamp(max(a, flash), 0.0, 1.0));
}
