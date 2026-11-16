#!/usr/bin/env python3
"""Procedural, tileable surface textures (albedo + normal map) for the detailed landmark buildings.
Writes world/textures/<name>_albedo.png and <name>_normal.png."""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "world", "textures")
os.makedirs(OUT, exist_ok=True)
N = 1024


def fbm(shape, beta, seed):
    """Tileable fractal noise in 0..1 (random phases shaped by a 1/f^beta spectrum)."""
    rng = np.random.default_rng(seed)
    fy = np.fft.fftfreq(shape[0])[:, None] * shape[0]
    fx = np.fft.fftfreq(shape[1])[None, :] * shape[1]
    k = np.sqrt(fx * fx + fy * fy)
    k[0, 0] = 1.0
    spec = np.fft.fft2(rng.standard_normal(shape)) / k ** beta
    spec[0, 0] = 0.0
    out = np.real(np.fft.ifft2(spec))
    return (out - out.min()) / (out.max() - out.min())


def save(name, albedo, height, strength):
    rgb = np.clip(albedo, 0, 1)
    Image.fromarray((rgb * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_albedo.png"))
    dx = (np.roll(height, -1, 1) - np.roll(height, 1, 1)) * strength
    dy = (np.roll(height, -1, 0) - np.roll(height, 1, 0)) * strength
    nz = np.ones_like(dx)
    ln = np.sqrt(dx * dx + dy * dy + nz * nz)
    nrm = np.stack([-dx / ln, dy / ln, nz / ln], -1) * 0.5 + 0.5
    Image.fromarray((nrm * 255).astype(np.uint8)).save(os.path.join(OUT, name + "_normal.png"))


def grey(v, tint=(1.0, 1.0, 1.0)):
    return np.stack([v * tint[0], v * tint[1], v * tint[2]], -1)


# --- board-formed concrete, 3 m tile: horizontal shuttering boards, grain, pores, rain streaks
boards = 20
bh = N // boards
rng = np.random.default_rng(7)
rows = np.arange(N) // bh % boards
tone = rng.uniform(-0.015, 0.015, boards)[rows][:, None]
grain = np.repeat(fbm((N, N // 16), 1.2, 1), 16, axis=1)
for b in range(boards):                                   # shift the grain per board
    sl = slice(b * bh, (b + 1) * bh)
    grain[sl] = np.roll(grain[sl], int(rng.integers(0, N)), axis=1)
cloud = fbm((N, N), 2.0, 2)
fine = fbm((N, N), 0.6, 3)
streak = np.repeat(fbm((N // 16, N), 1.6, 4), 16, axis=0)  # vertical weathering
gap = ((np.arange(N) % bh) < 2).astype(np.float32)[:, None] * np.ones((1, N))
pores = (fbm((N, N), 0.2, 5) > 0.83).astype(np.float32)
v = 0.60 + tone + 0.12 * (cloud - 0.5) + 0.035 * (grain - 0.5) + 0.05 * (fine - 0.5) - 0.10 * (streak - 0.45).clip(0) - 0.05 * gap - 0.08 * pores
h = 0.5 * grain + 0.3 * fine - 1.2 * gap - 0.8 * pores
save("concrete", grey(v, (0.97, 0.985, 1.0)), h, 2.2)

# --- painted plaster, 2 m tile: near-white so the material colour tints it
fine = fbm((N, N), 0.9, 11)
blot = fbm((N, N), 2.2, 12)
streak = np.repeat(fbm((N // 32, N), 1.5, 13), 32, axis=0)
v = 0.90 + 0.06 * (fine - 0.5) + 0.07 * (blot - 0.5) - 0.07 * (streak - 0.5).clip(0)
save("plaster", grey(v), fine + 0.3 * blot, 1.6)

# --- granite setts, 2 m tile: running bond
R, C = 16, 8
rh, cw = N // R, N // C
yy, xx = np.mgrid[0:N, 0:N]
row = yy // rh
xs = (xx + (row % 2) * (cw // 2)) % N
col = xs // cw
rng = np.random.default_rng(21)
stone_tone = rng.uniform(0.40, 0.50, (R, C))[row, col]
stone_warm = rng.uniform(-0.02, 0.03, (R, C))[row, col]
u = (xs % cw) / cw
w = (yy % rh) / rh
edge = np.minimum(np.minimum(u, 1 - u) * cw, np.minimum(w, 1 - w) * rh)     # px to nearest joint
joint = (edge < 3).astype(np.float32)
dome = np.clip(edge / 10.0, 0, 1)
speck = fbm((N, N), 0.4, 22)
v = stone_tone + 0.10 * (speck - 0.5)
alb = np.stack([v + stone_warm, v, v - stone_warm * 0.6], -1) * (1 - 0.55 * joint[..., None])
save("paving", alb, dome + 0.25 * speck - 0.6 * joint, 2.5)

# --- roof tiles, 2 m tile: 8 courses of pantiles (u along the eave, v up the slope)
R, C = 8, 8
rh, cw = N // R, N // C
row = yy // rh
xs = (xx + (row % 2) * (cw // 2)) % N
u = (xs % cw) / cw
w = (yy % rh) / rh                      # 0 at the top of a course, 1 at its lower edge
rng = np.random.default_rng(31)
tile_tone = rng.uniform(-0.07, 0.07, (R, C))[row, xs // cw]
curve = 0.5 - 0.5 * np.cos(u * 2 * np.pi)
lip = (w > 0.93).astype(np.float32)
shadow = np.clip(1 - w / 0.18, 0, 1)
moss = fbm((N, N), 1.8, 32)
v = 0.74 + tile_tone + 0.14 * (curve - 0.5) + 0.08 * w - 0.30 * shadow + 0.06 * lip - 0.10 * (moss - 0.55).clip(0)
save("rooftile", grey(v), curve * 0.8 + w * 0.6, 2.0)

# --- roofing felt / gravel for flat roofs, 2 m tile
g = fbm((N, N), 0.3, 41)
c = fbm((N, N), 2.0, 42)
save("gravel", grey(0.42 + 0.22 * (g - 0.5) + 0.08 * (c - 0.5), (1.0, 0.97, 0.92)), g, 2.5)
# --- painted timber cladding, 2 m tile: horizontal boards; near-white so the paint colour tints it
boards = 14
bh = N // boards
rows = (np.arange(N) // bh) % boards
rng = np.random.default_rng(51)
tone = rng.uniform(-0.03, 0.03, boards)[rows][:, None]
grain = np.repeat(fbm((N, N // 32), 1.3, 52), 32, axis=1)
wy = (np.arange(N) % bh) / bh
lap = np.clip(1 - wy / 0.14, 0, 1)[:, None] * np.ones((1, N))          # shadow under the board above
v = 0.90 + tone + 0.05 * (grain - 0.5) - 0.28 * lap
save("cladding", grey(v), 0.3 * grain - 1.0 * lap + wy[:, None] * 0.5, 2.0)

# the same boards standing upright (barns, boathouses, newer houses)
save("cladv", grey(v.T.copy() * np.ones((N, N))), (0.3 * grain - 1.0 * lap + wy[:, None] * 0.5).T.copy(), 2.0)

# --- standing-seam sheet roofing, 2 m tile: a raised seam every half metre, running down the slope
sx = (np.arange(N) % (N // 4)) / (N // 4)
seam = np.clip(1 - np.abs(sx - 0.5) / 0.035, 0, 1)[None, :] * np.ones((N, 1))
dull = fbm((N, N), 2.0, 81)
streak = np.repeat(fbm((N // 32, N), 1.5, 82), 32, axis=0)
v = 0.80 + 0.06 * (dull - 0.5) - 0.05 * (streak - 0.5).clip(0) + 0.10 * seam - 0.10 * np.roll(seam, 6, 1)
save("sheet", grey(v), seam * 1.5 + 0.1 * dull, 2.5)

# --- asphalt, 2 m tile: fine aggregate, a little patchy
agg = fbm((N, N), 0.15, 61)
patch = fbm((N, N), 2.2, 62)
v = 0.50 + 0.22 * (agg - 0.5) + 0.10 * (patch - 0.5)
save("asphalt", grey(v), agg, 2.0)

# --- concrete paving slabs for sidewalks, 2 m tile: 4 x 4 slabs
sl = N // 4
uu = (xx % sl) / sl
ww = (yy % sl) / sl
edge = np.minimum(np.minimum(uu, 1 - uu), np.minimum(ww, 1 - ww)) * sl
joint = (edge < 3).astype(np.float32)
rng = np.random.default_rng(71)
slab_tone = rng.uniform(-0.03, 0.03, (4, 4))[yy // sl, xx // sl]
speck = fbm((N, N), 0.3, 72)
v = 0.62 + slab_tone + 0.10 * (speck - 0.5) - 0.25 * joint
save("slabs", grey(v), 0.4 * speck - 0.8 * joint, 2.0)
# --- close-up detail for the terrain, 2 m and 3 m tiles: shades around mid-grey that the ground colour is multiplied by
blades = np.repeat(fbm((N // 2, N), 0.5, 91), 2, axis=0)                 # short upright streaks
clump = fbm((N, N), 1.6, 92)
fine = fbm((N, N), 0.2, 93)
v = 0.5 + 0.30 * (blades - 0.5) + 0.22 * (clump - 0.5) + 0.16 * (fine - 0.5)
save("turf", grey(v), 0.6 * blades + 0.5 * clump + 0.3 * fine, 3.0)
crack = np.abs(fbm((N, N), 1.4, 94) - 0.5) * 2.0                          # dark lines where the noise crosses its middle
lump = fbm((N, N), 1.9, 95)
grit = fbm((N, N), 0.25, 96)
v = 0.5 + 0.22 * (lump - 0.5) + 0.14 * (grit - 0.5) - 0.25 * np.clip(1 - crack / 0.06, 0, 1)
save("stone", grey(v), 0.8 * lump + 0.3 * grit - 0.8 * np.clip(1 - crack / 0.06, 0, 1), 3.0)
# --- a gravel walk, 2 m tile: light, with pebbles and a little wear down the middle
peb = fbm((N, N), 0.1, 101)
mid = fbm((N, N), 1.4, 102)
blot = fbm((N, N), 2.3, 103)
v = 0.74 + 0.20 * (peb - 0.5) + 0.10 * (mid - 0.5) + 0.08 * (blot - 0.5) - 0.12 * (peb > 0.78)
save("path", grey(v, (1.0, 0.96, 0.88)), peb + 0.3 * mid, 2.2)
print("textures written to", OUT)
