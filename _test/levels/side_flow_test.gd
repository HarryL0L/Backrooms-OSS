extends Node
# Side level framework test (placeholders stand in for every level):
#  1. a real entrance in the Backrooms (the crawlspace's vent) used through
#     the Use prompt takes you into the level;
#  2. crawling: crouched into the placeholder's low duct you go down flat,
#     can't get up inside, and stand again past it; force_crawl;
#  3. wading: in its flooded pit you're in water, slower, splashing;
#  4. save inside, back to the menu, Continue: same level, same place;
#  5. its exit takes you back into the Backrooms;
#  6. a chain: the stairwell's exit goes on into the flooded basement;
#  7. caught (back to the Backrooms) and a deadly fall;
#  8. the Dead Mall's ways in (hospital lift, metro stairs) stand on its
#     walls, and the lift takes you to Ward 0.
# Every level is its placeholder here, built or not.
# Prints PASS / FAIL lines; exits 1 if anything failed or a script error.
#   ... res://_test/levels/side_flow_test.tscn

class _Errors:
	extends Logger
	var count := 0
	var lines: Array[String] = []
	var _lock := Mutex.new()

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
			error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_SCRIPT and error_type != ERROR_TYPE_SHADER:
			return
		_lock.lock()
		count += 1
		lines.append("%s:%d %s %s %s" % [file, line, function, code, rationale])
		_lock.unlock()

	func _log_message(_message: String, _error: bool) -> void:
		pass


var game
var fails := 0
var errors := _Errors.new()
var out := OS.get_user_data_dir() + "/levels/flow"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(errors)
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	# The framework is tested on the placeholders (their duct, pit and
	# exits), whichever levels are built by now.
	for id in SideLevels.ids():
		SideLevels._scripts[id] = null
		SideLevels._info.erase(id)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func check(ok: bool, what: String) -> void:
	print(("PASS " if ok else "FAIL ") + what)
	if not ok:
		fails += 1


func _wait(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _until(cond: Callable, limit: float) -> bool:
	var t := 0.0
	while not cond.call():
		await get_tree().process_frame
		t += get_process_delta_time()
		if t > limit:
			return false
	return true


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])


func _settled() -> bool:
	return game.state == game.State.PLAYING and not game._transition


func _in(id: String) -> bool:
	return _settled() and game._in_side and game.side_id == id


func _back() -> bool:
	return _settled() and not game._in_side and game.player.global_position.y > -100.0


## Into the level `id` with nothing in the way.
func _debug_into(id: String) -> bool:
	game.debug_enter_side(id)
	return await _until(func() -> bool: return _in(id), 60.0)


func _exit_of(level: SideLevel) -> LevelEntrance:
	for n in level.find_children("*", "LevelEntrance", true, false):
		if (n as LevelEntrance).exit_of == level:
			return n
	return null


func _run() -> void:
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return _settled(), 120.0)
	game.hud.set_fade(0.0)
	var p: Player = game.player

	# 0. Where every level's nearest way in is from the start (on a floor it
	# can be on), for this seed.
	for id in SideLevels.ids():
		for spec in SideLevels.info(id).entrances:
			if spec["in"] != "backrooms":
				print("  %-12s in the Dead Mall (%s, %s)" % [id, spec.slot, spec.look])
				continue
			var fl := clampi(0, int(spec.floors[0]), int(spec.floors[1]))
			var g := WorldGen.new(game.gen.seed_value, fl)
			var s: Dictionary = LevelEntrances.find(g, id, g.spawn_position(), 16)
			print("  %-12s floor %2d: %s" % [id, fl, "%s %.0f m from the start" % [spec.look,
					(s.pos as Vector3).distance_to(g.spawn_position())] if not s.is_empty() else "none within 16 regions"])

	# 1. The crawlspace's vent, used like a player would.
	var spot: Dictionary = LevelEntrances.find(game.gen, "crawlspace", p.global_position, 14)
	check(not spot.is_empty(), "a crawlspace entrance exists near the start: %s" % [spot.get("pos")])
	if not spot.is_empty():
		# A step in front of it, looking right at it.
		var front: Vector3 = spot.pos + Basis(Vector3.UP, spot.yaw) * Vector3(0, 0, 1.1)
		var f: Vector3 = spot.pos + Vector3(0, 0.32, 0) - (front + Vector3.UP * Player.EYE)
		p.teleport(front + Vector3(0, 0.05, 0), atan2(-f.x, -f.z), atan2(f.y, Vector2(f.x, f.z).length()))
		await _until(func() -> bool: return game.entrances.nearest(p.global_position, "crawlspace") != null, 5.0)
		await _until(func() -> bool: return game.chunks.is_area_ready(p.global_position, 1), 30.0)
		await _wait(1.0)
		await _shot("vent")
		game._update_use()
		check(not game._use_target.is_empty() and game._use_target[0] is LevelEntrance, "the vent offers: %s" %
				[game._use_target[2] if not game._use_target.is_empty() else "nothing"])
		game._use()
		check(await _until(func() -> bool: return _in("crawlspace"), 60.0), "through the vent into the crawlspace")
	if not game._in_side:
		check(await _debug_into("crawlspace"), "into the crawlspace (debug)")
	var lv: SideLevel = game.side
	var o := Vector3(0, SideLevel.LEVEL_Y, 0)
	await _shot("arrival")

	# 2. Crawling.
	p.controls_enabled = true
	p.teleport(o + Vector3(-5.6, 0.05, -4.5), -PI * 0.5)
	await _wait(0.5)
	p.crouching = true
	Input.action_press("move_forward")
	await _wait(5.0)
	check(p.crawling and p.global_position.x - o.x > -3.6, "crouched into the duct: crawling %s at x %.2f, eye %.2f" %
			[p.crawling, p.global_position.x - o.x, p.head.position.y])
	check(p.surface_at() == Player.SURF_METAL, "metal underfoot in the duct (%d)" % p.surface_at())
	Input.action_release("move_forward")
	p.crouching = false
	p.queue_jump()
	await _wait(1.0)
	check(p.crawling, "can't get up inside the duct (height %.2f)" % p._shape.height)
	await _shot("duct")
	Input.action_press("move_forward")
	await _until(func() -> bool: return p.global_position.x - o.x > 0.6, 12.0)
	await _wait(0.4)
	Input.action_release("move_forward")
	await _wait(1.2)
	check(not p.crawling and p._shape.height > Player.STAND_H - 0.05, "up again past the duct (height %.2f at x %.2f)" %
			[p._shape.height, p.global_position.x - o.x])
	p.force_crawl = true
	await _wait(0.8)
	var low := p.crawling
	p.queue_jump()
	await _wait(0.6)
	check(low and p.crawling, "force_crawl keeps you down")
	p.force_crawl = false
	await _wait(1.2)
	check(not p.crawling, "and lets you up")

	# 3. Wading.
	p.teleport(o + Vector3(5.5, PlaceholderLevel.PIT_FLOOR + 0.05, -2.0), PI * 0.5)
	await _wait(0.8)
	check(p.in_water() and absf(p.water_depth() - 1.0) < 0.1 and p.surface_at() == Player.SURF_WATER,
			"in the pit: in water %s, depth %.2f, surface %d" % [p.in_water(), p.water_depth(), p.surface_at()])
	Input.action_press("move_forward")
	await _wait(1.5)
	var v := Vector2(p.velocity.x, p.velocity.z).length()
	Input.action_release("move_forward")
	check(v < Player.WALK * 0.7 and v > 0.5, "wading is slower: %.2f m/s (walk %.1f)" % [v, Player.WALK])
	p.teleport(o + Vector3(-5.0, 0.05, 2.0), 0.0)
	await _wait(0.5)
	check(not p.in_water() and p.surface_at() == Player.SURF_CONCRETE, "dry floor again")
	# The Backrooms' own pools are untouched: off the side level nothing changes.

	# 4. Save, back to the menu, continue.
	var saved_at := p.global_position
	game._write_save()
	var cf := ConfigFile.new()
	cf.load("user://save.cfg")
	check(cf.get_value("save", "side", "") == "crawlspace", "the save says crawlspace")
	game.exit_to_menu()
	await _until(func() -> bool: return game.state == game.State.MENU, 60.0)
	check(not game._in_side, "the menu is in the Backrooms")
	game.continue_game()
	check(await _until(func() -> bool: return _in("crawlspace"), 90.0), "Continue goes back into the crawlspace")
	await _wait(0.5)
	check(game.player.global_position.distance_to(saved_at) < 0.5, "where you were: %s (saved %s)" %
			[game.player.global_position, saved_at])
	p = game.player
	lv = game.side

	# 5. Out through its exit.
	var ex := _exit_of(lv)
	check(ex != null and ex.dest == "", "it has an exit back to the Backrooms")
	if ex:
		ex._activate()
	check(await _until(_back, 60.0), "back in the Backrooms at %s" % [p.global_position])
	await _wait(0.5)
	check(game.chunks.visible and game.world_env.environment == game.env and not p.side_mode, "the Backrooms are back")

	# 6. A chain: stairwell -> flooded.
	check(await _debug_into("stairwell"), "into the stairwell")
	ex = _exit_of(game.side)
	check(ex != null and ex.dest == "flooded", "its exit goes on to the flooded basement")
	if ex:
		ex._activate()
	check(await _until(func() -> bool: return _in("flooded"), 60.0), "the chain lands in the flooded basement")
	ex = _exit_of(game.side)
	if ex:
		ex._activate()
	check(await _until(_back, 60.0), "and out of it, back to the Backrooms")

	# 7. Caught, and a fall.
	check(await _debug_into("metro"), "into the metro")
	game.side.catch_player(["Test: caught."])
	check(await _until(_back, 60.0), "caught: back in the Backrooms")
	check(await _debug_into("metro"), "into the metro again")
	var w: Walker = game.side.make_walker("tall")
	w.global_position = p.global_position - p.global_basis.z * 2.0
	game.side.catch_player(["Test: caught by a figure."], {"scare": w, "sound": "tall_roar", "from": 2.0, "to": 0.6, "time": 0.9})
	await _wait(0.5)
	await _shot("jumpscare")
	check(await _until(_back, 60.0), "caught with a jumpscare: back in the Backrooms")
	check(await _debug_into("reservoir"), "into the reservoir")
	game.side.fall_kill = 3.0
	p.teleport(p.global_position + Vector3(0, 12.0, 0), p.yaw)
	check(await _until(_back, 60.0), "a deadly fall: back in the Backrooms")

	# 8. The mall's ways in.
	game._enter_mall()
	await _wait(2.0)
	var found := {}
	var space: PhysicsDirectSpaceState3D = p.get_world_3d().direct_space_state
	for n in game.mall.find_children("*", "LevelEntrance", true, false):
		var e := n as LevelEntrance
		var from := e.global_position + Vector3.UP * 1.0 + e.global_basis.z * 0.5
		var q := PhysicsRayQueryParameters3D.create(from, from - e.global_basis.z * 2.0)
		var hit := space.intersect_ray(q)
		var d: float = from.distance_to(hit.position) - 0.5 if not hit.is_empty() else INF
		found[e.dest] = e
		check(d < 0.35, "mall: %s's %s stands on a wall (%.2f m off it)" % [e.dest, e.look, d])
	check(found.has("ward") and found.has("metro"), "mall has the ward lift and the metro stairs: %s" % [found.keys()])
	if found.has("ward"):
		var e: LevelEntrance = found.ward
		p.teleport(e.global_position + e.global_basis.z * 1.6 + Vector3(0, 0.05, 0), atan2(e.global_basis.z.x, e.global_basis.z.z), -0.1)
		await _wait(1.0)
		await _shot("mall_ward")
		game.use_level_entrance(e)
		check(await _until(func() -> bool: return _in("ward"), 60.0), "the hospital lift goes to Ward 0")
		ex = _exit_of(game.side)
		if ex:
			ex._activate()
		check(await _until(_back, 60.0), "and back to the Backrooms (not the mall): mall %s" % game._in_mall)

	for l in errors.lines:
		print("ERROR ", l)
	print("side_flow_test: %d failed, %d script/shader errors" % [fails, errors.count])
	OS.remove_logger(errors)
	# (Free the game first. Godot can still crash on the way out after the
	# Dead Mall has been built ("Aborted", exit 134, the stock
	# mall_ride_test too): the line above is the result.)
	game.queue_free()
	for i in 4:
		await get_tree().process_frame
	get_tree().quit(1 if fails > 0 or errors.count > 0 else 0)
