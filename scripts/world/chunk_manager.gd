class_name ChunkManager
extends Node3D
## Streams chunks around a target node, Minecraft style.
##
## Geometry + lighting is built on the WorkerThreadPool; the main thread only
## uploads finished meshes, with a per-frame time budget so streaming never
## causes a hitch. Chunks are requested nearest-first and outside the view
## radius they are freed. Fog and the darkness of the Backrooms hide the edge.

signal initial_area_ready

var gen: WorldGen
var mats: WorldMaterials
var target: Node3D
var view_radius := 3
var cast_shadows := false
## Chunks take part in VoxelGI (experimental, Forward+).
var gi_static := false

var _chunks := {}        # Vector2i -> Node3D
var _stale := {}         # loaded chunks waiting to be rebuilt (settings changed)
var _tasks := {}         # Vector2i -> task id
var _results := {}       # Vector2i -> Dictionary (finished, waiting for upload)
var _mutex := Mutex.new()
var _last_center := Vector2i(1 << 30, 0)
var _wanted: Array[Vector2i] = []
var _initial_done := false
var _max_tasks := 2
var _generation := 0
## Only draw chunks you could see (ChunkVisibility): rooms behind walls
## aren't drawn at all.
var culling := true
var _vis: ChunkVisibility
var _vis_task := -1
var _vis_result := {}
var _vis_t := 0.0
var _vis_center := Vector2i(1 << 30, 0)
var _vis_pending := {}
## L.U.C.I.D. (stage 2): the state of every switchable lamp the loaded
## chunks' light depends on, in the global shader texture `lucid_lamps`
## (LAMP_GRID^2, R8, 1 = as baked, 0 = off; ChunkBuilder.lamp_index). The
## lightmaps keep each lamp's light (direct and bounce) apart, so the
## shaders scale it by this. Updated when the flicker clock ticks (14 Hz)
## or a lamp is overridden (set_lamp).
var _lamps := {}             # lamp index -> [cell, seed]
var _lamps_dirty := true
var _lamp_level := {}        # lamp index -> current level (0..1)
var _lamp_bytes := PackedByteArray()
var _lamp_img: Image
var _lamp_tex: ImageTexture
var _lamp_tick := -1
var _overrides := {}         # cell -> level
## The manager the game uses (for things that light themselves from the
## probe grid: light_cube()).
static var current: ChunkManager


func _ready() -> void:
	_max_tasks = clampi(OS.get_processor_count() - 1, 1, 6)
	current = self
	var n := ChunkBuilder.LAMP_GRID
	_lamp_bytes.resize(n * n)
	_lamp_bytes.fill(255)
	_lamp_img = Image.create_from_data(n, n, false, Image.FORMAT_R8, _lamp_bytes)
	_lamp_tex = ImageTexture.create_from_image(_lamp_img)
	RenderingServer.global_shader_parameter_set("lucid_lamps", _lamp_tex)


func setup(p_gen: WorldGen, p_mats: WorldMaterials) -> void:
	clear()
	gen = p_gen
	mats = p_mats
	mats.set_world_seed(gen.seed_value)
	_vis = ChunkVisibility.new(gen)
	_initial_done = false
	_last_center = Vector2i(1 << 30, 0)


## Switches to another floor's world without waiting for builds in flight
## (their results are dropped): no hitch while you're on the stairs.
func swap_world(p_gen: WorldGen) -> void:
	_generation += 1
	_wait_vis()
	gen = p_gen
	_vis = ChunkVisibility.new(gen)
	_mutex.lock()
	_results.clear()
	_mutex.unlock()
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()
	_stale.clear()
	_wanted.clear()
	_initial_done = false
	_last_center = Vector2i(1 << 30, 0)


func clear() -> void:
	_lamps_dirty = true
	_generation += 1
	_wait_vis()
	for id in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()
	_stale.clear()
	_wanted.clear()


## Rebuilds every loaded chunk (e.g. after a lighting setting changed). Old
## chunks stay in place until their replacement is ready, so nothing pops out
## from under the player.
func rebuild() -> void:
	for k in _chunks.keys():
		_stale[k] = true


func loaded_count() -> int:
	return _chunks.size()


func is_area_ready(p: Vector3, radius: int) -> bool:
	var c := chunk_of(p)
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			if not _chunks.has(c + Vector2i(dx, dz)):
				return false
	return true


static func chunk_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / WorldGen.CHUNK_SIZE), floori(p.z / WorldGen.CHUNK_SIZE))


func _process(_delta: float) -> void:
	if gen == null or target == null:
		return
	var center := chunk_of(target.global_position)
	if center != _last_center:
		_last_center = center
		_refresh_wanted(center)
		_unload_far(center)
	_reap_tasks()
	_schedule()
	_upload(center)
	_update_visibility(center, _delta)
	if ChunkBuilder.lucid:
		_update_lamps()
	if not _initial_done and is_area_ready(target.global_position, 1):
		_initial_done = true
		initial_area_ready.emit()


# ------------------------------------------------------------- culling ---

## Whether chunk c is loaded and drawn (not culled as out of sight).
func is_shown(c: Vector2i) -> bool:
	return _chunks.has(c) and (_chunks[c] as Node3D).visible


func _wait_vis() -> void:
	if _vis_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_vis_task)
		_vis_task = -1
	_vis_result = {}


func _update_visibility(center: Vector2i, delta: float) -> void:
	if _vis_task >= 0 and WorkerThreadPool.is_task_completed(_vis_task):
		WorkerThreadPool.wait_for_task_completion(_vis_task)
		_vis_task = -1
		_vis_result = _vis_pending
		_apply_visibility(center)
	elif center != _vis_center:
		# Moved into another chunk: its neighbours show at once.
		_apply_visibility(center)
	_vis_center = center
	_vis_t -= delta
	if _vis_task < 0 and _vis_t <= 0.0 and culling and _vis:
		_vis_t = 0.15
		var res := {}
		var p := target.global_position
		var reach := (view_radius + 1.5) * WorldGen.CHUNK_SIZE
		var v := _vis
		_vis_pending = res
		_vis_task = WorkerThreadPool.add_task(func() -> void:
			res.merge(v.visible_from(p, reach)))


func _apply_visibility(center: Vector2i) -> void:
	for k in _chunks:
		(_chunks[k] as Node3D).visible = _wants_shown(k, center)


func _wants_shown(k: Vector2i, center: Vector2i) -> bool:
	if not culling or _vis_result.is_empty():
		return true
	# Right around you, always (nothing can pop in close up).
	if absi(k.x - center.x) <= 1 and absi(k.y - center.y) <= 1:
		return true
	return _vis_result.has(k)


func _refresh_wanted(center: Vector2i) -> void:
	_wanted.clear()
	for dz in range(-view_radius, view_radius + 1):
		for dx in range(-view_radius, view_radius + 1):
			if dx * dx + dz * dz <= view_radius * view_radius + 1:
				_wanted.append(center + Vector2i(dx, dz))
	_wanted.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return (a - center).length_squared() < (b - center).length_squared())


func _unload_far(center: Vector2i) -> void:
	var limit := (view_radius + 1) * (view_radius + 1) + 2
	for k in _chunks.keys():
		if (k - center).length_squared() > limit:
			_chunks[k].queue_free()
			_chunks.erase(k)
			_stale.erase(k)
			_lamps_dirty = true
	_mutex.lock()
	for k in _results.keys():
		if (k - center).length_squared() > limit:
			_results.erase(k)
	_mutex.unlock()


func _schedule() -> void:
	# Weak phones: many slow cores all building chunks starve the main and
	# render threads (stutter), so only two builders on the Potato preset.
	var limit := _max_tasks if int(Settings.get_value("graphics/preset")) > 0 else mini(_max_tasks, 2)
	for c in _wanted:
		if _tasks.size() >= limit:
			return
		if (_chunks.has(c) and not _stale.has(c)) or _tasks.has(c):
			continue
		_mutex.lock()
		var done := _results.has(c)
		_mutex.unlock()
		if done:
			continue
		_tasks[c] = WorkerThreadPool.add_task(_build_task.bind(c, gen, _generation), false, "chunk")


func _reap_tasks() -> void:
	for c in _tasks.keys():
		if WorkerThreadPool.is_task_completed(_tasks[c]):
			WorkerThreadPool.wait_for_task_completion(_tasks[c])
			_tasks.erase(c)


func _build_task(c: Vector2i, g: WorldGen, generation: int) -> void:
	var result := ChunkBuilder.new(g, c).build()
	_mutex.lock()
	if generation == _generation:
		_results[c] = result
	_mutex.unlock()


func _upload(center: Vector2i) -> void:
	var budget_us := 4000 if _initial_done else 40000
	var start := Time.get_ticks_usec()
	while Time.get_ticks_usec() - start < budget_us:
		_mutex.lock()
		var best := Vector2i.ZERO
		var found := false
		var best_d := 1 << 30
		for k in _results.keys():
			var d: int = (k - center).length_squared()
			if d < best_d:
				best_d = d
				best = k
				found = true
		var data: Dictionary = _results[best] if found else {}
		if found:
			_results.erase(best)
		_mutex.unlock()
		if not found:
			return
		if not _chunks.has(best):
			_chunks[best] = _make_chunk(data)
			_chunks[best].visible = _wants_shown(best, center)
		elif _stale.has(best):
			_stale.erase(best)
			_chunks[best].queue_free()
			_chunks[best] = _make_chunk(data)
			_chunks[best].visible = _wants_shown(best, center)


func _make_chunk(data: Dictionary) -> Node3D:
	var root := Node3D.new()
	var c: Vector2i = data.coord
	root.name = "Chunk_%d_%d" % [c.x, c.y]
	var mesh := ArrayMesh.new()
	var surfaces: Dictionary = data.surfaces
	var fmt := (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT) \
			| (Mesh.ARRAY_CUSTOM_RG_FLOAT << Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT)
	# Each chunk has its own lightmap, so lightmapped materials get a per-chunk
	# copy that points at it (same shader, so no extra shader compiles).
	var lm_tex: ImageTexture = null
	var seed_tex: ImageTexture = null
	var dir_tex: ImageTexture = null
	if data.get("lightmap") != null:
		lm_tex = ImageTexture.create_from_image(data.lightmap)
		seed_tex = ImageTexture.create_from_image(data.lightmap_seed)
		if data.get("lightmap_dir") != null:
			dir_tex = ImageTexture.create_from_image(data.lightmap_dir)
	for m in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[m], [], {}, fmt)
		var mat: Material = mats.materials[m]
		if lm_tex != null and ChunkBuilder.LIGHTMAPPED.has(m):
			mat = mat.duplicate()
			(mat as ShaderMaterial).set_shader_parameter("lightmap", lm_tex)
			(mat as ShaderMaterial).set_shader_parameter("lightmap_seed", seed_tex)
			if dir_tex != null:
				(mat as ShaderMaterial).set_shader_parameter("lightmap_dir", dir_tex)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_STATIC if gi_static else GeometryInstance3D.GI_MODE_DISABLED
	root.add_child(mi)
	var faces: PackedVector3Array = data.collision
	if faces.size() > 0:
		var body := StaticBody3D.new()
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(faces)
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
		root.add_child(body)
	if data.has("probes"):
		root.set_meta("probes", data.probes)
	if data.has("grid"):
		root.set_meta("grid", data.grid)
		root.set_meta("grid_slots", data.grid_slots)
		root.set_meta("grid_walls", data.grid_walls)
		root.set_meta("grid_floor", data.grid_floor)
	if data.has("lamps"):
		root.set_meta("lamps", data.lamps)
		_lamps_dirty = true
	add_child(root)
	return root


# ---------------------------------------------------------- Lucid lamps ---

## Switches a lamp (by its cell) to `level` (0 = dead, 1 = as baked) until
## cleared with a negative level. Only switchable (flickering) lamps have
## their light kept apart in the bake; for them it replaces the flicker.
func set_lamp(cell: Vector2i, level: float) -> void:
	if level < 0.0:
		_overrides.erase(cell)
	else:
		_overrides[cell] = level
	_lamp_tick = -1


## The level of switchable lamp `idx` (ChunkBuilder.lamp_index) right now.
func lamp_level(idx: int) -> float:
	return _lamp_level.get(idx, 1.0)


func _update_lamps() -> void:
	if _lamps_dirty:
		_lamps_dirty = false
		var old := _lamps
		_lamps = {}
		for ch in _chunks.values():
			if not ch.has_meta("lamps"):
				continue
			var l: PackedFloat32Array = ch.get_meta("lamps")
			for i in range(0, l.size(), 3):
				var cell := Vector2i(int(l[i]), int(l[i + 1]))
				_lamps[ChunkBuilder.lamp_index(cell.x, cell.y)] = [cell, l[i + 2]]
		# Texels no longer used go back to "as baked".
		for idx in old:
			if not _lamps.has(idx):
				_lamp_bytes[idx] = 255
				_lamp_level.erase(idx)
		_lamp_tick = -1
	var t := Ambience.world_time()
	var tick := int(floor(t * 14.0))
	if tick == _lamp_tick:
		return
	_lamp_tick = tick
	for idx in _lamps:
		var e: Array = _lamps[idx]
		var v: float = _overrides[e[0]] if _overrides.has(e[0]) else WorldGen.flicker(e[1], t)
		_lamp_level[idx] = v
		_lamp_bytes[idx] = clampi(roundi(v * 255.0), 0, 255)
	_lamp_img.set_data(ChunkBuilder.LAMP_GRID, ChunkBuilder.LAMP_GRID, false, Image.FORMAT_R8, _lamp_bytes)
	_lamp_tex.update(_lamp_img)


# ------------------------------------------------------ Lucid probe grid ---

## L.U.C.I.D.: the light arriving at point p from the six axis directions
## (+x -x +y -y +z -z: an ambient cube, E / pi in engine units, so a
## surface of albedo a facing n shows a x sum(n_i^2 cube_i)), from the
## probe grid the chunks bake (ChunkBuilder._light_grid): direct light from
## the fixtures each probe can see, the far tail and the bounce, with the
## switchable lamps at their current level. Blended between the four cells
## round p (never through a wall) and the two probe heights. Empty where no
## chunk with a grid is loaded.
func light_cube(p: Vector3) -> PackedColorArray:
	var out := PackedColorArray()
	var cw := WorldGen.CELL
	var c0 := Vector2i(floori(p.x / cw), floori(p.z / cw))
	var fu := p.x / cw - c0.x - 0.5
	var fv := p.z / cw - c0.y - 0.5
	var c1 := c0 + Vector2i(1 if fu > 0.0 else -1, 0)
	var c2 := c0 + Vector2i(0, 1 if fv > 0.0 else -1)
	var c3 := Vector2i(c1.x, c2.y)
	var wu := absf(fu)
	var wv := absf(fv)
	var walls0 := _grid_walls(c0)
	if walls0 < 0:
		return out
	# Neighbours behind a wall (or not loaded) are left out.
	var open_u := _open(c0, c1, walls0)
	var open_v := _open(c0, c2, walls0)
	var open_d := open_u and open_v and _open(c1, c3, _grid_walls(c1)) and _open(c2, c3, _grid_walls(c2))
	var cells := [c0, c1, c2, c3]
	var ws := [(1.0 - wu) * (1.0 - wv), wu * (1.0 - wv) if open_u else 0.0, (1.0 - wu) * wv if open_v else 0.0, wu * wv if open_d else 0.0]
	out.resize(6)
	out.fill(Color(0, 0, 0))
	var tw := 0.0
	for q in 4:
		var w: float = ws[q]
		if w <= 0.0:
			continue
		var cube := _grid_cube(cells[q], p.y)
		if cube.is_empty():
			continue
		for a in 6:
			out[a] += cube[a] * w
		tw += w
	if tw <= 0.0:
		return PackedColorArray()
	for a in 6:
		out[a] = out[a] / tw
	return out


## The probe cube of world cell c at height y (above the cell's floor, the
## two probe heights blended), with the slot lamps at their level.
func _grid_cube(c: Vector2i, y: float) -> PackedColorArray:
	var ck := Vector2i(floori(float(c.x) / WorldGen.CHUNK), floori(float(c.y) / WorldGen.CHUNK))
	var ch: Node3D = _chunks.get(ck)
	if ch == null or not ch.has_meta("grid"):
		return PackedColorArray()
	var grid: PackedColorArray = ch.get_meta("grid")
	var slots: PackedFloat32Array = ch.get_meta("grid_slots")
	var ci := (c.x - ck.x * WorldGen.CHUNK) + (c.y - ck.y * WorldGen.CHUNK) * WorldGen.CHUNK
	var f: float = (ch.get_meta("grid_floor") as PackedFloat32Array)[ci]
	var gy: Array = ChunkBuilder.GRID_Y
	var t := clampf((y - f - gy[0]) / (gy[1] - gy[0]), 0.0, 1.0)
	var dims := PackedFloat32Array()
	dims.resize(12)
	for q in 2:
		var o := ci * 26 + q * 13
		var lvl := lamp_level(int(slots[o]))
		if lvl < 1.0:
			for a in 12:
				dims[a] += slots[o + 1 + a] * (1.0 - lvl)
	var out := PackedColorArray()
	out.resize(6)
	for a in 6:
		var lo := grid[ci * 12 + a] * (1.0 - dims[a])
		var hi := grid[ci * 12 + 6 + a] * (1.0 - dims[6 + a])
		out[a] = lo.lerp(hi, t)
	return out


## Walls round world cell c (ChunkBuilder grid_walls bits), -1 if unknown.
func _grid_walls(c: Vector2i) -> int:
	var ck := Vector2i(floori(float(c.x) / WorldGen.CHUNK), floori(float(c.y) / WorldGen.CHUNK))
	var ch: Node3D = _chunks.get(ck)
	if ch == null or not ch.has_meta("grid_walls"):
		return -1
	var w: PackedByteArray = ch.get_meta("grid_walls")
	return w[(c.x - ck.x * WorldGen.CHUNK) + (c.y - ck.y * WorldGen.CHUNK) * WorldGen.CHUNK]


## Whether light may be blended from neighbouring cell b into cell a.
func _open(a: Vector2i, b: Vector2i, walls_a: int) -> bool:
	if walls_a < 0 or _grid_walls(b) < 0:
		return false
	var d := b - a
	var bit := 1 if d.x < 0 else (2 if d.x > 0 else (4 if d.y < 0 else 8))
	return walls_a & bit == 0


## The ambient cube `cube` (light_cube) seen by a surface facing n.
static func cube_light(cube: PackedColorArray, n: Vector3) -> Color:
	if cube.size() < 6:
		return Color(0, 0, 0)
	var c := cube[0 if n.x > 0.0 else 1] * (n.x * n.x)
	c += cube[2 if n.y > 0.0 else 3] * (n.y * n.y)
	c += cube[4 if n.z > 0.0 else 5] * (n.z * n.z)
	return c


## L.U.C.I.D.: light arriving at point p from direction n (the baked ambient
## cube of p's cell: E / pi in engine units, which is also the mean
## luminance a camera sees looking along n). Alpha -1: no probe here (chunk
## not loaded, or not built with Lucid).
func light_probe(p: Vector3, n: Vector3) -> Color:
	var c := chunk_of(p)
	var ch: Node3D = _chunks.get(c)
	if ch == null or not ch.has_meta("probes"):
		return Color(0, 0, 0, -1)
	var pr: PackedColorArray = ch.get_meta("probes")
	var i := clampi(floori(p.x / WorldGen.CELL) - c.x * WorldGen.CHUNK, 0, WorldGen.CHUNK - 1)
	var j := clampi(floori(p.z / WorldGen.CELL) - c.y * WorldGen.CHUNK, 0, WorldGen.CHUNK - 1)
	var o := (i + j * WorldGen.CHUNK) * 6
	var col := pr[o + (0 if n.x > 0.0 else 1)] * (n.x * n.x)
	col += pr[o + (2 if n.y > 0.0 else 3)] * (n.y * n.y)
	col += pr[o + (4 if n.z > 0.0 else 5)] * (n.z * n.z)
	col.a = 1.0
	return col


func set_shadows(on: bool) -> void:
	cast_shadows = on
	for c in _chunks.values():
		for ch in c.get_children():
			if ch is MeshInstance3D:
				ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func set_gi(on: bool) -> void:
	gi_static = on
	for c in _chunks.values():
		for ch in c.get_children():
			if ch is MeshInstance3D:
				ch.gi_mode = GeometryInstance3D.GI_MODE_STATIC if on else GeometryInstance3D.GI_MODE_DISABLED


func _exit_tree() -> void:
	for id in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
