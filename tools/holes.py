#!/usr/bin/env python3
"""Holes in the paving, found exactly and without the game.

Reads only world/ (the 1 m ground in world/h1/, the paving triangles in world/paved.bin, world/meta.json and
world/paved_area.json) and checks every square metre of asphalt and sidewalk on the whole map, the way the game
draws it (scripts/detail.gd lifts asphalt 0.10 m and sidewalk 0.23 m off the heights in paved.bin; scripts/world.gd
draws each square metre of ground as two triangles, split from its (x+1, z) corner to its (x, z+1) corner):

  poke     ground higher than the asphalt or sidewalk over it (sampled every 10 cm on the game's ground triangles)
  crack    an edge of a paving triangle that has paving of the same kind beyond it at another height, or a
           hairline gap to the paving beyond it
  seam     the same along a 100 m cell edge, where the paving is cut into cells
  under    the edge of the paving standing so far over the ground beside it that one can see under it,
           with no kerb or shoulder piece along it
  missing  a cell whose triangles cover less than the paving that was meant there (or more: laid double)

Writes data/holes.json (each hole: kind, x, z, size) and data/holes.png (the map with the holes as red dots),
prints the totals, and exits with an error when there are any.   tools/holes.py --near x,z,r  lists those nearby.
"""
import json
import os
import sys

import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
WORLD = os.path.join(ROOT, "world")
LIFT = {"A": 0.10, "S": 0.23}                 # scripts/detail.gd, _paved_part
WATER = 0.45                                   # paving lower than this is out in the water and not drawn
STEP = 0.1
CELL = 100.0


def load_ground(meta):
    f = meta["fine"]
    w, h, strip = int(f["w"]), int(f["h"]), int(f["strip"])
    cols = []
    for k in range((w + strip - 1) // strip):
        a = np.fromfile(os.path.join(WORLD, "h1", "x%02d.bin" % k), "<u2")
        cols.append(a.reshape(h, -1))
    return (np.concatenate(cols, 1).astype(np.float32) * f["scale"] + f["offset"])


def load_paved():
    """cell -> {"A": triangles (n, 3, 3), "S": ..., "K": pieces (n, 10), "E": ...}"""
    data = np.fromfile(os.path.join(WORLD, "paved.bin"), np.float32)
    out, i = {}, 0
    while i + 6 <= len(data):
        key = (int(data[i]), int(data[i + 1]))
        n = [int(v) for v in data[i + 2:i + 6]]
        i += 6
        d = {}
        for name, cnt, width in zip("ASKE", n, (9, 9, 10, 10)):
            d[name] = data[i:i + cnt * width].reshape(cnt, width).astype(np.float64)
            i += cnt * width
        d["A"] = d["A"].reshape(-1, 3, 3)
        d["S"] = d["S"].reshape(-1, 3, 3)
        out[key] = d
    return out


def water_squares():
    """The 2 m squares that have a lake or running water in them (world/waterlevel.bin), as a set of (x, z) numbers."""
    path = os.path.join(WORLD, "waterlevel.bin")
    if not os.path.exists(path):
        return set()
    data = open(path, "rb").read()
    n = int(np.frombuffer(data, np.int32, 1, 0)[0])
    out = set()
    for i in range(n):
        at = 4 + i * 10004
        cx, cz = np.frombuffer(data, np.int16, 2, at)
        lv = np.frombuffer(data, np.int16, 2500, at + 4).reshape(50, 50)
        iz, ix = np.nonzero(lv > -32000)
        out.update(zip((int(cx) * 50 + ix).tolist(), (int(cz) * 50 + iz).tolist()))
    return out


class Ground:
    def __init__(self, meta, H1):
        self.x0, self.z0 = meta["x0"], meta["z0"]
        self.H = H1
        self.h, self.w = H1.shape
        self.C = np.ascontiguousarray(H1[::10, ::10])          # the far ground: every tenth point

    def near(self, x, z):
        """The ground as the 1 m terrain draws it."""
        fx = np.clip(x - self.x0, 0, self.w - 1.001)
        fz = np.clip(z - self.z0, 0, self.h - 1.001)
        ix, iz = fx.astype(np.int64), fz.astype(np.int64)
        tx, tz = fx - ix, fz - iz
        lo = tx + tz <= 1.0
        H = self.H
        h10, h01 = H[iz, ix + 1], H[iz + 1, ix]
        hc = np.where(lo, H[iz, ix], H[iz + 1, ix + 1])
        ax, az = np.where(lo, tx, 1 - tx), np.where(lo, tz, 1 - tz)
        return hc + ax * (np.where(lo, h10, h01) - hc) + az * (np.where(lo, h01, h10) - hc)

    def far(self, x, z):
        """The ground as the far terrain draws it: the 10 m points, evened between them."""
        C = self.C
        fx = np.clip((x - self.x0) / 10.0, 0, C.shape[1] - 1.001)
        fz = np.clip((z - self.z0) / 10.0, 0, C.shape[0] - 1.001)
        ix, iz = fx.astype(np.int64), fz.astype(np.int64)
        tx, tz = fx - ix, fz - iz
        return C[iz, ix] * (1 - tx) * (1 - tz) + C[iz, ix + 1] * tx * (1 - tz) + C[iz + 1, ix] * (1 - tx) * tz + C[iz + 1, ix + 1] * tx * tz


def samples(T, step=STEP):
    """Points every `step` inside triangles (n, 3, 3): returns x, z, the triangle's height there, and its number."""
    lo = np.floor(T[:, :, [0, 2]].min(1) / step)
    hi = np.ceil(T[:, :, [0, 2]].max(1) / step)
    n = int((hi - lo).max()) + 1
    k = np.arange(n)
    gx = (lo[:, 0, None, None] + k[None, None, :]) * step + np.zeros((1, n, 1))
    gz = (lo[:, 1, None, None] + k[None, :, None]) * step + np.zeros((1, 1, n))
    a, b, c = T[:, 0], T[:, 1], T[:, 2]
    det = (b[:, 2] - c[:, 2]) * (a[:, 0] - c[:, 0]) + (c[:, 0] - b[:, 0]) * (a[:, 2] - c[:, 2])
    ok = np.abs(det) > 1e-9
    det = np.where(ok, det, 1.0)[:, None, None]
    wa = ((b[:, 2] - c[:, 2])[:, None, None] * (gx - c[:, 0, None, None]) + (c[:, 0] - b[:, 0])[:, None, None] * (gz - c[:, 2, None, None])) / det
    wb = ((c[:, 2] - a[:, 2])[:, None, None] * (gx - c[:, 0, None, None]) + (a[:, 0] - c[:, 0])[:, None, None] * (gz - c[:, 2, None, None])) / det
    wc = 1.0 - wa - wb
    inside = (wa >= 0) & (wb >= 0) & (wc >= 0) & ok[:, None, None]
    y = wa * a[:, 1, None, None] + wb * b[:, 1, None, None] + wc * c[:, 1, None, None]
    t = np.broadcast_to(np.arange(len(T))[:, None, None], inside.shape)
    return gx[inside], gz[inside], y[inside], t[inside]


def clusters(x, z, size, reach=1.5):
    """Group points that lie together: returns [x, z, total size] for each group (a hole)."""
    if not len(x):
        return []
    key = np.round(np.stack([x, z], 1) / reach).astype(np.int64)
    uniq, inv = np.unique(key, axis=0, return_inverse=True)
    inv = inv.ravel()
    cells = {tuple(u): i for i, u in enumerate(uniq)}
    parent = list(range(len(uniq)))

    def find(i):
        while parent[i] != i:
            parent[i] = parent[parent[i]]
            i = parent[i]
        return i
    for (cx, cz), i in cells.items():
        for d in ((1, 0), (0, 1), (1, 1), (1, -1)):
            j = cells.get((cx + d[0], cz + d[1]))
            if j is not None:
                parent[find(i)] = find(j)
    root = np.asarray([find(i) for i in range(len(uniq))])[inv]
    out = []
    for r in np.unique(root):
        m = root == r
        w = size[m]
        out.append([float(np.average(x[m], weights=np.maximum(w, 1e-9))), float(np.average(z[m], weights=np.maximum(w, 1e-9))), float(w.sum())])
    return out


def main():
    meta = json.load(open(os.path.join(WORLD, "meta.json")))
    G = Ground(meta, load_ground(meta))
    paved = load_paved()
    try:
        meant = {tuple(int(v) for v in k.split(",")): a for k, a in json.load(open(os.path.join(WORLD, "paved_area.json"))).items()}
    except FileNotFoundError:
        meant = None
    found = []                                  # [kind, x, z, size]
    worst = {}

    def add(kind, rows):
        for x, z, s in rows:
            found.append([kind, round(x, 1), round(z, 1), round(s, 3)])

    # ---- the ground standing through, close up and far away
    n_tri = 0
    for key in sorted(paved):
        d = paved[key]
        for name in "AS":
            T = d[name]
            T = T[T[:, :, 1].min(1) >= WATER - LIFT[name]]     # (the game leaves out what is in the water)
            n_tri += len(T)
            px, pz, pe, pf = [], [], [], []
            for c0 in range(0, len(T), 4000):
                x, z, y, _t = samples(T[c0:c0 + 4000])
                top = y + LIFT[name]
                e = G.near(x, z) - top
                bad = e > 0.0
                if bad.any():
                    px.append(x[bad]); pz.append(z[bad]); pe.append(e[bad])
                    worst["poke"] = max(worst.get("poke", 0.0), float(e.max()))
                f = G.far(x, z) - top
                # paving is drawn only inside the 1 m ground, so the far ground is never under it; this measures
                # what would show if it were (kept as a figure, not counted as holes)
                pf.append(float((f > 0.0).sum()) * STEP * STEP)
            if px:
                x, z, e = np.concatenate(px), np.concatenate(pz), np.concatenate(pe)
                add("poke", [[cx, cz, n * STEP * STEP] for cx, cz, n in clusters(x, z, np.ones(len(x)))])
            worst["far_m2"] = worst.get("far_m2", 0.0) + sum(pf)

    # ---- cracks, seams and edges one can see under: every edge of every triangle, over the whole map
    V, Y, KIND = [], [], []
    for key in sorted(paved):
        for ki, name in enumerate("AS"):
            T = paved[key][name]
            if len(T):
                V.append(T[:, :, [0, 2]]); Y.append(T[:, :, 1]); KIND.append(np.full(len(T), ki))
    V, Y, KIND = np.concatenate(V), np.concatenate(Y), np.concatenate(KIND)
    area2 = (V[:, 1, 0] - V[:, 0, 0]) * (V[:, 2, 1] - V[:, 0, 1]) - (V[:, 1, 1] - V[:, 0, 1]) * (V[:, 2, 0] - V[:, 0, 0])
    keep = np.abs(area2) > 1e-6
    V, Y, KIND, area2 = V[keep], Y[keep], KIND[keep], area2[keep]
    Q = np.round(V * 1000).astype(np.int64)                    # corners to the millimetre
    ea = np.concatenate([Q[:, 0], Q[:, 1], Q[:, 2]])
    eb = np.concatenate([Q[:, 1], Q[:, 2], Q[:, 0]])
    ya = np.concatenate([Y[:, 0], Y[:, 1], Y[:, 2]])
    yb = np.concatenate([Y[:, 1], Y[:, 2], Y[:, 0]])
    tri = np.tile(np.arange(len(V)), 3)
    swap = (ea[:, 0] > eb[:, 0]) | ((ea[:, 0] == eb[:, 0]) & (ea[:, 1] > eb[:, 1]))
    lo = np.where(swap[:, None], eb, ea)
    hi = np.where(swap[:, None], ea, eb)
    ylo = np.where(swap, yb, ya) + np.where(KIND[tri] == 0, LIFT["A"], LIFT["S"])
    yhi = np.where(swap, ya, yb) + np.where(KIND[tri] == 0, LIFT["A"], LIFT["S"])
    code = np.concatenate([lo, hi], 1)
    order = np.lexsort(code.T[::-1])
    code, tri_s, ylo_s, yhi_s = code[order], tri[order], ylo[order], yhi[order]
    same = np.all(code[1:] == code[:-1], 1)
    first = np.concatenate([[True], ~same])
    group = np.cumsum(first) - 1
    count = np.bincount(group)
    # shared edges: two triangles of the same kind must meet at the same height
    pair = np.nonzero(same)[0]
    step_h = np.maximum(np.abs(ylo_s[pair] - ylo_s[pair + 1]), np.abs(yhi_s[pair] - yhi_s[pair + 1]))
    stepped = (KIND[tri_s[pair]] == KIND[tri_s[pair + 1]]) & (step_h > 0.01)
    lone = np.nonzero(count[group] == 1)[0]                    # edges with no partner: the outline, or a crack
    a = code[lone, :2] / 1000.0
    b = code[lone, 2:] / 1000.0
    t = tri_s[lone]
    mid = (a + b) * 0.5
    cen = V[t].mean(1)
    nrm = np.stack([-(b - a)[:, 1], (b - a)[:, 0]], 1)
    ln = np.maximum(np.hypot(nrm[:, 0], nrm[:, 1]), 1e-9)
    nrm /= ln[:, None]
    nrm *= np.where(((mid - cen) * nrm).sum(1) < 0, -1.0, 1.0)[:, None]      # pointing out of its triangle
    ymid = (ylo_s[lone] + yhi_s[lone]) * 0.5

    # what lies beyond each lone edge: look the points up among all triangles, by 1 m squares
    def paving_at(px, pz):
        """For points: the kind (0 asphalt, 1 sidewalk, -1 none) and the drawn height of the paving there."""
        kind = np.full(len(px), -1)
        high = np.full(len(px), np.nan)
        bx0 = np.floor(V[:, :, 0].min(1)).astype(np.int64); bx1 = np.floor(V[:, :, 0].max(1)).astype(np.int64)
        bz0 = np.floor(V[:, :, 1].min(1)).astype(np.int64); bz1 = np.floor(V[:, :, 1].max(1)).astype(np.int64)
        qx, qz = np.floor(px).astype(np.int64), np.floor(pz).astype(np.int64)
        qkey = qx * 100003 + qz
        qo = np.argsort(qkey, kind="stable")
        qk = qkey[qo]
        for dx in range(0, int((bx1 - bx0).max()) + 1):
            for dz in range(0, int((bz1 - bz0).max()) + 1):
                use = np.nonzero((bx0 + dx <= bx1) & (bz0 + dz <= bz1))[0]
                if not len(use):
                    continue
                tk = (bx0[use] + dx) * 100003 + (bz0[use] + dz)
                l = np.searchsorted(qk, tk, "left"); r = np.searchsorted(qk, tk, "right")
                n = r - l
                has = n > 0
                if not has.any():
                    continue
                ti = np.repeat(use[has], n[has])
                off = np.arange(n[has].sum()) - np.repeat(np.cumsum(n[has]) - n[has], n[has])
                pi = qo[np.repeat(l[has], n[has]) + off]
                A, B, C = V[ti, 0], V[ti, 1], V[ti, 2]
                det = (B[:, 1] - C[:, 1]) * (A[:, 0] - C[:, 0]) + (C[:, 0] - B[:, 0]) * (A[:, 1] - C[:, 1])
                wa = ((B[:, 1] - C[:, 1]) * (px[pi] - C[:, 0]) + (C[:, 0] - B[:, 0]) * (pz[pi] - C[:, 1])) / det
                wb = ((C[:, 1] - A[:, 1]) * (px[pi] - C[:, 0]) + (A[:, 0] - C[:, 0]) * (pz[pi] - C[:, 1])) / det
                wc = 1 - wa - wb
                ins = (wa >= -1e-9) & (wb >= -1e-9) & (wc >= -1e-9)
                yy = wa * Y[ti, 0] + wb * Y[ti, 1] + wc * Y[ti, 2] + np.where(KIND[ti] == 0, LIFT["A"], LIFT["S"])
                kind[pi[ins]] = KIND[ti[ins]]
                high[pi[ins]] = yy[ins]
        return kind, high

    k1, h1 = paving_at(mid[:, 0] + nrm[:, 0] * 0.015, mid[:, 1] + nrm[:, 1] * 0.015)
    k2, _h2 = paving_at(mid[:, 0] + nrm[:, 0] * 0.06, mid[:, 1] + nrm[:, 1] * 0.06)
    mine = KIND[t]
    dry = ymid > 0.6 + 0.1                                       # (not out in the water)
    on_seam = (np.abs(mid[:, 0] / CELL - np.round(mid[:, 0] / CELL)) < 1e-6) | (np.abs(mid[:, 1] / CELL - np.round(mid[:, 1] / CELL)) < 1e-6)
    step_here = dry & (k1 == mine) & (np.abs(h1 - ymid) > 0.015)        # the same kind beyond, at another height
    gap_here = dry & (k1 < 0) & (k2 == mine)                         # nothing right beyond, the same paving a hair further
    # (a hairline between asphalt and a sidewalk does not show: the kerb hangs over it)
    crack = step_here | gap_here
    for name, m in (("seam", crack & on_seam), ("crack", crack & ~on_seam)):
        add(name, [c for c in clusters(mid[m, 0], mid[m, 1], ln[m]) if c[2] >= 0.15])      # (under 15 cm long: a notch at a corner, not a slit)
    # shared edges that step
    if stepped.any():
        e = pair[stepped]
        mx = (code[e, 0] + code[e, 2]) / 2000.0; mz = (code[e, 1] + code[e, 3]) / 2000.0
        sm = (np.abs(mx / CELL - np.round(mx / CELL)) < 1e-6) | (np.abs(mz / CELL - np.round(mz / CELL)) < 1e-6)
        for name, m in (("seam", sm), ("crack", ~sm)):
            add(name, clusters(mx[m], mz[m], np.hypot(code[e, 2] - code[e, 0], code[e, 3] - code[e, 1])[m] / 1000.0))

    # the true outline: how far the paving stands over the ground just beside it, where no kerb or shoulder covers it
    edge = dry & (k1 < 0) & (k2 < 0)
    ox, oz = mid[:, 0] + nrm[:, 0] * 0.05, mid[:, 1] + nrm[:, 1] * 0.05
    drop = ymid - G.near(ox, oz)
    P = []
    for key in paved:
        for name in "KE":
            q = paved[key][name]
            if len(q):
                P.append((q[:, [0, 2]] + q[:, [5, 7]]) * 0.5)
                P.append(q[:, [0, 2]])
                P.append(q[:, [5, 7]])
    covered = np.zeros(len(mid), bool)
    if P:
        P = np.concatenate(P)
        pk = set(zip(np.floor(P[:, 0] / 2.0).astype(np.int64).tolist(), np.floor(P[:, 1] / 2.0).astype(np.int64).tolist()))
        cand = np.nonzero(edge & (drop > 0.25))[0]
        mx, mz = np.floor(mid[cand, 0] / 2.0).astype(np.int64), np.floor(mid[cand, 1] / 2.0).astype(np.int64)
        for i, x, z in zip(cand, mx.tolist(), mz.tolist()):
            covered[i] = any((x + dx, z + dz) in pk for dx in (-1, 0, 1) for dz in (-1, 0, 1))
    # (a kerb or a shoulder piece is drawn down into the ground beside it, however far below: scripts/detail.gd)
    under = edge & (drop > 0.25) & ~covered & (G.near(ox, oz) > 0.5)
    # (where a road ends at a bridge, the deck goes on over the water and its bank: not an open edge)
    wet = water_squares()
    if wet and under.any():
        for i in np.nonzero(under)[0]:
            for reach in (1.0, 3.0, 5.0, 7.0):
                if (int(np.floor((mid[i, 0] + nrm[i, 0] * reach) / 2.0)), int(np.floor((mid[i, 1] + nrm[i, 1] * reach) / 2.0))) in wet:
                    under[i] = False
    add("under", clusters(mid[under, 0], mid[under, 1], ln[under], reach=3.0))
    if "--why" in sys.argv:
        gout = G.near(ox, oz)
        for i in np.nonzero(under)[0][np.argsort(-ln[under])[:400:8]]:
            print("  under at (%.1f, %.1f): edge %.2f m long stands %.2f over ground at %.2f, covered %s, kind %d" % (mid[i, 0], mid[i, 1], ln[i], drop[i], gout[i], covered[i], mine[i]))

    if under.any():
        worst["under"] = float(drop[under].max())

    # ---- paving that is missing, cell by cell
    if meant is not None:
        tri_area = {}
        for key, d in paved.items():
            out = []
            for name in "AS":
                T = d[name]
                out.append(float(np.abs((T[:, 1, 0] - T[:, 0, 0]) * (T[:, 2, 2] - T[:, 0, 2]) - (T[:, 1, 2] - T[:, 0, 2]) * (T[:, 2, 0] - T[:, 0, 0])).sum() * 0.5))
            tri_area[key] = out
        for key in sorted(set(meant) | set(tri_area)):
            want = meant.get(key, [0.0, 0.0])
            have = tri_area.get(key, [0.0, 0.0])
            for w, h in zip(want, have):
                if abs(w - h) > max(0.5, 0.002 * w):
                    add("missing", [[(key[0] + 0.5) * CELL, (key[1] + 0.5) * CELL, w - h]])

    if "--near" in sys.argv:
        x, z, r = [float(v) for v in sys.argv[sys.argv.index("--near") + 1].split(",")]
        for f in found:
            if np.hypot(f[1] - x, f[2] - z) <= r:
                print(f)
    found.sort(key=lambda f: (f[0], -abs(f[3])))
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    json.dump(found, open(os.path.join(ROOT, "data", "holes.json"), "w"))
    picture(meta, paved, found)
    tot = {}
    for k, _x, _z, s in found:
        t = tot.setdefault(k, [0, 0.0])
        t[0] += 1
        t[1] += abs(s)
    unit = {"poke": "m2", "crack": "m", "seam": "m", "under": "m", "missing": "m2"}
    print("holes: checked %d triangles of paving in %d cells" % (n_tri, len(paved)))
    for k in ("poke", "crack", "seam", "under", "missing"):
        n, s = tot.get(k, [0, 0.0])
        print("  %-8s %5d   %8.1f %s" % (k, n, s, unit[k]))
    print("  (if paving were drawn beyond the 1 m ground, the far ground would stand through %.0f m2 of it)" % worst.get("far_m2", 0.0))
    if "poke" in worst:
        print("  highest ground over paving: %.2f m" % worst["poke"])
    if meant is None:
        print("  (world/paved_area.json is not there: missing paving was not checked; rebuild the map)")
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            f.write("### Holes in the paving\n\n| kind | places | size |\n|---|---|---|\n")
            for k in ("poke", "crack", "seam", "under", "missing"):
                n, s = tot.get(k, [0, 0.0])
                f.write("| %s | %d | %.1f %s |\n" % (k, n, s, unit[k]))
    sys.exit(1 if found else 0)


def picture(meta, paved, found):
    """data/holes.png: the paving in grey, 4 m a pixel, and each hole as a red dot."""
    from PIL import Image, ImageDraw
    x0, z0, x1, z1 = meta["x0"], meta["z0"], meta["x1"], meta["z1"]
    s = 4.0
    w, h = int((x1 - x0) / s), int((z1 - z0) / s)
    im = np.full((h, w, 3), 24, np.uint8)
    for d in paved.values():
        for name, col in (("A", (110, 110, 114)), ("S", (170, 168, 164))):
            T = d[name]
            if len(T):
                c = T.mean(1)
                ix = np.clip(((c[:, 0] - x0) / s).astype(int), 0, w - 1)
                iz = np.clip(((c[:, 2] - z0) / s).astype(int), 0, h - 1)
                im[iz, ix] = col
    img = Image.fromarray(im)
    dr = ImageDraw.Draw(img)
    for _k, x, z, _s in found:
        u, v = (x - x0) / s, (z - z0) / s
        dr.ellipse((u - 4, v - 4, u + 4, v + 4), outline=(255, 40, 40), width=2)
    img.save(os.path.join(ROOT, "data", "holes.png"))


if __name__ == "__main__":
    main()
