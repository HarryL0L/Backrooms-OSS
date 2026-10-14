extends Node
# Dev harness: screenshots of a Poolrooms sun gallery (windows, sun patches, god rays).
var game
var out := OS.get_user_data_dir() + "/gallery"
var step := 0
var t := 0.0
var pos := Vector3.ZERO
var views := [[-PI * 0.5, 0.05, "along_east"], [PI * 0.5, 0.05, "along_west"], [PI * 0.75, 0.15, "windows"], [-PI * 0.2, -0.25, "patches"], [0.55, 0.12, "rays"]]
var vi := 0

func _ready():
	if OS.get_environment("NORAYS") != "": ChunkBuilder.god_rays = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(name):
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

func _process(delta):
	t += delta
	var g = game.gen
	match step:
		0:
			if game.state == game.State.MENU:
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				if OS.get_environment("NORAYS") != "": ChunkBuilder.god_rays = false
				var found := Vector2i.ZERO
				var ok := false
				for r in range(6, 400, 2):
					for k in 32:
						var a := k * TAU / 32.0
						var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
						c.y = c.y - posmod(c.y, 5) + 1
						var good: bool = true
						for dx in range(-6, 7):
							for dz in range(-1, 5):
								if g.biome_at(c.x + dx, c.y + dz) != 1 or not g.gallery(c.x + dx, c.y + dz):
									good = false
						if good:
							found = c; ok = true; break
					if ok: break
				print("gallery cell ", found, " ok ", ok)
				if not ok:
					get_tree().quit(); return
				pos = Vector3((found.x + 0.5) * 2.4, -0.75, (found.y + 0.5) * 2.4)
				game.player.teleport(pos, views[0][0], views[0][1])
				step = 2; t = 0
		2:
			if t > 8.0 and game.chunks.is_area_ready(game.player.global_position, 2):
				step = 3; t = 0
		3:
			if t > 1.0:
				shot(views[vi][2])
				vi += 1
				if vi >= views.size():
					get_tree().quit(); return
				var p2: Vector3 = pos + (Vector3(0, 0, 6.0) if views[vi][2] == "rays" else Vector3.ZERO)
				game.player.teleport(p2, views[vi][0], views[vi][1])
				t = 0
