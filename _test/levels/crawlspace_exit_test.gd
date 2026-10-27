extends Node
# The Crawlspace for real (not the placeholder): in, kept prone, the exit
# grille offered by the Use prompt where you look at it, and through it (the
# push-out and drop) back into the Backrooms.
#   ... res://_test/levels/crawlspace_exit_test.tscn
# Prints PASS / FAIL lines and "crawlspace_exit_test: N failed".

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


func _back() -> bool:
	return not game._in_side and not game._transition and game.state == game.State.PLAYING \
			and game.player.global_position.y > -100.0


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
	game.debug_enter_side("crawlspace")
	var inside := await _until(func() -> bool: return game._in_side and not game._transition and game.side_id == "crawlspace", 60.0)
	check(inside, "into the crawlspace")
	var lv: SideLevel = game.side
	check(lv != null and String(lv.get_script().resource_path).ends_with("crawlspace_level.gd"), "it's the real level")
	var p: Player = game.player
	await get_tree().create_timer(1.0).timeout
	check(p.crawling and p.force_crawl, "prone, and kept there")
	# Up to the exit grille, looking at it.
	var at := Vector3(4.0, SideLevel.LEVEL_Y, -42.75)
	p.teleport(at, 0.0, -0.25)
	await get_tree().create_timer(1.0).timeout
	game._update_use()
	var t: Array = game._use_target
	check(not t.is_empty() and t[0] is LevelEntrance and t[2] == "Push the grille out", "the grille offers: %s" % [t])
	game._use()
	var back := await _until(_back, 60.0)
	check(back, "through it and back in the Backrooms at %s" % p.global_position)
	check(not p.force_crawl, "on your feet again")
	print("crawlspace_exit_test: %d failed" % fails)
	get_tree().quit(1 if fails > 0 else 0)
