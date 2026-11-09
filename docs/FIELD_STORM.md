# Level 10 - The Field: the supercell

The Field used to be a sunny meadow under fair-weather cumulus. It is now an
endless meadow on a summer afternoon in the inflow of a tornadic supercell:
dark storm light, a rain-free base with its wall cloud and a tornado
kilometres off, the precipitation core beside it, rain bands sweeping over,
gusts running through the grass, lightning and thunder. The exit door and its
tree still stand out in the grass; the tornado never comes for you.

Everything is in real units through the L.U.C.I.D. camera (docs/LUCID.md,
stage 1), on every preset. Nothing is raymarched at run time: the sky is a
few analytic surfaces met along the view ray plus a short integral of the
air, the tornado is two strips of camera-facing quads. (The sunny Field's
one-off cumulus bake, `cloud_bake.gdshader`, is gone, and so is the sun.)

Files: `scripts/world/field_storm.gd` (`FieldStorm`: layout, wind and rain
fields, camera, lightning, rain, tornado, sound), `scripts/world/field_grass.gd`
(`FieldGrass`), `shaders/field_storm.gdshaderinc` (what every Field shader
shares), `field_sky.gdshader`, `field_tornado.gdshader`,
`field_grass.gdshader`, `field_ground.gdshader`, `field_tree.gdshader`;
shared with the Blue Hour: `LucidStorm` (lightning, bolts, thunder timing),
`LucidRain` (falling rain, lens drops), `lucid_bolt.gdshader`,
`lucid_rain.gdshader`. Test harness: `_test/field_storm_shots.tscn`.

## What a supercell looks like from its inflow

A storm chaser's classic view (NWS SKYWARN spotter guides; Doswell &
Burgess 1993; Lemon & Doswell 1979; Bluestein 2013): you stand to the
south-east of the storm, in the warm moist air flowing into it. Over you
and far downwind spreads the anvil (the storm's top, spread out under the
tropopause ~10-12 km up). Toward the storm the sky lowers to the dark,
flat, rain-free base under the updraft (1-1.5 km up in tornadic
environments: their lifting condensation level is low, under ~1 km for
most significant tornadoes, Rasmussen & Blanchard 1998, Thompson et al.
2003). Under the base hangs the wall cloud, an abrupt lowering 1.5-6 km
across, often rotating visibly, with ragged scud racing into it from the
inflow. The tornado comes down from it. Beside it (to the north and
north-east in a classic supercell) the forward-flank precipitation core
stands as a grey curtain, often with a green cast in the late afternoon
(Bohren & Fraser 1993; Gallagher, Beasley & Bohren 1996 measured it); the
rear flank's rain wraps round the tornado. Under the base you see the
bright horizon beyond the storm, so the wall cloud and the tornado stand
dark against light. The updraft's flanks show laminar, striated banding
turning round the mesocyclone.

## The layout (`FieldStorm`, from the player; north is -Z)

| Part | Where | Size | Source of the numbers |
| --- | --- | --- | --- |
| Mesocyclone, wall cloud | azimuth 340, 4.6 km | wall cloud 2.1-3 km across, hanging 600 m under the base | wall clouds 1.5-6 km wide (NWS); mesocyclones 2-10 km |
| Tornado | south-west of the wall cloud's centre | cone 170-600 m wide at the top, 30-170 m at the ground; rope 30-280 m | median tornado width ~50-150 m, large ones over 500 m (SPC climatology) |
| Precipitation core | azimuth 20, 10 km | 5 km radius, edged (rain shafts end); 70 mm/h at its heart | supercell cores 50-100+ mm/h |
| Rear-flank hook | 1 km south-east of the mesocyclone | 1.4 km, 7 mm/h | Lemon & Doswell 1979 |
| Rain-free base | round both, 1.2 km up, its far edge ~9 km off behind the wall cloud | 5 km radius | LCL of tornadic storms ~0.5-1.5 km |
| Anvil | overhead, spread east (downwind) | 24 km radius, 10 km up | summer tropopause 10-15 km |
| Updraft tower | behind the mesocyclone | 5.2 km radius, 13 km tall | shades you from the sun behind the storm |
| Sun | azimuth 318, 21 degrees up | 65 000 lux beam | late afternoon, hazy summer air |

The layout is anchored to the player: walking toward the tornado never
brings it closer (it stays 4-6 km off), so the field is effectively endless
and the storm stays where a chaser would keep it. The whole storm drifts
east-north-east and back over 25 minutes (up to 6.7 m/s across the view).
The tornado lives in cycles (cyclic tornadogenesis; Burgess et al. 1982):
35 s forming (the debris whirl first, the condensation funnel lowering
from the wall cloud), 210 s mature (a cone, breathing), 70 s roping out
(thinning, bowing, its foot dragged behind by the outflow), 25 s lifting,
50 s gone. It turns at 0.55 rad/s as a cone and faster as a rope
(angular momentum: ~60 m/s round a ~100 m core), and moves ~2 m/s
relative to the storm. It does not harm the player in any way.

## Light (cd/m2, lux) and the camera

| Quantity | Value | Reference |
| --- | --- | --- |
| Shaded air and sky under the storm (`SHADE_NITS`) | 230 cd/m2, 7500 K | a tenth of a bright overcast (overcast skies 1 000-8 000 cd/m2; very dark storm daylight ~100-1 000 lux) |
| Open ground under it | ~1 000 lux (half that in a heavy band) | lux tables: overcast day ~1 000 lux, very dark overcast ~100 lux (IES Lighting Handbook) |
| Base, wall cloud, anvil | x0.62, x0.42, x1.25 the shade, mottled | |
| Sunlit hazy air (`SUNAIR_NITS`) | +1 800 cd/m2 (x Henyey-Greenstein g 0.55, plus the air's Rayleigh blue) | clear hazy horizon 3 000-6 000 cd/m2 |
| Sun beam | 65 000 lux at 21 degrees | |
| Haze | 1.0e-4 /m (visibility ~40 km), thinning with a 2.5 km scale height | clean inflow air |
| Rain extinction | Marshall-Palmer geometric cross-section (`LucidRain.sigma`): 2.4e-3 /m at 70 mm/h (visibility 1.6 km) | as in LUCID.md "Rain" |

The camera is `Lucid.Camera` (f/2, 1/8000-1/30 s, ISO 50-1600) metering the
view (the shaded field, the base, the bright horizon under it) in program
mode, aiming 0.2 stop under the ISO 2720 calibration so a storm looks dark,
with 2.5 stops of highlight headroom (the horizon under the base may clip
as it does on a phone), auto white balance toward the 7500 K shade (half
corrected, so it stays blue-grey). The sky shader carries the exposure, so
Godot's ambient light from the sky (the dark base overhead, the bright band
under it) comes out exposed too; the flash is a directional light converted
with `Lucid.light_node_cam`. AgX grade (`EnvironmentFactory.lucid_grade`) on
every preset. Sunlight reaches the ground (and the air) only where no
tower, base or anvil is between it and the sun (`field_lit`): you stand in
the storm's shadow, the far fields to the west and south lie in sun.

## One wind field (`field_wind_at`)

Every moving thing reads the same wind (globals `field_wind`, `field_band`,
GDScript copy `FieldStorm.wind_at`): the grass (both kinds), the tree, the
rain's slant, the scud in the sky, the sound.

- Mean: the inflow toward the mesocyclone, 9 m/s at 2 m (+-1.2 m/s slowly;
  storm-relative low-level inflow is 10-20 m/s in tornadic storms, Thompson
  et al. 2003). Behind a rain band's gust front (up to 2.6 km ahead of its
  rain) it turns to the band's cold outflow, 17 m/s away from the core
  (gust fronts and outflows 15-25 m/s, Wakimoto 1982; rear-flank
  downdrafts gust 20-30 m/s, Markowski et al. 2002).
- Gusts: the mean times a gust factor 1 + I g, I the turbulence intensity
  (0.32 in the inflow, 0.5 in the outflow; near-surface over grass ~0.2-0.4,
  Stull 1988), g four plane waves 14-85 m long, mostly across the wind, in
  packets 420 m apart, all riding on the air (Taylor's frozen turbulence:
  their phase moves with the distance the air has travelled, so gust fronts
  sweep over the grass at the wind speed, the "honami" of Finnigan 1979 and
  Py, de Langre & Moulia 2006). Gusts reach ~14 m/s in the inflow, 25 m/s
  in the outflow.
- Rain: `field_rain_at` (core + hook + band, cells along the band), the
  same in GDScript (`rain_at`) for the drops, the lens and the sound. A
  band (30-45 mm/h, 1.4 km half width, 3.2 km half length, its middle
  east of you) forms 5.2 km off to the north-east every 12 minutes, builds
  over two minutes and sweeps over you toward the south-west at 13 m/s,
  passing east of the tornado; its gust front turns the wind ~2.6 km ahead
  of its rain, so the grass flattens before the first drops.

## The grass bends with the dynamic pressure

A blade is a cantilever: the drag on it grows with the dynamic pressure
q = rho v^2 / 2, its stiffness holds it. Each blade is drawn as a circular
arc whose bend is tan(theta) = (v / v45)^2: v45 = 10 m/s (the 2 m wind at
which it leans 45 degrees; inside the canopy the log profile with z0 ~0.05 m
gives about half of that) times 0.75-1.3 per blade, so 2 m/s sways it ~2
degrees, the 9 m/s inflow leans it ~40 degrees, a 15 m/s gust lays it ~65
degrees, the outflow flattens it. Plus its own droop (0.12-0.67 rad), the
tips' flutter at 2-3 Hz (grass stems' natural frequencies are 1-5 Hz,
de Langre 2008) growing with v, and a push away from the player within 0.75 m.
Wet (in and after rain, `field_wind.w`): v45 8.5 m/s, more droop, slower
flutter (2.1 Hz), darker, glossier (the water film).

On Medium and below the grass stays the ground shader's lawn, at the same
cost, with only a cheap per-vertex sheen where gusts lay it over (lighter
where the pale blade sides turn up), darker when wet.

## Realistic grass (High, Max, Realistic: `FieldGrass`)

Instanced blades (one blade per MultiMesh instance, a pure translation; its
looks hashed from its world root, so blades stay put as tiles follow you):

| Ring | Tile | Radius | Blades/m2 | Segments | Width |
| --- | --- | --- | --- | --- | --- |
| near | 5 m, 5x5 | 0-8 m | 130 | 3 | 12 mm |
| mid | 12 m, 5x5 | 8-21 m | 32 | 2 | 20 mm |
| far | 32 m, 5x5 | 21-55 m | 8 | 1 | 45 mm |

Max and Realistic: x1.15 density and reach. About 100k blades in view on
High (the near ring's ~13k, the mid ring's ~20k, the far ring's ~35k in
front of you, plus the hidden ones in the tiles' corners). Rings hand over by dithering
(each blade has its own threshold), tiles wholly outside their ring are
hidden, the rest frustum-culled. Heights 0.2-0.6 m (x1.35 for the 8 % with
seed heads), taller in clumps, a few dry blades, darker near the root (the
canopy shades itself), translucent (BACKLIGHT). Past the blades the ground
takes their mean colour, under them the thatch.

## Lightning and thunder (`LucidStorm`, driven)

The Blue Hour's lightning, unchanged in its physics, now with a `driven`
mode (the level sets the rain, wind and intensity), a `focus` (flashes
round the storm's core and base, 4.5 km round the point between the
mesocyclone and the core) and its rates as properties: a flash every ~16 s
(supercells flash tens of times a minute, most of them in the cloud,
MacGorman & Rust 1998), more as a band comes. Its base is 1.2 km over the
Field. By day a flash's lit patch of cloud (~20 cd/m2) is a tenth of the
base's own light, so cloud flashes are a faint flicker in the core; a bolt's
channel (thousands of cd/m2) shows plainly against the dark core. A near
channel lights the field directly (a line source of I' cd/m from the ground
to the base: E = I' atan(H / rho) / rho, ~1/10 of the storm light at 1.5 km).
Thunder arrives at 343 m/s from the channel's nearest point, from
open-country recordings (no echoes, `night_city_thunder.py --open`).

## Rain (`LucidRain`, daylight)

The Blue Hour's rain, its ground now the Field's hills (`ground_kind` 1):
its rate is the rain field where you stand (none in the inflow, up to
~40 mm/h under a band), its slant the wind field (6-8 m/s drops in 15 m/s
wind slant ~65 degrees), its streaks as long as the camera's shutter
makes them (by day 1/250-1/60 s: short dashes, longer in the darker band).
Its surround is the storm's sky. Lens drops on the body cam as in the
city. Far off, the same rain field is the rain shafts in the sky and the
veil over the ground and the tornado.

## Sound

Wind over the grass (level ~v^3 in amplitude, +30 dB per decade of speed,
pitch rising), rain on the meadow by the rain rate here, the tornado's
distant rumble (-26 dB at full presence: most of a tornado's sound is low
frequency and carries, Bedard 2005), thunder. All are procedural
placeholders (Freesound blocked, see `assets/levels/field/LICENSE.md`).
The music (*Empty Hours*, warm and serene) no longer plays in the Field: a
supercell's wind and thunder are its soundtrack.

## Cost

Measured with `_test/field_storm_shots.tscn` (lavapipe, a CPU rasterizer,
1280 x 720, PERF=1: mean frame time over 60 frames; compare runs only, its
vertex work is far slower than any phone GPU's):

| Preset | Draw calls | Primitives | Frame time | Notes |
| --- | --- | --- | --- | --- |
| Low | 5-29 | 27-40k | 87-89 ms | 5 sky steps, 4 ground air steps, lighter rain and bolts |
| Medium | 6-31 | 27-49k | 146-173 ms | the lawn shader, no blades |
| High | 41-67 | 407-530k | 449-491 ms | + ~150k blades processed (~65k in view) |
| Realistic | 36-65 | 460-600k (900k looking down) | | x1.15 blade density and reach |

The draw calls past Medium are the grass tiles (up to ~35 visible); the
rest is the sky, the ground, the tornado's two strips, the tree, the door,
the rain (one draw, only while it rains) and a bolt (one, only while lit).
On lavapipe High costs ~2.8x Medium because it transforms every blade on the
CPU; on a mid-range phone GPU the blades are ~0.75 M vertices of ~150 ALU
(the wind field and the height: ~110 M ALU a frame) and thin overdraw in the
lower half of the view, an estimated +3-5 ms over Medium, which is why the
blades are High and up only. Per pixel the sky does 9 air steps (4 in the
radiance cubemap's pass, 5 on Potato and Low), each a rain and sunlight
lookup (value noise, no textures but the one noise map for the cloud
layers); the ground does its air per vertex (~14k vertices), the tornado per
vertex too. CPU: FieldStorm ~0.1 ms a frame (the wind and rain fields where
you stand, the meter, a few globals); the grass tiles move only when you
cross a tile. Sounds +1.2 MB.

## Sources

- Bedard, A. J. (2005). Low-frequency atmospheric acoustic energy associated with vortices produced by thunderstorms. Mon. Wea. Rev. 133, 241-263.
- Bluestein, H. B. (2013). Severe Convective Storms and Tornadoes: Observations and Dynamics. Springer.
- Bohren, C. F., & Fraser, A. B. (1993). Green thunderstorms. Bull. Amer. Meteor. Soc. 74, 2185-2193.
- Burgess, D. W., Wood, V. T., & Brown, R. A. (1982). Mesocyclone evolution statistics. Preprints, 12th Conf. Severe Local Storms, AMS.
- de Langre, E. (2008). Effects of wind on plants. Annu. Rev. Fluid Mech. 40, 141-168.
- Doswell, C. A., & Burgess, D. W. (1993). Tornadoes and tornadic storms: a review of conceptual models. Geophys. Monogr. 79, AGU.
- Finnigan, J. J. (1979). Turbulence in waving wheat. Boundary-Layer Meteorol. 16, 181-211.
- Gallagher, F. W., Beasley, W. H., & Bohren, C. F. (1996). Green thunderstorms observed. Bull. Amer. Meteor. Soc. 77, 2889-2897.
- Lemon, L. R., & Doswell, C. A. (1979). Severe thunderstorm evolution and mesocyclone structure as related to tornadogenesis. Mon. Wea. Rev. 107, 1184-1197.
- MacGorman, D. R., & Rust, W. D. (1998). The Electrical Nature of Storms. Oxford University Press.
- Markowski, P. M., Straka, J. M., & Rasmussen, E. N. (2002). Direct surface thermodynamic observations within the rear-flank downdrafts of nontornadic and tornadic supercells. Mon. Wea. Rev. 130, 1692-1721.
- Marshall, J. S., & Palmer, W. M. (1948); Gunn, R., & Kinzer, G. D. (1949); Atlas, D., et al. (1973): drop sizes and fall speeds (see docs/LUCID.md).
- NOAA NWS. SKYWARN Storm Spotter Guide / Advanced Spotters' Field Guide (wall cloud, rain-free base, scud, striations, inflow).
- Py, C., de Langre, E., & Moulia, B. (2006). A frequency lock-in mechanism in the interaction between wind and crop canopies. J. Fluid Mech. 568, 425-449.
- Rasmussen, E. N., & Blanchard, D. O. (1998). A baseline climatology of sounding-derived supercell and tornado forecast parameters. Wea. Forecasting 13, 1148-1164.
- Stull, R. B. (1988). An Introduction to Boundary Layer Meteorology. Kluwer.
- Taylor, G. I. (1938). The spectrum of turbulence. Proc. R. Soc. Lond. A 164, 476-490.
- Thompson, R. L., Edwards, R., Hart, J. A., Elmore, K. L., & Markowski, P. (2003). Close proximity soundings within supercell environments obtained from the Rapid Update Cycle. Wea. Forecasting 18, 1243-1261.
- Wakimoto, R. M. (1982). The life cycle of thunderstorm gust fronts as viewed with Doppler radar and rawinsonde data. Mon. Wea. Rev. 110, 1060-1082.
