extends Node
# Films both jumpscares (with sound, Godot's movie writer): the car park's
# tall one runs you down; then the crawler in the Unlit Halls reaches you.
#   godot --path . --fixed-fps 30 --resolution 1280x720 --write-movie js.avi res://_test/jumpscare_film.tscn
var game
var step := 0
var t := 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

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

func _stage(w: Walker, biome: int, dist: float, behind := false) -> void:
	var p: Vector3 = game.player.global_position
	var nv := EntityNav.new(game.gen, biome)
	var f := nv.flood(game.gen.cell_of(p), ceili(dist / 2.4) + 2, 800)
	var best: Vector2i = game.gen.cell_of(p)
	var bd := INF
	for c in f:
		var e: float = absf(EntityNav.center(c).distance_to(p) - dist)
		var q := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.4, EntityNav.center(c) + Vector3.UP * 1.4)
		q.exclude = [game.player.get_rid()]
		if e < bd and game.get_world_3d().direct_space_state.intersect_ray(q).is_empty():
			bd = e
			best = c
	var at := EntityNav.center(best)
	var d := at - p
	var yaw := atan2(-d.x, -d.z) + (PI if behind else 0.0)
	game.player.teleport(p, yaw, -0.05)
	w.debug_place(at, p)

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
				game.hud.set_fade(1.0)
				for w in game._walkers():
					w.set("_timer", 1e9)
				game._floor = -1
				game._use_gen(WorldGen.new(game.gen.seed_value, -1), true)
				game.player.teleport(_find(game.gen, WorldGen.GARAGE), 0.0)
				step = 2; t = 0
		2:
			if t > 3.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				_stage(game.attendant, WorldGen.GARAGE, 12.0)
				game.hud.set_fade(0.0)
				step = 3; t = 0
		3:
			if game._transition and step == 3:
				print("js: caught after %.1f s" % t)
				step = 4; t = 0
			elif t > 15.0:
				print("js: never caught"); step = 4; t = 0
		4:
			if t > 8.0 and not game._transition and game.state == game.State.PLAYING:
				game._floor = 0
				game._use_gen(WorldGen.new(game.gen.seed_value, 0), true)
				game.player.teleport(_find(game.gen, WorldGen.DARK), 0.0)
				game.player.set_flashlight(true)
				game.hud.set_fade(1.0)
				step = 5; t = 0
		5:
			if t > 3.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				# Behind you, close.
				_stage(game.crawler, WorldGen.DARK, 5.0, true)
				game.hud.set_fade(0.0)
				step = 6; t = 0
		6:
			if game.crawler._state == CrawlerEntity.SCARE and step == 6:
				print("js: crawler lunged after %.1f s" % t)
				step = 7; t = 0
			elif t > 20.0:
				print("js: crawler never came, state ", game.crawler._state); step = 7; t = 0
		7:
			if t > 3.0:
				get_tree().quit()
