#!/usr/bin/env python3
"""Make a car model from Meshy fit for the game (asked for on 22 November: "do steps 1-6 on the volvo, also fix the
wheels. they are off angle, so they wobble when rotating").

Meshy gives a .glb with the body and the four wheels as separate parts, one picture wrapped over everything, no
surface directions (normals), the car lying along X at 0.12 units long, and the front wheels turned as if steering.
This writes models/<name>.glb with

  * the car in the game's own frame: metres, nose toward -Z, standing on y = 0, squared up by its own wheels;
  * each wheel by itself round the origin with its axle exactly along X (the axle and the middle are found from the
    tread, which is a band round the axle), and the place of its hub as the node's position: a wheel that turns
    round its own axle does not wobble;
  * normals: smooth over a panel, sharp where two faces meet at more than CREASE degrees;
  * the pictures at full size (JPEG), and one more, `mask`: R where there is window glass, G headlamps, B tail
    lamps, A indicators. shaders/car_model.gdshader makes glass of the first and lights the others.

    .venv/bin/python tools/car_model.py IN.glb models/volvo.glb [--length 4.79] [--preview DIR]
"""
import io
import json
import os
import struct
import sys

import numpy as np
from PIL import Image

CREASE = 38.0
CT = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}


def load(path):
    with open(path, "rb") as f:
        f.read(12)
        n, _ = struct.unpack("<I4s", f.read(8))
        doc = json.loads(f.read(n))
        n, _ = struct.unpack("<I4s", f.read(8))
        blob = f.read(n)

    def acc(i):
        a = doc["accessors"][i]
        v = doc["bufferViews"][a["bufferView"]]
        off = v.get("byteOffset", 0) + a.get("byteOffset", 0)
        return np.frombuffer(blob, CT[a["componentType"]], a["count"] * NC[a["type"]], off).reshape(a["count"], NC[a["type"]])

    def image(tex):
        v = doc["bufferViews"][doc["images"][doc["textures"][tex]["source"]]["bufferView"]]
        return Image.open(io.BytesIO(blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])).convert("RGB")

    parts = []
    for node in doc["nodes"]:
        if "mesh" not in node:
            continue
        p = doc["meshes"][node["mesh"]]["primitives"][0]
        parts.append({"pos": acc(p["attributes"]["POSITION"]).astype(np.float64), "uv": acc(p["attributes"]["TEXCOORD_0"]).astype(np.float64),
                      "tri": acc(p["indices"]).reshape(-1, 3).astype(np.int64)})
    m = doc["materials"][0]
    pics = {"colour": image(m["pbrMetallicRoughness"]["baseColorTexture"]["index"]),
            "orm": image(m["pbrMetallicRoughness"]["metallicRoughnessTexture"]["index"]),
            "normal": image(m["normalTexture"]["index"])}
    return parts, pics


def wheel_fit(P):
    """The axle (a unit vector) and the middle of a wheel, from its tread: the points furthest from the axle."""
    c = P.mean(0)
    ax = np.linalg.eigh(np.cov((P - c).T))[1][:, 0]
    r = 0.0
    for _ in range(5):
        d = P - c
        rad = np.linalg.norm(d - np.outer(d @ ax, ax), axis=1)
        T = P[rad > 0.85 * rad.max()]
        c2 = T.mean(0)
        ax = np.linalg.eigh(np.cov((T - c2).T))[1][:, 0]
        e1 = np.cross(ax, [0.0, 1.0, 0.0])
        e1 /= np.linalg.norm(e1)
        e2 = np.cross(ax, e1)
        x, y = (T - c2) @ e1, (T - c2) @ e2
        s = np.linalg.lstsq(np.c_[2 * x, 2 * y, np.ones(len(x))], x * x + y * y, rcond=None)[0]
        c = c2 + s[0] * e1 + s[1] * e2
        r = float(np.sqrt(s[2] + s[0] ** 2 + s[1] ** 2))
    return ax, c, r


def turn_to(a, b):
    """The smallest turn that takes unit vector a onto unit vector b."""
    v = np.cross(a, b)
    c = float(a @ b)
    if np.linalg.norm(v) < 1e-9:
        return np.eye(3)
    k = np.array([[0, -v[2], v[1]], [v[2], 0, -v[0]], [-v[1], v[0], 0]])
    return np.eye(3) + k + k @ k / (1.0 + c)


def to_game(parts, length):
    """Body and wheels in the game's frame. Gives (body, [wheel fl, fr, rl, rr]); a wheel has "hub"."""
    parts = sorted(parts, key=lambda p: -len(p["tri"]))
    body, wheels = parts[0], parts[1:5]
    k = length / np.ptp(body["pos"][:, 0])
    lay = np.array([[0.0, 0.0, -1.0], [0.0, 1.0, 0.0], [1.0, 0.0, 0.0]]) * k            # model X to Z, Z to -X
    for p in parts[:5]:
        p["pos"] = p["pos"] @ lay.T
    fits = [wheel_fit(w["pos"]) for w in wheels]
    mids = np.array([f[1] for f in fits])
    # square the car up by its wheels: the rear axle lies across, the wheels stand on the ground, the middle of the
    # body is the middle between the wheels
    front = mids[mids[:, 2] < mids[:, 2].mean()]
    rear = mids[mids[:, 2] >= mids[:, 2].mean()]
    across = rear[np.argmax(rear[:, 0])] - rear[np.argmin(rear[:, 0])]
    yaw = np.arctan2(across[2], across[0])
    c, s = np.cos(yaw), np.sin(yaw)
    square = np.array([[c, 0.0, s], [0.0, 1.0, 0.0], [-s, 0.0, c]])
    radius = float(np.mean([f[2] for f in fits]))
    move = np.array([-(square @ mids.T).T[:, 0].mean(), radius - mids[:, 1].mean(), -(body["pos"] @ square.T)[:, 2].mean() * 0.0])
    zmid = ((body["pos"] @ square.T)[:, 2].min() + (body["pos"] @ square.T)[:, 2].max()) * 0.5
    move[2] = -zmid
    body["pos"] = body["pos"] @ square.T + move
    out = [None] * 4
    track = float(np.mean(np.abs((mids @ square.T + move)[:, 0])))
    zf = float(((front @ square.T) + move)[:, 2].mean())
    zr = float(((rear @ square.T) + move)[:, 2].mean())
    for w, (ax, mid, r) in zip(wheels, fits):
        ax = square @ ax
        mid = square @ mid + move
        P = w["pos"] @ square.T + move - mid
        ax = ax if ax[0] > 0 else -ax
        P = P @ turn_to(ax, np.array([1.0, 0.0, 0.0])).T
        P *= radius / r                                                             # (all four the same size)
        w["pos"] = P
        left = mid[0] < 0.0
        is_front = mid[2] < (zf + zr) * 0.5
        w["hub"] = [(-track if left else track), radius, zf if is_front else zr]
        w["name"] = "wheel_" + ("f" if is_front else "r") + ("l" if left else "r")
        w["was"] = (float(np.degrees(np.arccos(min(1.0, abs(ax[0]))))), mid.tolist())
        out[(0 if is_front else 2) + (0 if left else 1)] = w
    body["name"] = "body"
    return body, out, {"radius": radius, "track": track, "axle_f": zf, "axle_r": zr}


def preview(body, wheels, pics, folder):
    """Pictures of the car from six sides, to see what the masks and the wheels have come to."""
    os.makedirs(folder, exist_ok=True)
    tex = np.asarray(pics["colour"]).astype(np.float64) / 255.0
    th, tw = tex.shape[:2]
    rng = np.random.default_rng(1)
    pts, cols = [], []
    for p in [body] + wheels:
        P = p["pos"] + (np.array(p["hub"]) if "hub" in p else 0.0)
        a, b, c = P[p["tri"][:, 0]], P[p["tri"][:, 1]], P[p["tri"][:, 2]]
        ua, ub, uc = p["uv"][p["tri"][:, 0]], p["uv"][p["tri"][:, 1]], p["uv"][p["tri"][:, 2]]
        area = np.linalg.norm(np.cross(b - a, c - a), axis=1) * 0.5
        n = np.maximum(1, (area * 220000).astype(int))
        idx = np.repeat(np.arange(len(a)), n)
        r1, r2 = rng.random(len(idx)), rng.random(len(idx))
        s = np.sqrt(r1)
        w0, w1, w2 = 1 - s, s * (1 - r2), s * r2
        pts.append(a[idx] * w0[:, None] + b[idx] * w1[:, None] + c[idx] * w2[:, None])
        uv = ua[idx] * w0[:, None] + ub[idx] * w1[:, None] + uc[idx] * w2[:, None]
        cols.append(tex[np.clip((uv[:, 1] % 1.0 * th).astype(int), 0, th - 1), np.clip((uv[:, 0] % 1.0 * tw).astype(int), 0, tw - 1)])
    pts, cols = np.concatenate(pts), np.concatenate(cols)
    views = {"left": (2, 1, 0, -1), "right": (2, 1, 0, 1), "front": (0, 1, 2, -1), "rear": (0, 1, 2, 1), "top": (0, 2, 1, 1)}
    for name, (hx, vy, depth, sign) in views.items():
        sc = 300.0
        x = pts[:, hx] * (sign if name in ("left", "front") else -sign if name == "rear" else 1.0)
        if name == "right":
            x = -pts[:, hx]
        u = ((x + 2.6) * sc).astype(int)
        v = ((2.7 - pts[:, vy] - (0.0 if name != "top" else 0.0)) * sc).astype(int) if name == "top" else ((1.7 - pts[:, vy]) * sc).astype(int)
        W, H = int(5.2 * sc), int((5.4 if name == "top" else 1.8) * sc)
        ok = (u >= 0) & (u < W) & (v >= 0) & (v < H)
        order = np.argsort(pts[ok, depth] * sign)
        img = np.full((H, W, 3), 0.35)
        img[v[ok][order], u[ok][order]] = cols[ok][order]
        Image.fromarray((img * 255).astype(np.uint8)).save(os.path.join(folder, name + ".jpg"), quality=90)


def with_normals(part):
    """Normals for a part that has none: each corner takes the faces round its point that lie within CREASE degrees
    of its own face (weighted by their size), so panels are smooth and edges stay edges. Points are then shared
    again where place, picture and normal agree."""
    P, UV, T = part["pos"], part["uv"], part["tri"]
    _, weld = np.unique(np.round(P, 4), axis=0, return_inverse=True)
    weld = weld.reshape(-1)
    fn = np.cross(P[T[:, 1]] - P[T[:, 0]], P[T[:, 2]] - P[T[:, 0]])
    area = np.linalg.norm(fn, axis=1)
    unit = fn / np.maximum(area, 1e-12)[:, None]
    wt = weld[T]
    order = np.argsort(wt.reshape(-1), kind="stable")
    faces = order // 3
    starts = np.searchsorted(wt.reshape(-1)[order], np.arange(wt.max() + 2))
    limit = np.cos(np.radians(CREASE))
    N = np.zeros((len(T), 3, 3))
    for v in range(wt.max() + 1):
        fs = faces[starts[v]:starts[v + 1]]
        if len(fs) == 0:
            continue
        u = unit[fs]
        near = (u @ u.T) >= limit
        sums = near @ fn[fs]
        sums /= np.maximum(np.linalg.norm(sums, axis=1), 1e-12)[:, None]
        for f, n in zip(fs, sums):
            N[f, np.nonzero(wt[f] == v)[0]] = n
    key = np.c_[wt.reshape(-1), np.round(UV[T].reshape(-1, 2) * 8192), np.round(N.reshape(-1, 3) * 64)]
    _, first, inv = np.unique(key, axis=0, return_index=True, return_inverse=True)
    corner = T.reshape(-1)
    part["pos"] = P[corner][first]
    part["uv"] = UV[corner][first]
    part["nrm"] = N.reshape(-1, 3)[first]
    part["tri"] = inv.reshape(-1, 3)


def make_mask(body, colour, size):
    """R window glass, G headlamps, B tail lamps, A indicators: by where on the car a point of the picture lies and
    what colour it has there."""
    tex = np.asarray(colour.resize((size, size), Image.BILINEAR)).astype(np.float64) / 255.0
    lum = tex @ np.array([0.30, 0.59, 0.11])
    sat = tex.max(2) - tex.min(2)
    r, g, b = tex[..., 0], tex[..., 1], tex[..., 2]
    orange = (r > 0.55) & (g > 0.38 * r) & (g < 0.78 * r) & (b < 0.45 * r)
    red = (r > 0.35) & (g < 0.74 * r) & (b < 0.74 * r) & ~orange
    mask = np.zeros((size, size, 4), np.uint8)
    P, UV, T = body["pos"], body["uv"], body["tri"]
    for t in T:
        uv = UV[t] * size
        x0, x1 = int(np.floor(uv[:, 0].min())) - 1, int(np.ceil(uv[:, 0].max())) + 1
        y0, y1 = int(np.floor(uv[:, 1].min())) - 1, int(np.ceil(uv[:, 1].max())) + 1
        x0, y0, x1, y1 = max(x0, 0), max(y0, 0), min(x1, size - 1), min(y1, size - 1)
        if x1 < x0 or y1 < y0:
            continue
        gx, gy = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
        d = (uv[1, 1] - uv[2, 1]) * (uv[0, 0] - uv[2, 0]) + (uv[2, 0] - uv[1, 0]) * (uv[0, 1] - uv[2, 1])
        if abs(d) < 1e-9:
            continue
        w0 = ((uv[1, 1] - uv[2, 1]) * (gx - uv[2, 0]) + (uv[2, 0] - uv[1, 0]) * (gy - uv[2, 1])) / d
        w1 = ((uv[2, 1] - uv[0, 1]) * (gx - uv[2, 0]) + (uv[0, 0] - uv[2, 0]) * (gy - uv[2, 1])) / d
        w2 = 1.0 - w0 - w1
        e = 1.2 / max(np.sqrt(abs(d)), 1.0)                                     # (a pixel over the edge, for the seams)
        inside = (w0 >= -e) & (w1 >= -e) & (w2 >= -e)
        if not inside.any():
            continue
        pos = w0[..., None] * P[t[0]] + w1[..., None] * P[t[1]] + w2[..., None] * P[t[2]]
        sl = (slice(y0, y1 + 1), slice(x0, x1 + 1))
        x, y, z = np.abs(pos[..., 0]), pos[..., 1], pos[..., 2]
        glass = inside & (y > 0.975) & (x < 0.80) & (lum[sl] < 0.62) & (sat[sl] < 0.16)
        head = inside & (z < -2.15) & (y > 0.61) & (y < 0.79) & (x > 0.30) & (x < 0.74) & (lum[sl] > 0.30) & ~orange[sl]
        tail = inside & (z > 2.15) & (y > 0.50) & (y < 0.90) & red[sl]
        blink = inside & orange[sl] & (y > 0.45) & (y < 0.95) & (np.abs(z) > 2.0)
        for k, m in enumerate((glass, head, tail, blink)):
            mask[sl][..., k][m] = 255
    return Image.fromarray(mask, "RGBA")


def write_glb(path, body, wheels, pics, quality=92):
    blob = bytearray()
    views, accessors, meshes, nodes = [], [], [], []

    def view(data, target=None):
        while len(blob) % 4:
            blob.append(0)
        v = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target:
            v["target"] = target
        blob.extend(data)
        views.append(v)
        return len(views) - 1

    def accessor(arr, kind, comp, target, bounds=False):
        a = {"bufferView": view(arr.tobytes(), target), "componentType": comp, "count": len(arr), "type": kind}
        if bounds:
            a["min"], a["max"] = arr.min(0).tolist(), arr.max(0).tolist()
        accessors.append(a)
        return len(accessors) - 1

    for part in [body] + wheels:
        uv = part["uv"].astype(np.float32)
        prim = {"attributes": {"POSITION": accessor(part["pos"].astype(np.float32), "VEC3", 5126, 34962, True),
                               "NORMAL": accessor(part["nrm"].astype(np.float32), "VEC3", 5126, 34962),
                               "TEXCOORD_0": accessor(uv, "VEC2", 5126, 34962)},
                "indices": accessor(part["tri"].astype(np.uint32).reshape(-1), "SCALAR", 5125, 34963), "material": 0}
        meshes.append({"name": part["name"], "primitives": [prim]})
        node = {"name": part["name"], "mesh": len(meshes) - 1}
        if "hub" in part:
            node["translation"] = [float(v) for v in part["hub"]]
        nodes.append(node)
    images = []
    for name in ("colour", "orm", "normal"):
        out = io.BytesIO()
        pics[name].save(out, "JPEG", quality=quality)
        images.append({"bufferView": view(out.getvalue()), "mimeType": "image/jpeg", "name": name})
    doc = {"asset": {"version": "2.0", "generator": "molde tools/car_model.py"}, "scene": 0, "scenes": [{"nodes": list(range(len(nodes)))}],
           "nodes": nodes, "meshes": meshes, "accessors": accessors, "bufferViews": views, "images": images,
           "samplers": [{"magFilter": 9729, "minFilter": 9987, "wrapS": 10497, "wrapT": 10497}],
           "textures": [{"source": i, "sampler": 0} for i in range(3)],
           "materials": [{"name": "car", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0}, "metallicRoughnessTexture": {"index": 1}},
                          "normalTexture": {"index": 2}}]}
    while len(blob) % 4:
        blob.append(0)
    doc["buffers"] = [{"byteLength": len(blob)}]
    js = json.dumps(doc, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    with open(path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, 28 + len(js) + len(blob)))
        f.write(struct.pack("<I4s", len(js), b"JSON") + js)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob))
    return (28 + len(js) + len(blob)) / 1e6


def main():
    args = sys.argv[1:]
    length = float(args[args.index("--length") + 1]) if "--length" in args else 4.79
    parts, pics = load(args[0])
    body, wheels, dims = to_game(parts, length)
    for w in wheels:
        print("  %s: axle was %.1f degrees off, hub %s" % (w["name"], w["was"][0], [round(v, 3) for v in w["hub"]]))
    print("  ", {k: round(v, 3) for k, v in dims.items()}, "body", np.round(body["pos"].min(0), 3), np.round(body["pos"].max(0), 3))
    if "--preview" in args:
        preview(body, wheels, pics, args[args.index("--preview") + 1])
    for part in [body] + wheels:
        with_normals(part)
    mask = make_mask(body, pics["colour"], 2048)
    mask.save(os.path.splitext(args[1])[0] + "_mask.png")
    got = np.asarray(mask).reshape(-1, 4).mean(0) / 255.0 * 100.0
    print("   mask: glass %.2f %%, headlamps %.3f %%, tail lamps %.3f %%, indicators %.3f %% of the picture" % tuple(got))
    size = write_glb(args[1], body, wheels, pics)
    print("   wrote %s, %.1f MB, %d triangles" % (args[1], size, sum(len(p["tri"]) for p in [body] + wheels)))
    if "--preview" in args:
        m = np.asarray(mask.resize(pics["colour"].size, Image.NEAREST)).astype(np.float64) / 255.0
        c = np.asarray(pics["colour"]).astype(np.float64) / 255.0
        c = c * (1 - m[..., :1]) + m[..., :1] * np.array([0.1, 0.3, 1.0])
        c = c * (1 - m[..., 1:2]) + m[..., 1:2] * np.array([1.0, 1.0, 0.0])
        c = c * (1 - m[..., 2:3]) + m[..., 2:3] * np.array([1.0, 0.0, 1.0])
        c = c * (1 - m[..., 3:4]) + m[..., 3:4] * np.array([0.0, 1.0, 0.0])
        shown = dict(pics, colour=Image.fromarray((c * 255).astype(np.uint8)))
        preview(body, wheels, shown, os.path.join(args[args.index("--preview") + 1], "mask"))


if __name__ == "__main__":
    main()
