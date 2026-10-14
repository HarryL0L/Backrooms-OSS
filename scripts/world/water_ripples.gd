class_name WaterRipples
extends Node3D
## Interactive water: a ripple height field simulated on the GPU around the
## player (wave equation, ping-ponging between two small SubViewports), fed by
## wading, jumping in and the odd drip from the ceiling. The water shader
## bends its normals, reflections and highlights with it. Splashes also throw
## a burst of droplets.

const RES := 256
const SIZE := 16.0                 # metres covered by the grid
const TEXEL := SIZE / RES
const WAVE_SPEED := 0.55           # m/s
const MAX_DROPS := 8
const SIM_SHADER := preload("res://shaders/ripple_sim.gdshader")

var material: ShaderMaterial       # the water material
var player: Player
var gen: WorldGen
var active := false:
	set(v):
		active = v
		_apply_active()

var _vp: Array[SubViewport] = []
var _sim: Array[ShaderMaterial] = []
var _cur := 0
var _origin := Vector2.ZERO        # world xz of the grid's min corner
var _drops: Array[Vector4] = []    # world x, world z, radius m, strength m
var _was_in_water := false
var _drip_t := 3.0
var _splash: CPUParticles3D
var _drip_audio: AudioStreamPlayer3D


func _ready() -> void:
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(RES, RES)
		vp.use_hdr_2d = true            # float storage, heights are signed
		vp.disable_3d = true
		vp.transparent_bg = false
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var rect := ColorRect.new()
		rect.size = Vector2(RES, RES)
		var m := ShaderMaterial.new()
		m.shader = SIM_SHADER
		rect.material = m
		vp.add_child(rect)
		add_child(vp)
		_vp.append(vp)
		_sim.append(m)
	_sim[0].set_shader_parameter("prev_tex", _vp[1].get_texture())
	_sim[1].set_shader_parameter("prev_tex", _vp[0].get_texture())
	_splash = _make_splash()
	add_child(_splash)
	_drip_audio = AudioStreamPlayer3D.new()
	_drip_audio.stream = AudioSynth.cached("drip")
	_drip_audio.bus = "Ambience" if AudioServer.get_bus_index("Ambience") >= 0 else "Master"
	_drip_audio.unit_size = 4.0
	add_child(_drip_audio)
	_apply_active()


func _apply_active() -> void:
	if material == null or _vp.is_empty():
		return
	if not active:
		for vp in _vp:
			vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		material.set_shader_parameter("ripple_on", 0.0)


## Adds a disturbance at a world position (strength in metres of height).
func disturb(p: Vector3, radius: float, strength: float) -> void:
	if _drops.size() < MAX_DROPS:
		_drops.append(Vector4(p.x, p.z, radius, strength))


func splash(p: Vector3, amount: float) -> void:
	disturb(p, 0.18, -0.12 * amount)
	_splash.global_position = Vector3(p.x, WorldGen.WATER_Y, p.z)
	_splash.amount = int(clampf(24.0 * amount, 8.0, 48.0))
	_splash.restart()
	_splash.emitting = true


func _process(delta: float) -> void:
	if not active or player == null or material == null:
		return
	_feed(delta)
	# Recentre the grid on the player in whole texels.
	var p := Vector2(player.global_position.x, player.global_position.z)
	var centre := _origin + Vector2(SIZE, SIZE) * 0.5
	var shift := Vector2i.ZERO
	if p.distance_to(centre) > 2.0:
		shift = Vector2i(roundi((p.x - centre.x) / TEXEL), roundi((p.y - centre.y) / TEXEL))
		if absi(shift.x) > RES / 2 or absi(shift.y) > RES / 2:
			shift = Vector2i.ZERO
			_origin = p - Vector2(SIZE, SIZE) * 0.5   # teleported: start fresh
		else:
			_origin += Vector2(shift) * TEXEL
	# One simulation step into the other viewport.
	var n := 1 - _cur
	var m := _sim[n]
	m.set_shader_parameter("shift", Vector2(shift) / RES)
	var c := WAVE_SPEED * clampf(delta, 0.005, 0.05) / TEXEL
	m.set_shader_parameter("k", minf(c * c, 0.45))
	m.set_shader_parameter("damping", pow(0.35, clampf(delta, 0.005, 0.05)))
	var arr := PackedVector4Array()
	arr.resize(MAX_DROPS)
	for i in _drops.size():
		var d := _drops[i]
		arr[i] = Vector4((d.x - _origin.x) / SIZE, (d.y - _origin.y) / SIZE, d.z / SIZE, d.w)
	m.set_shader_parameter("drops", arr)
	m.set_shader_parameter("drop_count", _drops.size())
	_drops.clear()
	_vp[n].render_target_update_mode = SubViewport.UPDATE_ONCE
	_cur = n
	material.set_shader_parameter("ripple_tex", _vp[n].get_texture())
	material.set_shader_parameter("ripple_rect", Vector3(_origin.x, _origin.y, SIZE))
	material.set_shader_parameter("ripple_on", 1.0)


func _feed(delta: float) -> void:
	var p := player.global_position
	var in_water := player.in_water()
	if in_water and not _was_in_water:
		splash(p, clampf(-player.velocity.y * 0.35, 0.6, 2.0))
	elif in_water:
		var v := Vector2(player.velocity.x, player.velocity.z).length()
		if v > 0.15:
			# Wake: small pushes just ahead of the legs, scaled by speed.
			disturb(p + Vector3(player.velocity.x, 0, player.velocity.z) * 0.12, 0.22, -0.9 * v * delta)
	_was_in_water = in_water
	# Now and then a drop falls from the ceiling somewhere nearby.
	_drip_t -= delta
	if _drip_t <= 0.0:
		_drip_t = randf_range(1.5, 5.0)
		for _try in 6:
			var q := p + Vector3(randf_range(-6.0, 6.0), 0.0, randf_range(-6.0, 6.0))
			var c := gen.cell_of(q)
			if gen.biome_at(c.x, c.y) == WorldGen.POOL and gen.pool_noise(c.x, c.y):
				disturb(q, 0.08, -0.05)
				_drip_audio.global_position = Vector3(q.x, WorldGen.WATER_Y, q.z)
				_drip_audio.pitch_scale = randf_range(0.85, 1.2)
				_drip_audio.play()
				break


func _make_splash() -> CPUParticles3D:
	var s := CPUParticles3D.new()
	s.emitting = false
	s.one_shot = true
	s.explosiveness = 0.95
	s.lifetime = 0.9
	s.amount = 32
	s.direction = Vector3.UP
	s.spread = 35.0
	s.initial_velocity_min = 1.2
	s.initial_velocity_max = 3.0
	s.gravity = Vector3(0, -9.8, 0)
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.25
	s.scale_amount_min = 0.5
	s.scale_amount_max = 1.2
	var mesh := SphereMesh.new()
	mesh.radius = 0.016
	mesh.height = 0.032
	mesh.radial_segments = 6
	mesh.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.85, 0.95, 1.0, 0.6)
	mesh.material = mat
	s.mesh = mesh
	return s
