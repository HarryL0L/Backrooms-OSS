class_name MultiplayerMenu
extends Control
## LAN multiplayer screen: your name and suit number, host a game (new or
## saved), or join one found on the network / by IP. 1-4 players; others can
## join a running game at any time.

signal closed
signal host_requested(continue_saved: bool)
signal join_requested(ip: String)

var net: Net
var _name: LineEdit
var _number: SpinBox
var _host_saved: Button
var _list: VBoxContainer
var _none: Label
var _ip: LineEdit
var _status: Label
var _my_ip: Label


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel.offset_left = 40
	panel.offset_right = -40
	panel.offset_top = 24
	panel.offset_bottom = -24
	add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var v := VBoxContainer.new()
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 12)
	sc.add_child(v)
	var top := HBoxContainer.new()
	v.add_child(top)
	var title := UITheme.title_label("MULTIPLAYER  ·  LAN", 30)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(title)
	var back := Button.new()
	back.text = "Back"
	back.custom_minimum_size = Vector2(140, 52)
	back.pressed.connect(close)
	top.add_child(back)
	_note(v, "Play together on the same Wi-Fi, 1 to 4 players. Friends can join a running game at any time.")

	var you := _row(v, "Your name")
	_name = LineEdit.new()
	_name.custom_minimum_size = Vector2(280, 52)
	_name.max_length = 16
	_name.text = str(Settings.get_value("net/name"))
	you.add_child(_name)
	var num := _row(v, "Suit number (on your back)")
	_number = SpinBox.new()
	_number.min_value = 0
	_number.max_value = 99
	_number.rounded = true
	_number.custom_minimum_size = Vector2(160, 52)
	_number.value = int(Settings.get_value("net/number"))
	num.add_child(_number)
	_note(v, "If someone in the game already has your number, you get the next free one.")

	v.add_child(UITheme.title_label("HOST", 22))
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 12)
	v.add_child(hb)
	var hn := Button.new()
	hn.text = "Host a new game"
	hn.custom_minimum_size = Vector2(300, 56)
	hn.pressed.connect(func() -> void: _save_identity(); host_requested.emit(false))
	hb.add_child(hn)
	_host_saved = Button.new()
	_host_saved.text = "Host your saved game"
	_host_saved.custom_minimum_size = Vector2(300, 56)
	_host_saved.pressed.connect(func() -> void: _save_identity(); host_requested.emit(true))
	hb.add_child(_host_saved)
	_my_ip = Label.new()
	_my_ip.add_theme_color_override("font_color", UITheme.DIM)
	v.add_child(_my_ip)

	v.add_child(UITheme.title_label("JOIN", 22))
	_list = VBoxContainer.new()
	_list.add_theme_constant_override("separation", 8)
	v.add_child(_list)
	_none = Label.new()
	_none.text = "Looking for games on your network..."
	_none.add_theme_color_override("font_color", UITheme.DIM)
	_list.add_child(_none)
	var jr := _row(v, "Or join by the host's IP")
	_ip = LineEdit.new()
	_ip.placeholder_text = "192.168.1.23"
	_ip.custom_minimum_size = Vector2(260, 52)
	jr.add_child(_ip)
	var jb := Button.new()
	jb.text = "Join"
	jb.custom_minimum_size = Vector2(120, 52)
	jb.pressed.connect(func() -> void:
		if _ip.text.strip_edges() != "":
			_save_identity()
			join_requested.emit(_ip.text.strip_edges()))
	jr.add_child(jb)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.add_theme_color_override("font_color", UITheme.ACCENT)
	v.add_child(_status)


func open(has_save: bool) -> void:
	show()
	_host_saved.visible = has_save
	_status.text = ""
	var ips := Net.local_ips()
	_my_ip.text = ("Your address (for joining by IP): " + ", ".join(ips)) if not ips.is_empty() else "Not connected to a network?"
	if net and not net.hosts_changed.is_connected(_refresh_list):
		net.hosts_changed.connect(_refresh_list)
	_refresh_list()


func close() -> void:
	hide()
	closed.emit()


func set_status(t: String) -> void:
	_status.text = t


func _unhandled_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close()


func _save_identity() -> void:
	var n := _name.text.strip_edges()
	Settings.set_value("net/name", n if n != "" else "Player")
	Settings.set_value("net/number", int(_number.value))


func _refresh_list() -> void:
	for c in _list.get_children():
		if c != _none:
			c.queue_free()
	_none.visible = net == null or net.hosts.is_empty()
	if net == null:
		return
	for ip in net.hosts:
		var h: Dictionary = net.hosts[ip]
		var b := Button.new()
		var full: bool = int(h.players) >= int(h.max)
		b.text = "%s's game   ·   %d/%d players   ·   %s%s" % [h.name, h.players, h.max, ip, "   (full)" if full else ""]
		b.disabled = full
		b.custom_minimum_size = Vector2(0, 54)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func() -> void:
			_save_identity()
			join_requested.emit(ip))
		_list.add_child(b)


func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size.x = 300
	h.add_child(l)
	parent.add_child(h)
	return h


func _note(parent: Control, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.add_theme_color_override("font_color", UITheme.DIM)
	l.add_theme_font_size_override("font_size", 17)
	parent.add_child(l)
