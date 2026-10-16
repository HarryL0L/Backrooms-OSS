extends Node
# Dev harness: the Window Dresser's AI in the mall. Stands near it with the
# back turned (stalk/wake), then runs (hunt, loop), then stops (catch).
var game
var out := OS.get_user_data_dir() + "/dresser_ai"
var step := 0
var t := 0.0
var log_t := 0.0
var ai
var shots := 0

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

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
				game._enter_mall()
				step = 2; t = 0
		2:
			if t > 2.0:
				ai = game.mall.ai
				print("ai at ", ai.pos, " nav path test: ", NavigationServer3D.map_get_path(ai.get_world_3d().navigation_map, ai.pos, ai.pos + Vector3(10, 0, 0), true).size())
				# Stand 6 m from it, back turned.
				var p: Vector3 = ai.pos + Vector3(0, 0, -6.0 * signf(ai.pos.z + 0.001))
				game.player.teleport(Vector3(p.x, MallLevel.MALL_Y + 0.05, clampf(p.z, -4.5, 4.5)), 0.0 if ai.pos.z > 0 else PI, 0.0)
				ai.aggression = 0.95
				ai.cooldown = 0.0
				step = 3; t = 0
		3:
			log_t -= delta
			if log_t <= 0.0:
				log_t = 0.5
				print("t=%.1f state=%s dist=%.1f seen=%s aggr=%.2f pos=%s path=%d i=%d goal=%s" % [t, ai.State.keys()[ai.state], ai.pos.distance_to(game.player.global_position), ai.seen, ai.aggression, ai.pos, ai._path.size(), ai._path_i, ai._goal])
			if ai.state == ai.State.HUNT and shots == 0:
				# Turn round to look at it.
				var d: Vector3 = ai.pos - game.player.global_position
				game.player.yaw = atan2(-d.x, -d.z)
				game.player.rotation.y = game.player.yaw
				shots = 1; t = 0; step = 4
			elif t > 40:
				print("no hunt after 40 s"); get_tree().quit()
		4:
			if t > 0.3 and shots == 1:
				shot("hunt_seen"); shots = 2
				# Run away along the concourse.
				Input.action_press("move_forward"); Input.action_press("sprint")
				var p: Vector3 = game.player.global_position
				game.player.yaw = -PI * 0.5 if ai.pos.x < p.x else PI * 0.5
				game.player.rotation.y = game.player.yaw
			log_t -= delta
			if log_t <= 0.0:
				log_t = 0.5
				print("t=%.1f state=%s dist=%.1f px=%.1f loop=%s" % [t, ai.State.keys()[ai.state], ai.pos.distance_to(game.player.global_position), game.player.global_position.x, game.mall.loop_on])
			if t > 6.0:
				Input.action_release("move_forward"); Input.action_release("sprint")
			if game._transition and shots == 2:
				shots = 3; t = 7.0
			if shots == 3 and t > 7.3:
				shot("caught"); shots = 4
			if not game._in_mall and t > 6.0:
				print("left the mall (caught)"); get_tree().quit()
			if t > 30:
				print("timeout"); get_tree().quit()
