class_name FieldGrass
extends Node3D
## The Field's realistic grass on High, Max and Realistic (Medium and below
## keep the ground shader's lawn): instanced blades in three rings round
## you (dense near, fewer and wider farther), each ring a grid of tiles
## that follow you in whole tiles (so the blades stay where they grow), all
## tiles of a ring drawing one shared MultiMesh with one material.
## shaders/field_grass.gdshader shapes, bends and colours each blade.

const SHADER := preload("res://shaders/field_grass.gdshader")
## Per ring: tile size (m), tiles each side of yours, the ring's radii (m),
## blades per m2, segments per blade, blade width (m).
const RINGS := [
	{"tile": 5.0, "n": 2, "r_in": 0.0, "r_out": 8.0, "dens": 130.0, "segs": 3, "width": 0.012, "fade": 2.0},
	{"tile": 12.0, "n": 2, "r_in": 8.0, "r_out": 21.0, "dens": 32.0, "segs": 2, "width": 0.02, "fade": 4.0},
	{"tile": 32.0, "n": 2, "r_in": 21.0, "r_out": 55.0, "dens": 8.0, "segs": 1, "width": 0.045, "fade": 10.0},
]

## Max and Realistic: denser, reaching farther.
var spread := 1.0
var _rings := []


## Builds the rings; `dense` for Max and Realistic.
func setup(dense: bool) -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY
	spread = 1.15 if dense else 1.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for r: Dictionary in RINGS:
		var tile: float = r.tile
		var r_out: float = r.r_out * spread
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = _blade(r.segs)
		# Stratified jitter: one blade per cell of a fine grid over the tile.
		var per := int(tile * tile * float(r.dens) * (spread if dense else 1.0))
		var side := int(ceil(sqrt(float(per))))
		mm.instance_count = side * side
		var cell := tile / side
		for i in side * side:
			var x := (float(i % side) + rng.randf()) * cell
			var z := (float(i / side) + rng.randf()) * cell
			mm.set_instance_transform(i, Transform3D(Basis.IDENTITY, Vector3(x, 0.0, z)))
		mm.custom_aabb = AABB(Vector3(-1.0, -10.0, -1.0), Vector3(tile + 2.0, 22.0, tile + 2.0))
		var mat := ShaderMaterial.new()
		mat.shader = SHADER
		mat.set_shader_parameter("r_in", float(r.r_in) * spread)
		mat.set_shader_parameter("r_out", r_out)
		mat.set_shader_parameter("width", r.width)
		mat.set_shader_parameter("fade", r.fade)
		var tiles := []
		var n: int = r.n
		for k in (2 * n + 1) * (2 * n + 1):
			var mi := MultiMeshInstance3D.new()
			mi.multimesh = mm
			mi.material_override = mat
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mi)
			tiles.append(mi)
		_rings.append({"r": r, "tiles": tiles, "key": Vector2i(1 << 30, 0), "r_out": r_out, "mat": mat})


## The farthest blades (m): the ground takes their colour past this.
func reach() -> float:
	return float(RINGS[RINGS.size() - 1].r_out) * spread


## A blade of `segs` segments: a strip tapering to a point.
static func _blade(segs: int) -> ArrayMesh:
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for s in segs:
		var y := float(s) / segs
		v.push_back(Vector3(-0.5, y, 0.0))
		v.push_back(Vector3(0.5, y, 0.0))
	v.push_back(Vector3(0.0, 1.0, 0.0))
	for s in segs - 1:
		var b := s * 2
		idx.append_array([b, b + 2, b + 1, b + 1, b + 2, b + 3])
	var top := (segs - 1) * 2
	idx.append_array([top, segs * 2, top + 1])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	return m


## Moves the tiles with the camera (whole tiles at a time); hides those
## wholly outside their ring.
func update(cam: Vector3) -> void:
	for ring: Dictionary in _rings:
		var r: Dictionary = ring.r
		var tile: float = r.tile
		var c := Vector2i(floori(cam.x / tile), floori(cam.z / tile))
		if c == ring.key:
			continue
		ring.key = c
		var n: int = r.n
		var lo: float = float(r.r_in) * spread - float(r.fade)
		var hi: float = ring.r_out + float(r.fade)
		var k := 0
		for j in range(-n, n + 1):
			for i in range(-n, n + 1):
				var mi: MultiMeshInstance3D = ring.tiles[k]
				k += 1
				var o := Vector3((c.x + i) * tile, FieldLevel.FIELD_Y, (c.y + j) * tile)
				mi.global_position = o
				# Nearest and farthest points of the tile from the camera's tile.
				var cx := (c.x + 0.5) * tile
				var cz := (c.y + 0.5) * tile
				var nx := clampf(cx, o.x, o.x + tile) - cx
				var nz := clampf(cz, o.z, o.z + tile) - cz
				var fx := maxf(absf(o.x - cx), absf(o.x + tile - cx))
				var fz := maxf(absf(o.z - cz), absf(o.z + tile - cz))
				var near := sqrt(nx * nx + nz * nz) - tile
				var far := sqrt(fx * fx + fz * fz) + tile
				mi.visible = near < hi and far > lo
