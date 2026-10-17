class_name FoundFootage
extends CanvasLayer
## "Found footage" camera mode (Settings graphics/found_footage: 0 off,
## 1 phone camera, 2 camcorder tape). Separate from the quality presets.
## The image is reprocessed like a real cheap camera's (shaders/
## found_footage.gdshader); this node drives what changes over time:
##  - auto exposure that lags and hunts (overshoots) when the light changes,
##  - auto white balance drifting warm and cool,
##  - handheld shake (a slow wander plus small jitters, more when you run),
##  - tape tracking glitches now and then (camcorder),
##  - the recording overlay: REC and the running time (and a date stamp and
##    battery on the camcorder).
## It sits above the 3D view and the lens/grain layer, below the HUD.

var player: Player
var gen: WorldGen
var mode := 0

var _rect: ColorRect
var _mat: ShaderMaterial
var _rec: Label
var _stamp: Label
var _batt: Label
var _rng := RandomNumberGenerator.new()
var _frame := 0.0
var _rec_t := 0.0
var _exp := 1.0
var _exp_v := 0.0
var _wb := Vector3.ONE
var _wb_target := Vector3.ONE
var _wb_t := 0.0
var _glitch := 0.0
var _glitch_t := 6.0
var _shake := Vector2.ZERO
var _shake_v := Vector2.ZERO


func _ready() -> void:
	layer = 2
	_rng.randomize()
	_rect = ColorRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/found_footage.gdshader")
	_rect.material = _mat
	add_child(_rect)
	_rec = _label(Control.PRESET_TOP_LEFT, Vector2(36, 24), 26, Color(1, 0.25, 0.2))
	_stamp = _label(Control.PRESET_BOTTOM_LEFT, Vector2(36, -64), 24, Color(1, 0.95, 0.85))
	_batt = _label(Control.PRESET_TOP_RIGHT, Vector2(-300, 24), 24, Color(1, 0.95, 0.85))   # clear of the pause button
	set_mode(0)


func _label(preset: int, off: Vector2, size: int, c: Color) -> Label:
	var l := Label.new()
	l.set_anchors_and_offsets_preset(preset)
	l.position += off
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", c)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(l)
	return l


func set_mode(m: int) -> void:
	mode = m
	visible = m > 0
	set_process(m > 0)
	_mat.set_shader_parameter("mode", m)
	_stamp.visible = m == 2
	_batt.visible = m == 2
	if m == 0 and player:
		player.camera.h_offset = 0.0
		player.camera.v_offset = 0.0


func _process(delta: float) -> void:
	_frame += 1.0
	_rec_t += delta
	_mat.set_shader_parameter("frame", fmod(_frame, 1000.0))
	# Auto exposure: aims for mid-grey from how much light is around, but a
	# cheap camera reacts late and overshoots (a damped spring).
	var target := 1.0
	if player and gen and player.camera.global_position.y > -100.0:
		var lum := gen.light_level_near(player.camera.global_position, 3) * 0.35
		if player.flashlight_on:
			lum = maxf(lum, 0.45)
		target = clampf(pow(1.2 / maxf(lum, 0.05), 0.45), 0.8, 2.6)
	_exp_v += (target - _exp) * delta * 5.0
	_exp_v *= exp(-delta * 2.8)
	_exp += _exp_v * delta
	_mat.set_shader_parameter("exposure", _exp)
	# White balance wanders.
	_wb_t -= delta
	if _wb_t <= 0.0:
		_wb_t = _rng.randf_range(3.0, 8.0)
		var w := _rng.randf_range(-0.05, 0.05)
		_wb_target = Vector3(1.0 + w, 1.0, 1.0 - w * 1.2)
	_wb = _wb.lerp(_wb_target, minf(1.0, delta * 0.6))
	_mat.set_shader_parameter("white_balance", _wb)
	# Tape tracking glitches.
	if mode == 2:
		_glitch_t -= delta
		if _glitch_t <= 0.0:
			_glitch_t = _rng.randf_range(5.0, 16.0)
			_glitch = _rng.randf_range(0.5, 1.0)
		_glitch = maxf(_glitch - delta * 2.5, 0.0)
		_mat.set_shader_parameter("glitch", _glitch)
	# Handheld: a slow wander plus jitter, more while running.
	if player:
		var run := clampf(Vector2(player.velocity.x, player.velocity.z).length() / 4.5, 0.0, 1.0)
		var k := 0.004 + 0.01 * run
		_shake_v += Vector2(_rng.randf_range(-1, 1), _rng.randf_range(-1, 1)) * k * 60.0 * delta
		_shake_v -= _shake * delta * 6.0
		_shake_v *= exp(-delta * 3.0)
		_shake += _shake_v * delta
		player.camera.h_offset = _shake.x
		player.camera.v_offset = _shake.y
	# Overlay.
	var blink := fmod(_rec_t, 1.0) < 0.6
	var t := int(_rec_t)
	var stamp := "%02d:%02d:%02d" % [t / 3600, (t / 60) % 60, t % 60]
	_rec.text = ("●" if blink else "  ") + " REC  " + stamp
	if mode == 2:
		var dt := Time.get_datetime_dict_from_system()
		var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
		var h12: int = (int(dt.hour) + 11) % 12 + 1
		_stamp.text = "%s %d %d\n%d:%02d:%02d %s" % [months[int(dt.month) - 1], dt.day, dt.year, h12, dt.minute, dt.second, "AM" if dt.hour < 12 else "PM"]
		_batt.text = "▮▮▮▯" if fmod(_rec_t, 30.0) > 1.0 else "▮▮▯▯"
