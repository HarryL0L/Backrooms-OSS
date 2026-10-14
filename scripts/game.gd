extends Node3D
## Root of the game. Owns the world, player, audio and UI, and runs the
## menu -> loading -> playing -> paused state machine.

enum State { BOOT, MENU, LOADING, PLAYING, PAUSED, EDIT_TOUCH }

const SAVE_PATH := "user://save.cfg"
const MENU_SEED := 7355608
const FIELD_NAME := "Level 10 - The Field"
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
var ripples: WaterRipples
var odd_doors: OddDoors
var field: FieldLevel          # Level 10, only while you're in it
var world_env: WorldEnvironment
var _in_field := false
# Frame-rate watchdog (auto quality): seconds of steady play measured, frames
# counted, and how many times it has stepped quality down this session.
var _perf_t := 0.0
var _perf_frames := 0
var _perf_drops := 0
var _perf_wait := 20.0
var _transition := false

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
	world_env = WorldEnvironment.new()
	env = EnvironmentFactory.make()
	world_env.environment = env
	add_child(world_env)
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
	ripples = WaterRipples.new()
	ripples.material = mats.materials[ChunkBuilder.MAT_WATER]
	ripples.player = player
	add_child(ripples)
	odd_doors = OddDoors.new()
	odd_doors.process_mode = Node.PROCESS_MODE_PAUSABLE
	odd_doors.target = player
	odd_doors.door_entered.connect(_on_odd_door)
	add_child(odd_doors)
	if not (Settings.is_ultra and Settings.ultra_safe_level >= 2):
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
		var on: bool = Settings.get_value("graphics/realtime_lights") and Settings.get_value("graphics/light_highlights")
		fixtures.max_lights = FixtureLights.COUNT if on else 0
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
		ripples.gen = gen
		odd_doors.clear()
		odd_doors.gen = gen
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
	if save.has("field_exit"):
		pos = sg.spawn_position()
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
	if _in_field:
		_leave_field()
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
	if save.has("field_exit"):
		# Saved in the Field: load the Backrooms world (for the way back) at its
		# spawn, then go straight to the Field.
		var sg := WorldGen.new(save.seed)
		_load_world(save.seed, sg.spawn_position(), 0.0, 0.0, func() -> void:
			player.set_flashlight(false)
			_start_playing()
			_enter_field(save.field_exit, save.pos, save.yaw)
			hud.fade_to(0.0, 1.0))
		return
	_load_world(save.seed, save.pos, save.yaw, save.get("pitch", 0.0), func() -> void:
		player.set_flashlight(save.get("flashlight", false))
		_start_playing()
		hud.fade_to(0.0, 1.0))


func _start_playing() -> void:
	state = State.PLAYING
	_perf_wait = 20.0
	_perf_t = 0.0
	_perf_frames = 0
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
	var where: String = FIELD_NAME if _in_field else WorldGen.BIOME_NAMES[gen.biome_at(c.x, c.y)]
	info.text = "%s\nSeed %d  ·  %s explored" % [where, gen.seed_value, _format_time(_play_time)]
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
	if _in_field:
		_leave_field()
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
		_perf_watch(delta)
	if _in_field:
		return
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
	ripples.active = _biome == WorldGen.POOL and gen != null and Settings.get_value("graphics/water_ripples")
	reflection.set_active(_biome == WorldGen.POOL and int(Settings.get_value("graphics/water_reflections")) > 0)


# ----------------------------------------------------------- performance ---

## If play is consistently slow, step the quality preset down (at most twice a
## session, never below Potato). Skips the first seconds after loading and any
## transition, which have legitimately slow frames.
func _perf_watch(delta: float) -> void:
	if not Settings.get_value("graphics/auto_quality") or _transition or _perf_drops >= 2:
		return
	if _perf_wait > 0.0:
		_perf_wait -= delta
		return
	_perf_t += delta
	_perf_frames += 1
	if _perf_t < 15.0:
		return
	var fps := _perf_frames / _perf_t
	_perf_t = 0.0
	_perf_frames = 0
	var cap: int = Settings.get_value("graphics/fps_cap")
	var target := 20.0 if cap == 0 else 26.0
	var preset: int = Settings.get_value("graphics/preset")
	if fps >= target or preset <= 0:
		return
	_perf_drops += 1
	_perf_wait = 10.0
	Settings.apply_preset(preset - 1)
	print("Auto quality: %.1f FPS, lowered to %s" % [fps, Settings.PRESET_NAMES[preset - 1]])
	hud.show_level("Graphics lowered to " + Settings.PRESET_NAMES[preset - 1],
			"The game was running slowly (%d FPS). Settings > Graphics to change." % int(fps))


# ---------------------------------------------------------------- field ---

func _on_odd_door(door: OddDoor) -> void:
	if state != State.PLAYING or _transition or _in_field:
		return
	_transition = true
	player.controls_enabled = false
	await door.open()
	hud.set_fade_color(Color(1.0, 0.98, 0.94))
	await hud.fade_to(1.0, 0.9)
	_enter_field()
	hud.show_level(FIELD_NAME, "Warm wind. Endless grass. The door is gone.")
	await hud.fade_to(0.0, 2.2)
	hud.set_fade_color(Color.BLACK)
	player.controls_enabled = true
	_transition = false


## Swaps the Backrooms out and the Field in. With no arguments it's a fresh
## arrival; a saved game passes the exit door and player position back.
func _enter_field(exit_pos := Vector3.INF, pos := Vector3.INF, yaw := 0.0) -> void:
	_in_field = true
	field = FieldLevel.new()
	field.process_mode = Node.PROCESS_MODE_PAUSABLE
	field.player = player
	add_child(field)
	field.build(gen.hashi(int(_play_time * 10.0), gen.seed_value, 811), exit_pos)
	field.exit_entered.connect(_on_field_exit)
	world_env.environment = field.environment
	chunks.visible = false
	chunks.process_mode = Node.PROCESS_MODE_DISABLED
	odd_doors.visible = false
	odd_doors.process_mode = Node.PROCESS_MODE_DISABLED
	if fixtures:
		fixtures.max_lights = 0
		fixtures._place()
	ripples.active = false
	reflection.set_active(false)
	ambience.outdoor = true
	player.field_mode = true
	player.set_flashlight(false)
	player.camera.far = 9000.0
	if pos.is_finite():
		player.teleport(pos, yaw)
	else:
		player.teleport(field.arrival(), 0.0)


func _leave_field() -> void:
	_in_field = false
	if field:
		field.queue_free()
		field = null
	world_env.environment = env
	chunks.visible = true
	chunks.process_mode = Node.PROCESS_MODE_PAUSABLE
	odd_doors.visible = true
	odd_doors.process_mode = Node.PROCESS_MODE_PAUSABLE
	ambience.outdoor = false
	player.field_mode = false
	player.camera.far = 95.0
	_apply_settings()


func _on_field_exit() -> void:
	if state != State.PLAYING or _transition:
		return
	_transition = true
	player.controls_enabled = false
	await field.open_exit()
	await hud.fade_to(1.0, 0.8)
	_leave_field()
	# Back into the Backrooms, but somewhere else entirely.
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var g := gen
	var c := g.cell_of(Vector3.ZERO)
	for _try in 200:
		var a := rng.randf() * TAU
		var d := rng.randf_range(300.0, 900.0) / WorldGen.CELL
		c = Vector2i(int(cos(a) * d), int(sin(a) * d)) + g.spawn_cell
		var b := g.biome_at(c.x, c.y)
		if b != WorldGen.POOL and not g.is_solid(c.x, c.y, b) and not g.pool_noise(c.x, c.y):
			break
	var pos := Vector3((c.x + 0.5) * WorldGen.CELL, 0.05, (c.y + 0.5) * WorldGen.CELL)
	_load_world(g.seed_value, pos, rng.randf() * TAU, 0.0, func() -> void:
		_start_playing()
		_transition = false
		hud.fade_to(0.0, 1.5))


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
	if _in_field:
		cf.set_value("save", "field_exit", field.exit_pos)
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
