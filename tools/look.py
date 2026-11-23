#!/usr/bin/env python3
"""What a place looks like from the road: cuts the view toward a point out of the nearest all-round road photos
already fetched (tools/vegbilder.py), for judging a building by eye.

    python3 tools/look.py X Z [how many] [reach in metres]  ->  data/vegbilder/look/X_Z_k.jpg

X, Z in the game's metres. The cut is 90 degrees wide, centred on the point, the horizon in its upper half.
"""
import json, math, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "vegbilder")


def main(x, z, count=3, reach=90.0):
    have = set(os.listdir(os.path.join(DIR, "img")))
    rows = [q for q in json.load(open(os.path.join(DIR, "images.json"))) if q["id"] + ".jpg" in have]
    rows.sort(key=lambda q: math.hypot(q["x"] - x, q["z"] - z))
    out = os.path.join(DIR, "look")
    os.makedirs(out, exist_ok=True)
    done, seen = [], []
    for q in rows:
        d = math.hypot(q["x"] - x, q["z"] - z)
        if d > reach or len(done) >= count:
            break
        if any(math.hypot(q["x"] - sx, q["z"] - sz) < 12.0 for sx, sz in seen):
            continue                                        # (not the same view twice)
        seen.append((q["x"], q["z"]))
        im = Image.open(os.path.join(DIR, "img", q["id"] + ".jpg"))
        w, h = im.size
        bearing = math.degrees(math.atan2(x - q["x"], -(z - q["z"]))) % 360.0      # compass: 0 north (-z), 90 east (+x)
        col = int(((bearing - q["heading"]) % 360.0) / 360.0 * w + w / 2) % w
        im = Image.fromarray(__import__("numpy").roll(__import__("numpy").asarray(im), w // 2 - col, axis=1))
        half = w // 8
        cut = im.crop((w // 2 - half, int(h * 0.36), w // 2 + half, int(h * 0.74)))
        path = os.path.join(out, "%d_%d_%d.jpg" % (round(x), round(z), len(done)))
        cut.save(path, quality=88)
        done.append((path, round(d), q["id"]))
    return done


if __name__ == "__main__":
    a = sys.argv[1:]
    for path, d, pid in main(float(a[0]), float(a[1]), int(a[2]) if len(a) > 2 else 3, float(a[3]) if len(a) > 3 else 90.0):
        print(path, d, "m", pid)
