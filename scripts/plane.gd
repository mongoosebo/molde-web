extends RefCounted
## The airliner on the apron at Årø and on its way in and out (note of 21 Nov: "make this plane 10 x polygons,
## make it have Norwegian decals"). A twin-jet of the size that flies Molde to Oslo, 39 m long and 35 m across the
## wings, in a Norwegian livery: a red nose and a red fin on a white body, a dark blue line between them, the
## flag on the fin and by the rear door. It was eleven plain shapes; it is built here of a smooth body, swept and
## tapered wings with winglets and flap fairings, engines with their intakes and pylons, a swept tail, the
## windows and doors, the undercarriage and the lights.
## Its nose points to -Z, it stands on y = 0 on its wheels, and its middle is where the old one's was.

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo)

const BODY_R := 1.88
const BODY_Y := 3.55          # the middle line of the body over the ground

static var _mesh: ArrayMesh


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## A section of a wing or a tail plane at one place along it: a closed outline, rounded in front, sharp behind.
static func _section(at: Vector3, chord: float, thick: float, across: Vector3) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for q in [[0.0, 0.0], [0.03, 0.55], [0.12, 0.92], [0.30, 1.0], [0.55, 0.80], [0.80, 0.42], [1.0, 0.04], [0.80, -0.22], [0.55, -0.42], [0.30, -0.52], [0.12, -0.48], [0.03, -0.30]]:
		ring.append(at + Vector3(0, 0, 1) * (chord * float(q[0])) + across * (thick * 0.5 * float(q[1])))
	return ring


## A wing, a tail plane or the fin: from its root to its tip, each [leading edge, chord, thickness], `up` the way its thickness lies.
static func _plane(g, mat, stations: Array, up: Vector3) -> void:
	var rows := []
	for s in stations:
		rows.append(_section(s[0], s[1], s[2], up))
	g.skin(rows, true, mat)
	var name: String = mat.call(rows.size() - 1, 0) if mat is Callable else mat
	g.cap(name, rows[-1], (stations[-1][0] as Vector3) - (stations[0][0] as Vector3))


static func _flag(g, at: Vector3, right: Vector3, tall: float, out: Vector3) -> void:
	# the Norwegian flag, 22 by 16: red, a white cross, a blue cross in it, the upright nearer the hoist
	var wide := tall * 22.0 / 16.0
	var bs := Basis(right, Vector3.UP, out)
	g.box("flag_red", at, Vector3(wide * 0.5, tall * 0.5, 0.004), bs)
	g.box("white_flat", at + right * (wide * (8.0 / 22.0 - 0.5)) + out * 0.004, Vector3(wide * 2.0 / 22.0, tall * 0.5, 0.004), bs)
	g.box("white_flat", at + out * 0.004, Vector3(wide * 0.5, tall * 2.0 / 16.0, 0.004), bs)
	g.box("flag_blue", at + right * (wide * (8.0 / 22.0 - 0.5)) + out * 0.008, Vector3(wide * 1.0 / 22.0, tall * 0.5, 0.004), bs)
	g.box("flag_blue", at + out * 0.008, Vector3(wide * 0.5, tall * 1.0 / 16.0, 0.004), bs)


## A door, drawn on the body's skin: a thin dark line round it, from angle a0 to a1 round the body, `half` wide each way.
static func _door(g, sx: float, z: float, a0: float, a1: float, half: float) -> void:
	var r := BODY_R + 0.004
	for k in 8:
		var a := lerpf(a0, a1, (float(k) + 0.5) / 8.0)
		var bs := Basis(Vector3.BACK, a if sx > 0.0 else PI - a)
		for e in [-1.0, 1.0]:
			g.box("door_line", Vector3(r * sx * cos(a), BODY_Y + r * sin(a), z + half * float(e)), Vector3(0.004, r * (a1 - a0) / 16.0 + 0.004, 0.012), bs)
	for a2 in [a0, a1]:
		var bs2 := Basis(Vector3.BACK, float(a2) if sx > 0.0 else PI - float(a2))
		g.box("door_line", Vector3(r * sx * cos(float(a2)), BODY_Y + r * sin(float(a2)), z), Vector3(0.004, 0.012, half), bs2)
	var ah := lerpf(a0, a1, 0.38)
	g.box("steel", Vector3((r + 0.004) * sx * cos(ah), BODY_Y + r * sin(ah), z + half * 0.55), Vector3(0.006, 0.025, 0.07), Basis(Vector3.BACK, ah if sx > 0.0 else PI - ah))


static func build() -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var g = Shapes.Geo.new()
	# ---- the body: a round tube, the nose drawn down to a blunt point, the tail up to a narrow cone
	var st := [[-19.6, 0.02, -0.55], [-19.3, 0.35, -0.50], [-18.7, 0.78, -0.40], [-17.8, 1.20, -0.25], [-16.6, 1.55, -0.10], [-15.2, 1.78, -0.02], [-13.6, 1.88, 0.0],
		[-10.0, 1.88, 0.0], [-5.0, 1.88, 0.0], [0.0, 1.88, 0.0], [5.0, 1.88, 0.0], [9.0, 1.88, 0.0], [11.5, 1.80, 0.10], [13.5, 1.58, 0.32], [15.5, 1.22, 0.62],
		[17.3, 0.82, 0.92], [18.6, 0.48, 1.12], [19.4, 0.24, 1.22], [19.8, 0.06, 1.26]]
	var rows := []
	for q in st:
		var ring := PackedVector3Array()
		for k in 24:
			var a := TAU * float(k) / 24.0
			ring.append(Vector3(cos(a) * float(q[1]), BODY_Y + float(q[2]) + sin(a) * float(q[1]), q[0]))
		rows.append(ring)
	# red to behind the cockpit, a dark blue band, then white; the belly a shade of grey
	g.skin(rows, true, func(i, k): return ("red" if i < 5 else ("navy" if i == 5 else ("belly" if (k >= 15 and k <= 20 and i > 6 and i < 13) else "white"))))
	# the cockpit windows: six panes round the nose, raked; the wipers' black surround
	for k in 6:
		var a2 := -1.15 + 2.3 * float(k) / 5.0
		var at := Vector3(sin(a2) * 1.42, BODY_Y + 0.72, -16.75 + 0.55 * absf(sin(a2)) * 1.6)
		var out := Vector3(sin(a2), 0.45, -cos(a2) * 0.9).normalized()
		g.box("glass", at + out * 0.06, Vector3(0.36, 0.25, 0.03), Basis(Vector3.UP.cross(out).normalized(), out.cross(Vector3.UP.cross(out).normalized()), out))
	# cabin windows, the doors with their sills and handles, the flag by the rear door
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		var side := Vector3(sx, 0, 0)
		for k in 46:
			var z := -12.6 + 0.52 * float(k)
			if (z > -1.2 and z < -0.4) or (z > 1.4 and z < 2.2):
				continue                                               # (the over-wing exits have their own)
			g.box("glass", Vector3((BODY_R + 0.005) * sx * cos(0.32), BODY_Y + BODY_R * sin(0.32), z), Vector3(0.012, 0.17, 0.12))
		# (the doors are drawn on the skin, as an outline that follows its curve: standing out of it as panels they
		# looked stuck on; "make doors on the plane a texture", 21 Nov)
		for dz in [-14.2, 11.6]:
			_door(g, sx, dz, -0.42, 0.69, 0.44)
			g.box("glass", Vector3((BODY_R + 0.006) * sx * cos(0.33), BODY_Y + BODY_R * sin(0.33), dz), Vector3(0.008, 0.13, 0.10))
		for dz2 in [-0.8, 1.8]:
			_door(g, sx, dz2, 0.02, 0.60, 0.27)
			g.box("glass", Vector3((BODY_R + 0.005) * sx * cos(0.32), BODY_Y + BODY_R * sin(0.32), dz2), Vector3(0.012, 0.17, 0.12))
		_flag(g, Vector3((BODY_R - 0.03) * sx, BODY_Y + 0.55, 9.6), Vector3(0, 0, -sx), 0.62, side)
		# ---- a wing: swept back, tapered, rising a little to the tip, with a winglet; flap fairings under it
		var wing := [[Vector3(1.6 * sx, BODY_Y - 1.15, -3.6), 7.4, 0.95], [Vector3(5.6 * sx, BODY_Y - 0.85, -0.9), 4.7, 0.62], [Vector3(11.5 * sx, BODY_Y - 0.35, 3.1), 2.9, 0.36],
			[Vector3(16.6 * sx, BODY_Y + 0.08, 6.6), 1.55, 0.20]]
		_plane(g, "wing", wing, Vector3.UP)
		_plane(g, func(i, k): return "red" if i >= 1 else "wing", [[Vector3(16.6 * sx, BODY_Y + 0.08, 6.6), 1.55, 0.18], [Vector3(17.15 * sx, BODY_Y + 0.75, 7.25), 1.15, 0.12], [Vector3(17.45 * sx, BODY_Y + 2.35, 8.05), 0.55, 0.07]], side)
		for q2 in [[4.2, 1.6], [8.3, 3.2], [12.4, 5.3]]:
			var fx: float = float(q2[0]) * sx
			g.lathe("wing", Vector3(fx, BODY_Y - 1.18 + 0.045 * float(q2[0]), float(q2[1]) - 0.2), Vector3.BACK, [Vector2(0.0, -0.6), Vector2(0.20, 0.0), Vector2(0.24, 1.2), Vector2(0.15, 2.3), Vector2(0.0, 2.9)], 8)
		g.box("lamp_white", Vector3(16.9 * sx, BODY_Y + 0.12, 7.1), Vector3(0.06, 0.04, 0.10))
		g.box("lamp_red" if sx < 0.0 else "lamp_green", Vector3(16.75 * sx, BODY_Y + 0.10, 6.62), Vector3(0.08, 0.04, 0.06))
		# ---- an engine under the wing: the cowl with its lip, the fan and spinner in the intake, the hot nozzle, the pylon
		var ec := Vector3(5.35 * sx, BODY_Y - 2.02, -3.3)
		g.lathe("cowl", ec, Vector3.BACK, [Vector2(0.92, 0.0), Vector2(1.06, 0.12), Vector2(1.15, 0.9), Vector2(1.14, 2.2), Vector2(0.98, 3.3), Vector2(0.80, 3.9), Vector2(0.72, 3.9),
			Vector2(0.86, 2.2), Vector2(0.90, 0.9), Vector2(0.88, 0.14)], 22)
		g.lathe("red", ec + Vector3(0, 0, 0.25), Vector3.BACK, [Vector2(1.158, 0.0), Vector2(1.164, 0.5), Vector2(1.158, 1.0)], 22)                 # a red band round the cowl
		g.lathe("fan", ec + Vector3(0, 0, 0.55), Vector3.BACK, [Vector2(0.0, 0.0), Vector2(0.89, 0.0)], 22)
		for k in 18:
			var a3 := TAU * float(k) / 18.0
			g.box("steel", ec + Vector3(cos(a3) * 0.56, sin(a3) * 0.56, 0.50), Vector3(0.32, 0.035, 0.02), Basis(Vector3.BACK, a3) * Basis(Vector3.RIGHT, 0.5))
		g.lathe("white", ec + Vector3(0, 0, 0.05), Vector3.BACK, [Vector2(0.0, 0.0), Vector2(0.12, 0.10), Vector2(0.24, 0.32), Vector2(0.30, 0.52)], 12)   # the spinner
		g.lathe("hot", ec + Vector3(0, 0, 3.6), Vector3.BACK, [Vector2(0.58, 0.0), Vector2(0.50, 0.9), Vector2(0.30, 1.45), Vector2(0.0, 1.9)], 16)
		g.box("wing", ec + Vector3(0, 1.12, 2.3), Vector3(0.14, 0.42, 2.4), Basis(Vector3.RIGHT, -0.10))
		# ---- a tail plane
		_plane(g, "wing", [[Vector3(0.7 * sx, BODY_Y + 1.25, 14.6), 3.6, 0.36], [Vector3(6.6 * sx, BODY_Y + 1.75, 18.2), 1.4, 0.16]], Vector3.UP)
		# ---- the main undercarriage: a leg, its brace, two wheels, the door
		var leg := Vector3(2.86 * sx, 0.0, 1.7)
		g.tube("steel", [leg + Vector3(0, 0.55, 0), leg + Vector3(-0.25 * sx, BODY_Y - 1.5, 0.1)], 0.12, 10)
		g.tube("steel", [leg + Vector3(0, 0.9, 0), leg + Vector3(-1.1 * sx, BODY_Y - 1.55, 0.0)], 0.06, 8)
		g.box("white", leg + Vector3(0.22 * sx, 1.35, 0.1), Vector3(0.03, 0.75, 0.55))
		for w in [-0.42, 0.42]:
			var wc := leg + Vector3(float(w), 0.56, 0)
			g.lathe("rubber", wc, Vector3.RIGHT, [Vector2(0.30, -0.20), Vector2(0.50, -0.21), Vector2(0.56, -0.12), Vector2(0.56, 0.12), Vector2(0.50, 0.21), Vector2(0.30, 0.20)], 18)
			g.lathe("steel", wc, Vector3.RIGHT, [Vector2(0.0, -0.10), Vector2(0.30, -0.16), Vector2(0.30, 0.16), Vector2(0.0, 0.10)], 12)
	# ---- the fin: swept, red, with the flag high on it; the rudder's line; the fairing at its foot
	_plane(g, func(i, k): return "red", [[Vector3(0, BODY_Y + 1.55, 11.9), 6.8, 0.52], [Vector3(0, BODY_Y + 4.4, 15.0), 4.4, 0.36], [Vector3(0, BODY_Y + 8.75, 18.9), 2.05, 0.18]], Vector3.RIGHT)
	_plane(g, "white", [[Vector3(0, BODY_Y + 1.0, 9.2), 3.4, 0.30], [Vector3(0, BODY_Y + 1.95, 12.1), 1.6, 0.20]], Vector3.RIGHT)
	for sgn2 in [-1.0, 1.0]:
		var s2: float = sgn2
		_flag(g, Vector3(0.19 * s2, BODY_Y + 5.9, 18.1), Vector3(0, 0, -s2), 1.25, Vector3(s2, 0, 0))
	g.box("lamp_red", Vector3(0, BODY_Y + BODY_R + 0.06, -4.0), Vector3(0.09, 0.06, 0.14))                                        # the beacons, above and below
	g.box("lamp_red", Vector3(0, BODY_Y - BODY_R - 0.06, 0.5), Vector3(0.09, 0.06, 0.14))
	g.box("lamp_white", Vector3(0, BODY_Y + 1.30, 19.86), Vector3(0.05, 0.05, 0.05))
	g.lathe("hot", Vector3(0, BODY_Y + 1.26, 19.55), Vector3.BACK, [Vector2(0.16, 0.0), Vector2(0.12, 0.32), Vector2(0.0, 0.32)], 10)       # the exhaust of the unit in the tail
	for q3 in [[-9.0, 1.0], [-2.0, 1.0], [6.5, 1.0], [-11.5, -1.0], [3.5, -1.0]]:                                                # aerials on the back and the belly
		g.box("white", Vector3(0, BODY_Y + (BODY_R + 0.16) * float(q3[1]), q3[0]), Vector3(0.015, 0.17, 0.16), Basis(Vector3.RIGHT, 0.5 * float(q3[1])))
	# ---- the nose wheel: its leg, two wheels, the doors standing open
	g.tube("steel", [Vector3(0, 0.42, -15.6), Vector3(0, BODY_Y - 1.55, -15.45)], 0.085, 10)
	g.tube("steel", [Vector3(0, 0.9, -15.6), Vector3(0, BODY_Y - 1.6, -14.5)], 0.045, 8)
	for w2 in [-0.22, 0.22]:
		var wc2 := Vector3(float(w2), 0.40, -15.6)
		g.lathe("rubber", wc2, Vector3.RIGHT, [Vector2(0.20, -0.11), Vector2(0.35, -0.12), Vector2(0.40, -0.07), Vector2(0.40, 0.07), Vector2(0.35, 0.12), Vector2(0.20, 0.11)], 16)
		g.lathe("steel", wc2, Vector3.RIGHT, [Vector2(0.0, -0.06), Vector2(0.20, -0.09), Vector2(0.20, 0.09), Vector2(0.0, 0.06)], 10)
		g.box("white", Vector3(0.50 * signf(float(w2)), BODY_Y - 1.95, -15.2), Vector3(0.02, 0.36, 0.80))
	g.box("lamp_white", Vector3(0, 1.75, -15.72), Vector3(0.10, 0.07, 0.04))                                                     # the taxi lamp on the leg
	var lamp_w := _mat(Color(1.0, 0.98, 0.90), 0.3)
	lamp_w.emission_enabled = true
	lamp_w.emission = Color(1.0, 0.97, 0.85)
	var lamp_r := _mat(Color(0.95, 0.10, 0.08), 0.3)
	lamp_r.emission_enabled = true
	lamp_r.emission = Color(1.0, 0.1, 0.05)
	var lamp_g := _mat(Color(0.10, 0.85, 0.25), 0.3)
	lamp_g.emission_enabled = true
	lamp_g.emission = Color(0.1, 1.0, 0.3)
	var mats := {"white": _mat(Color(0.94, 0.94, 0.93), 0.32, 0.1), "belly": _mat(Color(0.80, 0.81, 0.83), 0.35, 0.1), "red": _mat(Color(0.83, 0.07, 0.10), 0.30, 0.1),
		"navy": _mat(Color(0.05, 0.12, 0.33), 0.30, 0.1), "wing": _mat(Color(0.74, 0.76, 0.79), 0.32, 0.55), "cowl": _mat(Color(0.93, 0.93, 0.93), 0.28, 0.2),
		"fan": _mat(Color(0.05, 0.05, 0.06), 0.5), "hot": _mat(Color(0.30, 0.29, 0.28), 0.4, 0.7), "steel": _mat(Color(0.62, 0.64, 0.67), 0.35, 0.7),
		"rubber": _mat(Color(0.03, 0.03, 0.03), 0.95), "glass": _mat(Color(0.05, 0.07, 0.10), 0.08, 0.6), "door_line": _mat(Color(0.30, 0.31, 0.33), 0.6),
		"flag_red": _mat(Color(0.73, 0.05, 0.13), 0.5), "flag_blue": _mat(Color(0.0, 0.13, 0.36), 0.5), "white_flat": _mat(Color(0.96, 0.96, 0.96), 0.5),
		"lamp_white": lamp_w, "lamp_red": lamp_r, "lamp_green": lamp_g}
	_mesh = g.commit(mats)
	return _mesh
