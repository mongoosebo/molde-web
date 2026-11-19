extends Node3D
## A FRAM bus the player can drive (scripts/jobs.gd has the route to drive it on). The same blue bus as the
## ones in the traffic (scripts/bus.gd), with what scripts/player.gd asks of anything driven: where its tyres
## stand, a solid shape, and wheels that roll and steer. It is heavy: slow to gather speed, slow to stop, and
## wide in the turns.

const BusModel := preload("res://scripts/bus.gd")

var LABEL := "the FRAM bus"
var SPECS := {"speed": 14.0, "fast": 19.5, "reverse": 3.5, "power": 2.6, "brake": 7.0, "reach": 7.0,
	"drift": false, "hides_rider": true, "exit": 2.3, "camera": 15.0, "turn": 0.42}

var _wheels: Array = []
var _steer: Array = []
var _roll := 0.0
var _col: CollisionShape3D


func _ready() -> void:
	var made: Dictionary = BusModel.make()
	add_child(made["node"])
	_wheels = made["wheels"]
	_steer = made["steer"]
	_col = CollisionShape3D.new()
	_col.shape = hull_shape()
	var body := StaticBody3D.new()
	body.add_child(_col)
	add_child(body)


func specs() -> Dictionary:
	return SPECS


func wheel_points() -> Array:
	var t := BusModel.HALF_W - 0.17
	return [Vector3(-t, 0, BusModel.AXLE_F), Vector3(t, 0, BusModel.AXLE_F), Vector3(-t, 0, BusModel.AXLE_R), Vector3(t, 0, BusModel.AXLE_R)]


func hull_shape(floor := -1.0) -> ConvexPolygonShape3D:
	var lo := maxf(BusModel.FLOOR, floor)
	var pts := PackedVector3Array()
	for x in [-BusModel.HALF_W, BusModel.HALF_W]:
		for y in [lo, BusModel.ROOF]:
			for z in [-BusModel.LEN * 0.5, BusModel.LEN * 0.5]:
				pts.append(Vector3(x, y, z))
	var shape := ConvexPolygonShape3D.new()
	shape.points = pts
	return shape


func set_parked(parked: bool) -> void:
	_col.disabled = not parked


func park() -> void:
	for h in _steer:
		(h as Node3D).rotation.y = 0.0


func chassis_xf() -> Transform3D:
	return Transform3D.IDENTITY


func eye() -> Vector3:
	return Vector3(-0.72, 1.95, -BusModel.LEN * 0.5 - 0.12)      # (just outside the windscreen: the bus has no inside)


func grip(side: float) -> Vector3:
	return Vector3(-0.75 + 0.18 * side, 1.55, -5.0)


func foot(side: float) -> Vector3:
	return Vector3(-0.75 + 0.12 * side, 0.95, -5.3)


func set_drift(_on: bool, _slip: float, _speed: float) -> void:
	pass


func animate(speed: float, steer: float, delta: float, _exclude: Array = []) -> void:
	_roll = fposmod(_roll - speed * delta / BusModel.WHEEL_R, TAU)
	for w in _wheels:
		(w as Node3D).rotation.x = _roll
	for h in _steer:
		(h as Node3D).rotation.y = lerpf((h as Node3D).rotation.y, -steer * 0.55, minf(1.0, 6.0 * delta))
