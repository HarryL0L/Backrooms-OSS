class_name HUD
extends Control
## In-game overlays: film grain / vignette, level title cards, stamina hint,
## FPS counter, loading screen and fades. Deliberately minimal - no crosshair.

var _post: ColorRect
var _lens: ColorRect
var _eye: ColorRect
var _eye_mat: ShaderMaterial
var _copy: BackBufferCopy
var _post_mat: ShaderMaterial
var _title: Label
var _subtitle: Label
var _fps: Label
var _stamina: ProgressBar
var _fade: ColorRect
var _scare: ColorRect
var _scare_mat: ShaderMaterial
var _loading: Control
var _loading_label: Label
var _story: Label
var _prompt: Label
var _title_t := 0.0
var _vignette_boost := 0.0
var _realistic := false
## Raindrops arriving on the body cam's lens a second (set by a level where
## it rains: LucidRain.lens_rate). They sit, some run down leaving a wet
## track, and dry off; shaders/eye_lens.gdshader draws them.
static var lens_rain := 0.0
## Set to start with a dry lens (a teleport).
static var lens_wipe := false
const LENS_DROPS := 12
var _drops: Array[Dictionary] = []
var _drop_rng := RandomNumberGenerator.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lens = ColorRect.new()
	_lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var lm := ShaderMaterial.new()
	lm.shader = load("res://shaders/lens.gdshader")
	_lens.material = lm
	# Lens + grain live on their own canvas layer below the UI, so they only
	# affect the 3D view (not menus or touch buttons).
	var fx := CanvasLayer.new()
	fx.layer = 1
	add_child(fx)
	# Human eye camera: the edges of the wide view pulled back in (first,
	# so the lens effects and grain go on top).
	_eye = ColorRect.new()
	_eye.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_eye.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eye_mat = ShaderMaterial.new()
	_eye_mat.shader = load("res://shaders/eye_lens.gdshader")
	_eye.material = _eye_mat
	fx.add_child(_eye)
	var fx2 := CanvasLayer.new()
	fx2.layer = 2
	add_child(fx2)
	_copy = BackBufferCopy.new()          # the lens reads the eye pass's output
	_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	fx2.add_child(_copy)
	fx2.add_child(_lens)
	_post = ColorRect.new()
	_post.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/post_overlay.gdshader")
	_post.material = _post_mat
	fx2.add_child(_post)
	_title = _label(40, HORIZONTAL_ALIGNMENT_CENTER)
	_title.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_title.offset_top = 90
	_subtitle = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_subtitle.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	_subtitle.offset_top = 145
	_subtitle.add_theme_color_override("font_color", Color(0.85, 0.82, 0.7))
	for l in [_title, _subtitle]:
		l.modulate.a = 0.0
	_fps = _label(16, HORIZONTAL_ALIGNMENT_LEFT)
	_fps.position = Vector2(12, 8)
	_stamina = ProgressBar.new()
	_stamina.show_percentage = false
	_stamina.max_value = 1.0
	_stamina.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_stamina.offset_left = -110
	_stamina.offset_right = 110
	_stamina.offset_top = -30
	_stamina.offset_bottom = -24
	_stamina.grow_horizontal = Control.GROW_DIRECTION_BOTH
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.1)
	var fg := StyleBoxFlat.new()
	fg.bg_color = Color(0.95, 0.9, 0.7, 0.6)
	_stamina.add_theme_stylebox_override("background", bg)
	_stamina.add_theme_stylebox_override("fill", fg)
	_stamina.modulate.a = 0.0
	_stamina.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_stamina)
	_prompt = _label(18, HORIZONTAL_ALIGNMENT_CENTER)
	_prompt.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_prompt.offset_left = -300
	_prompt.offset_right = 300
	_prompt.offset_top = 46
	_prompt.offset_bottom = 74
	_prompt.add_theme_color_override("font_color", Color(0.95, 0.92, 0.8, 0.85))
	_prompt.visible = false
	_story = _label(24, HORIZONTAL_ALIGNMENT_CENTER)
	_story.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_story.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_story.modulate.a = 0.0
	# Jumpscare overlay: a white flash and torn static (see scare()).
	_scare = ColorRect.new()
	_scare.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_scare.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scare_mat = ShaderMaterial.new()
	_scare_mat.shader = load("res://shaders/scare.gdshader")
	_scare.material = _scare_mat
	_scare.visible = false
	add_child(_scare)
	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)
	move_child(_story, -1)
	_loading = Control.new()
	_loading.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_loading.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_loading_label = _label(20, HORIZONTAL_ALIGNMENT_RIGHT)
	_loading_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_loading_label.offset_left = -500
	_loading_label.offset_top = -60
	_loading_label.offset_right = -32
	_loading_label.offset_bottom = -24
	_loading_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_loading_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	remove_child(_loading_label)
	_loading.add_child(_loading_label)
	add_child(_loading)
	_loading.visible = false
	Settings.changed.connect(_apply_settings)
	_apply_settings()


func _label(fs: int, align: HorizontalAlignment) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", fs)
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	add_child(l)
	return l


func _apply_settings() -> void:
	var ps1: bool = Settings.get_value("graphics/ps1")
	# The found footage camera brings its own grain, vignette and lens.
	var footage: bool = int(Settings.get_value("graphics/found_footage")) > 0 and not ps1
	_post.visible = Settings.get_value("graphics/film_grain") and not footage
	# Full-resolution grain and lens warping would smear the PS1 pixels.
	# Realistic (film grain is off in its preset; if switched on): only a
	# faint noise and a light vignette.
	_realistic = Settings.is_realistic()
	_post_mat.set_shader_parameter("grain", 0.0 if ps1 else (0.014 if _realistic else 0.05))
	_lens.visible = Settings.get_value("graphics/lens_fx") and not ps1 and not footage
	_fps.visible = Settings.get_value("graphics/show_fps")
	_eye.visible = Player.human_eye()
	# Realistic: the body cam's sensor noise in the dark (free: this pass
	# reads the whole image anyway), instead of grain over everything.
	_eye_mat.set_shader_parameter("noise", 0.06 if _realistic else 0.0)
	# A full-screen copy costs a phone a whole extra pass: only when the lens
	# needs the body cam's output.
	_copy.visible = _eye.visible and _lens.visible


## Drops on the body cam's lens: Poisson arrivals at lens_rain a second, a
## random size (out of focus, a drop 2-3 mm across on the window in front of
## the lens covers 6-14 % of the picture's height), most just sit and dry
## off in 6-14 s, about a third start to run down after a second or three,
## wobbling and leaving a fading wet track.
func _lens_drops(delta: float) -> void:
	if lens_wipe:
		lens_wipe = false
		_drops.clear()
		_eye_mat.set_shader_parameter("drop_n", 0)
	if lens_rain <= 0.0 and _drops.is_empty():
		return
	if lens_rain > 0.0 and _drop_rng.randf() < 1.0 - exp(-lens_rain * delta):
		if _drops.size() >= LENS_DROPS:
			_drops.pop_front()
		_drops.append({"x": _drop_rng.randf_range(0.06, 0.94), "y": _drop_rng.randf_range(0.04, 0.85),
				"r": _drop_rng.randf_range(0.03, 0.07), "age": 0.0, "life": _drop_rng.randf_range(6.0, 14.0),
				"run": _drop_rng.randf_range(1.0, 3.0) if _drop_rng.randf() < 0.35 else INF, "v": 0.0, "y0": 0.0,
				"seed": _drop_rng.randf() * 10.0})
	var d4 := PackedVector4Array()
	var t4 := PackedVector4Array()
	var i := 0
	while i < _drops.size():
		var d := _drops[i]
		d.age += delta
		if d.age > d.life or d.y > 1.1:
			_drops.remove_at(i)
			continue
		if d.age > d.run:
			if d.v == 0.0:
				d.y0 = d.y
			d.v = minf(d.v + delta * 0.15, 0.12)
			d.y += d.v * delta
			d.x += sin(d.age * 3.0 + d.seed) * 0.004 * delta
		var a := minf(d.age / 0.15, 1.0) * clampf((d.life - d.age) / 2.0, 0.0, 1.0)
		d4.append(Vector4(d.x, d.y, d.r * (0.8 if d.v > 0.0 else 1.0), a))
		t4.append(Vector4(d.y0, a * 0.6 if d.v > 0.0 else 0.0, d.seed, 0.0))
		i += 1
	_eye_mat.set_shader_parameter("drop_n", d4.size())
	if not d4.is_empty():
		_eye_mat.set_shader_parameter("drops", d4)
		_eye_mat.set_shader_parameter("trails", t4)


## What pressing Use would do, under the middle of the view ("" hides it).
func set_prompt(text: String) -> void:
	_prompt.text = text
	_prompt.visible = text != ""


func show_level(title: String, subtitle: String) -> void:
	_title.text = title
	_subtitle.text = subtitle
	_title_t = 5.0


func set_loading(on: bool, text := "") -> void:
	_loading.visible = on
	_loading_label.text = text


func fade_to(alpha: float, time: float) -> void:
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", alpha, time)
	await tw.finished


## Jumpscare overlay: flash 0..1 (white), noise 0..1 (static and tearing).
func scare(flash: float, noise: float) -> void:
	_scare.visible = flash > 0.001 or noise > 0.001
	_scare_mat.set_shader_parameter("flash", flash)
	_scare_mat.set_shader_parameter("noise", noise)


func set_fade(alpha: float) -> void:
	_fade.color.a = alpha


## Colour of the full-screen fade (black normally, white for the Field door).
func set_fade_color(c: Color) -> void:
	_fade.color = Color(c.r, c.g, c.b, _fade.color.a)


func story(lines: Array, per_line := 2.6) -> void:
	for line in lines:
		_story.text = line
		var tw := create_tween()
		tw.tween_property(_story, "modulate:a", 1.0, 0.8)
		tw.tween_interval(per_line)
		tw.tween_property(_story, "modulate:a", 0.0, 0.8)
		await tw.finished


func set_stamina(v: float, exhausted: bool) -> void:
	_stamina.value = v
	var target := 0.0 if v > 0.98 else 1.0
	_stamina.modulate.a = lerpf(_stamina.modulate.a, target, 0.08)
	_vignette_boost = lerpf(_vignette_boost, 0.35 if exhausted else 0.0, 0.05)


func _process(delta: float) -> void:
	if _title_t > 0.0:
		_title_t -= delta
		var a := clampf(minf(5.0 - _title_t, _title_t) / 1.2, 0.0, 1.0)
		_title.modulate.a = a
		_subtitle.modulate.a = a * 0.9
	if _fps.visible:
		_fps.text = "%d FPS" % Engine.get_frames_per_second()
	if _eye.visible:
		var vs := get_viewport_rect().size
		_eye_mat.set_shader_parameter("aspect", vs.x / maxf(vs.y, 1.0))
		_lens_drops(delta)
	if _post.visible:
		_post_mat.set_shader_parameter("vignette", (0.12 if _realistic else 0.42) + _vignette_boost)
	if _loading.visible:
		_loading_label.modulate.a = 0.5 + 0.5 * sin(Time.get_ticks_msec() / 300.0)
