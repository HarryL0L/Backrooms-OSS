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
3. **Sky, day/night, city scale** (done for the city levels, see below;
   testbed: Level 12.1, The Blue Hour, `night_city`)
   - Sky visibility (an ambient-occlusion "sky factor") baked per texel, so
     daylight through windows and openings is physical.
   - Day/night as a blend of two or three baked states (sun + sky, dusk,
     night with street lamps and lit windows) under one camera.
   - City-scale light management: street lamps (`sodium_hps_150w`,
     `led_street_100w`), lit windows, cars. Distant lights become emitters
     and a merged far-field term, near ones get baked transfer. The camera's
     limits (ISO, shutter) make night look like night.
4. **Reflections and air** (done, see below)
   - One physically based specular (GGX, Smith, Schlick with real F0),
     taken from the diffuse.
   - Analytic reflections of the emitters the level knows (panels, street
     heads, signals), streaking toward the viewer as on a real polished
     floor or wet street.
   - Box-projected reflection probes, captured once per street segment or
     mall section, in the same units.
   - Wetness: darker (Lekner & Dorf), smoother, puddles: the Blue Hour
     after rain.
   - Air: the haze lit by the nearest street heads (single scattering).

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

## What stage 3 does

Stage 3 lights a city at night: a light-polluted sky and the moon, streets
of real lamps, thousands of lit windows, a city to the horizon, on a phone.
It is built for side levels (`scripts/render/lucid_city.gd`,
`shaders/lucid_*`) and tested in The Blue Hour (`night_city`); the
Backrooms' own bake is unchanged.

### The night sky and the moon (`Lucid.STATES`, `Lucid.sky_nits`)

The sky is a luminance model in cd/m2: a zenith value, a horizon excess
fading with elevation as exp(-h / h0), and for twilight a glow toward an
azimuth (cos^4). Each part has a colour temperature (daylight locus for
the sky, Planckian for lamp glow). The same model runs in GDScript (bake,
meter) and in the shaders (`lucid_sky_nits`, from the globals
`lucid_sky_zenith/horizon/glow/glow_dir` that `LucidCity.push_sky()` sets).

| State | Zenith | Horizon | Sky on the ground | Direct | Windows lit | Haze |
| --- | --- | --- | --- | --- | --- | --- |
| night | 0.040 cd/m2, 11000 K (16.1 mag/arcsec2, ~230 x the natural 174 ucd/m2) | 0.24 cd/m2, 4300 K, h0 = 0.22 rad | 0.18 lux horizontal, 0.14 vertical | moon 0.18 lux, 4100 K, 20 deg up at azimuth 255 | 30 % | 3.3e-4 /m (12 km) |
| dusk (sun -5 deg) | 1.1 cd/m2, 15000 K | 3.0 cd/m2 + 5.0 glow in the west, 2600 K | 4.9 lux, 2.8 vertical | none | 20 % | 1.8e-4 /m |

Megacity centres measure 15-17 mag/arcsec2 at the zenith (Falchi et al.
2016); the horizon of a light dome is several times brighter and warmer
(the long path through aerosol, low sodium sources). The moon is a
directional light of 0.18 lux and a disc of 0.18 / 6.4e-5 sr = 2800 cd/m2
(the light and the disc agree), with the aerosols' aureole (5 % of its
light within a few degrees). Stars brighter than magnitude 3.5 are point
sources of their real illuminance (2.54e-6 lux x 10^(-0.4 m)) dimmed by
the air mass; at 16 mag/arcsec2 only a few show, as in a city.

### Where the blue comes from

Nothing is tinted. Three real effects make the night read blue:

1. The sky's own colour: light-pollution and moonlight scattered by
   molecules (Rayleigh) is a ~11000 K sky; the lamps' light that reaches
   the ground is 2100 K (sodium) and 4000 K (LED), the windows 2900-4000 K.
2. The camera's auto white balance is set by what it sees: the meter's
   nine spots give a colour (the lit surfaces' light, the sky, the city),
   converted to a CCT (McCamy 1992) and half corrected from 5500 K as in
   stage 1. Under the lamps and windows it settles at 3400-4400 K, so
   sodium stays orange, LED near white, and the 11000 K sky and everything
   lit only by it go blue.
3. The eye's night shift (`Camera.night_vision`, 0.5 in the city): in the
   mesopic range (5 to 0.005 cd/m2, CIE 191:2010) the rods take over, so
   each pixel's colour moves towards its scotopic luminance, Y (1.33 (1 +
   (Y + Z) / X) - 1.68) / 2.576 (Jensen et al. 2000), in the blue grey of
   chromaticity (0.25, 0.25) (Thompson, Shirley & Ferwerda 2002), by
   log-linear steps over the range (`Lucid.mesopic`, `lucid_mesopic`). It
   works on absolute luminance before the exposure, so dark sky and moonlit
   roofs shift, lamp pools (0.5-3 cd/m2) barely do, and red lamps go dark.

### The night camera (`Lucid.night_camera()`)

A phone's main camera in its night video mode: f/1.8, ISO up to 12800,
four 1/30 s frames merged (1/8 s effective): EV100 from -2.3 (the sensor
saturates at 0.24 cd/m2) to 15.7. It aims at -0.5 EV from mid grey instead
of +0.8 (phones aim lower in low light so a night looks like night and the
lamp pools hold), and keeps its brightest spot within 2.5 stops. The meter
(`night_city_level.gd`, `_meter`) reads one of nine spots a frame: a
physics ray, then the surface's albedo times the lamps' light there (the
same cos^m law, unoccluded) plus the probe grid's natural light; the sky
model where the ray escapes; the city's mean where it meets the backdrop.
Lit windows are light sources and are not metered (they clip, as in a
photo). Measured in the harness: EV 0.8-1.8 on the roof, 2.4-3.6 in the
street, 4.5 at the foot of the stair under a bulb.

### Sky visibility and the per-vertex bake (`LucidCity.bake`)

City surfaces are tessellated (a vertex every 1-1.5 m where lamps light
them, coarser up high) and baked offline (`tools/lucid/city_bake.tscn`,
headless, ~85 s for the crossing's 46 000 vertices) against the level's
colliders in a physics space. Per vertex, in engine units (E / pi):

- Every lamp within 70 m: E = I0 cos^m(theta_e) cos(theta_r) / d^2 with a
  shadow ray (steel grating, railings and poles cast none).
- A cosine-weighted gather of 64 rays (Hammersley, rotated per vertex):
  an escaped ray adds the state's sky radiance in its direction, a hit adds
  what that surface sends back: its albedo times the lamps' light there
  (the lamp layer's bounce), its share of sky and moon (the natural layer)
  and the mean luminance of its lit windows or shop lights (from the
  collider's metadata: lit share x glazed share x window luminance).
- The sky visibility: the cosine-weighted open share of the hemisphere
  (open streets 0.45-0.6, the alley 0.2-0.35, under the stair less).
- The moon with a shadow ray (night state).
- The gather is denoised over the vertices of the same surface within
  1.6 m facing the same way; direct light and the moon (the sharp shadows)
  are not.

The result is an ArrayMesh with custom arrays (`lucid_city.gdshader`):

| Array | Format | Holds |
| --- | --- | --- |
| CUSTOM0 | RGBA half | rgb all lamps (direct + bounce), a sky visibility |
| CUSTOM1 | RGBA half | rgb natural light of state A (night), a slot share 0 |
| CUSTOM2 | RGBA half | rgb natural light of state B (dusk), a slot share 1 |
| CUSTOM3 | RGBA8 | slot lamp indices (3), a slot share 2 |

`L = lamps x (1 - dot(shares, 1 - levels)) x lamp level + mix(A, B, blend)`
(vertex shader; 32 lamp levels in a uniform array). The sky visibility
also weights the sky's reflection on damp asphalt and in unlit windows.
Probe grids (`LucidCity.bake_probes`: the crossing every 4 m and the roof
every 3 m, 1.2 m up, the mean of six directions per layer) light moving
things (`light_at`) and the meter.

### Day/night as baked states

A tile stores its lamps once and its natural light per state; a blend
factor (global `lucid_sky.x`) mixes two of them in the vertex shader and
everything else follows it: the sky globals, the windows' lit share, the
backdrop's far field, the haze, the probes, the meter. The lamp layer's
level (`lucid_sky.z`) turns the street lamps off for a day state. Two
states are baked now (night, dusk); a third (day: sun and clear sky)
would be one more pair of arrays and one more `Lucid.STATES` entry. The
level stays at night; `_test/levels/night_city_dusk.gd` (or
the level script's static `force_blend = 1.0`) shows dusk.

### City-scale light management

- Lamps near you are baked geometry with lens faces of their real
  luminance (36 000 cd/m2 for the LED heads, 42 000 for sodium); the
  nearest four are also SpotLights whose `light()` adds only the specular
  highlight on baked surfaces (the diffuse is in the bake), with energy
  from `Lucid.light_node_cam()` under the level's camera.
- Every other lamp, beacon and signal is a point source in a MultiMesh
  (`lucid_points.gdshader`): a camera-facing gaussian disc no smaller than
  a pixel carrying the source's real intensity toward the camera (street
  heads I0 (cos^1.2 + 2 % for a flat LED lens, 12 % for a sodium drop
  lens), so a lamp seen from above is mostly dark), attenuated by the air.
  Bright ones get the lens's veiling glare: 3 % of the light reaching the
  camera spread as 1 / (1 + (theta / 0.004)^2)^1.5, so halos have the
  energy they really carry. Signals and beacons run on the level's clock.
- The ground beyond the crossing (`lucid_ground.gdshader`) finds the lamps
  that light a point by arithmetic (the grid is regular): the four nearest
  pairs of avenue heads and the block's three pairs of street heads, each
  with its real I0 and cos^m, plus half the sky and the shops' spill.
- Buildings are instanced unit boxes (`lucid_blocks.gdshader`) in 16
  MultiMeshes (8 directions x near / far, so most are culled), lit by the
  state's far field: sky on roofs and walls, the lamp rows' vertical
  illuminance on the lower floors (worked out from the real lamp rows:
  `_facade_light`), the moon on the faces turned to it.
- Windows (`lucid_windows.gdshaderinc`): a grid of storeys and bays (the
  openings sized in metres: homes 1.2 x 1.5 m on 0.9 m sills, masonry 1.1
  m wide up to 2.0 m tall, curtain wall vision glass from the floor to a
  2.9 m ceiling; SPEC.md's audit), lit
  by hash with real luminances (25 cd/m2 office floors, 12 homes, 40 for a
  closed shop's night lights, Lucid.FIXTURES), with frames, sills and sash
  bars and a room behind the glass (a ceiling lamp, furniture against the
  light, blinds or curtains; dark rooms show their blinds and curtains lit
  by the street through the pane, a hall light further in). Glass mirrors
  by Fresnel (a pane is two faces: F0 0.08; solar-control curtain walls
  about three times that): on the near facades the reflection probe of the
  street it faces and the street heads and signals (stage 4), elsewhere
  the sky and, below the horizon, the city. Resolved windows blend their
  edges in the camera's output (compressed, weighted, expanded), so a
  window fifty times brighter than its wall keeps no stair-stepped edge.
  When a window falls under about a pixel the facade switches to cells of
  2, 4, 8 windows lit with the same probability: the same mean, the speckle
  of a photo, no shimmer; where it does so only one way (a facade edge on,
  or seen straight up) the windows blend to their mean along it, as whole
  long cells lit or not would draw stripes.
- Air: Koschmieder (transmittance exp(-sigma d), the rest the horizon's
  luminance as airlight) in every city shader (`lucid_finish`); no halo
  quads.

### Validation (stage 3)

Baked direct light against the analytic sum (`Lucid.FIXTURES`, the lamps
of the grid, no occlusion in these open spots):

| Point | Analytic | Baked |
| --- | --- | --- |
| Road under an avenue LED head (7.5, 0, 17.5) | 41.0 + 3.4 (opposite head) + 0.4 (neighbours) = 44.8 lux | 45.8 |
| Road under a street sodium head (25, 0, 5.1) | 52.5 + 6.9 + 0.4 = 59.8 lux (+ avenue heads) | 61.8 |
| Crossing centre | 8.1 lux (lamps) | 8.1 |

Natural light (night) at street level is 4.7-7.6 lux, almost all of it
the lit windows and shops round the crossing (the sky gives 0.18 lux); the
sky visibility is 0.61 at the crossing's centre, 0.44-0.47 along the
avenue, 0.32-0.35 on the sidewalks, lower in the alley.

Cost (lavapipe, 1280 x 720, Realistic): 23-29 draw calls and 119k-140k
primitives in the harness's views (the Lobby: 210-472 calls); four real
lights and the moon, no shadows; the bake is 1.3 MB of vertex data, 56 KB
of probes.

### Known limits of stage 3

- The meter's surface light ignores occlusion (it uses the lamp law, not
  the bake); windows are not metered.
- The gather sees lit windows as a facade's mean luminance, not window by
  window; the backdrop buildings in it are boxes within 380 m.
- Only the crossing is baked; the backdrop is analytic (no shadows, no
  bounce between buildings, no lamp light on the far facades' upper parts).
- One gather per vertex at 64 rays, denoised: bright small sources near a
  vertex (a shopfront) can leave soft blotches.
- The probes are the mean of six directions (no direction for moving
  things yet).
- (Found in stage 4) Colours passed to the city's vec3 uniforms arrived
  converted from sRGB, see "Stage 3 fixes" below.

## API (stage 3)

- `Lucid`: `STATES`, `sky_dir(alt, az)`, `sky_nits(state, dir)`,
  `sky_uniforms(state)`, `sky_illuminance(state, n)`, `mag_arcsec2_nits(m)`,
  `SKY_NATURAL_NITS`, `MOON_DISC_SR`, `mesopic(nits)`, `scotopic(c)`,
  `night_shift(c, amount)`, `night_camera()`, `Camera.night_vision`,
  `light_node_cam(c, cam)`, `push_level(cam, blend, lamps, air, haze)`,
  `clear_level()`; fixtures `jelly_jar_60w`, `window_office`,
  `window_home`, `shopfront`, `signal_red/yellow/green`, `ped_hand`,
  `ped_walk`, `aviation_red_flash/steady` (chromaticity `xy` for coloured
  signals).
- `LucidCity`: `GRID`, `AVENUE_LAMP`, `STREET_LAMP`, `grid_lamps(rect)`,
  `Surf` (quad, box, box_rot, cyl, poly with cell clipping, wall),
  `corner_walk()`, `bake(surfs, lamps, states, space, rays)`,
  `bake_probes()`, `unit_box()`, `block_multimesh()`, `point_multimesh()`,
  `instance()`, `push_sky(a, b, t)`.
- Globals: `lucid_sky` (x blend, y night vision, z lamp level, w haze),
  `lucid_air` (rgb airlight, a extinction), `lucid_sky_zenith`,
  `lucid_sky_horizon`, `lucid_sky_glow`, `lucid_sky_glow_dir`.
- Shaders: `lucid_city.gdshaderinc` (`lucid_finish`, `lucid_mesopic`,
  `lucid_air_light`, `lucid_sky_now`, `lucid_reflection`,
  `lucid_road_paint`), `lucid_city` / `lucid_facade` (baked surfaces),
  `lucid_blocks`, `lucid_ground`, `lucid_points`, `lucid_sky`,
  `lucid_windows.gdshaderinc`.

Stage 3 sources: Falchi et al. 2016, the new world atlas of artificial
night sky brightness, https://www.science.org/doi/10.1126/sciadv.1600377 ;
Jensen et al. 2000, a physically-based night sky model,
https://graphics.stanford.edu/~henrik/papers/nightsky/ ; Thompson,
Shirley & Ferwerda 2002, a spatial post-processing algorithm for images of
night scenes; CIE 191:2010 mesopic photometry,
https://cie.co.at/publications/recommended-system-mesopic-photometry-based-visual-performance ;
McCamy 1992 CCT formula, https://en.wikipedia.org/wiki/Color_temperature ;
ITE VTCSH / PTCSI signal intensities; FAA AC 70/7460-1M obstruction
lighting; Koschmieder's law, https://en.wikipedia.org/wiki/Visibility .
The city's sizes: assets/levels/night_city/SPEC.md.

## What stage 4 does

Stage 4 gives L.U.C.I.D. surfaces a real specular: polished floors and wet
streets mirror the lights the way a phone photo shows them, and nothing is
reflected that the light does not give.

### One specular model (`shaders/lucid_spec.gdshaderinc`)

- GGX (Trowbridge-Reitz) microfacets, Smith's height-correlated
  visibility, Schlick's Fresnel with the material's real F0. Roughness is
  perceptual (alpha = roughness^2).
- The diffuse keeps 1 - E_spec, where E_spec is the lobe's directional
  albedo (the split-sum DFG term, Karis' analytic fit for mobile). So a
  glossy floor at a grazing view gets darker as it gets more mirror-like.
- Three sources of specular light, in the same units as the bake:
  1. **Emitters the level knows**, worked out per pixel
     (`lucid_emitter_cover`). The reflected lobe is a gaussian about the
     mirror direction, sqrt(2) alpha wide in the plane of incidence and
     cos(theta_v) times that across it. A microfacet tilt turns the
     reflection by twice the tilt in that plane and by 2 cos(theta_v) times
     it across, which is why lamps on a glossy floor stretch into streaks
     toward you. Its peak density, 1 / (4 pi alpha^2 cos theta_v), is
     GGX's. An emitter (a rectangle of known size and luminance) covers a
     share of that lobe: its angular extent in the lobe's frame (its area
     kept), convolved with the gaussian (an erf on each axis). The
     reflected radiance is luminance x share x E_spec. The pixel's own
     angular footprint widens the lobe a little, so a mirror does not
     alias.
  2. **The environment** (everything but those emitters): a box-projected
     reflection probe, read at the mip whose texel matches the lobe.
  3. **Light nodes** (the moon): GGX per light in `light()`.

Materials (roughness, F0):

| Surface | Roughness | F0 | Where |
| --- | --- | --- | --- |
| Asphalt, dry | 0.75 (x the texture) | 0.04 | city road, alley |
| Asphalt, soaked (wet 1.0) | 0.19 | 0.04 | after rain |
| Concrete sidewalk / curb, damp (wet 0.55) | 0.74-0.8 | 0.04 | darker, still matt |
| Roof concrete, damp (wet 0.5) | 0.85 | 0.04 | ponds in puddles |
| Puddle (water film) | 0.03 | 0.02 | city, any wet floor |
| Painted steel (poles, doors, housings) | 0.45-0.5 | 0.04 | city |
| Polished terrazzo | 0.08 | 0.045 | Dead Mall floors |
| Glazed floor tile | 0.06 (0.03 wet) | 0.04 (0.02 wet) | Dead Mall, Poolrooms |
| Honed stone | 0.2 | 0.045 | Dead Mall |
| Fountain water | 0.03 | 0.02 | Dead Mall |
| Brushed steel (rails) | 0.3 | 0.56 | Dead Mall |
| Carpet, dry or damp | 0.98 | (none) | Lobby: no gloss, damp only darker |

### Emitters reflected analytically

- **Blue Hour** (`shaders/lucid_street.gdshaderinc`, `lamp_reflections`):
  the street grid's lamps are found by arithmetic, not from a list. The
  reflected ray meets the avenue heads' height (10 m) and the street heads'
  height (8 m). The nearest head of each kind to that point is evaluated
  as its lens (LED 0.5 x 0.25 m, 36 400 cd/m2; sodium 0.4 x 0.25 m,
  42 000 cd/m2), at its lamp level (the failing head follows its cycle).
  Far down a street the meeting point is far away, so a puddle mirrors the
  distant heads too. The eight vehicle signals' lit lenses (300 mm, peak
  cd / area, a +-15 degree beam) give the red, yellow and green streaks.
  That is 2 + 8 emitter evaluations per wet pixel, the signals rejected
  early when out of the lobe.
- **Dead Mall** (`mall.gdshader`, `panel_cover`): the panels are drawn from
  above into a map (`_build_reflections`: cover and height, RG8, 0.1 m a
  texel). The floor follows the reflected ray to the three heights where
  panels hang and reads the map with `textureGrad` over the lobe's
  footprint on that plane: sigma x distance / sin(elevation) along the
  ray, sigma_across x distance across it. Their radiance is the bake's own
  (Blender emission strength 9 = radiance 9 in lightmap units), so a panel's
  reflection keeps its ratio to the lit floor. Stage 3's oval spots (7x
  the panel's luminance, (1 - roughness) as a gloss) are gone.
- **Poolrooms** (`pool_tile.gdshader`, `panel_cover`): the 2 x 2 LED
  panels sit on WorldGen's checkerboard (3 % dead). The 3 x 3 cells round
  the reflected ray's point on the ceiling plane are evaluated as
  emitters at the panels' luminance (`Lucid.face_engine`: 2540 cd/m2 with the LLF, 16.5 in
  engine units, set by WorldMaterials). Where the lobe's footprint
  outgrows the cells (far off, at grazing views) it hands over to the
  panels' mean cover (lit area / ceiling area, 3.2 %). Each tile is laid a
  hair out of level (+-0.004 rad), so the image breaks tile by tile. The
  rest of the white-tiled room is the Tiled Baths' one "probe": the floor's
  own light x 0.79 x 0.7.

### Reflection probes (`scripts/render/lucid_probe.gd`, `LucidProbe`)

A probe is the radiance arriving at a point, in the level's light units,
as an octahedral map: 128 texels across, RGBE 9-9-9-5, box-filtered mips,
85 KB with its mips. It is captured once, when the level is built: six 64 px HDR
SubViewports (RGBA half, checked exact from 0.0003 to 30) with a linear
camera render its faces, two frames a probe, reused from one probe to the
next. The faces are then resampled on the CPU (about 20 ms a probe). A texel is
clamped at 50 engine units.

While a probe captures, the global `lucid_capture` is 1, and
`lucid_capturing(PROJECTION_MATRIX)` is 1 only in the capture views (a
90 degree square projection, which no player camera has). In those views:

- the city shaders output engine units (no exposure, night shift or
  airglow: the surface that mirrors the probe adds those along its own
  view);
- the analytic emitters go dark (street heads' and signals' lenses, the
  mall's panels), and so do the point sprites;
- the ground's own reflections are off (they would come back as glare
  round the probe's horizon), the moon's specular too (`light()`: its
  glint on the wet ground, 700 times a probe's mean, was read back by
  box-projected rays that point below the probe's centre as a blurry
  white smear on the wet road).

So nothing is reflected twice. A floor reads the probe box-projected: its
reflected ray is followed to the box (the street canyon between the
building lines, the mall section between its shopfronts) and the map is
read toward that point from the probe's centre, never sharper than mip 1.

- **Blue Hour**: seven probes, 1.7 m up (the roof 1.7 m over the roof):
  the alley, the roof, the crossing, the avenue north and south, the
  street east and west. Where a street runs on, its box ends 400 m away.
  The crossing is open four ways: it projects onto its two canyons
  (`lucid_plus_dir`: the ray is followed until it has left both the
  avenue's and the street's building lines, i.e. to the corner block it
  meets; a single 120 m box put the corner shopfronts, seen from the
  probe's centre, in the wrong place, a hard-edged white wedge on the wet
  asphalt at the crosswalks). They show
  the lit windows, the shopfronts and the sky in the wet asphalt.
- **Dead Mall**: one per kind of section (8), in section space, shared by
  the repeated sections.
- **Backrooms chunks**: no probe. The Lobby is matt; the Tiled Baths use
  the analytic room term above.

### Wet surfaces (`lucid_wet`)

A porous surface takes water in two steps (Lagarde 2013).

1. Up to wet = 0.5 the pores fill. That makes it darker, by Lekner & Dorf
   (1988): light is trapped under the water,
   A_wet = A (1 - r_e)(1 - r_i) / (1 - r_i A) with r_e = 0.066 and
   r_i = 0.472 for water, so asphalt goes from 0.09 to 0.046. It stays
   rough.
2. Above 0.5 water lies on it and smooths it, to a quarter of its
   roughness soaked. Water also fills half the texture's relief.

A puddle is a flat water film (roughness 0.03, F0 0.02) over the darkened
surface. Puddles sit in the low spots: value noise for depressions a few
metres across, and on roads the gutters along the curbs, where the 2 %
crossfall sends the water (`puddle`). The noise's octaves are turned off
the grid (no square shapes), an octave finer than the pixel's footprint
fades to its mean, and the rim is as wide as the mask changes across the
pixel, so a puddle's edge does not stair-step or crawl at grazing views.

### Ground surfaces without glitches

- **Specular anti-aliasing** (`lucid_surface`, Kaplanyan 2016, like
  Godot's own shader): the final normal's change across the pixel is added
  to roughness^2 (at most 0.18), so the asphalt's relief does not sparkle
  in the lamps', signals' and shopfronts' reflections on the wet road.
  Flat water keeps its mirror.
- **Road paint** is box-filtered over the pixel's footprint along x and z
  (`fwidth`, not its length): lines seen down the road stay sharp across,
  the dashes and the zebra's bars are filtered pulse trains (they no longer
  crawl), and far off a line fades to its mean coverage instead of a
  bright half-covered band.
- **Floors that do not repeat** (`untile`: the sidewalks, the plaza and
  the roof, whose pale concrete showed its 1.2-1.6 m repeat; the wet
  asphalt hides its own): a copy of the texture turned 37 degrees, scaled 0.83 and shifted
  is blended in by smooth noise about 1.5 m across (a narrow blend, so the
  detail keeps its contrast), the two layers +-8 % apart in tone. One more
  texture read.
- **Normal maps** are imported as normal maps (RGTC on desktop, EAC RG11 on
  phones; z rebuilt in the shader): RGB block compression made 4x4 blocks
  in the wet reflections. About 1.4 MB more video memory.
- **The far ground**'s wear is smooth value noise (hashed 2 m squares
  showed as a checkerboard on the far streets).

The Blue Hour is after rain: the road soaked (puddles 0.5), the alley
0.9, sidewalks and curbs damp (0.55: dark, matt), the plaza 0.6, the roof
0.5 with ponding. The far ground shader uses the same model, so the two
agree where they meet. The Lobby's damp carpet patches are darker by the
same formula and matt (stage 3 gave them roughness 0.55 and more specular).
Pool surrounds are glazed tile with a water film where wet.

### Air (`lucid_airglow`)

The haze is lit by the four nearest street heads (globals
`lucid_glow0..3`), as single scattering along the view ray from the eye to
the shaded point. Each head is a point source of I0 cos^1.2 (taken at the
ray's closest point, h from the lamp). The scattering coefficient is 0.9 x
the extinction (urban aerosol, albedo 0.9), with a Henyey-Greenstein phase
(g = 0.6):

L = sigma_s I p (atan((d - tc) / h) + atan(tc / h)) / h

At the night state's 3.3e-4 /m (12 km visibility) that is a faint glow of
about 0.3 cd/m2 a metre from a head, as strong as the real haze makes it.
It is added in `lucid_finish_at` (city surfaces, buildings, the far ground)
and in the sky. Indoor dust is not modelled.

### Stage 3 fixes

- **Colour uniforms**: Godot converts a Color given to a vec3 / vec4
  uniform from sRGB to linear, even without `source_color`. So every
  measured value the city passed as a Color arrived wrong:
  - an albedo of 0.30 arrived as 0.073;
  - a window's 25 cd/m2 arrived as 7x less;
  - a lens's 36 000 cd/m2 arrived as 10^15.

  Textured surfaces were half hidden by the same error in `tex_mean`.
  `NightCityLevel._sp()` now passes them as Vector3. Windows,
  shopfronts, untextured steel and signals now have their real values,
  and the lenses no longer bloom without bound.
- **Shopfronts**: they no longer read as flat clipped panels. They show a
  real luminance range: a row of night lights under the ceiling (8x the
  mean, which clip), the ceiling-lit top of the back wall, shelving in
  shadow, a dim floor, a dark counter, and the glass's reflection over
  them. Their mean is ~0.6 of the fixture's 40 cd/m2 (the bake's gather
  still uses the full mean).
- **Meter**: the city's meter adds the lamps' GGX reflection on wet ground
  for the spots that hit it (each lens as a small sphere, Karis 2013), and
  the darkening.

## API (stage 4)

- `shaders/lucid_spec.gdshaderinc` (guarded; included by
  `lucid_city.gdshaderinc`, `mall.gdshader`, `pool_tile.gdshader`):
  - BRDF: `lucid_schlick`, `lucid_ggx(n, v, l, rough, f0)` (BRDF x cos),
    `lucid_spec_albedo(ndv, rough, f0)`, `lucid_lobe`.
  - Mirror and emitters: `LucidMirror` / `lucid_mirror(n, v, rough)`,
    `lucid_emitter_cover(p, m, centre, a1, a2, half_sizes)`, `lucid_box`,
    `lucid_erf`.
  - Probes: `lucid_oct`, `lucid_box_dir`, `lucid_plus_dir` (a crossing),
    `lucid_probe_lod`.
  - Capture: `lucid_capture` (global), `lucid_capturing(PROJECTION_MATRIX)`.
- `shaders/lucid_street.gdshaderinc`: uniforms `wet`, `puddles`, `gutters`,
  `lens_led`, `lens_na`, `fail_lamp`, `sig_pos/rad/dir[8]`; functions
  `lucid_wet(col, rough, f0, moist, film)`, `puddle(p, footprint)` (uses
  derivatives: uniform control flow),
  `lamp_reflections(lp, m)`.
- `lucid_city.gdshaderinc`: `lucid_airglow(wpos, cam)`,
  `lucid_finish_at(c, wpos, cam, cap)`; globals `lucid_glow0..3`,
  `lucid_glow_led`, `lucid_glow_na`.
- `lucid_surface.gdshaderinc` uniforms: `f0` (replaces `specular`),
  `reflect_env`, `lamp_refl`, `analytic_emitter`, `probe_tex`
  (sampler2DArray), `probe_n`, `probe_c/lo/hi/sel[8]` (`probe_c.w` 1: a
  crossing, `lucid_plus_dir`), `untile`. `sky_gloss` is
  gone (the sky's reflection is now the probe's or E_spec x sky x sky
  visibility).
- `LucidProbe`: `SIZE`, `FACE`, `CLAMP`, `capture_environment(bg)`,
  `capture(host, origins, env, far, scale)` (await; two frames a probe),
  `octahedral(faces)`, `oct_dir(u, v)`, `array_texture(maps)`,
  `bytes(maps)`.
- `NightCityLevel`: `PROBES`, `PROBE_PROJECT`, `PROBE_PLUS`, `probe_bytes`, `probe_ms`,
  `_capture_probes()`, `_lamps_spec()` (meter), `_sp()`; layout materials
  take `f0`, `wet`, `puddles`, `gutters`, `lamps`, `untile`. `QA_GROUND=1`
  adds the ground QA shots (`g_*`: standing, looking down, grazing, the
  crossing, the alley, the roof, the far ground).
- `MallLevel`: `REAL_SPEC`, `PROBE_Y`, `PROBE_BOX`, `probe_bytes`,
  `refl_bytes`; `mall.gdshader` uniforms `rough_real`, `f0`, `panel_rad`,
  `probe_tex`, `probe_c`, `probe_box_lo/hi`.
- `pool_tile.gdshader`: `panel_rad`, `panel_cover()`.
- `_test/levels/level_shots.gd`: `PERF=1` (mean frame time over 60
  frames a shot), `SHOTS=<list>`.

### Validation (stage 4)

The probe capture is checked in the harness (a box of known emission on
each face, 0.0003 to 30 engine units). They come back exact through the
HDR SubViewport, and the octahedral map puts each one in its direction.

A street head's reflection on the soaked road matches GGX worked by hand.
Take the avenue LED head 25 m off, seen from 1.7 m (cos theta_v = 0.17):

- roughness 0.27 gives a peak of about 37 cd/m2, against 0.7 cd/m2 for
  the lamp-lit road beside it (50x);
- across the view the streak is 2 sqrt(2) alpha cos theta_v = 2 degrees
  wide.

This is the look of a phone photo of a wet street: the streaks clip, the
road between them is dark.

Screens (before = HEAD, after = stage 4; `_test/levels/level_shots.tscn
-- night_city`, `_test/realistic_shots.tscn`, `_test/lucid_shots.tscn`,
`_test/water_shots.tscn PRESET=5`):

- Blue Hour avenue, crossing, side street: the lamps and signals streak
  toward you in the soaked asphalt; puddles mirror the shopfronts and the
  facades (probes); damp sidewalks are darker and matt. The windows and
  shopfronts are brighter and the lenses' bloom smaller (the colour
  uniform fix).
- Roof, alley, failing lamp: the roof is damp, with shallow puddles; the
  alley's puddles mirror the stair's bulbs' light and the lit windows.
  The failing head's streak goes out with it.
- Dead Mall concourse and Fountain Court: the panels' reflections are
  rectangles stretched toward you, faint at your feet (F ~ 0.05) and
  strong far off; the far floor mirrors the section (probe). Stage 3's
  round spots at 7x the panel's luminance are gone.
- Poolrooms dry floor and pool edge: the panels on the checkerboard,
  streaking and breaking tile by tile, fading into an even sheen far off.
  Stage 3's mottled streaks are gone.
- Lobby spawn hall: unchanged but for the damp carpet patches (darker,
  no gloss). The car park's Attendant: unchanged.

Cost (lavapipe, 1280 x 720, Realistic, mean frame time over 60 frames,
the same project tree; run-to-run noise about 5 %):

| View | HEAD | Stage 4 | Draw calls |
| --- | --- | --- | --- |
| Blue Hour, mean of 12 shots | 135.8 ms | 130.0 / 132.3 ms (two runs) | 24-29, unchanged |
| Dead Mall concourse / Fountain Court | 98.7 / 96.1 ms | 104.3 / 102.6 ms (mean of three runs, +6 %) | 86, unchanged |
| Poolrooms (realistic_shots) | 165.2 ms | 176.8 ms (mean of three, +7 %) | 380, unchanged |
| Lobby spawn hall | 125.4-131.9 ms | 131.0-140.3 ms (noise: the shading is the same) | 212 |

Memory:

- Probes: the Blue Hour 7 x 85 KB = 597 KB, the Dead Mall 8 = 682 KB.
- The mall's panel map: 2277 KB, the same as before (RG8 at 0.1 m
  instead of RGF at 0.2 m).
- Lavapipe reports the Blue Hour's video memory at 131 MB instead of 106.6
  MB. That is the HDR capture's pipelines and the six capture viewports'
  leftovers (about 1.4 MB a viewport stays allocated after it is freed;
  42 viewports at once left 150 MB, so they are reused).

Capture time on lavapipe, first-use pipeline compiles included: the Blue
Hour 11.2 s, the Dead Mall 7.7-10.9 s. Resampling takes ~20 ms a probe.
On a phone it is two frames a probe (14 / 16 frames) at load.

Regressions:

- `side_flow_test`: 0 failed, 0 script / shader errors (exit 134 after
  the mall, as before).
- `level_shots night_city`, `realistic_shots`, `lucid_shots`,
  `water_shots`: 0 script or shader errors.
- The Android export builds.
- The presets other than Realistic take the old paths: the pool tile's
  `tile_glint` and the carpet's damp gloss without L.U.C.I.D., the mall's
  analytic floor only in Realistic.

### Known limits of stage 4

- The lobe is a gaussian with GGX's peak and width, but not GGX's long
  tails. The soft halo round a reflection on a polished floor is
  narrower than a real one.
- Emitters are rectangles seen in the small-angle limit, their extents
  projected onto the lobe's axes (a parallelogram's area kept). A lamp
  seen nearly edge-on in a mirror is approximate.
- The Blue Hour reflects the nearest avenue head and street head (where
  the reflected ray meets their heights) and the eight vehicle signals.
  The pedestrian signals, the stair's bulbs and the far point lights are
  not reflected (the point sprites are kept out of the probes).
- Probes are captured once at 64 px a face, never read sharper than mip 1,
  and box-projected with one box. A puddle's mirror image of a facade is
  soft; the crossing (open four ways) projects onto its two canyons. The
  capture costs two frames a probe at load and pipelines for the HDR
  target. The probes do not follow the lamp levels
  (a failing head's light in them stays).
- The Backrooms chunks have no probes. The Tiled Baths reflect the room as
  a uniform term from the floor's own light. No glossy biome besides it
  shows its environment.
- The mall's panel map is 0.1 m a texel. A panel's reflection on terrazzo
  at 0.08 is about as sharp as the map. The map has the lowest panel over
  each spot only.
- Wetness is a fixed state of the level (after rain), not a weather
  simulation. The bake's bounce does not see the darker wet ground (a few %
  less bounce in reality).
- Airglow only for the four nearest heads, isotropic in azimuth, without
  the extinction along the path (under 1 % at these distances).
- The city's probes (mean of six directions) for moving things are still
  not directional (stage 3 limit). Entities get no specular from the
  probes.

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
