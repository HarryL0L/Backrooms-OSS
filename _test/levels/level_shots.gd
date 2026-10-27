extends Node
# Side level screenshot / QA harness.
#
#   G=/tmp/claude-0/godot/Godot_v4.7-stable_linux.x86_64
#   flock /tmp/claude-0/godot.lock timeout 600 env VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
#       xvfb-run -a $G --path . --rendering-method mobile --rendering-driver vulkan --resolution 1280x720 \
#       res://_test/levels/level_shots.tscn -- <id> [--movie] [--preset N]
#
# Boots the game, starts a new game (seed 1234, like the other harnesses),
# goes into side level <id> (game.debug_enter_side), waits for the warm-up
# (shader compiles), then stands at each of the level's shots() exactly as
# in play (the player's own camera: human eye lens, PS1 mode, whatever the
# settings are) and saves user://levels/<id>/<name>.png, printing FPS, draw
# calls, primitives, objects and video memory for each. Textures that would
# cost too much on a phone (no mipmaps, not VRAM compressed, over 1024 px)
# are listed. With --movie it then plays the level's film(); record it by
# adding Godot's own `--write-movie user_dir/levels/<id>.avi --fixed-fps 30`
# before the `--`. --preset N switches the graphics preset first (0 Potato
# .. 5 Photoreal); --set key=value any setting (e.g. --set graphics/ps1=true);
# --script res://... runs that script as level <id> (a variant being tried).
# Exits 1 on any script or shader error.

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
var id := "crawlspace"
var movie := false
var preset := -1
var sets := {}
var script_path := ""
var _restore := {}
var _preset0 := -1
var out := ""
var errors := _Errors.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	OS.add_logger(errors)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--movie":
			movie = true
		elif a == "--preset" and i + 1 < args.size():
			preset = int(args[i + 1])
		elif a == "--set" and i + 1 < args.size():
			var kv: PackedStringArray = args[i + 1].split("=", true, 1)
			sets[kv[0]] = str_to_var(kv[1]) if kv.size() > 1 and str_to_var(kv[1]) != null else (kv[1] if kv.size() > 1 else true)
		elif a == "--script" and i + 1 < args.size():
			script_path = args[i + 1]
		elif not a.begins_with("--") and (i == 0 or not args[i - 1] in ["--preset", "--set", "--script"]):
			id = a
	if script_path != "":
		# Another script stands in as the level (a variant being tried).
		SideLevels._scripts[id] = load(script_path)
		SideLevels._info.erase(id)
	out = OS.get_user_data_dir() + "/levels/" + id
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


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


func _run() -> void:
	print("level_shots: ", id, " (", "built" if SideLevels.info(id).built else "placeholder", ")")
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	if preset >= 0:
		_preset0 = int(Settings.get_value("graphics/preset"))
		Settings.apply_preset(preset)
	for k in sets:
		_restore[k] = Settings.get_value(k)      # (settings are saved: put them back after)
		Settings.set_value(k, sets[k])
		print("level_shots: ", k, " = ", Settings.get_value(k))
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING, 120.0)
	game.hud.set_fade(0.0)
	var t0 := Time.get_ticks_msec()
	await game.debug_enter_side(id)
	await _until(func() -> bool: return game._in_side and not game._transition, 60.0)
	print("level_shots: entered in %.1f s; warming up" % ((Time.get_ticks_msec() - t0) / 1000.0))
	game.hud._title_t = 0.001          # (the title card would cover the first shots)
	await _wait(4.0)
	var level: SideLevel = game.side
	_check_textures(level)
	var p: Player = game.player
	p.controls_enabled = false
	for s in level.shots():
		var xf: Transform3D = s.transform
		p.force_crawl = bool(s.get("crawl", false))
		p.teleport(xf.origin + Vector3(0, 0.02, 0), SideLevel._yaw_of(xf), SideLevel._pitch_of(xf))
		p.snap_stance()
		if s.has("flashlight"):
			p.set_flashlight(bool(s.flashlight))
		await _wait(float(s.get("wait", 1.5)))
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [out, s.name]
		get_viewport().get_texture().get_image().save_png(path)
		print("shot %-14s fps %5.1f  draw calls %4d  primitives %7d  objects %4d  video mem %6.1f MB  -> %s" % [s.name,
				Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, path])
	p.force_crawl = false
	if movie:
		print("level_shots: film")
		p.controls_enabled = true
		await level.film()
		await _wait(0.5)
	_finish()


func _finish() -> void:
	for k in _restore:
		Settings.set_value(k, _restore[k])
	if _preset0 >= 0:
		Settings.apply_preset(_preset0)
	for l in errors.lines:
		print("ERROR ", l)
	print("level_shots: done, %d script/shader errors" % errors.count)
	OS.remove_logger(errors)
	await _quit(1 if errors.count > 0 else 0)


## Frees the game before quitting: quitting with it still running can crash
## Godot on the way out (Aborted, exit 134, the stock tests too).
func _quit(code: int) -> void:
	game.queue_free()
	for i in 4:
		await get_tree().process_frame
	get_tree().quit(code)


## Lists textures in the level's materials that would cost too much on a
## phone (no mipmaps, not VRAM compressed, bigger than 1024).
func _check_textures(level: SideLevel) -> void:
	var seen := {}
	for m in level.warm_materials():
		if not (m is ShaderMaterial):
			continue
		for pname in ["albedo_tex", "normal_tex", "rough_tex"]:
			var tex = (m as ShaderMaterial).get_shader_parameter(pname)
			if not (tex is Texture2D) or seen.has(tex):
				continue
			seen[tex] = true
			var img: Image = (tex as Texture2D).get_image()
			var notes := []
			if img and not img.has_mipmaps():
				notes.append("no mipmaps")
			if img and not img.is_compressed():
				notes.append("not VRAM compressed")
			if tex.get_width() > 1024 or tex.get_height() > 1024:
				notes.append("%dx%d" % [tex.get_width(), tex.get_height()])
			if not notes.is_empty():
				print("texture warning: %s: %s (see README: textures)" % [tex.resource_path, ", ".join(notes)])
	print("level_shots: %d textures checked" % seen.size())
