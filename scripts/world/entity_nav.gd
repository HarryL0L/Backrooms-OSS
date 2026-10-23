class_name EntityNav
extends RefCounted
## Grid paths for the things that walk the levels: from cell centre to cell
## centre through the openings between cells (never through walls, Level 1's
## racks and crates, or the parked cars), staying inside one level. Centre
## to centre crosses each edge at its middle, clear of the pillars on the
## grid's corners and inside any doorway.

const PASSABLE := [WorldGen.E_OPEN, WorldGen.E_DOOR, WorldGen.E_ARCH, WorldGen.E_GATE, WorldGen.E_PASS]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var gen: WorldGen
var biome := -1
var _edges := {}          # Vector3i(line, along, vertical) -> passable
var _cells := {}          # Vector2i -> walkable
var _car_regions := {}    # LobbyDetails regions whose cars are marked
var _cars := {}           # Vector2i -> true: a parked car stands here


func _init(p_gen: WorldGen, p_biome: int) -> void:
	gen = p_gen
	biome = p_biome


static func center(c: Vector2i) -> Vector3:
	return Vector3((c.x + 0.5) * WorldGen.CELL, 0.0, (c.y + 0.5) * WorldGen.CELL)


func cell_ok(c: Vector2i) -> bool:
	if _cells.has(c):
		return _cells[c]
	var b := gen.biome_at(c.x, c.y)
	var ok := b == biome and not gen.is_solid(c.x, c.y, b) and not gen.stair_zone(c.x, c.y, 0)
	if ok and b == WorldGen.CONCRETE:
		ok = not gen.rack_at(c.x, c.y) and not gen.crates_at(c.x, c.y)
	if ok and b == WorldGen.GARAGE:
		ok = not car_at(c)
	if _cells.size() > 50000:
		_cells.clear()
	_cells[c] = ok
	return ok


## A parked car (covered or not) stands in this car park cell.
func car_at(c: Vector2i) -> bool:
	var r := Vector2i(floori(float(c.x) / LobbyDetails.REGION), floori(float(c.y) / LobbyDetails.REGION))
	for dz in [0, -1]:          # a car starting in the region above reaches down into this one
		var rr: Vector2i = r + Vector2i(0, dz)
		if not _car_regions.has(rr):
			_car_regions[rr] = true
			var res := {}
			LobbyDetails._compute(gen, rr, res)
			for e in res.get("props", []):
				if e[1] == LobbyDetails.CAR or e[1] == LobbyDetails.SUV:
					var at: Vector3 = e[0]
					var gx := floori(at.x / WorldGen.CELL)
					var gz := floori((at.z - 2.6) / WorldGen.CELL)
					_cars[Vector2i(gx, gz)] = true
					_cars[Vector2i(gx, gz + 1)] = true
	return _cars.has(c)


## Whether you can step from cell a to the neighbouring cell b.
func step_ok(a: Vector2i, b: Vector2i) -> bool:
	if not cell_ok(b):
		return false
	var vertical := a.y == b.y
	var line := maxi(a.x, b.x) if vertical else maxi(a.y, b.y)
	var along := a.y if vertical else a.x
	var k := Vector3i(line, along, 1 if vertical else 0)
	if _edges.has(k):
		return _edges[k]
	var lo := Vector2i(line - 1, along) if vertical else Vector2i(along, line - 1)
	var hi := Vector2i(line, along) if vertical else Vector2i(along, line)
	var ok := gen.edge_kind(line, along, vertical, gen.biome_at(lo.x, lo.y), gen.biome_at(hi.x, hi.y)) in PASSABLE
	if _edges.size() > 100000:
		_edges.clear()
	_edges[k] = ok
	return ok


## Everywhere reachable from `from` within `radius` cells (at most `limit`
## cells): cell -> [previous cell, steps].
func flood(from: Vector2i, radius: int, limit := 1500) -> Dictionary:
	var seen := {from: [from, 0]}
	var queue: Array[Vector2i] = [from]
	var i := 0
	while i < queue.size() and seen.size() < limit:
		var c: Vector2i = queue[i]
		i += 1
		var n: int = seen[c][1]
		for d in DIRS:
			var nc: Vector2i = c + d
			if seen.has(nc) or absi(nc.x - from.x) > radius or absi(nc.y - from.y) > radius:
				continue
			if step_ok(c, nc):
				seen[nc] = [c, n + 1]
				queue.append(nc)
	return seen


## The cells to walk through (not including where you are) to reach `to`,
## from a flood(); empty when it can't be reached.
static func path_to(f: Dictionary, to: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not f.has(to):
		return out
	var c := to
	while f[c][0] != c:
		out.push_front(c)
		c = f[c][0]
	return out


## The walkable cell nearest c (c itself when it's walkable): a noise from a
## parked car comes from a cell nobody can stand in.
func nearest_ok(c: Vector2i, reach := 3) -> Vector2i:
	if cell_ok(c):
		return c
	for r in range(1, reach + 1):
		var best := Vector2i(1 << 30, 0)
		for dz in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dz)) != r:
					continue
				var n := c + Vector2i(dx, dz)
				if cell_ok(n) and (best.x == 1 << 30 or (n - c).length_squared() < (best - c).length_squared()):
					best = n
		if best.x != 1 << 30:
			return best
	return c


func path(from: Vector2i, to: Vector2i, radius: int) -> Array[Vector2i]:
	return path_to(flood(from, radius), to)
