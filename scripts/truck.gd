extends RefCounted
## Lorries, parked in the yard at Bolsønes and driving in the traffic (note of 20 Nov: "parked buses and trucks
## here, a couple of different trucks, also a couple for the moving traffic"). Four kinds, each a European
## cab-over lorry built the way the bus is (scripts/bus.gd): a box lorry, a tipper, a tanker, and a tractor with
## a 13.6 m semi-trailer. Each faces -Z and stands on y = 0. The wheels are separate, their axle along Y, so
## that the traffic can turn them the way it turns a car's (scripts/traffic.gd).

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo)

const HALF_W := 1.25
const WHEEL_R := 0.52
const CAB_LEN := 2.25
## kind -> length, the axles (z from the middle; the first steers), the colours it comes in (cab, body)
const KINDS := {
	"box": {"len": 8.4, "axles": [-2.85, 2.35], "paints": [[Color(0.93, 0.93, 0.92), Color(0.93, 0.93, 0.92)], [Color(0.10, 0.25, 0.55), Color(0.90, 0.90, 0.88)], [Color(0.78, 0.10, 0.08), Color(0.92, 0.92, 0.90)]]},
	"tipper": {"len": 7.6, "axles": [-2.45, 2.05], "paints": [[Color(0.92, 0.50, 0.06), Color(0.30, 0.31, 0.33)], [Color(0.90, 0.78, 0.10), Color(0.34, 0.35, 0.36)]]},
	"tank": {"len": 8.6, "axles": [-2.95, 2.45], "paints": [[Color(0.80, 0.10, 0.08), Color(0.80, 0.81, 0.83)], [Color(0.93, 0.93, 0.92), Color(0.80, 0.81, 0.83)]]},
	"semi": {"len": 16.5, "axles": [-6.85, -3.55, 4.45, 5.75, 7.05], "paints": [[Color(0.10, 0.25, 0.55), Color(0.84, 0.85, 0.86)], [Color(0.93, 0.93, 0.92), Color(0.16, 0.36, 0.22)], [Color(0.78, 0.10, 0.08), Color(0.86, 0.86, 0.84)]]},
}

static var _cache := {}
static var _wheel: ArrayMesh


static func _mat(c: Color, rough := 0.5, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


static func _mats(cab: Color, body: Color) -> Dictionary:
	var lamp := _mat(Color(0.98, 0.97, 0.90), 0.2)
	lamp.emission_enabled = true
	lamp.emission = Color(1.0, 0.97, 0.85)
	lamp.emission_energy_multiplier = 0.5
	return {"cab": _mat(cab, 0.30, 0.2), "body": _mat(body, 0.55), "glass": _mat(Color(0.05, 0.07, 0.09), 0.08, 0.6), "black": _mat(Color(0.03, 0.03, 0.035), 0.7),
		"rubber": _mat(Color(0.03, 0.03, 0.03), 0.95), "grey": _mat(Color(0.30, 0.31, 0.33), 0.6), "alloy": _mat(Color(0.74, 0.75, 0.77), 0.3, 0.8), "lamp": lamp,
		"amber": _mat(Color(0.95, 0.52, 0.05), 0.3), "red": _mat(Color(0.75, 0.04, 0.04), 0.3), "plate": _mat(Color(0.93, 0.93, 0.90), 0.5), "steel": _mat(Color(0.55, 0.56, 0.58), 0.45, 0.5)}


## The cab: its nose at z0, facing -Z. A tall cab-over with a raked windscreen, a dark grille, a bumper with
## lamps, steps, mirrors on arms, a sun visor, and for the long-distance one a wind deflector on the roof.
## Over the front wheels (their axle at `axle`) the cab's lower edge rises in an arch, so that the wheels stand
## clear in it instead of inside the cab ("the front wheels of the trucks are hidden by the chassis", 20 Nov).
static func _cab(g, z0: float, top: float, deflector: bool, axle: float) -> void:
	var z1 := z0 + CAB_LEN
	var rows := []
	var cuts := [[z0, 0.94, 0.55, 0.60], [z0 + 0.05, 0.985, 0.25, 0.56], [z0 + 0.30, 1.0, 0.04, 0.55], [z0 + 0.60, 1.0, 0.0, 0.55]]
	var arch := 0.64
	for dz in [-0.64, -0.60, -0.52, -0.38, -0.20, 0.0, 0.20, 0.38, 0.52, 0.60, 0.64]:
		var d: float = dz
		cuts.append([axle + d, 1.0, 0.0, maxf(0.55, WHEEL_R + sqrt(maxf(arch * arch - d * d, 0.0)))])
	cuts.append_array([[z1 - 0.06, 1.0, 0.0, 0.55], [z1, 0.98, 0.04, 0.58]])
	for q in cuts:
		var ring := PackedVector3Array()
		var w: float = HALF_W * float(q[1])
		var y1: float = top - float(q[2])
		var y0: float = float(q[3])
		var r := 0.14
		ring.append(Vector3(-w, y0, q[0]))
		for k in 5:
			var a := PI * 0.5 * float(k) / 4.0
			ring.append(Vector3(-w + r - cos(a) * r, y1 - r + sin(a) * r, q[0]))
		for k in 5:
			var a2 := PI * 0.5 * float(4 - k) / 4.0
			ring.append(Vector3(w - r + cos(a2) * r, y1 - r + sin(a2) * r, q[0]))
		ring.append(Vector3(w, y0, q[0]))
		rows.append(ring)
	g.skin(rows, true, "cab")
	g.cap("cab", rows[0], Vector3.FORWARD)
	g.cap("cab", rows[rows.size() - 1], Vector3.BACK)
	# the windscreen and its surround, the visor over it, the wipers
	g.box("black", Vector3(0, top - 1.02, z0 + 0.02), Vector3(1.14, 0.50, 0.035), Basis(Vector3.RIGHT, -0.10))
	g.box("glass", Vector3(0, top - 1.02, z0 + 0.005), Vector3(1.08, 0.45, 0.03), Basis(Vector3.RIGHT, -0.10))
	g.box("black", Vector3(0, top - 0.50, z0 - 0.10), Vector3(1.16, 0.035, 0.16), Basis(Vector3.RIGHT, 0.30))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("black", Vector3(0.45 * sx, top - 1.20, z0 - 0.035), Vector3(0.012, 0.30, 0.008), Basis(Vector3.BACK, 0.9 * sx))
		# the side window, the door's gap and handle, the steps under the door
		g.box("glass", Vector3((HALF_W + 0.004) * sx, top - 1.05, z0 + 1.05), Vector3(0.008, 0.36, 0.50))
		g.box("black", Vector3((HALF_W + 0.003) * sx, top - 1.60, z0 + 1.62), Vector3(0.004, 0.95, 0.008))
		g.box("black", Vector3((HALF_W + 0.003) * sx, top - 1.60, z0 + 0.50), Vector3(0.004, 0.95, 0.008))
		g.box("black", Vector3((HALF_W + 0.012) * sx, top - 1.58, z0 + 1.50), Vector3(0.012, 0.02, 0.07))
		g.box("black", Vector3((HALF_W - 0.06) * sx, 0.42, z0 + 0.42), Vector3(0.10, 0.14, 0.24))
		g.box("alloy", Vector3((HALF_W + 0.03) * sx, 0.50, z0 + 0.42), Vector3(0.02, 0.012, 0.20))
		g.box("alloy", Vector3((HALF_W + 0.03) * sx, 0.32, z0 + 0.42), Vector3(0.02, 0.012, 0.20))
		# the mirror, tall, on its arms ahead of the door
		g.tube("black", [Vector3(HALF_W * sx, top - 0.75, z0 + 0.42), Vector3((HALF_W + 0.26) * sx, top - 0.80, z0 + 0.30), Vector3((HALF_W + 0.26) * sx, top - 1.55, z0 + 0.30),
			Vector3(HALF_W * sx, top - 1.60, z0 + 0.42)], 0.018, 6)
		g.box("black", Vector3((HALF_W + 0.27) * sx, top - 1.15, z0 + 0.29), Vector3(0.085, 0.26, 0.04))
		g.box("alloy", Vector3((HALF_W + 0.27) * sx, top - 1.15, z0 + 0.335), Vector3(0.07, 0.23, 0.004))
		# head lamps in the bumper, the indicator outside them, a marker lamp on the roof's corner
		g.box("black", Vector3(0.88 * sx, 0.62, z0 - 0.045), Vector3(0.27, 0.10, 0.02))
		g.box("lamp", Vector3(0.84 * sx, 0.62, z0 - 0.062), Vector3(0.17, 0.075, 0.006))
		g.box("amber", Vector3(1.10 * sx, 0.62, z0 - 0.058), Vector3(0.06, 0.075, 0.008))
		g.box("amber", Vector3(0.95 * sx, top - 0.10, z0 + 0.30), Vector3(0.05, 0.02, 0.03))
		# the mudguard over the front wheel
		g.box("black", Vector3((HALF_W + 0.012) * sx, WHEEL_R + arch + 0.03, axle), Vector3(0.014, 0.03, 0.30))
		g.box("black", Vector3((HALF_W - 0.20) * sx, 0.70, axle + arch + 0.03), Vector3(0.20, 0.30, 0.012))            # the mud flap behind it
	# the grille: a dark panel with bars, the maker's badge, the bumper, the plate
	g.box("black", Vector3(0, 1.22, z0 - 0.012), Vector3(0.98, 0.42, 0.02))
	for k in 6:
		g.box("grey", Vector3(0, 0.90 + 0.13 * float(k), z0 - 0.036), Vector3(0.92, 0.014, 0.006))
	g.box("alloy", Vector3(0, 1.74, z0 - 0.036), Vector3(0.16, 0.05, 0.006))
	g.box("grey", Vector3(0, 0.58, z0 - 0.02), Vector3(HALF_W - 0.02, 0.20, 0.06))
	g.box("plate", Vector3(0, 0.50, z0 - 0.084), Vector3(0.26, 0.055, 0.004))
	if deflector:
		g.box("cab", Vector3(0, top + 0.30, z0 + 1.35), Vector3(1.12, 0.035, 0.95), Basis(Vector3.RIGHT, 0.36))
		for sgn2 in [-1.0, 1.0]:
			var s2: float = sgn2
			g.box("cab", Vector3(1.10 * s2, top + 0.20, z0 + 1.55), Vector3(0.03, 0.30, 0.60))


## The frame under the body, from behind the cab to the tail: the two rails, the fuel tank, the air tanks,
## side under-run rails, the bar and the lamps at the back, mudguards over the rear wheels.
static func _chassis(g, z0: float, z1: float, rear_axles: Array, tail_y := 0.95) -> void:
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("black", Vector3(0.42 * sx, 0.86, (z0 + z1) * 0.5), Vector3(0.05, 0.11, (z1 - z0) * 0.5))
		g.box("grey", Vector3((HALF_W - 0.03) * sx, 0.55, (z0 + z1) * 0.5 - 0.3), Vector3(0.02, 0.05, maxf((z1 - z0) * 0.5 - 1.5, 0.3)))
		for az in rear_axles:
			var zc: float = az
			g.box("black", Vector3((HALF_W - 0.29) * sx, 1.10, zc), Vector3(0.29, 0.03, 0.66))
			g.box("black", Vector3((HALF_W - 0.29) * sx, 0.72, zc + 0.68), Vector3(0.27, 0.34, 0.012))             # the mud flap
		g.box("black", Vector3(1.02 * sx, tail_y, z1 + 0.004), Vector3(0.20, 0.07, 0.02))
		g.box("red", Vector3(1.08 * sx, tail_y, z1 + 0.026), Vector3(0.09, 0.05, 0.006))
		g.box("amber", Vector3(0.92 * sx, tail_y, z1 + 0.026), Vector3(0.05, 0.05, 0.006))
	g.cyl("alloy", Vector3(-0.88, 0.70, z0 + 0.75), Vector3.BACK, 0.30, 0.55, 16)                                   # the fuel tank
	g.cyl("grey", Vector3(0.88, 0.74, z0 + 0.55), Vector3.BACK, 0.16, 0.40, 12)                                    # air tanks
	g.box("grey", Vector3(0.90, 0.62, z0 + 1.45), Vector3(0.26, 0.24, 0.30))                                       # the battery box
	g.box("grey", Vector3(0, 0.56, z1 - 0.04), Vector3(HALF_W - 0.05, 0.05, 0.04))                                 # the under-run bar
	g.box("plate", Vector3(0, 0.74, z1 + 0.012), Vector3(0.26, 0.055, 0.004))


static func _box_body(g, z0: float, z1: float, top: float, floor_y := 1.12) -> void:
	g.box("body", Vector3(0, (floor_y + top) * 0.5, (z0 + z1) * 0.5), Vector3(HALF_W, (top - floor_y) * 0.5, (z1 - z0) * 0.5))
	g.box("grey", Vector3(0, floor_y - 0.04, (z0 + z1) * 0.5), Vector3(HALF_W + 0.006, 0.05, (z1 - z0) * 0.5 + 0.006))   # the floor's edge
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("alloy", Vector3((HALF_W + 0.004) * sx, top - 0.03, (z0 + z1) * 0.5), Vector3(0.006, 0.03, (z1 - z0) * 0.5))       # the rail along the roof's edge
		g.box("alloy", Vector3((HALF_W - 0.03) * sx, (floor_y + top) * 0.5, z1 + 0.004), Vector3(0.03, (top - floor_y) * 0.5, 0.006))
		for k in int((z1 - z0) / 1.3):
			g.box("amber", Vector3((HALF_W + 0.006) * sx, floor_y - 0.04, z0 + 0.65 + 1.3 * float(k)), Vector3(0.006, 0.02, 0.04))  # side markers
		g.box("red", Vector3(1.05 * sx, top - 0.08, z1 + 0.006), Vector3(0.06, 0.025, 0.006))
	# the two doors at the back: the gap between them, the locking bars and their handles, the hinges
	g.box("black", Vector3(0, (floor_y + top) * 0.5, z1 + 0.004), Vector3(0.006, (top - floor_y) * 0.5 - 0.04, 0.004))
	for dx in [-0.62, -0.18, 0.18, 0.62]:
		var x: float = dx
		g.tube("steel", [Vector3(x, floor_y + 0.05, z1 + 0.02), Vector3(x, top - 0.06, z1 + 0.02)], 0.014, 6)
		g.box("steel", Vector3(x + 0.07 * signf(x), floor_y + 0.55, z1 + 0.03), Vector3(0.07, 0.014, 0.008))


static func _build(kind: String, cab: Color, body: Color) -> ArrayMesh:
	var g = Shapes.Geo.new()
	var spec: Dictionary = KINDS[kind]
	var hl: float = float(spec["len"]) * 0.5
	var axles: Array = spec["axles"]
	match kind:
		"box":
			_cab(g, -hl, 2.95, true, float(axles[0]))
			_chassis(g, -hl + CAB_LEN, hl, [axles[1]])
			_box_body(g, -hl + CAB_LEN + 0.18, hl, 3.70)
			# a fridge unit on the front of the box, over the cab
			g.box("grey", Vector3(0, 3.20, -hl + CAB_LEN + 0.06), Vector3(0.85, 0.32, 0.12))
		"tipper":
			_cab(g, -hl, 2.90, false, float(axles[0]))
			_chassis(g, -hl + CAB_LEN, hl, [axles[1]])
			var z0 := -hl + CAB_LEN + 0.30
			# the open body: a floor, two sides with ribs, a tall headboard that reaches over the cab, a tailgate
			g.box("body", Vector3(0, 1.20, (z0 + hl) * 0.5), Vector3(HALF_W, 0.06, (hl - z0) * 0.5))
			for sgn in [-1.0, 1.0]:
				var sx: float = sgn
				g.box("body", Vector3((HALF_W - 0.04) * sx, 1.75, (z0 + hl) * 0.5), Vector3(0.04, 0.55, (hl - z0) * 0.5))
				for k in 5:
					g.box("body", Vector3((HALF_W + 0.02) * sx, 1.75, z0 + 0.35 + (hl - z0 - 0.7) * float(k) / 4.0), Vector3(0.03, 0.55, 0.05))
				g.box("body", Vector3((HALF_W + 0.01) * sx, 2.27, (z0 + hl) * 0.5), Vector3(0.06, 0.04, (hl - z0) * 0.5))
			g.box("body", Vector3(0, 1.95, z0 + 0.04), Vector3(HALF_W, 0.80, 0.04))
			g.box("body", Vector3(0, 2.78, z0 - 0.45), Vector3(HALF_W - 0.1, 0.04, 0.50))
			g.box("body", Vector3(0, 1.72, hl - 0.04), Vector3(HALF_W - 0.08, 0.50, 0.035))
			# a load of gravel lying in it
			g.ball("grey", Vector3(0, 1.85, (z0 + hl) * 0.5 + 0.2), Vector3(HALF_W - 0.15, 0.50, (hl - z0) * 0.5 - 0.35), 12, 5)
			g.tube("steel", [Vector3(0, 0.95, z0 + 0.25), Vector3(0, 1.20, z0 + 0.45)], 0.07, 8)                    # the ram
		"tank":
			_cab(g, -hl, 2.90, false, float(axles[0]))
			_chassis(g, -hl + CAB_LEN, hl, [axles[1]])
			var zt0 := -hl + CAB_LEN + 0.35
			var zm := (zt0 + hl - 0.25) * 0.5
			var half := (hl - 0.25 - zt0) * 0.5
			g.cyl("body", Vector3(0, 2.05, zm), Vector3.BACK, 1.02, half - 0.18, 28)
			g.ball("body", Vector3(0, 2.05, zm - half + 0.18), Vector3(1.02, 1.02, 0.20), 20, 6)
			g.ball("body", Vector3(0, 2.05, zm + half - 0.18), Vector3(1.02, 1.02, 0.20), 20, 6)
			for k in 3:
				g.cyl("steel", Vector3(0, 3.08, zm - half * 0.6 + half * 0.6 * float(k)), Vector3.UP, 0.26, 0.05, 14)   # the lids on top
				g.box("grey", Vector3(0, 1.05, zm - half * 0.6 + half * 0.6 * float(k)), Vector3(0.95, 0.10, 0.10))      # the cradles
			g.box("steel", Vector3(0, 3.06, zm), Vector3(0.30, 0.012, half - 0.2))                                   # the walkway
			g.box("cab", Vector3(0, 2.05, zm), Vector3(1.03, 0.10, half * 0.7))                                      # a band in the company's colour
			g.tube("steel", [Vector3(0.80, 1.0, hl - 0.15), Vector3(0.80, 3.05, hl - 0.15)], 0.02, 6)                # the ladder at the back
			g.tube("steel", [Vector3(0.50, 1.0, hl - 0.15), Vector3(0.50, 3.05, hl - 0.15)], 0.02, 6)
			for k in 6:
				g.box("steel", Vector3(0.65, 1.2 + 0.33 * float(k), hl - 0.15), Vector3(0.15, 0.015, 0.015))
		"semi":
			# the tractor: the cab, a short frame with the fifth wheel over its driven axle
			_cab(g, -hl, 3.05, true, float(axles[0]))
			var zt := -hl + CAB_LEN
			g.box("cab", Vector3(0, 2.0, zt + 0.10), Vector3(HALF_W - 0.02, 1.05, 0.10))                              # the back of the sleeper cab
			_chassis(g, zt, zt + 3.4, [axles[1]], 0.90)
			g.cyl("grey", Vector3(0, 1.02, float(axles[1]) - 0.1), Vector3.UP, 0.45, 0.04, 18)
			# the trailer: a box on its own frame, landing legs, three axles, the under-run rails
			var z0t := zt + 0.75
			_box_body(g, z0t, hl, 4.0, 1.25)
			for sgn in [-1.0, 1.0]:
				var sx2: float = sgn
				g.box("black", Vector3(0.45 * sx2, 1.08, (z0t + hl) * 0.5 + 1.5), Vector3(0.05, 0.10, (hl - z0t) * 0.5 - 1.5))
				g.box("steel", Vector3(0.80 * sx2, 0.62, z0t + 3.2), Vector3(0.05, 0.52, 0.05))                       # a landing leg
				g.box("steel", Vector3(0.80 * sx2, 0.10, z0t + 3.2), Vector3(0.12, 0.02, 0.12))
				g.box("grey", Vector3((HALF_W - 0.03) * sx2, 0.60, 1.4), Vector3(0.02, 0.05, 2.4))                    # the side rail
				g.box("grey", Vector3((HALF_W - 0.03) * sx2, 0.85, 1.4), Vector3(0.02, 0.05, 2.4))
				for k in 3:
					g.box("black", Vector3((HALF_W - 0.29) * sx2, 1.12, float(axles[2 + k])), Vector3(0.29, 0.03, 0.60))
				g.box("black", Vector3(1.02 * sx2, 0.95, hl + 0.004), Vector3(0.20, 0.07, 0.02))
				g.box("red", Vector3(1.08 * sx2, 0.95, hl + 0.026), Vector3(0.09, 0.05, 0.006))
				g.box("amber", Vector3(0.92 * sx2, 0.95, hl + 0.026), Vector3(0.05, 0.05, 0.006))
			g.box("grey", Vector3(0, 0.56, hl - 0.04), Vector3(HALF_W - 0.05, 0.05, 0.04))
			g.box("plate", Vector3(0, 0.74, hl + 0.012), Vector3(0.26, 0.055, 0.004))
	return g.commit(_mats(cab, body))


## A wheel, its axle along Y (the traffic lays it over on its side): a truck tyre, a deep steel rim, the hub and its ten nuts.
static func wheel_mesh() -> ArrayMesh:
	if _wheel == null:
		var w = Shapes.Geo.new()
		w.lathe("rubber", Vector3.ZERO, Vector3.UP, [Vector2(0.29, -0.13), Vector2(0.43, -0.15), Vector2(0.50, -0.135), Vector2(WHEEL_R, -0.10), Vector2(WHEEL_R, 0.10),
			Vector2(0.50, 0.135), Vector2(0.43, 0.15), Vector2(0.29, 0.13)], 32)
		w.lathe("alloy", Vector3.ZERO, Vector3.UP, [Vector2(0.0, 0.03), Vector2(0.13, 0.03), Vector2(0.16, 0.10), Vector2(0.29, 0.13), Vector2(0.29, -0.13), Vector2(0.16, -0.10),
			Vector2(0.13, -0.03), Vector2(0.0, -0.03)], 24)
		for side in [-1.0, 1.0]:
			var sy: float = side
			w.cyl("grey", Vector3(0, 0.07 * sy, 0), Vector3.UP, 0.08, 0.04, 14)
			for k in 10:
				var a := TAU * float(k) / 10.0
				w.cyl("alloy", Vector3(sin(a) * 0.11, 0.05 * sy, cos(a) * 0.11), Vector3.UP, 0.014, 0.02, 6)
		_wheel = w.commit(_mats(Color.WHITE, Color.WHITE))
	return _wheel


## The body of one kind in one of its colours (built once, then kept).
static func body_mesh(kind: String, paint: int) -> ArrayMesh:
	var key := "%s:%d" % [kind, paint]
	if not _cache.has(key):
		var paints: Array = KINDS[kind]["paints"]
		var p: Array = paints[posmod(paint, paints.size())]
		_cache[key] = _build(kind, p[0], p[1])
	return _cache[key]


## What the traffic needs to drive a two-axle lorry as it drives a car (scripts/traffic.gd, _models).
static func traffic_model(kind: String, paint: int) -> Dictionary:
	var axles: Array = KINDS[kind]["axles"]
	return {"name": "lorry " + kind, "body": body_mesh(kind, paint), "wheel": wheel_mesh(), "track": HALF_W - 0.17, "wheel_r": WHEEL_R,
		"axle_f": float(axles[0]), "axle_r": float(axles[1]), "wb": float(axles[1]) - float(axles[0]), "paints": [Color.WHITE], "long": true}


## A lorry standing still: its body, all its wheels (two a side on every axle but the first), and a box to walk into.
static func make(kind: String, paint: int) -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = body_mesh(kind, paint)
	root.add_child(body)
	var axles: Array = KINDS[kind]["axles"]
	for k in axles.size():
		for sgn in [-1.0, 1.0]:
			var sx: float = sgn
			for twin in (1 if k == 0 else 2):
				var mi := MeshInstance3D.new()
				mi.mesh = wheel_mesh()
				mi.rotation.z = PI * 0.5
				mi.position = Vector3((HALF_W - 0.17 - 0.33 * float(twin)) * sx, WHEEL_R, float(axles[k]))
				root.add_child(mi)
	var solid := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var bx := BoxShape3D.new()
	var top := 4.0 if kind == "semi" else 3.5
	bx.size = Vector3(HALF_W * 2.0, top - 0.3, float(KINDS[kind]["len"]))
	shape.shape = bx
	shape.position = Vector3(0, 0.3 + (top - 0.3) * 0.5, 0)
	solid.add_child(shape)
	root.add_child(solid)
	return root
