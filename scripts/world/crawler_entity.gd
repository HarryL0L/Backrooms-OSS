class_name CrawlerEntity
extends Walker
## The Unlit Halls: something on all fours, pale and bare as a shop
## dummy, that you only ever see in your flashlight. While you're not
## looking it creeps closer through the dark; look its way and it goes still; put the beam on it and
## it scuttles off and is gone. Let it reach you and it lunges with a
## shriek: you stagger (winded, the torch knocked out) and it's gone. It
## never kills you.

enum { CREEP, FLEE, LUNGE }

const REACH := 1.8

var hall_figure: HallFigure   # never both at once

var _state := CREEP
var _timer := 0.0
var _repath := 0.0
var _lit := 0.0
var _flee_t := 0.0
var _life := 0.0
var _lunge_t := 0.0
var _lunge_from := Vector3.ZERO


func _ready() -> void:
	super()
	_timer = _rng.randf_range(40.0, 80.0)


func _process(delta: float) -> void:
	var on: bool = allowed and gen != null and player != null and Settings.get_value("gameplay/entities")
	if not on or _player_biome() != WorldGen.DARK or player.seated:
		if present:
			_despawn()
		return
	if not present:
		_timer -= delta
		if _timer <= 0.0:
			_timer = 3.0
			if hall_figure == null or not hall_figure.visible:
				_try_spawn()
		return
	_life += delta
	# Hardly any light of its own: the flashlight shows it.
	_update_light(delta, 0.12)
	var d := _dist()
	var seen := _seen(30.0, 36.0, 0.6)
	_lit = _lit + delta if _lit_by_flashlight(0.5) else 0.0
	match _state:
		CREEP:
			if _lit > 0.2:
				_state = FLEE
				_flee_t = 0.0
				speed = 4.2
				_say("crawler_hiss", -2.0, _rng.randf_range(0.95, 1.1))
				_wander(6, 10, true)
			elif d < REACH:
				_state = LUNGE
				_lunge_t = 0.0
				_lunge_from = global_position
				_say("crawler_scream", 4.0, _rng.randf_range(0.95, 1.08))
			elif seen:
				# Caught in the corner of your eye: perfectly still.
				body.pose_crawl(_phase, 0.0)
			else:
				_repath -= delta
				if _repath <= 0.0 or _path.is_empty():
					_repath = 1.0
					_path = nav.path(_cell(), gen.cell_of(player.global_position), 12)
					if _path.is_empty() and _life > 5.0:
						_vanish()
						return
				speed = 1.7 if d > 6.0 else 1.1
				if _path.size() <= 1:
					_creep_at(player.global_position, delta)
				else:
					_walk(delta)
				body.pose_crawl(_phase, 1.0)
		FLEE:
			_flee_t += delta
			if not _walk(delta, 1.0):
				_creep_at(global_position + _forward(), delta)
			body.pose_crawl(_phase, 1.0)
			if (_flee_t > 0.7 and not seen) or _flee_t > 3.0:
				_vanish()
				return
		LUNGE:
			_lunge_t += delta
			var k := clampf(_lunge_t / 0.22, 0.0, 1.0)
			var to := player.global_position - _lunge_from
			to.y = 0.0
			global_position = _lunge_from + to * k * maxf(1.0 - 0.6 / maxf(to.length(), 0.01), 0.0)
			_face(to, 1.0)
			body.pose_crawl(_phase, 0.0)
			if _lunge_t > 0.22:
				_hit()
				return
	if _life > 90.0 and not seen:
		_vanish()


## Straight at a point (the last bit, inside your own cell).
func _creep_at(p: Vector3, delta: float) -> void:
	var to := p - global_position
	to.y = 0.0
	var d := to.length()
	if d > 0.05:
		global_position += to / d * minf(speed * delta, d)
		_face(to, 1.0 - exp(-8.0 * delta))
	_stride(delta, speed)


func _hit() -> void:
	_shake(player.camera, 0.09, 0.7)
	player.stamina = 0.0
	player.exhausted = true
	if player.flashlight_on:
		player.set_flashlight(false)
	_vanish()


func _try_spawn() -> void:
	_nav(WorldGen.DARK)
	var c := _spawn_cell(12.0, 22.0, true)
	if c.x == 1 << 30:
		return
	_make_body("crawler", 1.0)
	_place(c, player.global_position)
	_state = CREEP
	_life = 0.0
	_lit = 0.0
	_repath = 0.0
	body.pose_crawl(0.0, 0.0)
	_update_light(1.0, 0.12)


func _vanish() -> void:
	_despawn()
	_timer = _rng.randf_range(60.0, 120.0)


## Limbs skittering on the carpet (recorded), now and then as it moves.
func _footstep(v: float) -> void:
	if _steps.playing:
		return
	_steps.stream = Sfx.get_stream("crawler_scuttle")
	_steps.pitch_scale = _rng.randf_range(0.9, 1.15)
	_steps.volume_db = linear_to_db(clampf(v / 3.0, 0.3, 1.0)) - 9.0
	_steps.play(_rng.randf() * 1.5)


## For tests: crouched here, facing a point.
func debug_place(pos: Vector3, face: Vector3) -> void:
	_nav(WorldGen.DARK)
	_make_body("crawler", 1.0)
	_place(gen.cell_of(pos), face)
	global_position = pos
	_state = CREEP
	_life = 0.0
	body.pose_crawl(0.6, 1.0)
