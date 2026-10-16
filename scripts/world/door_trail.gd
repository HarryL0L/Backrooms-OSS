class_name DoorTrail
extends Node3D
## Clues that lead to a mysterious door, along the real route through the
## maze (a breadth-first search out from the door's room, done on a worker
## thread):
##  - painted arrows on the walls (sky blue for the Field, red marker for
##    the mall), left by earlier wanderers, every few rooms
##    and at every junction, with a little drawing beside them: a sun for the
##    Field, a music note for the Dead Mall;
##  - things on the floor that get thicker the closer you are: dry grass and
##    leaves blown in from the Field, or receipts, tickets and a shopping bag
##    from the mall.
## Everything is two MultiMeshes (arrows, litter): two draw calls per door.

const REACH := 30              # rooms (cells) the arrows reach out to
const LITTER_REACH := 14
const PASSABLE := [WorldGen.E_OPEN, WorldGen.E_DOOR, WorldGen.E_ARCH, WorldGen.E_GATE]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var mall := false
var _task := -1
var _result := {}
var _arrow_mm: MultiMesh
static var _tex := {}
## "m|cell" / "f|cell" -> [trail instance id, distance, arrow index]: one arrow of a kind per
## room, from whichever door of that kind is nearer, so trails never argue.
static var _claims := {}
static var _mat := {}


## Starts the route search (worker thread). `door_cell` is the room the door
## opens into.
func start(gen: WorldGen, door_cell: Vector2i, is_mall: bool, seed_value: int) -> void:
	mall = is_mall
	top_level = true
	_task = WorkerThreadPool.add_task(_compute.bind(gen, door_cell, seed_value))


func _process(_delta: float) -> void:
	if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
		_build()
		set_process(false)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)
		_task = -1
	var me := get_instance_id()
	for k in _claims.keys():
		if _claims[k][0] == me:
			_claims.erase(k)


static func _open(g: WorldGen, a: Vector2i, b: Vector2i) -> bool:
	var bb := g.biome_at(b.x, b.y)
	if g.is_solid(b.x, b.y, bb) or bb == WorldGen.POOL:
		return false
	var ba := g.biome_at(a.x, a.y)
	var kind: int
	if a.x != b.x:
		var line := maxi(a.x, b.x)
		kind = g.edge_kind(line, a.y, true, g.biome_at(line - 1, a.y), g.biome_at(line, a.y))
	else:
		var line := maxi(a.y, b.y)
		kind = g.edge_kind(line, a.x, false, g.biome_at(a.x, line - 1), g.biome_at(a.x, line))
	return ba != WorldGen.POOL and kind in PASSABLE


func _compute(g: WorldGen, start_cell: Vector2i, seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	# Stay in the door's own level: wanderers marked the Lobby, not the
	# pipes or the concrete halls next to it.
	var home := g.biome_at(start_cell.x, start_cell.y)
	var dist := {start_cell: 0}
	var toward := {}           # cell -> next cell on the way to the door
	var queue: Array[Vector2i] = [start_cell]
	var head := 0
	while head < queue.size():
		var c := queue[head]
		head += 1
		var d: int = dist[c]
		if d >= REACH:
			continue
		for dv in DIRS:
			var n: Vector2i = c + dv
			if dist.has(n) or g.biome_at(n.x, n.y) != home or not _open(g, c, n):
				continue
			dist[n] = d + 1
			toward[n] = c
			queue.append(n)
	var arrows := []           # [Transform3D, light]
	var litter := []           # [Transform3D, tile, light]
	var C := WorldGen.CELL
	for c in dist:
		var d: int = dist[c]
		if d == 0 or not toward.has(c):
			continue
		var nxt: Vector2i = toward[c]
		var dv: Vector2i = nxt - c
		var exits := 0
		for e in DIRS:
			if _open(g, c, c + e):
				exits += 1
		var light := clampf(g.light_level_near(Vector3((c.x + 0.5) * C, 1.4, (c.y + 0.5) * C)) * 0.35, 0.08, 1.0)
		# Arrows: every fourth room, and at most junctions.
		if d >= 2 and (d % 4 == 0 or (exits >= 3 and rng.randf() < 0.6)):
			var sides := [Vector2i(-dv.y, dv.x), Vector2i(dv.y, -dv.x)]
			for s: Vector2i in sides:
				if _open(g, c, c + s):
					continue                # no wall on that side
				var centre := Vector3((c.x + 0.5) * C, 0.0, (c.y + 0.5) * C)
				var nrm := -Vector3(s.x, 0, s.y)              # wall faces into the room
				# Mall marks sit low, Field marks high (and a hair further out),
				# so two trails crossing on one wall never overlap.
				var p := centre - nrm * (C * 0.5 - (0.1 if mall else 0.11))
				var along := Vector3(dv.x, 0, dv.y)
				p += along * rng.randf_range(-0.3, 0.3)
				p.y = rng.randf_range(0.85, 1.1) if mall else rng.randf_range(1.5, 1.75)
				var tilt := rng.randf_range(-0.12, 0.12)
				var up := Vector3.UP.rotated(nrm, tilt)
				var x := along.rotated(nrm, tilt)
				arrows.append([Transform3D(Basis(x * 0.8, up * 0.4, nrm), p), c, d, light])
				break
		# Litter: thicker near the door.
		if d <= LITTER_REACH:
			var n := int(roundf(3.2 * (1.0 - float(d) / LITTER_REACH) + rng.randf_range(-0.4, 0.8)))
			for k in maxi(n, 0):
				var p := Vector3((c.x + rng.randf_range(0.12, 0.88)) * C, 0.006 + k * 0.0015, (c.y + rng.randf_range(0.12, 0.88)) * C)
				var size := rng.randf_range(0.12, 0.26)
				var tile := rng.randi() % 4
				if mall and tile == 3:
					size *= 1.8              # the shopping bag
				var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis(Vector3.RIGHT, -PI * 0.5)
				litter.append([Transform3D(b.scaled(Vector3(size, size, size)), p), tile, light])
	_result = {"arrows": arrows, "litter": litter}


func _build() -> void:
	var litter: Array = _result.get("litter", [])
	var arrows := []
	var me := get_instance_id()
	for a: Array in _result.get("arrows", []):
		var key := "%s|%s" % ["m" if mall else "f", a[1]]
		var cl: Array = _claims.get(key, [])
		if not cl.is_empty() and cl[0] != me and is_instance_id_valid(cl[0]):
			if cl[1] <= a[2]:
				continue
			(instance_from_id(cl[0]) as DoorTrail)._hide_arrow(cl[2])   # we're nearer: take the wall
		_claims[key] = [me, a[2], arrows.size()]
		arrows.append(a)
	if arrows.size() > 0:
		var ami := _multimesh(arrows, "arrow_mall" if mall else "arrow_field", false)
		_arrow_mm = ami.multimesh
		add_child(ami)
	if litter.size() > 0:
		add_child(_multimesh(litter, "litter_mall" if mall else "litter_field", true))


func _hide_arrow(i: int) -> void:
	if _arrow_mm and i < _arrow_mm.instance_count:
		_arrow_mm.set_instance_transform(i, Transform3D(Basis().scaled(Vector3.ZERO), Vector3.ZERO))


func _multimesh(items: Array, tex_name: String, tiles: bool) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.use_custom_data = tiles
	var q := QuadMesh.new()
	q.size = Vector2(1, 1)
	mm.mesh = q
	mm.instance_count = items.size()
	for i in items.size():
		var it: Array = items[i]
		mm.set_instance_transform(i, it[0])
		var lv: float = it[-1]
		mm.set_instance_color(i, Color(lv, lv, lv))
		if tiles:
			mm.set_instance_custom_data(i, Color(float(it[1]), 0, 0, 0))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.material_override = _material(tex_name, tiles)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


static func _material(tex_name: String, tiles: bool) -> ShaderMaterial:
	if _mat.has(tex_name):
		return _mat[tex_name]
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/clue.gdshader")
	sm.set_shader_parameter("tex", texture(tex_name))
	sm.set_shader_parameter("tiles", 4.0 if tiles else 1.0)
	_mat[tex_name] = sm
	return sm


# ------------------------------------------------------------- textures ---
## Drawn once in code: chalk arrows with a sun or a note, and 4-tile atlases
## of floor litter.
static func texture(name: String) -> ImageTexture:
	if _tex.has(name):
		return _tex[name]
	var img: Image
	match name:
		"arrow_field", "arrow_mall":
			img = _arrow(name == "arrow_mall")
		"litter_field":
			img = _litter(false)
		_:
			img = _litter(true)
	img.generate_mipmaps()
	var t := ImageTexture.create_from_image(img)
	_tex[name] = t
	return t


static func _chalk(img: Image, a: Vector2, b: Vector2, w: float, rng: RandomNumberGenerator, col := Color(0.93, 0.93, 0.9)) -> void:
	# Solid, slightly ragged strokes (round stamps along the line) so the
	# mipmaps keep their coverage and the marks read from across a room.
	var n := int(a.distance_to(b) / 1.0) + 1
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		var r := w * rng.randf_range(0.8, 1.15)
		for y in range(int(p.y - r - 1), int(p.y + r + 2)):
			for x in range(int(p.x - r - 1), int(p.x + r + 2)):
				if x < 0 or y < 0 or x >= img.get_width() or y >= img.get_height():
					continue
				if Vector2(x + 0.5, y + 0.5).distance_to(p) > r:
					continue
				var c := img.get_pixel(x, y)
				var k := rng.randf_range(0.85, 1.0)
				img.set_pixel(x, y, Color(col.r * k, col.g * k, col.b * k, maxf(c.a, rng.randf_range(0.7, 1.0))))


static func _arrow(is_mall: bool) -> Image:
	var img := Image.create(256, 128, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7 if is_mall else 3
	# Sky-blue paint (the colour of the Field door) or red marker (the mall),
	# both loud against the yellow wallpaper. Shaft and head, hand-drawn.
	var col := Color(0.62, 0.08, 0.06) if is_mall else Color(0.16, 0.42, 0.78)
	img.fill(Color(col.r, col.g, col.b, 0.0))     # no light fringe when filtered
	_chalk(img, Vector2(64, 66), Vector2(204, 62), 6.0, rng, col)
	_chalk(img, Vector2(206, 62), Vector2(168, 28), 6.0, rng, col)
	_chalk(img, Vector2(206, 62), Vector2(170, 98), 6.0, rng, col)
	if is_mall:
		# A music note (the muzak) by the tail.
		_chalk(img, Vector2(30, 24), Vector2(30, 98), 4.0, rng, col)
		_chalk(img, Vector2(30, 24), Vector2(50, 40), 4.0, rng, col)
		for k in 9:
			_chalk(img, Vector2(12, 94 + k * 1.4), Vector2(32, 94 + k * 1.4), 3.0, rng, col)   # filled head
	else:
		# A little sun by the tail.
		for k in 18:
			var a := TAU * k / 18.0
			_chalk(img, Vector2(26, 64), Vector2(26, 64) + Vector2(cos(a), sin(a)) * 10.0, 3.5, rng, col)
		for k in 8:
			var a := TAU * k / 8.0
			_chalk(img, Vector2(26, 64) + Vector2(cos(a), sin(a)) * 15.0, Vector2(26, 64) + Vector2(cos(a), sin(a)) * 22.0, 3.0, rng, col)
	return img


static func _litter(is_mall: bool) -> Image:
	var img := Image.create(256, 64, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11 if is_mall else 13
	for tile in 4:
		var ox := tile * 64
		if is_mall:
			match tile:
				0, 1:
					# Receipt: a long curled paper strip with faded print.
					for y in range(6, 58):
						for x in range(22, 42):
							var curl := 1.0 - 0.15 * sin(y * 0.2 + tile)
							img.set_pixel(ox + x, y, Color(0.92 * curl, 0.9 * curl, 0.84 * curl, 1.0))
					for r in range(10, 54, 4):
						for x in range(25, 25 + rng.randi_range(6, 13)):
							img.set_pixel(ox + x, r, Color(0.45, 0.45, 0.5, 1.0))
				2:
					# Ticket stub / price tag.
					for y in range(18, 46):
						for x in range(14, 50):
							img.set_pixel(ox + x, y, Color(0.85, 0.75, 0.3, 1.0) if x > 18 else Color(0.8, 0.2, 0.15, 1.0))
				3:
					# A flattened shopping bag with its logo band.
					for y in range(4, 60):
						for x in range(8, 56):
							var c := Color(0.82, 0.8, 0.74, 1.0)
							if y > 22 and y < 34:
								c = Color(0.5, 0.1, 0.08, 1.0)
							img.set_pixel(ox + x, y, c * (0.9 + 0.1 * rng.randf()))
		else:
			if tile < 2:
				# A dry leaf: an ellipse with a vein.
				var col := Color(0.55, 0.38, 0.15, 1.0) if tile == 0 else Color(0.62, 0.5, 0.2, 1.0)
				for y in 64:
					for x in 64:
						var u := (x - 32.0) / 24.0
						var v := (y - 32.0) / 12.0
						if u * u + v * v < 1.0:
							img.set_pixel(ox + x, y, col * (0.85 + 0.15 * rng.randf()))
				for x in range(10, 56):
					img.set_pixel(ox + x, 32, Color(0.35, 0.25, 0.1, 1.0))
			else:
				# Dry grass blades.
				for k in 6:
					var x0 := rng.randf_range(10, 54)
					var lean := rng.randf_range(-12, 12)
					for y in range(8, 58):
						var x := int(x0 + lean * (y - 8) / 50.0)
						for w in 2:
							img.set_pixel(ox + clampi(x + w, 0, 63), y, Color(0.66, 0.6, 0.32, 1.0))
	return img
