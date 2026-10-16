class_name RemotePlayer
extends Node3D
## Another player, as you see them: the hazmat suit model following their
## network updates (buffered ~100 ms and interpolated so it moves smoothly),
## walking/running with the same gait as the first-person view, crouching,
## their chest torch shining when their flashlight is on, and their
## footsteps in 3D.

const DELAY := 0.1

var gen: WorldGen
var ambience: Ambience
var model: HazmatModel
var number := 0

var _buf: Array = []                  # [time, state]
var _torch: SpotLight3D
var _shadow: MeshInstance3D
var _shadow_mat: StandardMaterial3D
var _steps: AudioStreamPlayer3D
var _phase := 0.0
var _speed := 0.0
var _run := 0.0
var _crouch := 0.0
var _air := 0.0
var _light_t := 0.0
var _rng := RandomNumberGenerator.new()
var _last_pos := Vector3.INF
var in_field := false
var in_mall := false


func _ready() -> void:
	_rng.randomize()
	model = HazmatModel.new()
	model.tag = "%02d" % number
	add_child(model)
	_torch = SpotLight3D.new()
	_torch.spot_range = 18.0
	_torch.spot_angle = 26.0
	_torch.light_energy = 2.2
	_torch.light_color = Color(1.0, 0.94, 0.82)
	_torch.shadow_enabled = false
	_torch.visible = false
	add_child(_torch)
	# Soft contact shadow so they stand on the floor (the world has no real
	# shadows from its baked light).
	_shadow = MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = Vector2(0.9, 0.9)
	_shadow.mesh = q
	var sm := StandardMaterial3D.new()
	sm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.albedo_color = Color(0, 0, 0, 0.55)
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	sm.albedo_texture = gt
	_shadow.material_override = sm
	_shadow_mat = sm
	_shadow.position.y = 0.012
	_shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_shadow)
	_steps = AudioStreamPlayer3D.new()
	_steps.bus = "World"
	_steps.unit_size = 2.5
	_steps.max_distance = 30.0
	add_child(_steps)
	visible = false


func set_number(n: int) -> void:
	number = n
	if model:
		model.set_tag("%02d" % n)


func push_state(s: Dictionary) -> void:
	_buf.append([Time.get_ticks_msec() / 1000.0, s])
	if _buf.size() > 30:
		_buf.pop_front()


func _process(delta: float) -> void:
	if _buf.is_empty():
		return
	var t := Time.get_ticks_msec() / 1000.0 - DELAY
	# Find the two states around t (or the newest one).
	var a: Array = _buf[0]
	var b: Array = _buf[0]
	for i in _buf.size():
		if float(_buf[i][0]) <= t:
			a = _buf[i]
			b = _buf[mini(i + 1, _buf.size() - 1)]
	while _buf.size() > 2 and float(_buf[1][0]) < t:
		_buf.pop_front()
	var sa: Dictionary = a[1]
	var sb: Dictionary = b[1]
	var span: float = maxf(float(b[0]) - float(a[0]), 0.001)
	var k := clampf((t - float(a[0])) / span, 0.0, 1.0)
	var pa: Vector3 = sa.p
	var pb: Vector3 = sb.p
	var pos := pa.lerp(pb, k)
	if _last_pos.is_finite() and pos.distance_to(_last_pos) > 6.0:
		_last_pos = pos                       # teleported: no streak
	global_position = pos
	var yaw := lerp_angle(float(sa.y), float(sb.y), k)
	rotation = Vector3(0, yaw + PI, 0)        # the model faces +Z, players look -Z
	var pitch := lerpf(float(sa.x), float(sb.x), k)
	in_field = bool(sb.get("fl", false))
	in_mall = bool(sb.get("ml", false))
	visible = true
	# Gait from their actual movement.
	var vel: Vector3 = sb.get("v", Vector3.ZERO)
	var hs := Vector2(vel.x, vel.z).length()
	_speed = lerpf(_speed, hs, 1.0 - exp(-8.0 * delta))
	_run = lerpf(_run, smoothstep(Player.WALK + 0.3, Player.SPRINT - 0.3, _speed), 1.0 - exp(-4.0 * delta))
	# Crouching and jumping are poses (legs bend, boots stay on the floor).
	_crouch = lerpf(_crouch, 1.0 if sb.get("c", false) else 0.0, 1.0 - exp(-10.0 * delta))
	var airborne := not bool(sb.get("g", true)) and absf(vel.y) > 0.4
	_air = lerpf(_air, 1.0 if airborne else 0.0, 1.0 - exp(-(12.0 if airborne else 18.0) * delta))
	model.crouch = _crouch
	model.air = _air
	var step_len := clampf(0.45 + 0.27 * _speed, 0.55, 1.8)
	var prev := _phase
	_phase += _speed * delta / step_len * PI
	if _speed > 0.3 and not airborne and floori(prev / PI) != floori(_phase / PI):
		_footstep()
	var amount := clampf(_speed / Player.WALK, 0.0, 1.0)
	if amount > 0.02:
		model.pose_walk(_phase, amount, _run)
	else:
		model.pose_idle(Time.get_ticks_msec() / 1000.0)
	_place_shadow(pos)
	# Torch beam from the chest, along where they look.
	var on: bool = sb.get("f", false) and Settings.light_nodes()
	_torch.visible = on
	if on:
		_torch.position = Vector3(0, 1.28 - 0.45 * _crouch, 0)
		_torch.global_rotation = Vector3(pitch, yaw, 0)
	# Match the light where they stand (the world's light is baked).
	_light_t -= delta
	if _light_t <= 0.0 and gen:
		_light_t = 0.3
		var c := Color.BLACK
		if not in_field and not in_mall:
			c = Color(1.0, 0.97, 0.9) * clampf(gen.light_level_near(pos + Vector3.UP * 1.2) * 0.35, 0.04, 1.1)
		model.set_env_light(c)


## The contact shadow stays on the floor under them (it doesn't fly up when
## they jump) and fades out the higher they are.
func _place_shadow(pos: Vector3) -> void:
	var q := PhysicsRayQueryParameters3D.create(pos + Vector3.UP * 0.4, pos + Vector3.DOWN * 4.0)
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit.is_empty():
		_shadow.visible = false
		return
	var h := pos.y - float(hit.position.y)
	_shadow.visible = h < 3.0
	_shadow.global_position = Vector3(pos.x, float(hit.position.y) + 0.012, pos.z)
	var k := clampf(1.0 - h / 3.0, 0.0, 1.0)
	_shadow_mat.albedo_color.a = 0.55 * k
	_shadow.scale = Vector3.ONE * lerpf(1.3, 1.0, k)


func _footstep() -> void:
	if ambience == null or gen == null:
		return
	var surf := Player.SURF_GRASS if in_field else (Player.SURF_TILE if in_mall else Player.surface_for(gen, global_position))
	var st := ambience.step_stream(surf)
	if st == null:
		return
	_steps.stream = st
	_steps.pitch_scale = _rng.randf_range(0.9, 1.1)
	_steps.volume_db = linear_to_db(clampf(_speed / Player.SPRINT, 0.35, 1.0)) - 4.0
	_steps.play()
