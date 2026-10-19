extends Node
# Dev harness: close-ups of a stairwell (door from both sides, a flight, a
# light, the shaft above) on the Lobby floor.
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var views := []
var placed := false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _look(eye: Vector3, at: Vector3):
	var d := at - eye
	game.player.teleport(Vector3(eye.x, eye.y - 1.62, eye.z), atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(int(OS.get_environment("PRESET")) if OS.get_environment("PRESET") != "" else 4)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var b: Vector2i = game.gen.stair_block(1, 1)
				var o := Vector3(b.x * 2.4, 0, b.y * 2.4)
				views = [
					["door_in", o + Vector3(1.3, 1.62, 3.4), o + Vector3(0.0, 1.0, 1.2)],
					["door_out", o + Vector3(-2.2, 1.62, 0.4), o + Vector3(0.0, 1.0, 1.2)],
					["door_jamb", o + Vector3(-0.8, 1.62, 2.4), o + Vector3(0.0, 1.2, 1.75)],
					["flight", o + Vector3(1.0, 1.62, 1.2), o + Vector3(5.5, -1.0, 1.2)],
					["lamp", o + Vector3(0.75, 2.15, 3.3), o + Vector3(0.2, 2.75, 3.8)],
					["up", o + Vector3(1.2, 1.62, 3.6), o + Vector3(3.0, 5.0, 3.6)],
					["half", o + Vector3(6.5, -2.0 + 1.62, 1.0), o + Vector3(2.0, -3.0, 3.6)],
				]
				if OS.get_environment("ONLY") != "":
					views = views.filter(func(v): return v[0] in OS.get_environment("ONLY").split(","))
				game.hud.set_fade(0.0)
				step = 2; t = 0
		2:
			if views.is_empty():
				get_tree().quit(); return
			var v: Array = views[0]
			if not placed:
				_look(v[1], v[2]); placed = true
				game.player.set_physics_process(false)
			if t > 5.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				get_viewport().get_texture().get_image().save_png("%s/sw_%s%s.png" % [out, v[0], OS.get_environment("TAG")])
				print("shot ", v[0])
				views.pop_front(); placed = false; t = 0
