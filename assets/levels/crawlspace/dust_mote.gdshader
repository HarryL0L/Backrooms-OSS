// Dust motes hanging in the duct: specks you only see where the torch beam
// catches them (forward scatter makes the ones nearer the beam's axis and
// looking into the light brighter). Billboarded particles, additive.
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;

uniform vec3 torch_pos = vec3(0.0);
uniform vec3 torch_dir = vec3(0.0, 0.0, -1.0);
uniform float torch_on = 1.0;
uniform float cos_outer = 0.88;     // 28 deg cone
uniform float cos_inner = 0.97;
uniform float strength = 2.2;

varying vec3 v_wpos;

void vertex() {
	// Face the camera (particle billboard), keeping the particle's scale.
	mat4 mv = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	mv = mv * mat4(vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0), vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
			vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0), vec4(0.0, 0.0, 0.0, 1.0));
	MODELVIEW_MATRIX = mv;
	v_wpos = (INV_VIEW_MATRIX * mv * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 to_p = v_wpos - torch_pos;
	float d = length(to_p);
	float c = dot(to_p / max(d, 0.001), normalize(torch_dir));
	float cone = smoothstep(cos_outer, cos_inner, c);
	float near = smoothstep(0.12, 0.35, d) / (1.0 + d * d * 0.35);
	vec3 view = normalize(v_wpos - CAMERA_POSITION_WORLD);
	float fwd = 0.5 + 0.8 * pow(max(dot(view, normalize(torch_dir)), 0.0), 6.0);
	float r = length(UV - 0.5) * 2.0;
	float spot = clamp(1.0 - r, 0.0, 1.0);
	spot *= spot;
	ALBEDO = vec3(1.0, 0.93, 0.8) * strength * cone * near * fwd * spot * torch_on;
}
