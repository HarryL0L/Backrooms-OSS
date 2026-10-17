extends Node
# Dev harness: PS1 style screenshots (Yellow Halls, Tiled Baths, sun gallery) plus a normal-mode Yellow Halls for comparison.
var game
var out := OS.get_user_data_dir() + "/ps1"
var step := 0
var t := 0.0
var spots := []   # [pos, yaw, pitch, name]
var si := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(name):
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name)

func find_cell(g, test: Callable) -> Vector2i:
	for r in range(4, 400, 2):
		for k in 32:
			var a := k * TAU / 32.0
			var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
			if test.call(c):
				return c
	return Vector2i(1 << 20, 0)

func _process(delta):
	t += delta
	var g = game.gen
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/ps1", true)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				var sp: Vector3 = g.spawn_position()
				spots.append([sp, 0.6, 0.0, "lobby"])
				var pc := find_cell(g, func(c): return g.biome_at(c.x, c.y) == 1 and not g.gallery(c.x, c.y) and g.biome_at(c.x + 3, c.y) == 1 and g.biome_at(c.x - 3, c.y) == 1 and g.biome_at(c.x, c.y + 3) == 1 and g.biome_at(c.x, c.y - 3) == 1)
				spots.append([Vector3((pc.x + 0.5) * 2.4, 0.3, (pc.y + 0.5) * 2.4), 0.3, -0.05, "pool"])
				var gc := find_cell(g, func(c):
					var cc := Vector2i(c.x, c.y - posmod(c.y, 5) + 1)
					for dx in range(-6, 7):
						for dz in range(-1, 5):
							if g.biome_at(cc.x + dx, cc.y + dz) != 1 or not g.gallery(cc.x + dx, cc.y + dz):
								return false
					return true)
				gc.y = gc.y - posmod(gc.y, 5) + 1
				spots.append([Vector3((gc.x + 0.5) * 2.4, -0.75, (gc.y + 0.5) * 2.4), -PI * 0.5, 0.05, "gallery"])
				spots.append([sp, 0.6, 0.0, "lobby_normal"])
				game.player.teleport(spots[0][0], spots[0][1], spots[0][2])
				step = 2; t = 0
		2:
			if t > 7.0 and game.chunks.is_area_ready(game.player.global_position, 2):
				step = 3; t = 0
		3:
			if t > 1.0:
				shot(spots[si][3])
				si += 1
				if si >= spots.size():
					get_tree().quit(); return
				if spots[si][3] == "lobby_normal":
					Settings.set_value("graphics/ps1", false)
				game.player.teleport(spots[si][0], spots[si][1], spots[si][2])
				step = 2; t = 0
