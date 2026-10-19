extends Node
# Dev harness: an uncovered SUV in the car park on B1. Photographs it shut,
# then uses it the way a player would (aim at the handle, press Use): driver
# door open, key turned, dome light on; and a covered car for its shadow.
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var views := []
var placed := false
var suv := []
var cov := []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _look(eye: Vector3, at: Vector3):
	var d := at - eye
	game.player.teleport(Vector3(eye.x, 0.05, eye.z), atan2(-d.x, -d.z), atan2(at.y - 1.6, Vector2(d.x, d.z).length()))

func _car() -> ParkedCar:
	var best: ParkedCar = null
	for n in get_tree().get_nodes_in_group("usable"):
		if best == null or n.global_position.distance_to(suv[0]) < best.global_position.distance_to(suv[0]):
			best = n
	return best

func _aim_use(id: String) -> void:
	var car := _car()
	for tg in car.use_targets(game.player):
		if tg[0] == id:
			var p: Vector3 = tg[1]
			var cam: Camera3D = game.player.camera
			var d := p - cam.global_position
			game.player.yaw = atan2(-d.x, -d.z)
			game.player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
			game.player.rotation.y = game.player.yaw
			game.player.add_look(0.0, 0.0)
	await get_tree().process_frame
	await get_tree().process_frame
	print("target ", game._use_target.slice(1), " for ", id)
	game._use()

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
				var rc0 := Vector2i(floori(float(g.spawn_cell.x) / 16), floori(float(g.spawn_cell.y) / 16))
				for r in range(0, 8):
					for dz in range(-r, r + 1):
						for dx in range(-r, r + 1):
							if maxi(absi(dx), absi(dz)) != r:
								continue
							var res := {}
							LobbyDetails._compute(g, rc0 + Vector2i(dx, dz), res)
							for p in res.props:
								if p[1] == LobbyDetails.SUV and suv.is_empty() and (OS.get_environment("DAMAGED") == "") != p[7]:
									suv = p
								if p[1] == LobbyDetails.CAR and cov.is_empty():
									cov = p
				print("suv ", suv, "\ncovered ", cov)
				var sp: Vector3 = suv[0]
				var b := Basis(Vector3.UP, suv[3]) * Basis(Vector3.UP, PI * 0.5)
				# Car space: front -X, driver side +Z.
				views.append(["front", sp + b * Vector3(-5.0, 0, 3.0), sp + Vector3(0, 0.7, 0), ""])
				# Get in, start it, and look at the dashboard from the seat.
				views.append(["seat", sp + b * Vector3(0.6, 0, 1.9), sp + b * Vector3(-0.3, 1.2, 0.9), "DoorFL,getin,key", sp + b * Vector3(-3.0, 1.0, 0.37)])
				views.append(["lights", sp + b * Vector3(-7.0, 0, 2.2), sp + b * Vector3(-2.0, 0.5, 0.0), ""])
				var cp: Vector3 = cov[0]
				views.append(["covered", cp + Vector3(2.4, 0, -4.6), cp + Vector3(0, 0.6, 0), ""])
				# A column's bay number, and a stairwell landing's light.
				var res2 := {}
				LobbyDetails._compute(g, Vector2i(floori(sp.x / 2.4 / 16), floori(sp.z / 2.4 / 16)), res2)
				for sg in res2.signs:
					if (sg as Array).size() > 5:
						views.append(["column", (sg[0] as Vector3) + Vector3(0.6, -1.7, -2.2), (sg[0] as Vector3), ""])
						break
				var sb: Vector2i = g.stair_block(1, 1)
				var so := Vector3(sb.x * 2.4, 0, sb.y * 2.4)
				views.append(["stair_lamp", so + Vector3(1.2, 0.05, 1.2), so + Vector3(0.2, 2.75, 3.8), ""])
				game.hud.set_fade(0.0)
				step = 2; t = 0
		2:
			if views.is_empty():
				get_tree().quit(); return
			var v: Array = views[0]
			if not placed:
				_look(v[1], v[2]); placed = true
			if t > 6.0 and v[3] != "" and game.chunks.is_area_ready(game.player.global_position, 1):
				var ids: PackedStringArray = (v[3] as String).split(",")
				v[3] = ""
				for id in ids:
					await _aim_use(id)
					await get_tree().create_timer(2.6 if id == "getin" else 0.8).timeout
				if "getin" in ids:
					# Stay in the seat: just look ahead.
					await get_tree().create_timer(1.5).timeout
					var d: Vector3 = v[4] - game.player.camera.global_position
					game.player.yaw = atan2(-d.x, -d.z)
					game.player.pitch = atan2(d.y, Vector2(d.x, d.z).length())
					game.player._apply_rotation()
				else:
					_look(v[1], v[2])
				t = 5.0
			if t > 7.0 and v[3] == "" and game.chunks.is_area_ready(game.player.global_position, 1):
				get_viewport().get_texture().get_image().save_png("%s/suv_%s.png" % [out, v[0]])
				print("shot ", v[0])
				views.pop_front(); placed = false; t = 0
