extends Node
# Dev harness for L.U.C.I.D. (docs/LUCID.md): the same Lobby views under the
# Realistic preset, for before / after sheets, plus the illuminance the bake
# computes on the floor under and between troffers, and frame cost.
# TAG=<file suffix> (default "after"), VIEWS=<comma list> (default all),
# PERF=1 also prints draw calls and the mean frame time over 60 frames per
# view (lavapipe: compare runs with each other only), PROBE=1 prints the
# probed illuminance (lux) and the camera's exposure. NOFIX=1: without the
# fixture highlight lights; FLASH=1: flashlight on.
# Shots: user://photo/lucid_<view>_<tag>.png
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var g: WorldGen
var views := []
var vi := 0
var tag := "after"
var perf := false
var probe := false
var _frames := 0
var _sum_ms := 0.0
var _sum_dc := 0.0
var _last_us := 0

const ALL := ["spawn_hall", "corridor", "dark_corner", "dead_light"]


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	if OS.get_environment("TAG") != "":
		tag = OS.get_environment("TAG")
	perf = OS.get_environment("PERF") == "1"
	probe = OS.get_environment("PROBE") == "1"
	var want: Array = ALL if OS.get_environment("VIEWS") == "" else Array(OS.get_environment("VIEWS").split(","))
	for v in ALL:
		if want.has(v):
			views.append(v)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)


func _lit(gx: int, gz: int) -> bool:
	var s := g.light_state(gx, gz, WorldGen.LOBBY)
	return s == WorldGen.L_ON or s == WorldGen.L_FLICKER


func _cell_pos(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * WorldGen.CELL, 0.05, (c.y + 0.5) * WorldGen.CELL)


## A Lobby cell nearest the spawn with walls on its west and north sides
## and no lit fixture in the 3 x 3 cells around it: a dark corner.
func _find_corner() -> Vector2i:
	var best := g.spawn_cell
	var best_n := 99
	for r in range(3, 40):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := g.spawn_cell + Vector2i(dx, dz)
				if g.biome_at(c.x, c.y) != WorldGen.LOBBY or g.is_solid(c.x, c.y, WorldGen.LOBBY):
					continue
				var e: Array = g._cell_edges(c.x, c.y)
				if e[0] != WorldGen.E_WALL or e[2] != WorldGen.E_WALL or e[1] == WorldGen.E_WALL or e[3] == WorldGen.E_WALL:
					continue
				var n := 0
				for j in range(-1, 2):
					for i in range(-1, 2):
						if _lit(c.x + i, c.y + j):
							n += 1
				if n < best_n:
					best_n = n
					best = c
		if best_n == 0:
			break
	return best


## A dead fixture in the Lobby (not at the spawn) with an open cell to its
## south to stand in.
func _find_dead() -> Vector2i:
	for r in range(3, 60):
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var c := g.spawn_cell + Vector2i(dx, dz)
				if g.biome_at(c.x, c.y) != WorldGen.LOBBY or g.light_state(c.x, c.y, WorldGen.LOBBY) != WorldGen.L_DEAD:
					continue
				var s := c + Vector2i(0, 1)
				if g.is_solid(s.x, s.y, WorldGen.LOBBY) or g.biome_at(s.x, s.y) != WorldGen.LOBBY:
					continue
				var e: Array = g._cell_edges(s.x, s.y)
				if e[2] == WorldGen.E_OPEN:
					return c
	return g.spawn_cell


func _go() -> void:
	var v: String = views[vi]
	game.player.set_flashlight(OS.get_environment("FLASH") == "1")
	if OS.get_environment("NOFIX") == "1":
		game.fixtures.max_lights = 0
	match v:
		"spawn_hall":
			game.player.teleport(g.spawn_position() + Vector3(0.6, 0, 0.6), 0.6, -0.03)
		"corridor":
			var hall := g.spawn_position()
			for r in range(4, 300, 2):
				var c: Vector2i = g.spawn_cell + Vector2i(0, r)
				if g.biome_at(c.x, c.y) == WorldGen.LOBBY and not g.open_hall(c.x, c.y):
					hall = _cell_pos(c)
					if r > 10:
						break
			game.player.teleport(hall, 0.0, -0.02)
		"dark_corner":
			var c := _find_corner()
			# From the far side of the cell, looking into the north-west corner.
			game.player.teleport(_cell_pos(c) + Vector3(1.0, 0, 1.0), PI * 0.25, -0.12)
		"dead_light":
			var c := _find_dead()
			game.player.teleport(_cell_pos(c + Vector2i(0, 1)) + Vector3(0, 0, 0.9), 0.0, 0.22)
	var cc := g.cell_of(game.player.global_position)
	game._biome = g.biome_at(cc.x, cc.y)


func _probe() -> void:
	if not ClassDB.class_exists("Node") or not probe:
		return
	var s := g.spawn_cell
	# The spawn hall is lit by every second row (gz even), every cell along it.
	var row := s.y - posmod(s.y, 2)
	var under := Vector3((s.x + 0.5) * WorldGen.CELL, 0.0, (row + 0.5) * WorldGen.CELL)
	var between_z := under + Vector3(0, 0, WorldGen.CELL)        # halfway to the next row
	var between_x := under + Vector3(WorldGen.CELL * 0.5, 0, 0)  # halfway along the row
	for pair in [["floor under a troffer", under], ["floor between rows", between_z], ["floor between along row", between_x],
			["desk (0.75 m) under a troffer", under + Vector3.UP * 0.75]]:
		var r: Dictionary = ChunkBuilder.probe(g, pair[1], Vector3.UP)
		print("PROBE %-30s E=%.0f lux (direct %.0f, indirect %.0f)" % [pair[0], r.lux, r.direct, r.indirect])
	var w: Dictionary = ChunkBuilder.probe(g, under + Vector3(0, 1.5, 0), Vector3.FORWARD)
	print("PROBE vertical at eye height      E=%.0f lux" % w.lux)
	var ce: Dictionary = ChunkBuilder.probe(g, between_z + Vector3(0, WorldGen.CEIL_H[0] - 0.05, 0), Vector3.DOWN)
	print("PROBE ceiling between rows        E=%.0f lux (direct %.0f, indirect %.0f)" % [ce.lux, ce.direct, ce.indirect])


func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				Settings.set_value("gameplay/entities", false)
				Settings.set_value("gameplay/jumpscares", false)
				Settings.is_mobile = true
				Settings.apply_preset(Settings.REALISTIC)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				g = game.gen
				game.hud.set_fade(0.0)
				Engine.max_fps = 0
				DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
				if probe:
					_probe()
				step = 2; t = 0
				_go()
		2:
			if t > 9.0 and game.chunks.is_area_ready(game.player.global_position, 2):
				game.hud.set_fade(0.0)
				game.hud._title.modulate.a = 0.0
				game.hud._subtitle.modulate.a = 0.0
				get_viewport().get_texture().get_image().save_png("%s/lucid_%s_%s.png" % [out, views[vi], tag])
				var info := ""
				if "lucid_cam" in game and game.lucid_cam != null:
					info = " EV100 %.2f WB %dK" % [game.lucid_cam.ev100, roundi(game.lucid_cam.wb_kelvin)]
				print("shot ", views[vi], " ", tag, " exposure ", game.world_env.environment.tonemap_exposure, info)
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
