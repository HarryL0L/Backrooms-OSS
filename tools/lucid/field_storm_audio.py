# Procedural storm sounds for the Field (FieldStorm): PLACEHOLDERS, to be
# replaced by CC0 field recordings (Freesound was tried on 2026-11-09 and
# was blocked from the build environment).
#   python3 tools/lucid/field_storm_audio.py assets/levels/field/audio
# (needs numpy, ffmpeg). Ogg Vorbis loops:
#   wind_field.ogg    stereo, 20 s: strong wind over open grassland, the low
#                     rush of the air and the hiss of the grass, with its own
#                     slow surges (the game sets the level and pitch from the
#                     wind speed where you stand)
#   rain_grass.ogg    stereo, 20 s: heavy rain on a meadow: a soft wideband
#                     hiss (drops into grass make no sharp ticks), a dull
#                     patter of near drops, the wash of the whole field
#   tornado_roar.ogg  mono, 20 s: a tornado kilometres off: a deep continuous
#                     rumble (most of its sound is under 100 Hz and travels
#                     far; the highs are gone), slowly surging
# Thunder for open country: tools/lucid/night_city_thunder.py <dir> --open.
import numpy as np, wave, subprocess, sys, os
SR = 44100
out = sys.argv[1]
rng = np.random.default_rng(11)
N = 20 * SR


def shape(x, f_lo, f_hi, tilt=0.0):
    # Band-limit white noise with soft skirts and a spectral tilt (dB/oct ~ 6 tilt).
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / SR)
    w = 1.0 / (1.0 + (f_lo / np.maximum(f, 1.0)) ** 4) / (1.0 + (f / f_hi) ** 4)
    w = w * (np.maximum(f, 20.0) / 1000.0) ** tilt
    return np.fft.irfft(X * w, len(x))


def loop_env(n, periods, depth):
    # A slow modulation that loops exactly (whole cycles in the clip).
    t = np.arange(n) / n
    e = np.ones(n)
    for p, d in zip(periods, depth):
        e += d * np.sin(2 * np.pi * p * t + rng.uniform(0, 6.28))
    return np.maximum(e, 0.05)


def norm(x, peak):
    return x / (np.max(np.abs(x)) + 1e-9) * peak


def save(name, x):
    p = os.path.join(out, name + '.wav')
    y = np.clip(x, -1, 1)
    ch = 1 if y.ndim == 1 else y.shape[0]
    data = y if ch == 1 else y.T.reshape(-1)
    with wave.open(p, 'wb') as w:
        w.setnchannels(ch)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((data * 32767).astype(np.int16).tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', p, '-c:a', 'libvorbis', '-q:a', '4',
                    os.path.join(out, name + '.ogg')], check=True)
    os.remove(p)
    print(name, 'ok')


def wind():
    # The rush: pink-ish noise 40-900 Hz; the grass: a hiss 2-9 kHz that
    # follows the surges more strongly (blades hiss as v rises).
    ch = []
    for c in range(2):
        e = loop_env(N, [3, 7, 13], [0.35, 0.2, 0.12])
        rush = shape(rng.standard_normal(N), 40, 900, -0.8) * e
        hiss = shape(rng.standard_normal(N), 2000, 9000, -0.3) * e ** 2.2
        ch.append(norm(rush, 1.0) * 0.75 + norm(hiss, 1.0) * 0.25)
    x = np.array(ch)
    return norm(x, 0.8)


def rain():
    # Hiss of countless far drops; near drops into grass: soft thuds (a few
    # ms of low band noise), no clicks; the field's wash below 400 Hz.
    ch = []
    for c in range(2):
        hiss = shape(rng.standard_normal(N), 900, 12000, -0.2)
        wash = shape(rng.standard_normal(N), 60, 400, -0.5)
        pat = np.zeros(N + SR)
        k = rng.poisson(900 * N / SR)
        at = rng.integers(0, N, k)
        L = int(0.012 * SR)
        tt = np.arange(L) / SR
        for a in at:
            kk = rng.standard_normal(L) * np.exp(-tt / rng.uniform(0.002, 0.006))
            pat[a:a + L] += kk * rng.lognormal(0, 0.6)
        pat[:SR] += pat[N:N + SR]
        pat = shape(pat[:N], 300, 5000, -0.4)
        ch.append(norm(hiss, 1.0) * 0.55 + norm(pat, 1.0) * 0.3 + norm(wash, 1.0) * 0.25)
    return norm(np.array(ch), 0.75)


def roar():
    e = loop_env(N, [1, 2, 5], [0.25, 0.18, 0.1])
    low = shape(rng.standard_normal(N), 18, 160, -1.0) * e
    mid = shape(rng.standard_normal(N), 120, 600, -1.2) * e ** 1.5
    return norm(norm(low, 1.0) * 0.85 + norm(mid, 1.0) * 0.15, 0.8)


def loopify(x, fade=SR // 2):
    # Crossfade the end into the start so the loop is seamless.
    y = x[..., :-fade].copy()
    t = np.linspace(0, 1, fade)
    y[..., :fade] = x[..., :fade] * t + x[..., -fade:] * (1 - t)
    return y


os.makedirs(out, exist_ok=True)
save('wind_field', loopify(wind()))
save('rain_grass', loopify(rain()))
save('tornado_roar', loopify(roar()))
