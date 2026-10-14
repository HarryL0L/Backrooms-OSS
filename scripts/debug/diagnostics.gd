class_name Diagnostics
extends CanvasLayer
## Diagnostic mode, only active in builds exported with the "diag" feature tag
## (the "Ultra Debug" APK). It logs device/renderer details and runs an
## automatic test that toggles graphics features one at a time, so rendering
## problems on a specific GPU can be pinned down from a single logcat.
##
## Output: every line is printed with a "DIAG" prefix (logcat tag "godot"),
## also written to user://diag/log.txt, plus one screenshot per test step in
## user://diag/. On Android, pull them from a debug build with:
##   adb exec-out run-as io.github.backroomsoss tar -c -C files diag > diag.tar

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
	# Each step changes one more thing; the name says what was just changed.
	_steps = [
		["01 baseline (all effects as configured)", {}],
		["02 lens effects OFF", {"graphics/lens_fx": false}],
		["03 film grain OFF", {"graphics/film_grain": false}],
		["04 bloom OFF", {"graphics/bloom": false}],
		["05 light halos OFF", {"graphics/halos": false}],
		["06 anti-aliasing OFF", {"graphics/aa": 0}],
		["07 render scale 1.0 (no FSR)", {"graphics/render_scale": 1.0, "graphics/fsr": false}],
		["08 SSR OFF", {"graphics/ssr": false}],
		["09 SSAO OFF", {"graphics/ssao": false}],
		["10 SSIL OFF", {"graphics/ssil": false}],
		["11 volumetric fog OFF", {"graphics/volumetric_fog": false}],
		["12 water reflections OFF", {"graphics/water_reflections": 0}],
		["13 flashlight shadows OFF", {"graphics/flashlight_shadows": false}],
		["14 3D world hidden (2D only)", {"__hide_world": true}],
		["15 restore: lens effects ON only", {"__restore": true, "graphics/film_grain": false, "graphics/bloom": false,
				"graphics/halos": false, "graphics/aa": 0, "graphics/ssr": false, "graphics/ssao": false, "graphics/ssil": false,
				"graphics/volumetric_fog": false}],
		["16 + bloom ON", {"graphics/bloom": true}],
		["17 + SMAA ON", {"graphics/aa": 3}],
		["18 + FXAA instead of SMAA", {"graphics/aa": 4}],
		["19 + MSAA 2x instead", {"graphics/aa": 1}],
		["20 + volumetric fog ON", {"graphics/volumetric_fog": true}],
		["21 + SSR ON", {"graphics/ssr": true}],
		["22 + SSAO + SSIL ON", {"graphics/ssao": true, "graphics/ssil": true}],
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


func _next_step() -> void:
	_step += 1
	_t = 0.0
	if _step >= _steps.size():
		_finish()
		return
	var s: Array = _steps[_step]
	var changes: Dictionary = s[1]
	if changes.has("__restore"):
		game.chunks.visible = true
	for k in changes:
		if k == "__hide_world":
			game.chunks.visible = false
		elif not (k as String).begins_with("__"):
			Settings.values[k] = changes[k]
	Settings.apply()
	Settings.changed.emit()
	_label.text = "TEST STEP " + s[0]
	_sub.text = "Step %d/%d - note whether the picture looks CLEAN or CORRUPTED" % [_step + 1, _steps.size()]
	log_line("---- step %s : %s" % [s[0], JSON.stringify(changes)])


func _capture() -> void:
	# Two frames 3 frames apart: the scene is static, so a big difference is noise
	# (film grain, when enabled, also contributes).
	var a := get_viewport().get_texture().get_image()
	for i in 3:
		await RenderingServer.frame_post_draw
	var b := get_viewport().get_texture().get_image()
	if a == null or b == null:
		log_line("  capture failed")
		return
	var w := 320
	var h := int(320.0 * a.get_height() / maxf(a.get_width(), 1.0))
	a.resize(w, h, Image.INTERPOLATE_BILINEAR)
	b.resize(w, h, Image.INTERPOLATE_BILINEAR)
	var diff := 0.0
	var luma := 0.0
	var hf := 0.0
	for y in range(0, h, 2):
		for x in range(0, w - 1, 2):
			var ca := a.get_pixel(x, y)
			var cb := b.get_pixel(x, y)
			diff += absf(ca.get_luminance() - cb.get_luminance())
			luma += ca.get_luminance()
			# High-frequency energy: neighbouring-pixel differences (blocky noise raises it).
			hf += absf(ca.get_luminance() - a.get_pixel(x + 1, y).get_luminance())
	var n := float((h / 2) * (w / 2))
	var name := "user://diag/step_%02d.png" % (_step + 1)
	var full := get_viewport().get_texture().get_image()
	if full:
		full.resize(int(full.get_width() * 0.5), int(full.get_height() * 0.5), Image.INTERPOLATE_BILINEAR)
		full.save_png(name)
	log_line("  result step %02d: mean_luma=%.3f temporal_noise=%.4f high_freq=%.4f fps=%d  -> %s" % [
		_step + 1, luma / n, diff / n, hf / n, Engine.get_frames_per_second(), name])


func _finish() -> void:
	_done = true
	game.chunks.visible = true
	Settings.values = _saved_settings
	Settings.apply()
	Settings.changed.emit()
	_label.text = "DIAGNOSTICS DONE"
	_sub.text = "Settings restored. Now save the log (see README / chat instructions)."
	log_line("==== effect test finished; settings restored ====")
