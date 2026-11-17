#!/usr/bin/env python3
"""How well does every house in the game agree with Kartverket's laser scan?

Reads world/buildings.json (what the game builds) and measures each building against the 1 m surface model
(DOM) and terrain model (DTM):

  seen     share of the outline where the laser has something standing (over 2 m above the ground)
  shift    how far the outline would have to be moved to cover what the laser sees best (metres), and the gain
  err      typical difference between the roof in the game and the roof the laser measured (median, metres)
  bad      share of the roof that is more than a metre off
  relief   how much the measured roof varies in height (a flat roof on a building with a large relief is wrong)
  drop     ground height difference along the walls (how much foundation shows)

Writes data/house_audit.json (one row per building, worst first) and prints the totals.
"""
import json
import os
import sys

import numpy as np
import shapely
from shapely.geometry import Polygon

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from kartverket import Sampler

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DOM, DTM = Sampler("dom"), Sampler("dtm")


def roof_at(faces, x, z):
    """Height of the game's roof at points: the highest face over each (NaN where none)."""
    best = np.full(len(x), np.nan)
    for f in faces:
        v = np.asarray(f[1:], float).reshape(-1, 3)
        if len(v) < 3:
            continue
        poly = Polygon(v[:, [0, 2]])
        if not poly.is_valid or poly.area < 0.05:
            continue
        A = np.stack([np.ones(len(v)), v[:, 0] - v[0, 0], v[:, 2] - v[0, 2]], 1)
        coef, *_ = np.linalg.lstsq(A, v[:, 1], rcond=None)
        inside = shapely.contains_xy(poly.buffer(0.05), x, z)
        y = coef[0] + coef[1] * (x - v[0, 0]) + coef[2] * (z - v[0, 2])
        take = inside & (np.isnan(best) | (y > best))
        best[take] = y[take]
    return best


def audit(b):
    small, h, ymin, ymax, style, flat, roof, _wall, _roofc, name, osm_id = b[:11]
    P = np.asarray(flat, float).reshape(-1, 2)
    foot = Polygon(P)
    if not foot.is_valid or foot.area < 6:
        return None
    x0, z0, x1, z1 = foot.bounds
    gx, gz = np.meshgrid(np.arange(x0 - 4, x1 + 4.01, 1.0), np.arange(z0 - 4, z1 + 4.01, 1.0))
    gx, gz = gx.ravel(), gz.ravel()
    dom, dtm = DOM.bilinear(gx, gz), DTM.bilinear(gx, gz)
    if np.isnan(dom).mean() > 0.5:
        return None
    tall = (dom - dtm) > 2.0
    inside = shapely.contains_xy(foot, gx, gz)
    if inside.sum() < 4:
        return None
    seen = float(tall[inside].mean())
    # the best place for the outline: slide it over what the laser sees
    best, at = seen, (0.0, 0.0)
    for dx in (-3, -2, -1, 0, 1, 2, 3):
        for dz in (-3, -2, -1, 0, 1, 2, 3):
            if dx == 0 and dz == 0:
                continue
            m = shapely.contains_xy(foot, gx - dx, gz - dz)
            s = float(tall[m].mean()) if m.any() else 0.0
            if s > best + 0.02 + 0.01 * (abs(dx) + abs(dz)):
                best, at = s, (float(dx), float(dz))
    deep = shapely.contains_xy(foot.buffer(-0.8), gx, gz) & tall
    err, bad, relief = None, None, None
    if deep.sum() >= 6:
        got = roof_at(roof["f"], gx[deep], gz[deep])
        d = got - dom[deep]
        ok = ~np.isnan(d)
        if ok.sum() >= 6:
            err = float(np.median(np.abs(d[ok])))
            bad = float(np.mean(np.abs(d[ok]) > 1.0))
        dd = dom[deep]
        relief = float(np.percentile(dd, 92) - np.percentile(dd, 8))
    all_flat = all(int(f[0]) == 1 for f in roof["f"]) if roof["f"] else True
    return {"id": osm_id, "x": round(float(P[:, 0].mean()), 1), "z": round(float(P[:, 1].mean()), 1), "area": round(foot.area),
            "small": small, "style": style, "seen": round(seen, 2), "shift": list(at), "gain": round(best - seen, 2),
            "err": None if err is None else round(err, 2), "bad": None if bad is None else round(bad, 2),
            "relief": None if relief is None else round(relief, 2), "flat": all_flat, "faces": len(roof["f"]),
            "h": h, "drop": round(ymax - ymin, 2)}


def main():
    B = json.load(open(os.path.join(ROOT, "world", "buildings.json")))
    rows = [r for r in (audit(b) for b in B) if r]
    def score(r):
        return (r["bad"] or 0) + (1 - r["seen"]) + r["gain"]
    rows.sort(key=score, reverse=True)
    json.dump(rows, open(os.path.join(ROOT, "data", "house_audit.json"), "w"))
    n = len(rows)
    has = [r for r in rows if r["err"] is not None]
    print("houses audited:", n, "of", len(B))
    print("  the laser sees less than half of the outline standing:", sum(r["seen"] < 0.5 for r in rows))
    print("  outline fits better moved by a metre or more (gain over 10 %):", sum(r["gain"] > 0.10 for r in rows))
    print("  roof within 0.3 m (median):", sum(r["err"] <= 0.3 for r in has), " 0.3-0.6:", sum(0.3 < r["err"] <= 0.6 for r in has),
          " 0.6-1.0:", sum(0.6 < r["err"] <= 1.0 for r in has), " over 1 m:", sum(r["err"] > 1.0 for r in has))
    print("  more than a fifth of the roof over a metre off:", sum(r["bad"] > 0.2 for r in has))
    print("  flat roof in the game where the laser measured a relief over 1.5 m:", sum(r["flat"] and (r["relief"] or 0) > 1.5 for r in has))
    print("  ground falls more than 1.5 m along the walls:", sum(r["drop"] > 1.5 for r in rows), " more than 3 m:", sum(r["drop"] > 3 for r in rows))


if __name__ == "__main__":
    main()
