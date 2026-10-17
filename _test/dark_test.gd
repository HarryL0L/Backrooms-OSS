extends Node
# Dev harness: Potato preset in the Unlit Halls and a dim Yellow Halls corner, with
# and without the dark lift, plus the shader flashlight.
var game
var out := OS.get_user_data_dir() + "/dark"
var step := 0
var t := 0.0
var shots := [["l0", 0.0, false], ["l1", 0.1, false], ["l2", 0.18, false], ["l3", 0.28, false]]
var si := 0

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
				Settings.apply_preset(0)
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				var found := false
				for r in range(4, 300, 3):
					for k in 24:
						var a := k * TAU / 24.0
						var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
						if g.biome_at(c.x, c.y) == 3 and not g.is_solid(c.x, c.y, 3) and g.biome_at(c.x + 3, c.y) == 3 and g.biome_at(c.x - 3, c.y) == 3:
							game.player.teleport(Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4), 0.0, -0.1)
							found = true; break
					if found: break
				print("teleported ", found); step = 2; t = 0
		2:
			if t > 5.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				var s = shots[si]
				RenderingServer.global_shader_parameter_set("dark_lift", s[1])
				game.player.set_flashlight(s[2])
				step = 3; t = 0
		3:
			if t > 0.6:
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shots[si][0]])
				print("shot ", shots[si][0])
				si += 1
				if si >= shots.size():
					get_tree().quit()
				else:
					step = 2; t = 10
