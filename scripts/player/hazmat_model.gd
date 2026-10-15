class_name HazmatModel
extends Node3D
## A player in a yellow hazmat suit (how other players see you). Built from
## code: smooth lofted tubes for the body and limbs with baggy folds at the
## joints, a hood with a big visor over a black respirator, taped gloves and
## boots. Jointed (hips, knees, shoulders, elbows, neck) so it can be posed
## and animated procedurally. About 1.8 m tall; faces +Z.

## Stencilled on the back.
var tag := "07"

var hips: Node3D
var torso: Node3D
var neck: Node3D
var legs: Array[Node3D] = []      # [left hip, right hip]
var knees: Array[Node3D] = []
var arms: Array[Node3D] = []      # [left shoulder, right shoulder]
var elbows: Array[Node3D] = []

static var _mats := {}


func _ready() -> void:
	_build()


# --------------------------------------------------------------- materials ---
static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"suit":
			m.albedo_color = Color(0.86, 0.68, 0.1)
			m.roughness = 0.45
			m.metallic_specular = 0.6
		"suit_dark":                      # folds / seams
			m.albedo_color = Color(0.62, 0.47, 0.06)
			m.roughness = 0.55
		"rubber":
			m.albedo_color = Color(0.05, 0.05, 0.055)
			m.roughness = 0.6
		"tape":
			m.albedo_color = Color(0.42, 0.43, 0.44)
			m.roughness = 0.7
		"visor":
			m.albedo_color = Color(0.55, 0.62, 0.6, 0.28)
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.roughness = 0.03
			m.metallic = 0.3
			m.metallic_specular = 1.0
			m.cull_mode = BaseMaterial3D.CULL_DISABLED
		"mask":
			m.albedo_color = Color(0.09, 0.09, 0.1)
			m.roughness = 0.5
		"filter":
			m.albedo_color = Color(0.32, 0.33, 0.3)
			m.roughness = 0.45
			m.metallic = 0.4
		"lens":
			m.albedo_color = Color(1.0, 0.95, 0.82)
			m.emission_enabled = true
			m.emission = Color(1.0, 0.93, 0.75) * 1.5
		"zip":
			m.albedo_color = Color(0.2, 0.2, 0.2)
			m.metallic = 0.6
			m.roughness = 0.4
	_mats[key] = m
	return m


# ------------------------------------------------------------------ meshes ---
## A smooth tube along `pts` with elliptical cross-sections (rx sideways,
## rz front-back) and optional fabric folds. Ends are closed with caps.
static func loft(pts: Array, rx: Array, rz: Array, segs := 18, folds := [], cap := true,
		arc := Vector2(0.0, TAU)) -> ArrayMesh:
	# A partial arc (arc.y - arc.x < TAU) gives an open strip, e.g. a visor.
	var closed := arc.y - arc.x >= TAU - 0.001
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := []
	var n := pts.size()
	for i in n:
		var p: Vector3 = pts[i]
		var tan: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := Vector3.FORWARD.cross(tan)
		if side.length() < 0.2:
			side = Vector3.RIGHT
		side = side.normalized()
		var fwd := tan.cross(side).normalized()
		var ring := []
		for k in (segs if closed else segs + 1):
			var a := arc.x + (arc.y - arc.x) * k / segs
			var r := 1.0
			for f in folds:                      # [ring index, depth, count]
				if i == 0 or i == n - 1:
					break                        # ends stay round so parts meet cleanly
				var w: float = exp(-pow((i - float(f[0])) / 0.8, 2.0))
				r += f[1] * w * sin(a * f[2] + i * 0.7)
			ring.append(p + side * cos(a) * float(rx[i]) * r - fwd * sin(a) * float(rz[i]) * r)
		rings.append(ring)
	for i in n - 1:
		for k in segs:
			var k2 := (k + 1) % segs if closed else k + 1
			st.add_vertex(rings[i][k]); st.add_vertex(rings[i][k2]); st.add_vertex(rings[i + 1][k])
			st.add_vertex(rings[i][k2]); st.add_vertex(rings[i + 1][k2]); st.add_vertex(rings[i + 1][k])
	if cap and closed:
		for e in [0, n - 1]:
			var c: Vector3 = pts[e]
			for k in segs:
				var k2 := (k + 1) % segs
				if e == 0:
					st.add_vertex(c); st.add_vertex(rings[e][k2]); st.add_vertex(rings[e][k])
				else:
					st.add_vertex(c); st.add_vertex(rings[e][k]); st.add_vertex(rings[e][k2])
	st.generate_normals()
	return st.commit()


static func ellipsoid(r: Vector3, segs := 20, rings := 12) -> ArrayMesh:
	var sm := SphereMesh.new()
	sm.radius = 1.0
	sm.height = 2.0
	sm.radial_segments = segs
	sm.rings = rings
	var arr := sm.get_mesh_arrays()
	var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var nn: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
	for i in v.size():
		v[i] = v[i] * r
		nn[i] = (nn[i] / r).normalized()
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = nn
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


static func cyl(r0: float, r1: float, h: float, segs := 14) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.bottom_radius = r0
	c.top_radius = r1
	c.height = h
	c.radial_segments = segs
	c.rings = 1
	return c


func _part(parent: Node3D, mesh: Mesh, mat: String, pos := Vector3.ZERO, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(mat)
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _joint(parent: Node3D, pos: Vector3) -> Node3D:
	var j := Node3D.new()
	j.position = pos
	parent.add_child(j)
	return j


# ------------------------------------------------------------------- build ---
func _build() -> void:
	hips = _joint(self, Vector3(0, 0.93, 0))
	# Pelvis / seat of the suit (baggy).
	_part(hips, loft([Vector3(0, -0.17, 0), Vector3(0, -0.1, 0), Vector3(0, -0.02, 0), Vector3(0, 0.07, 0)],
			[0.1, 0.18, 0.2, 0.17], [0.09, 0.13, 0.14, 0.12], 20), "suit")
	torso = _joint(hips, Vector3(0, 0.06, 0))
	# Torso: belly to shoulders, a little slack, folds over the waist.
	var tp := []
	var trx := []
	var trz := []
	for i in 7:
		var u := i / 6.0
		tp.append(Vector3(0, u * 0.42, 0.01 * sin(u * PI)))
		trx.append(lerpf(0.208, 0.23, smoothstep(0.0, 0.8, u)) - 0.07 * smoothstep(0.85, 1.0, u))
		trz.append(lerpf(0.14, 0.135, u) + 0.012 * sin(u * PI) - 0.03 * smoothstep(0.85, 1.0, u))
	_part(torso, loft(tp, trx, trz, 22), "suit")
	# Front zip and storm flap.
	_part(torso, BoxMesh.new(), "zip", Vector3(0.015, 0.2, 0.15), Vector3(0.06, 0, 0)).scale = Vector3(0.012, 0.36, 0.008)
	_part(torso, BoxMesh.new(), "suit_dark", Vector3(-0.005, 0.2, 0.152), Vector3(0.06, 0, 0)).scale = Vector3(0.04, 0.38, 0.006)
	# Chest torch, clipped on the left of the chest.
	var torch := _joint(torso, Vector3(0.11, 0.3, 0.145))
	_part(torch, cyl(0.022, 0.026, 0.07), "rubber", Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	_part(torch, cyl(0.02, 0.02, 0.004), "lens", Vector3(0, 0, 0.037), Vector3(PI * 0.5, 0, 0))
	# Number stencilled on the back.
	var lab := Label3D.new()
	lab.text = tag
	lab.font_size = 96
	lab.pixel_size = 0.0014
	lab.modulate = Color(0.08, 0.08, 0.08)
	lab.outline_size = 0
	lab.position = Vector3(0, 0.27, -0.138)
	lab.rotation = Vector3(0, PI, 0)
	lab.double_sided = false
	torso.add_child(lab)

	neck = _joint(torso, Vector3(0, 0.44, 0))
	_build_hood(neck)

	for s in [-1.0, 1.0]:
		_build_arm(s)
		_build_leg(s)
	# A relaxed stance.
	pose_idle(0.0)


func _build_hood(parent: Node3D) -> void:
	# The hood: from the shoulders up over the head, slack at the neck, roomy
	# around the respirator. At visor height it only goes round the back: the
	# front is the window.
	const WIN := 0.95                      # half-width of the window (radians)
	const FRONT := PI * 0.5                # +Z in loft()'s angle
	var lower_p := [Vector3(0, -0.05, -0.01), Vector3(0, 0.02, 0.0), Vector3(0, 0.075, 0.01)]
	_part(parent, loft(lower_p, [0.17, 0.14, 0.135], [0.13, 0.13, 0.145], 24, [[1, 0.04, 7]], false), "suit")
	var band_p := []
	var band_x := []
	var band_z := []
	for i in 5:
		var u := i / 4.0
		band_p.append(Vector3(0, 0.075 + u * 0.165, 0.012))
		band_x.append(0.137 + 0.006 * sin(u * PI))
		band_z.append(0.147 + 0.006 * sin(u * PI))
	_part(parent, loft(band_p, band_x, band_z, 20, [], false, Vector2(FRONT + WIN, FRONT - WIN + TAU)), "suit")
	var upper_p := [Vector3(0, 0.24, 0.012), Vector3(0, 0.29, 0.005), Vector3(0, 0.33, -0.005), Vector3(0, 0.352, -0.01)]
	_part(parent, loft(upper_p, [0.137, 0.12, 0.085, 0.02], [0.147, 0.13, 0.095, 0.02], 24), "suit")
	# Clear visor over the window, with rubber rims round it.
	var vx := []
	var vz := []
	for i in band_p.size():
		vx.append(float(band_x[i]) + 0.006)
		vz.append(float(band_z[i]) + 0.006)
	_part(parent, loft(band_p, vx, vz, 18, [], false, Vector2(FRONT - WIN - 0.05, FRONT + WIN + 0.05)), "visor")
	for y in [0.075, 0.24]:
		_part(parent, loft([Vector3(0, y - 0.008, 0.012), Vector3(0, y + 0.008, 0.012)], [0.145, 0.145], [0.155, 0.155], 18,
				[], false, Vector2(FRONT - WIN - 0.08, FRONT + WIN + 0.08)), "rubber")
	for sgn in [-1.0, 1.0]:
		var a: float = FRONT + sgn * (WIN + 0.03)
		var rim := _part(parent, cyl(0.009, 0.009, 0.17, 6), "rubber",
				Vector3(cos(a) * 0.143, 0.158, sin(a) * 0.153 + 0.012))
	# Inside: the wearer's head in a black balaclava and a full-face respirator.
	_part(parent, ellipsoid(Vector3(0.095, 0.12, 0.105)), "mask", Vector3(0, 0.16, 0.0))
	_part(parent, ellipsoid(Vector3(0.088, 0.1, 0.075)), "mask", Vector3(0, 0.15, 0.055))
	_part(parent, ellipsoid(Vector3(0.07, 0.03, 0.02)), "visor", Vector3(0, 0.188, 0.118))     # the mask's own eyepiece
	_part(parent, cyl(0.028, 0.034, 0.05), "mask", Vector3(0, 0.105, 0.125), Vector3(PI * 0.5, 0, 0))   # valve snout
	for sgn in [-1.0, 1.0]:
		var piv := _joint(parent, Vector3(sgn * 0.062, 0.1, 0.105))
		piv.rotation = Vector3(0.15, sgn * 0.85, 0)
		_part(piv, cyl(0.034, 0.034, 0.04, 16), "filter", Vector3(0, 0, 0.02), Vector3(PI * 0.5, 0, 0))
		_part(piv, cyl(0.026, 0.026, 0.004, 12), "mask", Vector3(0, 0, 0.041), Vector3(PI * 0.5, 0, 0))


func _build_arm(s: float) -> void:
	var sh := _joint(torso, Vector3(s * 0.2, 0.38, 0))
	arms.append(sh)
	# Upper arm with a baggy sleeve.
	_part(sh, ellipsoid(Vector3(0.082, 0.078, 0.08)), "suit", Vector3(0, -0.015, 0))
	_part(sh, loft([Vector3(0, 0.0, 0), Vector3(0, -0.08, 0), Vector3(0, -0.15, 0), Vector3(0, -0.22, 0), Vector3(0, -0.29, 0)],
			[0.07, 0.074, 0.07, 0.066, 0.058], [0.07, 0.072, 0.068, 0.064, 0.056], 16), "suit")
	var el := _joint(sh, Vector3(0, -0.29, 0))
	elbows.append(el)
	_part(el, ellipsoid(Vector3(0.07, 0.07, 0.07)), "suit")
	_part(el, loft([Vector3(0, 0.0, 0), Vector3(0, -0.06, 0), Vector3(0, -0.13, 0), Vector3(0, -0.2, 0), Vector3(0, -0.25, 0)],
			[0.057, 0.06, 0.056, 0.052, 0.049], [0.055, 0.058, 0.054, 0.05, 0.047], 16), "suit")
	# Taped cuff and a thick rubber glove.
	_part(el, cyl(0.06, 0.06, 0.04), "tape", Vector3(0, -0.24, 0))
	var hand := _joint(el, Vector3(0, -0.3, 0))
	_part(hand, loft([Vector3(0, 0.05, 0), Vector3(0, 0.0, 0.005), Vector3(0, -0.05, 0.01), Vector3(0, -0.09, 0.01)],
			[0.048, 0.042, 0.045, 0.03], [0.045, 0.03, 0.025, 0.02], 14), "rubber")
	_part(hand, loft([Vector3(-s * 0.035, 0.0, 0.025), Vector3(-s * 0.05, -0.04, 0.035)], [0.014, 0.012], [0.014, 0.012], 8), "rubber")


func _build_leg(s: float) -> void:
	var hp := _joint(hips, Vector3(s * 0.1, -0.06, 0))
	legs.append(hp)
	_part(hp, ellipsoid(Vector3(0.1, 0.1, 0.1)), "suit", Vector3(0, 0.0, 0))
	_part(hp, loft([Vector3(0, 0.02, 0), Vector3(0, -0.1, 0), Vector3(0, -0.22, 0.005), Vector3(0, -0.33, 0.003), Vector3(0, -0.42, 0)],
			[0.09, 0.098, 0.09, 0.082, 0.072], [0.09, 0.095, 0.087, 0.079, 0.071], 16), "suit")
	var kn := _joint(hp, Vector3(0, -0.42, 0))
	knees.append(kn)
	_part(kn, ellipsoid(Vector3(0.085, 0.085, 0.087)), "suit")
	_part(kn, loft([Vector3(0, 0.0, 0), Vector3(0, -0.08, 0), Vector3(0, -0.17, 0), Vector3(0, -0.27, 0), Vector3(0, -0.35, 0)],
			[0.07, 0.074, 0.07, 0.069, 0.07], [0.07, 0.074, 0.07, 0.069, 0.07], 16), "suit")
	# Taped ankle, rubber boot.
	_part(kn, cyl(0.079, 0.079, 0.045), "tape", Vector3(0, -0.34, 0))
	_part(kn, loft([Vector3(0, -0.33, -0.01), Vector3(0, -0.42, 0.0), Vector3(0, -0.47, 0.03)],
			[0.068, 0.062, 0.06], [0.07, 0.07, 0.075], 16), "rubber")
	_part(kn, loft([Vector3(0, -0.495, -0.07), Vector3(0, -0.495, 0.0), Vector3(0, -0.49, 0.11), Vector3(0, -0.48, 0.15)],
			[0.06, 0.064, 0.058, 0.04], [0.025, 0.03, 0.03, 0.022], 14), "rubber")


# ------------------------------------------------------------------- poses ---
## Standing, breathing.
func pose_idle(t: float) -> void:
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		arms[i].rotation = Vector3(0.05, 0, s * 0.13)
		elbows[i].rotation = Vector3(-0.18, 0, 0)
		legs[i].rotation = Vector3(0, 0, s * 0.03)
		knees[i].rotation = Vector3(0.04, 0, 0)
	torso.rotation.x = 0.02 * sin(t * 1.4)
	neck.rotation.x = 0.04


## Walking/running cycle: phase in radians (one stride per TAU), amount 0..1.
func pose_walk(phase: float, amount: float, run: float) -> void:
	var swing := lerpf(0.45, 0.8, run) * amount
	for i in 2:
		var s := -1.0 if i == 0 else 1.0
		var ph := phase + (0.0 if i == 0 else PI)
		legs[i].rotation = Vector3(-sin(ph) * swing, 0, s * 0.03)
		knees[i].rotation = Vector3(maxf(0.0, sin(ph + 1.3)) * lerpf(0.7, 1.4, run) * amount + 0.05, 0, 0)
		arms[i].rotation = Vector3(sin(ph) * swing * 0.8, 0, s * 0.13)
		elbows[i].rotation = Vector3(-lerpf(0.25, 1.2, run) * amount - 0.15, 0, 0)
	hips.position.y = 0.93 - absf(cos(phase)) * 0.03 * amount
	torso.rotation.x = lerpf(0.04, 0.22, run) * amount
