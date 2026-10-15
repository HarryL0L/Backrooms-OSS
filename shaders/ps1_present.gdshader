// Shows the low-resolution PS1-style render: 15-bit colour (5 bits per
// channel) with the console's 4x4 ordered dither, at source-pixel scale.
shader_type canvas_item;

uniform vec2 src_size = vec2(426.0, 240.0);

const float BAYER[16] = float[](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0,
		3.0, 11.0, 1.0, 9.0, 15.0, 7.0, 13.0, 5.0);

void fragment() {
	vec3 c = texture(TEXTURE, UV).rgb;
	ivec2 p = ivec2(floor(UV * src_size));
	float d = (BAYER[(p.x & 3) + (p.y & 3) * 4] / 16.0 - 0.5);
	c = clamp(floor(c * 31.0 + 0.5 + d) / 31.0, 0.0, 1.0);
	COLOR = vec4(c, 1.0);
}
