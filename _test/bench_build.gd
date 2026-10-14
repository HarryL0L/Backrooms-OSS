extends SceneTree
# Dev benchmark: time ChunkBuilder.build() for a block of chunks (single thread).
# Run: godot --headless --path . --script res://_test/bench_build.gd

func _init() -> void:
	var gen := WorldGen.new(12345)
	var c0 := ChunkManager.chunk_of(gen.spawn_position())
	var t := Time.get_ticks_usec()
	var n := 0
	var verts := 0
	var texels := 0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
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
