// The pool water's surface shape, shared by the water and by the pool tiles
// seen through it (refraction, caustics, the meniscus line), so both follow
// the same waves and ripples. Include after common.gdshaderinc.

uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap, repeat_enable;
// Interactive ripples (WaterRipples): r = height (m) on a grid that follows the player.
uniform sampler2D ripple_tex : hint_default_black, filter_linear, repeat_disable;
uniform vec3 ripple_rect = vec3(0.0, 0.0, 16.0);   // grid min corner x, z and size (m)
uniform float ripple_on = 0.0;

// Gentle background motion: a few travelling waves summed (GPU Gems ch. 1
// style). Indoor pool, so centimetres, not ocean swell.
// xy = direction, z = wavelength (m), w = amplitude (m).
const vec4 WAVES[4] = vec4[](
	vec4(0.8, 0.6, 2.6, 0.010),
	vec4(-0.5, 0.86, 1.7, 0.007),
	vec4(0.2, -0.98, 1.1, 0.004),
	vec4(-0.9, -0.3, 0.7, 0.0025));

// x = height (m), yz = slope (dh/dx, dh/dz).
vec3 waves(vec2 p, float t) {
	float h = 0.0;
	vec2 g = vec2(0.0);
	for (int i = 0; i < 4; i++) {
		vec2 d = normalize(WAVES[i].xy);
		float k = 6.2831853 / WAVES[i].z;
		float w = sqrt(9.8 * k) * 0.35;   // deep-water dispersion, slowed for a calm pool
		float ph = k * dot(d, p) - w * t + float(i) * 1.7;
		h += WAVES[i].w * sin(ph);
		g += WAVES[i].w * k * cos(ph) * d;
	}
	return vec3(h, g);
}

// Position on the ripple grid, or negative outside it.
vec2 ripple_uv(vec2 p) {
	if (ripple_on < 0.5) {
		return vec2(-1.0);
	}
	vec2 ruv = (p - ripple_rect.xy) / ripple_rect.z;
	return (ruv.x > 0.0 && ruv.y > 0.0 && ruv.x < 1.0 && ruv.y < 1.0) ? ruv : vec2(-1.0);
}

float ripple_height(vec2 p) {
	vec2 ruv = ripple_uv(p);
	return ruv.x < 0.0 ? 0.0 : clamp(textureLod(ripple_tex, ruv, 0.0).r, -0.25, 0.25);
}

vec2 ripple_slope(vec2 p) {
	vec2 ruv = ripple_uv(p);
	if (ruv.x < 0.0) {
		return vec2(0.0);
	}
	vec2 px = 1.0 / vec2(textureSize(ripple_tex, 0));
	float texel = ripple_rect.z * px.x;
	vec2 rs;
	rs.x = textureLod(ripple_tex, ruv + vec2(px.x, 0.0), 0.0).r - textureLod(ripple_tex, ruv - vec2(px.x, 0.0), 0.0).r;
	rs.y = textureLod(ripple_tex, ruv + vec2(0.0, px.y), 0.0).r - textureLod(ripple_tex, ruv - vec2(0.0, px.y), 0.0).r;
	return rs / (2.0 * texel);
}

// Slope of the surface as the eye sees it: the waves (waves().yz, passed in
// so the water can interpolate them from its vertices), the ripples and a
// slow drift from the noise.
vec2 water_slope(vec2 p, float t, vec2 wave_slope) {
	vec2 n = texture(noise_normal, p * 0.21 + t * vec2(0.012, 0.008)).rg
			+ texture(noise_normal, p * 0.17 - t * vec2(0.009, 0.013)).rg - 1.0;
	return wave_slope * 0.8 + ripple_slope(p) - n * 0.02;
}

// The small capillary wrinkles on top, which break the reflected lights'
// edges up (surface only, too fine to show in the refraction).
vec2 water_wrinkles(vec2 p, float t) {
	return (texture(noise_normal, p * 1.3 + t * vec2(-0.05, 0.035)).rg - 0.5) * -0.015;
}

// Fraction of light reflected by water (n = 1.33) at this angle (Schlick).
float water_fresnel(float cos_v) {
	return 0.02 + 0.98 * pow(1.0 - clamp(cos_v, 0.0, 1.0), 5.0);
}
