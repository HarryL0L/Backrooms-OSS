class_name VoxelGIRig
extends Node3D
## Experimental (Forward+ only): Godot's VoxelGI around the player, for real
## bounce light from the light nodes: the flashlight's beam lights up the
## walls around it, colours bleed onto neighbouring surfaces and corners get
## soft indirect shadows, all in real time as lights move and flicker.
##
## VoxelGI needs a bake of the static geometry it covers. The world is built
## as you walk, so a volume around the player is baked at runtime and baked
## again when the player has moved far enough (a short hitch on weak GPUs,
## hence experimental). Only real Light3D nodes bounce: our surfaces are lit
## through the shader's EMISSION, which VoxelGI ignores, so FixtureLights and
## the flashlight are what feed it.

const SIZE := Vector3(32.0, 8.0, 32.0)
## Re-bake once the player is this far (metres, horizontal) from the centre.
const REBAKE_DIST := 7.0

## Static geometry to bake (the chunk manager, or the mall).
var source: Node3D
var target: Node3D

var _vgi: VoxelGI
var _centre := Vector3.INF
var _dirty := false
var last_bake_ms := 0.0


func _ready() -> void:
	_vgi = VoxelGI.new()
	_vgi.size = SIZE
	# 0.5 m voxels on phones, 0.25 m on desktop.
	_vgi.subdiv = VoxelGI.SUBDIV_64 if Settings.is_mobile else VoxelGI.SUBDIV_128
	_vgi.top_level = true
	add_child(_vgi)
	set_active(false)


func set_active(on: bool) -> void:
	visible = on
	set_process(on)
	_vgi.visible = on
	if on:
		_dirty = true
	else:
		_vgi.data = null
		_centre = Vector3.INF


## Bake again at the next frame (the geometry under the volume changed).
func invalidate() -> void:
	_dirty = true


func _process(_delta: float) -> void:
	if target == null or source == null or not is_instance_valid(source):
		return
	var p := target.global_position
	if _dirty or Vector2(p.x - _centre.x, p.z - _centre.z).length() > REBAKE_DIST:
		_bake(p)


func _bake(p: Vector3) -> void:
	_dirty = false
	# Floors are at the player's feet; the volume goes 1 m below and up to
	# the tallest ceilings.
	_centre = Vector3(snappedf(p.x, 1.0), floorf(p.y) - 1.0 + SIZE.y * 0.5, snappedf(p.z, 1.0))
	_vgi.global_position = _centre
	var t := Time.get_ticks_usec()
	_vgi.bake(source)
	last_bake_ms = (Time.get_ticks_usec() - t) / 1000.0
	if _vgi.data:
		_vgi.data.energy = 1.0
		_vgi.data.propagation = 0.7
		_vgi.data.bias = 1.5
		_vgi.data.normal_bias = 0.0
		_vgi.data.interior = true    # no sky: the environment isn't sampled
