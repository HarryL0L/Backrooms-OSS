class_name OddDoor
extends Node3D
## The mysterious door: a sky-blue painted door in a white frame with a brass
## knob, daylight leaking from the gap under it. Nothing else in the Backrooms
## looks like it. In the Lobby it sits on a wall; in the Field it stands alone
## in the grass (and the Backrooms hum leaks out of it instead).
## The door faces local +Z; the player walks into it to go through.

signal entered

const W := 0.92
const H := 2.06

## Lit by real lights (Field) rather than self-lit like the emissive Backrooms.
var outdoor := false
## Standing alone in the field (frame and back visible) rather than on a wall.
var freestanding := false

var _pivot: Node3D
var _glow: MeshInstance3D
var _audio: AudioStreamPlayer3D
var _used := false


func _ready() -> void:
	var paint := _mat(Color(0.33, 0.62, 0.86), 0.55)
	var frame := _mat(Color(0.93, 0.92, 0.88), 0.6)
	var brass := _mat(Color(0.78, 0.62, 0.30), 0.3)
	brass.metallic = 0.9
	var light := StandardMaterial3D.new()
	light.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	light.albedo_color = Color(1.0, 0.97, 0.88) if not outdoor else Color(1.0, 0.92, 0.55)
	# Frame: two jambs and a head.
	_box(frame, Vector3(0.09, H + 0.09, 0.14), Vector3(-W * 0.5 - 0.045, (H + 0.09) * 0.5, 0.0))
	_box(frame, Vector3(0.09, H + 0.09, 0.14), Vector3(W * 0.5 + 0.045, (H + 0.09) * 0.5, 0.0))
	_box(frame, Vector3(W + 0.18, 0.09, 0.14), Vector3(0.0, H + 0.045, 0.0))
	# Door leaf on a hinge pivot (hinge on the left as seen from the front).
	_pivot = Node3D.new()
	_pivot.position = Vector3(-W * 0.5, 0.0, 0.0)
	add_child(_pivot)
	var leaf := _box(paint, Vector3(W, H - 0.02, 0.045), Vector3(W * 0.5, H * 0.5 + 0.01, 0.0), _pivot)
	# Raised panels for a hand-made look.
	for py in [0.55, 1.45]:
		_box(paint, Vector3(W * 0.62, 0.62, 0.012), Vector3(W * 0.5, py, 0.028), _pivot)
		if freestanding:
			_box(paint, Vector3(W * 0.62, 0.62, 0.012), Vector3(W * 0.5, py, -0.028), _pivot)
	var knob := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.035
	sm.height = 0.07
	knob.mesh = sm
	knob.material_override = brass
	knob.position = Vector3(W - 0.09, 1.0, 0.05)
	_pivot.add_child(knob)
	if freestanding:
		var k2 := knob.duplicate() as MeshInstance3D
		k2.position.z = -0.05
		_pivot.add_child(k2)
	leaf.name = "Leaf"
	# Light from "the other side": a strip under the door, and the whole
	# opening once the door swings.
	_box(light, Vector3(W - 0.04, 0.012, 0.01), Vector3(0.0, 0.006, 0.03))
	_glow = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(W, H)
	_glow.mesh = q
	_glow.material_override = light
	_glow.position = Vector3(0.0, H * 0.5, -0.03)
	_glow.visible = false
	add_child(_glow)
	# Walk-in trigger in front (and behind, when free-standing).
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(W * 0.8, 1.6, 0.5 if not freestanding else 0.3)
	cs.shape = bs
	cs.position = Vector3(0.0, 0.9, 0.25 if not freestanding else 0.0)
	area.add_child(cs)
	area.body_entered.connect(_on_body)
	add_child(area)
	if freestanding:
		# Solid frame posts so it can't be walked through sideways.
		var body := StaticBody3D.new()
		for sx in [-1.0, 1.0]:
			var c2 := CollisionShape3D.new()
			var b2 := BoxShape3D.new()
			b2.size = Vector3(0.09, H + 0.09, 0.14)
			c2.shape = b2
			c2.position = Vector3(sx * (W * 0.5 + 0.045), (H + 0.09) * 0.5, 0.0)
			body.add_child(c2)
		add_child(body)
	# A sound that gives it away when you're close.
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = AudioSynth.draught() if not outdoor else AudioSynth.hum()
	_audio.unit_size = 1.6 if not outdoor else 3.0
	_audio.max_distance = 14.0 if not outdoor else 40.0
	_audio.volume_db = -6.0 if not outdoor else -2.0
	_audio.position = Vector3(0.0, 1.0, 0.1)
	add_child(_audio)
	_audio.play()


func _on_body(body: Node3D) -> void:
	if _used or not (body is Player):
		return
	_used = true
	entered.emit()


## Swings the door open onto the light behind it.
func open() -> void:
	_glow.visible = true
	var tw := create_tween()
	tw.tween_property(_pivot, "rotation:y", -1.75 if not freestanding else 1.75, 0.7) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	await tw.finished


func _mat(c: Color, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if not outdoor:
		# Backrooms surfaces are self-lit (baked light is emitted), so the door
		# carries its own share of the room's light.
		m.emission_enabled = true
		m.emission = c * 0.55
	return m


func _box(m: Material, size: Vector3, pos: Vector3, parent: Node3D = self) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	parent.add_child(mi)
	return mi
