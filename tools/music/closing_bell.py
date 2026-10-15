"""'Closing Bell' - original chase music for Backrooms-OSS (the Dead Mall).
Exactly 60 seconds (40 bars at 160 BPM), ending on a hit when the chase
ends. The mall's PA chime announces it; a distorted E-phrygian bass drives
it; the opening phrase of 'Fountain Court' returns twisted into minor as a
screaming lead; a Shepard tone (a pitch that seems to rise forever) runs
under the second half, like the mall looping around you.
Everything is synthesized: no samples."""
import numpy as np, wave, sys

SR = 44100
rng = np.random.default_rng(66)
BPM = 160.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
S16 = BEAT / 4
BARS = 40
CHASE = BARS * BAR                 # 60.0 s
TOTAL = CHASE + 4.0
N = int(SR * TOTAL)
t_all = np.arange(N) / SR
mix = np.zeros((2, N))
verb_send = np.zeros((2, N))

def mtof(m): return 440.0 * 2 ** ((m - 69) / 12)

def put(sig, t0, pan=0.5, gain=1.0, send=0.2):
    s0 = int(round(t0 * SR))
    if s0 >= N: return
    n = min(len(sig), N - s0)
    for ch, g in ((0, 1 - pan), (1, pan)):
        mix[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4
        verb_send[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4 * send

def saw(f, t, bright=1.0, hmax=60):
    out = np.zeros_like(t)
    for h in range(1, hmax):
        if f * h > 9000: break
        out += np.sin(2 * np.pi * f * h * t) / h * np.exp(-(h - 1) * (0.25 / bright))
    return out

def bandnoise(n, lo, hi):
    X = np.fft.rfft(rng.standard_normal(n)); fr = np.fft.rfftfreq(n, 1 / SR)
    X *= (fr > lo) & (fr < hi)
    y = np.fft.irfft(X, n); return y / (np.abs(y).max() + 1e-9)

# ------------------------------------------------------------- drums ---
def kick(v=1.0):
    n = int(0.4 * SR); t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum(42 + 120 * np.exp(-t * 28)) / SR) * np.exp(-t * 7)
    click = bandnoise(n, 1500, 7000) * np.exp(-t * 300) * 0.4
    return np.tanh((body + click) * 2.2) * v

def snare(v=1.0):
    n = int(0.3 * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * 190 * t) * np.exp(-t * 25)
    noise = bandnoise(n, 300, 9000) * np.exp(-t * 14)
    return np.tanh((tone * 0.6 + noise) * 1.8) * v

def hat(v=1.0, open_=False):
    n = int((0.25 if open_ else 0.05) * SR); t = np.arange(n) / SR
    return bandnoise(n, 7000, 18000) * np.exp(-t * (10 if open_ else 80)) * v

def thump():
    n = int(0.35 * SR); t = np.arange(n) / SR
    return np.sin(2 * np.pi * np.cumsum(50 + 40 * np.exp(-t * 20)) / SR) * np.exp(-t * 9)

# --------------------------------------------------------------- tones ---
def bass(m, dur, accent):
    f = mtof(m)
    n = int((dur + 0.05) * SR); t = np.arange(n) / SR
    sig = saw(f, t, bright=0.9 + 0.9 * accent) + 0.35 * np.sin(2 * np.pi * f * t)
    env = np.minimum(t / 0.003, 1) * np.clip(1 - (t - dur) / 0.03, 0, 1) * (0.7 + 0.3 * np.exp(-t * 12))
    return np.tanh(sig * env * (1.8 + accent)) * 0.8

def stab(notes, dur):
    n = int((dur + 0.15) * SR); t = np.arange(n) / SR
    out = sum(saw(mtof(m) * 2 ** (rng.uniform(-12, 12) / 1200), t, 1.2, 25) for m in notes)
    env = np.minimum(t / 0.004, 1) * np.exp(-t * 6) * np.clip(1 - (t - dur) / 0.1, 0, 1)
    return np.tanh(out * env * 1.5) * 0.6

def lead(m, dur, bend=0.0):
    f = mtof(m)
    n = int((dur + 0.2) * SR); t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 6.0 * t) * np.clip((t - 0.15) / 0.2, 0, 1)
    fr = f * vib * 2 ** (np.clip(t / dur, 0, 1) * bend / 1200)
    out = np.zeros(n)
    for det in (-9, 9):                       # two detuned square-ish oscillators
        ph = 2 * np.pi * np.cumsum(fr * 2 ** (det / 1200)) / SR
        for h in range(1, 16, 2):
            out += np.sin(ph * h) / h
    env = np.minimum(t / 0.01, 1) * np.clip(1 - (t - dur) / 0.12, 0, 1)
    return np.tanh(out * env * 1.6) * 0.5

def chime(m, dur):
    f = mtof(m)
    n = int((dur + 2.5) * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t * 2) \
        + 0.25 * np.sin(2 * np.pi * 5.4 * f * t) * np.exp(-t * 5)
    return tone * np.minimum(t / 0.002, 1) * np.exp(-t * 1.1)

def shepard(t0, t1, rise_oct=1.0):
    n = int((t1 - t0) * SR); t = np.arange(n) / SR
    pos = (t / (t1 - t0)) * rise_oct           # octaves risen so far
    out = np.zeros(n)
    for k in range(8):
        oct_ = (k + pos) % 8                   # each partial climbs and wraps around
        f = 40.0 * 2 ** oct_
        amp = np.exp(-((oct_ - 4.0) / 1.6) ** 2)
        ph = 2 * np.pi * np.cumsum(f) / SR
        out += np.sin(ph) * amp
    return out * 0.12

# Bass riff in E phrygian (16ths, two bars), accents for drive.
RIFF = [40, 40, 52, 40, 41, 40, 52, 40, 40, 40, 43, 40, 41, 52, 50, 41,
        40, 40, 52, 40, 41, 40, 52, 40, 40, 43, 41, 40, 47, 46, 41, 40]
ACC = [1, 0, .5, 0, 1, 0, .5, 0, 1, 0, .6, 0, 1, .4, .6, .3] * 2
# The 'Fountain Court' opening phrase, now in E minor, screamed.
TWISTED = [(0, 76, .5), (.5, 75, .5), (1, 76, 1), (2, 79, 1), (3, 77, 1), (4, 76, 1.5), (5.5, 72, .5), (6, 71, 2),
           (8, 72, .5), (8.5, 76, .5), (9, 77, 1), (10, 79, 1.5), (11.5, 77, .5), (12, 76, 1), (13, 75, 1), (14, 76, 2, -100)]
STABS = [[52, 55, 59, 65], [53, 57, 60, 64], [52, 55, 59, 62], [50, 53, 58, 65]]   # Em(b9) Fmaj7 Em7 Bb(b5) colour

def bar_t(b): return b * BAR

# ---------------------------------------------------------------- score ---
# 0-1: the PA chime, wrong, and an impact.
put(kick(1.3), 0.0, 0.5, 0.9, 0.4)
for i, (m, d) in enumerate(((79, 0.0), (75, 0.55), (79, 1.1), (74, 1.65))):
    put(chime(m - (0.0 if i < 2 else 0.6), 0.5), d, 0.4 + 0.2 * (i % 2), 0.22, 0.7)
for b in range(BARS):
    t0 = bar_t(b)
    sec = 0 if b < 2 else 1 if b < 10 else 2 if b < 18 else 3 if b < 26 else 4 if b < 38 else 5
    # Bass: from bar 2 on (half-time feel and lighter in the breakdown).
    if sec >= 1:
        for i in range(16):
            ri = (b % 2) * 16 + i
            if sec == 3 and i % 2:
                continue
            put(bass(RIFF[ri], S16 * (0.85 if sec != 3 else 1.7), ACC[ri]), t0 + i * S16, 0.5, 0.2, 0.05)
    # Drums.
    if sec in (1, 2, 4, 5):
        for q in range(4):
            put(kick(), t0 + q * BEAT, 0.5, 0.45, 0.05)
        for q in (1, 3):
            put(snare(), t0 + q * BEAT, 0.5, 0.6, 0.25)
        for i in range(16):
            put(hat(0.9 if i % 4 == 2 else 0.55, open_=(i % 8 == 6)), t0 + i * S16, 0.65, 0.3, 0.1)
        if sec in (4, 5) and b % 4 == 3:          # fills into each phrase
            for i in range(8):
                put(snare(0.5 + 0.06 * i), t0 + 2 * BEAT + i * S16, 0.5, 0.35, 0.2)
    elif sec == 3:                                 # breakdown: heavy half-time, heartbeat
        put(kick(1.1), t0, 0.5, 0.8, 0.1); put(snare(1.1), t0 + 2 * BEAT, 0.5, 0.55, 0.4)
        put(thump(), t0 + 3 * BEAT, 0.5, 0.5); put(thump(), t0 + 3.4 * BEAT, 0.5, 0.35)
    # Corrupted muzak stabs.
    if sec in (2, 4, 5):
        ch = STABS[(b // 2) % 4]
        for at in ((0, 0.75), (1.5, 0.4), (3, 0.3)) if b % 2 == 0 else ((0.5, 0.4), (2.5, 1.0)):
            put(stab(ch, at[1] * BEAT), t0 + at[0] * BEAT, 0.5 + rng.uniform(-0.2, 0.2), 0.3, 0.3)
# The twisted tune: bars 10-17 and again, higher and harder, 30-37.
for start, shift, g in ((10, 0, 0.32), (30, 12, 0.28), (34, 12, 0.28)):
    for n_ in TWISTED:
        bt, m, ln = n_[:3]
        bend = n_[3] if len(n_) > 3 else 0.0
        if start == 34 and bt >= 8:
            break
        put(lead(m + shift - 12, ln * BEAT * 2, bend), bar_t(start) + bt * BEAT * 2, 0.55, g, 0.35)
# Breakdown: the chime returns, slowed and low; the Shepard tone starts and never stops rising.
for i, m in enumerate((67, 63, 67, 62)):
    put(chime(m, 1.0), bar_t(18) + i * BAR * 2, 0.3 + 0.4 * (i % 2), 0.2, 0.8)
sh = shepard(bar_t(18), CHASE, rise_oct=2.5)
put(sh * np.minimum(np.arange(len(sh)) / SR / 4.0, 1), bar_t(18), 0.5, 1.0, 0.3)
# Final build: snare roll and a noise riser, then the hit at 60 s.
for i in range(32):
    put(snare(0.4 + 0.02 * i), bar_t(38) + i * BAR * 2 / 32, 0.5, 0.35, 0.25)
rn = int(2 * BAR * SR); rt = np.arange(rn) / SR
riser = np.zeros(rn)
for k in range(16):                             # a rising band of noise, in 16 slices
    a, b2 = k * rn // 16, (k + 1) * rn // 16
    lo = 400 * 2 ** (k / 3.5)
    riser[a:b2] = bandnoise(b2 - a, lo, lo * 3)
put(riser * (rt / rt[-1]) ** 2, bar_t(38), 0.5, 0.35, 0.3)
put(kick(1.4), CHASE, 0.5, 1.0, 0.6)
put(stab([40, 52, 53, 59], 1.5), CHASE, 0.5, 0.3, 0.8)
put(chime(64, 2.0), CHASE + 0.05, 0.5, 0.25, 0.9)

# ------------------------------------------------------------ the space ---
def filt(x, f):
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * f(fr), len(x))
def reverb(x, seed):
    r = np.random.default_rng(seed); n = int(3.5 * SR); tt = np.arange(n) / SR
    ir = filt(r.standard_normal(n) * np.exp(-tt * 1.6), lambda fr: 1 / (1 + (fr / 4500) ** 2))
    m = len(x) + n
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)] / np.abs(ir).sum() * 25
out = mix + np.stack([reverb(verb_send[0], 3), reverb(verb_send[1], 4)]) * 0.9
# Glue: gentle pump from the kick, soft clip, slight high-cut.
out = np.stack([filt(o, lambda fr: (1 / np.sqrt(1 + (fr / 14000) ** 4)) * (1 - 1 / np.sqrt(1 + (fr / 38) ** 4))) for o in out])
fade = np.ones(N); fi = int(0.01 * SR); fade[:fi] = np.linspace(0, 1, fi)
fo = int(3.5 * SR); fade[-fo:] = np.linspace(1, 0, fo) ** 2
out *= fade
out = np.tanh(out / np.abs(out).max() * 1.6) / np.tanh(1.6) * 0.92
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out.T * 32767).astype(np.int16).tobytes())
print("chase %.1f s, total %.1f s" % (CHASE, TOTAL))
