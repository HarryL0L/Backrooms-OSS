extends Node3D
# Dev harness: the Window Dresser in Godot with the game shader, in each pose.
var out := OS.get_user_data_dir() + "/dresser"
var d: WindowDresser
var cam: Camera3D
var shots := [["dormant", false, Vector3(0.9, 1.4, 3.0)], ["hunt", true, Vector3(1.2, 1.1, 2.4)],
		["run", true, Vector3(2.4, 1.2, 1.2)], ["lunge", true, Vector3(0.6, 1.5, 1.6)], ["stalk_b", false, Vector3(1.0, 1.5, 2.6)]]
var i := 0
var t := 0.0

func _ready():
	DirAccess.make_dir_recursive_absolute(out)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.03, 0.03, 0.035)
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new(); we.environment = env; add_child(we)
	var floor_ := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(8, 8); floor_.mesh = pm
	var fm := StandardMaterial3D.new(); fm.albedo_color = Color(0.12, 0.11, 0.1)
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	floor_.material_override = fm
	add_child(floor_)
	d = WindowDresser.new()
	add_child(d)
	d.set_env_light(Color(0.75, 0.73, 0.68))
	cam = Camera3D.new(); add_child(cam); cam.current = true; cam.fov = 50
	_setup()

func _setup():
	var s = shots[i]
	d.set_awake(s[1])
	d.set_pose(s[0])
	if s[0] == "run":
		d.play_run(0.0)
	cam.look_at_from_position(s[2], Vector3(0, 1.0, 0) if s[0] != "dormant" else Vector3(0, 1.05, 0))

func _process(delta):
	t += delta
	if t > 0.6:
		get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, shots[i][0]])
		print("shot ", shots[i][0])
		i += 1; t = 0
		if i >= shots.size():
			get_tree().quit(); return
		_setup()
