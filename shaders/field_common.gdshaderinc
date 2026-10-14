// Shared by the Field level's shaders. field_height() must match
// FieldLevel.height() in field_level.gd (collision uses the GDScript copy).

float field_height(vec2 p) {
	float h = 1.8 * sin(p.x * 0.0105 + 0.3) * sin(p.y * 0.0087 + 1.1)
			+ 0.8 * sin(p.x * 0.021 + p.y * 0.016 + 2.0)
			+ 0.25 * sin(p.x * 0.047 - p.y * 0.039 + 0.7);
	// Far away the land settles into a flat horizon.
	return h * (1.0 - smoothstep(1500.0, 3000.0, length(p)));
}

// Panorama mapping shared by the cloud bake and the sky.
const float CLOUD_EL_MIN = -0.03;   // radians of elevation at the bottom row
const float CLOUD_EL_MAX = 0.95;    // ... at the top row
