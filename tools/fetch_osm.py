#!/usr/bin/env python3
"""Download the OpenStreetMap data for the game area (tools/area.py) into data/osm_raw.json."""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import X0, X1, Z0, Z1, to_latlon

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
south, west = to_latlon(X0 - 150, Z1 + 150)
north, east = to_latlon(X1 + 150, Z0 - 150)
bbox = f"({south:.5f},{west:.5f},{north:.5f},{east:.5f})"
query = f"""[out:json][timeout:300];
(
  way["building"]{bbox}; relation["building"]{bbox}; way["highway"]{bbox}; way["aeroway"]{bbox};
  way["natural"]{bbox}; relation["natural"]{bbox}; way["landuse"]{bbox}; relation["landuse"]{bbox};
  way["leisure"]{bbox}; way["man_made"]{bbox}; way["amenity"]{bbox}; way["barrier"]{bbox};
  way["waterway"]{bbox}; way["railway"]{bbox}; way["power"]{bbox}; way["tourism"]{bbox};
  node["place"]{bbox}; node["amenity"]{bbox}; node["shop"]{bbox}; node["natural"]{bbox};
  node["highway"]{bbox}; node["barrier"]{bbox}; node["man_made"]{bbox}; node["tourism"]{bbox};
  node["public_transport"]{bbox}; node["power"]{bbox}; node["emergency"]{bbox}; node["leisure"]{bbox};
  node["historic"]{bbox}; way["historic"]{bbox};
);
out tags geom;"""
out = os.path.join(ROOT, "data", "osm_raw.json")
for host in ("https://overpass-api.de", "https://overpass.private.coffee", "https://overpass.kumi.systems"):
    subprocess.run(["curl", "-s", "-m", "300", "-A", "map-builder/1.0", "--data-urlencode", "data=" + query,
                    "-o", out + ".part", host + "/api/interpreter"])
    try:
        n = len(json.load(open(out + ".part"))["elements"])
    except (OSError, ValueError, KeyError):
        print("no answer from", host)
        continue
    if n > 1000:
        os.replace(out + ".part", out)
        print(n, "elements")
        break
else:
    sys.exit("download failed")
