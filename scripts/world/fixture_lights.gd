class_name FixtureLights
extends Node3D
## Ultra mode: places a small pool of real OmniLights on the light fixtures
## nearest to the player. Baked lighting already does the diffuse work, so these
## lights contribute mostly specular glints and light the volumetric fog, giving
## the hazy glow around each panel. They flicker in sync with the panels.

const COUNT := 6

var gen: WorldGen
var target: Node3D
var _lights: Array[OmniLight3D] = []
var _seeds := PackedFloat32Array()
var _base := PackedFloat32Array()
var _scan := 0.0


func _ready() -> void:
	for i in COUNT:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		l.light_specular = 2.2
		l.light_volumetric_fog_energy = 2.5
		l.visible = false
		add_child(l)
		_lights.append(l)
	_seeds.resize(COUNT)
	_base.resize(COUNT)


func _process(delta: float) -> void:
	if gen == null or target == null:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.35
		_place()
	var t := Ambience.world_time()
	for i in COUNT:
		if _lights[i].visible:
			_lights[i].light_energy = _base[i] * (WorldGen.flicker(_seeds[i], t) if _seeds[i] > 0.0 else 1.0)


func _place() -> void:
	var p := target.global_position
	var c := gen.cell_of(p)
	var found := []
	for dz in range(-4, 5):
		for dx in range(-4, 5):
			var gx := c.x + dx
			var gz := c.y + dz
			var b := gen.biome_at(gx, gz)
			var s := gen.light_state(gx, gz, b)
			if s == WorldGen.L_ON or s == WorldGen.L_FLICKER or s == WorldGen.L_SKY:
				var lp := Vector3((gx + 0.5) * WorldGen.CELL, WorldGen.CEIL_H[b] - 0.25, (gz + 0.5) * WorldGen.CELL)
				found.append([lp.distance_squared_to(p), lp, b, s, gen.light_seed(gx, gz) if s == WorldGen.L_FLICKER else 0.0])
	found.sort_custom(func(a: Array, bb: Array) -> bool: return a[0] < bb[0])
	for i in COUNT:
		var l := _lights[i]
		if i >= found.size():
			l.visible = false
			continue
		var e: Array = found[i]
		var b: int = e[2]
		var sky: bool = e[3] == WorldGen.L_SKY
		l.visible = true
		l.global_position = e[1]
		l.light_color = WorldGen.SKY_COLOR if sky else WorldGen.LIGHT_COLOR[b]
		l.omni_range = WorldGen.LIGHT_RADIUS[b] * (1.2 if sky else 0.8)
		_base[i] = 0.9 if sky else 0.35
		_seeds[i] = e[4]
