class_name ChunkVisibility
extends RefCounted
## Which chunks you could possibly see: the rest aren't drawn. The world is
## a grid of rooms, so most of what's loaded is behind walls at any moment.
## A few times a second, rays are cast across the room grid from around your
## position, in every direction (so turning never reveals a hole), stopping
## at full walls and solid cells; the chunks they reach are visible.
##
## Runs on a worker thread. Our own (not the engine's occlusion culling)
## because that needs the Embree module, which 32-bit Android builds lack,
## and those older phones are the ones that need it most. Which grid edges
## block is remembered between runs (the world never changes).

const RAYS := 200
## Rays start from around you too, so a step to the side or round a corner
## doesn't wait for the next run.
const ORIGINS := [Vector2(0, 0), Vector2(1.1, 0), Vector2(-1.1, 0), Vector2(0, 1.1), Vector2(0, -1.1)]

var gen: WorldGen
var _blocks := {}          # Vector3i(x, z, vertical) -> bool (an edge is a full wall)
var _solid := {}           # Vector2i -> bool


func _init(p_gen: WorldGen) -> void:
	gen = p_gen


## The chunks seen from p (world) within `reach` metres. Thread-safe as long
## as only one call runs at a time.
func visible_from(p: Vector3, reach: float) -> Dictionary:
	var out := {}
	var C := WorldGen.CELL
	var cs := WorldGen.CHUNK
	for o in ORIGINS:
		var ox := p.x / C + (o as Vector2).x / C
		var oz := p.z / C + (o as Vector2).y / C
		var sx := floori(ox)
		var sz := floori(oz)
		if _cell_solid(sx, sz):
			continue
		var max_t := reach / C
		for r in RAYS:
			var a := TAU * r / RAYS
			var dx := cos(a)
			var dz := sin(a)
			# Grid traversal (Amanatides & Woo).
			var cx := sx
			var cz := sz
			var step_x := 1 if dx > 0.0 else -1
			var step_z := 1 if dz > 0.0 else -1
			var t_dx := absf(1.0 / dx) if absf(dx) > 1e-6 else INF
			var t_dz := absf(1.0 / dz) if absf(dz) > 1e-6 else INF
			var t_x := ((cx + 1 - ox) if dx > 0.0 else (ox - cx)) * t_dx
			var t_z := ((cz + 1 - oz) if dz > 0.0 else (oz - cz)) * t_dz
			out[Vector2i(floori(float(cx) / cs), floori(float(cz) / cs))] = true
			while true:
				var nx := cx
				var nz := cz
				var t := 0.0
				var vertical := true
				if t_x < t_z:
					t = t_x
					nx += step_x
					t_x += t_dx
				else:
					t = t_z
					nz += step_z
					t_z += t_dz
					vertical = false
				if t > max_t:
					break
				# The edge between (cx, cz) and (nx, nz).
				var line := maxi(cx, nx) if vertical else maxi(cz, nz)
				var along := cz if vertical else cx
				if _edge_blocks(line, along, vertical) or _cell_solid(nx, nz):
					break
				cx = nx
				cz = nz
				out[Vector2i(floori(float(cx) / cs), floori(float(cz) / cs))] = true
	return out


func _edge_blocks(line: int, along: int, vertical: bool) -> bool:
	var k := Vector3i(line, along, 1 if vertical else 0)
	if _blocks.has(k):
		return _blocks[k]
	var ax := line - 1 if vertical else along
	var az := along if vertical else line - 1
	var bx := line if vertical else along
	var bz := along if vertical else line
	var e := gen.edge_kind(line, along, vertical, gen.biome_at(ax, az), gen.biome_at(bx, bz))
	var b := e == WorldGen.E_WALL
	if _blocks.size() > 400000:
		_blocks.clear()
	_blocks[k] = b
	return b


func _cell_solid(x: int, z: int) -> bool:
	var k := Vector2i(x, z)
	if _solid.has(k):
		return _solid[k]
	var s := gen.is_solid(x, z, gen.biome_at(x, z))
	if _solid.size() > 200000:
		_solid.clear()
	_solid[k] = s
	return s
