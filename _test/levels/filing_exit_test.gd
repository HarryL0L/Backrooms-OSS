extends Node
# The Stacks (filing) for real, with the player's own physics:
#  1. the mechanic: standing still in Bay 1 bank B's aisle, it shuts on you
#     (the warning, the carriages pushing, the catch), in fair time;
#  2. the maze: from the arrival a walker finds its way to the exit door
#     through the moving shelving (a path on the level's walk grid, re-planned
#     as the aisles move; it walks out of any aisle that starts closing on it
#     REACT s after the warning), with every range event on: it must get there
#     within WALK_LIMIT s and never be caught;
#  3. standing on the floor where you arrive, in the corridors, in Bay 4 and
#     on the exit door's threshold; the exit door offered by the Use prompt;
#     through it, back into the Backrooms, without dropping on the way out
#     (the ride and the fade) or after you're put down. A few returns, on
#     floors 0, 1, 2, -1.
#   ... res://_test/levels/filing_exit_test.tscn [-- returns=6 walks=3]
# Prints PASS / FAIL lines and "filing_exit_test: N failed".

var game
var fails := 0
const FLOORS := [0, 1, 2, -1]
const L := preload("res://scripts/world/levels/filing_level.gd")
const LAYOUT := preload("res://scripts/world/levels/filing_layout.gd")
const REACT := 1.0
const WALK_LIMIT := 300.0


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


func _b(x: float, y: float) -> Vector3:
	return Vector3(x, SideLevel.LEVEL_Y, -y)


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var returns := int(args.get("returns", "6"))
	var walks := int(args.get("walks", "3"))
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING and not game._transition, 120.0)
	game.hud.set_fade(0.0)
	var p: Player = game.player
	var Y := SideLevel.LEVEL_Y
	# 1. The mechanic: standing still in Bay 1 bank B's aisle, it shuts on you.
	game.debug_enter_side("filing")
	if await _until(_settled, 90.0):
		var lv = game.side
		lv._events = true
		lv._first_b = false
		var bk = lv._cells["R1"].banks[1]
		var g: int = lv.open_gaps(bk)[0]
		var at: Vector2 = lv._gap_in("R1", 1, g, 3.2)
		p.teleport(_b(at.x, at.y), 0.0)
		var caught := {"t": -1.0, "warn": -1.0, "move": -1.0}
		lv.player_caught.connect(func(_l: Array, _h: Dictionary) -> void: caught.t = 1.0, CONNECT_ONE_SHOT)
		var t := 0.0
		while caught.t < 0.0 and t < 25.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			if caught.warn < 0.0 and bk.state == 1:
				caught.warn = t
			if caught.move < 0.0 and bk.state == 2:
				caught.move = t
		check(caught.t > 0.0, "standing in an aisle: caught (warning at %.1f s, moving at %.1f s, caught by %.1f s)" % [
				caught.warn, caught.move, t])
		check(caught.warn > 0.0 and t - caught.warn > 3.0, "the warning came %.1f s before the catch (fair: > 3 s)" % (t - caught.warn))
		await _until(func() -> bool: return not game._in_side and not game._transition, 60.0)
	# 2. The maze, walked.
	for w in walks:
		game.debug_enter_side("filing")
		if not await _until(_settled, 90.0):
			check(false, "walk %d: into the Stacks" % w)
			continue
		var lv = game.side
		if w > 0:
			lv.sim_reset(4000 + w * 131)          # (another layout of the shelving each walk)
		lv.sim = false
		lv._events = true
		var r: Dictionary = await _walk_maze(lv, p)
		check(r.ok, "walk %d: from the arrival to the exit door through the maze in %.0f s (limit %.0f), %.0f m walked, %d closes on the floor, %d warnings walked out of, caught %s" % [
				w, r.t, WALK_LIMIT, r.dist, r.closes, r.escapes, r.caught])
		if game._in_side:
			await _use_exit(p, w, -1)
		await _until(func() -> bool: return not game._in_side and not game._transition, 60.0)
	# 3. Standing everywhere, the exit, the returns.
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
			await _stand(p, _b(5.8, 8.43), PI * 0.5, "Bay 1 main aisle")
			await _stand(p, _b(10.65, 16.96), 0.0, "Bay 1 door threshold")
			await _stand(p, _b(-3.6, 17.98), -PI * 0.5, "corridor A dead end")
			await _stand(p, _b(18.55, 18.99), 0.0, "fire door threshold onto Bay 4")
			await _stand(p, _b(15.4, 12.0), 0.0, "sorting")
			await _stand(p, _b(36.14, 3.0), 0.0, "corridor B dead end")
			await _stand(p, _b(35.12, 8.43), -PI * 0.5, "Bay 3 / corridor B threshold")
			await _stand(p, _b(0.95, 24.0), 0.0, "Bay 2 main aisle")
			await _stand(p, _b(12.0, 28.64), -PI * 0.5, "Bay 2 rear aisle by Bay 4's door")
			await _stand(p, _b(20.0, 28.64), -PI * 0.5, "Bay 4 main aisle")
			var ex: Array = LAYOUT.DATA.exit
			await _stand(p, _b(ex[0], ex[1] - 0.25), 0.0, "exit door threshold")
		await _use_exit(p, i, fl)
	print("filing_exit_test: %d failed" % fails)
	game.queue_free()
	for k in 4:
		await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)


## Up to the exit door, Use it, ride out, land in the Backrooms.
func _use_exit(p: Player, i: int, fl: int) -> void:
	var ex: Array = LAYOUT.DATA.exit
	p.teleport(_b(ex[0], ex[1] - 0.8), 0.0, -0.65)
	await get_tree().create_timer(0.5).timeout
	game._update_use()
	var tgt: Array = game._use_target
	if tgt.is_empty() or tgt[2] != "Open the exit door":
		check(false, "return %d: the exit door offers %s" % [i, tgt])
		return
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
	if fl >= -1:
		check(not fell, "return %d floor %d: back in the Backrooms at (%.1f, %.2f, %.1f), lowest %.2f, resets %d, on floor %s" % [
			i, fl, put.x, put.y, put.z, low, resets, p.is_on_floor()])


## The slot a closing bank is closing (Blender rect).
func _closing_slot(lv, bk) -> Rect2:
	var w: Vector2 = lv._gap(bk, bk.close_gap)
	return lv._rect_b(bk.cell, (w.x + w.y) * 0.5, (bk.z0 + bk.z1) * 0.5, maxf(w.y - w.x, 0.0), bk.L)


## Walks from the arrival to the exit door with the player's physics: a path
## on the walk grid to the exit (aisles that are closing left out), the view
## turned toward a point a metre down it; out of an aisle that closes on you.
func _walk_maze(lv, p: Player) -> Dictionary:
	var arr: Transform3D = lv.arrival()
	p.teleport(arr.origin, SideLevel._yaw_of(arr))
	p.controls_enabled = true
	RenderingServer.render_loop_enabled = false
	var caught := {"c": false}
	var cb := func(_l: Array, _h: Dictionary) -> void: caught.c = true
	lv.player_caught.connect(cb)
	var size: Vector2i = lv.grid_size()
	var gw := size.x
	var exit_b := Vector2(LAYOUT.DATA.exit[0], LAYOUT.DATA.exit[1])
	var t := 0.0
	var plan_t := -10.0
	var field := PackedInt32Array()
	var free := PackedByteArray()
	var mode := "go"
	var last := p.global_position
	var dist := 0.0
	var stuck_t := 0.0
	var escapes := 0
	var flee_ev := -1
	var ok := false
	var ev0: int = lv.events_log.size()
	Input.action_press("move_forward")
	while t < WALK_LIMIT and not caught.c and game._in_side:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		var pp := p.global_position
		var bp := Vector2(pp.x, -pp.z)
		dist += Vector2(pp.x - last.x, pp.z - last.z).length()
		stuck_t = stuck_t + dt if Vector2(pp.x - last.x, pp.z - last.z).length() < 0.4 * dt else 0.0
		last = pp
		if OS.get_environment("TRACE") != "" and int(t / 5.0) != int((t - dt) / 5.0):
			var cg: int = lv.grid_index(bp)
			print("TRACE t %.0f at (%.2f, %.2f) cell %s mode %s field %d" % [t, bp.x, bp.y, lv._cur.id, mode,
					field[cg] if cg >= 0 and cg < field.size() else -9])
		if bp.distance_to(exit_b) < 1.5:
			ok = true            # (at the door: the Use prompt reaches it from here)
			break
		# danger: an aisle closing with you in it
		var danger := -1
		for b in lv.banks():
			if (b.state == 1 or b.state == 2) and b.log_i >= 0 and _closing_slot(lv, b).grow(0.1).has_point(bp):
				danger = b.log_i
		if danger >= 0 and danger != flee_ev and lv._t - float(lv.events_log[danger].t0) < REACT:
			Input.action_release("move_forward")       # (a moment to take it in)
			continue
		if danger >= 0 and danger != flee_ev:
			flee_ev = danger
			escapes += 1
			mode = "flee"
			plan_t = -10.0          # (planned once: the way out as it is when you start out)
		if danger < 0 and mode == "flee":
			mode = "go"
			plan_t = -10.0
		if t - plan_t > 0.4 and not (mode == "flee" and plan_t > 0.0):
			plan_t = t
			free = lv.grid_free()
			if mode == "flee":
				var bk = lv.banks()[int(lv.events_log[flee_ev].b)]
				var own: Rect2 = lv.bank_rect(bk)
				var esc := PackedInt32Array()
				for i in free.size():
					if free[i] == 1 and not own.grow(0.2).has_point(lv.grid_pos(i)):
						esc.append(i)
				field = lv.grid_bfs(free, esc)
			else:
				var f := free.duplicate()
				for b in lv.banks():
					if b.state == 1 or b.state == 2:
						var sl := _closing_slot(lv, b).grow(0.3)
						for i in f.size():
							if f[i] == 1 and sl.has_point(lv.grid_pos(i)):
								f[i] = 0
				field = lv.grid_bfs(f, lv.grid_exit(f))
		var cur: int = lv.grid_index(bp)
		# the nearest cell of the field if this one isn't on it
		if cur < 0 or field[cur] < 0:
			var best := -1
			for dy in range(-3, 4):
				for dx in range(-3, 4):
					var j: int = lv.grid_index(bp + Vector2(dx, dy) * L.GRID)
					if j >= 0 and field[j] >= 0 and (best < 0 or field[j] < field[best]):
						best = j
			cur = best
		if cur < 0:
			Input.action_release("move_forward")       # nowhere to go yet: wait
			continue
		# a point a metre or so down the path
		var aim := cur
		for k in 5:
			var nb := aim
			for n in [aim - 1, aim + 1, aim - gw, aim + gw]:
				if n >= 0 and n < field.size() and field[n] >= 0 and field[n] < field[nb]:
					nb = n
			aim = nb
		if aim == cur and field[cur] > 0:
			Input.action_release("move_forward")       # blocked for now: wait
			continue
		var to: Vector2 = lv.grid_pos(aim)
		if stuck_t > 1.5:
			to = lv.grid_pos(cur)                       # stuck on an edge: back to the cell's centre
		var d := to - bp
		Input.action_press("move_forward")
		p.yaw = lerp_angle(p.yaw, atan2(-d.x, d.y), 0.35)
		p._apply_rotation()
	Input.action_release("move_forward")
	RenderingServer.render_loop_enabled = true
	if lv.player_caught.is_connected(cb):
		lv.player_caught.disconnect(cb)
	return {"ok": ok and not caught.c, "t": t, "dist": dist, "closes": lv.events_log.size() - ev0, "escapes": escapes,
			"caught": caught.c}
