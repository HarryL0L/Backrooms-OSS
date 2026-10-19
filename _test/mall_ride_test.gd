extends Node
# Dev harness: the Dead Mall's escalator and lift, ridden. Stands on the
# Fountain Court's up escalator (ground to level 1) without walking, then
# calls the lift to level 1, steps in, asks for level 2 and gets out.
# Photos in user://mall/ride_*.png.
var game
var out := OS.get_user_data_dir() + "/mall"
var step := 0
var t := 0.0
var log_t := 0.0
var lift: MallLift
var esc: MallEscalator

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/ride_%s.png" % [out, name])
	print("shot ", name)

func _p() -> Vector3:
	return game.player.global_position - Vector3(0, MallLevel.MALL_Y, 0)

func _process(delta):
	t += delta
	log_t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				game._enter_mall()
				step = 2; t = 0
		2:
			if t > 3.0:
				for n in game.mall.get_children():
					if n is MallLift:
						lift = n
					if n is MallEscalator and (esc == null or n.global_position.y < esc.global_position.y):
						esc = n
				print("escalator at ", esc.global_position, " dir ", esc.global_basis.x, "; lift at ", lift.global_position, " door ", lift.global_basis.x)
				# On the bottom landing of the up escalator, facing up it.
				var p: Vector3 = esc.global_transform * Vector3(-0.7, 0.05, 0)
				var d: Vector3 = esc.global_basis.x
				game.player.teleport(p, atan2(-d.x, -d.z), 0.1)
				step = 3; t = 0
		3:
			if log_t > 2.0:
				log_t = 0.0
				print("  escalator ride t %.0f at %s" % [t, _p()])
			if t > 1.5 and t < 1.6:
				_shot("escalator_foot")
			if t > 9.0 and t < 9.1:
				_shot("escalator_mid")
			if t > 26.0:
				print("after the escalator: height %.2f (level 1 is 5)" % _p().y)
				_shot("escalator_top")
				# To the lift on level 1, facing its doors.
				var front: Vector3 = lift.global_transform * Vector3(2.0, 5.05, 0)
				var d: Vector3 = -lift.global_basis.x
				game.player.teleport(front, atan2(-d.x, -d.z), 0.0)
				step = 4; t = 0
		4:
			if t > 1.0:
				print("lift: ", lift.use("call1", game.player))
				step = 5; t = 0
		5:
			if log_t > 1.0:
				log_t = 0.0
				print("  lift t %.0f car %.2f state %d at %d" % [t, lift._car_y, lift._state, lift._at])
			if (lift._at == 1 and lift._state == MallLift.OPEN) or t > 20.0:
				print("lift arrived on level 1 after %.1f s" % t)
				_shot("lift_open")
				game.player.teleport(lift.global_transform * Vector3(0, 5.05, 0), game.player.yaw, 0.0)
				step = 6; t = 0
		6:
			if t > 1.0:
				print("targets inside: ", lift.use_targets(game.player).map(func(e): return e[2]))
				lift.use("go2", game.player)
				step = 7; t = 0
		7:
			if log_t > 1.0:
				log_t = 0.0
				print("  ride t %.0f car %.2f player %.2f" % [t, lift._car_y, _p().y])
			if t > 2.5 and t < 2.6:
				_shot("lift_riding")
			if (lift._at == 2 and lift._state == MallLift.OPEN) or t > 20.0:
				print("on level 2: player height %.2f (level 2 is 10)" % _p().y)
				var d: Vector3 = lift.global_basis.x
				game.player.teleport(game.player.global_position, atan2(-d.x, -d.z), -0.05)
				step = 8; t = 0
		8:
			if t > 1.0:
				_shot("lift_level2")
				# Walk out onto the gallery.
				Input.action_press("move_forward")
				step = 9; t = 0
		9:
			if t > 2.0:
				Input.action_release("move_forward")
				print("walked out to ", _p())
				_shot("gallery_level2")
				get_tree().quit()
