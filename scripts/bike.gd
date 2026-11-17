extends Node3D
## A mountain bike. Parked, it leans on its stand; the player gets on with F and rides it
## (scripts/player.gd drives it like the other vehicles). Faces -Z.
##
## The rider pedals: the cranks turn with the wheels while there is pressure on them, the pedals stay level,
## and the rider's feet are on them, so the legs go round. The bars, fork and front wheel turn with the
## steering and the hands stay on the grips. It leans into bends. Holding Space crouches rider and bike
## ("preload"); letting go springs them up — the longer the hold, the higher the jump.

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo)

const LABEL := "the bicycle"
const SPECS := {"bike": true, "speed": 8.5, "fast": 13.5, "reverse": 1.2, "power": 5.5, "brake": 13.0, "reach": 2.3,
	"drift": false, "hides_rider": false, "exit": 0.9, "camera": 0.0}

const WHEEL_R := 0.345
const AXLE_F := -0.58
const AXLE_R := 0.50
const BB := Vector3(0, 0.315, 0.07)                  # the bottom bracket: where the cranks turn
const CRANK := 0.172
const SEAT := Vector3(0, 0.955, 0.25)
const HEAD_TOP := Vector3(0, 0.985, -0.415)
const HEAD_LOW := Vector3(0, 0.835, -0.455)
const BAR_Y := 1.075
const BAR_Z := -0.41

var _chassis: Node3D
var _steer_node: Node3D          # bars, fork and front wheel: turns about the steering axis
var _front: Node3D
var _rear: Node3D
var _crank: Node3D
var _pedals: Array = []
var _col: CollisionShape3D
var _body_mesh: ArrayMesh
var _mats := {}

var _spin := 0.0
var _crank_a := 0.6
var _steer := 0.0
var _roll := 0.0
var _roll_v := 0.0
var _preload := 0.0
var _pedalling := false
var _parked := true
var _last_yaw := 0.0
var _fresh := true


func _ready() -> void:
	_mats = {
		"frame": _mat(Color(0.05, 0.32, 0.55), 0.3, 0.4), "black": _mat(Color(0.05, 0.05, 0.055), 0.7), "rubber": _mat(Color(0.035, 0.035, 0.035), 1.0),
		"steel": _mat(Color(0.70, 0.71, 0.73), 0.3, 0.85), "alloy": _mat(Color(0.25, 0.25, 0.27), 0.4, 0.7), "saddle": _mat(Color(0.07, 0.07, 0.07), 0.8),
		"red": _mat(Color(0.75, 0.06, 0.05), 0.4), "lamp": _mat(Color(0.95, 0.95, 0.9), 0.3),
	}
	_chassis = Node3D.new()
	add_child(_chassis)
	var g = Shapes.Geo.new()
	var rear_axle := Vector3(0, WHEEL_R, AXLE_R)
	var seat_top := Vector3(0, 0.90, 0.215)
	var seat_join := Vector3(0, 0.80, 0.185)
	# the frame: top tube, down tube, seat tube; chain stays and seat stays to the rear axle
	g.tube("frame", [seat_join, HEAD_TOP + Vector3(0, -0.035, 0.01)], 0.019, 12)
	g.tube("frame", [BB, HEAD_LOW + Vector3(0, 0.02, 0.0)], 0.024, 12)
	g.tube("frame", [BB, seat_top], 0.019, 12)
	g.tube("frame", [HEAD_LOW - (HEAD_TOP - HEAD_LOW).normalized() * 0.01, HEAD_TOP + (HEAD_TOP - HEAD_LOW).normalized() * 0.01], 0.026, 12)
	g.tube("steel", [seat_top, SEAT - Vector3(0, 0.035, 0)], 0.013, 10)                      # seat post
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.tube("frame", [BB + Vector3(0.035 * sx, 0, 0.02), rear_axle + Vector3(0.068 * sx, 0, 0)], 0.011, 8)
		g.tube("frame", [seat_join + Vector3(0.02 * sx, 0, 0.0), rear_axle + Vector3(0.068 * sx, 0, 0)], 0.009, 8)
		g.box("steel", rear_axle + Vector3(0.068 * sx, 0, 0), Vector3(0.006, 0.02, 0.022))
	g.cyl("frame", BB, Vector3.RIGHT, 0.028, 0.04, 12)
	# the saddle: narrow at the nose, broad at the back
	var rows := []
	for q in [[-0.14, 0.016, 0.012], [-0.10, 0.026, 0.020], [0.0, 0.045, 0.026], [0.08, 0.072, 0.028], [0.125, 0.078, 0.024], [0.14, 0.05, 0.012]]:
		var ring := PackedVector3Array()
		for k in 12:
			var a := TAU * float(k) / 12.0
			ring.append(SEAT + Vector3(cos(a) * float(q[1]), sin(a) * float(q[2]) * (1.0 if sin(a) > 0.0 else 0.5), q[0]))
		rows.append(ring)
	g.skin(rows, true, "saddle")
	g.cap("saddle", rows[0], Vector3.FORWARD)
	g.cap("saddle", rows[-1], Vector3.BACK)
	# rear mudguard-less; a reflector under the saddle, the rear derailleur and sprockets, the stand
	g.box("red", SEAT + Vector3(0, -0.06, 0.13), Vector3(0.022, 0.016, 0.006))
	g.lathe("steel", rear_axle + Vector3(0.048, 0, 0), Vector3.RIGHT, [Vector2(0.02, 0.0), Vector2(0.055, 0.0), Vector2(0.048, 0.008), Vector2(0.04, 0.008), Vector2(0.034, 0.016), Vector2(0.02, 0.016)], 20)
	g.box("black", rear_axle + Vector3(0.075, -0.09, 0.02), Vector3(0.008, 0.06, 0.018), Basis(Vector3.RIGHT, 0.3))
	g.cyl("black", rear_axle + Vector3(0.075, -0.145, 0.035), Vector3.RIGHT, 0.022, 0.004, 10)
	g.tube("steel", [rear_axle + Vector3(-0.07, -0.02, -0.10), Vector3(-0.20, 0.02, AXLE_R - 0.02)], 0.007, 6)     # the stand, folded down
	# the chain: along the top and the bottom from the chainring to the sprocket
	for q in [[0.085, 0.0], [-0.085, -0.02]]:
		g.tube("alloy", [BB + Vector3(0.05, q[0], 0.0), rear_axle + Vector3(0.05, 0.045 if float(q[0]) > 0.0 else -0.05 + float(q[1]), 0.0)], 0.005, 5)
	var body := MeshInstance3D.new()
	body.mesh = g.commit(_mats)
	_body_mesh = body.mesh
	_chassis.add_child(body)

	# cranks and pedals, turning about the bottom bracket
	_crank = Node3D.new()
	_crank.position = BB
	_chassis.add_child(_crank)
	var cg = Shapes.Geo.new()
	cg.lathe("alloy", Vector3(0.05, 0, 0), Vector3.RIGHT, [Vector2(0.03, -0.003), Vector2(0.088, -0.003), Vector2(0.088, 0.003), Vector2(0.03, 0.003)], 28)   # the chainring
	for k in 14:
		var a := TAU * float(k) / 14.0
		cg.box("alloy", Vector3(0.05, sin(a) * 0.092, cos(a) * 0.092), Vector3(0.002, 0.006, 0.008), Basis(Vector3.RIGHT, -a))
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		cg.tube("steel", [Vector3(0.062 * sx2, 0, 0), Vector3(0.078 * sx2, 0, CRANK * sx2)], 0.011, 8)
	var cmi := MeshInstance3D.new()
	cmi.mesh = cg.commit(_mats)
	_crank.add_child(cmi)
	var pg = Shapes.Geo.new()
	pg.box("black", Vector3.ZERO, Vector3(0.05, 0.011, 0.045))
	pg.box("steel", Vector3.ZERO, Vector3(0.052, 0.004, 0.047))
	for k in 6:
		pg.box("steel", Vector3(-0.04 + 0.016 * float(k), 0.014, 0.038 * (1.0 if k % 2 == 0 else -1.0)), Vector3(0.002, 0.004, 0.002))
	var pedal_mesh: ArrayMesh = pg.commit(_mats)
	for sgn in [-1.0, 1.0]:
		var p := MeshInstance3D.new()
		p.mesh = pedal_mesh
		_chassis.add_child(p)
		_pedals.append(p)

	# the rear wheel
	var wg = Shapes.Geo.new()
	_build_wheel(wg)
	var wheel_mats := {}                                # a tyre is a shell: both sides of it are drawn, so it is never seen through
	for key in _mats:
		wheel_mats[key] = _mats[key]
		if _mats[key] is StandardMaterial3D:
			wheel_mats[key] = _mats[key].duplicate()
			wheel_mats[key].cull_mode = BaseMaterial3D.CULL_DISABLED
	var wheel_mesh: ArrayMesh = wg.commit(wheel_mats)
	_rear = Node3D.new()
	_rear.position = rear_axle
	_chassis.add_child(_rear)
	var rmi := MeshInstance3D.new()
	rmi.mesh = wheel_mesh
	_rear.add_child(rmi)

	# what turns with the steering: the fork and front wheel, the stem and the bars
	_steer_node = Node3D.new()
	_steer_node.position = HEAD_LOW
	_chassis.add_child(_steer_node)
	var sg = Shapes.Geo.new()
	var front_axle := Vector3(0, WHEEL_R, AXLE_F) - HEAD_LOW
	for sgn in [-1.0, 1.0]:
		var sx3: float = sgn
		sg.tube("black", [Vector3(0.05 * sx3, -0.03, -0.005), Vector3(0.055 * sx3, -0.27, -0.07), front_axle + Vector3(0.055 * sx3, 0, 0)], 0.017, 10)   # suspension fork legs
		sg.tube("steel", [Vector3(0.05 * sx3, -0.03, -0.005), Vector3(0.053 * sx3, -0.20, -0.052)], 0.013, 10)
	sg.box("black", Vector3(0, -0.03, -0.005), Vector3(0.07, 0.016, 0.022))                 # fork crown
	sg.tube("black", [Vector3(0, 0.15, 0.04), Vector3(0, BAR_Y - HEAD_LOW.y, BAR_Z - HEAD_LOW.z)], 0.016, 10)     # stem
	sg.tube("alloy", [Vector3(-0.34, BAR_Y - HEAD_LOW.y + 0.012, BAR_Z - HEAD_LOW.z + 0.03), Vector3(-0.12, BAR_Y - HEAD_LOW.y, BAR_Z - HEAD_LOW.z), Vector3(0.12, BAR_Y - HEAD_LOW.y, BAR_Z - HEAD_LOW.z),
		Vector3(0.34, BAR_Y - HEAD_LOW.y + 0.012, BAR_Z - HEAD_LOW.z + 0.03)], 0.012, 10)
	for sgn in [-1.0, 1.0]:
		var sx4: float = sgn
		sg.tube("rubber", [Vector3(0.24 * sx4, BAR_Y - HEAD_LOW.y + 0.008, BAR_Z - HEAD_LOW.z + 0.018), Vector3(0.35 * sx4, BAR_Y - HEAD_LOW.y + 0.013, BAR_Z - HEAD_LOW.z + 0.032)], 0.017, 10)   # grips
		sg.tube("steel", [Vector3(0.21 * sx4, BAR_Y - HEAD_LOW.y, BAR_Z - HEAD_LOW.z - 0.01), Vector3(0.24 * sx4, BAR_Y - HEAD_LOW.y - 0.01, BAR_Z - HEAD_LOW.z - 0.05), Vector3(0.33 * sx4, BAR_Y - HEAD_LOW.y - 0.012, BAR_Z - HEAD_LOW.z - 0.045)], 0.005, 6)   # brake levers
	sg.box("lamp", Vector3(0, 0.19, -0.02), Vector3(0.022, 0.016, 0.01))                    # a front reflector
	var smi := MeshInstance3D.new()
	smi.mesh = sg.commit(_mats)
	_steer_node.add_child(smi)
	_front = Node3D.new()
	_front.position = front_axle
	_steer_node.add_child(_front)
	var fmi := MeshInstance3D.new()
	fmi.mesh = wheel_mesh
	_front.add_child(fmi)

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.5, 1.0, 1.75)
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position = Vector3(0, 0.5, 0)
	var sb := StaticBody3D.new()
	sb.add_child(_col)
	add_child(sb)
	_place()


## A wheel in the plane across the X axis: a knobbly tyre, a rim, a hub and thirty-two spokes, a disc brake.
func _build_wheel(g) -> void:
	g.lathe("rubber", Vector3.ZERO, Vector3.RIGHT, [Vector2(0.300, -0.018), Vector2(0.312, -0.026), Vector2(0.330, -0.027), Vector2(0.341, -0.018), Vector2(WHEEL_R, -0.006),
		Vector2(WHEEL_R, 0.006), Vector2(0.341, 0.018), Vector2(0.330, 0.027), Vector2(0.312, 0.026), Vector2(0.300, 0.018)], 40)
	for k in 40:                                                    # knobs
		var a := TAU * float(k) / 40.0
		for sgn in [-1.0, 1.0]:
			var sx: float = sgn
			g.box("rubber", Vector3(0.012 * sx + (0.006 if k % 2 == 0 else -0.006), sin(a) * (WHEEL_R + 0.002), cos(a) * (WHEEL_R + 0.002)), Vector3(0.006, 0.004, 0.009), Basis(Vector3.RIGHT, -a))
	g.lathe("alloy", Vector3.ZERO, Vector3.RIGHT, [Vector2(0.302, -0.014), Vector2(0.300, -0.016), Vector2(0.285, -0.012), Vector2(0.280, 0.0), Vector2(0.285, 0.012), Vector2(0.300, 0.016), Vector2(0.302, 0.014)], 36)
	g.lathe("steel", Vector3.ZERO, Vector3.RIGHT, [Vector2(0.0, -0.05), Vector2(0.012, -0.05), Vector2(0.024, -0.04), Vector2(0.018, -0.02), Vector2(0.018, 0.02), Vector2(0.024, 0.04), Vector2(0.012, 0.05), Vector2(0.0, 0.05)], 14)
	for k in 32:
		var a2 := TAU * float(k) / 32.0
		var side := 1.0 if k % 2 == 0 else -1.0
		var skew := 0.5 * (1.0 if (k / 2) % 2 == 0 else -1.0)                      # crossed spokes
		var inner := Vector3(0.038 * side, sin(a2 + skew) * 0.024, cos(a2 + skew) * 0.024)
		var outer := Vector3(0.004 * side, sin(a2) * 0.283, cos(a2) * 0.283)
		g.tube("steel", [inner, outer], 0.0016, 4)
	g.lathe("steel", Vector3(-0.045, 0, 0), Vector3.RIGHT, [Vector2(0.025, -0.0015), Vector2(0.085, -0.0015), Vector2(0.085, 0.0015), Vector2(0.025, 0.0015)], 24)     # brake disc


func _mat(color: Color, rough: float, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metallic
	return mat


# ------------------------------------------------------------------ what the player's code asks of a vehicle
func specs() -> Dictionary:
	return SPECS


## Where the tyres stand on the ground, in the bicycle's own frame.
func wheel_points() -> Array:
	return [Vector3(0, 0, AXLE_F), Vector3(0, 0, AXLE_R)]


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


func set_parked(parked: bool) -> void:
	_col.disabled = not parked
	_parked = parked


func park() -> void:
	_roll = 0.0
	_roll_v = 0.0
	_steer = 0.35
	_preload = 0.0
	_fresh = true
	_place()


func set_drift(_on: bool, _slip: float, _speed: float) -> void:
	pass


## Crouching for a jump: 0 not at all, 1 as far as it goes.
func set_preload(amount: float) -> void:
	_preload = clampf(amount, 0.0, 1.0)


## Whether the rider is pressing on the pedals (they turn then; coasting, they stay where they are).
func set_pedal(on: bool) -> void:
	_pedalling = on


func chassis_xf() -> Transform3D:
	return _chassis.transform


## Where the rider sits, and how far the back leans forward; lower and further forward when crouched.
func seat() -> Array:
	return [SEAT + Vector3(0, 0.035 - 0.07 * _preload, -0.02 - 0.04 * _preload), 0.62 + 0.25 * _preload]


## The grips, wherever the steering has taken them.
func grip(side: float) -> Vector3:
	return _chassis.transform * (_steer_node.transform * Vector3(0.30 * side, BAR_Y - HEAD_LOW.y + 0.035, BAR_Z - HEAD_LOW.z + 0.028))


## The pedals, wherever the cranks have taken them (the right one leads, the left is half a turn behind).
func foot(side: float) -> Vector3:
	return _chassis.transform * (_pedal_at(side) + Vector3(0.0, 0.085, 0.03))


func _pedal_at(side: float) -> Vector3:
	var s := 1.0 if side > 0.0 else -1.0                   # the two cranks point opposite ways
	return BB + Vector3(0.115 * side, -sin(_crank_a) * CRANK * s, cos(_crank_a) * CRANK * s)


func animate(speed: float, steer: float, delta: float, _exclude: Array = []) -> void:
	delta = maxf(delta, 0.001)
	_spin -= speed * delta / WHEEL_R
	if _pedalling and _preload < 0.05:
		_crank_a -= speed * delta / WHEEL_R * 0.42                       # the gearing: about one turn of the cranks to two and a half of the wheel
	elif _preload > 0.05:
		_crank_a = lerp_angle(_crank_a, 0.0, minf(1.0, 8.0 * delta))      # cranks level for the jump
	_steer = lerpf(_steer, steer * 0.5 * clampf(1.2 - absf(speed) * 0.06, 0.25, 1.0), minf(1.0, 9.0 * delta))
	var yaw := global_rotation.y
	if _fresh:
		_last_yaw = yaw
		_fresh = false
	var yaw_rate := angle_difference(_last_yaw, yaw) / delta
	_last_yaw = yaw
	# it leans into the bend, the more the faster and tighter it turns
	var want := clampf(speed * yaw_rate * 0.045, -0.55, 0.55)
	_roll_v += (-60.0 * (_roll - want) - 11.0 * _roll_v) * delta
	_roll = clampf(_roll + _roll_v * delta, -0.6, 0.6)
	_place()


func _place() -> void:
	var lean := 0.16 if _parked else _roll
	_chassis.transform = Transform3D(Basis(Vector3.BACK, lean), Vector3(0.0, -0.045 * _preload, 0.0))
	var axis := (HEAD_TOP - HEAD_LOW).normalized()
	_steer_node.transform = Transform3D(Basis(axis, _steer), HEAD_LOW)
	_front.rotation.x = _spin
	_rear.rotation.x = _spin
	_crank.rotation.x = _crank_a
	for i in 2:
		_pedals[i].position = _pedal_at(1.0 if i == 1 else -1.0)
