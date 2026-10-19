class_name Walker
extends Node3D
## What the walking entities share: a body (EntityBody, a downloaded CC0
## figure with its own walk and run clips) that walks a grid path
## (EntityNav) at a given speed with footsteps, lit like everything else by
## the light where it stands, and checks for whether you can see it, whether
## your flashlight is on it, and where you are. Each level's entity extends
## it with its own behaviour; nothing here runs until `present`.

var gen: WorldGen:
	set(g):
		gen = g
		nav = null
		if present:
			_despawn()
var player: Player
var ambience: Ambience
var allowed := false
var nav: EntityNav
var body: EntityBody
var present := false
var speed := 1.2

var _path: Array[Vector2i] = []
var _phase := 0.0
var _moving := 0.0           # 0 standing .. 1 walking (blended)
var _light_t := 0.0
var _steps: AudioStreamPlayer3D
var _voice: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	visible = false
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = "World"
	_steps.unit_size = 3.0
	_steps.max_distance = 30.0
	add_child(_steps)
	_voice = AudioStreamPlayer3D.new()
	_voice.bus = "World"
	_voice.unit_size = 6.0
	_voice.max_distance = 45.0
	_voice.position = Vector3.UP * 1.6
	add_child(_voice)


## A new body (a fresh face, clothes and proportions each time).
## A body: one of the downloaded figures (see EntityBody.SCENES), `size`
## times life size, its clothes tinted.
func _make_body(who: String, size := 1.0, tint := Color.WHITE) -> void:
	if body and body.who == who and is_equal_approx(body.scale.y, size):
		return
	if body:
		body.queue_free()
	body = EntityBody.new()
	body.who = who
	body.tint = tint
	body.scale = Vector3.ONE * size
	add_child(body)
	_light_t = 0.0


var _last_pos := Vector3.ZERO
var _vel := 0.0


## Plays the clip for how fast it's actually going, then any overlays.
func _animate(delta: float) -> void:
	if body == null:
		return
	var d := global_position - _last_pos
	d.y = 0.0
	_last_pos = global_position
	var v := d.length() / maxf(delta, 0.001)
	if v > 20.0:
		v = 0.0             # placed somewhere new
	_vel = lerpf(_vel, v, 1.0 - exp(-10.0 * delta))
	if body.who != "crawler":
		body.move(_vel)
	body.update(delta)


func _nav(biome: int) -> EntityNav:
	if nav == null or nav.biome != biome:
		nav = EntityNav.new(gen, biome)
	return nav


func _biome_at(p: Vector3) -> int:
	var c := gen.cell_of(p)
	return gen.biome_at(c.x, c.y)


func _player_biome() -> int:
	return _biome_at(player.global_position)


func _cell() -> Vector2i:
	return gen.cell_of(global_position)


func _place(c: Vector2i, face: Vector3) -> void:
	global_position = EntityNav.center(c)
	_face(face - global_position, 1.0)
	_last_pos = global_position
	_vel = 0.0
	_path.clear()
	present = true
	visible = true
	_light_t = 0.0


## Gone, whatever it was doing.
func reset() -> void:
	_despawn()


func _despawn() -> void:
	present = false
	visible = false
	_path.clear()
	_steps.stop()


## Turns towards a direction (the body faces +Z).
func _face(dir: Vector3, k: float) -> void:
	if Vector2(dir.x, dir.z).length() < 0.01:
		return
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), k)


func _forward() -> Vector3:
	return global_basis.z


## Walks the current path; true while there's still some of it to go.
func _walk(delta: float, run := 0.0) -> bool:
	if _path.is_empty():
		return false
	var target := EntityNav.center(_path[0])
	var to := target - global_position
	to.y = 0.0
	var d := to.length()
	var step := speed * delta
	if d <= step:
		global_position = Vector3(target.x, global_position.y, target.z)
		_path.pop_front()
	else:
		global_position += to / d * step
	_face(to, 1.0 - exp(-8.0 * delta))
	_stride(delta, speed, run)
	return true


## Advances the walk cycle (and footsteps) for moving at `v` m/s.
func _stride(delta: float, v: float, run := 0.0) -> void:
	var before := _phase
	# About 0.75 m a step walking, 1.1 running (two steps per TAU).
	_phase += delta * v / lerpf(0.75, 1.1, run) * PI
	if floori(before / PI) != floori(_phase / PI):
		_footstep(v)


func _footstep(v: float) -> void:
	if ambience == null:
		return
	var st := ambience.step_stream(Player.surface_for(gen, global_position))
	if st == null:
		return
	_steps.stream = st
	_steps.pitch_scale = _rng.randf_range(0.9, 1.1) * _step_pitch()
	_steps.volume_db = linear_to_db(clampf(v / Player.SPRINT, 0.3, 1.0)) + _step_db()
	_steps.play()


func _step_pitch() -> float:
	return 1.0


func _step_db() -> float:
	return -6.0


func _say(sound: String, db := 0.0, pitch := 1.0) -> void:
	_voice.stream = AudioSynth.cached(sound)
	_voice.volume_db = db
	_voice.pitch_scale = pitch
	_voice.play()


## The light where it stands, as the body's emission (like remote players).
func _update_light(delta: float, dim := 1.0) -> void:
	_light_t -= delta
	if _light_t > 0.0 or body == null:
		return
	_light_t = 0.4
	var cl := _cell()
	var bio := gen.biome_at(cl.x, cl.y)
	var lv := gen.light_level_near(global_position + Vector3.UP * 1.2, 4)
	var tint: Color = WorldGen.BOUNCE_TINT[bio].lerp(Color.WHITE, 0.5)
	var c: Color = tint * clampf(lv * 0.4, 0.05, 1.1) + WorldGen.AMBIENT[bio] * 2.0
	body.set_env_light(c * dim)


## You can see it: on screen (within `cone` degrees of where you look) and
## nothing in the way.
func _seen(max_dist := 40.0, cone := 34.0, h := 1.4) -> bool:
	var cam := player.camera
	var target := global_position + Vector3.UP * h
	var to := target - cam.global_position
	var d := to.length()
	if d > max_dist or (-cam.global_basis.z).dot(to / maxf(d, 0.001)) < cos(deg_to_rad(cone)):
		return false
	return _clear(cam.global_position, target)


func _clear(a: Vector3, b: Vector3) -> bool:
	var q := PhysicsRayQueryParameters3D.create(a, b)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _lit_by_flashlight(h := 1.0) -> bool:
	if not player.flashlight_on:
		return false
	var rig := player.flash_rig
	var target := global_position + Vector3.UP * h
	var to := target - rig.global_position
	var dist := to.length()
	if dist > player.flashlight.spot_range * 0.9:
		return false
	if (-rig.global_basis.z).dot(to / dist) < cos(deg_to_rad(player.flashlight.spot_angle * 0.8)):
		return false
	return _clear(rig.global_position, target)


func _dist() -> float:
	var d := player.global_position - global_position
	return Vector2(d.x, d.z).length()


## A cell `lo`..`hi` metres from you, reachable from nowhere in particular,
## out of your view; prefers the darker ones when `dark`.
func _spawn_cell(lo: float, hi: float, dark := false) -> Vector2i:
	var p := player.global_position
	var eye := player.camera.global_position
	var fwd := -player.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var c := gen.cell_of(p)
	var r := ceili(hi / WorldGen.CELL)
	var picks := []
	for _try in 80:
		var cc := c + Vector2i(_rng.randi_range(-r, r), _rng.randi_range(-r, r))
		var at := EntityNav.center(cc)
		var to := at - p
		to.y = 0.0
		var d := to.length()
		if d < lo or d > hi or not nav.cell_ok(cc):
			continue
		if fwd.dot(to / d) > cos(deg_to_rad(65.0)) and not _blocked(eye, at):
			continue
		if dark and gen.light_level_near(at + Vector3.UP * 1.2) > 0.35:
			continue
		picks.append(cc)
		if picks.size() >= 6:
			break
	if picks.is_empty():
		return Vector2i(1 << 30, 0)
	return picks[_rng.randi() % picks.size()]


func _blocked(eye: Vector3, at: Vector3) -> bool:
	for h in [0.6, 1.6]:
		if _clear(eye, at + Vector3.UP * h):
			return false
	return true


## Somewhere to walk to `lo`..`hi` cells away (further from you when `away`).
func _wander(lo: int, hi: int, away := false) -> bool:
	var here := _cell()
	var f := nav.flood(here, hi + 1, 600)
	var best := Vector2i.ZERO
	var best_s := -INF
	var pc := gen.cell_of(player.global_position)
	for c in f:
		var n: int = f[c][1]
		if n < lo or n > hi:
			continue
		var s := _rng.randf()
		if away:
			s += float((c - pc).length_squared()) * 0.05
		if s > best_s:
			best_s = s
			best = c
	if best_s == -INF:
		return false
	_path = EntityNav.path_to(f, best)
	return not _path.is_empty()


## Camera shake: a quick random jolt that dies away.
func _shake(cam: Camera3D, strength: float, time: float) -> void:
	var tw := cam.create_tween()
	tw.tween_method(func(k: float) -> void:
		cam.h_offset = randf_range(-1.0, 1.0) * strength * k
		cam.v_offset = randf_range(-1.0, 1.0) * strength * k, 1.0, 0.0, time)
