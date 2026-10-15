extends Node3D
# Dev harness: design renders of the hazmat player model.
var out := OS.get_user_data_dir() + "/hazmat"
var cam: Camera3D
var model: HazmatModel
var shots := [
	["front", Vector3(1.3, 1.25, 2.6), Vector3(0, 0.95, 0), 38.0, "idle"],
	["back", Vector3(-1.5, 1.35, -2.4), Vector3(0, 1.0, 0), 38.0, "idle"],
	["head", Vector3(0.35, 1.62, 0.75), Vector3(0, 1.57, 0), 30.0, "idle"],
	["walk", Vector3(2.6, 1.15, 0.9), Vector3(0, 0.92, 0), 38.0, "walk"],
]
var i := 0
var t := 0.0

func _ready():
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.13, 0.14)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.5, 0.5, 0.55)
	env.ambient_light_energy = 0.55
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	for l in [[Vector3(-0.6, -0.9, -0.5), 1.4, Color(1, 0.97, 0.9)], [Vector3(0.7, -0.3, -0.4), 0.45, Color(0.8, 0.85, 1.0)], [Vector3(0.2, -0.4, 0.9), 0.8, Color(1, 1, 1)]]:
		var d := DirectionalLight3D.new()
		d.light_color = l[2]; d.light_energy = l[1]
		add_child(d)
		d.look_at_from_position(Vector3.ZERO, l[0], Vector3.UP if absf(l[0].y) < 0.99 else Vector3.FORWARD)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(8, 8); floor_.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.3, 0.3, 0.32); fm.roughness = 0.9
	floor_.material_override = fm
	add_child(floor_)
	model = HazmatModel.new()
	add_child(model)
	cam = Camera3D.new(); add_child(cam); cam.current = true
	_setup()

func _setup():
	var s = shots[i]
	cam.fov = s[3]
	cam.look_at_from_position(s[1], s[2])
	if s[4] == "walk":
		model.pose_walk(0.9, 1.0, 0.0)
	else:
		model.pose_idle(0.0)

func _process(delta):
	t += delta
	if t > 0.5:
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shots[i][0]])
		print("shot ", shots[i][0])
		i += 1; t = 0
		if i >= shots.size():
			get_tree().quit(); return
		_setup()
