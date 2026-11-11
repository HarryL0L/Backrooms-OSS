"""The Endless Stairwell (side level "stairwell"): a concrete service / exit
stair in a painted block shaft, built at the sizes in
assets/levels/stairwell/SPEC.md (IBC 1011 / 1014 / 1015 / 1023 values,
each with its source there).

One storey of the stair is one kit, the same on every floor: the landing at
floor level with its fire door (vision panel), the stair identification
sign beside it and a two-lamp wall fixture over it; the two flights up to
the next landing (9 risers each, 7 in x 11 in, on a 44 in clear width) with
the half landing and its own wall fixture between them; the guards and
handrails round the well; the block walls of the storey. The level
(scripts/world/levels/stairwell_level.gd) stacks seven of them round you and
recycles them as you climb or descend, so the stair never ends. The top
storey (B2, where you come in) is a second kit: no flights up, the shaft's
roof slab over it, a guard across the drop where the up flight would be.

Light (L.U.C.I.D. units, as office.py / filing.py): each fixture's
wraparound lens is an emitter of its real luminance (two F17T8 lamps, 1325
lm each, ballast factor 0.88, light loss 0.8, Lambertian over the lens:
see SPEC.md), stored as cd/m2 / 153.6. Every lamp is switchable, so there
is no colour bake, only the group bake (one channel each):
  group 0  this storey's landing fixture
  group 1  this storey's half-landing fixture
  group 2  the storey above's two fixtures (their light reaching this one)
  group 3  the storey below's two fixtures
The storey is baked with a copy of itself above and below in the scene (they
shade it, bounce light, and carry the lamps of groups 2 and 3), so the
light crosses the seams. In Godot each storey's mesh gets its own four
multipliers (an instance uniform: assets/levels/stairwell/stairwell_lit
.gdshader), from the lamps of its own floor and the floors either side: a
lamp that dies darkens its own storey and the ends of the next ones.

Run:
  /tmp/claude-0/bpyenv/bin/python tools/blender/levels/stairwell.py [out] [--fast] [--samples N] [--kits unit,top]
  python3 tools/blender/levels/stairwell.py --textures <download dir>   (textures, signs, stencil digits)
  python3 tools/blender/levels/stairwell.py --sounds                    (audio)
"""
import math
import os
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "assets/levels/stairwell"
HERE = os.path.dirname(os.path.abspath(__file__))
IN = 0.0254

# ---------------------------------------------------------------- sizes ---
# Blender: x east (across the shaft), y north (along the flights), z up; the
# landing of this storey at z = 0, its door in the south wall (y = 0).
R = 7 * IN                  # riser, IBC 1011.5.2 maximum (178 mm)
T = 11 * IN                 # tread, IBC 1011.5.2 minimum (279 mm)
NR = 9                      # risers per flight (two flights a storey)
H = 2 * NR * R              # floor to floor: 18 x 7 in = 3.2004 m
CLEAR = 44 * IN             # clear width, IBC 1011.2 (1118 mm)
GUARD_T = 0.05              # the guard's footprint at the slab edge
FW = CLEAR + GUARD_T        # wall face to the well edge (1.168 m)
WELL = 0.75                 # the open well between the flights
SW = 2 * FW + WELL          # shaft, inside (3.085 m)
RUN = (NR - 1) * T          # a flight's going (2.235 m)
LM = 60 * IN                # landing depth at the door (1.524 m)
LH = 48 * IN                # half landing depth, IBC 1011.6 (1219 mm)
SL = LM + RUN + LH          # shaft, inside (4.978 m)
SLAB = 0.20                 # landing slabs
WAIST = 0.15                # the flights' concrete waist
NOSE = 1 * IN               # nosing projection (IBC 1011.5.5.1: <= 1 1/4 in)
STRIPE = 2 * IN             # safety-yellow nosing stripe (IBC 1025.2.1: 1-2 in)
RAIL_H = 36 * IN            # handrail height over the nosings (IBC 1014.2: 34-38 in)
RAIL_R = 0.75 * IN          # 1 1/2 in round rail
RAIL_CLR = 1.5 * IN         # clear of the wall (IBC 1014.7)
RAIL_EXT = 12 * IN          # top extension (IBC 1014.6)
GUARD_H = 42 * IN           # guard (IBC 1015.3)
BAL = 0.5 * IN              # balusters, 1/2 in square
BAL_P = 0.11                # pitch: 97 mm clear (IBC 1015.4: < 4 in sphere)
DOOR_W, DOOR_H = 36 * IN, 84 * IN      # 3070 hollow-metal fire door
DOOR_X = SW / 2
VISION = 10 * IN            # 10 x 10 in vision panel (100 sq in)
SIGN_W, SIGN_H = 18 * IN, 12 * IN      # IBC 1023.9.1 stair identification sign
SIGN_Z = 60 * IN            # its bottom (IBC 1023.9: >= 5 ft)
SIGN_X = DOOR_X - DOOR_W / 2 - 0.12 - SIGN_W / 2   # latch side of the door
STENCIL_X = DOOR_X + DOOR_W / 2 + 0.62            # the stencilled number, centre
STENCIL_Z = 1.62
STENCIL_H = 0.42
LAMP_Z = DOOR_H + 0.38      # the landing fixture over the door
LAMP_HZ = H / 2 + 2.25      # the half landing's fixture, on the north wall
LAMP_W, LAMP_D, LAMP_T = 0.66, 0.11, 0.15
# Light: L.U.C.I.D. units.
UNIT_NITS = 153.6
LAMP_LM = 2 * 1325.0 * 0.88            # two F17T8 / 841 (1325 lm), ballast factor 0.88
LLF = 0.80                             # dirty lens, old lamps
LENS_AREA = LAMP_W * (0.09 + 0.10 + 0.10)  # front + top + bottom of the wrap
LENS_NITS = LAMP_LM * LLF / (math.pi * LENS_AREA)
LENS_EMIT = LENS_NITS / UNIT_NITS


def nosing_z(y, flight):
    """Height of the line through the nosings of a flight at y (U1 rises
    north from the landing, U2 rises south from the half landing)."""
    if flight == 1:
        return R + (y - LM) * R / T
    return H / 2 + R + (LM + RUN - y) * R / T


# ============================================================ textures ===

def write_import(path, normal=False, mip=True, mode=2):
    params = {"compress/mode": mode, "compress/normal_map": 1 if normal else 0,
              "mipmaps/generate": "true" if mip else "false", "process/fix_alpha_border": "true",
              "detect_3d/compress_to": 0}
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n')
        for k, v in params.items():
            f.write(f"{k}={v}\n")


def glyphs():
    """The Stacks' stroke lettering (tools/blender/levels/filing.py GLYPHS):
    no fonts anywhere."""
    src = open(os.path.join(HERE, "filing.py")).read()
    i = src.index("\n_O = [") + 1
    j = src.index("\n}\n", i) + 3
    ns = {}
    exec(src[i:j], ns)
    return ns["GLYPHS"]


def make_textures(src):
    import numpy as np
    from PIL import Image, ImageDraw, ImageFilter
    dst = os.path.join(OUT, "textures")
    os.makedirs(dst, exist_ok=True)
    G = glyphs()

    def lin(a):
        return np.power(a / 255.0, 2.2)

    def srgb(a):
        return np.clip(np.power(np.clip(a, 0, 1), 1 / 2.2) * 255.0 + 0.5, 0, 255).astype(np.uint8)

    def albedo(img, target, sat=0.0):
        la = lin(np.asarray(img.convert("RGB"), np.float64))
        grey = la.mean(axis=2, keepdims=True)
        la = grey + (la - grey) * sat
        return la / la.reshape(-1, 3).mean(axis=0) * np.array(target)

    def acg(asset, kind):
        return Image.open(os.path.join(src, asset, f"{asset}_1K-JPG_{kind}.jpg"))

    def ph(asset, kind):
        return Image.open(os.path.join(src, asset, f"{asset}_{kind}_1k.jpg"))

    def save(arr_or_img, name, size, q=88):
        im = arr_or_img if isinstance(arr_or_img, Image.Image) else Image.fromarray(srgb(arr_or_img))
        im.resize((size, size), Image.LANCZOS).save(os.path.join(dst, name), quality=q)

    # Painted block (CMU): 8 x 16 in units (7 5/8 x 15 5/8 in, 3/8 in
    # tooled joints), running bond. One repeat = 3 blocks across (48 in) and
    # 8 courses up, stretched to H / 2 (a course of 200 mm instead of 203:
    # 16 courses a storey, so the joints carry on from storey to storey). Paint: a light warm grey, eggshell, over the
    # block's own pitted face (the plaster's grain, stronger).
    N = 1024
    rep = 48 * IN
    px = N / rep
    cpx = N / 8.0                    # one course (the repeat is 8 courses: a storey = 2 repeats)
    base = albedo(acg("PaintedPlaster017", "Color").resize((N, N)), (0.47, 0.465, 0.43), 0.2)
    nrm = np.asarray(acg("PaintedPlaster017", "NormalGL").convert("RGB").resize((N, N)), np.float64) / 255.0 * 2 - 1
    rough = np.asarray(acg("PaintedPlaster017", "Roughness").convert("L").resize((N, N)), np.float64) / 255.0
    y, x = np.mgrid[0:N, 0:N] + 0.5
    course = np.floor(y / cpx).astype(int)
    xs = x + (course % 2) * (8 * IN * px)
    jx = np.mod(xs, 16 * IN * px)
    jy = np.mod(y, cpx)
    jw = 0.375 * IN * px
    dx = np.minimum(jx, 16 * IN * px - jx)
    dy = np.minimum(jy, cpx - jy)
    joint = np.clip(1.0 - np.minimum(dx, dy) / (jw * 0.5 + 1.0), 0, 1)
    rng = np.random.default_rng(4101)
    blk = (np.floor(xs / (16 * IN * px)).astype(int) * 7 + course * 13) % 97
    tone = 1.0 + 0.035 * (rng.random(97)[blk] - 0.5)
    col = base * tone[:, :, None] * (1.0 - 0.28 * joint[:, :, None])
    # joints: a concave groove in the normal map
    gx = np.where(dx < dy, np.sign(np.mod(xs, 16 * IN * px) - 8 * IN * px), 0.0)
    gy = np.where(dy <= dx, np.sign(np.mod(y, cpx) - cpx / 2), 0.0)
    n2 = nrm * 0.55
    n2[:, :, 0] += -gx * joint * 0.6
    n2[:, :, 1] += gy * joint * 0.6
    n2[:, :, 2] = np.abs(n2[:, :, 2]) + 1.0
    n2 /= np.linalg.norm(n2, axis=2, keepdims=True)
    save(col, "cmu_paint_diff.jpg", 1024)
    Image.fromarray(((n2 * 0.5 + 0.5) * 255).astype(np.uint8)).resize((512, 512), Image.LANCZOS).save(
        os.path.join(dst, "cmu_paint_nor.jpg"), quality=88)
    Image.fromarray((np.clip(0.55 + 0.35 * rough + 0.2 * joint, 0, 1) * 255).astype(np.uint8)).resize(
        (256, 256), Image.LANCZOS).save(os.path.join(dst, "cmu_paint_rough.jpg"), quality=88)
    # Concrete (treads, landings, soffits): worn trowelled concrete.
    save(albedo(ph("concrete_floor_worn_001", "diff"), (0.27, 0.265, 0.25), 0.3), "concrete_diff.jpg", 1024)
    save(ph("concrete_floor_worn_001", "nor_gl"), "concrete_nor.jpg", 512)
    save(ph("concrete_floor_worn_001", "rough").convert("L"), "concrete_rough.jpg", 256)
    # The fire doors: painted steel, a blue-grey enamel, chipped.
    dp = albedo(acg("PaintedMetal014", "Color"), (0.16, 0.19, 0.21), 0.12)
    dm = dp.reshape(-1, 3).mean(axis=0)
    save(dm + (dp - dm) * 0.3, "door_paint_diff.jpg", 512)       # (its chipped rust, toned down to wear)
    save(acg("PaintedMetal014", "NormalGL"), "door_paint_nor.jpg", 512)
    save(acg("PaintedMetal014", "Roughness").convert("L"), "door_paint_rough.jpg", 256)

    S = 2

    def text(dr, s, x0, y0, h, w, fill=255, center=None):
        gw = 0.62 * h
        tw = sum((0.55 * h if c == " " else 0.82 * h) for c in s) - 0.2 * h
        x = x0 if center is None else center - tw / 2
        for c in s:
            if c == " ":
                x += 0.55 * h
                continue
            for line in G.get(c, []):
                dr.line([(x + p * gw, y0 + q * h) for p, q in line], fill=fill, width=w, joint="curve")
            x += 0.82 * h

    # The stair identification sign (IBC 1023.9.1): 18 x 12 in, white on
    # dark blue. Top: the stair (1 1/2 in letters), the floor number goes
    # in the middle (5 in, drawn by the level), under it the roof terminus,
    # at the bottom the stair's termini and the way to the exit discharge.
    W_, H_ = 576, 384                       # 32 px per inch
    ink = Image.new("L", (W_ * S, H_ * S), 0)
    dr = ImageDraw.Draw(ink)
    ppi = 32 * S
    text(dr, "STAIR 2", 0, 0.7 * ppi, 1.6 * ppi, int(0.27 * ppi), center=W_ * S / 2)
    text(dr, "NO ROOF ACCESS", 0, 8.0 * ppi, 1.0 * ppi, int(0.2 * ppi), center=W_ * S / 2)
    text(dr, "B2 - B", 0, 9.35 * ppi, 0.9 * ppi, int(0.18 * ppi), center=W_ * S / 2 - 0.9 * ppi)
    dr.line([(W_ * S / 2 + 1.4 * ppi, 10.2 * ppi), (W_ * S / 2 + 2.6 * ppi, 10.2 * ppi)], fill=255,
            width=int(0.15 * ppi))
    text(dr, "EXIT DISCHARGE LEVEL 1  UP", 0, 10.55 * ppi, 0.75 * ppi, int(0.15 * ppi), center=W_ * S / 2)
    dr.rectangle([0.25 * ppi, 0.25 * ppi, W_ * S - 0.25 * ppi, H_ * S - 0.25 * ppi], outline=255,
                 width=int(0.12 * ppi))
    m = np.asarray(ink.resize((W_, H_), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.4)), np.float64) / 255.0
    plate = np.array([0.012, 0.035, 0.11])
    white = np.array([0.75, 0.76, 0.74])
    img = plate * (1 - m[:, :, None]) + white * m[:, :, None]
    gr = np.asarray(Image.fromarray((rng.random((24, 36)) * 255).astype(np.uint8)).resize((W_, H_), Image.BICUBIC),
                    np.float64) / 255.0
    img *= (0.9 + 0.1 * gr)[:, :, None]
    sq = np.zeros((512, 512, 3)) + plate
    sq[64:64 + H_ // 1, :] = 0
    out = Image.fromarray(srgb(img)).resize((512, 342), Image.LANCZOS)
    canvas = Image.new("RGB", (512, 512), tuple(srgb(plate)))
    canvas.paste(out, (0, 0))
    canvas.save(os.path.join(dst, "sign_plate_diff.jpg"), quality=92)
    # Stencil digits (the floor numbers, sprayed on the block; and the
    # sign's number): "B", 0-9, "-", in a 16 x 1 strip of 64 x 96 cells,
    # white strokes in alpha, with the stencil's bridges.
    cw, ch = 64, 96
    chars = "B0123456789-"
    st = Image.new("L", (cw * 16 * S, ch * S), 0)
    d2 = ImageDraw.Draw(st)
    for k, c in enumerate(chars):
        h = ch * S * 0.78
        x0 = k * cw * S + (cw * S - 0.62 * h) / 2
        for line in G[c]:
            d2.line([(x0 + p * 0.62 * h, ch * S * 0.11 + q * h) for p, q in line], fill=255, width=int(11 * S),
                    joint="curve")
        # bridges: two thin gaps across each glyph, as a cut stencil has
        d2.rectangle([k * cw * S, ch * S * 0.36, (k + 1) * cw * S, ch * S * 0.36 + 3 * S], fill=0)
        d2.rectangle([k * cw * S, ch * S * 0.63, (k + 1) * cw * S, ch * S * 0.63 + 3 * S], fill=0)
    a = np.asarray(st.resize((cw * 16, ch), Image.LANCZOS).filter(ImageFilter.GaussianBlur(0.6)), np.float64) / 255.0
    sp = rng.random(a.shape)
    a = np.clip(a * (0.85 + 0.3 * sp) - 0.05 * (sp > 0.93), 0, 1)       # overspray, dropouts
    rgba = np.zeros((ch, cw * 16, 4), np.uint8)
    rgba[:, :, :3] = 255
    rgba[:, :, 3] = (a * 255).astype(np.uint8)
    Image.fromarray(rgba, "RGBA").save(os.path.join(dst, "digits_diff.png"))
    for fn in os.listdir(dst):
        if fn.endswith(".jpg") or fn.endswith(".png"):
            write_import(os.path.join(dst, fn), normal=fn.endswith("_nor.jpg"))
    print("textures done; lens %.0f cd/m2 (emit %.2f)" % (LENS_NITS, LENS_EMIT))


if "--textures" in sys.argv:
    make_textures(sys.argv[sys.argv.index("--textures") + 1])
    sys.exit(0)


# =============================================================== sounds ===
# Real recordings were not available (Freesound blocks automated access), so
# every sound is synthesised here as a documented placeholder, as the other
# levels do: noise shaped in the frequency domain with smooth log-frequency
# bands (nothing resonant, no sine blips), loops periodic by construction,
# and the shaft's echo (a tall hard concrete room: T60 about 3 s) convolved
# in where a sound is heard from far down the shaft.

SR = 44100


def make_sounds(dst):
    import subprocess
    import wave
    import numpy as np
    os.makedirs(dst, exist_ok=True)
    rs = np.random.default_rng(4102)

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

    def shaft(x, t60=3.0, wet=0.45, lp=2500.0, pre=0.012):
        """The stairwell's echo: dense, long, darkening as it dies (concrete
        and block absorb the highs a little each bounce)."""
        n = int(t60 * SR)
        t = np.arange(n) / SR
        ir = rs.standard_normal(n) * np.exp(-6.9 * t / t60)
        # the highs die faster: split in two bands with different decays
        lo = filt(ir, lambda f: 1.0 / (1.0 + (f / 700.0) ** 2))
        hi = filt(rs.standard_normal(n) * np.exp(-6.9 * t / (t60 * 0.45)), lambda f: band(f, 1200, lp * 2))
        ir = lo + 0.5 * hi
        ir[:int(pre * SR)] = 0
        ir /= np.sqrt((ir ** 2).sum())
        y = np.convolve(x, ir)[:len(x) + n]
        out = np.zeros(len(y))
        out[:len(x)] = x * (1 - wet)
        return out + y * wet * 3.0

    def place(d, x, at):
        i = int(at * SR)
        j = min(len(d), i + len(x))
        if j > i:
            d[i:j] += x[:j - i]

    def save(name, x, loop=False):
        x = np.asarray(x, np.float64)
        if loop:
            x = x / (np.sqrt((x ** 2).mean()) + 1e-9) * 10 ** (-20 / 20)
        else:
            x = x / (np.abs(x).max() + 1e-9) * 10 ** (-3 / 20)
            fade = min(len(x), int(0.02 * SR))
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

    # The shaft's air: a tall closed concrete shaft breathing (stack effect
    # through the door gaps): a deep, slow, broadband roar, with the faint
    # hiss of air past a door's undercut. Periodic (16 s).
    n = 16 * SR
    t = np.arange(n) / SR
    air = loop_noise(n, lambda f: 1.0 / np.maximum(f, 15.0) ** 0.9 / (1.0 + (f / 250.0) ** 2) + 0.05 * band(f, 2000, 6000))
    swell = 1.0 + 0.25 * np.sin(2 * math.pi * t / 16.0) + 0.12 * np.sin(2 * math.pi * t / 8.0 + 1.0)
    save("shaft_loop", air * swell, loop=True)
    # A fixture's ballast hum (magnetic ballast: 120 Hz and its harmonics,
    # mains-locked, under a little buzz), as heard a metre or two away.
    n = 8 * SR
    t = np.arange(n) / SR
    h = sum(a * np.sin(2 * math.pi * 120.0 * (k + 1) * t + rs.random() * 6.28)
            for k, a in enumerate((1.0, 0.45, 0.25, 0.12, 0.06)))
    bz = loop_noise(n, lambda f: band(f, 300, 3000))
    bz *= 1.0 + 0.8 * np.sin(2 * math.pi * 120 * t) ** 2
    save("hum_loop", h * 0.45 + bz / np.abs(bz).max() * 0.35, loop=True)
    # A failing ballast: the tubes dropping out and restriking: a relay-like
    # tick, the arc's buzz burst, ticks.
    for k in range(3):
        d = np.zeros(int(0.9 * SR))
        at = 0.0
        for j in range(3 + k):
            place(d, burst(0.03, 1500, 7000, 0.0005, 0.006, 0.7), at)
            place(d, burst(0.12 + 0.1 * rs.random(), 120, 2400, 0.004, 0.05, 0.35), at + 0.01)
            at += 0.08 + 0.18 * rs.random()
        save(f"flicker_{k + 1}", d)
    # A lamp giving up: the cathode's pop, a fizz dying away.
    d = np.zeros(int(1.6 * SR))
    place(d, burst(0.06, 500, 6000, 0.0005, 0.012, 1.0), 0.0)
    place(d, burst(1.2, 2000, 9000, 0.01, 0.35, 0.25), 0.02)
    save("lamp_die", shaft(d, 2.0, 0.35))
    # A locked fire door: the lever stops against the lock, the latch bolt
    # knocks in its strike, the leaf rattles in its frame.
    for k in range(2):
        d = np.zeros(int(1.2 * SR))
        at = 0.0
        for j in range(4):
            place(d, burst(0.05, 900, 5000, 0.0005, 0.01, 0.8 - 0.12 * j), at)
            place(d, burst(0.09, 120, 900, 0.001, 0.03, 0.6 - 0.1 * j), at + 0.003)
            at += 0.11 + 0.05 * rs.random()
        save(f"rattle_{k + 1}", shaft(d, 2.2, 0.3))
    # A fire door slamming several floors down, heard from up the shaft:
    # the closer's last sweep (air), the leaf hitting its stops (a heavy
    # low thud with the frame's clang in it), the latch, and the shaft
    # ringing with it for three seconds. Low-passed by the distance.
    d = np.zeros(int(1.0 * SR))
    place(d, burst(0.35, 200, 1500, 0.2, 0.1, 0.12), 0.0)
    place(d, burst(0.25, 35, 260, 0.001, 0.09, 1.0), 0.33)
    place(d, burst(0.15, 400, 2500, 0.0008, 0.04, 0.55), 0.332)
    place(d, burst(0.04, 1500, 5000, 0.0005, 0.008, 0.35), 0.40)
    d = filt(d, lambda f: 1.0 / (1.0 + (f / 2200.0) ** 2))
    save("door_slam", shaft(d, 3.2, 0.6))
    # The same door shut behind you, close: the closer's hiss and the
    # latch catching (as you arrive on B2).
    d = np.zeros(int(1.6 * SR))
    place(d, burst(0.9, 300, 3000, 0.4, 0.3, 0.06), 0.0)
    place(d, burst(0.2, 40, 300, 0.001, 0.07, 0.9), 0.95)
    place(d, burst(0.03, 1800, 6000, 0.0005, 0.006, 0.6), 0.97)
    save("door_shut", shaft(d, 2.6, 0.4))
    # Footsteps on concrete stairs (hard-soled shoes), heard from below:
    # a heel's knock and the sole's scuff, each a little different;
    # distance low-pass and the shaft's echo.
    for k in range(4):
        d = np.zeros(int(0.5 * SR))
        place(d, burst(0.05, 150, 1800, 0.0008, 0.015, 1.0), 0.0)
        place(d, burst(0.09, 800, 5000, 0.004, 0.03, 0.35 + 0.1 * rs.random()), 0.03 + 0.02 * rs.random())
        d = filt(d, lambda f: 1.0 / (1.0 + (f / (1600.0 + 300 * k)) ** 2))
        save(f"step_{k + 1}", shaft(d, 2.4, 0.55))
    # Water at the bottom: slow lapping against the steps, drips into it
    # from the flights above, the hollow sound of a flooded room.
    n = 12 * SR
    t = np.arange(n) / SR
    lap = loop_noise(n, lambda f: band(f, 80, 700) + 0.3 * band(f, 700, 3000))
    lap *= 0.6 + 0.4 * np.sin(2 * math.pi * t / 4.0) ** 2
    dr = np.zeros(n)
    for i in range(14):
        at = rs.random() * (12 - 0.3)
        g = burst(0.12, 900, 4000, 0.0005, 0.02, 0.5 + 0.5 * rs.random())
        place(dr, g, at)
    save("water_loop", lap + dr * 2.5, loop=True)
    print("sounds done")


if "--sounds" in sys.argv:
    make_sounds(os.path.join(OUT, "audio"))
    sys.exit(0)


# ================================================================= kits ===

sys.path.insert(0, os.path.join(HERE, ".."))
import bpy  # noqa: E402
import numpy as np  # noqa: E402
import level_kit as K  # noqa: E402

TEXTURED = ("concrete", "cmu_paint", "door_paint", "sign_plate")
LAMP_ALPHA = {"lamp_main": 0.1, "lamp_half": 0.2}


def declare_materials():
    K.material("concrete", (0.27, 0.265, 0.25), rough=0.8)
    K.material("cmu_paint", (0.47, 0.465, 0.43), rough=0.85)
    K.material("door_paint", (0.16, 0.19, 0.21), rough=0.5)
    K.material("sign_plate", (0.05, 0.07, 0.14), rough=0.4)
    K.material("frame", (0.10, 0.11, 0.12), rough=0.5)
    K.material("rail", (0.035, 0.035, 0.035), rough=0.45)          # black enamel
    K.material("guard", (0.13, 0.145, 0.135), rough=0.5)              # grey-green enamel
    K.material("nosing", (0.82, 0.55, 0.02), rough=0.6)            # ANSI safety yellow (5Y 8/12)
    K.material("hardware", (0.55, 0.55, 0.52), rough=0.3, metal=0.9)
    K.material("vision", (0.004, 0.004, 0.005), rough=0.05)        # wired glass, the dark behind it
    K.material("lamp_body", (0.72, 0.72, 0.70), rough=0.5)
    K.material("conduit", (0.45, 0.46, 0.47), rough=0.5, metal=0.6)
    K.material("black", (0.02, 0.02, 0.02), rough=0.7)
    K.material("lamp_main", (1.0, 1.0, 1.0), emit=LENS_EMIT, group=0)
    K.material("lamp_half", (1.0, 1.0, 1.0), emit=LENS_EMIT, group=1)
    K.material("lamp_above", (1.0, 1.0, 1.0), emit=LENS_EMIT, group=2)
    K.material("lamp_below", (1.0, 1.0, 1.0), emit=LENS_EMIT, group=3)


def quad(b, pts, m, toward):
    b.oquad(pts, m, toward)


def flight(b, x0, x1, which):
    """One flight: risers, treads (with their nosing lip and yellow stripe),
    the sloped soffit, the side face on the well side."""
    sgn = 1 if which == 1 else -1                 # the way it rises (y)
    y0 = LM if which == 1 else LM + RUN
    z0 = 0.0 if which == 1 else H / 2
    well_x = x0 if which == 1 else x1             # its edge on the well
    out_x = -1 if which == 1 else 1               # out of the flight, into the well
    for i in range(1, NR + 1):
        yr = y0 + sgn * (i - 1) * T               # riser i (and tread i's nosing)
        zb, zt = z0 + (i - 1) * R, z0 + i * R
        # riser (faces down the flight); the last one up to the landing's top
        ztr = zt if i == NR else zt - 0.02
        quad(b, [(x0, yr, zb), (x1, yr, zb), (x1, yr, ztr), (x0, yr, ztr)], "concrete",
             ((x0 + x1) / 2, yr - sgn, (zb + zt) / 2))
        if i < NR:
            yb = yr + sgn * T
            yf = yr - sgn * NOSE
            # tread, then the stripe on its leading edge, the lip's face
            ys = yf + sgn * STRIPE
            quad(b, [(x0, ys, zt), (x1, ys, zt), (x1, yb, zt), (x0, yb, zt)], "concrete", ((x0 + x1) / 2, (ys + yb) / 2, zt + 1))
            quad(b, [(x0, yf, zt), (x1, yf, zt), (x1, ys, zt), (x0, ys, zt)], "nosing", ((x0 + x1) / 2, yf, zt + 1))
            quad(b, [(x0, yf, zt - 0.02), (x1, yf, zt - 0.02), (x1, yf, zt), (x0, yf, zt)], "nosing",
                 ((x0 + x1) / 2, yf - sgn, zt))
            quad(b, [(x0, yf, zt - 0.02), (x1, yf, zt - 0.02), (x1, yr, zt - 0.02), (x0, yr, zt - 0.02)], "concrete",
                 ((x0 + x1) / 2, (yf + yr) / 2, zt - 1))
            # the side face under this tread, down to the soffit
            ya, yb2 = sorted((yf, yb))
            za = soffit_z(ya, which)
            zb2 = soffit_z(yb2, which)
            quad(b, [(well_x, ya, za), (well_x, yb2, zb2), (well_x, yb2, zt), (well_x, ya, zt)], "concrete",
                 (well_x + out_x, (ya + yb2) / 2, zt - 0.1))
    # the soffit under the flight
    ya, yb = (LM, LM + RUN)
    za, zb = soffit_z(ya, which), soffit_z(yb, which)
    quad(b, [(x0, ya, za), (x1, ya, za), (x1, yb, zb), (x0, yb, zb)], "concrete", ((x0 + x1) / 2, (ya + yb) / 2, -5.0))


def soffit_z(y, which):
    cos = T / math.hypot(T, R)
    if which == 1:
        zr = (y - LM) * R / T
    else:
        zr = H / 2 + (LM + RUN - y) * R / T
    return zr - WAIST / cos


def slab(b, y0, y1, z):
    """A landing slab across the shaft: top and underside."""
    quad(b, [(0, y0, z), (SW, y0, z), (SW, y1, z), (0, y1, z)], "concrete", (SW / 2, (y0 + y1) / 2, z + 1))
    quad(b, [(0, y0, z - SLAB), (SW, y0, z - SLAB), (SW, y1, z - SLAB), (0, y1, z - SLAB)], "concrete",
         (SW / 2, (y0 + y1) / 2, z - 5))


def edge(b, y, x0, x1, z0, z1, face):
    """A slab's edge (face: +1 toward +y)."""
    quad(b, [(x0, y, z0), (x1, y, z0), (x1, y, z1), (x0, y, z1)], "concrete", ((x0 + x1) / 2, y + face, (z0 + z1) / 2))


def stripe(b, y, x0, x1, z, face):
    """The yellow stripe on a landing's nosing (face: the way it faces)."""
    ys = y - face * STRIPE
    lo, hi = sorted((y, ys))
    quad(b, [(x0, lo, z + 0.0015), (x1, lo, z + 0.0015), (x1, hi, z + 0.0015), (x0, hi, z + 0.0015)], "nosing",
         ((x0 + x1) / 2, lo, z + 1))


def walls(b, top=False):
    z0, z1 = -SLAB, H - SLAB
    c = (SW / 2, SL / 2, H / 2)
    # east, west, north: whole
    quad(b, [(SW, 0, z0), (SW, SL, z0), (SW, SL, z1), (SW, 0, z1)], "cmu_paint", c)
    quad(b, [(0, 0, z0), (0, SL, z0), (0, SL, z1), (0, 0, z1)], "cmu_paint", c)
    quad(b, [(0, SL, z0), (SW, SL, z0), (SW, SL, z1), (0, SL, z1)], "cmu_paint", c)
    # south, round the door opening
    d0, d1 = DOOR_X - DOOR_W / 2, DOOR_X + DOOR_W / 2
    quad(b, [(0, 0, z0), (d0, 0, z0), (d0, 0, z1), (0, 0, z1)], "cmu_paint", c)
    quad(b, [(d1, 0, z0), (SW, 0, z0), (SW, 0, z1), (d1, 0, z1)], "cmu_paint", c)
    quad(b, [(d0, 0, DOOR_H), (d1, 0, DOOR_H), (d1, 0, z1), (d0, 0, z1)], "cmu_paint", c)
    quad(b, [(d0, 0, z0), (d1, 0, z0), (d1, 0, 0), (d0, 0, 0)], "cmu_paint", c)


def door(b, leaf=True):
    """A 3070 hollow-metal fire door in its frame, shut; a 10 x 10 in
    vision panel (wired glass: the dark corridor behind it), lever, closer,
    kick plate. Without `leaf`: the frame and the dark opening (the level
    puts its own moving leaf in: the way back, on B2)."""
    d0, d1 = DOOR_X - DOOR_W / 2, DOOR_X + DOOR_W / 2
    f = 2 * IN
    b.box((f, 0.02, DOOR_H + f), (d0 - f / 2, 0.01, (DOOR_H + f) / 2), "frame")
    b.box((f, 0.02, DOOR_H + f), (d1 + f / 2, 0.01, (DOOR_H + f) / 2), "frame")
    b.box((DOOR_W + 2 * f, 0.02, f), (DOOR_X, 0.01, DOOR_H + f / 2), "frame")
    # the reveal (frame through the wall)
    for x in (d0, d1):
        quad(b, [(x, 0, 0), (x, -0.2, 0), (x, -0.2, DOOR_H), (x, 0, DOOR_H)], "frame", (DOOR_X, -0.1, 1))
    quad(b, [(d0, 0, DOOR_H), (d1, 0, DOOR_H), (d1, -0.2, DOOR_H), (d0, -0.2, DOOR_H)], "frame", (DOOR_X, -0.1, 0))
    quad(b, [(d0, 0, 0.001), (d1, 0, 0.001), (d1, -0.2, 0.001), (d0, -0.2, 0.001)], "concrete", (DOOR_X, -0.1, 1))
    if not leaf:
        quad(b, [(d0, -0.2, 0), (d1, -0.2, 0), (d1, -0.2, DOOR_H), (d0, -0.2, DOOR_H)], "black", (DOOR_X, 0, 1))
        return
    yl = -0.06                                    # the leaf's face, in the frame's stop
    quad(b, [(d0, yl, 0), (d1, yl, 0), (d1, yl, DOOR_H), (d0, yl, DOOR_H)], "door_paint", (DOOR_X, 1, 1))
    # vision panel: 10 x 10 in, its centre 60 in up, on the latch side
    vx, vz = DOOR_X + 0.12, 60 * IN
    b.box((VISION + 0.04, 0.012, VISION + 0.04), (vx, yl + 0.006, vz), "frame")
    quad(b, [(vx - VISION / 2, yl + 0.0125, vz - VISION / 2), (vx + VISION / 2, yl + 0.0125, vz - VISION / 2),
             (vx + VISION / 2, yl + 0.0125, vz + VISION / 2), (vx - VISION / 2, yl + 0.0125, vz + VISION / 2)],
         "vision", (vx, 1, vz))
    # lever handle (latch side: east), rose, kick plate, closer and arm
    lx = d1 - 0.075
    b.cyl(0.03, 0.03, 0.012, (lx, yl + 0.006, 1.0), "hardware", segs=12, rot=(math.pi / 2, 0, 0))
    b.box((0.13, 0.02, 0.018), (lx - 0.06, yl + 0.04, 1.0), "hardware")
    b.box((0.016, 0.04, 0.016), (lx, yl + 0.025, 1.0), "hardware")
    b.box((DOOR_W - 0.06, 0.003, 0.25), (DOOR_X, yl + 0.0015, 0.14), "hardware")
    b.box((0.28, 0.06, 0.06), (d0 + 0.22, yl + 0.03 + 0.02, DOOR_H - 0.08), "hardware")
    b.box((0.30, 0.025, 0.02), (d0 + 0.42, yl + 0.06, DOOR_H - 0.05), "hardware", rot=(0, 0, 0.35))


def lamp(b, x, y, z, face, m):
    """The stairwell fixture: a 2 ft two-lamp T8 wall unit, steel back box,
    a wraparound polycarbonate lens (the emitter), a conduit up to the slab.
    face: +1 lens toward +y (south wall), -1 toward -y (north wall)."""
    b.box((LAMP_W + 0.04, 0.035, LAMP_T + 0.02), (x, y + face * 0.0175, z), "lamp_body")
    b.box((LAMP_W, LAMP_D - 0.035, LAMP_T - 0.03), (x, y + face * (0.035 + (LAMP_D - 0.035) / 2), z), m, bevel=0.012)
    for sx in (-1, 1):
        b.box((0.012, LAMP_D, LAMP_T), (x + sx * (LAMP_W / 2 + 0.006), y + face * LAMP_D / 2, z), "lamp_body")
    zc = z + LAMP_T / 2 + 0.01
    b.cyl(0.011, 0.011, 0.5, (x + LAMP_W / 2 - 0.05, y + face * 0.02, zc + 0.25), "conduit", segs=6)
    b.box((0.06, 0.03, 0.06), (x + LAMP_W / 2 - 0.05, y + face * 0.02, zc + 0.03), "conduit")


def rail(b, pts, wall=None):
    """A 1 1/2 in round handrail through `pts`; brackets to the wall (or to
    the guard) every ~1.2 m."""
    b.tube(pts, RAIL_R, "rail", segs=8)
    if wall is None:
        return
    axis, at = wall
    total = sum(math.dist(p, q) for p, q in zip(pts, pts[1:]))
    nb = max(2, int(total / 1.2) + 1)
    for k in range(nb):
        s = (k + 0.5) / nb * total
        for p, q in zip(pts, pts[1:]):
            dl = math.dist(p, q)
            if s <= dl:
                t = s / dl
                c = [p[i] + (q[i] - p[i]) * t for i in range(3)]
                break
            s -= dl
        if axis == "x":
            b.box((abs(c[0] - at), 0.012, 0.012), ((c[0] + at) / 2, c[1], c[2] - RAIL_R - 0.03), "hardware")
            b.box((0.012, 0.012, 0.035), (c[0], c[1], c[2] - RAIL_R - 0.015), "hardware")
            b.box((0.006, 0.06, 0.06), (at + (0.003 if at < SW / 2 else -0.003), c[1], c[2] - RAIL_R - 0.03),
                  "hardware")


def guard_run(b, x, ya, za, yb, zb, flat=False):
    """A steel guard along the well edge from (ya, za) to (yb, zb) (z: the
    walking line under it, nosing line or landing): 1 1/2 in top rail at
    42 in, a bottom rail, 1/2 in balusters at 110 mm, end posts."""
    L = abs(yb - ya)
    n = max(1, int(L / BAL_P))
    sl = (zb - za) / (yb - ya) if yb != ya else 0.0
    for k in range(n + 1):
        y = ya + (yb - ya) * k / n
        zw = za + sl * (y - ya)
        top = zw + GUARD_H - 0.02
        bot = zw - (R + 0.02 if not flat else 0.0)        # (into the step's side: the stair's balusters are cast in)
        b.box((BAL, BAL, top - bot), (x, y, (top + bot) / 2), "guard")
    b.tube([(x, ya, za + GUARD_H), (x, yb, zb + GUARD_H)], 0.019, "guard", segs=6)
    b.tube([(x, ya, za + 0.09), (x, yb, zb + 0.09)], 0.012, "guard", segs=6)
    for y, z in ((ya, za), (yb, zb)):
        b.box((0.038, 0.038, GUARD_H + 0.04), (x, y, z + (GUARD_H + 0.04) / 2 - 0.04), "guard")


def guard_x(b, y, xa, xb, z):
    """A guard across (along x) at y, standing on a landing at z."""
    n = max(1, int(abs(xb - xa) / BAL_P))
    for k in range(n + 1):
        x = xa + (xb - xa) * k / n
        b.box((BAL, BAL, GUARD_H - 0.05), (x, y, z + (GUARD_H - 0.05) / 2 + 0.03), "guard")
    b.tube([(xa, y, z + GUARD_H), (xb, y, z + GUARD_H)], 0.019, "guard", segs=6)
    b.tube([(xa, y, z + 0.09), (xb, y, z + 0.09)], 0.012, "guard", segs=6)


def storey(b, lamps=("lamp_main", "lamp_half"), top=False):
    """One storey (see the module doc). lamps: the materials of its two
    fixtures (the context copies use the groups of the storeys either side)."""
    walls(b, top)
    slab(b, 0.0, LM, 0.0)
    # this landing's edge (facing north): under the flight down (the storey
    # below's U2, whose top riser covers the top of it), across the well, and
    # under this storey's U1
    cs = WAIST * math.hypot(T, R) / T
    edge(b, LM, 0.0, FW, -R - cs, -SLAB, 1)
    edge(b, LM, FW, SW - FW, -SLAB, 0.0, 1)
    edge(b, LM, SW - FW, SW, -SLAB, -cs, 1)
    stripe(b, LM, 0.0, FW, 0.0, 1)
    door(b, leaf=not top)
    # the stair identification sign (latch side of the door)
    b.box((SIGN_W + 0.01, 0.006, SIGN_H + 0.01), (SIGN_X, 0.003, SIGN_Z + SIGN_H / 2), "frame")
    quad(b, [(SIGN_X - SIGN_W / 2, 0.0065, SIGN_Z), (SIGN_X + SIGN_W / 2, 0.0065, SIGN_Z),
             (SIGN_X + SIGN_W / 2, 0.0065, SIGN_Z + SIGN_H), (SIGN_X - SIGN_W / 2, 0.0065, SIGN_Z + SIGN_H)],
         "sign_plate", (SIGN_X, 1, SIGN_Z))
    lamp(b, DOOR_X, 0.0, LAMP_Z, 1, lamps[0])
    if top:
        # the shaft's roof slab, the guard across the drop where the up
        # flight would be
        quad(b, [(0, 0, H - SLAB), (SW, 0, H - SLAB), (SW, SL, H - SLAB), (0, SL, H - SLAB)], "concrete",
             (SW / 2, SL / 2, 0))
        cs = WAIST * math.hypot(T, R) / T
        edge(b, LM, FW, SW, -SLAB, 0.0, 1)
        guard_x(b, LM - 0.025, FW - 0.025, SW - 0.02, 0.0)
        b.box((0.038, 0.038, GUARD_H + 0.04), (SW - 0.02, LM - 0.025, (GUARD_H + 0.04) / 2 - 0.04), "guard")
        # the inner rail of the flight down, continued along this guard
        ix2 = FW - 0.025 - 0.06
        rail(b, [(ix2, LM, RAIL_H), (ix2, LM - 0.085, RAIL_H), (SW - 0.05, LM - 0.085, RAIL_H)])
        return
    # half landing and its fixture
    slab(b, LM + RUN, SL, H / 2)
    edge(b, LM + RUN, 0.0, FW, H / 2 - SLAB, H / 2 - cs, -1)
    edge(b, LM + RUN, FW, SW - FW, H / 2 - SLAB, H / 2, -1)
    edge(b, LM + RUN, SW - FW, SW, (NR - 1) * R - cs, (NR - 1) * R, -1)
    stripe(b, LM + RUN, SW - FW, SW, H / 2, -1)
    lamp(b, DOOR_X, SL, LAMP_HZ, -1, lamps[1])
    # U1: up the east side from this landing to the half landing
    flight(b, SW - FW, SW, 1)
    # U2: up the west side from the half landing to the landing above
    flight(b, 0.0, FW, 2)
    # guards along the well
    gx1 = SW - FW + 0.025
    gx2 = FW - 0.025
    guard_run(b, gx1, LM, R, LM + RUN, H / 2)
    guard_run(b, gx2, LM + RUN, H / 2 + R, LM, H)
    guard_x(b, LM + RUN + 0.025, gx2, gx1, H / 2)       # across the well's end at the half landing
    guard_x(b, LM - 0.025, gx2, gx1, 0.0)               # and at this landing
    # handrails: the inner one continuous round the well, 36 in over the
    # nosings, on the guards' flight side; the wall ones with their
    # extensions (12 in level at the top, one tread on the slope at the
    # bottom), returned to the wall
    ix1 = gx1 + 0.06
    ix2 = gx2 - 0.06
    rail(b, [(ix2, LM, RAIL_H), (ix2, LM - 0.085, RAIL_H), (ix1, LM - 0.085, RAIL_H + R * 0.5),
             (ix1, LM, R + RAIL_H), (ix1, LM + RUN, H / 2 + RAIL_H), (ix1, LM + RUN + 0.085, H / 2 + RAIL_H),
             (ix2, LM + RUN + 0.085, H / 2 + RAIL_H), (ix2, LM + RUN, H / 2 + R + RAIL_H), (ix2, LM, H + RAIL_H)])
    wx1 = SW - RAIL_CLR - RAIL_R
    rail(b, [(SW, LM - T, RAIL_H), (wx1, LM - T, RAIL_H), (wx1, LM, R + RAIL_H), (wx1, LM + RUN, H / 2 + RAIL_H),
             (wx1, LM + RUN + RAIL_EXT, H / 2 + RAIL_H), (SW, LM + RUN + RAIL_EXT, H / 2 + RAIL_H)], ("x", SW))
    wx2 = RAIL_CLR + RAIL_R
    rail(b, [(0, LM + RUN + T, H / 2 + RAIL_H), (wx2, LM + RUN + T, H / 2 + RAIL_H),
             (wx2, LM + RUN, H / 2 + R + RAIL_H), (wx2, LM, H + RAIL_H), (wx2, LM - RAIL_EXT, H + RAIL_H),
             (0, LM - RAIL_EXT, H + RAIL_H)], ("x", 0.0))


def context(name, z, lamps, top=False):
    """A copy of a storey in the bake scene only (not exported)."""
    cb = K.Builder()
    storey(cb, lamps, top)
    ob = bpy.data.objects.new(name, cb.to_mesh(name))
    bpy.context.scene.collection.objects.link(ob)
    ob.location = (0, 0, z)
    return ob


def merge_paint(vis):
    """Every untextured material into one vertex-coloured "paint" (linear
    albedo in RGB; alpha 0.1 / 0.2 marks the landing / half-landing lens)."""
    me = vis.data
    names = [m.name for m in me.materials]
    keep = [n for n in names if n in TEXTURED]
    K.material("paint", (1.0, 1.0, 1.0))
    table_c = np.zeros((len(names), 4))
    remap = np.zeros(len(names), int)
    for i, n in enumerate(names):
        d = K.MATS[n]
        table_c[i] = (*d["color"], LAMP_ALPHA.get(n, 1.0)) if n not in keep else (1, 1, 1, 1)
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
    me.materials.clear()
    for n in keep + ["paint"]:
        me.materials.append(bpy.data.materials[n])
    me.polygons.foreach_set("material_index", remap[mi])
    me.update()


def sign_uvs(vis):
    """The sign plate's face: its picture (the top 342 rows of the 512 px
    texture) over the 18 x 12 in plate."""
    me = vis.data
    mi = [m.name for m in me.materials].index("sign_plate")
    uv = me.uv_layers["uv"]
    for p in me.polygons:
        if p.material_index != mi:
            continue
        for li in p.loop_indices:
            v = me.vertices[me.loops[li].vertex_index].co
            u = ((SIGN_X + SIGN_W / 2) - v.x) / SIGN_W          # (read from the stair: +x is on your left)
            t = (v.z - SIGN_Z) / SIGN_H
            uv.data[li].uv = (u, 1.0 - (1.0 - t) * 342.0 / 512.0)


def export_glb(vis, out, name):
    for o in bpy.data.objects:
        o.select_set(o == vis)
    bpy.ops.export_scene.gltf(filepath=os.path.join(out, name + ".glb"), export_format="GLB", use_selection=True,
                              export_apply=True, export_materials="EXPORT", export_image_format="NONE",
                              export_texcoords=True, export_normals=True, export_vertex_color="ACTIVE")
    print("exported", name)


def build_kit(name, top, lm, samples):
    K.reset()
    declare_materials()
    b = K.Builder()
    storey(b, top=top)
    scene = bpy.context.scene
    vis = bpy.data.objects.new(name, b.to_mesh(name))
    scene.collection.objects.link(vis)
    for p in vis.data.polygons:
        p.use_smooth = False
    K.box_uvs(vis, 1.0)
    sign_uvs(vis)
    K.lightmap_uvs(vis, 0.004)
    print(name, "tris", sum(len(p.vertices) - 2 for p in vis.data.polygons))
    # the storeys either side (shade, bounce, and their lamps: groups 2 / 3)
    if not top:
        context("ctx_above", H, ("lamp_above", "lamp_above"), top=False)
    context("ctx_below", -H, ("lamp_below", "lamp_below"))
    context("ctx_below2", -2 * H, ("black", "black"))
    if not top:
        context("ctx_above2", 2 * H, ("black", "black"))
    if K.FAST:
        lm = min(lm, 256)
        samples = min(samples, 16)
    w = bpy.data.worlds.new("w")
    w.use_nodes = True
    w.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    scene.world = w
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.max_bounces = 6
    scene.cycles.diffuse_bounces = 5
    scene.cycles.glossy_bounces = 1
    scene.cycles.sample_clamp_indirect = 2.0
    scene.render.bake.margin = 4
    scene.render.bake.use_selected_to_active = False
    bpy.context.view_layer.objects.active = vis
    for o in bpy.data.objects:
        o.select_set(o == vis)
    os.makedirs(os.path.join(OUT, "lightmaps"), exist_ok=True)
    gm = np.zeros((lm, lm, 4))
    for g in ((0, 3) if top else (0, 1, 2, 3)):
        px = K._denoise(K.bake(vis, lm, lambda k, g=g: k == g))       # (a second pass: small lamps, few samples)
        lum = px[:, :, 0] * 0.3 + px[:, :, 1] * 0.59 + px[:, :, 2] * 0.11
        gm[:, :, g] = np.sqrt(np.clip(lum / K.GROUP_SCALE, 0, 1))
        print(name, "group", g, "baked, max %.3f mean %.4f" % (lum.max(), lum[lum > 0].mean() if (lum > 0).any() else 0))
    K._save_png(gm, os.path.join(OUT, "lightmaps", name + "_groups.png"), alpha=True)
    K._restore_emission()
    for o in list(bpy.data.objects):
        if o.name.startswith("ctx_"):
            bpy.data.objects.remove(o)
    merge_paint(vis)
    export_glb(vis, OUT, name)


samples = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 160
kits = sys.argv[sys.argv.index("--kits") + 1].split(",") if "--kits" in sys.argv else ["unit", "top"]
print("storey %.4f m, shaft %.3f x %.3f m, lens %.0f cd/m2 (emit %.2f)" % (H, SW, SL, LENS_NITS, LENS_EMIT))
if "unit" in kits:
    build_kit("stair_unit", False, 1024, samples)
if "top" in kits:
    build_kit("stair_top", True, 512, samples)
