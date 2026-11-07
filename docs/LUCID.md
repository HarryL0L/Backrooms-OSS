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

1. **Units, camera, albedo** (this stage, done)
   - Real light units, real fixture presets with sources, and Kelvin colour
     from the CIE locus.
   - A physical camera: EV100, phone-like metering and limits, auto white
     balance in Kelvin, AgX.
   - Measured albedos for the Lobby's surfaces.
   - The bake in lux, with radiosity carried to all bounces.
   - The ad-hoc compensations removed.
2. **Relightable per-tile bake**
   - Bake one transfer per light per tile, in lux per unit flux, so lights
     can be switched, dimmed or flickered exactly without a rebake (today a
     texel follows only its strongest flickering lamp).
   - A 3D probe grid (spherical-harmonic L1 or ambient cube) for moving things
     such as entities, props and the player's hands. This replaces the
     analytic `WorldGen.lucid_light_near` estimate. The per-cell ambient cubes
     added in stage 1 (`ChunkManager.light_probe`) are the seed of it.
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
