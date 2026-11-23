#!/usr/bin/env python3
"""The faces of the road signs, drawn into one picture (world/textures/signs.png) that the game cuts the plates from.

Each face is drawn in metres on its own plate and squeezed into one square of the picture; build_map.py asks
`face_of(number, text)` which square a sign of the road database gets and how large its plate is.

  tools/sign_faces.py        draw the picture and say what is in it
"""
import math, os, re
from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CELL, COLS, SS = 128, 8, 4
RED, BLUE, YELLOW, WHITE, BLACK, GREY, GREEN = (200, 22, 28), (20, 78, 160), (248, 196, 20), (245, 245, 240), (16, 16, 18), (120, 122, 126), (20, 120, 70)
_FONTS = ["/usr/share/fonts/noto/NotoSans-Bold.ttf", "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf", "/usr/share/fonts/liberation/LiberationSans-Bold.ttf"]


def _font(px):
    for f in _FONTS:
        if os.path.exists(f):
            return ImageFont.truetype(f, px)
    return ImageFont.load_default()


class Plate:
    """One plate, w by h metres, drawn with (0, 0) at its middle, x to the right and y up."""

    def __init__(self, w, h):
        self.w, self.h, self.S = w, h, CELL * SS
        self.im = Image.new("RGBA", (self.S, self.S), (0, 0, 0, 0))
        self.d = ImageDraw.Draw(self.im)

    def px(self, x, y):
        return ((x / self.w + 0.5) * self.S, (0.5 - y / self.h) * self.S)

    def poly(self, pts, col):
        self.d.polygon([self.px(x, y) for x, y in pts], fill=col)

    def disc(self, x, y, r, col):
        (x0, y0), (x1, y1) = self.px(x - r, y + r), self.px(x + r, y - r)
        self.d.ellipse([x0, y0, x1, y1], fill=col)

    def box(self, x0, y0, x1, y1, col):
        self.poly([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], col)

    def line(self, pts, wd, col):
        for (xa, ya), (xb, yb) in zip(pts, pts[1:]):
            ln = math.hypot(xb - xa, yb - ya) or 1.0
            nx, ny = -(yb - ya) / ln * wd / 2, (xb - xa) / ln * wd / 2
            self.poly([(xa + nx, ya + ny), (xb + nx, yb + ny), (xb - nx, yb - ny), (xa - nx, ya - ny)], col)
        for x, y in pts:
            self.disc(x, y, wd / 2, col)

    def ngon(self, n, r, col, turn=0.0, x=0.0, y=0.0):
        self.poly([(x + r * math.sin(turn + 2 * math.pi * k / n), y + r * math.cos(turn + 2 * math.pi * k / n)) for k in range(n)], col)

    def text(self, x, y, tall, s, col):
        """Lettering `tall` metres high, its middle at (x, y)."""
        ppm = self.S / self.h
        f = _font(max(8, int(tall * ppm * 1.33)))
        l, t, r, b = f.getbbox(s)
        tmp = Image.new("RGBA", (r - l + 8, b - t + 8), (0, 0, 0, 0))
        ImageDraw.Draw(tmp).text((4 - l, 4 - t), s, font=f, fill=col)
        tmp = tmp.resize((max(1, int(tmp.width * self.h / self.w)), tmp.height), Image.LANCZOS)
        cx, cy = self.px(x, y)
        self.im.alpha_composite(tmp, (int(cx - tmp.width / 2), int(cy - tmp.height / 2)))

    def arrow(self, xa, ya, xb, yb, wd, col):
        ln = math.hypot(xb - xa, yb - ya)
        ux, uy = (xb - xa) / ln, (yb - ya) / ln
        hx, hy = xb - ux * wd * 2.2, yb - uy * wd * 2.2
        self.line([(xa, ya), (hx, hy)], wd, col)
        self.poly([(xb, yb), (hx - uy * wd * 1.5, hy + ux * wd * 1.5), (hx + uy * wd * 1.5, hy - ux * wd * 1.5)], col)

    def walker(self, x, y, tall, col):
        """A walking figure `tall` metres high standing at (x, y)."""
        k = tall
        self.disc(x + 0.03 * k, y + 0.9 * k, 0.09 * k, col)
        self.line([(x + 0.02 * k, y + 0.76 * k), (x, y + 0.42 * k)], 0.13 * k, col)
        self.line([(x, y + 0.42 * k), (x - 0.17 * k, y)], 0.09 * k, col)
        self.line([(x, y + 0.42 * k), (x + 0.12 * k, y + 0.2 * k), (x + 0.2 * k, y)], 0.09 * k, col)
        self.line([(x + 0.02 * k, y + 0.72 * k), (x - 0.16 * k, y + 0.5 * k)], 0.07 * k, col)
        self.line([(x + 0.02 * k, y + 0.72 * k), (x + 0.2 * k, y + 0.55 * k)], 0.07 * k, col)

    def done(self):
        return self.im.resize((CELL, CELL), Image.LANCZOS)


def _triangle(up=True, r=0.45):
    """A warning triangle 0.9 m on a side: red, with the white field inside."""
    p = Plate(0.9, 0.78)
    s = 1.0 if up else -1.0
    out = [(-0.45, -0.39 * s), (0.45, -0.39 * s), (0.0, 0.39 * s)]
    p.poly(out, RED)
    c = (0.0, -0.13 * s)
    p.poly([(c[0] + (x - c[0]) * 0.68, c[1] + (y - c[1]) * 0.68) for x, y in out], WHITE)
    return p


def _ring(col=WHITE, edge=RED, r=0.30):
    p = Plate(2 * r, 2 * r)
    p.disc(0, 0, r, edge)
    p.disc(0, 0, r * 0.76, col)
    return p


def _blue_disc(r=0.30):
    p = Plate(2 * r, 2 * r)
    p.disc(0, 0, r, WHITE)
    p.disc(0, 0, r * 0.95, BLUE)
    return p


def _square(col, w=0.6, h=0.6, edge=WHITE, rim=0.02):
    p = Plate(w, h)
    p.box(-w / 2, -h / 2, w / 2, h / 2, edge)
    p.box(-w / 2 + rim, -h / 2 + rim, w / 2 - rim, h / 2 - rim, col)
    return p


def _diag(p, r, n=5, col=GREY):
    for k in range(n):
        o = (k - (n - 1) / 2) * 0.035
        p.line([(-r * 0.62 + o, -r * 0.62 - o), (r * 0.62 + o, r * 0.62 - o)], 0.012, col)


def _speed(n, end=False):
    p = _ring(edge=WHITE if end else RED)
    if end:
        p.disc(0, 0, 0.30, GREY)
        p.disc(0, 0, 0.285, WHITE)
    p.text(0, 0.0, 0.26, str(n), GREY if end else BLACK)
    if end:
        _diag(p, 0.30, col=BLACK)
    return p


def _zone(n, end=False):
    p = _square(WHITE, 0.6, 0.8, BLACK, 0.015)
    p.disc(0, 0.12, 0.24, GREY if end else RED)
    p.disc(0, 0.12, 0.185, WHITE)
    p.text(0, 0.12, 0.20, str(n), GREY if end else BLACK)
    p.text(0, -0.26, 0.13, "Sone", GREY if end else BLACK)
    if end:
        for k in range(5):
            o = (k - 2) * 0.04
            p.line([(-0.26 + o, -0.36 - o * 0.2), (0.26 + o, 0.36 - o * 0.2)], 0.012, BLACK)
    return p


def _no_park(cross, zone=False, end=False):
    if zone:
        p = _square(WHITE, 0.6, 0.8, BLACK, 0.015)
        cx, cy, r = 0.0, 0.12, 0.24
        p.text(0, -0.26, 0.13, "Sone", GREY if end else BLACK)
    else:
        p = Plate(0.6, 0.6)
        cx, cy, r = 0.0, 0.0, 0.30
    p.disc(cx, cy, r, GREY if end else RED)
    p.disc(cx, cy, r * 0.78, (150, 152, 156) if end else BLUE)
    k = r * 0.64
    p.line([(cx - k, cy + k), (cx + k, cy - k)], r * 0.2, GREY if end else RED)
    if cross:
        p.line([(cx + k, cy + k), (cx - k, cy - k)], r * 0.2, RED)
    return p


def _bus(p, y=0.0, k=1.0):
    p.line([(-0.15 * k, y + 0.10 * k), (0.15 * k, y + 0.10 * k), (0.15 * k, y - 0.07 * k), (-0.15 * k, y - 0.07 * k), (-0.15 * k, y + 0.10 * k)], 0.03 * k, BLACK)
    p.box(-0.15 * k, y - 0.07 * k, 0.15 * k, y + 0.10 * k, BLACK)
    for q in (-0.11, -0.035, 0.04):
        p.box(q * k, y + 0.02 * k, (q + 0.06) * k, y + 0.085 * k, WHITE)
    p.disc(-0.09 * k, y - 0.09 * k, 0.035 * k, BLACK)
    p.disc(0.09 * k, y - 0.09 * k, 0.035 * k, BLACK)


def _car(p, y=0.0, k=1.0, col=BLACK):
    p.poly([(-0.17 * k, y - 0.03 * k), (-0.17 * k, y + 0.03 * k), (-0.10 * k, y + 0.04 * k), (-0.06 * k, y + 0.10 * k), (0.07 * k, y + 0.10 * k),
            (0.12 * k, y + 0.04 * k), (0.17 * k, y + 0.03 * k), (0.17 * k, y - 0.03 * k)], col)
    p.disc(-0.10 * k, y - 0.035 * k, 0.035 * k, col)
    p.disc(0.10 * k, y - 0.035 * k, 0.035 * k, col)


def _bike(p, y=0.0, k=1.0, col=WHITE):
    for sx in (-0.11, 0.11):
        p.disc(sx * k, y, 0.065 * k, col)
        p.disc(sx * k, y, 0.045 * k, BLUE)
    p.line([(-0.11 * k, y), (-0.03 * k, y + 0.10 * k), (0.07 * k, y + 0.10 * k), (0.11 * k, y)], 0.016 * k, col)
    p.line([(-0.03 * k, y + 0.10 * k), (0.01 * k, y), (0.07 * k, y + 0.10 * k)], 0.016 * k, col)
    p.line([(-0.05 * k, y + 0.13 * k), (-0.01 * k, y + 0.13 * k)], 0.018 * k, col)


def _plate_text(col=WHITE, edge=BLACK):
    """An empty plate with a rim: the game letters it (and stretches it to the lines it has to hold)."""
    p = Plate(0.6, 0.3)
    p.box(-0.3, -0.15, 0.3, 0.15, edge)
    p.box(-0.285, -0.128, 0.285, 0.128, col)
    return p


def _pointer(right):
    """A yellow direction sign with a point at one end: lettered by the game."""
    p = Plate(1.3, 0.3)
    s = 1.0 if right else -1.0
    out = [(-0.65 * s, -0.15), (0.50 * s, -0.15), (0.65 * s, 0.0), (0.50 * s, 0.15), (-0.65 * s, 0.15)]
    p.poly(out, BLACK)
    p.poly([(x * 0.975 - 0.004 * s, y * 0.86) for x, y in out], YELLOW)
    return p


def _table(way):
    """A yellow direction sign with an arrow at its left end (V left, H right, R straight on)."""
    p = Plate(1.3, 0.3)
    p.box(-0.65, -0.15, 0.65, 0.15, BLACK)
    p.box(-0.635, -0.13, 0.635, 0.13, YELLOW)
    if way == "V":
        p.arrow(-0.42, 0.0, -0.60, 0.0, 0.035, BLACK)
    elif way == "H":
        p.arrow(-0.60, 0.0, -0.42, 0.0, 0.035, BLACK)
    else:
        p.arrow(-0.51, -0.10, -0.51, 0.11, 0.035, BLACK)
    return p


def _board(round_):
    """The big yellow board before a junction, with the junction drawn on it."""
    p = Plate(2.0, 2.4)
    p.box(-1.0, -1.2, 1.0, 1.2, BLACK)
    p.box(-0.96, -1.16, 0.96, 1.16, YELLOW)
    if round_:
        p.disc(0, 0.1, 0.36, BLACK)
        p.disc(0, 0.1, 0.22, YELLOW)
        p.line([(0, -0.95), (0, -0.26)], 0.12, BLACK)
        p.arrow(0.0, 0.46, 0.0, 0.95, 0.10, BLACK)
        p.arrow(0.36, 0.1, 0.80, 0.1, 0.10, BLACK)
        p.arrow(-0.36, 0.1, -0.80, 0.1, 0.10, BLACK)
    else:
        p.arrow(0.0, -0.95, 0.0, 0.95, 0.12, BLACK)
        p.arrow(0.0, 0.0, 0.75, 0.0, 0.10, BLACK)
        p.arrow(0.0, 0.0, -0.75, 0.0, 0.10, BLACK)
    return p


def _marker(left):
    """The striped plate on the nose of a traffic island: the stripes fall toward the side to pass on."""
    p = Plate(0.25, 0.75)
    p.box(-0.125, -0.375, 0.125, 0.375, YELLOW)
    s = -1.0 if left else 1.0
    for k in range(-3, 6):
        y = k * 0.16
        p.poly([(-0.125 * s, y), (0.125 * s, y - 0.2), (0.125 * s, y - 0.28), (-0.125 * s, y - 0.08)], BLACK)
    return p


def _faces():
    f = {}
    f["back"] = Plate(1, 1); f["back"].box(-0.5, -0.5, 0.5, 0.5, (118, 120, 124))
    f["202"] = _triangle(up=False)
    p = Plate(0.6, 0.6); p.ngon(8, 0.325, WHITE, math.pi / 8); p.ngon(8, 0.30, RED, math.pi / 8); p.text(0, 0, 0.17, "STOP", WHITE); f["204"] = p
    p = Plate(0.6, 0.6); p.ngon(4, 0.30, WHITE); p.ngon(4, 0.275, BLACK); p.ngon(4, 0.26, WHITE); p.ngon(4, 0.175, YELLOW); f["206"] = p
    f["1"] = _triangle(); f["1"].box(-0.025, -0.16, 0.025, 0.05, BLACK); f["1"].disc(0, -0.23, 0.03, BLACK)
    p = _triangle(); p.box(-0.22, -0.26, 0.22, -0.23, BLACK); p.poly([(-0.16, -0.23)] + [(0.16 * math.cos(a), -0.23 + 0.11 * math.sin(a)) for a in [math.pi * k / 12 for k in range(12, -1, -1)]], BLACK); f["109"] = p
    p = _triangle(); p.box(-0.24, -0.27, 0.24, -0.24, BLACK)
    for q in (-0.11, 0.11):
        p.poly([(q - 0.09, -0.24)] + [(q + 0.09 * math.cos(a), -0.24 + 0.07 * math.sin(a)) for a in [math.pi * k / 10 for k in range(10, -1, -1)]], BLACK)
    f["108"] = p
    p = _triangle(); p.walker(-0.08, -0.29, 0.30, BLACK); p.walker(0.10, -0.29, 0.22, BLACK); f["142"] = p
    p = _triangle(); p.box(-0.055, -0.29, 0.055, 0.07, BLACK)
    for y, c in ((0.01, RED), (-0.11, YELLOW), (-0.23, GREEN)):
        p.disc(0, y, 0.04, c)
    f["132"] = p
    p = _triangle(); p.arrow(0, -0.29, 0, 0.08, 0.06, BLACK); p.box(-0.15, -0.14, 0.15, -0.115, BLACK); f["210"] = p
    p = Plate(0.6, 0.6); p.disc(0, 0, 0.30, WHITE); p.disc(0, 0, 0.285, RED); p.box(-0.21, -0.045, 0.21, 0.045, YELLOW); f["302"] = p
    p = _ring(); _car(p, 0.045, 0.95); p.disc(-0.08, -0.10, 0.035, BLACK); p.disc(0.08, -0.10, 0.035, BLACK); p.line([(-0.08, -0.10), (0.0, -0.06), (0.08, -0.10)], 0.02, BLACK); f["306"] = p
    p = _ring(); p.walker(0.0, -0.17, 0.34, BLACK); f["306.8"] = p
    for n in (20, 30, 40, 50, 60, 70, 80, 90):
        f["362.%d" % n] = _speed(n)
        f["364.%d" % n] = _speed(n, True)
    for n in (30, 40):
        f["366.%d" % n] = _zone(n)
        f["368.%d" % n] = _zone(n, True)
    f["370"], f["372"] = _no_park(True), _no_park(False)
    f["376"], f["378"] = _no_park(False, True), _no_park(False, True, True)
    p = _blue_disc(); p.arrow(-0.13, 0.13, 0.15, -0.15, 0.07, WHITE); f["404.1"] = p
    p = _blue_disc(); p.arrow(0.13, 0.13, -0.15, -0.15, 0.07, WHITE); f["404.2"] = p
    p = _blue_disc()
    for k in range(3):
        a0 = math.radians(90 + 120 * k)
        arc = [(0.17 * math.cos(a0 + math.radians(t)), 0.17 * math.sin(a0 + math.radians(t))) for t in range(10, 85, 6)]
        p.line(arc, 0.055, WHITE)
        a1 = a0 + math.radians(104)
        tx, ty = -math.sin(a1), math.cos(a1)
        cx, cy = 0.17 * math.cos(a1), 0.17 * math.sin(a1)
        p.poly([(cx + tx * 0.07, cy + ty * 0.07), (cx - tx * 0.03 + ty * 0.075, cy - ty * 0.03 - tx * 0.075), (cx - tx * 0.03 - ty * 0.075, cy - ty * 0.03 + tx * 0.075)], WHITE)
    f["406"] = p
    p = _square(BLUE); p.box(-0.21, -0.21, 0.21, 0.21, WHITE); _bus(p, 0.0, 1.15); f["512"] = p
    p = _square(BLUE); p.poly([(-0.25, -0.22), (0.25, -0.22), (0.0, 0.25)], WHITE); p.walker(0.0, -0.17, 0.27, BLACK)
    p.box(-0.17, -0.205, 0.17, -0.175, BLACK); f["516"] = p
    p = _blue_disc(); p.walker(0.0, 0.02, 0.22, WHITE); p.box(-0.2, -0.012, 0.2, 0.0, WHITE); _bike(p, -0.14, 0.8); f["522"] = p
    p = _blue_disc(); p.walker(0.0, -0.17, 0.34, WHITE); f["518"] = p
    p = _blue_disc(); _bike(p, -0.03, 1.2); f["520"] = p
    p = _square(BLUE); p.box(-0.04, -0.22, 0.04, 0.12, WHITE); p.box(-0.17, 0.10, 0.17, 0.21, RED); f["527"] = p
    p = _square(BLUE); p.text(0, 0.0, 0.40, "P", WHITE); f["552"] = p
    f["713.H"], f["713.V"] = _pointer(True), _pointer(False)
    for w in "VHR":
        f["711." + w] = _table(w)
    f["701"], f["703"] = _board(False), _board(True)
    f["white"] = _plate_text()
    f["yellow"] = _plate_text(YELLOW)
    f["green"] = _plate_text(GREEN, WHITE)
    p = Plate(0.3, 0.6); p.box(-0.15, -0.3, 0.15, 0.3, BLACK); p.box(-0.135, -0.285, 0.135, 0.285, WHITE)
    p.arrow(0, -0.02, 0, 0.24, 0.035, BLACK); p.arrow(0, 0.02, 0, -0.24, 0.035, BLACK); f["828.1"] = p
    p = Plate(0.3, 0.6); p.box(-0.15, -0.3, 0.15, 0.3, BLACK); p.box(-0.135, -0.285, 0.135, 0.285, WHITE); p.arrow(0, 0.22, 0, -0.24, 0.035, BLACK); f["828.2"] = p
    p = Plate(0.3, 0.6); p.box(-0.15, -0.3, 0.15, 0.3, BLACK); p.box(-0.135, -0.285, 0.135, 0.285, WHITE); p.arrow(0, -0.22, 0, 0.24, 0.035, BLACK); f["828.3"] = p
    f["906V"], f["906H"] = _marker(True), _marker(False)
    for right in (True, False):
        p = Plate(0.5, 0.5); p.box(-0.25, -0.25, 0.25, 0.25, YELLOW)
        s = 1.0 if right else -1.0
        for o in (-0.14, 0.06):
            p.poly([(o * s, 0.25), ((o + 0.1) * s, 0.25), ((o + 0.26) * s, 0.0), ((o + 0.1) * s, -0.25), (o * s, -0.25), ((o + 0.16) * s, 0.0)], BLACK)
        f["904H" if right else "904V"] = p
    return f


_F = None
ORDER = []


def _all():
    global _F, ORDER
    if _F is None:
        _F = _faces()
        ORDER = list(_F.keys())
    return _F


# what is lettered on a plate that the database gives no text for
SAID = {"808.301": "Gjelder gjennomkjøring", "808.519": "Kjøring til eiendommene tillatt", "808.123": "Opphøyde gangfelt", "808.121": "Opphøyd gangfelt",
        "808.105": "Fartsdempere", "808.161": "Skole", "808.313": "Gjelder ikke buss", "808.303": "Gjelder ikke varetransport"}


def clean(text):
    """The text of a sign as it is read: the database's marks for symbols and line breaks taken out."""
    t = re.sub(r"@[^@]*@", " ", text or "")
    t = re.sub(r"[¤$]([^¤$]*)[¤$]", r"\1 ", t)
    t = re.sub(r"\s+", " ", t).strip()
    return "" if set(t) <= set("?") else t


def wrap(text, wide):
    out, line = [], ""
    for word in text.split(" "):
        if line and len(line) + 1 + len(word) > wide:
            out.append(line)
            line = word
        else:
            line = (line + " " + word).strip()
    if line:
        out.append(line)
    return out[:4]


def face_of(number, text=""):
    """For a sign number of the database ("362.40", "713.H", "808.301" …) and its text: (square in the picture,
    width, height of the plate in metres, lettering or "", colour of the lettering 0 black 1 white, the size of the
    lettering (metres per point of a 64-point letter), how far right of the middle it is set), or None for a sign that is not drawn."""
    f = _all()
    number = (number or "").strip()
    if not number:
        return None
    text = clean(text)
    main = number.split(".")[0]

    def at(key, said="", ink=0, w=None, h=None, px=0.0, ox=0.0):
        p = f[key]
        return (ORDER.index(key), w or p.w, h or p.h, said, ink, px, ox)

    if number in f and main not in ("713", "711", "701", "703"):
        return at(number)
    if main in ("362", "364"):
        return None
    if main in ("366", "368"):
        n = "40" if "40" in text else "30"
        return at(main + "." + n)
    if main in ("376", "378", "370", "372", "404", "406", "512", "516", "518", "520", "522", "552", "527", "302", "204", "202", "206", "210"):
        key = main if main in f else None
        if main == "404":
            key = "404.2" if number.endswith(".2") else "404.1"
        return at(key) if key else None
    if main == "306":
        return at("306.8" if number in ("306.8", "306.7") else "306")
    if number[0] == "1" and len(main) == 3:
        return at(main if main in f else "1")
    if main == "713" and text:
        lines = wrap(text, 16)[:2]
        right = number.endswith("H")
        return at("713.H" if right else "713.V", "\n".join(lines), 0, max(1.0, 0.075 * max(len(q) for q in lines) + 0.5), 0.14 + 0.16 * len(lines), 0.0018, -0.06 if right else 0.06)
    if main == "711" and text:
        way = "V" if ".V" in number else ("H" if ".H" in number else "R")
        lines = wrap(text, 16)[:2]
        wide = max(1.0, 0.075 * max(len(q) for q in lines) + 0.6)
        return at("711." + way, "\n".join(lines), 0, wide, 0.14 + 0.16 * len(lines), 0.0018, wide * 0.09)
    if main in ("701", "703"):
        return at(main)
    if main == "723" and text:
        e = number in ("723.11", "723.12")
        return at("green" if e else "white", text[:6], 1 if e else 0, 0.16 + 0.11 * len(text[:6]), 0.26, 0.0026)
    if main == "727" and text:
        lines = wrap(text, 16)[:2]
        return at("yellow", "\n".join(lines), 0, max(0.8, 0.075 * max(len(q) for q in lines) + 0.25), 0.14 + 0.16 * len(lines), 0.0018)
    if main in ("802", "804", "806", "808", "834", "807", "810", "812", "814", "816", "822", "824", "829"):
        said = text or SAID.get(number, "")
        if not said:
            return None
        lines = wrap(said, 13)
        return at("white", "\n".join(lines), 0, 0.6, 0.08 + 0.105 * len(lines), 0.0012)
    return None


def write(path):
    f = _all()
    rows = (len(ORDER) + COLS - 1) // COLS
    rows = 1 << (rows - 1).bit_length()                    # a power of two, so the picture halves cleanly
    im = Image.new("RGBA", (CELL * COLS, CELL * rows), (0, 0, 0, 0))
    for k, key in enumerate(ORDER):
        im.paste(f[key].done(), ((k % COLS) * CELL, (k // COLS) * CELL))
    # (under each clear point the colour of the nearest painted one, so the edge of a plate does not go dark far away)
    import numpy as np
    from scipy import ndimage
    a = np.asarray(im).copy()
    clear = a[:, :, 3] < 8
    idx = ndimage.distance_transform_edt(clear, return_distances=False, return_indices=True)
    a[clear, :3] = a[idx[0][clear], idx[1][clear], :3]
    Image.fromarray(a).save(path)
    return COLS, rows


if __name__ == "__main__":
    cols, rows = write(os.path.join(ROOT, "world", "textures", "signs.png"))
    print("faces:", len(ORDER), "in", cols, "x", rows, "squares")
    print(" ".join(ORDER))
