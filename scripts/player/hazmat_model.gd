class_name HazmatModel
extends Node3D
## A player in a yellow hazmat suit (how other players see you). Built from
## code on a Skeleton3D: the torso, arms and legs are each one continuous
## skinned surface, weighted across the bones so shoulders, elbows, hips and
## knees bend smoothly. Gauntlet gloves with fingers, rubber boots with toe
## caps, heels and thick soles; a hood with a big visor over a black
## respirator. About 1.8 m tall; faces +Z. pose_idle()/pose_walk() animate it.

## Stencilled on the back.
var tag := "07"

var skeleton: Skeleton3D
var _label: Label3D

enum { HIPS, SPINE, CHEST, NECK, HEAD, UARM_L, FARM_L, HAND_L, UARM_R, FARM_R, HAND_R,
	THIGH_L, SHIN_L, FOOT_L, THIGH_R, SHIN_R, FOOT_R }
const BONES := [
	# name, parent, global rest position
	["hips", -1, Vector3(0, 0.93, 0)], ["spine", HIPS, Vector3(0, 1.05, 0)], ["chest", SPINE, Vector3(0, 1.25, 0)],
	["neck", CHEST, Vector3(0, 1.44, 0)], ["head", NECK, Vector3(0, 1.52, 0)],
	["uarm_l", CHEST, Vector3(-0.2, 1.4, 0)], ["farm_l", UARM_L, Vector3(-0.22, 1.12, 0)], ["hand_l", FARM_L, Vector3(-0.23, 0.87, 0)],
	["uarm_r", CHEST, Vector3(0.2, 1.4, 0)], ["farm_r", UARM_R, Vector3(0.22, 1.12, 0)], ["hand_r", FARM_R, Vector3(0.23, 0.87, 0)],
	["thigh_l", HIPS, Vector3(-0.1, 0.87, 0)], ["shin_l", THIGH_L, Vector3(-0.1, 0.47, 0)], ["foot_l", SHIN_L, Vector3(-0.1, 0.09, 0)],
	["thigh_r", HIPS, Vector3(0.1, 0.87, 0)], ["shin_r", THIGH_R, Vector3(0.1, 0.47, 0)], ["foot_r", SHIN_R, Vector3(0.1, 0.09, 0)],
]

static var _mats := {}


func _ready() -> void:
	_build()


# --------------------------------------------------------------- materials ---
static func _mat(key: String) -> Material:
	if _mats.has(key):
		return _mats[key]
	var m: Material
	# [albedo, roughness, specular, wrinkles] for the opaque parts.
	var spec := {
		"suit": [Color(0.86, 0.68, 0.1), 0.45, 0.55, 1.0],
		"suit_dark": [Color(0.62, 0.47, 0.06), 0.55, 0.4, 0.0],
		"rubber": [Color(0.05, 0.05, 0.055), 0.6, 0.45, 0.0],
		"rubber_fold": [Color(0.05, 0.05, 0.055), 0.6, 0.45, 0.5],
		"sole": [Color(0.025, 0.025, 0.028), 0.85, 0.2, 0.0],
		"tape": [Color(0.42, 0.43, 0.44), 0.7, 0.3, 0.25],
		"mask": [Color(0.09, 0.09, 0.1), 0.5, 0.45, 0.0],
		"filter": [Color(0.32, 0.33, 0.3), 0.45, 0.7, 0.0],
		"zip": [Color(0.2, 0.2, 0.2), 0.4, 0.8, 0.0],
	}
	if spec.has(key):
		var sm := ShaderMaterial.new()
		sm.shader = load("res://shaders/hazmat.gdshader")
		var p: Array = spec[key]
		sm.set_shader_parameter("albedo", p[0])
		sm.set_shader_parameter("roughness", p[1])
		sm.set_shader_parameter("specular_amt", p[2])
		sm.set_shader_parameter("wrinkles", p[3])
		m = sm
	else:
		var st := StandardMaterial3D.new()
		match key:
			"visor":
				st.albedo_color = Color(0.55, 0.62, 0.6, 0.28)
				st.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
				st.roughness = 0.03
				st.metallic = 0.3
				st.metallic_specular = 1.0
				st.cull_mode = BaseMaterial3D.CULL_DISABLED
			"lens":
				st.albedo_color = Color(1.0, 0.95, 0.82)
				st.emission_enabled = true
				st.emission = Color(1.0, 0.93, 0.75) * 1.5
		m = st
	_mats[key] = m
	return m


## Light level where the model stands (Backrooms surfaces are self-lit, so
## the model is given the same light as emission).
func set_env_light(c: Color) -> void:
	for mi in find_children("*", "MeshInstance3D", true, false):
		if (mi as MeshInstance3D).material_override is ShaderMaterial:
			(mi as MeshInstance3D).set_instance_shader_parameter("env_light", c)


func set_tag(t: String) -> void:
	tag = t
	if _label:
		_label.text = t


## Materials to pre-compile during loading.
static func warm_materials() -> Array[Material]:
	var out: Array[Material] = []
	for k in ["suit", "rubber", "visor", "lens"]:
		out.append(_mat(k))
	return out


# ------------------------------------------------------------------ meshes ---
## A smooth tube along `pts` with elliptical cross-sections (rx sideways,
## rz front-back) and optional fabric folds. Ends are closed with caps.
static func loft(pts: Array, rx: Array, rz: Array, segs := 18, folds := [], cap := true,
		arc := Vector2(0.0, TAU), crease := 0.0) -> ArrayMesh:
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
		for k in segs + 1:                       # closed rings repeat the first point (UV seam)
			var a := arc.x + (arc.y - arc.x) * k / segs
			var r := 1.0
			for f in folds:                      # [ring index, depth, count]
				if i == 0 or i == n - 1:
					break                        # ends stay round so parts meet cleanly
				var w: float = exp(-pow((i - float(f[0])) / 0.8, 2.0))
				r += f[1] * w * sin(a * f[2] + i * 0.7)
			ring.append(p + side * cos(a) * float(rx[i]) * r - fwd * sin(a) * float(rz[i]) * r)
		rings.append(ring)
	var vlen := [0.0]
	for i in range(1, n):
		vlen.append(float(vlen[i - 1]) + (pts[i] as Vector3).distance_to(pts[i - 1]))
	var put := func(i: int, k: int) -> void:
		st.set_uv(Vector2(float(k) / segs, vlen[i]))
		st.set_uv2(Vector2(crease, 0.0))
		st.add_vertex(rings[i][k])
	for i in n - 1:
		for k in segs:
			put.call(i, k); put.call(i, k + 1); put.call(i + 1, k)
			put.call(i, k + 1); put.call(i + 1, k + 1); put.call(i + 1, k)
	if cap and closed:
		for e in [0, n - 1]:
			var c: Vector3 = pts[e]
			for k in segs:
				st.set_uv(Vector2(0.5, vlen[e])); st.set_uv2(Vector2(crease, 0.0))
				if e == 0:
					st.add_vertex(c); put.call(e, k + 1); put.call(e, k)
				else:
					st.add_vertex(c); put.call(e, k); put.call(e, k + 1)
	st.index()
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


# ------------------------------------------------------------ skinned body ---
## Like loft() but every ring carries bone weights: [[bone, w], [bone, w]].
static func skinned_loft(pts: Array, rx: Array, rz: Array, weights: Array, segs := 20, creases := []) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := pts.size()
	var rings := []
	for i in n:
		var p: Vector3 = pts[i]
		var tan: Vector3 = ((pts[mini(i + 1, n - 1)] as Vector3) - (pts[maxi(i - 1, 0)] as Vector3)).normalized()
		var side := Vector3.FORWARD.cross(tan)
		if side.length() < 0.2:
			side = Vector3.RIGHT
		side = side.normalized()
		var fwd := tan.cross(side).normalized()
		var ring := []
		for k in segs + 1:
			var a := TAU * k / segs
			ring.append(p + side * cos(a) * float(rx[i]) - fwd * sin(a) * float(rz[i]))
		rings.append(ring)
	var vlen := [0.0]
	for i in range(1, n):
		vlen.append(float(vlen[i - 1]) + (pts[i] as Vector3).distance_to(pts[i - 1]))
	var vb := func(i: int, v: Vector3) -> void:
		var w: Array = weights[i]
		var b := PackedInt32Array([0, 0, 0, 0])
		var wt := PackedFloat32Array([0.0, 0.0, 0.0, 0.0])
		for j in w.size():
			b[j] = w[j][0]
			wt[j] = w[j][1]
		st.set_bones(b)
		st.set_weights(wt)
		st.add_vertex(v)
	var pv := func(i: int, k: int) -> void:
		st.set_uv(Vector2(float(k) / segs, vlen[i]))
		st.set_uv2(Vector2(float(creases[i]) if creases.size() > i else 0.0, 0.0))
		vb.call(i, rings[i][k])
	for i in n - 1:
		for k in segs:
			pv.call(i, k); pv.call(i, k + 1); pv.call(i + 1, k)
			pv.call(i, k + 1); pv.call(i + 1, k + 1); pv.call(i + 1, k)
	for e in [0, n - 1]:
		var c: Vector3 = pts[e]
		for k in segs:
			st.set_uv(Vector2(0.5, vlen[e])); st.set_uv2(Vector2.ZERO)
			if e == 0:
				vb.call(e, c); pv.call(e, k + 1); pv.call(e, k)
			else:
				vb.call(e, c); pv.call(e, k); pv.call(e, k + 1)
	st.index()
	st.generate_normals()
	return st.commit()


func _skin_part(mesh: ArrayMesh, mat: String) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _mat(mat)
	skeleton.add_child(mi)
	mi.skeleton = NodePath("..")


func _attach(bone: int) -> Node3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = BONES[bone][0]
	skeleton.add_child(ba)
	var holder := Node3D.new()                 # children placed in bone-local space
	ba.add_child(holder)
	return holder


# ------------------------------------------------------------------- build ---
func _build() -> void:
	skeleton = Skeleton3D.new()
	add_child(skeleton)
	for b in BONES:
		var i := skeleton.add_bone(b[0])
		var par: int = b[1]
		var gpos: Vector3 = b[2]
		if par >= 0:
			skeleton.set_bone_parent(i, par)
			gpos -= BONES[par][2]
		skeleton.set_bone_rest(i, Transform3D(Basis(), gpos))
	skeleton.reset_bone_poses()

	# Torso, crotch to neck, one surface.
	var tb := [
		[0.74, 0.12, 0.1, [[HIPS, 1.0]]], [0.8, 0.17, 0.12, [[HIPS, 1.0]]], [0.88, 0.195, 0.135, [[HIPS, 1.0]]],
		[0.97, 0.19, 0.135, [[HIPS, 0.7], [SPINE, 0.3]]], [1.06, 0.192, 0.14, [[SPINE, 1.0]]],
		[1.16, 0.208, 0.146, [[SPINE, 0.5], [CHEST, 0.5]]], [1.26, 0.222, 0.15, [[CHEST, 1.0]]],
		[1.35, 0.222, 0.146, [[CHEST, 1.0]]], [1.42, 0.2, 0.13, [[CHEST, 1.0]]],
		[1.47, 0.13, 0.1, [[CHEST, 0.5], [NECK, 0.5]]], [1.52, 0.08, 0.08, [[NECK, 1.0]]]]
	var pts := []; var rx := []; var rz := []; var ws := []
	for r in tb:
		pts.append(Vector3(0, r[0], 0.004 * sin((r[0] - 0.74) * 4.0))); rx.append(r[1]); rz.append(r[2]); ws.append(r[3])
	_skin_part(skinned_loft(pts, rx, rz, ws, 26, [0.6, 0.4, 0.2, 0.7, 0.5, 0.25, 0.1, 0.1, 0.3, 0.5, 0.2]), "suit")

	for side in [-1.0, 1.0]:
		var L: bool = side < 0.0
		var ua: int = UARM_L if L else UARM_R
		var fa: int = FARM_L if L else FARM_R
		var hd: int = HAND_L if L else HAND_R
		var th: int = THIGH_L if L else THIGH_R
		var sh: int = SHIN_L if L else SHIN_R
		var ft: int = FOOT_L if L else FOOT_R
		# Arm: from inside the shoulder to the wrist, sleeve slightly baggy.
		var ab := [
			[0.15, 1.42, 0.07, [[CHEST, 1.0]]], [0.2, 1.38, 0.077, [[CHEST, 0.5], [ua, 0.5]]],
			[0.21, 1.3, 0.074, [[ua, 1.0]]], [0.215, 1.21, 0.069, [[ua, 1.0]]],
			[0.22, 1.145, 0.065, [[ua, 0.7], [fa, 0.3]]], [0.222, 1.1, 0.063, [[ua, 0.3], [fa, 0.7]]],
			[0.225, 1.0, 0.059, [[fa, 1.0]]], [0.228, 0.93, 0.054, [[fa, 1.0]]], [0.23, 0.88, 0.047, [[fa, 0.8], [hd, 0.2]]]]
		pts = []; rx = []; rz = []; ws = []
		for r in ab:
			pts.append(Vector3(side * r[0], r[1], 0.0)); rx.append(r[2]); rz.append(r[2] * 0.97); ws.append(r[3])
		_skin_part(skinned_loft(pts, rx, rz, ws, 18, [0.5, 0.7, 0.35, 0.3, 0.9, 1.0, 0.4, 0.6, 0.85]), "suit")
		# Leg: from inside the pelvis to the ankle.
		var lb := [
			[0.07, 0.93, 0.09, [[HIPS, 1.0]]], [0.1, 0.84, 0.1, [[HIPS, 0.4], [th, 0.6]]], [0.1, 0.74, 0.098, [[th, 1.0]]],
			[0.1, 0.62, 0.09, [[th, 1.0]]], [0.1, 0.52, 0.083, [[th, 0.75], [sh, 0.25]]], [0.1, 0.45, 0.081, [[th, 0.25], [sh, 0.75]]],
			[0.1, 0.34, 0.075, [[sh, 1.0]]], [0.1, 0.25, 0.066, [[sh, 1.0]]], [0.1, 0.15, 0.06, [[sh, 1.0]]]]
		pts = []; rx = []; rz = []; ws = []
		for r in lb:
			pts.append(Vector3(side * r[0], r[1], 0.003)); rx.append(r[2]); rz.append(r[2]); ws.append(r[3])
		_skin_part(skinned_loft(pts, rx, rz, ws, 18, [0.6, 0.8, 0.3, 0.3, 0.9, 1.0, 0.35, 0.7, 1.0]), "suit")
		_build_glove(_attach(hd), side)
		_build_boot(_attach(ft), _attach(sh), side)

	_build_chest_details(_attach(CHEST))
	var head := _attach(NECK)
	head.position = Vector3(0, -0.01, 0)
	_build_hood(head)
	pose_idle(0.0)


func _build_chest_details(c: Node3D) -> void:
	# Bone-local: the chest bone sits at y 1.25.
	_part(c, BoxMesh.new(), "suit_dark", Vector3(-0.006, -0.06, 0.15), Vector3(0.05, 0, 0)).scale = Vector3(0.04, 0.38, 0.006)
	_part(c, BoxMesh.new(), "zip", Vector3(0.014, -0.06, 0.153), Vector3(0.05, 0, 0)).scale = Vector3(0.011, 0.36, 0.006)
	var torch := _joint(c, Vector3(0.11, 0.05, 0.152))
	_part(torch, cyl(0.022, 0.026, 0.07), "rubber", Vector3.ZERO, Vector3(PI * 0.5, 0, 0))
	_part(torch, cyl(0.02, 0.02, 0.004), "lens", Vector3(0, 0, 0.037), Vector3(PI * 0.5, 0, 0))
	_part(torch, BoxMesh.new(), "rubber", Vector3(0, 0, -0.02)).scale = Vector3(0.05, 0.012, 0.012)
	var lab := Label3D.new()
	_label = lab
	lab.text = tag
	lab.font_size = 96
	lab.pixel_size = 0.0014
	lab.modulate = Color(0.08, 0.08, 0.08)
	lab.outline_size = 0
	lab.position = Vector3(0, 0.03, -0.152)
	lab.rotation = Vector3(0, PI, 0)
	lab.double_sided = false
	c.add_child(lab)


## Thick rubber gauntlet glove; bone-local (wrist at the origin, fingers down).
## Palms face the thigh, so the palm is thin in X and wide in Z.
func _build_glove(h: Node3D, side: float) -> void:
	# Gauntlet cuff flaring over the sleeve, with a tape band.
	_part(h, loft([Vector3(0, 0.09, 0), Vector3(0, 0.05, 0), Vector3(0, 0.01, 0)], [0.066, 0.06, 0.05], [0.066, 0.06, 0.05], 16), "rubber")
	_part(h, cyl(0.064, 0.068, 0.03), "tape", Vector3(0, 0.075, 0))
	# Palm.
	_part(h, loft([Vector3(0, 0.015, 0), Vector3(0, -0.02, 0.003), Vector3(0, -0.06, 0.005), Vector3(0, -0.085, 0.004)],
			[0.03, 0.026, 0.024, 0.02], [0.046, 0.05, 0.05, 0.044], 14), "rubber")
	# Four fingers, slightly curled toward the thigh, index in front.
	var inward := -side
	for f in 4:
		var z := 0.034 - f * 0.022
		var ln: float = [0.07, 0.078, 0.074, 0.06][f]
		var base := Vector3(0, -0.08, z)
		var path := [base, base + Vector3(inward * 0.006, -ln * 0.5, 0), base + Vector3(inward * 0.02, -ln * 0.9, 0)]
		_part(h, loft(path, [0.0115, 0.0105, 0.009], [0.0115, 0.0105, 0.009], 8), "rubber")
	# Thumb, from the front of the palm, angled forward and down.
	var tb := Vector3(inward * 0.01, -0.025, 0.036)
	_part(h, loft([tb, tb + Vector3(inward * 0.012, -0.03, 0.008), tb + Vector3(inward * 0.02, -0.058, 0.004)],
			[0.0135, 0.012, 0.0105], [0.0135, 0.012, 0.0105], 8), "rubber")


## Rubber boot; bone-local (ankle at the origin, 0.09 above the ground).
func _build_boot(f: Node3D, shin: Node3D, side: float) -> void:
	# Shaft over the trouser leg, taped at the top. It follows the shin (so
	# the leg stays inside it when the knee bends), placed at the ankle.
	var s := _joint(shin, BONES[FOOT_L][2] - BONES[SHIN_L][2])
	_part(s, loft([Vector3(0, 0.19, 0.0), Vector3(0, 0.1, 0.002), Vector3(0, 0.03, 0.008), Vector3(0, -0.025, 0.02)],
			[0.088, 0.08, 0.071, 0.06], [0.09, 0.082, 0.078, 0.07], 18), "rubber")
	_part(s, cyl(0.091, 0.093, 0.035), "tape", Vector3(0, 0.18, 0))
	# Flexible ankle on the foot that fills the bend between shaft and foot.
	_part(f, ellipsoid(Vector3(0.068, 0.055, 0.074), 16, 10), "rubber", Vector3(0, -0.012, 0.004))
	# Foot: heel to a rounded toe cap (along +Z; rx = width, rz = height).
	var fp := [Vector3(0, -0.035, -0.075), Vector3(0, -0.035, -0.04), Vector3(0, -0.04, 0.03),
		Vector3(0, -0.048, 0.1), Vector3(0, -0.05, 0.15), Vector3(0, -0.052, 0.178)]
	_part(f, loft(fp, [0.05, 0.062, 0.064, 0.06, 0.05, 0.022], [0.045, 0.05, 0.05, 0.04, 0.032, 0.015], 18), "rubber")
	# Thick sole, a touch wider, with a separate heel block.
	var sp := [Vector3(0, -0.078, -0.08), Vector3(0, -0.079, 0.0), Vector3(0, -0.079, 0.1), Vector3(0, -0.078, 0.17), Vector3(0, -0.076, 0.19)]
	_part(f, loft(sp, [0.052, 0.066, 0.068, 0.052, 0.02], [0.012, 0.012, 0.012, 0.012, 0.008], 16), "sole")
	_part(f, BoxMesh.new(), "sole", Vector3(0, -0.07, -0.055)).scale = Vector3(0.1, 0.03, 0.06)


func _build_hood(parent: Node3D) -> void:
	# The hood: from the shoulders up over the head, slack at the neck, roomy
	# around the respirator. At visor height it only goes round the back: the
	# front is the window.
	const WIN := 0.95                      # half-width of the window (radians)
	const FRONT := PI * 0.5                # +Z in loft()'s angle
	var lower_p := [Vector3(0, -0.05, -0.01), Vector3(0, 0.02, 0.0), Vector3(0, 0.075, 0.01)]
	_part(parent, loft(lower_p, [0.17, 0.14, 0.135], [0.13, 0.13, 0.145], 24, [[1, 0.04, 7]], false, Vector2(0.0, TAU), 0.5), "suit")
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


# ------------------------------------------------------------------- poses ---
## 0 standing .. 1 fully crouched; layered on top of idle and walk poses.
var crouch := 0.0
## 0 on the ground .. 1 in the air (legs tucked, arms up for balance).
var air := 0.0
var _off := {}                # bone -> euler offset from crouch/air


func _rot(bone: int, e: Vector3) -> void:
	skeleton.set_bone_pose_rotation(bone, Quaternion.from_euler(e + _off.get(bone, Vector3.ZERO)))


## Crouch is a real squat: thighs forward, knees bent twice as far so the
## shins come back, feet kept flat, hips lowered by exactly what the legs
## give up (so the boots stay on the floor) and the back leaning forward.
## In the air the knees tuck up and the arms lift and spread.
func _overlay() -> Vector3:
	_off.clear()
	var a := 1.05 * crouch
	var tuck := 0.55 * air * (1.0 - crouch * 0.5)
	for L in [true, false]:
		var s := -1.0 if L else 1.0
		_off[THIGH_L if L else THIGH_R] = Vector3(-a - tuck, 0, s * 0.08 * crouch)
		_off[SHIN_L if L else SHIN_R] = Vector3(2.0 * a + tuck * 1.6, 0, 0)
		_off[FOOT_L if L else FOOT_R] = Vector3(-a + tuck * 0.25, 0, 0)
		_off[UARM_L if L else UARM_R] = Vector3(-0.35 * crouch - 0.45 * air, 0, s * 0.3 * air)
		_off[FARM_L if L else FARM_R] = Vector3(-0.45 * crouch - 0.35 * air, 0, 0)
	_off[SPINE] = Vector3(0.4 * crouch, 0, 0)
	_off[CHEST] = Vector3(0.12 * crouch, 0, 0)
	_off[NECK] = Vector3(-0.45 * crouch, 0, 0)
	# Thigh 0.40 + shin 0.38 long: the hips drop by what the bent legs lose.
	var drop := 0.78 * (1.0 - cos(a))
	return BONES[HIPS][2] + Vector3(0, -drop, 0.03 * sin(a))


## Standing, breathing.
func pose_idle(t: float) -> void:
	skeleton.set_bone_pose_position(HIPS, _overlay())
	for L in [true, false]:
		var s := -1.0 if L else 1.0
		_rot(UARM_L if L else UARM_R, Vector3(0.05, 0, s * 0.1))
		_rot(FARM_L if L else FARM_R, Vector3(-0.2, 0, 0))
		_rot(HAND_L if L else HAND_R, Vector3(-0.05, 0, 0))
		_rot(THIGH_L if L else THIGH_R, Vector3(0, 0, s * 0.02))
		_rot(SHIN_L if L else SHIN_R, Vector3(0.04, 0, 0))
		_rot(FOOT_L if L else FOOT_R, Vector3(-0.04, 0, 0))
	_rot(SPINE, Vector3(0.015 * sin(t * 1.4), 0, 0))
	_rot(CHEST, Vector3(0.01 * sin(t * 1.4 + 0.5), 0, 0))
	_rot(NECK, Vector3(0.04, 0, 0))


## Walking/running cycle: phase in radians (one stride per TAU), amount 0..1,
## run 0 (walk) .. 1 (run). Matches the first-person gait.
func pose_walk(phase: float, amount: float, run: float) -> void:
	var hips := _overlay()
	# Short, careful steps when crouched; legs hardly swing in the air.
	amount *= 1.0 - 0.45 * crouch
	amount *= 1.0 - 0.8 * air
	var swing := lerpf(0.42, 0.75, run) * amount
	for L in [true, false]:
		var s := -1.0 if L else 1.0
		var ph := phase + (0.0 if L else PI)
		_rot(THIGH_L if L else THIGH_R, Vector3(-sin(ph) * swing, 0, s * 0.02))
		var knee := maxf(0.0, sin(ph + 1.25)) * lerpf(0.75, 1.5, run) * amount + 0.05
		_rot(SHIN_L if L else SHIN_R, Vector3(knee, 0, 0))
		_rot(FOOT_L if L else FOOT_R, Vector3(-knee * 0.35 + sin(ph) * swing * 0.4, 0, 0))
		_rot(UARM_L if L else UARM_R, Vector3(sin(ph) * swing * 0.75, 0, s * 0.1))
		_rot(FARM_L if L else FARM_R, Vector3(-lerpf(0.3, 1.25, run) * amount - 0.15, 0, 0))
	skeleton.set_bone_pose_position(HIPS, hips + Vector3(0, -absf(cos(phase)) * 0.03 * amount, 0))
	_rot(SPINE, Vector3(lerpf(0.03, 0.15, run) * amount, sin(phase) * 0.06 * amount, 0))
	_rot(CHEST, Vector3(lerpf(0.01, 0.07, run) * amount, -sin(phase) * 0.1 * amount, 0))
	_rot(NECK, Vector3(-lerpf(0.02, 0.12, run) * amount + 0.04, 0, 0))
