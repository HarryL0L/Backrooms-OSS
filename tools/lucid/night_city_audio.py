# Procedural city sounds for The Blue Hour (night_city): no third-party audio.
# python3 tools/lucid/night_city_audio.py assets/levels/night_city/audio  (needs numpy, ffmpeg)
import numpy as np, wave, subprocess, sys, os
SR = 44100
out = sys.argv[1]
rng = np.random.default_rng(12)

def lp(x, fc):
    a = np.exp(-2*np.pi*fc/SR); y = np.empty_like(x); s = 0.0
    for i in range(len(x)):
        s = (1-a)*x[i] + a*s; y[i] = s
    return y

def fft_band(x, lo, hi):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1/SR)
    w = np.clip((f-lo)/max(lo*0.3,1),0,1) * np.clip((hi-f)/(hi*0.3),0,1)
    return np.fft.irfft(X*w, len(x))

def loopify(x, fade=SR):
    # crossfade the end into the start
    y = x[:-fade].copy()
    t = np.linspace(0,1,fade)
    y[:fade] = x[:fade]*t + x[-fade:]*(1-t)
    return y

def save(name, x, peak=0.7):
    x = x / (np.max(np.abs(x))+1e-9) * peak
    p = os.path.join(out, name+'.wav')
    with wave.open(p,'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((x*32767).astype(np.int16).tobytes())
    subprocess.run(['ffmpeg','-y','-loglevel','error','-i',p,'-c:a','libvorbis','-q:a','3',os.path.join(out,name+'.ogg')],check=True)
    os.remove(p)

def t(sec): return np.arange(int(sec*SR))/SR

# 1. The city's hum with nobody in it: low rumble, far broadband air, mains hum.
n = int(31*SR)
br = np.cumsum(rng.standard_normal(n)); br -= np.convolve(br, np.ones(4410)/4410, 'same')
rumble = fft_band(br, 20, 140)
air = fft_band(rng.standard_normal(n), 150, 900) * 0.25
tt = np.arange(n)/SR
mains = sum(a*np.sin(2*np.pi*f*tt + p) for f,a,p in [(60,0.05,0),(120,0.12,1),(180,0.03,2),(240,0.02,0.5)])
swell = 0.8 + 0.2*np.sin(2*np.pi*tt/31.0*2) 
x = (rumble/np.std(rumble) + air/np.std(air)*0.35 + mains*3)*swell
save('city_hum', loopify(x), 0.6)

# 2. Wind between the towers: gusty band noise, a faint whistle.
n = int(31*SR); tt = np.arange(n)/SR
g = fft_band(rng.standard_normal(n), 0.05, 0.4); g = (g-g.min())/(g.max()-g.min())
wn = fft_band(rng.standard_normal(n), 250, 1800)
wh = fft_band(rng.standard_normal(n), 820, 980) * 3
x = (wn/np.std(wn))*(0.3+0.9*g) + (wh/np.std(wh))*0.25*g**2
save('wind_high', loopify(x), 0.6)

# 3. A siren far away: a slow wail, muffled by distance and buildings, echoing.
tt = t(15)
f = 950 + 420*np.sin(2*np.pi*tt/4.6 - np.pi/2)
ph = 2*np.pi*np.cumsum(f)/SR
s = np.sin(ph) + 0.4*np.sin(2*ph) + 0.15*np.sin(3*ph)
env = np.clip(tt/3,0,1)*np.clip((15-tt)/4,0,1)
s = fft_band(s*env, 300, 1600)
ir = rng.standard_normal(int(1.8*SR)) * np.exp(-np.arange(int(1.8*SR))/SR/0.45)
wet = np.convolve(s, ir)[:len(s)]
x = s*0.3 + wet/np.std(wet)*np.std(s)*0.9
save('siren_far', x, 0.5)

# 4. A lamp's ballast buzz: 120 Hz and its harmonics, a little crackle.
tt = t(4)
b = sum((1/k**1.2)*np.sin(2*np.pi*120*k*tt + k) for k in range(1,14))
cr = fft_band(rng.standard_normal(len(tt)), 2000, 8000) * (rng.random(len(tt)) < 0.002)
save('lamp_buzz', b + cr*2, 0.5)

# 5-6. Accessible pedestrian signal: a locator tick each second; the rapid
# walk tick (about 10 a second).
def tick(dur=0.03, f=880):
    tt = t(dur); return np.sin(2*np.pi*f*tt)*np.exp(-tt/0.006) + 0.3*rng.standard_normal(len(tt))*np.exp(-tt/0.002)
x = np.zeros(SR); k = tick(); x[:len(k)] += k
save('aps_locate', x, 0.6)
x = np.zeros(SR)
for i in range(10):
    k = tick(0.025, 1050); o = int(i*SR/10); x[o:o+len(k)] += k
save('aps_walk', x, 0.6)

# 7. The failing lamp's igniter: sharp ticks of the starting pulses, then
# the arc catching with a hum.
tt = t(3.0); x = np.zeros(len(tt))
for i in range(9):
    o = int((0.1 + i*0.16)*SR); k = rng.standard_normal(300)*np.exp(-np.arange(300)/40); x[o:o+300] += k
hum = sum((1/k)*np.sin(2*np.pi*120*k*tt) for k in range(1,8)) * np.clip((tt-1.6)/0.8,0,1)*np.clip((3-tt)/0.3,0,1)
save('restrike', x + hum*0.4, 0.6)
print('ok')
