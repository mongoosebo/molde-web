extends Node3D
## A white saloon after the Volvo 740: the long, square three-box shape, black bumpers and grille, 17 inch
## rims. Parked, it is a solid object; the player gets in with F and then carries it along
## (scripts/player.gd does the driving, as for the ATV). Faces -Z.
##
## Suspension like the ATV's, a bit stiffer: each wheel follows the ground under it and the body sits on
## springs. On the rear wing stands a whip aerial with a fox tail tied to it; the aerial sways on a spring
## and the tail is a chain of points that hang, swing and stream out behind under their own weight and the
## air. Holding Space at speed breaks the rear wheels loose (see player.gd), and then they pour out smoke.

# What makes this car this car. Another car is the same script with other numbers here (set in _init) and
# its own details (_build_details): see scripts/integra.gd.
var LABEL := "the Volvo"
var SPECS := {"speed": 36.0, "fast": 52.0, "reverse": 9.0, "power": 10.5, "brake": 30.0, "reach": 3.6,
	"drift": true, "hides_rider": true, "exit": 1.9, "camera": 6.6}

var WHEEL_R := 0.318              # a 225/45 tyre on a 17 inch rim
var RIM_R := 0.216                # 17 inches across
const TRAVEL_UP := 0.10
const TRAVEL_DOWN := 0.09
var ARCH_R := 0.385               # the wheel arches
var TRACK := 0.74                 # half the distance between the wheels of an axle
var AXLE_F := -1.42
var AXLE_R := 1.35
var HALF_LEN := 2.36              # nose and tail, from the middle
var TOP_LINE := [Vector2(-2.36, 0.83), Vector2(-2.31, 0.905), Vector2(-1.02, 0.965), Vector2(-0.40, 1.435), Vector2(0.30, 1.447),
	Vector2(0.95, 1.435), Vector2(1.52, 1.005), Vector2(2.30, 0.985), Vector2(2.36, 0.91)]      # the car from the side: (z, height of its top)
var CABIN := Vector2(-1.02, 1.52)             # where the glasshouse stands on the body
var BELT := Vector2(0.965, 1.005)             # the height of the sills of the side windows, front and rear
var HALF_W := 0.835                           # half the width at the window sills
var ROOF_W := 0.70                            # and at the roof
var GLASS_H := 0.42                           # the height of glass over which the sides lean in that far
var FLANK := [Vector2(0.850, -0.045), Vector2(0.868, 0.80), Vector2(0.872, 0.70), Vector2(0.872, 0.60), Vector2(0.884, 0.588),
	Vector2(0.884, 0.528), Vector2(0.872, 0.516), Vector2(0.868, 0.42), Vector2(0.858, 0.33)]   # the side below the windows: (half width, height; a negative height is measured down from the window sill)
var STRIP := true                             # a black rubbing strip along the flank (its 5th to 7th points)
var SILL := 0.27                              # the underside, and how far it rises under nose and tail
var OVERHANG := 0.36
var SCREENS := [Vector2(-0.97, -0.44), Vector2(0.99, 1.47)]     # windscreen and rear window, along the car
var SIDE_GLASS := Vector2(-0.70, 1.20)
var PILLARS := [Vector2(0.17, 0.27)]          # black pillars between the side windows
var PAINT_SHADER := "res://shaders/car_paint.gdshader"
var BODY_BOX := Vector3(1.78, 1.25, 4.8)      # for bumping into when parked
var AERIAL_LEN := 0.95
var PAINT := Color(0.93, 0.93, 0.90)
var CORNER := 0.045                           # how round the edge of the roof and the shoulders are
var CROWN := 0.012                            # how much higher the middle of the top is than its edges
var SQUEEZE := 0.075                          # how much narrower the very nose and tail are than the body
var SQUEEZE_LEN := 0.24                       # and over what length they narrow
var END_FINE := 0.06                          # the length at each end where the outline is taken more closely
var SQUEEZE_TAIL := -1.0                      # the same for the tail alone, if it differs from the nose (negative: it does not)
var FOX_TAIL := true
const TAIL_POINTS := 7
const TAIL_LINK := 0.085

var _chassis: Node3D
var _col: CollisionShape3D
var _wheels: Array = []          # [hub, spinning part, is_front, rest position]
var _spin := 0.0
var _rear_spin := 0.0
var _steer := 0.0
var _offsets := [0.0, 0.0, 0.0, 0.0]

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

var _aerial: MeshInstance3D
var _aerial_base := Vector3(-0.72, 0.93, 1.72)
var _whip := Vector2.ZERO        # how far the tip of the aerial is bent (sideways, back), and its speed
var _whip_v := Vector2.ZERO
var _tail: Array = []            # positions in the world
var _tail_old: Array = []
var _tail_parts: Array = []      # MeshInstance3D per link
var _tail_root: Node3D           # top level, so the links are placed in world space
var _smoke: Array = []           # CPUParticles3D at the two rear wheels
var _smoking := false
var _mats := {}
var _smoke_idle := 99.0         # seconds since the rear wheels last smoked


func _ready() -> void:
	_chassis = Node3D.new()
	add_child(_chassis)
	_mats = {
		"paint": _paint(),
		"glass": _mat(Color(0.05, 0.07, 0.09), 0.08, 0.6),
		"black": _mat(Color(0.045, 0.045, 0.05), 0.7),
		"under": _mat(Color(0.03, 0.03, 0.03), 1.0),
		"chrome": _mat(Color(0.78, 0.79, 0.81), 0.2, 0.9),
		"rubber": _mat(Color(0.03, 0.03, 0.03), 0.95),
		"alloy": _mat(Color(0.80, 0.81, 0.83), 0.28, 0.85),
		"iron": _mat(Color(0.30, 0.30, 0.31), 0.5, 0.7),
		"lamp": _lit(Color(0.96, 0.95, 0.86), 0.7),
		"amber": _lit(Color(0.95, 0.52, 0.08), 0.25),
		"red": _lit(Color(0.62, 0.04, 0.03), 0.3),
		"plate": _mat(Color(0.92, 0.92, 0.88), 0.6),
	}
	_tune_materials()
	var shell := Geo.new()
	_build_shell(shell)
	_build_details(shell)
	var body_mi := MeshInstance3D.new()
	body_mi.mesh = shell.commit(_mats)
	_chassis.add_child(body_mi)

	var wheel := Geo.new()
	_build_wheel(wheel)
	var wheel_mats := {}
	for key in _mats:                                     # a wheel is seen from inside its rim too: both sides of every surface are drawn
		wheel_mats[key] = _mats[key]
		if _mats[key] is StandardMaterial3D:
			wheel_mats[key] = _mats[key].duplicate()
			wheel_mats[key].cull_mode = BaseMaterial3D.CULL_DISABLED
	var wheel_mesh := wheel.commit(wheel_mats)
	for front in [true, false]:
		for sx in [-TRACK, TRACK]:
			var z := AXLE_F if front else AXLE_R
			var hub := Node3D.new()
			hub.position = Vector3(sx, WHEEL_R, z)
			add_child(hub)
			var turn := Node3D.new()
			turn.rotation.z = PI * 0.5
			hub.add_child(turn)
			var roll := Node3D.new()
			turn.add_child(roll)
			var mi := MeshInstance3D.new()
			mi.mesh = wheel_mesh
			roll.add_child(mi)
			_wheels.append([hub, roll, front, hub.position])
	# the aerial and the fox tail
	var rod := CylinderMesh.new()
	rod.top_radius = 0.004
	rod.bottom_radius = 0.007
	rod.height = 1.0
	rod.radial_segments = 5
	rod.material = _mat(Color(0.75, 0.76, 0.78), 0.3, 0.9)
	_aerial = MeshInstance3D.new()
	_aerial.mesh = rod
	_chassis.add_child(_aerial)
	_tail_root = Node3D.new()
	_tail_root.top_level = true
	add_child(_tail_root)
	for i in (TAIL_POINTS - 1 if FOX_TAIL else 0):
		var t := float(i) / float(TAIL_POINTS - 2)
		var fur := CapsuleMesh.new()
		fur.radius = lerpf(0.030, 0.062, sin(t * PI * 0.85)) * (0.75 if i == 0 else 1.0)
		fur.height = TAIL_LINK + fur.radius * 2.0
		fur.radial_segments = 7
		fur.rings = 2
		fur.material = _mat(Color(0.93, 0.92, 0.88) if i == TAIL_POINTS - 2 else Color(0.72, 0.33, 0.10).lerp(Color(0.55, 0.22, 0.07), t), 1.0)
		var mi := MeshInstance3D.new()
		mi.mesh = fur
		_tail_root.add_child(mi)
		_tail_parts.append(mi)

	# tyre smoke at the rear wheels
	var puff := QuadMesh.new()
	puff.size = Vector2(1.0, 1.0)
	var pm := StandardMaterial3D.new()
	pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	pm.vertex_color_use_as_albedo = true
	pm.albedo_texture = _puff_texture()
	pm.cull_mode = BaseMaterial3D.CULL_DISABLED
	puff.material = pm
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.18))
	grow.add_point(Vector2(0.25, 0.6))
	grow.add_point(Vector2(1.0, 1.0))
	var fade := Gradient.new()
	fade.set_color(0, Color(0.92, 0.92, 0.92, 0.0))
	fade.add_point(0.06, Color(0.90, 0.90, 0.90, 0.62))
	fade.add_point(0.5, Color(0.84, 0.84, 0.85, 0.34))
	fade.set_color(fade.get_point_count() - 1, Color(0.8, 0.8, 0.82, 0.0))
	for sx in [-TRACK, TRACK]:
		var p := CPUParticles3D.new()
		p.mesh = puff
		p.amount = 260
		p.lifetime = 2.6
		p.local_coords = false
		p.emitting = false
		p.visible = false
		p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
		p.emission_box_extents = Vector3(0.12, 0.05, 0.25)
		p.direction = Vector3(0, 0.5, 1)
		p.spread = 35.0
		p.initial_velocity_min = 0.6
		p.initial_velocity_max = 2.4
		p.gravity = Vector3(0, 0.9, 0)
		p.damping_min = 0.6
		p.damping_max = 1.2
		p.scale_amount_min = 2.6
		p.scale_amount_max = 4.6
		p.scale_amount_curve = grow
		p.color_ramp = fade
		p.angle_min = 0.0
		p.angle_max = 360.0
		p.position = Vector3(sx, 0.12, AXLE_R + 0.15)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(p)
		_smoke.append(p)

	var shape := BoxShape3D.new()
	shape.size = BODY_BOX
	_col = CollisionShape3D.new()
	_col.shape = shape
	_col.position = Vector3(0, 0.80, 0)
	var body := StaticBody3D.new()
	body.add_child(_col)
	add_child(body)
	_place_parts()
	_reset_tail()


func _puff_texture() -> GradientTexture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.add_point(0.55, Color(1, 1, 1, 0.55))
	g.set_color(g.get_point_count() - 1, Color(1, 1, 1, 0))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	return tex


func _mat(color: Color, rough: float, metallic := 0.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = rough
	mat.metallic = metallic
	return mat


func _box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, rough := 0.45, emit := 0.0) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mat := _mat(color, rough)
	if emit > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emit
	mesh.material = mat
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	parent.add_child(mi)
	return mi


func specs() -> Dictionary:
	return SPECS


## Solid when parked; no collider of its own while someone is driving it.
func set_parked(parked: bool) -> void:
	_col.disabled = not parked


func park() -> void:
	_heave = 0.0; _heave_v = 0.0
	_pitch = 0.0; _pitch_v = 0.0
	_roll = 0.0; _roll_v = 0.0
	_offsets = [0.0, 0.0, 0.0, 0.0]
	_steer = 0.0
	_fresh = true
	set_drift(false, 0.0, 0.0)
	_place_parts()


func chassis_xf() -> Transform3D:
	return _chassis.transform


## The steering wheel and the pedals, for a rider who is shown (this one is not: the driver sits inside).
func grip(side: float) -> Vector3:
	return _chassis.transform * Vector3(-0.38 + 0.16 * side, 1.02, -0.45)


func foot(side: float) -> Vector3:
	return _chassis.transform * Vector3(-0.38 + 0.12 * side, 0.42, -0.95)


## The rear wheels have broken loose (or not): smoke, and the wheels spinning faster than the road.
func set_drift(on: bool, slip: float, speed: float) -> void:
	_smoking = on
	if on:
		_smoke_idle = 0.0
	for p in _smoke:
		p.visible = _smoke_idle < 3.0                      # see _process: not drawn at all while there is no smoke
		p.emitting = on
		if on:
			p.initial_velocity_max = 1.6 + absf(speed) * 0.12
			p.direction = Vector3(clampf(-slip, -1.0, 1.0) * 0.8, 0.5, 1.0)


func animate(speed: float, steer: float, delta: float, exclude: Array = []) -> void:
	delta = maxf(delta, 0.001)
	_spin -= speed * delta / WHEEL_R
	_rear_spin -= (speed + (14.0 * signf(speed + 0.01) if _smoking else 0.0)) * delta / WHEEL_R
	_steer = lerpf(_steer, steer * 0.5, minf(1.0, 9.0 * delta))

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
	var lateral := clampf(speed * yaw_rate, -16.0, 16.0)
	var vy := (y - _last_y) / delta
	var bump := clampf((vy - _last_vy) / delta, -60.0, 60.0)
	_last_speed = speed
	_last_yaw = yaw
	_last_y = y
	_last_vy = vy

	# springs and dampers: as the ATV's, a bit stiffer and with less travel
	_heave_v += (-230.0 * _heave - 13.0 * _heave_v - bump * 0.42) * delta
	_heave = clampf(_heave + _heave_v * delta, -0.08, 0.07)
	_pitch_v += (-170.0 * (_pitch - accel * 0.0065) - 12.0 * _pitch_v) * delta
	_pitch = clampf(_pitch + _pitch_v * delta, -0.085, 0.085)
	_roll_v += (-170.0 * (_roll + lateral * 0.0075) - 12.0 * _roll_v) * delta
	_roll = clampf(_roll + _roll_v * delta, -0.10, 0.10)

	# the aerial: a light whip on a soft spring, thrown about by what the car does
	var push := Vector2(lateral * 0.016, -accel * 0.012 + speed * 0.0022) + Vector2(0.0, bump * 0.0008)
	_whip_v += (-90.0 * (_whip - push) - 3.2 * _whip_v) * delta
	_whip = (_whip + _whip_v * delta).limit_length(0.34)

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
				target = -TRAVEL_DOWN
			else:
				var local: Vector3 = gx.affine_inverse() * hit["position"]
				target = clampf(local.y, -TRAVEL_DOWN, TRAVEL_UP)
		_offsets[i] = lerpf(_offsets[i], target, minf(1.0, 26.0 * delta))
	_place_parts()


func _place_parts() -> void:
	_chassis.transform = Transform3D(Basis.from_euler(Vector3(_pitch, 0.0, _roll)), Vector3(0.0, _heave, 0.0))
	for i in _wheels.size():
		var w: Array = _wheels[i]
		var hub: Node3D = w[0]
		var roll: Node3D = w[1]
		var rest: Vector3 = w[3]
		hub.position = rest + Vector3(0, _offsets[i], 0)
		hub.rotation.y = _steer if w[2] else 0.0
		roll.rotation.y = -(_spin if w[2] else _rear_spin)
	# the aerial leans from its base to wherever its tip has swung
	var tip := _aerial_tip_local()
	var d := tip - _aerial_base
	var length := d.length()
	var up := d / length
	var x := up.cross(Vector3.BACK).normalized()
	_aerial.transform = Transform3D(Basis(x, up * length, x.cross(up)), (_aerial_base + tip) * 0.5)


func _aerial_tip_local() -> Vector3:
	var w := _whip * (AERIAL_LEN / 0.95)
	return _aerial_base + Vector3(w.x, sqrt(maxf(0.01, AERIAL_LEN * AERIAL_LEN - w.length_squared())), 0.10 * AERIAL_LEN + w.y)


func _reset_tail() -> void:
	_tail.clear()
	_tail_old.clear()
	var top: Vector3 = (global_transform * (_chassis.transform * _aerial_tip_local())) if is_inside_tree() else Vector3.ZERO
	for i in TAIL_POINTS:
		_tail.append(top - Vector3(0, TAIL_LINK * float(i), 0))
		_tail_old.append(_tail[i])


## The fox tail: a chain hanging from the tip of the aerial. Each point keeps going the way it was going,
## is pulled down by its weight and held back by the air, and the links are then pulled back to length —
## so it hangs when the car stands, swings when it turns and streams out behind when it goes.
func _process(delta: float) -> void:
	if not is_inside_tree():
		return
	if not FOX_TAIL:
		if not _smoking:
			_smoke_idle += delta
		for p in _smoke:
			p.visible = _smoke_idle < 3.0
		return
	delta = clampf(delta, 0.001, 0.05)
	# A smoke emitter that has never run, or has run dry, still draws its unused puffs where it stands, as
	# black blobs under the wheels. So it is hidden except while smoking and until the last smoke has gone.
	if not _smoking:
		_smoke_idle += delta
	for p in _smoke:
		p.visible = _smoke_idle < 3.0
	var top: Vector3 = get_global_transform_interpolated() * (_chassis.transform * _aerial_tip_local())
	if _tail.is_empty() or _tail[0].distance_to(top) > 4.0:
		_reset_tail()
		_tail[0] = top
	_tail[0] = top
	_tail_old[0] = top
	for i in range(1, TAIL_POINTS):
		var p: Vector3 = _tail[i]
		var v: Vector3 = (p - _tail_old[i]) * pow(0.04, delta)           # the air takes most of its speed in a second
		_tail_old[i] = p
		_tail[i] = p + v + Vector3(0, -9.8, 0) * delta * delta * 0.6
	for _k in 4:
		for i in range(1, TAIL_POINTS):
			var a: Vector3 = _tail[i - 1]
			var b: Vector3 = _tail[i]
			var d := b - a
			var ln := d.length()
			if ln > 0.0001:
				_tail[i] = a + d * (TAIL_LINK / ln)
	for i in TAIL_POINTS - 1:
		var a2: Vector3 = _tail[i]
		var b2: Vector3 = _tail[i + 1]
		var up := (a2 - b2).normalized()
		var x := up.cross(Vector3.RIGHT)
		if x.length_squared() < 0.001:
			x = up.cross(Vector3.BACK)
		x = x.normalized()
		_tail_parts[i].global_transform = Transform3D(Basis(x, up, x.cross(up)), (a2 + b2) * 0.5)
# ------------------------------------------------------------------ the shape of the car
## Collects flat-shaded triangles per material.
class Geo:
	var surf := {}

	func tri(m: String, a: Vector3, b: Vector3, c: Vector3, hint: Vector3) -> void:
		var n := (b - a).cross(c - a)
		if n.length_squared() < 1e-12:
			return
		n = n.normalized()
		if not surf.has(m):
			surf[m] = [PackedVector3Array(), PackedVector3Array()]
		var s: Array = surf[m]
		if n.dot(hint) < 0.0:
			n = -n
			s[0].append(a); s[0].append(b); s[0].append(c)
		else:
			s[0].append(a); s[0].append(c); s[0].append(b)
		s[1].append(n); s[1].append(n); s[1].append(n)

	func quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
		tri(m, a, b, c, hint)
		tri(m, a, c, d, hint)

	## A box with half-extents h along the axes of a basis.
	func box(m: String, c: Vector3, h: Vector3, bs := Basis()) -> void:
		var x := bs.x * h.x
		var y := bs.y * h.y
		var z := bs.z * h.z
		quad(m, c + x - y - z, c + x + y - z, c + x + y + z, c + x - y + z, bs.x)
		quad(m, c - x - y - z, c - x + y - z, c - x + y + z, c - x - y + z, -bs.x)
		quad(m, c - x + y - z, c + x + y - z, c + x + y + z, c - x + y + z, bs.y)
		quad(m, c - x - y - z, c + x - y - z, c + x - y + z, c - x - y + z, -bs.y)
		quad(m, c - x - y + z, c + x - y + z, c + x + y + z, c - x + y + z, bs.z)
		quad(m, c - x - y - z, c + x - y - z, c + x + y - z, c - x + y - z, -bs.z)

	## A surface of revolution: `profile` is a list of Vector2(radius, distance along the axis).
	func lathe(m: String, c: Vector3, axis: Vector3, profile: Array, segs: int) -> void:
		var u := axis.cross(Vector3.RIGHT)
		if u.length_squared() < 0.01:
			u = axis.cross(Vector3.UP)
		u = u.normalized()
		var v := axis.cross(u)
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var d0 := u * cos(a0) + v * sin(a0)
			var d1 := u * cos(a1) + v * sin(a1)
			for i in profile.size() - 1:
				var p: Vector2 = profile[i]
				var q: Vector2 = profile[i + 1]
				var out := (d0 + d1) * (q.y - p.y) - axis * (q.x - p.x) * 2.0       # away from the axis, or along it on a flat face
				if (q.y - p.y) < 0.0:
					out = -out
				if absf(q.y - p.y) < 1e-6:
					out = axis * (1.0 if profile[0].y > 0.0 or p.y > 0.0 else -1.0)
				quad(m, c + d0 * p.x + axis * p.y, c + d1 * p.x + axis * p.y, c + d1 * q.x + axis * q.y, c + d0 * q.x + axis * q.y, out)

	## A plain cylinder with end caps.
	func cyl(m: String, c: Vector3, axis: Vector3, r: float, half: float, segs: int) -> void:
		var u := axis.cross(Vector3.RIGHT)
		if u.length_squared() < 0.01:
			u = axis.cross(Vector3.UP)
		u = u.normalized()
		var v := axis.cross(u)
		for k in segs:
			var a0 := TAU * float(k) / float(segs)
			var a1 := TAU * float(k + 1) / float(segs)
			var d0 := (u * cos(a0) + v * sin(a0)) * r
			var d1 := (u * cos(a1) + v * sin(a1)) * r
			quad(m, c + d0 - axis * half, c + d1 - axis * half, c + d1 + axis * half, c + d0 + axis * half, d0 + d1)
			tri(m, c + axis * half, c + d0 + axis * half, c + d1 + axis * half, axis)
			tri(m, c - axis * half, c + d0 - axis * half, c + d1 - axis * half, -axis)

	## A smooth skin over rows of points (each row a ring round a body, or a strip across a surface). `mat` is
	## what it is made of: a name, or a function of (row, place in the row) giving one. The points get rounded
	## normals, so the body is smooth and not faceted.
	func skin(rows: Array, closed: bool, mat) -> void:
		var n := rows.size()
		var m: int = rows[0].size()
		var centres := PackedVector3Array()
		for i in n:
			var c := Vector3.ZERO
			for p in rows[i]:
				c += p
			centres.append(c / float(m))
		var normals := []
		for i in n:
			var row := PackedVector3Array()
			for j in m:
				var along: Vector3 = rows[mini(i + 1, n - 1)][j] - rows[maxi(i - 1, 0)][j]
				var jn := (j + 1) % m if closed else mini(j + 1, m - 1)
				var jp := (j - 1 + m) % m if closed else maxi(j - 1, 0)
				var around: Vector3 = rows[i][jn] - rows[i][jp]
				var nrm := along.cross(around)
				var out: Vector3 = rows[i][j] - centres[i]
				if out.length_squared() < 1e-10:                       # a row drawn together to a point: the end of the body
					out = centres[i] - centres[i - 1 if i > 0 else 1]
				if nrm.length_squared() < 1e-12:
					nrm = out
				nrm = nrm.normalized()
				if closed and nrm.dot(out) < 0.0:
					nrm = -nrm
				row.append(nrm)
			normals.append(row)
		var last := m if closed else m - 1
		for i in n - 1:
			for j in last:
				var j2 := (j + 1) % m
				var name: String = mat.call(i, j) if mat is Callable else mat
				if name == "":
					continue
				if not surf.has(name):
					surf[name] = [PackedVector3Array(), PackedVector3Array()]
				var s: Array = surf[name]
				var idx := [[i, j], [i + 1, j], [i + 1, j2], [i, j], [i + 1, j2], [i, j2]]
				for t in 2:
					var a: Vector3 = rows[idx[t * 3][0]][idx[t * 3][1]]
					var b: Vector3 = rows[idx[t * 3 + 1][0]][idx[t * 3 + 1][1]]
					var c2: Vector3 = rows[idx[t * 3 + 2][0]][idx[t * 3 + 2][1]]
					var face := (b - a).cross(c2 - a)
					if face.length_squared() < 1e-16:
						continue
					var want: Vector3 = normals[idx[t * 3][0]][idx[t * 3][1]] + normals[idx[t * 3 + 1][0]][idx[t * 3 + 1][1]] + normals[idx[t * 3 + 2][0]][idx[t * 3 + 2][1]]
					var order := [0, 1, 2] if face.dot(want) < 0.0 else [0, 2, 1]
					for k in order:
						var q: Array = idx[t * 3 + k]
						s[0].append(rows[q[0]][q[1]])
						s[1].append(normals[q[0]][q[1]])

	## A flat end across a ring.
	func cap(m: String, ring: PackedVector3Array, hint: Vector3) -> void:
		for k in range(1, ring.size() - 1):
			tri(m, ring[0], ring[k], ring[k + 1], hint)

	## A round tube along a line of points, closed at both ends.
	func tube(m, pts: Array, r: float, segs: int) -> void:
		var rows := []
		var ref := Vector3.UP
		for i in pts.size():
			var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
			var u := t.cross(ref)
			if u.length_squared() < 0.01:
				u = t.cross(Vector3.RIGHT)
			u = u.normalized()
			var v := t.cross(u).normalized()
			ref = v * -1.0 if v.dot(ref) < 0.0 else v              # carry the frame along, so the tube does not twist
			var ring := PackedVector3Array()
			for k in segs:
				var a := TAU * float(k) / float(segs)
				ring.append(pts[i] + (u * cos(a) + v * sin(a)) * r)
			rows.append(ring)
		skin(rows, true, m)
		var name: String = m.call(0, 0) if m is Callable else m
		cap(name, rows[0], pts[0] - pts[1])
		cap(name, rows[-1], pts[-1] - pts[-2])

	## A ball, or an egg: radii along x, y and z.
	func ball(m, c: Vector3, r: Vector3, segs: int, rings: int) -> void:
		var rows := []
		for i in rings + 1:
			var lat := PI * float(i) / float(rings)
			var ring := PackedVector3Array()
			for k in segs:
				var a := TAU * float(k) / float(segs)
				ring.append(c + Vector3(cos(a) * sin(lat) * r.x, cos(lat) * r.y, sin(a) * sin(lat) * r.z))
			rows.append(ring)
		skin(rows, true, m)
	func count() -> int:
		var total := 0
		for m in surf:
			total += surf[m][0].size() / 3
		return total

	func commit(mats: Dictionary) -> ArrayMesh:
		var mesh := ArrayMesh.new()
		for m in surf:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = surf[m][0]
			arrays[Mesh.ARRAY_NORMAL] = surf[m][1]
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			mesh.surface_set_material(mesh.get_surface_count() - 1, mats[m])
		return mesh


## For a car that is this one with other colours: change the materials here.
func _tune_materials() -> void:
	pass


## The body colour, with the lines of the doors, bonnet and boot drawn into it (shaders/car_paint.gdshader).
func _paint() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PAINT_SHADER)
	mat.set_shader_parameter("paint", PAINT)
	return mat


func _lit(color: Color, energy: float) -> StandardMaterial3D:
	var mat := _mat(color, 0.25)
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = energy
	return mat


func _along(points: Array, z: float) -> float:
	for i in points.size() - 1:
		var a: Vector2 = points[i]
		var b: Vector2 = points[i + 1]
		if z <= b.x:
			return lerpf(a.y, b.y, clampf((z - a.x) / maxf(b.x - a.x, 1e-6), 0.0, 1.0))
	return points[-1].y


## The line of the car seen from the side: the height of its top at each place along it.
func _top(z: float) -> float:
	return _along(TOP_LINE, z)


func _belt(z: float) -> float:
	return lerpf(BELT.x, BELT.y, clampf((z - CABIN.x) / (CABIN.y - CABIN.x), 0.0, 1.0))


## The lower edge of the body: the sills, and the round arches over the wheels.
func _bottom(z: float) -> float:
	var low := lerpf(SILL, OVERHANG, clampf((absf(z) - (HALF_LEN - 0.46)) / 0.45, 0.0, 1.0))
	for zw in [AXLE_F, AXLE_R]:
		var dz: float = z - zw
		if absf(dz) < ARCH_R:
			low = maxf(low, WHEEL_R + sqrt(ARCH_R * ARCH_R - dz * dz))
	return low


## One half of the car's outline across, at a place along it: from the middle of the top, out over the
## shoulder, down the glass and the flank to the sill and back under to the middle. Always the same number
## of points, so that neighbouring outlines join up into a skin.
func _section(z: float) -> Array:
	var top := _top(z)
	var cabin := z > CABIN.x and z < CABIN.y
	var rc := CORNER
	var belt := minf(_belt(z), top - rc - 0.002) if cabin else top - rc - 0.002
	var squeeze := 1.0 - SQUEEZE * smoothstep(HALF_LEN - SQUEEZE_LEN, HALF_LEN, absf(z))
	if z > 0.0 and SQUEEZE_TAIL >= 0.0:
		squeeze = 1.0 - SQUEEZE_TAIL * smoothstep(HALF_LEN - SQUEEZE_LEN * 0.6, HALF_LEN, z)          # the corners of the nose and tail are rounded off
	var wb := HALF_W * squeeze
	var wt := lerpf(wb, ROOF_W, clampf((top - rc - belt) / GLASS_H, 0.0, 1.0))
	var bottom := _bottom(z)
	var pts := []
	for k in 7:                                                            # across the top
		var f := float(k) / 6.0
		pts.append(Vector2((wt - rc) * f, top + CROWN * (1.0 - f * f)))
	for k in range(1, 7):                                                  # round the shoulder
		var a := PI * 0.5 * float(k) / 6.0
		pts.append(Vector2(wt - rc + sin(a) * rc, top - rc + cos(a) * rc))
	for k in range(1, 5):                                                  # down the glass
		var f2 := float(k) / 4.0
		pts.append(Vector2(lerpf(wt, wb, f2), lerpf(top - rc, belt, f2)))
	var last_y := belt
	for q in FLANK:
		# never higher than the point before it: where the body is low (a sloping nose) the flank is squeezed down, not folded over
		var fy := minf(q.y if q.y > 0.0 else belt + q.y, last_y - 0.004)
		last_y = fy
		pts.append(Vector2(q.x * squeeze, maxf(fy, bottom)))
	pts.append(Vector2((FLANK[-1].x - 0.013) * squeeze, bottom))
	pts.append(Vector2(0.60, bottom))
	pts.append(Vector2(0.30, bottom))
	pts.append(Vector2(0.0, bottom))
	return pts


func _build_shell(g: Geo) -> void:
	# the places along the car where its outline is taken: every 16 mm, and four times as close at the very
	# nose and tail, where the shape turns quickly
	var zs := PackedFloat32Array()
	var zz := -HALF_LEN
	while zz < HALF_LEN - 0.0005:
		zs.append(zz)
		zz += 0.004 if absf(zz + 0.002) > HALF_LEN - END_FINE else 0.016
	zs.append(HALF_LEN)
	var n := zs.size() - 1
	var prev := []
	var prev_z := 0.0
	for i in n + 1:
		var z := zs[i]
		var sec := _section(z)
		if i > 0:
			var zm := (z + prev_z) * 0.5
			var rise := _top(zm) - _belt(zm)
			var screen := false
			for sc in SCREENS:
				screen = screen or (zm > sc.x and zm < sc.y)
			var pillar := false
			for pl in PILLARS:
				pillar = pillar or (zm > pl.x and zm < pl.y)
			var side_glass := zm > SIDE_GLASS.x and zm < SIDE_GLASS.y and rise > 0.24 and not pillar
			for sgn in [1.0, -1.0]:
				var sx: float = sgn
				for j in sec.size() - 1:
					var m := "paint"
					if j < 5 and screen:
						m = "glass"                                                    # windscreen and rear window, inside their frames
					elif j >= 8 and j < 16 and side_glass:
						m = "glass"                                                    # the side windows, between the pillars, as tall as the windscreen: up to the roof
					elif j >= 8 and j < 16 and pillar and rise > 0.24:
						m = "black"                                                    # the middle pillar, black, in the line of the glass
					elif j >= 20 and j < 23 and STRIP:
						m = "black"                                                    # the rubbing strip
					elif j >= 26:
						m = "under"
					var a := Vector3(prev[j].x * sx, prev[j].y, prev_z)
					var b := Vector3(sec[j].x * sx, sec[j].y, z)
					var c := Vector3(sec[j + 1].x * sx, sec[j + 1].y, z)
					var d := Vector3(prev[j + 1].x * sx, prev[j + 1].y, prev_z)
					var mid := (a + b + c + d) * 0.25
					g.quad(m, a, b, c, d, mid - Vector3(0, (_top(zm) + _bottom(zm)) * 0.5, mid.z))      # outward: away from the middle of the body there
		if i == 0 or i == n:                                                   # the flat of the nose and of the tail
			var face := Vector3(0, 0, -1.0 if i == 0 else 1.0)
			var centre := Vector3(0, (_top(z) + _bottom(z)) * 0.5, z)
			for sgn in [1.0, -1.0]:
				var sx2: float = sgn
				for j in sec.size() - 1:
					g.tri("paint", centre, Vector3(sec[j].x * sx2, sec[j].y, z), Vector3(sec[j + 1].x * sx2, sec[j + 1].y, z), face)
		prev = sec
		prev_z = z
	# inside the wheel arches: dark liners, so that one does not see through the car
	for zw in [AXLE_F, AXLE_R]:
		for sgn in [1.0, -1.0]:
			var sx3: float = sgn
			g.box("under", Vector3(0.58 * sx3, WHEEL_R + 0.18, zw), Vector3(0.01, 0.24, ARCH_R + 0.02))


## A bar with rounded edges that runs across the car and wraps round its corners: a bumper.
func _bumper(g: Geo, z: float, y: float, face: float) -> void:
	var steps := 44
	var ring := 10
	var prev := []
	for i in steps + 1:
		var x := -0.915 + 1.83 * float(i) / float(steps)
		var wrap := smoothstep(0.74, 0.915, absf(x))
		var zc := z - face * 0.26 * wrap * wrap                              # the ends sweep back along the flanks
		var pts := []
		for k in ring:
			var a := TAU * float(k) / float(ring)
			var px := cos(a)
			var py := sin(a)
			# a rounded rectangle 0.17 deep and 0.19 tall
			pts.append(Vector3(x, y + clampf(py * 1.5, -1.0, 1.0) * 0.095, zc + face * clampf(px * 1.5, -1.0, 1.0) * 0.085))
		if i > 0:
			for k in ring:
				var k2 := (k + 1) % ring
				var mid: Vector3 = (prev[k] + pts[k] + pts[k2] + prev[k2]) * 0.25
				g.quad("black", prev[k], pts[k], pts[k2], prev[k2], mid - Vector3(mid.x, y, zc))
		if i == 0 or i == steps:
			for k in range(1, ring - 1):
				g.tri("black", pts[0], pts[k], pts[k + 1], Vector3(-1.0 if i == 0 else 1.0, 0, 0))
		prev = pts
	g.box("chrome", Vector3(0, y + 0.098, z + face * 0.02), Vector3(0.74, 0.006, 0.05))


func _build_details(g: Geo) -> void:
	_bumper(g, -2.40, 0.47, -1.0)
	_bumper(g, 2.40, 0.47, 1.0)
	g.box("black", Vector3(0, 0.33, -2.28), Vector3(0.80, 0.055, 0.06))                       # front valance
	g.box("black", Vector3(0, 0.34, 2.30), Vector3(0.80, 0.05, 0.05))
	# the grille: a black frame, upright slats, the diagonal bar and the badge on it
	g.box("chrome", Vector3(0, 0.845, -2.372), Vector3(0.36, 0.008, 0.012))
	g.box("chrome", Vector3(0, 0.635, -2.372), Vector3(0.36, 0.008, 0.012))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("chrome", Vector3(0.36 * sx, 0.74, -2.372), Vector3(0.008, 0.113, 0.012))
	g.box("black", Vector3(0, 0.74, -2.362), Vector3(0.355, 0.105, 0.004))
	for k in 23:
		g.box("black", Vector3(-0.33 + 0.03 * float(k), 0.74, -2.372), Vector3(0.005, 0.10, 0.01))
	g.box("chrome", Vector3(0, 0.74, -2.386), Vector3(0.40, 0.014, 0.006), Basis(Vector3.BACK, 0.29))
	g.cyl("chrome", Vector3(0, 0.74, -2.392), Vector3.BACK, 0.05, 0.006, 20)
	g.cyl("iron", Vector3(0, 0.74, -2.399), Vector3.BACK, 0.036, 0.002, 20)
	# headlights: two square lamps a side in a chrome frame, the indicator wrapping round the corner
	for sgn in [-1.0, 1.0]:
		var sx2: float = sgn
		g.box("chrome", Vector3(0.60 * sx2, 0.745, -2.366), Vector3(0.225, 0.105, 0.008))
		for k in 2:
			var lx := (0.49 + 0.215 * float(k)) * sx2
			g.box("lamp", Vector3(lx, 0.745, -2.376), Vector3(0.098, 0.088, 0.006))
			for r in 5:
				g.box("chrome", Vector3(lx, 0.675 + 0.035 * float(r), -2.383), Vector3(0.098, 0.0025, 0.002))     # the ribs of the lens
		g.box("amber", Vector3(0.835 * sx2, 0.745, -2.33), Vector3(0.012, 0.095, 0.05))
		g.box("amber", Vector3(0.60 * sx2, 0.42, -2.50), Vector3(0.11, 0.022, 0.006))                  # in the bumper
		g.box("lamp", Vector3(0.36 * sx2, 0.34, -2.345), Vector3(0.075, 0.035, 0.008))                 # fog lamps
		g.box("amber", Vector3(0.878 * sx2, 0.66, -1.95), Vector3(0.004, 0.02, 0.035))                 # side repeaters
		# tail lights: a tall cluster in sections, with ribs
		g.box("black", Vector3(0.60 * sx2, 0.775, 2.366), Vector3(0.25, 0.135, 0.008))
		var kinds := ["red", "red", "amber", "lamp"]
		for k in 4:
			g.box(kinds[k], Vector3((0.79 - 0.125 * float(k)) * sx2, 0.775, 2.376), Vector3(0.058, 0.122, 0.006))
		for r in 7:
			g.box("black", Vector3(0.60 * sx2, 0.665 + 0.037 * float(r), 2.384), Vector3(0.245, 0.002, 0.002))
		g.box("red", Vector3(0.838 * sx2, 0.775, 2.32), Vector3(0.012, 0.12, 0.05))
		# mirrors: a stalk, a housing and the glass
		g.box("black", Vector3(0.87 * sx2, 1.02, -0.74), Vector3(0.03, 0.012, 0.03))
		g.box("black", Vector3(0.955 * sx2, 1.045, -0.73), Vector3(0.075, 0.05, 0.035))
		g.box("glass", Vector3(0.955 * sx2, 1.045, -0.693), Vector3(0.066, 0.042, 0.002))
		# (the gaps round the doors, their handles and locks, and the chrome along the windows and over them are
		# drawn into the paint: shaders/car_paint.gdshader)
		# wipers, lying on the screen
		var slope := Basis(Vector3.RIGHT, -0.654)
		g.box("black", Vector3(0.28 * sx2 - 0.10, 1.02, -0.985) + slope.z * -0.20, Vector3(0.008, 0.008, 0.22), slope * Basis(Vector3.UP, 0.9))
		g.box("black", Vector3(0.28 * sx2 - 0.10, 1.03, -0.985) + slope.z * -0.22, Vector3(0.006, 0.004, 0.24), slope * Basis(Vector3.UP, 0.9))
	# the lines of the bonnet and the boot lid, the filler flap, plates, badges, the exhaust
	for pz in [[-2.505, 0.47], [2.372, 0.60]]:
		g.box("black", Vector3(0, pz[1], pz[0]), Vector3(0.27, 0.062, 0.004))
		g.box("plate", Vector3(0, pz[1], pz[0] + signf(pz[0]) * 0.004), Vector3(0.26, 0.055, 0.002))
	for k in 5:                                                                                     # V O L V O
		g.box("chrome", Vector3(-0.66 + 0.035 * float(k), 0.93, 2.366), Vector3(0.012, 0.014, 0.003))
	for k in 3:
		g.box("chrome", Vector3(0.58 + 0.035 * float(k), 0.93, 2.366), Vector3(0.012, 0.014, 0.003))  # 7 4 0
	g.lathe("chrome", Vector3(0.52, 0.30, 2.36), Vector3.BACK, [Vector2(0.0, -0.02), Vector2(0.026, -0.02), Vector2(0.03, 0.0), Vector2(0.03, 0.16),
		Vector2(0.024, 0.16), Vector2(0.024, 0.02), Vector2(0.0, 0.02)], 16)
	g.box("iron", Vector3(0.40, 0.25, 1.9), Vector3(0.16, 0.06, 0.30))                             # silencer
	g.cyl("black", Vector3(_aerial_base.x, _aerial_base.y - 0.005, _aerial_base.z), Vector3.UP, 0.016, 0.012, 12)


## A wheel, turning about the Y axis of its own frame: a tyre with rounded shoulders and tread grooves, a
## 17 inch alloy rim with five double spokes, the brake disc behind them, the hub and its five nuts.
## Both faces are made alike, so the same wheel serves on either side of the car.
func _build_wheel(g: Geo) -> void:
	var segs := 56
	var hw := 0.112
	var wr := WHEEL_R
	var mid_r := (RIM_R + wr) * 0.5 - 0.005
	g.lathe("rubber", Vector3.ZERO, Vector3.UP, [Vector2(RIM_R, -hw + 0.008), Vector2(RIM_R + 0.012, -hw), Vector2(mid_r, -hw - 0.004),
		Vector2(wr - 0.026, -hw + 0.004), Vector2(wr - 0.010, -hw + 0.022), Vector2(wr - 0.002, -hw + 0.045), Vector2(wr, -0.050), Vector2(wr, -0.034),
		Vector2(wr - 0.007, -0.031), Vector2(wr - 0.007, -0.021), Vector2(wr, -0.018), Vector2(wr, 0.018), Vector2(wr - 0.007, 0.021), Vector2(wr - 0.007, 0.031),
		Vector2(wr, 0.034), Vector2(wr, 0.050), Vector2(wr - 0.002, hw - 0.045), Vector2(wr - 0.010, hw - 0.022), Vector2(wr - 0.026, hw - 0.004),
		Vector2(mid_r, hw + 0.004), Vector2(RIM_R + 0.012, hw), Vector2(RIM_R, hw - 0.008)], segs)
	# the rim: a lip on each face and the barrel between them
	g.lathe("alloy", Vector3.ZERO, Vector3.UP, [Vector2(RIM_R - 0.03, -hw + 0.03), Vector2(RIM_R - 0.012, -hw + 0.004), Vector2(RIM_R + 0.004, -hw - 0.002),
		Vector2(RIM_R + 0.004, -hw + 0.012), Vector2(RIM_R - 0.014, -hw + 0.03), Vector2(RIM_R - 0.02, 0.0), Vector2(RIM_R - 0.014, hw - 0.03),
		Vector2(RIM_R + 0.004, hw - 0.012), Vector2(RIM_R + 0.004, hw + 0.002), Vector2(RIM_R - 0.012, hw - 0.004), Vector2(RIM_R - 0.03, hw - 0.03)], segs)
	# closed behind the spokes on both faces, and the inside of the barrel between them: nothing shows through
	for face in [-1.0, 1.0]:
		var fy0: float = face
		g.cyl("under", Vector3(0, fy0 * (hw - 0.05), 0), Vector3.UP, RIM_R - 0.012, 0.004, segs)
	g.lathe("under", Vector3.ZERO, Vector3.UP, [Vector2(RIM_R - 0.016, -hw + 0.03), Vector2(RIM_R - 0.016, hw - 0.03)], segs)
	g.cyl("iron", Vector3.ZERO, Vector3.UP, RIM_R * 0.70, 0.012, 40)                                    # brake disc
	g.box("red", Vector3(0.11, 0.0, 0.07), Vector3(0.05, 0.03, 0.035))                           # a caliper (turns with the wheel; it is small)
	for face in [-1.0, 1.0]:
		var fy: float = face
		var y := fy * (hw - 0.03)
		g.lathe("alloy", Vector3(0, y, 0), Vector3(0, fy, 0), [Vector2(0.0, 0.016), Vector2(0.040, 0.016), Vector2(0.058, 0.008), Vector2(0.064, -0.012)], 24)
		g.cyl("chrome", Vector3(0, y + fy * 0.018, 0), Vector3.UP, 0.022, 0.004, 16)
		for k in 5:
			var a := TAU * float(k) / 5.0
			var dir := Vector3(cos(a), 0, sin(a))
			var side := Vector3(-dir.z, 0, dir.x)
			g.cyl("chrome", Vector3(0, y + fy * 0.014, 0) + (dir.rotated(Vector3.UP, TAU / 10.0)) * 0.043, Vector3.UP, 0.008, 0.006, 8)   # wheel nut
			for pair in [-1.0, 1.0]:
				var pr: float = pair
				# a spoke in four pieces from hub to rim, splaying a little and sinking toward the rim
				for q in 4:
					var r0 := 0.058 + (RIM_R - 0.075) * float(q) / 4.0
					var r1 := 0.058 + (RIM_R - 0.075) * float(q + 1) / 4.0
					var off0 := pr * (0.010 + 0.022 * float(q) / 4.0)
					var off1 := pr * (0.010 + 0.022 * float(q + 1) / 4.0)
					var p0 := dir * r0 + side * off0 + Vector3(0, y + fy * (0.004 - 0.010 * float(q) / 4.0), 0)
					var p1 := dir * r1 + side * off1 + Vector3(0, y + fy * (0.004 - 0.010 * float(q + 1) / 4.0), 0)
					var along := (p1 - p0).normalized()
					var across := Vector3.UP.cross(along).normalized()
					g.box("alloy", (p0 + p1) * 0.5, Vector3(0.009, 0.011, p0.distance_to(p1) * 0.5 + 0.002), Basis(across, Vector3.UP, along))
