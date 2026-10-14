// Field sky: deep blue gradient, soft sun, and the pre-baked cumulus panorama.
shader_type sky;
#include "res://shaders/field_common.gdshaderinc"

uniform sampler2D clouds : filter_linear, repeat_enable, hint_default_transparent;
uniform vec3 zenith_color = vec3(0.012, 0.14, 0.62);
uniform vec3 horizon_color = vec3(0.30, 0.52, 0.86);

void sky() {
	vec3 d = EYEDIR;
	float e = clamp(d.y, -1.0, 1.0);
	vec3 col = mix(horizon_color, zenith_color, pow(clamp(e, 0.0, 1.0), 0.5));
	col = mix(col, horizon_color * 0.9, smoothstep(0.0, -0.1, e));
	if (LIGHT0_ENABLED) {
		float s = max(dot(d, LIGHT0_DIRECTION), 0.0);
		col += LIGHT0_COLOR * (smoothstep(0.99985, 0.99995, s) * 40.0 + pow(s, 12.0) * 0.12);
	}
	float el = asin(e);
	if (el > CLOUD_EL_MIN && el < CLOUD_EL_MAX) {
		vec2 uv = vec2(atan(d.x, -d.z) / 6.2831853 + 0.5, (CLOUD_EL_MAX - el) / (CLOUD_EL_MAX - CLOUD_EL_MIN));
		vec4 c = texture(clouds, uv);
		col = col * (1.0 - c.a) + c.rgb;
	}
	COLOR = col;
}
