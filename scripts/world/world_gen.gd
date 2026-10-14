class_name WorldGen
extends RefCounted
## Deterministic description of the infinite world.
##
## Every query is a pure function of (seed, global cell coordinates). Chunks can
## therefore be generated in any order, on any thread, and always agree with
## their neighbours at the seams - exactly like Minecraft terrain columns.
##
## The world is a flat grid of square cells. Walls live on cell *edges*, lights
## at cell centres, pillars at cell *vertices*. Large Voronoi regions decide the
## "level" (biome) a cell belongs to, so the Lobby flows into the Poolrooms, the
## concrete Habitable Zone and the unlit halls without loading screens.

const CELL := 2.4
const CHUNK := 8
const CHUNK_SIZE := CELL * CHUNK
const REGION := 34.0

enum { LOBBY, POOL, CONCRETE, DARK }
const BIOME_COUNT := 4
const BIOME_NAMES := ["Level 0 - The Lobby", "Level 37 - The Poolrooms", "Level 1 - Habitable Zone", "Level 0.1 - The Unlit Halls"]

# Edge kinds.
const E_OPEN := 0
const E_WALL := 1
const E_DOOR := 2
const E_ARCH := 3
const E_GATE := 4
const DOOR_W := [0.0, 0.0, 1.1, 1.7, 1.7]
const DOOR_H := [0.0, 0.0, 2.1, 3.1, 2.7]

# Per-biome constants.
const CEIL_H := [2.7, 4.4, 3.6, 2.7]
const POOL_FLOOR := -0.8
const WATER_Y := -0.16
const LIGHT_COLOR := [Color(1.0, 0.92, 0.70), Color(0.90, 0.97, 1.0), Color(0.82, 0.90, 1.0), Color(1.0, 0.82, 0.58)]
const LIGHT_POWER := [3.0, 2.6, 5.0, 2.0]
const LIGHT_RADIUS := [7.5, 7.0, 10.5, 6.0]
const AMBIENT := [Color(0.06, 0.05, 0.03), Color(0.16, 0.18, 0.19), Color(0.018, 0.019, 0.021), Color(0.005, 0.004, 0.003)]
# Approximate colour of light after bouncing off the room surfaces.
const BOUNCE_TINT := [Color(0.95, 0.80, 0.45), Color(0.85, 0.95, 1.0), Color(0.65, 0.65, 0.65), Color(0.9, 0.75, 0.45)]

# Light states.
const L_NONE := 0
const L_ON := 1
const L_FLICKER := 2
const L_DEAD := 3

var seed_value: int
var spawn_cell: Vector2i


func _init(p_seed: int) -> void:
	seed_value = p_seed & 0x7FFFFFFF
	var sp := region_point(0, 0)
	spawn_cell = Vector2i(floori(sp.x), floori(sp.y))


# ---------------------------------------------------------------- hashing ---

func hashi(x: int, z: int, salt: int) -> int:
	var h: int = (x * 0x27d4eb2d) ^ (z * 0x165667b1) ^ (salt * 0x3c6ef372) ^ seed_value
	h &= 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0xFFFFFFFF
	return h ^ (h >> 15)


func rnd(x: int, z: int, salt: int) -> float:
	return float(hashi(x, z, salt) & 0xFFFFFF) / 16777216.0


func vnoise(x: float, z: float, salt: int) -> float:
	var ix := floori(x)
	var iz := floori(z)
	var fx := x - ix
	var fz := z - iz
	fx = fx * fx * (3.0 - 2.0 * fx)
	fz = fz * fz * (3.0 - 2.0 * fz)
	var a := rnd(ix, iz, salt)
	var b := rnd(ix + 1, iz, salt)
	var c := rnd(ix, iz + 1, salt)
	var d := rnd(ix + 1, iz + 1, salt)
	return lerpf(lerpf(a, b, fx), lerpf(c, d, fx), fz)


# ----------------------------------------------------------------- biomes ---

func region_point(rx: int, rz: int) -> Vector2:
	return Vector2((rx + 0.2 + 0.6 * rnd(rx, rz, 11)) * REGION, (rz + 0.2 + 0.6 * rnd(rx, rz, 12)) * REGION)


func region_biome(rx: int, rz: int) -> int:
	if rx == 0 and rz == 0:
		return LOBBY
	var r := rnd(rx, rz, 13)
	if r < 0.44:
		return LOBBY
	if r < 0.65:
		return POOL
	if r < 0.85:
		return CONCRETE
	return DARK


func biome_at(gx: int, gz: int) -> int:
	# Domain warp so region borders meander instead of being straight lines.
	var px := gx + 0.5 + (vnoise(gx * 0.11, gz * 0.11, 14) - 0.5) * 9.0
	var pz := gz + 0.5 + (vnoise(gx * 0.11, gz * 0.11, 15) - 0.5) * 9.0
	var rx := floori(px / REGION)
	var rz := floori(pz / REGION)
	var best := INF
	var bx := 0
	var bz := 0
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var p := region_point(rx + dx, rz + dz)
			var d := (p.x - px) * (p.x - px) + (p.y - pz) * (p.y - pz)
			if d < best:
				best = d
				bx = rx + dx
				bz = rz + dz
	return region_biome(bx, bz)


func near_spawn(gx: int, gz: int, r: int) -> bool:
	return absi(gx - spawn_cell.x) <= r and absi(gz - spawn_cell.y) <= r


## True when the cell is a sunken pool. Needs the four neighbour biomes so pools
## never touch a level boundary.
func pool_noise(gx: int, gz: int) -> bool:
	if near_spawn(gx, gz, 3):
		return false
	return vnoise(gx * 0.19, gz * 0.19, 21) > 0.56


func open_hall(gx: int, gz: int) -> bool:
	return vnoise(gx * 0.07, gz * 0.07, 42) > 0.66


# ------------------------------------------------------------------ edges ---

## Kind of the edge on grid line `line` at position `along`.
## vertical=true: edge between cells (line-1, along) and (line, along).
## vertical=false: edge between cells (along, line-1) and (along, line).
## ba/bb are the biomes of the two cells.
func edge_kind(line: int, along: int, vertical: bool, ba: int, bb: int) -> int:
	var ex := line if vertical else along
	var ez := along if vertical else line
	if near_spawn(ex, ez, 1) or (near_spawn(ex, ez, 2) and ba == bb):
		return E_OPEN
	var salt := 0 if vertical else 500
	if ba != bb:
		var seg := floori(along / 3.0)
		# Guarantee at least one passage per 3 cells of border.
		if posmod(along, 3) == hashi(line, seg, 40 + salt) % 3:
			return E_DOOR
		return E_DOOR if rnd(line, along, 41 + salt) < 0.15 else E_WALL
	var big := floori(along / 24.0)
	match ba:
		LOBBY, DARK:
			var dens := 0.16 + 0.52 * rnd(line, big, 43 + salt)
			if open_hall(ex, ez):
				dens *= 0.12
			if rnd(line, floori(along / 3.0), 44 + salt) >= dens:
				return E_OPEN
			var r := rnd(line, along, 45 + salt)
			if r < 0.08:
				return E_OPEN
			if r < 0.25:
				return E_DOOR
			return E_WALL
		POOL:
			var dens := 0.08 + 0.3 * rnd(line, big, 46 + salt)
			if rnd(line, floori(along / 4.0), 47 + salt) >= dens:
				return E_OPEN
			return E_ARCH if rnd(line, along, 48 + salt) < 0.4 else E_WALL
		CONCRETE:
			var dens := 0.04 + 0.22 * rnd(line, big, 49 + salt)
			if rnd(line, floori(along / 2.0), 50 + salt) >= dens:
				return E_OPEN
			return E_GATE if rnd(line, along, 51 + salt) < 0.3 else E_WALL
	return E_OPEN


## Size of a structural pillar at grid vertex (vx, vz), 0 for none.
## `b` is the biome of cell (vx, vz).
func pillar_at(vx: int, vz: int, b: int) -> float:
	if near_spawn(vx, vz, 1):
		return 0.0
	match b:
		CONCRETE:
			if posmod(vx, 3) == 0 and posmod(vz, 3) == 0:
				return 0.7
		LOBBY, DARK:
			if open_hall(vx, vz) and posmod(vx, 2) == 0 and posmod(vz, 2) == 0:
				return 0.42
		POOL:
			if vnoise(vx * 0.15, vz * 0.15, 52) > 0.62 and posmod(vx + vz, 2) == 0:
				return 0.55
			if rnd(vx, vz, 53) < 0.03:
				return 0.55
	return 0.0


# ----------------------------------------------------------------- lights ---

func light_state(gx: int, gz: int, b: int) -> int:
	var r := rnd(gx, gz, 31)
	match b:
		LOBBY:
			if posmod(gz, 2) != 0:
				return L_NONE
			if near_spawn(gx, gz, 2):
				return L_ON
			if r < 0.05:
				return L_DEAD
			return L_FLICKER if r < 0.10 else L_ON
		POOL:
			if posmod(gx + gz, 2) != 0:
				return L_NONE
			return L_DEAD if r < 0.03 else L_ON
		CONCRETE:
			if posmod(gx, 3) != 1 or posmod(gz, 3) != 1:
				return L_NONE
			if r < 0.2:
				return L_DEAD
			return L_FLICKER if r < 0.36 else L_ON
		DARK:
			if posmod(gz, 2) != 0:
				return L_NONE
			if r < 0.9:
				return L_DEAD
			return L_FLICKER if r < 0.96 else L_ON
	return L_NONE


## Seed used by the shaders / audio to flicker a light, always > 0.
func light_seed(gx: int, gz: int) -> float:
	return 1.0 + float(hashi(gx, gz, 32) & 0xFFFF)


## Global flicker function. Must stay in sync with `flicker()` in the shaders.
static func flicker(light_seed_value: float, t: float) -> float:
	var s := int(light_seed_value)
	var burst_slot := int(floor(t * 0.45 + light_seed_value * 0.37))
	var b := _ihash(s * 31 + burst_slot * 7919)
	if float(b & 0xFFFF) / 65535.0 < 0.72:
		return 1.0
	var fast := _ihash(s * 131 + int(floor(t * 14.0)) * 104729)
	var v := float(fast & 0xFFFF) / 65535.0
	return 0.0 if v < 0.45 else 0.55 + 0.45 * v


static func _ihash(x: int) -> int:
	var h := x & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	h = ((h ^ (h >> 16)) * 0x45d9f3b) & 0xFFFFFFFF
	return h ^ (h >> 16)


# ------------------------------------------------------------ main-thread ---

func cell_of(p: Vector3) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.z / CELL))


func spawn_position() -> Vector3:
	return Vector3((spawn_cell.x + 0.5) * CELL, 0.05, (spawn_cell.y + 0.5) * CELL)


## Rough local light level at a position (used by audio for the fluorescent hum).
func light_level_near(p: Vector3) -> float:
	var c := cell_of(p)
	var total := 0.0
	for dz in range(-2, 3):
		for dx in range(-2, 3):
			var gx := c.x + dx
			var gz := c.y + dz
			var b := biome_at(gx, gz)
			var s := light_state(gx, gz, b)
			if s == L_ON or s == L_FLICKER:
				var lp := Vector3((gx + 0.5) * CELL, CEIL_H[b], (gz + 0.5) * CELL)
				total += LIGHT_POWER[b] / (1.0 + lp.distance_squared_to(p) * 0.3)
	return total


## Nearest flickering light (for its buzzing sound). Returns [position, seed] or [].
func nearest_flicker(p: Vector3, radius_cells: int) -> Array:
	var c := cell_of(p)
	var best := INF
	var res := []
	for dz in range(-radius_cells, radius_cells + 1):
		for dx in range(-radius_cells, radius_cells + 1):
			var gx := c.x + dx
			var gz := c.y + dz
			var b := biome_at(gx, gz)
			if light_state(gx, gz, b) == L_FLICKER:
				var lp := Vector3((gx + 0.5) * CELL, CEIL_H[b] - 0.05, (gz + 0.5) * CELL)
				var d := lp.distance_squared_to(p)
				if d < best:
					best = d
					res = [lp, light_seed(gx, gz)]
	return res
