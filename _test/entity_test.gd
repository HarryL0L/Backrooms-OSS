extends Node
# Dev harness for the walking entities. Photographs each in its level and
# runs their behaviour:
#   pool:      the far-off voices in the Poolrooms fade up, and stop when
#              you leave.
#   crawler:   in the Unlit Halls, flashlight off then on; then you turn
#              your back and it creeps up and lunges.
#   attendant: in the car park on B1 he sees you and catches you.
#   hide:      you sit in an SUV with the doors shut; he walks past and
#              doesn't see you.
# ONLY=crawler,attendant,... picks parts. Photos in user://photo/ent_*.png.
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var parts := ["pool", "crawler", "attendant", "hide"]
var part := ""
var phase := 0
var ent: Walker
var was_caught := false
var log_t := 0.0
var car: ParkedCar


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	if OS.get_environment("ONLY") != "":
		parts = Array(OS.get_environment("ONLY").split(","))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/ent_%s.png" % [out, name])
	print("shot ", name)


func _find(g: WorldGen, biome: int) -> Vector3:
	for r in range(6, 400, 2):
		for k in 16:
			var a := k * TAU / 16.0
			var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
			if g.biome_at(c.x, c.y) != biome or g.is_solid(c.x, c.y, biome):
				continue
			var nv := EntityNav.new(g, biome)
			if nv.cell_ok(c) and nv.flood(c, 6, 400).size() > 60:
				return EntityNav.center(c) + Vector3.UP * 0.05
	return Vector3.INF


## Puts you at p facing a reachable cell about `dist` m away, and the
## entity there facing you.
func _stage(w: Walker, biome: int, p: Vector3, dist: float) -> void:
	var nv := EntityNav.new(game.gen, biome)
	var here: Vector2i = game.gen.cell_of(p)
	var f := nv.flood(here, ceili(dist / 2.4) + 2, 800)
	var best := here
	var bd := INF
	for c in f:
		var e: float = absf(EntityNav.center(c).distance_to(p) - dist)
		if e < bd and _clear_line(p, EntityNav.center(c)):
			bd = e
			best = c
	var at := EntityNav.center(best)
	var d := at - p
	game.player.teleport(p, atan2(-d.x, -d.z), -0.05)
	w.debug_place(at, p)


func _clear_line(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a + Vector3.UP * 1.4, b + Vector3.UP * 1.4)
	q.exclude = [game.player.get_rid()]
	return game.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _next_part() -> void:
	if parts.is_empty():
		print("entity_test: done")
		get_tree().quit()
		return
	part = parts.pop_front()
	phase = 0
	t = 0.0
	print("--- ", part)


func _process(delta):
	t += delta
	log_t += delta
	if ent and ent.present and log_t > 0.5:
		log_t = 0.0
		print("  t %.1f d %.1f state %s pos %s" % [t, ent._dist(), ent.get("_state"), ent.global_position])
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/ps1", false)
				Settings.apply_preset(4)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game()
				step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				game.attendant.caught.connect(func(): was_caught = true)
				# Nothing turns up on its own during the test.
				for w in game._walkers():
					w.set("_timer", 1e9)
				step = 2
				_next_part()
		2:
			call("_" + part)


func _ready_here() -> bool:
	return t > 3.0 and game.chunks.is_area_ready(game.player.global_position, 1)


func _pool():
	var pv: PoolVoices = game.ambience.find_children("*", "PoolVoices", false, false)[0]
	match phase:
		0:
			var p := Vector3.INF
			var g: WorldGen = game.gen
			for r in range(6, 400, 2):
				for k in 16:
					var a := k * TAU / 16.0
					var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
					if p == Vector3.INF and g.biome_at(c.x, c.y) == WorldGen.POOL and not g.pool_noise(c.x, c.y) \
							and g.biome_at(c.x + 3, c.y) == WorldGen.POOL and g.biome_at(c.x - 3, c.y) == WorldGen.POOL:
						p = Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4)
			game.player.teleport(p, 0.0)
			phase = 1; t = 0
		1:
			if int(t * 2.0) != int((t - get_process_delta_time()) * 2.0) and int(t) % 5 == 0:
				print("pool t %.0f voices %s" % [t, pv._voices.map(func(v): return "%s %.1f dB %.0f m" % [v.playing, v.volume_db, v.global_position.distance_to(game.player.global_position)] if v.playing else "-")])
			if t > 32.0:
				game.player.teleport(game.gen.spawn_position(), 0.0)
				phase = 2; t = 0
		2:
			if t > 4.0:
				print("pool voices after leaving: ", pv._voices.map(func(v): return v.playing))
				_next_part()


func _crawler():
	var cr: CrawlerEntity = game.crawler
	ent = cr
	match phase:
		0:
			var p := _find(game.gen, WorldGen.DARK)
			game.player.teleport(p, 0.0)
			game.player.set_flashlight(false)
			phase = 1; t = 0
		1:
			if _ready_here():
				_stage(cr, WorldGen.DARK, game.player.global_position, 4.5)
				cr.set_process(false)
				phase = 2; t = 0
		2:
			if t > 1.5:
				_shot("crawler_dark")
				game.player.set_flashlight(true)
				phase = 3; t = 0
		3:
			if t > 1.0:
				_shot("crawler_lit")
				phase = 31; t = 0
		31:
			if t > 0.5:
				game.player.set_flashlight(false)
				# Back turned: let it come.
				cr.set_process(true)
				game.player.yaw += PI
				game.player._apply_rotation()
				game.player.stamina = 1.0
				game.player.exhausted = false
				phase = 4; t = 0
		4:
			if not cr.present or t > 15.0:
				print("crawler lunged: stamina %.2f exhausted %s present %s after %.1f s" % [game.player.stamina, game.player.exhausted, cr.present, t])
				# And with the beam on it: it flees.
				_stage(cr, WorldGen.DARK, game.player.global_position, 6.0)
				game.player.set_flashlight(true)
				phase = 5; t = 0
		5:
			if not cr.present or t > 6.0:
				print("crawler fled from the beam: gone %s after %.1f s" % [not cr.present, t])
				game.player.set_flashlight(false)
				_next_part()


func _to_garage() -> void:
	game._floor = -1
	game._use_gen(WorldGen.new(game.gen.seed_value, -1), true)


func _attendant():
	var at: AttendantEntity = game.attendant
	ent = at
	match phase:
		0:
			_to_garage()
			var p := _find(game.gen, WorldGen.GARAGE)
			game.player.teleport(p, 0.0)
			phase = 1; t = 0
		1:
			if _ready_here():
				_stage(at, WorldGen.GARAGE, game.player.global_position, 14.0)
				at.set_process(false)
				phase = 2; t = 0
		2:
			if t > 1.5:
				_shot("attendant")
				at.set_process(true)
				was_caught = false
				phase = 3; t = 0
		3:
			if t > 0.9 and t < 1.0:
				_shot("attendant_chase")
			if was_caught or t > 12.0:
				print("attendant caught you: %s after %.1f s" % [was_caught, t])
				phase = 4; t = 0
		4:
			# Let the caught sequence finish before going on.
			if t > 1.0 and not game._transition and game.state == game.State.PLAYING:
				_next_part()


func _hide():
	var at: AttendantEntity = game.attendant
	ent = at
	match phase:
		0:
			if game.gen.floor_index != -1:
				_to_garage()
			var g: WorldGen = game.gen
			var rc0 := Vector2i(floori(float(g.spawn_cell.x) / 16), floori(float(g.spawn_cell.y) / 16))
			var suv := []
			for r in range(0, 6):
				for dz in range(-r, r + 1):
					for dx in range(-r, r + 1):
						var res := {}
						LobbyDetails._compute(g, rc0 + Vector2i(dx, dz), res)
						for e in res.props:
							if e[1] == LobbyDetails.SUV and suv.is_empty():
								suv = e
			var b := Basis(Vector3.UP, suv[3]) * Basis(Vector3.UP, PI * 0.5)
			game.player.teleport(suv[0] + b * Vector3(0.6, 0.05, 1.9), 0.0)
			phase = 1; t = 0
		1:
			if _ready_here():
				for n in get_tree().get_nodes_in_group("usable"):
					if car == null or n.global_position.distance_to(game.player.global_position) < car.global_position.distance_to(game.player.global_position):
						car = n
				car.use("getin", game.player)
				phase = 2; t = 0
		2:
			if t > 3.0:
				print("seated %s sheltered %s" % [game.player.seated, car.sheltered()])
				# He comes walking down the lane past the car.
				var p: Vector3 = car.global_transform * Vector3(0, 0, 4.0)
				var nv := EntityNav.new(game.gen, WorldGen.GARAGE)
				var c: Vector2i = game.gen.cell_of(p)
				at.debug_place(EntityNav.center(c), car.global_position)
				at.set("_last_known", car.global_position)
				at.call("_search")
				was_caught = false
				phase = 3; t = 0
		3:
			if t > 1.0 and t < 1.1:
				_shot("hide_peer")
			if was_caught or t > 16.0:
				print("hidden in the car: caught %s, state %s, present %s" % [was_caught, at._state, at.present])
				_next_part()
