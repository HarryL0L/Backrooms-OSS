class_name FixtureLights
extends Node3D
## Places a small pool of real OmniLights on the light fixtures nearest to the
## player (that the player can see). Diffuse lighting is already baked into
## the lightmaps, so on the Mobile renderer these lights are tuned to add
## almost no diffuse light and only real-time specular highlights: the glints
## of the panels on pool tiles, puddles and water that move as you walk.
## On Forward+ (desktop) they also light the volumetric fog.

const COUNT := 6
const FADE_TIME := 0.3
## Bounce strength under VoxelGI: the lights' direct diffuse is kept low
## (the lightmaps already have it), their bounce has to stand for the panel.
const GI_BOUNCE := 2.0

var gen: WorldGen
var target: Node3D
## Max number of lights placed (settings / diagnostics can lower it; 0 = none).
var max_lights := COUNT

var _lights: Array[OmniLight3D] = []
var _keys: Array[Vector2i] = []      # fixture cell per slot (NONE = free)
var _seeds := PackedFloat32Array()
var _base := PackedFloat32Array()
var _fade := PackedFloat32Array()
var _scan := 0.0
var _forward_plus := false

const NONE := Vector2i(1 << 30, 1 << 30)


func _ready() -> void:
	_forward_plus = RenderingServer.get_current_rendering_method() == "forward_plus"
	for i in COUNT:
		var l := OmniLight3D.new()
		l.shadow_enabled = false
		if _forward_plus:
			l.light_specular = 2.2
			l.light_volumetric_fog_energy = 2.5
		else:
			# Energy scales diffuse and specular; light_specular only specular.
			# Tiny energy x big specular = highlights without double diffuse.
			l.light_specular = 24.0
		l.visible = false
		add_child(l)
		_lights.append(l)
		_keys.append(NONE)
	_seeds.resize(COUNT)
	_base.resize(COUNT)
	_fade.resize(COUNT)


## With VoxelGI on (experimental), these lights also feed its bounce light.
func set_gi(on: bool) -> void:
	for l in _lights:
		l.light_indirect_energy = GI_BOUNCE if on else 1.0


func _process(delta: float) -> void:
	if gen == null or target == null:
		return
	_scan -= delta
	if _scan <= 0.0:
		_scan = 0.35
		_place()
	var t := Ambience.world_time()
	var step := delta / FADE_TIME
	for i in COUNT:
		var l := _lights[i]
		if _keys[i] == NONE:
			_fade[i] = maxf(_fade[i] - step, 0.0)
		else:
			_fade[i] = minf(_fade[i] + step, 1.0)
		l.visible = _fade[i] > 0.0
		if l.visible:
			var fl := WorldGen.flicker(_seeds[i], t) if _seeds[i] > 0.0 else 1.0
			l.light_energy = _base[i] * fl * _fade[i]


func _place() -> void:
	if max_lights == 0:
		for i in COUNT:
			_keys[i] = NONE
		return
	var p := target.global_position
	var eye := p + Vector3.UP * 1.5
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
				found.append([lp.distance_squared_to(p), lp, b, s, Vector2i(gx, gz)])
	found.sort_custom(func(a: Array, bb: Array) -> bool: return a[0] < bb[0])
	# Keep the nearest fixtures the player can actually see (no highlights from
	# lamps behind walls).
	var space := get_world_3d().direct_space_state
	var exclude: Array[RID] = []
	if target is CollisionObject3D:
		exclude.append((target as CollisionObject3D).get_rid())
	var chosen := {}
	for e in found:
		if chosen.size() >= max_lights:
			break
		var q := PhysicsRayQueryParameters3D.create(eye, e[1])
		q.exclude = exclude
		if space.intersect_ray(q).is_empty():
			chosen[e[4]] = e
	# Slots whose fixture is still chosen keep it (no popping); others are
	# freed and refilled.
	for i in COUNT:
		if _keys[i] != NONE and not chosen.has(_keys[i]):
			_keys[i] = NONE
	for key in chosen:
		if _keys.has(key):
			continue
		var slot := -1
		for i in COUNT:
			if _keys[i] == NONE and _fade[i] <= 0.0:
				slot = i
				break
		if slot < 0:
			break
		var e: Array = chosen[key]
		var b: int = e[2]
		var sky: bool = e[3] == WorldGen.L_SKY
		var l := _lights[slot]
		_keys[slot] = key
		_fade[slot] = 0.0
		l.global_position = e[1]
		l.light_color = WorldGen.SKY_COLOR if sky else WorldGen.LIGHT_COLOR[b]
		l.omni_range = WorldGen.LIGHT_RADIUS[b] * (1.2 if sky else 0.8)
		var energy := 0.9 if sky else 0.35 * sqrt(WorldGen.LIGHT_REACH[b])
		_base[slot] = energy if _forward_plus else energy * 0.12
		_seeds[slot] = gen.light_seed(key.x, key.y) if e[3] == WorldGen.L_FLICKER else 0.0
