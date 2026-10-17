extends Node
# Dev harness: re-shoots the README screenshots that show on-screen text
# (main menu; level titles with the touch controls) into docs/screenshots.
var game
var out := ProjectSettings.globalize_path("res://docs/screenshots")
var step := 0
var t := 0.0
var g: WorldGen
var views := []
var vi := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(n):
	get_viewport().get_texture().get_image().save_jpg("%s/%s.jpg" % [out, n], 0.9)
	print("shot ", n)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU and t > 18.0:
				Settings.apply_preset(3)
				Settings.set_value("graphics/auto_quality", false)
				shot("menu")
				if OS.get_cmdline_user_args().has("menu_only"):
					get_tree().quit(); return
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				g = game.gen
				game._using_touch = true
				game._update_touch_visibility()
				var sp: Vector3 = g.spawn_position()
				# Pillared hall, a close wall, a Tiled Baths arcade.
				var hall := sp
				for r in range(4, 300, 2):
					var c: Vector2i = g.spawn_cell + Vector2i(r, 0)
					if g.open_hall(c.x, c.y) and g.biome_at(c.x, c.y) == WorldGen.LOBBY:
						hall = Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4); break
				views.append(["yellow_halls_touch", hall, 0.6, 0.0, WorldGen.LOBBY])
				views.append(["yellow_halls_wallpaper", sp, 0.3, -0.05, WorldGen.LOBBY])
				var pool := sp
				for r in range(6, 400, 2):
					var done := false
					for k in 16:
						var a := k * TAU / 16.0
						var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
						if g.biome_at(c.x, c.y) == WorldGen.POOL and not g.gallery(c.x, c.y) and not g.pool_noise(c.x, c.y) and g.biome_at(c.x + 3, c.y) == WorldGen.POOL and g.biome_at(c.x - 3, c.y) == WorldGen.POOL:
							pool = Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4); done = true; break
					if done: break
				views.append(["tiled_baths_arches", pool, 0.4, 0.0, WorldGen.POOL])
				step = 2; t = 0; _go()
		2:
			if t > 7.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				var v = views[vi]
				game.hud.set_fade(0.0)
				game.hud.show_level(WorldGen.BIOME_NAMES[v[4]], game.SUBTITLES[v[4]])
				step = 3; t = 0
		3:
			if t > 1.2:
				shot(views[vi][0])
				vi += 1
				if vi >= views.size():
					get_tree().quit(); return
				_go(); step = 2; t = 0

func _go():
	var v = views[vi]
	game.player.teleport(v[1], v[2], v[3])
	game._biome = g.biome_at(g.cell_of(v[1]).x, g.cell_of(v[1]).y)
