class_name Stairwells
extends Node3D
## Keeps the stairwells near the player built (see Stairwell) and notices when
## you've gone more than half a floor up or down one: `floor_step` asks the
## game to swap in the next floor.

signal floor_step(dir: int)

## Past the half landing by this much before the floor changes (and you land
## this far short of it on the other side, so turning back doesn't flip-flop).
const SWAP_Y := WorldGen.FLOOR_H * 0.5 + 0.3

var gen: WorldGen
var player: Player
var chunks: ChunkManager
var floor_index := 0
var _wells := {}           # block -> Stairwell
var _scan := 0.0


func clear() -> void:
	for w in _wells.values():
		w.queue_free()
	_wells.clear()
	_scan = 0.0


func set_floor(f: int) -> void:
	floor_index = f
	for w in _wells.values():
		(w as Stairwell).set_floor(f)


func _physics_process(delta: float) -> void:
	if gen == null or player == null:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.5
		_refresh()
	var p := player.global_position
	var inside: Stairwell = null
	for w in _wells.values():
		var sw := w as Stairwell
		if sw.contains(p):
			inside = sw
		var ready := chunks.is_area_ready(sw.global_position + Vector3(-1.0, 0.0, 1.2), 1)
		sw.update_door(delta, p, ready)
	player.in_stairwell = inside != null
	if inside == null or not player.controls_enabled:
		return
	if p.y < -SWAP_Y:
		floor_step.emit(-1)
	elif p.y > SWAP_Y:
		floor_step.emit(1)


func _refresh() -> void:
	var c := gen.cell_of(player.global_position)
	var sx := floori(float(c.x) / WorldGen.STAIR_REGION)
	var sz := floori(float(c.y) / WorldGen.STAIR_REGION)
	var keep := {}
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var b := gen.stair_block(sx + dx, sz + dz)
			if b.x == WorldGen.NO_STAIRS:
				continue
			keep[b] = true
			if not _wells.has(b):
				var w := Stairwell.new()
				w.setup(b)
				add_child(w)
				w.set_floor(floor_index)
				_wells[b] = w
	for b in _wells.keys():
		if not keep.has(b):
			_wells[b].queue_free()
			_wells.erase(b)
