extends Node
# Dev harness: Potato + PS1, walks through the world and reports main-thread
# frame-time spikes, plus the cost of the entities' spawn searches.
var game
var step := 0
var t := 0.0
var times := []
var spikes := []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func us(f: Callable, n := 5) -> float:
	var t0 := Time.get_ticks_usec()
	for i in n: f.call()
	return (Time.get_ticks_usec() - t0) / 1000.0 / n

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(0)
				Settings.set_value("graphics/ps1", true)
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING and t > 4.0:
				Input.action_press("move_forward"); Input.action_press("sprint")
				step = 2; t = 0
		2:
			var pt: float = delta * 1000.0
			times.append(pt)
			if pt > 45.0 and t > 1.0: spikes.append([snappedf(t, 0.01), snappedf(pt, 0.1)])
			if int(t * 10) % 40 == 0:
				game.player.yaw += 0.02
			if t > 25.0:
				times.sort()
				print("frames %d  median %.2f ms  p99 %.2f ms  max %.2f ms" % [times.size(), times[times.size() / 2], times[int(times.size() * 0.99)], times[-1]])
				print("frame spikes >45ms: ", spikes.slice(0, 30))
				var g = game.gen
				var p: Vector3 = game.player.global_position
				g.biome_at(3, 7)
				print("biome_at x1000 (cached): %.2f ms" % us(func(): for i in 1000: g.biome_at(3, 7), 1))
				print("light_level_near: %.3f ms" % us(func(): g.light_level_near(p), 20))
				print("nearest_flicker: %.3f ms" % us(func(): g.nearest_flicker(p, 4), 20))
				var hf = game.hall_figure
				print("hall_figure._try_spawn: %.2f ms" % us(func(): hf._try_spawn(); hf._hide(), 3))
				var ln = game.lining
				print("lining._candidates(7,13): %.2f ms" % us(func(): ln._candidates(7.0, 13.0), 3))
				print("fixtures._place: %.2f ms" % us(func(): game.fixtures._place(), 3))
				var cb := ChunkBuilder.new(g, ChunkManager.chunk_of(p) + Vector2i(5, 5))
				var data := cb.build()
				var faces: PackedVector3Array = data.collision
				print("chunk: %d collision tris, %d surfaces" % [faces.size() / 3, data.surfaces.size()])
				print("set_faces: %.2f ms" % us(func(): var sh := ConcavePolygonShape3D.new(); sh.set_faces(faces), 3))
				print("_make_chunk: %.2f ms" % us(func(): game.chunks._make_chunk(data).queue_free(), 3))
				get_tree().quit()
