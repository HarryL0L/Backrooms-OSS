extends Node
# Dev harness: the same views at a preset (env PRESET, default 5 Photoreal):
# a lit hall, a corner, the Tiled Baths, the Unlit Halls, the Dead Mall.
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var views := []
var vi := 0
var tag := ""

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				var pr := int(OS.get_environment("PRESET")) if OS.get_environment("PRESET") != "" else 5
				tag = str(pr)
				Settings.set_value("graphics/ps1", false)      # a fair comparison
				Settings.apply_preset(pr)
				Settings.set_value("graphics/found_footage", int(OS.get_environment("FF")) if OS.get_environment("FF") != "" else 0)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var g: WorldGen = game.gen
				var sp := g.spawn_position()
				views.append(["hall", sp, 0.6, -0.05])
				views.append(["corner", sp, 2.4, -0.25])
				var pool := sp
				var dark := sp
				for r in range(6, 400, 2):
					for k in 16:
						var a := k * TAU / 16.0
						var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
						var b := g.biome_at(c.x, c.y)
						if pool == sp and b == WorldGen.POOL and not g.pool_noise(c.x, c.y) and g.biome_at(c.x + 3, c.y) == b and g.biome_at(c.x - 3, c.y) == b:
							pool = Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4)
						if dark == sp and b == WorldGen.DARK and not g.is_solid(c.x, c.y, b) and g.biome_at(c.x + 3, c.y) == b and g.biome_at(c.x - 3, c.y) == b:
							dark = Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4)
				views.append(["baths", pool, 0.4, 0.0])
				views.append(["unlit", dark, 0.0, -0.05])
				views.append(["mall", Vector3(24, MallLevel.MALL_Y + 0.05, 3.5), -PI * 0.5, 0.05])
				var lamp_cell := g.cell_of(sp)
				lamp_cell.y -= posmod(lamp_cell.y, 2)
				views.append(["ceiling", Vector3((lamp_cell.x + 0.5) * 2.4 + 1.6, 0.05, (lamp_cell.y + 0.5) * 2.4), PI * 0.5, 0.75])
				views.append(["tiles", pool, 0.4, -0.75])
				var mall_v = views.filter(func(v): return v[0] == "mall")
				views = views.filter(func(v): return v[0] != "mall") + mall_v
				if OS.get_environment("ONLY") != "":
					views = views.filter(func(v): return v[0] in OS.get_environment("ONLY").split(","))
				tag += OS.get_environment("TAG")
				game.hud.set_fade(0.0)
				_go(); step = 2; t = 0
		2:
			var ready: bool = game._in_mall or game.chunks.is_area_ready(game.player.global_position, 1)
			# Long enough for the eyes to adapt.
			if OS.get_environment("NOGRADE") != "":
				EnvironmentFactory.photoreal_grade(game.env, false)
			if t > 9.0 and ready:
				game.hud.set_fade(0.0)
				game.hud._title_t = 0.0
				get_viewport().get_texture().get_image().save_png("%s/%s_%s.png" % [out, views[vi][0], tag])
				print("shot ", views[vi][0], " exposure ", game.env.tonemap_exposure)
				vi += 1
				if vi >= views.size():
					get_tree().quit(); return
				_go(); t = 0

func _go():
	var v = views[vi]
	if v[0] == "mall":
		game._enter_mall()
		await get_tree().create_timer(3.0).timeout
	game.player.teleport(v[1], v[2], v[3])
	if v[0] == "unlit":
		game.player.set_flashlight(true)
