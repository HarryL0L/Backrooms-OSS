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
				# teleport into the tiled baths to test water + climbing
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
				# Find a mysterious door and stand in front of it.
				var od = game.odd_doors
				var rc := Vector2i(floori(float(game.gen.spawn_cell.x) / od.REGION), floori(float(game.gen.spawn_cell.y) / od.REGION))
				var dp := Vector3.INF
				for rr in range(0, 12):
					for dz in range(-rr, rr + 1):
						for dx in range(-rr, rr + 1):
							if dp == Vector3.INF:
								var dr: Dictionary = od.door_in_region(rc + Vector2i(dx, dz))
								if not dr.is_empty():
									dp = dr.pos
				print("odd door at ", dp)
				game.player.teleport(dp + Vector3(2.2, 0.05, 0.0), PI * 0.5, 0.0)
				step = 12; t = 0
		12:
			if t > 3.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				shot("odd_door"); step = 13; t = 0
				Input.action_press("move_forward")
		13:
			if game._in_field or t > 8.0:
				Input.action_release("move_forward")
				print("in field: ", game._in_field)
				step = 14; t = 0
		14:
			if t > 4.0:
				shot("field_arrival"); step = 15; t = 0
				var pl = game.player
				pl.teleport(pl.global_position, pl.yaw + PI * 0.75, 0.05)
		15:
			if t > 1.0:
				shot("field_side"); step = 16; t = 0
				# Stand near the exit door, looking at it.
				var ep: Vector3 = game.field.exit_pos
				var to := Vector3(-ep.x, 0, -ep.z).normalized()
				var stand := FieldLevel.ground_at(ep.x + to.x * 6.0, ep.z + to.z * 6.0) + Vector3(0, 0.1, 0)
				game.player.teleport(stand, atan2(to.x, to.z), 0.0)
				print("exit door at ", ep, " dist from arrival ", Vector2(ep.x, ep.z).length())
		16:
			if t > 2.0:
				shot("field_exit_door"); step = 17; t = 0
				Input.action_press("move_forward")
		17:
			if not game._in_field or t > 10.0:
				Input.action_release("move_forward")
				print("left field: ", not game._in_field)
				step = 18; t = 0
		18:
			if t > 6.0:
				shot("back_in_backrooms")
				print("state=", game.state, " pos=", game.player.global_position)
				get_tree().quit()
