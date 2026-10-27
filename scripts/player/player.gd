class_name Player
extends CharacterBody3D
## First person controller: walking, sprinting with stamina, crouching,
## crawling (prone, in side levels and under anything too low to crouch
## under), wading, jumping, climbing out of pools, head bob, footsteps and a
## hand-held flashlight. Input comes from keyboard/mouse, gamepads and the
## on-screen touch controls.

signal footstep(surface: int, strength: float)
signal flashlight_toggled(on: bool)

enum { SURF_CARPET, SURF_TILE, SURF_CONCRETE, SURF_WATER, SURF_GRASS, SURF_METAL }
const SURF_COUNT := 6

const WALK := 2.6
const SPRINT := 4.9
const CROUCH := 1.3
## Elbow crawl, prone.
const CRAWL := 0.75
const WATER_MULT := 0.55
const ACCEL := 10.0
const AIR_ACCEL := 1.5
const JUMP_V := 4.2
const GRAVITY := 12.0
const STAND_H := 1.75
const CROUCH_H := 1.05
const EYE := 1.62
const EYE_CROUCH := 0.95
## Prone: the capsule is a ball round your chest (RADIUS * 2 high), the eyes
## just above the floor.
const CRAWL_H := 0.6
const EYE_CRAWL := 0.38
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
## Sitting in a car (ParkedCar): no walking, only looking around.
var seated := false
## Where you'll stand again when you get out (saved instead of the seat).
var seat_exit := Vector3.ZERO
var _ride := PackedVector3Array()   # eye positions along the way in or out
var _ride_t := -1.0
var _ride_time := 1.0
var _ride_yaw := Vector2.ZERO        # from, to
var _ride_pitch := -0.08
var _ride_done := Callable()
## True while in the outdoor Field level (grass, no pools, no Backrooms rules).
## Pushed along by something you stand on (an escalator), this frame.
var carry := Vector3.ZERO
var field_mode := false
## In the Dead Mall (tiled floors, far below the Backrooms).
var mall_mode := false
## In a side level (SideLevel, far below everything else): its own floors,
## water and light; no Backrooms rules. `side` is the level, which answers
## surface_at / water_level_at / albedo_at.
var side_mode := false
var side: SideLevel = null
## Down on your front: set while the body is lower than a crouch (see
## _update_crouch). Read it; don't set it.
var crawling := false
## A level that's crawl-only (a duct) keeps you down while this is set.
var force_crawl := false
## Climbing up onto ledges (pool rims, jump-climbs). Levels can switch it off
## (a catwalk railing you mustn't vault).
var can_climb := true
## Crouched, you went down flat under something too low to crouch under;
## you get back up by yourself once there's room.
var _tight := false


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


## Human eye camera: this many degrees across (whatever the screen's
## shape), with shaders/eye_lens.gdshader taking the stretch off the edges.
const HUMAN_FOV := 115.0


static func human_eye() -> bool:
	return bool(Settings.get_value("graphics/human_eye")) and not bool(Settings.get_value("graphics/ps1"))


func _apply_settings() -> void:
	if human_eye():
		camera.keep_aspect = Camera3D.KEEP_WIDTH
		camera.fov = HUMAN_FOV
	else:
		camera.keep_aspect = Camera3D.KEEP_HEIGHT
		camera.fov = Settings.get_value("graphics/fov")
	flashlight.shadow_enabled = Settings.get_value("graphics/flashlight_shadows")
	# Without real-time lights the flashlight is computed in the world shaders.
	shader_flashlight = not Settings.light_nodes()
	bounce_on = Settings.light_nodes() and Settings.get_value("graphics/photoreal") and not Settings.get_value("graphics/ps1")
	set_flashlight(flashlight_on)


func teleport(p: Vector3, p_yaw: float, p_pitch := 0.0) -> void:
	if seated or _ride_t >= 0.0:
		_ride_t = -1.0
		_ride_done = Callable()
		stand_up()
	global_position = p
	_safe_pos = p
	_col.disabled = false          # (in case a ride left it off)
	velocity = Vector3.ZERO
	yaw = p_yaw
	pitch = p_pitch
	_climb_t = -1.0
	_apply_rotation()
	flash_rig.global_transform = camera.global_transform


var shader_flashlight := false
## Inside a stairwell shaft (set by Stairwells).
var in_stairwell := false


## Moves you straight up or down without touching anything else (a floor
## change on the stairs: the shaft around you looks the same).
func shift_y(dy: float) -> void:
	global_position.y += dy
	_safe_pos.y += dy
	flash_rig.global_position.y += dy
	flash_bounce.global_position.y += dy
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
	if side_mode:
		# Wading splashes, whatever the floor under the water is.
		if in_water():
			return SURF_WATER
		return side.surface_at(global_position) if side else SURF_CONCRETE
	if field_mode:
		return SURF_GRASS
	if mall_mode:
		return SURF_TILE
	if in_stairwell:
		return SURF_CONCRETE
	return surface_for(gen, global_position)


## Footstep surface at a position in the Backrooms.
static func surface_for(g: WorldGen, pos: Vector3) -> int:
	if pos.y < WorldGen.WATER_Y - 0.05:
		return SURF_WATER
	var c := g.cell_of(pos)
	match g.biome_at(c.x, c.y):
		WorldGen.POOL:
			return SURF_TILE
		WorldGen.CONCRETE, WorldGen.PIPES, WorldGen.GARAGE:
			return SURF_CONCRETE
	return SURF_CARPET


func in_water() -> bool:
	if side_mode:
		return water_depth() > 0.1
	return not in_stairwell and not field_mode and not mall_mode and global_position.y < WorldGen.WATER_Y - 0.1


## How deep the water you stand in is (side levels; 0 for none).
func water_depth() -> float:
	if not side_mode or side == null:
		return 0.0
	return maxf(side.water_level_at(global_position) - global_position.y, 0.0)


func _physics_process(delta: float) -> void:
	if _climb_t >= 0.0:
		_process_climb(delta)
		return
	if _ride_t >= 0.0:
		_process_ride(delta)
		return
	if seated:
		if controls_enabled:
			_gamepad_look(delta)
		velocity = Vector3.ZERO
		wish_dir = Vector3.ZERO
		_update_flash_rig(delta)
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
	var sprinting: bool = want_sprint and input.y < -0.3 and not crouching and not crawling and not exhausted and input.length() > 0.5
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
	if crawling:
		speed = CRAWL
	if water:
		# Side levels' water can be anything from a puddle to waist deep:
		# the deeper it is, the harder you wade (full drag by 0.6 m).
		speed *= WATER_MULT if not side_mode else lerpf(1.0, WATER_MULT, clampf((water_depth() - 0.1) / 0.5, 0.0, 1.0))
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
		if crawling:
			# Up off your front (as far as there's room), unless the level
			# keeps you down.
			if not force_crawl:
				crouching = false
				_tight = false
		elif not _try_climb(wish if wish.length() > 0.1 else -global_basis.z, 1.0):
			if crouching:
				crouching = false
			else:
				velocity.y = JUMP_V * (0.7 if water else 1.0)
	velocity += carry
	move_and_slide()
	velocity -= Vector3(carry.x, 0.0, carry.z)
	carry = Vector3.ZERO
	# Pushing against a pool rim climbs out automatically.
	if is_on_floor() and is_on_wall() and wish.length() > 0.5 and not crawling:
		_try_climb(wish.normalized(), 0.85)
	_update_crouch(delta, wish)
	_update_bob(delta, input)
	# Fell out of the world: back to the last floor you stood on. In the
	# Backrooms that's anything below the pools; elsewhere (the Field, the
	# mall, side levels, all far below) a long drop. A side level that
	# wants falls to kill sets SideLevel.fall_kill, which acts first.
	var far_below := field_mode or mall_mode or side_mode
	if is_on_floor():
		if global_position.y > -1.0 or far_below:
			_safe_pos = global_position
	if global_position.y < (_safe_pos.y - 30.0 if far_below else -12.0):
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
	if not can_climb:
		return false
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


## Moves the eye along `eyes` (world positions, the first is where it is
## now) over `time` seconds, turning to `to_yaw` (and the view settling to
## `to_pitch`), with no collision: getting into or out of a car, ducking
## into a vent, climbing down a hatch or a ladder. Calls `done` at the end.
func ride(eyes: PackedVector3Array, to_yaw: float, time: float, done: Callable, to_pitch := -0.08) -> void:
	_ride = eyes
	_ride_t = 0.0
	_ride_time = time
	_ride_yaw = Vector2(yaw, to_yaw)
	_ride_pitch = to_pitch
	_ride_done = done
	velocity = Vector3.ZERO
	crouching = false
	_col.disabled = true


func _process_ride(delta: float) -> void:
	_ride_t = minf(_ride_t + delta / _ride_time, 1.0)
	# Each stretch eases in and out: duck, slide across, settle.
	var n := _ride.size() - 1
	var f := _ride_t * n
	var i := mini(floori(f), n - 1)
	var e := _ride[i].lerp(_ride[i + 1], smoothstep(0.0, 1.0, f - i))
	global_position = e - Vector3.UP * _eye
	head.position.y = _eye
	yaw = lerp_angle(_ride_yaw.x, _ride_yaw.y, smoothstep(0.15, 0.85, _ride_t))
	pitch = lerpf(pitch, _ride_pitch, 1.0 - exp(-4.0 * delta))
	_apply_rotation()
	camera.rotation.z = sin(_ride_t * PI) * 0.05
	if _ride_t >= 1.0:
		_ride_t = -1.0
		camera.rotation.z = 0.0
		var d := _ride_done
		_ride_done = Callable()
		if d.is_valid():
			d.call()
	_update_flash_rig(delta)


## Being moved for you (a ride, a climb out of a pool) or sitting in a car.
func busy() -> bool:
	return _ride_t >= 0.0 or _climb_t >= 0.0 or seated


## Back on your feet after a ride out of a seat.
func stand_up() -> void:
	seated = false
	_col.disabled = false
	_safe_pos = global_position


## Standing, crouched or flat on your front. Crouched and pushing into a gap
## too low to crouch through (a duct mouth, under a shelf), you go down flat
## and crawl (`_tight`), and get back up by yourself once there's room. A
## level can keep you down (force_crawl). Never up into something: if only
## a crouch fits, you crouch; if not even that, you stay down.
func _update_crouch(delta: float, wish := Vector3.ZERO) -> void:
	if (crouching or crawling) and not force_crawl and not _tight and is_on_floor() and wish.length() > 0.5:
		var ahead := wish.normalized() * 0.35
		if not _fits(CROUCH_H, ahead) and _fits(CRAWL_H, ahead):
			_tight = true
	elif _tight and _shape.height < CROUCH_H - 0.01 and _fits(CROUCH_H, Vector3.ZERO) \
			and (wish.length() < 0.5 or _fits(CROUCH_H, wish.normalized() * 0.35)):
		_tight = false
	var target_h := _stance_height()
	if target_h > _shape.height + 0.01 and test_move(global_transform, Vector3(0, target_h - _shape.height, 0)):
		# Don't get up into something.
		if target_h > CROUCH_H and _shape.height < CROUCH_H - 0.01 \
				and not test_move(global_transform, Vector3(0, CROUCH_H - _shape.height, 0)):
			target_h = CROUCH_H
		else:
			target_h = _shape.height
	_shape.height = move_toward(_shape.height, target_h, delta * 3.5)
	_col.position.y = _shape.height * 0.5
	crawling = _shape.height < (CRAWL_H + CROUCH_H) * 0.5
	_eye = lerpf(_eye, _eye_for(_shape.height), 1.0 - exp(-14.0 * delta))


func _stance_height() -> float:
	if force_crawl or _tight:
		return CRAWL_H
	return CROUCH_H if crouching else STAND_H


func _eye_for(h: float) -> float:
	if h >= CROUCH_H:
		return remap(h, CROUCH_H, STAND_H, EYE_CROUCH, EYE)
	return remap(h, CRAWL_H, CROUCH_H, EYE_CRAWL, EYE_CROUCH)


## Straight into the stance you should be in, no easing (after a teleport
## into a duct, or continuing a game saved there).
func snap_stance() -> void:
	_shape.height = _stance_height()
	_col.position.y = _shape.height * 0.5
	crawling = _shape.height < (CRAWL_H + CROUCH_H) * 0.5
	_eye = _eye_for(_shape.height)
	head.position.y = _eye


## 0 standing, 1 crouched, 2 crawling (for saves).
func stance() -> int:
	return 2 if crawling else (1 if crouching else 0)


func set_stance(s: int) -> void:
	crouching = s >= 1
	_tight = s == 2
	snap_stance()


var _probe: CapsuleShape3D


## Whether a body `h` tall (a little narrower than yours, its feet just off
## the floor so standing on it doesn't count) fits at `offset` from here.
func _fits(h: float, offset: Vector3) -> bool:
	if _probe == null:
		_probe = CapsuleShape3D.new()
		_probe.radius = RADIUS - 0.04
	_probe.height = h - 0.06
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = _probe
	q.transform = Transform3D(Basis(), global_position + offset + Vector3(0, 0.06 + _probe.height * 0.5, 0))
	q.exclude = [get_rid()]
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()


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
	# Prone (0..1, as far down as the body is): each elbow pull drags you
	# about 0.3 m.
	var prone := clampf(remap(_shape.height, CROUCH_H, CRAWL_H, 0.0, 1.0), 0.0, 1.0)
	step_len = lerpf(step_len, 0.3, prone)
	if on_floor and hspeed > (0.3 if prone < 0.5 else 0.15):
		var prev := _step_phase
		_step_phase += hspeed * delta / step_len * PI
		if floori(prev / PI) != floori(_step_phase / PI):
			var strength := clampf(hspeed / SPRINT, 0.35, 1.0) * (0.55 if crouching else 1.0)
			if crawling:
				strength = 0.3          # knees and elbows, not footfalls
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
	var bz := 0.0
	var target_roll := -input.x * 0.025 + sin(p) * lerpf(0.003, 0.007, _run_blend) * amt
	var nod := -lerpf(w * 0.003, pow(w, 3.0) * 0.012, _run_blend) * amt - _land_dip * 0.15
	if prone > 0.0:
		# Elbow crawl: each pull heaves the shoulders up on one side and
		# drags the body forward, so the view rolls left and right, rises and
		# sinks a little, and lunges ahead on each pull.
		var ca := clampf(hspeed / CRAWL, 0.0, 1.0) * (1.0 if on_floor and head_bob else 0.0) * prone
		var pull := 0.5 - 0.5 * cos(2.0 * _step_phase)          # 0 at rest .. 1 mid-pull
		bx = lerpf(bx, sin(_step_phase) * 0.045, ca)
		by = lerpf(by, pull * 0.02 + breathe, prone)
		bz = -pull * 0.05 * ca
		target_roll = lerpf(target_roll, -input.x * 0.02 + sin(_step_phase) * 0.05 * ca, prone)
		nod = lerpf(nod, -pull * 0.025 * ca, prone)
	head.position = Vector3(bx, _eye + by - _land_dip, bz)
	_roll = lerpf(_roll, target_roll, 1.0 - exp(-10.0 * delta))
	camera.rotation.z = _roll
	# A small nod on each landing, stronger when running.
	camera.rotation.x = nod


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
	if side_mode and side:
		return side.albedo_at(p, n)
	if gen == null or mall_mode or side_mode:
		return Color(0.55, 0.53, 0.5)
	var c := gen.cell_of(p - n * 0.1)
	var b := gen.biome_at(c.x, c.y)
	if n.y > 0.6:
		return ChunkBuilder.ALB_FLOOR[b]
	if n.y < -0.6:
		return ChunkBuilder.ALB_CEIL[b]
	return ChunkBuilder.ALB_WALL[b]
