# Side levels: the author's guide

Side levels are self-contained real-world places (a duct network, an
archive, a metro station...) reached from entrances in the Backrooms (or the
Dead Mall, or another side level's exit) and left by their own exits. Each
level is built by one author, **in its own files only**. You never edit
`game.gd`, `player.gd`, `side_levels.gd` or anyone else's level: everything a
level needs is in the API below. If something truly is missing, say so in
your report instead of patching shared code.

The framework:

| File | What |
| --- | --- |
| `scripts/world/levels/side_level.gd` | `SideLevel`, the base class every level extends |
| `scripts/world/levels/side_levels.gd` | `SideLevels`, the registry (ids, titles, entrance specs) |
| `scripts/world/levels/level_entrance.gd` | `LevelEntrance`, entrances and exits (door, vent, hatch...) |
| `scripts/world/levels/level_entrances.gd` | `LevelEntrances`, places entrances in the world |
| `scripts/world/levels/placeholder_level.gd` | `PlaceholderLevel`, stands in until your level exists; also a worked example |
| `shaders/level_lit.gdshader(inc)`, `level_lit_cutout.gdshader` | the shared surface shader (lightmap, light groups, textures) |
| `tools/blender/level_kit.py` | Blender helpers: build, unwrap, bake, export GLB |
| `tools/blender/levels/_example.py` | worked Blender example (output in `assets/levels/_example/`) |
| `_test/levels/level_shots.tscn` | screenshot / performance / film harness |
| `_test/levels/side_flow_test.tscn` | flow test (enter, save, continue, exit, chain, caught, fall) |
| `_test/levels/kit_test.tscn` | loads the example kit and switches its light groups |

## Ids

`crawlspace`, `filing`, `reservoir`, `stairwell`, `flooded`, `office`,
`atrium`, `ward`, `surveillance`, `metro`. Until
`scripts/world/levels/<id>_level.gd` exists (or while it fails to parse),
the game uses the placeholder room, so the game always runs.

## Files per level

```
scripts/world/levels/<id>_level.gd      your level (extends SideLevel); any helpers
                                        as scripts/world/levels/<id>_*.gd
assets/levels/<id>/                     everything else:
    <kit>.glb                           Blender exports (level_kit.py)
    lightmaps/<kit>.png, <kit>_groups.png
    textures/<material>_diff.jpg, _nor.jpg, _rough.jpg (or _arm.jpg)
    audio/*.ogg
    LICENSE.md                          every third-party asset: name, author,
                                        source page URL, licence (CC0)
    SPEC.md                             what the level is, its layout, its
                                        rules, its exits, what's left to do
tools/blender/levels/<id>.py            the Blender script that makes the kits
```

Keep `.import` files of your assets (they are not ignored under
`assets/levels/`): they carry VRAM compression and mipmap settings.

## Licensing: CC0 only

Every asset you did not make yourself must be **CC0** (public domain), and
you must check the licence **on the asset's own page**, not on a list. Good
sources: Poly Haven (textures, HDRIs, models), ambientCG (textures), Kenney
(models, sounds), Freesound **only items marked CC0** (not CC-BY, not
"Sampling+"). Record each one in `assets/levels/<id>/LICENSE.md` with its
name, author, the page URL and "CC0 1.0". No copyrighted material of any
kind, nothing from games, films or web series (no Kane Pixels content), no
"free for personal use", no AI-scraped packs. Procedural content (code,
`AudioSynth`, Blender scripts) needs no entry.

## The level class

A minimal level (procedural boxes, no Blender kit):

```gdscript
extends SideLevel
## The Crawlspace: ... (what it is, in plain prose)

const NAME := "Level 2.1 - The Crawlspace"     # optional: override the registry
const INTRO := "Hot air. Sheet metal. No room to turn round."
const NEXT := ""                                 # where exits lead by default

const O := Vector3(0.0, LEVEL_Y, 0.0)


func build(p_seed: int) -> void:
	seed_value = p_seed
	var metal := flat_material({"color": Color(0.5, 0.5, 0.52), "roughness": 0.4, "metallic": 0.6},
			Color(0.2, 0.2, 0.2))
	add_box(Vector3(2, 0.1, 30), O + Vector3(0, -0.05, 0), metal)        # floor
	add_box(Vector3(2, 0.1, 30), O + Vector3(0, 0.8, 0), metal)          # ceiling
	add_box(Vector3(0.1, 0.8, 30), O + Vector3(-1, 0.4, 0), metal)       # walls
	add_box(Vector3(0.1, 0.8, 30), O + Vector3(1, 0.4, 0), metal)
	add_exit(Transform3D(Basis(Vector3.UP, PI), O + Vector3(0, 0, 14.9)), "vent", "", {"walk_in": true})
	add_loop("draught", Vector3.INF, -16.0)
	environment = make_environment({"fog_density": 0.05})


func on_enter() -> void:
	player.force_crawl = true          # (the game clears it when you leave)


func arrival() -> Transform3D:
	return Transform3D(Basis(Vector3.UP, PI), O + Vector3(0, 0, -14))   # facing +Z


func wants_flashlight() -> bool:
	return true


func surface_at(_p: Vector3) -> int:
	return Player.SURF_METAL


func camera_far() -> float:
	return 40.0


func shots() -> Array:
	return [{"name": "arrival", "transform": arrival(), "crawl": true}]
```

Coordinates: every level is built round `Vector3(0, SideLevel.LEVEL_Y, 0)`
(`LEVEL_Y = -8000`; the Field is at -2000, the Dead Mall at -4000). Only one
side level exists at a time, so they all share it. Stay within a few km.

### What the game does with your level

1. `SideLevels.create(id)` makes it, the game sets `player`, `id`, `low`
   (`_setup`), adds it to the tree and calls `build(seed)` behind the fade.
2. On a saved game: `load_state(d)` with what your `save_state()` returned.
3. The Backrooms are hidden, `environment` goes on the world, the camera's
   far plane is `camera_far()`, the echo is `reverb()`; you're put at
   `arrival()` (or the saved position) and the torch comes on if
   `wants_flashlight()`. Then `on_enter()`; then `warm_materials()` are
   compiled behind the fade, and the title card shows NAME / INTRO.
4. While you're there the player asks `surface_at`, `water_level_at`,
   `albedo_at`; remote players and the radar ask `light_at`.
5. Leaving: `on_leave()`, then the level is freed. The game resets the
   player's `force_crawl`, `can_climb`, camera offsets, far plane and cull
   mask, the light groups and the environment.

### Exact API (`SideLevel`)

Signals (emit them through the helpers):
- `exit_entered(to: String)`: "" = back into the Backrooms somewhere else;
  a level id = straight on into that level (a chain, e.g. stairwell ->
  flooded). Exits made with `add_exit` emit it for you.
- `player_caught(lines: Array, how: Dictionary)`: use `catch_player()`.
- `player_fell(lines: Array)`: use `fall()`, or set `fall_kill`.

Constants: `LEVEL_Y := -8000.0`, `FEED_LAYER := 1 << 19` (render layer 20),
`SURFACE` (defaults for surface dictionaries).

Variables: `player: Player`, `environment: Environment`, `id: String`,
`low: bool` (Potato/Low preset), `seed_value: int`, `fall_kill: float`
(metres of free fall that kill; 0 off), `fall_lines: Array`,
`underwater_tint: Color` (alpha 0 = none), `spots: Dictionary` (kit
`spot_*` empties -> world Transform3D), `low_view_range: float` (hide kit
meshes beyond this on low presets), `rumble: float` (steady camera shake).

Virtuals (all optional; defaults in brackets):
- `build(p_seed: int) -> void` [an empty environment]
- `arrival() -> Transform3D` [origin, facing -Z]; feet position, you face -basis.z
- `open_exit() -> void` (await ok) [plays the used exit's `enter()`]
- `light_at(p: Vector3) -> Color` [grey 0.5]
- `surface_at(p: Vector3) -> int` [`Player.SURF_CONCRETE`]: one of
  `SURF_CARPET, SURF_TILE, SURF_CONCRETE, SURF_WATER, SURF_GRASS, SURF_METAL`
  (water is chosen for you while wading)
- `water_level_at(p: Vector3) -> float` [-INF]: water surface height; more
  than 0.1 m of it and you wade (slower the deeper, full drag by 0.6 m;
  splashing steps); camera below it -> `underwater_tint`
- `albedo_at(p: Vector3, n: Vector3) -> Color` (the torch's bounce light)
- `camera_far() -> float` [150]; `wants_flashlight() -> bool` [false]
- `reverb() -> Dictionary` [{room 0.7, damp 0.5, wet 0.3}]
- `warm_materials() -> Array[Material]` [everything made by load_kit /
  flat_material; append your own shaders' materials]
- `shots() -> Array` [arrival and behind]: `[{name, transform, crawl?,
  flashlight?, wait?}]` for the harness
- `film() -> void` (await) [a slow look round]: the harness's movie mode
- `on_enter()`, `on_leave()`
- `save_state() -> Dictionary` / `load_state(d: Dictionary)`: plain values only

Events:
- `catch_player(lines: Array, how := {})`: the game plays the catch, shows
  `lines` on black, puts you in the Backrooms somewhere else. `how`:
  `"scare"`: a Walker (see `make_walker`) that rushes you as a jumpscare,
  plus jumpscare opts `"sound"` (Sfx name), `"from"`, `"to"` (metres from
  your eyes to its head), `"time"`; without one, a jolt and a fade. Use it
  for being crushed (filing), hit by the train (metro), a gurney (ward).
- `fall(lines := [])`: a deadly fall (reservoir). With `fall_kill = 20.0`
  the level does it by itself after 20 m in the air.

Helpers:
- `load_kit(glb: String, lightmap := "", textures_dir := "", surfaces := {}, groups := "", at := Vector3(0, LEVEL_Y, 0)) -> Node3D`:
  instantiates a level_kit GLB and gives each Blender material (by name,
  `.001` suffixes ignored) the level shader with the bake. `surfaces[name]`
  may set any of `color, roughness, metallic, specular, emit, group, uv
  (0 mesh UV, 1 world-projected), scale, normal_depth, cutout, texture`.
  Textures are looked up as `<textures_dir>/<name>_diff|_nor|_rough|_arm
  .jpg|.png`. Names starting with `glass` become see-through glass.
  `spot_*` empties land in `spots` (`spots_named(prefix)` lists repeats);
  `-colonly` meshes become collision.
- `flat_material(surf := {}, light := Color(0.5, 0.5, 0.5), group_mix := Vector4.ZERO, textures_dir := "", tex_name := "") -> ShaderMaterial`:
  the level shader without a bake, for moving or procedural parts (shelving
  carriages, the train, gurneys). `group_mix` = how much each light group
  lights it.
- `add_box(size: Vector3, pos: Vector3, mat: Material, collide := true, parent: Node3D = null) -> MeshInstance3D`
- `add_exit(xf: Transform3D, look := "door", to := "", opts := {}) -> LevelEntrance`:
  look is `door, double, vent, hatch, lift, stairs` or `none` (an invisible
  walk-in trigger for an exit you model yourself). `xf` faces +Z (the side
  you stand on), origin at floor level on the wall face. opts: `label`,
  `sign`, `walk_in`, `size`, `script` (your own LevelEntrance subclass).
- `add_loop(sound: Variant, at := Vector3.INF, volume_db := -12.0, opts := {}) -> Node`:
  a res:// path, an AudioStream, or an AudioSynth name (`hum`, `wind`,
  `drip`, `draught`); 3D at `at`. opts: `unit_size, max_distance, pitch, bus, filter`.
- `shake(strength: float, time: float)`: a jolt of camera shake (0.02 a
  thud, 0.06 a train); `rumble` for a steady one.
- `set_light_group(i: int, color := Color.WHITE, intensity := 1.0)`: light
  group 0..3 of the group bake (0 off, 1 as baked). Global, cheap; call it
  every frame for a flicker (office, ward).
- `make_environment(opts := {}) -> Environment`: follows the graphics
  settings. opts: `background, fog, fog_density, exposure, glow, saturation, contrast`.
- `add_figure(xf: Transform3D, who := "tall", tint := Color.WHITE, size := 1.0) -> EntityBody`
- `make_walker(who := "tall", size := 1.0, tint := Color.WHITE) -> Walker`

Player things a level may use (`player: Player`): `force_crawl` (keep the
player prone: crawlspace), `crawling` (read only), `can_climb` (false: no
vaulting railings), `teleport(pos, yaw, pitch := 0.0)`, `ride(eyes:
PackedVector3Array, to_yaw, time, done: Callable, to_pitch := -0.08)` for
scripted climbs (ladders), `busy()`, `set_flashlight(on)`, `camera`,
`in_water()`, `water_depth()`, `controls_enabled`. Crawling happens by
itself too: crouch into a gap lower than a crouch (about 1 m) and you go
flat (0.6 m capsule, eyes at 0.38 m, 0.75 m/s) and get up by yourself once
there's room; you can never stand up into a ceiling. Touch controls work
the same (the CROUCH button).

### Registry and entrances

`SideLevels.LEVELS` holds each id's working title, intro line, chain `next`
and entrance specs. **Don't edit it**: put constants of the same names in
your level script and they win (`SideLevels.info(id)` reads them):

```gdscript
const NAME := "Level 4.1 - The Endless Stairwell"
const INTRO := "B2. B3. B4. It doesn't stop."
const NEXT := "flooded"
const ENTRANCES := [{"kind": "wall", "biomes": ["GARAGE"], "floors": [-1, -1], "look": "door",
		"sign": "STAIRS", "label": "Take the service stairs", "chance": 0.45}]
```

Entrance spec keys: `in` (`"backrooms"` or `"mall"`), `kind` (`"wall"` or
`"floor"`), `biomes` (`LOBBY, POOL, CONCRETE, DARK, PIPES, GARAGE`; GARAGE
only exists on floors -1 and below), `floors` ([lowest, highest]), `chance`
(per region of 20 x 20 cells, about 48 m square), `pool` (a hatch at the bottom of a pool), `slot`
(Dead Mall: `dept_back_n`, `dept_back_s`, `dept_side_n`, `dept_side_s`),
`look`, `sign`, `label`, `script`.

Your own look or ride: extend `LevelEntrance` (in
`scripts/world/levels/<id>_entrance.gd`), override `_build()` (keep a dark
opening made with `make_void()` so the ride ends in darkness) and/or
`enter(p: Player)` (await `open()` then `ride(p, eyes, time, pitch)`), and
name it in the spec's or add_exit's `"script"`. Entrances reach the game
through the group `LevelEntrance.HOST_GROUP` (`use_level_entrance(e)`);
exits tell their level (`_exit_activated`). No hard references.

### The interact prompt

The game's Use prompt shows anything in group `"usable"` that has
`use_targets(p: Player) -> Array` (`[[id: String, world_pos: Vector3,
label: String], ...]`) and `use(id: String, p: Player) -> String`. Entrances
and exits already are. For your own usables (a ladder, a switch, a monitor)
add a Node3D to the group with those two methods (see
`scripts/world/parked_car.gd`, `scripts/world/mall_lift.gd`).

### Figures

`add_figure(xf, "tall")` gives an `EntityBody` (the CC0 MakeHuman body in
`assets/entities`, already licensed: see its LICENSE.md): `"tall"` walks and
runs (`body.move(speed)` picks the clip, `body.play(clip, speed)`), `"crawler"`
you pose (`pose_crawl(phase, amount)`). Call `body.update(delta)` every
frame and `body.set_env_light(light_at(pos))` when it moves between lights.
For one that catches you, `make_walker()` and pass it as `how.scare`.

### Feed-only objects (render layers)

The player's camera never draws `SideLevel.FEED_LAYER` (layer 20; the game
clears that bit of its cull mask in side levels and puts it back after).
For something only the security monitors show: `node.layers =
SideLevel.FEED_LAYER`; for feed cameras use a `SubViewport` with
`world_3d = get_world_3d()` (shared world) and a `Camera3D` whose
`cull_mask = 1 | SideLevel.FEED_LAYER`. Keep feeds low-res (e.g. 256 x 144)
and update them at a low rate (`render_target_update_mode` UPDATE_ONCE on a
timer) for phones. Don't use other layer bits without saying so in SPEC.md.

## Light: baking with level_kit.py

Build the level's geometry in a Blender script (`tools/blender/levels/<id>.py`,
start from `_example.py`), run with
`/tmp/claude-0/bpyenv/bin/python tools/blender/levels/<id>.py [--fast]`
(`--fast` = 512 px, few samples, for iterating). It writes
`assets/levels/<id>/<kit>.glb` and `lightmaps/<kit>.png` (+ `_groups.png`).

- `K.reset()`, `K.material(name, color, rough=, emit=, group=, metal=)`:
  materials by name; the same names are the keys of `load_kit`'s
  `surfaces` and texture files.
- `kit = K.Kit(name)`; geometry on `kit.b`: `box(size, loc, m, rot=,
  bevel=)`, `cyl`, `tube`, `quad`, `oquad`, `wall(a, b, z0, z1, thick, m)`,
  `slab(x0, y0, x1, y1, z, thick, m)`, `place`; `K.room(b, lo, hi, floor,
  wall, ceiling)`. Normals face into the room.
- Lights: `K.point_light(kit, loc, watts, color=, radius=, group=)`,
  `K.area_light(...)`, `K.spot_light(...)`; `kit.sky = (colour, strength)`
  for daylight.
- `kit.col(size, loc, rz=)` collision boxes, `kit.spot("spot_x", loc, rz)`
  named places, `kit.export(out, lm=1024, samples=96)`, `kit.preview(...)`.
- Light groups: give a light (and its lamp material) `group=0..3`. The
  colour bake holds only lights with no group (always on); each group is
  baked alone into one channel of `_groups.png`. In Godot pass the groups
  file to `load_kit(..., groups)` and give the lamp surfaces the same
  `"group"`, then `set_light_group(i, colour, intensity)` at run time.
- Real-time lights (OmniLight3D / SpotLight3D you add in Godot: a train's
  windows, a swinging lamp) add on top of the bake. Keep them few.
- A big level: several kits (one lightmap each, 1024 px max), so each part
  keeps enough lightmap texels; hide far kits yourself if it helps.

Coordinates: Godot (x, y, z) = Blender (x, z, -y). Godot's level origin is
`at` in `load_kit` (default `(0, LEVEL_Y, 0)`).

## Performance budget (phones, mobile renderer)

Measured by the harness in the worst view of the level:
- <= 150k triangles (primitives) in view, <= 150 draw calls
- <= 6 real-time lights in view, no real-time shadows
- textures <= 1024 px, VRAM compressed, with mipmaps (the harness warns)
- <= 8 MB of assets per level (`du -sh assets/levels/<id>`)
- On `low` (Potato/Low): fewer lights, shorter `camera_far()`, thicker fog,
  `low_view_range` for kits.
- Audio: ogg, mono for 3D sounds.

## Screenshots, stats and film: the harness

Godot is shared with other agents: **wrap every Godot run in the lock**
`flock /tmp/claude-0/godot.lock ...`, and import new assets first:

```
G=/tmp/claude-0/godot/Godot_v4.7-stable_linux.x86_64
flock /tmp/claude-0/godot.lock timeout 600 $G --headless --path . --import
flock /tmp/claude-0/godot.lock timeout 600 env VK_ICD_FILENAMES=/usr/share/vulkan/icd.d/lvp_icd.json \
    xvfb-run -a $G --path . --rendering-method mobile --rendering-driver vulkan --resolution 1280x720 \
    res://_test/levels/level_shots.tscn -- <id> [--movie] [--preset N] [--set key=value] [--script res://path.gd]
```

It boots the game, starts a new game (seed 1234), enters `<id>`
(`game.debug_enter_side`), warms up, then stands at each of your `shots()`
with the real player camera and saves
`user://levels/<id>/<name>.png` (on this machine
`~/.local/share/godot/app_userdata/Backrooms-OSS/levels/<id>/`). Per shot it
prints a line like

```
shot arrival  fps 9.0  draw calls 45  primitives 848  objects 45  video mem 162.8 MB  -> .../arrival.png
```

(FPS under llvmpipe means nothing; draw calls and primitives do.) It ends
with `level_shots: done, N script/shader errors` and exits 1 if N > 0.
Look at the PNGs (Read them). `--preset 0..5` tries a graphics preset
(0 Potato), `--set graphics/ps1=true` any setting (put back after),
`--script` runs another script as `<id>` (a variant you're trying).

Film: `--movie` plays your `film()` after the shots. Record it with Godot's
movie maker, put before `res://`: `--write-movie /path/out.avi --fixed-fps 30`
(slow under llvmpipe; keep films short, under a minute).

The flow test, `res://_test/levels/side_flow_test.tscn`, must keep passing
(it always uses the placeholders, whatever is built, so it tests the
framework): it prints PASS / FAIL lines and
`side_flow_test: N failed, M script/shader errors`. Trust that line, not
the exit code: after the Dead Mall has been built Godot can crash while
quitting ("Aborted", exit 134; the stock `_test/mall_ride_test.tscn` does
it too).

## Saves and multiplayer

Saving inside a level stores its id, your position, stance and
`save_state()`. Continue loads the Backrooms behind it, rebuilds your level
with the same seed, calls `load_state()`, and puts you back. Two players who
took the same entrance get the same `seed_value`, so build deterministically
from it (`RandomNumberGenerator` seeded with `seed_value`, never `randi()`
for layout). Other players are shown only when they are in the same level
from the same entrance; their brightness comes from your `light_at`.

## Checklist before you hand in

- Only your files changed (`git status`).
- `assets/levels/<id>/LICENSE.md` lists every third-party asset (CC0, URL).
- `assets/levels/<id>/SPEC.md` describes the level.
- Harness runs with 0 errors; shots look right; budget met in the worst shot.
- `side_flow_test` still passes.
