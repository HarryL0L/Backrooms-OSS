# Level 1.1 - The Stacks (`filing`)

A records centre's storage floor after hours: five storage bays and a
sorting room behind 8 in block fire-barrier walls, joined by two 72 in
service corridors, about 1030 m2. Every bay is filled wall to wall with
mechanical-assist mobile shelving: carriages of cartons on flush floor
rails, a three-spoke handle on every end panel. The open aisles are the
only ways through the bays, and they move: nobody turns the handles.
Getting lost and getting caught between two ranges are the stakes.

Files: `scripts/world/levels/filing_level.gd` (the level: shelving geometry,
motion, lights, portals, the walk grid), `scripts/world/levels/filing_layout.gd`
(the floor plan as data: GENERATED, do not edit),
`tools/blender/levels/filing_layout.py` (the floor plan: edit this, run it),
`tools/blender/levels/filing.py` (one kit per room and its bake, textures,
the labels atlas, sounds), this folder (kits, lightmaps, textures, audio,
`filing_lit.gdshader(inc)`, LICENSE.md), `_test/levels/filing_exit_test.tscn`,
`_test/levels/filing_maze_test.tscn`.

## How you get here, how you leave

- **In**: the registry entrance (`ARCHIVE` door in CONCRETE biome walls, in
  `side_levels.gd`). You stand just inside Bay 1's archive door (shut behind
  you: NO EXIT) at the west end of its main aisle, facing east. The main
  aisle's occupancy sensor sees you: relay, a second of ballast preheat, the
  strips strike. Bay 1 is the room the Stacks were before the floor grew.
- **Out**: the exit door in Bay 4's north wall, mid-way along its main
  aisle, under its exit sign ("Open the exit door", Use): `exit_entered("")`,
  back into the Backrooms somewhere else. The framework's `door` look; its
  ride ends 0.1 m in front of the wall over Bay 4's floor (each kit's floor
  collision covers its room and 0.35 m past every wall).

## The floor plan (Blender x east, y north; Godot (x, z) = (x, -y) round LEVEL_Y)

A top-down map with the routes: `python3 tools/blender/levels/filing_layout.py --map out.png`.

```
 y=30.7 +---------BAY 2-----+------------------BAY 4 (dark)---[EXIT]-------+ CORR
        |main | 12 carriages|  24 carriages, 2 open aisles, 8-sect ranges   |  B
        |aisle| E-W ranges  |  handles on the north main aisle; far ends    |
        |  ^  | 9 sections  |  against corridor A (two fire doors open      |  |
        |  |  |rear aisle ->+--door into Bay 4's main aisle                 |  |
 y=19.1 +-d4--+-------------+--------[g1]--------------[g2]-------------+--+  |
        |stair2  CORRIDOR A (72 in)                                      vault |
 y=17.1 +------------d1-----+---d2---+------------------------d3---------+  |
        | BAY 1 (as built)  |SORTING |  BAY 3: two banks of 16,           d6--+
        | 2 banks of 12     |        |  2 open aisles each                |  |
        | main aisle        |        |  main aisle                        |  |
 y=0    +--arrival----------+--------+------------------------------------+ janitor
       x=0               11.6  19.0                                     35.0  37.1
```

| Room | Size | Shelving |
| --- | --- | --- |
| Bay 1 (R1) | 11.61 x 16.87 m | 2 banks x 12 carriages, 1 open aisle each, 6-section (6.45 m) ranges; the cart in bank A's aisle |
| Corridor A (C1) | 39.2 x 1.83 m | dead ends: STAIR 2 (locked, west, 5.2 m past Bay 2's door), VAULT (locked, east) |
| Sorting (R2) | 7.19 x 10.06 m | none: two sorting tables, a pigeonhole case, a desk and terminal, three carts, the step stool, a floor plan |
| Bay 3 (R3) | 15.83 x 16.87 m | 2 banks x 16 carriages, 2 open aisles each, 6-section ranges |
| Bay 2 (R4) | 12.50 x 11.61 m | 1 bank x 12, 1 open aisle, ranges east-west, 9 sections (9.65 m); main aisle west, rear aisle east |
| Bay 4 (R5) | 22.28 x 10.46 m | 1 bank x 24, 2 open aisles, 8 sections (8.58 m); far ends against corridor A, no rear aisle |
| Corridor B (C3) | 1.83 x 27.56 m | dead end south: JANITOR (locked), a mop bucket |
| **Total** | **1035 m2** | 92 carriages, 12 fixed units |

Doors (36 x 84 in hollow-metal fire doors, held open on magnets): Bay 1 /
corridor A (d1), sorting / A (d2), Bay 3 / A (d3, into Bay 3's north rear
aisle), Bay 2 / A (d4), Bay 2 / Bay 4 (d5, from Bay 2's rear aisle into
Bay 4's main aisle), Bay 3 / corridor B (d6, from Bay 3's main aisle), B /
Bay 4 (d7). **Gated**: two fire doors (g1, g2) from corridor A open straight
onto Bay 4's range ends: shelving behind the door, unless an aisle has
rolled in line with it.

The ways to the exit (all through moving shelving):
1. Bay 1 (any aisle of bank B) > corridor A west > Bay 2 (any of its long
   east-west aisles) > its rear aisle > Bay 4's main aisle > the exit.
2. Corridor A > g1 or g2, when an aisle lines up > up that 8.6 m aisle >
   the exit. Otherwise you see the end of a carriage through the door.
3. Corridor A east > Bay 3 (either aisle of bank B) > its main aisle >
   corridor B north > Bay 4's main aisle from the east > the exit.

Navigation aids: door signs (where the door goes, from each side), a range
card on every end panel ("4A17": bay, bank, carriage), bay / range signs by
the main aisles, direction signs in the corridors, and floor plans ("STORAGE
FLOOR 1 REV C", with a red YOU ARE HERE dot) in corridor A, corridor B and
sorting. Misleading on purpose: corridor A's "EXIT <-" points west, at the
locked stair; Bay 2's floor plan is REV A (Bay 4's doors further west, no
corridor B, the exit at the stair).

Time to the exit: the walking bot in `filing_exit_test` (knows the plan, sees
the shelving) takes 28-140 s depending on the shelving (it waits out closing aisles); a first-time player
who has to read the signs, try the dead ends and wait out or dodge the
shelving takes three to five minutes.

## Real-world values and sources

| What | Value used | Source |
| --- | --- | --- |
| Records carton | 15 x 12 x 10 in nominal (outside 12.5 in wide, 10.25 in high on the shelf), ~1.2 cu ft, the 12 in end facing the aisle | Conservation Resources "15 x 12 x 10 in. cubic foot record storage box" https://www.conservationresources.com/?p=1583 ; Texas DOT "standard document storage box ... 1.2 cubic foot ... 10 x 12 x 15 inches" https://www.txdot.gov/manuals/itd/rec/inactive_records/storage-i1019528/storage_box_descriptions-i1019626.html |
| Full carton mass | 30 lb (13.6 kg) per cubic foot of records | Douglas County GA volume conversion chart https://douglascountyga.gov/DocumentCenter/View/1285/Volume-Conversion-Chart-PDF ; Texas A&M https://askus.library.tamu.edu/faq/111765 |
| Shelf depth / section | 15 in per face, 42 in sections (3 cartons across) | carton size above |
| Range lengths | 6 sections (6.45 m, Bays 1 and 3), 8 (8.58 m, Bay 4), 9 (9.65 m, Bay 2); mechanical-assist carriages come in standard lengths up to 45 ft (13.7 m) | Spacesaver mechanical assist brochure: "available in standard lengths up to 45 feet (13.7m)" https://info.southwestsolutions.com/hubfs/Brochures/SSG-Brochures/SPA-129/High-Density/Mechanical-Assist-High-Density-Storage.pdf ; Montel Mobilex carriage lengths "3' to 45' (0.91m - 13.7m)" https://www.montel.com/media/4cflnw1q/mobilex_one_pager-copy.pdf |
| Shelf pitch, height | 12 in (305 mm) openings, 7 high from 0.14 m, canopy top 2.30 m | carton height + clearance |
| Aisle | 36 in (914 mm) | Metro qwikTRAK: aisle "30"-36" (760-914mm)" https://res.cloudinary.com/iwh/image/upload/q_auto,g_center/assets/1/26/Metro_qwikTRAK-DataSheet.pdf ; ADA 36 in https://info.southwestsolutions.com/hubfs/Brochures/SSG-Brochures/SPA-129/High-Density/ADA-Accessibility-Compliance.pdf |
| Carriage capacity | 1000 lb per linear foot | Spacesaver mechanical assist spec (above) ; Montel Mobilex "1,000 lbs per linear foot" (above) |
| Loaded carriage mass | 6-section: 252 cartons x 13.6 kg = 3.4 t + ~0.35 t steel | the two rows above |
| Drive | 6:1 on 5 in (127 mm) cast-iron wheels: 0.0665 m per turn | Borroughs Aisle Saver https://mh-usa.com/wp-content/uploads/2024/04/Borroughs-Aisle-Saver-Mobile-Shelving-Brochure.pdf ; Spacesaver https://og.mhi.org/media/members/15465/130065500422919439.pdf |
| Carriage speed | 0.11 m/s (a brisk crank); powered systems are held to 3 in/s (76 mm/s) | Bradford / Southwest ActivRAC 16P https://info.southwestsolutions.com/hubfs/Brochures/SSG-Brochures/SPA-129/High-Density/Tech-Data-ActivRAC-16P.pdf |
| Fire compartments | each bay its own compartment behind 8 in (0.2 m) block fire-barrier walls; records centres are limited to 250 000 cu ft of records per compartment (our largest, Bay 3: ~8 600 cartons, about 10 000 cu ft) | 36 CFR 1234.12 (fire barrier walls; "250,000 cubic feet total of Federal records in a single records storage area") https://www.law.cornell.edu/cfr/text/36/1234.12 ; NFPA 232 compartment limit (trade press summary) https://law-journals-books.vlex.com/vid/nfpa-standard-update-54542548 |
| Fire doors | 36 x 84 in hollow metal, held open by electromagnetic hold-opens that release on the alarm (never wedges) | https://open-exam-prep.com/study-guides/chfm/compliance-framework/life-safety-code-egress ; https://www.swinter.com/tech-notes-meeting-the-accessibility-criteria-for-horizontal-exit-doors/ |
| Service corridors | 72 in (carts pass); code minimum 44 in; dead ends 20 ft, 50 ft where sprinklered (ours: 5.2 m and 6.4 m, sprinklered) | IBC 1020.2 table (Chicago adoption) https://codelibrary.amlegal.com/codes/chicago/latest/chicago_il/0-0-0-2665038 ; dead ends https://datadrivenaec.com/insights/ibc-egress-corridor-requirements |
| Occupancy sensors | real ones are set from 30 s to 30 min (15 min a common default; energy code: off within 20 min); here 2 min in the bays and sorting 5 min, 30 s in the corridors, 22 s in Bay 4 (set near the bottom of the range: the after-hours economy setting that makes the dark bay dark) | Leviton OSWHB (time delay, default 15 min) https://leviton.com/products/oswhb-i0w ; ICC IECC Q&A https://www.iccsafe.org/building-safety-journal/bsj-technical/iecc-qa-switches-and-lighting-occupancy-sensors-in-storage-rooms/ |
| Sprinkler clearance | deflectors at 2.82 m: 0.52 m over the top of storage (NFPA 13: 18 in min.) | https://www.csemag.com/sprinkler-installations-and-obstructions/ |
| Strip fixture | 4 ft 2 x F32T8 strip, 4500 lm, 5000 K, x LLF 0.85 | `Lucid.FIXTURES.strip_t8_2lamp` (docs/LUCID.md) |
| Light level | ~320 lux under a row; 200-400 lux in the open aisles with the bars (EN 12464-1 archives 200 lux vertical) | https://glamox.com/en/pbs/application-guide/education/libraries-and-study-halls ; https://www.docs.lighting.philips.com/global/lighting_university/courses_new2015/ABT/english/storages_02.html |
| Aisle light bar | 820 lm/m LED, 4000 K, on the canopy edge of each face; on with motion in the aisle, off 20 s after | catalogue-typical LED linear output |
| Ceiling | 3.20 m slab soffit | records storage 3.0-3.5 m |

## The light (L.U.C.I.D. units)

- One kit per room (`filing_<R1..R5,C1,C3>.glb`), each baked on its own in
  Cycles (`filing.py`): the colour lightmap holds what is always on (night
  lights, exit signs), the group map its four occupancy-sensor zones (baked
  at half the colour map's size: they are smooth). Tubes are emitters of
  their real luminance (6520 cd/m2, `TUBE_EMIT` 42.4 engine units).
- 24 light groups on the floor, not 4: every room's materials carry their own
  `room_light[4]` (filing_lit.gdshaderinc) instead of the framework's four
  global groups. Bay 1: main aisle, bank A + south rear aisle, bank B south
  row, bank B north row + north rear aisle (as first built); Bay 3 the same;
  Bay 2: main aisle, two range zones, rear aisle; Bay 4: four single strips
  5.5 m apart over the main aisle and nothing else (dark between them; its
  aisles have only their bars); corridors: four and three zones; sorting one.
- Each kit's untextured materials are merged into one vertex-coloured
  `paint` surface (lamps coded in its alpha), so a kit is four or five draw
  calls (floor, block, slab, paint, exit sign).
- The shelving moves, so it is lit analytically (as first built) from the
  same rows, in each room's own frame (`frame_ax`: Bay 2 and corridor B run
  north-south), plus the aisle bars, plus light through the doorways: each
  opening is a Lambertian patch of the next room's luminance (its light at
  the door times a mean albedo of 0.4, over 0.91 x 2.13 m), so a lit corridor
  throws a pool onto the range ends behind a fire door and into a dark bay.
- Camera: auto exposure metering the rows where you are and look, white
  balanced at 4800 K.

## Rules (the motion)

- A bank's state: idle, warning, moving, stopped (Bay 1's cart), going back.
  A close picks an open aisle and a shut gap in the run of carriages next to
  it; the carriages between roll together (as cranking one end of a pressed
  run does) by the aisle's width until they meet: a clunk, cartons jumping,
  papers sliding off; the aisle is now where the shut gap was. A bank always
  keeps its count of open aisles (1 or 2), so there is always a way through.
- **Warning** (before any motion): the frames creak, the cartons on the
  moving carriages shiver, the handles twitch, the aisle bar flickers and
  goes out (driver click); then the handles spin, the rails rumble, the chain
  drive ticks; 1.2 s to 0.11 m/s.
- **Fair warning** (`_warn_for`): long enough that from the furthest point of
  the closing aisle you can react (1.5 s) and walk out at 2.6 m/s to an open
  end (the main aisle; the rear aisle; a fire door only if it lines up) with
  0.3 s to spare before the gap is narrower than you (0.64 m); never less
  than 1.5 s. A dead-end 8.6 m aisle in Bay 4 warns ~2.0 s, then ~3.1 s more
  until it is too narrow: 5.1 s to walk 8.6 m.
- **Being caught**: stand in an aisle (1 m or more from both ends) 2.6-6 s
  and it shuts on you (the first time in Bay 1 bank B: 0.9 s, 2 m in, and the
  east carriages move so the new aisle opens by the door). The carriages are
  AnimatableBody3D and push you; if the gap you're in closes below 0.64 m (or
  inside a carriage), the crush, `catch_player` with lines.
- **Now and then** (every 6-13 s, more often near you) a range moves on its
  own somewhere on the floor; never one you're standing in, never more than
  two at once; Bay 4 now and then lines an aisle up with a fire door.
- **Bay 1 bank A** has a cart in its aisle (as first built): the first time
  you pass its mouth it rolls in, pins the cart, rattles, rolls back. The
  cart can't be passed (0.55 m beside it), so Bay 1's south rear aisle is a
  space nobody reaches (it was never on a route).
- **Bay 4**: as you walk its main aisle, something knocks from inside the
  shut shelving beside you, a step ahead of you; stop, and it knocks once
  more right by you, then waits. Sound only; nothing comes out.
- **Lights**: occupancy sensors per zone (above), time out behind you;
  aisle bars on when you're at an aisle's mouth or in it, off 20 s after.
- Saved: every bank's open aisles, the cart, which lights are on, the two
  first-time events.

## Fairness, proved

`_test/levels/filing_maze_test.tscn` runs the level's own logic (`sim_step`:
the scheduler, the stand-in-an-aisle closes, the first-time events, the
cart) for 5 seeds x 5 minutes with a walker that wanders, stops in aisles so
they shut on it, and walks out REACT s after a warning, on the level's walk
grid (0.25 m cells where a 0.3 m radius person fits, `grid_free`):
1. every spot anyone can reach rejoins the exit within 20 s (a flood fill
   from the exit door every 0.5 s; cut-offs only last while a range rolls);
2. from the arrival and 40 random spots at random moments, the exit is
   reached within 150 s (the reachable set swept forward through the
   recorded shelving states at a walk, waiting allowed);
3. at the start of every close, from every spot in that aisle, react + walk
   out is shorter than the time until it is narrower than a person;
4. the walker is never crushed.
Last run: 158 closes, the smallest walk-out margin 0.33 s (the SAFETY
built into `_warn_for`), the longest cut-off 6.0 s (a range rolling across
the only aisle of Bay 1 bank B), the exit reached from every sampled spot
and moment within 25 s by a walker who knows the way, the walker never
crushed. (Bay 1's south rear aisle, behind the cart, is the one place
nobody can ever reach: ~100 grid cells, never joined, so never a place you
can be.)
`filing_exit_test` walks the maze with the player's own physics (three
layouts: 28 s, 138 s, 79 s) and checks the catch (warned 5.3 s before it),
standing on every kind of floor, the exit.

## Sound (synthesised placeholders, `filing.py --sounds`)

Freesound refuses automated access, so every sound is shaped noise (smooth
log-frequency bands, no sine tones in any impact; the only tones are the
ballast's 120 Hz hum, as in a real ballast): `hvac_loop`, `hum_loop`,
`rumble_loop`, `drive_loop`, `clunk_1/2`, `creak_1/2`, `carton_1..3`,
`paper_1/2`, `relay`, `ballast_start`, `led_click`, `cart_1/2`, `crush`,
`knock_1..3` (knuckles on the inside of a steel end panel through a
carriage of cartons: low thud bands, a dull tap, low-passed). Replace with
real CC0 recordings when they can be fetched: same names.

## Cost (harness, worst views)

Measured with `level_shots -- filing` (Realistic) at its 17 shots and with
`SWEEP=3.0` (352 views: every 3 m over the floor where you can stand, four
ways each, all lights on).

| | Shots | Sweep (worst of 352) |
| --- | --- | --- |
| Draw calls | 3-40 | 51 (Bay 2, looking down the main aisle with Bay 4 through the door) |
| Primitives | 4 200-51 000 | 67 900 (corridor A, looking along it past four doorways) |
| Real-time lights | 0 | 0 |
| Textures | 13, all <= 1024 px, VRAM compressed, mipmapped (no harness warnings) | |
| Assets on disk | 9.1 MB (was 4.3: seven kits and their lightmaps, the labels atlas, one wood texture, three sounds) | |

What keeps it cheap: a carriage is one draw call (frame, cartons, handle and
range card in one mesh; the handle turns and the card is picked in the
vertex shader), and only a carriage with an open side draws its shelves and
cartons (one with both sides pressed shut draws its base, canopy and end
panels: ~100 triangles); a room's kit is ~5 draw calls; and only the room
you're in and what you can see of the others through their doorways is
drawn (a 2D portal pass every frame, the view clipped by each opening, then
per carriage). Six carton meshes per range length are shared by all
carriages.

QA: `_test/levels/level_shots.tscn -- filing` (17 shots), `--movie` (the
film), `filing_exit_test`, `filing_maze_test`, `side_flow_test`,
`side_exit_fall_test`.

## Left to do

- Real CC0 recordings for every sound.
- Light leaks: the doorway spill ignores the shelving in between; the bake
  of each room doesn't see the next room's lamps (the spill stands in).
- Specular highlights of the strips on the sealed floor.
