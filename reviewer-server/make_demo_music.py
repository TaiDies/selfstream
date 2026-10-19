"""Makes the demo library: short original tracks synthesized from scratch (no samples, no recordings), so there is
nothing to license. Released under CC0. Needs numpy, Pillow and ffmpeg.   python3 make_demo_music.py OUT_DIR"""
import os, subprocess, sys, wave
import numpy as np
from PIL import Image, ImageDraw, ImageFont

SR = 44100
rng = np.random.default_rng(7)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def env(n, a=0.01, d=0.15, s=0.6, r=0.2):
    e = np.ones(n); a, d, r = int(a * SR), int(d * SR), int(r * SR)
    a = min(a, n); e[:a] = np.linspace(0, 1, a, endpoint=False) if a else 1
    d2 = min(d, max(n - a, 0)); e[a:a + d2] = np.linspace(1, s, d2) if d2 else 1
    e[a + d2:] = s
    r = min(r, n); e[n - r:] *= np.linspace(1, 0, r) if r else 1
    return e

def tone(freq, dur, harm=(1, .5, .25, .12), **adsr):
    n = int(dur * SR); t = np.arange(n) / SR
    w = sum(a * np.sin(2 * np.pi * freq * (i + 1) * t) for i, a in enumerate(harm))
    return w / max(sum(harm), 1e-9) * env(n, **adsr)

def add(buf, x, at):
    i = int(at * SR); j = min(i + len(x), len(buf))
    if i < len(buf): buf[i:j] += x[:j - i]

def kick(): 
    t = np.arange(int(.25 * SR)) / SR; f = 120 * np.exp(-t * 18) + 40
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 11)

def hat():
    n = int(.05 * SR); return rng.standard_normal(n) * np.exp(-np.arange(n) / SR * 90) * .25

def snare():
    n = int(.18 * SR); t = np.arange(n) / SR
    return (rng.standard_normal(n) * .6 + np.sin(2 * np.pi * 190 * t) * .4) * np.exp(-t * 22)

SCALES = {"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10]}

def chord(root, kind, deg):
    sc = SCALES[kind]
    return [root + sc[(deg + o) % 7] + 12 * ((deg + o) // 7) for o in (0, 2, 4)]

def make(path, bpm, root, kind, prog, lead, drums, bass, harm, seconds=44, seed=0):
    r = np.random.default_rng(seed)
    beat = 60 / bpm; bar = beat * 4
    buf = np.zeros(int(seconds * SR))
    bars = int(seconds / bar)
    for b in range(bars):
        t0 = b * bar; deg = prog[b % len(prog)]; ch = chord(root, kind, deg)
        for m in ch:
            add(buf, tone(hz(m), bar * .98, harm=(1, .3, .1), a=.25, d=.4, s=.7, r=.4) * .16, t0)
        if bass:
            for k in range(4):
                add(buf, tone(hz(ch[0] - 24), beat * .9, harm=(1, .5), a=.005, d=.1, s=.5, r=.1) * .35, t0 + k * beat)
        steps = 8 if lead == "arp" else 4
        for k in range(steps):
            if lead == "arp":
                m = ch[k % 3] + 12
            else:
                m = (root + SCALES[kind][int(r.integers(0, 7))] + 12) if r.random() > .25 else None
            if m is not None:
                add(buf, tone(hz(m), beat * (.5 if lead == "arp" else 1), harm=harm, a=.004, d=.2, s=.3, r=.1) * .24, t0 + k * beat * (4 / steps))
        if drums:
            for k in range(4):
                if k % 2 == 0: add(buf, kick() * .55, t0 + k * beat)
                else: add(buf, snare() * .35, t0 + k * beat)
                add(buf, hat(), t0 + k * beat); add(buf, hat() * .6, t0 + k * beat + beat / 2)
    buf /= max(np.abs(buf).max(), 1e-6) / .85
    fade = int(1.5 * SR); buf[-fade:] *= np.linspace(1, 0, fade)
    st = np.stack([buf, np.roll(buf, 220) * .96], 1)  # a touch of stereo
    wav = path + ".wav"
    with wave.open(wav, "wb") as w:
        w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes((st * 32767).astype("<i2").tobytes())
    return wav

def cover(path, title, c1, c2):
    img = Image.new("RGB", (600, 600), c1); d = ImageDraw.Draw(img)
    for i in range(0, 600, 12):
        d.line([(0, i), (600, 600 - i)], fill=c2, width=2)
    d.rectangle([60, 230, 540, 370], fill=(10, 10, 14))
    try: f = ImageFont.truetype("DejaVuSans-Bold.ttf", 44)
    except Exception: f = ImageFont.load_default()
    d.text((300, 300), title, fill=(255, 255, 255), font=f, anchor="mm")
    img.save(path, quality=90)

ALBUMS = [
    ("Demo Orchestra", "Demo Album One", 2024, (30, 60, 110), (70, 130, 200), [
        ("Opening Theme", 92, 60, "major", [0, 4, 5, 3], "arp", False, True, (1, .4, .2)),
        ("Morning Light", 100, 62, "major", [0, 5, 3, 4], "arp", True, True, (1, .2)),
        ("Quiet Streets", 76, 57, "minor", [0, 5, 2, 6], "line", False, True, (1, .5, .1, .05)),
    ]),
    ("Sample Beats", "Sample Beats Vol. 1", 2024, (90, 40, 90), (200, 90, 170), [
        ("Test Groove", 110, 55, "minor", [0, 3, 4, 0], "arp", True, True, (1, .6, .3)),
        ("Loop Station", 124, 58, "minor", [0, 5, 3, 6], "arp", True, True, (1, .3, .3, .2)),
        ("Short Circuit", 98, 52, "minor", [0, 6, 5, 4], "line", True, True, (1, .7, .4)),
    ]),
    ("Test Tones", "Calibration", 2025, (30, 90, 70), (110, 200, 150), [
        ("Reference A", 84, 57, "major", [0, 3, 0, 4], "line", False, False, (1, .2)),
        ("Pink Horizon", 70, 59, "major", [0, 2, 5, 3], "line", False, True, (1, .4, .1)),
        ("Last Sample", 88, 54, "minor", [0, 2, 5, 4], "arp", False, True, (1, .5, .25, .1)),
    ]),
]

out = sys.argv[1]
n = 0
for artist, album, year, c1, c2, tracks in ALBUMS:
    d = os.path.join(out, artist, album); os.makedirs(d, exist_ok=True)
    cov = os.path.join(d, "cover.jpg"); cover(cov, album, c1, c2)
    for i, (title, bpm, root, kind, prog, lead, drums, bass, harm) in enumerate(tracks, 1):
        n += 1
        wav = make(os.path.join(d, f"{i:02d}"), bpm, root, kind, prog, lead, drums, bass, harm, seed=n)
        mp3 = os.path.join(d, f"{i:02d} - {title}.mp3")
        subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", wav, "-i", cov, "-map", "0:a", "-map", "1:v", "-c:a", "libmp3lame", "-b:a", "160k",
                        "-c:v", "mjpeg", "-id3v2_version", "3", "-metadata:s:v", "title=Album cover", "-metadata:s:v", "comment=Cover (front)",
                        "-metadata", f"title={title}", "-metadata", f"artist={artist}", "-metadata", f"album_artist={artist}",
                        "-metadata", f"album={album}", "-metadata", f"track={i}/{len(tracks)}", "-metadata", f"date={year}",
                        "-metadata", "genre=Demo", "-metadata", "comment=Original synthesized demo track, CC0", mp3], check=True)
        os.remove(wav)
print("tracks:", n)
