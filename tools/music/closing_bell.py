"""'Closing Bell' - original chase music for Backrooms-OSS (the Dead Mall).
Exactly 60 seconds, ending on a hit when the chase ends. A horror chase
score, not a song: stabbing low strings in an uneven 3-3-2 pulse, huge
toms and struck metal, distorted brass swells a tritone apart, screeching
string glissandi, a heartbeat that speeds up and a Shepard tone that seems
to rise forever - all in a vast, empty, echoing mall. In the middle the
'Fountain Court' tune drifts past, far away, slow and out of tune.
Everything is synthesized: no samples."""
import numpy as np, wave, sys

SR = 44100
rng = np.random.default_rng(66)
BPM = 144.0
BEAT = 60.0 / BPM
BAR = 4 * BEAT
S16 = BEAT / 4
BARS = 36
CHASE = BARS * BAR                 # 60.0 s
TOTAL = CHASE + 6.0
N = int(SR * TOTAL)
t_all = np.arange(N) / SR
dry = np.zeros((2, N))
send = np.zeros((2, N))

def mtof(m): return 440.0 * 2 ** ((m - 69) / 12)

def put(sig, t0, pan=0.5, gain=1.0, wet=0.3):
    s0 = int(round(t0 * SR))
    if s0 >= N or s0 < 0: return
    n = min(len(sig), N - s0)
    for ch, g in ((0, 1 - pan), (1, pan)):
        dry[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4 * (1 - 0.5 * wet)
        send[ch, s0:s0 + n] += sig[:n] * gain * g * 1.4 * wet

def bandnoise(n, lo, hi):
    X = np.fft.rfft(rng.standard_normal(n)); fr = np.fft.rfftfreq(n, 1 / SR)
    X *= (fr > lo) & (fr < hi)
    y = np.fft.irfft(X, n); return y / (np.abs(y).max() + 1e-9)

def saw_ph(ph, hmax, roll):
    out = np.zeros_like(ph)
    for h in range(1, hmax + 1):
        out += np.sin(ph * h) / h ** roll
    return out

# ------------------------------------------------------------ sounds ---
def string_stab(m, vel):
    """Short, hard bowed note (a section: three slightly detuned players)."""
    n = int(0.35 * SR); t = np.arange(n) / SR
    out = np.zeros(n)
    for d in (-8, 0, 7):
        f = mtof(m) * 2 ** ((d + rng.uniform(-3, 3)) / 1200)
        out += saw_ph(2 * np.pi * f * t, 18, 1.15)
    bow = bandnoise(n, 1200, 6000) * np.exp(-t * 60) * 0.5
    env = np.minimum(t / 0.006, 1) * np.exp(-t * (9 - 3 * vel))
    return np.tanh((out * 0.35 + bow) * env * (1.2 + vel)) * vel

def tremolo_cluster(notes, dur):
    n = int(dur * SR); t = np.arange(n) / SR
    out = np.zeros(n)
    for i, m in enumerate(notes):
        f = mtof(m) * (1 + 0.004 * np.sin(2 * np.pi * (5.3 + i * 0.4) * t + i))
        ph = 2 * np.pi * np.cumsum(f) / SR
        trem = 0.55 + 0.45 * np.abs(np.sin(2 * np.pi * (6.5 + i * 0.7) * t + i))
        out += saw_ph(ph, 8, 1.4) * trem
    env = (t / dur) ** 1.6 * np.clip((dur - t) / 0.05, 0, 1)        # crescendo
    return out * env * 0.18

def screech(f0, f1, dur):
    n = int(dur * SR); t = np.arange(n) / SR
    out = np.zeros(n)
    for d in (-25, 0, 31):
        f = f0 * (f1 / f0) ** (t / dur) * 2 ** (d / 1200) * (1 + 0.012 * np.sin(2 * np.pi * 7 * t))
        out += saw_ph(2 * np.pi * np.cumsum(f) / SR, 6, 1.6)
    env = np.minimum(t / 0.3, 1) * np.clip((dur - t) / 0.25, 0, 1)
    return out * env * 0.12

def braam(roots, dur):
    """Low brass blast: detuned saws that brighten as they swell, then distort."""
    n = int((dur + 1.0) * SR); t = np.arange(n) / SR
    swell = np.minimum(t / 0.35, 1) ** 2 * np.clip(1 - (t - dur) / 1.0, 0, 1)
    out = np.zeros(n)
    for m in roots:
        for d in (-14, -5, 6, 15):
            ph = 2 * np.pi * mtof(m) * 2 ** (d / 1200) * t
            for h in range(1, 30):
                out += np.sin(ph * h + d) / h * np.clip(swell * 30 - h, 0, 1) ** 0.5 / h ** 0.3
    return np.tanh(out * swell * 0.25) * 0.9

def tom(v=1.0, pitch=1.0):
    n = int(0.9 * SR); t = np.arange(n) / SR
    body = np.sin(2 * np.pi * np.cumsum((48 + 70 * np.exp(-t * 18)) * pitch) / SR) * np.exp(-t * 4.5)
    skin = bandnoise(n, 100, 1800) * np.exp(-t * 22) * 0.5
    return np.tanh((body + skin) * 1.8) * v

def metal(v=1.0, base=None):
    """Struck metal: a railing, a shutter, a cart - inharmonic, ringing."""
    n = int(2.2 * SR); t = np.arange(n) / SR
    f0 = base or rng.uniform(180, 420)
    out = np.zeros(n)
    for r, a, dec in ((1.0, 1.0, 2.5), (2.32, 0.7, 3.5), (3.87, 0.5, 4.5), (5.41, 0.35, 6), (7.13, 0.25, 8), (9.6, 0.15, 11)):
        out += np.sin(2 * np.pi * f0 * r * t + rng.uniform(0, 6)) * a * np.exp(-t * dec)
    hit = bandnoise(n, 800, 9000) * np.exp(-t * 90) * 0.8
    return (out * 0.5 + hit) * v

def heartbeat(v=1.0):
    def thud(tt): return np.sin(2 * np.pi * np.cumsum(40 + 35 * np.exp(-tt * 25)) / SR) * np.exp(-tt * 14)
    n = int(0.6 * SR); t = np.arange(n) / SR
    out = thud(t) + np.concatenate([np.zeros(int(0.22 * SR)), thud(t)[:n - int(0.22 * SR)] * 0.7])
    return out * v

def chime(m, dur):
    f = mtof(m)
    n = int((dur + 4.0) * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * f * t) + 0.5 * np.sin(2 * np.pi * 2.76 * f * t) * np.exp(-t * 1.5) \
        + 0.25 * np.sin(2 * np.pi * 5.4 * f * t) * np.exp(-t * 3)
    return tone * np.minimum(t / 0.002, 1) * np.exp(-t * 0.6)

def ghost_vibe(m, dur):
    f = mtof(m) * 2 ** (-35 / 1200)                 # out of tune
    n = int((dur + 3.0) * SR); t = np.arange(n) / SR
    tone = np.sin(2 * np.pi * f * t) + 0.2 * np.sin(8 * np.pi * f * t) * np.exp(-t * 3)
    trem = 1 - 0.3 * (0.5 + 0.5 * np.sin(2 * np.pi * 4.0 * t))
    return tone * trem * np.minimum(t / 0.003, 1) * np.exp(-t * 0.8)

def shepard(dur, rise_oct):
    n = int(dur * SR); t = np.arange(n) / SR
    pos = (t / dur) * rise_oct
    out = np.zeros(n)
    for k in range(8):
        oct_ = (k + pos) % 8
        f = 35.0 * 2 ** oct_
        amp = np.exp(-((oct_ - 4.2) / 1.5) ** 2)
        out += saw_ph(2 * np.pi * np.cumsum(f) / SR, 3, 2.0) * amp
    return out * 0.07

# -------------------------------------------------------------- score ---
def bt(b, beat=0.0): return b * BAR + beat * BEAT

# 3-3-2 accents over 16ths, on E with the semitone (F) and tritone (Bb) leaning in.
PULSE = [(0, 40, 1.0), (3, 40, .9), (6, 41, .9), (8, 40, 1.0), (11, 40, .9), (14, 46, .9)]
FILL = [1, 2, 4, 5, 7, 9, 10, 12, 13, 15]

# 0: the mall's PA chime - wrong, slowed, dropping - then the first blow.
for i, m in enumerate((67, 63, 66, 61)):
    put(chime(m - 12, 0.5), i * 0.42, 0.35 + 0.3 * (i % 2), 0.3, 0.8)
put(braam([40, 46], 2.6), bt(1), 0.5, 0.55, 0.5)
put(tom(1.3), bt(1), 0.5, 0.7, 0.6)
put(metal(1.0, 210), bt(1), 0.3, 0.35, 0.8)
put(screech(900, 1500, 2.0), bt(1, 1), 0.7, 0.6, 0.7)

for b in range(2, BARS):
    sec = 1 if b < 10 else 2 if b < 18 else 3 if b < 24 else 4 if b < 34 else 5
    # The string pulse (thins to just the accents in the breakdown).
    for i16, m, v in PULSE:
        if sec == 3 and i16 not in (0, 8):
            continue
        put(string_stab(m, v), bt(b) + i16 * S16, 0.45, 0.36, 0.15)
        put(string_stab(m + 12, v * 0.8), bt(b) + i16 * S16 + 0.004, 0.6, 0.3, 0.2)
    if sec in (2, 4, 5):
        for i16 in FILL:
            put(string_stab(40 if i16 % 3 else 52, 0.45), bt(b) + i16 * S16, 0.5, 0.2, 0.1)
    # Toms on the accents; doubling up later.
    if sec in (1, 2, 4, 5):
        for i16 in (0, 6, 8, 14) if sec == 1 else (0, 3, 6, 8, 11, 14):
            put(tom(1.0 if i16 in (0, 8) else 0.7, 1.0 if i16 % 8 else 0.85), bt(b) + i16 * S16, 0.5, 0.26, 0.45)
    if sec in (4, 5) and b % 2 == 1:
        for i in range(4):
            put(tom(0.6 + 0.1 * i, 1.3 - 0.1 * i), bt(b, 2 + i * 0.5), 0.3 + 0.13 * i, 0.38, 0.45)
    # Struck metal, irregular.
    if sec != 3 and rng.random() < (0.5 if sec < 4 else 0.85):
        put(metal(0.8), bt(b, rng.choice([1.5, 2.75, 3.25])), rng.uniform(0.15, 0.85), 0.45, 0.7)
    # Brass blasts: every 4 bars, then every 2.
    if (sec in (1, 2) and b % 4 == 2) or (sec in (4, 5) and b % 2 == 0):
        put(braam([40, 46] if (b // 2) % 2 else [40, 41], BAR * 1.2), bt(b), 0.5, 0.42, 0.4)
# High string tremolo clusters that swell and cut off.
for b0, notes in ((10, [76, 77, 82]), (14, [77, 78, 83]), (26, [79, 80, 85]), (30, [81, 82, 87, 88])):
    put(tremolo_cluster(notes, BAR * 4), bt(b0), 0.55, 0.8, 0.5)
# Screeches.
for b0, f0, f1 in ((12, 1100, 1700), (20, 700, 2600), (22, 1500, 900), (28, 1300, 2300), (32, 1600, 3100)):
    put(screech(f0, f1, BAR * 1.5), bt(b0, 2), rng.uniform(0.25, 0.75), 0.9, 0.8)
# Heartbeat from the second section, speeding up.
tb = bt(10); rate = 1.6
while tb < CHASE - 1.0:
    put(heartbeat(1.0 if 18 * BAR < tb < 24 * BAR else 0.6), tb, 0.5, 0.45, 0.05)
    rate = max(0.55, rate * 0.985)
    tb += rate
# Breakdown: the Fountain Court tune, far away, slow and out of tune.
GHOST = [(0, 76, 1), (1, 75, 1), (2, 76, 2), (4, 80, 2), (6, 78, 2), (8, 76, 3), (11, 73, 1), (12, 71, 4)]
for beat_, m, ln in GHOST:
    put(ghost_vibe(m - 12, ln * BEAT * 1.5), bt(18) + beat_ * BEAT * 1.5, 0.4, 0.22, 1.0)
for i, m in enumerate((55, 51)):
    put(chime(m - 12, 1.0), bt(21) + i * 1.2, 0.3 + 0.4 * i, 0.3, 1.0)
# The endless rise, from the second section to the end.
sh = shepard(CHASE - bt(10), 3.0)
put(sh * np.minimum(np.arange(len(sh)) / SR / 6.0, 1), bt(10), 0.5, 1.0, 0.4)
# Final two bars: a roaring riser of noise, then silence, then the last hit.
rn = int(2 * BAR * SR); rt = np.arange(rn) / SR
riser = np.zeros(rn)
for k in range(24):
    a, b2 = k * rn // 24, (k + 1) * rn // 24
    lo = 150 * 2 ** (k / 4.0)
    riser[a:b2] = bandnoise(b2 - a, lo, lo * 2.5)
put(riser * (rt / rt[-1]) ** 2.5, bt(34), 0.5, 0.45, 0.4)
dry[:, int((CHASE - 0.35) * SR):int(CHASE * SR)] = 0.0
send[:, int((CHASE - 0.35) * SR):int(CHASE * SR)] = 0.0
put(braam([40, 46, 52], 2.5), CHASE, 0.5, 0.8, 0.7)
put(tom(1.5, 0.8), CHASE, 0.5, 0.9, 0.7)
put(metal(1.2, 160), CHASE, 0.5, 0.5, 0.9)

# --------------------------------------------------- the empty building ---
def filt(x, f):
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    return np.fft.irfft(X * f(fr), len(x))
def reverb(x, seed, secs=6.0, decay=0.75):
    r = np.random.default_rng(seed); n = int(secs * SR); tt = np.arange(n) / SR
    ir = filt(r.standard_normal(n) * np.exp(-tt * decay), lambda fr: 1 / (1 + (fr / 4000) ** 2))
    ir = np.concatenate([np.zeros(int(0.045 * SR)), ir])[:n]
    m = len(x) + n
    return np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)] / np.abs(ir).sum() * 28
out = dry + np.stack([reverb(send[0], 7), reverb(send[1], 8)]) * 1.1
hum = 0.003 * (np.sin(2 * np.pi * 60 * t_all) + 0.6 * np.sin(2 * np.pi * 120 * t_all + 1) + 0.4 * np.sin(2 * np.pi * 180 * t_all))
out += hum * (np.abs(out).max())
out = np.stack([filt(o, lambda fr: (1 / np.sqrt(1 + (fr / 13000) ** 4)) * (1 - 1 / np.sqrt(1 + (fr / 32) ** 4))) for o in out])
fade = np.ones(N); fo = int(5 * SR); fade[-fo:] = np.linspace(1, 0, fo) ** 2
fade[:int(0.01 * SR)] = np.linspace(0, 1, int(0.01 * SR))
out *= fade
out = np.tanh(out / np.abs(out).max() * 1.7) / np.tanh(1.7) * 0.92
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((out.T * 32767).astype(np.int16).tobytes())
print("chase %.1f s, total %.1f s" % (CHASE, TOTAL))
