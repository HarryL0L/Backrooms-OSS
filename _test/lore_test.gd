extends Node
# Dev harness: the Lobby's lore details. Photographs a trash bin / bucket and
# a thin place in a wall, then walks into the thin place and checks that you
# noclip through it.
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var thin := []
var prop := []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _look(eye: Vector3, at: Vector3, pitch := 0.0):
	var d := at - eye
	game.player.teleport(Vector3(eye.x, 0.05, eye.z), atan2(-d.x, -d.z), pitch)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/ps1", false)
				Settings.apply_preset(4)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var g: WorldGen = game.gen
				var rc := Vector2i(floori(float(g.spawn_cell.x) / 16), floori(float(g.spawn_cell.y) / 16))
				for rad in 12:
					for dz in range(-rad, rad + 1):
						for dx in range(-rad, rad + 1):
							if maxi(absi(dx), absi(dz)) != rad:
								continue
							var res := {}
							LobbyDetails._compute(g, rc + Vector2i(dx, dz), res)
							if thin.is_empty() and not res.thin.is_empty():
								thin = res.thin
							if prop.is_empty() and res.props.size() > 0:
								prop = res.props[0]
				print("thin ", thin, " prop ", prop)
				game.hud.set_fade(0.0)
				var p: Vector3 = prop[0]
				var off := Vector3(floorf(p.x / 2.4) * 2.4 + 1.2, 0.0, floorf(p.z / 2.4) * 2.4 + 1.2) - p
				var n := Vector3(signf(off.x), 0, 0) if absf(off.x) > absf(off.z) else Vector3(0, 0, signf(off.z))
				_look(p + n * 1.9 + n.cross(Vector3.UP) * 0.5, p, -0.45)
				step = 2; t = 0
		2:
			if t > 8.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				get_viewport().get_texture().get_image().save_png(out + "/lore_prop.png")
				var f: Vector3 = thin[0]
				var n: Vector3 = thin[1]
				_look(f + n * 1.6 + Vector3(0, 0, 0), f + Vector3.UP * 1.5)
				step = 3; t = 0
		3:
			if t > 6.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				get_viewport().get_texture().get_image().save_png(out + "/lore_thin.png")
				Input.action_press("move_forward")
				step = 4; t = 0
		4:
			if game._transition:
				print("NOCLIPPED after ", t, " s")
				Input.action_release("move_forward")
				step = 5; t = 0
			elif t > 8.0:
				print("FAIL: no noclip; pos ", game.player.global_position)
				get_tree().quit()
		5:
			if t > 12.0:
				print("state ", game.state, " pos ", game.player.global_position)
				get_tree().quit()
