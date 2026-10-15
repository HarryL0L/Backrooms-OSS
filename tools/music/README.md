# Music

All of the game's music is rendered entirely from code (no samples), with
numpy. The rendered `.ogg` files in `music/` are committed so the game builds
without Python; these scripts are their source. Same licence as the game.

| Script | Track | Used for |
|---|---|---|
| `compose.py` | **Empty Hours**: detuned pads, a glassy melody with echoes, tape wobble and hiss | The Field |
| `fountain_court.py` | **Fountain Court**: soft-jazz mall music in an empty atrium, going from happy and nostalgic to sad to eerie (it gets stuck, sags, the power dies), then carrying on as if nothing happened | Dead Mall (planned) |
| `closing_bell.py` | **Closing Bell**: exactly 60 s horror chase score: stabbing low strings in a 3-3-2 pulse, huge toms and struck metal, distorted brass swells a tritone apart, screeching glissandi, a speeding heartbeat, a Shepard tone that rises forever, and the Fountain Court tune drifting past far away; ends on a hit | Dead Mall chase (planned) |

    python3 compose.py empty_hours.wav
    ffmpeg -i empty_hours.wav -c:a libvorbis -q:a 4 ../../music/empty_hours.ogg

(and likewise `fountain_court.py` / `closing_bell.py`).
