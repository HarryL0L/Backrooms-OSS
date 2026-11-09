class_name FieldLevel
extends Node3D
## The Meadow: an endless lawn on a summer afternoon under a tornadic
## supercell (FieldStorm, docs/FIELD_STORM.md): a dark green-grey storm
## light, the wall cloud and a tornado kilometres off, rain bands and gusts
## sweeping the grass, lightning and thunder. Reached through a rare door in
## the Yellow Halls; the way back is a lone door standing somewhere out in
## the grass. On High and up the grass is real blades (FieldGrass).
##
## It lives far below the Backrooms (FIELD_Y) so both can exist in one scene
## without touching. The ground mesh and its collision follow the player.

signal exit_entered

const FIELD_Y := -2000.0
const EXIT_MIN := 90.0
const EXIT_MAX := 150.0
## The exit lies roughly ahead of where you arrive (toward the giant cloud),
## under a lone tree on a rise: the only landmark in the whole field.
const EXIT_SPREAD := 0.85        # radians either side of straight ahead
const EYE := 1.6
const COLL_N := 97               # collision heightmap size (1 m spacing)

var player: Player
var environment: Environment
var exit_pos := Vector3.ZERO

var _ground: MeshInstance3D
var _coll: CollisionShape3D
var _coll_centre := Vector2(INF, INF)
var _door: OddDoor
var _noise_fine: NoiseTexture2D
var _noise_blot: NoiseTexture2D
## The weather (the storm, its light and camera, the rain, the sound).
var storm: FieldStorm
## The realistic grass (High and up), else null.
var grass: FieldGrass


## Same function as field_height() in field_common.gdshaderinc.
static func height(x: float, z: float) -> float:
	var h := 3.2 * sin(x * 0.021 + 0.3) * sin(z * 0.017 + 1.1) \
			+ 2.2 * sin(x * 0.033 + z * 0.026 + 2.0) \
			+ 1.4 * sin(-x * 0.019 + z * 0.041 + 0.7) \
			+ 0.3 * sin(x * 0.09 - z * 0.07 + 1.9)
	return h * (1.0 - smoothstep(1500.0, 3000.0, Vector2(x, z).length()))


static func ground_at(x: float, z: float) -> Vector3:
	return Vector3(x, FIELD_Y + height(x, z), z)


## Builds the level. `seed_value` decides where the exit door stands;
## `exit_override` restores a saved one.
func build(seed_value: int, exit_override := Vector3.INF) -> void:
	_noise_fine = _noise(256, 0.035, 5, 1)
	_noise_blot = _noise(256, 0.012, 4, 2)
	var preset := int(Settings.get_value("graphics/preset"))
	var low := preset <= 1
	environment = _make_environment(low)
	storm = FieldStorm.new()
	storm.name = "Storm"
	add_child(storm)
	storm.setup(seed_value, _noise_fine, low)
	_ground = MeshInstance3D.new()
	_ground.mesh = _make_ground_mesh()
	var gm := ShaderMaterial.new()
	gm.shader = load("res://shaders/field_ground.gdshader")
	gm.set_shader_parameter("noise_fine", _noise_fine)
	gm.set_shader_parameter("noise_blot", _noise_blot)
	gm.set_shader_parameter("air_steps", 4 if low else 6)
	# Real blades on High, Max and Realistic (not in the PS1 look).
	if preset >= 3 and not bool(Settings.get_value("graphics/ps1")):
		grass = FieldGrass.new()
		grass.name = "Grass"
		add_child(grass)
		grass.setup(preset >= 4)
		gm.set_shader_parameter("blades", 1.0)
		gm.set_shader_parameter("blade_far", grass.reach())
	_ground.material_override = gm
	_ground.extra_cull_margin = 16.0
	_ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ground)
	var body := StaticBody3D.new()
	_coll = CollisionShape3D.new()
	var hm := HeightMapShape3D.new()
	hm.map_width = COLL_N
	hm.map_depth = COLL_N
	_coll.shape = hm
	body.add_child(_coll)
	add_child(body)
	# Exit door somewhere out there, turned to face where you arrived.
	if exit_override.is_finite():
		exit_pos = exit_override
	else:
		exit_pos = _pick_exit(seed_value)
	_door = OddDoor.new()
	_door.outdoor = true
	_door.freestanding = true
	add_child(_door)
	_door.global_position = exit_pos - Vector3(0, 0.04, 0)
	# Front (+Z) turned toward the arrival point.
	_door.look_at(Vector3(0.0, _door.global_position.y, 0.0), Vector3.UP, true)
	_door.entered.connect(func() -> void: exit_entered.emit())
	_make_tree(exit_pos)
	# (No music: the storm's wind, rain and thunder are the Field's sound now.)


## Chooses the exit spot: a random candidate ahead of the arrival point whose
## door can be seen over the hills from there, else one whose tree can.
func _pick_exit(seed_value: int) -> Vector3:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var eye := Vector3(0.0, height(0.0, 0.0) + EYE, 0.0)
	var door_seen := []
	var tree_seen := []
	var any := []
	for k in 40:
		var a := rng.randf_range(-EXIT_SPREAD, EXIT_SPREAD)
		var d := rng.randf_range(EXIT_MIN, EXIT_MAX)
		var p := Vector3(sin(a) * d, 0.0, -cos(a) * d)
		p.y = height(p.x, p.z)
		any.append(p)
		if _visible_from(eye, p + Vector3(0, 1.0, 0)):
			door_seen.append(p)
		elif _visible_from(eye, p + Vector3(0, 8.0, 0)):
			tree_seen.append(p)
	var pool: Array = door_seen if not door_seen.is_empty() else (tree_seen if not tree_seen.is_empty() else any)
	var best: Vector3 = pool[rng.randi() % pool.size()]
	return ground_at(best.x, best.z)


## Terrain line-of-sight between two points (heights relative to FIELD_Y).
static func _visible_from(a: Vector3, b: Vector3) -> bool:
	for i in range(1, 48):
		var t := i / 48.0
		var p := a.lerp(b, t)
		if height(p.x, p.z) > p.y - 0.15:
			return false
	return true


## The lone tree beside the exit door: a leaning trunk with a few limbs and a
## clumpy crown, about 12 m tall so it shows on the horizon.
func _make_tree(door: Vector3) -> void:
	var side := Vector3(door.z, 0.0, -door.x).normalized()   # perpendicular to the way you came
	var base := ground_at(door.x + side.x * 5.0, door.z + side.z * 5.0)
	var tree := Node3D.new()
	add_child(tree)
	tree.global_position = base - Vector3(0, 0.3, 0)
	tree.rotation.y = atan2(side.x, side.z)
	tree.scale = Vector3.ONE * 1.3
	var bark := StandardMaterial3D.new()
	bark.albedo_color = Color(0.17, 0.13, 0.1)
	bark.roughness = 1.0
	var lean := Vector3(0.35, 0.0, 0.1)
	_limb(tree, bark, Vector3.ZERO, Vector3(0.0, 4.6, 0.0) + lean, 0.34, 0.24)
	var top := Vector3(0.0, 4.6, 0.0) + lean
	var limbs := [Vector3(-2.2, 2.0, 0.6), Vector3(2.0, 2.3, -0.4), Vector3(0.4, 2.6, 1.8), Vector3(-0.3, 2.4, -2.0)]
	for l in limbs:
		_limb(tree, bark, top - Vector3(0, 0.6, 0), top + l, 0.18, 0.08)
	var leaves := ShaderMaterial.new()
	leaves.shader = load("res://shaders/field_tree.gdshader")
	leaves.set_shader_parameter("noise_fine", _noise_fine)
	leaves.set_shader_parameter("base_y", base.y - 0.3)
	var rng := RandomNumberGenerator.new()
	rng.seed = int(door.x * 13.0) ^ int(door.z * 7.0)
	var clumps := [Vector3(0, 7.2, 0), Vector3(-2.4, 6.4, 0.6), Vector3(2.3, 6.6, -0.3), Vector3(0.5, 6.9, 2.0),
			Vector3(-0.4, 6.6, -2.2), Vector3(0.2, 8.4, 0.2), Vector3(-1.5, 7.8, -0.8), Vector3(1.4, 7.9, 1.0)]
	for c in clumps:
		var mi := MeshInstance3D.new()
		var sp := SphereMesh.new()
		var r := rng.randf_range(1.7, 2.4)
		sp.radius = r
		sp.height = r * rng.randf_range(1.5, 1.8)
		sp.radial_segments = 20
		sp.rings = 10
		mi.mesh = sp
		mi.material_override = leaves
		mi.position = c + lean
		tree.add_child(mi)
	# Trunk collision.
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35
	cyl.height = 5.0
	cs.shape = cyl
	cs.position = Vector3(0.15, 2.5, 0.05)
	body.add_child(cs)
	tree.add_child(body)


func _limb(parent: Node3D, m: Material, a: Vector3, b: Vector3, r0: float, r1: float) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.bottom_radius = r0
	cm.top_radius = r1
	cm.height = a.distance_to(b)
	cm.radial_segments = 10
	cm.rings = 1
	mi.mesh = cm
	mi.material_override = m
	parent.add_child(mi)
	mi.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mi.basis = Basis(Quaternion(Vector3.UP, dir))


## Where you arrive, and the direction that faces the giant cloud.
func arrival() -> Vector3:
	return ground_at(0.0, 0.0) + Vector3(0, 0.05, 0)


func open_exit() -> void:
	await _door.open()


func _process(delta: float) -> void:
	if player == null:
		return
	var p := player.global_position
	if player.camera != null:
		storm.update(delta, player.camera, environment)
		if grass != null:
			grass.update(player.camera.global_position)
	# Ground mesh follows in 4 m steps (its heights come from world position).
	_ground.global_position = Vector3(snappedf(p.x, 4.0), FIELD_Y, snappedf(p.z, 4.0))
	var c := Vector2(roundf(p.x), roundf(p.z))
	if c.distance_to(_coll_centre) > 24.0:
		_update_collision(c)


func _update_collision(c: Vector2) -> void:
	_coll_centre = c
	var hm := _coll.shape as HeightMapShape3D
	var data := PackedFloat32Array()
	data.resize(COLL_N * COLL_N)
	var half := (COLL_N - 1) / 2
	for z in COLL_N:
		for x in COLL_N:
			data[x + z * COLL_N] = height(c.x + x - half, c.y + z - half)
	hm.map_data = data
	_coll.global_position = Vector3(c.x, FIELD_Y, c.y)


## Polar grid, dense near the centre and coarse toward the 6 km horizon.
func _make_ground_mesh() -> ArrayMesh:
	var radii := PackedFloat32Array([0.0])
	var r := 0.6
	while r < 6000.0:
		radii.push_back(r)
		r = r * 1.09 + 0.35
	radii.push_back(6000.0)
	var seg := 160
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var idx := PackedInt32Array()
	for ri in radii.size():
		for s in seg:
			var a := TAU * s / seg
			v.push_back(Vector3(cos(a) * radii[ri], 0.0, sin(a) * radii[ri]))
			n.push_back(Vector3.UP)
	for ri in radii.size() - 1:
		for s in seg:
			var a := ri * seg + s
			var b := ri * seg + (s + 1) % seg
			var c := (ri + 1) * seg + s
			var d := (ri + 1) * seg + (s + 1) % seg
			idx.append_array([a, c, b, b, c, d])   # clockwise seen from above = front
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_NORMAL] = n
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-6000, -10, -6000), Vector3(12000, 20, 12000))
	return m


func _make_environment(low: bool) -> Environment:
	var e := Environment.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/field_sky.gdshader")
	sky_mat.set_shader_parameter("noise", _noise_fine)
	sky_mat.set_shader_parameter("steps", 5 if low else 9)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	sky.radiance_size = Sky.RADIANCE_SIZE_64
	sky.process_mode = Sky.PROCESS_MODE_INCREMENTAL
	e.background_mode = Environment.BG_SKY
	e.sky = sky
	# Lit by the storm's sky itself (its shader carries the camera's
	# exposure): the dark base overhead, the bright horizon under it.
	e.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	e.ambient_light_energy = 1.0
	e.ambient_light_sky_contribution = 1.0
	e.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	# The near things' air (FieldStorm sets its density and colour); the
	# ground, the sky and the tornado do their own.
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_sky_affect = 0.0
	e.fog_aerial_perspective = 0.0
	EnvironmentFactory.lucid_grade(e)
	e.tonemap_exposure = float(Settings.get_value("graphics/brightness"))
	e.adjustment_enabled = true
	e.glow_enabled = bool(Settings.get_value("graphics/bloom"))
	return e


static func _noise(size: int, freq: float, octaves: int, seed_value: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.frequency = freq
	n.fractal_octaves = octaves
	n.seed = seed_value
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	return t
