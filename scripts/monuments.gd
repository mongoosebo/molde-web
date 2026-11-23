extends "res://scripts/landmarks.gd"
## Molde's skyline, modelled by hand on top of the Rådhusplassen buildings:
## the cathedral and its free-standing bell tower, Scandic Seilet, Aker Stadion, and the piers.
## Sizes and heights are taken from the map footprints and Kartverket's laser data; the facades
## are a plausible reconstruction.

const SEILET_BASE := {
	"floors": 4, "g_h": 4.2, "f_h": 3.3, "bay": 3.6, "margin": 0.6,
	"g_open": [3.0, 3.0, 0.3], "u_open": [3.0, 1.9, 0.8],
	"wall": "plaster_white", "plinth": "concrete_dark", "glass": "glass_blue", "frame": "dark",
	"top": 0.9, "roof": "flat"}


func build_all(w, meta: Dictionary) -> void:
	build(w, meta.get("landmarks", []), meta.get("plaza", []))
	_mats["copper"] = _plain(Color(0.30, 0.50, 0.43), 0.55, 0.35)
	# the cathedral's roof is red tile (photos, 19 Nov), not copper: the same red as before, now with the tiles' own
	# courses and shadows in it; and its spire copper sheet gone nearly black, with its standing seams (note of 20 Nov)
	_mats["church_tile"] = _textured("rooftile", Color(0.74, 0.31, 0.19) / 0.75, 1.6, 0.85)
	_mats["spire"] = _textured("seam", Color(0.19, 0.25, 0.23) / 0.79, 2.4, 0.55)
	_mats["spire"].metallic = 0.3
	_mats["glass_blue"] = _plain(Color(0.09, 0.15, 0.20), 0.07, 0.9)
	_mats["sail_glass"] = _plain(Color(0.30, 0.45, 0.57), 0.08, 0.85)      # Seilet is glass from top to bottom, sky-blue in daylight (photos, 19 Nov)
	_mats["sail_line"] = _plain(Color(0.55, 0.62, 0.68), 0.35, 0.6)
	_mats["steel"] = _plain(Color(0.62, 0.64, 0.66), 0.45, 0.6)
	_mats["seat_blue"] = _plain(Color(0.07, 0.20, 0.50), 0.8)
	_mats["pitch"] = _plain(Color(0.13, 0.33, 0.12), 1.0)
	_mats["line"] = _plain(Color(0.90, 0.90, 0.88), 0.9)
	_mats["granite"] = _textured("plaster", Color(0.80, 0.80, 0.78), 2.0, 0.8)
	_mats["granite_light"] = _textured("plaster", Color(0.90, 0.90, 0.88), 2.0, 0.8)
	_mats["roof_dark"] = _plain(Color(0.40, 0.42, 0.45), 0.5, 0.5)      # (the stadium roof is grey zinc, not black: photos, 19 Nov)
	for lm in meta.get("landmarks", []):
		var flat: Array = lm["pts"]
		var poly := PackedVector2Array()
		for i in flat.size() / 2:
			poly.append(Vector2(flat[2 * i], flat[2 * i + 1]))
		match lm["key"]:
			"domkirke":
				_build_domkirke(lm["ymin"], lm["ymax"])
			"klokketarn":
				_build_bell_tower(poly, lm["ymin"])
			"seilet":
				_build_seilet(poly, lm["ymin"], lm["ymax"])
	var st: Dictionary = meta.get("stadium", {})
	if st.has("outline") and st.has("pitch"):
		_build_stadium(st)
	_build_piers(meta.get("piers", []))
	_mats["track"] = _plain(Color(0.56, 0.22, 0.16), 0.95)
	_mats["fuel_red"] = _plain(Color(0.78, 0.10, 0.08), 0.5)
	_mats["fuel_yellow"] = _plain(Color(0.95, 0.78, 0.10), 0.5)
	_build_quays(meta.get("quays", []))
	_build_sports(meta.get("sports", {}))
	for f in meta.get("fields", []):
		_build_sports(f)
	_mats["green"] = _plain(Color(0.22, 0.46, 0.18), 1.0)
	_mats["sand"] = _plain(Color(0.80, 0.73, 0.54), 1.0)
	_build_golf(meta.get("golf", []))
	_mats["net"] = _plain(Color(0.9, 0.9, 0.88, 0.45), 0.9)
	_mats["net"].transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats["net"].cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats["tape"] = _plain(Color(0.10, 0.25, 0.70), 0.8)
	_build_courts(meta.get("courts", []))
	_build_fountains(meta.get("fountains", []))
	_build_door_signs(meta.get("door_signs", []))
	_build_statues(meta.get("statues", []), meta.get("sandpits", []))
	_build_canopies(meta.get("canopies", []))
	_build_skywalks(meta.get("skywalks", []))
	_build_portals(meta.get("portals", []))


# ------------------------------------------------------------------ helpers
func _v3(p: Vector2, y: float) -> Vector3:
	return Vector3(p.x, y, p.y)


func _face(a: Vector2, b: Vector2, outward: Vector2) -> Face:
	var f := Face.new()
	var d := b - a
	f.length = d.length()
	var t2 := d / f.length
	var n2 := Vector2(t2.y, -t2.x)
	if n2.dot(outward) < 0.0:
		n2 = -n2
	f.a = Vector3(a.x, 0.0, a.y)
	f.t = Vector3(t2.x, 0.0, t2.y)
	f.n = Vector3(n2.x, 0.0, n2.y)
	return f


## Quad whose normal is worked out from its corners; `hint` says which side is the outside.
func _quad_auto(mb: MB, m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3) -> void:
	var nrm := (b - a).cross(d - a)
	if nrm.length() < 1e-6:                    # two corners coincide (a fan around a corner)
		nrm = (c - a).cross(d - a)
	if nrm.length() < 1e-6:
		nrm = (b - a).cross(c - a)
	if nrm.length() < 1e-6:
		return
	nrm = nrm.normalized()
	if nrm.dot(hint) < 0.0:
		nrm = -nrm
	mb.quad(m, a, b, c, d, nrm)


## A wall with tall, narrow, recessed windows (bay <= 0: a plain wall).
func _slit_wall(mb: MB, f: Face, ybase: float, ytop: float, wall: String, glass: String, bay: float, ww: float, wy0: float, wy1: float) -> void:
	var n := int(f.length / bay) if bay > 0.0 else 0
	if n == 0:
		mb.quad(wall, f.p(0, ybase), f.p(f.length, ybase), f.p(f.length, ytop), f.p(0, ytop), f.n)
		return
	mb.quad(wall, f.p(0, ybase), f.p(f.length, ybase), f.p(f.length, wy0), f.p(0, wy0), f.n)
	mb.quad(wall, f.p(0, wy1), f.p(f.length, wy1), f.p(f.length, ytop), f.p(0, ytop), f.n)
	var bw := f.length / float(n)
	var prev := 0.0
	var d := 0.35
	for i in n:
		var s0 := (float(i) + 0.5) * bw - ww * 0.5
		var s1 := s0 + ww
		mb.quad(wall, f.p(prev, wy0), f.p(s0, wy0), f.p(s0, wy1), f.p(prev, wy1), f.n)
		mb.quad(wall, f.p(s0, wy0), f.p(s0, wy1), f.p(s0, wy1, d), f.p(s0, wy0, d), f.t)
		mb.quad(wall, f.p(s1, wy0), f.p(s1, wy1), f.p(s1, wy1, d), f.p(s1, wy0, d), -f.t)
		mb.quad(wall, f.p(s0, wy1), f.p(s1, wy1), f.p(s1, wy1, d), f.p(s0, wy1, d), Vector3.DOWN)
		mb.quad(wall, f.p(s0, wy0), f.p(s1, wy0), f.p(s1, wy0, d), f.p(s0, wy0, d), Vector3.UP)
		mb.quad(glass, f.p(s0, wy0, d), f.p(s1, wy0, d), f.p(s1, wy1, d), f.p(s0, wy1, d), f.n)
		prev = s1
	mb.quad(wall, f.p(prev, wy0), f.p(f.length, wy0), f.p(f.length, wy1), f.p(prev, wy1), f.n)


## A hall with a pitched roof on a rectangle: centre c, ridge along u, half-length hl, half-width hw.
## `win` = [bay, width, y0, y1] above the floor level yfloor, for the long walls.
func _gable_hall(mb: MB, c: Vector2, u: Vector2, hl: float, hw: float, ybase: float, yfloor: float, eave: float, ridge: float, wall: String, roof: String, win: Array) -> void:
	var v := Vector2(-u.y, u.x)
	var ye := yfloor + eave
	var yr := yfloor + ridge
	for side in [-1.0, 1.0]:
		var sd: float = side
		var f := _face(c - u * hl + v * hw * sd, c + u * hl + v * hw * sd, v * sd)
		_slit_wall(mb, f, ybase, ye, wall, "glass", win[0], win[1], yfloor + win[2], yfloor + win[3])
		# gable end
		var g := _face(c + u * hl * sd - v * hw, c + u * hl * sd + v * hw, u * sd)
		mb.quad(wall, g.p(0, ybase), g.p(g.length, ybase), g.p(g.length, ye), g.p(0, ye), g.n)
		mb.tri(wall, g.p(0, ye), g.p(g.length, ye), g.p(hw, yr), g.n)
		# roof slope with a small overhang
		var o := 0.45
		var drop := o * (ridge - eave) / hw
		var e0 := _v3(c - u * (hl + o) + v * (hw + o) * sd, ye - drop)
		var e1 := _v3(c + u * (hl + o) + v * (hw + o) * sd, ye - drop)
		var r0 := _v3(c - u * (hl + o), yr)
		var r1 := _v3(c + u * (hl + o), yr)
		_quad_auto(mb, roof, e0, e1, r1, r0, Vector3.UP)
		_quad_auto(mb, "white", e0, e1, r1 - Vector3(0, 0.12, 0), r0 - Vector3(0, 0.12, 0), Vector3.DOWN)


func _box_body(c: Vector3, u: Vector2, size: Vector3) -> void:
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	var ux := Vector3(u.x, 0, u.y)
	col.transform = Transform3D(Basis(ux, Vector3.UP, ux.cross(Vector3.UP)), c)
	var body := StaticBody3D.new()
	body.add_child(col)
	add_child(body)


func _mesh_body(cv: PackedVector3Array) -> void:
	if cv.is_empty():
		return
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(cv)
	var col := CollisionShape3D.new()
	col.shape = shape
	var body := StaticBody3D.new()
	body.add_child(col)
	add_child(body)


func _cq(cv: PackedVector3Array, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	cv.append(a); cv.append(b); cv.append(c)
	cv.append(a); cv.append(c); cv.append(d)


# ------------------------------------------------------------------ Molde domkirke
## Finn Bryn's cathedral (1957): a long white basilica under a steep copper roof, a low aisle
## along the north side, a round apse to the east and a parish wing behind it.
func _build_domkirke(ymin: float, ymax: float) -> void:
	var mb := MB.new()
	var u := Vector2(0.9774, -0.2114)          # the ridge, west to east
	var v := Vector2(-u.y, u.x)                # toward the south, the square side
	var c := Vector2(59.8, -84.5)
	var hl := 27.0
	var hw := 6.85
	var yf: float = world.height_at(c.x, c.y) + 0.4      # floor level; the ground falls away to the south
	var yb := ymin - 1.5
	var eave := 14.0
	var ridge := 27.0
	_gable_hall(mb, c, u, hl, hw, yb, yf, eave, ridge, "plaster_white", "church_tile", [5.4, 1.5, 3.0, 12.4])

	# west front: the main door under a tall window
	var wf := _face(c - u * hl - v * hw, c - u * hl + v * hw, -u)
	mb.box("door", wf.p(hw, yf + 2.0, -0.06), wf.t, Vector3.UP, wf.n, Vector3(1.6, 2.0, 0.08))
	# (a round window high in the gable, not a tall one: photos, 19 Nov)
	mb.box("white", wf.p(hw, yf + 15.0, -0.05), wf.t, Vector3.UP, wf.n, Vector3(1.75, 1.75, 0.05))
	mb.box("glass", wf.p(hw, yf + 15.0, -0.08), (wf.t + Vector3.UP).normalized(), (Vector3.UP - wf.t).normalized(), wf.n, Vector3(1.05, 1.05, 0.06))
	mb.box("glass", wf.p(hw, yf + 15.0, -0.08), wf.t, Vector3.UP, wf.n, Vector3(1.05, 1.05, 0.06))
	mb.box("white", wf.p(hw, yf + 4.25, -0.5), wf.t, Vector3.UP, wf.n, Vector3(2.6, 0.12, 0.6))

	# north aisle: the roof carries on down over it
	var a0 := -16.8
	var a1 := 19.2
	var aw := 4.2
	var ay := eave - aw * (ridge - eave) / hw
	var af := _face(c + u * a0 - v * (hw + aw), c + u * a1 - v * (hw + aw), -v)
	_slit_wall(mb, af, yb, yf + ay, "plaster_white", "glass", 3.0, 1.0, yf + 1.4, yf + ay - 0.6)
	_quad_auto(mb, "church_tile", af.p(-0.3, yf + ay - 0.2, -0.3), af.p(af.length + 0.3, yf + ay - 0.2, -0.3),
		_v3(c + u * (a1 + 0.3) - v * hw, yf + eave), _v3(c + u * (a0 - 0.3) - v * hw, yf + eave), Vector3.UP)
	for s in [a0, a1]:
		var e := _face(c + u * s - v * hw, c + u * s - v * (hw + aw), u * (1.0 if s == a1 else -1.0))
		mb.quad("plaster_white", e.p(0, yb), e.p(aw, yb), e.p(aw, yf + ay), e.p(0, yf + ay), e.n)
		mb.tri("plaster_white", e.p(0, yf + ay), e.p(aw, yf + ay), e.p(0, yf + eave), e.n)

	# apse
	var ac := c + u * (hl + 2.4)
	var ar := 6.4
	var segs := 20
	for i in segs:
		var t0 := TAU * float(i) / segs
		var t1 := TAU * float(i + 1) / segs
		var p0 := ac + Vector2(cos(t0), sin(t0)) * ar
		var p1 := ac + Vector2(cos(t1), sin(t1)) * ar
		var nm := Vector3(cos((t0 + t1) * 0.5), 0, sin((t0 + t1) * 0.5))
		mb.quad("plaster_white", _v3(p0, yb), _v3(p1, yb), _v3(p1, yf + 13.0), _v3(p0, yf + 13.0), nm)
		mb.tri("church_tile", _v3(p0, yf + 13.0), _v3(p1, yf + 13.0), _v3(ac, yf + 16.4), (nm * 0.4 + Vector3.UP).normalized())

	# parish wing and the passage to it
	var pc := c + u * 20.3 - v * 18.4
	var pf: float = maxf(yf, world.height_at(pc.x, pc.y) + 0.3)             # these stand on higher ground than the nave
	mb.box("plaster_white", _v3(pc, (yb + pf + 5.4) * 0.5), Vector3(u.x, 0, u.y), Vector3.UP, Vector3(v.x, 0, v.y), Vector3(5.5, (pf + 5.4 - yb) * 0.5, 5.6))
	var wu := Vector2(0.966, 0.259)
	var wc := Vector2(77.6, -115.6)
	var wf2: float = maxf(yf, world.height_at(wc.x, wc.y) + 0.3)
	_gable_hall(mb, wc, wu, 9.6, 4.2, yb, wf2, 6.4, 10.8, "plaster_white", "church_tile", [3.2, 1.1, 1.2, 5.0])
	_commit(mb, "Domkirke")

	_box_body(_v3(c, (yb + yf + eave + 5.0) * 0.5), u, Vector3(hl * 2.0, yf + eave + 5.0 - yb, hw * 2.0))
	_box_body(_v3(c + u * (a0 + a1) * 0.5 - v * (hw + aw * 0.5), (yb + yf + ay) * 0.5), u, Vector3(a1 - a0, yf + ay - yb, aw))
	_box_body(_v3(pc, (yb + pf + 5.4) * 0.5), u, Vector3(11.0, pf + 5.4 - yb, 11.2))
	_box_body(_v3(wc, (yb + wf2 + 8.0) * 0.5), wu, Vector3(19.2, wf2 + 8.0 - yb, 8.4))
	var cyl := CylinderShape3D.new()
	cyl.radius = ar
	cyl.height = yf + 13.0 - yb
	var col := CollisionShape3D.new()
	col.shape = cyl
	col.position = _v3(ac, (yb + yf + 13.0) * 0.5)
	var body := StaticBody3D.new()
	body.add_child(col)
	add_child(body)


## The free-standing bell tower: a white shaft with upright ribs and a dark spire, 50 m to the tip.
func _build_bell_tower(poly: PackedVector2Array, ymin: float) -> void:
	var mb := MB.new()
	var centre := Vector2.ZERO
	for p in poly:
		centre += p
	centre /= float(poly.size())
	var yb := ymin - 1.5
	var ys := ymin + 25.0
	var cv := PackedVector3Array()
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var f := _face(a, b, (a + b) * 0.5 - centre)
		_slit_wall(mb, f, yb, ys, "plaster_white", "dark", f.length / 3.0, 0.8, ys - 7.5, ys - 1.6)
		_cq(cv, f.p(0, yb), f.p(f.length, yb), f.p(f.length, ys), f.p(0, ys))
		# the upright ribs that run up the shaft between its openings, and the band under the spire
		for r in 4:
			mb.box("white", f.p(f.length * float(r) / 3.0, (ymin + ys) * 0.5, -0.12), f.t, Vector3.UP, f.n, Vector3(0.16, (ys - ymin) * 0.5, 0.14))
		mb.box("white", f.p(f.length * 0.5, ys - 0.5, -0.2), f.t, Vector3.UP, f.n, Vector3(f.length * 0.5 + 0.2, 0.5, 0.22))
		if i == 0:
			mb.box("door", f.p(f.length * 0.5, ymin + 1.6, -0.05), f.t, Vector3.UP, f.n, Vector3(0.8, 1.6, 0.06))
		var o := 0.35
		var ea := _v3(a + (a - centre).normalized() * o, ys)
		var eb := _v3(b + (b - centre).normalized() * o, ys)
		var apex := _v3(centre, ys + 25.0)
		var nrm := (eb - ea).cross(apex - ea).normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		mb.tri("spire", ea, eb, apex, nrm)
		mb.tri("white", ea, eb, _v3(centre, ys), Vector3.DOWN)
	_commit(mb, "Klokketarn")
	_mesh_body(cv)


# ------------------------------------------------------------------ Scandic Seilet
## The sail: a 16-storey glass tower on the tip of a wedge-shaped podium by the water.
func _build_seilet(poly: PackedVector2Array, ymin: float, ymax: float) -> void:
	_build_landmark("seilet_base", SEILET_BASE, poly, ymin, ymax, Vector2(-600.0, 300.0), 0.0, 0.0)
	var mb := MB.new()
	var w := Vector2(-805.2, 470.0)            # the two long edges of the wedge meet at the tip
	var e := Vector2(-751.4, 484.8)
	var tip := Vector2(-778.0, 528.7)
	var tin := tip - Vector2(0.0, 1.2)
	var yb := ymin + 0.25
	var fh := 3.3
	var floors := 16
	var ytop := yb + fh * floors + 1.6
	var podium := yb + 15.0
	var left_hint := Vector3(-(tip.y - w.y), 0, tip.x - w.x).normalized()
	var right_hint := Vector3(tip.y - e.y, 0, -(tip.x - e.x)).normalized()
	var steps := []                            # [y, material]
	for k in floors:
		steps.append([yb + fh * k, "sail_line"])           # a thin line at each floor, the rest glass
		steps.append([yb + fh * k + 0.28, "sail_glass"])
	steps.append([yb + fh * floors, "sail_line"])
	steps.append([ytop, ""])
	var cv := PackedVector3Array()
	for i in steps.size() - 1:
		var y0: float = steps[i][0]
		var y1: float = steps[i + 1][0]
		var m: String = steps[i][1]
		var z0 := _sail_back(y0, podium, ytop)
		var z1 := _sail_back(y1, podium, ytop)
		var l0 := _v3(_on_edge(w, tip, z0) + Vector2(0.7, 0), y0)
		var l1 := _v3(_on_edge(w, tip, z1) + Vector2(0.7, 0), y1)
		var r0 := _v3(_on_edge(e, tip, z0) - Vector2(0.7, 0), y0)
		var r1 := _v3(_on_edge(e, tip, z1) - Vector2(0.7, 0), y1)
		var t0 := _v3(tin, y0)
		var t1 := _v3(tin, y1)
		_quad_auto(mb, m, l0, r0, r1, l1, Vector3(0, 0.2, -1))
		_quad_auto(mb, m, l0, t0, t1, l1, left_hint)
		_quad_auto(mb, m, r0, t0, t1, r1, right_hint)
		_cq(cv, l0, r0, r1, l1)
		_cq(cv, l0, t0, t1, l1)
		_cq(cv, r0, t0, t1, r1)
	var zt := _sail_back(ytop, podium, ytop)
	mb.tri("white", _v3(_on_edge(w, tip, zt) + Vector2(0.7, 0), ytop), _v3(_on_edge(e, tip, zt) - Vector2(0.7, 0), ytop), _v3(tin, ytop), Vector3.UP)
	# the mast at the tip
	# (thin, and half as tall again as the tower: it is what makes the sail a sail from across the fjord)
	mb.box("steel", _v3(tin + Vector2(0, 0.5), (yb + ytop + 24.0) * 0.5), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.2, (ytop + 24.0 - yb) * 0.5, 0.2))
	for k in 6:
		mb.box("steel", _v3(tin + Vector2(0, 0.25), yb + (ytop - yb) * (float(k) + 0.5) / 6.0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.06, 0.06, 0.3))
	_commit(mb, "Seilet")
	_mesh_body(cv)


## The landward face leans back as it rises, like a filled sail.
func _sail_back(y: float, podium: float, ytop: float) -> float:
	var f := clampf((y - podium) / (ytop - podium), 0.0, 1.0)
	return 497.0 + 11.0 * pow(f, 1.7)


func _on_edge(a: Vector2, b: Vector2, z: float) -> Vector2:
	return a.lerp(b, (z - a.y) / (b.y - a.y))


# ------------------------------------------------------------------ Aker Stadion
func _build_stadium(st: Dictionary) -> void:
	var mb := MB.new()
	var cv := PackedVector3Array()
	var y0: float = st["y"]
	var pf: Array = st["pitch"]
	var p0 := Vector2(pf[0], pf[1])
	var p1 := Vector2(pf[2], pf[3])
	var p2 := Vector2(pf[4], pf[5])
	var p3 := Vector2(pf[6], pf[7])
	var c := (p0 + p1 + p2 + p3) * 0.25
	var u := (p1 - p0).normalized()
	var v := (p2 - p1).normalized()
	var hu := p0.distance_to(p1) * 0.5
	var hv := p1.distance_to(p2) * 0.5

	# outline, resampled to short segments so the stands can curve and have gates
	var of: Array = st["outline"]
	var ring := PackedVector2Array()
	var n0 := of.size() / 2
	for i in n0:
		var a := Vector2(of[2 * i], of[2 * i + 1])
		var b := Vector2(of[(2 * i + 2) % of.size()], of[(2 * i + 3) % of.size()])
		var k := maxi(1, int(ceil(a.distance_to(b) / 4.0)))
		for j in k:
			ring.append(a.lerp(b, float(j) / float(k)))
	var n := ring.size()
	var front := PackedVector2Array()          # first row of seats
	var lip := PackedVector2Array()            # inner edge of the roof
	var back := PackedVector2Array()           # top row
	var gate := PackedByteArray()
	for i in n:
		var d := ring[i] - c
		var la := d.dot(u)
		var lb := d.dot(v)
		var fr := c + u * clampf(la, -(hu + 4.5), hu + 4.5) + v * clampf(lb, -(hv + 5.0), hv + 5.0)
		front.append(fr)
		lip.append(c + u * clampf(la, -(hu + 7.3), hu + 7.3) + v * clampf(lb, -(hv + 8.6), hv + 8.6))
		back.append(ring[i] + (fr - ring[i]).normalized() * 2.6)
	for i in n:
		var mid := (ring[i] + ring[(i + 1) % n]) * 0.5 - c
		var la := mid.dot(u)
		var lb := mid.dot(v)
		gate.append(1 if ((absf(la) < 3.5 and absf(lb) > hv) or (absf(lb) < 3.5 and absf(la) > hu)) else 0)

	# The outside, after photographs of the real stadium: two storeys of pale granite with a tall glazed
	# ground floor and a ribbon of windows above it, a white band, and over that the dark roof curving in
	# and up like the back of a shell to the flat top, which runs on to the roof edge over the stands.
	var wall_y := y0 + 9.4
	var top_y := y0 + 13.5
	var crown := y0 + 18.2
	var reach := 9.0
	var curve := []                              # rings of the curved roof: [outline moved inward, height]
	for k in 6:
		var th := PI * 0.5 * float(k) / 5.0
		var rk := PackedVector2Array()
		for i in n:
			rk.append(ring[i] + (front[i] - ring[i]).normalized() * (reach * (1.0 - cos(th))))
		curve.append([rk, wall_y + (crown - wall_y) * sin(th)])
	for i in n:
		var j := (i + 1) % n
		var out := Vector3(ring[i].x + ring[j].x - 2.0 * c.x, 0, ring[i].y + ring[j].y - 2.0 * c.y).normalized()
		var oa := ring[i]
		var ob := ring[j]
		var is_gate := gate[i] == 1
		var low := y0 + 4.6
		var bands := [[y0 - 2.0, y0 + 1.2, "granite"], [y0 + 1.2, y0 + 4.0, "glass_blue"], [y0 + 4.0, y0 + 5.5, "granite"],
			[y0 + 5.5, y0 + 6.9, "glass_blue"], [y0 + 6.9, y0 + 9.0, "granite"], [y0 + 9.0, wall_y, "white"]]
		for band in bands:
			var ya: float = band[0]
			var yb: float = band[1]
			if is_gate and yb <= low:
				continue
			mb.quad(band[2], _v3(oa, maxf(ya, low) if is_gate else ya), _v3(ob, maxf(ya, low) if is_gate else ya), _v3(ob, yb), _v3(oa, yb), out)
		if is_gate:
			_quad_auto(mb, "concrete", _v3(oa, low), _v3(ob, low), _v3(back[j], low), _v3(back[i], low), Vector3.DOWN)
		else:
			_cq(cv, _v3(oa, y0 - 2.0), _v3(ob, y0 - 2.0), _v3(ob, low), _v3(oa, low))
		_cq(cv, _v3(oa, low), _v3(ob, low), _v3(ob, crown), _v3(oa, crown))
		# granite piers between the glazing, every other stretch
		if i % 2 == 0 and not is_gate:
			mb.box("granite_light", _v3(oa, y0 + 3.6) + out * 0.1, out, Vector3.UP, out.cross(Vector3.UP), Vector3(0.18, 5.4, 0.45))
		# the curved roof, with its inner face for those looking up from the stands
		for k in 5:
			var r0: PackedVector2Array = curve[k][0]
			var r1: PackedVector2Array = curve[k + 1][0]
			var h0: float = curve[k][1]
			var h1: float = curve[k + 1][1]
			_quad_auto(mb, "roof_dark", _v3(r0[i], h0), _v3(r0[j], h0), _v3(r1[j], h1), _v3(r1[i], h1), out + Vector3.UP)
			_quad_auto(mb, "steel", _v3(r0[i], h0 - 0.05), _v3(r0[j], h0 - 0.05), _v3(r1[j], h1 - 0.05), _v3(r1[i], h1 - 0.05), -out - Vector3.UP)
		# the flat top, on to the roof edge over the stands, and floodlights along that edge
		var top_ring: PackedVector2Array = curve[5][0]
		var ra := _v3(top_ring[i], crown)
		var rb := _v3(top_ring[j], crown)
		var la3 := _v3(lip[i], y0 + 20.0)
		var lb3 := _v3(lip[j], y0 + 20.0)
		_quad_auto(mb, "roof_dark", ra, rb, lb3, la3, Vector3.UP)
		_quad_auto(mb, "steel", ra - Vector3(0, 0.5, 0), rb - Vector3(0, 0.5, 0), lb3 - Vector3(0, 0.35, 0), la3 - Vector3(0, 0.35, 0), Vector3.DOWN)
		_quad_auto(mb, "steel", la3, lb3, lb3 - Vector3(0, 0.35, 0), la3 - Vector3(0, 0.35, 0), -out)
		if i % 3 == 0:
			mb.box("white", la3 + Vector3(0, 0.25, 0), out, Vector3.UP, out.cross(Vector3.UP), Vector3(0.25, 0.25, 0.6))
		# top walkway
		_quad_auto(mb, "concrete", _v3(back[i], top_y), _v3(back[j], top_y), _v3(ob, top_y), _v3(oa, top_y), Vector3.UP)
		_cq(cv, _v3(back[i], top_y), _v3(back[j], top_y), _v3(ob, top_y), _v3(oa, top_y))
		if not is_gate:
			# seats and the wall in front of them
			var fa := _v3(front[i], y0 + 1.2)
			var fb := _v3(front[j], y0 + 1.2)
			_quad_auto(mb, "seat_blue", fa, fb, _v3(back[j], top_y), _v3(back[i], top_y), Vector3.UP)
			_cq(cv, fa, fb, _v3(back[j], top_y), _v3(back[i], top_y))
			_quad_auto(mb, "concrete", _v3(front[i], y0 - 0.5), _v3(front[j], y0 - 0.5), fb, fa, -out)
			_cq(cv, _v3(front[i], y0 - 0.5), _v3(front[j], y0 - 0.5), fb, fa)
		# the cut through the stand on either side of a gate
		if is_gate != (gate[(i + n - 1) % n] == 1):
			var along := Vector3(ob.x - oa.x, 0, ob.y - oa.y).normalized()
			for side in [along, -along]:
				var sd: Vector3 = side
				mb.quad("concrete", _v3(front[i], y0 - 0.5), _v3(back[i], y0 - 0.5), _v3(back[i], top_y), _v3(front[i], y0 + 1.2), sd)
				mb.quad("concrete", _v3(back[i], y0 - 0.5), _v3(oa, y0 - 0.5), _v3(oa, top_y), _v3(back[i], top_y), sd)
			_cq(cv, _v3(front[i], y0 - 0.5), _v3(back[i], y0 - 0.5), _v3(back[i], top_y), _v3(front[i], y0 + 1.2))
			_cq(cv, _v3(back[i], y0 - 0.5), _v3(oa, y0 - 0.5), _v3(oa, top_y), _v3(back[i], top_y))

	# the pitch
	var yp := y0 + 0.06
	var ux := Vector3(u.x, 0, u.y)
	var vx := Vector3(v.x, 0, v.y)
	mb.quad("pitch", _v3(c - u * (hu + 4.4) - v * (hv + 4.9), yp), _v3(c + u * (hu + 4.4) - v * (hv + 4.9), yp),
		_v3(c + u * (hu + 4.4) + v * (hv + 4.9), yp), _v3(c - u * (hu + 4.4) + v * (hv + 4.9), yp), Vector3.UP)
	var yl := yp + 0.02
	var lw := 0.07
	for s in [-1.0, 1.0]:
		var sd: float = s
		mb.box("line", _v3(c + v * hv * sd, yl), ux, Vector3.UP, vx, Vector3(hu, 0.005, lw))
		mb.box("line", _v3(c + u * hu * sd, yl), ux, Vector3.UP, vx, Vector3(lw, 0.005, hv))
		# penalty area and goal
		mb.box("line", _v3(c + u * (hu - 16.5) * sd, yl), ux, Vector3.UP, vx, Vector3(lw, 0.005, 20.15))
		for t in [-1.0, 1.0]:
			var td: float = t
			mb.box("line", _v3(c + u * (hu - 8.25) * sd + v * 20.15 * td, yl), ux, Vector3.UP, vx, Vector3(8.25, 0.005, lw))
			mb.box("white", _v3(c + u * hu * sd + v * 3.66 * td, y0 + 1.22), ux, Vector3.UP, vx, Vector3(0.06, 1.22, 0.06))
		mb.box("white", _v3(c + u * hu * sd, y0 + 2.44), ux, Vector3.UP, vx, Vector3(0.06, 0.06, 3.72))
	mb.box("line", _v3(c, yl), ux, Vector3.UP, vx, Vector3(lw, 0.005, hv))
	for i in 40:
		var t0 := TAU * float(i) / 40.0
		var t1 := TAU * float(i + 1) / 40.0
		var q0 := c + (u * cos(t0) + v * sin(t0)) * 9.15
		var q1 := c + (u * cos(t1) + v * sin(t1)) * 9.15
		var dir := (q1 - q0).normalized()
		mb.box("line", _v3((q0 + q1) * 0.5, yl), Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(-dir.y, 0, dir.x), Vector3(q0.distance_to(q1) * 0.5 + 0.03, 0.005, lw))
	# The entrance tower in the middle of the side that faces the fjord: light granite, taller than the roof,
	# with a dark glazed centre and the name over it. A white frame stands at each end of that side.
	var sea := 1.0 if v.y > 0.0 else -1.0
	var edge := 0.0
	var ends := 0.0
	for q in ring:
		var dq := q - c
		if absf(dq.dot(u)) < 8.0:
			edge = maxf(edge, dq.dot(v) * sea)
		if dq.dot(v) * sea > hv:
			ends = maxf(ends, absf(dq.dot(u)))
	var outv := Vector3(v.x, 0, v.y) * sea
	var tower := _v3(c + v * sea * (edge + 0.5), y0 + 8.0)
	mb.box("granite_light", tower, ux, Vector3.UP, outv, Vector3(11.0, 10.5, 3.5))
	mb.quad("glass_blue", tower + ux * -5.0 + outv * 3.56 + Vector3(0, -8.0, 0), tower + ux * 5.0 + outv * 3.56 + Vector3(0, -8.0, 0),
		tower + ux * 5.0 + outv * 3.56 + Vector3(0, 6.2, 0), tower + ux * -5.0 + outv * 3.56 + Vector3(0, 6.2, 0), outv)
	for k in range(-2, 3):
		mb.box("granite_light", tower + ux * (float(k) * 2.5) + outv * 3.6 + Vector3(0, -0.9, 0), ux, Vector3.UP, outv, Vector3(0.12, 7.1, 0.12))
	for yy in [-4.5, -1.0, 2.5]:
		var by: float = yy
		mb.box("granite_light", tower + outv * 3.6 + Vector3(0, by, 0), ux, Vector3.UP, outv, Vector3(5.0, 0.12, 0.12))
	_cq(cv, tower + ux * -11.0 + outv * 3.5 + Vector3(0, -10.5, 0), tower + ux * 11.0 + outv * 3.5 + Vector3(0, -10.5, 0),
		tower + ux * 11.0 + outv * 3.5 + Vector3(0, 10.5, 0), tower + ux * -11.0 + outv * 3.5 + Vector3(0, 10.5, 0))
	var name := Label3D.new()
	name.text = "AKER STADION"
	name.font_size = 160
	name.pixel_size = 0.0075
	name.outline_size = 0
	name.modulate = Color(0.08, 0.08, 0.09)
	name.double_sided = false
	name.transform = Transform3D(Basis(Vector3.UP.cross(outv), Vector3.UP, outv), tower + outv * 3.58 + Vector3(0, 8.4, 0))
	add_child(name)
	for s2 in [-1.0, 1.0]:
		var sd2: float = s2
		var fc := _v3(c + u * sd2 * (ends - 4.0) + v * sea * (edge + 3.0), y0 + 4.5)
		mb.box("white", fc + ux * 4.0, ux, Vector3.UP, outv, Vector3(0.35, 5.5, 0.35))
		mb.box("white", fc - ux * 4.0, ux, Vector3.UP, outv, Vector3(0.35, 5.5, 0.35))
		mb.box("white", fc + Vector3(0, 5.2, 0), ux, Vector3.UP, outv, Vector3(4.35, 0.35, 0.35))
	_commit(mb, "AkerStadion")
	_mesh_body(cv)


# ------------------------------------------------------------------ piers and breakwaters
func _build_piers(piers: Array) -> void:
	var mb := MB.new()
	var cv := PackedVector3Array()
	var deck := 1.5
	var foot := -4.0
	for pr in piers:
		var flat: Array = pr["pts"]
		var pts := PackedVector2Array()
		for i in flat.size() / 2:
			pts.append(Vector2(flat[2 * i], flat[2 * i + 1]))
		var stone: bool = pr["kind"] == "breakwater"
		var m := "concrete_dark" if stone else "concrete"
		var top := deck + (0.5 if stone else 0.0)
		if pr["closed"] and pts.size() >= 3:
			var centre := Vector2.ZERO
			for p in pts:
				centre += p
			centre /= float(pts.size())
			var tris := Geometry2D.triangulate_polygon(pts)
			var i := 0
			while i + 2 < tris.size():
				var a := _v3(pts[tris[i]], top)
				var b := _v3(pts[tris[i + 1]], top)
				var c := _v3(pts[tris[i + 2]], top)
				mb.tri(m, a, b, c, Vector3.UP)
				cv.append(a); cv.append(b); cv.append(c)
				i += 3
			for k in pts.size():
				var a2 := pts[k]
				var b2 := pts[(k + 1) % pts.size()]
				if a2.distance_to(b2) < 0.05:
					continue
				var f := _face(a2, b2, (a2 + b2) * 0.5 - centre)
				mb.quad(m, f.p(0, foot), f.p(f.length, foot), f.p(f.length, top), f.p(0, top), f.n)
				_cq(cv, f.p(0, foot), f.p(f.length, foot), f.p(f.length, top), f.p(0, top))
		else:
			var half := 3.5 if stone else 2.2
			for k in pts.size() - 1:
				var a3 := pts[k]
				var b3 := pts[k + 1]
				var length := a3.distance_to(b3)
				if length < 0.05:
					continue
				var dir := (b3 - a3) / length
				var mid := _v3((a3 + b3) * 0.5, (top + foot) * 0.5)
				var size := Vector3(length * 0.5 + half * 0.5, (top - foot) * 0.5, half)
				mb.box(m, mid, Vector3(dir.x, 0, dir.y), Vector3.UP, Vector3(-dir.y, 0, dir.x), size)
				_box_body(mid, dir, size * 2.0)
	if not mb.surf.is_empty():
		_commit(mb, "Piers")
	_mesh_body(cv)


# ------------------------------------------------------------------ tunnel mouths
## A concrete portal where a road goes into the hill. The tunnels are not open: each mouth is
## dark a few metres in, and Haukabøtunnelen — the road out to the west — is buried in rubble.
func _build_portals(portals: Array) -> void:
	if portals.is_empty():
		return
	var mb := MB.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 662
	for pt in portals:
		var at := Vector2(pt["x"], pt["z"])
		var d := Vector2(pt["dx"], pt["dz"])            # into the hill
		var side := Vector2(-d.y, d.x)
		var d3 := Vector3(d.x, 0, d.y)
		var s3 := Vector3(side.x, 0, side.y)
		var y: float = world.height_at(at.x, at.y)
		var hw: float = float(pt["w"]) * 0.5 + 1.2
		var h: float = pt.get("h", 5.6)
		var wing := 4.0 if h > 3.5 else 0.9                  # a doorway for people has short cheeks, not road-sized wing walls
		for sgn in [-1.0, 1.0]:
			var sd: float = sgn
			mb.box("concrete", _v3(at + side * (hw + 0.8) * sd + d * 3.0, y + h * 0.5 - 1.0), s3, Vector3.UP, d3, Vector3(0.8, h * 0.5 + 1.0, 4.0))
			_box_body(_v3(at + side * (hw + 0.8) * sd + d * 3.0, y + h * 0.5 - 1.0), side, Vector3(1.6, h + 2.0, 8.0))
			# wing walls holding back the hillside
			mb.box("concrete", _v3(at + side * (hw + 1.6 + wing) * sd - d * 0.6, y + h * 0.5 - 0.5), s3, Vector3.UP, d3, Vector3(wing, h * 0.5 + (1.5 if h > 3.5 else 0.7), 0.4))
		mb.box("concrete", _v3(at + d * 3.0, y + h + 0.6), s3, Vector3.UP, d3, Vector3(hw + 1.6, 0.6, 4.0))
		mb.box("concrete_dark", _v3(at - d * 1.0, y + h + (1.7 if h > 3.5 else 1.0)), s3, Vector3.UP, d3, Vector3(hw + 1.6 + (wing * 2.0 if h > 3.5 else 0.4), 0.5 if h > 3.5 else 0.25, 0.45))
		mb.box("dark", _v3(at + d * 7.2, y + h * 0.5), s3, Vector3.UP, d3, Vector3(hw, h * 0.5 + 0.2, 0.3))
		_box_body(_v3(at + d * 7.2, y + h * 0.5), side, Vector3(hw * 2.0, h + 0.4, 0.6))
		_box_body(_v3(at + d * 3.0, y + h + 0.6), side, Vector3(hw * 2.0 + 3.2, 1.2, 8.0))
		if pt.get("rubble", false):
			# a collapse: broken concrete and rock from the roof, spilling out onto the road
			for i in 110:
				var back := rng.randf_range(-7.0, 6.5)
				var across := rng.randf_range(-hw, hw)
				var pile := clampf(1.0 - absf(back - 1.5) / 8.5, 0.05, 1.0) * (h + 0.3)
				var size := Vector3(rng.randf_range(0.35, 1.5), rng.randf_range(0.3, 1.1), rng.randf_range(0.35, 1.7))
				if back < -3.0:
					size *= 0.6
				var c := _v3(at + d * back + side * across, y + rng.randf_range(0.0, pile))
				var b := Basis.from_euler(Vector3(rng.randf_range(-0.6, 0.6), rng.randf_range(0, TAU), rng.randf_range(-0.6, 0.6)))
				mb.box("concrete_dark" if i % 3 == 0 else ("gravel" if i % 3 == 1 else "concrete"), c, b.x, b.y, b.z, size * 0.5)
			var heap := _v3(at + d * 1.0, y + h * 0.5)
			_box_body(heap, side, Vector3(hw * 2.0, h, 9.0))
			_box_body(_v3(at - d * 5.0, y + 0.5), side, Vector3(hw * 2.0, 1.4, 4.0))
	_commit(mb, "Portals")
# ------------------------------------------------------------------ the quay front
## The harbour front of the town centre: a straight concrete quay wall along the line the map gives for the
## shore, with a kerb along its edge. Each piece is [ax, az, bx, bz, nx, nz], n pointing out to sea.
func _build_quays(quays: Array) -> void:
	if quays.is_empty():
		return
	var mb := MB.new()
	var cv := PackedVector3Array()
	for q in quays:
		var a := Vector2(q[0], q[1])
		var b := Vector2(q[2], q[3])
		var n := Vector3(q[4], 0, q[5])
		var length := a.distance_to(b)
		if length < 0.1:
			continue
		var dir := (b - a) / length
		var parts := maxi(1, int(ceil(length / 4.0)))
		for k in parts:
			var p0 := a.lerp(b, float(k) / parts)
			var p1 := a.lerp(b, float(k + 1) / parts)
			var y0: float = maxf(world.height_at(p0.x - n.x * 1.5, p0.y - n.z * 1.5), 1.5) + 0.03
			var y1: float = maxf(world.height_at(p1.x - n.x * 1.5, p1.y - n.z * 1.5), 1.5) + 0.03
			var a0 := _v3(p0, y0) + n * 0.15
			var a1 := _v3(p1, y1) + n * 0.15
			mb.quad("concrete", Vector3(a0.x, -4.0, a0.z), Vector3(a1.x, -4.0, a1.z), a1, a0, n)
			_cq(cv, Vector3(a0.x, -4.0, a0.z), Vector3(a1.x, -4.0, a1.z), a1 + Vector3(0, 0.2, 0), a0 + Vector3(0, 0.2, 0))
			mb.quad("concrete", a0, a1, a1 - n * 1.9, a0 - n * 1.9, Vector3.UP)                      # the edge of the quay, level
			var mid := (a0 + a1) * 0.5 - n * 0.3 + Vector3(0, 0.1, 0)
			mb.box("concrete_dark", mid, Vector3(dir.x, 0, dir.y), Vector3.UP, n, Vector3(p0.distance_to(p1) * 0.5, 0.11, 0.22))
	if not mb.surf.is_empty():
		_commit(mb, "Quays")
	_mesh_body(cv)


# ------------------------------------------------------------------ Molde idrettspark
## The athletics ground above the town centre: a red running track round a grass football pitch, the main
## stand with blue seats under a roof on the north side, and two open concrete stands on the south side.
func _build_sports(sp: Dictionary) -> void:
	if not sp.has("level"):
		return
	var mb := MB.new()
	var cv := PackedVector3Array()
	var level: float = sp["level"]
	var flat: Array = sp.get("track", [])
	var loop := PackedVector2Array()
	for i in flat.size() / 2:
		loop.append(Vector2(flat[2 * i], flat[2 * i + 1]))
	var n := loop.size()
	var half: float = sp.get("half", 3.7)
	for i in n:
		var p0 := loop[i]
		var p1 := loop[(i + 1) % n]
		var t0 := (loop[(i + 1) % n] - loop[(i - 1 + n) % n]).normalized()
		var t1 := (loop[(i + 2) % n] - loop[i]).normalized()
		var n0 := Vector2(t0.y, -t0.x)
		var n1 := Vector2(t1.y, -t1.x)
		mb.quad("track", _v3(p0 + n0 * half, level + 0.06), _v3(p1 + n1 * half, level + 0.06), _v3(p1 - n1 * half, level + 0.06), _v3(p0 - n0 * half, level + 0.06), Vector3.UP)
		for lane in 7:
			var off := -half + 0.08 + float(lane) * (half * 2.0 - 0.16) / 6.0
			mb.quad("line", _v3(p0 + n0 * (off - 0.03), level + 0.075), _v3(p1 + n1 * (off - 0.03), level + 0.075),
				_v3(p1 + n1 * (off + 0.03), level + 0.075), _v3(p0 + n0 * (off + 0.03), level + 0.075), Vector3.UP)
	if sp.has("pitch"):
		var pf: Array = sp["pitch"]                          # centre x, z, direction along it x, z, half length, half width
		var c := Vector2(pf[0], pf[1])
		var u := Vector2(pf[2], pf[3])
		var v := Vector2(-u.y, u.x)
		var hl: float = pf[4]
		var hw: float = pf[5]
		var y := level + 0.05
		mb.quad("pitch", _v3(c - u * hl - v * hw, y), _v3(c + u * hl - v * hw, y), _v3(c + u * hl + v * hw, y), _v3(c - u * hl + v * hw, y), Vector3.UP)
		var ly := y + 0.015
		# a small pitch has its markings and goals in proportion
		var sc := clampf(hl / 52.5, 0.25, 1.0)
		var bx := 16.5 * sc
		var bw := minf(20.16 * sc, hw - 1.0)
		var lines := [[-hl, -hw, hl, -hw], [-hl, hw, hl, hw], [-hl, -hw, -hl, hw], [hl, -hw, hl, hw], [0.0, -hw, 0.0, hw],
			[-hl, -bw, -hl + bx, -bw], [-hl, bw, -hl + bx, bw], [-hl + bx, -bw, -hl + bx, bw],
			[hl, -bw, hl - bx, -bw], [hl, bw, hl - bx, bw], [hl - bx, -bw, hl - bx, bw]]
		for ln in lines:
			var a := c + u * float(ln[0]) + v * float(ln[1])
			var b := c + u * float(ln[2]) + v * float(ln[3])
			var d := (b - a).normalized()
			var w := Vector2(-d.y, d.x) * 0.06
			mb.quad("line", _v3(a - w - d * 0.06, ly), _v3(b - w + d * 0.06, ly), _v3(b + w + d * 0.06, ly), _v3(a + w - d * 0.06, ly), Vector3.UP)
		for k in 24:
			var a0 := TAU * float(k) / 24.0
			var a1 := TAU * float(k + 1) / 24.0
			var q0 := c + u * (cos(a0) * 9.15 * sc) + v * (sin(a0) * 9.15 * sc)
			var q1 := c + u * (cos(a1) * 9.15 * sc) + v * (sin(a1) * 9.15 * sc)
			var w2 := (q0 - c).normalized() * 0.06
			var w3 := (q1 - c).normalized() * 0.06
			mb.quad("line", _v3(q0 - w2, ly), _v3(q1 - w3, ly), _v3(q1 + w3, ly), _v3(q0 + w2, ly), Vector3.UP)
		for sgn in [-1.0, 1.0]:                                # goals
			var sg: float = sgn
			var g := c + u * (hl * sg)
			var gw := 3.66 if sc > 0.7 else 2.5 if sc > 0.45 else 1.5          # 11-, 7- and 5-a-side goals
			var gh := 2.44 if sc > 0.45 else 2.0
			for side in [-gw, gw]:
				var sd: float = side
				mb.box("white", _v3(g + v * sd, y + gh * 0.5), Vector3(u.x, 0, u.y), Vector3.UP, Vector3(v.x, 0, v.y), Vector3(0.06, gh * 0.5, 0.06))
			mb.box("white", _v3(g, y + gh), Vector3(u.x, 0, u.y), Vector3.UP, Vector3(v.x, 0, v.y), Vector3(0.06, 0.06, gw + 0.06))
	# stands: [centre x, z, direction along it x, z, length, depth, rows, 1 = seats and a roof]; the rows climb away from the pitch
	for sd in sp.get("stands", []):
		var c2 := Vector2(sd[0], sd[1])
		var u2 := Vector2(sd[2], sd[3])
		var back := Vector2(sd[4], sd[5])                   # unit vector from the front row to the back
		var length: float = sd[6]
		var rows: int = sd[7]
		var seats: bool = sd[8] > 0.5
		var row_d := 0.85
		var rise := 0.42
		var ux := Vector3(u2.x, 0, u2.y)
		var bx := Vector3(back.x, 0, back.y)
		var base: float = sd[9]
		for r in rows:
			var y0 := base + 0.5 + rise * float(r)
			var front := _v3(c2 + back * (row_d * float(r)), 0.0)
			# (each step goes well down into the ground: where the ground falls away at an end, the stand stood in the air)
			var mid := front + bx * (row_d * 0.5) + Vector3(0, y0 * 0.5 + (base - 6.0) * 0.5, 0)
			mb.box("concrete", mid, ux, Vector3.UP, bx, Vector3(length * 0.5, (y0 - (base - 6.0)) * 0.5, row_d * 0.5))
			var e0 := front - ux * (length * 0.5) + Vector3(0, y0, 0)
			var e1 := front + ux * (length * 0.5) + Vector3(0, y0, 0)
			_cq(cv, e0, e1, e1 + bx * row_d, e0 + bx * row_d)
			_cq(cv, e0 - Vector3(0, rise, 0), e1 - Vector3(0, rise, 0), e1, e0)
			if seats:
				mb.box("seat_blue", front + bx * (row_d * 0.62) + Vector3(0, y0 + 0.2, 0), ux, Vector3.UP, bx, Vector3(length * 0.5 - 0.6, 0.2, 0.2))
		var depth := row_d * float(rows)
		var top_y := base + 0.5 + rise * float(rows)
		var rear := _v3(c2 + back * depth, 0.0)
		if seats:
			# the building behind the seats and the roof over them, on a row of columns at the back
			var house_d: float = sd[10]
			var roof_y := top_y + 4.2
			if house_d > 1.0:
				mb.box("granite", rear + bx * (house_d * 0.5) + Vector3(0, (roof_y + base - 6.0) * 0.5, 0), ux, Vector3.UP, bx, Vector3(length * 0.5, (roof_y - base + 6.0) * 0.5, house_d * 0.5))       # (down into the ground: its south-west corner hung in the air, 21 Nov)
				_box_body(rear + bx * (house_d * 0.5) + Vector3(0, (roof_y + base) * 0.5, 0), u2, Vector3(length, roof_y - base, house_d))
				mb.box("glass_blue", rear + bx * (-0.03) + Vector3(0, top_y + 1.6, 0), ux, Vector3.UP, bx, Vector3(length * 0.5 - 2.0, 0.9, 0.04))
			mb.box("roof_dark", rear + bx * (house_d * 0.5 - depth * 0.5) + Vector3(0, roof_y + 0.2, 0), ux, Vector3.UP, bx, Vector3(length * 0.5 + 0.8, 0.2, (house_d + depth) * 0.5 + 0.6))
			if house_d <= 1.0:
				# a stand by itself: the roof on a row of steel columns behind the last row, and a wall at its back
				# (the roof hung in the air: "a part of the roof is floating", 21 Nov)
				var posts := maxi(2, int(length / 6.0) + 1)
				for k in posts:
					var along2 := -length * 0.5 + 0.4 + (length - 0.8) * float(k) / float(posts - 1)
					mb.box("steel", rear + ux * along2 + bx * 0.25 + Vector3(0, (roof_y + base - 1.0) * 0.5, 0), ux, Vector3.UP, bx, Vector3(0.11, (roof_y - base + 1.0) * 0.5, 0.11))
				mb.box("concrete", rear + bx * 0.45 + Vector3(0, (top_y + 1.1 + base - 6.0) * 0.5, 0), ux, Vector3.UP, bx, Vector3(length * 0.5, (top_y + 1.1 - base + 6.0) * 0.5, 0.10))
		else:
			mb.box("concrete", rear + bx * 0.12 + Vector3(0, (top_y + 1.0 + base - 1.0) * 0.5, 0), ux, Vector3.UP, bx, Vector3(length * 0.5, (top_y + 1.0 - base + 1.0) * 0.5, 0.12))
			_box_body(rear + bx * 0.12 + Vector3(0, (top_y + 1.0 + base) * 0.5, 0), u2, Vector3(length, top_y + 1.0 - base, 0.24))
	if not mb.surf.is_empty():
		_commit(mb, "Idrettspark")
	_mesh_body(cv)


# ------------------------------------------------------------------ filling stations
## A roof on columns over the pumps: [outline x, z, …], the ground under it and the height of the roof.
func _build_canopies(canopies: Array) -> void:
	if canopies.is_empty():
		return
	var mb := MB.new()
	for cn in canopies:
		var c := Vector2(cn["c"][0], cn["c"][1])
		var u := Vector2(cn["u"][0], cn["u"][1])
		var v := Vector2(-u.y, u.x)
		var hl: float = cn["hl"]
		var hw: float = cn["hw"]
		var ground: float = cn["ground"]
		var top: float = ground + float(cn["h"])
		var ux := Vector3(u.x, 0, u.y)
		var vx := Vector3(v.x, 0, v.y)
		mb.box("white", _v3(c, top - 0.35), ux, Vector3.UP, vx, Vector3(hl, 0.35, hw))
		mb.box("fuel_red", _v3(c, top - 0.35), ux, Vector3.UP, vx, Vector3(hl + 0.04, 0.2, hw + 0.04))
		mb.box("fuel_yellow", _v3(c, top - 0.62), ux, Vector3.UP, vx, Vector3(hl + 0.05, 0.05, hw + 0.05))
		if cn.get("turn", false):
			# the islands side by side across the roof's shorter side, each lying along its longer side: one drives
			# through from end to end, a row of pumps on either hand
			var rows := maxi(1, int(hw / 3.6))
			var reach := hl - 2.6
			for k in rows:
				var across := ((float(k) + 0.5) / float(rows) * 2.0 - 1.0) * hw
				var p := c + v * (across * (hw - 2.4) / hw)
				var py: float = world.height_at(p.x, p.y)
				mb.box("concrete", _v3(p, py + 0.08), ux, Vector3.UP, vx, Vector3(reach * 0.75, 0.1, 0.6))             # the island
				for sgn in [-1.0, 1.0]:
					var sg: float = sgn
					var col := p + u * (sg * reach * 0.72)
					mb.box("steel", _v3(col, (py + top) * 0.5), ux, Vector3.UP, vx, Vector3(0.16, (top - py) * 0.5, 0.16))
					_box_body(_v3(col, (py + top) * 0.5), u, Vector3(0.32, top - py, 0.32))
					var pump := p + u * (sg * reach * 0.30)
					mb.box("fuel_red", _v3(pump, py + 0.95), ux, Vector3.UP, vx, Vector3(0.5, 0.8, 0.28))
					mb.box("dark", _v3(pump, py + 1.35), ux, Vector3.UP, vx, Vector3(0.36, 0.22, 0.29))
					_box_body(_v3(pump, py + 0.9), u, Vector3(1.0, 1.8, 0.56))
		var islands := maxi(1, int(hl / 4.5))
		if cn.get("turn", false):
			islands = 0
		for k in islands:
			var along := (float(k) + 0.5) / float(islands) * 2.0 - 1.0
			var p := c + u * (along * (hl - 2.5))
			var py: float = world.height_at(p.x, p.y)
			mb.box("concrete", _v3(p, py + 0.08), ux, Vector3.UP, vx, Vector3(0.6, 0.1, hw * 0.55))             # the island
			for sgn in [-1.0, 1.0]:
				var sg: float = sgn
				var col := p + v * (sg * hw * 0.5)
				mb.box("steel", _v3(col, (py + top) * 0.5), ux, Vector3.UP, vx, Vector3(0.16, (top - py) * 0.5, 0.16))
				_box_body(_v3(col, (py + top) * 0.5), u, Vector3(0.32, top - py, 0.32))
				var pump := p + v * (sg * hw * 0.2)
				mb.box("fuel_red", _v3(pump, py + 0.95), ux, Vector3.UP, vx, Vector3(0.28, 0.8, 0.5))
				mb.box("dark", _v3(pump, py + 1.35), ux, Vector3.UP, vx, Vector3(0.29, 0.22, 0.36))
				_box_body(_v3(pump, py + 0.9), u, Vector3(0.56, 1.8, 1.0))
	if not mb.surf.is_empty():
		_commit(mb, "Canopies")
# ------------------------------------------------------------------ footbridges between buildings
## An enclosed, glazed footbridge high above the ground: a floor and a roof slab, glass walls with steel
## posts, and a pair of columns under every bend of a long one.
func _build_skywalks(walks: Array) -> void:
	if walks.is_empty():
		return
	var mb := MB.new()
	for sk in walks:
		var flat: Array = sk["pts"]
		var pts := PackedVector2Array()
		for i in flat.size() / 2:
			pts.append(Vector2(flat[2 * i], flat[2 * i + 1]))
		var half: float = float(sk["w"]) * 0.5
		var y: float = sk["y"]
		var tall := 3.0
		for i in pts.size() - 1:
			var a := pts[i]
			var b := pts[i + 1]
			var length := a.distance_to(b)
			if length < 0.2:
				continue
			var d := (b - a) / length
			var ux := Vector3(d.x, 0, d.y)
			var vx := Vector3(-d.y, 0, d.x)
			var mid := _v3((a + b) * 0.5, y)
			var run := length * 0.5 + half * 0.3
			mb.box("concrete", mid + Vector3(0, -0.25, 0), ux, Vector3.UP, vx, Vector3(run, 0.25, half + 0.1))
			mb.box("roof_dark", mid + Vector3(0, tall + 0.15, 0), ux, Vector3.UP, vx, Vector3(run, 0.15, half + 0.25))
			for sgn in [-1.0, 1.0]:
				var sg: float = sgn
				mb.box("granite_light", mid + vx * (half * sg) + Vector3(0, 0.45, 0), ux, Vector3.UP, vx, Vector3(run, 0.45, 0.08))
				mb.box("glass_blue", mid + vx * (half * sg) + Vector3(0, 0.9 + (tall - 0.9) * 0.5, 0), ux, Vector3.UP, vx, Vector3(run, (tall - 0.9) * 0.5, 0.04))
				var posts := maxi(1, int(length / 2.5))
				for k in posts + 1:
					var along := -length * 0.5 + length * float(k) / float(posts)
					mb.box("steel", mid + ux * along + vx * (half * sg) + Vector3(0, tall * 0.5, 0), ux, Vector3.UP, vx, Vector3(0.05, tall * 0.5, 0.07))
			_box_body(mid + Vector3(0, tall * 0.5 - 0.1, 0), d, Vector3(length + half * 0.6, tall + 0.8, half * 2.0 + 0.2))
		for i in range(1, pts.size() - 1):
			var p := pts[i]
			var d2 := (pts[i + 1] - pts[i - 1]).normalized()
			var side := Vector2(-d2.y, d2.x)
			for sgn in [-1.0, 1.0]:
				var sg2: float = sgn
				var q := p + side * (half * 0.7 * sg2)
				var gy: float = world.height_at(q.x, q.y)
				if y - gy > 1.5:
					mb.box("concrete", _v3(q, (gy + y) * 0.5 - 0.25), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.3, (y - gy) * 0.5 + 0.25, 0.3))
					_box_body(_v3(q, (gy + y) * 0.5), Vector2(1, 0), Vector3(0.6, y - gy, 0.6))
	if not mb.surf.is_empty():
		_commit(mb, "Skywalks")
# ------------------------------------------------------------------ the golf course
## Greens with a flag, and a bunker beside each: [x, z, the way the bunker lies]. The course is mapped only as
## an outline, so where they are is made up; they lie on the ground as it is.
func _build_golf(greens: Array) -> void:
	if greens.is_empty():
		return
	var mb := MB.new()
	for gr in greens:
		var c := Vector2(gr[0], gr[1])
		var turn: float = gr[2]
		var segs := 20
		for ring in 2:
			var r0 := 0.0 if ring == 0 else 5.0
			var r1 := 5.0 if ring == 0 else 9.5
			for k in segs:
				var a0 := TAU * float(k) / segs
				var a1 := TAU * float(k + 1) / segs
				var pts := []
				for q in [[r0, a0], [r1, a0], [r1, a1], [r0, a1]]:
					var p := c + Vector2(cos(q[1]), sin(q[1]) * 0.8).rotated(turn) * float(q[0])
					pts.append(Vector3(p.x, world.height_at(p.x, p.y) + 0.16, p.y))
				mb.quad("green", pts[0], pts[1], pts[2], pts[3], Vector3.UP)
		# the bunker: a kidney of sand to one side
		var bc := c + Vector2(cos(turn), sin(turn)) * 14.0
		for k in 14:
			var a0 := TAU * float(k) / 14.0
			var a1 := TAU * float(k + 1) / 14.0
			var p0 := bc + Vector2(cos(a0) * 5.0, sin(a0) * 2.8).rotated(turn + 1.2)
			var p1 := bc + Vector2(cos(a1) * 5.0, sin(a1) * 2.8).rotated(turn + 1.2)
			mb.tri("sand", Vector3(bc.x, world.height_at(bc.x, bc.y) + 0.10, bc.y), Vector3(p0.x, world.height_at(p0.x, p0.y) + 0.14, p0.y),
				Vector3(p1.x, world.height_at(p1.x, p1.y) + 0.14, p1.y), Vector3.UP)
		# the pin and its flag
		var gy: float = world.height_at(c.x, c.y)
		mb.box("white", Vector3(c.x, gy + 1.05, c.y), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.012, 1.05, 0.012))
		mb.box("fuel_red", Vector3(c.x + 0.17, gy + 1.93, c.y), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.17, 0.11, 0.006))
	if not mb.surf.is_empty():
		_commit(mb, "Golf")
# ------------------------------------------------------------------ volleyball courts
## A sand court with its boundary tapes and a net on two posts: [centre x, z, direction x, z, half length, half width, level].
func _build_courts(courts: Array) -> void:
	if courts.is_empty():
		return
	var mb := MB.new()
	for ct in courts:
		var c := Vector2(ct[0], ct[1])
		var u := Vector2(ct[2], ct[3])
		var v := Vector2(-u.y, u.x)
		var hl: float = ct[4]
		var hw: float = ct[5]
		var y: float = float(ct[6]) + 0.06
		var ux := Vector3(u.x, 0, u.y)
		var vx := Vector3(v.x, 0, v.y)
		mb.quad("sand", _v3(c - u * (hl + 2.0) - v * (hw + 2.0), y), _v3(c + u * (hl + 2.0) - v * (hw + 2.0), y), _v3(c + u * (hl + 2.0) + v * (hw + 2.0), y), _v3(c - u * (hl + 2.0) + v * (hw + 2.0), y), Vector3.UP)
		for ln in [[-hl, -hw, hl, -hw], [-hl, hw, hl, hw], [-hl, -hw, -hl, hw], [hl, -hw, hl, hw]]:
			var a := c + u * float(ln[0]) + v * float(ln[1])
			var b := c + u * float(ln[2]) + v * float(ln[3])
			var d := (b - a).normalized()
			var w := Vector2(-d.y, d.x) * 0.04
			mb.quad("tape", _v3(a - w, y + 0.012), _v3(b - w, y + 0.012), _v3(b + w, y + 0.012), _v3(a + w, y + 0.012), Vector3.UP)
		for sgn in [-1.0, 1.0]:
			var sg: float = sgn
			mb.box("steel", _v3(c + v * (sg * (hw + 0.6)), y + 1.25), ux, Vector3.UP, vx, Vector3(0.04, 1.25, 0.04))
		mb.quad("net", _v3(c - v * (hw + 0.6), y + 1.40), _v3(c + v * (hw + 0.6), y + 1.40), _v3(c + v * (hw + 0.6), y + 2.40), _v3(c - v * (hw + 0.6), y + 2.40), ux)
		mb.box("line", _v3(c, y + 2.40), vx, Vector3.UP, ux, Vector3(hw + 0.6, 0.025, 0.012))
		mb.box("line", _v3(c, y + 1.40), vx, Vector3.UP, ux, Vector3(hw + 0.6, 0.015, 0.01))
	if not mb.surf.is_empty():
		_commit(mb, "Courts")
# ------------------------------------------------------------------ fountains
## What stands in the middle of a pond. A whale: its back and head out of the water, the tail lifted behind,
## and a jet of water blown up from the top of its head, falling back round it.
func _build_fountains(list: Array) -> void:
	for f in list:
		if f.get("kind", "") != "whale":
			continue
		var o := Vector3(f["x"], f["y"], f["z"])
		var g = preload("res://scripts/car.gd").Geo.new()
		var mats := {"whale": _plain(Color(0.20, 0.25, 0.30), 0.35, 0.3), "belly": _plain(Color(0.72, 0.74, 0.74), 0.5), "dark": _plain(Color(0.03, 0.03, 0.04), 0.3)}
		# the body: long and round, thickest behind the head, tapering to the tail which curves up out of the water
		var rows := []
		for i in 25:
			var t := float(i) / 24.0
			var z := lerpf(-1.9, 2.3, t)
			var r := 0.62 * pow(sin(clampf(t * 0.93 + 0.07, 0.0, 1.0) * PI), 0.6) * (1.0 - 0.45 * t)
			var lift := 0.9 * pow(maxf(0.0, t - 0.62) / 0.38, 2.0)
			var ring := PackedVector3Array()
			for k in 16:
				var a := TAU * float(k) / 16.0
				ring.append(Vector3(cos(a) * r * 1.1, 0.02 + lift + sin(a) * r * 0.85, z))
			rows.append(ring)
		g.skin(rows, true, func(_i: int, j: int) -> String: return "belly" if j >= 10 and j <= 14 else "whale")
		for sgn in [-1.0, 1.0]:
			var sx: float = sgn
			g.ball("whale", Vector3(0.42 * sx, 0.92, 2.42), Vector3(0.46, 0.05, 0.24), 12, 5)                # the flukes
			g.ball("whale", Vector3(0.72 * sx, 0.0, -0.6), Vector3(0.30, 0.05, 0.16), 10, 5)                 # flippers
			g.ball("dark", Vector3(0.50 * sx, 0.16, -1.35), Vector3(0.03, 0.03, 0.03), 8, 4)                 # eyes
		g.ball("dark", Vector3(0, 0.52, -1.0), Vector3(0.05, 0.02, 0.07), 8, 4)                           # the blowhole
		var mi := MeshInstance3D.new()
		mi.mesh = g.commit(mats)
		mi.position = o
		mi.rotation.y = 0.6
		add_child(mi)
		var body := StaticBody3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(1.3, 1.4, 4.2)
		var col := CollisionShape3D.new()
		col.shape = shape
		col.position = o + Vector3(0, 0.2, 0)
		col.rotation.y = 0.6
		body.add_child(col)
		add_child(body)
		# the spout
		var puff := QuadMesh.new()
		puff.size = Vector2(0.16, 0.16)
		var pm := StandardMaterial3D.new()
		pm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		pm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		pm.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		pm.vertex_color_use_as_albedo = true
		pm.albedo_color = Color(0.85, 0.93, 0.97, 0.55)
		puff.material = pm
		var p := CPUParticles3D.new()
		p.mesh = puff
		p.amount = 220
		p.lifetime = 1.5
		p.direction = Vector3.UP
		p.spread = 9.0
		p.initial_velocity_min = 6.0
		p.initial_velocity_max = 7.2
		p.gravity = Vector3(0, -9.8, 0)
		p.scale_amount_min = 0.6
		p.scale_amount_max = 1.5
		p.position = o + Basis(Vector3.UP, 0.6) * Vector3(0, 0.55, -1.0)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.visibility_range_end = 220.0
		add_child(p)


# ------------------------------------------------------------------ signs by doors
## A small plate on a wall with a name on it: [x, y, z, the way the wall faces x, z, the words].
func _build_door_signs(list: Array) -> void:
	for sg in list:
		var n := Vector3(sg[3], 0, sg[4])
		if sg.size() > 6 and int(sg[6]) == 1:
			_shop_front(sg, n)
			continue
		if sg.size() > 6 and int(sg[6]) == 2:
			_dog_window(sg, n)
			continue
		var at := Vector3(sg[0], sg[1], sg[2]) + n * 0.09
		var text := str(sg[5])
		var wide := 0.012 * float(text.length()) + 0.05
		var plate := BoxMesh.new()
		plate.size = Vector3(wide * 2.0, 0.11, 0.012)
		plate.material = _plain(Color(0.93, 0.92, 0.88), 0.6)
		var mi := MeshInstance3D.new()
		mi.mesh = plate
		mi.transform = Transform3D(Basis(Vector3.UP.cross(n), Vector3.UP, n), at)
		add_child(mi)
		var label := Label3D.new()
		label.text = text
		label.font_size = 64
		label.pixel_size = 0.00075
		label.outline_size = 0
		label.modulate = Color(0.08, 0.08, 0.09)
		label.shaded = false
		label.double_sided = false
		label.transform = Transform3D(Basis(Vector3.UP.cross(n), Vector3.UP, n), at + n * 0.009)
		add_child(label)
## The way in to a shop: glazed double doors in a dark frame, and the shop's name on a red board over them.
func _shop_front(sg: Array, n: Vector3) -> void:
	var along := Vector3.UP.cross(n)
	var ground: float = float(sg[1]) - 1.55
	var at := Vector3(sg[0], ground, sg[2]) + n * 0.10
	var bs := Basis(along, Vector3.UP, n)
	var mb := MB.new()
	mb.box("dark", at + Vector3(0, 1.25, 0), along, Vector3.UP, n, Vector3(1.45, 1.25, 0.06))
	for sgn in [-1.0, 1.0]:
		var sd: float = sgn
		mb.box("glass", at + along * (0.66 * sd) + Vector3(0, 1.2, 0) + n * 0.05, along, Vector3.UP, n, Vector3(0.6, 1.1, 0.03))
	_mats["shop_red"] = _plain(Color(0.80, 0.08, 0.06), 0.5)
	mb.box("shop_red", at + Vector3(0, 3.05, 0) + n * 0.05, along, Vector3.UP, n, Vector3(2.3, 0.42, 0.08))
	_commit(mb, "ShopFront")
	var label := Label3D.new()
	label.text = str(sg[5])
	label.font_size = 150
	label.pixel_size = 0.0042
	label.outline_size = 0
	label.modulate = Color(1.0, 0.86, 0.10)
	label.shaded = false
	label.double_sided = false
	label.transform = Transform3D(bs, at + Vector3(0, 3.05, 0) + n * 0.14)
	add_child(label)


# ------------------------------------------------------------------ statues and playgrounds
## A stone ring standing on edge on a low plinth; and the sand under a playground.
func _build_statues(list: Array, sandpits: Array) -> void:
	var mb := MB.new()
	for pit in sandpits:
		var c := Vector2(pit[0], pit[1])
		var r: float = pit[2]
		for k in 18:
			var a0 := TAU * float(k) / 18.0
			var a1 := TAU * float(k + 1) / 18.0
			var p0 := c + Vector2(cos(a0), sin(a0)) * r
			var p1 := c + Vector2(cos(a1), sin(a1)) * r
			mb.tri("sand", Vector3(c.x, world.height_at(c.x, c.y) + 0.09, c.y), Vector3(p0.x, world.height_at(p0.x, p0.y) + 0.09, p0.y), Vector3(p1.x, world.height_at(p1.x, p1.y) + 0.09, p1.y), Vector3.UP)
	if not mb.surf.is_empty():
		_commit(mb, "Sandpits")
	for st in list:
		if st.get("kind", "") != "donut":
			continue
		var h: float = st["h"]
		var o := Vector3(st["x"], st["y"], st["z"])
		var stone := _textured("concrete", Color(0.62, 0.60, 0.57), 2.0, 0.95)
		var ring := TorusMesh.new()
		ring.outer_radius = h * 0.5
		ring.inner_radius = h * 0.5 - h * 0.30
		ring.rings = 48
		ring.ring_segments = 20
		ring.material = stone
		var mi := MeshInstance3D.new()
		mi.mesh = ring
		mi.position = o + Vector3(0, h * 0.5 + 0.25, 0)
		mi.rotation = Vector3(PI * 0.5, 0.5, 0)
		add_child(mi)
		var base := BoxMesh.new()
		base.size = Vector3(h * 0.5, 0.3, h * 0.28)
		base.material = stone
		var bi := MeshInstance3D.new()
		bi.mesh = base
		bi.position = o + Vector3(0, 0.15, 0)
		bi.rotation.y = 0.5
		add_child(bi)
		_box_body(o + Vector3(0, h * 0.5, 0), Vector2(cos(0.5), -sin(0.5)), Vector3(h, h, h * 0.3))
## A big upstairs window with a dog looking out of it: an English setter, white flecked with liver, its paws
## on the sill, long ears hanging, nose to the glass.
func _dog_window(sg: Array, n: Vector3) -> void:
	var along := Vector3.UP.cross(n)
	var at := Vector3(sg[0], sg[1], sg[2]) + n * 0.06
	var mb := MB.new()
	mb.box("white", at, along, Vector3.UP, n, Vector3(0.98, 0.72, 0.05))                       # the frame
	mb.box("glass", at + n * 0.03, along, Vector3.UP, n, Vector3(0.90, 0.64, 0.03))
	mb.box("white", at + n * 0.05, along, Vector3.UP, n, Vector3(0.015, 0.64, 0.02))          # the bar down the middle
	mb.box("white", at - Vector3(0, 0.74, 0) + n * 0.08, along, Vector3.UP, n, Vector3(1.04, 0.03, 0.10))   # the sill
	_commit(mb, "DogWindow")
	var g = preload("res://scripts/car.gd").Geo.new()
	var mats := {"coat": _plain(Color(0.93, 0.92, 0.88), 0.9), "liver": _plain(Color(0.36, 0.20, 0.12), 0.9), "nose": _plain(Color(0.06, 0.05, 0.05), 0.4),
		"eye": _plain(Color(0.10, 0.06, 0.03), 0.3), "tongue": _plain(Color(0.85, 0.42, 0.45), 0.6)}
	# in the dog's own frame: x across, y up, z out of the window
	g.ball("coat", Vector3(0, -0.36, -0.02), Vector3(0.20, 0.30, 0.16), 14, 8)                 # chest
	g.ball("coat", Vector3(0, -0.10, 0.03), Vector3(0.105, 0.17, 0.10), 12, 6)                 # neck
	g.ball("coat", Vector3(0, 0.07, 0.07), Vector3(0.105, 0.115, 0.12), 14, 8)                 # skull
	g.ball("coat", Vector3(0, 0.03, 0.20), Vector3(0.062, 0.062, 0.115), 12, 6)                # muzzle
	g.ball("liver", Vector3(0.05, 0.12, 0.10), Vector3(0.06, 0.05, 0.07), 10, 5)               # a patch over one eye
	g.ball("nose", Vector3(0, 0.045, 0.312), Vector3(0.026, 0.022, 0.018), 8, 4)
	g.ball("tongue", Vector3(0, -0.035, 0.26), Vector3(0.022, 0.012, 0.045), 8, 4)
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		g.ball("eye", Vector3(0.048 * sx, 0.105, 0.165), Vector3(0.016, 0.016, 0.012), 8, 4)
		g.ball("liver", Vector3(0.115 * sx, 0.0, 0.05), Vector3(0.028, 0.125, 0.065), 10, 6)      # the long ears
		g.ball("coat", Vector3(0.11 * sx, -0.585, 0.10), Vector3(0.045, 0.035, 0.07), 10, 5)      # paws on the sill
		g.tube("coat", [Vector3(0.11 * sx, -0.58, 0.07), Vector3(0.12 * sx, -0.42, 0.02)], 0.036, 8)
	for q in [[0.10, -0.30, 0.10, 0.05], [-0.13, -0.42, 0.06, 0.04], [0.02, -0.52, 0.11, 0.035], [-0.06, -0.20, 0.10, 0.03]]:
		g.ball("liver", Vector3(q[0], q[1], q[2]), Vector3(q[3], q[3], 0.03), 8, 4)                # flecks
	var mi := MeshInstance3D.new()
	mi.mesh = g.commit(mats)
	mi.transform = Transform3D(Basis(along, Vector3.UP, n), at + n * 0.16 - Vector3(0, 0.08, 0))
	add_child(mi)
