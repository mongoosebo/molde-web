#!/usr/bin/env python3
"""What the national road database (NVDB, Statens vegvesen; open data under NLOD) knows about the roads of Molde.

  tools/nvdb.py            fetch the kinds of thing listed in KINDS for Molde kommune (1506) into data/nvdb/<id>.json
                           (kept; a kind already there is not fetched again), and print for each how many lie inside
                           the game's map, split by who owns the road: E/R state, F county, K town, P private
  tools/nvdb.py --again    fetch afresh

Each kept object: {"id", "x", "z" (the middle of it, game metres), "pts" (its line or outline, [x, z, ...]),
"road" (E, R, F, K, P or S), "p": {name of property: value}, "ref" (the road and stretch, as "FV6238 S1D1"),
"m" (metres along that stretch), "side" (H right or V left of the road, seen the way its metres run), "of" (what it hangs on)}.
"""
import json, os, re, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import LAT0, LON0, MX, MZ, X0, X1, Z0, Z1

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "nvdb")
API = "https://nvdbapiles.atlas.vegvesen.no/vegobjekter/api/v4/vegobjekter/%d?kommune=1506&inkluder=lokasjon,geometri,egenskaper,relasjoner&srid=4326&antall=1000"
KINDS = {174: "pedestrian crossings", 95: "sign posts", 96: "sign plates", 25: "bus shelters", 487: "bus stop fittings", 87: "street lights",
         48: "sidewalks", 9: "kerbs", 49: "traffic islands", 5: "guard rails", 7: "fences", 511: "bushes", 274: "flower beds",
         103: "speed bumps", 241: "road surface", 15: "grass verges", 90: "signal points", 47: "lay-bys", 172: "traffic dividers"}


def get(url):
    out = subprocess.run(["curl", "-s", "-m", "120", "-H", "X-Client: map-tool", "-H", "Accept: application/json", url], capture_output=True, text=True).stdout
    return json.loads(out)


def points(wkt):
    nums = [float(v) for v in re.findall(r"-?\d+\.?\d*(?:[eE]-?\d+)?", wkt.split("(", 1)[1])] if "(" in wkt else []
    dim = 3 if " Z" in wkt.split("(", 1)[0] or (len(nums) % 3 == 0 and len(nums) % 2 != 0) else 2
    pts = []
    for i in range(0, len(nums) - dim + 1, dim):
        lat, lon = nums[i], nums[i + 1]
        pts += [round((lon - LON0) * MX, 2), round((LAT0 - lat) * MZ, 2)]
    return pts


def fetch(kind):
    url, rows = API % kind, []
    while url:
        d = get(url)
        for o in d.get("objekter", []):
            g = (o.get("geometri") or {}).get("wkt")
            if not g:
                continue
            pts = points(g)
            if len(pts) < 2:
                continue
            xs, zs = pts[0::2], pts[1::2]
            x, z = sum(xs) / len(xs), sum(zs) / len(zs)
            refs = (o.get("lokasjon") or {}).get("vegsystemreferanser") or []
            road = ((refs[0].get("vegsystem") or {}).get("vegkategori") if refs else None) or "?"
            props = {p["navn"]: p.get("verdi") for p in o.get("egenskaper", []) if p.get("egenskapstype") != "Geometri" and "verdi" in p}
            row = {"id": o["id"], "x": round(x, 2), "z": round(z, 2), "pts": pts if len(pts) <= 400 else pts[:400], "road": road, "p": props}
            if refs:                                       # where along which road, and on which side of it
                st, ml = refs[0].get("strekning") or {}, refs[0].get("metrertLokasjon") or {}
                row["ref"] = re.sub(r" m\d+.*$", "", refs[0].get("kortform") or "")
                if "meter" in st:
                    row["m"] = round(st["meter"], 1)
                row["side"] = ml.get("sideposisjon") or ""
            par = [v for f in ((o.get("relasjoner") or {}).get("foreldre") or []) for v in f.get("vegobjekter", [])]
            if par:
                row["of"] = par[0]
            rows.append(row)
        nxt = (d.get("metadata") or {}).get("neste") or {}
        url = nxt.get("href") if d.get("metadata", {}).get("returnert", 0) > 0 else None
    return rows


def load(kind):
    """What was fetched of one kind ([] if it never was: the map is then built without it)."""
    path = os.path.join(DIR, "%d.json" % kind)
    return json.load(open(path)) if os.path.exists(path) else []


def inside(rows, margin=0.0):
    return [r for r in rows if X0 + margin < r["x"] < X1 - margin and Z0 + margin < r["z"] < Z1 - margin]


if __name__ == "__main__":
    os.makedirs(DIR, exist_ok=True)
    for kind, name in KINDS.items():
        path = os.path.join(DIR, "%d.json" % kind)
        if "--again" in sys.argv or not os.path.exists(path):
            json.dump(fetch(kind), open(path, "w"), separators=(",", ":"))
        rows = load(kind)
        here = inside(rows)
        by = {}
        for r in here:
            by[r["road"]] = by.get(r["road"], 0) + 1
        print("%-22s in the kommune %5d, on the map %5d  %s" % (name, len(rows), len(here), " ".join("%s:%d" % kv for kv in sorted(by.items()))))
