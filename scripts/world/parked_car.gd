class_name ParkedCar
extends Node3D
## An uncovered car in the Car Park: "Generic SUV ZYX0" by 1DInc (CC0, see
## assets/garage/LICENSE.md), re-lit with our own shaders. Nobody drives it,
## but it works: the doors open, the dome light switches on, and the key's in
## it: turning it lights the dashboard, the headlights and the tail lights.
## The damaged ones have a flat battery.
##
## The game asks `use_targets()` which parts you could be looking at and
## calls `use(id)` when you press Use.

const OPEN_ANGLE := 1.15
const DOORS := ["DoorFL", "DoorFR", "DoorRL", "DoorRR"]
## The key, at the steering column (driver's side, left-hand drive).
const KEY_POS := Vector3(-0.72, 1.02, 0.36)
const DASH_POS := Vector3(-0.66, 1.1, 0.37)
const CABIN_POS := Vector3(-0.25, 1.5, 0.0)

## Material name in the GLB -> [kind, gloss, glass] (see garage_suv.gdshader).
const KINDS := {
	"car_carpaint": [1, 0.9], "car_chrome": [2, 0.9], "car_light": [4, 0.9], "car_glass_red": [5, 0.9],
	"car_leather": [0, 0.25], "car_grey": [0, 0.35], "car_white": [0, 0.3], "car_tires": [0, 0.1],
	"car_plastic_black": [0, 0.25], "car_plastic_grey": [0, 0.2],
}

var light := 0.5
var damaged := false
var paint := Color(0, 0, 0, 0)
var light_dir := Vector3.UP * 0.3

var _meshes: Array[MeshInstance3D] = []
var _doors := {}       # name -> [node, open, angle, sign, handle (door-local)]
var _cabin := false
var _ignition := false
var _dash: MeshInstance3D
var _beams: MeshInstance3D
var _audio: AudioStreamPlayer3D
var _flicker := 0.0

static var _scenes := {}
static var _mats := {}
static var _glass_mat: ShaderMaterial
static var _dash_mat: ShaderMaterial
static var _beam_mat: ShaderMaterial


func setup(p_light: float, p_damaged: bool, p_paint: Color, p_light_dir: Vector3) -> void:
	light = p_light
	damaged = p_damaged
	paint = p_paint
	light_dir = p_light_dir


func _ready() -> void:
	var path := "res://assets/garage/suv_damaged.glb" if damaged else "res://assets/garage/suv.glb"
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var car: Node3D = (_scenes[path] as PackedScene).instantiate()
	add_child(car)
	for m in car.find_children("*", "MeshInstance3D", true, false):
		var mi := m as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			mi.set_surface_override_material(i, _material(mi.mesh.surface_get_material(i)))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_meshes.append(mi)
	for n in DOORS:
		var d := car.find_child(n, true, false) as Node3D
		if d == null:
			continue
		var side := signf(d.position.z)
		var bb := _local_aabb(d)
		# The handle: towards the back edge, a bit above the middle, outside.
		var outer := bb.end.z if side > 0.0 else bb.position.z
		var handle := Vector3(bb.end.x - 0.2, bb.get_center().y + 0.12, outer)
		_doors[n] = [d, false, 0.0, side, handle]
		for m in d.find_children("*", "MeshInstance3D", true, false) + ([d] if d is MeshInstance3D else []):
			(m as MeshInstance3D).set_instance_shader_parameter("part_offset", d.position)
	_dash = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(0.34, 0.11)
	_dash.mesh = q
	_dash.material_override = _dash_material()
	# Facing the driver (+X), leaning back.
	_dash.transform = Transform3D(Basis(Vector3.UP, PI * 0.5) * Basis(Vector3.RIGHT, -0.35), DASH_POS)
	_dash.visible = false
	add_child(_dash)
	_beams = MeshInstance3D.new()
	var p := PlaneMesh.new()
	p.size = Vector2(6.0, 3.4)
	_beams.mesh = p
	_beams.material_override = _beam_material()
	_beams.position = Vector3(-2.3 - 3.0, 0.02, 0.0)
	_beams.visible = false
	_beams.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_beams)
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = "World"
	_audio.unit_size = 4.0
	_audio.position = Vector3(-0.3, 1.0, 0.0)
	add_child(_audio)
	_set_all("light", light)
	_set_all("light_dir", light_dir)
	if paint.a > 0.0:
		_set_all("paint", Vector4(paint.r, paint.g, paint.b, 1.0))
	add_to_group("usable")
	set_process(false)


## What you can do from here: [id, world position, label].
func use_targets() -> Array:
	var out := []
	var front_open := false
	var any_open := false
	for n in _doors:
		var e: Array = _doors[n]
		var d: Node3D = e[0]
		out.append([n, d.global_transform * (e[4] as Vector3), "Close the door" if e[1] else "Open the door"])
		any_open = any_open or e[1]
		if e[1] and String(n).begins_with("DoorF"):
			front_open = true
	if any_open:
		out.append(["cabin", global_transform * CABIN_POS, "Dome light off" if _cabin else "Dome light on"])
	if front_open:
		out.append(["key", global_transform * KEY_POS, "Switch off" if _ignition else "Turn the key"])
	return out


func use(id: String) -> void:
	match id:
		"cabin":
			_cabin = not _cabin
			_set_all("cabin", 1.0 if _cabin else 0.0)
			_play("click", 0.0)
		"key":
			_play("click", -4.0)
			if _ignition:
				_set_ignition(false)
			elif damaged:
				# Flat battery: the dash flickers and dies.
				_flicker = 0.6
				set_process(true)
			else:
				_set_ignition(true)
		_:
			if _doors.has(id):
				var e: Array = _doors[id]
				e[1] = not e[1]
				_play("car_latch" if e[1] else "car_shut", 0.0)
				set_process(true)


func _set_ignition(on: bool) -> void:
	_ignition = on
	_dash.visible = on
	_beams.visible = on
	_set_all("lamps", 1.0 if on else 0.0)


func _process(delta: float) -> void:
	var busy := false
	for n in _doors:
		var e: Array = _doors[n]
		var target: float = OPEN_ANGLE if e[1] else 0.0
		var a: float = e[2]
		# Swings out easing to a stop, slams shut.
		a = lerpf(a, target, minf(delta * 5.0, 1.0)) if e[1] else move_toward(a, target, delta * 3.2)
		if absf(a - target) < 0.005:
			a = target
		e[2] = a
		(e[0] as Node3D).rotation.y = -float(e[3]) * a
		busy = busy or not is_equal_approx(a, target)
	if _flicker > 0.0:
		_flicker -= delta
		_dash.visible = _flicker > 0.0 and fmod(_flicker * 13.0, 1.0) < 0.5
		_set_all("lamps", 0.15 if _dash.visible else 0.0)
		busy = true
	set_process(busy)


func _play(sound: String, db: float) -> void:
	_audio.stream = AudioSynth.cached(sound)
	_audio.volume_db = db
	_audio.play()


func _set_all(param: String, v: Variant) -> void:
	for mi in _meshes:
		mi.set_instance_shader_parameter(param, v)


## The door's mesh bounds in the door's own space.
static func _local_aabb(d: Node3D) -> AABB:
	var bb := AABB()
	var first := true
	for m in d.find_children("*", "MeshInstance3D", true, false) + ([d] if d is MeshInstance3D else []):
		var mi := m as MeshInstance3D
		var x := d.global_transform.affine_inverse() * mi.global_transform if mi != d else Transform3D.IDENTITY
		var b := x * mi.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	return bb


static func _material(src: Material) -> ShaderMaterial:
	var key := src.resource_name if src else ""
	if _mats.has(key):
		return _mats[key]
	var m: ShaderMaterial
	if key == "car_glass":
		if _glass_mat == null:
			_glass_mat = ShaderMaterial.new()
			_glass_mat.shader = load("res://shaders/garage_suv_glass.gdshader")
		m = _glass_mat
	else:
		m = ShaderMaterial.new()
		m.shader = load("res://shaders/garage_suv.gdshader")
		var k: Array = KINDS.get(key, [0, 0.2])
		m.set_shader_parameter("kind", k[0])
		m.set_shader_parameter("gloss", k[1])
		var sm := src as BaseMaterial3D
		m.set_shader_parameter("albedo", sm.albedo_color if sm else Color(0.1, 0.1, 0.1))
	_mats[key] = m
	return m


static func _dash_material() -> ShaderMaterial:
	if _dash_mat == null:
		_dash_mat = ShaderMaterial.new()
		var s := Shader.new()
		s.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, fog_disabled;
void fragment() {
	// Two dials and a strip between them, glowing pale blue-green.
	vec2 p = (UV - 0.5) * vec2(3.1, 1.0);
	float d1 = abs(length(p - vec2(-0.85, 0.0)) - 0.36);
	float d2 = abs(length(p - vec2(0.85, 0.0)) - 0.36);
	float ring = exp(-min(d1, d2) * 70.0);
	float strip = step(abs(p.x), 0.32) * step(abs(p.y), 0.3) * 0.35;
	float glow = exp(-length(p) * 1.4) * 0.25;
	ALBEDO = vec3(0.45, 0.9, 1.0) * (ring + strip + glow) * 1.6;
}
"""
		_dash_mat.shader = s
	return _dash_mat


static func _beam_material() -> ShaderMaterial:
	if _beam_mat == null:
		_beam_mat = ShaderMaterial.new()
		var s := Shader.new()
		s.code = """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, fog_disabled;
void fragment() {
	// Two pools of headlight on the floor ahead, brightest near the car
	// (UV.x = 1 is the car's end of the plane).
	vec2 p = UV;
	float along = 1.0 - p.x;
	float spread = 0.08 + along * 0.22;
	float l = exp(-pow((p.y - 0.5 + 0.17) / spread, 2.0)) + exp(-pow((p.y - 0.5 - 0.17) / spread, 2.0));
	float fade = smoothstep(0.0, 0.12, along) * (1.0 - smoothstep(0.35, 1.0, along));
	ALBEDO = vec3(1.0, 0.95, 0.85) * min(l, 1.2) * fade * 0.55;
}
"""
		_beam_mat.shader = s
	return _beam_mat
