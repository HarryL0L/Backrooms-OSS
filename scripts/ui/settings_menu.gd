class_name SettingsMenu
extends Control
## Tabbed settings screen: graphics, audio, controls, key/gamepad bindings and
## touch layout. All values are applied and saved immediately.

signal closed
signal edit_touch_layout

var _tabs: TabContainer
var _bind_buttons := {}     # "action/slot" -> Button
var _waiting := ""          # "action/slot" waiting for input
var _first_focus: Control
var _controls := {}         # setting key -> [control, value label or null]


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = 24
	panel.offset_bottom = -24
	add_child(panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	panel.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := UITheme.title_label("SETTINGS", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 52)
	back.pressed.connect(close)
	top.add_child(back)
	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	v.add_child(_tabs)
	_build_graphics()
	_build_audio()
	_build_controls()
	_build_bindings()
	_build_touch()
	Settings.changed.connect(_refresh_bindings)
	Settings.changed.connect(_refresh_controls)


func open() -> void:
	show()
	_waiting = ""
	_refresh_bindings()
	await get_tree().process_frame
	if _first_focus:
		_first_focus.grab_focus()


func close() -> void:
	_waiting = ""
	hide()
	closed.emit()


func _unhandled_input(event: InputEvent) -> void:
	if visible and _waiting == "" and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


# ------------------------------------------------------------- builders ---

func _page(name_: String) -> VBoxContainer:
	var sc := ScrollContainer.new()
	sc.name = name_
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_tabs.add_child(sc)
	var m := MarginContainer.new()
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_theme_constant_override("margin_left", 12)
	m.add_theme_constant_override("margin_right", 24)
	m.add_theme_constant_override("margin_top", 12)
	sc.add_child(m)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 10)
	m.add_child(v)
	return v


func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 300
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(l)
	parent.add_child(h)
	return h


func _slider(parent: Control, label: String, key: String, lo: float, hi: float, step: float, fmt := "%.2f") -> void:
	var h := _row(parent, label)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = step
	s.value = Settings.get_value(key)
	s.custom_minimum_size = Vector2(320, 44)
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var val := Label.new()
	val.custom_minimum_size.x = 80
	val.text = fmt % s.value
	s.value_changed.connect(func(x: float) -> void:
		val.text = fmt % x
		Settings.set_value(key, x if step < 1.0 or typeof(Settings.get_value(key)) == TYPE_FLOAT else int(x)))
	h.add_child(s)
	h.add_child(val)
	_controls[key] = [s, val, fmt]
	if _first_focus == null:
		_first_focus = s


func _toggle(parent: Control, label: String, key: String) -> void:
	var h := _row(parent, label)
	var c := CheckButton.new()
	c.button_pressed = Settings.get_value(key)
	c.custom_minimum_size = Vector2(120, 44)
	c.toggled.connect(func(on: bool) -> void: Settings.set_value(key, on))
	h.add_child(c)
	_controls[key] = [c]
	if _first_focus == null:
		_first_focus = c


func _option(parent: Control, label: String, key: String, items: Array) -> void:
	var h := _row(parent, label)
	var o := OptionButton.new()
	for it in items:
		o.add_item(it)
	o.selected = int(Settings.get_value(key))
	o.custom_minimum_size = Vector2(320, 48)
	o.item_selected.connect(func(i: int) -> void: Settings.set_value(key, i))
	h.add_child(o)
	_controls[key] = [o]
	if _first_focus == null:
		_first_focus = o


func _heading(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_color_override("font_color", UITheme.ACCENT)
	l.add_theme_font_size_override("font_size", 22)
	parent.add_child(l)


func _note(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.DIM)
	l.add_theme_font_size_override("font_size", 17)
	parent.add_child(l)


func _build_graphics() -> void:
	var p := _page("Graphics")
	var h := _row(p, "Quality preset")
	for i in Settings.PRESETS.size():
		var b := Button.new()
		b.text = Settings.PRESET_NAMES[i]
		b.custom_minimum_size = Vector2(96, 48)
		b.pressed.connect(func() -> void: Settings.apply_preset(i))
		h.add_child(b)
	_toggle(p, "PS1 style (low-res pixels, wobbly vertices, dithered colour)", "graphics/ps1")
	_slider(p, "PS1 resolution (lines)", "graphics/ps1_lines", 160, 480, 16, "%d")
	_slider(p, "Render scale", "graphics/render_scale", 0.4, 1.0, 0.05, "%.2f")
	_toggle(p, "FSR upscaling (when scale < 1)", "graphics/fsr")
	_option(p, "Anti-aliasing", "graphics/aa", ["Off", "MSAA 2x", "MSAA 4x", "SMAA", "FXAA"])
	_slider(p, "View distance (chunks)", "graphics/view_distance", 2, 6, 1, "%d")
	_option(p, "Frame rate cap", "graphics/fps_cap", ["30 FPS", "60 FPS", "Unlimited"])
	_slider(p, "Field of view", "graphics/fov", 60, 100, 1, "%d")
	_slider(p, "Brightness", "graphics/brightness", 0.5, 2.0, 0.05, "%.2f")
	_toggle(p, "Bloom", "graphics/bloom")
	_option(p, "Water reflections", "graphics/water_reflections", ["Off (fake)", "Low", "High"])
	_toggle(p, "Interactive water ripples & splashes", "graphics/water_ripples")
	_option(p, "Found footage camera (looks like real recorded footage)", "graphics/found_footage", ["Off", "Phone camera", "Camcorder (tape)"])
	_toggle(p, "Film grain & vignette", "graphics/film_grain")
	_toggle(p, "Lens effects (chromatic aberration)", "graphics/lens_fx")
	_toggle(p, "Light halos (haze glow)", "graphics/halos")
	_toggle(p, "Auto-lower quality if the game runs slowly", "graphics/auto_quality")
	_toggle(p, "Per-pixel lighting (off = faster world generation)", "graphics/lightmaps")
	_toggle(p, "Real-time light highlights (shine on tiles and water)", "graphics/light_highlights")
	_toggle(p, "Real-time lights (off = shader flashlight, for buggy GPU drivers)", "graphics/realtime_lights")
	_toggle(p, "Flashlight shadows", "graphics/flashlight_shadows")
	_toggle(p, "Head bob", "graphics/head_bob")
	_toggle(p, "Entities (something in the walls, someone in the dark, the Window Dresser)", "gameplay/entities")
	_toggle(p, "Show FPS", "graphics/show_fps")
	if Settings.is_ultra:
		_toggle(p, "Screen-space reflections (Ultra)", "graphics/ssr")
		_toggle(p, "Ambient occlusion SSAO (Ultra)", "graphics/ssao")
		_toggle(p, "Indirect light SSIL (Ultra)", "graphics/ssil")
		_toggle(p, "Volumetric fog (Ultra)", "graphics/volumetric_fog")
	else:
		_note(p, "SSR, SSAO, SSIL and volumetric fog are available in the Ultra build (Forward+ renderer, for high-end devices).")
	_note(p, "Lighting is pre-baked into the world as it generates, so the biggest performance levers are render scale, view distance and flashlight shadows.")
	_heading(p, "Experimental")
	if Settings.is_ultra:
		_toggle(p, "VoxelGI bounce light (real-time colour bleeding and indirect shadows)", "graphics/voxel_gi")
		_note(p, "Light from the flashlight and nearby fixtures bounces off walls and floors. Re-bakes around you as you walk (a short hitch). Heavy: for strong GPUs.")
	else:
		_note(p, "VoxelGI bounce light needs the Forward+ renderer (desktop builds). On phones, Photoreal bakes bounce light into the world instead.")


func _build_audio() -> void:
	var p := _page("Audio")
	_slider(p, "Master volume", "audio/master", 0.0, 1.0, 0.05)
	_slider(p, "Ambience (hum, room tone, water)", "audio/ambience", 0.0, 1.0, 0.05)
	_slider(p, "Effects (footsteps, sounds)", "audio/effects", 0.0, 1.0, 0.05)


func _build_controls() -> void:
	var p := _page("Controls")
	_slider(p, "Mouse sensitivity", "controls/mouse_sens", 0.1, 4.0, 0.05)
	_slider(p, "Touch look sensitivity", "controls/touch_sens", 0.1, 4.0, 0.05)
	_slider(p, "Gamepad look sensitivity", "controls/pad_sens", 0.1, 4.0, 0.05)
	_toggle(p, "Invert look Y", "controls/invert_y")
	_toggle(p, "Crouch is a toggle", "controls/crouch_toggle")
	_toggle(p, "Sprint is a toggle (keyboard)", "controls/sprint_toggle")
	_note(p, "Keyboard, mouse and gamepads work on Android too. Click the game view to capture the mouse; press Pause to release it.")


func _build_bindings() -> void:
	var p := _page("Bindings")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 8)
	p.add_child(grid)
	for h in ["Action", "Primary", "Secondary", "Gamepad"]:
		var l := Label.new()
		l.text = h
		l.add_theme_color_override("font_color", UITheme.ACCENT)
		grid.add_child(l)
	for a in Settings.ACTIONS:
		var l := Label.new()
		l.text = Settings.ACTION_LABELS[a]
		l.custom_minimum_size.x = 200
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(l)
		for slot in ["0", "1", "pad"]:
			var b := Button.new()
			b.custom_minimum_size = Vector2(190, 46)
			b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			var key: String = a + "/" + slot
			b.pressed.connect(func() -> void: _begin_capture(key))
			_bind_buttons[key] = b
			grid.add_child(b)
	var reset := Button.new()
	reset.text = "Reset to defaults"
	reset.custom_minimum_size = Vector2(260, 50)
	reset.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	reset.pressed.connect(Settings.reset_bindings)
	p.add_child(reset)
	_note(p, "Select a slot, then press a key, mouse button or gamepad button. Movement also always works with the left stick.")
	_refresh_bindings()


func _build_touch() -> void:
	var p := _page("Touch")
	_option(p, "On-screen controls", "controls/touch_mode", ["Automatic", "Always show", "Never show"])
	_toggle(p, "Fixed joystick (stays where it's placed; off = appears under your thumb)", "controls/joystick_fixed")
	_slider(p, "Opacity", "controls/touch_opacity", 0.1, 1.0, 0.05)
	_slider(p, "Look sensitivity", "controls/touch_sens", 0.1, 4.0, 0.05)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 12)
	p.add_child(h)
	var edit := Button.new()
	edit.text = "Edit layout"
	edit.custom_minimum_size = Vector2(220, 52)
	edit.pressed.connect(func() -> void: edit_touch_layout.emit())
	h.add_child(edit)
	var reset := Button.new()
	reset.text = "Reset layout"
	reset.custom_minimum_size = Vector2(220, 52)
	reset.pressed.connect(Settings.reset_touch_layout)
	h.add_child(reset)
	_note(p, "Automatic hides the on-screen controls while a keyboard, mouse or gamepad is in use. In the editor, drag any control to move it and use the slider to resize it.")


func _refresh_controls() -> void:
	for key in _controls:
		var e: Array = _controls[key]
		var v: Variant = Settings.get_value(key)
		var c: Control = e[0]
		if c is HSlider:
			(c as HSlider).set_value_no_signal(v)
			(e[1] as Label).text = e[2] % v
		elif c is CheckButton:
			(c as CheckButton).set_pressed_no_signal(v)
		elif c is OptionButton:
			(c as OptionButton).selected = int(v)


# ------------------------------------------------------------- bindings ---

func _refresh_bindings() -> void:
	for key in _bind_buttons:
		var parts: PackedStringArray = key.split("/")
		var b: Button = _bind_buttons[key]
		if key == _waiting:
			b.text = "Press..."
			continue
		if parts[1] == "pad":
			b.text = Settings.binding_label(Settings.pad.get(parts[0], ""))
		else:
			b.text = Settings.binding_label(Settings.keys[parts[0]][int(parts[1])])


func _begin_capture(key: String) -> void:
	_waiting = key
	_refresh_bindings()


func _input(event: InputEvent) -> void:
	if _waiting == "" or not visible:
		return
	var parts: PackedStringArray = _waiting.split("/")
	var action := parts[0]
	var is_pad := parts[1] == "pad"
	var accepted := false
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_ESCAPE and action != "pause":
			_waiting = ""
			_refresh_bindings()
			get_viewport().set_input_as_handled()
			return
		if not is_pad:
			Settings.set_key_binding(action, int(parts[1]), event)
			accepted = true
	elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION and not is_pad:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			return
		Settings.set_key_binding(action, int(parts[1]), event)
		accepted = true
	elif event is InputEventJoypadButton and event.pressed and is_pad:
		Settings.set_pad_binding(action, event)
		accepted = true
	if accepted:
		var key := _waiting
		_waiting = ""
		_refresh_bindings()
		get_viewport().set_input_as_handled()
		var b: Button = _bind_buttons[key]
		b.grab_focus.call_deferred()
