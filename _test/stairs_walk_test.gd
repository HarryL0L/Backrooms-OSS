extends Node
# Dev harness: walks a stairwell for real (held input): down flight A to the
# half landing, round onto flight B and down until the floor changes, then on
# down to B1's landing and out of the door into B1. Logs height and floor.
var game
var step := 0
var t := 0.0
var o := Vector3.ZERO
var log_t := 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _face(dir: Vector3):
	game.player.yaw = atan2(-dir.x, -dir.z)
	game.player._apply_rotation()

func _process(delta):
	t += delta
	log_t += delta
	if step >= 2 and log_t > 0.5:
		log_t = 0.0
		var l: Vector3 = game.player.global_position - o
		print("step %d  local (%.2f, %.2f, %.2f)  floor %d  stairwell %s" % [step, l.x, l.y, l.z, game._floor, game.player.in_stairwell])
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(1)
				Settings.set_value("graphics/auto_quality", false)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var b: Vector2i = game.gen.stair_block(1, 1)
				o = Vector3(b.x * 2.4, 0.0, b.y * 2.4)
				game.hud.set_fade(0.0)
				game.player.teleport(o + Vector3(-1.2, 0.05, 1.2), 0.0)
				_face(Vector3.RIGHT)
				step = 2; t = 0
		2:
			if t > 4.0:
				Input.action_press("move_forward")      # through the door, east down flight A
				step = 3; t = 0
		3:
			var l: Vector3 = game.player.global_position - o
			if l.x > 6.3 or t > 15.0:
				# On the half landing: walk across to the other lane, then west down flight B.
				_face(Vector3.BACK)
				step = 4; t = 0
		4:
			var l: Vector3 = game.player.global_position - o
			if l.z > 3.5 or t > 6.0:
				_face(Vector3.LEFT)
				step = 5; t = 0
		5:
			var l: Vector3 = game.player.global_position - o
			if l.x < 1.2 or t > 15.0:
				# B1's landing: turn to the door and walk out.
				_face(Vector3.FORWARD)
				step = 6; t = 0
		6:
			var l: Vector3 = game.player.global_position - o
			if l.z < 1.3 or t > 5.0:
				_face(Vector3.LEFT)
				step = 7; t = 0
		7:
			if t > 6.0:
				Input.action_release("move_forward")
				var l: Vector3 = game.player.global_position - o
				print("END local (%.2f, %.2f, %.2f) floor %d gen floor %d" % [l.x, l.y, l.z, game._floor, game.gen.floor_index])
				get_tree().quit()
