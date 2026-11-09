# Level 10 - The Field: third-party assets

None. Everything the Field uses is made for it: the terrain, the grass
blades, the sky, the supercell and the tornado are procedural (shaders and
scripts, see `docs/FIELD_STORM.md`), and no texture is loaded.

## Sounds

Freesound (the planned source of CC0 storm recordings) could not be reached
from the build environment (tried on 2026-11-09: HTTP 403 from the proxy), so
every sound in `audio/` is a PROCEDURAL PLACEHOLDER with no third-party
material in it:

| File | Made by | What |
| --- | --- | --- |
| `audio/wind_field.ogg` | `tools/lucid/field_storm_audio.py` | stereo 20 s loop: strong wind over open grassland (low rush, grass hiss) |
| `audio/rain_grass.ogg` | `tools/lucid/field_storm_audio.py` | stereo 20 s loop: heavy rain on a meadow (soft hiss, dull patter, wash) |
| `audio/tornado_roar.ogg` | `tools/lucid/field_storm_audio.py` | mono 20 s loop: a tornado kilometres off (deep rumble under ~160 Hz) |
| `audio/thunder_{near,mid,far}_{1,2}.ogg` | `tools/lucid/night_city_thunder.py audio --open` | thunder at 1.6, 4 and 9 km in open country (the Blue Hour's model without the towers' echoes) |

Real CC0 recordings (Freesound, with each sound's licence checked on its own
page) could replace them file for file later; log them here.
