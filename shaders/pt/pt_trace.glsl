#[compute]
#version 450
// Experimental path-traced lighting for the Lobby (PathTracer, PathTraceEffect).
//
// One thread per low-resolution pixel. The world near the player is a grid of
// 2.4 m cells (ChunkBuilder._pt_cells: walls on the cell edges, posts and
// pillars on the corners, floor at 0, a flat ceiling with troffers in it), so
// rays are traced analytically through the grid (a DDA over the cells, ray /
// box tests for the walls in each) instead of against triangles.
//
// Per pixel: the camera ray finds the surface (as the raster pass will draw
// it), then one path sample: next-event estimation to one of the nearby
// troffers (picked in proportion to its unshadowed light, a random point on
// the panel, shadow ray), one or two cosine-weighted bounces with the same
// estimate at each hit. The result is irradiance / pi (what the surface
// shaders multiply their albedo by), accumulated over frames with
// reprojection to the previous frame (rejected where the surface differs).
//
// Surface id ("geo", one float): normal id * 1000 + 500 + the surface's plane
// coordinate relative to the camera (n.x faces: x, ...), 0 = nothing / not
// traced. Normal ids: 0 +x, 1 -x, 2 +y, 3 -y, 4 +z, 5 -z.

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(set = 0, binding = 0, std140) uniform Params {
	mat4 inv_proj;      // clip -> view (this frame)
	mat4 cam_basis;     // view -> world rotation (this frame)
	mat4 prev_vp;       // world -> clip (previous frame)
	vec4 cam_pos;       // xyz, w = world time (s)
	vec4 prev_cam;      // xyz, w = light radiance scale
	ivec4 win;          // window origin cell x, z, window size (cells), frame number
	ivec4 dims;         // low-res width, height, bounces, reset history
	vec4 light_col;     // rgb, a = max history length
	vec4 misc;          // x ambient, y firefly clamp, z, w unused
} P;

layout(set = 0, binding = 1, rgba16ui) uniform readonly uimage2D cells;
layout(set = 0, binding = 2, rgba32f) uniform readonly image2D hist_in;
layout(set = 0, binding = 3, r32f) uniform readonly image2D geo_in;
layout(set = 0, binding = 4, rgba32f) uniform writeonly image2D hist_out;
layout(set = 0, binding = 5, r32f) uniform writeonly image2D geo_out;

const float CELL = 2.4;
const float T = 0.15;
const float PI = 3.14159265;
// WorldGen.CEIL_H, DOOR_W, DOOR_H, LIGHT_POWER; ChunkBuilder.PANEL_SIZE, ALB_*.
const float CEIL_H[6] = float[](3.0, 4.8, 6.0, 2.7, 2.7, 2.6);
const float DOOR_W[7] = float[](0.0, 0.0, 1.1, 1.7, 1.7, 0.95, 1.8);
const float DOOR_H[7] = float[](0.0, 0.0, 2.1, 3.1, 2.7, 3.95, 2.6);
const float POWER[6] = float[](1.0, 1.06, 1.56, 0.62, 1.06, 1.06);
const vec2 PANEL[6] = vec2[](vec2(1.22, 0.62), vec2(0.62, 0.62), vec2(1.7, 0.24), vec2(1.22, 0.62), vec2(0.6, 0.6), vec2(1.3, 0.12));
const vec3 ALB_WALL = vec3(0.72, 0.65, 0.34);
const vec3 ALB_FLOOR = vec3(0.52, 0.41, 0.22);
const vec3 ALB_CEIL = vec3(0.78, 0.76, 0.66);

// ------------------------------------------------------------- random ---

uint rng;

uint pcg(uint v) {
	uint s = v * 747796405u + 2891336453u;
	uint w = ((s >> ((s >> 28u) + 4u)) ^ s) * 277803737u;
	return (w >> 22u) ^ w;
}

float rnd() {
	rng = pcg(rng);
	return float(rng >> 8u) / 16777216.0;
}

// ---------------------------------------------------------------- grid ---

// Cell data, or zero (not loaded: rays stop there) outside the window.
uvec4 cell(int gx, int gz) {
	ivec2 l = ivec2(gx - P.win.x, gz - P.win.y);
	if (l.x < 0 || l.y < 0 || l.x >= P.win.z || l.y >= P.win.z) {
		return uvec4(0u);
	}
	return imageLoad(cells, l);
}

// Must match flicker() in common.gdshaderinc.
uint ihash(uint x) {
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	return (x >> 16u) ^ x;
}

float flicker(float seed, float t) {
	if (seed < 0.5) {
		return 1.0;
	}
	int s = int(seed);
	int burst_slot = int(floor(t * 0.45 + seed * 0.37));
	uint b = ihash(uint(s * 31 + burst_slot * 7919));
	if (float(b & 65535u) / 65535.0 < 0.72) {
		return 1.0;
	}
	uint f = ihash(uint(s * 131 + int(floor(t * 14.0)) * 104729));
	float v = float(f & 65535u) / 65535.0;
	return v < 0.45 ? 0.0 : 0.55 + 0.45 * v;
}

// How bright a cell's troffer is right now (0 none / dead).
float light_on(uvec4 c) {
	uint s = (c.x >> 4u) & 15u;
	if (s == 1u) {
		return 1.0;
	}
	if (s == 2u) {
		return flicker(float(c.w), P.cam_pos.w);
	}
	return 0.0;
}

int biome(uvec4 c) {
	return int(min((c.x >> 8u) & 15u, 5u));
}

// ----------------------------------------------------------- intersect ---

struct Ray {
	vec3 o;
	vec3 d;
	vec3 inv;
};

// Ray / box: closest entry after the origin, keeps the nearest in t / n.
void box(Ray r, vec3 lo, vec3 hi, inout float t, inout int n) {
	vec3 a = (lo - r.o) * r.inv;
	vec3 b = (hi - r.o) * r.inv;
	vec3 mn = min(a, b);
	vec3 mx = max(a, b);
	float tn = max(max(mn.x, mn.y), mn.z);
	float tf = min(min(mx.x, mx.y), mx.z);
	if (tn > tf || tn <= 1e-4 || tn >= t) {
		return;
	}
	t = tn;
	if (tn == mn.x) {
		n = r.d.x > 0.0 ? 1 : 0;
	} else if (tn == mn.y) {
		n = r.d.y > 0.0 ? 3 : 2;
	} else {
		n = r.d.z > 0.0 ? 5 : 4;
	}
}

// A wall on a cell edge: `vertical` = on the line x = `line`, running along
// z from `s0` (one cell); otherwise on z = `line`, along x. Doorways and
// archways are open below their lintel.
void wall(Ray r, uint kind, bool vertical, float line, float s0, float ceil_y, inout float t, inout int n) {
	if (kind == 0u) {
		return;
	}
	float a0 = s0 + T;
	float a1 = s0 + CELL - T;
	if (kind == 1u || kind > 6u) {
		if (vertical) {
			box(r, vec3(line - T, -0.5, a0), vec3(line + T, ceil_y, a1), t, n);
		} else {
			box(r, vec3(a0, -0.5, line - T), vec3(a1, ceil_y, line + T), t, n);
		}
		return;
	}
	float w = DOOR_W[kind];
	float mid = s0 + CELL * 0.5;
	float o0 = mid - w * 0.5;
	float o1 = mid + w * 0.5;
	float yt = min(DOOR_H[kind], ceil_y - 0.05);
	if (vertical) {
		box(r, vec3(line - T, -0.5, a0), vec3(line + T, ceil_y, o0), t, n);
		box(r, vec3(line - T, -0.5, o1), vec3(line + T, ceil_y, a1), t, n);
		box(r, vec3(line - T, yt, o0), vec3(line + T, ceil_y, o1), t, n);
	} else {
		box(r, vec3(a0, -0.5, line - T), vec3(o0, ceil_y, line + T), t, n);
		box(r, vec3(o1, -0.5, line - T), vec3(a1, ceil_y, line + T), t, n);
		box(r, vec3(o0, yt, line - T), vec3(o1, ceil_y, line + T), t, n);
	}
}

void post(Ray r, uint half_mm, float vx, float vz, float ceil_y, inout float t, inout int n) {
	if (half_mm == 0u) {
		return;
	}
	float h = float(half_mm) * 0.001;
	box(r, vec3(vx - h, -0.5, vz - h), vec3(vx + h, ceil_y, vz + h), t, n);
}

// Traces a ray up to `tmax`. Returns true on a hit: t, normal id n and
// surface s (0 wall, 1 floor, 2 ceiling, 3 the edge of the known world /
// inside something solid: no light comes from there).
bool trace(vec3 o, vec3 d, float tmax, int max_cells, out float t, out int n, out int s, out ivec2 hc) {
	Ray r;
	r.o = o;
	r.d = d;
	r.inv = 1.0 / vec3(abs(d.x) < 1e-7 ? 1e-7 : d.x, abs(d.y) < 1e-7 ? 1e-7 : d.y, abs(d.z) < 1e-7 ? 1e-7 : d.z);
	vec2 p = o.xz / CELL;
	ivec2 g = ivec2(floor(p));
	vec2 dd = d.xz;
	ivec2 st = ivec2(dd.x > 0.0 ? 1 : -1, dd.y > 0.0 ? 1 : -1);
	vec2 tdel = abs(CELL * r.inv.xz);
	vec2 nb = vec2(g + max(st, ivec2(0))) * CELL;
	vec2 tnext = (nb - o.xz) * r.inv.xz;
	float t0 = 0.0;
	n = 0;
	s = 3;
	hc = g;
	for (int i = 0; i < max_cells; i++) {
		float t1 = min(min(tnext.x, tnext.y), tmax);
		uvec4 c = cell(g.x, g.y);
		hc = g;
		if ((c.x & 2u) == 0u || (c.x & 1u) != 0u) {
			t = t0;
			s = 3;
			return true;
		}
		float cy = CEIL_H[biome(c)];
		float best = 1e30;
		int bn = 0;
		int bs = 0;
		if (d.y > 0.0) {
			float tc = (cy - o.y) * r.inv.y;
			if (tc > 1e-4 && tc < best) {
				best = tc;
				bn = 3;
				bs = 2;
			}
		} else {
			float tf = -o.y * r.inv.y;
			if (tf > 1e-4 && tf < best) {
				best = tf;
				bn = 2;
				bs = 1;
			}
		}
		float bw = best;
		uvec4 ce = cell(g.x + 1, g.y);
		uvec4 cs = cell(g.x, g.y + 1);
		uvec4 cse = cell(g.x + 1, g.y + 1);
		float x0 = float(g.x) * CELL;
		float z0 = float(g.y) * CELL;
		wall(r, c.y & 255u, true, x0, z0, cy, bw, bn);
		wall(r, ce.y & 255u, true, x0 + CELL, z0, cy, bw, bn);
		wall(r, c.y >> 8u, false, z0, x0, cy, bw, bn);
		wall(r, cs.y >> 8u, false, z0 + CELL, x0, cy, bw, bn);
		post(r, c.z, x0, z0, cy, bw, bn);
		post(r, ce.z, x0 + CELL, z0, cy, bw, bn);
		post(r, cs.z, x0, z0 + CELL, cy, bw, bn);
		post(r, cse.z, x0 + CELL, z0 + CELL, cy, bw, bn);
		if (bw < best) {
			best = bw;
			bs = 0;
		}
		if (best <= t1 + 1e-4) {
			if (best > tmax) {
				return false;
			}
			t = best;
			n = bn;
			s = bs;
			return true;
		}
		if (t1 >= tmax) {
			return false;
		}
		t0 = t1;
		if (tnext.x < tnext.y) {
			tnext.x += tdel.x;
			g.x += st.x;
		} else {
			tnext.y += tdel.y;
			g.y += st.y;
		}
	}
	return false;
}

bool occluded(vec3 o, vec3 d, float dist) {
	float t;
	int n;
	int s;
	ivec2 hc;
	return trace(o, d, dist, 12, t, n, s, hc);
}

vec3 normal_of(int n) {
	vec3 v = vec3(0.0);
	v[n >> 1] = (n & 1) == 0 ? 1.0 : -1.0;
	return v;
}

// --------------------------------------------------------------- light ---

// One light sample: the troffer picked (centre, size, power) and its share.
struct Pick {
	vec3 c;
	vec2 sz;
	float pw;
	float w;
};

// The light from a picked troffer: a random point on it, shadow ray.
vec3 light_sample(vec3 p, vec3 nn, Pick k, float wsum) {
	vec3 y = k.c + vec3((rnd() - 0.5) * k.sz.x, 0.0, (rnd() - 0.5) * k.sz.y);
	vec3 v = y - p;
	float d2 = dot(v, v);
	float d = sqrt(d2);
	vec3 l = v / d;
	float cp = dot(nn, l);
	float cl = l.y;
	if (cp <= 0.0 || cl <= 0.0) {
		return vec3(0.0);
	}
	if (occluded(p + nn * 0.002, l, d - 0.01)) {
		return vec3(0.0);
	}
	// L * A * cos * cos / d^2 / pdf(light), / pi.
	return vec3(k.pw * cp * cl * k.sz.x * k.sz.y / max(d2, 0.02) * (wsum / k.w) / PI);
}

// Direct irradiance / pi at p (normal nn) from the troffers in the cells
// within `rad` of cell hc: `n` (1 or 2) of them picked in proportion to their
// unshadowed light (one pass over the cells, a reservoir per sample).
vec3 direct(vec3 p, vec3 nn, ivec2 hc, int rad, int n) {
	float wsum = 0.0;
	Pick k0 = Pick(vec3(0.0), vec2(0.0), 0.0, 0.0);
	Pick k1 = k0;
	for (int dz = -rad; dz <= rad; dz++) {
		for (int dx = -rad; dx <= rad; dx++) {
			ivec2 lc = hc + ivec2(dx, dz);
			uvec4 c = cell(lc.x, lc.y);
			if ((c.x & 2u) == 0u) {
				continue;
			}
			float on = light_on(c);
			if (on <= 0.0) {
				continue;
			}
			int b = biome(c);
			vec3 lp = vec3((float(lc.x) + 0.5) * CELL, CEIL_H[b] - 0.012, (float(lc.y) + 0.5) * CELL);
			vec3 v = lp - p;
			float d2 = dot(v, v) + 0.05;
			float inv_d = inversesqrt(d2);
			float cp = max(dot(nn, v) * inv_d, 0.0) + 0.03;
			float cl = max(v.y * inv_d, 0.0) + 0.03;
			float pw = on * POWER[b];
			float w = pw * PANEL[b].x * PANEL[b].y * cp * cl / d2;
			wsum += w;
			Pick k = Pick(lp, PANEL[b], pw, w);
			if (rnd() * wsum < w) {
				k0 = k;
			}
			if (n > 1 && rnd() * wsum < w) {
				k1 = k;
			}
		}
	}
	if (wsum <= 0.0) {
		return vec3(0.0);
	}
	vec3 e = light_sample(p, nn, k0, wsum);
	if (n > 1) {
		e = (e + light_sample(p, nn, k1, wsum)) * 0.5;
	}
	return e;
}

vec3 albedo(int s) {
	return s == 0 ? ALB_WALL : (s == 1 ? ALB_FLOOR : ALB_CEIL);
}

// Cosine-weighted direction around an axis normal.
vec3 cos_dir(vec3 nn) {
	float u = rnd();
	float v = rnd();
	float r = sqrt(u);
	float a = 2.0 * PI * v;
	vec3 tt = abs(nn.y) > 0.5 ? vec3(1.0, 0.0, 0.0) : vec3(0.0, 1.0, 0.0);
	vec3 bb = cross(nn, tt);
	tt = cross(bb, nn);
	return normalize(tt * (r * cos(a)) + bb * (r * sin(a)) + nn * sqrt(max(1.0 - u, 0.0)));
}

float plane_of(vec3 p, int n) {
	return p[n >> 1];
}

float geo_code(int n, float plane_rel) {
	return float(n) * 1000.0 + 500.0 + clamp(plane_rel, -400.0, 400.0);
}

// ---------------------------------------------------------------- main ---

void main() {
	ivec2 px = ivec2(gl_GlobalInvocationID.xy);
	if (px.x >= P.dims.x || px.y >= P.dims.y) {
		return;
	}
	// (Row 0 is clip y = -1: the same way up as SCREEN_UV in the surface
	// shaders on the RenderingDevice renderers.)
	vec2 uv = (vec2(px) + 0.5) / vec2(P.dims.xy);
	vec4 vr = P.inv_proj * vec4(uv * 2.0 - 1.0, 1.0, 1.0);
	vec3 dir = normalize(mat3(P.cam_basis) * (vr.xyz / vr.w));
	vec3 cam = P.cam_pos.xyz;
	float t;
	int n;
	int s;
	ivec2 hc;
	if (!trace(cam, dir, 120.0, 64, t, n, s, hc) || s == 3) {
		imageStore(geo_out, px, vec4(0.0));
		imageStore(hist_out, px, vec4(0.0));
		return;
	}
	vec3 p = cam + dir * t;
	vec3 nn = normal_of(n);
	rng = pcg(uint(px.x) * 1973u + uint(px.y) * 9277u + uint(P.win.w) * 26699u);

	// One path sample: direct light here, then the bounces.
	vec3 sum = direct(p, nn, hc, 3, 2);
	vec3 thr = vec3(1.0);
	vec3 bp = p;
	vec3 bn = nn;
	for (int k = 0; k < P.dims.z; k++) {
		vec3 d = cos_dir(bn);
		float bt;
		int bnid;
		int bs;
		ivec2 bc;
		if (!trace(bp + bn * 0.002, d, 40.0, 24, bt, bnid, bs, bc) || bs == 3) {
			break;
		}
		bp = bp + bn * 0.002 + d * bt;
		bn = normal_of(bnid);
		thr *= albedo(bs);
		sum += thr * direct(bp, bn, bc, 2, 1);
	}
	sum = sum * P.light_col.rgb * P.prev_cam.w;
	// Clamp fireflies (rare near-wall light samples).
	float lum = dot(sum, vec3(0.3, 0.59, 0.11));
	if (lum > P.misc.y) {
		sum *= P.misc.y / lum;
	}

	// Temporal accumulation: the same surface point in the previous frame.
	float plane = plane_of(p, n);
	float geo = geo_code(n, plane - cam[n >> 1]);
	vec4 h = vec4(0.0);
	float hw = 0.0;
	if (P.dims.w == 0) {
		vec4 clip = P.prev_vp * vec4(p, 1.0);
		if (clip.w > 0.01) {
			vec2 puv = clip.xy / clip.w * 0.5 + 0.5;
			vec2 pp = puv * vec2(P.dims.xy) - 0.5;
			ivec2 b0 = ivec2(floor(pp));
			vec2 f = pp - vec2(b0);
			for (int k = 0; k < 4; k++) {
				ivec2 o = ivec2(k & 1, k >> 1);
				ivec2 q = b0 + o;
				if (q.x < 0 || q.y < 0 || q.x >= P.dims.x || q.y >= P.dims.y) {
					continue;
				}
				float g = imageLoad(geo_in, q).r;
				int gn = int(floor(g / 1000.0));
				if (g <= 0.0 || gn != n) {
					continue;
				}
				float gp = g - float(gn) * 1000.0 - 500.0 + P.prev_cam[n >> 1];
				if (abs(gp - plane) > 0.05) {
					continue;
				}
				float w = (o.x == 1 ? f.x : 1.0 - f.x) * (o.y == 1 ? f.y : 1.0 - f.y);
				h += imageLoad(hist_in, q) * w;
				hw += w;
			}
		}
	}
	float count = 1.0;
	vec3 res = sum;
	if (hw > 0.05) {
		h /= hw;
		count = min(h.a * min(hw * 1.5, 1.0) + 1.0, P.light_col.a);
		res = mix(h.rgb, sum, 1.0 / count);
	}
	imageStore(hist_out, px, vec4(res, count));
	imageStore(geo_out, px, vec4(geo));
}
