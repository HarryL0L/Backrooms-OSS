# Music

All of the game's music is rendered entirely from code (no samples), with
numpy. The rendered `.ogg` files in `music/` are committed so the game builds
without Python; these scripts are their source. Same licence as the game.

| Script | Track | Used for |
|---|---|---|
| `compose.py` | **Empty Hours**: detuned pads, a glassy melody with echoes, tape wobble and hiss | The Field |
| `fountain_court.py` | **Fountain Court**: soft-jazz mall music in an empty atrium, going from happy and nostalgic to sad to eerie (it gets stuck, sags, the power dies), then carrying on as if nothing happened | Dead Mall (planned) |
| `closing_bell.py` | **Closing Bell**: exactly 60 s of found-footage-style chase sound design: the entity's roar (growl with vocal fry and an inhuman scream on top) when it sees you, its heavy three-beat gallop closing in, a quickening throb, dark drones, metal scrapes and hits, close growls in dead-quiet drops, a mic that overloads when it's near; waves building to a climax, cut dead at 60 s | Dead Mall chase (planned) |

    python3 compose.py empty_hours.wav
    ffmpeg -i empty_hours.wav -c:a libvorbis -q:a 4 ../../music/empty_hours.ogg

(and likewise `fountain_court.py` / `closing_bell.py`).
