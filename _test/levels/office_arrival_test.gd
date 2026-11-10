extends Node
# The Dimming Floor's ways in and out: dropping in from the Crawlspace
# (its exit_entered("office"): under the open grille), through the
# registry's SUITE 400 door from the Backrooms (just inside the suite door),
# and out through the stair door (Use "Take the stairs": back in the
# Backrooms). Also: the banks go out behind you as you walk.
#   ... res://_test/levels/office_arrival_test.tscn
# Prints PASS / FAIL lines and "office_arrival_test: N failed".

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
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING and not game._transition, 120.0)
	game.hud.set_fade(0.0)
	var p: Player = game.player
	# 1. From the Crawlspace: its exit says "office".
	game.debug_enter_side("crawlspace")
	check(await _until(_settled.bind("crawlspace"), 60.0), "into the crawlspace")
	game.side.exit_entered.emit("office")
	check(await _until(_settled.bind("office"), 90.0), "on into the office")
	var lv: SideLevel = game.side
	check(String(lv.get_script().resource_path).ends_with("office_level.gd"), "the built office level")
	var hole := Vector3(34.44, SideLevel.LEVEL_Y, -8.84)
	var d := Vector2(p.global_position.x - hole.x, p.global_position.z - hole.z).length()
	check(d < 0.3 and absf(p.global_position.y - hole.y) < 0.3, "standing under the open grille (%.2f m off)" % d)
	check(not p.crawling, "on your feet")
	# The banks go out behind you as you walk west down the spine.
	await get_tree().create_timer(1.0).timeout
	p.teleport(Vector3(29.0, SideLevel.LEVEL_Y, -8.0), PI * 0.5)
	Input.action_press("move_forward")
	await get_tree().create_timer(5.0).timeout
	Input.action_release("move_forward")
	var dark := 0
	for k in 15:
		if lv.get("_lamps")[k] < 0.5:
			dark += 1
	check(dark >= 2, "%d banks went out behind you" % dark)
	# 2. Out through the stair door.
	p.teleport(Vector3(0.9, SideLevel.LEVEL_Y, -15.65), PI * 0.5, -0.75)
	await get_tree().create_timer(0.8).timeout
	game._update_use()
	var t: Array = game._use_target
	check(not t.is_empty() and t[0] is LevelEntrance and t[2] == "Take the stairs", "the stair door offers: %s" % [t])
	game._use()
	check(await _until(func() -> bool: return not game._in_side and not game._transition, 60.0), "back in the Backrooms")
	# 3. Through a SUITE 400 door from the Backrooms.
	var e := LevelEntrance.new()
	e.dest = "office"
	e.look = "door"
	game.add_child(e)
	e.global_position = p.global_position + Vector3(0, 0, -0.6)
	game.enter_side_level("office", e)
	check(await _until(_settled.bind("office"), 90.0), "into the office through its door")
	var suite := Vector3(1.0, SideLevel.LEVEL_Y, -9.9)
	d = Vector2(p.global_position.x - suite.x, p.global_position.z - suite.z).length()
	check(d < 0.3, "just inside the suite door (%.2f m off)" % d)
	print("office_arrival_test: %d failed" % fails)
	game.queue_free()
	await get_tree().process_frame
	get_tree().quit(1 if fails > 0 else 0)
