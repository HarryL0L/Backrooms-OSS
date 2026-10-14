extends Node
# Dev harness: drives the real game and saves screenshots.
var game
var out := OS.get_user_data_dir() + "/play"
var step := 0
var t := 0.0
var _frames := 0
var _pool_pos := Vector3.ZERO

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(name):
	var img := get_viewport().get_texture().get_image()
	img.save_png("%s/%s.png" % [out, name])
	print("shot ", name, " state=", game.state, " pos=", game.player.global_position, " fps=", Engine.get_frames_per_second(), " chunks=", game.chunks.loaded_count())

func _process(d):
	t += d
	match step:
		0:
			if game.state == game.State.MENU and t > 3.0:
				shot("menu"); step = 1; t = 0
				game.new_game()
		1:
			if game.state == game.State.PLAYING and t > 3.5:
				shot("start"); step = 2; t = 0
				Input.action_press("move_forward")
		2:
			if t > 4.0:
				Input.action_release("move_forward")
				shot("walked"); step = 3; t = 0
				game.player.add_look(1.2, 0.0)
				game._using_touch = true
				game._update_touch_visibility()
		3:
			if t > 0.5:
				shot("touch"); step = 4; t = 0
				game.player.set_flashlight(true)
				game.player.add_look(0.0, -0.3)
		4:
			if t > 0.5:
				shot("flashlight"); step = 5; t = 0
				game.pause()
		5:
			if t > 0.5:
				shot("pause"); step = 6; t = 0
				game.open_settings()
		6:
			if t > 0.5:
				shot("settings"); step = 7; t = 0
				game.settings_menu._tabs.current_tab = 3
		7:
			if t > 0.5:
				shot("bindings"); step = 8; t = 0
				game.settings_menu.close()
				game.resume()
				# teleport into the poolrooms to test water + climbing
				var g = game.gen
				for r in range(5, 300):
					var found = false
					for k in 16:
						var a = k * PI / 8
						var c = g.spawn_cell + Vector2i(int(cos(a)*r), int(sin(a)*r))
						if g.biome_at(c.x, c.y) == 1 and g.pool_noise(c.x, c.y) and g.biome_at(c.x+1,c.y)==1 and g.biome_at(c.x-1,c.y)==1 and g.biome_at(c.x,c.y+1)==1 and g.biome_at(c.x,c.y-1)==1:
							game.player.teleport(Vector3((c.x+0.5)*2.4, 0.5, (c.y+0.5)*2.4), 0.0)
							_pool_pos = Vector3((c.x+0.5)*2.4, WorldGen.POOL_FLOOR + 0.02, (c.y+0.5)*2.4)
							found = true
							break
					if found: break
				game.player.set_flashlight(false)
		8:
			if t > 4.0:
				shot("pool"); step = 9; t = 0
				Input.action_press("move_forward")
		9:
			if t > 5.0:
				Input.action_release("move_forward")
				shot("pool_walk"); step = 10; t = 0
				# Look down at the wake and drop a splash ahead.
				var pl = game.player
				pl.teleport(_pool_pos, pl.yaw, -0.85)
				game.ripples.splash(_pool_pos - pl.global_basis.z * 1.0, 2.0)
		10:
			_frames += 1
			if _frames > 40:
				shot("pool_ripples"); step = 11
				var rimg: Image = game.ripples._vp[game.ripples._cur].get_texture().get_image()
				var mn := 1e9
				var mx := -1e9
				for y in range(0, rimg.get_height(), 4):
					for x in range(0, rimg.get_width(), 4):
						var v := rimg.get_pixel(x, y).r
						mn = minf(mn, v)
						mx = maxf(mx, v)
				print("ripple tex format=", rimg.get_format(), " min=", mn, " max=", mx, " origin=", game.ripples._origin, " active=", game.ripples.active)
				get_tree().quit()
