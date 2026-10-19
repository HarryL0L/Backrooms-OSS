class_name LobbyDetails
extends Node3D
## The small things in the Yellow Halls, around the player:
##  - scattered electrical outlets, light switches and vent grilles low on
##    the walls, and empty mounts (a paler patch with screw holes where
##    something once hung);
##  - indents in the carpet where furniture stood once;
##  - now and then a dark, sodden patch of carpet: the floor under it is
##    rotten through. Step on it and it gives way (`floor_gave_way`);
##  - rare thin places in the walls, where the wallpaper's seam doesn't quite
##    line up: lean into one long enough and you clip through it, out of this
##    part of the halls entirely (`noclipped`);
##  - plastic trash bins and buckets left against the walls, as in the photo
##    the place is known from;
##  - things that copy an ordinary building and get it slightly wrong: exit
##    signs with the letters out of order, door plaques that make no sense,
##    doors with no doorway behind them (handle on the hinge side, or at knee
##    height), stairs that climb into the ceiling, a clock with thirteen hours
##    and no hands, outlets with three slots, switches upside down or out of
##    reach. None of it near where you start: the Lobby there is an ordinary
##    copy of an office. The further out (and the further up or down) you
##    go, the worse the copy gets, until things stick out of the walls, sink
##    into the floor and hang from the ceiling.
## Built per REGION x REGION cells on worker threads, one MultiMesh each.

signal floor_gave_way
signal noclipped

const REGION := 16
const TILES := 9       # outlet, switch, mount, vent, indents, sodden, seam, odd outlet, clock
enum { OUTLET, SWITCH, MOUNT, VENT, INDENT, SODDEN, SEAM, OUTLET_ODD, CLOCK }
enum { FAKE_DOOR, STAIRS_UP, DOOR_SUNK, DOOR_THROUGH }
## Signs read right near the start; further out the copy gets them wrong
## (more often the further you go).
const EXIT_ODD := ["EXTI", "EIXT", "XIT", "TIXE", "EXIT EXIT", "EXI"]
const PLAQUE_TEXT := ["ROOM 0", "214", "STAFF ONLY", "OFFICE", "STORAGE", "MEETING ROOM", "RESTROOM", "WAITING", "PRIVATE"]
const PLAQUE_ODD := ["ROOM 00", "ROOM -1", "STAFF OLNY", "OFIFCE", "STORGAE", "MEETNG ROOM", "WAITNG", "1/2", "PIRVATE",
		"NO EXIT", "THIS WAY", "ROOM ROOM", ""]
enum { BIN, BUCKET, CAR, SUV }
## SUV paint (linear): the original taupe, silver, black, navy, white, dark red, dark green.
const SUV_PAINT := [Color(0.32, 0.29, 0.25), Color(0.45, 0.46, 0.47), Color(0.02, 0.02, 0.022), Color(0.015, 0.025, 0.08),
		Color(0.7, 0.7, 0.68), Color(0.18, 0.01, 0.012), Color(0.04, 0.07, 0.05)]
## Seconds of pushing into a thin place before you're through.
const NOCLIP_TIME := 0.9

var gen: WorldGen
var target: Node3D
var _regions := {}         # Vector2i -> Node3D (or null while building)
var _tasks := {}           # Vector2i -> [task id, result dict]
var _scan := 0.0
var _thin := []           # [Area3D, wall normal] of the thin places nearby
var _push := 0.0
static var _mat: ShaderMaterial
static var _prop_mat: ShaderMaterial


func clear() -> void:
	for r in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[r][0])
	_tasks.clear()
	for r in _regions:
		if _regions[r]:
			_regions[r].queue_free()
	_regions.clear()


func _exit_tree() -> void:
	for r in _tasks:
		WorkerThreadPool.wait_for_task_completion(_tasks[r][0])
	_tasks.clear()


func _process(delta: float) -> void:
	if gen == null or target == null:
		return
	_check_thin(delta)
	for r in _tasks.keys():
		var t: Array = _tasks[r]
		if WorkerThreadPool.is_task_completed(t[0]):
			WorkerThreadPool.wait_for_task_completion(t[0])
			_tasks.erase(r)
			if _regions.has(r):
				_regions[r] = _build(t[1])
	_scan -= delta
	if _scan > 0.0:
		return
	_scan = 0.5
	var c := gen.cell_of(target.global_position)
	var rc := Vector2i(floori(float(c.x) / REGION), floori(float(c.y) / REGION))
	var keep := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var r := rc + Vector2i(dx, dz)
			keep[r] = true
			if not _regions.has(r):
				_regions[r] = null
				var res := {}
				_tasks[r] = [WorkerThreadPool.add_task(_compute.bind(gen, r, res)), res]
	for r in _regions.keys():
		if not keep.has(r) and not _tasks.has(r):
			if _regions[r]:
				_regions[r].queue_free()
			_regions.erase(r)


# --------------------------------------------------------------- placing ---
static func _compute(g: WorldGen, r: Vector2i, res: Dictionary) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = g.hashi(r.x, r.y, 1201)
	var C := WorldGen.CELL
	var items := []            # [Transform3D, tile, light]
	var sodden := Vector3.INF
	var thin := []
	var props := []            # [position, kind, light, yaw]
	var fakes := []            # [kind, face, normal, along, light, variant]
	var signs := []            # [position, normal, text, exit?, light]
	var stairs_done := false
	var dirs := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for j in REGION:
		for i in REGION:
			var gx := r.x * REGION + i
			var gz := r.y * REGION + j
			var cb := g.biome_at(gx, gz)
			if cb == WorldGen.GARAGE:
				_garage_cell(g, gx, gz, rng, props, signs)
				continue
			if cb != WorldGen.LOBBY or g.is_solid(gx, gz, WorldGen.LOBBY):
				continue
			var centre := Vector3((gx + 0.5) * C, 0.0, (gz + 0.5) * C)
			var light := clampf(g.light_level_near(centre + Vector3.UP * 1.2) * 0.22, 0.04, 0.8)
			var cx := chaos(g, gx, gz)
			# Far out, things have come loose: a bucket stuck upside down in
			# the ceiling, a bin sunk into the carpet.
			if rng.randf() < 0.004 * cx * cx:
				props.append([centre + Vector3(rng.randf_range(-0.6, 0.6), WorldGen.CEIL_H[WorldGen.LOBBY] + 0.14, rng.randf_range(-0.6, 0.6)),
						BUCKET, light, rng.randf() * TAU, Vector3(PI, 0, rng.randf_range(-0.2, 0.2))])
			elif rng.randf() < 0.004 * cx * cx:
				props.append([centre + Vector3(rng.randf_range(-0.6, 0.6), -rng.randf_range(0.2, 0.4), rng.randf_range(-0.6, 0.6)),
						BIN, light, rng.randf() * TAU, Vector3(rng.randf_range(-0.3, 0.3), 0, rng.randf_range(-0.3, 0.3))])
			var edges := g._cell_edges(gx, gz)       # W, E, N, S
			for k in 4:
				if edges[k] == WorldGen.E_DOOR or edges[k] == WorldGen.E_PASS:
					# Over and beside doorways: signs that don't quite work.
					var nd: Vector3 = dirs[k]
					var fd := centre - nd * (C * 0.5 - ChunkBuilder.T - 0.005)
					var top: float = WorldGen.DOOR_H[edges[k]]
					# Only between rooms of the Lobby: an office plaque by the way
					# into the car park makes no sense.
					var other := Vector2i(gx, gz) - Vector2i(int(nd.x), int(nd.z))
					if g.biome_at(other.x, other.y) != WorldGen.LOBBY:
						continue
					var sr := rng.randf() / maxf(cx, 0.001)
					var wrong := rng.randf() < 0.7 * cx * cx
					if sr < 0.07:
						var t: String = EXIT_ODD[rng.randi() % EXIT_ODD.size()] if wrong else "EXIT"
						signs.append([fd + Vector3.UP * (top + 0.22) + nd * 0.03, nd, t, true, light])
					elif sr < 0.14 and edges[k] == WorldGen.E_DOOR:
						var side := Vector3(-nd.z, 0, nd.x) * (0.85 if rng.randf() < 0.5 else -0.85)
						var t: String = PLAQUE_ODD[rng.randi() % PLAQUE_ODD.size()] if wrong else PLAQUE_TEXT[rng.randi() % PLAQUE_TEXT.size()]
						signs.append([fd + side + Vector3.UP * 1.5 + nd * 0.012, nd, t, false, light])
					continue
				if edges[k] != WorldGen.E_WALL:
					continue
				# The wall's inner face, looking into the cell.
				var n: Vector3 = dirs[k]           # W wall faces +X, E faces -X, ...
				var along := Vector3(-n.z, 0, n.x)
				var face := centre - n * (C * 0.5 - ChunkBuilder.T - 0.005)
				var roll := rng.randf()
				var tile := -1
				var size := Vector2.ZERO
				var h := 0.0
				var flip := false
				if roll < 0.11:
					tile = OUTLET
					size = Vector2(0.075, 0.115)
					h = 0.32
					var odd := rng.randf()
					if odd < 0.12 * cx:
						tile = OUTLET_ODD          # three slots, like a face
					elif odd < 0.2 * cx:
						h = rng.randf_range(2.3, 2.6)     # out of reach
				elif roll < 0.135:
					tile = SWITCH
					size = Vector2(0.075, 0.115)
					h = 1.22
					var odd := rng.randf()
					if odd < 0.15 * cx:
						flip = true                 # upside down
					elif odd < 0.3 * cx:
						h = 0.1 if rng.randf() < 0.5 else 2.5
				elif roll < 0.135 + 0.008 * cx:
					tile = CLOCK
					size = Vector2(0.34, 0.34)
					h = 2.2
				elif roll < 0.16:
					tile = MOUNT
					size = Vector2(rng.randf_range(0.35, 0.7), rng.randf_range(0.25, 0.5))
					h = rng.randf_range(1.3, 1.7)
				elif roll < 0.175:
					tile = VENT
					size = Vector2(0.3, 0.16)
					h = 0.2
				if thin.is_empty() and not g.near_spawn(gx, gz, 10) and rng.randf() < 0.0004 + 0.0016 * cx:
					thin = [face, n]
					var sp := face + Vector3.UP * 1.15 + n * 0.002
					items.append([Transform3D(Basis(along * 0.5, Vector3.UP * 2.2, n), sp), SEAM, light])
					continue
				# Bins and buckets stand against the wall.
				var pr := rng.randf()
				if pr < 0.012 or (pr > 0.99 and pr < 0.996):
					var kind := BIN if pr < 0.012 else BUCKET
					var off := 0.26 if kind == BIN else 0.2
					var tilt := Vector3.ZERO
					var sink := 0.0
					if rng.randf() < 0.5 * cx * cx:
						# Half in the wall, or half in the floor, a little askew.
						off = -0.02 if rng.randf() < 0.5 else off
						sink = rng.randf_range(0.0, 0.25)
						tilt = Vector3(rng.randf_range(-0.25, 0.25), 0, rng.randf_range(-0.25, 0.25))
					props.append([face + n * off + along * rng.randf_range(-0.7, 0.7) - Vector3.UP * sink, kind, light, rng.randf() * TAU, tilt])
				# Doors to nowhere, and stairs into the ceiling.
				var fr := rng.randf()
				if fr < 0.006 * cx:
					var kind := FAKE_DOOR
					var cr := rng.randf()
					if cr < 0.4 * cx * cx:
						kind = DOOR_SUNK if cr < 0.2 * cx * cx else DOOR_THROUGH
					fakes.append([kind, face, n, along, light, rng.randi() % 3])
					continue
				if fr > 1.0 - 0.003 * cx and not stairs_done:
					stairs_done = true
					fakes.append([STAIRS_UP, face, n, along, light, 0])
					continue
				if tile < 0:
					continue
				var p := face + along * rng.randf_range(-0.8, 0.8) + Vector3.UP * h
				var up := Vector3.DOWN if flip else Vector3.UP
				var ax := -along if flip else along
				items.append([Transform3D(Basis(ax * size.x, up * size.y, n), p), tile, light])
			# Furniture indents in the carpet.
			if rng.randf() < 0.03:
				var a := rng.randf() * TAU
				var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -PI * 0.5)
				var p := centre + Vector3(rng.randf_range(-0.5, 0.5), 0.004, rng.randf_range(-0.5, 0.5))
				items.append([Transform3D(b.scaled(Vector3(1.3, 0.75, 1.0)), p), INDENT, light])
			# One rotten patch in some regions, away from the start.
			if sodden == Vector3.INF and not g.near_spawn(gx, gz, 8) and rng.randf() < 0.0016:
				sodden = centre + Vector3(rng.randf_range(-0.3, 0.3), 0.005, rng.randf_range(-0.3, 0.3))
				var b2 := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5)
				items.append([Transform3D(b2.scaled(Vector3(1.5, 1.3, 1.0)), sodden), SODDEN, light])
	res["items"] = items
	res["sodden"] = sodden
	res["thin"] = thin
	res["props"] = props
	res["fakes"] = fakes
	res["signs"] = signs


func _build(res: Dictionary) -> Node3D:
	var root := Node3D.new()
	add_child(root)
	var items: Array = res.get("items", [])
	if items.size() > 0:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		var q := QuadMesh.new()
		q.size = Vector2(1, 1)
		mm.mesh = q
		mm.instance_count = items.size()
		for i in items.size():
			var it: Array = items[i]
			mm.set_instance_transform(i, it[0])
			var lv: float = it[2]
			mm.set_instance_color(i, Color(lv, lv, lv))
			mm.set_instance_custom_data(i, Color(float(it[1]), 0, 0, 0))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _material()
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
	var sp: Vector3 = res.get("sodden", Vector3.INF)
	if sp != Vector3.INF:
		var area := Area3D.new()
		var cs := CollisionShape3D.new()
		var sh := CylinderShape3D.new()
		sh.radius = 0.45
		sh.height = 0.6
		cs.shape = sh
		area.add_child(cs)
		area.position = sp + Vector3.UP * 0.3
		area.body_entered.connect(func(body: Node3D) -> void:
			if body is Player:
				floor_gave_way.emit())
		root.add_child(area)
	var th: Array = res.get("thin", [])
	if not th.is_empty():
		var a2 := Area3D.new()
		var cs2 := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = Vector3(0.9, 1.6, 0.9)
		cs2.shape = bx
		a2.add_child(cs2)
		a2.position = th[0] + th[1] * 0.4 + Vector3.UP * 0.9
		root.add_child(a2)
		_thin.append([a2, th[1]])
	var props: Array = res.get("props", [])
	if props.size() > 0:
		_build_props(root, props)
	for f in res.get("fakes", []):
		_build_fake(root, f)
	for s in res.get("signs", []):
		_build_sign(root, s)
	return root


## A door that isn't one (no doorway behind it), or stairs into the ceiling.
func _build_fake(root: Node3D, f: Array) -> void:
	var face: Vector3 = f[1]
	var n: Vector3 = f[2]
	var light: float = minf(float(f[4]) * 1.6, 1.0)
	var basis := Basis(Vector3.UP.cross(n), Vector3.UP, n)     # x along the wall, z out of it
	var body := StaticBody3D.new()
	root.add_child(body)
	match int(f[0]):
		FAKE_DOOR, DOOR_SUNK, DOOR_THROUGH:
			if int(f[0]) == DOOR_SUNK:
				face -= Vector3.UP * 0.9                    # half under the floor
			elif int(f[0]) == DOOR_THROUGH:
				# Sideways, sticking straight out through the wall.
				basis = Basis(Vector3.UP, PI * 0.5) * basis
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.06, 2.0, 0.9)
				cs.shape = bs
				cs.position = face + Vector3.UP * 1.0
				body.add_child(cs)
			var wood := Color(0.55, 0.45, 0.32)
			var trim := Color(0.82, 0.8, 0.72)
			_piece(root, face, basis, Vector3(0.0, 1.0, 0.025), Vector3(0.88, 2.0, 0.04), wood * light)
			# Casing round it.
			_piece(root, face, basis, Vector3(-0.48, 1.04, 0.015), Vector3(0.08, 2.08, 0.03), trim * light)
			_piece(root, face, basis, Vector3(0.48, 1.04, 0.015), Vector3(0.08, 2.08, 0.03), trim * light)
			_piece(root, face, basis, Vector3(0.0, 2.04, 0.015), Vector3(1.04, 0.08, 0.03), trim * light)
			# The handle: on the hinge side, at knee height, or both.
			var hx := 0.36
			var hy := 1.0
			match int(f[5]):
				0: hx = -0.36                  # where the hinges are
				1: hy = 0.38
				_:
					hx = -0.36
					hy = 1.75
			_piece(root, face, basis, Vector3(hx, hy, 0.07), Vector3(0.12, 0.03, 0.05), Color(0.7, 0.66, 0.5) * light)
		STAIRS_UP:
			# Eight steps up along the wall, the last one into the ceiling.
			var c := Color(0.5, 0.42, 0.26)
			for i in 8:
				var x0 := -1.0 + i * 0.25
				var hgt := (i + 1) * 0.375
				_piece(root, face, basis, Vector3(x0 + 0.125, hgt * 0.5, 0.48), Vector3(0.25, hgt, 0.95), c * light * (0.85 + 0.05 * (i % 2)))
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(0.25, hgt, 0.95)
				cs.shape = bs
				cs.transform = Transform3D(basis, face + basis * Vector3(x0 + 0.125, hgt * 0.5, 0.48))
				body.add_child(cs)


func _piece(root: Node3D, face: Vector3, basis: Basis, local: Vector3, size: Vector3, col: Color) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = _props_material()
	mi.transform = Transform3D(basis, face + basis * local)
	root.add_child(mi)
	mi.set_instance_shader_parameter("tint_light", Color(col.r, col.g, col.b, 1.0))


## An exit sign over a doorway (a lit box, the word not quite right), or a
## plaque beside a door.
func _build_sign(root: Node3D, s: Array) -> void:
	var p: Vector3 = s[0]
	var n: Vector3 = s[1]
	var exit: bool = s[3]
	var light: float = minf(float(s[4]) * 1.6, 1.0)
	var basis := Basis(Vector3.UP.cross(n), Vector3.UP, n)
	if s.size() > 5:
		# Stencilled straight onto a column.
		var lp := Label3D.new()
		lp.text = s[2]
		lp.font_size = 96
		# As wide as fits on the column's face (about 0.6 of a character's
		# height per character).
		lp.pixel_size = minf(0.0024, 0.6 / (maxf(lp.text.length(), 1) * 0.6 * 96.0))
		lp.outline_size = 0
		lp.shaded = false
		lp.double_sided = false
		lp.modulate = Color(0.12, 0.12, 0.11) if light > 0.15 else Color(0.5, 0.48, 0.42) * light * 3.0
		lp.transform = Transform3D(basis, p + n * 0.004)
		root.add_child(lp)
		return
	if exit:
		_piece(root, p - n * 0.03, basis, Vector3(0, 0, 0.03), Vector3(0.46, 0.17, 0.06), Color(0.86, 0.85, 0.8) * light)
	else:
		_piece(root, p - n * 0.008, basis, Vector3(0, 0, 0.004), Vector3(0.34, 0.11, 0.008), Color(0.2, 0.19, 0.17) * light)
	var l := Label3D.new()
	l.text = s[2]
	l.font_size = 64 if exit else 36
	l.pixel_size = 0.0022 if exit else 0.0017
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.modulate = Color(1.0, 0.18, 0.12) * 1.3 if exit else Color(0.9, 0.88, 0.8) * light
	l.transform = Transform3D(basis, p + n * (0.062 if exit else 0.006))
	root.add_child(l)


## The car park: now and then a car under a dust sheet in a bay, and bay
## numbers painted on the columns (not always in order).
static func _garage_cell(g: WorldGen, gx: int, gz: int, rng: RandomNumberGenerator, props: Array, signs: Array) -> void:
	var C := WorldGen.CELL
	var light := clampf(g.light_level_near(Vector3((gx + 0.5) * C, 1.2, (gz + 0.5) * C)) * 0.22, 0.04, 0.8)
	if posmod(gz, 4) == 0 and rng.randf() < 0.09 and _bay_clear(g, gx, gz):
		# Clear of the column at the bay's back corner.
		var shift := 0.2 if posmod(gx, 3) == 0 else (-0.2 if posmod(gx, 3) == 2 else 0.0)
		var at := Vector3((gx + 0.5) * C + shift + rng.randf_range(-0.06, 0.06), 0.0, gz * C + 2.6)
		# Most are under dust sheets; now and then one isn't (more often
		# damaged further out).
		var kind := SUV if rng.randf() < 0.25 else CAR
		props.append([at, kind, light, rng.randf_range(-0.05, 0.05) + (PI if rng.randf() < 0.5 else 0.0), Vector3.ZERO, false,
				g.light_dir_near(at + Vector3.UP * 0.8), rng.randf() < 0.15 + 0.5 * chaos(g, gx, gz),
				SUV_PAINT[rng.randi() % SUV_PAINT.size()]])
	if posmod(gx, 3) == 0 and posmod(gz, 4) == 0 and g.pillar_at(gx, gz, WorldGen.GARAGE) > 0.0:
		var cx := chaos(g, gx, gz)
		var num := posmod(gx / 3, 40) + 1
		var text := "%s-%02d" % [WorldGen.floor_name(g.floor_index), num]
		var odd := rng.randf()
		if odd < 0.25 * cx:
			text = ["%s-%02d" % [WorldGen.floor_name(g.floor_index), num - 1], "%s-??" % WorldGen.floor_name(g.floor_index),
					"%s-%02d" % [WorldGen.floor_name(g.floor_index - 1), num], "P-0", "%02d-%s" % [num, WorldGen.floor_name(g.floor_index)]][rng.randi() % 5]
		signs.append([Vector3(gx * C, 1.75, gz * C - 0.405), Vector3(0, 0, -1), text, false, light, true])


## A car fits in the bay at (gx, gz) (two cells deep): all car park, nothing
## solid, no wall or doorway across or beside it, not by a stairwell.
static func _bay_clear(g: WorldGen, gx: int, gz: int) -> bool:
	for dz in 2:
		var z := gz + dz
		if g.biome_at(gx, z) != WorldGen.GARAGE or g.is_solid(gx, z, WorldGen.GARAGE) or g.stair_zone(gx, z, 1) \
				or g.near_spawn(gx, z, 2):
			return false
		var e: Array = g._cell_edges(gx, z)       # W, E, N, S
		if e[0] == WorldGen.E_DOOR or e[1] == WorldGen.E_DOOR or e[3] != WorldGen.E_OPEN:
			return false
	return true


## How badly the copy has gone wrong here (0 near where you start, 1 far
## out). Other floors start worse.
static func chaos(g: WorldGen, gx: int, gz: int) -> float:
	var d := Vector2(gx - g.spawn_cell.x, gz - g.spawn_cell.y).length()
	return clampf((d - 14.0) / 110.0 + absf(g.floor_index) * 0.3, 0.0, 1.0)


## Pushing into a thin place for a moment takes you through it.
func _check_thin(delta: float) -> void:
	var p := target as Player
	if p == null:
		return
	var pushing := false
	for i in range(_thin.size() - 1, -1, -1):
		if not is_instance_valid(_thin[i][0]):
			_thin.remove_at(i)
			continue
		var a: Area3D = _thin[i][0]
		var n: Vector3 = _thin[i][1]
		if a.overlaps_body(p) and p.wish_dir.dot(-n) > 0.6 and p.controls_enabled:
			pushing = true
	_push = _push + delta if pushing else 0.0
	if _push > NOCLIP_TIME:
		_push = 0.0
		noclipped.emit()


## A car under a dust cover: Poly Haven's "Covered Car" (CC0, see
## assets/garage/LICENSE.md), re-lit with our own shader. Or an uncovered
## SUV you can open up (ParkedCar).
func _build_car(root: Node3D, body: StaticBody3D, e: Array) -> void:
	var light: float = minf(float(e[2]) * 1.6, 1.0)
	var xf := Transform3D(Basis(Vector3.UP, e[3]), e[0])
	var ldir: Vector3 = e[6]
	if e[1] == SUV:
		var pc := ParkedCar.new()
		pc.setup(light, e[7], e[8], ldir)
		# The model is long along X.
		pc.transform = xf * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3.ZERO)
		root.add_child(pc)
	else:
		var car: Node3D = _car_scene().instantiate()
		car.transform = xf
		root.add_child(car)
		for m in car.find_children("*", "MeshInstance3D", true, false):
			var mi := m as MeshInstance3D
			for i in mi.mesh.get_surface_count():
				mi.set_surface_override_material(i, _car_material(mi.mesh.surface_get_material(i)))
			mi.set_instance_shader_parameter("light", light)
			mi.set_instance_shader_parameter("light_dir", ldir)
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_car_shadow(root, xf, ldir)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(1.85, 1.45, 4.45)
	cs.shape = bs
	cs.transform = Transform3D(xf.basis, e[0] + Vector3.UP * 0.72)
	body.add_child(cs)


## Occlusion on the floor under a car (lightmaps are baked without the cars).
static func _car_shadow(root: Node3D, xf: Transform3D, ldir: Vector3) -> void:
	if _shadow_mat == null:
		_shadow_mat = ShaderMaterial.new()
		_shadow_mat.shader = load("res://shaders/car_shadow.gdshader")
		_shadow_mesh = PlaneMesh.new()
		_shadow_mesh.size = Vector2(3.6, 6.4)
	var mi := MeshInstance3D.new()
	mi.mesh = _shadow_mesh
	mi.material_override = _shadow_mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.transform = xf.translated_local(Vector3.UP * 0.012)
	# Leans away from the lights, in the plane's own axes.
	var l := xf.basis.inverse() * ldir
	mi.set_instance_shader_parameter("lean", -Vector2(l.x, l.z))
	root.add_child(mi)


static var _car_packed: PackedScene
static var _shadow_mat: ShaderMaterial
static var _shadow_mesh: PlaneMesh
static var _car_mats := {}


static func _car_scene() -> PackedScene:
	if _car_packed == null:
		_car_packed = load("res://assets/garage/covered_car.glb")
	return _car_packed


static func _car_material(src: Material) -> ShaderMaterial:
	if _car_mats.has(src):
		return _car_mats[src]
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/garage_car.gdshader")
	var sm := src as BaseMaterial3D
	if sm:
		m.set_shader_parameter("albedo_tex", sm.albedo_texture)
		m.set_shader_parameter("normal_tex", sm.normal_texture)
		m.set_shader_parameter("has_normal", 1.0 if sm.normal_texture else 0.0)
	_car_mats[src] = m
	return m


func _build_props(root: Node3D, props: Array) -> void:
	var meshes := [_cyl(0.21, 0.18, 0.62), _cyl(0.15, 0.12, 0.3)]
	var tints := [Color(0.42, 0.44, 0.43), Color(0.86, 0.85, 0.8)]
	var body := StaticBody3D.new()
	root.add_child(body)
	for e in props:
		if e[1] == CAR or e[1] == SUV:
			_build_car(root, body, e)
	for kind in 2:
		var list := props.filter(func(e: Array) -> bool: return e[1] == kind)
		if list.is_empty():
			continue
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.use_custom_data = true
		mm.mesh = meshes[kind]
		mm.instance_count = list.size()
		for i in list.size():
			var e: Array = list[i]
			var h: float = (meshes[kind] as CylinderMesh).height
			mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, e[3]), e[0] + Vector3.UP * h * 0.5))
			var lv: float = minf(float(e[2]) * 1.6, 1.0)
			var tilt: Vector3 = e[4] if e.size() > 4 else Vector3.ZERO
			if tilt != Vector3.ZERO:
				var b := Basis.from_euler(tilt) * Basis(Vector3.UP, e[3])
				mm.set_instance_transform(i, Transform3D(b, e[0] + b * (Vector3.UP * h * 0.5)))
			mm.set_instance_color(i, tints[kind] * lv)
			mm.set_instance_custom_data(i, Color(h * 0.5, 0, 0, 0))
			var cs := CollisionShape3D.new()
			var sh := CylinderShape3D.new()
			sh.radius = (meshes[kind] as CylinderMesh).top_radius
			sh.height = h
			cs.shape = sh
			cs.position = e[0] + Vector3.UP * h * 0.5
			body.add_child(cs)
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		mi.material_override = _props_material()
		root.add_child(mi)


static func _cyl(top: float, bottom: float, h: float) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = h
	c.radial_segments = 16
	c.rings = 1
	return c


static func _props_material() -> ShaderMaterial:
	if _prop_mat:
		return _prop_mat
	_prop_mat = ShaderMaterial.new()
	_prop_mat.shader = load("res://shaders/lobby_prop.gdshader")
	return _prop_mat


static func _material() -> ShaderMaterial:
	if _mat:
		return _mat
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/clue.gdshader")
	var tex := ImageTexture.create_from_image(_atlas())
	_mat.set_shader_parameter("tex", tex)
	_mat.set_shader_parameter("tiles", float(TILES))
	return _mat


# ---------------------------------------------------------------- atlas ---
static func _atlas() -> Image:
	const T := 64
	var img := Image.create(T * TILES, T, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var plate := Color(0.86, 0.83, 0.74, 1)
	var dark := Color(0.12, 0.11, 0.1, 1)
	# Outlet: plate, two slots, a ground hole, a screw.
	_rect(img, OUTLET * T + 4, 2, 56, 60, plate)
	for sx in [24, 38]:
		_rect(img, OUTLET * T + sx, 16, 3, 10, dark)
		_rect(img, OUTLET * T + sx, 38, 3, 10, dark)
	_rect(img, OUTLET * T + 29, 29, 6, 6, Color(0.6, 0.58, 0.52, 1))
	# Switch: plate with a toggle.
	_rect(img, SWITCH * T + 4, 2, 56, 60, plate)
	_rect(img, SWITCH * T + 26, 20, 12, 24, Color(0.78, 0.75, 0.66, 1))
	_rect(img, SWITCH * T + 28, 22, 8, 9, Color(0.92, 0.9, 0.82, 1))
	# Empty mount: a cleaner, slightly paler rectangle of wallpaper (it was
	# out of the light), ragged at the edges; screw holes.
	for y in T:
		for x in T:
			var e := minf(minf(x, T - 1 - x), minf(y, T - 1 - y)) + rng.randf_range(-1.5, 1.5)
			if e > 1.0:
				img.set_pixel(MOUNT * T + x, y, Color(0.76, 0.74, 0.48, 1.0))
	for p in [Vector2i(8, 8), Vector2i(54, 8), Vector2i(8, 54), Vector2i(54, 54)]:
		_rect(img, MOUNT * T + p.x, p.y, 3, 3, dark)
	# Vent grille.
	_rect(img, VENT * T + 2, 8, 60, 48, Color(0.7, 0.68, 0.6, 1))
	for y in range(13, 52, 6):
		_rect(img, VENT * T + 7, y, 50, 3, Color(0.2, 0.19, 0.17, 1))
	# Furniture indents: four flattened squares in the pile.
	for p in [Vector2i(4, 6), Vector2i(52, 6), Vector2i(4, 50), Vector2i(52, 50)]:
		_rect(img, INDENT * T + p.x, p.y, 8, 8, Color(0.2, 0.17, 0.08, 0.75))
	# Sodden patch: a dark, soaked blot with a lighter tide line.
	for y in T:
		for x in T:
			var d := Vector2(x - 31.5, y - 31.5).length() / 30.0 + rng.randf_range(-0.05, 0.05)
			if d < 1.0:
				var c := Color(0.2, 0.16, 0.07, 0.9) if d < 0.82 else Color(0.38, 0.32, 0.15, 0.8)
				img.set_pixel(SODDEN * T + x, y, c)
	# Seam: two strips of wallpaper that don't quite meet; a hairline gap
	# and one edge a shade lighter where it's lifted away from the wall.
	for y in T:
		var wob := int(round(sin(y * 0.4) * 0.6))
		_rect(img, SEAM * T + 31 + wob, y, 1, 1, Color(0.4, 0.37, 0.2, 0.55))
		_rect(img, SEAM * T + 32 + wob, y, 1, 1, Color(0.8, 0.77, 0.5, 0.4))
	# Odd outlet: three slots, the way a face has two eyes and a mouth.
	_rect(img, OUTLET_ODD * T + 4, 2, 56, 60, plate)
	_rect(img, OUTLET_ODD * T + 20, 16, 3, 10, dark)
	_rect(img, OUTLET_ODD * T + 41, 16, 3, 10, dark)
	_rect(img, OUTLET_ODD * T + 24, 40, 16, 3, dark)
	# Clock: thirteen marks round the dial, no hands.
	for y in T:
		for x in T:
			var d := Vector2(x - 31.5, y - 31.5).length()
			if d < 30.0:
				img.set_pixel(CLOCK * T + x, y, Color(0.88, 0.87, 0.82, 1) if d < 27.5 else Color(0.2, 0.19, 0.18, 1))
	for m in 13:
		var a := m * TAU / 13.0
		for r in range(19, 25):
			img.set_pixel(CLOCK * T + int(31.5 + cos(a) * r), int(31.5 + sin(a) * r), dark)
	_rect(img, CLOCK * T + 30, 30, 4, 4, dark)
	img.generate_mipmaps()
	return img


static func _rect(img: Image, x0: int, y0: int, w: int, h: int, c: Color) -> void:
	for y in range(y0, y0 + h):
		for x in range(x0, x0 + w):
			img.set_pixel(x, y, c)
