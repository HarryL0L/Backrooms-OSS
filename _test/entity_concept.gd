extends Node3D
# Concept render of "The Lining": a figure pressing out through the Yellow Halls
# wallpaper. Uses the game's own wallpaper/carpet/ceiling shaders.
# Run: godot --path . res://_test/entity_concept.tscn -- <out_prefix>

var mats: WorldMaterials

# Capsule list in wall space (x across, y up, metres): [a, b, radius, height]
var parts := []

func _cap(a: Vector2, b: Vector2, r: float, h: float) -> void:
	parts.append([a, b, r, h])

func _seg_d(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 1e-6), 0.0, 1.0)
	return p.distance_to(a + ab * t)

## How far the figure pushes the paper out at wall point p.
func relief(p: Vector2) -> float:
	var h := 0.0
	for c in parts:
		var d := _seg_d(p, c[0], c[1])
		var r: float = c[2]
		if d < r * 1.6:
			var k := clampf(1.0 - (d / r) * (d / r), 0.0, 1.0)
			# Rounded body plus a soft skirt where the paper drapes.
			var v: float = c[3] * sqrt(k) + c[3] * 0.25 * exp(-pow(d / r, 2.0) * 1.5)
			h = maxf(h, v) + 0.12 * minf(h, v)     # soft union
	return maxf(h, 0.0)


## Face pressed into the paper: nose, brow, cheekbones, chin (added on top of
## the membrane) and the open mouth / eye hollows (subtracted).
func face(p: Vector2) -> float:
	var c := Vector2(0.035, 1.64)                  # face centre (head tilted a little)
	var q := p - c
	q = Vector2(q.x * cos(0.12) - q.y * sin(0.12), q.x * sin(0.12) + q.y * cos(0.12))
	var f := 0.0
	f += 0.022 * exp(-pow(q.x / 0.014, 2.0) - pow((q.y + 0.005) / 0.032, 2.0))          # nose
	f += 0.012 * exp(-pow(q.x / 0.06, 2.0) - pow((q.y - 0.045) / 0.012, 2.0))           # brow
	for sx in [-1.0, 1.0]:
		f += 0.008 * exp(-pow((q.x - sx * 0.042) / 0.02, 2.0) - pow((q.y + 0.02) / 0.016, 2.0))   # cheeks
		f -= 0.016 * exp(-pow((q.x - sx * 0.03) / 0.017, 2.0) - pow((q.y - 0.022) / 0.012, 2.0))  # eye hollows
	f -= 0.03 * exp(-pow(q.x / 0.022, 2.0) - pow((q.y + 0.06) / 0.028, 2.0))           # open mouth
	f += 0.01 * exp(-pow(q.x / 0.03, 2.0) - pow((q.y + 0.105) / 0.015, 2.0))           # chin
	return f


func _ready() -> void:
	mats = WorldMaterials.new()
	mats.set_world_seed(12345)
	var we := WorldEnvironment.new()
	we.environment = load("res://scripts/world/environment_factory.gd").make()
	add_child(we)
	RenderingServer.global_shader_parameter_set("world_time", 3.0)
	# Figure: head, neck, torso, raised arms with palms and fingers pressed flat.
	_cap(Vector2(0.035, 1.62), Vector2(0.03, 1.69), 0.085, 0.1)     # head (pushed hardest)
	_cap(Vector2(0.03, 1.47), Vector2(0.03, 1.55), 0.045, 0.045)    # neck
	_cap(Vector2(0.02, 1.08), Vector2(0.02, 1.33), 0.15, 0.04)      # chest
	_cap(Vector2(0.02, 0.85), Vector2(0.02, 1.05), 0.12, 0.022)     # belly
	_cap(Vector2(-0.17, 1.39), Vector2(0.21, 1.39), 0.055, 0.04)    # shoulders
	_cap(Vector2(-0.18, 1.38), Vector2(-0.33, 1.63), 0.04, 0.045)   # left upper arm
	_cap(Vector2(-0.33, 1.63), Vector2(-0.29, 1.92), 0.035, 0.06)   # left forearm
	_cap(Vector2(0.22, 1.38), Vector2(0.38, 1.66), 0.04, 0.045)     # right upper arm
	_cap(Vector2(0.38, 1.66), Vector2(0.36, 2.02), 0.035, 0.065)    # right forearm (higher)
	for side in [-1.0, 1.0]:
		var palm: Vector2 = Vector2(-0.29, 1.98) if side < 0.0 else Vector2(0.36, 2.08)
		_cap(palm - Vector2(0, 0.035), palm + Vector2(0, 0.025), 0.042, 0.085)
		for f in 5:
			var ang: float = deg_to_rad(-48.0 + f * 24.0) * side
			var dirv := Vector2(sin(ang), cos(ang))
			var flen: float = [0.075, 0.105, 0.115, 0.105, 0.085][f]
			if f == 0:
				dirv = Vector2(-side * 0.95, 0.1).normalized()
				flen = 0.08
			_cap(palm + dirv * 0.035, palm + dirv * (0.035 + flen), 0.015, 0.075)
	_cap(Vector2(-0.06, 0.2), Vector2(-0.05, 0.85), 0.06, 0.012)     # legs, barely there
	_cap(Vector2(0.1, 0.2), Vector2(0.09, 0.85), 0.06, 0.012)

	_relief_wall(Vector3(0, 0, 0), 2.4, 2.7)
	_flat(ChunkBuilder.MAT_WALLPAPER, Vector3(-3.6, 0, 0), Vector3(2.4, 0, 0), Vector3(0, 2.7, 0), Vector3(0, 0, 1), 0.8)
	_flat(ChunkBuilder.MAT_WALLPAPER, Vector3(1.2, 0, 0), Vector3(2.4, 0, 0), Vector3(0, 2.7, 0), Vector3(0, 0, 1), 0.7)
	_flat(ChunkBuilder.MAT_WALLPAPER, Vector3(-3.6, 0, 0), Vector3(0, 0, 5.0), Vector3(0, 2.7, 0), Vector3(1, 0, 0), 0.55)
	_flat(ChunkBuilder.MAT_WALLPAPER, Vector3(3.6, 0, 5.0), Vector3(0, 0, -5.0), Vector3(0, 2.7, 0), Vector3(-1, 0, 0), 0.5)
	_flat(ChunkBuilder.MAT_CARPET, Vector3(-3.6, 0, 5.0), Vector3(7.2, 0, 0), Vector3(0, 0, -5.0), Vector3(0, 1, 0), 0.7)
	_flat(ChunkBuilder.MAT_CEILING_TILE, Vector3(-3.6, 2.7, 0), Vector3(7.2, 0, 0), Vector3(0, 0, 5.0), Vector3(0, -1, 0), 0.75)
	var panel := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.22, 0.02, 0.62)
	panel.mesh = bm
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.albedo_color = Color(1.0, 0.97, 0.85) * 1.6
	panel.material_override = pm
	panel.position = Vector3(0.2, 2.69, 1.6)
	add_child(panel)

	var cam := Camera3D.new()
	cam.fov = 70
	add_child(cam)
	cam.current = true
	var out: String = OS.get_cmdline_user_args()[0] if OS.get_cmdline_user_args().size() > 0 else "user://entity"
	for shot in [[Vector3(1.4, 1.6, 4.0), Vector3(0.05, 1.35, 0.0), "wide"], [Vector3(0.55, 1.58, 1.05), Vector3(0.05, 1.7, 0.0), "close"]]:
		cam.position = shot[0]
		cam.look_at(shot[1])
		for i in 12:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("%s_%s.png" % [out, shot[2]])
	get_tree().quit()


## Baked-looking light for a point: warm overhead panel, falloff, contact AO.
func _light(p: Vector3, n: Vector3, base: float) -> Color:
	var lp := Vector3(0.2, 2.5, 1.6)
	var l := (lp - p)
	var d := l.length()
	var ndl := maxf(n.dot(l / d), 0.0)
	var v := base * (0.35 + 1.6 * ndl / (1.0 + d * d * 0.18))
	v *= 0.62 + 0.38 * smoothstep(0.0, 0.6, p.y)
	return Color(v * 1.0, v * 0.95, v * 0.7, 0.0)


func _relief_wall(origin: Vector3, w: float, h: float) -> void:
	var nu := 200
	var nv := 225
	var arrays := _new_arrays()
	var hgt := PackedFloat32Array()
	hgt.resize(nu * nv)
	var raw := PackedFloat32Array()
	raw.resize(nu * nv)
	for j in nv:
		for i in nu:
			var p := Vector2(-w * 0.5 + w * i / (nu - 1), h * j / (nv - 1))
			raw[i + j * nu] = relief(p)
	# Paper is a sheet pulled taut over the body: relax it like a membrane that
	# can't go below the body (tents between hands, head and shoulders).
	hgt = raw.duplicate()
	for it in 22:
		var nh := hgt.duplicate()
		for j in range(1, nv - 1):
			for i in range(1, nu - 1):
				var k := i + j * nu
				# Glue pulls the paper back to the wall, so it only tents locally.
				var avg := (hgt[k - 1] + hgt[k + 1] + hgt[k - nu] + hgt[k + nu]) * 0.25 * 0.93
				nh[k] = maxf(raw[k], avg)
		hgt = nh
	for j in nv:
		for i in nu:
			var p := Vector2(-w * 0.5 + w * i / (nu - 1), h * j / (nv - 1))
			hgt[i + j * nu] = maxf(hgt[i + j * nu] + face(p), 0.0)
	var blur := hgt.duplicate()
	for j in range(2, nv - 2):
		for i in range(2, nu - 2):
			var k := i + j * nu
			blur[k] = (hgt[k - 2] + hgt[k + 2] + hgt[k - 2 * nu] + hgt[k + 2 * nu] + hgt[k]) * 0.2
	for j in nv:
		for i in nu:
			var p := Vector2(-w * 0.5 + w * i / (nu - 1), h * j / (nv - 1))
			var z := hgt[i + j * nu]
			var zx := hgt[mini(i + 1, nu - 1) + j * nu] - hgt[maxi(i - 1, 0) + j * nu]
			var zy := hgt[i + mini(j + 1, nv - 1) * nu] - hgt[i + maxi(j - 1, 0) * nu]
			var dx := w / (nu - 1) * 2.0
			var dy := h / (nv - 1) * 2.0
			var n := Vector3(-zx / dx, -zy / dy, 1.0).normalized()
			var pos := origin + Vector3(p.x, p.y, z)
			# Paper stretches over the shape: the pattern drifts with the slope.
			var uv := Vector2(p.x + z * n.x * 0.6, -(p.y + z * n.y * 0.6))
			# Hollows (mouth, eyes, folds against the wall) catch less light.
			var cav := clampf((blur[i + j * nu] - z) * 40.0, 0.0, 0.6)
			var c := _light(pos, n, 0.85) * (1.0 - cav)
			c.a = 0.0
			_add(arrays, pos, n, uv, c)
	var idx := PackedInt32Array()
	for j in nv - 1:
		for i in nu - 1:
			var a := i + j * nu
			idx.append_array([a, a + nu, a + 1, a + 1, a + nu, a + nu + 1])
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh(arrays, ChunkBuilder.MAT_WALLPAPER)


func _flat(mat: int, o: Vector3, du: Vector3, dv: Vector3, n: Vector3, base: float) -> void:
	var arrays := _new_arrays()
	var nu := 24
	var nv := 24
	for j in nv:
		for i in nu:
			var pos := o + du * (float(i) / (nu - 1)) + dv * (float(j) / (nv - 1))
			var uv := Vector2(pos.x, pos.z) if absf(n.y) > 0.5 else (Vector2(pos.z, -pos.y) if absf(n.x) > 0.5 else Vector2(pos.x, -pos.y))
			_add(arrays, pos, n, uv, _light(pos, n, base))
	var idx := PackedInt32Array()
	var flip := du.cross(dv).dot(n) > 0.0
	for j in nv - 1:
		for i in nu - 1:
			var a := i + j * nu
			if flip:
				idx.append_array([a, a + nu, a + 1, a + 1, a + nu, a + nu + 1])
			else:
				idx.append_array([a, a + 1, a + nu, a + 1, a + nu + 1, a + nu])
	arrays[Mesh.ARRAY_INDEX] = idx
	_mesh(arrays, mat)


func _new_arrays() -> Array:
	var a := []
	a.resize(Mesh.ARRAY_MAX)
	a[Mesh.ARRAY_VERTEX] = PackedVector3Array()
	a[Mesh.ARRAY_NORMAL] = PackedVector3Array()
	a[Mesh.ARRAY_TANGENT] = PackedFloat32Array()
	a[Mesh.ARRAY_TEX_UV] = PackedVector2Array()
	a[Mesh.ARRAY_TEX_UV2] = PackedVector2Array()
	a[Mesh.ARRAY_CUSTOM0] = PackedFloat32Array()
	a[Mesh.ARRAY_CUSTOM1] = PackedFloat32Array()
	return a


func _add(a: Array, p: Vector3, n: Vector3, uv: Vector2, c: Color) -> void:
	a[Mesh.ARRAY_VERTEX].push_back(p)
	a[Mesh.ARRAY_NORMAL].push_back(n)
	var t := Vector3.UP.cross(n)
	if t.length_squared() < 0.01:
		t = Vector3.RIGHT
	t = t.normalized()
	a[Mesh.ARRAY_TANGENT].append_array([t.x, t.y, t.z, 1.0])
	a[Mesh.ARRAY_TEX_UV].push_back(uv)
	a[Mesh.ARRAY_TEX_UV2].push_back(Vector2.ZERO)
	a[Mesh.ARRAY_CUSTOM0].append_array([c.r, c.g, c.b, c.a])
	a[Mesh.ARRAY_CUSTOM1].append_array([-1.0, -1.0])


func _mesh(arrays: Array, mat: int) -> void:
	var m := ArrayMesh.new()
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) | (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, fmt)
	m.surface_set_material(0, mats.materials[mat])
	var mi := MeshInstance3D.new()
	mi.mesh = m
	add_child(mi)
