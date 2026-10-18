class_name OddDoors
extends Node3D
## Places the rare mysterious doors (OddDoor) on Yellow Halls walls near the player.
## Each REGION x REGION cell area may hold one, at a spot derived from the world
## seed, so a door is always in the same place for a given seed.

signal door_entered(door: OddDoor)

const REGION := 24
const CHANCE := 0.55

var gen: WorldGen
var target: Node3D
var _doors := {}            # Vector2i region -> OddDoor (or null when the region has none)
var _trails := {}           # Vector2i region -> DoorTrail (clues leading to that door)
var _scan := 0.0


## Door placement for a region, or an empty Dictionary when it has none.
## The door stands on the east face of the wall on grid line x = gx, cell row gz.
func door_in_region(r: Vector2i) -> Dictionary:
	if gen.rnd(r.x, r.y, 701) >= CHANCE:
		return {}
	for attempt in 6:
		var gx := r.x * REGION + 2 + int(gen.rnd(r.x, r.y, 702 + attempt * 2) * (REGION - 4))
		var gz := r.y * REGION + 2 + int(gen.rnd(r.x, r.y, 703 + attempt * 2) * (REGION - 4))
		if gen.near_spawn(gx, gz, 5):
			continue
		var ba := gen.biome_at(gx - 1, gz)
		var bb := gen.biome_at(gx, gz)
		if ba != WorldGen.LOBBY or bb != WorldGen.LOBBY:
			continue
		if gen.is_solid(gx, gz, bb) or gen.edge_kind(gx, gz, true, ba, bb) != WorldGen.E_WALL:
			continue
		var pos := Vector3(gx * WorldGen.CELL + ChunkBuilder.T + 0.035, 0.0, (gz + 0.5) * WorldGen.CELL)
		# About half the doors open onto the Dead Mall instead of the Field.
		return {"pos": pos, "mall": gen.rnd(r.x, r.y, 709) < 0.5}
	return {}


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
			if _doors.has(r):
				continue
			var d := door_in_region(r)
			if d.is_empty():
				_doors[r] = null
				continue
			var door := OddDoor.new()
			door.mall = d.mall
			add_child(door)
			door.global_position = d.pos
			door.rotation.y = PI * 0.5      # front (+Z) turned to face +X, into the room
			door.entered.connect(func() -> void: door_entered.emit(door))
			_doors[r] = door
			# Chalk arrows and litter along the way there.
			var trail := DoorTrail.new()
			add_child(trail)
			trail.start(gen, gen.cell_of(d.pos + Vector3(0.5, 0, 0)), d.mall, gen.hashi(r.x, r.y, 713))
			_trails[r] = trail
	for r in _doors.keys():
		if not keep.has(r):
			if _doors[r] != null:
				_doors[r].queue_free()
			_doors.erase(r)
			if _trails.has(r):
				_trails[r].queue_free()
				_trails.erase(r)


func clear() -> void:
	for r in _doors:
		if _doors[r] != null:
			_doors[r].queue_free()
	_doors.clear()
	for r in _trails:
		_trails[r].queue_free()
	_trails.clear()


## Nearest door position within the loaded regions (for tests / hints).
func nearest(p: Vector3) -> Vector3:
	var best := Vector3.INF
	for r in _doors:
		var d: OddDoor = _doors[r]
		if d != null and (best == Vector3.INF or d.global_position.distance_to(p) < best.distance_to(p)):
			best = d.global_position
	return best
