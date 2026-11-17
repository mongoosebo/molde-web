#!/usr/bin/env python3
"""Turn raw OpenStreetMap data and Kartverket elevation for Molde into the files the game loads.

Inputs:  data/osm_raw.json (tools/fetch_osm.py), Kartverket terrain and laser data (tools/kartverket.py)
Outputs (world/): height.bin, mask.png, buildings.json, trees.bin, wrecks.bin, meta.json

World frame: +X east, +Z south, Y up, metres. Origin = Molde town centre.
"""
import json, math, os, random, struct, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DATA = os.path.join(ROOT, "data")
OUT = os.path.join(ROOT, "world")
os.makedirs(OUT, exist_ok=True)

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import LAT0, LON0, MX, MZ, X0, X1, Z0, Z1, to_latlon   # the game area and its frame
import overrides                                # corrections made by hand, from notes left in the game

CELL = 10.0                                     # height grid spacing
GW = int((X1 - X0) / CELL) + 1
GH = int((Z1 - Z0) / CELL) + 1
MASK_RES = 2.0                                  # metres per mask pixel
MW, MH = int((X1 - X0) / MASK_RES), int((Z1 - Z0) / MASK_RES)
SS = 2                                          # draw mask at 1 m, then downsample

rng = random.Random(1940)

from kartverket import Sampler, Terrain  # laser surface (DOM) and terrain (DTM) models, 1 m
DOM, DTM = Sampler("dom"), Sampler("dtm")


def to_xz(lat, lon):
    return (lon - LON0) * MX, -(lat - LAT0) * MZ


def blur(arr, radius):
    """Gaussian blur of a float array in [0,1] via PIL."""
    im = Image.fromarray(np.clip(arr * 255, 0, 255).astype(np.uint8))
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0


print("elevation…")
# The ground is Kartverket's 1 m terrain model, resampled into the game's frame. The resampled grid is
# kept in data/kartverket/ so that later runs start quickly. The sea is 0 or missing in the model.
from kartverket import fetch_area, grid
FW, FH = int(X1 - X0) + 1, int(Z1 - Z0) + 1     # the fine grid: one height per metre
_raw = os.path.join(DATA, "kartverket", "h1_raw.npy")
if os.path.exists(_raw):
    H1 = np.load(_raw)
else:
    print("  tiles:", fetch_area("dtm", X0, X1, Z0, Z1))
    H1 = grid("dtm", X0, Z0, FW, FH)
    np.save(_raw, H1)
assert H1.shape == (FH, FW)


def blur_big(mask, radius):
    """Gaussian blur of a big boolean grid, as float 0…1."""
    im = Image.fromarray(mask.astype(np.uint8) * 255)
    return np.asarray(im.filter(ImageFilter.GaussianBlur(radius))).astype(np.float32) / 255.0


sea = np.isnan(H1) | (H1 <= 0.25) | (H1 > 1500)
sea |= blur_big(sea, 12) > 0.7                      # stray readings inside the gaps
# Give the seabed a slope away from the shore so the waterline is clean.
shore = blur_big(sea, 40)                           # 0 on land … 1 in open water
H1 = np.where(sea, -0.6 - 14.0 * np.clip((shore - 0.45) / 0.55, 0, 1), np.maximum(np.nan_to_num(H1), 0.45)).astype(np.float32)
del shore


def height_at(x, z):
    fx = min(max(x - X0, 0), FW - 1.001)
    fz = min(max(z - Z0, 0), FH - 1.001)
    ix, iz = int(fx), int(fz)
    tx, tz = fx - ix, fz - iz
    return float(H1[iz, ix] * (1 - tx) * (1 - tz) + H1[iz, ix + 1] * tx * (1 - tz)
                 + H1[iz + 1, ix] * (1 - tx) * tz + H1[iz + 1, ix + 1] * tx * tz)


# ---------------------------------------------------------------- OSM
print("osm…")
elements = json.load(open(os.path.join(DATA, "osm_raw.json")))["elements"]


def pts_of(e):
    return [to_xz(g["lat"], g["lon"]) for g in e.get("geometry", [])]


def inside(x, z, margin=0.0):
    return X0 + margin < x < X1 - margin and Z0 + margin < z < Z1 - margin


ROAD_W = {"trunk": 9.5, "trunk_link": 7, "primary": 9, "primary_link": 7, "secondary": 8, "tertiary": 7,
          "residential": 5.5, "unclassified": 5.5, "living_street": 5, "service": 3.6, "pedestrian": 6,
          "raceway": 6}
PATH_W = {"footway": 2.2, "path": 1.8, "cycleway": 2.8, "steps": 2.2, "track": 3.0}

big = (MW * SS, MH * SS)
road_im = Image.new("L", big, 0)
path_im = Image.new("L", big, 0)
open_im = Image.new("L", big, 0)     # grass, pitches, cemeteries, aprons: no forest here
wood_im = Image.new("L", big, 0)
lake_im = Image.new("L", big, 0)
bld_im = Image.new("L", big, 0)
lawn_im = Image.new("L", big, 0)     # mown grass: parks, pitches, graveyards, gardens
farm_im = Image.new("L", big, 0)     # fields and meadows
wet_im = Image.new("L", big, 0)      # bog
rock_im = Image.new("L", big, 0)     # bare rock, scree, sand
line_im = Image.new("L", big, 0)     # under overhead power lines
d_lawn, d_farm, d_wet, d_rock, d_line = (ImageDraw.Draw(i) for i in (lawn_im, farm_im, wet_im, rock_im, line_im))
d_road, d_path, d_open = ImageDraw.Draw(road_im), ImageDraw.Draw(path_im), ImageDraw.Draw(open_im)
d_wood, d_lake, d_bld = ImageDraw.Draw(wood_im), ImageDraw.Draw(lake_im), ImageDraw.Draw(bld_im)


def px(points):
    s = SS / MASK_RES
    return [((x - X0) * s, (z - Z0) * s) for x, z in points]


def draw_line(draw, points, width_m):
    p = px(points)
    w = max(1, int(round(width_m * SS / MASK_RES)))
    draw.line(p, fill=255, width=w, joint="curve")
    r = w / 2
    for x, y in (p[0], p[-1]):
        draw.ellipse((x - r, y - r, x + r, y + r), fill=255)


def cover(t, ring, hole=False):
    """Paint what the map says covers the ground inside an outline (or clear it again, for a hole)."""
    p = px(ring)
    if len(p) < 3:
        return
    fill = 0 if hole else 255
    nat, lu, ls = t.get("natural"), t.get("landuse"), t.get("leisure")
    if nat == "water":
        d_lake.polygon(p, fill=fill)
        if not hole:
            lakes.append(list(ring))
    elif nat in ("wood", "scrub"):
        d_wood.polygon(p, fill=fill)
    elif nat == "wetland":
        d_wet.polygon(p, fill=fill)
    elif nat in ("bare_rock", "scree", "beach", "sand", "shingle"):
        d_rock.polygon(p, fill=fill)
    elif lu in ("farmland", "meadow", "orchard", "allotments"):
        d_farm.polygon(p, fill=fill)
    elif lu in ("grass", "cemetery", "recreation_ground", "village_green", "flowerbed") or ls in (
            "park", "pitch", "garden", "playground", "golf_course", "track", "stadium") or t.get("amenity") == "grave_yard":
        d_lawn.polygon(p, fill=fill)
    if not hole and (lu in ("grass", "cemetery", "industrial", "harbour", "farmland", "meadow") or ls or nat in ("wetland", "bare_rock", "beach", "sand")):
        d_open.polygon(p, fill=255)


def level_site(points, target, margin):
    """Flatten the terrain under a large structure (target None: the median height there),
    blending back into the surroundings over some metres. Returns the level used."""
    pad = margin + 30
    i0 = max(0, int(min(q[0] for q in points) - pad - X0))
    i1 = min(FW, int(max(q[0] for q in points) + pad - X0) + 1)
    j0 = max(0, int(min(q[1] for q in points) - pad - Z0))
    j1 = min(FH, int(max(q[1] for q in points) + pad - Z0) + 1)
    im = Image.new("L", (i1 - i0, j1 - j0), 0)
    p = [(x - X0 - i0, z - Z0 - j0) for x, z in points]
    d = ImageDraw.Draw(im)
    d.polygon(p, fill=255)
    d.line(p + [p[0]], fill=255, width=max(1, int(2 * margin)))
    core = np.asarray(im) > 0
    win = H1[j0:j1, i0:i1]
    if target is None:
        target = float(np.median(win[core]))
    m = np.maximum(blur_big(core, 8) * 1.6 - 0.3, core.astype(np.float32)).clip(0, 1)
    H1[j0:j1, i0:i1] = win * (1 - m) + target * m
    return target


# Structures modelled by hand in scripts/monuments.gd.
STADIUM_ID, PITCH_ID, SEILET_ID = 74887533, 401866199, 88452674
stadium = {}
piers = []
portals = []          # mouths of the road tunnels: [x, z, direction into the hill, blocked with rubble]
RUBBLE_TUNNELS = {36394009}                      # Haukabøtunnelen: the way out west is buried

waterways = []        # (kind, points) of rivers, streams and ditches above ground
lakes = []            # outlines of lakes and ponds
museums = []          # outlines of open-air museums
runways = []          # centre lines of runways
stands = []           # aircraft parking positions
osm_nodes = []        # (tags, x, z) of every mapped point: lamps, bus stops, benches, single trees …
barriers = []         # (kind, points): fences, hedges, walls, guard rails
parkings = []         # outlines of car parks
playgrounds = []      # outlines of playgrounds
power_lines = []      # points of overhead lines
tree_rows = []
way_tags = []         # (points, tags) of the roads, for signs and lamps
bridges = []          # [half width, markings, points] of everything carried over a gap
road_areas = []       # squares and yards mapped as areas: [pedestrian?, points]
storgata = []         # the stretches of Storgata, the main shopping street
tags_of = {}          # id of a road's point list -> its tags
round_lines = []      # the roads that are roundabouts: (points, half width)
pedestrian_ids = set()
road_ways = []        # for the road meshes: [kind, half width, markings, sidewalk left, sidewalk right, points]
MARKED = {"trunk": 2, "primary": 2, "secondary": 1, "tertiary": 1}
PAVED = {"asphalt", "paved", "paving_stones", "concrete", "sett"}

streets = {}          # name -> list of polylines (for the HUD)
drivable = []         # polylines for wreck placement
buildings_raw = []
plaza = []
places, pois = [], []

# buildings mapped as relations (an outline in several pieces, or with a courtyard): one building per outer ring
from shapely.geometry import LineString, Polygon as SPoly, MultiPoint
from shapely.ops import unary_union, polygonize
import shapely
for e in list(elements):
    if e["type"] == "relation" and "building" in e.get("tags", {}):
        lines = [LineString([to_xz(g["lat"], g["lon"]) for g in m["geometry"]]) for m in e.get("members", [])
                 if m.get("role") != "inner" and len(m.get("geometry", [])) >= 2]
        for k, poly in enumerate(polygonize(unary_union(lines)) if lines else []):
            ring = [to_latlon(x, z) for x, z in poly.exterior.coords]
            elements.append({"type": "way", "id": 10 ** 10 + e["id"] * 10 + k, "tags": e["tags"],
                             "geometry": [{"lat": la, "lon": lo} for la, lo in ring]})

# woods, lakes, bogs and fields mapped as relations: every outer ring, less the holes
for e in elements:
    t = e.get("tags", {})
    if e["type"] == "relation" and "building" not in t and (t.get("natural") or t.get("landuse")):
        for role, hole in (("outer", False), ("inner", True)):
            lines = [LineString([to_xz(g["lat"], g["lon"]) for g in m["geometry"]]) for m in e.get("members", [])
                     if m.get("role", "outer") == role and len(m.get("geometry", [])) >= 2]
            for poly in (polygonize(unary_union(lines)) if lines else []):
                cover(t, list(poly.exterior.coords), hole)

# ---- corrections by hand (tools/overrides.py) join the map as if they had been mapped
def _as_way(wid, tags, ring):
    ring = list(ring) + [ring[0]]
    return {"type": "way", "id": wid, "tags": tags, "geometry": [dict(zip(("lat", "lon"), to_latlon(x, z))) for x, z in ring]}


def laser_footprints(window, min_h, known=None):
    """Outlines of what stands inside a window, from the laser surface model: tall, and smooth like a roof."""
    from scipy import ndimage as _nd
    x0, x1, z0, z1 = window
    i0, i1, j0, j1 = int(x0 - X0), int(x1 - X0), int(z0 - Z0), int(z1 - Z0)
    dom = np.load(os.path.join(DATA, "kartverket", "dom_raw.npy"), mmap_mode="r")[j0:j1, i0:i1]
    dtm = np.load(os.path.join(DATA, "kartverket", "h1_raw.npy"), mmap_mode="r")[j0:j1, i0:i1]
    A = np.nan_to_num(np.asarray(dom, float) - np.asarray(dtm, float))
    m = (A > min_h) & (_nd.maximum_filter(A, 3) - _nd.minimum_filter(A, 3) < 2.2)
    m = _nd.binary_dilation(_nd.binary_closing(_nd.binary_opening(m, iterations=2), iterations=2), iterations=1) & (A > min_h * 0.6)
    if known is not None and not known.is_empty:               # what the map already has as buildings is not traced again
        jj, ii = np.nonzero(m)
        inside_known = shapely.contains_xy(known, x0 + ii + 0.5, z0 + jj + 0.5)
        m[jj[inside_known], ii[inside_known]] = False
        m = _nd.binary_opening(m, iterations=2)
    lab, n = _nd.label(m)
    out = []
    for k in range(1, n + 1):
        part = lab == k
        if part.sum() < 150:
            continue
        boxes = []
        for j in range(part.shape[0]):
            run = np.flatnonzero(np.diff(np.concatenate(([0], part[j].astype(np.int8), [0]))))
            for a, b in zip(run[0::2], run[1::2]):
                boxes.append(shapely.box(x0 + a, z0 + j, x0 + b, z0 + j + 1))
        g = unary_union(boxes).buffer(1.0, join_style="mitre").buffer(-1.0, join_style="mitre").simplify(1.3)
        for poly in getattr(g, "geoms", [g]):
            if poly.geom_type == "Polygon" and poly.area > 150:
                out.append(poly)
    return sorted(out, key=lambda q: -q.area)


# the golf course is mapped as relations, which the main download does not have: data/osm_golf.json
golf_polys = []
_gpath = os.path.join(DATA, "osm_golf.json")
if os.path.exists(_gpath):
    for e in json.load(open(_gpath))["elements"]:
        if e["type"] == "relation" and e.get("tags", {}).get("leisure") == "golf_course":
            lines = [LineString([to_xz(g["lat"], g["lon"]) for g in m["geometry"]]) for m in e.get("members", [])
                     if m.get("role") != "inner" and len(m.get("geometry", [])) >= 2]
            for k, poly in enumerate(polygonize(unary_union(lines))):
                golf_polys.append(poly)
                elements.append(_as_way(9_200_000_000 + e["id"] * 10 + k, {"leisure": "golf_course"}, list(poly.exterior.coords)[:-1]))
pitch_ways, cemeteries, court_ways = [], [], []
_pond_ids = {q["way"] for q in overrides.PONDS}
ponds = []
_fuel = [to_xz(e["lat"], e["lon"]) for e in elements if e["type"] == "node" and e.get("tags", {}).get("amenity") == "fuel"]
_drop = set(overrides.DROP_WAYS)
_wanted_ids = {v for v in overrides.SPORTS.values() if isinstance(v, int)}
wanted, coasts, canopy_ways = {}, [], []
for k, ring in enumerate(overrides.PARKING):
    elements.append(_as_way(9_000_000_000 + k, {"amenity": "parking", "surface": "asphalt"}, ring))
for k, lb in enumerate(overrides.LASER_BUILDINGS):
    _wb = shapely.box(lb["window"][0], lb["window"][2], lb["window"][1], lb["window"][3])
    _have = []
    for e in elements:
        if e["type"] == "way" and "building" in e.get("tags", {}) and len(e.get("geometry", [])) >= 4 and e["id"] not in lb.get("replaces", []):
            q = SPoly([to_xz(g["lat"], g["lon"]) for g in e["geometry"]])
            if q.is_valid and q.intersects(_wb):
                _have.append(q.buffer(1.5))
    found = laser_footprints(lb["window"], lb["min_h"], unary_union(_have) if _have else None)
    if lb.get("one") and len(found) > 1:                    # one building: its parts run together
        whole = unary_union(found).buffer(9.0, join_style="mitre").buffer(-9.0, join_style="mitre").simplify(1.5)
        found = sorted([q for q in getattr(whole, "geoms", [whole]) if q.geom_type == "Polygon"], key=lambda q: -q.area)[:1]
    for j, poly in enumerate(found):
        elements.append(_as_way(9_100_000_000 + 20 * k + j, {"building": lb["kind"], "name": lb["name"] if j == 0 else ""}, list(poly.exterior.coords)[:-1]))
    if found:
        _drop |= set(lb.get("replaces", []))
    print("  traced from the laser model:", lb["name"], [round(q.area) for q in found], "m²")

for e in elements:
    t = e.get("tags", {})
    if e["type"] == "node":
        x, z = to_xz(e["lat"], e["lon"])
        if not inside(x, z):
            continue
        osm_nodes.append((t, x, z))
        if "place" in t and t.get("name"):
            places.append({"name": t["name"], "kind": t["place"], "x": round(x, 1), "z": round(z, 1)})
        elif t.get("amenity") or t.get("shop"):
            pois.append({"name": t.get("name", ""), "kind": t.get("amenity") or t.get("shop"),
                         "x": round(x, 1), "z": round(z, 1)})
        continue
    pts = pts_of(e)
    if len(pts) < 2:
        continue
    closed = len(pts) >= 4 and pts[0] == pts[-1]
    if e["id"] in _pond_ids and closed:
        ponds.append(pts)
    if e["id"] in _wanted_ids:
        wanted[e["id"]] = pts
        continue
    if e["id"] in _drop:
        continue
    if t.get("natural") == "coastline":
        coasts.append(pts)
        continue
    if t.get("building") == "roof" and closed and any(math.hypot(pts[0][0] - fx, pts[0][1] - fz) < 45 for fx, fz in _fuel):
        canopy_ways.append(pts)                          # the roof over the pumps of a filling station
        continue
    if closed and t.get("leisure") == "pitch" and t.get("sport") == "soccer" and e["id"] != PITCH_ID:
        pitch_ways.append((e["id"], pts))
    if closed and t.get("leisure") == "pitch" and t.get("sport") in ("beachvolleyball", "volleyball"):
        court_ways.append(pts)
    if closed and (t.get("landuse") == "cemetery" or t.get("amenity") == "grave_yard"):
        cemeteries.append(pts)
    if e["id"] == STADIUM_ID:
        stadium["outline"] = [round(v, 2) for q in pts[:-1] for v in q]
        stadium["y"] = round(level_site(pts, None, 12), 2)
        d_bld.polygon(px(pts), fill=255)                 # keeps trees out
        d_open.polygon(px(pts), fill=255)
        continue
    if e["id"] == PITCH_ID:
        stadium["pitch"] = [round(v, 2) for q in pts[:-1] for v in q]
        continue
    if t.get("man_made") in ("pier", "breakwater", "quay"):
        piers.append({"closed": closed, "kind": t["man_made"],
                      "pts": [round(v, 2) for q in (pts[:-1] if closed else pts) for v in q]})
        continue
    if e["id"] == SEILET_ID:
        level_site(pts, 2.4, 14)                         # the hotel stands on a filled quay
    if t.get("barrier") in ("fence", "hedge", "wall", "retaining_wall", "guard_rail"):
        barriers.append((overrides.BARRIER_KIND.get(e["id"], t["barrier"]), pts))
        continue
    if t.get("power") == "line":
        power_lines.append(pts)
        draw_line(d_line, pts, 16)
        continue
    if t.get("waterway") in ("stream", "river", "ditch", "canal") and t.get("tunnel") is None:
        draw_line(d_lake, pts, 8.0 if t["waterway"] == "river" else 3.0)
        waterways.append((t["waterway"], pts))
        continue
    if t.get("natural") == "tree_row":
        tree_rows.append(pts)
        continue
    if t.get("amenity") == "parking" and closed and "building" not in t and t.get("parking") not in ("underground", "multi-storey"):
        parkings.append(pts)
        d_road.polygon(px(pts), fill=255)
        d_open.polygon(px(pts), fill=255)
        continue
    if t.get("leisure") == "playground" and closed:
        playgrounds.append(pts)
    if t.get("tourism") == "museum" and closed and "building" not in t:
        museums.append(SPoly(pts).buffer(0))
    if "building" in t:
        if closed:
            buildings_raw.append((t, pts[:-1], e["id"]))
            d_bld.polygon(px(pts), fill=255)
    elif "highway" in t:
        hw = t["highway"]
        if hw in ROAD_W and t.get("tunnel") != "yes":
            way_tags.append((pts, t))
        if e["id"] == 945769320:
            plaza = [round(v, 2) for p in pts[:-1] for v in p]
        if t.get("tunnel") in ("yes", "building_passage") and hw not in PATH_W:
            if t.get("tunnel") == "yes":
                if hw in ROAD_W and hw != "service":
                    for a, b in ((pts[0], pts[1]), (pts[-1], pts[-2])):
                        ln = math.hypot(b[0] - a[0], b[1] - a[1])
                        if inside(a[0], a[1], 40) and ln > 0.5:
                            portals.append({"x": round(a[0], 1), "z": round(a[1], 1), "dx": round((b[0] - a[0]) / ln, 3),
                                            "dz": round((b[1] - a[1]) / ln, 3), "w": ROAD_W[hw],
                                            "rubble": e["id"] in RUBBLE_TUNNELS, "name": t.get("name", "")})
                continue
        if t.get("bridge") not in (None, "no") and (hw in ROAD_W or hw in PATH_W) and not (t.get("area") == "yes"):
            mark = MARKED.get(hw, 0) if hw in ROAD_W else 0
            bridges.append([(ROAD_W[hw] if hw in ROAD_W else PATH_W[hw]) / 2, mark, pts])
            draw_line(d_bld, pts, (ROAD_W[hw] if hw in ROAD_W else PATH_W[hw]) + 2.0)      # keeps trees off the deck
            if hw in ROAD_W and hw not in ("service", "pedestrian", "raceway"):
                drivable.append((hw, pts))
        elif hw in ROAD_W:
            if t.get("area") == "yes" and closed:
                d_road.polygon(px(pts), fill=255)
                if e["id"] != 945769320:                 # Rådhusplassen has its own paving (scripts/landmarks.gd)
                    road_areas.append([hw == "pedestrian", pts])
            else:
                draw_line(d_road, pts, ROAD_W[hw])
                if hw not in ("pedestrian", "raceway") and t.get("surface") not in ("unpaved", "gravel", "compacted", "fine_gravel", "ground", "dirt"):
                    sw = t.get("sidewalk", "")
                    both = sw == "both" or t.get("sidewalk:both") == "yes"
                    if t.get("name") == "Storgata":
                        both = True                          # the main street has a sidewalk on both sides throughout
                        storgata.append(pts)
                    left = both or sw == "left" or t.get("sidewalk:left") == "yes"
                    right = both or sw == "right" or t.get("sidewalk:right") == "yes"
                    mark = 0 if t.get("junction") == "roundabout" else MARKED.get(hw, 0)
                    if t.get("oneway") == "yes" and mark:
                        mark = 3 if mark == 2 else 0                # edge lines only
                    half_w = ROAD_W[hw] / 2
                    if t.get("oneway") == "yes" and t.get("junction") != "roundabout" and half_w > 3.0:
                        half_w = max(2.6, half_w * 0.58)             # one direction only: one carriageway of a divided road
                    road_ways.append([0, half_w, mark, left, right, pts, t.get("bridge") is None])
                    tags_of[id(pts)] = t
                    if t.get("junction") == "roundabout":
                        round_lines.append((pts, ROAD_W[hw] / 2))
                elif hw == "pedestrian":
                    road_ways.append([0, 3.0, 0, False, False, pts, True])
                    pedestrian_ids.add(id(pts))
            if hw not in ("service", "pedestrian", "raceway"):
                drivable.append((hw, pts))
        elif hw in PATH_W:
            draw_line(d_path, pts, PATH_W[hw])
            if t.get("tunnel") != "yes":
                if hw == "footway" and t.get("footway") == "sidewalk":
                    road_ways.append([1, 1.0, 0, False, False, pts, False])      # a sidewalk mapped as its own line
                elif hw == "footway" and t.get("footway") == "crossing":
                    road_ways.append([2, 1.5, 0, False, False, pts, False])      # zebra crossing
                elif hw == "cycleway" or (hw == "footway" and t.get("surface") in PAVED):
                    road_ways.append([3, PATH_W[hw] / 2, 0, False, False, pts, False])   # paved foot and cycle path
                elif hw == "steps":
                    road_ways.append([8, 1.0, 0, False, False, pts, False])              # a flight of steps
                else:
                    # gravel walks and tracks (7); a trail on bare earth is narrower and darker (marking 1)
                    earth = hw == "path" and t.get("surface") not in ("gravel", "fine_gravel", "compacted", "paved", "asphalt")
                    road_ways.append([7, PATH_W[hw] / 2 * (0.7 if earth else 0.85), 1 if earth else 0, False, False, pts, False])
        else:
            continue
        if t.get("name"):
            streets.setdefault(t["name"], []).append(pts)
    elif "aeroway" in t:
        if t["aeroway"] == "parking_position":
            stands.append(pts)
        if t["aeroway"] == "runway":
            runways.append(pts)
            draw_line(d_road, pts, 45)
        elif t["aeroway"] == "taxiway":
            draw_line(d_road, pts, 18)
        elif closed:
            d_road.polygon(px(pts), fill=255)
        draw_line(d_open, pts, 160)
    elif closed:
        cover(t, pts)

# ---------------------------------------------------------------- roads and sidewalks for the close-up meshes
# ---------------------------------------------------------------- outlines put where the laser has the building
# Many outlines on the map were drawn by hand from aerial photos and sit a metre or three beside the house
# (garages and sheds most of all). Each building, or each group of buildings that touch, is slid over the laser
# surface model to where most of it stands on something roof-like (standing well over the ground, and even) and
# least of its surroundings do; it is moved there when that is clearly better. Results are kept between runs.
def _register_outlines():
    import pickle
    path = os.path.join(DATA, "kartverket", "shifts2.pkl")
    try:
        cache = pickle.load(open(path, "rb"))
    except (OSError, EOFError):
        cache = {}
    fixed = {231352909, 172573648, 172573646, 935525932, 310662273, 230972703, SEILET_ID} | {i for i, v in overrides.BUILDINGS.items() if v.get("join")}
    polys, index = [], []
    for k, (_t, q, _i) in enumerate(buildings_raw):
        if len(q) >= 3:
            g = SPoly(q)
            if g.is_valid and g.area > 4:
                polys.append(g)
                index.append(k)
    tree = shapely.STRtree(polys)
    parent = list(range(len(polys)))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    ia, ib = tree.query(polys, predicate="dwithin", distance=0.25)
    for a, b in zip(ia.tolist(), ib.tolist()):
        if a != b:
            parent[find(a)] = find(b)
    groups = {}
    for a in range(len(polys)):
        groups.setdefault(find(a), []).append(a)
    moved, tried = 0, 0
    for members in groups.values():
        if any(buildings_raw[index[a]][2] in fixed for a in members):
            continue
        foot = unary_union([polys[a] for a in members]) if len(members) > 1 else polys[members[0]]
        if foot.area > 1500:
            continue
        key = (tuple(sorted(buildings_raw[index[a]][2] for a in members)), round(foot.area, 1), round(foot.centroid.x, 1), round(foot.centroid.y, 1))
        if key not in cache:
            tried += 1
            x0, z0, x1, z1 = foot.bounds
            S = 0.5
            xs, zs = np.arange(x0 - 8, x1 + 8.01, S), np.arange(z0 - 8, z1 + 8.01, S)
            gx, gz = np.meshgrid(xs, zs)
            dom = DOM.bilinear(gx.ravel(), gz.ravel()).reshape(gx.shape)
            dtm = DTM.bilinear(gx.ravel(), gz.ravel()).reshape(gx.shape)
            best = (0.0, 0.0)
            if not np.isnan(dom).mean() > 0.2:
                dom = np.nan_to_num(dom, nan=-50.0)
                dtm = np.nan_to_num(dtm, nan=0.0)
                even = np.abs(dom - (np.roll(dom, 2, 0) + np.roll(dom, -2, 0) + np.roll(dom, 2, 1) + np.roll(dom, -2, 1)) / 4) < 0.25
                cand = (dom - dtm > 1.8).astype(np.float32)
                even = (even & (cand > 0)).astype(np.float32)
                inside = shapely.contains_xy(foot, gx.ravel(), gz.ravel()).reshape(gx.shape)
                ring = shapely.contains_xy(foot.buffer(2.0), gx.ravel(), gz.ravel()).reshape(gx.shape) & ~inside
                jj, ii = np.nonzero(inside)
                rj, ri = np.nonzero(ring)
                if len(jj) >= 12 and len(rj) >= 8:
                    def score(dj, di):
                        return float(cand[jj + dj, ii + di].mean()), float(cand[rj + dj, ri + di].mean())
                    c0, r0 = score(0, 0)
                    top, at, cov = c0 - 0.6 * r0, (0, 0), c0
                    for dj in range(-10, 11):
                        for di in range(-10, 11):
                            c, r = score(dj, di)
                            sc = c - 0.6 * r - 0.008 * math.hypot(dj, di)
                            if sc > top:
                                top, at, cov = sc, (dj, di), c
                    # (what it is moved onto must be a roof: mostly standing, and even rather than leafy)
                    if at != (0, 0) and top - (c0 - 0.6 * r0) >= 0.14 and cov >= 0.7 and math.hypot(*at) * S >= 0.75 \
                            and float(even[jj + at[0], ii + at[1]].mean()) >= 0.4 * cov:
                        best = (at[1] * S, at[0] * S)
            cache[key] = best
        dx, dz = cache[key]
        if dx == 0.0 and dz == 0.0:
            continue
        there = shapely.affinity.translate(foot, dx, dz)
        clash = [b for b in tree.query(there, predicate="intersects").tolist() if b not in members]
        if any(there.intersection(polys[b]).area > 0.5 for b in clash):
            continue
        for a in members:
            t_, q, i_ = buildings_raw[index[a]]
            q = [(x + dx, z + dz) for x, z in q]
            buildings_raw[index[a]] = (t_, q, i_)
            d_bld.polygon(px(q), fill=255)
        moved += len(members)
    pickle.dump(cache, open(path, "wb"))
    print("  outlines moved to where the laser has the building:", moved, "(groups measured this run: %d)" % tried)


import shapely.affinity
_register_outlines()

# roads.bin (float32): per way [n, half width, kind, markings] then n x [x, z, sidewalk left, sidewalk right, height].
# Kinds: 0 road, 1 raised sidewalk, 2 zebra crossing, 3 paved path. A sidewalk stops where another road,
# a driveway or a building is in its way. The ground is graded to each road first, so that a road is level
# across and even along its length instead of following every facet of the hillside.
road_big = np.asarray(road_im)                      # 1 m per pixel
bld_big = np.asarray(bld_im)


def stations(pts, step=3.0):
    out = [pts[0]]
    for (xa, za), (xb, zb) in zip(pts, pts[1:]):
        k = max(1, int(math.ceil(math.hypot(xb - xa, zb - za) / step)))
        for q in range(1, k + 1):
            out.append((xa + (xb - xa) * q / k, za + (zb - za) * q / k))
    return out


def profile(st, half=0.0):
    """Ground height along a line of stations, evened out over about 25 m. On a road the height is
    the middle one of three across it, so a bank or a ditch beside a slightly misplaced line does not count."""
    h = []
    for i, (x, z) in enumerate(st):
        if not inside(x, z, 5):
            h.append(np.nan)
            continue
        if half < 1.5:
            h.append(height_at(x, z))
            continue
        xa, za = st[max(i - 1, 0)]
        xb, zb = st[min(i + 1, len(st) - 1)]
        ln = math.hypot(xb - xa, zb - za) or 1.0
        nx, nz = (zb - za) / ln * half * 0.6, -(xb - xa) / ln * half * 0.6
        h.append(sorted((height_at(x, z), height_at(x + nx, z + nz), height_at(x - nx, z - nz)))[1])
    h = np.array(h)
    ok = ~np.isnan(h)
    if not ok.any():
        return h
    h = np.where(ok, h, np.nanmean(h))
    k = min(4, (len(h) - 1) // 2)
    if k < 1:
        return h
    pad = np.concatenate([np.full(k, h[0]), h, np.full(k, h[-1])])
    return np.convolve(pad, np.ones(2 * k + 1) / (2 * k + 1), mode="valid")


# ---------------------------------------------------------------- rivers and streams
# Each is given a bed cut into the ground that only ever runs downhill, and a water surface a little above
# the bed; the game draws that surface as moving water (water.bin, written further down).
print("rivers…")
rivers = []           # [half width, 1 for a river, [(x, z, water level), ...]] running downstream
for kind, pts in waterways:
    st = [q for q in stations(pts, 2.0) if inside(q[0], q[1], 12)]
    if len(st) < 4:
        continue
    h = np.array([height_at(x, z) for x, z in st])
    if h[0] < h[-1]:                                       # drawn against the flow
        st, h = st[::-1], h[::-1]
    half, depth = (3.4, 0.9) if kind == "river" else (1.4, 0.55) if kind == "stream" else (0.8, 0.4)
    bed = np.minimum.accumulate(h) - depth
    pad = np.concatenate([np.full(3, bed[0]), bed, np.full(3, bed[-1])])
    bed = np.minimum.accumulate(np.convolve(pad, np.ones(7) / 7, mode="valid"))
    fade = 1.8
    reach = half + fade
    for (xa, za), (xb, zb), ba, bb, ha in zip(st, st[1:], bed, bed[1:], h):
        if ha < 0.9:
            continue                                       # at the sea
        i0, i1 = int(min(xa, xb) - reach - X0), int(max(xa, xb) + reach - X0) + 2
        j0, j1 = int(min(za, zb) - reach - Z0), int(max(za, zb) + reach - Z0) + 2
        gx = (X0 + np.arange(i0, i1))[None, :] - xa
        gz = (Z0 + np.arange(j0, j1))[:, None] - za
        dx, dz = xb - xa, zb - za
        t = np.clip((gx * dx + gz * dz) / max(dx * dx + dz * dz, 1e-9), 0.0, 1.0)
        wt = np.clip((reach - np.hypot(gx - t * dx, gz - t * dz)) / fade, 0.0, 1.0)
        wt = wt * wt * (3 - 2 * wt)
        win = H1[j0:j1, i0:i1]
        H1[j0:j1, i0:i1] = np.minimum(win, win * (1 - wt) + (ba + (bb - ba) * t) * wt)
    rivers.append([half, 1.0 if kind == "river" else 0.0, [(x, z, max(float(b) + 0.32, 0.02)) for (x, z), b in zip(st, bed)]])

# Sidewalks by one rule. The map gives them in two ways: as a mark on the road ("sidewalk on the left") and as
# lines of their own. Where a drawn line runs along a road for most of that road's length, it IS that road's
# sidewalk: the road is marked instead and the line dropped, so the walk lies against the asphalt at one width
# and is never there twice.
_sw_roads = [w for w in road_ways if w[0] == 0 and len(w[5]) >= 2 and id(w[5]) not in pedestrian_ids]
_sw_lines = [LineString(w[5]) for w in _sw_roads]
_sw_tree = shapely.STRtree(_sw_lines) if _sw_lines else None
_cover = {}                                               # (road index, side) -> [[from, to] along the road, the drawn lines]
for wi, w in enumerate(road_ways):
    if w[0] != 1 or len(w[5]) < 2 or _sw_tree is None:
        continue
    line = LineString(w[5])
    if line.length < 4.0:
        continue
    P = [line.interpolate(d) for d in np.arange(1.0, line.length, 2.0)] or [line.interpolate(0.5, normalized=True)]
    best = None
    for ri in _sw_tree.query(line.buffer(8.0)):
        rl, half = _sw_lines[ri], _sw_roads[ri][1]
        d = np.array([rl.distance(q) for q in P])
        frac = float(((d > half - 0.8) & (d < half + 4.5)).mean())
        if frac >= 0.6 and (best is None or frac > best[0]):
            best = (frac, int(ri))
    if best is None:
        continue
    ri = best[1]
    rl = _sw_lines[ri]
    mid = P[len(P) // 2]
    at = rl.project(mid)
    pa, pb = rl.interpolate(max(at - 0.5, 0.0)), rl.interpolate(min(at + 0.5, rl.length))
    left_of_xz = (pb.x - pa.x) * (mid.y - pa.y) - (pb.y - pa.y) * (mid.x - pa.x) > 0
    side_i = 4 if left_of_xz else 3                       # (left of travel is the right-hand side in (x, z) terms)
    s = sorted(rl.project(q) for q in P)
    c = _cover.setdefault((ri, side_i), [[], []])
    c[0].append((s[0], s[-1]))
    c[1].append(wi)
_drop = set()
n_sw_marked = 0
for (ri, side_i), (spans, lines_) in _cover.items():
    w = _sw_roads[ri]
    covered = unary_union([shapely.box(a, 0, b, 1) for a, b in spans]).area if spans else 0.0
    if w[side_i]:
        _drop.update(lines_)                              # there twice
    elif covered >= 0.6 * _sw_lines[ri].length:
        w[side_i] = True
        _drop.update(lines_)
        n_sw_marked += 1
road_ways = [w for wi, w in enumerate(road_ways) if wi not in _drop]
print("  drawn sidewalks taken as their road's own:", len(_drop), "roads marked:", n_sw_marked)
del _sw_roads, _sw_lines, _sw_tree, _cover, _drop
print("grading roads…")
# Every road, sidewalk and paved path is pressed into the 1 m ground: level across its width (and its
# sidewalks), following its own evened-out profile along, and blended back into the hillside beside it.
# A crossing mapped only as a point on a road gets its stripes too: straight across the road there.
_road_lines = [(LineString(w[5]), w[1]) for w in road_ways if w[0] == 0 and len(w[5]) >= 2]
_road_tree = shapely.STRtree([q[0] for q in _road_lines])
_zebra_tree = shapely.STRtree([LineString(w[5]) for w in road_ways if w[0] == 2 and len(w[5]) >= 2] or [LineString([(1e9, 1e9), (1e9 + 1, 1e9)])])
n_zebra = 0
for t, x, z in osm_nodes:
    if t.get("highway") != "crossing" or t.get("crossing") == "unmarked" or t.get("crossing:markings") == "no":
        continue
    pt = shapely.Point(x, z)
    if len(_zebra_tree.query_nearest(pt, max_distance=4.0)) or not inside(x, z, 20):
        continue
    hit = _road_tree.query_nearest(pt, max_distance=2.0)
    if not len(hit):
        continue
    line, half = _road_lines[int(hit[0])]
    s0 = line.project(pt)
    a, b = line.interpolate(max(s0 - 1.0, 0.0)), line.interpolate(min(s0 + 1.0, line.length))
    ln = math.hypot(b.x - a.x, b.y - a.y)
    if ln < 0.5:
        continue
    nx, nz = (b.y - a.y) / ln, -(b.x - a.x) / ln
    road_ways.append([2, 2.0, 0, False, False, [(x - nx * (half + 0.3), z - nz * (half + 0.3)), (x + nx * (half + 0.3), z + nz * (half + 0.3))], False])
    n_zebra += 1
print("  zebra crossings added from points:", n_zebra)

# A crossing is painted on asphalt only: each one is cut down to the stretch (or stretches, where there is
# an island or a verge in the middle) that lies on a carriageway. One that touches no road is dropped.
_carr = [LineString(w[5]).buffer(w[1], quad_segs=3) for w in road_ways
         if w[0] == 0 and w[6] and len(w[5]) >= 2 and id(w[5]) not in pedestrian_ids]
_carr += [SPoly(pts).buffer(0) for ped, pts in road_areas if not ped]
_carr = unary_union(_carr).buffer(-0.15)
shapely.prepare(_carr)
for ring in overrides.PAVED:
    road_areas.append([True, list(ring) + [ring[0]]])
for q in overrides.PORTALS:
    portals.append({"x": q["at"][0], "z": q["at"][1], "dx": q["dir"][0], "dz": q["dir"][1], "w": q["w"], "h": q["h"],
                    "rubble": False, "name": q["name"], "keep": True})


def _cells_in(poly):
    """The 1 m terrain cells inside a polygon: (j0, i0, mask)."""
    bx0, bz0, bx1, bz1 = poly.bounds
    i0, j0 = max(0, int(bx0 - X0) - 1), max(0, int(bz0 - Z0) - 1)
    i1, j1 = min(FW, int(bx1 - X0) + 2), min(FH, int(bz1 - Z0) + 2)
    im = Image.new("L", (max(1, i1 - i0), max(1, j1 - j0)), 0)
    d = ImageDraw.Draw(im)
    for g in getattr(poly, "geoms", [poly]):
        if g.geom_type == "Polygon" and not g.is_empty:
            d.polygon([(x - X0 - i0, z - Z0 - j0) for x, z in g.exterior.coords], fill=255)
    return j0, i0, np.asarray(im) > 0


# The harbour front: the mapped shore line of the town centre is a built quay, straighter and further out
# than the old shore in the terrain model. The ground behind it is filled up to quay level and paved, the
# sea in front of it is deep, and the game puts a quay wall along the line.
quays = []
QUAY_Y = 1.5
_win = shapely.box(*overrides.QUAY_BOX)
for pts in coasts:
    line = LineString(pts).intersection(_win)
    for g in getattr(line, "geoms", [line]):
        if g.geom_type != "LineString" or g.length < 8:
            continue
        g = g.simplify(0.3)
        mean = []
        for d in (14.0, -14.0):
            j0, i0, m = _cells_in(g.buffer(d, single_sided=True))
            sub = H1[j0:j0 + m.shape[0], i0:i0 + m.shape[1]]
            mean.append(float(sub[m].mean()) if m.any() else -9.0)
        sgn = 1.0 if mean[0] > mean[1] else -1.0             # which side of the line the land is on
        land = g.buffer(sgn * 60.0, single_sided=True)
        j0, i0, m = _cells_in(land)
        sub = H1[j0:j0 + m.shape[0], i0:i0 + m.shape[1]]
        sub[m & (sub < QUAY_Y)] = QUAY_Y
        water = g.buffer(-sgn * 14.0, single_sided=True).difference(land.buffer(0.6))
        j0, i0, m = _cells_in(water)
        sub = H1[j0:j0 + m.shape[0], i0:i0 + m.shape[1]]
        sub[m] = np.minimum(sub[m], -3.0)
        strip = g.buffer(sgn * 16.0, single_sided=True)
        for part in getattr(strip, "geoms", [strip]):
            if part.geom_type == "Polygon" and part.area > 20:
                road_areas.append([True, list(part.exterior.coords)])
        co = list(g.coords)
        for (ax, az), (bx, bz) in zip(co, co[1:]):
            ln = math.hypot(bx - ax, bz - az)
            if ln < 0.3:
                continue
            nx, nz = (bz - az) / ln, -(bx - ax) / ln
            mx, mz = (ax + bx) / 2, (az + bz) / 2
            if land.contains(shapely.Point(mx + nx * 2.0, mz + nz * 2.0)):
                nx, nz = -nx, -nz
            quays.append([round(ax, 2), round(az, 2), round(bx, 2), round(bz, 2), round(nx, 4), round(nz, 4)])
print("  quay front:", round(sum(math.hypot(q[2] - q[0], q[3] - q[1]) for q in quays)), "m")

# Molde idrettspark: level ground, the track and the pitch, and its stands (built by the game from these numbers)
sports = {}
_sp = overrides.SPORTS
if _sp["track"] in wanted:
    tr = wanted[_sp["track"]]
    level = level_site(tr, None, 12)
    loop = stations(tr, 3.0)
    if math.dist(loop[0], loop[-1]) < 1.0:
        loop = loop[:-1]
    sports = {"level": round(level, 2), "half": 3.7, "track": [round(v, 2) for q in loop for v in q], "stands": []}

    def _rect(ring):
        r = list(SPoly(ring).minimum_rotated_rectangle.exterior.coords)[:4]
        c = np.mean(r, 0)
        e0, e1 = np.subtract(r[1], r[0]), np.subtract(r[2], r[1])
        if np.hypot(*e0) < np.hypot(*e1):
            e0, e1 = e1, e0
        return c, e0 / np.hypot(*e0), float(np.hypot(*e0)) / 2, float(np.hypot(*e1)) / 2

    tc, tu, thl, thw = _rect(tr)
    pc = tc
    if _sp["pitch"] in wanted:
        pc, pu, phl, phw = _rect(wanted[_sp["pitch"]])
        sports["pitch"] = [round(float(pc[0]), 2), round(float(pc[1]), 2), round(float(pu[0]), 4), round(float(pu[1]), 4), round(min(phl, 52.5), 1), round(min(phw, 34.0), 1)]
    if _sp["tribune"] in wanted:
        bc, bu, bhl, bhw = _rect(wanted[_sp["tribune"]])
        back = np.array([-bu[1], bu[0]])
        if (bc - pc) @ back < 0:
            back = -back
        rows = 11
        front = bc - back * bhw
        sports["stands"].append([round(float(front[0]), 2), round(float(front[1]), 2), round(float(bu[0]), 4), round(float(bu[1]), 4),
                                 round(float(back[0]), 4), round(float(back[1]), 4), round(2 * bhl - 2.0, 1), rows, 1,
                                 round(height_at(float(front[0]), float(front[1])), 2), round(max(0.0, 2 * bhw - rows * 0.85), 1)])
        level_site(wanted[_sp["tribune"]], height_at(float(front[0]), float(front[1])), 3)
    tv = np.array([-tu[1], tu[0]])
    for sx, sz in _sp["stands"]:
        q = np.array([sx, sz]) - tc
        side = 1.0 if q @ tv > 0 else -1.0
        front = tc + tu * float(q @ tu) + tv * side * (thw + 3.7 + 2.0)
        sports["stands"].append([round(float(front[0]), 2), round(float(front[1]), 2), round(float(tu[0]), 4), round(float(tu[1]), 4),
                                 round(float(tv[0] * side), 4), round(float(tv[1] * side), 4), 30.0, 5, 0, round(level, 2), 0.0])
    sports_clear = SPoly(tr).buffer(16.0)
else:
    sports_clear = None

# Football pitches: level ground, and for the game the pitch itself (centre, direction, half length and width)
# and any stand beside it. A full-size pitch is at most 105 by 68 m; a mapped outline is often the whole ground.
fields = []
_replaced = {q["way"]: q for q in overrides.PITCH_AT}
for wid, pts in pitch_ways:
    poly = SPoly(pts)
    if not poly.is_valid or poly.area < 500:
        continue
    r = list(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    c = np.mean(r, 0)
    e0, e1 = np.subtract(r[1], r[0]), np.subtract(r[2], r[1])
    if np.hypot(*e0) < np.hypot(*e1):
        e0, e1 = e1, e0
    u = e0 / np.hypot(*e0)
    hl, hw = min(float(np.hypot(*e0)) / 2 - 1.0, 52.5), min(float(np.hypot(*e1)) / 2 - 1.0, 34.0)
    if wid in _replaced:
        c = np.array(_replaced[wid]["at"])
        hl, hw = _replaced[wid]["half"]
    if hl < 8 or hw < 5:
        continue
    level = level_site(pts, None, 3)
    f = {"outline": pts, "level": round(level, 2), "pitch": [round(float(c[0]), 2), round(float(c[1]), 2), round(float(u[0]), 4), round(float(u[1]), 4), round(hl, 1), round(hw, 1)], "stands": []}
    for sd in overrides.STANDS:
        if sd["way"] == wid:
            v = np.array([-u[1], u[0]])
            if (np.array(sd["toward"]) - c) @ v < 0:
                v = -v
            front = c + v * (hw + 3.0)
            f["stands"].append([round(float(front[0]), 2), round(float(front[1]), 2), round(float(u[0]), 4), round(float(u[1]), 4),
                                round(float(v[0]), 4), round(float(v[1]), 4), sd["length"], sd["rows"], 1, round(level, 2), 0.0])
    fields.append(f)
# volleyball courts: sand, lines and a net (centre, direction, half length, half width, level)
courts = []
for pts in court_ways:
    poly = SPoly(pts)
    if not poly.is_valid or poly.area < 60:
        continue
    r = list(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    c = np.mean(r, 0)
    e0, e1 = np.subtract(r[1], r[0]), np.subtract(r[2], r[1])
    if np.hypot(*e0) < np.hypot(*e1):
        e0, e1 = e1, e0
    u = e0 / np.hypot(*e0)
    courts.append([round(float(c[0]), 2), round(float(c[1]), 2), round(float(u[0]), 4), round(float(u[1]), 4),
                   round(min(float(np.hypot(*e0)) / 2, 9.0), 1), round(min(float(np.hypot(*e1)) / 2, 4.5), 1), round(level_site(pts, None, 2), 2)])
# no path runs across a pitch or a court: the ones the map draws over them (short cuts worn across a gravel
# ground) are left out
_play = [SPoly(f["outline"]) for f in fields] + [SPoly(q) for q in court_ways]
_play = unary_union(_play).buffer(0.5) if _play else None
if _play is not None:
    _keep = []
    for w in road_ways:
        if w[0] in (3, 7) and len(w[5]) >= 2:
            ln = LineString(w[5])
            if ln.intersection(_play).length > 0.5 * ln.length:
                continue
        _keep.append(w)
    print("  paths across pitches left out:", len(road_ways) - len(_keep))
    road_ways = _keep
for f in fields:
    del f["outline"]
print("  football pitches:", len(fields), "volleyball courts:", len(courts))

# Rådhusplassen is one paved floor from wall to wall: the footpaths the map draws across it are not there,
# and the steps in the alleys beside the town hall are as wide as the alleys.
plaza_poly = SPoly(list(zip(plaza[0::2], plaza[1::2]))).buffer(0) if plaza else None
if plaza_poly is not None:
    _reach = plaza_poly.buffer(22.0)
    _near_b = [SPoly(q) for _t, q, _i in buildings_raw if len(q) >= 3 and SPoly(q).is_valid and SPoly(q).distance(plaza_poly) < 40]
    _near_u = unary_union(_near_b)
    _keep = []
    for w in road_ways:
        if w[0] in (3, 7) and len(w[5]) >= 2:
            ln = LineString(w[5])
            if ln.intersection(_reach).length > 0.6 * ln.length:
                continue
        if w[0] == 8 and len(w[5]) >= 2 and LineString(w[5]).distance(plaza_poly) < 25:
            w[1] = float(np.clip(min(_near_u.distance(shapely.Point(q)) for q in w[5]) - 0.05, 1.0, 6.0))
        _keep.append(w)
    road_ways = _keep
_carr_wide = _carr.buffer(0.2)
_ways, n_cut, n_gone = [], 0, 0
for w in road_ways:
    if w[0] != 2 or len(w[5]) < 2:
        _ways.append(w)
        continue
    line = LineString(w[5])
    on = line.intersection(_carr)
    parts = [g for g in getattr(on, "geoms", [on]) if g.geom_type == "LineString" and g.length >= 1.5]
    if len(parts) == 1 and parts[0].length > line.length - 0.05:
        _ways.append(w)
        continue
    n_cut += 1 if parts else 0
    n_gone += 0 if parts else 1
    for g in parts:
        _ways.append([2, w[1], w[2], w[3], w[4], [(float(x), float(z)) for x, z in g.coords], w[6]])
    off = line.difference(_carr_wide)                  # what is left of it beside the road is footpath
    for g in getattr(off, "geoms", [off]):
        if g.geom_type == "LineString" and g.length >= 0.4:
            _ways.append([3, 1.1, 0, False, False, [(float(x), float(z)) for x, z in g.coords], False])
road_ways = _ways
# one crossing, one set of bars: a crossing lying on another (mapped twice, or as a line and as a point) goes
_zk, _zdrop = [], set()
for wi, w in enumerate(road_ways):
    if w[0] != 2 or len(w[5]) < 2:
        continue
    zl = LineString(w[5])
    if any(zl.distance(o) < 1.6 and zl.interpolate(0.5, normalized=True).distance(o) < 2.5 for o in _zk):
        _zdrop.add(wi)
    else:
        _zk.append(zl)
road_ways = [w for wi, w in enumerate(road_ways) if wi not in _zdrop]
print("  crossings trimmed to the asphalt:", n_cut, "dropped (no road under them):", n_gone, "lying on another:", len(_zdrop))
road_st = [stations(w[5]) for w in road_ways]
road_h = [profile(st, w[1] if w[0] == 0 else 0.0) for w, st in zip(road_ways, road_st)]
w_sum = np.zeros((FH, FW), np.float32)
hw_sum = np.zeros((FH, FW), np.float32)
w_max = np.zeros((FH, FW), np.float32)
for w, st, hs in zip(road_ways, road_st, road_h):
    kind = w[0]
    if kind == 2 or (kind == 0 and not w[6]):
        continue
    if kind == 0:
        flat, fade = w[1] + 0.5 + (2.3 if (w[3] or w[4]) else 0.0), 3.0
    elif kind in (7, 8):
        flat, fade = w[1] + 0.15, 1.2
    else:
        flat, fade = w[1] + 0.3, 1.8
    reach = flat + fade
    for (xa, za), (xb, zb), ha, hb in zip(st, st[1:], hs, hs[1:]):
        if np.isnan(ha) or np.isnan(hb) or min(ha, hb) < 0.6 or not inside(xa, za, 25) or not inside(xb, zb, 25):
            continue
        i0, i1 = int(min(xa, xb) - reach - X0), int(max(xa, xb) + reach - X0) + 2
        j0, j1 = int(min(za, zb) - reach - Z0), int(max(za, zb) + reach - Z0) + 2
        gx = (X0 + np.arange(i0, i1))[None, :] - xa
        gz = (Z0 + np.arange(j0, j1))[:, None] - za
        dx, dz = xb - xa, zb - za
        t = np.clip((gx * dx + gz * dz) / max(dx * dx + dz * dz, 1e-9), 0.0, 1.0)
        d = np.hypot(gx - t * dx, gz - t * dz)
        wt = np.clip((reach - d) / fade, 0.0, 1.0)
        wt = (wt * wt * (3 - 2 * wt)).astype(np.float32)
        w_sum[j0:j1, i0:i1] += wt
        hw_sum[j0:j1, i0:i1] += wt * (ha + (hb - ha) * t)
        np.maximum(w_max[j0:j1, i0:i1], wt, out=w_max[j0:j1, i0:i1])
grade = (w_sum > 0) & (H1 > 0.5)
H1 = np.where(grade, H1 * (1 - w_max) + hw_sum / np.maximum(w_sum, 1e-6) * w_max, H1).astype(np.float32)
graded = w_max >= 0.98                                    # the ground here is a road's own, level across
del w_sum, hw_sum, w_max, grade

# Where three or more stretches of road meet is a junction; lane markings stop short of it.
from scipy.spatial import cKDTree
_deg = {}
for w in road_ways:
    if w[0] == 0:
        for i, q in enumerate(w[5]):
            key = (round(q[0], 2), round(q[1], 2))
            _deg[key] = _deg.get(key, 0) + (1 if i in (0, len(w[5]) - 1) else 2)
_junctions = [k for k, d in _deg.items() if d >= 3]
junction_tree = cKDTree(_junctions) if _junctions else None

road_out = []
n_ways = n_stations = 0
# No line is painted where the edge of a road runs on another road's asphalt (two carriageways running
# together before a roundabout, a slip road joining): there the lines would cross each other's lanes.
_rw = [w for w in road_ways if w[0] == 0 and len(w[5]) >= 2]
_rlines = [LineString(w[5]) for w in _rw]
_rtree = shapely.STRtree(_rlines)
_rhalf = np.array([w[1] for w in _rw])
_rindex = {id(w[5]): k for k, w in enumerate(_rw)}
for (kind, half, mark, left, right, pts, _burn), st, hs in zip(road_ways, road_st, road_h):
    rows = []
    near = junction_tree.query(st)[0] if (junction_tree is not None and kind == 0) else np.full(len(st), 1e9)
    shared = np.zeros(len(st), bool)
    if kind == 0 and mark and len(st) >= 2:
        S = np.asarray(st)
        Tn = np.gradient(S, axis=0)
        Tn /= np.maximum(np.hypot(Tn[:, 0], Tn[:, 1]), 1e-6)[:, None]
        Nn = np.stack([Tn[:, 1], -Tn[:, 0]], 1)
        me = _rindex.get(id(pts), -1)
        for sgn in (1.0, -1.0):
            P = shapely.points(S + Nn * sgn * (half - 0.2))
            a_, b_ = _rtree.query(P, predicate="dwithin", distance=float(_rhalf.max()))
            if len(a_):
                d_ = shapely.distance(P[a_], np.asarray(_rlines, dtype=object)[b_])
                bad = (d_ < _rhalf[b_] - 0.4) & (b_ != me)
                shared[a_[bad]] = True
        if shared.any():
            shared = np.convolve(shared.astype(float), np.ones(5), "same") > 0
    for i, (x, z) in enumerate(st):
        ok = inside(x, z, 5) and height_at(x, z) > 0.3 and not (kind in (1, 7, 8) and road_big[int((z - Z0) * SS / MASK_RES), int((x - X0) * SS / MASK_RES)])
        bare = any(math.hypot(x - qx, z - qz) < qr for qx, qz, qr in overrides.NO_MARKINGS)       # a place without road paint
        if bare and kind == 2:
            ok = False
        rows.append((ok, x, z, float(near[i] > half + 7.0 and not shared[i] and not bare), 0.0, float(hs[i])))
    run = []
    for row in rows + [(False, 0, 0, 0, 0, 0)]:            # split where the way leaves the map or is interrupted
        if row[0]:
            run.append(row[1:])
            continue
        if len(run) >= 2:
            road_out.extend([float(len(run)), half, float(kind), float(mark)])
            for r in run:
                road_out.extend(r)
            n_ways += 1
            n_stations += len(run)
        run = []

# Bridges (kind 4): stretches that belong together are joined end to end, and the deck runs straight from
# the ground at one end to the ground at the other.
_chains = [[b[0], b[1], list(b[2])] for b in bridges]
_merged = True
while _merged:
    _merged = False
    for i in range(len(_chains)):
        for j in range(len(_chains)):
            if i == j or _chains[i] is None or _chains[j] is None:
                continue
            a, b = _chains[i], _chains[j]
            if math.dist(a[2][-1], b[2][0]) < 0.05:
                a[2] += b[2][1:]
            elif math.dist(a[2][-1], b[2][-1]) < 0.05:
                a[2] += b[2][-2::-1]
            elif math.dist(a[2][0], b[2][0]) < 0.05:
                a[2] = b[2][:0:-1] + a[2]
            else:
                continue
            a[0] = max(a[0], b[0])
            _chains[j] = None
            _merged = True
# A footbridge lying right alongside a road bridge is not a bridge of its own: it is that bridge's sidewalk.
# The road deck is widened to take it in and the footbridge is left out. Other footbridges near a road are
# concrete, with concrete parapets (mark 9); only those out in the terrain are timber.
_road_decks = [c for c in _chains if c is not None and c[0] > 2.0 and len(c[2]) >= 2]
_town_roads = unary_union([LineString(w[5]) for w in road_ways if w[0] == 0 and len(w[5]) >= 2])
n_absorbed = 0
_road_half0 = {id(c): c[0] for c in _road_decks}
for k, c in enumerate(_chains):
    if c is None or c[0] > 2.0 or len(c[2]) < 2:
        continue
    line = LineString(c[2])
    for r in _road_decks:
        rl = LineString(r[2])
        near = line.intersection(rl.buffer(r[0] + 2 * c[0] + 1.5)).length
        if near > 0.6 * line.length:
            r[0] = max(r[0], max(rl.distance(shapely.Point(q)) for q in c[2]) + c[0])
            # which side of the road it lies on (left of the road's direction is positive): the deck grows that way only
            if len(r) == 3:
                r += [-_road_half0[id(r)], _road_half0[id(r)]]
            for q in c[2]:
                at = rl.project(shapely.Point(q))
                pa, pb = rl.interpolate(max(at - 0.5, 0.0)), rl.interpolate(min(at + 0.5, rl.length))
                side_ = (pb.x - pa.x) * (q[1] - pa.y) - (pb.y - pa.y) * (q[0] - pa.x)
                d_ = rl.distance(shapely.Point(q)) * (1.0 if side_ > 0 else -1.0)
                r[3], r[4] = min(r[3], d_ - c[0]), max(r[4], d_ + c[0])
            _chains[k] = None
            n_absorbed += 1
            break
    else:
        if line.distance(_town_roads) < 30.0:
            c[1] = 9
# A road deck reaches a few metres past the map's bridge at each end, so that it covers the whole cut the
# stream makes through the road; and a short bridge in town has concrete parapets (16 added to its markings).
for c in _chains:
    if c is None or c[0] <= 2.0 or len(c[2]) < 2:
        continue
    length = LineString(c[2]).length
    # another road joining at the bridge: then it is left as the map has it, neither longer nor walled in,
    # or the deck and its parapets would stand across the side road
    _own = LineString(c[2])
    _along = np.subtract(c[2][-1], c[2][0]) / max(math.dist(c[2][-1], c[2][0]), 1e-6)

    def _crosses(w):
        """Does this road come up to the bridge from the side? Judged by the way it runs where it is nearest."""
        wl = LineString(w[5])
        if wl.distance(_own) >= c[0] + w[1] + 6.0:
            return False
        at = wl.project(shapely.ops.nearest_points(wl, _own)[0])
        qa, qb = wl.interpolate(max(at - 4.0, 0.0)), wl.interpolate(min(at + 4.0, wl.length))
        ln_ = math.hypot(qb.x - qa.x, qb.y - qa.y)
        return ln_ > 0.5 and abs(np.dot([(qb.x - qa.x) / ln_, (qb.y - qa.y) / ln_], _along)) < 0.8

    joined = any(w[0] == 0 and len(w[5]) >= 2 and not any(math.dist(q0, q1) < 0.5 for q0 in (w[5][0], w[5][-1]) for q1 in (c[2][0], c[2][-1]))
                 and _crosses(w) for w in road_ways)
    if joined:
        continue
    for end in (0, -1):
        a, b = np.array(c[2][end]), np.array(c[2][1 if end == 0 else -2])
        d = (a - b) / max(float(np.hypot(*(a - b))), 1e-6)
        q = a + d * 5.0
        if inside(q[0], q[1], 8):
            if end == 0:
                c[2].insert(0, (float(q[0]), float(q[1])))
            else:
                c[2].append((float(q[0]), float(q[1])))
    if length < 45.0:
        c[1] = int(c[1]) % 16 + 16
print("  footbridges taken into the road bridge beside them:", n_absorbed)
# A deck that took in a footbridge on one side only is not widened on the other: its line moves over to the
# middle of what it carries (and the yellow line, which would no longer be in the middle of the road, is left out).
for c in _chains:
    if c is None or len(c) < 5:
        continue
    lo, hi = c[3], c[4]
    del c[3:]
    if abs(lo + hi) / 2 > 0.3:
        moved = LineString(c[2]).offset_curve((lo + hi) / 2)
        if moved.geom_type == "LineString" and len(moved.coords) >= 2:
            pts_ = [(float(x), float(z)) for x, z in moved.coords]
            if math.dist(pts_[0], c[2][0]) > math.dist(pts_[-1], c[2][0]):
                pts_.reverse()
            c[2], c[0] = pts_, (hi - lo) / 2
            c[1] = (int(c[1]) // 16) * 16
# Where a road must give way — it runs into a wider road, or into a roundabout — a row of white triangles is
# painted across its lane (kind 6: from the middle of the road, or its left edge if one-way, to its right edge).
round_keys = {(round(q[0], 2), round(q[1], 2)) for pts, _h in round_lines for q in pts}
round_ids = {id(pts) for pts, _h in round_lines}
_widest = {}
_names_at = {}
_speeds_at = {}
for w in road_ways:
    if w[0] == 0:
        tg = tags_of.get(id(w[5]), {})
        for q in (w[5][0], w[5][-1]) if id(w[5]) not in round_ids else w[5]:
            key = (round(q[0], 2), round(q[1], 2))
            _widest[key] = max(_widest.get(key, 0.0), w[1])
            if tg.get("name"):
                _names_at.setdefault(key, set()).add(tg["name"])
            if tg.get("maxspeed", "").isdigit():
                _speeds_at.setdefault(key, set()).add(int(tg["maxspeed"]))
        for q in w[5][1:-1]:                                   # a road passing straight through a junction counts too
            key = (round(q[0], 2), round(q[1], 2))
            if _deg.get(key, 0) >= 3:
                _widest[key] = max(_widest.get(key, 0.0), w[1])
                if tg.get("name"):
                    _names_at.setdefault(key, set()).add(tg["name"])
_zebras_now = shapely.STRtree([LineString(w[5]) for w in road_ways if w[0] == 2 and len(w[5]) >= 2] or [LineString([(1e9, 1e9), (1e9 + 1, 1e9)])])
approaches = []       # every road end at a junction: [end, direction of travel toward it, half width, how far back the line is, tags, kind of duty]
for w in road_ways:
    if w[0] != 0 or len(w[5]) < 2 or id(w[5]) in round_ids:
        continue
    tg = tags_of.get(id(w[5]), {})
    for end, nxt, leaving in ((w[5][0], w[5][1], True), (w[5][-1], w[5][-2], False)):
        key = (round(end[0], 2), round(end[1], 2))
        if _deg.get(key, 0) < 3:
            continue
        dx, dz = end[0] - nxt[0], end[1] - nxt[1]
        ln = math.hypot(dx, dz)
        if ln < 4.0:
            continue
        dx, dz = dx / ln, dz / ln
        widest = _widest.get(key, w[1])
        back = min(ln, widest + 1.6)
        oneway = tg.get("oneway") == "yes"
        duty = 0
        if not (oneway and leaving):                           # traffic does arrive this way
            if key in round_keys:
                duty = 2
            elif widest > w[1] + 0.2 and w[1] > 1.8:
                duty = 1
        approaches.append([end, (dx, dz), w[1], back, tg, duty, oneway, key])
        if duty and height_at(*end) > 0.6:
            bx, bz = end[0] - dx * back, end[1] - dz * back
            rx, rz = -dz, dx                                    # to the right of travel
            lo = -w[1] + 0.3 if oneway else 0.15
            pa, pb = (bx + rx * lo, bz + rz * lo), (bx + rx * (w[1] - 0.3), bz + rz * (w[1] - 0.3))
            # (not where a pedestrian crossing lies: its bars and the triangles would be painted into each other)
            if inside(pa[0], pa[1], 10) and inside(pb[0], pb[1], 10) and not any(math.hypot(pa[0] - qx, pa[1] - qz) < qr for qx, qz, qr in overrides.NO_MARKINGS) \
                    and not len(_zebras_now.query(LineString([pa, pb]), predicate="dwithin", distance=2.6)):
                road_out.extend([2.0, 0.3, 6.0, 0.0, pa[0], pa[1], 0.0, 0.0, height_at(*pa), pb[0], pb[1], 0.0, 0.0, height_at(*pb)])

for pts in runways:                                       # kind 5: a runway's paint
    st = [q for q in stations(pts, 10.0) if inside(q[0], q[1], 30)]
    if len(st) >= 2:
        road_out.extend([float(len(st)), 22.5, 5.0, 0.0])
        for x, z in st:
            road_out.extend([x, z, 0.0, 0.0, height_at(x, z)])
# Nothing comes up through a road deck. The ground under it is held at or below the deck (well below, away
# from its edges), so that no bank, road or kerb the deck spans stands up through the asphalt; further down,
# the sidewalks stop at the deck and the stream under it is kept below it.
def _deck_height(st, hs, x, z):
    """Height of a deck (stations and their heights) at the points x, z: that of the nearest spot on its line."""
    best = np.full(np.shape(x), 1e18)
    out = np.zeros(np.shape(x))
    for (xa, za), (xb, zb), ya, yb in zip(st, st[1:], hs, hs[1:]):
        dx, dz = xb - xa, zb - za
        t = np.clip(((x - xa) * dx + (z - za) * dz) / max(dx * dx + dz * dz, 1e-9), 0.0, 1.0)
        d = (x - xa - t * dx) ** 2 + (z - za - t * dz) ** 2
        near = d < best
        best = np.where(near, d, best)
        out = np.where(near, ya + (yb - ya) * t, out)
    return out


road_decks = []       # [stations, their heights, the deck's outline and a bit, half width] of every road bridge
_deck_ends = {}
for ch in _chains:
    if ch is None:
        continue
    st = stations(ch[2], 3.0)
    if len(st) < 2 or not all(inside(x, z, 5) for x, z in st):
        continue
    ha, hb = max(height_at(*st[0]), 0.6), max(height_at(*st[-1]), 0.6)
    _deck_ends[id(ch)] = (ha, hb)
    if ch[0] > 2.0:
        road_decks.append([st, [ha + (hb - ha) * i / (len(st) - 1) for i in range(len(st))], None, ch[0]])
for dk in road_decks:
    st, hs, _none, half = dk
    line = LineString(st)
    dk[2] = line.buffer(half + 1.0, cap_style="flat")
    inner = shapely.ops.substring(line, 1.5, line.length - 1.5).buffer(half - 1.5, cap_style="flat") if line.length > 4.0 and half > 2.0 else None
    x0, z0, x1, z1 = dk[2].bounds
    i0, i1, j0, j1 = int(x0 - X0), int(x1 - X0) + 2, int(z0 - Z0), int(z1 - Z0) + 2
    gx, gz = np.meshgrid(X0 + np.arange(i0, i1, dtype=float), Z0 + np.arange(j0, j1, dtype=float))
    top = _deck_height(st, hs, gx, gz)
    limit = np.where(shapely.contains_xy(dk[2], gx, gz), top - 0.05, 1e9)
    if inner is not None and not inner.is_empty:
        limit = np.where(shapely.contains_xy(inner, gx, gz), top - 0.6, limit)
    was = H1[j0:j1, i0:i1].copy()
    win = np.where(was > 0.5, np.minimum(was, np.maximum(limit, 0.5)), was)
    # paint on the road that carries on onto the deck (a crossing, give-way marks) lies on the deck: there the
    # ground is brought right up under it, if it was about that high already (not where the deck is in the air)
    _paint = [LineString(w[5]).buffer(2.5) for w in road_ways if w[0] in (2, 6) and len(w[5]) >= 2 and LineString(w[5]).intersects(dk[2])]
    if _paint:
        on = shapely.contains_xy(unary_union(_paint).intersection(line.buffer(half + 0.3, cap_style="flat")), gx, gz)
        win = np.where(on & (was > top - 0.2), top, win)
    H1[j0:j1, i0:i1] = win.astype(np.float32)
print("  road decks with the ground held under them:", len(road_decks))
n_bridges = 0
# Decks lying side by side (a road bridge and the footbridge next to it) get no railing between them:
# the third number of a deck point says which sides are open (1 = left of travel, 2 = right, 3 = both).
_decks = [(ch, LineString(ch[2]).buffer(ch[0] + 0.3, cap_style="flat")) for ch in _chains if ch is not None and len(ch[2]) >= 2]
_deck_tree = shapely.STRtree([g for _c, g in _decks])
for ch in _chains:
    if ch is None:
        continue
    st = stations(ch[2], 3.0)
    if len(st) < 2 or not all(inside(x, z, 5) for x, z in st):
        continue
    ha, hb = _deck_ends[id(ch)]
    road_out.extend([float(len(st)), ch[0], 4.0, float(ch[1])])
    for i, (x, z) in enumerate(st):
        (xa, za), (xb, zb) = st[max(i - 1, 0)], st[min(i + 1, len(st) - 1)]
        ln = math.hypot(xb - xa, zb - za) or 1.0
        ox, oz = (zb - za) / ln, -(xb - xa) / ln                # to the left of travel, as the game has it
        open_ = 0
        for bit, sgn in ((1, 1.0), (2, -1.0)):
            pt = shapely.Point(x + ox * sgn * (ch[0] + 0.9), z + oz * sgn * (ch[0] + 0.9))
            if any(_decks[j][0] is not ch for j in _deck_tree.query(pt, predicate="within")):
                open_ |= bit
        road_out.extend([x, z, float(open_), 0.0, ha + (hb - ha) * i / (len(st) - 1)])
    n_bridges += 1
np.asarray(road_out, np.float32).tofile(os.path.join(OUT, "roads.bin"))
print("  road ribbons:", n_ways, "stations:", n_stations, "bridges:", n_bridges)

# ---------------------------------------------------------------- paved surfaces
# All road ribbons are melted into one outline, with the inner corners at junctions rounded off, and
# the sidewalks into another (from the sidewalk tags, the sidewalks drawn as lines of their own and the
# pedestrian squares). A sidewalk carries on across a driveway. Both are cut into triangles per 100 m
# cell; the game lays them on the ground. paved.bin (float32): per cell [cell x, cell z, number of
# asphalt triangles, sidewalk triangles, kerb pieces, shoulder pieces], then the triangles (x, z three
# times each) and the pieces (x, z, x, z; the open side is to the right of the direction).
print("paved areas…")
_all, _main, _side = [], [], []
for kind, half, mark, left, right, pts, burn in road_ways:
    if len(pts) < 2 or not burn and kind == 0:
        continue
    line = LineString(pts)
    if kind == 0 and half == 3.0 and mark == 0 and not left and not right and id(pts) in pedestrian_ids:
        _side.append(line.buffer(half, quad_segs=3))                      # a pedestrian street: slabs, not asphalt
    elif kind == 0:
        rib = line.buffer(half, quad_segs=3)
        _all.append(rib)
        if half > 1.8:
            _main.append(rib)
        if left:                                          # left of travel is the right-hand side in (x, z) terms
            _side.append(line.buffer(-(half + 2.0), single_sided=True, quad_segs=2).buffer(0))
        if right:
            _side.append(line.buffer(half + 2.0, single_sided=True, quad_segs=2).buffer(0))
    elif kind == 1:
        _side.append(line.buffer(1.0, quad_segs=2, cap_style="flat"))     # two metres wide, as beside a road
# the island in the middle of a roundabout: a kerbed ring of paving, grass inside it
if round_lines:
    for ring in polygonize(unary_union([LineString(pts) for pts, _h in round_lines])):
        half = max(h for pts, h in round_lines if ring.buffer(0.5).intersects(LineString(pts)))
        island = ring.buffer(-(half + 0.2))
        if not island.is_empty and island.area > 6.0:
            core = island.buffer(-1.3)
            _side.append(island.difference(core) if not core.is_empty else island)
for ped, pts in road_areas:
    poly = SPoly(pts).buffer(0)
    (_side if ped else _all).append(poly)
    if not ped:
        _main.append(poly)
_drive = list(_all)                                        # where cars drive: the roads, not the car parks
for pts in parkings:
    _all.append(SPoly(pts).buffer(0))
# No building stands in a road. Where the map has one reaching into the driving lane (a garage drawn a few
# metres off, mostly), it is trimmed back to the roadside, or taken
# away if less than about half of it would be left.
_core = unary_union([LineString(w[5]).buffer(w[1] + 0.3, quad_segs=3) for w in road_ways
                     if w[0] == 0 and w[6] and len(w[5]) >= 2 and id(w[5]) not in pedestrian_ids])
_core_wide = _core.buffer(0.3)
shapely.prepare(_core)
# buildings that stand wall to wall with their neighbours, where the map leaves a gap: the gap is filled
_joined = {i for i, v in overrides.BUILDINGS.items() if v.get("join")}
if _joined:
    _all_b = [(i, SPoly(q)) for _t0, q, i in buildings_raw if len(q) >= 3]
    for k, (_t0, q, i) in enumerate(buildings_raw):
        if i not in _joined:
            continue
        me = SPoly(q)
        grown = me
        for j, other in _all_b:
            d = me.distance(other)
            if j != i and other.is_valid and 0.0 < d < 6.0:
                gap = me.buffer(d + 0.4).intersection(other.buffer(d + 0.4)).convex_hull.difference(other)
                grown = grown.union(gap)
        grown = grown.buffer(0.3, join_style="mitre").buffer(-0.3, join_style="mitre")
        grown = max(getattr(grown, "geoms", [grown]), key=lambda g: g.area)
        buildings_raw[k] = (_t0, [(float(x), float(z)) for x, z in grown.simplify(0.2).exterior.coords[:-1]], i)
# sidewalks count as road for a small building (a garage or shed drawn a metre into the pavement)
_walks_sw = []
for w in road_ways:
    if w[0] == 0 and w[6] and len(w[5]) >= 2 and (w[3] or w[4]) and id(w[5]) not in pedestrian_ids:
        ln_ = LineString(w[5])
        if w[3]:
            _walks_sw.append(ln_.buffer(-(w[1] + 2.0), single_sided=True).buffer(0))
        if w[4]:
            _walks_sw.append(ln_.buffer(w[1] + 2.0, single_sided=True).buffer(0))
_core_sw = _core.union(unary_union(_walks_sw)) if _walks_sw else _core
_core_sw_wide = _core_sw.buffer(0.2)
shapely.prepare(_core_sw)
_kept, n_bgone, n_btrim = [], 0, 0
for _t, _pts, _id in buildings_raw:
    poly = SPoly(_pts)
    if len(_pts) >= 3 and poly.is_valid and poly.area < 60 and shapely.intersects(_core_sw, poly) and poly.intersection(_core_sw).area > 0.15:
        rest = poly.difference(_core_sw_wide).buffer(-0.4).buffer(0.4, join_style="mitre")
        rest = max(getattr(rest, "geoms", [rest]), key=lambda g: g.area) if not rest.is_empty else rest
        if rest.is_empty or rest.geom_type != "Polygon" or rest.area < 0.55 * poly.area or rest.area < 8 or rest.buffer(-1.1).is_empty:
            n_bgone += 1                                   # (a strip under 2.2 m wide is no building)
        else:
            _kept.append((_t, [(float(x), float(z)) for x, z in rest.simplify(0.2).exterior.coords[:-1]], _id))
            n_btrim += 1
        continue
    if len(_pts) < 3 or not poly.is_valid or not shapely.intersects(_core, poly):
        _kept.append((_t, _pts, _id))
        continue
    over = poly.intersection(_core).area
    if over < 0.15:
        _kept.append((_t, _pts, _id))
        continue
    rest = poly.difference(_core_wide).buffer(-0.4).buffer(0.4, join_style="mitre")
    rest = max(getattr(rest, "geoms", [rest]), key=lambda g: g.area) if not rest.is_empty else rest
    if rest.is_empty or rest.geom_type != "Polygon" or rest.area < 0.55 * poly.area or rest.area < 10 or rest.buffer(-1.1).is_empty:
        n_bgone += 1
        continue
    _kept.append((_t, [(float(x), float(z)) for x, z in rest.simplify(0.2).exterior.coords[:-1]], _id))
    n_btrim += 1
buildings_raw = _kept
print("  buildings in a road: removed", n_bgone, "trimmed", n_btrim)
# No two buildings stand in each other: one that lies mostly inside another (a part drawn twice) is left out,
# and where two merely overlap the smaller gives way.
_bp = [SPoly(q) if len(q) >= 3 else None for _t, q, _i in buildings_raw]
_bp = [(g if g.is_valid else g.buffer(0)) if g is not None else SPoly() for g in _bp]
_bt = shapely.STRtree(_bp)
_ia, _ib = _bt.query(_bp, predicate="intersects")
_gone, _n_cut = set(), 0
for _a, _b in zip(_ia.tolist(), _ib.tolist()):
    if _a >= _b or _a in _gone or _b in _gone:
        continue
    _ov = _bp[_a].intersection(_bp[_b]).area
    if _ov <= 1.0:
        continue
    _sm, _lg = (_a, _b) if _bp[_a].area < _bp[_b].area else (_b, _a)
    if _ov > 0.6 * _bp[_sm].area:
        _gone.add(_sm)
        continue
    _rest = _bp[_sm].difference(_bp[_lg].buffer(0.05))
    _rest = max(getattr(_rest, "geoms", [_rest]), key=lambda g: g.area) if not _rest.is_empty else _rest
    if _rest.is_empty or _rest.geom_type != "Polygon" or _rest.area < 8:
        _gone.add(_sm)
        continue
    _bp[_sm] = _rest
    buildings_raw[_sm] = (buildings_raw[_sm][0], [(float(x), float(z)) for x, z in _rest.simplify(0.1).exterior.coords[:-1]], buildings_raw[_sm][2])
    _n_cut += 1
buildings_raw = [b for k, b in enumerate(buildings_raw) if k not in _gone]
print("  buildings standing in each other: left out", len(_gone), "cut back", _n_cut)
_blds = []
for _t, _pts, _id in buildings_raw:
    poly = SPoly(_pts)
    if poly.is_valid:
        _blds.append(poly)
bld_union = unary_union(_blds)
map_box = shapely.box(X0 + 6, Z0 + 6, X1 - 6, Z1 - 6)
road_all = unary_union(_all).buffer(2.5, quad_segs=3).buffer(-2.5, quad_segs=3).difference(bld_union.buffer(0.05)).intersection(map_box)
drive = unary_union(_drive).buffer(2.5, quad_segs=3).buffer(-2.5, quad_segs=3)
road_main = unary_union(_main).buffer(2.5, quad_segs=3).buffer(-2.5, quad_segs=3)
side = unary_union(_side).buffer(0.8, quad_segs=2).buffer(-0.8, quad_segs=2).difference(road_main).difference(bld_union.buffer(0.05)).intersection(map_box)
side = unary_union([g for g in getattr(side, "geoms", [side]) if g.geom_type == "Polygon" and g.area > 3.0])
side = side.difference(road_all.buffer(-0.05))             # where a road runs through a paved square, it is road
# Paved foot and cycle paths are asphalt like the roads, laid and cut with them (not ribbons of their own):
# every stretch of one that was to be drawn, at its own width. A path gives way to a sidewalk.
_paths, _i, _ro = [], 0, np.asarray(road_out, np.float64)
while _i + 4 <= len(_ro):
    _n = int(_ro[_i])
    if int(_ro[_i + 2]) == 3 and _n >= 2:
        _paths.append(LineString(_ro[_i + 4:_i + 4 + _n * 5].reshape(_n, 5)[:, :2]).buffer(float(_ro[_i + 1]), quad_segs=3))
    _i += 4 + _n * 5
if _paths:
    _pp = unary_union(_paths).difference(bld_union.buffer(0.05)).difference(side).intersection(map_box)
    print("  paved paths laid as asphalt: %d stretches, %.0f m2" % (len(_paths), _pp.area))
    road_all = unary_union([road_all, _pp])
# asphalt where someone who knows the place says there is asphalt: the open ground round each point
_fills = []
for x, z, r in overrides.ASPHALT_AT:
    reach = shapely.Point(x, z).buffer(r).difference(bld_union.buffer(0.2)).difference(side)
    part = [g for g in getattr(reach, "geoms", [reach]) if g.geom_type == "Polygon" and g.distance(shapely.Point(x, z)) < 1.0]
    if part:
        _fills.append(part[0])
for x, z, r in overrides.KERB_OPENINGS:
    gap = shapely.Point(x, z).buffer(r)
    _fills.append(gap.intersection(side.buffer(0.3)))
    side = side.difference(gap)
if _fills:
    road_all = unary_union([road_all] + _fills).buffer(0.6).buffer(-0.6).difference(bld_union.buffer(0.05)).intersection(map_box)
    side = side.difference(road_all.buffer(-0.05))
# the asphalt that is laid on the ground: the same, without the thin spikes and slivers that the cutting-out of
# buildings and the melting-together of shapes leave along its edge
road_laid = road_all.buffer(-0.6, quad_segs=3).buffer(0.6, quad_segs=3)
if road_decks:                                             # a road deck is its own asphalt, from side to side
    _deck_area = unary_union([LineString(dk[0]).buffer(dk[3] + 0.3, cap_style="flat") for dk in road_decks])
    side = side.difference(_deck_area)
    # a scrap of sidewalk left standing against a deck (a corner the deck did not quite take) goes too
    side = unary_union([g for g in getattr(side, "geoms", [side]) if g.geom_type == "Polygon" and (g.area > 20.0 or g.distance(_deck_area) > 0.5)])
    road_laid = road_laid.difference(_deck_area)
side = unary_union([g for g in getattr(side, "geoms", [side]) if g.geom_type == "Polygon" and g.area > 3.0])
# No slits and no pinholes: a strip of ground under about two metres wide between two paved surfaces (or between
# paving and a wall), and a small patch wholly closed in by paving, is paved over with asphalt.
_pv = unary_union([road_laid, side] + ([_deck_area] if road_decks else []))
shapely.prepare(_pv)
_ba = np.asarray(_blds, dtype=object)
_walls = unary_union(list(_ba[shapely.dwithin(_ba, _pv, 1.3)])).buffer(0.02)       # the buildings that stand at the paving
_shut = unary_union([_pv, _walls])
_fill = [_shut.buffer(0.9, quad_segs=3).buffer(-0.9, quad_segs=3).difference(_shut)]
_isles = []
for _p in getattr(_pv, "geoms", [_pv]):
    for _ring in _p.interiors:
        _h = SPoly(_ring)
        if _h.area < 14.0 or 4.0 * _h.area / _h.length < 2.2:
            if _h.area >= 3.0 and not _h.buffer(-0.6).is_empty and _h.distance(side) > 0.3:
                _isles.append(_h)                          # a traffic island: kerbed paving, not asphalt
            else:
                _fill.append(_h)
_fill = unary_union(_fill).difference(_walls).difference(side)
if _isles:
    _fill = _fill.difference(unary_union(_isles))
if road_decks:
    _fill = _fill.difference(_deck_area)
_fill = unary_union([g for g in getattr(_fill, "geoms", [_fill]) if g.geom_type == "Polygon" and g.area > 0.01]).intersection(map_box)
# each piece takes after what it lies against most: slabs beside a sidewalk, asphalt beside a road
_to_side, _to_road = [], []
_sp, _rp = list(getattr(side, "geoms", [side])), list(getattr(road_laid, "geoms", [road_laid]))
_st, _rt = shapely.STRtree(_sp), shapely.STRtree(_rp)
for _g in getattr(_fill, "geoms", [_fill]):
    _rim = _g.buffer(0.12)
    _as = sum(_rim.intersection(_sp[i]).area for i in _st.query(_rim))
    _ar = sum(_rim.intersection(_rp[i]).area for i in _rt.query(_rim))
    if _as + _ar > 0.0:                                    # (a nook between two walls that touches no paving stays as it is)
        (_to_side if _as > _ar else _to_road).append(_g)
print("  slits and pinholes paved over: %.0f m2 (%d as asphalt, %d as sidewalk)" % (sum(g.area for g in _to_road + _to_side), len(_to_road), len(_to_side)))
road_laid = unary_union([road_laid] + _to_road)
road_all = unary_union([road_all] + _to_road)
side = unary_union([side] + _to_side + _isles)
print("  traffic islands kept as kerbed paving:", len(_isles))

# A gravel path is not drawn across paving: where its line runs over asphalt or a sidewalk, the path stops at
# the edge and takes up again on the far side. The paved paths are in the asphalt already. (roads.bin was
# written before the paving was known; it is redone here.)
_onp = unary_union([road_laid, side])
_onp_wide = _onp.buffer(0.9, quad_segs=2)
shapely.prepare(_onp); shapely.prepare(_onp_wide)
_ro, _out, _i, _n_cut, _n_gone = np.asarray(road_out, np.float64), [], 0, 0, 0
while _i + 4 <= len(_ro):
    _n = int(_ro[_i])
    _head, _rows = _ro[_i:_i + 4], _ro[_i + 4:_i + 4 + _n * 5].reshape(_n, 5)
    _i += 4 + _n * 5
    if int(_head[2]) == 3:
        _n_gone += 1
        continue
    if int(_head[2]) != 7 or _n < 2:
        _out.append(_head); _out.append(_rows.ravel())
        continue
    _ln = LineString(_rows[:, :2])
    if not shapely.intersects(_onp, _ln):
        _out.append(_head); _out.append(_rows.ravel())
        continue
    _n_cut += 1
    _d = np.concatenate([[0.0], np.cumsum(np.hypot(np.diff(_rows[:, 0]), np.diff(_rows[:, 1])))])
    _rest = _ln.difference(_onp)
    for _part in getattr(_rest, "geoms", [_rest]):
        if _part.geom_type != "LineString" or _part.length < 1.0:
            continue
        if _part.length < 12.0 and _part.intersection(_onp_wide).length > 0.6 * _part.length:
            continue                                       # a stub left running along the edge of the asphalt
        _c = np.asarray(_part.coords)
        _at = shapely.line_locate_point(_ln, shapely.points(_c))
        _k = np.clip(np.searchsorted(_d, _at), 0, _n - 1)
        _run = np.stack([_c[:, 0], _c[:, 1], _rows[_k, 2], _rows[_k, 3], np.interp(_at, _d, _rows[:, 4])], 1)
        _out.append(np.array([len(_run), _head[1], _head[2], _head[3]])); _out.append(_run.ravel())
np.concatenate(_out).astype(np.float32).tofile(os.path.join(OUT, "roads.bin"))
print("  gravel paths cut at the edge of paving:", _n_cut, " paved path ribbons no longer drawn:", _n_gone)

# kept for the road sweep (tools/sweep.py), which compares these outlines with pictures of the finished ground
import pickle as _pk
_pk.dump({"road_all": shapely.to_wkb(road_all), "road_laid": shapely.to_wkb(road_laid), "side": shapely.to_wkb(side),
          "drive": shapely.to_wkb(drive), "deck": shapely.to_wkb(_deck_area) if road_decks else None,
          "buildings": shapely.to_wkb(bld_union)}, open(os.path.join(DATA, "paved_expect.pkl"), "wb"))


def triangles(poly, step=2.5):
    """Cut a polygon into triangles no bigger than about `step`, so they can follow the ground. The cut is
    exact: the polygon is laid over a square grid (the same grid everywhere, so neighbours share corners), whole
    squares become two triangles and the squares its outline runs through are cut to the outline. Nothing is
    left out along the edge and nothing reaches over it."""
    x0, z0, x1, z1 = poly.bounds
    gx, gz = np.meshgrid(np.arange(math.floor(x0 / step) * step, x1, step), np.arange(math.floor(z0 / step) * step, z1, step))
    gx, gz = gx.ravel(), gz.ravel()
    if not len(gx):
        return np.zeros((0, 6), np.float32)
    boxes = shapely.box(gx, gz, gx + step, gz + step)
    shapely.prepare(poly)
    whole = shapely.contains(poly, boxes)
    out = []
    if whole.any():
        ax, az = gx[whole], gz[whole]
        bx, bz = ax + step, az + step
        out.append(np.stack([ax, az, bx, az, bx, bz], 1))
        out.append(np.stack([ax, az, bx, bz, ax, bz], 1))
    part = ~whole & shapely.intersects(poly, boxes)
    if part.any():
        cut = shapely.intersection(poly, boxes[part])
        cut = shapely.get_parts(cut)
        cut = cut[(shapely.get_type_id(cut) == 3) & (shapely.area(cut) > 0.002)]
        if len(cut):
            tri = shapely.get_parts(shapely.constrained_delaunay_triangles(cut))
            tri = shapely.get_parts(tri)
            tri = tri[shapely.get_type_id(tri) == 3]
            if len(tri):
                out.append(shapely.get_coordinates(tri).reshape(-1, 4, 2)[:, :3].reshape(-1, 6))
    if not out:
        return np.zeros((0, 6), np.float32)
    co = np.concatenate(out).reshape(-1, 3, 2)
    area = np.abs((co[:, 1, 0] - co[:, 0, 0]) * (co[:, 2, 1] - co[:, 0, 1]) - (co[:, 1, 1] - co[:, 0, 1]) * (co[:, 2, 0] - co[:, 0, 0])) / 2
    return co[area > 0.004].reshape(-1, 6).astype(np.float32)


def pieces(lines, solid):
    """Boundary lines as short pieces [x, z, x, z, and the way out at each end (x, z twice)] with the open side
    (not `solid`) to the right. The way out at a corner is the mean of the two pieces meeting there, so what
    is hung on the edge (a kerb, a shoulder) runs round bends in one piece instead of fanning out in flaps."""
    out = []
    for ln in getattr(lines, "geoms", [lines]):
        if ln.is_empty or ln.geom_type not in ("LineString", "LinearRing"):
            continue
        co = shapely.get_coordinates(ln.segmentize(3.0))
        if len(co) >= 2:
            keep = np.concatenate([[True], np.hypot(*(co[1:] - co[:-1]).T) > 0.02])
            co = co[keep]
        if len(co) < 2:
            continue
        a, b = co[:-1], co[1:]
        d = b - a
        ln2 = np.hypot(d[:, 0], d[:, 1])
        right = np.stack([d[:, 1], -d[:, 0]], 1) / ln2[:, None]
        mid = (a + b) / 2 + right * 0.15
        flip = shapely.contains_xy(solid, mid[:, 0], mid[:, 1])
        nrm = np.where(flip[:, None], -right, right)               # out of the solid, per piece
        closed = len(co) > 3 and np.hypot(*(co[0] - co[-1])) < 0.02
        prev_n = np.roll(nrm, 1, 0)
        next_n = np.roll(nrm, -1, 0)
        if not closed:
            prev_n[0], next_n[-1] = nrm[0], nrm[-1]
        n0 = nrm + prev_n
        n1 = nrm + next_n
        for q, own in ((n0, nrm), (n1, nrm)):
            l_ = np.hypot(q[:, 0], q[:, 1])
            bad = l_ < 0.3                                          # a hairpin: keep the piece's own way out
            q[bad] = own[bad]
            l_[bad] = 1.0
            q /= l_[:, None]
        sa, sb = np.where(flip[:, None], b, a), np.where(flip[:, None], a, b)
        na, nb = np.where(flip[:, None], n1, n0), np.where(flip[:, None], n0, n1)
        out.append(np.concatenate([sa, sb, na, nb], 1))
    return np.concatenate(out).astype(np.float32) if out else np.zeros((0, 8), np.float32)


def pieces_laid(q):
    """Edge pieces with their heights: [x, y, z, out x, out z] for each end."""
    q = np.asarray(q, np.float64)
    if not len(q):
        return np.zeros((0, 10), np.float32)
    ya, yb = heights(q[:, 0], q[:, 1]), heights(q[:, 2], q[:, 3])
    return np.stack([q[:, 0], ya, q[:, 1], q[:, 4], q[:, 5], q[:, 2], yb, q[:, 3], q[:, 6], q[:, 7]], 1).astype(np.float32)


def cells_of(geom):
    """The parts of a geometry in each 100 m cell that it touches."""
    if geom.is_empty:
        return
    x0, z0, x1, z1 = geom.bounds
    for tx in range(int(x0 // 1000), int(x1 // 1000) + 1):
        for tz in range(int(z0 // 1000), int(z1 // 1000) + 1):
            tile = shapely.clip_by_rect(geom, tx * 1000, tz * 1000, tx * 1000 + 1000, tz * 1000 + 1000)
            if tile.is_empty:
                continue
            a0, b0, a1, b1 = tile.bounds
            for cx in range(int(a0 // 100), int(a1 // 100) + 1):
                for cz in range(int(b0 // 100), int(b1 // 100) + 1):
                    part = shapely.clip_by_rect(tile, cx * 100, cz * 100, cx * 100 + 100, cz * 100 + 100)
                    if not part.is_empty:
                        yield (cx, cz), part


# water.bin (float32): per stretch of running water [n, half width, 1 for a river] then n x [x, z, water level],
# running downstream; a stretch stops where a road lies over it (a culvert). lakes.bin: per lake
# [number of triangles, water level] then the triangles (x, z three times each).
water_out = []
n_water = 0
for half, big_one, pts in rivers:
    P = np.asarray(pts)
    under = shapely.contains_xy(road_all, P[:, 0], P[:, 1]) | shapely.contains_xy(bld_union, P[:, 0], P[:, 1])
    piece = []
    for q, hidden in list(zip(pts, under)) + [(None, True)]:
        if not hidden:
            piece.append(q)
            continue
        if len(piece) >= 3:
            water_out += [float(len(piece)), half, big_one]
            for x, z, y in piece:
                y = min(y, height_at(x, z) + 0.45)
                for dst, dhs, dpoly, _dh in road_decks:            # under a road deck: below it
                    if dpoly.buffer(half + 1.0).contains(shapely.Point(x, z)):
                        y = min(y, float(_deck_height(dst, dhs, np.float64(x), np.float64(z))) - 0.6)
                water_out += [x, z, y]
            n_water += 1
        piece = []
np.asarray(water_out, np.float32).tofile(os.path.join(OUT, "water.bin"))
lake_out = []
n_lakes = 0
for ring in lakes:
    poly = SPoly(ring).buffer(0).intersection(map_box)
    for g in getattr(poly, "geoms", [poly]):
        if g.geom_type != "Polygon" or g.area < 40:
            continue
        inner = g.buffer(-1.5)
        c = inner.representative_point() if not inner.is_empty else g.representative_point()
        ring_h = [height_at(x, z) for x, z in list(g.exterior.coords)[::3]]
        level = min(height_at(c.x, c.y), float(np.percentile(ring_h, 20))) + 0.12
        if level < 0.9 or np.percentile(ring_h, 80) - np.percentile(ring_h, 20) > 0.8:
            continue                                               # part of the sea, or the banks of a river: not level
        tris = triangles(g.buffer(0.8), 14.0)
        if len(tris):
            lake_out += [float(len(tris)), level] + tris.ravel().tolist()
            n_lakes += 1
np.asarray(lake_out, np.float32).tofile(os.path.join(OUT, "lakes.bin"))
print("  running water stretches:", n_water, "lakes:", n_lakes)
plaza_tris = []
if plaza_poly is not None:
    _floor = plaza_poly.buffer(22.0).difference(bld_union.buffer(0.05)).difference(road_all).difference(side)
    _floor = [g for g in getattr(_floor, "geoms", [_floor]) if g.geom_type == "Polygon" and g.intersects(plaza_poly)]
    if _floor:
        _floor = max(_floor, key=lambda g: g.intersection(plaza_poly).area).buffer(0.25).difference(bld_union)
        for g in getattr(_floor, "geoms", [_floor]):
            if g.geom_type == "Polygon" and g.area > 1.0:
                plaza_tris += [round(float(v), 2) for v in triangles(g, 2.0).ravel()]

# The terrace in front of the town hall: level with its entrance, and a flight of long steps down to the square
# (the laser model has a smooth slope there). The ground under the steps is a ramp; the game builds the steps.
radhus_steps = None
_rh = next((q for _t, q, _i in buildings_raw if _i == 231352909), None)
if _rh is not None and plaza_poly is not None:
    _best = None
    for i in range(len(_rh)):
        a, b = np.array(_rh[i]), np.array(_rh[(i + 1) % len(_rh)])
        ln = float(np.hypot(*(b - a)))
        if ln > 12 and plaza_poly.exterior.distance(shapely.Point(*((a + b) / 2))) < 1.5 and (_best is None or ln > _best[2]):
            _best = (a, b, ln)
    if _best is not None:
        a, b, ln = _best
        t = (b - a) / ln
        n = np.array([-t[1], t[0]])
        if (np.array(plaza_poly.centroid.coords[0]) - (a + b) / 2) @ n < 0:
            n = -n
        cfg = overrides.RADHUS_TERRACE
        out, run_ = cfg["out"], cfg["steps"] * cfg["tread"]
        i0, i1 = int(min(a[0], b[0]) - 20 - X0), int(max(a[0], b[0]) + 20 - X0)
        j0, j1 = int(min(a[1], b[1]) - 20 - Z0), int(max(a[1], b[1]) + 20 - Z0)
        gx, gz = np.meshgrid(np.arange(i0, i1) + X0, np.arange(j0, j1) + Z0)
        sa = (gx - a[0]) * t[0] + (gz - a[1]) * t[1]
        dn = (gx - a[0]) * n[0] + (gz - a[1]) * n[1]
        sub = H1[j0:j1, i0:i1]
        along = (sa > 0.5) & (sa < ln - 0.5)
        top = float(np.median(sub[along & (dn > 1.0) & (dn < 3.0)]))
        low = float(np.median(sub[along & (dn > out + run_ + 2.0) & (dn < out + run_ + 6.0)]))
        if 0.3 < top - low < 2.0:
            new = sub.copy()
            m = along & (dn > -0.5) & (dn <= out)
            new[m] = top
            m = along & (dn > out) & (dn <= out + run_)
            new[m] = np.maximum(low, top - (top - low) * (dn[m] - out + cfg["tread"]) / run_)
            m = along & (dn > out + run_) & (dn <= out + run_ + 5.0)
            new[m] = np.minimum(sub[m], low + 0.04)
            H1[j0:j1, i0:i1] = new
            radhus_steps = {"a": [round(float(a[0]), 2), round(float(a[1]), 2)], "b": [round(float(b[0]), 2), round(float(b[1]), 2)],
                            "n": [round(float(n[0]), 4), round(float(n[1]), 4)], "top": round(top, 2), "low": round(low, 2),
                            "out": out, "steps": cfg["steps"], "tread": cfg["tread"]}
            print("  town hall terrace at", round(top, 2), "over the square at", round(low, 2))

# A single cell standing tens of metres above all its neighbours is a fault in the data or in the working
# of it, not ground: it would stand in the landscape as a pillar. Such cells take their neighbours' height.
from scipy import ndimage as _ndi
from scipy import ndimage
_low = _ndi.minimum_filter(H1, size=5)
_spike = H1 - _low > 25.0
print("  pillars in the terrain removed:", int(_spike.sum()))
H1[_spike] = _low[_spike]
del _low, _spike


# ---------------------------------------------------------------- the paved surfaces, laid
# The ground is final now, and the asphalt and the sidewalks are laid on it here, once: every corner of every
# triangle is given its height, and the game draws and drives on exactly that. Paved ground that no road has
# levelled (a car park, a square, the filled-in corner of a junction) is evened out first: it takes the level
# of the graded road beside it where there is one, and is otherwise smoothed, so that asphalt lies flat
# instead of following every bump or climbing the bank beside it.
H_SCALE, H_OFFSET, STRIP = 0.02, -40.0, 1000
print("laying the paved surfaces…")
_pm = Image.new("L", (FW, FH), 0)
_pd = ImageDraw.Draw(_pm)
for _geom in (road_all, side):
    for g in getattr(_geom, "geoms", [_geom]):
        if g.geom_type != "Polygon":
            continue
        _pd.polygon([(x - X0, z - Z0) for x, z in g.exterior.coords], fill=255)
        for hole in g.interiors:
            _pd.polygon([(x - X0, z - Z0) for x, z in hole.coords], fill=0)
pmask = np.asarray(_pm) > 0
del _pm, _pd
_loose = pmask & ~graded & (H1 > 0.5)
if _loose.any():
    _src = (pmask & graded & (H1 > 0.5)).astype(np.float32)
    _wg = ndimage.gaussian_filter(_src, 3.0)
    _hg = ndimage.gaussian_filter(_src * H1, 3.0) / np.maximum(_wg, 1e-6)          # the graded road nearby
    _self = (pmask & (H1 > 0.5)).astype(np.float32)
    _ws = ndimage.gaussian_filter(_self, 2.0)
    _hs = ndimage.gaussian_filter(_self * H1, 2.0) / np.maximum(_ws, 1e-6)          # the paved ground itself, smoothed
    _t = np.clip(_wg / 0.25, 0.0, 1.0)
    H1 = np.where(_loose, _hg * _t + _hs * (1 - _t), H1).astype(np.float32)
    del _src, _wg, _hg, _self, _ws, _hs, _t
print("  paved ground evened out:", int(_loose.sum()), "m2")
del _loose
# Paving does not lie in the sea. Where a quay, a pier or a shore road reaches out over ground at sea level,
# the ground under it is brought up to the paved ground beside it (0.9 m at the least): the quay goes as far
# as its paving. Under a bridge deck the water stays.
_low = pmask & (H1 < 0.9)
if road_decks:
    _dm = Image.new("L", (FW, FH), 0)
    _dd = ImageDraw.Draw(_dm)
    for g in getattr(_deck_area.buffer(2.5), "geoms", [_deck_area.buffer(2.5)]):
        _dd.polygon([(x - X0, z - Z0) for x, z in g.exterior.coords], fill=255)
    _low &= ~(np.asarray(_dm) > 0)
    del _dm, _dd
if _low.any():
    _dry = (pmask & (H1 >= 0.9)).astype(np.float32)
    _wd = ndimage.gaussian_filter(_dry, 3.0)
    _hd = ndimage.gaussian_filter(_dry * H1, 3.0) / np.maximum(_wd, 1e-6)
    H1 = np.where(_low, np.where(_wd > 0.02, np.maximum(_hd, 0.9), 0.9), H1).astype(np.float32)
    del _dry, _wd, _hd
print("  paving brought up out of the water:", int(_low.sum()), "m2")
del _low
H1 = (np.clip(np.round((H1 - H_OFFSET) / H_SCALE), 0, 65535) * H_SCALE + H_OFFSET).astype(np.float32)      # as the game will read it
# The paved surface has heights of its own, fixed here once: the paved ground, carried one step out past its
# edge, so that the rim of the asphalt takes its height from the road and not from the bank beside it.
# It is also a little smoother than the ground it was read from (a road has no dents a metre across).
_m = pmask.astype(np.float32)
_wm = ndimage.gaussian_filter(_m, 1.2)
_hm = ndimage.gaussian_filter(_m * H1, 1.2)
HS = np.where(pmask, _hm / np.maximum(_wm, 1e-6), H1).astype(np.float32)
for _size in (5, 3):                                   # (two steps out; the nearer step from the nearer ground)
    _wm = ndimage.uniform_filter(_m, _size)
    _hm = ndimage.uniform_filter(_m * np.where(pmask, HS, 0.0), _size)
    if _size == 5:
        _far = np.where(pmask | (_wm < 0.02), HS, _hm / np.maximum(_wm, 1e-6))
    else:
        HS = np.where(pmask, HS, np.where(_wm < 0.05, _far, _hm / np.maximum(_wm, 1e-6))).astype(np.float32)
del _m, _wm, _hm, _far


def heights(x, z):
    """Ground height at many points at once."""
    fx = np.clip(np.asarray(x, np.float64) - X0, 0, FW - 1.001)
    fz = np.clip(np.asarray(z, np.float64) - Z0, 0, FH - 1.001)
    ix, iz = fx.astype(int), fz.astype(int)
    tx, tz = fx - ix, fz - iz
    return (H1[iz, ix] * (1 - tx) * (1 - tz) + H1[iz, ix + 1] * tx * (1 - tz) + H1[iz + 1, ix] * (1 - tx) * tz + H1[iz + 1, ix + 1] * tx * tz)


def surface(x, z):
    """Height of the paved surface at many points at once (before the game's lift)."""
    fx = np.clip(np.asarray(x, np.float64) - X0, 0, FW - 1.001)
    fz = np.clip(np.asarray(z, np.float64) - Z0, 0, FH - 1.001)
    ix, iz = fx.astype(int), fz.astype(int)
    tx, tz = fx - ix, fz - iz
    return (HS[iz, ix] * (1 - tx) * (1 - tz) + HS[iz, ix + 1] * tx * (1 - tz) + HS[iz + 1, ix] * (1 - tx) * tz + HS[iz + 1, ix + 1] * tx * tz)


def laid(x, z, step=2.5):
    """Height of the asphalt as it is laid: flat between the corners of the 2.5 m squares it is cut into."""
    x, z = np.asarray(x, np.float64), np.asarray(z, np.float64)
    lx, lz = np.floor(x / step) * step, np.floor(z / step) * step
    tx, tz = (x - lx) / step, (z - lz) / step
    return (surface(lx, lz) * (1 - tx) * (1 - tz) + surface(lx + step, lz) * tx * (1 - tz)
            + surface(lx, lz + step) * (1 - tx) * tz + surface(lx + step, lz + step) * tx * tz)


def ground(x, z):
    """Height of the ground as the game draws it: each square metre is two triangles, split from its (x+1, z)
    corner to its (x, z+1) corner. Also returns the three ground points each height hangs on."""
    fx = np.clip(np.asarray(x, np.float64) - X0, 0, FW - 1.001)
    fz = np.clip(np.asarray(z, np.float64) - Z0, 0, FH - 1.001)
    ix, iz = fx.astype(int), fz.astype(int)
    tx, tz = fx - ix, fz - iz
    lo = tx + tz <= 1.0
    h10, h01 = H1[iz, ix + 1], H1[iz + 1, ix]
    hc = np.where(lo, H1[iz, ix], H1[iz + 1, ix + 1])
    ax, az = np.where(lo, tx, 1 - tx), np.where(lo, tz, 1 - tz)
    return hc + ax * (np.where(lo, h10, h01) - hc) + az * (np.where(lo, h01, h10) - hc), ix, iz, lo


def with_heights(q):
    """Rows of (x, z) pairs as rows of (x, y, z) triples."""
    q = np.asarray(q, np.float64)
    if not len(q):
        return np.zeros((0, q.shape[1] * 3 // 2 if q.ndim == 2 else 0), np.float32)
    q = q.reshape(len(q), -1, 2)
    y = surface(q[:, :, 0], q[:, :, 1])
    return np.stack([q[:, :, 0], y, q[:, :, 1]], 2).reshape(len(q), -1).astype(np.float32)


# paved.bin (float32): per cell [cell x, cell z, number of asphalt triangles, sidewalk triangles, kerb pieces,
# shoulder pieces], then the triangles (x, y, z three times each) and the pieces (x, y, z and the way out x, z,
# for each end; the open side is to the right of the direction). y is the ground there; the game lifts asphalt
# and sidewalk off it.
paved = {}
for name, geom in (("A", road_laid), ("S", side)):
    for key, part in cells_of(geom):
        tris = [triangles(g) for g in getattr(part, "geoms", [part]) if g.geom_type == "Polygon" and g.area > 0.05]
        if tris:
            paved.setdefault(key, {})[name] = np.concatenate(tris)
for name, lines, solid in (("K", side.boundary, side), ("E", road_laid.boundary.difference(side.buffer(0.4)).difference(_deck_area.buffer(0.3)) if road_decks else road_laid.boundary.difference(side.buffer(0.4)), road_laid)):
    for key, part in cells_of(lines):
        seg = pieces(part, solid)
        if len(seg):
            paved.setdefault(key, {})[name] = seg
# The ground under the paving is then made to agree with it: each ground point under a triangle is put on that
# triangle, so the ground cannot stand up through the asphalt between a triangle's corners.
_all_tris = np.concatenate([d[k] for d in paved.values() for k in "AS" if k in d and len(d[k])]).astype(np.float64).reshape(-1, 3, 2)
_y = surface(_all_tris[:, :, 0], _all_tris[:, :, 1])
_ax, _az = _all_tris[:, 0, 0], _all_tris[:, 0, 1]
_e1, _e2 = _all_tris[:, 1] - _all_tris[:, 0], _all_tris[:, 2] - _all_tris[:, 0]
_den = _e1[:, 0] * _e2[:, 1] - _e1[:, 1] * _e2[:, 0]
_okt = np.abs(_den) > 1e-6
_bx0 = np.floor(_all_tris[:, :, 0].min(1) - X0).astype(int)
_bz0 = np.floor(_all_tris[:, :, 1].min(1) - Z0).astype(int)
_span = int(max(np.ceil(_all_tris[:, :, 0].max(1) - X0).astype(int).__sub__(_bx0).max(), np.ceil(_all_tris[:, :, 1].max(1) - Z0).astype(int).__sub__(_bz0).max())) + 1
_new = H1.copy()
_under = np.zeros(H1.shape, bool)                      # ground points that lie under paving
for _dx in range(_span):
    for _dz in range(_span):
        gx, gz = _bx0 + _dx, _bz0 + _dz
        px, pz = gx + X0 - _ax, gz + Z0 - _az
        u = (px * _e2[:, 1] - pz * _e2[:, 0]) / np.where(_okt, _den, 1.0)
        v = (pz * _e1[:, 0] - px * _e1[:, 1]) / np.where(_okt, _den, 1.0)
        hit = _okt & (u >= -1e-6) & (v >= -1e-6) & (u + v <= 1 + 1e-6) & (gx >= 0) & (gx < FW) & (gz >= 0) & (gz < FH)
        if hit.any():
            _new[gz[hit], gx[hit]] = (_y[hit, 0] + u[hit] * (_y[hit, 1] - _y[hit, 0]) + v[hit] * (_y[hit, 2] - _y[hit, 0])).astype(np.float32)
            _under[gz[hit], gx[hit]] = True
H1 = _new
H1 = (np.clip(np.floor((H1 - H_OFFSET) / H_SCALE + 0.01), 0, 65535) * H_SCALE + H_OFFSET).astype(np.float32)
# And the ground just beside the paving may not stand over it: a bank begins a metre out from the edge of the
# asphalt, not on it (the ground between a point under the road and a higher one beside it would otherwise
# rise across the edge and cover it in wedges).
_top = ndimage.maximum_filter(np.where(_under, H1, -1e9).astype(np.float32), size=3)
_ring = ndimage.binary_dilation(_under, structure=np.ones((3, 3), bool)) & ~_under & (H1 > 0.5)
H1 = np.where(_ring, np.minimum(H1, _top + 0.06), H1).astype(np.float32)
H1 = (np.clip(np.round((H1 - H_OFFSET) / H_SCALE), 0, 65535) * H_SCALE + H_OFFSET).astype(np.float32)
print("  ground beside the paving held down at", int((_ring & (H1 <= _top + 0.07)).sum()), "points")
# Last, what still stands through is pressed down. Between its points the ground is flat pieces of a square
# metre, the paving flat pieces of its own, and where the paving folds inward the ground between can stand
# over it. The ground is measured along every edge of every paved triangle (where the two can differ most)
# and the ground points that hold it too high are lowered, until nothing is nearer the top of the asphalt
# than 4 cm.
_tq = np.linspace(0.0, 1.0, 13)
for _round in range(8):
    _worst, _n_low = 0.0, 0
    _down = np.zeros(H1.shape, np.float32)
    for _c0 in range(0, len(_all_tris), 150000):
        _t = _all_tris[_c0:_c0 + 150000]
        _yy = _y[_c0:_c0 + 150000]
        for _a, _b in ((0, 1), (1, 2), (2, 0)):
            _px = _t[:, _a, 0][:, None] * (1 - _tq) + _t[:, _b, 0][:, None] * _tq
            _pz = _t[:, _a, 1][:, None] * (1 - _tq) + _t[:, _b, 1][:, None] * _tq
            _py = _yy[:, _a][:, None] * (1 - _tq) + _yy[:, _b][:, None] * _tq
            _g, _ix, _iz, _lo = ground(_px, _pz)
            _ex = _g - (_py + 0.06)
            _bad = _ex > 0.0
            if not _bad.any():
                continue
            _worst = max(_worst, float(_ex.max()))
            _n_low += int(_bad.sum())
            _e, _ix, _iz, _lo = _ex[_bad].astype(np.float32) + 0.01, _ix[_bad], _iz[_bad], _lo[_bad]
            np.maximum.at(_down, (_iz, _ix + 1), _e)
            np.maximum.at(_down, (_iz + 1, _ix), _e)
            np.maximum.at(_down, (np.where(_lo, _iz, _iz + 1), np.where(_lo, _ix, _ix + 1)), _e)
    if _n_low == 0:
        break
    H1 = H1 - _down
    H1 = (np.clip(np.floor((H1 - H_OFFSET) / H_SCALE + 0.01), 0, 65535) * H_SCALE + H_OFFSET).astype(np.float32)
    print("  ground standing through the paving: %d places, by up to %.2f m; pressed down (round %d)" % (_n_low, _worst, _round + 1))
del _all_tris, _new, _under, _top, _ring, _down
with open(os.path.join(OUT, "paved.bin"), "wb") as f:
    for (cx, cz), d in sorted(paved.items()):
        parts = [with_heights(d.get(k, np.zeros((0, 6), np.float32))) if k in "AS" else pieces_laid(d.get(k, np.zeros((0, 8), np.float32))) for k in "ASKE"]
        f.write(np.asarray([cx, cz] + [len(q) for q in parts], np.float32).tobytes())
        for q in parts:
            f.write(q.astype(np.float32).tobytes())
print("  paved cells:", len(paved), "asphalt triangles:", sum(len(d.get("A", [])) for d in paved.values()),
      "sidewalk triangles:", sum(len(d.get("S", [])) for d in paved.values()))

# How good are the roads? Counted over the whole map and written to data/road_check.json with the worst places,
# so that a change to the road building can be judged by numbers: holes in the asphalt under where cars drive,
# sidewalk lying in the carriageway, asphalt on steep ground, and jolts along the middle of the road.
_chk = {"hole": [], "walk": [], "steep": [], "jolt": []}
_cover = road_laid.union(_deck_area) if road_decks else road_laid
shapely.prepare(_cover); shapely.prepare(side); shapely.prepare(bld_union)
_n_pts = 0
for w in road_ways:
    if w[0] != 0 or not w[6] or len(w[5]) < 2 or id(w[5]) in pedestrian_ids:
        continue
    st = np.asarray(stations(w[5], 2.0))
    if len(st) < 3:
        continue
    T = np.gradient(st, axis=0)
    T /= np.maximum(np.hypot(T[:, 0], T[:, 1]), 1e-6)[:, None]
    N = np.stack([T[:, 1], -T[:, 0]], 1)
    for off in (0.0, w[1] - 0.7, -(w[1] - 0.7)):
        P = st + N * off
        ok = (P[:, 0] > X0 + 12) & (P[:, 0] < X1 - 12) & (P[:, 1] > Z0 + 12) & (P[:, 1] < Z1 - 12)
        ok &= heights(P[:, 0], P[:, 1]) > 0.6
        ok &= ~shapely.contains_xy(bld_union, P[:, 0], P[:, 1])
        _n_pts += int(ok.sum())
        miss = ok & ~shapely.contains_xy(_cover, P[:, 0], P[:, 1])
        _chk["walk"] += [[round(float(x), 1), round(float(z), 1)] for x, z in P[miss & shapely.contains_xy(side, P[:, 0], P[:, 1])]]
        _chk["hole"] += [[round(float(x), 1), round(float(z), 1)] for x, z in P[miss & ~shapely.contains_xy(side, P[:, 0], P[:, 1])]]
    y = laid(st[:, 0], st[:, 1])
    d2 = np.abs(y[:-2] - 2 * y[1:-1] + y[2:])
    for k in np.nonzero((d2 > 0.08) & (y[1:-1] > 0.6) & (st[1:-1, 0] > X0 + 12) & (st[1:-1, 0] < X1 - 12) & (st[1:-1, 1] > Z0 + 12) & (st[1:-1, 1] < Z1 - 12))[0]:
        _chk["jolt"].append([round(float(st[k + 1, 0]), 1), round(float(st[k + 1, 1]), 1), round(float(d2[k]), 2), int(graded[min(max(int(st[k + 1, 1] - Z0), 0), FH - 1), min(max(int(st[k + 1, 0] - X0), 0), FW - 1)]), w[1]])
_n_tri = 0
for d in paved.values():
    q = with_heights(d.get("A", np.zeros((0, 6), np.float32))).reshape(-1, 3, 3).astype(np.float64)
    if not len(q):
        continue
    n = np.cross(q[:, 1] - q[:, 0], q[:, 2] - q[:, 0])
    slope = np.hypot(n[:, 0], n[:, 2]) / np.maximum(np.abs(n[:, 1]), 1e-9)
    _n_tri += len(q)
    for k in np.nonzero((slope > 0.25) & (q[:, :, 1].min(1) > 0.6))[0]:
        _chk["steep"].append([round(float(q[k, :, 0].mean()), 1), round(float(q[k, :, 2].mean()), 1), round(float(slope[k]), 2), int(graded[int(q[k, :, 2].mean() - Z0), int(q[k, :, 0].mean() - X0)])])
print("  road check: of", _n_pts, "points on the carriageway,", len(_chk["hole"]), "have no asphalt and", len(_chk["walk"]), "have sidewalk;",
      "of", _n_tri, "asphalt triangles,", len(_chk["steep"]), "are steep; jolts along the middle of roads:", len(_chk["jolt"]))
json.dump(_chk, open(os.path.join(DATA, "road_check.json"), "w"), separators=(",", ":"))
del _chk, _cover

# The ground as the game loads it: the 1 m grid in strips of 1000 columns (16-bit, 2 cm steps), which
# it reads piece by piece around the player, and every tenth point of it for the far view.
os.makedirs(os.path.join(OUT, "h1"), exist_ok=True)
_q = np.clip(np.round((H1 - H_OFFSET) / H_SCALE), 0, 65535).astype("<u2")
for k in range((FW + STRIP - 1) // STRIP):
    np.ascontiguousarray(_q[:, k * STRIP:(k + 1) * STRIP]).tofile(os.path.join(OUT, "h1", "x%02d.bin" % k))
del _q
H = np.ascontiguousarray(H1[::10, ::10])
assert H.shape == (GH, GW)
H.tofile(os.path.join(OUT, "height.bin"))
sea = H <= 0.25

# ---------------------------------------------------------------- forest mask (10 m grid)
print("forest and trees…")
from scipy import ndimage


def to_grid(im):
    return np.asarray(im.resize((GW, GH), Image.BOX)).astype(np.float32) / 255.0


bld_g, road_g, open_g, wood_g, lake_g = (to_grid(i) for i in (bld_im, road_im, open_im, wood_im, lake_im))
built_up = blur(np.clip(bld_g * 6 + road_g * 1.5, 0, 1), 5)        # how "town" a cell is
land = (~sea) & (lake_g < 0.3)

# Trees are where the laser saw them: the height of whatever stands on the ground (surface model minus
# terrain model), with buildings, roads and power lines taken out, is the canopy; every peak in it is a tree
# of that height. The surface model for the whole area is kept in data/kartverket/dom_raw.npy.
_dom = os.path.join(DATA, "kartverket", "dom_raw.npy")
if not os.path.exists(_dom):
    print("  surface tiles:", fetch_area("dom", X0, X1, Z0, Z1))
    np.save(_dom, grid("dom", X0, Z0, FW, FH))
chm = np.nan_to_num(np.load(_dom) - H1, nan=0.0)
taken = np.zeros(H1.shape, bool)
taken[:-1, :-1] = (np.asarray(bld_im) > 0) | (np.asarray(road_im) > 0) | (np.asarray(line_im) > 0) | (np.asarray(lake_im) > 0)
taken = ndimage.binary_dilation(taken, iterations=2)
chm[taken | (H1 < 0.8)] = 0.0
del taken
chm = np.clip(chm, 0.0, 45.0).astype(np.float32)
canopy = chm > 2.5
smooth = ndimage.gaussian_filter(chm, 1.0)
tops = (smooth == ndimage.maximum_filter(smooth, size=7)) & (smooth > 3.0)
tops &= ndimage.uniform_filter(canopy.astype(np.float32), 3) > 0.6           # a crown, not a pole
dense = ndimage.uniform_filter(canopy.astype(np.float32), 25)
tall = ndimage.maximum_filter(chm, size=3)
tz, tx = np.nonzero(tops)
th, td = tall[tz, tx], dense[tz, tx]
del smooth, tops, tall, dense
trng = np.random.default_rng(1940)
in_forest = td > 0.55
keep_share = min(1.0, max(0.05, (430000 - int((~in_forest).sum())) / max(int(in_forest.sum()), 1)))
keep = ~in_forest | (trng.random(len(tz)) < keep_share)                       # thin the forest, keep every town tree
tz, tx, th, in_forest = tz[keep], tx[keep], th[keep], in_forest[keep]
spruce = trng.random(len(tz)) < np.where(in_forest, np.where(th > 9, 0.8, 0.55), 0.3)
scale = np.clip(th / np.where(spruce, 7.9, 7.4), 0.45, 3.2)
print("  trees seen by the laser:", len(keep), "kept:", len(tz), "forest share kept:", round(keep_share, 2))
trees = [(float(X0 + x + jx), float(Z0 + z + jz), float(sc), 0.0 if sp else 1.0, float(H1[z, x]))
         for x, z, sc, sp, jx, jz in zip(tx, tz, scale, spruce, trng.uniform(-0.3, 0.3, len(tz)), trng.uniform(-0.3, 0.3, len(tz)))]

# the forest floor is drawn where the canopy is
_cov = canopy[:FH - 1, :FW - 1].reshape((FH - 1) // 10, 10, (FW - 1) // 10, 10).mean((1, 3))
forest_g = np.zeros((GH, GW), bool)
forest_g[:-1, :-1] = _cov > 0.35
forest_g &= land
mask_b = Image.fromarray((canopy[:FH - 1, :FW - 1] * 255).astype(np.uint8)).resize((MW, MH), Image.BOX).filter(ImageFilter.GaussianBlur(2.5))
del canopy, chm

# The road tint of the ground: full (255) where the ground itself is the road surface (gravel roads, runways),
# half (128) where laid asphalt or paving lies on it. The game tints the half-strength kind only far away, where
# the laid surfaces are not built; close by, the asphalt is what was laid, and the bank beside it stays green.
_r = np.asarray(road_im).copy()
_laid = ndimage.binary_dilation(pmask, iterations=2)[:_r.shape[0], :_r.shape[1]]
_r[:_laid.shape[0], :_laid.shape[1]][_laid & (_r[:_laid.shape[0], :_laid.shape[1]] > 0)] = 128
_r[:_laid.shape[0], :_laid.shape[1]][pmask[:_laid.shape[0], :_laid.shape[1]]] = 128
mask_r = Image.fromarray(_r).resize((MW, MH), Image.BOX)
del _r, _laid
mask_g = path_im.resize((MW, MH), Image.BOX)
mask_a = Image.fromarray(255 - np.asarray(lake_im.resize((MW, MH), Image.BOX)))
Image.merge("RGBA", (mask_r, mask_g, mask_b, mask_a)).save(os.path.join(OUT, "mask.png"))
# a second mask for what else covers the ground: R mown grass (gardens count half), G fields, B bog, A bare rock and sand
garden = np.clip(blur(np.clip(bld_g * 5, 0, 1), 2.5) * 2.2, 0, 0.6)           # around houses
lawn = np.maximum(np.asarray(lawn_im.resize((MW, MH), Image.BOX)).astype(np.float32) / 255.0,
                  np.asarray(Image.fromarray((garden * 255).astype(np.uint8)).resize((MW, MH), Image.BILINEAR)).astype(np.float32) / 255.0)
Image.merge("RGBA", (Image.fromarray((lawn * 255).astype(np.uint8)), farm_im.resize((MW, MH), Image.BOX),
                     wet_im.resize((MW, MH), Image.BOX), rock_im.resize((MW, MH), Image.BOX))).save(os.path.join(OUT, "mask2.png"))

storgata_line = unary_union([LineString(q) for q in storgata]) if storgata else None
for t, x, z in osm_nodes:                                  # single trees and rows of trees that are on the map
    if t.get("natural") == "tree" and inside(x, z, 10) and height_at(x, z) > 0.8:
        trees.append((x, z, rng.uniform(1.0, 1.5), 0.0 if t.get("leaf_type") == "needleleaved" else 1.0, height_at(x, z)))
for pts in tree_rows:
    for x, z in stations(pts, 8.0):
        if inside(x, z, 10) and height_at(x, z) > 0.8:
            trees.append((x, z, rng.uniform(1.0, 1.4), 1.0, height_at(x, z)))
# no tree stands on the asphalt, whatever put it there
_keep_out = road_all.buffer(0.5, quad_segs=2)
if storgata_line is not None:                              # and none at all along Storgata
    _keep_out = _keep_out.union(storgata_line.buffer(14.0))
shapely.prepare(_keep_out)
_T = np.asarray(trees, np.float32)
_on = shapely.contains_xy(_keep_out, _T[:, 0].astype(float), _T[:, 1].astype(float))
for _x, _z in overrides.NO_TREES:                          # and the ones someone who knows the place says are not there
    _on |= np.hypot(_T[:, 0] - _x, _T[:, 1] - _z) < 1.5
if sports_clear is not None:
    _on |= shapely.contains_xy(sports_clear, _T[:, 0].astype(float), _T[:, 1].astype(float))
for q in overrides.PORTALS:                                # nor in the mouth of a way into the hill
    _on |= np.hypot(_T[:, 0] - (q["at"][0] + q["dir"][0] * 3.0), _T[:, 1] - (q["at"][1] + q["dir"][1] * 3.0)) < 9.0
for x, z in overrides.PLAYGROUNDS:
    _on |= np.hypot(_T[:, 0] - x, _T[:, 1] - z) < 6.0
for f in fields:                                           # nor on a football pitch
    pc, pu = np.array(f["pitch"][0:2]), np.array(f["pitch"][2:4])
    du = (_T[:, 0] - pc[0]) * pu[0] + (_T[:, 1] - pc[1]) * pu[1]
    dv = -(_T[:, 0] - pc[0]) * pu[1] + (_T[:, 1] - pc[1]) * pu[0]
    _on |= (np.abs(du) < f["pitch"][4] + 3.0) & (np.abs(dv) < f["pitch"][5] + 3.0)
if plaza_tris:
    _on |= shapely.contains_xy(plaza_poly.buffer(22.0).difference(bld_union), _T[:, 0].astype(float), _T[:, 1].astype(float)) & \
        (np.hypot(_T[:, 0] - plaza_poly.centroid.x, _T[:, 1] - plaza_poly.centroid.y) < 30)
print("  trees on the asphalt, removed:", int(_on.sum()))
trees = [t for t, o in zip(trees, _on) if not o]
with open(os.path.join(OUT, "trees.bin"), "wb") as f:
    f.write(np.asarray(trees, np.float32).tobytes())

# ---------------------------------------------------------------- buildings + war damage
print("buildings…")
# How a building is dressed when seen close up (the styles in scripts/facades.gd). The map says what a
# building is; how old it looks is read from its measured shape, since nothing open gives its year:
# a steep roof on a compact house is an older villa, a low one a house of the 1960s-80s, a flat or
# single-pitch one a newer house; blocks of flats with pitched roofs are post-war, flat ones newer.
(VILLA, HOUSE60, MODERN, ROW, APT_OLD, APT_NEW, SHOP, BIGBOX, INDUSTRY, OUTBUILDING, PUBLIC, BARN, OLD_TIMBER,
 MAIN_STREET) = range(14)
HOUSE_KINDS = {"house", "detached", "bungalow", "farm"}
ROW_KINDS = {"semidetached_house", "terrace"}
APT_KINDS = {"apartments", "dormitory", "residential", "hotel"}
SHOP_KINDS = {"commercial", "office", "retail", "service", "supermarket", "kiosk"}
INDUSTRY_KINDS = {"warehouse", "industrial", "hangar", "transportation", "parking"}
OUT_KINDS = {"garage", "garages", "shed", "carport", "roof", "greenhouse", "container", "toilets"}
BARN_KINDS = {"barn", "farm_auxiliary", "boathouse", "cabin", "hut"}
PUBLIC_KINDS = {"civic", "school", "kindergarten", "church", "religious", "sports_centre", "hospital", "university",
                "public", "chapel", "college"}


def roof_shape(roof, area):
    """Mean pitch of the sloping faces (degrees) and the share of the outline they cover."""
    acc = tot = 0.0
    for f in roof["f"]:
        if f[0]:
            continue
        P = np.array(f[1:]).reshape(-1, 3)
        n = np.zeros(3)
        for i in range(len(P)):
            n += np.cross(P[i], P[(i + 1) % len(P)])
        a = float(np.linalg.norm(n)) / 2
        if a < 0.5:
            continue
        acc += a * math.degrees(math.acos(min(1.0, abs(n[1]) / (2 * a))))
        tot += abs(n[1]) / 2
    return (acc / max(tot, 1e-6) if tot else 0.0), tot / max(area, 1e-6)


def style_of(kind, area, h, roof, r):
    pitch, share = roof_shape(roof, area)
    pitched = share > 0.45 and pitch > 9
    if kind in OUT_KINDS or (kind == "yes" and area < 45):
        return OUTBUILDING
    if kind in BARN_KINDS:
        return BARN
    if kind in HOUSE_KINDS or (kind == "yes" and area < 260 and h < 9.5):
        if not pitched or (share < 0.7 and pitch < 14):
            return MODERN
        if pitch >= 34 or (pitch >= 29 and r.random() < 0.5):
            return VILLA if area < 200 else HOUSE60
        return HOUSE60
    if kind in ROW_KINDS:
        return ROW
    if kind in APT_KINDS:
        return APT_OLD if pitched else APT_NEW
    if kind in SHOP_KINDS:
        return BIGBOX if (area > 1400 and not pitched) else SHOP
    if kind in INDUSTRY_KINDS:
        return INDUSTRY if area >= 60 else OUTBUILDING
    if kind in PUBLIC_KINDS:
        return PUBLIC
    return PUBLIC if area >= 260 else HOUSE60


WHITE_PAINT, FALU, OCHRE = (235, 232, 222), (150, 50, 40), (212, 168, 82)
WALLS = {
    VILLA: [WHITE_PAINT, WHITE_PAINT, WHITE_PAINT, OCHRE, OCHRE, FALU, (172, 190, 170), (160, 180, 195), (226, 206, 162), (120, 140, 150)],
    HOUSE60: [(110, 75, 50), (110, 75, 50), (72, 60, 50), (62, 82, 62), (190, 150, 72), WHITE_PAINT, WHITE_PAINT, (142, 142, 136),
              FALU, (78, 96, 120), (200, 190, 170)],
    MODERN: [(240, 240, 238), (62, 64, 67), (62, 64, 67), (132, 134, 137), (172, 132, 92), (40, 42, 45)],
    ROW: [WHITE_PAINT, FALU, OCHRE, (110, 75, 50), (122, 142, 152), (200, 190, 170), (142, 142, 136)],
    APT_OLD: [(226, 212, 172), (222, 192, 142), (206, 172, 152), (200, 206, 196), (230, 226, 216), (188, 120, 96)],
    APT_NEW: [(236, 236, 233), (182, 184, 187), (92, 94, 98), (202, 172, 132), (225, 225, 220)],
    SHOP: [(216, 206, 186), (200, 180, 150), (226, 223, 216), (186, 150, 126), (172, 176, 176), (150, 96, 76)],
    BIGBOX: [(200, 202, 205), (152, 156, 160), (230, 230, 228), (72, 92, 122), (160, 42, 42)],
    INDUSTRY: [(172, 176, 180), (122, 132, 142), (206, 206, 200), (92, 112, 96), (142, 62, 52)],
    OUTBUILDING: [WHITE_PAINT, FALU, (110, 75, 50), (142, 142, 136), OCHRE],
    PUBLIC: [(226, 216, 196), (202, 186, 160), (216, 216, 210), (172, 110, 90), (236, 233, 226)],
    BARN: [FALU, FALU, FALU, FALU, WHITE_PAINT, OCHRE, (90, 66, 46), (62, 52, 46)],
    OLD_TIMBER: [(74, 54, 40), (60, 46, 36), (88, 64, 44), (50, 40, 34)],
    # the rendered post-war blocks of Storgata, in the pale and warm colours seen in photographs of the street
    MAIN_STREET: [(228, 214, 176), (232, 228, 218), (216, 142, 98), (222, 180, 104), (192, 202, 182), (204, 204, 198),
                  (226, 196, 150), (236, 224, 190)],
}
ROOF_TILE = [(58, 58, 61), (58, 58, 61), (58, 58, 61), (42, 42, 44), (124, 62, 46), (124, 62, 46), (86, 92, 82)]
ROOF_SHEET = [(122, 126, 131), (62, 64, 68), (62, 64, 68), (150, 150, 148), (96, 62, 52)]
ROOF_FLAT = [(72, 72, 74), (92, 90, 86), (62, 64, 67)]
SHEET_ROOFED = {MODERN, APT_NEW, BIGBOX, INDUSTRY, BARN}


def colour_tag(v):
    """An OSM colour tag (#rrggbb or a few plain names) as (r, g, b), or None."""
    names = {"white": (238, 238, 232), "red": FALU, "yellow": OCHRE, "grey": (150, 150, 148), "gray": (150, 150, 148),
             "black": (40, 40, 42), "brown": (110, 75, 50), "green": (70, 100, 70), "blue": (80, 100, 130), "beige": (215, 200, 170)}
    v = (v or "").strip().lower()
    if v in names:
        return names[v]
    if len(v) == 7 and v[0] == "#":
        try:
            return int(v[1:3], 16), int(v[3:5], 16), int(v[5:7], 16)
        except ValueError:
            return None
    return None


H_BY_TYPE = {"house": (6.0, 8.5), "detached": (6.0, 8.5), "semidetached_house": (6.5, 8.5), "terrace": (6.5, 8.5),
             "apartments": (10, 17), "residential": (8, 13), "garage": (2.6, 3.2), "garages": (2.6, 3.2),
             "shed": (2.3, 3.0), "cabin": (3.2, 4.5), "boathouse": (3.5, 5), "civic": (8, 13),
             "warehouse": (6, 9), "industrial": (7, 11), "office": (10, 18), "commercial": (8, 15),
             "retail": (6, 11), "school": (7, 11), "church": (12, 18), "hospital": (14, 22), "hotel": (14, 30),
             "kindergarten": (4.5, 6), "university": (10, 16), "public": (8, 13), "roof": (3, 4.5)}
SMALL = {"garage", "garages", "shed", "cabin", "boathouse", "roof", "carport", "hut"}


def area_centroid(p):
    a = cx = cz = 0.0
    for i in range(len(p)):
        x0, z0 = p[i]
        x1, z1 = p[(i + 1) % len(p)]
        c = x0 * z1 - x1 * z0
        a += c
        cx += (x0 + x1) * c
        cz += (z0 + z1) * c
    a *= 0.5
    if abs(a) < 1e-6:
        return 0.0, p[0][0], p[0][1]
    return a, cx / (6 * a), cz / (6 * a)


def roof_fit(pts):
    """Measure a building against Kartverket's laser data.
    Returns (eave height above the uphill ground, roof type 0 flat / 1 gable / 2 hip, ridge rise, ridge direction)
    plus the ground height difference across the footprint, or None where there is no data."""
    P = np.asarray(pts, np.float64)
    n = len(P)
    seg = np.roll(P, -1, 0) - P
    i = int(np.argmax((seg ** 2).sum(1)))
    u = seg[i] / math.hypot(*seg[i])
    v = np.array([-u[1], u[0]])
    pu, pv = P @ u, P @ v
    um, vm = (pu.min() + pu.max()) / 2, (pv.min() + pv.max()) / 2
    hu, hv = (pu.max() - pu.min()) / 2, (pv.max() - pv.min()) / 2
    if hu < 1.2 or hv < 1.2:
        return None
    gu, gv = np.meshgrid(np.arange(-hu + 0.8, hu - 0.79, 1.0), np.arange(-hv + 0.8, hv - 0.79, 1.0))
    gu, gv = gu.ravel(), gv.ravel()
    X = (um + gu) * u[0] + (vm + gv) * v[0]
    Z = (um + gu) * u[1] + (vm + gv) * v[1]
    inside = np.zeros(len(X), bool)                       # even-odd point in polygon
    for k in range(n):
        x0, z0 = P[k]
        x1, z1 = P[(k + 1) % n]
        if z0 == z1:
            continue
        cross = ((z0 > Z) != (z1 > Z)) & (X < (x1 - x0) * (Z - z0) / (z1 - z0) + x0)
        inside ^= cross
    X, Z, gu, gv = X[inside], Z[inside], gu[inside], gv[inside]
    if len(X) < 6:
        return None
    d = DOM.at(X, Z)
    ok = ~np.isnan(d)
    if ok.sum() < 6:
        return None
    d, gu, gv = d[ok], gu[ok], gv[ok]
    keep = d <= np.percentile(d, 96)                      # overhanging trees, antennas
    d, gu, gv = d[keep], gu[keep], gv[keep]
    ground = DTM.at(P[:, 0], P[:, 1])
    if np.isnan(ground).all():
        return None
    span = float(np.nanmax(ground) - np.nanmin(ground))
    ground = float(np.nanmax(ground))

    def fit(t):                                           # d ≈ a - b·t, t = 0 on the ridge, 1 at the eave
        A = np.stack([np.ones_like(t), -t], 1)
        coef, *_ = np.linalg.lstsq(A, d, rcond=None)
        res = d - A @ coef
        var = ((d - d.mean()) ** 2).sum()
        return coef[0], coef[1], (1 - (res ** 2).sum() / var) if var > 1e-6 else 0.0

    a1, b1, r1 = fit(np.abs(gv) / hv)                     # ridge along u
    a2, b2, r2 = fit(np.abs(gu) / hu)                     # ridge along v
    if r2 > r1:
        a, b, r, ridge, half, along, across, hlen = a2, b2, r2, v, hu, gv, gu, hv
    else:
        a, b, r, ridge, half, along, across, hlen = a1, b1, r1, u, hv, gu, gv, hu
    if r < 0.4 or b < 0.8 or b > 9.0 or b / half > 1.6:
        return max(2.2, float(np.median(d)) - ground), 0, 0.0, 0.0, span
    kind = 1
    near = np.abs(across) < 0.3 * half                    # along the ridge: does it drop toward the ends?
    if hlen > half * 1.15 and near.sum() >= 6:
        end = np.clip((np.abs(along[near]) - (hlen - half)) / half, 0, 1)
        if end.max() > 0.5:
            A = np.stack([np.ones_like(end), -end], 1)
            coef, *_ = np.linalg.lstsq(A, d[near], rcond=None)
            if coef[1] > 0.5 * b:
                kind = 2
    return max(2.2, float(a - b) - ground), kind, float(b), math.atan2(ridge[1], ridge[0]), span


prelim = []
# Hand-detailed buildings around Rådhusplassen (built by scripts/landmarks.gd, left out of the generic set).
LANDMARKS = {231352909: "radhus", 172573648: "storgata31", 172573646: "storgata33", 935525932: "aandahls",
             310662273: "domkirke", 230972703: "klokketarn", SEILET_ID: "seilet"}
landmarks = []
for t, pts, osm_id in buildings_raw:
    a, cx, cz = area_centroid(pts)
    if abs(a) < 6 or not inside(cx, cz, 15):
        continue
    if a > 0:                       # normalise winding (counter-clockwise seen from above, +Y)
        pts = pts[::-1]
    if osm_id in LANDMARKS:
        hs = [height_at(x, z) for x, z in pts]
        fitted = roof_fit(pts)
        landmarks.append({"key": LANDMARKS[osm_id], "ymin": round(min(hs), 2), "ymax": round(max(hs), 2),
                          "h": round(fitted[0] + fitted[4], 1) if fitted else 0.0, "rise": round(fitted[2], 1) if fitted else 0.0,
                          "pts": [round(v, 2) for p in pts for v in p]})
        continue
    prelim.append((t, pts, abs(a), cx, cz, osm_id))

# Roofs: the real shape of each, worked out from the laser surface model (tools/roofs.py). That takes a
# few minutes for the whole town, so the results are kept in data/kartverket/roofs.pkl between runs.
import pickle
import multiprocessing
import roofs

_cache_path = os.path.join(DATA, "kartverket", "roofs.pkl")
try:
    roof_cache = pickle.load(open(_cache_path, "rb"))
except (OSError, EOFError):
    roof_cache = {}


def _roof_job(job):
    key, pts, ymin, osm_id = job
    try:
        return key, roofs.fit(pts, DOM, ymin, osm_id)
    except Exception as err:                                  # one odd outline must not stop the town
        print("  roof failed for way", osm_id, err)
        return key, None


jobs = []
grounds = []
for t, pts, a, cx, cz, osm_id in prelim:
    hs = [height_at(x, z) for x, z in pts]
    grounds.append((min(hs), max(hs)))
    key = (osm_id, roofs.VERSION, round(min(hs), 1), hash(tuple(round(v, 2) for q in pts for v in q)))
    if key not in roof_cache:
        jobs.append((key, pts, min(hs), osm_id))
if jobs:
    print("  fitting", len(jobs), "roofs…")
    with multiprocessing.get_context("fork").Pool() as pool:
        for key, roof in pool.imap_unordered(_roof_job, jobs, chunksize=20):
            roof_cache[key] = roof
    pickle.dump(roof_cache, open(_cache_path, "wb"))

# Real colours read from street photos, for the buildings that have them (tools/colours.py).
try:
    real_colours = json.load(open(os.path.join(DATA, "colours.json")))
except OSError:
    real_colours = {}
try:                                                      # and from Vegbilder's road photos, which stand closer (colours.py --vegbilder)
    for _k, _v in json.load(open(os.path.join(DATA, "colours_vegbilder.json"))).items():
        if int(_k) not in getattr(overrides, "NO_PHOTO_COLOUR", ()):
            real_colours[_k] = dict(real_colours.get(_k, {}), **_v)
except OSError:
    pass
photographed = set()
n_real = [0, 0]

buildings, fires = [], []
centres = []
measured = 0
n_unseen = [0]
roof_stats = [0, 0, 0]
for (t, pts, a, cx, cz, osm_id), (ymin, ymax) in zip(prelim, grounds):
    kind = t.get("building", "yes")
    key = (osm_id, roofs.VERSION, round(ymin, 1), hash(tuple(round(v, 2) for q in pts for v in q)))
    roof = roof_cache.get(key)
    if roof is None:
        h = None
        try:
            if "height" in t:
                h = float(str(t["height"]).replace("m", "").strip())
            elif "building:levels" in t:
                h = float(t["building:levels"]) * 3.0 + 1.2
        except ValueError:
            h = None
        if h is None:
            lo, hi = H_BY_TYPE.get(kind, (5.5, 9.0) if a < 300 else (7.0, 12.0))
            h = rng.uniform(lo, hi)
        roof = roofs.flat_roof(pts, ymax + max(2.2, min(h, 70.0)))
    elif roof["eave"] - ymax < 2.6 and roof["top"] - ymin < 4.2 and a > 200 and kind not in SMALL and kind != "roof" and "levels" not in overrides.BUILDINGS.get(osm_id, {}):
        # A large building that the laser model has as bare ground: built after the survey. It gets the height
        # buildings of its kind usually have, not the minimum.
        try:
            hh = float(t["building:levels"]) * 3.0 + 1.2 if "building:levels" in t else None
        except ValueError:
            hh = None
        if hh is None:
            lo, hi = H_BY_TYPE.get(kind, (7.0, 9.5))
            hh = max(6.5, (lo + hi) / 2) if a > 800 else (lo + hi) / 2
        roof = roofs.flat_roof(pts, ymax + hh)
        n_unseen[0] += 1
    else:
        measured += 1
        roof_stats[roof["kind"]] += 1
    known = overrides.BUILDINGS.get(osm_id, {})
    if known.get("plain"):                                  # a plain roof where the fitted one came out wrong
        try:
            roof = roofs.fit(pts, DOM, ymin, osm_id, True) or roof
        except Exception as err:
            print("  plain roof failed for way", osm_id, err)
    if "levels" in known or "add_levels" in known:           # someone who knows the building says how tall it is
        dy = (ymax + known["levels"] * 3.0 + 0.4 - roof["eave"]) if "levels" in known else known["add_levels"] * 3.0
        if abs(dy) > 0.3:
            roof = pickle.loads(pickle.dumps(roof))
            for f in roof["f"]:
                for q in range(2, len(f), 3):
                    f[q] = round(f[q] + dy, 2)
            for w in roof["w"]:
                for q in range(4, len(w), 7):
                    w[q + 1] = round(w[q + 1] + dy, 2)
                    w[q + 3] = round(w[q + 3] + dy, 2)
                    if w[q + 4]:
                        w[q + 5] = round(w[q + 5] + dy, 2)
                        w[q + 6] = round(w[q + 6] + dy, 2)
            for st in roof["s"]:
                st[4], st[5], st[6] = round(st[4] + dy, 2), round(st[5] + dy, 2), round(st[6] + dy, 2)
            roof["eave"] += dy
            roof["top"] += dy
    h = max(2.2, roof["eave"] - ymax)
    small = 1 if (kind in SMALL or a < 45) else 0
    flat = [round(v, 2) for p in pts for v in p]
    r = random.Random(osm_id)
    style = style_of(kind, a, h, roof, r)
    if a < 400 and any(m.contains(shapely.Point(cx, cz)) for m in museums):
        style = OLD_TIMBER                                    # the old farm buildings of the open-air museum
    wall = colour_tag(t.get("building:colour")) or r.choice(WALLS[style])
    pitch, share = roof_shape(roof, a)
    roof_col = colour_tag(t.get("roof:colour")) or r.choice(ROOF_FLAT if share < 0.3 else ROOF_SHEET if style in SHEET_ROOFED else ROOF_TILE)
    if style == OLD_TIMBER:
        roof_col = r.choice([(70, 92, 48), (84, 96, 52), (62, 80, 44)])       # turf
    fronts = []
    if storgata_line is not None and style not in (OUTBUILDING, OLD_TIMBER) and a > 60 and storgata_line.distance(shapely.Point(cx, cz)) < 30:
        # which of its walls look onto Storgata
        for wi, w in enumerate(roof["w"]):
            ln = math.hypot(w[2] - w[0], w[3] - w[1])
            if ln < 4.0:
                continue
            mx, mz = (w[0] + w[2]) / 2, (w[1] + w[3]) / 2
            ox, oz = (w[3] - w[1]) / ln, -(w[2] - w[0]) / ln
            if storgata_line.distance(shapely.Point(mx, mz)) < 13 and storgata_line.distance(shapely.Point(mx + ox * 3, mz + oz * 3)) < storgata_line.distance(shapely.Point(mx, mz)):
                fronts.append(wi)
        if fronts:
            style = MAIN_STREET
            wall = colour_tag(t.get("building:colour")) or r.choice(WALLS[style])
    real = real_colours.get(str(osm_id), {})
    if "wall" in real and not colour_tag(t.get("building:colour")):
        wall = tuple(real["wall"])
        photographed.add(len(buildings))
        n_real[0] += 1
    if "roof" in real and share >= 0.3 and style != OLD_TIMBER and not colour_tag(t.get("roof:colour")):
        roof_col = tuple(real["roof"])
        n_real[1] += 1
    if "wall" in known:
        wall = tuple(known["wall"])
    if "roof" in known:
        roof_col = tuple(known["roof"])
    if "style" in known:
        style = known["style"]
    name = known.get("name", t.get("name", ""))
    if not name and a > 150:
        name = {"terminal": "Molde lufthavn"}.get(t.get("aeroway"), "") or {"hospital": "Molde sjukehus", "university": "Høgskolen i Molde"}.get(kind, "")
    # each wall also gets the ground at its two ends and the lowest ground along it
    walls = []
    for w in roof["w"]:
        ln = math.hypot(w[2] - w[0], w[3] - w[1])
        k = max(1, int(ln / 2))
        gs = [height_at(w[0] + (w[2] - w[0]) * q / k, w[1] + (w[3] - w[1]) * q / k) for q in range(k + 1)]
        walls.append(w[:4] + [round(gs[0], 2), round(gs[-1], 2), round(min(gs), 2)] + w[4:])
    # [small, eave height above the uphill ground, lowest and highest ground at the walls, style, outline, roof,
    #  wall colour, roof colour]
    buildings.append([small, round(h, 1), round(ymin, 2), round(ymax, 2), style, flat,
                      {"f": roof["f"], "w": walls, "s": roof["s"], "top": roof["top"], "sf": fronts}, list(wall), list(roof_col), name, osm_id])
    centres.append((cx, cz))

# a garage or shed is painted like the house it belongs to
from scipy.spatial import cKDTree
homes = [i for i, b in enumerate(buildings) if b[4] in (VILLA, HOUSE60, MODERN, ROW, BARN)]
if homes:
    tree = cKDTree([centres[i] for i in homes])
    for i, b in enumerate(buildings):
        if b[4] == OUTBUILDING and i not in photographed:
            d, j = tree.query(centres[i])
            if d < 30:
                b[7], b[8] = buildings[homes[j]][7], buildings[homes[j]][8]
json.dump(buildings, open(os.path.join(OUT, "buildings.json"), "w"), separators=(",", ":"))
print("  roofs replaced by a plain one:", sum(1 for r in roof_cache.values() if r and r.get("simple")))
print("  large buildings the laser did not see, given a usual height:", n_unseen[0])
print("  measured from laser data:", measured, "flat/pitched/hipped or more:", roof_stats)
print("  buildings:", len(buildings), "with a wall colour from photos:", n_real[0], "with a roof colour from photos:", n_real[1])

# ---------------------------------------------------------------- street furniture
# props.bin (float32, 8 per prop): [kind, x, y, z, a, b, c, d]. A thing standing at a point has a = the way
# it faces (radians, turning from north toward east… as the game's yaw), b = size, c = colour number.
# Something that runs along a line (fence, hedge, wall, wire) is laid in panels: a, b, c = the vector from
# its start to its end. Mapped things are placed where the map has them; lamps along lit streets, garden
# fences and hedges along residential streets, signs at junctions and parked cars are placed by rule.
print("street furniture…")
(LAMP, SHELTER, BUS_SIGN, BENCH, FENCE, HEDGE, WALL, GUARD_RAIL, FLAGPOLE, CAR, GIVE_WAY, ROUND_SIGN, CROSSING_SIGN,
 SIGNAL, POST_BOX, PICNIC, SWINGS, PYLON, WIRES, PICKET, RETAINING, BOAT, FERRY, AIRLINER, VIEWPOINT, GIVE_WAY_ROUND,
 NAME_SIGN, PLANTER, CRUISE, GRAVE) = range(30)
props = []
prng = random.Random(7)


def yaw_of(dx, dz):
    """The game's yaw for something that should face along (dx, dz)."""
    return math.atan2(-dx, -dz)


def put(kind, x, z, yaw=0.0, size=1.0, colour=0.0):
    if inside(x, z, 8):
        y = height_at(x, z)
        if y > 0.6:
            props.append((kind, x, y, z, yaw, size, colour, 0.0))


_run_id = [0]


def run(kind, pts, step=2.5, lift=0.0):
    """Panels along a line, each from one point on the ground to the next. The last number of a panel
    says which line it belongs to (used to find doubles, written out as 0)."""
    _run_id[0] += 1
    for (xa, za), (xb, zb) in zip(pts, pts[1:]):
        ln = math.hypot(xb - xa, zb - za)
        if ln < 0.3:
            continue
        k = max(1, int(round(ln / step)))
        for q in range(k):
            x0, z0 = xa + (xb - xa) * q / k, za + (zb - za) * q / k
            x1, z1 = xa + (xb - xa) * (q + 1) / k, za + (zb - za) * (q + 1) / k
            if inside(x0, z0, 8) and inside(x1, z1, 8):
                y0, y1 = height_at(x0, z0), height_at(x1, z1)
                if min(y0, y1) > 0.6:
                    props.append((kind, x0, y0 + lift, z0, x1 - x0, y1 - y0, z1 - z0, float(_run_id[0])))


# every station of every road: where it is, which way it runs, how wide the road is
_sx, _sd, _sh = [], [], []
for w, st in zip(road_ways, road_st):
    if w[0] != 0:
        continue
    for i, (x, z) in enumerate(st):
        xa, za = st[max(i - 1, 0)]
        xb, zb = st[min(i + 1, len(st) - 1)]
        ln = math.hypot(xb - xa, zb - za) or 1.0
        _sx.append((x, z))
        _sd.append(((xb - xa) / ln, (zb - za) / ln))
        _sh.append(w[1])
station_tree = cKDTree(_sx)


def beside_road(x, z, clear=0.9):
    """Move a point off the carriageway if it is on it. Returns (x, z, direction to the road, distance)."""
    ds, js = station_tree.query((x, z), k=10)
    d, j = float(ds[0]), int(js[0])
    best = None
    for dq, jq in zip(ds, js):                               # the road it stands squarely beside; the widest of them
        if dq > d + 7.0:
            break
        al = (x - _sx[jq][0]) * _sd[jq][0] + (z - _sx[jq][1]) * _sd[jq][1]
        if abs(al) <= 1.8 and (best is None or _sh[jq] > _sh[best] + 0.2):
            best = int(jq)
    if best is not None:
        j = best
        d = math.hypot(x - _sx[j][0], z - _sx[j][1])
    rx, rz = _sx[j]
    dx, dz = _sd[j]
    along = (x - rx) * dx + (z - rz) * dz
    across = -(x - rx) * dz + (z - rz) * dx              # to the right of the road's direction
    sgn = 1.0 if across >= 0 else -1.0
    want = _sh[j] + clear
    if d < 40 and abs(across) < want:
        x, z = rx + dx * along - dz * sgn * want, rz + dz * along + dx * sgn * want
    return x, z, (dz * sgn, -dx * sgn), d


shapely.prepare(road_all)
shapely.prepare(side)
bld_near = bld_union.buffer(1.0)
shapely.prepare(bld_near)
_lamps = []
for t, x, z in osm_nodes:
    hwn = t.get("highway")
    if hwn == "street_lamp":
        x, z, to_road, d = beside_road(x, z)
        put(LAMP, x, z, yaw_of(*to_road))
        _lamps.append((x, z))
    elif hwn == "bus_stop":
        x, z, to_road, d = beside_road(x, z, 2.4)
        if d < 40:
            put(SHELTER if t.get("shelter") != "no" else BUS_SIGN, x, z, yaw_of(*to_road))
    elif hwn == "traffic_signals":
        x, z, to_road, d = beside_road(x, z)
        put(SIGNAL, x, z, yaw_of(*to_road))
    elif t.get("amenity") == "bench":
        x, z, to_road, d = beside_road(x, z)
        put(BENCH, x, z, yaw_of(*to_road) if d < 25 else prng.uniform(0, 6.28))
    elif t.get("man_made") == "flagpole":
        put(FLAGPOLE, x, z, prng.uniform(0, 6.28))
    elif t.get("amenity") == "post_box":
        x, z, to_road, d = beside_road(x, z)
        put(POST_BOX, x, z, yaw_of(*to_road))
    elif t.get("leisure") == "picnic_table":
        put(PICNIC, x, z, prng.uniform(0, 3.14))
for kind, pts in barriers:
    run({"fence": FENCE, "hedge": HEDGE, "wall": WALL, "retaining_wall": RETAINING, "guard_rail": GUARD_RAIL}[kind], pts)
for pts in playgrounds:
    poly = SPoly(pts)
    if poly.is_valid and poly.area > 30:
        c = poly.representative_point()
        put(SWINGS, c.x, c.y, prng.uniform(0, 3.14))
for pts in power_lines:
    for i, (x, z) in enumerate(pts):
        xa, za = pts[max(i - 1, 0)]
        xb, zb = pts[min(i + 1, len(pts) - 1)]
        put(PYLON, x, z, yaw_of(xb - xa, zb - za))
    run(WIRES, pts, 400.0, 21.0)

# lamps along lit streets and the bigger roads, where the map has none
lamp_tree = cKDTree(_lamps) if _lamps else None
for pts, t in way_tags:
    hw = t["highway"]
    if not (t.get("lit") == "yes" or hw in ("trunk", "primary", "secondary", "tertiary") or (hw == "residential" and t.get("lit") != "no")):
        continue
    half = ROAD_W[hw] / 2
    st = stations(pts, 3.0)
    gap = 12 if hw != "residential" else 16
    for i in range(gap // 2, len(st) - 1, gap):
        (xa, za), (xb, zb) = st[i], st[i + 1]
        ln = math.hypot(xb - xa, zb - za) or 1.0
        nx, nz = (zb - za) / ln, -(xb - xa) / ln
        x, z = xa + nx * (half + 0.9), za + nz * (half + 0.9)
        if not inside(x, z, 10) or shapely.contains_xy(road_all, x, z) or shapely.contains_xy(bld_near, x, z):
            continue
        if lamp_tree is not None and lamp_tree.query((x, z))[0] < 22:
            continue
        put(LAMP, x, z, yaw_of(-nx, -nz))

# signs at junctions: give way (with the roundabout sign under it at a roundabout), the speed limit where it
# changes, and the names of the streets where two named streets meet
name_signs = []
_named = set()
for end, (dx, dz), half, back, tg, duty, oneway, key in approaches:
    x, z = end[0] - dx * (back + 1.5) - dz * (half + 0.8), end[1] - dz * (back + 1.5) + dx * (half + 0.8)      # right-hand side
    if duty and not shapely.contains_xy(bld_near, x, z):
        put(GIVE_WAY_ROUND if duty == 2 else GIVE_WAY, x, z, yaw_of(-dx, -dz))
    speed = tg.get("maxspeed", "")
    if speed.isdigit() and not oneway and len(_speeds_at.get(key, ())) > 1:
        x2, z2 = end[0] - dx * (back + 9) + dz * (half + 0.8), end[1] - dz * (back + 9) - dx * (half + 0.8)
        if not shapely.contains_xy(bld_near, x2, z2):
            put(ROUND_SIGN, x2, z2, yaw_of(dx, dz), 1.0, float(speed))
    names = _names_at.get(key, set())
    own = tg.get("name")
    if own and len(names) >= 2 and key not in _named:
        x3, z3 = end[0] - dx * (back + 0.5) + dz * (half + 0.9), end[1] - dz * (back + 0.5) - dx * (half + 0.9)   # left-hand corner
        if inside(x3, z3, 10) and height_at(x3, z3) > 0.6 and not shapely.contains_xy(bld_near, x3, z3) and not shapely.contains_xy(road_all, x3, z3):
            _named.add(key)
            put(NAME_SIGN, x3, z3, yaw_of(dx, dz))
            name_signs.append([round(x3, 2), round(height_at(x3, z3), 2), round(z3, 2), round(yaw_of(dx, dz), 3), own, sorted(names - {own})[0]])
# a blue sign at both ends of every zebra crossing
for w in road_ways:
    if w[0] == 2 and len(w[5]) >= 2:
        (xa, za), (xb, zb) = w[5][0], w[5][-1]
        ln = math.hypot(xb - xa, zb - za)
        if ln > 3.0:
            ux, uz = (xb - xa) / ln, (zb - za) / ln
            put(CROSSING_SIGN, xa - ux * 0.4 + uz * 1.8, za - uz * 0.4 - ux * 1.8, yaw_of(uz, -ux))
            put(CROSSING_SIGN, xb + ux * 0.4 - uz * 1.8, zb + uz * 0.4 + ux * 1.8, yaw_of(-uz, ux))

# cars: rows in the car parks, a few along residential streets
n_cars = 0
for pts in parkings:
    poly = SPoly(pts)
    if not poly.is_valid or poly.area < 60:
        continue
    P = np.asarray(pts[:-1] if pts[0] == pts[-1] else pts)
    seg = np.roll(P, -1, 0) - P
    k = int(np.argmax((seg ** 2).sum(1)))
    u = seg[k] / np.hypot(*seg[k])
    v = np.array([-u[1], u[0]])
    c = P.mean(0)
    pu, pv = (P - c) @ u, (P - c) @ v
    inner = poly.buffer(-1.3)
    row = pv.min() + 2.9
    k = 0
    while row < pv.max() - 2.0:
        a = pu.min() + 1.6
        while a < pu.max() - 1.2:
            q = c + u * a + v * row
            if prng.random() < 0.42 and station_tree.query((q[0], q[1]))[0] > 4.6 and inner.contains(shapely.Point(q)) and inner.contains(shapely.Point(q + v * 1.9)) and inner.contains(shapely.Point(q - v * 1.9)):
                put(CAR, q[0], q[1], yaw_of(*v) + (math.pi if prng.random() < 0.5 else 0.0), 1.0, prng.randrange(8))
                n_cars += 1
            a += 2.7
        row += 5.4 if k % 2 == 0 else 11.6                         # two rows nose to nose, then an aisle
        k += 1
for w, st in zip(road_ways, road_st):
    if w[0] != 0 or abs(w[1] - 2.75) > 0.3:
        continue
    for i in range(3, len(st) - 3):
        if prng.random() < 0.012 and junction_tree is not None and junction_tree.query(st[i])[0] > 14:
            (xa, za), (xb, zb) = st[i - 1], st[i + 1]
            ln = math.hypot(xb - xa, zb - za) or 1.0
            dx, dz = (xb - xa) / ln, (zb - za) / ln
            x, z = st[i][0] - dz * (w[1] - 1.15), st[i][1] + dx * (w[1] - 1.15)       # at the right-hand kerb
            put(CAR, x, z, yaw_of(dx, dz), 1.0, prng.randrange(8))
            n_cars += 1

# garden boundaries along residential streets: a hedge, a picket fence or a plain fence in front of some
# houses, open at every driveway and path
_homes = [i for i, b in enumerate(buildings) if b[4] in (VILLA, HOUSE60, MODERN, ROW)]
home_tree = cKDTree([centres[i] for i in _homes])
gaps = shapely.STRtree([LineString(w[5]) for w in road_ways if (w[0] == 0 and w[1] <= 1.8) or w[0] in (1, 3)] +
                       [LineString(b[2]) for b in bridges])
gap_geoms = gaps.geometries
n_garden = 0
for w, st in zip(road_ways, road_st):
    if w[0] != 0 or not (2.4 <= w[1] <= 3.5) or len(st) < 3:
        continue
    S = np.asarray(st)
    T = np.gradient(S, axis=0)
    T /= np.maximum(np.hypot(T[:, 0], T[:, 1]), 1e-6)[:, None]
    N = np.stack([T[:, 1], -T[:, 0]], 1)
    jd = junction_tree.query(S)[0] if junction_tree is not None else np.full(len(S), 1e9)
    for sgn in (1.0, -1.0):
        walk = shapely.contains_xy(side, S[:, 0] + N[:, 0] * sgn * (w[1] + 1.0), S[:, 1] + N[:, 1] * sgn * (w[1] + 1.0))
        P = S + N * sgn * (w[1] + np.where(walk, 2.7, 1.3))[:, None]
        hd, hj = home_tree.query(P)
        ok = (hd < 20) & (jd > w[1] + 6) & ~shapely.contains_xy(road_all, P[:, 0], P[:, 1]) & ~shapely.contains_xy(side, P[:, 0], P[:, 1]) \
            & ~shapely.contains_xy(bld_near, P[:, 0], P[:, 1])
        line = []
        last = None
        for i in range(len(P) + 1):
            style = None
            if i < len(P) and ok[i]:
                pick = (int(hj[i]) * 2654435761 >> 7) % 6
                style = (HEDGE, PICKET, FENCE)[pick - 3] if pick >= 3 else None
                if style is not None:
                    near = gaps.query_nearest(shapely.Point(P[i]), max_distance=3.4)
                    if len(near):
                        style = None
            if style is not None and (last is None or (style, int(hj[i])) == last):
                line.append((float(P[i][0]), float(P[i][1])))
                last = (style, int(hj[i]))
                continue
            if len(line) >= 2:
                run(last[0], line, 3.0)
                n_garden += len(line) - 1
            line = [(float(P[i][0]), float(P[i][1]))] if style is not None else []
            last = (style, int(hj[i])) if style is not None else None
# boats along the jetties, a ferry at the ferry quay, an airliner on a stand, a railing and a telescope at viewpoints
def seaward(x, z, reach):
    """The direction (unit vector) in which the ground falls away most within `reach` metres."""
    best, out = 1e9, (0.0, 1.0)
    for k in range(16):
        dx, dz = math.cos(k * math.pi / 8), math.sin(k * math.pi / 8)
        h = sum(height_at(x + dx * reach * f, z + dz * reach * f) for f in (0.4, 0.7, 1.0)) if inside(x + dx * reach, z + dz * reach, 5) else 1e9
        if h < best:
            best, out = h, (dx, dz)
    return out


# Storgata: tubs of flowers and benches along the sidewalks
def crowded(x, z, r):
    return any(q[0] not in (FENCE, HEDGE, WALL, GUARD_RAIL, WIRES, PICKET, RETAINING) and abs(q[1] - x) < r and abs(q[3] - z) < r
               and math.hypot(q[1] - x, q[3] - z) < r for q in props)


for pts in storgata:
    st = stations(pts, 21.0)
    for i in range(1, len(st) - 1):
        (xa, za), (xb, zb) = st[i - 1], st[i + 1]
        ln = math.hypot(xb - xa, zb - za) or 1.0
        nx, nz = (zb - za) / ln, -(xb - xa) / ln
        sgn = 1.0 if i % 2 else -1.0
        off = ROAD_W[tags_of[id(pts)]["highway"]] / 2 + 1.5
        x, z = st[i][0] + nx * sgn * off, st[i][1] + nz * sgn * off
        if shapely.contains_xy(bld_near, x, z) or shapely.contains_xy(road_all, x, z) or crowded(x, z, 5.0):
            continue
        if i % 3 == 0:
            put(BENCH, x, z, yaw_of(-nx * sgn, -nz * sgn))
        else:
            put(PLANTER, x, z, prng.uniform(0, 6.28), 1.0, prng.randrange(3))
# cemeteries: rows of gravestones, all facing the same way, with the paths and roads through them left clear
n_graves = 0
_walks = unary_union([LineString(w[5]).buffer(w[1] + 1.2) for w in road_ways if w[0] in (0, 3, 7, 8) and len(w[5]) >= 2])
shapely.prepare(_walks)
for pts in cemeteries:
    poly = SPoly(pts)
    if not poly.is_valid or poly.area < 400:
        continue
    inner = poly.buffer(-2.5)
    if inner.is_empty:
        continue
    r = list(poly.minimum_rotated_rectangle.exterior.coords)[:4]
    e0, e1 = np.subtract(r[1], r[0]), np.subtract(r[2], r[1])
    if np.hypot(*e0) < np.hypot(*e1):
        e0, e1 = e1, e0
    u, v = e0 / np.hypot(*e0), e1 / np.hypot(*e1)
    L, W = float(np.hypot(*e0)), float(np.hypot(*e1))
    o = np.array(r[0]) if np.allclose(np.subtract(r[1], r[0]), e0) else np.array(r[1])
    gu, gv = np.meshgrid(np.arange(1.5, L, 2.3), np.arange(2.0, W, 4.4))
    P = o + gu.ravel()[:, None] * u + gv.ravel()[:, None] * v
    ok = shapely.contains_xy(inner, P[:, 0], P[:, 1]) & ~shapely.contains_xy(_walks, P[:, 0], P[:, 1]) \
        & ~shapely.contains_xy(bld_near, P[:, 0], P[:, 1])
    yaw = yaw_of(v[0], v[1])
    for x, z in P[ok]:
        if prng.random() < 0.82 and inside(x, z, 8):
            y = height_at(x, z)
            if y > 0.6:
                props.append((GRAVE, float(x), y, float(z), yaw + prng.uniform(-0.04, 0.04), prng.uniform(0.75, 1.25), float(prng.randrange(4)), 0.0))
                n_graves += 1
print("  gravestones:", n_graves)
# the golf course: a flag on a green here and there, where the ground is open (the course itself is not mapped in
# detail, so where the greens are is made up)
golf = []
_tree_xy = cKDTree(np.asarray(trees, np.float32)[:, :2])
for poly in golf_polys:
    inner = poly.buffer(-18.0)
    x0g, z0g, x1g, z1g = poly.bounds
    for gx in np.arange(x0g + 40, x1g, 95.0):
        for gz in np.arange(z0g + 40, z1g, 95.0):
            x, z = gx + prng.uniform(-22, 22), gz + prng.uniform(-22, 22)
            if inner.contains(shapely.Point(x, z)) and _tree_xy.query((x, z))[0] > 14 and height_at(x, z) > 1.0 \
                    and not shapely.contains_xy(bld_near, x, z) and not shapely.contains_xy(road_all, x, z):
                golf.append([round(float(x), 1), round(float(z), 1), round(prng.uniform(0, 6.28), 2)])
print("  golf greens:", len(golf))
n_boats = 0
for pier in piers:
    if pier["closed"] or pier["kind"] != "pier":
        continue
    line = list(zip(pier["pts"][0::2], pier["pts"][1::2]))
    st = stations(line, 5.5)
    for i in range(1, len(st) - 1):
        (xa, za), (xb, zb) = st[i - 1], st[i + 1]
        ln = math.hypot(xb - xa, zb - za) or 1.0
        nx, nz = (zb - za) / ln, -(xb - xa) / ln
        for sgn in (1.0, -1.0):
            x, z = st[i][0] + nx * sgn * 5.2, st[i][1] + nz * sgn * 5.2
            if prng.random() < 0.45 and inside(x, z, 10) and height_at(x, z) < -0.5:
                props.append((BOAT, x, 0.0, z, yaw_of(-nx * sgn, -nz * sgn), prng.uniform(0.8, 1.25), prng.randrange(8), 0.0))
                n_boats += 1
_quays = []
for t, x, z in osm_nodes:
    if t.get("amenity") == "ferry_terminal" and inside(x, z, 120) and all(math.hypot(x - qx, z - qz) > 250 for qx, qz in _quays):
        dx, dz = seaward(x, z, 60.0)
        fx, fz = x + dx * 62.0, z + dz * 62.0
        cr = overrides.CRUISE_AT
        if cr and coasts and math.hypot(x - cr[0], z - cr[1]) < 150:
            # a cruise ship alongside: parallel to the shore line there, in water deep enough along its whole length
            shore = min((LineString(q) for q in coasts), key=lambda q: q.distance(shapely.Point(cr)))
            s0 = shore.project(shapely.Point(cr))
            a, b = shore.interpolate(max(0.0, s0 - 40)), shore.interpolate(min(shore.length, s0 + 40))
            ln = math.hypot(b.x - a.x, b.y - a.y) or 1.0
            tx, tz = (b.x - a.x) / ln, (b.y - a.y) / ln
            base = shore.interpolate(s0)
            nx, nz = tz, -tx
            if height_at(base.x + nx * 40, base.y + nz * 40) > height_at(base.x - nx * 40, base.y - nz * 40):
                nx, nz = -nx, -nz
            off = 22.0
            while off < 140 and any(height_at(base.x + nx * off + tx * q, base.y + nz * off + tz * q) > -1.0
                                    or height_at(base.x + nx * (off - 13) + tx * q, base.y + nz * (off - 13) + tz * q) > -0.5
                                    for q in range(-90, 91, 15)):
                off += 4.0
            props.append((CRUISE, base.x + nx * off, 0.0, base.y + nz * off, yaw_of(tx, tz), 1.0, 0.0, 0.0))
            _quays.append((x, z))
        elif inside(fx, fz, 60) and height_at(fx, fz) < -1.0:
            props.append((FERRY, fx, 0.0, fz, yaw_of(-dx, -dz), 1.0, 0.0, 0.0))
            _quays.append((x, z))
    elif t.get("tourism") == "viewpoint" and inside(x, z, 20) and height_at(x, z) > 2.0:
        dx, dz = seaward(x, z, 25.0)
        put(VIEWPOINT, x, z, yaw_of(dx, dz))
for k, pts in enumerate(stands):
    if k % 3 == 0 and len(pts) >= 2:
        (xa, za), (xb, zb) = pts[0], pts[-1]
        put(AIRLINER, (xa + xb) / 2, (za + zb) / 2, yaw_of(xb - xa, zb - za))
for x, z in overrides.PLAYGROUNDS:
    put(SWINGS, x, z, prng.uniform(0, 3.14))
    put(PICNIC, x + 5.0, z + 2.0, prng.uniform(0, 3.14))
    put(BENCH, x - 4.5, z + 3.0, yaw_of(4.5, -3.0))
statues = [{"kind": q["kind"], "x": q["at"][0], "z": q["at"][1], "y": round(height_at(*q["at"]), 2), "h": q["height"]} for q in overrides.STATUES]
sandpits = [[x, z, 5.5] for x, z in overrides.PLAYGROUNDS]
# Benches round a pond face away from the water; and what stands in the middle of it.
fountains = []
for ring in ponds:
    pond = SPoly(ring)
    cx, cz = pond.centroid.x, pond.centroid.y
    reach = math.sqrt(pond.area / math.pi) + 16.0
    for k, pr in enumerate(props):
        if int(pr[0]) == BENCH and math.hypot(pr[1] - cx, pr[3] - cz) < reach:
            props[k] = (pr[0], pr[1], pr[2], pr[3], yaw_of(pr[1] - cx, pr[3] - cz)) + tuple(pr[5:])
    kind = next((q["fountain"] for q in overrides.PONDS), "")
    fountains.append({"x": round(cx, 2), "z": round(cz, 2), "y": round(max(height_at(x, z) for x, z in ring) - 0.25 + overrides.WHALE_LIFT, 2), "kind": kind})
# things that are not there
props = [pr for pr in props if not (int(pr[0]) in (CROSSING_SIGN, GIVE_WAY, GIVE_WAY_ROUND) and any(math.hypot(pr[1] - qx, pr[3] - qz) < qr for qx, qz, qr in overrides.NO_MARKINGS))]
props = [pr for pr in props if int(pr[0]) in (FENCE, HEDGE, WALL, GUARD_RAIL, WIRES, PICKET, RETAINING)
         or all(math.hypot(pr[1] - x, pr[3] - z) > 2.0 for x, z in overrides.NO_PROPS)]
# signs by doors: on the wall of the building nearest the point, facing out
door_signs = []
for q in overrides.DOOR_SIGNS:
    best = None
    for b in buildings:
        if "osm_id" in q and b[10] != q["osm_id"]:
            continue
        o = b[5]
        n_ = len(o) // 2
        for i in range(n_):
            ax, az, bx, bz = o[2 * i], o[2 * i + 1], o[(2 * i + 2) % len(o)], o[(2 * i + 3) % len(o)]
            ln = math.hypot(bx - ax, bz - az)
            if ln < 0.5:
                continue
            t_ = max(0.0, min(1.0, ((q["at"][0] - ax) * (bx - ax) + (q["at"][1] - az) * (bz - az)) / (ln * ln)))
            px_, pz_ = ax + (bx - ax) * t_, az + (bz - az) * t_
            d_ = math.hypot(px_ - q["at"][0], pz_ - q["at"][1])
            if best is None or d_ < best[0]:
                nx_, nz_ = (bz - az) / ln, -(bx - ax) / ln
                if (q["at"][0] - px_) * nx_ + (q["at"][1] - pz_) * nz_ < 0 and d_ > 0.05:
                    nx_, nz_ = -nx_, -nz_
                c_ = np.mean(np.asarray(o).reshape(-1, 2), 0)
                if (px_ - c_[0]) * nx_ + (pz_ - c_[1]) * nz_ < 0:
                    nx_, nz_ = -nx_, -nz_
                best = (d_, px_, pz_, nx_, nz_)
    if best is not None and (best[0] < 6.0 or "osm_id" in q):
        y_ = height_at(best[1], best[2]) + 1.55
        if q.get("window"):                                   # an upstairs window: a floor up, but under the eaves
            b_ = next(b for b in buildings if b[10] == q["osm_id"])
            y_ = float(np.median([w[8] for w in b_[6]["w"]])) - 1.3   # the top floor: just under the eaves, as the walls are built
        door_signs.append([round(best[1], 2), round(y_, 2), round(best[2], 2), round(best[3], 4), round(best[4], 4), q["text"],
                           1 if q.get("shop") else (2 if q.get("window") else 0)])

# Last check: nothing stands where cars drive. A thing found on a carriageway is moved to the nearest
# roadside if that is close and free, otherwise it is dropped; a fence or wall loses the panels that cross.
_clear = {SHELTER: 1.7, BENCH: 0.7, PICNIC: 1.1, SWINGS: 1.6, PYLON: 1.5, CAR: 1.0, PLANTER: 0.7}
_linear = {FENCE, HEDGE, WALL, GUARD_RAIL, PICKET, RETAINING}
_skip = {WIRES, BOAT, FERRY, AIRLINER, CRUISE, GRAVE}
_zone = {}


def _zone_of(c):
    if c not in _zone:
        g = drive.buffer(c, quad_segs=3)
        shapely.prepare(g)
        _zone[c] = (g, drive.buffer(c + 0.08, quad_segs=3).boundary)
    return _zone[c]


_edge = drive.buffer(-0.25)
shapely.prepare(_edge)
_out, n_moved, n_dropped = [], 0, 0
for pr in props:
    kind = int(pr[0])
    if kind in _skip:
        _out.append(pr)
    elif kind == GUARD_RAIL:                              # belongs at the edge of the road: push it out to there
        zone, rim = _zone_of(0.3)
        ends = []
        for x, z in ((pr[1], pr[3]), (pr[1] + pr[4], pr[3] + pr[6])):
            if shapely.contains_xy(zone, x, z):
                q = shapely.ops.nearest_points(rim, shapely.Point(x, z))[0]
                x, z = (q.x, q.y) if math.hypot(q.x - x, q.y - z) < 6.0 else (None, None)
            ends.append((x, z))
        (xa, za), (xb, zb) = ends
        if xa is None or xb is None or not 0.3 < math.hypot(xb - xa, zb - za) < 6.0 or shapely.intersects(_edge, LineString(ends)):
            n_dropped += 1
        else:
            ya, yb = height_at(xa, za), height_at(xb, zb)
            _out.append((pr[0], xa, ya, za, xb - xa, yb - ya, zb - za, pr[7]))
            n_moved += 1
    elif kind in _linear:
        if shapely.intersects(_edge, LineString([(pr[1], pr[3]), (pr[1] + pr[4], pr[3] + pr[6])])):
            n_dropped += 1
        else:
            _out.append(pr)
    else:
        zone, rim = _zone_of(_clear.get(kind, 0.4))
        if not shapely.contains_xy(zone, pr[1], pr[3]):
            _out.append(pr)
            continue
        q = shapely.ops.nearest_points(rim, shapely.Point(pr[1], pr[3]))[0]
        if kind in (CAR, NAME_SIGN) or math.hypot(q.x - pr[1], q.y - pr[3]) > 5.0 or shapely.contains_xy(bld_near, q.x, q.y) \
                or not inside(q.x, q.y, 8) or height_at(q.x, q.y) <= 0.6:
            n_dropped += 1
            continue
        _out.append((pr[0], q.x, height_at(q.x, q.y), q.y) + tuple(pr[4:]))
        n_moved += 1
props = _out

# No doubles: a railing, fence, hedge or wall that runs alongside another one closer than 2.4 m is dropped
# (the first one placed stays: what the map has before what the rules add), and so is one along a bridge,
# which has railings of its own.
_deck = unary_union([LineString(b[2]).buffer(b[0] + 1.3, cap_style="flat") for b in bridges if len(b[2]) >= 2]) if bridges else None
if _deck is not None:
    shapely.prepare(_deck)
_grid, _out, n_double = {}, [], 0
for pr in props:
    kind = int(pr[0])
    if kind not in _linear:
        _out.append(pr)
        continue
    ax, az, bx, bz = pr[1], pr[3], pr[1] + pr[4], pr[3] + pr[6]
    mx, mz = (ax + bx) / 2, (az + bz) / 2
    ln = math.hypot(bx - ax, bz - az) or 1.0
    ux, uz = (bx - ax) / ln, (bz - az) / ln
    double = _deck is not None and kind != RETAINING and shapely.contains_xy(_deck, mx, mz)
    cx, cz = int(mx // 4), int(mz // 4)
    if not double:
        for gx in (cx - 1, cx, cx + 1):
            for gz in (cz - 1, cz, cz + 1):
                for (qx, qz, vx, vz, half, rid) in _grid.get((gx, gz), ()):
                    if rid == pr[7] or abs(ux * vx + uz * vz) < 0.75:
                        continue
                    along = (mx - qx) * vx + (mz - qz) * vz
                    if abs(along) < half + 0.4 and abs(-(mx - qx) * vz + (mz - qz) * vx) < 2.4:
                        double = True
    if double:
        n_double += 1
        continue
    _grid.setdefault((cx, cz), []).append((mx, mz, ux, uz, ln / 2, pr[7]))
    _out.append(pr)
props = [tuple(pr[:7]) + (0.0,) if int(pr[0]) in _linear or int(pr[0]) == WIRES else pr for pr in _out]
print("  double railings and fences removed:", n_double)
_z = _zone_of(0.4)[0]
name_signs = [q for q in name_signs if not shapely.contains_xy(_z, q[0], q[2])]
print("  on the carriageway: moved", n_moved, "dropped", n_dropped)
np.asarray(props, np.float32).tofile(os.path.join(OUT, "props.bin"))
print("  boats:", n_boats, "ferries:", len(_quays))
print("  props:", len(props), "cars:", n_cars, "garden panels:", n_garden)

# No wrecks or barricades in the streets.
wrecks = []
with open(os.path.join(OUT, "wrecks.bin"), "wb") as f:
    f.write(b"")


skywalks = []
for sk in overrides.SKYWALKS:
    st = stations(list(sk["pts"]), 2.0)
    y = sk["y"] if sk["y"] is not None else max(height_at(x, z) for x, z in st) + 5.0
    skywalks.append({"pts": [round(float(v), 2) for q in sk["pts"] for v in q], "w": sk["w"], "y": round(float(y), 2)})
canopies = []
for pts in canopy_ways:
    r = list(SPoly(pts).minimum_rotated_rectangle.exterior.coords)[:4]
    c = np.mean(r, 0)
    e0, e1 = np.subtract(r[1], r[0]), np.subtract(r[2], r[1])
    if np.hypot(*e0) < np.hypot(*e1):
        e0, e1 = e1, e0
    canopies.append({"c": [round(float(c[0]), 2), round(float(c[1]), 2)], "u": [round(float(e0[0] / np.hypot(*e0)), 4), round(float(e0[1] / np.hypot(*e0)), 4)],
                     "hl": round(float(np.hypot(*e0)) / 2, 2), "hw": round(float(np.hypot(*e1)) / 2, 2),
                     "ground": round(height_at(float(c[0]), float(c[1])), 2), "h": 5.4})

# Tunnel mouths: not the joints between two stretches of the same tunnel, and not out in the sea.
_seen = {}
for q in portals:
    _seen[(q["x"], q["z"])] = _seen.get((q["x"], q["z"]), 0) + 1
portals = [q for q in portals if q.get("keep") or (_seen[(q["x"], q["z"])] == 1 and height_at(q["x"], q["z"]) > 1.0)]

# ---------------------------------------------------------------- street names, places, spawn
def simplify(pts, step=12.0):
    out = [pts[0]]
    for p in pts[1:-1]:
        if math.hypot(p[0] - out[-1][0], p[1] - out[-1][1]) >= step:
            out.append(p)
    out.append(pts[-1])
    return out


street_out = []
for name, lines in streets.items():
    for line in lines:
        s = [p for p in simplify(line) if inside(p[0], p[1])]
        if len(s) >= 2:
            street_out.append([name, [round(v, 1) for p in s for v in p]])

# Spawn: the middle of Rådhusplassen, in front of the town hall.
px_ = plaza[0::2]
pz_ = plaza[1::2]
spawn = [round(sum(px_) / len(px_), 1), round(sum(pz_) / len(pz_), 1)]

# The landscape far outside the map, for the view: the mountains across the fjord and the coast, 96 km across.
from kartverket import backdrop
BACK_HALF, BACK_N = 48000.0, 641
backdrop(BACK_HALF, 100, BACK_N).tofile(os.path.join(OUT, "backdrop.bin"))

meta = {
    "backdrop": {"half": BACK_HALF, "n": BACK_N}, "name_signs": name_signs,
    "x0": X0, "z0": Z0, "x1": X1, "z1": Z1, "cell": CELL, "gw": GW, "gh": GH,
    "mask_res": MASK_RES, "fine": {"w": FW, "h": FH, "strip": STRIP, "scale": H_SCALE, "offset": H_OFFSET}, "lat0": LAT0, "lon0": LON0,
    "spawn": spawn, "places": places, "pois": pois, "streets": street_out, "fires": fires, "landmarks": landmarks, "plaza": plaza,
    "stadium": stadium, "piers": piers, "portals": portals,
    "quays": quays, "sports": sports, "canopies": canopies, "skywalks": skywalks, "fields": fields, "golf": golf, "courts": courts, "fountains": fountains, "door_signs": door_signs, "mercedes": list(overrides.MERCEDES_AT), "bicycle": list(overrides.BICYCLE_AT), "statues": statues, "sandpits": sandpits,
    "plaza_tris": plaza_tris, "radhus_steps": radhus_steps, "rosepiken": list(overrides.ROSEPIKEN),
    "doors": {k: [list(d) for d in v] for k, v in overrides.DOORS.items()},
    "attribution": "Map data © OpenStreetMap contributors (ODbL). Terrain, building heights and roofs: © Kartverket, hoydedata.no.",
}
json.dump(meta, open(os.path.join(OUT, "meta.json"), "w"), ensure_ascii=False, separators=(",", ":"))
print("  trees:", len(trees), "wrecks:", len(wrecks), "streets:", len(street_out), "places:", len(places), "spawn:", spawn)

# ---------------------------------------------------------------- overview image for a sanity check
ov = np.zeros((GH, GW, 3), np.uint8)
shade = np.clip(H / 450.0, 0, 1)
ov[..., 0] = 60 + 120 * shade
ov[..., 1] = 90 + 110 * shade
ov[..., 2] = 60 + 90 * shade
ov[forest_g] = (ov[forest_g] * 0.6).astype(np.uint8)
ov[sea] = (40, 70, 110)
ov[lake_g > 0.3] = (60, 100, 150)
ov[path_g > 0.15 if (path_g := to_grid(path_im)) is not None else False] = (190, 170, 130)
ov[road_g > 0.15] = (235, 235, 235)
ovim = Image.fromarray(ov).resize((GW * 2, GH * 2), Image.NEAREST)
d = ImageDraw.Draw(ovim)
for small, h, ymin, ymax, style, flat, *_ in buildings:
    p = [((flat[i] - X0) / 5, (flat[i + 1] - Z0) / 5) for i in range(0, len(flat), 2)]
    c = (250, 220, 120)
    d.polygon(p, fill=c)
sx, sz = (spawn[0] - X0) / 5, (spawn[1] - Z0) / 5
d.ellipse((sx - 8, sz - 8, sx + 8, sz + 8), outline=(255, 0, 255), width=3)
ovim.save(os.path.join(DATA, "overview.png"))
print("done")
