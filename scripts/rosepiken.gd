extends RefCounted
## Rosepiken, the rose maiden on Rådhusplassen (Ragnhild Butenschøn, 1971), after photographs of her (note of
## 20 Nov: "make Rosepiken 10 x detail, look for reference pictures"): a slim girl in bronze, bare above a
## short wrap skirt, short curly hair, holding a wide shallow basket of roses in front of her with both hands.
## She stands on a low island of dark stone in the middle of a square basin with a broad rim of pebbled
## concrete, and jets of water rise round her to the height of her shoulders.
## Everything here is built round the middle of the basin, on y = 0 (the paving), the girl facing +Z.

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo)

const HALF := 2.9             # the basin, from its middle to the outside of its rim
const RIM := 0.5              # how broad the rim is
const RIM_H := 0.42
const WATER := 0.30
const ISLAND := 1.3           # the island, from its middle to its edge
const ISLAND_H := 0.40


static func _mat(c: Color, rough: float, metal := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	m.metallic = metal
	return m


## A limb: a round body along a line of points, as thick at each as `radii` says, closed at both ends.
static func _limb(g, m: String, pts: Array, radii: Array, segs := 10) -> void:
	var rows := []
	var ref := Vector3.BACK
	for i in pts.size():
		var t: Vector3 = (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var u := t.cross(ref)
		if u.length_squared() < 0.01:
			u = t.cross(Vector3.RIGHT)
		u = u.normalized()
		var v := t.cross(u).normalized()
		ref = v * -1.0 if v.dot(ref) < 0.0 else v
		var ring := PackedVector3Array()
		for k in segs:
			var a := TAU * float(k) / float(segs)
			ring.append(pts[i] + (u * cos(a) + v * sin(a)) * float(radii[i]))
		rows.append(ring)
	g.skin(rows, true, m)
	g.cap(m, rows[0], pts[0] - pts[1])
	g.cap(m, rows[-1], pts[-1] - pts[-2])


## The girl and her basket, her feet on y = 0.
static func _girl(g) -> void:
	var b := "bronze"
	g.box(b, Vector3(0, 0.012, 0.02), Vector3(0.21, 0.012, 0.17))                                    # the plate she is cast on
	var y0 := 0.024
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		# a foot, the leg from the ankle over the calf and the knee to the hip (her weight on the left leg)
		g.ball(b, Vector3(0.075 * sx, y0 + 0.030, 0.045), Vector3(0.040, 0.030, 0.105), 10, 5)
		g.ball(b, Vector3(0.075 * sx, y0 + 0.045, -0.030), Vector3(0.034, 0.045, 0.045), 8, 4)         # the heel
		var knee := Vector3(0.078 * sx, y0 + 0.50, 0.012 if sx < 0.0 else 0.035)
		_limb(g, b, [Vector3(0.075 * sx, y0 + 0.05, -0.010), Vector3(0.075 * sx, y0 + 0.10, -0.012), Vector3(0.077 * sx, y0 + 0.30, -0.020), Vector3(0.078 * sx, y0 + 0.42, 0.0), knee,
			Vector3(0.082 * sx, y0 + 0.70, 0.010), Vector3(0.088 * sx, y0 + 0.90, 0.0)], [0.030, 0.027, 0.047, 0.040, 0.043, 0.058, 0.070])
		g.ball(b, knee + Vector3(0, 0.0, 0.030), Vector3(0.030, 0.035, 0.020), 8, 4)                  # the kneecap
	# the skirt: wrapped, to just over the knee, wider at the hem, with the edge of the wrap down the front
	var hem := y0 + 0.58
	var rows := []
	for q in [[0.0, 0.205, 0.175], [0.10, 0.195, 0.165], [0.24, 0.170, 0.140], [0.36, 0.142, 0.112], [0.44, 0.122, 0.095], [0.47, 0.118, 0.090]]:
		var ring := PackedVector3Array()
		for k in 20:
			var a := TAU * float(k) / 20.0
			var fold := 1.0 + 0.045 * sin(a * 7.0) * (1.0 - float(q[0]) / 0.47)                        # the cloth falls in folds, most at the hem
			ring.append(Vector3(cos(a) * float(q[1]) * fold, hem + float(q[0]), sin(a) * float(q[2]) * fold))
		rows.append(ring)
	g.skin(rows, true, b)
	g.cap(b, rows[0], Vector3.DOWN)
	_limb(g, b, [Vector3(0.05, hem + 0.01, 0.178), Vector3(0.04, hem + 0.25, 0.142), Vector3(0.02, hem + 0.46, 0.094)], [0.012, 0.011, 0.010], 6)
	g.lathe(b, Vector3(0, hem + 0.455, 0), Vector3.UP, [Vector2(0.121, 0.0), Vector2(0.126, 0.012), Vector2(0.121, 0.03)], 20)      # the waistband
	# the body: the belly, the ribs and chest, small breasts, the shoulders, the collar bones
	var wy := hem + 0.47
	g.ball(b, Vector3(0, wy + 0.06, 0.0), Vector3(0.112, 0.13, 0.085), 14, 7)
	g.ball(b, Vector3(0, wy + 0.24, -0.005), Vector3(0.140, 0.17, 0.092), 16, 8)
	g.ball(b, Vector3(0, wy + 0.355, -0.01), Vector3(0.172, 0.070, 0.078), 14, 6)
	for sgn2 in [-1.0, 1.0]:
		var s2: float = sgn2
		g.ball(b, Vector3(0.060 * s2, wy + 0.270, 0.066), Vector3(0.038, 0.036, 0.024), 10, 5)
		g.ball(b, Vector3(0.150 * s2, wy + 0.372, -0.008), Vector3(0.046, 0.040, 0.044), 10, 5)
		_limb(g, b, [Vector3(0.02 * s2, wy + 0.405, 0.045), Vector3(0.15 * s2, wy + 0.40, 0.020)], [0.010, 0.012], 6)
		# an arm: out from the shoulder, the elbow a little out from her side, the forearm forward to the basket's rim
		var sh := Vector3(0.160 * s2, wy + 0.365, -0.008)
		var el := Vector3(0.235 * s2, wy + 0.11, -0.010)
		var hand := Vector3(0.255 * s2, wy + 0.035, 0.225)
		_limb(g, b, [sh, sh.lerp(el, 0.5) + Vector3(0.008 * s2, 0, 0), el], [0.040, 0.037, 0.031])
		g.ball(b, el, Vector3(0.032, 0.032, 0.032), 8, 4)
		_limb(g, b, [el, el.lerp(hand, 0.45), hand], [0.031, 0.030, 0.022])
		g.ball(b, hand + Vector3(-0.012 * s2, 0.0, 0.035), Vector3(0.026, 0.020, 0.048), 8, 4)          # the hand, on the rim
		for f in 4:
			_limb(g, b, [hand + Vector3(-0.020 * s2, 0.012, 0.045 + 0.012 * float(f)), hand + Vector3(-0.050 * s2, 0.004, 0.050 + 0.014 * float(f)),
				hand + Vector3(-0.062 * s2, -0.022, 0.052 + 0.014 * float(f))], [0.008, 0.007, 0.006], 5)   # the fingers over it
	# the neck, the head a little bowed toward the roses, the face, the ears
	_limb(g, b, [Vector3(0, wy + 0.39, -0.012), Vector3(0, wy + 0.45, -0.004), Vector3(0, wy + 0.50, 0.006)], [0.050, 0.038, 0.039])
	var hc := Vector3(0, wy + 0.580, 0.018)
	g.ball(b, hc, Vector3(0.078, 0.100, 0.090), 16, 9)
	g.ball(b, hc + Vector3(0, -0.052, 0.028), Vector3(0.052, 0.048, 0.056), 12, 6)                    # the jaw and chin
	_limb(g, b, [hc + Vector3(0, 0.020, 0.086), hc + Vector3(0, -0.022, 0.098)], [0.008, 0.013], 6)     # the nose
	g.ball(b, hc + Vector3(0, -0.048, 0.080), Vector3(0.015, 0.004, 0.006), 8, 3)                     # the mouth
	for sgn3 in [-1.0, 1.0]:
		var s3: float = sgn3
		g.ball(b, hc + Vector3(0.030 * s3, 0.010, 0.080), Vector3(0.011, 0.005, 0.005), 8, 3)         # the eyes, under the brows
		g.ball(b, hc + Vector3(0.078 * s3, -0.005, 0.0), Vector3(0.010, 0.022, 0.015), 6, 3)
	# the hair: short, a cap of it over the skull, and curls all round and over the top
	g.ball(b, hc + Vector3(0, 0.028, -0.018), Vector3(0.090, 0.092, 0.098), 16, 8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1971
	for k in 46:
		var a2 := rng.randf() * TAU
		var up := rng.randf_range(-0.15, 1.0)
		if sin(a2) > 0.55 and up < 0.45:
			continue                                                                                # (not over the face)
		var ring_r := sqrt(maxf(1.0 - up * up, 0.0))
		var cp := hc + Vector3(0, 0.030, -0.018) + Vector3(cos(a2) * ring_r * 0.092, up * 0.094, sin(a2) * ring_r * 0.100)
		g.ball(b, cp, Vector3.ONE * rng.randf_range(0.020, 0.030), 7, 4)
	# the basket: wide and shallow, woven (rings round it), held in front of her at the waist, full of roses
	var bc := Vector3(0.0, wy + 0.01, 0.245)
	g.lathe(b, bc, Vector3.UP, [Vector2(0.0, -0.035), Vector2(0.17, -0.035), Vector2(0.255, 0.018), Vector2(0.275, 0.050), Vector2(0.262, 0.056), Vector2(0.235, 0.030), Vector2(0.0, 0.020)], 22)
	for k in 4:
		g.lathe(b, bc, Vector3.UP, [Vector2(0.185 + 0.024 * float(k), -0.030 + 0.020 * float(k)), Vector2(0.192 + 0.024 * float(k), -0.020 + 0.020 * float(k)), Vector2(0.186 + 0.024 * float(k), -0.012 + 0.020 * float(k))], 22)
	for k in 34:
		var a3 := rng.randf() * TAU
		var rr := sqrt(rng.randf()) * 0.215
		var rp := bc + Vector3(cos(a3) * rr, 0.045 + rng.randf() * 0.03 + (0.215 - rr) * 0.16, sin(a3) * rr * 0.92)
		var size := rng.randf_range(0.026, 0.038)
		var kind := "rose_red" if k % 6 == 0 else ("rose_pale" if k % 6 == 3 else b)                    # (a few real ones are always laid among hers)
		g.ball(kind, rp, Vector3(size, size * 0.8, size), 8, 4)
		g.ball(kind, rp + Vector3(0, size * 0.55, 0), Vector3(size * 0.55, size * 0.5, size * 0.55), 6, 3)   # the bud in the middle of the bloom
		if k % 3 == 0:
			g.ball(b, rp + Vector3(cos(a3 + 1.0) * size * 1.2, -size * 0.3, sin(a3 + 1.0) * size * 1.2), Vector3(size * 0.9, 0.006, size * 0.5), 6, 3)   # a leaf


## The basin, the island, the water and the jets. Returns the mesh; `tall` is how high the girl's head reaches.
static func build() -> ArrayMesh:
	var g = Shapes.Geo.new()
	var inner := HALF - RIM
	# the rim: four broad beams of pebbled concrete, their top a little rounded off at the edges
	for k in 4:
		var bs := Basis(Vector3.UP, PI * 0.5 * float(k))
		g.box("pebble", bs * Vector3(0, RIM_H * 0.5 - 0.15, HALF - RIM * 0.5), Vector3(HALF if k % 2 == 0 else HALF - RIM, RIM_H * 0.5 + 0.15, RIM * 0.5), bs)
		g.box("pebble_dark", bs * Vector3(0, RIM_H + 0.004, HALF - RIM * 0.5), Vector3(HALF - 0.04 if k % 2 == 0 else HALF - RIM, 0.004, RIM * 0.5 - 0.04), bs)
	# the floor of the basin, dark under the water, and the water
	g.box("stone", Vector3(0, 0.02, 0), Vector3(inner, 0.02, inner))
	g.quad("water", Vector3(-inner, WATER, -inner), Vector3(inner, WATER, -inner), Vector3(inner, WATER, inner), Vector3(-inner, WATER, inner), Vector3.UP)
	# the island: a slab of dark stone just over the water, on a narrower foot, and a second step under her feet
	g.box("stone", Vector3(0, ISLAND_H * 0.5 - 0.06, 0), Vector3(ISLAND - 0.18, ISLAND_H * 0.5 - 0.06, ISLAND - 0.18))
	g.box("stone_wet", Vector3(0, ISLAND_H - 0.06, 0), Vector3(ISLAND, 0.06, ISLAND))
	g.box("stone_wet", Vector3(0, ISLAND_H + 0.03, 0.05), Vector3(0.46, 0.03, 0.40))
	# the jets: nozzles in the island beside and behind her, each a thin column that widens and breaks into drops
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	for q in [[-0.95, 0.35, 1.25], [-1.0, -0.15, 1.45], [-0.75, -0.65, 1.35], [-0.25, -0.95, 1.55], [0.35, -0.95, 1.40], [0.80, -0.60, 1.50], [1.0, -0.10, 1.30], [0.92, 0.40, 1.15], [-0.55, 0.85, 0.9], [0.55, 0.85, 0.95]]:
		var foot := Vector3(q[0], ISLAND_H, q[1])
		var top: float = q[2]
		g.cyl("bronze", foot + Vector3(0, 0.03, 0), Vector3.UP, 0.022, 0.03, 8)
		g.lathe("spray", foot, Vector3.UP, [Vector2(0.012, 0.05), Vector2(0.020, top * 0.45), Vector2(0.045, top * 0.80), Vector2(0.075, top * 0.97), Vector2(0.04, top), Vector2(0.0, top)], 8)
		for d in 16:
			var a := rng.randf() * TAU
			var out := rng.randf_range(0.03, 0.20)
			var hy := top * rng.randf_range(0.25, 1.0)
			var sz := rng.randf_range(0.012, 0.028)
			g.ball("spray", foot + Vector3(cos(a) * out, hy, sin(a) * out), Vector3(sz, sz * 1.6, sz), 5, 3)
		g.lathe("foam", foot + Vector3(0, 0.002, 0), Vector3.UP, [Vector2(0.0, 0.001), Vector2(0.28, 0.001)], 10)          # the wet ring where it falls back
	# a ring of foam on the water round the island
	g.lathe("foam", Vector3(0, WATER + 0.004, 0), Vector3.UP, [Vector2(ISLAND * 1.2, 0.001), Vector2(ISLAND * 1.55, 0.001)], 4)
	var girl = Shapes.Geo.new()
	_girl(girl)
	var mats := {"bronze": _mat(Color(0.21, 0.19, 0.13), 0.5, 0.65), "rose_red": _mat(Color(0.62, 0.06, 0.10), 0.8), "rose_pale": _mat(Color(0.90, 0.72, 0.74), 0.8),
		"pebble": _mat(Color(0.52, 0.49, 0.44), 0.95), "pebble_dark": _mat(Color(0.45, 0.42, 0.38), 0.95), "stone": _mat(Color(0.13, 0.12, 0.11), 0.6),
		"stone_wet": _mat(Color(0.17, 0.14, 0.12), 0.18), "water": _mat(Color(0.07, 0.15, 0.15, 0.82), 0.04, 0.4), "spray": _mat(Color(0.93, 0.96, 0.98, 0.55), 0.3),
		"foam": _mat(Color(0.85, 0.90, 0.92, 0.35), 0.4)}
	for k2 in ["water", "spray", "foam"]:
		(mats[k2] as StandardMaterial3D).transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	(mats["spray"] as StandardMaterial3D).shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	# she is cast a little over life size (1.9 m), and stands on the island's upper step
	var mesh: ArrayMesh = g.commit(mats)
	var figure: ArrayMesh = girl.commit(mats)
	var lift := Transform3D(Basis().scaled(Vector3.ONE * 1.12), Vector3(0, ISLAND_H + 0.06, 0.05))
	for s in figure.get_surface_count():
		var arrays := figure.surface_get_arrays(s)
		var vs: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for i in vs.size():
			vs[i] = lift * vs[i]
		arrays[Mesh.ARRAY_VERTEX] = vs
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, figure.surface_get_material(s))
	return mesh
