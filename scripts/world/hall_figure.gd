class_name HallFigure
extends Node3D
## A too-tall, too-thin figure with white glowing eyes and a too-wide glowing
## smile, standing at the far end of
## the Unlit Halls. It only ever appears out of view (so it's simply there when
## you turn around) and it's gone a second after your flashlight finds it, when
## you get close, or when you look away and back. It never moves toward you and never
## attacks.

const SEEN_DIST := 30.0

var gen: WorldGen
var player: Player
var ambience: Ambience
var allowed := false

var _body: Node3D
var _mat: StandardMaterial3D
var _glow_mat: StandardMaterial3D
var _halo_mat: StandardMaterial3D
var _halos: Array[MeshInstance3D] = []
var _base_emit := Color.BLACK
var _head: Node3D
var _timer := 0.0
var _present := false
var _was_seen := false
var _unseen_t := 0.0
var _lit_t := 0.0
var _lit_limit := 1.0       # seconds in your flashlight beam before it's gone
var _sway := 0.0
var _audio: AudioStreamPlayer3D
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	_timer = _rng.randf_range(15.0, 35.0)
	_build()
	visible = false
	_audio = AudioStreamPlayer3D.new()
	_audio.bus = "World"
	_audio.unit_size = 6.0
	_audio.max_distance = 40.0
	add_child(_audio)


func _build() -> void:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.035, 0.032, 0.03)
	m.roughness = 1.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	# Everything here is self-lit from baked light, so it carries its own
	# (small) share of the light where it stands; set on spawn.
	m.emission_enabled = true
	_mat = m
	_body = Node3D.new()
	add_child(_body)
	# Proportions are deliberately wrong: long shins, long thin torso, arms
	# hanging past the knees, a small head bowed forward against the ceiling.
	for sx in [-1.0, 1.0]:
		_limb(m, Vector3(sx * 0.09, 0.0, 0.0), Vector3(sx * 0.1, 1.15, 0.0), 0.05)          # legs
		_limb(m, Vector3(sx * 0.2, 2.05, 0.02), Vector3(sx * 0.25, 1.4, 0.05), 0.035)       # upper arms
		_limb(m, Vector3(sx * 0.25, 1.4, 0.05), Vector3(sx * 0.24, 0.62, 0.12), 0.03)      # forearms, too long
		_limb(m, Vector3(sx * 0.24, 0.62, 0.12), Vector3(sx * 0.23, 0.42, 0.16), 0.022)    # long fingers
	_limb(m, Vector3(0, 1.1, 0.0), Vector3(0, 2.0, 0.04), 0.1)                          # torso
	_limb(m, Vector3(-0.2, 2.05, 0.03), Vector3(0.2, 2.05, 0.03), 0.06)                 # shoulders
	_head = Node3D.new()
	_head.position = Vector3(0, 2.12, 0.08)
	_body.add_child(_head)
	_limb(m, Vector3(0, 0, 0), Vector3(0, 0.12, 0.1), 0.045, _head)                    # neck, bent
	var hs := MeshInstance3D.new()
	var sp := SphereMesh.new()
	sp.radius = 0.1
	sp.height = 0.26
	hs.mesh = sp
	hs.material_override = m
	hs.position = Vector3(0, 0.22, 0.16)
	hs.rotation.x = 0.5
	_head.add_child(hs)
	_build_face(hs)


## White glowing eyes and a too-wide glowing grin. Lit by nothing - they're
## what you see first in the dark - with a soft glow so they still read from
## 20 m away at low resolution.
func _build_face(head: Node3D) -> void:
	_glow_mat = StandardMaterial3D.new()
	_glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_glow_mat.albedo_color = Color(1.0, 1.0, 0.97)
	_halo_mat = StandardMaterial3D.new()
	_halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_halo_mat.no_depth_test = false
	_halo_mat.albedo_color = Color(0.85, 0.9, 1.0, 0.55)
	var grad := Gradient.new()
	grad.set_color(0, Color(1, 1, 1, 1))
	grad.set_color(1, Color(1, 1, 1, 0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill = GradientTexture2D.FILL_RADIAL
	gt.fill_from = Vector2(0.5, 0.5)
	gt.fill_to = Vector2(1.0, 0.5)
	gt.width = 64
	gt.height = 64
	_halo_mat.albedo_texture = gt
	# The head sphere is 0.1 wide and 0.13 tall (radii); its face is +Z.
	for sx in [-1.0, 1.0]:
		var e := MeshInstance3D.new()
		var sp := SphereMesh.new()
		sp.radius = 0.021
		sp.height = 0.03
		sp.radial_segments = 8
		sp.rings = 4
		e.mesh = sp
		e.material_override = _glow_mat
		e.position = Vector3(sx * 0.037, 0.03, 0.088)
		head.add_child(e)
		_halo(head, e.position + Vector3(0, 0, 0.03), 0.075)
	# The grin: a thin arc much wider than a mouth should be, corners up.
	var segs := 11
	var prev := Vector3.ZERO
	for i in segs + 1:
		var u := -1.0 + 2.0 * i / segs
		var x := u * 0.072
		var y := -0.05 + 0.034 * u * u
		var zz := 0.1 * sqrt(maxf(1.0 - (x / 0.1) ** 2 - (y / 0.13) ** 2, 0.05)) + 0.004
		var pt := Vector3(x, y, zz)
		if i > 0:
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(prev.distance_to(pt) + 0.004, 0.009 - 0.004 * absf(u), 0.006)
			seg.mesh = bm
			seg.material_override = _glow_mat
			seg.position = (prev + pt) * 0.5
			var d := (pt - prev).normalized()
			seg.basis = Basis(Quaternion(Vector3.RIGHT, d))
			head.add_child(seg)
		prev = pt
	_halo(head, Vector3(0, -0.035, 0.12), 0.11, 0.45)


func _halo(parent: Node3D, pos: Vector3, size: float, strength := 1.0) -> void:
	var h := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(size, size)
	h.mesh = q
	h.material_override = _halo_mat
	h.position = pos
	h.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	h.transparency = 1.0 - strength
	h.set_meta("size", size)
	parent.add_child(h)
	_halos.append(h)


## Materials to pre-compile during loading (see Game._warm_shaders).
func warm_materials() -> Array[Material]:
	return [_mat, _glow_mat, _halo_mat]


func _limb(m: Material, a: Vector3, b: Vector3, r: float, parent: Node3D = null) -> void:
	var mi := MeshInstance3D.new()
	var cm := CapsuleMesh.new()
	cm.radius = r
	cm.height = a.distance_to(b) + r * 2.0
	cm.radial_segments = 8
	cm.rings = 2
	mi.mesh = cm
	mi.material_override = m
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else _body).add_child(mi)
	mi.position = (a + b) * 0.5
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mi.basis = Basis(Quaternion(Vector3.UP, dir))


func _process(delta: float) -> void:
	if _audio.stream == null:
		_audio.stream = AudioSynth.cached("exhale")
	var on: bool = allowed and gen != null and player != null and Settings.get_value("gameplay/entities")
	if not on:
		_hide()
		return
	if not _present:
		if _biome(player.global_position) == WorldGen.DARK:
			_timer -= delta
		if _timer <= 0.0:
			if not _try_spawn():
				_timer = 2.0
		return
	# Barely alive: a slow sway, the head tilting.
	_sway += delta
	_body.rotation.z = sin(_sway * 0.4) * 0.025
	_head.rotation.z = sin(_sway * 0.23 + 1.0) * 0.12
	var d := global_position.distance_to(player.global_position)
	# The glow grows with distance so the eyes and smile still read as points
	# of light far down a hall (and at PS1 resolution).
	var k := clampf(d / 6.0, 1.0, 4.0)
	for h in _halos:
		(h.mesh as QuadMesh).size = Vector2.ONE * float(h.get_meta("size")) * k
	var seen := _in_view()
	if seen:
		_was_seen = true
		_unseen_t = 0.0
	else:
		_unseen_t += delta
	# The world's flashlight is drawn by the surface shaders; this plain
	# material fakes catching the beam so you see it for that last second.
	if _lit_by_flashlight():
		_lit_t += delta
		_mat.emission = _base_emit + Color(0.26, 0.24, 0.21) * clampf(1.3 - d / 20.0, 0.25, 1.0)
	else:
		_lit_t = 0.0
		_mat.emission = _base_emit
	if d < 8.0 or _lit_t > _lit_limit or _biome(player.global_position) != WorldGen.DARK \
			or (_was_seen and _unseen_t > 0.6) or d > SEEN_DIST + 10.0:
		_vanish(_was_seen)


func _try_spawn() -> bool:
	# Nearer first; the narrow halls often hide everything that close, and
	# the glowing face still reads from further away.
	return _try_spawn_within(20.0) or _try_spawn_within(26.0)


func _try_spawn_within(dmax: float) -> bool:
	var p := player.global_position
	var eye := p + Vector3.UP * 1.55
	var fwd := -player.camera.global_basis.z
	fwd.y = 0.0
	fwd = fwd.normalized()
	var c := gen.cell_of(p)
	var space := get_world_3d().direct_space_state
	var best := []
	var r := ceili(dmax / WorldGen.CELL)
	for gz in range(c.y - r, c.y + r + 1):
		for gx in range(c.x - r, c.x + r + 1):
			var b := gen.biome_at(gx, gz)
			if b != WorldGen.DARK or gen.is_solid(gx, gz, b):
				continue
			var pos := Vector3((gx + 0.5) * WorldGen.CELL, 0.0, (gz + 0.5) * WorldGen.CELL)
			var to := pos - p
			to.y = 0.0
			var dist := to.length()
			if dist < 10.0 or dist > dmax:
				continue
			# Out of view now.
			if fwd.dot(to / dist) > cos(deg_to_rad(70.0)):
				continue
			# Prefers a pool of light (its shape shows best there), but the
			# Unlit Halls have few working lamps, so dark spots are fine too.
			var light := gen.light_level_near(pos + Vector3.UP * 1.5)
			var ok := true
			for hgt in [0.8, 1.6, 2.3]:
				var q := PhysicsRayQueryParameters3D.create(eye, pos + Vector3.UP * hgt)
				q.exclude = [player.get_rid()]
				if not space.intersect_ray(q).is_empty():
					ok = false
					break
			if ok:
				best.append([light, pos])
	if best.is_empty():
		return false
	best.sort_custom(func(a: Array, bb: Array) -> bool: return a[0] > bb[0])
	var pick: Vector3 = best[_rng.randi() % mini(3, best.size())][1]
	global_position = pick
	var lv := clampf(gen.light_level_near(pick + Vector3.UP * 1.5), 0.0, 1.5)
	# A faint shape even in the dark, like your eyes adjusting.
	_base_emit = Color(0.025, 0.023, 0.021) + Color(0.06, 0.054, 0.046) * lv
	_mat.emission = _base_emit
	_lit_limit = _rng.randf_range(0.8, 1.3)
	look_at(Vector3(player.global_position.x, 0.0, player.global_position.z), Vector3.UP, true)
	_present = true
	_was_seen = false
	_unseen_t = 0.0
	_lit_t = 0.0
	visible = true
	if ambience:
		ambience.hum_duck_figure = 0.5
	return true


func _vanish(with_sound: bool) -> void:
	if with_sound and _audio.stream:
		_audio.global_position = global_position + Vector3.UP * 2.0
		_audio.pitch_scale = _rng.randf_range(0.8, 1.0)
		_audio.play()
	_hide()
	_timer = _rng.randf_range(50.0, 110.0)


func _hide() -> void:
	if _present and ambience:
		ambience.hum_duck_figure = 1.0
	_present = false
	visible = false


func _in_view() -> bool:
	var cam := player.camera
	var target := global_position + Vector3.UP * 1.6
	var to := target - cam.global_position
	if to.length() > SEEN_DIST or (-cam.global_basis.z).dot(to.normalized()) < cos(deg_to_rad(36.0)):
		return false
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, target)
	q.exclude = [player.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q).is_empty()


func _lit_by_flashlight() -> bool:
	if not player.flashlight_on:
		return false
	var rig := player.flash_rig
	var target := global_position + Vector3.UP * 1.4
	var to := target - rig.global_position
	var dist := to.length()
	if dist > player.flashlight.spot_range * 0.9:
		return false
	return (-rig.global_basis.z).dot(to / dist) > cos(deg_to_rad(player.flashlight.spot_angle * 0.8))


func _biome(p: Vector3) -> int:
	var c := gen.cell_of(p)
	return gen.biome_at(c.x, c.y)


## For tests: stand at a position, facing a point.
func debug_place(pos: Vector3, face: Vector3) -> void:
	global_position = pos
	look_at(Vector3(face.x, pos.y, face.z), Vector3.UP, true)
	_present = true
	visible = true
