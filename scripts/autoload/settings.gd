extends Node
## Global settings, input bindings and touch layout. Persisted to user://.

signal changed

const PATH := "user://settings.cfg"

const ACTIONS := ["move_forward", "move_back", "move_left", "move_right", "sprint", "crouch", "jump", "flashlight", "pause"]
const ACTION_LABELS := {
	"move_forward": "Move forward", "move_back": "Move back", "move_left": "Strafe left",
	"move_right": "Strafe right", "sprint": "Sprint", "crouch": "Crouch", "jump": "Jump / climb",
	"flashlight": "Flashlight", "pause": "Pause",
}
const DEFAULT_KEYS := {
	"move_forward": ["k:87", "k:4194320"],     # W, Up
	"move_back": ["k:83", "k:4194322"],        # S, Down
	"move_left": ["k:65", "k:4194319"],        # A, Left
	"move_right": ["k:68", "k:4194321"],       # D, Right
	"sprint": ["k:4194325", ""],               # Shift
	"crouch": ["k:4194326", "k:67"],           # Ctrl, C
	"jump": ["k:32", ""],                      # Space
	"flashlight": ["k:70", "m:2"],             # F, right mouse
	"pause": ["k:4194305", "k:80"],            # Escape, P
}
const DEFAULT_PAD := {
	"sprint": "j:7", "crouch": "j:1", "jump": "j:0", "flashlight": "j:3", "pause": "j:6",
	"move_forward": "", "move_back": "", "move_left": "", "move_right": "",
}
# Fixed analogue bindings for the movement actions.
const PAD_AXES := {
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0], "move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"move_left": [JOY_AXIS_LEFT_X, -1.0], "move_right": [JOY_AXIS_LEFT_X, 1.0],
}

const TOUCH_DEFAULTS := {
	"joystick": {"pos": Vector2(0.15, 0.70), "scale": 1.0},
	"jump": {"pos": Vector2(0.885, 0.60), "scale": 1.0},
	"crouch": {"pos": Vector2(0.885, 0.84), "scale": 1.0},
	"sprint": {"pos": Vector2(0.765, 0.84), "scale": 1.0},
	"flashlight": {"pos": Vector2(0.92, 0.36), "scale": 0.85},
	"pause": {"pos": Vector2(0.955, 0.08), "scale": 0.7},
}

var is_mobile := false
## True when running the Forward+ ("Ultra") build: SSR, SSAO, SSIL, volumetric fog.
var is_ultra := false
## Ultra crash guard: how many effect groups were switched off because a
## previous launch died before reaching the menu (GPU driver crashes).
var ultra_safe_level := 0
const GUARD_PATH := "user://ultra_guard.cfg"
const GUARD_MAX := 3
var values := {}
var keys := {}
var pad := {}
var touch_layout := {}


func defaults() -> Dictionary:
	return {
		"graphics/render_scale": (0.7 if is_ultra else 0.8) if is_mobile else 1.0,
		"graphics/fsr": true,
		"graphics/aa": 3 if is_ultra else (1 if is_mobile else 2),
		"graphics/ssr": true,
		"graphics/ssao": true,
		"graphics/ssil": not is_mobile,
		"graphics/volumetric_fog": true,
		"graphics/view_distance": 3 if is_mobile else 4,
		"graphics/fps_cap": 1,
		"graphics/bloom": true,
		"graphics/film_grain": true,
		"graphics/lens_fx": true,
		"graphics/halos": true,
		"graphics/realtime_lights": true,
		"graphics/light_highlights": true,
		"graphics/water_ripples": true,
		"graphics/lightmaps": true,
		"graphics/preset": 2 if is_mobile else 3,
		"graphics/auto_quality": true,
		"graphics/water_reflections": 1 if is_mobile else 2,
		"graphics/flashlight_shadows": not is_mobile,
		"graphics/fov": 75.0,
		"graphics/head_bob": true,
		"graphics/brightness": 1.0,
		"graphics/show_fps": false,
		"audio/master": 0.9,
		"audio/ambience": 0.9,
		"audio/effects": 1.0,
		"controls/mouse_sens": 1.0,
		"controls/touch_sens": 1.0,
		"controls/pad_sens": 1.0,
		"controls/invert_y": false,
		"controls/crouch_toggle": true,
		"controls/sprint_toggle": false,
		"controls/touch_mode": 0,
		"controls/touch_opacity": 0.55,
	}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	is_mobile = OS.has_feature("mobile") or OS.has_feature("web_android") or OS.has_feature("web_ios")
	is_ultra = RenderingServer.get_current_rendering_method() == "forward_plus"
	values = defaults()
	keys = DEFAULT_KEYS.duplicate(true)
	pad = DEFAULT_PAD.duplicate(true)
	touch_layout = TOUCH_DEFAULTS.duplicate(true)
	_setup_audio_buses()
	var first_run := not FileAccess.file_exists(PATH)
	load_settings()
	if first_run:
		var tier := detect_tier()
		print("Backrooms-OSS: first launch, detected quality tier ", PRESET_NAMES[tier], " (", device_summary(), ")")
		apply_preset(tier)
	_ultra_guard_begin()
	apply_bindings()
	apply()


## Guesses a quality preset from the hardware on first launch:
## Potato for very weak devices, Low for weak ones, else the platform default.
## The in-game frame-rate watchdog (Game) corrects it later if it's wrong.
func detect_tier() -> int:
	var default_tier: int = defaults()["graphics/preset"]
	if not is_mobile:
		return default_tier
	var gpu := RenderingServer.get_video_adapter_name()
	var cores := OS.get_processor_count()
	var mem_gb := float(OS.get_memory_info().get("physical", 0)) / 1073741824.0
	var compat := RenderingServer.get_current_rendering_method() == "gl_compatibility"
	var potato_gpu := RegEx.create_from_string("(?i)(mali-(4\\d\\d|t[678]\\d\\d|g31|g51)|adreno.*\\b(3\\d\\d|4\\d\\d|50\\d)\\b|powervr.*(sgx|ge8))")
	var low_gpu := RegEx.create_from_string("(?i)(mali-(g52|g57|g68)|adreno.*\\b(51\\d|6[01]\\d)\\b|powervr)")
	if compat or (mem_gb > 0.0 and mem_gb < 2.5) or cores <= 4 or potato_gpu.search(gpu) != null:
		return 0
	if (mem_gb > 0.0 and mem_gb < 4.5) or low_gpu.search(gpu) != null:
		return 1
	return default_tier


func device_summary() -> String:
	return "%s, %s, %d cores, %.1f GB RAM" % [RenderingServer.get_video_adapter_name(),
			RenderingServer.get_current_rendering_method(), OS.get_processor_count(),
			float(OS.get_memory_info().get("physical", 0)) / 1073741824.0]


func get_value(key: String) -> Variant:
	return values.get(key, defaults().get(key))


func set_value(key: String, v: Variant) -> void:
	values[key] = v
	apply()
	save_settings()
	changed.emit()


# ------------------------------------------------------------ persistence ---

## Some mobile GPU drivers crash while compiling Forward+ effect shaders (seen
## on Mali-G77). Native crashes can't be caught, so every Ultra launch leaves a
## "pending" marker that is only cleared once the game reaches its menu. If the
## marker is still there on the next launch, one more group of effects is
## disabled, so repeated launches converge on a configuration the driver survives.
func _ultra_guard_begin() -> void:
	if not is_ultra:
		return
	var cf := ConfigFile.new()
	cf.load(GUARD_PATH)
	var level: int = cf.get_value("guard", "level", 0)
	if cf.get_value("guard", "pending", false):
		level = mini(level + 1, GUARD_MAX)
	ultra_safe_level = level
	cf.set_value("guard", "level", level)
	cf.set_value("guard", "pending", true)
	cf.save(GUARD_PATH)
	if level >= 1:
		values["graphics/volumetric_fog"] = false
		values["graphics/ssil"] = false
	if level >= 2:
		values["graphics/ssr"] = false
		values["graphics/ssao"] = false
	if level >= 3:
		values["graphics/water_reflections"] = 0
		values["graphics/lens_fx"] = false
		values["graphics/aa"] = 0
	if level > 0:
		save_settings()


## Called once the game has been running stably (menu reached).
func mark_ultra_stable() -> void:
	if not is_ultra:
		return
	var cf := ConfigFile.new()
	cf.load(GUARD_PATH)
	cf.set_value("guard", "pending", false)
	cf.save(GUARD_PATH)


func ultra_guard_message() -> String:
	match ultra_safe_level:
		1:
			return "Ultra: volumetric fog and SSIL were turned off after a crash on this device."
		2:
			return "Ultra: volumetric fog, SSIL, SSR and SSAO were turned off after crashes on this device."
		3:
			return "Ultra: most effects were turned off after crashes. If it still crashes, use the standard APK."
	return ""


func load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(PATH) != OK:
		return
	var d := defaults()
	for k in d:
		var parts: PackedStringArray = k.split("/")
		if cf.has_section_key(parts[0], parts[1]):
			var v: Variant = cf.get_value(parts[0], parts[1])
			if typeof(v) == typeof(d[k]) or (typeof(d[k]) == TYPE_FLOAT and typeof(v) == TYPE_INT):
				values[k] = v
	for a in ACTIONS:
		if cf.has_section_key("keys", a):
			var arr: Variant = cf.get_value("keys", a)
			if arr is Array and arr.size() == 2:
				keys[a] = arr
		if cf.has_section_key("pad", a):
			pad[a] = str(cf.get_value("pad", a))
	for id in TOUCH_DEFAULTS:
		if cf.has_section_key("touch_layout", id):
			var e: Variant = cf.get_value("touch_layout", id)
			if e is Dictionary and e.has("pos") and e.has("scale"):
				touch_layout[id] = e


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in values:
		var parts: PackedStringArray = k.split("/")
		cf.set_value(parts[0], parts[1], values[k])
	for a in ACTIONS:
		cf.set_value("keys", a, keys[a])
		cf.set_value("pad", a, pad[a])
	for id in touch_layout:
		cf.set_value("touch_layout", id, touch_layout[id])
	cf.save(PATH)


const PRESET_NAMES := ["Potato", "Low", "Medium", "High", "Max"]
const PRESETS := [
	# Potato: for very weak phones. Everything optional is off, half-res render,
	# per-vertex lighting (cheaper world generation), 30 FPS cap.
	{"graphics/render_scale": 0.5, "graphics/fsr": false, "graphics/aa": 0, "graphics/view_distance": 2,
		"graphics/water_reflections": 0, "graphics/water_ripples": false, "graphics/lens_fx": false,
		"graphics/film_grain": false, "graphics/flashlight_shadows": false, "graphics/halos": false,
		"graphics/bloom": false, "graphics/light_highlights": false, "graphics/lightmaps": false, "graphics/fps_cap": 0},
	{"graphics/render_scale": 0.6, "graphics/fsr": true, "graphics/water_ripples": true, "graphics/lightmaps": true, "graphics/film_grain": true, "graphics/aa": 0, "graphics/view_distance": 2, "graphics/water_reflections": 0,
		"graphics/lens_fx": false, "graphics/flashlight_shadows": false, "graphics/halos": true, "graphics/bloom": true, "graphics/light_highlights": false},
	{"graphics/render_scale": 0.75, "graphics/fsr": true, "graphics/water_ripples": true, "graphics/lightmaps": true, "graphics/film_grain": true, "graphics/aa": 1, "graphics/view_distance": 3, "graphics/water_reflections": 1,
		"graphics/lens_fx": true, "graphics/flashlight_shadows": false, "graphics/halos": true, "graphics/bloom": true, "graphics/light_highlights": true},
	{"graphics/render_scale": 0.9, "graphics/fsr": true, "graphics/water_ripples": true, "graphics/lightmaps": true, "graphics/film_grain": true, "graphics/aa": 1, "graphics/view_distance": 4, "graphics/water_reflections": 2,
		"graphics/lens_fx": true, "graphics/flashlight_shadows": true, "graphics/halos": true, "graphics/bloom": true, "graphics/light_highlights": true},
	{"graphics/render_scale": 1.0, "graphics/fsr": true, "graphics/water_ripples": true, "graphics/lightmaps": true, "graphics/film_grain": true, "graphics/aa": 2, "graphics/view_distance": 5, "graphics/water_reflections": 2,
		"graphics/lens_fx": true, "graphics/flashlight_shadows": true, "graphics/halos": true, "graphics/bloom": true, "graphics/light_highlights": true},
]


## Applies a whole quality preset (0 Potato .. 4 Max) at once.
func apply_preset(i: int) -> void:
	i = clampi(i, 0, PRESETS.size() - 1)
	var p: Dictionary = PRESETS[i]
	for k in p:
		values[k] = p[k]
	values["graphics/preset"] = i
	apply()
	save_settings()
	changed.emit()


func reset_touch_layout() -> void:
	touch_layout = TOUCH_DEFAULTS.duplicate(true)
	save_settings()
	changed.emit()


func reset_bindings() -> void:
	keys = DEFAULT_KEYS.duplicate(true)
	pad = DEFAULT_PAD.duplicate(true)
	apply_bindings()
	save_settings()
	changed.emit()


# ---------------------------------------------------------------- apply ---

func apply() -> void:
	ChunkBuilder.lightmaps = get_value("graphics/lightmaps")
	ChunkBuilder.water_sub = 16 if get_value("graphics/preset") > 0 else 4
	var fps: int = get_value("graphics/fps_cap")
	Engine.max_fps = [30, 60, 0][clampi(fps, 0, 2)]
	var vp := get_tree().root
	vp.scaling_3d_scale = clampf(get_value("graphics/render_scale"), 0.4, 1.0)
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if get_value("graphics/fsr") and vp.scaling_3d_scale < 0.99 \
			else Viewport.SCALING_3D_MODE_BILINEAR
	# 0 off, 1 MSAA 2x, 2 MSAA 4x, 3 SMAA, 4 FXAA
	var aa: int = clampi(get_value("graphics/aa"), 0, 4)
	vp.msaa_3d = [Viewport.MSAA_DISABLED, Viewport.MSAA_2X, Viewport.MSAA_4X, Viewport.MSAA_DISABLED, Viewport.MSAA_DISABLED][aa]
	if RenderingServer.get_current_rendering_method() != "gl_compatibility":
		vp.screen_space_aa = [Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED, Viewport.SCREEN_SPACE_AA_DISABLED,
				Viewport.SCREEN_SPACE_AA_SMAA, Viewport.SCREEN_SPACE_AA_FXAA][aa]
	_set_bus("Master", get_value("audio/master"))
	_set_bus("Ambience", get_value("audio/ambience"))
	_set_bus("World", get_value("audio/effects"))


func _set_bus(bus: String, v: float) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx >= 0:
		AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(v, 0.0001)))
		AudioServer.set_bus_mute(idx, v <= 0.001)


func _setup_audio_buses() -> void:
	if AudioServer.get_bus_index("World") < 0:
		AudioServer.add_bus()
		var i := AudioServer.bus_count - 1
		AudioServer.set_bus_name(i, "World")
		AudioServer.set_bus_send(i, "Master")
		var rev := AudioEffectReverb.new()
		rev.room_size = 0.6
		rev.damping = 0.6
		rev.wet = 0.25
		rev.dry = 1.0
		rev.spread = 0.8
		AudioServer.add_bus_effect(i, rev)
	if AudioServer.get_bus_index("Ambience") < 0:
		AudioServer.add_bus()
		var j := AudioServer.bus_count - 1
		AudioServer.set_bus_name(j, "Ambience")
		AudioServer.set_bus_send(j, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 20000.0
		AudioServer.add_bus_effect(j, lp)


# ------------------------------------------------------------- bindings ---

func apply_bindings() -> void:
	for a in ACTIONS:
		if not InputMap.has_action(a):
			InputMap.add_action(a, 0.25)
		InputMap.action_erase_events(a)
		for s in keys[a]:
			var ev := event_from_string(s)
			if ev:
				InputMap.action_add_event(a, ev)
		var pe := event_from_string(pad.get(a, ""))
		if pe:
			InputMap.action_add_event(a, pe)
		if PAD_AXES.has(a):
			var m := InputEventJoypadMotion.new()
			m.axis = PAD_AXES[a][0]
			m.axis_value = PAD_AXES[a][1]
			m.device = -1
			InputMap.action_add_event(a, m)


func set_key_binding(action: String, slot: int, ev: InputEvent) -> void:
	var s := event_to_string(ev)
	if s == "":
		return
	# Remove the same input from any other action/slot to avoid conflicts.
	for a in ACTIONS:
		for k in 2:
			if keys[a][k] == s:
				keys[a][k] = ""
	keys[action][slot] = s
	apply_bindings()
	save_settings()
	changed.emit()


func set_pad_binding(action: String, ev: InputEvent) -> void:
	var s := event_to_string(ev)
	if s == "":
		return
	for a in ACTIONS:
		if pad[a] == s:
			pad[a] = ""
	pad[action] = s
	apply_bindings()
	save_settings()
	changed.emit()


static func event_to_string(ev: InputEvent) -> String:
	if ev is InputEventKey:
		var code: int = ev.physical_keycode if ev.physical_keycode != 0 else ev.keycode
		return "k:%d" % code
	if ev is InputEventMouseButton:
		return "m:%d" % ev.button_index
	if ev is InputEventJoypadButton:
		return "j:%d" % ev.button_index
	return ""


static func event_from_string(s: String) -> InputEvent:
	if s.length() < 3:
		return null
	var v := s.substr(2).to_int()
	match s.substr(0, 2):
		"k:":
			var e := InputEventKey.new()
			e.physical_keycode = v
			return e
		"m:":
			var e := InputEventMouseButton.new()
			e.button_index = v
			return e
		"j:":
			var e := InputEventJoypadButton.new()
			e.button_index = v
			e.device = -1
			return e
	return null


static func binding_label(s: String) -> String:
	if s.length() < 3:
		return "-"
	var v := s.substr(2).to_int()
	match s.substr(0, 2):
		"k:":
			# Physical->logical key mapping isn't available on every display server (e.g. Android).
			var kc := v if OS.has_feature("mobile") or DisplayServer.get_name() == "headless" \
					else DisplayServer.keyboard_get_keycode_from_physical(v)
			var label := OS.get_keycode_string(kc if kc != 0 else v)
			return label if label != "" else "Key %d" % v
		"m:":
			match v:
				MOUSE_BUTTON_LEFT: return "Mouse L"
				MOUSE_BUTTON_RIGHT: return "Mouse R"
				MOUSE_BUTTON_MIDDLE: return "Mouse M"
				MOUSE_BUTTON_XBUTTON1: return "Mouse 4"
				MOUSE_BUTTON_XBUTTON2: return "Mouse 5"
			return "Mouse %d" % v
		"j:":
			var names := {0: "A / Cross", 1: "B / Circle", 2: "X / Square", 3: "Y / Triangle", 4: "Back", 5: "Guide",
				6: "Start", 7: "L3", 8: "R3", 9: "LB / L1", 10: "RB / R1", 11: "D-Up", 12: "D-Down", 13: "D-Left", 14: "D-Right"}
			return names.get(v, "Button %d" % v)
	return "-"
