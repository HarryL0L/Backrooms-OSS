extends Node
# Experimental path-traced Lobby lighting: screenshots and timings.
#
#   G=/tmp/claude-0/godot/Godot_v4.7-stable_linux.x86_64
#   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a $G --path . \
#       --rendering-method mobile --rendering-driver vulkan --resolution 1280x720 res://_test/pt_test.tscn [-- --quality N] [--view corridor]
#
# Boots the game (seed 1234), finds a few Lobby views (the spawn hall, a
# walled corridor with a light, an open hall with pillars) and for each saves
# user://pt/<view>_<what>.png: "off" (baked lighting), "raw" (one traced
# frame, no accumulation or filter), "noisy" (the first frame with the filter),
# "conv" (after 2 s standing still), "turn_slow" / "turn_fast" (while turning
# at 30 and 180 degrees a second). Prints the tracer's GPU time.

var game
var out := OS.get_user_data_dir() + "/pt"
var quality := 0
var only := ""
var errors := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--quality" and i + 1 < args.size():
			quality = int(args[i + 1])
		if args[i] == "--view" and i + 1 < args.size():
			only = args[i + 1]
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _frames(n: int) -> void:
	for i in n:
		await RenderingServer.frame_post_draw


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > limit:
			return false
	return true


func _shot(name_: String) -> void:
	await RenderingServer.frame_post_draw
	var path := "%s/%s.png" % [out, name_]
	get_viewport().get_texture().get_image().save_png(path)
	var e: PathTraceEffect = game.path_tracer.effect
	print("shot %-22s fps %5.1f  pt active %s  pt gpu %.2f ms -> %s" % [name_, Engine.get_frames_per_second(),
			game.path_tracer.active, e.gpu_ms if e else -1.0, path])


## Prints how many traced texels saw each kind of face, and their mean light.
func _dump(e: PathTraceEffect) -> void:
	var rd := RenderingServer.get_rendering_device()
	var b := rd.texture_get_data(e._out, 0)
	var cnt := {}
	var lum := {}
	for i in range(0, b.size(), 16):
		var a := b.decode_float(i + 12)
		var nid := int(floor(a / 1000.0)) if a > 0.0 else -1
		cnt[nid] = cnt.get(nid, 0) + 1
		lum[nid] = lum.get(nid, 0.0) + b.decode_float(i) + b.decode_float(i + 4) + b.decode_float(i + 8)
	for k in cnt:
		print("pt_test: face %d: %d texels, mean light %.3f" % [k, cnt[k], lum[k] / cnt[k] / 3.0])


func _look(p: Vector3, yaw: float, pitch := 0.0) -> void:
	game.player.teleport(p, yaw, pitch)


func _set_pt(on: bool) -> void:
	Settings.set_value("graphics/path_traced", on)


## Lobby views near the spawn: [name, position, yaw].
func _views() -> Array:
	var g: WorldGen = game.gen
	var views := [["spawn", game.player.global_position, game.player.yaw]]
	var corridor := []
	var hall := []
	var sc: Vector2i = g.spawn_cell
	for r in range(3, 40):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := sc + Vector2i(dx, dz)
				if g.biome_at(c.x, c.y) != WorldGen.LOBBY or g.stair_zone(c.x, c.y, 2):
					continue
				# A corridor along z: walls both sides for four cells, a light ahead.
				if corridor.is_empty():
					var ok := true
					for k in 4:
						var e: Array = g._cell_edges(c.x, c.y + k)
						if e[0] != WorldGen.E_WALL or e[1] != WorldGen.E_WALL:
							ok = false
							break
					if ok and g.light_state(c.x, c.y + 2, WorldGen.LOBBY) == WorldGen.L_ON:
						corridor = ["corridor", Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.2) * 2.4), PI]
				if hall.is_empty() and g.pillar_at(c.x, c.y, WorldGen.LOBBY) > 0.0 and g.pillar_at(c.x + 2, c.y, WorldGen.LOBBY) > 0.0 \
						and g.light_state(c.x, c.y, WorldGen.LOBBY) == WorldGen.L_ON:
					hall = ["hall", Vector3((c.x - 1.5) * 2.4, 0.05, (c.y + 0.5) * 2.4), -PI * 0.5]
		if not corridor.is_empty() and not hall.is_empty():
			break
	if not corridor.is_empty():
		views.append(corridor)
	if not hall.is_empty():
		views.append(hall)
	return views


func _run() -> void:
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	Settings.set_value("graphics/pt_quality", quality)
	_set_pt(false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING, 120.0)
	game.hud.set_fade(0.0)
	game.hud._title_t = 0.001
	await _wait(3.0)
	print("pt_test: renderer %s, supported %s, quality %d" % [RenderingServer.get_current_rendering_method(), PathTracer.supported(), quality])
	var views := _views()
	for v in views:
		print("pt_test: view ", v)
	for v in views:
		var nm: String = v[0]
		if only != "" and nm != only:
			continue
		_set_pt(false)
		_look(v[1], v[2])
		await _until(func() -> bool: return game.chunks.is_area_ready(game.player.global_position, 1), 30.0)
		await _wait(1.5)
		await _shot(nm + "_off")
		# Raw: one sample, no history, no filter.
		_set_pt(true)
		await _until(func() -> bool: return game.path_tracer.active, 10.0)
		var e: PathTraceEffect = game.path_tracer.effect
		if e == null or e.failed:
			print("pt_test: FAIL tracer unavailable")
			break
		e.max_history = 1.0
		e.filter_strength = 0.0
		await _frames(3)
		await _shot(nm + "_raw")
		e.max_history = 48.0
		e.filter_strength = 1.0
		e.reset()
		await _frames(1)
		await _shot(nm + "_noisy")
		var ms := 0.0
		var n := 0
		# ~2 s at 60 FPS (lavapipe draws a few frames a second: count frames).
		for f in 120:
			await RenderingServer.frame_post_draw
			if e.gpu_ms > 0.0:
				ms += e.gpu_ms
				n += 1
		print("pt_test: %s pt gpu avg %.2f ms over %d frames (lavapipe)" % [nm, ms / maxi(n, 1), n])
		await _shot(nm + "_conv")
		_dump(e)
		# Turning slowly, then fast (degrees a second at 60 FPS, frame by frame).
		for spd in [[30.0, "turn_slow"], [180.0, "turn_fast"]]:
			var yaw0: float = game.player.yaw
			for f in 30:
				await RenderingServer.frame_post_draw
				game.player.yaw += deg_to_rad(spd[0]) / 60.0
				game.player._apply_rotation()
			await _shot(nm + "_" + spd[1])
			game.player.yaw = yaw0
			game.player._apply_rotation()
			await _wait(1.0)
	_set_pt(false)
	print("pt_test: done")
	get_tree().quit()
