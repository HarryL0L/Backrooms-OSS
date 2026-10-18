extends Node
# Dev harness: a stairwell. Photographs its door from the halls, the landing,
# the half landing, goes down past the half landing (the floor should change
# to B1 with you moved up one floor height), then the landing door on B1
# (open once B1 is built) and B1's halls outside.
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var o := Vector3.ZERO      # stairwell origin
var shots := []
var placed := false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _look(eye: Vector3, at: Vector3):
	var d := at - eye
	game.player.teleport(eye, atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func _shot(n: String):
	get_viewport().get_texture().get_image().save_png("%s/stairs_%s.png" % [out, n])
	print("shot ", n, " floor ", game._floor, " y ", snappedf(game.player.global_position.y, 0.01), " in_stairwell ", game.player.in_stairwell)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/ps1", false)
				Settings.apply_preset(int(OS.get_environment("PRESET")) if OS.get_environment("PRESET") != "" else 4)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var g: WorldGen = game.gen
				var best := Vector2i.ZERO
				var bd := INF
				for sz in range(-2, 3):
					for sx in range(-2, 3):
						var b := g.stair_block(sx, sz)
						if b.x == WorldGen.NO_STAIRS:
							continue
						var d := Vector2(b - g.spawn_cell).length()
						if d < bd:
							bd = d; best = b
				o = Vector3(best.x * 2.4, 0.0, best.y * 2.4)
				print("stairwell at ", best)
				game.hud.set_fade(0.0)
				shots = [
					["door", o + Vector3(-3.4, 0.05, 1.2 + 0.6), o + Vector3(0.0, 1.2, 1.2)],
					["landing", o + Vector3(0.6, 0.05, 1.2), o + Vector3(5.0, -1.2, 1.2)],
					["half", o + Vector3(6.6, -1.95, 1.0), o + Vector3(2.0, -3.4, 3.6)],
				]
				step = 2; t = 0
		2:
			if shots.is_empty():
				# Down past the half landing, on flight B.
				_look(o + Vector3(4.6, -2.45, 3.6), o + Vector3(1.0, -4.0, 3.6))
				step = 3; t = 0
				return
			var s: Array = shots[0]
			if not placed:
				_look(s[1], s[2]); placed = true
			if t > 5.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				_shot(s[0]); shots.pop_front(); t = 0; placed = false
		3:
			if t > 3.0:
				_shot("past_half")
				step = 4; t = 0
		4:
			if not placed:
				_look(o + Vector3(0.9, 0.05, 2.0), o + Vector3(-1.0, 1.0, 1.2)); placed = true
			if t > 8.0 and game.chunks.is_area_ready(o, 1):
				_shot("b1_door")
				_look(o + Vector3(-3.2, 0.05, 1.2), o + Vector3(-12.0, 1.2, 1.2))
				step = 5; t = 0
		5:
			if t > 5.0:
				_shot("b1_halls")
				print("floor index ", game.gen.floor_index, " hud level shown")
				get_tree().quit()
