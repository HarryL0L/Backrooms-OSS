class_name DresserAI
extends Node3D
## The Window Dresser's mind. It stands in a shop window like the other
## mannequins until it decides you're worth it, then:
##
## - It senses: sight (a view cone with line of sight), hearing (running
##   carries ~20 m, walking ~9 m, crouching ~3 m) and memory (where it last
##   saw or heard you, and how long ago).
## - It builds aggression from time in the mall, you being near, you running,
##   and you shining a torch on it. Past a threshold it leaves the stand.
## - Stalking: it only moves when you can't see it, choosing places out of
##   your sight that bring it closer, and freezes in a new pose the moment you
##   look. Reaching you unseen, or being stared at with a torch up close,
##   wakes it: the face cracks open and the hunt begins.
## - Hunting (60 s, the mall loops): it runs a little slower than you
##   sprint but faster than you walk, aims where you're going rather than
##   where you are, takes the loop round to cut you off when you lose it, a
##   torch on its face slows it, and if you hide it searches where it last
##   had you, checks the shops nearby and waits at a shop door it heard you
##   go through.
## - It moves in stop-motion: the logical position is smooth, the body only
##   jumps to it a few times a second.

signal caught
signal hunt_started
signal hunt_ended

enum State { DORMANT, STALK, HUNT, SEARCH, RETURN }

const STALK_SPEED := 6.0       # while nobody is looking
const RUN := 4.3               # player sprint 4.9, walk 2.6
const RUN_LIT := 2.4           # torch in its face
const HUNT_TIME := 60.0
const CATCH_DIST := 1.4           # long arms
const FRAME := 1.0 / 9.0       # stop-motion step
const SIGHT := 32.0
const FOG_HIDE := 30.0         # beyond this the player can't make it out

var body: WindowDresser
var mall: MallLevel
var player: Player
var state := State.DORMANT
var pos := Vector3.ZERO        # where it really is (the body catches up in steps)
var aggression := 0.0
var hunt_left := 0.0
var cooldown := 25.0
var seen := false              # the player can see it right now
var lit := false               # the player's torch is on its face
var last_known := Vector3.INF  # where it last saw/heard the player
var last_known_age := 999.0

var _home: Transform3D
var _frame_t := 0.0
var _path := PackedVector3Array()
var _path_i := 0
var _repath_t := 0.0
var _goal := Vector3.INF
var _stare_t := 0.0
var _unseen_t := 0.0
var _lost_t := 0.0
var _cutoff_t := 0.0
var _camp_t := 0.0
var _search: Array[Vector3] = []
var _step_t := 0.0
var _creak_t := 0.0
var _pose_dirty := false
var _rng := RandomNumberGenerator.new()
var _reachable := true
var _reveal := 0.0             # frozen while its face cracks open
var _feet: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D


func setup(p_mall: MallLevel, p_player: Player, home: Transform3D) -> void:
	mall = p_mall
	player = p_player
	_home = home
	_rng.randomize()
	body = WindowDresser.new()
	add_child(body)
	body.global_transform = home
	pos = home.origin
	body.set_env_light(Color(0.55, 0.53, 0.5))
	_feet = AudioStreamPlayer3D.new()
	_feet.bus = "World"
	_feet.unit_size = 4.0
	_feet.max_distance = 45.0
	add_child(_feet)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "World"
	_voice.unit_size = 5.0
	_voice.max_distance = 60.0
	add_child(_voice)


# ----------------------------------------------------------------- senses ---
func _head() -> Vector3:
	return pos + Vector3.UP * (1.55 if state == State.HUNT else 1.75)


## Can the player see it? In the camera's view, close enough to make out
## through the haze (or lit by the torch), and not behind anything.
func _player_sees() -> bool:
	var cam := player.camera
	var eye := cam.global_position
	for p in [_head(), pos + Vector3.UP * 1.0]:
		if not cam.is_position_in_frustum(p):
			continue
		var d := eye.distance_to(p)
		if d > FOG_HIDE and not lit:
			continue
		if _clear(eye, p):
			return true
	return false


func _torch_on_it() -> bool:
	if not player.flashlight_on:
		return false
	var cam := player.camera
	var to := _head() - cam.global_position
	if to.length() > 16.0:
		return false
	return (-cam.global_basis.z).angle_to(to) < deg_to_rad(13.0) and _clear(cam.global_position, _head())


## Does it see the player? Wide cone ahead (all round when hunting).
func _sees_player() -> bool:
	var eye := player.camera.global_position
	var to := eye - _head()
	if to.length() > SIGHT:
		return false
	if state != State.HUNT:
		var fwd := body.global_basis.z
		if fwd.angle_to(Vector3(to.x, 0, to.z)) > deg_to_rad(75.0):
			return false
	return _clear(_head(), eye)


## How far the player's footsteps carry right now.
func _noise_radius() -> float:
	var hs := Vector2(player.velocity.x, player.velocity.z).length()
	if hs < 0.3:
		return 0.0
	if player.crouching:
		return 3.0
	return 20.0 if hs > Player.WALK + 0.6 else 9.0


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


# -------------------------------------------------------------- thinking ---
func _physics_process(delta: float) -> void:
	if player == null or mall == null:
		return
	seen = _player_sees()
	lit = seen and _torch_on_it()
	var ppos := player.global_position
	var dist := Vector2(ppos.x - pos.x, ppos.z - pos.z).length()
	# Memory.
	last_known_age += delta
	if _sees_player():
		last_known = ppos
		last_known_age = 0.0
	elif dist < _noise_radius():
		# Heard you: roughly where you are.
		last_known = ppos + Vector3(_rng.randf_range(-1.5, 1.5), 0, _rng.randf_range(-1.5, 1.5))
		last_known_age = 0.0
	match state:
		State.DORMANT:
			_dormant(delta, dist)
		State.STALK:
			_stalk(delta, dist)
		State.HUNT:
			_hunt(delta, dist)
		State.SEARCH:
			_search_for(delta, dist)
		State.RETURN:
			_return_home(delta)
	_present(delta)


func _dormant(delta: float, dist: float) -> void:
	cooldown -= delta
	# Aggression: just being here, being close, running, the torch.
	aggression += delta * 0.006
	if dist < 7.0:
		aggression += delta * 0.05
	if _noise_radius() > 15.0 and dist < 20.0:
		aggression += delta * 0.04
	if lit:
		aggression += delta * 0.25
		_stare_t += delta
	else:
		_stare_t = maxf(_stare_t - delta, 0.0)
	if cooldown > 0.0:
		return
	if (lit and _stare_t > 1.6 and dist < 7.0):
		_wake()
	elif aggression >= 1.0 and not seen:
		_set_state(State.STALK)


func _stalk(delta: float, dist: float) -> void:
	if lit:
		_stare_t += delta
		if _stare_t > 1.4 and dist < 8.0:
			_wake()
			return
	else:
		_stare_t = maxf(_stare_t - delta * 0.5, 0.0)
	if seen:
		_unseen_t = 0.0
		_face(player.global_position)
		return                        # frozen
	_unseen_t += delta
	if dist < 2.6:
		_wake()                       # it got to you while you weren't looking
		return
	# Pick the next hiding place: out of the player's sight, closer than now.
	_repath_t -= delta
	if _goal == Vector3.INF or _repath_t <= 0.0 or (_path_i >= _path.size() and _repath_t < 0.9):
		_repath_t = 1.2
		_goal = _pick_stalk_spot(dist)
		_plan(_goal)
		if not _reachable and _goal != pos:
			_teleport(_goal)
			return
	_follow(delta, STALK_SPEED)
	_creak_t -= delta
	if _creak_t <= 0.0:
		_creak_t = _rng.randf_range(2.5, 5.0)
		_play(_voice, "creak", -10.0)


func _pick_stalk_spot(dist: float) -> Vector3:
	var p := player.global_position
	var best := Vector3.INF
	var best_score := INF
	var want := clampf(dist * 0.6, 2.0, 10.0)
	for i in 14:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(want * 0.6, want * 1.3)
		var c := _on_nav(p + Vector3(cos(a) * r, 0, sin(a) * r))
		if c == Vector3.INF:
			continue
		# Must be out of the player's sight; prefer behind them.
		var cam := player.camera
		if cam.is_position_in_frustum(c + Vector3.UP) and _clear(cam.global_position, c + Vector3.UP * 1.2):
			continue
		var behind := (c - p).normalized().dot(-cam.global_basis.z)
		var score := absf(c.distance_to(p) - want) + behind * 2.0
		if score < best_score:
			best_score = score
			best = c
	return best if best != Vector3.INF else pos


func _wake() -> void:
	body.set_awake(true)
	_play(_voice, "crack", 2.0)
	hunt_left = HUNT_TIME
	_set_state(State.HUNT)
	_reveal = 1.2
	_face(player.global_position)
	hunt_started.emit()


func _hunt(delta: float, dist: float) -> void:
	if _reveal > 0.0:
		# The face cracking open: it stands there looking at you. Run.
		_reveal -= delta
		_face(player.global_position)
		return
	hunt_left -= delta
	if hunt_left <= 0.0:
		_end_hunt()
		return
	if dist < CATCH_DIST and absf(player.global_position.y - pos.y) < 1.5:
		_set_state(State.DORMANT)
		caught.emit()
		return
	var sees := last_known_age < 0.2
	if sees:
		_lost_t = 0.0
		# Aim where the player is going: lead the target by the time it
		# takes to get there (capped), clamped onto the navmesh.
		var v := player.velocity
		var lead := clampf(dist / RUN, 0.0, 1.1)
		var aim := _on_nav(player.global_position + Vector3(v.x, 0, v.z) * lead)
		_repath_t -= delta
		if _repath_t <= 0.0 or _path_i >= _path.size():
			_repath_t = 0.25
			_plan(aim if aim != Vector3.INF else player.global_position)
	else:
		_lost_t += delta
		_cutoff_t -= delta
		# Lost sight while you run: come round the loop and meet you head on.
		if mall.loop_on and _lost_t > 1.8 and _cutoff_t <= 0.0 and not seen and _noise_radius() > 15.0:
			_cutoff_t = 12.0
			if _cut_off():
				return
		if _lost_t > 5.0:
			_begin_search()
			return
		_repath_t -= delta
		if _repath_t <= 0.0 or _path_i >= _path.size():
			_repath_t = 0.4
			_plan(last_known if last_known != Vector3.INF else player.global_position)
	_follow(delta, RUN_LIT if lit else RUN)


## Reappear ahead of the player (out of sight), where they're running to.
func _cut_off() -> bool:
	var p := player.global_position
	var v := Vector3(player.velocity.x, 0, player.velocity.z)
	if v.length() < 1.0:
		return false
	var ahead := _on_nav(p + v.normalized() * 16.0)
	if ahead == Vector3.INF:
		return false
	var cam := player.camera
	if cam.is_position_in_frustum(ahead + Vector3.UP) and _clear(cam.global_position, ahead + Vector3.UP):
		# They'd see it pop in; wait for the next corner.
		return false
	_teleport(ahead)
	_face(p)
	return true


func _begin_search() -> void:
	_search.clear()
	if last_known != Vector3.INF:
		_search.append(last_known)
		# Then the shop windows/doors nearest to where it lost you.
		var near: Array = []
		for t in mall.mannequin_spots:
			if t.origin.distance_to(last_known) < 14.0:
				near.append(t.origin)
		near.sort_custom(func(a: Vector3, b: Vector3) -> bool: return a.distance_to(last_known) < b.distance_to(last_known))
		for k in mini(3, near.size()):
			var o: Vector3 = near[k]
			# Stand in the shop doorway (on the concourse side) and look in.
			_search.append(_on_nav(Vector3(o.x, o.y, signf(o.z) * 5.2 + mall.global_position.z)))
	_camp_t = 0.0
	_set_state(State.SEARCH)


func _search_for(delta: float, dist: float) -> void:
	hunt_left -= delta
	if hunt_left <= 0.0:
		_end_hunt()
		return
	if last_known_age < 0.2:
		_set_state(State.HUNT)       # found you
		return
	if dist < CATCH_DIST:
		caught.emit()
		return
	if _search.is_empty():
		_begin_search()
		if _search.is_empty():
			_end_hunt()
		return
	var goal: Vector3 = _search[0]
	if goal == Vector3.INF:
		_search.pop_front()
		return
	if _path_i >= _path.size() or _goal != goal:
		_goal = goal
		_plan(goal)
	if Vector2(pos.x - goal.x, pos.z - goal.z).length() < 0.6:
		# Wait and listen (longer at a shop door it heard you behind).
		_camp_t += delta
		_face(player.global_position if dist < 12.0 else goal + Vector3(0, 0, -signf(goal.z)))
		if _camp_t > (6.0 if dist < 10.0 else 2.0):
			_camp_t = 0.0
			_search.pop_front()
		return
	_follow(delta, RUN * 0.7)


func _end_hunt() -> void:
	hunt_ended.emit()
	aggression = 0.15
	cooldown = 80.0
	_set_state(State.RETURN)


## Back to the window display, only moving while nobody is looking.
func _return_home(delta: float) -> void:
	if seen:
		return
	if body.awake:
		body.set_awake(false)
	# Pick a (possibly new) display spot far from the player.
	if _goal == Vector3.INF or _path_i >= _path.size():
		var best := _home
		var far := 0.0
		for t in mall.mannequin_spots:
			var d := t.origin.distance_to(player.global_position)
			if d > far and d < 60.0:
				far = d
				best = t
		_home = best
		_goal = best.origin
		_plan(_goal)
		if not _reachable:
			_path = PackedVector3Array()
	if Vector2(pos.x - _goal.x, pos.z - _goal.z).length() < 0.5 or _path.is_empty():
		_teleport(_home.origin)
		body.global_transform = _home
		_set_state(State.DORMANT)
		return
	_follow(delta, STALK_SPEED)


# ------------------------------------------------------------ movement ---
func _plan(to: Vector3) -> void:
	if to == Vector3.INF:
		_path = PackedVector3Array()
		_path_i = 0
		return
	var map := get_world_3d().navigation_map
	_path = NavigationServer3D.map_get_path(map, pos, to, true)
	_path_i = 1 if _path.size() > 1 else _path.size()
	# Can it actually get there? (It may be shut in a shop behind a stuck
	# shutter; it doesn't walk then, it just isn't there any more.)
	_reachable = _path.size() > 0 and Vector2(_path[-1].x - to.x, _path[-1].z - to.z).length() < 1.0


func _follow(delta: float, speed: float) -> void:
	var step := speed * delta
	while step > 0.0 and _path_i < _path.size():
		var target := _path[_path_i]
		var to := target - pos
		to.y = 0.0
		var d := to.length()
		if d <= step:
			pos = Vector3(target.x, target.y, target.z)
			step -= d
			_path_i += 1
		else:
			pos += to / d * step
			step = 0.0
	if _path_i < _path.size():
		_face(_path[_path_i])
	else:
		_face(player.global_position)


func _on_nav(p: Vector3) -> Vector3:
	var map := get_world_3d().navigation_map
	var q := NavigationServer3D.map_get_closest_point(map, p)
	if q.distance_to(Vector3(p.x, q.y, p.z)) > 2.5:
		return Vector3.INF
	return q


var _yaw := 0.0


func _face(target: Vector3) -> void:
	var d := target - pos
	if Vector2(d.x, d.z).length() > 0.05:
		_yaw = atan2(d.x, d.z)


func _teleport(p: Vector3) -> void:
	pos = p
	_path = PackedVector3Array()
	_path_i = 0
	body.global_position = p
	_pose_dirty = true


## The mall loop moved the world under everyone: keep relative positions.
func shift(offset: Vector3) -> void:
	pos += offset
	body.global_position += offset
	for i in _path.size():
		_path[i] += offset
	if last_known != Vector3.INF:
		last_known += offset
	if _goal != Vector3.INF:
		_goal += offset


func _set_state(s: State) -> void:
	state = s
	_path = PackedVector3Array()
	_path_i = 0
	_goal = Vector3.INF
	_pose_dirty = true
	_stare_t = 0.0


# ----------------------------------------------------------- presentation ---
## Stop-motion: the body jumps to the real position a few times a second,
## never while the player is looking (unless it's hunting).
func _present(delta: float) -> void:
	_frame_t -= delta
	if _frame_t > 0.0:
		return
	_frame_t = FRAME
	var moving := body.global_position.distance_to(pos) > 0.02
	if seen and state != State.HUNT and state != State.SEARCH:
		return                       # it never moves while you watch
	body.global_position = pos
	body.rotation.y = _yaw
	match state:
		State.DORMANT:
			if _pose_dirty:
				body.set_pose("dormant")
		State.STALK, State.RETURN:
			if moving or _pose_dirty:
				body.set_pose(["stalk_a", "stalk_b", "stalk_c", "hunt"][_rng.randi() % 4])
		State.HUNT, State.SEARCH:
			if _reveal > 0.0:
				body.set_pose("hunt")
			elif moving:
				body.play_run(1.6 if state == State.HUNT else 1.1)
				_step_t -= FRAME
				if _step_t <= 0.0:
					_step_t = 0.28
					_play(_feet, "clack", -2.0, _rng.randf_range(0.85, 1.15))
			else:
				body.set_pose("hunt")
	_pose_dirty = false
	_feet.global_position = pos
	_voice.global_position = _head()


func _play(p: AudioStreamPlayer3D, sound: String, db: float, pitch := 1.0) -> void:
	p.stream = AudioSynth.cached(sound)
	p.volume_db = db
	p.pitch_scale = pitch
	p.play()


## For the jump scare: its broken face right in front of your eyes.
func lunge_at(cam: Camera3D) -> void:
	var f := -cam.global_basis.z
	f.y = 0.0
	f = f.normalized()
	body.rotation.y = atan2(-f.x, -f.z)
	body.set_awake(true)
	body.set_pose("lunge")
	body.global_position = cam.global_position + f * 0.9 - Vector3.UP * 1.5
	# Put its head (wherever the pose leaves it) half a metre ahead of the eye.
	var head := body.head_position()
	if head.is_finite():
		body.global_position += (cam.global_position + f * 0.5 - Vector3.UP * 0.04) - head
	_voice.global_position = cam.global_position
	_play(_voice, "shriek", 6.0)
