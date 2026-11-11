# The Endless Stairwell: third-party assets

Every third-party asset below is **CC0 1.0** (public domain dedication),
checked on the asset's own page on 2026-11-11 (the ambientCG pages read
"... Creative Commons CC0 license, making them free to use without
attribution - even in commercial circumstances."; the Poly Haven page reads
"CC0 1.0 Universal - public domain dedication, no attribution required").
Everything else in this folder is made by this project's own scripts and
needs no entry:

- the two storey kits (`stair_unit.glb`, `stair_top.glb`) and their group
  lightmaps (`tools/blender/levels/stairwell.py`: all geometry modelled in
  code from the dimensions in SPEC.md; no downloaded models),
- the hand on the rail, the stencilled numbers' quads, the water plane
  (procedural geometry in `scripts/world/levels/stairwell_level.gd`), B2's
  door leaf (`scripts/world/levels/stairwell_entrance.gd`),
- `textures/sign_plate_diff.jpg` (the stair identification sign) and
  `textures/digits_diff.png` (the stencil digits): drawn by
  `stairwell.py --textures` with the Stacks' stroke lettering (no fonts,
  original wording, no brands),
- the block joints drawn into `cmu_paint_*` (`stairwell.py --textures`),
- every sound in `audio/` (synthesised by `stairwell.py --sounds`: noise
  shaped in the frequency domain; placeholders until real CC0 recordings
  can be fetched, see SPEC.md "Sound"),
- `stairwell_lit.gdshader(inc)`, `stairwell_lit_cutout.gdshader` (a modified
  copy of the project's own `shaders/level_lit.gdshaderinc`) and
  `stairwell_water.gdshader`.

No fonts are used in any texture (all lettering is drawn as strokes by the
script). The B2 door's Use prompt and the HUD use the game's own font.

## Textures

Downloaded as 1K JPG packs on 2026-11-11. Changes common to all: colour
rescaled so its linear mean equals the albedo in SPEC.md (and partly
desaturated), resized (diffuse 512-1024 px, normal 512 px, roughness
256 px), the OpenGL normal map used.

| Used as | Asset | Author | Page | Licence | Changes |
| --- | --- | --- | --- | --- | --- |
| `cmu_paint_*` (the painted block walls) | Painted Plaster 017 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=PaintedPlaster017 | CC0 1.0 | light warm grey (linear mean 0.47, 0.465, 0.43); 8 x 16 in block joints (running bond, 3 blocks x 8 courses a repeat) drawn into colour, normal and roughness, a per-block tone |
| `concrete_*` (treads, landings, soffits) | Concrete Floor Worn 001 | Poly Haven (Dimitrios Savva, photography; Rico Cilliers, processing) | https://polyhaven.com/a/concrete_floor_worn_001 | CC0 1.0 | grey (linear mean 0.27, 0.265, 0.25), 30 % of its colour kept |
| `door_paint_*` (the fire doors) | Painted Metal 014 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=PaintedMetal014 | CC0 1.0 | blue-grey enamel (linear mean 0.16, 0.19, 0.21), 12 % of its colour kept and its contrast cut to 30 % (the chipped rust reads as wear) |
