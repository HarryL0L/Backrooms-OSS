extends Node3D
# Dev harness: the FigureModel kinds side by side (copies, attendant,
# crawler), front and side views.
func _ready():
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(20, 20); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.albedo_color = Color(0.25, 0.25, 0.24)
	floor.material_override = fm
	add_child(floor)
	var figs := []
	var specs := [[FigureModel.COPY, 1, 1.0], [FigureModel.COPY, 7, 1.0], [FigureModel.ATTENDANT, 0, 1.27], [FigureModel.CRAWLER, 0, 1.0]]
	for i in specs.size():
		var f := FigureModel.new()
		f.kind = specs[i][0]
		f.style_seed = specs[i][1]
		f.size = specs[i][2]
		f.position = Vector3(-2.4 + i * 1.6, 0, 0)
		add_child(f)
		figs.append(f)
	await get_tree().process_frame
	for f in figs:
		f.set_env_light(Color(0.75, 0.73, 0.7))
	figs[0].pose_idle(0.0)
	figs[1].pose_walk(0.8, 1.0, 0.0)
	figs[2].pose_walk(1.2, 1.0, 0.6)
	figs[3].pose_crawl(0.6, 1.0)
	var cam := Camera3D.new(); add_child(cam)
	var out := OS.get_user_data_dir() + "/photo/"
	cam.fov = 40
	cam.look_at_from_position(Vector3(-0.8, 1.3, 4.6), Vector3(-0.8, 1.1, 0))
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(out + "fig_front.png")
	cam.look_at_from_position(Vector3(2.4 + 2.4, 0.9, 0.6), Vector3(2.4, 0.45, 0))
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(out + "fig_side.png")
	cam.look_at_from_position(Vector3(0.8, 1.6, 1.3), Vector3(0.8, 1.75, 0))
	await get_tree().create_timer(0.6).timeout
	get_viewport().get_texture().get_image().save_png(out + "fig_face.png")
	get_tree().quit()
