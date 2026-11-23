extends Node3D
## An aeroplane one can fly (notes of 21 Nov: "add a flyable Cessna plane here", "make the Norwegian planes
## flyable"). Two kinds: a Cessna, a small high-winged four-seater with one propeller, and the airliner of
## scripts/plane.gd. scripts/player.gd flies it (_fly_plane): W and S open and close the throttle, the nose
## follows where one looks, A and D steer on the ground and bank in the air; it needs speed to leave the ground
## and falls out of the air without it. Set `kind` before it enters the tree.

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo)
const Airliner := preload("res://scripts/plane.gd")

## what the player's code needs to fly each: the speed it leaves the ground at and the fastest it goes (m/s), how
## hard the engines push (m/s²), how fast it turns and pitches (rad/s), how far the camera hangs behind
const KINDS := {
	"cessna": {"label": "the Cessna", "reach": 5.5, "exit": 2.4, "camera": 13.0, "stall": 25.0, "top": 62.0, "push": 5.5, "turn": 0.75, "pitch": 0.9, "brake": 7.0, "box": Vector3(2.2, 2.6, 7.6)},
	"airliner": {"label": "the airliner", "reach": 17.0, "exit": 6.0, "camera": 58.0, "stall": 62.0, "top": 190.0, "push": 9.5, "turn": 0.32, "pitch": 0.45, "brake": 9.0, "box": Vector3(4.0, 5.5, 38.0)},
}

var kind := "cessna"
var LABEL := "the Cessna"
var rotor := 0.0                 # how hard the engine is working, 0 to 1 (scripts/sound.gd listens to this, as to the helicopter's rotor)
var engine := false
var throttle := 0.0              # set by the player's code while it is flown

var _chassis: Node3D
var _col: CollisionShape3D
var _prop: Node3D
var _disc: MeshInstance3D
var _specs := {}


func _ready() -> void:
	var k: Dictionary = KINDS[kind]
	LABEL = k["label"]
	_specs = {"flies": true, "wings": true, "reach": k["reach"], "hides_rider": true, "exit": k["exit"], "camera": k["camera"], "drift": false,
		"speed": 0.0, "fast": 0.0, "reverse": 0.0, "power": 0.0, "brake": k["brake"], "stall": k["stall"], "top": k["top"], "push": k["push"],
		"turn": k["turn"], "pitch": k["pitch"]}
	_chassis = Node3D.new()
	add_child(_chassis)
	var body := MeshInstance3D.new()
	body.mesh = Airliner.build() if kind == "airliner" else _cessna()
	_chassis.add_child(body)
	if kind == "cessna":
		_prop = Node3D.new()
		_prop.position = Vector3(0, 1.42, -2.78)
		_chassis.add_child(_prop)
		var blades := MeshInstance3D.new()
		blades.mesh = _propeller()
		_prop.add_child(blades)
		_disc = MeshInstance3D.new()
		var dm := CylinderMesh.new()
		dm.top_radius = 0.95
		dm.bottom_radius = 0.95
		dm.height = 0.01
		dm.radial_segments = 20
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.1, 0.1, 0.1, 0.18)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		dm.material = mat
		_disc.mesh = dm
		_disc.rotation.x = PI * 0.5
		_disc.position = _prop.position
		_disc.visible = false
		_chassis.add_child(_disc)
	var solid := StaticBody3D.new()
	_col = CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = k["box"]
	_col.shape = box
	_col.position = Vector3(0, float((k["box"] as Vector3).y) * 0.5 + 0.4, 0)
	solid.add_child(_col)
	add_child(solid)


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## The Cessna: 8.3 m long, 11 m across the wing, which sits on top of the cabin on a strut each side; a fixed
## undercarriage of three wheels; white with a red stripe and a Norwegian registration's blue fin tip.
func _cessna() -> ArrayMesh:
	var g = Shapes.Geo.new()
	# the body: the cowl round the engine, the cabin, and the tail cone rising to the fin
	var st := [[-2.70, 0.30, 0.34, 1.40], [-2.55, 0.48, 0.46, 1.38], [-1.90, 0.56, 0.54, 1.36], [-1.30, 0.60, 0.66, 1.42], [-0.70, 0.62, 0.78, 1.52], [0.40, 0.62, 0.78, 1.52],
		[1.20, 0.56, 0.66, 1.50], [2.20, 0.40, 0.44, 1.55], [3.40, 0.24, 0.28, 1.62], [4.60, 0.10, 0.16, 1.70], [5.30, 0.03, 0.08, 1.74]]
	var rows := []
	for q in st:
		var ring := PackedVector3Array()
		for k in 16:
			var a := TAU * float(k) / 16.0
			var sq := 0.82                                               # (squarer than round: a cabin of flat sides)
			var cx := signf(cos(a)) * pow(absf(cos(a)), sq)
			var sy := signf(sin(a)) * pow(absf(sin(a)), sq)
			ring.append(Vector3(cx * float(q[1]), float(q[3]) + sy * float(q[2]), q[0]))
		rows.append(ring)
	g.skin(rows, true, func(i, k): return "red" if (i >= 1 and i <= 9 and (k == 0 or k == 8 or k == 15 or k == 7)) else "white")
	g.cap("white", rows[0], Vector3.FORWARD)
	g.lathe("steel", Vector3(0, 1.42, -2.72), Vector3.BACK, [Vector2(0.0, -0.30), Vector2(0.10, -0.20), Vector2(0.17, 0.0)], 12)           # the spinner
	g.box("fan", Vector3(0, 1.20, -2.705), Vector3(0.20, 0.07, 0.01))                                                               # the air intake under it
	# the windscreen, the side windows, the rear window
	g.box("glass", Vector3(0, 1.98, -0.98), Vector3(0.55, 0.26, 0.02), Basis(Vector3.RIGHT, -0.75))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.box("glass", Vector3(0.615 * sx, 1.86, -0.25), Vector3(0.012, 0.22, 0.42))
		g.box("glass", Vector3(0.60 * sx, 1.86, 0.72), Vector3(0.012, 0.19, 0.32))
		g.box("door_line", Vector3(0.622 * sx, 1.50, -0.25), Vector3(0.004, 0.62, 0.006))
		g.box("door_line", Vector3(0.622 * sx, 1.50, 0.22), Vector3(0.004, 0.62, 0.006))
		# the wing: straight, on top of the cabin, a little washed out to the tip; the strut down to the body
		Airliner._plane(g, func(i, k): return "white", [[Vector3(0.0, 2.32, -0.95), 1.62, 0.24], [Vector3(2.4 * sx, 2.36, -0.95), 1.62, 0.22], [Vector3(5.45 * sx, 2.44, -0.80), 1.15, 0.14]], Vector3.UP)
		g.box("red", Vector3(5.40 * sx, 2.45, -0.25), Vector3(0.10, 0.07, 0.56))                                                     # the wing tip
		g.tube("white", [Vector3(0.58 * sx, 0.98, -0.30), Vector3(2.55 * sx, 2.26, -0.30)], 0.045, 8)
		g.box("lamp_red" if sx < 0.0 else "lamp_green", Vector3(5.52 * sx, 2.45, -0.45), Vector3(0.03, 0.03, 0.05))
		# the tail plane
		Airliner._plane(g, func(i, k): return "white", [[Vector3(0.0, 1.72, 4.25), 1.15, 0.12], [Vector3(1.75 * sx, 1.72, 4.45), 0.80, 0.08]], Vector3.UP)
		# a main wheel on its sprung leg, in a spat
		g.tube("white", [Vector3(0.45 * sx, 0.95, 0.35), Vector3(1.22 * sx, 0.36, 0.42)], 0.05, 8)
		g.lathe("rubber", Vector3(1.26 * sx, 0.22, 0.42), Vector3.RIGHT, [Vector2(0.10, -0.07), Vector2(0.19, -0.075), Vector2(0.22, -0.04), Vector2(0.22, 0.04), Vector2(0.19, 0.075), Vector2(0.10, 0.07)], 14)
		g.ball("white", Vector3(1.26 * sx, 0.33, 0.44), Vector3(0.11, 0.17, 0.36), 10, 5)
		g.box("flag_red", Vector3(0.22 * sx * 0.0 + 0.045 * sx, 2.25, 4.75), Vector3(0.004, 0.16, 0.22))                              # the flag on the fin
		g.box("white_flat", Vector3(0.049 * sx, 2.25, 4.69), Vector3(0.004, 0.16, 0.04))
		g.box("white_flat", Vector3(0.049 * sx, 2.25, 4.75), Vector3(0.004, 0.04, 0.22))
		g.box("flag_blue", Vector3(0.053 * sx, 2.25, 4.69), Vector3(0.004, 0.16, 0.02))
		g.box("flag_blue", Vector3(0.053 * sx, 2.25, 4.75), Vector3(0.004, 0.02, 0.22))
	# the fin, swept, with the rudder's tip in red
	Airliner._plane(g, func(i, k): return "red" if i >= 1 else "white", [[Vector3(0, 1.70, 3.55), 1.75, 0.12], [Vector3(0, 2.75, 4.60), 0.95, 0.08], [Vector3(0, 3.02, 4.85), 0.72, 0.06]], Vector3.RIGHT)
	# the nose wheel on its leg
	g.tube("steel", [Vector3(0, 1.0, -1.95), Vector3(0, 0.30, -2.02)], 0.035, 8)
	g.lathe("rubber", Vector3(0, 0.19, -2.02), Vector3.RIGHT, [Vector2(0.09, -0.06), Vector2(0.16, -0.065), Vector2(0.19, -0.03), Vector2(0.19, 0.03), Vector2(0.16, 0.065), Vector2(0.09, 0.06)], 12)
	g.ball("white", Vector3(0, 0.29, -2.0), Vector3(0.09, 0.14, 0.30), 10, 5)
	g.box("lamp_red", Vector3(0, 3.06, 5.15), Vector3(0.03, 0.04, 0.04))
	g.tube("steel", [Vector3(0.25, 2.42, -0.2), Vector3(0.25, 2.62, 0.1)], 0.008, 4)                                                 # an aerial
	var lamp_r := _mat(Color(0.95, 0.10, 0.08), 0.3)
	lamp_r.emission_enabled = true
	lamp_r.emission = Color(1.0, 0.1, 0.05)
	var lamp_g := _mat(Color(0.10, 0.85, 0.25), 0.3)
	lamp_g.emission_enabled = true
	lamp_g.emission = Color(0.1, 1.0, 0.3)
	return g.commit({"white": _mat(Color(0.94, 0.94, 0.92), 0.35, 0.1), "red": _mat(Color(0.78, 0.07, 0.10), 0.35, 0.1), "glass": _mat(Color(0.06, 0.09, 0.12), 0.08, 0.6),
		"steel": _mat(Color(0.65, 0.66, 0.69), 0.35, 0.7), "fan": _mat(Color(0.04, 0.04, 0.05), 0.6), "rubber": _mat(Color(0.03, 0.03, 0.03), 0.95),
		"door_line": _mat(Color(0.30, 0.31, 0.33), 0.6), "flag_red": _mat(Color(0.73, 0.05, 0.13), 0.5), "flag_blue": _mat(Color(0.0, 0.13, 0.36), 0.5),
		"white_flat": _mat(Color(0.96, 0.96, 0.96), 0.5), "lamp_red": lamp_r, "lamp_green": lamp_g})


func _propeller() -> ArrayMesh:
	var g = Shapes.Geo.new()
	for sgn in [-1.0, 1.0]:
		var s: float = sgn
		g.box("blade", Vector3(0.28 * s, 0, 0), Vector3(0.22, 0.075, 0.012), Basis(Vector3.RIGHT, 0.5 * s))
		g.box("blade", Vector3(0.70 * s, 0, 0), Vector3(0.22, 0.055, 0.008), Basis(Vector3.RIGHT, 0.3 * s))
	return g.commit({"blade": _mat(Color(0.07, 0.07, 0.08), 0.5, 0.3)})


# ------------------------------------------------------------------ what the player's code asks of a vehicle
func specs() -> Dictionary:
	return _specs


func set_parked(parked: bool) -> void:
	_col.disabled = not parked
	engine = not parked
	if parked:
		throttle = 0.0


func park() -> void:
	_chassis.transform = Transform3D.IDENTITY


func set_drift(_on: bool, _slip: float, _speed: float) -> void:
	pass


func chassis_xf() -> Transform3D:
	return _chassis.transform


func eye() -> Vector3:
	return Vector3(-0.28, 1.95, -0.45) if kind == "cessna" else Vector3(-0.5, 4.55, -16.6)


func seat() -> Array:
	return [Vector3(-0.28, 1.25, -0.30), -0.10]


func grip(side: float) -> Vector3:
	return _chassis.transform * Vector3(-0.28 + 0.14 * side, 1.55, -0.85)


func foot(side: float) -> Vector3:
	return _chassis.transform * Vector3(-0.28 + 0.11 * side, 1.05, -1.25)


func animate(_speed: float, _steer: float, _delta: float, _exclude: Array = []) -> void:
	pass


## The engine: idling as soon as someone sits in it, up and down with the throttle; the propeller a blur at speed.
func _process(delta: float) -> void:
	rotor = move_toward(rotor, (0.25 + 0.75 * throttle) if engine else 0.0, delta * 0.8)
	if _prop != null:
		_prop.rotation.z += rotor * 70.0 * delta
		_prop.visible = rotor < 0.5
		_disc.visible = rotor >= 0.35
