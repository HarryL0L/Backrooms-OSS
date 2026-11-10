# The Dimming Floor: third-party assets

Every third-party asset below is **CC0 1.0** (public domain dedication),
checked on the asset's own page on 2026-11-10 (each page reads "CC0
license, making them free to use without..."). Everything else in this
folder is made by this project's own scripts and needs no entry:

- the GLB kits and lightmaps (`tools/blender/levels/office.py`, all geometry
  modelled in code from the dimensions in SPEC.md: furniture, chairs and
  monitors included; no downloaded models),
- the composites and generated textures (`carpet_*` quarter-turn layout,
  `blinds_diff`, `lens_diff`; `office.py --textures`),
- every sound in `audio/` (synthesised by `office.py --sounds`, see SPEC.md
  "Sound"; placeholders until real CC0 recordings can be fetched),
- `office_lit.gdshader(inc)`, a modified copy of the project's own
  `shaders/level_lit.gdshaderinc`.

## Textures (ambientCG, "Creative Commons CC0" on each page)

Downloaded as the 1K JPG packs. Changes common to all: colour rescaled so
its linear mean equals the albedo in SPEC.md (and tinted), resized to 512 px
(roughness 256 px), NormalGL used as the normal map.

| Used as | Asset | Author | Page | Changes |
| --- | --- | --- | --- | --- |
| `carpet_*` | Carpet 012 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Carpet012 | dark blue-grey; laid out as 2 x 2 tiles, alternate tiles turned 90 degrees (quarter-turn carpet tiles), normal map turned with them |
| `ceiling_tile_*` | Office Ceiling 001 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=OfficeCeiling001 | none beyond the common changes (6 tiles per repeat = 2 ft grid) |
| `wall_paint_*` | Painted Plaster 017 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=PaintedPlaster017 | warm off-white |
| `panel_fabric_*` | Fabric 030 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Fabric030 | blue-grey panel fabric |
| `laminate_*` | Wood 049 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Wood049 | desaturated to a grey-beige laminate |

## Figure

What stands in the dark is the project's CC0 MakeHuman body
(`assets/entities`, see `assets/entities/LICENSE.md`) through `EntityBody`.
