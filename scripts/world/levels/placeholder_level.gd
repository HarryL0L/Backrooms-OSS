class_name PlaceholderLevel
extends SideLevel
## Stands in for a side level that isn't built yet (SideLevels.create makes
## it when scripts/world/levels/<id>_level.gd doesn't exist): a plain lit
## room with the level's name on the wall and an exit door (to the level
## its chain goes on to, or back to the Backrooms). It also has a bit of
## everything the framework does, to try it out and as a worked example:
## a low duct through a wall block (crouch into it and you go down and
## crawl; metal underfoot), a flooded pit 1 m deep (wading, and the tint
## when your eyes go under), and a bank of ceiling lights that's light
## group 0 and flickers now and then.

## SideLevels.info() of the level it stands in for.
var info := {}
var _room: Node3D
var _flicker_t := 6.0
var _flicker := 0.0

## Room, local to (0, LEVEL_Y, 0): x -8..8, z -6..6, 3.2 m high.
const HALF := Vector2(8.0, 6.0)
const H := 3.2
## The duct: through a block against the north wall, x -4..0.
const DUCT := Rect2(-4.0, -5.0, 4.0, 1.0)      # x, z, length, width
const DUCT_H := 0.75
## The flooded pit: x 2..6, z -5..-1, floor 1.05 down, water 1 m deep.
const PIT := Rect2(2.0, -5.0, 4.0, 4.0)
const PIT_FLOOR := -1.05
const WATER := -0.05


func build(p_seed: int) -> void:
	seed_value = p_seed
	if info.is_empty():
		info = SideLevels.info(id)
	_room = Node3D.new()
	_room.name = "Room"
	add_child(_room)
	_room.position = Vector3(0.0, LEVEL_Y, 0.0)
	var lit := Color(0.42, 0.41, 0.38)
	var gm := Vector4(0.25, 0.0, 0.0, 0.0)       # part of the room's light is the ceiling bank (group 0)
	var floor_m := flat_material({"color": Color(0.46, 0.45, 0.43), "roughness": 0.85}, lit, gm)
	var wall_m := flat_material({"color": Color(0.74, 0.72, 0.66), "roughness": 0.9}, lit, gm)
	var ceil_m := flat_material({"color": Color(0.8, 0.79, 0.75), "roughness": 0.9}, lit * 0.8, gm)
	var duct_m := flat_material({"color": Color(0.62, 0.63, 0.62), "roughness": 0.35, "metallic": 0.6},
			Color(0.06, 0.06, 0.06), Vector4(0.02, 0.0, 0.0, 0.0))
	var tile_m := flat_material({"color": Color(0.7, 0.78, 0.78), "roughness": 0.3}, lit * 0.7, gm)
	var lamp_m := flat_material({"color": Color(1.0, 0.97, 0.9), "emit": 1.6, "group": 0}, Color(0, 0, 0))
	# Floor (with the pit cut out), ceiling, walls.
	var px0 := PIT.position.x
	var px1 := PIT.end.x
	var pz0 := PIT.position.y
	var pz1 := PIT.end.y
	_slab(floor_m, -HALF.x, px0, -HALF.y, HALF.y)
	_slab(floor_m, px1, HALF.x, -HALF.y, HALF.y)
	_slab(floor_m, px0, px1, -HALF.y, pz0)
	_slab(floor_m, px0, px1, pz1, HALF.y)
	add_box(Vector3(HALF.x * 2.0, 0.2, HALF.y * 2.0), Vector3(0, H + 0.1, 0), ceil_m, true, _room)
	for sx in [-1.0, 1.0]:
		add_box(Vector3(0.3, H, HALF.y * 2.0 + 0.6), Vector3(sx * (HALF.x + 0.15), H * 0.5, 0), wall_m, true, _room)
		add_box(Vector3(HALF.x * 2.0, H, 0.3), Vector3(0, H * 0.5, sx * (HALF.y + 0.15)), wall_m, true, _room)
	# The ceiling bank: light panels in a grid.
	for x in [-5.0, -1.0, 3.0]:
		for z in [-3.0, 1.0, 4.0]:
			add_box(Vector3(1.2, 0.02, 0.6), Vector3(x, H - 0.01, z), lamp_m, false, _room)
	# The pit: floor, sides, a step to climb out by, and the water.
	add_box(Vector3(PIT.size.x, 0.2, PIT.size.y), Vector3(PIT.get_center().x, PIT_FLOOR - 0.1, PIT.get_center().y), tile_m, true, _room)
	var dh := -PIT_FLOOR
	add_box(Vector3(0.2, dh, PIT.size.y), Vector3(px0 - 0.1, PIT_FLOOR + dh * 0.5, PIT.get_center().y), tile_m, true, _room)
	add_box(Vector3(0.2, dh, PIT.size.y), Vector3(px1 + 0.1, PIT_FLOOR + dh * 0.5, PIT.get_center().y), tile_m, true, _room)
	add_box(Vector3(PIT.size.x, dh, 0.2), Vector3(PIT.get_center().x, PIT_FLOOR + dh * 0.5, pz0 - 0.1), tile_m, true, _room)
	add_box(Vector3(PIT.size.x, dh, 0.2), Vector3(PIT.get_center().x, PIT_FLOOR + dh * 0.5, pz1 + 0.1), tile_m, true, _room)
	add_box(Vector3(0.8, 0.5, PIT.size.y), Vector3(px0 + 0.4, PIT_FLOOR + 0.25, PIT.get_center().y), tile_m, true, _room)
	var water := MeshInstance3D.new()
	var q := PlaneMesh.new()
	q.size = PIT.size
	water.mesh = q
	var wm := StandardMaterial3D.new()
	wm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wm.albedo_color = Color(0.05, 0.12, 0.11, 0.7)
	wm.roughness = 0.05
	wm.emission_enabled = true
	wm.emission = Color(0.03, 0.06, 0.06)
	wm.cull_mode = BaseMaterial3D.CULL_DISABLED
	water.material_override = wm
	water.position = Vector3(PIT.get_center().x, WATER, PIT.get_center().y)
	_room.add_child(water)
	# The duct block: a wall against the north wall with a low duct through.
	var dx0 := DUCT.position.x
	var dx1 := DUCT.end.x
	var dz0 := DUCT.position.y
	var dz1 := DUCT.end.y
	var dcx := (dx0 + dx1) * 0.5
	var bl := DUCT.size.x
	add_box(Vector3(bl, H, dz0 + HALF.y), Vector3(dcx, H * 0.5, (-HALF.y + dz0) * 0.5), wall_m, true, _room)
	add_box(Vector3(bl, H, 0.2), Vector3(dcx, H * 0.5, dz1 + 0.1), wall_m, true, _room)
	add_box(Vector3(bl, H - DUCT_H, DUCT.size.y), Vector3(dcx, DUCT_H + (H - DUCT_H) * 0.5, DUCT.get_center().y), wall_m, true, _room)
	# Its sheet metal lining (no collision of its own).
	add_box(Vector3(bl, 0.01, DUCT.size.y), Vector3(dcx, 0.005, DUCT.get_center().y), duct_m, false, _room)
	add_box(Vector3(bl, 0.01, DUCT.size.y), Vector3(dcx, DUCT_H - 0.005, DUCT.get_center().y), duct_m, false, _room)
	for z in [dz0 + 0.005, dz1 - 0.005]:
		add_box(Vector3(bl, DUCT_H, 0.01), Vector3(dcx, DUCT_H * 0.5, z), duct_m, false, _room)
	# The name on the east wall, by the exit.
	var sign_bg := flat_material({"color": Color(0.9, 0.88, 0.8)}, lit)
	add_box(Vector3(0.02, 1.3, 4.6), Vector3(HALF.x - 0.01, 1.85, -0.2), sign_bg, false, _room)
	_label(info.get("name", id), Vector3(HALF.x - 0.03, 2.25, -0.2), 0.0055)
	_label(info.get("intro", ""), Vector3(HALF.x - 0.03, 1.8, -0.2), 0.0028)
	_label("Placeholder: %s is not built yet" % SideLevels.script_path(id).get_file(), Vector3(HALF.x - 0.03, 1.42, -0.2), 0.0024)
	var to: String = info.get("next", "")
	add_exit(Transform3D(Basis(Vector3.UP, -PI * 0.5), _room.position + Vector3(HALF.x - 0.01, 0.0, 3.6)), "door", to,
			{"sign": "EXIT" if to == "" else "ON", "label": "Back to the Backrooms" if to == "" else "Go on"})
	add_loop("hum", Vector3.INF, -24.0)
	environment = make_environment({"background": Color(0.02, 0.02, 0.02), "fog": Color(0.05, 0.05, 0.045),
			"fog_density": 0.01})


func _slab(m: Material, x0: float, x1: float, z0: float, z1: float) -> void:
	add_box(Vector3(x1 - x0, 0.2, z1 - z0), Vector3((x0 + x1) * 0.5, -0.1, (z0 + z1) * 0.5), m, true, _room)


func _label(text: String, at: Vector3, px: float) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = px
	l.modulate = Color(0.1, 0.1, 0.1)
	l.shaded = false
	l.double_sided = false
	l.rotation.y = -PI * 0.5
	l.position = at
	_room.add_child(l)


func arrival() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, -PI * 0.5), _room.position + Vector3(-6.0, 0.0, 3.0))


func _local(p: Vector3) -> Vector3:
	return p - Vector3(0.0, LEVEL_Y, 0.0)


func _in_duct(p: Vector3) -> bool:
	var l := _local(p)
	return DUCT.has_point(Vector2(l.x, l.z)) and l.y < DUCT_H


func surface_at(p: Vector3) -> int:
	if _in_duct(p + Vector3.UP * 0.1):
		return Player.SURF_METAL
	var l := _local(p)
	if PIT.has_point(Vector2(l.x, l.z)):
		return Player.SURF_TILE
	return Player.SURF_CONCRETE


func water_level_at(p: Vector3) -> float:
	var l := _local(p)
	if PIT.grow(0.05).has_point(Vector2(l.x, l.z)):
		return LEVEL_Y + WATER
	return -INF


func light_at(p: Vector3) -> Color:
	if _in_duct(p + Vector3.UP * 0.1):
		return Color(0.06, 0.06, 0.06)
	return Color(0.55, 0.53, 0.5) * (0.65 + 0.35 * (1.0 - _flicker))


func camera_far() -> float:
	return 60.0


func reverb() -> Dictionary:
	return {"room": 0.55, "damp": 0.6, "wet": 0.22}


func _process(delta: float) -> void:
	# Now and then the ceiling bank stutters (light group 0).
	_flicker_t -= delta
	if _flicker_t <= 0.0:
		_flicker_t = randf_range(5.0, 11.0)
		_flicker = 1.0
	if _flicker > 0.0:
		_flicker = maxf(_flicker - delta * 1.4, 0.0)
		var on := 1.0 if _flicker <= 0.0 or randf() > 0.5 else 0.15
		set_light_group(0, Color(1.0, 0.97, 0.9), on)


func shots() -> Array:
	var o := _room.position
	return [
		{"name": "arrival", "transform": arrival()},
		{"name": "duct_mouth", "transform": Transform3D(Basis(Vector3.UP, -PI * 0.5).rotated(Vector3.UP, 0.0), o + Vector3(-5.5, 0.0, -4.5))},
		{"name": "in_duct", "transform": Transform3D(Basis(Vector3.UP, -PI * 0.5), o + Vector3(-2.5, 0.0, -4.5)), "crawl": true,
			"flashlight": true},
		{"name": "pit", "transform": Transform3D(Basis(Vector3.UP, 0.72) * Basis(Vector3.RIGHT, -0.35), o + Vector3(6.8, 0.0, 0.2))},
		{"name": "wading", "transform": Transform3D(Basis(Vector3.UP, PI * 0.5), o + Vector3(5.2, PIT_FLOOR, -3.0))},
		{"name": "exit", "transform": Transform3D(Basis(Vector3.UP, -PI * 0.5), o + Vector3(4.5, 0.0, 3.6))},
	]


## Film: walk to the duct, crouch, crawl through it, wade the pit, and go
## to the exit (drives the real controls, so it shows the stances and bob).
func film() -> void:
	var o := _room.position
	player.teleport(arrival().origin, SideLevel._yaw_of(arrival()))
	await _walk_to(o + Vector3(-5.0, 0.0, -4.5), 6.0)
	player.crouching = true
	await _walk_to(o + Vector3(0.8, 0.0, -4.5), 14.0)
	player.crouching = false
	await get_tree().create_timer(1.0).timeout
	await _walk_to(o + Vector3(1.8, 0.0, -3.0), 4.0)
	await _walk_to(o + Vector3(5.0, PIT_FLOOR, -3.0), 8.0)
	await _walk_to(o + Vector3(2.4, PIT_FLOOR, -3.0), 8.0)
	await _walk_to(o + Vector3(1.0, 0.0, -3.0), 4.0)
	await _walk_to(o + Vector3(6.5, 0.0, 3.6), 8.0)


## Walks (the forward key, turning towards it) until within 0.35 m of `to`
## (ignoring height) or `limit` seconds pass.
func _walk_to(to: Vector3, limit: float) -> void:
	var t := 0.0
	Input.action_press("move_forward")
	while t < limit:
		var d := to - player.global_position
		d.y = 0.0
		if d.length() < 0.35:
			break
		player.yaw = lerp_angle(player.yaw, atan2(-d.x, -d.z), 0.2)
		player._apply_rotation()
		t += get_process_delta_time()
		await get_tree().process_frame
	Input.action_release("move_forward")
