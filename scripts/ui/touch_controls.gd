class_name TouchControls
extends Control
## On-screen controls for touchscreens: a movement stick on the left (floating,
## or fixed in place with controls/joystick_fixed),
## free look by dragging anywhere else, and action buttons. Every element can
## be moved and resized in the layout editor; the layout is saved in Settings.

signal button_pressed(id: String)
signal selection_changed(id: String)

const BUTTONS := ["jump", "crouch", "sprint", "flashlight", "pause"]
const LABELS := {"jump": "JUMP", "crouch": "CROUCH", "sprint": "RUN", "flashlight": "LIGHT", "pause": "II"}
const BASE_RADIUS := 46.0
const STICK_RADIUS := 78.0

var player: Player
var editing := false
var selected := ""
var move_vector := Vector2.ZERO
var sprint_held := false

var _stick_finger := -1
var _stick_origin := Vector2.ZERO
var _stick_pos := Vector2.ZERO
var _look_finger := -1
var _btn_fingers := {}       # finger -> button id
var _drag_finger := -1
var _drag_offset := Vector2.ZERO
var _font: Font
var _forbidden: Array[Control] = []


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = get_theme_default_font()
	Settings.changed.connect(queue_redraw)
	resized.connect(queue_redraw)


## Controls that should receive touches instead of this layer (e.g. the editor panel).
func add_exclusion(c: Control) -> void:
	_forbidden.append(c)


func element_center(id: String) -> Vector2:
	var e: Dictionary = Settings.touch_layout.get(id, Settings.TOUCH_DEFAULTS[id])
	return e.pos * size


func element_scale(id: String) -> float:
	var e: Dictionary = Settings.touch_layout.get(id, Settings.TOUCH_DEFAULTS[id])
	return e.scale


func element_radius(id: String) -> float:
	return (STICK_RADIUS if id == "joystick" else BASE_RADIUS) * element_scale(id)


func reset_state() -> void:
	_stick_finger = -1
	_look_finger = -1
	_btn_fingers.clear()
	_drag_finger = -1
	move_vector = Vector2.ZERO
	sprint_held = false
	queue_redraw()


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			for c in _forbidden:
				if c.is_visible_in_tree() and c.get_global_rect().has_point(event.position):
					return
		if editing:
			_edit_touch(event)
		else:
			_play_touch(event)
	elif event is InputEventScreenDrag:
		if editing:
			if event.index == _drag_finger and selected != "":
				var p: Vector2 = (event.position + _drag_offset) / size
				p = p.clamp(Vector2(0.03, 0.05), Vector2(0.97, 0.95))
				Settings.touch_layout[selected] = {"pos": p, "scale": element_scale(selected)}
				queue_redraw()
		else:
			_play_drag(event)


func _hit_button(pos: Vector2) -> String:
	for id in BUTTONS:
		if pos.distance_to(element_center(id)) <= element_radius(id) * 1.15:
			return id
	return ""


func _play_touch(event: InputEventScreenTouch) -> void:
	var idx: int = event.index
	if event.pressed:
		var b := _hit_button(event.position)
		if b != "":
			_btn_fingers[idx] = b
			_press(b)
			get_viewport().set_input_as_handled()
			queue_redraw()
			return
		var stick_c := element_center("joystick")
		var fixed: bool = Settings.get_value("controls/joystick_fixed")
		var zone := not fixed and event.position.x < size.x * 0.42 and event.position.y > size.y * 0.3
		var near := event.position.distance_to(stick_c) < element_radius("joystick") * (1.3 if fixed else 1.5)
		if _stick_finger < 0 and (zone or near):
			_stick_finger = idx
			# Fixed: the stick stays put and the touch already moves the knob.
			_stick_origin = stick_c if fixed else event.position
			_stick_pos = event.position
			move_vector = Vector2.ZERO
			if fixed:
				_update_stick()
		elif _look_finger < 0:
			_look_finger = idx
		get_viewport().set_input_as_handled()
		queue_redraw()
	else:
		_btn_fingers.erase(idx)
		if idx == _stick_finger:
			_stick_finger = -1
			move_vector = Vector2.ZERO
		if idx == _look_finger:
			_look_finger = -1
		queue_redraw()


func _press(b: String) -> void:
	if b == "sprint":
		sprint_held = not sprint_held
	button_pressed.emit(b)


func _play_drag(event: InputEventScreenDrag) -> void:
	if event.index == _stick_finger:
		_stick_pos = event.position
		_update_stick()
	elif event.index == _look_finger and player != null:
		var s: float = 0.0048 * Settings.get_value("controls/touch_sens")
		player.add_look(event.relative.x * s, event.relative.y * s)


func _update_stick() -> void:
	var r := element_radius("joystick")
	var d: Vector2 = _stick_pos - _stick_origin
	if d.length() > r:
		if Settings.get_value("controls/joystick_fixed"):
			d = d.normalized() * r          # the knob stops at the rim
		else:
			# Floating: the stick base follows the finger so it never "runs out".
			_stick_origin = _stick_pos - d.normalized() * r
			d = _stick_pos - _stick_origin
	var v := d / r
	var l := v.length()
	move_vector = Vector2.ZERO if l < 0.12 else v.normalized() * clampf((l - 0.12) / 0.88, 0.0, 1.0)
	queue_redraw()


func _process(_delta: float) -> void:
	# Running stops when the stick is released.
	if not editing and _stick_finger < 0 and sprint_held:
		sprint_held = false
		queue_redraw()


func _edit_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		var best := ""
		var best_d := INF
		for id in ["joystick"] + BUTTONS:
			var d := event.position.distance_to(element_center(id))
			if d < element_radius(id) * 1.3 and d < best_d:
				best = id
				best_d = d
		if best != "":
			selected = best
			_drag_finger = event.index
			_drag_offset = element_center(best) - event.position
			selection_changed.emit(selected)
			get_viewport().set_input_as_handled()
			queue_redraw()
	elif event.index == _drag_finger:
		_drag_finger = -1
		Settings.save_settings()


func set_selected_scale(s: float) -> void:
	if selected == "":
		return
	var e: Dictionary = Settings.touch_layout.get(selected, Settings.TOUCH_DEFAULTS[selected])
	Settings.touch_layout[selected] = {"pos": e.pos, "scale": clampf(s, 0.5, 2.0)}
	Settings.save_settings()
	queue_redraw()


func _draw() -> void:
	var a: float = Settings.get_value("controls/touch_opacity")
	var white := Color(1, 1, 1, a)
	var fill := Color(0.08, 0.08, 0.06, a * 0.45)
	# Joystick.
	var r := element_radius("joystick")
	var base := _stick_origin if _stick_finger >= 0 else element_center("joystick")
	draw_circle(base, r, fill)
	draw_arc(base, r, 0, TAU, 48, white * Color(1, 1, 1, 0.8), 2.0, true)
	var knob := base + move_vector * r
	draw_circle(knob, r * 0.42, Color(1, 1, 1, a * 0.55))
	if editing:
		_draw_edit_frame("joystick", base, r)
	# Buttons.
	for id in BUTTONS:
		var c := element_center(id)
		var br := element_radius(id)
		var active: bool = _btn_fingers.values().has(id) or (id == "sprint" and sprint_held) \
				or (id == "crouch" and player != null and player.crouching) \
				or (id == "flashlight" and player != null and player.flashlight_on)
		draw_circle(c, br, Color(0.95, 0.85, 0.45, a * 0.5) if active else fill)
		draw_arc(c, br, 0, TAU, 40, white, 2.0, true)
		var label: String = LABELS[id]
		var fs := int(15 * element_scale(id)) if id != "pause" else int(20 * element_scale(id))
		var ts := _font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs)
		draw_string(_font, c + Vector2(-ts.x * 0.5, ts.y * 0.3), label, HORIZONTAL_ALIGNMENT_CENTER, -1, fs, white)
		if editing:
			_draw_edit_frame(id, c, br)


func _draw_edit_frame(id: String, c: Vector2, r: float) -> void:
	var col := Color(1.0, 0.85, 0.3, 0.95) if id == selected else Color(1, 1, 1, 0.4)
	draw_rect(Rect2(c - Vector2(r, r) * 1.12, Vector2(r, r) * 2.24), col, false, 2.0)
