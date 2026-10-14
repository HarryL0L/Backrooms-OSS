class_name LiningEntity
extends Node
## "The Lining": something behind the Lobby wallpaper. You only ever see a
## face pressing out through the paper (sometimes hands too), slowly
## breathing. It never attacks and never chases; it appears in dim spots at
## the edge of your view or behind you, moves closer whenever you look away,
## and smooths back into the wall soon after you look straight at it.
##
## Drawn entirely by the wallpaper shader (see shaders/wallpaper.gdshader):
## this node only decides where it is and how far it pushes out, through the
## lining_* global shader parameters.

const FORM_RATE := 0.45      # strength per second while pressing out
const SINK_RATE := 0.6       # ... while smoothing back out
const STARE_TIME := 1.5      # seconds of being watched before it smooths out

var gen: WorldGen
var player: Player
var ambience: Ambience
var odd_doors: OddDoors
## Off in the Field, while loading, or when disabled in Settings.
var allowed := false
## Tests/screenshots: hold the current pose (no behaviour).
var frozen := false

enum { IDLE, PRESENT }
var _state := IDLE
var _timer := 0.0
var _moves_left := 0
var _moves_done := 0
var _strength := 0.0
var _target := 0.0
var _seen_t := 0.0
var _unseen_t := 0.0
var _patience := 5.0          # how long it waits unseen before moving
var _hands := 0.0             # how far the hands show (0..1)
var _hands_target := 0.0
var _episode_origin := Vector3.ZERO
var _wall := {}               # pos, right, normal
var _creak: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()
var _shape_task := -1
var _shape: Image


func _ready() -> void:
	_rng.randomize()
	_timer = _rng.randf_range(90.0, 180.0)
	_creak = AudioStreamPlayer3D.new()
	_creak.bus = "World"
	_creak.unit_size = 3.0
	_creak.max_distance = 22.0
	add_child(_creak)
	# The height map takes a moment to compute: do it off the main thread.
	_shape_task = WorkerThreadPool.add_task(func() -> void: _shape = LiningShape.build())
	_set_globals()


func _exit_tree() -> void:
	if _shape_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_shape_task)


func _process(delta: float) -> void:
	if _shape_task >= 0 and WorkerThreadPool.is_task_completed(_shape_task):
		WorkerThreadPool.wait_for_task_completion(_shape_task)
		_shape_task = -1
		RenderingServer.global_shader_parameter_set("lining_tex", ImageTexture.create_from_image(_shape))
		_creak.stream = AudioSynth.cached("paper")
	var ready := _shape_task < 0 and gen != null and player != null
	var on: bool = ready and allowed and Settings.get_value("gameplay/entities")
	if not on:
		if _state == PRESENT:
			_end_episode()
		_target = 0.0
	elif not frozen:
		_think(delta)
	var rate := FORM_RATE if _target > _strength else SINK_RATE
	_strength = move_toward(_strength, _target, rate * delta)
	# Hands press out only once the face is there, and leave first.
	var ht := _hands_target if _strength > 0.7 and _target > 0.5 else 0.0
	_hands = move_toward(_hands, ht, (0.3 if ht > _hands else 0.9) * delta)
	_set_globals()
	if ambience:
		# The fluorescent hum fades out near it.
		var near := 0.0
		if not _wall.is_empty() and player:
			near = clampf(1.0 - player.global_position.distance_to(_wall.pos) / 12.0, 0.0, 1.0)
		ambience.hum_duck = 1.0 - 0.85 * _strength * near


func _think(delta: float) -> void:
	var in_lobby := _biome_at(player.global_position) == WorldGen.LOBBY
	match _state:
		IDLE:
			if in_lobby:
				_timer -= delta
			if _timer <= 0.0 and _strength <= 0.01:
				_moves_done = 0
				_episode_origin = player.global_position
				if _relocate(7.0, 13.0):
					_state = PRESENT
					_moves_left = _rng.randi_range(2, 4)
				else:
					_timer = 5.0
		PRESENT:
			if not in_lobby or player.global_position.distance_to(_episode_origin) > 35.0:
				_end_episode()
				return
			if _is_seen():
				_seen_t += delta
				_unseen_t = 0.0
				if _seen_t > STARE_TIME:
					_target = 0.0          # stared at long enough: it sinks back
			else:
				_unseen_t += delta
				_seen_t = 0.0
				var settled := absf(_strength - _target) < 0.02
				if _unseen_t > _patience and settled:
					if _moves_left > 0:
						# Closer every time you look away.
						var k := float(_moves_done) / 4.0
						if _relocate(lerpf(7.0, 2.6, k), lerpf(11.0, 4.5, k)):
							_moves_left -= 1
							_moves_done += 1
						_unseen_t = 0.0
					else:
						_end_episode()


func _end_episode() -> void:
	_state = IDLE
	_target = 0.0
	_timer = _rng.randf_range(45.0, 120.0)


## Moves it to a Lobby wall dmin..dmax metres away that is out of view (but
## in line of sight once you turn). It forms there from flat.
func _relocate(dmin: float, dmax: float) -> bool:
	var cand := _candidates(dmin, dmax)
	if cand.is_empty():
		# The maze hides most distant walls: widen the search before giving up.
		cand = _candidates(maxf(dmin * 0.5, 2.2), dmax * 1.4)
	if cand.is_empty():
		return false
	# Prefer dim spots: pick among the darker half of the candidates.
	cand.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.light < b.light)
	_wall = cand[_rng.randi() % maxi(1, (cand.size() + 1) / 2)]
	_strength = 0.0
	_target = 1.0
	_seen_t = 0.0
	_patience = _rng.randf_range(3.5, 7.0)
	# Sometimes the hands come too, more often the closer it has crept.
	_hands_target = 1.0 if _rng.randf() < 0.2 + 0.15 * _moves_done else 0.0
	if _creak.stream:
		_creak.global_position = _wall.pos + Vector3.UP * 1.5
		_creak.pitch_scale = _rng.randf_range(0.85, 1.1)
		_creak.play()
	return true


func _candidates(dmin: float, dmax: float) -> Array:
	var out := []
	var p := player.global_position
	var eye := p + Vector3.UP * 1.55
	var fwd := -player.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var c := gen.cell_of(p)
	var r := int(ceil(dmax / WorldGen.CELL)) + 1
	var space := player.get_world_3d().direct_space_state
	for gz in range(c.y - r, c.y + r + 1):
		for gx in range(c.x - r, c.x + r + 1):
			var b := gen.biome_at(gx, gz)
			if b != WorldGen.LOBBY or gen.is_solid(gx, gz, b):
				continue
			# The four walls of this cell, seen from inside it.
			var faces := [
				[gx, gz, true, gx - 1, gz, Vector3(1, 0, 0), Vector3(gx * WorldGen.CELL, 0, (gz + 0.5) * WorldGen.CELL)],
				[gx + 1, gz, true, gx + 1, gz, Vector3(-1, 0, 0), Vector3((gx + 1) * WorldGen.CELL, 0, (gz + 0.5) * WorldGen.CELL)],
				[gz, gx, false, gx, gz - 1, Vector3(0, 0, 1), Vector3((gx + 0.5) * WorldGen.CELL, 0, gz * WorldGen.CELL)],
				[gz + 1, gx, false, gx, gz + 1, Vector3(0, 0, -1), Vector3((gx + 0.5) * WorldGen.CELL, 0, (gz + 1) * WorldGen.CELL)],
			]
			for f in faces:
				var ob := gen.biome_at(f[3], f[4])
				var ba: int = ob if (f[5].x > 0.0 or f[5].z > 0.0) else b
				var bb: int = b if (f[5].x > 0.0 or f[5].z > 0.0) else ob
				if gen.edge_kind(f[0], f[1], f[2], ba, bb) != WorldGen.E_WALL:
					continue
				var n: Vector3 = f[5]
				var pos: Vector3 = f[6] + n * ChunkBuilder.T
				var d := Vector2(pos.x - p.x, pos.z - p.z).length()
				if d < dmin or d > dmax:
					continue
				# Out of view: well outside the centre of the screen.
				var to := (pos - p)
				to.y = 0.0
				if fwd.dot(to.normalized()) > cos(deg_to_rad(65.0)):
					continue
				if odd_doors and odd_doors.nearest(pos).distance_to(pos) < 1.6:
					continue
				# You must be able to see the spot once you turn around.
				var q := PhysicsRayQueryParameters3D.create(eye, pos + n * 0.08 + Vector3.UP * 1.5)
				q.exclude = [player.get_rid()]
				if not space.intersect_ray(q).is_empty():
					continue
				var light := gen.light_level_near(pos + n * 0.5 + Vector3.UP * 1.5)
				out.append({"pos": pos, "normal": n, "right": Vector3.UP.cross(n), "light": light})
	return out


func _is_seen() -> bool:
	if _wall.is_empty():
		return false
	var cam := player.camera
	var target: Vector3 = _wall.pos + Vector3.UP * 1.5 + _wall.normal * 0.05
	var to := target - cam.global_position
	if to.length() > 20.0 or (-cam.global_basis.z).dot(to.normalized()) < cos(deg_to_rad(38.0)):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, target)
	q.exclude = [player.get_rid()]
	return player.get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _biome_at(p: Vector3) -> int:
	var c := gen.cell_of(p)
	return gen.biome_at(c.x, c.y)


func _set_globals() -> void:
	var pos: Vector3 = _wall.get("pos", Vector3.ZERO)
	var right: Vector3 = _wall.get("right", Vector3.RIGHT)
	var n: Vector3 = _wall.get("normal", Vector3.BACK)
	RenderingServer.global_shader_parameter_set("lining_pos", Vector4(pos.x, pos.y, pos.z, _strength if not _wall.is_empty() else 0.0))
	RenderingServer.global_shader_parameter_set("lining_right", Vector4(right.x, right.y, right.z, _hands))
	RenderingServer.global_shader_parameter_set("lining_normal", Vector4(n.x, n.y, n.z, 0.0))


## For tests: place it on a given wall immediately at full strength.
func debug_show(pos: Vector3, normal: Vector3, hands := 1.0) -> void:
	_wall = {"pos": pos, "normal": normal, "right": Vector3.UP.cross(normal)}
	_strength = 1.0
	_target = 1.0
	_hands = hands
	_hands_target = hands
	_state = PRESENT
	_moves_left = 0
	_episode_origin = pos
	_set_globals()
