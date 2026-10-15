extends Node
# Dev harness: hosts a LAN game (seed 4242) and walks about with the flashlight on.
var game
var step := 0
var t := 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "4242"
				game._host_game(false)
				step = 1
		1:
			if game.state == game.State.PLAYING:
				print("HOST playing, roster ", game.net.roster)
				game.player.set_flashlight(true)
				step = 2; t = 0
		2:
			# Walk back and forth slowly so the client sees the gait.
			var phase := int(t / 3.0) % 2
			if phase == 0:
				Input.action_press("move_forward"); Input.action_release("move_back")
			else:
				Input.action_press("move_back"); Input.action_release("move_forward")
			if t > 140.0:
				print("HOST roster at end ", game.net.roster)
				get_tree().quit()
