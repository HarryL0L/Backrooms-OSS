class_name EntityBody
extends Node3D
## A downloaded figure (assets/entities, CC0: see assets/entities/LICENSE.md)
## with its own clips (idle, walks, run), relit like the world with the
## figure shader. Faces +Z. update() advances the clips and then applies
## anything laid over them: a head turn, a neck stoop, or the crawl (posed
## from limb directions, since the base mesh has no clips of its own).

const SCENES := {
	"sam": "res://assets/entities/sam.glb",
	"harper": "res://assets/entities/harper.glb",
	"jordan": "res://assets/entities/jordan.glb",
	"crawler": "res://assets/entities/crawler.glb",
}
## Clip name -> in-place travel speed (m/s), from the source pages.
const CLIP_SPEED := {"Walk_Relaxed": 1.3, "Walk_Brisk": 1.7, "Run": 4.5}
## Each limb bone and the bone its far end reaches (its direction).
const CHILD := {
	"pelvis": "spine_01", "spine_01": "spine_02", "spine_02": "spine_03", "spine_03": "neck_01",
	"neck_01": "head", "upperarm_l": "lowerarm_l", "lowerarm_l": "hand_l", "upperarm_r": "lowerarm_r",
	"lowerarm_r": "hand_r", "hand_l": "middle_01_l", "hand_r": "middle_01_r",
	"thigh_l": "calf_l", "calf_l": "foot_l", "thigh_r": "calf_r", "calf_r": "foot_r",
	"foot_l": "ball_l", "foot_r": "ball_r",
}

static var _scenes := {}
static var _shader: Shader

var who := "sam"
var tint := Color.WHITE
var skeleton: Skeleton3D
var anim: AnimationPlayer
var head_yaw := 0.0
var stoop := 0.0
var _mats: Array[ShaderMaterial] = []
var _clip := ""
var _over := {}           # bone -> [rotation written, overlay applied]


func _ready() -> void:
	var path: String = SCENES[who]
	if not _scenes.has(path):
		_scenes[path] = load(path)
	var inst: Node3D = (_scenes[path] as PackedScene).instantiate()
	add_child(inst)
	skeleton = inst.find_child("*", true, false) as Skeleton3D
	for n in inst.find_children("*", "Skeleton3D", true, false):
		skeleton = n
	for n in inst.find_children("*", "AnimationPlayer", true, false):
		anim = n
	if anim:
		# Advanced by hand in update(), so the overlays go on after it.
		anim.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
		for c in CLIP_SPEED.keys() + ["Idle_Standing"]:
			if anim.has_animation(c):
				anim.get_animation(c).loop_mode = Animation.LOOP_LINEAR
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		_relight(mi)


func _relight(mi: MeshInstance3D) -> void:
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if _shader == null:
		_shader = load("res://shaders/figure.gdshader")
	for i in mi.mesh.get_surface_count():
		var src := mi.get_active_material(i)
		var m := ShaderMaterial.new()
		m.shader = _shader
		if src is BaseMaterial3D:
			var b := src as BaseMaterial3D
			m.set_shader_parameter("albedo_tex", b.albedo_texture)
			# The tint is for the clothes (the face and hands stay as they are).
			var cloth := b.resource_name.contains("fabric") or b.resource_name.contains("suit") \
					or b.resource_name.contains("original top") or b.resource_name.contains("original bottom")
			m.set_shader_parameter("tint", b.albedo_color * (tint if cloth else Color.WHITE))
			m.set_shader_parameter("roughness", b.roughness)
			if b.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED:
				m.set_shader_parameter("alpha_cut", 0.5)
		mi.set_surface_override_material(i, m)
		_mats.append(m)


## Light level where it stands (see figure.gdshader).
func set_env_light(c: Color) -> void:
	for m in _mats:
		m.set_shader_parameter("env_light", Vector3(c.r, c.g, c.b))


## Plays a clip, timed so the feet keep pace with `speed` m/s.
func play(clip: String, speed := 0.0, blend := 0.3) -> void:
	if anim == null or not anim.has_animation(clip):
		return
	var rate := 1.0
	if CLIP_SPEED.has(clip) and speed > 0.0:
		rate = speed / (CLIP_SPEED[clip] * scale.y)
	if clip != _clip:
		anim.play(clip, blend, rate)
		_clip = clip
	else:
		anim.play(clip, -1, rate)


## The clip for moving at `speed` m/s (standing when about 0).
func move(speed: float) -> void:
	if speed < 0.1:
		play("Idle_Standing")
	elif speed < 2.4 * scale.y:
		play("Walk_Brisk" if speed > 1.5 * scale.y else "Walk_Relaxed", speed)
	else:
		play("Run", speed)


func update(delta: float) -> void:
	if anim:
		anim.advance(delta)
	if skeleton == null:
		return
	# Take off last frame's overlays where the clip didn't set the bone again.
	for b in _over:
		var e: Array = _over[b]
		if skeleton.get_bone_pose_rotation(b).is_equal_approx(e[0]):
			skeleton.set_bone_pose_rotation(b, e[0] * (e[1] as Quaternion).inverse())
	_over.clear()
	if absf(head_yaw) > 0.001:
		_turn("neck_01", Vector3.UP, head_yaw * 0.35)
		_turn("head", Vector3.UP, head_yaw * 0.65)
	if stoop > 0.001:
		_turn("spine_03", Vector3.RIGHT, stoop * 0.4)
		_turn("neck_01", Vector3.RIGHT, stoop * 0.6)


## Rotates a bone about an axis given in the figure's own space (+Y up,
## +X its left, +Z ahead), on top of its current pose.
func _turn(bone: String, axis: Vector3, angle: float) -> void:
	var b := skeleton.find_bone(bone)
	if b < 0:
		return
	var g := skeleton.get_bone_global_pose(b).basis.orthonormalized()
	var q := Quaternion((g.inverse() * axis).normalized(), angle)
	var r := skeleton.get_bone_pose_rotation(b) * q
	skeleton.set_bone_pose_rotation(b, r)
	if _over.has(b):
		q = (_over[b][1] as Quaternion) * q
	_over[b] = [r, q]


## On all fours: hips at `hip_h` metres, each limb pointing where it's told
## (figure space). phase in radians, one stride per TAU; amount 0..1.
func pose_crawl(phase: float, amount: float) -> void:
	if skeleton == null:
		return
	var sw := sin(phase) * amount
	var sw2 := sin(phase + PI) * amount
	var dirs := {
		"pelvis": Vector3(0, 0.12, 1), "spine_01": Vector3(0, 0.14, 1), "spine_02": Vector3(0, 0.16, 1),
		"spine_03": Vector3(0, 0.3, 1), "neck_01": Vector3(0, 0.75, 1), "head": Vector3(0, 0.9, 0.6),
		# Arms straight down to the floor, a little ahead; diagonal pairs.
		"upperarm_l": Vector3(0.12, -1, 0.15 + 0.45 * sw), "lowerarm_l": Vector3(0.05, -1, 0.05 + 0.25 * sw - 0.2 * maxf(cos(phase), 0.0) * amount),
		"upperarm_r": Vector3(-0.12, -1, 0.15 + 0.45 * sw2), "lowerarm_r": Vector3(-0.05, -1, 0.05 + 0.25 * sw2 - 0.2 * maxf(cos(phase + PI), 0.0) * amount),
		"hand_l": Vector3(0.1, -0.15, 1), "hand_r": Vector3(-0.1, -0.15, 1),
		# Knees on the floor under the hips, shins trailing behind.
		"thigh_l": Vector3(0.14, -1, 0.1 + 0.4 * sw2), "calf_l": Vector3(0.04, -0.12 - 0.3 * maxf(cos(phase + PI), 0.0) * amount, -1),
		"thigh_r": Vector3(-0.14, -1, 0.1 + 0.4 * sw), "calf_r": Vector3(-0.04, -0.12 - 0.3 * maxf(cos(phase), 0.0) * amount, -1),
		"foot_l": Vector3(0, -1, -0.4), "foot_r": Vector3(0, -1, -0.4),
	}
	_aim_all(dirs)
	var p := skeleton.find_bone("pelvis")
	var rest := skeleton.get_bone_rest(p).origin
	var parent := skeleton.get_bone_parent(p)
	var pb := skeleton.get_bone_global_rest(parent).basis if parent >= 0 else Basis.IDENTITY
	# Down to all fours (the rest pelvis is at standing hip height).
	skeleton.set_bone_pose_position(p, rest + pb.inverse() * Vector3(0, -0.45, -0.25))


## Sets bone rotations so each listed bone points along its direction,
## parents first (bones not listed keep their rest pose).
func _aim_all(dirs: Dictionary) -> void:
	var globals := {}
	for b in skeleton.get_bone_count():
		var parent := skeleton.get_bone_parent(b)
		var pg: Basis = globals[parent] if parent >= 0 else Basis.IDENTITY
		var rest_g := skeleton.get_bone_global_rest(b).basis.orthonormalized()
		var name := skeleton.get_bone_name(b)
		var g: Basis
		if dirs.has(name) and CHILD.has(name):
			var c := skeleton.find_bone(CHILD[name])
			var from := (skeleton.get_bone_global_rest(c).origin - skeleton.get_bone_global_rest(b).origin).normalized()
			var to: Vector3 = (dirs[name] as Vector3).normalized()
			g = Basis(_arc(from, to)) * rest_g
		else:
			g = pg * skeleton.get_bone_rest(b).basis.orthonormalized()
		globals[b] = g
		skeleton.set_bone_pose_rotation(b, (pg.inverse() * g).get_rotation_quaternion())


static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := a.dot(b)
	if d > 0.9999:
		return Quaternion.IDENTITY
	if d < -0.9999:
		var ax := a.cross(Vector3.RIGHT)
		if ax.length() < 0.01:
			ax = a.cross(Vector3.UP)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(clampf(d, -1.0, 1.0)))


## Materials to pre-compile during loading.
static func warm_materials() -> Array[Material]:
	if _shader == null:
		_shader = load("res://shaders/figure.gdshader")
	var m := ShaderMaterial.new()
	m.shader = _shader
	var m2 := ShaderMaterial.new()
	m2.shader = _shader
	m2.set_shader_parameter("alpha_cut", 0.5)
	return [m, m2]
