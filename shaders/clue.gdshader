// Door trail clues (DoorTrail): chalk arrows on walls and litter on the
// floor. Self-lit like the Backrooms (instance colour = light where it is),
// plus the flashlight. Alpha-tested, so no sorting.
shader_type spatial;
render_mode unshaded, cull_disabled;
#include "res://shaders/common.gdshaderinc"
#include "res://shaders/ps1.gdshaderinc"

uniform sampler2D tex : source_color, filter_linear_mipmap;
uniform float tiles = 1.0;

varying float v_tile;
varying vec3 v_light;
varying vec3 v_wpos;
varying vec3 v_wn;

void vertex() {
	v_tile = INSTANCE_CUSTOM.r;
	v_light = COLOR.rgb;
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wn = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	POSITION = ps1_snap(PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0));
}

void fragment() {
	vec4 c = texture(tex, vec2((UV.x + v_tile) / tiles, UV.y));
	vec3 n = v_wn * (FRONT_FACING ? 1.0 : -1.0);
	ALBEDO = c.rgb * (v_light + flashlight(v_wpos, n, CAMERA_POSITION_WORLD, 0.2)) + dither(FRAGCOORD.xy);
	ALPHA = c.a;
	ALPHA_SCISSOR_THRESHOLD = 0.35;
}
