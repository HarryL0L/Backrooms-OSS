class_name Menus
extends RefCounted
## Small factory for the main and pause menus.


static func button(text: String, cb: Callable, min_w := 340) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_w, 58)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.pressed.connect(cb)
	return b


## Main menu shown over a slowly drifting view of the Lobby.
static func main_menu(game: Node) -> Control:
	var root := Control.new()
	root.name = "MainMenu"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var grad := TextureRect.new()
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.88))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	grad.texture = gt
	grad.stretch_mode = TextureRect.STRETCH_SCALE
	grad.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	grad.offset_right = 760
	grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(grad)
	var m := MarginContainer.new()
	m.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	m.offset_right = 620
	m.add_theme_constant_override("margin_left", 64)
	m.add_theme_constant_override("margin_top", 48)
	m.add_theme_constant_override("margin_bottom", 40)
	root.add_child(m)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	v.alignment = BoxContainer.ALIGNMENT_CENTER
	m.add_child(v)
	var title := UITheme.title_label("BACKROOMS", 76)
	title.add_theme_color_override("font_color", Color(0.95, 0.88, 0.56))
	title.add_theme_constant_override("outline_size", 0)
	v.add_child(title)
	var sub := UITheme.title_label("O P E N   S O U R C E   ·   v" + str(ProjectSettings.get_setting("application/config/version")), 18)
	sub.add_theme_color_override("font_color", UITheme.DIM)
	v.add_child(sub)
	var quote := UITheme.title_label("\"If you're not careful and you noclip out of reality\nin the wrong areas, you'll end up in the Backrooms.\"", 17)
	quote.add_theme_color_override("font_color", Color(0.75, 0.72, 0.6, 0.8))
	v.add_child(quote)
	var spacer := Control.new()
	spacer.custom_minimum_size.y = 18
	v.add_child(spacer)
	var cont := button("Continue", game.continue_game)
	cont.name = "Continue"
	v.add_child(cont)
	v.add_child(button("Enter the Backrooms", game.new_game))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	var seed_edit := LineEdit.new()
	seed_edit.name = "SeedEdit"
	seed_edit.placeholder_text = "Seed (blank = random)"
	seed_edit.custom_minimum_size = Vector2(340, 52)
	seed_row.add_child(seed_edit)
	v.add_child(seed_row)
	v.add_child(button("Multiplayer (LAN)", game.open_multiplayer))
	v.add_child(button("Settings", game.open_settings))
	if not OS.has_feature("web"):
		v.add_child(button("Quit", func() -> void: game.get_tree().quit()))
	var foot := UITheme.title_label("Free software (MIT). No monsters... yet.", 15)
	foot.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	v.add_child(foot)
	return root


static func pause_menu(game: Node) -> Control:
	var root := Control.new()
	root.name = "PauseMenu"
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(shade)
	var c := CenterContainer.new()
	c.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(c)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 12)
	c.add_child(v)
	var t := UITheme.title_label("PAUSED", 44)
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	v.add_child(t)
	var info := UITheme.title_label("", 17)
	info.name = "Info"
	info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	info.add_theme_color_override("font_color", UITheme.DIM)
	v.add_child(info)
	var resume := button("Resume", game.resume)
	resume.name = "Resume"
	v.add_child(resume)
	v.add_child(button("Settings", game.open_settings))
	v.add_child(button("Save & exit to menu", game.exit_to_menu))
	return root
