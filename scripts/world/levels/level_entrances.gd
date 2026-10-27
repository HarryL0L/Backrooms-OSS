class_name LevelEntrances
extends Node3D
## Puts the side levels' ways in into the world: in the Backrooms around
## the player (like OddDoors: each REGION x REGION cell area may hold one of
## each level's entrances, at a spot made from the world seed, so it's
## always in the same place for a given seed and floor), and in the Dead Mall
## when it's built (place_in_mall). What goes where comes from the levels'
## entrance specs (SideLevels.entrances()):
##  - "wall": on a wall facing into a cell of one of its biomes, on one of
##    its floors, clear of the start, the stairwells, pools, racks and car
##    bays (in the car park only the driving lanes have walls you can use);
##  - "floor": in the middle of such a cell (a hatch), or at the bottom of a
##    sunken pool ("pool": true);
##  - "mall": at one of MALL_SLOTS.
## The entrances (LevelEntrance) tell the game themselves when they're used.

const REGION := 20
const C := WorldGen.CELL
## Places in the Dead Mall for an entrance: [x, z, yaw] (at MallLevel.MALL_Y;
## yaw turns its front, +Z, to face into the mall). The department store's
## back wall has two staff doors (z -6 and +6); its side walls are bare.
const MALL_SLOTS := {
	"dept_back_n": [235.84, -6.0, -PI * 0.5],
	"dept_back_s": [235.84, 6.0, -PI * 0.5],
	"dept_side_n": [218.0, -12.98, 0.0],
	"dept_side_s": [218.0, 12.98, PI],
}

var gen: WorldGen
var target: Node3D
var _regions := {}          # Vector2i -> Array of LevelEntrance
var _scan := 0.0


## Each level's entrance specs with a salt of its own (so where one level's
## entrances go never depends on the other levels): [[id, spec, salt], ...].
static func specs() -> Array:
	var out := []
	var n := {}
	for e in SideLevels.entrances():
		var id: String = e[0]
		var k: int = n.get(id, 0)
		n[id] = k + 1
		out.append([id, e[1], 1500 + (id.hash() & 0x3FFF) * 8 + k * 97])
	return out


## The entrances in region `r` of world `g`: [{id, spec, pos, yaw, light}].
static func spots_in_region(g: WorldGen, r: Vector2i) -> Array:
	var out := []
	for e in specs():
		var spec: Dictionary = e[1]
		if spec["in"] != "backrooms":
			continue
		var salt: int = e[2]
		if g.floor_index < int(spec.floors[0]) or g.floor_index > int(spec.floors[1]):
			continue
		if g.rnd(r.x, r.y, salt) >= float(spec.chance):
			continue
		for attempt in 12:
			var gx := r.x * REGION + 2 + int(g.rnd(r.x, r.y, salt + 1 + attempt * 3) * (REGION - 4))
			var gz := r.y * REGION + 2 + int(g.rnd(r.x, r.y, salt + 2 + attempt * 3) * (REGION - 4))
			var side := int(g.rnd(r.x, r.y, salt + 3 + attempt * 3) * 4.0)
			var s := _try(g, gx, gz, side, spec)
			if s.is_empty():
				continue
			var clash := false
			for o in out:
				if (o.pos as Vector3).distance_to(s.pos) < 4.0:
					clash = true
			if clash:
				continue
			s.id = e[0]
			s.spec = spec
			out.append(s)
			break
	return out


## A spot for `spec` at cell (gx, gz) (`side`: which wall, W E N S), or {}.
static func _try(g: WorldGen, gx: int, gz: int, side: int, spec: Dictionary) -> Dictionary:
	var b := g.biome_at(gx, gz)
	if not (spec.biomes as Array).has(b):
		return {}
	if g.near_spawn(gx, gz, 4) or g.stair_zone(gx, gz, 2) or g.is_solid(gx, gz, b):
		return {}
	if b == WorldGen.GARAGE and posmod(gz, 4) < 2:
		return {}                 # a parking bay: there may be a car
	if b == WorldGen.CONCRETE and (g.rack_at(gx, gz) or g.crates_at(gx, gz)):
		return {}
	var pool := _pool_cell(g, gx, gz)
	var pos: Vector3
	var yaw := 0.0
	if spec.kind == "floor":
		if pool != bool(spec.pool):
			return {}
		pos = Vector3((gx + 0.5) * C, WorldGen.POOL_FLOOR if pool else 0.0, (gz + 0.5) * C)
		yaw = side * PI * 0.5
	else:
		if pool:
			return {}
		var e: Array = g._cell_edges(gx, gz)            # W, E, N, S
		if e[side] != WorldGen.E_WALL:
			return {}
		var t := ChunkBuilder.T + 0.02
		var ends: Array[Vector2i] = []
		match side:
			0:
				pos = Vector3(gx * C + t, 0.0, (gz + 0.5) * C)
				yaw = PI * 0.5
				ends = [Vector2i(gx, gz), Vector2i(gx, gz + 1)]
			1:
				pos = Vector3((gx + 1) * C - t, 0.0, (gz + 0.5) * C)
				yaw = -PI * 0.5
				ends = [Vector2i(gx + 1, gz), Vector2i(gx + 1, gz + 1)]
			2:
				pos = Vector3((gx + 0.5) * C, 0.0, gz * C + t)
				yaw = 0.0
				ends = [Vector2i(gx, gz), Vector2i(gx + 1, gz)]
			_:
				pos = Vector3((gx + 0.5) * C, 0.0, (gz + 1) * C - t)
				yaw = PI
				ends = [Vector2i(gx, gz + 1), Vector2i(gx + 1, gz + 1)]
		# Wide ones need the wall's ends clear of columns.
		if spec.look in ["double", "stairs", "lift"]:
			for v in ends:
				if g.pillar_at(v.x, v.y, g.biome_at(v.x, v.y)) != 0.0:
					return {}
	var light := clampf(g.light_level_near(pos + Vector3.UP * 1.2) * 0.22, 0.04, 0.8)
	return {"pos": pos, "yaw": yaw, "light": light, "cell": Vector2i(gx, gz)}


## A sunken pool cell of the Tiled Baths (as ChunkBuilder decides them).
static func _pool_cell(g: WorldGen, gx: int, gz: int) -> bool:
	var b := WorldGen.POOL
	return g.biome_at(gx, gz) == b and g.biome_at(gx - 1, gz) == b and g.biome_at(gx + 1, gz) == b \
			and g.biome_at(gx, gz - 1) == b and g.biome_at(gx, gz + 1) == b and g.pool_noise(gx, gz)


## Makes the entrance node for a spot (its own script if the spec names one).
static func make(id: String, spec: Dictionary, light: float) -> LevelEntrance:
	var e: LevelEntrance
	if spec.script != "" and ResourceLoader.exists(spec.script):
		e = (load(spec.script) as GDScript).new()
	else:
		e = LevelEntrance.new()
	e.dest = id
	e.spec = spec
	e.look = spec.look
	e.sign_text = spec.sign
	e.label = spec.label
	e.light = light
	return e


func _process(delta: float) -> void:
	if gen == null or target == null:
		return
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
			if _regions.has(r):
				continue
			var list := []
			for s in spots_in_region(gen, r):
				var e := make(s.id, s.spec, s.light)
				add_child(e)
				e.global_position = s.pos
				e.rotation.y = s.yaw
				list.append(e)
			_regions[r] = list
	for r in _regions.keys():
		if not keep.has(r):
			for e in _regions[r]:
				e.queue_free()
			_regions.erase(r)


func clear() -> void:
	for r in _regions:
		for e in _regions[r]:
			e.queue_free()
	_regions.clear()


## The mall's entrances (children of the mall, so they go with it).
func place_in_mall(mall: Node3D) -> void:
	for e in specs():
		var spec: Dictionary = e[1]
		if spec["in"] != "mall":
			continue
		if not MALL_SLOTS.has(spec.slot):
			push_warning("LevelEntrances: no mall slot '%s' (%s)" % [spec.slot, e[0]])
			continue
		var s: Array = MALL_SLOTS[spec.slot]
		var n := make(e[0], spec, 0.55)
		mall.add_child(n)
		n.global_position = Vector3(s[0], MallLevel.MALL_Y, s[1])
		n.rotation.y = s[2]


## The nearest loaded entrance (to level `id`, or any), or null.
func nearest(p: Vector3, id := "") -> LevelEntrance:
	var best: LevelEntrance = null
	for r in _regions:
		for e in _regions[r]:
			if (id == "" or e.dest == id) and (best == null or e.global_position.distance_to(p) < best.global_position.distance_to(p)):
				best = e
	return best


## Where the nearest entrance to level `id` is, searching outwards from
## `from` (up to `rings` regions away): {pos, yaw, light, id, spec} or {}.
static func find(g: WorldGen, id: String, from: Vector3, rings := 12) -> Dictionary:
	var c := g.cell_of(from)
	var rc := Vector2i(floori(float(c.x) / REGION), floori(float(c.y) / REGION))
	var best := {}
	for ring in rings + 1:
		for dz in range(-ring, ring + 1):
			for dx in range(-ring, ring + 1):
				if maxi(absi(dx), absi(dz)) != ring:
					continue
				for s in spots_in_region(g, rc + Vector2i(dx, dz)):
					if s.id == id and (best.is_empty() or (s.pos as Vector3).distance_to(from) < (best.pos as Vector3).distance_to(from)):
						best = s
		if not best.is_empty():
			return best
	return best
