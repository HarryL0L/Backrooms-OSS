class_name PoolVoices
extends Node3D
## The Poolrooms remember being busy. Somewhere off through the tiled
## halls there are people: voices, talk, children shrieking and laughing,
## far away but clear, with a little of the tiles' echo. Two of these murmurs drift
## around you at a distance, each fading up somewhere, carrying on for a
## while and fading out, then turning up somewhere else. You never find
## anyone. Recordings: CC0, see assets/audio/pool/LICENSE.md.

const CLIPS := [
	"res://assets/audio/pool/leisure.ogg",
	"res://assets/audio/pool/far.ogg",
]
const FADE_IN := 5.0
const FADE_OUT := 6.0

var ambience: Ambience
var _streams: Array[AudioStream] = []
var _voices: Array[AudioStreamPlayer3D] = []
var _state: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	for path in CLIPS:
		var st := load(path) as AudioStreamOggVorbis
		st.loop = true
		_streams.append(st)
	for i in 2:
		var v := AudioStreamPlayer3D.new()
		# Not the World bus: its tiled-hall reverb washed the voices out.
		v.bus = "Ambience"
		v.unit_size = 16.0
		v.max_distance = 70.0
		v.attenuation_filter_cutoff_hz = 9000.0
		v.volume_db = -60.0
		add_child(v)
		_voices.append(v)
		# Staggered, so they don't come and go together.
		_state.append({"t": 0.0, "life": 0.0, "gap": _rng.randf_range(1.0, 4.0) + i * 7.0, "db": -8.0})


func _process(delta: float) -> void:
	var p := ambience.player
	var here: bool = ambience.enabled and not ambience.outdoor and p != null and ambience._biome == WorldGen.POOL
	for i in _voices.size():
		var v := _voices[i]
		var s := _state[i]
		if not here:
			# Gone quiet the moment you leave.
			if v.playing:
				v.volume_db = move_toward(v.volume_db, -60.0, delta * 30.0)
				if v.volume_db <= -59.0:
					v.stop()
			continue
		if not v.playing:
			s.gap -= delta
			if s.gap <= 0.0:
				_start(v, s, p.global_position)
			continue
		s.t += delta
		var k := clampf(s.t / FADE_IN, 0.0, 1.0) * clampf((s.life - s.t) / FADE_OUT, 0.0, 1.0)
		v.volume_db = lerpf(-60.0, s.db, sqrt(k))
		if s.t >= s.life or v.global_position.distance_to(p.global_position) > 60.0:
			v.stop()
			s.gap = _rng.randf_range(4.0, 20.0)


func _start(v: AudioStreamPlayer3D, s: Dictionary, around: Vector3) -> void:
	var a := _rng.randf() * TAU
	var d := _rng.randf_range(14.0, 30.0)
	v.global_position = around + Vector3(cos(a) * d, 1.4, sin(a) * d)
	var st := _streams[_rng.randi() % _streams.size()]
	v.stream = st
	v.pitch_scale = _rng.randf_range(0.94, 1.02)
	v.volume_db = -60.0
	v.play(_rng.randf() * maxf(st.get_length() - 5.0, 0.0))
	s.t = 0.0
	s.life = _rng.randf_range(18.0, 45.0)
	s.db = _rng.randf_range(-11.0, -5.0)
