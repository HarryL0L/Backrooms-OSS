// Shared helpers for all world shaders.
// Lighting is baked by ChunkBuilder, either per pixel into the chunk's
// lightmap (flat faces) or per vertex into CUSTOM0 (curved surfaces, props):
//   rgb = irradiance, a = share of it coming from a flickering lamp (UV2.x = lamp seed).
// CUSTOM1.xy = lightmap texel coordinates, or negative for per-vertex light.

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

// Lifts the darkest places a little (Potato preset: small, dim phone screens
// otherwise show them as flat black). Fades out by mid brightness, so lit
// rooms look the same. Set by Settings.apply().
global uniform float dark_lift;

vec3 baked_light(vec4 custom0, float seed, float t) {
	float f = flicker(seed, t);
	vec3 l = custom0.rgb * (1.0 - custom0.a * (1.0 - f));
	float lum = dot(l, vec3(0.3, 0.59, 0.11));
	return l + vec3(1.0, 0.95, 0.84) * dark_lift * (1.0 - smoothstep(0.0, 0.45, lum));
}

uniform sampler2D lightmap : hint_default_black, filter_linear, repeat_disable;
// Per texel: the seed of the flickering lamp its flicker share follows
// (16 bits in RG8, 0 = none).
uniform sampler2D lightmap_seed : hint_default_black, filter_nearest, repeat_disable;

// How much a lightmap texel is dimmed right now: its flicker share times how
// far its own lamp has dropped.
float lm_dim(ivec2 i, ivec2 sz) {
	i = clamp(i, ivec2(0), sz - 1);
	float share = texelFetch(lightmap, i, 0).a;
	if (share < 0.002) {
		return 0.0;
	}
	vec2 e = texelFetch(lightmap_seed, i, 0).rg * 255.0;
	float seed = floor(e.r + 0.5) + floor(e.g + 0.5) * 256.0;
	return seed < 0.5 ? 0.0 : share * (1.0 - flicker(seed, world_time));
}

// lm = (texel x, texel y, unused). Each texel dims with its own lamp, and the
// dimming of the four nearest texels is blended, so light from a flickering
// lamp fades smoothly across every face it reaches.
vec3 lightmap_light(vec3 vertex_light, vec3 lm) {
	if (lm.x < 0.0) {
		return vertex_light;
	}
	ivec2 sz = textureSize(lightmap, 0);
	vec4 s = texture(lightmap, lm.xy / vec2(sz));
	if (s.a < 0.002) {
		return s.rgb;
	}
	vec2 tc = lm.xy - 0.5;
	ivec2 i0 = ivec2(floor(tc));
	vec2 fr = tc - floor(tc);
	float d = mix(mix(lm_dim(i0, sz), lm_dim(i0 + ivec2(1, 0), sz), fr.x),
			mix(lm_dim(i0 + ivec2(0, 1), sz), lm_dim(i0 + ivec2(1, 1), sz), fr.x), fr.y);
	return s.rgb * (1.0 - d);
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
// mode 0 = Tiled Baths (checker, 1.1 m panels), 1 = Grey Floors (tubes every 3 cells).
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

// Height of the water surface in the Tiled Baths (WorldGen.WATER_Y). The planar
// reflection camera sits below it; for that camera everything under the plane is
// squashed onto the plane so it can't block the reflected view. Done in the vertex
// shader (not with discard) to keep early-Z intact on mobile GPUs.
const float REFLECT_PLANE = -0.16;

vec3 clip_below_water(vec3 v, vec3 cam) {
	if (cam.y < REFLECT_PLANE) {
		v.y = max(v.y, REFLECT_PLANE + 0.002);
	}
	return v;
}

bool below_reflection_plane(vec3 wpos, vec3 cam) {
	return cam.y < REFLECT_PLANE && wpos.y < REFLECT_PLANE;
}

// Shader-based flashlight, used instead of a SpotLight3D when real-time lights
// are disabled (some Mali drivers corrupt every Forward+ frame that processes
// a light node). Set every frame by Player: flash_params = (on, range,
// cos(outer angle), cos(inner angle)).
global uniform vec3 flash_pos;
global uniform vec3 flash_dir;
global uniform vec4 flash_params;

vec3 flashlight(vec3 wpos, vec3 n, vec3 cam, float gloss) {
	if (flash_params.x < 0.5) {
		return vec3(0.0);
	}
	vec3 to_light = flash_pos - wpos;
	float d = length(to_light);
	vec3 l = to_light / max(d, 0.0001);
	float cone = smoothstep(flash_params.z, flash_params.w, dot(-l, flash_dir));
	if (cone <= 0.0) {
		return vec3(0.0);
	}
	float fall = 1.0 - clamp(d / flash_params.y, 0.0, 1.0);
	float att = fall * fall / (1.0 + d * d * 0.06);
	float ndl = max(dot(n, l), 0.0);
	vec3 v = normalize(cam - wpos);
	float spec = pow(max(dot(n, normalize(l + v)), 0.0), mix(8.0, 96.0, gloss)) * gloss * 1.5;
	return vec3(1.0, 0.93, 0.80) * 5.0 * cone * att * (ndl + spec * ndl);
}

float dither(vec2 frag) {
	return (hash12(frag) - 0.5) / 255.0;
}

// ---------------------------------------------------------------- Photoreal ---
// Set from Settings: 1 in the Photoreal preset.
global uniform float photoreal;
// Directional lightmap (Photoreal): rgb = where the baked light comes from
// (world space, 0..1 encoded), a = 1 where there is a direction.
uniform sampler2D lightmap_dir : hint_default_black, filter_linear, repeat_disable;
// Optional photographed material (assets/textures/<surface>/), Photoreal only.
uniform sampler2D photo_albedo : source_color, hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D photo_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float photo_on = 0.0;
uniform float photo_scale = 1.0;          // metres per repeat
uniform vec3 photo_mean = vec3(0.5);      // average colour, so it adds detail, not a tint

// Photo detail as a multiplier around 1 (keeps our colours, adds the real grain).
vec3 photo_detail(vec2 uv) {
	if (photo_on < 0.5 || photoreal < 0.5) {
		return vec3(1.0);
	}
	return texture(photo_albedo, uv / photo_scale).rgb / max(photo_mean, vec3(0.05));
}

vec3 photo_nmap(vec2 uv, vec3 fallback) {
	if (photo_on < 0.5 || photoreal < 0.5) {
		return fallback;
	}
	return texture(photo_normal, uv / photo_scale).rgb;
}

// Tangent frame from screen derivatives (view space), so bump and parallax
// follow the surface's own UVs whatever way the mesh was built.
mat3 uv_frame(vec3 n, vec3 p, vec2 uv) {
	vec3 dp1 = dFdx(p);
	vec3 dp2 = dFdy(p);
	vec2 du1 = dFdx(uv);
	vec2 du2 = dFdy(uv);
	vec3 p2 = cross(dp2, n);
	vec3 p1 = cross(n, dp1);
	vec3 t = p2 * du1.x + p1 * du2.x;
	vec3 b = p2 * du1.y + p1 * du2.y;
	float inv = inversesqrt(max(max(dot(t, t), dot(b, b)), 1e-12));
	return mat3(t * inv, b * inv, n);
}

// A normal map sample (0..1 rgb, `depth` strength) as a view-space normal.
vec3 nmap_normal(vec3 nm, float depth, mat3 tbn) {
	vec2 xy = (nm.xy * 2.0 - 1.0) * depth;
	return normalize(tbn * vec3(xy, sqrt(max(1.0 - dot(xy, xy), 0.0))));
}

// How the surface detail tilts the baked light (directional lightmap): bumps
// facing the lamp get brighter, those facing away darker. 1 = no change.
float baked_bump(vec3 lm, vec3 n_detail, vec3 n_geom, mat4 view) {
	if (photoreal < 0.5 || lm.x < 0.0) {
		return 1.0;
	}
	vec4 d = texture(lightmap_dir, lm.xy / vec2(textureSize(lightmap_dir, 0)));
	if (d.a < 0.5) {
		return 1.0;
	}
	vec3 l = normalize((view * vec4(d.xyz * 2.0 - 1.0, 0.0)).xyz);
	float base = max(dot(n_geom, l), 0.3);
	return clamp(mix(1.0, max(dot(n_detail, l), 0.0) / base, 0.8), 0.3, 1.7);
}
