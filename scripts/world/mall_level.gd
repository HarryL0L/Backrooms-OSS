class_name MallLevel
extends Node3D
## The Dead Mall: a closed-down shopping mall, built in Blender
## (tools/blender/mall_kit.py) as tileable sections with baked lighting.
## Entrance, three concourse sections (an arcade, a leaking roof), the
## Fountain Court, a cafe row, the food court, the first three again, and the
## department store at the far end: about 240 m. Three floors: galleries
## round an atrium that runs the whole length under a glass vault, shops on
## every level; in the Fountain Court the escalators (still running) and a
## glass lift (still working) go up. "Fountain Court" drifts from the
## ceiling speakers. Nobody else is here.
##
## It lives far below the Backrooms (MALL_Y), like the Field. Sections run
## along +X from the entrance; the concourse is 12 m wide (z -6..6).

signal exit_entered

const MALL_Y := -4000.0
const NAME := "The Dead Mall"
const MUSIC := "res://music/fountain_court.ogg"
const LAYOUT := [["entrance", 20.0], ["concourse_a", 20.0], ["concourse_c", 20.0], ["concourse_b", 20.0],
		["fountain_court", 24.0], ["concourse_d", 20.0], ["food_court", 20.0],
		["concourse_a", 20.0], ["concourse_c", 20.0], ["concourse_b", 20.0], ["department_store", 32.0]]
## [pattern, colour, roughness, emission] per Blender material name.
const SURFACES := {
	"terrazzo": [1, Color(0.56, 0.52, 0.46), 0.3, 0.0], "tile_white": [2, Color(0.8, 0.79, 0.75), 0.3, 0.0],
	"wall_paint": [0, Color(0.64, 0.57, 0.46), 0.85, 0.0], "ceiling_tile": [3, Color(0.74, 0.72, 0.66), 0.9, 0.0],
	"light_panel": [0, Color(1.0, 0.97, 0.9), 0.5, 1.3], "light_dead": [0, Color(0.45, 0.45, 0.43), 0.5, 0.0],
	"metal_frame": [0, Color(0.17, 0.14, 0.11), 0.45, 0.0], "metal_bright": [0, Color(0.62, 0.62, 0.6), 0.3, 0.0],
	"shutter": [6, Color(0.5, 0.5, 0.48), 0.55, 0.0], "sign_red": [0, Color(0.52, 0.09, 0.07), 0.5, 0.0],
	"sign_teal": [0, Color(0.1, 0.38, 0.38), 0.5, 0.0], "sign_cream": [0, Color(0.82, 0.76, 0.62), 0.5, 0.0],
	"concrete": [0, Color(0.52, 0.5, 0.46), 0.9, 0.0], "brick": [0, Color(0.46, 0.26, 0.19), 0.9, 0.0],
	"soil": [4, Color(0.13, 0.1, 0.07), 0.95, 0.0], "plant_dead": [0, Color(0.32, 0.25, 0.14), 0.8, 0.0],
	"wood": [5, Color(0.44, 0.28, 0.16), 0.6, 0.0], "stone": [1, Color(0.72, 0.68, 0.6), 0.45, 0.0],
	"water": [0, Color(0.06, 0.08, 0.07), 0.05, 0.0], "plastic_orange": [0, Color(0.76, 0.34, 0.09), 0.45, 0.0],
	"plastic_yellow": [0, Color(0.86, 0.71, 0.12), 0.45, 0.0], "fabric": [4, Color(0.36, 0.31, 0.33), 0.9, 0.0],
	"dark": [0, Color(0.02, 0.02, 0.02), 0.9, 0.0], "carpet": [4, Color(0.27, 0.19, 0.21), 0.95, 0.0],
	"screen": [0, Color(0.1, 0.25, 0.2), 0.3, 0.6],
}

var player: Player
var environment: Environment
var length := 0.0
## Named places from the Blender kit ("spot_*" empties), world transforms.
var spots := {}
var _base_exposure := 1.45
var _door: OddDoor
var _music: AudioStreamPlayer
var _hum: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()
static var _mats := {}


## Weak phones (Potato/Low): far sections hidden in thicker haze.
var low := false


func build(seed_value: int) -> void:
	_rng.seed = seed_value
	low = int(Settings.get_value("graphics/preset")) <= 1
	var x := 0.0
	for e in LAYOUT:
		var sec: String = e[0]
		var ln: float = e[1]
		var inst: Node3D = (load("res://assets/mall/%s.glb" % sec) as PackedScene).instantiate()
		inst.name = "%s_%d" % [sec, get_child_count()]
		add_child(inst)
		inst.position = Vector3(x + ln * 0.5, MALL_Y, 0.0)
		_prepare(inst, sec)
		x += ln
	length = x
	_collect_spots()
	_build_movers()
	environment = _make_environment()
	_place_exit()
	_music = AudioStreamPlayer.new()
	var st: AudioStream = load(MUSIC).duplicate()
	if st is AudioStreamOggVorbis:
		(st as AudioStreamOggVorbis).loop = true
	_music.stream = st
	_music.volume_db = -11.0
	_music.bus = "World"
	add_child(_music)
	_music.play()
	_hum = AudioStreamPlayer.new()
	_hum.stream = AudioSynth.cached("hum")
	_hum.volume_db = -20.0
	_hum.bus = "World"
	add_child(_hum)
	_hum.play()


## Swaps each Blender material for the mall shader with this section's
## lightmap (one material per section type and surface, shared).
func _prepare(inst: Node3D, sec: String) -> void:
	var lm: Texture2D = load("res://assets/mall/lightmaps/%s.png" % sec)
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		if low:
			m.visibility_range_end = 62.0
			m.visibility_range_end_margin = 6.0
			m.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		for s in m.mesh.get_surface_count():
			var src := m.mesh.surface_get_material(s)
			var mname := src.resource_name if src else ""
			m.set_surface_override_material(s, _material(sec, mname, lm))


static func _material(sec: String, mname: String, lm: Texture2D) -> Material:
	var key := sec + "/" + mname
	if _mats.has(key):
		return _mats[key]
	var sm := ShaderMaterial.new()
	if mname == "glass":
		sm.shader = load("res://shaders/mall_glass.gdshader")
		sm.render_priority = 1
	else:
		sm.shader = load("res://shaders/mall.gdshader")
		var d: Array = SURFACES.get(mname, [0, Color(0.6, 0.6, 0.6), 0.7, 0.0])
		sm.set_shader_parameter("pattern", d[0])
		sm.set_shader_parameter("albedo", d[1])
		sm.set_shader_parameter("roughness", d[2])
		sm.set_shader_parameter("emit", d[3])
		sm.set_shader_parameter("floor_y", MALL_Y)
		sm.set_shader_parameter("grime", 0.1 if mname.begins_with("light") else 0.35)
	sm.set_shader_parameter("lightmap", lm)
	_mats[key] = sm
	return sm


## The mall's look for the moving parts (escalator steps, the lift), lit
## evenly at `light` instead of by a baked lightmap.
static func lit_material(mname: String, light: float) -> Material:
	var sec := "lit%.2f" % light
	if _mats.has(sec + "/" + mname):
		return _mats[sec + "/" + mname]
	if mname == "glass":
		# Clear: the lift's glass is seen through twice (car and shaft).
		var g := StandardMaterial3D.new()
		g.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		g.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		g.albedo_color = Color(0.62, 0.7, 0.68, 0.1)
		g.cull_mode = BaseMaterial3D.CULL_DISABLED
		_mats[sec + "/" + mname] = g
		return g
	var img := Image.create(1, 1, false, Image.FORMAT_RGB8)
	var v := sqrt(clampf(light / 4.0, 0.0, 1.0))
	img.set_pixel(0, 0, Color(v, v, v))
	return _material(sec, mname, ImageTexture.create_from_image(img))


## For the loading screen's shader warm-up.
static func warm_materials() -> Array[Material]:
	var out: Array[Material] = []
	for path in ["res://shaders/mall.gdshader", "res://shaders/mall_glass.gdshader"]:
		var sm := ShaderMaterial.new()
		sm.shader = load(path)
		out.append(sm)
	return out


func _collect_spots() -> void:
	for n in find_children("spot_*", "Node3D", true, false):
		var t := (n as Node3D).global_transform
		var key := String(n.name)
		# Several sections repeat: keep every copy as name, name#2, ...
		var k := key
		var i := 2
		while spots.has(k):
			k = "%s#%d" % [key, i]
			i += 1
		spots[k] = t


## The escalators and the lift, where the kit left room for them.
func _build_movers() -> void:
	for k in spots:
		var t: Transform3D = spots[k]
		t.basis = t.basis.orthonormalized()
		if String(k).begins_with("spot_esc_"):
			var e := MallEscalator.new()
			e.player = player
			add_child(e)
			e.global_transform = t
		elif String(k).begins_with("spot_lift"):
			var l := MallLift.new()
			add_child(l)
			l.global_transform = t


## Spots whose name starts with `prefix`.
func spots_named(prefix: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for k in spots:
		if String(k).begins_with(prefix):
			out.append(spots[k])
	return out


func _place_exit() -> void:
	if not spots.has("spot_exit"):
		return
	_door = OddDoor.new()
	_door.mall = true
	_door.inside_mall = true
	add_child(_door)
	var t: Transform3D = spots["spot_exit"]
	_door.global_position = t.origin
	_door.rotation.y = PI * 0.5    # set in the entrance glazing, facing +X into the mall
	_door.entered.connect(func() -> void: exit_entered.emit())


## Where you come in: just inside the entrance, looking down the concourse.
func arrival() -> Transform3D:
	var t: Transform3D = spots.get("spot_arrival", Transform3D(Basis(), Vector3(4.0, MALL_Y, 2.0)))
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), t.origin)


func open_exit() -> void:
	if _door:
		await _door.open()


func _make_environment() -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	# What shows through the skylights: a dull dusk sky.
	e.background_color = Color(0.16, 0.18, 0.23)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK
	e.ambient_light_energy = 0.0
	e.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	if Settings.get_value("graphics/photoreal") and not Settings.get_value("graphics/ps1"):
		e.tonemap_mode = Environment.TONE_MAPPER_AGX       # Photoreal grade
		e.tonemap_white = 12.0
	_base_exposure = 1.45 * float(Settings.get_value("graphics/brightness"))
	e.tonemap_exposure = _base_exposure
	e.fog_enabled = true
	e.fog_mode = Environment.FOG_MODE_EXPONENTIAL
	e.fog_light_color = Color(0.2, 0.19, 0.17)
	e.fog_light_energy = 0.5
	e.fog_density = 0.034 if low else 0.018
	e.fog_sky_affect = 0.0
	e.glow_enabled = Settings.get_value("graphics/bloom")
	e.glow_intensity = 0.25
	e.glow_hdr_threshold = 1.6
	e.adjustment_enabled = true
	e.adjustment_contrast = 1.05
	e.adjustment_saturation = 0.85
	return e


## Light level at a point (for the entity and players to match the room).
func light_at(_p: Vector3) -> Color:
	return Color(0.55, 0.53, 0.5)
