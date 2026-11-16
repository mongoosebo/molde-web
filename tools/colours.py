#!/usr/bin/env python3
"""Real wall and roof colours from Mapillary street photos (CC BY-SA), for the buildings that have any.

For every building with photos nearby, points on the walls and roof faces that a photo can see (the
right side, in range, nothing else in the way) are found in the photo from where it was taken and
which way it looks, and the colour there is read off. Many readings from several photos are boiled
down to one wall colour and one roof colour per building, leaving out sky, leaves and deep shadow.

Needs world/buildings.json (tools/build_map.py) and data/mapillary/images.json (tools/mapillary.py).
Writes data/colours.json: {OSM id: {"wall": [r, g, b], "roof": [r, g, b]}}; build_map.py uses it on its
next run. Photos are kept in data/mapillary/img/ (not in the repository).
"""
import json, math, os, subprocess, sys, datetime
from concurrent.futures import ThreadPoolExecutor
import numpy as np
from PIL import Image
import shapely
from shapely.geometry import Polygon, LineString
from shapely.ops import substring
from scipy.spatial import cKDTree

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import LAT0, LON0, MX, MZ, X0, Z0
from mapillary import token, DIR

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
IMG = os.path.join(DIR, "img")
REACH = 45.0          # how far a photo may be from what it shows
EYE = 2.3             # camera height above the ground
PER_BUILDING = 5      # photos used per building


class Ground:
    """The game's 1 m terrain, read from world/h1."""

    def __init__(self):
        fine = json.load(open(os.path.join(ROOT, "world", "meta.json")))["fine"]
        self.w, self.h, self.strip, self.scale, self.offset = fine["w"], fine["h"], fine["strip"], fine["scale"], fine["offset"]
        self.maps = []
        for k in range((self.w + self.strip - 1) // self.strip):
            cols = min(self.strip, self.w - k * self.strip)
            self.maps.append(np.memmap(os.path.join(ROOT, "world", "h1", "x%02d.bin" % k), "<u2", "r", shape=(self.h, cols)))

    def at(self, x, z):
        i = min(max(int(round(x - X0)), 0), self.w - 1)
        j = min(max(int(round(z - Z0)), 0), self.h - 1)
        return float(self.maps[i // self.strip][j, i % self.strip]) * self.scale + self.offset


def rotation(v):
    """Rotation matrix from an angle-axis vector (the way the photo's orientation is given)."""
    v = np.asarray(v, float)
    angle = float(np.linalg.norm(v))
    if angle < 1e-9:
        return np.eye(3)
    k = v / angle
    K = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + math.sin(angle) * K + (1 - math.cos(angle)) * (K @ K)


def pixel(cam, target):
    """Where a point (x, y, z) shows in a photo, as (column, row) in fractions of its size, or None.
    The photo's own orientation and lens are used: east-north-up into the camera's right-down-forward,
    then the lens model of its kind (perspective, fisheye or all-round)."""
    X, Y, Z = cam["R"] @ np.array([target[0] - cam["x"], -(target[2] - cam["z"]), target[1] - cam["y"]])
    if cam["kind"] == "spherical":
        lon = math.atan2(X, Z)
        lat = math.atan2(-Y, math.hypot(X, Z))
        return 0.5 + lon / (2 * math.pi), 0.5 - lat / math.pi
    if Z <= 0.05:
        return None
    if cam["kind"] == "fisheye":
        r = math.hypot(X, Y)
        theta = math.atan2(r, Z)
        d = 1 + cam["k1"] * theta ** 2 + cam["k2"] * theta ** 4
        xn, yn = (d * theta * X / r, d * theta * Y / r) if r > 1e-9 else (0.0, 0.0)
    else:
        xn, yn = X / Z, Y / Z
        r2 = xn * xn + yn * yn
        if r2 > 1.6:
            return None
        d = 1 + cam["k1"] * r2 + cam["k2"] * r2 * r2
        xn, yn = xn * d, yn * d
    u = 0.5 + cam["f"] * xn * cam["long"] / cam["w"]
    v = 0.5 + cam["f"] * yn * cam["long"] / cam["h"]
    return (u, v) if 0.03 < u < 0.97 and 0.03 < v < 0.97 else None


def boil(samples):
    """One colour from many readings: the middle of the biggest group of like readings — if at least
    half of them agree. Fewer than eight readings, or no agreement, gives nothing."""
    s = np.asarray(samples, float)
    if len(s) < 8:
        return None
    centre = np.median(s, 0)
    for _ in range(4):
        near = np.linalg.norm(s - centre, axis=1) < 42
        if near.sum() < 4:
            return None
        centre = np.median(s[near], 0)
    if near.sum() < max(6, 0.5 * len(s)):
        return None
    return [int(round(v)) for v in centre]


def trusted(rgb, roof):
    """Is a boiled-down colour one to believe? What stands between a camera and a house — a retaining wall,
    a road, a shadow, a hedge — is grey, dark or green, so those are not trusted; a light or a clearly
    coloured wall is, and so is a red or brown roof. Whites are evened out to one paint white."""
    r, g, b = rgb
    lum = 0.3 * r + 0.6 * g + 0.1 * b
    sat = max(rgb) - min(rgb)
    if roof:
        return [int(r), int(g), int(b)] if (r - b >= 28 and r > g and lum > 45) else None
    if g > r and g > b:
        return None
    if lum >= 165 and sat < 30:
        return [236, 234, 226]
    if lum >= 150 or (sat >= 45 and lum >= 60):
        return [int(r), int(g), int(b)]
    return None


def usable(rgb, spread, roof):
    r, g, b = rgb
    lum = 0.3 * r + 0.6 * g + 0.1 * b
    if spread > 30 or lum < (28 if roof else 48):
        return False                                               # a busy patch (branches, an edge) or deep shadow
    if g > r + 10 and g > b + 10:
        return False                                               # leaves
    if b > r + 22 and lum > 150:
        return False                                               # sky
    return True


def main(only=None, debug=False):
    ground = Ground()
    blds = json.load(open(os.path.join(ROOT, "world", "buildings.json")))
    polys = [Polygon(list(zip(b[5][0::2], b[5][1::2]))).buffer(0) for b in blds]
    tree = shapely.STRtree(polys)
    cams = []
    for r in json.load(open(os.path.join(DIR, "images.json"))):
        if "computed_geometry" not in r or "computed_rotation" not in r or r.get("camera_type") == "fisheye":
            continue                                                # (the few fisheye photos are turned another way round)
        lon, lat = r["computed_geometry"]["coordinates"]
        x, z = (lon - LON0) * MX, -(lat - LAT0) * MZ
        par = (r.get("camera_parameters") or [0.85, 0, 0]) + [0, 0, 0]
        cams.append({"id": r["id"], "x": x, "z": z, "y": ground.at(x, z) + EYE, "R": rotation(r["computed_rotation"]),
                     "kind": r.get("camera_type", "perspective"), "pano": bool(r.get("is_pano")),
                     "f": par[0] if par[0] > 0.2 else 0.85, "k1": par[1], "k2": par[2], "w": r.get("width", 4), "h": r.get("height", 3),
                     "long": max(r.get("width", 4), r.get("height", 3)), "year": datetime.datetime.fromtimestamp(r["captured_at"] / 1000).year,
                     "seq": r.get("sequence", "")})
    cam_tree = cKDTree([(c["x"], c["z"]) for c in cams])

    def clear(cam, x, z, own):
        ray = LineString([(cam["x"], cam["z"]), (x, z)])
        ray = substring(ray, 0, max(ray.length - 0.6, 0.1))
        return not any(polys[k].intersects(ray) for k in tree.query(ray))

    # ---- what each photo can see of each building
    jobs = {}                                                       # building index -> [(camera, [(roof?, point), ...]), ...]
    for bi, b in enumerate(blds):
        if only is not None and b[10] not in only:
            continue
        cx, cz = float(np.mean(b[5][0::2])), float(np.mean(b[5][1::2]))
        near = cam_tree.query_ball_point((cx, cz), REACH + 15)
        if not near:
            continue
        views = []
        for ci in near:
            cam = cams[ci]
            pts = []
            for w in b[6]["w"]:
                ax, az, bx, bz = w[:4]
                ln = math.hypot(bx - ax, bz - az)
                if ln < 2.5:
                    continue
                tx, tz = (bx - ax) / ln, (bz - az) / ln
                ox, oz = tz, -tx                                    # outward
                top = min(min(w[i + 1], w[i + 3]) for i in range(7, len(w) - 6, 7))
                base = max(w[4], w[5])
                if top - base < 2.2:
                    continue
                for f in (0.3, 0.5, 0.7):
                    x, z = ax + (bx - ax) * f, az + (bz - az) * f
                    vx, vz = cam["x"] - x, cam["z"] - z
                    d = math.hypot(vx, vz)
                    if not (5 < d < REACH) or (vx * ox + vz * oz) / d < 0.42 or not clear(cam, x, z, bi):
                        continue
                    for y in {round(top - 1.0, 1), round(top - 1.7, 1), round(max(top - 2.4, (base + top) / 2), 1)}:      # high up, clear of hedges and cars
                        pts.append((False, (x, y, z)))
            for face in b[6]["f"]:
                if face[0]:
                    continue
                P = np.array(face[1:]).reshape(-1, 3)
                n = np.zeros(3)
                for i in range(len(P)):
                    n += np.cross(P[i], P[(i + 1) % len(P)])
                if np.linalg.norm(n) < 6:                           # under 3 m2
                    continue
                n /= np.linalg.norm(n)
                if n[1] < 0:
                    n = -n
                c = P.mean(0)
                v = np.array([cam["x"], cam["y"], cam["z"]]) - c
                d = float(np.linalg.norm(v))
                if 8 < d < REACH + 10 and float(v @ n) / d > 0.12 and clear(cam, c[0], c[2], bi):
                    for q in (c, (c + P[0]) / 2, (c + P[len(P) // 2]) / 2):
                        pts.append((True, tuple(q)))
            pts = [(roof, p) for roof, p in pts if pixel(cam, p) is not None]
            if pts:
                score = len(pts) + (4 if cam["year"] >= 2023 else 0) + (3 if cam["pano"] else 0)
                views.append((score, ci, pts))
        views.sort(key=lambda v: -v[0])
        picked, seqs = [], {}
        for score, ci, pts in views:
            if seqs.get(cams[ci]["seq"], 0) >= 2:
                continue
            seqs[cams[ci]["seq"]] = seqs.get(cams[ci]["seq"], 0) + 1
            picked.append((ci, pts))
            if len(picked) >= PER_BUILDING:
                break
        if picked:
            jobs[bi] = picked
    want = sorted({cams[ci]["id"] for views in jobs.values() for ci, _ in views})
    print("buildings in view:", len(jobs), "photos needed:", len(want), flush=True)

    # ---- fetch the photos (1024 px versions)
    os.makedirs(IMG, exist_ok=True)

    def fetch(image_id):
        path = os.path.join(IMG, image_id + ".jpg")
        if os.path.exists(path) and os.path.getsize(path) > 2000:
            return True
        out = subprocess.run(["curl", "-s", "-m", "60", "-A", "map-builder/1.0", "-G", "https://graph.mapillary.com/" + image_id,
                              "--data-urlencode", "access_token=" + token(), "--data-urlencode", "fields=thumb_1024_url"],
                             capture_output=True, text=True).stdout
        try:
            url = json.loads(out)["thumb_1024_url"]
        except (ValueError, KeyError):
            return False
        subprocess.run(["curl", "-s", "-m", "90", "-A", "map-builder/1.0", "-o", path, url])
        return os.path.exists(path) and os.path.getsize(path) > 2000

    with ThreadPoolExecutor(8) as pool:
        got = list(pool.map(fetch, want))
    print("photos fetched:", sum(got), "missing:", got.count(False), flush=True)

    # ---- read the colours
    by_cam = {}
    for bi, views in jobs.items():
        for ci, pts in views:
            by_cam.setdefault(ci, []).append((bi, pts))
    readings = {bi: ([], []) for bi in jobs}
    seen_in = {bi: set() for bi in jobs}
    for ci, items in by_cam.items():
        path = os.path.join(IMG, cams[ci]["id"] + ".jpg")
        try:
            im = np.asarray(Image.open(path).convert("RGB")).astype(np.float32)
        except OSError:
            continue
        H, W = im.shape[:2]
        sky = np.median(im[int(H * 0.04):int(H * 0.12)].reshape(-1, 3), 0)      # what the sky looks like in this photo
        marks = []
        for bi, pts in items:
            for roof, p in pts:
                u, v = pixel(cams[ci], p)
                col, row = int(u * W) % W, int(v * H)
                if not (4 <= row < H - 4):
                    continue
                patch = im[row - 3:row + 4, max(col - 3, 0):col + 4].reshape(-1, 3)
                rgb = np.median(patch, 0)
                if float(np.abs(rgb - sky).max()) < 28 or rgb.min() > 244:
                    continue                                        # sky, not wall
                if usable(rgb, float(patch.std(0).mean()), roof):
                    readings[bi][1 if roof else 0].append(rgb)
                    seen_in[bi].add(ci)
                marks.append((col, row, roof))
        if debug:
            dbg = Image.open(path).convert("RGB")
            from PIL import ImageDraw
            d = ImageDraw.Draw(dbg)
            for col, row, roof in marks:
                d.rectangle((col - 4, row - 4, col + 4, row + 4), outline=(255, 0, 0) if roof else (0, 255, 255), width=2)
            dbg.save(os.path.join(DIR, "debug_" + cams[ci]["id"] + ".jpg"))
    out, raw = {}, {}
    for bi, (walls, roofs) in readings.items():
        rec = {}
        if len(seen_in[bi]) < 2:
            continue                                                # one photo alone is not enough
        wall, roof = boil(walls), boil(roofs)
        raw[str(blds[bi][10])] = {"wall": wall, "roof": roof}
        wall, roof = wall and trusted(wall, False), roof and trusted(roof, True)
        if wall:
            rec["wall"] = wall
        if roof:
            rec["roof"] = roof
        if rec:
            out[str(blds[bi][10])] = rec
    json.dump(raw, open(os.path.join(DIR, "raw_colours.json"), "w"))
    return out


if __name__ == "__main__":
    if len(sys.argv) > 1:                                           # a look at a few buildings: python3 colours.py <OSM id> …
        print(main({int(a) for a in sys.argv[1:]}, debug=True))
    else:
        res = main()
        json.dump(res, open(os.path.join(ROOT, "data", "colours.json"), "w"), separators=(",", ":"))
        print("buildings with a wall colour:", sum(1 for r in res.values() if "wall" in r), "with a roof colour:", sum(1 for r in res.values() if "roof" in r))
