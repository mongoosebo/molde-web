extends CharacterBody3D
## Third-person character: WASD to move, mouse to look, Shift to sprint, Space to jump.
## F gets on and off the ATV; on it, W/S is throttle and brake/reverse, A/D steers, Shift is full throttle.

const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.8
const SWIM_SPEED := 1.7
const JUMP_SPEED := 5.4
const GRAVITY := 16.0
const MOUSE_SENS := 0.0025
const WATER_LINE := -1.15          # feet height when floating
const ATV_SPEED := 25.0            # m/s, 90 km/h
const ATV_FAST := 38.0             # with Shift: about 135 km/h
const ATV_REVERSE := 8.0
const ATV_POWER := 17.0            # m/s² off the line, tailing off toward top speed
const ATV_BRAKE := 30.0
const ATV_REACH := 3.2

var world                           # scripts/world.gd
var stamina := 1.0
var yaw := 0.0
var pitch := -0.22
var swimming := false
var atv: Node3D                     # the vehicle being driven, or the one last used (scripts/atv.gd, scripts/car.gd)
var vehicles: Array = []            # everything that can be driven, set by main
var driving := false

var _heading := 0.0                 # vehicle: forward is (-sin, 0, -cos)
var _course := 0.0                  # the way it is actually travelling; differs from the heading in a drift
var _spec := {}                     # the driven vehicle's numbers (speeds, power, whether it can drift …)
var _cam_before := 4.6
var _hop := 0.0                     # bicycle: how far the jump is wound up, 0 to 1
var _lean := Vector2.ZERO            # helicopter: how far it leans (to the right, forward), radians
var _drive_speed := 0.0
var _atv_home: Node
var _air_time := 0.0                # seconds since the wheels last touched the ground

var _pivot: Node3D
var _arm: SpringArm3D
var _cam: Camera3D
var _body: Node3D
var _leg_l: Node3D
var _leg_r: Node3D
var _arm_l: Node3D
var _arm_r: Node3D
var _torso: Node3D
var _head: Node3D
var _knee_l: Node3D
var _knee_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D

const THIGH := 0.46
const SHIN := 0.42
const UPPER_ARM := 0.33
const FOREARM := 0.31
const HIP := Vector3(0.12, 0.95, 0.0)
const SHOULDER := Vector3(0.30, 1.52, 0.0)
var _phase := 0.0
var _exhausted := false


func _ready() -> void:
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.6

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	var col := CollisionShape3D.new()
	col.shape = capsule
	col.position.y = 0.875
	add_child(col)

	_build_body()

	_pivot = Node3D.new()
	_pivot.top_level = true
	_pivot.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(_pivot)
	_arm = SpringArm3D.new()
	_arm.spring_length = 4.6
	_arm.margin = 0.25
	var probe := SphereShape3D.new()
	probe.radius = 0.22
	_arm.shape = probe
	_arm.add_excluded_object(get_rid())
	_pivot.add_child(_arm)
	_cam = Camera3D.new()
	_cam.fov = 70.0
	_cam.near = 0.1
	_cam.far = 70000.0
	_cam.h_offset = 0.45
	_arm.add_child(_cam)
	_cam.make_current()

	if not OS.has_feature("web"):         # a browser only gives up the mouse on a click; the first click captures it
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo): smooth skins, tubes, balls

var _bmats := {}


func _bmat(color: Color, rough := 0.9) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	return mat


func _show(parent: Node3D, g) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = g.commit(_bmats)
	parent.add_child(mi)
	return mi


## A ring of points round a limb or the body, in the plane across it at height y: an oval, or squarer (sq < 1).
func _oval(y: float, rx: float, rz: float, n := 12, cz := 0.0, sq := 1.0) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for k in n:
		var a := TAU * float(k) / float(n)
		var cs := cos(a)
		var sn := sin(a)
		ring.append(Vector3(rx * signf(cs) * pow(absf(cs), sq), y, cz + rz * signf(sn) * pow(absf(sn), sq)))
	return ring


## A limb in two parts with a hinge between them (knee or elbow). Returns [root joint, hinge].
## Both hang straight down (-Y) at rest; rotation.x swings forward, the hinge bends about its own X.
func _limb(pos: Vector3, upper: float, lower: float, leg: bool, side: float) -> Array:
	var joint := Node3D.new()
	joint.position = pos
	_body.add_child(joint)
	var hinge := Node3D.new()
	hinge.position = Vector3(0, -upper, 0)
	joint.add_child(hinge)
	var g = Shapes.Geo.new()
	var h = Shapes.Geo.new()
	if leg:
		# thigh: full at the hip, narrowing to the knee
		var rows := []
		for q in [[0.03, 0.070, 0.080], [0.0, 0.092, 0.100], [-0.10, 0.095, 0.104], [-0.25, 0.085, 0.092], [-0.38, 0.073, 0.079], [-upper, 0.068, 0.074], [-upper - 0.03, 0.060, 0.066]]:
			rows.append(_oval(q[0], q[1], q[2], 14))
		g.skin(rows, true, "jeans")
		g.cap("jeans", rows[0], Vector3.UP)
		# shin: the calf behind, the trouser leg a little wide at the hem, then the boot
		var rows2 := []
		for q in [[0.03, 0.060, 0.066, 0.0], [0.0, 0.068, 0.074, 0.0], [-0.09, 0.066, 0.078, 0.008], [-0.20, 0.058, 0.064, 0.004], [-0.31, 0.052, 0.055, 0.0], [-0.345, 0.060, 0.062, 0.0], [-0.35, 0.050, 0.052, 0.0]]:
			rows2.append(_oval(q[0], q[1], q[2], 14, q[3]))
		h.skin(rows2, true, "jeans")
		var rows3 := []
		for q in [[-0.335, 0.050, 0.054], [-0.40, 0.052, 0.058], [-lower - 0.01, 0.054, 0.062]]:
			rows3.append(_oval(q[0], q[1], q[2], 14))
		h.skin(rows3, true, "boots")
		# the foot: from the heel forward to a rounded toe, flat underneath
		var foot := []
		var sole_y := -lower - 0.09
		for q in [[0.075, 0.030, 0.045], [0.06, 0.050, 0.052], [0.0, 0.056, 0.055], [-0.09, 0.060, 0.048], [-0.16, 0.058, 0.038], [-0.205, 0.046, 0.028], [-0.225, 0.020, 0.016]]:
			var ring := PackedVector3Array()
			for k in 12:
				var a := TAU * float(k) / 12.0
				var sn := sin(a)
				ring.append(Vector3(float(q[1]) * cos(a), sole_y + float(q[2]) + float(q[2]) * (sn if sn > 0.0 else sn * 0.9), q[0]))
			foot.append(ring)
		h.skin(foot, true, "boots")
		h.cap("boots", foot[0], Vector3.BACK)
		h.cap("boots", foot[-1], Vector3.FORWARD)
		h.box("sole", Vector3(0, sole_y - 0.004, -0.07), Vector3(0.056, 0.012, 0.14))
		h.box("sole", Vector3(0, sole_y - 0.012, 0.045), Vector3(0.05, 0.012, 0.035))                 # the heel
		for k in 4:                                                                                    # laces
			h.box("sole", Vector3(0, sole_y + 0.098 - 0.012 * float(k), -0.05 - 0.028 * float(k)), Vector3(0.03, 0.004, 0.004))
	else:
		# upper arm in the sleeve of the parka, rounded over the shoulder
		var rows4 := []
		for q in [[0.05, 0.030, 0.034], [0.035, 0.055, 0.060], [0.0, 0.064, 0.068], [-0.15, 0.058, 0.062], [-upper, 0.050, 0.054], [-upper - 0.025, 0.044, 0.048]]:
			rows4.append(_oval(q[0], q[1], q[2], 12))
		g.skin(rows4, true, "parka")
		g.cap("parka", rows4[0], Vector3.UP)
		var rows5 := []
		for q in [[0.025, 0.044, 0.048], [0.0, 0.050, 0.054], [-0.14, 0.046, 0.050], [-lower + 0.045, 0.041, 0.044], [-lower + 0.03, 0.047, 0.049], [-lower + 0.005, 0.047, 0.049], [-lower + 0.005, 0.030, 0.032]]:
			rows5.append(_oval(q[0], q[1], q[2], 12))
		h.skin(rows5, true, "parka")
		# the hand: a palm, four fingers curled together, and the thumb forward of them
		h.ball("skin", Vector3(0, -lower - 0.035, 0), Vector3(0.022, 0.045, 0.040), 10, 6)
		h.ball("skin", Vector3(0, -lower - 0.085, -0.004), Vector3(0.020, 0.032, 0.036), 10, 5)
		h.ball("skin", Vector3(-0.012 * side, -lower - 0.05, -0.045), Vector3(0.012, 0.030, 0.014), 8, 5)
	_show(joint, g)
	_show(hinge, h)
	return [joint, hinge]


func _build_body() -> void:
	# An ordinary person: parka, jeans, beanie, a backpack. Faces -Z. Knees and elbows bend.
	_bmats = {
		"parka": _bmat(Color(0.27, 0.31, 0.25)), "parka_dark": _bmat(Color(0.19, 0.22, 0.18)), "jeans": _bmat(Color(0.15, 0.19, 0.28)),
		"skin": _bmat(Color(0.84, 0.68, 0.57), 0.7), "boots": _bmat(Color(0.12, 0.10, 0.09), 0.7), "sole": _bmat(Color(0.05, 0.05, 0.05)),
		"pack": _bmat(Color(0.24, 0.19, 0.14)), "strap": _bmat(Color(0.13, 0.11, 0.09)), "beanie": _bmat(Color(0.45, 0.12, 0.10)),
		"dark": _bmat(Color(0.06, 0.05, 0.05), 0.5), "white": _bmat(Color(0.92, 0.92, 0.9), 0.5), "metal": _bmat(Color(0.6, 0.6, 0.62), 0.4),
		"hair": _bmat(Color(0.22, 0.15, 0.10)),
	}
	_body = Node3D.new()
	add_child(_body)
	_torso = Node3D.new()
	_torso.position = Vector3(0, 0.95, 0)
	_body.add_child(_torso)
	var g = Shapes.Geo.new()
	# the parka: over the hips, in at the waist, out over the chest and shoulders, up to the collar
	var rows := []
	for q in [[-0.07, 0.185, 0.118], [-0.06, 0.205, 0.130], [0.02, 0.205, 0.132], [0.16, 0.195, 0.126], [0.32, 0.215, 0.136], [0.47, 0.236, 0.140],
			[0.56, 0.238, 0.132], [0.61, 0.200, 0.115], [0.645, 0.110, 0.090], [0.665, 0.080, 0.080], [0.71, 0.074, 0.076], [0.715, 0.058, 0.060]]:
		rows.append(_oval(q[0], q[1], q[2], 20, 0.0, 0.82))
	g.skin(rows, true, "parka")
	g.cap("parka", rows[0], Vector3.DOWN)
	g.cap("parka_dark", rows[-1], Vector3.UP)
	g.box("metal", Vector3(0, 0.32, -0.139), Vector3(0.005, 0.30, 0.003))                            # the zip
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("parka_dark", Vector3(0.115 * sx, 0.10, -0.131), Vector3(0.055, 0.012, 0.006), Basis(Vector3.BACK, 0.12 * sx))    # pocket flaps
		g.box("parka_dark", Vector3(0.115 * sx, 0.44, -0.139), Vector3(0.045, 0.010, 0.005))                                  # chest pockets
	g.ball("parka", Vector3(0, 0.63, 0.085), Vector3(0.115, 0.075, 0.065), 12, 6)                    # the hood, lying on the back
	# the backpack: a rounded bag with a lid and a pocket, straps over the shoulders
	var bag := []
	for q in [[0.11, 0.10, 0.045], [0.13, 0.150, 0.078], [0.20, 0.168, 0.088], [0.44, 0.165, 0.088], [0.53, 0.150, 0.078], [0.565, 0.100, 0.048]]:
		bag.append(_oval(q[0], q[1], q[2], 16, 0.215, 0.55))
	g.skin(bag, true, "pack")
	g.cap("pack", bag[0], Vector3.DOWN)
	g.cap("pack", bag[-1], Vector3.UP)
	var lid := []
	for q in [[0.47, 0.160, 0.030], [0.50, 0.172, 0.094], [0.56, 0.160, 0.086], [0.585, 0.090, 0.040]]:
		lid.append(_oval(q[0], q[1], q[2], 16, 0.220, 0.6))
	g.skin(lid, true, "strap")
	g.cap("strap", lid[-1], Vector3.UP)
	var pocket := []
	for q in [[0.16, 0.085, 0.012], [0.18, 0.110, 0.026], [0.33, 0.110, 0.026], [0.35, 0.085, 0.012]]:
		pocket.append(_oval(q[0], q[1], q[2], 12, 0.305, 0.6))
	g.skin(pocket, true, "pack")
	g.cap("pack", pocket[0], Vector3.DOWN)
	g.cap("pack", pocket[-1], Vector3.UP)
	g.box("metal", Vector3(0, 0.345, 0.325), Vector3(0.08, 0.004, 0.004))                             # its zip
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		g.tube("strap", [Vector3(0.12 * sx2, 0.55, 0.15), Vector3(0.135 * sx2, 0.635, 0.03), Vector3(0.135 * sx2, 0.60, -0.10), Vector3(0.14 * sx2, 0.42, -0.142),
			Vector3(0.165 * sx2, 0.24, -0.09), Vector3(0.15 * sx2, 0.17, 0.12)], 0.017, 6)
		g.box("metal", Vector3(0.165 * sx2, 0.25, -0.10), Vector3(0.016, 0.012, 0.008))                    # buckles
	_show(_torso, g)

	_head = Node3D.new()
	_head.position = Vector3(0, 0.64, 0)
	_torso.add_child(_head)
	var hd = Shapes.Geo.new()
	hd.tube("skin", [Vector3(0, -0.05, 0.005), Vector3(0, 0.05, 0.0)], 0.047, 12)                      # neck
	hd.ball("skin", Vector3(0, 0.125, 0), Vector3(0.096, 0.122, 0.106), 18, 12)
	hd.ball("skin", Vector3(0, 0.06, -0.035), Vector3(0.070, 0.060, 0.075), 12, 6)                    # jaw and chin
	hd.ball("skin", Vector3(0, 0.108, -0.106), Vector3(0.015, 0.024, 0.022), 8, 5)                    # nose
	hd.box("dark", Vector3(0, 0.060, -0.103), Vector3(0.026, 0.0035, 0.004))                           # mouth
	for sgn in [-1.0, 1.0]:
		var sx3: float = sgn
		hd.ball("white", Vector3(0.037 * sx3, 0.140, -0.089), Vector3(0.016, 0.011, 0.010), 8, 4)         # eyes
		hd.ball("dark", Vector3(0.037 * sx3, 0.140, -0.097), Vector3(0.008, 0.008, 0.005), 8, 4)
		hd.box("hair", Vector3(0.037 * sx3, 0.160, -0.096), Vector3(0.020, 0.004, 0.004), Basis(Vector3.BACK, -0.12 * sx3))   # eyebrows
		hd.ball("skin", Vector3(0.097 * sx3, 0.120, 0.008), Vector3(0.012, 0.030, 0.020), 8, 5)            # ears
	hd.ball("hair", Vector3(0, 0.10, 0.055), Vector3(0.090, 0.075, 0.062), 12, 6)                     # hair showing under the beanie at the back
	# the beanie: a turned-up rim, a rounded crown and a bobble
	hd.lathe("beanie", Vector3(0, 0.168, 0.004), Vector3.UP, [Vector2(0.100, -0.012), Vector2(0.113, -0.008), Vector2(0.115, 0.040), Vector2(0.106, 0.048),
		Vector2(0.104, 0.085), Vector2(0.090, 0.122), Vector2(0.060, 0.150), Vector2(0.025, 0.163), Vector2(0.0, 0.166)], 20)
	hd.ball("beanie", Vector3(0, 0.355, 0.004), Vector3(0.036, 0.036, 0.036), 10, 6)
	_show(_head, hd)

	var leg := _limb(HIP * Vector3(-1, 1, 1), THIGH, SHIN, true, -1.0)
	_leg_l = leg[0]
	_knee_l = leg[1]
	leg = _limb(HIP, THIGH, SHIN, true, 1.0)
	_leg_r = leg[0]
	_knee_r = leg[1]
	var arm := _limb(SHOULDER * Vector3(-1, 1, 1), UPPER_ARM, FOREARM, false, -1.0)
	_arm_l = arm[0]
	_elbow_l = arm[1]
	arm = _limb(SHOULDER, UPPER_ARM, FOREARM, false, 1.0)
	_arm_r = arm[0]
	_elbow_r = arm[1]
## Two-bone reach: put the end of a limb (wrist or ankle) on `target`, with the hinge pushed toward `pole`.
## Everything is in the limb root's parent space.
func _reach(joint: Node3D, hinge: Node3D, target: Vector3, l1: float, l2: float, pole: Vector3) -> void:
	var d := target - joint.position
	var dist := clampf(d.length(), 0.05, l1 + l2 - 0.004)
	var dir := d.normalized()
	var axis := dir.cross(pole)
	if axis.length_squared() < 1e-6:
		axis = dir.cross(Vector3.RIGHT)
	axis = axis.normalized()
	var a := acos(clampf((l1 * l1 + dist * dist - l2 * l2) / (2.0 * l1 * dist), -1.0, 1.0))
	var inner := acos(clampf((l1 * l1 + l2 * l2 - dist * dist) / (2.0 * l1 * l2), -1.0, 1.0))
	var upper := dir.rotated(axis, a)
	var y := -upper
	joint.basis = Basis(axis, y, axis.cross(y))
	hinge.rotation = Vector3(-(PI - inner), 0.0, 0.0)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		yaw -= event.relative.x * MOUSE_SENS
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS, -1.35, 0.7)
	elif event is InputEventMouseButton and event.pressed:
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_arm.spring_length = maxf(1.8, _arm.spring_length - 0.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_arm.spring_length = minf(12.0, _arm.spring_length + 0.4)
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("interact"):
		_toggle_atv()
	elif event.is_action_pressed("fullscreen"):
		var w := get_window()
		w.mode = Window.MODE_WINDOWED if w.mode == Window.MODE_FULLSCREEN else Window.MODE_FULLSCREEN


## True when the player is on foot and close enough to get on the ATV.
func near_atv() -> bool:
	return not driving and _nearest_vehicle() != null


## The closest vehicle within reach, or null.
func _nearest_vehicle() -> Node3D:
	var best: Node3D = null
	var best_d := 1e9
	for v in (vehicles if not vehicles.is_empty() else [atv]):
		if v == null:
			continue
		var d: float = global_position.distance_to(v.global_position)
		if d < float(v.specs()["reach"]) and d < best_d:
			best_d = d
			best = v
	return best


## What the vehicle within reach is called (for the prompt on screen).
func vehicle_label() -> String:
	var v := atv if driving else _nearest_vehicle()
	return v.LABEL if v != null else ""


func _toggle_atv() -> void:
	if atv == null:
		return
	if not driving:
		var v := _nearest_vehicle()
		if v == null:
			return
		atv = v
		_spec = atv.specs()
		driving = true
		_heading = atv.global_rotation.y
		_course = _heading
		_cam_before = _arm.spring_length
		if float(_spec["camera"]) > 0.0:
			_arm.spring_length = _spec["camera"]
		_drive_speed = 0.0
		_atv_home = atv.get_parent()
		atv.set_parked(false)
		global_position = atv.global_position + Vector3(0, 0.1, 0)
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		_body.basis = Basis(Vector3.UP, _heading)
		atv.reparent(_body, false)
		atv.transform = Transform3D.IDENTITY
		_show_rider(not _spec["hides_rider"])
		if not _spec["hides_rider"]:
			_ride_pose()
	else:
		if _spec.get("flies", false) and (not (is_on_floor() or global_position.y <= WATER_LINE + 0.35) or velocity.length() > 1.5):
			return                                           # not while it is in the air
		driving = false
		floor_snap_length = 0.6
		var xf := _body.global_transform
		atv.reparent(_atv_home, false)
		atv.global_transform = Transform3D(Basis(Vector3.UP, _heading), xf.origin)
		atv.global_position.y = world.height_at(xf.origin.x, xf.origin.z)
		atv.reset_physics_interpolation()
		atv.park()
		atv.set_parked(true)
		_show_rider(true)
		if float(_spec["camera"]) > 0.0:
			_arm.spring_length = _cam_before
		# step off to the left
		var left := Basis(Vector3.UP, _heading) * Vector3(-float(_spec["exit"]), 0, 0)
		global_position += left + Vector3(0, 0.3, 0)
		velocity = Vector3.ZERO
		reset_physics_interpolation()
		_body.basis = Basis(Vector3.UP, _heading)
		_torso.transform = Transform3D(Basis(), Vector3(0, 0.95, 0))
		_head.rotation = Vector3.ZERO
		for limb in [[_leg_l, _knee_l, HIP * Vector3(-1, 1, 1)], [_leg_r, _knee_r, HIP], [_arm_l, _elbow_l, SHOULDER * Vector3(-1, 1, 1)], [_arm_r, _elbow_r, SHOULDER]]:
			limb[0].transform = Transform3D(Basis(), limb[2])
			limb[1].rotation = Vector3.ZERO


## The driver of a car sits inside it and is not drawn.
func _show_rider(on: bool) -> void:
	for part in _body.get_children():
		if part != atv and part is Node3D:
			part.visible = on
## Sit on the ATV: hips on the seat, feet on the rests, and the hands on the grips wherever the
## handlebars and the suspension have taken them.
func _ride_pose() -> void:
	var cx: Transform3D = atv.chassis_xf()
	var lean := 0.5
	var hips := Vector3(0.0, 0.90, 0.15)
	if atv.has_method("seat"):                         # a vehicle one sits in says where its seat is
		var st: Array = atv.seat()
		hips = st[0]
		lean = st[1]
	_torso.transform = cx * Transform3D(Basis(Vector3.RIGHT, -lean), hips)
	_head.rotation.x = lean * 0.75
	for side in [-1.0, 1.0]:
		var sd: float = side
		var leg: Node3D = _leg_l if sd < 0.0 else _leg_r
		var knee: Node3D = _knee_l if sd < 0.0 else _knee_r
		leg.position = cx * (hips + Vector3(0.15 * sd, 0.0, 0.02))
		_reach(leg, knee, atv.foot(sd), THIGH, SHIN, cx.basis * Vector3(0.45 * sd, 0.5, -1.0))
		var arm: Node3D = _arm_l if sd < 0.0 else _arm_r
		var elbow: Node3D = _elbow_l if sd < 0.0 else _elbow_r
		arm.position = _torso.transform * Vector3(0.28 * sd, 0.55, 0.0)
		_reach(arm, elbow, atv.grip(sd), UPPER_ARM, FOREARM + 0.05, cx.basis * Vector3(0.7 * sd, -1.0, 0.5))


func _drive(delta: float, iv: Vector2) -> void:
	# No glue: the ATV is carried by its own momentum. On the ground it runs along the surface;
	# when the ground falls away faster than gravity can follow — a crest, a ledge, a ramp — it flies.
	floor_snap_length = 0.0
	var grounded := is_on_floor()
	_air_time = 0.0 if grounded else _air_time + delta
	var contact := _air_time < 0.12                  # brief hops over small bumps still count as driving
	var in_water: bool = global_position.y <= WATER_LINE + 0.05
	var fwd := Vector3(-sin(_heading), 0.0, -cos(_heading))

	if contact or in_water:
		var throttle := -iv.y
		var fast: float = _spec["fast"]
		var top: float = fast if Input.is_action_pressed("sprint") else float(_spec["speed"])
		if in_water:
			top = 1.5
		var target := 0.0
		if throttle > 0.1:
			target = top * throttle
		elif throttle < -0.1:
			target = float(_spec["reverse"]) * throttle
		var rate := 3.0                                  # coasting
		if absf(target) > 0.1:
			if signf(target) != signf(_drive_speed) and absf(_drive_speed) > 0.5:
				rate = _spec["brake"]
			else:
				rate = float(_spec["power"]) * lerpf(1.0, 0.3, clampf(absf(_drive_speed) / fast, 0.0, 1.0))
		_drive_speed = move_toward(_drive_speed, target, rate * delta)
		# steering needs some speed, and gets calmer as it gets fast
		var grip := clampf(_drive_speed / 3.0, -1.0, 1.0)
		_heading -= iv.x * grip * delta * lerpf(2.2, 0.5, clampf(absf(_drive_speed) / fast, 0.0, 1.0))
		# Drifting (Space, in a vehicle that can): the rear wheels let go. The nose swings round quickly with the
		# steering while the car keeps travelling nearly the way it was going, scrubbing off speed as it slides.
		var sliding: bool = _spec["drift"] and Input.is_action_pressed("jump") and absf(_drive_speed) > 5.0 and not in_water
		if sliding:
			_heading -= iv.x * signf(_drive_speed) * delta * 1.1
			_course = lerp_angle(_course, _heading, minf(1.0, 0.9 * delta))
			_drive_speed = move_toward(_drive_speed, 0.0, (4.0 + 9.0 * absf(sin(angle_difference(_course, _heading)))) * delta)
		else:
			_course = lerp_angle(_course, _heading, minf(1.0, (5.0 if absf(angle_difference(_course, _heading)) > 0.06 else 40.0) * delta))
		var slip := angle_difference(_course, _heading)
		if absf(slip) > 1.2:                              # no further round than this: it would be going backwards
			_heading = _course + 1.2 * signf(slip)
			slip = 1.2 * signf(slip)
		atv.set_drift(sliding or (_spec["drift"] and absf(slip) > 0.25 and absf(_drive_speed) > 5.0), slip, _drive_speed)
		fwd = Vector3(-sin(_course), 0.0, -cos(_course))
	else:
		_heading -= iv.x * 0.5 * delta                 # a little twist in the air
		_course = lerp_angle(_course, _heading, minf(1.0, 2.0 * delta))
		fwd = Vector3(-sin(_course), 0.0, -cos(_course))
		atv.set_drift(false, 0.0, 0.0)

	if grounded:
		var n := get_floor_normal()
		var along := (fwd - n * fwd.dot(n)).normalized()
		velocity = along * _drive_speed - n * 0.6      # along the slope, pressed lightly onto it
	else:
		velocity.x = fwd.x * _drive_speed
		velocity.z = fwd.z * _drive_speed
		velocity.y -= GRAVITY * delta
	if _spec.get("bike", false):
		# The bicycle jumps: holding Space winds the jump up (rider and bike crouch), letting go lets it fly —
		# the longer it was held, the higher.
		if Input.is_action_pressed("jump") and contact:
			_hop = minf(_hop + delta / 0.65, 1.0)
		elif _hop > 0.0:
			if contact:
				velocity.y = 3.0 + 4.2 * _hop
				_air_time = 1.0
			_hop = 0.0
		atv.set_preload(_hop)
		atv.set_pedal(contact and Input.get_action_strength("move_forward") > 0.1 and _hop < 0.05)
	move_and_slide()
	if is_on_wall():
		# whatever it ran into takes the speed off
		var real := get_real_velocity()
		var kept := Vector3(real.x, 0.0, real.z).dot(fwd)
		if absf(kept) < absf(_drive_speed):
			_drive_speed = lerpf(_drive_speed, kept, 0.5)
	if global_position.y < WATER_LINE:
		global_position.y = WATER_LINE
		velocity.y = maxf(velocity.y, 0.0)
	var ground: float = world.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.3
		velocity.y = 0.0
	global_position.x = clampf(global_position.x, world.x0 + 30.0, world.x1 - 30.0)
	global_position.z = clampf(global_position.z, world.z0 + 30.0, world.z1 - 30.0)
	world.update_streaming(global_position)
	var want: Basis
	if contact:
		want = world.ground_basis(global_position.x, global_position.z, _heading)
	else:
		# in the air the nose follows the arc
		var hs := maxf(absf(_drive_speed), 3.0)
		want = Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, clampf(atan2(velocity.y, hs) * 0.7, -0.6, 0.6))
	_body.basis = _body.basis.orthonormalized().slerp(want.orthonormalized(), minf(1.0, 10.0 * delta))
	atv.animate(_drive_speed * cos(angle_difference(_course, _heading)), -iv.x, delta, [get_rid()])
	if not _spec["hides_rider"]:
		_ride_pose()


## Flying the helicopter. It has weight: with the rotor up to speed the lift just carries it, Space adds
## to the lift and Ctrl takes from it, and without lift it falls. It turns to where the mouse looks. WASD
## leans it, and it speeds up the way it leans; the air holds it back more the faster it goes, and takes
## the sideways slip out of it. On the ground it stands on its skids.
func _fly(delta: float, iv: Vector2) -> void:
	floor_snap_length = 0.0
	var rotor: float = atv.rotor
	var lift := smoothstep(0.55, 1.0, rotor)                  # no lift to speak of until the rotor is nearly up to speed
	var afloat: bool = global_position.y <= WATER_LINE + 0.35                # down on the sea: it floats on its skids
	var grounded := is_on_floor() or afloat
	var up := Input.get_action_strength("jump") - Input.get_action_strength("descend")
	# the nose follows the mouse, as fast as the tail rotor can swing it — and only with the rotor turning
	_heading = rotate_toward(_heading, yaw, (1.9 if not grounded else 0.6) * lift * delta)
	var fwd := Vector3(-sin(_heading), 0.0, -cos(_heading))
	var right := Vector3(cos(_heading), 0.0, -sin(_heading))
	var reach := 0.50 if Input.is_action_pressed("sprint") else 0.34
	var want := Vector2(iv.x, -iv.y) * reach * lift
	if grounded:
		want = Vector2.ZERO
	_lean = _lean.move_toward(want, 1.1 * delta)
	# forces, as accelerations: gravity, the rotor's lift (straight up from the leaning machine), the air
	var acc := Vector3(0.0, -GRAVITY, 0.0)
	var thrust := GRAVITY * lift * (1.0 + (0.42 * up if up > 0.0 else 0.40 * up))
	acc += Vector3.UP * thrust * cos(_lean.length())
	acc += (fwd * sin(_lean.y) + right * sin(_lean.x)) * thrust
	var hv := Vector3(velocity.x, 0.0, velocity.z)
	acc -= hv * (0.06 + 0.0045 * hv.length())                 # drag along the way it goes
	acc -= right * hv.dot(right) * 0.9                        # the fin and body resist slipping sideways
	acc.y -= velocity.y * 0.55                                # and the rotor disc resists rising and sinking
	if grounded and thrust < GRAVITY * 1.02:
		velocity = velocity.move_toward(Vector3.ZERO, 14.0 * delta)        # standing on the skids
		velocity.y = -0.5 if not afloat else 0.0
	else:
		velocity += acc * delta
	var fall := velocity.y
	move_and_slide()
	if is_on_floor() and fall < -1.0:
		velocity.x *= 0.5                                       # a landing takes the speed out of it
		velocity.z *= 0.5
	if global_position.y < WATER_LINE + 0.3:
		global_position.y = WATER_LINE + 0.3
		velocity.y = maxf(velocity.y, 0.0)
	var ground: float = world.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.3
		velocity.y = 0.0
	global_position.x = clampf(global_position.x, world.x0 + 30.0, world.x1 - 30.0)
	global_position.z = clampf(global_position.z, world.z0 + 30.0, world.z1 - 30.0)
	global_position.y = minf(global_position.y, 1500.0)
	world.update_streaming(global_position)
	_drive_speed = Vector3(velocity.x, 0.0, velocity.z).dot(fwd)
	var basis_want := Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, -_lean.y) * Basis(Vector3.BACK, -_lean.x)
	_body.basis = _body.basis.orthonormalized().slerp(basis_want.orthonormalized(), minf(1.0, 8.0 * delta))
	if not _spec["hides_rider"]:
		_ride_pose()


func _physics_process(delta: float) -> void:

	var iv := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	yaw -= look.x * 2.6 * delta
	pitch = clampf(pitch - look.y * 1.8 * delta, -1.35, 0.7)
	if driving:
		if _spec.get("flies", false):
			_fly(delta, iv)
		else:
			_drive(delta, iv)
		return

	var dir := Basis(Vector3.UP, yaw) * Vector3(iv.x, 0.0, iv.y)
	swimming = global_position.y <= WATER_LINE + 0.05 and world.height_at(global_position.x, global_position.z) < WATER_LINE

	var moving := iv.length() > 0.1
	if stamina <= 0.0:
		_exhausted = true
	elif stamina > 0.25:
		_exhausted = false
	var sprinting := moving and Input.is_action_pressed("sprint") and not _exhausted and not swimming
	stamina = clampf(stamina + (-0.11 if sprinting else 0.07) * delta, 0.0, 1.0)

	var speed := SWIM_SPEED if swimming else (SPRINT_SPEED if sprinting else WALK_SPEED)
	var grounded := is_on_floor() or swimming
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(dir * speed, (34.0 if grounded else 7.0) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED
	else:
		velocity.y -= GRAVITY * delta
	move_and_slide()

	# Float in the fjord instead of walking the seabed.
	if global_position.y < WATER_LINE:
		global_position.y = WATER_LINE
		velocity.y = maxf(velocity.y, 0.0)
	# Never fall through the world, never leave the map.
	var ground: float = world.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.3
		velocity.y = 0.0
	global_position.x = clampf(global_position.x, world.x0 + 30.0, world.x1 - 30.0)
	global_position.z = clampf(global_position.z, world.z0 + 30.0, world.z1 - 30.0)
	world.update_streaming(global_position)

	if dir.length() > 0.1:
		_body.rotation.y = lerp_angle(_body.rotation.y, atan2(-dir.x, -dir.z), minf(1.0, 12.0 * delta))
	_animate(delta, hv.length(), grounded)


func _animate(delta: float, speed: float, grounded: bool) -> void:
	_phase += speed * delta * 1.85
	var amount := clampf(speed / 4.5, 0.0, 1.3)
	var s := sin(_phase)
	var c := cos(_phase)
	var blend := minf(1.0, 14.0 * delta)
	# hips swing; the knee folds while its leg comes forward and straightens to take the weight
	var hip_l := s * 0.72 * amount
	var hip_r := -s * 0.72 * amount
	var knee_l := -(0.08 + 1.05 * maxf(0.0, c)) * amount
	var knee_r := -(0.08 + 1.05 * maxf(0.0, -c)) * amount
	var sh_l := -s * 0.6 * amount
	var sh_r := s * 0.6 * amount
	var el_l := 0.12 + (0.55 + 0.45 * maxf(0.0, -s)) * amount
	var el_r := 0.12 + (0.55 + 0.45 * maxf(0.0, s)) * amount
	if swimming:
		hip_l = s * 0.5
		hip_r = -s * 0.5
		knee_l = -0.3 - 0.3 * maxf(0.0, c)
		knee_r = -0.3 - 0.3 * maxf(0.0, -c)
		sh_l = 2.4 + s * 0.6
		sh_r = 2.4 - s * 0.6
		el_l = 0.3
		el_r = 0.3
	elif not grounded:
		hip_l = 0.55
		hip_r = 0.15
		knee_l = -0.9
		knee_r = -0.5
		sh_l = -0.5
		sh_r = 0.6
		el_l = 0.7
		el_r = 0.7
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, hip_l, blend)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, hip_r, blend)
	_knee_l.rotation.x = lerpf(_knee_l.rotation.x, knee_l, blend)
	_knee_r.rotation.x = lerpf(_knee_r.rotation.x, knee_r, blend)
	_arm_l.rotation.x = lerpf(_arm_l.rotation.x, sh_l, blend)
	_arm_r.rotation.x = lerpf(_arm_r.rotation.x, sh_r, blend)
	_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, el_l, blend)
	_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, el_r, blend)
	_torso.rotation.x = lerpf(_torso.rotation.x, -0.07 * amount - (0.9 if swimming else 0.0), 0.15)
	_torso.position.y = 0.95 + absf(s) * 0.035 * amount + sin(Time.get_ticks_msec() * 0.002) * 0.004


func _process(_delta: float) -> void:
	_pivot.global_position = get_global_transform_interpolated().origin + Vector3(0.0, 1.55, 0.0)
	_pivot.rotation = Vector3(pitch, yaw, 0.0)


## Compass bearing the camera is looking along, degrees clockwise from north.
func bearing() -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)
