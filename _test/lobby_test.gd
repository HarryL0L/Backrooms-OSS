extends Node
# Dev harness: Yellow Halls details. Photographs a wall with an empty mount and
# outlets, a sodden patch of carpet; then steps on it (the floor gives way:
# you fall through the dark into the Lobby somewhere else).
var game
var out := OS.get_user_data_dir() + "/lobby"
var step := 0
var t := 0.0
var sodden := Vector3.INF

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(n):
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)

func cam_at(p: Vector3, look: Vector3):
	var d := look - (p + Vector3(0, 1.62, 0))
	game.player.teleport(p, atan2(-d.x, -d.z), atan2(d.y, Vector2(d.x, d.z).length()))

func _process(delta):
	t += delta
	var g = game.gen
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(2)
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING and t > 4.0:
				game.hud.set_fade(0.0)
				var best = null
				var counts := {}
				for r in game.details._regions:
					var root = game.details._regions[r]
					if root == null: continue
					for ch in root.get_children():
						if ch is MultiMeshInstance3D:
							var mm: MultiMesh = ch.multimesh
							for i in mm.instance_count:
								var tile = int(mm.get_instance_custom_data(i).r)
								counts[tile] = counts.get(tile, 0) + 1
								if tile == LobbyDetails.MOUNT and best == null:
									best = mm.get_instance_transform(i)
						elif ch is Area3D and sodden == Vector3.INF:
							sodden = ch.global_position
				print("detail counts ", counts, " sodden ", sodden)
				if best:
					var n = best.basis.z.normalized()
					var p = best.origin + n * 1.6
					cam_at(Vector3(p.x, 0.05, p.z), best.origin + Vector3(0, -0.5, 0))
				step = 2; t = 0
		2:
			if t > 5.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				shot("wall_details"); step = 3; t = 0
				if sodden != Vector3.INF:
					cam_at(sodden + Vector3(1.8, -0.25, 0), sodden)
		3:
			if t > 5.0 and game.chunks.is_area_ready(game.player.global_position, 1):
				shot("sodden"); step = 4; t = 0
				if sodden != Vector3.INF:
					game.player.teleport(sodden + Vector3(0, -0.25, 0), 0.0, 0.0)
				else:
					game._on_floor_gave_way()
		4:
			if game._transition and step == 4:
				print("the floor gave way")
				step = 5; t = 0
			elif t > 5.0:
				print("floor never gave way"); get_tree().quit()
		5:
			if t > 2.0 and not game._transition and game.state == game.State.PLAYING:
				var c = g.cell_of(game.player.global_position)
				print("after the fall: ", WorldGen.BIOME_NAMES[g.biome_at(c.x, c.y)], " at ", game.player.global_position)
				get_tree().quit()
			elif t > 60.0:
				print("timeout falling"); get_tree().quit()
