# Level 4.1 - The Endless Stairwell (`stairwell`)

A concrete service / exit stair in a painted block shaft, at night, going
down. B2, B3, B4... it doesn't stop, and the numbers stop making sense.
The lights get fewer and fail the deeper you go. A door slams somewhere
below; footsteps come up toward you and stop a flight and a half short; a
hand rests on the guard rail two floors down, and it is always two
floors down. No entity catches you: this is the dread level. At the bottom
the stair runs down into black water.

Files: `scripts/world/levels/stairwell_level.gd` (the level),
`scripts/world/levels/stairwell_entrance.gd` (B2's door leaf),
`tools/blender/levels/stairwell.py` (kits, bake, textures, signs, sounds),
this folder (kits, group lightmaps, textures, audio, `stairwell_lit` and
`stairwell_water` shaders, LICENSE.md), `_test/levels/stairwell_test.tscn`.

## How you get here, how you leave

- **From the Stacks** (Level 1.1): STAIR 2, the door at the far (north) end
  of the Stacks' corridor B ("Take the stairs down"). Corridor B is reached
  only through moving shelving, so the stair is as deep in that maze as its
  exit (see the Stacks' SPEC.md). You arrive on **B2**, the top landing,
  with its door shutting behind you on its closer.
- **From the Backrooms**: the registry's entrance, unchanged: a door signed
  STAIRS in a GARAGE wall on floor -1 ("Take the service stairs"). Same
  arrival.
- **Back out**: B2's door ("Open the door"): the Backrooms, somewhere else.
- **On**: at the bottom (B58 by the count) the stair runs into water; wade
  in past 0.85 m and you go on into the flooded basement (`NEXT =
  "flooded"`; until that level exists the framework's placeholder room
  stands in for it).
- **Going back up** is honest: every flight you went down is a flight to
  climb back (as long as the descent, over three minutes from the bottom:
  not a cheap escape), and B2's door lets you out. Decided so because the
  dread is in choosing to go on, and a stair that traps you going up would
  turn a dread level into a puzzle with an unfair fail; the cost of the way
  back is its length.
- Nothing catches you, nothing kills you (`catch_player` is never called;
  the guards are too high to vault: `player.can_climb = false`).

## Real reference: an IBC egress stair

All values used exactly (Blender metres in `stairwell.py`, the same in the
level script). Sources were read on 2026-11-11.

| What | Value used | Code / source |
| --- | --- | --- |
| Riser | 7 in = 177.8 mm (the maximum), 9 a flight | IBC 1011.5.2: "Stair riser heights shall be 7 inches (178 mm) maximum and 4 inches (102 mm) minimum" ([CBC 2022 s. 1011, adopting IBC text](https://gocodebook.com/library/us/ca/ca-building-code/chapter-10-means-of-egress/section-1011-stairways)) |
| Tread | 11 in = 279.4 mm (the minimum) | IBC 1011.5.2: "Rectangular tread depths shall be 11 inches (279 mm) minimum" (same page) |
| Floor to floor | 18 risers = 3.2004 m (10 ft 6 in), two flights of 1.600 m | within the 3.0-3.7 m brief; IBC 1011.8: a flight rises no more than 12 ft (3658 mm) between landings (same page) |
| Clear width | 44 in = 1118 mm, wall face to the guard's inner face | IBC 1011.2: "the minimum width shall be not less than 44 inches (1118 mm)" (same page) |
| Headroom | 3.0 m everywhere (the slab over each landing at H - 0.2) | IBC 1011.3: not less than 80 in (2032 mm) from the nosing line (same page) |
| Landings | 60 in (1524 mm) deep at the doors, 48 in (1219 mm) at the half landings, the shaft's full width | IBC 1011.6: width not less than the stair's, depth the stair's width or 48 in (1219 mm), whichever is less; "Doors opening onto a landing shall not reduce the landing to less than one-half the required width" (same page): the 36 in leaf swinging over the 60 in landing leaves 24 in > 22 in |
| Nosing | 1 in projection | IBC 1011.5.5.1: "not more than 1 1/4 inches (32 mm)" (same page) |
| Nosing stripe | 2 in (51 mm), safety yellow, on every tread's and landing's leading edge | IBC 1025.2.1: stripes 1 in min., 2 in max. on the leading edge of each step ([CBC s. 1025](https://gocodebook.com/library/us/ca/ca-building-code/chapter-10-means-of-egress/section-1025-luminous-egress-path-markings)); colour ANSI Z535.1 safety yellow, Munsell 5Y 8/12 ([Munsell, ANSI colours](https://munsell.com/color-products/color-standards/munsell-ansi-color-standards/)), linear albedo (0.82, 0.55, 0.02) |
| Handrails | 36 in (914 mm) over the nosings, both sides, 1 1/2 in round, 1 1/2 in clear of the wall, black enamel; the inner one continuous round the well, the wall ones extended 12 in level at the top and one tread on the slope at the bottom, returned to the wall | IBC 1014.2: "not less than 34 inches (864 mm) and not more than 38 inches (965 mm)"; 1014.6: "extend horizontally not less than 12 inches (305 mm) beyond the top landing nosing and continue to slope for the depth of one tread beyond the bottom tread nosing"; 1014.7: clearance 1 1/2 in ([CBC s. 1014](https://gocodebook.com/library/us/ca/ca-building-code/chapter-10-means-of-egress/section-1014-handrails)) |
| Guards | 42 in (1067 mm) along the well, 1/2 in balusters at 110 mm (97 mm clear), grey-green enamel | IBC 1015.3: "not less than 42 inches (1067 mm) high"; 1015.4: no opening passing a 4 in sphere ([CBC s. 1015](https://gocodebook.com/library/us/ca/ca-building-code/chapter-10-means-of-egress/section-1015-guards)) |
| Well | 0.75 m between the flights | design choice: wide enough to look down several floors (the hero view), guarded on every side |
| Fire doors | 3070 hollow metal, 36 x 84 in, a 10 x 10 in (100 sq in) wired-glass vision panel | 100 sq in limit for fire-protective glazing in stair doors (NFPA 80, as summarised by [SAFTI: size limits](https://safti.com/articles/size-limits-for-vision-panels/) and [CDF: vision panel ratings](https://www.cdfdistributors.com/blog/post/vision-panel-fire-rating-requirements-commercial-doors), 10 in maximum dimension) |
| Stair identification sign | 18 x 12 in, its bottom 60 in (1524 mm) up, beside the door: STAIR 2 at the top, the floor number (5 in) in the middle with B for a basement, NO ROOF ACCESS, the termini (B2 - B__) and EXIT DISCHARGE LEVEL 1 UP at the bottom | IBC 1023.9 / 1023.9.1 ([CBC s. 1023](https://gocodebook.com/library/us/ca/ca-building-code/chapter-10-means-of-egress/section-1023-interior-exit-stairways-and-ramps)) |
| Walls | painted CMU, 8 x 16 in units (7 5/8 x 15 5/8 in + 3/8 in joints), running bond; courses drawn at 200 mm so a storey is exactly 16 (the joints carry on from storey to storey) | [NCMA TEK 2-1A via Angelus Block](https://angelusblock.com/resources/cmu-basics/dimensions-and-sizes/) |
| Fixtures | a 2 ft two-lamp T8 stairwell wall fixture over every landing door and on the half landing's wall: 2 x F17T8/841 at 1325 lm, ballast factor 0.88, light loss 0.8 (old lamps, a dirty lens): 1866 lm, Lambertian over the wraparound lens (0.19 m2): 3103 cd/m2 | F17T8 1325 initial lumens ([TCP F17T8 spec sheet](https://www.tcpi.com/wp-content/uploads/2017/04/31017741-Spec-Sheet-1.pdf)); 2-lamp stairwell fixtures with emergency ballasts ([TCP stairwell fixture](https://www.commercialbulbs.com/item/0025355/tcp-st4l2nml120b5-stairwell-fixture-4-low-ballast-factor-2-lamp)) |
| Light on the landings | about 140 lux under a working fixture (bake: E / pi in engine units ~0.29) | IBC 1008.2.1: "Along exit access stairways, exit stairways and at their required landings, the illumination level shall not be less than 10 footcandles (108 lux)" ([CBC s. 1008](https://gocodebook.com/library/us/ca/ca-building-code/chapter-10-means-of-egress/section-1008-means-of-egress-illumination)); on emergency power 1 fc average, 0.1 fc minimum, 90 min (same) |
| Player | eye 1.62 m, walk 2.6 m/s | `Player.EYE`, `Player.WALK` |

Derived: a flight's going 8 x 11 in = 2.235 m; shaft inside 3.085 x 4.978
m (two 1.168 m flights and the 0.75 m well; 60 in + 2.235 m + 48 in).

## Layout (one storey; Blender x across, y from the door wall, z up)

```
 y=4.98 +--------------------------------------+   north wall: half-landing fixture
        |           half landing (z 1.60)       |
 y=3.76 +-----------+--------+-----------------+
        | U2: up    |  well  | U1: up          |   U1 rises north from this landing
        | south to  | 0.75 m | to the half     |   U2 rises south from the half landing
        | the next  | guards | landing         |   to the landing above (z 3.20)
        | landing   |        |                 |
 y=1.52 +-----------+--------+-----------------+
        |        landing (z 0)  guard across   |
        | [sign]   [ fire door ]   B14 stencil |   door wall: the landing fixture over the door
 y=0    +--------------------------------------+
       x=0         1.17    1.92              3.09
```

Going down from a landing: across it to the west, down U2 (north) of the
storey below, round the half landing, down U1 (south) to the next landing's
east side, facing its door wall: the stencilled number and the sign are in
front of you.

## Endless, cheaply: the recycled stack

Seven storeys of the one kit stand in a fixed stack round you (two above,
four below; `J0 .. J1`). Slot 0 shows the storey you're on (`base`). When
you're more than half a storey plus 0.3 m below slot 0's landing (on the
second flight down) the stack moves: you go back up by exactly one floor
height (`Player.shift_y`, which also carries your last safe position and
the torch's rig), sounds in flight go with you, and every slot shows the
storey next to the one it showed (its stencil and sign, its lamps' light
multipliers, its door, which slot has B2's exit door, the hand, the water).
Going up is the same the other way. The stack is identical slot to slot,
collision included, so nothing you can see or touch moves; the test walks
it and measures (see Tests). Stair coordinate: `u = base - (y - LEVEL_Y) /
H` (landing n at n.0), continuous across shifts.

The top storey (B2) is its own kit (`stair_top`): no flights up, the
shaft's roof slab over it, a guard across the drop where the up flight
would be; the slots above it are hidden (and their collision off). Below
B58 nothing is shown (it's under the water).

Collision is built in code per slot (`_unit_body`): the landing and half
landing slabs, each flight a smooth slope through its landings' edges
(35.6 degrees, under the player's 50 degree floor limit; the player walks
it both ways like the Backrooms' own stairwells), the walls, the guards
(sloped along the flights, across the well's ends).

## The floors (`label(n)`)

B2 .. B12; then **B14** (no 13) .. B27, **B27 again**; B28 .. B44; then
B47, **B112, B113**, B47, B48, B49, **B9**, B51, B52, B53, **B--, B--**,
B5; the water. The floor counter (`storey()`) is the true storey; the
stencil (420 mm, sprayed, with a stencil's bridges) and the sign show the
label.

## Light

L.U.C.I.D. units (docs/LUCID.md): every lens is an emitter of its real
luminance (3103 cd/m2, stored as cd/m2 / 153.6 = 20.2), baked in Cycles
(`stairwell.py`, 160 samples, 1024 px group map for the storey, 512 px for
the top). Every lamp can fail, so there is no colour bake: four light
groups, all in the group map: R the storey's landing fixture, G its
half-landing fixture, B the storey above's two, A the storey below's two
(the storey is baked with copies of itself above and below in the scene:
they shade it, bounce light, and carry those lamps). Each slot's meshes get
their own four multipliers (an instance uniform, `unit_light`, in
`stairwell_lit.gdshaderinc`) from the lamps of that floor and its
neighbours, times the lamps' colour (F17T8/841, 4100 K, Duv +0.003, under a
4300 K white balance, normalised; passed as a Vector3). So one kit, seven
floors' lights, 0 real-time lights (the torch aside). The stencils and the
hand have no bake: fixed shares of the channels (`group_mix`).

Lamps by depth (`lamp_kind`): all burn down to B5; below, the chance a
fixture is dead rises smoothly to 92 % near the bottom; of the rest more
and more have a failing ballast (`_flicker`: drop-outs, stutter, the
cathodes' glow, restrike, each fixture its own pattern, with the ballast's
tick-and-buzz when one near you drops out) or burn dim on a battery pack.
The first time you reach a floor, a failing fixture just below it may give
up as you come down to it (a last stutter, the cathode's pop and fizz).
At the bottom B58's two fixtures still burn on their battery packs, over the water.
Each burning fixture near you hums (120 Hz ballast).

The body cam's exposure meters the fixtures round you (inverse square) and
the torch on what it points at, and adapts (slow up, fast down).

## Scares

- **The numbers**: see above.
- **Lights thinning**: see above.
- **A door slams below** (first reaching B6, B17, B29, B41, B52): three
  floors down, 2.5-4.5 s after you arrive: the closer's sweep, the leaf on
  its stops, the latch, the shaft ringing for 3 s; a jolt of camera shake;
  that floor's lamps jump.
- **Footsteps coming up** (first reaching B9, B22, B35, B47): hard soles
  on concrete stairs, four floors down, climbing a storey every 5.5 s, a
  step every half second, along the stair; they stop a flight and a half
  below you. Go down to meet them and they've stopped already.
- **The hand** (from B7): on the top rail of the inner guard two floors
  down (U2's, three quarters of the way up it, where a look down the well
  through the landing's guard reaches it), fingers curled over the rail
  into the well, a grey forearm and a dark sleeve going back down into the
  flight. It is in the slot two below you, so it is always two floors down
  however far you go (two, not three: from a landing, through the guard,
  6.4 m is as far down the well as a hand still reads as a hand). Look at
  it for 2 s and it slides back off the rail; it's there
  again two floors further down.
- **The doors**: every landing's door is locked ("Try the door": the lever
  stops, the latch knocks; now and then something on the other side lets
  go of the handle).
- B2's door shuts behind you as you arrive (a hydraulic closer's sweep,
  slowing, the latch speed's last few degrees, the latch).

## Sound

Real recordings were not available (Freesound blocks automated access), so
every sound is synthesised by `stairwell.py --sounds` as a documented
placeholder, like the other levels: noise shaped in the frequency domain
with smooth log-frequency bands (no sine blips, no resonant filters), loops
periodic by construction, and the shaft's long hard echo (T60 about 3 s,
the highs dying faster) convolved into what's heard from far down the
shaft. `shaft_loop` (the stack effect's roar), `hum_loop` (a magnetic
ballast), `flicker_1..3`, `lamp_die`, `rattle_1..2` (locked doors),
`door_slam`, `door_shut`, `step_1..4` (footsteps on concrete stairs, from
below), `water_loop`. Your own footsteps are the game's concrete steps with
the level's reverb (`room 0.95, damp 0.12, wet 0.42`).

## The bottom

B58 by the count (56 storeys below B2, 179 m): the stair runs down into
still black water 1.2 m deep over B58's landing (its door half under); the
half landing above it is 0.4 m clear of it; B58's fixtures still burn on
their battery packs, dim: the one over the half-drowned door lies in the
water as a glint (the reflected view ray against the lens's rectangle,
broken up by a slow shiver of ripples, times Fresnel), the torch's beam
dull on the black. Why 56 storeys: at a walk a storey
takes 3.4 s here (the test measures it: 189 s from B2 to the water at a
walk), so the descent is a bit over three minutes of walking (a real stair at a real pace would be
twice that): long enough that going down is a decision and coming back up
is not cheap, short enough to play.

## Cost

Harness (`level_shots.tscn -- stairwell`, Realistic preset, 1280 x 720):
the worst view is looking down the well (`well_down3`): 13 draw calls,
12.3k primitives; a landing 4-5 draw calls, 4.5-6k primitives (the stack
is 7 storeys of one 2,016-triangle kit, five surfaces each, plus the
numbers; storeys out of view are culled). 0 real-time lights (the torch
aside). Textures 256-1024 px, VRAM compressed, mipmapped (the group maps
lossless). Assets: 3.0 MB (`du -sh assets/levels/stairwell`).

## Tests

`_test/levels/stairwell_test.tscn` (see its header): arrival through the
Stacks' STAIR 2 and through the garage's STAIRS door, the descent and the
climb with the real controls (on the floor every frame, no seam across any
recycle, the counter matching), the whole way down into the water, a
locked landing door, out through B2's door.

## Left to do

- Real recordings (CC0) for the footsteps, slam and ballasts.
- Remote players: each client recycles its own stack, so another player in
  the stair is drawn at their real height relative to yours only when on
  the same storey.
- The flooded basement (`flooded`) itself.
