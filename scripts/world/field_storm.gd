class_name FieldStorm
extends Node3D
## The Field's weather: a tornadic supercell on a summer afternoon
## (docs/FIELD_STORM.md). FieldLevel owns one and calls update() every
## frame. It keeps the storm's layout (its mesocyclone and wall cloud, the
## tornado under it, the precipitation core, the base, the anvil and the
## tower that hides the sun), one wind field and one rain field (globals
## field_*, shared by the sky, the ground, the grass, the tornado and the
## rain, so everything moves together), the physical camera that exposes
## it (Lucid.Camera), the lightning and thunder (LucidStorm), the falling
## rain (LucidRain), the tornado's funnel and debris cloud, and the sound.
##
## The storm stands at real distances from the player and keeps them: its
## layout is anchored to where you are, so walking toward the tornado never
## brings it closer (the field is endless). It never comes for you.

const TORNADO_SHADER := preload("res://shaders/field_tornado.gdshader")
const AUDIO := "res://assets/levels/field/audio/"

## The layout (m, from the player; north is -Z): the mesocyclone 4.6 km off
## to the north-north-west (azimuth 340), the precipitation core 10 km off
## to the north-north-east (70 mm/h at its heart, Gaussian, 4 km), the
## rain-free base round both (1.2 km up), the anvil spread overhead and
## downwind to the east (10 km up).
const MESO := Vector2(-1573.0, -4323.0)
const CORE := Vector2(3420.0, -9400.0)
const CORE_R := 5000.0
const CORE_RATE := 70.0
const BASE_C := Vector2(-300.0, -4400.0)
const BASE_R := 5000.0
const BASE_H := 1200.0
const ANVIL_C := Vector2(10000.0, -6000.0)
const ANVIL_R := 24000.0
const ANVIL_H := 10000.0
## The whole storm drifts east-north-east and back over 25 minutes (up to
## 6.7 m/s across the view).
const DRIFT_AMP := 1600.0
const DRIFT_PERIOD := 1500.0
const DRIFT_DIR := Vector2(0.94, -0.34)
## The sun, late afternoon, behind the storm (azimuth 318, 21 degrees up):
## its beam through hazy summer air, its colour.
const SUN_AZ := 318.0
const SUN_ALT := 21.0
const SUN_LUX := 65000.0
const SUN_K := 4800.0
## The light under the storm: the shaded air and sky (cd/m2, about a
## tenth of a bright overcast's), its colour; what sunlit hazy air adds;
## the haze's extinction (1/m: ~40 km visibility in the inflow).
const SHADE_NITS := 230.0
const SHADE_K := 7500.0
const SUNAIR_NITS := 1800.0
const HAZE := 1.0e-4
## The inflow (m/s at 2 m, toward the mesocyclone) and how it varies.
const INFLOW := 9.0
## A rain band every BAND_PERIOD s: it forms BAND_START m away on the
## core's side (north-east) and sweeps over you toward the south-west at
## BAND_SPEED m/s, its gust front ahead, passing east of the tornado.
const BAND_SPEED := 13.0
const BAND_DIR := Vector2(-0.7071, 0.7071)
const BAND_START := -5200.0
const BAND_PERIOD := 720.0
## The tornado's life (s): forming, mature, roping out, lifting, gone.
const T_FORM := 35.0
const T_MATURE := 210.0
const T_ROPE := 70.0
const T_LIFT := 25.0
const T_GAP := 50.0
## As in field_storm.gdshaderinc.
const BAND_W := 1400.0
const BAND_L := 3200.0
const BAND_A := -1800.0
const FRONT := 2600.0
const OUTFLOW := 17.0
const TI_IN := 0.32
const TI_OUT := 0.5
const HOOK := Vector2(900.0, 500.0)
const HOOK_R := 1400.0
const HOOK_RATE := 7.0
const WALL_DROP := 600.0

## Thunder recordings by distance class: [name, made for (m), up to (m)].
const THUNDER := [["thunder_near", 1600.0, 2600.0], ["thunder_mid", 4000.0, 6500.0], ["thunder_far", 9000.0, 1e9]]

var cam: Lucid.Camera
var lightning: LucidStorm
var rain: LucidRain
var low := false
## Where the storm is laid out from (world xz: the player).
var anchor := Vector2.ZERO
var t := 0.0
## How far the air has moved (m), how wet the grass is (0 .. 1).
var advect := 0.0
var wetness := 0.0
## The band's clock and peak (mm/h).
var band_phase := 40.0
var band_rate := 38.0
## The tornado's age in its cycle (s).
var tornado_age := T_FORM + 50.0
var presence := 0.0
## The wind (m/s, at 2 m) and the rain (mm/h) where you stand.
var wind_here := Vector3.ZERO
var rain_here := 0.0

var _rng := RandomNumberGenerator.new()
var _wind_mean := Vector2.ZERO
var _band_p := Vector2.ZERO
var _band_n := Vector2.ZERO
var _band_now := 0.0
var _core := Vector2.ZERO
var _meso := Vector2.ZERO
var _spin := 0.0
var _meso_turn := 0.0
var _foot := Vector2.ZERO
var _flash: DirectionalLight3D
var _tor: MeshInstance3D
var _deb: MeshInstance3D
var _tor_mat: ShaderMaterial
var _deb_mat: ShaderMaterial
var _wind_snd: AudioStreamPlayer
var _rain_snd: AudioStreamPlayer
var _roar_snd: AudioStreamPlayer
var _sounds := {}
var _cam_prev := Vector3.INF
var _cam_vel := Vector3.ZERO
var _rain_on := true


func setup(p_seed: int, noise: Texture2D, p_low: bool) -> void:
	_rng.seed = p_seed
	low = p_low
	top_level = true
	global_transform = Transform3D.IDENTITY
	cam = Lucid.Camera.new()
	# A phone's daylight program, aiming a little under mid grey: a storm
	# should look dark, and the bright horizon must not burn out.
	cam.compensation = -0.2
	cam.headroom = 2.5
	band_rate = _rng.randf_range(30.0, 45.0)
	lightning = LucidStorm.new()
	lightning.name = "Lightning"
	add_child(lightning)
	lightning.setup(p_seed, FieldLevel.FIELD_Y, low)
	lightning.driven = true
	lightning.focus_r = 4500.0
	# A supercell flashes far more than the Blue Hour's storm: a visible
	# flash every ~15 s, more as a band comes over.
	lightning.lam_base = 1.0 / 16.0
	lightning.lam_burst = 1.0 / 8.0
	lightning.thunder.connect(_thunder)
	lightning.set_bolt_colours(Color(1.25, 1.0, 1.3), Color(0.82, 0.84, 0.92))
	_flash = DirectionalLight3D.new()
	_flash.shadow_enabled = false
	_flash.visible = false
	add_child(_flash)
	_build_tornado(noise)
	_build_audio()
	Settings.changed.connect(_settings)
	_settings()
	_layout(0.0)


func _settings() -> void:
	lightning.reduce = bool(Settings.get_value("gameplay/reduce_flashing"))
	var on := bool(Settings.get_value("graphics/rain"))
	if on and rain == null:
		rain = LucidRain.new()
		rain.name = "Rain"
		add_child(rain)
		if low:
			rain.setup(1500, 150, 0, 0, Vector3(0.0, FieldLevel.FIELD_Y, 0.0))
		else:
			rain.setup(4000, 400, 0, 0, Vector3(0.0, FieldLevel.FIELD_Y, 0.0))
		rain.material.set_shader_parameter("ground_kind", 1)
		rain.material.set_shader_parameter("roof", Vector4.ZERO)
		rain.set_lights([], Color(0, 0, 0))
	_rain_on = on
	if rain != null:
		rain.visible = on
	if not on:
		HUD.lens_rain = 0.0


func _exit_tree() -> void:
	LucidStorm.clear()
	Lucid.clear_level()
	HUD.lens_rain = 0.0


# ------------------------------------------------------------ the fields ---

## The storm laid out from the anchor at time t: the drift, the band, the
## inflow, and the globals the shaders read.
func _layout(delta: float) -> void:
	var drift := DRIFT_DIR * DRIFT_AMP * sin(TAU * t / DRIFT_PERIOD)
	_meso = anchor + MESO + drift
	_core = anchor + CORE + drift
	_meso_turn += delta * 25.0 / 1500.0
	# The inflow: toward the mesocyclone, backing and gusting slowly.
	var to := (_meso - anchor).normalized().rotated(0.2 + 0.08 * sin(t * 0.011))
	_wind_mean = to * (INFLOW + 1.2 * sin(t * 0.023 + 1.0))
	advect += _wind_mean.length() * delta
	_band_n = BAND_DIR
	var s := BAND_START + BAND_SPEED * band_phase
	_band_p = anchor + _band_n * s
	# It builds over its first two minutes and dies over its last two.
	_band_now = band_rate * smoothstep(0.0, 130.0, band_phase) * (1.0 - smoothstep(BAND_PERIOD - 120.0, BAND_PERIOD, band_phase))
	var rs := RenderingServer
	rs.global_shader_parameter_set("field_wind", Vector4(_wind_mean.x, _wind_mean.y, advect, wetness))
	rs.global_shader_parameter_set("field_band", Vector4(_band_p.x, _band_p.y, _band_n.angle(), _band_now))
	rs.global_shader_parameter_set("field_core", Vector4(_core.x, _core.y, CORE_R, CORE_RATE))
	rs.global_shader_parameter_set("field_meso", Vector4(_meso.x, _meso.y, presence, _meso_turn))
	var sd := sun_dir()
	var k := 1.0 / Lucid.UNIT_NITS
	rs.global_shader_parameter_set("field_sun", Vector4(sd.x, sd.y, sd.z, SUN_LUX / PI * k))
	var sh := Lucid.kelvin_rgb(SHADE_K, true) * (SHADE_NITS * k)
	rs.global_shader_parameter_set("field_light", Vector4(sh.r, sh.g, sh.b, HAZE))
	var sa := Lucid.kelvin_rgb(SUN_K, true) * (SUNAIR_NITS * k)
	rs.global_shader_parameter_set("field_sunair", Vector4(sa.r, sa.g, sa.b, 0.0))
	rs.global_shader_parameter_set("field_cloud", Vector4(BASE_H, ANVIL_H, BASE_R, ANVIL_R))
	var bc := anchor + BASE_C + drift
	var ac := anchor + ANVIL_C + drift
	rs.global_shader_parameter_set("field_cloud_c", Vector4(bc.x, bc.y, ac.x, ac.y))
	# The rain drops' surround and the air the lightning shows through.
	var zen := sh * 1.25
	var hor := sh * 1.6
	rs.global_shader_parameter_set("lucid_sky_zenith", Vector4(zen.r, zen.g, zen.b, 0.3))
	rs.global_shader_parameter_set("lucid_sky_horizon", Vector4(hor.r, hor.g, hor.b, 0.0))
	rs.global_shader_parameter_set("lucid_sky_glow", Vector4.ZERO)


static func sun_dir() -> Vector3:
	var az := deg_to_rad(SUN_AZ)
	var el := deg_to_rad(SUN_ALT)
	return Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))


## Rain (mm/h) at p (world xz): field_rain_at() in field_storm.gdshaderinc.
func rain_at(p: Vector2) -> float:
	var r := CORE_RATE * (1.0 - smoothstep(0.25, 1.0, (p - _core).length() / CORE_R))
	r += HOOK_RATE * (1.0 - smoothstep(0.2, 1.0, (p - _meso - HOOK).length() / HOOK_R))
	var q := p - _band_p
	var s := q.dot(_band_n)
	var along := q.dot(Vector2(-_band_n.y, _band_n.x))
	var cells := (0.62 + 0.38 * sin(along * 0.0019 + 1.3) * sin(along * 0.00071 + s * 0.0011 + 0.4)) \
			* exp(-(along - BAND_A) * (along - BAND_A) / (BAND_L * BAND_L))
	return r + _band_now * exp(-s * s / (BAND_W * BAND_W)) * cells


## The wind (m/s at 2 m) at p (world xz) and its gust factor (z):
## field_wind_at() in field_storm.gdshaderinc.
func wind_at(p: Vector2) -> Vector3:
	var s := (p - _band_p).dot(_band_n)
	var o := smoothstep(BAND_W * 0.2 + FRONT, BAND_W * 0.2, s) * smoothstep(-3.5 * BAND_W, -0.8 * BAND_W, s) \
			* clampf(_band_now / 25.0, 0.0, 1.0)
	var m := _wind_mean.lerp(_band_n * OUTFLOW, o)
	var sp := m.length()
	var d := m / sp if sp > 0.01 else Vector2(1.0, 0.0)
	var e := Vector2(-d.y, d.x)
	var x := advect
	var g := 0.5 * sin(d.dot(p) * 0.0739 - x * 0.0739 + 0.3) \
			+ 0.3 * sin((d * 0.94 + e * 0.34).dot(p) * 0.1337 - x * 0.1337 + 2.1) \
			+ 0.2 * sin((d * 0.96 - e * 0.3).dot(p) * 0.2417 - x * 0.2417 + 4.0) \
			+ 0.12 * sin((d * 0.83 + e * 0.56).dot(p) * 0.4488 - x * 0.4488 + 5.3)
	var env := 0.5 + 0.5 * sin(d.dot(p) * 0.01496 - x * 0.01496 + 0.7)
	var k := maxf(1.0 + lerpf(TI_IN, TI_OUT, o) * g * (0.5 + env), 0.15)
	return Vector3(m.x * k, m.y * k, k)


# ------------------------------------------------------------- the frame ---

func update(delta: float, camera: Camera3D, env: Environment) -> void:
	t += delta
	var eye := camera.global_position
	anchor = Vector2(eye.x, eye.z)
	band_phase += delta
	if band_phase > BAND_PERIOD:
		band_phase -= BAND_PERIOD
		band_rate = _rng.randf_range(30.0, 45.0)
	_tornado_life(delta)
	_layout(delta)
	var w := wind_at(anchor)
	wind_here = Vector3(w.x, 0.0, w.y)
	rain_here = rain_at(anchor)
	# Wet within a minute of heavy rain; dries over ~10 minutes.
	var wet_to := clampf(rain_here / 8.0, 0.0, 1.0)
	wetness = move_toward(wetness, wet_to, delta * (1.0 / 60.0 if wet_to > wetness else 1.0 / 600.0))
	# The lightning: round the core and under the base, more and nearer as
	# a band comes (intensity: the rain on its way).
	lightning.rate = rain_here
	lightning.wind = wind_here
	lightning.intensity = clampf(rain_at(anchor + _band_n * 1500.0) / 30.0, 0.0, 1.0)
	lightning.focus = anchor + (MESO + CORE) * 0.5 + DRIFT_DIR * DRIFT_AMP * sin(TAU * t / DRIFT_PERIOD)
	lightning.update(delta, eye)
	_expose(delta, camera)
	var sig := LucidRain.sigma(rain_here)
	var sh := Lucid.kelvin_rgb(SHADE_K, true) * (SHADE_NITS / Lucid.UNIT_NITS)
	Lucid.push_level(cam, 0.0, 0.0, sh * 1.6 * Lucid.UNIT_NITS, HAZE)
	RenderingServer.global_shader_parameter_set("lucid_rain", Vector4(sig * 0.5, 0.0, lightning.rings, sig))
	# Godot's fog for what is near (grass, the door, the tree): the haze and
	# the rain here, the shaded air's colour.
	var ex := cam.shader_exposure()
	var dark := 1.0 - 0.5 * smoothstep(2.0, 45.0, rain_here)
	var fc := Color(sh.r * ex.r, sh.g * ex.g, sh.b * ex.b) * (1.6 * dark)
	var fm := maxf(fc.r, maxf(fc.g, fc.b))
	env.fog_light_color = (fc / maxf(fm, 1e-4)).linear_to_srgb() if fm > 0.0 else Color.BLACK
	env.fog_light_energy = fm
	env.fog_density = HAZE + sig
	_flash_light()
	_tornado_params(eye)
	_rain_update(delta, camera)
	_sound(delta)


## The camera: matrix metering of the view (the shaded field, the base,
## the bright horizon under it) in program mode, white balance toward the
## storm's shade.
func _expose(delta: float, camera: Camera3D) -> void:
	var dark := 1.0 - 0.5 * smoothstep(2.0, 45.0, rain_here)
	var e_up := PI * SHADE_NITS * 1.35 * dark
	var ground := 0.13 * e_up / PI
	var fwd := -camera.global_basis.z
	var pitch := asin(clampf(fwd.y, -1.0, 1.0))
	# Toward the storm the dark base; away from it the sunlit inflow sky.
	var face := Vector2(fwd.x, fwd.z).normalized().dot((_meso - anchor).normalized())
	var sky := lerpf(1100.0, SHADE_NITS * 0.7, smoothstep(-0.6, 0.6, face)) * dark * lerpf(1.0, 1.6, clampf(pitch * 1.6, 0.0, 1.0))
	var frac := clampf(0.42 + pitch * 1.3, 0.05, 0.95)
	var avg := exp(lerpf(log(ground), log(sky), frac))
	# The horizon under the base is the brightest thing in view when you
	# look toward the storm.
	var toward := clampf(face, 0.0, 1.0)
	var peak := lerpf(sky * 2.0, SUNAIR_NITS * 0.7 * dark, toward * (1.0 - smoothstep(0.1, 0.45, absf(pitch))))
	cam.meter(avg, delta, peak)
	cam.balance(SHADE_K, delta)
	cam.settle()


## The flash's light on the field: the lit cloud and the air (LucidStorm),
## and a near channel's own light (a line source of I' cd/m from the
## ground to the base, at rho: E = I' atan(H / rho) / rho).
func _flash_light() -> void:
	var e := lightning.light(lightning.flash_dir) if lightning.flux > 0.0 else Color(0, 0, 0)
	var dir := lightning.flash_dir
	var ch := lightning.channel()
	if float(ch[0]) > 0.0:
		var foot: Vector3 = ch[2]
		var rho := maxf(Vector2(foot.x, foot.z).length(), 50.0)
		var ec := float(ch[0]) * atan(BASE_H / rho) / rho / PI / Lucid.UNIT_NITS
		var c := LucidStorm.FLASH_RGB / Lucid.lum(LucidStorm.FLASH_RGB)
		e += c * ec
		dir = (dir * Lucid.lum(lightning.light(dir)) + Vector3(foot.x, 0.0, foot.z).normalized() * ec).normalized()
	var ln := Lucid.light_node_cam(e, cam)
	_flash.visible = ln[0] > 1e-4
	if _flash.visible:
		_flash.light_energy = ln[0]
		_flash.light_color = ln[1]
		var up := Vector3.UP if absf(dir.y) < 0.99 else Vector3.BACK
		_flash.look_at_from_position(Vector3.ZERO, dir, up)


# ----------------------------------------------------------- the tornado ---

## Its cycle: a funnel lowering from the wall cloud as the debris whirl
## spins up under it, a cone for minutes, then it ropes out (thins, bends,
## its foot dragged behind), the condensation lifts, and a while later the
## next one forms. Drifting with the storm meanwhile.
func _tornado_life(delta: float) -> void:
	tornado_age += delta
	var cycle := T_FORM + T_MATURE + T_ROPE + T_LIFT + T_GAP
	if tornado_age > cycle:
		tornado_age -= cycle
	var a := tornado_age
	if a < T_FORM:
		presence = smoothstep(0.0, T_FORM, a)
	elif a < T_FORM + T_MATURE + T_ROPE:
		presence = 1.0
	elif a < T_FORM + T_MATURE + T_ROPE + T_LIFT:
		presence = 1.0 - smoothstep(0.0, T_LIFT, a - T_FORM - T_MATURE - T_ROPE)
	else:
		presence = 0.0
	# Angular speed (rad/s): ~60 m/s round a 100 m core, faster as it
	# narrows (angular momentum).
	_spin += delta * lerpf(0.55, 1.1, _rope())


## 0 a cone .. 1 a rope.
func _rope() -> float:
	return smoothstep(T_FORM + T_MATURE - 20.0, T_FORM + T_MATURE + T_ROPE, tornado_age)


func _build_tornado(noise: Texture2D) -> void:
	var n := 72
	var v := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in n + 1:
		var y := float(i) / n
		v.push_back(Vector3(-1.0, y, 0.0))
		v.push_back(Vector3(1.0, y, 0.0))
	for i in n:
		var b := i * 2
		idx.append_array([b, b + 1, b + 2, b + 2, b + 1, b + 3])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = v
	arr[Mesh.ARRAY_INDEX] = idx
	var m := ArrayMesh.new()
	m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	m.custom_aabb = AABB(Vector3(-1e5, -1e5, -1e5), Vector3(2e5, 2e5, 2e5))
	for part in 2:
		var mat := ShaderMaterial.new()
		mat.shader = TORNADO_SHADER
		mat.set_shader_parameter("noise", noise)
		mat.set_shader_parameter("part", part)
		# The debris cloud behind the funnel's foot, the funnel over it.
		mat.render_priority = part
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		if part == 0:
			_tor = mi
			_tor_mat = mat
		else:
			_deb = mi
			_deb_mat = mat


func _tornado_params(eye: Vector3) -> void:
	var a := tornado_age
	var rope := _rope()
	# Where it stands: south-west of the mesocyclone's centre at first,
	# moving east with the rear flank's outflow as it ages (~2 m/s against
	# the storm).
	var along := clampf(a, 0.0, T_FORM + T_MATURE + T_ROPE + T_LIFT)
	_foot = _meso + Vector2(-350.0, 450.0) + DRIFT_DIR * along * 2.2
	var foot := FieldLevel.ground_at(_foot.x, _foot.y)
	# (Its top hidden up inside the wall cloud.)
	var top_h := BASE_H - WALL_DROP + 160.0 - FieldLevel.height(_foot.x, _foot.y)
	# Condensation: lowering from the wall cloud as it forms, nearly to the
	# ground in its prime (the debris cloud fills the rest), lifting at the end.
	var cond := 0.06 + 0.05 * sin(t * 0.07)
	if a < T_FORM:
		cond = lerpf(1.0, cond, smoothstep(0.0, T_FORM, a))
	elif a > T_FORM + T_MATURE + T_ROPE:
		cond = lerpf(cond, 1.0, smoothstep(0.0, T_LIFT, a - T_FORM - T_MATURE - T_ROPE))
	var breathe := 1.0 + 0.12 * sin(t * 0.05) + 0.06 * sin(t * 0.17 + 1.0)
	var vis := presence > 0.001
	_tor.visible = vis
	_deb.visible = vis or (a > T_FORM * 0.4 and a < T_FORM)
	for mat: ShaderMaterial in [_tor_mat, _deb_mat]:
		mat.set_shader_parameter("foot", foot)
		mat.set_shader_parameter("top_h", top_h)
		mat.set_shader_parameter("r_top", lerpf(300.0, 140.0, rope) * breathe)
		mat.set_shader_parameter("r_bot", lerpf(85.0, 14.0, rope) * breathe)
		mat.set_shader_parameter("shape", lerpf(1.6, 3.5, rope))
		mat.set_shader_parameter("bend", lerpf(25.0, 320.0, rope))
		mat.set_shader_parameter("bend_ph", t * 0.03)
		mat.set_shader_parameter("tilt", DRIFT_DIR * lerpf(120.0, 520.0, rope))
		mat.set_shader_parameter("cond", cond)
		mat.set_shader_parameter("spin", _spin)
		mat.set_shader_parameter("presence", presence)
	var dbr := smoothstep(T_FORM * 0.3, T_FORM, a) * (1.0 - smoothstep(0.0, T_LIFT * 0.8, a - T_FORM - T_MATURE - T_ROPE))
	_deb_mat.set_shader_parameter("presence", dbr * lerpf(1.0, 0.55, rope))
	_deb_mat.set_shader_parameter("debris_r", lerpf(260.0, 120.0, rope) * breathe)
	_deb_mat.set_shader_parameter("debris_h", lerpf(230.0, 100.0, rope))


## The tornado's foot (world) and its distance from you (m).
func tornado_foot() -> Vector3:
	return FieldLevel.ground_at(_foot.x, _foot.y)


# ---------------------------------------------------------------- the rain ---

func _rain_update(delta: float, camera: Camera3D) -> void:
	if rain == null or not _rain_on:
		return
	var c := camera.global_position
	if _cam_prev.is_finite() and delta > 0.0:
		var v := (c - _cam_prev) / delta
		if v.length() > 15.0:
			v = Vector3.ZERO
			HUD.lens_wipe = true
		_cam_vel = _cam_vel.lerp(v, minf(delta * 8.0, 1.0))
	_cam_prev = c
	rain.set_rate(maxf(rain_here, 0.05), wind_here)
	rain.visible = rain_here > 0.2
	rain.follow(camera, clampf(cam.shutter, 1.0 / 2000.0, 1.0 / 30.0), _cam_vel.limit_length(8.0),
			clampf(rain_here / 0.6, 0.0, 1.0))
	# The surround a drop refracts: the field round it (grass ~0.12 under
	# the storm's light).
	var e := Lucid.kelvin_rgb(SHADE_K, true) * (SHADE_NITS * 1.35 * 0.12 / Lucid.UNIT_NITS)
	rain.set_lights([], e)
	HUD.lens_rain = rain.lens_rate(-camera.global_basis.z, _cam_vel) if rain_here > 0.2 else 0.0


# ---------------------------------------------------------------- the sound ---

func _build_audio() -> void:
	_wind_snd = _loop("wind_field", -6.0)
	_rain_snd = _loop("rain_grass", -80.0)
	_roar_snd = _loop("tornado_roar", -80.0)


func _loop(n: String, db: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.name = n
	var path := AUDIO + n + ".ogg"
	if ResourceLoader.exists(path):
		var s: AudioStream = load(path)
		if s is AudioStreamOggVorbis:
			(s as AudioStreamOggVorbis).loop = true
		p.stream = s
	elif n == "wind_field":
		p.stream = AudioSynth.cached("wind")
	p.volume_db = db
	p.bus = "World"
	add_child(p)
	if p.stream != null:
		p.play()
	return p


## The wind's roar follows its speed here (aeolian noise grows ~v^6 in
## power; heard through the grass and the ears it rises ~30 dB per decade),
## the rain's patter its rate, the tornado's far rumble its presence.
func _sound(delta: float) -> void:
	var v := maxf(wind_here.length(), 0.5)
	var k := minf(delta * 4.0, 1.0)
	_wind_snd.volume_db = lerpf(_wind_snd.volume_db, clampf(-6.0 + 30.0 * log(v / INFLOW) / log(10.0), -26.0, 4.0), k)
	_wind_snd.pitch_scale = clampf(0.8 + 0.022 * v, 0.8, 1.3)
	var rdb := -3.0 + 10.0 * log(maxf(rain_here, 0.01) / 20.0) / log(10.0) if rain_here > 0.15 else -80.0
	_rain_snd.volume_db = lerpf(_rain_snd.volume_db, rdb if _rain_on else -80.0, k)
	_roar_snd.volume_db = -80.0 if presence < 0.01 else -26.0 + 20.0 * log(presence) / log(10.0)


## Thunder `dist` m off from `dir`: the recording of its class, 6 dB down
## per doubling of the distance within it (open country: no echoes).
func _thunder(dist: float, dir: Vector3) -> void:
	var cls: Array = THUNDER[THUNDER.size() - 1]
	for c: Array in THUNDER:
		if dist < float(c[2]):
			cls = c
			break
	var names := []
	for k in [1, 2]:
		var n := "%s_%d" % [cls[0], k]
		if not _sounds.has(n) and ResourceLoader.exists(AUDIO + n + ".ogg"):
			_sounds[n] = load(AUDIO + n + ".ogg")
		if _sounds.has(n):
			names.append(n)
	if names.is_empty():
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _sounds[names[_rng.randi() % names.size()]]
	p.bus = "World"
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED
	p.volume_db = 12.0 + 20.0 * log(float(cls[1]) / dist) / log(10.0)
	add_child(p)
	var c3 := get_viewport().get_camera_3d()
	var at := c3.global_position if c3 != null else Vector3.ZERO
	p.global_position = at + dir * 40.0 + Vector3(0, 15.0, 0)
	p.play()
	p.finished.connect(p.queue_free)
