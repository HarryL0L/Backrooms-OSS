class_name WorldMaterials
extends RefCounted
## Creates the shared world materials. All textures are generated procedurally
## from seamless noise at startup, so the game ships without image assets.

var materials: Array[Material] = []
var _noise_fine: NoiseTexture2D
var _noise_blot: NoiseTexture2D
var _noise_normal: NoiseTexture2D


func _init() -> void:
	_noise_fine = _noise(256, 0.035, 5, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, false, 1)
	_noise_blot = _noise(256, 0.012, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, false, 2)
	_noise_normal = _noise(256, 0.05, 4, FastNoiseLite.TYPE_SIMPLEX_SMOOTH, true, 3)
	materials.resize(ChunkBuilder.MAT_COUNT)
	materials[ChunkBuilder.MAT_WALLPAPER] = _mat("wallpaper")
	materials[ChunkBuilder.MAT_CARPET] = _mat("carpet")
	materials[ChunkBuilder.MAT_CEILING_TILE] = _mat("ceiling_tile")
	materials[ChunkBuilder.MAT_POOL_TILE] = _mat("pool_tile")
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
	# Photographed materials for Photoreal, if any are in assets/textures/.
	# (metres per repeat: a real carpet / paper / tile sample is ~1-2 m.)
	_photo([ChunkBuilder.MAT_CARPET], "carpet", 1.5)
	_photo([ChunkBuilder.MAT_WALLPAPER], "wallpaper", 1.2)
	_photo([ChunkBuilder.MAT_CEILING_TILE], "ceiling_tile", 1.2)
	_photo([ChunkBuilder.MAT_CONC_WALL, ChunkBuilder.MAT_CONC_FLOOR, ChunkBuilder.MAT_CONC_CEIL], "concrete", 2.0)


## Optional photo textures: assets/textures/<surface>/albedo.(jpg|png|webp) and
## normal.(...). Only used in the Photoreal preset; their average colour is
## divided out, so a photo adds the real grain and wear but not its own tint.
## Use only CC0 or your own photos.
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
	img.resize(1, 1, Image.INTERPOLATE_BILINEAR)
	var mean := img.get_pixel(0, 0)
	for m in mats:
		var sm := materials[m] as ShaderMaterial
		sm.set_shader_parameter("photo_albedo", albedo)
		if normal:
			sm.set_shader_parameter("photo_normal", normal)
		sm.set_shader_parameter("photo_scale", scale)
		sm.set_shader_parameter("photo_mean", Vector3(mean.r, mean.g, mean.b))
		sm.set_shader_parameter("photo_on", 1.0)
	print("Photoreal: using photo texture for ", surface)


static func _find_tex(base: String) -> Texture2D:
	for ext in ["jpg", "png", "webp"]:
		var path := "%s.%s" % [base, ext]
		if ResourceLoader.exists(path):
			return load(path)
	return null


func set_world_seed(seed_value: int) -> void:
	for m in materials:
		(m as ShaderMaterial).set_shader_parameter("world_seed", seed_value & 0x7FFFFFFF)


func are_textures_ready() -> bool:
	for t in [_noise_fine, _noise_blot, _noise_normal]:
		if t.get_image() == null:
			return false
	return true


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
