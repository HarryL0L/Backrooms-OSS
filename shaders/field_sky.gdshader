// Field sky under a tornadic supercell (FieldStorm, docs/FIELD_STORM.md).
// No raymarched volumes: every layer is a surface met analytically along the
// view ray, textured with noise. Overhead the anvil (~10 km up, its
// mammatus near the edge); toward the storm the dark rain-free base
// (1.2 km), striated round the mesocyclone, which turns; the wall cloud
// hanging under it; inflow scud racing in under the base; beyond them the
// clear sky. Then the air along the ray, by steps (field_air): the haze and
// the rain shafts, each lit by the storm's shade or by the sun behind the
// storm where it reaches, so the horizon under the base glows, the core's
// curtain stands grey-green, the rain shafts in the sun shine. A lightning
// flash lights the base from inside (lucid_lightning_sky). Engine units,
// then the camera's exposure.
shader_type sky;
#include "res://shaders/field_common.gdshaderinc"
#include "res://shaders/lucid_city.gdshaderinc"
#define FIELD_HAS_LUCID
#include "res://shaders/field_storm.gdshaderinc"

uniform sampler2D noise : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform int steps = 9;
// The layers' brightness against the shade light (field_light).
uniform float base_k = 0.62;
uniform float wall_k = 0.2;
uniform float anvil_k = 1.25;
// The clear sky beyond the storm: zenith and horizon (engine units).
uniform vec3 clear_zenith = vec3(5.0, 9.0, 19.0);
uniform vec3 clear_horizon = vec3(13.0, 16.0, 21.0);
// The ground's albedo far off.
uniform float ground_albedo = 0.11;

float nz(vec2 p, float scale) {
	return texture(noise, p / scale).r;
}

// Fades a noise octave to its mean as it nears the pixel footprint.
float oct(vec2 p, float scale, float dist, float fade) {
	return mix(nz(p, scale), 0.5, smoothstep(scale * fade * 0.5, scale * fade, dist));
}

vec3 base_light(vec2 p, float dist, float cover) {
	vec3 l = field_shade_at(p) * base_k;
	float n = oct(p, 3600.0, dist, 18.0) * 0.6 + oct(p, 900.0, dist, 14.0) * 0.3 + oct(p, 220.0, dist, 12.0) * 0.1;
	// Toward its edge the base thins and takes light from the side.
	float edge = 1.0 + 1.1 * (1.0 - cover);
	// Laminar bands round the mesocyclone, turning with it (faster inside).
	vec2 rel = p - field_meso.xy;
	float r = length(rel);
	float a = atan(rel.y, rel.x) - field_meso.w * clamp(1800.0 / max(r, 600.0), 0.3, 1.6);
	float band = sin(r * 0.0042 + nz(vec2(a * 900.0, r * 0.3), 2600.0) * 5.0);
	float near = 1.0 - smoothstep(1500.0, 6500.0, r);
	float s = 1.0 + 0.16 * band * near;
	// Darker where it lowers toward the updraft and the wall cloud.
	float low = 1.0 - 0.15 * (1.0 - smoothstep(1500.0, 5000.0, r));
	return l * (0.3 + 1.4 * n) * edge * s * low;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 eye = POSITION;
	float ey = eye.y - FIELD_Y;
	vec3 col;
	float dist = 40000.0;
	int n = AT_CUBEMAP_PASS ? 4 : steps;
	if (d.y < -0.0004) {
		// The ground beyond the mesh (the land is flat out there): the
		// storm's shade, the sun where it gets under the storm.
		dist = min(ey / -d.y, 40000.0);
		vec2 g = eye.xz + d.xz * dist;
		float lit = field_lit(g, 0.0);
		vec3 e = field_shade_at(g) * 1.3 + vec3(field_sun.w) * vec3(1.0, 0.95, 0.85) * field_sun.y * lit;
		col = e * ground_albedo * (0.8 + 0.4 * oct(g, 900.0, dist, 30.0));
	} else {
		float el = clamp(d.y, 0.0, 1.0);
		col = mix(clear_horizon, clear_zenith, pow(el, 0.45));
		float ph = field_phase(dot(d, field_sun.xyz));
		col += field_sunair.rgb * ph * 0.25 * (1.0 - el);
		if (d.y > 0.0005) {
			// The anvil: smooth, its edge ragged, mammatus hanging near it.
			float ta = (field_cloud.y - ey) / d.y;
			if (ta < 120000.0) {
				vec2 pa = eye.xz + d.xz * ta;
				float ca = field_anvil_cover(pa);
				float m = oct(pa, 1400.0, ta, 8.0);
				float mam = smoothstep(0.35, 0.95, ca) * (1.0 - smoothstep(0.95, 1.0, ca) * 0.6);
				vec3 al = field_light.rgb * anvil_k * (0.75 + 0.5 * oct(pa, 5200.0, ta, 12.0)) * mix(1.0, 0.55 + 0.9 * m * m, mam * 0.6);
				// Its thin edge glows where the sun is behind it.
				al += field_sunair.rgb * ph * 0.35 * (1.0 - ca) * smoothstep(0.0, 0.3, ca);
				col = mix(col, al, ca);
				if (ca > 0.5) {
					dist = min(dist, ta);
				}
			}
			// The base.
			float tb = (field_cloud.x - ey) / d.y;
			if (tb < 60000.0) {
				vec2 pb = eye.xz + d.xz * tb;
				float cb = field_base_cover(pb);
				if (cb > 0.001) {
					col = mix(col, base_light(pb, tb, cb), cb);
					if (cb > 0.4) {
						dist = min(dist, tb);
					}
				}
			}
		}
		// The wall cloud: a ragged drum hanging from the base round the
		// mesocyclone, its sides banded, turning.
		float hb = field_cloud.x - FIELD_WALL_DROP;
		vec2 o = eye.xz - field_meso.xy;
		float rm = 0.5 * (FIELD_WALL_R0 + FIELD_WALL_R1);
		float a2 = dot(d.xz, d.xz);
		float b2 = dot(o, d.xz);
		float c2 = dot(o, o) - rm * rm;
		float disc = b2 * b2 - a2 * c2;
		if (disc > 0.0 && a2 > 1e-6) {
			float tw = (-b2 - sqrt(disc)) / a2;
			float yw = ey + d.y * tw;
			vec2 pw = eye.xz + d.xz * tw;
			vec2 rel = pw - field_meso.xy;
			float ang = atan(rel.y, rel.x) - field_meso.w * 1.2;
			float u = (yw - hb) / FIELD_WALL_DROP;
			float rag = nz(vec2(ang * 700.0, yw * 1.6), 900.0);
			float fine = nz(vec2(ang * 2400.0, yw * 5.0 - TIME * 4.0), 420.0);
			// A soft, ragged foot (scud hanging from it), merging into the base above.
			float cw = smoothstep(-0.1, 0.55, u + (rag - 0.5) * 0.6) * (0.7 + 0.3 * fine) * (1.0 - step(1.0, u));
			// Its silhouette ragged, narrower toward its foot: e is 1 where the
			// ray grazes the drum.
			float e = sqrt(max(1.0 - b2 * b2 / (a2 * dot(o, o)), 0.0)) * length(o) / rm;
			cw *= 1.0 - smoothstep(0.55 + 0.35 * u, 1.0, e + (rag - 0.5) * 0.35 + (fine - 0.5) * 0.1);
			if (tw > 0.0 && cw > 0.001) {
				float bands = 0.85 + 0.3 * nz(vec2(ang * 1800.0, yw * 0.9 + ang * 300.0), 1600.0);
				// The base's own shade carried down, darker toward its ragged
				// foot (thicker cloud over it, lit only from the side).
				vec3 wl = base_light(pw, tw, 1.0) * mix(wall_k / base_k, 1.0, pow(clamp(u, 0.0, 1.0), 1.5)) * bands
						* (1.0 + 0.5 * (1.0 - smoothstep(0.0, 0.25, u)));
				col = mix(col, wl, cw);
				if (cw > 0.4) {
					dist = min(dist, tw);
				}
			}
		}
		// Inflow scud: ragged wisps ~450 m up racing in under the base
		// toward the wall cloud, lit a little brighter than the base.
		if (d.y > 0.002) {
			float ts = (450.0 - ey) / d.y;
			if (ts < 25000.0) {
				vec2 ps = eye.xz + d.xz * ts;
				vec2 flow = ps + field_wind.xy * TIME * 1.6;
				float k = oct(flow, 520.0, ts, 10.0) * 0.7 + oct(flow, 140.0, ts, 8.0) * 0.3;
				float near = (1.0 - smoothstep(2500.0, 7000.0, length(ps - field_meso.xy))) * field_base_cover(ps);
				float cs = smoothstep(0.62, 0.8, k) * near * 0.85 * (1.0 - smoothstep(6000.0, 12000.0, ts));
				col = mix(col, field_shade_at(ps) * (0.55 + 0.4 * k), cs);
			}
		}
	}
	vec4 air = field_air(eye, d, dist, n);
	col = col * air.a + air.rgb;
	col += lucid_lightning_sky(d);
	COLOR = col * lucid_exposure.rgb;
}
