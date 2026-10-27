# The Crawlspace: third-party assets

Every asset below is **CC0 1.0** (public domain dedication), checked on the
asset's own page on 2026-10-27. Everything else in this folder (the GLB
kits, lightmaps, `dust_mote.gdshader`, the spangle and composites in the
textures) is made by this project's scripts (`tools/blender/levels/crawlspace.py`,
and the texture/sound processing described in SPEC.md).

## Textures (ambientCG, all "Creative Commons CC0" on the page)

| Used as | Asset | Author | Page | Changes |
| --- | --- | --- | --- | --- |
| `duct_galv_*`, `duct_top_diff`, base of `duct_floor_*` | Metal 011 (1K JPG) | ambientCG | https://ambientcg.com/view?id=Metal011 | desaturated toward zinc grey; procedural hot-dip spangle (Voronoi crystals) multiplied into colour and roughness; faint smudges from SurfaceImperfections015 |
| dust on `duct_floor_*`, `duct_top_diff`, smudges | Surface Imperfections 015 (1K JPG) | ambientCG | https://ambientcg.com/view?id=SurfaceImperfections015 | opacity map used as a dust mask, colour as dust/smudge tone |
| `liner_*` (duct liner) | Fabric 029 (1K JPG) | ambientCG | https://ambientcg.com/view?id=Fabric029 | taken to the near-black of coated glass-fibre liner; roughness raised |
| `carpet_*` | Carpet 012 (1K JPG) | ambientCG | https://ambientcg.com/view?id=Carpet012 | resized to 512 px (roughness 256) |
| `ceiling_tile_*` | Office Ceiling 001 (1K JPG) | ambientCG | https://ambientcg.com/view?id=OfficeCeiling001 | resized to 512 px (roughness 256) |
| `wall_paint_*` | Painted Plaster 017 (1K JPG) | ambientCG | https://ambientcg.com/view?id=PaintedPlaster017 | resized to 512 px (roughness 256) |

## Sounds (Freesound, all "Creative Commons 0" on the page)

Downloaded as Freesound's HQ previews; cut, mono, 44.1 kHz, peak (one-shots,
-3 dBFS) or RMS (loops, -20 dBFS) normalised, loops crossfaded, ogg q4.

| Files | Sound | Author | Page |
| --- | --- | --- | --- |
| `pop_1`..`pop_5` | sheet metal sound one: womps.wav | trijohnstone | https://freesound.org/people/trijohnstone/sounds/547976/ |
| `pop_6` | Sheet Metal 2.wav (bend, pop) | ingudios | https://freesound.org/people/ingudios/sounds/119486/ |
| `flex_1`, `flex_2` | Flexing a Piece of Resonating Copper Sheet Metal | depwl9992 | https://freesound.org/people/depwl9992/sounds/457542/ |
| `bang_1`..`bang_3` | Duct impacts | j1987 | https://freesound.org/people/j1987/sounds/178835/ |
| `knock_1`..`knock_4` | Metal Knocking | BenjaminNelan | https://freesound.org/people/BenjaminNelan/sounds/410362/ |
| `knock_heavy` | door metal knock heavy bang from other side | kyles | https://freesound.org/people/kyles/sounds/637480/ |
| `crawl_1`..`crawl_7` | Crawling_inside_air_vent.wav | Samx89 | https://freesound.org/people/Samx89/sounds/660319/ |
| `brush_1`..`brush_4` | Crawling Through a Vent | Ultra-Edward | https://freesound.org/people/Ultra-Edward/sounds/795872/ |
| `creak_crawl` | quiet metal creaking | squarfington | https://freesound.org/people/squarfington/sounds/815606/ |
| `creak_slow` | Creaking Metal - Slow | EagleStealthTeam | https://freesound.org/people/EagleStealthTeam/sounds/172411/ |
| `drag` | R18-35-Drag Body Across Floor.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/481863/ |
| `grille_kick` | Metal - Air/Ventilation shaft kicked open 2 | TILIADESIGN | https://freesound.org/people/TILIADESIGN/sounds/488833/ |
| `grille_land` | Vent cover hitting | Zoidoi1709 | https://freesound.org/people/Zoidoi1709/sounds/785772/ |
| `fan_start` | HVAC Blower Fan | TheTechTinkerer | https://freesound.org/people/TheTechTinkerer/sounds/799531/ |
| `fan_loop` | S06-25 Loud exhaust fan in large interior space.wav | craigsmith | https://freesound.org/people/craigsmith/sounds/675541/ |
| `air_loop` | Air vent (looped) | lfyaudio | https://freesound.org/people/lfyaudio/sounds/848969/ |
| `grille_air` | Air Return Vent (loop) | NickTayloe | https://freesound.org/people/NickTayloe/sounds/843295/ |
| `duct_hum` | Vent Duct.wav | kiefspoon | https://freesound.org/people/kiefspoon/sounds/93059/ |
| `room_hum` | Fluorescent Light Hum | CHallSmith | https://freesound.org/people/CHallSmith/sounds/870708/ |
| `ballast_start` | Faulty Fluorescent Light Starter & Hum.wav | EverydaySounds | https://freesound.org/people/EverydaySounds/sounds/125064/ |
| `flicker_loop` | Flickering Fluorescent Light with Background Hum | kentspublicdomain | https://freesound.org/people/kentspublicdomain/sounds/777053/ |

## Figure

The pale one round the bend is the project's CC0 MakeHuman body
(`assets/entities`, see `assets/entities/LICENSE.md`), posed in code.
