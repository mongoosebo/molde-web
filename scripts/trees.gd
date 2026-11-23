extends RefCounted
## The trees as they are seen close by (note of 20 Nov: "more detailed tree models, 5 x polygons, more
## branches, both tree types"). The five kinds scripts/world.gd plants, each about five times the triangles of the
## plain cone-and-ball model it had: a spruce with tiers of drooping boughs round a tapering trunk, a pine with a
## long bare trunk, stubs of dead branches and a crown of flat clumps high up, and three broadleaves (a rounder
## one, a birch, a rowan) whose trunk divides into boughs that carry many clumps of leaves.
## Each is the same height and width as the plain model, which is still what is drawn a little further off
## (shaders/tree.gdshader changes from one to the other by how far the tree is from the camera).
## A model is one surface of triangles with a colour at every corner; it stands on y = 0.

var _v := PackedVector3Array()
var _n := PackedVector3Array()
var _c := PackedColorArray()
var _rng := RandomNumberGenerator.new()


## One triangle. With no normals given it is flat and faces up and away from the trunk. (The front of a triangle
## is the side its corners run clockwise round; they are turned to suit.)
func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, na = null, nb = null, nc = null) -> void:
	var flat := (c - a).cross(b - a).normalized()
	var mid := (a + b + c) / 3.0
	var want: Vector3 = Vector3(mid.x, 0.5 * Vector2(mid.x, mid.z).length() + 0.01, mid.z) if na == null else ((na as Vector3) + (nb as Vector3) + (nc as Vector3))
	if flat.dot(want) < 0.0:
		var keep := b
		b = c
		c = keep
		var keep_n = nb
		nb = nc
		nc = keep_n
		flat = -flat
	_v.append(a); _v.append(b); _v.append(c)
	_n.append(flat if na == null else na); _n.append(flat if nb == null else nb); _n.append(flat if nc == null else nc)
	_c.append(col); _c.append(col); _c.append(col)


## A round, tapering stem along a line of points, as thick at each as `radii` says. Smooth round, open at the foot.
func _stem(pts: Array, radii: Array, col: Color, segs: int, tip := Color(0, 0, 0, 0)) -> void:
	var rings := []
	var ref := Vector3.RIGHT
	for i in pts.size():
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var u := t.cross(ref)
		if u.length_squared() < 0.01:
			u = t.cross(Vector3.BACK)
		u = u.normalized()
		var w := u.cross(t).normalized()
		ref = w
		var ring := []
		for k in segs:
			var a := TAU * float(k) / float(segs)
			ring.append((u * cos(a) + w * sin(a)))
		rings.append(ring)
	for i in pts.size() - 1:
		var c0 := col if tip.a == 0.0 else col.lerp(tip, float(i) / float(pts.size() - 1))
		for k in segs:
			var k2 := (k + 1) % segs
			var a0: Vector3 = pts[i] + rings[i][k] * float(radii[i])
			var a1: Vector3 = pts[i] + rings[i][k2] * float(radii[i])
			var b0: Vector3 = pts[i + 1] + rings[i + 1][k] * float(radii[i + 1])
			var b1: Vector3 = pts[i + 1] + rings[i + 1][k2] * float(radii[i + 1])
			_tri(a0, b0, a1, c0, rings[i][k], rings[i + 1][k], rings[i][k2])
			if float(radii[i + 1]) > 0.001:
				_tri(a1, b0, b1, c0, rings[i][k2], rings[i + 1][k], rings[i + 1][k2])


## A clump of leaves or needles: a ball, pressed or drawn out as `r` says, its surface uneven, darker underneath.
func _clump(at: Vector3, r: Vector3, col: Color, segs := 7, rings := 4) -> void:
	var pts := []
	var nrm := []
	var turn := _rng.randf() * TAU
	for i in rings + 1:
		var lat := PI * float(i) / float(rings)
		var row := []
		var nrow := []
		for k in segs:
			var a := TAU * (float(k) + 0.5 * float(i % 2)) / float(segs) + turn
			var d := Vector3(cos(a) * sin(lat), cos(lat), sin(a) * sin(lat))
			var bump := 1.0 if i == 0 or i == rings else _rng.randf_range(0.82, 1.14)
			row.append(at + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * bump)
			nrow.append(d)
		pts.append(row)
		nrow.resize(segs)
		nrm.append(nrow)
	for i in rings:
		var shade := 0.74 + 0.30 * (1.0 - float(i) / float(rings - 1)) if rings > 1 else 1.0
		var c2 := Color(col.r * shade, col.g * shade, col.b * shade)
		for k in segs:
			var k2 := (k + 1) % segs
			if i > 0:
				_tri(pts[i][k], pts[i][k2], pts[i + 1][k], c2, nrm[i][k], nrm[i][k2], nrm[i + 1][k])
			if i < rings - 1:
				_tri(pts[i][k2], pts[i + 1][k2], pts[i + 1][k], c2, nrm[i][k2], nrm[i + 1][k2], nrm[i + 1][k])


func _commit(material: Material) -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_COLOR] = _c
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, material)
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_c = PackedColorArray()
	return mesh


## A bough of a conifer: a flat spray of needles from the trunk out and down, with a ridge along its middle.
func _spray(from: Vector3, out: Vector3, length: float, droop: float, wide: float, col: Color) -> void:
	var side := Vector3.UP.cross(out).normalized()
	var mid := from + out * (length * 0.55) + Vector3(0, -droop * 0.40, 0)
	var tip := from + out * length + Vector3(0, -droop, 0)
	var l := mid + side * wide + Vector3(0, -wide * 0.35, 0)
	var r := mid - side * wide + Vector3(0, -wide * 0.35, 0)
	var dark := Color(col.r * 0.78, col.g * 0.78, col.b * 0.78)
	_tri(from, l, mid + Vector3(0, wide * 0.18, 0), col)
	_tri(from, mid + Vector3(0, wide * 0.18, 0), r, col)
	_tri(l, tip, mid + Vector3(0, wide * 0.18, 0), dark)
	_tri(mid + Vector3(0, wide * 0.18, 0), tip, r, dark)


## 0: a spruce, 7.9 m to its top and 1.9 m to the tips of its lowest boughs.
func spruce(material: Material) -> ArrayMesh:
	_rng.seed = 101
	var bark := Color(0.23, 0.17, 0.12)
	_stem([Vector3(0, 0, 0), Vector3(0.01, 2.0, 0), Vector3(0, 5.0, 0.01), Vector3(0, 7.2, 0), Vector3(0, 7.9, 0)], [0.21, 0.15, 0.09, 0.035, 0.0], bark, 7)
	var tiers := 8
	for t in tiers:
		var f := float(t) / float(tiers - 1)                      # 0 at the lowest tier, 1 at the top
		var y := lerpf(1.55, 7.15, f)
		var reach := lerpf(1.90, 0.42, pow(f, 0.85))
		var boughs := 9 if t < 5 else (7 if t < 7 else 5)
		var col := Color(0.12, 0.22, 0.14).lerp(Color(0.15, 0.27, 0.17), f)
		for k in boughs:
			var a := TAU * (float(k) + 0.5 * float(t % 2)) / float(boughs) + _rng.randf_range(-0.12, 0.12)
			var out := Vector3(cos(a), 0, sin(a))
			var ln := reach * _rng.randf_range(0.86, 1.06)
			var tint := _rng.randf_range(0.90, 1.10)
			_spray(Vector3(0, y + _rng.randf_range(-0.08, 0.08), 0) + out * 0.05, out, ln, ln * lerpf(0.42, 0.25, f), ln * lerpf(0.30, 0.36, f), Color(col.r * tint, col.g * tint, col.b * tint))
		# the body of needles close to the trunk, so that the tree is not seen through between the boughs
		var skirt := 6
		for k in skirt:
			var a0 := TAU * float(k) / float(skirt)
			var a1 := TAU * float(k + 1) / float(skirt)
			var low := y - reach * 0.50
			_tri(Vector3(0, y + 0.55, 0), Vector3(cos(a1), 0, sin(a1)) * reach * 0.58 + Vector3(0, low, 0), Vector3(cos(a0), 0, sin(a0)) * reach * 0.58 + Vector3(0, low, 0),
				Color(col.r * 0.72, col.g * 0.72, col.b * 0.72))
	return _commit(material)


## 2: a pine, 8.4 m: the trunk bare and red-brown, dead stubs on it, the crown in flat clumps high up.
func pine(material: Material) -> ArrayMesh:
	_rng.seed = 202
	var low := Color(0.36, 0.22, 0.15)
	var high := Color(0.62, 0.33, 0.17)
	var trunk := [Vector3(0, 0, 0), Vector3(0.03, 2.0, 0.02), Vector3(-0.02, 4.2, 0.04), Vector3(0.05, 5.8, 0.0), Vector3(0.0, 7.0, -0.03)]
	_stem(trunk, [0.20, 0.16, 0.13, 0.10, 0.05], low, 7, high)
	for q in [[2.6, 0.6], [3.5, 2.5], [4.3, 4.4]]:
		var a: float = q[1]
		_stem([Vector3(0, q[0], 0), Vector3(cos(a), 0.25, sin(a)) * 0.55 + Vector3(0, q[0], 0)], [0.035, 0.012], Color(0.30, 0.26, 0.23), 4)
	var boughs := 6
	for k in boughs:
		var a2 := TAU * float(k) / float(boughs) + _rng.randf_range(-0.2, 0.2)
		var y := 5.3 + 0.38 * float(k % 3) + _rng.randf_range(-0.1, 0.1)
		var out := Vector3(cos(a2), 0, sin(a2))
		var reach := _rng.randf_range(0.85, 1.25)
		var end := Vector3(0, y + 0.50, 0) + out * reach
		_stem([Vector3(0, y, 0), Vector3(0, y + 0.18, 0) + out * (reach * 0.5), end], [0.06, 0.04, 0.02], high, 5)
		var g := Color(0.13, 0.25, 0.16).lerp(Color(0.16, 0.29, 0.18), _rng.randf())
		_clump(end + Vector3(0, 0.12, 0), Vector3(0.62, 0.36, 0.62), g)
		_clump(end + out * 0.38 + Vector3(0, -0.02, 0), Vector3(0.44, 0.27, 0.44), g, 6, 3)
	for q2 in [[0.0, 7.55, 0.0, 0.80], [0.45, 7.05, 0.3, 0.60], [-0.4, 7.15, -0.35, 0.58], [0.1, 6.55, -0.5, 0.55]]:
		_clump(Vector3(q2[0], q2[1], q2[2]), Vector3(q2[3], float(q2[3]) * 0.62, q2[3]), Color(0.15, 0.27, 0.17))
	return _commit(material)


## A broadleaf: the trunk to where it divides, boughs up and out from there (each with a side branch), and clumps
## of leaves on them. `spec`: tall (to the top of the crown), fork (where the trunk divides), trunk (its radius at
## the foot), wide (the crown's radius), boughs, bark, bark_mark (bands of another colour on the trunk: a birch),
## leaves (two colours the clumps lie between), hang (how much the outer clumps are drawn out downward: a birch),
## berries (a colour, or null), clump (the size of a clump).
func _broadleaf(spec: Dictionary, material: Material) -> ArrayMesh:
	var tall: float = spec["tall"]
	var fork: float = spec["fork"]
	var r0: float = spec["trunk"]
	var wide: float = spec["wide"]
	var bark: Color = spec["bark"]
	var la: Color = spec["leaves"][0]
	var lb: Color = spec["leaves"][1]
	var size: float = spec["clump"]
	var lean := Vector3(_rng.randf_range(-0.05, 0.05), 0, _rng.randf_range(-0.05, 0.05))
	var top_of_trunk := Vector3(lean.x * fork, fork, lean.z * fork)
	if spec.has("bark_mark"):
		# a birch: the white trunk in short lengths, every other one a little darker, black at the foot
		var parts := 9
		for i in parts:
			var f0 := float(i) / float(parts)
			var f1 := float(i + 1) / float(parts)
			var c := (spec["bark_mark"] as Color) if (i == 0 or i % 3 == 2) else bark
			_stem([top_of_trunk * f0, top_of_trunk * f1], [lerpf(r0, r0 * 0.62, f0), lerpf(r0, r0 * 0.62, f1)], c if i > 0 else Color(0.16, 0.15, 0.14), 6)
	else:
		_stem([Vector3.ZERO, top_of_trunk * 0.5 + Vector3(0.03, 0, -0.02), top_of_trunk], [r0, r0 * 0.78, r0 * 0.62], bark, 7)
	var boughs: int = spec["boughs"]
	var crown_mid := (fork + tall) * 0.5 + (tall - fork) * 0.08
	for k in boughs:
		var a := TAU * float(k) / float(boughs) + _rng.randf_range(-0.25, 0.25)
		var out := Vector3(cos(a), 0, sin(a))
		var steep := 0.25 if k == 0 else _rng.randf_range(0.55, 1.0)         # (the first goes on nearly straight up: the leader)
		var rise := (tall - fork) * (0.80 if k == 0 else _rng.randf_range(0.42, 0.66))
		var reach := wide * steep * 0.82
		var knee := top_of_trunk + out * (reach * 0.45) + Vector3(0, rise * 0.50, 0)
		var end := top_of_trunk + out * reach + Vector3(0, rise, 0)
		_stem([top_of_trunk - Vector3(0, 0.15, 0), knee, end], [r0 * 0.50, r0 * 0.30, r0 * 0.10], bark, 5)
		# a side branch from the knee, the other way round the tree
		var a2 := a + (1.1 if k % 2 == 0 else -1.1)
		var out2 := Vector3(cos(a2), 0, sin(a2))
		var end2 := knee + out2 * (wide * 0.42) + Vector3(0, rise * 0.22, 0)
		_stem([knee, end2], [r0 * 0.24, r0 * 0.07], bark, 4)
		# leaves: a clump at the end of each, one between, and one out at the side
		for q in [[end, 1.0], [end2, 0.85], [knee.lerp(end, 0.55) + out * (size * 0.5), 0.9], [end + out * (size * 0.75) + Vector3(0, -size * 0.35, 0), 0.72]]:
			var at: Vector3 = q[0]
			var sc: float = float(q[1]) * size * _rng.randf_range(0.88, 1.12)
			var edge := clampf(Vector2(at.x, at.z).length() / wide, 0.0, 1.0)
			var hang: float = float(spec.get("hang", 0.0)) * edge
			var col := la.lerp(lb, _rng.randf())
			_clump(at + Vector3(0, -hang * sc * 0.5, 0), Vector3(sc, sc * (0.78 + hang), sc), col)
	# the middle of the crown, and its top
	_clump(Vector3(top_of_trunk.x, crown_mid, top_of_trunk.z), Vector3(wide * 0.62, (tall - fork) * 0.36, wide * 0.62), la.lerp(lb, 0.3), 8, 5)
	_clump(Vector3(top_of_trunk.x * 1.2, tall - size * 0.62, top_of_trunk.z * 1.2), Vector3(size * 0.95, size * 0.62, size * 0.95), lb)
	if spec.get("berries") != null:
		for k in 7:
			var a3 := _rng.randf() * TAU
			var rr := wide * _rng.randf_range(0.55, 0.95)
			_clump(Vector3(cos(a3) * rr, _rng.randf_range(fork + 0.4, tall - 0.6), sin(a3) * rr), Vector3(0.20, 0.15, 0.20), spec["berries"], 5, 3)
	return _commit(material)


## 1: the rounder broadleaf, 7.7 m.
func broadleaf(material: Material) -> ArrayMesh:
	_rng.seed = 303
	return _broadleaf({"tall": 7.7, "fork": 2.9, "trunk": 0.19, "wide": 2.15, "boughs": 5, "bark": Color(0.30, 0.24, 0.18),
		"leaves": [Color(0.17, 0.29, 0.12), Color(0.25, 0.38, 0.16)], "clump": 1.02}, material)


## 3: a birch, 7.8 m: slender and white, its crown light and hanging.
func birch(material: Material) -> ArrayMesh:
	_rng.seed = 404
	return _broadleaf({"tall": 7.8, "fork": 3.4, "trunk": 0.13, "wide": 1.65, "boughs": 5, "bark": Color(0.86, 0.86, 0.82), "bark_mark": Color(0.70, 0.70, 0.67),
		"leaves": [Color(0.33, 0.45, 0.19), Color(0.42, 0.53, 0.23)], "hang": 0.55, "clump": 0.78}, material)


## 4: a rowan, 4.6 m: small, with clusters of red berries.
func rowan(material: Material) -> ArrayMesh:
	_rng.seed = 505
	return _broadleaf({"tall": 4.6, "fork": 1.6, "trunk": 0.10, "wide": 1.45, "boughs": 4, "bark": Color(0.34, 0.30, 0.27),
		"leaves": [Color(0.26, 0.36, 0.14), Color(0.31, 0.40, 0.15)], "berries": Color(0.60, 0.14, 0.08), "clump": 0.72}, material)
