"""'Empty Hours' - an original liminal ambient piece for Backrooms-OSS.
Everything is synthesized here: no samples, no borrowed melody."""
import numpy as np, wave, sys

SR = 44100
rng = np.random.default_rng(7)
BAR = 9.0                      # seconds per chord
INTRO = 4.0
chords = [                      # MIDI notes; dreamy, unresolved major-7/9 voicings in Db
    [49, 56, 60, 63, 65],       # Dbmaj9
    [46, 53, 56, 60, 61],       # Bbm9
    [42, 49, 53, 58, 60],       # Gbmaj7#11
    [44, 51, 56, 58, 63],       # Absus2
    [49, 56, 60, 65, 68],       # Dbmaj9 (higher)
    [41, 48, 51, 56, 58],       # Fm7 add11
    [42, 49, 53, 56, 65],       # Gbmaj9
    [42, 49, 53, 58, 60],       # Gbmaj7#11 - never resolves
]
TOTAL = INTRO + BAR * len(chords) + 10.0
N = int(SR * TOTAL)
t_all = np.arange(N) / SR

def mtof(m): return 440.0 * 2 ** ((m - 69) / 12)

def env_adsr(n, a, r):
    e = np.ones(n)
    na, nr = int(a * SR), int(r * SR)
    e[:na] = np.linspace(0, 1, na) ** 2
    e[-nr:] *= np.linspace(1, 0, nr) ** 1.5
    return e

L = np.zeros(N); R = np.zeros(N)

# --- Pads: soft detuned saw-ish tones (additive, gentle roll-off), slow swell.
for ci, ch in enumerate(chords):
    start = INTRO + ci * BAR - 2.0 if ci else 0.5
    dur = BAR + 5.0
    s0 = int(max(start, 0) * SR); n = min(int(dur * SR), N - s0)
    t = np.arange(n) / SR
    e = env_adsr(n, 3.0, 4.5)
    for k, m in enumerate(ch):
        f = mtof(m)
        for d, pan in ((-6, 0.25), (0, 0.5), (6, 0.75)):
            fd = f * 2 ** (d / 1200)
            ph = rng.uniform(0, 2 * np.pi)
            sig = np.zeros(n)
            for h in range(1, 9):
                if fd * h > 6000: break
                sig += np.sin(2 * np.pi * fd * h * t + ph * h) / h ** 1.7
            amp = 0.05 * (0.8 if k == 0 else 1.0) * (1 + 0.15 * np.sin(2 * np.pi * (0.07 + 0.013 * k) * t + k))
            L[s0:s0 + n] += sig * e * amp * (1 - pan)
            R[s0:s0 + n] += sig * e * amp * pan

# --- Sub drone on the root, very quiet.
root = np.zeros(N)
for ci, ch in enumerate(chords):
    s0 = int((INTRO + ci * BAR) * SR); n = min(int((BAR + 3) * SR), N - s0)
    t = np.arange(n) / SR
    root[s0:s0 + n] += np.sin(2 * np.pi * mtof(ch[0] - 12) * t) * env_adsr(n, 2.0, 3.0) * 0.06
L += root; R += root

# --- Melody: a glassy electric-piano / music-box voice, sparse, original.
# (time in beats of 1.5 s from INTRO, MIDI note, velocity)
B = 1.5
melody = [
    (0, 80, .8), (1, 77, .6), (2, 75, .7), (4.5, 72, .5),
    (6, 77, .7), (7, 75, .5), (8, 73, .6), (10, 70, .5),
    (12, 72, .7), (13, 73, .6), (14, 77, .7), (16.5, 75, .5),
    (18, 80, .7), (19, 82, .6), (20, 80, .5), (22, 77, .6),
    (24, 85, .6), (25, 84, .5), (26, 80, .7), (28.5, 77, .5),
    (30, 75, .6), (31, 77, .5), (32, 72, .6), (34, 70, .5),
    (36, 73, .6), (37, 75, .5), (38, 77, .6), (40, 80, .5),
    (42, 77, .55), (43, 75, .45), (44, 72, .5), (46, 70, .4),
]
mel = np.zeros(N)
for beat, m, v in melody:
    s0 = int((INTRO + 1.0 + beat * B) * SR); n = min(int(5.0 * SR), N - s0)
    if n <= 0: continue
    t = np.arange(n) / SR
    f = mtof(m)
    tone = (np.sin(2 * np.pi * f * t) * np.exp(-t * 1.1)
            + 0.35 * np.sin(2 * np.pi * 2 * f * t) * np.exp(-t * 2.2)
            + 0.12 * np.sin(2 * np.pi * 3.01 * f * t) * np.exp(-t * 3.5)
            + 0.10 * np.sin(2 * np.pi * 4.17 * f * t) * np.exp(-t * 6.0))   # slightly inharmonic: glassy
    att = np.minimum(t / 0.004, 1.0)
    mel[s0:s0 + n] += tone * att * v * 0.11

# Echo (dotted, ping-pong-ish) on the melody.
def delay(x, sec, fb, lp=0.35):
    d = int(sec * SR); y = x.copy()
    for k in range(1, 6):
        g = fb ** k
        tap = np.zeros_like(x); tap[d * k:] = x[:-d * k] * g
        # darken each repeat
        X = np.fft.rfft(tap); fr = np.fft.rfftfreq(len(tap), 1 / SR)
        X *= 1 / (1 + (fr / (5000 / (1 + k))) ** 2)
        y += np.fft.irfft(X, len(tap))
    return y
melL = delay(mel, 1.125, 0.42); melR = delay(np.roll(mel, int(0.375 * SR)) * 0.9, 1.125, 0.42)
L += melL * 0.9; R += melR * 0.9

# --- Fluorescent hum and tape hiss underneath.
hum = (np.sin(2 * np.pi * 120 * t_all) + 0.5 * np.sin(2 * np.pi * 240 * t_all + 1) + 0.25 * np.sin(2 * np.pi * 360 * t_all + 2))
hum *= 0.006 * (1 + 0.3 * np.sin(2 * np.pi * 0.05 * t_all))
def colored_noise(n, slope):
    X = np.fft.rfft(rng.standard_normal(n)); fr = np.fft.rfftfreq(n, 1 / SR); fr[0] = 1
    X /= fr ** slope; X *= 1 / (1 + (fr / 9000) ** 2)
    y = np.fft.irfft(X, n); return y / np.abs(y).max()
hissL = colored_noise(N, 0.3) * 0.006; hissR = colored_noise(N, 0.3) * 0.006
L += hum + hissL; R += hum * 0.9 + hissR

# --- Reverb: convolution with a synthetic, darkening 5 s tail (different per side).
def reverb(x, seed):
    r = np.random.default_rng(seed); n = int(5.0 * SR)
    t = np.arange(n) / SR
    ir = r.standard_normal(n) * np.exp(-t * 1.3)
    X = np.fft.rfft(ir); fr = np.fft.rfftfreq(n, 1 / SR); X *= 1 / (1 + (fr / 3500) ** 2); ir = np.fft.irfft(X, n)
    ir[:int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))
    m = len(x) + n
    y = np.fft.irfft(np.fft.rfft(x, m) * np.fft.rfft(ir, m), m)[:len(x)]
    return y / np.abs(ir).sum() * 18
wetL = reverb(L, 1); wetR = reverb(R, 2)
L = L * 0.55 + wetL * 0.6; R = R * 0.55 + wetR * 0.6

# --- Tape: slow wow + faster flutter (pitch wobble), then a soft VHS-like top end.
warp = t_all + 0.0035 * np.sin(2 * np.pi * 0.31 * t_all) + 0.0004 * np.sin(2 * np.pi * 5.3 * t_all)
L = np.interp(warp, t_all, L); R = np.interp(warp, t_all, R)
def tone_shape(x):
    X = np.fft.rfft(x); fr = np.fft.rfftfreq(len(x), 1 / SR)
    X *= 1 / np.sqrt(1 + (fr / 7500) ** 4)          # gentle high cut
    X *= 1 - 0.6 / (1 + (fr / 45) ** 4)              # trim rumble
    return np.fft.irfft(X, len(x))
L = tone_shape(L); R = tone_shape(R)

# Fade in/out, soft saturation, normalise.
fade = np.ones(N); fi, fo = int(3 * SR), int(8 * SR)
fade[:fi] = np.linspace(0, 1, fi) ** 2; fade[-fo:] = np.linspace(1, 0, fo) ** 1.5
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max())
L = np.tanh(L / peak * 1.1) / np.tanh(1.1) * 0.89; R = np.tanh(R / peak * 1.1) / np.tanh(1.1) * 0.89
out = np.stack([L, R], 1)
pcm = (out * 32767).astype(np.int16)
with wave.open(sys.argv[1], 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR); w.writeframes(pcm.tobytes())
print("seconds", TOTAL)
