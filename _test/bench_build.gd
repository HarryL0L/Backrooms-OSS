extends SceneTree
# Dev benchmark: time ChunkBuilder.build() for a block of chunks (single thread).
# Run: godot --headless --path . --script res://_test/bench_build.gd

func _init() -> void:
	# `-- photoreal`: the Photoreal bake (finer lightmaps, corner AO, trim,
	# directional lightmap, bounce field).
	if OS.get_cmdline_user_args().has("photoreal"):
		ChunkBuilder.lm_scale = 0.5
		ChunkBuilder.photoreal_ao = true
		ChunkBuilder.detail = true
		ChunkBuilder.dir_lm = true
		ChunkBuilder.gi = true
	var gen := WorldGen.new(12345)
	var c0 := ChunkManager.chunk_of(gen.spawn_position())
	var t := Time.get_ticks_usec()
	var n := 0
	var verts := 0
	var texels := 0
	var r := 1 if OS.get_cmdline_user_args().has("small") else 2
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var b := ChunkBuilder.new(gen, c0 + Vector2i(dx, dz))
			var d := b.build()
			n += 1
			for m in d.surfaces:
				verts += (d.surfaces[m][Mesh.ARRAY_VERTEX] as PackedVector3Array).size()
			if d.has("lightmap") and d.lightmap != null:
				texels += d.lightmap.get_width() * d.lightmap.get_height()
	var ms := (Time.get_ticks_usec() - t) / 1000.0
	print("chunks=%d  avg %.1f ms/chunk  avg verts %d  avg lightmap texels %d" % [n, ms / n, verts / n, texels / n])
	quit()
