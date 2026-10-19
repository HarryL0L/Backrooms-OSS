extends Node
# Dev harness: chunk culling (ChunkVisibility). From several spots, takes the
# same view with culling on and off (they must match) and logs how many
# chunks were drawn and how long a visibility pass takes.
var game
var out := OS.get_user_data_dir() + "/photo"
var step := 0
var t := 0.0
var spots := []
var phase := 0
var placed := false

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
				Settings.apply_preset(3)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var g: WorldGen = game.gen
				var sp := g.spawn_position()
				var rng := RandomNumberGenerator.new()
				rng.seed = 7
				spots.append([sp, 0.6])
				for i in 7:
					var c := g.spawn_cell + Vector2i(rng.randi_range(-60, 60), rng.randi_range(-60, 60))
					if g.is_solid(c.x, c.y, g.biome_at(c.x, c.y)):
						continue
					spots.append([Vector3((c.x + 0.5) * 2.4, 0.05, (c.y + 0.5) * 2.4), rng.randf() * TAU])
				var vg: ChunkVisibility = ChunkVisibility.new(g)
				var t0 := Time.get_ticks_usec()
				var vis := vg.visible_from(sp, 4.5 * WorldGen.CHUNK_SIZE)
				print("cold pass %.1f ms, %d chunks" % [(Time.get_ticks_usec() - t0) / 1000.0, vis.size()])
				t0 = Time.get_ticks_usec()
				vis = vg.visible_from(sp + Vector3(1, 0, 0), 4.5 * WorldGen.CHUNK_SIZE)
				print("warm pass %.1f ms" % [(Time.get_ticks_usec() - t0) / 1000.0])
				game.hud.set_fade(0.0)
				step = 2; t = 0; phase = 0
		2:
			if spots.is_empty():
				get_tree().quit(); return
			var s: Array = spots[0]
			if not placed:
				placed = true
				game.player.teleport(s[0], s[1], 0.0)
				game.chunks.culling = phase == 0
				if phase == 1:
					for k in game.chunks._chunks:
						game.chunks._chunks[k].visible = true
			if t > 6.0 and game.chunks.is_area_ready(game.player.global_position, 2):
				var n := 0
				for k in game.chunks._chunks:
					if game.chunks._chunks[k].visible:
						n += 1
				var i := 8 - spots.size()
				get_viewport().get_texture().get_image().save_png("%s/cull_%d_%s.png" % [out, i, "on" if phase == 0 else "off"])
				print("spot %d %s: %d of %d chunks drawn" % [i, "on" if phase == 0 else "off", n, game.chunks._chunks.size()])
				phase += 1
				t = 0
				placed = false
				if phase == 2:
					phase = 0
					spots.pop_front()
