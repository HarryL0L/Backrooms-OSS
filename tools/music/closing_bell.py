"""'Closing Bell' - chase audio for Backrooms-OSS (the Dead Mall).
Exactly 60 seconds. Found-footage style sound design rather than a song:
the entity's roar the moment it sees you, its heavy galloping footsteps
closing in, a low throbbing pulse, struck and scraped metal, dark drones,
and a mic that overloads when it gets close. It comes in waves with dead
drops between them, builds to a climax and cuts out at 60 s.
Everything is synthesized: no samples."""
import numpy as np, wave, sys

SR = 44100
rng = np.random.default_rng(31)
CHASE = 60.0
TOTAL = CHASE + 2.0
N = int(SR * TOTAL)
t_all = np.arange(N) / SR
dry = np.zeros((2, N))
send = np.zeros((2, N))

def put(sig, t0, pan=0.5, gain=1.0, wet=0.3):
    s0 = int(round(t0 * SR))
    if s0 >= N or s0 < 0: return
    n = min(len(sig), N - s0)
    for ch, g in ((0, 1 - pan), (1, pan)):
        dry[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4 * (1 - 0.6 * wet)
        send[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4 * wet

def ramp(t, a, b): return np.clip((t - a) / (b - a), 0, 1)
def drive(x, k): return np.tanh(x * k) / np.tanh(k)

def stft_shape(x, gain_fn):
    """Filters x with a time-varying spectral gain gain_fn(t, freqs)."""
    n = len(x); F, H = 2048, 512
    xp = np.concatenate([x, np.zeros(F)])
    win = np.hanning(F); out = np.zeros(n + F)
    freqs = np.fft.rfftfreq(F, 1 / SR)
    for s in range(0, n, H):
        X = np.fft.rfft(xp[s:s + F] * win)
        out[s:s + F] += np.fft.irfft(X * gain_fn(s / SR, freqs), F) * win
    return out[:n] / 1.5

def formants(fs, bws, amps):
    def g(t, fr):
        out = np.zeros_like(fr)
        for f, b, a in zip(fs(t), bws, amps):
            out += a * np.exp(-((fr - f) / b) ** 2)
        return out
    return g

# ------------------------------------------------------- the creature ---
def voice(dur, f0_fn, vowel_fn, fry=0.6, noise=0.35, jitter=0.03):
    """Glottal pulse train with jitter and period-doubling (a growl), shaped
    by moving formants, plus breath noise."""
    n = int(dur * SR); t = np.arange(n) / SR
    f0 = f0_fn(t) * (1 + jitter * np.interp(t, np.linspace(0, dur, 60), rng.standard_normal(60)))
    ph = np.cumsum(f0) / SR
    frac = ph % 1.0
    pulse = (1 - frac) ** 3                                      # sharp glottal closures
    sub = ((ph / 2) % 1.0 < 0.5) * 2 - 1                         # every other cycle louder: fry
    src = pulse * (1 + fry * sub)
    src = src - np.convolve(src, np.ones(64) / 64, 'same')       # remove DC drift
    src += noise * rng.standard_normal(n)
    out = stft_shape(src, vowel_fn)
    env = np.minimum(t / 0.06, 1) * np.clip((dur - t) / 0.25, 0, 1)
    return out * env

def roar(dur=2.2, size=1.0):
    peak = rng.uniform(0.25, 0.45)
    f0 = lambda t: (55 + 70 * np.exp(-((t / dur - peak) / 0.3) ** 2)) * size
    vow = formants(lambda t: (420 + 260 * np.sin(np.pi * min(t / dur, 1)), 900 + 300 * np.sin(np.pi * min(t / dur, 1)), 2300),
                   (120, 180, 400), (1.0, 0.8, 0.35))
    low = voice(dur, f0, vow, fry=0.8, noise=0.5)
    # An inhuman scream riding on top.
    f1 = lambda t: (520 + 260 * np.exp(-((t / dur - peak) / 0.25) ** 2)) * (1 + 0.02 * np.sin(2 * np.pi * 9 * t))
    vow2 = formants(lambda t: (700, 1900, 3000), (180, 260, 400), (0.8, 1.0, 0.5))
    hi = voice(dur, f1, vow2, fry=0.3, noise=0.6, jitter=0.05)
    x = low / (np.abs(low).max() + 1e-9) + 0.55 * hi / (np.abs(hi).max() + 1e-9)
    return drive(x * 1.6, 2.0)

def growl(dur=2.5):
    f0 = lambda t: 48 + 8 * np.sin(2 * np.pi * 0.7 * t)
    vow = formants(lambda t: (380, 800, 2200), (100, 160, 300), (1.0, 0.6, 0.2))
    x = voice(dur, f0, vow, fry=1.0, noise=0.6, jitter=0.06)
    return drive(x / (np.abs(x).max() + 1e-9) * 1.3, 1.5)

# --------------------------------------------------------- its steps ---
def step(v=1.0):
    n = int(0.7 * SR); t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(38 + 55 * np.exp(-t * 22)) / SR) * np.exp(-t * 6)
    knock = stft_shape(rng.standard_normal(n), lambda tt, fr: np.exp(-((fr - 280) / 220) ** 2)) * np.exp(-t * 30)
    rattle = stft_shape(rng.standard_normal(n), lambda tt, fr: np.exp(-((fr - 1800) / 900) ** 2)) * np.exp(-t * 45) * 0.3
    return drive((body * 1.1 + 1.4 * knock / (np.abs(knock).max() + 1e-9) + 0.8 * rattle / (np.abs(rattle).max() + 1e-9)) * v, 2.2)

# -------------------------------------------------------- the place ---
def metal(v=1.0, base=None, ring=1.0):
    n = int(2.5 * SR); t = np.arange(n) / SR
    f0 = base or rng.uniform(140, 300)
    out = np.zeros(n)
    for r, a, dec in ((1.0, 1.0, 1.8), (2.32, 0.6, 2.6), (3.87, 0.4, 3.5), (5.41, 0.25, 5), (7.13, 0.15, 7)):
        out += np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6)) * a * np.exp(-t * dec / ring)
    hit = stft_shape(rng.standard_normal(n), lambda tt, fr: np.exp(-((fr - 1200) / 1500) ** 2)) * np.exp(-t * 60)
    return (out * 0.5 + hit / (np.abs(hit).max() + 1e-9)) * v

def scrape(d):
    f0 = rng.uniform(700, 1500); f1 = f0 * rng.uniform(0.7, 1.4)
    src = rng.standard_normal(int(d * SR))
    x = stft_shape(src, lambda tt, fr: (np.exp(-((fr - f0 * (f1 / f0) ** (tt / d)) / 60) ** 2)
                                        + 0.6 * np.exp(-((fr - 2.31 * f0 * (f1 / f0) ** (tt / d)) / 90) ** 2)))
    tt = np.arange(len(x)) / SR
    x = x / (np.abs(x).max() + 1e-9) * (0.4 + 0.6 * np.abs(np.sin(2 * np.pi * rng.uniform(6, 14) * tt)))
    return x * np.minimum(tt / 0.08, 1) * np.clip((d - tt) / 0.3, 0, 1)

# ------------------------------------------------------------ score ---
# Intensity: waves with dead drops (used for drones, throb and step loudness).
inten = (0.75 * (1 - ramp(t_all, 1, 4)) + 0.55 * ramp(t_all, 3, 6) - 0.5 * ramp(t_all, 13.5, 14.2)
         + 0.7 * ramp(t_all, 16, 17) + 0.25 * ramp(t_all, 17, 33) - 0.85 * ramp(t_all, 33.8, 34.4)
         + 0.9 * ramp(t_all, 38, 39) + 0.4 * ramp(t_all, 39, 58))
inten = np.clip(inten, 0.05, 1.3)

# 0 s: it sees you.
put(roar(2.6, 1.0), 0.0, 0.5, 1.0, 0.35)
put(step(1.6), 0.0, 0.5, 0.9, 0.3)
put(metal(1.2, 120, 1.5), 0.02, 0.35, 0.6, 0.5)

# Dark drone bed: low saws, gently saturated, swelling with the intensity.
n = int(CHASE * SR); t = t_all[:n]
dr = np.zeros(n)
for f, a in ((41.2, 1.0), (43.6, 0.6), (61.7, 0.5), (82.4, 0.35), (87.3, 0.25)):
    ph = 2 * np.pi * np.cumsum(f * (1 + 0.004 * np.sin(2 * np.pi * rng.uniform(0.05, 0.2) * t))) / SR
    for h in range(1, 14):
        dr += np.sin(ph * h + h) / h * a
dr = stft_shape(dr, lambda tt, fr: 1 / (1 + (fr / (300 + 900 * np.interp(tt, t_all, inten))) ** 2))
put(drive(dr / np.abs(dr).max() * 2, 1.5) * np.interp(t, t_all, inten), 0, 0.5, 0.42, 0.35)
# The throb: a pulse whose speed rises with the chase (no beat, no notes).
throb_rate = 3.0 + 4.0 * np.cumsum(np.interp(t, t_all, inten)) / SR / CHASE
lfo = 0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(throb_rate) / SR)
thr = np.sin(2 * np.pi * 55 * t) + 0.5 * np.sin(2 * np.pi * 110 * t + 1) + 0.25 * np.sin(2 * np.pi * 165 * t)
put(drive(thr * lfo ** 2 * 1.5, 1.5) * np.interp(t, t_all, np.clip(inten - 0.15, 0, 1)), 0, 0.5, 0.35, 0.2)

# Its footsteps: a heavy three-beat gallop, from far down the hall to right
# behind you; faster and drier as it closes in. Silent in the drops.
tg = 3.0
while tg < CHASE - 0.3:
    k = np.interp(tg, t_all, inten)
    if k > 0.3:
        close = np.clip((tg - 3) / 55, 0, 1)
        cyc = 0.78 - 0.3 * close
        for j, (off, v) in enumerate(((0.0, 0.7), (0.13 - 0.03 * close, 0.8), (0.26 - 0.06 * close, 1.0))):
            put(step(v), tg + off, 0.5 + rng.uniform(-0.12, 0.12), 0.55 + 0.35 * close, 0.65 - 0.45 * close)
        tg += cyc
    else:
        tg += 0.25

# Roars and stingers.
for at, d, s in ((16.0, 2.0, 1.05), (23.5, 1.6, 0.95), (29.5, 1.8, 1.1), (38.0, 2.4, 0.9), (45.5, 1.5, 1.2),
                 (51.0, 1.8, 1.0), (55.5, 2.2, 1.15)):
    put(roar(d, s), at, rng.uniform(0.35, 0.65), 0.8 + 0.15 * (at > 38), 0.3)
    put(metal(1.0, rng.uniform(100, 180), 1.3), at, rng.uniform(0.2, 0.8), 0.45, 0.6)
# Close, quiet growls in the dead drops (right next to you).
put(growl(2.2), 14.0, 0.85, 0.5, 0.08)
put(growl(3.0), 34.6, 0.15, 0.55, 0.08)
# Metal scrapes and hits through the waves.
for at in np.sort(rng.uniform(4, 58, 14)):
    if np.interp(at, t_all, inten) > 0.4:
        if rng.random() < 0.5:
            put(scrape(rng.uniform(0.8, 1.8)), at, rng.uniform(0.1, 0.9), 0.32, 0.6)
        else:
            put(metal(0.7), at, rng.uniform(0.1, 0.9), 0.35, 0.65)
# A rising groan under the climax (the building itself).
cl = int((CHASE - 38) * SR); ct = np.arange(cl) / SR
f = 70 * 2 ** (ct / (CHASE - 38) * 1.5)
groan = np.zeros(cl); ph = 2 * np.pi * np.cumsum(f) / SR
for h in range(1, 10):
    groan += np.sin(ph * h * (1 + 0.003 * h)) / h
put(drive(groan * (ct / ct[-1]) ** 1.5, 2.0), 38, 0.5, 0.35, 0.4)

# --------------------------------------------------------- the space ---
def filt(x, f):
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * f(fr), len(x))
def reverb(x, seed, secs=5.0, decay=0.9):
    r = np.random.default_rng(seed); n2 = int(secs * SR); tt = np.arange(n2) / SR
    ir = filt(r.standard_normal(n2) * np.exp(-tt * decay), lambda fr: 1 / (1 + (fr / 3500) ** 2))
    ir = np.concatenate([np.zeros(int(0.05 * SR)), ir])[:n2]
    m = len(x) + n2
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)] / np.abs(ir).sum() * 26
out = dry + np.stack([reverb(send[0], 3), reverb(send[1], 4)])

# Mic overload when it's close: brief hard clipping on the roars and climax.
peak = np.abs(out).max()
clip_amt = np.zeros(N)
for at in (0.0, 16.0, 29.5, 38.0, 45.5, 51.0, 55.5):
    clip_amt = np.maximum(clip_amt, np.exp(-((t_all - at - 0.4) / 0.5) ** 2))
clip_amt = np.maximum(clip_amt, ramp(t_all, 52, 59.5) * 0.7)
hard = np.clip(out / peak * 3.0, -1, 1) * peak
out = out * (1 - clip_amt) + hard * clip_amt * 0.8
# A little tape wow, darker top, no hiss.
wow = 1 + 0.003 * np.sin(2 * np.pi * 0.4 * t_all) * (0.3 + ramp(t_all, 0, CHASE))
src = np.cumsum(wow) / SR
out = np.stack([np.interp(src, t_all, o) for o in out])
out = np.stack([filt(o, lambda fr: (1 - 1 / np.sqrt(1 + (fr / 30) ** 4)) / np.sqrt(1 + (fr / 9000) ** 4)) for o in out])
out = np.tanh(out / np.abs(out).max() * 1.8) / np.tanh(1.8) * 0.95
cut = int(CHASE * SR)
out[:, cut:] = 0.0
out[:, cut - 180:cut] *= np.linspace(1, 0, 180)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out.T * 32767).astype(np.int16).tobytes())
print("chase %.1f s" % CHASE)
