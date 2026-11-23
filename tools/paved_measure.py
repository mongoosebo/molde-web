"""Measures what the player sees as faults in the paving: small unpaved holes inside it, small specks of one
surface in or beside the other, and bus stops standing on bare ground. Reads world/ only."""
import json, os, sys, math, collections
import numpy as np
from PIL import Image, ImageDraw
sys.path.insert(0, "tools")
import holes
from scipy import ndimage
m = json.load(open("world/meta.json"))
X0, Z0, X1, Z1 = m["x0"], m["z0"], m["x1"], m["z1"]
R = 4
W, H = int((X1 - X0) * R), int((Z1 - Z0) * R)
img = Image.new("L", (W, H), 0); dr = ImageDraw.Draw(img)
for val, name in ((1, "A"), (2, "S")):
    for d in holes.load_paved().values():
        for tri in d[name]:
            dr.polygon([((p[0] - X0) * R, (p[2] - Z0) * R) for p in tri], fill=val, outline=val)
for b in json.load(open("world/buildings.json")):
    o = b[5]
    dr.polygon([((o[i] - X0) * R, (o[i + 1] - Z0) * R) for i in range(0, len(o), 2)], fill=3)
g = np.asarray(img)
def comps(mask, lo, hi, border=None, name=""):
    lab, n = ndimage.label(mask)
    area = ndimage.sum(mask, lab, range(1, n + 1)) / R / R
    cm = ndimage.center_of_mass(mask, lab, range(1, n + 1))
    sl = ndimage.find_objects(lab)
    out = []
    for k in range(n):
        if not lo <= area[k] <= hi: continue
        s = sl[k]
        if s[0].start == 0 or s[1].start == 0 or s[0].stop == H or s[1].stop == W: continue
        box = (slice(max(0, s[0].start - 1), s[0].stop + 1), slice(max(0, s[1].start - 1), s[1].stop + 1))
        me = lab[box] == k + 1
        ring = ndimage.binary_dilation(me) & ~me
        around = g[box][ring]
        if border is not None and not border(around): continue
        out.append((round(float(area[k]), 2), round(cm[k][1] / R + X0, 1), round(cm[k][0] / R + Z0, 1)))
    out.sort(reverse=True)
    print("%-58s %5d  %8.0f m2" % (name, len(out), sum(a for a, _, _ in out)))
    return out
res = {}
paved = (g == 1) | (g == 2)
res["hole"] = comps(g == 0, 0.1, 25.0, lambda a: (np.isin(a, (1, 2)).mean() > 0.9), "bare holes under 25 m2 ringed by paving")
res["hole_b"] = comps(g == 0, 0.1, 25.0, lambda a: (np.isin(a, (1, 2)).mean() <= 0.9 and (a == 0).sum() == 0), "bare slivers between paving and a building")
res["side_speck"] = comps(g == 2, 0.05, 6.0, None, "pieces of sidewalk under 6 m2")
res["asph_speck"] = comps(g == 1, 0.05, 6.0, None, "pieces of asphalt under 6 m2")
res["asph_in_side"] = comps(g == 1, 0.05, 15.0, lambda a: (a == 2).mean() > 0.9, "asphalt under 15 m2 ringed by sidewalk")
res["side_in_asph"] = comps(g == 2, 0.05, 15.0, lambda a: (a == 1).mean() > 0.9, "sidewalk under 15 m2 ringed by asphalt")
# thin necks and spikes: paving that disappears when 0.5 m is taken off and put back
op = ndimage.binary_opening(paved, iterations=int(0.5 * R))
thin = paved & ~op
res["thin"] = comps(thin, 1.0, 1e9, None, "paving narrower than 1 m (spikes, slivers), pieces over 1 m2")
# bare notches: bare ground that fills in when paving is grown 0.75 m and shrunk back
cl = ndimage.binary_closing(paved | (g == 3), iterations=int(0.75 * R))
notch = cl & (g == 0)
res["notch"] = comps(notch, 1.0, 1e9, None, "bare notches and slits under 1.5 m wide, pieces over 1 m2")
json.dump(res, open(sys.argv[1], "w"))
