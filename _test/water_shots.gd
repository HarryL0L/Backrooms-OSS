extends Node
# Dev harness: the Poolrooms water from five views under one graphics preset,
# and the dry tiled floor (the "poolrooms" view of realistic_shots).
# PRESET=<0..5> (default 2 = Medium), TAG=<file suffix> (default the preset's
# name), PERF=1 also prints draw calls and the mean frame time over 60 frames
# per view (lavapipe: compare runs with each other only), VIEWS=<comma list>
# (default all), PS1=1 turns PS1 style on. Phone values.
# Shots: user://photo/water_<view>_<tag>.png
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var g: WorldGen
var vi := 0
var preset := 2
var tag := ""
var perf := false
var _frames := 0
var _sum_ms := 0.0
var _sum_dc := 0.0
var _last_us := 0
var _centre := Vector2i.ZERO    # a pool cell with pool all round it
var _rim := Vector3.ZERO        # standing on the dry floor at the pool's edge
var _rim_yaw := 0.0             # facing the pool centre

const ALL := ["deep", "wading", "edge_down", "across", "wide", "dry"]
var views := []


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


## Same test as ChunkBuilder: a sunken pool cell.
func _is_pool(x: int, z: int) -> bool:
	var b := WorldGen.POOL
	return g.biome_at(x, z) == b and g.biome_at(x - 1, z) == b and g.biome_at(x + 1, z) == b \
			and g.biome_at(x, z - 1) == b and g.biome_at(x, z + 1) == b and g.pool_noise(x, z) \
			and not g.gallery(x, z)


## The nearest pool cell (in rings round the spawn) with pool 2 cells all round.
func _find_pool() -> void:
	for r in range(4, 400, 2):
		for k in 32:
			var a := k * TAU / 32.0
			var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
			var ok := true
			for dz in range(-2, 3):
				for dx in range(-2, 3):
					if not _is_pool(c.x + dx, c.y + dz):
						ok = false
			if ok:
				_centre = c
				print("pool centre ", _centre)
				return


## The first dry cell (walking out from the centre in the four directions)
## that can be seen from the centre: stand 0.35 m back from its edge.
func _find_rim() -> void:
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var from := _pos(_centre, 0.6)
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var e: Vector2i = _centre
		while _is_pool(e.x, e.y):
			e += d
		var p := _pos(e, 0.6) - Vector3(d.x, 0, d.y) * (WorldGen.CELL * 0.5 - 0.35)
		var q := PhysicsRayQueryParameters3D.create(from, p)
		q.exclude = [game.player.get_rid()]
		if space.intersect_ray(q).is_empty():
			_rim = Vector3(p.x, 0.05, p.z)
			var dir := Vector3(-d.x, 0, -d.y)
			_rim_yaw = atan2(-dir.x, -dir.z)
			print("rim ", _rim)
			return


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


func _pos(c: Vector2i, y: float, ox := 0.5, oz := 0.5) -> Vector3:
	return Vector3((c.x + ox) * WorldGen.CELL, y, (c.y + oz) * WorldGen.CELL)


func _go() -> void:
	var f := WorldGen.POOL_FLOOR + 0.05
	if _rim == Vector3.ZERO and views[vi] in ["edge_down", "across", "wide"]:
		# The rim is found by raycasts: load the pool round the centre first.
		game.player.teleport(_pos(_centre, f), 0.0)
		while not game.chunks.is_area_ready(game.player.global_position, 1):
			await get_tree().process_frame
		for i in 3:
			await get_tree().physics_frame
		_find_rim()
		t = 0.0
	match views[vi]:
		"deep":
			game.player.teleport(_pos(_centre, f), 0.7, -0.75)
		"wading":
			game.player.teleport(_pos(_centre, f, 0.2, 0.3), 2.2, -0.4)
		"edge_down":
			# On the rim, looking down at the water at your feet.
			pass
			game.player.teleport(_rim, _rim_yaw, -1.0)
		"across":
			game.player.teleport(_rim, _rim_yaw + 0.3, -0.1)
		"wide":
			game.player.teleport(_rim, _rim_yaw - 0.5, -0.22)
		"dry":
			game.player.teleport(_find(WorldGen.POOL), 0.0)
			while not game.chunks.is_area_ready(game.player.global_position, 1):
				await get_tree().process_frame
			for i in 3:
				await get_tree().physics_frame
			_aim_longest()
			t = 0.0
	game._biome = WorldGen.POOL
	game._update_reflection()


func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				Settings.set_value("gameplay/entities", false)
				Settings.set_value("gameplay/jumpscares", false)
				Settings.is_mobile = true
				Settings.apply_preset(preset)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				g = game.gen
				game.hud.set_fade(0.0)
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				if OS.get_environment("PS1") == "1":
					Settings.set_value("graphics/ps1", true)
				_find_pool()
				step = 2; t = 0
				_go()
		2:
			if t > 8.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				game.hud.set_fade(0.0)
				game.hud._title.modulate.a = 0.0
				game.hud._subtitle.modulate.a = 0.0
				get_viewport().get_texture().get_image().save_png("%s/water_%s_%s.png" % [out, views[vi], tag])
				print("shot ", views[vi], " ", tag)
				step = 3; t = 0
				_frames = -5; _sum_ms = 0.0; _sum_dc = 0.0
				_last_us = Time.get_ticks_usec()
		3:
			if perf:
				var now := Time.get_ticks_usec()
				if _frames >= 0:
					_sum_ms += (now - _last_us) / 1000.0
					_sum_dc += RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
				_last_us = now
				_frames += 1
				if _frames < 60:
					return
				print("PERF %s %s draw_calls=%d frame_ms=%.2f" % [views[vi], tag, roundi(_sum_dc / 60.0), _sum_ms / 60.0])
			vi += 1
			if vi >= views.size():
				get_tree().quit(); return
			step = 2; t = 0
			_go()
