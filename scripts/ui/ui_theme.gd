class_name UITheme
extends RefCounted
## Builds the game's UI theme in code: muted, slightly translucent panels with
## a sickly fluorescent accent, large touch-friendly buttons.

const ACCENT := Color(0.93, 0.84, 0.47)
const TEXT := Color(0.92, 0.9, 0.82)
const DIM := Color(0.62, 0.6, 0.52)


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 22
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Roboto Condensed", "DejaVu Sans Condensed", "Arial Narrow", "sans-serif"])
	font.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
	t.default_font = font

	var normal := _box(Color(0.06, 0.055, 0.04, 0.72), Color(1, 1, 1, 0.08))
	var hover := _box(Color(0.16, 0.14, 0.08, 0.85), Color(ACCENT, 0.5))
	var pressed := _box(Color(0.3, 0.26, 0.12, 0.9), ACCENT)
	var focus := _box(Color(0, 0, 0, 0), ACCENT)
	focus.draw_center = false
	for type in ["Button", "OptionButton", "CheckButton"]:
		t.set_stylebox("normal", type, normal)
		t.set_stylebox("hover", type, hover)
		t.set_stylebox("pressed", type, pressed)
		t.set_stylebox("hover_pressed", type, pressed)
		t.set_stylebox("focus", type, focus)
		t.set_stylebox("disabled", type, _box(Color(0.05, 0.05, 0.05, 0.5), Color(1, 1, 1, 0.03)))
		t.set_color("font_color", type, TEXT)
		t.set_color("font_hover_color", type, Color.WHITE)
		t.set_color("font_pressed_color", type, Color.WHITE)
		t.set_color("font_focus_color", type, Color.WHITE)
		t.set_color("font_disabled_color", type, Color(1, 1, 1, 0.3))
	t.set_stylebox("panel", "Panel", _box(Color(0.03, 0.03, 0.025, 0.86), Color(1, 1, 1, 0.06)))
	t.set_stylebox("panel", "PanelContainer", _box(Color(0.03, 0.03, 0.025, 0.86), Color(1, 1, 1, 0.06), 18))
	t.set_stylebox("panel", "TabContainer", _box(Color(0.03, 0.03, 0.025, 0.0), Color(0, 0, 0, 0), 8))
	t.set_stylebox("tab_selected", "TabContainer", _box(Color(0.25, 0.22, 0.1, 0.9), ACCENT, 10))
	t.set_stylebox("tab_unselected", "TabContainer", _box(Color(0.06, 0.055, 0.04, 0.7), Color(1, 1, 1, 0.05), 10))
	t.set_stylebox("tab_hovered", "TabContainer", _box(Color(0.14, 0.12, 0.07, 0.85), Color(ACCENT, 0.4), 10))
	t.set_stylebox("tab_focus", "TabContainer", focus)
	t.set_color("font_selected_color", "TabContainer", Color.WHITE)
	t.set_color("font_unselected_color", "TabContainer", DIM)
	t.set_color("font_hovered_color", "TabContainer", TEXT)
	t.set_font_size("font_size", "TabContainer", 20)
	t.set_color("font_color", "Label", TEXT)
	t.set_stylebox("normal", "LineEdit", _box(Color(0.02, 0.02, 0.02, 0.8), Color(1, 1, 1, 0.1)))
	t.set_stylebox("focus", "LineEdit", _box(Color(0.02, 0.02, 0.02, 0.8), ACCENT))
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("font_placeholder_color", "LineEdit", Color(1, 1, 1, 0.3))
	var track := _box(Color(1, 1, 1, 0.12), Color(0, 0, 0, 0), 4)
	track.content_margin_top = 4
	track.content_margin_bottom = 4
	t.set_stylebox("slider", "HSlider", track)
	var area := _box(Color(ACCENT, 0.7), Color(0, 0, 0, 0), 4)
	t.set_stylebox("grabber_area", "HSlider", area)
	t.set_stylebox("grabber_area_highlight", "HSlider", area)
	var grabber := _circle(14, Color.WHITE)
	t.set_icon("grabber", "HSlider", grabber)
	t.set_icon("grabber_highlight", "HSlider", _circle(14, ACCENT))
	t.set_stylebox("panel", "PopupMenu", _box(Color(0.05, 0.05, 0.04, 0.97), Color(1, 1, 1, 0.1), 8))
	t.set_font_size("font_size", "PopupMenu", 22)
	t.set_constant("v_separation", "PopupMenu", 14)
	return t


static func _box(bg: Color, border: Color, margin := 14) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(2)
	s.set_corner_radius_all(4)
	s.content_margin_left = margin + 6
	s.content_margin_right = margin + 6
	s.content_margin_top = margin * 0.6
	s.content_margin_bottom = margin * 0.6
	return s


static func _circle(size: int, col: Color) -> ImageTexture:
	var img := Image.create(size * 2, size * 2, false, Image.FORMAT_RGBA8)
	for y in size * 2:
		for x in size * 2:
			var d := Vector2(x + 0.5 - size, y + 0.5 - size).length()
			img.set_pixel(x, y, Color(col, clampf(size - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


static func title_label(text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", TEXT)
	return l
