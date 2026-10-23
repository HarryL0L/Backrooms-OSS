extends Node
# Films the car park's tall one, first person, with sound (Godot's movie
# writer). You stand by an SUV; it prowls far off. You get in and the door
# slams: it hears, comes, searches, stoops to look in at the window,
# breathing, and walks off. You get out and run: it hears you, screams,
# runs you down. Run with
#   godot --path . --fixed-fps 30 --resolution 1280x720 --write-movie film.avi res://_test/garage_film.tscn
var game
var step := 0
var t := 0.0
var total := 0.0
var car: ParkedCar
var at: AttendantEntity
var yaw_to := 0.0
var pitch_to := 0.0
var track := true
var turn := 2.5
var caught := false

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _aim(p: Vector3) -> void:
	var d: Vector3 = p - game.player.camera.global_position
	yaw_to = atan2(-d.x, -d.z)
	pitch_to = clampf(atan2(d.y, Vector2(d.x, d.z).length()), -0.6, 0.5)

func _steer(delta: float) -> void:
	var p: Player = game.player
	if p._ride_t >= 0.0:
		return
	var k := 1.0 - exp(-turn * delta)
	p.yaw = lerp_angle(p.yaw, yaw_to, k)
	p.pitch = lerpf(p.pitch, pitch_to, k)
	p._apply_rotation()

func _head() -> Vector3:
	return at.global_position + Vector3.UP * 2.1

func _process(delta):
	t += delta
	total += delta
	if game.player and step >= 3:
		if track and at and at.present:
			_aim(_head())
		_steer(delta)
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				Settings.apply_preset(4)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(1.0)
				game._floor = -1
				game._use_gen(WorldGen.new(game.gen.seed_value, -1), true)
				at = game.attendant
				at.set("_timer", 1e9)          # it's placed, below
				var g: WorldGen = game.gen
				var rc0 := Vector2i(floori(float(g.spawn_cell.x) / 16), floori(float(g.spawn_cell.y) / 16))
				var suv := []
				for r in range(1, 6):
					for dz in range(-r, r + 1):
						for dx in range(-r, r + 1):
							var res := {}
							LobbyDetails._compute(g, rc0 + Vector2i(dx, dz), res)
							for e in res.props:
								if e[1] == LobbyDetails.SUV and not e[7] and suv.is_empty():
									suv = e
				var b := Basis(Vector3.UP, suv[3]) * Basis(Vector3.UP, PI * 0.5)
				var door: Vector3 = suv[0] + b * Vector3(-0.3, 0.05, 2.2)
				var out: Vector3 = b * Vector3(0, 0, 1)
				game.player.teleport(door, atan2(-out.x, -out.z), 0.0)
				step = 2; t = 0
		2:
			if t > 3.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				for n in get_tree().get_nodes_in_group("usable"):
					if n is ParkedCar and (car == null or n.global_position.distance_to(game.player.global_position) < car.global_position.distance_to(game.player.global_position)):
						car = n
				# It, far down the lane, walking away from you.
				var nv := EntityNav.new(game.gen, WorldGen.GARAGE)
				var here: Vector2i = game.gen.cell_of(game.player.global_position)
				var f := nv.flood(here, 10, 900)
				var best := here
				var bd := INF
				for c in f:
					var e := absf(EntityNav.center(c).distance_to(game.player.global_position) - 16.0)
					var q := PhysicsRayQueryParameters3D.create(game.player.camera.global_position, EntityNav.center(c) + Vector3.UP * 1.6)
					q.exclude = [game.player.get_rid()]
					if e < bd and game.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
						bd = e
						best = c
				var p := EntityNav.center(best)
				at.debug_place(p, p + (p - game.player.global_position))
				game.hud.set_fade(0.0)
				track = true
				turn = 1.6
				step = 3; t = 0
		3:
			# Seen it. Into the car, quietly as you can (the door still slams).
			if t > 4.0:
				track = false
				_aim(car.global_transform * Vector3(-0.3, 1.0, 0.9))
			if t > 5.0:
				car.use("DoorFL", game.player)
				step = 4; t = 0
		4:
			if t > 1.0:
				car.use("getin", game.player)
				step = 5; t = 0
		5:
			# Seated, the door pulled shut. Watch it.
			if t > 2.6:
				track = true
				turn = 2.0
			if t > 3.0:
				print("film: seated, it is ", at._state)
				step = 6; t = 0
		6:
			if at._state == AttendantEntity.LEAVE and at._dist() > 12.0 and t > 4.0:
				print("film: it left after %.0f s" % t)
				step = 7; t = 0
			if t > 50.0:
				print("film: it never left, state ", at._state)
				step = 7; t = 0
		7:
			if t > 2.0:
				car.use("getout", game.player)
				step = 8; t = 0
		8:
			if t > 2.2:
				# Away from it, running.
				track = false
				var away: Vector3 = game.player.global_position - at.global_position
				_aim(game.player.camera.global_position + Vector3(away.x, 0, away.z).normalized() * 5.0)
				turn = 6.0
				Input.action_press("move_forward")
				Input.action_press("sprint")
				step = 9; t = 0
		9:
			if at._state == AttendantEntity.CHASE and t > 1.0:
				print("film: it's coming")
				Input.action_release("sprint")
				Input.action_release("move_forward")
				step = 10; t = 0
			elif t > 4.0:
				Input.action_release("sprint")
				Input.action_release("move_forward")
				step = 10; t = 0
		10:
			# Look back.
			if t > 0.4:
				track = true
				turn = 5.0
			if game._transition or t > 15.0:
				print("film: caught ", game._transition)
				step = 11; t = 0
		11:
			if t > 7.0:
				print("film: %.1f s" % total)
				get_tree().quit()
