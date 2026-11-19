#!/usr/bin/env python3
"""Windows out of Sentinel-2 scenes (10 m, bands B02 B03 B04 B08), for tools/ortho_paved.py.

The scenes are the open "Sentinel-2 L2A COGs" on AWS (registry.opendata.aws/sentinel-2-l2a-cogs): no key, no
login. Copernicus Sentinel data is free to use, copy and adapt (the Sentinel Data Legal Notice); it asks for the
credit "Contains modified Copernicus Sentinel data [year]".

A scene band is one 110 km GeoTIFF of some 100 to 250 MB. Only the tiles over the game area are read, by HTTP
range requests, and kept in data/ortho/ as .npy with the frame beside them."""
import json, math, os, struct, subprocess, zlib
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, "data", "ortho")
BASE = "https://sentinel-cogs.s3.us-west-2.amazonaws.com/sentinel-s2-l2a-cogs/32/V/MQ/"
# Summer scenes of tile 32VMQ with next to no cloud (found with earth-search.aws.element84.com, 19 Nov 2026).
SCENES = {
    "2025-07-16": "2025/7/S2C_32VMQ_20250716_0_L2A",
    "2022-08-31": "2022/8/S2A_32VMQ_20220831_0_L2A",
    "2021-07-12": "2021/7/S2B_32VMQ_20210712_0_L2A",
}
BANDS = ("B02", "B03", "B04", "B08")
AGENT = "Mozilla/5.0"


def utm(lat, lon, lon0):
    """ETRS89/WGS84 degrees -> UTM east, north with the central meridian lon0 (numpy arrays or floats)."""
    a, f, k0 = 6378137.0, 1 / 298.257222101, 0.9996
    e2 = f * (2 - f)
    ep2 = e2 / (1 - e2)
    phi = np.radians(lat)
    lam = np.radians(lon) - math.radians(lon0)
    s, c, t = np.sin(phi), np.cos(phi), np.tan(phi)
    N = a / np.sqrt(1 - e2 * s * s)
    T, C, A = t * t, ep2 * c * c, lam * c
    M = a * ((1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256) * phi
             - (3 * e2 / 8 + 3 * e2 ** 2 / 32 + 45 * e2 ** 3 / 1024) * np.sin(2 * phi)
             + (15 * e2 ** 2 / 256 + 45 * e2 ** 3 / 1024) * np.sin(4 * phi) - (35 * e2 ** 3 / 3072) * np.sin(6 * phi))
    x = k0 * N * (A + (1 - T + C) * A ** 3 / 6 + (5 - 18 * T + T * T + 72 * C - 58 * ep2) * A ** 5 / 120) + 500000
    y = k0 * (M + N * t * (A * A / 2 + (5 - T + 9 * C + 4 * C * C) * A ** 4 / 24 + (61 - 58 * T + T * T + 600 * C - 330 * ep2) * A ** 6 / 720))
    return x, y


def _get(url, start, length):
    r = subprocess.run(["curl", "-s", "-f", "-m", "120", "-A", AGENT, "-r", "%d-%d" % (start, start + length - 1), url], capture_output=True)
    if r.returncode != 0 or len(r.stdout) != length:
        raise IOError("range request failed: %s %d+%d" % (url, start, length))
    return r.stdout


_SIZE = {1: 1, 2: 1, 3: 2, 4: 4, 5: 8, 12: 8, 16: 8}
_FMT = {1: "B", 2: "c", 3: "H", 4: "I", 5: "II", 12: "d", 16: "Q"}


def _ifd(url):
    """The tags of the first (full size) image of a classic little-endian TIFF."""
    head = _get(url, 0, 65536)
    assert head[:4] == b"II*\x00", "not a classic little-endian TIFF"
    off = struct.unpack_from("<I", head, 4)[0]
    n = struct.unpack_from("<H", head, off)[0]
    tags = {}
    for k in range(n):
        tag, typ, cnt, val = struct.unpack_from("<HHII", head, off + 2 + 12 * k)
        size = _SIZE[typ] * cnt
        if size <= 4:
            raw = head[off + 2 + 12 * k + 8: off + 2 + 12 * k + 8 + size]
        elif val + size <= len(head):
            raw = head[val: val + size]
        else:
            raw = _get(url, val, size)
        if typ == 2:
            tags[tag] = raw.decode("latin1")
        elif typ == 5:
            tags[tag] = struct.unpack("<%dI" % (2 * cnt), raw)
        else:
            tags[tag] = struct.unpack("<%d%s" % (cnt, _FMT[typ]), raw)
    return tags


def window(url, e0, n0, e1, n1):
    """The pixels of a band over the UTM box (uint16), with the east of its left edge, the north of its top edge
    and the pixel size."""
    t = _ifd(url)
    w, h, tw, th = t[256][0], t[257][0], t[322][0], t[323][0]
    assert t[259][0] in (8, 32946) and t[258][0] == 16, "expected 16-bit deflate tiles"
    pred = t.get(317, (1,))[0]
    px = t[33550][0]
    tie = t[33922]
    west, north = tie[3] - tie[0] * px, tie[4] + tie[1] * px
    c0, c1 = int((e0 - west) // px), int((e1 - west) // px) + 1
    r0, r1 = int((north - n1) // px), int((north - n0) // px) + 1
    c0, r0, c1, r1 = max(c0, 0), max(r0, 0), min(c1, w), min(r1, h)
    out = np.zeros((r1 - r0, c1 - c0), np.uint16)
    across = (w + tw - 1) // tw
    for ty in range(r0 // th, (r1 - 1) // th + 1):
        for tx in range(c0 // tw, (c1 - 1) // tw + 1):
            k = ty * across + tx
            if t[325][k] == 0:
                continue
            tile = np.frombuffer(zlib.decompress(_get(url, t[324][k], t[325][k])), "<u2").reshape(th, tw)
            if pred == 2:
                tile = np.cumsum(tile, axis=1, dtype=np.uint16)
            ya, yb, xa, xb = max(r0, ty * th), min(r1, (ty + 1) * th), max(c0, tx * tw), min(c1, (tx + 1) * tw)
            out[ya - r0: yb - r0, xa - c0: xb - c0] = tile[ya - ty * th: yb - ty * th, xa - tx * tw: xb - tx * tw]
    return out, west + c0 * px, north - r0 * px, px


def fetch(x0, x1, z0, z1, to_latlon, log=print):
    """Every scene and band over the game box, cached. Returns {date: {band: array, "e0", "n0", "px"}}."""
    os.makedirs(CACHE, exist_ok=True)
    xs = np.array([x0, x1, x0, x1, (x0 + x1) / 2, (x0 + x1) / 2])
    zs = np.array([z0, z0, z1, z1, z0, z1])
    lat, lon = to_latlon(xs, zs)
    e, n = utm(lat, lon, 9.0)
    box = (math.floor(e.min() / 10) * 10 - 100, math.floor(n.min() / 10) * 10 - 100, math.ceil(e.max() / 10) * 10 + 100, math.ceil(n.max() / 10) * 10 + 100)
    got = {}
    for date, path in SCENES.items():
        frame = os.path.join(CACHE, "s2_%s.json" % date)
        if os.path.exists(frame) and json.load(open(frame)).get("box") != list(box):
            os.remove(frame)
        if not os.path.exists(frame):
            meta = {"box": list(box), "scene": path}
            for b in BANDS:
                log("  Sentinel-2 %s %s…" % (date, b))
                arr, we, no, px = window(BASE + path + "/" + b + ".tif", *box)
                np.save(os.path.join(CACHE, "s2_%s_%s.npy" % (date, b)), arr)
                meta.update(e0=we, n0=no, px=px)
            json.dump(meta, open(frame, "w"))
        meta = json.load(open(frame))
        got[date] = {b: np.load(os.path.join(CACHE, "s2_%s_%s.npy" % (date, b))) for b in BANDS}
        got[date].update(e0=meta["e0"], n0=meta["n0"], px=meta["px"])
    return got


def sample(scene, band, lat, lon):
    """A band at points, bilinear (pixel centres are half a pixel in from the corner the frame names)."""
    e, n = utm(lat, lon, 9.0)
    a = band if isinstance(band, np.ndarray) else scene[band].astype(np.float32)
    fx = np.clip((e - scene["e0"]) / scene["px"] - 0.5, 0, a.shape[1] - 1.001)
    fy = np.clip((scene["n0"] - n) / scene["px"] - 0.5, 0, a.shape[0] - 1.001)
    ix, iy = fx.astype(int), fy.astype(int)
    tx, ty = (fx - ix).astype(np.float32), (fy - iy).astype(np.float32)
    return (a[iy, ix] * (1 - tx) * (1 - ty) + a[iy, ix + 1] * tx * (1 - ty) + a[iy + 1, ix] * (1 - tx) * ty + a[iy + 1, ix + 1] * tx * ty)
