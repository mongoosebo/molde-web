#!/usr/bin/env python3
"""The real shape of a roof, from Kartverket's laser surface model (DOM, 1 m).

For one building outline this finds the flat pieces the roof is made of (planes fitted to the laser
points), sorts them into bodies — two slopes that meet in a ridge, with any hip ends, are one body; a
wing, a dormer or a lower part is another — and returns the roof as plain geometry:

  faces  the roof surfaces, as 3D polygons
  walls  the outer walls, each with the line its top follows (eaves, gables, steps)
  steps  the upright faces inside the outline where a higher body stands over a lower one

The roof height at a point is the highest body there; a body is the lowest of its planes. That gives
ridges, hips, valleys, cross gables, lean-to roofs and stepped flat roofs without naming any of them.

Needs shapely and scipy (see README: tools run from the project's .venv).
"""
import math
import numpy as np
import shapely
from shapely.geometry import Polygon, box
from shapely.ops import unary_union
from scipy import ndimage

VERSION = 10          # raise to throw away cached results
STEP = 0.7            # spacing of the laser samples taken inside the outline
TOL = 0.18            # how far a point may lie from a plane and still belong to it
EAVE = 0.45           # how far the roof runs out past the wall
FULL = np.ones((3, 3), bool)


def _polys(g):
    if g.is_empty:
        return []
    if g.geom_type == "Polygon":
        return [g]
    return [p for p in getattr(g, "geoms", []) if p.geom_type == "Polygon" and p.area > 0.05]


def _cells_polygon(mask, u0, v0):
    """Union of the grid cells in a mask, as a shapely geometry in the building's own frame."""
    boxes = []
    for j in range(mask.shape[0]):
        row = mask[j]
        i = 0
        n = len(row)
        while i < n:
            if row[i]:
                k = i
                while k < n and row[k]:
                    k += 1
                boxes.append(box(u0 + i * STEP, v0 + j * STEP, u0 + k * STEP, v0 + (j + 1) * STEP))
                i = k
            else:
                i += 1
    return unary_union(boxes) if boxes else Polygon()


def _planes(Y, rng):
    """Fit planes y = a + b·i + c·j (grid units) to a grid of heights with gaps (NaN).
    Returns a list of (coefficients, mask of the cells that lie on it)."""
    nv, nu = Y.shape
    rem = ~np.isnan(Y)
    total = int(rem.sum())
    minpts = max(10, min(int(0.05 * total), 40))
    jj, ii = np.mgrid[0:nv, 0:nu]
    out = []
    fails = 0
    while rem.sum() >= minpts and len(out) < 12 and fails < 5:
        cells = np.argwhere(rem)
        k = 160
        pick = cells[rng.integers(0, len(cells), k)]
        o1 = rng.integers(-3, 4, (k, 2))
        o2 = rng.integers(-3, 4, (k, 2))
        p1, p2 = pick + o1, pick + o2
        ok = np.ones(k, bool)
        for p in (p1, p2):
            ok &= (p[:, 0] >= 0) & (p[:, 0] < nv) & (p[:, 1] >= 0) & (p[:, 1] < nu)
        p1, p2 = np.clip(p1, 0, [nv - 1, nu - 1]), np.clip(p2, 0, [nv - 1, nu - 1])
        ok &= rem[p1[:, 0], p1[:, 1]] & rem[p2[:, 0], p2[:, 1]]
        det = (o1[:, 1] * o2[:, 0] - o1[:, 0] * o2[:, 1]).astype(float)
        ok &= np.abs(det) >= 4
        if not ok.any():
            fails += 1
            continue
        pick, p1, p2, o1, o2, det = pick[ok], p1[ok], p2[ok], o1[ok], o2[ok], det[ok]
        y0 = Y[pick[:, 0], pick[:, 1]]
        d1 = Y[p1[:, 0], p1[:, 1]] - y0
        d2 = Y[p2[:, 0], p2[:, 1]] - y0
        # d = b·di + c·dj for both partners
        b = (d1 * o2[:, 0] - d2 * o1[:, 0]) / det
        c = (d2 * o1[:, 1] - d1 * o2[:, 1]) / det
        a = y0 - b * pick[:, 1] - c * pick[:, 0]
        steep = np.hypot(b, c) / STEP < 1.9                      # not a wall or the side of a tree
        ri, rj, ry = ii[rem], jj[rem], Y[rem]
        res = np.abs(a[:, None] + b[:, None] * ri[None, :] + c[:, None] * rj[None, :] - ry[None, :]) < TOL
        count = res.sum(1) * steep
        best = int(np.argmax(count))
        if count[best] < minpts:
            fails += 1
            continue
        coef = np.array([a[best], b[best], c[best]])
        inl = res[best]
        for _ in range(2):                                       # refine on its own points
            A = np.stack([np.ones(inl.sum()), ri[inl], rj[inl]], 1)
            coef, *_ = np.linalg.lstsq(A, ry[inl], rcond=None)
            inl = np.abs(coef[0] + coef[1] * ri + coef[2] * rj - ry) < TOL
            if inl.sum() < 3:
                break
        mask = np.zeros_like(rem)
        mask[rj[inl], ri[inl]] = True
        lab, n = ndimage.label(mask, structure=FULL)             # one connected patch at a time
        if n > 1:
            sizes = ndimage.sum(mask, lab, range(1, n + 1))
            mask = lab == (1 + int(np.argmax(sizes)))
        if mask.sum() < minpts or np.hypot(coef[1], coef[2]) / STEP > 1.9:
            fails += 1
            rem &= ~mask if mask.sum() < 4 else rem
            continue
        fails = 0
        out.append([coef, mask])
        rem &= ~mask
    # points left over join a neighbouring plane they nearly lie on
    for _ in range(3):
        for coef, mask in out:
            near = ndimage.binary_dilation(mask, FULL) & rem
            near &= np.abs(coef[0] + coef[1] * ii + coef[2] * jj - np.nan_to_num(Y, nan=1e9)) < 0.35
            mask |= near
            rem &= ~near
    return out, rem


def _largest_rect(mask):
    """The largest rectangle of set cells in a grid: (area, j0, j1, i0, i1), ends exclusive."""
    nv, nu = mask.shape
    height = np.zeros(nu, int)
    best = (0, 0, 0, 0, 0)
    for j in range(nv):
        height = np.where(mask[j], height + 1, 0)
        stack = []
        for i in range(nu + 1):
            h = height[i] if i < nu else 0
            start = i
            while stack and stack[-1][1] >= h:
                st, hh = stack.pop()
                if hh * (i - st) > best[0]:
                    best = (hh * (i - st), j - hh + 1, j + 1, st, i)
                start = st
            stack.append((start, h))
    return best


def _wing_roof(Y, j0, j1, i0, i1, Yd=None):
    """The roof of one rectangular wing, from the measured heights inside it. Returns (planes, mean error):
    planes as [a, b, c] with y = a + b·i + c·j in grid cells; one plane for a flat or single-pitch roof, two
    for a pitched one, four when its ends are hipped."""
    sub = Y[j0:j1, i0:i1]
    ok = ~np.isnan(sub)
    if ok.sum() < 4:
        return None
    if Yd is not None:                                           # well inside the walls the laser is not blurred by the drop to the ground
        deep = ~np.isnan(Yd[j0:j1, i0:i1])
        if deep.sum() >= max(8, 0.4 * ok.sum()):
            sub, ok = Yd[j0:j1, i0:i1], deep
    jj, ii = np.mgrid[j0:j1, i0:i1]
    y, ci, cj = sub[ok], ii[ok].astype(float), jj[ok].astype(float)
    keep = y <= np.percentile(y, 97) + 0.3                      # a tree leaning over, an aerial
    y, ci, cj = y[keep], ci[keep], cj[keep]
    level = float(np.median(y))
    best = ([np.array([level, 0.0, 0.0])], float(np.mean(np.abs(y - level))))
    if len(y) >= 8:
        A = np.stack([np.ones(len(y)), ci, cj], 1)                # one sloping plane
        coef, *_ = np.linalg.lstsq(A, y, rcond=None)
        slope = math.hypot(coef[1], coef[2]) / STEP
        e = float(np.mean(np.abs(A @ coef - y)))
        if 0.08 <= slope <= 0.9 and e < 0.7 * best[1] - 0.02:
            best = ([coef], e)
    mi, mj = (i0 + i1 - 1) / 2.0, (j0 + j1 - 1) / 2.0
    hi_, hj_ = (i1 - i0) / 2.0, (j1 - j0) / 2.0
    if len(y) >= 12 and min(hi_, hj_) * STEP >= 1.4:
        for across, half, along, hlen, axis in ((cj - mj, hj_, ci - mi, hi_, 0), (ci - mi, hi_, cj - mj, hj_, 1)):
            t = np.abs(across) / half
            A = np.stack([np.ones(len(y)), -t], 1)
            (top, rise), *_ = np.linalg.lstsq(A, y, rcond=None)
            run = half * STEP
            if rise < 0.5 or rise / run < 0.2:
                continue
            rise = min(rise, 1.3 * run, 7.0, max(0.5, top - (float(np.percentile(y, 6)) - 0.3)))   # the eaves are where they were measured
            m = rise / half                                        # per cell
            got = top - m * np.abs(across)
            ends = []
            if hlen >= half * 0.95:                                # do the ends come down too (a hipped roof, a pyramid)?
                hip = np.minimum(got, top - m * (np.abs(along) - (hlen - half)))
                if float(np.mean(np.abs(hip - y))) < 0.85 * float(np.mean(np.abs(got - y))):
                    got, ends = hip, [1.0, -1.0]
            e = float(np.mean(np.abs(got - y)))
            if e < 0.8 * best[1] - 0.03:
                planes = []
                for sgn in (1.0, -1.0):                            # y = top - m·sgn·(x - mid) on each side
                    if axis == 0:
                        planes.append(np.array([top + m * sgn * mj, 0.0, -m * sgn]))
                    else:
                        planes.append(np.array([top + m * sgn * mi, -m * sgn, 0.0]))
                for sgn in ends:                                   # y = top - m·(sgn·(s - mid) - (hlen - half))
                    k = top + m * (hlen - half)
                    if axis == 0:
                        planes.append(np.array([k + m * sgn * mi, -m * sgn, 0.0]))
                    else:
                        planes.append(np.array([k + m * sgn * mj, 0.0, -m * sgn]))
                best = (planes, e)
    return best


def _wings(Y, M, cover, Yd=None):
    """A building as rectangular wings, each with a roof of its own: the outline (cells M) is cut into the
    largest rectangles that fit it, a rectangle is cut again where the measured roof steps up or down along it
    (a house and its lower garage drawn as one), and every wing gets a flat, single-pitch, pitched or hipped
    roof from the heights measured inside it. Returns (list of plane lists, label grid over `cover`, boxes)."""
    left = M.copy()
    total = int(M.sum())
    boxes = []
    while len(boxes) < 6:
        area, j0, j1, i0, i1 = _largest_rect(left)
        if area < max(10, 0.06 * total) or min(j1 - j0, i1 - i0) < 3:
            break
        boxes.append((j0, j1, i0, i1))
        left[j0:j1, i0:i1] = False
    if not boxes:
        return None
    # a step in the roof along a rectangle: two wings
    cut = []
    for j0, j1, i0, i1 in boxes:
        parts = [(j0, j1, i0, i1)]
        for axis in (1, 0):
            new = []
            for b in parts:
                a0, a1 = (b[2], b[3]) if axis == 1 else (b[0], b[1])
                sub = Y[b[0]:b[1], b[2]:b[3]]
                import warnings
                with warnings.catch_warnings():
                    warnings.simplefilter("ignore")
                    prof = np.nanmedian(sub, axis=0 if axis == 1 else 1)
                at, jump = -1, 1.1
                for s in range(4, len(prof) - 4):
                    a, c = prof[:s], prof[s:]
                    if np.isnan(a).all() or np.isnan(c).all():
                        continue
                    whole = abs(float(np.nanmedian(a)) - float(np.nanmedian(c)))
                    here = abs(float(np.nanmedian(prof[max(0, s - 2):s])) - float(np.nanmedian(prof[s:s + 2])))
                    if min(whole, here) > jump:
                        at, jump = s, min(whole, here)
                if at > 0:
                    if axis == 1:
                        new += [(b[0], b[1], b[2], b[2] + at), (b[0], b[1], b[2] + at, b[3])]
                    else:
                        new += [(b[0], b[0] + at, b[2], b[3]), (b[0] + at, b[1], b[2], b[3])]
                else:
                    new.append(b)
            parts = new
        cut += parts
    boxes = cut
    roofs_, keep = [], []
    for b in boxes:
        r = _wing_roof(Y, *b, Yd=Yd)
        if r is not None:
            roofs_.append(r[0])
            keep.append(b)
    if not keep:
        return None
    label = np.zeros(M.shape, int)
    for g, (j0, j1, i0, i1) in enumerate(keep):
        label[j0:j1, i0:i1] = g + 1
    label[~cover] = 0
    _d, (nj, ni) = ndimage.distance_transform_edt(label == 0, return_indices=True)
    fill = cover & (label == 0)
    label[fill] = label[nj[fill], ni[fill]]
    return roofs_, label, keep


def flat_roof(pts, y):
    """A plain flat roof at height y over an outline: the same form as fit() returns."""
    P = np.asarray(pts, float)
    x, z = P[:, 0], P[:, 1]
    if float(np.sum(x * np.roll(z, -1) - np.roll(x, -1) * z)) < 0:
        P = P[::-1]                                       # walls must run the same way round as in fit(), or they face inward
    n = len(P)
    walls = []
    for i in range(n):
        a, b = P[i], P[(i + 1) % n]
        ln = float(np.hypot(*(b - a)))
        if ln > 0.05:
            walls.append([round(a[0], 2), round(a[1], 2), round(b[0], 2), round(b[1], 2), 0.0, round(y, 2), round(ln, 2), round(y, 2), 0, 0, 0])
    face = [1] + [round(float(q), 2) for p in P for q in (p[0], y, p[1])]
    return {"f": [face], "w": walls, "s": [], "eave": y, "top": y, "kind": 0, "simple": True}


def fit(pts, dom, ground_lo, seed=0, force_plain=False):
    """Roof of one building. pts: outline in game coordinates (x, z). dom: laser surface sampler.
    Returns {"f": faces, "w": walls, "s": steps, "eave", "top", "kind"} or None without laser data."""
    P = np.asarray(pts, float)
    foot_w = Polygon(P)
    if not foot_w.is_valid or foot_w.area < 4:
        return None
    rng = np.random.default_rng(seed)
    seg = np.roll(P, -1, 0) - P
    k = int(np.argmax((seg ** 2).sum(1)))
    u = seg[k] / np.hypot(*seg[k])
    v = np.array([-u[1], u[0]])
    c = P.mean(0)
    Q = np.stack([(P - c) @ u, (P - c) @ v], 1)                  # the outline in the building's frame
    foot = Polygon(Q)
    if not foot.is_valid:
        return None
    foot = shapely.geometry.polygon.orient(foot, 1.0)
    u0, v0 = Q[:, 0].min() - STEP, Q[:, 1].min() - STEP
    nu = int((Q[:, 0].max() - u0) / STEP) + 2
    nv = int((Q[:, 1].max() - v0) / STEP) + 2
    if nu * nv > 400000:
        return None
    jj, ii = np.mgrid[0:nv, 0:nu]
    U = u0 + (ii + 0.5) * STEP
    V = v0 + (jj + 0.5) * STEP

    def world(uu, vv):
        return c[0] + uu * u[0] + vv * v[0], c[1] + uu * u[1] + vv * v[1]

    cover = shapely.contains_xy(foot.buffer(STEP * 0.75), U.ravel(), V.ravel()).reshape(U.shape)   # every cell the outline touches
    inner = shapely.contains_xy(foot.buffer(-0.35), U.ravel(), V.ravel()).reshape(U.shape)
    if inner.sum() < 4:
        inner = shapely.contains_xy(foot, U.ravel(), V.ravel()).reshape(U.shape)
    if inner.sum() < 3:
        return None
    Y = np.full(U.shape, np.nan)
    X, Z = world(U[inner], V[inner])
    Y[inner] = dom.bilinear(X, Z)
    Y[Y < ground_lo + 1.5] = np.nan                              # the yard showing inside the outline
    valid = ~np.isnan(Y)
    total = int(valid.sum())
    dormers = []                                                 # boxes the laser shows standing up out of a plain pitched roof
    if total < 3:
        return None
    # a plain fallback roof is never taller than a building of that size can be (a tree over a shed is not a tower)
    area = foot.area
    tallest = ground_lo + (3.6 if area < 40 else 8.5 if area < 150 else 12.5 if area < 450 else 60.0)
    if total < 12:
        return flat_roof(pts, min(float(np.nanmedian(Y)), tallest))
    cut = np.nanpercentile(Y, 99) + 3.0                          # masts, a tree leaning over
    Y[Y > cut] = np.nan

    planes, left = _planes(Y, rng)
    # scraps are not parts of a roof: a plane must cover a fair share of the building to count
    planes = [p for p in planes if p[1].sum() >= max(12, 0.07 * total)]
    if not planes:
        return flat_roof(pts, min(float(np.nanmedian(Y)), tallest))
    # nearly level planes are made level
    flat = []
    for p in planes:
        slope = math.hypot(p[0][1], p[0][2]) / STEP
        if slope < 0.05:
            p[0] = np.array([float(np.mean(Y[p[1]])), 0.0, 0.0])
        flat.append(slope < 0.09)

    def ev(coef, i, j):
        return coef[0] + coef[1] * i + coef[2] * j

    # bodies: sloping planes that touch and bend the right way round each other (ridges, hips)
    order = sorted(range(len(planes)), key=lambda q: -planes[q][1].sum())
    bodies = []

    def fits(a, b):
        if flat[a] and flat[b]:
            return False
        ma, mb = planes[a][1], planes[b][1]
        if not (ndimage.binary_dilation(ma, FULL, iterations=2) & mb).any():
            return False
        ca, cb = planes[a][0], planes[b][0]
        ok_a = np.mean(ev(cb, ii[ma], jj[ma]) >= ev(ca, ii[ma], jj[ma]) - 0.25)
        ok_b = np.mean(ev(ca, ii[mb], jj[mb]) >= ev(cb, ii[mb], jj[mb]) - 0.25)
        return ok_a > 0.9 and ok_b > 0.9

    for q in order:
        for body in bodies:
            if all(fits(q, m) for m in body):
                body.append(q)
                break
        else:
            bodies.append([q])

    # A big building whose roof is not one simple shape is built as blocks: each part flat at its own
    # measured height, parts of nearly the same height run together. Stepped flat blocks are what large
    # halls, shops and schools look like; a patchwork of slopes is not.
    shares = sorted((sum(int(planes[q][1].sum()) for q in body) for body in bodies), reverse=True)
    if area >= 450 and not (len(bodies) == 1 or (len(bodies) == 2 and shares[0] >= 0.8 * sum(shares))):
        blocks = []
        for body in bodies:
            mask = np.zeros(U.shape, bool)
            for q in body:
                mask |= planes[q][1]
            blocks.append([float(np.median(Y[mask])), mask])
        blocks.sort(key=lambda q: q[0])
        merged = [blocks[0]]
        for level, mask in blocks[1:]:
            if level - merged[-1][0] < 1.5:
                a, b = int(merged[-1][1].sum()), int(mask.sum())
                merged[-1] = [(merged[-1][0] * a + level * b) / (a + b), merged[-1][1] | mask]
            else:
                merged.append([level, mask])
        planes = [[np.array([level, 0.0, 0.0]), mask] for level, mask in merged]
        flat = [True] * len(planes)
        bodies = [[k] for k in range(len(planes))]

    def surf(body, i, j):
        return np.min([ev(planes[q][0], i, j) for q in body], 0)

    # every cell of the outline goes to a body: its own, or the nearest when nearly all of the roof was understood
    label = np.zeros(U.shape, int)
    for g, body in enumerate(bodies):
        for q in body:
            label[planes[q][1]] = g + 1
    covered = (label > 0).sum() / max(total, 1)
    dist, (nj, ni) = ndimage.distance_transform_edt(label == 0, return_indices=True)
    # (a roof always reaches the walls on every side: cells left blank would show as bites out of its corners)
    unknown = cover & (label == 0) & (dist > 2.5) if covered < 0.8 else np.zeros(U.shape, bool)
    fill = cover & (label == 0)
    label[fill] = label[nj[fill], ni[fill]]
    rest = unknown
    low = float(min(surf(body, ii[label == g + 1], jj[label == g + 1]).min() for g, body in enumerate(bodies)))
    if rest.any() and (left & rest).sum() >= 6:
        base_y = float(np.nanmedian(Y[left & rest]))
    else:
        base_y = low - 0.25
    base_y = max(base_y, ground_lo + 2.4)                  # no roof comes down lower than a wall can stand
    # where two bodies run into each other at the same height (a valley), each reaches a little into the other,
    # so that the line between them is where their surfaces really cross
    regions = []
    for g, body in enumerate(bodies):
        mine = label == g + 1
        grow = np.zeros_like(mine)
        ring = ndimage.binary_dilation(mine, FULL) & ~mine & (label > 0)
        for h in set(label[ring].tolist()):
            cells = ring & (label == h)
            same = np.abs(surf(body, ii[cells], jj[cells]) - surf(bodies[h - 1], ii[cells], jj[cells])) < 0.6
            seedm = np.zeros_like(mine)
            seedm[jj[cells][same], ii[cells][same]] = True
            grow |= ndimage.binary_dilation(seedm, FULL, iterations=3) & (label == h)
        # straighten the stepped edge of the cells; a little too wide rather than leaving a gap
        geom = _cells_polygon(mine | grow, u0, v0).simplify(0.5).buffer(0.75, join_style="mitre").intersection(foot)
        regions.append(geom)
    if len(bodies) == 1:
        regions = [foot]

    # ---- does the result make sense? A roof that could not be understood (trees over it, scaffolding, too
    # few points, a shape too involved for this method) comes out as spikes, pits and stray walls. Such a
    # building gets a plain roof instead that is at least believable: a simple pitched roof along its length
    # with the measured eaves and ridge heights, or a flat one at the measured height.
    errs = []
    means = []
    for g, body in enumerate(bodies):
        mine = (label == g + 1) & valid & ~np.isnan(Y)
        if mine.any():
            errs.append(np.abs(surf(body, ii[mine], jj[mine]) - Y[mine]))
            means.append((float(np.mean(Y[mine])), int(mine.sum())))
    err = np.concatenate(errs) if errs else np.array([9.0])
    steepest = max(math.hypot(p[0][1], p[0][2]) / STEP for p in planes)
    small_bodies = [m for m, n in means if n < 0.2 * total]
    main_level = max(means, key=lambda q: q[1])[0] if means else 0.0
    # a house is held to a stricter test, well inside its walls: the planes together must give the measured
    # roof nearly everywhere (planes of a cross-gable cut into each other's corners if taken as one shape)
    deep = shapely.contains_xy(foot.buffer(-1.2), U.ravel(), V.ravel()).reshape(U.shape) & valid & ~np.isnan(Y)
    strict = False
    if area < 350 and deep.sum() >= 12:
        got = np.full(U.shape, np.nan)
        for g, body in enumerate(bodies):
            mine = (label == g + 1) & deep
            if mine.any():
                got[mine] = surf(body, ii[mine], jj[mine])
        miss = np.abs(got[deep] - Y[deep])
        strict = float(np.mean(miss > 0.6)) > 0.06 or (area < 120 and len(bodies) > 1)
    odd = (force_plain or strict or float(np.mean(err)) > 0.45 or float(np.percentile(err, 90)) > 1.3
           or (rest.any() and (left & rest).sum() >= 6 and area < 700)
           or (area < 350 and (len(bodies) > 2 or len(planes) > 5 or steepest > 1.25))
           or (area < 350 and any(abs(m - main_level) > 3.2 for m in small_bodies)))
    simple = False
    if odd:
        ok_y = Y[valid & ~np.isnan(Y)]
        along_u = (Q[:, 0].max() - Q[:, 0].min()) >= (Q[:, 1].max() - Q[:, 1].min())
        X = V if along_u else U                                    # the coordinate across the ridge
        lo, hi = (Q[:, 1].min(), Q[:, 1].max()) if along_u else (Q[:, 0].min(), Q[:, 0].max())
        mid, hw = (lo + hi) / 2, (hi - lo) / 2
        eave_y, ridge_y = float(np.percentile(ok_y, 10)), float(np.percentile(ok_y, 96))
        eave_y = min(eave_y, tallest)
        ridge_y = min(ridge_y, eave_y + 5.0)
        plain_flat = area > 450 or ridge_y - eave_y < 0.7 or (ridge_y - eave_y) / hw < 0.18
        level = min(float(np.percentile(ok_y, 60)), tallest)
        if plain_flat:
            plain_planes = [[np.array([level, 0.0, 0.0]), valid.copy()]]
        else:
            slope = min(max((ridge_y - eave_y) / hw, 0.3), 1.1)
            ridge_y = eave_y + slope * hw
            first = (u0 if not along_u else v0) + 0.5 * STEP
            plain_planes = []
            for sgn in (-1.0, 1.0):                                    # y = k + m·X on each side of the ridge
                m = -sgn * slope
                k = ridge_y - m * mid
                coef = np.array([k + m * first, 0.0, m * STEP]) if along_u else np.array([k + m * first, m * STEP, 0.0])
                plain_planes.append([coef, valid & ((X - mid) * sgn > 0)])
            if not plain_planes[0][1].any() or not plain_planes[1][1].any():
                plain_flat, plain_planes = True, [[np.array([level, 0.0, 0.0]), valid.copy()]]
        meas = valid & ~np.isnan(Y)
        plain_err = float(np.mean(np.abs(np.min([ev(p[0], ii[meas], jj[meas]) for p in plain_planes], 0) - Y[meas])))
        # the same building as wings, each with its own roof: taken when it agrees clearly better with the laser
        Yd = np.where(shapely.contains_xy(foot.buffer(-1.0), U.ravel(), V.ravel()).reshape(U.shape), Y, np.nan)
        wing = None if force_plain else _wings(Y, shapely.contains_xy(foot, U.ravel(), V.ravel()).reshape(U.shape), cover, Yd)
        if wing is not None:
            w_roofs, w_label, w_boxes = wing
            got = np.full(U.shape, np.nan)
            for g, pl in enumerate(w_roofs):
                mine = (w_label == g + 1) & meas
                if mine.any():
                    got[mine] = np.min([ev(c_, ii[mine], jj[mine]) for c_ in pl], 0)
            w_ok = meas & ~np.isnan(got)
            wing_err = float(np.mean(np.abs(got[w_ok] - Y[w_ok]))) if w_ok.sum() >= 6 else 9.0
            if (len(w_roofs) == 1 and len(w_roofs[0]) == 1 and abs(w_roofs[0][0][1]) + abs(w_roofs[0][0][2]) < 1e-9) \
                    or wing_err > 0.85 * plain_err - 0.03 or wing_err > 1.2:
                wing = None                                            # one flat block, or no better than the plain roof
        if wing is None:
            if plain_flat:
                return flat_roof(pts, level)
            planes, flat = plain_planes, [False, False]
            bodies, regions, simple = [[0, 1]], [foot], True
            # dormers: where the laser stands half a metre or more over the plain roof in a compact, level patch
            # of some square metres on one slope (a tree over the roof is neither compact nor level)
            res = np.full(U.shape, np.nan)
            res[meas] = Y[meas] - np.min([ev(p[0], ii[meas], jj[meas]) for p in plain_planes], 0)
            up_ = meas & (res > 0.45) & (res < 2.4)
            if 0 < up_.sum() < 0.22 * meas.sum():
                lab_, nl_ = ndimage.label(up_)
                inside_ = foot.buffer(-0.6)
                for g_ in range(1, nl_ + 1):
                    m_ = lab_ == g_
                    n_ = int(m_.sum())
                    if n_ < 4 or n_ > 34:
                        continue
                    js_, is_ = np.nonzero(m_)
                    du_, dv_ = (is_.max() - is_.min() + 1) * STEP, (js_.max() - js_.min() + 1) * STEP
                    wid_, dep_ = (du_, dv_) if along_u else (dv_, du_)          # along the ridge, across it
                    if n_ * STEP * STEP < 0.55 * du_ * dv_ or not (1.2 <= wid_ <= 5.0 and 0.7 <= dep_ <= 4.5) or float(np.std(Y[m_])) > 0.45:
                        continue
                    cu_, cv_ = float(U[m_].mean()), float(V[m_].mean())
                    xc_ = cv_ if along_u else cu_
                    if abs(xc_ - mid) < 0.9 or not inside_.contains(shapely.Point(cu_, cv_)):
                        continue
                    out_ = (v if along_u else u) * (1.0 if xc_ > mid else -1.0)  # down the slope it stands on
                    wx_, wz_ = world(cu_, cv_)
                    top_ = float(np.percentile(Y[m_], 75))
                    dormers.append([round(float(wx_), 2), round(float(wz_), 2), round(top_, 2), round(wid_, 2), round(dep_, 2),
                                    round(float(out_[0]), 3), round(float(out_[1]), 3), round(top_ - float(np.median(res[m_])), 2)])
                dormers = dormers[:4]
            rest = np.zeros(U.shape, bool)
            base_y = eave_y - 1.0
        else:
            planes, flat, bodies, regions = [], [], [], []
            lows = []
            for g, pl in enumerate(w_roofs):
                body = []
                mine = w_label == g + 1
                for c_ in pl:
                    c_ = np.array(c_, float)
                    is_flat = abs(c_[1]) + abs(c_[2]) < 1e-9
                    planes.append([c_, mine])
                    flat.append(is_flat)
                    body.append(len(planes) - 1)
                bodies.append(body)
                geom = _cells_polygon(mine, u0, v0).buffer(0.4, join_style="mitre").intersection(foot)
                regions.append(geom)
                if mine.any():
                    lows.append(float(np.min([ev(planes[q][0], ii[mine], jj[mine]) for q in body], 0).min()))
            # where a pitched wing runs into the side of another, its roof carries on into it as far as that
            # one's ridge, so that the two meet in valleys instead of at an upright wall
            for g, (j0, j1, i0, i1) in enumerate(w_boxes):
                if len(w_roofs[g]) < 2:
                    continue
                ridge_u = abs(w_roofs[g][0][1]) < 1e-9             # its ridge runs along u when the planes fall along v (j)
                for h, (J0, J1, I0, I1) in enumerate(w_boxes):
                    if h == g or len(w_roofs[h]) < 2:
                        continue
                    other_u = abs(w_roofs[h][0][1]) < 1e-9
                    if ridge_u == other_u:
                        continue
                    if ridge_u:                                    # g's strip is its rows; it meets h end on, to the left or right
                        if not (j0 >= J0 - 1 and j1 <= J1 + 1 and (abs(i1 - I0) <= 1 or abs(i0 - I1) <= 1)):
                            continue
                        mid_i = (I0 + I1) / 2.0
                        ia, ib = (I0, mid_i) if abs(i1 - I0) <= 1 else (mid_i, I1)
                        ext = box(u0 + ia * STEP, v0 + j0 * STEP, u0 + ib * STEP, v0 + j1 * STEP)
                    else:
                        if not (i0 >= I0 - 1 and i1 <= I1 + 1 and (abs(j1 - J0) <= 1 or abs(j0 - J1) <= 1)):
                            continue
                        mid_j = (J0 + J1) / 2.0
                        ja, jb = (J0, mid_j) if abs(j1 - J0) <= 1 else (mid_j, J1)
                        ext = box(u0 + i0 * STEP, v0 + ja * STEP, u0 + i1 * STEP, v0 + jb * STEP)
                    regions[g] = unary_union([regions[g], ext.intersection(foot)])
            simple = True
            rest = np.zeros(U.shape, bool)
            base_y = max(min(lows) - 0.6, ground_lo + 2.2) if lows else eave_y - 1.0

    roof_kind = 0 if all(flat[q] for body in bodies for q in body) else (2 if any(len(b) >= 3 for b in bodies) else 1)
    # a plane carried on past the points it was fitted to must not climb above anything that was measured
    for g, body in enumerate(bodies):
        if not simple and not all(flat[q] for q in body):
            cap = max(float(np.max(Y[planes[q][1]])) for q in body) + 0.2
            planes.append([np.array([cap, 0.0, 0.0]), np.zeros(U.shape, bool)])
            flat.append(True)
            body.append(len(planes) - 1)

    def plane_uv(q):
        """Plane as y = a + b·u + c·v in metres."""
        a, b, cc = planes[q][0]
        b, cc = b / STEP, cc / STEP
        return a - b * (u0 + 0.5 * STEP) - cc * (v0 + 0.5 * STEP), b, cc

    puv = {q: plane_uv(q) for q in range(len(planes))}

    def height(g, uu, vv):
        return min(puv[q][0] + puv[q][1] * uu + puv[q][2] * vv for q in bodies[g])

    def top_at(uu, vv, skip=-1):
        """Roof height at a point and the body it belongs to (-1: the base level)."""
        best, who = base_y, -1
        pt = shapely.Point(uu, vv)
        for g in range(len(bodies)):
            if g != skip and regions[g].covers(pt):
                h = height(g, uu, vv)
                if h > best:
                    best, who = h, g
        return best, who

    # ---- roof faces
    faces = []
    R = 1e4
    for g, body in enumerate(bodies):
        for q in body:
            geom = regions[g]
            a, b, cc = puv[q]
            for r in body:
                if r == q or geom.is_empty:
                    continue
                a2, b2, c2 = puv[r]
                n = np.array([b - b2, cc - c2])                  # this plane is the lower one where n·p + (a - a2) <= 0
                ln = np.hypot(*n)
                if ln < 1e-9:
                    if a > a2:
                        geom = Polygon()
                    continue
                n /= ln
                p0 = -(a - a2) / ln * n
                t = np.array([-n[1], n[0]])
                geom = geom.intersection(Polygon([p0 + t * R, p0 - t * R, p0 - t * R - n * R, p0 + t * R - n * R]))
            for poly in _polys(geom):
                poly = poly.simplify(0.03)
                if poly.area < 0.15:
                    continue
                ring = list(poly.exterior.coords)[:-1]
                face = [1 if flat[q] else 0]
                for uu, vv in ring:
                    x, z = world(uu, vv)
                    face += [round(x, 2), round(a + b * uu + cc * vv, 2), round(z, 2)]
                faces.append(face)
    if True:                                               # the level nothing goes below, over the whole outline
        face = [1]
        for uu, vv in list(foot.exterior.coords)[:-1]:
            x, z = world(uu, vv)
            face += [round(x, 2), round(base_y, 2), round(z, 2)]
        faces.append(face)

    # ---- outer walls: the line the top of each follows
    ring = list(foot.exterior.coords)[:-1]
    walls = []
    eave_samples = []
    hi = base_y
    bounds = [reg.boundary for reg in regions]
    for i in range(len(ring)):
        A, B = np.array(ring[i]), np.array(ring[(i + 1) % len(ring)])
        ln = float(np.hypot(*(B - A)))
        if ln < 0.05:
            continue
        t = (B - A) / ln
        nin = np.array([-t[1], t[0]])                            # into the building (outline runs anticlockwise)
        A2, B2 = A + nin * 0.06, B + nin * 0.06
        line = shapely.LineString([A2, B2])
        cuts = {0.0, ln}
        for bd in bounds:                                        # where a body starts or stops
            hit = line.intersection(bd)
            for pt in shapely.get_coordinates(hit):
                cuts.add(float(np.clip((pt - A2) @ t, 0, ln)))
        for body in bodies:                                      # where two planes of a body cross
            for x in range(len(body)):
                for y in range(x + 1, len(body)):
                    p, q = puv[body[x]], puv[body[y]]
                    d0 = (p[0] - q[0]) + (p[1] - q[1]) * A2[0] + (p[2] - q[2]) * A2[1]
                    d1 = (p[1] - q[1]) * t[0] + (p[2] - q[2]) * t[1]
                    if abs(d1) > 1e-9 and 0 < -d0 / d1 < ln:
                        cuts.add(float(-d0 / d1))
        cuts = sorted(cuts)
        pieces = []
        for s0, s1 in zip(cuts, cuts[1:]):
            if s1 - s0 < 0.03:
                continue
            mid = A2 + t * (s0 + s1) / 2
            lines = [(base_y, base_y, -1, -1)]
            for g in range(len(bodies)):
                if regions[g].covers(shapely.Point(mid)):
                    q = min(bodies[g], key=lambda r: puv[r][0] + puv[r][1] * mid[0] + puv[r][2] * mid[1])
                    a, b, cc = puv[q]
                    e0, e1 = A2 + t * s0, A2 + t * s1
                    lines.append((a + b * e0[0] + cc * e0[1], a + b * e1[0] + cc * e1[1], g, q))
            sub = {0.0, 1.0}
            for x in range(len(lines)):                          # where one body rises above another
                for y in range(x + 1, len(lines)):
                    da, db = lines[x][0] - lines[y][0], lines[x][1] - lines[y][1]
                    if da * db < 0:
                        sub.add(da / (da - db))
            sub = sorted(sub)
            for f0, f1 in zip(sub, sub[1:]):
                if (f1 - f0) * (s1 - s0) < 0.03:
                    continue
                fm = (f0 + f1) / 2
                y0, y1, g, q = max(lines, key=lambda L: L[0] + (L[1] - L[0]) * fm)
                ya, yb = y0 + (y1 - y0) * f0, y0 + (y1 - y0) * f1
                sa, sb = s0 + (s1 - s0) * f0, s0 + (s1 - s0) * f1
                kind, oa, ob = 0, ya, yb
                if q >= 0 and not flat[q]:
                    a, b, cc = puv[q]
                    kind = 1
                    ea, eb = A + t * sa - nin * EAVE, A + t * sb - nin * EAVE     # the roof carried out past the wall
                    oa, ob = a + b * ea[0] + cc * ea[1], a + b * eb[0] + cc * eb[1]
                pieces.append([sa, ya, sb, yb, kind, oa, ob])
                eave_samples += [(min(ya, yb), sb - sa)]
                hi = max(hi, ya, yb)
        run = []
        for pc in pieces + [None]:                               # a new wall where the top jumps
            if pc is not None and (not run or abs(run[-1][3] - pc[1]) < 0.4):
                run.append(pc)
                continue
            if run:
                a0, b0 = A + t * run[0][0], A + t * run[-1][2]
                xa, za = world(*a0)
                xb, zb = world(*b0)
                rec = [round(xa, 2), round(za, 2), round(xb, 2), round(zb, 2)]
                for sa, ya, sb, yb, kind, oa, ob in run:
                    rec += [round(sa - run[0][0], 2), round(ya, 2), round(sb - run[0][0], 2), round(yb, 2), kind, round(oa, 2), round(ob, 2)]
                walls.append(rec)
            run = [pc] if pc is not None else []

    # ---- upright faces inside the outline, where a higher body stands over a lower one
    steps = []
    edge = foot.boundary
    for g in range(len(bodies)):
        for poly in _polys(regions[g]):
            for r in [poly.exterior] + list(poly.interiors):
                cs = np.asarray(r.coords)
                ccw = r.is_ccw
                for A, B in zip(cs[:-1], cs[1:]):
                    ln = float(np.hypot(*(B - A)))
                    if ln < 0.05:
                        continue
                    mid = (A + B) / 2
                    if edge.distance(shapely.Point(mid)) < 0.04:
                        continue
                    t = (B - A) / ln
                    out = np.array([t[1], -t[0]]) * (1 if ccw else -1)
                    hm = height(g, *mid)
                    below, _ = top_at(*(mid + out * 0.08), skip=g)
                    if hm <= below + 0.05:
                        continue
                    ya, yb = height(g, *A), height(g, *B)
                    xa, za = world(*A)
                    xb, zb = world(*B)
                    ox, oz = out[0] * u[0] + out[1] * v[0], out[0] * u[1] + out[1] * v[1]
                    steps.append([round(xa, 2), round(za, 2), round(xb, 2), round(zb, 2), round(ya, 2), round(yb, 2),
                                  round(min(below, ya, yb), 2), round(ox, 3), round(oz, 3)])
                    hi = max(hi, ya, yb)

    if not walls:
        return flat_roof(pts, float(np.nanmedian(Y)))
    eave_samples.sort()
    acc, half = 0.0, 0.15 * sum(w for _, w in eave_samples)
    eave = eave_samples[0][0]
    for y, w in eave_samples:
        acc += w
        if acc >= half:
            eave = y
            break
    return {"f": faces, "w": walls, "s": steps, "eave": round(float(eave), 2), "top": round(float(hi), 2), "kind": roof_kind, "simple": simple, "d": dormers}
