"""'Fountain Court' - an original piece for Backrooms-OSS.
Mall music in an empty atrium that goes from happy and nostalgic, to sad,
to eerie and unsafe (it gets stuck, sags, distorts, the power dies), and
then simply carries on as if nothing happened - just further away and a
little flat. Soft-jazz combo (Rhodes, vibraphone, strings, bass, drum
machine) through tinny ceiling speakers, echoes from other speakers down the
hall and a long reverb. Everything is synthesized: no samples, no borrowed
melody."""
import numpy as np, wave, sys

SR = 44100
rng = np.random.default_rng(23)
BEAT = 60.0 / 72.0
BAR = 4 * BEAT

def mtof(m): return 440.0 * 2 ** ((m - 69) / 12)

# ------------------------------------------------------------ structure ---
# Section start times (seconds, source timeline).
A0 = 1.0                      # happy: 12 bars
B0 = A0 + 12 * BAR            # sad: 12 bars
C0 = B0 + 12 * BAR            # eerie: stuck, sagging, falling apart: 9 bars
CUT = C0 + 9 * BAR            # the power dies
D0 = CUT + 2.2                # ...and it carries on: 12 bars
END = D0 + 12 * BAR + 9.0
N = int(SR * END)
t_all = np.arange(N) / SR

HAPPY = [(40, [56, 59, 63, 66]), (37, [52, 56, 59, 63]), (45, [56, 59, 61, 64]), (47, [57, 61, 63, 66])]
SAD = [(40, [56, 59, 63, 66]), (37, [52, 56, 59, 63]), (45, [56, 59, 61, 64]), (45, [57, 60, 64, 66]),
       (44, [54, 59, 63, 68]), (37, [53, 56, 59, 62]), (42, [57, 61, 64, 68]), (47, [57, 64, 66, 71]),
       (45, [56, 59, 61, 64]), (45, [57, 60, 64, 66]), (44, [56, 59, 63, 64]), (45, [57, 60, 64, 66])]
TUNE_1 = [(0, 76, .5), (.5, 75, .5), (1, 76, 1), (2, 80, 1), (3, 78, 1), (4, 76, 1.5), (5.5, 73, .5), (6, 71, 2),
          (8, 73, .5), (8.5, 76, .5), (9, 78, 1), (10, 81, 1.5), (11.5, 80, .5), (12, 78, 1), (13, 75, 1), (14, 73, 2)]
TUNE_2 = [(0, 76, .5), (.5, 78, .5), (1, 80, 1), (2, 83, 1), (3, 81, .5), (3.5, 80, .5), (4, 78, 1.5), (5.5, 76, .5),
          (6, 73, 2), (8, 81, 1), (9, 80, 1), (10, 78, 1), (11, 76, 1), (12, 75, 1.5), (13.5, 76, .5), (14, 76, 2)]
TIRED = [(0, 75, 1), (1, 73, 1), (2, 71, 2), (4, 68, 1.5), (5.5, 71, .5), (6, 73, 2), (8, 73, 1), (9, 71, 1),
         (10, 68, 2), (12, 72, 1.5), (13.5, 71, .5), (14, 69, 2), (16, 71, 1), (17, 75, 1), (18, 78, 2),
         (20, 77, 1.5), (21.5, 74, .5), (22, 71, 2), (24, 73, 2), (26, 69, 1), (27, 68, 1), (28, 66, 4)]

band = np.zeros((2, N))      # the music, as it comes out of the speakers
room = np.zeros((2, N))      # things in the building itself (not through the speakers)

def put(buf, sig, t0, pan=0.5, gain=1.0):
    s0 = int(t0 * SR)
    if s0 >= N or s0 < 0: return
    n = min(len(sig), N - s0)
    buf[0, s0:s0 + n] += sig[:n] * gain * (1 - pan) * 1.4
    buf[1, s0:s0 + n] += sig[:n] * gain * pan * 1.4

def release(t, dur, r):
    return np.clip(1 - (t - dur) / r, 0, 1) ** 2

# ---------------------------------------------------------- instruments ---
def epiano(m, dur, vel, sag=0.0, cut=None):
    f = mtof(m)
    n = int((dur + 1.2) * SR); t = np.arange(n) / SR
    fr = f * 2 ** (np.clip(t / dur, 0, 1) * sag / 1200)
    ph = 2 * np.pi * np.cumsum(fr) / SR
    idx = vel * 1.5 * np.exp(-t * 2.8) + 0.25
    sig = np.sin(ph + idx * np.sin(ph)) + 0.12 * vel * np.sin(ph * 14.0) * np.exp(-t * 35)
    env = np.minimum(t / 0.003, 1) * np.exp(-t * 0.85) * release(t, dur, 0.25)
    if cut is not None:            # chopped off mid-note (a skipping CD)
        env *= np.clip((cut - t) / 0.004, 0, 1)
    return sig * env * vel

def vibes(m, dur, vel):
    f = mtof(m)
    n = int((dur + 2.5) * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * f * t) + 0.22 * np.sin(8 * np.pi * f * t) * np.exp(-t * 4) \
        + 0.06 * np.sin(20 * np.pi * f * t) * np.exp(-t * 12)
    trem = 1 - 0.28 * (0.5 + 0.5 * np.sin(2 * np.pi * 5.2 * t))
    return tone * trem * np.minimum(t / 0.002, 1) * np.exp(-t * 0.75) * release(t, dur + 0.6, 0.6) * vel

def pad(notes, dur, bright=1.0):
    n = int((dur + 2.0) * SR); t = np.arange(n) / SR
    out = np.zeros(n)
    for m in notes:
        for d in (-5, 5):
            fd = mtof(m) * 2 ** (d / 1200); ph = rng.uniform(0, 6.28)
            for h in range(1, 6):
                out += np.sin(2 * np.pi * fd * h * t + ph * h) / h ** (2.4 - 0.6 * bright)
    return out * np.minimum(t / 1.2, 1) ** 2 * release(t, dur, 1.8) * 0.05

def bass(m, dur, vel):
    f = mtof(m)
    n = int((dur + 0.4) * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(4 * np.pi * f * t) * np.exp(-t * 3)
    return tone * np.minimum(t / 0.01, 1) * np.exp(-t * 1.2) * release(t, dur, 0.12) * vel

def bandpass_noise(dur, lo, hi, decay):
    n = int(dur * SR); t = np.arange(n) / SR
    X = np.fft.rfft(rng.standard_normal(n)); fr = np.fft.rfftfreq(n, 1 / SR)
    X *= (fr > lo) & (fr < hi)
    return np.fft.irfft(X, n) * np.exp(-t * decay)

def kick():
    n = int(0.35 * SR); t = np.arange(n) / SR
    return np.sin(2 * np.pi * np.cumsum(45 + 50 * np.exp(-t * 30)) / SR) * np.exp(-t * 9)

def rim():
    n = int(0.08 * SR); t = np.arange(n) / SR
    return (np.sin(2 * np.pi * 1700 * t) * 0.6 + bandpass_noise(0.08, 1500, 6000, 1) * 0.3) * np.exp(-t * 70)

def hat(open_=False):
    return bandpass_noise(0.2 if open_ else 0.06, 6000, 16000, 14 if open_ else 60)

# ------------------------------------------------------- 1. happy (A, D) ---
def happy_section(s0, with_tune):
    for b in range(12):
        root, v = HAPPY[b % 4]
        t0 = s0 + b * BAR
        for k, m in enumerate(v):            # syncopated bossa comping
            pan = 0.35 + 0.1 * k
            put(band, epiano(m, BEAT * 0.9, 0.6), t0 + k * 0.01, pan, 0.15)
            put(band, epiano(m, BEAT * 0.6, 0.5), t0 + 1.5 * BEAT + k * 0.01, pan, 0.15)
            put(band, epiano(m, BEAT * 1.2, 0.55), t0 + 2.5 * BEAT + k * 0.01, pan, 0.15)
        put(band, pad(v, BAR, 1.0), t0, 0.5, 0.8)
        for bt, d, iv in ((0, 1.4, 0), (1.5, 0.4, 7), (2, 1.4, 0), (3.5, 0.4, 7)):
            put(band, bass(root + iv, BEAT * d, 0.8), t0 + bt * BEAT, 0.5, 0.34)
        for e8 in range(8):
            put(band, hat(e8 == 7), t0 + e8 * BEAT / 2 + (0.025 if e8 % 2 else 0), 0.62, 0.07 if e8 % 2 else 0.1)
        clave = (0, 1.5, 3) if b % 2 == 0 else (1, 2.5)
        for c in clave:
            put(band, rim(), t0 + c * BEAT, 0.45, 0.09)
        put(band, kick(), t0, 0.5, 0.3); put(band, kick(), t0 + 2.5 * BEAT, 0.5, 0.22)
    if with_tune:
        for half, tune in ((4, TUNE_1), (8, TUNE_2)):
            for bt, m, ln in tune:
                put(band, vibes(m, ln * BEAT, 0.85), s0 + half * BAR + bt * BEAT, 0.58, 0.2)

happy_section(A0, True)

# --------------------------------------------------------------- 2. sad ---
for b, (root, v) in enumerate(SAD):
    t0 = B0 + b * BAR
    sag = b == 9
    for k, m in enumerate(v):
        pan = 0.35 + 0.1 * k
        put(band, epiano(m, BEAT * 1.4, 0.5), t0 + k * 0.014, pan, 0.16)
        put(band, epiano(m, BEAT * 1.0, 0.38, sag=-70 if sag and k == 3 else 0.0), t0 + 1.5 * BEAT, pan, 0.16)
        put(band, epiano(m, BEAT * 0.6, 0.22), t0 + 3 * BEAT, pan, 0.16)
    put(band, pad(v, BAR, 0.6), t0, 0.5, 1.0)
    put(band, bass(root, BEAT * 1.8, 0.7), t0, 0.5, 0.34)
    put(band, bass(root + 7, BEAT * 1.4, 0.5), t0 + 2 * BEAT, 0.5, 0.3)
    if b < 8:                                 # the drums thin out, then stop
        for q in range(4):
            put(band, hat(), t0 + q * BEAT, 0.62, 0.06)
        put(band, rim(), t0 + 3 * BEAT, 0.45, 0.07)
        if b % 2 == 0:
            put(band, kick(), t0, 0.5, 0.2)
for bt, m, ln in TIRED:
    put(band, vibes(m, ln * BEAT, 0.7), B0 + bt * BEAT, 0.58, 0.19)

# ------------------------------------------------------------ 3. eerie ---
# The CD gets stuck on the Am6 chord: a chopped fragment re-triggering,
# irregular, while the band drops out and the building starts to sound.
stuck = [57, 60, 64, 66]
t = C0
k = 0
while t < CUT - 0.8:
    frag = 0.42 + 0.25 * rng.random() if k % 5 else 0.9
    for i, m in enumerate(stuck):
        put(band, epiano(m, frag, 0.5, cut=frag), t + i * 0.006, 0.35 + 0.1 * i, 0.17)
    if k % 3 == 0:
        put(band, bass(45, frag, 0.6), t, 0.5, 0.3)
    t += frag + (0.0 if rng.random() < 0.7 else rng.uniform(0.1, 0.5))
    k += 1
# One last attempt at the tune, which can't get past its first notes.
for bt, m, ln in ((0, 76, .5), (.5, 75, .5), (1, 76, 1), (2.5, 76, .5), (3, 75, 1.5)):
    put(band, vibes(m, ln * BEAT, 0.6), C0 + 2 * BAR + bt * BEAT, 0.6, 0.16)
# The building: a low drone a tritone apart (beating), reversed piano swells,
# and a slow, heavy pulse.
cn = int((CUT - C0) * SR); ct = np.arange(cn) / SR
grow = np.clip(ct / (CUT - C0), 0, 1)
drone = np.zeros(cn)
for f0, a0 in ((82.4, 1.0), (116.5, 0.75), (123.5, 0.35)):     # E2, Bb2 (tritone), B2 (rubbing)
    for h in range(1, 7):
        drone += a0 * np.sin(2 * np.pi * f0 * h * ct * (1 + 0.0015 * h) + h) / h ** 1.3
drone *= grow ** 1.2 * (0.8 + 0.2 * np.sin(2 * np.pi * 0.13 * ct)) * 0.3
put(room, drone, C0, 0.5, 1.0)
for i, (at, notes) in enumerate(((1.5, [70, 71]), (3.5, [63, 64, 70]), (5.5, [58, 59, 65]), (7.0, [70, 76, 77]))):
    sw = sum(epiano(m, 2.5, 0.6) for m in notes)[::-1]
    put(room, sw, C0 + at * BAR - len(sw) / SR + 0.3, 0.3 + 0.13 * i, 0.12)
def thud():
    n = int(0.5 * SR); tt = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(70 + 60 * np.exp(-tt * 20)) / SR) * np.exp(-tt * 7)
    return body + bandpass_noise(0.5, 150, 900, 25) * 0.6
for p in np.arange(C0 + 3 * BAR, CUT - 0.5, BEAT * 1.5):
    put(room, thud(), p, 0.5, 0.3)

# The power dies; then, after a moment, the air handling clunks back on.
put(room, thud() * 1.5, D0 - 0.25, 0.5, 0.5)

# ---------------------------------------------- 4. ...and it carries on ---
happy_section(D0, True)

# ------------------------------------------------------------- the tape ---
def ramp(t, a, b): return np.clip((t - a) / (b - a), 0, 1)
wow = 0.002 + 0.003 * ramp(t_all, B0, C0) + 0.01 * ramp(t_all, C0, CUT) - 0.01 * ramp(t_all, CUT, D0)
rate = 1 + wow * np.sin(2 * np.pi * 0.29 * t_all) + 0.0006 * np.sin(2 * np.pi * 5.1 * t_all)
sagc = ramp(t_all, C0 + 2 * BAR, CUT)
rate *= 1 - 0.16 * sagc * sagc + 0.16 * ramp(t_all, CUT, CUT + 0.01)   # sags, then snaps back
rate *= 1 - 0.015 * ramp(t_all, D0 - 0.5, D0)                            # ...but stays a little flat
src = np.cumsum(rate) / SR
for ch in range(2):
    band[ch] = np.interp(src, t_all, band[ch])
band *= 1 - ramp(t_all, CUT - 0.05, CUT) + ramp(t_all, D0, D0 + 0.05)   # hard power cut

# ------------------------------------------------------------ the place ---
def filt(x, f):
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * f(fr), len(x))

spk = lambda fr: (1 / np.sqrt(1 + (fr / 6500) ** 6)) * (1 - 1 / np.sqrt(1 + (fr / 110) ** 4)) \
    * (1 + 0.3 * np.exp(-((fr - 1300) / 600) ** 2))
dry = np.stack([filt(band[0], spk), filt(band[1], spk)])
# Unsafe: the speakers start to break up.
crush = ramp(t_all, C0 + BAR, CUT) * 0.8
pk = np.abs(dry).max()
broken = np.tanh(np.round(dry / pk * 10) / 10 * 3) * pk / 3
dry = dry * (1 - crush) + broken * crush

hall = dry.copy()
for d, g, side in ((0.11, 0.45, 0), (0.23, 0.35, 1), (0.37, 0.28, 0), (0.52, 0.2, 1)):
    n = int(d * SR)
    tap = np.zeros(N); tap[n:] = dry[side, :-n] * g
    tap = filt(tap, lambda fr, d=d: 1 / (1 + (fr / (3200 / (1 + d * 3))) ** 2))
    hall[1 - side] += tap * 0.8; hall[side] += tap * 0.4
hall += room * (np.abs(dry).max() / max(np.abs(room).max(), 1e-9)) * 0.35

def reverb(x, seed, secs=7.0, decay=0.85):
    r = np.random.default_rng(seed); n = int(secs * SR)
    tt = np.arange(n) / SR
    ir = filt(r.standard_normal(n) * np.exp(-tt * decay), lambda fr: 1 / (1 + (fr / 3800) ** 2))
    ir = np.concatenate([np.zeros(int(0.06 * SR)), ir])[:n]
    m = len(x) + n
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)] / np.abs(ir).sum() * 30
wet = np.stack([reverb(hall[0], 5), reverb(hall[1], 6)])
# Close and clear while it's happy; further and further away after.
dist = 0.15 + 0.35 * ramp(t_all, B0, B0 + 8 * BAR) + 0.4 * ramp(t_all, C0, CUT) - 0.25 * ramp(t_all, CUT, D0)
mix = hall * (0.75 - 0.55 * dist) + wet * (0.45 + 0.6 * dist)
# When the power dies the hall rings for a moment, then real silence.
mix *= np.clip(1 - (t_all - CUT) / 0.6, 0, 1) + ramp(t_all, D0 - 0.3, D0)

def colored(n, slope, lp):
    X = np.fft.rfft(rng.standard_normal(n)); fr = np.fft.rfftfreq(n, 1 / SR); fr[0] = 1
    X /= fr ** slope; X *= 1 / (1 + (fr / lp) ** 2)
    y = np.fft.irfft(X, n); return y / np.abs(y).max()
power = 1 - ramp(t_all, CUT - 0.05, CUT) + ramp(t_all, D0 - 0.25, D0 + 1.5)
hvac = np.stack([colored(N, 0.9, 700), colored(N, 0.9, 700)]) * 0.035 * (1 + 0.8 * ramp(t_all, C0, CUT)) * power
hum = 0.004 * (np.sin(2 * np.pi * 60 * t_all) + 0.6 * np.sin(2 * np.pi * 180 * t_all + 1)) * power
mix = mix / np.abs(mix).max() * 0.8 + hvac + hum

fade = np.ones(N); fi, fo = int(3 * SR), int(14 * SR)
fade[:fi] = np.linspace(0, 1, fi) ** 2; fade[-fo:] = np.linspace(1, 0, fo) ** 1.5
mix *= fade
mix = np.tanh(mix / np.abs(mix).max() * 1.05) / np.tanh(1.05) * 0.89
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((mix.T * 32767).astype(np.int16).tobytes())
print("seconds %.1f  sad %.0f  eerie %.0f  cut %.0f  carries on %.0f" % (END, B0, C0, CUT, D0))
