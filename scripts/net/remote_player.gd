class_name RemotePlayer
extends Node3D
## Another player, as you see them: the hazmat suit model following their
## network updates (buffered ~100 ms and interpolated so it moves smoothly),
## walking/running with the same gait as the first-person view, crouching,
## their chest torch shining when their flashlight is on, sitting when
## they're in a car, and their footsteps in 3D.
##
## States are placed on the sender's clock (so Wi-Fi bunching doesn't make
## them stutter) and shown 150 ms late, between the two around that time.

const DELAY := 0.15
## Short airborne blips (the top of a jump, a stair step) keep the jump pose.
const AIR_GRACE := 0.12

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
var _clock_off := INF       # our clock minus theirs (smallest seen), seconds
var _air_t := 0.0
var in_field := false
var in_mall := false
var side_seed := 0
var seated := false
## The floor they're on: someone a floor up or down stands at the same x, z
## but isn't here.
var floor_index := 0
## Where the player looking at them is (set_viewer).
var viewer_floor := 0
var viewer_field := false
var viewer_mall := false
var viewer_side := 0
## The side level they're in ("" none; older games never send one), the
## one the viewer is in, and that level (for its light and floors).
var in_level := ""
var viewer_level := ""
var level: SideLevel = null


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
	var now := Time.get_ticks_msec() / 1000.0
	var t := now
	if s.has("t"):
		# Their send time on our clock: the offset is the smallest gap seen
		# (the least-delayed packet), so bunched packets keep their spacing.
		var sent := float(s.t) / 1000.0
		_clock_off = minf(_clock_off, now - sent)
		t = sent + _clock_off
	_buf.append([t, s])
	if _buf.size() > 30:
		_buf.pop_front()


func has_state() -> bool:
	return not _buf.is_empty()


## Where the player looking at them is.
func set_viewer(p_floor: int, p_field: bool, p_mall: bool, p_side: int, p_level := "") -> void:
	viewer_floor = p_floor
	viewer_field = p_field
	viewer_mall = p_mall
	viewer_side = p_side
	viewer_level = p_level


## In the Field, the Mall or a side level rather than the Backrooms.
func away() -> bool:
	return in_field or in_mall or in_level != ""


func place_name() -> String:
	if in_level != "":
		# "Level 2.1 - The Crawlspace" -> "L2.1"
		return String(SideLevels.info(in_level).name).get_slice(" - ", 0).replace("Level ", "L").left(6)
	if in_field:
		return "FIELD"
	if in_mall:
		return "MALL"
	return "B%d" % -floor_index if floor_index < 0 else ("L%d" % floor_index if floor_index > 0 else "L0")


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
	# A floor change on the stairs moves them by a floor height: put the
	# earlier state into the new floor's frame instead of sliding between.
	var fa := int(sa.get("fr", 0))
	var fb := int(sb.get("fr", 0))
	if fa != fb:
		pa.y += (fa - fb) * WorldGen.FLOOR_H
	var pos := pa.lerp(pb, k)
	if pa.distance_to(pb) > 6.0 or bool(sa.get("fl", false)) != bool(sb.get("fl", false)) \
			or bool(sa.get("ml", false)) != bool(sb.get("ml", false)) or str(sa.get("sl", "")) != str(sb.get("sl", "")):
		pos = pb                              # teleported: no streak
	_last_pos = pos
	global_position = pos
	var yaw := lerp_angle(float(sa.y), float(sb.y), k)
	rotation = Vector3(0, yaw + PI, 0)        # the model faces +Z, players look -Z
	var pitch := lerpf(float(sa.x), float(sb.x), k)
	in_field = bool(sb.get("fl", false))
	in_mall = bool(sb.get("ml", false))
	side_seed = int(sb.get("sd", 0))
	floor_index = int(sb.get("fr", 0))
	seated = bool(sb.get("s", false))
	in_level = str(sb.get("sl", ""))
	# Only where you are: the same floor of the Backrooms, or the same Field,
	# Mall or side level (the one behind the same door).
	if in_level != "" or viewer_level != "":
		visible = in_level == viewer_level and side_seed == viewer_side
	elif in_field or in_mall or viewer_field or viewer_mall:
		visible = in_field == viewer_field and in_mall == viewer_mall and side_seed == viewer_side
	else:
		visible = floor_index == viewer_floor
	if not visible:
		return
	if seated:
		# In a car (or getting in or out of one): sitting, no steps.
		model.crouch = 0.0
		model.air = 0.0
		model.pose_sit()
		_speed = 0.0
		_shadow.visible = false
		_torch.visible = false
		return
	# Gait from their actual movement, backwards when they back up.
	var vel: Vector3 = sb.get("v", Vector3.ZERO)
	var hs := Vector2(vel.x, vel.z).length()
	var fwd := -Basis(Vector3.UP, yaw).z
	var dir := -1.0 if vel.dot(fwd) < -0.2 * hs else 1.0
	_speed = lerpf(_speed, hs, 1.0 - exp(-8.0 * delta))
	_run = lerpf(_run, smoothstep(Player.WALK + 0.3, Player.SPRINT - 0.3, _speed), 1.0 - exp(-4.0 * delta))
	# Crouching and jumping are poses (legs bend, boots stay on the floor).
	_crouch = lerpf(_crouch, 1.0 if sb.get("c", false) else 0.0, 1.0 - exp(-10.0 * delta))
	_air_t = 0.0 if bool(sb.get("g", true)) else _air_t + delta
	var airborne := _air_t > 0.05 and (absf(vel.y) > 0.4 or _air_t > AIR_GRACE)
	_air = lerpf(_air, 1.0 if airborne else 0.0, 1.0 - exp(-(12.0 if airborne else 18.0) * delta))
	model.crouch = _crouch
	model.air = _air
	var step_len := clampf(0.45 + 0.27 * _speed, 0.55, 1.8)
	var prev := _phase
	_phase += dir * _speed * delta / step_len * PI
	if _speed > 0.3 and not airborne and floori(prev / PI) != floori(_phase / PI) and is_visible_in_tree():
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
		var c: Color
		if in_level != "" and level:
			c = level.light_at(pos + Vector3.UP * 1.2)
		elif in_mall:
			c = Color(0.55, 0.53, 0.5)            # same as the mannequins there
		elif in_field:
			c = Color(0.32, 0.34, 0.38)           # sky light; the sun adds the rest
		else:
			# Lamps further out light big open halls too (the old 2-cell
			# search left people black in the middle of a lit room), and
			# never darker than the level's own ambient, plus a little so
			# you can always make out a fellow wanderer.
			var cl := gen.cell_of(pos)
			var bio := gen.biome_at(cl.x, cl.y)
			var lv := gen.light_level_near(pos + Vector3.UP * 1.2, 4)
			var floor_v := 0.09 if bio == WorldGen.DARK else 0.16
			var tint: Color = WorldGen.BOUNCE_TINT[bio].lerp(Color.WHITE, 0.5)
			c = tint * clampf(lv * 0.4, floor_v, 1.1) + WorldGen.AMBIENT[bio] * 2.0
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
	if in_level != "" and level:
		var p := global_position
		surf = Player.SURF_WATER if level.water_level_at(p) > p.y + 0.1 else level.surface_at(p)
	var st := ambience.step_stream(surf)
	if st == null:
		return
	_steps.stream = st
	_steps.pitch_scale = _rng.randf_range(0.9, 1.1)
	_steps.volume_db = linear_to_db(clampf(_speed / Player.SPRINT, 0.35, 1.0)) - 4.0
	_steps.play()
