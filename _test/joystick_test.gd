extends Node
func _ready():
	var root := Control.new()
	root.size = Vector2(1280, 720)
	add_child(root)
	var tc := TouchControls.new()
	tc.size = Vector2(1280, 720)
	root.add_child(tc)
	await get_tree().process_frame
	for fixed in [false, true]:
		Settings.set_value("controls/joystick_fixed", fixed)
		var c := tc.element_center("joystick")
		var r := tc.element_radius("joystick")
		# Touch 20 px right of centre, then drag far to the right.
		var t := InputEventScreenTouch.new(); t.index = 0; t.pressed = true; t.position = c + Vector2(20, 0)
		tc._play_touch(t)
		var d := InputEventScreenDrag.new(); d.index = 0; d.position = c + Vector2(r * 3.0, 0)
		tc._play_drag(d)
		print("fixed=%s origin moved %.0f px, move=(%.2f, %.2f)" % [fixed, tc._stick_origin.distance_to(c), tc.move_vector.x, tc.move_vector.y])
		# A touch far from the stick in the left zone.
		t.pressed = false; tc._play_touch(t)
		var t2 := InputEventScreenTouch.new(); t2.index = 1; t2.pressed = true; t2.position = Vector2(200, 400) if c.distance_to(Vector2(200, 400)) > r * 1.6 else Vector2(420, 300)
		tc._play_touch(t2)
		print("   touch away from stick grabs it: ", tc._stick_finger == 1)
		t2.pressed = false; tc._play_touch(t2)
	Settings.set_value("controls/joystick_fixed", false)
	get_tree().quit()
