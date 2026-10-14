class_name Diagnostics
extends CanvasLayer
## Diagnostic mode, only active in builds exported with the "diag" feature tag
## (the "Ultra Debug" APK). It logs device/renderer details and runs an
## automatic test that toggles graphics features one at a time, so rendering
## problems on a specific GPU can be pinned down from a single logcat.
##
## Output: every line is printed with a "DIAG" prefix (logcat tag "godot") and
## written to user://diag/log.txt, plus one screenshot per test step. When the
## test finishes everything (this log, Godot's own verbose log, the app's own
## logcat and the screenshots) is packed into one zip and saved to the shared
## Documents folder (/sdcard/Documents/Backrooms-OSS/) so it can be shared
## straight from the phone. The on-screen text shows where it was saved.

const STEP_WAIT := 2.5

var game: Node
var _log: FileAccess
var _label: Label
var _sub: Label
var _steps: Array = []
var _step := -1
var _t := 0.0
var _started := false
var _done := false
var _stats_t := 0.0
var _saved_settings := {}
var _busy := false
var _sv: SubViewport
var _sv_cam: Camera3D
var _sv_layer: CanvasLayer


static func enabled() -> bool:
	return OS.has_feature("diag")


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute("user://diag")
	_log = FileAccess.open("user://diag/log.txt", FileAccess.WRITE)
	var panel := ColorRect.new()
	panel.color = Color(0, 0, 0, 0.75)
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.offset_bottom = 96
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(panel)
	_label = Label.new()
	_label.position = Vector2(20, 6)
	_label.add_theme_font_size_override("font_size", 38)
	_label.add_theme_color_override("font_color", Color(1, 0.3, 0.3))
	add_child(_label)
	_sub = Label.new()
	_sub.position = Vector2(22, 54)
	_sub.add_theme_font_size_override("font_size", 22)
	_sub.add_theme_color_override("font_color", Color(1, 1, 1))
	add_child(_sub)
	_label.text = "DIAGNOSTIC BUILD"
	_sub.text = "Waiting for the menu... don't touch the screen."
	_log_system()
	_build_steps()
	# Dev only: DIAG_STEPS=n runs just the first n steps (for quick local tests).
	var n := OS.get_environment("DIAG_STEPS").to_int()
	if n > 0:
		_steps = _steps.slice(0, n)


func log_line(s: String) -> void:
	var line := "DIAG %8.2f  %s" % [Time.get_ticks_msec() / 1000.0, s]
	print(line)
	if _log:
		_log.store_line(line)
		_log.flush()


# ----------------------------------------------------------------- report ---

func _log_system() -> void:
	log_line("==== Backrooms-OSS diagnostics ====")
	log_line("version %s, Godot %s" % [ProjectSettings.get_setting("application/config/version"), Engine.get_version_info().string])
	log_line("OS %s %s, model '%s', locale %s" % [OS.get_name(), OS.get_version(), OS.get_model_name(), OS.get_locale()])
	log_line("CPU '%s' x%d" % [OS.get_processor_name(), OS.get_processor_count()])
	log_line("features: mobile=%s ultra=%s diag=%s" % [OS.has_feature("mobile"), OS.has_feature("ultra"), OS.has_feature("diag")])
	log_line("renderer: method=%s driver=%s" % [RenderingServer.get_current_rendering_method(), RenderingServer.get_current_rendering_driver_name()])
	log_line("GPU: '%s' vendor '%s' api '%s' type %d" % [RenderingServer.get_video_adapter_name(), RenderingServer.get_video_adapter_vendor(),
			RenderingServer.get_video_adapter_api_version(), RenderingServer.get_video_adapter_type()])
	var rd := RenderingServer.get_rendering_device()
	if rd:
		log_line("RenderingDevice: device '%s' vendor '%s' pipeline cache uuid %s" % [rd.get_device_name(), rd.get_device_vendor_name(), rd.get_device_pipeline_cache_uuid()])
		var limits := {
			"max_bound_uniform_sets": RenderingDevice.LIMIT_MAX_BOUND_UNIFORM_SETS,
			"max_texture_size_2d": RenderingDevice.LIMIT_MAX_TEXTURE_SIZE_2D,
			"max_compute_shared_memory": RenderingDevice.LIMIT_MAX_COMPUTE_SHARED_MEMORY_SIZE,
			"max_push_constant_size": RenderingDevice.LIMIT_MAX_PUSH_CONSTANT_SIZE,
		}
		for lim in limits:
			log_line("  limit %s = %d" % [lim, rd.limit_get(limits[lim])])
	var vp := get_viewport()
	log_line("window %s, screen %s @ %.1f Hz, dpi %d" % [DisplayServer.window_get_size(), DisplayServer.screen_get_size(),
			DisplayServer.screen_get_refresh_rate(), DisplayServer.screen_get_dpi()])
	log_line("viewport visible rect %s, scaling_3d mode %d scale %.2f, msaa_3d %d, ssaa %d" % [vp.get_visible_rect().size,
			vp.scaling_3d_mode, vp.scaling_3d_scale, vp.msaa_3d, vp.screen_space_aa])
	for k in ["rendering/renderer/rendering_method", "rendering/rendering_device/driver", "rendering/rendering_device/pipeline_cache/enable",
			"rendering/anti_aliasing/quality/msaa_3d", "rendering/anti_aliasing/quality/screen_space_aa", "display/window/vsync/vsync_mode"]:
		log_line("  setting %s = %s" % [k, ProjectSettings.get_setting(k)])
	for k in Settings.values:
		if (k as String).begins_with("graphics/"):
			log_line("  user %s = %s" % [k, Settings.values[k]])
	log_line("ultra crash guard level %d" % Settings.ultra_safe_level)


# ------------------------------------------------------------------- test ---

func _build_steps() -> void:
	# Round 3. Round 2 showed: pure 2D is clean; as soon as Forward+ renders 3D
	# into the root viewport, the whole root render target (2D included) reads
	# back with 8-row strips duplicated, regardless of format/effects/scale.
	# Test the workaround: render 3D into a SubViewport and show it as a 2D
	# texture, so the root render target only ever sees pure 2D.
	var off := {"graphics/lens_fx": false, "graphics/film_grain": false, "graphics/bloom": false,
		"graphics/halos": false, "graphics/aa": 0, "graphics/ssr": false, "graphics/ssao": false,
		"graphics/ssil": false, "graphics/volumetric_fog": false, "graphics/water_reflections": 0}
	_steps = [
		["01 baseline (3D in root viewport)", {}],
		["02 3D in SubViewport, shown as texture", {"__offscreen": true}],
		["03 SubViewport + HDR 2D on the SubViewport", {"__sv_hdr": true}],
		["04 SubViewport + all effects OFF", off.merged({"__sv_hdr": false})],
		["05 SubViewport + effects back ON", {"__restore_effects": true}],
		["06 back to 3D in root viewport (control)", {"__offscreen": false}],
	]


func _process(delta: float) -> void:
	_stats_t += delta
	if _stats_t >= 1.0:
		_stats_t = 0.0
		log_line("stats fps=%d frame=%.1fms draw_calls=%d prims=%d vram=%.0fMB mem=%.0fMB chunks=%s state=%s" % [
			Engine.get_frames_per_second(), Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0,
			Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),
			Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0,
			game.chunks.loaded_count() if game else -1, game.state if game else -1])
	_sync_offscreen_camera()
	if _done or game == null:
		return
	if not _started:
		if game.state == 1:  # State.MENU
			_t += delta
			if _t > 4.0:
				_started = true
				_saved_settings = Settings.values.duplicate()
				log_line("==== starting automatic effect test (%d steps, %.1fs each) ====" % [_steps.size(), STEP_WAIT])
				_next_step()
		return
	if _busy:
		return
	_t += delta
	if _t >= STEP_WAIT:
		_busy = true
		await _capture()
		_next_step()
		_busy = false


## Workaround under test: 3D goes to an off-screen SubViewport, which the root
## viewport only draws as a texture (pure 2D).
func _set_offscreen(on: bool) -> void:
	if on and _sv == null:
		_sv_layer = CanvasLayer.new()
		_sv_layer.layer = -10
		add_child(_sv_layer)
		_sv = SubViewport.new()
		_sv.size = DisplayServer.window_get_size()
		_sv.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_sv.msaa_3d = get_tree().root.msaa_3d
		_sv.screen_space_aa = get_tree().root.screen_space_aa
		_sv.scaling_3d_scale = get_tree().root.scaling_3d_scale
		_sv_layer.add_child(_sv)
		_sv_cam = Camera3D.new()
		_sv.add_child(_sv_cam)
		_sv_cam.current = true
		var tr := TextureRect.new()
		tr.texture = _sv.get_texture()
		tr.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_sv_layer.add_child(tr)
		game.player.camera.current = false
		log_line("  offscreen 3D on: SubViewport %s" % _sv.size)
	elif not on and _sv != null:
		_sv_layer.queue_free()
		_sv = null
		_sv_cam = null
		_sv_layer = null
		game.player.camera.current = true
		log_line("  offscreen 3D off")


func _sync_offscreen_camera() -> void:
	if _sv_cam and game:
		var c: Camera3D = game.player.camera
		_sv_cam.global_transform = c.global_transform
		_sv_cam.fov = c.fov
		_sv_cam.near = c.near
		_sv_cam.far = c.far


func _next_step() -> void:
	_step += 1
	_t = 0.0
	if _step >= _steps.size():
		_finish()
		return
	var s: Array = _steps[_step]
	var changes: Dictionary = s[1]
	if changes.has("__restore_effects"):
		for k in _saved_settings:
			Settings.values[k] = _saved_settings[k]
	for k in changes:
		match k:
			"__hdr2d":
				get_tree().root.use_hdr_2d = changes[k]
			"__camera":
				game.player.camera.current = changes[k]
			"__offscreen":
				_set_offscreen(changes[k])
			"__sv_hdr":
				if _sv:
					_sv.use_hdr_2d = changes[k]
			_:
				if not (k as String).begins_with("__"):
					Settings.values[k] = changes[k]
	Settings.apply()
	Settings.changed.emit()
	_label.text = "TEST STEP " + s[0]
	_sub.text = "Step %d/%d - note whether the picture looks CLEAN or CORRUPTED" % [_step + 1, _steps.size()]
	log_line("---- step %s : %s" % [s[0], JSON.stringify(changes)])


func _capture() -> void:
	var a := get_viewport().get_texture().get_image()
	for i in 3:
		await RenderingServer.frame_post_draw
	var b := get_viewport().get_texture().get_image()
	if a == null or b == null:
		log_line("  capture failed")
		return
	var name := "user://diag/step_%02d.png" % (_step + 1)
	var dup := _row_block_duplication(a)
	var noise := _temporal_noise(a, b)
	var small := a.duplicate() as Image
	small.resize(int(a.get_width() * 0.5), int(a.get_height() * 0.5), Image.INTERPOLATE_BILINEAR)
	small.save_png(name)
	log_line("  result step %02d: ROOT size=%dx%d format=%d DUPLICATION=%.3f (%s) temporal_noise=%.4f fps=%d -> %s" % [
		_step + 1, a.get_width(), a.get_height(), a.get_format(), dup,
		"CORRUPTED" if dup > 0.35 else "clean", noise, Engine.get_frames_per_second(), name])
	if _sv:
		var si := _sv.get_texture().get_image()
		if si:
			var sdup := _row_block_duplication(si)
			var sname := "user://diag/step_%02d_subviewport.png" % (_step + 1)
			var ss := si.duplicate() as Image
			ss.resize(int(si.get_width() * 0.5), int(si.get_height() * 0.5), Image.INTERPOLATE_BILINEAR)
			ss.save_png(sname)
			log_line("  result step %02d: SUBVIEWPORT size=%dx%d format=%d hdr2d=%s DUPLICATION=%.3f (%s) -> %s" % [
				_step + 1, si.get_width(), si.get_height(), si.get_format(), _sv.use_hdr_2d, sdup,
				"CORRUPTED" if sdup > 0.35 else "clean", sname])


func _row_block_duplication(img: Image) -> float:
	return RenderCheck.row_block_duplication(img)


func _temporal_noise(a: Image, b: Image) -> float:
	var x := a.duplicate() as Image
	var y := b.duplicate() as Image
	x.resize(320, 144, Image.INTERPOLATE_BILINEAR)
	y.resize(320, 144, Image.INTERPOLATE_BILINEAR)
	var diff := 0.0
	for j in range(0, 144, 2):
		for i in range(0, 320, 2):
			diff += absf(x.get_pixel(i, j).get_luminance() - y.get_pixel(i, j).get_luminance())
	return diff / (72.0 * 160.0)


func _finish() -> void:
	_done = true
	_set_offscreen(false)
	game.chunks.visible = true
	game.player.camera.current = true
	get_tree().root.use_hdr_2d = false
	Settings.values = _saved_settings
	Settings.apply()
	Settings.changed.emit()
	log_line("==== effect test finished; settings restored ====")
	_label.text = "DIAGNOSTICS DONE - saving report..."
	_sub.text = ""
	await get_tree().process_frame
	var where := _export_report()
	if where == "":
		_label.text = "DIAGNOSTICS DONE - could not save the zip"
		_sub.text = "Use adb instead (see chat instructions)."
	else:
		_label.text = "DIAGNOSTICS DONE - report saved"
		_sub.text = where


## The app's own logcat lines (Android lets an app read its own process logs,
## which include Vulkan loader and GPU driver messages).
func _own_logcat() -> String:
	if OS.get_name() != "Android":
		return "(logcat only available on Android)"
	var out := []
	var code := OS.execute("logcat", ["-d", "-v", "time", "-t", "20000"], out, true)
	if code != 0 or out.is_empty():
		return "(logcat failed, exit code %d)" % code
	return "".join(out)


## Godot's own log file (verbose output; file logging is enabled for this build).
func _godot_log() -> PackedByteArray:
	var path: String = ProjectSettings.get_setting("debug/file_logging/log_path", "user://logs/godot.log")
	if FileAccess.file_exists(path):
		return FileAccess.get_file_as_bytes(path)
	return "(no godot.log at %s)".to_utf8_buffer()


func _export_report() -> String:
	var stamp := Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
	var zip_name := "backrooms-diag-%s.zip" % stamp
	var tmp := "user://diag/" + zip_name
	if _log:
		_log.flush()
	var z := ZIPPacker.new()
	if z.open(tmp) != OK:
		log_line("zip: could not create " + tmp)
		return ""
	_zip_add(z, "diag_log.txt", FileAccess.get_file_as_bytes("user://diag/log.txt"))
	_zip_add(z, "godot.log", _godot_log())
	_zip_add(z, "logcat.txt", _own_logcat().to_utf8_buffer())
	for f in DirAccess.get_files_at("user://diag"):
		if f.ends_with(".png"):
			_zip_add(z, "screens/" + f, FileAccess.get_file_as_bytes("user://diag/" + f))
	z.close()
	var data := FileAccess.get_file_as_bytes(tmp)
	# Shared Documents first (visible in any file manager), then fallbacks.
	var dirs := [
		OS.get_system_dir(OS.SYSTEM_DIR_DOCUMENTS) + "/Backrooms-OSS",
		OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS) + "/Backrooms-OSS",
		"/storage/emulated/0/Android/data/io.github.backroomsoss/files",
	]
	for dir in dirs:
		if dir.begins_with("/Backrooms-OSS"):
			continue  # system dir unavailable
		DirAccess.make_dir_recursive_absolute(dir)
		var path: String = dir + "/" + zip_name
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f:
			f.store_buffer(data)
			f.close()
			log_line("report saved: %s (%d KB)" % [path, data.size() / 1024])
			return path
		log_line("could not write %s (error %d)" % [path, FileAccess.get_open_error()])
	log_line("report only available internally at " + ProjectSettings.globalize_path(tmp))
	return ""


func _zip_add(z: ZIPPacker, name: String, bytes: PackedByteArray) -> void:
	z.start_file(name)
	z.write_file(bytes)
	z.close_file()
