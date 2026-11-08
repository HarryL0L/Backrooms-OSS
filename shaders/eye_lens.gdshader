// Body cam (Settings > Body cam): the view is rendered wide (128 degrees
// across), which a flat projection stretches badly at the edges; this bends
// it like a body camera's fisheye lens: the middle a little enlarged, the
// edges squeezed and curved, the corners falling off darker. Where it
// rains, the drops on its window (HUD._lens_drops).
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.34;     // 0 flat .. how much the middle is enlarged
uniform float falloff = 0.35;      // corner darkening (a fisheye lens loses light at the rim)
uniform float aspect = 1.7778;
uniform float noise = 0.0;         // sensor noise, only in the dark (Realistic)
// Raindrops on the lens window (HUD._lens_drops): x, y (screen), radius
// (of the height), opacity; their wet tracks: where it began to run (y),
// the track's opacity, a seed.
uniform int drop_n = 0;
uniform vec4 drops[12];
uniform vec4 trails[12];

float rand(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	// Radius in screen proportions, 1 at the corners.
	float r = length(c * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0) * 0.5);
	vec2 src = 0.5 + c * ((1.0 - strength) + strength * r * r);
	float rim = 1.0 - falloff * smoothstep(0.55, 1.05, r);
	// A drop on the window, a centimetre in front of a lens focused far
	// off, is a blurred blob: a small lens of its own, it shows the scene
	// round it shrunk and turned over, soft-edged, darker at its rim
	// (light bent out of the picture). A running drop's track is a thin
	// smear of water.
	float blur = 0.0;
	float br = 0.0;
	vec2 off = vec2(0.0);
	float shade = 1.0;
	for (int i = 0; i < drop_n; i++) {
		vec4 d = drops[i];
		vec2 q = (SCREEN_UV - d.xy) * vec2(aspect, 1.0);
		float dr = length(q) / d.z;
		if (dr < 1.0) {
			// (Soft: out of focus, a drop's edge is a blurred ring.)
			float m = (1.0 - smoothstep(0.55, 1.0, dr)) * d.w;
			off -= q / vec2(aspect, 1.0) * (0.6 * m * (1.0 - 0.5 * dr * dr));
			blur = max(blur, m);
			br = max(br, d.z * m);
			shade += 0.12 * m * smoothstep(0.4, 0.8, dr) - 0.08 * m * (1.0 - dr);
		}
		vec4 tr = trails[i];
		if (tr.y > 0.0 && SCREEN_UV.y < d.y && SCREEN_UV.y > tr.x) {
			float wob = sin(SCREEN_UV.y * 40.0 + tr.z) * 0.004;
			float tw = abs((SCREEN_UV.x - d.x - wob) * aspect) / (d.z * 0.3);
			float m = (1.0 - smoothstep(0.4, 1.0, tw)) * tr.y * smoothstep(tr.x, d.y, SCREEN_UV.y);
			off.x -= (SCREEN_UV.x - d.x - wob) * 0.8 * m;
			blur = max(blur, m * 0.7);
			br = max(br, d.z * 0.3 * m);
		}
	}
	vec3 col = textureLod(screen_tex, src + off, 0.0).rgb;
	if (blur > 0.0) {
		// The blur: eight taps round the point (the screen copy has no
		// mipmaps to read), as wide as a third of the drop.
		vec3 b = col;
		for (int k = 0; k < 8; k++) {
			float an = float(k) * 0.785398 + 0.3;
			b += textureLod(screen_tex, src + off + vec2(cos(an) / aspect, sin(an)) * br * 0.35, 0.0).rgb;
		}
		col = mix(col, b / 9.0, blur) * shade;
	}
	col *= rim;
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
