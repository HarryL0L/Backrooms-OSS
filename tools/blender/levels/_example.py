"""Worked example for level_kit.py (not a level): a 10 x 8 m room, 3 m
high, with a doorway, two banks of ceiling lamps (light groups 0 and 1)
and an always-on exit sign. Copy it to tools/blender/levels/<id>.py.

Run:  /tmp/claude-0/bpyenv/bin/python tools/blender/levels/_example.py <out dir> [--fast]
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import level_kit as K  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "assets/levels/_example"

K.reset()
K.material("floor_tile", (0.42, 0.41, 0.39), rough=0.6)
K.material("wall_paint", (0.66, 0.64, 0.58), rough=0.9)
K.material("ceiling_tile", (0.75, 0.74, 0.7), rough=0.95)
K.material("bank_a", (1.0, 0.97, 0.9), emit=9.0, group=0)
K.material("bank_b", (1.0, 0.97, 0.9), emit=9.0, group=1)
K.material("exit_sign", (0.2, 1.0, 0.3), emit=4.0)          # always on

kit = K.Kit("example_room")
b = kit.b
H = 3.0
# Floor and ceiling, walls with a doorway in the east wall (x = 5).
b.slab(-5, -4, 5, 4, 0.0, 0.2, "floor_tile")
b.box((10, 8, 0.2), (0, 0, H + 0.1), "ceiling_tile")
b.wall((-5, -4), (5, -4), 0, H, 0.2, "wall_paint")
b.wall((-5, 4), (5, 4), 0, H, 0.2, "wall_paint")
b.wall((-5, -4), (-5, 4), 0, H, 0.2, "wall_paint")
b.wall((5, -4), (5, -0.6), 0, H, 0.2, "wall_paint")
b.wall((5, 0.6), (5, 4), 0, H, 0.2, "wall_paint")
b.wall((5, -0.6), (5, 0.6), 2.2, H, 0.2, "wall_paint")
# Two banks of lamps: west half group 0, east half group 1.
for x in (-3.5, -1.5):
    for y in (-2.0, 0.0, 2.0):
        b.box((1.2, 0.6, 0.02), (x, y, H - 0.01), "bank_a")
        K.area_light(kit, (x, y, H - 0.03), (1.2, 0.6), 18.0, group=0)
for x in (1.5, 3.5):
    for y in (-2.0, 0.0, 2.0):
        b.box((1.2, 0.6, 0.02), (x, y, H - 0.01), "bank_b")
        K.area_light(kit, (x, y, H - 0.03), (1.2, 0.6), 18.0, group=1)
b.box((0.35, 0.04, 0.15), (4.88, 0.0, 2.4), "exit_sign", rot=(0, 0, math.pi / 2))
# Collision (Godot): floor, ceiling, walls.
kit.col((10, 8, 0.2), (0, 0, -0.1))
kit.col((10, 8, 0.2), (0, 0, H + 0.1))
for y in (-4, 4):
    kit.col((10, 0.2, H), (0, y, H / 2))
kit.col((0.2, 8, H), (-5, 0, H / 2))
kit.col((0.2, 3.4, H), (5, -2.3, H / 2))
kit.col((0.2, 3.4, H), (5, 2.3, H / 2))
kit.spot("spot_arrival", (-4.0, 0.0, 0.0), -math.pi / 2)  # looking +X (Godot -Z)
kit.spot("spot_exit", (4.9, 0.0, 0.0), -math.pi / 2)   # its front (Godot +Z) into the room
kit.export(OUT, lm=512, samples=64)
