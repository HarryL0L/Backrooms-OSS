"""Dead Mall level kit: builds the mall sections from the props in
mall_props.py, bakes their lighting (Cycles: ceiling panels, dusk light
through the skylights, bounce light) into a lightmap per section, and
exports each as a GLB with:
  - one visual mesh (materials named for the Godot mall shader, UV = lightmap)
  - "*-colonly" boxes (Godot turns them into static collision)
  - "spot_*" empties: places for mannequins, the exit door, the entity...

Sections tile along X (Blender; Godot X) and share the concourse cross-
section: floor at z 0, open ends 12 m wide (y -6..6), 6 m high.

Run:  python mall_kit.py <assets/mall dir> [--only concourse_a,...] [--fast] [--preview dir]
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import bpy  # noqa: E402,I001
import numpy as np  # noqa: E402
import mall_props as P  # noqa: E402
from mall_props import Builder, _eul  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

OUT = sys.argv[1]
ONLY = sys.argv[sys.argv.index("--only") + 1].split(",") if "--only" in sys.argv else None
FAST = "--fast" in sys.argv
PREVIEW = sys.argv[sys.argv.index("--preview") + 1] if "--preview" in sys.argv else None
LM = 512 if FAST else 1024
LM_SCALE = 4.0          # lightmap stores sqrt(light / LM_SCALE)

HALF_W = 6.0            # concourse half width
H = 6.0                 # concourse ceiling
SHOP_D = 7.0            # shop depth behind the front


class Section:
    def __init__(self, name, length):
        self.name = name
        self.length = length
        self.b = Builder()
        self.cols = []          # (size, loc, rot_z)
        self.spots = []         # (name, loc, rot_z)

    def col(self, size, loc, rz=0.0):
        self.cols.append((size, loc, rz))

    def spot(self, name, loc, rz=0.0):
        self.spots.append((name, loc, rz))

    def prop(self, name, loc, rz=0.0, col=None):
        self.b.place(P.PROPS[name](), Matrix.LocRotScale(Vector(loc), _eul((0, 0, rz)), None))
        if col:
            self.col(col, (loc[0], loc[1], col[2] / 2), rz)


# --------------------------------------------------------------- pieces ---
def oquad(b, corners, m, toward):
    """A one-sided quad facing the point `toward` (the inside of the room).
    Fixed vertex orders flipped half the shop interiors inside out (the
    south side of the concourse), so they vanished into the void."""
    a, c1, c2 = (Vector(v) for v in corners[:3])
    n = (c1 - a).cross(c2 - a)
    if n.dot(Vector(toward) - a) < 0:
        corners = list(reversed(corners))
    b.quad(corners, m)



def ceiling(s, x0, x1, y0, y1, z, rng, lights=True, dead=0.25, skylight=None):
    """Drop ceiling with a T-bar grid and recessed light panels; an optional
    (y0, y1) strip is left open for a skylight."""
    b = s.b
    ys = [(y0, y1)] if skylight is None else [(y0, skylight[0]), (skylight[1], y1)]
    for a, c in ys:
        if c - a < 0.01:
            continue
        b.quad([(x0, a, z), (x0, c, z), (x1, c, z), (x1, a, z)], "ceiling_tile")
        y = a
        while y <= c + 1e-6:
            b.box((x1 - x0, 0.025, 0.02), ((x0 + x1) / 2, y, z - 0.01), "metal_bright")
            y += 1.2
        x = x0
        while x <= x1 + 1e-6:
            b.box((0.025, c - a, 0.02), (x, (a + c) / 2, z - 0.01), "metal_bright")
            x += 1.2
        if lights:
            x = x0 + 2.0
            while x < x1 - 0.5:
                y = a + 1.8
                while y < c - 0.5:
                    m = "light_dead" if rng.random() < dead else "light_panel"
                    b.box((1.15, 0.55, 0.02), (x, y, z - 0.012), m)
                    y += 3.6
                x += 4.0


def skylight_vault(s, x0, x1, y0, y1, z):
    """Gabled glass roof with bronze ribs over a ceiling opening."""
    b = s.b
    yc = (y0 + y1) / 2
    rise = 1.4
    b.quad([(x0, y0, z), (x1, y0, z), (x1, yc, z + rise), (x0, yc, z + rise)], "glass")
    b.quad([(x0, yc, z + rise), (x1, yc, z + rise), (x1, y1, z), (x0, y1, z)], "glass")
    x = x0
    while x <= x1 + 1e-6:
        b.tube([(x, y0, z), (x, yc, z + rise), (x, y1, z)], 0.04, "metal_frame", 6)
        x += 2.5
    b.tube([(x0, yc, z + rise), (x1, yc, z + rise)], 0.05, "metal_frame", 6)
    for y in (y0, y1):
        b.box((x1 - x0, 0.3, 0.4), ((x0 + x1) / 2, y, z - 0.2), "wall_paint")      # upstand


def shopfront(s, x0, x1, side, kind, rng, contents="clothes"):
    """A shop on one side of the concourse. side=+1: north (y>0), -1: south.
    kind: 'open' (glass front, door gap), 'shutter' (closed), 'half' (shutter
    stuck half a metre up)."""
    b = s.b
    yf = side * HALF_W
    yb = side * (HALF_W + SHOP_D)
    xc = (x0 + x1) / 2
    xa, xb = x0 + 0.3, x1 - 0.3
    # Pilasters at the shop edges (half of each, so sections tile).
    for x, w in ((x0 + 0.15, 0.3), (x1 - 0.15, 0.3)):
        b.box((w, 0.5, H), (x, yf + side * 0.05, H / 2), "wall_paint", bevel=0.01)
    # Bulkhead above the front, sign band, sign box.
    b.box((xb - xa, 0.3, H - 3.4), (xc, yf + side * 0.15, 3.4 + (H - 3.4) / 2), "wall_paint")
    b.box((xb - xa, 0.32, 0.12), (xc, yf + side * 0.15, 3.36), "metal_frame")
    sign = rng.choice(["sign_red", "sign_teal", "sign_cream"])
    sw = rng.uniform(3.2, 4.6)
    b.box((sw, 0.22, 0.8), (xc, yf - side * 0.1, 4.1), sign, bevel=0.03)
    letters = rng.randint(4, 7)
    for k in range(letters):
        if rng.random() < 0.2:
            continue          # fallen letter
        lx = xc - sw * 0.35 + k * (sw * 0.7 / max(letters - 1, 1))
        b.box((0.32, 0.06, 0.42), (lx, yf - side * 0.23, 4.1 + rng.uniform(-0.02, 0.02)),
              "sign_cream" if sign != "sign_cream" else "sign_red", (0, 0, 0), bevel=0.01)
    # Interior shell, every face turned to the inside.
    inside = (xc, (yf + yb) / 2, 1.5)
    oquad(b, [(xa, yf, 0.003), (xb, yf, 0.003), (xb, yb, 0.003), (xa, yb, 0.003)], "carpet" if contents == "clothes" else "tile_white", (xc, (yf + yb) / 2, 2.0))
    oquad(b, [(xa, yb, 0), (xb, yb, 0), (xb, yb, 3.6), (xa, yb, 3.6)], "wall_paint", inside)
    for x in (xa, xb):
        oquad(b, [(x, yf, 0), (x, yb, 0), (x, yb, 3.6), (x, yf, 3.6)], "wall_paint", inside)
    # Some of the shop lights still work, so the interiors aren't black holes.
    ceiling(s, xa, xb, min(yf, yb), max(yf, yb), 3.6, rng, lights=True, dead=0.35)
    s.col((0.3, SHOP_D, 3.6), (xa - 0.15, (yf + yb) / 2, 1.8))
    s.col((0.3, SHOP_D, 3.6), (xb + 0.15, (yf + yb) / 2, 1.8))
    s.col((xb - xa, 0.3, 3.6), (xc, yb + side * 0.15, 1.8))
    # Front.
    b.box((xb - xa, 0.14, 0.25), (xc, yf, 0.125), "metal_frame")
    b.box((xb - xa, 0.14, 0.15), (xc, yf, 3.2), "metal_frame")
    door = (xc - 1.2, xc + 1.2) if kind == "open" else None
    x = xa
    n = max(2, round((xb - xa) / 1.55))
    xs = [xa + (xb - xa) * k / n for k in range(n + 1)]
    for k, x in enumerate(xs):
        b.box((0.09, 0.14, 3.2), (x, yf, 1.6), "metal_frame")
    for xl, xr in zip(xs, xs[1:]):
        if door and xl >= door[0] - 0.01 and xr <= door[1] + 0.01:
            continue
        if door and xl < door[1] and xr > door[0]:
            # pane cut by the door gap
            for a, c in ((xl, door[0]), (door[1], xr)):
                if c - a > 0.05:
                    b.quad([(a, yf, 0.25), (c, yf, 0.25), (c, yf, 3.12), (a, yf, 3.12)], "glass")
            continue
        b.quad([(xl, yf, 0.25), (xr, yf, 0.25), (xr, yf, 3.12), (xl, yf, 3.12)], "glass")
    if door:
        b.box((0.09, 0.14, 3.2), (door[0], yf, 1.6), "metal_frame")
        b.box((0.09, 0.14, 3.2), (door[1], yf, 1.6), "metal_frame")
        s.col((door[0] - xa, 0.2, 3.3), ((xa + door[0]) / 2, yf, 1.65))
        s.col((xb - door[1], 0.2, 3.3), ((door[1] + xb) / 2, yf, 1.65))
    else:
        s.col((xb - xa, 0.2, 3.3), (xc, yf, 1.65))
    if kind in ("shutter", "half"):
        z0 = 0.55 if kind == "half" else 0.0
        ys = yf - side * 0.12
        z = z0
        while z < 3.15:
            b.box((xb - xa - 0.1, 0.04, 0.085), (xc, ys, z + 0.045), "shutter")
            b.box((xb - xa - 0.1, 0.02, 0.02), (xc, ys - side * 0.025, z + 0.09), "shutter")
            z += 0.1
        b.box((xb - xa - 0.1, 0.05, 0.06), (xc, ys, z0 + 0.03), "metal_frame")
        b.box((xb - xa, 0.45, 0.45), (xc, yf - side * 0.2, 3.45), "shutter")
        for x in (xa + 0.05, xb - 0.05):
            b.box((0.08, 0.1, 3.2), (x, ys, 1.6), "metal_frame")
    # Contents and mannequin spots.
    if kind != "shutter" and contents in ("clothes", "shelves", "arcade", "cafe"):
        if contents == "clothes":
            for k in range(3):
                s.prop("clothes_rack", (xa + 1.8 + k * 2.4, yf + side * (3.6 + (k % 2) * 1.4), 0), rng.uniform(-0.3, 0.3))
            s.prop("counter", (xb - 2.0, yb - side * 1.2, 0), 0 if side > 0 else math.pi, col=(2.4, 0.7, 1.05))
            # Window display: a raised plinth with mannequins facing out.
            b.box((xb - xa - 0.6, 1.4, 0.3), (xc, yf + side * 0.9, 0.15), "wood", bevel=0.02)
            s.col((xb - xa - 0.6, 1.4, 0.3), (xc, yf + side * 0.9, 0.15))
            for k, dx in enumerate((-2.8, -1.4, 1.4, 2.8)):
                if abs(dx) < 1.3 and door:
                    continue
                s.spot(f"spot_mannequin_{s.name}_{side}_{x0:.0f}_{k}", (xc + dx, yf + side * 0.9, 0.3), 0.0 if side > 0 else math.pi)
        elif contents == "arcade":
            # An arcade: cabinets round the walls, their screens still on.
            rz = 0.0 if side > 0 else math.pi
            for k in range(5):
                s.prop("arcade_cabinet", (xa + 1.0 + k * 1.9, yb - side * 0.6, 0), rz, col=(0.7, 0.75, 1.9))
            for k in range(3):
                s.prop("arcade_cabinet", (xa + 2.2 + k * 2.6, yf + side * 3.4, 0), rz + rng.uniform(-0.15, 0.15), col=(0.7, 0.75, 1.9))
        elif contents == "cafe":
            s.prop("counter", (xc, yb - side * 1.2, 0), 0 if side > 0 else math.pi, col=(2.4, 0.7, 1.05))
            for k in range(3):
                s.prop("table_set", (xa + 1.8 + k * 3.0, yf + side * (2.4 + (k % 2) * 1.6), 0), rng.uniform(0, 6.28), col=(1.6, 1.6, 0.8))
        else:
            for k in range(3):
                s.prop("shelving", (xa + 1.5 + k * 2.8, yb - side * 0.35, 0), 0 if side > 0 else math.pi, col=(1.2, 0.4, 2.0))
            for k in range(2):
                s.prop("shelving", (xa + 2.6 + k * 4.0, yf + side * 3.6, 0), math.pi / 2, col=(1.2, 0.4, 2.0))
            s.spot(f"spot_mannequin_{s.name}_{side}_{x0:.0f}_0", (xa + 1.0, yf + side * 1.2, 0.0), 0.0 if side > 0 else math.pi)
        if rng.random() < 0.5:
            s.prop("empty_stand", (xc + rng.uniform(-2, 2), yf + side * 2.0, 0), rng.uniform(0, 6))


def concourse_shell(s, x0, x1, rng, skylight=True):
    b = s.b
    b.quad([(x0, -HALF_W, 0), (x1, -HALF_W, 0), (x1, HALF_W, 0), (x0, HALF_W, 0)], "terrazzo")
    s.col((x1 - x0, 2 * (HALF_W + SHOP_D) + 1, 0.4), ((x0 + x1) / 2, 0, -0.2))
    ceiling(s, x0, x1, -HALF_W, HALF_W, H, rng, skylight=(-2.0, 2.0) if skylight else None)
    if skylight:
        skylight_vault(s, x0, x1, -2.0, 2.0, H)
    # Terrazzo border strips (brass inlay lines).
    for y in (-HALF_W + 0.5, HALF_W - 0.5):
        b.box((x1 - x0, 0.03, 0.004), ((x0 + x1) / 2, y, 0.002), "metal_frame")
    x = x0 + 2.5
    while x < x1:
        b.box((0.03, 2 * HALF_W - 1, 0.004), (x, 0, 0.002), "metal_frame")
        x += 5.0


# ------------------------------------------------------------- sections ---
def concourse_a():
    s = Section("concourse_a", 20.0)
    rng = random.Random(11)
    concourse_shell(s, -10, 10, rng)
    shopfront(s, -10, 0, 1, "open", rng, "clothes")
    shopfront(s, 0, 10, 1, "shutter", rng)
    shopfront(s, -10, 0, -1, "half", rng, "shelves")
    shopfront(s, 0, 10, -1, "open", rng, "shelves")
    s.prop("planter_palm", (-5, 0, 0), 0.3, col=(1.3, 1.3, 0.6))
    s.prop("bench", (-5, 2.0, 0), math.pi, col=(1.8, 0.5, 0.7))
    s.prop("bench", (-5, -2.0, 0), 0, col=(1.8, 0.5, 0.7))
    s.prop("trash_bin", (-2.6, 2.2, 0), 0, col=(0.6, 0.6, 1.0))
    s.prop("planter_shrub", (5, 0, 0), 1.0, col=(1.3, 1.3, 0.6))
    s.prop("wet_floor_sign", (6.8, -3.2, 0), 0.6)
    s.prop("payphone", (9.6, -5.7, 0), math.pi, col=(0.4, 0.3, 1.8))
    s.spot("spot_patrol_a", (-8, 0, 0))
    s.spot("spot_patrol_b", (8, 0, 0))
    return s


def concourse_b():
    s = Section("concourse_b", 20.0)
    rng = random.Random(23)
    concourse_shell(s, -10, 10, rng)
    shopfront(s, -10, 0, 1, "shutter", rng)
    shopfront(s, 0, 10, 1, "open", rng, "clothes")
    shopfront(s, -10, 0, -1, "open", rng, "clothes")
    shopfront(s, 0, 10, -1, "shutter", rng)
    s.prop("kiosk", (-3.5, 0, 0), 0.0, col=(2.5, 1.5, 2.5))
    s.prop("shopping_cart", (-0.8, 2.6, 0), 2.2)
    s.prop("planter_palm", (5.5, 0, 0), 1.2, col=(1.3, 1.3, 0.6))
    s.prop("bench", (5.5, -2.0, 0), 0, col=(1.8, 0.5, 0.7))
    s.prop("trash_bin", (8.2, 2.3, 0), 0, col=(0.6, 0.6, 1.0))
    s.prop("directory", (2.0, -3.6, 0), -0.2, col=(0.9, 0.3, 2.1))
    s.spot("spot_patrol_a", (-8, 0, 0))
    s.spot("spot_patrol_b", (8, 0, 0))
    return s


def fountain_court():
    s = Section("fountain_court", 24.0)
    rng = random.Random(37)
    b = s.b
    x0, x1, y0, y1 = -12, 12, -12, 12
    HC = 9.0
    b.quad([(x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0)], "terrazzo")
    s.col((24, 24 + 2 * SHOP_D, 0.4), (0, 0, -0.2))
    # Radiating brass inlay around the fountain.
    for k in range(16):
        a = 2 * math.pi * k / 16
        b.box((5.5, 0.03, 0.004), (math.cos(a) * 6.3, math.sin(a) * 6.3, 0.002), "metal_frame", (0, 0, a))
    b.lathe([(8.9, 0.002), (9.0, 0.002)], (0, 0, 0), "metal_frame", 64)
    # High ceiling with a pyramid skylight.
    sk = 5.0
    # Ceiling round the skylight well.
    ceiling(s, x0, x1, y0, -sk, HC, rng, dead=0.35)
    ceiling(s, x0, x1, sk, y1, HC, rng, dead=0.35)
    ceiling(s, x0, -sk, -sk, sk, HC, rng, dead=0.35)
    ceiling(s, sk, x1, -sk, sk, HC, rng, dead=0.35)
    b.box((2 * sk + 0.6, 0.3, 1.2), (0, -sk, HC + 0.6), "wall_paint")
    b.box((2 * sk + 0.6, 0.3, 1.2), (0, sk, HC + 0.6), "wall_paint")
    b.box((0.3, 2 * sk, 1.2), (-sk, 0, HC + 0.6), "wall_paint")
    b.box((0.3, 2 * sk, 1.2), (sk, 0, HC + 0.6), "wall_paint")
    apex = (0, 0, HC + 1.2 + 3.0)
    corners = [(-sk, -sk, HC + 1.2), (sk, -sk, HC + 1.2), (sk, sk, HC + 1.2), (-sk, sk, HC + 1.2)]
    for k in range(4):
        b.quad([corners[k], corners[(k + 1) % 4], apex], "glass")
        b.tube([corners[k], apex], 0.06, "metal_frame", 6)
        for t in (0.33, 0.66):
            pa = Vector(corners[k]).lerp(Vector(apex), t)
            pb = Vector(corners[(k + 1) % 4]).lerp(Vector(apex), t)
            b.tube([pa, pb], 0.035, "metal_frame", 6)
    # Hanging pendant lights round the well (some dead).
    for k in range(8):
        a = 2 * math.pi * k / 8 + 0.2
        p = Vector((math.cos(a) * 7.5, math.sin(a) * 7.5, HC))
        b.tube([p, p + Vector((0, 0, -2.5))], 0.008, "dark", 4)
        b.lathe([(0.05, -2.5), (0.35, -2.85), (0.36, -2.9)], tuple(p), "metal_frame", 16)
        b.cyl(0.3, 0.3, 0.02, tuple(p + Vector((0, 0, -2.88))), "light_dead" if k in (2, 5) else "light_panel", 16)
    # Walls with shopfronts north and south; openings to the concourse east/west.
    for side in (1, -1):
        yw = side * 12
        # big anchor store entrance (shuttered) in the middle, small shops each side
        for xa_, xb_, kind in ((-12, -4, "shutter"), (-4, 4, "shutter"), (4, 12, "half")):
            shop_y = yw - side * HALF_W
            # Shift a shopfront so its front sits on the court wall.
            sub = Section("tmp", 0)
            shopfront(sub, xa_, xb_, side, kind, rng, "clothes")
            b.place(sub.b, Matrix.Translation((0, side * (12 - HALF_W), 0)))
            for size, loc, rz in sub.cols:
                s.col(size, (loc[0], loc[1] + side * (12 - HALF_W), loc[2]), rz)
            for name, loc, rz in sub.spots:
                s.spot(name.replace("tmp", "court"), (loc[0], loc[1] + side * (12 - HALF_W), loc[2]), rz)
        b.box((24, 0.3, HC - H), (0, yw, H + (HC - H) / 2), "wall_paint")
    for xw in (-12, 12):
        for sy in (1, -1):
            b.box((0.3, 12 - HALF_W, HC), (xw, sy * (HALF_W + (12 - HALF_W) / 2), HC / 2), "wall_paint")
            s.col((0.3, 12 - HALF_W, HC), (xw, sy * (HALF_W + (12 - HALF_W) / 2), HC / 2))
        b.box((0.3, 2 * HALF_W, HC - H), (xw, 0, H + (HC - H) / 2), "wall_paint")
    # The fountain, palms, benches.
    s.prop("fountain", (0, 0, 0), 0.0)
    for k in range(8):
        a = 2 * math.pi * k / 8
        s.col((2.4, 0.6, 0.9), (math.cos(a) * 2.75, math.sin(a) * 2.75, 0.45), a + math.pi / 2)
    for k in range(4):
        a = math.pi / 4 + k * math.pi / 2
        s.prop("planter_palm", (math.cos(a) * 7.2, math.sin(a) * 7.2, 0), a, col=(1.3, 1.3, 0.6))
        for o in (-1, 1):
            ab = a + o * 0.42
            s.prop("bench", (math.cos(ab) * 6.6, math.sin(ab) * 6.6, 0), ab + math.pi / 2, col=(1.8, 0.5, 0.7))
    s.prop("trash_bin", (9.5, 4.5, 0), 0, col=(0.6, 0.6, 1.0))
    s.prop("directory", (-9.0, -4.2, 0), 0.4, col=(0.9, 0.3, 2.1))
    # A dead escalator up to a dark mezzanine that isn't there any more.
    s.prop("escalator", (8.0, -10.2, 0), -math.pi / 2)
    s.col((7.5, 1.6, 4.5), (11.2, -10.2, 2.0), 0.0)
    b.box((4.0, 4.0, 0.4), (14.5, -10.2, 4.3), "concrete")
    s.spot("spot_fountain", (0, 0, 0))
    for k in range(4):
        a = k * math.pi / 2
        s.spot(f"spot_patrol_court_{k}", (math.cos(a) * 8.5, math.sin(a) * 8.5, 0))
    return s


def food_court():
    s = Section("food_court", 20.0)
    rng = random.Random(51)
    b = s.b
    concourse_shell(s, -10, 10, rng, skylight=False)
    # Counters along both side walls (the court is a through route now).
    for side in (1, -1):
        for x in (2.5, 7.5):
            s.prop("counter", (x, side * (HALF_W - 0.9), 0), 0 if side > 0 else math.pi, col=(2.4, 0.7, 1.05))
            b.box((3.6, 0.1, 1.0), (x, side * (HALF_W + 0.0), 3.0), rng.choice(["sign_red", "sign_teal", "sign_cream"]), bevel=0.03)
            for r in range(3):
                b.box((2.6, 0.02, 0.08), (x - 0.2, side * (HALF_W - 0.06), 3.3 - r * 0.25), "sign_cream")
            z = 1.1
            while z < 2.4:
                b.box((3.4, 0.04, 0.085), (x, side * (HALF_W - 0.2), z + 0.045), "shutter")
                z += 0.1
    for k in range(6):
        x = -7 + (k % 3) * 6.5
        y = -2.4 if k < 3 else 2.4
        s.prop("table_set", (x, y, 0), rng.uniform(0, 6.28), col=(1.6, 1.6, 0.8))
    s.prop("trash_bin", (4.5, -5.3, 0), 0, col=(0.6, 0.6, 1.0))
    s.prop("trash_bin", (4.5, 5.3, 0), 0, col=(0.6, 0.6, 1.0))
    s.prop("wet_floor_sign", (2.0, 0.3, 0), 2.0)
    for side in (1, -1):
        shopfront(s, -10, 0, side, "shutter", rng)
        b.box((10, 0.3, H), (5, side * (HALF_W + 0.15), H / 2), "tile_white")
        s.col((10, 0.3, H), (5, side * (HALF_W + 0.15), H / 2))
    s.spot("spot_patrol_food", (0, 0, 0))
    return s


def entrance():
    s = Section("entrance", 20.0)
    rng = random.Random(67)
    b = s.b
    concourse_shell(s, -10, 10, rng)
    # Glass entrance vestibule at the west end: outside is only darkness.
    xw = -10
    b.box((0.3, 2 * HALF_W, H), (xw - 0.15, 0, H / 2), "dark")
    s.col((0.3, 2 * HALF_W, H), (xw - 0.15, 0, H / 2))
    for y in np.linspace(-HALF_W, HALF_W, 9):
        b.box((0.12, 0.1, 3.4), (xw + 0.8, y, 1.7), "metal_frame")
    b.box((0.14, 2 * HALF_W, 0.2), (xw + 0.8, 0, 3.4), "metal_frame")
    b.quad([(xw + 0.8, -HALF_W, 0.1), (xw + 0.8, HALF_W, 0.1), (xw + 0.8, HALF_W, 3.3), (xw + 0.8, -HALF_W, 3.3)], "glass")
    b.box((0.3, 2 * HALF_W, H - 3.5), (xw + 0.8, 0, 3.5 + (H - 3.5) / 2), "wall_paint")
    s.col((0.3, 2 * HALF_W, 3.5), (xw + 0.8, 0, 1.75))
    for k in range(4):
        b.box((0.03, 0.5, 0.04), (xw + 0.74, -3 + k * 2, 1.05), "metal_bright")       # push bars
    for side in (1, -1):
        shopfront(s, -10, 0, side, "shutter", rng)
        shopfront(s, 0, 10, side, "half" if side > 0 else "open", rng, "shelves")
    s.prop("bench", (-4.0, 3.2, 0), math.pi, col=(1.8, 0.5, 0.7))
    s.prop("trash_bin", (-6.5, -3.0, 0), 0, col=(0.6, 0.6, 1.0))
    s.prop("directory", (-6.0, 0.5, 0), math.pi / 2, col=(0.9, 0.3, 2.1))
    # The way out (the odd door) set into the entrance glazing, facing in.
    s.spot("spot_exit", (-9.05, 4.0, 0), 0.0)
    s.spot("spot_arrival", (-6.0, -2.0, 0), -math.pi / 2)
    return s


def concourse_c():
    """An arcade, a stuck shutter, a leak from the roof."""
    s = Section("concourse_c", 20.0)
    rng = random.Random(83)
    b = s.b
    concourse_shell(s, -10, 10, rng)
    shopfront(s, -10, 0, 1, "open", rng, "arcade")
    shopfront(s, 0, 10, 1, "half", rng, "clothes")
    shopfront(s, -10, 0, -1, "shutter", rng)
    shopfront(s, 0, 10, -1, "open", rng, "shelves")
    s.prop("planter_shrub", (-4.5, 0, 0), 0.4, col=(1.3, 1.3, 0.6))
    s.prop("bench", (-4.5, -2.0, 0), 0, col=(1.8, 0.5, 0.7))
    s.prop("trash_bin", (1.5, -2.6, 0), 0, col=(0.6, 0.6, 1.0))
    # A leak: a stagnant puddle under a missing ceiling tile, the tile on the floor.
    b.quad([(3.0, 2.0, 0.006), (6.2, 2.4, 0.006), (6.0, 4.6, 0.006), (3.4, 4.3, 0.006)], "water")
    b.box((1.2, 0.6, 0.03), (5.1, 4.9, 0.05), "ceiling_tile", (0.0, 0.06, 0.4))
    b.box((1.15, 0.55, 0.02), (4.4, 3.4, H + 0.02), "dark")
    s.prop("wet_floor_sign", (2.6, 2.9, 0), 0.9)
    s.prop("bench", (6.5, -2.0, 0), 0, col=(1.8, 0.5, 0.7))
    s.spot("spot_patrol_a", (-8, 0, 0))
    s.spot("spot_patrol_b", (8, 0, 0))
    return s


def concourse_d():
    """A cafe, a shoe shop, payphones, a cart tipped on its side."""
    s = Section("concourse_d", 20.0)
    rng = random.Random(97)
    concourse_shell(s, -10, 10, rng)
    shopfront(s, -10, 0, 1, "open", rng, "cafe")
    shopfront(s, 0, 10, 1, "shutter", rng)
    shopfront(s, -10, 0, -1, "open", rng, "clothes")
    shopfront(s, 0, 10, -1, "half", rng, "shelves")
    s.prop("planter_palm", (-3.0, 0, 0), 2.1, col=(1.3, 1.3, 0.6))
    s.prop("bench", (-3.0, 2.0, 0), math.pi, col=(1.8, 0.5, 0.7))
    s.prop("payphone", (9.2, 5.7, 0), 0, col=(0.4, 0.3, 1.8))
    s.prop("payphone", (8.4, 5.7, 0), 0, col=(0.4, 0.3, 1.8))
    s.prop("directory", (4.0, 0.0, 0), math.pi / 2, col=(0.9, 0.3, 2.1))
    s.b.place(P.PROPS["shopping_cart"](), Matrix.LocRotScale(Vector((1.5, -3.2, 0.42)), _eul((math.pi / 2, 0, 0.7)), None))
    s.prop("trash_bin", (-7.0, -2.4, 0), 0, col=(0.6, 0.6, 1.0))
    s.spot("spot_patrol_a", (-8, 0, 0))
    s.spot("spot_patrol_b", (8, 0, 0))
    return s


def department_store():
    """The anchor store at the far end: a big low sales floor, cosmetics
    counters by the entrance, racks, fitting rooms, display platforms of
    mannequins, staff doors at the back."""
    L = 32.0
    s = Section("department_store", L)
    rng = random.Random(131)
    b = s.b
    x0, x1 = -L / 2, L / 2
    W = HALF_W + SHOP_D            # 13
    HC = 4.5
    # Floor: terrazzo main aisle, carpet either side.
    b.quad([(x0, -2.5, 0), (x1, -2.5, 0), (x1, 2.5, 0), (x0, 2.5, 0)], "terrazzo")
    for a, c in ((-W, -2.5), (2.5, W)):
        b.quad([(x0, a, 0.002), (x1, a, 0.002), (x1, c, 0.002), (x0, c, 0.002)], "carpet")
    s.col((L, 2 * W + 1, 0.4), (0, 0, -0.2))
    # Front: walls either side of the 12 m opening, a big header with the name.
    for sy in (1, -1):
        b.box((0.3, W - HALF_W, H), (x0, sy * (HALF_W + (W - HALF_W) / 2), H / 2), "wall_paint")
        s.col((0.3, W - HALF_W, H), (x0, sy * (HALF_W + (W - HALF_W) / 2), H / 2))
    b.box((0.4, 2 * HALF_W, H - HC + 0.3), (x0, 0, HC - 0.15 + (H - HC + 0.3) / 2), "wall_paint")
    b.box((0.2, 9.0, 1.1), (x0 - 0.3, 0, 5.2), "sign_red", bevel=0.04)
    for k in range(8):
        if k == 5:
            continue          # a letter fell off
        b.box((0.08, 0.7, 0.8), (x0 - 0.42, -3.6 + k * 1.03, 5.2), "sign_cream", bevel=0.02)
    # Side and back walls.
    for sy in (1, -1):
        oquad(b, [(x0, sy * W, 0), (x1, sy * W, 0), (x1, sy * W, HC), (x0, sy * W, HC)], "wall_paint", (0, 0, 2))
        s.col((L, 0.3, HC), (0, sy * (W + 0.15), HC / 2))
    oquad(b, [(x1, -W, 0), (x1, W, 0), (x1, W, HC), (x1, -W, HC)], "wall_paint", (0, 0, 2))
    s.col((0.3, 2 * W, HC), (x1 + 0.15, 0, HC / 2))
    for y in (-6.0, 6.0):          # staff doors
        b.box((0.1, 1.2, 2.2), (x1 - 0.05, y, 1.1), "dark")
        b.box((0.12, 1.36, 0.08), (x1 - 0.05, y, 2.24), "metal_frame")
        b.box((0.03, 0.5, 0.15), (x1 - 0.12, y, 2.45), "sign_cream")
        b.box((0.06, 0.04, 0.4), (x1 - 0.12, y - 0.45, 1.05), "metal_bright")
    ceiling(s, x0, x1, -W, W, HC, rng, dead=0.45)
    # Columns.
    for x in (-8.0, 0.0, 8.0):
        for y in (-6.5, 6.5):
            b.box((0.6, 0.6, HC), (x, y, HC / 2), "wall_paint", bevel=0.02)
            s.col((0.6, 0.6, HC), (x, y, HC / 2))
    # Hanging department signs.
    for x, y in ((-11.0, -7.5), (-11.0, 7.5), (4.0, -9.0), (4.0, 9.0)):
        b.box((1.6, 0.06, 0.45), (x, y, 3.3), rng.choice(["sign_cream", "sign_teal"]), bevel=0.01)
        for dx in (-0.6, 0.6):
            b.tube([(x + dx, y, 3.52), (x + dx, y, HC)], 0.006, "dark", 4)
    # Cosmetics: glass counters in islands near the entrance.
    for cx, cy in ((-12.0, -5.0), (-12.0, 5.0)):
        for dx, dy, rz in ((-1.0, -1.2, 0.0), (1.0, -1.2, 0.0), (-1.0, 1.2, math.pi), (1.0, 1.2, math.pi)):
            s.prop("glass_case", (cx + dx, cy + dy, 0), rz, col=(1.8, 0.6, 1.05))
    # Clothes: round racks and display tables in rows, a few rail racks.
    for x in (-5.0, -1.5, 2.0, 5.5):
        for y in (-10.5, -8.0, 8.0, 10.5):
            if rng.random() < 0.8:
                s.prop("round_rack", (x + rng.uniform(-0.3, 0.3), y + rng.uniform(-0.3, 0.3), 0), rng.uniform(0, 6.28), col=(1.1, 1.1, 1.4))
    for x in (-4.0, 3.5):
        for y in (-4.4, 4.4):
            s.prop("display_table", (x, y, 0), rng.uniform(-0.2, 0.2), col=(1.6, 0.9, 0.85))
    for k in range(3):
        s.prop("clothes_rack", (10.0 + k * 1.8, -10.6, 0), math.pi / 2, col=(1.3, 0.5, 1.5))
    s.prop("fitting_rooms", (12.0, 12.3, 0), 0.0, col=(3.1, 1.35, 2.2))
    s.prop("shopping_cart", (-6.5, 1.6, 0), 0.9)
    s.prop("empty_stand", (6.0, -3.2, 0), 1.0)
    s.prop("wet_floor_sign", (-2.0, -1.2, 0), 2.6)
    # Display platforms: mannequins posed on low round stages.
    for k, (px, py) in enumerate(((-8.0, 0.0), (8.0, 0.0), (13.5, 0.0))):
        b.cyl(1.3, 1.3, 0.25, (px, py, 0.125), "wood", 24)
        s.col((2.0, 2.0, 0.25), (px, py, 0.125))
        for j, a in enumerate((0.6, 2.7, 4.6)):
            s.spot(f"spot_mannequin_dept_{k}_{j}", (px + math.cos(a) * 0.75, py + math.sin(a) * 0.75, 0.25), rng.uniform(-math.pi, math.pi))
    for k, (px, py) in enumerate(((-12.0, 0.0), (-4.0, -9.5), (4.0, 9.5), (12.0, -6.0), (12.0, 6.0))):
        s.spot(f"spot_patrol_dept_{k}", (px, py, 0))
    return s


SECTIONS = {"concourse_a": concourse_a, "concourse_b": concourse_b, "concourse_c": concourse_c,
            "concourse_d": concourse_d, "fountain_court": fountain_court, "food_court": food_court,
            "entrance": entrance, "department_store": department_store}


# ------------------------------------------------------------ bake/export ---
def build(sec):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    s = SECTIONS[sec]()
    vis = s.b.to_object(sec)
    for p in vis.data.polygons:
        p.use_smooth = False
    # Lightmap UVs.
    bpy.context.view_layer.objects.active = vis
    vis.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.mesh.remove_doubles(threshold=0.0005)
    bpy.ops.uv.smart_project(angle_limit=math.radians(60), island_margin=0.002, area_weight=1.0)
    bpy.ops.uv.select_all(action="SELECT")
    bpy.ops.uv.pack_islands(margin=0.003, rotate=True, shape_method="CONCAVE", scale=True)
    bpy.ops.object.mode_set(mode="OBJECT")
    print(sec, "tris", sum(len(p.vertices) - 2 for p in vis.data.polygons))
    # Sky: dusk light through the skylights.
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Color"].default_value = (0.32, 0.36, 0.46, 1)
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 1.4
    scene.world = w
    img = bpy.data.images.new(sec + "_lm", LM, LM, alpha=False, float_buffer=True)
    for m in vis.data.materials:
        nt = m.node_tree
        node = nt.nodes.new("ShaderNodeTexImage")
        node.image = img
        nt.nodes.active = node
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = 24 if FAST else 96
    scene.render.bake.margin = 4
    scene.render.bake.use_selected_to_active = False
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"DIRECT", "INDIRECT"})
    # Clean up the noise a little (blur inside the filled texels only).
    px = np.array(img.pixels[:]).reshape(LM, LM, 4)[:, :, :3]
    mask = (px.sum(axis=2) > 1e-6).astype(np.float32)
    k = np.array([1, 4, 6, 4, 1], np.float32)
    k /= k.sum()

    def blur(a):
        for ax in (0, 1):
            pad = [(0, 0)] * a.ndim
            pad[ax] = (2, 2)
            ap = np.pad(a, pad, mode="edge")
            a = sum(k[i] * np.take(ap, range(i, i + a.shape[ax]), axis=ax) for i in range(5))
        return a
    num = blur(px * mask[:, :, None])
    den = blur(mask)[:, :, None]
    px = np.where(den > 1e-4, num / np.maximum(den, 1e-4), px)
    enc = np.sqrt(np.clip(px / LM_SCALE, 0, 1))
    out = bpy.data.images.new(sec + "_lightmap", LM, LM, alpha=False)
    rgba = np.concatenate([enc, np.ones((LM, LM, 1))], axis=2)
    out.pixels[:] = rgba.ravel()
    os.makedirs(os.path.join(OUT, "lightmaps"), exist_ok=True)
    out.filepath_raw = os.path.join(OUT, "lightmaps", sec + ".png")
    out.file_format = "PNG"
    out.save()
    # Remove bake nodes (keep plain materials for export).
    for m in vis.data.materials:
        for nd in [n for n in m.node_tree.nodes if n.type == "TEX_IMAGE"]:
            m.node_tree.nodes.remove(nd)
    # Collision boxes and spots.
    objs = [vis]
    for i, (size, loc, rz) in enumerate(s.cols):
        cb = Builder()
        cb.box(size, (0, 0, 0), "concrete")
        co = cb.to_object(f"col{i}-colonly")
        co.location = loc
        co.rotation_euler = (0, 0, rz)
        objs.append(co)
    for name, loc, rz in s.spots:
        e = bpy.data.objects.new(name, None)
        scene.collection.objects.link(e)
        e.location = loc
        e.rotation_euler = (0, 0, rz)
        objs.append(e)
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=os.path.join(OUT, sec + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT", export_image_format="NONE")
    if PREVIEW:
        preview(sec, s)
    print("exported", sec, "cols", len(s.cols), "spots", len(s.spots))


def preview(sec, s):
    """A quick render of the section with its baked lighting look."""
    scene = bpy.context.scene
    cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam"))
    scene.collection.objects.link(cam)
    scene.camera = cam
    cam.data.lens = 18
    x0 = -s.length / 2 + 1.0
    cam.location = (x0, -3.5, 1.65)
    cam.rotation_euler = (Vector((s.length / 2, 1.0, 1.9)) - cam.location).to_track_quat("-Z", "Y").to_euler()
    for o in bpy.data.objects:
        if o.name.endswith("-colonly"):
            o.hide_render = True
    scene.cycles.samples = 24 if FAST else 64
    scene.cycles.use_denoising = True
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.view_settings.view_transform = "AgX"
    scene.render.filepath = os.path.join(PREVIEW, sec + ".png")
    bpy.ops.render.render(write_still=True)


if __name__ == "__main__":
    os.makedirs(OUT, exist_ok=True)
    if PREVIEW:
        os.makedirs(PREVIEW, exist_ok=True)
    for name in SECTIONS:
        if ONLY and name not in ONLY:
            continue
        build(name)
