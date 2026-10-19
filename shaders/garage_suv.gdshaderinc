// Shared by garage_suv (opaque) and garage_suv_glass: how the parked SUV is
// lit. Like everything in the Backrooms it is self-lit: the light where it
// stands (instance uniform), shading by which way a surface faces, and for
// paint, chrome and glass a reflection of the car park's own tube lights
// on the ceiling above. Cabin light and lamps are switched per car.

instance uniform float light = 0.5;
instance uniform float lamps = 0.0;      // head and tail lights
instance uniform float cabin = 0.0;      // the dome light
instance uniform vec4 paint = vec4(0.0); // rgb, a = 1 to repaint the body
// For a door: where its hinge sits in the car (the mesh is hinge-relative).
instance uniform vec3 part_offset = vec3(0.0);

const vec3 CABIN_LAMP = vec3(-0.25, 1.52, 0.0);
const float GARAGE_CEIL = 2.6;

varying vec3 v_wpos;
varying vec3 v_car;    // position in the car (closed doors), metres

// Inside the cabin: under the roof, between the doors.
float in_cabin(vec3 c) {
	return step(abs(c.z), 0.74) * step(0.5, c.y) * step(c.y, 1.66) * step(-1.2, c.x) * step(c.x, 1.45);
}

// The tube lights above, seen reflected in a glossy surface.
vec3 garage_env(vec3 wpos, vec3 r) {
	if (r.y < 0.0) {
		// The dark floor, a little lighter towards the horizon.
		return vec3(0.03, 0.03, 0.028) * light * (1.0 + 4.0 * (1.0 + r.y));
	}
	float dist = max(GARAGE_CEIL - wpos.y, 0.05) / max(r.y, 0.03);
	vec2 hp = wpos.xz + r.xz * dist;
	vec2 cf = hp / 2.4;
	vec2 cl = floor(cf);
	vec2 fr = (cf - cl - 0.5) * 2.4;
	int gx = int(cl.x);
	int gz = int(cl.y);
	bool lane = ((gz % 4 + 4) % 4) == 2 && ((gx % 2 + 2) % 2) == 0;
	bool bay = ((gz % 4 + 4) % 4) == 0 && ((gx % 3 + 3) % 3) == 1;
	vec3 ceil_col = vec3(0.16, 0.16, 0.15) * light;
	if (!(lane || bay)) {
		return ceil_col;
	}
	vec2 d = abs(fr) - vec2(0.62, 0.07);
	float blur = 0.015 + dist * 0.02;
	float tube = 1.0 - smoothstep(-blur, blur, max(d.x, d.y));
	return ceil_col + vec3(0.85, 0.93, 1.0) * 5.0 * tube / (1.0 + dist * 0.2);
}

float fresnel(vec3 n, vec3 v) {
	return 0.04 + 0.96 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
}

// The dome light, on what it can see inside the cabin.
vec3 cabin_light(vec3 c, vec3 a) {
	float d = length(c - CABIN_LAMP);
	return a * vec3(1.0, 0.86, 0.62) * cabin * 2.6 / (1.0 + d * d * 3.0) * in_cabin(c);
}
