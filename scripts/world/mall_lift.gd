class_name MallLift
extends Node3D
## The Dead Mall's glass lift, in a corner of the Fountain Court's atrium:
## a glass shaft with sliding doors on each of the three floors, a glass
## car that carries you. Call it from any floor (the button beside the
## doors), choose a floor inside. It chimes when it arrives. Uses the
## game's interact prompt (group "usable", like the cars).
##
## Local space: origin at the bottom of the shaft, +X the way out through
## the doors (towards the gallery), +Y up.

const FLOORS := 3
const FH := 5.0
const HALF := 1.0            # shaft half size
const CAR := 0.9             # car half size
const CAR_H := 2.4
const DOOR_H := 2.2
const DOOR_W := 1.1
const SPEED := 1.3
const DOOR_TIME := 0.9
const OPEN_FOR := 6.0
const NAMES := ["Ground floor", "Level 1", "Level 2"]

enum { IDLE, OPENING, OPEN, CLOSING, MOVING }

var light := 0.5
var _car: AnimatableBody3D
var _car_y := 0.0
var _at := 0                 # floor the car is at (or heading for)
var _queue: Array[int] = []
var _state := IDLE
var _t := 0.0
var _door_k := 0.0           # 0 shut .. 1 open (the doors at _at)
var _gates: Array = []       # per floor: [left, right] AnimatableBody3D
var _audio: AudioStreamPlayer3D
var _motor: AudioStreamPlayer3D


func _ready() -> void:
	add_to_group("usable")
	_build_shaft()
	_build_car()
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = "World"
	_audio.unit_size = 4.0
	_car.add_child(_audio)
	_audio.position = Vector3(0, CAR_H, 0)
	_motor = AudioStreamPlayer3D.new()
	_motor.bus = "World"
	_motor.stream = AudioSynth.cached("hum")
	_motor.pitch_scale = 0.4
	_motor.volume_db = -10.0
	_motor.unit_size = 3.0
	_car.add_child(_motor)
	_open()


func _mat(m: String) -> Material:
	return MallLevel.lit_material(m, light)


func _box(parent: Node3D, size: Vector3, pos: Vector3, m: String, collide := false) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(m)
	mi.mesh = bm
	mi.position = pos
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(mi)
	if collide:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		cs.position = pos
		parent.add_child(cs)


func _build_shaft() -> void:
	var top := FLOORS * FH - 0.3
	var shaft := StaticBody3D.new()
	add_child(shaft)
	# Corner posts, glass on three sides, a machine housing on top.
	for x in [-HALF, HALF]:
		for z in [-HALF, HALF]:
			_box(shaft, Vector3(0.1, top + 1.0, 0.1), Vector3(x, (top + 1.0) * 0.5, z), "metal_frame")
	_box(shaft, Vector3(0.04, top, 2.0 * HALF), Vector3(-HALF, top * 0.5, 0), "glass", true)
	for z in [-HALF, HALF]:
		_box(shaft, Vector3(2.0 * HALF, top, 0.04), Vector3(0, top * 0.5, z), "glass", true)
	_box(shaft, Vector3(2.0 * HALF + 0.2, 0.9, 2.0 * HALF + 0.2), Vector3(0, top + 0.95, 0), "metal_frame")
	# The door side: a frame round each floor's doors, glass between floors.
	for k in FLOORS:
		var y0 := k * FH
		var y1 := (k + 1) * FH if k < FLOORS - 1 else top
		_box(shaft, Vector3(0.04, y1 - y0 - DOOR_H, 2.0 * HALF), Vector3(HALF, y0 + DOOR_H + (y1 - y0 - DOOR_H) * 0.5, 0), "glass", true)
		_box(shaft, Vector3(0.12, 0.12, 2.0 * HALF), Vector3(HALF + 0.02, y0 + DOOR_H + 0.06, 0), "metal_frame")
		for zs in [-1.0, 1.0]:
			_box(shaft, Vector3(0.04, DOOR_H, HALF - DOOR_W * 0.5), Vector3(HALF, y0 + DOOR_H * 0.5, zs * (DOOR_W * 0.5 + (HALF - DOOR_W * 0.5) * 0.5)), "metal_frame", true)
		# Call button beside the doors: a steel plate, the button lit.
		_box(shaft, Vector3(0.02, 0.18, 0.09), Vector3(HALF + 0.03, y0 + 1.1, DOOR_W * 0.5 + 0.2), "metal_bright")
		_box(shaft, Vector3(0.02, 0.035, 0.035), Vector3(HALF + 0.045, y0 + 1.12, DOOR_W * 0.5 + 0.2), "light_panel")
		var gates := []
		for zs in [-1.0, 1.0]:
			var g := AnimatableBody3D.new()
			g.sync_to_physics = false
			add_child(g)
			g.position = Vector3(HALF + 0.05, y0, zs * DOOR_W * 0.25)
			# A bronze-framed glass door leaf.
			_box(g, Vector3(0.05, 0.12, DOOR_W * 0.5), Vector3(0, 0.06, 0), "metal_frame", true)
			_box(g, Vector3(0.05, 0.12, DOOR_W * 0.5), Vector3(0, DOOR_H - 0.06, 0), "metal_frame")
			for zz in [-1.0, 1.0]:
				_box(g, Vector3(0.05, DOOR_H, 0.06), Vector3(0, DOOR_H * 0.5, zz * (DOOR_W * 0.25 - 0.03)), "metal_frame")
			_box(g, Vector3(0.02, DOOR_H - 0.24, DOOR_W * 0.5 - 0.12), Vector3(0, DOOR_H * 0.5, 0), "glass", true)
			gates.append(g)
		_gates.append(gates)


func _build_car() -> void:
	_car = AnimatableBody3D.new()
	add_child(_car)
	_box(_car, Vector3(2.0 * CAR, 0.1, 2.0 * CAR), Vector3(0, -0.05, 0), "terrazzo", true)
	_box(_car, Vector3(2.0 * CAR, 0.12, 2.0 * CAR), Vector3(0, CAR_H + 0.06, 0), "metal_frame")
	_box(_car, Vector3(1.2, 0.02, 0.6), Vector3(0, CAR_H - 0.01, 0), "light_panel")
	_box(_car, Vector3(0.04, CAR_H, 2.0 * CAR), Vector3(-CAR, CAR_H * 0.5, 0), "glass", true)
	for zs in [-1.0, 1.0]:
		_box(_car, Vector3(2.0 * CAR, CAR_H, 0.04), Vector3(0, CAR_H * 0.5, zs * CAR), "glass", true)
		_box(_car, Vector3(2.0 * CAR, 0.05, 0.05), Vector3(0, 0.95, zs * (CAR - 0.06)), "metal_bright")
	# The button panel, inside by the doors.
	_box(_car, Vector3(0.3, 0.9, 0.03), Vector3(CAR - 0.25, 1.25, -CAR + 0.04), "metal_bright")
	for k in FLOORS:
		_box(_car, Vector3(0.07, 0.07, 0.03), Vector3(CAR - 0.25, _button_h(k), -CAR + 0.06), "light_panel")
	# Bronze corner posts on the car.
	for x in [-CAR, CAR]:
		for z in [-CAR, CAR]:
			_box(_car, Vector3(0.06, CAR_H, 0.06), Vector3(x, CAR_H * 0.5, z), "metal_frame")


func _button_h(k: int) -> float:
	return 0.95 + k * 0.25


## What you can do from here: [id, world position, label].
func use_targets(p: Player) -> Array:
	var out := []
	var l := to_local(p.global_position)
	if absf(l.x) < CAR and absf(l.z) < CAR and absf(l.y - _car_y) < 1.0:
		for k in FLOORS:
			out.append(["go%d" % k, _car.global_transform * Vector3(CAR - 0.25, _button_h(k), -CAR + 0.08), NAMES[k]])
	else:
		for k in FLOORS:
			out.append(["call%d" % k, global_transform * Vector3(HALF + 0.05, k * FH + 1.1, DOOR_W * 0.5 + 0.2), "Call the lift"])
	return out


func use(id: String, _p: Player) -> String:
	var k := int(id.substr(id.length() - 1))
	_play("click", -6.0)
	if k == _at and _state != MOVING:
		_open()
		return ""
	if not _queue.has(k):
		_queue.append(k)
	return "" if id.begins_with("go") else "The lift is coming."


func _open() -> void:
	if _state == OPEN or _state == OPENING:
		_t = 0.0
		return
	_state = OPENING
	_t = 0.0


func _physics_process(delta: float) -> void:
	_t += delta
	match _state:
		IDLE:
			if not _queue.is_empty():
				_state = MOVING if _queue[0] != _at else OPENING
				if _queue[0] == _at:
					_queue.pop_front()
				else:
					_motor.play()
				_t = 0.0
		OPENING:
			_door_k = minf(_door_k + delta / DOOR_TIME, 1.0)
			if _door_k >= 1.0:
				_state = OPEN
				_t = 0.0
		OPEN:
			# Stays open a while; closes early if somewhere else is asked for.
			if _t > OPEN_FOR or (not _queue.is_empty() and _t > 1.5):
				_state = CLOSING
		CLOSING:
			_door_k = maxf(_door_k - delta / DOOR_TIME, 0.0)
			if _door_k <= 0.0:
				_state = IDLE
		MOVING:
			var target: int = _queue[0]
			var ty := target * FH
			_car_y = move_toward(_car_y, ty, SPEED * delta * clampf(absf(ty - _car_y) * 1.5 + 0.15, 0.15, 1.0))
			_at = roundi(_car_y / FH)
			if is_equal_approx(_car_y, ty):
				_car_y = ty
				_at = target
				_queue.pop_front()
				_motor.stop()
				_play("ding", -2.0)
				_state = OPENING
				_t = 0.0
	_car.position = Vector3(0, _car_y, 0)
	# Only the doors where the car stands open.
	for k in FLOORS:
		var o := _door_k if k == _at and _state != MOVING else 0.0
		for i in 2:
			var zs := -1.0 if i == 0 else 1.0
			(_gates[k][i] as Node3D).position.z = zs * (DOOR_W * 0.25 + o * (DOOR_W * 0.5 - 0.02))


func _play(sound: String, db: float) -> void:
	_audio.stream = AudioSynth.cached(sound)
	_audio.volume_db = db
	_audio.play()
