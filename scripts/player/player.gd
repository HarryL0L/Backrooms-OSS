class_name Player
extends CharacterBody3D
## First person controller: walking, sprinting with stamina, crouching, jumping,
## climbing out of pools, head bob, footsteps and a hand-held flashlight.
## Input comes from keyboard/mouse, gamepads and the on-screen touch controls.

signal footstep(surface: int, strength: float)
signal flashlight_toggled(on: bool)

enum { SURF_CARPET, SURF_TILE, SURF_CONCRETE, SURF_WATER, SURF_GRASS }

const WALK := 2.6
const SPRINT := 4.9
const CROUCH := 1.3
const WATER_MULT := 0.55
const ACCEL := 10.0
const AIR_ACCEL := 1.5
const JUMP_V := 4.2
const GRAVITY := 12.0
const STAND_H := 1.75
const CROUCH_H := 1.05
const EYE := 1.62
const EYE_CROUCH := 0.95
const RADIUS := 0.3

var gen: WorldGen
var touch: Node = null
var controls_enabled := false
var yaw := 0.0
var pitch := 0.0
var crouching := false
var sprint_latched := false
var stamina := 1.0
var exhausted := false
var flashlight_on := false

var head: Node3D
var camera: Camera3D
var flash_rig: Node3D
var flashlight: SpotLight3D
var flash_fill: OmniLight3D
## Photoreal: the flashlight's bounce light (see _update_bounce).
var flash_bounce: OmniLight3D
var bounce_on := false
var _bounce_e := 0.0
var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _eye := EYE
var _step_phase := 0.0       # one step per PI radians
var _bob_amount := 0.0
var _run_blend := 0.0
var _land_dip := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _jump_queued := 0.0
var _climb_t := -1.0
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _roll := 0.0
var _idle_t := 0.0
var _safe_pos := Vector3.ZERO
## True while in the outdoor Field level (grass, no pools, no Backrooms rules).
var field_mode := false
## In the Dead Mall (tiled floors, far below the Backrooms).
var mall_mode := false


func _ready() -> void:
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	safe_margin = 0.02
	_shape = CapsuleShape3D.new()
	_shape.radius = RADIUS
	_shape.height = STAND_H
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_col.position.y = STAND_H * 0.5
	add_child(_col)
	head = Node3D.new()
	head.position.y = EYE
	add_child(head)
	camera = Camera3D.new()
	camera.near = 0.05
	camera.far = 95.0
	camera.current = true
	head.add_child(camera)
	flash_rig = Node3D.new()
	flash_rig.top_level = true
	add_child(flash_rig)
	flashlight = SpotLight3D.new()
	flashlight.light_color = Color(1.0, 0.93, 0.80)
	flashlight.light_energy = 5.0
	flashlight.light_specular = 0.7
	flashlight.spot_range = 24.0
	flashlight.spot_angle = 28.0
	flashlight.spot_angle_attenuation = 0.9
	flashlight.spot_attenuation = 1.3
	flashlight.shadow_bias = 0.04
	flashlight.shadow_normal_bias = 1.5
	flashlight.visible = false
	flash_rig.add_child(flashlight)
	flash_fill = OmniLight3D.new()
	flash_fill.light_color = Color(1.0, 0.93, 0.80)
	flash_fill.light_energy = 0.12
	flash_fill.omni_range = 5.0
	flash_fill.light_specular = 0.0
	flash_fill.visible = false
	flash_rig.add_child(flash_fill)
	flash_bounce = OmniLight3D.new()
	flash_bounce.top_level = true
	flash_bounce.omni_range = 5.5
	flash_bounce.omni_attenuation = 1.2
	flash_bounce.light_specular = 0.0
	flash_bounce.visible = false
	add_child(flash_bounce)
	_apply_settings()
	Settings.changed.connect(_apply_settings)


func _apply_settings() -> void:
	camera.fov = Settings.get_value("graphics/fov")
	flashlight.shadow_enabled = Settings.get_value("graphics/flashlight_shadows")
	# Without real-time lights the flashlight is computed in the world shaders.
	shader_flashlight = not Settings.light_nodes()
	bounce_on = Settings.light_nodes() and Settings.get_value("graphics/photoreal") and not Settings.get_value("graphics/ps1")
	set_flashlight(flashlight_on)


func teleport(p: Vector3, p_yaw: float, p_pitch := 0.0) -> void:
	global_position = p
	_safe_pos = p
	velocity = Vector3.ZERO
	yaw = p_yaw
	pitch = p_pitch
	_climb_t = -1.0
	_apply_rotation()
	flash_rig.global_transform = camera.global_transform


var shader_flashlight := false
## Where the player is trying to walk this frame (world space, length <= 1).
var wish_dir := Vector3.ZERO


func set_flashlight(on: bool) -> void:
	var changed := on != flashlight_on
	flashlight_on = on
	flashlight.visible = on and not shader_flashlight
	flash_fill.visible = on and not shader_flashlight
	_push_flash_globals()
	if changed:
		flashlight_toggled.emit(on)


## Feeds the shader flashlight (see flashlight() in common.gdshaderinc).
func _push_flash_globals() -> void:
	var active := flashlight_on and shader_flashlight
	RenderingServer.global_shader_parameter_set("flash_params", Vector4(1.0 if active else 0.0, flashlight.spot_range,
			cos(deg_to_rad(flashlight.spot_angle)), cos(deg_to_rad(flashlight.spot_angle * 0.55))))
	if active:
		RenderingServer.global_shader_parameter_set("flash_pos", flash_rig.global_position)
		RenderingServer.global_shader_parameter_set("flash_dir", -flash_rig.global_basis.z)


func toggle_flashlight() -> void:
	set_flashlight(not flashlight_on)


func toggle_crouch() -> void:
	crouching = not crouching


func queue_jump() -> void:
	_jump_queued = 0.2


func add_look(delta_yaw: float, delta_pitch: float) -> void:
	if not controls_enabled:
		return
	yaw -= delta_yaw
	var inv := -1.0 if Settings.get_value("controls/invert_y") else 1.0
	pitch = clampf(pitch - delta_pitch * inv, -1.48, 1.48)
	_apply_rotation()


func _apply_rotation() -> void:
	rotation.y = yaw
	head.rotation.x = pitch


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseMotion and event.device != InputEvent.DEVICE_ID_EMULATION \
			and Input.mouse_mode in [Input.MOUSE_MODE_CAPTURED, Input.MOUSE_MODE_HIDDEN]:
		var s: float = 0.0022 * Settings.get_value("controls/mouse_sens")
		add_look(event.relative.x * s, event.relative.y * s)
	elif event.is_action_pressed("flashlight") and not _is_emulated_mouse(event):
		toggle_flashlight()
	elif event.is_action_pressed("crouch") and not _is_emulated_mouse(event):
		if Settings.get_value("controls/crouch_toggle"):
			toggle_crouch()
		else:
			crouching = true
	elif event.is_action_released("crouch") and not Settings.get_value("controls/crouch_toggle"):
		crouching = false
	elif event.is_action_pressed("sprint") and Settings.get_value("controls/sprint_toggle"):
		sprint_latched = not sprint_latched
	elif event.is_action_pressed("jump") and not _is_emulated_mouse(event):
		queue_jump()


static func _is_emulated_mouse(event: InputEvent) -> bool:
	return event is InputEventMouseButton and event.device == InputEvent.DEVICE_ID_EMULATION


func surface_at() -> int:
	if field_mode:
		return SURF_GRASS
	if mall_mode:
		return SURF_TILE
	return surface_for(gen, global_position)


## Footstep surface at a position in the Backrooms.
static func surface_for(g: WorldGen, pos: Vector3) -> int:
	if pos.y < WorldGen.WATER_Y - 0.05:
		return SURF_WATER
	var c := g.cell_of(pos)
	match g.biome_at(c.x, c.y):
		WorldGen.POOL:
			return SURF_TILE
		WorldGen.CONCRETE, WorldGen.PIPES:
			return SURF_CONCRETE
	return SURF_CARPET


func in_water() -> bool:
	return not field_mode and not mall_mode and global_position.y < WorldGen.WATER_Y - 0.1


func _physics_process(delta: float) -> void:
	if _climb_t >= 0.0:
		_process_climb(delta)
		return
	var input := Vector2.ZERO
	if controls_enabled:
		input = Input.get_vector("move_left", "move_right", "move_forward", "move_back", 0.2)
		if touch != null:
			input += touch.move_vector
		input = input.limit_length(1.0)
		_gamepad_look(delta)
	var wish := Basis(Vector3.UP, yaw) * Vector3(input.x, 0.0, input.y)
	wish_dir = wish
	var water := in_water()
	var want_sprint: bool = Input.is_action_pressed("sprint") or sprint_latched or (touch != null and touch.sprint_held)
	var sprinting: bool = want_sprint and input.y < -0.3 and not crouching and not exhausted and input.length() > 0.5
	if sprinting:
		stamina = maxf(stamina - delta * 0.11, 0.0)
		if stamina <= 0.0:
			exhausted = true
	else:
		stamina = minf(stamina + delta * (0.08 if exhausted else 0.16), 1.0)
		if exhausted and stamina > 0.35:
			exhausted = false
	if input.length() < 0.1:
		sprint_latched = false
	var speed := CROUCH if crouching else (SPRINT if sprinting else WALK)
	if water:
		speed *= WATER_MULT
	if exhausted:
		speed = minf(speed, WALK * 0.85)
	var target := wish * speed
	var on_floor := is_on_floor()
	var k := 1.0 - exp(-(ACCEL if on_floor else AIR_ACCEL) * delta)
	velocity.x = lerpf(velocity.x, target.x, k)
	velocity.z = lerpf(velocity.z, target.z, k)
	if not on_floor:
		velocity.y -= GRAVITY * delta
		_fall_speed = minf(_fall_speed, velocity.y)
	_jump_queued -= delta
	if _jump_queued > 0.0 and on_floor:
		_jump_queued = 0.0
		if not _try_climb(wish if wish.length() > 0.1 else -global_basis.z, 1.0):
			if crouching:
				crouching = false
			else:
				velocity.y = JUMP_V * (0.7 if water else 1.0)
	move_and_slide()
	# Pushing against a pool rim climbs out automatically.
	if is_on_floor() and is_on_wall() and wish.length() > 0.5:
		_try_climb(wish.normalized(), 0.85)
	_update_crouch(delta)
	_update_bob(delta, input)
	if is_on_floor():
		if global_position.y > -1.0 or field_mode or mall_mode:
			_safe_pos = global_position
	if global_position.y < (_safe_pos.y - 30.0 if field_mode or mall_mode else -12.0):
		teleport(_safe_pos + Vector3(0, 0.2, 0), yaw, pitch)
	_update_flash_rig(delta)


func _gamepad_look(delta: float) -> void:
	var rx := Input.get_joy_axis(0, JOY_AXIS_RIGHT_X)
	var ry := Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y)
	var v := Vector2(rx, ry)
	if v.length() < 0.15:
		return
	v = v.normalized() * ((v.length() - 0.15) / 0.85)
	v *= v.length()
	var rate: float = 3.2 * Settings.get_value("controls/pad_sens")
	add_look(v.x * rate * delta, v.y * rate * delta * 0.75)


func _try_climb(dir: Vector3, max_h: float) -> bool:
	dir.y = 0.0
	if dir.length() < 0.1:
		return false
	dir = dir.normalized()
	var xf := global_transform
	var up := Vector3(0, max_h + 0.05, 0)
	if test_move(xf, up):
		return false
	var raised := xf.translated(up)
	if test_move(raised, dir * 0.45):
		return false
	# Make sure there is floor to stand on and that it's actually a step up.
	var ahead := raised.translated(dir * 0.45)
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(ahead.origin + Vector3(0, 0.1, 0), ahead.origin - Vector3(0, max_h + 0.3, 0))
	q.exclude = [get_rid()]
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return false
	var step: float = hit.position.y - global_position.y
	if step < 0.25 or step > max_h + 0.01:
		return false
	_climb_from = global_position
	_climb_to = Vector3(ahead.origin.x, hit.position.y + 0.02, ahead.origin.z)
	_climb_t = 0.0
	velocity = Vector3.ZERO
	footstep.emit(surface_at(), 0.8)
	return true


func _process_climb(delta: float) -> void:
	_climb_t += delta / 0.55
	var t := minf(_climb_t, 1.0)
	var up_t := smoothstep(0.0, 0.6, t)
	var fw_t := smoothstep(0.35, 1.0, t)
	global_position = Vector3(lerpf(_climb_from.x, _climb_to.x, fw_t), lerpf(_climb_from.y, _climb_to.y, up_t),
			lerpf(_climb_from.z, _climb_to.z, fw_t))
	head.position.y = _eye - sin(t * PI) * 0.25
	camera.rotation.z = sin(t * PI) * 0.05
	if t >= 1.0:
		_climb_t = -1.0
		footstep.emit(surface_at(), 0.6)
	_update_flash_rig(delta)


func _update_crouch(delta: float) -> void:
	var target_h := CROUCH_H if crouching else STAND_H
	if not crouching and _shape.height < STAND_H - 0.01:
		# Don't stand up into something.
		if test_move(global_transform, Vector3(0, STAND_H - _shape.height, 0)):
			target_h = _shape.height
	_shape.height = move_toward(_shape.height, target_h, delta * 3.5)
	_col.position.y = _shape.height * 0.5
	var target_eye := remap(_shape.height, CROUCH_H, STAND_H, EYE_CROUCH, EYE)
	_eye = lerpf(_eye, target_eye, 1.0 - exp(-14.0 * delta))


func _update_bob(delta: float, input: Vector2) -> void:
	var on_floor := is_on_floor()
	var hspeed := Vector2(velocity.x, velocity.z).length()
	if on_floor and not _was_on_floor and _fall_speed < -2.5:
		_land_dip = clampf(-_fall_speed * 0.03, 0.03, 0.18)
		footstep.emit(surface_at(), clampf(-_fall_speed / 6.0, 0.6, 1.5))
	if on_floor:
		_fall_speed = 0.0
	_was_on_floor = on_floor
	# Step length grows with speed like a real gait (about 2.2 steps/s at a
	# brisk walk, 2.8 at a sprint), and the phase is accumulated so changing
	# speed never makes the bob jump.
	var step_len := clampf(0.45 + 0.27 * hspeed, 0.55, 1.8)
	if on_floor and hspeed > 0.3:
		var prev := _step_phase
		_step_phase += hspeed * delta / step_len * PI
		if floori(prev / PI) != floori(_step_phase / PI):
			var strength := clampf(hspeed / SPRINT, 0.35, 1.0) * (0.55 if crouching else 1.0)
			footstep.emit(surface_at(), strength)
	var head_bob: bool = Settings.get_value("graphics/head_bob")
	var target_amt := clampf(hspeed / WALK, 0.0, 1.0) if on_floor and head_bob else 0.0
	_bob_amount = lerpf(_bob_amount, target_amt, 1.0 - exp(-6.0 * delta))
	_run_blend = lerpf(_run_blend, smoothstep(WALK + 0.3, SPRINT - 0.3, hspeed), 1.0 - exp(-4.0 * delta))
	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-7.0 * delta))
	_idle_t += delta
	var breathe := sin(_idle_t * (1.4 if not exhausted else 2.6)) * 0.006 * (2.2 if exhausted else 1.0)
	# The head is lowest just after each foot lands (the knee takes the
	# weight) and highest passing over the planted leg. Walking is a smooth
	# rise and fall; running dips sharply on landing and floats in between.
	var p := _step_phase - 0.3
	var w := 0.5 * (1.0 + cos(2.0 * p))                  # 1 at landing, 0 mid-step
	var walk_y := -w * 0.026
	var run_y := -pow(w, 3.0) * 0.055
	var amt := _bob_amount * (0.6 if crouching else 1.0)
	var by := lerpf(walk_y, run_y, _run_blend) * amt + breathe
	# Weight shifts over the standing foot: sideways sway at half the rate.
	var bx := sin(p) * lerpf(0.016, 0.024, _run_blend) * amt
	head.position = Vector3(bx, _eye + by - _land_dip, 0.0)
	var target_roll := -input.x * 0.025 + sin(p) * lerpf(0.003, 0.007, _run_blend) * amt
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-10.0 * delta))
	camera.rotation.z = _roll
	# A small nod on each landing, stronger when running.
	camera.rotation.x = -lerpf(w * 0.003, pow(w, 3.0) * 0.012, _run_blend) * amt - _land_dip * 0.15


func _update_flash_rig(delta: float) -> void:
	var target := camera.global_transform
	target.origin += target.basis * Vector3(0.18, -0.2, -0.1)
	var w := 1.0 - exp(-13.0 * delta)
	var q := flash_rig.global_basis.get_rotation_quaternion().slerp(target.basis.get_rotation_quaternion(), w)
	flash_rig.global_transform = Transform3D(Basis(q), target.origin)
	if shader_flashlight and flashlight_on:
		_push_flash_globals()
	_update_bounce(delta)


## Bounce light from the flashlight on any renderer: one small light where the
## beam lands, in the colour of what it lands on, so a lit yellow wall throws
## a soft yellow glow back into the room (a single "virtual point light").
func _update_bounce(delta: float) -> void:
	var target_e := 0.0
	if bounce_on and flashlight_on and not field_mode:
		var from := flash_rig.global_position
		var dir := -flash_rig.global_basis.z
		var q := PhysicsRayQueryParameters3D.create(from, from + dir * flashlight.spot_range)
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		if not hit.is_empty():
			var n: Vector3 = hit.normal
			var d := from.distance_to(hit.position)
			var alb := _albedo_at(hit.position, n)
			var lum := (alb.r + alb.g + alb.b) / 3.0
			target_e = BOUNCE_ENERGY * lum * clampf(1.0 - d / flashlight.spot_range, 0.0, 1.0)
			var p: Vector3 = hit.position + n * 0.45
			if _bounce_e <= 0.001:
				flash_bounce.global_position = p
			else:
				flash_bounce.global_position = flash_bounce.global_position.lerp(p, 1.0 - exp(-12.0 * delta))
			var m := maxf(alb.r, maxf(alb.g, alb.b))
			flash_bounce.light_color = flashlight.light_color * Color(alb.r / m, alb.g / m, alb.b / m)
	_bounce_e = lerpf(_bounce_e, target_e, 1.0 - exp(-10.0 * delta))
	flash_bounce.light_energy = _bounce_e
	flash_bounce.visible = _bounce_e > 0.005


const BOUNCE_ENERGY := 0.9


## What colour the surface at p is (for the bounce): the level's wall, floor
## or ceiling colour in the Backrooms, a neutral grey elsewhere.
func _albedo_at(p: Vector3, n: Vector3) -> Color:
	if gen == null or mall_mode:
		return Color(0.55, 0.53, 0.5)
	var c := gen.cell_of(p - n * 0.1)
	var b := gen.biome_at(c.x, c.y)
	if n.y > 0.6:
		return ChunkBuilder.ALB_FLOOR[b]
	if n.y < -0.6:
		return ChunkBuilder.ALB_CEIL[b]
	return ChunkBuilder.ALB_WALL[b]
