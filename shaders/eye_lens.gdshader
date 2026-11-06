// Body cam (Settings > Body cam): the view is rendered wide (128 degrees
// across), which a flat projection stretches badly at the edges; this bends
// it like a body camera's fisheye lens: the middle a little enlarged, the
// edges squeezed and curved, the corners falling off darker.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.34;     // 0 flat .. how much the middle is enlarged
uniform float falloff = 0.35;      // corner darkening (a fisheye lens loses light at the rim)
uniform float aspect = 1.7778;
uniform float noise = 0.0;         // sensor noise, only in the dark (Realistic)

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	// Radius in screen proportions, 1 at the corners.
	float r = length(c * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0) * 0.5);
	vec2 src = 0.5 + c * ((1.0 - strength) + strength * r * r);
	float rim = 1.0 - falloff * smoothstep(0.55, 1.05, r);
	vec3 col = textureLod(screen_tex, src, 0.0).rgb * rim;
	if (noise > 0.0) {
		// A small sensor's noise: coarse, a little coloured, and only where
		// the image is dark (bright areas stay clean).
		vec2 px = floor(FRAGCOORD.xy * 0.5) + floor(TIME * 30.0) * 17.13;
		vec3 n = vec3(rand(px), rand(px + 3.7), rand(px + 9.1)) - 0.5;
		float dark = 1.0 - smoothstep(0.02, 0.35, dot(col, vec3(0.3, 0.59, 0.11)));
		col = max(col + (n.g + (n - n.g) * 0.4) * noise * dark, vec3(0.0));
	}
	COLOR = vec4(col, 1.0);
}
