// Shared helpers for all world shaders.
// Lighting is baked per vertex by ChunkBuilder into CUSTOM0:
//   rgb = irradiance, a = share of it coming from a flickering lamp (UV2.x = lamp seed).

uniform uint world_seed = 0u;
// Set every frame by the game so light flicker and its buzzing sound stay in sync.
global uniform float world_time;

uint ihash(uint x) {
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	x = ((x >> 16u) ^ x) * 0x45d9f3bu;
	return (x >> 16u) ^ x;
}

// Must match WorldGen.flicker().
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

vec3 baked_light(vec4 custom0, float seed, float t) {
	float f = flicker(seed, t);
	return custom0.rgb * (1.0 - custom0.a * (1.0 - f));
}

// Same as WorldGen.hashi()/rnd(): uint arithmetic wraps exactly like the
// masked 64-bit integer maths on the GDScript side.
uint world_hash(int x, int z, uint salt) {
	uint h = (uint(x) * 0x27d4eb2du) ^ (uint(z) * 0x165667b1u) ^ (salt * 0x3c6ef372u) ^ world_seed;
	h = (h ^ (h >> 15u)) * 0x2c1b3c6du;
	h = (h ^ (h >> 12u)) * 0x297a2d39u;
	return h ^ (h >> 15u);
}

float world_rnd(int x, int z, uint salt) {
	return float(world_hash(x, z, salt) & 0xFFFFFFu) / 16777216.0;
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Reflection of the ceiling light grid seen in a mirror-like horizontal surface.
// mode 0 = Poolrooms (checker, 1.1 m panels), 1 = Habitable Zone (tubes every 3 cells).
vec3 ceiling_reflection(vec3 wpos, vec3 cam, vec3 n, float ceil_y, int mode, float t) {
	vec3 v = normalize(wpos - cam);
	vec3 r = reflect(v, n);
	if (r.y < 0.02) {
		return vec3(0.0);
	}
	float dist = (ceil_y - wpos.y) / r.y;
	vec2 hp = wpos.xz + r.xz * dist;
	vec2 cf = hp / 2.4;
	vec2 cl = floor(cf);
	vec2 fr = cf - cl - 0.5;
	int gx = int(cl.x);
	int gz = int(cl.y);
	float rr = world_rnd(gx, gz, 31u);
	vec2 half_size;
	vec3 col;
	float on = 1.0;
	if (mode == 0) {
		if (((gx + gz) & 1) != 0 || rr < 0.03) {
			return vec3(0.0);
		}
		half_size = vec2(0.55);
		col = vec3(0.9, 0.97, 1.0) * 3.0;
	} else {
		if (((gx % 3 + 3) % 3) != 1 || ((gz % 3 + 3) % 3) != 1 || rr < 0.2) {
			return vec3(0.0);
		}
		half_size = vec2(0.85, 0.12);
		col = vec3(0.82, 0.9, 1.0) * 6.0;
		if (rr < 0.36) {
			on = flicker(1.0 + float(world_hash(gx, gz, 32u) & 0xFFFFu), t);
		}
	}
	vec2 d = abs(fr * 2.4) - half_size;
	float blur = 0.02 + dist * 0.025;
	float mask = 1.0 - smoothstep(-blur, blur, max(d.x, d.y));
	return col * mask * on / (1.0 + dist * 0.15);
}

float dither(vec2 frag) {
	return (hash12(frag) - 0.5) / 255.0;
}
