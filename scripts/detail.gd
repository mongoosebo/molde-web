extends Node3D
## Close-up detail, built around the player as they move and dropped again behind them:
## dressed buildings (scripts/facades.gd) in place of the plain blocks, and real road surfaces
## with markings, kerbs, sidewalks and zebra crossings on top of the painted terrain.

const Facades := preload("res://scripts/facades.gd")

const CELL := 100.0
const NEAR := 240.0            # build cells whose centre is this close
const FAR := 340.0             # and drop them beyond this
const BUDGET_USEC := 5000      # building work per frame

const ASPHALT := Color(0.42, 0.42, 0.44)
const PATH := Color(0.50, 0.49, 0.48)
const SIDEWALK := Color(0.78, 0.77, 0.75)
const KERB := Color(0.50, 0.50, 0.51)
const YELLOW := Color(0.86, 0.66, 0.10)
const WHITE := Color(0.90, 0.90, 0.88)
const SHOULDER := Color(0.36, 0.34, 0.31)

var world
var fac
var buildings := {}            # cell -> [rec, ...]
var far_meshes := {}           # cell -> MeshInstance3D (the plain blocks)
var road_cells := {}           # cell -> PackedInt32Array [way, station, way, station, ...]
var paved := {}                # cell -> [asphalt triangles, sidewalk triangles, kerb pieces, shoulder pieces] (x, z floats)
var ways: Array = []           # [half, kind, mark, pts, normals, fl, fr, dist, graded height, surface height]

var _cells := {}               # cell -> Node3D (finished)
var _job_key := Vector2i(-99999, -99999)
var _job: Dictionary = {}
var _centre := Vector3(1e9, 0, 1e9)
var _queue: Array = []


func setup(w) -> void:
	world = w
	fac = Facades.new()
	_load_roads()
	_load_paved()


static func cell_of(x: float, z: float) -> Vector2i:
	return Vector2i(int(floor(x / CELL)), int(floor(z / CELL)))


func add_building(rec: Dictionary, key: Vector2i) -> void:
	if not buildings.has(key):
		buildings[key] = []
	buildings[key].append(rec)


func _load_roads() -> void:
	var data := FileAccess.get_file_as_bytes("res://world/roads.bin").to_float32_array()
	var i := 0
	while i + 4 <= data.size():
		var n := int(data[i])
		var half := data[i + 1]
		var kind := int(data[i + 2])
		var mark := int(data[i + 3])
		i += 4
		var pts := PackedVector2Array()
		var fl := PackedByteArray()
		var fr := PackedByteArray()
		var hs := PackedFloat32Array()
		var ys := PackedFloat32Array()
		for k in n:
			pts.append(Vector2(data[i], data[i + 1]))
			fl.append(int(data[i + 2]) if kind == 4 else (1 if data[i + 2] > 0.5 else 0))
			fr.append(1 if data[i + 3] > 0.5 else 0)
			hs.append(data[i + 4])
			ys.append(NAN)
			i += 5
		var nrm := PackedVector2Array()
		var dist := PackedFloat32Array()
		var d := 0.0
		for k in n:
			var a := pts[maxi(k - 1, 0)]
			var b := pts[mini(k + 1, n - 1)]
			var t := (b - a).normalized()
			nrm.append(Vector2(t.y, -t.x))             # to the left of the direction of travel
			if k > 0:
				d += pts[k].distance_to(pts[k - 1])
			dist.append(d)
		var w := ways.size()
		ways.append([half, kind, mark, pts, nrm, fl, fr, dist, hs, ys])
		for k in n - 1:
			var mid := (pts[k] + pts[k + 1]) * 0.5
			var key := cell_of(mid.x, mid.y)
			if not road_cells.has(key):
				road_cells[key] = PackedInt32Array()
			road_cells[key].append(w)
			road_cells[key].append(k)


## The melted road and sidewalk surfaces, cut into triangles per cell by tools/build_map.py.
func _load_paved() -> void:
	var data := FileAccess.get_file_as_bytes("res://world/paved.bin").to_float32_array()
	var i := 0
	while i + 6 <= data.size():
		var key := Vector2i(int(data[i]), int(data[i + 1]))
		var na := int(data[i + 2]) * 6
		var ns := int(data[i + 3]) * 6
		var nk := int(data[i + 4]) * 4
		var ne := int(data[i + 5]) * 4
		i += 6
		paved[key] = [data.slice(i, i + na), data.slice(i + na, i + na + ns), data.slice(i + na + ns, i + na + ns + nk),
			data.slice(i + na + ns + nk, i + na + ns + nk + ne)]
		i += na + ns + nk + ne


# ------------------------------------------------------------------ streaming
func update(p: Vector3) -> void:
	if Vector2(p.x - _centre.x, p.z - _centre.z).length() < 12.0:
		return
	_centre = p
	var c := cell_of(p.x, p.z)
	var r := int(ceil(NEAR / CELL)) + 1
	_queue.clear()
	for dz in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var k := Vector2i(c.x + dx, c.y + dz)
			if _cells.has(k) or not (buildings.has(k) or road_cells.has(k) or paved.has(k) or world.props.cells.has(k)):
				continue
			var d := _dist(k, p)
			if d < NEAR:
				_queue.append([d, k])
	_queue.sort_custom(func(a, b): return a[0] < b[0])
	for k in _cells.keys():
		if _dist(k, p) > FAR:
			_drop(k)


func _dist(k: Vector2i, p: Vector3) -> float:
	return Vector2((float(k.x) + 0.5) * CELL - p.x, (float(k.y) + 0.5) * CELL - p.z).length()


func _drop(k: Vector2i) -> void:
	_cells[k].queue_free()
	_cells.erase(k)
	if far_meshes.has(k):
		far_meshes[k].visible = true


func _process(_delta: float) -> void:
	_work(BUDGET_USEC)


## Build everything in range right now (loading screen, screenshots).
func flush(p: Vector3) -> void:
	_centre = Vector3(1e9, 0, 1e9)
	update(p)
	_work(-1)


func _work(budget: int) -> void:
	var t0 := Time.get_ticks_usec()
	while true:
		if _job.is_empty():
			while not _queue.is_empty() and _cells.has(_queue[0][1]):
				_queue.pop_front()
			if _queue.is_empty():
				return
			_job_key = _queue.pop_front()[1]
			_job = {"mb": Facades.MB.new(), "roads": Facades.MB.new(), "cv": PackedVector3Array(), "b": 0, "r": 0, "p": 0, "part": 0}
		var recs: Array = buildings.get(_job_key, [])
		var segs: PackedInt32Array = road_cells.get(_job_key, PackedInt32Array())
		var pv: Array = paved.get(_job_key, [])
		while _job["part"] < pv.size():
			var arr: PackedFloat32Array = pv[_job["part"]]
			var stride := 6 if _job["part"] < 2 else 4
			var stop := mini(_job["p"] + stride * 40, arr.size())
			_paved_part(_job["roads"], _job["cv"], _job["part"], arr, _job["p"], stop)
			_job["p"] = stop
			if stop >= arr.size():
				_job["part"] += 1
				_job["p"] = 0
			if budget >= 0 and Time.get_ticks_usec() - t0 > budget:
				return
		while _job["r"] < segs.size():
			var stop := mini(_job["r"] + 24, segs.size())
			while _job["r"] < stop:
				_road_segment(_job["roads"], _job["cv"], ways[segs[_job["r"]]], segs[_job["r"] + 1])
				_job["r"] += 2
			if budget >= 0 and Time.get_ticks_usec() - t0 > budget:
				return
		while _job["b"] < recs.size():
			fac.build(_job["mb"], recs[_job["b"]])
			_job["b"] += 1
			if budget >= 0 and Time.get_ticks_usec() - t0 > budget:
				return
		_finish()
		if budget >= 0 and Time.get_ticks_usec() - t0 > budget:
			return


func _finish() -> void:
	var node := Node3D.new()
	var mb: Facades.MB = _job["mb"]
	if not mb.is_empty():
		var mi := MeshInstance3D.new()
		mi.mesh = fac.commit(mb)
		node.add_child(mi)
		if far_meshes.has(_job_key):
			far_meshes[_job_key].visible = false
	var rb: Facades.MB = _job["roads"]
	if not rb.is_empty():
		var ri := MeshInstance3D.new()
		ri.mesh = fac.commit(rb)
		ri.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(ri)
	var cv: PackedVector3Array = _job["cv"]
	if not cv.is_empty():
		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(cv)
		var col := CollisionShape3D.new()
		col.shape = shape
		var body := StaticBody3D.new()
		body.add_child(col)
		node.add_child(body)
	for rec in buildings.get(_job_key, []):
		if rec["name"] != "":
			_name_sign(node, rec)
	world.props.solid(node, _job_key)
	add_child(node)
	_cells[_job_key] = node
	_job = {}


## The name of a building, lettered on its two longest walls.
func _name_sign(node: Node3D, rec: Dictionary) -> void:
	var walls: Array = rec["rf"]["w"].duplicate()
	walls.sort_custom(func(a, b): return Vector2(a[2] - a[0], a[3] - a[1]).length() > Vector2(b[2] - b[0], b[3] - b[1]).length())
	var text: String = rec["name"].to_upper()
	for k in mini(2, walls.size()):
		var w: Array = walls[k]
		var a := Vector2(w[0], w[1])
		var b := Vector2(w[2], w[3])
		var length := a.distance_to(b)
		if length < 3.0:
			continue
		var t := (b - a) / length
		var out := Vector3(t.y, 0.0, -t.x)
		var top := INF
		var i := 7
		while i + 6 < w.size():
			top = minf(top, minf(w[i + 1], w[i + 3]))
			i += 7
		var ground := maxf(w[4], w[5])
		var y := minf(ground + 3.3, top - 0.5)
		if y < ground + 1.6:
			continue
		var label := Label3D.new()
		label.text = text
		label.font_size = 64
		label.pixel_size = minf(0.009, 0.85 * length / (float(text.length()) * 40.0))
		var wc: Color = rec["wall"]
		var dark_wall := wc.r * 0.3 + wc.g * 0.6 + wc.b * 0.1 < 0.45
		label.modulate = Color(0.93, 0.93, 0.90) if dark_wall else Color(0.08, 0.08, 0.09)
		label.outline_modulate = Color(0.06, 0.06, 0.07) if dark_wall else Color(0.9, 0.9, 0.88)
		label.outline_size = 6
		var mid := (a + b) * 0.5
		label.transform = Transform3D(Basis(Vector3.UP.cross(out), Vector3.UP, out), Vector3(mid.x, y, mid.y) + out * 0.12)
		node.add_child(label)


# ------------------------------------------------------------------ roads
## A point on a road surface. The height depends only on where the point is — never on which road
## it belongs to — so two roads that meet or overlap are at the same level and leave no step.
## The 1 m ground is already pressed level under every road (tools/build_map.py); the surface lies
## just above the highest of it within a step.
func _g(p: Vector2, lift: float) -> Vector3:
	var y: float = world.height_at(p.x, p.y)
	for o in [Vector2(0.8, 0.0), Vector2(-0.8, 0.0), Vector2(0.0, 0.8), Vector2(0.0, -0.8)]:
		y = maxf(y, world.height_at(p.x + o.x, p.y + o.y))
	return Vector3(p.x, y + lift, p.y)


func _quad_cv(cv: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	cv.append(a); cv.append(b); cv.append(c)
	cv.append(a); cv.append(c); cv.append(d)


## Drawn and solid.
func _solid(mb, cv: PackedVector3Array, m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
	mb.quad(m, a, b, c, d, nrm, col)
	_quad_cv(cv, a, b, c, d)


## Lay a run of the paved triangles or edge pieces of a cell on the ground.
## part 0: asphalt, 1: sidewalk (raised a kerb's height), 2: the edge of a sidewalk, 3: the edge of a road.
func _paved_part(mb, cv: PackedVector3Array, part: int, arr: PackedFloat32Array, from: int, to: int) -> void:
	var up := Vector3.UP
	var i := from
	if part < 2:
		var lift := 0.10 if part == 0 else 0.23
		var m := "asphalt" if part == 0 else "sidewalk"
		var col := ASPHALT if part == 0 else SIDEWALK
		while i < to:
			var a := _g(Vector2(arr[i], arr[i + 1]), lift)
			var b := _g(Vector2(arr[i + 2], arr[i + 3]), lift)
			var c := _g(Vector2(arr[i + 4], arr[i + 5]), lift)
			i += 6
			if minf(a.y, minf(b.y, c.y)) < 0.45:
				continue                                       # out in the water
			mb.tri(m, a, b, c, up, col)
			cv.append(a); cv.append(b); cv.append(c)
		return
	while i < to:
		var p0 := Vector2(arr[i], arr[i + 1])
		var p1 := Vector2(arr[i + 2], arr[i + 3])
		i += 4
		var t := (p1 - p0).normalized()
		var out := Vector3(t.y, 0, -t.x)                       # the open side
		if part == 2:
			# kerb and back edge of a sidewalk: drawn upright, solid as a short ramp
			var a := _g(p0, 0.23)
			var b := _g(p1, 0.23)
			if minf(a.y, b.y) < 0.6:
				continue
			var dn := Vector3(0, 0.9, 0)
			mb.quad("trim", a, b, b - dn, a - dn, out, KERB)
			_quad_cv(cv, a, b, b + out * 1.2 - Vector3(0, 0.3, 0), a + out * 1.2 - Vector3(0, 0.3, 0))      # a long, gentle ramp to drive over: no jolt
		else:
			# the edge of the asphalt falling away into the ground: a gentle ramp, so wheels roll up onto the road
			var a := _g(p0, 0.10)
			var b := _g(p1, 0.10)
			if minf(a.y, b.y) < 0.5:
				continue
			var dn := out * 1.6 - Vector3(0, 0.7, 0)
			_solid(mb, cv, "asphalt", a, b, b + dn, a + dn, (up + out * 0.45).normalized(), SHOULDER)


const DECK := Color(0.47, 0.47, 0.48)
const RAIL := Color(0.30, 0.32, 0.34)


func _road_segment(mb, cv: PackedVector3Array, way: Array, i: int) -> void:
	var half: float = way[0]
	var kind: int = way[1]
	var mark: int = way[2]
	var pts: PackedVector2Array = way[3]
	var nrm: PackedVector2Array = way[4]
	var p0 := pts[i]
	var p1 := pts[i + 1]
	var n0 := nrm[i]
	var n1 := nrm[i + 1]
	var up := Vector3.UP
	var out0 := Vector3(n0.x, 0, n0.y)
	var out1 := Vector3(n1.x, 0, n1.y)
	var dist: PackedFloat32Array = way[7]
	if kind == 2:
		# zebra crossing: bars along the direction of traffic, one every metre of the walk across
		var length := p0.distance_to(p1)
		if length < 0.01:
			return
		var t := (p1 - p0) / length
		var s := ceilf(dist[i]) - dist[i]
		while s < length:
			var c := p0 + t * s
			var c2 := p0 + t * minf(s + 0.5, length)
			# each bar in two halves, so it lies on the crown of the road
			mb.quad_auto("mark", _g(c + n0 * half, 0.15), _g(c, 0.15), _g(c2, 0.15), _g(c2 + n0 * half, 0.15), up, WHITE)
			mb.quad_auto("mark", _g(c, 0.15), _g(c - n0 * half, 0.15), _g(c2 - n0 * half, 0.15), _g(c2, 0.15), up, WHITE)
			s += 1.0
		return
	if kind == 1:
		return                                                 # sidewalks are part of the paved surfaces now
	if kind == 4:
		_bridge_segment(mb, cv, way, i)
		return
	if kind == 6:
		# give-way line: a row of white triangles across the lane, pointing at the traffic that must wait
		var across := p1 - p0
		var width := across.length()
		if width < 0.6:
			return
		var t := across / width
		var back := Vector2(-t.y, t.x)                             # toward the traffic coming up to the line
		var count := maxi(1, int(width / 0.6))
		var step := width / float(count)
		for k in count:
			var base := p0 + t * (step * (float(k) + 0.5))
			mb.tri("mark", _g(base - t * 0.25, 0.15), _g(base + t * 0.25, 0.15), _g(base + back * 0.6, 0.15), up, WHITE)
		return
	if kind == 5:
		# runway paint: a centre line of long dashes, edge lines, and bars across at both ends
		var n := pts.size()
		var c0r := _g(p0, 0.03)
		var c1r := _g(p1, 0.03)
		if i % 5 < 3:
			mb.quad_auto("mark", c0r + out0 * 0.45, c0r - out0 * 0.45, c1r - out1 * 0.45, c1r + out1 * 0.45, up, WHITE)
		for sgn in [1.0, -1.0]:
			var sd: float = sgn
			var e0 := _g(p0 + n0 * (sd * 21.0), 0.03)
			var e1 := _g(p1 + n1 * (sd * 21.0), 0.03)
			mb.quad_auto("mark", e0 - out0 * 0.45, e0 + out0 * 0.45, e1 + out1 * 0.45, e1 - out1 * 0.45, up, WHITE)
		if (i >= 3 and i < 6) or (i >= n - 7 and i < n - 4):
			for bar in range(-5, 6):
				if bar == 0:
					continue
				var off := float(bar) * 3.4
				mb.quad_auto("mark", _g(p0 + n0 * (off - 0.9), 0.03), _g(p0 + n0 * (off + 0.9), 0.03), _g(p1 + n1 * (off + 0.9), 0.03), _g(p1 + n1 * (off - 0.9), 0.03), up, WHITE)
		return
	var hair := Vector3(0, 0.015, 0)
	if kind == 0:
		# the surface comes from the paved triangles; here only the paint, and none of it across a junction
		var ok: PackedByteArray = way[5]
		if ok[i] == 0 or ok[i + 1] == 0:
			return
		if (mark == 1 or mark == 2) and int(dist[i] / 3.0) % 4 == 0:
			var c0 := _g(p0, 0.10) + hair
			var c1 := _g(p1, 0.10) + hair
			mb.quad("mark", c0 + out0 * 0.06, c0 - out0 * 0.06, c1 - out1 * 0.06, c1 + out1 * 0.06, up, YELLOW)
		if mark >= 2:
			for sgn in [1.0, -1.0]:
				var sd: float = sgn
				var e0 := _g(p0 + n0 * (sd * (half - 0.25)), 0.10) + hair
				var e1 := _g(p1 + n1 * (sd * (half - 0.25)), 0.10) + hair
				mb.quad("mark", e0 - out0 * 0.05, e0 + out0 * 0.05, e1 + out1 * 0.05, e1 - out1 * 0.05, up, WHITE)
		return
	if kind == 8:
		_steps_segment(mb, cv, half, p0, p1, n0)
		return
	# a foot or cycle path: a ribbon of its own, standing a little proud of the ground, with soft edges.
	# Paved ones are asphalt; walks are light gravel; trails are trodden earth.
	var m := "asphalt"
	var col := PATH
	var edge := SHOULDER
	var lift := 0.09
	if kind == 7:
		m = "path"
		lift = 0.07
		col = Color(0.56, 0.48, 0.38) if mark == 1 else Color(0.93, 0.88, 0.78)
		edge = col.darkened(0.45)
	var a0 := _g(p0 + n0 * half, lift)
	var c0p := _g(p0, lift + 0.03)
	var b0 := _g(p0 - n0 * half, lift)
	var a1 := _g(p1 + n1 * half, lift)
	var c1p := _g(p1, lift + 0.03)
	var b1 := _g(p1 - n1 * half, lift)
	_solid(mb, cv, m, a0, c0p, c1p, a1, up, col)
	_solid(mb, cv, m, c0p, b0, b1, c1p, up, col)
	for sgn in [1.0, -1.0]:
		var sd: float = sgn
		var e0 := a0 if sd > 0.0 else b0
		var e1 := a1 if sd > 0.0 else b1
		var o0 := out0 * sd
		var o1 := out1 * sd
		var w := 0.7 if kind == 7 else 1.2
		_solid(mb, cv, m, e0, e1, e1 + o1 * w - Vector3(0, 0.4, 0), e0 + o0 * w - Vector3(0, 0.4, 0), (up + o0 * 0.4).normalized(), edge)


## A stretch of a flight of steps: level stone treads with risers between them, a stone cheek along
## each side. It is solid as a plain ramp, so feet and wheels go up it smoothly.
func _steps_segment(mb, cv: PackedVector3Array, half: float, p0: Vector2, p1: Vector2, n0: Vector2) -> void:
	var stone := Color(0.60, 0.59, 0.57)
	var length := p0.distance_to(p1)
	if length < 0.1:
		return
	var y0: float = world.height_at(p0.x, p0.y) + 0.06
	var y1: float = world.height_at(p1.x, p1.y) + 0.06
	var side := Vector3(n0.x, 0, n0.y) * half
	var a := Vector3(p0.x, y0, p0.y)
	var b := Vector3(p1.x, y1, p1.y)
	_quad_cv(cv, a + side, a - side, b - side, b + side)
	var count := maxi(1, int(round(maxf(absf(y1 - y0) / 0.17, length / 0.9))))
	var out := Vector3(n0.x, 0, n0.y)
	var run := (b - a) / float(count)
	run.y = 0.0
	var rise := (y1 - y0) / float(count)
	var dir := run.normalized()
	for k in count:
		var lo := a + run * float(k) + Vector3(0, rise * float(k), 0)
		var top := maxf(lo.y, lo.y + rise)                              # the tread is level, at the higher end of its step
		var s0 := Vector3(lo.x, top, lo.z)
		var s1 := s0 + run
		mb.quad("sidewalk", s0 + side, s0 - side, s1 - side, s1 + side, Vector3.UP, stone)
		var foot := s0 if rise > 0.0 else s1                            # the riser stands at the low end
		mb.quad("trim", foot + side, foot - side, foot - side - Vector3(0, absf(rise) + 0.02, 0), foot + side - Vector3(0, absf(rise) + 0.02, 0),
			-dir if rise > 0.0 else dir, stone.darkened(0.25))
		for sgn in [1.0, -1.0]:
			var sd: float = sgn
			var e0 := s0 + side * sd
			var e1 := s1 + side * sd
			mb.quad("trim", e0, e1, e1 - Vector3(0, absf(rise) + 0.5, 0), e0 - Vector3(0, absf(rise) + 0.5, 0), out * sd, stone.darkened(0.15))


const TIMBER := Color(0.40, 0.29, 0.20)
const CONCRETE := Color(0.56, 0.56, 0.55)


## One stretch of a bridge. A road bridge is a concrete deck on two girders, with an edge beam and a
## steel railing; a footbridge is planked timber with a timber railing. Both stand on abutments at
## their ends and on piers with a cap where they are high above the ground. The railing is solid.
func _bridge_segment(mb, cv: PackedVector3Array, way: Array, i: int) -> void:
	var half: float = way[0]
	var mark: int = way[2]
	var pts: PackedVector2Array = way[3]
	var nrm: PackedVector2Array = way[4]
	var hs: PackedFloat32Array = way[8]
	var dist: PackedFloat32Array = way[7]
	var open: PackedByteArray = way[5]
	var n := pts.size()
	var up := Vector3.UP
	var o0 := Vector3(nrm[i].x, 0, nrm[i].y)
	var o1 := Vector3(nrm[i + 1].x, 0, nrm[i + 1].y)
	var c0 := Vector3(pts[i].x, hs[i] + 0.06, pts[i].y)             # level with the road it carries: no step on or off
	var c1 := Vector3(pts[i + 1].x, hs[i + 1] + 0.06, pts[i + 1].y)
	var parapet := mark >= 16                                          # a town bridge: concrete parapets, not steel rails
	mark = mark % 16
	var road := half > 2.0
	var conc := mark == 9                                              # a footbridge of concrete, with concrete parapets
	var thick := Vector3(0, 0.35 if road else (0.28 if conc else 0.18), 0)
	var body := CONCRETE if road or conc else TIMBER
	var a0 := c0 + o0 * half
	var b0 := c0 - o0 * half
	var a1 := c1 + o1 * half
	var b1 := c1 - o1 * half
	_solid(mb, cv, "asphalt" if road else ("trim" if conc else "clad"), a0, b0, b1, a1, up, ASPHALT if road else (CONCRETE.lightened(0.08) if conc else TIMBER))
	mb.quad("trim", a0 - thick, b0 - thick, b1 - thick, a1 - thick, Vector3.DOWN, body)
	if road and (mark == 1 or mark == 2) and int(dist[i] / 3.0) % 4 == 0:
		var hair := Vector3(0, 0.015, 0)
		mb.quad("mark", c0 + hair + o0 * 0.06, c0 + hair - o0 * 0.06, c1 + hair - o1 * 0.06, c1 + hair + o1 * 0.06, up, YELLOW)
	var along := (c1 - c0).normalized()
	# two girders under the deck
	var deep := Vector3(0, 0.9 if road else 0.35, 0)
	for sgn in [1.0, -1.0]:
		var sd: float = sgn
		var g0 := c0 + o0 * (half * 0.55 * sd) - thick
		var g1 := c1 + o1 * (half * 0.55 * sd) - thick
		var w0 := o0 * 0.22
		var w1 := o1 * 0.22
		mb.quad("trim", g0 + w0, g1 + w1, g1 + w1 - deep, g0 + w0 - deep, o0, body.darkened(0.12))
		mb.quad("trim", g0 - w0, g1 - w1, g1 - w1 - deep, g0 - w0 - deep, -o0, body.darkened(0.12))
		mb.quad("trim", g0 + w0 - deep, g1 + w1 - deep, g1 - w1 - deep, g0 - w0 - deep, Vector3.DOWN, body.darkened(0.2))
	for sgn in [1.0, -1.0]:
		var sd: float = sgn
		var e0 := c0 + o0 * (half * sd)
		var e1 := c1 + o1 * (half * sd)
		var out := o0 * sd
		mb.quad("trim", e0, e1, e1 - thick, e0 - thick, out, body)
		var bit := 1 if sd > 0.0 else 2
		if (open[i] & bit) != 0 and (open[i + 1] & bit) != 0:
			continue                                           # another deck lies against this side: no railing between
		var inset0 := e0 - o0 * (sd * 0.12)
		var inset1 := e1 - o1 * (sd * 0.12)
		var h := Vector3(0, 1.1, 0)
		if road and parapet:
			# a solid concrete parapet with a coping, on the edge of the deck
			var q0 := e0 - o0 * (sd * 0.14)
			var q1 := e1 - o1 * (sd * 0.14)
			mb.box("trim", (q0 + q1) * 0.5 + Vector3(0, 0.48, 0), along, Vector3.UP, out, Vector3(q0.distance_to(q1) * 0.5, 0.48, 0.12), CONCRETE)
			mb.box("trim", (q0 + q1) * 0.5 + Vector3(0, 0.99, 0), along, Vector3.UP, out, Vector3(q0.distance_to(q1) * 0.5, 0.04, 0.15), CONCRETE.darkened(0.08))
		elif road:
			# edge beam, then posts with three rails
			var kb := Vector3(0, 0.22, 0)
			var in0 := e0 - o0 * (sd * 0.3)
			var in1 := e1 - o1 * (sd * 0.3)
			mb.quad("trim", e0, e1, e1 + kb, e0 + kb, out, CONCRETE)
			mb.quad("trim", e0 + kb, e1 + kb, in1 + kb, in0 + kb, up, CONCRETE)
			mb.quad("trim", in0, in1, in1 + kb, in0 + kb, -out, CONCRETE)
			for f in [0.0, 0.5]:
				var fp: float = f
				mb.box("trim", inset0.lerp(inset1, fp) + h * 0.5 + kb * 0.5, along, Vector3.UP, out, Vector3(0.04, 0.5, 0.04), RAIL)
			for rail in [1.08, 0.75, 0.45]:
				var ry: float = rail
				var r0 := inset0 + Vector3(0, ry, 0)
				var r1 := inset1 + Vector3(0, ry, 0)
				mb.box("trim", (r0 + r1) * 0.5, along, Vector3.UP, out, Vector3(r0.distance_to(r1) * 0.5, 0.03, 0.025), RAIL)
		elif conc:
			# a solid concrete parapet with a coping on top
			var p0 := e0 - o0 * (sd * 0.10)
			var p1 := e1 - o1 * (sd * 0.10)
			mb.box("trim", (p0 + p1) * 0.5 + Vector3(0, 0.46, 0), along, Vector3.UP, out, Vector3(p0.distance_to(p1) * 0.5, 0.46, 0.09), CONCRETE)
			mb.box("trim", (p0 + p1) * 0.5 + Vector3(0, 0.95, 0), along, Vector3.UP, out, Vector3(p0.distance_to(p1) * 0.5, 0.035, 0.12), CONCRETE.darkened(0.08))
		else:
			# timber posts, a hand rail and two boards
			for f in [0.0, 0.5]:
				var fp: float = f
				mb.box("clad", inset0.lerp(inset1, fp) + h * 0.5, along, Vector3.UP, out, Vector3(0.06, 0.55, 0.06), TIMBER)
			for rail in [1.06, 0.62, 0.25]:
				var ry: float = rail
				var r0 := inset0 + Vector3(0, ry, 0)
				var r1 := inset1 + Vector3(0, ry, 0)
				mb.box("clad", (r0 + r1) * 0.5, along, Vector3.UP, out, Vector3(r0.distance_to(r1) * 0.5, 0.06 if ry > 1.0 else 0.05, 0.03), TIMBER)
		_quad_cv(cv, inset0, inset1, inset1 + h, inset0 + h)
	# abutments: a wall under each end, wider than the deck, down into the ground
	for end in [0, n - 2]:
		if i != end:
			continue
		var at := c0 if end == 0 else c1
		var oo := o0 if end == 0 else o1
		var ground: float = world.height_at(at.x, at.z)
		var foot := minf(ground, at.y - 1.2) - 1.5
		var top_y := at.y - thick.y
		mb.box("plaster", Vector3(at.x, (top_y + foot) * 0.5, at.z), oo, Vector3.UP, along, Vector3(half + 0.6, (top_y - foot) * 0.5, 0.6), CONCRETE)
	# piers with a cap, where the deck is high above the ground
	var every := 4 if road else 3
	if i % every == every - 2 and i > 0 and i < n - 2:
		var ground2: float = world.height_at(pts[i].x, pts[i].y)
		var under := c0.y - thick.y - deep.y
		if under - ground2 > 1.6:
			var bottom := maxf(ground2, -3.0) - 0.6
			mb.box("plaster", Vector3(c0.x, under - 0.2, c0.z), o0, Vector3.UP, along, Vector3(half * 0.85, 0.2, 0.55), CONCRETE)
			mb.box("plaster", Vector3(c0.x, (under - 0.4 + bottom) * 0.5, c0.z), o0, Vector3.UP, along,
				Vector3(minf(half * 0.45, 1.6), (under - 0.4 - bottom) * 0.5, 0.35), CONCRETE if road else TIMBER)
