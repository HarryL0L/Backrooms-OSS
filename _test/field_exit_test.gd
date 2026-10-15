extends Node
# Dev harness: Field arrival view (can you see where to go?) and the exit tree up close.
var game
var out := OS.get_user_data_dir() + "/field_exit"
var step := 0
var t := 0.0
var n := 0

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
	match step:
		0:
			if game.state == game.State.MENU:
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING and t > 3.0:
				game.hud.set_fade(0.0)
				game._enter_field()
				step = 2; t = 0
		2:
			if t > 3.0:
				var e: Vector3 = game.field.exit_pos
				print("exit ", e, " dist ", Vector2(e.x, e.z).length())
				shot("arrival_%d" % n)
				# Walk most of the way there and look at it.
				var to := Vector3(e.x, 0, e.z).normalized()
				var p: Vector3 = FieldLevel.ground_at(e.x - to.x * 22.0, e.z - to.z * 22.0) + Vector3(0, 0.1, 0)
				game.player.teleport(p, atan2(-to.x, -to.z), 0.12)
				step = 3; t = 0
		3:
			if t > 2.0:
				shot("near_%d" % n)
				n += 1
				if n >= 2:
					get_tree().quit(); return
				game._leave_field()
				game._enter_field()
				step = 2; t = 0
