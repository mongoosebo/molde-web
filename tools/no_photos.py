#!/usr/bin/env python3
"""Which streets have no street photos yet: data/no_photos.png.

Wall and roof colours are read off street photos (tools/colours.py): Mapillary's (data/mapillary/images.json,
tools/mapillary.py) and Statens vegvesen's road photos (data/vegbilder/images.json, tools/vegbilder.py). This
draws the map with every street in it: green where a photo was taken within 25 m, red where none was. The red
streets are where to go with the Mapillary phone app; after uploading, run tools/mapillary.py and
tools/colours.py again. Prints how many kilometres have photos and lists the longest streets without.

    .venv/bin/python tools/no_photos.py
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import LAT0, LON0, MX, MZ, X0, X1, Z0, Z1

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SCALE = 0.5                                     # pixels a metre
DRIVEN = {"motorway", "trunk", "primary", "secondary", "tertiary", "unclassified", "residential", "living_street", "service", "pedestrian",
          "motorway_link", "trunk_link", "primary_link", "secondary_link", "tertiary_link"}


def photos():
    pts = []
    for path in ("data/mapillary/images.json", "data/vegbilder/images.json"):
        try:
            rows = json.load(open(os.path.join(ROOT, path)))
        except OSError:
            continue
        rows = rows.values() if isinstance(rows, dict) else rows
        for r in rows:
            if "x" in r and "z" in r:
                pts.append((r["x"], r["z"]))
            else:
                g = r.get("computed_geometry") or r.get("geometry")
                if g and g.get("coordinates"):
                    lon, lat = g["coordinates"][:2]
                    pts.append(((lon - LON0) * MX, (LAT0 - lat) * MZ))
    return np.asarray(pts, float)


def main():
    P = photos()
    tree = cKDTree(P) if len(P) else None
    w, h = int((X1 - X0) * SCALE), int((Z1 - Z0) * SCALE)
    img = Image.new("RGB", (w, h), (18, 20, 22))
    dr = ImageDraw.Draw(img)
    with_m = without_m = 0.0
    bare = {}
    for e in json.load(open(os.path.join(ROOT, "data", "osm_raw.json")))["elements"]:
        t = e.get("tags", {})
        if e["type"] != "way" or t.get("highway") not in DRIVEN or not e.get("geometry"):
            continue
        g = [((p["lon"] - LON0) * MX, (LAT0 - p["lat"]) * MZ) for p in e["geometry"]]
        for (xa, za), (xb, zb) in zip(g, g[1:]):
            if not (X0 < xa < X1 and Z0 < za < Z1):
                continue
            ln = float(np.hypot(xb - xa, zb - za))
            n = max(1, int(ln / 10.0))
            for k in range(n):
                p0 = (xa + (xb - xa) * k / n, za + (zb - za) * k / n)
                p1 = (xa + (xb - xa) * (k + 1) / n, za + (zb - za) * (k + 1) / n)
                mid = ((p0[0] + p1[0]) / 2, (p0[1] + p1[1]) / 2)
                seen = tree is not None and tree.query(mid)[0] < 25.0
                dr.line([((p0[0] - X0) * SCALE, (p0[1] - Z0) * SCALE), ((p1[0] - X0) * SCALE, (p1[1] - Z0) * SCALE)],
                        fill=(70, 170, 90) if seen else (225, 70, 60), width=2 if seen else 3)
                if seen:
                    with_m += ln / n
                else:
                    without_m += ln / n
                    name = t.get("name") or "(a %s road without a name)" % t.get("highway")
                    bare[name] = bare.get(name, 0.0) + ln / n
    out = os.path.join(ROOT, "data", "no_photos.png")
    img.save(out)
    print("streets with a photo within 25 m: %.1f km; without: %.1f km (%d photos known)" % (with_m / 1000, without_m / 1000, len(P)))
    print("the longest without (metres):")
    for name, m in sorted(bare.items(), key=lambda kv: -kv[1])[:25]:
        if not name.startswith("("):
            print("  %-30s %5.0f" % (name, m))
    print("the map:", out, "(green: photographed, red: not)")


if __name__ == "__main__":
    main()
