extends Node
# Walkthrough recorder: plays the game with held input from the Lobby into a
# stairwell, down to the car park on B1, over to an uncovered SUV, opens the
# driver's door, gets in, turns the key and the dome light on, looks round
# and gets out. Saves every frame as JPEG into user://walk/. Run with
#   godot --path . --fixed-fps 30 --resolution 1280x720 res://_test/walkthrough.tscn
# then: ffmpeg -framerate 30 -i walk/%05d.jpg -c:v libx264 -pix_fmt yuv420p walk.mp4

var game
var out := OS.get_user_data_dir() + "/walk"
var step := 0
var t := 0.0
var o := Vector3.ZERO
var frame := 0
var rec := false
var yaw_to := 0.0
var pitch_to := 0.0
var turn_rate := 5.0
var path: Array = []
var car: ParkedCar = null
var car_e: Array = []
var _last_pos := Vector3.ZERO
var _stuck := 0.0
var acts: Array = []        # the car sequence: [seconds, Callable]


func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 1000
	DirAccess.make_dir_recursive_absolute(out)
	for f in DirAccess.get_files_at(out):
		DirAccess.remove_absolute(out + "/" + f)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	RenderingServer.frame_post_draw.connect(_grab)


func _grab():
	if rec:
		get_viewport().get_texture().get_image().save_jpg("%s/%05d.jpg" % [out, frame], 0.92)
		frame += 1


func _aim(p: Vector3) -> void:
	var d: Vector3 = p - game.player.camera.global_position
	yaw_to = atan2(-d.x, -d.z)
	pitch_to = atan2(d.y, Vector2(d.x, d.z).length())


func _face(dir: Vector3) -> void:
	yaw_to = atan2(-dir.x, -dir.z)


func _steer(delta: float) -> void:
	var p: Player = game.player
	if p._ride_t >= 0.0:
		return
	var k := 1.0 - exp(-turn_rate * delta)
	p.yaw = lerp_angle(p.yaw, yaw_to, k)
	p.pitch = lerpf(p.pitch, pitch_to, k)
	p._apply_rotation()


var _dbg := 0.0


func _process(delta):
	t += delta
	_dbg += delta
	if _dbg > 2.0:
		_dbg = 0.0
		print("walk dbg step %d state %d t %.1f frames %d warm %d/%d area %s amb %s paused %s proc %s" % [step, game.state, t, frame, game._warm_next, game._warm_list.size(), game.chunks.is_area_ready(game.player.global_position, 1), game.ambience.is_ready(), get_tree().paused, game.can_process()])
	_steer(delta)
	var l: Vector3 = game.player.global_position - o
	match step:
		0:
			if game.state == game.State.MENU:
				Settings.apply_preset(int(OS.get_environment("PRESET")) if OS.get_environment("PRESET") != "" else 4)
				Settings.set_value("graphics/auto_quality", false)
				Settings.set_value("graphics/render_scale", 1.0)
				(game.main_menu.find_child("SeedEdit", true, false) as LineEdit).text = "1234"
				game.new_game(); step = 1
		1:
			if game.state == game.State.PLAYING:
				var b: Vector2i = game.gen.stair_block(1, 1)
				o = Vector3(b.x * 2.4, 0.0, b.y * 2.4)
				game.hud.set_fade(0.0)
				# By the stairwell door, looking back into the Lobby.
				game.player.teleport(o + Vector3(-1.3, 0.05, 1.2), PI * 0.5)
				_face(Vector3.LEFT)
				turn_rate = 1.6
				step = 2; t = 0
		2:
			if t > 5.0 and not rec and game.chunks.is_area_ready(game.player.global_position, 1):
				rec = true
				t = 0
			if rec and t > 1.5:
				_face(Vector3.RIGHT)                    # turn round to the grey door
			if rec and t > 3.6:
				turn_rate = 5.0
				Input.action_press("move_forward")      # through it, down flight A
				step = 3; t = 0
		3:
			if l.x > 6.3 or t > 18.0:
				_face(Vector3.BACK)                     # across the half landing
				step = 4; t = 0
		4:
			if l.z > 3.5 or t > 6.0:
				_face(Vector3.LEFT)                     # down flight B to B1
				step = 5; t = 0
		5:
			if l.x < 1.2 or t > 15.0:
				_face(Vector3.FORWARD)
				step = 6; t = 0
		6:
			if l.z < 1.3 or t > 5.0:
				_face(Vector3.LEFT)                     # out of the door into the car park
				step = 7; t = 0
		7:
			if t > 1.6:
				_plan_route()
				step = 8; t = 0
		8:
			_walk(delta)
		9:
			# At the car: run the sequence.
			if acts.is_empty():
				rec = false
				print("walkthrough: ", frame, " frames")
				get_tree().quit()
				return
			if t >= acts[0][0]:
				var a: Callable = acts.pop_front()[1]
				t = 0
				a.call()


## Finds the nearest clean SUV on B1 and the way to its driver's door:
## out to the lane, along it, into the empty bay beside the car.
func _plan_route() -> void:
	var g: WorldGen = game.gen
	var here: Vector3 = game.player.global_position
	var c := g.cell_of(here)
	var rc := Vector2i(floori(c.x / 16.0), floori(c.y / 16.0))
	var best := INF
	var all := []
	for dz in range(-3, 4):
		for dx in range(-3, 4):
			var res := {}
			LobbyDetails._compute(g, rc + Vector2i(dx, dz), res)
			for e in res.props:
				if e[1] == LobbyDetails.CAR or e[1] == LobbyDetails.SUV:
					all.append(e)
	# The nearest clean SUV we can walk straight to (out into the car park,
	# then alongside it), with the bay beside its driver's door empty.
	var space: PhysicsDirectSpaceState3D = game.player.get_world_3d().direct_space_state
	var start := here + Vector3(-2.0, 0, 0)
	var cands := all.filter(func(e: Array) -> bool: return e[1] == LobbyDetails.SUV and not e[7] and (e[0] as Vector3).distance_to(here) < 30.0)
	cands.sort_custom(func(a: Array, b: Array) -> bool: return (a[0] as Vector3).distance_to(here) < (b[0] as Vector3).distance_to(here))
	for e in cands:
		var xf := _car_xf(e)
		var blocked := false
		for e2 in all:
			if e2 != e and (e2[0] as Vector3).distance_to(xf * Vector3(0, 0, 2.4)) < 1.5:
				blocked = true
		var a := xf * Vector3(0.5, 0, 3.6)
		var b := xf * Vector3(0.5, 0, 1.6)
		if blocked or not _clear(space, here, start) or not _clear(space, start, a) or not _clear(space, a, b):
			continue
		car_e = e
		path = [start, a, b]
		break
	if car_e.is_empty():
		print("walkthrough: no car with a clear way")
		get_tree().quit()
		return
	print("walkthrough: car ", car_e, " at ", (car_e[0] as Vector3).distance_to(here), " m")


func _clear(space: PhysicsDirectSpaceState3D, a: Vector3, b: Vector3) -> bool:
	for y in [0.5, 1.3]:
		for side in [-0.32, 0.0, 0.32]:
			var d := (b - a)
			d.y = 0.0
			var off := Vector3(-d.z, 0, d.x).normalized() * side
			var q := PhysicsRayQueryParameters3D.create(Vector3(a.x, y, a.z) + off, Vector3(b.x, y, b.z) + off)
			q.exclude = [game.player.get_rid()]
			if not space.intersect_ray(q).is_empty():
				return false
	return true


func _car_xf(e: Array) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, e[3]) * Basis(Vector3.UP, PI * 0.5), e[0])


func _walk(delta: float) -> void:
	var p: Player = game.player
	var pos := p.global_position
	var target: Vector3 = path[0]
	var d := Vector3(target.x - pos.x, 0, target.z - pos.z)
	if d.length() < (0.25 if path.size() == 1 else 0.6):
		path.pop_front()
		if path.is_empty():
			Input.action_release("move_forward")
			_at_car()
			return
		return
	_face(d)
	# Stuck on something: hop to the waypoint.
	_stuck = _stuck + delta if pos.distance_to(_last_pos) < 0.5 * delta else 0.0
	_last_pos = pos
	if _stuck > 1.5:
		print("walkthrough: stuck at ", pos, ", skipping to ", target)
		p.teleport(Vector3(target.x, pos.y, target.z), p.yaw, p.pitch)
		_stuck = 0.0


func _at_car() -> void:
	for n in get_tree().get_nodes_in_group("usable"):
		if car == null or n.global_position.distance_to(car_e[0]) < car.global_position.distance_to(car_e[0]):
			car = n
	var p: Player = game.player
	turn_rate = 3.0
	acts = [
		[0.3, func(): _aim(_target("DoorFL"))],
		[1.4, func(): game._use()],
		[1.6, func(): _aim(_target("getin"))],
		[1.1, func(): game._use()],
		[2.4, func(): turn_rate = 2.5; _aim(_target("key"))],
		[1.3, func(): game._use()],
		[1.0, func(): _aim(car.global_transform * Vector3(-6.0, 1.0, 0.0))],
		[2.4, func(): _aim(_target("cabin"))],
		[1.3, func(): game._use()],
		[1.4, func(): _aim(car.global_transform * Vector3(-0.4, 1.0, -1.3))],  # across to the passenger side
		[2.0, func(): _aim(car.global_transform * Vector3(-5.0, 0.4, 0.0))],   # the headlights on the floor ahead
		[2.2, func(): _aim(_target("getout"))],
		[1.3, func(): game._use()],
		[2.6, func(): _aim(car.global_transform * Vector3(-1.0, 1.0, 0.4))],   # look back at it
		[2.5, func(): pass],
	]
	step = 9; t = 0


func _target(id: String) -> Vector3:
	for tg in car.use_targets(game.player):
		if tg[0] == id:
			return tg[1]
	print("walkthrough: no target ", id)
	return game.player.camera.global_position - game.player.camera.global_basis.z
