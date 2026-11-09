# Procedural rain for The Blue Hour (night_city): PLACEHOLDERS, to be replaced
# by CC0 field recordings (Freesound could not be reached from the build
# environment). python3 tools/lucid/night_city_rain.py assets/levels/night_city/audio
# (needs numpy, ffmpeg)
#   rain.ogg        stereo, 20 s loop: moderate rain on hard city surfaces (wideband
#                   hiss of far drops, a dense patter of near ones, now and then a
#                   bigger splash, the low wash of the whole city)
#   rain_metal.ogg  mono, 10 s loop: drops on sheet metal (a roof, a grating), each
#                   a tick, a short rattle of band noise and a dull knock
import numpy as np, wave, subprocess, sys, os
SR = 44100
out = sys.argv[1]
rng = np.random.default_rng(7)

def band(x, lo, hi, tilt=0.0):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR)
    w = np.clip((f - lo) / max(lo * 0.5, 1), 0, 1) * np.clip((hi - f) / (hi * 0.3), 0, 1)
    w = w * (np.maximum(f, 1.0) / 1000.0) ** tilt
    return np.fft.irfft(X * w, len(x))

def loopify(x, fade):
    y = x[..., :-fade].copy(); t = np.linspace(0, 1, fade)
    y[..., :fade] = x[..., :fade] * t + x[..., -fade:] * (1 - t)
    return y

def impulses(n, rate, kern_fn, count_kern=64):
    # Poisson events, each a kernel drawn from a small bank, random gain.
    bank = [kern_fn() for _ in range(count_kern)]
    y = np.zeros(n + SR)
    k = rng.poisson(rate * n / SR)
    at = rng.integers(0, n, k); g = rng.lognormal(0, 0.7, k)
    for a, gg, b in zip(at, g, rng.integers(0, count_kern, k)):
        kk = bank[b]; y[a:a + len(kk)] += kk * gg
    y[:SR] += y[n:n + SR]          # wrap the tail round: it loops
    return y[:n]

def tick():
    # A near drop on wet stone: a click of band noise, 1-4 ms.
    L = int(SR * 0.006); tt = np.arange(L) / SR
    return rng.standard_normal(L) * np.exp(-tt / rng.uniform(0.0006, 0.002))

def splash():
    # A bigger drop into a puddle: a noisy splash and the bubble's rising plip.
    L = int(SR * 0.05); tt = np.arange(L) / SR
    f = rng.uniform(1500, 4000) * (1 + 2.0 * tt / 0.05)
    plip = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-tt / 0.008) * 0.6
    return (rng.standard_normal(L) * np.exp(-tt / 0.004) + plip)

def ping():
    # A drop on sheet metal: a sharp tick, a short bright rattle of wide noise
    # bands and a dull knock of the sheet. Noise, not sine modes: ringing
    # modes read as a synth "tink tink" in the game.
    L = int(SR * 0.06); tt = np.arange(L) / SR
    y = rng.standard_normal(L) * np.exp(-tt / 0.0008) * 0.5
    for _ in range(2):
        f0 = rng.uniform(1500, 6000)
        r = band(rng.standard_normal(L), f0 * 0.6, f0 * 1.5)
        y += r / np.std(r) * np.exp(-tt / rng.uniform(0.003, 0.012)) * rng.uniform(0.2, 0.45)
    k = band(rng.standard_normal(L), 150, 700)
    y += k / np.std(k) * np.exp(-tt / rng.uniform(0.006, 0.015)) * 0.3
    return y

def save(name, x, peak):
    x = np.atleast_2d(x); x = x / (np.max(np.abs(x)) + 1e-9) * peak
    p = os.path.join(out, name + '.wav')
    with wave.open(p, 'wb') as w:
        w.setnchannels(x.shape[0]); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x.T * 32767).astype(np.int16).tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', p, '-c:a', 'libvorbis', '-q:a', '4', os.path.join(out, name + '.ogg')], check=True)
    os.remove(p)

# 1. Rain on the city.
n = int(21 * SR); fade = SR
chans = []
common = band(rng.standard_normal(n), 400, 14000, -0.25)
wash = band(rng.standard_normal(n), 60, 500, -0.5)
for c in range(2):
    hiss = band(rng.standard_normal(n), 500, 15000, -0.2)
    patter = band(impulses(n, 1800, tick), 1200, 12000)
    near = band(impulses(n, 14, splash, 32), 300, 12000)
    x = (common / np.std(common) * 0.5 + hiss / np.std(hiss) * 0.5 + patter / np.std(patter) * 0.55
         + near / np.std(near) * 0.25 + wash / np.std(wash) * 0.35)
    chans.append(x)
save('rain', loopify(np.array(chans), fade), 0.6)

# 2. Rain on sheet metal.
n = int(11 * SR)
m = impulses(n, 70, ping, 48)
m = m / np.std(m) + band(rng.standard_normal(n), 2000, 9000) * 0.15
save('rain_metal', loopify(m, SR), 0.6)
