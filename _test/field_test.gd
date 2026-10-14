extends Node
# Dev harness: loads the game, goes straight to the Field and saves screenshots.
var game
var out := OS.get_user_data_dir() + "/field"
var step := 0
var t := 0.0
var frames := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(name):
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("shot ", name, " pos=", game.player.global_position, " fps=", Engine.get_frames_per_second())

func _process(delta):
	t += delta
	frames += 1
	match step:
		0:
			if game.state == game.State.MENU:
				print("menu ready after ", t)
				game.new_game()
				step = 1; t = 0
		1:
			if game.state == game.State.PLAYING:
				print("playing")
				game.hud.set_fade(0.0)
				game._enter_field()
				step = 2; t = 0; frames = 0
		2:
			if frames == 20:
				# Save while in the Field, go to the menu and continue.
				game._write_save()
				game.exit_to_menu()
				step = 20; t = 0
		20:
			if game.state == game.State.MENU and t > 1.0:
				game.continue_game()
				step = 21; t = 0
		21:
			if game.state == game.State.PLAYING and t > 1.0:
				print("continued in field: ", game._in_field, " pos=", game.player.global_position)
				game.hud.set_fade(0.0)
				step = 22; frames = 0
		22:
			if frames > 30:
				shot("arrival"); step = 3; t = 0; frames = 0
				game.player.teleport(game.player.global_position, PI * 0.8, 0.1)
		3:
			if frames > 5:
				shot("behind"); step = 4; frames = 0
				game.player.teleport(game.player.global_position, -PI * 0.45, -0.25)
		4:
			if frames > 5:
				shot("side_down"); step = 5; frames = 0
				var ep: Vector3 = game.field.exit_pos
				var to := Vector3(-ep.x, 0, -ep.z).normalized()
				var stand := FieldLevel.ground_at(ep.x + to.x * 7.0, ep.z + to.z * 7.0) + Vector3(0, 0.1, 0)
				game.player.teleport(stand, atan2(to.x, to.z), 0.0)
				print("exit door at ", ep, " dist ", Vector2(ep.x, ep.z).length())
		5:
			if frames > 10:
				shot("exit_door"); step = 6; t = 0
				Input.action_press("move_forward")
		6:
			if not game._in_field or t > 8.0:
				Input.action_release("move_forward")
				print("left field: ", not game._in_field, " state=", game.state)
				step = 7; t = 0
		7:
			if game.state == game.State.PLAYING and t > 2.0:
				shot("back"); get_tree().quit()
			elif t > 60.0:
				print("timeout waiting to return, state=", game.state); get_tree().quit()
