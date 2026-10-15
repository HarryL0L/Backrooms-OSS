# Music

All of the game's music is rendered entirely from code (no samples), with
numpy. The rendered `.ogg` files in `music/` are committed so the game builds
without Python; these scripts are their source. Same licence as the game.

| Script | Track | Used for |
|---|---|---|
| `compose.py` | **Empty Hours**: detuned pads, a glassy melody with echoes, tape wobble and hiss | The Field |
| `fountain_court.py` | **Fountain Court**: soft-jazz mall music in an empty atrium, going from happy and nostalgic to sad to eerie (it gets stuck, sags, the power dies), then carrying on as if nothing happened | Dead Mall (planned) |
| `closing_bell.py` | **Closing Bell**: exactly 60 s of chase noise and dread, no melody or beat: a full-volume blast when the entity sees you, grinding distorted drones that stutter and glitch, metal scrapes, random booms, distant howls and an endlessly rising rumble on warped tape; cuts dead at 60 s | Dead Mall chase (planned) |

    python3 compose.py empty_hours.wav
    ffmpeg -i empty_hours.wav -c:a libvorbis -q:a 4 ../../music/empty_hours.ogg

(and likewise `fountain_court.py` / `closing_bell.py`).
