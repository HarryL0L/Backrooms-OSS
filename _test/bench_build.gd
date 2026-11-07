extends Node
# Dev benchmark: time ChunkBuilder.build() for a block of chunks (single thread).
# Run: godot --headless --path . res://_test/bench_build.tscn [-- small] [realistic] [no_gi] [no_detail] [no_lucid] [lm=<scale>]
# (a scene, so the autoloads the builder needs are there)

func _ready() -> void:
	# `-- realistic`: the Realistic bake (contrast, corner AO, trim, bounce
	# field); `no_gi`, `no_detail`, `lm=0.5` change one part of it.
	# (Set both ways: the saved settings may have switched Realistic on.)
	var args := OS.get_cmdline_user_args()
	var pr := args.has("realistic")
	ChunkBuilder.lightmaps = true
	ChunkBuilder.lm_scale = 1.0
	for a in args:
		if a.begins_with("lm="):
			ChunkBuilder.lm_scale = float(a.substr(3))
	ChunkBuilder.wall_ao = pr
	ChunkBuilder.contrast = pr
	ChunkBuilder.detail = pr and not args.has("no_detail")
	ChunkBuilder.dir_lm = false
	ChunkBuilder.gi = pr and not args.has("no_gi")
	# `no_lucid`: the Realistic bake without L.U.C.I.D. (the old fudged one).
	ChunkBuilder.lucid = ChunkBuilder.gi and not args.has("no_lucid")
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
	if args.has("phases"):
		# `phases`: how long the lights and the bounce field take on their own.
		var t_l := 0
		var t_g := 0
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var b := ChunkBuilder.new(gen, c0 + Vector2i(dx, dz))
				var t0 := Time.get_ticks_usec()
				b._compute_layout()
				b._compute_lights()
				var t1 := Time.get_ticks_usec()
				if b._gi:
					b._compute_gi()
				t_l += t1 - t0
				t_g += Time.get_ticks_usec() - t1
		print("phases: layout+lights %.1f ms/chunk, bounce field %.1f ms/chunk" % [t_l / 1000.0 / n, t_g / 1000.0 / n])
	print("chunks=%d  avg %.1f ms/chunk  avg verts %d  avg lightmap texels %d" % [n, ms / n, verts / n, texels / n])
	get_tree().quit()
