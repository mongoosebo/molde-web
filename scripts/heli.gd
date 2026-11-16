extends Node3D
## A Bell 206 JetRanger: the egg-shaped cabin with its big bulged windscreen, chin windows by the pilots' feet,
## two doors a side and windows in the roof; the engine under a cowling on top behind the mast, its exhaust
## standing out of it; a long slim tail boom with a stabiliser half way along and a swept fin and tail rotor at
## the end; two skids on arched cross tubes; a two-bladed main rotor. Parked, it is a solid object; the player
## gets in with F and flies it (scripts/player.gd, _fly), and is seen through the glass in the right-hand seat.
## Faces -Z.
##
## It is flown by physics: the rotor has to spin up before it will lift, the machine has weight and momentum,
## it leans the way it is pushed and speeds up that way, the air holds it back, and it comes down if the lift
## is taken off. The mouse turns it, Space lifts, Ctrl lowers, WASD leans it forward, back and sideways.

const Car := preload("res://scripts/car.gd")

const LABEL := "the helicopter"
const LIFT := 0.12                # the skids stand on the paving, which lies a little above the bare ground
const SPECS := {"flies": true, "reach": 4.2, "hides_rider": false, "exit": 2.2, "camera": 12.0, "drift": false,
	"speed": 0.0, "fast": 0.0, "reverse": 0.0, "power": 0.0, "brake": 0.0}

# the cabin from the side and from above: (z, height of the top), (z, height of the belly), (z, half width)
const TOP := [Vector2(-2.35, 1.10), Vector2(-2.22, 1.30), Vector2(-1.95, 1.60), Vector2(-1.55, 1.97), Vector2(-1.10, 2.24), Vector2(-0.65, 2.37),
	Vector2(0.0, 2.41), Vector2(0.9, 2.39), Vector2(1.5, 2.27), Vector2(2.0, 2.04), Vector2(2.6, 1.81), Vector2(3.0, 1.775)]
const BOTTOM := [Vector2(-2.35, 1.06), Vector2(-2.22, 0.90), Vector2(-1.95, 0.74), Vector2(-1.55, 0.65), Vector2(-1.0, 0.61), Vector2(0.8, 0.61),
	Vector2(1.3, 0.73), Vector2(1.9, 1.05), Vector2(2.6, 1.41), Vector2(3.0, 1.465)]
const WIDTH := [Vector2(-2.35, 0.02), Vector2(-2.27, 0.24), Vector2(-2.05, 0.53), Vector2(-1.65, 0.79), Vector2(-1.15, 0.93), Vector2(-0.5, 0.985),
	Vector2(0.5, 0.985), Vector2(1.0, 0.91), Vector2(1.6, 0.63), Vector2(2.2, 0.35), Vector2(2.6, 0.215), Vector2(3.0, 0.155)]

var rotor := 0.0                 # how fast the rotor turns: 0 stopped, 1 flying speed
var engine := false

var _chassis: Node3D
var _col: CollisionShape3D
var _main: Node3D                # the main rotor
var _tail: Node3D                # the tail rotor
var _disc: MeshInstance3D        # the blur of the blades at speed
var _disc_mat: StandardMaterial3D
var _mats := {}


func _ready() -> void:
	_chassis = Node3D.new()
	_chassis.position.y = LIFT
	add_child(_chassis)
	_mats = {
		"paint": _mat(Color(0.93, 0.93, 0.91), 0.3, 0.1),
		"red": _mat(Color(0.75, 0.06, 0.05), 0.35, 0.1),
		"glass": _mat(Color(0.62, 0.80, 0.86, 0.26), 0.04, 0.2),
		"tint": _mat(Color(0.25, 0.55, 0.40, 0.40), 0.04, 0.2),
		"black": _mat(Color(0.05, 0.05, 0.055), 0.6),
		"steel": _mat(Color(0.55, 0.57, 0.60), 0.35, 0.8),
		"dark": _mat(Color(0.16, 0.17, 0.18), 0.6, 0.3),
		"blade": _mat(Color(0.10, 0.10, 0.11), 0.5, 0.2),
		"yellow": _mat(Color(0.92, 0.75, 0.10), 0.5),
		"lamp": _lit(Color(0.95, 0.95, 0.9), 0.5),
		"beacon": _lit(Color(0.9, 0.08, 0.05), 0.8),
		"green": _lit(Color(0.1, 0.8, 0.2), 0.6),
		"seat": _mat(Color(0.20, 0.22, 0.27), 0.9),
		"floor": _mat(Color(0.30, 0.30, 0.31), 0.9),
	}
	for key in ["glass", "tint"]:
		_mats[key].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_mats[key].cull_mode = BaseMaterial3D.CULL_DISABLED
	for key in ["paint", "red"]:
		_mats[key].cull_mode = BaseMaterial3D.CULL_DISABLED      # the inside of the cabin shows through the glass
	var g = Car.Geo.new()
	_build_cabin(g)
	_build_boom_and_tail(g)
	_build_cowling(g)
	_build_skids(g)
	_build_inside(g)
	_build_fittings(g)
	var mi := MeshInstance3D.new()
	mi.mesh = g.commit(_mats)
	_chassis.add_child(mi)

	# main rotor: mast, swashplate, hub and two long blades that droop a little when still
	var top_y := 3.12
	_main = Node3D.new()
	_main.position = Vector3(0, top_y, 0.0)
	_chassis.add_child(_main)
	var rg = Car.Geo.new()
	rg.lathe("steel", Vector3(0, -0.52, 0), Vector3.UP, [Vector2(0.0, 0.0), Vector2(0.055, 0.0), Vector2(0.055, 0.46), Vector2(0.09, 0.50), Vector2(0.09, 0.58), Vector2(0.0, 0.60)], 18)
	rg.lathe("dark", Vector3(0, -0.36, 0), Vector3.UP, [Vector2(0.06, 0.0), Vector2(0.20, 0.0), Vector2(0.22, 0.03), Vector2(0.20, 0.06), Vector2(0.06, 0.06)], 24)      # swashplate
	rg.box("steel", Vector3(0, 0.02, 0), Vector3(0.62, 0.05, 0.09))                                    # the yoke across the mast
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		rg.cyl("steel", Vector3(0.18 * sx, -0.17, 0.10 * sx), Vector3(0.05 * sx, 1.0, 0.0).normalized(), 0.012, 0.20, 8)     # pitch links
		rg.box("dark", Vector3(0.50 * sx, 0.02, 0), Vector3(0.14, 0.045, 0.11))                         # blade grips
		_blade(rg, sx)
	var rmi := MeshInstance3D.new()
	rmi.mesh = rg.commit(_mats)
	_main.add_child(rmi)
	var dm := CylinderMesh.new()
	dm.top_radius = 5.08
	dm.bottom_radius = 5.08
	dm.height = 0.02
	dm.radial_segments = 48
	_disc_mat = StandardMaterial3D.new()
	_disc_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_disc_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_disc_mat.albedo_color = Color(0.1, 0.1, 0.1, 0.0)
	_disc_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	dm.material = _disc_mat
	_disc = MeshInstance3D.new()
	_disc.mesh = dm
	_disc.position = Vector3(0, top_y + 0.02, 0.0)
	_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_chassis.add_child(_disc)
	# tail rotor: two blades on the left of the fin
	_tail = Node3D.new()
	_tail.position = Vector3(-0.24, 2.12, 6.92)
	_chassis.add_child(_tail)
	var tg = Car.Geo.new()
	tg.cyl("steel", Vector3.ZERO, Vector3.RIGHT, 0.045, 0.06, 12)
	for sgn in [-1.0, 1.0]:
		var sy: float = sgn
		for q in 4:
			var r0 := 0.06 + 0.76 * float(q) / 4.0
			var r1 := 0.06 + 0.76 * float(q + 1) / 4.0
			tg.box("yellow" if q == 3 else "blade", Vector3(0, (r0 + r1) * 0.5 * sy, 0), Vector3(0.008, (r1 - r0) * 0.5 + 0.002, 0.045 + 0.02 * float(q) / 4.0), Basis(Vector3.UP, 0.25))
	var tmi := MeshInstance3D.new()
	tmi.mesh = tg.commit(_mats)
	_tail.add_child(tmi)

	var shape := BoxShape3D.new()
	shape.size = Vector3(2.2, 2.9, 5.2)
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position = Vector3(0, 1.55, 0.1)
	var sb := StaticBody3D.new()
	sb.add_child(_col)
	add_child(sb)


# ------------------------------------------------------------------ the shape
static func _at(points: Array, z: float) -> float:
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		if z <= b.x:
			var t := clampf((z - a.x) / maxf(b.x - a.x, 1e-6), 0.0, 1.0)
			return lerpf(a.y, b.y, t * t * (3.0 - 2.0 * t) * 0.5 + t * 0.5)       # half way between straight and eased: no sharp kinks
	return points[-1].y


## A smooth skin over rows of points (each row a ring round the body). `pick` says what each patch is made
## of; the points get rounded normals, so the body is smooth and not faceted.
func _skin(g, rows: Array, closed: bool, pick: Callable) -> void:
	var n := rows.size()
	var m: int = rows[0].size()
	var normals := []
	for i in n:
		var row := PackedVector3Array()
		var centre := Vector3.ZERO
		for p in rows[i]:
			centre += p
		centre /= float(m)
		for j in m:
			var along: Vector3 = rows[mini(i + 1, n - 1)][j] - rows[maxi(i - 1, 0)][j]
			var jn := (j + 1) % m if closed else mini(j + 1, m - 1)
			var jp := (j - 1 + m) % m if closed else maxi(j - 1, 0)
			var around: Vector3 = rows[i][jn] - rows[i][jp]
			var nrm := along.cross(around)
			if nrm.length_squared() < 1e-12:
				nrm = rows[i][j] - centre
			nrm = nrm.normalized()
			if nrm.dot(rows[i][j] - centre) < 0.0:
				nrm = -nrm
			row.append(nrm)
		normals.append(row)
	var last := m if closed else m - 1
	for i in n - 1:
		for j in last:
			var j2 := (j + 1) % m
			var mat: String = pick.call(i, j)
			if mat == "":
				continue
			if not g.surf.has(mat):
				g.surf[mat] = [PackedVector3Array(), PackedVector3Array()]
			var s: Array = g.surf[mat]
			var idx := [[i, j], [i + 1, j], [i + 1, j2], [i, j], [i + 1, j2], [i, j2]]
			var a: Vector3 = rows[i][j]
			var b: Vector3 = rows[i + 1][j]
			var c: Vector3 = rows[i + 1][j2]
			var face := (b - a).cross(c - a)
			if face.length_squared() < 1e-14:
				face = (c - a).cross(rows[i][j2] - a)
			# the same winding rule as Geo.tri: the front is the side the normals point to
			var flip: bool = face.dot(normals[i][j] + normals[i + 1][j2]) >= 0.0
			for t in 2:
				var order := [0, 1, 2] if not flip else [0, 2, 1]
				for k in order:
					var q: Array = idx[t * 3 + k]
					s[0].append(rows[q[0]][q[1]])
					s[1].append(normals[q[0]][q[1]])


## One ring round the cabin at z: a rounded shape, squarer than an ellipse, wider than it is tall.
func _cabin_ring(z: float, count: int) -> PackedVector3Array:
	var top := _at(TOP, z)
	var bot := _at(BOTTOM, z)
	var w := _at(WIDTH, z)
	var cy := (top + bot) * 0.5
	var hy := (top - bot) * 0.5
	var ring := PackedVector3Array()
	for k in count:
		var a := TAU * float(k) / float(count)
		var cs := cos(a)
		var sn := sin(a)
		var e := 0.78                                           # 1 would be an ellipse; lower is squarer
		ring.append(Vector3(w * signf(cs) * pow(absf(cs), e), cy + hy * signf(sn) * pow(absf(sn), e) - 0.06 * hy * (1.0 - absf(sn)), z))
	return ring


func _build_cabin(g) -> void:
	var count := 52
	var rows := []
	var zs := PackedFloat32Array()
	var z := -2.35
	while z < 3.0 - 0.0005:
		zs.append(z)
		z += 0.012 if z < -2.0 else 0.025
	zs.append(3.0)
	for zz in zs:
		rows.append(_cabin_ring(zz, count))
	var pick := func(i: int, j: int) -> String:
		var zm: float = (zs[i] + zs[i + 1]) * 0.5
		var a := TAU * (float(j) + 0.5) / float(count)
		var el := rad_to_deg(atan2(sin(a), absf(cos(a))))          # how far up the side: -90 belly, 0 waist, 90 roof
		var post := absf(cos(a)) < 0.045                           # the middle of the machine, top and bottom
		if zm > -2.14 and zm < -1.02 and el > 9.0 and not post:
			return "glass"                                         # the windscreen, in two panes
		if zm > -2.02 and zm < -1.38 and el < -20.0 and el > -66.0:
			return "glass"                                         # chin windows by the pilots' feet
		if zm > -0.95 and zm < -0.22 and el > 7.0 and el < 58.0:
			return "glass"                                         # front door windows
		if zm > -0.07 and zm < 0.66 and el > 9.0 and el < 55.0:
			return "glass"                                         # rear door windows
		if zm > -0.92 and zm < -0.34 and el > 64.0 and el < 84.0:
			return "tint"                                          # the green windows in the roof
		if zm > -1.95 and zm < 2.75 and el > -9.0 and el < 1.5:
			return "red"                                           # the stripe along the waist
		return "paint"
	_skin(g, rows, true, pick)


func _build_boom_and_tail(g) -> void:
	# the boom: a slim tube from the back of the cabin to the tail, rising a little, red at its tip
	var rows := []
	var count := 22
	var stations := 36
	var zs := []
	for i in stations + 1:
		var t := float(i) / float(stations)
		var z := lerpf(3.0, 7.12, t)
		zs.append(z)
		var r := lerpf(0.155, 0.075, t) * (1.0 if t < 0.97 else lerpf(1.0, 0.25, (t - 0.97) / 0.03))
		var cy := lerpf(1.62, 1.70, t)
		var ring := PackedVector3Array()
		for k in count:
			var a := TAU * float(k) / float(count)
			ring.append(Vector3(cos(a) * r, cy + sin(a) * r, z))
		rows.append(ring)
	_skin(g, rows, true, func(i: int, _j: int) -> String: return "red" if zs[i] > 6.55 else "paint")
	# the stabiliser across the boom, with a small plate at each end
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		_wing(g, "paint", Vector3(0.12 * sx, 1.64, 4.72), Vector3(1.00 * sx, 1.64, 4.78), 0.40, 0.30, 0.045, Vector3.UP)
		_wing(g, "paint", Vector3(1.00 * sx, 1.46, 4.80), Vector3(1.00 * sx, 1.86, 4.84), 0.30, 0.24, 0.02, Vector3(sx, 0, 0))
	# the fin: swept back above the boom, a shorter piece below it, and the guard under that
	_wing(g, "paint", Vector3(0.05, 1.74, 6.62), Vector3(0.05, 2.78, 7.18), 0.62, 0.36, 0.05, Vector3.RIGHT)
	_wing(g, "paint", Vector3(0.05, 1.64, 6.66), Vector3(0.05, 1.12, 6.98), 0.52, 0.30, 0.045, Vector3.RIGHT)
	g.cyl("steel", Vector3(0.05, 1.02, 7.02), Vector3(0, -0.5, 0.86).normalized(), 0.014, 0.16, 8)
	# the tail rotor's gearbox
	g.lathe("dark", Vector3(-0.02, 2.12, 6.92), Vector3.LEFT, [Vector2(0.0, -0.08), Vector2(0.075, -0.06), Vector2(0.085, 0.06), Vector2(0.05, 0.16), Vector2(0.0, 0.17)], 16)
	g.box("beacon", Vector3(0.05, 2.82, 7.20), Vector3(0.02, 0.03, 0.03))


## A flat tapered surface with a rounded leading edge: a stabiliser, a fin. From root to tip, with the chord
## (front to back) at each and the thickness; `flat` is the direction it is thin in.
func _wing(g, m: String, root: Vector3, tip: Vector3, chord0: float, chord1: float, thick: float, flat: Vector3) -> void:
	var rows := []
	var steps := 8
	var back := Vector3.BACK
	for i in steps + 1:
		var t := float(i) / float(steps)
		var c := root.lerp(tip, t)
		var ch := lerpf(chord0, chord1, t)
		var th := thick * (1.0 if t < 0.9 else lerpf(1.0, 0.3, (t - 0.9) / 0.1))
		var ring := PackedVector3Array()
		for q in [[0.0, 0.0], [0.08, 0.7], [0.3, 1.0], [0.65, 0.7], [1.0, 0.08], [1.0, -0.08], [0.65, -0.7], [0.3, -1.0], [0.08, -0.7]]:
			ring.append(c + back * (ch * (float(q[0]) - 0.35)) + flat * (th * 0.5 * float(q[1])))
		rows.append(ring)
	_skin(g, rows, true, func(_i: int, _j: int) -> String: return m)
	for end in [0, steps]:                                          # close the ends
		var ring2: PackedVector3Array = rows[end]
		for k in range(1, ring2.size() - 1):
			g.tri(m, ring2[0], ring2[k], ring2[k + 1], (tip - root) * (1.0 if end == steps else -1.0))


func _build_cowling(g) -> void:
	# the engine and gearbox cowling: a rounded hump along the roof, highest round the mast
	var rows := []
	var count := 18
	var stations := 64
	for i in stations + 1:
		var t := float(i) / float(stations)
		var z := lerpf(-0.75, 2.65, t)
		var roof := _at(TOP, z) - 0.05
		var bulge := sin(clampf(t, 0.0, 1.0) * PI)
		var h := 0.06 + 0.44 * pow(bulge, 0.55) * (1.0 - 0.25 * t)
		var w := (0.20 + 0.36 * pow(bulge, 0.5)) * (1.0 - 0.3 * t)
		var ring := PackedVector3Array()
		for k in count + 1:
			var a := PI * float(k) / float(count)
			ring.append(Vector3(cos(a) * w, roof + sin(a) * h, z))
		rows.append(ring)
	_skin(g, rows, false, func(_i: int, _j: int) -> String: return "paint")
	# air intakes at its shoulders, the exhaust stack standing out of it, the oil cooler's grille
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("black", Vector3(0.40 * sx, 2.56, 0.55), Vector3(0.012, 0.09, 0.22), Basis(Vector3.BACK, -0.5 * sx))
		for k in 5:
			g.box("steel", Vector3(0.405 * sx, 2.50 + 0.03 * float(k), 0.55), Vector3(0.014, 0.004, 0.21), Basis(Vector3.BACK, -0.5 * sx))
	g.lathe("dark", Vector3(0, 2.74, 1.55), Vector3(0, 0.80, 0.60).normalized(), [Vector2(0.0, -0.05), Vector2(0.105, -0.05), Vector2(0.115, 0.0), Vector2(0.115, 0.26),
		Vector2(0.098, 0.26), Vector2(0.098, 0.02), Vector2(0.0, 0.02)], 20)
	g.box("black", Vector3(0, 2.66, 2.20), Vector3(0.16, 0.012, 0.16), Basis(Vector3.RIGHT, 0.25))
	# the fairing where the mast comes out
	g.lathe("paint", Vector3(0, 2.78, 0.0), Vector3.UP, [Vector2(0.24, 0.0), Vector2(0.20, 0.07), Vector2(0.11, 0.11), Vector2(0.0, 0.115)], 20)


func _build_skids(g) -> void:
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		# a skid: a long tube whose toe curves up
		var rows := []
		var stations := 36
		for i in stations + 1:
			var t := float(i) / float(stations)
			var z := lerpf(1.62, -2.12, t)
			var y := 0.055 + (0.42 * pow((t - 0.86) / 0.14, 2.0) if t > 0.86 else 0.0)
			var ring := PackedVector3Array()
			for k in 12:
				var a := TAU * float(k) / 12.0
				ring.append(Vector3(1.06 * sx + cos(a) * 0.045, y + sin(a) * 0.045, z))
			rows.append(ring)
		_skin(g, rows, true, func(_i: int, _j: int) -> String: return "steel")
		g.cyl("black", Vector3(1.06 * sx, 0.012, 0.9), Vector3.BACK, 0.05, 0.25, 8)          # wear shoes under it
		g.cyl("black", Vector3(1.06 * sx, 0.012, -1.0), Vector3.BACK, 0.05, 0.25, 8)
		g.box("dark", Vector3(0.80 * sx, 0.58, -0.75), Vector3(0.18, 0.012, 0.09))            # the step by the front door
	# the two cross tubes: arched from skid to skid under the belly
	for lz in [-0.85, 0.80]:
		var rows2 := []
		for i in 33:
			var t := float(i) / 32.0 * 2.0 - 1.0
			var x := 1.06 * t
			var y := 0.10 + 0.50 * (1.0 - pow(absf(t), 2.4))
			var ring := PackedVector3Array()
			for k in 10:
				var a := TAU * float(k) / 10.0
				ring.append(Vector3(x, y + sin(a) * 0.036, lz + cos(a) * 0.036))
			rows2.append(ring)
		_skin(g, rows2, true, func(_i: int, _j: int) -> String: return "steel")


func _build_inside(g) -> void:
	g.box("floor", Vector3(0, 0.70, -0.45), Vector3(0.86, 0.02, 1.35))
	g.box("floor", Vector3(0, 1.45, 0.86), Vector3(0.88, 0.75, 0.02))                        # the bulkhead behind the rear seats
	for row in [[-0.78, 0.38], [0.30, 0.45]]:
		for sgn in [-1.0, 1.0]:
			var sx: float = sgn
			var z: float = row[0]
			var x: float = float(row[1]) * sx
			g.box("seat", Vector3(x, 0.92, z), Vector3(0.24, 0.06, 0.24))
			g.box("seat", Vector3(x, 1.30, z + 0.25), Vector3(0.23, 0.34, 0.05), Basis(Vector3.RIGHT, 0.12))
			g.box("seat", Vector3(x, 1.73, z + 0.30), Vector3(0.12, 0.09, 0.04), Basis(Vector3.RIGHT, 0.12))
			g.box("dark", Vector3(x, 0.80, z), Vector3(0.20, 0.07, 0.20))
	# the instrument panel on its pedestal between the pilots, with its dials; sticks and pedals
	g.box("dark", Vector3(0, 1.02, -1.62), Vector3(0.20, 0.30, 0.14))
	g.box("black", Vector3(0, 1.36, -1.52), Vector3(0.42, 0.16, 0.05), Basis(Vector3.RIGHT, -0.25))
	for k in 8:
		g.cyl("steel", Vector3(-0.31 + 0.09 * float(k % 4) * 2.07, 1.40 - 0.13 * float(k / 4), -1.465), Vector3(0, 0.25, 0.97).normalized(), 0.035, 0.006, 12)
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		g.cyl("dark", Vector3(0.38 * sx2, 0.93, -1.10), Vector3(0, 1.0, -0.25).normalized(), 0.014, 0.24, 8)       # cyclic sticks
		g.cyl("black", Vector3(0.38 * sx2, 1.18, -1.165), Vector3(0, 1.0, -0.25).normalized(), 0.022, 0.05, 8)
		g.cyl("dark", Vector3(0.38 * sx2 - 0.26, 0.86, -0.72), Vector3(0, 0.35, -0.94).normalized(), 0.014, 0.20, 8)  # collective levers
		for p in [-0.11, 0.11]:
			g.box("dark", Vector3(0.38 * sx2 + p, 0.80, -1.72), Vector3(0.045, 0.06, 0.012), Basis(Vector3.RIGHT, -0.5))


func _build_fittings(g) -> void:
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("black", Vector3(0.975 * sx, 1.42, -0.86), Vector3(0.008, 0.012, 0.05))          # door handles
		g.box("black", Vector3(0.975 * sx, 1.42, 0.02), Vector3(0.008, 0.012, 0.05))
		g.box("green" if sx > 0.0 else "beacon", Vector3(1.01 * sx, 1.66, 4.80), Vector3(0.012, 0.02, 0.03))     # position lights on the stabiliser
		g.box("lamp", Vector3(0.22 * sx, 0.70, -1.92), Vector3(0.06, 0.035, 0.03))               # landing lights under the nose
	g.cyl("beacon", Vector3(0, 0.60, 0.4), Vector3.UP, 0.05, 0.03, 12)                          # the beacon under the belly
	g.cyl("steel", Vector3(-0.30, 1.15, -2.22), Vector3.BACK, 0.008, 0.11, 6)                    # pitot tube
	g.box("steel", Vector3(0, 2.50, -0.35), Vector3(0.006, 0.09, 0.05), Basis(Vector3.RIGHT, -0.4))   # aerials
	g.box("steel", Vector3(0, 0.50, 1.0), Vector3(0.006, 0.10, 0.06), Basis(Vector3.RIGHT, 0.4))
	g.box("steel", Vector3(0, 1.80, 5.6), Vector3(0.004, 0.09, 0.03))


## A main rotor blade, out to one side: a slim aerofoil that droops under its own weight, yellow at the tip.
func _blade(g, sx: float) -> void:
	var rows := []
	var steps := 22
	for i in steps + 1:
		var t := float(i) / float(steps)
		var r := lerpf(0.62, 5.08, t)
		var droop := -0.0042 * r * r
		var ring := PackedVector3Array()
		for q in [[-0.33, 0.0], [-0.28, 0.5], [-0.12, 1.0], [0.20, 0.75], [0.67, 0.08], [0.67, -0.08], [0.20, -0.5], [-0.12, -0.7], [-0.28, -0.4]]:
			ring.append(Vector3(r * sx, droop + float(q[1]) * 0.019, float(q[0]) * 0.33 * sx))
		rows.append(ring)
	_skin(g, rows, true, func(i: int, _j: int) -> String: return "yellow" if i >= steps - 2 else "blade")
	var tip: PackedVector3Array = rows[steps]
	for k in range(1, tip.size() - 1):
		g.tri("yellow", tip[0], tip[k], tip[k + 1], Vector3(sx, 0, 0))


func _mat(color: Color, rough: float, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metallic
	return mat


func _lit(color: Color, energy: float) -> StandardMaterial3D:
	var mat := _mat(color, 0.3)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


# ------------------------------------------------------------------ what the player's code asks of a vehicle
func specs() -> Dictionary:
	return SPECS


func set_parked(parked: bool) -> void:
	_col.disabled = not parked
	engine = not parked


func park() -> void:
	_chassis.transform = Transform3D(Basis(), Vector3(0, LIFT, 0))


func set_drift(_on: bool, _slip: float, _speed: float) -> void:
	pass


func chassis_xf() -> Transform3D:
	return _chassis.transform


## Where the pilot sits (the right-hand front seat): the hips, and how far the back leans.
func seat() -> Array:
	return [Vector3(0.38, 1.00, -0.76), -0.10]


## The pilot's hands: the right on the cyclic stick between the knees, the left on the collective lever.
func grip(side: float) -> Vector3:
	return _chassis.transform * (Vector3(0.38, 1.21, -1.17) if side > 0.0 else Vector3(0.12, 0.93, -0.90))


## And feet, on the pedals.
func foot(side: float) -> Vector3:
	return _chassis.transform * Vector3(0.38 + 0.11 * side, 0.82, -1.66)


func animate(_speed: float, _steer: float, _delta: float, _exclude: Array = []) -> void:
	pass


## The rotor runs up while the engine is on and runs down when it is off; the blades turn, and at speed
## they are a blur.
func _process(delta: float) -> void:
	rotor = move_toward(rotor, 1.0 if engine else 0.0, delta * (0.28 if engine else 0.12))
	if rotor > 0.001:
		_main.rotation.y -= rotor * 38.0 * delta
		_tail.rotation.x += rotor * 120.0 * delta
	_disc_mat.albedo_color.a = 0.20 * smoothstep(0.35, 1.0, rotor)
	_disc.visible = rotor > 0.3
