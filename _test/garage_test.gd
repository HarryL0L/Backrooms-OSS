extends Node
# Dev harness: the car park on B1. Switches to floor B1 (as the stairs do)
# and photographs a lane, a covered car in its bay and a numbered column.
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
	game.player.teleport(Vector3(eye.x, 0.05, eye.z), atan2(-d.x, -d.z), atan2(at.y - 1.6, Vector2(d.x, d.z).length()))

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
				game._floor = -1
				game._use_gen(WorldGen.new(game.gen.seed_value, -1), true)
				var g: WorldGen = game.gen
				var C := WorldGen.CELL
				# A lane with car park all round.
				var lane := Vector2i.MAX
				var car := []
				for r in range(8, 120, 2):
					for k in 24:
						var a := k * TAU / 24.0
						var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
						c.y -= posmod(c.y, 4) - 2
						var ok := true
						for d in [Vector2i(-3, 0), Vector2i(3, 0), Vector2i(0, -2), Vector2i(0, 2), Vector2i(6, 0)]:
							if g.biome_at(c.x + d.x, c.y + d.y) != WorldGen.GARAGE:
								ok = false
						if ok and lane == Vector2i.MAX:
							lane = c
				var rc := Vector2i(floori(float(lane.x) / 16), floori(float(lane.y) / 16))
				for dz in range(-3, 4):
					for dx in range(-3, 4):
						var res := {}
						LobbyDetails._compute(g, rc + Vector2i(dx, dz), res)
						for p in res.props:
							if p[1] == LobbyDetails.CAR and car.is_empty():
								car = p
				print("lane ", lane, " car ", car)
				var lp := Vector3((lane.x + 0.5) * C, 0.0, (lane.y + 0.5) * C)
				if OS.get_environment("ONLY_CAR") == "":
					views.append(["lane", lp, lp + Vector3(12.0, 1.4, 0.0)])
				if OS.get_environment("ONLY_CAR") == "":
					views.append(["bays", lp + Vector3(0, 0, -0.6), lp + Vector3(4.0, 0.6, -4.0)])
				var col := Vector3(floorf(lane.x / 3.0) * 3.0 * C, 0.0, (lane.y + 2) * C)
				if OS.get_environment("ONLY_CAR") == "":
					views.append(["column", col + Vector3(1.0, 0, -2.0), col + Vector3(0, 1.7, -0.3)])
				if not car.is_empty():
					var cp: Vector3 = car[0]
					views.append(["car", cp + Vector3(2.0, 0, -5.0), cp + Vector3(0, 0.7, 0)])
				game.hud.set_fade(0.0)
				step = 2; t = 0
		2:
			if views.is_empty():
				get_tree().quit(); return
			var v: Array = views[0]
			if not placed:
				_look(v[1], v[2]); placed = true
			if t > 7.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				get_viewport().get_texture().get_image().save_png("%s/garage_%s.png" % [out, v[0]])
				print("shot ", v[0], " biome ", game.gen.biome_at(game.gen.cell_of(game.player.global_position).x, game.gen.cell_of(game.player.global_position).y))
				views.pop_front(); placed = false; t = 0
