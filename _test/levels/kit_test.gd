extends Node
# Dev harness: the worked example Blender kit (assets/levels/_example, made
# by tools/blender/levels/_example.py) loaded with SideLevel.load_kit, its
# light groups switched: both on, group 0 off, group 1 dim red. Photos in
# user://levels/kit/. (It stands in for "atrium" for the run.)
var game
var out := OS.get_user_data_dir() + "/levels/kit"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.make_dir_recursive_absolute(out)
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	SideLevels.level_script("atrium")
	SideLevels._scripts["atrium"] = load("res://_test/levels/kit_level.gd")
	SideLevels._info.erase("atrium")
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)
	_run()


func _shot(name: String) -> void:
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s/%s.png" % [out, name])
	print("shot ", name, "  draw calls ", Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))


func _run() -> void:
	while game.state != game.State.MENU:
		await get_tree().process_frame
	Settings.set_value("graphics/auto_quality", false)
	game.new_game()
	while game.state != game.State.PLAYING:
		await get_tree().process_frame
	await game.debug_enter_side("atrium")
	while game._transition:
		await get_tree().process_frame
	game.hud._title_t = 0.001
	var lv: SideLevel = game.side
	print("level ", lv.get_script().resource_path, " spots ", lv.spots.keys())
	var p: Player = game.player
	p.controls_enabled = false
	await get_tree().create_timer(3.0).timeout
	await _shot("both_on")
	lv.set_light_group(0, Color.WHITE, 0.0)
	await _shot("group0_off")
	lv.set_light_group(0)
	lv.set_light_group(1, Color(1.0, 0.25, 0.2), 0.4)
	await _shot("group1_red")
	lv.set_light_group(0, Color.WHITE, 0.0)
	lv.set_light_group(1, Color.WHITE, 0.0)
	p.set_flashlight(true)
	await _shot("dark_flashlight")
	game.queue_free()          # (first: quitting with it running can crash on the way out)
	for i in 4:
		await get_tree().process_frame
	get_tree().quit()
