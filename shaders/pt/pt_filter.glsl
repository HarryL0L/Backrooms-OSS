#[compute]
#version 450
// Experimental path-traced lighting: one pass of an a-trous wavelet filter
// (3 x 3 taps `step` pixels apart) over the accumulated irradiance, guided by
// the surface id (pt_trace.glsl: same face and plane) and by luminance, with
// the luminance tolerance wide where the history is short (noisy) and narrow
// where it has converged. Run with steps 1, 2, 4, 8. Writes rgb + the
// surface id in alpha, which the surface shaders use to upsample
// (pt_light.gdshaderinc).

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, rgba32f) uniform readonly image2D src;
layout(set = 0, binding = 1, r32f) uniform readonly image2D geo;
layout(set = 0, binding = 2, rgba32f) uniform readonly image2D hist;
layout(set = 0, binding = 3, rgba32f) uniform writeonly image2D dst;

layout(push_constant, std430) uniform Push {
	ivec2 size;
	int step;
	float strength;     // luminance tolerance scale
} pc;

float plane_of(float g, out int n) {
	n = int(floor(g / 1000.0));
	return g - float(n) * 1000.0;
}

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= pc.size.x || px.y >= pc.size.y) {
		return;
	}
	float g0 = imageLoad(geo, px).r;
	vec4 c0 = imageLoad(src, px);
	if (g0 <= 0.0) {
		imageStore(dst, px, vec4(c0.rgb, 0.0));
		return;
	}
	int n0;
	float p0 = plane_of(g0, n0);
	float count = max(imageLoad(hist, px).a, 1.0);
	const float K[3] = float[](0.25, 0.5, 0.25);
	// The taps on the same surface, and their mean brightness.
	vec3 cs[9];
	float ws[9];
	float lm = 0.0;
	float wm = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			int t = (i + 1) + (j + 1) * 3;
			ws[t] = 0.0;
			cs[t] = vec3(0.0);
			ivec2 q = px + ivec2(i, j) * pc.step;
			if (q.x < 0 || q.y < 0 || q.x >= pc.size.x || q.y >= pc.size.y) {
				continue;
			}
			float g = imageLoad(geo, q).r;
			int n;
			float p = plane_of(g, n);
			if (g <= 0.0 || n != n0 || abs(p - p0) > 0.04) {
				continue;
			}
			cs[t] = imageLoad(src, q).rgb;
			ws[t] = K[i + 1] * K[j + 1];
			lm += dot(cs[t], vec3(0.3, 0.59, 0.11)) * ws[t];
			wm += ws[t];
		}
	}
	lm /= max(wm, 1e-6);
	float l0 = dot(c0.rgb, vec3(0.3, 0.59, 0.11));
	// Noisy (young) pixels blur freely; converged ones keep their detail.
	// (Relative to the local mean, so a lone black or bright sample is
	// smoothed away rather than kept as an edge.)
	float sig = pc.strength * (0.02 + lm * (0.15 + 2.5 / sqrt(count))) + 1e-5;
	vec3 sum = vec3(0.0);
	float wsum = 0.0;
	for (int t = 0; t < 9; t++) {
		if (ws[t] <= 0.0) {
			continue;
		}
		float l = dot(cs[t], vec3(0.3, 0.59, 0.11));
		float w = ws[t] * exp(-abs(l - (t == 4 ? l : mix(l0, lm, 0.5))) / sig);
		sum += cs[t] * w;
		wsum += w;
	}
	imageStore(dst, px, vec4(wsum > 0.0 ? sum / wsum : c0.rgb, g0));
}
