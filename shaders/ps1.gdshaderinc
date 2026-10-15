// PS1 style (see RetroView). `ps1_grid` is the vertex snap grid in NDC steps
// per unit, zero when PS1 style is off.
global uniform vec2 ps1_grid;

// UV * w and w, interpolated with perspective correction: dividing them in
// the fragment shader gives screen-linear (affine) UVs, like the PS1's
// texture mapper with its characteristic warping.
varying vec3 v_ps1_aff;

// Vertex "wobble": positions snap to a coarse screen grid.
vec4 ps1_snap(vec4 clip) {
	if (ps1_grid.x > 0.0 && clip.w > 0.0) {
		vec2 ndc = clip.xy / clip.w;
		ndc = floor(ndc * ps1_grid + 0.5) / ps1_grid;
		clip.xy = ndc * clip.w;
	}
	return clip;
}

// Affine, low-resolution texture coordinates (UV is in metres: ~40 texels/m).
vec2 ps1_uv(vec2 uv) {
	if (ps1_grid.x <= 0.0 || v_ps1_aff.z <= 0.0) {
		return uv;
	}
	vec2 a = v_ps1_aff.xy / v_ps1_aff.z;
	return (floor(a * 40.0) + 0.5) / 40.0;
}
