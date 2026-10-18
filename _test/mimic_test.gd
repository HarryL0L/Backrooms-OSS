extends Node
# Dev harness: the Lobby's not-quite-right copies of an ordinary building.
# Finds and photographs an exit sign, a plaque, a door to nowhere, stairs
# into the ceiling, a thirteen-hour clock and an odd outlet.
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
				Settings.apply_preset(4)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var g: WorldGen = game.gen
				var rc := Vector2i(floori(float(g.spawn_cell.x) / 16), floori(float(g.spawn_cell.y) / 16))
				var want := {"exit": null, "plaque": null, "door": null, "stairs": null, "clock": null, "outlet": null}
				for rad in 10:
					for dz in range(-rad, rad + 1):
						for dx in range(-rad, rad + 1):
							if maxi(absi(dx), absi(dz)) != rad:
								continue
							var res := {}
							LobbyDetails._compute(g, rc + Vector2i(dx, dz), res)
							for s in res.signs:
								var k := "exit" if s[3] else "plaque"
								if want[k] == null:
									want[k] = [s[0], s[1], 1.6 if s[3] else 1.0]
							for f in res.fakes:
								var k := "door" if f[0] == LobbyDetails.FAKE_DOOR else "stairs"
								if want[k] == null:
									want[k] = [f[1] + Vector3.UP * 1.2, f[2], 1.95]
							for it in res.items:
								if it[1] == LobbyDetails.CLOCK and want.clock == null:
									want.clock = [it[0].origin, it[0].basis.z.normalized(), 1.6]
								if it[1] == LobbyDetails.OUTLET_ODD and want.outlet == null:
									want.outlet = [it[0].origin, it[0].basis.z.normalized(), 0.9]
				for k in want:
					if want[k] != null:
						views.append([k] + want[k])
					else:
						print("not found: ", k)
				game.hud.set_fade(0.0)
				step = 2; t = 0
		2:
			if views.is_empty():
				get_tree().quit(); return
			var v: Array = views[0]
			if not placed:
				var p: Vector3 = v[1]
				var n: Vector3 = v[2]
				_look(p + n * float(v[3]), p)
				placed = true
			if t > 6.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				get_viewport().get_texture().get_image().save_png("%s/mimic_%s.png" % [out, v[0]])
				print("shot ", v[0], " target ", v[1], " n ", v[2], " player ", game.player.global_position, " yaw ", game.player.yaw, " pitch ", game.player.pitch)
				var near := 0
				var far := []
				for m in game.details.find_children("*", "MeshInstance3D", true, false):
					var dd: float = (m as Node3D).global_position.distance_to(v[1])
					if dd < 3.0:
						near += 1
					far.append(snappedf(dd, 0.1))
				far.sort()
				print("   pieces near ", near, " nearest ", far.slice(0, 4))
				views.pop_front(); placed = false; t = 0
