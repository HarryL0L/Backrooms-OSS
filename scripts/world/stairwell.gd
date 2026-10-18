class_name Stairwell
extends Node3D
## A closed concrete stairwell between the floors of the Backrooms.
##
## The shaft fills a block of STAIR_W x STAIR_D cells (WorldGen.stair_block)
## and is the same on every floor. Switchback flights: from the landing at
## the door, flight A runs east and down to a half landing, flight B runs back
## west and down to the next landing; going up is the same in reverse. Every
## flight and landing is a solid slab and a full-height wall splits the two
## flights, so from anywhere on the stairs you only see a few metres of the
## shaft, which looks the same from one floor to the next.
##
## That's what makes the floors seamless: only the floor you're on is built.
## Once you're past the half landing (more than half a floor down or up),
## Stairwells moves you up or down by one floor height and the game swaps in
## the next floor's world. The shaft around you is identical, so nothing
## visibly changes. The door on your landing stays shut until the floor
## around it is built.
##
## Built five storeys tall (two above, two below), so the shaft is complete
## within sight wherever you are on it. Only the door at your floor's landing
## opens; the others are always shut.

const CELL := WorldGen.CELL
const H := WorldGen.FLOOR_H
const SX := WorldGen.STAIR_W * CELL      # 7.2 m
const SZ := WorldGen.STAIR_D * CELL      # 4.8 m
const W0 := ChunkBuilder.T + 0.015       # inner wall faces, just inside the world's walls
const LAND := 1.55                        # main landing depth (x)
const MID := SX - W0 - 1.5                # where the half landing starts (x)
const SPLIT := SZ * 0.5                   # the wall between the two flights (z)
const STEPS := 12
const STOREYS := 2                        # above and below
const DOOR_Z0 := CELL * 0.5 - 0.55        # matches the world's E_DOOR (1.1 x 2.1 m)
const DOOR_Z1 := CELL * 0.5 + 0.55
const DOOR_H := 2.1

const C_CONCRETE := Color(0.5, 0.49, 0.46)
const C_WALL := Color(0.66, 0.65, 0.58)
const C_DADO := Color(0.42, 0.45, 0.4)
const C_DOOR := Color(0.36, 0.4, 0.37)
const C_NOSING := Color(0.72, 0.62, 0.22)

static var _mesh: ArrayMesh
static var _mat: ShaderMaterial
static var _shapes := []          # [Shape3D, Transform3D]

var block: Vector2i
var _door: Node3D
var _door_open := 0.0
var _door_block: CollisionShape3D
var _labels: Array[Label3D] = []
var _rng := RandomNumberGenerator.new()


func setup(p_block: Vector2i) -> void:
	block = p_block
	position = Vector3(block.x * CELL, 0.0, block.y * CELL)


func _ready() -> void:
	if _mesh == null:
		_build_shared()
	var mi := MeshInstance3D.new()
	mi.mesh = _mesh
	mi.material_override = _mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	mi.set_instance_shader_parameter("origin", position)
	var body := StaticBody3D.new()
	for s in _shapes:
		var cs := CollisionShape3D.new()
		cs.shape = s[0]
		cs.transform = s[1]
		body.add_child(cs)
	# Your landing's door blocks the way while it's shut.
	_door_block = CollisionShape3D.new()
	var db := BoxShape3D.new()
	db.size = Vector3(ChunkBuilder.T * 2.0, DOOR_H, DOOR_Z1 - DOOR_Z0)
	_door_block.shape = db
	_door_block.position = Vector3(0.0, DOOR_H * 0.5, (DOOR_Z0 + DOOR_Z1) * 0.5)
	body.add_child(_door_block)
	add_child(body)
	# Doors: one per landing; only the one on this floor opens.
	for st in range(-STOREYS, STOREYS + 1):
		var d := _make_door()
		d.position = Vector3(ChunkBuilder.T * 0.5, st * H, DOOR_Z0)
		add_child(d)
		for m in d.find_children("*", "MeshInstance3D", true, false):
			(m as MeshInstance3D).set_instance_shader_parameter("origin", position)
		if st == 0:
			_door = d
		# The floor number, stencilled beside the door.
		var l := Label3D.new()
		l.font_size = 160
		l.pixel_size = 0.0035
		l.outline_size = 0
		l.modulate = Color(0.32, 0.3, 0.26)
		l.shaded = false
		l.double_sided = false
		l.position = Vector3(W0 + 0.005, st * H + 1.6, SZ - 1.1)
		l.rotation = Vector3(0, PI * 0.5, 0)
		add_child(l)
		_labels.append(l)
	# Bulbs: one over each landing and half landing.
	for p in lamp_positions():
		var b := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.07
		sm.height = 0.14
		b.mesh = sm
		var bm := StandardMaterial3D.new()
		bm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		bm.albedo_color = Color(1.0, 0.92, 0.75) * 1.6
		b.material_override = bm
		b.position = p
		add_child(b)


## The bulbs, in the stairwell's own coordinates.
static func lamp_positions() -> PackedVector3Array:
	var lamps := PackedVector3Array()
	for st in range(-STOREYS, STOREYS + 1):
		lamps.append(Vector3(0.75, st * H + 3.05, SZ - 1.0))
		lamps.append(Vector3(SX - 0.75, st * H - H * 0.5 + 3.05, SZ * 0.5))
	return lamps


## Writes the floor numbers for the floor you're on.
func set_floor(f: int) -> void:
	for i in _labels.size():
		_labels[i].text = WorldGen.floor_name(f + i - STOREYS)


## Opens the door on your landing (when the floor beyond is ready).
func update_door(delta: float, player_pos: Vector3, world_ready: bool) -> void:
	var local := player_pos - position
	var near := Vector2(local.x, local.z - CELL * 0.5).length() < 2.1 and absf(local.y) < 1.5
	var target := 1.0 if near and world_ready else 0.0
	_door_open = move_toward(_door_open, target, delta * 1.6)
	_door.rotation.y = smoothstep(0.0, 1.0, _door_open) * deg_to_rad(100.0)
	_door_block.disabled = _door_open > 0.6


## True when p (world) is inside the shaft (or its doorway).
func contains(p: Vector3) -> bool:
	var l := p - position
	return l.x > -0.05 and l.x < SX and l.z > 0.0 and l.z < SZ


static func _make_door() -> Node3D:
	var hinge := Node3D.new()      # at the doorway's -z jamb, swings into the shaft
	var leaf := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.05, DOOR_H - 0.02, DOOR_Z1 - DOOR_Z0 - 0.02)
	leaf.mesh = bm
	leaf.position = Vector3(0.0, DOOR_H * 0.5, (DOOR_Z1 - DOOR_Z0) * 0.5)
	leaf.material_override = _door_material()
	hinge.add_child(leaf)
	# Push bar.
	var bar := MeshInstance3D.new()
	var bb := BoxMesh.new()
	bb.size = Vector3(0.06, 0.05, 0.8)
	bar.mesh = bb
	bar.position = Vector3(0.05, 1.0, (DOOR_Z1 - DOOR_Z0) * 0.5)
	bar.material_override = leaf.material_override
	hinge.add_child(bar)
	return hinge


static var _door_mat: ShaderMaterial


static func _door_material() -> ShaderMaterial:
	if _door_mat == null:
		_door_mat = ShaderMaterial.new()
		_door_mat.shader = load("res://shaders/stairwell.gdshader")
		_door_mat.set_shader_parameter("tint", C_DOOR)
		_door_mat.set_shader_parameter("use_tint", 1.0)
		_door_mat.set_shader_parameter("ambient", 0.3)     # lit from the halls too
		_door_mat.set_shader_parameter("lamps", lamp_positions())
	return _door_mat


# ------------------------------------------------------------- geometry ---

static func _build_shared() -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_shapes.clear()
	var top := (STOREYS + 1) * H
	var bottom := -(STOREYS + 1) * H
	var run := MID - LAND
	var rise := H * 0.5
	for s in range(-STOREYS, STOREYS + 1):
		var y0 := s * H
		# Landing at the door, and the half landing below it.
		_box(st, Vector3(W0, y0 - 0.3, W0), Vector3(LAND, y0, SZ - W0), C_CONCRETE, true)
		_box(st, Vector3(MID, y0 - rise - 0.3, W0), Vector3(SX - W0, y0 - rise, SZ - W0), C_CONCRETE, true)
		# Flight A: east and down, the door side. Flight B: west and down.
		for i in STEPS:
			var xa0 := LAND + run * i / STEPS
			var xa1 := LAND + run * (i + 1) / STEPS
			var ya := y0 - rise * (i + 1) / STEPS
			_box(st, Vector3(xa0, ya - 0.4, W0), Vector3(xa1, ya, SPLIT - 0.07), C_CONCRETE, false)
			_box(st, Vector3(xa0, ya - 0.012, W0), Vector3(xa0 + 0.05, ya + 0.002, SPLIT - 0.07), C_NOSING, false)
			var xb1 := MID - run * i / STEPS
			var xb0 := MID - run * (i + 1) / STEPS
			var yb := y0 - rise - rise * (i + 1) / STEPS
			_box(st, Vector3(xb0, yb - 0.4, SPLIT + 0.07), Vector3(xb1, yb, SZ - W0), C_CONCRETE, false)
			_box(st, Vector3(xb1 - 0.05, yb - 0.012, SPLIT + 0.07), Vector3(xb1, yb + 0.002, SZ - W0), C_NOSING, false)
		_ramp(Vector3(LAND, y0, W0), Vector3(MID, y0 - rise, SPLIT - 0.07))
		_ramp(Vector3(MID, y0 - rise, SPLIT + 0.07), Vector3(LAND, y0 - H, SZ - W0))
		# The west wall around the door, above it up to the next landing.
		_box(st, Vector3(0.0, y0 + DOOR_H, DOOR_Z0), Vector3(W0, y0 + H - 0.3, DOOR_Z1), C_WALL, true)
		# A darker painted band along the walls at each landing (dado).
		_box(st, Vector3(W0, y0, DOOR_Z1), Vector3(W0 + 0.004, y0 + 1.0, SZ - W0), C_DADO, false)
		_box(st, Vector3(W0, y0, W0), Vector3(W0 + 0.004, y0 + 1.0, DOOR_Z0), C_DADO, false)
	# The wall between the flights, full height.
	_box(st, Vector3(LAND, bottom, SPLIT - 0.07), Vector3(MID, top, SPLIT + 0.07), C_WALL, true)
	# Outer walls (the west one with a door gap at each landing).
	_box(st, Vector3(0.0, bottom, 0.0), Vector3(W0, top, DOOR_Z0), C_WALL, true)
	_box(st, Vector3(0.0, bottom, DOOR_Z1), Vector3(W0, top, SZ), C_WALL, true)
	_box(st, Vector3(0.0, bottom, DOOR_Z0), Vector3(W0, -STOREYS * H - 0.3, DOOR_Z1), C_WALL, true)
	_box(st, Vector3(SX - W0, bottom, 0.0), Vector3(SX, top, SZ), C_WALL, true)
	_box(st, Vector3(0.0, bottom, 0.0), Vector3(SX, top, W0), C_WALL, true)
	_box(st, Vector3(0.0, bottom, SZ - W0), Vector3(SX, top, SZ), C_WALL, true)
	_box(st, Vector3(0.0, top - 0.3, 0.0), Vector3(SX, top, SZ), C_CONCRETE, true)
	_box(st, Vector3(0.0, bottom, 0.0), Vector3(SX, bottom + 0.3, SZ), C_CONCRETE, true)
	st.generate_tangents()
	_mesh = st.commit()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/stairwell.gdshader")
	_mat.set_shader_parameter("lamps", lamp_positions())


static func _box(st: SurfaceTool, lo: Vector3, hi: Vector3, c: Color, collide: bool) -> void:
	var faces := [
		[Vector3.RIGHT, [Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.LEFT, [Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z)]],
		[Vector3.UP, [Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z)]],
		[Vector3.DOWN, [Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, lo.y, hi.z)]],
		[Vector3.BACK, [Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z)]],
		[Vector3.FORWARD, [Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z)]],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var q: Array = f[1]
		for k in [0, 2, 1, 0, 3, 2]:      # clockwise = front in Godot
			st.set_color(c)
			st.set_normal(n)
			var p: Vector3 = q[k]
			st.set_uv(Vector2(p.x + p.z, p.y))
			st.add_vertex(p)
	if collide:
		var bs := BoxShape3D.new()
		bs.size = hi - lo
		_shapes.append([bs, Transform3D(Basis(), (lo + hi) * 0.5)])


## Collision for a flight: a smooth slope under the steps (no stepping up
## edges), from the top edge `a` (x, y, z0) to the bottom edge `b` (x, y, z1).
static func _ramp(a: Vector3, b: Vector3) -> void:
	var d := Vector3(b.x - a.x, b.y - a.y, 0.0)
	var length := d.length()
	var xa := d / length
	var ya := Vector3(-xa.y, xa.x, 0.0)
	if ya.y < 0.0:
		ya = -ya
	var za := xa.cross(ya)
	var bs := BoxShape3D.new()
	var width := absf(b.z - a.z)
	bs.size = Vector3(length, 0.2, width)
	var mid := Vector3((a.x + b.x) * 0.5, (a.y + b.y) * 0.5, (a.z + b.z) * 0.5) - ya * 0.1
	_shapes.append([bs, Transform3D(Basis(xa, ya, za), mid)])
