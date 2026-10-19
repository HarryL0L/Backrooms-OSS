class_name MallEscalator
extends Node3D
## A working escalator in the Dead Mall, from one floor up to the next.
## Its cladding is baked into the mall (tools/blender/mall_kit.py); here
## are the moving steps, the ramp you stand on and the side walls, and the
## carry: stand on it and it takes you up (walk against it and you can go
## down, slowly). Still running, after everything else stopped.
##
## Local space: +X is the way up, +Y up, Z across. The origin is the foot
## of the incline; a level run of FLAT at each end.

const RISE := 5.0
const RUN := RISE / tan(deg_to_rad(30.0))
const FLAT := 1.2
const WIDTH := 1.0
const SPEED := 0.5
const PITCH := 0.4           # step depth (horizontal)

var player: Player
var light := 0.9
var _steps: MultiMeshInstance3D
var _offset := 0.0
var _hum: AudioStreamPlayer3D


func _ready() -> void:
	process_physics_priority = -10        # before the player moves
	_build_steps()
	_build_collision()
	_hum = AudioStreamPlayer3D.new()
	_hum.stream = AudioSynth.cached("hum")
	_hum.bus = "World"
	_hum.pitch_scale = 0.55
	_hum.volume_db = -14.0
	_hum.unit_size = 3.0
	_hum.max_distance = 20.0
	_hum.position = Vector3(RUN * 0.5, RISE * 0.5 - 0.8, 0.0)
	add_child(_hum)
	_hum.play()


func _build_steps() -> void:
	var m := BoxMesh.new()
	m.size = Vector3(PITCH - 0.02, 0.24, WIDTH)
	m.material = MallLevel.lit_material("metal_bright", light)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = m
	mm.instance_count = ceili((RUN + 2.0 * FLAT) / PITCH)
	_steps = MultiMeshInstance3D.new()
	_steps.multimesh = mm
	_steps.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_steps)
	_place_steps()


## Height of the step line at u (along, from the foot of the incline).
static func line(u: float) -> float:
	return clampf(u, 0.0, RUN) / RUN * RISE


func _place_steps() -> void:
	var mm := _steps.multimesh
	var span := RUN + 2.0 * FLAT
	for i in mm.instance_count:
		var u := fposmod(i * PITCH + _offset, span) - FLAT
		# Each tread level; on the incline its front edge sits on the line.
		var h := line(u + PITCH * 0.5)
		mm.set_instance_transform(i, Transform3D(Basis(), Vector3(u + PITCH * 0.5, h - 0.12, 0.0)))


func _build_collision() -> void:
	var body := StaticBody3D.new()
	add_child(body)
	var ang := atan2(RISE, RUN)
	var ramp := CollisionShape3D.new()
	var rb := BoxShape3D.new()
	rb.size = Vector3(RUN / cos(ang) + 0.1, 0.3, WIDTH + 0.1)
	ramp.shape = rb
	# Its top face on the step line.
	ramp.transform = Transform3D(Basis(Vector3.BACK, ang), Vector3(RUN * 0.5, RISE * 0.5, 0.0) + Vector3(sin(ang), -cos(ang), 0.0) * 0.15)
	body.add_child(ramp)
	for zs in [-1.0, 1.0]:
		var wall := CollisionShape3D.new()
		var wb := BoxShape3D.new()
		wb.size = Vector3(RUN + 2.0 * FLAT, RISE + 1.4, 0.1)
		wall.shape = wb
		wall.position = Vector3(RUN * 0.5, (RISE + 1.4) * 0.5 - 0.2, zs * 0.62)
		body.add_child(wall)


func _physics_process(delta: float) -> void:
	_offset = fposmod(_offset + SPEED * delta, RUN + 2.0 * FLAT)
	_place_steps()
	if player == null or not player.is_on_floor():
		return
	var l := to_local(player.global_position)
	if l.x < -FLAT - 0.1 or l.x > RUN + FLAT + 0.1 or absf(l.z) > WIDTH * 0.5 + 0.1:
		return
	if absf(l.y - line(l.x)) > 0.45:
		return
	# Carried along (up the slope the ramp lifts you).
	player.carry += global_basis.x * SPEED
