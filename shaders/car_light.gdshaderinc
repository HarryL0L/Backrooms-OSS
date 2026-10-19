// How a parked car takes the car park's light, to sit in the baked world:
// soft light from the ceiling and its bounce off the floor, a key from the
// side the nearest tubes are on (light_dir, from WorldGen.light_dir_near,
// longer = more one-sided), and occlusion low down and underneath, where
// the floor and the body hide each other.
instance uniform vec3 light_dir = vec3(0.0, 0.3, 0.0);

// h: height above the floor (metres).
float car_shade(vec3 wn, float h) {
	float dl = length(light_dir);
	vec3 l = dl > 0.001 ? light_dir / dl : vec3(0.0, 1.0, 0.0);
	float up = clamp(wn.y * 0.5 + 0.5, 0.0, 1.0);
	// Ceiling above, the grey floor's bounce below.
	float sky = 0.22 + 0.78 * pow(up, 1.5);
	float key = clamp(dot(wn, l) * 0.6 + 0.4, 0.0, 1.0);
	float s = mix(sky, sky * 0.45 + key * 0.85, clamp(dl, 0.0, 1.0) * 0.75);
	// Ambient occlusion: the sills, bumpers and wheels near the floor.
	s *= mix(0.4, 1.0, smoothstep(0.02, 0.7, h));
	return s;
}
