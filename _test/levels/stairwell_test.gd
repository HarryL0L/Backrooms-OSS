extends Node
# The Endless Stairwell (stairwell) for real, with the player's own physics:
#  1. from the Stacks: through STAIR 2 at the far end of corridor B (the Use
#     prompt), into the stairwell, arriving on B2 by its door, on the floor;
#  2. the descent: a walker (the real controls, steering along the stair)
#     goes down DOWN storeys and up UP: every physics frame on the floor
#     (never more than AIR_MAX frames off it over an edge), never falling,
#     the floor counter (storey()) matching the landings walked, and where
#     you are along the stair and the camera continuous across every recycle
#     of the stack (no pop: after each shift, position and camera differ from
#     the frame before by a step, once the shift's floor height is taken
#     off), the stack recycled at every storey;
#  3. on down to the bottom: the stair runs into the water, and wading into
#     it takes you on into the flooded basement (NEXT); the whole way down
#     from B2 timed at a walk;
#  4. a landing door: locked; B2's door: back out into the Backrooms, landing
#     on your feet;
#  5. from the Backrooms: the STAIRS door on the garage level (floor -1),
#     through the Use prompt, arriving on B2 the same way.
#   ... res://_test/levels/stairwell_test.tscn [-- down=10 up=3 bottom=1]
# Prints PASS / FAIL lines and "stairwell_test: N failed".

const L := preload("res://scripts/world/levels/stairwell_level.gd")
const AIR_MAX := 3
const STEP_MAX := 0.15

var game
var fails := 0


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
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _run() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.split("=")
		if kv.size() == 2:
			args[kv[0]] = kv[1]
	var down := int(args.get("down", "10"))
	var up := int(args.get("up", "3"))
	var bottom: bool = args.get("bottom", "1") == "1"
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING and not game._transition, 120.0)
	game.hud.set_fade(0.0)
	var p: Player = game.player

	# 1. From the Stacks, through STAIR 2.
	game.debug_enter_side("filing")
	if await _until(func() -> bool: return _settled("filing"), 90.0):
		var st: LevelEntrance = null
		for n in game.side.find_children("*", "LevelEntrance", true, false):
			if (n as LevelEntrance).dest == "stairwell":
				st = n
		check(st != null, "the Stacks have STAIR 2 (an exit to the stairwell)")
		if st:
			game.side._events = false
			var bz := st.global_basis.z
			p.teleport(st.global_position + bz * 0.9 + Vector3(0, 0.05, 0), atan2(bz.x, bz.z), -0.2)
			await get_tree().create_timer(0.6).timeout
			_face(p, st)
			game._update_use()
			var tgt: Array = game._use_target
			check(not tgt.is_empty() and tgt[0] == st, "STAIR 2 offers: %s" % [tgt[2] if not tgt.is_empty() else "nothing"])
			game._use()
			check(await _until(func() -> bool: return _settled("stairwell"), 90.0), "through STAIR 2 into the stairwell")
	else:
		check(false, "into the Stacks")
	if not _settled("stairwell"):
		game.debug_enter_side("stairwell")
		await _until(func() -> bool: return _settled("stairwell"), 90.0)
	await _arrived("from the Stacks")

	# 2. Down, and up some.
	var lv = game.side
	lv._events = false
	p.controls_enabled = true
	RenderingServer.render_loop_enabled = false
	var r: Dictionary = await _walk(lv, p, 1, down, 60.0 + down * 12.0)
	check(r.ok and lv.storey() == L.TOP + down, "down %d storeys in %.1f s (%.1f s a storey): storey() %d (expected %d), %d recycles" % [
			down, r.t, r.t / maxf(down, 1), lv.storey(), L.TOP + down, r.rebases])
	_report(r, "going down")
	r = await _walk(lv, p, -1, up, 60.0 + up * 14.0)
	check(r.ok and lv.storey() == L.TOP + down - up, "up %d storeys in %.1f s: storey() %d (expected %d), %d recycles" % [
			up, r.t, lv.storey(), L.TOP + down - up, r.rebases])
	_report(r, "going up")

	# 3. On down to the water.
	if bottom:
		var left: int = L.BOTTOM - lv.storey()
		r = await _walk(lv, p, 1, left + 2, 90.0 + left * 12.0, true)
		check(r.flooded, "the stair runs into the water at the bottom (B%d by the count); into it: on into the flooded basement (%s)" % [
				L.BOTTOM, game.side_id])
		_report(r, "down to the bottom")
		var per: float = r.t / maxf(left, 1)
		print("descent: B2 to the water, %d storeys, at %.2f s a storey: %.0f s at a walk" % [L.BOTTOM - L.TOP, per,
				per * (L.BOTTOM - L.TOP)])
		check(per * (L.BOTTOM - L.TOP) > 150.0 and per * (L.BOTTOM - L.TOP) < 420.0,
				"a believable descent: %.0f s from B2 to the water (2.5 to 7 min)" % (per * (L.BOTTOM - L.TOP)))
	RenderingServer.render_loop_enabled = true
	Input.action_release("move_forward")

	# 4. A landing door; B2's door, out.
	await _until(func() -> bool: return not game._transition, 60.0)
	game.debug_enter_side("stairwell")
	if not await _until(func() -> bool: return _settled("stairwell"), 90.0):
		check(false, "back into the stairwell")
		_finish()
		return
	lv = game.side
	lv.goto_storey(5)
	await get_tree().create_timer(0.5).timeout
	var du = null
	for s in lv._slots:
		if s.j == 0:
			du = s.door_use
	var said: String = du.use("door", p) if du else ""
	check(said.begins_with("Locked"), "a landing door (B5): \"%s\"" % said)
	lv.goto_storey(L.TOP, Vector3(L.DOOR_X, 0.8, 0.0), PI)
	await get_tree().create_timer(0.6).timeout
	_face(p, lv._exit_b2)
	game._update_use()
	var tg: Array = game._use_target
	check(not tg.is_empty() and tg[0] == lv._exit_b2, "B2's door offers: %s" % [tg[2] if not tg.is_empty() else "nothing"])
	if not tg.is_empty():
		var y0 := p.global_position.y
		var low := INF
		game._use()
		var t := 0.0
		while game._in_side and t < 30.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			low = minf(low, p.global_position.y)
		check(not game._in_side and low > y0 - 0.6, "through B2's door, back to the Backrooms (lowest %.2f m below the landing)" % (y0 - low))
		await _until(func() -> bool: return game.state == game.State.PLAYING and not game._transition and p.is_physics_processing(), 120.0)
		var put := p.global_position
		var lo := INF
		t = 0.0
		while t < 5.0:
			await get_tree().physics_frame
			t += get_physics_process_delta_time()
			lo = minf(lo, p.global_position.y)
		check(lo > put.y - 0.6 and p.is_on_floor(), "back in the Backrooms on your feet at %s (lowest %.2f)" % [put, put.y - lo])

	# 5. From the Backrooms: the garage level's STAIRS door.
	await _from_backrooms(p)
	_finish()


func _finish() -> void:
	print("stairwell_test: %d failed" % fails)
	game.queue_free()
	for k in 4:
		await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)


## Looks straight at what a usable offers (its Use point).
func _face(p: Player, n: Node) -> void:
	var tg: Array = n.use_targets(p)
	if tg.is_empty():
		return
	var d: Vector3 = (tg[0][1] as Vector3) - p.camera.global_position
	p.yaw = atan2(-d.x, -d.z)
	p.pitch = atan2(d.y, Vector2(d.x, d.z).length())
	p._apply_rotation()


## Arrived on B2: the storey, the place, on the floor, its number.
func _arrived(how: String) -> void:
	var lv = game.side
	var p: Player = game.player
	check(lv.get_script() == L, "%s: the stairwell's own level (not the placeholder)" % how)
	await get_tree().create_timer(1.0).timeout
	var arr: Transform3D = lv.arrival()
	var d := Vector2(p.global_position.x - arr.origin.x, p.global_position.z - arr.origin.z).length()
	var txt := ""
	for s in lv._slots:
		if s.j == 0:
			txt = s.text
	check(lv.storey() == L.TOP and txt == "B2" and d < 0.4 and p.is_on_floor() and absf(p.global_position.y - arr.origin.y) < 0.1,
			"%s: on B2 (\"%s\") by its door, %.2f m from the arrival, on the floor %s" % [how, txt, d, p.is_on_floor()])


func _report(r: Dictionary, what: String) -> void:
	check(r.air_max <= AIR_MAX and r.vy_min > -3.0 and r.resets == 0,
			"%s: never off the floor for more than %d frames (longest %d), never falling (lowest vertical speed %.2f m/s), no fall resets (%d)" % [
			what, AIR_MAX, r.air_max, r.vy_min, r.resets])
	check(r.jump_max < STEP_MAX and r.cam_max < STEP_MAX,
			"%s: no seam: across %d recycles the largest frame-to-frame move, the shift taken off, was %.3f m (body) / %.3f m (camera)" % [
			what, r.rebases, r.jump_max, r.cam_max])
	check(r.landings_ok, "%s: the floor counter matched every landing (%s)" % [what, r.counts])


## Walks `storeys` storeys down (dir 1) or up (-1) with the real controls.
func _walk(lv, p: Player, dir: int, storeys: int, limit: float, to_water := false) -> Dictionary:
	var out := {"ok": false, "t": 0.0, "air_max": 0, "vy_min": 0.0, "resets": 0, "jump_max": 0.0, "cam_max": 0.0,
			"rebases": 0, "landings_ok": true, "counts": "", "flooded": false}
	var start: int = lv.storey()
	var goal: int = start + dir * storeys
	var air := 0
	var last_b: int = lv.storey()
	var last_p := p.global_position
	var last_c := p.camera.global_position
	var stuck := 0.0
	var t := 0.0
	var visited: Array = [start]
	Input.action_press("move_forward")
	while t < limit:
		await get_tree().physics_frame
		var dt := get_physics_process_delta_time()
		t += dt
		if not game._in_side or game.side != lv:
			out.flooded = game.side_id == "flooded"
			break
		var b: int = lv.storey()
		var pp := p.global_position
		var cp := p.camera.global_position
		var sh: float = (b - last_b) * L.H
		var mv := (pp - last_p - Vector3(0, sh, 0)).length()
		var mc := (cp - last_c - Vector3(0, sh, 0)).length()
		out.jump_max = maxf(out.jump_max, mv)
		out.cam_max = maxf(out.cam_max, mc)
		if absf(sh) > 0.0:
			visited.append(b)
			out.rebases += 1
		if mv > 1.0:
			out.resets += 1
		air = 0 if p.is_on_floor() else air + 1
		out.air_max = maxi(out.air_max, air)
		if not (to_water and p.in_water()):
			out.vy_min = minf(out.vy_min, p.velocity.y)
		stuck = stuck + dt if Vector2(pp.x - last_p.x, pp.z - last_p.z).length() < 0.2 * dt else 0.0
		last_b = b
		last_p = pp
		last_c = cp
		if stuck > 4.0:
			print("stuck at %s storey %d" % [pp, b])
			break
		if not to_water and lv.storey() == goal:
			# on to the landing (the shift comes half a storey early)
			var u: float = lv._u_of(pp)
			if (dir > 0 and u >= goal - 0.02) or (dir < 0 and u <= goal + 0.02):
				out.ok = true
				break
		var to: Vector3 = lv.walk_target(dir) - pp
		p.yaw = lerp_angle(p.yaw, atan2(-to.x, -to.z), 0.25)
		p._apply_rotation()
	Input.action_release("move_forward")
	await get_tree().create_timer(0.3).timeout
	out.t = t
	# the counter went one storey at a time, in order
	for i in range(1, visited.size()):
		if int(visited[i]) - int(visited[i - 1]) != dir:
			out.landings_ok = false
	out.counts = "%s" % [visited] if visited.size() <= 12 else "%d .. %d, %d steps" % [visited[0], visited[-1], visited.size() - 1]
	return out


## The STAIRS door on the garage level (floor -1), used like a player would.
func _from_backrooms(p: Player) -> void:
	game._floor = -1
	game.stairs.clear()
	game._use_gen(WorldGen.new(game.gen.seed_value, -1), false)
	var spot: Dictionary = LevelEntrances.find(game.gen, "stairwell", p.global_position, 24)
	check(not spot.is_empty(), "a STAIRS door on the garage level near you: %s" % [spot.get("pos")])
	if spot.is_empty():
		return
	var front: Vector3 = spot.pos + Basis(Vector3.UP, spot.yaw) * Vector3(0, 0, 1.1)
	var f: Vector3 = spot.pos + Vector3(0, 1.05, 0) - (front + Vector3.UP * Player.EYE)
	p.teleport(front + Vector3(0, 0.05, 0), atan2(-f.x, -f.z), atan2(f.y, Vector2(f.x, f.z).length()))
	await _until(func() -> bool: return game.entrances.nearest(p.global_position, "stairwell") != null, 10.0)
	await _until(func() -> bool: return game.chunks.is_area_ready(p.global_position, 1), 30.0)
	await get_tree().create_timer(1.0).timeout
	p.teleport(front + Vector3(0, 0.05, 0), atan2(-f.x, -f.z), atan2(f.y, Vector2(f.x, f.z).length()))
	await get_tree().create_timer(0.5).timeout
	var ent: LevelEntrance = game.entrances.nearest(p.global_position, "stairwell")
	if ent:
		_face(p, ent)
	game._update_use()
	var tgt: Array = game._use_target
	check(not tgt.is_empty() and tgt[0] is LevelEntrance and (tgt[0] as LevelEntrance).dest == "stairwell",
			"the garage's STAIRS door offers: %s" % [tgt[2] if not tgt.is_empty() else "nothing"])
	if tgt.is_empty():
		return
	game._use()
	check(await _until(func() -> bool: return _settled("stairwell"), 90.0), "through the STAIRS door into the stairwell")
	if _settled("stairwell"):
		await _arrived("from the Backrooms")
