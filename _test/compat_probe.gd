extends Node3D
# Dev harness: a hazmat model with env_light set, and a car-style instance
# uniform quad, to check per-instance uniforms on the current renderer.
func _ready():
	var m := HazmatModel.new()
	add_child(m)
	await get_tree().process_frame
	m.set_env_light(Color(0.6, 0.6, 0.6))
	m.pose_idle(0.0)
	var cam := Camera3D.new(); add_child(cam)
	cam.look_at_from_position(Vector3(0, 1.0, 3.0), Vector3(0, 0.9, 0))
	await get_tree().create_timer(1.0).timeout
	print("renderer ", RenderingServer.get_current_rendering_method())
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/photo/compat_%s.png" % RenderingServer.get_current_rendering_method())
	get_tree().quit()
