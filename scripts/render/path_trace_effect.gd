class_name PathTraceEffect
extends CompositorEffect
## Experimental path-traced lighting, the GPU side (PathTracer drives it).
## Runs before the opaque pass of the player's camera: traces the Lobby's
## cell grid from the camera at a fraction of the resolution
## (shaders/pt/pt_trace.glsl: direct light from the troffers plus one or two
## bounces, accumulated over frames), filters it (pt_filter.glsl, four a-trous
## passes) and leaves the result in `output`, which the Lobby's surface
## shaders read through the `pt_light` global instead of their baked light
## (shaders/pt_light.gdshaderinc). Rendering-device work only happens on the
## render thread; the main thread only sets the plain properties and the
## grid (set_cells).

## Fraction of the render resolution traced (4 = a quarter on each axis).
var divisor := 4
## Bounces after the first hit (1 or 2).
var bounces := 1
## Light world time (s), for the flicker (same clock as the shaders).
var world_time := 0.0
## Troffer radiance (times the light colour) and colour.
var radiance := 22.0
var light_color := Color(1.0, 0.87, 0.70)
## Frames of history at most (more = smoother, slower to follow flicker).
var max_history := 48.0
## Luminance cap of one sample (against fireflies).
var firefly := 6.0
## How freely the filter blurs.
var filter_strength := 1.0
## The texture the surface shaders sample (rgb irradiance / pi, a = surface id).
var output := Texture2DRD.new()
## True once a frame has been traced (the shaders may switch over).
var traced := false
## True when compute shaders couldn't be set up (stay on baked light).
var failed := false
## GPU time of the last measured frame (ms), -1 unknown.
var gpu_ms := -1.0

var _rd: RenderingDevice
var _trace_spirv: RDShaderSPIRV
var _filter_spirv: RDShaderSPIRV
var _trace_shader := RID()
var _trace_pipe := RID()
var _filter_shader := RID()
var _filter_pipe := RID()
var _ubo := RID()
var _cells_tex := RID()
var _size := Vector2i.ZERO
var _hist: Array[RID] = [RID(), RID()]
var _geo: Array[RID] = [RID(), RID()]
var _tmp: Array[RID] = [RID(), RID()]
var _out := RID()
var _graveyard: Array = []        # [rid, frames left]: freed once no longer in flight
var _cur := 0
var _frame := 0
var _reset := true
var _prev_vp := Projection.IDENTITY
var _prev_cam := Vector3.ZERO

const WIN := 64
var _mutex := Mutex.new()
var _cells := PackedByteArray()
var _cells_dirty := false
var _origin := Vector2i.ZERO
var _origin_gpu := Vector2i.ZERO


func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_PRE_OPAQUE
	enabled = false
	_rd = RenderingServer.get_rendering_device()
	if _rd == null:
		failed = true
		return
	var tf: RDShaderFile = load("res://shaders/pt/pt_trace.glsl")
	var ff: RDShaderFile = load("res://shaders/pt/pt_filter.glsl")
	if tf == null or ff == null:
		failed = true
		return
	_trace_spirv = tf.get_spirv()
	_filter_spirv = ff.get_spirv()
	if _trace_spirv.compile_error_compute != "" or _filter_spirv.compile_error_compute != "":
		push_warning("PathTraceEffect: " + _trace_spirv.compile_error_compute + _filter_spirv.compile_error_compute)
		failed = true
		return
	RenderingServer.call_on_render_thread(_setup)


func _setup() -> void:
	_trace_shader = _rd.shader_create_from_spirv(_trace_spirv, "pt_trace")
	_filter_shader = _rd.shader_create_from_spirv(_filter_spirv, "pt_filter")
	if not _trace_shader.is_valid() or not _filter_shader.is_valid():
		failed = true
		return
	_trace_pipe = _rd.compute_pipeline_create(_trace_shader)
	_filter_pipe = _rd.compute_pipeline_create(_filter_shader)
	_ubo = _rd.uniform_buffer_create(UBO_SIZE)
	var tf := RDTextureFormat.new()
	tf.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_UINT
	tf.width = WIN
	tf.height = WIN
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
			| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
	var zero := PackedByteArray()
	zero.resize(WIN * WIN * 8)
	_cells_tex = _rd.texture_create(tf, RDTextureView.new(), [zero])
	if not _trace_pipe.is_valid() or not _filter_pipe.is_valid() or not _cells_tex.is_valid():
		failed = true


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and _rd != null:
		var rids: Array[RID] = [_trace_pipe, _filter_pipe, _trace_shader, _filter_shader, _ubo, _cells_tex, _out]
		rids.append_array(_hist)
		rids.append_array(_geo)
		rids.append_array(_tmp)
		for g in _graveyard:
			rids.append(g[0])
		for r in rids:
			if r.is_valid():
				_rd.free_rid(r)


## The cell grid around the player: WIN x WIN cells from cell `origin`, four
## 16-bit words each (see ChunkBuilder._pt_cells).
func set_cells(origin: Vector2i, bytes: PackedByteArray) -> void:
	_mutex.lock()
	_origin = origin
	_cells = bytes
	_cells_dirty = true
	_mutex.unlock()


## Drop the history (after a teleport, or when switched back on).
func reset() -> void:
	_reset = true


const UBO_SIZE := 64 * 3 + 16 * 6


func _texture(format: int, size: Vector2i, sampled: bool) -> RID:
	var tf := RDTextureFormat.new()
	tf.format = format
	tf.width = size.x
	tf.height = size.y
	tf.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT | RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT \
			| (RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT if sampled else 0)
	return _rd.texture_create(tf, RDTextureView.new())


func _alloc(size: Vector2i) -> void:
	var old: Array[RID] = [_out]
	old.append_array(_hist)
	old.append_array(_geo)
	old.append_array(_tmp)
	for r in old:
		if r.is_valid():
			_graveyard.append([r, 4])
	_size = size
	for i in 2:
		_hist[i] = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, size, false)
		_geo[i] = _texture(RenderingDevice.DATA_FORMAT_R32_SFLOAT, size, false)
		_tmp[i] = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, size, false)
	_out = _texture(RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT, size, true)
	_reset = true
	# (Texture2DRD hands this to the render thread itself; set it from the main thread.)
	output.call_deferred("set_texture_rd_rid", _out)


func _image(binding: int, rid: RID) -> RDUniform:
	var u := RDUniform.new()
	u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u.binding = binding
	u.add_id(rid)
	return u


static func _put_proj(b: PackedByteArray, at: int, p: Projection) -> void:
	for c in 4:
		var v: Vector4 = p[c]
		for k in 4:
			b.encode_float(at + c * 16 + k * 4, v[k])


static func _put_vec(b: PackedByteArray, at: int, v: Vector4) -> void:
	for k in 4:
		b.encode_float(at + k * 4, v[k])


static func _put_ivec(b: PackedByteArray, at: int, a: int, c: int, d: int, e: int) -> void:
	b.encode_s32(at, a)
	b.encode_s32(at + 4, c)
	b.encode_s32(at + 8, d)
	b.encode_s32(at + 12, e)


func _render_callback(_type: int, render_data: RenderData) -> void:
	if failed or not _trace_pipe.is_valid():
		return
	for i in range(_graveyard.size() - 1, -1, -1):
		_graveyard[i][1] -= 1
		if _graveyard[i][1] <= 0:
			_rd.free_rid(_graveyard[i][0])
			_graveyard.remove_at(i)
	var sb := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	var sd := render_data.get_render_scene_data() as RenderSceneDataRD
	if sb == null or sd == null:
		return
	var full := sb.get_internal_size()
	var size := Vector2i(ceili(full.x / float(divisor)), ceili(full.y / float(divisor)))
	if size.x < 8 or size.y < 8:
		return
	if size != _size:
		_alloc(size)
	_mutex.lock()
	if _cells_dirty:
		_cells_dirty = false
		_origin_gpu = _origin
		if _cells.size() == WIN * WIN * 8:
			_rd.texture_update(_cells_tex, 0, _cells)
	_mutex.unlock()

	var cam := sd.get_cam_transform()
	var proj := sd.get_cam_projection()
	var b := PackedByteArray()
	b.resize(UBO_SIZE)
	_put_proj(b, 0, proj.inverse())
	_put_proj(b, 64, Projection(Transform3D(cam.basis, Vector3.ZERO)))
	_put_proj(b, 128, _prev_vp)
	_put_vec(b, 192, Vector4(cam.origin.x, cam.origin.y, cam.origin.z, world_time))
	_put_vec(b, 208, Vector4(_prev_cam.x, _prev_cam.y, _prev_cam.z, radiance))
	_put_ivec(b, 224, _origin_gpu.x, _origin_gpu.y, WIN, _frame)
	_put_ivec(b, 240, size.x, size.y, clampi(bounces, 0, 3), 1 if _reset else 0)
	_put_vec(b, 256, Vector4(light_color.r, light_color.g, light_color.b, max_history))
	_put_vec(b, 272, Vector4(0.0, firefly, 0.0, 0.0))
	_rd.buffer_update(_ubo, 0, UBO_SIZE, b)

	var prev := _cur
	_cur = 1 - _cur
	var ubo_u := RDUniform.new()
	ubo_u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	ubo_u.binding = 0
	ubo_u.add_id(_ubo)
	var trace_set := UniformSetCacheRD.get_cache(_trace_shader, 0, [ubo_u, _image(1, _cells_tex),
			_image(2, _hist[prev]), _image(3, _geo[prev]), _image(4, _hist[_cur]), _image(5, _geo[_cur])])
	var gx := ceili(size.x / 8.0)
	var gy := ceili(size.y / 8.0)
	_rd.draw_command_begin_label("Path traced lighting", Color(1, 0.8, 0.4))
	_rd.capture_timestamp("pt_begin")
	var list := _rd.compute_list_begin()
	_rd.compute_list_bind_compute_pipeline(list, _trace_pipe)
	_rd.compute_list_bind_uniform_set(list, trace_set, 0)
	_rd.compute_list_dispatch(list, gx, gy, 1)
	_rd.compute_list_end()
	_rd.capture_timestamp("pt_traced")
	# A-trous: hist -> tmp0 -> tmp1 -> tmp0 -> out.
	var srcs: Array[RID] = [_hist[_cur], _tmp[0], _tmp[1], _tmp[0]]
	var dsts: Array[RID] = [_tmp[0], _tmp[1], _tmp[0], _out]
	for k in 4:
		var fset := UniformSetCacheRD.get_cache(_filter_shader, 0, [_image(0, srcs[k]), _image(1, _geo[_cur]),
				_image(2, _hist[_cur]), _image(3, dsts[k])])
		var pc := PackedByteArray()
		pc.resize(16)
		pc.encode_s32(0, size.x)
		pc.encode_s32(4, size.y)
		pc.encode_s32(8, 1 << k)
		pc.encode_float(12, filter_strength)
		list = _rd.compute_list_begin()
		_rd.compute_list_bind_compute_pipeline(list, _filter_pipe)
		_rd.compute_list_bind_uniform_set(list, fset, 0)
		_rd.compute_list_set_push_constant(list, pc, pc.size())
		_rd.compute_list_dispatch(list, gx, gy, 1)
		_rd.compute_list_end()
	_rd.capture_timestamp("pt_end")
	_rd.draw_command_end_label()
	_read_timing()

	_prev_vp = proj * Projection(cam.affine_inverse())
	_prev_cam = cam.origin
	_reset = false
	_frame += 1
	traced = true


## GPU time between our timestamps, from a frame that has finished.
func _read_timing() -> void:
	var n := _rd.get_captured_timestamps_count()
	var t0 := -1
	var t1 := -1
	for i in n:
		var nm := _rd.get_captured_timestamp_name(i)
		if nm == "pt_begin":
			t0 = _rd.get_captured_timestamp_gpu_time(i)
		elif nm == "pt_end":
			t1 = _rd.get_captured_timestamp_gpu_time(i)
	if t0 >= 0 and t1 > t0:
		gpu_ms = (t1 - t0) / 1000000.0
