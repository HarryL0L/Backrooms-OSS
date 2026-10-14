// Camera lens imperfections: subtle barrel distortion and chromatic aberration
// towards the edges of the frame, like footage from a cheap camera.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float aberration = 0.0035;
uniform float distortion = 0.035;

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 c = uv - 0.5;
	float r2 = dot(c, c);
	vec2 duv = 0.5 + c * (1.0 - distortion * r2 * 2.0);
	vec2 dir = c * r2 * 4.0 * aberration / max(length(c), 0.001);
	float rch = textureLod(screen_tex, duv + dir, 0.0).r;
	float gch = textureLod(screen_tex, duv, 0.0).g;
	float bch = textureLod(screen_tex, duv - dir, 0.0).b;
	COLOR = vec4(rch, gch, bch, 1.0);
}
