extends Node
# Dev harness: opens the multiplayer menu and checks the LAN host list.
var game
var t := 0.0
var step := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _process(delta):
	t += delta
	if step == 0 and game.state == game.State.MENU and t > 3.0:
		game.open_multiplayer()
		step = 1; t = 0
	elif step == 1 and t > 6.0:
		print("BROWSE hosts: ", game.net.hosts)
		DirAccess.make_dir_recursive_absolute(OS.get_user_data_dir() + "/net")
		get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/net/menu.png")
		get_tree().quit()
