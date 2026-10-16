// Dead Mall glass (shopfronts, skylights, the escalator sides): faintly
// tinted, more reflective at grazing angles, catching the baked light.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"
// (`lightmap` comes from common.gdshaderinc)

uniform float lm_scale = 4.0;
uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.6);

varying vec3 v_wpos;
varying vec3 v_wn;

void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_wpos);
	float fres = pow(1.0 - abs(dot(normalize(v_wn), v)), 3.0);
	vec3 lm = texture(lightmap, UV).rgb;
	vec3 light = lm * lm * lm_scale;
	// Dust and smears.
	float smear = hash12(floor(v_wpos.xy * 9.0 + v_wpos.zz * 9.0)) * 0.08;
	ALBEDO = tint * (0.12 + light * 0.18) + vec3(0.6, 0.65, 0.7) * fres * 0.35 + smear * light
			+ tint * flashlight(v_wpos, normalize(v_wn), CAMERA_POSITION_WORLD, 0.95) * 0.4;
	ALPHA = clamp(0.14 + fres * 0.5 + smear, 0.0, 0.85);
}
