class_name RetroView
extends Node
## "PS1 style" output: the 3D world is rendered into a small SubViewport
## (240 lines by default) by a camera that copies the player's, then shown
## full screen with nearest-neighbour scaling, 15-bit colour and ordered
## dithering. The HUD and touch controls stay sharp on top. While active the
## main viewport skips 3D rendering entirely, so this costs less than the
## normal path. Vertex snapping (the PS1 "wobble") is done in the world
## shaders through the `ps1_grid` global (see shaders/ps1.gdshaderinc).

var source: Camera3D
var active := false
var lines := 240

var _vp: SubViewport
var _cam: Camera3D
var _layer: CanvasLayer
var _rect: TextureRect
var _mat: ShaderMaterial


func _ready() -> void:
	process_priority = 100   # after the player has moved the camera
	_vp = SubViewport.new()
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_vp.msaa_3d = Viewport.MSAA_DISABLED
	_vp.handle_input_locally = false
	_vp.gui_disable_input = true
	_vp.audio_listener_enable_3d = false
	add_child(_vp)
	_cam = Camera3D.new()
	_cam.current = true
	_vp.add_child(_cam)
	_layer = CanvasLayer.new()
	_layer.layer = -1        # below the HUD and its lens/grain layer
	_layer.visible = false
	add_child(_layer)
	_rect = TextureRect.new()
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.texture = _vp.get_texture()
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/ps1_present.gdshader")
	_rect.material = _mat
	_layer.add_child(_rect)


func set_active(on: bool) -> void:
	active = on and source != null
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if active else SubViewport.UPDATE_DISABLED
	_layer.visible = active
	get_viewport().disable_3d = active
	if not active:
		RenderingServer.global_shader_parameter_set("ps1_grid", Vector2.ZERO)
	_process(0.0)


func _process(_delta: float) -> void:
	if not active:
		return
	var win := Vector2(get_viewport().get_visible_rect().size)
	var h := clampi(lines, 120, 720)
	var want := Vector2i(maxi(64, roundi(win.x / win.y * h)), h)
	if _vp.size != want:
		_vp.size = want
		_mat.set_shader_parameter("src_size", Vector2(want))
	# Snap vertices to a 2-pixel grid: visibly wobbly, not shredded.
	RenderingServer.global_shader_parameter_set("ps1_grid", Vector2(want) * 0.25)
	_cam.global_transform = source.global_transform
	_cam.fov = source.fov
	_cam.near = source.near
	_cam.far = source.far
	_cam.cull_mask = source.cull_mask
	_cam.environment = source.environment
	_cam.attributes = source.attributes
