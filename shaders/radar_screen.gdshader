shader_type spatial;
render_mode unshaded, cull_back, fog_disabled;
// Hand-held radar screen: range rings, a rotating sweep, and blips for the
// other players. blips[i] = (x, y in -1..1 with +y = ahead, alpha, at rim).

uniform vec4 blips[4];
uniform float sweep = 0.0;
uniform float brightness = 1.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	p.y = -p.y;
	float r = length(p);
	vec3 green = vec3(0.25, 1.0, 0.45);
	vec3 col = vec3(0.012, 0.04, 0.02);
	if (r > 1.0) {
		// Bezel.
		col = vec3(0.03, 0.032, 0.035) * (1.0 - smoothstep(1.0, 1.08, r) * 0.4);
	} else {
		float w = fwidth(r) * 1.2;
		col += green * 0.22 * (1.0 - smoothstep(0.0, w + 0.006, abs(r - 0.333)));
		col += green * 0.22 * (1.0 - smoothstep(0.0, w + 0.006, abs(r - 0.667)));
		col += green * 0.35 * (1.0 - smoothstep(0.0, w + 0.008, abs(r - 0.985)));
		col += green * 0.12 * (1.0 - smoothstep(0.0, 0.008, min(abs(p.x), abs(p.y))));
		float a = atan(p.x, p.y);
		float behind = mod(sweep - a, 6.2831853);
		col += green * 0.42 * exp(-behind * 2.6);
		for (int i = 0; i < 4; i++) {
			vec4 b = blips[i];
			if (b.z > 0.0) {
				float d = length(p - b.xy);
				// Brighter just after the sweep passes over it.
				float hit = 0.55 + 0.45 * exp(-mod(sweep - atan(b.x, b.y), 6.2831853) * 1.5);
				col += vec3(1.0, 0.82, 0.25) * b.z * hit * (1.0 - smoothstep(0.045, 0.085, d));
			}
		}
		// You, in the middle.
		col += vec3(0.85) * (1.0 - smoothstep(0.025, 0.045, r));
		col *= 1.0 - 0.35 * r * r;
	}
	ALBEDO = col * brightness;
}
