# Level 2.1 - The Crawlspace (`crawlspace`)

The supply trunk of an office floor's air system, above its suspended
ceiling, at night. Galvanised rectangular duct you can only crawl through,
lit by your torch and by what comes up through the registers from the
offices below, which are still lit and empty. You get in through a wall vent
in the Backrooms (LOBBY / PIPES, registry entrance) and get out by pushing
the return grille at the far end out of the ceiling and dropping into the
office (`exit_entered("")`, back to the Backrooms).

Files: `scripts/world/levels/crawlspace_level.gd` (the level),
`tools/blender/levels/crawlspace.py` (builds and bakes `crawl_duct.glb` and
`crawl_rooms.glb`), `assets/levels/crawlspace/` (kits, lightmaps, textures,
audio, `dust_mote.gdshader`, this file, LICENSE.md).

## Real-world values (and where they come from)

Every size below is used as written, in the Blender script and the level.

| What | Value | Source |
| --- | --- | --- |
| Trunk, clear inside | 36 x 30 in = 914 x 762 mm ("duct sizes shown are clear inside dimensions") | Texas State Univ. spec 23 31 00, construction item E: https://docs.gato.txst.edu/141175/23_31_00-HVAC-Ducts-and-Casings.pdf |
| Sheet | galvanised, 22 ga (0.85 mm) for 31-54 in largest side, low pressure | same spec, 2.03 B table (12" and less No. 26 ... 31"-54" No. 22) |
| Section length / joint spacing | 5 ft = 1.524 m (sections come in standard 4 and 5 ft lengths) | same spec (its 4 and 5 ft standard lengths clause); SMACNA reinforcement tool listing joint lengths of 4, 5, 6 ft: https://splitmetrics.com/apps/smacna-hvac-dcs/id716751022 |
| Transverse joint | rolled-on flange (SMACNA T-25a TDC / T-25b TDF), 35 mm profile, flange outside the duct (inside: the rolled edges and the gap, sealed) | Conklin, TDC vs TDF: https://www.conklinmetal.com/tdc-tdf-which-is-the-better-profile/ ; 35 mm TDF profile: https://systemaire.com.au/news.aspx?id=47 |
| Joint sealing | sealant + 3 in open-weave glass fibre tape bedded in it | Texas State spec 2.02 A |
| Cross-breaking | required: panel 19 in or wider with more than 10 sq ft unbraced (our 36 x 60 in = 15 sq ft, 30 x 60 in = 12.5 sq ft), 20 ga or lighter, up to 3 in w.g. | DAS CT / ITI duct construction slides: https://portal.ct.gov/-/media/das/oedm/design-and-trades/dt_mastropasqua_ducts.pdf ; crown 6 mm is our choice (not specified) |
| Hangers | 18 ga band iron straps screwed to the duct sides, 8 ft (2.44 m) centres (ducts up to 40 in) | Texas State spec 3.02 J.1 |
| Turning vanes | 2 in radius hollow vanes, 26 ga, on 2-1/8 in (54 mm) centres along the rail; rail 2-1/4 in | Duro Dyne vane & rail submittal: https://siglers.com/mwdownloads/download/link/id/9274 |
| Elbows | mitred (square) elbows with vanes where space dictates | Texas State spec 3.02 E.1 |
| Volume damper | opposed-blade, 6 in (152 mm) blades on ~6 in centres, 16 ga, 1/2 in shaft, 5 x 1 in hat-channel frame | Ruskin CD44 listing: https://www.kele.com/product/actuators-and-dampers/dampers/ruskin/cd44-36x16-ob-s |
| Access doors | 18 x 18 in, 24 ga, cam latch, gasketed | Acudor CD-5080 / Ductmate doors: https://shop.distributioninternational.com/specialty/hvac/hvac-access-doors/accd1818ca |
| Duct liner (insulated run) | coated black glass fibre; fasteners on 12 in centres | Texas State spec 3.08 A |
| Floor registers | 24 x 12 in lay-in eggcrate return, 1/2 x 1/2 x 1/2 in aluminium core, 1-1/4 in frame | Nailor 51EC: https://nailor.com/sites/default/files/documents/51EC-4A_B_3.PDF |
| Exit grille | 24 x 24 in fixed-bar return, bars at 45 deg on 3/4 in centres | TRUaire 270 series listing: https://www.pacesupply.com/Product/TRU27024X24 |
| Air speed in the trunk | 5-8 m/s (1000-1500 fpm) for main ducts in public buildings; the pops travel at 6 m/s | Engineering ToolBox: https://engineeringtoolbox.com/velocities-ventilation-ducts-d_211.html |
| Thermal pops | sheet expands/contracts with warm air and binds on its supports, then snaps: popping as heat comes on and goes off | This Old House, noisy ducts: https://www.thisoldhouse.com/heating-cooling/how-to-quiet-noisy-ducts |
| Office ceiling | 9 ft (2.743 m) floor to ceiling; plenum above | CISCA ceiling LCA (9 ft office): https://www.cisca.org/files/public/LCS_brochure_rev_9-08_lo-res.pdf |
| Ceiling tiles | 24 x 24 x 5/8 in lay-in on 15/16 in grid, LR ~0.82 | Armstrong Cortega listing: https://www.newegg.com/p/2BU-000P-00018 |
| Troffers | 2 x 4 ft LED, 32 W, ~4100 lm, 4000 K; three per office | Lithonia BLC listing: https://www.platt.com/p/1903274/lithonia-lighting/2x4-led-center-basket-troffer-4098l-40k/193048323511/litblc2x44000lm40 |
| Office light level | 300-500 lux general office (3 troffers in ~28 m2 gives ~270-300 lux at CU 0.6) | https://www.paclights.com/learning-center/standard-office-lighting-levels-explained/ |
| Fan | 28 in tube-axial, direct drive 1725 rpm (motor torque: up to speed in ~5 s; coasts down over ~20 s) | 1725 rpm is the standard 4-pole 60 Hz motor speed (nameplate value) |
| Furniture | desk 60 x 30 in, 29 in high; 4-drawer file 15 x 28 x 52 in; door 36 x 84 in; cove base 4 in | standard office sizes (BIFMA / common catalogues) |

Blender lighting: a troffer is an area light of 13.7 W radiant (4100 lm at
~300 lm/W luminous efficacy of radiation for 4000 K white LED), CCT 4000 K
as RGB (1.0, 0.92, 0.82). In the game the torch is the player's own beam at
0.45 of its Backrooms energy (a hand-held LED torch a hand's length from
sheet metal would otherwise burn out the view).

## Layout (Blender XY, metres; Godot (x, y, z) = (x, z, -y) round (0, -8000, 0))

```
                      n7 (4,46)  end cap
                       |  EXIT 24x24 at (4,44) over office 7
  w_end ---- n5 =lined= n6 (4,36)   <- the hand, from the s_end spur
  (-17,36)   |(-10,36)   |
             |  twin duct (knocks) 1.3 m west, y 24..36
             |  register (-10,31) faulty office (group 0)
  fan_end -- n3 (-10,24) ---- register (-5,24) ---- n2 (0,24) torn-vane elbow
  (-10,15)   damper y 20.6, fan y 18.2, register y 16 (plant room, group 1)
                                                  |
                                                  | access door
                                    n8 (9,12) == n1 (0,12) tee
                         whole vanes ||           |
                          (stub, register 9,15.6) | register (0,5.5), office 1
                                                  n0 (0,0) start: the wall grille you came in by
```

Main way: n0 - n1 - n2 - n3 - n5 - n6 - n7, about 70 m (93 s of crawling at
0.75 m/s); spurs: n1-n8 (ends in whole vanes), the fan spur, w_end, s_end.
Offices below: under each register (7 rooms), one dark, one whose lights fail
(group 0), the plant room behind the fan (group 1, chopped by its blades),
one with an occupancy sensor (group 2, off until you pass over), the exit
office (group 3).

## What happens

- Crawl foley: each pull of the crawl (player `footstep`) knocks an elbow or
  knee on the sheet (7 cuts of a real vent crawl), sometimes a brush of the
  body, and now and then the panel under you gives with a dull flex and a
  tiny jolt.
- Thermal pops: every 18-34 s, warm air reaches your stretch: the joints pop
  one after another from 4-10 m upwind to past you, at 6 m/s; the one beside
  you bangs, shakes the view and sheds dust from the seam (particles). A big
  run the first time you're halfway along n1-n2.
- Air pulses (a VAV box hunting): every 9-18 s the air swells for 3-5 s
  (louder, a touch higher), the motes drift faster down the duct and the
  damper flutters.
- Dust motes: specks that show only in the torch beam (forward scatter),
  drifting with the air.
- The fan: it windmills in the draught behind the damper; get within the
  spur and its motor starts (clunk, start-up recording), spins up to 1725 rpm
  (time constant 1.6 s, blur disc past ~5 rev/s), the damper blades shudder,
  the plant room's light through it is chopped by the blades (group 1) and
  goes steady; after 14 s it cuts out and coasts down (time constant 7 s).
- The twin duct: along n3-n5 something in the parallel duct knocks a beat
  behind each of your pulls (low-passed, from the west). Stop and it does two
  more, then stops; 4 s later one heavy bang right beside you. Leave the run
  without stopping and it goes on ahead and away.
- Lights below: the faulty office stutters every 5-13 s, sometimes drops out
  and its starter tries again (ballast recording); the occupancy-sensor
  office comes on 1.1 s after you pass over it (nobody's there) and goes off
  45 s later.
- The hand: a pale figure lies in the s_end spur with its left hand round the
  corner flat on n6's floor. When your torch finds it (within 4.6 m, looking
  along the run) or you get within 2.4 m: a beat, the fingers tighten, then
  it's snatched back (cubic ease-in to 2.8 m, the arm lifting off the floor,
  a roll of the body), dragging, then creaking away down the spur.
- The exit: Use on the return grille: you shove, it swings down on its last
  clip (two shoves, eased), drops the 2.74 m (0.75 s, tumbling), clatters and
  bounces on the carpet; you let yourself down through the hole, hang, drop
  and land, and the game takes you back to the Backrooms.

## Light, sound, budget

Baked light (Cycles, `level_kit.py`): two kits, 1024 px maps, the duct baked
with the offices in the scene so their light comes up through the registers.
Light groups 0-3 as above. No real-time lights but the player's torch.
Sounds: real CC0 recordings only (LICENSE.md); mono 44.1 kHz ogg; 3D at the
registers (air, the lights' hum below), the fan, the twin duct, the hand;
the trunk air and air-handler hum everywhere; reverb small and bright
(room 0.28, damp 0.15, wet 0.34).

Budget (harness, worst view): 48k primitives, 15 draw calls (Potato: 47k, 12),
<= 15 draw calls, 0 real-time lights besides the torch. Low/Potato: far
plane 18 m, thicker fog, 90 motes instead of 220. No `low_view_range` (each
kit is one mesh across the whole network, so it would hide the kit).

## Left to do / known simplifications

- TDC/TDF flanges, corner pieces and cleats are on the outside of a real
  duct and are never seen from inside; inside we show the rolled flange
  edges, the gap and gasket, and the patchy sealant over them.
- The fan blade light chopping is a light-group modulation (no real-time
  shadows on phones), so the whole plant-room light pulses rather than
  casting moving blade shadows.
- The figure is the shared CC0 body; only its hand (and the crown of its
  head) should be seen before it goes.
- The duct does not visibly flex (no vertex animation in the shared shader);
  flex is sound plus a small camera jolt.
