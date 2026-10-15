extends Node
# Dev harness: times each part of the loading screen (world chunks, sounds)
# on the Potato preset with PS1 style.
var game
var t0 := 0
var step := 0
var chunks_at := -1
var audio_at := -1

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://save.cfg"))
	t0 = Time.get_ticks_msec()
	game = load("res://scenes/main.tscn").instantiate()
	add_child(game)

func _process(_d):
	var ms := Time.get_ticks_msec() - t0
	if step == 0 and game.state == game.State.MENU:
		print("menu at %d ms (sounds ready: %s)" % [ms, game.ambience.is_ready()])
		Settings.apply_preset(0)
		Settings.set_value("graphics/ps1", true)
		Settings.set_value("graphics/auto_quality", false)
		game.new_game()
		t0 = Time.get_ticks_msec()
		step = 1
	elif step == 1:
		if audio_at < 0 and game.ambience.is_ready(): audio_at = ms
		if chunks_at < 0 and game.chunks.is_area_ready(game.player.global_position, 1): chunks_at = ms
		if game.state == game.State.PLAYING:
			print("loading: chunks %d ms, sounds %d ms, playing %d ms" % [chunks_at, audio_at, ms])
			get_tree().quit()
		elif ms > 120000:
			print("STUCK: chunks %d sounds %d loaded %d" % [chunks_at, audio_at, game.chunks.loaded_count()])
			get_tree().quit()
