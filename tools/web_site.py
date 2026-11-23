#!/usr/bin/env python3
"""Put the map next to a web export: copy world/ into SITE/world/ and write SITE/world/files.json.

The browser build leaves world/ out of its pack (export_presets.cfg) and the page (web/shell.html) downloads the
files listed in files.json instead, so no single file on the site comes near GitHub Pages' size limits.

    python3 tools/web_site.py build/web
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

root = Path(__file__).resolve().parent.parent
src = root / "world"
dest = Path(sys.argv[1] if len(sys.argv) > 1 else root / "build" / "web") / "world"
if dest.exists():
    shutil.rmtree(dest)

files = []
for p in sorted(src.rglob("*")):
    if not p.is_file() or p.suffix == ".import" or p.name.startswith("."):
        continue
    name = p.relative_to(src).as_posix()
    data = p.read_bytes()
    files.append({"name": name, "size": len(data), "hash": hashlib.sha1(data).hexdigest()[:12]})
    (dest / name).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(p, dest / name)
# The player's and the Volvo's models (models/, left out of the pack by its .gdignore) go along with the map, as
# world/models/; in the browser scripts/car.gd and player.gd read them from /world/models/.
for p in sorted((root / "models").glob("*")):
    if not p.is_file() or p.suffix == ".import" or p.name.startswith("."):
        continue
    name = "models/" + p.name
    data = p.read_bytes()
    files.append({"name": name, "size": len(data), "hash": hashlib.sha1(data).hexdigest()[:12]})
    (dest / name).parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(p, dest / name)

(dest / "files.json").write_text(json.dumps(files, indent=0))
big = max(files, key=lambda f: f["size"])
print(f"{len(files)} map files, {sum(f['size'] for f in files) / 1048576:.0f} MB, "
      f"largest {big['name']} {big['size'] / 1048576:.0f} MB -> {dest}")
