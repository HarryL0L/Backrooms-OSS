extends Node
# Dev harness: the same Lobby view with the standard camera and with the
# Human eye camera. user://photo/eye_standard.png, eye_human.png
var game
var step := 0
var t := 0.0
var out := OS.get_user_data_dir() + "/photo"

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
				Settings.set_value("graphics/auto_quality", false)
				Settings.apply_preset(4)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				var sp: Vector3 = game.gen.spawn_position()
				game.player.teleport(sp + Vector3(0.6, 0, 0.6), 0.6, -0.03)
				Settings.set_value("graphics/human_eye", false)
				step = 2; t = 0
		2:
			if t > 14.0:
				get_viewport().get_texture().get_image().save_png(out + "/eye_standard.png")
				Settings.set_value("graphics/human_eye", true)
				step = 3; t = 0
		3:
			if t > 1.0:
				get_viewport().get_texture().get_image().save_png(out + "/eye_human.png")
				get_tree().quit()
