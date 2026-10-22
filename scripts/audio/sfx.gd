class_name Sfx
extends RefCounted
## The entities' voices and steps: CC0 recordings from Freesound
## (assets/audio/entities, see its LICENSE.md), cut and levelled. Everything
## else the game hears is synthesized (AudioSynth).

const DIR := "res://assets/audio/entities/"

static var _cache := {}


static func get_stream(name: String) -> AudioStream:
	if not _cache.has(name):
		_cache[name] = load(DIR + name + ".ogg")
	return _cache[name]


static func has(name: String) -> bool:
	return _cache.has(name) or ResourceLoader.exists(DIR + name + ".ogg")


## One of name_0 .. name_{count-1}.
static func pick(name: String, count: int) -> AudioStream:
	return get_stream("%s_%d" % [name, randi() % count])
