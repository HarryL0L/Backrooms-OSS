extends Node
# Dev harness: walks and sprints, reports step rate and head motion ranges.
var game
var step := 0
var t := 0.0
var steps := 0
var ys := []
var xs := []

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _physics_process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING and t > 3.0:
				game._enter_field()      # open ground to walk on
				game.player.footstep.connect(func(_s, _st): steps += 1)
				Input.action_press("move_forward")
				step = 2; t = 0
		2, 3:
			if t > 2.0:
				ys.append(game.player.head.position.y); xs.append(game.player.head.position.x)
			if t > 7.0:
				var hs := Vector2(game.player.velocity.x, game.player.velocity.z).length()
				print("%s: speed %.2f m/s, %.2f steps/s, head y range %.1f cm, x range %.1f cm" % [
					"walk" if step == 2 else "sprint", hs, steps / 7.0, (ys.max() - ys.min()) * 100, (xs.max() - xs.min()) * 100])
				steps = 0; ys.clear(); xs.clear(); t = 0
				if step == 2:
					Input.action_press("sprint"); step = 3
				else:
					get_tree().quit()
