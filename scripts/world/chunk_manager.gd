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

var _chunks := {}        # Vector2i -> Node3D
var _tasks := {}         # Vector2i -> task id
var _results := {}       # Vector2i -> Dictionary (finished, waiting for upload)
var _mutex := Mutex.new()
var _last_center := Vector2i(1 << 30, 0)
var _wanted: Array[Vector2i] = []
var _initial_done := false
var _max_tasks := 2
var _generation := 0


func _ready() -> void:
	_max_tasks = clampi(OS.get_processor_count() - 1, 1, 6)


func setup(p_gen: WorldGen, p_mats: WorldMaterials) -> void:
	clear()
	gen = p_gen
	mats = p_mats
	mats.set_world_seed(gen.seed_value)
	_initial_done = false
	_last_center = Vector2i(1 << 30, 0)


func clear() -> void:
	_generation += 1
	for id in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
	_mutex.lock()
	_results.clear()
	_mutex.unlock()
	for c in _chunks.values():
		c.queue_free()
	_chunks.clear()
	_wanted.clear()


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
	if not _initial_done and is_area_ready(target.global_position, 1):
		_initial_done = true
		initial_area_ready.emit()


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
	_mutex.lock()
	for k in _results.keys():
		if (k - center).length_squared() > limit:
			_results.erase(k)
	_mutex.unlock()


func _schedule() -> void:
	for c in _wanted:
		if _tasks.size() >= _max_tasks:
			return
		if _chunks.has(c) or _tasks.has(c):
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
	if data.get("lightmap") != null:
		lm_tex = ImageTexture.create_from_image(data.lightmap)
	for m in surfaces:
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surfaces[m], [], {}, fmt)
		var mat: Material = mats.materials[m]
		if lm_tex != null and ChunkBuilder.LIGHTMAPPED.has(m):
			mat = mat.duplicate()
			(mat as ShaderMaterial).set_shader_parameter("lightmap", lm_tex)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mat)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
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
	add_child(root)
	return root


func set_shadows(on: bool) -> void:
	cast_shadows = on
	for c in _chunks.values():
		for ch in c.get_children():
			if ch is MeshInstance3D:
				ch.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if on else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


func _exit_tree() -> void:
	for id in _tasks.values():
		WorkerThreadPool.wait_for_task_completion(id)
	_tasks.clear()
