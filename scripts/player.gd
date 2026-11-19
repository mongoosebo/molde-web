extends CharacterBody3D
## Third-person character: WASD to move, mouse to look, Shift to sprint, Space to jump.
## F gets on and off the ATV; on it, W/S is throttle and brake/reverse, A/D steers, Shift is full throttle.

const WALK_SPEED := 4.6
const SPRINT_SPEED := 7.8
const SWIM_SPEED := 1.7             # breaststroke
const CRAWL_SPEED := 3.3            # sprint swimming (Shift), on the same breath as running
const SWIM_DEPTH := 1.3             # water this deep is swum in; shallower is waded through
const JUMP_SPEED := 5.4
const GRAVITY := 16.0
const MOUSE_SENS := 0.0025
const WATER_LINE := -1.15          # the feet under the surface when floating: head and shoulders out
const ATV_SPEED := 25.0            # m/s, 90 km/h
const ATV_FAST := 38.0             # with Shift: about 135 km/h
const ATV_REVERSE := 8.0
const ATV_POWER := 17.0            # m/s² off the line, tailing off toward top speed
const ATV_BRAKE := 30.0
const ATV_REACH := 3.2

var world                           # scripts/world.gd
var sound                           # scripts/sound.gd (set by main; may be missing)
var stamina := 1.0
var yaw := 0.0
var pitch := -0.22
var swimming := false
var wading := 0.0                   # how deep the walker stands in water it cannot swim in, 0 to 1
var crawling := false               # sprint swimming
var under_water := false            # the camera is under the surface (scripts/hud.gd colours the view)
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
var _col: CollisionShape3D          # the walker's own shape
var _car_col: CollisionShape3D      # the shape of the vehicle being driven: its body, clear of the ground
var _wheel_pts: Array = []          # where the driven vehicle's tyres stand, in its own frame
var _vy := 0.0                      # the vehicle's speed up or down
var _ground_v := 0.0                # how fast the ground under the wheels is rising, evened out
var _ground_y := 0.0                # the ground under the wheels, last time
var _wheels_down := true
var _wet := false                   # in the water last step (to splash on going in)
var _stroke := 0.0                  # where in the swimming stroke the body is
var _climb := 0.0                   # climbing out of the water: seconds left
var _climb_time := 0.55             # how long this climb takes (longer the higher the edge)
var _climb_from := Vector3.ZERO
var _climb_to := Vector3.ZERO
var _splashes: Array = []           # a few bursts of spray, used in turn
var _splash_next := 0
var _trail: Array = []              # the last half second of driving: [time, ground under the wheels, upward speed the slope gave]
var _drive_t := 0.0
const JUMP_BOOST := 2.6             # how much of the climb it had is thrown into a jump when the ground falls away
var blocked_by := ""                # what last stood too high under a wheel to drive up (for the checks)
var _wheel_hit := ""
const BODY_CLEAR := 0.30            # nothing of a driven vehicle's hitbox reaches lower than this over the road

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
var _figure: Node3D
var _swim_pitch := 0.0              # how far the whole body lies forward (swimming), and how far it is rolled
var _swim_roll := 0.0
var _swim_sink := 0.0
var _ankle_l: Node3D
var _ankle_r: Node3D
var _gait := 0.0                    # where in the stride the legs are: 0 to 1, the left heel coming down at 0
var _air := 0.0                     # seconds off the ground
var _land := 0.0                    # seconds left of the crouch after landing
var _knee_r: Node3D
var _elbow_l: Node3D
var _elbow_r: Node3D

const THIGH := 0.46
const SHIN := 0.42
const UPPER_ARM := 0.33
const FOREARM := 0.31
const HIP := Vector3(0.12, 0.95, 0.0)
const SHOULDER := Vector3(0.250, 1.515, 0.0)
var _phase := 0.0
var _exhausted := false


func _ready() -> void:
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.6

	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.32
	capsule.height = 1.75
	_col = CollisionShape3D.new()
	_col.shape = capsule
	_col.position.y = 0.875
	add_child(_col)

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


const Body := preload("res://scripts/body.gd")        # the figure itself: shared with the people of the town

var body_triangles := 0                 # how many triangles the body is drawn with (./run.sh -- --body)


func _build_body() -> void:
	# A man of 42, 1.84 m, of Nordic looks: short brown hair, blue eyes, a few days' stubble; a little round in
	# front (and not as broad across the chest as he was: note of 18 Nov). A brown duck work jacket with a
	# corduroy collar, jeans, wheat-coloured work boots. Built by scripts/body.gd, at its finest cut.
	var b: Dictionary = Body.make({"sex": "m", "build": 1, "hair": "short", "detail": 1.0}, Body.materials())
	_body = Node3D.new()                     # turns the way he faces
	add_child(_body)
	_figure = b["root"]                      # and in it the figure itself, which lies forward in the water when he swims
	_body.add_child(_figure)
	_torso = b["torso"]
	_head = b["head"]
	_leg_l = b["leg_l"]
	_knee_l = b["knee_l"]
	_ankle_l = b["ankle_l"]
	_leg_r = b["leg_r"]
	_knee_r = b["knee_r"]
	_ankle_r = b["ankle_r"]
	_arm_l = b["arm_l"]
	_elbow_l = b["elbow_l"]
	_arm_r = b["arm_r"]
	_elbow_r = b["elbow_r"]
	body_triangles = b["triangles"]


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
			if not seat_view:
				_arm.spring_length = maxf(1.8, _arm.spring_length - 0.4)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if not seat_view:
				_arm.spring_length = minf(12.0, _arm.spring_length + 0.4)
	elif event.is_action_pressed("interact"):
		set_seat_view(false)
		_toggle_atv()
	elif event.is_action_pressed("view"):
		set_seat_view(not seat_view)
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


func _toggle_atv(force := false) -> void:
	if atv == null:
		return
	set_seat_view(false)
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
		_figure.transform = Transform3D.IDENTITY          # (upright again, if he was swimming)
		_swim_pitch = 0.0
		_swim_roll = 0.0
		_swim_sink = 0.0
		atv.reparent(_body, false)
		atv.transform = Transform3D.IDENTITY
		_show_rider(not _spec["hides_rider"])
		if not _spec["hides_rider"]:
			_ride_pose()
		if not _spec.get("flies", false):
			# From here on the vehicle is what is solid: its own body shape, held clear of the road, and it
			# stands on its tyres (see _drive). The walker's capsule is put away until he gets out.
			_wheel_pts = atv.wheel_points() if atv.has_method("wheel_points") else [Vector3(-0.5, 0, -0.8), Vector3(0.5, 0, -0.8), Vector3(-0.5, 0, 0.8), Vector3(0.5, 0, 0.8)]
			_car_col = CollisionShape3D.new()
			if atv.has_method("hull_shape") and _wheel_pts.size() >= 4:
				_car_col.shape = atv.hull_shape(BODY_CLEAR)
			else:
				var box := BoxShape3D.new()
				box.size = Vector3(0.5, 1.2, 1.7)
				_car_col.shape = box
				_car_col.position = Vector3(0, BODY_CLEAR + 0.6, 0)
			_car_col.basis = Basis(Vector3.UP, _heading)
			add_child(_car_col)
			_col.disabled = true
			motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
			_vy = 0.0
			_ground_v = 0.0
			_ground_y = global_position.y
			_trail.clear()
			_wheels_down = true
	else:
		if not force and _spec.get("flies", false) and (not (is_on_floor() or global_position.y <= _float_line(-WATER_LINE - 0.3, 0.6) + 0.05) or velocity.length() > 1.5):
			return                                           # not while it is in the air
		driving = false
		floor_snap_length = 0.6
		if _car_col != null:
			_car_col.queue_free()
			_car_col = null
			_col.disabled = false
			motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
		var xf := _body.global_transform
		atv.reparent(_atv_home, false)
		atv.global_transform = Transform3D(xf.basis.orthonormalized(), xf.origin)      # left leaning as the hill leans
		# (it stays where its tyres stood: on the asphalt, on a bridge deck, not on the bare ground under them)
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
		_ankle_l.rotation = Vector3.ZERO
		_ankle_r.rotation = Vector3.ZERO


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


## The height a floating thing's underside settles at here: the water's surface less `sink`, or far below
## everything where there is no water deep enough to float in.
func _float_line(sink: float, least_depth: float) -> float:
	var w: Dictionary = world.water_at(global_position.x, global_position.z)
	if w.is_empty() or w["depth"] < least_depth:
		return -1e9
	return w["level"] - sink


## Spray where something goes into the water, and a hard push on the ripples. `power` from 0 to 1.
func _splash(at: Vector3, power: float) -> void:
	if absf(at.y) < 0.2:
		return                                              # the sea (its surface is at 0) is kept still: no spray
	if _splashes.is_empty():
		for i in 3:
			var p := CPUParticles3D.new()
			p.emitting = false
			p.one_shot = true
			p.amount = 46
			p.lifetime = 0.9
			p.explosiveness = 0.95
			p.direction = Vector3.UP
			p.spread = 50.0
			p.gravity = Vector3(0, -9.0, 0)
			p.scale_amount_min = 0.5
			p.scale_amount_max = 1.3
			var quad := QuadMesh.new()
			quad.size = Vector2(0.12, 0.12)
			var m := StandardMaterial3D.new()
			m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.albedo_color = Color(0.86, 0.91, 0.93, 0.75)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			quad.material = m
			p.mesh = quad
			p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			p.top_level = true
			add_child(p)
			_splashes.append(p)
	var s: CPUParticles3D = _splashes[_splash_next]
	_splash_next = (_splash_next + 1) % _splashes.size()
	s.global_position = at
	s.initial_velocity_min = 1.2 + 2.0 * power
	s.initial_velocity_max = 2.6 + 4.5 * power
	s.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	s.emission_sphere_radius = 0.25 + 0.6 * power
	s.restart()
	s.emitting = true
	world.ripples.push(Vector2(at.x, at.z), 0.8 + 1.4 * power, 0.10 + 0.25 * power, 1.0)
	if sound != null:
		sound.play_at("splash_big" if power > 0.45 else "splash_small", at, 0.5 + 0.7 * power)


func _drive(delta: float, iv: Vector2) -> void:
	# No glue: the ATV is carried by its own momentum. On the ground it runs along the surface;
	# when the ground falls away faster than gravity can follow — a crest, a ledge, a ramp — it flies.
	floor_snap_length = 0.0
	var grounded := _wheels_down
	_air_time = 0.0 if grounded else _air_time + delta
	var contact := _air_time < 0.12                  # brief hops over small bumps still count as driving
	var afloat_at := _float_line(-WATER_LINE, 1.0)   # (water under a metre deep is driven through, on its bed)
	var in_water: bool = global_position.y <= afloat_at + 0.05
	var fwd := Vector3(-sin(_heading), 0.0, -cos(_heading))

	if contact or in_water:
		var throttle := -iv.y
		# slippery winter roads (the menu): the wheels take longer to follow the steering, and to stop
		var wt = get_parent().get("weather")
		var icy := 0.22 if (wt != null and wt.winter and wt.slippery and not _spec.get("flies", false)) else 1.0
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
				rate = float(_spec["brake"]) * (0.35 if icy < 1.0 else 1.0)
			else:
				rate = float(_spec["power"]) * lerpf(1.0, 0.3, clampf(absf(_drive_speed) / fast, 0.0, 1.0))
		_drive_speed = move_toward(_drive_speed, target, rate * delta)
		# steering needs some speed, and gets calmer as it gets fast
		var grip := clampf(_drive_speed / 3.0, -1.0, 1.0)
		_heading -= iv.x * grip * delta * lerpf(2.2, 0.5, clampf(absf(_drive_speed) / fast, 0.0, 1.0)) * float(_spec.get("turn", 1.0))      # (a bus turns wide)
		# Drifting (Space, in a vehicle that can): the rear wheels let go. The nose swings round quickly with the
		# steering while the car keeps travelling nearly the way it was going, scrubbing off speed as it slides.
		var sliding: bool = _spec["drift"] and Input.is_action_pressed("jump") and absf(_drive_speed) > 5.0 and not in_water
		if sliding:
			_heading -= iv.x * signf(_drive_speed) * delta * 1.1
			_course = lerp_angle(_course, _heading, minf(1.0, 0.9 * delta))
			_drive_speed = move_toward(_drive_speed, 0.0, (4.0 + 9.0 * absf(sin(angle_difference(_course, _heading)))) * delta)
		else:
			_course = lerp_angle(_course, _heading, minf(1.0, (5.0 if absf(angle_difference(_course, _heading)) > 0.06 else 40.0) * delta * icy))
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

	velocity = Vector3(fwd.x, 0.0, fwd.z) * _drive_speed * (cos(_body.basis.get_euler().x) if grounded else 1.0)
	if _spec.get("bike", false):
		# The bicycle jumps: holding Space winds the jump up (rider and bike crouch), letting go lets it fly —
		# the longer it was held, the higher.
		if Input.is_action_pressed("jump") and contact:
			_hop = minf(_hop + delta / 0.65, 1.0)
		elif _hop > 0.0:
			if contact:
				_vy = 3.0 + 4.2 * _hop
				_ground_v = _vy
				_air_time = 1.0
			_hop = 0.0
		atv.set_preload(_hop)
		atv.set_pedal(contact and Input.get_action_strength("move_forward") > 0.1 and _hop < 0.05)
	var before := global_position
	_car_col.basis = _body.basis.orthonormalized()     # the hitbox leans with the body: on a hill its nose is not in the road
	move_and_slide()
	var struck := false
	for ci in get_slide_collision_count():
		if absf(get_slide_collision(ci).get_normal().y) < 0.7:      # something upright: a wall, a post, another car
			struck = true
	if struck:
		# whatever it ran into takes the speed off
		var real := get_real_velocity()
		var kept := Vector3(real.x, 0.0, real.z).dot(fwd)
		if absf(kept) < absf(_drive_speed):
			_drive_speed = lerpf(_drive_speed, kept, 0.5)
	global_position.y = before.y                       # up and down is the wheels' business, below

	# The vehicle stands on its tyres: under each one the road is looked for, and the body rides at the height
	# and the lean those points give. A kerb or a lip under one wheel moves the body only a little and never
	# throws it; a ledge too high to drive up stops it like a wall.
	var hb := Basis(Vector3.UP, _heading)
	var grounds := _wheel_grounds(hb)
	var gy := 0.0
	for g in grounds:
		gy += g
	gy /= float(grounds.size())
	if gy - global_position.y > 0.55 and global_position.y > afloat_at + 0.1:
		blocked_by = "%s, %.2f m up" % [_wheel_hit, gy - global_position.y]
		global_position.x = before.x
		global_position.z = before.z
		_drive_speed *= 0.4
		grounds = _wheel_grounds(hb)
		gy = 0.0
		for g in grounds:
			gy += g
		gy /= float(grounds.size())
	# How fast the ground under the wheels is rising. Evened out only briefly: at speed, 0.05 s is a metre or two of road.
	_ground_v = lerpf(_ground_v, clampf((gy - _ground_y) / maxf(delta, 0.001), -12.0, 12.0), minf(1.0, delta / 0.05))
	_ground_y = gy
	# The upward speed the slope gives: the speed along the road times the slope the body stands at, nose to tail.
	# Over a crest or off the top of a bank the car keeps the climb it had a moment ago, and more, so it flies as it
	# should. A kerb or a lip (under about 20 cm of climb) gives nothing: those are evened out and never throw it.
	var ayf := 0.0; var ayr := 0.0; var azf := 0.0; var azr := 0.0
	var anf := 0; var anr := 0
	for i in _wheel_pts.size():
		if _wheel_pts[i].z < 0.0:
			ayf += grounds[i]; azf += _wheel_pts[i].z; anf += 1
		else:
			ayr += grounds[i]; azr += _wheel_pts[i].z; anr += 1
	var climbing := 0.0
	if anf > 0 and anr > 0:
		climbing = _drive_speed * (ayf / anf - ayr / anr) / maxf(azr / anr - azf / anf, 0.5)
	_drive_t += delta
	_trail.append([_drive_t, gy, climbing])
	while _trail.size() > 1 and _trail[0][0] < _drive_t - 0.5:
		_trail.pop_front()
	var low := gy
	var held := climbing
	for e in _trail:
		low = minf(low, e[1])
		if e[0] >= _drive_t - 0.3:
			held = maxf(held, e[2])
	var launch := _ground_v + JUMP_BOOST * smoothstep(0.2, 0.6, gy - low) * maxf(0.0, held - maxf(climbing, _ground_v) - 0.4)
	_vy -= GRAVITY * delta
	var ny := global_position.y + _vy * delta
	if ny <= gy + 0.01:
		ny = lerpf(global_position.y, gy, minf(1.0, 28.0 * delta)) if gy > global_position.y else gy
		_vy = minf(launch, 14.0)                        # carried up or down with the road: over a crest it flies
		_wheels_down = true
	else:
		_wheels_down = ny - gy < 0.06
	global_position.y = ny
	if global_position.y < afloat_at:
		global_position.y = afloat_at
		_vy = maxf(_vy, 0.0)
	# through water: the wheels push it aside, a wake behind, and a splash on going in
	var wv: Dictionary = world.water_at(global_position.x, global_position.z)
	var wet: bool = not wv.is_empty() and wv["depth"] > 0.08 and global_position.y < wv["level"] + 0.05
	if wet:
		var sp := absf(_drive_speed)
		world.ripples.push(Vector2(global_position.x, global_position.z) + Vector2(fwd.x, fwd.z) * 1.2, 1.4, 0.004 + 0.0022 * sp, clampf(sp / 9.0, 0.0, 1.0))
		world.ripples.push(Vector2(global_position.x, global_position.z) - Vector2(fwd.x, fwd.z) * 1.2, 1.2, 0.002 + 0.0012 * sp, clampf(sp / 14.0, 0.0, 0.8))
		if not _wet and (sp > 4.0 or _vy < -3.0):
			_splash(Vector3(global_position.x, wv["level"], global_position.z) + fwd * 1.5, clampf(sp / 22.0 + absf(_vy) / 14.0, 0.2, 1.0))
	_wet = wet
	var ground: float = world.height_at(global_position.x, global_position.z)
	if global_position.y < ground - 1.5:
		global_position.y = ground + 0.3
		_vy = 0.0
	global_position.x = clampf(global_position.x, world.x0 + 30.0, world.x1 - 30.0)
	global_position.z = clampf(global_position.z, world.z0 + 30.0, world.z1 - 30.0)
	world.update_streaming(global_position)
	var want: Basis
	if _air_time < 0.12:
		# nose and tail, left and right: the body leans as its wheels stand
		var yf := 0.0; var yr := 0.0; var yl := 0.0; var yrt := 0.0
		var nf := 0; var nr := 0; var nl := 0; var nrt := 0
		var zf := 0.0; var zr := 0.0; var xl := 0.0; var xr := 0.0
		for i in _wheel_pts.size():
			var p: Vector3 = _wheel_pts[i]
			if p.z < 0.0:
				yf += grounds[i]; zf += p.z; nf += 1
			else:
				yr += grounds[i]; zr += p.z; nr += 1
			if p.x < -0.05:
				yl += grounds[i]; xl += p.x; nl += 1
			elif p.x > 0.05:
				yrt += grounds[i]; xr += p.x; nrt += 1
		var f3 := hb * Vector3(0, 0, -1)
		var r3 := hb * Vector3(1, 0, 0)
		if nf > 0 and nr > 0:
			f3 = (f3 * (zr / nr - zf / nf) + Vector3(0, yf / nf - yr / nr, 0)).normalized()
		if nl > 0 and nrt > 0:
			r3 = (r3 * (xr / nrt - xl / nl) + Vector3(0, yrt / nrt - yl / nl, 0)).normalized()
		var up3 := r3.cross(f3).normalized()
		want = Basis(f3.cross(up3).normalized(), up3, -f3).orthonormalized()
	else:
		# in the air the nose follows the arc
		var hs := maxf(absf(_drive_speed), 3.0)
		want = Basis(Vector3.UP, _heading) * Basis(Vector3.RIGHT, clampf(atan2(_vy, hs) * 0.7, -0.6, 0.6))
	_body.basis = _body.basis.orthonormalized().slerp(want.orthonormalized(), minf(1.0, 10.0 * delta))
	atv.animate(_drive_speed * cos(angle_difference(_course, _heading)), -iv.x, delta, [get_rid()])
	if not _spec["hides_rider"]:
		_ride_pose()


## The road under each tyre of the driven vehicle: what a ray straight down from above the wheel meets (asphalt,
## a kerb, a bridge deck), or the bare ground where it meets nothing.
func _wheel_grounds(hb: Basis) -> Array:
	var space := get_world_3d().direct_space_state
	var out := []
	for p in _wheel_pts:
		var wp: Vector3 = global_position + hb * p
		var q := PhysicsRayQueryParameters3D.create(wp + Vector3(0, 0.9, 0), wp - Vector3(0, 2.0, 0))
		q.exclude = [get_rid()]
		var hit := space.intersect_ray(q)
		out.append(hit["position"].y if not hit.is_empty() else world.height_at(wp.x, wp.z))
		if not hit.is_empty() and hit["position"].y > global_position.y + 0.4:
			var par: Node = hit["collider"].get_parent()
			_wheel_hit = "%s/%s" % [par.get_parent().name if par.get_parent() != null else "", par.name]
	return out


func wheels_down() -> bool:
	return _wheels_down


## Flying the helicopter. It has weight: with the rotor up to speed the lift just carries it, Space adds
## to the lift and Ctrl takes from it, and without lift it falls. It turns to where the mouse looks. WASD
## leans it, and it speeds up the way it leans; the air holds it back more the faster it goes, and takes
## the sideways slip out of it. On the ground it stands on its skids.
func _fly(delta: float, iv: Vector2) -> void:
	floor_snap_length = 0.0
	var rotor: float = atv.rotor
	var lift := smoothstep(0.55, 1.0, rotor)                  # no lift to speak of until the rotor is nearly up to speed
	var heli_line := _float_line(-WATER_LINE - 0.3, 0.6)
	var afloat: bool = global_position.y <= heli_line + 0.05                 # down on the water: it floats on its skids
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
	if global_position.y < heli_line:
		global_position.y = heli_line
		velocity.y = maxf(velocity.y, 0.0)
	if global_position.y < heli_line + 3.0 and lift > 0.5:      # the downwash on the water
		world.ripples.push(Vector2(global_position.x, global_position.z), 3.5, 0.006 * lift, 0.25)
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
	world.ripples.step(global_position, delta)

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
	# The water here (the sea, a lake or a river): deep enough, it is swum in; shallower, it is waded through,
	# slower the deeper it is. Running water carries a swimmer along, so upstream is hard work.
	var w: Dictionary = world.water_at(global_position.x, global_position.z)
	var level: float = w.get("level", -1e9)
	var depth: float = w.get("depth", 0.0)
	var flow: Vector2 = w.get("flow", Vector2.ZERO)
	var bob := sin(Time.get_ticks_msec() * 0.0021) * 0.035 + sin(Time.get_ticks_msec() * 0.0034 + 1.3) * 0.02
	var float_y := level + WATER_LINE + bob
	swimming = depth >= SWIM_DEPTH and global_position.y <= float_y + 0.12
	wading = 0.0 if swimming else clampf((level - global_position.y) / SWIM_DEPTH, 0.0, 1.0)
	if _climb > 0.0:
		# climbing out: up over the edge and onto it, in half a second
		_climb -= delta
		var t := 1.0 - clampf(_climb / _climb_time, 0.0, 1.0)
		global_position = Vector3(lerpf(_climb_from.x, _climb_to.x, smoothstep(0.35, 1.0, t)), lerpf(_climb_from.y, _climb_to.y, smoothstep(0.0, 0.75, t)),
			lerpf(_climb_from.z, _climb_to.z, smoothstep(0.35, 1.0, t)))
		velocity = Vector3.ZERO
		world.update_streaming(global_position)
		_animate(delta, 0.0, false)
		return

	var moving := iv.length() > 0.1
	if stamina <= 0.0:
		_exhausted = true
	elif stamina > 0.25:
		_exhausted = false
	var sprinting := moving and Input.is_action_pressed("sprint") and not _exhausted
	crawling = swimming and sprinting
	stamina = clampf(stamina + (-0.11 if sprinting else 0.07) * delta, 0.0, 1.0)

	var speed := (CRAWL_SPEED if crawling else SWIM_SPEED) if swimming else (SPRINT_SPEED if sprinting else WALK_SPEED) * lerpf(1.0, 0.32, wading)
	var grounded := is_on_floor() or swimming
	var want := dir * speed
	if swimming:
		want += Vector3(flow.x, 0.0, flow.y)
	elif wading > 0.3:
		want += Vector3(flow.x, 0.0, flow.y) * (wading - 0.3)
	var hv := Vector3(velocity.x, 0.0, velocity.z).move_toward(want, ((9.0 if swimming else 34.0) if grounded else 7.0) * delta)
	velocity.x = hv.x
	velocity.z = hv.z
	if swimming:
		# floating: the body rides at the surface; Space gives a small kick up, for getting onto an edge
		velocity.y = move_toward(velocity.y, 0.0, 10.0 * delta)
		if Input.is_action_just_pressed("jump"):
			velocity.y = 3.2
			world.ripples.push(Vector2(global_position.x, global_position.z), 0.9, 0.05, 0.7)
		if global_position.y > float_y:
			velocity.y -= GRAVITY * 0.5 * delta
	elif is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = JUMP_SPEED * lerpf(1.0, 0.45, wading)
	else:
		velocity.y -= GRAVITY * delta
	var fall := velocity.y
	move_and_slide()

	# Float instead of walking the bed.
	if depth >= SWIM_DEPTH and global_position.y < float_y:
		global_position.y = move_toward(global_position.y, float_y, 4.0 * delta) if global_position.y > float_y - 0.4 else float_y
		velocity.y = maxf(velocity.y, 0.0)
	# What the body does to the water: pushed aside while wading and swimming, a splash on going in.
	var wet: bool = depth > 0.1 and global_position.y < level - 0.05
	if wet:
		var here := Vector2(global_position.x, global_position.z)
		var sp := Vector2(velocity.x - flow.x, velocity.z - flow.y).length()
		world.ripples.push(here, 0.55, 0.0015 + 0.0045 * sp, 0.55 if crawling else clampf(sp / 9.0, 0.0, 0.3))
		if swimming and sp > 0.3 and sin(_stroke) > 0.92:          # the pull of each stroke
			world.ripples.push(here + Vector2(dir.x, dir.z) * 0.5, 0.7, 0.012, 0.35 if crawling else 0.1)
		if not _wet and (fall < -3.0 or sp > 5.0):
			_splash(Vector3(global_position.x, level, global_position.z), clampf(absf(fall) / 12.0 + sp / 16.0, 0.15, 1.0))
	_wet = wet
	# Out of the water: where the ground or the edge of a quay ahead is within reach of the surface, a short climb.
	if swimming and moving and (is_on_wall() or depth < SWIM_DEPTH + 0.25):
		var ahead := global_position + dir.normalized() * 0.75
		var q := PhysicsRayQueryParameters3D.create(Vector3(ahead.x, level + 2.8, ahead.z), Vector3(ahead.x, level - 0.4, ahead.z))
		q.exclude = [get_rid()]
		var hit := get_world_3d().direct_space_state.intersect_ray(q)
		var top: float = hit["position"].y if not hit.is_empty() else world.height_at(ahead.x, ahead.z)
		var wa: Dictionary = world.water_at(ahead.x, ahead.z)
		# (a beach or a low edge is half a second; a quay standing a couple of metres over the water is a real climb)
		if top - level <= 2.3 and top > level - 0.35 and (wa.is_empty() or wa["depth"] < 0.6 or not hit.is_empty()) and top > global_position.y + 0.5:
			_climb_time = 0.55 + 0.6 * maxf(top - level - 0.7, 0.0)
			_climb = _climb_time
			_climb_from = global_position
			_climb_to = Vector3(ahead.x, top + 0.05, ahead.z)
			swimming = false
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


## The stride, measured off people walking and sprinting: the angle of the hip (forward is positive), how far the
## knee is bent and the angle of the ankle (toes up is positive) at twelve moments of one stride of one leg, from
## its heel coming down. The other leg is half a stride behind. Between the walk and the sprint the body runs at
## something of both.
const WALK := {"hip": [0.40, 0.33, 0.22, 0.10, -0.03, -0.17, -0.29, -0.30, -0.10, 0.18, 0.40, 0.45],
	"knee": [0.06, 0.24, 0.18, 0.09, 0.06, 0.10, 0.30, 0.72, 1.08, 0.95, 0.45, 0.10],
	"ankle": [0.05, -0.12, 0.0, 0.08, 0.14, 0.18, 0.05, -0.32, -0.20, -0.02, 0.06, 0.08]}
const SPRINT := {"hip": [0.62, 0.40, 0.12, -0.18, -0.45, -0.62, -0.50, -0.10, 0.45, 0.90, 1.02, 0.85],
	"knee": [0.42, 0.62, 0.50, 0.35, 0.28, 0.55, 1.25, 1.90, 2.05, 1.60, 0.95, 0.50],
	"ankle": [0.10, 0.22, 0.15, -0.10, -0.42, -0.50, -0.30, -0.10, 0.05, 0.10, 0.10, 0.10]}


## The value of one of those curves at a moment of the stride (t from 0 to 1, round and round), smoothly between its twelve.
func _stride(curve: Array, t: float) -> float:
	var x := fposmod(t, 1.0) * 12.0
	var i := int(x)
	var f := x - float(i)
	var p0: float = curve[(i + 11) % 12]
	var p1: float = curve[i % 12]
	var p2: float = curve[(i + 1) % 12]
	var p3: float = curve[(i + 2) % 12]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f)


func _animate(delta: float, speed: float, grounded: bool) -> void:
	_phase += speed * delta * 1.85
	var amount := clampf(speed / 1.2, 0.0, 1.0)            # (standing still the limbs hang; they take up the stride over the first metre a second)
	var run := 0.45 * smoothstep(1.5, 4.2, speed) + 0.55 * smoothstep(5.0, 7.4, speed)      # 0 a walk, 1 a sprint
	_gait = fposmod(_gait + speed * delta / lerpf(1.5, 3.6, run), 1.0)
	var blend := minf(1.0, 14.0 * delta)
	# each leg: hip, knee and ankle from where it is in its stride
	var hip_l := lerpf(_stride(WALK["hip"], _gait), _stride(SPRINT["hip"], _gait), run) * amount
	var hip_r := lerpf(_stride(WALK["hip"], _gait + 0.5), _stride(SPRINT["hip"], _gait + 0.5), run) * amount
	var knee_l := -lerpf(_stride(WALK["knee"], _gait), _stride(SPRINT["knee"], _gait), run) * amount
	var knee_r := -lerpf(_stride(WALK["knee"], _gait + 0.5), _stride(SPRINT["knee"], _gait + 0.5), run) * amount
	var ank_l := lerpf(_stride(WALK["ankle"], _gait), _stride(SPRINT["ankle"], _gait), run) * amount
	var ank_r := lerpf(_stride(WALK["ankle"], _gait + 0.5), _stride(SPRINT["ankle"], _gait + 0.5), run) * amount
	# each arm swings with the leg of the other side, the elbow bent more the faster it goes and as the arm comes forward
	var sh_l := hip_r * lerpf(0.60, 0.95, run) - 0.12 * amount       # (a little behind the body on the whole: the arms are not held out in front)
	var sh_r := hip_l * lerpf(0.60, 0.95, run) - 0.12 * amount
	var el_l := 0.10 + (lerpf(0.20, 1.35, run) + lerpf(0.30, 0.35, run) * maxf(0.0, sh_l)) * amount
	var el_r := 0.10 + (lerpf(0.20, 1.35, run) + lerpf(0.30, 0.35, run) * maxf(0.0, sh_r)) * amount
	# the body: lowest as each heel comes down, turning a little against the legs, leaning into a run
	var bob := -cos(_gait * TAU * 2.0) * lerpf(0.014, 0.040, run) * amount
	var twist := sin(_gait * TAU) * lerpf(0.06, 0.14, run) * amount
	var sway := sin(_gait * TAU) * 0.025 * amount
	var drop := 0.0
	var spread := 0.0                                   # arms and legs out to the side (only in the water)
	var tip := -lerpf(0.04, 0.20, run) * amount          # how far the body tips forward
	var lie := 0.0                                      # the whole figure laid forward in the water, rolled about its length, sunk
	var roll := 0.0
	var sink := 0.0
	var head_x := 0.0                                   # the head lifted (to look ahead when lying flat), turned (to breathe)
	var head_y := 0.0
	var leg_out := -1.0                                 # the legs out to the side (the frog kick); -1: half of what the arms do
	var in_water := swimming or _climb > 0.0
	if in_water:
		ank_l = -0.45                                       # feet pointed
		ank_r = -0.45
		bob = 0.0
		twist = 0.0
		sway = 0.0
	if _climb > 0.0:
		# hauling out over an edge: arms up and forward, knees coming up
		sh_l = 2.6; sh_r = 2.6; el_l = 0.5; el_r = 0.5
		hip_l = 0.9; hip_r = 0.2; knee_l = -1.2; knee_r = -0.4
		tip = -0.5
	elif swimming and crawling:
		# Crawl. The body lies flat in the surface, face down, rolling a little toward the arm that pulls. Each arm
		# goes right round: in ahead of the head, down and back under the body to the hip (the pull), then out and
		# forward over the water with the elbow high (the recovery); the other arm half a turn behind. The legs
		# flutter from the hip, six beats to a turn of the arms, toes pointed. The head turns to the side of the
		# recovering left arm to breathe.
		_stroke += delta * 5.4
		var ph := fposmod(_stroke, TAU)
		sh_l = PI - ph
		sh_r = PI - fposmod(ph + PI, TAU)
		el_l = 0.28 + 1.20 * maxf(0.0, -sin(ph))
		el_r = 0.28 + 1.20 * maxf(0.0, sin(ph))
		hip_l = 0.24 * sin(_stroke * 3.0)
		hip_r = -hip_l
		knee_l = -0.10 - 0.24 * maxf(0.0, sin(_stroke * 3.0))
		knee_r = -0.10 - 0.24 * maxf(0.0, -sin(_stroke * 3.0))
		lie = -1.43
		roll = 0.36 * sin(ph)
		sink = -0.06
		tip = 0.05
		head_x = 0.22
		head_y = 1.05 * pow(maxf(0.0, -sin(ph)), 1.5)
	elif swimming and speed > 0.4:
		# Breaststroke, in four parts. The pull: the arms sweep out and back and the head comes up to breathe.
		# The recovery: the hands come in under the chest and shoot forward while the heels are drawn up to the
		# seat, knees apart. The kick: the legs whip out, back and together. The glide: stretched out, face down.
		_stroke += delta * 3.3
		var ph2 := fposmod(_stroke, TAU) / TAU
		var pull := smoothstep(0.0, 0.12, ph2) * (1.0 - smoothstep(0.24, 0.40, ph2))
		var tuck := smoothstep(0.20, 0.32, ph2) * (1.0 - smoothstep(0.38, 0.52, ph2))
		var draw := smoothstep(0.26, 0.46, ph2) * (1.0 - smoothstep(0.50, 0.60, ph2))
		var whip := smoothstep(0.48, 0.56, ph2) * (1.0 - smoothstep(0.60, 0.74, ph2))
		var breath := smoothstep(0.04, 0.18, ph2) * (1.0 - smoothstep(0.30, 0.46, ph2))
		sh_l = 3.05 - 1.55 * pull - 0.70 * tuck
		sh_r = sh_l
		el_l = 0.08 + 0.45 * pull + 1.90 * tuck
		el_r = el_l
		spread = 0.95 * pull * (1.0 - tuck)
		hip_l = 0.85 * draw
		hip_r = hip_l
		knee_l = -0.08 - 1.80 * draw
		knee_r = knee_l
		leg_out = 0.55 * draw + 0.45 * whip
		ank_l = lerpf(-0.45, 0.40, maxf(draw, whip))             # the feet turned out and flexed to push; pointed in the glide
		ank_r = ank_l
		lie = -1.36 + 0.22 * breath
		sink = -0.12 + 0.10 * breath
		tip = 0.04 + 0.10 * breath
		head_x = 0.45 + 0.55 * breath
	elif swimming:
		# treading water: upright, the arms sculling out to the sides, the legs pedalling slowly
		_stroke += delta * 3.0
		sh_l = 1.15 + 0.25 * sin(_stroke)
		sh_r = 1.15 - 0.25 * sin(_stroke)
		el_l = 0.35
		el_r = 0.35
		spread = 0.9 + 0.2 * cos(_stroke)
		hip_l = 0.35 + 0.35 * sin(_stroke * 0.8)
		hip_r = 0.35 - 0.35 * sin(_stroke * 0.8)
		knee_l = -0.7 - 0.4 * cos(_stroke * 0.8)
		knee_r = -0.7 + 0.4 * cos(_stroke * 0.8)
		lie = -0.10
		tip = -0.04
	elif not grounded:
		# A jump, in three parts by how fast the body is rising or falling. Up: one knee driven up and the other
		# leg trailing with its toes pointed, the arms thrown up. Over the top: both knees drawn up. Down: the
		# legs reaching for the ground, toes first, knees soft, the arms out for balance.
		_air += delta
		var vy := velocity.y
		var up := smoothstep(0.6, 2.4, vy)
		var down := smoothstep(0.6, 2.4, -vy)
		var top := 1.0 - up - down
		hip_l = 0.80 * up + 0.85 * top + 0.30 * down
		hip_r = -0.25 * up + 0.65 * top + 0.12 * down
		knee_l = -(1.25 * up + 1.35 * top + 0.35 * down)
		knee_r = -(0.35 * up + 1.15 * top + 0.22 * down)
		ank_l = -0.30 * up + 0.05 * top - 0.25 * down
		ank_r = -0.55 * up + 0.05 * top - 0.25 * down
		sh_l = 1.50 * up + 1.00 * top + 0.50 * down
		sh_r = 1.10 * up + 0.80 * top + 0.50 * down
		el_l = 0.50 * up + 0.60 * top + 0.35 * down
		el_r = 0.50 * up + 0.60 * top + 0.35 * down
		spread = 0.35 * top + 0.55 * down
		tip = -0.12 * up - 0.05 * down
		bob = 0.0
		twist = 0.0
		sway = 0.0
	else:
		if _air > 0.25:
			_land = 0.30                                        # down from a real jump or a drop: the knees take it
		_air = 0.0
	if _land > 0.0 and grounded and not in_water:
		# landing: knees, hips and ankles give, the body sinks and tips forward, the arms swing back; then up again
		_land = maxf(_land - delta, 0.0)
		var give := sin(clampf(_land / 0.30, 0.0, 1.0) * PI * 0.5)
		hip_l += 0.55 * give
		hip_r += 0.55 * give
		knee_l -= 1.00 * give
		knee_r -= 1.00 * give
		ank_l += 0.42 * give
		ank_r += 0.42 * give
		sh_l -= 0.5 * give
		sh_r -= 0.5 * give
		tip -= 0.25 * give
		drop = 0.10 * give
	_leg_l.rotation.x = lerpf(_leg_l.rotation.x, hip_l, blend)
	_leg_r.rotation.x = lerpf(_leg_r.rotation.x, hip_r, blend)
	_knee_l.rotation.x = lerpf(_knee_l.rotation.x, knee_l, blend)
	_knee_r.rotation.x = lerpf(_knee_r.rotation.x, knee_r, blend)
	_arm_l.rotation.x = lerp_angle(_arm_l.rotation.x, sh_l, blend)       # (by the short way round: in the crawl an arm goes right round)
	_arm_r.rotation.x = lerp_angle(_arm_r.rotation.x, sh_r, blend)
	_elbow_l.rotation.x = lerpf(_elbow_l.rotation.x, el_l, blend)
	_elbow_r.rotation.x = lerpf(_elbow_r.rotation.x, el_r, blend)
	_arm_l.rotation.z = lerpf(_arm_l.rotation.z, -spread, blend)
	_arm_r.rotation.z = lerpf(_arm_r.rotation.z, spread, blend)
	if leg_out < 0.0:
		leg_out = spread * 0.5
	_leg_l.rotation.z = lerpf(_leg_l.rotation.z, -leg_out, blend)
	_leg_r.rotation.z = lerpf(_leg_r.rotation.z, leg_out, blend)
	_head.rotation.x = lerpf(_head.rotation.x, head_x, blend)
	_head.rotation.y = lerpf(_head.rotation.y, head_y, blend)
	# the whole figure laid forward about its chest, so that swimming it lies in the surface of the water
	_swim_pitch = lerpf(_swim_pitch, lie, minf(1.0, 5.0 * delta))
	_swim_roll = lerpf(_swim_roll, roll, minf(1.0, 10.0 * delta))
	_swim_sink = lerpf(_swim_sink, sink, minf(1.0, 5.0 * delta))
	var laid := Basis(Vector3.RIGHT, _swim_pitch) * Basis(Vector3.UP, _swim_roll)
	var chest := Vector3(0, 1.18, 0)
	_figure.transform = Transform3D(laid, chest - laid * chest + Vector3(0, _swim_sink, 0))
	_ankle_l.rotation.x = lerpf(_ankle_l.rotation.x, clampf(ank_l, -0.6, 0.5), blend)
	_ankle_r.rotation.x = lerpf(_ankle_r.rotation.x, clampf(ank_r, -0.6, 0.5), blend)
	_torso.rotation.x = lerpf(_torso.rotation.x, tip, 0.15)
	_torso.rotation.y = lerpf(_torso.rotation.y, twist, blend)
	_torso.rotation.z = lerpf(_torso.rotation.z, sway, blend)
	_torso.position.y = lerpf(_torso.position.y, 0.95 + bob - drop + sin(Time.get_ticks_msec() * 0.002) * 0.004, minf(1.0, 20.0 * delta))
	# the arms hang from the shoulders wherever the body has leant or turned them to, and the hips go down and up with the body
	var at_shoulder := SHOULDER - Vector3(0, 0.95, 0)
	_arm_r.position = _torso.transform * at_shoulder
	_arm_l.position = _torso.transform * (at_shoulder * Vector3(-1, 1, 1))
	_leg_l.position.y = HIP.y + _torso.position.y - 0.95
	_leg_r.position.y = HIP.y + _torso.position.y - 0.95


## Q: the view from the seat of what is being driven, and back to the view from behind. From the seat the
## mouse still looks round; the camera sits where the driver's eyes are and follows the vehicle as it leans.
var seat_view := false
var _seat_arm := 0.0


func set_seat_view(on: bool) -> void:
	if on == seat_view or (on and not driving):
		return
	seat_view = on
	if on:
		_seat_arm = _arm.spring_length
		_arm.spring_length = 0.0
		_cam.h_offset = 0.0
		yaw = _heading
		pitch = -0.06
	else:
		_arm.spring_length = _seat_arm
		_cam.h_offset = 0.45


func _process(_delta: float) -> void:
	if seat_view and not driving:
		set_seat_view(false)
	if seat_view:
		var eye: Vector3 = atv.eye() if atv.has_method("eye") else Vector3(0.0, 1.62, 0.12)
		_pivot.global_position = get_global_transform_interpolated() * (_body.transform * eye)
	else:
		_pivot.global_position = get_global_transform_interpolated().origin + Vector3(0.0, 1.55, 0.0)
	_pivot.rotation = Vector3(pitch, yaw, 0.0)
	# The camera stays over the water while swimming; if it does dip under, the view is coloured (scripts/hud.gd).
	var cw: Dictionary = world.water_at(_cam.global_position.x, _cam.global_position.z) if world != null else {}
	under_water = false
	if not cw.is_empty() and cw["depth"] > 0.3:
		if swimming and _cam.global_position.y < cw["level"] + 0.3:
			_pivot.global_position.y += cw["level"] + 0.3 - _cam.global_position.y
		under_water = _cam.global_position.y < cw["level"] - 0.02


## Compass bearing the camera is looking along, degrees clockwise from north.
func bearing() -> float:
	return fposmod(-rad_to_deg(yaw), 360.0)
