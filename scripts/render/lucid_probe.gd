class_name LucidProbe
extends RefCounted
## L.U.C.I.D. stage 4: reflection probes (docs/LUCID.md, "stage 4").
##
## A probe is the radiance arriving at a point from every direction, in the
## level's own light units, stored as an octahedral map (SIZE texels
## across, RGBE 9-9-9-5, mips box-filtered, so a rough surface reads a
## blurrier mip; lucid_spec.gdshaderinc). It is captured once, when the
## level is built: six 90 degree views of the world rendered into a small
## HDR SubViewport with a linear camera (no tone mapping, no grading), then
## resampled. What the level handles analytically (the lamps and panels
## whose reflections lucid_emitter_cover works out per pixel) is switched
## off while it captures, so nothing is reflected twice. A surface samples
## it box-projected (the reflected ray followed to the room's or street's
## box), which puts the reflection of a wall or a shopfront where it is.

const SIZE := 128
const FACE := 64
## The brightest texel kept (engine units: 7700 cd/m2; the lamps' lenses
## are analytic and left out).
const CLAMP := 50.0
## Look direction and up of the six faces.
const FACES := [[Vector3.RIGHT, Vector3.UP], [Vector3.LEFT, Vector3.UP], [Vector3.UP, Vector3.BACK],
		[Vector3.DOWN, Vector3.FORWARD], [Vector3.BACK, Vector3.UP], [Vector3.FORWARD, Vector3.UP]]


## A linear camera environment for captures: what the shaders output, as is.
static func capture_environment(bg := Color.BLACK) -> Environment:
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = bg
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color.BLACK
	e.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED
	e.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	e.tonemap_exposure = 1.0
	e.glow_enabled = false
	e.fog_enabled = false
	e.adjustment_enabled = false
	e.ssao_enabled = false
	e.ssr_enabled = false
	return e


## Renders the six faces round each of `origins` (global) from `host`'s
## world and returns one array of six RGBA half images per origin. Await
## it. Six small SubViewports, reused for one probe after another (two
## frames a probe: viewports the renderer has made keep some memory after
## they are freed, ~1.4 MB each). `scale` divides what is captured (the
## exposure the shaders applied, per channel). While it runs,
## lucid_capture is 1: the shaders that reflect emitters analytically
## darken those emitters in views whose projection is a 90 degree square
## (only these cameras), so the main view is not affected.
static func capture(host: Node, origins: Array, env: Environment, far := 400.0, scale := Color(1, 1, 1)) -> Array:
	var vps: Array[SubViewport] = []
	var cams: Array[Camera3D] = []
	for f in FACES:
		var vp := SubViewport.new()
		vp.size = Vector2i(FACE, FACE)
		vp.use_hdr_2d = true
		vp.positional_shadow_atlas_size = 0
		vp.msaa_3d = Viewport.MSAA_DISABLED
		vp.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		var cam := Camera3D.new()
		cam.fov = 90.0
		cam.near = 0.05
		cam.far = far
		cam.environment = env
		vp.add_child(cam)
		host.add_child(vp)
		cam.current = true
		vps.append(vp)
		cams.append(cam)
	RenderingServer.global_shader_parameter_set("lucid_capture", 1.0)
	var out := []
	for o: Vector3 in origins:
		for k in 6:
			cams[k].global_transform = Transform3D(Basis.looking_at(FACES[k][0], FACES[k][1]), o)
			vps[k].render_target_update_mode = SubViewport.UPDATE_ONCE
		# One frame to render, one to read back.
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var faces := []
		for k in 6:
			var img := vps[k].get_texture().get_image()
			if img.get_format() != Image.FORMAT_RGBAH:
				img.convert(Image.FORMAT_RGBAH)
			if scale != Color(1, 1, 1):
				for y in FACE:
					for x in FACE:
						var c := img.get_pixel(x, y)
						img.set_pixel(x, y, Color(c.r / scale.r, c.g / scale.g, c.b / scale.b, 1.0))
			faces.append(img)
		out.append(faces)
	RenderingServer.global_shader_parameter_set("lucid_capture", 0.0)
	for vp in vps:
		vp.queue_free()
	return out


## The direction an octahedral map's texel (u, v in 0..1) looks along
## (lucid_oct in the shader is its inverse).
static func oct_dir(u: float, v: float) -> Vector3:
	var o := Vector2(u, v) * 2.0 - Vector2.ONE
	var d := Vector3(o.x, 1.0 - absf(o.x) - absf(o.y), o.y)
	if d.y < 0.0:
		var x := (1.0 - absf(d.z)) * (1.0 if d.x >= 0.0 else -1.0)
		var z := (1.0 - absf(d.x)) * (1.0 if d.z >= 0.0 else -1.0)
		d.x = x
		d.z = z
	return d.normalized()


## Six faces (capture_faces) as an octahedral map with box-filtered mips
## (RGBE 9995: 4 bytes a texel; SIZE 128 is 85 KB with its mips).
static func octahedral(faces: Array) -> Image:
	var bases := []
	for f in FACES:
		bases.append(Basis.looking_at(f[0], f[1]))
	var out := Image.create(SIZE, SIZE, false, Image.FORMAT_RGBAF)
	var fm := float(FACE)
	for y in SIZE:
		for x in SIZE:
			var d := oct_dir((x + 0.5) / SIZE, (y + 0.5) / SIZE)
			var a := d.abs()
			var fi := 0
			if a.x >= a.y and a.x >= a.z:
				fi = 0 if d.x > 0.0 else 1
			elif a.y >= a.z:
				fi = 2 if d.y > 0.0 else 3
			else:
				fi = 4 if d.z > 0.0 else 5
			var l: Vector3 = (bases[fi] as Basis).transposed() * d
			var u := (l.x / -l.z * 0.5 + 0.5) * fm - 0.5
			var v := (-l.y / -l.z * 0.5 + 0.5) * fm - 0.5
			var c := _bilinear(faces[fi], u, v)
			# A texel brighter than CLAMP (a lens left in the view) would
			# spread through the mips as glare.
			var m := maxf(c.r, maxf(c.g, c.b))
			if m > CLAMP:
				c = c * (CLAMP / m)
				c.a = 1.0
			out.set_pixel(x, y, c)
	out.generate_mipmaps()
	out.convert(Image.FORMAT_RGBE9995)
	return out


static func _bilinear(img: Image, u: float, v: float) -> Color:
	var x0 := clampi(floori(u), 0, FACE - 1)
	var y0 := clampi(floori(v), 0, FACE - 1)
	var x1 := mini(x0 + 1, FACE - 1)
	var y1 := mini(y0 + 1, FACE - 1)
	var fx := clampf(u - floorf(u), 0.0, 1.0)
	var fy := clampf(v - floorf(v), 0.0, 1.0)
	var c := img.get_pixel(x0, y0).lerp(img.get_pixel(x1, y0), fx).lerp(img.get_pixel(x0, y1).lerp(img.get_pixel(x1, y1), fx), fy)
	c.a = 1.0
	return c


## Probe maps as one texture array (every image the same size and mips).
static func array_texture(maps: Array[Image]) -> Texture2DArray:
	var t := Texture2DArray.new()
	t.create_from_images(maps)
	return t


## Memory of a set of probe maps (bytes).
static func bytes(maps: Array[Image]) -> int:
	var n := 0
	for m in maps:
		n += m.get_data().size()
	return n
