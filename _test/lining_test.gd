extends Node
# Dev harness: shows The Lining in the real game and exercises its behaviour.
var game
var out := OS.get_user_data_dir() + "/lining"
var step := 0
var t := 0.0
var wall := {}

func _ready():
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
	var L = game.lining
	match step:
		0:
			if game.state == game.State.MENU:
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING and L._shape_task < 0:
				game.hud.set_fade(0.0)
				# Face away from candidates: pick any wall 3-6 m away that's out of view.
				var c: Array = L._candidates(3.0, 6.0)
				if c.is_empty():
					c = L._candidates(2.2, 16.0)
				print("candidates: ", c.size())
				if c.is_empty():
					get_tree().quit(); return
				wall = c[0]
				L.debug_show(wall.pos, wall.normal)
				# Stand 2.6 m in front of it, looking at it.
				var stand: Vector3 = wall.pos + wall.normal * 2.6 + Vector3(0, 0.02, 0)
				game.player.teleport(stand, atan2(wall.normal.x, wall.normal.z), -0.05)
				step = 2; t = 0
		2:
			if t > 1.5:
				shot("front"); step = 3; t = 0
				game.player.set_flashlight(true)
		3:
			if t > 1.0:
				shot("flashlight"); step = 4; t = 0
				game.player.set_flashlight(false)
				# Behaviour: let it run, looking away from it.
				L._end_episode()
				L._strength = 0.0
				L._timer = 0.0
				game.player.teleport(game.player.global_position, game.player.yaw + PI, 0.0)
		4:
			if t > 6.0:
				print("after 6 s looking away: state=", L._state, " strength=%.2f" % L._strength, " moves_done=", L._moves_done, " wall=", L._wall.get("pos"))
				# Turn to look at it and stare.
				var to: Vector3 = L._wall.pos - game.player.global_position
				game.player.teleport(game.player.global_position, atan2(-to.x, -to.z), 0.0)
				step = 5; t = 0
		5:
			if t > 1.0 and t < 1.2:
				print("seen=", L._is_seen())
			if t > 7.0:
				print("after staring 7 s: strength=%.2f target=%.1f" % [L._strength, L._target])
				get_tree().quit()
