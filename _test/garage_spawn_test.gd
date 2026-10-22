extends Node
# Dev harness: lets the car park's tall one turn up on its own (no
# placing) while you stand in the car park, and logs where it is.
var game
var step := 0
var t := 0.0
var log_t := 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _process(delta):
	t += delta
	log_t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				game._floor = -1
				game._use_gen(WorldGen.new(game.gen.seed_value, -1), true)
				var g: WorldGen = game.gen
				var p: Vector3 = g.spawn_position()
				for r in range(4, 200, 2):
					var c: Vector2i = g.spawn_cell + Vector2i(r, 0)
					if g.biome_at(c.x, c.y) == WorldGen.GARAGE and not g.stair_zone(c.x, c.y, 4):
						p = Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4)
						break
				game.player.teleport(p, 0.0)
				step = 2; t = 0
		2:
			var a: AttendantEntity = game.attendant
			if log_t > 3.0:
				log_t = 0.0
				print("t %.0f allowed %s biome %d timer %.1f present %s state %s dist %s" % [t, a.allowed, a._player_biome() if a.gen else -1, a._timer, a.present, a._state, a._dist() if a.present else -1.0])
			if t > 150.0:
				get_tree().quit()
