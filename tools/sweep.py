#!/usr/bin/env python3
"""Reads the road sweep: the straight-down pictures of every paved tile that `./run.sh -- --sweep` leaves in
data/sweep/, and compares them with the outlines the map builder meant to pave (data/paved_expect.pkl).

Finds, with a position for each:
  poke    asphalt was meant here, the picture shows ground (the ground stands through, or nothing was laid)
  walk    sidewalk was meant here, the picture shows ground
  slit    a strip of ground narrower than about 1.2 m between two paved surfaces
  pocket  a small patch of ground wholly enclosed by paving
  paint   road paint lying on something that is not asphalt

Writes data/sweep.json and prints the totals.   tools/sweep.py --crop x,z,r out.png  cuts a picture out.
"""
import glob
import json
import os
import pickle
import sys

import numpy as np
import shapely
from PIL import Image, ImageDraw
from scipy import ndimage

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "sweep")
TILE, N = 200.0, 2000
PX = TILE / N


def classes(path):
    im = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
    r, g, b = im[..., 0], im[..., 1], im[..., 2]
    asphalt = (r > 190) & (g < 70) & (b > 190)
    walk = (r < 70) & (g > 190) & (b > 190)
    paint = (r < 70) & (g < 70) & (b > 190)
    deck = (r > 190) & (g > 190) & (b < 70)
    return asphalt, walk, paint, deck


def raster(geom, tx, tz):
    """A geometry as a mask over one tile."""
    img = Image.new("1", (N, N), 0)
    if geom is None or geom.is_empty:
        return np.zeros((N, N), bool)
    d = ImageDraw.Draw(img)
    x0, z0 = tx * TILE, tz * TILE
    part = shapely.intersection(geom, shapely.box(x0 - 1, z0 - 1, x0 + TILE + 1, z0 + TILE + 1))
    for p in getattr(part, "geoms", [part]):
        if p.geom_type != "Polygon" or p.is_empty:
            continue
        d.polygon([((x - x0) / PX, (z - z0) / PX) for x, z in p.exterior.coords], fill=1)
        for hole in p.interiors:
            d.polygon([((x - x0) / PX, (z - z0) / PX) for x, z in hole.coords], fill=0)
    return np.asarray(img, bool)


def spots(mask, tx, tz, kind, least, out, extra=None):
    lab, n = ndimage.label(mask)
    if n == 0:
        return
    idx = np.arange(1, n + 1)
    area = ndimage.sum(mask, lab, idx) * PX * PX
    com = ndimage.center_of_mass(mask, lab, idx)
    for a, (v, u) in zip(area, com):
        if a >= least:
            out.append([kind, round(tx * TILE + u * PX, 1), round(tz * TILE + v * PX, 1), round(float(a), 2)])


def main():
    if "--crop" in sys.argv:
        x, z, r = [float(v) for v in sys.argv[sys.argv.index("--crop") + 1].split(",")]
        out = sys.argv[sys.argv.index("--crop") + 2]
        tx, tz = int(x // TILE), int(z // TILE)
        im = Image.open(os.path.join(DIR, "%d_%d.png" % (tx, tz))).convert("RGB")
        u, v = (x - tx * TILE) / PX, (z - tz * TILE) / PX
        im.crop((int(u - r / PX), int(v - r / PX), int(u + r / PX), int(v + r / PX))).resize((900, 900), Image.NEAREST).save(out)
        return
    exp = pickle.load(open(os.path.join(ROOT, "data", "paved_expect.pkl"), "rb"))
    g = {k: (shapely.from_wkb(v) if v is not None else None) for k, v in exp.items()}
    for v in g.values():
        if v is not None:
            shapely.prepare(v)
    ball = np.hypot(*np.mgrid[-6:7, -6:7]) <= 6.2
    found = []
    for path in sorted(glob.glob(os.path.join(DIR, "*.png"))):
        tx, tz = [int(v) for v in os.path.basename(path)[:-4].split("_")]
        asphalt, walk, paint, deck = classes(path)
        paved = asphalt | walk | paint | deck
        laid = raster(g["road_laid"], tx, tz)
        side = raster(g["side"], tx, tz)
        dk = raster(g["deck"], tx, tz)
        blds = raster(g["buildings"], tx, tz)
        inner = ndimage.binary_erosion(laid, iterations=3)
        spots(inner & ~paved, tx, tz, "poke", 0.25, found)
        spots(ndimage.binary_erosion(side, iterations=3) & ~paved, tx, tz, "walk", 0.25, found)
        # ground closed in by paving, and thin strips of it between paved surfaces (buildings count as closed)
        solid = paved | blds
        closed = ndimage.binary_closing(np.pad(solid, 8), structure=ball)[8:-8, 8:-8]
        spots(closed & ~solid, tx, tz, "slit", 0.3, found)
        lab, n = ndimage.label(~solid)
        if n:
            edge = set(np.unique(np.concatenate([lab[0], lab[-1], lab[:, 0], lab[:, -1]])))
            idx = [i for i in range(1, n + 1) if i not in edge]
            if idx:
                area = ndimage.sum(~solid, lab, idx) * PX * PX
                keep = [i for i, a in zip(idx, area) if 0.3 <= a < 40.0]
                if keep:
                    spots(np.isin(lab, keep), tx, tz, "pocket", 0.3, found)
        off = paint & ~ndimage.binary_dilation(laid | dk, iterations=4)
        spots(off, tx, tz, "paint", 0.15, found)
    found.sort(key=lambda f: (f[0], -f[3]))
    json.dump(found, open(os.path.join(ROOT, "data", "sweep.json"), "w"))
    tot = {}
    for k, _x, _z, a in found:
        t = tot.setdefault(k, [0, 0.0])
        t[0] += 1
        t[1] += a
    print("sweep:", "  ".join("%s %d (%.0f m2)" % (k, n, a) for k, (n, a) in sorted(tot.items())))


if __name__ == "__main__":
    main()
