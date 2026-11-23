extends RefCounted
## A town bus of FRAM, the bus company of Møre og Romsdal: a 12 m low-floor bus in blue, with white lettering
## and lighter blue waves along its sides. Built in the detail of the player's Volvo: a rounded body, the band of
## windows with its pillars, two double doors on the right, the windscreen with wipers and mirrors on arms,
## lamps and indicators, the destination board, the engine's grilles at the back, the units on the roof, wheels
## with rims and bolts that turn (the front ones steer). Faces -Z, stands on y = 0.
## (Blue as asked in the note of 18 Nov; the livery is drawn from memory of the buses, not from a picture.)

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo)

const LEN := 12.0
const HALF_W := 1.275
const FLOOR := 0.30               # the underside of the skirts
const ROOF := 3.05
const WHEEL_R := 0.48
const AXLE_F := -3.35
const AXLE_R := 2.75

static var _body: ArrayMesh
static var _wheel: ArrayMesh
static var triangles := 0


static func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _mats() -> Dictionary:
	var lamp := _mat(Color(0.98, 0.97, 0.90), 0.2)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.97, 0.85)
	lamp.emission_energy_multiplier = 0.6
	var board := _mat(Color(1.0, 0.62, 0.10), 0.4)
	board.emission_enabled = true
	board.emission = Color(1.0, 0.62, 0.10)
	board.emission_energy_multiplier = 1.2
	return {"blue": _mat(Color(0.04, 0.20, 0.47), 0.28, 0.25), "light": _mat(Color(0.20, 0.55, 0.82), 0.3, 0.2), "pale": _mat(Color(0.55, 0.80, 0.93), 0.3, 0.2),
		"white": _mat(Color(0.94, 0.95, 0.96), 0.35), "glass": _mat(Color(0.05, 0.07, 0.09), 0.08, 0.6), "black": _mat(Color(0.03, 0.03, 0.035), 0.7),
		"rubber": _mat(Color(0.03, 0.03, 0.03), 0.95), "grey": _mat(Color(0.33, 0.34, 0.36), 0.6), "alloy": _mat(Color(0.72, 0.73, 0.75), 0.3, 0.8),
		"lamp": lamp, "amber": _mat(Color(0.95, 0.52, 0.05), 0.3), "red": _mat(Color(0.75, 0.04, 0.04), 0.3), "board": board, "plate": _mat(Color(0.93, 0.93, 0.90), 0.5)}


static func _build() -> void:
	var g = Shapes.Geo.new()
	var hl := LEN * 0.5
	# the body: rings from nose to tail, flat-sided, the roof's edges and the corners of the nose rounded
	var rows := []
	for q in [[-hl, 0.90, 0.30, 0.10], [-hl + 0.06, 0.955, 0.12, 0.05], [-hl + 0.22, 0.99, 0.03, 0.01], [-hl + 0.55, 1.0, 0.0, 0.0], [-2.0, 1.0, 0.0, 0.0], [2.0, 1.0, 0.0, 0.0],
			[hl - 0.45, 1.0, 0.0, 0.0], [hl - 0.16, 0.99, 0.02, 0.01], [hl - 0.04, 0.965, 0.08, 0.04], [hl, 0.93, 0.18, 0.08]]:
		var ring := PackedVector3Array()
		var w: float = HALF_W * float(q[1])
		var top: float = ROOF - float(q[2])
		var low: float = FLOOR + float(q[3])
		var r := 0.22
		ring.append(Vector3(-w, low, q[0]))
		for k in 9:                                              # up the left side and round over the roof's edge
			var a := PI * 0.5 * float(k) / 8.0
			ring.append(Vector3(-w + r - cos(a) * r, top - r + sin(a) * r, q[0]))
		for k in 9:
			var a2 := PI * 0.5 * float(8 - k) / 8.0
			ring.append(Vector3(w - r + cos(a2) * r, top - r + sin(a2) * r, q[0]))
		ring.append(Vector3(w, low, q[0]))
		rows.append(ring)
	g.skin(rows, true, "blue")
	g.cap("blue", rows[0], Vector3.FORWARD)
	g.cap("blue", rows[-1], Vector3.BACK)
	# the skirt under the body and the wheel arches cut dark into it
	g.box("black", Vector3(0, FLOOR + 0.05, 0), Vector3(HALF_W - 0.02, 0.06, hl - 0.2))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		var x := (HALF_W + 0.004) * sx
		for az in [AXLE_F, AXLE_R]:
			var zc: float = az
			# the wheel arch: a dark round behind each wheel. (A black plate stood here over the whole wheel, and the
			# wheel itself sat inside the body's side where it could not be seen: "a weird black cover on the outside
			# of the bus wheels", 20 Nov. The wheels now stand out of the side, as on the Volvo.)
			g.cyl("black", Vector3(x, 0.50, zc), Vector3.RIGHT, 0.57, 0.006, 28)
		# the band of windows: dark glass from behind the windscreen to the tail, a pillar between each pane
		g.box("glass", Vector3(x, 1.95, 0.35), Vector3(0.008, 0.62, hl - 0.75))
		for k in 9:
			g.box("black", Vector3(x + 0.004 * sx, 1.95, -4.35 + 1.22 * float(k)), Vector3(0.006, 0.62, 0.035))
		g.box("black", Vector3(x + 0.004 * sx, 2.30, 0.35), Vector3(0.005, 0.012, hl - 0.75))               # the line of the opening top lights
		for k in 8:
			g.box("alloy", Vector3(x + 0.008 * sx, 2.42, -3.74 + 1.22 * float(k)), Vector3(0.004, 0.012, 0.05))   # their catches
		# the waves of lighter blue along the lower side, rising toward the back
		var xw := x + 0.006 * sx
		var hint := Vector3(sx, 0, 0)
		for k in 48:
			var t0 := float(k) / 48.0
			var t1 := float(k + 1) / 48.0
			var z0 := lerpf(-2.2, hl - 0.5, t0)
			var z1 := lerpf(-2.2, hl - 0.5, t1)
			# a broad wave swelling toward the back, and a narrow pale one under it
			var a0 := 0.46 + 0.50 * t0 * t0 + 0.06 * sin(t0 * 7.0)
			var a1 := 0.46 + 0.50 * t1 * t1 + 0.06 * sin(t1 * 7.0)
			var w0 := 0.30 * sin(t0 * PI) * (0.4 + 0.6 * t0) + 0.01
			var w1 := 0.30 * sin(t1 * PI) * (0.4 + 0.6 * t1) + 0.01
			g.quad("light", Vector3(xw, a0, z0), Vector3(xw, a0 + w0, z0), Vector3(xw, a1 + w1, z1), Vector3(xw, a1, z1), hint)
			var b0 := a0 - 0.10 - 0.05 * t0
			var b1 := a1 - 0.10 - 0.05 * t1
			g.quad("pale", Vector3(xw, b0, z0), Vector3(xw, b0 + w0 * 0.3, z0), Vector3(xw, b1 + w1 * 0.3, z1), Vector3(xw, b1, z1), hint)
		g.box("white", Vector3(x, 1.27, 0.3), Vector3(0.004, 0.012, hl - 0.8))                               # a fine white line under the windows
		# side markers, the repeater, reflectors
		for k in 5:
			g.box("amber", Vector3(x + 0.004 * sx, 0.78, -4.6 + 2.3 * float(k)), Vector3(0.006, 0.022, 0.05))
		g.box("amber", Vector3(x + 0.004 * sx, 1.12, -5.15), Vector3(0.008, 0.03, 0.06))
		# the mirror on its arm, out ahead of the corner
		g.tube("black", [Vector3(HALF_W * 0.95 * sx, 2.72, -hl + 0.20), Vector3((HALF_W + 0.30) * sx, 2.66, -hl - 0.18), Vector3((HALF_W + 0.36) * sx, 2.30, -hl - 0.22)], 0.022, 8)
		g.box("black", Vector3((HALF_W + 0.37) * sx, 2.02, -hl - 0.22), Vector3(0.10, 0.24, 0.05))
		g.box("alloy", Vector3((HALF_W + 0.37) * sx, 2.02, -hl - 0.168), Vector3(0.085, 0.21, 0.004))
		# head lamps: two round ones a side in a dark surround, the indicator outside them, a fog lamp in the bumper
		g.box("black", Vector3(0.86 * sx, 0.86, -hl - 0.006), Vector3(0.33, 0.12, 0.02))
		for k in 2:
			g.cyl("alloy", Vector3((0.70 + 0.24 * float(k)) * sx, 0.86, -hl - 0.022), Vector3.BACK, 0.092, 0.010, 20)
			g.cyl("lamp", Vector3((0.70 + 0.24 * float(k)) * sx, 0.86, -hl - 0.034), Vector3.BACK, 0.076, 0.006, 20)
		g.box("amber", Vector3(1.14 * sx, 0.86, -hl + 0.02), Vector3(0.05, 0.08, 0.03))
		g.cyl("lamp", Vector3(0.80 * sx, 0.50, -hl - 0.03), Vector3.BACK, 0.055, 0.008, 14)
		# tail lamps: a tall cluster each side (indicator, tail, brake, reverse), a reflector, a lamp high up
		g.box("black", Vector3(1.05 * sx, 1.20, hl + 0.004), Vector3(0.12, 0.42, 0.02))
		for q2 in [[1.50, "amber"], [1.30, "red"], [1.10, "red"], [0.90, "lamp"]]:
			g.cyl(q2[1], Vector3(1.05 * sx, q2[0], hl + 0.022), Vector3.BACK, 0.075, 0.008, 16)
		g.box("red", Vector3(1.05 * sx, 0.60, hl + 0.01), Vector3(0.09, 0.03, 0.01))
		g.box("red", Vector3(1.08 * sx, 2.86, hl - 0.03), Vector3(0.07, 0.03, 0.02))
		g.box("lamp", Vector3(1.08 * sx, 2.90, -hl + 0.10), Vector3(0.06, 0.02, 0.02))
	# the doors on the right (the kerb side): a double door at the front and one in the middle, glass to the floor
	for dz in [-4.72, 0.20]:
		var z0: float = dz
		var xr := HALF_W + 0.006
		g.box("black", Vector3(xr, 1.52, z0), Vector3(0.010, 1.16, 0.66))
		for leaf in [-0.325, 0.325]:
			g.box("glass", Vector3(xr + 0.008, 1.56, z0 + float(leaf)), Vector3(0.006, 1.04, 0.285))
			g.box("alloy", Vector3(xr + 0.016, 1.30, z0 + float(leaf) * 0.25), Vector3(0.012, 0.42, 0.012))        # the grab rail inside the glass
		g.box("rubber", Vector3(xr + 0.012, 1.52, z0), Vector3(0.008, 1.14, 0.012))                             # the seal where the leaves meet
		g.box("amber", Vector3(xr + 0.008, 2.76, z0), Vector3(0.006, 0.03, 0.30))                                 # the lamp over the door
		g.box("alloy", Vector3(xr - 0.02, 0.36, z0), Vector3(0.03, 0.02, 0.64))                                   # the sill
	# the driver's window on the left, lower than the rest, and the hatch for the battery
	g.box("glass", Vector3(-HALF_W - 0.006, 1.72, -5.05), Vector3(0.008, 0.80, 0.55))
	g.box("black", Vector3(-HALF_W - 0.010, 1.72, -5.05), Vector3(0.004, 0.012, 0.55))
	for q3 in [[-2.3, 0.75, 0.55, 0.22], [1.2, 0.75, 0.45, 0.22], [4.6, 0.95, 0.50, 0.42], [-HALF_W, 0, 0, 0]]:
		if q3[2] > 0.0:
			for edge in [[0.0, float(q3[3]), float(q3[2]), 0.004], [0.0, -float(q3[3]), float(q3[2]), 0.004], [float(q3[2]), 0.0, 0.004, float(q3[3])], [-float(q3[2]), 0.0, 0.004, float(q3[3])]]:
				g.box("black", Vector3(-HALF_W - 0.004, float(q3[1]) + float(edge[1]), float(q3[0]) + float(edge[0])), Vector3(0.004, edge[3], edge[2]))
	g.cyl("black", Vector3(-HALF_W - 0.006, 0.95, 2.0), Vector3.RIGHT, 0.07, 0.006, 14)                           # the filler
	# the front: the windscreen in one tall pane, its dark surround, the destination board over it, wipers, the
	# grille low down, the bumper, the number plate
	g.box("black", Vector3(0, 1.98, -hl - 0.004), Vector3(1.20, 0.98, 0.02))
	g.box("glass", Vector3(0, 1.80, -hl - 0.014), Vector3(1.16, 0.72, 0.012))
	g.box("black", Vector3(0, 2.72, -hl - 0.016), Vector3(1.05, 0.17, 0.014))
	g.box("board", Vector3(-0.72, 2.72, -hl - 0.032), Vector3(0.17, 0.11, 0.004))                                  # the line's number (the words are lettered on in the game)
	for sgn2 in [-1.0, 1.0]:
		var sw: float = sgn2
		g.tube("black", [Vector3(0.45 * sw, 1.10, -hl - 0.03), Vector3(0.30 * sw, 1.55, -hl - 0.035), Vector3(0.10 * sw, 1.95, -hl - 0.035)], 0.012, 6)
		g.box("black", Vector3(0.20 * sw, 1.76, -hl - 0.04), Vector3(0.012, 0.36, 0.008), Basis(Vector3.BACK, 0.42 * sw))
	g.box("black", Vector3(0, 0.50, -hl - 0.02), Vector3(1.22, 0.16, 0.05))
	for k in 5:
		g.box("grey", Vector3(0, 0.40 + 0.045 * float(k), -hl - 0.075), Vector3(0.40, 0.008, 0.006))
	g.box("plate", Vector3(0, 0.62, -hl - 0.078), Vector3(0.26, 0.055, 0.004))
	g.box("white", Vector3(0, 1.02, -hl - 0.03), Vector3(0.50, 0.012, 0.004))
	# the back: a low rear window, the engine's grilles, the bumper, the plate, the number of the line
	g.box("glass", Vector3(0, 2.30, hl + 0.004), Vector3(0.95, 0.36, 0.012))
	g.box("black", Vector3(0, 1.20, hl + 0.006), Vector3(0.80, 0.50, 0.012))
	for k in 12:
		g.box("grey", Vector3(0, 0.78 + 0.075 * float(k), hl + 0.022), Vector3(0.76, 0.012, 0.006))
	g.box("black", Vector3(0, 0.46, hl + 0.02), Vector3(1.22, 0.14, 0.05))
	g.box("plate", Vector3(0, 0.66, hl + 0.03), Vector3(0.26, 0.055, 0.004))
	g.box("board", Vector3(0.62, 2.30, hl + 0.018), Vector3(0.16, 0.10, 0.004))
	g.cyl("alloy", Vector3(-0.85, 0.36, hl + 0.02), Vector3.BACK, 0.045, 0.06, 12)                                # the exhaust
	# the roof: the air-conditioning unit, the hatches, the fairing at the front, an aerial
	g.box("white", Vector3(0, ROOF + 0.11, 2.6), Vector3(0.88, 0.12, 1.25))
	g.box("grey", Vector3(0, ROOF + 0.235, 2.6), Vector3(0.70, 0.008, 1.0))
	for k in 6:
		g.box("grey", Vector3(0, ROOF + 0.13, 1.6 + 0.4 * float(k)), Vector3(0.885, 0.07, 0.012))
	for hz in [-2.6, -0.2]:
		g.box("white", Vector3(0, ROOF + 0.035, hz), Vector3(0.42, 0.04, 0.42))
		g.box("grey", Vector3(0, ROOF + 0.078, hz), Vector3(0.36, 0.006, 0.36))
	g.box("blue", Vector3(0, ROOF + 0.05, -hl + 0.9), Vector3(0.95, 0.06, 0.55), Basis(Vector3.RIGHT, 0.10))
	g.tube("black", [Vector3(0.5, ROOF, -4.0), Vector3(0.5, ROOF + 0.45, -3.9)], 0.008, 5)
	# through the glass: the driver's seat and wheel, rows of seats, the poles
	g.box("grey", Vector3(-0.72, 1.15, -4.85), Vector3(0.24, 0.42, 0.24))
	g.lathe("black", Vector3(-0.72, 1.42, -5.30), Vector3(0, 0.5, 0.86).normalized(), [Vector2(0.17, -0.012), Vector2(0.20, 0.0), Vector2(0.17, 0.012)], 18, true)
	for k in 8:
		for sgn3 in [-1.0, 1.0]:
			g.box("light", Vector3(0.74 * float(sgn3), 1.42, -3.3 + 1.05 * float(k)), Vector3(0.40, 0.30, 0.05))
	for k in 5:
		g.tube("amber", [Vector3(0.30, 0.9, -3.8 + 2.0 * float(k)), Vector3(0.30, 2.85, -3.8 + 2.0 * float(k))], 0.016, 6)
	var mats := _mats()
	_body = g.commit(mats)
	triangles = g.count()
	# a wheel, its axle along X: a tyre with a square shoulder, a deep steel rim, the hub with its ten nuts
	var w = Shapes.Geo.new()
	w.lathe("rubber", Vector3.ZERO, Vector3.RIGHT, [Vector2(0.285, -0.13), Vector2(0.40, -0.15), Vector2(0.465, -0.135), Vector2(WHEEL_R, -0.10), Vector2(WHEEL_R, 0.10),
		Vector2(0.465, 0.135), Vector2(0.40, 0.15), Vector2(0.285, 0.13)], 36)
	for k in 36:                                                # the tread: a groove across at every tenth of a turn or so
		var a4 := TAU * float(k) / 36.0
		w.box("black", Vector3(0, sin(a4) * (WHEEL_R + 0.001), cos(a4) * (WHEEL_R + 0.001)), Vector3(0.10, 0.004, 0.012), Basis(Vector3.RIGHT, -a4))
	w.lathe("alloy", Vector3.ZERO, Vector3.RIGHT, [Vector2(0.0, 0.02), Vector2(0.12, 0.02), Vector2(0.15, 0.09), Vector2(0.285, 0.13), Vector2(0.285, 0.10), Vector2(0.17, 0.05),
		Vector2(0.13, -0.02), Vector2(0.0, -0.02)], 28)
	w.cyl("grey", Vector3(0.06, 0, 0), Vector3.RIGHT, 0.075, 0.04, 16)
	for k in 10:
		var a5 := TAU * float(k) / 10.0
		w.cyl("alloy", Vector3(0.045, sin(a5) * 0.105, cos(a5) * 0.105), Vector3.RIGHT, 0.014, 0.018, 6)
	_wheel = w.commit(mats)
	triangles += w.count() * 4


## A bus: {"node", "wheels" (the four that turn), "steer" (the two front ones' steering joints)}.
static func make() -> Dictionary:
	if _body == null:
		_build()
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = _body
	root.add_child(body)
	var wheels := []
	var steer := []
	for front in [true, false]:
		for sgn in [-1.0, 1.0]:
			var sx: float = sgn
			var hub := Node3D.new()
			hub.position = Vector3((HALF_W - 0.09) * sx, WHEEL_R, AXLE_F if front else AXLE_R)
			root.add_child(hub)
			var roll := Node3D.new()
			hub.add_child(roll)
			var mi := MeshInstance3D.new()
			mi.mesh = _wheel
			if sx < 0.0:
				mi.rotation.y = PI                               # the rim's face outward on both sides
			roll.add_child(mi)
			wheels.append(roll)
			if front:
				steer.append(hub)
	# the lettering: FRAM in white along both sides and across the front and the back, the destination in amber
	for q in [[Vector3(HALF_W + 0.012, 1.02, 2.6), Vector3.RIGHT, "FRAM", 0.36, Color(0.96, 0.97, 0.98)], [Vector3(-HALF_W - 0.012, 1.02, -1.2), Vector3.LEFT, "FRAM", 0.36, Color(0.96, 0.97, 0.98)],
			[Vector3(0, 1.08, -LEN * 0.5 - 0.04), Vector3.FORWARD, "FRAM", 0.15, Color(0.96, 0.97, 0.98)], [Vector3(0.35, 1.90, LEN * 0.5 + 0.022), Vector3.BACK, "FRAM", 0.20, Color(0.96, 0.97, 0.98)],
			[Vector3(0.18, 2.72, -LEN * 0.5 - 0.034), Vector3.FORWARD, "Molde sentrum", 0.15, Color(1.0, 0.66, 0.12)], [Vector3(-0.72, 2.72, -LEN * 0.5 - 0.038), Vector3.FORWARD, "701", 0.15, Color(0.05, 0.04, 0.02)],
			[Vector3(HALF_W + 0.012, 0.62, -2.6), Vector3.RIGHT, "frammr.no", 0.11, Color(0.96, 0.97, 0.98)]]:
		var label := Label3D.new()
		label.text = q[2]
		label.font_size = 96
		label.pixel_size = float(q[3]) / 96.0
		label.outline_size = 0
		label.modulate = q[4]
		label.shaded = false
		label.double_sided = false
		var n: Vector3 = q[1]
		label.transform = Transform3D(Basis(Vector3.UP.cross(n).normalized(), Vector3.UP, n), q[0])
		root.add_child(label)
	return {"node": root, "wheels": wheels, "steer": steer}
