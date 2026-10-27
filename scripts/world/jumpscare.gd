class_name Jumpscare
extends Node
## The moment something gets you. You're turned to face it and it comes
## the last metre at your face, arms up (optionally two pale eyes in the head);
## the lights strobe on it, the screen shakes and tears with static, a
## white flash, its scream right in your ears over a deep hit. Then (when
## it caught you) a hard cut to black and silence, and the ringing. Off
## with Settings > Jumpscares (then just the old fade).

var player: Player
var hud: HUD

var _voice: AudioStreamPlayer
var _hit: AudioStreamPlayer
var _ring: AudioStreamPlayer
var _eye_mat: StandardMaterial3D


func _ready() -> void:
	_voice = _player("World")
	_hit = _player("Master")
	_ring = _player("Master")
	_eye_mat = StandardMaterial3D.new()
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_eye_mat.albedo_color = Color(1.0, 0.96, 0.88)


func _player(bus: String) -> AudioStreamPlayer:
	var a := AudioStreamPlayer.new()
	a.bus = bus
	add_child(a)
	return a


static func enabled() -> bool:
	return bool(Settings.get_value("gameplay/jumpscares"))


## Plays it with walker `w`. opts: sound (Sfx name), from / to (metres from
## your eyes to its head), time (s), cut (to black at the end), eyes.
func run(w: Walker, opts: Dictionary) -> void:
	var cam := player.camera
	var body := w.body
	var fov0 := cam.fov
	var from_d: float = opts.get("from", 1.6)
	var to_d: float = opts.get("to", 0.42)
	var time: float = opts.get("time", 0.8)
	var cut: bool = opts.get("cut", true)
	# Turned round to face it (straight ahead if it's on top of you).
	var to := w.global_position - cam.global_position
	to.y = 0.0
	if to.length() < 0.2:
		to = -cam.global_basis.z
		to.y = 0.0
	var dir := to.normalized()
	player.yaw = atan2(-dir.x, -dir.z)
	player.pitch = 0.0
	player._apply_rotation()
	var eye := cam.global_position
	w.visible = true
	w.rotation = Vector3(-float(opts.get("rear", 0.0)), atan2(-dir.x, -dir.z), 0.0)   # faces +Z: you; rearing up
	body.update(0.0)
	var eyes: Array[MeshInstance3D] = []
	if opts.get("eyes", false):
		for i in 2:
			var e := MeshInstance3D.new()
			var sm := SphereMesh.new()
			sm.radius = 0.02
			sm.height = 0.028
			sm.radial_segments = 8
			sm.rings = 4
			e.mesh = sm
			e.material_override = _eye_mat
			e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			w.add_child(e)
			eyes.append(e)
	_voice.stream = Sfx.get_stream(opts.get("sound", "tall_roar"))
	_voice.volume_db = 6.0
	_voice.pitch_scale = randf_range(0.92, 1.02)
	_voice.play()
	_hit.stream = AudioSynth.cached("impact")
	_hit.volume_db = 2.0
	_hit.play()
	var right := dir.cross(Vector3.UP).normalized()
	var t := 0.0
	while t < time:
		var dt := get_process_delta_time()
		t += dt
		var k := clampf(t / time, 0.0, 1.0)
		var rush := 1.0 - pow(1.0 - minf(k * 1.6, 1.0), 3.0)     # rushes in, then holds there
		var d := lerpf(from_d, to_d, rush)
		body.reach = rush
		body.update(dt)
		# Its head held right in the middle of your view, whatever the pose does.
		var want := eye + dir * d + Vector3.UP * 0.03 * sin(t * 40.0)
		w.global_position += want - body.head_position()
		# The lights strobe on it.
		var lit := 2.4 if fmod(t, 0.14) < 0.05 else 0.25
		body.set_env_light(Color(lit, lit * 0.97, lit * 0.92))
		var h := body.head_position()
		for i in eyes.size():
			eyes[i].global_position = h - dir * 0.15 * body.scale.y + right * (0.045 if i == 0 else -0.045) - Vector3.UP * 0.02
		var shake := 0.06 * (1.0 - 0.5 * k)
		cam.h_offset = randf_range(-1.0, 1.0) * shake
		cam.v_offset = randf_range(-1.0, 1.0) * shake
		cam.fov = lerpf(fov0, fov0 - 18.0, rush)
		hud.scare(maxf(0.0, 1.0 - t / 0.1) * 0.9, 0.3 + 0.6 * k)
		await get_tree().process_frame
	if cut:
		# Black, silence, the ringing.
		hud.set_fade(1.0)
		hud.scare(0.0, 0.0)
		_voice.stop()
		_ring.stream = AudioSynth.cached("ring")
		_ring.volume_db = -10.0
		_ring.play()
	else:
		# A last white flash, fading off.
		var f := 0.85
		while f > 0.0:
			f -= get_process_delta_time() * 2.5
			hud.scare(maxf(f, 0.0), maxf(f, 0.0) * 0.6)
			await get_tree().process_frame
		hud.scare(0.0, 0.0)
	for e in eyes:
		e.queue_free()
	body.reach = 0.0
	cam.fov = fov0
	cam.h_offset = 0.0
	cam.v_offset = 0.0
