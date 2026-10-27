// Human eye camera (Settings > Human eye): the view is rendered wide (115
// degrees across), which a flat projection stretches badly at the edges;
// this pulls the edges back in and leaves the middle natural, the way your
// own eyes see a room: wide around you, nothing smeared, spaces feel big.
shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform float strength = 0.24;     // 0 flat .. how much the middle is enlarged
uniform float aspect = 1.7778;

void fragment() {
	vec2 c = SCREEN_UV - 0.5;
	// Radius in screen proportions, 1 at the corners.
	float r = length(c * vec2(aspect, 1.0)) / length(vec2(aspect, 1.0) * 0.5);
	vec2 src = 0.5 + c * ((1.0 - strength) + strength * r * r);
	COLOR = vec4(textureLod(screen_tex, src, 0.0).rgb, 1.0);
}
