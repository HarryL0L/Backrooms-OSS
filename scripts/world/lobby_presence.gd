class_name LobbyPresence
extends Node3D
## Something else walks the Lobby. It is never seen, only heard: now and then
## footsteps start up on the carpet somewhere behind the walls, heavier than
## yours, and come your way. Run, and it hears you sooner and walks faster;
## stand still and it stops to listen. It never comes closer than the next
## room, and the steps simply stop, which is worse.

const STEP_GAP := 0.62

var gen: WorldGen
var player: Player
var ambience: Ambience
## Set by the game (playing, in the Backrooms, not mid-transition).
var allowed := false

var _audio: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _wait := 0.0
var _pos := Vector3.ZERO
var _steps_left := 0
var _step_t := 0.0
var _heard := 0.0          # how much noise you've made lately (0..1)


func _ready() -> void:
	_rng.randomize()
	_wait = _rng.randf_range(35.0, 80.0)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = "World"
	# Carries through the walls: you should know it when you hear it.
	_audio.unit_size = 9.0
	_audio.max_distance = 40.0
	add_child(_audio)


func _process(delta: float) -> void:
	if not allowed or gen == null or player == null or ambience == null or not ambience.is_ready() \
			or not Settings.get_value("gameplay/entities"):
		_steps_left = 0
		if ambience:
			ambience.hum_duck_presence = 1.0
		return
	# The hum dips a little while it walks, so the steps stand out.
	ambience.hum_duck_presence = lerpf(ambience.hum_duck_presence, 0.6 if _steps_left > 0 else 1.0, 1.0 - exp(-2.0 * delta))
	var pp := player.global_position
	var spd := Vector2(player.velocity.x, player.velocity.z).length()
	_heard = clampf(_heard + delta * (0.22 if spd > 3.4 else -0.04), 0.0, 1.0)
	if _steps_left > 0:
		_step_t -= delta
		if _step_t <= 0.0:
			_step()
		return
	var c := gen.cell_of(pp)
	if gen.biome_at(c.x, c.y) != WorldGen.LOBBY or pp.y < -1.0:
		return
	_wait -= delta * (1.0 + _heard * 2.5)
	if _wait <= 0.0:
		_begin()


## Starts somewhere 9-14 m away that you can't see.
func _begin() -> void:
	var eye := player.global_position + Vector3.UP * 1.5
	var space := get_world_3d().direct_space_state
	for _try in 24:
		var a := _rng.randf() * TAU
		var d := _rng.randf_range(9.0, 14.0)
		var p := player.global_position + Vector3(cos(a) * d, 0.0, sin(a) * d)
		var cc := gen.cell_of(p)
		if gen.biome_at(cc.x, cc.y) != WorldGen.LOBBY or gen.is_solid(cc.x, cc.y, WorldGen.LOBBY):
			continue
		p = Vector3((cc.x + 0.5) * WorldGen.CELL, 0.05, (cc.y + 0.5) * WorldGen.CELL)
		var q := PhysicsRayQueryParameters3D.create(eye, p + Vector3.UP * 1.2)
		q.exclude = [player.get_rid()]
		if space.intersect_ray(q).is_empty():
			continue           # in plain sight: somewhere else
		_pos = p
		_steps_left = _rng.randi_range(7, 16)
		_step_t = 0.0
		return
	_wait = 20.0


func _step() -> void:
	_steps_left -= 1
	var gap := STEP_GAP * (0.65 if _heard > 0.5 else 1.0) * _rng.randf_range(0.9, 1.12)
	_step_t = gap
	var to := player.global_position - _pos
	to.y = 0.0
	if to.length() < 6.5:
		# Right on the other side of the wall now. Then nothing.
		_steps_left = 0
	elif _rng.randf() < 0.12 and _heard < 0.3:
		_step_t += _rng.randf_range(1.2, 3.0)     # stops, listening
	if _steps_left > 0 or to.length() >= 6.5:
		var dir := to.normalized().rotated(Vector3.UP, _rng.randf_range(-0.5, 0.5))
		_pos += dir * 0.72
	_audio.global_position = _pos + Vector3.UP * 0.1
	# Its own heavy shoes, not like your steps (see AudioSynth.stalk_step).
	_audio.stream = AudioSynth.cached("stalk_step%d" % _rng.randi_range(0, 3))
	_audio.pitch_scale = _rng.randf_range(0.94, 1.04)
	_audio.volume_db = 2.0
	_audio.play()
	if _steps_left == 0:
		_wait = _rng.randf_range(70.0, 160.0)
