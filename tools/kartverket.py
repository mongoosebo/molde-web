#!/usr/bin/env python3
"""Kartverket laser elevation data (hoydedata.no): surface model (DOM, with buildings and trees)
and terrain model (DTM), 1 m, EPSG:25833. Tiles are cached in data/kartverket/.

Run directly to download every 1 km tile that contains a building:  python3 tools/kartverket.py
"""
import json, math, os, subprocess, sys, time
import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "data", "kartverket")
LAT0, LON0 = 62.7375, 7.1591
MX = 111320.0 * math.cos(math.radians(LAT0))
MZ = 111430.0
TILE = 1000          # metres and pixels per tile
URL = ("https://wcs.geonorge.no/skwms1/wcs.hoyde-{kind}-nhm-25833?service=WCS&version=1.0.0&request=GetCoverage"
       "&coverage=nhm_{kind}_topo_25833&CRS=EPSG:25833&BBOX={x0},{y0},{x1},{y1}&WIDTH={n}&HEIGHT={n}&FORMAT=GeoTIFF")


def utm33(lat, lon):
    """WGS84/ETRS89 degrees -> UTM zone 33N (numpy arrays or floats)."""
    a = 6378137.0
    f = 1 / 298.257222101
    k0 = 0.9996
    e2 = f * (2 - f)
    ep2 = e2 / (1 - e2)
    phi = np.radians(lat)
    lam = np.radians(lon) - math.radians(15.0)
    s, c, t = np.sin(phi), np.cos(phi), np.tan(phi)
    N = a / np.sqrt(1 - e2 * s * s)
    T = t * t
    C = ep2 * c * c
    A = lam * c
    M = a * ((1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256) * phi
             - (3 * e2 / 8 + 3 * e2 ** 2 / 32 + 45 * e2 ** 3 / 1024) * np.sin(2 * phi)
             + (15 * e2 ** 2 / 256 + 45 * e2 ** 3 / 1024) * np.sin(4 * phi)
             - (35 * e2 ** 3 / 3072) * np.sin(6 * phi))
    x = k0 * N * (A + (1 - T + C) * A ** 3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * A ** 5 / 120) + 500000
    y = k0 * (M + N * t * (A * A / 2 + (5 - T + 9 * C + 4 * C * C) * A ** 4 / 24
                           + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * A ** 6 / 720))
    return x, y


def world_to_utm(x, z):
    """Game coordinates (x east, z south, metres) -> UTM33."""
    return utm33(LAT0 - np.asarray(z) / MZ, LON0 + np.asarray(x) / MX)


def tile_path(kind, tx, ty):
    return os.path.join(CACHE, f"{kind}_{tx}_{ty}.tif")


def fetch(kind, tx, ty):
    path = tile_path(kind, tx, ty)
    if os.path.exists(path) and os.path.getsize(path) > 100000:
        return True
    os.makedirs(CACHE, exist_ok=True)
    url = URL.format(kind=kind, x0=tx * TILE, y0=ty * TILE, x1=(tx + 1) * TILE, y1=(ty + 1) * TILE, n=TILE)
    for attempt in range(3):
        subprocess.run(["curl", "-s", "-m", "120", "-A", "map-builder/1.0", "-o", path + ".part", url])
        try:
            with open(path + ".part", "rb") as f:
                ok = f.read(2) in (b"II", b"MM")
        except OSError:
            ok = False
        if ok:
            os.replace(path + ".part", path)
            return True
        time.sleep(3)
    return False


class Sampler:
    """Bilinear lookups into the cached tiles. Missing tiles give NaN."""

    def __init__(self, kind):
        self.kind = kind
        self.tiles = {}

    def _tile(self, tx, ty):
        key = (tx, ty)
        if key not in self.tiles:
            path = tile_path(self.kind, tx, ty)
            if os.path.exists(path):
                arr = np.asarray(Image.open(path)).astype(np.float32)
                arr[arr < -100] = np.nan
                self.tiles[key] = arr
            else:
                self.tiles[key] = None
        return self.tiles[key]

    def at(self, x, z):
        """Heights at game coordinates (arrays). Nearest-pixel is enough at 1 m."""
        e, n = world_to_utm(x, z)
        e = np.atleast_1d(e)
        n = np.atleast_1d(n)
        out = np.full(e.shape, np.nan, np.float32)
        tx = np.floor(e / TILE).astype(int)
        ty = np.floor(n / TILE).astype(int)
        for key in set(zip(tx.tolist(), ty.tolist())):
            arr = self._tile(*key)
            if arr is None:
                continue
            m = (tx == key[0]) & (ty == key[1])
            col = np.clip((e[m] - key[0] * TILE).astype(int), 0, TILE - 1)
            row = np.clip(((key[1] + 1) * TILE - n[m]).astype(int), 0, TILE - 1)
            out[m] = arr[row, col]
        return out

    def bilinear(self, x, z):
        """Heights at game coordinates, interpolated between the four pixels around each point
        (pixel centres are at half metres). Falls back to the nearest pixel next to gaps."""
        e, n = world_to_utm(x, z)
        e = np.atleast_1d(e) - 0.5
        n = np.atleast_1d(n) - 0.5
        e0, n0 = np.floor(e), np.floor(n)
        fe, fn = (e - e0).astype(np.float32), (n - n0).astype(np.float32)
        acc = np.zeros(e.shape, np.float32)
        wsum = np.zeros(e.shape, np.float32)
        for de, dn, w in ((0, 0, (1 - fe) * (1 - fn)), (1, 0, fe * (1 - fn)), (0, 1, (1 - fe) * fn), (1, 1, fe * fn)):
            v = self._pix(e0 + de, n0 + dn)
            ok = ~np.isnan(v)
            acc[ok] += v[ok] * w[ok]
            wsum[ok] += w[ok]
        return np.where(wsum > 0.25, acc / np.maximum(wsum, 1e-6), np.nan).astype(np.float32)

    def _pix(self, e, n):
        out = np.full(e.shape, np.nan, np.float32)
        tx = np.floor(e / TILE).astype(int)
        ty = np.floor(n / TILE).astype(int)
        code = tx * 100000 + ty
        for c in np.unique(code):
            key = (int(c // 100000), int(c % 100000))
            arr = self._tile(*key)
            if arr is None:
                continue
            m = code == c
            col = np.clip((e[m] - key[0] * TILE).astype(int), 0, TILE - 1)
            row = np.clip(((key[1] + 1) * TILE - 1 - n[m]).astype(int), 0, TILE - 1)
            out[m] = arr[row, col]
        return out


if __name__ == "__main__":
    els = json.load(open(os.path.join(ROOT, "data", "osm_raw.json")))["elements"]
    need = set()
    for e in els:
        if e["type"] == "way" and "building" in e.get("tags", {}):
            g = e["geometry"]
            ex, ny = utm33(np.array([p["lat"] for p in g]), np.array([p["lon"] for p in g]))
            for a, b in zip(ex, ny):
                need.add((int(a // TILE), int(b // TILE)))
    need = sorted(need)
    print(len(need), "tiles needed")
    if "--count" in sys.argv:
        sys.exit()
    failed = 0
    for i, (tx, ty) in enumerate(need):
        for kind in ("dom", "dtm"):
            if not fetch(kind, tx, ty):
                failed += 1
                print("failed", kind, tx, ty)
        if i % 10 == 0:
            print(f"{i + 1}/{len(need)}", flush=True)
    print("done, failed:", failed)


# ---------------------------------------------------------------- terrain for the whole game area
COARSE = 5           # metres per pixel of the terrain model used for the ground
BLOCK = 5000         # metres per downloaded block


class Terrain:
    """Kartverket's terrain model (DTM) over the whole game area at 5 m, for the ground itself.
    Blocks are cached in data/kartverket/terrain5_*.tif. Sea and gaps give NaN."""

    def __init__(self, x0, x1, z0, z1):
        cx = np.array([x0, x1, x0, x1, (x0 + x1) / 2, (x0 + x1) / 2])
        cz = np.array([z0, z0, z1, z1, z0, z1])
        e, n = world_to_utm(cx, cz)
        self.blocks = {}
        os.makedirs(CACHE, exist_ok=True)
        for bx in range(int((e.min() - 300) // BLOCK), int((e.max() + 300) // BLOCK) + 1):
            for by in range(int((n.min() - 300) // BLOCK), int((n.max() + 300) // BLOCK) + 1):
                path = os.path.join(CACHE, f"terrain5_{bx}_{by}.tif")
                if not os.path.exists(path):
                    url = URL.format(kind="dtm", x0=bx * BLOCK, y0=by * BLOCK, x1=(bx + 1) * BLOCK,
                                     y1=(by + 1) * BLOCK, n=BLOCK // COARSE)
                    for attempt in range(3):
                        subprocess.run(["curl", "-s", "-m", "300", "-A", "map-builder/1.0", "-o", path + ".part", url])
                        try:
                            with open(path + ".part", "rb") as f:
                                ok = f.read(2) in (b"II", b"MM")
                        except OSError:
                            ok = False
                        if ok:
                            os.replace(path + ".part", path)
                            break
                        time.sleep(3)
                if os.path.exists(path) and os.path.getsize(path) > 10000:      # empty blocks are tiny
                    arr = np.asarray(Image.open(path)).astype(np.float32)
                    arr[(arr < -100) | (arr > 3000)] = np.nan
                    self.blocks[(bx, by)] = arr

    def at(self, x, z):
        e, n = world_to_utm(x, z)
        e = np.atleast_1d(e)
        n = np.atleast_1d(n)
        out = np.full(e.shape, np.nan, np.float32)
        bx = np.floor(e / BLOCK).astype(int)
        by = np.floor(n / BLOCK).astype(int)
        size = BLOCK // COARSE
        for key in set(zip(bx.ravel().tolist(), by.ravel().tolist())):
            arr = self.blocks.get(key)
            if arr is None:
                continue
            m = (bx == key[0]) & (by == key[1])
            col = np.clip(((e[m] - key[0] * BLOCK) / COARSE).astype(int), 0, size - 1)
            row = np.clip((((key[1] + 1) * BLOCK - n[m]) / COARSE).astype(int), 0, size - 1)
            out[m] = arr[row, col]
        return out


# ---------------------------------------------------------------- 1 m terrain for the whole game area
def area_tiles(x0, x1, z0, z1):
    """Every 1 km tile that touches the game area."""
    xs = np.linspace(x0, x1, 40)
    zs = np.linspace(z0, z1, 40)
    gx, gz = np.meshgrid(xs, zs)
    e, n = world_to_utm(gx, gz)
    return sorted({(tx, ty) for tx in range(int(e.min() // TILE), int(e.max() // TILE) + 1)
                   for ty in range(int(n.min() // TILE), int(n.max() // TILE) + 1)})


def fetch_area(kind, x0, x1, z0, z1, workers=4):
    """Download the tiles for the whole area. Tiles out at sea come back empty; they are remembered
    with a marker file so they are not asked for again."""
    from concurrent.futures import ThreadPoolExecutor

    def one(key):
        path = tile_path(kind, *key)
        if os.path.exists(path + ".empty") or (os.path.exists(path) and os.path.getsize(path) > 100000):
            return True
        ok = fetch(kind, *key)
        if ok and os.path.getsize(path) <= 100000:
            os.replace(path, path + ".empty")
        return ok

    tiles = area_tiles(x0, x1, z0, z1)
    with ThreadPoolExecutor(workers) as pool:
        res = list(pool.map(one, tiles))
    return len(tiles), res.count(False)


def grid(kind, x0, z0, w, h, step=1.0, rows=500):
    """A whole grid of heights (h rows of w, bilinear from the 1 m tiles), NaN where there is no data."""
    s = Sampler(kind)
    out = np.empty((h, w), np.float32)
    xs = x0 + np.arange(w) * step
    for r0 in range(0, h, rows):
        zs = z0 + np.arange(r0, min(r0 + rows, h)) * step
        gx, gz = np.meshgrid(xs, zs)
        out[r0:r0 + len(zs)] = s.bilinear(gx.ravel(), gz.ravel()).reshape(gx.shape)
    return out


# ---------------------------------------------------------------- the wider landscape, for the far view
def backdrop(half, step, n_out):
    """Terrain for a square of 2·half metres around the game's origin, n_out heights a side (row 0 in
    the north), from one coarse download. Sea and gaps are 0."""
    e0, n0 = utm33(LAT0, LON0)
    reach = half * 1.2 + 4000                         # the game's frame is turned a little against the UTM grid
    x0, y0 = int((e0 - reach) // step) * step, int((n0 - reach) // step) * step
    n = int(2 * reach // step)
    path = os.path.join(CACHE, f"backdrop_{step}_{n}.tif")
    if not os.path.exists(path):
        os.makedirs(CACHE, exist_ok=True)
        url = URL.format(kind="dtm", x0=x0, y0=y0, x1=x0 + n * step, y1=y0 + n * step, n=n)
        subprocess.run(["curl", "-s", "-m", "600", "-A", "map-builder/1.0", "-o", path, url])
    arr = np.asarray(Image.open(path)).astype(np.float32)
    arr[(arr < -100) | (arr > 3000)] = 0.0
    gx, gz = np.meshgrid(np.linspace(-half, half, n_out), np.linspace(-half, half, n_out))
    e, nn = world_to_utm(gx, gz)
    col = np.clip(((e - x0) / step).astype(int), 0, n - 1)
    row = np.clip(((y0 + n * step - nn) / step).astype(int), 0, n - 1)
    return np.nan_to_num(arr[row, col]).astype(np.float32)
