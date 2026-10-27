class_name LevelEntrance
extends Node3D
## A way into a side level (dest = its id), set into a wall or the floor of
## the Backrooms (placed by LevelEntrances), standing in the Dead Mall, or,
## as an exit, in a side level itself (SideLevel.add_exit; dest "" = back
## to the Backrooms). One family of looks for all of them: "door", "double",
## "vent", "hatch", "lift", "stairs", or "none" (an invisible walk-in
## trigger for an exit a level builds itself).
##
## Local space: it faces +Z (the side you stand on); the origin is on the
## wall face at floor level (on the floor, for a hatch). Its parts are
## self-lit by `light` like the world around them (the Backrooms' surfaces
## carry their baked light as emission), and real lights add on top.
##
## Using it: the game's interact prompt (group "usable": use_targets() /
## use()), or walking into it when `walk_in`. Neither knows about the game:
## an entrance calls whoever is in HOST_GROUP (the game) with
## use_level_entrance(self); an exit tells its level (SideLevel
## _exit_activated), which emits exit_entered. Then the game plays enter()
## (the door swinging, the ride in) before its fade. To make your own look
## or ride, extend this, override _build() and/or enter(), and name your
## script in the level's ENTRANCES ("script") or add_exit opts.

const HOST_GROUP := "side_level_host"
const LOOKS := ["door", "double", "vent", "hatch", "lift", "stairs", "none"]
const LABELS := {"door": "Open the door", "double": "Push the doors", "vent": "Crawl into the vent",
		"hatch": "Climb down the hatch", "lift": "Call the lift", "stairs": "Go down the stairs", "none": ""}

## Where it goes: a side level's id ("" = the Backrooms, for exits).
var dest := ""
var look := "door"
## Text on a plate above it ("" none).
var sign_text := ""
## The Use prompt ("" = the look's default; none at all for "none").
var label := ""
## Walking into it is enough (no Use).
var walk_in := false
## The walk-in box (in front of it, local).
var trigger_size := Vector3(1.0, 1.8, 0.7)
## How lit it is where it stands, 0..1 (the spawner and add_exit set it).
var light := 0.5
## The side level this is an exit of (null: an entrance).
var exit_of: SideLevel = null
## The entrance spec it was placed from (LevelEntrances), if any.
var spec := {}
## Being gone through.
var busy := false

## Moving parts, by name ("leaf", "leaf2", "lid", "grille"...), and where
## each sits shut.
var parts := {}
var _void: MeshInstance3D
var _audio: AudioStreamPlayer3D
var _mats := {}


func _ready() -> void:
	add_to_group("usable")
	if label == "":
		label = LABELS.get(look, "Go through")
	_build()
	if walk_in:
		var area := Area3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = trigger_size
		cs.shape = bs
		cs.position = Vector3(0.0, trigger_size.y * 0.5, trigger_size.z * 0.5) if look != "hatch" \
				else Vector3(0.0, trigger_size.y * 0.5, 0.0)
		area.add_child(cs)
		area.body_entered.connect(func(b: Node3D) -> void:
			if b is Player:
				_activate())
		add_child(area)


# ------------------------------------------------------------------- use ---

## What you can do from here: [id, world position, label].
func use_targets(_p: Player) -> Array:
	if busy or walk_in or (look == "none" and label == ""):
		return []
	return [["go", global_transform * use_point(), label]]


## Where the prompt sits (local): what you look at to use it.
func use_point() -> Vector3:
	match look:
		"vent":
			return Vector3(0.0, 0.32, 0.05)
		"hatch":
			return Vector3(0.0, 0.05, 0.0)
		"lift":
			return Vector3(0.0, 1.1, 0.05)
	return Vector3(0.0, 1.05, 0.08)


func use(_id: String, _p: Player) -> String:
	_activate()
	return ""


func _activate() -> void:
	if busy:
		return
	if exit_of != null:
		exit_of._exit_activated(self)
	else:
		get_tree().call_group(HOST_GROUP, "use_level_entrance", self)


# ----------------------------------------------------------------- enter ---

## Going through: opens and takes the player in, ending with their eyes
## right up against the dark (or lit) opening so it fills the view; the
## game fades after it. Override for your own (a ladder down, a squeeze).
func enter(p: Player) -> void:
	busy = true
	match look:
		"none":
			return
		"vent":
			await open()
			await ride(p, [_world(Vector3(0, 0.55, 0.75)), _world(Vector3(0, 0.22, 0.12))], 1.6, 0.0)
		"hatch":
			await open()
			await ride(p, [_world(Vector3(0, 1.05, 0.25)), _world(Vector3(0, 0.12, 0.0))], 1.7, -1.35)
		"stairs":
			await open()
			await ride(p, [_world(Vector3(0, 1.55, 0.7)), _world(Vector3(0, 1.3, 0.1))], 1.2, -0.25)
		_:
			await open()
			await ride(p, [_world(Vector3(0, 1.58, 0.65)), _world(Vector3(0, 1.5, 0.1))], 1.1, -0.05)


## Opens it (the door swings, the grille drops, the lid lifts, the lift's
## doors slide apart), showing the opening behind.
func open() -> void:
	if _audio:
		_audio.volume_db += 4.0
	var tw := create_tween().set_parallel(true)
	var any := false
	for k in parts:
		var n: Node3D = parts[k]
		any = true
		match k:
			"leaf":
				tw.tween_property(n, "rotation:y", -1.7, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			"leaf2":
				tw.tween_property(n, "rotation:y", 1.7, 0.75).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			"grille":
				tw.tween_property(n, "rotation:x", 1.45, 0.6).set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)
			"lid":
				tw.tween_property(n, "rotation:x", -1.9, 0.9).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
			"slide_l":
				tw.tween_property(n, "position:x", n.position.x - 0.5, 1.0).set_trans(Tween.TRANS_SINE)
			"slide_r":
				tw.tween_property(n, "position:x", n.position.x + 0.5, 1.0).set_trans(Tween.TRANS_SINE)
			"gate":
				tw.tween_property(n, "position:y", n.position.y + 1.2, 1.0).set_trans(Tween.TRANS_SINE)
	if any:
		await tw.finished
	else:
		tw.kill()


## Moves the player's eyes through `eyes` (world points; it starts from
## where they are) in `time` s, settling the view to `pitch`, facing in.
func ride(p: Player, eyes: Array, time: float, pitch := -0.08) -> void:
	var path := PackedVector3Array([p.camera.global_position])
	for e in eyes:
		path.append(e)
	var f := -global_basis.z
	var yaw := atan2(-f.x, -f.z)
	var state := {"done": false}
	p.ride(path, yaw, time, func() -> void:
		p.stand_up()                     # (a ride switches collision off)
		state.done = true, pitch)
	while not state.done and is_inside_tree():
		await get_tree().process_frame


func _world(local: Vector3) -> Vector3:
	return global_transform * local


# ----------------------------------------------------------------- looks ---

## Makes the look. Override for your own (keep the opening's dark quad,
## `make_void`, so the ride ends in darkness).
func _build() -> void:
	match look:
		"door":
			_door(0.92, 2.06, false)
		"double":
			_door(1.7, 2.3, true)
		"vent":
			_vent()
		"hatch":
			_hatch()
		"lift":
			_lift()
		"stairs":
			_stairs()
	if sign_text != "" and look != "none":
		var y: float = {"vent": 0.68, "hatch": 0.0, "lift": 2.42, "stairs": 2.42, "double": 2.5}.get(look, 2.27)
		if look != "hatch":
			_plate(sign_text, Vector3(0.0, y, 0.03))
	_sound()


func _door(w: float, h: float, double: bool) -> void:
	var paint := mat(Color(0.42, 0.45, 0.43), 0.5, 0.2)
	var frame := mat(Color(0.25, 0.25, 0.24), 0.4, 0.5)
	var steel := mat(Color(0.7, 0.7, 0.68), 0.3, 0.9)
	box(frame, Vector3(0.08, h + 0.08, 0.12), Vector3(-w * 0.5 - 0.04, (h + 0.08) * 0.5, 0.06))
	box(frame, Vector3(0.08, h + 0.08, 0.12), Vector3(w * 0.5 + 0.04, (h + 0.08) * 0.5, 0.06))
	box(frame, Vector3(w + 0.16, 0.08, 0.12), Vector3(0.0, h + 0.04, 0.06))
	make_void(Vector2(w, h), Vector3(0.0, h * 0.5, 0.01))
	var leaves := 2 if double else 1
	var lw := w / leaves
	for i in leaves:
		var piv := Node3D.new()
		var right := i == 1
		piv.position = Vector3(w * 0.5 if right else -w * 0.5, 0.0, 0.05)
		add_child(piv)
		var sx := -1.0 if right else 1.0
		box(paint, Vector3(lw - 0.01, h - 0.01, 0.045), Vector3(sx * lw * 0.5, h * 0.5, 0.0), piv)
		# A push plate or a lever handle.
		if double:
			box(steel, Vector3(0.1, 0.32, 0.01), Vector3(sx * (lw - 0.12), 1.15, 0.028), piv)
		else:
			box(steel, Vector3(0.13, 0.025, 0.03), Vector3(sx * (lw - 0.13), 1.0, 0.045), piv)
			box(steel, Vector3(0.04, 0.12, 0.01), Vector3(sx * (lw - 0.09), 1.0, 0.026), piv)
		parts["leaf2" if right else "leaf"] = piv


func _vent() -> void:
	var w := 0.62
	var h := 0.42
	var y0 := 0.12
	var metal := mat(Color(0.72, 0.71, 0.66), 0.45, 0.6)
	make_void(Vector2(w, h), Vector3(0.0, y0 + h * 0.5, 0.005))
	box(metal, Vector3(w + 0.06, 0.03, 0.02), Vector3(0.0, y0 - 0.015, 0.01))
	box(metal, Vector3(w + 0.06, 0.03, 0.02), Vector3(0.0, y0 + h + 0.015, 0.01))
	box(metal, Vector3(0.03, h, 0.02), Vector3(-w * 0.5 - 0.015, y0 + h * 0.5, 0.01))
	box(metal, Vector3(0.03, h, 0.02), Vector3(w * 0.5 + 0.015, y0 + h * 0.5, 0.01))
	# The grille, hinged at the bottom; one screw already gone.
	var piv := Node3D.new()
	piv.position = Vector3(0.0, y0, 0.02)
	add_child(piv)
	var n := 9
	for i in n:
		box(metal, Vector3(w - 0.02, 0.012, 0.03), Vector3(0.0, (i + 0.5) * h / n, 0.0), piv, Vector3(-0.6, 0, 0))
	box(metal, Vector3(w, 0.02, 0.01), Vector3(0.0, h - 0.01, 0.0), piv)
	parts["grille"] = piv


func _hatch() -> void:
	var s := 0.8
	var frame := mat(Color(0.33, 0.33, 0.31), 0.5, 0.6)
	var steel := mat(Color(0.45, 0.46, 0.44), 0.4, 0.7)
	var v := make_void(Vector2(s, s), Vector3(0.0, 0.004, 0.0))
	v.rotation.x = -PI * 0.5
	for sx in [-1.0, 1.0]:
		box(frame, Vector3(0.06, 0.03, s + 0.12), Vector3(sx * (s * 0.5 + 0.03), 0.015, 0.0))
		box(frame, Vector3(s, 0.03, 0.06), Vector3(0.0, 0.015, sx * (s * 0.5 + 0.03)))
	# The lid, hinged on its far edge (-Z), chequer plate and a ring pull.
	var piv := Node3D.new()
	piv.position = Vector3(0.0, 0.03, -s * 0.5)
	add_child(piv)
	box(steel, Vector3(s - 0.01, 0.02, s - 0.01), Vector3(0.0, 0.0, s * 0.5), piv)
	for i in 5:
		box(steel, Vector3(s - 0.1, 0.006, 0.02), Vector3(0.0, 0.012, 0.1 + i * 0.15), piv)
	box(frame, Vector3(0.12, 0.015, 0.02), Vector3(0.0, 0.016, s - 0.08), piv)
	parts["lid"] = piv


func _lift() -> void:
	var w := 1.0
	var h := 2.1
	var steel := mat(Color(0.62, 0.63, 0.62), 0.25, 0.9)
	var frame := mat(Color(0.3, 0.3, 0.3), 0.4, 0.6)
	var lit := mat(Color(1.0, 0.8, 0.45), 0.5, 0.0, 2.5)
	box(frame, Vector3(0.34, h + 0.2, 0.1), Vector3(-w * 0.5 - 0.17, (h + 0.2) * 0.5, 0.05))
	box(frame, Vector3(0.34, h + 0.2, 0.1), Vector3(w * 0.5 + 0.17, (h + 0.2) * 0.5, 0.05))
	box(frame, Vector3(w + 0.68, 0.2, 0.1), Vector3(0.0, h + 0.1, 0.05))
	# Behind the doors: the car, lit (a warm glow).
	var v := make_void(Vector2(w, h), Vector3(0.0, h * 0.5, 0.01))
	v.material_override = _glow_mat(Color(0.55, 0.5, 0.4))
	for sx in [-1.0, 1.0]:
		var d := Node3D.new()
		d.position = Vector3(sx * w * 0.25, 0.0, 0.035)
		add_child(d)
		box(steel, Vector3(w * 0.5 - 0.005, h, 0.03), Vector3(0.0, h * 0.5, 0.0), d)
		parts["slide_r" if sx > 0.0 else "slide_l"] = d
	# Call button and floor indicator.
	box(steel, Vector3(0.09, 0.2, 0.02), Vector3(w * 0.5 + 0.17, 1.1, 0.105))
	box(lit, Vector3(0.03, 0.03, 0.02), Vector3(w * 0.5 + 0.17, 1.13, 0.115))
	box(lit, Vector3(0.18, 0.05, 0.02), Vector3(0.0, h + 0.1, 0.105))


func _stairs() -> void:
	var w := 1.6
	var h := 2.1
	var tile := mat(Color(0.82, 0.81, 0.76), 0.3, 0.1)
	var steel := mat(Color(0.5, 0.5, 0.48), 0.4, 0.8)
	box(tile, Vector3(0.2, h + 0.2, 0.12), Vector3(-w * 0.5 - 0.1, (h + 0.2) * 0.5, 0.06))
	box(tile, Vector3(0.2, h + 0.2, 0.12), Vector3(w * 0.5 + 0.1, (h + 0.2) * 0.5, 0.06))
	box(tile, Vector3(w + 0.4, 0.2, 0.12), Vector3(0.0, h + 0.1, 0.06))
	make_void(Vector2(w, h), Vector3(0.0, h * 0.5, 0.01))
	# Step nosings catching a little light, going down into the dark.
	for i in 5:
		var k := 1.0 - i * 0.2
		var m := mat(Color(0.6, 0.58, 0.5) * k, 0.5, 0.0)
		box(m, Vector3(w - 0.1, 0.02, 0.02), Vector3(0.0, 0.32 - i * 0.07, 0.02))
	# A roller grille, stuck half up.
	var g := Node3D.new()
	g.position = Vector3(0.0, h * 0.55, 0.08)
	add_child(g)
	for i in 10:
		box(steel, Vector3(w, 0.03, 0.02), Vector3(0.0, i * 0.1, 0.0), g)
	parts["gate"] = g


## A plate of text above it (lit like the place around it).
func _plate(text: String, at: Vector3) -> void:
	var plate := mat(Color(0.86, 0.84, 0.76), 0.6, 0.0)
	var w := maxf(0.34, text.length() * 0.075 + 0.12)
	box(plate, Vector3(w, 0.16, 0.015), at)
	var l := Label3D.new()
	l.text = text
	l.font_size = 48
	l.pixel_size = 0.0022
	l.modulate = Color(0.08, 0.08, 0.08)
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = at + Vector3(0.0, 0.0, 0.009)
	add_child(l)


func _sound() -> void:
	var fn: String = {"vent": "draught", "hatch": "drip", "stairs": "wind", "lift": "hum"}.get(look, "draught")
	if look == "none":
		return
	_audio = AudioStreamPlayer3D.new()
	_audio.stream = AudioSynth.cached(fn)
	_audio.bus = "World"
	_audio.unit_size = 1.5
	_audio.max_distance = 12.0
	_audio.volume_db = -10.0 if look != "lift" else -18.0
	_audio.position = use_point()
	add_child(_audio)
	_audio.play()


# --------------------------------------------------------------- helpers ---

## The dark behind the opening (local, facing +Z): what you ride into.
func make_void(size: Vector2, at: Vector3) -> MeshInstance3D:
	_void = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = size
	_void.mesh = q
	_void.material_override = _glow_mat(Color(0.004, 0.004, 0.004))
	_void.position = at
	_void.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_void)
	return _void


## A material for its parts: `c` lit by `light` (and real lights).
func mat(c: Color, rough: float, metal := 0.0, glow := 0.0) -> StandardMaterial3D:
	var key := "%s|%s|%s|%s|%.2f" % [c, rough, metal, glow, light]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	m.emission_enabled = true
	m.emission = c * (light * 0.9 + glow)
	_mats[key] = m
	return m


func _glow_mat(c: Color) -> StandardMaterial3D:
	var key := "glow|%s" % c
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = c
	_mats[key] = m
	return m


func box(m: Material, size: Vector3, pos: Vector3, parent: Node3D = null, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = m
	mi.position = pos
	mi.rotation = rot
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	(parent if parent else self).add_child(mi)
	return mi


## For the loading fade's shader warm-up.
static func warm_materials() -> Array[Material]:
	var out: Array[Material] = []
	var m := StandardMaterial3D.new()
	m.emission_enabled = true
	out.append(m)
	var u := StandardMaterial3D.new()
	u.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	out.append(u)
	return out
