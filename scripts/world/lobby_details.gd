class_name LobbyDetails
extends Node3D
## The small things in the Yellow Halls, around the player:
##  - scattered electrical outlets, light switches and vent grilles low on
##    the walls, and empty mounts (a paler patch with screw holes where
##    something once hung);
##  - indents in the carpet where furniture stood once;
##  - now and then a dark, sodden patch of carpet: the floor under it is
##    rotten through. Step on it and it gives way (`floor_gave_way`).
## Built per REGION x REGION cells on worker threads, one MultiMesh each.

signal floor_gave_way

const REGION := 16
const TILES := 6       # outlet, switch, mount, vent, indents, sodden
enum { OUTLET, SWITCH, MOUNT, VENT, INDENT, SODDEN }

var gen: WorldGen
var target: Node3D
var _regions := {}         # Vector2i -> Node3D (or null while building)
var _tasks := {}           # Vector2i -> [task id, result dict]
var _scan := 0.0
static var _mat: ShaderMaterial


func clear() -> void:
	for r in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[r][0])
	_tasks.clear()
	for r in _regions:
		if _regions[r]:
			_regions[r].queue_free()
	_regions.clear()


func _exit_tree() -> void:
	for r in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[r][0])
	_tasks.clear()


func _process(delta: float) -> void:
	if gen == null or target == null:
		return
	for r in _tasks.keys():
		var t: Array = _tasks[r]
		if WorkerThreadPool.is_task_completed(t[0]):
			WorkerThreadPool.wait_for_task_completion(t[0])
			_tasks.erase(r)
			if _regions.has(r):
				_regions[r] = _build(t[1])
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.5
	var c := gen.cell_of(target.global_position)
	var rc := Vector2i(floori(float(c.x) / REGION), floori(float(c.y) / REGION))
	var keep := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var r := rc + Vector2i(dx, dz)
			keep[r] = true
			if not _regions.has(r):
				_regions[r] = null
				var res := {}
				_tasks[r] = [WorkerThreadPool.add_task(_compute.bind(gen, r, res)), res]
	for r in _regions.keys():
		if not keep.has(r) and not _tasks.has(r):
			if _regions[r]:
				_regions[r].queue_free()
			_regions.erase(r)


# --------------------------------------------------------------- placing ---
static func _compute(g: WorldGen, r: Vector2i, res: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = g.hashi(r.x, r.y, 1201)
	var C := WorldGen.CELL
	var items := []            # [Transform3D, tile, light]
	var sodden := Vector3.INF
	var dirs := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for j in REGION:
		for i in REGION:
			var gx := r.x * REGION + i
			var gz := r.y * REGION + j
			if g.biome_at(gx, gz) != WorldGen.LOBBY or g.is_solid(gx, gz, WorldGen.LOBBY):
				continue
			var centre := Vector3((gx + 0.5) * C, 0.0, (gz + 0.5) * C)
			var light := clampf(g.light_level_near(centre + Vector3.UP * 1.2) * 0.22, 0.04, 0.8)
			var edges := g._cell_edges(gx, gz)       # W, E, N, S
			for k in 4:
				if edges[k] != WorldGen.E_WALL:
					continue
				# The wall's inner face, looking into the cell.
				var n: Vector3 = dirs[k]           # W wall faces +X, E faces -X, ...
				var along := Vector3(-n.z, 0, n.x)
				var face := centre - n * (C * 0.5 - 0.075)
				var roll := rng.randf()
				var tile := -1
				var size := Vector2.ZERO
				var h := 0.0
				if roll < 0.11:
					tile = OUTLET
					size = Vector2(0.075, 0.115)
					h = 0.32
				elif roll < 0.135:
					tile = SWITCH
					size = Vector2(0.075, 0.115)
					h = 1.22
				elif roll < 0.16:
					tile = MOUNT
					size = Vector2(rng.randf_range(0.35, 0.7), rng.randf_range(0.25, 0.5))
					h = rng.randf_range(1.3, 1.7)
				elif roll < 0.175:
					tile = VENT
					size = Vector2(0.3, 0.16)
					h = 0.2
				if tile < 0:
					continue
				var p := face + along * rng.randf_range(-0.8, 0.8) + Vector3.UP * h
				items.append([Transform3D(Basis(along * size.x, Vector3.UP * size.y, n), p), tile, light])
			# Furniture indents in the carpet.
			if rng.randf() < 0.03:
				var a := rng.randf() * TAU
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -PI * 0.5)
				var p := centre + Vector3(rng.randf_range(-0.5, 0.5), 0.004, rng.randf_range(-0.5, 0.5))
				items.append([Transform3D(b.scaled(Vector3(1.3, 0.75, 1.0)), p), INDENT, light])
			# One rotten patch in some regions, away from the start.
			if sodden == Vector3.INF and not g.near_spawn(gx, gz, 8) and rng.randf() < 0.0016:
				sodden = centre + Vector3(rng.randf_range(-0.3, 0.3), 0.005, rng.randf_range(-0.3, 0.3))
				var b2 := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5)
				items.append([Transform3D(b2.scaled(Vector3(1.5, 1.3, 1.0)), sodden), SODDEN, light])
	res["items"] = items
	res["sodden"] = sodden


func _build(res: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var items: Array = res.get("items", [])
	if items.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = items.size()
		for i in items.size():
			var it: Array = items[i]
			mm.set_instance_transform(i, it[0])
			var lv: float = it[2]
			mm.set_instance_color(i, Color(lv, lv, lv))
			mm.set_instance_custom_data(i, Color(float(it[1]), 0, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var sp: Vector3 = res.get("sodden", Vector3.INF)
	if sp != Vector3.INF:
		var area := Area3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.45
		sh.height = 0.6
		cs.shape = sh
		area.add_child(cs)
		area.position = sp + Vector3.UP * 0.3
		area.body_entered.connect(func(body: Node3D) -> void:
			if body is Player:
				floor_gave_way.emit())
		root.add_child(area)
	return root


static func _material() -> ShaderMaterial:
	if _mat:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/clue.gdshader")
	var tex := ImageTexture.create_from_image(_atlas())
	_mat.set_shader_parameter("tex", tex)
	_mat.set_shader_parameter("tiles", float(TILES))
	return _mat


# ---------------------------------------------------------------- atlas ---
static func _atlas() -> Image:
	const T := 64
	var img := Image.create(T * TILES, T, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var plate := Color(0.86, 0.83, 0.74, 1)
	var dark := Color(0.12, 0.11, 0.1, 1)
	# Outlet: plate, two slots, a ground hole, a screw.
	_rect(img, OUTLET * T + 4, 2, 56, 60, plate)
	for sx in [24, 38]:
		_rect(img, OUTLET * T + sx, 16, 3, 10, dark)
		_rect(img, OUTLET * T + sx, 38, 3, 10, dark)
	_rect(img, OUTLET * T + 29, 29, 6, 6, Color(0.6, 0.58, 0.52, 1))
	# Switch: plate with a toggle.
	_rect(img, SWITCH * T + 4, 2, 56, 60, plate)
	_rect(img, SWITCH * T + 26, 20, 12, 24, Color(0.78, 0.75, 0.66, 1))
	_rect(img, SWITCH * T + 28, 22, 8, 9, Color(0.92, 0.9, 0.82, 1))
	# Empty mount: a cleaner, slightly paler rectangle of wallpaper (it was
	# out of the light), ragged at the edges; screw holes.
	for y in T:
		for x in T:
			var e := minf(minf(x, T - 1 - x), minf(y, T - 1 - y)) + rng.randf_range(-1.5, 1.5)
			if e > 1.0:
				img.set_pixel(MOUNT * T + x, y, Color(0.76, 0.74, 0.48, 1.0))
	for p in [Vector2i(8, 8), Vector2i(54, 8), Vector2i(8, 54), Vector2i(54, 54)]:
		_rect(img, MOUNT * T + p.x, p.y, 3, 3, dark)
	# Vent grille.
	_rect(img, VENT * T + 2, 8, 60, 48, Color(0.7, 0.68, 0.6, 1))
	for y in range(13, 52, 6):
		_rect(img, VENT * T + 7, y, 50, 3, Color(0.2, 0.19, 0.17, 1))
	# Furniture indents: four flattened squares in the pile.
	for p in [Vector2i(4, 6), Vector2i(52, 6), Vector2i(4, 50), Vector2i(52, 50)]:
		_rect(img, INDENT * T + p.x, p.y, 8, 8, Color(0.2, 0.17, 0.08, 0.75))
	# Sodden patch: a dark, soaked blot with a lighter tide line.
	for y in T:
		for x in T:
			var d := Vector2(x - 31.5, y - 31.5).length() / 30.0 + rng.randf_range(-0.05, 0.05)
			if d < 1.0:
				var c := Color(0.2, 0.16, 0.07, 0.9) if d < 0.82 else Color(0.38, 0.32, 0.15, 0.8)
				img.set_pixel(SODDEN * T + x, y, c)
	img.generate_mipmaps()
	return img


static func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			img.set_pixel(x, y, c)
