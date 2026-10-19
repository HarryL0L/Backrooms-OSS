class_name WindowDresser
extends Node3D
## The Window Dresser's body: the Blender-made model (assets/models/
## window_dresser.glb) with its materials swapped for the world-lit shader,
## and helpers to pose it. Behaviour lives in DresserAI.
## Poses are stop-motion: "dormant", "stalk_a/b/c", "hunt", "lunge" are
## single frames, "run" is a 6-frame cycle with no blending in between.
## Its front is +Z (turn it with look_at(target, Vector3.UP, true)).

const SCENE := "res://assets/models/window_dresser.glb"

var anim: AnimationPlayer
var awake := false
var _meshes: Array[MeshInstance3D] = []
var _calm: Node3D
var _broken: Node3D
var _stand: Array[Node3D] = []
static var _mats := {}


func _ready() -> void:
	var model: Node3D = (load(SCENE) as PackedScene).instantiate()
	add_child(model)
	# The model faces +Z (Blender -Y): its front is this node's +Z.
	anim = model.find_children("*", "AnimationPlayer", true, false)[0] as AnimationPlayer
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		_meshes.append(m)
		for s in m.mesh.get_surface_count():
			m.set_surface_override_material(s, _material_for(m.mesh.surface_get_material(s)))
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		m.gi_mode = GeometryInstance3D.GI_MODE_DYNAMIC    # lit by VoxelGI, never baked into it
		if m.name.begins_with("head_calm"):
			_calm = m
		elif m.name.begins_with("head_broken"):
			_broken = m
		elif m.name.begins_with("display_"):
			_stand.append(m)
	set_awake(false)
	set_pose("dormant")


## Swaps a Blender material for the world-lit one (shared per name).
static func _material_for(src: Material) -> Material:
	var key := src.resource_name if src else ""
	if _mats.has(key):
		return _mats[key]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/dresser.gdshader")
	var std := src as BaseMaterial3D
	match key:
		"DresserSkin":
			sm.set_shader_parameter("albedo_tex", std.albedo_texture if std else null)
			sm.set_shader_parameter("normal_tex", std.normal_texture if std else null)
		"Inner":
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", Color(0.03, 0.012, 0.01))
		"Teeth":
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", Color(0.62, 0.57, 0.45))
		"EyeGlint":
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", Color(1.0, 0.92, 0.75))
			sm.set_shader_parameter("glow", 3.0)
		"Pin":
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", Color(0.3, 0.3, 0.29))
			sm.set_shader_parameter("roughness", 0.3)
		"TagRed":
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", Color(0.45, 0.04, 0.03))
		"Fibreglass":
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", Color(0.8, 0.74, 0.62))
		"Tag":
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", Color(0.85, 0.84, 0.8))
		_:
			sm.set_shader_parameter("use_textures", false)
			sm.set_shader_parameter("albedo", std.albedo_color if std else Color(0.74, 0.68, 0.55))
	_mats[key] = sm
	return sm


## For the loading screen's shader warm-up.
static func warm_materials() -> Array[Material]:
	var out: Array[Material] = []
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/dresser.gdshader")
	out.append(sm)
	return out


func set_pose(name: String) -> void:
	if anim and anim.has_animation(name):
		anim.speed_scale = 1.0
		anim.play(name)
		anim.seek(0.0, true)
		if name != "run":
			anim.pause()


## Running (or the slow searching prowl, `cycle` "walk"), the cycle at a
## speed matching how fast it moves.
func play_run(speed_scale: float, cycle := "run") -> void:
	if not anim.has_animation(cycle):
		cycle = "run"
	if anim.current_animation != cycle:
		anim.play(cycle, 0.15)
	anim.speed_scale = speed_scale


## Dormant: smooth egg head and the display stand. Awake: the shattered face.
func set_awake(on: bool) -> void:
	awake = on
	if _calm:
		_calm.visible = not on
	if _broken:
		_broken.visible = on
	for s in _stand:
		s.visible = not on


## World position of the head bone in the current pose (INF if unknown).
func head_position() -> Vector3:
	if anim:
		anim.advance(0.0)
	for sk in find_children("*", "Skeleton3D", true, false):
		var skel := sk as Skeleton3D
		var i := skel.find_bone("head")
		if i >= 0:
			skel.force_update_all_bone_transforms()
			return skel.global_transform * skel.get_bone_global_pose(i).origin
	return Vector3.INF


func set_env_light(c: Color) -> void:
	for m in _meshes:
		UniqueParams.set_param(m, &"env_light", Vector3(c.r, c.g, c.b))
