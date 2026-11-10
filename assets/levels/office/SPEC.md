# Level 6.1 - The Dimming Floor (`office`)

One floor of an open-plan office building, after hours. Carpet tiles, a
9 ft T-bar ceiling, ninety 2 x 4 troffers, 48 workstations, black glass all
round with nothing behind it (not even the city). The floor's lighting
panel only believes you're there while you keep still.

Files: `scripts/world/levels/office_level.gd` (the level),
`tools/blender/levels/office.py` (kits, bake, textures, sounds), this
folder (kits, lightmaps, textures, audio, `office_lit.gdshader(inc)`,
LICENSE.md).

## How you get here, how you leave

- **From the Crawlspace** (its return grille: `exit_entered("office")`): the
  default arrival. You stand under a 2 x 2 ft hole in the ceiling grid (the
  return grille's neck going up into the dark trunk), the grille lying face
  down on the carpet in front of you, grit still drifting down (particles,
  a trickle of debris, a small jolt of landing). Facing west, down the spine.
- **The registry entrance** (`SUITE 400` door, floors >= 1, in
  `side_levels.gd`): when `arrival()` finds that you are still in the
  Backrooms beside a `LevelEntrance` whose `dest` is `"office"`, you come
  in just inside the suite door (west wall, on the spine) facing east down
  the north spine aisle. Any other
  way in (a chain, the dev harness) uses the grille. No framework change.
- **Out**: the stair door in the west wall (north end) under its EXIT sign:
  "Take the stairs" (Use). The door swings into the stair, you go through
  onto the landing (concrete, painted block, steel stairs, a wall pack),
  `exit_entered("")`: back into the Backrooms somewhere else.

## Layout (Blender x east, y north; Godot (x, z, -y) round LEVEL_Y)

```
 y=18.3  +---------------------------- windows (N) --------------------------+
         |  [stair]E  cluster 1      cluster 3      cluster 5     cluster 7   |
   ~15.6 D=stair      (6 cubes)      (6 cubes)      (6 cubes,     (6 cubes)   |
         |                                          chair rolls)              |
   ~9.9  D=suite (SUITE 400; spine: two 1.8 m aisles either side of the       |
    9.1  |  files   o  files files  o   copier    o   files  ^grille          w|
         |  cluster 0      cluster 2 (monitor wakes) cluster 4    cluster 6   |
    3.6  D=elec (the relay panel)                                             |
 y=0     +---------------------------- windows (S) --------------------------+
        x=0                                                              x=36.6
```

- Floor plate 120 x 60 ft (36.58 x 18.29 m), 4 x 2 bays on a 30 ft grid;
  3 interior columns (24 in square, drywall) on the spine at y = 30 ft.
- Workstation clusters 24 x 16 ft (2 x 3 cubes of 8 x 8 ft), one per bay
  each side of the spine, 3 ft cross aisles at the columns, 6 ft perimeter
  aisles, a 14 ft spine.
- Banks: troffer columns at x = 5 ft + k x 8 ft (k = 0..14), six fixtures
  each (rows every 10 ft). Bank k = baked light group k % 4.
- The open grille: the 2 x 2 ft cell at (34.44, 8.84). Chair: workstation 31
  (bay 2 north, opening on the spine). Monitor: workstation 16 (bay 1 south).

## Real-world values and sources

| What | Value used | Source |
| --- | --- | --- |
| Floor-to-ceiling (open plan office) | 9 ft (2.743 m) | CISCA life-cycle study, typical office "a nine (9) foot floor to ceiling height and an open plan layout" https://assets.noviams.com/novi-file-uploads/cisca/migrated%20assets/project_149/images/cisca_life_cycle_study_-__final_report.pdf ; GSA shell "typical 9-0 ceiling height offices" https://www.scribd.com/document/250919218/gsa-usc-shell-office-pdf |
| Column grid | 30 ft bays | precast office design guide, "30' wide typical" https://jvi-inc.com/?p=5707 |
| Ceiling grid / tiles | 2 x 2 ft lay-in tiles, 15/16 in T-bar, 5/8 in tile; 2 x 4 troffers span two cells | standard US suspended ceiling module (ASTM C635 grid); Office Ceiling 001 texture is the same module |
| Troffer | 2 x 4 ft, 3 x F32T8 (2850 lm each), ballast factor 0.88, luminaire efficiency ~80 % -> 6020 lm (L.U.C.I.D. `troffer_t8_3lamp`), 4100 K (F32T8/841) | Day-Brite 3-lamp F32T8 2x4 troffer sheets: 2850 lm/lamp, BF .88, 84 W, efficiency 78.7-87.1 % https://www.assets.signify.com/is/content/PhilipsLighting/3813a342d0e240ecb465a87f01138620 ; docs/LUCID.md "Fixtures" |
| Light loss factor | 0.85 (lamp lumen depreciation ~0.95 x lens dirt) | docs/LUCID.md (`LUCID_LLF`, 0.8 for the Backrooms' old troffers; this office is cleaner) |
| Lens luminance | I0 / A = (5117 lm x 2 / 2 pi) / (1.22 x 0.61 m) = 2190 cd/m2 = 14.27 engine units | Lambertian troffer, docs/LUCID.md "Engine units" (1 unit = 153.6 cd/m2) |
| Layout | 8 x 10 ft (2.44 x 3.05 m) per troffer -> measured in the bake on the carpet in the aisles: 280-495 lux (10 points, median ~400) | target 300-500 lux, EN 12464-1 office 500 lux (docs/LUCID.md "Targets") |
| Programmed-start ballast | lamps strike 1.0-1.5 s after power (cathode preheat), no flicker; here 1.12-1.33 s, one lamp after another | Elliott Electric catalogue (Advance programmed start T8: "start lamps quickly (1.0 -1.5 seconds) without flicker") https://elliottelectric.com/Media/IZT4S32-ADV ; GE UltraStart sheet "1 to 1.5 seconds" https://www.1000bulbs.com/pdf/ultrastart%20sell%20sheet.pdf |
| Fluorescent run-up | ~90 % at strike, full in ~20 s (cold lamp) | typical T8 warm-up (estimate) |
| Workstation | 8 x 8 ft cubes; spine panel 65 in (1.65 m), side and return panels 53 in (1.35 m), 3 in thick; 36 in opening | panel heights 53-54 in (seated privacy) and 65 in (standard) https://www.officefurniture2go.com/answers/cubicles-workstations/what-panel-heights-are-available-for-cubicles.html |
| Worksurface | 29 in (0.737 m) high, 30 in deep, 24 in return | fixed-height desks 29-30 in https://www.officefurniture2go.com/guides/pdfs/OF2go_Straight_Desks_Top10_QA.pdf ; UBC: 29 in is above elbow height for nearly all users https://hr.ubc.ca/sites/default/files/2020-09/Height%20Adjustable%20Desks%20Purchasing%20Guidelines%201_2.pdf |
| Mobile pedestal | 15 x 22 x 27.5 in | typical box/box/file pedestal catalogue size |
| Task chair | 26 in five-star base, 19 in seat height, ~1 m back | BIFMA X5.1 class task chair, typical catalogue values |
| Monitor | 24 in 16:9 (0.53 x 0.30 m active) | standard panel size |
| Lateral file | 36 x 18 x 40 in (3-drawer) | typical catalogue size |
| Exit sign | 12 x 7.5 in housing, EXIT in 6 in letters, 3/4 in stroke; red LED letters ~300 cd/m2 | IBC 1013.6.1 letter height and stroke (via https://Parks.ColoradoSprings.gov/system/files/2023-07/2021_ifc_exit_signs_emergency_lighting_final_0.pdf and CA Title 8 3216 https://www.dir.ca.gov/Title8/3216.html); luminance an estimate |
| Doors | 36 x 84 in, hollow metal frame 2 in face; stair door swings into the stair (direction of egress), panic bar on the office side | IBC egress door minimums / common practice |
| Stair | 7 in risers, 11 in treads | IBC 1011.5.2 maximum riser 7 in, minimum tread 11 in |
| Windows | 5 ft mullion module, 30 in sill, glass to the ceiling, perimeter convector enclosure | common curtain-wall office module |
| Mini blinds | 1 in slats | standard commercial horizontal blinds |
| Albedos (linear) | carpet 0.06-0.08, ceiling tile 0.80 (LR 0.80+ for mineral fibre), wall 0.60, panel fabric 0.13, laminate 0.37 | manufacturers' light reflectance values (ceiling tiles LR 0.80-0.90; dark commercial carpet LRV 5-10 %); docs/LUCID.md albedo table |
| Chair rolling | v0 0.95 m/s, deceleration ~0.35 m/s2 (caster rolling resistance on carpet ~0.035) | estimate from rolling-resistance coefficients of small casters on carpet |

## Light (L.U.C.I.D.)

- Units: every lens emits its real luminance in engine units, so the
  Cycles DIFFUSE bake (light only) is E / pi in the same unit as the
  Backrooms' L.U.C.I.D. bake (cd/m2 / 153.6). Albedos are linear means of
  the textures (the textures are rescaled to them), the same values tint the
  bounce in the bake.
- Banks: 15 banks, 4 group channels. The bake puts bank k in group k % 4;
  `office_lit.gdshaderinc` (a copy of the framework's shader with only the
  group light changed) takes, per pixel, the nearest bank of each group
  along x, blended half way to the next one of that group (4 banks =
  9.75 m away, where its direct light is ~1 % of the near bank's), times
  that bank's state from a 16 x 1 texture the level updates each frame.
  So each bank switches, flickers and starts alone; lenses follow their
  bank. If the framework's include changes, regenerate the copy (the four
  replacements are listed in its header).
- Always on (colour bake): the exit signs, one night-light troffer by the
  stair (an unswitched emergency circuit, as real offices have), the
  stair's 1500 lm wall pack.
- Light colour: Lucid `troffer_t8_3lamp` 4100 K, under a 4500 K white
  balance (a phone's AWB under fluorescent light).
- Camera: the level runs its own body-cam auto exposure (`_update_exposure`):
  metered from the banks round you and where you look, up to 2.4 stops of
  gain in the dark, opening slowly (1.2 /s) and closing fast (3 /s). The dark
  stays dark.
- Moving parts (the chair, the monitor, the door leaf) get the bank light at
  their position (`light_at`) as a flat light. The monitor's backlight adds
  one small real-time omni light (only while awake).

## What happens

- **The banks**: once you've walked 4 m from where you landed, walking makes
  the banks behind you (more than ~1 bank behind, in the direction you're
  going) go out, the farthest first, one every 0.45-0.85 s: the contactor
  clunks in the electrical closet (one place, behind its door: filtered), the
  tubes tick off at the bank, now and then a weak lamp blinks once more.
- **Standing still** 2.6 s: the dark banks come back from the far end toward
  you, one every 0.6-1.05 s: relay, ~1.1 s of cathode preheat (the lamp ends
  glow orange through the lens, a rising buzz), the three lamps strike one
  after another, 40 % of the time the third stutters (zaps) before it holds.
  They stop short of you, leaving a dark gap of 4, 3, 2, 1, then 0 banks:
  each time closer.
- **In the gap**: the figure (the tall CC0 body, near-black, lit only by the
  little light that reaches it) stands at the edge of the light that came
  back, turned toward you, its head following you. It is gone when its bank
  strikes, when you come within 4 m, or when your torch finds it (the lit
  bank behind it blinks, a zap, and it isn't there). It never comes for you.
- **The chair** in workstation 31 rolls out into the spine as you pass
  (0.95 m/s, slowing on the carpet, swivelling), casters rumbling.
- **The monitor** in workstation 16 wakes when you're within 3.6 m (relay
  click, the backlight coming up with a little flash, a dim blue lock
  screen, light on the desk), sleeps when you've gone.
- A **phone** rings four times somewhere dark (every 55-90 s); the
  **printer** by the copier warms up the first time you come near it.

## Sound

Real recordings could not be fetched for this level (Freesound refuses
automated access and no API key was available), so every sound is a
**synthesised placeholder** (`office.py --sounds`): noise shaped in the
frequency domain (loops periodic by construction, no seams), smooth
log-frequency bands rather than resonant filters (nothing rings), mains
120 Hz hum where a real ballast hums. Mono 44.1 kHz ogg q4, one-shots
-3 dBFS peak, loops -20 dBFS RMS: `hum_loop` (per bank, 3D, volume by its
output), `hvac_loop`, `relay_1..3`, `tube_off_1..2`, `ballast_start_1..2`,
`zap_1..3`, `phone_ring`, `printer_start`, `chair_roll`, `monitor_wake`,
`door_open`, `debris`. Replace them with CC0 recordings of the same names
when possible (the Crawlspace already carries CC0 recordings of a
fluorescent hum and a starter that would fit). Reverb: room 0.45, damp 0.8,
wet 0.16 (carpet, mineral tile, fabric panels: a dead room).

## Budget (harness, mobile renderer, 1280 x 720)

| | Medium (preset 2) | Realistic (preset 5) |
| --- | --- | --- |
| Worst shot (arrival / spine / chair) | 12 draw calls, 46.2k primitives | 10 draw calls, 46.2k primitives |
| Real-time lights in view | 0 (1 omni while the monitor is awake) | same |
| Video memory (whole game) | 127 MB | 151 MB |

- Kits: 22.8k + 23.0k triangles (two GLBs, 2.1 MB each), 2 x 1024 px colour
  lightmaps + 2 x 1024 px group maps (lossless, as level_kit writes them).
- Textures: 512 px (roughness 256), VRAM compressed with mipmaps (the
  harness lists none as too costly).
- Folder: 7.4 MB (`du -sh assets/levels/office`), under the 8 MB budget.
- Per frame on the CPU: 15 banks into a 16 x 1 texture and a 64 x 1
  far-light strip, ~1000 multiply-adds.
- Low presets: `camera_far()` 30 m (48 m otherwise).

## Tests

- `_test/levels/level_shots.tscn -- office` (11 shots: arrival, arrival_up,
  arrival_grille, spine, cubicles, perimeter, behind (the figure in the
  gap), relight (cathode glow, a lamp striking), dark, chair, exit;
  `--movie` plays `film()`): 0 errors on presets 2 and 5.
- `_test/levels/office_arrival_test.tscn`: from the Crawlspace's
  `exit_entered("office")` you stand under the grille, on your feet; banks
  go out behind you as you walk; the stair door offers "Take the stairs"
  and takes you back to the Backrooms; through a SUITE 400 door you stand
  just inside the suite door (10 PASS, 0 failed).
- `_test/levels/side_flow_test.tscn`: 0 failed.

## Left to do

- Real CC0 recordings for the placeholder sounds.
- Reflections in the night glass (it is black: nothing outside, and no
  reflection probe on phones).
