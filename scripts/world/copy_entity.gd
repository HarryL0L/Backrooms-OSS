class_name CopyEntity
extends Walker
## Level 1: now and then someone else is walking the warehouse aisles. A
## man in ordinary clothes, minding his own business, who never says
## anything. Look at one and he stops and turns his head to you; after a
## while he walks off. Get close and it turns and walks
## away. Once it's seen you up close, the moment you look away it isn't
## there any more. It never comes towards you and never touches you.

enum { WALK, WATCH, LEAVE }

const NEAR := 5.0
const WHO := ["sam", "jordan"]

var _state := WALK
var _timer := 0.0
var _pause := 0.0
var _watch_t := 0.0
var _head := 0.0             # head turn (radians, body-relative)
var _was_close := false
var _unseen := 0.0
var _life := 0.0
var _t := 0.0


func _ready() -> void:
	super()
	_timer = _rng.randf_range(15.0, 45.0)


func _process(delta: float) -> void:
	var on: bool = allowed and gen != null and player != null and Settings.get_value("gameplay/entities")
	if not on or _player_biome() != WorldGen.CONCRETE:
		if present:
			_despawn()
		return
	if not present:
		_timer -= delta
		if _timer <= 0.0:
			_timer = 3.0
			_try_spawn()
		return
	_t += delta
	_life += delta
	_update_light(delta)
	var d := _dist()
	var seen := _seen(32.0)
	_unseen = 0.0 if seen else _unseen + delta
	if d < 9.0:
		_was_close = true
	# Gone the moment you look away, once you've been near; or when it's
	# far behind you, or has been about for long enough.
	if (_was_close and _unseen > 0.4) or d > 48.0 or (_life > 150.0 and _unseen > 1.0):
		_vanish()
		return
	if d < NEAR and _state != LEAVE:
		_leave(1.7)
	match _state:
		WALK:
			if seen and d < 26.0:
				_state = WATCH
				_watch_t = _rng.randf_range(2.0, 4.5)
				_path.clear()
			elif _pause > 0.0:
				_pause -= delta
			elif not _walk(delta):
				# Stand a moment, then on somewhere else.
				_pause = _rng.randf_range(0.0, 2.5)
				if not _wander(3, 8):
					_pause = 1.0
		WATCH:
			_watch_t -= delta
			if _watch_t < 0.0:
				_leave(1.25)
		LEAVE:
			if not _walk(delta):
				_state = WALK
				_pause = 0.5
	# Turn the head to you while watching (and a glance back when leaving).
	var want := 0.0
	if _state == WATCH or (_state == LEAVE and d < 12.0 and seen):
		var to := player.camera.global_position - global_position
		want = wrapf(atan2(to.x, to.z) - rotation.y, -PI, PI)
		want = clampf(want, -1.6, 1.6)
		# A body turn follows if it would have to crane too far.
		if _state == WATCH and absf(want) > 1.2:
			_face(to, 1.0 - exp(-1.5 * delta))
	_head = lerpf(_head, want, 1.0 - exp(-3.0 * delta))
	body.head_yaw = _head
	_animate(delta)


func _leave(v: float) -> void:
	_state = LEAVE
	speed = v
	if not _wander(5, 10, true):
		_state = WALK


func _try_spawn() -> void:
	_nav(WorldGen.CONCRETE)
	var c := _spawn_cell(16.0, 30.0)
	if c.x == 1 << 30:
		return
	_make_body(WHO[_rng.randi() % WHO.size()])
	_place(c, player.global_position)
	_state = WALK
	speed = _rng.randf_range(1.0, 1.3)
	_pause = 0.0
	_was_close = false
	_unseen = 0.0
	_life = 0.0
	_head = 0.0
	_update_light(1.0)


func _vanish() -> void:
	_despawn()
	_timer = _rng.randf_range(35.0, 90.0)


func _step_db() -> float:
	return -11.0


## For tests: stand here (facing a point) and start walking.
func debug_place(pos: Vector3, face: Vector3) -> void:
	_nav(WorldGen.CONCRETE)
	_make_body(WHO[0])
	_place(gen.cell_of(pos), face)
	global_position = pos
	_state = WALK
	_was_close = false
	_life = 0.0
