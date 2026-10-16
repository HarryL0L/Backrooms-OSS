#!/usr/bin/env python3
"""Cuts the trailer together from the frames _test/trailer.tscn recorded.

    python3 tools/trailer/edit.py <frames_dir> <sfx_dir> <out.mp4>

frames_dir holds one folder of JPEG frames per shot (NN_name/0000.jpg ...),
sfx_dir the WAVs the recorder writes with `-- sfx=<dir>`. Title cards are
drawn here with PIL; music comes from music/. Needs ffmpeg and Pillow.
"""
import glob
import os
import random
import subprocess
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

FPS = 30
W, H = 1280, 720
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SERIF = "/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf"
SANS = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
SANS_B = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"

# The cut: ("shot", name, fade_in, fade_out) or ("card", lines, secs) or
# ("black", secs). Fades are in seconds (to/from black).
EDIT = [
    ("card", ["You noclipped out of reality."], 3.0),
    ("shot", "lobby", 0.8, 0.0),
    ("shot", "flicker", 0.0, 0.3),
    ("card", ["The hum never stops."], 2.2),
    ("shot", "gallery", 0.3, 0.0),
    ("shot", "pool", 0.0, 0.0),
    ("shot", "pipes", 0.0, 0.0),
    ("shot", "habitable", 0.0, 0.0),
    ("shot", "unlit", 0.0, 0.4),
    ("card", ["Someone left arrows on the walls."], 2.4),
    ("shot", "arrow", 0.3, 0.0),
    ("shot", "mall_door", 0.0, 0.0),
    ("shot", "field_door", 0.0, 0.0),   # ends on white by itself
    ("shot", "field", 0.0, 0.0),        # starts on white
    ("shot", "field_exit", 0.0, 0.5),
    ("card", ["Not every door", "leads somewhere better."], 2.8),
    ("shot", "mall", 0.5, 0.0),
    ("shot", "court", 0.0, 0.0),
    ("shot", "window", 0.0, 0.3),
    ("card", ["Don't look away."], 2.0),
    ("shot", "dresser_still", 0.3, 0.0),
    ("shot", "dresser_wake", 0.0, 0.0),
    ("shot", "dresser_run", 0.0, 0.0),
    ("shot", "dresser_lunge", 0.0, 0.0),
    ("black", 1.4),
    ("title", 4.5),
    ("card", ["Free and open source.", "Android  ·  LAN co-op  ·  Seven levels"], 3.5),
]


def font(path, size):
    return ImageFont.truetype(path, size)


def grain(img, amount, seed):
    rnd = random.Random(seed)
    noise = Image.effect_noise((W // 2, H // 2), 40).resize((W, H)).convert("RGB")
    return Image.blend(img, noise, amount * (0.8 + 0.4 * rnd.random()))


def card_frames(lines, secs, out_dir, title=False):
    os.makedirs(out_dir, exist_ok=True)
    n = int(secs * FPS)
    base = Image.new("RGB", (W, H), (0, 0, 0))
    d = ImageDraw.Draw(base)
    if title:
        f1 = font(SANS_B, 92)
        t = "BACKROOMS-OSS"
        tw = d.textlength(t, font=f1)
        # A sodium-yellow glow behind the title, like the Lobby's light.
        glow = Image.new("RGB", (W, H), (0, 0, 0))
        gd = ImageDraw.Draw(glow)
        gd.text(((W - tw) / 2, H / 2 - 80), t, font=f1, fill=(200, 180, 90))
        glow = glow.filter(ImageFilter.GaussianBlur(18))
        base = Image.blend(base, glow, 0.9)
        d = ImageDraw.Draw(base)
        d.text(((W - tw) / 2, H / 2 - 80), t, font=f1, fill=(236, 226, 170))
        f2 = font(SERIF, 26)
        s = "There is no way out. Only further in."
        d.text(((W - d.textlength(s, font=f2)) / 2, H / 2 + 40), s, font=f2, fill=(175, 168, 140))
    else:
        f = font(SERIF, 40 if len(lines) == 1 else 36)
        y = H / 2 - len(lines) * 26
        for i, line in enumerate(lines):
            if i == 1 and line.startswith("Android"):
                f = font(SANS, 26)
            tw = d.textlength(line, font=f)
            d.text(((W - tw) / 2, y), line, font=f, fill=(222, 214, 180))
            y += 60
    for i in range(n):
        # Fade in over 0.5 s, out over 0.5 s; a little flicker and grain.
        a = min(1.0, i / (0.5 * FPS), (n - 1 - i) / (0.5 * FPS))
        if random.Random(i * 7 + len(lines)).random() < 0.04:
            a *= 0.6
        img = Image.blend(Image.new("RGB", (W, H)), base, max(0.0, a))
        img = grain(img, 0.05, i)
        img.save(f"{out_dir}/{i:04d}.jpg", quality=92)
    return n


def run(cmd):
    subprocess.run(cmd, check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)


def main():
    frames, sfx, out = sys.argv[1], sys.argv[2], sys.argv[3]
    work = os.path.join(os.path.dirname(os.path.abspath(out)), "trailer_work")
    os.makedirs(work, exist_ok=True)
    shot_dirs = {}
    for dpath in glob.glob(os.path.join(frames, "*_*")):
        if os.path.isdir(dpath):
            shot_dirs[os.path.basename(dpath).split("_", 1)[1]] = dpath
    segs = []
    t = 0.0
    times = {}                      # shot name -> (start, duration) on the timeline
    for k, item in enumerate(EDIT):
        seg = os.path.join(work, f"seg{k:02d}.mp4")
        if item[0] == "shot":
            _, name, fin, fout = item
            src = shot_dirs[name]
            n = len(glob.glob(src + "/*.jpg"))
            dur = n / FPS
            vf = []
            if fin > 0:
                vf.append(f"fade=t=in:st=0:d={fin}")
            if fout > 0:
                vf.append(f"fade=t=out:st={dur - fout:.3f}:d={fout}")
            run(["ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{src}/%04d.jpg"]
                + (["-vf", ",".join(vf)] if vf else [])
                + ["-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", "-preset", "medium", seg])
            times[name] = (t, dur)
        else:
            if item[0] == "black":
                n = int(item[1] * FPS)
                cdir = os.path.join(work, f"card{k:02d}")
                os.makedirs(cdir, exist_ok=True)
                for i in range(n):
                    Image.new("RGB", (W, H)).save(f"{cdir}/{i:04d}.jpg")
            elif item[0] == "title":
                cdir = os.path.join(work, f"card{k:02d}")
                n = card_frames([], item[1], cdir, title=True)
                times["title"] = (t, item[1])
            else:
                cdir = os.path.join(work, f"card{k:02d}")
                n = card_frames(item[1], item[2], cdir)
                times.setdefault("cards", []).append((t, item[2]))
            dur = n / FPS
            run(["ffmpeg", "-y", "-framerate", str(FPS), "-i", f"{cdir}/%04d.jpg",
                 "-c:v", "libx264", "-pix_fmt", "yuv420p", "-crf", "17", seg])
        segs.append(seg)
        t += dur
    total = t
    lst = os.path.join(work, "list.txt")
    with open(lst, "w") as f:
        for s in segs:
            f.write(f"file '{s}'\n")
    video = os.path.join(work, "video.mp4")
    run(["ffmpeg", "-y", "-f", "concat", "-safe", "0", "-i", lst, "-c", "copy", video])

    # ---------------------------------------------------------------- sound
    inputs = []
    chains = []

    def add(path, start, dur, vol=1.0, fin=0.0, fout=0.0, loop=False, extra=""):
        i = len(inputs) + 1          # input 0 is the video
        inputs.append((path, loop))
        fl = [f"atrim=0:{dur:.3f}", "asetpts=PTS-STARTPTS"]
        if extra:
            fl.append(extra)
        if fin > 0:
            fl.append(f"afade=t=in:st=0:d={fin}")
        if fout > 0:
            fl.append(f"afade=t=out:st={max(0.0, dur - fout):.3f}:d={fout}")
        fl.append(f"volume={vol}")
        ms = int(start * 1000)
        fl.append(f"adelay={ms}|{ms}")
        chains.append(f"[{i}:a]aformat=sample_rates=44100:channel_layouts=stereo," + ",".join(fl) + f"[a{i}]")

    S = lambda n: os.path.join(sfx, n + ".wav")
    MENU = os.path.join(ROOT, "music/empty_hours.ogg")
    MALL = os.path.join(ROOT, "music/fountain_court.ogg")
    st = lambda n: times[n][0]
    du = lambda n: times[n][1]
    end_backrooms = st("field_door") + du("field_door")
    # The Backrooms: the hum under everything, the tube's buzz, the menu theme.
    add(S("hum"), 0.0, end_backrooms, 0.55, 1.5, 0.3, loop=True)
    add(S("drone"), 0.0, end_backrooms, 0.35, 2.0, 0.3, loop=True)
    add(S("buzz"), st("flicker"), du("flicker"), 0.8, 0.2, 0.3, loop=True)
    add(MENU, st("gallery") - 2.2, end_backrooms - st("gallery") + 2.2 + du("field") , 0.75, 2.0, 2.5)
    add(S("drip"), st("pipes") + 0.6, 2.0, 0.6)
    add(S("draught"), st("arrow"), du("arrow"), 0.5, 0.4, 0.4, loop=True)
    # Muzak through the mall door, muffled.
    add(MALL, st("mall_door"), du("mall_door"), 0.9, 1.0, 0.2, extra="lowpass=f=700")
    add(S("creak"), st("field_door") + 0.3 * du("field_door"), 1.5, 0.9)
    # The Field: open air.
    add(S("wind"), st("field"), du("field") + du("field_exit"), 0.9, 0.6, 0.8, loop=True)
    # The mall: the music, a little slow and sour.
    m0 = st("mall")
    wake = st("dresser_wake")
    add(MALL, m0, wake - m0, 0.85, 0.8, 0.05, extra="asetrate=44100*0.92,aresample=44100,lowpass=f=5000")
    add(S("hum"), m0, wake - m0, 0.25, 1.0, 0.1, loop=True)
    add(S("crack"), wake, 2.0, 1.6)
    # Stop-motion footsteps: one per pose change.
    run0 = st("dresser_run")
    k = 0.0
    while k < du("dresser_run") - 0.1:
        add(S("clack"), run0 + k, 0.5, 1.2 + k * 0.4)
        k += 0.24
    add(S("shriek"), st("dresser_lunge"), 2.5, 1.8, 0.0, 1.2)
    # The title.
    tt = times["title"][0]
    add(S("drone"), tt - 0.5, total - tt + 0.5, 0.6, 1.0, 2.0, loop=True)
    add(MENU, tt, total - tt, 0.6, 1.5, 2.5)

    cmd = ["ffmpeg", "-y", "-i", video]
    for path, loop in inputs:
        cmd += (["-stream_loop", "-1"] if loop else []) + ["-i", path]
    mix = ";".join(chains) + ";" + "".join(f"[a{i + 1}]" for i in range(len(inputs))) \
        + f"amix=inputs={len(inputs)}:normalize=0,alimiter=limit=0.9,atrim=0:{total:.3f}[aout]"
    cmd += ["-filter_complex", mix, "-map", "0:v", "-map", "[aout]",
            "-c:v", "copy", "-c:a", "aac", "-b:a", "192k", "-shortest", out]
    subprocess.run(cmd, check=True)
    print(f"trailer: {out} ({total:.1f} s)")


if __name__ == "__main__":
    main()
