shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
#include "res://shaders/common.gdshaderinc"

uniform sampler2D noise_fine : hint_default_white, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D noise_blot : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform sampler2D noise_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 base_color : source_color = vec3(0.84, 0.74, 0.42);
uniform vec3 stripe_color : source_color = vec3(0.76, 0.66, 0.36);

varying vec3 v_light;

void vertex() {
	v_light = baked_light(CUSTOM0, UV2.x, world_time);
}

void fragment() {
	vec2 uv = UV;
	float y = -uv.y;
	// Paper strips 0.53 m wide with visible seams.
	float strip = fract(uv.x / 0.53);
	float seam = smoothstep(0.0, 0.004, strip) * smoothstep(1.0, 0.996, strip);
	// Classic vertical stripe pattern with a faint chevron motif.
	float aa = clamp(fwidth(uv.x * 7.5) * 2.0, 0.0, 1.0);
	float band = smoothstep(0.42, 0.5, fract(uv.x * 7.5)) * smoothstep(1.0, 0.92, fract(uv.x * 7.5));
	vec2 m = fract(vec2(uv.x * 15.0, y * 9.0)) - 0.5;
	float motif = smoothstep(0.22, 0.16, abs(m.x) + abs(m.y) * 0.7) * (1.0 - band);
	band = mix(band, 0.45, smoothstep(0.2, 0.8, aa));
	motif *= 1.0 - smoothstep(0.1, 0.5, aa);
	vec3 col = mix(base_color, stripe_color, band * 0.65);
	col = mix(col, col * 0.9, motif * 0.35);
	float n = texture(noise_fine, uv * 1.7).r;
	col *= 0.9 + 0.2 * n;
	// Water damage blotches, worse near the floor.
	float blot = texture(noise_blot, uv * vec2(0.12, 0.09)).r;
	float low = smoothstep(1.3, 0.0, y);
	float stain = smoothstep(0.56, 0.74, blot) * (low * 0.85 + 0.2);
	col = mix(col, col * vec3(0.62, 0.52, 0.32), stain * 0.75);
	float tide = smoothstep(0.025, 0.0, abs(blot - 0.58)) * low;
	col = mix(col, col * vec3(0.52, 0.42, 0.24), tide * 0.55);
	// Long vertical drip streaks.
	float streak = texture(noise_fine, vec2(uv.x * 2.3, y * 0.06)).r;
	col *= 1.0 - smoothstep(0.62, 0.8, streak) * 0.12;
	col *= mix(0.72, 1.0, seam);
	col *= mix(0.8, 1.0, smoothstep(0.0, 0.18, y));
	ALBEDO = col;
	ROUGHNESS = 0.82;
	SPECULAR = 0.3;
	NORMAL_MAP = texture(noise_normal, uv * 1.3).rgb;
	NORMAL_MAP_DEPTH = 0.35;
	EMISSION = col * v_light + dither(FRAGCOORD.xy);
}
