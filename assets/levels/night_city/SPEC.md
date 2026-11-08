# Level 12.1 - The Blue Hour (`night_city`)

An endless, empty modern city stopped in the middle of a clear night.
Every street lamp is on, thousands of windows are lit, the signals still
cycle green, yellow and red for nobody and the crossing still ticks for the
blind; no people, no cars, only the hum of a city with nobody in it and,
now and then, a siren very far away that never comes closer. Original
setting: no real city, brand or franchise.

You come out of a steel roof door ("ROOF", on a CONCRETE or LOBBY wall of
an upper Backrooms floor, 2 and up) onto the roof of a six-storey brick
building on the corner of an avenue and a street. You can walk to the
parapet, round the bulkhead and the timber water tank, and down the steel
fire stair in the alley to the crossing: its four corners, the two
carriageways and the plaza under the office tower, closed off by road
barricades. You leave by the roof door you came from or by the building's
street door on the avenue (both `exit_entered("")`, back to the Backrooms).

Files: `scripts/world/levels/night_city_level.gd` (the level: materials,
backdrop, camera, signals, the failing lamp, sound, shots, film),
`night_city_layout.gd` (the plan, shared with the bake),
`scripts/render/lucid_city.gd` (L.U.C.I.D. stage 3: geometry for baking,
the bake, instancing, the sky), the `shaders/lucid_*` shaders,
`tools/lucid/city_bake.tscn` (bakes `bake/street.res`, `bake/a.res`,
`bake/probes.res`; rerun after any change to the plan: ~85 s headless),
`tools/lucid/night_city_audio.py`, `_test/levels/night_city_dusk.gd` (the
same level in its dusk state, for the harness). Lighting: docs/LUCID.md,
stage 3. Rain: `scripts/render/lucid_rain.gd`, `shaders/lucid_rain.gdshader`,
the rings in `shaders/lucid_street.gdshaderinc`, the lens drops in
`shaders/eye_lens.gdshader` and `scripts/ui/hud.gd`,
`tools/lucid/night_city_rain.py` (its placeholder sounds); docs/LUCID.md,
"Rain".

## Layout (level space: metres, X east, Z south, ground 0 at the crossing)

```
              z -70  D1 brick 5 st (shops)    D2 7 st
   E2   E1 office tower 160 m          |avenue|
        (plaza in front, -70..-15)     | x=0  |
  ------- street (z = 0, 12 m carriageway, 4 m sidewalks) ---------
   C2 5 st   C1 office 12 st    |      |  A (yours) 6 st | alley | B 9 st
                                |      |  roof 21.0 m    | 45-51 |
              z +70             |      |  A2 4 st        | stair |
```

- Grid: avenues along Z every 110 m, streets along X every 80 m
  (`LucidCity.GRID`), the same everywhere to the horizon.
- Roof: A's roof at 21.0 m (shops 4.5 m, five storeys of 3.3 m),
  parapet 1.1 m with a gap to the fire stair's top landing; bulkhead 5 x 5
  x 3 m with the roof door (arrival) and a caged bulb; water tank 4.6 m
  across on a 3.2 m stand; condensers, vents.
- Fire stair: on A's east wall in the 6 m alley, two flights a storey
  (10 treads of 0.3 m, risers 0.15 m; the first storey's lower flight
  starts under the first floor landing: 13 treads, risers 0.174 m),
  landings 1.2 m, rails 1.07 m; bulbs at each storey. Built like a real
  steel one: 200 mm channel stringers, open bar-grating treads with nosing
  angles, grating landings in 150 mm channel frames on a ledger angle
  bolted to the wall and on four 80 mm columns, knee braces under the half
  landings, guards (top rail, bottom rail, 12 mm pickets 0.1 m apart) on
  every open side, a wall handrail on the inner flights. A window opens
  onto each floor landing (sill 0.8 m), none behind the flights (A_side
  `win_mask`).
- Street door: a pair of 0.915 x 2.13 m leaves under a transom in its own
  5 m bay of the avenue front (no shopfront there: A_wall `shop_mask`).
- Bulkhead: a steel ladder up its north face to its roof.
- Bounds: barricades at x = +-86 and z = +-61 (invisible walls behind
  them), the alley's plywood hoarding at z = 46.
- Backdrop: ~5700 instanced buildings to 5.5 km (all of them within 1.3
  km, only taller ones further), two downtown clusters (one across a
  river 1.5 km west, with a suspension bridge), an elevated expressway
  385 m east, ~14000 point lights (lamps, beacons, signals, the bridge's
  cable lights).

## Real-world values: the audit (and where they come from)

Every object and dimension of the level, checked against codes,
standards and real ones (with a 1.75 m figure beside it: `QA_FIGURES=1`
in a debug build adds grey 1.75 m people at 13 spots and `scale_*` views
to `shots()`; see "Scale QA" below). "Was" is before the audit; "ok" means
it was already right.

Sources used throughout: [MUTCD 3] https://mutcd.fhwa.dot.gov/htm/2009/part3/part3a.htm ,
https://mutcd.fhwa.dot.gov/htm/2009/part3/part3b.htm ; [MUTCD 4]
https://mutcd.fhwa.dot.gov/htm/2009/part4/part4d.htm ,
https://mutcd.fhwa.dot.gov/htm/2009/part4/part4e.htm ; [MUTCD 6]
https://mutcd.fhwa.dot.gov/htm/2009/part6/part6f.htm ; [NACTO]
https://nacto.org/publication/urban-street-design-guide/ ; [IBC]
https://codes.iccsafe.org/content/IBC2018/chapter-10-means-of-egress ;
[CTBUH] https://www.ctbuh.org/resource/height ; [ADA]
https://www.access-board.gov/ada/ ; [OSHA]
https://www.osha.gov/laws-regs/regulations/standardnumber/1910/1910.23 ;
[FAA] https://www.faa.gov/documentLibrary/media/Advisory_Circular/Advisory_Circular_70_7460_1M.pdf .

### Streets

| What | Was | Now | Source |
| --- | --- | --- | --- |
| Grid, blocks | avenues every 110 m, streets every 80 m: blocks 80 x 60 m | ok | city blocks 60-250 m (Portland 61 x 61, Manhattan 61 x 274): https://en.wikipedia.org/wiki/City_block |
| Rights of way | avenue 30 m, street 20 m between building lines | ok | Manhattan avenues 100 ft, streets 60 ft: https://en.wikipedia.org/wiki/Commissioners%27_Plan_of_1811 |
| Avenue carriageway | 19 m: 4 lanes x 3.5 m + 2 parking x 2.5 m, no median | ok | lanes 3.0-3.6 m [NACTO lane width], https://safety.fhwa.dot.gov/geometric/pubs/mitigationstrategies/chapter3/3_lanewidth.cfm ; parking 2.1-2.7 m [NACTO] |
| Street carriageway | 12 m: 2 lanes x 3.5 m + 2 parking x 2.5 m | ok | same |
| Sidewalks | avenue 5.5 m, street 4.0 m | ok | downtown 3.7-6 m [NACTO sidewalks] |
| Curb | 150 mm barrier curb (collision: 0.4 m ramps); corner radius 4.5 m | ok | curbs 100-225 mm, 150 typical (AASHTO Green Book); radii 3-4.5 m [NACTO corner radii] |
| Lane lines | 120 mm, 3 m dashes, 9 m gaps | ok | 100-150 mm, 10 ft / 30 ft [MUTCD 3] 3A.06 |
| Avenue centre line | four 100 mm white lines (two either side of the axis) | a double yellow line: two 100 mm lines 100 mm apart | [MUTCD 3] 3A.05 (yellow separates opposing traffic), 3A.06 (double line) |
| Street centre line | white, dashed | yellow, dashed (3 m / 9 m) | [MUTCD 3] 3A.05, 3B.01 |
| Parking edge lines | 100 mm solid white | ok | [MUTCD 3] 3B.19 |
| Stop lines | 0.4 m, on the lanes leaving the crossing (the wrong half), 0.6 m from the crosswalk | 0.4 m, on the approach lanes (traffic keeps right), 1.2 m short of the crosswalk (avenue), 1.6 m (street) | 12-24 in wide, 4 ft or more before the crosswalk [MUTCD 3] 3B.16 |
| Crosswalks | 3 m, continental bars 0.6 m on 1.2 m centres, along the traffic; stopped short of the curb where it curves (up to 2.7 m of bare road) | the same, carried to 0.3 m from the curb round the corner radius | 6 ft or more, bars 12-24 in [MUTCD 3] 3B.18; at least the sidewalk's width, 10 ft [NACTO crosswalks] |
| Gutters, drains | water collects along the curbs (2 % crossfall, shader) | ok (no inlets modelled) | |
| Curb ramps | none (the collision ramps the curbs everywhere) | not added | (left to do: ADA 406, 1:12, 0.9 m) |

### Lamps and signals

| What | Was | Now | Source |
| --- | --- | --- | --- |
| Avenue lamps | LED 100 W, head 10 m up on a 2.5 m arm, pole 0.22 m, 0.6 m behind the curb, opposite pairs every 35 m (3.5 x height); head 0.72 x 0.32 x 0.12 m | ok | arterial 9-12 m poles, spacing 3-4 x height: https://en.wikipedia.org/wiki/Street_light ; offset 0.5 m or more from the curb face (AASHTO Roadside Design Guide); LED cobra heads ~0.7-0.8 m long |
| Street lamps | HPS 150 W, 8 m up on 1.5 m arms, pairs every 30 m; head 0.75 x 0.36 x 0.2 m | ok | local streets 7.5-9 m; HPS cobra heads (e.g. M-400 class) ~0.75 m long |
| Signal heads | three 300 mm sections, housing 0.36 x 1.05 x 0.25 m, 0.24 m visors | ok (lens drawn 0.27 m square: the 300 mm disc's area) | ITE VTCSH 12 in lenses |
| Signal placement | on all four corners, a mast arm head over the near-side lanes facing out, a pole head facing out: near-side heads, at the crosswalk | far side (MUTCD): the corner on an approach's far right carries its mast arm over its lanes (avenue arm 7.8 m, street arm 6 m), the far left corner a second head on the pole, both facing back across the crossing (18.8 m past the avenue's stop lines) | 2 heads or more per approach, 40-180 ft past the stop line [MUTCD 4] 4D.11, 4D.13, 4D.14 |
| Head heights | arm head 5.5 m (bottom 5.0 m over the road), arm 6.2 m; pole head 3.4 m | arm ok; pole head 4.1 m (bottom 3.4 m over the sidewalk, over the pedestrian head) | over a road: bottom 15 ft (4.6 m) or more, top 25.6 ft or less; at the side: bottom 8-19 ft [MUTCD 4] 4D.15 |
| Signal poles | 0.24 m, 6.4 m; arm 0.14 m | 0.33 m, 6.4 m; arm 0.18 m | mast arm poles 11-16 in at the base for 20-40 ft arms (manufacturer tables, e.g. Valmont, Union Metal) |
| Pedestrian heads | 0.36 x 0.5 m, symbols 0.26 x 0.2 m, centre 2.5 m | two 300 mm sections, 0.36 x 0.74 m, symbols 0.28 m high, bottom 2.2 m up | symbols 9 in (229 mm) or more where the far curb is over 60 ft off [MUTCD 4] 4E.07; bottom 7-10 ft up 4E.08 |
| Far crossings' signals | heads as the old near-side layout | mast arm heads as at the crossing (pole heads left out: the same point count) | |

### Street furniture

| What | Was | Now | Source |
| --- | --- | --- | --- |
| Hydrant | 0.24 m body, 0.65 m high, 3.5 m behind the curb | 0.2 m body, 0.78 m high with bonnet and base flange, nozzles, 0.65 m behind the curb | hydrants 0.6-0.9 m high, nozzles to the street, 18-24 in behind the curb: https://en.wikipedia.org/wiki/Fire_hydrant |
| Bus shelter | 2.0 x 6.4 m roof at 2.6 m, bench 0.45 m high, 0.4 m deep, back panel | ok | e.g. 1.5 x 4.3 x 2.4 m (NYC): https://www.nycstreetdesign.info/furniture/bus-stop-shelter ; seat 17-19 in [ADA] 903.5 |
| Litter basket | 0.56 m, 0.95 m high | ok | wire baskets 0.5-0.6 m, 0.8-1.0 m |
| Barricades | two 0.18 m rails (top 1.24 m), legs 1.1 m: Type 2 | Type 3: three 0.2 m rails, top 1.55 m, legs 1.6 m | road closure: Type 3, rails 8-12 in, top 5 ft or more [MUTCD 6] 6F.68 |
| Alley | 6 m, plywood hoarding 2.4 m, dumpster 1.8 x 1.1 x 1.3 m | ok | 20 ft fire access: https://codes.iccsafe.org/content/IFC2018/chapter-5-fire-service-features (503.2.1); 8 ft construction fences; 2 yd3 front-load dumpsters ~1.8 x 1.1 x 1.2 m |
| Manholes, bollards, trees, benches on the walk | none | not added | (left to do) |

### Buildings

| What | Was | Now | Source |
| --- | --- | --- | --- |
| Shop floor | 4.5 m floor to floor, shopfronts in 5 m bays, glass 0.36-3.5 m, fascia over | ok | retail ground floors 4.5-6 m [CTBUH]; stall risers 0.3-0.45 m |
| Brick walk-ups (A, A2, D1) | 3.6 m floor to floor (A's roof 22.5 m) | 3.3 m (pre-war: 3.0 m ceilings and the floor; A's roof 21.0 m, A2 14.4 m, D1 17.7 m) | residential 3.1 m floor to floor [CTBUH]; pre-war ceilings 9-10 ft |
| Concrete apartments (B) | 3.6 m (roof 33.3 m) | 3.1 m (29.3 m) | [CTBUH] 3.1 m |
| C2, D2, E2 | 3.5, 3.1, 3.2 m | ok | |
| Offices (C1, E1 tower) | 4.2, 4.1 m; E1's lobby 8.2 m; E1 160 m on 40 x 40 m | ok | office 3.9 m floor to floor [CTBUH]; slenderness 4:1 |
| Windows, homes | 40 % of the bay, 50 % of the storey: 1.2 x 1.5 m in 3.0 m bays but 1.68 x 1.8 m on B's 4.2 m bays, sill 1.08 m at 3.6 m | 1.2 x 1.5 m on a 0.9 m sill whatever the bay and storey | typical 0.9-1.2 x 1.4-1.6 m, sill 0.9 m (IRC R312.2: 24 in minimum) |
| Windows, masonry | 42 % of the bay: 1.1 x 2.05 m (A's front), 1.64 m wide on its 3.9 m alley bays, sill 0.9 m | 1.1 m wide, sill 0.85 m, up to 2.0 m tall (1.75 m in 3.3 m storeys) under a 0.7 m lintel and floor | pre-war double-hung sash 3-3.5 ft x 5.5-6.5 ft |
| Curtain walls | 1.5 m modules, 90 mm mullions, vision glass 1.1-4.0 m over each floor (desks would float 1.1 m up) | 1.25 m modules on C1 and E1 (they fit the corners), 64 mm mullions, vision glass from the floor to a 2.9 m ceiling, spandrel over the plenum and slab edge | 1.2-1.5 m modules, 2.5 in mullions (e.g. Kawneer 1600); ceilings 2.7-2.9 m |
| Bays at corners | the grids ran from the world origin: windows and shopfronts cut by building corners (a 0.25 m sliver on A's front) | every facade's bays divide its walls corner to corner (A, D1, C2, E2 2.5 m; A2 3.33 m; B 2.75 m and 4.0 m with `win_mask` shifts; D2 3.08 m) | |
| Residents' door | 1.8 x 2.3 m over a lit shopfront | two 0.915 x 2.13 m leaves, a transom, a steel lintel, in its own bay | 36 x 80-84 in doors; [IBC] 1010.1.1 |
| Roof door | 0.92 x 2.05 m, handle 1.05 m | ok | 36 x 80 in; hardware 34-48 in [ADA] 404.2.7 |
| Parapet | 0.3 m brick, 1.1 m over the roof, 60 mm coping 50 mm proud | ok | guards 42 in (1067 mm) [IBC] 1015.3 |
| Bulkhead | 5 x 5 x 3 m | ok | |
| Bulkhead ladder | rails 0.46 m apart, rungs every 0.3 m, 0.18 m off the wall, rails 1.07 m over the top | ok | 16 in clear width, 12 in rungs, 7 in behind, 42 in extension [OSHA] 1910.23 |
| Water tank | 4.6 m across, 4.2 m of staves, on a 3.2 m steel stand | ok | NYC timber tanks 10-30 thousand gallons: https://en.wikipedia.org/wiki/Water_tower |
| Condensers, exhaust, vents | 2.2 x 1.3 x 1.2 m units, 1.6 x 1.0 x 3.0 m exhaust, 0.16 m vents 1.4 m high | ok | vents 6 in or more over a roof: https://codes.iccsafe.org/content/IPC2018/chapter-9-vents (904.1) |

### Fire stair

| What | Was | Now | Source |
| --- | --- | --- | --- |
| Risers, treads | risers 0.181 / 0.18 m (over 178 mm), treads 0.273 m on the first storey (under 279 mm), 0.333 m above | treads 0.3 m everywhere, risers 0.174 m (first storey, its lower flight 13 treads from under the first floor landing) and 0.15 m | risers 4-7 in, treads 11 in or more [IBC] 1011.5.2; 2R + T 0.6-0.65 m |
| Width, landings | lanes 1.1 and 1.15 m (1.0 m clear), landings 1.2 m deep | ok | 36-44 in [IBC] 1011.2; landings as deep as the stair is wide 1011.6 |
| Guards | 1.07 m, a mid rail at 0.55 m, pickets every 0.3 m | 1.07 m, a bottom rail, 12 mm pickets 0.1 m apart | 42 in high 1015.3; no opening a 4 in (102 mm) sphere passes 1015.4 |
| Handrail | 0.86 m over the nosings | ok | 34-38 in [IBC] 1014.2 |
| Windows onto it | sill 0.8 m over each floor landing | ok (the 3.3 m storeys: `win_mask` v shift) | |
| Bulbs | 3.1 m over each floor | 2.8 m (under the 3.3 m storey's landing, over the window head) | |

### Backdrop

| What | Was | Now | Source |
| --- | --- | --- | --- |
| Buildings | ~4700 boxes: homes 2.9-3.3 m storeys (3 m bays), masonry 3.3-3.8 m (2.6 m), offices 3.8-4.2 m (1.5 m), shops 4.5 m; 10-320 m | ok (their windows in metres as above) | [CTBUH] |
| Suspension bridge | towers 125 m over the water for a 130 m main span (twice too tall: a sag of 1:1.4), deck 30 m | main span 220 m between towers 10 m in from the banks, 55 m side spans to anchorages at the streets on the banks, towers 60 m (30 m over the deck: sag 26 m, 1:8.5), deck 24 m wide, 30 m over the water | sag 1:8-1:12: https://en.wikipedia.org/wiki/Suspension_bridge ; Manhattan Bridge 448 m span, towers 102 m, 41 m clearance: https://en.wikipedia.org/wiki/Manhattan_Bridge |
| Expressway | 24 m deck at 12 m on 3 x 3 m piers every 30 m, LED lamps 10 m over the deck every 40 m | ok | 6 lanes of 3.6 m with shoulders |
| Aircraft warning lights | steady 32 cd over 45 m, flashing 2000 cd only over 150 m; the bridge towers steady | flashing medium intensity red (2000 cd, 40 a minute) on everything over 45 m (the bridge towers too), steady 32 cd on some 30-45 m roofs | low intensity under 45 m, medium intensity 45-150 m: ICAO Annex 14 vol. I 6.2; L-810 steady to 150 ft, L-864 flashing above [FAA] ch. 4 |

## Scale QA

`QA_FIGURES=1` (debug builds only) puts grey figures of a person (the
entity rig's own mesh in its rest pose, unstretched, 1.681 m scaled to
1.75 m) by an avenue lamp, a street lamp, the street door, a shopfront, a
hydrant, the bus shelter, a signal pole, on both crosswalks, on a fire
stair landing, in the alley, at the parapet and at the roof door, and
adds a `scale_*` view of each to `shots()`; run `level_shots` with
`--set graphics/human_eye=false` for the eye (1.62 m, plain lens) and
without it for the body cam (chest, 128 degree fisheye).

## Rain

It never stops raining in the Blue Hour, yet the sky is clear blue: no
clouds anywhere (docs/OPEN_WORLD.md). Settings > Rain turns it off
(`graphics/rain`, default on); Potato and Low draw a lighter rain (1500 +
500 drops, 200 splashes, 96 drips instead of 4000 + 1600, 600, 240).

| What | Real value | Source | Here |
| --- | --- | --- | --- |
| Rain rate | moderate 2.6-7.6 mm/h | AMS Glossary, "Rain" | 6 mm/h |
| Drop sizes | N(D) = 8000 exp(-4.1 R^-0.21 D) /m3/mm | Marshall & Palmer 1948 | lambda 2.81 /mm: 696 drops of 0.5 mm and up per m3, mean 0.86 mm, drawn up to 4.5 mm |
| Fall speed | 2.0 (0.5 mm), 4.0 (1), 6.5 (2), 8.0 (3), 9 (4.5 mm) m/s | Gunn & Kinzer 1949; fit v = 9.65 - 10.3 exp(-0.6 D), Atlas et al. 1973 | the fit, per drop |
| Wind | light air to light breeze | | 1 m/s from the west-north-west (+-20 % per drop): ~15 degree slant |
| Streak length | v x exposure time | Garg & Nayar 2007 | the night camera's 1/8 s (four merged 1/30 s frames): 0.25-1 m |
| Streak opacity | D / (v t) of the exposure x D / pixel width | Garg & Nayar 2007 | D^2 / ((v t + w) w), w = drop or 2.5 px |
| Drop brightness | what it scatters: I cos^m / d^2 x phase; plus its surround, inverted over ~165 degrees | Garg & Nayar 2004; Mie / geometric optics of water spheres | 8 nearest lights + 8 lit signals, phase 0.88 HG(0.85) + 0.12 HG(-0.3); surround: the probe light x 0.2, the sky looking up |
| Impacts (1 mm and up) | 852 /m2/s at 6 mm/h | integral of N(D) v(D) | splashes (60 ms crowns) within 6 m; rings on the water |
| Ripple rings | capillary waves 2-3 cm, ~0.2 m/s, gone in ~0.5 s | | 0.2 m cells (two layers) + 0.33 m cells, one ring a cycle each |
| Scattering by the rain | 5.6e-4 /m (geometric cross-section) | integral of N(D) pi D^2 / 4 | half of it added to the haze's in the lamps' airglow |
| Drips | a pendant drop leaves an edge at ~4.5 mm | (capillary length of water, 2.7 mm) | grows 0.4 s, falls with drag to 9 m/s terminal, splashes |
| Lens drops | 696 /m3 x speed toward the lens x a 12 cm2 window | | 0.8/s standing facing the wind, ~2/s walking into it, none under cover |

Where it does not rain (boxes in level space): under the bus shelter's
roof (x -13.8..-11.4, z -38.2..-31.8, under 2.55 m), the fire stair (x
45..47.6, z 12.4..17.8, under its top landing at the roof), the water tank
on its stand. Drips fall from the shelter roof's long edges, under the
stair's lowest landing and half landing, the four signal mast arms, the
tank roof's eaves, the parapet coping over both streets and the bulkhead's
coping. Sound: rain on hard surfaces everywhere (6 dB down under cover),
patter on the metal of the shelter roof and the stair's landings, drips
under the shelter's edge and the stair (procedural placeholders, see
LICENSE.md).

## What happens

- Signals cycle (60 s) at the crossing and at ~150 crossings down the
  avenue and the street, on a green wave (offset by the travel time at
  12 m/s); the near ones tick (accessible pedestrian signals).
- The sodium lamp at the alley's mouth is failing: it goes out, cools,
  restrikes with the igniter's ticking, glows pinkish and slowly warms to
  orange. Its baked pool dims and returns exactly (a relightable slot).
- Aircraft beacons on the towers flash; a siren wails far away every
  minute or two, from a random direction 300 m off.
- The camera exposes and balances like a phone filming at night (see
  docs/LUCID.md, stage 3).
- It rains (above), and the body cam's lens collects drops that run and
  dry.

## Performance (Realistic preset, worst view of the harness)

Draw calls 19-29, primitives 102k-154k (lavapipe, 1280 x 720; the steel
fire stair is ~13k of it). The Lobby
on Realistic draws 210-472 calls. (The audit's pickets, mast arms,
pedestrian heads and third barricade rails: baked vertices 65.5k ->
70.7k; over the harness's 29 views primitives 139.0k -> 141.7k on average,
153.6k -> 156.7k at most, draw calls unchanged.) Up to 4 real lights (the nearest lamps,
specular only on baked surfaces) plus the moon, no real-time shadows,
textures 1024 px or less (VRAM compressed, mipmaps), assets ~4 MB.

Rain (Realistic, body cam on, lavapipe 1280 x 720, mean of 60 frames, on
vs off at the crossing, under a head, in the alley, under the shelter):
one draw call more (28 -> 29 at the crossing), +12.9k primitives (6440
quads, all placed in the vertex shader; Potato and Low 2296 quads), frame
time 349 -> 381 ms (+9 %, relative only; the ripples are a few ALU per wet
pixel, the lens drops a loop inside the body cam's existing pass). Sounds
+0.4 MB.

## Left to do

- Real CC0 recordings for the city sounds and the rain (Freesound was
  unreachable; the rain's are procedural placeholders).
- Parked cars, trees, street furniture variety (manholes, drain inlets,
  bollards, benches); curb ramps at the crosswalks; interiors behind the
  shop windows (now a procedural glow).
- The backdrop's buildings are boxes with procedural facades; crowns and
  setbacks are simple.
