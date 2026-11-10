extends Node
# The Stacks (filing) for real: in, standing on the floor where you arrive,
# in the rear aisle and on the exit door's threshold; the exit door offered
# by the Use prompt where you look at it; through it, back into the
# Backrooms, without dropping on the way out (the ride and the fade) or
# after you're put down. A few returns, on floors 0, 1, 2, -1.
#   ... res://_test/levels/filing_exit_test.tscn [-- returns=6]
# Prints PASS / FAIL lines and "filing_exit_test: N failed".

var game
var fails := 0
const FLOORS := [0, 1, 2, -1]
const L := preload("res://scripts/world/levels/filing_level.gd")


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


func _settled() -> bool:
	return game._in_side and not game._transition and game.side_id == "filing"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _stand(p: Player, at: Vector3, yaw: float, what: String) -> void:
	p.teleport(at + Vector3(0, 0.05, 0), yaw)
	await get_tree().create_timer(0.7).timeout
	var dy := p.global_position.y - at.y
	check(p.is_on_floor() and absf(dy) < 0.12, "%s: on the floor (y %+.2f)" % [what, dy])


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var returns := int(args.get("returns", "6"))
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING and not game._transition, 120.0)
	game.hud.set_fade(0.0)
	var p: Player = game.player
	var Y := SideLevel.LEVEL_Y
	# The mechanic: standing still in bank B's aisle, it shuts on you (the
	# warning, the carriages pushing, the catch), in fair time.
	game.debug_enter_side("filing")
	if await _until(_settled, 90.0):
		var lv = game.side
		lv._events = true
		lv._first_b = false
		var mid: float = lv._gap_mid(1, lv._aisle[1])
		p.teleport(Vector3(mid, Y, -(L.BANK_Y[1] + 3.2)), 0.0)
		var caught := {"t": -1.0, "warn": -1.0, "move": -1.0}
		lv.player_caught.connect(func(_l: Array, _h: Dictionary) -> void: caught.t = 1.0, CONNECT_ONE_SHOT)
		var t := 0.0
		while caught.t < 0.0 and t < 20.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if caught.warn < 0.0 and lv._state[1] == 1:
				caught.warn = t
			if caught.move < 0.0 and lv._state[1] == 2:
				caught.move = t
		check(caught.t > 0.0, "standing in an aisle: caught (warning at %.1f s, moving at %.1f s, caught by %.1f s)" % [
				caught.warn, caught.move, t])
		check(caught.warn > 0.0 and t - caught.warn > 3.0, "the warning came %.1f s before the catch (fair: > 3 s)" % (t - caught.warn))
		await _until(func() -> bool: return not game._in_side and not game._transition, 60.0)
	for i in returns:
		var fl: int = FLOORS[(i / 2) % FLOORS.size()]
		game.debug_enter_side("filing")
		if not await _until(_settled, 90.0):
			check(false, "return %d: into the Stacks" % i)
			continue
		check(game.side.get_script() == L, "return %d: the Stacks' own level (not the placeholder)" % i)
		var lv = game.side
		lv._events = false             # (no range shuts on the test)
		if fl != game._floor:
			game._floor = fl
			game.stairs.clear()
			game._use_gen(WorldGen.new(game.gen.seed_value, fl), false)
			for n in game._backrooms_nodes():
				n.visible = false
				n.process_mode = Node.PROCESS_MODE_DISABLED
		if i == 0:
			var arr: Transform3D = lv.arrival()
			await _stand(p, arr.origin, SideLevel._yaw_of(arr), "arrival")
			await _stand(p, Vector3(5.8, Y, -L.MAIN_Y), PI * 0.5, "main aisle")
			await _stand(p, Vector3(3.0, Y, -(L.ROOM_D - 0.5)), -PI * 0.5, "north rear aisle")
			await _stand(p, Vector3(L.EXIT_X, Y, -(L.ROOM_D - 0.25)), 0.0, "exit door threshold")
		# Up to the exit door and Use it.
		p.teleport(Vector3(L.EXIT_X, Y, -(L.ROOM_D - 0.8)), 0.0, -0.65)
		await get_tree().create_timer(0.5).timeout
		game._update_use()
		var tgt: Array = game._use_target
		if tgt.is_empty() or tgt[2] != "Open the exit door":
			check(false, "return %d: the exit door offers %s" % [i, tgt])
			continue
		game._use()
		var door_y := p.global_position.y
		var low_out := INF
		var t := 0.0
		while game._in_side:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			low_out = minf(low_out, p.global_position.y)
			if t > 30.0:
				break
		check(low_out > door_y - 0.6, "return %d: through the exit door, lowest %.2f m below the door's floor" % [i, door_y - low_out])
		var put := Vector3.INF
		while not p.is_physics_processing() or game.state != game.State.PLAYING:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if put == Vector3.INF and game.state == game.State.LOADING:
				put = p.global_position
			if t > 120.0:
				break
		if put == Vector3.INF:
			put = p.global_position
		var low := INF
		var resets := 0
		var last_y := p.global_position.y
		var t0 := t
		while t - t0 < 6.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			var y := p.global_position.y
			if y - last_y > 3.0:
				resets += 1
			last_y = y
			low = minf(low, y)
		var fell := low < put.y - 0.6 or resets > 0 or not p.is_on_floor()
		check(not fell, "return %d floor %d: back in the Backrooms at (%.1f, %.2f, %.1f), lowest %.2f, resets %d, on floor %s" % [
			i, fl, put.x, put.y, put.z, low, resets, p.is_on_floor()])
	print("filing_exit_test: %d failed" % fails)
	game.queue_free()
	for k in 4:
		await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)
