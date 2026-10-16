class_name Ambience
extends Node3D
## Drives all world audio: the omnipresent fluorescent hum (louder under
## working lights), room tone, Poolroom water, buzzing faulty tubes in sync
## with their visual flicker, footsteps, and rare distant noises.

const REVERB := [
	{"room": 0.45, "damp": 0.85, "wet": 0.12},   # carpet and ceiling tiles soak up sound
	{"room": 0.9, "damp": 0.55, "wet": 0.32},    # tiles echo, but a bright tail rang metallic
	{"room": 0.85, "damp": 0.45, "wet": 0.38},
	{"room": 0.6, "damp": 0.6, "wet": 0.3},
	{"room": 0.75, "damp": 0.3, "wet": 0.42},
]

var gen: WorldGen
var player: Player
var enabled := false
## Outdoors (the Field): Backrooms loops and distant noises go silent and the
## reverb dries up; footsteps still play.
var outdoor := false
## Multiplier on the fluorescent hum (The Lining makes it fade out near it).
var hum_duck := 1.0
var hum_duck_figure := 1.0

var _hum: AudioStreamPlayer
var _drone: AudioStreamPlayer
var _water: AudioStreamPlayer
var _buzz: AudioStreamPlayer3D
var _steps: AudioStreamPlayer
var _click: AudioStreamPlayer
var _distant: AudioStreamPlayer3D
var _step_streams := []
var _distant_streams := []
var _buzz_seed := 0.0
var _scan_t := 0.0
var _distant_t := 30.0
var _hum_level := 0.0
var _water_level := 0.0
var _biome := 0
var _rng := RandomNumberGenerator.new()
var _ready_streams := false
var _task := -1
var _generated := {}


func _ready() -> void:
	_rng.randomize()
	_hum = _player2d("Ambience")
	_drone = _player2d("Ambience")
	_water = _player2d("Ambience")
	_steps = _player2d("World")
	_click = _player2d("World")
	_buzz = AudioStreamPlayer3D.new()
	_buzz.bus = "World"
	_buzz.unit_size = 2.0
	_buzz.max_distance = 14.0
	add_child(_buzz)
	_distant = AudioStreamPlayer3D.new()
	_distant.bus = "World"
	_distant.unit_size = 14.0
	_distant.max_distance = 80.0
	_distant.attenuation_filter_cutoff_hz = 1200.0
	add_child(_distant)
	# Synthesis takes a moment; do it off the main thread.
	_task = WorkerThreadPool.add_task(_generate)


func _player2d(bus: String) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	add_child(p)
	return p


func _generate() -> void:
	var g := {}
	g.hum = AudioSynth.hum()
	g.drone = AudioSynth.drone()
	g.water = AudioSynth.water_loop()
	g.buzz = AudioSynth.buzz()
	g.click = AudioSynth.click()
	# Shared by the doors, the Field and the Poolroom drips; made here, off the
	# main thread, so they never cause a hitch later.
	for fn in ["draught", "hum", "wind", "drip", "paper", "exhale"]:
		AudioSynth.cached(fn)
	var steps := []
	for surf in 5:
		var vs := []
		for v in 4:
			vs.append(AudioSynth.footstep(surf, v))
		steps.append(vs)
	g.steps = steps
	var d := []
	for k in 4:
		d.append(AudioSynth.distant(k))
	g.distant = d
	_generated = g


func _finish_generation() -> void:
	WorkerThreadPool.wait_for_task_completion(_task)
	_task = -1
	var g := _generated
	_hum.stream = g.hum
	_drone.stream = g.drone
	_water.stream = g.water
	_buzz.stream = g.buzz
	_click.stream = g.click
	_step_streams = g.steps
	_distant_streams = g.distant
	for p in [_hum, _drone, _water]:
		p.volume_db = -80.0
		p.play()
	_buzz.volume_db = -80.0
	_buzz.play()
	_ready_streams = true


func is_ready() -> bool:
	return _ready_streams


func attach(p_gen: WorldGen, p_player: Player) -> void:
	gen = p_gen
	if player != p_player:
		player = p_player
		player.footstep.connect(_on_footstep)
		player.flashlight_toggled.connect(func(_on: bool) -> void: play_click())


func play_click() -> void:
	if _ready_streams:
		_click.pitch_scale = _rng.randf_range(0.95, 1.05)
		_click.play()


func _on_footstep(surface: int, strength: float) -> void:
	if not _ready_streams or not enabled:
		return
	var list: Array = _step_streams[surface]
	_steps.stream = list[_rng.randi() % list.size()]
	_steps.pitch_scale = _rng.randf_range(0.9, 1.1)
	_steps.volume_db = linear_to_db(clampf(strength, 0.05, 1.5)) - 6.0
	_steps.play()


## A random footstep sound for a surface (other players' steps).
func step_stream(surface: int) -> AudioStream:
	if not _ready_streams:
		return null
	var list: Array = _step_streams[surface]
	return list[_rng.randi() % list.size()]


## When >= 0, the world clock is pinned to this (recording at a fixed frame
## rate, where real time runs at a different speed from game time).
static var fixed_clock := -1.0


static func world_time() -> float:
	if fixed_clock >= 0.0:
		return fixed_clock
	return fmod(Time.get_ticks_msec() / 1000.0, 3600.0)


func _process(delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		_finish_generation()
	if not _ready_streams or gen == null or player == null:
		return
	var p := player.global_position
	_scan_t -= delta
	if _scan_t <= 0.0:
		_scan_t = 0.4
		var c := gen.cell_of(p)
		_biome = gen.biome_at(c.x, c.y)
		_hum_level = clampf(gen.light_level_near(p + Vector3(0, 1.5, 0)) * 0.55, 0.0, 1.0)
		_water_level = 0.0
		if _biome == WorldGen.POOL:
			_water_level = 1.0 if player.in_water() else 0.55
		var f := gen.nearest_flicker(p, 4)
		if f.is_empty():
			_buzz_seed = 0.0
		else:
			_buzz.global_position = f[0]
			_buzz_seed = f[1]
		_update_reverb()
	var k := 1.0 - exp(-2.5 * delta)
	var on := 1.0 if enabled and not outdoor else 0.0
	var hum_v := 0.0 if outdoor else (0.02 + _hum_level * 0.5 * on) * hum_duck * hum_duck_figure
	_hum.volume_db = lerpf(_hum.volume_db, linear_to_db(hum_v + 0.0001), k)
	_drone.volume_db = lerpf(_drone.volume_db, linear_to_db(0.22 * on + 0.0001), k)
	_water.volume_db = lerpf(_water.volume_db, linear_to_db(_water_level * 0.5 * on + 0.0001), k)
	var fl := WorldGen.flicker(_buzz_seed, world_time()) if _buzz_seed > 0.0 else 1.0
	var buzz_v := 0.0
	if _buzz_seed > 0.0 and enabled and not outdoor:
		buzz_v = 0.35 if fl > 0.0 and fl < 1.0 else (0.08 if fl >= 1.0 else 0.0)
	_buzz.volume_db = linear_to_db(buzz_v + 0.0001)
	if enabled and not outdoor:
		_distant_t -= delta
		if _distant_t <= 0.0:
			_distant_t = _rng.randf_range(35.0, 90.0)
			_play_distant()


func _play_distant() -> void:
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(18.0, 40.0)
	_distant.global_position = player.global_position + Vector3(cos(a) * d, 1.5, sin(a) * d)
	var kind := _rng.randi() % 4
	if _biome == WorldGen.POOL and kind == 1:
		kind = 0
	_distant.stream = _distant_streams[kind]
	_distant.pitch_scale = _rng.randf_range(0.85, 1.1)
	_distant.volume_db = -4.0
	_distant.play()


func _update_reverb() -> void:
	var idx := AudioServer.get_bus_index("World")
	if idx < 0:
		return
	var rev := AudioServer.get_bus_effect(idx, 0) as AudioEffectReverb
	if rev == null:
		return
	var r: Dictionary = {"room": 0.3, "damp": 0.9, "wet": 0.03} if outdoor else REVERB[_biome]
	rev.room_size = lerpf(rev.room_size, r.room, 0.35)
	rev.damping = lerpf(rev.damping, r.damp, 0.35)
	rev.wet = lerpf(rev.wet, r.wet, 0.35)


func set_muffled(muffled: bool) -> void:
	var idx := AudioServer.get_bus_index("Ambience")
	if idx >= 0 and AudioServer.get_bus_effect_count(idx) > 0:
		var lp := AudioServer.get_bus_effect(idx, 0) as AudioEffectLowPassFilter
		lp.cutoff_hz = 900.0 if muffled else 20000.0


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
