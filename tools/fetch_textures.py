#!/usr/bin/env python3
"""Photographed building materials from Poly Haven (polyhaven.com, CC0) in place of the generated ones.

tools/make_textures.py makes every texture in world/textures/ from noise. For the materials of buildings a
photograph looks more like the thing: this fetches the 1K sets (colour, normal, roughness) of a few Poly Haven
textures and writes them under the names the game already uses (scripts/facades.gd, scripts/landmarks.gd), so
it is run after make_textures.py:

    cladding   horizontal boards        cladv     vertical boards       plaster   rendered wall
    concrete   board-marked concrete    rooftile  pan tiles             sheet     corrugated sheet
    stone      granite blocks           and new:  slate, seam (box-profile sheet), brick

The colour of a wall or a roof in the game is the building's own; the texture only carries the material (the
boards, the grooves, the grain, light and dark). So each photograph is made grey and brought to the brightness
the generated texture had: a far building then keeps its colour when it is swapped for the close-up one.

The downloads (about 15 MB) are kept in data/textures_src/, not in the repository. world/textures/CREDITS.md
lists what was used.   .venv/bin/python tools/fetch_textures.py
"""
import json
import os
import subprocess

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "data", "textures_src")
OUT = os.path.join(ROOT, "world", "textures")
API = "https://api.polyhaven.com/files/"
# name in the game: (Poly Haven texture, brightness to bring it to, how much of its light and dark to keep)
USE = {
    "cladding": ("exterior_wall_cladding", 0.88, 1.0),
    "cladv": ("white_planks_clean", 0.88, 1.3),
    "plaster": ("painted_plaster_wall", 0.88, 0.8),
    "concrete": ("concrete_layers", 0.56, 0.8),
    "rooftile": ("roof_09", 0.75, 0.9),
    "sheet": ("corrugated_iron_02", 0.79, 1.0),
    "stone": ("granite_wall", 0.47, 0.8),
    "slate": ("grey_roof_01", 0.55, 0.9),
    "seam": ("box_profile_metal_sheet", 0.79, 1.2),
    "brick": ("brick_wall_006", 0.62, 0.9),
}


def get(url, path):
    if not (os.path.exists(path) and os.path.getsize(path) > 10000):
        subprocess.run(["curl", "-s", "-m", "180", "-A", "map-builder/1.0", "-o", path, url], check=True)
    return path


def main():
    os.makedirs(SRC, exist_ok=True)
    used = []
    for name, (asset, bright, keep) in USE.items():
        listing = os.path.join(SRC, asset + ".json")
        get(API + asset, listing)
        files = json.load(open(listing))
        diff = Image.open(get(files["Diffuse"]["1k"]["jpg"]["url"], os.path.join(SRC, asset + "_diff.jpg"))).convert("RGB")
        nor = Image.open(get(files["nor_gl"]["1k"]["jpg"]["url"], os.path.join(SRC, asset + "_nor.jpg"))).convert("RGB")
        rough = Image.open(get(files["Rough"]["1k"]["jpg"]["url"], os.path.join(SRC, asset + "_rough.jpg"))).convert("L")
        a = np.asarray(diff).astype(np.float64) / 255.0
        lum = a @ np.array([0.30, 0.59, 0.11])
        grey = bright + (lum - lum.mean()) * keep * (bright / max(lum.mean(), 0.05)) ** 0.5
        # (a breath of the photograph's own colour is left in: 12 %, around the same grey)
        tint = a - lum[..., None]
        out = np.clip(grey[..., None] + 0.12 * tint, 0.0, 1.0)
        Image.fromarray((out * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name + "_albedo.png"))
        nor.resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name + "_normal.png"))
        r = np.asarray(rough).astype(np.float64) / 255.0
        r = np.clip(r / max(r.mean(), 0.05) * 0.92, 0.0, 1.0)             # (the material's own roughness stays the game's; the map gives the variation)
        Image.fromarray((r * 255).astype(np.uint8)).resize((1024, 1024), Image.LANCZOS).save(os.path.join(OUT, name + "_rough.png"))
        used.append((name, asset))
        print("  %-9s from %-26s brightness %.2f -> %.2f" % (name, asset, lum.mean(), out.mean()))
    with open(os.path.join(OUT, "CREDITS.md"), "w") as f:
        f.write("# Textures\n\nThe building materials below are photographed textures from Poly Haven (https://polyhaven.com), which are CC0:\n"
                "free to use, no credit needed. They are listed all the same. Each was made grey and brought to the brightness\n"
                "the game expects by `tools/fetch_textures.py`; the colour of a wall or roof is the building's own.\n\n"
                "| texture here | Poly Haven texture |\n|---|---|\n")
        for name, asset in used:
            f.write("| `%s_albedo.png`, `_normal.png`, `_rough.png` | [%s](https://polyhaven.com/a/%s) |\n" % (name, asset, asset))
        f.write("\nEvery other texture in this folder is made by `tools/make_textures.py` from noise.\n")
    print("textures:", len(used), "sets written to world/textures/")


if __name__ == "__main__":
    main()
