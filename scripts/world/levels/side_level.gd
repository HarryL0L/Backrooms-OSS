class_name SideLevel
extends Node3D
## The base of every side level: a self-contained place you reach through an
## entrance in the Backrooms (a vent, a hatch, a door: LevelEntrance, placed
## by LevelEntrances), in the Dead Mall, or from another side level's exit,
## and leave by one of its own exits. Each level is one script,
## scripts/world/levels/<id>_level.gd, extending this; the registry
## (SideLevels) finds it by its id. See scripts/world/levels/README.md.
##
## All side levels live far away from everything else, around LEVEL_Y (the
## Field is at -2000, the Dead Mall at -4000). Only one exists at a time, so
## they all share it: build round (0, LEVEL_Y, 0) and stay within a few
## kilometres of it.
##
## The game sets `player`, `id` and `low`, adds the level to the tree and
## calls build(seed) behind the fade, then puts you at arrival() (or where a
## saved game left you, after load_state()), and calls on_enter(). It reads
## the level's environment, camera_far(), reverb(), wants_flashlight() and
## warm_materials(). While you're in it the player asks the level what you
## stand on (surface_at), how deep the water is (water_level_at) and what
## colour the walls are (albedo_at, for the flashlight's bounce); other
## players' models ask light_at. Leaving, it calls on_leave() and frees it.
##
## A level tells the game what happens through three signals:
##  - exit_entered(to): you went through an exit. "" = back into the
##    Backrooms, somewhere else; another level's id = straight on into that
##    level (a chain). add_exit() places exits that do this for you.
##  - player_caught(lines, how): something got you. The game plays the
##    catch (a jumpscare with `how.scare`, a Walker, or a jolt and a fade),
##    shows `lines` one by one on black, and puts you back in the Backrooms
##    somewhere else. catch_player() emits it.
##  - player_fell(lines): a fall nobody walks away from: the rush of air,
##    the impact, the lines, the Backrooms. fall() emits it; set `fall_kill`
##    and the level notices long falls by itself.

signal exit_entered(to: String)
signal player_caught(lines: Array, how: Dictionary)
signal player_fell(lines: Array)

## Height every side level is built round.
const LEVEL_Y := -8000.0
## Render layer 20: things only the level's own cameras show (a figure seen
## only on the security monitors). The player's camera never draws it; give
## a feed camera a cull_mask that includes it. Set a node's layers to
## FEED_LAYER (only the feeds) or 1 | FEED_LAYER (everyone).
const FEED_LAYER := 1 << 19
const SHADER := "res://shaders/level_lit.gdshader"
const SHADER_CUTOUT := "res://shaders/level_lit_cutout.gdshader"
## Defaults for a surface in load_kit / flat_material (see load_kit).
const SURFACE := {"color": Color(0.6, 0.6, 0.6), "roughness": 0.7, "metallic": 0.0, "specular": 0.4,
		"emit": 0.0, "group": -1, "uv": 0, "scale": Vector2.ONE, "normal_depth": 1.0, "cutout": false}

## You; set by the game before build().
var player: Player
## The level's look (sky or background, fog, tonemap); made in build(). The
## game puts it on the world while you're here. make_environment() makes
## one that follows the graphics settings.
var environment: Environment
## This level's id in SideLevels (e.g. "crawlspace").
var id := ""
## Weak phones (Potato or Low preset): cut what's far off, thicken the fog.
var low := false
## The seed build() was given (same door, same level, for everyone).
var seed_value := 0
## Falling more than this many metres without landing kills you
## (player_fell with fall_lines). 0: off (the player's own safety net puts
## you back on the last floor after 30 m).
var fall_kill := 0.0
var fall_lines: Array = ["The edge wasn't where you thought.", "You fell for a long time.",
		"Then: damp carpet, and the hum."]
## Over the screen while your eyes are under water_level_at() (alpha: how
## strong); transparent for none.
var underwater_tint := Color(0.05, 0.12, 0.1, 0.75)
## Named places from the Blender kits ("spot_*" empties), world transforms:
## spots["spot_exit"], and repeats as name#2, name#3...
var spots := {}
## Kit meshes beyond this distance (m) are hidden on Potato/Low; 0 = never.
var low_view_range := 0.0

var _exit_used: LevelEntrance
var _kit_mats: Array[Material] = []
var _tex_cache := {}
var _shake := 0.0
var _shake_time := 0.0
var _shake_left := 0.0
## Steady camera shake (a train going past), 0.. about 0.05.
var rumble := 0.0
var _shaking := false
var _air_from := INF
var _under: ColorRect
var _done := false


# ---------------------------------------------------------------- virtuals ---

## Builds the level (behind the loading fade): geometry, lights, sounds,
## `environment`. `seed_value` is the same for everyone who came through the
## same entrance.
func build(p_seed: int) -> void:
	seed_value = p_seed
	environment = make_environment()


## Where you arrive (feet position; you face -basis.z).
func arrival() -> Transform3D:
	return Transform3D(Basis(), Vector3(0.0, LEVEL_Y, 0.0))


## Plays the exit you used (a door swinging open, the ride through it) before
## the fade. The default plays the exit's own LevelEntrance.enter().
func open_exit() -> void:
	if _exit_used and is_instance_valid(_exit_used):
		await _exit_used.enter(player)


## Light at a point (other players' models and figures match it).
func light_at(_p: Vector3) -> Color:
	return Color(0.5, 0.5, 0.5)


## Footstep surface at a point (Player.SURF_*). Wading is handled for you.
func surface_at(_p: Vector3) -> int:
	return Player.SURF_CONCRETE


## Height of the water surface over a point, or -INF for no water. Standing
## in more than 0.1 m of it you wade (slower the deeper, splashing steps);
## your eyes under it tint the screen (underwater_tint).
func water_level_at(_p: Vector3) -> float:
	return -INF


## Colour of the surface at p with normal n (the flashlight's bounce light).
func albedo_at(_p: Vector3, _n: Vector3) -> Color:
	return Color(0.55, 0.53, 0.5)


## How far the camera sees (m). Keep it short where you can: past it is
## the environment's background colour, so match the fog to it.
func camera_far() -> float:
	return 150.0


## The torch comes on by itself when you arrive (ducts, tunnels).
func wants_flashlight() -> bool:
	return false


## The echo here: {room, damp, wet} like Ambience.REVERB (0..1 each).
func reverb() -> Dictionary:
	return {"room": 0.7, "damp": 0.5, "wet": 0.3}


## Materials to compile behind the loading fade. By default every material
## made by load_kit() and flat_material(); add your own shaders' here.
func warm_materials() -> Array[Material]:
	return _kit_mats.duplicate()


## Viewpoints for the screenshot harness (_test/levels/level_shots.tscn):
## [{name, transform}] where transform.origin is where you stand (feet) and
## -basis.z where you look (pitch included). Optional keys: "crawl": true
## (shot lying down), "flashlight": true/false, "wait": seconds before the
## shot (default 1.5).
func shots() -> Array:
	var t := arrival()
	return [{"name": "arrival", "transform": t},
			{"name": "behind", "transform": t.rotated_local(Vector3.UP, PI)}]


## A scripted sequence for the harness's movie mode (--movie; record with
## Godot's --write-movie), to check animations. Await whatever you like;
## return when done. The default looks slowly round from the arrival point.
func film() -> void:
	var t := arrival()
	player.teleport(t.origin, _yaw_of(t))
	var y0 := player.yaw
	var k := 0.0
	while k < 1.0:
		k += get_process_delta_time() / 8.0
		player.yaw = y0 + TAU * k
		player._apply_rotation()
		await get_tree().process_frame


## Called once you're in (after the teleport; the fade may still be up).
func on_enter() -> void:
	pass


## Called when you leave, just before the level is freed.
func on_leave() -> void:
	pass


## What to keep in a saved game (positions of moving parts, a counter...).
## Only plain values (numbers, strings, vectors, arrays, dictionaries).
func save_state() -> Dictionary:
	return {}


## Continuing a saved game: called after build(), before on_enter().
func load_state(_d: Dictionary) -> void:
	pass


# ----------------------------------------------------------------- events ---

## Something got you: the game takes it from here (see player_caught).
## how: "scare" (a Walker to rush at you, as the Backrooms' own entities
## do), "sound" (Sfx name for its voice), "from"/"to"/"time" (jumpscare
## distances and length), or nothing for a jolt and a fade.
func catch_player(lines: Array, how := {}) -> void:
	if _done:
		return
	_done = true
	player_caught.emit(lines, how)


## A fall that kills you (see player_fell).
func fall(lines: Array = []) -> void:
	if _done:
		return
	_done = true
	player_fell.emit(lines if not lines.is_empty() else fall_lines)


## An exit was used (LevelEntrance calls this for exits made by add_exit).
func _exit_activated(e: LevelEntrance) -> void:
	if _done:
		return
	_exit_used = e
	exit_entered.emit(e.dest)


# ---------------------------------------------------------------- helpers ---

## Instantiates a Blender kit (GLB from tools/blender/level_kit.py) at `at`
## and gives each of its materials the level shader with this kit's baked
## light. Per Blender material name (".001" suffixes ignored):
##  - `surfaces[name]`: a Dictionary of any of the keys in SURFACE: color
##    (tint; the colour when there's no texture), roughness, metallic,
##    specular, emit (self-lit lamp strength), group (light group 0..3 the
##    lamp belongs to), uv (0 the mesh's UVs, 1 projected from world
##    position), scale (repeats per UV unit, or metres per repeat with uv 1;
##    a float or Vector2), normal_depth, cutout (alpha tested), texture (file
##    name stem to use instead of the material name);
##  - textures, if any, from `textures_dir`: <name>_diff, _nor (OpenGL
##    style), _rough or _arm (roughness in green), .jpg or .png;
##  - names starting with "glass": see-through glass.
## `lightmap`: the colour bake (UV2); `groups`: the light group bake (RGBA,
## UV2), or "" for none. "spot_*" empties land in `spots`; "-colonly"
## meshes are the collision.
func load_kit(glb: String, lightmap := "", textures_dir := "", surfaces := {}, groups := "",
		at := Vector3(0.0, LEVEL_Y, 0.0)) -> Node3D:
	var scene := load(glb) as PackedScene
	if scene == null:
		push_error("SideLevel %s: can't load kit %s" % [id, glb])
		return null
	var inst: Node3D = scene.instantiate()
	inst.name = glb.get_file().get_basename()
	add_child(inst)
	inst.global_position = at
	var lm: Texture2D = load(lightmap) if lightmap != "" else null
	var gm: Texture2D = load(groups) if groups != "" else null
	var made := {}
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if m.mesh == null:
			continue
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if low and low_view_range > 0.0:
			m.visibility_range_end = low_view_range
			m.visibility_range_end_margin = 6.0
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			var mname := _clean_name(src.resource_name if src else "")
			if not made.has(mname):
				made[mname] = _kit_material(mname, surfaces.get(mname, {}), lm, gm, textures_dir)
			m.set_surface_override_material(s, made[mname])
	_collect_spots(inst)
	return inst


## A level shader material without baked light, for parts made in Godot or
## that move (a shelving carriage, a train, a door): lit evenly by `light`,
## plus `group_mix` (how much light it gets from each light group, if the
## level has some). `surf` as in load_kit's surfaces, and "shade" (0..1,
## default 1): faces darker the more they face sideways or down, so boxes
## read as solid without baked light.
func flat_material(surf := {}, light := Color(0.5, 0.5, 0.5), group_mix := Vector4.ZERO, textures_dir := "",
		tex_name := "") -> ShaderMaterial:
	var sm := _surface_material(surf, textures_dir, tex_name if tex_name != "" else String(surf.get("texture", "")))
	sm.set_shader_parameter("has_lightmap", false)
	sm.set_shader_parameter("const_light", Vector3(light.r, light.g, light.b))
	sm.set_shader_parameter("flat_shade", float(surf.get("shade", 1.0)))
	sm.set_shader_parameter("group_mix", group_mix)
	return sm


## A box (procedural geometry): mesh with `mat`, and collision unless told
## not to. Position is its centre, local to `parent` (the level by default).
func add_box(size: Vector3, pos: Vector3, mat: Material, collide := true, parent: Node3D = null) -> MeshInstance3D:
	var p: Node3D = parent if parent else self
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos
	p.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		mi.add_child(body)
	return mi


## An exit at `xf` (world; it faces +Z, the side you stand on, origin on
## the wall or floor at floor level) of one of LevelEntrance's looks
## ("door", "double", "vent", "hatch", "lift", "stairs", or "none": just a
## trigger, for an exit you build yourself). `to`: "" back to the
## Backrooms, or a level id. opts: "label" (the Use prompt), "sign",
## "walk_in" (walking into it is enough), "size" (the walk-in box),
## "script" (your own LevelEntrance subclass, for your own look and ride).
func add_exit(xf: Transform3D, look := "door", to := "", opts := {}) -> LevelEntrance:
	var e: LevelEntrance
	if opts.has("script"):
		e = (load(opts.script) as GDScript).new()
	else:
		e = LevelEntrance.new()
	e.look = look
	e.dest = to
	e.exit_of = self
	e.label = opts.get("label", "")
	e.sign_text = opts.get("sign", "")
	e.walk_in = opts.get("walk_in", look == "none")
	if opts.has("size"):
		e.trigger_size = opts.size
	var lc := light_at(xf.origin)
	e.light = clampf((lc.r + lc.g + lc.b) / 3.0, 0.04, 1.0)
	add_child(e)
	e.global_transform = xf
	return e


## A looping sound: a path (an .ogg / .wav / .mp3 in your assets), an
## AudioStream, or the name of an AudioSynth sound ("hum", "wind", "drip",
## "draught"). Everywhere at once, or in 3D at `at`. opts: "unit_size",
## "max_distance", "pitch", "bus" ("World"), "filter" (low-pass Hz, 3D).
func add_loop(sound: Variant, at := Vector3.INF, volume_db := -12.0, opts := {}) -> Node:
	var st: AudioStream
	if sound is AudioStream:
		st = sound
	elif String(sound).begins_with("res://"):
		st = load(sound)
	else:
		st = AudioSynth.cached(String(sound))
	if st == null:
		push_error("SideLevel %s: no sound %s" % [id, sound])
		return null
	st = st.duplicate()
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	elif st is AudioStreamMP3:
		(st as AudioStreamMP3).loop = true
	elif st is AudioStreamWAV and (st as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_DISABLED:
		var w := st as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	var node: Node
	if at.is_finite():
		var a := AudioStreamPlayer3D.new()
		a.stream = st
		a.volume_db = volume_db
		a.unit_size = opts.get("unit_size", 6.0)
		a.max_distance = opts.get("max_distance", 60.0)
		a.pitch_scale = opts.get("pitch", 1.0)
		a.bus = opts.get("bus", "World")
		if opts.has("filter"):
			a.attenuation_filter_cutoff_hz = opts.filter
		add_child(a)
		a.global_position = at
		a.play()
		node = a
	else:
		var a2 := AudioStreamPlayer.new()
		a2.stream = st
		a2.volume_db = volume_db
		a2.pitch_scale = opts.get("pitch", 1.0)
		a2.bus = opts.get("bus", "World")
		add_child(a2)
		a2.play()
		node = a2
	return node


## A jolt of camera shake that dies away over `time` seconds (strength in
## metres of camera offset: 0.02 a thud, 0.06 a train). For a steady
## shake set `rumble`.
func shake(strength: float, time: float) -> void:
	if strength >= _shake * (_shake_left / maxf(_shake_time, 0.001)):
		_shake = strength
		_shake_time = maxf(time, 0.01)
		_shake_left = _shake_time


## Light group `i` (0..3, the channels of the group bake): colour and
## intensity (0 off, 1 as baked, more for brighter). Shared by every level
## shader material, so call it whenever (every frame for a flicker).
func set_light_group(i: int, color := Color.WHITE, intensity := 1.0) -> void:
	RenderingServer.global_shader_parameter_set("level_light_%d" % clampi(i, 0, 3),
			Vector4(color.r, color.g, color.b, intensity))


## A look that follows the graphics settings (Photoreal grade, bloom,
## brightness), like the Dead Mall's. opts: "background" (Color), "fog"
## (Color), "fog_density", "exposure", "glow" (strength), "saturation",
## "contrast". Tweak the result as you like.
func make_environment(opts := {}) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = opts.get("background", Color(0.0, 0.0, 0.0))
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK
	e.ambient_light_energy = 0.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if Settings.get_value("graphics/photoreal") and not Settings.get_value("graphics/ps1"):
		e.tonemap_mode = Environment.TONE_MAPPER_AGX       # Photoreal grade
		e.tonemap_white = 12.0
	e.tonemap_exposure = float(opts.get("exposure", 1.3)) * float(Settings.get_value("graphics/brightness"))
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = opts.get("fog", e.background_color)
	e.fog_light_energy = 1.0
	var fd: float = opts.get("fog_density", 0.02)
	e.fog_density = fd * (1.8 if low else 1.0)
	e.fog_sky_affect = 0.0
	e.glow_enabled = Settings.get_value("graphics/bloom")
	e.glow_intensity = opts.get("glow", 0.25)
	e.glow_hdr_threshold = 1.6
	e.adjustment_enabled = true
	e.adjustment_contrast = opts.get("contrast", 1.05)
	e.adjustment_saturation = opts.get("saturation", 0.9)
	return e


## One of the CC0 figures (EntityBody: "tall", the stretched black one that
## walks and runs, or "crawler", the base body you pose yourself), lit to
## match where it stands. Call body.move(speed) / body.play(clip) and
## body.update(delta) every frame to animate it. For one that can catch
## you with a jumpscare use make_walker().
func add_figure(xf: Transform3D, who := "tall", tint := Color.WHITE, size := 1.0) -> EntityBody:
	var b := EntityBody.new()
	b.who = who
	b.tint = tint
	b.scale = Vector3.ONE * size
	add_child(b)
	b.global_transform = xf.scaled_local(Vector3.ONE * size)
	b.set_env_light(light_at(xf.origin))
	return b


## A Walker (the Backrooms' entities' base) with a figure, for
## catch_player(lines, {"scare": walker}); you move it and animate its
## `body` yourself (its grid navigation is for the Backrooms only).
func make_walker(who := "tall", size := 1.0, tint := Color.WHITE) -> Walker:
	var w := Walker.new()
	w.player = player
	add_child(w)
	w._make_body(who, size, tint)
	w.visible = true
	return w


static func _yaw_of(t: Transform3D) -> float:
	var f := -t.basis.z
	return atan2(-f.x, -f.z)


static func _pitch_of(t: Transform3D) -> float:
	var f := (-t.basis.z).normalized()
	return asin(clampf(f.y, -1.0, 1.0))


## Materials every level uses (the harness and the loading fade warm them).
static func base_warm_materials() -> Array[Material]:
	var out: Array[Material] = []
	for path in [SHADER, SHADER_CUTOUT]:
		var sm := ShaderMaterial.new()
		sm.shader = load(path)
		out.append(sm)
	return out


# -------------------------------------------------------------- internals ---

## Called by the game before build(): who you are and where.
func _setup(p_player: Player, p_id: String) -> void:
	player = p_player
	id = p_id
	low = int(Settings.get_value("graphics/preset")) <= 1
	var tick := _Ticker.new()
	tick.level = self
	tick.name = "_ticker"
	add_child(tick)
	for i in 4:
		set_light_group(i)


## Called by the game just before it frees the level: put everything shared
## back (camera offsets, light groups, the tint).
func _teardown() -> void:
	if player and _shaking:
		player.camera.h_offset = 0.0
		player.camera.v_offset = 0.0
	_shaking = false
	rumble = 0.0
	for i in 4:
		set_light_group(i)
	if _under:
		_under.visible = false      # (its layer goes with the level)


## What the base does every frame, whatever the level's own _process does.
func _tick(delta: float) -> void:
	if player == null:
		return
	# Camera shake.
	_shake_left = maxf(_shake_left - delta, 0.0)
	var amt := rumble + _shake * (_shake_left / maxf(_shake_time, 0.001))
	if amt > 0.0005 and not _done:
		player.camera.h_offset = randf_range(-1.0, 1.0) * amt
		player.camera.v_offset = randf_range(-1.0, 1.0) * amt
		_shaking = true
	elif _shaking:
		player.camera.h_offset = 0.0
		player.camera.v_offset = 0.0
		_shaking = false
	# Long falls.
	if fall_kill > 0.0 and not _done and player.is_physics_processing():
		if player.is_on_floor() or player.busy():
			_air_from = player.global_position.y
		elif _air_from == INF:
			_air_from = player.global_position.y
		elif _air_from - player.global_position.y > fall_kill:
			fall()
	# Under the water.
	var cam := player.camera.global_position
	var under := underwater_tint.a > 0.0 and cam.y < water_level_at(cam)
	if under and _under == null:
		var layer := CanvasLayer.new()
		layer.layer = 0
		add_child(layer)
		_under = ColorRect.new()
		_under.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
		layer.add_child(_under)
	if _under:
		_under.color = underwater_tint
		_under.visible = under


func _kit_material(mname: String, surf: Dictionary, lm: Texture2D, gm: Texture2D, textures_dir: String) -> Material:
	if mname.begins_with("glass"):
		var g := StandardMaterial3D.new()
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		var c: Color = surf.get("color", Color(0.3, 0.36, 0.35))
		g.albedo_color = Color(c.r, c.g, c.b, 0.12)
		g.roughness = 0.05
		g.metallic_specular = 0.8
		g.emission_enabled = true
		g.emission = c * 0.08
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		g.render_priority = 1
		_kit_mats.append(g)
		return g
	var sm := _surface_material(surf, textures_dir, surf.get("texture", mname))
	sm.set_shader_parameter("has_lightmap", lm != null)
	if lm:
		sm.set_shader_parameter("lightmap", lm)
	sm.set_shader_parameter("has_group_map", gm != null)
	if gm:
		sm.set_shader_parameter("group_map", gm)
	return sm


func _surface_material(surf: Dictionary, textures_dir: String, tex_name: String) -> ShaderMaterial:
	var d := SURFACE.duplicate()
	d.merge(surf, true)
	var sm := ShaderMaterial.new()
	sm.shader = load(SHADER_CUTOUT if d.cutout else SHADER)
	var c: Color = d.color
	sm.set_shader_parameter("albedo", c)
	sm.set_shader_parameter("roughness", d.roughness)
	sm.set_shader_parameter("metallic", d.metallic)
	sm.set_shader_parameter("specular", d.specular)
	sm.set_shader_parameter("emit", d.emit)
	sm.set_shader_parameter("emit_group", int(d.group))
	sm.set_shader_parameter("uv_mode", int(d.uv))
	var sc: Variant = d.scale
	sm.set_shader_parameter("uv_scale", sc if sc is Vector2 else Vector2(float(sc), float(sc)))
	sm.set_shader_parameter("normal_depth", d.normal_depth)
	if textures_dir != "" and tex_name != "":
		var diff := _texture(textures_dir, tex_name, ["_diff", "_color", "_albedo"])
		if diff:
			sm.set_shader_parameter("albedo_tex", diff)
			if not surf.has("color"):
				sm.set_shader_parameter("albedo", Color.WHITE)
		var nor := _texture(textures_dir, tex_name, ["_nor", "_nor_gl", "_normal"])
		if nor:
			sm.set_shader_parameter("normal_tex", nor)
			sm.set_shader_parameter("use_normal", true)
		var rough := _texture(textures_dir, tex_name, ["_rough", "_arm", "_roughness"])
		if rough:
			sm.set_shader_parameter("rough_tex", rough)
			if not surf.has("roughness"):
				sm.set_shader_parameter("roughness", 1.0)
	_kit_mats.append(sm)
	return sm


func _texture(dir: String, stem: String, suffixes: Array) -> Texture2D:
	for suf in suffixes:
		for ext in [".jpg", ".png", ".webp"]:
			var path: String = dir.path_join(stem + suf + ext)
			if _tex_cache.has(path):
				return _tex_cache[path]
			if ResourceLoader.exists(path):
				var t: Texture2D = load(path)
				_tex_cache[path] = t
				return t
	return null


static func _clean_name(n: String) -> String:
	# Blender's duplicate suffixes: "concrete.001" is "concrete".
	var dot := n.rfind(".")
	if dot > 0 and n.substr(dot + 1).is_valid_int():
		return n.substr(0, dot)
	return n


func _collect_spots(root: Node) -> void:
	for n in root.find_children("spot_*", "Node3D", true, false):
		var key := String(n.name)
		var k := key
		var i := 2
		while spots.has(k):
			k = "%s#%d" % [key, i]
			i += 1
		spots[k] = (n as Node3D).global_transform


## Spots whose name starts with `prefix`.
func spots_named(prefix: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for k in spots:
		if String(k).begins_with(prefix):
			out.append(spots[k])
	return out


## Runs the base's per-frame work in its own node, so a level's own
## _process (which needn't call super) never turns it off.
class _Ticker:
	extends Node
	var level: Node             # the SideLevel (untyped: no cycle back to the outer class)

	func _process(delta: float) -> void:
		level.call("_tick", delta)

	func _exit_tree() -> void:
		level.call("_teardown")
