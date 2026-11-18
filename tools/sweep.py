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

tools/sweep.py --street  reads the street-level sweep instead (`./run.sh -- --sweep-street`, data/sweep_street/):
sixteen views from each place, each taken as the game draws it and again with the ground taken away. It finds

  through  ground seen where paving should be: paving that shows only when the ground is gone, at a spot
           where the line of sight should have met paving first (the map's own ground and paving say so): the
           ground stands up through it there, or flickers over it, or the wrong ground is drawn
  sky      empty sky seen looking downward, where there must always be ground or sea: a crack through the world

and turns each into a map position (roughly: where that line of sight meets level ground). It writes
data/sweep_street.json, copies the pictures that have something in them to data/sweep_street/found/, prints the
totals and exits with an error when there are any.
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


def street():
    import math
    import shutil
    idx = json.load(open(os.path.join(ROOT, "data", "sweep_street", "index.json")))
    W, H, fov, pitch, eyes = idx["w"], idx["h"], idx["fov"], idx["pitch"], idx["eyes"]
    focal = (H / 2) / math.tan(math.radians(fov) / 2)          # (Godot's field of view is the upright one)
    out_dir = os.path.join(ROOT, "data", "sweep_street", "found")
    shutil.rmtree(out_dir, ignore_errors=True)
    os.makedirs(out_dir)
    # the downward slope of each pixel's line of sight (the camera looks `pitch` degrees down)
    v = (np.arange(H) + 0.5 - H / 2) / focal
    u = (np.arange(W) + 0.5 - W / 2) / focal
    cp, sp = math.cos(math.radians(pitch)), math.sin(math.radians(pitch))
    fwd = cp + v[:, None] * sp * 0 + np.zeros((H, W))            # forward part of the ray (camera frame, before the turn)
    ray_y = sp * 1.0 - v[:, None] * cp + np.zeros((H, W))        # up part: looking down is negative
    ray_f = cp * 1.0 + v[:, None] * sp + np.zeros((H, W))
    ray_r = u[None, :] + np.zeros((H, W))
    norm = np.sqrt(ray_y ** 2 + ray_f ** 2 + ray_r ** 2)
    down = -ray_y / norm                                         # sine of the angle below level
    # the map's own ground and paving, to follow a line of sight to what it should meet
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import holes
    meta = json.load(open(os.path.join(ROOT, "world", "meta.json")))
    G = holes.Ground(meta, holes.load_ground(meta))
    paved = holes.load_paved()
    masks = {}

    def is_paved(px, pz):
        """Whether points lie on paving (0.25 m squares, each cell's laid out when first asked about)."""
        out = np.zeros(len(px), bool)
        cx, cz = np.floor(px / 100.0).astype(int), np.floor(pz / 100.0).astype(int)
        for key in set(zip(cx.tolist(), cz.tolist())):
            if key not in paved:
                continue
            if key not in masks:
                m = np.zeros((400, 400), bool)
                for name in "AS":
                    T = paved[key][name]
                    for c0 in range(0, len(T), 4000):
                        tx, tz, _y, _t = holes.samples(T[c0:c0 + 4000], 0.125)
                        m[np.clip(((tz - key[1] * 100.0) / 0.25).astype(int), 0, 399), np.clip(((tx - key[0] * 100.0) / 0.25).astype(int), 0, 399)] = True
                masks[key] = m
            sel = (cx == key[0]) & (cz == key[1])
            out[sel] = masks[key][np.clip(((pz[sel] - key[1] * 100.0) / 0.25).astype(int), 0, 399), np.clip(((px[sel] - key[0] * 100.0) / 0.25).astype(int), 0, 399)]
        return out

    steps = np.concatenate([np.arange(0.5, 40.0, 0.2), np.arange(40.0, 420.0, 1.0)])
    found = []
    for n, x, y, z in idx["places"]:
        path = os.path.join(ROOT, "data", "sweep_street", "%05d.png" % n)
        im = np.asarray(Image.open(path).convert("RGB")).astype(np.int16)
        r, g, b = im[..., 0], im[..., 1], im[..., 2]
        paving = ((r > 190) & (g < 70) & (b > 190)) | ((r < 70) & (g > 190) & (b > 190)) | ((r < 70) & (g < 70) & (b > 190))
        sky = (r < 30) & (g > 225) & (b < 30)
        hit = False
        for c in range(16):
            cx, cy = (c % 8) * W, (c // 8) * H
            a_pav, b_pav = paving[cy:cy + H, cx:cx + W], paving[cy + 2 * H:cy + 3 * H, cx:cx + W]
            a_sky = sky[cy:cy + H, cx:cx + W]
            yaw = -2 * math.pi * (c % 8) / 8.0
            eye = y + eyes[c // 8]
            # the camera looks along -Z turned by yaw about Y; right is +X turned the same way
            fx, fz = -math.sin(yaw), -math.cos(yaw)
            rx, rz = math.cos(yaw), -math.sin(yaw)

            def meets(vv, uu):
                """Where the lines of sight through pixels first meet the map's ground: x, z, distance."""
                dx = (ray_f[vv, uu] * fx + ray_r[vv, uu] * rx) / norm[vv, uu]
                dz = (ray_f[vv, uu] * fz + ray_r[vv, uu] * rz) / norm[vv, uu]
                dy = ray_y[vv, uu] / norm[vv, uu]
                px = x + dx[:, None] * steps[None, :]
                pz = z + dz[:, None] * steps[None, :]
                py = eye + dy[:, None] * steps[None, :]
                under = py <= G.near(px, pz) + 0.12              # (the paving lies 10 cm over the ground)
                first = np.where(under.any(1), under.argmax(1), len(steps) - 1)
                k = np.arange(len(vv))
                return px[k, first], pz[k, first], steps[first]
            # ground where paving should be
            cand = b_pav & ~a_pav & ~a_sky
            lab, k = ndimage.label(cand)
            for i in range(1, k + 1):
                m = lab == i
                if m.sum() < 60 or ndimage.binary_erosion(m, structure=np.ones((2, 2), bool)).sum() < 2:      # (smaller: the foot of a kerb, a sliver)
                    continue
                vv, uu = np.nonzero(m)
                pick = np.linspace(0, len(vv) - 1, min(len(vv), 24)).astype(int)
                px, pz, dist = meets(vv[pick], uu[pick])
                # (well inside the paving: a bank right beside a road is rightly seen in front of it; edges are tools/holes.py's)
                on = is_paved(px, pz) & is_paved(px + 0.8, pz) & is_paved(px - 0.8, pz) & is_paved(px, pz + 0.8) & is_paved(px, pz - 0.8)
                # far off, a line of sight skims the ground and a pixel is many metres of it: the answer must hold
                # a pixel higher and a pixel lower too
                for dv in (-1, 1):
                    qx, qz, _d = meets(np.clip(vv[pick] + dv, 0, H - 1), uu[pick])
                    on &= is_paved(qx, qz)
                if on.mean() < 0.6:
                    continue                                    # the ground is rightly in front of the paving there
                found.append(["through", round(float(np.median(px[on])), 1), round(float(np.median(pz[on])), 1), int(m.sum()), n, c, round(float(np.median(dist[on])), 1)])
                hit = True
            # sky looking downward
            low = a_sky & (down > 0.08)
            lab, k = ndimage.label(low)
            for i in range(1, k + 1):
                m = lab == i
                if m.sum() < 80:
                    continue                                    # (small ones are glass and gaps in things, not the world)
                vv, uu = np.nonzero(m)
                px, pz, dist = meets(vv[:1], uu[:1])
                found.append(["sky", round(float(px[0]), 1), round(float(pz[0]), 1), int(m.sum()), n, c, round(float(dist[0]), 1)])
                hit = True
        if hit:
            shutil.copy(path, out_dir)
    found.sort(key=lambda f: (f[0], -f[3]))
    json.dump(found, open(os.path.join(ROOT, "data", "sweep_street.json"), "w"))
    tot = {}
    for f in found:
        t = tot.setdefault(f[0], [0, set()])
        t[0] += 1
        t[1].add(f[4])
    print("street sweep: %d places looked at" % len(idx["places"]))
    for k in ("through", "sky"):
        t = tot.get(k, [0, set()])
        print("  %-8s %5d patches, seen from %d places" % (k, t[0], len(t[1])))
    sys.exit(1 if found else 0)


def main():
    if "--street" in sys.argv:
        street()
        return
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
