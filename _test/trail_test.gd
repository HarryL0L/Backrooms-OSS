extends Node
# Dev harness: walks back along a door's trail and photographs the clues.
var game
var out := OS.get_user_data_dir() + "/trail"
var step := 0
var t := 0.0
var door_pos := Vector3.ZERO
var mall := true
var cells := []
var ci := 0

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
				Settings.apply_preset(2)
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				var od = game.odd_doors
				for want_mall in [true, false]:
					for rx in range(-10, 11):
						for rz in range(-10, 11):
							var d = od.door_in_region(Vector2i(rx, rz))
							if not d.is_empty() and d.mall == want_mall:
								if want_mall: door_pos = d.pos
								else: cells.append(d.pos)
								break
						if (want_mall and door_pos != Vector3.ZERO) or (not want_mall and cells.size() > 0): break
				print("mall door ", door_pos, " field door ", cells)
				game.player.teleport(door_pos + Vector3(1.5, 0.05, 0), PI * 0.5, 0.0)
				step = 2; t = 0
		2:
			if t > 6.0:
				# Find the trail's arrow instances and stand by a few.
				var trails = game.odd_doors._trails.values()
				for tr in trails:
					for mi in tr.get_children():
						var mm: MultiMesh = mi.multimesh
						print("trail mall=", tr.mall, " ", mi.material_override.get_shader_parameter("tiles"), " instances ", mm.instance_count)
				var shots := 0
				for tr in trails:
					if tr.get_child_count() == 0: continue
					var arrows: MultiMesh = tr.get_child(0).multimesh
					for k in [0, arrows.instance_count / 2]:
						var xf: Transform3D = arrows.get_instance_transform(k)
						cells.append(xf)
						print("arrow ", xf)
				step = 3; t = 0
		3:
			if ci >= cells.size():
				get_tree().quit(); return
			var c = cells[ci]
			if c is Transform3D:
				var p: Vector3 = c.origin + c.basis.z.normalized() * 2.2
				var d: Vector3 = c.origin - p
				game.player.teleport(Vector3(p.x, 0.05, p.z), atan2(-d.x, -d.z), -0.15)
			else:
				game.player.teleport(c + Vector3(3.5, 0.05, 0), PI * 0.5, -0.1)
			step = 4; t = 0
		4:
			if t > 5.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				get_viewport().get_texture().get_image().save_png("%s/clue_%d.png" % [out, ci])
				print("shot ", ci)
				ci += 1; step = 3
