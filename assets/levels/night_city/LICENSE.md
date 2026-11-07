# The Blue Hour (`night_city`): third-party assets

Everything here not listed below was made for this level (procedural
geometry in `scripts/world/levels/night_city_layout.gd`, shaders, the bake
in `bake/` made by `tools/lucid/city_bake.tscn`) and needs no entry.

## Textures (ambientCG, all "CC0 1.0 Universal" on the asset's page)

Downloaded as the 1K JPG sets on 2026-11-07; the licence checked on each
asset's own page ("CC0 license, making them free to use without
attribution"). Colour, OpenGL normal and roughness maps kept, resized to
1024 or 512 px, re-encoded as JPG (quality 88). The shaders use each colour
map normalised by its linear mean (detail only); the albedo is the measured
one in the plan.

| Files | Asset | Author | Page | Licence |
| --- | --- | --- | --- | --- |
| `textures/asphalt_*` | Asphalt 033 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Asphalt033 | CC0 1.0 |
| `textures/concrete_*` | Concrete 034 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Concrete034 | CC0 1.0 |
| `textures/facade_concrete_*` | Concrete 046 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Concrete046 | CC0 1.0 |
| `textures/brick_*` | Bricks 105 | ambientCG (Lennart Demes) | https://ambientcg.com/view?id=Bricks105 | CC0 1.0 |

## Sounds

None third-party. Freesound (the planned source of CC0 city recordings)
could not be reached from the build environment, so every sound in
`audio/` is synthesized by `tools/lucid/night_city_audio.py` (numpy, then
ffmpeg to Ogg Vorbis, mono): the city's hum, wind between the towers, a far
siren, a ballast's buzz, the accessible pedestrian signal's locator and walk
ticks, and a sodium lamp's igniter restriking. Real CC0 recordings could
replace them file for file later (log them here).
