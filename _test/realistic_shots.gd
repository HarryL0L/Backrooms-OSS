extends Node
# Dev harness: the same views under one graphics preset, for comparing the
# Realistic preset with the others. PRESET=<0..5> (default 5), TAG=<file
# suffix> (default the preset's name), VIEWS=<comma list> (default all),
# PERF=1 also prints draw calls, primitives and the mean frame time over 60
# frames per view (lavapipe: compare presets with each other only). The
# preset's phone values are used unless DESKTOP=1; AA=<0..4> overrides the
# anti-aliasing (to compare presets at the same MSAA).
# Shots: user://photo/real_<view>_<tag>.png
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var g: WorldGen
var views := []
var vi := 0
var preset := 5
var tag := ""
var perf := false
var _frames := 0
var _sum_ms := 0.0
var _sum_dc := 0.0
var _sum_prim := 0.0
var _last_us := 0
var _aimed := false

const ALL := ["lobby_spawn", "lobby_corridor", "poolrooms", "warehouse", "dark_halls", "car_park", "mall", "mall_court", "crawlspace", "field"]


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	if OS.get_environment("PRESET") != "":
		preset = int(OS.get_environment("PRESET"))
	tag = OS.get_environment("TAG") if OS.get_environment("TAG") != "" else Settings.PRESET_NAMES[preset].to_lower()
	perf = OS.get_environment("PERF") == "1"
	var want: Array = ALL if OS.get_environment("VIEWS") == "" else Array(OS.get_environment("VIEWS").split(","))
	for v in ALL:
		if want.has(v):
			views.append(v)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)


## The open cell nearest the spawn (in rings) in biome `b`, with the same biome
## `margin` cells around it.
func _find(b: int, margin := 3) -> Vector3:
	for r in range(4, 400, 2):
		for k in 24:
			var a := k * TAU / 24.0
			var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
			var ok := true
			for d in [Vector2i(margin, 0), Vector2i(-margin, 0), Vector2i(0, margin), Vector2i(0, -margin), Vector2i(0, 0)]:
				if g.biome_at(c.x + d.x, c.y + d.y) != b:
					ok = false
			if ok and (b != WorldGen.POOL or not (g.gallery(c.x, c.y) or g.pool_noise(c.x, c.y))):
				return Vector3((c.x + 0.5) * WorldGen.CELL, 0.05, (c.y + 0.5) * WorldGen.CELL)
	return g.spawn_position()


## Turns the player to the longest clear view (raycasts at eye height).
func _aim_longest() -> void:
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var eye: Vector3 = game.player.global_position + Vector3(0, 1.55, 0)
	var best := 0.0
	var best_yaw := 0.0
	for k in 32:
		var yaw := k * TAU / 32.0
		var dir := Vector3(-sin(yaw), 0, -cos(yaw))
		var q := PhysicsRayQueryParameters3D.create(eye, eye + dir * 40.0)
		q.exclude = [game.player.get_rid()]
		var hit: Dictionary = space.intersect_ray(q)
		var d: float = 40.0 if hit.is_empty() else eye.distance_to(hit.position)
		if d > best + 0.5:
			best = d
			best_yaw = yaw
	game.player.teleport(game.player.global_position, best_yaw, -0.04)


func _go() -> void:
	var v: String = views[vi]
	_aimed = false
	match v:
		"lobby_spawn":
			game.player.teleport(g.spawn_position() + Vector3(0.6, 0, 0.6), 0.6, -0.03)
			_aimed = true
		"lobby_corridor":
			var hall := g.spawn_position()
			for r in range(4, 300, 2):
				var c: Vector2i = g.spawn_cell + Vector2i(0, r)
				if g.biome_at(c.x, c.y) == WorldGen.LOBBY and not g.open_hall(c.x, c.y):
					hall = Vector3((c.x + 0.5) * WorldGen.CELL, 0.05, (c.y + 0.5) * WorldGen.CELL)
					if r > 10:
						break
			game.player.teleport(hall, 0.0)
		"poolrooms":
			game.player.teleport(_find(WorldGen.POOL), 0.0)
		"warehouse":
			game.player.teleport(_find(WorldGen.CONCRETE), 0.0)
		"dark_halls":
			game.player.teleport(_find(WorldGen.DARK), 0.0)
			game.player.set_flashlight(true)
		"car_park":
			game.player.set_flashlight(false)
			game._floor = -1
			game._use_gen(WorldGen.new(game.gen.seed_value, -1), true)
			g = game.gen
			game.player.teleport(_find(WorldGen.GARAGE, 4), 0.0)
		"mall":
			game.player.set_flashlight(false)
			await game._enter_mall()
			_aimed = true
		"mall_court":
			# Towards the Fountain Court down the concourse, off-centre.
			game.player.teleport(Vector3(64.0, MallLevel.MALL_Y + 0.05, 3.5), -PI * 0.5 + 0.12, -0.08)
			_aimed = true
		"crawlspace":
			await game.debug_enter_side("crawlspace")
			_aimed = true
		"field":
			game._leave_side_levels()
			game._enter_field()
			game.player.teleport(game.player.global_position, 0.0, 0.05)
			_aimed = true
	var c := g.cell_of(game.player.global_position)
	game._biome = g.biome_at(c.x, c.y)


func _ready_to_shoot() -> bool:
	var v: String = views[vi]
	if v in ["mall", "crawlspace", "field"]:
		return t > 9.0
	if v == "mall_court":
		return t > 4.0
	return t > 8.0 and game.chunks.is_area_ready(game.player.global_position, 2)


func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				Settings.set_value("gameplay/entities", false)
				Settings.set_value("gameplay/jumpscares", false)
				# The phone values of the preset (DESKTOP=1: the desktop ones).
				Settings.is_mobile = OS.get_environment("DESKTOP") != "1"
				Settings.apply_preset(preset)
				if OS.get_environment("AA") != "":
					Settings.set_value("graphics/aa", int(OS.get_environment("AA")))
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				g = game.gen
				game.hud.set_fade(0.0)
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				step = 2; t = 0
				_go()
		2:
			if not _aimed and t > 4.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				_aim_longest()
				_aimed = true
			if _aimed and _ready_to_shoot():
				game.hud.set_fade(0.0)
				game.hud._title.modulate.a = 0.0
				game.hud._subtitle.modulate.a = 0.0
				get_viewport().get_texture().get_image().save_png("%s/real_%s_%s.png" % [out, views[vi], tag])
				print("shot ", views[vi], " ", tag, " exposure ", game.world_env.environment.tonemap_exposure)
				step = 3; t = 0
				_frames = -5; _sum_ms = 0.0; _sum_dc = 0.0; _sum_prim = 0.0
				_last_us = Time.get_ticks_usec()
		3:
			if perf:
				var now := Time.get_ticks_usec()
				if _frames >= 0:
					_sum_ms += (now - _last_us) / 1000.0
					_sum_dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
					_sum_prim += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)
				_last_us = now
				_frames += 1
				if _frames < 60:
					return
				print("PERF %s %s draw_calls=%d primitives=%d frame_ms=%.2f" % [views[vi], tag,
						roundi(_sum_dc / 60.0), roundi(_sum_prim / 60.0), _sum_ms / 60.0])
			vi += 1
			if vi >= views.size():
				get_tree().quit(); return
			step = 2; t = 0
			_go()
