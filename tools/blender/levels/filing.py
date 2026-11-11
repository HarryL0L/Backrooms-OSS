"""The Stacks (side level "filing"): a records centre's storage floor after
hours, about 1030 m2, built at the sizes in assets/levels/filing/SPEC.md
from the floor plan in tools/blender/levels/filing_layout.py: five storage
bays and a sorting room behind 8 in block fire-barrier walls, two 72 in
service corridors, sealed concrete under a 3.2 m painted slab, 2-lamp T8
strips hung in rows across the ranges on occupancy sensors.

This script makes one kit per room (floor and rails, walls with their fire
door openings and held-open leaves, slab, strips, sprinklers, ducts, the
sorting room's furniture): everything that doesn't move, each baked on its
own. The mobile shelving itself is the level's own procedural geometry
(scripts/world/levels/filing_level.gd), lit analytically by the level's
shader (assets/levels/filing/filing_lit.gdshaderinc) from the same strip
rows, because it moves.

Light (L.U.C.I.D. units, as office.py): each strip's two tubes are emitters
of their real luminance (Lucid strip_t8_2lamp, 4500 lm x LLF 0.85 over the
tubes' surface: 6510 cd/m2), stored as cd/m2 / 153.6. Each room's four
light groups are its occupancy-sensor zones (filing_layout.ROWS); always on
(colour bake): the night-light strips and the exit sign. The untextured
materials are merged into one vertex-coloured "paint" surface after the
bake (merge_paint), so each kit is ~5 draw calls.

Run:
  python3 tools/blender/levels/filing_layout.py [--map out.png]          (layout data, map)
  /tmp/claude-0/bpyenv/bin/python tools/blender/levels/filing.py [out] [--fast] [--samples N] [--cells R1,C1]
  python3 tools/blender/levels/filing.py --textures <download dir>   (textures)
  python3 tools/blender/levels/filing.py --labels                    (signs, cards, plans)
  python3 tools/blender/levels/filing.py --sounds                    (audio)
"""
import math
import os
import random
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "assets/levels/filing"
IN = 0.0254
FT = 0.3048

# ---------------------------------------------------------------- sizes ---
# (the floor plan and the shelving's sizes are in filing_layout.py)
CEIL = 3.20                 # floor to slab soffit
STRIP_Z = 2.85              # strip underside (tubes just below)
DOOR_W, DOOR_H = 36 * IN, 84 * IN
# Light: L.U.C.I.D. units.
UNIT_NITS = 153.6
LLF = 0.85
STRIP_LM = 4500.0
TUBE_R = 0.0127
TUBE_L = 1.17
TUBE_AREA = 2 * (2 * math.pi * TUBE_R * TUBE_L)
TUBE_NITS = STRIP_LM * LLF / (math.pi * TUBE_AREA)
TUBE_EMIT = TUBE_NITS / UNIT_NITS
EXIT_EMIT = 300.0 / UNIT_NITS


# ============================================================ textures ===

def write_import(path, normal=False):
    params = {"compress/mode": 2, "compress/normal_map": 1 if normal else 0, "mipmaps/generate": "true",
              "process/fix_alpha_border": "true", "detect_3d/compress_to": 0}
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n')
        for k, v in params.items():
            f.write(f"{k}={v}\n")


def make_textures(src):
    """CC0 downloads (src/<Asset>/...) -> textures/, colour scaled so its
    linear mean is the albedo in SPEC.md; the carton atlas, range cards,
    exit sign and paper drawn here over them."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
    dst = os.path.join(OUT, "textures")
    os.makedirs(dst, exist_ok=True)
    rng = np.random.default_rng(1101)

    def lin(a):
        return np.power(np.clip(a, 0, 255) / 255.0, 2.2)

    def srgb(a):
        return np.clip(np.power(np.clip(a, 0, 1), 1 / 2.2) * 255.0 + 0.5, 0, 255).astype(np.uint8)

    def albedo_arr(img, target, sat=0.0):
        la = lin(np.asarray(img.convert("RGB"), np.float64))
        grey = la.mean(axis=2, keepdims=True)
        la = grey + (la - grey) * sat
        return la / la.reshape(-1, 3).mean(axis=0) * np.array(target)

    def acg(asset, kind):
        return Image.open(os.path.join(src, asset, f"{asset}_1K-JPG_{kind}.jpg"))

    def ph(asset, kind):
        return Image.open(os.path.join(src, asset, f"{asset}_{kind}.jpg"))

    def save(img, name, size=None, q=88):
        if size:
            img = img.resize((size, size) if isinstance(size, int) else size, Image.LANCZOS)
        img.save(os.path.join(dst, name), quality=q)

    # Sealed concrete floor (Poly Haven concrete_floor_worn_001): mid grey,
    # a little warm, the sealer's sheen (roughness scaled down).
    a = albedo_arr(ph("concrete_floor_worn_001", "Diffuse"), (0.30, 0.295, 0.28), 0.35)
    save(Image.fromarray(srgb(a)), "concrete_floor_diff.jpg", 1024)
    save(ph("concrete_floor_worn_001", "nor_gl"), "concrete_floor_nor.jpg", 512)
    r = np.asarray(ph("concrete_floor_worn_001", "Rough").convert("L"), np.float64) / 255.0
    r = np.clip(0.30 + (r - r.mean()) * 0.8 + 0.12, 0.15, 0.9)
    save(Image.fromarray((r * 255).astype(np.uint8)), "concrete_floor_rough.jpg", 256)

    # Painted concrete block (8 x 16 in nominal, 3/8 in tooled joints,
    # running bond) over ambientCG PaintedPlaster017: one repeat = 3 blocks
    # x 6 courses = 48 x 48 in.
    S = 1024
    base = albedo_arr(acg("PaintedPlaster017", "Color").resize((S, S), Image.LANCZOS), (0.60, 0.59, 0.555), 0.0)
    nor = np.asarray(acg("PaintedPlaster017", "NormalGL").convert("RGB").resize((S, S), Image.LANCZOS), np.float64)
    px = S / (48 * IN)                       # pixels per metre
    joint = 0.0095 * px
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float64)
    course = 8 * IN * px
    row = np.floor(yy / course)
    xs = xx + (row % 2) * (8 * IN * px)
    blk = 16 * IN * px
    dy = np.minimum(yy % course, course - yy % course)
    dx = np.minimum(xs % blk, blk - xs % blk)
    d = np.minimum(dx, dy)
    j = np.clip(1.0 - d / joint, 0, 1)                  # 1 in the joint centre
    base *= (1.0 - 0.18 * j)[:, :, None]
    # (blocks a touch uneven in tone, paint thicker in places)
    tone = 1.0 + 0.025 * rng.standard_normal((int(S / course) + 2, int(S / blk) + 3))
    base *= tone[row.astype(int), (np.floor(xs / blk)).astype(int) % tone.shape[1]][:, :, None]
    # joint normals: a concave groove across the joint
    gx = np.where(dx < dy, np.sign((xs % blk) - blk / 2) * -1, 0.0) * j
    gy = np.where(dy <= dx, np.sign((yy % course) - course / 2) * -1, 0.0) * j
    nor[:, :, 0] = np.clip(nor[:, :, 0] + gx * 70, 0, 255)
    nor[:, :, 1] = np.clip(nor[:, :, 1] - gy * 70, 0, 255)
    save(Image.fromarray(srgb(base)), "cmu_paint_diff.jpg", 512)
    save(Image.fromarray(nor.astype(np.uint8)), "cmu_paint_nor.jpg", 512)
    rr = np.asarray(acg("PaintedPlaster017", "Roughness").convert("L").resize((256, 256)), np.float64)
    save(Image.fromarray(np.clip(rr * 0.9, 0, 255).astype(np.uint8)), "cmu_paint_rough.jpg")
    # The slab soffit: the same paint, flat white, no joints.
    pl = albedo_arr(acg("PaintedPlaster017", "Color"), (0.72, 0.72, 0.70), 0.0)
    pl = pl.mean(axis=(0, 1)) + (pl - pl.mean(axis=(0, 1))) * 0.35        # (rolled paint: flatter)
    save(Image.fromarray(srgb(pl)), "slab_paint_diff.jpg", 512)
    save(acg("PaintedPlaster017", "NormalGL"), "slab_paint_nor.jpg", 512)

    # The sorting room's pigeonhole case (ambientCG Wood090A, birch): aged
    # and darkened to an old varnished case.
    a = albedo_arr(acg("Wood090A", "Color"), (0.33, 0.22, 0.13), 0.9)
    save(Image.fromarray(srgb(a)), "sorter_wood_diff.jpg", 512)
    save(acg("Wood090A", "NormalGL"), "sorter_wood_nor.jpg", 256)

    # The carton atlas, 1024 x 1024 in 4 x 4 cells of 256 px:
    #  row 0, 1: carton ends (12 x 10 in, what faces the aisle): 8 kinds
    #  row 2: kraft side, white side, kraft lid, white lid
    #  row 3: two sheets of paper, two cells of range cards.
    kraft = albedo_arr(acg("Cardboard002", "Color").resize((512, 512)), (0.40, 0.29, 0.17), 0.85)
    kraft2 = albedo_arr(acg("Cardboard004", "Color").resize((512, 512)), (0.36, 0.26, 0.155), 0.85)
    knor = np.asarray(acg("Cardboard002", "NormalGL").convert("RGB").resize((512, 512)), np.float64)
    W = 1024
    atlas = np.zeros((W, W, 3))
    anor = np.full((W, W, 3), (128.0, 128.0, 255.0))
    C = 256

    def cell(cx, cy):
        return slice(cy * C, cy * C + C), slice(cx * C, cx * C + C)

    def kraft_cell(variant, white=False):
        k = kraft if variant % 2 == 0 else kraft2
        ox, oy = (variant * 97) % 256, (variant * 61) % 256
        t = k[oy:oy + C, ox:ox + C].copy()
        if white:
            g = t.mean(axis=2, keepdims=True)
            t = 0.70 + (g - g.mean()) * 0.6 + np.zeros_like(t)
            t *= np.array([1.0, 0.99, 0.96])
        return t

    def draw_rect(t, x0, y0, x1, y1, col):
        t[int(y0):int(y1), int(x0):int(x1)] = col

    def grime(t, amount):
        n = rng.standard_normal((16, 16))
        n = np.array(Image.fromarray(((n - n.min()) / (np.ptp(n)) * 255).astype(np.uint8)).resize((C, C), Image.BICUBIC),
                     np.float64) / 255.0
        return t * (1.0 - amount * np.clip(n - 0.4, 0, 1)[:, :, None])

    def scribble(t, x0, y0, w, h, lines, col, seed):
        """Hand-written marker lines (no real text): wobbly strokes."""
        im = Image.new("L", (C, C), 0)
        dr = ImageDraw.Draw(im)
        rr2 = random.Random(seed)
        for li in range(lines):
            y = y0 + (li + 0.6) * h / lines
            x = x0 + rr2.uniform(0, 4)
            end = x0 + w * rr2.uniform(0.6, 0.97)
            while x < end:
                # a "word": one continuous cursive stroke of loops
                n = rr2.randint(4, 9)
                pts = []
                ph = rr2.uniform(0, 6.28)
                for k in range(n * 6):
                    ph += rr2.uniform(0.6, 1.4)
                    xx = x + k * rr2.uniform(0.9, 1.4)
                    amp = h / lines * (0.22 if rr2.random() > 0.15 else 0.45)
                    pts.append((xx, y - abs(math.sin(ph)) * amp + rr2.uniform(-0.4, 0.4)))
                if len(pts) > 1:
                    dr.line(pts, fill=255, width=2)
                x = pts[-1][0] + rr2.uniform(5, 10)
        m = np.asarray(im.filter(ImageFilter.GaussianBlur(0.6)), np.float64)[:, :, None] / 255.0
        return t * (1 - m) + np.array(col) * m

    def handhole(t, n, cxp, cyp, wpx, hpx):
        """A die-cut hand hole: dark inside, a pressed edge."""
        yy2, xx2 = np.mgrid[0:C, 0:C].astype(np.float64)
        e = ((xx2 - cxp) / (wpx / 2)) ** 2 + ((yy2 - cyp) / (hpx / 2)) ** 4
        hole = e < 1.0
        rim = (e >= 1.0) & (e < 1.6)
        t[hole] = t[hole] * 0.06
        t[rim] *= 0.85
        n[rim, 1] += np.clip((yy2[rim] - cyp) * 8, -60, 60)

    # carton ends: the end is 12 x 10 in; the cell's top 213 px is the end
    # (the rest is the lid's edge band, used by the lid overlap strip)
    ends = []
    for v in range(8):
        white = v in (2, 6)
        t = kraft_cell(v, white)
        n = knor[(v * 37) % 256:(v * 37) % 256 + C, (v * 53) % 256:(v * 53) % 256 + C].copy()
        # lid overlap band (2 in) at the top of the end
        draw_rect(t, 0, 0, C, 36, t[0:36].mean(axis=(0, 1)) * 0.9)
        t[34:37] *= 0.55
        n[34:37, :, 1] = 90
        if v in (0, 3, 4, 7):
            # a white label with marker writing
            lab = (0.78, 0.77, 0.72) if v != 7 else (0.80, 0.75, 0.52)
            draw_rect(t, 40, 64, 216, 136, lab)
            t = scribble(t, 46, 66, 164, 66, 3, (0.03, 0.03, 0.05), 300 + v)
        elif white:
            # printed frame and a write-on panel
            draw_rect(t, 22, 50, 234, 54, (0.30, 0.33, 0.38))
            draw_rect(t, 22, 186, 234, 190, (0.30, 0.33, 0.38))
            t = scribble(t, 40, 70, 170, 60, 2, (0.02, 0.02, 0.04), 400 + v)
        else:
            # straight on the kraft in thick marker
            t = scribble(t, 50, 64, 150, 78, 2, (0.02, 0.02, 0.03), 500 + v)
        handhole(t, n, 128, 172, 70, 22)
        t = grime(t, 0.25 if v in (1, 5) else 0.1)
        ends.append((t, n))
    for v, (t, n) in enumerate(ends):
        ys, xs = cell(v % 4, v // 4)
        atlas[ys, xs] = t
        anor[ys, xs] = n
    for i, (white, lid) in enumerate(((False, False), (True, False), (False, True), (True, True))):
        t = kraft_cell(10 + i, white)
        if lid:
            t[:, :12] *= 0.8
            t[:, -12:] *= 0.8
        ys, xs = cell(i, 2)
        atlas[ys, xs] = grime(t, 0.12)
        anor[ys, xs] = knor[:C, C:]
    # paper: two sheets (letter) with grey type lines and a form's boxes
    for i in range(2):
        t = np.full((C, C, 3), 0.80) * np.array([1.0, 0.995, 0.975])
        rr2 = random.Random(70 + i)
        y = 30
        while y < 230:
            x1 = rr2.uniform(150, 226)
            if rr2.random() < 0.15:
                y += 9
                continue
            draw_rect(t, 26, y, x1, y + 3, (0.30, 0.30, 0.31))
            y += 9
        if i == 1:
            for k in range(4):
                draw_rect(t, 26, 30 + k * 18, 230, 31 + k * 18, (0.35, 0.35, 0.36))
        ys, xs = cell(i, 3)
        atlas[ys, xs] = t
    # range cards: 48 cards (64 x 42 px) "A 01".."B 14", blocky printed
    # letters and digits drawn as strokes.
    SEG = {"0": "abcdef", "1": "bc", "2": "abged", "3": "abgcd", "4": "fgbc", "5": "afgcd", "6": "afgedc",
           "7": "abc", "8": "abcdefg", "9": "abcfgd", "A": "efabcg", "B": "fedcgb_"}

    def glyph(dr, ch, x, y, w, h, s):
        segs = {"a": [(x, y), (x + w, y)], "b": [(x + w, y), (x + w, y + h / 2)], "c": [(x + w, y + h / 2), (x + w, y + h)],
                "d": [(x, y + h), (x + w, y + h)], "e": [(x, y + h / 2), (x, y + h)], "f": [(x, y), (x, y + h / 2)],
                "g": [(x, y + h / 2), (x + w, y + h / 2)]}
        if ch == "B":
            for k in "fe":
                dr.line(segs[k], fill=255, width=s)
            dr.line([(x, y), (x + w * 0.8, y), (x + w, y + h * 0.2), (x + w, y + h * 0.35), (x + w * 0.8, y + h / 2),
                     (x, y + h / 2)], fill=255, width=s)
            dr.line([(x + w * 0.8, y + h / 2), (x + w, y + h * 0.65), (x + w, y + h * 0.8), (x + w * 0.8, y + h), (x, y + h)],
                    fill=255, width=s)
            return
        for k in SEG[ch]:
            dr.line(segs[k], fill=255, width=s)

    for half in range(2):
        im = Image.new("L", (C, C), 0)
        dr = ImageDraw.Draw(im)
        for k in range(24):
            idx = half * 24 + k
            bank, num = ("A", idx + 1) if idx < 24 else ("B", idx - 23)
            if idx >= 24:
                bank, num = "B", idx - 23
            cx0, cy0 = (k % 4) * 64, (k // 4) * 42
            txt = bank + "%02d" % num
            for ci, ch in enumerate(txt):
                glyph(dr, ch, cx0 + 8 + ci * 17 + (4 if ci > 0 else 0), cy0 + 9, 9, 22, 3)
        m = np.asarray(im.filter(ImageFilter.GaussianBlur(0.5)), np.float64)[:, :, None] / 255.0
        t = np.full((C, C, 3), 0.82) * (1 - m) + 0.03 * m
        for k in range(24):
            cx0, cy0 = (k % 4) * 64, (k // 4) * 42
            t[cy0:cy0 + 2, cx0:cx0 + 64] = 0.25
            t[cy0:cy0 + 42, cx0:cx0 + 2] = 0.25
        ys, xs = cell(2 + half, 3)
        atlas[ys, xs] = t
    Image.fromarray(srgb(atlas)).save(os.path.join(dst, "carton_diff.jpg"), quality=90)
    Image.fromarray(np.clip(anor, 0, 255).astype(np.uint8)).save(os.path.join(dst, "carton_nor.jpg"), quality=90)

    # Exit sign face: red LED letters on black (the letters only glow).
    w, h = 256, 96
    im = Image.new("L", (w, h), 0)
    dr = ImageDraw.Draw(im)
    s = 9
    x, y, gw, gh = 40, 22, 30, 52
    dr.line([(x + gw, y), (x, y), (x, y + gh), (x + gw, y + gh)], fill=255, width=s)       # E
    dr.line([(x, y + gh / 2), (x + gw * 0.8, y + gh / 2)], fill=255, width=s)
    x += gw + 18
    dr.line([(x, y), (x + gw, y + gh)], fill=255, width=s)                                # X
    dr.line([(x + gw, y), (x, y + gh)], fill=255, width=s)
    x += gw + 22
    dr.line([(x, y), (x, y + gh)], fill=255, width=s)                                     # I
    x += 20
    dr.line([(x, y), (x + gw, y)], fill=255, width=s)                                     # T
    dr.line([(x + gw / 2, y), (x + gw / 2, y + gh)], fill=255, width=s)
    m = np.asarray(im.filter(ImageFilter.GaussianBlur(1.2)), np.float64) / 255.0
    e = np.zeros((h, w, 3))
    e[:, :, 0] = 0.02 + 0.98 * m
    e[:, :, 1] = 0.02 + 0.20 * m
    e[:, :, 2] = 0.02 + 0.10 * m
    Image.fromarray(srgb(e)).resize((256, 128)).save(os.path.join(dst, "exit_face_diff.jpg"), quality=92)

    for fn in os.listdir(dst):
        if fn.endswith(".jpg"):
            write_import(os.path.join(dst, fn), normal=fn.endswith("_nor.jpg"))
    print("textures done")


# Stroke lettering (no fonts): each glyph a few polylines in a unit box
# (x right, y down), drawn at any size.
_O = [(0.2, 0), (0.8, 0), (1, 0.2), (1, 0.8), (0.8, 1), (0.2, 1), (0, 0.8), (0, 0.2), (0.2, 0)]
_P = [(0, 1), (0, 0), (0.8, 0), (1, 0.15), (1, 0.4), (0.8, 0.55), (0, 0.55)]
GLYPHS = {
    "A": [[(0, 1), (0.5, 0), (1, 1)], [(0.2, 0.62), (0.8, 0.62)]],
    "B": [[(0, 0.5), (0.72, 0.5), (0.95, 0.65), (0.95, 0.85), (0.75, 1), (0, 1), (0, 0), (0.7, 0), (0.9, 0.12),
           (0.9, 0.36), (0.72, 0.5)]],
    "C": [[(1, 0.12), (0.8, 0), (0.2, 0), (0, 0.2), (0, 0.8), (0.2, 1), (0.8, 1), (1, 0.88)]],
    "D": [[(0, 0), (0, 1), (0.65, 1), (1, 0.72), (1, 0.28), (0.65, 0), (0, 0)]],
    "E": [[(1, 0), (0, 0), (0, 1), (1, 1)], [(0, 0.5), (0.75, 0.5)]],
    "F": [[(1, 0), (0, 0), (0, 1)], [(0, 0.5), (0.75, 0.5)]],
    "G": [[(1, 0.15), (0.8, 0), (0.2, 0), (0, 0.2), (0, 0.8), (0.2, 1), (0.8, 1), (1, 0.8), (1, 0.55), (0.55, 0.55)]],
    "H": [[(0, 0), (0, 1)], [(1, 0), (1, 1)], [(0, 0.5), (1, 0.5)]],
    "I": [[(0.5, 0), (0.5, 1)], [(0.2, 0), (0.8, 0)], [(0.2, 1), (0.8, 1)]],
    "J": [[(1, 0), (1, 0.8), (0.8, 1), (0.2, 1), (0, 0.8)]],
    "K": [[(0, 0), (0, 1)], [(1, 0), (0, 0.6)], [(0.32, 0.38), (1, 1)]],
    "L": [[(0, 0), (0, 1), (1, 1)]],
    "M": [[(0, 1), (0, 0), (0.5, 0.55), (1, 0), (1, 1)]],
    "N": [[(0, 1), (0, 0), (1, 1), (1, 0)]],
    "O": [_O],
    "P": [_P],
    "R": [_P, [(0.45, 0.55), (1, 1)]],
    "S": [[(1, 0.1), (0.8, 0), (0.2, 0), (0, 0.15), (0, 0.36), (0.2, 0.5), (0.8, 0.5), (1, 0.64), (1, 0.85), (0.8, 1),
           (0.2, 1), (0, 0.9)]],
    "T": [[(0, 0), (1, 0)], [(0.5, 0), (0.5, 1)]],
    "U": [[(0, 0), (0, 0.8), (0.2, 1), (0.8, 1), (1, 0.8), (1, 0)]],
    "V": [[(0, 0), (0.5, 1), (1, 0)]],
    "W": [[(0, 0), (0.25, 1), (0.5, 0.4), (0.75, 1), (1, 0)]],
    "X": [[(0, 0), (1, 1)], [(1, 0), (0, 1)]],
    "Y": [[(0, 0), (0.5, 0.5), (1, 0)], [(0.5, 0.5), (0.5, 1)]],
    "Z": [[(0, 0), (1, 0), (0, 1), (1, 1)]],
    "0": [_O, [(0.85, 0.15), (0.15, 0.85)]],
    "1": [[(0.2, 0.2), (0.55, 0), (0.55, 1)], [(0.2, 1), (0.9, 1)]],
    "2": [[(0, 0.2), (0.2, 0), (0.8, 0), (1, 0.2), (1, 0.4), (0, 1), (1, 1)]],
    "3": [[(0, 0), (1, 0), (0.45, 0.42), (0.8, 0.42), (1, 0.62), (1, 0.85), (0.8, 1), (0.2, 1), (0, 0.88)]],
    "4": [[(0.75, 1), (0.75, 0), (0, 0.7), (1, 0.7)]],
    "5": [[(1, 0), (0.05, 0), (0, 0.45), (0.75, 0.45), (1, 0.62), (1, 0.85), (0.8, 1), (0.15, 1), (0, 0.9)]],
    "6": [[(0.9, 0.05), (0.6, 0), (0.2, 0), (0, 0.25), (0, 0.8), (0.2, 1), (0.8, 1), (1, 0.8), (1, 0.62), (0.8, 0.45),
           (0, 0.45)]],
    "7": [[(0, 0), (1, 0), (0.35, 1)]],
    "8": [[(0.2, 0.5), (0, 0.35), (0, 0.15), (0.2, 0), (0.8, 0), (1, 0.15), (1, 0.35), (0.8, 0.5), (0.2, 0.5),
           (0, 0.65), (0, 0.85), (0.2, 1), (0.8, 1), (1, 0.85), (1, 0.65), (0.8, 0.5)]],
    "9": [[(1, 0.45), (0.2, 0.45), (0, 0.3), (0, 0.15), (0.2, 0), (0.8, 0), (1, 0.2), (1, 0.8), (0.8, 1), (0.3, 1)]],
    "-": [[(0.15, 0.5), (0.85, 0.5)]],
    ".": [[(0.45, 0.92), (0.55, 0.92), (0.55, 1), (0.45, 1), (0.45, 0.92)]],
    "/": [[(0.9, 0), (0.1, 1)]],
}


def text_width(s, h):
    return sum((0.55 * h if ch == " " else 0.82 * h) for ch in s) - 0.2 * h


def draw_text(dr, s, x, y, h, width=2, fill=255):
    """Upper-case text, top-left at (x, y), cap height h (px)."""
    gw = 0.62 * h
    for ch in s:
        if ch == " ":
            x += 0.55 * h
            continue
        for line in GLYPHS.get(ch, []):
            dr.line([(x + px * gw, y + py * h) for px, py in line], fill=fill, width=width, joint="curve")
        x += 0.82 * h


def draw_arrow(dr, x, y, size, direction, width=3, fill=255):
    """An arrow centred at (x, y): W, E, N, S."""
    d = {"W": (-1, 0), "E": (1, 0), "N": (0, -1), "S": (0, 1)}[direction]
    tip = (x + d[0] * size / 2, y + d[1] * size / 2)
    tail = (x - d[0] * size / 2, y - d[1] * size / 2)
    p = (-d[1], d[0])
    dr.line([tail, tip], fill=fill, width=width)
    dr.line([(tip[0] - d[0] * size * 0.35 + p[0] * size * 0.3, tip[1] - d[1] * size * 0.35 + p[1] * size * 0.3), tip,
             (tip[0] - d[0] * size * 0.35 - p[0] * size * 0.3, tip[1] - d[1] * size * 0.35 - p[1] * size * 0.3)],
            fill=fill, width=width, joint="curve")


def make_labels():
    """The labels atlas: range cards, door signs, direction / range signs,
    the 'you are here' dot, two floor plans (current and an old revision)."""
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import filing_layout as FL
    W = 1024
    S = 2                                        # drawn at twice the size, then halved (antialiased)
    ink = Image.new("L", (W * S, W * S), 0)      # 255 = ink
    dr = ImageDraw.Draw(ink)
    base = np.full((W, W, 3), 0.80) * np.array([1.0, 0.995, 0.975])     # card stock / sign face (linear)
    paint = []                                   # (rect, linear colour) background fills
    at = FL.atlas()

    def R(key):
        x, y, w, h = at[key]
        return x * S, y * S, w * S, h * S

    # range cards: "1A01"
    k = 0
    for bk in FL.BANKS:
        for i in range(bk["n"]):
            x, y, w, h = R("card:%d" % k)
            t = bk["label"] + "%02d" % (i + 1)
            hh = 17 * S
            draw_text(dr, t, x + (w - text_width(t, hh)) / 2, y + 12 * S, hh, width=3 * S)
            dr.rectangle([x, y, x + w - 1, y + 2 * S], fill=170)
            dr.rectangle([x, y, x + 2 * S, y + h - 1], fill=170)
            k += 1
    # door signs: white letters on a dark green-grey panel (as a building's
    # room signs), a rule under them
    for n in FL.DOOR_SIGNS:
        x, y, w, h = at["door:" + n]
        paint.append(((x, y, w, h), (0.035, 0.05, 0.045)))
        x, y, w, h = R("door:" + n)
        if n == "notice":
            for li, t in enumerate(("KEEP CLEAR OF MOVING", "SHELVING. DO NOT ENTER", "AN AISLE THAT IS CLOSING")):
                hh = 11 * S
                draw_text(dr, t, x + (w - text_width(t, hh)) / 2, y + (6 + li * 19) * S, hh, width=2 * S)
            continue
        k = h / (64 * S)                         # (the 13th sign's slot is smaller, the same shape)
        hh = (30 * S if len(n) <= 8 else 23 * S) * k
        draw_text(dr, n, x + (w - text_width(n, hh)) / 2, y + (h - hh) / 2, hh, width=max(2, round(4 * S * k)))
    # direction and range signs
    for n in FL.WIDE_SIGNS:
        x, y, w, h = at[n]
        paint.append(((x, y, w, h), (0.035, 0.05, 0.045) if n.startswith("range") else (0.02, 0.12, 0.05)))
        x, y, w, h = R(n)
        if n.startswith("arrow"):
            _, t, d = n.split(":")
            hh = 34 * S
            tw = text_width(t, hh)
            if d == "W":
                draw_arrow(dr, x + 40 * S, y + h / 2, 52 * S, "W", width=6 * S)
                draw_text(dr, t, x + 80 * S, y + (h - hh) / 2, hh, width=5 * S)
            elif d == "E":
                draw_text(dr, t, x + 18 * S, y + (h - hh) / 2, hh, width=5 * S)
                draw_arrow(dr, x + 36 * S + tw, y + h / 2, 52 * S, "E", width=6 * S)
            else:
                draw_arrow(dr, x + 36 * S, y + h / 2, 56 * S, d, width=6 * S)
                draw_text(dr, t, x + 74 * S, y + (h - hh) / 2, hh, width=5 * S)
        else:
            cid = n.split(":")[1]
            name = FL.CELLS[cid]["name"]
            draw_text(dr, name, x + 14 * S, y + 10 * S, 28 * S, width=4 * S)
            lines = ["%s 01-%02d" % (bk["label"], bk["n"]) for bk in FL.BANKS if bk["cell"] == cid]
            draw_text(dr, "RANGES " + "  ".join(lines), x + 14 * S, y + 52 * S, 13 * S, width=2 * S)
    # the dot
    x, y, w, h = R("dot")
    dr.ellipse([x + 2 * S, y + 2 * S, x + w - 2 * S, y + h - 2 * S], fill=255)
    # floor plans
    pw = FL.PLAN_WORLD
    px = FL.PLAN_PX

    def plan(key, old):
        ox, oy, ow, oh = at[key]
        paint.append(((ox, oy, ow, oh), (0.78, 0.78, 0.74)))
        sx = px[2] / (pw[2] - pw[0])
        sy = px[3] / (pw[3] - pw[1])
        s = min(sx, sy)

        def P(xw, yw):
            return ((ox + px[0] + (xw - pw[0]) * s) * S, (oy + px[1] + px[3] - (yw - pw[1]) * s) * S)
        cells = dict(FL.CELLS)
        if old:
            cells = {k: v for k, v in cells.items() if k != "C3"}
        for cid, c in cells.items():
            x0, y0, x1, y1 = c["rect"]
            a, b = P(x0, y1), P(x1, y0)
            dr.rectangle([a[0], a[1], b[0], b[1]], outline=255, width=3 * S)
            nm = c["name"]
            hh = 7 * S if c["kind"] != "corridor" else 5 * S
            cx, cy = (a[0] + b[0]) / 2, (a[1] + b[1]) / 2
            if c["kind"] == "corridor" and c["ax"] == [0, 1]:
                cy -= 30 * S
            draw_text(dr, nm, cx - text_width(nm, hh) / 2, cy - hh / 2, hh, width=S + 1)
        for bk in FL.BANKS:
            if old and bk["cell"] == "R5":
                pass
            g = FL.bank_geom(bk)
            for u in (g["uL"], g["uR"]):
                p0, p1 = P(*FL.to_world(bk, u, 0)), P(*FL.to_world(bk, u, g["L"]))
                dr.line([p0, p1], fill=150, width=S)
            q = [P(*FL.to_world(bk, uu, vv)) for uu, vv in ((g["uL"], 0), (g["uR"], 0), (g["uR"], g["L"]),
                                                             (g["uL"], g["L"]))]
            dr.line(q + [q[0]], fill=150, width=S)
        for d in FL.DOORS:
            if old and (d["a"] == "C3" or d["b"] == "C3" or d["kind"] == "gated"):
                continue
            a, b = FL.door_span(d)
            pa, pb = P(*a), P(*b)
            if d["kind"] in ("door", "gated"):
                dr.line([pa, pb], fill=0, width=5 * S)
        # the stair doors, marked on the wall: STAIR 1 (corridor A's west end)
        # and, on the current revision only, STAIR 2 (corridor B's north end)
        stairs = [("STAIR 1", FL.door_span(FL.DOORS[[d["id"] for d in FL.DOORS].index("stair1")]), "w")]
        if not old:
            stairs.append(("STAIR 2", FL.door_span(FL.DOORS[[d["id"] for d in FL.DOORS].index("stair")]), "n"))
        for t, (a, b), side in stairs:
            pa, pb = P(*a), P(*b)
            dr.line([pa, pb], fill=255, width=4 * S)
            hh = 6 * S
            if side == "w":
                draw_text(dr, t, pa[0] + 5 * S, (pa[1] + pb[1]) / 2 + 7 * S, hh, width=S + 1)
            else:
                draw_text(dr, t, (pa[0] + pb[0]) / 2 - text_width(t, hh) - 4 * S, pa[1] + 6 * S, hh, width=S + 1)
        if old:
            # the old revision: Bay 4's doors further west, and the exit at the stair
            for x in (14.4, 20.5):
                pa, pb = P(x - 0.45, FL.C1Y1 + 0.1), P(x + 0.45, FL.C1Y1 + 0.1)
                dr.line([pa, pb], fill=0, width=5 * S)
            ex = P(-4.3, (FL.C1Y0 + FL.C1Y1) / 2)
        else:
            ex = P(FL.EXIT[0], FL.EXIT[1] + 0.1)
        draw_text(dr, "EXIT", ex[0] - text_width("EXIT", 9 * S) / 2, ex[1] - 14 * S, 9 * S, width=2 * S)
        dr.ellipse([ex[0] - 4 * S, ex[1] - 4 * S, ex[0] + 4 * S, ex[1] + 4 * S], fill=255)
        t = "STORAGE FLOOR 1   REV C" if not old else "STORAGE FLOOR 1   REV A"
        draw_text(dr, t, (ox + 10) * S, (oy + 10) * S, 11 * S, width=2 * S)
        draw_text(dr, "YOU ARE HERE", (ox + ow - 120) * S, (oy + oh - 20) * S, 8 * S, width=S + 1)
        dr.ellipse([(ox + ow - 134) * S, (oy + oh - 21) * S, (ox + ow - 124) * S, (oy + oh - 11) * S], fill=255)
        return P

    plan("plan", False)
    plan("plan_old", True)
    m = np.asarray(ink.resize((W, W), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.35)), np.float64) / 255.0
    img = base.copy()
    for (x, y, w, h), col in paint:
        img[y:y + h, x:x + w] = col
    # ink: dark on cards and plans, white on the dark signs; the dot and the
    # plans' exits red
    dark = np.zeros((W, W), bool)
    for (x, y, w, h), col in paint:
        if sum(col) < 0.5:
            dark[y:y + h, x:x + w] = True
    inkc = np.where(dark[:, :, None], np.array([0.78, 0.78, 0.75]), np.array([0.03, 0.03, 0.035]))
    img = img * (1 - m[:, :, None]) + inkc * m[:, :, None]
    x, y, w, h = at["dot"]
    img[y:y + h, x:x + w] = img[y:y + h, x:x + w] * (1 - m[y:y + h, x:x + w, None]) + \
        np.array([0.6, 0.02, 0.02]) * m[y:y + h, x:x + w, None]
    # grime on the old plan, a little on everything
    rng = np.random.default_rng(1104)
    n = rng.standard_normal((32, 32))
    n = np.array(Image.fromarray(((n - n.min()) / np.ptp(n) * 255).astype(np.uint8)).resize((W, W), Image.BICUBIC),
                 np.float64) / 255.0
    img *= (1.0 - 0.06 * n)[:, :, None]
    ox, oy, ow, oh = at["plan_old"]
    img[oy:oy + oh, ox:ox + ow] *= np.array([1.0, 0.96, 0.84]) * (1.0 - 0.12 * n[oy:oy + oh, ox:ox + ow, None])
    dst = os.path.join(OUT, "textures")
    os.makedirs(dst, exist_ok=True)
    out = np.clip(np.power(np.clip(img, 0, 1), 1 / 2.2) * 255 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(out).save(os.path.join(dst, "labels_diff.png"))
    write_import(os.path.join(dst, "labels_diff.png"))
    print("labels done")


if "--labels" in sys.argv:
    make_labels()
    sys.exit(0)


if "--textures" in sys.argv:
    make_textures(sys.argv[sys.argv.index("--textures") + 1])
    sys.exit(0)


# =============================================================== sounds ===
# Real recordings were not available for this level (see SPEC.md), so every
# sound is synthesised here as a documented placeholder: noise shaped in the
# frequency domain with smooth log-frequency bands (nothing resonant, no
# sine tones in any impact), loops periodic by construction.

SR = 44100


def make_sounds(dst):
    import subprocess
    import wave
    import numpy as np
    os.makedirs(dst, exist_ok=True)
    rs = np.random.default_rng(1102)

    def band(f, lo, hi):
        f = np.maximum(f, 1.0)
        c = math.sqrt(lo * hi)
        w = max(math.log(hi / lo) / 2.0, 0.05)
        return np.exp(-0.5 * (np.log(f / c) / w) ** 2)

    def loop_noise(n, shape):
        f = np.fft.rfftfreq(n, 1.0 / SR)
        spec = shape(f) * np.exp(2j * math.pi * rs.random(f.size))
        spec[0] = 0
        return np.fft.irfft(spec, n)

    def filt(x, shape):
        n = 1 << int(math.ceil(math.log2(len(x) + 4096)))
        f = np.fft.rfftfreq(n, 1.0 / SR)
        return np.fft.irfft(np.fft.rfft(x, n) * shape(f), n)[:len(x)]

    def noise(sec):
        return rs.standard_normal(int(sec * SR))

    def env(n, a, d, sustain=0.0):
        t = np.arange(n) / SR
        return np.minimum(t / max(a, 1e-4), 1.0) * (sustain + (1 - sustain) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4)))

    def burst(sec, lo, hi, a, d, gain=1.0):
        x = filt(noise(sec), lambda f: band(f, lo, hi))
        return x / (np.abs(x).max() + 1e-9) * env(len(x), a, d) * gain

    def room(x, t60=0.8, wet=0.3, lp=3500.0):
        n = int(t60 * SR)
        ir = rs.standard_normal(n) * np.exp(-6.9 * np.arange(n) / n)
        ir = filt(ir, lambda f: 1.0 / (1.0 + (f / lp) ** 2))
        ir /= np.sqrt((ir ** 2).sum())
        y = np.convolve(x, ir)[:len(x) + n]
        out = np.zeros(len(y))
        out[:len(x)] = x * (1 - wet)
        return out + y * wet

    def place(d, x, at):
        i = int(at * SR)
        j = min(len(d), i + len(x))
        if j > i:
            d[i:j] += x[:j - i]

    def hum(n, f0=120.0, amps=(1.0, 0.5, 0.28, 0.16, 0.08, 0.05)):
        t = np.arange(n) / SR
        return sum(a * np.sin(2 * math.pi * f0 * (k + 1) * t + rs.random() * 6.28) for k, a in enumerate(amps))

    def save(name, x, loop=False):
        x = np.asarray(x, np.float64)
        if loop:
            x = x / (np.sqrt((x ** 2).mean()) + 1e-9) * 10 ** (-20 / 20)
        else:
            x = x / (np.abs(x).max() + 1e-9) * 10 ** (-3 / 20)
            fade = min(len(x), int(0.01 * SR))
            x[-fade:] *= np.linspace(1, 0, fade)
        x = np.clip(x, -1, 1)
        wav = os.path.join(dst, name + ".wav")
        with wave.open(wav, "wb") as w:
            w.setnchannels(1)
            w.setsampwidth(2)
            w.setframerate(SR)
            w.writeframes((x * 32767).astype("<i2").tobytes())
        subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-c:a", "libvorbis", "-q:a", "4", "-ac", "1",
                        os.path.join(dst, name + ".ogg")], check=True)
        os.remove(wav)
        with open(os.path.join(dst, name + ".ogg.import"), "w") as f:
            f.write('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\n\n'
                    f'loop={"true" if loop else "false"}\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n')

    # The building's air: the records room's dedicated air handler (it runs
    # all night for the humidity), broadband, low weighted.
    n = 12 * SR
    save("hvac_loop", loop_noise(n, lambda f: 1.0 / np.sqrt(np.maximum(f, 20) / 50.0) / (1.0 + (f / 600.0) ** 2)
                                 + 0.7 * band(f, 30, 80)), loop=True)
    # A strip's ballast hum (120 Hz magnetostriction and harmonics, a little
    # buzz), as heard under it.
    n = 8 * SR
    t = np.arange(n) / SR
    h = hum(n) * (1.0 + 0.06 * np.sin(2 * math.pi * t / 4.0))
    bz = loop_noise(n, lambda f: band(f, 1500, 6000) * 0.6 + band(f, 100, 400) * 0.4)
    bz *= 1.0 + 0.6 * np.sin(2 * math.pi * 120 * t) ** 2
    save("hum_loop", h * 0.5 + bz / np.abs(bz).max() * 0.3, loop=True)
    # Rail rumble: steel wheels (5 in, cast iron) on flush steel rails under
    # ~3.8 t a carriage: a low roar, the floor carrying it, grit, and the
    # wheels' once-a-turn flat (periodic in 6 s).
    n = 6 * SR
    t = np.arange(n) / SR
    low = loop_noise(n, lambda f: band(f, 22, 140) * 1.0 + band(f, 140, 500) * 0.35 + band(f, 900, 4000) * 0.06)
    low /= np.abs(low).max()
    grit = loop_noise(n, lambda f: band(f, 1200, 6000))
    grit /= np.abs(grit).max()
    am = 1.0 + 0.25 * np.sin(2 * math.pi * t * 2.0 / 6.0 * 3) + 0.15 * np.sin(2 * math.pi * t * 5.0)
    save("rumble_loop", low * am + grit * 0.08 * (1.0 + np.sin(2 * math.pi * t * 7.0) ** 8), loop=True)
    # The drive: chain and sprockets under the end panel, the handle's
    # hub: a train of small ticks (noise bursts) and a whir (4 s, 52 ticks).
    n = 4 * SR
    d = np.zeros(n)
    for k in range(52):
        at = k * 4.0 / 52 + rs.uniform(-0.004, 0.004)
        place(d, burst(0.02, 2000, 7000, 0.0003, 0.003, rs.uniform(0.5, 1.0)), max(at, 0))
        place(d, burst(0.03, 400, 1400, 0.001, 0.008, 0.4), max(at + 0.002, 0))
    wh = loop_noise(n, lambda f: band(f, 300, 1200))
    d = d / np.abs(d).max() + wh / np.abs(wh).max() * 0.25
    save("drive_loop", d, loop=True)
    # End stop: a carriage meeting its neighbour (bumpers) under load: the
    # thud through the floor, the steel knock, every carton on the range
    # jumping a little and settling.
    for i in range(2):
        L = 1.6
        x = np.zeros(int(L * SR))
        place(x, burst(0.8, 28, 160, 0.003, 0.22 + 0.06 * i, 1.6), 0.0)
        place(x, burst(0.15, 350, 2200, 0.0008, 0.035, 0.9), 0.002)
        place(x, burst(0.08, 1800, 6000, 0.0004, 0.01, 0.35), 0.004)
        for k in range(40):
            at = 0.01 + rs.exponential(0.12)
            place(x, burst(0.05, 500, 3500, 0.001, rs.uniform(0.004, 0.015), rs.uniform(0.05, 0.25)), min(at, L - 0.06))
        save(f"clunk_{i + 1}", room(x, 0.9, 0.3, 3000.0))
    # The warning: the frames taking the strain before a range moves, a
    # creak (noise through a slowly falling band an octave wide) and ticks.
    for i in range(2):
        L = 1.4
        n = int(L * SR)
        x = np.zeros(n)
        src = noise(L)
        seg = 2048
        out = np.zeros(n + seg)
        win = np.hanning(seg)
        for s0 in range(0, n - seg, seg // 2):
            c = 520 - 300 * (s0 / n) + 60 * i
            f = np.fft.rfftfreq(seg, 1.0 / SR)
            blk = np.fft.irfft(np.fft.rfft(src[s0:s0 + seg] * win) * band(f, c / 1.5, c * 1.5), seg)
            out[s0:s0 + seg] += blk
        x += out[:n] / (np.abs(out).max() + 1e-9) * env(n, 0.25, 0.6, 0.3) * 0.7
        for k in range(6):
            place(x, burst(0.02, 1500, 5000, 0.0003, 0.004, 0.4), rs.uniform(0.05, 1.2))
        place(x, burst(0.5, 30, 120, 0.05, 0.25, 0.5), 0.1)
        save(f"creak_{i + 1}", room(x, 0.8, 0.35))
    # Cartons shifting on a shelf: cardboard scuff and a soft thump.
    for i in range(3):
        L = 0.6
        x = np.zeros(int(L * SR))
        sc = burst(0.25 + 0.1 * i, 400, 4000, 0.03, 0.08, 0.6)
        place(x, sc, 0.0)
        place(x, burst(0.2, 70, 300, 0.002, 0.04, 1.0), 0.12 + 0.05 * i)
        place(x, burst(0.05, 800, 3000, 0.001, 0.01, 0.3), 0.125 + 0.05 * i)
        save(f"carton_{i + 1}", room(x, 0.6, 0.25))
    # Paper sliding off a carton and fluttering down; landing.
    for i in range(2):
        L = 1.4
        n = int(L * SR)
        x = filt(noise(L), lambda f: band(f, 1500, 9000) + 0.3 * band(f, 400, 1500))
        t = np.arange(n) / SR
        fl = 0.35 + 0.65 * np.abs(np.sin(2 * math.pi * (14 + 5 * i) * t + 3 * np.sin(2 * math.pi * 1.3 * t)))
        e = np.minimum(t / 0.04, 1) * np.exp(-np.maximum(t - 0.25, 0) / 0.5)
        y = x / np.abs(x).max() * fl * e
        place(y, burst(0.12, 300, 3000, 0.002, 0.03, 0.5), L - 0.2)
        save(f"paper_{i + 1}", y)
    # The occupancy sensor's relay and a programmed-start ballast: ~1.1 s of
    # cathode preheat (a faint buzz), the lamps striking (ticks, the hum
    # stepping up).
    x = np.zeros(int(0.4 * SR))
    place(x, burst(0.06, 900, 3500, 0.0006, 0.012, 1.0), 0.0)
    place(x, burst(0.2, 60, 220, 0.002, 0.05, 1.2), 0.001)
    place(x, burst(0.05, 1500, 5000, 0.0005, 0.008, 0.5), 0.02)
    save("relay", room(x, 0.5, 0.3))
    L = 2.2
    x = np.zeros(int(L * SR))
    pre = filt(noise(1.15), lambda f: band(f, 800, 4000)) * np.linspace(0.05, 0.4, int(1.15 * SR)) ** 1.5
    place(x, pre / np.abs(pre).max() * 0.25, 0.0)
    for k, at in enumerate((1.12, 1.2)):
        place(x, burst(0.03, 2000, 8000, 0.0004, 0.003, 0.8), at)
        hh = hum(int((L - at) * SR)) * env(int((L - at) * SR), 0.01, 0.35, 0.25) * 0.12
        place(x, hh, at)
    save("ballast_start", x)
    # Aisle light (LED bar) switching off: a driver click.
    x = np.zeros(int(0.15 * SR))
    place(x, burst(0.03, 2500, 7000, 0.0004, 0.004, 0.8), 0.0)
    place(x, burst(0.06, 200, 800, 0.001, 0.015, 0.4), 0.001)
    save("led_click", x)
    # A records cart's steel shelves jolted: knocks and rattle (noise bands).
    for i in range(2):
        L = 0.9
        x = np.zeros(int(L * SR))
        place(x, burst(0.3, 120, 600, 0.001, 0.05, 1.0), 0.0)
        for k in range(14):
            place(x, burst(0.04, 900, 4500, 0.0005, rs.uniform(0.006, 0.02), rs.uniform(0.2, 0.7)),
                  rs.exponential(0.12))
        save(f"cart_{i + 1}", room(x, 0.6, 0.25))
    # Caught between two ranges: the drive grinding on, cartons bursting,
    # the bumpers meeting through you; dull, heavy, no ring.
    L = 3.0
    x = np.zeros(int(L * SR))
    gr = filt(noise(2.4), lambda f: band(f, 40, 300) + 0.4 * band(f, 300, 1500))
    place(x, gr / np.abs(gr).max() * env(len(gr), 0.4, 0.8, 0.5) * 0.8, 0.0)
    for k in range(18):
        place(x, burst(0.12, 300, 3000, 0.002, rs.uniform(0.02, 0.06), rs.uniform(0.3, 0.9)), rs.uniform(0.2, 1.8))
    place(x, burst(0.9, 25, 120, 0.004, 0.35, 2.0), 1.6)
    place(x, burst(0.2, 200, 1200, 0.002, 0.06, 1.0), 1.602)
    save("crush", room(x, 1.0, 0.3, 2500.0))
    # Knocking from inside shut shelving: knuckles on the inner side of a
    # steel end panel, through cartons: a muffled thud (low noise band), a
    # dull tap of the sheet steel, two or three to a knock; heard through a
    # carriage's worth of cardboard, so dark (no highs).
    for i in range(3):
        L = 1.3
        x = np.zeros(int(L * SR))
        at = 0.0
        for k in range(2 + (i % 2)):
            place(x, burst(0.25, 60, 260, 0.002, 0.05 + 0.01 * k, 1.0), at)
            place(x, burst(0.08, 300, 1100, 0.0008, 0.018, 0.45), at + 0.001)
            at += rs.uniform(0.17, 0.26)
        y = filt(x, lambda f: 1.0 / (1.0 + (f / 1400.0) ** 2))
        save(f"knock_{i + 1}", room(y, 0.7, 0.35, 1800.0))
    print("sounds done")


if "--sounds" in sys.argv:
    make_sounds(os.path.join(OUT, "audio"))
    sys.exit(0)


# ================================================================= kit ===
# One kit per cell of the floor plan (tools/blender/levels/filing_layout.py):
# floor, block walls with their fire-door openings, the slab, strips,
# sprinklers, rails under the shelving, fittings. Each is baked on its own
# (colour: the always-on lamps; groups: its four sensor zones), and its
# untextured materials are merged into one vertex-coloured "paint" surface
# so a kit costs about four draw calls.
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, ".."))
sys.path.insert(0, HERE)
import bpy  # noqa: E402
import numpy as np  # noqa: E402
import level_kit as K  # noqa: E402
import filing_layout as FL  # noqa: E402

TEXTURED = ("concrete_floor", "cmu_paint", "slab_paint", "exit_face", "sorter_wood")
RAIL_STEP = 1.883


def declare_materials():
    K.material("concrete_floor", (0.30, 0.295, 0.28), rough=0.35)
    K.material("rail", (0.30, 0.30, 0.30), rough=0.35, metal=0.8)
    K.material("rail_gap", (0.03, 0.03, 0.03), rough=0.9)
    K.material("cmu_paint", (0.60, 0.59, 0.555), rough=0.9)
    K.material("slab_paint", (0.72, 0.72, 0.70), rough=0.95)
    K.material("base", (0.04, 0.04, 0.04), rough=0.8)
    K.material("strip_body", (0.80, 0.80, 0.78), rough=0.5)
    K.material("rod", (0.45, 0.46, 0.47), rough=0.5, metal=0.6)
    K.material("pipe_red", (0.38, 0.03, 0.02), rough=0.5)
    K.material("sprinkler", (0.70, 0.66, 0.50), rough=0.35, metal=0.8)
    K.material("galv", (0.45, 0.46, 0.47), rough=0.5, metal=0.6)
    K.material("grille", (0.80, 0.80, 0.78), rough=0.5)
    K.material("grille_dark", (0.02, 0.02, 0.02), rough=0.9)
    K.material("door_steel", (0.28, 0.30, 0.30), rough=0.45)
    K.material("door_frame", (0.20, 0.20, 0.20), rough=0.45, metal=0.3)
    K.material("hardware", (0.55, 0.55, 0.53), rough=0.3, metal=0.9)
    K.material("exit_housing", (0.80, 0.80, 0.78), rough=0.5)
    K.material("exit_face", (1.0, 0.22, 0.12), emit=EXIT_EMIT)
    K.material("sensor", (0.85, 0.85, 0.82), rough=0.4)
    K.material("extinguisher", (0.42, 0.02, 0.02), rough=0.3)
    K.material("black", (0.03, 0.03, 0.03), rough=0.6)
    K.material("logger", (0.75, 0.75, 0.72), rough=0.5)
    K.material("stool", (0.20, 0.30, 0.42), rough=0.45)
    K.material("rubber", (0.03, 0.03, 0.03), rough=0.9)
    K.material("laminate", (0.52, 0.49, 0.42), rough=0.4)
    K.material("steel_grey", (0.33, 0.34, 0.35), rough=0.45)
    K.material("sorter_wood", (0.33, 0.22, 0.13), rough=0.6)
    K.material("monitor", (0.52, 0.50, 0.45), rough=0.5)
    K.material("screen", (0.015, 0.02, 0.022), rough=0.15)
    K.material("bucket", (0.45, 0.33, 0.04), rough=0.5)
    K.material("magnet", (0.15, 0.15, 0.15), rough=0.5)
    for g in range(4):
        K.material(f"lamp_g{g}", (1.0, 1.0, 1.0), emit=TUBE_EMIT, group=g)
    K.material("lamp_night", (1.0, 1.0, 1.0), emit=TUBE_EMIT)


# --------------------------------------------------------------- helpers ---

def rect(b, x0, y0, x1, y1, z, m, up=True):
    c = ((x0 + x1) / 2, (y0 + y1) / 2, z + (1 if up else -1))
    b.oquad([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], m, c)


def strip(b, x, y, m, along_y=False):
    """A 4 ft two-lamp T8 strip hung on two rods: the white channel, two
    tubes under it; along x (or y)."""
    if not along_y:
        b.box((1.22, 0.11, 0.06), (x, y, STRIP_Z + 0.05), "strip_body", bevel=0.006)
        for s in (-1, 1):
            b.cyl(TUBE_R, TUBE_R, TUBE_L, (x, y + s * 0.028, STRIP_Z + 0.008), m, segs=8, rot=(0, math.pi / 2, 0))
            b.cyl(0.006, 0.006, CEIL - STRIP_Z - 0.08, (x + s * 0.45, y, (CEIL + STRIP_Z + 0.08) / 2), "rod", segs=6)
            b.box((0.03, 0.025, 0.02), (x + s * 0.6, y + s * 0.028, STRIP_Z + 0.01), "strip_body")
    else:
        b.box((0.11, 1.22, 0.06), (x, y, STRIP_Z + 0.05), "strip_body", bevel=0.006)
        for s in (-1, 1):
            b.cyl(TUBE_R, TUBE_R, TUBE_L, (x + s * 0.028, y, STRIP_Z + 0.008), m, segs=8, rot=(math.pi / 2, 0, 0))
            b.cyl(0.006, 0.006, CEIL - STRIP_Z - 0.08, (x, y + s * 0.45, (CEIL + STRIP_Z + 0.08) / 2), "rod", segs=6)
            b.box((0.025, 0.03, 0.02), (x + s * 0.028, y + s * 0.6, STRIP_Z + 0.01), "strip_body")


def sides(cid):
    """The cell's four walls: (name, axis the wall runs along, fixed coord of
    its face, from, to, inward normal)."""
    x0, y0, x1, y1 = FL.CELLS[cid]["rect"]
    return [("s", "x", y0, x0, x1, (0, 1)), ("n", "x", y1, x0, x1, (0, -1)),
            ("w", "y", x0, y0, y1, (1, 0)), ("e", "y", x1, y0, y1, (-1, 0))]


def doors_on(cid, side):
    name, axis, at, s0, s1, nrm = side
    centre = at - (nrm[0] + nrm[1]) * FL.WALL_T / 2       # the wall's centre line
    out = []
    for d in FL.DOORS:
        if d["axis"] != axis or cid not in (d["a"], d["b"]):
            continue
        cx, cy = d["c"]
        along, across = (cx, cy) if axis == "x" else (cy, cx)
        if abs(across - centre) < 0.06 and s0 - 0.01 <= along <= s1 + 0.01:
            out.append((along, d))
    return sorted(out, key=lambda t: t[0])


def wall_quad(b, side, a0, a1, z0, z1, m):
    name, axis, at, s0, s1, nrm = side
    if axis == "x":
        pts = [(a0, at, z0), (a1, at, z0), (a1, at, z1), (a0, at, z1)]
        tow = ((a0 + a1) / 2, at + nrm[1], (z0 + z1) / 2)
    else:
        pts = [(at, a0, z0), (at, a1, z0), (at, a1, z1), (at, a0, z1)]
        tow = (at + nrm[0], (a0 + a1) / 2, (z0 + z1) / 2)
    b.oquad(pts, m, tow)


def wbox(b, side, a, off, z, size_along, size_off, size_z, m):
    """A box against the wall: `a` along it, `off` out from its face into the
    room, z its centre height."""
    name, axis, at, s0, s1, nrm = side
    if axis == "x":
        b.box((size_along, size_off, size_z), (a, at + nrm[1] * off, z), m)
    else:
        b.box((size_off, size_along, size_z), (at + nrm[0] * off, a, z), m)


def wcol(kit, side, a, off, z, size_along, size_off, size_z):
    name, axis, at, s0, s1, nrm = side
    if axis == "x":
        kit.col((size_along, size_off, size_z), (a, at + nrm[1] * off, z))
    else:
        kit.col((size_off, size_along, size_z), (at + nrm[0] * off, a, z))


# ----------------------------------------------------------------- walls ---

def walls(kit, cid):
    b = kit.b
    T = FL.WALL_T
    for side in sides(cid):
        name, axis, at, s0, s1, nrm = side
        ds = doors_on(cid, side)
        opens = [(a - d["w"] / 2, a + d["w"] / 2, d) for a, d in ds if d["kind"] in ("door", "gated")]
        cuts = [s0] + [v for o in opens for v in o[:2]] + [s1]
        for i in range(0, len(cuts), 2):
            a0, a1 = cuts[i], cuts[i + 1]
            if a1 - a0 > 0.001:
                wall_quad(b, side, a0, a1, 0.0, CEIL, "cmu_paint")
                wbox(b, side, (a0 + a1) / 2, 0.003, 0.0508, a1 - a0, 0.006, 0.1016, "base")
            # collision: the wall's full thickness, past the corners
            e0 = a0 - (T if i == 0 else 0.0)
            e1 = a1 + (T if i + 2 == len(cuts) else 0.0)
            if e1 - e0 > 0.001:
                wcol(kit, side, (e0 + e1) / 2, -T / 2, CEIL / 2, e1 - e0, T, CEIL + 0.4)
        for o0, o1, d in opens:
            wall_quad(b, side, o0, o1, DOOR_H, CEIL, "cmu_paint")
            frame_trim(b, side, o0, o1)
            if d["a"] == cid:
                jambs(b, side, o0, o1)
            if d.get("leaf_cell") == cid:
                held_leaf(kit, side, d)
        for a, d in ds:
            if d["kind"] in ("arrive", "locked"):
                shut_door(b, side, a, d)
            elif d["kind"] == "exit":
                wbox(b, side, a, 0.03, 2.42, 0.33, 0.06, 0.2, "exit_housing")
                wbox(b, side, a, 0.062, 2.42, 0.30, 0.004, 0.115, "exit_face")


def frame_trim(b, side, o0, o1):
    f = 2 * IN
    wbox(b, side, o0 - f / 2, 0.006, (DOOR_H + f) / 2, f, 0.012, DOOR_H + f, "door_frame")
    wbox(b, side, o1 + f / 2, 0.006, (DOOR_H + f) / 2, f, 0.012, DOOR_H + f, "door_frame")
    wbox(b, side, (o0 + o1) / 2, 0.006, DOOR_H + f / 2, o1 - o0 + 2 * f, 0.012, f, "door_frame")


def jambs(b, side, o0, o1):
    """The opening's reveal through the wall (hollow-metal frame) and its floor."""
    name, axis, at, s0, s1, nrm = side
    T = FL.WALL_T
    if axis == "x":
        yo = at - nrm[1] * T          # the far face
        ya, yb = sorted((at, yo))
        b.oquad([(o0, ya, 0), (o0, yb, 0), (o0, yb, DOOR_H), (o0, ya, DOOR_H)], "door_frame", (o0 + 1, at, 1))
        b.oquad([(o1, ya, 0), (o1, yb, 0), (o1, yb, DOOR_H), (o1, ya, DOOR_H)], "door_frame", (o1 - 1, at, 1))
        rect(b, o0, ya, o1, yb, DOOR_H, "door_frame", up=False)
        rect(b, o0, ya, o1, yb, 0.0, "concrete_floor")
    else:
        xo = at - nrm[0] * T
        xa, xb = sorted((at, xo))
        b.oquad([(xa, o0, 0), (xb, o0, 0), (xb, o0, DOOR_H), (xa, o0, DOOR_H)], "door_frame", (at, o0 + 1, 1))
        b.oquad([(xa, o1, 0), (xb, o1, 0), (xb, o1, DOOR_H), (xa, o1, DOOR_H)], "door_frame", (at, o1 - 1, 1))
        rect(b, xa, o0, xb, o1, DOOR_H, "door_frame", up=False)
        rect(b, xa, o0, xb, o1, 0.0, "concrete_floor")


def held_leaf(kit, side, d):
    """The fire door swung right round against the wall beside the opening,
    held there by its magnet (it would close on an alarm); where: the
    layout's leaf_along."""
    b = kit.b
    r0, r1 = d["leaf_along"]
    o = d["c"][0] if side[1] == "x" else d["c"][1]
    w = r1 - r0
    a = (r0 + r1) / 2
    hinge_left = r0 > o            # the leaf is right of the opening: hinged at its left end
    wbox(b, side, a, 0.075, DOOR_H / 2, w - 0.006, 0.045, DOOR_H - 0.01, "door_steel")
    wbox(b, side, a, 0.1, 0.13, w - 0.05, 0.003, 0.25, "hardware")              # kick plate
    lever_a = r1 - 0.07 if hinge_left else r0 + 0.07
    wbox(b, side, lever_a, 0.12, 1.0, 0.13, 0.04, 0.025, "hardware")
    free_a = r1 - 0.12 if hinge_left else r0 + 0.12
    wbox(b, side, free_a, 0.07, DOOR_H - 0.25, 0.08, 0.14, 0.08, "magnet")       # the hold-open magnet
    wcol(kit, side, a, 0.075, DOOR_H / 2, w, 0.09, DOOR_H)


def shut_door(b, side, a, d):
    """A shut hollow-metal door in its frame (the way you came in; a locked
    stair, vault or janitor's door)."""
    w = d["w"]
    frame_trim(b, side, a - w / 2, a + w / 2)
    wbox(b, side, a, 0.008, DOOR_H / 2, w - 0.006, 0.016, DOOR_H - 0.006, "door_steel")
    wbox(b, side, a - w / 2 + 0.13, 0.035, 1.0, 0.13, 0.04, 0.025, "hardware")
    wbox(b, side, a - w / 2 + 0.07, 0.02, 1.0, 0.06, 0.03, 0.06, "hardware")
    wbox(b, side, a + 0.2, 0.04, DOOR_H - 0.1, 0.3, 0.05, 0.05, "hardware")        # closer
    wbox(b, side, a, 0.0175, 0.13, w - 0.05, 0.003, 0.25, "hardware")


# ---------------------------------------------------------------- lights ---

def lights(kit, cid):
    b = kit.b
    for r in FL.ROWS:
        if r["cell"] != cid:
            continue
        m = "lamp_night" if r["g"] < 0 else "lamp_g%d" % r["g"]
        along_y = abs(r["a"][1] - r["b"][1]) > 1e-6
        for i in range(r["n"]):
            t = (i + 0.5) / r["n"]
            strip(b, r["a"][0] + (r["b"][0] - r["a"][0]) * t, r["a"][1] + (r["b"][1] - r["a"][1]) * t, m, along_y)
    # an occupancy sensor (ceiling PIR) for each group zone
    for g, rects in FL.sensor_rects().get(cid, {}).items():
        x0, y0, x1, y1 = rects[0]
        b.cyl(0.055, 0.045, 0.03, ((x0 + x1) / 2 + 0.35, (y0 + y1) / 2 + 0.35, CEIL - 0.015), "sensor", segs=12)


def sprinklers(kit, cid):
    """Wet system: 1 in branch lines between the strip rows, pendent heads on
    a ~3 m grid, deflectors 2.82 m up (0.52 m over the top of storage)."""
    b = kit.b
    x0, y0, x1, y1 = FL.CELLS[cid]["rect"]
    zb = CEIL - 0.16
    rows = [r for r in FL.ROWS if r["cell"] == cid and r["g"] >= -1]
    along_x = FL.CELLS[cid]["ax"] == [1, 0]
    if FL.CELLS[cid]["kind"] == "corridor":
        lines = [((y0 + y1) / 2 - 0.45) if along_x else ((x0 + x1) / 2 - 0.45)]
    else:
        ps = sorted({round(r["a"][1] if along_x else r["a"][0], 3) for r in rows})
        lo, hi = (y0, y1) if along_x else (x0, x1)
        ps = [lo] + ps + [hi]
        lines = [(p + q) / 2 for p, q in zip(ps, ps[1:]) if q - p > 1.6]
    s0, s1 = (x0, x1) if along_x else (y0, y1)
    nh = max(1, int(round((s1 - s0) / 3.0)))
    for c in lines:
        if along_x:
            b.cyl(0.0167, 0.0167, s1 - s0 - 0.6, ((s0 + s1) / 2, c, zb), "pipe_red", segs=8, rot=(0, math.pi / 2, 0))
        else:
            b.cyl(0.0167, 0.0167, s1 - s0 - 0.6, (c, (s0 + s1) / 2, zb), "pipe_red", segs=8, rot=(math.pi / 2, 0, 0))
        for k in range(nh):
            s = s0 + (k + 0.5) * (s1 - s0) / nh
            x, y = (s, c) if along_x else (c, s)
            b.cyl(0.012, 0.012, zb - 2.86, (x, y, (zb + 2.86) / 2), "pipe_red", segs=6)
            b.cyl(0.011, 0.008, 0.03, (x, y, 2.845), "sprinkler", segs=8)
            b.cyl(0.021, 0.021, 0.003, (x, y, 2.825), "sprinkler", segs=12)
            b.box((0.004, 0.022, 0.03), (x, y, 2.84), "sprinkler")
        for k in range(max(1, nh - 1)):
            s = s0 + (k + 1.0) * (s1 - s0) / nh
            x, y = (s, c) if along_x else (c, s)
            b.box((0.01, 0.01, CEIL - zb), (x, y, (CEIL + zb) / 2), "rod")
    # the feed main along one wall, across the branch lines
    if len(lines) > 1:
        if along_x:
            xm = x1 - 0.35
            b.cyl(0.057, 0.057, y1 - y0 - 0.4, (xm, (y0 + y1) / 2, CEIL - 0.12), "pipe_red", segs=12,
                  rot=(math.pi / 2, 0, 0))
        else:
            ym = y1 - 0.35
            b.cyl(0.057, 0.057, x1 - x0 - 0.4, ((x0 + x1) / 2, ym, CEIL - 0.12), "pipe_red", segs=12,
                  rot=(0, math.pi / 2, 0))


def duct(kit, x0, x1, y):
    """A supply duct along x over a main aisle, galvanised, side grilles."""
    b = kit.b
    b.box((x1 - x0, 0.6, 0.3), ((x0 + x1) / 2, y, CEIL - 0.17), "galv")
    n = max(2, int((x1 - x0) / 3.6))
    for i in range(n):
        x = x0 + (i + 0.6) * (x1 - x0) / n
        b.box((0.5, 0.012, 0.18), (x, y - 0.306, CEIL - 0.17), "grille")
        b.box((0.46, 0.006, 0.14), (x, y - 0.312, CEIL - 0.17), "grille_dark")
    for i in range(n + 1):
        x = x0 + 0.3 + i * (x1 - x0 - 0.6) / n
        b.box((0.03, 0.66, 0.012), (x, y, CEIL - 0.33), "rod")
        for s in (-1, 1):
            b.box((0.01, 0.01, 0.34), (x, y + s * 0.33, CEIL - 0.17), "rod")


def rails(kit, cid):
    """Flush rails under each bank: a 2 in steel head in a channel cast into
    the slab, across the bank between its fixed units, every ~1.9 m."""
    b = kit.b
    for bk in FL.BANKS:
        if bk["cell"] != cid:
            continue
        g = FL.bank_geom(bk)
        L = g["L"]
        nr = max(2, int(round((L - 0.8) / RAIL_STEP)) + 1)
        u0, u1 = g["uL"] - 0.02, g["uR"] + 0.02
        ang = math.atan2(bk["eu"][1], bk["eu"][0])
        for k in range(nr):
            v = 0.40 + k * (L - 0.8) / (nr - 1)
            cx, cy = FL.to_world(bk, (u0 + u1) / 2, v)
            b.box((u1 - u0, 0.072, 0.0012), (cx, cy, 0.0006), "rail_gap", rot=(0, 0, ang))
            b.box((u1 - u0, 0.052, 0.002), (cx, cy, 0.001), "rail", rot=(0, 0, ang))


def extinguisher(b, x, y, face):
    """A 10 lb extinguisher on its wall hook (face: direction into the room)."""
    fx, fy = face
    b.cyl(0.075, 0.075, 0.42, (x + fx * 0.09, y + fy * 0.09, 1.0), "extinguisher", segs=14)
    b.cyl(0.03, 0.03, 0.08, (x + fx * 0.09, y + fy * 0.09, 1.25), "black", segs=8)
    b.box((0.06 if fy == 0 else 0.04, 0.04 if fy == 0 else 0.06, 0.12), (x + fx * 0.035, y + fy * 0.035, 1.45), "black")


def table(kit, x, y, w, d, h=0.76, top="laminate"):
    """A steel sorting table: laminate top, square legs, a lower shelf."""
    b = kit.b
    b.box((w, d, 0.03), (x, y, h - 0.015), top)
    b.box((w - 0.06, d - 0.06, 0.06), (x, y, h - 0.06), "steel_grey")
    b.box((w - 0.1, d - 0.1, 0.02), (x, y, 0.22), "steel_grey")
    for sx in (-1, 1):
        for sy in (-1, 1):
            b.box((0.04, 0.04, h - 0.03), (x + sx * (w / 2 - 0.05), y + sy * (d / 2 - 0.05), (h - 0.03) / 2), "steel_grey")
    kit.col((w, d, h), (x, y, h / 2))


def sorter(kit, x, y, along_x=True):
    """A pigeonhole sorting case: 6 x 8 cubbies of 11 in, plywood, on a base."""
    b = kit.b
    W, D, H = 2.2, 0.38, 1.95
    sx, sy = (W, D) if along_x else (D, W)
    b.box((sx, sy, 0.1), (x, y, 0.05), "black")
    b.box((sx if along_x else 0.012, 0.012 if along_x else sy, H - 0.1), (x - (0 if along_x else D / 2 - 0.006),
          y + (D / 2 - 0.006 if along_x else 0), 0.1 + (H - 0.1) / 2), "sorter_wood")
    for i in range(9):
        t = -W / 2 + i * W / 8
        if along_x:
            b.box((0.016, D, H - 0.1), (x + t, y, 0.1 + (H - 0.1) / 2), "sorter_wood")
        else:
            b.box((D, 0.016, H - 0.1), (x, y + t, 0.1 + (H - 0.1) / 2), "sorter_wood")
    for k in range(7):
        z = 0.1 + k * (H - 0.1) / 6
        b.box((sx, sy, 0.016), (x, y, z), "sorter_wood")
    kit.col((sx, sy, H), (x, y, H / 2))


def fittings(kit, cid):
    b = kit.b
    x0, y0, x1, y1 = FL.CELLS[cid]["rect"]
    if cid == "R1":
        ay = FL.ARRIVAL[1]
        extinguisher(b, 0.0, ay + 1.3, (1, 0))
        b.box((0.03, 0.12, 0.17), (0.015, ay - 1.4, 1.5), "logger")
        b.box((0.006, 0.07, 0.04), (0.031, ay - 1.4, 1.53), "black")
        duct(kit, 0.3, x1 - 0.3, FL.MAIN1 + 0.62)
    elif cid == "R3":
        extinguisher(b, x0, FL.MAIN1 - 1.4, (1, 0))
        b.box((0.03, 0.12, 0.17), (x1 - 0.015, FL.MAIN1 + 1.5, 1.5), "logger")
        duct(kit, x0 + 0.3, x1 - 0.3, FL.MAIN1 + 0.62)
    elif cid == "R4":
        extinguisher(b, 2.6, y1, (0, -1))
        b.box((0.12, 0.03, 0.17), (1.2, y1 - 0.015, 1.5), "logger")
    elif cid == "R5":
        extinguisher(b, x0, FL.R5MAIN - 0.2, (1, 0))
    elif cid == "C1":
        extinguisher(b, 6.1, y0, (0, 1))
        extinguisher(b, 25.0, y1, (0, -1))
    elif cid == "C3":
        extinguisher(b, x1, 18.0, (-1, 0))
        # a mop bucket and wringer at the dead end
        bx, by = [pr["c"] for pr in FL.PROPS if pr["kind"] == "bucket"][0]
        b.cyl(0.2, 0.17, 0.4, (bx, by, 0.24), "bucket", segs=16)
        b.box((0.3, 0.2, 0.18), (bx, by, 0.52), "bucket")
        b.cyl(0.012, 0.012, 1.3, (bx + 0.15, by + 0.05, 0.9), "rod", segs=6, rot=(0.15, 0.1, 0))
        for k in range(4):
            a = k * math.pi / 2 + 0.4
            b.cyl(0.03, 0.03, 0.04, (bx + 0.18 * math.cos(a), by + 0.18 * math.sin(a), 0.02), "black", segs=8)
        kit.col((0.42, 0.42, 0.7), (bx, by, 0.35))
    elif cid == "R2":
        # Sorting: two tables, the pigeonhole case, a desk with a terminal.
        for pr in FL.PROPS:
            if pr["cell"] != "R2":
                continue
            (px, py), (sx, sy) = pr["c"], pr["size"]
            if pr["kind"] == "table":
                table(kit, px, py, sx, sy)
            elif pr["kind"] == "sorter":
                sorter(kit, px, py, along_x=sx > sy)
            elif pr["kind"] == "desk":
                table(kit, px, py, sx, sy)
                mx, my = px + 0.15, py - 0.05
                b.box((0.38, 0.4, 0.34), (mx, my, 0.76 + 0.17), "monitor")
                b.box((0.33, 0.004, 0.26), (mx, my + 0.202, 0.76 + 0.18), "screen")
                b.box((0.44, 0.16, 0.025), (mx - 0.1, my + 0.31, 0.775), "monitor")
            elif pr["kind"] == "stool":
                # a kick step stool (14 in high, 16 in base), parked here off the aisles
                b.cyl(0.203, 0.15, 0.33, (px, py, 0.175), "stool", segs=20)
                b.cyl(0.152, 0.152, 0.025, (px, py, 0.3555), "rubber", segs=20)
                b.cyl(0.205, 0.205, 0.012, (px, py, 0.006), "rubber", segs=20)
                kit.col((0.34, 0.34, 0.36), (px, py, 0.18))
            elif pr["kind"] == "chair":
                b.box((0.42, 0.42, 0.06), (px, py, 0.46), "black")
                b.box((0.42, 0.05, 0.4), (px, py + 0.2, 0.72), "black")
                b.cyl(0.02, 0.02, 0.36, (px, py, 0.25), "rod", segs=6)
                for k in range(5):
                    a = k * 2 * math.pi / 5
                    b.box((0.26, 0.03, 0.02), (px + 0.13 * math.cos(a), py + 0.13 * math.sin(a), 0.05), "black",
                          rot=(0, 0, a))
                kit.col((sx, sy, 0.9), (px, py, 0.45))
        extinguisher(b, x0, 14.0, (1, 0))
        b.box((0.03, 0.12, 0.17), (x1 - 0.015, 9.0, 1.5), "logger")


# --------------------------------------------------------------- export ---

def merge_paint(vis):
    """Every untextured material into one vertex-coloured "paint" (linear
    albedo in RGB; alpha codes a lamp: 0.1-0.4 group 0-3, 0.5 always on)."""
    me = vis.data
    names = [m.name for m in me.materials]
    keep = [n for n in names if n in TEXTURED]
    K.material("paint", (1.0, 1.0, 1.0))
    table_c = np.zeros((len(names), 4))
    remap = np.zeros(len(names), int)
    for i, n in enumerate(names):
        d = K.MATS[n]
        a = 1.0
        if n.startswith("lamp_g"):
            a = (int(n[-1]) + 1) / 10.0
        elif n == "lamp_night":
            a = 0.5
        table_c[i] = (*d["color"], a) if n not in keep else (1, 1, 1, 1)
        remap[i] = keep.index(n) if n in keep else len(keep)
    npoly = len(me.polygons)
    mi = np.zeros(npoly, int)
    me.polygons.foreach_get("material_index", mi)
    ls = np.zeros(npoly, int)
    lt = np.zeros(npoly, int)
    me.polygons.foreach_get("loop_start", ls)
    me.polygons.foreach_get("loop_total", lt)
    cols = np.zeros((len(me.loops), 4), np.float32)
    for p in range(npoly):
        cols[ls[p]:ls[p] + lt[p]] = table_c[mi[p]]
    ca = me.color_attributes.new("Color", "FLOAT_COLOR", "CORNER")
    ca.data.foreach_set("color", cols.ravel())
    me.color_attributes.active_color = ca
    me.materials.clear()
    for n in keep + ["paint"]:
        me.materials.append(bpy.data.materials[n])
    me.polygons.foreach_set("material_index", remap[mi])
    me.update()


def export_glb(kit, vis, out):
    scene = bpy.context.scene
    objs = [vis]
    for i, (size, loc, rz) in enumerate(kit.cols):
        cb = K.Builder()
        cb.box(size, (0, 0, 0), "concrete_floor")
        co = bpy.data.objects.new(f"col{i}-colonly", cb.to_mesh(f"col{i}"))
        scene.collection.objects.link(co)
        co.location = loc
        co.rotation_euler = (0, 0, rz)
        objs.append(co)
    for name, loc, rz in kit.spots:
        e = bpy.data.objects.new(name, None)
        scene.collection.objects.link(e)
        e.location = loc
        e.rotation_euler = (0, 0, rz)
        objs.append(e)
    for o in bpy.data.objects:
        o.select_set(o in objs)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, kit.name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT", export_image_format="NONE",
                              export_texcoords=True, export_normals=True, export_vertex_color="ACTIVE")
    print("exported", kit.name, "cols", len(kit.cols), "spots", len(kit.spots))


def export(kit, out, lm, samples):
    """As level_kit.Kit.export, but: the light groups baked at half size (they
    are smooth), then the materials merged (merge_paint)."""
    os.makedirs(os.path.join(out, "lightmaps"), exist_ok=True)
    scene = bpy.context.scene
    vis = bpy.data.objects.new(kit.name, kit.b.to_mesh(kit.name))
    scene.collection.objects.link(vis)
    for p in vis.data.polygons:
        p.use_smooth = False
    K.box_uvs(vis, 1.0)
    K.lightmap_uvs(vis, 0.003)
    print(kit.name, "tris", sum(len(p.vertices) - 2 for p in vis.data.polygons))
    if K.FAST:
        lm = min(lm, 256)
        samples = min(samples, 16)
    glm = max(lm // 2, 128)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = w
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 4
    scene.cycles.glossy_bounces = 1
    scene.cycles.sample_clamp_indirect = 2.0
    scene.render.bake.margin = 4
    scene.render.bake.use_selected_to_active = False
    bpy.context.view_layer.objects.active = vis
    for o in bpy.data.objects:
        o.select_set(o == vis)
    rgb = K.bake(vis, lm, lambda g: g < 0)
    K._save_png(np.sqrt(np.clip(rgb / K.LM_SCALE, 0, 1)), os.path.join(out, "lightmaps", kit.name + ".png"), alpha=False)
    present = {m.name for m in vis.data.materials}
    groups = sorted({K.MATS[n]["group"] for n in present if K.MATS[n]["emit"] and K.MATS[n]["group"] >= 0})
    if groups:
        gm = np.zeros((glm, glm, 4))
        for g in groups:
            px = K.bake(vis, glm, lambda k, g=g: k == g)
            lum = px[:, :, 0] * 0.3 + px[:, :, 1] * 0.59 + px[:, :, 2] * 0.11
            gm[:, :, g] = np.sqrt(np.clip(lum / K.GROUP_SCALE, 0, 1))
            print(kit.name, "group", g, "baked")
        K._save_png(gm, os.path.join(out, "lightmaps", kit.name + "_groups.png"), alpha=True)
    K._restore_emission()
    merge_paint(vis)
    export_glb(kit, vis, out)


def build_cell(cid, samples):
    K.reset()
    declare_materials()
    c = FL.CELLS[cid]
    x0, y0, x1, y1 = c["rect"]
    kit = K.Kit("filing_" + cid)
    b = kit.b
    rect(b, x0, y0, x1, y1, 0.0, "concrete_floor")
    rect(b, x0, y0, x1, y1, CEIL, "slab_paint", up=False)
    kit.col((x1 - x0 + 0.7, y1 - y0 + 0.7, 0.4), ((x0 + x1) / 2, (y0 + y1) / 2, -0.2))
    kit.col((x1 - x0 + 0.7, y1 - y0 + 0.7, 0.4), ((x0 + x1) / 2, (y0 + y1) / 2, CEIL + 0.2))
    walls(kit, cid)
    lights(kit, cid)
    sprinklers(kit, cid)
    rails(kit, cid)
    fittings(kit, cid)
    if cid == "R1":
        kit.spot("spot_arrival", (FL.ARRIVAL[0], FL.ARRIVAL[1], 0.0), -math.pi / 2)
    if cid == "R5":
        kit.spot("spot_exit", (FL.EXIT[0], FL.EXIT[1], 0.0), math.pi)
    export(kit, OUT, c["lm"], samples)


samples = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 96
cells = sys.argv[sys.argv.index("--cells") + 1].split(",") if "--cells" in sys.argv else list(FL.CELLS)
print("tube nits %.0f emit %.2f" % (TUBE_NITS, TUBE_EMIT))
for cid in cells:
    build_cell(cid, samples)
