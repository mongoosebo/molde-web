#!/usr/bin/env python3
"""Street photos from Mapillary (CC BY-SA) for the game area: where each was taken and which way it looks.

The access token is read from ~/.config/molde/mapillary_token (never kept in the repository).
Run directly to list every photo in the area into data/mapillary/images.json.
"""
import json, os, subprocess, sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from area import X0, X1, Z0, Z1, to_latlon

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DIR = os.path.join(ROOT, "data", "mapillary")
FIELDS = "id,geometry,computed_geometry,compass_angle,computed_compass_angle,captured_at,camera_type,camera_parameters,computed_rotation,computed_altitude,is_pano,width,height,sequence"


def token():
    return open(os.path.expanduser("~/.config/molde/mapillary_token")).read().strip()


def query(west, south, east, north, fields=FIELDS, limit=2000):
    out = subprocess.run(["curl", "-s", "-m", "90", "-A", "map-builder/1.0", "-G", "https://graph.mapillary.com/images",
                          "--data-urlencode", "access_token=" + token(), "--data-urlencode", "fields=" + fields,
                          "--data-urlencode", f"bbox={west:.6f},{south:.6f},{east:.6f},{north:.6f}",
                          "--data-urlencode", f"limit={limit}"], capture_output=True, text=True).stdout
    try:
        return json.loads(out).get("data")
    except ValueError:
        return None


def box(west, south, east, north, depth=0):
    """Every photo in a box; a box that comes back full is split in four."""
    rows = None
    for attempt in range(3):
        rows = query(west, south, east, north)
        if rows is not None:
            break
    if rows is None:
        print("  no answer for", west, south, flush=True)
        return []
    if len(rows) < 2000 or depth > 5:
        return rows
    mx, my = (west + east) / 2, (south + north) / 2
    return (box(west, south, mx, my, depth + 1) + box(mx, south, east, my, depth + 1)
            + box(west, my, mx, north, depth + 1) + box(mx, my, east, north, depth + 1))


if __name__ == "__main__":
    os.makedirs(DIR, exist_ok=True)
    south, west = to_latlon(X0, Z1)
    north, east = to_latlon(X1, Z0)
    step = 0.01
    seen = {}
    lon = west
    while lon < east:
        lat = south
        while lat < north:
            for r in box(lon, lat, min(lon + step, east), min(lat + step, north)):
                seen[r["id"]] = r
            lat += step
        lon += step
        print(f"  {100 * (lon - west) / (east - west):.0f}%  photos so far: {len(seen)}", flush=True)
    json.dump(list(seen.values()), open(os.path.join(DIR, "images.json"), "w"))
    print(len(seen), "photos")
