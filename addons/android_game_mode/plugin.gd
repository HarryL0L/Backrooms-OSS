@tool
extends EditorPlugin
## Android game detection. The manifest already says isGame="true" and
## appCategory="game" (preset: package/app_category = Game); this adds the
## android.game_mode_config resource that Android 12+ GameManager and the OEM
## game dashboards / boosters built on it look for, so the system offers its
## Performance and Battery game modes for Backrooms-OSS.
## Only takes effect with the Gradle build (gradle_build/use_gradle_build).
## That is OFF: the Gradle-built APK wouldn't install on some older phones
## (Galaxy J7 Prime, Android 8.1: "problem while parsing the package"), so
## the quick export is used; isGame / appCategory=game are still set.

var _exporter: GameModeExporter


func _enter_tree() -> void:
	_exporter = GameModeExporter.new()
	add_export_plugin(_exporter)


func _exit_tree() -> void:
	remove_export_plugin(_exporter)
	_exporter = null


class GameModeExporter extends EditorExportPlugin:
	const XML_DIR := "res://android/build/res/xml"
	const CONFIG := """<?xml version="1.0" encoding="utf-8"?>
<game-mode-config xmlns:android="http://schemas.android.com/apk/res/android"
    android:supportsPerformanceGameMode="true"
    android:supportsBatteryGameMode="true"
    android:allowGameDownscaling="false"
    android:allowGameFpsOverride="true" />
"""

	func _get_name() -> String:
		return "AndroidGameMode"

	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid

	func _export_begin(features: PackedStringArray, _is_debug: bool, _path: String, _flags: int) -> void:
		if not features.has("android"):
			return
		# The resource lives in the Gradle build template's res/ folder.
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(XML_DIR))
		var f := FileAccess.open(XML_DIR + "/game_mode_config.xml", FileAccess.WRITE)
		if f:
			f.store_string(CONFIG)

	func _get_android_manifest_application_element_contents(_platform: EditorExportPlatform, _debug: bool) -> String:
		return "<meta-data android:name=\"android.game_mode_config\" android:resource=\"@xml/game_mode_config\" />\n"
