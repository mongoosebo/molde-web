extends RefCounted
## The boats that lie at the piers (note of 20 Nov: "make the stationary boats 10 x more detailed, and different
## sizes and variants; small boats, sailboats; no yachts"). Seven kinds, of the sort one sees in a small-boat
## harbour on the Romsdalsfjord: a wooden rowing boat, an open plastic boat with an outboard, a cabin boat, a
## snekke (the pointed-stern wooden motor boat), a small and a larger sailing boat, and a sjark (a small
## fishing boat with its wheelhouse forward). Each has a hull drawn as a smooth skin over its sections, and what
## stands in and on it: thwarts and oars, engine, wheel and windscreen, cabin and windows, rails, mast, boom and
## stays, fenders and a mooring line. Each is built twice: in full, and coarsely for when it is far off.
##
## A boat faces -Z with its stem 4 m ahead of its origin (at the pier, where tools/build_map.py puts it bow-on)
## and lies on y = 0, the sea. The hull's colour is the one the map gives each boat (the multimesh's own colour);
## everything else has its own.

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo)
const BOW := -4.0
const KINDS := ["rowing", "open", "cabin", "snekke", "sail_small", "sjark", "sail", "open"]     # the map's number for a boat (0 to 7) -> its kind
const LENGTHS := {"rowing": 4.4, "open": 4.9, "cabin": 7.0, "snekke": 6.6, "sail_small": 6.3, "sjark": 8.0, "sail": 8.4}     # stem to stern, as built below
## how far the tip of the stem lies ahead of the boat's own middle point (every hull starts at BOW; its stem rakes on from there)
const FORE := {"rowing": 4.45, "open": 4.55, "cabin": 4.9, "snekke": 4.5, "sail_small": 4.8, "sjark": 4.7, "sail": 5.0}

static var _made := {}


static func _mat(c: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _mats() -> Dictionary:
	var hull := _mat(Color.WHITE, 0.45)
	hull.vertex_color_use_as_albedo = true              # (takes the colour of each boat)
	hull.vertex_color_is_srgb = true
	return {"hull": hull, "white": _mat(Color(0.92, 0.92, 0.90), 0.5), "wood": _mat(Color(0.52, 0.34, 0.18), 0.8), "wood_dark": _mat(Color(0.30, 0.19, 0.10), 0.85),
		"glass": _mat(Color(0.07, 0.10, 0.13), 0.1, 0.5), "black": _mat(Color(0.04, 0.04, 0.045), 0.7), "grey": _mat(Color(0.42, 0.43, 0.45), 0.6),
		"alloy": _mat(Color(0.76, 0.77, 0.79), 0.3, 0.8), "red": _mat(Color(0.70, 0.08, 0.07), 0.5), "sail": _mat(Color(0.90, 0.89, 0.84), 0.9),
		"rope": _mat(Color(0.78, 0.72, 0.58), 0.95), "orange": _mat(Color(0.92, 0.42, 0.08), 0.6), "canvas": _mat(Color(0.10, 0.20, 0.40), 0.9),
		"deck": _mat(Color(0.80, 0.80, 0.77), 0.8), "green": _mat(Color(0.10, 0.36, 0.22), 0.6), "blue": _mat(Color(0.12, 0.25, 0.50), 0.6)}


## A hull from stem to stern. `s`: len, beam, free (gunwale over the water amidships), draft, stern (how wide the
## stern is, of the beam: 0 a pointed stern), sheer (how much higher the bow is), floor (the inside floor's
## height; NAN: decked over), rake (how far the stem leans forward), rail (the material of the rubbing strake).
## Returns, for each section, [z, half beam, gunwale height]: where things can be stood.
static func _hull(g, s: Dictionary, fine: bool) -> Array:
	var rows_n := 15 if fine else 6
	var pts_n := 13 if fine else 7
	var length: float = s["len"]
	var half: float = float(s["beam"]) * 0.5
	var outer := []
	var inner := []
	var deck := []
	var marks := []
	var rail_l := []
	var rail_r := []
	for i in rows_n + 1:
		var t := float(i) / float(rows_n)
		var w := half * pow(sin(minf(t / 0.42, 1.0) * PI * 0.5), 0.75)
		w *= lerpf(1.0, float(s["stern"]), smoothstep(0.55, 1.0, t))
		if float(s["stern"]) < 0.05 and t > 0.999:
			w = 0.0
		var gy: float = float(s["free"]) + float(s["sheer"]) * pow(1.0 - t, 2.2) + float(s["sheer"]) * 0.2 * pow(t, 3.0)
		var ky: float = -float(s["draft"]) * (1.0 - pow(1.0 - t, 4.0)) * (1.0 - 0.5 * pow(t, 6.0) * (1.0 if float(s["stern"]) < 0.05 else 0.3))
		var ring := PackedVector3Array()
		for k in pts_n:
			var u := 1.0 - 2.0 * float(k) / float(pts_n - 1)                 # from the starboard gunwale, under the keel, to the port one
			var a := (1.0 - absf(u)) * PI * 0.5
			var up := 1.0 - pow(sin(a), 0.85)                                 # 1 at the gunwale, 0 at the keel
			var z := BOW + length * t - float(s["rake"]) * pow(1.0 - t, 3.0) * up
			ring.append(Vector3(w * signf(u) * pow(cos(a), 0.55), ky + (gy - ky) * up, z))
		outer.append(ring)
		var zt := BOW + length * t - float(s["rake"]) * pow(1.0 - t, 3.0)
		marks.append([zt, w, gy])
		rail_r.append(Vector3(w, gy, zt))
		rail_l.append(Vector3(-w, gy, zt))
		if is_nan(float(s["floor"])):
			deck.append(PackedVector3Array([Vector3(-w, gy - 0.01, zt), Vector3(w, gy - 0.01, zt)]))
		else:
			var wi := maxf(w - 0.05, 0.0)
			var fy := minf(float(s["floor"]), gy - 0.05)
			inner.append(PackedVector3Array([Vector3(-wi, gy, zt), Vector3(-wi * 0.86, lerpf(gy, fy, 0.6), zt), Vector3(-wi * 0.66, fy, zt), Vector3(wi * 0.66, fy, zt),
				Vector3(wi * 0.86, lerpf(gy, fy, 0.6), zt), Vector3(wi, gy, zt)]))
	g.skin(outer, false, "hull")
	if float(s["stern"]) >= 0.05:
		g.cap("hull", outer[rows_n], Vector3.BACK)
	if deck.is_empty():
		g.skin(inner, false, s.get("inside", "white"))
		g.cap(s.get("inside", "white"), inner[rows_n], Vector3.FORWARD)
	else:
		g.skin(deck, false, "deck")
	g.tube(s.get("rail", "white"), rail_r, 0.028 if fine else 0.035, 5 if fine else 3)
	g.tube(s.get("rail", "white"), rail_l, 0.028 if fine else 0.035, 5 if fine else 3)
	return marks


## Where the gunwale is at a place along the boat: [half beam, height].
static func _at(marks: Array, z: float) -> Array:
	for i in marks.size() - 1:
		if z <= float(marks[i + 1][0]):
			var f := clampf((z - float(marks[i][0])) / maxf(float(marks[i + 1][0]) - float(marks[i][0]), 0.001), 0.0, 1.0)
			return [lerpf(marks[i][1], marks[i + 1][1], f), lerpf(marks[i][2], marks[i + 1][2], f)]
	return [marks[-1][1], marks[-1][2]]


## What every boat at a pier has: a line from the stem to the pier, and fenders hanging along the sides.
static func _moored(g, marks: Array, fenders: Array) -> void:
	var stem: Array = marks[0]
	g.tube("rope", [Vector3(0, float(stem[2]) - 0.03, float(stem[0]) + 0.15), Vector3(0.05, float(stem[2]) + 0.05, float(stem[0]) - 0.5), Vector3(0.12, float(stem[2]) + 0.25, float(stem[0]) - 1.1)], 0.014, 4)
	for z in fenders:
		var q := _at(marks, z)
		for sgn in [-1.0, 1.0]:
			var x: float = (float(q[0]) + 0.07) * float(sgn)
			g.tube("rope", [Vector3(x - 0.05 * float(sgn), float(q[1]), z), Vector3(x, float(q[1]) - 0.12, z)], 0.008, 3)
			g.ball("white", Vector3(x, float(q[1]) - 0.32, z), Vector3(0.075, 0.21, 0.075), 8, 5)


static func _outboard(g, z: float, y: float, big: bool) -> void:
	var k := 1.25 if big else 1.0
	g.box("black", Vector3(0, y + 0.22 * k, z + 0.10), Vector3(0.14 * k, 0.17 * k, 0.20 * k))                 # the cowling
	g.box("grey", Vector3(0, y + 0.03 * k, z + 0.10), Vector3(0.13 * k, 0.03, 0.19 * k))
	g.box("grey", Vector3(0, y - 0.28 * k, z + 0.16), Vector3(0.045, 0.30 * k, 0.07))                         # the leg
	g.box("black", Vector3(0, y + 0.02, z - 0.04), Vector3(0.09, 0.10, 0.05))                                  # the clamp on the transom
	g.cyl("alloy", Vector3(0, y - 0.55 * k, z + 0.24), Vector3.BACK, 0.09, 0.012, 8)                           # the propeller
	if not big:
		g.tube("black", [Vector3(0, y + 0.20, z - 0.05), Vector3(0.05, y + 0.26, z - 0.50)], 0.018, 5)        # the tiller


static func _cleat(g, at: Vector3) -> void:
	g.box("alloy", at + Vector3(0, 0.035, 0), Vector3(0.012, 0.035, 0.012))
	g.box("alloy", at + Vector3(0, 0.07, 0), Vector3(0.014, 0.012, 0.08))


static func _rowing(g, fine: bool) -> void:
	var m := _hull(g, {"len": 4.4, "beam": 1.55, "free": 0.42, "draft": 0.14, "stern": 0.62, "sheer": 0.22, "floor": 0.10, "rake": 0.45, "rail": "wood_dark", "inside": "wood"}, fine)
	for z in [-2.75, -1.75, -0.55]:                             # the thwarts
		var q := _at(m, z)
		g.box("wood_dark", Vector3(0, float(q[1]) - 0.13, z), Vector3(float(q[0]) - 0.04, 0.015, 0.11))
	g.box("wood_dark", Vector3(0, float(_at(m, 0.15)[1]) - 0.13, 0.15), Vector3(float(_at(m, 0.15)[0]) - 0.05, 0.015, 0.16))      # the stern seat
	if not fine:
		return
	for k in 9:                                                # the floor boards
		g.box("wood_dark", Vector3(0, 0.115, -3.0 + 0.36 * float(k)), Vector3(0.36, 0.008, 0.14))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		var q2 := _at(m, -1.45)
		g.box("alloy", Vector3((float(q2[0]) - 0.02) * sx, float(q2[1]) + 0.05, -1.45), Vector3(0.012, 0.05, 0.012))             # a rowlock
		g.box("alloy", Vector3((float(q2[0]) - 0.02) * sx, float(q2[1]) + 0.10, -1.45), Vector3(0.03, 0.012, 0.012))
		# an oar laid along the thwarts, its blade aft
		g.tube("wood", [Vector3(0.30 * sx, float(q2[1]) - 0.09, -3.1), Vector3(0.32 * sx, float(q2[1]) - 0.09, -0.9)], 0.022, 5)
		g.box("wood", Vector3(0.33 * sx, float(q2[1]) - 0.09, -0.55), Vector3(0.07, 0.008, 0.36))
	g.box("orange", Vector3(-0.25, 0.20, -0.1), Vector3(0.13, 0.08, 0.10))                                      # a bailer
	g.box("red", Vector3(0.22, 0.24, -3.05), Vector3(0.12, 0.11, 0.17))                                         # a fuel can forward
	_moored(g, m, [-1.9])


static func _open(g, fine: bool) -> void:
	var m := _hull(g, {"len": 4.9, "beam": 1.9, "free": 0.52, "draft": 0.20, "stern": 0.86, "sheer": 0.20, "floor": 0.16, "rake": 0.55, "rail": "black"}, fine)
	var q := _at(m, -1.4)
	# the steering console to starboard, with its windscreen and wheel; a bench across, a seat box aft
	g.box("white", Vector3(0.38, 0.52, -1.55), Vector3(0.30, 0.36, 0.22))
	g.box("glass", Vector3(0.38, 1.02, -1.70), Vector3(0.29, 0.16, 0.012), Basis(Vector3.RIGHT, 0.35))
	g.box("white", Vector3(0, 0.36, -0.75), Vector3(float(_at(m, -0.75)[0]) - 0.06, 0.20, 0.20))
	g.box("blue", Vector3(0, 0.575, -0.75), Vector3(float(_at(m, -0.75)[0]) - 0.10, 0.02, 0.18))
	g.box("white", Vector3(0, 0.36, -3.0), Vector3(float(_at(m, -3.0)[0]) - 0.08, 0.20, 0.30))                  # the locker in the bow
	_outboard(g, BOW + 4.9, float(_at(m, 0.8)[1]), true)
	if not fine:
		return
	g.lathe("black", Vector3(0.38, 0.88, -1.36), Vector3(0, 0.35, 0.94).normalized(), [Vector2(0.13, -0.012), Vector2(0.155, 0.0), Vector2(0.13, 0.012)], 14, true)
	g.tube("alloy", [Vector3(0.38, 0.86, -1.38), Vector3(0.38, 0.80, -1.50)], 0.014, 5)
	g.box("black", Vector3(0.50, 0.90, -1.52), Vector3(0.03, 0.05, 0.08))                                        # the throttle
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		_cleat(g, Vector3((float(q[0]) - 0.07) * sx, float(q[1]), 0.55))
		g.tube("alloy", [Vector3((float(_at(m, -3.3)[0]) - 0.03) * sx, float(_at(m, -3.3)[1]), -3.3), Vector3((float(_at(m, -2.8)[0]) - 0.02) * sx, float(_at(m, -2.8)[1]) + 0.22, -2.8),
			Vector3((float(_at(m, -2.0)[0]) - 0.02) * sx, float(_at(m, -2.0)[1]) + 0.22, -2.0), Vector3((float(_at(m, -1.8)[0]) - 0.02) * sx, float(_at(m, -1.8)[1]), -1.8)], 0.013, 4)      # a grab rail
	_cleat(g, Vector3(0, float(m[1][2]) - 0.02, float(m[1][0]) + 0.1))
	g.box("red", Vector3(-0.45, 0.30, 0.35), Vector3(0.15, 0.14, 0.20))                                          # the fuel tank
	g.tube("black", [Vector3(-0.40, 0.40, 0.55), Vector3(-0.15, 0.42, 0.80), Vector3(0, 0.60, 0.88)], 0.012, 4)
	g.box("orange", Vector3(-0.50, 0.26, -1.9), Vector3(0.20, 0.10, 0.14))                                       # life jackets stowed
	_moored(g, m, [-2.1, -0.2])


static func _cabin(g, fine: bool) -> void:
	var m := _hull(g, {"len": 7.0, "beam": 2.5, "free": 0.82, "draft": 0.34, "stern": 0.88, "sheer": 0.26, "floor": NAN, "rake": 0.9, "rail": "black"}, fine)
	# the cabin over the fore part: its sides, the raked windscreen, dark windows; the cockpit aft, sunk between coamings
	var rows := []
	for q in [[-2.3, 0.72, 0.30], [-1.85, 0.92, 0.72], [-0.2, 1.0, 0.78], [0.25, 1.0, 0.74]]:
		var w: float = 1.02 * float(q[1])
		var top: float = 0.95 + float(q[2])
		var ring := PackedVector3Array([Vector3(-w, 0.90, q[0]), Vector3(-w * 0.94, top - 0.05, q[0]), Vector3(-w * 0.82, top, q[0]), Vector3(w * 0.82, top, q[0]), Vector3(w * 0.94, top - 0.05, q[0]), Vector3(w, 0.90, q[0])])
		rows.append(ring)
	g.skin(rows, true, "white")
	g.cap("white", rows[3], Vector3.BACK)
	g.box("glass", Vector3(0, 1.36, -2.04), Vector3(0.72, 0.19, 0.012), Basis(Vector3.RIGHT, 0.82))               # the windscreen
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("glass", Vector3(1.0 * sx, 1.44, -0.85), Vector3(0.012, 0.15, 0.72), Basis(Vector3.BACK, 0.08 * sx))    # side windows
		g.box("white", Vector3(0.98 * sx, 1.02, 1.65), Vector3(0.07, 0.14, 1.38))                                  # the cockpit's coaming
	g.box("grey", Vector3(0, 0.84, 1.65), Vector3(0.90, 0.02, 1.36))                                              # the cockpit floor
	g.box("glass", Vector3(-0.35, 1.30, 0.265), Vector3(0.28, 0.36, 0.012))                                       # the cabin door
	g.box("white", Vector3(0, 0.98, 2.80), Vector3(0.90, 0.13, 0.20))                                             # the bench across the stern
	g.box("blue", Vector3(0, 1.12, 2.80), Vector3(0.86, 0.02, 0.18))
	_outboard(g, BOW + 7.0, 0.80, true)
	if not fine:
		return
	g.box("blue", Vector3(0.52, 1.02, 0.75), Vector3(0.24, 0.20, 0.24))                                           # the helmsman's seat
	g.box("blue", Vector3(0.52, 1.36, 0.97), Vector3(0.24, 0.20, 0.03))
	# the pulpit round the bow, and a hand rail along the cabin roof
	var bow := []
	for k in 9:
		var z := lerpf(-1.9, float(m[0][0]) + 0.12, sin(float(k) / 8.0 * PI))
		var qq := _at(m, z)
		var side := -1.0 if k < 4 else 1.0
		bow.append(Vector3((float(qq[0]) - 0.05) * side * (0.0 if k == 4 else 1.0), float(qq[1]) + 0.50, z))
	g.tube("alloy", bow, 0.014, 5)
	for k in [0, 2, 4, 6, 8]:
		g.tube("alloy", [bow[k], bow[k] - Vector3(0, 0.50, 0)], 0.012, 4)
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		g.tube("alloy", [Vector3(0.70 * sx2, 1.76, -1.6), Vector3(0.72 * sx2, 1.80, -0.9), Vector3(0.72 * sx2, 1.76, -0.1)], 0.012, 4)
		_cleat(g, Vector3(0.85 * sx2, 0.92, -2.9))
		_cleat(g, Vector3(1.0 * sx2, 1.16, 2.7))
		g.box("red" if sx2 < 0.0 else "green", Vector3(0.80 * sx2, 1.60, -1.75), Vector3(0.03, 0.03, 0.05))       # the side lights
	g.tube("alloy", [Vector3(0, 1.73, -0.6), Vector3(0, 2.25, -0.55)], 0.012, 4)                                   # the mast for the white light, an aerial
	g.box("white", Vector3(0, 2.27, -0.55), Vector3(0.03, 0.03, 0.03))
	g.tube("black", [Vector3(0.5, 1.73, -0.2), Vector3(0.5, 2.9, 0.0)], 0.006, 3)
	g.box("alloy", Vector3(0, 0.93, -3.25), Vector3(0.10, 0.03, 0.16))                                             # the anchor on the foredeck
	g.box("orange", Vector3(0.95, 1.50, 0.45), Vector3(0.03, 0.20, 0.20))                                          # a life ring on the cabin's side
	_moored(g, m, [-1.6, 0.6, 2.2])


static func _snekke(g, fine: bool) -> void:
	var m := _hull(g, {"len": 6.6, "beam": 2.3, "free": 0.66, "draft": 0.42, "stern": 0.0, "sheer": 0.34, "floor": 0.22, "rake": 0.5, "rail": "wood_dark", "inside": "wood"}, fine)
	# a foredeck and a low cabin on it, three round ports a side; the engine's box amidships; benches round the stern
	g.box("wood", Vector3(0, float(_at(m, -2.6)[1]) - 0.03, -2.75), Vector3(float(_at(m, -2.6)[0]) - 0.08, 0.02, 0.95))
	g.box("white", Vector3(0, 0.98, -2.05), Vector3(0.74, 0.26, 0.85))
	g.box("wood_dark", Vector3(0, 1.26, -2.05), Vector3(0.80, 0.03, 0.92))
	g.box("glass", Vector3(0, 1.02, -1.19), Vector3(0.30, 0.16, 0.012))
	g.box("wood_dark", Vector3(0, 0.50, -0.15), Vector3(0.36, 0.26, 0.48))                                        # the engine box
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		for k in 3:
			g.cyl("glass", Vector3(0.745 * sx, 1.02, -2.6 + 0.55 * float(k)), Vector3.RIGHT, 0.085, 0.006, 10)
		g.box("wood", Vector3((float(_at(m, 1.3)[0]) - 0.24) * sx, 0.50, 1.25), Vector3(0.17, 0.02, 0.75))        # a bench
	# the rudder on the stern post, and its tiller
	g.box("wood_dark", Vector3(0, 0.10, BOW + 6.6 + 0.10), Vector3(0.025, 0.55, 0.16))
	g.tube("wood_dark", [Vector3(0, 0.78, BOW + 6.6 + 0.02), Vector3(0, 0.86, BOW + 6.6 - 0.95)], 0.022, 5)
	if not fine:
		return
	g.tube("black", [Vector3(0.2, 0.76, -0.2), Vector3(0.2, 1.55, -0.2)], 0.035, 6)                                # the exhaust pipe
	g.tube("wood", [Vector3(0, 1.28, -1.6), Vector3(0, 2.6, -1.6)], 0.03, 5)                                       # a short mast with a lantern and a flag
	g.box("white", Vector3(0, 2.63, -1.6), Vector3(0.04, 0.04, 0.04))
	g.tube("wood", [Vector3(0, 0.95, BOW + 6.6 - 0.15), Vector3(0, 1.85, BOW + 6.6 + 0.25)], 0.014, 4)
	g.box("red", Vector3(0, 1.66, BOW + 6.6 + 0.42), Vector3(0.004, 0.13, 0.20))
	g.box("blue", Vector3(0, 1.66, BOW + 6.6 + 0.36), Vector3(0.006, 0.13, 0.03))
	g.box("white", Vector3(0, 1.66, BOW + 6.6 + 0.36), Vector3(0.005, 0.13, 0.05))
	for k in 12:
		g.box("wood_dark", Vector3(0, 0.235, -1.0 + 0.30 * float(k)), Vector3(0.50, 0.008, 0.12))
	_cleat(g, Vector3(0, float(_at(m, -3.4)[1]) - 0.01, -3.4))
	g.tube("rope", [Vector3(-0.3, 0.26, 1.9), Vector3(-0.1, 0.26, 2.1), Vector3(-0.3, 0.26, 2.2), Vector3(-0.45, 0.26, 2.0), Vector3(-0.3, 0.26, 1.9)], 0.02, 4)      # a coil of rope
	_moored(g, m, [-1.9, 0.9])


static func _sailing(g, fine: bool, big: bool) -> void:
	var length := 8.4 if big else 6.3
	var k := length / 8.4
	var m := _hull(g, {"len": length, "beam": 2.75 * (0.95 if big else 0.80), "free": 0.95 * k + 0.10, "draft": 0.45 * k, "stern": 0.55, "sheer": 0.22, "floor": NAN, "rake": 1.0 * k, "rail": "wood" if big else "white"}, fine)
	var deck_y := float(_at(m, BOW + length * 0.5)[1])
	var mast_z := BOW + length * 0.40
	var top := 11.0 if big else 8.2
	# the coachroof with its windows, the cockpit behind it between coamings, the hatch
	var z0 := BOW + length * 0.26
	var z1 := BOW + length * 0.62
	var hw := 0.78 * k + 0.05
	g.box("white", Vector3(0, deck_y + 0.19, (z0 + z1) * 0.5), Vector3(hw, 0.19, (z1 - z0) * 0.5))
	g.box("white", Vector3(0, deck_y + 0.10, z0 - 0.25), Vector3(hw * 0.8, 0.10, 0.25), Basis(Vector3.RIGHT, 0.25))
	g.box("wood", Vector3(0, deck_y + 0.39, z1 - 0.35), Vector3(0.32, 0.015, 0.32))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("glass", Vector3((hw + 0.005) * sx, deck_y + 0.22, (z0 + z1) * 0.5), Vector3(0.006, 0.07, (z1 - z0) * 0.36))
		g.box("white", Vector3((float(_at(m, z1 + 1.0)[0]) - 0.20) * sx, deck_y + 0.12, z1 + length * 0.14), Vector3(0.06, 0.12, length * 0.14))
	g.box("grey", Vector3(0, deck_y - 0.06, z1 + length * 0.14), Vector3(float(_at(m, z1 + 1.0)[0]) - 0.28, 0.02, length * 0.14))
	# the mast, the boom with the sail stowed along it under its cover, the rudder and the tiller
	g.tube("alloy", [Vector3(0, deck_y + 0.38, mast_z), Vector3(0, top, mast_z)], 0.055 if big else 0.045, 6)
	var boom_y := deck_y + 1.25
	var boom_end := mast_z + length * 0.40
	g.tube("alloy", [Vector3(0, boom_y, mast_z + 0.06), Vector3(0, boom_y, boom_end)], 0.04, 5)
	g.tube("canvas", [Vector3(0, boom_y + 0.11, mast_z + 0.15), Vector3(0, boom_y + 0.13, (mast_z + boom_end) * 0.5), Vector3(0, boom_y + 0.09, boom_end - 0.1)], 0.10, 6)
	g.box("white", Vector3(0, -0.10, BOW + length + 0.06), Vector3(0.025, 0.55, 0.14))
	g.tube("wood", [Vector3(0, deck_y + 0.25, BOW + length - 0.02), Vector3(0, deck_y + 0.40, BOW + length - 1.1 * k)], 0.02, 5)
	# the stays: forward to the stem, aft to the stern, and the shrouds out to the sides over the spreaders
	var stem: Array = m[0]
	g.tube("alloy", [Vector3(0, top - 0.3, mast_z), Vector3(0, float(stem[2]) + 0.02, float(stem[0]) + 0.1)], 0.008, 3)
	g.tube("alloy", [Vector3(0, top - 0.05, mast_z), Vector3(0, deck_y + 0.05, BOW + length - 0.05)], 0.008, 3)
	var sp_y := lerpf(deck_y, top, 0.55)
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		var chain := Vector3((float(_at(m, mast_z)[0]) - 0.05) * sx2, deck_y, mast_z + 0.1)
		var spread := Vector3(0.62 * k * sx2, sp_y, mast_z)
		g.tube("alloy", [Vector3(0, sp_y, mast_z), spread], 0.014, 4)
		g.tube("alloy", [chain, spread, Vector3(0, top - 0.4, mast_z)], 0.007, 3)
	if not fine:
		return
	# the furled jib on the forestay, the pulpit, stanchions and life lines, the pushpit, winches, the boom's sheet
	var foot := Vector3(0, float(stem[2]) + 0.25, float(stem[0]) + 0.22)
	var head := foot.lerp(Vector3(0, top - 0.3, mast_z), 0.86)
	g.tube("sail", [foot, foot.lerp(head, 0.5), head], 0.045, 5)
	var posts := []
	for q in [0.10, 0.30, 0.50, 0.70, 0.90]:
		posts.append(BOW + length * float(q))
	for sgn in [-1.0, 1.0]:
		var sx3: float = sgn
		var line := []
		for z in posts:
			var qq := _at(m, z)
			var foot2 := Vector3((float(qq[0]) - 0.04) * sx3, float(qq[1]), z)
			g.tube("alloy", [foot2, foot2 + Vector3(0, 0.55, 0)], 0.011, 4)
			line.append(foot2 + Vector3(0, 0.55, 0))
		g.tube("alloy", line, 0.006, 3)
		g.tube("alloy", [line[0], Vector3(0, float(stem[2]) + 0.55, float(stem[0]) + 0.05)], 0.012, 4)            # the pulpit
		g.tube("alloy", [line[4], Vector3(0.0, float(_at(m, BOW + length)[1]) + 0.55, BOW + length - 0.02)], 0.012, 4)      # the pushpit
		g.cyl("alloy", Vector3((float(_at(m, z1 + 0.6)[0]) - 0.20) * sx3, deck_y + 0.30, z1 + 0.6), Vector3.UP, 0.06, 0.06, 8)       # a winch
		_cleat(g, Vector3((float(_at(m, BOW + 0.8)[0]) - 0.08) * sx3, float(_at(m, BOW + 0.8)[1]), BOW + 0.8))
	g.tube("alloy", [Vector3(0, float(stem[2]) + 0.55, float(stem[0]) + 0.05), Vector3(0, float(stem[2]), float(stem[0]) + 0.05)], 0.012, 4)
	g.tube("rope", [Vector3(0, boom_y - 0.03, boom_end - 0.3), Vector3(0, deck_y + 0.02, BOW + length - 0.9 * k)], 0.010, 3)       # the main sheet
	g.box("alloy", Vector3(0, top + 0.03, mast_z), Vector3(0.02, 0.03, 0.02))                                     # the light and the wind vane at the masthead
	g.tube("black", [Vector3(0, top, mast_z), Vector3(0.0, top + 0.35, mast_z + 0.05)], 0.004, 3)
	g.box("alloy", Vector3(0, float(stem[2]) + 0.03, float(stem[0]) + 0.45), Vector3(0.10, 0.025, 0.14))          # the anchor at the stem
	_moored(g, m, [BOW + length * 0.35, BOW + length * 0.6, BOW + length * 0.82])


static func _sjark(g, fine: bool) -> void:
	var m := _hull(g, {"len": 8.0, "beam": 2.9, "free": 0.95, "draft": 0.55, "stern": 0.80, "sheer": 0.42, "floor": NAN, "rake": 0.7, "rail": "black"}, fine)
	# the wheelhouse forward: windows all round, a visor of roof over them; the working deck aft inside a bulwark
	g.box("white", Vector3(0, 1.85, -1.75), Vector3(0.95, 0.80, 0.95))
	g.box("grey", Vector3(0, 2.68, -1.80), Vector3(1.05, 0.04, 1.10))
	g.box("glass", Vector3(0, 2.15, -2.705), Vector3(0.80, 0.24, 0.012))
	g.box("glass", Vector3(0, 2.15, -0.795), Vector3(0.60, 0.22, 0.012))
	g.box("white", Vector3(0.45, 1.62, -0.79), Vector3(0.30, 0.56, 0.014))                                        # the door aft
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("glass", Vector3(0.955 * sx, 2.15, -1.75), Vector3(0.012, 0.22, 0.70))
		g.box("hull", Vector3((float(_at(m, 1.5)[0]) - 0.03) * sx, 1.22, 1.55), Vector3(0.03, 0.26, 2.35))          # the bulwark
	g.box("hull", Vector3(0, 1.22, BOW + 8.0 - 0.03), Vector3(float(_at(m, 3.9)[0]) - 0.03, 0.26, 0.03))
	g.tube("alloy", [Vector3(0, 2.70, -1.5), Vector3(0, 4.4, -1.4)], 0.04, 5)                                      # the mast, with its lights and radar
	g.box("white", Vector3(0, 3.3, -1.25), Vector3(0.28, 0.05, 0.10))
	if not fine:
		return
	g.box("white", Vector3(0, 4.43, -1.4), Vector3(0.04, 0.04, 0.04))
	g.tube("alloy", [Vector3(0, 4.0, -1.4), Vector3(0, 3.2, 2.9), Vector3(0, 1.5, 3.5)], 0.02, 4)                 # the boom over the deck
	g.tube("black", [Vector3(0.6, 2.70, -1.2), Vector3(0.6, 4.1, -1.2)], 0.006, 3)
	g.tube("black", [Vector3(-0.5, 2.70, -1.0), Vector3(-0.5, 3.3, -1.0)], 0.05, 6)                                # the exhaust
	g.cyl("orange", Vector3(1.0, 1.75, -1.0), Vector3.RIGHT, 0.22, 0.03, 12)                                       # a life ring
	g.cyl("grey", Vector3(-0.95, 1.55, 0.6), Vector3.BACK, 0.30, 0.12, 12)                                         # the net hauler on the rail
	g.box("grey", Vector3(-0.95, 1.20, 0.6), Vector3(0.08, 0.25, 0.08))
	for q in [[0.4, 1.3, "blue"], [0.4, 2.1, "blue"], [-0.35, 2.4, "green"], [0.2, 3.0, "white"]]:                 # fish crates and tubs
		g.box(q[2], Vector3(float(q[0]), 1.13, float(q[1])), Vector3(0.36, 0.17, 0.28))
	g.tube("orange", [Vector3(-0.5, 1.02, 3.2), Vector3(-0.2, 1.02, 3.45), Vector3(-0.6, 1.02, 3.55), Vector3(-0.8, 1.02, 3.3), Vector3(-0.5, 1.02, 3.2)], 0.035, 4)     # rope
	g.ball("red", Vector3(0.7, 1.25, 3.3), Vector3(0.22, 0.22, 0.22), 10, 6)                                       # a buoy
	g.box("alloy", Vector3(0, 1.42, -3.3), Vector3(0.14, 0.14, 0.14))                                              # the windlass on the foredeck
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		for z in [-0.4, 1.4, 3.0]:                                 # old tyres as fenders
			var qq := _at(m, z)
			g.lathe("black", Vector3((float(qq[0]) + 0.09) * sx2, float(qq[1]) - 0.40, z), Vector3.RIGHT, [Vector2(0.17, -0.07), Vector2(0.30, -0.07), Vector2(0.30, 0.07), Vector2(0.17, 0.07)], 10)
	_moored(g, m, [])


## The boat of a kind: [built in full, built coarsely].
static func meshes(kind: String) -> Array:
	if not _made.has(kind):
		var pair := []
		for fine in [true, false]:
			var g = Shapes.Geo.new()
			match kind:
				"rowing": _rowing(g, fine)
				"open": _open(g, fine)
				"cabin": _cabin(g, fine)
				"snekke": _snekke(g, fine)
				"sail_small": _sailing(g, fine, false)
				"sail": _sailing(g, fine, true)
				_: _sjark(g, fine)
			pair.append(g.commit(_mats()))
		_made[kind] = pair
	return _made[kind]
