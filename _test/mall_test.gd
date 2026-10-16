extends Node
# Dev harness: enters the Dead Mall and takes screenshots along it.
var game
var out := OS.get_user_data_dir() + "/mall"
var step := 0
var t := 0.0
var views := [
	["arrival", Vector3(4, 0, -2), -PI * 0.5, 0.0],
	["concourse", Vector3(24, 0, 3.5), -PI * 0.5, 0.05],
	["window", Vector3(31, 0, 2.5), 0.4, 0.0],
	["court", Vector3(62, 0, -9), -PI * 0.62, 0.12],
	["fountain", Vector3(72, 0, 5), PI * 0.65, 0.05],
	["food", Vector3(128, 0, 0), -PI * 0.5, 0.0],
	["exit_door", Vector3(3.5, 0, 0), PI * 0.8, 0.0],
]
var vi := 0

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
				if OS.get_environment("PRESET") != "":
					Settings.apply_preset(int(OS.get_environment("PRESET")))
				if OS.get_environment("PS1") != "":
					Settings.set_value("graphics/ps1", true)
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				game._enter_mall()
				step = 2; t = 0
		2:
			if t > 2.0:
				var v = views[vi]
				game.player.teleport(Vector3(v[1].x, MallLevel.MALL_Y + 0.05, v[1].z), v[2], v[3])
				game.hud.set_fade(0.0)
				step = 3; t = 0
		3:
			if t > 1.2:
				get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, views[vi][0]])
				print("shot ", views[vi][0])
				vi += 1
				if vi >= views.size():
					print("decoys ", game.mall.decoys.size(), " spots ", game.mall.spots.size(), " mannequin spots ", game.mall.mannequin_spots.size())
					get_tree().quit(); return
				step = 2; t = 2.0
