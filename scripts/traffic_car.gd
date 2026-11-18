extends "res://scripts/car.gd"
## The cars of the traffic: twenty models of the kinds one meets in a Norwegian town, each built the way the
## Volvo is built (scripts/car.gd): a skin drawn over outlines taken across the car, wheels with tyres, rims and
## spokes, lamps, grille, mirrors, wipers, plates, and the gaps round the doors drawn into the paint. A model is
## a row of numbers in MODELS: its real length, width, height and wheelbase, where its bonnet, windscreen, roof
## and tail lie, and what kind of lamps it has. `use()` turns such a row into the outline the Volvo's script
## builds from. scripts/traffic.gd builds each model once and draws it as many times as it is on the road.
##
## The numbers along the car are measured from the nose, in metres:
##   cowl    where the windscreen starts            roof    where the roof starts, and where it ends
##   deck    where the rear window ends (a saloon: at the boot lid; a hatchback or an estate: near the tail)
## and heights from the ground: nose_h the front of the bonnet, cowl_h the foot of the windscreen (and the sill
## of the side windows there), deck_h the foot of the rear window. `round` says how rounded the body is, from
## 0 (a box) to 1; `nose_r` how long the curve of the nose is.

const MODELS := [
	{"name": "VW Golf", "L": 4.26, "W": 1.79, "H": 1.45, "wb": 2.64, "fo": 0.86, "wr": 0.316, "rim": 0.205,
		"nose_h": 0.78, "nose_r": 0.22, "cowl": 1.22, "cowl_h": 0.98, "roof": [1.95, 3.55], "deck": 4.10, "deck_h": 1.03,
		"round": 0.45, "lamps": "rect", "tail": "wide", "grille": 0.30, "doors": 4, "sill": 0.20,
		"paints": [Color(0.86, 0.87, 0.88), Color(0.08, 0.08, 0.09), Color(0.33, 0.35, 0.37), Color(0.10, 0.22, 0.45), Color(0.62, 0.06, 0.06)]},
	{"name": "Toyota Corolla", "L": 4.37, "W": 1.79, "H": 1.44, "wb": 2.64, "fo": 0.93, "wr": 0.316, "rim": 0.205,
		"nose_h": 0.72, "nose_r": 0.34, "cowl": 1.28, "cowl_h": 0.97, "roof": [2.05, 3.50], "deck": 4.18, "deck_h": 1.05,
		"round": 0.75, "lamps": "slim", "tail": "wide", "grille": 0.42, "doors": 4, "sill": 0.19,
		"paints": [Color(0.90, 0.90, 0.89), Color(0.42, 0.43, 0.45), Color(0.09, 0.09, 0.10), Color(0.55, 0.07, 0.08), Color(0.16, 0.25, 0.42)]},
	{"name": "VW Passat", "L": 4.77, "W": 1.83, "H": 1.50, "wb": 2.79, "fo": 0.93, "wr": 0.326, "rim": 0.216,
		"nose_h": 0.77, "nose_r": 0.20, "cowl": 1.36, "cowl_h": 0.98, "roof": [2.08, 4.25], "deck": 4.62, "deck_h": 1.02,
		"round": 0.40, "lamps": "slim", "tail": "wide", "grille": 0.52, "doors": 4, "sill": 0.20, "rails": true, "estate": true, "trim": 1.0,
		"paints": [Color(0.10, 0.10, 0.11), Color(0.36, 0.38, 0.40), Color(0.82, 0.83, 0.84), Color(0.12, 0.17, 0.30), Color(0.90, 0.90, 0.89)]},
	{"name": "Tesla Model 3", "L": 4.69, "W": 1.85, "H": 1.44, "wb": 2.88, "fo": 0.84, "wr": 0.335, "rim": 0.230,
		"nose_h": 0.70, "nose_r": 0.38, "cowl": 1.24, "cowl_h": 0.96, "roof": [2.10, 3.30], "deck": 4.32, "deck_h": 1.06,
		"round": 0.85, "lamps": "slim", "tail": "wide", "grille": 0.0, "doors": 4, "sill": 0.18, "ev": true, "alloy": Color(0.30, 0.31, 0.33),
		"paints": [Color(0.92, 0.92, 0.92), Color(0.07, 0.07, 0.08), Color(0.10, 0.20, 0.50), Color(0.60, 0.05, 0.06), Color(0.30, 0.31, 0.33)]},
	{"name": "Tesla Model Y", "L": 4.75, "W": 1.92, "H": 1.62, "wb": 2.89, "fo": 0.88, "wr": 0.350, "rim": 0.240,
		"nose_h": 0.82, "nose_r": 0.36, "cowl": 1.30, "cowl_h": 1.10, "roof": [2.15, 3.45], "deck": 4.52, "deck_h": 1.22,
		"round": 0.85, "lamps": "slim", "tail": "wide", "grille": 0.0, "doors": 4, "sill": 0.25, "ev": true, "alloy": Color(0.26, 0.27, 0.29),
		"paints": [Color(0.92, 0.92, 0.92), Color(0.07, 0.07, 0.08), Color(0.30, 0.31, 0.33), Color(0.10, 0.20, 0.50), Color(0.92, 0.92, 0.92)]},
	{"name": "Volvo V70", "L": 4.82, "W": 1.86, "H": 1.55, "wb": 2.82, "fo": 0.95, "wr": 0.326, "rim": 0.216,
		"nose_h": 0.80, "nose_r": 0.18, "cowl": 1.40, "cowl_h": 1.00, "roof": [2.10, 4.50], "deck": 4.74, "deck_h": 1.04,
		"round": 0.30, "lamps": "rect", "tail": "tall", "grille": 0.34, "doors": 4, "sill": 0.21, "rails": true, "estate": true, "trim": 1.0,
		"paints": [Color(0.12, 0.16, 0.26), Color(0.78, 0.79, 0.80), Color(0.09, 0.09, 0.10), Color(0.34, 0.20, 0.14), Color(0.40, 0.42, 0.44)]},
	{"name": "Volvo XC60", "L": 4.69, "W": 1.90, "H": 1.66, "wb": 2.87, "fo": 0.90, "wr": 0.365, "rim": 0.240,
		"nose_h": 0.93, "nose_r": 0.20, "cowl": 1.34, "cowl_h": 1.16, "roof": [2.06, 4.05], "deck": 4.55, "deck_h": 1.24,
		"round": 0.45, "lamps": "slim", "tail": "tall", "grille": 0.36, "doors": 4, "sill": 0.30, "rails": true, "estate": true,
		"paints": [Color(0.09, 0.09, 0.10), Color(0.84, 0.85, 0.86), Color(0.20, 0.27, 0.36), Color(0.38, 0.39, 0.41), Color(0.50, 0.44, 0.36)]},
	{"name": "Toyota RAV4", "L": 4.60, "W": 1.86, "H": 1.69, "wb": 2.69, "fo": 0.93, "wr": 0.360, "rim": 0.230,
		"nose_h": 0.98, "nose_r": 0.16, "cowl": 1.32, "cowl_h": 1.18, "roof": [2.02, 4.00], "deck": 4.44, "deck_h": 1.26,
		"round": 0.25, "lamps": "slim", "tail": "wide", "grille": 0.46, "doors": 4, "sill": 0.31, "rails": true, "estate": true, "arch": "black",
		"paints": [Color(0.90, 0.90, 0.89), Color(0.42, 0.44, 0.45), Color(0.09, 0.09, 0.10), Color(0.16, 0.24, 0.36), Color(0.50, 0.08, 0.08)]},
	{"name": "Nissan Leaf", "L": 4.49, "W": 1.79, "H": 1.54, "wb": 2.70, "fo": 0.97, "wr": 0.320, "rim": 0.210,
		"nose_h": 0.80, "nose_r": 0.34, "cowl": 1.22, "cowl_h": 1.04, "roof": [2.02, 3.70], "deck": 4.32, "deck_h": 1.14,
		"round": 0.70, "lamps": "slim", "tail": "tall", "grille": 0.28, "doors": 4, "sill": 0.20, "ev": true,
		"paints": [Color(0.90, 0.90, 0.90), Color(0.10, 0.10, 0.11), Color(0.20, 0.36, 0.60), Color(0.44, 0.45, 0.47), Color(0.55, 0.08, 0.08)]},
	{"name": "Skoda Octavia", "L": 4.69, "W": 1.83, "H": 1.47, "wb": 2.69, "fo": 0.92, "wr": 0.318, "rim": 0.205,
		"nose_h": 0.76, "nose_r": 0.22, "cowl": 1.32, "cowl_h": 0.97, "roof": [2.05, 4.20], "deck": 4.56, "deck_h": 1.02,
		"round": 0.45, "lamps": "rect", "tail": "wide", "grille": 0.40, "doors": 4, "sill": 0.19, "rails": true, "estate": true, "trim": 1.0,
		"paints": [Color(0.84, 0.85, 0.86), Color(0.18, 0.28, 0.48), Color(0.09, 0.09, 0.10), Color(0.38, 0.39, 0.41), Color(0.90, 0.90, 0.89)]},
	{"name": "Ford Focus", "L": 4.38, "W": 1.83, "H": 1.47, "wb": 2.70, "fo": 0.90, "wr": 0.316, "rim": 0.205,
		"nose_h": 0.74, "nose_r": 0.32, "cowl": 1.26, "cowl_h": 0.98, "roof": [2.02, 3.55], "deck": 4.20, "deck_h": 1.06,
		"round": 0.70, "lamps": "slim", "tail": "tall", "grille": 0.44, "doors": 4, "sill": 0.19,
		"paints": [Color(0.14, 0.24, 0.52), Color(0.84, 0.85, 0.86), Color(0.09, 0.09, 0.10), Color(0.58, 0.07, 0.07), Color(0.40, 0.42, 0.44)]},
	{"name": "BMW 3-serie", "L": 4.71, "W": 1.83, "H": 1.44, "wb": 2.85, "fo": 0.80, "wr": 0.330, "rim": 0.225,
		"nose_h": 0.74, "nose_r": 0.24, "cowl": 1.44, "cowl_h": 0.96, "roof": [2.20, 3.50], "deck": 4.14, "deck_h": 1.03,
		"round": 0.55, "lamps": "rect", "tail": "wide", "grille": 0.24, "doors": 4, "sill": 0.18, "saloon": true, "trim": 1.0, "chrome_grille": true,
		"paints": [Color(0.09, 0.09, 0.10), Color(0.86, 0.87, 0.88), Color(0.36, 0.38, 0.40), Color(0.10, 0.16, 0.34), Color(0.90, 0.90, 0.90)]},
	{"name": "Audi A4 Avant", "L": 4.76, "W": 1.85, "H": 1.44, "wb": 2.82, "fo": 0.90, "wr": 0.330, "rim": 0.225,
		"nose_h": 0.74, "nose_r": 0.24, "cowl": 1.38, "cowl_h": 0.96, "roof": [2.12, 4.10], "deck": 4.60, "deck_h": 1.02,
		"round": 0.50, "lamps": "slim", "tail": "wide", "grille": 0.38, "doors": 4, "sill": 0.18, "rails": true, "estate": true, "trim": 1.0, "chrome_grille": true, "tall_grille": true,
		"paints": [Color(0.36, 0.38, 0.40), Color(0.09, 0.09, 0.10), Color(0.90, 0.90, 0.90), Color(0.12, 0.20, 0.36), Color(0.80, 0.81, 0.82)]},
	{"name": "Mercedes E-klasse", "L": 4.94, "W": 1.85, "H": 1.46, "wb": 2.94, "fo": 0.86, "wr": 0.335, "rim": 0.225,
		"nose_h": 0.76, "nose_r": 0.28, "cowl": 1.52, "cowl_h": 0.98, "roof": [2.28, 3.70], "deck": 4.36, "deck_h": 1.04,
		"round": 0.60, "lamps": "rect", "tail": "wide", "grille": 0.32, "doors": 4, "sill": 0.18, "saloon": true, "trim": 1.0, "chrome_grille": true, "tall_grille": true,
		"paints": [Color(0.80, 0.81, 0.82), Color(0.09, 0.09, 0.10), Color(0.30, 0.32, 0.34), Color(0.14, 0.18, 0.28), Color(0.90, 0.90, 0.89)]},
	{"name": "Toyota Yaris", "L": 3.94, "W": 1.75, "H": 1.50, "wb": 2.56, "fo": 0.80, "wr": 0.300, "rim": 0.190,
		"nose_h": 0.78, "nose_r": 0.32, "cowl": 1.06, "cowl_h": 1.00, "roof": [1.80, 3.20], "deck": 3.80, "deck_h": 1.10,
		"round": 0.80, "lamps": "slim", "tail": "wide", "grille": 0.40, "doors": 4, "sill": 0.19,
		"paints": [Color(0.60, 0.08, 0.07), Color(0.90, 0.90, 0.89), Color(0.42, 0.44, 0.45), Color(0.10, 0.10, 0.11), Color(0.20, 0.45, 0.60)]},
	{"name": "Fiat 500", "L": 3.57, "W": 1.63, "H": 1.49, "wb": 2.30, "fo": 0.74, "wr": 0.290, "rim": 0.180,
		"nose_h": 0.80, "nose_r": 0.40, "cowl": 0.98, "cowl_h": 0.98, "roof": [1.62, 2.75], "deck": 3.42, "deck_h": 1.08,
		"round": 1.0, "lamps": "round", "tail": "tall", "grille": 0.0, "doors": 2, "sill": 0.19, "trim": 1.0,
		"paints": [Color(0.92, 0.90, 0.82), Color(0.62, 0.08, 0.07), Color(0.52, 0.72, 0.74), Color(0.10, 0.10, 0.11), Color(0.90, 0.78, 0.25)]},
	{"name": "Mazda CX-5", "L": 4.55, "W": 1.84, "H": 1.68, "wb": 2.70, "fo": 0.93, "wr": 0.355, "rim": 0.230,
		"nose_h": 0.94, "nose_r": 0.26, "cowl": 1.42, "cowl_h": 1.15, "roof": [2.12, 3.95], "deck": 4.40, "deck_h": 1.24,
		"round": 0.60, "lamps": "slim", "tail": "wide", "grille": 0.44, "doors": 4, "sill": 0.30, "rails": true, "estate": true, "arch": "black", "chrome_grille": true,
		"paints": [Color(0.50, 0.05, 0.07), Color(0.34, 0.36, 0.38), Color(0.90, 0.90, 0.90), Color(0.09, 0.09, 0.10), Color(0.12, 0.18, 0.32)]},
	{"name": "Hyundai Ioniq 5", "L": 4.64, "W": 1.89, "H": 1.61, "wb": 3.00, "fo": 0.85, "wr": 0.360, "rim": 0.245,
		"nose_h": 0.86, "nose_r": 0.16, "cowl": 1.20, "cowl_h": 1.08, "roof": [2.00, 3.85], "deck": 4.46, "deck_h": 1.16,
		"round": 0.15, "lamps": "slim", "tail": "bar", "grille": 0.0, "doors": 4, "sill": 0.24, "ev": true, "arch": "black",
		"paints": [Color(0.62, 0.66, 0.64), Color(0.90, 0.90, 0.89), Color(0.09, 0.09, 0.10), Color(0.34, 0.40, 0.36), Color(0.44, 0.45, 0.47)]},
	{"name": "VW Transporter", "L": 4.90, "W": 1.90, "H": 1.97, "wb": 3.00, "fo": 0.90, "wr": 0.345, "rim": 0.215,
		"nose_h": 1.02, "nose_r": 0.20, "cowl": 0.95, "cowl_h": 1.20, "roof": [1.55, 4.70], "deck": 4.84, "deck_h": 1.24,
		"round": 0.20, "lamps": "rect", "tail": "tall", "grille": 0.50, "doors": 2, "sill": 0.27, "van": true, "steel": true,
		"paints": [Color(0.92, 0.92, 0.91), Color(0.92, 0.92, 0.91), Color(0.42, 0.44, 0.46), Color(0.10, 0.20, 0.42), Color(0.60, 0.08, 0.07)]},
	{"name": "Peugeot 208", "L": 4.06, "W": 1.75, "H": 1.43, "wb": 2.54, "fo": 0.84, "wr": 0.305, "rim": 0.200,
		"nose_h": 0.76, "nose_r": 0.30, "cowl": 1.18, "cowl_h": 0.97, "roof": [1.90, 3.30], "deck": 3.92, "deck_h": 1.06,
		"round": 0.65, "lamps": "slim", "tail": "bar", "grille": 0.40, "doors": 4, "sill": 0.19,
		"paints": [Color(0.88, 0.76, 0.16), Color(0.90, 0.90, 0.90), Color(0.10, 0.10, 0.11), Color(0.14, 0.26, 0.50), Color(0.40, 0.42, 0.44)]},
]

var spec := {}
var _zc := 0.0            # where along the car (nose at -HALF_LEN) the windscreen starts, the roof starts and ends, the rear window ends
var _zrf := 0.0
var _zrr := 0.0
var _zd := 0.0
var _zb := 0.0            # the pillar between the doors
var _door_end := 0.0


## Take a row of MODELS and turn it into the numbers the body is built from. Call it before the node enters the tree.
func use(s: Dictionary) -> void:
	spec = s
	LABEL = s["name"]
	var hl: float = s["L"] * 0.5
	var r: float = s["round"]
	HALF_LEN = hl
	WHEEL_R = s["wr"]
	RIM_R = s["rim"]
	ARCH_R = WHEEL_R + 0.065
	TRACK = s["W"] * 0.5 - 0.135
	AXLE_F = -hl + s["fo"]
	AXLE_R = AXLE_F + s["wb"]
	_zc = -hl + s["cowl"]
	_zrf = -hl + s["roof"][0]
	_zrr = -hl + s["roof"][1]
	_zd = -hl + s["deck"]
	var top: float = s["H"]
	var nose_h: float = s["nose_h"]
	var cowl_h: float = s["cowl_h"]
	var deck_h: float = s["deck_h"]
	var nr: float = s["nose_r"]
	var tr := minf(nr * 0.7, hl - _zd - 0.02)                 # the curve of the tail, shorter than the nose's
	# the car from the side: the curve of the nose, the bonnet, the windscreen, the roof, the rear window, the tail
	TOP_LINE = []
	for k in 6:
		var a := PI * 0.5 * float(k) / 5.0
		TOP_LINE.append(Vector2(-hl + nr * (1.0 - cos(a)), nose_h - 0.55 * nr * (1.0 - sin(a))))
	TOP_LINE.append(Vector2((-hl + nr + _zc) * 0.5, (nose_h + cowl_h) * 0.5 + 0.012))
	TOP_LINE.append(Vector2(_zc, cowl_h))
	TOP_LINE.append(Vector2(_zrf, top - 0.035))
	TOP_LINE.append(Vector2(_zrf + 0.25, top - 0.008))
	TOP_LINE.append(Vector2((_zrf + _zrr) * 0.5 + 0.1, top))
	TOP_LINE.append(Vector2(_zrr, top - 0.02))
	if s.get("saloon", false):
		TOP_LINE.append(Vector2(_zd, deck_h + 0.012))
		TOP_LINE.append(Vector2(hl - tr, deck_h))
	else:
		TOP_LINE.append(Vector2(minf(_zd, hl - tr - 0.01), deck_h))
	for k in range(1, 5):
		var a2 := PI * 0.5 * float(k) / 4.0
		TOP_LINE.append(Vector2(hl - tr * (1.0 - sin(a2)), deck_h - 0.5 * tr * (1.0 - cos(a2)) - 0.02 * float(k)))
	CABIN = Vector2(_zc, _zd)
	BELT = Vector2(cowl_h, deck_h)
	HALF_W = s["W"] * 0.5 - 0.055
	ROOF_W = HALF_W - (0.10 if s.get("van", false) else 0.16)
	GLASS_H = (top - (cowl_h + deck_h) * 0.5) * 0.9
	var b := cowl_h
	FLANK = [Vector2(HALF_W + 0.015, -0.045), Vector2(HALF_W + 0.030, 0.83 * b), Vector2(HALF_W + 0.040, 0.72 * b), Vector2(HALF_W + 0.045, 0.62 * b),
		Vector2(HALF_W + 0.046, 0.54 * b), Vector2(HALF_W + 0.044, 0.46 * b), Vector2(HALF_W + 0.038, 0.39 * b), Vector2(HALF_W + 0.028, 0.33 * b),
		Vector2(HALF_W + 0.012, 0.28 * b)]
	STRIP = false
	SILL = s["sill"]
	OVERHANG = SILL + 0.07
	SCREENS = [Vector2(_zc + 0.05, _zrf - 0.03), Vector2(_zrr + 0.05, _zd - 0.05)]
	var long_glass: bool = s.get("estate", false)
	SIDE_GLASS = Vector2(_zc + 0.30, _zd - (0.20 if long_glass else 0.30))
	if s.get("van", false):
		SIDE_GLASS.y = _zc + 1.55                                 # a panel van: glass in the cab only
	# the pillar between the doors, and on an estate the one behind the rear door
	_zb = lerpf(SIDE_GLASS.x, minf(SIDE_GLASS.y, _zrr + 0.2), 0.60 if s["doors"] == 2 else 0.47)
	_door_end = minf(AXLE_R - ARCH_R * 0.55, _zd - 0.25)
	PILLARS = [Vector2(_zb - 0.05, _zb + 0.05)]
	if long_glass:
		PILLARS.append(Vector2(_door_end + 0.10, _door_end + 0.22))
	PAINT_SHADER = "res://shaders/car_paint_traffic.gdshader"
	PAINT = (s["paints"] as Array)[0]
	CORNER = 0.05 + 0.06 * r
	CROWN = 0.012 + 0.022 * r
	SQUEEZE = 0.08 + 0.08 * r
	SQUEEZE_LEN = 0.25 + 0.30 * r
	SQUEEZE_TAIL = 0.06 + 0.05 * r
	END_FINE = 0.06 + 0.14 * r
	BODY_BOX = Vector3(s["W"], top - SILL, s["L"])
	FOX_TAIL = false
	AERIAL_LEN = 0.06
	_aerial_base = Vector3(0, top - 0.01, _zrr - 0.25)
	SKIN_STEP = 0.04                                              # (a third of the Volvo's outlines: seen from a few metres, the same)
	WHEEL_SEGS = 28
	SPECS = {"speed": 14.0, "fast": 20.0, "reverse": 4.0, "power": 4.0, "brake": 12.0, "reach": 3.0}


func _tune_materials() -> void:
	if spec.has("alloy"):
		_mats["alloy"] = _mat(spec["alloy"], 0.35, 0.8)
	if spec.get("steel", false):
		_mats["alloy"] = _mat(Color(0.55, 0.56, 0.58), 0.5, 0.5)       # plain steel wheels on a van
	_mats["trim"] = _mat(Color(0.06, 0.06, 0.065), 0.8)                # unpainted plastic: arches, valances
	_mats["clear"] = _lit(Color(0.86, 0.86, 0.82), 0.25)


## The paint: one material for the model, the colour given to each car (scripts/traffic.gd), and the lines of
## this model's doors, bonnet and boot lid.
func _paint() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PAINT_SHADER)
	mat.set_shader_parameter("doors", Vector3(_zc + 0.16, _zb, _door_end))
	mat.set_shader_parameter("two_door", 1.0 if spec["doors"] == 2 else 0.0)
	mat.set_shader_parameter("sill_y", SILL + 0.045)
	mat.set_shader_parameter("belt", Vector4(CABIN.x, CABIN.y, BELT.x, BELT.y))
	mat.set_shader_parameter("hood", Vector3(HALF_W - 0.075, -HALF_LEN + float(spec["nose_r"]) * 0.8, _zc - 0.02))
	if spec.get("saloon", false):
		mat.set_shader_parameter("boot", Vector3(HALF_W - 0.075, _zd + 0.02, HALF_LEN - 0.08))
	mat.set_shader_parameter("trim", spec.get("trim", 0.0))
	mat.set_shader_parameter("flap_z", AXLE_R + ARCH_R + 0.14)
	return mat


func _build_details(g: Geo) -> void:
	var fz := -HALF_LEN
	var bz := HALF_LEN
	var yn: float = TOP_LINE[0].y                               # the top of the flat of the nose, and of the tail
	var yt: float = TOP_LINE[-1].y
	var xo := HALF_W * (1.0 - SQUEEZE) - 0.03                   # how far out the flats of nose and tail reach
	var low := OVERHANG
	var lamps: String = spec["lamps"]
	var grille: float = spec["grille"]
	# the nose: lamps, grille, the intake under it, the plate
	var lh := clampf((yn - low) * 0.16, 0.035, 0.07)            # half the height of a headlamp: what the nose has room for
	if lamps == "slim":
		lh *= 0.6
	var ly := yn - lh - 0.035
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		if lamps == "round":
			g.cyl("black", Vector3((xo - 0.13) * sx, ly - 0.02, fz - 0.002), Vector3.BACK, 0.105, 0.004, 24)
			g.cyl("chrome", Vector3((xo - 0.13) * sx, ly - 0.02, fz - 0.006), Vector3.BACK, 0.098, 0.004, 24)
			g.cyl("lamp", Vector3((xo - 0.13) * sx, ly - 0.02, fz - 0.010), Vector3.BACK, 0.086, 0.004, 24)
			g.cyl("amber", Vector3((xo - 0.16) * sx, ly - 0.19, fz - 0.006), Vector3.BACK, 0.04, 0.004, 16)
		else:
			var lw := 0.17 if lamps == "rect" else 0.20
			g.box("black", Vector3((xo - lw) * sx, ly, fz - 0.002), Vector3(lw + 0.008, lh + 0.008, 0.004))
			g.box("lamp", Vector3((xo - lw - 0.03) * sx, ly, fz - 0.007), Vector3(lw - 0.035, lh, 0.004))
			g.box("amber", Vector3((xo - 0.03) * sx, ly, fz - 0.007), Vector3(0.026, lh, 0.004))
			g.box("chrome", Vector3((xo - lw - 0.03) * sx, ly - lh + 0.006, fz - 0.011), Vector3(lw - 0.04, 0.004, 0.002))      # the daytime light along its lower edge
			g.box("lamp", Vector3((xo - 0.01) * sx, ly, fz + 0.05), Vector3(0.014, lh, 0.05))                                 # round the corner
		g.box("lamp", Vector3((xo - 0.18) * sx, low + 0.085, fz - 0.004), Vector3(0.05, 0.022, 0.004))                         # fog lamps
		g.box("amber", Vector3((HALF_W + 0.046) * sx, BELT.x - 0.20, AXLE_F + ARCH_R + 0.12), Vector3(0.004, 0.012, 0.03))       # side repeaters
	if grille > 0.0:
		var gh := (lh + 0.012) * (1.7 if spec.get("tall_grille", false) else 1.0)
		var gy := ly - (gh - lh - 0.012)
		g.box("chrome" if spec.get("chrome_grille", false) else "black", Vector3(0, gy, fz - 0.002), Vector3(grille + 0.012, gh + 0.012, 0.004))
		g.box("black", Vector3(0, gy, fz - 0.006), Vector3(grille, gh, 0.004))
		for k in 4:
			g.box("iron", Vector3(0, gy - gh + gh * 2.0 * (float(k) + 0.5) / 4.0, fz - 0.011), Vector3(grille - 0.01, 0.004, 0.003))
		g.cyl("chrome", Vector3(0, gy, fz - 0.014), Vector3.BACK, minf(0.045, gh * 0.8), 0.004, 20)
	else:
		g.cyl("chrome", Vector3(0, yn - 0.03, fz - 0.004), Vector3.BACK, 0.035, 0.003, 20)        # no grille: only the badge
	g.box("trim", Vector3(0, low + 0.085, fz - 0.002), Vector3(xo - 0.27, 0.05, 0.004))                # the intake under the bumper
	for k in 3:
		g.box("iron", Vector3(0, low + 0.05 + 0.035 * float(k), fz - 0.007), Vector3(xo - 0.29, 0.003, 0.003))
	g.box("trim", Vector3(0, low - 0.01, fz + 0.06), Vector3(xo - 0.05, 0.02, 0.07))                  # the lip
	g.box("black", Vector3(0, low + 0.20, fz - 0.003), Vector3(0.27, 0.058, 0.003))
	g.box("plate", Vector3(0, low + 0.20, fz - 0.007), Vector3(0.26, 0.052, 0.002))
	# the tail: lamps, the plate and the badge, the valance and the exhaust
	var tail: String = spec["tail"]
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		if tail == "tall":
			var th := clampf((yt - low) * 0.26, 0.09, 0.16)
			g.box("black", Vector3((xo - 0.065) * sx2, yt - th - 0.02, bz + 0.002), Vector3(0.075, th + 0.008, 0.004))
			g.box("red", Vector3((xo - 0.065) * sx2, yt - th * 0.6 - 0.02, bz + 0.007), Vector3(0.062, th * 0.6, 0.004))
			g.box("amber", Vector3((xo - 0.065) * sx2, yt - th * 1.45 - 0.02, bz + 0.007), Vector3(0.062, th * 0.22, 0.004))
			g.box("clear", Vector3((xo - 0.065) * sx2, yt - th * 1.85 - 0.02, bz + 0.007), Vector3(0.062, th * 0.15, 0.004))
			g.box("red", Vector3((xo + 0.0) * sx2, yt - th - 0.02, bz - 0.04), Vector3(0.014, th, 0.04))
		else:
			g.box("black", Vector3((xo - 0.19) * sx2, yt - 0.085, bz + 0.002), Vector3(0.20, 0.062, 0.004))
			g.box("red", Vector3((xo - 0.13) * sx2, yt - 0.085, bz + 0.007), Vector3(0.13, 0.052, 0.004))
			g.box("amber", Vector3((xo - 0.30) * sx2, yt - 0.068, bz + 0.007), Vector3(0.04, 0.03, 0.004))
			g.box("clear", Vector3((xo - 0.30) * sx2, yt - 0.115, bz + 0.007), Vector3(0.04, 0.018, 0.004))
			g.box("red", Vector3((xo - 0.01) * sx2, yt - 0.085, bz - 0.04), Vector3(0.014, 0.05, 0.045))
		g.box("red", Vector3((xo - 0.20) * sx2, low + 0.10, bz + 0.004), Vector3(0.06, 0.014, 0.003))                  # reflectors
	if tail == "bar":
		g.box("red", Vector3(0, yt - 0.085, bz + 0.006), Vector3(xo - 0.33, 0.012, 0.003))                                  # a bar of light right across
	var plate_y := (yt - 0.26) if not spec.get("saloon", false) else low + 0.22
	g.box("black", Vector3(0, plate_y, bz + 0.003), Vector3(0.27, 0.058, 0.003))
	g.box("plate", Vector3(0, plate_y, bz + 0.007), Vector3(0.26, 0.052, 0.002))
	g.cyl("chrome", Vector3(0, minf(plate_y + 0.13, yt - 0.04), bz + 0.004), Vector3.BACK, 0.032, 0.003, 20)                # the badge
	g.box("trim", Vector3(0, low + 0.03, bz - 0.05), Vector3(xo - 0.10, 0.045, 0.06))                                    # the valance
	if not spec.get("ev", false):
		g.lathe("chrome", Vector3(0.48, low + 0.01, bz - 0.06), Vector3.BACK, [Vector2(0.0, -0.02), Vector2(0.03, -0.02), Vector2(0.034, 0.0), Vector2(0.034, 0.10),
			Vector2(0.028, 0.10), Vector2(0.028, 0.02), Vector2(0.0, 0.02)], 14)
		g.box("iron", Vector3(0.40, SILL + 0.0, bz - 0.50), Vector3(0.15, 0.05, 0.26))                                   # silencer
	# along the sides: mirrors, black arches on the cars that have them, roof rails; and the wipers
	var slope := Basis(Vector3.RIGHT, -atan2(float(spec["H"]) - BELT.x, _zrf - _zc))
	for sgn in [-1.0, 1.0]:
		var sx3: float = sgn
		var mz := _zc + 0.30
		g.box("black", Vector3((HALF_W + 0.03) * sx3, BELT.x + 0.045, mz), Vector3(0.03, 0.012, 0.028))
		g.box("paint", Vector3((HALF_W + 0.11) * sx3, BELT.x + 0.07, mz + 0.01), Vector3(0.075, 0.05, 0.038))
		g.box("glass", Vector3((HALF_W + 0.11) * sx3, BELT.x + 0.07, mz + 0.05), Vector3(0.066, 0.042, 0.002))
		if spec.get("arch", "") == "black":
			for zw in [AXLE_F, AXLE_R]:
				for q in 7:                                                                                                  # a band of plastic round each arch
					var a := PI * (float(q) + 0.5) / 7.0
					g.box("trim", Vector3((HALF_W + 0.047) * sx3, WHEEL_R + sin(a) * (ARCH_R + 0.03), zw - cos(a) * (ARCH_R + 0.03)),
						Vector3(0.006, 0.035, (ARCH_R + 0.03) * 0.25), Basis(Vector3.RIGHT, a - PI * 0.5))
			g.box("trim", Vector3((HALF_W + 0.036) * sx3, SILL + 0.035, (AXLE_F + AXLE_R) * 0.5), Vector3(0.006, 0.04, (AXLE_R - AXLE_F) * 0.5 - ARCH_R))
		if spec.get("rails", false):
			g.box("black", Vector3((ROOF_W - 0.07) * sx3, float(spec["H"]) + 0.03, (_zrf + _zrr) * 0.5 + 0.15), Vector3(0.014, 0.012, (_zrr - _zrf) * 0.5 - 0.15))
			for e in [-1.0, 1.0]:
				g.box("black", Vector3((ROOF_W - 0.07) * sx3, float(spec["H"]) + 0.01, (_zrf + _zrr) * 0.5 + 0.15 + float(e) * ((_zrr - _zrf) * 0.5 - 0.17)), Vector3(0.014, 0.025, 0.03))
		g.box("black", Vector3(0.28 * sx3 - 0.10, BELT.x + 0.05, _zc + 0.035) + slope.z * -0.20, Vector3(0.007, 0.007, 0.21), slope * Basis(Vector3.UP, 0.9))
	g.box("black", Vector3(0, float(spec["H"]) + 0.012, _zrr - 0.25), Vector3(0.016, 0.028, 0.07))                         # the aerial: a fin on the roof
