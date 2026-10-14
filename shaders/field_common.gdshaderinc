// Shared by the Field level's shaders. field_height() must match
// FieldLevel.height() in field_level.gd (collision uses the GDScript copy).

// Rolling hills: rises of ~6-8 m every 150-400 m (slopes stay under ~13 deg).
// `detail` scales the shorter waves; the ground shader fades them out far
// from the camera, where the mesh is too coarse to show them. Collision is
// always near the player, where detail = 1, so the two always agree there.
float field_height_d(vec2 p, float detail) {
	float h = 3.2 * sin(p.x * 0.021 + 0.3) * sin(p.y * 0.017 + 1.1)
			+ detail * (2.2 * sin(p.x * 0.033 + p.y * 0.026 + 2.0)
			+ 1.4 * sin(-p.x * 0.019 + p.y * 0.041 + 0.7)
			+ 0.3 * sin(p.x * 0.09 - p.y * 0.07 + 1.9));
	// Far away the land settles into a flat horizon.
	return h * (1.0 - smoothstep(1500.0, 3000.0, length(p)));
}

float field_height(vec2 p) {
	return field_height_d(p, 1.0);
}

// Panorama mapping shared by the cloud bake and the sky.
const float CLOUD_EL_MIN = -0.03;   // radians of elevation at the bottom row
const float CLOUD_EL_MAX = 0.95;    // ... at the top row
