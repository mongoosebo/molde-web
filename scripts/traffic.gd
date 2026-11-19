extends Node3D
## What moves by itself: cars on the real roads, buses on a few routes, boats on the fjord and planes at Årø.
##
## Cars are twenty models of the kinds one meets in town (scripts/traffic_car.gd), each built like the Volvo and
## picked at random with one of its usual colours; their wheels turn and steer. They exist only near the player
## (made and removed some way off). Each is steered like a car toward a point running ahead of it in the
## right-hand lane of its road, so it takes bends and junctions in curves; they slow for bends, corners and the
## ends of roads, keep their distance from the car in front, stop for the player, and pick a road to go on by
## at each junction. The nearest few are solid. The menu's "Traffic" setting says how many there are (none,
## little, normal).
##
## Buses run there and back between Rutebilholdeplassen and three ends of town, stopping at the bus stops along
## the way and waiting at the bus square. A ferry sails out across the fjord and back, small boats move slowly
## off the harbour, the coastal steamer comes in to the quay morning and evening, and now and then a plane
## lands at or takes off from Molde lufthavn, Årø. Boats leave a wake when the player is near (scripts/ripples.gd).

const CARS_MAX := 30
const NEAR := 120.0                      # cars are made no nearer than this, and removed beyond FAR
const FAR := 440.0
const SOLID := 6
const BUS_SQUARE := Vector2(120.0, 35.0)

var world
var player
var daytime
var amount := 2: set = set_amount       # 0 none, 1 little, 2 normal
var cars: Array = []                     # each: {w, dir, s, v, col, hold}
var buses: Array = []
var stats := {"made": 0, "removed": 0, "turns": 0, "stops_for_player": 0, "stops_for_walkers": 0, "gave_way": 0, "bus_stops": 0, "flights": 0}

var _ways: Array = []                    # the roads cars drive on (detail.ways entries)
var _way_of := {}                        # number of a road in detail.ways -> its number in _ways
var _stations: Array = []                # for each road: the distances along it where another road meets it (and its two ends)
var _links := {}                         # Vector2i(road, station number) -> [Vector2i(road, station number), ...]: where one can cross over
var _models: Array = []               # the car models: {body, wheel (meshes), track, wheel_r, axle_f, axle_r, wb, paints}
const BusModel := preload("res://scripts/bus.gd")
var _rng := RandomNumberGenerator.new()
var _spawn_in := 0.0
var _bodies: Array = []
var _boats: Array = []                   # each: {node, kind, ...}
var _meshes := {}
var _plane: MeshInstance3D
var _plane_t := -1.0
var _plane_in := 90.0
var _plane_lands := true
var _runway := PackedVector2Array()


func set_amount(a: int) -> void:
	amount = a
	if a == 0:
		for c in cars:
			_forget(c)
		cars.clear()


func setup(w, p, d) -> void:
	world = w
	player = p
	daytime = d
	_rng.seed = 7
	_meshes = world.props._meshes()
	for wn in world.detail.ways.size():
		var way: Array = world.detail.ways[wn]
		if way[1] == 5 and (way[3] as PackedVector2Array).size() > 50:
			_runway = way[3]
		if way[1] != 0 or (way[3] as PackedVector2Array).size() < 2:
			continue
		# only roads that are laid with asphalt (the map's cover has them at half strength; a gravel road, a
		# track or a flight of steps drawn as a road is at full strength or not there at all): note of 18 Nov
		var laid := 0
		var seen := 0
		for q in (way[3] as PackedVector2Array):
			var road: float = world.cover_at(q.x, q.y)["road"]
			seen += 1
			if road > 0.3 and road < 0.75:
				laid += 1
		if laid * 10 < seen * 7:
			continue
		_way_of[wn] = _ways.size()
		_ways.append(way)
	_join_roads()
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF      # (see _process; everything under this node is moved each frame)
	_build_models()                                        # (about 1.7 s for the twenty)
	for i in SOLID:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.8, 1.4, 4.3)
		shape.shape = box
		shape.position = Vector3(0, 0.8, 0)
		body.add_child(shape)
		body.position = Vector3(0, -500, 0)
		add_child(body)
		_bodies.append(body)
	_setup_buses()
	_setup_boats()
	if not _runway.is_empty():
		_plane = MeshInstance3D.new()
		_plane.name = "Plane"
		_plane.mesh = _meshes[world.props.AIRLINER]
		_plane.visible = false
		add_child(_plane)


## The road network. The map gives roads as separate lines; most meet another road somewhere along it, not end
## to end. Every end of a road is joined to each road that passes within 8 m of it, at the nearest place on
## that road: both get a "station" there, and the two stations are linked, so a car (or a bus route) can cross
## from one road to the other.
func _join_roads() -> void:
	var grid := {}                                          # 8 m square -> [road, point number, ...]
	for w in _ways.size():
		var pts: PackedVector2Array = _ways[w][3]
		for k in pts.size():
			var key := Vector2i(int(floor(pts[k].x / 8.0)), int(floor(pts[k].y / 8.0)))
			if not grid.has(key):
				grid[key] = PackedInt32Array()
			grid[key].append(w)
			grid[key].append(k)
	var marks: Array = []                                   # for each road: [distance along, ...] to become stations
	for w in _ways.size():
		marks.append([0.0, _length(_ways[w])])
	var pairs: Array = []                                   # [road a, distance, road b, distance]
	for w in _ways.size():
		var pts: PackedVector2Array = _ways[w][3]
		for e in 2:
			var p := pts[0] if e == 0 else pts[pts.size() - 1]
			var best := {}                                  # other road -> [distance squared, point number]
			var c := Vector2i(int(floor(p.x / 8.0)), int(floor(p.y / 8.0)))
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					var list = grid.get(Vector2i(c.x + dx, c.y + dz))
					if list == null:
						continue
					for i in range(0, list.size(), 2):
						var o: int = list[i]
						if o == w:
							continue
						var d: float = ((_ways[o][3] as PackedVector2Array)[list[i + 1]] as Vector2).distance_squared_to(p)
						if d < 64.0 and (not best.has(o) or d < best[o][0]):
							best[o] = [d, list[i + 1]]
			for o in best:
				var so: float = (_ways[o][7] as PackedFloat32Array)[best[o][1]]
				pairs.append([w, 0.0 if e == 0 else _length(_ways[w]), o, so])
				marks[o].append(so)
	for w in _ways.size():
		var list: Array = marks[w]
		list.sort()
		var st := PackedFloat32Array()
		for v in list:
			if st.is_empty() or v - st[st.size() - 1] > 4.0:
				st.append(v)
		st[st.size() - 1] = _length(_ways[w])
		_stations.append(st)
	for pr in pairs:
		var a := Vector2i(pr[0], _station_near(pr[0], pr[1]))
		var b := Vector2i(pr[2], _station_near(pr[2], pr[3]))
		for q in [[a, b], [b, a]]:
			if not _links.has(q[0]):
				_links[q[0]] = []
			if not q[1] in _links[q[0]]:
				_links[q[0]].append(q[1])


func _station_near(w: int, s: float) -> int:
	var st: PackedFloat32Array = _stations[w]
	var best := 0
	for i in st.size():
		if absf(st[i] - s) < absf(st[best] - s):
			best = i
	return best


# ------------------------------------------------------------------ along a road
## The place, the direction and the half width of a road at a distance along it.
func _along(way: Array, s: float) -> Array:
	var pts: PackedVector2Array = way[3]
	var dist: PackedFloat32Array = way[7]
	var k := clampi(dist.bsearch(s) - 1, 0, pts.size() - 2)
	var seg := maxf(dist[k + 1] - dist[k], 0.001)
	var t := clampf((s - dist[k]) / seg, 0.0, 1.0)
	return [pts[k].lerp(pts[k + 1], t), (pts[k + 1] - pts[k]).normalized(), way[0]]


func _length(way: Array) -> float:
	var dist: PackedFloat32Array = way[7]
	return dist[dist.size() - 1]


## The road's height at a place: the asphalt where it is laid near the player, the ground elsewhere.
func _height(p: Vector2) -> float:
	var y: float = world.detail.top_at(p.x, p.y)                 # (on the asphalt, or up on the slabs of a sidewalk)
	return y if not is_nan(y) else world.height_at(p.x, p.y) + 0.10


## Where a vehicle on a road is: [place in the world, the way it faces (a unit Vector2)].
func _pose(way: Array, s: float, dir: int, reach: float) -> Array:
	var a := _along(way, s)
	var fwd: Vector2 = a[1] * float(dir)
	var right := Vector2(-fwd.y, fwd.x)
	var off := minf(float(a[2]) * 0.5, reach)
	var p: Vector2 = a[0] + right * off
	return [Vector3(p.x, _height(p), p.y), fwd]


func _xf(pos: Vector3, fwd: Vector2, scale := Vector3.ONE) -> Transform3D:
	# models face -Z; tip them along the road by the height a little ahead and behind
	var ahead := Vector2(pos.x, pos.z) + fwd * 2.0
	var behind := Vector2(pos.x, pos.z) - fwd * 2.0
	var f3 := Vector3(fwd.x, (_height(ahead) - _height(behind)) / 4.0, fwd.y).normalized()
	var right := f3.cross(Vector3.UP).normalized()
	var up := right.cross(f3).normalized()
	return Transform3D(Basis(right, up, -f3).scaled(scale), pos)


# ------------------------------------------------------------------ cars
## Run every drawn frame, not on the physics tick, and without the engine's smoothing between ticks. A car is
## drawn as the k-th copy of one model, and k changes whenever a car ahead of it in the list leaves; the
## smoothing then slid each copy from where the k-th car was to where the new k-th car is, which showed as cars
## flickering (note of 17 Nov). Moved each frame they are smooth by themselves.
func _process(delta: float) -> void:
	var t0_ := Time.get_ticks_usec()
	_run(delta)
	if world != null:
		world.took("traffic", t0_)


func _run(delta: float) -> void:
	if world == null:
		return
	var pp: Vector3 = player.global_position
	var here := Vector2(pp.x, pp.z)
	var want: int = [0, 12, CARS_MAX][amount]
	_spawn_in -= delta
	if cars.size() < want and _spawn_in <= 0.0:
		_spawn_in = 0.25
		var tq236 := Time.get_ticks_usec()
		_make_car(here)
		world.took("t_make", tq236)
	# by road and direction, for keeping distance
	var lanes := {}
	for c in cars:
		var key := Vector2i(c["w"], c["dir"])
		if not lanes.has(key):
			lanes[key] = []
		lanes[key].append(c)
	var player_speed := Vector2(player.velocity.x, player.velocity.z).length()
	var snd = get_parent().get("sound")
	var walkers := PackedVector2Array()                  # townspeople near enough to matter
	var folk = get_parent().get("people")
	if folk != null:
		for f in folk.people:
			var fp: Vector3 = (f["node"] as Node3D).position
			if absf(fp.x - here.x) < 260.0 and absf(fp.z - here.y) < 260.0:
				walkers.append(Vector2(fp.x, fp.z))
	var i := cars.size() - 1
	while i >= 0:
		var c: Dictionary = cars[i]
		var way: Array = _ways[c["w"]]
		var length := _length(way)
		var p: Vector2 = c["pos"]
		var fwd: Vector2 = c["head"]
		if p.distance_to(here) > FAR:
			_forget(c)
			cars.remove_at(i)
			stats["removed"] += 1
			i -= 1
			continue
		# A car is steered, not slid along a line: it has a place and a heading of its own, and drives toward a
		# point that runs ahead of it along its road, in its lane (`s`, the distance of that point along the
		# road). It can only turn as tightly as a car can, so at a junction, where the point goes off down
		# another road, the car follows round in a curve; and nothing it does can move it sideways or turn it
		# on the spot.
		var aim := _lane_point(way, c["s"], c["dir"])
		var lead: float = 4.0 + 0.45 * c["v"]
		var off: float = fwd.angle_to(aim - p) if p.distance_to(aim) > 0.3 else 0.0
		# how fast it may go here
		var a := _along(way, clampf(c["s"], 0.0, length))
		var top := 13.5 if float(a[2]) >= 3.2 else 8.5
		var to_end: float = (length - c["s"]) if c["dir"] > 0 else c["s"]
		var a2 := _along(way, clampf(c["s"] + 12.0 * c["dir"], 0.0, length))
		var bend := absf((a[1] as Vector2).angle_to(a2[1]))
		top = top / (1.0 + 2.6 * bend)
		if to_end < 16.0:
			top = minf(top, 4.0 + to_end * 0.35)
		top = minf(top, lerpf(13.5, 3.0, clampf(absf(off) / 0.7, 0.0, 1.0)))      # slowly round a corner
		# the car in front
		for o in lanes[Vector2i(c["w"], c["dir"])]:
			var gap: float = (o["s"] - c["s"]) * c["dir"]
			if o != c and gap > 0.0 and gap < 9.0 + c["v"] * 1.4:
				top = minf(top, maxf(0.0, (gap - 6.5) * 0.9))
		# the player, on foot or in something, in the way ahead
		var rel := here - p
		var front := rel.dot(fwd)
		if front > -1.0 and front < 7.0 + c["v"] * 1.6 and absf(rel.dot(Vector2(-fwd.y, fwd.x))) < 2.3 and absf(pp.y - _height(p)) < 3.0:
			if c["v"] > 0.5 and top > 0.0:
				stats["stops_for_player"] += 1
			top = 0.0
			# kept waiting, it sounds its horn (once, and then not again for a while)
			c["held"] = float(c.get("held", 0.0)) + delta
			if float(c["held"]) > 3.0 and snd != null:
				c["held"] = -8.0
				snd.play_at("horn", Vector3(p.x, _height(p) + 1.0, p.y), 0.9)
		else:
			c["held"] = minf(float(c.get("held", 0.0)), 0.0)
		# somebody walking in the way ahead (on a crossing, or anywhere else): it waits for them
		for wk in walkers:
			var rw: Vector2 = wk - p
			var fw: float = rw.dot(fwd)
			if fw > 0.5 and fw < 6.0 + c["v"] * 1.4 and absf(rw.dot(Vector2(-fwd.y, fwd.x))) < 2.0:
				if c["v"] > 0.5 and top > 0.0:
					stats["stops_for_walkers"] += 1
				top = 0.0
		# another car across its way (at a junction, on a roundabout): the one already there goes first. Of two
		# that both stand, the one made first goes, so they do not wait for each other for ever.
		for oi in cars.size():
			var o2: Dictionary = cars[oi]
			if oi == i or (o2["w"] == c["w"] and o2["dir"] == c["dir"]):
				continue
			var ro: Vector2 = (o2["pos"] as Vector2) - p
			var fo: float = ro.dot(fwd)
			if fo > 1.5 and fo < 5.5 + c["v"] * 1.2 and absf(ro.dot(Vector2(-fwd.y, fwd.x))) < 1.7 and (o2["head"] as Vector2).dot(fwd) > -0.6:
				if float(o2["v"]) > 0.6 or oi < i:
					if c["v"] > 0.5 and top > 0.0:
						stats["gave_way"] += 1
					top = 0.0
		c["v"] = move_toward(c["v"], top, (2.4 if top > c["v"] else 7.0) * delta)
		# the point ahead keeps its lead: it runs on faster when the car has come close to it, and waits when the car is far behind
		var before: float = c["s"]
		c["s"] += c["v"] * c["dir"] * delta * clampf(1.0 + (lead - p.distance_to(aim)) / lead, 0.0, 2.5)
		# passing (or reaching) a place where another road meets this one: on along this road, or off by the other
		var st: PackedFloat32Array = _stations[c["w"]]
		for k in st.size():
			if (st[k] - before) * c["dir"] > 0.0 and (st[k] - c["s"]) * c["dir"] <= 0.0:
				var last: bool = k == (st.size() - 1 if c["dir"] > 0 else 0)
				var options: Array = []
				for o in _links.get(Vector2i(c["w"], k), []):
					var so: PackedFloat32Array = _stations[o.x]
					if o.y < so.size() - 1:
						options.append([o, 1])
					if o.y > 0:
						options.append([o, -1])
				if last and options.is_empty():
					c["dir"] = -c["dir"]                            # a dead end: round and back (the car turns in as wide a circle as it needs)
					c["s"] = clampf(c["s"], 0.0, length)
				elif last or (not options.is_empty() and _rng.randf() < 0.3):
					var pick: Array = options[_rng.randi_range(0, options.size() - 1)]
					c["w"] = pick[0].x
					c["dir"] = pick[1]
					c["s"] = (_stations[pick[0].x] as PackedFloat32Array)[pick[0].y]
					stats["turns"] += 1
				break
		# steer toward the point and drive: the heading turns no faster than a turning circle of 4.5 m radius allows
		aim = _lane_point(_ways[c["w"]], c["s"], c["dir"])
		off = fwd.angle_to(aim - p) if p.distance_to(aim) > 0.3 else 0.0
		var most: float = c["v"] * delta / 4.5
		fwd = fwd.rotated(clampf(off, -most, most))
		c["head"] = fwd
		c["pos"] = p + fwd * c["v"] * delta
		c["steer"] = lerpf(c["steer"], clampf(-off, -0.55, 0.55), minf(1.0, 5.0 * delta))
		i -= 1
	# draw them, and make the nearest few solid
	var near := []
	var step_ok := delta < 0.05                                 # (the checks below mean nothing over a long frame)
	for c in cars:
		var p2: Vector2 = c["pos"]
		var xf := _xf(Vector3(p2.x, _height(p2) - 0.08, p2.y), c["head"])
		if not c.has("node"):
			var tq330 := Time.get_ticks_usec()
			_show(c)
			world.took("t_show", tq330)
		elif step_ok:
			stats["sharpest_swing_deg"] = maxf(stats.get("sharpest_swing_deg", 0.0), absf(rad_to_deg((c["drawn"] as Vector2).angle_to(c["head"]))))
			var was: Vector3 = (c["node"] as Node3D).global_position
			stats["longest_jump_m"] = maxf(stats.get("longest_jump_m", 0.0), Vector2(was.x, was.z).distance_to(p2) - c["v"] * delta)
		c["drawn"] = c["head"]
		(c["node"] as Node3D).global_transform = xf
		# the wheels turn with the road covered, and the front ones point the way the car is steering
		var m: Dictionary = _models[c["model"]]
		c["spin"] += c["v"] * delta / float(m["wheel_r"])
		var hubs: Array = c["hubs"]
		for q in 4:
			(hubs[q][0] as Node3D).rotation.y = c["steer"] if q < 2 else 0.0
			(hubs[q][1] as Node3D).rotation.y = c["spin"]
		near.append([Vector3(p2.x, 0, p2.y).distance_squared_to(Vector3(pp.x, 0, pp.z)), xf])
	near.sort_custom(func(x, y): return x[0] < y[0])
	for k in SOLID:
		if k < near.size() and near[k][0] < 70.0 * 70.0:
			_bodies[k].global_transform = near[k][1]
		else:
			_bodies[k].position = Vector3(0, -500, 0)
	var tq351 := Time.get_ticks_usec()
	_run_parked(delta, pp)
	world.took("t_parked", tq351)
	var tq352 := Time.get_ticks_usec()
	_run_buses(delta, here, pp)
	world.took("t_buses", tq352)
	var tq353 := Time.get_ticks_usec()
	_run_boats(delta, pp)
	world.took("t_boats", tq353)
	var tq354 := Time.get_ticks_usec()
	_run_plane(delta)
	world.took("t_plane", tq354)


# ------------------------------------------------------------------ parked cars
## The cars standing parked all over town are simple boxes, drawn in their hundreds from afar. Those within 90 m
## of the player are stood in again as cars of the traffic's twenty models (which one is settled by where the
## car stands, so it is always the same), in the parked car's own colour, and the box in that place is put away;
## beyond 110 m the box comes back. Not more than forty at a time, the nearest.
var _parked_shown := {}                  # where it stands (in decimetres) -> {the record from scripts/props.gd, the car}
var _parked_in := 0.0


func _run_parked(delta: float, pp: Vector3) -> void:
	_parked_in -= delta
	if _parked_in > 0.0:
		return
	_parked_in = 0.4
	var want := []
	var cell := Vector2i(int(floor(pp.x / 100.0)), int(floor(pp.z / 100.0)))
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			for e in world.props.parked.get(cell + Vector2i(dx, dz), []):
				var at: Vector3 = (e[0] as Transform3D).origin
				var d := Vector2(at.x - pp.x, at.z - pp.z).length()
				if d < 90.0:
					want.append([d, Vector2i(int(round(at.x * 10.0)), int(round(at.z * 10.0))), e])
	want.sort_custom(func(x, y): return x[0] < y[0])
	var keep := {}
	for k in mini(want.size(), 40):
		var key: Vector2i = want[k][1]
		keep[key] = true
		if _parked_shown.has(key):
			continue
		var e: Array = want[k][2]
		var c := {"model": posmod(hash(key), _models.size()), "col": e[1]}
		var tq389 := Time.get_ticks_usec()
		_show(c)
		world.took("t_show", tq389)
		var xf: Transform3D = e[0]
		var stand: Vector3 = xf.origin
		var paved: float = world.detail.surface_at(stand.x, stand.z)
		if not is_nan(paved):
			stand.y = maxf(stand.y, paved)                      # on the asphalt or the paving, not sunk in it
		# it stands on the ground as the ground lies: nose and tail, left and right wheels each at their own height
		# (standing level on a sloping car park, one end of it was sunk in the asphalt: note of 18 Nov)
		var bs := xf.basis.orthonormalized()
		var fw := -bs.z
		var rt := bs.x
		var hf: float = _height(Vector2(stand.x + fw.x * 1.3, stand.z + fw.z * 1.3)) - 0.03
		var hb: float = _height(Vector2(stand.x - fw.x * 1.3, stand.z - fw.z * 1.3)) - 0.03
		var hl: float = _height(Vector2(stand.x - rt.x * 0.75, stand.z - rt.z * 0.75)) - 0.03
		var hr: float = _height(Vector2(stand.x + rt.x * 0.75, stand.z + rt.z * 0.75)) - 0.03
		stand.y = (hf + hb + hl + hr) * 0.25                    # (as the cars that drive stand: on the laid asphalt)
		var up := Vector3(0, 1, 0) - fw * ((hf - hb) / 2.6) - rt * ((hr - hl) / 1.5)
		up = up.normalized()
		var fwd := (fw - up * fw.dot(up)).normalized()
		(c["node"] as Node3D).global_transform = Transform3D(Basis(fwd.cross(up).normalized(), up, -fwd), stand)
		(e[2] as MultiMesh).set_instance_transform(e[3], Transform3D(Basis().scaled(Vector3(0.001, 0.001, 0.001)), (e[4] as Transform3D).origin - Vector3(0, 60, 0)))
		_parked_shown[key] = {"rec": e, "car": c}
	for key in _parked_shown.keys():
		if keep.has(key):
			continue
		var rec: Array = _parked_shown[key]["rec"]
		var at2: Vector3 = (rec[0] as Transform3D).origin
		if Vector2(at2.x - pp.x, at2.z - pp.z).length() > 110.0 or _parked_shown.size() > 60:
			_forget(_parked_shown[key]["car"])
			(rec[2] as MultiMesh).set_instance_transform(rec[3], rec[4])
			_parked_shown.erase(key)


# ------------------------------------------------------------------ the car models
## Build each of the twenty models once (scripts/traffic_car.gd): its body and one wheel, to be drawn for every
## car of that model on the road.
func _build_models() -> void:
	var maker: GDScript = load("res://scripts/traffic_car.gd")
	for s in maker.MODELS:
		var car = maker.new()
		car.use(s)
		car.position = Vector3(0, -900, 0)
		add_child(car)                                              # (it builds itself on entering the tree)
		_models.append({"name": s["name"], "body": car._body_mesh, "wheel": ((car._wheels[0][1] as Node3D).get_child(0) as MeshInstance3D).mesh,
			"track": car.TRACK, "wheel_r": car.WHEEL_R, "axle_f": car.AXLE_F, "axle_r": car.AXLE_R, "wb": car.AXLE_R - car.AXLE_F, "paints": s["paints"]})
		remove_child(car)
		car.queue_free()


## Put a car on show: its model's body in its own colour, and four wheels that turn and steer.
func _show(c: Dictionary) -> void:
	var m: Dictionary = _models[c["model"]]
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	body.mesh = m["body"]
	body.set_instance_shader_parameter("paint", c["col"])
	root.add_child(body)
	var hubs := []
	for front in [true, false]:
		for sx in [-float(m["track"]), float(m["track"])]:
			var hub := Node3D.new()
			hub.position = Vector3(sx, m["wheel_r"], m["axle_f"] if front else m["axle_r"])
			root.add_child(hub)
			var turn := Node3D.new()
			turn.rotation.z = PI * 0.5
			hub.add_child(turn)
			var roll := Node3D.new()
			turn.add_child(roll)
			var mi := MeshInstance3D.new()
			mi.mesh = m["wheel"]
			roll.add_child(mi)
			hubs.append([hub, roll])
	add_child(root)
	c["node"] = root
	c["hubs"] = hubs


func _forget(c: Dictionary) -> void:
	if c.has("node"):
		(c["node"] as Node3D).queue_free()
		c.erase("node")


# ------------------------------------------------------------------ lanes
## The place in its lane of a point a distance along a road, for a car going the given way along it.
func _lane_point(way: Array, s: float, dir: int) -> Vector2:
	var length := _length(way)
	var a := _along(way, clampf(s, 0.0, length))
	var fwd: Vector2 = a[1] * float(dir)
	# (past either end of the road its line is carried straight on, so that a car at the very end still has a
	# point ahead of it and one behind)
	return a[0] + (a[1] as Vector2) * (s - clampf(s, 0.0, length)) + Vector2(-fwd.y, fwd.x) * minf(float(a[2]) * 0.5, 1.7)


## A new car on a road some way from the player.
func _make_car(here: Vector2) -> void:
	for attempt in 6:
		var a := _rng.randf() * TAU
		var r := _rng.randf_range(NEAR + 20.0, FAR - 80.0)
		var q := here + Vector2(cos(a), sin(a)) * r
		var list = world.detail.road_cells.get(world.detail.cell_of(q.x, q.y))
		if list == null:
			continue
		var k: int = _rng.randi_range(0, list.size() / 2 - 1) * 2
		var way: Array = world.detail.ways[list[k]]
		var wi: int = _way_of.get(list[k], -1)          # (not _ways.find: that compares whole roads, 12 ms a time)
		if wi < 0:
			continue
		var s: float = (way[7] as PackedFloat32Array)[list[k + 1]]
		if (_along(way, s)[0] as Vector2).distance_to(here) < NEAR:
			continue
		var crowded := false
		for c in cars:
			if c["w"] == wi and absf(c["s"] - s) < 14.0:
				crowded = true
		if crowded:
			continue
		var model := _rng.randi_range(0, _models.size() - 1)
		var paints: Array = _models[model]["paints"]
		cars.append({"w": wi, "dir": 1 if _rng.randf() < 0.5 else -1, "s": s, "v": 6.0, "model": model,
			"col": paints[_rng.randi_range(0, paints.size() - 1)], "spin": 0.0, "steer": 0.0})
		var made: Dictionary = cars[cars.size() - 1]
		made["head"] = (_along(way, s)[1] as Vector2) * float(made["dir"])
		made["pos"] = _lane_point(way, s, made["dir"])
		made["s"] = s + 5.0 * float(made["dir"])                    # (the point it drives toward starts out ahead of it)
		stats["made"] += 1
		return


# ------------------------------------------------------------------ buses
## The shortest way along the roads between two stations: legs of [road, from distance, to distance].
func _route(from: Vector2i, to: Vector2i) -> Array:
	var best := {from: 0.0}
	var came := {}
	var open := [[0.0, from]]
	var done := {}
	while not open.is_empty():
		var lowest := 0
		for i in open.size():
			if open[i][0] < open[lowest][0]:
				lowest = i
		var cur: Array = open[lowest]
		open.remove_at(lowest)
		var node: Vector2i = cur[1]
		if done.has(node):
			continue
		done[node] = true
		if node == to:
			break
		var st: PackedFloat32Array = _stations[node.x]
		var slow := 1.0 if float(_ways[node.x][0]) >= 3.2 else 1.7           # (buses keep to the bigger roads)
		var nexts := []
		if node.y + 1 < st.size():
			nexts.append([Vector2i(node.x, node.y + 1), (st[node.y + 1] - st[node.y]) * slow])
		if node.y > 0:
			nexts.append([Vector2i(node.x, node.y - 1), (st[node.y] - st[node.y - 1]) * slow])
		for o in _links.get(node, []):
			nexts.append([o, 6.0])
		for nx in nexts:
			var cost: float = cur[0] + nx[1]
			if cost < best.get(nx[0], 1e18):
				best[nx[0]] = cost
				came[nx[0]] = node
				open.append([cost, nx[0]])
	if not came.has(to):
		return []
	var chain := [to]
	while came.has(chain[0]):
		chain.push_front(came[chain[0]])
	var legs := []
	for i in chain.size() - 1:
		var a: Vector2i = chain[i]
		var b: Vector2i = chain[i + 1]
		if a.x != b.x:
			continue                                            # crossing over to the other road
		var s0: float = (_stations[a.x] as PackedFloat32Array)[a.y]
		var s1: float = (_stations[a.x] as PackedFloat32Array)[b.y]
		if not legs.is_empty() and legs[legs.size() - 1][0] == a.x and is_equal_approx(legs[legs.size() - 1][2], s0):
			legs[legs.size() - 1][2] = s1
		else:
			legs.append([a.x, s0, s1])
	return legs


## A way along the roads from one place to another, as points a few metres apart (for jobs, the driving checks
## and anything else that needs to know how to get somewhere). Empty if the roads do not join up.
func route_points(a: Vector2, b: Vector2, step := 4.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	for leg in _route(_nearest_station(a), _nearest_station(b)):
		var way: Array = _ways[leg[0]]
		var n := maxi(int(absf(leg[2] - leg[1]) / step), 1)
		for i in n + 1:
			var q: Vector2 = _along(way, lerpf(leg[1], leg[2], float(i) / n))[0]
			if out.is_empty() or out[out.size() - 1].distance_to(q) > 0.5:
				out.append(q)
	return out


## A bus line as places in the world: {"way": points every 5 m from the bus square outward, "stops": its stops in order}.
func line_points(k: int) -> Dictionary:
	var b: Dictionary = buses[k]
	var way := PackedVector2Array()
	var stops: Array = []
	var run := 0.0
	var next := 0
	var at: Array = b["stops"]
	for leg in b["path"]:
		var w: Array = _ways[leg[0]]
		var span: float = absf(leg[2] - leg[1])
		var dir: float = signf(leg[2] - leg[1])
		var n := maxi(int(span / 5.0), 1)
		for i in n + 1:
			way.append(_along(w, leg[1] + dir * span * float(i) / n)[0])
		while next < at.size() and float(at[next]) <= run + span:
			var a := _along(w, leg[1] + dir * (float(at[next]) - run))
			var fwd: Vector2 = (a[1] as Vector2) * dir
			stops.append((a[0] as Vector2) + Vector2(-fwd.y, fwd.x) * minf(float(a[2]) * 0.5, 1.9))
			next += 1
		run += span
	if stops.is_empty() or (stops[stops.size() - 1] as Vector2).distance_to(way[way.size() - 1]) > 80.0:
		stops.append(way[way.size() - 1])                    # (the end of the line is a stop too)
	return {"way": way, "stops": stops}


## The ferry gets on with it (somebody on board is passing the time): `extra` more seconds of sailing now.
func hurry_ferry(extra: float) -> void:
	for b in _boats:
		if b["kind"] == "ferry" and float(b["wait"]) <= 0.0:
			var total: float = (b["a"] as Vector2).distance_to(b["b"])
			b["t"] = clampf(float(b["t"]) + float(b["v"]) * extra * (1.0 if b["going"] else -1.0), 0.0, total)


## The station nearest a place, on a road wide enough for a bus.
func _nearest_station(p: Vector2) -> Vector2i:
	var best := Vector2i.ZERO
	var d := 1e18
	for w in _ways.size():
		if float(_ways[w][0]) < 2.6:
			continue
		var st: PackedFloat32Array = _stations[w]
		for k in st.size():
			var q: Vector2 = _along(_ways[w], st[k])[0]
			if q.distance_squared_to(p) < d and _links.has(Vector2i(w, k)):
				d = q.distance_squared_to(p)
				best = Vector2i(w, k)
	return best


func _setup_buses() -> void:
	var start := _nearest_station(BUS_SQUARE)
	var stops := []
	for key in world.props.cells:
		for rec in world.props.cells[key]:
			if rec[0] == world.props.BUS_SIGN or rec[0] == world.props.SHELTER:
				stops.append(Vector2((rec[1] as Transform3D).origin.x, (rec[1] as Transform3D).origin.z))
	# three lines: west, east and up the hill; each goes as far out as the roads join up
	for line in [[Vector2(-4300.0, 300.0), Vector2(-2600.0, 100.0), Vector2(-1300.0, 150.0)], [Vector2(4300.0, -900.0), Vector2(2600.0, -500.0), Vector2(1400.0, -300.0)],
			[Vector2(-500.0, -1500.0), Vector2(-300.0, -900.0), Vector2(200.0, -600.0)]]:
		var path := []
		for target in line:
			path = _route(start, _nearest_station(target))
			if path.size() >= 3:
				break
		if path.size() < 3:
			continue
		# where along the route the bus stops are
		var at := []
		var run := 0.0
		for leg in path:
			var way: Array = _ways[leg[0]]
			var pts: PackedVector2Array = way[3]
			var dist: PackedFloat32Array = way[7]
			var lo: float = minf(leg[1], leg[2])
			var hi: float = maxf(leg[1], leg[2])
			var found := []
			for k in range(0, pts.size(), 2):
				if dist[k] < lo or dist[k] > hi:
					continue
				for st in stops:
					if (st as Vector2).distance_squared_to(pts[k]) < 100.0:
						found.append(run + absf(dist[k] - leg[1]))
			found.sort()
			for s2 in found:
				if at.is_empty() or s2 - at[at.size() - 1] > 60.0:
					at.append(s2)
			run += hi - lo
		buses.append({"path": path, "leg": 0, "s": 0.0, "v": 0.0, "wait": 20.0 + 25.0 * buses.size(), "back": false, "stops": at, "run": 0.0, "total": run, "next": 0})
	# each is a bus of its own (scripts/bus.gd): FRAM's blue, with wheels that turn
	for b in buses:
		var made: Dictionary = BusModel.make()
		b["node"] = made["node"]
		b["wheels"] = made["wheels"]
		b["steer"] = made["steer"]
		b["roll"] = 0.0
		(b["node"] as Node3D).position = Vector3(0, -900, 0)
		add_child(b["node"])


func _run_buses(delta: float, here: Vector2, pp: Vector3) -> void:
	for k in buses.size():
		var b: Dictionary = buses[k]
		var leg: Array = b["path"][b["leg"]]
		var way: Array = _ways[leg[0]]
		var span: float = absf(leg[2] - leg[1])
		var from: float = leg[2] if b["back"] else leg[1]
		var to: float = leg[1] if b["back"] else leg[2]
		var dir := 1 if to >= from else -1
		var s_way: float = from + b["s"] * dir                      # (b.s is how far along this leg it has come)
		var pose := _pose(way, s_way, dir, 1.9)
		if b.has("blend"):
			var t: float = smoothstep(0.0, 1.0, b["blend"])
			pose = [(pose[0] as Vector3).lerp(b["from"][0], t), (pose[1] as Vector2).lerp(b["from"][1], t).normalized()]
			b["blend"] -= delta / 1.2
			if b["blend"] <= 0.0:
				b.erase("blend")
		if b["wait"] > 0.0:
			b["wait"] -= delta
			b["v"] = 0.0
		else:
			var a := _along(way, s_way)
			var fwd: Vector2 = a[1] * float(dir)
			var top := 11.0 if float(a[2]) >= 3.2 else 7.5
			var a2 := _along(way, s_way + 14.0 * dir)
			top = top / (1.0 + 3.0 * absf(fwd.angle_to(a2[1] * float(dir))))
			if span - b["s"] < 14.0:
				top = minf(top, 4.5)                                # a turn coming
			# the next stop along the route (b.run is how far along the route this leg begins, going out)
			var out_at: float = b["run"] + (b["s"] if not b["back"] else span - b["s"])
			var stops: Array = b["stops"]
			if b["next"] < stops.size():
				var to_stop: float = (stops[b["next"]] - out_at) if not b["back"] else (out_at - stops[stops.size() - 1 - b["next"]])
				if to_stop < 1.5:
					b["wait"] = 6.0
					b["next"] += 1
					var folk2 = get_parent().get("people")
					if folk2 != null:                               # those waiting at the stop get on
						folk2.bus_called(Vector2((pose[0] as Vector3).x, (pose[0] as Vector3).z))
					stats["bus_stops"] += 1
				elif to_stop < 40.0:
					top = minf(top, 1.5 + to_stop * 0.3)
			var rel := here - Vector2((pose[0] as Vector3).x, (pose[0] as Vector3).z)
			if rel.dot(fwd) > -1.0 and rel.dot(fwd) < 9.0 + b["v"] * 1.6 and absf(rel.dot(Vector2(-fwd.y, fwd.x))) < 2.6 and absf(pp.y - (pose[0] as Vector3).y) < 3.0:
				top = 0.0
			b["v"] = move_toward(b["v"], top, (1.4 if top > b["v"] else 5.0) * delta)
			b["s"] += b["v"] * delta
			if b["s"] >= span:
				b["from"] = pose
				b["blend"] = 1.0
				b["s"] = 0.0
				b["run"] += span * (1.0 if not b["back"] else 0.0)
				b["leg"] += -1 if b["back"] else 1
				if b["leg"] < 0 or b["leg"] >= (b["path"] as Array).size():
					# the end of the line: wait, then back the way it came (a long wait at the bus square)
					b["back"] = not b["back"]
					b["leg"] = clampi(b["leg"], 0, (b["path"] as Array).size() - 1)
					b["next"] = 0
					b["wait"] = 12.0 if b["back"] else 25.0
					b["run"] = b["total"] if b["back"] else 0.0
				if b["back"]:
					var nl: Array = b["path"][b["leg"]]
					b["run"] -= absf(nl[2] - nl[1])
		var bus: Node3D = b["node"]
		var xf_new := _xf(pose[0], pose[1])
		var was := bus.transform
		bus.transform = xf_new
		# the wheels turn by how far it has come, and the front ones steer the way it is turning
		var moved: float = (xf_new.origin - was.origin).dot(-xf_new.basis.z) if was.origin.y > -800.0 else 0.0
		if absf(moved) < 5.0:
			b["roll"] = fposmod(float(b["roll"]) - moved / BusModel.WHEEL_R, TAU)
			var turn := clampf(was.basis.z.signed_angle_to(xf_new.basis.z, Vector3.UP) * 6.1 / maxf(absf(moved), 0.02), -0.6, 0.6) if absf(moved) > 0.002 else 0.0
			for w in b["wheels"]:
				(w as Node3D).rotation.x = b["roll"]
			for h in b["steer"]:
				(h as Node3D).rotation.y = lerpf((h as Node3D).rotation.y, turn, 0.2)


# ------------------------------------------------------------------ boats
func _open_water(p: Vector2, least: float) -> bool:
	var w: Dictionary = world.water_at(p.x, p.y)
	return not w.is_empty() and w["level"] == 0.0 and w["depth"] > least


func _setup_boats() -> void:
	var ferry_at = null
	var cruise_at = null
	for key in world.props.cells:
		for rec in world.props.cells[key]:
			# (the ferry at the quay for Vestnes, east of the centre: not the one out at Hjertøya, which the
			# sailing ferry started from before, far out and away over the edge of the map)
			if rec[0] == world.props.FERRY and (ferry_at == null or (rec[1] as Transform3D).origin.distance_to(Vector3(510, 0, 68)) < (ferry_at as Transform3D).origin.distance_to(Vector3(510, 0, 68))):
				ferry_at = rec[1]
			if rec[0] == world.props.CRUISE:
				cruise_at = rec[1]
	# a ferry out across the fjord and back
	if ferry_at != null:
		var from := Vector2((ferry_at as Transform3D).origin.x, (ferry_at as Transform3D).origin.z)
		var out := Vector2(0, 1)
		var far := 0.0
		for k in 24:                                     # the way to the most open water
			var d := Vector2(cos(k * TAU / 24.0), sin(k * TAU / 24.0))
			var r := 0.0
			while r < 2500.0 and _open_water(from + d * (r + 60.0), 3.0):
				r += 60.0
			if r > far and d.y > 0.2:
				far = r
				out = d
		if far > 600.0:
			var far_end: Vector2 = from + out * minf(far - 100.0, 2300.0) + Vector2(-0.4, 0.9).normalized() * 2200.0
			far_end = far_end.clamp(Vector2(world.x0 + 300.0, world.z0 + 300.0), Vector2(world.x1 - 300.0, world.z1 - 200.0))      # (it turns inside the map)
			_add_boat(world.props.FERRY, {"kind": "ferry", "a": from + out * 190.0, "b": far_end,
				"t": 0.0, "v": 0.0, "going": true, "wait": 40.0, "top": 8.0, "reach": 26.0})
	# small boats pottering about off the harbour
	var made := 0
	for attempt in 80:
		if made >= 5:
			break
		var c := Vector2(_rng.randf_range(-900.0, 900.0), _rng.randf_range(120.0, 620.0))
		var r := _rng.randf_range(50.0, 140.0)
		var ok := true
		for k in 12:
			if not _open_water(c + Vector2(cos(k * TAU / 12.0), sin(k * TAU / 12.0) * 0.6) * (r + 12.0), 3.0):
				ok = false
		if ok:
			_add_boat(world.props.BOAT, {"kind": "boat", "c": c, "r": r, "t": _rng.randf() * TAU, "top": _rng.randf_range(1.6, 3.2), "turn": 1.0 if made % 2 == 0 else -1.0, "reach": 3.5})
			made += 1
	# the coastal steamer: in from the west to lie off the quay, morning and evening
	if cruise_at != null:
		var xf: Transform3D = cruise_at
		var berth := Vector2(xf.origin.x, xf.origin.z)
		for sign in [1.0, -1.0]:
			for off in [70.0, 100.0]:
				var q: Vector2 = Vector2(xf.origin.x, xf.origin.z) + Vector2(xf.basis.x.x, xf.basis.x.z) * off * sign
				if _open_water(q, 6.0) and berth == Vector2(xf.origin.x, xf.origin.z):
					berth = q
		var heading := Vector2(-xf.basis.z.x, -xf.basis.z.z).normalized()
		_add_boat(world.props.CRUISE, {"kind": "steamer", "berth": berth, "heading": heading, "reach": 16.0, "scale": 0.62})


func _add_boat(mesh_kind: int, state: Dictionary) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes[mesh_kind]
	if state.has("scale"):
		mi.scale = Vector3.ONE * float(state["scale"])
	add_child(mi)
	state["node"] = mi
	state["last"] = Vector3.ZERO
	_boats.append(state)


func _run_boats(delta: float, pp: Vector3) -> void:
	for b in _boats:
		var node: MeshInstance3D = b["node"]
		var pos := Vector2.ZERO
		var fwd := Vector2(0, -1)
		var speed := 0.0
		if b["kind"] == "boat":
			b["t"] += delta * float(b["top"]) / float(b["r"]) * float(b["turn"])
			pos = (b["c"] as Vector2) + Vector2(cos(b["t"]), sin(b["t"]) * 0.6) * float(b["r"])
			fwd = (Vector2(-sin(b["t"]), cos(b["t"]) * 0.6) * float(b["turn"])).normalized()
			speed = b["top"]
		elif b["kind"] == "ferry":
			var a: Vector2 = b["a"]
			var c: Vector2 = b["b"]
			var total := a.distance_to(c)
			if b["wait"] > 0.0:
				b["wait"] -= delta
				b["v"] = 0.0
			else:
				var left: float = (total - b["t"]) if b["going"] else b["t"]
				if float(b["v"]) == 0.0 and b["going"] and float(b["t"]) < 1.0 and get_parent().get("sound") != null:
					get_parent().get("sound").play_at("ship_horn", Vector3(a.x, 8.0, a.y), 1.6)      # casting off
				b["v"] = move_toward(b["v"], minf(b["top"], 0.6 + left * 0.06), 0.5 * delta)
				b["t"] += b["v"] * delta * (1.0 if b["going"] else -1.0)
				if (b["going"] and b["t"] >= total) or (not b["going"] and b["t"] <= 0.0):
					b["t"] = clampf(b["t"], 0.0, total)
					b["going"] = not b["going"]
					b["wait"] = 90.0
					if b["going"] and daytime != null and float(daytime.rate) > 0.0:
						# back at Molde: it leaves by the clock, on the next hour or half hour that is at least
						# half a minute away (an hour of the game's day is 100 seconds at the usual rate)
						var per_hour: float = 100.0 / float(daytime.rate)
						var leave: float = ceil((float(daytime.hours) + 30.0 / per_hour) * 2.0) / 2.0
						b["wait"] = (leave - float(daytime.hours)) * per_hour
						b["leaves"] = "%02d:%02d" % [int(leave) % 24, int(fposmod(leave, 1.0) * 60.0)]
			pos = a.lerp(c, b["t"] / total)
			fwd = (c - a).normalized() * (1.0 if b["going"] else -1.0)
			speed = b["v"]
		else:
			# the steamer by the clock: alongside 09:30 to 10:15 and 21:00 to 22:00, sailing in for half an hour
			# before and out for half an hour after, away the rest of the day
			var h: float = daytime.hours if daytime != null else 12.0
			var away := 1.0
			var leaving := false
			for call in [[9.5, 10.25], [21.0, 22.0]]:
				if h >= call[0] - 0.5 and h < call[0]:
					away = (call[0] - h) / 0.5
				elif h >= call[0] and h < call[1]:
					away = 0.0
				elif h >= call[1] and h < call[1] + 0.5:
					away = (h - call[1]) / 0.5
					leaving = true
			var berth: Vector2 = b["berth"]
			var head: Vector2 = b["heading"]
			var out := berth + Vector2(-1.0, 0.25).normalized() * 3800.0 if not leaving else berth + Vector2(1.0, 0.35).normalized() * 3800.0
			var ease := away * away * (3.0 - 2.0 * away)
			pos = berth.lerp(out, ease)
			fwd = head if away < 0.02 else ((berth - out).normalized() if not leaving else (out - berth).normalized())
			node.visible = away < 0.999
			speed = 0.0 if away < 0.02 or away > 0.98 else 4.0
		var y := 0.0 + sin(Time.get_ticks_msec() * 0.0011 + pos.x) * 0.05
		var f3 := Vector3(fwd.x, 0, fwd.y)
		node.global_transform = Transform3D(Basis(f3.cross(Vector3.UP), Vector3.UP, -f3).scaled(node.scale), Vector3(pos.x, y, pos.y))
		# a wake where the player can see it move the water
		if speed > 0.3 and Vector2(pp.x, pp.z).distance_to(pos) < 60.0 + float(b["reach"]):
			world.ripples.push(pos + fwd * float(b["reach"]) * 0.5, minf(float(b["reach"]) * 0.5, 7.0), 0.004 * speed, 0.7)
			world.ripples.push(pos - fwd * float(b["reach"]) * 0.5, minf(float(b["reach"]) * 0.4, 6.0), 0.003 * speed, 0.9)


# ------------------------------------------------------------------ planes
func _run_plane(delta: float) -> void:
	if _plane == null or amount == 0:
		return
	if _plane_t < 0.0:
		_plane_in -= delta
		if _plane_in <= 0.0:
			_plane_in = _rng.randf_range(240.0, 480.0)
			_plane_t = 0.0
			_plane_lands = not _plane_lands
			_plane.visible = true
			stats["flights"] += 1
		return
	_plane_t += delta
	var a := _runway[0]
	var b := _runway[_runway.size() - 1]
	var along := (b - a).normalized()
	var length := a.distance_to(b)
	var d := 0.0                                        # metres from the runway's start (before it: negative)
	var up := 0.0
	var nose := 0.0
	if _plane_lands:
		# down a three-degree slope to touch down 250 m in, then rolling out
		var t := _plane_t
		var touch := 32.0
		if t < touch:
			d = 250.0 - (touch - t) * 72.0
			up = (touch - t) * 72.0 * 0.052
			nose = 0.05
		else:
			var roll := t - touch
			d = 250.0 + 72.0 * roll - 0.5 * 2.3 * roll * roll
			if roll > 72.0 / 2.3:
				_plane_t = -1.0
				_plane.visible = false
				return
	else:
		var t := _plane_t
		var run := minf(t, 30.0)
		d = 150.0 + 0.5 * 2.6 * run * run
		if t > 30.0:
			var air := t - 30.0
			d += 78.0 * air
			up = 9.0 * air + 0.4 * air * air
			nose = 0.16
			if air > 40.0:
				_plane_t = -1.0
				_plane.visible = false
				return
	var p := a + along * d
	var ground: float = world.height_at(clampf(p.x, world.x0 + 5.0, world.x1 - 5.0), clampf(p.y, world.z0 + 5.0, world.z1 - 5.0)) if d > 0.0 and d < length else world.height_at(a.x, a.y)
	var f3 := Vector3(along.x, nose, along.y).normalized()
	var right := f3.cross(Vector3.UP).normalized()
	_plane.global_transform = Transform3D(Basis(right, right.cross(f3).normalized(), -f3), Vector3(p.x, ground + 0.1 + up, p.y))
