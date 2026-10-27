class_name AttendantEntity
extends Walker
## The car park has something that walks its lanes like an attendant:
## tall (well over two metres), thin, long-armed and pitch black, a shape
## you see against the lights and lose in the dark (your torch only finds
## a dull sheen on it). Heavy footsteps you hear long before you see it.
## If it sees you (a torch makes you easier to see, crouching harder) or
## hears you (running, a car door slamming, an engine), it comes, fast.
## Lose it and it searches where it last saw you, then gives up and walks
## off. If it catches you, you're somewhere else.
##
## Hide in a car: sit in it with the doors shut and the lights off and it
## can't see you; it may come and look in through the window, then leave.
## But if it saw you get in, it opens the door.

signal caught

enum { PATROL, INVESTIGATE, CHASE, SEARCH, PEER, GRAB, LEAVE }

const SIGHT := 22.0
const CONE := 35.0
const CHASE_SPEED := 4.3
const CATCH := 1.0
const SIZE := 1.3                        # about 2.3 m
const TINT := Color(0.015, 0.015, 0.017) # pitch black; the torch shows a sheen

var _state := PATROL
var _timer := 0.0
var _t := 0.0
var _last_known := Vector3.ZERO
var _lost := 0.0
var _repath := 0.0
var _search_t := 0.0
var _saw_get_in := false
var _car: ParkedCar           # the car you're hiding in, when it's at it
var _peer_t := 0.0
var _unseen := 0.0
var _life := 0.0
var _heart: AudioStreamPlayer
var _heard_cool := 0.0
var _growl_t := 8.0


func _ready() -> void:
	super()
	_timer = _rng.randf_range(15.0, 30.0)
	add_to_group(&"listeners")
	_steps.unit_size = 7.0
	_steps.max_distance = 55.0
	_voice.position = Vector3.UP * 2.2
	_heart = AudioStreamPlayer.new()
	_heart.bus = "World"
	add_child(_heart)


func _process(delta: float) -> void:
	var on: bool = allowed and gen != null and player != null and Settings.get_value("gameplay/entities")
	if not on or _player_biome() != WorldGen.GARAGE:
		if present:
			_despawn()
			_timer = _rng.randf_range(20.0, 40.0)
		_heart.stop()
		return
	if not present:
		_timer -= delta
		if _timer <= 0.0:
			_timer = 3.0
			_try_spawn()
		return
	_t += delta
	_life += delta
	_heard_cool -= delta
	_update_light(delta)
	var d := _dist()
	var sees := _sees_player(d)
	if sees:
		_last_known = player.global_position
		_lost = 0.0
		if player.seated or player._ride_t >= 0.0:
			_saw_get_in = true
		if _state != CHASE and _state != GRAB:
			_start_chase()
	else:
		_lost += delta
		if not player.seated and player._ride_t < 0.0:
			_saw_get_in = false
		_listen(d)
	_unseen = 0.0 if _seen(50.0, 40.0, 1.8) else _unseen + delta
	match _state:
		PATROL:
			speed = 1.3
			if not _walk(delta):
				_prowl()
			_growl_t -= delta
			if _growl_t <= 0.0:
				_growl_t = _rng.randf_range(14.0, 28.0)
				_say("tall_growl_%d" % _rng.randi_range(0, 2), -6.0, _rng.randf_range(0.8, 0.95))
		INVESTIGATE:
			if not _walk(delta, 0.4 if speed > 2.0 else 0.0):
				_search()
		CHASE:
			_chase(delta, d, sees)
		SEARCH:
			_search_t -= delta
			# Looks one way, then the other.
			_face(Vector3(sin(_t * 0.9), 0, cos(_t * 0.9)), 1.0 - exp(-1.2 * delta))
			if _search_t <= 0.0:
				var car := _hiding_car()
				if car and car.global_position.distance_to(global_position) < 9.0:
					_go_peer(car)
				else:
					_leave()
		PEER:
			_peer(delta)
		GRAB:
			_grab(delta)
		LEAVE:
			speed = 1.5
			if not _walk(delta):
				_wander(8, 14, true)
			if (_unseen > 2.0 and d > 22.0) or _unseen > 25.0:
				_despawn()
				_timer = _rng.randf_range(60.0, 120.0)
	if _state == PATROL and _life > 240.0 and _unseen > 2.0 and d > 25.0:
		_despawn()
		_timer = _rng.randf_range(40.0, 90.0)
	_heartbeat(d)
	if _state != PEER:
		body.stoop = 0.0
	_animate(delta)


# -------------------------------------------------------------- senses ---

func _sees_player(d: float) -> bool:
	if player.seated:
		var car := _hiding_car()
		# Shut in a dark car: invisible (unless it watched you get in).
		if car and car.sheltered() and not car.conspicuous() and not player.flashlight_on:
			return _saw_get_in and d < 30.0 and _lost < 2.0
		# A lit-up car shows you at closer range, through the glass.
		return d < 10.0 and _in_cone(player.camera.global_position, 60.0)
	var range_m := SIGHT * (1.4 if player.flashlight_on else 1.0) * (0.5 if player.crouching else 1.0)
	if d > range_m:
		return false
	var chest := player.global_position + Vector3.UP * (0.6 if player.crouching else 1.2)
	if d > 2.5 and not _in_cone(chest, CONE):
		return false
	return _clear(global_position + Vector3.UP * 2.2, chest)


func _in_cone(p: Vector3, deg: float) -> bool:
	var to := p - global_position
	to.y = 0.0
	return _forward().dot(to.normalized()) > cos(deg_to_rad(deg))


## Footsteps: running carries, walking only close by; crouching is silent.
func _listen(d: float) -> void:
	if player.seated or player.crouching or _heard_cool > 0.0:
		return
	var v := Vector2(player.velocity.x, player.velocity.z).length()
	if (v > Player.WALK + 0.6 and d < 16.0) or (v > 1.5 and d < 6.0):
		hear(player.global_position, 999.0)


## A noise (called through the "listeners" group by cars).
func hear(at: Vector3, radius: float) -> void:
	if not present or _state == CHASE or _state == GRAB:
		return
	if Vector2(at.x - global_position.x, at.z - global_position.z).length() > radius:
		return
	_heard_cool = 1.5
	_last_known = at
	_go_to(at, 2.4)
	_state = INVESTIGATE
	if _rng.randf() < 0.5:
		_say("tall_growl_%d" % _rng.randi_range(0, 2), -4.0, _rng.randf_range(0.85, 1.0))


# ------------------------------------------------------------- actions ---

func _start_chase() -> void:
	_state = CHASE
	_repath = 0.0
	_say("tall_scream_%d" % _rng.randi_range(0, 2), 3.0, _rng.randf_range(0.8, 0.95))
	var sting := AudioStreamPlayer.new()
	sting.stream = AudioSynth.cached("sting")
	sting.bus = "World"
	sting.volume_db = -3.0
	add_child(sting)
	sting.play()
	sting.finished.connect(sting.queue_free)


func _chase(delta: float, d: float, sees: bool) -> void:
	speed = CHASE_SPEED
	if player.seated:
		var car := _hiding_car()
		if car and _saw_get_in:
			_go_peer(car)
			_state = GRAB
			return
	if sees and d < CATCH:
		_catch()
		return
	if _lost > 1.2:
		# Lost you: on to where you were last seen.
		_go_to(_last_known, 3.2)
		_state = INVESTIGATE
		return
	var target := player.global_position if sees else _last_known
	# In the open with nothing in the way: straight at you.
	if sees and _direct(target):
		_path.clear()
		var to := target - global_position
		to.y = 0.0
		global_position += to.normalized() * minf(speed * delta, to.length())
		_face(to, 1.0 - exp(-10.0 * delta))
		_stride(delta, speed, 1.0)
	else:
		_repath -= delta
		if _repath <= 0.0 or _path.is_empty():
			_repath = 0.4
			_path = nav.path(_cell(), gen.cell_of(target), 16)
		if not _walk(delta, 1.0):
			_lost += delta


func _direct(target: Vector3) -> bool:
	var side := (target - global_position).cross(Vector3.UP).normalized() * 0.3
	for o in [side, -side]:
		if not _clear(global_position + Vector3.UP * 0.5 + o, target + Vector3.UP * 0.5 + o):
			return false
	return true


func _go_to(at: Vector3, v: float) -> void:
	speed = v
	_path = nav.path(_cell(), nav.nearest_ok(gen.cell_of(at)), 16)


## Walks the lanes around wherever you are (it knows roughly), so it's
## never long before it comes past.
func _prowl() -> void:
	var here := _cell()
	var f := nav.flood(here, 18, 1200)
	var p := player.global_position
	var best := []
	for c in f:
		var at := EntityNav.center(c)
		var d := Vector2(at.x - p.x, at.z - p.z).length()
		if d > 6.0 and d < 16.0:
			best.append(c)
	if best.is_empty():
		_wander(4, 10)
		return
	_path = EntityNav.path_to(f, best[_rng.randi() % best.size()])


func _search() -> void:
	_state = SEARCH
	_search_t = _rng.randf_range(4.0, 7.0)
	_path.clear()


func _leave() -> void:
	_state = LEAVE
	_saw_get_in = false
	_wander(8, 14, true)


## Over to the driver's window of the car you're in.
func _go_peer(car: ParkedCar) -> void:
	_car = car
	_state = PEER
	_peer_t = _rng.randf_range(3.5, 5.0)
	var at := car.global_transform * (ParkedCar.EXIT_FEET + Vector3(0, 0, 0.35))
	speed = 1.4
	_path = nav.path(_cell(), nav.nearest_ok(gen.cell_of(at)), 12)


func _peer(delta: float) -> void:
	if _car == null or not is_instance_valid(_car):
		_leave()
		return
	var at := _car.global_transform * (ParkedCar.EXIT_FEET + Vector3(0, 0, 0.35))
	if _walk(delta) or _approach(at, delta):
		return
	# At the window, stooping to look in, breathing on the glass.
	if not _voice.playing:
		_say("tall_breath", -2.0, 0.85)
	_face(_car.global_position - global_position, 1.0 - exp(-4.0 * delta))
	body.stoop = 0.8
	_peer_t -= delta
	if _peer_t <= 0.0:
		_leave()


## It saw you get in: straight to the door, wrenches it open.
func _grab(delta: float) -> void:
	if _car == null or not is_instance_valid(_car) or _car.driver() != player:
		_state = CHASE
		return
	speed = 3.0
	var at := _car.global_transform * (ParkedCar.EXIT_FEET + Vector3(0, 0, 0.35))
	if _walk(delta, 0.6) or _approach(at, delta):
		return
	_face(_car.global_position - global_position, 1.0)
	_car.pry_open()
	_catch()


## The last bit to a point off the cell grid; true while still going.
func _approach(at: Vector3, delta: float) -> bool:
	var to := at - global_position
	to.y = 0.0
	if to.length() < 0.1:
		return false
	global_position += to.normalized() * minf(speed * delta, to.length())
	_face(to, 1.0 - exp(-8.0 * delta))
	_stride(delta, speed)
	return true


func _catch() -> void:
	_state = GRAB
	set_process(false)
	_heart.stop()
	if not Jumpscare.enabled():
		_say("tall_roar", 5.0, 0.9)
		_shake(player.camera, 0.12, 1.0)
	caught.emit()


## Your heart, while it's after you or close.
func _heartbeat(d: float) -> void:
	var near := (_state == CHASE or _state == PEER or _state == GRAB or _state == INVESTIGATE) and d < 22.0
	if not near:
		if _heart.playing:
			_heart.stop()
		return
	_heart.volume_db = linear_to_db(clampf(1.2 - d / 22.0, 0.15, 1.0)) - 2.0
	_heart.pitch_scale = 1.35 if _state == CHASE else 1.0
	if not _heart.playing:
		_heart.stream = Sfx.get_stream("heartbeat")
		_heart.play()


func _hiding_car() -> ParkedCar:
	if not player.seated:
		return null
	for n in get_tree().get_nodes_in_group("usable"):
		if n is ParkedCar and (n as ParkedCar).driver() == player:
			return n
	return null



func _try_spawn() -> void:
	_nav(WorldGen.GARAGE)
	var c := _spawn_cell(18.0, 30.0)
	if c.x == 1 << 30:
		return
	_make_body("tall", SIZE, TINT, 0.3)
	_place(c, player.global_position)
	set_process(true)
	_state = PATROL
	_life = 0.0
	_lost = 99.0
	_saw_get_in = false
	_unseen = 0.0
	_update_light(1.0)


func _despawn() -> void:
	super()
	set_process(true)
	if _heart:
		_heart.stop()


## It takes longer strides than you.
func _stride(delta: float, v: float, run := 0.0) -> void:
	super(delta, v / 1.27, run)


## Heavy footfalls on the concrete (recorded, pitched down: it's big).
func _footstep(v: float) -> void:
	_steps.stream = Sfx.pick("tall_step", 8)
	_steps.pitch_scale = _rng.randf_range(0.74, 0.84)
	_steps.volume_db = linear_to_db(clampf(v / Player.SPRINT, 0.45, 1.0)) + 4.0
	_steps.play()


## For tests: standing here, facing a point, on patrol.
func debug_place(pos: Vector3, face: Vector3) -> void:
	_nav(WorldGen.GARAGE)
	_make_body("tall", SIZE, TINT, 0.3)
	_place(gen.cell_of(pos), face)
	global_position = pos
	set_process(true)
	_state = PATROL
	_lost = 99.0
	_life = 0.0
