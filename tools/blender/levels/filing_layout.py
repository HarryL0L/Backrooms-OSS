"""The Stacks (side level "filing"): the floor plan, in one place.

A records-centre storage floor after hours, about 1030 m2: five storage
bays and a sorting room behind fire-barrier walls (8 in block), joined by
two 72 in service corridors. Every bay is filled with mechanical-assist
mobile shelving; the open aisles are the only ways through, and they move.

This module is plain Python (no bpy). It is the single source of truth for
the layout: tools/blender/levels/filing.py builds the kits from it, and
`python3 tools/blender/levels/filing_layout.py` writes
scripts/world/levels/filing_layout.gd (the same data for the level script)
and the floor-plan map (--map <png>).

Coordinates: Blender, metres, x east, y north, z up; Godot (x, z) =
(x, -y), round SideLevel.LEVEL_Y.
"""
import json
import math
import os
import sys

IN = 0.0254
SEC_W = 42 * IN             # shelf section (3 records cartons across)
END_T = 0.025
SHELF_D = 15 * IN
FLUE = 2 * IN
CAR_W = 2 * SHELF_D + FLUE  # 0.8128 double-faced carriage
FIX_W = SHELF_D + 0.04      # single-faced fixed unit
AISLE = 36 * IN             # an open aisle
REAR = 42 * IN              # rear aisle
MAIN = 72 * IN              # main (cross) aisle; also the service corridors
WALL_T = 0.2                # 8 in block fire-barrier walls
CEIL = 3.2
DOOR_W = 36 * IN            # 3070 hollow-metal fire doors (36 x 84 in)
DOOR_H = 84 * IN
GAP = 0.05                  # shelving to wall


def range_l(nsec):
    return nsec * SEC_W + 2 * END_T


def bank_w(n, k):
    return 2 * FIX_W + n * CAR_W + k * AISLE


# ------------------------------------------------------------------ cells ---
# Bay 1 is the original room (Level 1.1 as first built), unchanged inside.
R6 = range_l(6)                         # 6.451
R8 = range_l(8)                         # 8.585
R9 = range_l(9)                         # 9.651
W1 = bank_w(12, 1) + 2 * GAP            # 11.612
D1 = 2 * REAR + 2 * R6 + MAIN           # 16.865
C1Y0 = D1 + WALL_T                      # 17.065
C1Y1 = C1Y0 + MAIN                      # 18.894
NY0 = C1Y1 + WALL_T                     # 19.094 (north block)
R3X0 = 19.2
R5X0 = 12.747
R5X1 = R5X0 + bank_w(24, 2) + 2 * GAP   # 35.025
R4X1 = MAIN + R9 + 40 * IN              # 12.496: R4 main aisle, ranges, a 40 in rear aisle
R4Y1 = NY0 + bank_w(12, 1) + 2 * GAP    # 30.706
R5Y1 = NY0 + GAP + R8 + MAIN            # 29.557
C3X0 = R5X1 + WALL_T                    # 35.225
C3X1 = C3X0 + MAIN
MAIN1 = REAR + R6 + MAIN / 2            # 8.432 (Bay 1 / Bay 3 main aisle)
R5MAIN = NY0 + GAP + R8 + MAIN / 2      # 28.643

CELLS = {
    # id: rect (x0, y0, x1, y1), kind, sign name, lightmap size, the room
    # frame (Blender direction of the shelving's motion), sensor time-out (s)
    "R1": {"rect": [0.0, 0.0, W1, D1], "kind": "bay", "name": "BAY 1", "lm": 1024, "ax": [1, 0], "timeout": 120.0},
    "C1": {"rect": [-4.2, C1Y0, R5X1, C1Y1], "kind": "corridor", "name": "CORRIDOR A", "lm": 512, "ax": [1, 0],
           "timeout": 30.0},
    "R2": {"rect": [W1 + WALL_T, 6.8, R3X0 - WALL_T, D1], "kind": "sort", "name": "SORTING", "lm": 512, "ax": [1, 0],
           "timeout": 300.0},
    "R3": {"rect": [R3X0, 0.0, R5X1, D1], "kind": "bay", "name": "BAY 3", "lm": 1024, "ax": [1, 0], "timeout": 120.0},
    "R4": {"rect": [0.0, NY0, R4X1, R4Y1], "kind": "bay", "name": "BAY 2", "lm": 1024, "ax": [0, 1], "timeout": 120.0},
    "R5": {"rect": [R5X0, NY0, R5X1, R5Y1], "kind": "bay", "name": "BAY 4", "lm": 1024, "ax": [1, 0], "timeout": 22.0,
           "dark": True},
    "C3": {"rect": [C3X0, 2.0, C3X1, R5Y1], "kind": "corridor", "name": "CORRIDOR B", "lm": 512, "ax": [0, 1],
           "timeout": 30.0},
}

# ------------------------------------------------------------------ banks ---
# o: the corner of the bank at u = 0, v = 0 (Blender); eu: the direction
# the carriages roll; ev: along the ranges, toward the handle end (the main
# aisle). n carriages, `aisles` the open gaps to start with (gap g is
# between carriage g-1 and g; 0 and n are by the fixed units), nsec
# sections per range, rear: what is past the far end ("aisle" or "wall"),
# label: what the range cards start with.


def _bank(cell, name, o, eu, ev, n, aisles, nsec, rear, label, room_w):
    w = bank_w(n, len(aisles))
    gap = (room_w - w) / 2.0
    return {"cell": cell, "name": name, "o": [round(o[0] + eu[0] * gap, 4), round(o[1] + eu[1] * gap, 4)],
            "eu": eu, "ev": ev, "n": n, "aisles": aisles, "nsec": nsec, "rear": rear, "label": label}


BANKS = [
    # Bay 1 (as first built): bank A south, bank B north, handles on the main aisle.
    _bank("R1", "A", [0.0, REAR], [1, 0], [0, 1], 12, [6], 6, "aisle", "1A", W1),
    _bank("R1", "B", [0.0, D1 - REAR], [1, 0], [0, -1], 12, [6], 6, "aisle", "1B", W1),
    # Bay 3: the same plan 15.8 m wide, two open aisles in each bank.
    _bank("R3", "A", [R3X0, REAR], [1, 0], [0, 1], 16, [4, 11], 6, "aisle", "3A", R5X1 - R3X0),
    _bank("R3", "B", [R3X0, D1 - REAR], [1, 0], [0, -1], 16, [5, 12], 6, "aisle", "3B", R5X1 - R3X0),
    # Bay 2: ranges east-west, 9 sections (9.65 m); handles on the west main aisle,
    # a rear aisle along the east wall; the carriages roll north-south.
    _bank("R4", "A", [MAIN + R9, NY0], [0, 1], [-1, 0], 12, [5], 9, "aisle", "2A", R4Y1 - NY0),
    # Bay 4 (dark): one bank of 24, two open aisles, 8-section ranges; the far
    # ends stand against the corridor wall (two fire doors open onto them).
    _bank("R5", "A", [R5X0, NY0 + GAP], [1, 0], [0, 1], 24, [9, 20], 8, "wall", "4A", R5X1 - R5X0),
]


def bank_geom(b):
    """Derived sizes of a bank: range length, width, the fixed units' inner
    faces (u), and the u of gap g's left face when the open gaps are `aisles`."""
    L = range_l(b["nsec"])
    k = len(b["aisles"])
    w = bank_w(b["n"], k)
    return {"L": L, "W": w, "uL": FIX_W, "uR": w - FIX_W}


def gap_u(b, g, aisles):
    """u of the left face of gap g (carriages pressed together, `aisles` open)."""
    return FIX_W + g * CAR_W + sum(AISLE for a in aisles if a < g)


def to_world(b, u, v):
    return (b["o"][0] + b["eu"][0] * u + b["ev"][0] * v, b["o"][1] + b["eu"][1] * u + b["ev"][1] * v)


# ------------------------------------------------------------------ doors ---
# c: the centre of the opening on the wall's centre line; axis: the wall
# runs along x or y; kind: door (open, held by its magnet), gated (open,
# but the shelving stands across it unless an aisle lines up), arrive
# (shut behind you), locked (a shut door: STAIR 1...), exit (the level's
# way out: a LevelEntrance door on a solid wall), stair (STAIR 2, the way
# on down to the stairwell: the same, with a door sign; nothing baked).
G5 = BANKS[5]


def _gated_x(g, aisles_left):
    # the centre of gap g of Bay 4's bank with `aisles_left` open aisles to its left
    u = FIX_W + g * CAR_W + aisles_left * AISLE + AISLE / 2
    return round(G5["o"][0] + u, 4)


DOORS = [
    {"id": "arrive", "a": "R1", "b": None, "c": [-WALL_T / 2, MAIN1], "axis": "y", "w": DOOR_W, "kind": "arrive",
     "sign": "NO EXIT"},
    {"id": "d1", "a": "R1", "b": "C1", "c": [10.65, D1 + WALL_T / 2], "axis": "x", "w": DOOR_W, "kind": "door",
     "sign": "BAY 1"},
    {"id": "d2", "a": "R2", "b": "C1", "c": [15.4, D1 + WALL_T / 2], "axis": "x", "w": DOOR_W, "kind": "door",
     "sign": "SORTING"},
    {"id": "d3", "a": "R3", "b": "C1", "c": [33.9, D1 + WALL_T / 2], "axis": "x", "w": DOOR_W, "kind": "door",
     "sign": "BAY 3"},
    {"id": "d4", "a": "R4", "b": "C1", "c": [0.95, C1Y1 + WALL_T / 2], "axis": "x", "w": DOOR_W, "kind": "door",
     "sign": "BAY 2", "leaf": "b"},
    {"id": "d5", "a": "R4", "b": "R5", "c": [R4X1 + WALL_T / 2, R5MAIN], "axis": "y", "w": DOOR_W, "kind": "door",
     "sign": "BAY 4"},
    {"id": "d6", "a": "C3", "b": "R3", "c": [R5X1 + WALL_T / 2, MAIN1], "axis": "y", "w": DOOR_W, "kind": "door",
     "sign": "BAY 3"},
    {"id": "d7", "a": "C3", "b": "R5", "c": [R5X1 + WALL_T / 2, R5MAIN], "axis": "y", "w": DOOR_W, "kind": "door",
     "sign": "BAY 4"},
    # Two fire doors from corridor A straight onto Bay 4's range ends.
    {"id": "g1", "a": "C1", "b": "R5", "c": [_gated_x(6, 0), C1Y1 + WALL_T / 2], "axis": "x", "w": 1.0,
     "kind": "gated", "sign": "BAY 4"},
    {"id": "g2", "a": "C1", "b": "R5", "c": [_gated_x(16, 1), C1Y1 + WALL_T / 2], "axis": "x", "w": 1.0,
     "kind": "gated", "sign": "BAY 4"},
    # Dead ends: doors that never open. STAIR 1, at corridor A's west end
    # (where corridor A's EXIT sign points), is chained shut.
    {"id": "stair1", "a": "C1", "b": None, "c": [-4.2 - WALL_T / 2, (C1Y0 + C1Y1) / 2], "axis": "y", "w": DOOR_W,
     "kind": "locked", "sign": "STAIR 1"},
    {"id": "vault", "a": "C1", "b": None, "c": [R5X1 + WALL_T / 2, (C1Y0 + C1Y1) / 2], "axis": "y", "w": DOOR_W,
     "kind": "locked", "sign": "VAULT"},
    {"id": "jan", "a": "C3", "b": None, "c": [(C3X0 + C3X1) / 2, 2.0 - WALL_T / 2], "axis": "x", "w": DOOR_W,
     "kind": "locked", "sign": "JANITOR"},
    {"id": "exit", "a": "R5", "b": None, "c": [24.6, R5Y1 + WALL_T / 2], "axis": "x", "w": DOOR_W, "kind": "exit",
     "sign": ""},
    # STAIR 2: the service stair down (side level "stairwell"), at the far
    # (north) end of corridor B. Corridor B is reached only through moving
    # shelving (Bay 3's banks, or Bay 4's from Bay 2 / the fire doors), so the
    # stair is as deep in the maze as the exit. A LevelEntrance door on a
    # solid wall, like the exit (nothing baked for it).
    {"id": "stair", "a": "C3", "b": None, "c": [(C3X0 + C3X1) / 2, R5Y1 + WALL_T / 2], "axis": "x", "w": DOOR_W,
     "kind": "stair", "sign": "STAIR 2"},
]

ARRIVAL = [1.0, MAIN1]          # facing east down Bay 1's main aisle
EXIT = [24.6, R5Y1]             # the exit door's foot (north wall of Bay 4)
STAIR = [(C3X0 + C3X1) / 2, R5Y1]   # STAIR 2's door foot (north end wall of corridor B)

# ------------------------------------------------------------------- rows ---
# Strip rows (two-lamp 4 ft T8 strips hung across the ranges, parallel to
# the carriages' motion): a, b the ends of the row, n strips evenly along
# it, g the light group in its cell (-1: the night light, always on).


def _rows_bay(cell, x0, x1, n):
    y = [0.5335, REAR + 1.61, REAR + 4.84, MAIN1, D1 - REAR - 4.84, D1 - REAR - 1.61, D1 - 0.5335]
    g = [1, 1, 1, 0, 2, 3, 3]
    return [{"cell": cell, "a": [x0, yy], "b": [x1, yy], "n": n, "g": gg} for yy, gg in zip(y, g)]


ROWS = []
# Bay 1: as first built (five strips per row at 1.18 .. 10.43 m; the main
# aisle's first strip is the night light).
ROWS += _rows_bay("R1", 0.02, 11.59, 5)
ROWS[3] = {"cell": "R1", "a": [2.34, MAIN1], "b": [11.59, MAIN1], "n": 4, "g": 0}
ROWS.insert(3, {"cell": "R1", "a": [0.0, MAIN1], "b": [2.34, MAIN1], "n": 1, "g": -1, "night": True})
ROWS += _rows_bay("R3", R3X0 + 0.2, R5X1 - 0.2, 7)
# Bay 2: rows along y (the motion), over the main aisle, the ranges, the rear aisle.
for x, g in ((MAIN / 2, 0), (MAIN + 1.6, 1), (MAIN + 4.8, 1), (MAIN + 8.0, 2), (R4X1 - 0.5, 3)):
    ROWS.append({"cell": "R4", "a": [x, NY0 + 0.2], "b": [x, R4Y1 - 0.2], "n": 5, "g": g})
# Bay 4 (dark): only the main aisle has strips, one on each occupancy
# sensor, 5.5 m apart: dark between them. The aisles have their light bars.
for i, x in enumerate((15.6, 21.1, 26.6, 32.1)):
    ROWS.append({"cell": "R5", "a": [x - 0.61, R5MAIN], "b": [x + 0.61, R5MAIN], "n": 1, "g": i})
# Corridor A: a strip every 3.9 m, four sensor zones; a night light by Bay 1's door.
_c1y = (C1Y0 + C1Y1) / 2
for g, (x0, x1, n) in enumerate(((-4.2, 8.4, 3), (8.4, 16.2, 2), (16.2, 26.0, 3), (26.0, R5X1, 2))):
    ROWS.append({"cell": "C1", "a": [x0, _c1y], "b": [x1, _c1y], "n": n, "g": g})
ROWS.append({"cell": "C1", "a": [9.3, _c1y + 0.45], "b": [10.52, _c1y + 0.45], "n": 1, "g": -1, "night": True})
# Corridor B: three zones.
_c3x = (C3X0 + C3X1) / 2
for g, (y0, y1, n) in enumerate(((2.0, 11.0, 2), (11.0, 20.2, 2), (20.2, R5Y1, 3))):
    ROWS.append({"cell": "C3", "a": [_c3x, y0], "b": [_c3x, y1], "n": n, "g": g})
# Sorting: three rows of three, one sensor; the night light strip.
for y in (8.9, 11.85, 14.8):
    ROWS.append({"cell": "R2", "a": [11.812, y], "b": [19.0, y], "n": 3, "g": 0})
ROWS.append({"cell": "R2", "a": [11.812 + 0.3, 16.3], "b": [11.812 + 1.52, 16.3], "n": 1, "g": -1, "night": True})


def sensor_rects():
    """Where each light group's occupancy sensor sees you: round each of its
    rows (2.8 m either side, 0.8 m past the ends), within the cell."""
    out = {}
    for r in ROWS:
        if r["g"] < 0:
            continue
        x0, y0, x1, y1 = CELLS[r["cell"]]["rect"]
        a, b = r["a"], r["b"]
        if abs(a[1] - b[1]) < 1e-6:
            rr = [min(a[0], b[0]) - 0.8, a[1] - 2.8, max(a[0], b[0]) + 0.8, a[1] + 2.8]
        else:
            rr = [a[0] - 2.8, min(a[1], b[1]) - 0.8, a[0] + 2.8, max(a[1], b[1]) + 0.8]
        rr = [max(rr[0], x0 - 0.3), max(rr[1], y0 - 0.3), min(rr[2], x1 + 0.3), min(rr[3], y1 + 0.3)]
        out.setdefault(r["cell"], {}).setdefault(str(r["g"]), []).append([round(v, 4) for v in rr])
    return out


# ------------------------------------------------------------------ signs ---
# Signs on the walls (drawn into the labels atlas by filing.py --textures,
# placed by the level as one mesh per cell): c (x, y, z centre), n (the
# way it faces, Blender), size (w, h), img (the atlas key).
SIGNS = []


def _door_signs():
    for d in DOORS:
        if not d.get("sign") or d["kind"] == "exit":
            continue
        cx, cy = d["c"]
        for cell, side in ((d["a"], 1), (d["b"], -1)):
            if cell is None:
                continue
            x0, y0, x1, y1 = CELLS[cell]["rect"]
            if d["axis"] == "x":
                n = [0, -1] if cy > (y0 + y1) / 2 else [0, 1]
                pos = [cx, cy + n[1] * (WALL_T / 2 + 0.006), DOOR_H + 0.26]
            else:
                n = [-1, 0] if cx > (x0 + x1) / 2 else [1, 0]
                pos = [cx + n[0] * (WALL_T / 2 + 0.006), cy, DOOR_H + 0.26]
            # the sign says where the door goes, from this side
            other = d["b"] if cell == d["a"] else d["a"]
            name = d["sign"] if other is None else CELLS[other]["name"]
            if d["kind"] == "locked" or d["kind"] == "arrive":
                name = d["sign"]
            SIGNS.append({"cell": cell, "c": [round(v, 4) for v in pos], "n": n, "size": [0.46, 0.115],
                          "img": "door:" + name})


_door_signs()
# Floor plans ("YOU ARE HERE"): in corridor A by Bay 1's door, in sorting, in
# corridor B. The one in Bay 2 is an old revision (it shows Bay 4's doors
# where they used to be, and no corridor B).
SIGNS += [
    {"cell": "C1", "c": [8.6, C1Y1 - 0.006, 1.45], "n": [0, -1], "size": [1.0, 0.714], "img": "plan:C1"},
    {"cell": "R2", "c": [12.5, D1 - 0.006, 1.45], "n": [0, -1], "size": [1.0, 0.714], "img": "plan:R2"},
    {"cell": "C3", "c": [C3X0 + 0.006, 13.0, 1.45], "n": [1, 0], "size": [1.0, 0.714], "img": "plan:C3"},
    {"cell": "R4", "c": [0.006, 21.0, 1.45], "n": [1, 0], "size": [1.0, 0.714], "img": "plan:old"},
    # bay range signs on the walls by the main aisles
    {"cell": "R1", "c": [0.006, MAIN1 + 1.9, 2.55], "n": [1, 0], "size": [0.6, 0.2], "img": "range:R1"},
    {"cell": "R3", "c": [R3X0 + 0.006, MAIN1 + 1.2, 2.55], "n": [1, 0], "size": [0.6, 0.2], "img": "range:R3"},
    {"cell": "R4", "c": [0.006, 24.9, 2.55], "n": [1, 0], "size": [0.6, 0.2], "img": "range:R4"},
    {"cell": "R5", "c": [R5X0 + 0.006, R5MAIN + 0.3, 2.55], "n": [1, 0], "size": [0.6, 0.2], "img": "range:R5"},
    # directions in the corridors (one of them lies: it points at STAIR 1,
    # which is chained shut; the stair that opens is STAIR 2, off corridor B)
    {"cell": "C1", "c": [4.0, C1Y1 - 0.006, 2.45], "n": [0, -1], "size": [0.6, 0.2], "img": "arrow:EXIT:W"},
    {"cell": "C1", "c": [22.0, C1Y0 + 0.006, 2.45], "n": [0, 1], "size": [0.6, 0.2], "img": "arrow:BAY 3:E"},
    {"cell": "C1", "c": [13.2, C1Y1 - 0.006, 2.45], "n": [0, -1], "size": [0.6, 0.2], "img": "arrow:BAY 2:W"},
    {"cell": "C3", "c": [C3X1 - 0.006, 10.5, 2.45], "n": [-1, 0], "size": [0.6, 0.2], "img": "arrow:BAY 4:N"},
    {"cell": "R5", "c": [24.6 - 1.1, R5Y1 - 0.006, 1.5], "n": [0, -1], "size": [0.46, 0.115], "img": "notice"},
]

# Props: records carts (Godot geometry) in sorting and here and there.
CARTS = [
    {"cell": "R1", "bank": 0},               # Bay 1: the one in bank A's aisle (moves)
    {"cell": "R2", "c": [13.0, 10.3], "yaw": 0.05},
    {"cell": "R2", "c": [13.9, 10.4], "yaw": -0.08},
    {"cell": "R2", "c": [17.9, 14.2], "yaw": 1.62},
    {"cell": "C1", "c": [30.4, C1Y0 + 0.35], "yaw": 1.571},
    {"cell": "C3", "c": [C3X0 + 0.35, 24.5], "yaw": 0.0},
]

# Fixed furniture (built in the kits, solid): kind, centre, size (x, y).
PROPS = [
    {"cell": "R2", "kind": "stool", "c": [12.4, 12.6], "size": [0.41, 0.41]},
    {"cell": "R2", "kind": "table", "c": [15.1, 11.6], "size": [1.83, 0.91]},
    {"cell": "R2", "kind": "table", "c": [15.1, 13.6], "size": [1.83, 0.91]},
    {"cell": "R2", "kind": "sorter", "c": [18.75, 11.0], "size": [0.38, 2.2]},
    {"cell": "R2", "kind": "desk", "c": [17.6, 7.22], "size": [1.52, 0.76]},
    {"cell": "R2", "kind": "chair", "c": [17.45, 7.98], "size": [0.5, 0.5]},
    {"cell": "C3", "kind": "bucket", "c": [C3X0 + 0.45, 2.5], "size": [0.42, 0.42]},
]


def _side_of(d, cid):
    """The wall a door is in, as seen from cell cid: (axis, face coord, inward
    normal, wall extent)."""
    x0, y0, x1, y1 = CELLS[cid]["rect"]
    cx, cy = d["c"]
    if d["axis"] == "x":
        return ("x", y0, (0, 1), (x0, x1)) if cy < (y0 + y1) / 2 else ("x", y1, (0, -1), (x0, x1))
    return ("y", x0, (1, 0), (y0, y1)) if cx < (x0 + x1) / 2 else ("y", x1, (-1, 0), (y0, y1))


def place_leaves():
    """Each open fire door's leaf, swung round flat against the wall beside
    its opening (held by its magnet), on its "leaf" side: d["leaf_rect"]
    (Blender x0, y0, x1, y1) and d["leaf_along"] (a0, a1 along the wall)."""
    for d in DOORS:
        if d["kind"] not in ("door", "gated"):
            continue
        cid = d["a"] if d.get("leaf", "a") == "a" else d["b"]
        axis, at, nrm, (s0, s1) = _side_of(d, cid)
        a = d["c"][0] if axis == "x" else d["c"][1]
        o0, o1 = a - d["w"] / 2, a + d["w"] / 2
        others = []
        for e in DOORS:
            if e is d or e["axis"] != axis:
                continue
            if cid not in (e["a"], e["b"]):
                continue
            ea = e["c"][0] if axis == "x" else e["c"][1]
            eacross = e["c"][1] if axis == "x" else e["c"][0]
            if abs(eacross - (d["c"][1] if axis == "x" else d["c"][0])) < 0.1:
                others.append((ea - e["w"] / 2 - 0.1, ea + e["w"] / 2 + 0.1))
        for s in SIGNS:
            if s["cell"] == cid and abs((s["n"][0], s["n"][1])[0] - nrm[0]) < 0.1 and abs(s["n"][1] - nrm[1]) < 0.1 \
                    and s["c"][2] < 2.2:
                sa = s["c"][0] if axis == "x" else s["c"][1]
                others.append((sa - s["size"][0] / 2 - 0.05, sa + s["size"][0] / 2 + 0.05))
        w = o1 - o0
        left = (o0 - 0.06 - w, o0 - 0.06)
        right = (o1 + 0.06, o1 + 0.06 + w)

        def ok(r):
            return r[0] > s0 + 0.05 and r[1] < s1 - 0.05 and all(r[1] < q0 or r[0] > q1 for q0, q1 in others)
        r = left if ok(left) else right
        d["leaf_cell"] = cid
        d["leaf_along"] = [round(r[0], 4), round(r[1], 4)]
        off0, off1 = 0.03, 0.12
        if axis == "x":
            ya, yb = at + nrm[1] * off0, at + nrm[1] * off1
            d["leaf_rect"] = [round(r[0], 4), round(min(ya, yb), 4), round(r[1], 4), round(max(ya, yb), 4)]
        else:
            xa, xb = at + nrm[0] * off0, at + nrm[0] * off1
            d["leaf_rect"] = [round(min(xa, xb), 4), round(r[0], 4), round(max(xa, xb), 4), round(r[1], 4)]


# The labels atlas (assets/levels/filing/textures/labels_diff.jpg, 1024 px,
# drawn by filing.py --labels): pixel rects (x, y, w, h).
DOOR_SIGNS = ["BAY 1", "BAY 2", "BAY 3", "BAY 4", "SORTING", "CORRIDOR A", "CORRIDOR B", "NO EXIT", "STAIR 2",
              "VAULT", "JANITOR", "notice", "STAIR 1"]
WIDE_SIGNS = ["arrow:EXIT:W", "arrow:BAY 3:E", "arrow:BAY 2:W", "arrow:BAY 4:N", "range:R1", "range:R3", "range:R4",
              "range:R5"]
PLAN_WORLD = [-5.4, -1.0, 38.2, 31.8]        # what a floor plan shows (Blender x0, y0, x1, y1)
PLAN_PX = [8, 44, 496, 312]                  # where in its 512 x 366 picture (x, y, w, h)


def atlas():
    a = {}
    ncards = sum(b["n"] for b in BANKS)
    for i in range(ncards):
        a["card:%d" % i] = [(i % 16) * 64, (i // 16) * 42, 64, 42]
    for k, n in enumerate(DOOR_SIGNS):
        if k < 12:
            a["door:" + n] = [(k % 4) * 256, 256 + (k // 4) * 64, 256, 64]
        else:
            # (the 13th: the free end of the last row of range cards, at the
            # same 4:1 shape, 168 x 42 px)
            a["door:" + n] = [768 + (k - 12) * 168, 210, 168, 42]
    a["notice"] = a["door:notice"]
    for k, n in enumerate(WIDE_SIGNS):
        a[n] = [(k % 4) * 256, 448 + (k // 4) * 85, 256, 85]
    a["dot"] = [0, 620, 20, 20]
    a["plan"] = [0, 640, 512, 366]
    a["plan_old"] = [512, 640, 512, 366]
    return a


place_leaves()
# Portals (for drawing only the rooms you can see): every open door.
PORTALS = [d for d in DOORS if d["kind"] in ("door", "gated")]


def door_span(d):
    """The opening's two ends on the wall's centre line."""
    cx, cy = d["c"]
    h = d["w"] / 2
    return ([cx - h, cy], [cx + h, cy]) if d["axis"] == "x" else ([cx, cy - h], [cx, cy + h])


def area():
    return sum((c["rect"][2] - c["rect"][0]) * (c["rect"][3] - c["rect"][1]) for c in CELLS.values())


def data():
    return {"cells": CELLS, "banks": BANKS, "doors": DOORS, "rows": ROWS, "sensors": sensor_rects(), "signs": SIGNS,
            "carts": CARTS, "props": PROPS, "arrival": ARRIVAL, "exit": EXIT, "stair": STAIR, "atlas": atlas(), "plan_world": PLAN_WORLD,
            "plan_px": PLAN_PX,
            "consts": {"CAR_W": CAR_W, "FIX_W": FIX_W, "AISLE": AISLE, "SEC_W": SEC_W, "END_T": END_T,
                       "SHELF_D": SHELF_D, "CEIL": CEIL, "WALL_T": WALL_T, "MAIN": MAIN, "REAR": REAR}}


def _gd(v, ind=0):
    """A Python value as a GDScript literal."""
    if isinstance(v, bool):
        return "true" if v else "false"
    if v is None:
        return "null"
    if isinstance(v, (int,)):
        return str(v)
    if isinstance(v, float):
        return repr(round(v, 5))
    if isinstance(v, str):
        return json.dumps(v)
    pad = "\t" * (ind + 1)
    if isinstance(v, (list, tuple)):
        if all(not isinstance(x, (list, dict, tuple)) for x in v):
            return "[" + ", ".join(_gd(x) for x in v) + "]"
        return "[\n" + ",\n".join(pad + _gd(x, ind + 1) for x in v) + ",\n" + "\t" * ind + "]"
    if isinstance(v, dict):
        if all(not isinstance(x, (list, dict, tuple)) for x in v.values()) and len(v) <= 6:
            return "{" + ", ".join(f"{json.dumps(str(k))}: {_gd(x)}" for k, x in v.items()) + "}"
        return "{\n" + ",\n".join(f"{pad}{json.dumps(str(k))}: {_gd(x, ind + 1)}" for k, x in v.items()) + ",\n" + \
            "\t" * ind + "}"
    raise TypeError(type(v))


def write_gd(path):
    with open(path, "w") as f:
        f.write("extends RefCounted\n## The Stacks' floor plan (cells, shelving banks, doors, strip rows, sensors,\n"
                "## signs). GENERATED by tools/blender/levels/filing_layout.py: edit that and\n"
                "## re-run it, never this file. Blender coordinates (x east, y north).\n\n")
        f.write("const DATA := " + _gd(data()) + "\n")


def draw_map(path, states=None):
    """A top-down plan: walls, doors, shelving (carriages as pressed), rows,
    the three routes to the exit."""
    from PIL import Image, ImageDraw
    S = 36
    X0, Y0 = -5.5, -1.2
    W, H = int((C3X1 + 1.5 - X0) * S), int((R4Y1 + 1.6 - Y0) * S) + 60

    def P(x, y):
        return (int((x - X0) * S), int(H - 60 - (y - Y0) * S))

    im = Image.new("RGB", (W, H), (24, 25, 27))
    dr = ImageDraw.Draw(im)
    for cid, c in CELLS.items():
        x0, y0, x1, y1 = c["rect"]
        dr.rectangle([P(x0 - WALL_T, y1 + WALL_T), P(x1 + WALL_T, y0 - WALL_T)], fill=(150, 150, 146))
    for cid, c in CELLS.items():
        x0, y0, x1, y1 = c["rect"]
        col = {"bay": (226, 224, 216), "corridor": (205, 210, 214), "sort": (220, 226, 210)}[c["kind"]]
        if c.get("dark"):
            col = (150, 150, 158)
        dr.rectangle([P(x0, y1), P(x1, y0)], fill=col)
    for d in DOORS:
        a, b = door_span(d)
        col = {"door": (226, 224, 216), "gated": (250, 200, 80), "arrive": (60, 140, 230), "locked": (120, 40, 40),
               "exit": (230, 40, 30), "stair": (170, 60, 200)}[d["kind"]]
        t = WALL_T / 2 + 0.02
        if d["axis"] == "x":
            dr.rectangle([P(a[0], a[1] + t), P(b[0], b[1] - t)], fill=col)
        else:
            dr.rectangle([P(a[0] - t, b[1]), P(b[0] + t, a[1])], fill=col)
    for bi, b in enumerate(BANKS):
        gm = bank_geom(b)
        aisles = (states or {}).get(bi, b["aisles"])
        L = gm["L"]

        def poly(u0, u1, v0, v1, fill):
            pts = [P(*to_world(b, u, v)) for u, v in ((u0, v0), (u1, v0), (u1, v1), (u0, v1))]
            dr.polygon(pts, fill=fill, outline=(40, 40, 40))
        poly(0, FIX_W, 0, L, (110, 100, 86))
        poly(gm["W"] - FIX_W, gm["W"], 0, L, (110, 100, 86))
        for i in range(b["n"]):
            u = FIX_W + i * CAR_W + sum(AISLE for a in aisles if a <= i)
            poly(u, u + CAR_W, 0, L, (140, 120, 92))
            hx, hy = to_world(b, u + CAR_W / 2, L + 0.12)
            dr.ellipse([P(hx - 0.07, hy + 0.07), P(hx + 0.07, hy - 0.07)], fill=(30, 30, 30))
    for r in ROWS:
        n = r["n"]
        for i in range(n):
            t = (i + 0.5) / n
            x = r["a"][0] + (r["b"][0] - r["a"][0]) * t
            y = r["a"][1] + (r["b"][1] - r["a"][1]) * t
            horiz = abs(r["a"][1] - r["b"][1]) < 1e-6
            dx, dy = (0.61, 0.06) if horiz else (0.06, 0.61)
            dr.rectangle([P(x - dx, y + dy), P(x + dx, y - dy)], fill=(255, 250, 200) if r["g"] >= 0 else (120, 255, 140))
    # the three routes, through the aisles as drawn
    st = states or {}

    def gc(bi, g, v):
        b = BANKS[bi]
        aisles = st.get(bi, b["aisles"])
        return to_world(b, gap_u(b, g, aisles) + AISLE / 2, v)

    c1y = (C1Y0 + C1Y1) / 2
    ga = gc(1, st.get(1, BANKS[1]["aisles"])[0], 0)
    r4 = gc(4, st.get(4, BANKS[4]["aisles"])[0], 0)
    r3 = gc(3, st.get(3, BANKS[3]["aisles"])[-1], 0)
    g1x = DOORS[[d["id"] for d in DOORS].index("g1")]["c"][0]
    routes = [
        ((40, 170, 60), [ARRIVAL, (ga[0], MAIN1), (ga[0], D1 - 0.5), (10.65, D1 - 0.5), (10.65, c1y), (0.95, c1y),
                         (0.95, r4[1]), (R4X1 - 0.5, r4[1]), (R4X1 - 0.5, R5MAIN), (EXIT[0], R5MAIN),
                         (EXIT[0], R5Y1 - 0.4)]),
        ((220, 120, 20), [(10.65, c1y - 0.2), (g1x, c1y - 0.2), (g1x, R5MAIN - 0.2), (EXIT[0] - 0.2, R5MAIN - 0.2),
                          (EXIT[0] - 0.2, R5Y1 - 0.5)]),
        ((40, 110, 220), [(10.65, c1y + 0.2), (33.9, c1y + 0.2), (33.9, D1 - 0.5), (r3[0], D1 - 0.5), (r3[0], MAIN1),
                          ((C3X0 + C3X1) / 2, MAIN1), ((C3X0 + C3X1) / 2, R5MAIN), (EXIT[0] + 0.2, R5MAIN + 0.25),
                          (EXIT[0] + 0.2, R5Y1 - 0.3)]),
        ((170, 60, 200), [((C3X0 + C3X1) / 2 + 0.25, R5MAIN - 2.0), ((C3X0 + C3X1) / 2 + 0.25, STAIR[1] - 0.3)]),
    ]
    for col, pts in routes:
        dr.line([P(*p) for p in pts], fill=col, width=5)
    for cid, c in CELLS.items():
        x0, y0, x1, y1 = c["rect"]
        dr.text(P(x0 + 0.3, y1 - 0.3), c["name"] + f"  {x1 - x0:.1f} x {y1 - y0:.1f} m", fill=(10, 10, 10))
    ax_, ay_ = P(*ARRIVAL)
    dr.ellipse([ax_ - 9, ay_ - 9, ax_ + 9, ay_ + 9], fill=(60, 140, 230))
    ex, ey = P(*EXIT)
    dr.ellipse([ex - 9, ey - 9, ex + 9, ey + 9], fill=(230, 40, 30))
    sx_, sy_ = P(*STAIR)
    dr.ellipse([sx_ - 9, sy_ - 9, sx_ + 9, sy_ + 9], fill=(170, 60, 200))
    dr.text(P(STAIR[0] - 1.6, STAIR[1] + 0.9), "STAIR 2 (down)", fill=(230, 230, 230))
    dr.text(P(-5.4, (C1Y0 + C1Y1) / 2 + 1.4), "STAIR 1 (locked)", fill=(230, 230, 230))
    dr.text((10, H - 50), "The Stacks, %.0f m2.  blue dot: arrival   red: exit   purple: STAIR 2 (down to the "
            "stairwell)   yellow: fire doors onto Bay 4's range ends (open only when an aisle lines up)   dark red: locked"
            % area(), fill=(230, 230, 230))
    dr.text((10, H - 32), "routes: green  Bay 1 > corridor A > Bay 2 (any aisle) > Bay 4 main aisle > exit;  orange  "
            "corridor A > a lined-up fire door > Bay 4 aisle;  blue  corridor A > Bay 3 (any aisle) > corridor B > Bay 4 "
            "(and north up corridor B to STAIR 2)  (shelving drawn in one of its states)",
            fill=(230, 230, 230))
    im.save(path)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.normpath(os.path.join(here, "..", "..", ".."))
    write_gd(os.path.join(root, "scripts/world/levels/filing_layout.gd"))
    print("area %.1f m2" % area())
    for k, c in CELLS.items():
        x0, y0, x1, y1 = c["rect"]
        print(k, c["name"], "%.2f x %.2f = %.1f m2" % (x1 - x0, y1 - y0, (x1 - x0) * (y1 - y0)))
    for b in BANKS:
        g = bank_geom(b)
        print("bank", b["cell"], b["name"], "o", b["o"], "L %.3f W %.3f" % (g["L"], g["W"]))
    for d in DOORS:
        print("door", d["id"], d["c"])
    if "--map" in sys.argv:
        # (drawn with Bay 4's aisles at 6 and 16: both fire doors lined up)
        draw_map(sys.argv[sys.argv.index("--map") + 1], {5: [6, 16]})
