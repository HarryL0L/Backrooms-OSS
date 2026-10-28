class_name PathTracer
extends Node
## Experimental path-traced lighting for the Lobby (Level 0, and the Lobby
## round the stairwells), the "graphics/path_traced" setting. While you're in
## the Lobby the walls, carpet, ceiling and trim are lit by a small real-time
## path tracer (PathTraceEffect on the player camera's compositor) instead of
## the baked lightmaps: light falls off along the walls from each troffer,
## the ceiling only gets bounce light, corners darken softly. Everywhere else
## (and with the setting off) nothing changes. Needs a RenderingDevice
## renderer (Forward+ or Mobile); on Compatibility, or if the compute shaders
## can't be built, it stays on baked light.
##
## This node keeps the tracer's copy of the cell grid round the player up to
## date (built from the loaded chunks, ChunkBuilder._pt_cells), switches the
## surface shaders over (`pt_on` global) once a frame has been traced and
## swaps the colour grade for a Cycles-like one (AgX, a little less exposure).

## Exposure while active (the path-traced Lobby is a little brighter than the
## baked one near the lights).
const EXPOSURE := 0.85
## Quality presets: [resolution divisor, bounces].
const QUALITY := [[4, 1], [4, 2], [2, 1], [2, 2]]

var game: Node
var effect: PathTraceEffect
## True while the Lobby is path traced (shaders switched over).
var active := false

var _compositor: Compositor
var _camera: Camera3D
var _origin := Vector2i(1 << 30, 0)
var _version := -1
var _gen: WorldGen
var _last_cam := Vector3.ZERO


## True when this renderer can run it at all.
static func supported() -> bool:
	return RenderingServer.get_current_rendering_method() != "gl_compatibility" \
			and RenderingServer.get_rendering_device() != null


func _exit_tree() -> void:
	RenderingServer.global_shader_parameter_set("pt_on", 0.0)
	if effect != null:
		# The tracer's texture is freed with it: leave the shaders a stand-in.
		var img := Image.create(1, 1, false, Image.FORMAT_RGBAF)
		RenderingServer.global_shader_parameter_set("pt_light", ImageTexture.create_from_image(img))
		if _camera != null and is_instance_valid(_camera):
			_camera.compositor = null


func _process(_delta: float) -> void:
	var want := _wanted()
	if want and effect == null:
		_create()
	if effect != null and effect.failed:
		want = false
	if effect != null:
		effect.enabled = want
	if want:
		_update_cells()
		var q: Array = QUALITY[clampi(int(Settings.get_value("graphics/pt_quality")), 0, QUALITY.size() - 1)]
		effect.divisor = q[0]
		effect.bounces = q[1]
		effect.world_time = Ambience.world_time()
		var cam: Vector3 = game.player.camera.global_position
		if cam.distance_to(_last_cam) > 3.0:
			effect.reset()          # teleported: the old history is of somewhere else
		_last_cam = cam
	var on := want and effect.traced
	if on != active:
		active = on
		RenderingServer.global_shader_parameter_set("pt_on", 1.0 if on else 0.0)
		if on:
			RenderingServer.global_shader_parameter_set("pt_light", effect.output)
		game.path_tracing_changed(on)
	if not want and effect != null:
		effect.traced = false
		effect.reset()


func _wanted() -> bool:
	if not Settings.get_value("graphics/path_traced") or Settings.get_value("graphics/ps1") or not supported():
		return false
	if game == null or game.gen == null or game.player == null:
		return false
	if not (game.state == game.State.PLAYING or game.state == game.State.PAUSED):
		return false
	if game._away() or game._biome != WorldGen.LOBBY:
		return false
	return true


func _create() -> void:
	effect = PathTraceEffect.new()
	if effect.failed:
		push_warning("PathTracer: compute shaders unavailable, staying on baked light")
		return
	_compositor = Compositor.new()
	_compositor.compositor_effects = [effect]
	_camera = game.player.camera
	_camera.compositor = _compositor


## Rebuilds the tracer's grid (PathTraceEffect.WIN cells square, whole chunks,
## the player's chunk near the middle) when the player changes chunk or
## chunks load / unload.
func _update_cells() -> void:
	var chunks: ChunkManager = game.chunks
	var cc := ChunkManager.chunk_of(game.player.global_position)
	var per := PathTraceEffect.WIN / WorldGen.CHUNK
	var origin := (cc - Vector2i(per / 2, per / 2)) * WorldGen.CHUNK
	if origin == _origin and chunks.layout_version == _version and game.gen == _gen:
		return
	_origin = origin
	_version = chunks.layout_version
	_gen = game.gen
	var row := WorldGen.CHUNK * 8
	var empty := PackedByteArray()
	empty.resize(WorldGen.CHUNK * WorldGen.CHUNK * 8)
	var data := []
	for z in per:
		for x in per:
			var b := chunks.pt_cells(cc + Vector2i(x - per / 2, z - per / 2))
			data.append(b if b.size() == empty.size() else empty)
	var out := PackedByteArray()
	for z in per:
		for j in WorldGen.CHUNK:
			for x in per:
				out.append_array((data[x + z * per] as PackedByteArray).slice(j * row, (j + 1) * row))
	effect.set_cells(origin, out)
