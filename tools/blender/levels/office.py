"""The Dimming Floor (side level "office"): one open-plan office floor after
hours, built at the sizes in assets/levels/office/SPEC.md. A 120 x 60 ft
(36.58 x 18.29 m) floor plate on a 30 ft column grid, 9 ft (2.743 m) to a
2 x 2 ft T-bar ceiling with 2 x 4 ft three-lamp T8 troffers on an 8 x 10 ft
layout, carpet tiles, clusters of 8 x 8 ft workstations (65 in spine panels,
53 in side panels, 29 in worksurfaces), lateral files and a copier along the
spine, a perimeter of black night glass with mini blinds, and the core on the
west: the suite door, an electrical closet and the stair door (the exit).

Light (L.U.C.I.D. units): every troffer lens is an emitter of its real
luminance (Lucid troffer_t8_3lamp, 6020 lm x LLF 0.85, Lambertian over
1.22 x 0.61 m: 2190 cd/m2), stored in the game's engine unit (cd/m2 /
153.6), so the bake is illuminance / pi in the same unit as the Backrooms'
L.U.C.I.D. bake. The 15 troffer columns are 15 switched banks; bank k is in
light group k % 4 and the level's shader picks, per pixel, the nearest bank
of each group (assets/levels/office/office_lit.gdshader), so 15 banks switch
separately with four group channels. Always on (colour bake): the exit
signs, one night-light troffer by the stair, the stairwell's wall pack.

Two kits (office_west, office_east: one 1024 px lightmap each); each is
baked with the other in the scene, so light and shadow cross the seam.

Run:
  /tmp/claude-0/bpyenv/bin/python tools/blender/levels/office.py [out] [--fast] [--samples N]
  python3 tools/blender/levels/office.py --textures <ambientCG dir>   (textures)
  python3 tools/blender/levels/office.py --sounds                      (audio)
"""
import math
import os
import random
import sys

OUT = sys.argv[1] if len(sys.argv) > 1 and not sys.argv[1].startswith("--") else "assets/levels/office"
IN = 0.0254
FT = 0.3048

# ---------------------------------------------------------------- sizes ---
PLATE_X = 120 * FT          # 36.576 m, east-west (4 bays)
PLATE_Y = 60 * FT           # 18.288 m, north-south (2 bays)
BAY = 30 * FT               # column grid
COL = 24 * IN               # column (concrete, drywall wrapped)
CEIL = 9 * FT               # finished floor to ceiling
TILE = 2 * FT               # T-bar grid module (2 x 2 ft tiles)
TROF = (2 * FT, 4 * FT)     # 2 x 4 troffer (x, y)
TROF_P = 8 * FT             # troffer columns every 8 ft (east-west): the banks
TROF_X0 = 5 * FT            # first column's centre
TROF_ROWS = [TILE * (2 + 5 * j) for j in range(6)]   # every 10 ft north-south
NBANK = 15
CUBE = 8 * FT               # workstation module
SPINE_H = 65 * IN           # spine panel
SIDE_H = 53 * IN            # side / return panels
PANEL_T = 3 * IN
DESK_H = 29 * IN
DESK_D = 30 * IN
RET_D = 24 * IN
SILL = 30 * IN
MULLION = 5 * FT
WALL_T = 0.15
HOLE = (34.44, 8.84)        # the open return grille (centre of a 2 x 2 ft cell)
STAIR_DOOR = (0.0, 15.65)   # centre of the 36 x 84 in stair door, west wall
ELEC_DOOR = (0.0, 3.6)
SUITE_DOOR = (0.0, 9.9)
DOOR_W, DOOR_H = 36 * IN, 84 * IN
SPLIT = 2 * BAY             # west / east kit seam (x)
# Light: L.U.C.I.D. units.
UNIT_NITS = 153.6
LLF = 0.85
TROFFER_LM = 6020.0
LENS_NITS = TROFFER_LM * LLF * 2.0 / (2.0 * math.pi) / (1.2192 * 0.6096)   # I0 / A, Lambertian
LENS_EMIT = LENS_NITS / UNIT_NITS                                        # ~14.3
EXIT_EMIT = 300.0 / UNIT_NITS        # LED exit letters, ~300 cd/m2
WALLPACK_EMIT = 1500.0 * 2.0 / (2 * math.pi) / (0.3 * 0.2) / UNIT_NITS   # 1500 lm stair wall pack lens


def bank_x(k):
    return TROF_X0 + k * TROF_P


# ============================================================ textures ===

def make_textures(src):
    """ambientCG 1K JPGs (src/<Asset>/<Asset>_1K-JPG_*.jpg) -> textures/,
    colour scaled so its linear mean is the measured albedo (SPEC.md)."""
    import numpy as np
    from PIL import Image
    dst = os.path.join(OUT, "textures")
    os.makedirs(dst, exist_ok=True)

    def load(asset, kind):
        return Image.open(os.path.join(src, asset, f"{asset}_1K-JPG_{kind}.jpg"))

    def lin(a):
        return np.power(a / 255.0, 2.2)

    def srgb(a):
        return np.clip(np.power(np.clip(a, 0, 1), 1 / 2.2) * 255.0 + 0.5, 0, 255).astype(np.uint8)

    def albedo(img, target, sat=0.0):
        a = np.asarray(img.convert("RGB"), np.float64)
        la = lin(a)
        grey = la.mean(axis=2, keepdims=True)
        la = grey + (la - grey) * sat
        la = la / la.reshape(-1, 3).mean(axis=0) * np.array(target)
        return Image.fromarray(srgb(la))

    def save(img, name, size, q=88):
        img.resize((size, size), Image.LANCZOS).save(os.path.join(dst, name), quality=q)

    def quarter(img, size):
        """2 x 2 carpet tiles, each turned 90 degrees from its neighbours
        (quarter-turn install): one texture repeat = 2 tiles."""
        h = size // 2
        t = img.resize((h, h), Image.LANCZOS)
        out = Image.new(img.mode, (size, size))
        out.paste(t, (0, 0))
        out.paste(t.rotate(90), (h, 0))
        out.paste(t.rotate(90), (0, h))
        out.paste(t, (h, h))
        return out

    jobs = {
        # name: (asset, linear albedo, size, saturation kept)
        "ceiling_tile": ("OfficeCeiling001", (0.80, 0.80, 0.78), 512, 0.0),
        "wall_paint": ("PaintedPlaster017", (0.62, 0.60, 0.555), 512, 0.0),
        "panel_fabric": ("Fabric030", (0.10, 0.118, 0.155), 512, 0.0),
        "laminate": ("Wood049", (0.40, 0.37, 0.32), 512, 0.0),
    }
    for name, (asset, tgt, size, sat) in jobs.items():
        save(albedo(load(asset, "Color"), tgt, sat), f"{name}_diff.jpg", size)
        save(load(asset, "NormalGL"), f"{name}_nor.jpg", size)
        save(load(asset, "Roughness").convert("L"), f"{name}_rough.jpg", 256)
    # Carpet tiles (quarter turned): dark blue-grey loop pile.
    c = albedo(load("Carpet012", "Color"), (0.068, 0.078, 0.100))
    quarter(c, 512).save(os.path.join(dst, "carpet_diff.jpg"), quality=88)
    n = load("Carpet012", "NormalGL").convert("RGB")
    # (a turned normal map needs its x/y swapped: rebuild the turned tiles)
    na = np.asarray(n.resize((256, 256), Image.LANCZOS), np.float64)
    rot = np.rot90(na, 1).copy()
    rx, ry = rot[:, :, 0].copy(), rot[:, :, 1].copy()
    rot[:, :, 0], rot[:, :, 1] = 255.0 - ry, rx
    out = np.zeros((512, 512, 3))
    out[:256, :256] = na
    out[256:, 256:] = na
    out[:256, 256:] = rot
    out[256:, :256] = rot
    Image.fromarray(out.astype(np.uint8)).save(os.path.join(dst, "carpet_nor.jpg"), quality=88)
    quarter(load("Carpet012", "Roughness").convert("L"), 256).save(os.path.join(dst, "carpet_rough.jpg"), quality=88)
    # Mini blinds (1 in slats, closed): one repeat = 1 m, 40 slats.
    h = 256
    v = np.arange(h) / h * 40.0
    f = v - np.floor(v)
    shade = 0.78 + 0.22 * np.sin(f * math.pi) - 0.35 * (f > 0.93)
    tgt = np.array([0.66, 0.65, 0.62])
    img = np.tile((shade[:, None, None] * tgt[None, None, :]), (1, 64, 1))
    Image.fromarray(srgb(img)).save(os.path.join(dst, "blinds_diff.jpg"), quality=90)
    # Troffer lens: three lamps behind a prismatic lens (seen dim at start-up).
    w, hh = 64, 128
    x = (np.arange(w) + 0.5) / w
    lamps = sum(np.exp(-((x - c0) / 0.07) ** 2) for c0 in (0.25, 0.5, 0.75))
    prof = 0.72 + 0.28 * lamps / lamps.max()
    yv = (np.arange(hh) + 0.5) / hh
    ends = np.clip(np.minimum(yv, 1 - yv) / 0.06, 0, 1) ** 0.5
    rng = np.random.default_rng(7)
    grain = 1.0 + 0.04 * rng.standard_normal((hh, w))
    lens = np.clip(prof[None, :] * (0.85 + 0.15 * ends[:, None]) * grain, 0, 1)
    Image.fromarray(srgb(np.repeat(lens[:, :, None], 3, axis=2))).save(os.path.join(dst, "lens_diff.jpg"), quality=92)
    for fn in os.listdir(dst):
        if fn.endswith(".jpg"):
            write_import(os.path.join(dst, fn), normal=fn.endswith("_nor.jpg"))
    print("textures done")


def write_import(path, normal=False):
    params = {"compress/mode": 2, "compress/normal_map": 1 if normal else 0, "mipmaps/generate": "true",
              "process/fix_alpha_border": "true", "detect_3d/compress_to": 0}
    with open(path + ".import", "w") as f:
        f.write('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n')
        for k, v in params.items():
            f.write(f"{k}={v}\n")


if "--textures" in sys.argv:
    make_textures(sys.argv[sys.argv.index("--textures") + 1])
    sys.exit(0)


# =============================================================== sounds ===
# Real recordings were not available for this level (see SPEC.md), so every
# sound is synthesised here as a documented placeholder: noise shaped in the
# frequency domain (loops are made periodic by construction, so they loop
# without a seam), smooth log-frequency bands instead of resonant filters
# (nothing rings), mains-locked 120 Hz hum where a real ballast hums.

SR = 44100


def make_sounds(dst):
    import subprocess
    import wave
    import numpy as np
    os.makedirs(dst, exist_ok=True)
    rs = np.random.default_rng(6011)

    def band(f, lo, hi, slope=1.0):
        """A smooth band (Gaussian in log frequency), 1 at its centre."""
        f = np.maximum(f, 1.0)
        c = math.sqrt(lo * hi)
        w = max(math.log(hi / lo) / 2.0, 0.05)
        return np.exp(-0.5 * (np.log(f / c) / w) ** 2 / slope)

    def loop_noise(n, shape):
        """Periodic noise of n samples with magnitude spectrum shape(f)."""
        f = np.fft.rfftfreq(n, 1.0 / SR)
        spec = shape(f) * np.exp(2j * math.pi * rs.random(f.size))
        spec[0] = 0
        return np.fft.irfft(spec, n)

    def filt(x, shape):
        """Zero-phase filtering of a one-shot (zero padded)."""
        n = 1 << int(math.ceil(math.log2(len(x) + 4096)))
        f = np.fft.rfftfreq(n, 1.0 / SR)
        y = np.fft.irfft(np.fft.rfft(x, n) * shape(f), n)
        return y[:len(x)]

    def noise(sec):
        return rs.standard_normal(int(sec * SR))

    def env(n, a, d, sustain=0.0):
        t = np.arange(n) / SR
        e = np.minimum(t / max(a, 1e-4), 1.0) * (sustain + (1 - sustain) * np.exp(-np.maximum(t - a, 0) / max(d, 1e-4)))
        return e

    def burst(sec, lo, hi, a, d, gain=1.0):
        x = filt(noise(sec), lambda f: band(f, lo, hi))
        return x / (np.abs(x).max() + 1e-9) * env(len(x), a, d) * gain

    def room(x, t60=0.5, wet=0.3, lp=4000.0):
        """A diffuse tail (exponentially decaying noise), for distance."""
        n = int(t60 * SR)
        ir = rs.standard_normal(n) * np.exp(-6.9 * np.arange(n) / n)
        ir = filt(ir, lambda f: 1.0 / (1.0 + (f / lp) ** 2))
        ir /= np.sqrt((ir ** 2).sum())
        y = np.convolve(x, ir)[:len(x) + n]
        out = np.zeros(len(y))
        out[:len(x)] = x * (1 - wet)
        return out + y * wet

    def place(dst_arr, x, at):
        i = int(at * SR)
        j = min(len(dst_arr), i + len(x))
        dst_arr[i:j] += x[:j - i]

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
        imp = os.path.join(dst, name + ".ogg.import")
        with open(imp, "w") as f:
            f.write('[remap]\n\nimporter="oggvorbisstr"\ntype="AudioStreamOggVorbis"\n\n[params]\n\n'
                    f'loop={"true" if loop else "false"}\nloop_offset=0\nbpm=0\nbeat_count=0\nbar_beats=4\n')

    # A troffer's hum: 120 Hz magnetostriction and its harmonics, a little
    # ballast buzz, breathing slowly (8 s, every partial periodic in it).
    n = 8 * SR
    t = np.arange(n) / SR
    h = hum(n) * (1.0 + 0.08 * np.sin(2 * math.pi * t / 4.0) + 0.05 * np.sin(2 * math.pi * t / 1.6))
    buzz = loop_noise(n, lambda f: band(f, 1500, 6000) * 0.6 + band(f, 100, 400) * 0.4)
    buzz *= 1.0 + 0.6 * np.sin(2 * math.pi * 120 * t) ** 2
    save("hum_loop", h * 0.5 + buzz / np.abs(buzz).max() * 0.35, loop=True)
    # The building's air: VAV boxes and diffusers, broadband, low weighted.
    n = 12 * SR
    air = loop_noise(n, lambda f: 1.0 / np.sqrt(np.maximum(f, 20) / 60.0) / (1.0 + (f / 700.0) ** 2) + 0.6 * band(f, 30, 90))
    save("hvac_loop", air, loop=True)
    # Relay panel: the contactor closing / opening behind the closet door.
    for i in range(3):
        x = np.zeros(int(0.5 * SR))
        place(x, burst(0.06, 900 + 300 * i, 3500, 0.0006, 0.012, 1.0), 0.0)
        place(x, burst(0.2, 60, 220, 0.002, 0.05, 1.3), 0.001)
        place(x, burst(0.05, 1500, 5000, 0.0005, 0.008, 0.5), 0.018 + 0.006 * i)   # armature bounce
        save(f"relay_{i + 1}", room(x, 0.35, 0.35, 3000.0))
    # Tubes going out: the ballast's click and the last of the hum.
    for i in range(2):
        x = np.zeros(int(0.35 * SR))
        place(x, burst(0.03, 2500, 7000, 0.0004, 0.004, 0.7), 0.0)
        place(x, burst(0.08, 150, 600, 0.001, 0.02, 0.6), 0.002)
        hh = hum(int(0.25 * SR)) * env(int(0.25 * SR), 0.001, 0.05) * 0.3
        place(x, hh, 0.0)
        save(f"tube_off_{i + 1}", x)
    # Programmed-start ballast: ~1.1 s of cathode preheat (a faint rising
    # buzz), then the three lamps strike one after another (a tick and the
    # hum stepping up), as the 1.0-1.5 s catalogue figure.
    for i in range(2):
        L = 2.2
        x = np.zeros(int(L * SR))
        pre = filt(noise(1.15), lambda f: band(f, 800, 4000)) * np.linspace(0.05, 0.4, int(1.15 * SR)) ** 1.5
        pre *= 1.0 + 0.8 * np.sin(2 * math.pi * 120 * np.arange(len(pre)) / SR) ** 2
        place(x, pre / np.abs(pre).max() * 0.25, 0.0)
        for k, at in enumerate((1.12, 1.19 + 0.05 * i, 1.33)):
            place(x, burst(0.03, 2000, 8000, 0.0004, 0.003, 0.8), at)
            hh = hum(int((L - at) * SR)) * env(int((L - at) * SR), 0.01, 0.35, 0.25) * 0.12
            place(x, hh, at)
        save(f"ballast_start_{i + 1}", x)
    # A failing lamp's zaps (one per flicker pulse).
    for i in range(3):
        d = 0.05 + 0.03 * i
        z = hum(int(d * SR), amps=(0.4, 0.6, 0.5, 0.4, 0.3, 0.2)) + filt(noise(d), lambda f: band(f, 1200, 6000)) * 0.6
        z *= env(len(z), 0.002, d * 0.5)
        save(f"zap_{i + 1}", z)
    # A desk phone ringing in an empty office somewhere: two alternating
    # tones (a 20 Hz warble), harmonics rolled off, heard through the room.
    L = 1.5
    tt = np.arange(int(L * SR)) / SR
    sel = (np.floor(tt * 20) % 2)
    f = np.where(sel > 0, 1020.0, 1310.0)
    ph = 2 * math.pi * np.cumsum(f) / SR
    tone = np.tanh(2.5 * np.sin(ph)) * env(len(tt), 0.01, 10.0, 1.0)
    tone[int(1.2 * SR):] *= np.exp(-np.arange(len(tone) - int(1.2 * SR)) / (0.02 * SR))
    tone = filt(tone, lambda f: 1.0 / (1.0 + (f / 1800.0) ** 4) * (1.0 - band(f, 20, 120)))
    save("phone_ring", room(np.concatenate([tone, np.zeros(int(0.4 * SR))]), 0.9, 0.55, 2500.0))
    # A laser printer warming up: fuser relay, fan spin-up, the gear train,
    # a pick-roller clunk and a sheet through.
    L = 7.0
    x = np.zeros(int(L * SR))
    place(x, burst(0.2, 60, 250, 0.002, 0.04, 0.8), 0.0)
    fan = filt(noise(6.0), lambda f: band(f, 150, 900))
    fan *= np.minimum(np.arange(len(fan)) / (1.8 * SR), 1.0) * np.exp(-np.maximum(np.arange(len(fan)) - 4.5 * SR, 0) / SR)
    place(x, fan / np.abs(fan).max() * 0.4, 0.2)
    gear = filt(noise(3.0), lambda f: band(f, 300, 2500))
    gear *= (1 + 0.7 * np.sin(2 * math.pi * 47 * np.arange(len(gear)) / SR)) * env(len(gear), 0.3, 10.0, 1.0)
    gear[-int(0.3 * SR):] *= np.linspace(1, 0, int(0.3 * SR))
    place(x, gear / np.abs(gear).max() * 0.35, 2.0)
    place(x, burst(0.12, 200, 1500, 0.001, 0.03, 0.9), 3.1)
    sheet = filt(noise(0.9), lambda f: band(f, 1500, 7000)) * np.sin(np.linspace(0, math.pi, int(0.9 * SR)))
    place(x, sheet / np.abs(sheet).max() * 0.35, 3.3)
    save("printer_start", room(x, 0.6, 0.4, 5000.0))
    # A task chair rolling on carpet by itself: casters rumbling and
    # slowing (2.6 s), a creak of the seat as it starts.
    L = 2.8
    nn = int(L * SR)
    tt = np.arange(nn) / SR
    v = np.maximum(0.9 - 0.36 * tt, 0) / 0.9
    rum = filt(noise(L), lambda f: band(f, 70, 500)) * v
    tick = np.zeros(nn)
    rot = np.cumsum(v) / SR * 5.0          # caster revolutions
    tick += (np.abs(np.sin(math.pi * rot)) > 0.995) * 1.0
    tick = filt(tick, lambda f: band(f, 600, 3000)) * 0.6
    creak = filt(noise(0.5), lambda f: band(f, 350, 1200, 0.5)) * env(int(0.5 * SR), 0.08, 0.15)
    x = rum / np.abs(rum).max() + tick / (np.abs(tick).max() + 1e-9) * 0.25
    place(x, creak / np.abs(creak).max() * 0.5, 0.02)
    save("chair_roll", x)
    # A monitor waking: its relay, a breath of hiss from the backlight.
    x = np.zeros(int(0.8 * SR))
    place(x, burst(0.04, 1500, 6000, 0.0005, 0.006, 0.8), 0.0)
    hiss = filt(noise(0.6), lambda f: band(f, 5000, 12000)) * env(int(0.6 * SR), 0.05, 0.25) * 0.12
    place(x, hiss / np.abs(hiss).max() * 0.12, 0.05)
    save("monitor_wake", x)
    # The stair door: panic bar, latch, hinges, the stairwell's air.
    x = np.zeros(int(1.6 * SR))
    place(x, burst(0.1, 400, 2500, 0.0006, 0.02, 1.0), 0.0)
    place(x, burst(0.2, 70, 300, 0.002, 0.06, 1.0), 0.004)
    place(x, burst(0.05, 2000, 6000, 0.0005, 0.008, 0.5), 0.06)
    whoosh = filt(noise(1.3), lambda f: band(f, 100, 1500)) * np.sin(np.linspace(0, math.pi, int(1.3 * SR))) ** 2
    place(x, whoosh / np.abs(whoosh).max() * 0.45, 0.15)
    save("door_open", room(x, 0.7, 0.3, 4000.0))
    # Grit and fibre falling from the open grille (arrival).
    x = np.zeros(int(3.0 * SR))
    for k in range(70):
        at = rs.random() ** 2 * 2.6
        place(x, burst(0.01, 2500, 9000, 0.0003, 0.002, rs.uniform(0.1, 1.0) * (1 - at / 3.0)), at)
    save("debris", x)
    print("sounds done")


if "--sounds" in sys.argv:
    make_sounds(os.path.join(OUT, "audio"))
    sys.exit(0)

# ================================================================= bake ===
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import bpy  # noqa: E402
import level_kit as K  # noqa: E402
from mathutils import Matrix  # noqa: E402

K.reset()
# Measured / catalogue albedos (linear), as the textures' means (SPEC.md).
K.material("carpet", (0.068, 0.078, 0.100), rough=0.95)
K.material("ceiling_tile", (0.80, 0.80, 0.78), rough=0.95)
K.material("wall_paint", (0.62, 0.60, 0.555), rough=0.9)
K.material("base", (0.05, 0.05, 0.05), rough=0.8)
K.material("panel_fabric", (0.10, 0.118, 0.155), rough=0.95)
K.material("panel_trim", (0.30, 0.30, 0.29), rough=0.5)
K.material("laminate", (0.40, 0.37, 0.32), rough=0.5)
K.material("desk_metal", (0.10, 0.10, 0.10), rough=0.5, metal=0.3)
K.material("pedestal", (0.33, 0.32, 0.30), rough=0.5)
K.material("monitor", (0.025, 0.025, 0.027), rough=0.35)
K.material("screen", (0.012, 0.012, 0.014), rough=0.1)
K.material("keyboard", (0.03, 0.03, 0.03), rough=0.6)
K.material("chair_fabric", (0.035, 0.035, 0.04), rough=0.95)
K.material("chair_base", (0.04, 0.04, 0.04), rough=0.4)
K.material("troffer_frame", (0.80, 0.80, 0.78), rough=0.5)
K.material("grille", (0.80, 0.80, 0.78), rough=0.5)
K.material("grille_dark", (0.02, 0.02, 0.02), rough=0.9)
K.material("galv", (0.45, 0.46, 0.47), rough=0.5, metal=0.3)
K.material("exit_housing", (0.80, 0.80, 0.78), rough=0.5)
K.material("exit_led", (1.0, 0.04, 0.02), emit=EXIT_EMIT)
K.material("door_steel", (0.30, 0.31, 0.30), rough=0.45)
K.material("door_wood", (0.30, 0.20, 0.12), rough=0.5)
K.material("door_frame", (0.20, 0.20, 0.20), rough=0.45, metal=0.3)
K.material("hardware", (0.55, 0.55, 0.53), rough=0.3, metal=0.9)
K.material("glass_window", (0.02, 0.025, 0.03), rough=0.05)
K.material("mullion", (0.035, 0.032, 0.03), rough=0.35, metal=0.5)
K.material("sill", (0.45, 0.44, 0.42), rough=0.4)
K.material("convector", (0.52, 0.50, 0.46), rough=0.5)
K.material("convector_grille", (0.03, 0.03, 0.03), rough=0.7)
K.material("blinds", (0.66, 0.65, 0.62), rough=0.6)
K.material("cabinet", (0.33, 0.32, 0.30), rough=0.5, metal=0.2)
K.material("copier", (0.55, 0.54, 0.51), rough=0.5)
K.material("copier_dark", (0.05, 0.05, 0.05), rough=0.5)
K.material("paper", (0.80, 0.80, 0.78), rough=0.9)
K.material("floor_box", (0.30, 0.29, 0.27), rough=0.4, metal=0.7)
K.material("concrete", (0.35, 0.34, 0.32), rough=0.9)
K.material("cmu_paint", (0.55, 0.54, 0.50), rough=0.9)
K.material("stair_steel", (0.12, 0.12, 0.12), rough=0.6, metal=0.4)
K.material("sign_plate", (0.08, 0.08, 0.09), rough=0.5)
K.material("sprinkler", (0.85, 0.84, 0.80), rough=0.4, metal=0.5)
K.material("bin", (0.06, 0.06, 0.06), rough=0.6)
K.material("bin_blue", (0.02, 0.06, 0.16), rough=0.6)
for g in range(4):
    K.material(f"lamp_g{g}", (1.0, 1.0, 1.0), emit=LENS_EMIT, group=g)
K.material("lamp_night", (1.0, 1.0, 1.0), emit=LENS_EMIT)
K.material("wallpack", (1.0, 1.0, 1.0), emit=WALLPACK_EMIT)

west = K.Kit("office_west")
east = K.Kit("office_east")
rng = random.Random(4100)


def kb(x):
    """The builder for something centred at x."""
    return west.b if x < SPLIT else east.b


def kit_of(x):
    return west if x < SPLIT else east


def col(size, loc, rz=0.0):
    kit_of(loc[0]).col(size, loc, rz)


def rect_floor(b, x0, y0, x1, y1, z, m, up=True):
    c = ((x0 + x1) / 2, (y0 + y1) / 2, z + (1 if up else -1))
    b.oquad([(x0, y0, z), (x1, y0, z), (x1, y1, z), (x0, y1, z)], m, c)


# ---------------------------------------------------------- shell ---

def shell():
    for kit, x0, x1 in ((west, 0.0, SPLIT), (east, SPLIT, PLATE_X)):
        b = kit.b
        rect_floor(b, x0, 0, x1, PLATE_Y, 0.0, "carpet")
        # Ceiling, with the open grille cell left out.
        hx0, hx1 = HOLE[0] - TILE / 2, HOLE[0] + TILE / 2
        hy0, hy1 = HOLE[1] - TILE / 2, HOLE[1] + TILE / 2
        if x0 <= HOLE[0] < x1:
            rect_floor(b, x0, 0, hx0, PLATE_Y, CEIL, "ceiling_tile", up=False)
            rect_floor(b, hx1, 0, x1, PLATE_Y, CEIL, "ceiling_tile", up=False)
            rect_floor(b, hx0, 0, hx1, hy0, CEIL, "ceiling_tile", up=False)
            rect_floor(b, hx0, hy1, hx1, PLATE_Y, CEIL, "ceiling_tile", up=False)
        else:
            rect_floor(b, x0, 0, x1, PLATE_Y, CEIL, "ceiling_tile", up=False)
        kit.col((x1 - x0, PLATE_Y, 0.2), ((x0 + x1) / 2, PLATE_Y / 2, -0.1))
        kit.col((x1 - x0, PLATE_Y, 0.2), ((x0 + x1) / 2, PLATE_Y / 2, CEIL + 0.1))
    # Columns (interior) on the 30 ft grid, with rubber base.
    for i in (1, 2, 3):
        x, y = i * BAY, BAY
        b = kb(x)
        b.box((COL, COL, CEIL), (x, y, CEIL / 2), "wall_paint")
        b.box((COL + 0.006, COL + 0.006, 0.1016), (x, y, 0.0508), "base")
        col((COL, COL, CEIL), (x, y, CEIL / 2))
    west_core()
    for side in ("S", "N", "E"):
        perimeter(side)


def door_opening_wall(b, y_ops, x=0.0):
    """The west core wall (inner face at x) with openings [(y0, y1, head)]."""
    ys = [0.0]
    for y0, y1, _h in y_ops:
        ys += [y0, y1]
    ys.append(PLATE_Y)
    for i in range(0, len(ys), 2):
        a, c = ys[i], ys[i + 1]
        if c - a > 0.01:
            b.box((WALL_T, c - a, CEIL), (x - WALL_T / 2, (a + c) / 2, CEIL / 2), "wall_paint")
            b.box((0.006, c - a, 0.1016), (x + 0.003, (a + c) / 2, 0.0508), "base")
            col((WALL_T, c - a, CEIL + 0.2), (x - WALL_T / 2, (a + c) / 2, CEIL / 2))
    for y0, y1, h in y_ops:
        b.box((WALL_T, y1 - y0, CEIL - h), (x - WALL_T / 2, (y0 + y1) / 2, (CEIL + h) / 2), "wall_paint")
        col((WALL_T, y1 - y0, CEIL - h), (x - WALL_T / 2, (y0 + y1) / 2, (CEIL + h) / 2))


def door_frame(b, yc, w=DOOR_W, h=DOOR_H):
    """A hollow-metal frame (2 in face) round an opening in the west wall."""
    f = 2 * IN
    for s in (-1, 1):
        b.box((WALL_T + 0.03, f, h + f), (-WALL_T / 2 + 0.0, yc + s * (w / 2 + f / 2), (h + f) / 2), "door_frame")
    b.box((WALL_T + 0.03, w + 2 * f, f), (-WALL_T / 2, yc, h + f / 2), "door_frame")


def exit_sign(b, loc, faces=(1,), centered=False):
    """An LED exit sign (12 x 7.5 in housing), EXIT in 6 in letters with a
    3/4 in stroke, on its +x face (faces: +1 / -1 for the +x / -x faces);
    `centered`: hung on a stem at loc (double faced), else on a wall at x."""
    x, y, z = loc
    hw, hh, hd = 12 * IN, 7.5 * IN, 2 * IN
    b.box((hd, hw, hh), (x if centered else x + hd / 2, y, z), "exit_housing")
    lh, st, lw, gap = 6 * IN, 0.75 * IN, 2.2 * IN, 0.5 * IN
    total = 3 * lw + st + 3 * gap
    u0 = -total / 2
    for f in faces:
        xf = (x + f * hd / 2 if centered else x + hd) + f * 0.002

        def seg(u, v, du, dv, rot=0.0):
            b.box((0.004, du, dv), (xf, y + f * u, z + v), "exit_led", rot=(f * rot, 0, 0))
        seg(u0 + st / 2, 0, st, lh)                       # E
        for v in (-lh / 2 + st / 2, 0, lh / 2 - st / 2):
            seg(u0 + lw / 2, v, lw, st)
        u = u0 + lw + gap + lw / 2                        # X
        ang = math.atan2(lh, lw)
        for sg in (1, -1):
            seg(u, 0, st, math.hypot(lw, lh) * 0.92, rot=sg * (math.pi / 2 - ang))
        seg(u0 + 2 * lw + 2 * gap + st / 2, 0, st, lh)    # I
        u = u0 + 2 * lw + 3 * gap + st + lw / 2           # T
        seg(u, lh / 2 - st / 2, lw, st)
        seg(u, 0, st, lh)


def west_core():
    b = west.b
    ops = sorted([(SUITE_DOOR[1] - DOOR_W / 2, SUITE_DOOR[1] + DOOR_W / 2 + 0.45, DOOR_H),
                  (ELEC_DOOR[1] - DOOR_W / 2, ELEC_DOOR[1] + DOOR_W / 2, DOOR_H),
                  (STAIR_DOOR[1] - DOOR_W / 2, STAIR_DOOR[1] + DOOR_W / 2, DOOR_H)])
    door_opening_wall(b, ops)
    # Suite entry: wood door (closed) with a 12 in glass sidelite.
    yc = SUITE_DOOR[1]
    door_frame(b, yc + 0.225, w=DOOR_W + 0.45)
    b.box((0.045, DOOR_W - 0.01, DOOR_H - 0.01), (-0.06, yc, DOOR_H / 2), "door_wood")
    b.box((0.03, 0.4, DOOR_H - 0.05), (-0.07, yc + DOOR_W / 2 + 0.225, DOOR_H / 2), "glass_window")
    b.box((0.02, 0.15, 0.025), (0.0, yc + DOOR_W / 2 - 0.1, 1.0), "hardware")
    b.box((0.012, 0.012, 0.12), (-0.03, yc + DOOR_W / 2 - 0.05, 1.0), "hardware")
    b.box((0.03, 0.4, 0.16), (-0.02, yc, DOOR_H + 0.25), "sign_plate")     # suite number plate
    col((0.2, DOOR_W + 0.45, DOOR_H), (-0.07, yc + 0.225, DOOR_H / 2))
    # Electrical closet: steel door, closed.
    yc = ELEC_DOOR[1]
    door_frame(b, yc)
    b.box((0.045, DOOR_W - 0.01, DOOR_H - 0.01), (-0.06, yc, DOOR_H / 2), "door_steel")
    b.box((0.03, 0.14, 0.03), (0.0, yc + DOOR_W / 2 - 0.12, 1.0), "hardware")
    b.box((0.012, 0.26, 0.09), (-0.03, yc, 1.6), "sign_plate")
    col((0.2, DOOR_W, DOOR_H), (-0.07, yc, DOOR_H / 2))
    # Stair door: the frame here; the leaf (it opens) is the level's own.
    yc = STAIR_DOOR[1]
    door_frame(b, yc)
    b.box((0.012, 0.3, 0.2), (-0.0, yc + DOOR_W / 2 + 0.3, 1.52), "sign_plate")   # stair ID sign
    exit_sign(b, (0.0, yc, DOOR_H + 0.22))
    # Behind it: the stair landing (concrete, painted block, steel stairs
    # down and up) lit by an always-on wall pack.
    sx0, sx1, sy0, sy1 = -3.2, -WALL_T, yc - 2.2, yc + 1.6
    rect_floor(b, sx0, sy0, sx1, sy1, 0.0, "concrete")
    rect_floor(b, sx0, sy0, sx1, sy1, 3.2, "concrete", up=False)
    c = ((sx0 + sx1) / 2, (sy0 + sy1) / 2, 1.5)
    b.oquad([(sx0, sy0, 0), (sx1, sy0, 0), (sx1, sy0, 3.2), (sx0, sy0, 3.2)], "cmu_paint", c)
    b.oquad([(sx0, sy1, 0), (sx1, sy1, 0), (sx1, sy1, 3.2), (sx0, sy1, 3.2)], "cmu_paint", c)
    b.oquad([(sx0, sy0, 0), (sx0, sy1, 0), (sx0, sy1, 3.2), (sx0, sy0, 3.2)], "cmu_paint", c)
    for i in range(6):      # the flight down, 7 in risers, 11 in treads
        b.box((1.1, 0.279, 0.04), (sx0 + 0.6, sy0 + 0.2 + 1.5 - i * 0.279, -0.178 * (i + 1) + 0.0), "stair_steel")
    for i in range(6):      # and up
        b.box((1.1, 0.279, 0.04), (sx0 + 1.75, sy0 + 0.2 + i * 0.279, 0.178 * (i + 1)), "stair_steel")
    b.tube([(sx0 + 1.2, sy0 + 0.1, 0.9), (sx0 + 1.2, sy0 + 1.9, 0.9 + 6 * 0.178)], 0.02, "stair_steel")
    b.box((0.3, 0.12, 0.2), (sx0 + 0.06, (sy0 + sy1) / 2, 2.4), "door_frame", rot=(0, 0, math.pi / 2))
    b.box((0.012, 0.28, 0.18), (sx0 + 0.12, (sy0 + sy1) / 2, 2.4), "wallpack")
    b.box((0.012, 0.45, 0.3), (sx0 + 0.006, sy0 + 2.6, 1.6), "sign_plate")       # floor number


def perimeter(side):
    """Window wall: spandrel to a 30 in sill, convector enclosure, glass to
    the ceiling on a 5 ft mullion module, perimeter columns, mini blinds."""
    if side in ("S", "N"):
        n = int(round(PLATE_X / MULLION))
        y = 0.0 if side == "S" else PLATE_Y
        inward = 1 if side == "S" else -1
        for i in range(n):
            x0, x1 = i * MULLION, (i + 1) * MULLION
            module(kb((x0 + x1) / 2), (x0, y), (x1, y), inward, "y")
        for i in range(5):
            x = i * BAY
            pil(kb(min(max(x, 0.3), PLATE_X - 0.3)), x, y, inward, "y")
        for kit, x0, x1 in ((west, 0, SPLIT), (east, SPLIT, PLATE_X)):
            kit.col((x1 - x0, 0.5, CEIL), ((x0 + x1) / 2, y + inward * 0.15, CEIL / 2))
    else:
        n = int(round(PLATE_Y / MULLION))
        x = PLATE_X
        for i in range(n):
            y0, y1 = i * MULLION, (i + 1) * MULLION
            module(east.b, (x, y0), (x, y1), -1, "x")
        pil(east.b, x, BAY, -1, "x")
        east.col((0.5, PLATE_Y, CEIL), (x - 0.15, PLATE_Y / 2, CEIL / 2))


def module(b, a, c, inward, axis):
    """One 5 ft window module from a to c (on the wall line)."""
    if axis == "y":
        (x0, y), (x1, _y) = a, c
        L = x1 - x0
        xm = (x0 + x1) / 2

        def P(u, d, z):     # u along, d inward from the wall line
            return (x0 + u, y + inward * d, z)
        b.box((L, 0.12, SILL), (xm, y - inward * 0.06 + inward * 0.12, SILL / 2), "wall_paint")
        b.box((L, 0.22, 0.02), (xm, y + inward * 0.12, SILL + 0.01), "sill")
        b.box((L, 0.2, SILL - 0.12), (xm, y + inward * 0.30, (SILL - 0.12) / 2 + 0.0), "convector")
        b.box((L - 0.04, 0.12, 0.004), (xm, y + inward * 0.30, SILL - 0.12 + 0.002), "convector_grille")
        b.box((L, 0.006, 0.1016), (xm, y + inward * 0.403, 0.0508), "base")
        b.box((L, 0.02, CEIL - SILL + 0.1), (xm, y - inward * 0.02, (CEIL + SILL) / 2), "glass_window")
        b.box((0.064, 0.12, CEIL - SILL), (x0 + 0.0, y + inward * 0.03, (CEIL + SILL) / 2), "mullion")
        b.box((L, 0.1, 0.05), (xm, y + inward * 0.03, SILL + 0.045), "mullion")
        blind(b, P, L, inward, axis)
    else:
        (x, y0), (_x, y1) = a, c
        L = y1 - y0
        ym = (y0 + y1) / 2
        b.box((0.12, L, SILL), (x + inward * 0.06, ym, SILL / 2), "wall_paint")
        b.box((0.22, L, 0.02), (x + inward * 0.12, ym, SILL + 0.01), "sill")
        b.box((0.2, L, SILL - 0.12), (x + inward * 0.30, ym, (SILL - 0.12) / 2), "convector")
        b.box((0.12, L - 0.04, 0.004), (x + inward * 0.30, ym, SILL - 0.12 + 0.002), "convector_grille")
        b.box((0.006, L, 0.1016), (x + inward * 0.403, ym, 0.0508), "base")
        b.box((0.02, L, CEIL - SILL + 0.1), (x - inward * 0.02, ym, (CEIL + SILL) / 2), "glass_window")
        b.box((0.12, 0.064, CEIL - SILL), (x + inward * 0.03, y0, (CEIL + SILL) / 2), "mullion")
        b.box((0.1, L, 0.05), (x + inward * 0.03, ym, SILL + 0.045), "mullion")

        def P(u, d, z):
            return (x + inward * d, y0 + u, z)
        blind(b, P, L, inward, axis)


def blind(b, P, L, inward, axis):
    r = rng.random()
    if r < 0.45:            # raised: the stack under the head rail
        drop = CEIL - 0.12
    elif r < 0.8:           # all the way down, slats closed
        drop = SILL + 0.06
    else:
        drop = rng.uniform(1.3, 2.2)
    d = 0.09
    ctr = P(L / 2, d, 0)
    corners = [P(0.03, d, drop), P(L - 0.03, d, drop), P(L - 0.03, d, CEIL - 0.04), P(0.03, d, CEIL - 0.04)]
    if drop < CEIL - 0.15:
        b.oquad(corners, "blinds", (ctr[0] + (inward if axis == "x" else 0), ctr[1] + (inward if axis == "y" else 0), 1.5))
    hx = (L - 0.04, 0.03) if axis == "y" else (0.03, L - 0.04)
    p = P(L / 2, d, drop - 0.012)
    b.box((hx[0], hx[1], 0.025 if drop < CEIL - 0.15 else 0.09), p, "blinds")
    p = P(L / 2, d, CEIL - 0.025)
    b.box((hx[0], hx[1] + 0.01, 0.04), p, "mullion")


def pil(b, x, y, inward, axis):
    if axis == "y":
        b.box((COL, 0.36, CEIL), (min(max(x, COL / 2), PLATE_X - COL / 2), y + inward * 0.18, CEIL / 2), "wall_paint")
    else:
        b.box((0.36, COL, CEIL), (x + inward * 0.18, y, CEIL / 2), "wall_paint")


# --------------------------------------------------------- ceiling ---

def ceiling():
    for k in range(NBANK):
        x = bank_x(k)
        for j, y in enumerate(TROF_ROWS):
            b = kb(x)
            night = (k == 0 and j == len(TROF_ROWS) - 1)
            m = "lamp_night" if night else f"lamp_g{k % 4}"
            b.box((TROF[0], TROF[1], 0.012), (x, y, CEIL - 0.006), "troffer_frame")
            b.box((TROF[0] - 0.05, TROF[1] - 0.05, 0.004), (x, y, CEIL - 0.0125), m)
    # Supply diffusers (24 x 24 in, square cone) and return grilles in
    # tiles between the troffers; sprinkler heads on a ~12 ft grid.
    for i in range(14):
        for j in range(3):
            cx = bank_x(i) + TROF_P / 2
            cy = TROF_ROWS[2 * j] + 1.524 + 0.0
            if abs(cx - HOLE[0]) < 1.0 and abs(cy - HOLE[1]) < 1.0:
                continue
            b = kb(cx)
            if (i + j) % 3 == 0:            # return: perforated face
                b.box((0.6, 0.6, 0.006), (cx, cy, CEIL - 0.003), "grille")
                b.box((0.5, 0.5, 0.002), (cx, cy, CEIL - 0.0065), "grille_dark")
            else:                           # supply: nested square cones
                for r, m in ((0.6, "grille"), (0.44, "grille_dark"), (0.40, "grille"), (0.26, "grille_dark"),
                             (0.22, "grille")):
                    b.box((r, r, 0.004 + (0.6 - r) * 0.04), (cx, cy, CEIL - 0.002 - (0.6 - r) * 0.02), m)
    for i in range(10):
        for j in range(5):
            x, y = 1.8 + i * 3.66, 1.8 + j * 3.66
            b = kb(x)
            b.cyl(0.03, 0.03, 0.006, (x, y, CEIL - 0.003), "sprinkler", segs=6)
            b.cyl(0.018, 0.012, 0.045, (x, y, CEIL - 0.028), "sprinkler", segs=5)
    # Exit signs hung in the spine (double faced, toward the stair).
    for x in (12.0, 26.0):
        b = kb(x)
        b.box((0.01, 0.01, 0.25), (x, BAY + 1.2, CEIL - 0.125), "hardware")
        exit_sign(b, (x, BAY + 1.2, CEIL - 0.34), faces=(1, -1), centered=True)
    open_grille()


def open_grille():
    """The return grille you came through: a 2 x 2 ft hole in the grid, its
    neck up into the dark duct, the grille lying on the carpet."""
    b = east.b
    x, y = HOLE
    h = TILE / 2
    t = 15 / 16 * IN
    for s in (-1, 1):                       # T-bar flanges round the hole
        b.box((TILE + t, t, 0.035), (x, y + s * h, CEIL + 0.012), "grille")
        b.box((t, TILE + t, 0.035), (x + s * h, y, CEIL + 0.012), "grille")
    top = CEIL + 0.3
    c = (x, y, CEIL + 0.15)
    s0 = h - 0.02
    for (ax, ay), (bx_, by) in (((-1, -1), (1, -1)), ((1, -1), (1, 1)), ((1, 1), (-1, 1)), ((-1, 1), (-1, -1))):
        b.oquad([(x + ax * s0, y + ay * s0, CEIL + 0.02), (x + bx_ * s0, y + by * s0, CEIL + 0.02),
                 (x + bx_ * s0, y + by * s0, top), (x + ax * s0, y + ay * s0, top)], "galv", c)
    # The trunk above (36 x 30 in inside), seen through the neck.
    dw, dh = 18 * IN, 30 * IN
    y0, y1 = y - 3.0, y + 3.0
    cc = (x, y, top + dh / 2)
    b.oquad([(x - dw, y0, top + dh), (x + dw, y0, top + dh), (x + dw, y1, top + dh), (x - dw, y1, top + dh)], "galv", cc)
    for sx in (-1, 1):
        b.oquad([(x + sx * dw, y0, top), (x + sx * dw, y1, top), (x + sx * dw, y1, top + dh), (x + sx * dw, y0, top + dh)],
                "galv", cc)
    for (a0, a1, b0, b1) in ((x - dw, x + dw, y0, y - s0), (x - dw, x + dw, y + s0, y1), (x - dw, x - s0, y - s0, y + s0),
                             (x + s0, x + dw, y - s0, y + s0)):
        b.oquad([(a0, b0, top), (a1, b0, top), (a1, b1, top), (a0, b1, top)], "galv", cc)
    for yy in (y0, y1):
        b.oquad([(x - dw, yy, top), (x + dw, yy, top), (x + dw, yy, top + dh), (x - dw, yy, top + dh)], "grille_dark", cc)
    # The grille on the carpet, face up, beside where you landed.
    g = K.Builder()
    g.box((0.62, 0.62, 0.006), (0, 0, 0.028), "grille")
    for s in (-1, 1):
        g.box((0.62, 0.035, 0.03), (0, s * 0.2925, 0.015), "grille")
        g.box((0.035, 0.62, 0.03), (s * 0.2925, 0, 0.015), "grille")
    b.place(g, Matrix.Translation((x - 0.85, y - 0.38, 0.0)) @ Matrix.Rotation(0.42, 4, "Z")
            @ Matrix.Rotation(math.pi, 4, "X") @ Matrix.Translation((0, 0, -0.032)))
    # (upside down: you see its back, the frame and the louvre blades)
    lb = K.Builder()
    for i in range(12):
        lb.box((0.55, 0.012, 0.025), (0, -0.264 + i * 0.048, 0.016), "grille", rot=(0.7, 0, 0))
    b.place(lb, Matrix.Translation((x - 0.85, y - 0.38, 0.0)) @ Matrix.Rotation(0.42, 4, "Z"))


# ------------------------------------------------------- furniture ---

def chair_builder():
    c = K.Builder()
    for i in range(5):
        a = i * 2 * math.pi / 5
        c.box((0.30, 0.04, 0.03), (math.cos(a) * 0.15, math.sin(a) * 0.15, 0.07), "chair_base", rot=(0, 0, a))
        c.box((0.04, 0.03, 0.045), (math.cos(a) * 0.30, math.sin(a) * 0.30, 0.0225), "chair_base", rot=(0, 0, a))
    c.cyl(0.045, 0.04, 0.06, (0, 0, 0.09), "chair_base", segs=6, caps=False)
    c.cyl(0.024, 0.024, 0.30, (0, 0, 0.26), "hardware", segs=6, caps=False)
    c.box((0.2, 0.22, 0.05), (0, 0, 0.405), "chair_base")
    c.box((0.50, 0.48, 0.08), (0, 0.02, 0.47), "chair_fabric", bevel=0.025)
    c.box((0.06, 0.035, 0.32), (0, -0.25, 0.56), "chair_base", rot=(0.1, 0, 0))
    c.box((0.46, 0.07, 0.52), (0, -0.29, 0.86), "chair_fabric", rot=(0.14, 0, 0), bevel=0.025)
    for s in (-1, 1):
        c.box((0.03, 0.05, 0.2), (s * 0.27, -0.02, 0.56), "chair_base")
        c.box((0.07, 0.25, 0.025), (s * 0.27, 0.0, 0.67), "chair_base")
    return c


def monitor_builder(screen="screen"):
    m = K.Builder()
    m.box((0.22, 0.18, 0.015), (0, 0, 0.0075), "monitor")
    m.box((0.05, 0.025, 0.30), (0, -0.045, 0.16), "monitor")
    m.box((0.541, 0.035, 0.323), (0, -0.02, 0.36), "monitor")
    m.box((0.527, 0.002, 0.297), (0, -0.0015, 0.365), screen)
    return m


CHAIR = None
MONITOR = None
SKIP_CHAIR = set()      # cubicles whose chair is the level's own (it rolls)
SKIP_MONITOR = set()    # ... and whose monitor wakes
SPECIAL = {}            # cubicle index -> its transform (for the level)


def cubicle(idx, x0, ymid, s, hand):
    """One 8 x 8 ft workstation: x0..x0+8 ft, from the spine (ymid) out to
    ymid + s * 8 ft (the aisle side). hand: which side the return is on."""
    global CHAIR, MONITOR
    if CHAIR is None:
        CHAIR, MONITOR = chair_builder(), monitor_builder()
    xc = x0 + CUBE / 2
    b = kb(xc)
    y_out = ymid + s * CUBE
    pt = PANEL_T / 2
    # Return panels on the aisle side (30 in each side of a 36 in opening).
    for sx in (0, 1):
        xa = x0 + (pt if sx == 0 else CUBE - pt)
        ret = 30 * IN
        xr = xa + (ret / 2 if sx == 0 else -ret / 2)
        b.box((ret, PANEL_T, SIDE_H), (xr, y_out - s * pt, SIDE_H / 2), "panel_fabric")
        b.box((ret, PANEL_T + 0.006, 0.02), (xr, y_out - s * pt, SIDE_H + 0.01), "panel_trim")
        col((ret, PANEL_T, SIDE_H), (xr, y_out - s * pt, SIDE_H / 2))
    # Worksurfaces: 30 in deep along the spine, a 24 in deep return.
    yd = ymid + s * (pt + DESK_D / 2)
    w = CUBE - PANEL_T - 0.02
    b.box((w, DESK_D, 0.03), (xc, yd, DESK_H - 0.015), "laminate")
    b.box((w, 0.02, 0.03), (xc, ymid + s * (pt + DESK_D), DESK_H - 0.015), "panel_trim")
    hx = x0 + (pt + RET_D / 2 + 0.01 if hand < 0 else CUBE - pt - RET_D / 2 - 0.01)
    rl = 48 * IN
    yr = ymid + s * (pt + DESK_D + rl / 2)
    b.box((RET_D, rl, 0.03), (hx, yr, DESK_H - 0.015), "laminate")
    b.box((0.05, 0.05, DESK_H - 0.03), (hx, ymid + s * (pt + DESK_D + rl - 0.05), (DESK_H - 0.03) / 2), "desk_metal")
    col((w, DESK_D, DESK_H), (xc, yd, DESK_H / 2))
    col((RET_D, rl, DESK_H), (hx, yr, DESK_H / 2))
    # Mobile pedestal (15 x 22 x 27.5 in) under the far end.
    px = x0 + (CUBE - 0.4 if hand < 0 else 0.4)
    py = ymid + s * (pt + 0.32)
    b.box((15 * IN, 22 * IN, 27.5 * IN), (px, py, 27.5 * IN / 2 + 0.01), "pedestal")
    for k, zz in enumerate((0.2, 0.42, 0.6)):
        b.box((0.12, 0.006, 0.012), (px, py + s * 0.281, zz), "hardware")
    # Monitor (24 in), keyboard, sometimes papers, a mug; the chair.
    mx = xc + rng.uniform(-0.25, 0.25)
    my = ymid + s * (pt + 0.2)
    rz = 0.0 if s > 0 else math.pi
    if idx not in SKIP_MONITOR:
        b.place(MONITOR, Matrix.Translation((mx, my, DESK_H)) @ Matrix.Rotation(rz + rng.uniform(-0.15, 0.15), 4, "Z"))
    SPECIAL.setdefault("monitor_%d" % idx, (mx, my, DESK_H, rz))
    b.box((0.44, 0.14, 0.022), (mx, my + s * 0.33, DESK_H + 0.011), "keyboard", rot=(0, 0, rng.uniform(-0.1, 0.1)))
    if rng.random() < 0.6:
        for i in range(rng.randint(1, 4)):
            b.box((0.216, 0.279, 0.002 + 0.003 * i),
                  (hx + rng.uniform(-0.05, 0.05), yr + rng.uniform(-0.3, 0.3), DESK_H + 0.001 + 0.003 * i),
                  "paper", rot=(0, 0, rng.uniform(-0.4, 0.4)))
    if rng.random() < 0.4:
        b.cyl(0.04, 0.04, 0.095, (mx + rng.choice((-0.45, 0.45)), my + s * 0.2, DESK_H + 0.048), "paper", segs=10)
    cx = xc + rng.uniform(-0.4, 0.4)
    cy = ymid + s * (pt + DESK_D + rng.uniform(0.25, 0.75))
    crz = rz + math.pi + rng.uniform(-0.9, 0.9)
    if idx not in SKIP_CHAIR:
        b.place(CHAIR, Matrix.Translation((cx, cy, 0.0)) @ Matrix.Rotation(crz, 4, "Z"))
        col((0.55, 0.55, 0.9), (cx, cy, 0.45))
    SPECIAL.setdefault("chair_%d" % idx, (cx, cy, 0.0, crz))
    # A waste bin and a recycling bin under the return; a floor box cover.
    b.cyl(0.13, 0.11, 0.34, (hx, yr + s * 0.35, 0.17), "bin" if rng.random() < 0.6 else "bin_blue", segs=8, caps=False)
    b.box((0.2, 0.2, 0.004), (xc + 0.6, ymid + s * 0.9, 0.002), "floor_box")


def cluster(ci, x0, y0):
    """2 x 3 workstations: x0..x0+24 ft, y0..y0+16 ft, spine along x."""
    ymid = y0 + CUBE
    xc = x0 + 1.5 * CUBE
    b = kb(xc)
    for sx in (0, 1):       # the spine split at the kit seam would be fine; keep it whole per cluster
        pass
    b.box((3 * CUBE, PANEL_T, SPINE_H), (xc, ymid, SPINE_H / 2), "panel_fabric")
    b.box((3 * CUBE, PANEL_T + 0.006, 0.02), (xc, ymid, SPINE_H + 0.01), "panel_trim")
    col((3 * CUBE, PANEL_T, SPINE_H), (xc, ymid, SPINE_H / 2))
    for i in range(4):      # side panels, full depth both sides of the spine
        x = x0 + i * CUBE
        b.box((PANEL_T, 2 * CUBE, SIDE_H), (x, ymid, SIDE_H / 2), "panel_fabric")
        b.box((PANEL_T + 0.006, 2 * CUBE, 0.02), (x, ymid, SIDE_H + 0.01), "panel_trim")
        b.box((PANEL_T + 0.01, 0.05, SIDE_H + 0.02), (x, ymid + CUBE, (SIDE_H + 0.02) / 2), "panel_trim")
        b.box((PANEL_T + 0.01, 0.05, SIDE_H + 0.02), (x, ymid - CUBE, (SIDE_H + 0.02) / 2), "panel_trim")
        col((PANEL_T, 2 * CUBE, SIDE_H), (x, ymid, SIDE_H / 2))
    for r, s in ((0, -1), (1, 1)):
        for i in range(3):
            idx = ci * 6 + r * 3 + i
            cubicle(idx, x0 + i * CUBE, ymid, s, -1 if (i % 2 == 0) else 1)


def spine_furniture():
    """Along the column line in the spine: lateral files, the copier."""
    y = BAY
    for x0, x1 in ((1.6, 4.4), (5.6, 7.9), (10.4, 13.2), (14.4, 17.0), (28.6, 31.4)):
        n = int(round((x1 - x0) / (36 * IN)))
        for i in range(n):
            x = x0 + (i + 0.5) * 36 * IN
            b = kb(x)
            b.box((36 * IN - 0.005, 18 * IN, 40 * IN), (x, y, 20 * IN), "cabinet")
            for k in range(3):
                for s in (-1, 1):
                    b.box((0.2, 0.006, 0.02), (x, y + s * (9 * IN + 0.003), 0.25 + k * 0.33), "hardware")
            if rng.random() < 0.35:
                b.box((0.3, 0.24, 0.08), (x + rng.uniform(-0.2, 0.2), y, 40 * IN + 0.04), "paper")
        col((x1 - x0 + 0.1, 18 * IN, 40 * IN), ((x0 + x1) / 2, y, 20 * IN))
    # Copier (multifunction, floor standing) and a laser printer on a cart.
    x = 22.6
    b = kb(x)
    b.box((0.62, 0.70, 0.98), (x, y, 0.49), "copier")
    b.box((0.60, 0.50, 0.14), (x, y + 0.05, 1.05), "copier")
    b.box((0.55, 0.42, 0.012), (x, y + 0.05, 1.126), "copier_dark")
    b.box((0.25, 0.12, 0.06), (x + 0.12, y + 0.36, 1.0), "copier_dark", rot=(0.4, 0, 0))
    for k in range(3):
        b.box((0.56, 0.005, 0.004), (x, y + 0.352, 0.25 + k * 0.2), "copier_dark")
    col((0.7, 0.75, 1.15), (x, y, 0.57))
    x = 24.0
    b.box((0.5, 0.45, 0.7), (x, y, 0.35), "cabinet")
    b.box((0.42, 0.40, 0.30), (x, y, 0.85), "copier")
    b.box((0.30, 0.15, 0.004), (x, y + 0.08, 1.0), "paper")
    b.box((0.5, 0.40, 0.6), (21.2, y, 0.3), "bin_blue")
    col((0.5, 0.5, 1.0), (24.0, y, 0.5))


def furniture():
    for bay in range(4):
        x0 = bay * BAY + (BAY - 3 * CUBE) / 2
        cluster(bay * 2, x0, 2.134)
        cluster(bay * 2 + 1, x0, 11.278 - 0.0)
    spine_furniture()


# The chair that rolls and the monitor that wakes are the level's own
# (cluster 4 is bay 2 south: cubicles 24..29; cluster 5 north: 30..35).
SKIP_CHAIR.add(31)          # bay 2 north cluster, middle cubicle (opens on the spine)
SKIP_MONITOR.add(16)        # bay 1 south cluster, middle cubicle (opens on the spine)

shell()
ceiling()
furniture()
for k in sorted(SPECIAL):
    if k in ("chair_31", "monitor_16"):
        print("SPECIAL", k, ["%.4f" % v for v in SPECIAL[k]])
print("lens nits %.0f emit %.2f" % (LENS_NITS, LENS_EMIT))

scene = bpy.context.scene
scene.cycles.max_bounces = 6
scene.cycles.diffuse_bounces = 4
scene.cycles.glossy_bounces = 1
scene.cycles.transparent_max_bounces = 2
scene.cycles.sample_clamp_indirect = 2.0     # (engine units: no fireflies from the lenses)
samples = int(sys.argv[sys.argv.index("--samples") + 1]) if "--samples" in sys.argv else 96

# The east half in the scene while the west bakes (light and shadow across
# the seam), then the east with the west in place.
tmp = bpy.data.objects.new("east_tmp", east.b.to_mesh("east_tmp"))
scene.collection.objects.link(tmp)
# Bake-only: the stair door leaf, shut (the level's own leaf opens).
occ = K.Builder()
occ.box((0.045, DOOR_W, DOOR_H), (-0.06, STAIR_DOOR[1], DOOR_H / 2), "door_steel")
occ_ob = bpy.data.objects.new("stair_leaf_bake", occ.to_mesh("stair_leaf_bake"))
scene.collection.objects.link(occ_ob)
west.export(OUT, lm=1024, samples=samples)
bpy.data.objects.remove(tmp, do_unlink=True)
for o in bpy.data.objects:
    if o.name.endswith("-colonly") or o.type == "EMPTY":
        o.hide_render = True
east.export(OUT, lm=1024, samples=samples)
