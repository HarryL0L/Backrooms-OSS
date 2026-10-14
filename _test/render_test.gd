extends Node3D
# Dev harness: renders views of the world to PNG files.
var cm: ChunkManager
var cam: Camera3D
var gen: WorldGen
var shots := []
var frame := 0
var out_dir := OS.get_user_data_dir() + "/shots"

func _ready():
	DirAccess.make_dir_recursive_absolute(out_dir)
	var args := OS.get_cmdline_user_args()
	gen = WorldGen.new(int(args[0]) if args.size() > 0 else 12345)
	var mats := WorldMaterials.new()
	var env := WorldEnvironment.new()
	env.environment = load("res://scripts/world/environment_factory.gd").make()
	add_child(env)
	cm = ChunkManager.new()
	add_child(cm)
	cm.view_radius = 3
	cm.setup(gen, mats)
	cam = Camera3D.new()
	cam.fov = 75
	cam.far = 90
	add_child(cam)
	cm.target = cam
	# find shots: spawn + one per biome
	var sp := gen.spawn_position()
	shots.append([sp + Vector3(0, 1.6, 0), 0.0, "spawn"])
	shots.append([sp + Vector3(0, 1.6, 0), PI * 0.5, "spawn2"])
	var found := {}
	for r in range(1, 400):
		for k in 8:
			var a := k * PI / 4.0
			var c := gen.spawn_cell + Vector2i(int(cos(a) * r), int(sin(a) * r))
			var b := gen.biome_at(c.x, c.y)
			if b != 0 and not found.has(b) and gen.biome_at(c.x+3, c.y) == b and gen.biome_at(c.x-3, c.y) == b and gen.biome_at(c.x, c.y+3) == b and gen.biome_at(c.x, c.y-3) == b:
				found[b] = c
	for b in found:
		var c: Vector2i = found[b]
		shots.append([Vector3((c.x + 0.5) * 2.4, 1.6, (c.y + 0.5) * 2.4), 0.3, "biome%d" % b])
	for r in range(5, 300):
		var done := false
		for k in 16:
			var a := k * PI / 8
			var c := gen.spawn_cell + Vector2i(int(cos(a)*r), int(sin(a)*r))
			if gen.biome_at(c.x, c.y) == 1 and gen.pool_noise(c.x, c.y) and gen.biome_at(c.x+2,c.y)==1 and gen.biome_at(c.x-2,c.y)==1 and gen.biome_at(c.x,c.y+2)==1 and gen.biome_at(c.x,c.y-2)==1:
				var p := Vector3((c.x+0.5)*2.4, 0.82, (c.y+0.5)*2.4)
				shots.append([p, 0.0, "pool_in", -0.25])
				shots.append([p + Vector3(0, 0.8, 4.0), 0.0, "pool_above", -0.5])
				done = true
				break
		if done: break
	print("shots: ", shots.size())
	_next()

var idx := -1
var wait := 0
func _next():
	idx += 1
	if idx >= shots.size():
		get_tree().quit()
		return
	cam.global_position = shots[idx][0]
	cam.rotation = Vector3(shots[idx][3] if shots[idx].size() > 3 else 0.0, shots[idx][1], 0)
	wait = 0

func _process(_d):
	if idx >= shots.size():
		return
	wait += 1
	if cm.is_area_ready(cam.global_position, 2) and wait > 20:
		var img := get_viewport().get_texture().get_image()
		img.save_png("%s/%s.png" % [out_dir, shots[idx][2]])
		print("saved ", shots[idx][2], " chunks=", cm.loaded_count(), " frames=", wait)
		_next()
	elif wait > 3000:
		print("timeout ", shots[idx][2])
		_next()
