extends Node
# The Field's storm: screenshots and a film (docs/FIELD_STORM.md).
#
#   G=/tmp/claude-0/godot/Godot_v4.7-stable_linux.x86_64
#   VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json xvfb-run -a $G --path . --rendering-method mobile \
#       --rendering-driver vulkan --resolution 1280x720 res://_test/field_storm_shots.tscn -- [--preset N] \
#       [--set key=value] [--tag name] [--film | --clouds]
#
# Starts a new game (seed 1234), goes into the Field, and saves
# user://field_storm/<tag>/<shot>.png, printing FPS, draw calls, primitives
# and (PERF=1) the mean frame time over 60 frames. SHOTS=<comma list> takes
# only those. --film plays a 45 s storm-chaser film instead (record it with
# `--write-movie <path>.avi --fixed-fps 30` before the `--`): the tornado
# rotating and drifting, gusts in the grass, a rain band arriving, a strike
# with its thunder 5 s later. --clouds plays a 20 s pan along the storm's
# clouds instead (record it the same way). Exits 1 on any script or shader
# error.

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
var preset := -1
var sets := {}
var tag := "default"
var film := false
var clouds := false
var out := ""
var errors := _Errors.new()
var _restore := {}
var _preset0 := -1
var _yaw_to := 0.0
var _pitch_to := 0.0
var _steer := false
var _turn := 1.2
## The film runs the rain band this many times faster (time compression).
var _band_k := 1.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	OS.add_logger(errors)
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		var a: String = args[i]
		if a == "--film":
			film = true
		elif a == "--clouds":
			clouds = true
		elif a == "--preset" and i + 1 < args.size():
			preset = int(args[i + 1])
		elif a == "--tag" and i + 1 < args.size():
			tag = args[i + 1]
		elif a == "--set" and i + 1 < args.size():
			var kv: PackedStringArray = args[i + 1].split("=", true, 1)
			sets[kv[0]] = str_to_var(kv[1]) if kv.size() > 1 and str_to_var(kv[1]) != null else (kv[1] if kv.size() > 1 else true)
	out = OS.get_user_data_dir() + "/field_storm/" + tag
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


func _process(delta: float) -> void:
	if not _steer or game == null or game.player == null:
		return
	if game.field != null:
		game.field.storm.band_phase += delta * (_band_k - 1.0)
	var p: Player = game.player
	var k := 1.0 - exp(-_turn * delta)
	p.yaw = lerp_angle(p.yaw, _yaw_to, k)
	p.pitch = lerpf(p.pitch, _pitch_to, k)
	p._apply_rotation()


## Yaw and pitch from the eye toward a world point.
func _aim_at(at: Vector3, pitch_add := 0.0) -> Vector2:
	var d: Vector3 = at - game.player.camera.global_position
	return Vector2(atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()) + pitch_add)


func _stand(pos: Vector2, yaw: float, pitch: float) -> void:
	game.player.teleport(FieldLevel.ground_at(pos.x, pos.y) + Vector3(0, 0.05, 0), yaw, pitch)


func _run() -> void:
	await _until(func() -> bool: return game.state == game.State.MENU, 120.0)
	Settings.set_value("graphics/auto_quality", false)
	if preset >= 0:
		_preset0 = int(Settings.get_value("graphics/preset"))
		Settings.apply_preset(preset)
	for k in sets:
		_restore[k] = Settings.get_value(k)
		Settings.set_value(k, sets[k])
		print("field_storm: ", k, " = ", Settings.get_value(k))
	(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
	game.new_game()
	await _until(func() -> bool: return game.state == game.State.PLAYING, 120.0)
	game.hud.set_fade(0.0)
	game._enter_field()
	game.hud._title_t = 0.001
	var p: Player = game.player
	p.controls_enabled = false
	await _wait(3.0)
	if clouds:
		await _clouds_film()
	elif film:
		await _film()
	else:
		await _shots()
	_finish()


func _shots() -> void:
	var f: FieldLevel = game.field
	var st: FieldStorm = f.storm
	var only := OS.get_environment("SHOTS").split(",", false)
	var e: Vector3 = f.exit_pos
	var to := Vector3(e.x, 0, e.z).normalized()
	var list := [
		{"name": "wide_storm", "do": func() -> void:
			st.band_phase = 40.0
			_stand(Vector2.ZERO, 0.0, 0.0)
			var a := _aim_at(st.tornado_foot() + Vector3(0, 300, 0), 0.02)
			game.player.teleport(game.player.global_position, a.x, a.y)},
		{"name": "supercell_up", "do": func() -> void:
			var a := _aim_at(st.tornado_foot() + Vector3(600, 0, 0), 0.32)
			game.player.teleport(game.player.global_position, a.x, a.y)},
		{"name": "sun_gap", "do": func() -> void:
			# Under the base's edge toward the sun behind the storm.
			game.player.teleport(game.player.global_position, -deg_to_rad(312.0), 0.16)},
		{"name": "curtain", "do": func() -> void:
			# The core's rain curtain beside the tornado.
			game.player.teleport(game.player.global_position, -deg_to_rad(8.0), 0.06)},
		{"name": "wall_cloud", "after": func() -> void: game.player._apply_settings(), "do": func() -> void:
			# The tornado and the wall cloud, zoomed (a 28 degree lens).
			var a := _aim_at(st.tornado_foot() + Vector3(0, 650, 0), 0.0)
			game.player.teleport(game.player.global_position, a.x, a.y)
			game.player.camera.fov = 28.0},
		{"name": "grass_close", "do": func() -> void:
			var w := st.wind_here
			game.player.teleport(game.player.global_position, atan2(w.x, w.z) + 0.6, -0.45)},
		{"name": "grass_mid", "do": func() -> void:
			var w := st.wind_here
			game.player.teleport(game.player.global_position, atan2(-w.z, w.x), -0.1)},
		{"name": "behind", "do": func() -> void:
			game.player.teleport(game.player.global_position, 2.09, 0.05)},
		{"name": "lightning", "wait": 0.0, "do": func() -> void:
			st.band_phase = 40.0
			game.player.teleport(game.player.global_position, -deg_to_rad(8.0), 0.1)
			await _wait(1.5)
			st.lightning.flash(deg_to_rad(16.0), 1600.0, true, true, 0.0, 1.0)
			await get_tree().process_frame},
		{"name": "band_coming", "do": func() -> void:
			st.band_phase = 230.0
			var n: Vector2 = -st._band_n
			game.player.teleport(game.player.global_position, atan2(-n.x, -n.y), 0.06)},
		{"name": "in_rain", "do": func() -> void:
			st.band_phase = 400.0
			var a := _aim_at(st.tornado_foot() + Vector3(0, 250, 0), 0.0)
			game.player.teleport(game.player.global_position, a.x, a.y)},
		{"name": "exit_door", "do": func() -> void:
			st.band_phase = 40.0
			_stand(Vector2(e.x - to.x * 14.0, e.z - to.z * 14.0), atan2(to.x, to.z) + PI, 0.08)},
	]
	for s: Dictionary in list:
		if not only.is_empty() and not only.has(s.name):
			continue
		await (s.do as Callable).call()
		await _wait(float(s.get("wait", 2.0)))
		await RenderingServer.frame_post_draw
		var path := "%s/%s.png" % [out, s.name]
		get_viewport().get_texture().get_image().save_png(path)
		if s.has("after"):
			(s.after as Callable).call()
		var tf: Vector3 = st.tornado_foot() - game.player.global_position
		print("  tornado %.0f m off at azimuth %.0f, presence %.2f" % [Vector2(tf.x, tf.z).length(), rad_to_deg(atan2(tf.x, -tf.z)), st.presence])
		print("shot %-13s fps %5.1f  draw calls %4d  primitives %8d  EV %.1f  wind %.1f m/s  rain %.1f mm/h  -> %s" % [s.name,
				Engine.get_frames_per_second(),
				Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
				Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
				st.cam.ev100, st.wind_here.length(), st.rain_here, path])
		if OS.get_environment("PERF") == "1":
			var pt0 := Time.get_ticks_usec()
			for i in 60:
				await RenderingServer.frame_post_draw
			print("PERF %s frame_ms=%.2f" % [s.name, (Time.get_ticks_usec() - pt0) / 60000.0])


## 45 s, body cam: standing in the grass filming the tornado; the wind
## gusting; a strike off to the right, its thunder ~5 s later; the rain
## band's gust front, then its rain sweeping in; a few steps forward.
func _film() -> void:
	var f: FieldLevel = game.field
	var st: FieldStorm = f.storm
	var p: Player = game.player
	st.band_phase = 110.0          # forming, 3.8 km off to the north-east
	st.tornado_age = FieldStorm.T_FORM + 30.0
	st.lightning.calm(1e5)
	_stand(Vector2(10.0, -20.0), 0.0, 0.0)
	var a := _aim_at(st.tornado_foot() + Vector3(0, 350, 0), -0.02)
	p.teleport(p.global_position, a.x, a.y)
	_yaw_to = a.x
	_pitch_to = a.y
	_steer = true
	var t0 := Time.get_ticks_msec()
	# 0-9 s: hold on the tornado (a little zoom of attention: tilt down).
	await _wait(9.0)
	# 9-15 s: pan down-left across the grass in the wind.
	_yaw_to = a.x + 0.5
	_pitch_to = -0.3
	await _wait(6.0)
	# 15-22 s: back up toward the storm, a strike to the right of the tornado.
	_band_k = 6.0
	_yaw_to = a.x - 0.25
	_pitch_to = 0.04
	await _wait(3.0)
	var sa := _aim_at(st.tornado_foot() + Vector3(1800, 0, 1500))
	st.lightning.flash(-sa.x, 1750.0, true, true, 0.0, 1.0)
	await _wait(4.0)
	# 22-32 s: turn toward the rain band coming in; band and gust front run in.
	_band_k = 6.0
	var n: Vector2 = -st._band_n
	_yaw_to = atan2(-n.x, -n.y)
	_pitch_to = 0.05
	_turn = 0.7
	await _wait(10.0)
	# 32-45 s: back to the tornado, walking a few steps as the rain arrives.
	_yaw_to = a.x
	_pitch_to = 0.0
	Input.action_press("move_forward")
	p.controls_enabled = true
	await _wait(6.0)
	Input.action_release("move_forward")
	await _wait(7.0)
	print("field_storm: film %.1f s wall" % ((Time.get_ticks_msec() - t0) / 1000.0))


## 20 s, real time: standing in the grass, a slow pan along the storm from
## the sun side (the base's soft rim against the bright gap)
## across the base and the wall cloud turning over the tornado to the core's
## rain curtain, the scud racing in under the base.
func _clouds_film() -> void:
	var st: FieldStorm = game.field.storm
	var p: Player = game.player
	st.band_phase = 40.0
	st.tornado_age = FieldStorm.T_FORM + 40.0
	st.lightning.calm(1e5)
	_stand(Vector2(10.0, -20.0), 0.0, 0.0)
	var a := _aim_at(st.tornado_foot() + Vector3(0, 450, 0), 0.0)
	p.teleport(p.global_position, a.x + 0.75, 0.2)
	_yaw_to = a.x + 0.75
	_pitch_to = 0.2
	_steer = true
	_turn = 0.35
	var t0 := Time.get_ticks_msec()
	await _wait(2.0)
	_yaw_to = a.x
	_pitch_to = 0.1
	await _wait(10.0)
	_yaw_to = a.x - 0.5
	_pitch_to = 0.12
	await _wait(8.0)
	print("field_storm: clouds film %.1f s wall" % ((Time.get_ticks_msec() - t0) / 1000.0))


func _finish() -> void:
	for k in _restore:
		Settings.set_value(k, _restore[k])
	if _preset0 >= 0:
		Settings.apply_preset(_preset0)
	for l in errors.lines:
		print("ERROR ", l)
	print("field_storm: done, %d script/shader errors" % errors.count)
	OS.remove_logger(errors)
	game.queue_free()
	for i in 4:
		await get_tree().process_frame
	get_tree().quit(1 if errors.count > 0 else 0)
