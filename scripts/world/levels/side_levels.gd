class_name SideLevels
extends RefCounted
## The side levels: their ids, working titles, the line under the title, the
## level a chain goes on to, and where their ways in stand in the world.
##
## A level's own script (scripts/world/levels/<id>_level.gd, extending
## SideLevel) is the only file its author touches: anything here can be
## overridden from it with constants of the same names, read by info():
##     const NAME := "Level 2.1 - The Crawlspace"
##     const INTRO := "Hot air. Sheet metal. No room to turn round."
##     const NEXT := ""                 # where its exits lead ("" = back)
##     const ENTRANCES := [ ...specs, see below... ]
## Until a level's script exists (or while it fails to load) create() makes
## a placeholder (PlaceholderLevel): a plain lit room with the level's name
## on the wall and an exit, so the whole game runs while levels are built.
##
## Entrance specs (one Dictionary per way in; LevelEntrances places them):
##   "in": "backrooms" (default) or "mall" (the Dead Mall)
##   "kind": "wall" (set into a wall) or "floor" (a hatch)    [backrooms]
##   "biomes": [WorldGen.LOBBY, ...] or names ["LOBBY", ...]   [backrooms]
##   "floors": [lowest, highest] floor index (default any)     [backrooms]
##   "chance": per 48 m x 48 m region where it can go (0.35)   [backrooms]
##   "pool": true: a floor hatch at the bottom of a pool      [backrooms]
##   "slot": a place in the mall (LevelEntrances.MALL_SLOTS)   [mall]
##   "look": "door", "double", "vent", "hatch", "lift", "stairs"
##   "sign": text on a plate over it; "label": the Use prompt
##   "script": your own LevelEntrance subclass (look and ride)

const DIR := "res://scripts/world/levels/"
const LEVELS := {
	"crawlspace": {"name": "Level 2.1 - The Crawlspace", "intro": "Hot air. Sheet metal. No room to turn round.",
		"entrances": [{"kind": "wall", "biomes": ["LOBBY", "PIPES"], "look": "vent", "chance": 0.4}]},
	"filing": {"name": "Level 1.1 - The Stacks", "intro": "Records nobody will ever ask for. The shelves move on their own.",
		"entrances": [{"kind": "wall", "biomes": ["CONCRETE"], "look": "door", "sign": "ARCHIVE",
			"label": "Open the archive door", "chance": 0.45}]},
	"reservoir": {"name": "Level 37.1 - The Drained Reservoir", "intro": "Columns like a cathedral. Far below, the floor.",
		"entrances": [{"kind": "floor", "biomes": ["POOL"], "look": "hatch", "label": "Climb down the drain hatch",
			"chance": 0.4}]},
	"stairwell": {"name": "Level 4.1 - The Endless Stairwell", "intro": "B2. B3. B4. It doesn't stop.", "next": "flooded",
		"entrances": [{"kind": "wall", "biomes": ["GARAGE"], "floors": [-1, -1], "look": "door", "sign": "STAIRS",
			"label": "Take the service stairs", "chance": 0.45}]},
	"flooded": {"name": "Level 4.2 - The Flooded Basement", "intro": "Cold water to the waist. Something moves it.",
		"entrances": []},
	"office": {"name": "Level 6.1 - The Dimming Floor", "intro": "The lights go out behind you. Don't look back.",
		"entrances": [{"kind": "wall", "biomes": ["LOBBY", "CONCRETE"], "floors": [1, 99], "look": "door",
			"sign": "SUITE 400", "label": "Open the office door", "chance": 0.45}]},
	"atrium": {"name": "Level 8.1 - The Atrium", "intro": "Sixty metres of nothing overhead. Your steps come back late.",
		"entrances": [{"kind": "wall", "biomes": ["LOBBY"], "look": "double", "label": "Push the doors", "chance": 0.3}]},
	"ward": {"name": "Level 9.1 - Ward 0", "intro": "A monitor still beeps. Nobody's in the bed.",
		"entrances": [{"in": "mall", "slot": "dept_back_n", "look": "lift", "sign": "WARD 0",
			"label": "Call the hospital lift"}]},
	"surveillance": {"name": "Level 5.1 - The Surveillance Floor", "intro": "Every corridor on a screen. One of them has someone in it.",
		"entrances": [{"kind": "wall", "biomes": ["GARAGE"], "floors": [-99, -1], "look": "door", "sign": "SECURITY",
			"label": "Open the security office", "chance": 0.35}]},
	"metro": {"name": "Level 7.1 - The Metro Station", "intro": "The boards say a train is due. They always say that.",
		"entrances": [{"kind": "wall", "biomes": ["GARAGE"], "floors": [-99, -1], "look": "stairs", "sign": "METRO",
			"chance": 0.35},
			{"in": "mall", "slot": "dept_back_s", "look": "stairs", "sign": "METRO"}]},
}
const BIOME_IDS := {"LOBBY": WorldGen.LOBBY, "POOL": WorldGen.POOL, "CONCRETE": WorldGen.CONCRETE,
		"DARK": WorldGen.DARK, "PIPES": WorldGen.PIPES, "GARAGE": WorldGen.GARAGE}

static var _info := {}
static var _scripts := {}


static func ids() -> Array:
	return LEVELS.keys()


static func exists(id: String) -> bool:
	return LEVELS.has(id)


static func script_path(id: String) -> String:
	return DIR + id + "_level.gd"


## The level's script, or null while it doesn't exist (or doesn't load, or
## doesn't extend SideLevel).
static func level_script(id: String) -> GDScript:
	if _scripts.has(id):
		return _scripts[id]
	var s: GDScript = null
	var path := script_path(id)
	if ResourceLoader.exists(path):
		s = load(path) as GDScript
		if s and not (s.can_instantiate() and _extends_side_level(s)):
			push_warning("SideLevels: %s doesn't load as a SideLevel; using the placeholder" % path)
			s = null
	_scripts[id] = s
	return s


static func _extends_side_level(s: Script) -> bool:
	var b := s
	while b:
		if b.get_global_name() == &"SideLevel":
			return true
		b = b.get_base_script()
	return false


## Everything about a level: name, intro, next, entrances (normalised
## specs), "built" (its own script exists). The level script's constants
## NAME, INTRO, NEXT and ENTRANCES win over the table above.
static func info(id: String) -> Dictionary:
	if _info.has(id):
		return _info[id]
	var base: Dictionary = LEVELS.get(id, {})
	var d := {"id": id, "name": base.get("name", "Level ? - " + id.capitalize()), "intro": base.get("intro", ""),
			"next": base.get("next", ""), "entrances": base.get("entrances", []), "built": false}
	var s := level_script(id)
	if s:
		d.built = true
		var c := s.get_script_constant_map()
		for k in [["NAME", "name"], ["INTRO", "intro"], ["NEXT", "next"], ["ENTRANCES", "entrances"]]:
			if c.has(k[0]):
				d[k[1]] = c[k[0]]
	var specs := []
	for e in d.entrances:
		specs.append(_normalise(e))
	d.entrances = specs
	_info[id] = d
	return d


static func _normalise(e: Dictionary) -> Dictionary:
	var d := {"in": "backrooms", "kind": "wall", "biomes": [], "floors": [-999, 999], "chance": 0.35,
			"pool": false, "slot": "", "look": "door", "sign": "", "label": "", "script": ""}
	d.merge(e, true)
	var b := []
	for x in d.biomes:
		b.append(BIOME_IDS.get(x, -1) if x is String else int(x))
	d.biomes = b
	if d.kind == "floor" and not e.has("look"):
		d.look = "hatch"
	return d


## Every way in: [[level id, spec], ...].
static func entrances() -> Array:
	var out := []
	for id in LEVELS:
		for e in info(id).entrances:
			out.append([id, e])
	return out


## Makes the level `id` (its own script, or the placeholder).
static func create(id: String) -> SideLevel:
	var s := level_script(id)
	if s:
		var inst: Object = s.new()
		if inst is SideLevel:
			return inst
		push_warning("SideLevels: %s isn't a SideLevel" % script_path(id))
	var p := PlaceholderLevel.new()
	p.info = info(id)
	return p
