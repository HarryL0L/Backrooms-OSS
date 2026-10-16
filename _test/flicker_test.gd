extends Node
# Dev harness: stands near a flickering lamp (Medium preset, lightmaps) and
# shoots it fully lit and switched off, by pinning world_time.
var game
var out := OS.get_user_data_dir() + "/flicker"
var step := 0
var t := 0.0
var lamp := []
var times := []
var ti := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000          # after the game sets world_time
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(int(OS.get_environment("PRESET")) if OS.get_environment("PRESET") != "" else 2)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "777"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				var p: Vector3 = game.player.global_position
				lamp = game.gen.nearest_flicker(p, 20)
				print("lamp ", lamp)
				var lp: Vector3 = lamp[0]
				game.player.teleport(Vector3(lp.x + 3.0, 0.05, lp.z + 3.0), PI * 0.25, -0.35)
				# Times when that lamp is on and off.
				var on := -1.0
				var off := -1.0
				var tt := 10.0
				while (on < 0 or off < 0) and tt < 3000.0:
					var f := WorldGen.flicker(lamp[1], tt)
					if f >= 0.99 and on < 0: on = tt
					if f <= 0.01 and off < 0: off = tt
					tt += 0.071
				times = [on, off]
				print("on ", on, " off ", off)
				step = 2; t = 0
		2:
			if t > 6.0:
				# Find a spot that sees the lamp and the floor under it.
				var lp: Vector3 = lamp[0]
				var space = game.player.get_world_3d().direct_space_state
				for o in [Vector3(-5, 0, 0), Vector3(5, 0, 0), Vector3(0, 0, -5), Vector3(0, 0, 5), Vector3(-4, 0, -4), Vector3(4, 0, 4), Vector3(-4, 0, 4), Vector3(4, 0, -4), Vector3(-7, 0, 0), Vector3(7, 0, 0), Vector3(0, 0, 7), Vector3(0, 0, -7)]:
					var eye: Vector3 = Vector3(lp.x, 1.6, lp.z) + o
					var q := PhysicsRayQueryParameters3D.create(eye, Vector3(lp.x, 0.3, lp.z))
					q.exclude = [game.player.get_rid()]
					if space.intersect_ray(q).is_empty():
						var d := Vector3(lp.x, 0, lp.z) - Vector3(eye.x, 0, eye.z)
						game.player.teleport(Vector3(eye.x, 0.05, eye.z), atan2(-d.x, -d.z), -0.3)
						print("view from ", o)
						break
				step = 4; t = 0
		4:
			if t > 2.0:
				step = 3; t = 0
		3:
			RenderingServer.global_shader_parameter_set("world_time", times[ti])
			if t > 0.5:
				get_viewport().get_texture().get_image().save_png("%s/%s%s.png" % [out, OS.get_environment("PRESET"), ["on", "off"][ti]])
				print("shot ", ti)
				ti += 1; t = 0
				if ti >= 2:
					get_tree().quit()
