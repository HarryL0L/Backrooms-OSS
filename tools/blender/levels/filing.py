"""The Stacks (side level "filing"): one records-centre storage room after
hours, built at the sizes in assets/levels/filing/SPEC.md. 11.6 x 16.9 m of
sealed concrete under a 3.2 m painted slab: two banks of high-density
mobile shelving (twelve double-faced mechanical-assist carriages each,
between two fixed single-faced units against the side walls) on flush
floor rails, a 6 ft main aisle between the banks with the carriages'
three-spoke handles on it, 42 in rear aisles along the end walls, and
2-lamp T8 strips hung in rows across the ranges (parallel to the rails,
so whichever aisle is open has light), switched by occupancy sensors.

This script makes the room's shell kit (floor and rails, walls, slab,
strips, sprinkler pipe, duct, doors): everything that doesn't move. The
shelving itself is the level's own procedural geometry
(scripts/world/levels/filing_level.gd), lit analytically by the level's
shader (assets/levels/filing/filing_lit.gdshaderinc) from the same strip
rows, because it moves.

Light (L.U.C.I.D. units, as office.py): each strip's two tubes are emitters
of their real luminance (Lucid strip_t8_2lamp, 4500 lm x LLF 0.85 over the
tubes' surface: 6510 cd/m2), stored as cd/m2 / 153.6. Light groups: 0 the
main aisle row, 1 bank A's rows and the south rear aisle, 2 bank B's south
row, 3 bank B's north row and the north rear aisle. Always on (colour
bake): the night-light strip by the door and the exit sign.

Run:
  /tmp/claude-0/bpyenv/bin/python tools/blender/levels/filing.py [out] [--fast] [--samples N]
  python3 tools/blender/levels/filing.py --textures <download dir>   (textures)
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
# (keep in step with scripts/world/levels/filing_level.gd)
SEC_W = 42 * IN             # shelf section (records cartons: 3 across)
NSEC = 6
END_T = 0.025               # end panel / end frame
RANGE_L = NSEC * SEC_W + 2 * END_T     # 6.451 m, a carriage's length
SHELF_D = 15 * IN           # each face
FLUE = 2 * IN
CAR_W = 2 * SHELF_D + FLUE  # 0.813 m double-faced carriage
FIX_W = SHELF_D + 0.04      # single-faced fixed unit (with back panel)
AISLE = 36 * IN             # the one open aisle in a bank
NCAR = 12
WALL_GAP = 0.05
BANK_X0 = WALL_GAP
BANK_W = 2 * FIX_W + NCAR * CAR_W + AISLE
ROOM_W = BANK_W + 2 * WALL_GAP          # 11.612
REAR = 42 * IN              # rear aisles
MAIN = 72 * IN              # main aisle
BANK_A_Y = REAR
BANK_B_Y = REAR + RANGE_L + MAIN
ROOM_D = 2 * REAR + 2 * RANGE_L + MAIN  # 16.865
CEIL = 3.20                 # floor to slab soffit
RAIL_DY = (0.40, 2.28, 4.17, 6.05)      # rails under a range (from its south end)
STRIP_Z = 2.85              # strip underside (tubes just below)
STRIP_X = (1.18, 3.50, 5.81, 8.12, 10.43)
ROWS = {                    # y: group (strip rows, along x)
    0.5335: 1, BANK_A_Y + 1.61: 1, BANK_A_Y + 4.84: 1,
    BANK_A_Y + RANGE_L + MAIN / 2: 0,
    BANK_B_Y + 1.61: 2, BANK_B_Y + 4.84: 3, ROOM_D - 0.5335: 3,
}
MAIN_Y = BANK_A_Y + RANGE_L + MAIN / 2
DOOR_W, DOOR_H = 36 * IN, 84 * IN
ARRIVE_Y = MAIN_Y           # the archive door (west wall, main aisle)
EXIT_X = ROOM_W - 1.0       # the exit door (north wall, rear aisle)
WALL_T = 0.2
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
    print("sounds done")


if "--sounds" in sys.argv:
    make_sounds(os.path.join(OUT, "audio"))
    sys.exit(0)


# ================================================================= kit ===
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import bpy  # noqa: E402
import level_kit as K  # noqa: E402

K.reset()
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
for g in range(4):
    K.material(f"lamp_g{g}", (1.0, 1.0, 1.0), emit=TUBE_EMIT, group=g)
K.material("lamp_night", (1.0, 1.0, 1.0), emit=TUBE_EMIT)

kit = K.Kit("filing_room")
b = kit.b
rng = random.Random(1103)


def rect(x0, y0, x1, y1, z, m, up=True):
    c = ((x0 + x1) / 2, (y0 + y1) / 2, z + (1 if up else -1))
    b.oquad([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], m, c)


def shell():
    rect(0, 0, ROOM_W, ROOM_D, 0.0, "concrete_floor")
    rect(0, 0, ROOM_W, ROOM_D, CEIL, "slab_paint", up=False)
    kit.col((ROOM_W + 1, ROOM_D + 1, 0.4), (ROOM_W / 2, ROOM_D / 2, -0.2))
    kit.col((ROOM_W + 1, ROOM_D + 1, 0.4), (ROOM_W / 2, ROOM_D / 2, CEIL + 0.2))
    # Walls (painted block), the rubber cove base along them.
    for (a, c, axis, at, toward) in ((0, ROOM_W, "x", 0.0, 1), (0, ROOM_W, "x", ROOM_D, -1),
                                     (0, ROOM_D, "y", 0.0, 1), (0, ROOM_D, "y", ROOM_W, -1)):
        if axis == "x":
            b.oquad([(a, at, 0), (c, at, 0), (c, at, CEIL), (a, at, CEIL)], "cmu_paint", ((a + c) / 2, at + toward, 1))
            b.box((c - a, 0.006, 0.1016), ((a + c) / 2, at + toward * 0.003, 0.0508), "base")
            kit.col((c - a + 1, WALL_T, CEIL + 0.4), ((a + c) / 2, at - toward * WALL_T / 2, CEIL / 2))
        else:
            b.oquad([(at, a, 0), (at, c, 0), (at, c, CEIL), (at, a, CEIL)], "cmu_paint", (at + toward, (a + c) / 2, 1))
            b.box((0.006, c - a, 0.1016), (at + toward * 0.003, (a + c) / 2, 0.0508), "base")
            kit.col((WALL_T, c - a + 1, CEIL + 0.4), (at - toward * WALL_T / 2, (a + c) / 2, CEIL / 2))


def rails():
    """Flush rails: a 2 in steel head in a channel cast into the slab, a
    dark joint either side; across each bank between its fixed units."""
    x0 = BANK_X0 + FIX_W - 0.02
    x1 = BANK_X0 + BANK_W - FIX_W + 0.02
    for y0 in (BANK_A_Y, BANK_B_Y):
        for dy in RAIL_DY:
            y = y0 + dy
            b.box((x1 - x0, 0.072, 0.0012), ((x0 + x1) / 2, y, 0.0006), "rail_gap")
            b.box((x1 - x0, 0.052, 0.002), ((x0 + x1) / 2, y, 0.001), "rail")


def strip(x, y, m):
    """A 4 ft two-lamp T8 strip hung on two rods: the white channel, two
    tubes under it."""
    b.box((1.22, 0.11, 0.06), (x, y, STRIP_Z + 0.05), "strip_body", bevel=0.006)
    for s in (-1, 1):
        b.cyl(TUBE_R, TUBE_R, TUBE_L, (x, y + s * 0.028, STRIP_Z + 0.008), m, segs=8, rot=(0, math.pi / 2, 0))
        b.cyl(0.006, 0.006, CEIL - STRIP_Z - 0.08, (x + s * 0.45, y, (CEIL + STRIP_Z + 0.08) / 2), "rod", segs=6)
        b.box((0.03, 0.025, 0.02), (x + s * 0.6, y + s * 0.028, STRIP_Z + 0.01), "strip_body")   # lamp holders


def lights():
    for y, g in ROWS.items():
        for i, x in enumerate(STRIP_X):
            night = abs(y - MAIN_Y) < 0.01 and i == 0
            strip(x, y, "lamp_night" if night else f"lamp_g{g}")
    # Occupancy sensors (ceiling PIR) over the main aisle and each bank.
    for x, y in ((1.8, MAIN_Y), (9.8, MAIN_Y), (5.8, BANK_A_Y + 3.2), (5.8, BANK_B_Y + 1.6),
                 (5.8, BANK_B_Y + 4.8), (5.8, ROOM_D - 0.5)):
        b.cyl(0.055, 0.045, 0.03, (x, y + 0.35, CEIL - 0.015), "sensor", segs=12)


def sprinklers():
    """Wet system: a 4 in main along the east side, 1 in branch lines along
    x between the strip rows, pendent heads on a ~3 m grid, deflectors
    0.52 m over the top of storage (NFPA 13: 18 in min.)."""
    zb = CEIL - 0.16
    xm = ROOM_W - 0.35
    b.cyl(0.057, 0.057, ROOM_D - 0.4, (xm, ROOM_D / 2, CEIL - 0.12), "pipe_red", segs=12, rot=(math.pi / 2, 0, 0))
    for y in (1.6, 4.4, 7.0, 9.9, 12.6, 15.4):
        b.cyl(0.0167, 0.0167, xm - 0.6, ((xm + 0.6) / 2, y, zb), "pipe_red", segs=8, rot=(0, math.pi / 2, 0))
        b.cyl(0.03, 0.03, 0.1, (xm - 0.05, y, zb), "pipe_red", segs=8, rot=(0, math.pi / 2, 0))
        for x in (1.3, 4.3, 7.3, 10.3):
            b.cyl(0.012, 0.012, zb - 2.86, (x, y, (zb + 2.86) / 2), "pipe_red", segs=6)
            b.cyl(0.011, 0.008, 0.03, (x, y, 2.845), "sprinkler", segs=8)
            b.cyl(0.021, 0.021, 0.003, (x, y, 2.825), "sprinkler", segs=12)
            b.box((0.004, 0.022, 0.03), (x, y, 2.84), "sprinkler")
        # hangers to the slab
        for x in (2.8, 5.8, 8.8):
            b.box((0.01, 0.01, CEIL - zb), (x, y, (CEIL + zb) / 2), "rod")


def duct():
    """The supply duct over the main aisle, galvanised, with two square
    diffusers' worth of side grilles."""
    y = MAIN_Y + 0.62
    b.box((ROOM_W - 0.6, 0.6, 0.3), (ROOM_W / 2 - 0.1, y, CEIL - 0.17), "galv")
    for x in (2.6, 6.6, 9.6):
        b.box((0.5, 0.012, 0.18), (x, y - 0.306, CEIL - 0.17), "grille")
        b.box((0.46, 0.006, 0.14), (x, y - 0.312, CEIL - 0.17), "grille_dark")
    for x in (1.0, 4.0, 7.0, 10.0):
        b.box((0.03, 0.66, 0.012), (x, y, CEIL - 0.33), "rod")
        for s in (-1, 1):
            b.box((0.01, 0.01, 0.34), (x, y + s * 0.33, CEIL - 0.17), "rod")


def door_west():
    """The archive door you came in by (shut behind you): hollow metal, 36
    x 84 in, closer, lever."""
    y = ARRIVE_Y
    f = 2 * IN
    for s in (-1, 1):
        b.box((0.03, f, DOOR_H + f), (0.015, y + s * (DOOR_W / 2 + f / 2), (DOOR_H + f) / 2), "door_frame")
    b.box((0.03, DOOR_W + 2 * f, f), (0.015, y, DOOR_H + f / 2), "door_frame")
    b.box((0.012, DOOR_W - 0.006, DOOR_H - 0.006), (0.006, y, DOOR_H / 2), "door_steel")
    b.box((0.04, 0.13, 0.025), (0.035, y - DOOR_W / 2 + 0.13, 1.0), "hardware")
    b.cyl(0.03, 0.03, 0.03, (0.02, y - DOOR_W / 2 + 0.07, 1.0), "hardware", segs=12, rot=(0, math.pi / 2, 0))
    b.box((0.05, 0.3, 0.05), (0.04, y + 0.2, DOOR_H - 0.1), "hardware")
    b.box((0.003, DOOR_W - 0.05, 0.25), (0.0135, y, 0.13), "hardware")          # kick plate


def exit_door_trim():
    """Round the exit (the level's LevelEntrance makes the leaf): the exit
    sign over it, emergency-lit, always on."""
    x = EXIT_X
    y = ROOM_D
    b.box((0.33, 0.06, 0.2), (x, y - 0.03, 2.42), "exit_housing")
    b.box((0.30, 0.004, 0.115), (x, y - 0.062, 2.42), "exit_face")


def fittings():
    # Extinguisher by the door, a temperature / RH logger, the stool.
    b.cyl(0.075, 0.075, 0.42, (0.09, ARRIVE_Y + 1.3, 1.0), "extinguisher", segs=14)
    b.cyl(0.03, 0.03, 0.08, (0.09, ARRIVE_Y + 1.3, 1.25), "black", segs=8)
    b.box((0.06, 0.04, 0.12), (0.035, ARRIVE_Y + 1.3, 1.45), "black")
    b.box((0.03, 0.12, 0.17), (0.015, ARRIVE_Y - 1.4, 1.5), "logger")
    b.box((0.006, 0.07, 0.04), (0.031, ARRIVE_Y - 1.4, 1.53), "black")
    # Kick step stool (14 in high, 16 in base) by bank B's handles.
    sx, sy = 7.15, BANK_B_Y - 0.62
    b.cyl(0.203, 0.15, 0.33, (sx, sy, 0.175), "stool", segs=20)
    b.cyl(0.152, 0.152, 0.025, (sx, sy, 0.3555), "rubber", segs=20)
    b.cyl(0.205, 0.205, 0.012, (sx, sy, 0.006), "rubber", segs=20)
    kit.col((0.34, 0.34, 0.36), (sx, sy, 0.18))


shell()
rails()
lights()
sprinklers()
duct()
door_west()
exit_door_trim()
fittings()
kit.spot("spot_arrival", (1.0, ARRIVE_Y, 0.0), -math.pi / 2)
kit.spot("spot_exit", (EXIT_X, ROOM_D, 0.0), math.pi)
print("tube nits %.0f emit %.2f" % (TUBE_NITS, TUBE_EMIT))
print("room %.3f x %.3f, bank A y %.3f, bank B y %.3f, main y %.3f, range %.3f" % (
    ROOM_W, ROOM_D, BANK_A_Y, BANK_B_Y, MAIN_Y, RANGE_L))

scene = bpy.context.scene
scene.cycles.max_bounces = 6
scene.cycles.diffuse_bounces = 4
scene.cycles.glossy_bounces = 1
scene.cycles.sample_clamp_indirect = 2.0
samples = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 128
kit.export(OUT, lm=1024, samples=samples)
