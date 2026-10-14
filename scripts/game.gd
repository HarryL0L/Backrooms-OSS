extends Node3D
## Root of the game. Owns the world, player, audio and UI, and runs the
## menu -> loading -> playing -> paused state machine.

enum State { BOOT, MENU, LOADING, PLAYING, PAUSED, EDIT_TOUCH }

const SAVE_PATH := "user://save.cfg"
const MENU_SEED := 7355608
const SUBTITLES := [
	"Mono-yellow wallpaper. Damp carpet. The hum.",
	"Warm water. White tiles. Nobody else.",
	"Concrete, puddles and flickering tubes.",
	"The lights have died here. Use your flashlight.",
	"Narrow tunnels. Hot pipes. Something drips in the dark.",
]

var state := State.BOOT
var gen: WorldGen
var mats: WorldMaterials
var chunks: ChunkManager
var player: Player
var ambience: Ambience
var env: Environment
var reflection: WaterReflection
var fixtures: FixtureLights

var hud: HUD
var touch: TouchControls
var main_menu: Control
var pause_menu: Control
var settings_menu: SettingsMenu
var touch_editor: Control
var _editor_slider: HSlider
var _editor_label: Label

var _using_touch := false
var _biome := -1
var _biome_candidate := -1
var _biome_timer := 0.0
var _scan_t := 0.0
var _fog_color := Color.BLACK
var _fog_density := 0.03
var _play_time := 0.0
var _autosave_t := 0.0
var _settings_return := State.MENU
var _loading_done: Callable
var _world_seed := -1


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	print("Backrooms-OSS renderer: ", RenderingServer.get_current_rendering_method(),
			" (configured ", ProjectSettings.get_setting("rendering/renderer/rendering_method"), ")")
	mats = WorldMaterials.new()
	var we := WorldEnvironment.new()
	env = EnvironmentFactory.make()
	we.environment = env
	add_child(we)
	chunks = ChunkManager.new()
	chunks.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(chunks)
	player = Player.new()
	player.process_mode = Node.PROCESS_MODE_PAUSABLE
	add_child(player)
	player.set_physics_process(false)
	ambience = Ambience.new()
	add_child(ambience)
	reflection = WaterReflection.new()
	reflection.source = player.camera
	reflection.material = mats.materials[ChunkBuilder.MAT_WATER]
	add_child(reflection)
	if Settings.is_ultra and Settings.ultra_safe_level < 2:
		fixtures = FixtureLights.new()
		fixtures.target = player
		add_child(fixtures)
	_build_ui()
	if Diagnostics.enabled():
		var diag := Diagnostics.new()
		diag.game = self
		add_child(diag)
	_using_touch = Settings.is_mobile
	Settings.changed.connect(_apply_settings)
	_apply_settings()
	_enter_menu()


# ------------------------------------------------------------------- UI ---

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UITheme.make()
	layer.add_child(root)
	hud = HUD.new()
	root.add_child(hud)
	touch = TouchControls.new()
	touch.player = player
	touch.visible = false
	touch.button_pressed.connect(_on_touch_button)
	root.add_child(touch)
	player.touch = touch
	main_menu = Menus.main_menu(self)
	root.add_child(main_menu)
	pause_menu = Menus.pause_menu(self)
	pause_menu.hide()
	root.add_child(pause_menu)
	settings_menu = SettingsMenu.new()
	settings_menu.hide()
	settings_menu.closed.connect(_on_settings_closed)
	settings_menu.edit_touch_layout.connect(_open_touch_editor)
	root.add_child(settings_menu)
	touch_editor = _build_touch_editor()
	touch_editor.hide()
	root.add_child(touch_editor)
	touch.add_exclusion(touch_editor)
	# The HUD fade must cover menus during transitions.
	root.move_child(hud, -1)


func _build_touch_editor() -> Control:
	var p := PanelContainer.new()
	p.set_anchors_preset(Control.PRESET_CENTER_TOP)
	p.grow_horizontal = Control.GROW_DIRECTION_BOTH
	p.offset_top = 12
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	p.add_child(v)
	_editor_label = Label.new()
	_editor_label.text = "Drag a control to move it"
	_editor_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(_editor_label)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	v.add_child(h)
	var l := Label.new()
	l.text = "Size"
	h.add_child(l)
	_editor_slider = HSlider.new()
	_editor_slider.min_value = 0.5
	_editor_slider.max_value = 2.0
	_editor_slider.step = 0.05
	_editor_slider.custom_minimum_size = Vector2(220, 44)
	_editor_slider.value_changed.connect(touch.set_selected_scale)
	h.add_child(_editor_slider)
	var reset := Button.new()
	reset.text = "Reset"
	reset.pressed.connect(func() -> void:
		Settings.reset_touch_layout()
		touch.queue_redraw())
	h.add_child(reset)
	var done := Button.new()
	done.text = "Done"
	done.pressed.connect(_close_touch_editor)
	h.add_child(done)
	touch.selection_changed.connect(func(id: String) -> void:
		_editor_label.text = "Selected: " + id.capitalize()
		_editor_slider.set_value_no_signal(touch.element_scale(id)))
	return p


func _apply_settings() -> void:
	chunks.view_radius = int(Settings.get_value("graphics/view_distance"))
	chunks.set_shadows(Settings.get_value("graphics/flashlight_shadows"))
	env.glow_enabled = Settings.get_value("graphics/bloom")
	if fixtures:
		fixtures.max_lights = FixtureLights.COUNT if Settings.get_value("graphics/realtime_lights") else 0
		if fixtures.gen:
			fixtures._place()
	mats.materials[ChunkBuilder.MAT_HALO].set_shader_parameter("strength", 0.07 if Settings.get_value("graphics/halos") else 0.0)
	if Settings.is_ultra:
		EnvironmentFactory.apply_ultra(env, Settings.get_value("graphics/ssr"), Settings.get_value("graphics/ssao"),
				Settings.get_value("graphics/ssil"), Settings.get_value("graphics/volumetric_fog"))
	reflection.scale = [0.0, 0.34, 0.5][clampi(Settings.get_value("graphics/water_reflections"), 0, 2)]
	_update_reflection()
	env.tonemap_exposure = Settings.get_value("graphics/brightness")
	_update_touch_visibility()


func _update_touch_visibility() -> void:
	var mode: int = Settings.get_value("controls/touch_mode")
	var show := (mode == 1) or (mode == 0 and _using_touch)
	touch.visible = (state == State.PLAYING and show) or state == State.EDIT_TOUCH
	if not touch.visible:
		touch.reset_state()


# ---------------------------------------------------------------- world ---

func _load_world(seed_value: int, pos: Vector3, yaw: float, pitch: float, done: Callable) -> void:
	state = State.LOADING
	hud.set_fade(1.0)
	hud.set_loading(true, "Noclipping...")
	player.controls_enabled = false
	player.set_physics_process(false)
	if seed_value != _world_seed:
		_world_seed = seed_value
		gen = WorldGen.new(seed_value)
		chunks.setup(gen, mats)
		player.gen = gen
		ambience.attach(gen, player)
		if fixtures:
			fixtures.gen = gen
		_biome = -1
	chunks.target = player
	player.teleport(pos, yaw, pitch)
	_loading_done = done


func _check_loading() -> void:
	if chunks.is_area_ready(player.global_position, 1) and ambience.is_ready():
		hud.set_loading(false)
		player.set_physics_process(true)
		var cb := _loading_done
		_loading_done = Callable()
		if cb.is_valid():
			cb.call()


func _enter_menu() -> void:
	get_tree().paused = false
	pause_menu.hide()
	settings_menu.hide()
	main_menu.hide()
	ambience.enabled = true
	ambience.set_muffled(false)
	_release_mouse()
	var save := _read_save()
	var cont := main_menu.find_child("Continue", true, false) as Button
	cont.visible = not save.is_empty()
	var sv: int = save.get("seed", MENU_SEED)
	var sg := WorldGen.new(sv)
	var pos: Vector3 = save.get("pos", sg.spawn_position())
	_load_world(sv, pos, save.get("yaw", 0.0), 0.0, func() -> void:
		state = State.MENU
		player.set_physics_process(false)
		main_menu.show()
		if Settings.is_ultra:
			get_tree().create_timer(6.0).timeout.connect(Settings.mark_ultra_stable)
			get_tree().create_timer(3.0).timeout.connect(_check_ultra_rendering)
			var msg := Settings.ultra_guard_message()
			if msg != "":
				hud.show_level("Safe mode", msg)
		hud.fade_to(0.0, 1.2)
		_focus_first(main_menu))


## Detects the Forward+ driver corruption (see RenderCheck) once per launch
## and points the player to the standard build.
func _check_ultra_rendering() -> void:
	if state != State.MENU or Diagnostics.enabled():
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	var dup := RenderCheck.row_block_duplication(img)
	print("Ultra render check: duplication score %.3f" % dup)
	if dup < 0.8:
		return
	# Known cause (Mali-G77, driver r32p1): any real-time light node makes Forward+
	# corrupt the frame. Switch to the shader flashlight and no light nodes, then re-check.
	if Settings.get_value("graphics/realtime_lights"):
		Settings.set_value("graphics/realtime_lights", false)
		for i in 4:
			await RenderingServer.frame_post_draw
		img = get_viewport().get_texture().get_image()
		dup = RenderCheck.row_block_duplication(img) if img else 1.0
		print("Ultra render check after disabling real-time lights: %.3f" % dup)
		if dup < 0.8:
			hud.show_level("Compatibility mode", "This GPU driver garbles real-time lights, so they were switched off. The flashlight still works.")
			return
	var dlg := AcceptDialog.new()
	dlg.title = "Graphics driver problem"
	dlg.dialog_text = ("This phone's GPU driver (%s) corrupts the image with the Ultra renderer.\n\n"
		+ "This is a driver bug, not your settings. Please install the standard Backrooms-OSS.apk instead,\n"
		+ "which has the same game and works on this device.") % RenderingServer.get_video_adapter_name()
	dlg.dialog_autowrap = true
	dlg.min_size = Vector2i(900, 300)
	main_menu.add_child(dlg)
	dlg.popup_centered()


func new_game() -> void:
	if state != State.MENU:
		return
	var edit := main_menu.find_child("SeedEdit", true, false) as LineEdit
	var text := edit.text.strip_edges()
	var seed_value := randi() & 0x7FFFFFFF
	if text != "":
		seed_value = text.to_int() if text.is_valid_int() else (text.hash() & 0x7FFFFFFF)
	main_menu.hide()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))
	_play_time = 0.0
	await hud.fade_to(1.0, 0.6)
	_world_seed = -1
	var g := WorldGen.new(seed_value)
	_load_world(seed_value, g.spawn_position(), PI * 0.25, 0.0, func() -> void:
		player.set_flashlight(false)
		_intro())


func _intro() -> void:
	ambience.enabled = false
	await hud.story([
		"You noclipped out of reality.",
		"The smell of old, moist carpet. The endless hum of fluorescent lights.",
		"Rooms without end. Find a way out.",
	], 2.2)
	ambience.enabled = true
	_start_playing()
	await hud.fade_to(0.0, 2.5)


func continue_game() -> void:
	if state != State.MENU:
		return
	var save := _read_save()
	if save.is_empty():
		return
	main_menu.hide()
	_play_time = save.get("time", 0.0)
	await hud.fade_to(1.0, 0.4)
	_load_world(save.seed, save.pos, save.yaw, save.get("pitch", 0.0), func() -> void:
		player.set_flashlight(save.get("flashlight", false))
		_start_playing()
		hud.fade_to(0.0, 1.0))


func _start_playing() -> void:
	state = State.PLAYING
	_biome = -1
	player.controls_enabled = true
	ambience.enabled = true
	_capture_mouse_if_desktop()
	_update_touch_visibility()


func pause() -> void:
	if state != State.PLAYING:
		return
	state = State.PAUSED
	get_tree().paused = true
	ambience.set_muffled(true)
	_release_mouse()
	_update_touch_visibility()
	var c := gen.cell_of(player.global_position)
	var info := pause_menu.find_child("Info", true, false) as Label
	info.text = "%s\nSeed %d  ·  %s explored" % [WorldGen.BIOME_NAMES[gen.biome_at(c.x, c.y)], gen.seed_value, _format_time(_play_time)]
	pause_menu.show()
	_focus_first(pause_menu)
	_write_save()


func resume() -> void:
	if state != State.PAUSED:
		return
	pause_menu.hide()
	settings_menu.hide()
	get_tree().paused = false
	ambience.set_muffled(false)
	state = State.PLAYING
	_capture_mouse_if_desktop()
	_update_touch_visibility()


func exit_to_menu() -> void:
	_write_save()
	pause_menu.hide()
	get_tree().paused = false
	await hud.fade_to(1.0, 0.5)
	_enter_menu()


func open_settings() -> void:
	_settings_return = state
	main_menu.hide()
	pause_menu.hide()
	settings_menu.open()


func _on_settings_closed() -> void:
	if _settings_return == State.MENU:
		main_menu.show()
		_focus_first(main_menu)
	else:
		pause_menu.show()
		_focus_first(pause_menu)


func _open_touch_editor() -> void:
	settings_menu.hide()
	state = State.EDIT_TOUCH
	touch.editing = true
	touch.selected = ""
	_editor_label.text = "Drag a control to move it"
	touch_editor.show()
	_update_touch_visibility()


func _close_touch_editor() -> void:
	touch.editing = false
	touch_editor.hide()
	state = State.PAUSED if _settings_return == State.PAUSED else State.MENU
	_update_touch_visibility()
	settings_menu.open()


func _on_touch_button(id: String) -> void:
	if state != State.PLAYING:
		return
	match id:
		"jump":
			player.queue_jump()
		"crouch":
			player.toggle_crouch()
		"flashlight":
			player.toggle_flashlight()
		"pause":
			pause()


# ---------------------------------------------------------------- input ---

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not _using_touch:
			_using_touch = true
			_update_touch_visibility()
	elif event is InputEventKey or event is InputEventJoypadButton \
			or (event is InputEventMouseButton and event.device != InputEvent.DEVICE_ID_EMULATION) \
			or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		if _using_touch:
			_using_touch = false
			_update_touch_visibility()


func _unhandled_input(event: InputEvent) -> void:
	match state:
		State.PLAYING:
			if event.is_action_pressed("pause"):
				get_viewport().set_input_as_handled()
				pause()
			elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION \
					and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		State.PAUSED:
			if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
				if not settings_menu.visible:
					get_viewport().set_input_as_handled()
					resume()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_WM_GO_BACK_REQUEST:
			if state == State.PLAYING:
				pause()
			elif state == State.PAUSED and settings_menu.visible:
				settings_menu.close()
			elif state == State.PAUSED:
				resume()
			elif state == State.EDIT_TOUCH:
				_close_touch_editor()
			elif state == State.MENU and settings_menu.visible:
				settings_menu.close()
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT:
			if state == State.PLAYING:
				pause()
		NOTIFICATION_WM_CLOSE_REQUEST:
			if state == State.PLAYING or state == State.PAUSED:
				_write_save()


func _capture_mouse_if_desktop() -> void:
	if not Settings.is_mobile and not _using_touch:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _focus_first(menu: Control) -> void:
	if _using_touch:
		return
	await get_tree().process_frame
	for b in menu.find_children("*", "Button", true, false):
		if b.is_visible_in_tree():
			b.grab_focus()
			return


# ---------------------------------------------------------------- frame ---

func _process(delta: float) -> void:
	RenderingServer.global_shader_parameter_set("world_time", Ambience.world_time())
	if state == State.LOADING:
		_check_loading()
		return
	if gen == null:
		return
	if state == State.MENU:
		player.yaw += delta * 0.04
		player.add_look(0.0, 0.0)
		player.rotation.y = player.yaw
	if state == State.PLAYING:
		_play_time += delta
		_autosave_t += delta
		if _autosave_t > 30.0:
			_autosave_t = 0.0
			_write_save()
		hud.set_stamina(player.stamina, player.exhausted)
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_track_biome()
	var k := 1.0 - exp(-1.2 * delta)
	env.fog_light_color = env.fog_light_color.lerp(_fog_color, k)
	env.fog_density = lerpf(env.fog_density, _fog_density, k)
	env.fog_light_energy = lerpf(env.fog_light_energy, EnvironmentFactory.FOG_ENERGY[maxi(_biome, 0)], k)
	# Anything past the loaded chunks shows the background: make it the fog
	# colour so distant openings fade into haze instead of black holes.
	env.background_color = env.fog_light_color * env.fog_light_energy
	if env.volumetric_fog_enabled:
		env.volumetric_fog_albedo = env.volumetric_fog_albedo.lerp(_fog_color, k)
		env.volumetric_fog_density = lerpf(env.volumetric_fog_density, EnvironmentFactory.VOL_DENSITY[maxi(_biome, 0)], k)


func _track_biome() -> void:
	var c := gen.cell_of(player.global_position)
	var b := gen.biome_at(c.x, c.y)
	if _biome < 0:
		_set_biome(b, state == State.PLAYING)
		return
	if b == _biome:
		_biome_candidate = -1
		return
	if b != _biome_candidate:
		_biome_candidate = b
		_biome_timer = 0.0
	_biome_timer += 0.25
	if _biome_timer >= 0.75:
		_set_biome(b, true)


func _set_biome(b: int, announce: bool) -> void:
	_biome = b
	_biome_candidate = -1
	_fog_color = EnvironmentFactory.FOG[b]
	_fog_density = EnvironmentFactory.FOG_DENSITY[b]
	_update_reflection()
	if announce and state == State.PLAYING:
		hud.show_level(WorldGen.BIOME_NAMES[b], SUBTITLES[b])


func _update_reflection() -> void:
	reflection.set_active(_biome == WorldGen.POOL and int(Settings.get_value("graphics/water_reflections")) > 0)


# ----------------------------------------------------------------- save ---

func _write_save() -> void:
	if gen == null or (state != State.PLAYING and state != State.PAUSED):
		return
	var cf := ConfigFile.new()
	cf.set_value("save", "seed", gen.seed_value)
	cf.set_value("save", "pos", player.global_position)
	cf.set_value("save", "yaw", player.yaw)
	cf.set_value("save", "pitch", player.pitch)
	cf.set_value("save", "flashlight", player.flashlight_on)
	cf.set_value("save", "time", _play_time)
	cf.save(SAVE_PATH)


func _read_save() -> Dictionary:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) != OK or not cf.has_section_key("save", "seed"):
		return {}
	var d := {}
	for k in cf.get_section_keys("save"):
		d[k] = cf.get_value("save", k)
	if not (d.get("pos") is Vector3):
		return {}
	return d


static func _format_time(t: float) -> String:
	var m := int(t / 60.0)
	if m < 60:
		return "%d min" % m
	return "%d h %02d min" % [m / 60, m % 60]
