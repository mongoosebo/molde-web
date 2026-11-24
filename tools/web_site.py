#!/usr/bin/env python3
"""Put the map next to a web export: copy world/ into SITE/world/ and write SITE/world/files.json.

The browser build leaves world/ out of its pack (export_presets.cfg) and the page (web/shell.html) downloads the
files listed in files.json instead, so no single file on the site comes near GitHub Pages' size limits.

    python3 tools/web_site.py build/web
"""
import gzip
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

# The download is packed (asked for on 24 November: 329 MB before anything showed). Files of numbers and of text
# are gzipped, which the page undoes with the browser's own DecompressionStream. The 1 m heights, half of the
# whole map, first have each height replaced by how it differs from its neighbours to the west and north
# (ground is smooth: the differences are small numbers, which pack to a fifth), and the page adds them up again.
# Pictures, sounds and models are packed already and go as they are. files.json says for each file how it is
# stored ("packed": "gz" or "d2gz", "stored": bytes on the site, "width": heights in a row for d2gz).
meta = json.loads((src / "meta.json").read_text())
FINE_W = int(meta["fine"]["w"])
STRIP = int(meta["fine"]["strip"])


def differences(data: bytes, width: int) -> bytes:
    """Each 16-bit height as its difference from the one before it in its row, and that as its difference from
    the one above it; all modulo 65536, so adding them up again gives the heights back exactly."""
    try:
        import numpy as np
        a = np.frombuffer(data, dtype="<u2").reshape(-1, width)
        dx = a.copy()
        dx[:, 1:] = a[:, 1:] - a[:, :-1]
        dy = dx.copy()
        dy[1:, :] = dx[1:, :] - dx[:-1, :]
        return dy.astype("<u2").tobytes()
    except ImportError:
        import array
        a = array.array("H")
        a.frombytes(data)
        if sys.byteorder == "big":
            a.byteswap()
        out = array.array("H", bytes(len(data)))
        before = [0] * width
        for r in range(len(a) // width):
            row = a[r * width:(r + 1) * width].tolist()
            dx = [row[0]] + [(row[c] - row[c - 1]) & 0xFFFF for c in range(1, width)]
            out[r * width:(r + 1) * width] = array.array("H", [(x - b) & 0xFFFF for x, b in zip(dx, before)])
            before = dx
        if sys.byteorder == "big":
            out.byteswap()
        return out.tobytes()


def put(name: str, data: bytes) -> dict:
    entry = {"name": name, "size": len(data)}
    stored = data
    if name.startswith("h1/") and name.endswith(".bin"):
        strip = int(name[4:6])
        width = min(STRIP, FINE_W - strip * STRIP)
        stored = gzip.compress(differences(data, width), 6, mtime=0)
        entry.update(packed="d2gz", width=width)
    elif name.endswith((".bin", ".json")):
        stored = gzip.compress(data, 6, mtime=0)
        entry.update(packed="gz")
    entry["stored"] = len(stored)
    entry["hash"] = hashlib.sha1(stored).hexdigest()[:12]
    out = dest / (name + (".gz" if "packed" in entry else ""))
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(stored)
    return entry


files = []
for p in sorted(src.rglob("*")):
    if not p.is_file() or p.suffix == ".import" or p.name.startswith("."):
        continue
    files.append(put(p.relative_to(src).as_posix(), p.read_bytes()))
# The player's and the Volvo's models (models/, left out of the pack by its .gdignore) go along with the map, as
# world/models/; in the browser scripts/car.gd and player.gd read them from /world/models/.
for p in sorted((root / "models").glob("*")):
    if not p.is_file() or p.suffix == ".import" or p.name.startswith("."):
        continue
    files.append(put("models/" + p.name, p.read_bytes()))

(dest / "files.json").write_text(json.dumps(files, indent=0))
big = max(files, key=lambda f: f["stored"])
print(f"{len(files)} map files, {sum(f['size'] for f in files) / 1048576:.0f} MB, "
      f"to download {sum(f['stored'] for f in files) / 1048576:.0f} MB, "
      f"largest {big['name']} {big['stored'] / 1048576:.0f} MB -> {dest}")
