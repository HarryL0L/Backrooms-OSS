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
stage 3.

## Layout (level space: metres, X east, Z south, ground 0 at the crossing)

```
              z -70  D1 brick 5 st (shops)    D2 7 st
   E2   E1 office tower 160 m          |avenue|
        (plaza in front, -70..-15)     | x=0  |
  ------- street (z = 0, 12 m carriageway, 4 m sidewalks) ---------
   C2 5 st   C1 office 12 st    |      |  A (yours) 6 st | alley | B 9 st
                                |      |  roof 22.5 m    | 45-51 |
              z +70             |      |  A2 4 st        | stair |
```

- Grid: avenues along Z every 110 m, streets along X every 80 m
  (`LucidCity.GRID`), the same everywhere to the horizon.
- Roof: A's roof at 22.5 m, parapet 1.1 m with a gap to the fire stair's
  top landing; bulkhead 5 x 5 x 3 m with the roof door (arrival) and a
  caged bulb; water tank 4.6 m across on a 3.2 m stand; condensers, vents.
- Fire stair: on A's east wall in the 6 m alley, two flights a storey
  (3.0 m run each), landings 1.2 m, rails 1.07 m; bulbs at each storey.
  Built like a real steel one: 200 mm channel stringers, open bar-grating
  treads with nosing angles, grating landings in 150 mm channel frames on a
  ledger angle bolted to the wall and on four 80 mm columns, knee braces
  under the half landings, guards (top rail, mid rail, pickets every 0.3 m)
  on every open side, a wall handrail on the inner flights. A window opens
  onto each floor landing, none behind the flights (A_side `win_mask`).
- Bulkhead: a steel ladder up its north face to its roof.
- Bounds: barricades at x = +-86 and z = +-61 (invisible walls behind
  them), the alley's plywood hoarding at z = 46.
- Backdrop: ~5700 instanced buildings to 5.5 km (all of them within 1.3
  km, only taller ones further), two downtown clusters (one across a
  river 1.5 km west, with a suspension bridge), an elevated expressway
  385 m east, ~14000 point lights (lamps, beacons, signals, the bridge's
  cable lights).

## Real-world values (and where they come from)

| What | Value | Source |
| --- | --- | --- |
| Traffic lane | 3.5 m (11-12 ft) | FHWA lane width: https://safety.fhwa.dot.gov/geometric/pubs/mitigationstrategies/chapter3/3_lanewidth.cfm ; NACTO: https://nacto.org/publication/urban-street-design-guide/street-design-elements/lane-width/ |
| Parking lane | 2.5 m (7-9 ft) | NACTO, same guide |
| Sidewalks | 5.5 m on the avenue, 4 m on the street (downtown 4-6 m) | NACTO sidewalks: https://nacto.org/publication/urban-street-design-guide/street-design-elements/sidewalks/ |
| Curb | 150 mm (6 in) barrier curb; corner radius 4.5 m | NACTO corner radii: https://nacto.org/publication/urban-street-design-guide/intersection-design-elements/corner-radii/ |
| Street lamps | avenue: LED 100 W, 13000 lm, 4000 K, 10 m poles, 2.5 m arms, opposite pairs every 35 m; street: HPS 150 W, 12000 lm, 2100 K, 8 m, every 30 m (spacing 3-4 x mounting height) | Lucid.FIXTURES sources in docs/LUCID.md; spacing: https://en.wikipedia.org/wiki/Street_light |
| Storey heights | shops 4.5 m, homes 3.0-3.6 m, offices 3.8-4.2 m | CTBUH height criteria (3.1 m residential, 3.9 m office floor to floor): https://www.ctbuh.org/resource/height |
| Windows | homes 1.2 x 1.5 m in 3.0 m bays, masonry 1.1 x 2.0 m in 2.6 m bays, curtain wall 1.5 m mullion spacing | common residential / curtain wall module sizes |
| Parapet, rails | 1.1 m parapet, 1.07 m stair rails (42 in guards) | IBC 1015.3: https://codes.iccsafe.org/content/IBC2018/chapter-10-means-of-egress |
| Stair | risers 0.17-0.18 m (IBC max 7 in = 178 mm) | same |
| Door | 0.92 x 2.06 m (36 x 81 in) | standard door size |
| Signals | 300 mm LED heads, red 365 cd, yellow 910, green 475 (on axis); cycle 60 s: avenue green 30, yellow 4, all-red 2, street green 20, yellow 4 | ITE VTCSH: https://www.ite.org/technical-resources/standards/ ; yellow 3-6 s: MUTCD 4D.26 https://mutcd.fhwa.dot.gov/htm/2009/part4/part4d.htm |
| Pedestrian signals | hand 3750 cd/m2, walking person 2200 cd/m2; locator tone once a second, rapid tick during WALK | ITE PTCSI; MUTCD 4E.11: https://mutcd.fhwa.dot.gov/htm/2009/part4/part4e.htm |
| Aircraft warning lights | steady red 32 cd over 45 m, flashing red 2000 cd (40/min) over 150 m | FAA AC 70/7460-1M (ICAO Annex 14 equivalent): https://www.faa.gov/documentLibrary/media/Advisory_Circular/Advisory_Circular_70_7460_1M.pdf |
| Failing HPS lamp | on 80 s, out (arc drops as the lamp's voltage rises), 45 s to cool, restrike dim and pinkish, 75 s warm-up | sodium lamp end of life "cycling": https://en.wikipedia.org/wiki/Sodium-vapor_lamp |
| Night sky | zenith 0.04 cd/m2 (16.1 mag/arcsec2, ~230 x natural), horizon 0.24 cd/m2 | Falchi et al. 2016: https://www.science.org/doi/10.1126/sciadv.1600377 ; conversion: http://www.unihedron.com/projects/darksky/magconv.php |
| Moon | 0.18 lux, disc 2800 cd/m2, 20 deg up in the WSW | full moon 0.1-0.3 lux (docs/LUCID.md [7]) |
| Haze | extinction 3.3e-4 /m (12 km visual range, 3.912 / V) | Koschmieder: https://en.wikipedia.org/wiki/Visibility |
| Lit windows | office 25 cd/m2 (4000 K), home 12 (2900 K), closed shop's night lights 40 (3500 K); ~30 % lit | Lucid.FIXTURES (reasoning there) |
| Albedos | asphalt 0.09, sidewalk concrete 0.30, red brick 0.21, light concrete 0.38-0.45, roof membrane 0.30 | asphalt 0.05-0.12 aged: https://en.wikipedia.org/wiki/Albedo |

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

## Performance (Realistic preset, worst view of the harness)

Draw calls 19-29, primitives 102k-154k (lavapipe, 1280 x 720; the steel
fire stair is ~13k of it). The Lobby
on Realistic draws 210-472 calls. Up to 4 real lights (the nearest lamps,
specular only on baked surfaces) plus the moon, no real-time shadows,
textures 1024 px or less (VRAM compressed, mipmaps), assets ~4 MB.

## Left to do

- Real CC0 recordings for the city sounds (Freesound was unreachable).
- Parked cars, trees, street furniture variety; interiors behind the shop
  windows (now a procedural glow).
- The backdrop's buildings are boxes with procedural facades; crowns and
  setbacks are simple.
