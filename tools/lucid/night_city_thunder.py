# Procedural thunder for The Blue Hour (night_city): PLACEHOLDERS, to be
# replaced by CC0 field recordings (Freesound was tried on 2026-11-08 and was
# blocked from the build environment).
#   python3 tools/lucid/night_city_thunder.py assets/levels/night_city/audio
# (needs numpy, ffmpeg). Mono Ogg Vorbis, starting at the first arrival:
#   thunder_near_1/2.ogg  a strike 1.6 km off: a sharp crack, claps, the rumble
#   thunder_mid_1/2.ogg   4 km: softer claps rolling into the rumble
#   thunder_far_1/2.ogg   9 km (an intracloud flash's channel 2-3 km up
#                         too): a low roll, the highs gone
# All at the same scale (1/r spreading and the air's absorption between
# the classes are in the files; the game adds 6 dB per halving of the
# distance within a class).
#
# The physics, simplified (Few 1969, 1995; Bass 1980): the channel is a
# tortuous line (5 m segments turning ~16 degrees on average) from the
# ground to the cloud base and on up and sideways in the cloud for
# kilometres. Each segment's shock relaxes into an N-wave a few ms long
# (longer the farther it ran), radiated mostly at right angles to the
# segment, so the parts of the channel that face you give the claps and the
# rest the rumble; each arrives r / 343 s after the flash, 1/r as loud, and
# the air absorbs its highs (~0.005 dB/m at 1 kHz, as f^1.3 in humid air,
# ISO 9613-1). Echoes off the towers (a few discrete ones, then a diffuse
# tail of ~3 s) make the city's roll.
import numpy as np, wave, subprocess, sys, os
SR = 44100
C = 343.0
out = sys.argv[1]


def channel(rng, d, cg):
    # Points of the channel (m): the listener at the origin, the strike d
    # off to the north (cg), or an intracloud channel overhead there.
    pts = []
    p = np.array([0.0, 0.0, -d])
    if not cg:
        p[1] = rng.uniform(2000, 3000)
    v = np.array([0.0, 1.0, 0.0]) if cg else np.array([rng.normal(), rng.normal() * 0.2, rng.normal()])
    v /= np.linalg.norm(v)
    top = rng.uniform(4000, 6000)
    # In the cloud the discharge runs kilometres one way (its branches
    # spread along the charge layer).
    a = rng.uniform(0, 2 * np.pi)
    heading = np.array([np.cos(a), 0.0, np.sin(a)])
    seg = 5.0
    n = 0
    while n < 2600:
        pts.append(p.copy())
        # A turn of ~16 degrees on average; under the base it climbs, in
        # the cloud it spreads sideways.
        v = v + rng.normal(size=3) * 0.28
        if cg and p[1] < top * 0.8:
            v[1] += 0.25 if p[1] < 400 else 0.08
        else:
            v[1] *= 0.5
            v = v + heading * 0.12
        v /= np.linalg.norm(v)
        p = p + v * seg
        n += 1
    return np.array(pts)


def nwave(tau):
    L = max(int(tau * SR), 8)
    t = np.linspace(0, 1, L)
    w = 1.0 - 2.0 * t
    w[:2] *= np.array([0.3, 0.8])
    return w


def absorb(x, t0):
    # The air's absorption by arrival time (r = c (t0 + t)), frame by frame.
    n = 4096
    hop = 1024
    win = np.hanning(n)
    y = np.zeros(len(x) + n)
    f = np.fft.rfftfreq(n, 1 / SR)
    alpha = 5e-3 * (np.maximum(f, 1.0) / 1000.0) ** 1.3          # dB/m
    for s in range(0, len(x), hop):
        fr = x[s:s + n]
        if len(fr) < n:
            fr = np.pad(fr, (0, n - len(fr)))
        r = C * (t0 + (s + n / 2) / SR)
        g = 10 ** (-alpha * r / 20.0)
        y[s:s + n] += np.fft.irfft(np.fft.rfft(fr * win) * g, n)
    return y[:len(x)] / 1.5


def echoes(rng, x):
    # Discrete echoes off the towers, then a diffuse tail (T60 ~3 s).
    y = x.copy()
    for _ in range(6):
        dl = int(rng.uniform(0.12, 1.3) * SR)
        g = 10 ** (rng.uniform(-18, -8) / 20)
        e = np.convolve(x, np.ones(9) / 9, 'same') * g
        y[dl:] += e[:len(y) - dl]
    L = int(3.5 * SR)
    t = np.arange(L) / SR
    tail = rng.standard_normal(L) * np.exp(-6.9 * t / 3.0)
    tail = np.convolve(tail, np.ones(30) / 30, 'same')
    tail[:int(0.05 * SR)] = 0
    wet = np.fft.irfft(np.fft.rfft(x, len(x) + L) * np.fft.rfft(tail, len(x) + L), len(x) + L)[:len(x)]
    return y + wet / (np.max(np.abs(wet)) + 1e-9) * np.max(np.abs(x)) * 0.35


def thunder(seed, d, cg):
    rng = np.random.default_rng(seed)
    pts = channel(rng, d, cg)
    r = np.linalg.norm(pts, axis=1)
    seg = np.diff(pts, axis=0)
    seg /= np.linalg.norm(seg, axis=1)[:, None]
    mid = 0.5 * (pts[1:] + pts[:-1])
    rm = np.linalg.norm(mid, axis=1)
    cosang = np.abs(np.sum(seg * (-mid / rm[:, None]), axis=1))
    # Mostly at right angles to the segment.
    direc = np.exp(-(cosang / 0.3) ** 2) + 0.08
    t0 = rm.min() / C - 0.05
    dur = rm.max() / C - t0 + 4.5
    x = np.zeros(int(dur * SR) + SR)
    for k in range(len(rm)):
        # The return stroke is strongest near the ground (its current
        # fades with height): shorter, stronger shocks there, the crack.
        low = np.exp(-max(mid[k][1], 0.0) / 250.0) if cg else 0.0
        tau = 0.003 * (rm[k] / 1000.0) ** 0.25 * rng.uniform(0.6, 1.6) * (1.0 - 0.5 * low)
        w = nwave(tau) * direc[k] / rm[k] * rng.uniform(0.6, 1.4) * (1.0 + 1.5 * low)
        a = int((rm[k] / C - t0) * SR)
        x[a:a + len(w)] += w
    x = absorb(x, t0)
    x = echoes(rng, x)
    fade = int(1.5 * SR)
    x[-fade:] *= np.linspace(1, 0, fade)
    return x


def save(name, x):
    p = os.path.join(out, name + '.wav')
    y = np.clip(x, -1, 1)
    with wave.open(p, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((y * 32767).astype(np.int16).tobytes())
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', p, '-c:a', 'libvorbis', '-q:a', '4',
                    os.path.join(out, name + '.ogg')], check=True)
    os.remove(p)


sets = [('thunder_near', 1600.0, True), ('thunder_mid', 4000.0, True), ('thunder_far', 9000.0, False)]
clips = {}
for name, d, cg in sets:
    for k in (1, 2):
        clips['%s_%d' % (name, k)] = thunder(len(name) * 31 + k * 7, d, cg)
scale = 0.95 / max(np.max(np.abs(clips['thunder_near_1'])), np.max(np.abs(clips['thunder_near_2'])))
for n, x in clips.items():
    save(n, x * scale)
    print(n, '%.1f s' % (len(x) / SR), 'peak %.3f' % np.max(np.abs(x * scale)))
