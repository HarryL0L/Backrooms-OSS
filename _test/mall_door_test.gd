extends Node
# Dev harness: finds a Dead Mall door in the Yellow Halls, walks through it, checks
# the mall loads; then walks out through the mall's exit door.
var game
var out := OS.get_user_data_dir() + "/mall_door"
var step := 0
var t := 0.0
var door

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(n):
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				# Search regions for a mall door.
				var od = game.odd_doors
				var found := {}
				var g = game.gen
				for rx in range(-12, 13):
					for rz in range(-12, 13):
						var d = od.door_in_region(Vector2i(rx, rz))
						if not d.is_empty() and d.mall:
							found = d; break
					if not found.is_empty(): break
				print("mall door at ", found)
				# Stand in front of it (it faces +X) looking at it.
				var p: Vector3 = found.pos + Vector3(2.0, 0.05, 0)
				game.player.teleport(p, PI * 0.5, 0.0)
				step = 2; t = 0
		2:
			if t > 6.0:
				shot("door")
				Input.action_press("move_forward")
				step = 3; t = 0
		3:
			if game._in_mall and t > 1.0:
				Input.action_release("move_forward")
				print("in the mall: ", game._in_mall, " at ", game.player.global_position)
				step = 4; t = 0
			elif t > 15.0:
				print("did not reach the mall"); get_tree().quit()
		4:
			if t > 4.0 and not game._transition:
				game.hud.set_fade(0.0)
				shot("arrived")
				# Walk to the exit door.
				var ex: Transform3D = game.mall.spots["spot_exit"]
				game.player.teleport(ex.origin + Vector3(1.8, 0.05, 0), PI * 0.5, 0.0)
				step = 5; t = 0
		5:
			if t > 1.0 and t < 1.1:
				shot("exit_door")
			if t > 1.2:
				Input.action_press("move_forward")
			if not game._in_mall and t > 2.0:
				Input.action_release("move_forward")
				print("left the mall: back in backrooms at ", game.player.global_position)
				get_tree().quit()
			if t > 15.0:
				print("could not leave"); get_tree().quit()
