shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
#include "res://shaders/water.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec3 tile_color : source_color = vec3(0.93, 0.94, 0.91);
uniform vec3 grout_color : source_color = vec3(0.62, 0.68, 0.69);
uniform float water_y = -0.16;
uniform float ceiling_y = 4.8;
// Seen through the water. Absorption per metre of clear chlorinated water
// (red goes first, then green: shallow water is nearly clear, long paths
// turn teal), and the faint blue-green glow light scattered in it gives.
uniform vec3 water_absorb = vec3(0.45, 0.07, 0.03);
uniform vec3 water_scatter : source_color = vec3(0.08, 0.32, 0.40);
// Cell-edge noise (WorldMaterials): two drifting layers make the caustic net.
uniform sampler2D noise_caustic : hint_default_white, filter_linear_mipmap, repeat_enable;

varying vec3 v_vlight;
varying vec3 v_lm;
varying vec3 v_wpos;
varying vec3 v_wnormal;
varying float v_wet;

void vertex() {
	VERTEX = clip_below_water(VERTEX, CAMERA_POSITION_WORLD);
	v_vlight = baked_light(CUSTOM0, UV2.x, world_time);
	v_lm = vec3(CUSTOM1.xy, flicker(UV2.x, world_time));
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnormal = NORMAL;
	v_wet = UV2.y;   // ChunkBuilder._wetness(): 1 at a pool's rim
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
	v_ps1_aff = vec3(UV * POSITION.w, POSITION.w);
}

// PS1 style: the old soft caustics.
float caustics(vec2 p, float t) {
	float n1 = texture(noise_fine, p * 0.33 + t * vec2(0.031, 0.022)).r;
	float n2 = texture(noise_fine, p * 0.29 - t * vec2(0.024, 0.035) + 0.5).r;
	return pow(clamp(1.0 - abs(n1 - n2) * 3.5, 0.0, 1.0), 3.0);
}

// Light focused by the rippling surface onto the bottom: a bright net of
// two drifting cell-edge layers, brightest where they cross, blurring and
// fading with depth.
float caustic_net(vec2 p, float t, float depth) {
	vec2 q = p * 0.8;
	float a = texture(noise_caustic, q + t * vec2(0.021, 0.013)).r;
	float b = texture(noise_caustic, q * 1.13 - t * vec2(0.017, 0.024) + 0.37).r;
	float w = 0.16 + depth * 0.12;
	float ea = 1.0 - smoothstep(0.0, w, a);
	float eb = 1.0 - smoothstep(0.0, w, b);
	return ((ea + eb) * 0.3 + ea * eb * 1.2) * exp(-depth * 0.8);
}

// The ceiling lights mirrored in the glazed floor tiles. Schlick Fresnel
// with F0 = 0.04: faint at your feet, strong only far off at grazing
// angles. Each tile is laid a hair out of level, so the image breaks up
// tile by tile, and the glaze's slight roughness smears it into a streak
// running towards the viewer (longer the flatter the view). Wet tiles round
// a pool are smoother and mirror more sharply and brightly.
vec3 tile_glint(vec3 wpos, vec3 cam, vec2 cell, float wet) {
	vec2 tilt = vec2(hash12(cell + 17.0), hash12(cell + 41.0)) - 0.5;
	vec3 n = normalize(vec3(tilt.x * 0.008, 1.0, tilt.y * 0.008));
	vec3 v = normalize(wpos - cam);
	vec3 r = reflect(v, n);
	if (r.y < 0.02) {
		return vec3(0.0);
	}
	float dist = (ceiling_y - wpos.y) / r.y;
	vec2 cf = (wpos.xz + r.xz * dist) / 2.4;
	vec2 cl = floor(cf);
	int gx = int(cl.x);
	int gz = int(cl.y);
	if (((gx + gz) & 1) != 0 || world_rnd(gx, gz, 31u) < 0.03) {
		return vec3(0.0);
	}
	// How far (m) the reflected point misses the 0.62 m panel, split into
	// along and across the view direction.
	vec2 fr = (cf - cl - 0.5) * 2.4;
	vec2 o = max(abs(fr) - 0.31, 0.0) * sign(fr);
	vec2 vd = normalize(v.xz + vec2(1e-4, 0.0));
	float cosv = clamp(-v.y, 0.0, 1.0);
	float rough = mix(0.05, 0.015, wet);
	float along = dot(o, vd) * max(cosv, 0.35);
	float across = dot(o, vec2(-vd.y, vd.x));
	float mask = 1.0 - smoothstep(0.0, 0.01 + dist * rough, length(vec2(along, across)));
	float fres = 0.04 + 0.96 * pow(1.0 - cosv, 5.0);
	return vec3(0.9, 0.97, 1.0) * 3.0 * mask * min(fres, 0.5) * mix(0.5, 1.4, wet) / (1.0 + dist * 0.15);
}

// 1 on a tile, 0 down in the grout, with a rounded bevel.
float tile_height(vec2 uv, float tile) {
	vec2 f = fract(uv / tile);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * tile;
	return smoothstep(0.0015, 0.009, edge);
}

void fragment() {
	vec3 v_light = lightmap_light(v_vlight, v_lm);
	vec2 uv = ps1_uv(UV);
	const float TILE = 0.15;
	mat3 tbn = uv_frame(NORMAL, VERTEX, uv);
	vec3 pnorm = NORMAL;
	vec3 cam = CAMERA_POSITION_WORLD;
	float depth = water_y - v_wpos.y;
	bool under = depth > 0.0 && cam.y > water_y && ps1_grid.x <= 0.0;
	vec3 transmit = vec3(1.0);   // what the water lets through
	vec2 sslope = vec2(0.0);
	if (under) {
		// Refraction: follow the eye's ray into the water, bend it at the
		// rippling surface (n = 1.33) and look up the tile pattern where the
		// bent ray meets this face's plane instead of here. The bottom looks
		// shallower than it is, and the grout lines wobble with the surface.
		vec3 dv = v_wpos - cam;
		vec3 sp = cam + dv * ((cam.y - water_y) / max(cam.y - v_wpos.y, 0.001));
		sslope = water_slope(sp.xz, world_time, waves(sp.xz, world_time).yz);
		vec3 r = refract(normalize(dv), normalize(vec3(-sslope.x, 1.0, -sslope.y)), 0.75);
		vec3 fn = normalize(v_wnormal);
		vec3 hit = sp + r * (dot(v_wpos - sp, fn) / min(dot(r, fn), -0.05));
		vec3 off = hit - v_wpos;
		off *= min(1.0, 1.5 / max(length(off), 0.001));
		vec3 off_v = (VIEW_MATRIX * vec4(off, 0.0)).xyz;
		uv += vec2(dot(off_v, tbn[0]), dot(off_v, tbn[1]));
		// Beer-Lambert along the light's way down (about the depth) and back
		// up to the eye. The bent ray is short even at grazing angles; taking
		// half the straight one too stands in for the haze a real pool's
		// fine particles add over distance, so far water turns teal.
		float path = mix(length(hit - sp), min(length(dv) - length(sp - cam), 12.0), 0.5) + depth;
		transmit = exp(-water_absorb * path);
	}
	if (photoreal > 0.5) {
		// Parallax: each tile stands proud of a sunken grout line, with a
		// rounded edge that catches the light.
		vec3 vt = normalize(vec3(dot(VIEW, tbn[0]), dot(VIEW, tbn[1]), dot(VIEW, NORMAL)));
		vec2 stp = -vt.xy / max(vt.z, 0.25) * 0.007 / 8.0;
		float layer = 0.0;
		for (int i = 0; i < 8; i++) {
			if (layer >= 1.0 - tile_height(uv, TILE)) {
				break;
			}
			uv += stp;
			layer += 0.125;
		}
		float e = 0.002;
		float hx = tile_height(uv + vec2(e, 0.0), TILE) - tile_height(uv - vec2(e, 0.0), TILE);
		float hy = tile_height(uv + vec2(0.0, e), TILE) - tile_height(uv - vec2(0.0, e), TILE);
		pnorm = normalize(tbn * vec3(-hx * 0.7, -hy * 0.7, 1.0));
	}
	vec2 g = uv / TILE;
	vec2 cell = floor(g);
	vec2 f = fract(g);
	float edge = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y)) * TILE;
	float h = hash12(cell);
	vec3 tile = tile_color * (0.95 + 0.07 * h);
	if (h > 0.97) {
		tile *= vec3(0.86, 0.95, 1.0);
	}
	// Dark green tiled band along the waterline on walls and columns.
	if (abs(v_wnormal.y) < 0.5 && v_wpos.y < 0.33) {
		tile = vec3(0.15, 0.40, 0.31) * (0.85 + 0.25 * h);
	}
	float grime = texture(noise_blot, uv * 0.2).r;
	float aa = clamp((fwidth(g.x) + fwidth(g.y)) * 2.0, 0.0, 1.0);
	float grout = mix(smoothstep(0.0045, 0.0025, edge), 0.07, smoothstep(0.15, 0.6, aa));
	vec3 gc = grout_color * mix(1.0, 0.75, smoothstep(0.5, 0.75, grime));
	vec3 col = mix(tile, gc, grout);
	col *= 0.95 + 0.08 * texture(noise_fine, uv * 3.0).r;
	float bevel = smoothstep(0.004, 0.02, edge);
	vec3 emission_extra = vec3(0.0);
	if (under) {
		float lum = dot(v_light, vec3(0.3, 0.59, 0.11));
		// Caustics move with the surface above: offset by its slope.
		float cn = caustic_net(v_wpos.xz + v_wpos.y * 0.3 + sslope * depth * 2.0, world_time, depth);
		col *= transmit;
		emission_extra += col * v_light * (0.15 + cn * 0.7);
		emission_extra += water_scatter * (1.0 - transmit.g) * max(lum, 0.15) * 1.4;
	} else if (depth > 0.0) {
		float d = clamp(depth / 0.8, 0.0, 1.0);
		col *= mix(vec3(0.82, 0.97, 1.0), vec3(0.62, 0.9, 0.95), d);
		emission_extra += caustics(v_wpos.xz + v_wpos.y * 0.3, world_time) * v_light * vec3(0.8, 0.95, 1.0) * 0.6;
		emission_extra += col * v_light * 0.25;
	} else if (abs(v_wnormal.y) < 0.5 && v_wpos.y < 0.02 && ps1_grid.x <= 0.0) {
		// Pool wall just above the water: the wet meniscus line that follows
		// the waves, darker wet tiles above it, and a faint shimmer of
		// light bounced up off the ripples.
		float hw = water_y + waves(v_wpos.xz, world_time).x + ripple_height(v_wpos.xz);
		float above = v_wpos.y - hw;
		col *= mix(0.72, 1.0, smoothstep(0.0, 0.05, above));
		emission_extra += col * v_light * 0.35 * (1.0 - smoothstep(0.0, 0.008, above));
		float sh = caustic_net(v_wpos.xz * 0.7 + vec2(v_wpos.y * 1.5, 0.0), world_time * 1.6, 0.25);
		emission_extra += v_light * vec3(0.8, 0.95, 1.0) * sh * 0.18 * (1.0 - smoothstep(0.0, 0.18, above));
	} else if (v_wnormal.y > 0.5 && ps1_grid.x > 0.0) {
		// PS1 style: polished floor tiles mirror the lights above.
		float fres = 0.04 + 0.5 * pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
		emission_extra += ceiling_reflection(v_wpos, CAMERA_POSITION_WORLD, vec3(0.0, 1.0, 0.0), ceiling_y, 0, world_time) * fres * (1.0 - grout);
	} else if (v_wnormal.y > 0.5 && v_wpos.y < 1.0) {
		// Wet patches (puddles drying out away from the rim): grout darkens.
		float wet = clamp((v_wet - 0.35 + (grime - 0.5) * 0.9) * 2.5, 0.0, 1.0);
		col = mix(col, col * mix(1.0, 0.7, grout), wet);
		// (Realistic: a little stronger, as the photographed tiles are.)
		emission_extra += tile_glint(v_wpos, cam, cell, wet) * (1.0 - grout) * (1.0 + 0.3 * realistic);
	}
	float bump = 1.0;
	if (photoreal > 0.5) {
		NORMAL = pnorm;
		bump = baked_bump(v_lm, pnorm, tbn[2], VIEW_MATRIX);
	}
	ALBEDO = col * mix(0.85, 1.0, bevel);
	ROUGHNESS = mix(0.07, 0.7, grout);
	SPECULAR = 0.6;
	EMISSION = col * mix(0.85, 1.0, bevel) * v_light * bump + col * flashlight(v_wpos, normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz), CAMERA_POSITION_WORLD, 0.8) + emission_extra + dither(FRAGCOORD.xy);
}
