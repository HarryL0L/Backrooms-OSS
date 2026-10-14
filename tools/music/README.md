# Music

`compose.py` renders **Empty Hours**, the Field's music, entirely from code
(no samples): detuned pads, a glassy melody with echoes, tape wobble and hiss,
a faint fluorescent hum, and a synthetic reverb.

    python3 compose.py empty_hours.wav
    ffmpeg -i empty_hours.wav -c:a libvorbis -q:a 4 ../../music/empty_hours.ogg

Requires numpy. The rendered `music/empty_hours.ogg` is committed so the game
builds without Python; this script is its source. Same licence as the game.
