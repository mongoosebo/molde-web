#!/usr/bin/env python3
"""Bring a rigged character (a GLB with its skeleton and animations, as Meshy exports it) into the game as the
player's model: the same file with its textures made smaller, written to models/player.glb.

    .venv/bin/python tools/player_model.py ~/Downloads/the_character.glb

The colour and normal pictures are brought down to 2048 pixels and the roughness one to 1024, and stored as JPEG:
the 50 MB file becomes about 3 MB. Nothing else is changed. scripts/rigged.gd loads the result.
"""
import io, json, os, struct, sys

import numpy as np

from PIL import Image

Image.MAX_IMAGE_PIXELS = None
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


CT = {5121: np.uint8, 5123: np.uint16, 5125: np.uint32, 5126: np.float32}
NC = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4, "MAT4": 16}


def _view(doc, blob, i):
    """An accessor's numbers, as an array laid over the file's own bytes (so that writing to it changes the file)."""
    a = doc["accessors"][i]
    v = doc["bufferViews"][a["bufferView"]]
    assert not v.get("byteStride"), "interleaved data is not handled"
    n = NC[a["type"]]
    arr = np.frombuffer(blob, CT[a["componentType"]], a["count"] * n, v.get("byteOffset", 0) + a.get("byteOffset", 0))
    return arr.reshape(a["count"], n) if n > 1 else arr


def _free_the_hands(doc, blob):
    """A character modelled with his arms hanging has his hands lying against his thighs, and the rigging then
    binds half of each hand (and some of the sleeve) to the thigh: when the arm swings, the hand is drawn out
    into a flat sheet between the two. Every point of the surface that lies round the forearm and the hand, and
    out beyond the side of the body, is bound to the arm's own bones only."""
    nodes = doc["nodes"]
    skin = doc["skins"][0]
    names = [nodes[i].get("name", "").split(":")[-1] for i in skin["joints"]]
    if "LeftHand" not in names:
        return blob
    inv = _view(doc, blob, skin["inverseBindMatrices"]).reshape(-1, 4, 4)
    at = {n: np.linalg.inv(inv[k].T.astype(float))[:3, 3] for k, n in enumerate(names)}
    moved = 0
    for prim in doc["meshes"][0]["primitives"]:
        pos = _view(doc, blob, prim["attributes"]["POSITION"]).astype(float)
        joints = _view(doc, blob, prim["attributes"]["JOINTS_0"])
        weights = _view(doc, blob, prim["attributes"]["WEIGHTS_0"])
        for side in ("Left", "Right"):
            elbow, wrist = at[side + "ForeArm"], at[side + "Hand"]
            tip = wrist + (wrist - elbow) / np.linalg.norm(wrist - elbow) * 0.20
            own = [names.index(side + q) for q in ("Shoulder", "Arm", "ForeArm", "Hand")]
            hand, fore = names.index(side + "Hand"), names.index(side + "ForeArm")
            ab = tip - elbow
            t = np.clip(((pos - elbow) @ ab) / (ab @ ab), 0.0, 1.0)
            dist = np.linalg.norm(pos - (elbow + t[:, None] * ab), axis=1)
            sgn = 1.0 if wrist[0] > 0 else -1.0
            # where the body ends and the arm begins: between the two, level with the wrist, the surface thins out
            # to nothing (the crease where the sleeve lies against the hip); the emptiest slice of 4 mm is taken
            band = np.abs(pos[:, 1] - wrist[1]) < 0.10
            edges = np.arange(abs(wrist[0]) - 0.12, abs(wrist[0]) - 0.02, 0.004)
            counts = np.histogram(pos[band, 0] * sgn, edges)[0]
            body_half = float(edges[len(counts) - 1 - int(np.argmin(counts[::-1]))] + 0.002)
            print("  the crease between %s arm and body: %.3f m out" % (side.lower(), body_half))
            pick = np.nonzero((dist < 0.075) & (pos[:, 0] * sgn > body_half) & (pos[:, 1] < elbow[1]))[0]
            # and the other way about: the side of the sweater and the hip, inside the line of the body, that was
            # bound to the forearm hanging beside it (it was drawn up in a sheet when the arm was lifted)
            low = [fore, hand]
            hips, spine = names.index("Hips"), names.index("Spine")
            for v in np.nonzero((pos[:, 0] * sgn <= body_half) & (pos[:, 0] * sgn > 0.0) & (pos[:, 1] < elbow[1] + 0.05))[0]:
                bad = np.isin(joints[v], low) & (weights[v] > 0.004)
                if not bad.any():
                    continue
                moved += 1
                rest = float(weights[v][~bad].sum())
                if rest > 0.05:
                    weights[v] = np.where(bad, 0.0, weights[v] / rest)
                    joints[v] = np.where(bad, hips, joints[v])
                else:
                    joints[v] = (hips if pos[v, 1] < at["Spine"][1] else spine, 0, 0, 0)
                    weights[v] = (1.0, 0.0, 0.0, 0.0)
            for v in pick:
                keep = np.isin(joints[v], own)
                total = float(weights[v][keep].sum())
                if float(weights[v][~keep].sum()) < 0.004:
                    continue
                moved += 1
                if total > 0.05:
                    weights[v] = np.where(keep, weights[v] / total, 0.0)
                else:                                      # bound to the leg altogether: by where along the arm it is
                    joints[v] = (hand if pos[v, 1] < wrist[1] + 0.02 else fore, 0, 0, 0)
                    weights[v] = (1.0, 0.0, 0.0, 0.0)
                    continue
                joints[v] = np.where(keep, joints[v], own[2])
    # The upper arm. In such a model it is one skin with the chest (no crease between them at all), and the rigging
    # lets the arm's pull fade out slowly across half the chest: lift the arm and the chest goes with it ("the
    # overarms are kind of stuck to his thorax", 20 Nov). Here the change from body to arm is made in a band of
    # 4 cm where the arm begins (5.5 cm inside the line of its bone), from the elbow up to the shoulder joint,
    # and eased back into what the rigging gave over the top of the shoulder.
    eased = 0
    for prim in doc["meshes"][0]["primitives"]:
        pos = _view(doc, blob, prim["attributes"]["POSITION"]).astype(float)
        joints = _view(doc, blob, prim["attributes"]["JOINTS_0"])
        weights = _view(doc, blob, prim["attributes"]["WEIGHTS_0"])
        for side in ("Left", "Right"):
            top, elbow = at[side + "Arm"], at[side + "ForeArm"]
            sgn = 1.0 if top[0] > 0 else -1.0
            arm = [names.index(side + q) for q in ("Arm", "ForeArm", "Hand")]
            upper, chest = names.index(side + "Arm"), names.index("Spine2")
            for v in np.nonzero((pos[:, 0] * sgn > 0.05) & (pos[:, 1] > elbow[1]) & (pos[:, 1] < top[1] + 0.04))[0]:
                y = pos[v, 1]
                axis_x = abs(top[0] + (elbow[0] - top[0]) * min(max((y - top[1]) / (elbow[1] - top[1]), 0.0), 1.0))
                want = min(max((pos[v, 0] * sgn - (axis_x - 0.075)) / 0.04, 0.0), 1.0)
                want = want * want * (3.0 - 2.0 * want)
                is_arm = np.isin(joints[v], arm) & (weights[v] > 0.0)
                had = float(weights[v][is_arm].sum())
                keep = min(max((y - (top[1] - 0.02)) / 0.06, 0.0), 1.0)          # (over the shoulder: as the rigging had it)
                want = had * keep + want * (1.0 - keep)
                if abs(want - had) < 0.02:
                    continue
                eased += 1
                w, jn = weights[v].astype(float), joints[v].copy()
                body = ~is_arm & (w > 0.0)
                if want > 0.0 and not is_arm.any():                              # no arm bone among its four: the least of them makes way
                    k = int(np.argmin(np.where(body, w, 9.0))) if body.sum() > 1 else int(np.argmin(w))
                    jn[k], w[k] = upper, 0.0
                    is_arm = np.isin(jn, arm) & (np.arange(4) == k)
                    body = body & (np.arange(4) != k)
                    had = 0.0
                if want < 1.0 and not body.any():
                    k = int(np.argmin(np.where(is_arm, w, 9.0))) if is_arm.sum() > 1 else int(np.argmax(~is_arm))
                    if is_arm[k] and is_arm.sum() == 1:
                        k = (k + 1) % 4
                    jn[k], w[k] = chest, 0.0
                    is_arm[k] = False
                    body = np.arange(4) == k
                arm_sum, body_sum = float(w[is_arm].sum()), float(w[body].sum())
                new = np.zeros(4)
                if is_arm.any():
                    new[is_arm] = want * (w[is_arm] / arm_sum if arm_sum > 1e-6 else 1.0 / is_arm.sum())
                if body.any():
                    new[body] = (1.0 - want) * (w[body] / body_sum if body_sum > 1e-6 else 1.0 / body.sum())
                total = float(new.sum())
                if total < 1e-6:
                    continue
                weights[v] = new / total
                joints[v] = jn
    print("points of the upper arms and the chest bound anew:", eased)
    print("points of the hands and sleeves bound back to the arm:", moved)
    return bytes(blob)


def main(src, dst):
    f = open(src, "rb")
    magic, _ver, _total = struct.unpack("<4sII", f.read(12))
    assert magic == b"glTF", "not a GLB file"
    n, _ = struct.unpack("<I4s", f.read(8))
    doc = json.loads(f.read(n))
    n, _ = struct.unpack("<I4s", f.read(8))
    blob = f.read(n)
    blob = _free_the_hands(doc, bytearray(blob))
    mat = doc["materials"][0]
    tex = doc["textures"]
    role = {}
    if "normalTexture" in mat:
        role[tex[mat["normalTexture"]["index"]]["source"]] = (2048, 92)
    pbr = mat.get("pbrMetallicRoughness", {})
    if "baseColorTexture" in pbr:
        role[tex[pbr["baseColorTexture"]["index"]]["source"]] = (2048, 90)
    if "metallicRoughnessTexture" in pbr:
        role[tex[pbr["metallicRoughnessTexture"]["index"]]["source"]] = (1024, 85)
    new_of = {}
    for i, im in enumerate(doc["images"]):
        v = doc["bufferViews"][im["bufferView"]]
        raw = blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]]
        size, q = role.get(i, (2048, 90))
        pic = Image.open(io.BytesIO(raw)).convert("RGB")
        if max(pic.size) > size:
            pic = pic.resize((size, size), Image.LANCZOS)
        out = io.BytesIO()
        pic.save(out, "JPEG", quality=q, subsampling=0)
        new_of[im["bufferView"]] = out.getvalue()
        im["mimeType"] = "image/jpeg"
    parts, at = [], 0
    for k, v in enumerate(doc["bufferViews"]):
        data = new_of.get(k, blob[v.get("byteOffset", 0):v.get("byteOffset", 0) + v["byteLength"]])
        pad = (-at) % 4
        parts.append(b"\0" * pad)
        at += pad
        v["byteOffset"], v["byteLength"] = at, len(data)
        parts.append(data)
        at += len(data)
    parts.append(b"\0" * ((-at) % 4))
    blob = b"".join(parts)
    doc["buffers"] = [{"byteLength": len(blob)}]
    text = json.dumps(doc, separators=(",", ":")).encode()
    text += b" " * ((-len(text)) % 4)
    os.makedirs(os.path.dirname(dst), exist_ok=True)
    with open(dst, "wb") as o:
        o.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(text) + 8 + len(blob)))
        o.write(struct.pack("<I4s", len(text), b"JSON"))
        o.write(text)
        o.write(struct.pack("<I4s", len(blob), b"BIN\0"))
        o.write(blob)
    print("written", dst, "%.1f MB" % (os.path.getsize(dst) / 1e6), "animations:", [a.get("name") for a in doc.get("animations", [])])


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, "models", "player.glb"))
