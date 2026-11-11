# The Stacks: third-party assets

Every third-party asset below is **CC0 1.0** (public domain dedication),
checked on the asset's own page on 2026-11-10 (Wood 090 A, added with
the floor's expansion, on 2026-11-11) (each ambientCG page reads
"... Creative Commons CC0 license, making them free to use without ...";
the Poly Haven page reads "CC0 1.0 Universal - public domain dedication,
no attribution required"). Everything else in
this folder is made by this project's own scripts and needs no entry:

- the seven room kits (`filing_R1..R5, C1, C3.glb`) and their lightmaps
  (`tools/blender/levels/filing.py` from the floor plan in
  `tools/blender/levels/filing_layout.py`, all geometry modelled in code
  from the dimensions in SPEC.md; no downloaded models),
- the shelving, cartons, handles, carts, papers and the sign quads
  (procedural geometry in `scripts/world/levels/filing_level.gd`),
- `textures/labels_diff.png`: range cards, door / direction / range signs,
  the floor plans and the "you are here" dot, all drawn by
  `filing.py --labels` (stroke lettering, no fonts, original wording; no
  brands),
- the composites drawn over the CC0 textures: the carton atlas (labels,
  marker scribbles, hand holes, range cards with stroke-drawn letters and
  digits, typed sheets of paper), the block joints of `cmu_paint_*`, the exit
  sign face (`filing.py --textures`),
- every sound in `audio/` (synthesised by `filing.py --sounds`, including
  the `knock_*` sounds, see SPEC.md "Sound"; placeholders until real CC0
  recordings can be fetched),
- `filing_lit.gdshader(inc)`, a modified copy of the project's own
  `shaders/level_lit.gdshaderinc`.

No fonts are used (all lettering is drawn as strokes by the script).

## Textures

Downloaded as 1K JPG packs. Changes common to all: colour rescaled so its
linear mean equals the albedo in SPEC.md (and desaturated / tinted),
resized (diffuse 512-1024 px, normal 512 px, roughness 256 px), the OpenGL
normal map used.

| Used as | Asset | Author | Page | Licence | Changes |
| --- | --- | --- | --- | --- | --- |
| `concrete_floor_*` | Concrete Floor Worn 001 | Poly Haven (Dimitrios Savva, photography; Rico Cilliers, processing) | https://polyhaven.com/a/concrete_floor_worn_001 | CC0 1.0 | mid grey, roughness scaled down for the sealer's sheen |
| `cmu_paint_*` | Painted Plaster 017 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=PaintedPlaster017 | CC0 1.0 | off-white; 8 x 16 in block joints (running bond) drawn into colour and normal |
| `slab_paint_*` | Painted Plaster 017 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=PaintedPlaster017 | CC0 1.0 | flat white |
| `carton_*` (kraft) | Cardboard 002 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Cardboard002 | CC0 1.0 | kraft brown; cut into the atlas cells; labels, hand holes, grime drawn over |
| `carton_*` (older kraft) | Cardboard 004 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Cardboard004 | CC0 1.0 | as above, darker |
| `sorter_wood_*` (the sorting room's pigeonhole case) | Wood 090 A | ambientCG | https://ambientcg.com/view?id=Wood090A | CC0 1.0 | darkened and warmed to an aged varnished case (linear mean 0.33, 0.22, 0.13); diffuse 512 px, normal 256 px |
