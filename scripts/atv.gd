extends Node3D
## A quad bike. Parked, it is a solid object in the world; the player gets on with F and then
## carries it along (scripts/player.gd does the driving). Faces -Z.
##
## Suspension: each wheel rides up and down on its own to follow the ground under it, and the
## body sits on springs — it squats under throttle, dives under braking, leans out of corners
## and bounces after bumps and landings.

const LABEL := "the ATV"
const SPECS := {"speed": 25.0, "fast": 38.0, "reverse": 8.0, "power": 17.0, "brake": 30.0, "reach": 3.2,
	"drift": false, "hides_rider": false, "exit": 1.3, "camera": 0.0}
const WHEEL_R := 0.30
const TRAVEL_UP := 0.14
const TRAVEL_DOWN := 0.11
const GRIP := Vector3(0.36, 0.20, 0.04)        # on the handlebar, in the bars' own space
const FOOT := Vector3(0.42, 0.44, -0.05)

var _chassis: Node3D
var _bars: Node3D
var _col: CollisionShape3D
var _body_mesh: ArrayMesh
var _wheels: Array = []          # [hub, tyre, is_front, rest position, arm strut, shock strut, arm mount, shock mount]
var _spin := 0.0
var _offsets := [0.0, 0.0, 0.0, 0.0]

# the sprung body: displacement and speed of heave (m), pitch and roll (rad)
var _heave := 0.0
var _heave_v := 0.0
var _pitch := 0.0
var _pitch_v := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _last_speed := 0.0
var _last_yaw := 0.0
var _last_y := 0.0
var _last_vy := 0.0
var _fresh := true


const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo): smooth skins, tubes, balls

var _mats := {}


func _ready() -> void:
	_mats = {
		"red": _mat(Color(0.62, 0.09, 0.07), 0.45), "black": _mat(Color(0.06, 0.06, 0.065), 0.7), "grey": _mat(Color(0.32, 0.33, 0.35), 0.5),
		"steel": _mat(Color(0.55, 0.56, 0.58), 0.35), "rubber": _mat(Color(0.04, 0.04, 0.04), 1.0), "seat": _mat(Color(0.08, 0.08, 0.085), 0.95),
		"lamp": _mat(Color(0.95, 0.93, 0.80), 0.3), "tail": _mat(Color(0.7, 0.05, 0.04), 0.4), "alloy": _mat(Color(0.70, 0.71, 0.73), 0.3),
		"spring": _mat(Color(0.85, 0.65, 0.08), 0.5),
	}
	for key in ["steel", "alloy"]:
		_mats[key].metallic = 0.8
	_mats["red"].cull_mode = BaseMaterial3D.CULL_DISABLED            # the mudguards are thin shells, seen from both sides
	_mats["lamp"].emission_enabled = true
	_mats["lamp"].emission = Color(0.95, 0.93, 0.80)
	_mats["lamp"].emission_energy_multiplier = 0.5
	_chassis = Node3D.new()
	add_child(_chassis)
	var g = Shapes.Geo.new()
	_build_frame(g)
	_build_plastics(g)
	var body := MeshInstance3D.new()
	body.mesh = g.commit(_mats)
	_body_mesh = body.mesh
	_chassis.add_child(body)

	# the handlebars, which turn: the bar itself, grips, levers, the pod with the speedometer, the steering column
	_bars = Node3D.new()
	_bars.position = Vector3(0, 0.92, -0.55)
	_chassis.add_child(_bars)
	var b = Shapes.Geo.new()
	b.tube("steel", [Vector3(-0.30, 0.20, 0.05), Vector3(-0.20, 0.205, 0.03), Vector3(-0.09, 0.16, 0.01), Vector3(0.09, 0.16, 0.01), Vector3(0.20, 0.205, 0.03), Vector3(0.30, 0.20, 0.05)], 0.013, 10)
	b.tube("black", [Vector3(0, -0.14, 0.05), Vector3(0, 0.16, 0.01)], 0.022, 10)
	b.box("black", Vector3(0, 0.165, 0.0), Vector3(0.07, 0.02, 0.035))
	b.ball("black", Vector3(0, 0.215, -0.03), Vector3(0.075, 0.045, 0.06), 12, 6)                    # the pod
	b.cyl("lamp", Vector3(0, 0.243, -0.015), Vector3(0, 0.9, 0.4).normalized(), 0.04, 0.004, 14)
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		b.tube("rubber", [Vector3(0.29 * sx, 0.20, 0.048), Vector3(0.43 * sx, 0.20, 0.052)], 0.021, 10)             # grips
		for k in 5:
			b.cyl("rubber", Vector3((0.31 + 0.025 * float(k)) * sx, 0.20, 0.049), Vector3.RIGHT, 0.0235, 0.004, 10)
		b.tube("steel", [Vector3(0.27 * sx, 0.205, 0.02), Vector3(0.30 * sx, 0.21, -0.03), Vector3(0.42 * sx, 0.205, -0.035)], 0.006, 6)   # brake levers
		b.box("black", Vector3(0.265 * sx, 0.205, 0.035), Vector3(0.022, 0.018, 0.025))
	var bars_mi := MeshInstance3D.new()
	bars_mi.mesh = b.commit(_mats)
	_bars.add_child(bars_mi)

	# wheels: fat low-pressure tyres with lugs, on dished rims; each hangs on an arm and a coil-sprung shock
	var w = Shapes.Geo.new()
	_build_wheel(w)
	var wheel_mats := {}                                # a tyre is a shell: both sides of it are drawn, so it is never seen through
	for key in _mats:
		wheel_mats[key] = _mats[key]
		if _mats[key] is StandardMaterial3D:
			wheel_mats[key] = _mats[key].duplicate()
			wheel_mats[key].cull_mode = BaseMaterial3D.CULL_DISABLED
	var wheel_mesh: ArrayMesh = w.commit(wheel_mats)
	var arm_g = Shapes.Geo.new()
	arm_g.tube("black", [Vector3(0, -0.5, -0.05), Vector3(0, 0.5, -0.10)], 0.016, 8)
	arm_g.tube("black", [Vector3(0, -0.5, 0.05), Vector3(0, 0.5, 0.10)], 0.016, 8)
	arm_g.tube("black", [Vector3(0, 0.1, -0.085), Vector3(0, 0.1, 0.085)], 0.012, 6)
	var arm_mesh: ArrayMesh = arm_g.commit(_mats)
	var shock_g = Shapes.Geo.new()
	shock_g.tube("steel", [Vector3(0, -0.5, 0), Vector3(0, 0.5, 0)], 0.014, 8)
	shock_g.tube("black", [Vector3(0, 0.05, 0), Vector3(0, 0.5, 0)], 0.026, 10)
	var coil := []
	for k in 73:                                                    # the spring, six turns round the damper
		var a := TAU * float(k) / 12.0
		coil.append(Vector3(cos(a) * 0.042, -0.42 + 0.80 * float(k) / 72.0, sin(a) * 0.042))
	shock_g.tube("spring", coil, 0.008, 5)
	var shock_mesh: ArrayMesh = shock_g.commit(_mats)
	for front in [true, false]:
		for sx2 in [-0.47, 0.47]:
			var z := -0.62 if front else 0.62
			var hub := Node3D.new()
			hub.position = Vector3(sx2, WHEEL_R, z)
			add_child(hub)
			var mi := MeshInstance3D.new()
			mi.mesh = wheel_mesh
			mi.rotation.z = PI * 0.5
			hub.add_child(mi)
			var arm := MeshInstance3D.new()
			arm.mesh = arm_mesh
			add_child(arm)
			var shock := MeshInstance3D.new()
			shock.mesh = shock_mesh
			add_child(shock)
			var inward := -signf(sx2)
			_wheels.append([hub, mi, front, hub.position, arm, shock,
				Vector3(sx2 + inward * 0.27, 0.40, z), Vector3(sx2 + inward * 0.20, 0.74, z)])

	_col = CollisionShape3D.new()
	_col.shape = hull_shape()
	var sbody := StaticBody3D.new()
	sbody.add_child(_col)
	add_child(sbody)
	_place_parts()


## The frame, engine and exhaust, racks, bumper and footrests: the metal of it.
func _build_frame(g) -> void:
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		# the frame: a lower rail and an upper rail each side, joined front and back
		g.tube("black", [Vector3(0.17 * sx, 0.52, -0.86), Vector3(0.19 * sx, 0.30, -0.62), Vector3(0.21 * sx, 0.27, 0.0), Vector3(0.20 * sx, 0.30, 0.62), Vector3(0.17 * sx, 0.55, 0.88)], 0.022, 8)
		g.tube("black", [Vector3(0.17 * sx, 0.52, -0.86), Vector3(0.15 * sx, 0.70, -0.55), Vector3(0.14 * sx, 0.72, 0.20), Vector3(0.17 * sx, 0.70, 0.75), Vector3(0.17 * sx, 0.55, 0.88)], 0.020, 8)
		g.tube("black", [Vector3(0.21 * sx, 0.27, 0.0), Vector3(0.14 * sx, 0.72, 0.20)], 0.016, 6)
		# footrests: a plate with raised ribs, on two stays
		g.box("grey", Vector3(0.42 * sx, 0.345, -0.05), Vector3(0.10, 0.012, 0.15))
		for k in 6:
			g.box("black", Vector3(0.42 * sx, 0.362, -0.17 + 0.048 * float(k)), Vector3(0.095, 0.006, 0.008))
		g.tube("black", [Vector3(0.21 * sx, 0.28, -0.15), Vector3(0.50 * sx, 0.335, -0.17)], 0.012, 6)
		g.tube("black", [Vector3(0.21 * sx, 0.28, 0.08), Vector3(0.50 * sx, 0.335, 0.08)], 0.012, 6)
		g.tube("black", [Vector3(0.52 * sx, 0.34, -0.19), Vector3(0.52 * sx, 0.34, 0.10)], 0.012, 6)
		# racks front and rear: a hoop of tube with bars across it
		for q in [[-1.07, -0.66, 0.35], [0.64, 1.10, 0.37]]:
			g.tube("grey", [Vector3(float(q[2]) * sx, 0.875, q[0]), Vector3(float(q[2]) * sx, 0.875, q[1])], 0.011, 6)
			g.tube("grey", [Vector3(0.20 * sx, 0.875, (float(q[0]) + float(q[1])) * 0.5), Vector3(0.20 * sx, 0.79, (float(q[0]) + float(q[1])) * 0.5)], 0.010, 6)
	for q in [[-1.07, -0.66, 0.35], [0.64, 1.10, 0.37]]:
		for k in 5:
			var z := lerpf(q[0], q[1], float(k) / 4.0)
			g.tube("grey", [Vector3(-float(q[2]), 0.875, z), Vector3(q[2], 0.875, z)], 0.011 if k == 0 or k == 4 else 0.008, 6)
	# the front bumper: a hoop of tube standing out ahead of the nose
	g.tube("black", [Vector3(-0.17, 0.52, -0.86), Vector3(-0.26, 0.50, -1.06), Vector3(-0.22, 0.70, -1.13), Vector3(0.22, 0.70, -1.13), Vector3(0.26, 0.50, -1.06), Vector3(0.17, 0.52, -0.86)], 0.018, 8)
	g.tube("black", [Vector3(-0.26, 0.50, -1.06), Vector3(0.26, 0.50, -1.06)], 0.014, 6)
	g.box("grey", Vector3(0, 0.25, -0.2), Vector3(0.19, 0.008, 0.62))                               # skid plate
	# the engine: crankcase, a finned cylinder leaning forward, the airbox; the exhaust round to a silencer at the back
	g.box("grey", Vector3(0, 0.42, 0.05), Vector3(0.15, 0.12, 0.24))
	g.cyl("grey", Vector3(-0.155, 0.42, 0.10), Vector3.RIGHT, 0.10, 0.012, 16)
	g.cyl("grey", Vector3(0.155, 0.42, 0.10), Vector3.RIGHT, 0.10, 0.012, 16)
	var lean := Basis(Vector3.RIGHT, -0.35)
	g.box("black", Vector3(0, 0.60, -0.08), Vector3(0.075, 0.10, 0.075), lean)
	for k in 7:
		g.box("grey", Vector3(0, 0.60, -0.08) + lean.y * (-0.085 + 0.028 * float(k)), Vector3(0.105, 0.004, 0.105), lean)
	g.box("black", Vector3(0, 0.62, 0.33), Vector3(0.11, 0.07, 0.12))
	g.tube("steel", [Vector3(0.05, 0.63, -0.17), Vector3(0.16, 0.56, -0.24), Vector3(0.24, 0.46, -0.10), Vector3(0.26, 0.45, 0.30), Vector3(0.27, 0.56, 0.62), Vector3(0.27, 0.60, 0.74)], 0.022, 10)
	g.lathe("steel", Vector3(0.27, 0.61, 0.74), Vector3(0, 0.12, 0.99).normalized(), [Vector2(0.0, -0.01), Vector2(0.045, -0.01), Vector2(0.058, 0.02), Vector2(0.058, 0.30), Vector2(0.045, 0.33),
		Vector2(0.02, 0.335), Vector2(0.02, 0.37), Vector2(0.012, 0.37), Vector2(0.012, 0.33), Vector2(0.0, 0.33)], 16)
	# drive shafts to the rear wheels
	g.tube("steel", [Vector3(-0.40, 0.31, 0.62), Vector3(0.40, 0.31, 0.62)], 0.018, 8)
	g.box("grey", Vector3(0, 0.33, 0.62), Vector3(0.07, 0.07, 0.09))


## The plastics: the mudguards over each wheel, the nose with its lamps, the tank cover, the seat, the tail.
func _build_plastics(g) -> void:
	for front in [true, false]:
		for sgn in [-1.0, 1.0]:
			var sx: float = sgn
			var zc := -0.62 if front else 0.62
			var rows := []
			for i in 17:
				# an arc over the wheel, from in front of it to behind it; wider and lower toward the outside
				var a := deg_to_rad(lerpf(-78.0, 78.0, float(i) / 16.0)) * (1.0 if front else -1.0)
				var row := PackedVector3Array()
				for q in [[0.16, 0.50, 0.0], [0.28, 0.50, 0.0], [0.42, 0.495, 0.0], [0.56, 0.47, 0.0], [0.64, 0.42, 0.01], [0.655, 0.37, 0.03]]:
					var r: float = q[1]
					row.append(Vector3(float(q[0]) * sx, 0.30 + cos(a) * r - 0.02, zc - sin(a) * (r + float(q[2]))))
				rows.append(row)
			g.skin(rows, false, "red")
	# the nose between the front mudguards, with two lamps in it
	var nose := []
	for q in [[-1.02, 0.10, 0.05, 0.70], [-0.98, 0.17, 0.085, 0.71], [-0.86, 0.20, 0.10, 0.73], [-0.70, 0.21, 0.10, 0.76], [-0.60, 0.20, 0.09, 0.78]]:
		var ring := PackedVector3Array()
		for k in 14:
			var a := TAU * float(k) / 14.0
			ring.append(Vector3(cos(a) * float(q[1]), float(q[3]) + sin(a) * float(q[2]), q[0]))
		nose.append(ring)
	g.skin(nose, true, "red")
	g.cap("red", nose[0], Vector3.FORWARD)
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		g.cyl("black", Vector3(0.085 * sx2, 0.705, -1.022), Vector3.BACK, 0.052, 0.006, 16)
		g.lathe("lamp", Vector3(0.085 * sx2, 0.705, -1.026), Vector3.FORWARD, [Vector2(0.045, 0.0), Vector2(0.035, 0.008), Vector2(0.0, 0.012)], 16)
	# the tank cover: rounded, rising to the filler cap, narrowing to the seat
	var tank := []
	for q in [[-0.62, 0.17, 0.07, 0.80], [-0.55, 0.22, 0.11, 0.81], [-0.40, 0.235, 0.135, 0.82], [-0.22, 0.225, 0.13, 0.82], [-0.08, 0.20, 0.10, 0.81], [-0.02, 0.17, 0.07, 0.80]]:
		var ring2 := PackedVector3Array()
		for k in 16:
			var a2 := TAU * float(k) / 16.0
			ring2.append(Vector3(cos(a2) * float(q[1]), float(q[3]) + sin(a2) * float(q[2]) * (1.0 if sin(a2) > 0.0 else 0.6), q[0]))
		tank.append(ring2)
	g.skin(tank, true, "red")
	g.cap("red", tank[0], Vector3.FORWARD)
	g.cap("red", tank[-1], Vector3.BACK)
	g.cyl("black", Vector3(0, 0.955, -0.36), Vector3.UP, 0.04, 0.012, 14)
	# the seat: long, rounded on top, stepped up a little at the back
	var seat := []
	for q in [[-0.06, 0.15, 0.04, 0.84], [0.0, 0.19, 0.07, 0.845], [0.25, 0.215, 0.075, 0.85], [0.50, 0.225, 0.08, 0.86], [0.66, 0.21, 0.085, 0.875], [0.73, 0.15, 0.06, 0.875]]:
		var ring3 := PackedVector3Array()
		for k in 16:
			var a3 := TAU * float(k) / 16.0
			ring3.append(Vector3(cos(a3) * float(q[1]), float(q[3]) + sin(a3) * float(q[2]) * (1.0 if sin(a3) > 0.0 else 0.55), q[0]))
		seat.append(ring3)
	g.skin(seat, true, "seat")
	g.cap("seat", seat[0], Vector3.FORWARD)
	g.cap("seat", seat[-1], Vector3.BACK)
	# the tail between the rear mudguards, the tail lamp and the plate
	g.box("red", Vector3(0, 0.76, 0.86), Vector3(0.17, 0.035, 0.20))
	g.box("tail", Vector3(0, 0.74, 1.065), Vector3(0.07, 0.022, 0.008))
	g.box("alloy", Vector3(0, 0.66, 1.07), Vector3(0.09, 0.05, 0.004))
	# side panels under the seat
	for sgn in [-1.0, 1.0]:
		var sx3: float = sgn
		g.box("black", Vector3(0.20 * sx3, 0.66, 0.30), Vector3(0.012, 0.10, 0.26))
		g.box("red", Vector3(0.215 * sx3, 0.70, -0.30), Vector3(0.012, 0.07, 0.22), Basis(Vector3.BACK, 0.2 * sx3))


## A wheel, turning about the Y axis of its own frame: a fat tyre with rows of lugs, a dished rim, hub and nuts.
func _build_wheel(g) -> void:
	var segs := 40
	g.lathe("rubber", Vector3.ZERO, Vector3.UP, [Vector2(0.150, -0.105), Vector2(0.165, -0.122), Vector2(0.195, -0.131), Vector2(0.230, -0.133), Vector2(0.262, -0.122),
		Vector2(0.284, -0.100), Vector2(0.295, -0.065), Vector2(0.298, -0.022), Vector2(0.298, 0.022), Vector2(0.295, 0.065), Vector2(0.284, 0.100), Vector2(0.262, 0.122),
		Vector2(0.230, 0.133), Vector2(0.195, 0.131), Vector2(0.165, 0.122), Vector2(0.150, 0.105)], segs)
	for k in 24:                                                    # lugs: slanted bars in two rows, staggered
		for sgn in [-1.0, 1.0]:
			var sy: float = sgn
			var a := TAU * (float(k) + (0.0 if sy > 0.0 else 0.5)) / 24.0
			var out := Vector3(cos(a), 0, sin(a))
			var along := Vector3(-sin(a), 0, cos(a))
			var bs := Basis(along, Vector3.UP, out) * Basis(Vector3.BACK, 0.5 * sy)
			g.box("rubber", out * 0.296 + Vector3(0, 0.055 * sy, 0), Vector3(0.018, 0.05, 0.012), bs)
			g.box("rubber", out.rotated(Vector3.UP, 0.06) * 0.280 + Vector3(0, 0.112 * sy, 0), Vector3(0.016, 0.022, 0.012), Basis(along, Vector3.UP, out) * Basis(Vector3.RIGHT, -0.7 * sy))
	g.lathe("alloy", Vector3.ZERO, Vector3.UP, [Vector2(0.148, -0.108), Vector2(0.158, -0.100), Vector2(0.150, -0.085), Vector2(0.135, -0.075), Vector2(0.128, 0.0),
		Vector2(0.135, 0.075), Vector2(0.150, 0.085), Vector2(0.158, 0.100), Vector2(0.148, 0.108)], 32)
	for face in [-1.0, 1.0]:
		var fy: float = face
		g.lathe("alloy", Vector3(0, 0.07 * fy, 0), Vector3(0, fy, 0), [Vector2(0.132, 0.0), Vector2(0.10, -0.022), Vector2(0.055, -0.030), Vector2(0.045, -0.012), Vector2(0.0, -0.010)], 28)   # the dished face
		g.cyl("grey", Vector3(0, 0.062 * fy, 0), Vector3.UP, 0.035, 0.008, 14)
		for k in 4:
			var a2 := TAU * float(k) / 4.0 + 0.4
			g.cyl("steel", Vector3(cos(a2) * 0.065, 0.045 * fy, sin(a2) * 0.065), Vector3.UP, 0.009, 0.007, 8)
			g.cyl("black", Vector3(cos(a2 + 0.78) * 0.09, 0.048 * fy, sin(a2 + 0.78) * 0.09), Vector3.UP, 0.016, 0.002, 10)     # the holes in the dish
func _mat(color: Color, rough: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	mesh.material = _mat(color, 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)


func specs() -> Dictionary:
	return SPECS


## Where the tyres stand on the ground, in the ATV's own frame.
func wheel_points() -> Array:
	var out := []
	for w in _wheels:
		out.append(Vector3(w[3].x, 0, w[3].z))
	return out


## The shape of the body, for bumping into: the hull of what is drawn. With `floor` set, nothing of it reaches
## lower than that (the wheels carry a driven vehicle; its body must clear kerbs and bumps).
func hull_shape(floor := -1.0) -> ConvexPolygonShape3D:
	var shape: ConvexPolygonShape3D = _body_mesh.create_convex_shape(true, true)
	if floor > 0.0:
		var pts := shape.points
		for i in pts.size():
			pts[i].y = maxf(pts[i].y, floor)
		shape.points = pts
	return shape


func set_drift(_on: bool, _slip: float, _speed: float) -> void:
	pass
## Solid when parked; no collider of its own while someone is riding it.
func set_parked(parked: bool) -> void:
	_col.disabled = not parked


## Settle everything back to rest (after getting off).
func park() -> void:
	_heave = 0.0; _heave_v = 0.0
	_pitch = 0.0; _pitch_v = 0.0
	_roll = 0.0; _roll_v = 0.0
	_offsets = [0.0, 0.0, 0.0, 0.0]
	_bars.rotation.y = 0.0
	_fresh = true
	_place_parts()


## Where the body is right now, in the ATV's own space (the rider sits on this).
func chassis_xf() -> Transform3D:
	return _chassis.transform


## A handlebar grip (side -1 left, +1 right) and a footrest, in the ATV's own space.
func grip(side: float) -> Vector3:
	return _chassis.transform * (_bars.transform * Vector3(GRIP.x * side, GRIP.y, GRIP.z))


func foot(side: float) -> Vector3:
	return _chassis.transform * Vector3(FOOT.x * side, FOOT.y, FOOT.z)


func animate(speed: float, steer: float, delta: float, exclude: Array = []) -> void:
	delta = maxf(delta, 0.001)
	_spin -= speed * delta / WHEEL_R
	_bars.rotation.y = lerpf(_bars.rotation.y, steer * 0.45, minf(1.0, 10.0 * delta))

	# what the body feels: speeding up or braking, cornering, and the ground coming up at it
	var yaw := global_rotation.y
	var y := global_position.y
	if _fresh:
		_last_speed = speed
		_last_yaw = yaw
		_last_y = y
		_last_vy = 0.0
		_fresh = false
	var accel := clampf((speed - _last_speed) / delta, -25.0, 25.0)
	var yaw_rate := angle_difference(_last_yaw, yaw) / delta
	var lateral := clampf(speed * yaw_rate, -14.0, 14.0)
	var vy := (y - _last_y) / delta
	var bump := clampf((vy - _last_vy) / delta, -60.0, 60.0)
	_last_speed = speed
	_last_yaw = yaw
	_last_y = y
	_last_vy = vy

	# springs and dampers
	_heave_v += (-150.0 * _heave - 9.0 * _heave_v - bump * 0.55) * delta
	_heave = clampf(_heave + _heave_v * delta, -0.11, 0.10)
	_pitch_v += (-110.0 * (_pitch - accel * 0.011) - 9.0 * _pitch_v) * delta
	_pitch = clampf(_pitch + _pitch_v * delta, -0.16, 0.16)
	_roll_v += (-110.0 * (_roll + lateral * 0.012) - 9.0 * _roll_v) * delta
	_roll = clampf(_roll + _roll_v * delta, -0.17, 0.17)

	# each wheel finds the ground under it
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	var gx := global_transform
	for i in _wheels.size():
		var rest: Vector3 = _wheels[i][3]
		var target := 0.0
		if space != null:
			var from := gx * (rest + Vector3(0, 0.45, 0))
			var to := gx * (rest - Vector3(0, WHEEL_R + TRAVEL_DOWN + 0.05, 0))
			var q := PhysicsRayQueryParameters3D.create(from, to)
			q.exclude = exclude
			var hit := space.intersect_ray(q)
			if hit.is_empty():
				target = -TRAVEL_DOWN                        # hanging in the air
			else:
				var local: Vector3 = gx.affine_inverse() * hit["position"]
				target = clampf(local.y, -TRAVEL_DOWN, TRAVEL_UP)
		_offsets[i] = lerpf(_offsets[i], target, minf(1.0, 22.0 * delta))
	_place_parts()


func _place_parts() -> void:
	_chassis.transform = Transform3D(Basis.from_euler(Vector3(_pitch, 0.0, _roll)), Vector3(0.0, _heave, 0.0))
	for i in _wheels.size():
		var w: Array = _wheels[i]
		var hub: Node3D = w[0]
		var mi: MeshInstance3D = w[1]
		var rest: Vector3 = w[3]
		hub.position = rest + Vector3(0, _offsets[i], 0)
		hub.rotation.y = _bars.rotation.y if w[2] else 0.0
		mi.rotation.x = _spin
		var inner := hub.position - Vector3(signf(rest.x) * 0.14, 0, 0)
		_strut(w[4], _chassis.transform * w[6], inner)
		_strut(w[5], _chassis.transform * w[7], inner + Vector3(0, 0.04, 0))


## Stretch a 1 m long part (along its Y) between two points.
func _strut(mi: MeshInstance3D, a: Vector3, b: Vector3) -> void:
	var d := b - a
	var length := d.length()
	if length < 0.001:
		return
	var y := d / length
	var x := y.cross(Vector3.BACK)
	if x.length_squared() < 1e-6:
		x = Vector3.RIGHT
	x = x.normalized()
	mi.transform = Transform3D(Basis(x, y * length, x.cross(y)), (a + b) * 0.5)
