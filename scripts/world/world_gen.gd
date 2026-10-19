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
## "level" (biome) a cell belongs to, so the Yellow Halls flow into the Tiled Baths, the
## concrete Grey Floors and the unlit halls without loading screens.

const CELL := 2.4
const CHUNK := 8
const CHUNK_SIZE := CELL * CHUNK
const REGION := 34.0

enum { LOBBY, POOL, CONCRETE, DARK, PIPES, GARAGE }
const BIOME_COUNT := 6
const BIOME_NAMES := ["Level 0 - The Lobby", "Level 37 - The Poolrooms", "Level 1 - Habitable Zone",
	"Level 0.1 - The Unlit Halls", "Level 2 - Pipe Dreams", "The Car Park"]

# Edge kinds.
const E_OPEN := 0
const E_WALL := 1
const E_DOOR := 2
const E_ARCH := 3
const E_GATE := 4
const E_WINDOW := 5
## A wide doorless opening cut through a wallpapered wall; in the Lobby they
## come in rows (an arcade), like the archways of the original 2002 photo.
const E_PASS := 6
const DOOR_W := [0.0, 0.0, 1.1, 1.7, 1.7, 0.95, 1.8]
const DOOR_H := [0.0, 0.0, 2.1, 3.1, 2.7, 3.95, 2.6]
# Sun gallery windows (Tiled Baths): absolute sill height (top is DOOR_H[E_WINDOW]).
const WIN_Y0 := 0.45

# Per-biome constants.
const CEIL_H := [3.0, 4.8, 3.6, 2.7, 2.7, 2.6]
const POOL_FLOOR := -0.8
const WATER_Y := -0.16
const LIGHT_COLOR := [Color(1.0, 0.97, 0.86), Color(1.0, 0.98, 0.94), Color(1.0, 0.91, 0.70), Color(1.0, 0.82, 0.58), Color(1.0, 0.88, 0.7), Color(0.86, 0.95, 1.0)]
const LIGHT_POWER := [3.2, 3.4, 5.0, 2.0, 3.4, 3.4]
const LIGHT_RADIUS := [7.5, 7.0, 10.5, 6.0, 7.0, 8.0]
const AMBIENT := [Color(0.07, 0.07, 0.045), Color(0.09, 0.10, 0.10), Color(0.018, 0.019, 0.021), Color(0.005, 0.004, 0.003), Color(0.012, 0.01, 0.008), Color(0.012, 0.013, 0.014)]
# Approximate colour of light after bouncing off the room surfaces.
const BOUNCE_TINT := [Color(0.9, 0.88, 0.55), Color(0.85, 0.95, 1.0), Color(0.72, 0.68, 0.56), Color(0.9, 0.75, 0.45), Color(0.6, 0.5, 0.42), Color(0.62, 0.63, 0.62)]
# Skylights in the Tiled Baths: warm "sunlight" pouring in from above.
const SKY_COLOR := Color(1.0, 0.9, 0.72)
const SKY_POWER := 5.0
const SKY_RADIUS := 10.5
# Sun galleries: long flooded halls lit by low sunlight through rows of tall
# windows. Windows sit on every GALLERY_STEP-th horizontal grid line; the sun
# shines in from the -Z side, so it lands on the +Z side of each window row.
const GALLERY_STEP := 5
const SUN_TRAVEL := Vector3(0.0, -0.62, 0.78)   # direction the sunlight travels (normalized in use)
const SUN_COLOR := Color(1.0, 0.96, 0.88)
const SUN_POWER := 2.6

# Light states.
const L_NONE := 0
const L_ON := 1
const L_FLICKER := 2
const L_DEAD := 3
const L_SKY := 4

var seed_value: int
## Which floor of the Backrooms this is (0 = where you start, below is
## negative). Every floor has its own layout; stairwells stand at the same
## place on all of them.
var floor_index := 0
var _floor_salt := 0
var spawn_cell: Vector2i
var _biome_cache := {}
var _main_thread := OS.get_main_thread_id()


func _init(p_seed: int, p_floor := 0) -> void:
	seed_value = p_seed & 0x7FFFFFFF
	floor_index = p_floor
	_floor_salt = (p_floor * 0x5bd1e995) & 0x7FFFFFFF
	var sp := region_point(0, 0)
	spawn_cell = Vector2i(floori(sp.x), floori(sp.y))


# ---------------------------------------------------------------- hashing ---

func hashi(x: int, z: int, salt: int) -> int:
	var h: int = (x * 0x27d4eb2d) ^ (z * 0x165667b1) ^ (salt * 0x3c6ef372) ^ seed_value ^ _floor_salt
	h &= 0xFFFFFFFF
	h = ((h ^ (h >> 15)) * 0x2c1b3c6d) & 0xFFFFFFFF
	h = ((h ^ (h >> 12)) * 0x297a2d39) & 0xFFFFFFFF
	return h ^ (h >> 15)


## Like hashi, but the same on every floor (for what floors share: stairs).
func hashb(x: int, z: int, salt: int) -> int:
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
	# The first floor down is a car park, mostly; further down there's
	# a car park now and then.
	var garage := 0.72 if floor_index == -1 else (0.15 if floor_index < -1 else 0.0)
	if r < garage:
		return GARAGE
	r = (r - garage) / (1.0 - garage)
	# Down, the floors get older and darker: fewer pools, more pipes and
	# unlit halls. Up, emptier and more like offices: more concrete floors.
	var down := clampf(-floor_index * 0.07, 0.0, 0.28)
	var up := clampf(floor_index * 0.07, 0.0, 0.28)
	var t_lobby := 0.40 - down * 0.4
	var t_pool := t_lobby + 0.22 - down * 0.5 - up * 0.5
	var t_conc := t_pool + 0.15 + up
	var t_pipes := t_conc + 0.11 + down * 0.4
	if r < t_lobby:
		return LOBBY
	if r < t_pool:
		return POOL
	if r < t_conc:
		return CONCRETE
	if r < t_pipes:
		return PIPES
	return DARK


## Biome of a cell. Main-thread callers (audio, entities, lights) ask about
## the same cells over and over, so their answers are cached; chunk builder
## threads compute directly (no shared mutable state between threads).
func biome_at(gx: int, gz: int) -> int:
	if OS.get_thread_caller_id() != _main_thread:
		return _biome_compute(gx, gz)
	var k := Vector2i(gx, gz)
	var v: int = _biome_cache.get(k, -1)
	if v < 0:
		v = _biome_compute(gx, gz)
		if _biome_cache.size() > 200000:
			_biome_cache.clear()
		_biome_cache[k] = v
	return v


func _biome_compute(gx: int, gz: int) -> int:
	# Around a stairwell it's always the Lobby, on every floor.
	if stair_zone(gx, gz, 3):
		return GARAGE if floor_index == -1 else LOBBY
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
	if gallery(gx, gz):
		return true
	return vnoise(gx * 0.11, gz * 0.11, 21) > 0.47


## Pipeworks is a maze of narrow service corridors cut through solid rock:
## corridors run along every 4th row/column, with random segments missing.
func is_solid(gx: int, gz: int, b: int) -> bool:
	if stair_zone(gx, gz, 0):
		return true            # the stairwell shaft
	if b != PIPES or near_spawn(gx, gz, 1):
		return false
	var cx := posmod(gx, 4) == 0 and rnd(gx, floori(gz / 6.0), 81) < 0.82
	var cz := posmod(gz, 4) == 0 and rnd(floori(gx / 6.0), gz, 82) < 0.82
	if cx or cz:
		return false
	# Occasional small rooms where pipes gather.
	return vnoise(gx * 0.3, gz * 0.3, 83) < 0.78


## Part of a sun gallery (only meaningful inside the Tiled Baths).
func gallery(gx: int, gz: int) -> bool:
	return vnoise(gx * 0.045, gz * 0.045, 58) > 0.6 and not near_spawn(gx, gz, 6)


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
	var ax := line - 1 if vertical else along
	var az := along if vertical else line - 1
	# The stairwell's door: the west wall of its block, first row.
	if vertical:
		var sb0 := stair_block_at(ex, ez)
		if sb0.x != NO_STAIRS and sb0 == Vector2i(ex, ez):
			return E_DOOR
	var sa := is_solid(ax, az, ba)
	var sb := is_solid(ex, ez, bb)
	if sa or sb:
		return E_OPEN if sa == sb else E_WALL
	if ba != bb:
		var seg := floori(along / 3.0)
		# Guarantee at least one passage per 3 cells of border.
		if posmod(along, 3) == hashi(line, seg, 40 + salt) % 3:
			return E_DOOR
		return E_DOOR if rnd(line, along, 41 + salt) < 0.15 else E_WALL
	var big := floori(along / 24.0)
	match ba:
		LOBBY, DARK:
			# Now and then a straight run of wall becomes a row of archways:
			# opening, pier, opening, pier...
			if ba == LOBBY and not open_hall(ex, ez) and rnd(line, floori(along / 8.0), 60 + salt) < 0.1:
				return E_PASS if posmod(along, 2) == 0 else E_WALL
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
			if gallery(ex, ez) and gallery(ax, az):
				# Long halls: rows of windows with an arch every few cells.
				if not vertical and posmod(line, GALLERY_STEP) == 0:
					return E_ARCH if posmod(along, 9) == 4 else E_WINDOW
				return E_OPEN
			var dens := 0.06 + 0.3 * rnd(line, big, 46 + salt)
			if rnd(line, floori(along / 5.0), 47 + salt) >= dens:
				return E_OPEN
			return E_ARCH if rnd(line, along, 48 + salt) < 0.6 else E_WALL
		GARAGE:
			# Open floor between the columns; a short wall here and there.
			return E_WALL if rnd(line, along, 55 + salt) < 0.03 else E_OPEN
		PIPES:
			# Bulkhead doorways now and then.
			return E_DOOR if rnd(line, along, 54 + salt) < 0.04 else E_OPEN
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
			# Warehouse columns, 0.8 m.
			if posmod(vx, 3) == 0 and posmod(vz, 3) == 0:
				return 0.8
		GARAGE:
			# Columns between every three parking bays, at the bays' backs:
			# 0.8 m square, the usual size holding up a car park deck.
			if posmod(vx, 3) == 0 and posmod(vz, 4) == 0:
				return 0.8
		LOBBY, DARK:
			# Office building columns, wallpapered, 0.6 m.
			if open_hall(vx, vz) and posmod(vx, 2) == 0 and posmod(vz, 2) == 0:
				return 0.6
		POOL:
			if gallery(vx, vz):
				return 0.0
			# Negative size = round column.
			if vnoise(vx * 0.15, vz * 0.15, 52) > 0.55 and posmod(vx, 2) == 0 and posmod(vz, 2) == 0:
				return -0.8
			if rnd(vx, vz, 53) < 0.03:
				return -0.8
	return 0.0


# ----------------------------------------------------------------- lights ---

func light_state(gx: int, gz: int, b: int) -> int:
	if stair_zone(gx, gz, 0):
		return L_NONE
	var r := rnd(gx, gz, 31)
	if b == GARAGE:
		# Tube lights down the middle of each lane, and over the bays.
		var r2 := rnd(gx, gz, 31)
		var lane := posmod(gz, 4) == 2 and posmod(gx, 2) == 0
		var bay := posmod(gz, 4) == 0 and posmod(gx, 3) == 1
		if not (lane or bay):
			return L_NONE
		if r2 < 0.12:
			return L_DEAD
		return L_FLICKER if r2 < 0.2 else L_ON
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
			if posmod(gx + gz, 2) != 0 or gallery(gx, gz):
				return L_NONE
			if posmod(gx, 4) == 0 and posmod(gz, 4) == 0 and vnoise(gx * 0.08, gz * 0.08, 33) > 0.55:
				return L_SKY
			return L_DEAD if r < 0.03 else L_ON
		PIPES:
			if is_solid(gx, gz, b) or posmod(gx + gz, 3) != 0:
				return L_NONE
			if r < 0.15:
				return L_DEAD
			return L_FLICKER if r < 0.25 else L_ON
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


## Kinds of the four edges round a cell (W, E, N, S).
func _cell_edges(gx: int, gz: int) -> Array:
	return [
		edge_kind(gx, gz, true, biome_at(gx - 1, gz), biome_at(gx, gz)),
		edge_kind(gx + 1, gz, true, biome_at(gx, gz), biome_at(gx + 1, gz)),
		edge_kind(gz, gx, false, biome_at(gx, gz - 1), biome_at(gx, gz)),
		edge_kind(gz + 1, gx, false, biome_at(gx, gz), biome_at(gx, gz + 1)),
	]


## Seed used by the shaders / audio to flicker a light, always > 0.
func light_seed(gx: int, gz: int) -> float:
	return 1.0 + float(hashi(gx, gz, 32) & 0x7FFF)     # fits the 16-bit lightmap seed


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
func light_level_near(p: Vector3, radius := 2) -> float:
	var c := cell_of(p)
	var total := 0.0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var gx := c.x + dx
			var gz := c.y + dz
			var b := biome_at(gx, gz)
			var s := light_state(gx, gz, b)
			if s == L_ON or s == L_FLICKER:
				var lp := Vector3((gx + 0.5) * CELL, CEIL_H[b], (gz + 0.5) * CELL)
				total += LIGHT_POWER[b] / (1.0 + lp.distance_squared_to(p) * 0.3)
	return total


## Which way the light comes from around p: the pull of the lit fixtures
## nearby, each weighted like light_level_near. Its length says how one-sided
## the light is (0 in the middle of an even grid of lights, up to 1).
func light_dir_near(p: Vector3, radius := 3) -> Vector3:
	var c := cell_of(p)
	var sum := Vector3.ZERO
	var total := 0.0
	for dz in range(-radius, radius + 1):
		for dx in range(-radius, radius + 1):
			var gx := c.x + dx
			var gz := c.y + dz
			var b := biome_at(gx, gz)
			var s := light_state(gx, gz, b)
			if s == L_ON or s == L_FLICKER:
				var lp := Vector3((gx + 0.5) * CELL, CEIL_H[b], (gz + 0.5) * CELL)
				var w: float = LIGHT_POWER[b] / (1.0 + lp.distance_squared_to(p) * 0.3)
				sum += (lp - p).normalized() * w
				total += w
	return sum / total if total > 0.0 else Vector3.UP * 0.3


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


# -------------------------------------------------------------- stairwells ---
# One stairwell per STAIR_REGION x STAIR_REGION cells, at the same place on
# every floor: a block of STAIR_W x STAIR_D cells (a closed concrete shaft)
# with its door in the west wall of its first cell. See Stairwell.

const STAIR_REGION := 30
const STAIR_W := 3
const STAIR_D := 2
const NO_STAIRS := 1 << 30
## Height of one floor (the stairs climb this much per floor).
const FLOOR_H := 4.0


## The stairwell block of a stair region (its first cell), or NO_STAIRS.
func stair_block(sx: int, sz: int) -> Vector2i:
	if sx == 0 and sz == 0:
		return Vector2i(NO_STAIRS, NO_STAIRS)      # the start area
	var h := hashb(sx, sz, 901)
	var bx := sx * STAIR_REGION + 6 + h % (STAIR_REGION - 12)
	var bz := sz * STAIR_REGION + 6 + (h >> 8) % (STAIR_REGION - 12)
	return Vector2i(bx, bz)


## The block whose cells include (gx, gz), or NO_STAIRS.
func stair_block_at(gx: int, gz: int) -> Vector2i:
	var b := stair_block(floori(float(gx) / STAIR_REGION), floori(float(gz) / STAIR_REGION))
	if b.x != NO_STAIRS and gx >= b.x and gx < b.x + STAIR_W and gz >= b.y and gz < b.y + STAIR_D:
		return b
	return Vector2i(NO_STAIRS, NO_STAIRS)


## Within `margin` cells of a stairwell block.
func stair_zone(gx: int, gz: int, margin: int) -> bool:
	var b := stair_block(floori(float(gx) / STAIR_REGION), floori(float(gz) / STAIR_REGION))
	if b.x == NO_STAIRS:
		return false
	return gx >= b.x - margin and gx < b.x + STAIR_W + margin and gz >= b.y - margin and gz < b.y + STAIR_D + margin


## How a floor is written on the stairwell walls: 0, 1, 2 ... up, B1, B2 down.
static func floor_name(f: int) -> String:
	return str(f) if f >= 0 else "B%d" % -f
