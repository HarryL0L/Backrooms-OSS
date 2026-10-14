extends Node
# Dev harness: shows the hall figure in the Unlit Halls and checks it vanishes.
var game
var out := OS.get_user_data_dir() + "/figure"
var step := 0
var t := 0.0
var cells := []
var ci := 0
var red := StandardMaterial3D.new()

func _ready():
	red.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	red.albedo_color = Color.RED
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
	var F = game.hall_figure
	var g = game.gen
	match step:
		0:
			if game.state == game.State.MENU:
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				# Find a dark-halls cell and teleport there.
				for r in range(4, 300, 3):
					for k in 24:
						var a := k * TAU / 24.0
						var c: Vector2i = g.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
						if g.biome_at(c.x, c.y) == 3 and not g.is_solid(c.x, c.y, 3) and g.biome_at(c.x + 4, c.y) == 3 and g.biome_at(c.x - 4, c.y) == 3 and g.biome_at(c.x, c.y + 4) == 3 and g.biome_at(c.x, c.y - 4) == 3:
							cells.append(c)
					if cells.size() > 12: break
				print("dark cells ", cells.size())
				game.player.teleport(Vector3((cells[0].x + 0.5) * 2.4, 0.05, (cells[0].y + 0.5) * 2.4), 0.0, 0.0)
				step = 2; t = 0
		2:
			if t > 6.0 and game.chunks.is_area_ready(game.player.global_position, 2):
				# Let it spawn behind us, then turn round to look.
				F._timer = 0.0
				game.player.teleport(game.player.global_position, game.player.yaw, 0.0)
				step = 3; t = 0
		3:
			if F._present:
				print("figure at ", F.global_position, " dist ", F.global_position.distance_to(game.player.global_position))
				var to: Vector3 = F.global_position - game.player.global_position
				game.player.teleport(game.player.global_position, atan2(-to.x, -to.z), 0.08)
				step = 4; t = 0
			elif t > 5.0:
				ci += 1
				if ci >= cells.size():
					print("figure never spawned"); get_tree().quit()
				else:
					game.player.teleport(Vector3((cells[ci].x + 0.5) * 2.4, 0.05, (cells[ci].y + 0.5) * 2.4), randf() * TAU, 0.0)
					step = 2; t = 0
		4:
			if t > 0.5:
				print("present while looked at: ", F._present, " in_view ", F._in_view())
				var cam = game.player.camera
				print("screen ", cam.unproject_position(F.global_position + Vector3.UP * 1.3), " behind ", cam.is_position_behind(F.global_position), " vis ", F.visible, " ", F.is_visible_in_tree())
				shot("figure")
				for mi in F.find_children("*", "MeshInstance3D", true, false):
					mi.set_meta("m", mi.material_override); mi.material_override = red
				step = 41; t = 0
		41:
			if t > 0.3:
				shot("figure_red")
				for mi in F.find_children("*", "MeshInstance3D", true, false):
					mi.material_override = mi.get_meta("m")
				game.player.set_flashlight(true)
				step = 5; t = 0
		5:
			if t > 0.6:
				print("present after flashlight: ", F._present)
				shot("after_flashlight")
				get_tree().quit()
