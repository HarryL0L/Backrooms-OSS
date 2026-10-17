// Found footage: makes the frame look like it was shot on a real, cheap
// camera rather than rendered. Reads the finished frame (any renderer).
//  mode 1 = phone camera: over-sharpened, soft corners, grain that grows in
//           the dark, colour blotching from 4:2:0 chroma and compression,
//           a slightly warm/cool auto white balance, clipped highlights.
//  mode 2 = camcorder tape: soft, colour bleeding sideways, faint interlace,
//           lifted blacks, now and then a tracking glitch band.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 1;
uniform float exposure = 1.0;              // auto exposure hunting (script)
uniform vec3 white_balance = vec3(1.0);    // auto white balance drift (script)
uniform float frame = 0.0;                 // frame counter for the noise
uniform float glitch = 0.0;                // camcorder tracking glitch strength

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 to_ycc(vec3 c) {
	return vec3(dot(c, vec3(0.299, 0.587, 0.114)), dot(c, vec3(-0.169, -0.331, 0.5)), dot(c, vec3(0.5, -0.419, -0.081)));
}

vec3 to_rgb(vec3 y) {
	return vec3(y.x + 1.402 * y.z, y.x - 0.344 * y.y - 0.714 * y.z, y.x + 1.772 * y.y);
}

vec3 tap(vec2 uv) {
	return textureLod(screen_tex, clamp(uv, vec2(0.001), vec2(0.999)), 0.0).rgb;
}

void fragment() {
	vec2 res = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 px = SCREEN_PIXEL_SIZE;
	bool cam = mode == 2;
	vec2 uv = SCREEN_UV;
	// Tracking glitch: a band that tears sideways for a moment.
	if (cam && glitch > 0.0) {
		float band = smoothstep(0.03, 0.0, abs(uv.y - fract(frame * 0.013 + 0.37)));
		uv.x += band * glitch * 0.02 * (hash(vec2(floor(uv.y * res.y * 0.5), frame)) - 0.3);
	}
	// Lens: barrel distortion, corners softer.
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	uv = 0.5 + c * (1.0 - (cam ? 0.09 : 0.05) * r2);
	float soft = (cam ? 1.6 : 0.7) + r2 * (cam ? 3.0 : 2.5);
	vec3 centre = tap(uv);
	vec3 blur = (tap(uv + vec2(px.x, 0.0) * soft) + tap(uv - vec2(px.x, 0.0) * soft)
			+ tap(uv + vec2(0.0, px.y) * soft) + tap(uv - vec2(0.0, px.y) * soft)) * 0.25;
	vec3 col;
	if (cam) {
		col = mix(centre, blur, 0.7);
	} else {
		// Phone processing over-sharpens (halos on edges).
		col = centre + (centre - blur) * 0.85;
	}
	// Chroma at lower resolution (4:2:0 / tape colour bandwidth); tape bleeds
	// colour sideways.
	vec3 ycc = to_ycc(col);
	vec2 cuv = cam ? uv + vec2(px.x * 3.0, 0.0) : (floor(uv * res / 2.0) + 0.5) * 2.0 * px;
	vec3 cc = to_ycc(cam ? (tap(cuv) + tap(cuv + vec2(px.x * 4.0, 0.0)) + tap(cuv - vec2(px.x * 2.0, 0.0))) / 3.0 : tap(cuv));
	ycc.yz = cc.yz * (cam ? 0.8 : 1.0);
	// Compression: in flat, dark areas the 8x8 blocks show.
	if (!cam) {
		vec2 bc = (floor(uv * res / 8.0) + 0.5) * 8.0 * px;
		float by = to_ycc(tap(bc)).x;
		float flat_k = (1.0 - smoothstep(0.0, 0.06, abs(ycc.x - by))) * (1.0 - smoothstep(0.05, 0.3, ycc.x));
		ycc.x = mix(ycc.x, by, flat_k * 0.6);
		ycc.x = mix(ycc.x, floor(ycc.x * 64.0 + 0.5) / 64.0, 1.0 - smoothstep(0.0, 0.25, ycc.x));
	}
	col = to_rgb(ycc);
	// Auto exposure and white balance.
	col *= exposure * white_balance;
	// Sensor noise: much stronger in the dark, coloured in the shadows.
	float y = dot(col, vec3(0.299, 0.587, 0.114));
	vec2 np = floor(FRAGCOORD.xy / (cam ? 1.5 : 1.0));
	float dark = 1.0 - smoothstep(0.0, 0.6, y);
	float nl = (hash(np + frame * 17.0) - 0.5) * (0.025 + 0.16 * dark * dark);
	vec3 nc = vec3(hash(np + frame * 3.1 + 1.7), hash(np + frame * 5.3 + 4.1), hash(np + frame * 7.7 + 9.3)) - 0.5;
	col += nl + nc * 0.07 * dark * dark;
	if (cam) {
		// Lifted blacks, softer contrast, faint interlace lines.
		col = col * 0.9 + 0.035;
		col *= 0.96 + 0.04 * step(0.5, fract(FRAGCOORD.y * 0.5));
	} else {
		// Highlights clip and lose colour.
		col = mix(col, vec3(max(col.r, max(col.g, col.b))), smoothstep(0.85, 1.05, y) * 0.6);
	}
	// Vignette.
	col *= 1.0 - r2 * (cam ? 0.9 : 0.55);
	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
