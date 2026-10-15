extends Node
# Dev harness: joins 127.0.0.1, looks at the host and takes screenshots.
var game
var out := OS.get_user_data_dir() + "/net"
var step := 0
var t := 0.0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func shot(n):
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("CLIENT shot ", n)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU and t > 14.0:
				Settings.set_value("net/number", 7)
				game._join_game("127.0.0.1")
				step = 1; t = 0
		1:
			if game.state == game.State.PLAYING:
				print("CLIENT playing, roster ", game.net.roster, " my number ", game.net.my_number())
				step = 2; t = 0
			elif t > 40.0:
				print("CLIENT failed to join"); get_tree().quit()
		2:
			if t > 4.0 and not game._remotes.is_empty():
				var r = game._remotes.values()[0]
				var me: Vector3 = game.player.global_position
				var to: Vector3 = r.global_position - me
				print("CLIENT sees remote #%02d at %s dist %.1f" % [r.number, r.global_position, to.length()])
				# Step back a bit and look at them.
				var back: Vector3 = me - Vector3(to.x, 0, to.z).normalized() * 2.5
				game.player.teleport(back, atan2(-to.x, -to.z), -0.12)
				step = 3; t = 0
			elif t > 15.0:
				print("CLIENT no remote players"); get_tree().quit()
		3:
			if t > 1.5:
				shot("remote_1")
				step = 4; t = 0
		4:
			var r = game._remotes.values()[0]
			var me: Vector3 = game.player.global_position
			var to: Vector3 = r.global_position - me
			game.player.teleport(me, atan2(-to.x, -to.z), -0.1)
			if t > 2.3:
				shot("remote_2")
				step = 5; t = 0
		5:
			var r = game._remotes.values()[0]
			var to: Vector3 = r.global_position - game.player.global_position
			game.player.teleport(game.player.global_position, atan2(-to.x, -to.z) + 0.0, -0.1)
			if t > 1.2:
				shot("remote_3")
				get_tree().quit()
