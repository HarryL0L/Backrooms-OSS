extends Node3D
# Dev harness: the downloaded entity figures side by side (Sam, Harper,
# the Attendant, the crawler), front and side. user://photo/body_*.png
func _ready():
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.albedo_color = Color(0.25, 0.25, 0.24)
	floor.material_override = fm
	add_child(floor)
	var bodies := []
	var specs := [["sam", 1.0, Color.WHITE, "Idle_Standing"], ["jordan", 1.0, Color.WHITE, "Walk_Relaxed"], ["harper", 1.27, Color(0.3, 0.3, 0.32), "Run"], ["crawler", 1.0, Color(0.9, 0.88, 0.85), ""]]
	for i in specs.size():
		var b := EntityBody.new()
		b.who = specs[i][0]
		b.scale = Vector3.ONE * specs[i][1]
		b.tint = specs[i][2]
		b.position = Vector3(-2.4 + i * 1.6, 0, 0)
		add_child(b)
		bodies.append(b)
		if specs[i][3] != "":
			b.play(specs[i][3], 1.3)
	bodies[0].head_yaw = 0.6
	var out := OS.get_user_data_dir() + "/photo/"
	var cam := Camera3D.new(); add_child(cam)
	cam.fov = 40
	for f in 20:
		for b in bodies:
			b.set_env_light(Color(0.75, 0.73, 0.7))
			if b.who == "crawler":
				b.pose_crawl(f * 0.3, 1.0)
			b.update(0.03)
		await get_tree().process_frame
	cam.look_at_from_position(Vector3(-0.8, 1.3, 5.0), Vector3(-0.8, 1.0, 0))
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "body_front.png")
	cam.look_at_from_position(Vector3(4.5, 1.2, 1.5), Vector3(-0.8, 0.9, 0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "body_side.png")
	cam.look_at_from_position(Vector3(2.4, 0.9, 2.6), Vector3(2.4, 0.5, 0))
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out + "body_crawler.png")
	get_tree().quit()
