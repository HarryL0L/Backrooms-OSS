extends Node3D
## Root of the game. Owns the world, player, audio and UI, and runs the
## menu -> loading -> playing -> paused state machine.

enum State { BOOT, MENU, LOADING, PLAYING, PAUSED, EDIT_TOUCH }

const SAVE_PATH := "user://save.cfg"
const MENU_SEED := 7355608
const FIELD_NAME := "Level 10 - The Field"
const SUBTITLES := [
	"Yellow wallpaper. Damp carpet. The hum of the lights.",
	"Warm water. White tiles. Nobody else.",
	"A damp warehouse. Racks of boxes nobody ordered.",
	"The lights have died here. Use your flashlight.",
	"Narrow tunnels. Hot pipes. Something drips in the dark.",
	"Low concrete, oil stains, tube lights. Some of the keys are still in.",
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
var lining: LiningEntity
var hall_figure: HallFigure
var crawler: CrawlerEntity
var attendant: AttendantEntity
var jumpscare: Jumpscare
var presence: LobbyPresence      # heard, never seen
var stairs: Stairwells
## Which floor you're on (0 = where you started; below is negative).
var _floor := 0
var retro: RetroView
var path_tracer: PathTracer
var net: Net
var mp_menu: MultiplayerMenu
var _remotes := {}               # peer id -> RemotePlayer
var radar: Radar
var _net_t := 0.0
var _built_lightmaps := true
var _built_rays := true
var odd_doors: OddDoors
var details: LobbyDetails
var _photoreal := false
var footage: FoundFootage
var vgi: VoxelGIRig             # experimental VoxelGI (Forward+ only)
var _built_lm_scale := 1.0
var _built_detail := false
var _adapt := 1.0          # Photoreal eye adaptation (exposure multiplier)
var field: FieldLevel          # the Meadow, only while you're in it
var mall: MallLevel            # the Dead Mall, only while you're in it
var _in_mall := false
## A side level (SideLevel), only while you're in one, and its id.
var side: SideLevel
var side_id := ""
var _in_side := false
## The side levels' ways in, around you in the Backrooms (and in the mall).
var entrances: LevelEntrances
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
## A real mouse has been used (e.g. one plugged into a phone).
var _mouse_seen := false
var _biome := -1
var _biome_candidate := -1
var _biome_timer := 0.0
var _scan_t := 0.0
var _fog_color := Color.BLACK
var _fog_density := 0.03
var _play_time := 0.0
## Which Field / Dead Mall you're in: made from the door you came through, so
## two players who take the same door are in the same one.
var _side_seed := 0
var _autosave_t := 0.0
var _settings_return := State.MENU
var _loading_done: Callable
var _warm_list: Array[Material] = []
var _warm_next := 0
var _warm_holder: Node3D
var _warmed := {}            # "ps1/lightmaps" -> true once its shaders are compiled
var _warmed_hazmat := false
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
	radar = Radar.new()
	player.camera.add_child(radar)
	ambience = Ambience.new()
	add_child(ambience)
	net = Net.new()
	net.name = "Net"
	add_child(net)
	net.world_info = _net_world_info
	net.joined.connect(_on_net_joined)
	net.join_failed.connect(func(reason: String) -> void:
		if mp_menu:
			mp_menu.set_status(reason))
	net.disconnected.connect(_on_net_disconnected)
	net.peer_state.connect(_on_peer_state)
	net.peer_left.connect(_remove_remote)
	net.roster_changed.connect(_on_roster_changed)
	retro = RetroView.new()
	retro.source = player.camera
	add_child(retro)
	reflection = WaterReflection.new()
	reflection.source = player.camera
	reflection.material = mats.materials[ChunkBuilder.MAT_WATER]
	add_child(reflection)
	ripples = WaterRipples.new()
	ripples.material = mats.materials[ChunkBuilder.MAT_WATER]
	ripples.player = player
	add_child(ripples)
	lining = LiningEntity.new()
	lining.process_mode = Node.PROCESS_MODE_PAUSABLE
	lining.player = player
	lining.ambience = ambience
	add_child(lining)
	hall_figure = HallFigure.new()
	hall_figure.process_mode = Node.PROCESS_MODE_PAUSABLE
	hall_figure.player = player
	hall_figure.ambience = ambience
	add_child(hall_figure)
	crawler = CrawlerEntity.new()
	crawler.hall_figure = hall_figure
	hall_figure.crawler = crawler
	_walker(crawler)
	attendant = AttendantEntity.new()
	attendant.caught.connect(_on_caught)
	crawler.lunged.connect(_on_crawler_lunge)
	jumpscare = Jumpscare.new()
	jumpscare.player = player
	add_child(jumpscare)
	_walker(attendant)
	presence = LobbyPresence.new()
	presence.process_mode = Node.PROCESS_MODE_PAUSABLE
	presence.player = player
	presence.ambience = ambience
	add_child(presence)
	odd_doors = OddDoors.new()
	odd_doors.process_mode = Node.PROCESS_MODE_PAUSABLE
	odd_doors.target = player
	odd_doors.door_entered.connect(_on_odd_door)
	add_child(odd_doors)
	entrances = LevelEntrances.new()
	entrances.process_mode = Node.PROCESS_MODE_PAUSABLE
	entrances.target = player
	add_child(entrances)
	# The entrances call us when used (use_level_entrance).
	add_to_group(LevelEntrance.HOST_GROUP)
	details = LobbyDetails.new()
	details.process_mode = Node.PROCESS_MODE_PAUSABLE
	details.target = player
	details.chunks = chunks
	details.floor_gave_way.connect(_on_floor_gave_way)
	details.noclipped.connect(_on_noclipped)
	stairs = Stairwells.new()
	stairs.process_mode = Node.PROCESS_MODE_PAUSABLE
	stairs.player = player
	stairs.chunks = chunks
	stairs.floor_step.connect(_on_floor_step)
	add_child(stairs)
	add_child(details)
	path_tracer = PathTracer.new()
	path_tracer.game = self
	add_child(path_tracer)
	if not (Settings.is_ultra and Settings.ultra_safe_level >= 2):
		fixtures = FixtureLights.new()
		fixtures.target = player
		add_child(fixtures)
	if Settings.is_ultra:
		vgi = VoxelGIRig.new()
		vgi.process_mode = Node.PROCESS_MODE_PAUSABLE
		vgi.target = player
		vgi.source = chunks
		add_child(vgi)
		chunks.initial_area_ready.connect(vgi.invalidate)
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
	jumpscare.hud = hud
	root.add_child(hud)
	footage = FoundFootage.new()
	footage.player = player
	add_child(footage)
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
	mp_menu = MultiplayerMenu.new()
	mp_menu.hide()
	mp_menu.net = net
	mp_menu.closed.connect(func() -> void:
		net.browse(false)
		main_menu.show()
		_focus_first(main_menu))
	mp_menu.host_requested.connect(_host_game)
	mp_menu.join_requested.connect(_join_game)
	root.add_child(mp_menu)
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
		var on: bool = Settings.light_nodes() and Settings.get_value("graphics/light_highlights")
		fixtures.max_lights = FixtureLights.COUNT if on else 0
		if fixtures.gen:
			fixtures._place()
	# The halos hide behind walls by reading the depth buffer, which comes out
	# wrong with MSAA 2x on the Mobile renderer (glows show through walls in a
	# band at eye level); 4x and the other modes are fine.
	var halos: bool = Settings.get_value("graphics/halos") and not (int(Settings.get_value("graphics/aa")) == 1 and not Settings.is_ultra)
	mats.materials[ChunkBuilder.MAT_HALO].set_shader_parameter("strength", 0.07 if halos else 0.0)
	if Settings.is_ultra:
		EnvironmentFactory.apply_ultra(env, Settings.get_value("graphics/ssr"), Settings.get_value("graphics/ssao"),
				Settings.get_value("graphics/ssil"), Settings.get_value("graphics/volumetric_fog"))
	reflection.scale = [0.0, 0.34, 0.5][clampi(Settings.get_value("graphics/water_reflections"), 0, 2)]
	_update_reflection()
	env.tonemap_exposure = Settings.get_value("graphics/brightness")
	var photoreal: bool = Settings.get_value("graphics/photoreal") and not Settings.get_value("graphics/ps1")
	EnvironmentFactory.photoreal_grade(env, photoreal or (path_tracer != null and path_tracer.active))
	_photoreal = photoreal
	footage.set_mode(0 if Settings.get_value("graphics/ps1") else int(Settings.get_value("graphics/found_footage")))
	retro.lines = int(Settings.get_value("graphics/ps1_lines"))
	retro.set_active(Settings.get_value("graphics/ps1"))
	_update_gi()
	# Lighting mode changed (PS1 style or per-pixel lighting toggled): rebuild
	# the loaded chunks in place.
	if ChunkBuilder.lightmaps != _built_lightmaps or ChunkBuilder.god_rays != _built_rays or ChunkBuilder.lm_scale != _built_lm_scale \
			or ChunkBuilder.detail != _built_detail:
		_built_lightmaps = ChunkBuilder.lightmaps
		_built_rays = ChunkBuilder.god_rays
		_built_lm_scale = ChunkBuilder.lm_scale
		_built_detail = ChunkBuilder.detail
		chunks.rebuild()
	_update_touch_visibility()


## Experimental VoxelGI: on in the Backrooms and the mall (not the open
## Field, which has a sun and no walls to bounce from).
func _update_gi() -> void:
	if vgi == null:
		return
	var on: bool = Settings.get_value("graphics/voxel_gi") and not Settings.get_value("graphics/ps1") and not _in_field
	chunks.set_gi(on)
	if fixtures:
		fixtures.set_gi(on)
	vgi.source = mall if _in_mall else (side if _in_side else chunks)
	vgi.set_active(on)


func _update_touch_visibility() -> void:
	var mode: int = Settings.get_value("controls/touch_mode")
	var show := (mode == 1) or (mode == 0 and _using_touch)
	touch.visible = (state == State.PLAYING and show) or state == State.EDIT_TOUCH
	if not touch.visible:
		touch.reset_state()


# ---------------------------------------------------------------- world ---

const SAME_FLOOR := -9999


## Loads a world (`floor_index`: which floor; by default the one you're on).
func _load_world(seed_value: int, pos: Vector3, yaw: float, pitch: float, done: Callable, floor_index := SAME_FLOOR) -> void:
	state = State.LOADING
	hud.set_fade(1.0)
	hud.set_loading(true, "Noclipping...")
	player.controls_enabled = false
	player.set_physics_process(false)
	var f := _floor if floor_index == SAME_FLOOR else floor_index
	if seed_value != _world_seed or gen == null or f != gen.floor_index:
		_world_seed = seed_value
		_floor = f
		stairs.clear()
		_use_gen(WorldGen.new(seed_value, f), false)
	chunks.target = player
	player.teleport(pos, yaw, pitch)
	_loading_done = done
	_warm_shaders()


## Points everything at a world. `swap`: a floor change on the stairs (the
## old floor's chunks just go; nothing waits).
func _use_gen(g: WorldGen, swap: bool) -> void:
	gen = g
	if swap:
		chunks.swap_world(g)
	else:
		chunks.setup(g, mats)
	player.gen = g
	ambience.attach(g, player)
	if fixtures:
		fixtures.gen = g
	ripples.gen = g
	odd_doors.clear()
	odd_doors.gen = g
	entrances.clear()
	entrances.gen = g
	details.clear()
	details.gen = g
	footage.gen = g
	lining.gen = g
	hall_figure.gen = g
	for w in _walkers():
		w.gen = g
	presence.gen = g
	lining.odd_doors = odd_doors
	stairs.gen = g
	stairs.set_floor(g.floor_index)
	if not swap:
		_biome = -1             # (around a stairwell it's the Lobby on every floor)


## Half a floor up or down a stairwell: you're moved by one floor height (the
## shaft is identical, so you can't tell) and the next floor is swapped in.
func _on_floor_step(dir: int) -> void:
	if state != State.PLAYING or _transition or _away():
		return
	_floor += dir
	player.shift_y(-dir * WorldGen.FLOOR_H)
	_use_gen(WorldGen.new(gen.seed_value, _floor), true)
	hud.show_level("Floor %s" % WorldGen.floor_name(_floor),
			"The air is heavier down here." if dir < 0 else "It's quieter up here.")


## Draws every world material once, tiny and right in front of the camera,
## while the loading screen is up: weak GPUs compile shaders on first use,
## which otherwise shows up as a hitch the first time you meet each surface.
## One material per frame, so a slow shader compiler (Mali) never freezes the
## screen for long, and the loading text shows how far along it is. Shaders
## stay compiled for the session, so later loads skip this.
func _warm_shaders() -> void:
	_warm_list.clear()
	_warm_next = 0
	var key := "%s/%s" % [Settings.get_value("graphics/ps1"), ChunkBuilder.lightmaps]
	if _warmed.has(key) and _warmed_hazmat:
		return
	if not _warmed.has(key):
		_warmed[key] = true
		_warm_list.append_array(mats.materials)
		_warm_list.append_array(hall_figure.warm_materials())
	# Other players and the entities.
	if not _warmed_hazmat:
		_warmed_hazmat = true
		_warm_list.append_array(HazmatModel.warm_materials())
		_warm_list.append_array(EntityBody.warm_materials())
		_warm_list.append_array(Radar.warm_materials())
	_warm_list = _warm_list.filter(func(m: Material) -> bool: return m != null)
	_warm_holder = Node3D.new()
	player.camera.add_child(_warm_holder)


## Adds the next warm-up quad; true once every material has been drawn.
func _warm_step() -> bool:
	if _warm_holder == null:
		return true
	if _warm_next >= _warm_list.size():
		# Give the last one a frame to be drawn before clearing up.
		_warm_holder.queue_free()
		_warm_holder = null
		return false
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.004, 0.004)
	mi.mesh = q
	mi.material_override = _warm_list[_warm_next]
	mi.position = Vector3((_warm_next % 8) * 0.005 - 0.02, (_warm_next / 8) * 0.005 - 0.01, -0.3)
	_warm_holder.add_child(mi)
	_warm_next += 1
	return false


func _check_loading() -> void:
	var warmed := _warm_step()
	var area := chunks.is_area_ready(player.global_position, 1)
	if warmed and area and ambience.is_ready():
		hud.set_loading(false)
		player.set_physics_process(true)
		var cb := _loading_done
		_loading_done = Callable()
		if cb.is_valid():
			cb.call()
		return
	var parts := []
	if not warmed:
		parts.append("preparing surfaces %d/%d" % [mini(_warm_next, _warm_list.size()), _warm_list.size()])
	if not area:
		parts.append("building rooms")
	if not ambience.is_ready():
		parts.append("making sounds")
	hud.set_loading(true, "Noclipping...\n" + ", ".join(parts))


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
	if save.has("field_exit") or save.has("side"):
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
		_focus_first(main_menu), int(save.get("floor", 0)))


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
	_leave_side_levels()
	_world_seed = -1
	var g := WorldGen.new(seed_value)
	_load_world(seed_value, g.spawn_position(), PI * 0.25, 0.0, func() -> void:
		player.set_flashlight(false)
		_intro(), 0)


func _intro() -> void:
	ambience.enabled = false
	await hud.story([
		"You stepped through a wall that wasn't there.",
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
	_side_seed = int(save.get("side_seed", 0))
	await hud.fade_to(1.0, 0.4)
	if save.has("side") and SideLevels.exists(String(save.side)):
		# Saved in a side level: load the Backrooms (for the way back), then
		# go straight back in, where you were, as it was.
		var lg := WorldGen.new(save.seed)
		_load_world(save.seed, lg.spawn_position(), 0.0, 0.0, func() -> void:
			player.set_flashlight(save.get("flashlight", false))
			_start_playing()
			await _enter_side(String(save.side), save.pos, save.yaw, save.get("side_state", {}))
			player.set_stance(int(save.get("stance", 0)))
			hud.fade_to(0.0, 1.0), int(save.get("floor", 0)))
		return
	if save.get("mall", false):
		# Saved in the Dead Mall: load the Backrooms (for the way back), then
		# go straight to the mall.
		var mg := WorldGen.new(save.seed)
		_load_world(save.seed, mg.spawn_position(), 0.0, 0.0, func() -> void:
			player.set_flashlight(save.get("flashlight", false))
			_start_playing()
			await _enter_mall(save.pos, save.yaw)
			hud.fade_to(0.0, 1.0), int(save.get("floor", 0)))
		return
	if save.has("field_exit"):
		# Saved in the Field: load the Backrooms world (for the way back) at its
		# spawn, then go straight to the Field.
		var sg := WorldGen.new(save.seed)
		_load_world(save.seed, sg.spawn_position(), 0.0, 0.0, func() -> void:
			player.set_flashlight(false)
			_start_playing()
			_enter_field(save.field_exit, save.pos, save.yaw)
			hud.fade_to(0.0, 1.0), int(save.get("floor", 0)))
		return
	_load_world(save.seed, save.pos, save.yaw, save.get("pitch", 0.0), func() -> void:
		player.set_flashlight(save.get("flashlight", false))
		_start_playing()
		hud.fade_to(0.0, 1.0), int(save.get("floor", 0)))


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
	# Online the world keeps going for everyone else.
	get_tree().paused = not net.active
	ambience.set_muffled(true)
	_release_mouse()
	_update_touch_visibility()
	var c := gen.cell_of(player.global_position)
	var info := pause_menu.find_child("Info", true, false) as Label
	var where: String = FIELD_NAME if _in_field else (MallLevel.NAME if _in_mall else WorldGen.BIOME_NAMES[gen.biome_at(c.x, c.y)])
	if _in_side:
		where = SideLevels.info(side_id).name
	info.text = "%s\nSeed %d  ·  %s explored" % [where, gen.seed_value, _format_time(_play_time)]
	if net.active:
		var nums := []
		for id in net.roster:
			nums.append("%02d" % int(net.roster[id].number))
		info.text += "\nOnline (%s): players %s  ·  the game keeps running" % ["hosting" if net.is_host else "joined", ", ".join(nums)]
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
	_end_session()
	pause_menu.hide()
	get_tree().paused = false
	await hud.fade_to(1.0, 0.5)
	_leave_side_levels()
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
		"radar":
			radar.shown = not radar.shown
		"use":
			_use()


# ---------------------------------------------------------------- input ---

func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventScreenDrag:
		if not _using_touch:
			_using_touch = true
			_update_touch_visibility()
		return
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device != InputEvent.DEVICE_ID_EMULATION:
		_mouse_seen = true
		# A mouse on a phone: hide Android's pointer as soon as it's used
		# in game (on desktop the mouse is already captured while playing).
		if state == State.PLAYING and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
			_capture_mouse()
	if event is InputEventKey or event is InputEventJoypadButton \
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
			elif event.is_action_pressed("interact"):
				get_viewport().set_input_as_handled()
				_use()
			elif event.is_action_pressed("radar") and net.active:
				get_viewport().set_input_as_handled()
				radar.shown = not radar.shown
			elif event is InputEventMouseButton and event.pressed and event.device != InputEvent.DEVICE_ID_EMULATION \
					and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
				_capture_mouse()
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
	if (not Settings.is_mobile or _mouse_seen) and not _using_touch:
		_capture_mouse()


## Captures the mouse (hides the pointer, mouse look). On Android this is
## pointer capture (Android 8+); where it isn't available the pointer is at
## least hidden.
func _capture_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN


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


# ------------------------------------------------------------------ use ---

## What you're looking at that you can use (a car door, a switch):
## [node, id, label] or [].
var _use_target := []
## A line from the last thing used ("The battery's flat."), shown for a while.
var _use_hint := ""
var _use_hint_t := 0.0


func _update_use() -> void:
	_use_target = []
	var cam := player.camera
	var o := cam.global_position
	var f := -cam.global_basis.z
	var best := INF
	for n in get_tree().get_nodes_in_group("usable"):
		var node := n as Node3D
		if node.global_position.distance_squared_to(o) > 36.0:
			continue
		for t in node.use_targets(player):
			var d: Vector3 = t[1] - o
			var along := d.dot(f)
			if along < 0.15 or along > 2.4:
				continue
			# How far off the middle of the view, allowing more up close.
			var off := (d - f * along).length() / (0.1 + along * 0.12)
			if off < 1.0 and off + along * 0.2 < best:
				best = off + along * 0.2
				_use_target = [node, t[0], t[2]]
	var label := ""
	_use_hint_t -= get_process_delta_time()
	if _use_hint_t > 0.0:
		label = _use_hint
	elif not _use_target.is_empty():
		label = _use_target[2]
		if not _using_touch:
			var key := Settings.binding_label(Settings.keys["interact"][0])
			if Input.get_connected_joypads().size() > 0 and not _mouse_seen:
				key = Settings.binding_label(Settings.pad.get("interact", ""))
			label = "[%s]  %s" % [key, label]
	hud.set_prompt(label)
	touch.use_available = not _use_target.is_empty()


func _use() -> void:
	if not _use_target.is_empty() and is_instance_valid(_use_target[0]):
		var said: String = _use_target[0].use(_use_target[1], player)
		if said != "":
			_use_hint = said
			_use_hint_t = 2.5
		_update_use()


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
		_update_use()
		_perf_watch(delta)
	elif not _use_target.is_empty():
		_use_target = []
		hud.set_prompt("")
		touch.use_available = false
	if net.active and (state == State.PLAYING or state == State.PAUSED):
		_net_t -= delta
		if _net_t <= 0.0:
			_net_t = 0.05
			net.send_state({"p": player.global_position, "y": player.yaw, "x": player.pitch,
				"v": player.velocity, "f": player.flashlight_on, "c": player.crouching or player.crawling,
				"g": player.is_on_floor(), "fl": _in_field, "ml": _in_mall, "fr": _floor,
				"sd": _side_seed, "s": player.seated or player._ride_t >= 0.0, "t": Time.get_ticks_msec(),
				"sl": side_id if _in_side else "", "cr": player.crawling})
	_update_radar(delta)
	lining.allowed = state == State.PLAYING and not _away() and not _transition
	hall_figure.allowed = lining.allowed
	for w in _walkers():
		w.allowed = lining.allowed
	presence.allowed = lining.allowed
	if _away():
		return
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.25
		_track_biome()
	_eye_adaptation(delta)
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


## Photoreal: like eyes (or a camera's auto exposure), the image slowly
## brightens in the dark and quickly settles when you step into bright light.
func _eye_adaptation(delta: float) -> void:
	var base: float = Settings.get_value("graphics/brightness")
	if path_tracer.active:
		base *= PathTracer.EXPOSURE
	if not _photoreal:
		_adapt = 1.0
		env.tonemap_exposure = base
		return
	var lum := gen.light_level_near(player.camera.global_position, 3) * 0.35
	if player.in_stairwell:
		lum = 0.45                 # the shaft has its own bulbs
	if player.flashlight_on:
		lum = maxf(lum, 0.35)
	var target := clampf(pow(1.3 / maxf(lum, 0.05), 0.35), 0.85, 2.0)
	var rate := 0.35 if target > _adapt else 1.6
	_adapt = move_toward(_adapt, target, delta * rate * absf(target - _adapt) + delta * 0.02)
	env.tonemap_exposure = base * _adapt


## The experimental path tracer switched on or off (PathTracer): its
## Cycles-like grade (AgX, the Photoreal one) goes with it.
func path_tracing_changed(on: bool) -> void:
	EnvironmentFactory.photoreal_grade(env, on or _photoreal)


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
	reflection.set_active(_biome == WorldGen.POOL and int(Settings.get_value("graphics/water_reflections")) > 0
			and not Settings.get_value("graphics/ps1"))


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
	if state != State.PLAYING or _transition or _away():
		return
	_side_seed = gen.hashi(floori(door.global_position.x * 4.0), floori(door.global_position.z * 4.0), 811 + _floor) & 0x7FFFFFFF
	if door.mall:
		_go_to_mall(door)
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
	field.build(gen.hashi(_side_seed, gen.seed_value, 811), exit_pos)
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
	_update_gi()
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


# ------------------------------------------------------------- dead mall ---

func _away() -> bool:
	return _in_field or _in_mall or _in_side


func _leave_side_levels() -> void:
	if _in_field:
		_leave_field()
	if _in_mall:
		_leave_mall()
	if _in_side:
		_leave_side()


func _go_to_mall(door: OddDoor) -> void:
	_transition = true
	player.controls_enabled = false
	await door.open()
	await hud.fade_to(1.0, 1.1)
	await _enter_mall()
	hud.show_level(MallLevel.NAME, "Closed for years. The music is still playing.")
	await hud.fade_to(0.0, 2.2)
	player.controls_enabled = true
	_transition = false


## Swaps the Backrooms out and the Dead Mall in (a fresh arrival unless a
## saved position is given). Compiles the mall's shaders behind the fade.
func _enter_mall(pos := Vector3.INF, yaw := 0.0) -> void:
	_in_mall = true
	mall = MallLevel.new()
	mall.process_mode = Node.PROCESS_MODE_PAUSABLE
	mall.player = player
	add_child(mall)
	mall.build(gen.hashi(_side_seed, gen.seed_value, 977))
	mall.exit_entered.connect(_on_mall_exit)
	entrances.place_in_mall(mall)       # side levels' ways in (the hospital lift...)
	world_env.environment = mall.environment
	chunks.visible = false
	chunks.process_mode = Node.PROCESS_MODE_DISABLED
	odd_doors.visible = false
	odd_doors.process_mode = Node.PROCESS_MODE_DISABLED
	if fixtures:
		fixtures.max_lights = 0
		fixtures._place()
	ripples.active = false
	reflection.set_active(false)
	player.mall_mode = true
	player.camera.far = 140.0
	_update_gi()
	if pos.is_finite():
		player.teleport(pos, yaw)
	else:
		var t := mall.arrival()
		player.teleport(t.origin + Vector3(0, 0.05, 0), t.basis.get_euler().y)
	await _warm_now(MallLevel.warm_materials())


func _leave_mall() -> void:
	_in_mall = false
	if mall:
		mall.queue_free()
		mall = null
	world_env.environment = env
	chunks.visible = true
	chunks.process_mode = Node.PROCESS_MODE_PAUSABLE
	odd_doors.visible = true
	odd_doors.process_mode = Node.PROCESS_MODE_PAUSABLE
	player.mall_mode = false
	player.camera.far = 95.0
	_apply_settings()


func _on_mall_exit() -> void:
	if state != State.PLAYING or _transition:
		return
	_transition = true
	player.controls_enabled = false
	await mall.open_exit()
	await hud.fade_to(1.0, 0.8)
	_leave_mall()
	_return_somewhere_else()


# ----------------------------------------------------------- side levels ---
# The side levels (SideLevel, see scripts/world/levels/README.md): reached
# through an entrance (LevelEntrance, put in the world by LevelEntrances),
# left by one of their exits: back into the Backrooms somewhere else, or on
# into another side level (a chain). Like the Dead Mall they live far below
# (SideLevel.LEVEL_Y) and the Backrooms is hidden while you're in one.

## An entrance was used (LevelEntrance calls everything in its HOST_GROUP).
func use_level_entrance(e: LevelEntrance) -> void:
	if not SideLevels.exists(e.dest):
		push_warning("No side level '%s'" % e.dest)
		return
	enter_side_level(e.dest, e)


## Into side level `id`: through entrance `from` (its ride in first) when
## given. Two players who take the same entrance get the same level.
func enter_side_level(id: String, from: LevelEntrance = null) -> void:
	if state != State.PLAYING or _transition or _in_side or _in_field:
		return
	_transition = true
	player.controls_enabled = false
	if from:
		var p := from.global_position
		if _in_mall:
			_side_seed = gen.hashi(_side_seed & 0xFFFFF, floori(p.z * 4.0), 1302) & 0x7FFFFFFF
		else:
			_side_seed = gen.hashi(floori(p.x * 4.0), floori(p.z * 4.0), 1301 + _floor) & 0x7FFFFFFF
		await from.enter(player)
	else:
		_side_seed = gen.hashi(id.hash() & 0xFFFF, _floor, 1305) & 0x7FFFFFFF
	await hud.fade_to(1.0, 0.9)
	if _in_mall:
		_leave_mall()
	await _enter_side(id)
	_announce_side(id)
	await hud.fade_to(0.0, 1.6)
	player.controls_enabled = true
	_transition = false


func _announce_side(id: String) -> void:
	var info := SideLevels.info(id)
	hud.show_level(info.name, info.intro)


## Dev / test harnesses: straight into side level `id`, as if through a door
## where you stand (from inside another side level too).
func debug_enter_side(id: String) -> void:
	if not _in_side:
		await enter_side_level(id)
		return
	if _transition:
		return
	_transition = true
	await hud.fade_to(1.0, 0.4)
	_leave_side()
	_side_seed = gen.hashi(id.hash() & 0xFFFF, _floor, 1305) & 0x7FFFFFFF
	await _enter_side(id)
	_announce_side(id)
	await hud.fade_to(0.0, 0.6)
	player.controls_enabled = true
	_transition = false


## Swaps the Backrooms out and side level `id` in (a fresh arrival, or where
## a saved game left you with the level's saved state). Compiles its shaders
## behind the fade.
func _enter_side(id: String, pos := Vector3.INF, yaw := 0.0, saved := {}) -> void:
	_in_side = true
	side_id = id
	side = SideLevels.create(id)
	side.name = "Side_" + id
	side.process_mode = Node.PROCESS_MODE_PAUSABLE
	side._setup(player, id)
	add_child(side)
	side.build(gen.hashi(_side_seed, gen.seed_value, 1301) & 0x7FFFFFFF)
	if not saved.is_empty():
		side.load_state(saved)
	side.exit_entered.connect(_on_side_exit)
	side.player_caught.connect(_on_side_caught)
	side.player_fell.connect(_on_side_fell)
	if side.environment == null:
		side.environment = side.make_environment()
	world_env.environment = side.environment
	for n in _backrooms_nodes():
		n.visible = false
		n.process_mode = Node.PROCESS_MODE_DISABLED
	if fixtures:
		fixtures.max_lights = 0
		fixtures._place()
	ripples.active = false
	reflection.set_active(false)
	# The Backrooms' hum and noises stay quiet (the level brings its own).
	ambience.outdoor = true
	ambience.reverb_override = side.reverb()
	player.side_mode = true
	player.side = side
	player.camera.far = side.camera_far()
	player.camera.cull_mask &= ~SideLevel.FEED_LAYER
	_update_gi()
	if pos.is_finite():
		player.teleport(pos, yaw)
	else:
		var t := side.arrival()
		player.teleport(t.origin + Vector3(0, 0.05, 0), SideLevel._yaw_of(t))
		if side.wants_flashlight():
			player.set_flashlight(true)
	side.on_enter()
	player.snap_stance()
	var warm := side.warm_materials()
	warm.append_array(SideLevel.base_warm_materials())
	warm.append_array(LevelEntrance.warm_materials())
	await _warm_now(warm)


## What's hidden (and stopped) while you're in a side level.
func _backrooms_nodes() -> Array[Node3D]:
	return [chunks, odd_doors, entrances, details, stairs]


func _leave_side() -> void:
	_in_side = false
	if side:
		side.on_leave()
		side._teardown()
		side.queue_free()
		side = null
	side_id = ""
	world_env.environment = env
	for n in _backrooms_nodes():
		n.visible = true
		n.process_mode = Node.PROCESS_MODE_PAUSABLE
	ambience.outdoor = false
	ambience.reverb_override = {}
	player.side_mode = false
	player.side = null
	player.force_crawl = false
	player.can_climb = true
	player.camera.far = 95.0
	player.camera.cull_mask |= SideLevel.FEED_LAYER
	player.camera.h_offset = 0.0
	player.camera.v_offset = 0.0
	_apply_settings()


## Through a side level's exit: back into the Backrooms somewhere else, or
## (`to` another level's id) straight on into that one.
func _on_side_exit(to: String) -> void:
	if state != State.PLAYING or _transition or not _in_side:
		return
	_transition = true
	player.controls_enabled = false
	await side.open_exit()
	await hud.fade_to(1.0, 0.8)
	_leave_side()
	if to != "" and SideLevels.exists(to):
		_side_seed = gen.hashi(_side_seed & 0xFFFFF, to.hash() & 0xFFFF, 1307) & 0x7FFFFFFF
		await _enter_side(to)
		_announce_side(to)
		await hud.fade_to(0.0, 1.6)
		player.controls_enabled = true
		_transition = false
		return
	_return_somewhere_else()


## Something in a side level got you: its jumpscare (or a jolt), the
## level's lines on black, and the Backrooms again, somewhere else (like
## the Attendant's catch).
func _on_side_caught(lines: Array, how := {}) -> void:
	if state != State.PLAYING or _transition or not _in_side:
		return
	_transition = true
	player.controls_enabled = false
	player.set_physics_process(false)
	var w := how.get("scare") as Walker
	if w != null and is_instance_valid(w) and Jumpscare.enabled():
		await jumpscare.run(w, how)
		await get_tree().create_timer(1.2).timeout
	else:
		var hit := AudioStreamPlayer.new()
		hit.stream = AudioSynth.cached("impact")
		hit.bus = "Master"
		add_child(hit)
		hit.play()
		hud.scare(0.7, 0.6)
		await get_tree().create_timer(0.12).timeout
		hud.scare(0.0, 0.0)
		await hud.fade_to(1.0, 0.25)
		hit.finished.connect(hit.queue_free)
	ambience.enabled = false
	if player.seated:
		player.stand_up()
	_leave_side()
	await hud.story(lines, 2.0)
	player.set_physics_process(true)
	hud.show_level(WorldGen.BIOME_NAMES[WorldGen.LOBBY], "Somewhere else.")
	_return_somewhere_else(WorldGen.LOBBY)


## A fall in a side level that nobody walks away from.
func _on_side_fell(lines: Array) -> void:
	if state != State.PLAYING or _transition or not _in_side:
		return
	_transition = true
	player.controls_enabled = false
	var rush := AudioStreamPlayer.new()
	rush.stream = AudioSynth.cached("wind")
	rush.volume_db = -2.0
	rush.bus = "World"
	add_child(rush)
	rush.play()
	await hud.fade_to(1.0, 0.7)
	player.set_physics_process(false)
	rush.queue_free()
	var hit := AudioStreamPlayer.new()
	hit.stream = AudioSynth.cached("impact")
	hit.bus = "Master"
	add_child(hit)
	hit.play()
	hit.finished.connect(hit.queue_free)
	ambience.enabled = false
	_leave_side()
	await get_tree().create_timer(0.8).timeout
	await hud.story(lines, 2.0)
	player.set_physics_process(true)
	hud.show_level(WorldGen.BIOME_NAMES[WorldGen.LOBBY], "Somewhere else. Somewhere far.")
	_return_somewhere_else(WorldGen.LOBBY)


## Stepped on a sodden patch of carpet: the floor gives way, and you fall
## through the dark under it, landing somewhere far off in the Yellow Halls.
func _on_floor_gave_way() -> void:
	if state != State.PLAYING or _transition or _away():
		return
	_transition = true
	player.controls_enabled = false
	player.set_physics_process(false)
	var crack := AudioStreamPlayer.new()
	crack.stream = AudioSynth.cached("crack")
	crack.bus = "World"
	add_child(crack)
	crack.play()
	var tw := create_tween()
	tw.tween_property(player, "global_position:y", player.global_position.y - 2.6, 0.55) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	hud.fade_to(1.0, 0.5)
	await tw.finished
	var rush := AudioStreamPlayer.new()
	rush.stream = AudioSynth.cached("wind")
	rush.volume_db = -3.0
	rush.bus = "World"
	add_child(rush)
	rush.play()
	ambience.enabled = false
	await hud.story(["The floor gave way.", "You fall through the dark for what feels like hours.", "Then: damp carpet, and the hum."], 2.0)
	rush.queue_free()
	crack.queue_free()
	player.set_physics_process(true)
	hud.show_level(WorldGen.BIOME_NAMES[WorldGen.LOBBY], "Somewhere else. Somewhere far.")
	_return_somewhere_else(WorldGen.LOBBY)


## Back into the Backrooms, but somewhere else entirely (in the given level,
## if one is asked for).
## Leaned into a thin place in a wall long enough to slip through it: a
## moment of nothing on either side, then the halls again, somewhere else.
func _on_noclipped() -> void:
	if state != State.PLAYING or _transition or _away():
		return
	_transition = true
	player.controls_enabled = false
	player.set_physics_process(false)
	var tear := AudioStreamPlayer.new()
	tear.stream = AudioSynth.cached("exhale")
	tear.pitch_scale = 0.5
	tear.bus = "World"
	add_child(tear)
	tear.play()
	var tw := create_tween()
	tw.tween_property(player.camera, "fov", player.camera.fov + 25.0, 0.35).set_ease(Tween.EASE_IN)
	hud.fade_to(1.0, 0.35)
	await tw.finished
	ambience.enabled = false
	await hud.story(["You leaned into the wall, and it gave.", "For a moment there was nothing on either side of you.", "Then the hum came back."], 2.0)
	tear.queue_free()
	player._apply_settings()
	player.set_physics_process(true)
	hud.show_level(WorldGen.BIOME_NAMES[WorldGen.LOBBY], "You noclipped. This isn't where you were.")
	_return_somewhere_else(WorldGen.LOBBY)


## The Attendant got you: a jolt, the lights go, and you're somewhere else.
func _on_caught() -> void:
	if state != State.PLAYING or _transition or _away():
		# Not now (mid-transition, paused): it let go of you; it mustn't
		# stay frozen there, still counted as out, and never come back.
		attendant.reset()
		return
	_transition = true
	player.controls_enabled = false
	player.set_physics_process(false)
	if Jumpscare.enabled():
		await jumpscare.run(attendant, {"sound": "tall_roar", "from": 2.2, "to": 0.65, "time": 1.0, "cut": true, "eyes": false})
		await get_tree().create_timer(1.2).timeout
	else:
		await get_tree().create_timer(0.5).timeout
		await hud.fade_to(1.0, 0.25)
	ambience.enabled = false
	attendant.reset()
	if player.seated:
		player.stand_up()
	await hud.story(["A hand closed on your shoulder.", "Every light in the car park went out at once.", "When they came back, so did the hum."], 2.0)
	player.set_physics_process(true)
	player.camera.h_offset = 0.0
	player.camera.v_offset = 0.0
	hud.show_level(WorldGen.BIOME_NAMES[WorldGen.LOBBY], "Somewhere else.")
	_return_somewhere_else(WorldGen.LOBBY)


## The crawler's reached you: it comes up at your face, then it's gone.
func _on_crawler_lunge() -> void:
	var had := player.controls_enabled
	player.controls_enabled = false
	player.set_physics_process(false)
	await jumpscare.run(crawler, {"sound": "crawler_scream", "from": 1.3, "to": 0.55, "time": 0.65, "cut": false, "eyes": false, "rear": 1.0})
	player.set_physics_process(true)
	player.controls_enabled = had and state == State.PLAYING
	crawler.finish_lunge()


func _walker(w: Walker) -> void:
	w.process_mode = Node.PROCESS_MODE_PAUSABLE
	w.player = player
	w.ambience = ambience
	add_child(w)


func _walkers() -> Array[Walker]:
	var out: Array[Walker] = []
	out.append(crawler)
	out.append(attendant)
	return out


func _return_somewhere_else(level := -1) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var g := gen
	var c := g.cell_of(Vector3.ZERO)
	for _try in 600:
		var a := rng.randf() * TAU
		var d := rng.randf_range(300.0, 900.0) / WorldGen.CELL
		c = Vector2i(int(cos(a) * d), int(sin(a) * d)) + g.spawn_cell
		var b := g.biome_at(c.x, c.y)
		if level >= 0 and (b != level or g.biome_at(c.x + 2, c.y) != level or g.biome_at(c.x - 2, c.y) != level):
			continue
		if b != WorldGen.POOL and not g.is_solid(c.x, c.y, b) and not g.pool_noise(c.x, c.y):
			break
	var pos := Vector3((c.x + 0.5) * WorldGen.CELL, 0.05, (c.y + 0.5) * WorldGen.CELL)
	_load_world(g.seed_value, pos, rng.randf() * TAU, 0.0, func() -> void:
		_start_playing()
		_transition = false
		hud.fade_to(0.0, 1.5))


## Draws the given materials once in front of the camera and waits a few
## frames (shader compiles happen behind a fade, not in your face later).
func _warm_now(list: Array[Material]) -> void:
	var holder := Node3D.new()
	player.camera.add_child(holder)
	for i in list.size():
		var mi := MeshInstance3D.new()
		var q := QuadMesh.new()
		q.size = Vector2(0.004, 0.004)
		mi.mesh = q
		mi.material_override = list[i]
		mi.position = Vector3(i * 0.005, 0.0, -0.3)
		holder.add_child(mi)
	for _f in 3:
		await get_tree().process_frame
	holder.queue_free()


# ----------------------------------------------------------------- save ---

func _write_save() -> void:
	if gen == null or (state != State.PLAYING and state != State.PAUSED):
		return
	if net.active and not net.is_host:
		return                     # the host's game is the one that's saved
	var cf := ConfigFile.new()
	if player.in_stairwell:
		return                     # mid-flight; the last save off the stairs stands
	cf.set_value("save", "seed", gen.seed_value)
	cf.set_value("save", "floor", _floor)
	cf.set_value("save", "pos", player.seat_exit if player.seated else player.global_position)
	cf.set_value("save", "yaw", player.yaw)
	cf.set_value("save", "pitch", player.pitch)
	cf.set_value("save", "flashlight", player.flashlight_on)
	cf.set_value("save", "time", _play_time)
	cf.set_value("save", "side_seed", _side_seed)
	if _in_field:
		cf.set_value("save", "field_exit", field.exit_pos)
	if _in_mall:
		cf.set_value("save", "mall", true)
	if _in_side and side:
		cf.set_value("save", "side", side_id)
		cf.set_value("save", "side_state", side.save_state())
		cf.set_value("save", "stance", player.stance())
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


# ------------------------------------------------------------ multiplayer ---

func open_multiplayer() -> void:
	if state != State.MENU:
		return
	main_menu.hide()
	mp_menu.open(not _read_save().is_empty())
	net.browse(true)


## Host from the multiplayer menu: start (or continue) a game others can join.
func _host_game(continue_saved: bool) -> void:
	var err := net.host(Settings.get_value("net/name"), int(Settings.get_value("net/number")))
	if err != OK:
		mp_menu.set_status("Couldn't host (is another game already using port %d?)" % Net.PORT)
		return
	net.browse(false)
	mp_menu.hide()
	main_menu.show()        # new_game/continue_game hide it again
	if continue_saved:
		continue_game()
	else:
		new_game()


func _join_game(ip: String) -> void:
	mp_menu.set_status("Connecting to %s..." % ip)
	if net.join(ip, Settings.get_value("net/name"), int(Settings.get_value("net/number"))) != OK:
		mp_menu.set_status("Couldn't connect to %s." % ip)


## Host side: what a joining player needs (the world seed and where to appear).
func _net_world_info() -> Dictionary:
	var pos: Vector3 = gen.spawn_position() if gen else Vector3.ZERO
	var yaw := 0.0
	if gen and state != State.MENU and not _away():
		# Right next to the host (even while they're still loading or in the
		# intro), on whichever side has room.
		yaw = player.yaw
		pos = player.global_position
		var space := player.get_world_3d().direct_space_state
		var eye := player.global_position + Vector3.UP * 1.0
		for d: Vector3 in [player.global_basis.x, -player.global_basis.x, player.global_basis.z, -player.global_basis.z]:
			var q := PhysicsRayQueryParameters3D.create(eye, eye + d * 1.3)
			q.exclude = [player.get_rid()]
			if space.intersect_ray(q).is_empty():
				pos = player.global_position + d * 0.9
				break
	return {"seed": gen.seed_value if gen else 0, "pos": pos, "yaw": yaw, "floor": _floor}


func _on_net_joined(info: Dictionary) -> void:
	net.browse(false)
	mp_menu.hide()
	main_menu.hide()
	_play_time = 0.0
	await hud.fade_to(1.0, 0.5)
	_leave_side_levels()
	_world_seed = -1
	_load_world(int(info.seed), info.pos, float(info.yaw), 0.0, func() -> void:
		player.set_flashlight(false)
		_start_playing()
		hud.show_level("Joined", "You're in. Player %02d." % int(info.number))
		hud.fade_to(0.0, 1.0), int(info.get("floor", 0)))


func _on_net_disconnected(reason: String) -> void:
	_clear_remotes()
	if state == State.PLAYING or state == State.PAUSED:
		pause_menu.hide()
		get_tree().paused = false
		await hud.fade_to(1.0, 0.5)
		_leave_side_levels()
		_enter_menu()
		hud.show_level("Disconnected", reason)


func _end_session() -> void:
	if net.active:
		net.leave()
	_clear_remotes()


func _on_peer_state(id: int, s: Dictionary) -> void:
	if not _remotes.has(id):
		var r := RemotePlayer.new()
		r.gen = gen
		r.ambience = ambience
		r.number = int(net.roster.get(id, {}).get("number", 0))
		add_child(r)
		_remotes[id] = r
		radar.shown = true
	(_remotes[id] as RemotePlayer).push_state(s)


func _on_roster_changed() -> void:
	for id in _remotes:
		if net.roster.has(id):
			(_remotes[id] as RemotePlayer).set_number(int(net.roster[id].number))


func _remove_remote(id: int) -> void:
	if _remotes.has(id):
		_remotes[id].queue_free()
		_remotes.erase(id)


## Feeds the hand-held radar with the players in the same place as you (the
## Field is a separate world) and shows its touch button only online.
func _update_radar(delta: float) -> void:
	touch.radar_available = net.active
	if not net.active:
		radar.shown = false
	# Same place: a blip where they are. Another floor of the Backrooms
	# (the floors share one plan, the stairwells line up): a faint blip at
	# their spot marked with how many floors up or down. Somewhere else
	# entirely (another Field or Mall, or the Backrooms while you're out):
	# just their number and where.
	var others := []
	for id in _remotes:
		var r := _remotes[id] as RemotePlayer
		r.gen = gen
		r.set_viewer(_floor, _in_field, _in_mall, _side_seed, side_id if _in_side else "")
		r.level = side if _in_side else null
		if not r.has_state():
			continue
		if r.visible:
			others.append([r.global_position, r.number, ""])
		elif not _away() and not r.away():
			var df := r.floor_index - _floor
			others.append([r.global_position, r.number, ("▲%d" if df > 0 else "▼%d") % absi(df)])
		else:
			others.append([Vector3.INF, r.number, r.place_name()])
	var light := 1.0
	if gen and not _away():
		light = gen.light_level_near(player.global_position + Vector3.UP * 1.2) * 0.35
	elif _in_side and side:
		var lc := side.light_at(player.global_position + Vector3.UP * 1.2)
		light = (lc.r + lc.g + lc.b) / 3.0
	radar.update(delta, player, others, light)


func _clear_remotes() -> void:
	for id in _remotes:
		_remotes[id].queue_free()
	_remotes.clear()
