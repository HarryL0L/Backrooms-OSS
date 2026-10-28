// Experimental path-traced lighting (PathTracer / PathTraceEffect): while
// it's on (pt_on, only in the Lobby), the Lobby's walls, carpet, ceiling and
// trim take their light from the path tracer instead of the baked lightmap.
// `pt_light` is the tracer's low-resolution result for this very frame
// (traced before the opaque pass from the same camera): rgb = irradiance / pi,
// a = which surface each texel saw (normal id * 1000 + 500 + the plane's
// coordinate relative to the camera, see shaders/pt/pt_trace.glsl; 0 none).
// It's upsampled here: of the four nearest texels only the ones that saw this
// same face count (no light leaking across corners or onto things in front).
global uniform float pt_on;
global uniform sampler2D pt_light : filter_nearest;

// rgb = light, a = 1 when it came from the path tracer (else use the baked).
vec4 pt_sample(vec3 wpos, vec3 cam, vec2 screen_uv) {
	if (pt_on < 0.5) {
		return vec4(0.0);
	}
	vec3 gn = cross(dFdx(wpos), dFdy(wpos));
	vec3 an = abs(gn);
	int ax = an.x > an.y ? (an.x > an.z ? 0 : 2) : (an.y > an.z ? 1 : 2);
	float rel = wpos[ax] - cam[ax];
	int nid = ax * 2 + (rel < 0.0 ? 0 : 1);
	float code = float(nid) * 1000.0 + 500.0 + rel;
	ivec2 sz = textureSize(pt_light, 0);
	vec2 p = screen_uv * vec2(sz) - 0.5;
	ivec2 b0 = ivec2(floor(p));
	vec2 f = p - vec2(b0);
	vec3 sum = vec3(0.0);
	float ws = 0.0;
	for (int k = 0; k < 4; k++) {
		ivec2 o = ivec2(k & 1, k >> 1);
		vec4 s = texelFetch(pt_light, clamp(b0 + o, ivec2(0), sz - 1), 0);
		float d = abs(s.a - code);
		if (s.a > 0.0 && d < 0.05) {
			float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y) + 0.001;
			sum += s.rgb * w;
			ws += w;
		}
	}
	if (ws > 0.0) {
		return vec4(sum / ws, 1.0);
	}
	// None of them saw this face (a thin edge, a corner): the closest match
	// around it.
	ivec2 c = b0 + ivec2(round(f));
	float best = 0.2;
	vec3 col = vec3(0.0);
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec4 s = texelFetch(pt_light, clamp(c + ivec2(i, j), ivec2(0), sz - 1), 0);
			float d = abs(s.a - code);
			if (s.a > 0.0 && d < best) {
				best = d;
				col = s.rgb;
			}
		}
	}
	return best < 0.2 ? vec4(col, 1.0) : vec4(0.0);
}
