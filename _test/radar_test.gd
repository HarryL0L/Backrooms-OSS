extends Node
# Dev harness: a fake second player (crouching, then jumping) in front of
# you, with the hand-held radar up. Screenshots of each.
var game
var out := OS.get_user_data_dir() + "/radar"
var step := 0
var t := 0.0
var base: Vector3
var shots := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func fake(pos: Vector3, crouch: bool, ground: bool, vy: float, num: int, id: int):
	game._on_peer_state(id, {"p": pos, "y": 0.0, "x": 0.0, "v": Vector3(0, vy, 0), "f": false, "c": crouch, "g": ground, "fl": false})
	game._remotes[id].number = num

func shot(n):
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, n])
	print("shot ", n)

func _process(delta):
	t += delta
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.set_value("graphics/auto_quality", false)
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				game.hud.set_fade(0.0)
				game.net.active = true
				base = game.player.global_position
				step = 2; t = 0
		2:
			var fwd: Vector3 = -game.player.global_basis.z
			var right: Vector3 = game.player.global_basis.x
			var p: Vector3 = base + fwd * 3.0
			var jumping := t > 4.0
			var h := 0.0
			if jumping:
				var jt := fmod(t - 4.0, 0.9)
				h = 4.2 * jt - 6.0 * jt * jt
			var vy := 4.2 - 12.0 * fmod(t - 4.0, 0.9) if jumping else 0.0
			fake(p + Vector3.UP * maxf(h, 0.0), not jumping, not jumping or h <= 0.0, vy, 42, 5)
			fake(base + fwd * 14.0 - right * 9.0, false, true, 0.0, 7, 6)
			fake(base - fwd * 60.0 + right * 10.0, false, true, 0.0, 3, 7)
			if t > 3.0 and shots == 0:
				shot("crouch"); shots = 1
			if t > 4.32 and shots == 1:
				shot("jump"); shots = 2
			if t > 5.0:
				get_tree().quit()
