#!/usr/bin/env python3
"""Roof colours of the large buildings, from the satellite (PLAN.md, the map plan of 19 Nov, E).

Street photos give wall colours along the county roads only, and aerial photos of Norway are not open data. The
Sentinel-2 pictures tools/ortho_paved.py already uses (10 m, "Contains modified Copernicus Sentinel data") do
show the roof of anything large: a building of 300 m2 or more covers several of their pixels. For each such
building the pixels well inside its outline are read in three summer scenes, the middle value taken, and turned
into a colour: what the roof reflects in red, green and blue, toned down a little toward grey (the satellite sees
through haze). Roofs under trees or with grass on them (green in the near infrared) are left alone.

Writes data/colours_roofs.json: {OSM id: [r, g, b]}; tools/build_map.py uses it for a roof that has no colour
from a tag, a photo or by hand. Needs world/buildings.json from a build.
"""
import json, os, sys
import numpy as np
import shapely
from shapely.geometry import Polygon

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import X0, X1, Z0, Z1, to_latlon
import s2cog

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def main():
    S = s2cog.fetch(X0, X1, Z0, Z1, to_latlon)
    out, seen = {}, 0
    for b in json.load(open(os.path.join(ROOT, "world", "buildings.json"))):
        osm_id, q = b[-1], np.asarray(b[5], float).reshape(-1, 2)
        if len(q) < 3:
            continue
        poly = Polygon(q).buffer(0)
        if poly.area < 300.0:
            continue
        core = poly.buffer(-6.0)
        if core.is_empty or core.area < 40.0:
            core = poly.buffer(-3.5)
        if core.is_empty:
            continue
        x0, z0, x1, z1 = core.bounds
        gx, gz = np.meshgrid(np.arange(x0, x1 + 0.1, 4.0), np.arange(z0, z1 + 0.1, 4.0))
        gx, gz = gx.ravel(), gz.ravel()
        ok = shapely.contains_xy(core, gx, gz)
        if ok.sum() < 3:
            c = core.representative_point()
            gx, gz, ok = np.array([c.x]), np.array([c.y]), np.array([True])
        lat, lon = to_latlon(gx[ok], gz[ok])
        seen += 1
        rgbn = []
        for s in S.values():
            rgbn.append([float(np.median(s2cog.sample(s, k, lat, lon))) for k in ("B04", "B03", "B02", "B08")])
        r, g, bl, n = np.median(np.asarray(rgbn), 0)
        if (n - r) / (n + r + 1.0) > 0.30:
            continue                                   # green: trees over it, or turf
        refl = np.clip(np.array([r, g, bl]) / 10000.0, 0.005, 0.6)
        col = 255.0 * refl ** (1 / 2.2)
        col = col * 0.75 + col.mean() * 0.25           # toward grey a little
        col = np.clip(col * 0.92, 38, 205)
        out[str(osm_id)] = [int(round(v)) for v in col]
    json.dump(out, open(os.path.join(ROOT, "data", "colours_roofs.json"), "w"), separators=(",", ":"))
    cols = np.asarray(list(out.values()), float)
    red = int(((cols[:, 0] > cols[:, 1] * 1.18) & (cols[:, 0] > cols[:, 2] * 1.25)).sum())
    print("large buildings looked at: %d, roofs given a colour: %d (reddish: %d, darker than 80: %d, lighter than 150: %d)" % (
        seen, len(out), red, int((cols.mean(1) < 80).sum()), int((cols.mean(1) > 150).sum())))


if __name__ == "__main__":
    main()
