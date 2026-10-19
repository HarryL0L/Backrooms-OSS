class_name Radar
extends Node3D
## Hand-held radar for LAN games: held low in the left hand (hazmat glove and
## sleeve), it shows where the other players are relative to where you look,
## with their suit numbers. Raised and lowered with the radar button.

const RANGE := 28.0
const UP := Vector3(-0.15, -0.125, -0.32)
const DOWN := Vector3(-0.2, -0.5, -0.2)
const ROT_UP := Vector3(0.4, 0.3, 0.06)
const ROT_DOWN := Vector3(1.3, 1.1, 0.9)     # lying in the hand at the hip
const RAISE_TIME := 0.6

var shown := false
var _raise := 0.0
var _screen_mat: ShaderMaterial
var _body_mat: StandardMaterial3D
var _labels: Array[Label3D] = []
var _hand: Array[MeshInstance3D] = []
var _sweep := 0.0
var _sway := Vector2.ZERO
var _last_look := Vector2.INF
const SCREEN_R := 0.036
const SCREEN_C := Vector3(0, 0.022, 0.0151)


func _ready() -> void:
	var dev := Node3D.new()
	add_child(dev)
	# Body: a chunky handheld, tilted back towards the eye.
	_body_mat = StandardMaterial3D.new()
	_body_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_body_mat.albedo_color = Color(0.3, 0.31, 0.28)
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.09, 0.14, 0.028)
	body.mesh = bm
	body.material_override = _body_mat
	dev.add_child(body)
	var ant := MeshInstance3D.new()
	ant.mesh = HazmatModel.cyl(0.004, 0.003, 0.07, 8)
	ant.material_override = _body_mat
	ant.position = Vector3(0.03, 0.1, -0.004)
	dev.add_child(ant)
	var tip := MeshInstance3D.new()
	var ts := SphereMesh.new()
	ts.radius = 0.0055
	ts.height = 0.011
	tip.mesh = ts
	var tm := StandardMaterial3D.new()
	tm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	tm.albedo_color = Color(1.0, 0.25, 0.15)
	tip.material_override = tm
	tip.position = Vector3(0.03, 0.135, -0.004)
	dev.add_child(tip)
	var screen := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(SCREEN_R * 2.3, SCREEN_R * 2.3)
	screen.mesh = q
	_screen_mat = ShaderMaterial.new()
	_screen_mat.shader = preload("res://shaders/radar_screen.gdshader")
	screen.material_override = _screen_mat
	screen.position = SCREEN_C
	dev.add_child(screen)
	for i in 4:
		var l := Label3D.new()
		l.pixel_size = 0.00032
		l.font_size = 36
		l.outline_size = 8
		l.modulate = Color(1.0, 0.9, 0.5)
		l.outline_modulate = Color(0, 0, 0, 0.8)
		l.shaded = false
		l.fixed_size = false
		l.visible = false
		dev.add_child(l)
		_labels.append(l)
	# Glove gripping the left side (palm behind, thumb over the front), the
	# sleeve running down and out of view.
	var glove := MeshInstance3D.new()
	glove.mesh = HazmatModel.ellipsoid(Vector3(0.022, 0.048, 0.03), 14, 8)
	glove.material_override = HazmatModel._mat("rubber")
	glove.position = Vector3(-0.05, -0.035, -0.006)
	dev.add_child(glove)
	var fingers := MeshInstance3D.new()
	fingers.mesh = HazmatModel.ellipsoid(Vector3(0.009, 0.03, 0.009), 10, 6)
	fingers.material_override = HazmatModel._mat("rubber")
	fingers.position = Vector3(-0.04, -0.03, 0.018)
	fingers.rotation = Vector3(0, 0, -0.6)
	dev.add_child(fingers)
	var sleeve := MeshInstance3D.new()
	sleeve.mesh = HazmatModel.cyl(0.05, 0.034, 0.26, 14)
	sleeve.material_override = HazmatModel._mat("suit")
	sleeve.position = Vector3(-0.1, -0.16, 0.02)
	sleeve.rotation = Vector3(-0.35, 0, -0.42)
	dev.add_child(sleeve)
	for mi in [glove, fingers, sleeve]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_hand.append(mi)
	for mi in [body, ant, tip, screen]:
		(mi as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	rotation = ROT_DOWN
	scale = Vector3.ONE * 0.85
	position = DOWN
	visible = false


static func warm_materials() -> Array[Material]:
	var out: Array[Material] = []
	var sm := ShaderMaterial.new()
	sm.shader = preload("res://shaders/radar_screen.gdshader")
	out.append(sm)
	return out


## Pick-up: the hand brings it up from the hip in an arc, turning it to face
## you and settling with a small overshoot; putting it away runs backwards.
## While held it lags a little behind turns and bobs with your steps.
func _pose(delta: float, me: Player) -> void:
	var k := _raise
	# Ease out with overshoot (back), position slightly ahead of rotation.
	var c := 1.6
	var e := 1.0 + (c + 1.0) * pow(k - 1.0, 3.0) + c * pow(k - 1.0, 2.0)
	var er := smoothstep(0.0, 1.0, clampf(k * 1.15 - 0.1, 0.0, 1.0))
	var arc := Vector3(-0.06, 0.0, 0.05) * sin(k * PI)   # swings in from the side
	var look := Vector2(me.yaw, me.pitch)
	if _last_look.is_finite():
		var d := Vector2(angle_difference(_last_look.x, look.x), look.y - _last_look.y)
		_sway = (_sway + d * 0.6).limit_length(0.12)
	_last_look = look
	_sway = _sway.lerp(Vector2.ZERO, 1.0 - exp(-7.0 * delta))
	var hs := Vector2(me.velocity.x, me.velocity.z).length()
	var bob := minf(hs / Player.WALK, 1.4) * 0.006
	var ph := me._step_phase
	var held := Vector3(_sway.x * 0.25 + sin(ph) * bob, -_sway.y * 0.2 - absf(cos(ph)) * bob, 0.0)
	position = DOWN.lerp(UP, e) + arc + held * k
	rotation = ROT_DOWN.lerp(ROT_UP, er) + Vector3(_sway.y * 0.6, _sway.x * 0.8, -_sway.x * 0.5) * k


## others: Array of [world position, suit number, note]. The note marks
## someone on another floor ("▲1": a faint blip at their spot) or somewhere
## else entirely ("FIELD": no blip, a line along the top). me: the local player.
func update(delta: float, me: Player, others: Array, light: float) -> void:
	_raise = move_toward(_raise, 1.0 if shown else 0.0, delta / RAISE_TIME)
	visible = _raise > 0.0
	if not visible:
		_last_look = Vector2.INF
		return
	_pose(delta, me)
	_sweep = fmod(_sweep + delta * 2.4, TAU)
	_screen_mat.set_shader_parameter("sweep", _sweep)
	# The world is self-lit: match the device and hand to where you stand.
	var lv := clampf(light, 0.3, 1.1)
	_body_mat.albedo_color = Color(0.3, 0.31, 0.28) * lv
	for mi in _hand:
		UniqueParams.set_param(mi, &"env_light", Color(1.0, 0.97, 0.9) * lv * 0.9)
	var inv := me.global_basis.inverse()
	var blips: Array[Vector4] = []
	for i in 4:
		var l := _labels[i]
		if i >= others.size():
			blips.append(Vector4.ZERO)
			l.visible = false
			continue
		var note: String = others[i][2] if (others[i] as Array).size() > 2 else ""
		var at: Vector3 = others[i][0]
		l.visible = true
		if not at.is_finite():
			blips.append(Vector4.ZERO)
			l.text = "%02d %s" % [int(others[i][1]), note]
			l.position = SCREEN_C + Vector3(-SCREEN_R * 0.55, SCREEN_R * (0.75 - 0.3 * i), 0.001)
			continue
		var rel: Vector3 = inv * (at - me.global_position)
		var p := Vector2(rel.x, -rel.z) / RANGE
		var rim := p.length() > 0.9
		if rim:
			p = p.normalized() * 0.9
		var strength := 0.55 if rim else 1.0
		if note != "":
			strength *= 0.4                   # another floor
		blips.append(Vector4(p.x, p.y, strength, 1.0 if rim else 0.0))
		l.text = "%02d%s" % [int(others[i][1]), note]
		l.position = SCREEN_C + Vector3(p.x * SCREEN_R + 0.009, p.y * SCREEN_R + 0.006, 0.001)
	_screen_mat.set_shader_parameter("blips", blips)
