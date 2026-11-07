# L.U.C.I.D.

**Light-Unit Calibrated Indirect & Direct lighting**: the lighting system of the
Realistic preset.

The idea: if the maths is right, you get the right picture without spending
anything on it. Every light gives off its real luminous flux. The bake works
out illuminance in lux from that flux. Surfaces reflect it by their measured
albedo. A camera model with real exposure (EV100) and white balance (Kelvin)
turns the luminance into an image. There are no per-place exposure tables,
tint LUTs, ambient floors or extra lights for brightness. When something looks
wrong, the cause is a wrong number, and fixing that number fixes it everywhere.

The aim is the look of a real photograph of the place: troffers clipping to
white, a warm cast from the yellow walls, light falling off with distance, flat
diffuse light. It is not a "UE5 look". The heavy work happens when a chunk
is built, on the world threads. At draw time the cost stays close to plain
textured rendering: one multiply per pixel for exposure, and no extra lights.

## Staged plan

1. **Units, camera, albedo** (done)
   - Real light units, real fixture presets with sources, and Kelvin colour
     from the CIE locus.
   - A physical camera: EV100, phone-like metering and limits, auto white
     balance in Kelvin, AgX.
   - Measured albedos for the Lobby's surfaces.
   - The bake in lux, with radiosity carried to all bounces.
   - The ad-hoc compensations removed.
2. **Relightable bake, bounce accuracy, probe grid** (done, see below)
   - Each lightmapped face keeps its three most important switchable lamps
     apart (direct and bounce), so lamps flicker or die exactly without a
     rebake, their bounce with them.
   - Bounce gathered with subdivided form factors, the open part of the
     hemisphere filled from the outer ring; the far fixtures as an analytic
     tail.
   - A probe grid (ambient cubes at two heights per cell, with occlusion and
     the switchable lamps) lights entities, remote players, props and cars.
3. **Sky, day/night, city scale**
   - Sky visibility (an ambient-occlusion "sky factor") baked per texel, so
     daylight through windows and openings is physical.
   - Day/night as a blend of two or three baked states (sun + sky, dusk,
     night with street lamps and lit windows) under one camera.
   - City-scale light management: street lamps (`sodium_hps_150w`,
     `led_street_100w`), lit windows, cars. Distant lights become emitters
     and a merged far-field term, near ones get baked transfer. The camera's
     limits (ISO, shutter) make night look like night.
4. **Reflections and air**
   - Box-projected cube-map reflections per room or tile for glossy floors and
     water, in the same units.
   - Analytic air: height and density fog lit by the same lights (in-scattering
     from the fixtures' intensity), replacing the halo quads.

## What stage 1 does

| Before (Realistic) | After (L.U.C.I.D.) |
|---|---|
| `LIGHT_POWER` x `LIGHT_REACH`, falloff `w^2 / (1 + 0.42 d^2) x 1.45` | `I0 cos^m(theta_e) cos(theta_r) / d^2` from the fixture's real flux |
| Emission fudge `0.25 + 0.75 cos` | Lambertian troffer (m = 1), bulbs isotropic, high bays m = 1.6 |
| Ambient floor `AMBIENT x 0.4`, fake bounce `0.32 x att x 0.12` | none, bounce only from the radiosity |
| Radiosity x 1.5 (`GI_STRENGTH`), two bounces, x 0.3 in the Unlit Halls | x 1.0, all bounces (geometric tail of bounce 2 / bounce 1) |
| Contact AO squared, on all light | AO on the bounce light only |
| Bounce colours guessed (`ALB_*`) | measured albedos (`Lucid.ALBEDO`) |
| Panels `LIGHT_POWER x 1.5`, dead panels flat grey | lens luminance `I0 / A` (2060 cd/m2 for the Lobby's troffers); dead lens reflects the room |
| Exposure table per biome (`REAL_EXPOSURE`, 1.3 in the Lobby) | metered EV100 with camera limits |
| Tint LUT per biome (`REAL_WHITE`), toe (`REAL_BLACK`), saturation 0.85 | AWB in Kelvin (diagonal gains), veiling glare (3 %), phone profile saturation 1.15 |
| `tonemap_white = 8` (not read by AgX in Godot 4.7) | AgX's own white (16.29) on correctly exposed values |
| Photo textures at ~half albedo (sRGB mean / linear sample) | mean taken in linear: photo detail averages 1 (bug fix, all presets) |
| 6 highlight OmniLights in the Lobby, plus the flashlight's fill light | none in matt biomes (`LUCID_GLINTS`); flashlight fill off |
| Flashlight `5.0`, decay 1.3 | 2000 cd, inverse square, the same exposure |

### Engine units

The baked light, vertex light and emissive panels are stored as luminance
divided by `Lucid.UNIT_NITS` = 153.6 cd/m2. That is the luminance a camera at
EV100 7 (`STORE_EV100`) maps to 1.0. Baked light on a surface is stored as
E / pi (the luminance a white Lambertian surface would have), and the shaders
multiply it by their albedo.

The camera's exposure relative to EV100 7 is applied in the world shaders
(`lucid_exposure`, a global vec4: rgb = 2^(7 - EV100) x the white balance
gains), in `baked_light()` and `lightmap_light()`. The Mobile renderer's buffer
therefore always holds display-range values (it has little headroom) whatever
the real light level. The scene value fed to AgX is
`L x 1 / (1.2 x 2^EV100)`, which is ISO 2720 saturation-based exposure
(Lagarde & de Rousiers 2014). 1.0 means the sensor is saturated.

Godot light nodes use non-physical units, inverse square with attenuation 2,
and `albedo x energy x cos / d^2`. `Lucid.light_node()` converts an
engine-unit intensity to energy and colour under the active camera.

## API (stage 1)

`scripts/render/lucid.gd`, `class_name Lucid`:

- Constants: `UNIT_NITS`, `STORE_EV100`, `METER_K`, `FIXTURES`, `ALBEDO`, the
  `SUN_*` / `SKY_*` / `MOON_*` values, and the `TARGET_*` illuminance targets.
- Photometry:
  - `peak_intensity(fx)` (cd, from flux: I0 = flux (m+1) / 2 pi)
  - `flux(fx)`, `face_luminance(fx)`
  - `illuminance(i0, m, cos_e, cos_r, d)` (lux)
  - `luminance(albedo, lux)`
  - `nits_to_engine`, `lux_to_engine`, `engine_to_lux`
- Colour:
  - `planck_xy(K)` (Kim et al. 2002), `daylight_xy(K)` (CIE D series)
  - `xy_to_rgb(xy)` (linear Rec. 709, Y = 1)
  - `kelvin_rgb(K, daylight, duv)`, `fixture_rgb(fx)`
  - `wb_gains(K)`, `mired(K)`, `lum(c)`
  - `light_engine(fx, llf)` (the bake's light colour), `face_engine(fx, llf)`
    (the panel's emission)
- `Lucid.Camera`:
  - `aperture`, `shutter_min/max`, `iso_min/max`, `compensation`, `headroom`,
    `adapt_rate`, `awb_strength/neutral/min/max`
  - `ev_of(N, t, S)`, `ev_min()`, `ev_max()`, `metered_ev(nits)`
  - `meter(nits, delta, peak)`: program AE, which also sets `shutter` and `iso`
  - `balance(scene_K, delta)`
  - `exposure()`, `shader_exposure()`
- `Lucid.push(cam)`: sets `lucid_exposure` and `lucid_flash`; null means off.
  `Lucid.active` is the current camera. `Lucid.light_node(c)` gives
  `[energy, colour]` for a Godot light.

`scripts/render/lucid_meter.gd`, `class_name LucidMeter`: matrix metering.
Nine centre-weighted spots across the view, one every other frame. For each
spot it takes the ray hit's albedo, the illuminance from the fixtures it can
see (with occlusion rays), the bake's bounce at that point and the
flashlight's beam. `luminance()` is the log average and `peak()` the
brightest spot.

World side:

- `WorldGen.LUCID_FIXTURE`, `LUCID_LLF` (light loss factor), `LUCID_ALBEDO`,
  `LUCID_GLINTS`, `LUCID_GALLERY_SKY`, `lucid_light_near(p, n)`
- `ChunkBuilder.lucid`, `LUCID_RADIUS`, `_shade_lucid()`, `_ao_mix()`,
  `probe(gen, p, n)` (diagnostics: `{lux, direct, indirect}`), and per-chunk
  `probes` (ambient cubes)
- `ChunkManager.light_probe(p, n)`
- `WorldMaterials.LUCID` / `lucid_base(m)`: base colour = albedo / the
  shader's mean darkening
- `EnvironmentFactory.lucid_grade(e)`, `flare_lut(c)`

The bake and the shaders are on when `Settings` turns on Realistic with
lightmaps (`ChunkBuilder.lucid = ChunkBuilder.gi`). The other presets are
unchanged: `lucid_exposure` is (1, 1, 1, 0) and the legacy bake is used.

## What stage 2 does

### Relightable bake

A lamp that flickers or dies takes its bounce light with it. Each
lightmapped face keeps the `ChunkBuilder.SLOTS` = 3 switchable lamps that
give it the most light apart from the rest:

- `lightmap` (RGBA half): rgb = the light with every lamp on, a = the share
  of slot 0 in it.
- `lightmap_seed` (RG8, now filtered): the shares of slots 1 and 2. The
  stage 1 seed texture had the same size, so a texel still costs 10 bytes.
- The face's vertices carry the three slot lamps' indices in CUSTOM0 (unused
  on lightmapped faces before).
- A lamp's share is its direct light plus its own bounce light. In the
  radiosity, each switchable lamp's part of the first bounce is followed per
  probe and through the second bounce, and the further bounces are carried
  on as the same geometric series as the total. The result is kept per cell
  for surfaces facing up, down and sideways (`_cell_sw`).
- Switchable lamps are the flickering ones (`WorldGen.L_FLICKER`). Steady
  lamps, daylight and the far tail are in the steady light. A face lit by
  more than three flickering lamps keeps the weakest ones steady.

At runtime `ChunkManager` keeps the level of every switchable lamp of the
loaded chunks (from `WorldGen.flicker`, or `set_lamp()`) in a 128 x 128 R8
global texture, `lucid_lamps`, updated when the flicker clock ticks (14 Hz),
16 KB. A lamp's texel is (gx & 127, gz & 127). The world shaders read the
three slot levels in the vertex shader (`vertex_light()`, 3 texel fetches
per vertex), and per pixel do one more filtered fetch and a dot product
(`lightmap_light()`):
`L = rgb x (1 - dot(shares, 1 - levels))`. The stage 1 path did up to eight
fetches and four flicker hashes per pixel near a flickering lamp. The panel
of a flickering lamp reads the same level (light_panel.gdshader), so the
lens and the light it gives agree.

Vertex-lit geometry (trim, pipes, props) keeps one slot: the share (direct +
bounce) of its strongest flickering lamp with that lamp's seed, so its bounce
follows too. It follows the flicker clock but not `set_lamp()`.

### Bounce and far light

- Probes at two heights per cell, `LV_INSET` = 0.4 m above the floor and
  below the ceiling, so a ceiling takes the light the floor sends up from
  3 m away, not from mid-height. Surfaces between blend the two.
- The patches within `GI_NEAR` = 3 cells are gathered with subdivided form
  factors (up to 4 x 4 parts when a patch is nearer than its size). The
  stage 1 point-to-patch weight `A cos / (pi d^2 + A)` lost about 16 % of an
  infinite plane, most of the 25 % shortfall.
- The part of each probe's hemisphere that no gathered patch covers (an open
  hall going on beyond 3 cells) is filled as far as an endless floor and
  ceiling would fill it (half each for a face looking sideways, all of it
  for one looking at them) with the radiance of the outermost ring's floors
  and ceilings, and never by more than is missing. In a closed room nothing
  is missing and nothing is added.
- Three gathered bounces, then the rest as a geometric series per probe
  value (third / second). One ratio for all, as in stage 1, over-lit floors
  that get their bounce through the ceiling (second bounce, little third).
- Direct light from beyond the per-texel window (faded out from 7.1 to
  9.5 m) is an analytic tail: the local fixture density (lit fixtures per
  m^2 over the open cells within 4 cells) carried on as a regular grid in
  each of 16 directions, as far as a trace finds that direction open (cut
  off at 7.6 / 12 / 20 m, or to infinity). It is integrated for the
  fixture's cos^m distribution at the floor's and at the ceiling's height
  below the fixtures, and blended in height on walls. It is the exact
  complement of the per-texel window.

### Probe grid for things that move

`ChunkBuilder._light_grid()` bakes, per chunk cell, two probes at 0.5 m and
1.7 m above the floor. Each is an ambient cube (+x -x +y -y +z -z) of all
the light arriving there: direct light from the fixtures the probe can see
(visibility traced like the lightmaps), the far tail and the bounce. Each
probe also keeps its two strongest switchable lamps and their share of each
of its 12 values, and the cell keeps its walls.
`ChunkManager.light_cube(p)` blends the four cells round p (never through a
wall) and the two heights, with the lamps at their current level.
`EntityBody.set_env_cube()` / `HazmatModel.set_env_cube()` pass it to the
figure and hazmat shaders as two mat3 (`env_pos`, `env_neg`), evaluated per
pixel with the world normal (`env_cube_light()`, three selects and three
multiply-adds). Walkers (the Attendant, the crawler) update it every 0.08 s,
remote players every 0.1 s. The Lobby's bins and buckets and the car park's
cars are lit from the grid once their chunk is shown (`LobbyDetails._relight`).
The car shaders now follow the camera's exposure.

## API (stage 2)

- `ChunkBuilder.SLOTS`, `LAMP_GRID`, `lamp_index(gx, gz)`, `GI_NEAR`,
  `LV_INSET`, `TAIL_SECTORS`, `TAIL_REACH`, `FIELD_STEP` (the far tail and
  the bounce are worked out every 4 texels and interpolated), `GRID_Y`.
- `ChunkBuilder.probe(g, p, n, off := [])`: `off` = lamp cells switched off
  the way the runtime does it. `ChunkBuilder.kill_cells`: lamp cells left
  out of the bake (for checking against an exact rebake).
- Chunk build output (Lucid): `grid`, `grid_slots`, `grid_walls`,
  `grid_floor`, `lamps` (gx, gz, seed of each switchable lamp).
- `ChunkManager.current`, `light_cube(p)`, `cube_light(cube, n)`,
  `set_lamp(cell, level)` (a negative level clears it), `lamp_level(idx)`.
  `light_probe(p, n)` still gives the bounce alone (for the meter).
- Shaders (common.gdshaderinc): `lucid_lamps`, `lamp_level(idx)`,
  `vertex_light(custom0, custom1, seed, t)` (replaces `baked_light()` in the
  lightmapped materials' vertex shaders), `env_cube_light(pos, neg, n)`.

## Validation (stage 2)

`_test/lucid_shots.tscn` with `PROBE=1` (seed 1234, the spawn hall). The
expectation is computed in the test on the built level, independently of
the bake: direct light summed over every lit fixture within 30 m that the
point can see (physics rays against the walls), and the bounce by a Monte
Carlo gather (160 cosine-weighted rays, each hit's albedo times its direct
light plus its own bounce from 6 more rays, further bounces as a series).

| Point | Expected direct | Stage 1 direct | Stage 2 direct | Expected bounce (MC) | Stage 1 bounce | Stage 2 bounce |
|---|---|---|---|---|---|---|
| Floor under a troffer | 450 | 418 | 453 | 38 | 26 | 30 |
| Floor between rows | 346 | 315 | 346 | 38 | 23 | 31 |
| Floor between fixtures along a row | 441 | 412 | 452 | 36 | 28 | 26 |
| Desk (0.75 m) under a troffer | 547 | 530 | 555 | 36 | 26 | 30 |
| Vertical at eye height | 71 | 50 | 75 | 45 | 14 | 39 |
| Ceiling between rows | 0 | 0 | 0 | 43 | 29 | 56 |
| Hall wall at 1.5 m | 288 | 280 | 300 | 85 | 98 | 109 |

Direct light is now within 0 to 4 % of the visible-fixture sum (stage 1:
4 to 30 % low). The bounce error went from a mean of 39 % (mostly low) to
21 % (floors low, ceiling and walls high). The ceiling now gets more light
than the carpet sends it alone (0.10 x 385 = 39 lux), from the walls.

A flickering lamp's share (the lamp beside a wall of the Lobby, `LAMP`
lines): with the lamp off as the runtime slots give it, against an exact
rebake with the lamp left out (`kill_cells`):

| Point | On | Off, slots | Off, exact rebake | Off, stage 1 model (bounce stays) |
|---|---|---|---|---|
| Wall beside the lamp | 377 (direct 283, bounce 94) | 115 (57, 57) | 128 (58, 69) | 152 (58, 94) |
| Floor 2 cells away | 495 (371, 124) | 475 (358, 117) | 472 (358, 114) | 482 (358, 124) |
| Ceiling 1 cell away | 94 (0, 94) | 83 (0, 83) | 82 (0, 82) | 94: no change |

The lamp's own bounce is 25 of the wall's 94 lux of bounce (exact rebake);
the slots take out 37, so they over-attribute a little right beside the
lamp, and are within 1-3 lux further away. In stage 1 the bounce stayed on. On screen
(`flicker_on` / `flicker_off`, the flicker clock pinned to two moments with
the lamp on and off), the ceiling round the lamp dims to 0.78-0.85 of its
lit value and the walls further off to 0.88-0.96. In stage 1 they stayed at
1.00.

Cost (lavapipe, 1280 x 720, relative only):

- Bake: 449 / 527 ms/chunk at HEAD, 568 / 601 ms/chunk now (two runs on a
  noisy machine: 1.14 to 1.27x), single thread,
  `_test/bench_build.tscn -- realistic`. The bounce field went from 27 to
  about 105 ms (two probe levels, subdivided links, three gathers with the
  per-lamp shares, the far tail); the texels about 15 % more.
- Memory per chunk: the lightmaps are unchanged at 10 bytes per texel
  (about 208 KB for the average 20 800 texels). Added on the CPU: the probe
  grid, about 19 KB (12 KB of cubes, 6.5 KB of slots). Once: the lamp state
  texture, 16 KB.
- Frames: draw calls unchanged (210-472 per view). Mean frame time over 60
  frames: Lobby views 122.8 ms before, 120.9 ms after; all 13 views 130.8 /
  136.7 ms (the chunk threads share lavapipe's CPU, so the slower bake shows
  in the car park views). Per pixel the Lobby's surfaces do one more
  filtered fetch and a dot product, and no flicker hashes.

The presets other than Realistic render the same (the legacy bake and the
shaders' non-Lucid paths are unchanged; checked with `realistic_shots`
`PRESET=3`).

## Known limits of stage 2

- Only flickering lamps are switchable. A steady lamp that should die at
  runtime has to be baked as switchable (in `_compute_lights`, `lid`).
  Three slots per face: a face lit by four or more flickering lamps keeps
  the weakest steady.
- Vertex-lit geometry keeps one slot and follows the flicker clock, not
  `set_lamp()`.
- A lamp's share of the bounce is kept per cell for three directions and is
  a little too concentrated round the lamp (the further bounces spread
  wider).
- The far tail assumes the local fixture grid goes on, as a fan widening
  with distance. In a straight corridor it adds a little too much (a few
  lux).
- The bounce fill assumes an open hall's floor and ceiling go on. The Monte
  Carlo check shows floors about 20 % low and ceilings and walls about 30 %
  high in the spawn hall.
- The probe grid has a cube per cell at two heights. A figure takes one
  blended cube for its whole body (at 1.1 m). Hall figures, the lining,
  jumpscares, signs and the player's own hands still use the old estimates.
- Cars take the grid's luminance, not its colour (their shader's `light`
  is a scalar).

## Units and reference data

### Fixtures (`Lucid.FIXTURES`)

| Preset | Flux (lm) | CCT (K) | Distribution | Basis |
|---|---|---|---|---|
| `troffer_t8_3lamp` | 6020 (x LLF 0.8 in the Lobby = 4816) | 4100, duv +0.003 | cos (m = 1), 1.22 x 0.61 m | 3 x F32T8 2850 lm [1][2], BF 0.88, 80.1 % fixture efficiency [3] |
| `troffer_led_2x4` | 4000 | 4000 | cos | typical catalogue LED troffer |
| `panel_led_2x2` | 3300 | 5000 | cos | typical 2 x 2 LED panel |
| `troffer_t12_dim` | 1500 | 3000 | cos | 2 x F40T12, aged |
| `highbay_t5ho_6lamp` | 25500 | 3500 | cos^1.6 | 6 x F54T5HO 5000 lm, 85 % |
| `strip_t8_2lamp` | 4500 | 5000 | cos | 2 x F32T8, BF 0.88, 90 % |
| `incandescent_60w` / `_100w` | 800 / 1600 | 2800 / 2850 | isotropic | standard A19 ratings |
| `sodium_hps_150w` | 12000 | 2100 | cos^1.2 | 150 W HPS lamp 16000 lm [4], 75 % luminaire |
| `led_street_100w` | 13000 | 4000 | cos^1.2 | 115-160 lm/W street luminaires [5] |
| `flashlight` | 200 | 6000 | 2000 cd peak, 10 deg hot spot, 30 deg spill | 10 cd/lm, within ANSI FL1 ranges for small lights [6] |
| `skylight` | 3000 cd/m2 opening | 5500 | cos, 1.8 m square | diffuse daylight seen through an opening |

Light loss factor (`LUCID_LLF`): lamp lumen depreciation (about 0.95 at mean
life [2]) times lens dirt. 0.8 for the Backrooms' old troffers.

### Natural light (`Lucid.SUN_*` etc.)

| | Illuminance | CCT | Source |
|---|---|---|---|
| Direct sun, clear, high | 100 000 lux | 5500 K | [7] (100-120 klux) |
| Clear-sky diffuse | 15 000 lux | ~10 000 K | [7] |
| Overcast, dull | 2 000 lux (1 000 - 25 000) | 6500 K | [7] (sources differ widely) |
| Full moon | 0.25 lux (0.1 - 0.3) | 4100 K | [7] |

### Targets (validation)

| Space | Maintained illuminance | Source |
|---|---|---|
| Office | 500 lux (300-500 common) | EN 12464-1 [8] |
| Corridor / circulation | 100 lux | EN 12464-1 |
| Car park traffic lanes | 75 lux | EN 12464-1 |

### Albedos (`Lucid.ALBEDO`, linear mean, CIE Y)

| Surface | Linear RGB | Y | Basis |
|---|---|---|---|
| Aged yellow wallpaper | 0.58, 0.49, 0.14 | 0.47 | mid yellows LRV 26 (mustard) to 74 (cream) [9]; aged mid-yellow ~45-55 |
| Damp tan carpet | 0.14, 0.095, 0.04 | 0.10 | carpet tiles LRV 3-20 for dark and mid shades [10] |
| Mineral-fibre ceiling tile, aged | 0.76, 0.74, 0.65 | 0.74 | Armstrong Fine Fissured LR 0.82-0.85 new [11], yellowed |
| Off-white painted trim | 0.62, 0.59, 0.48 | 0.59 | off-white semi-gloss |
| Concrete | 0.35, 0.35, 0.33 | 0.35 | weathered grey |
| White glazed tile | 0.75, 0.80, 0.82 | 0.79 | |
| Prismatic acrylic lens (unlit) | 0.45 | 0.45 | |

Textures as albedo: the materials' colour uniforms are `source_color` (sRGB,
converted to linear by the engine). Photo textures are `source_color` and are
normalised by their linear mean (fixed in stage 1: this was the sRGB mean,
which halved them).

### Camera (`Lucid.Camera` defaults)

- f/2.0, shutter 1/8000 to 1/30 s (30 fps video), ISO 50-1600, so EV100 runs
  from 2.9 to 16.0. Below EV 2.9 a place is underexposed (dark stays dark).
- Metering: reflected light, K = 12.5 [12]. Log average of nine spots,
  compensation +0.8 EV so the average lands on mid grey (0.18). Highlight
  protection: the brightest spot is kept within 3 stops.
- Adaptation: eased, at most 1.6 stops/s.
- AWB: corrects 50 % of the light's shift from 5500 K, in mired (phones keep
  the warmth of indoor light), clamped to 2800-7500 K. It does not correct
  tint, so fluorescent duv shows as a faint green.

### Colour

- Planckian locus: Kim et al. 2002 cubic spline (1667-25000 K). Checked:
  6500 K gives x = 0.3135.
- Daylight locus: the CIE D-series formula. Checked: 6504 K gives RGB
  (0.999, 1.000, 0.999).
- xy to linear Rec. 709 / sRGB with the standard XYZ to sRGB matrix (D65).

## Validation (stage 1)

`_test/lucid_shots.tscn` (`PROBE=1`, seed 1234, the Lobby's spawn hall, 3 m
ceiling).

- Troffers sit every cell along every second row: 2.4 m x 4.8 m, so 11.5 m2
  per fixture.
- Each gives 4816 lm (6020 x 0.8), so I0 = 4816 / pi = 1533 cd.
- Lumen method: 4816 / 11.52 = 418 lux average delivered on the work plane
  (CU about 1 in an open hall).

| Point | Expected direct (analytic sum, same 9.5 m cut) | Baked direct | Baked total |
|---|---|---|---|
| Floor under a troffer | 416 | 418 | 444 |
| Floor between rows | 317 | 315 | 338 |
| Floor between fixtures along a row | 410 | 412 | 440 |
| Desk height (0.75 m) under a troffer | 525 | 530 | 555 |
| Ceiling between rows | 0 (recessed) | 0 | 29 |

Without the 9.5 m cut, the infinite grid gives 467 / 373 / 462 lux direct.
Bounce adds about 6 % in the open hall, as expected for a dark carpet (ρ 0.10)
under a 0.74 ceiling: 1 / (1 - ρ_floor ρ_ceiling) = 1.08. The total of
440-555 lux is an EN 12464-1 office level.

## Known limits of stage 1

(The first three are fixed in stage 2.)

- The radiosity gathers 2 cells around each probe and samples patches at
  cell centres. Open halls lose some far horizon light, so walls and ceiling
  get somewhat less bounce than an exact solution (the ceiling reads 29 lux
  where a simple open-room estimate gives about 40).
- The direct light is cut at 9.5 m (the chunk margin). That is about 10 % of
  direct light in the largest open halls.
- One flicker seed per texel: a texel lit by two flickering lamps follows
  only its strongest (stage 2 fixes this).
- Props, walkers and signs use the analytic `lucid_light_near`, without
  occlusion. Label3D and sprite decals do not follow the camera's exposure.
- The halos (off in Realistic) are not physically scaled.
- The other biomes have physical presets and look plausible under the new
  camera, but only the Lobby has been checked against reference values.

## Sources

1. Philips F32T8/TL841 ALTO, 2850-2950 lm initial: https://1000bulbs.com/product/4721/F-32T8P84125.html
2. F32T8 841 spec sheet, 2850 lm initial, 2710 lm design mean: https://assets.usesi.com/product-media/specification-sheets/USESI_74967_specification_sheets.pdf
3. Lightolier SPS2GFSVA332 3-lamp T8 lensed troffer, 80.1 % efficiency: https://manualmachine.com/lightolier/specplussps2gfsva232/20947770-specification
4. Satco S3129 150 W HPS, 16000 lm, 2100 K: https://satco.com/products/S3129
5. LED street lights at 4000 K, 100-160 lm/W: https://geyer.gr/en/p/led-street-light-economy-100w-4000k-10000lm-ip65/
6. ANSI/PLATO FL 1 (peak beam intensity, cd/lm ranges): https://www.nitecorelights.com/pages/ansi-nema-fl-1-guide
7. Orders of magnitude (illuminance): https://en.wikipedia.org/wiki/Orders_of_magnitude_(illuminance); full moon 0.1-0.3 lux: https://pmc.ncbi.nlm.nih.gov/articles/PMC9034710/table/tbl1
8. EN 12464-1 in brief (500 lx offices, maintained): https://fagerhult.at/es/knowledge/light-planning/en-12464-1/lighting-of-indoor-workplaces/standard-en-12464-1-in-brief
9. Sherwin-Williams yellows (Butter Up LRV 74, Cut the Mustard LRV 26): https://paintdb.com/brands/sherwin-williams/family/yellow
10. Desso carpet tile LRV sheets (BS 8493): https://www.specifiedby.com/desso/pallas-carpets/Desso_Pallas_Technical_LRV.pdf
11. Armstrong Fine Fissured, LR 0.82 / 0.85: https://www.partssource.com/parts/armstrong/1729A
12. Lagarde & de Rousiers, Moving Frostbite to Physically Based Rendering 3.0 (2014), physical camera and EV100: https://blog.selfshadow.com/publications/s2014-shading-course/frostbite/s2014_pbs_frostbite_slides.pdf
13. Kim et al. 2002 Planckian locus spline: https://en.wikipedia.org/wiki/Planckian_locus
