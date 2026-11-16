extends "res://scripts/car.gd"
## A Mercedes-Benz estate of the 124 series (the "T-model", 1985-96), in dark blue: the long roof running
## right back to an upright tailgate, roof rails, the chrome grille with the star standing on top of it,
## square headlamps with the indicators wrapped round the corners, ribbed tail lamps, grey lower flanks.
## It is the Volvo's script with other numbers and its own details; it is built, sprung and driven the same.


func _init() -> void:
	LABEL = "the Mercedes"
	SPECS = {"speed": 37.0, "fast": 54.0, "reverse": 9.0, "power": 10.0, "brake": 30.0, "reach": 3.6,
		"drift": true, "hides_rider": true, "exit": 1.9, "camera": 6.6}
	WHEEL_R = 0.312               # a 195/65 tyre on a 15 inch rim
	RIM_R = 0.190
	ARCH_R = 0.375
	TRACK = 0.745
	AXLE_F = -1.44
	AXLE_R = 1.36
	HALF_LEN = 2.38
	TOP_LINE = [Vector2(-2.38, 0.80), Vector2(-2.34, 0.875), Vector2(-2.20, 0.905), Vector2(-1.06, 0.975), Vector2(-0.44, 1.425), Vector2(0.20, 1.462),
		Vector2(1.40, 1.458), Vector2(2.14, 1.435), Vector2(2.22, 1.40), Vector2(2.345, 1.02), Vector2(2.38, 0.93)]
	CABIN = Vector2(-1.06, 2.345)
	BELT = Vector2(0.975, 1.012)
	HALF_W = 0.835
	ROOF_W = 0.69
	GLASS_H = 0.42
	FLANK = [Vector2(0.848, -0.045), Vector2(0.866, 0.80), Vector2(0.870, 0.70), Vector2(0.870, 0.62), Vector2(0.880, 0.61),
		Vector2(0.880, 0.36), Vector2(0.872, 0.35), Vector2(0.868, 0.33), Vector2(0.858, 0.31)]
	STRIP = true                                  # here it is the broad grey cladding along the lower flank
	SILL = 0.26
	OVERHANG = 0.35
	SCREENS = [Vector2(-1.01, -0.48), Vector2(2.235, 2.335)]
	SIDE_GLASS = Vector2(-0.72, 2.10)
	PILLARS = [Vector2(0.15, 0.25), Vector2(1.16, 1.26)]
	PAINT = Color(0.075, 0.12, 0.22)              # dark blue
	CORNER = 0.055
	CROWN = 0.016
	SQUEEZE = 0.07
	BODY_BOX = Vector3(1.78, 1.30, 4.8)
	_aerial_base = Vector3(0.70, 0.96, 2.0)
	AERIAL_LEN = 0.75
	FOX_TAIL = false


func _tune_materials() -> void:
	_mats["black"] = _mat(Color(0.30, 0.31, 0.33), 0.6)               # the cladding and bumpers are grey on this car
	_mats["trim"] = _mat(Color(0.045, 0.045, 0.05), 0.7)
	_mats["chromed"] = _mat(Color(0.82, 0.83, 0.85), 0.15, 0.95)


func _build_details(g: Geo) -> void:
	_bumper(g, -2.41, 0.47, -1.0)
	_bumper(g, 2.41, 0.47, 1.0)
	g.box("trim", Vector3(0, 0.33, -2.30), Vector3(0.80, 0.05, 0.06))                       # valances
	g.box("trim", Vector3(0, 0.34, 2.31), Vector3(0.80, 0.05, 0.05))
	# the grille: a broad chrome frame leaning back a little, fine slats, a bar down the middle, the star above
	var fz := -2.385
	g.box("chromed", Vector3(0, 0.885, fz), Vector3(0.335, 0.012, 0.016))
	g.box("chromed", Vector3(0, 0.625, fz), Vector3(0.335, 0.010, 0.016))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("chromed", Vector3(0.335 * sx, 0.755, fz), Vector3(0.012, 0.14, 0.016))
	g.box("trim", Vector3(0, 0.755, fz + 0.012), Vector3(0.325, 0.13, 0.004))
	for k in 9:
		g.box("chromed", Vector3(0, 0.65 + 0.026 * float(k), fz - 0.004), Vector3(0.32, 0.0035, 0.006))
	g.box("chromed", Vector3(0, 0.755, fz - 0.008), Vector3(0.010, 0.125, 0.006))
	g.cyl("chromed", Vector3(0, 0.935, -2.36), Vector3.UP, 0.012, 0.022, 10)                  # the star on its foot
	g.lathe("chromed", Vector3(0, 1.00, -2.36), Vector3.BACK, [Vector2(0.050, -0.004), Vector2(0.050, 0.004), Vector2(0.043, 0.004), Vector2(0.043, -0.004), Vector2(0.050, -0.004)], 24)
	for k in 3:
		var a := TAU * float(k) / 3.0 + PI * 0.5
		g.box("chromed", Vector3(cos(a) * 0.022, 1.00 + sin(a) * 0.022, -2.36), Vector3(0.024, 0.004, 0.003), Basis(Vector3.BACK, a))
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		# headlamps: one broad lamp a side, ribbed, with the indicator round the corner and a fog lamp below
		g.box("chromed", Vector3(0.585 * sx2, 0.755, -2.372), Vector3(0.225, 0.095, 0.008))
		g.box("lamp", Vector3(0.585 * sx2, 0.755, -2.382), Vector3(0.21, 0.082, 0.006))
		for r in 6:
			g.box("chromed", Vector3(0.585 * sx2, 0.69 + 0.026 * float(r), -2.389), Vector3(0.21, 0.002, 0.002))
		g.box("amber", Vector3(0.832 * sx2, 0.755, -2.32), Vector3(0.012, 0.085, 0.06))
		g.box("lamp", Vector3(0.50 * sx2, 0.43, -2.515), Vector3(0.10, 0.03, 0.006))
		g.box("amber", Vector3(0.879 * sx2, 0.68, -1.95), Vector3(0.004, 0.018, 0.03))
		# tail lamps: broad and ribbed, either side of the tailgate
		g.box("trim", Vector3(0.62 * sx2, 0.80, 2.372), Vector3(0.215, 0.105, 0.008))
		var kinds := ["amber", "red", "red", "lamp"]
		for k in 4:
			g.box(kinds[k], Vector3((0.775 - 0.105 * float(k)) * sx2, 0.80, 2.382), Vector3(0.049, 0.094, 0.006))
		for r in 6:
			g.box("trim", Vector3(0.62 * sx2, 0.72 + 0.032 * float(r), 2.390), Vector3(0.21, 0.003, 0.003))      # the ribs that keep them clean
		g.box("red", Vector3(0.838 * sx2, 0.80, 2.33), Vector3(0.012, 0.09, 0.05))
		# mirrors, wipers
		g.box("trim", Vector3(0.87 * sx2, 1.03, -0.76), Vector3(0.03, 0.012, 0.03))
		g.box("paint", Vector3(0.955 * sx2, 1.055, -0.75), Vector3(0.078, 0.052, 0.036))
		g.box("glass", Vector3(0.955 * sx2, 1.055, -0.712), Vector3(0.068, 0.043, 0.002))
		var slope := Basis(Vector3.RIGHT, -0.63)
		g.box("trim", Vector3(0.28 * sx2 - 0.10, 1.03, -1.02) + slope.z * -0.20, Vector3(0.008, 0.008, 0.22), slope * Basis(Vector3.UP, 0.9))
		# roof rails: a tube the length of the roof on four feet
		g.tube("chromed", [Vector3(0.60 * sx2, 1.50, -0.25), Vector3(0.61 * sx2, 1.515, 0.0), Vector3(0.61 * sx2, 1.515, 1.90), Vector3(0.60 * sx2, 1.49, 2.12)], 0.013, 8)
		for fz2 in [-0.20, 0.60, 1.35, 2.08]:
			g.box("trim", Vector3(0.61 * sx2, 1.485, fz2), Vector3(0.016, 0.022, 0.035))
	# the tailgate: its handle and lock, the wiper on the glass, plates, badges, exhaust
	g.box("chromed", Vector3(0, 0.99, 2.372), Vector3(0.09, 0.012, 0.008))
	g.box("trim", Vector3(0.10, 1.12, 2.335), Vector3(0.20, 0.008, 0.008), Basis(Vector3.BACK, 0.25))
	for pz in [[-2.525, 0.47], [2.378, 0.66]]:
		g.box("trim", Vector3(0, pz[1], pz[0]), Vector3(0.27, 0.062, 0.004))
		g.box("plate", Vector3(0, pz[1], pz[0] + signf(pz[0]) * 0.004), Vector3(0.26, 0.055, 0.002))
	g.cyl("chromed", Vector3(0, 0.90, 2.374), Vector3.BACK, 0.035, 0.004, 18)                 # the star on the tailgate
	for k in 4:
		g.box("chromed", Vector3(0.50 + 0.035 * float(k), 0.92, 2.372), Vector3(0.012, 0.014, 0.003))  # 230 TE
	g.lathe("chrome", Vector3(-0.50, 0.30, 2.37), Vector3.BACK, [Vector2(0.0, -0.02), Vector2(0.026, -0.02), Vector2(0.03, 0.0), Vector2(0.03, 0.16),
		Vector2(0.024, 0.16), Vector2(0.024, 0.02), Vector2(0.0, 0.02)], 16)
	g.box("iron", Vector3(-0.40, 0.25, 1.9), Vector3(0.16, 0.06, 0.30))
	g.cyl("trim", Vector3(_aerial_base.x, _aerial_base.y - 0.005, _aerial_base.z), Vector3.UP, 0.016, 0.012, 12)
