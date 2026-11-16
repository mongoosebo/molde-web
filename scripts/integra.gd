extends "res://scripts/car.gd"
## A Honda Integra Type R as sold in Europe (the third generation three-door, 1998-2001), in Milano red: a low,
## rounded wedge with four round headlamps in a smooth nose, a long sloping tailgate glass, a tall hoop of a
## wing, a tail-lamp cluster at each corner, and dark grey wheels. Shaped after photographs of the real car.
## It is the Volvo's script with other numbers (the outline, the wheels, how it goes) and its own details;
## the suspension, the wheels' build, the drifting and the smoke are the same.


func _init() -> void:
	LABEL = "the Integra"
	SPECS = {"speed": 40.0, "fast": 62.0, "reverse": 9.0, "power": 13.5, "brake": 33.0, "reach": 3.4,
		"drift": true, "hides_rider": true, "exit": 1.8, "camera": 6.0}
	WHEEL_R = 0.298               # a 195/55 tyre on a 15 inch rim
	RIM_R = 0.190
	ARCH_R = 0.350
	TRACK = 0.735
	AXLE_F = -1.30
	AXLE_R = 1.27
	HALF_LEN = 2.19
	# the nose curves down from the bonnet; the roof is one long arc; the tailgate glass runs down to a short deck
	TOP_LINE = [Vector2(-2.19, 0.47), Vector2(-2.186, 0.50), Vector2(-2.178, 0.535), Vector2(-2.166, 0.572), Vector2(-2.150, 0.606), Vector2(-2.128, 0.636),
		Vector2(-2.095, 0.666), Vector2(-2.05, 0.695), Vector2(-1.98, 0.722), Vector2(-1.85, 0.757), Vector2(-1.55, 0.81),
		Vector2(-1.08, 0.865), Vector2(-0.72, 1.09), Vector2(-0.38, 1.265), Vector2(-0.10, 1.315), Vector2(0.20, 1.325), Vector2(0.52, 1.305),
		Vector2(0.95, 1.20), Vector2(1.45, 1.03), Vector2(1.78, 0.945), Vector2(2.05, 0.925), Vector2(2.15, 0.89), Vector2(2.19, 0.82)]
	CABIN = Vector2(-1.08, 1.78)
	BELT = Vector2(0.865, 0.935)
	HALF_W = 0.80
	ROOF_W = 0.60
	GLASS_H = 0.40
	FLANK = [Vector2(0.822, -0.045), Vector2(0.842, 0.74), Vector2(0.850, 0.66), Vector2(0.852, 0.58), Vector2(0.850, 0.50),
		Vector2(0.845, 0.43), Vector2(0.836, 0.36), Vector2(0.824, 0.30), Vector2(0.810, 0.25)]
	STRIP = false
	SILL = 0.20
	OVERHANG = 0.26
	SCREENS = [Vector2(-1.03, -0.40), Vector2(0.60, 1.72)]
	SIDE_GLASS = Vector2(-0.78, 1.42)
	PILLARS = [Vector2(0.37, 0.44)]
	PAINT_SHADER = "res://shaders/car_paint_integra.gdshader"
	PAINT = Color(0.74, 0.035, 0.045)             # Milano red
	CORNER = 0.105
	CROWN = 0.035
	SQUEEZE = 0.15
	SQUEEZE_LEN = 0.55
	SQUEEZE_TAIL = 0.06
	END_FINE = 0.20
	BODY_BOX = Vector3(1.74, 1.15, 4.42)
	_aerial_base = Vector3(-0.40, 1.315, 0.15)
	AERIAL_LEN = 0.40
	FOX_TAIL = false


func _tune_materials() -> void:
	_mats["alloy"] = _mat(Color(0.20, 0.21, 0.23), 0.35, 0.8)         # the dark grey wheels the red cars had
	_mats["badge"] = _lit(Color(0.80, 0.03, 0.04), 0.2)
	_mats["clear"] = _lit(Color(0.86, 0.86, 0.82), 0.25)
	_mats["chromed"] = _mat(Color(0.82, 0.83, 0.85), 0.15, 0.95)


## A round headlamp let into the rounded nose, facing the way the nose faces there (forward and a little up):
## a dark bowl sunk into the body, a bright ring and a domed lens.
func _round_lamp(g: Geo, x: float, y: float, z: float, r: float) -> void:
	var out := Vector3(0, 0.31, -0.95).normalized()
	var c := Vector3(x, y, z)
	g.lathe("black", c, out, [Vector2(r + 0.016, 0.006), Vector2(r + 0.016, -0.03), Vector2(0.0, -0.03)], 32)
	g.lathe("black", c, out, [Vector2(0.0, 0.006), Vector2(r + 0.016, 0.006)], 32)
	g.lathe("chromed", c, out, [Vector2(r + 0.008, 0.004), Vector2(r + 0.006, 0.014), Vector2(r - 0.006, 0.016), Vector2(r - 0.010, 0.010)], 32)
	g.lathe("lamp", c, out, [Vector2(r - 0.008, 0.010), Vector2(r * 0.85, 0.017), Vector2(r * 0.55, 0.022), Vector2(r * 0.25, 0.0245), Vector2(0.0, 0.025)], 32)
	g.lathe("chromed", c, out, [Vector2(r * 0.42, 0.024), Vector2(r * 0.36, 0.028), Vector2(r * 0.30, 0.026)], 20)       # the ring of the projector inside


func _build_details(g: Geo) -> void:
	var fz := -2.19                                                                         # the flat of the nose
	# four round headlamps, the larger ones outside, and the badge between the pairs
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		_round_lamp(g, 0.535 * sx, 0.563, -2.165, 0.066)
		_round_lamp(g, 0.388 * sx, 0.560, -2.166, 0.054)
		# in the bumper: the clear lamp strip at each corner and the small duct beside the intake
		g.box("black", Vector3(0.50 * sx, 0.335, fz - 0.002), Vector3(0.125, 0.027, 0.004))
		g.box("clear", Vector3(0.515 * sx, 0.335, fz - 0.006), Vector3(0.105, 0.02, 0.004))
		g.box("amber", Vector3(0.425 * sx, 0.335, fz - 0.007), Vector3(0.02, 0.018, 0.004))
		g.box("amber", Vector3(0.853 * sx, 0.60, -1.70), Vector3(0.003, 0.014, 0.026))       # side repeaters
		# a tail-lamp cluster at each corner: red, with the paler round-ended part toward the middle
		g.box("black", Vector3(0.50 * sx, 0.775, 2.190), Vector3(0.235, 0.058, 0.006))
		g.box("red", Vector3(0.565 * sx, 0.775, 2.198), Vector3(0.16, 0.05, 0.005))
		g.box("clear", Vector3(0.35 * sx, 0.775, 2.198), Vector3(0.055, 0.042, 0.005))
		g.cyl("clear", Vector3(0.295 * sx, 0.775, 2.198), Vector3.BACK, 0.042, 0.005, 20)
		g.cyl("amber", Vector3(0.35 * sx, 0.775, 2.202), Vector3.BACK, 0.03, 0.003, 18)
		for r in 3:
			g.box("black", Vector3(0.565 * sx, 0.745 + 0.03 * float(r), 2.2045), Vector3(0.155, 0.0015, 0.0015))
		g.box("red", Vector3(0.742 * sx, 0.775, 2.16), Vector3(0.012, 0.05, 0.035))           # round the corner
		# mirrors, in the body colour, on the corner of the door glass
		g.box("black", Vector3(0.815 * sx, 0.905, -0.80), Vector3(0.022, 0.012, 0.028))
		g.box("paint", Vector3(0.905 * sx, 0.935, -0.79), Vector3(0.075, 0.048, 0.04))
		g.box("paint", Vector3(0.905 * sx, 0.935, -0.835), Vector3(0.06, 0.036, 0.012))
		g.box("glass", Vector3(0.905 * sx, 0.935, -0.748), Vector3(0.064, 0.038, 0.002))
		# the wing: a tall leg rising from each side of the tail, leaning in and back, in four pieces
		for q in 4:
			var t0 := float(q) / 4.0
			var t1 := float(q + 1) / 4.0
			var a := Vector3((0.735 - 0.035 * t0 * t0) * sx, 0.93 + 0.225 * t0, 1.90 + 0.14 * t0)
			var b := Vector3((0.735 - 0.035 * t1 * t1) * sx, 0.93 + 0.225 * t1, 1.90 + 0.14 * t1)
			var up := (b - a).normalized()
			var side := Vector3(1, 0, 0)
			g.box("paint", (a + b) * 0.5, Vector3(0.016, a.distance_to(b) * 0.5 + 0.004, 0.075 - 0.02 * t0), Basis(side, up, side.cross(up).normalized()))
		# sill skirts
		g.box("paint", Vector3(0.818 * sx, 0.232, -0.02), Vector3(0.014, 0.036, 0.90))
		# wipers
		var slope := Basis(Vector3.RIGHT, -0.53)
		g.box("black", Vector3(0.26 * sx - 0.10, 0.915, -1.03) + slope.z * -0.20, Vector3(0.007, 0.007, 0.21), slope * Basis(Vector3.UP, 0.95))
	g.box("badge", Vector3(0, 0.602, -2.176), Vector3(0.034, 0.028, 0.004), Basis(Vector3.RIGHT, 0.315))    # leaning back with the nose
	g.box("black", Vector3(0, 0.408, fz - 0.002), Vector3(0.27, 0.056, 0.003))               # number plates
	g.box("plate", Vector3(0, 0.408, fz - 0.006), Vector3(0.26, 0.05, 0.002))
	g.box("black", Vector3(0, 0.305, fz - 0.002), Vector3(0.33, 0.036, 0.005))               # the air intake under the plate
	for k in 3:
		g.box("iron", Vector3(0, 0.285 + 0.02 * float(k), fz - 0.008), Vector3(0.32, 0.003, 0.003))
	g.box("paint", Vector3(0, 0.225, -2.14), Vector3(0.74, 0.02, 0.085))                    # the lip under the bumper
	# the tail: the badge on the tailgate, the plate low in the bumper, a fog lamp beside it
	g.box("badge", Vector3(0, 0.80, 2.196), Vector3(0.034, 0.028, 0.004))
	g.box("black", Vector3(0, 0.455, 2.193), Vector3(0.27, 0.058, 0.003))
	g.box("plate", Vector3(0, 0.455, 2.197), Vector3(0.26, 0.052, 0.002))
	g.box("red", Vector3(0.40, 0.36, 2.195), Vector3(0.07, 0.022, 0.004))
	# the blade of the wing across the tops of its legs, a little arched: in five pieces
	for q in 5:
		var x0 := -0.70 + 1.40 * float(q) / 5.0
		var x1 := -0.70 + 1.40 * float(q + 1) / 5.0
		var y0 := 1.165 + 0.02 * (1.0 - pow(x0 / 0.70, 2.0))
		var y1 := 1.165 + 0.02 * (1.0 - pow(x1 / 0.70, 2.0))
		var a2 := Vector3(x0, y0, 2.045)
		var b2 := Vector3(x1, y1, 2.045)
		var along := (b2 - a2).normalized()
		g.box("paint", (a2 + b2) * 0.5, Vector3(a2.distance_to(b2) * 0.5 + 0.003, 0.011, 0.075), Basis(along, along.cross(Vector3.BACK).normalized() * -1.0, Vector3.BACK) * Basis(Vector3.RIGHT, -0.09))
		g.box("paint", (a2 + b2) * 0.5 + Vector3(0, 0.008, -0.012), Vector3(a2.distance_to(b2) * 0.5 + 0.003, 0.006, 0.045), Basis(along, along.cross(Vector3.BACK).normalized() * -1.0, Vector3.BACK) * Basis(Vector3.RIGHT, -0.09))
	# exhaust: one tail pipe, on the left
	g.lathe("chrome", Vector3(-0.47, 0.27, 2.15), Vector3.BACK, [Vector2(0.0, -0.02), Vector2(0.038, -0.02), Vector2(0.043, 0.0), Vector2(0.043, 0.12),
		Vector2(0.035, 0.12), Vector2(0.035, 0.02), Vector2(0.0, 0.02)], 20)
	g.box("iron", Vector3(-0.38, 0.21, 1.75), Vector3(0.15, 0.055, 0.28))
	g.cyl("black", Vector3(_aerial_base.x, _aerial_base.y - 0.004, _aerial_base.z), Vector3.UP, 0.014, 0.008, 12)
