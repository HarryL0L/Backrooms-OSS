extends Node3D
# Dev harness: the car shadow decal alone on a grey floor.
func _ready():
	var floor := MeshInstance3D.new()
	var pm := PlaneMesh.new(); pm.size = Vector2(12, 12); floor.mesh = pm
	var fm := StandardMaterial3D.new(); fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; fm.albedo_color = Color(0.6, 0.6, 0.6)
	floor.material_override = fm
	add_child(floor)
	var root := Node3D.new(); add_child(root)
	LobbyDetails._car_shadow(root, Transform3D(Basis(Vector3.UP, 0.3), Vector3.ZERO), Vector3(0.4, 0.4, 0.0))
	var cam := Camera3D.new(); add_child(cam)
	cam.look_at_from_position(Vector3(4, 7, 4), Vector3.ZERO)
	await get_tree().create_timer(1.0).timeout
	get_viewport().get_texture().get_image().save_png(OS.get_user_data_dir() + "/photo/shadow_probe.png")
	get_tree().quit()
