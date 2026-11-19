#!/usr/bin/env python3
"""Paved ground the map does not know about (PLAN.md 2.1 to 2.3): car parks, yards and forecourts of asphalt.

Writes data/auto_paved.json: a list of {"kind": "asphalt", "area", "confidence", "outline": [x, z, ...],
"holes": [[x, z, ...], ...], "ndvi", "bright", "bare"} in the game's metres (+x east, +z south).

What it reads, and why not aerial photos: Kartverket's "Norge i bilder" orthophotos are not open data (the
catalogue marks every one of its services "Norge digitalt begrenset", and every endpoint asks for a token), so
this works from two open sources instead:

  * the 1 m laser terrain and surface models the map is built from (hoydedata.no, already in data/kartverket/):
    paved ground is flat, even, and nothing stands on it but cars;
  * Sentinel-2 satellite pictures at 10 m (tools/s2cog.py; free to use, "Contains modified Copernicus Sentinel
    data"): paved ground has no green in it. Three summer scenes, the middle value of each pixel.

Ground is taken as asphalt where it is land, not green (NDVI), flat and even (terrain model), bare or with
something car-sized on it (surface model), not a building, not water, not a pitch, a playground, a graveyard or
other ground OpenStreetMap says is not paved, and not paved in the map already. What is left must be 60 m2 or
more, at least some 3 m wide, and touch a road, a paved area or a building within 3 m.

It cannot tell gravel from asphalt, and at 10 m it cannot see a lawn narrower than a few metres. It is tuned to
leave things out rather than put lawns in. The confidence is a rule of thumb (less for green nearby, for much
standing on it, for no road beside it, for bright ground, for small pieces; 0.4 at most for large empty lots,
which are often gravel): lay what has 0.6 or more, and look at the rest first. The airfield is left alone.

  tools/ortho_paved.py                the whole map -> data/auto_paved.json
  tools/ortho_paved.py --calibrate    against the squares marked by hand (tools/patches.jsonl): uses the paved
                                      ground of the build before they were laid (commit 7f01196), prints how
                                      much of the marked asphalt is found, writes nothing but pictures
  tools/ortho_paved.py --pictures     also data/ortho/auto_paved_*.png
"""
import json, os, pickle, subprocess, sys
import numpy as np
import shapely
from shapely.ops import unary_union
from scipy import ndimage as ndi
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import X0, X1, Z0, Z1, to_latlon, MX, MZ, LAT0, LON0
import s2cog

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
ORTHO = os.path.join(DATA, "ortho")
FW, FH = int(X1 - X0) + 1, int(Z1 - Z0) + 1          # the builder's fine grid: pixel (j, i) is the point X0 + i, Z0 + j
BEFORE = "7f01196"                                   # the last build before the squares were marked

# ---- the thresholds (set on the marked squares, see --calibrate)
NDVI_MAX = 0.24        # green: the middle NDVI of three summer scenes (marked asphalt: 95 % under 0.20)
NDVI_ANY = 0.34        # ... and no single scene over this
NIR_WATER = 450        # near infrared under this is water or deep shadow
SLOPE_MAX = 0.10       # terrain slope, metres per metre (marked asphalt: 98 % under 0.10)
ROUGH_MAX = 0.07       # how far the terrain strays from its own smoothing, m, over 5 m
BARE = 0.35            # surface over terrain under this: nothing stands here
CAR = 2.6              # ... under this: a car, a van, a fence, a low hedge; filled in when bare ground surrounds it
EAVES = 2.5            # m from a mapped building where anything tall is taken as its eaves
CLOSE = 3              # m: gaps this wide in bare ground are closed (rows of parked cars)
OPEN = 1.5             # m: what is narrower than twice this is dropped
POCKET = 2.5           # m: half the width of a gap between a wall and paved ground that is filled
NDVI_POCKET = 0.12     # ... where the NDVI is under this
REACH = 4.0            # m: how far a narrow strip may run from a wide piece
MIN_AREA = 60.0        # m2
TOUCH = 3.0            # m to a road, a paved area or a building
LOW_SHORE = 1.2        # m over the sea: below this is beach and tide
RUNWAY = 150.0         # m from a runway's centre line where nothing is laid
EMPTY_AREA, EMPTY_BARE = 1000.0, 0.94      # a lot this large and this bare is as likely gravel as asphalt
BRIGHT_GRAVEL = 1750   # visible brightness over this looks more like gravel or concrete than asphalt

UNPAVED = {"gravel", "fine_gravel", "unpaved", "ground", "grass", "artificial_turf", "sand", "dirt", "compacted",
           "earth", "clay", "woodchips", "pebblestone", "mud", "tartan", "wood"}
NOT_PAVED_AREAS = {
    "leisure": {"pitch", "track", "playground", "stadium", "golf_course", "garden", "swimming_pool", "park", "dog_park"},
    "landuse": {"grass", "farmland", "cemetery", "flowerbed", "recreation_ground", "winter_sports", "meadow", "forest",
                "farmyard", "construction", "allotments", "quarry", "landfill", "brownfield", "greenfield", "village_green"},
    "natural": {"water", "wetland", "wood", "scrub", "bare_rock", "beach", "sand", "scree", "heath", "grassland", "shingle"},
    "amenity": {"grave_yard"},
}


def log(*a):
    print(*a, flush=True)


def to_xz(lat, lon):
    return (lon - LON0) * MX, -(lat - LAT0) * MZ


def raster(geoms, value=1, into=None):
    """Polygons (game metres) onto the fine grid. The big ones first, so that what lies in a hole of one is kept."""
    im = Image.new("L", (FW, FH), 0) if into is None else into
    d = ImageDraw.Draw(im)
    parts = [g for g in shapely.get_parts(geoms).tolist() if g.geom_type == "Polygon" and not g.is_empty]
    parts.sort(key=lambda g: -g.area)
    for g in parts:
        d.polygon([(x - X0 + 0.5, z - Z0 + 0.5) for x, z in g.exterior.coords], fill=value)
        for h in g.interiors:
            d.polygon([(x - X0 + 0.5, z - Z0 + 0.5) for x, z in h.coords], fill=0)
    return im


def disk(r):
    k = int(np.ceil(r))
    y, x = np.ogrid[-k:k + 1, -k:k + 1]
    return x * x + y * y <= r * r + 0.01


def marked_squares():
    out = {"asphalt": [], "paving": []}
    path = os.path.join(ROOT, "tools", "patches.jsonl")
    if os.path.exists(path):
        for ln in open(path):
            if ln.strip():
                q = json.loads(ln)
                h = q["size"] / 2.0
                sq = shapely.affinity.rotate(shapely.box(q["x"] - h, q["z"] - h, q["x"] + h, q["z"] + h), -q.get("yaw", 0.0), use_radians=True)
                out.setdefault(q["kind"], []).append(sq)
    return out


def paved_before():
    """The asphalt and the sidewalk of the build before the squares were marked, from that commit's paved.bin."""
    cache = os.path.join(ORTHO, "paved_before_%s.npy" % BEFORE)
    if os.path.exists(cache):
        return np.load(cache)
    raw = subprocess.run(["git", "-C", ROOT, "show", BEFORE + ":world/paved.bin"], capture_output=True, check=True).stdout
    data = np.frombuffer(raw, np.float32)
    im = Image.new("L", (FW, FH), 0)
    d = ImageDraw.Draw(im)
    i = 0
    while i + 6 <= len(data):
        n = [int(v) for v in data[i + 2:i + 6]]
        i += 6
        for cnt, width in zip(n, (9, 9, 10, 10)):
            if width == 9 and cnt:
                t = data[i:i + cnt * 9].reshape(cnt, 3, 3)
                for a in (np.stack([t[:, :, 0] - X0 + 0.5, t[:, :, 2] - Z0 + 0.5], 2).reshape(cnt, 6)).tolist():
                    d.polygon(a, fill=1)
            i += cnt * width
    m = np.asarray(im) > 0
    np.save(cache, m)
    return m


def osm_not_paved():
    """Ground OpenStreetMap says is something other than asphalt, as a mask; and the outlines of its car parks."""
    im = Image.new("L", (FW, FH), 0)
    d = ImageDraw.Draw(im)
    for e in json.load(open(os.path.join(DATA, "osm_raw.json")))["elements"]:
        t = e.get("tags", {})
        if e["type"] != "way" or "geometry" not in e or "building" in t:
            continue
        pts = [to_xz(p["lat"], p["lon"]) for p in e["geometry"]]
        px = [(x - X0 + 0.5, z - Z0 + 0.5) for x, z in pts]
        closed = len(pts) >= 4 and e["geometry"][0] == e["geometry"][-1]
        soft = t.get("surface") in UNPAVED
        if closed and "highway" not in t and (soft or any(t.get(k) in v for k, v in NOT_PAVED_AREAS.items())):
            d.polygon(px, fill=1)
        elif "highway" in t and (soft or t["highway"] in ("track", "path", "bridleway") and t.get("surface") not in ("asphalt", "paved", "concrete")):
            d.line(px, fill=1, width=7 if t["highway"] == "track" or soft else 3)       # a gravel road and its verges
        elif t.get("aeroway") in ("runway", "taxiway", "taxilane", "apron", "helipad"):
            # the airfield is the builder's own (a tint of the ground and paint on it): nothing is laid there
            if closed:
                d.polygon(px, fill=1)
            d.line(px, fill=1, width={"taxiway": 40, "taxilane": 30}.get(t["aeroway"], 3))
            if t["aeroway"] == "runway":                   # (the strip, its ends and the fill it stands on: 150 m)
                for g in shapely.get_parts(shapely.LineString(pts).buffer(RUNWAY)).tolist():
                    d.polygon([(x - X0 + 0.5, z - Z0 + 0.5) for x, z in g.exterior.coords], fill=1)
        elif t.get("barrier") in ("hedge",) or t.get("natural") == "tree_row":
            d.line(px, fill=1, width=3)
    return np.asarray(im) > 0


def water_mask():
    """Lakes and running water as the game knows them (world/waterlevel.bin, 2 m squares)."""
    m = np.zeros((FH, FW), bool)
    path = os.path.join(ROOT, "world", "waterlevel.bin")
    if not os.path.exists(path):
        return m
    data = open(path, "rb").read()
    n = int(np.frombuffer(data, np.int32, 1, 0)[0])
    for i in range(n):
        at = 4 + i * 10004
        cx, cz = np.frombuffer(data, np.int16, 2, at)
        lv = np.frombuffer(data, np.int16, 2500, at + 4).reshape(50, 50) > -32000
        j0, i0 = int(cz) * 100 - int(Z0), int(cx) * 100 - int(X0)
        big = np.repeat(np.repeat(lv, 2, 0), 2, 1)
        ja, jb, ia, ib = max(j0, 0), min(j0 + 100, FH), max(i0, 0), min(i0 + 100, FW)
        if ja < jb and ia < ib:
            m[ja:jb, ia:ib] |= big[ja - j0:jb - j0, ia - i0:ib - i0]
    return m


def satellite():
    """NDVI (middle and highest of the scenes), near infrared and visible brightness on the 10 m grid of the scenes."""
    S = s2cog.fetch(X0, X1, Z0, Z1, to_latlon, log)
    nd, nir, vis = [], [], []
    for s in S.values():
        r, n = s["B04"].astype(np.float32), s["B08"].astype(np.float32)
        nd.append((n - r) / (n + r + 1.0))
        nir.append(n)
        vis.append((r + s["B03"] + s["B02"]) / 3.0)
    frame = next(iter(S.values()))
    return {"ndvi": np.median(nd, 0), "ndmax": np.max(nd, 0), "nir": np.median(nir, 0), "vis": np.median(vis, 0),
            "e0": frame["e0"], "n0": frame["n0"], "px": frame["px"]}


def features():
    """The masks everything is decided from, on the whole fine grid. Cached in data/ortho/features.npz."""
    cache = os.path.join(ORTHO, "features.npz")
    key = [NDVI_MAX, NDVI_ANY, NIR_WATER, SLOPE_MAX, ROUGH_MAX, BARE, CAR, LOW_SHORE]
    if os.path.exists(cache):
        f = np.load(cache)
        if f["key"].tolist() == key:
            return {k: f[k] for k in f.files}
    sat = satellite()
    H = np.load(os.path.join(DATA, "kartverket", "h1_raw.npy"), mmap_mode="r")
    D = np.load(os.path.join(DATA, "kartverket", "dom_raw.npy"), mmap_mode="r")
    out = {k: np.zeros((FH, FW), bool) for k in ("land", "dry", "flat", "bare", "low")}
    out["ndvi"] = np.zeros((FH, FW), np.int8)          # NDVI x 100
    out["vis"] = np.zeros((FH, FW), np.uint8)          # visible brightness / 16
    STRIP, HALO = 400, 12
    xs = X0 + np.arange(FW, dtype=np.float64)
    for j0 in range(0, FH, STRIP):
        ja, jb = max(j0 - HALO, 0), min(j0 + STRIP + HALO, FH)
        h = np.asarray(H[ja:jb]).astype(np.float32)
        ok = np.isfinite(h) & (h > -50) & (h < 3000)
        h = np.where(ok, h, 0.0)
        dom = np.asarray(D[ja:jb]).astype(np.float32)
        nd = np.where(np.isfinite(dom) & (dom > -50) & (dom < 3000), dom - h, 0.0)
        hs = ndi.gaussian_filter(h, 1.0)
        gy, gx = np.gradient(hs)
        slope = np.hypot(gx, gy)
        res = h - ndi.gaussian_filter(h, 2.0)
        rough = np.sqrt(ndi.uniform_filter(res * res, 5))
        gxx, gzz = np.meshgrid(xs, Z0 + np.arange(ja, jb, dtype=np.float64))
        lat, lon = to_latlon(gxx, gzz)
        ndvi = s2cog.sample(sat, sat["ndvi"], lat, lon)
        ndmax = s2cog.sample(sat, sat["ndmax"], lat, lon)
        nir = s2cog.sample(sat, sat["nir"], lat, lon)
        vis = s2cog.sample(sat, sat["vis"], lat, lon)
        a, b = j0 - ja, j0 - ja + min(STRIP, FH - j0)
        sl = slice(j0, j0 + b - a)
        out["land"][sl] = (ok & (h > LOW_SHORE))[a:b]
        out["dry"][sl] = ((ndvi < NDVI_MAX) & (ndmax < NDVI_ANY) & (nir > NIR_WATER))[a:b]
        out["flat"][sl] = ((slope < SLOPE_MAX) & (rough < ROUGH_MAX))[a:b]
        out["bare"][sl] = (nd < BARE)[a:b]
        out["low"][sl] = (nd < CAR)[a:b]
        out["ndvi"][sl] = np.clip(ndvi * 100, -100, 100).astype(np.int8)[a:b]
        out["vis"][sl] = np.clip(vis / 16, 0, 255).astype(np.uint8)[a:b]
        log("  features: row %d of %d" % (min(j0 + STRIP, FH), FH))
    out["key"] = np.array(key)
    np.savez(cache, **out)
    return out


def find(f, bld, paved, soft, touch_extra=None, box=None):
    """The mask of new asphalt, and the bare part of it (for the confidence)."""
    base = f["land"] & f["dry"] & f["flat"] & ~bld & ~soft
    near_bld = ndi.binary_dilation(bld, disk(EAVES))
    core = base & f["bare"]
    fill = base & (f["low"] | near_bld)
    cand = core | (ndi.binary_closing(core | bld, disk(CLOSE)) & fill)      # (cars in a row, and cars and eaves along a wall)
    # Narrow strips go, but measured together with what is paved or built beside them: a 2 m strip between a
    # found yard and its road or its wall belongs to the yard. A strip that is narrow all by itself (the verge
    # of a road drawn too thin) goes all the same: only what lies within REACH of a wide piece is kept.
    whole = ndi.binary_opening(cand | paved | bld, disk(OPEN))
    new = whole & cand & ~paved
    wide = ndi.binary_opening(new, disk(OPEN))
    # ... and the pockets a few metres wide between a wall and what is paved already, where nothing at all is
    # green around (a bed of flowers along a wall cannot be seen at 10 m, so only there)
    pocket = cand & ~paved & ndi.binary_closing(paved | bld, disk(POCKET)) & (f["ndvi"] < int(NDVI_POCKET * 100))
    new = (new & ndi.binary_dilation(wide, disk(REACH))) | pocket
    # pinholes (a lamp post, a sign, one tree) are closed; larger holes stay
    holes = ndi.binary_fill_holes(new) & ~new & ~bld & ~paved
    lab, n = ndi.label(holes)
    if n:
        size = np.bincount(lab.ravel(), minlength=n + 1)
        new |= (size < 15)[lab] & holes & f["dry"] & ~soft
    lab, n = ndi.label(new)
    if not n:
        return new, core, lab, np.zeros(1, bool)
    size = np.bincount(lab.ravel(), minlength=n + 1)
    anchor = ndi.binary_dilation(paved | bld if touch_extra is None else paved | bld | touch_extra, disk(TOUCH))
    touches = np.bincount(lab.ravel(), weights=anchor.ravel(), minlength=n + 1) > 0
    keep = (size >= MIN_AREA) & touches
    keep[0] = False
    return keep[lab], core, lab, keep


def polygons(mask, f, core, bld_geom, road_px):
    """The mask as simplified outlines kept off the buildings, each with its area and how sure it is."""
    lab, n = ndi.label(mask)
    out = []
    tree = shapely.STRtree(shapely.get_parts(bld_geom))
    blds = shapely.get_parts(bld_geom)
    near_road = ndi.binary_dilation(road_px, disk(TOUCH))
    for k, sl in enumerate(ndi.find_objects(lab), 1):
        m = lab[sl] == k
        j0, i0 = sl[0].start, sl[1].start
        pad = np.zeros((m.shape[0], m.shape[1] + 2), bool)
        pad[:, 1:-1] = m
        dif = np.diff(pad.astype(np.int8), axis=1)
        rj, ra = np.nonzero(dif == 1)
        _, rb = np.nonzero(dif == -1)
        # runs of pixels along each row; pixel i is the metre around the point X0 + i
        g = shapely.union_all(shapely.box(X0 + i0 + ra - 0.5, Z0 + j0 + rj - 0.5, X0 + i0 + rb - 0.5, Z0 + j0 + rj + 0.5))
        g = g.buffer(0.75, quad_segs=3).buffer(-0.75, quad_segs=3).simplify(0.5)
        hit = tree.query(g.buffer(0.5))
        if len(hit):
            g = g.difference(unary_union(blds[hit]).buffer(0.3, quad_segs=2))
        nd = float(f["ndvi"][sl][m].mean()) / 100.0
        vis = float(f["vis"][sl][m].mean()) * 16.0
        bare = float(core[sl][m].mean())
        road = bool((near_road[sl] & m).any())
        conf = 0.95 - 1.6 * max(0.0, nd - 0.06) - 0.35 * (1.0 - bare) - (0.0 if road else 0.15) - 0.3 * min(max((vis - BRIGHT_GRAVEL) / 600.0, 0.0), 1.0)
        for p in shapely.get_parts(g).tolist():
            if p.geom_type != "Polygon" or p.area < MIN_AREA:
                continue
            p = shapely.Polygon(p.exterior, [h for h in p.interiors if shapely.Polygon(h).area >= 4.0])
            c = conf - (0.1 if p.area < 120 else 0.0)
            if p.area >= EMPTY_AREA and bare >= EMPTY_BARE:
                # A large flat lot with next to nothing standing on it. Of three such looked up in aerial photos,
                # two were gravel (a building site on the shore, a gravel lot in Årødalen): not to be trusted.
                c = min(c, 0.4)
            out.append({"kind": "asphalt", "area": round(p.area, 1), "confidence": round(min(max(c, 0.05), 0.95), 2),
                        "outline": [round(v, 2) for q in list(p.exterior.coords)[:-1] for v in q],
                        "holes": [[round(v, 2) for q in list(h.coords)[:-1] for v in q] for h in p.interiors],
                        "ndvi": round(nd, 3), "bright": round(vis), "bare": round(bare, 2), "at_road": road})
    out.sort(key=lambda q: -q["area"])
    return out


def picture(path, box, f, bld, paved, found, squares, scale=2):
    """Laser relief of a box with the green of the satellite, what the map paves (blue), what was found (yellow
    outline, faint fill) and the squares marked by hand (red)."""
    x0, x1, z0, z1 = box
    i0, i1, j0, j1 = int(x0 - X0), int(x1 - X0), int(z0 - Z0), int(z1 - Z0)
    D = np.nan_to_num(np.load(os.path.join(DATA, "kartverket", "dom_raw.npy"), mmap_mode="r")[j0:j1, i0:i1].astype(np.float32))
    D = np.clip(D, -10, 2000)
    gy, gx = np.gradient(D)
    hs = np.clip(0.55 + 0.5 * (gx - gy) / np.sqrt(1 + gx * gx + gy * gy), 0, 1)
    rgb = np.repeat(hs[:, :, None], 3, 2) * 255

    def tint(m, c, a):
        rgb[m] = rgb[m] * (1 - a) + np.array(c) * a
    nd = f["ndvi"][j0:j1, i0:i1]
    tint(nd >= int(NDVI_MAX * 100), (60, 170, 60), 0.30)
    tint(~f["land"][j0:j1, i0:i1], (40, 80, 120), 0.6)
    tint(paved[j0:j1, i0:i1], (70, 100, 230), 0.45)
    tint(bld[j0:j1, i0:i1], (50, 50, 50), 0.5)
    fm = found[j0:j1, i0:i1]
    tint(fm, (255, 220, 0), 0.30)
    im = Image.fromarray(rgb.astype(np.uint8)).resize(((i1 - i0) * scale, (j1 - j0) * scale), Image.NEAREST)
    d = ImageDraw.Draw(im)
    edge = fm & ~ndi.binary_erosion(fm)
    big = np.asarray(Image.fromarray(edge).resize(im.size, Image.NEAREST))
    px = np.asarray(im).copy()
    px[big] = (255, 200, 0)
    im = Image.fromarray(px)
    d = ImageDraw.Draw(im)
    for kind, col in (("asphalt", (255, 0, 0)), ("paving", (255, 0, 255))):
        for sq in squares.get(kind, []):
            c = [((x - x0 + 0.5) * scale, (z - z0 + 0.5) * scale) for x, z in sq.exterior.coords]
            if all(-50 < a < im.size[0] + 50 and -50 < b < im.size[1] + 50 for a, b in c):
                d.line(c, fill=col, width=1)
    im.save(path)
    log("  picture:", path)


def main():
    cal = "--calibrate" in sys.argv
    os.makedirs(ORTHO, exist_ok=True)
    log("laser and satellite features…")
    f = features()
    log("what the map has…")
    exp = pickle.load(open(os.path.join(DATA, "paved_expect.pkl"), "rb"))
    bld_geom = shapely.from_wkb(exp["buildings"])
    cache = os.path.join(ORTHO, "map_masks.npz")
    stamp = [os.path.getmtime(os.path.join(DATA, n)) for n in ("paved_expect.pkl", "osm_raw.json")] + [os.path.getmtime(os.path.join(ROOT, "world", "waterlevel.bin"))]
    if os.path.exists(cache) and np.load(cache)["stamp"].tolist() == stamp:
        m = np.load(cache)
        bld, road_now, side_now, soft = m["bld"], m["road"], m["side"], m["soft"]
    else:
        bld = np.asarray(raster(bld_geom)) > 0
        road_now = np.asarray(raster(unary_union([shapely.from_wkb(exp[k]) for k in ("road_all", "road_laid")]))) > 0
        side_now = np.asarray(raster(shapely.from_wkb(exp["side"]))) > 0
        soft = osm_not_paved() | ndi.binary_dilation(water_mask(), disk(2))
        np.savez(cache, bld=bld, road=road_now, side=side_now, soft=soft, stamp=np.array(stamp))
    squares = marked_squares()
    if cal:
        paved = paved_before()
        road_px = paved
    else:
        paved = road_now | side_now
        road_px = road_now
    log("finding…")
    if cal:                                                # only around the marked squares: quicker to tune on
        j0, j1, i0, i1 = int(-900 - Z0), int(300 - Z0), int(-300 - X0), int(2800 - X0)
        win = (slice(j0, j1), slice(i0, i1))
        got, core_w, _, _ = find({k: v[win] for k, v in f.items() if k != "key"}, bld[win], paved[win], soft[win])
        found, core = np.zeros((FH, FW), bool), np.zeros((FH, FW), bool)
        found[win], core[win] = got, core_w
    else:
        found, core, lab, keep = find(f, bld, paved, soft)
    log("  found: %d m2" % found.sum())

    if cal:
        sq_a = np.asarray(raster(unary_union(squares["asphalt"]))) > 0
        sq_p = np.asarray(raster(unary_union(squares["paving"]))) > 0
        # the marked area as the builder lays it: the squares, the gaps between them filled (closing by 3 m)
        fill_a = ndi.binary_closing(sq_a, disk(3)) & ~bld
        for name, m in (("the asphalt squares themselves", sq_a & ~bld), ("... with the gaps between them filled", fill_a)):
            was = m & paved
            todo = m & ~paved
            log("%s: %d m2 off buildings, %d m2 of it paved before, %d m2 new" % (name, m.sum(), was.sum(), todo.sum()))
            log("   found by this tool: %d m2 = %.1f %% of the new, %.1f %% counting what was paved before" % (
                (todo & found).sum(), 100.0 * (todo & found).sum() / max(todo.sum(), 1), 100.0 * (m & (found | paved)).sum() / max(m.sum(), 1)))
            miss = todo & ~found
            for why, mm in (("green (NDVI)", ~f["dry"]), ("not flat or even", f["dry"] & ~f["flat"]), ("OSM says not paved / water", f["dry"] & f["flat"] & soft),
                            ("something tall on it", f["dry"] & f["flat"] & ~soft & ~f["low"]), ("low shore", ~f["land"])):
                log("     missed, %s: %d m2" % (why, (miss & mm).sum()))
        todo_p = sq_p & ~bld & ~paved
        log("paving squares (not what this tool looks for): %d m2 new, %d m2 of it found as asphalt" % (todo_p.sum(), (todo_p & found).sum()))
        np.save(os.path.join(ORTHO, "found_calibrate.npy"), found)
        picture(os.path.join(ORTHO, "auto_paved_calibrate_marked.png"), (1560, 1960, -330, -110), f, bld, paved, found, squares, 4)
        picture(os.path.join(ORTHO, "auto_paved_calibrate_wide.png"), (1000, 2600, -700, 100), f, bld, paved, found, squares, 1)
        return

    log("outlines…")
    polys = polygons(found, f, core, bld_geom, road_px)
    json.dump(polys, open(os.path.join(DATA, "auto_paved.json"), "w"), separators=(",", ":"))
    tot = sum(p["area"] for p in polys)
    log("data/auto_paved.json: %d outlines, %d m2" % (len(polys), tot))
    for lo, hi in ((0.8, 1.01), (0.6, 0.8), (0.4, 0.6), (0.0, 0.4)):
        sel = [p["area"] for p in polys if lo <= p["confidence"] < hi]
        log("   confidence %.1f to %.1f: %d outlines, %d m2" % (lo, min(hi, 1.0), len(sel), sum(sel)))
    np.save(os.path.join(ORTHO, "found.npy"), found)
    if "--pictures" in sys.argv:
        picture(os.path.join(ORTHO, "auto_paved_centre.png"), (-600, 1000, -500, 200), f, bld, paved, found, squares, 2)
        picture(os.path.join(ORTHO, "auto_paved_east.png"), (1000, 2600, -700, 100), f, bld, paved, found, squares, 2)
        picture(os.path.join(ORTHO, "auto_paved_kvam_bergmo.png"), (-2600, -1000, -500, 300), f, bld, paved, found, squares, 2)
        x0, x1, z0, z1 = X0, X1 - 1, Z0, Z1 - 1
        i = Image.open(os.path.join(ORTHO, "auto_paved_centre.png"))
        ov = np.zeros((FH, FW, 3), np.uint8)
        ov[f["land"]] = (70, 70, 70)
        ov[f["land"] & (f["ndvi"] >= int(NDVI_MAX * 100))] = (50, 100, 50)
        ov[paved] = (90, 110, 220)
        ov[bld] = (20, 20, 20)
        ov[ndi.binary_dilation(found, disk(2))] = (255, 220, 0)
        Image.fromarray(ov).resize((FW // 4, FH // 4), Image.BILINEAR).save(os.path.join(ORTHO, "auto_paved_whole_map.png"))
        log("  picture:", os.path.join(ORTHO, "auto_paved_whole_map.png"))


if __name__ == "__main__":
    main()
