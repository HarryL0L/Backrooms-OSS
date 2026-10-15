"""'Closing Bell' - chase audio for Backrooms-OSS (the Dead Mall).
Exactly 60 seconds of noise and dread, no melody and no beat: a full-volume
blast the moment the entity sees you, then grinding distorted drones that
stutter and glitch, scraping metal shrieks, booms at random moments, distant
howls, and a rumble that never stops rising - through warped, crackling
tape in a huge empty hall. At 60 s it all cuts out dead.
Everything is synthesized: no samples."""
import numpy as np, wave, sys

SR = 44100
rng = np.random.default_rng(13)
CHASE = 60.0
TOTAL = CHASE + 2.5
N = int(SR * TOTAL)
t_all = np.arange(N) / SR
dry = np.zeros((2, N))
send = np.zeros((2, N))

def put(sig, t0, pan=0.5, gain=1.0, wet=0.3):
    s0 = int(round(t0 * SR))
    if s0 >= N or s0 < 0: return
    n = min(len(sig), N - s0)
    for ch, g in ((0, 1 - pan), (1, pan)):
        dry[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4 * (1 - 0.5 * wet)
        send[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4 * wet

def ramp(t, a, b): return np.clip((t - a) / (b - a), 0, 1)

# STFT noise shaping: a band of noise whose centre (Hz) and width (octaves)
# follow curves over time - for rising rumbles, scrapes and howls.
def shaped_noise(dur, centre, width_oct, extra=None):
    n = int(dur * SR)
    F, H = 2048, 512
    x = rng.standard_normal(n + F)
    win = np.hanning(F)
    out = np.zeros(n + F)
    freqs = np.fft.rfftfreq(F, 1 / SR)
    lf = np.log2(np.maximum(freqs, 1.0))
    for s in range(0, n, H):
        tt = s / SR
        c = centre(tt); w = width_oct(tt)
        X = np.fft.rfft(x[s:s + F] * win)
        gain = np.exp(-((lf - np.log2(c)) / w) ** 2)
        if extra is not None:
            gain = gain * extra(tt, freqs)
        out[s:s + F] += np.fft.irfft(X * gain, F) * win
    out = out[:n]
    return out / (np.abs(out).max() + 1e-9)

def saws(freqs_t, n, hmax=40):
    out = np.zeros(n)
    for f in freqs_t:
        ph = 2 * np.pi * np.cumsum(f) / SR
        for h in range(1, hmax):
            out += np.sin(ph * h) / h
    return out

def drive(x, k): return np.tanh(x * k) / np.tanh(k)

def fold(x, k):
    y = x * k
    return np.abs(((y - 1) % 4) - 2) - 1   # wavefolder: harsh, metallic grit

# ----------------------------------------------------------- 1. the blast ---
bn = int(3.0 * SR); bt_ = np.arange(bn) / SR
dive = 2 ** (-bt_ * 1.2)                                  # everything plunges in pitch
blast = np.zeros(bn)
for f0 in (55.0, 58.3, 82.4, 116.5, 233.1, 311.1, 466.2, 622.3):   # clashing cluster
    blast += saws([f0 * dive * (1 + 0.004 * rng.standard_normal())] , bn, 25) * (1.0 if f0 < 200 else 0.6)
blast += shaped_noise(3.0, lambda t: 1800 * 2 ** (-t * 1.5), lambda t: 1.6) * 6
blast = drive(blast * np.exp(-bt_ * 0.9), 6.0)
put(blast, 0.0, 0.5, 1.0, 0.4)
imp = np.sin(2 * np.pi * np.cumsum(35 + 140 * np.exp(-bt_ * 14)) / SR) * np.exp(-bt_ * 2.5)
put(drive(imp * 3, 3.0), 0.0, 0.5, 0.9, 0.5)

# ----------------------------------------------------- 2. grinding drones ---
dur = CHASE
n = int(dur * SR); t = np.arange(n) / SR
rise = 2 ** (t / dur * 1.0)                             # up an octave over the minute
def wander(rate, depth):
    w = np.cumsum(rng.standard_normal(n // 2000 + 2))
    w = np.interp(np.arange(n), np.arange(len(w)) * 2000, w)
    return 1 + depth * np.tanh(w * rate)
drone = saws([41.2 * rise * wander(0.15, 0.03), 58.3 * rise * wander(0.15, 0.04),
              43.6 * rise * wander(0.2, 0.05)], n, 30)
drone = fold(drone * 0.08, 2.2 + 1.5 * t / dur)        # gets harsher as it goes
# Irregular stutter: the sound chops in bursts, never on a grid.
gate = np.ones(n)
s = int(4.0 * SR)
while s < n:
    ln = int(rng.uniform(0.15, 0.9) * SR)
    rate = rng.uniform(9, 26)
    seg = np.arange(min(ln, n - s)) / SR
    gate[s:s + len(seg)] = 0.25 + 0.75 * (np.sin(2 * np.pi * rate * seg) > 0)
    s += ln + int(rng.uniform(0.6, 3.0 + 3.0 * (1 - s / n)) * SR)
put(drone * gate * (0.55 + 0.45 * ramp(t, 0, 50)), 1.2, 0.5, 0.42, 0.3)
mid = saws([164.8 * rise * wander(0.3, 0.06), 233.1 * rise * wander(0.3, 0.07)], n, 14)
put(drive(mid * 0.15, 4.0) * gate * (0.3 + 0.5 * ramp(t, 10, 55)), 1.2, 0.5, 0.22, 0.4)

# -------------------------------------------------- 3. the endless rumble ---
rum = shaped_noise(dur, lambda tt: 60 * 2 ** ((tt / dur) * 4.0), lambda tt: 0.9 + 0.4 * tt / dur)
put(drive(rum * 2.0, 2.0) * (0.4 + 0.6 * ramp(t, 0, 58)), 1.0, 0.5, 0.45, 0.3)

# ------------------------------------------------- 4. metal shrieks/scrapes ---
def scrape(d):
    f0 = rng.uniform(900, 2600); f1 = f0 * rng.uniform(0.6, 1.8)
    c = lambda tt: f0 * (f1 / f0) ** (tt / d)
    reson = lambda tt, fr: 1 + 3 * np.exp(-((fr - 2.31 * c(tt)) / 120) ** 2) + 2 * np.exp(-((fr - 3.7 * c(tt)) / 150) ** 2)
    x = shaped_noise(d, c, lambda tt: 0.05, reson)
    tt = np.arange(len(x)) / SR
    flutter = 0.5 + 0.5 * np.abs(np.sin(2 * np.pi * rng.uniform(15, 40) * tt + rng.uniform(0, 6)))
    env = np.minimum(tt / 0.05, 1) * np.clip((d - tt) / 0.2, 0, 1)
    return drive(x * flutter * env * 3, 2.5)
tt0 = 1.5
while tt0 < CHASE - 1.0:
    d = rng.uniform(0.6, 2.2)
    put(scrape(d), tt0, rng.uniform(0.1, 0.9), 0.3 + 0.15 * tt0 / CHASE, 0.55)
    tt0 += rng.uniform(1.0, 4.0 - 2.4 * tt0 / CHASE)

# --------------------------------------------------- 5. random impacts ---
def boom(v):
    bn2 = int(1.6 * SR); b = np.arange(bn2) / SR
    body = np.sin(2 * np.pi * np.cumsum(30 + rng.uniform(60, 110) * np.exp(-b * 16)) / SR) * np.exp(-b * 3)
    crack = shaped_noise(1.6, lambda x: 900, lambda x: 1.5) * np.exp(-b * 18)
    return drive((body * 2 + crack) * v, 3.0)
tt0 = 3.0
while tt0 < CHASE - 0.6:
    put(boom(rng.uniform(0.7, 1.1)), tt0, rng.uniform(0.3, 0.7), 0.5, 0.6)
    tt0 += rng.uniform(0.7, 3.2) * (1.0 - 0.65 * tt0 / CHASE)

# ------------------------------------------------- 6. distant howls ---
def howl(d):
    f = rng.uniform(380, 620)
    vowel = lambda tt, fr: (np.exp(-((fr - 800) / 160) ** 2) + 0.8 * np.exp(-((fr - 1200) / 200) ** 2)
                            + 0.4 * np.exp(-((fr - 2600) / 300) ** 2))
    x = shaped_noise(d, lambda tt: f * (1 - 0.3 * tt / d), lambda tt: 1.2, vowel)
    tt = np.arange(len(x)) / SR
    tone = np.sin(2 * np.pi * np.cumsum(f * (1 - 0.3 * tt / d) * (1 + 0.02 * np.sin(2 * np.pi * 6 * tt))) / SR)
    env = np.sin(np.pi * np.clip(tt / d, 0, 1)) ** 1.5
    return (x * 0.7 + tone * 0.25) * env
for at in (9.0, 23.5, 38.0, 49.0):
    put(howl(rng.uniform(2.0, 3.2)), at, rng.choice([0.15, 0.85]), 0.35, 1.0)

# --------------------------------------------------------- the space ---
def filt(x, f):
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * f(fr), len(x))
def reverb(x, seed, secs=4.5, decay=1.0):
    r = np.random.default_rng(seed); n2 = int(secs * SR); tt = np.arange(n2) / SR
    ir = filt(r.standard_normal(n2) * np.exp(-tt * decay), lambda fr: 1 / (1 + (fr / 5000) ** 2))
    ir = np.concatenate([np.zeros(int(0.04 * SR)), ir])[:n2]
    m = len(x) + n2
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)] / np.abs(ir).sum() * 26
out = dry + np.stack([reverb(send[0], 7), reverb(send[1], 8)])

# Glitches on the whole thing: buffer stutters and drop-outs, more often later.
tt0 = 5.0
while tt0 < CHASE - 1.5:
    s0 = int(tt0 * SR); ln = int(rng.uniform(0.03, 0.12) * SR); reps = rng.integers(3, 9)
    frag = out[:, s0:s0 + ln].copy()
    for r in range(1, reps):
        out[:, s0 + r * ln: s0 + (r + 1) * ln] = frag
    if rng.random() < 0.3:                          # a hard drop-out after it
        e = s0 + reps * ln
        out[:, e:e + int(rng.uniform(0.05, 0.2) * SR)] *= 0.05
    tt0 += rng.uniform(1.5, 6.0) * (1.0 - 0.6 * tt0 / CHASE)

# Warped tape: wow that worsens, then crackle and hiss.
wow = 1 + (0.002 + 0.01 * ramp(t_all, 0, CHASE)) * np.sin(2 * np.pi * 0.5 * t_all) \
    + 0.002 * np.sin(2 * np.pi * 7.3 * t_all)
src = np.cumsum(wow) / SR
out = np.stack([np.interp(src, t_all, o) for o in out])
crackle = (rng.random(N) < 0.0006) * rng.uniform(-1, 1, N)
hiss = filt(rng.standard_normal(N), lambda fr: (fr > 3000) / (1 + (fr / 12000) ** 2))
out += (crackle * 0.5 + hiss / np.abs(hiss).max() * 0.02)[None, :] * np.abs(out).max()

# Loud and squashed (it's meant to be overwhelming), then the dead cut at 60 s.
out = np.stack([filt(o, lambda fr: (1 - 1 / np.sqrt(1 + (fr / 35) ** 4)) * (1 + 0.6 * np.exp(-((fr - 2500) / 1500) ** 2))) for o in out])
out = np.tanh(out / np.abs(out).max() * 2.6) / np.tanh(2.6) * 0.95
cut = int(CHASE * SR)
out[:, cut:] = 0.0
out[:, cut - int(0.004 * SR):cut] *= np.linspace(1, 0, int(0.004 * SR))
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out.T * 32767).astype(np.int16).tobytes())
print("chase %.1f s" % CHASE)
