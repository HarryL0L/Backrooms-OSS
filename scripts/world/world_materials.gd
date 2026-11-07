class_name WorldMaterials
extends RefCounted
## Creates the shared world materials. All textures are generated procedurally
## from seamless noise at startup, so the game ships without image assets.

var materials: Array[Material] = []
var _noise_fine: NoiseTexture2D
var _noise_blot: NoiseTexture2D
var _noise_normal: NoiseTexture2D
var _noise_caustic: NoiseTexture2D
var _photos_loaded := false


func _init() -> void:
	_noise_fine = _noise(256, 0.035, 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, false, 1)
	_noise_blot = _noise(256, 0.012, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, false, 2)
	_noise_normal = _noise(256, 0.05, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, true, 3)
	_noise_caustic = _caustic_noise()
	materials.resize(ChunkBuilder.MAT_COUNT)
	materials[ChunkBuilder.MAT_WALLPAPER] = _mat("wallpaper")
	materials[ChunkBuilder.MAT_CARPET] = _mat("carpet")
	materials[ChunkBuilder.MAT_CEILING_TILE] = _mat("ceiling_tile")
	materials[ChunkBuilder.MAT_POOL_TILE] = _mat("pool_tile")
	materials[ChunkBuilder.MAT_POOL_TILE].set_shader_parameter("noise_caustic", _noise_caustic)
	materials[ChunkBuilder.MAT_WATER] = _mat("water")
	materials[ChunkBuilder.MAT_WATER].render_priority = 1
	materials[ChunkBuilder.MAT_CONC_WALL] = _mat("concrete", {"kind": 0})
	materials[ChunkBuilder.MAT_CONC_FLOOR] = _mat("concrete", {"kind": 1})
	materials[ChunkBuilder.MAT_CONC_CEIL] = _mat("concrete", {"kind": 2})
	materials[ChunkBuilder.MAT_LIGHT] = _mat("light_panel")
	materials[ChunkBuilder.MAT_CRATE] = _mat("crate")
	materials[ChunkBuilder.MAT_CHROME] = _mat("metal", {"base_color": Color(0.8, 0.82, 0.85), "metal": 1.0, "rough": 0.12, "rust": 0.0})
	materials[ChunkBuilder.MAT_PIPE] = _mat("metal", {"base_color": Color(0.22, 0.2, 0.18), "metal": 0.7, "rough": 0.55, "rust": 1.0})
	materials[ChunkBuilder.MAT_OUTLET] = _mat("metal", {"base_color": Color(0.86, 0.84, 0.78), "metal": 0.0, "rough": 0.45, "rust": 0.0})
	materials[ChunkBuilder.MAT_SHAFT] = _mat("light_shaft")
	materials[ChunkBuilder.MAT_SHAFT].render_priority = 2
	materials[ChunkBuilder.MAT_GRIME] = _mat("concrete", {"kind": 3})
	materials[ChunkBuilder.MAT_BRICK] = _mat("concrete", {"kind": 4})
	materials[ChunkBuilder.MAT_HALO] = _mat("light_halo")
	materials[ChunkBuilder.MAT_HALO].render_priority = 3
	materials[ChunkBuilder.MAT_TRIM] = _mat("trim")
	materials[ChunkBuilder.MAT_GARAGE_FLOOR] = _mat("concrete", {"kind": 5, "base_color": Color(0.42, 0.42, 0.41)})
	materials[ChunkBuilder.MAT_GARAGE_COLUMN] = _mat("concrete", {"kind": 6})
	materials[ChunkBuilder.MAT_BLOCK_WALL] = _mat("concrete", {"kind": 7, "base_color": Color(0.5, 0.49, 0.46)})
	# Warehouse pallet racking: safety-orange steel, chipped.
	materials[ChunkBuilder.MAT_RACK] = _mat("metal", {"base_color": Color(0.92, 0.36, 0.0), "metal": 0.0, "rough": 0.6, "rust": 0.2})


## Photographed materials from assets/textures/ (CC0, see LICENSE.md there),
## used in the Realistic preset: they carry the real fibres, woodchip and
## fissures; the shaders keep the game's own colours. Loaded the first time
## Realistic is switched on, so the other presets don't hold them in memory.
## (Metres per repeat: a real carpet / paper sample is ~1-2 m.)
func _load_photos() -> void:
	_photos_loaded = true
	_photo([ChunkBuilder.MAT_CARPET], "carpet", 1.7)
	_photo([ChunkBuilder.MAT_WALLPAPER], "wallpaper", 1.2)
	_photo([ChunkBuilder.MAT_CEILING_TILE], "ceiling_tile", 3.6)    # 6 x 6 tiles of 0.6 m
	_photo([ChunkBuilder.MAT_CONC_WALL, ChunkBuilder.MAT_CONC_FLOOR, ChunkBuilder.MAT_CONC_CEIL], "concrete", 2.0)


## Optional photo textures: assets/textures/<surface>/albedo.(jpg|png|webp) and
## normal.(...). Used in the Realistic preset; their average colour is
## divided out, so a photo brings its real grain and relief at full strength
## but not its own tint. Use only CC0 or your own photos.
func _photo(mats: Array, surface: String, scale: float) -> void:
	var albedo := _find_tex("res://assets/textures/%s/albedo" % surface)
	if albedo == null:
		return
	var normal := _find_tex("res://assets/textures/%s/normal" % surface)
	var img := albedo.get_image()
	if img == null:
		return
	img = img.duplicate()
	if img.is_compressed():
		img.decompress()
	# The mean the shader divides by must be in the same space it samples
	# in: the photo is a source_color (sRGB) texture, read back as linear,
	# so average its linear values. (Averaging the sRGB bytes made the
	# detail average ~0.5 instead of 1: every photo material came out at
	# about half its albedo.) Halving step by step averages every pixel;
	# one bilinear resize to 1 x 1 would only sample a few.
	img.convert(Image.FORMAT_RGBA8)
	img.srgb_to_linear()
	img.convert(Image.FORMAT_RGBAF)
	while img.get_width() > 1 or img.get_height() > 1:
		img.resize(maxi(img.get_width() / 2, 1), maxi(img.get_height() / 2, 1), Image.INTERPOLATE_BILINEAR)
	var mean := img.get_pixel(0, 0)
	for m in mats:
		var sm := materials[m] as ShaderMaterial
		sm.set_shader_parameter("photo_albedo", albedo)
		if normal:
			sm.set_shader_parameter("photo_normal", normal)
		sm.set_shader_parameter("photo_scale", scale)
		sm.set_shader_parameter("photo_mean", Vector3(mean.r, mean.g, mean.b))
		sm.set_shader_parameter("photo_on", 1.0)
	print("Using photo texture for ", surface)


static func _find_tex(base: String) -> Texture2D:
	for ext in ["jpg", "png", "webp"]:
		var path := "%s.%s" % [base, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


## Realistic preset: material values nearer real ones, per material:
## {parameter: [default, Realistic]}. Only uniforms change (nothing extra
## per pixel). The wallpaper is an aged cream-yellow rather than lime, the
## carpet a duller tan, the ceiling tiles (lit only by bounce) a little
## greyer, and the sun shafts a faint haze, not bright beams.
const REALISTIC := {
	ChunkBuilder.MAT_WALLPAPER: {"base_color": [Color(0.80, 0.79, 0.50), Color(0.80, 0.75, 0.50)],
			"stripe_color": [Color(0.62, 0.68, 0.64), Color(0.66, 0.65, 0.56)]},
	ChunkBuilder.MAT_CARPET: {"base_color": [Color(0.50, 0.46, 0.28), Color(0.48, 0.43, 0.29)]},
	ChunkBuilder.MAT_CEILING_TILE: {"tile_color": [Color(0.84, 0.83, 0.74), Color(0.80, 0.79, 0.75)],
			"bar_color": [Color(0.60, 0.58, 0.52), Color(0.58, 0.57, 0.54)]},
	ChunkBuilder.MAT_SHAFT: {"strength": [0.22, 0.09]},
}


## L.U.C.I.D. (Realistic): the Lobby's surfaces at their measured albedo
## (Lucid.ALBEDO, mean linear reflectance). {material: [parameter, albedo
## name, shader mean]}: the shaders darken their base colour with pattern,
## stains and wear (Realistic), on average by `shader mean` (estimated from
## each shader's terms), so base = albedo / mean, as an sRGB colour (the
## uniforms are source_color: the engine converts them back to linear).
const LUCID := {
	ChunkBuilder.MAT_WALLPAPER: ["base_color", "wallpaper_yellow_aged", 0.87],
	ChunkBuilder.MAT_CARPET: ["base_color", "carpet_tan_damp", 0.81],
	ChunkBuilder.MAT_CEILING_TILE: ["tile_color", "ceiling_tile_aged", 0.77],
	ChunkBuilder.MAT_TRIM: ["base_color", "trim_offwhite", 0.93],
}


## The sRGB base colour that gives material `m` its Lucid albedo.
static func lucid_base(m: int) -> Color:
	var e: Array = LUCID[m]
	var a: Color = Lucid.ALBEDO[e[1]] / float(e[2])
	return Color(minf(a.r, 1.0), minf(a.g, 1.0), minf(a.b, 1.0)).linear_to_srgb()


## Switches the materials between their default and Realistic values.
func set_realistic(on: bool) -> void:
	if on and not _photos_loaded:
		_load_photos()
	for m in REALISTIC:
		var p: Dictionary = REALISTIC[m]
		for k in p:
			(materials[m] as ShaderMaterial).set_shader_parameter(k, p[k][1] if on else p[k][0])
	# Stage 4: the Tiled Baths' panels, whose reflections the glazed tiles
	# work out analytically.
	var pfx: Dictionary = Lucid.FIXTURES[WorldGen.LUCID_FIXTURE[WorldGen.POOL]]
	# (A Vector3: Godot would take a Color for an sRGB one.)
	var prad := Lucid.face_engine(pfx, WorldGen.LUCID_LLF[WorldGen.POOL])
	(materials[ChunkBuilder.MAT_POOL_TILE] as ShaderMaterial).set_shader_parameter("panel_rad", Vector3(prad.r, prad.g, prad.b))
	var trim_default := Color(0.84, 0.82, 0.74)
	for m in LUCID:
		var e: Array = LUCID[m]
		if on and ChunkBuilder.lucid:
			(materials[m] as ShaderMaterial).set_shader_parameter(e[0], lucid_base(m))
		elif m == ChunkBuilder.MAT_TRIM:
			(materials[m] as ShaderMaterial).set_shader_parameter(e[0], trim_default)


func set_world_seed(seed_value: int) -> void:
	for m in materials:
		(m as ShaderMaterial).set_shader_parameter("world_seed", seed_value & 0x7FFFFFFF)


func are_textures_ready() -> bool:
	for t in [_noise_fine, _noise_blot, _noise_normal, _noise_caustic]:
		if t.get_image() == null:
			return false
	return true


## Distance to the nearest cell edge (cellular noise, distance2 - distance):
## near 0 along a net of lines, like the bright web light makes on a pool
## bottom. 8 cells across the 256 px tile.
static func _caustic_noise() -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = FastNoiseLite.TYPE_CELLULAR
	n.frequency = 8.0 / 256.0
	n.fractal_type = FastNoiseLite.FRACTAL_NONE
	n.cellular_distance_function = FastNoiseLite.DISTANCE_EUCLIDEAN
	n.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	n.cellular_jitter = 0.9
	n.seed = 1341
	var t := NoiseTexture2D.new()
	t.width = 256
	t.height = 256
	t.seamless = true
	t.seamless_blend_skirt = 0.1
	t.noise = n
	t.generate_mipmaps = true
	t.normalize = true
	return t


func _mat(shader_name: String, params := {}) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/%s.gdshader" % shader_name)
	m.set_shader_parameter("noise_fine", _noise_fine)
	m.set_shader_parameter("noise_blot", _noise_blot)
	m.set_shader_parameter("noise_normal", _noise_normal)
	for k in params:
		m.set_shader_parameter(k, params[k])
	return m


static func _noise(size: int, freq: float, octaves: int, type: int, normal: bool, s: int) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.noise_type = type
	n.frequency = freq
	n.fractal_octaves = octaves
	n.fractal_type = FastNoiseLite.FRACTAL_FBM
	n.seed = 1337 + s
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.seamless_blend_skirt = 0.15
	t.noise = n
	t.generate_mipmaps = true
	if normal:
		t.as_normal_map = true
		t.bump_strength = 6.0
	else:
		t.normalize = true
	return t
