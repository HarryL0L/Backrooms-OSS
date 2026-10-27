"""The Crawlspace (side level "crawlspace"): a low-pressure supply trunk of
galvanised rectangular duct above an office floor's suspended ceiling, built
at the sizes in assets/levels/crawlspace/SPEC.md (SMACNA-style construction:
36 x 30 in clear inside, 22 ga, 5 ft sections with transverse joints and
cross-broken panels, mitred elbows with 2 in turning vanes on 2-1/8 in
centres, 24 x 12 in bar registers in the floor looking down through the
ceiling into lit offices, an opposed-blade damper and a tube-axial fan).

Two kits: "crawl_duct" (the network) and "crawl_rooms" (the offices below).
The rooms are baked first; the duct's bake then sees their light coming up
through the registers. Light groups: 0 the faulty office (flickers), 1 the
plant room behind the fan (the blades chop it), 2 the office whose
occupancy sensor trips, 3 the exit office.

Run:  /tmp/claude-0/bpyenv/bin/python tools/blender/levels/crawlspace.py [out dir] [--fast]
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import level_kit as K  # noqa: E402

OUT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "assets/levels/crawlspace"
IN = 0.0254
FT = 0.3048

# ---------------------------------------------------------------- sizes ---
W = 36 * IN                 # clear inside width (0.914 m)
H = 30 * IN                 # clear inside height (0.762 m)
SECTION = 5 * FT            # joint spacing (1.524 m)
BREAK = 0.006               # cross-break crown (outward)
CEIL_TOP = -0.15            # top of the ceiling tiles (the duct hangs 150 mm above)
TILE = 0.625 * IN           # 5/8 in tile
CEIL = CEIL_TOP - TILE      # the rooms' ceiling face
ROOM_H = 9 * FT             # floor to ceiling
FLOOR = CEIL - ROOM_H       # the rooms' floor
REG = (24 * IN, 12 * IN)    # floor register (across, along)
EXIT = (24 * IN, 24 * IN)   # the exit's return grille
BAR = 0.75 * IN             # bar spacing
VANE_R = 2 * IN             # turning vane radius
VANE_P = 2.125 * IN         # vane spacing along the rail
TROFFER = (2 * FT, 4 * FT)
TROFFER_W = 13.7            # radiant watts for ~4100 lm (see SPEC.md)

# -------------------------------------------------------------- materials ---
K.reset()
K.material("duct_galv", (0.56, 0.58, 0.60), rough=0.45, metal=0.6)
K.material("duct_top", (0.55, 0.57, 0.59), rough=0.45, metal=0.6)
K.material("duct_floor", (0.52, 0.51, 0.50), rough=0.7, metal=0.4)
K.material("mastic", (0.55, 0.57, 0.58), rough=0.95)
K.material("liner", (0.05, 0.05, 0.05), rough=0.95)
K.material("liner_pin", (0.5, 0.5, 0.5), rough=0.4, metal=0.7)
K.material("vane", (0.58, 0.60, 0.62), rough=0.4, metal=0.6)
K.material("grille", (0.86, 0.86, 0.84), rough=0.5)
K.material("gasket", (0.06, 0.06, 0.06), rough=0.8)
K.material("fan_paint", (0.30, 0.34, 0.33), rough=0.6)
K.material("carpet", (0.16, 0.19, 0.24), rough=0.95)
K.material("ceiling_tile", (0.82, 0.82, 0.80), rough=0.95)
K.material("wall_paint", (0.70, 0.69, 0.66), rough=0.9)
K.material("base", (0.12, 0.12, 0.12), rough=0.8)
K.material("door", (0.62, 0.58, 0.52), rough=0.6)
K.material("door_frame", (0.30, 0.30, 0.31), rough=0.5, metal=0.3)
K.material("troffer_frame", (0.85, 0.85, 0.84), rough=0.5)
K.material("plate", (0.90, 0.89, 0.86), rough=0.6)
K.material("screw", (0.55, 0.55, 0.53), rough=0.35, metal=0.8)
K.material("dust", (0.46, 0.44, 0.41), rough=1.0)
K.material("tape", (0.7, 0.71, 0.72), rough=0.3, metal=0.7)
K.material("cable_tie", (0.08, 0.08, 0.08), rough=0.6)
K.material("laminate", (0.60, 0.57, 0.52), rough=0.5)
K.material("desk_metal", (0.22, 0.22, 0.23), rough=0.5, metal=0.4)
K.material("chair_fabric", (0.07, 0.07, 0.08), rough=0.95)
K.material("cabinet", (0.66, 0.65, 0.60), rough=0.5, metal=0.2)
K.material("monitor", (0.02, 0.02, 0.02), rough=0.3)
K.material("whiteboard", (0.9, 0.9, 0.88), rough=0.2)
K.material("entry_glow", (0.78, 0.68, 0.42), rough=0.9)
LAMPS = {-1: "lamp", 0: "lamp_g0", 1: "lamp_g1", 2: "lamp_g2", 3: "lamp_g3"}
for g, n in LAMPS.items():
    K.material(n, (1.0, 0.98, 0.94), emit=2.0, group=g)
CCT_4000K = (1.0, 0.92, 0.82)          # 4000 K white in linear RGB (approx.)

# ----------------------------------------------------------------- layout ---
# Junctions (Blender XY, m): x east, y north. Godot: (x, z, -y).
NODES = {
    "n0": (0.0, 0.0), "n1": (0.0, 12.0), "n2": (0.0, 24.0), "n3": (-10.0, 24.0), "fan_end": (-10.0, 15.0),
    "n5": (-10.0, 36.0), "w_end": (-17.0, 36.0), "n6": (4.0, 36.0), "s_end": (4.0, 29.0), "n7": (4.0, 46.0),
    "n8": (9.0, 12.0), "n8_end": (9.0, 18.0),
}
# Ducts between junctions: (a, b, features). Features: ("reg", d) a floor
# register d m from a's centre; ("exit", d); ("door", d, side +1 left/-1 right);
# "liner".
DUCTS = [
    ("n0", "n1", [("reg", 5.5)]),
    ("n1", "n2", [("door", 5.0, 1)]),
    ("n2", "n3", [("reg", 5.0)]),
    ("n3", "fan_end", [("reg", 8.0)]),
    ("n3", "n5", [("reg", 7.0), ("door", 3.4, -1)]),
    ("n5", "w_end", [("door", 4.5, 1)]),
    ("n5", "n6", ["liner", ("reg", 8.0)]),
    ("n6", "s_end", []),
    ("n6", "n7", [("exit", 8.0)]),
    ("n1", "n8", [("reg", 5.0)]),
    ("n8", "n8_end", [("reg", 3.6)]),
]
# Elbows' turning vanes: "torn" (the throat half pulled out: you can get
# round) or "full" (you can't).
VANES = {"n2": "torn", "n8": "full", "n5": None}
DAMPER_Y = 20.6             # the opposed-blade damper in the fan spur (x = -10)
FAN_Y = 18.2                # the fan behind it
# Offices below (x0, y0, x1, y1, light group or None for dark, door wall).
ROOMS = [
    ((-2.6, 3.0, 2.6, 8.4), -1, "w"),      # under the first register
    ((3.2, 9.4, 9.8, 16.4), None, "e"),    # dark: the lights are off
    ((-7.6, 21.2, -2.4, 27.0), -1, "s"),
    ((-12.8, 13.0, -7.2, 17.4), 1, "w"),   # plant room behind the fan
    ((-13.0, 28.4, -7.0, 33.6), 0, "w"),   # the faulty one
    ((-4.6, 33.4, 0.6, 38.6), 2, "s"),     # occupancy sensor
    ((1.4, 41.0, 6.8, 47.2), 3, "e"),      # the way out
]


def side_angle(a, b):
    (ax, ay), (bx, by) = NODES[a], NODES[b]
    return math.atan2(by - ay, bx - ax)


def openings():
    """node -> set of open side angles (degrees: 0 E, 90 N, 180 W, 270 S)."""
    op = {n: set() for n in NODES}
    for a, b, _f in DUCTS:
        ang = round(math.degrees(side_angle(a, b))) % 360
        op[a].add(ang)
        op[b].add((ang + 180) % 360)
    return op


OPEN = openings()


class Local:
    """Geometry in a duct's own frame (x along, y left, z up), placed into the
    kit's builder with a matrix."""

    def __init__(self, kit, origin, ang):
        self.kit = kit
        self.b = K.Builder()
        self.o = origin
        self.ang = ang
        self.c, self.s = math.cos(ang), math.sin(ang)

    def w(self, p):
        x, y, z = p
        return (self.o[0] + x * self.c - y * self.s, self.o[1] + x * self.s + y * self.c, z)

    def done(self):
        from mathutils import Matrix
        m = Matrix.Translation((self.o[0], self.o[1], 0.0)) @ Matrix.Rotation(self.ang, 4, "Z")
        self.kit.b.place(self.b, m)

    def col(self, size, loc):
        self.kit.col(size, self.w(loc), self.ang)


def tri(b, pts, m, toward):
    b.oquad(pts, m, toward)


def xbreak(b, c0, c1, c2, c3, m, out, toward):
    """A cross-broken panel: four triangles to a centre pushed `out` (the X
    creases of SMACNA cross-breaking)."""
    cx = sum(p[0] for p in (c0, c1, c2, c3)) / 4 + out[0]
    cy = sum(p[1] for p in (c0, c1, c2, c3)) / 4 + out[1]
    cz = sum(p[2] for p in (c0, c1, c2, c3)) / 4 + out[2]
    ctr = (cx, cy, cz)
    for a, c in ((c0, c1), (c1, c2), (c2, c3), (c3, c0)):
        tri(b, [a, c, ctr], m, toward)


def flat(b, c0, c1, c2, c3, m, toward):
    b.oquad([c0, c1, c2, c3], m, toward)


def grille_bars(b, cx, cy, z, across, along, angle_deg, m, rot_z=0.0):
    """A bar grille's face (frame + fixed bars at angle) centred (cx, cy),
    its face at z; bars run `across`, spaced BAR along `along` (local frame
    rotated rot_z)."""
    c, s = math.cos(rot_z), math.sin(rot_z)

    def w(x, y):
        return (cx + x * c - y * s, cy + x * s + y * c)
    fr = 1.25 * IN
    dep = 1.0 * IN
    for sx in (-1, 1):       # frame: flanges on the ceiling face, borders round the core
        p = w(0, sx * (along / 2 + fr / 2 - 0.004))
        b.box((across + 2 * fr, fr, 0.004), (p[0], p[1], z - 0.002), m, rot=(0, 0, rot_z))
        p = w(sx * (across / 2 + fr / 2 - 0.004), 0)
        b.box((fr, along + 2 * fr, 0.004), (p[0], p[1], z - 0.002), m, rot=(0, 0, rot_z))
        p = w(0, sx * along / 2)
        b.box((across, 0.003, dep), (p[0], p[1], z + dep / 2), m, rot=(0, 0, rot_z))
        p = w(sx * across / 2, 0)
        b.box((0.003, along, dep), (p[0], p[1], z + dep / 2), m, rot=(0, 0, rot_z))
    n = int(along / BAR)
    for i in range(n):
        y = -along / 2 + (i + 0.5) * along / n
        p = w(0, y)
        b.box((across, 0.003, dep), (p[0], p[1], z + dep / 2), m, rot=(math.radians(angle_deg), 0, rot_z))


def eggcrate(b, cx, cy, z, across, along, m, rot_z=0.0):
    """A lay-in eggcrate return grille: 1/2 x 1/2 x 1/2 in aluminium grid core
    in a 1-1/4 in frame (face at z), centred (cx, cy), across x along."""
    c, s = math.cos(rot_z), math.sin(rot_z)

    def w(x, y):
        return (cx + x * c - y * s, cy + x * s + y * c)
    fr = 1.25 * IN
    cell = 0.5 * IN
    dep = 0.5 * IN
    for sx in (-1, 1):
        p = w(0, sx * (along / 2 + fr / 2 - 0.004))
        b.box((across + 2 * fr, fr, 0.004), (p[0], p[1], z - 0.002), m, rot=(0, 0, rot_z))
        p = w(sx * (across / 2 + fr / 2 - 0.004), 0)
        b.box((fr, along + 2 * fr, 0.004), (p[0], p[1], z - 0.002), m, rot=(0, 0, rot_z))
    # (each strip two quads 1.5 mm apart, its two faces)
    def strip(p0, p1, side):
        for k in (-1, 1):
            q0 = (p0[0] + side[0] * k * 0.00075, p0[1] + side[1] * k * 0.00075)
            q1 = (p1[0] + side[0] * k * 0.00075, p1[1] + side[1] * k * 0.00075)
            pts = [(q0[0], q0[1], z), (q1[0], q1[1], z), (q1[0], q1[1], z + dep), (q0[0], q0[1], z + dep)]
            b.oquad(pts, m, (q0[0] + side[0] * k, q0[1] + side[1] * k, z))
    n_a, n_l = int(across / cell), int(along / cell)
    for i in range(n_a + 1):
        u = -across / 2 + i * across / n_a
        strip(w(u, -along / 2), w(u, along / 2), (c, s))
    for j in range(n_l + 1):
        v = -along / 2 + j * along / n_l
        strip(w(-across / 2, v), w(across / 2, v), (-s, c))


def register_neck(L, x, size, exit_=False):
    """The opening in the duct floor at local x: a neck down to the ceiling
    and the grille in the tiles (local frame). Returns the hole (x0, x1, y0, y1)."""
    across, along = size
    x0, x1 = x - along / 2, x + along / 2
    y0, y1 = -across / 2, across / 2
    b = L.b
    ctr = (x, 0.0, -0.05)
    flat(b, (x0, y0, 0), (x1, y0, 0), (x1, y0, CEIL), (x0, y0, CEIL), "duct_galv", ctr)
    flat(b, (x0, y1, 0), (x1, y1, 0), (x1, y1, CEIL), (x0, y1, CEIL), "duct_galv", ctr)
    flat(b, (x0, y0, 0), (x0, y1, 0), (x0, y1, CEIL), (x0, y0, CEIL), "duct_galv", ctr)
    flat(b, (x1, y0, 0), (x1, y1, 0), (x1, y1, CEIL), (x1, y0, CEIL), "duct_galv", ctr)
    # The neck's collar: tabs bent over onto the duct floor, screwed down.
    for sx in (-1, 1):
        for t in (-0.2, 0.0, 0.2):
            b.box((0.025, 0.03, 0.001), (x + sx * (along / 2 + 0.0125), t, 0.0005), "duct_galv")
            b.cyl(0.0045, 0.0045, 0.003, (x + sx * (along / 2 + 0.013), t, 0.0015), "screw", segs=6)
    if not exit_:            # (the exit's grille is a moving part, made in Godot)
        eggcrate(b, x, 0.0, CEIL - 0.004, across, along, "grille", rot_z=math.pi / 2)
    return (x0, x1, y0, y1)


def duct(kit, a, b_, feats):
    ang = side_angle(a, b_)
    ax, ay = NODES[a]
    bx, by = NODES[b_]
    length = math.hypot(bx - ax, by - ay)
    L = Local(kit, (ax, ay), ang)
    b = L.b
    x_start, x_end = W / 2, length - W / 2
    liner = "liner" in feats
    holes = []
    for f in feats:
        if isinstance(f, tuple) and f[0] in ("reg", "exit"):
            holes.append(register_neck(L, f[1], REG if f[0] == "reg" else EXIT, f[0] == "exit"))
            kit.spot("spot_%s_%s_%s" % (f[0], a, b_), L.w((f[1], 0.0, 0.0)), ang)
        if isinstance(f, tuple) and f[0] == "door":
            access_door(L, f[1], f[2])
    # Joints every SECTION from the start; panels between.
    xs = [x_start]
    while xs[-1] + SECTION < x_end - 0.3:
        xs.append(xs[-1] + SECTION)
    xs.append(x_end)
    hy, ctr_z = W / 2, H / 2
    import random
    rng = random.Random(hash((a, b_)) & 0xFFFF)
    for x0, x1 in zip(xs, xs[1:]):
        toward = ((x0 + x1) / 2, 0.0, ctr_z)
        # Floor panels sag under years of service crawls (dents), walls and
        # roof keep their cross-break crown, give or take.
        dent = rng.uniform(0.002, 0.009) + (0.008 if rng.random() < 0.3 else 0.0)
        hole = [h for h in holes if h[0] < x1 and h[1] > x0]
        wall_m, top_m, floor_m = ("liner", "liner", "liner") if liner else ("duct_galv", "duct_top", "duct_floor")
        brk = 0.0 if liner else BREAK
        # Floor.
        if hole:
            h0, h1, hy0, hy1 = hole[0]
            h0, h1 = max(h0, x0), min(h1, x1)
            if h0 - x0 > 1e-4:
                flat(b, (x0, -hy, 0), (h0, -hy, 0), (h0, hy, 0), (x0, hy, 0), floor_m, toward)
            if x1 - h1 > 1e-4:
                flat(b, (h1, -hy, 0), (x1, -hy, 0), (x1, hy, 0), (h1, hy, 0), floor_m, toward)
            flat(b, (h0, -hy, 0), (h1, -hy, 0), (h1, hy0, 0), (h0, hy0, 0), floor_m, toward)
            flat(b, (h0, hy1, 0), (h1, hy1, 0), (h1, hy, 0), (h0, hy, 0), floor_m, toward)
        else:
            xbreak(b, (x0, -hy, 0), (x1, -hy, 0), (x1, hy, 0), (x0, hy, 0), floor_m,
                   (rng.uniform(-0.15, 0.15), rng.uniform(-0.1, 0.1), -(brk + dent if not liner else 0)), toward)
        xbreak(b, (x0, -hy, H), (x1, -hy, H), (x1, hy, H), (x0, hy, H), top_m, (0, 0, brk * rng.uniform(0.6, 1.4)), toward)
        for sy in (-1, 1):
            xbreak(b, (x0, sy * hy, 0), (x1, sy * hy, 0), (x1, sy * hy, H), (x0, sy * hy, H), wall_m,
                   (rng.uniform(-0.1, 0.1), sy * brk * rng.uniform(0.6, 1.5), rng.uniform(-0.05, 0.05)), toward)
        if not liner:
            dust_drifts(b, x0, x1, rng, hole[0] if hole else None)
            debris(b, x0, x1, rng)
    # Transverse joints: the sealed seam all round (mastic), and at the
    # corners the longitudinal (Pittsburgh) seams.
    for x in xs:
        if not liner:
            sealed_joint(b, x, hash((a, b_, round(x, 2))))
    # Hanger straps (18 ga band, 8 ft centres) are screwed to the sides near
    # the top: their screw tips come through.
    x = x_start + 0.5
    while x < x_end - 0.2:
        for sy in (-1, 1):
            for dx in (-0.02, 0.02):
                screw_tip(b, (x + dx, sy * hy, H - 0.045), (0, -sy, 0))
        x += 8 * FT
    if not liner:
        for sy in (-1, 1):
            for z in (0.0, H):
                b.box((x_end - x_start, 0.012, 0.012), ((x_start + x_end) / 2, sy * hy, z), "duct_galv",
                      rot=(math.pi / 4, 0, 0))
    else:
        # Liner fasteners (weld pins and washers) on 12 in centres.
        pitch = 12 * IN
        n = int((x_end - x_start) / pitch)
        for i in range(n):
            x = x_start + (i + 0.5) * (x_end - x_start) / n
            # (1-1/4 in square washers on the pins)
            q = 0.016
            for t in (-0.3, 0.0, 0.3):
                for f in ("floor", "roof"):
                    patch(b, f, x - q, x + q, t - q, t + q, 0.0015, "liner_pin")
            for f in ("left", "right"):
                for z in (0.19, 0.57):
                    patch(b, f, x - q, x + q, z - q, z + q, 0.0015, "liner_pin")
        for x in xs:
            for sy in (-1, 1):
                b.box((0.03, 0.004, H), (x, sy * (hy - 0.002), H / 2), "mastic")
    # Collision: floor, roof, walls.
    mid, ln = (x_start + x_end) / 2, x_end - x_start
    L.col((ln, W + 0.4, 0.2), (mid, 0, -0.1))
    L.col((ln, W + 0.4, 0.2), (mid, 0, H + 0.1))
    for sy in (-1, 1):
        L.col((ln, 0.2, H), (mid, sy * (hy + 0.1), H / 2))
    L.done()


def screw_tip(b, p, d):
    """A #10 sheet-metal screw's point through the sheet (4.8 mm, 13 mm
    proud), pointing along d."""
    ang = (0, 0, 0)
    if abs(d[1]) > 0.5:
        ang = (-d[1] * math.pi / 2, 0, 0)
    elif abs(d[0]) > 0.5:
        ang = (0, d[0] * math.pi / 2, 0)
    elif d[2] < 0:
        ang = (math.pi, 0, 0)
    from mathutils import Euler, Vector
    off = Euler(ang).to_matrix() @ Vector((0, 0, 0.0065))
    b.cyl(0.0024, 0.0004, 0.013, (p[0] + off.x, p[1] + off.y, p[2] + off.z), "screw", segs=6, rot=ang)


def dust_drifts(b, x0, x1, rng, hole):
    """Dust banks up where the floor meets the walls (the air is slowest
    there): a low wedge each side."""
    hy = W / 2
    for sy in (-1, 1):
        w0, w1 = rng.uniform(0.02, 0.06), rng.uniform(0.02, 0.06)
        h0, h1 = w0 * 0.25, w1 * 0.25
        pts = [(x0, sy * (hy - w0), 0.0006), (x1, sy * (hy - w1), 0.0006), (x1, sy * (hy - 0.0005), h1),
               (x0, sy * (hy - 0.0005), h0)]
        b.oquad(pts, "dust", ((x0 + x1) / 2, 0, H))


def debris(b, x0, x1, rng):
    """What gets left in a duct: dropped screws, a curl of foil tape, a bit of
    pipe-wrap, a cable tie."""
    for _ in range(rng.choice((0, 0, 1, 1, 2, 3))):
        x = rng.uniform(x0 + 0.1, x1 - 0.1)
        y = rng.uniform(-0.38, 0.38)
        r = rng.uniform(0, math.pi)
        k = rng.random()
        if k < 0.45:      # a screw lying on its side
            b.cyl(0.0024, 0.0024, 0.019, (x, y, 0.0026), "screw", segs=6, rot=(math.pi / 2, 0, r))
            b.cyl(0.0048, 0.0048, 0.003, (x + 0.011 * math.cos(r + math.pi / 2), y + 0.011 * math.sin(r + math.pi / 2), 0.0048),
                  "screw", segs=6, rot=(math.pi / 2, 0, r))
        elif k < 0.75:    # foil tape, curled
            b.box((rng.uniform(0.12, 0.3), 0.048, 0.0008), (x, y, 0.004), "tape", rot=(0.0, rng.uniform(-0.08, 0.08), r))
            b.box((0.05, 0.048, 0.0008), (x, y, 0.012), "tape", rot=(0.0, 0.6, r))
        elif k < 0.9:     # cable tie
            b.box((0.2, 0.0036, 0.0012), (x, y, 0.0008), "cable_tie", rot=(0, 0, r))
        else:             # a scrap of insulation
            b.box((0.09, 0.07, 0.025), (x, y, 0.012), "liner", rot=(0.1, 0.2, r), bevel=0.01)


def _onface(face, x, t, h):
    """A point on one of the duct's inner faces (local frame): x along, t
    across the face (y on floor/roof, z on the walls), h off it, inward."""
    hy = W / 2
    if face == "floor":
        return (x, t, h)
    if face == "roof":
        return (x, t, H - h)
    sy = 1 if face == "left" else -1
    return (x, sy * (hy - h), t)


def patch(b, face, x0, x1, t0, t1, h, m):
    """A flat patch on an inner face, h proud of it (one quad, facing in)."""
    pts = [_onface(face, x0, t0, h), _onface(face, x1, t0, h), _onface(face, x1, t1, h), _onface(face, x0, t1, h)]
    b.oquad(pts, m, ((x0 + x1) / 2, 0.0, H / 2))


def ridge(b, face, x, w, ht, t0, t1, m):
    """A low ridge across a face (two sloped quads), w wide, ht high."""
    for xa, ha, xb, hb in ((x - w / 2, 0.0, x, ht), (x, ht, x + w / 2, 0.0)):
        pts = [_onface(face, xa, t0, ha), _onface(face, xb, t0, hb), _onface(face, xb, t1, hb), _onface(face, xa, t1, ha)]
        b.oquad(pts, m, (x, 0.0, H / 2))


def sealed_joint(b, x, seed):
    """A transverse joint seen from inside: where each section's wall turns
    out into its rolled flange there's a rounded edge either side of a gap
    with the flange gasket dark at the bottom; sealant brushed over it with
    3 in glass fibre tape bedded in, in patchy strokes (bits of the joint
    show through), heavier in the corners."""
    import random
    r = random.Random(seed)
    hy = W / 2
    band = 3 * IN
    faces = {"floor": (-hy, hy), "roof": (-hy, hy), "left": (0.0, H), "right": (0.0, H)}
    for f, (t0, t1) in faces.items():
        patch(b, f, x - 0.003, x + 0.003, t0, t1, 0.0004, "gasket")
        for dx in (-0.0065, 0.0065):
            ridge(b, f, x + dx, 0.007, 0.0028, t0, t1, "duct_galv")
        for k in range(r.randint(2, 4)):
            w_ = band * r.uniform(0.6, 1.2)
            off = r.uniform(-0.015, 0.015)
            a = t0 + r.uniform(0, 0.5) * (t1 - t0)
            c = min(t1, a + r.uniform(0.3, 1.0) * (t1 - t0))
            patch(b, f, x + off - w_ / 2, x + off + w_ / 2, a, c, 0.0032 + 0.0006 * k, "mastic")
    for sy in (-1, 1):
        for z in (0.0, H):     # heavier at the corners
            b.box((band * 1.2, 0.03, 0.03), (x, sy * hy, z), "mastic", rot=(math.pi / 4, 0, 0))


def access_door(L, x, side):
    """An 18 x 18 in access door in a side wall (seen from inside: the door's
    inner skin in its frame, gasket round it)."""
    b = L.b
    s = 18 * IN
    y = side * (W / 2 - 0.002)
    zc = H / 2
    b.box((s + 0.05, 0.004, s + 0.05), (x, y, zc), "duct_galv")
    b.box((s, 0.006, s), (x, y - side * 0.002, zc), "gasket")
    b.box((s - 0.02, 0.008, s - 0.02), (x, y - side * 0.004, zc), "duct_galv")
    for dz in (-0.12, 0.12):   # cam latch posts through the skin
        b.cyl(0.008, 0.008, 0.02, (x + s / 2 - 0.04, y - side * 0.01, zc + dz), "liner_pin", segs=8,
              rot=(math.pi / 2, 0, 0))
    L.kit.spot("spot_door", L.w((x, side * W / 2, zc)), L.ang)


def node(kit, name):
    cx, cy = NODES[name]
    b = kit.b
    op = OPEN[name]
    hw = W / 2
    ctr = (cx, cy, H / 2)
    x0, x1, y0, y1 = cx - hw, cx + hw, cy - hw, cy + hw
    flat(b, (x0, y0, 0), (x1, y0, 0), (x1, y1, 0), (x0, y1, 0), "duct_floor", ctr)
    flat(b, (x0, y0, H), (x1, y0, H), (x1, y1, H), (x0, y1, H), "duct_top", ctr)
    sides = {0: ((x1, y0), (x1, y1)), 90: ((x0, y1), (x1, y1)), 180: ((x0, y0), (x0, y1)), 270: ((x0, y0), (x1, y0))}
    for ang, (p, q) in sides.items():
        if ang in op:
            continue
        if name == "n0" and ang == 270:
            entry_grille(kit, p, q)
            continue
        xbreak(b, (*p, 0), (*q, 0), (*q, H), (*p, H), "duct_galv",
               (math.cos(math.radians(ang)) * BREAK * 0.5, math.sin(math.radians(ang)) * BREAK * 0.5, 0), ctr)
        kit.col((0.2 if ang in (0, 180) else W + 0.4, W + 0.4 if ang in (0, 180) else 0.2, H),
                (cx + math.cos(math.radians(ang)) * (hw + 0.1), cy + math.sin(math.radians(ang)) * (hw + 0.1), H / 2))
    kit.col((W + 0.4, W + 0.4, 0.2), (cx, cy, -0.1))
    kit.col((W + 0.4, W + 0.4, 0.2), (cx, cy, H + 0.1))
    if len(op) == 2 and VANES.get(name):
        a, c = sorted(op)
        if (c - a) % 180 == 90:
            vanes(kit, name, op, VANES[name])
    kit.spot("spot_node_" + name, (cx, cy, 0.0), 0.0)


def vanes(kit, name, op, kind):
    """Turning vanes on their rails along the elbow's diagonal (throat to
    heel). Canonical elbow: open S and W (flow north, then west); others
    rotated from it."""
    cx, cy = NODES[name]
    for k in range(4):
        if {(270 + 90 * k) % 360, (180 + 90 * k) % 360} == op:
            break
    rot = math.radians(90 * k)
    c, s = math.cos(rot), math.sin(rot)

    def w(x, y):
        return (cx + x * c - y * s, cy + x * s + y * c)
    b = kit.b
    hw = W / 2
    diag = W * math.sqrt(2)
    n = int(diag / VANE_P)
    cut = 0.6 if kind == "torn" else 0.0
    for i in range(n):
        t = (i + 0.5) / n
        if t < cut:
            continue
        px, py = -hw + t * W, -hw + t * W          # on the throat (SW) -> heel (NE) diagonal
        ccx, ccy = px - VANE_R / 2, py - VANE_R / 2   # the arc's centre
        segs = 6
        for j in range(segs):
            a0 = math.pi / 2 * j / segs
            a1 = math.pi / 2 * (j + 1) / segs
            p0 = w(ccx + VANE_R * math.cos(a0), ccy + VANE_R * math.sin(a0))
            p1 = w(ccx + VANE_R * math.cos(a1), ccy + VANE_R * math.sin(a1))
            # (26 ga: a thin box per facet, so both faces survive the
            # lightmap unwrap's vertex merge)
            mx, my = (p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2
            ln = math.hypot(p1[0] - p0[0], p1[1] - p0[1])
            b.box((ln + 0.0004, 0.0008, H - 0.02), (mx, my, H / 2), "vane",
                  rot=(0, 0, math.atan2(p1[1] - p0[1], p1[0] - p0[0])))
    # Rails top and bottom along the diagonal.
    a0, a1 = w(-hw + cut * W, -hw + cut * W), w(hw, hw)
    mx, my = (a0[0] + a1[0]) / 2, (a0[1] + a1[1]) / 2
    ln = math.hypot(a1[0] - a0[0], a1[1] - a0[1])
    da = math.atan2(a1[1] - a0[1], a1[0] - a0[0])
    for z in (0.005, H - 0.005):
        b.box((ln, 2.25 * IN, 0.01), (mx, my, z), "vane", rot=(0, 0, da))
    kit.col((ln, 0.12, H), (mx, my, H / 2), da)
    if kind == "torn":
        # The torn-out vanes, bent, on the floor.
        for j, (x, y, r) in enumerate(((-0.25, -0.05, 0.4), (-0.05, -0.3, 1.9), (0.1, 0.05, 2.8))):
            p = w(x, y)
            b.box((0.5, 0.06, 0.004), (p[0], p[1], 0.004 + 0.002 * j), "vane", rot=(0.05 * j, 0.08, r + rot))
        # A stub of the rail where they were (bent up).
        p = w(-hw + 0.3 * W, -hw + 0.3 * W)
        b.box((0.4, 2.25 * IN, 0.006), (p[0], p[1], 0.03), "vane", rot=(0, -0.12, math.pi / 4 + rot))


def entry_grille(kit, p, q):
    """The end cap at the start: the 24 x 16 in sidewall grille you came in
    through, the Backrooms' light behind it."""
    b = kit.b
    (x0, y), (x1, _y) = p, q
    gw, gh, z0 = 24 * IN, 16 * IN, 0.14
    ctr = ((x0 + x1) / 2, y + 0.5, H / 2)
    cx = (x0 + x1) / 2
    # Cap with the opening.
    flat(b, (x0, y, 0), (x1, y, 0), (x1, y, z0), (x0, y, z0), "duct_galv", ctr)
    flat(b, (x0, y, z0 + gh), (x1, y, z0 + gh), (x1, y, H), (x0, y, H), "duct_galv", ctr)
    flat(b, (x0, y, z0), (cx - gw / 2, y, z0), (cx - gw / 2, y, z0 + gh), (x0, y, z0 + gh), "duct_galv", ctr)
    flat(b, (cx + gw / 2, y, z0), (x1, y, z0), (x1, y, z0 + gh), (cx + gw / 2, y, z0 + gh), "duct_galv", ctr)
    # The grille's blades (seen from behind: the duct side).
    n = int(gh / BAR)
    for i in range(n):
        b.box((gw, 0.028, 0.0025), (cx, y - 0.016, z0 + (i + 0.5) * gh / n), "grille", rot=(math.radians(-40), 0, 0))
    for sx in (-1, 1):
        b.box((0.004, 0.03, gh), (cx + sx * gw / 2, y - 0.016, z0 + gh / 2), "grille")
        b.box((gw, 0.03, 0.004), (cx, y - 0.016, z0 + gh / 2 + sx * gh / 2), "grille")
    # Behind it: the Backrooms (its wallpaper, lit by its fluorescent hum).
    b.box((gw + 0.3, 0.02, gh + 0.3), (cx, y - 0.45, z0 + gh / 2), "entry_glow")
    K.point_light(kit, (cx, y - 0.3, z0 + gh + 0.2), 4.0, color=(1.0, 0.88, 0.6), radius=0.3)
    kit.col((W + 0.4, 0.2, H), (cx, y - 0.1, H / 2))


def damper_and_fan(kit):
    """Fan spur (x = -10): the opposed-blade damper's hat-channel frame, and
    the tube-axial fan's panel, ring and motor (blades are moving parts,
    made in Godot)."""
    b = kit.b
    x = -10.0
    hw = W / 2
    lip = 1 * IN
    d = 5 * IN
    for sy in (-1, 1):
        b.box((lip, d, H), (x + sy * (hw - lip / 2), DAMPER_Y, H / 2), "duct_galv")
    for z in (lip / 2, H - lip / 2):
        b.box((W, d, lip), (x, DAMPER_Y, z), "duct_galv")
    kit.spot("spot_damper", (x, DAMPER_Y, H / 2), 0.0)
    # The fan: a plate across the duct with a 28 in ring.
    r = 14 * IN
    zc = H / 2
    segs = 32
    y = FAN_Y
    for i in range(segs):
        a0, a1 = 2 * math.pi * i / segs, 2 * math.pi * (i + 1) / segs

        def edge(a):
            cs, sn = math.cos(a), math.sin(a)
            k = min(hw / max(abs(cs), 1e-6), (H / 2) / max(abs(sn), 1e-6))
            return (x + cs * k, zc + sn * k)
        e0, e1 = edge(a0), edge(a1)
        c0 = (x + r * math.cos(a0), zc + r * math.sin(a0))
        c1 = (x + r * math.cos(a1), zc + r * math.sin(a1))
        for yy, rev in ((y + 0.003, False), (y - 0.003, True)):
            pts = [(c0[0], yy, c0[1]), (c1[0], yy, c1[1]), (e1[0], yy, e1[1]), (e0[0], yy, e0[1])]
            b.quad(list(reversed(pts)) if rev else pts, "fan_paint")
        # The ring (housing), 0.25 m deep, both faces.
        pts = [(c0[0], y - 0.25, c0[1]), (c1[0], y - 0.25, c1[1]), (c1[0], y, c1[1]), (c0[0], y, c0[1])]
        b.quad(pts, "fan_paint")
        k = (r + 0.003) / r      # the outer skin, 3 mm out (its own vertices)
        pts = [(x + (p[0] - x) * k, p[1], zc + (p[2] - zc) * k) for p in pts]
        b.quad(list(reversed(pts)), "fan_paint")
    # Motor behind the hub, on three struts.
    b.cyl(0.11, 0.11, 0.24, (x, y - 0.2, zc), "fan_paint", segs=16, rot=(math.pi / 2, 0, 0))
    for k in range(3):
        a = math.pi / 2 + 2 * math.pi * k / 3
        b.box((r - 0.1, 0.02, 0.03), (x + math.cos(a) * (r / 2 + 0.05), y - 0.22, zc + math.sin(a) * (r / 2 + 0.05)),
              "fan_paint", rot=(0, -a, 0))
    kit.col((W + 0.4, 0.3, H), (x, y - 0.1, H / 2))
    kit.col((W + 0.4, 0.2, H), (x, DAMPER_Y, H / 2))      # the damper (shut, or nearly)
    kit.spot("spot_fan", (x, y + 0.08, zc), 0.0)


# -------------------------------------------------------------- the rooms ---
def room(kit, rect, group, door_side, holes):
    """An empty office below: carpet, painted walls with rubber base, a lay-in
    ceiling (holes for the registers), troffers, a door and a switch."""
    b = kit.b
    x0, y0, x1, y1 = rect
    z0, z1 = FLOOR, CEIL
    c = ((x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2)
    flat(b, (x0, y0, z0), (x1, y0, z0), (x1, y1, z0), (x0, y1, z0), "carpet", c)
    # Ceiling with holes (each a rect (hx0, hy0, hx1, hy1)) cut as strips.
    hs = sorted(holes, key=lambda h: h[1])
    ys = [y0]
    for h in hs:
        ys += [h[1], h[3]]
    ys.append(y1)
    for i in range(0, len(ys) - 1):
        ya, yb = ys[i], ys[i + 1]
        if yb - ya < 1e-4:
            continue
        inside = [h for h in hs if h[1] <= ya + 1e-6 and h[3] >= yb - 1e-6]
        if inside:
            h = inside[0]
            flat(b, (x0, ya, z1), (h[0], ya, z1), (h[0], yb, z1), (x0, yb, z1), "ceiling_tile", c)
            flat(b, (h[2], ya, z1), (x1, ya, z1), (x1, yb, z1), (h[2], yb, z1), "ceiling_tile", c)
        else:
            flat(b, (x0, ya, z1), (x1, ya, z1), (x1, yb, z1), (x0, yb, z1), "ceiling_tile", c)
    walls = {"s": ((x0, y0), (x1, y0)), "n": ((x0, y1), (x1, y1)), "w": ((x0, y0), (x0, y1)), "e": ((x1, y0), (x1, y1))}
    for k, (p, q) in walls.items():
        flat(b, (*p, z0), (*q, z0), (*q, z1), (*p, z1), "wall_paint", c)
        # Rubber cove base, 4 in.
        dx, dy = q[0] - p[0], q[1] - p[1]
        ln = math.hypot(dx, dy)
        nx, ny = (c[0] - (p[0] + q[0]) / 2), (c[1] - (p[1] + q[1]) / 2)
        nl = math.hypot(nx, ny)
        off = 0.003
        mx = (p[0] + q[0]) / 2 + nx / nl * off * (1 if k in "ew" else 0)
        my = (p[1] + q[1]) / 2 + ny / nl * off * (1 if k in "ns" else 0)
        b.box((ln if k in "ns" else 0.006, ln if k in "ew" else 0.006, 4 * IN), (mx, my, z0 + 2 * IN), "base")
    # Door (36 x 84 in) with its frame, near one end of its wall, and the switch.
    p, q = walls[door_side]
    along = (q[0] - p[0], q[1] - p[1])
    ln = math.hypot(*along)
    ux, uy = along[0] / ln, along[1] / ln
    nx, ny = c[0] - (p[0] + q[0]) / 2, c[1] - (p[1] + q[1]) / 2
    nl = math.hypot(nx, ny)
    nx, ny = (nx / nl, 0) if door_side in "ew" else (0, ny / nl)
    dc = (p[0] + ux * 1.1, p[1] + uy * 1.1)
    dw, dh = 36 * IN, 84 * IN
    rz = math.atan2(uy, ux)
    b.box((dw, 0.012, dh), (dc[0] + nx * 0.006, dc[1] + ny * 0.006, z0 + dh / 2), "door", rot=(0, 0, rz))
    for s_ in (-1, 1):
        b.box((0.05, 0.03, dh + 0.05), (dc[0] + ux * s_ * (dw / 2 + 0.025) + nx * 0.012,
                                         dc[1] + uy * s_ * (dw / 2 + 0.025) + ny * 0.012, z0 + dh / 2), "door_frame", rot=(0, 0, rz))
    b.box((dw + 0.1, 0.03, 0.05), (dc[0] + nx * 0.012, dc[1] + ny * 0.012, z0 + dh + 0.025), "door_frame", rot=(0, 0, rz))
    hx, hy = dc[0] + ux * (dw / 2 - 0.08) + nx * 0.05, dc[1] + uy * (dw / 2 - 0.08) + ny * 0.05
    b.box((0.13, 0.02, 0.02), (hx - ux * 0.05, hy - uy * 0.05, z0 + 0.96), "door_frame", rot=(0, 0, rz))
    b.cyl(0.025, 0.025, 0.05, (hx, hy, z0 + 0.96), "door_frame", segs=8, rot=(math.pi / 2, 0, rz))
    sw = (p[0] + ux * 1.9 + nx * 0.004, p[1] + uy * 1.9 + ny * 0.004)
    b.box((0.07, 0.006, 0.115), (sw[0], sw[1], z0 + 1.22), "plate", rot=(0, 0, rz))
    # Troffers: three 2 x 4 lay-ins along the room's long axis, missing the holes.
    lamp = LAMPS.get(group, None) if group is not None else None
    long_x = (x1 - x0) > (y1 - y0)
    n = 3
    for i in range(n):
        t = (i + 0.5) / n
        if long_x:
            tx, ty, size = x0 + t * (x1 - x0), (y0 + y1) / 2, (TROFFER[1], TROFFER[0])
        else:
            tx, ty, size = (x0 + x1) / 2, y0 + t * (y1 - y0), (TROFFER[0], TROFFER[1])
        for h in holes:      # move off a register
            if abs(tx - (h[0] + h[2]) / 2) < (size[0] + h[2] - h[0]) / 2 + 0.1 and \
                    abs(ty - (h[1] + h[3]) / 2) < (size[1] + h[3] - h[1]) / 2 + 0.1:
                if long_x:
                    ty += 1.25
                else:
                    tx += 1.25
        b.box((size[0] + 0.05, size[1] + 0.05, 0.01), (tx, ty, z1 - 0.003), "troffer_frame")
        b.box((size[0] - 0.05, size[1] - 0.05, 0.004), (tx, ty, z1 - 0.009), lamp or "troffer_frame")
        if lamp:
            K.area_light(kit, (tx, ty, z1 - 0.02), (size[0] - 0.05, size[1] - 0.05), TROFFER_W, color=CCT_4000K,
                         group=group)
    kit.spot("spot_room_%d" % ROOMS.index((rect, group, door_side)), (c[0], c[1], z0), 0.0)
    kit.col((x1 - x0, y1 - y0, 0.2), (c[0], c[1], z0 - 0.1))


def desk(b, x, y, rz, rng):
    """A 60 x 30 in steel-framed desk with a laminate top (29 in high), its
    chair pushed out at an angle, sometimes a monitor (switched off)."""
    from mathutils import Matrix
    d = K.Builder()
    w, dp, h = 60 * IN, 30 * IN, 29 * IN
    d.box((w, dp, 0.025), (0, 0, h - 0.0125), "laminate")
    for sx in (-1, 1):
        d.box((0.025, dp - 0.04, h - 0.025), (sx * (w / 2 - 0.0125), 0, (h - 0.025) / 2), "desk_metal")
    d.box((w - 0.05, 0.015, 0.4), (0, dp / 2 - 0.05, h - 0.25), "desk_metal")
    if rng.random() < 0.7:
        d.box((0.56, 0.04, 0.33), (rng.uniform(-0.3, 0.3), dp / 2 - 0.18, h + 0.28), "monitor")
        d.box((0.06, 0.06, 0.12), (0, dp / 2 - 0.18, h + 0.06), "desk_metal")
        d.box((0.22, 0.18, 0.01), (0, dp / 2 - 0.18, h + 0.005), "desk_metal")
    # The chair: five-star base, column, seat, back.
    cx, cy = rng.uniform(-0.35, 0.35), -dp / 2 - rng.uniform(0.1, 0.45)
    cr = rng.uniform(-0.8, 0.8)
    for k in range(5):
        a = cr + 2 * math.pi * k / 5
        d.box((0.33, 0.035, 0.03), (cx + math.cos(a) * 0.16, cy + math.sin(a) * 0.16, 0.06), "desk_metal", rot=(0, 0, a))
    d.cyl(0.025, 0.025, 0.36, (cx, cy, 0.25), "desk_metal", segs=8)
    d.box((0.48, 0.46, 0.07), (cx, cy, 0.46), "chair_fabric", rot=(0, 0, cr), bevel=0.02)
    bx, by = cx - math.sin(cr) * 0.22 * -1, cy - math.cos(cr) * 0.22
    d.box((0.45, 0.06, 0.48), (bx, by, 0.78), "chair_fabric", rot=(0.12, 0, cr), bevel=0.02)
    b.place(d, Matrix.Translation((x, y, FLOOR)) @ Matrix.Rotation(rz, 4, "Z"))


def furnish(kit, rect, i):
    """The offices aren't stripped: desks in rows, a filing cabinet, a bin,
    a whiteboard. Nobody is at any of them."""
    import random
    rng = random.Random(100 + i)
    b = kit.b
    x0, y0, x1, y1 = rect
    long_x = (x1 - x0) > (y1 - y0)
    if i == 3:       # the plant room: a cabinet or two, nothing else
        b.box((0.9, 0.6, 1.9), (x1 - 0.6, y1 - 0.5, FLOOR + 0.95), "cabinet")
        b.box((0.9, 0.6, 1.9), (x1 - 1.55, y1 - 0.5, FLOOR + 0.95), "cabinet")
        return
    rows = 2
    for rr in range(rows):
        for cc in range(2):
            if long_x:
                x = x0 + (x1 - x0) * (0.3 + 0.4 * cc)
                y = y0 + (y1 - y0) * (0.3 + 0.42 * rr)
                rz = 0.0 if rr == 0 else math.pi
            else:
                x = x0 + (x1 - x0) * (0.3 + 0.42 * rr)
                y = y0 + (y1 - y0) * (0.3 + 0.4 * cc)
                rz = math.pi / 2 if rr == 0 else -math.pi / 2
            if rng.random() < 0.85:
                desk(b, x + rng.uniform(-0.05, 0.05), y + rng.uniform(-0.05, 0.05), rz + rng.uniform(-0.03, 0.03), rng)
    # A four-drawer filing cabinet (15 x 28 x 52 in) in a corner, a bin.
    cw, cd, ch = 15 * IN, 28 * IN, 52 * IN
    b.box((cw, cd, ch), (x1 - cw / 2 - 0.02, y0 + cd / 2 + 0.3, FLOOR + ch / 2), "cabinet")
    for k in range(4):     # drawer fronts' handles, on the face towards the room
        b.box((0.006, 0.12, 0.025), (x1 - cw - 0.022, y0 + 0.3 + cd / 2, FLOOR + ch / 8 + k * ch / 4 + 0.08), "desk_metal")
        b.box((0.003, cd - 0.03, 0.004), (x1 - cw - 0.021, y0 + 0.3 + cd / 2, FLOOR + (k + 1) * ch / 4 - 0.004), "desk_metal")
    b.cyl(0.14, 0.12, 0.38, (x0 + 0.4, y1 - 0.4, FLOOR + 0.19), "desk_metal", segs=12)
    # Whiteboard (4 x 3 ft) on the long wall.
    if long_x:
        b.box((1.22, 0.015, 0.91), ((x0 + x1) / 2, y1 - 0.008, FLOOR + 1.45), "whiteboard")
    else:
        b.box((0.015, 1.22, 0.91), (x1 - 0.008, (y0 + y1) / 2, FLOOR + 1.45), "whiteboard")


def build_rooms():
    kit = K.Kit("crawl_rooms")
    holes = []
    for a, b_, feats in DUCTS:
        ax, ay = NODES[a]
        ang = side_angle(a, b_)
        for f in feats:
            if isinstance(f, tuple) and f[0] in ("reg", "exit"):
                across, along = REG if f[0] == "reg" else EXIT
                px, py = ax + math.cos(ang) * f[1], ay + math.sin(ang) * f[1]
                hx = along if abs(math.cos(ang)) > 0.5 else across
                hy = across if abs(math.cos(ang)) > 0.5 else along
                holes.append((px - hx / 2, py - hy / 2, px + hx / 2, py + hy / 2))
    for rect, group, door in ROOMS:
        x0, y0, x1, y1 = rect
        mine = [h for h in holes if h[0] >= x0 and h[2] <= x1 and h[1] >= y0 and h[3] <= y1]
        room(kit, rect, group, door, mine)
        furnish(kit, rect, ROOMS.index((rect, group, door)))
        # The slab above the ceiling (the plenum's floor is the tiles' back).
    kit.export(OUT, lm=1024, samples=128)


def build_duct():
    kit = K.Kit("crawl_duct")
    for n in NODES:
        node(kit, n)
    for a, b_, f in DUCTS:
        duct(kit, a, b_, f)
    damper_and_fan(kit)
    kit.spot("spot_arrival", (0.0, -0.05, 0.0), 0.0)
    kit.export(OUT, lm=1024, samples=160)


build_rooms()
build_duct()

PREVIEW = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--preview=")]
if PREVIEW:
    # A quick Cycles look down a register (to check the light coming up).
    import bpy as _bpy
    kit = K.Kit("_preview")
    kit.preview(PREVIEW[0], (0.0, 5.25, 0.38), (0.0, 6.3, -2.9), lens=24,
                samples=24)
