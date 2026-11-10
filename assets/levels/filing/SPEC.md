# Level 1.1 - The Stacks (`filing`)

One storage room of a records centre, after hours. Sealed concrete, painted
block, a painted slab 3.2 m up with sprinkler pipe and a supply duct, and two
banks of high-density mobile shelving wall to wall: carriages of cartons on
flush floor rails, each with a three-spoke handle on its end panel. Each
bank has one open aisle. Nobody turns the handles.

Files: `scripts/world/levels/filing_level.gd` (the level, the shelving
geometry, the motion), `tools/blender/levels/filing.py` (the room kit and
its bake, textures, sounds), this folder (kit, lightmaps, textures, audio,
`filing_lit.gdshader(inc)`, LICENSE.md), `_test/levels/filing_exit_test.tscn`.

## How you get here, how you leave

- **In**: the registry entrance (`ARCHIVE` door in CONCRETE biome walls, in
  `side_levels.gd`). You stand just inside the archive door (shut behind you)
  at the west end of the main aisle, facing east down it. The main aisle's
  occupancy sensor sees you: relay, a second of ballast preheat, the strips
  strike. Until then only the night-light strip by the door and the exit sign
  in the far corner are lit.
- **Out**: the exit door in the north wall, east end of the north rear aisle,
  under its exit sign ("Open the exit door", Use): `exit_entered("")`, back
  into the Backrooms somewhere else. The rear aisle is behind bank B, so the
  only way there is through one of bank B's aisles. The exit is the
  framework's `door` look; its ride ends 0.1 m in front of the wall, over the
  room's floor (the kit's floor collision covers the whole room and 0.5 m
  past every wall), and `_test/levels/filing_exit_test.tscn` checks that you
  stand at the arrival, in the main and rear aisles and on the door's
  threshold, and that going through drops you nowhere.

## Layout (Blender x east, y north; Godot (x, z, -y) round LEVEL_Y)

```
 y=16.87 +--------------------------------------------[EXIT]-+  north rear aisle (42 in)
   15.80 |F|  bank B: 12 carriages + 1 open aisle         |F|  ranges 6.45 m (6 x 42 in)
         |I|  (handles on the south end panels)           |I|
    9.35 |X|______________________________________________|X|
    8.44 D=arrival      main aisle (72 in)                     |  stool by bank B
    7.52 |F|^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^|F|  (handles on north end panels)
         |I|  bank A: 12 carriages + 1 open aisle (cart)  |I|
    1.07 |X|______________________________________________|X|
 y=0     +-----------------------------------------------------+  south rear aisle (42 in)
        x=0                                                x=11.61
```

- Room 11.61 x 16.87 m, 3.20 m to the slab soffit.
- A bank: a fixed single-faced unit (0.421 m) against each side wall, twelve
  double-faced carriages (0.813 m) and one 36 in aisle between them: 11.51 m.
- Strip rows (along x, across the ranges, five 4 ft strips each, 2.32 m
  apart, tubes at 2.85 m): south rear aisle, bank A x 2, main aisle, bank B
  x 2, north rear aisle. Light groups: 0 main aisle, 1 bank A + south rear,
  2 bank B south, 3 bank B north + north rear. Always on: the night-light
  strip (main aisle, by the door), the exit sign.
- Four flush rails under each bank (0.40, 2.28, 4.17, 6.05 m from its south
  end), 2 in heads in cast-in channels.
- The cart (records truck) stands 2.9 m into bank A's aisle.

## Real-world values and sources

| What | Value used | Source |
| --- | --- | --- |
| Records carton | 15 x 12 x 10 in nominal (outside 12.5 in wide, 10.25 in high on the shelf), ~1.2 cu ft, the 12 in end facing the aisle | Conservation Resources "15 x 12 x 10 in. cubic foot record storage box" https://www.conservationresources.com/?p=1583 ; Texas DOT "standard document storage box ... 1.2 cubic foot ... 10 x 12 x 15 inches" https://www.txdot.gov/manuals/itd/rec/inactive_records/storage-i1019528/storage_box_descriptions-i1019626.html |
| Full carton mass | 30 lb (13.6 kg) per cubic foot of records | Douglas County GA volume conversion chart: "one cubic foot of records weighs about 30 lbs. dry" https://douglascountyga.gov/DocumentCenter/View/1285/Volume-Conversion-Chart-PDF ; Texas A&M: boxes no more than 35 lb packed https://askus.library.tamu.edu/faq/111765 |
| Shelf depth / section | 15 in per face (carton depth), 42 in sections (3 cartons across), 6 sections = 6.45 m ranges with end panels | carton size above; carriage lengths in multiples of the section |
| Shelf pitch, height | 12 in (305 mm) openings, 7 high from 0.14 m, canopy top 2.30 m | carton height + clearance; 7-high records shelving on a carriage |
| Aisle | 36 in (914 mm) | Metro qwikTRAK: aisle "30"-36" (760-914mm) under normal conditions" https://res.cloudinary.com/iwh/image/upload/q_auto,g_center/assets/1/26/Metro_qwikTRAK-DataSheet.pdf ; ADA 36 in continuous clearance https://info.southwestsolutions.com/hubfs/Brochures/SSG-Brochures/SPA-129/High-Density/ADA-Accessibility-Compliance.pdf |
| Carriage capacity | 1000 lb per linear foot: ~21 000 lb (9.5 t) for a 21 ft carriage | Spacesaver mechanical assist spec: "minimum load carrying capacity of 1,000 lb. (1,500 kg) per linear foot (meter)" https://info.southwestsolutions.com/hubfs/Brochures/SSG-Brochures/SPA-129/High-Density/Mechanical-Assist-High-Density-Storage.pdf ; Montel Mobilex "1,000 lbs per linear foot" https://www.montel.com/media/4cflnw1q/mobilex_one_pager-copy.pdf |
| Loaded carriage mass | 252 cartons x 13.6 kg = 3.4 t + ~0.35 t steel = ~3.8 t | the two rows above |
| Drive | 6:1 drive ratio on 5 in (127 mm) cast-iron wheels: 0.0665 m per turn of the handle; "6,000 lbs with just 1 lb of pressure" | Borroughs Aisle Saver "6:1 drive ratios ... moving 6,000 lbs. with just 1lb. of pressure" https://mh-usa.com/wp-content/uploads/2024/04/Borroughs-Aisle-Saver-Mobile-Shelving-Brochure.pdf ; Spacesaver "20" and over carriage widths utilize 5" (127mm) diameter cast iron load wheels" (search summary of https://og.mhi.org/media/members/15465/130065500422919439.pdf) |
| Carriage speed | 0.11 m/s (a brisk crank, 1.65 turns/s of the handle); for scale, powered systems are held to 3 in/s (76 mm/s) | Bradford / Southwest ActivRAC 16P "3" (76mm) per second" https://info.southwestsolutions.com/hubfs/Brochures/SSG-Brochures/SPA-129/High-Density/Tech-Data-ActivRAC-16P.pdf ; Montel Mobilex HD ~20 ft/min https://dp-assets-new.s3.amazonaws.com/assets/11994491/Mobilex_HD_Montel_Specifications_eng.pdf |
| Sprinkler clearance | deflectors at 2.82 m: 0.52 m over the top of storage (NFPA 13: 18 in / 457 mm min.) | CSE "clearance between the deflector and the top of storage must be 18 inches or greater" https://www.csemag.com/sprinkler-installations-and-obstructions/ ; OSHA interpretation (18 in plane over the storage area) https://osha.gov/laws-regs/standardinterpretations/2008-09-29 |
| Strip fixture | 4 ft 2 x F32T8 strip, 4500 lm, 5000 K, x LLF 0.85 | `Lucid.FIXTURES.strip_t8_2lamp` (docs/LUCID.md) |
| Light level | ~320 lux direct under a row, ~200-400 lux in the open aisles with the bars (EN 12464-1: archives / library shelves 200 lux vertical) | Glamox EN 12464-1 table "Library: bookshelves 200" https://glamox.com/en/pbs/application-guide/education/libraries-and-study-halls ; Philips "Archives - Em = 200 lux ... between racks" https://www.docs.lighting.philips.com/global/lighting_university/courses_new2015/ABT/english/storages_02.html |
| Aisle light bar | 820 lm/m LED, 4000 K, on the canopy edge of each face, aimed down into the aisle; on with motion in the aisle | catalogue-typical LED linear output; carriage-mounted aisle lighting is an option on mechanical-assist systems |
| Ceiling | 3.20 m slab soffit | brief: 3.0-3.5 m records storage |
| Main / rear aisles | 72 in / 42 in | common records-room layouts (48-72 in main aisle) |

## The light (L.U.C.I.D. units)

- The room is baked (Cycles, `filing.py`) without the shelving: the tubes
  are emitters of their real luminance (4500 lm x 0.85 over the two tubes'
  surface: 6520 cd/m2, `TUBE_EMIT` 42.4 engine units).
- The shelving moves, so it can't be baked: `filing_lit.gdshaderinc` lights
  it (and corrects the baked floor in the aisles) analytically from the same
  rows: each row is a Lambertian line source of 1827 lm/m (I = 582 cd/m), and
  a surface's irradiance is the exact integral over the part of the row it
  sees through its slot (between two faces, under the 2.30 m top of storage,
  or out of the slot's open end). The baked floor of an open aisle is
  multiplied by the ratio of the slot's light to the open room's, so it
  darkens as a real 36 in aisle between 2.3 m shelving does. The aisle bars
  are line sources along the ranges. Bounce: 30 % of the open floor's light
  times how open the slot is. The carriages' own shading (shelf undersides,
  the shelf above each carton) is baked into vertex colours.
- Camera: the level's auto exposure meters the rows' light where you are and
  where you look (opening up to ~4 stops in the dark), white balanced at
  4800 K (the 5000 K strips read neutral, the 4000 K bars a touch warm).

## Rules (the motion)

- A bank's state: idle, warning (1.0 s), moving, stopped, (bank A) going
  back. Closing aisle `a` moves every carriage on one side of it together
  (as cranking one does on a real system) by 36 in until they meet: a
  clunk, cartons jumping, papers sliding off; the bank's open aisle is now at
  the far end of the group that moved.
- **Warning** (always before any motion): the frames creak, the cartons on
  the moving carriages shiver, the handles twitch; if the aisle light bar was
  on it flickers for 0.8 s and switches off (a driver click). Then the
  handles spin (1.65 turns/s), the rails rumble (camera rumble within 9 m),
  the chain drive ticks; 1.2 s to full speed.
- **Being caught**: standing in a bank's aisle (more than 1 m in) for a
  while makes it shut on you: 2.6-6 s (the first time in bank B: 0.9 s after
  you're 2 m in, and the east carriages move, so the new aisle opens at the
  east end, by the exit). From the first warning to the gap being narrower
  than you (0.64 m) takes ~4.1 s; walking out of the middle of an aisle
  (3.2 m) takes 1.25 s, and walking straight through one (5.4 m past the
  first metre) takes 2.1 s, less than the shortest wait. The carriages are
  AnimatableBody3D and push you; if the gap you're in closes below 0.64 m
  (or below that next to the cart): the crush (grinding, cartons bursting,
  the bumpers meeting; shake), `catch_player` with lines.
- **Bank A** has a cart in its aisle. The first time you pass its mouth on
  the main aisle its strips come on by themselves and a side of it rolls in,
  shoves the cart across the aisle until it's pinned, clunks, rattles, waits
  and rolls back. Now and then (every 28-50 s while you're out of the banks)
  a range moves on its own: bank B relocating its aisle, or bank A at its
  cart again.
- **Lights**: occupancy sensors: main aisle on arrival; bank A's rows when
  you're at its aisle (or its range moves); bank B's south row when you
  enter it, its north row and the north rear aisle 3 m in. Each strip group
  starts as a programmed-start T8 does (relay, ~1.1 s cathode preheat,
  strike; now and then a lamp stutters). Aisle light bars: on when you're at
  an aisle's mouth or in it.
- Saved: each bank's aisle, the cart's place, which lights are on, the two
  first-time events.

## Sound (synthesised placeholders, `filing.py --sounds`)

Freesound refuses automated access and no API key was available, so every
sound is a documented placeholder made of shaped noise (smooth log-frequency
bands, no sine tones in any impact or drop; the only tones are the ballast's
120 Hz hum, as in a real ballast): `hvac_loop` (the records room's air
handler, all night for the humidity), `hum_loop` (strip ballast), `rumble_loop`
(cast-iron wheels on steel rails under 3.8 t, pitched with speed),
`drive_loop` (chain and sprocket ticks and whir), `clunk_1/2` (carriages
meeting: floor thud, steel knock, carton rattle), `creak_1/2` (the warning),
`carton_1..3` (cartons shifting), `paper_1/2` (paper sliding off and
fluttering), `relay`, `ballast_start`, `led_click`, `cart_1/2` (the cart's
steel jolted), `crush`. Mono 44.1 kHz ogg. Replace with real CC0 recordings
when they can be fetched: same names.

## Cost (harness, worst view)

| | Realistic | Medium |
| --- | --- | --- |
| Draw calls (worst: down the main aisle) | 79 | 81 |
| Primitives (worst) | 84 500 | 84 500 |
| Real-time lights | 0 | 0 |
| Textures | 11, all <= 1024 px, VRAM compressed, mipmapped (no harness warnings) | |
| Assets on disk | 4.3 MB | |

Per carriage: 3 draw calls (frame + its range card, the cartons, the
handle), one shared material; cartons 8 triangles each (the faces you can
see), six carton meshes shared by all 24 carriages; the room kit one
1024 px lightmap + groups. The shader's per-pixel work: two banks of 12
carriages scanned for the slot, 8 strip rows integrated.

QA: `_test/levels/level_shots.tscn -- filing` (10 shots, Realistic and
Medium, body cam on), `--movie` (the film), `_test/levels/filing_exit_test.tscn`
(standing everywhere you can be put, the exit ride, the return; and
standing in an aisle: warned 4.8 s before the catch), `side_flow_test`
(0 failed).

## Left to do

- Real CC0 recordings for every sound.
- Specular highlights of the strips on the sealed floor (no real-time lights:
  the floor is matt in the bake).
