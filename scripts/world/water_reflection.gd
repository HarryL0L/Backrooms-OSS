class_name WaterReflection
extends Node
## Real-time planar reflection for the Tiled Baths water. Every pool in the world
## shares one water height, so a single mirrored camera rendering at reduced
## resolution gives true reflections of walls, arches, columns and lights.
## Only active while the player is in the Tiled Baths.

var source: Camera3D
var material: ShaderMaterial
var active := false
var scale := 0.5

var _vp: SubViewport
var _cam: Camera3D


func _ready() -> void:
	process_priority = 100  # after the player has moved the camera
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.positional_shadow_atlas_size = 0
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	add_child(_vp)
	_cam = Camera3D.new()
	_vp.add_child(_cam)


func set_active(on: bool) -> void:
	active = on and source != null
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	if material:
		material.set_shader_parameter("reflection_on", 1.0 if active else 0.0)
		material.set_shader_parameter("reflection_tex", _vp.get_texture())


func _process(_delta: float) -> void:
	if not active:
		return
	var size := Vector2(get_viewport().get_visible_rect().size)
	var win := Vector2(DisplayServer.window_get_size())
	if win.x > 0:
		size = win
	var want := Vector2i(maxi(64, int(size.x * scale)), maxi(36, int(size.y * scale)))
	if _vp.size != want:
		_vp.size = want
	var t := source.global_transform
	var h := WorldGen.WATER_Y
	var o := t.origin
	var fwd := -t.basis.z
	var up := t.basis.y
	fwd.y = -fwd.y
	up.y = -up.y
	_cam.global_transform = Transform3D(Basis.looking_at(fwd, up), Vector3(o.x, 2.0 * h - o.y, o.z))
	_cam.fov = source.fov
	_cam.near = source.near
	_cam.far = source.far
