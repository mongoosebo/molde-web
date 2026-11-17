#!/usr/bin/env python3
"""All-round road photos from Statens vegvesen's Vegbilder (open data, NLOD) along a named street.

Vegbilder covers the European, national and county roads: every few metres a 360° photo, taken from a car
roof, with where it was taken and which way the car was heading. Run as

    python3 vegbilder.py Storgata [year]

to list the photos within 30 m of the ways with that name into data/vegbilder/images.json (added to what is
there). tools/colours.py reads wall colours off them. The photos themselves are kept, at half size, in
data/vegbilder/img/ (not in the repository). The links to them run out after some hours, so the list is
fetched anew before photos are downloaded.
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import LAT0, LON0, MX, MZ, to_latlon

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "vegbilder")
IMG = os.path.join(DIR, "img")
WFS = "https://ogckart-sn1.atlas.vegvesen.no/vegbilder_1_0/ows"
EYE = 2.8             # camera height above the road


def street(name):
    """The lines of the ways with this name, in the game's frame."""
    out = []
    for e in json.load(open(os.path.join(ROOT, "data", "osm_raw.json")))["elements"]:
        t = e.get("tags", {})
        if e["type"] == "way" and t.get("name") == name and "highway" in t and e.get("geometry"):
            out.append([((p["lon"] - LON0) * MX, (LAT0 - p["lat"]) * MZ) for p in e["geometry"]])
    return out


def listing(x0, z0, x1, z1, year):
    """Every 360° photo of a year in a box of the game's frame."""
    north, west = to_latlon(x0, z0)
    south, east = to_latlon(x1, z1)
    rows, start = [], 0
    while True:
        url = (f"{WFS}?service=WFS&version=2.0.0&request=GetFeature&typeNames=vegbilder_1_0:Vegbilder_360_{year}"
               f"&outputFormat=application/json&count=2000&startIndex={start}&bbox={west:.6f},{south:.6f},{east:.6f},{north:.6f},EPSG:4326")
        out = subprocess.run(["curl", "-s", "-m", "120", "-A", "map-builder/1.0", url], capture_output=True, text=True).stdout
        try:
            feats = json.loads(out)["features"]
        except (ValueError, KeyError):
            break
        for f in feats:
            p, (lon, lat) = f["properties"], f["geometry"]["coordinates"]
            rows.append({"id": f["id"].split(".", 1)[1], "x": round((lon - LON0) * MX, 2), "z": round((LAT0 - lat) * MZ, 2),
                         "heading": round(p["RETNING"], 2), "year": p["AAR"], "time": p["TIDSPUNKT"],
                         "road": f"{p['VEGKATEGORI']}{p['VEGNUMMER']}", "run": f"{p['VEGKATEGORI']}{p['VEGNUMMER']}-{p['FELTKODE']}-{p['TIDSPUNKT'][:10]}",
                         "url": p["URL"]})
        if len(feats) < 2000:
            break
        start += 2000
    return rows


def along(name, year):
    from shapely.geometry import LineString, Point
    from shapely.ops import unary_union
    lines = street(name)
    if not lines:
        return []
    line = unary_union([LineString(l) for l in lines if len(l) >= 2])
    x0, z0, x1, z1 = line.bounds
    return [r for r in listing(x0 - 60, z0 - 60, x1 + 60, z1 + 60, year) if line.distance(Point(r["x"], r["z"])) < 30.0]


def fetch(row):
    """The photo of a listed row, at half size (4096 x 2048), as a file path; None if it cannot be had."""
    from PIL import Image
    path = os.path.join(IMG, row["id"].replace(":", "-") + ".jpg")
    if os.path.exists(path) and os.path.getsize(path) > 20000:
        return path
    os.makedirs(IMG, exist_ok=True)
    tmp = path + ".part"
    subprocess.run(["curl", "-s", "-m", "180", "-A", "map-builder/1.0", "-o", tmp, row["url"]])
    try:
        Image.open(tmp).convert("RGB").resize((4096, 2048), Image.LANCZOS).save(path, quality=88)
    except Exception:
        return None
    finally:
        if os.path.exists(tmp):
            os.remove(tmp)
    return path


if __name__ == "__main__":
    name = sys.argv[1]
    year = int(sys.argv[2]) if len(sys.argv) > 2 else 2025
    rows = along(name, year)
    os.makedirs(DIR, exist_ok=True)
    path = os.path.join(DIR, "images.json")
    seen = {r["id"]: r for r in (json.load(open(path)) if os.path.exists(path) else [])}
    for r in rows:
        seen[r["id"]] = dict(r, street=name)
    json.dump(list(seen.values()), open(path, "w"))
    print(name, year, "photos:", len(rows), "listed in all:", len(seen))
