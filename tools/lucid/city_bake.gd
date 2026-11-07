extends Node3D
## Bakes a L.U.C.I.D. city level (stage 3, docs/LUCID.md): builds the
## level's plan with its occluders in a physics space, bakes every tile's
## surfaces per vertex (LucidCity.bake: lamps, the night and dusk states,
## sky visibility, relightable slots) and the probe grids for moving
## things, and saves them next to the level's assets. Run headless:
##   godot --headless --path . res://tools/lucid/city_bake.tscn [-- --count] [-- --rays N]
## (--count: only print the vertex counts).

const LAYOUT := "res://scripts/world/levels/night_city_layout.gd"
const OUT := "res://assets/levels/night_city/bake/"
const STATES := ["night", "dusk"]


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var rays := 48
	for i in args.size():
		if args[i] == "--rays" and i + 1 < args.size():
			rays = int(args[i + 1])
	var t0 := Time.get_ticks_msec()
	var lay: RefCounted = load(LAYOUT).new()
	lay.build(true)
	var total := 0
	for tile in lay.tiles:
		var n := 0
		for m in lay.tiles[tile]:
			n += (lay.tiles[tile][m] as LucidCity.Surf).size()
		print("city_bake: tile %s: %d vertices in %d surfaces" % [tile, n, lay.tiles[tile].size()])
		total += n
	print("city_bake: %d vertices, %d lamps, %d colliders, %d blocks, %d points, plan in %d ms" % [total, lay.lamps.size(),
			lay.colliders.size(), lay.blocks.size(), lay.points.size(), Time.get_ticks_msec() - t0])
	if "--count" in args:
		get_tree().quit(0)
		return
	for c in lay.colliders:
		if not c.occluder:
			continue
		var b := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = c.size
		cs.shape = bs
		b.add_child(cs)
		b.transform = c.xf
		b.set_meta("lucid", c.meta)
		add_child(b)
	for i in 3:
		await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	for tile in lay.tiles:
		var t1 := Time.get_ticks_msec()
		var mesh := LucidCity.bake(lay.tiles[tile], lay.lamps, STATES, space, rays, func(d: int, n: int) -> void:
			print("city_bake: %s %d / %d" % [tile, d, n]))
		mesh.set_meta("states", STATES)
		var err := ResourceSaver.save(mesh, OUT + tile + ".res", ResourceSaver.FLAG_COMPRESS)
		print("city_bake: %s baked in %.1f s -> %s (%s)" % [tile, (Time.get_ticks_msec() - t1) / 1000.0, OUT + tile + ".res", error_string(err)])
	# Probe grids: the crossing at 1.2 m over the street, A's roof.
	var t2 := Time.get_ticks_msec()
	var grids := []
	for g in [[Rect2(-90, -66, 180, 132), 4.0, 0.0, 1.2], [Rect2(15, 10, 30, 30), 3.0, lay.A_ROOF, 1.2]]:
		var data := LucidCity.bake_probes(g[0], g[1], g[2], g[3], lay.lamps, STATES, space, 24)
		grids.append({"rect": g[0], "step": g[1], "floor": g[2], "y": g[3], "data": data})
	var pr := Resource.new()
	pr.set_meta("grids", grids)
	pr.set_meta("states", STATES)
	ResourceSaver.save(pr, OUT + "probes.res", ResourceSaver.FLAG_COMPRESS)
	print("city_bake: probes in %.1f s; all done in %.1f s" % [(Time.get_ticks_msec() - t2) / 1000.0, (Time.get_ticks_msec() - t0) / 1000.0])
	get_tree().quit(0)
