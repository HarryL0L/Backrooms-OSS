extends Node
# Out of the Dimming Floor through its stair door ("Take the stairs"), over
# and over: each return lands somewhere else in the Backrooms, and you must
# land on your feet there, not fall. Arrives once through the Crawlspace
# chain, the rest straight in; on floors 0, 1, 2 and -1. Every frame for
# ~10 s after each return logs where you are, how fast you're going, on the
# floor or not, the side flags and the game's state (to user://levels/fall).
# A return fails if you drop more than 0.6 m going through the door (the
# fade out), or if you drop more than 0.6 m below where you were put, end
# up off the floor, or the fall reset catches you.
#   ... res://_test/levels/side_exit_fall_test.tscn [-- returns=30]
# Prints PASS / FAIL lines and "side_exit_fall_test: N failed".

var game
var fails := 0
var out := OS.get_user_data_dir() + "/levels/fall"
var log_file: FileAccess
const FLOORS := [0, 1, 2, -1]


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > limit:
			return false
	return true


func _settled(id: String) -> bool:
	return game._in_side and not game._transition and game.side_id == id


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	log_file = FileAccess.open(out + "/log.txt", FileAccess.WRITE)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _log(s: String) -> void:
	log_file.store_line(s)


func _frame_line(t: float) -> String:
	var p: Player = game.player
	var c: Vector2i = game.gen.cell_of(p.global_position)
	return "t=%5.2f pos=(%.2f,%.2f,%.2f) vel=(%.2f,%.2f,%.2f) floor=%s phys=%s state=%d trans=%s side=%s side_mode=%s safe_y=%.2f busy=%s col_off=%s crawl=%s biome=%d" % [
		t, p.global_position.x, p.global_position.y, p.global_position.z, p.velocity.x, p.velocity.y, p.velocity.z,
		p.is_on_floor(), p.is_physics_processing(), game.state, game._transition, game._in_side, p.side_mode,
		p.get("_safe_pos").y, p.busy(), p.get("_col").disabled, p.force_crawl, game.gen.biome_at(c.x, c.y)]


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var returns := int(args.get("returns", "30"))
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING and not game._transition, 120.0)
	game.hud.set_fade(0.0)
	var p: Player = game.player
	var falls := 0
	for i in returns:
		var fl: int = FLOORS[(i / 2) % FLOORS.size()]
		if i == 0:
			game.debug_enter_side("crawlspace")
			await _until(_settled.bind("crawlspace"), 60.0)
			game.side.exit_entered.emit("office")
		else:
			game.debug_enter_side("office")
		if not await _until(_settled.bind("office"), 90.0):
			check(false, "return %d: into the office" % i)
			continue
		# Walked the stairs to floor `fl` before coming in.
		if fl != game._floor:
			game._floor = fl
			game.stairs.clear()
			game._use_gen(WorldGen.new(game.gen.seed_value, fl), false)
			for n in game._backrooms_nodes():
				n.visible = false
				n.process_mode = Node.PROCESS_MODE_DISABLED
		if i == 0:
			# The landing behind the stair door holds you up.
			p.teleport(Vector3(-1.2, SideLevel.LEVEL_Y + 0.05, -15.2), PI * 0.5)
			await get_tree().create_timer(0.6).timeout
			check(p.is_on_floor() and p.global_position.y > SideLevel.LEVEL_Y - 0.1,
					"standing on the stair landing (y %.2f)" % (p.global_position.y - SideLevel.LEVEL_Y))
		# Up to the stair door and Use it, like the player.
		p.teleport(Vector3(0.9, SideLevel.LEVEL_Y, -15.65), PI * 0.5, -0.75)
		await get_tree().create_timer(0.5).timeout
		game._update_use()
		var tgt: Array = game._use_target
		if tgt.is_empty() or tgt[2] != "Take the stairs":
			check(false, "return %d: the stair door offers %s" % [i, tgt])
			continue
		game._use()
		_log("=== return %d (floor %d)" % [i, fl])
		var t := 0.0
		var door_y := p.global_position.y
		var low_out := INF
		while game._in_side:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			low_out = minf(low_out, p.global_position.y)
			_log(_frame_line(t) + " [leaving]")
		# Loading: until physics is back.
		var put := Vector3.INF
		while not p.is_physics_processing() or game.state != game.State.PLAYING:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if put == Vector3.INF and game.state == game.State.LOADING:
				put = p.global_position
			if int(t * 60.0) % 10 == 0:
				_log(_frame_line(t) + " [loading]")
			if t > 120.0:
				break
		if put == Vector3.INF:
			put = p.global_position
		var low := INF
		var resets := 0
		var last_y := p.global_position.y
		var shot := false
		var t0 := t
		var lines := []
		while t - t0 < 10.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var y := p.global_position.y
			if y - last_y > 3.0:
				resets += 1
			last_y = y
			low = minf(low, y)
			lines.append(_frame_line(t))
			_log(lines[-1])
			if not shot and t - t0 > 0.3:
				shot = true
				game.hud.set_fade(0.0)
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(out + "/return_%02d.png" % i)
		var c: Vector2i = game.gen.cell_of(put)
		# (through the door the ride lowers your eye a little; more is a fall)
		var fell_out := low_out < door_y - 0.6
		check(not fell_out, "return %d: through the stair door, lowest %.2f m below the door's floor" % [i, door_y - low_out])
		var fell := low < put.y - 0.6 or resets > 0 or not p.is_on_floor()
		if fell or fell_out:
			falls += 1
			print("  first frames of return %d:" % i)
			for k in mini(lines.size(), 40):
				if k % 4 == 0:
					print("   ", lines[k])
		check(not fell, "return %d floor %d: put at (%.1f, %.2f, %.1f) cell %s biome %d, lowest y %.2f, resets %d, on floor %s" % [
			i, fl, put.x, put.y, put.z, c, game.gen.biome_at(c.x, c.y), low, resets, p.is_on_floor()])
	print("falls: %d of %d" % [falls, returns])
	print("side_exit_fall_test: %d failed" % fails)
	log_file.close()
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)
