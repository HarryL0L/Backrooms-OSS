extends Node
# Dev harness: looks across a big Poolrooms pool (Medium preset) to compare
# near and far water colour.
var game
var out := OS.get_user_data_dir() + "/water"
var step := 0
var t := 0.0
var tag := OS.get_environment("TAG") if OS.get_environment("TAG") != "" else "water"

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _process(delta):
	t += delta
	var g = game.gen
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(int(OS.get_environment("PRESET")) if OS.get_environment("PRESET") != "" else 2)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "4242"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				var found := Vector2i.ZERO
				var dir := 0
				var ok := false
				for r in range(6, 400, 2):
					for k in 32:
						var a := k * TAU / 32.0
						var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
						if g.biome_at(c.x, c.y) != 1 or g.pool_noise(c.x, c.y) or g.gallery(c.x, c.y):
							continue
						# Deck cell with a long run of pool to the east.
						var run := 0
						for d in range(1, 9):
							if g.biome_at(c.x + d, c.y) == 1 and g.pool_noise(c.x + d, c.y) and not g.gallery(c.x + d, c.y):
								run += 1
							else:
								break
						if run >= 7:
							found = c; ok = true; break
					if ok: break
				print("deck ", found, " ok ", ok)
				if not ok:
					get_tree().quit(); return
				game.player.teleport(Vector3((found.x + 0.8) * 2.4, 0.05, (found.y + 0.5) * 2.4), -PI * 0.5, -0.22)
				step = 2; t = 0
		2:
			if t > 8.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				step = 3; t = 0
		3:
			if t > 1.0:
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, tag])
				print("shot ", tag)
				get_tree().quit()
