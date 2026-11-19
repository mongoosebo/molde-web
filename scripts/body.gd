extends RefCounted
## The human figure: one way of building a body, shared by the player and by the people of the town.
##
## A body is a set of parts (torso, head, thigh, shin, boot, upper arm, forearm with its hand), each a smooth
## skin of rings. `make(spec, colours)` puts a figure together on joints (hips, knees, ankles, shoulders,
## elbows) and returns them. The parts are built once for each shape that is asked for and then shared by every
## figure of that shape: what differs between two people of one shape is only their colours (each figure
## has its own materials laid over the shared mesh), their height, and how thick their limbs are.
##
## spec: {"sex": "m" | "f", "build": 0 slim | 1 medium | 2 heavy, "hair": "short" | "bald" | "bob" | "long" |
##        "tail" | "cap", "helmet": bool, "detail": 1.0 (how finely it is cut: 0.84 gives 70 % of the triangles),
##        "far": 0.0 (a second, coarse cut for when it is far off) and "lod": the distance where that takes over}
## Faces -Z. All limbs hang straight down (-Y) at rest; rotation.x swings a limb forward, a hinge bends about X.

const Shapes := preload("res://scripts/car.gd")       # for its shape builder (Geo): smooth skins, tubes, balls

const THIGH := 0.46
const SHIN := 0.42
const UPPER_ARM := 0.33
const FOREARM := 0.31
const HIP := Vector3(0.12, 0.95, 0.0)

## The stride: hip, knee and ankle through one step, twelve moments from one heel strike to the next of the same foot.
const WALK := {"hip": [0.40, 0.33, 0.22, 0.10, -0.03, -0.17, -0.29, -0.30, -0.10, 0.18, 0.40, 0.45],
	"knee": [0.06, 0.24, 0.18, 0.09, 0.06, 0.10, 0.30, 0.72, 1.08, 0.95, 0.45, 0.10],
	"ankle": [0.05, -0.12, 0.0, 0.08, 0.14, 0.18, 0.05, -0.32, -0.20, -0.02, 0.06, 0.08]}
const SPRINT := {"hip": [0.62, 0.40, 0.12, -0.18, -0.45, -0.62, -0.50, -0.10, 0.45, 0.90, 1.02, 0.85],
	"knee": [0.42, 0.62, 0.50, 0.35, 0.28, 0.55, 1.25, 1.90, 2.05, 1.60, 0.95, 0.50],
	"ankle": [0.10, 0.22, 0.15, -0.10, -0.42, -0.50, -0.30, -0.10, 0.05, 0.10, 0.10, 0.10]}

## What the player wears and looks like; a figure's own colours are laid over these.
const COLOURS := {
	"jacket": Color(0.52, 0.37, 0.20), "jacket_dark": Color(0.38, 0.27, 0.15), "cord": Color(0.22, 0.15, 0.10), "shirt": Color(0.20, 0.21, 0.23),
	"jeans": Color(0.16, 0.23, 0.37), "jeans_dark": Color(0.10, 0.15, 0.26), "skin": Color(0.86, 0.70, 0.60), "stubble": Color(0.72, 0.58, 0.50),
	"lip": Color(0.78, 0.57, 0.52), "hair_edge": Color(0.52, 0.39, 0.30), "shade": Color(0.74, 0.58, 0.49), "boot": Color(0.74, 0.55, 0.29),
	"boot_dark": Color(0.23, 0.16, 0.10), "sole_tan": Color(0.60, 0.44, 0.25), "sole": Color(0.05, 0.05, 0.05), "lace": Color(0.62, 0.47, 0.27),
	"dark": Color(0.05, 0.04, 0.04), "white": Color(0.93, 0.93, 0.91), "blue": Color(0.22, 0.48, 0.80), "metal": Color(0.70, 0.58, 0.32),
	"hair": Color(0.25, 0.16, 0.09), "patch": Color(0.93, 0.92, 0.88), "orange": Color(0.90, 0.45, 0.10), "hat": Color(0.20, 0.22, 0.30),
	"helmet": Color(0.95, 0.80, 0.10), "band": Color(0.80, 0.82, 0.84),
}
const ROUGH := {"jacket": 0.95, "jacket_dark": 0.95, "cord": 1.0, "skin": 0.65, "stubble": 0.8, "lip": 0.6, "hair_edge": 0.85, "shade": 0.7, "boot": 0.98,
	"dark": 0.5, "white": 0.4, "blue": 0.3, "metal": 0.4, "helmet": 0.35, "band": 0.3}

static var _parts := {}           # what has been built: key -> {"mesh": ArrayMesh, "names": Array of surface names, "count": triangles}


## The value of one of the stride's curves at a moment of it (t from 0 to 1, round and round), smoothly between its twelve.
static func stride(curve: Array, t: float) -> float:
	var x := fposmod(t, 1.0) * 12.0
	var i := int(x)
	var f := x - float(i)
	var p0: float = curve[(i + 11) % 12]
	var p1: float = curve[i % 12]
	var p2: float = curve[(i + 1) % 12]
	var p3: float = curve[(i + 2) % 12]
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * f + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * f * f + (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * f * f * f)


## Materials for a figure: the player's colours with this figure's own laid over them.
static func materials(own := {}) -> Dictionary:
	var out := {}
	for k in COLOURS:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = own.get(k, COLOURS[k])
		mat.roughness = ROUGH.get(k, 0.9)
		out[k] = mat
	return out


## How far out from the middle the shoulder joint is, for a spec.
static func shoulder(spec: Dictionary) -> Vector3:
	return Vector3(0.250 * (0.86 if spec.get("sex", "m") == "f" else 1.0), 1.515, 0.0)


# ------------------------------------------------------------------ rings
static func _n(base: int, d: float) -> int:
	return maxi(8, int(round(float(base) * d * 0.5)) * 2)


static func _s(base: int, d: float) -> int:
	return maxi(1, int(round(float(base) * d)))


## A ring of points round a limb or the body, in the plane across it at height y: an oval, or squarer (sq < 1).
static func _oval(y: float, rx: float, rz: float, n := 12, cz := 0.0, sq := 1.0) -> PackedVector3Array:
	var ring := PackedVector3Array()
	for k in n:
		var a := TAU * float(k) / float(n)
		var cs := cos(a)
		var sn := sin(a)
		ring.append(Vector3(rx * signf(cs) * pow(absf(cs), sq), y, cz + rz * signf(sn) * pow(absf(sn), sq)))
	return ring


## Rings round a limb or the body at many heights, from a few key rows [y, rx, rz, cz, sq] (the last two may be
## left out: 0 and 1). Between the keys the widths are rounded off, so the shape curves from one to the next
## instead of running in straight cones, and `sub` rings are laid for every key: that is where the smoothness
## (and most of the triangles) comes from.
static func _rings(keys: Array, n: int, sub: int) -> Array:
	var full := []
	for q in keys:
		full.append([q[0], q[1], q[2], q[3] if q.size() > 3 else 0.0, q[4] if q.size() > 4 else 1.0])
	var rows := []
	for i in full.size() - 1:
		var k0: Array = full[maxi(i - 1, 0)]
		var k1: Array = full[i]
		var k2: Array = full[i + 1]
		var k3: Array = full[mini(i + 2, full.size() - 1)]
		for st in sub:
			var t := float(st) / float(sub)
			var v := []
			for c in 5:
				if c == 0:
					v.append(lerpf(k1[0], k2[0], t))
				else:
					v.append(0.5 * ((2.0 * k1[c]) + (-k0[c] + k2[c]) * t + (2.0 * k0[c] - 5.0 * k1[c] + 4.0 * k2[c] - k3[c]) * t * t
						+ (-k0[c] + 3.0 * k1[c] - 3.0 * k2[c] + k3[c]) * t * t * t))
			rows.append(_oval(v[0], maxf(v[1], 0.002), maxf(v[2], 0.002), n, v[3], clampf(v[4], 0.4, 1.0)))
	var last: Array = full[-1]
	rows.append(_oval(last[0], last[1], last[2], n, last[3], last[4]))
	return rows


static func _keep(key: String, g, shift := Vector3.ZERO) -> Dictionary:
	var mesh := ArrayMesh.new()
	var names := []
	for m in g.surf:
		if shift != Vector3.ZERO:
			var pts: PackedVector3Array = g.surf[m][0]
			for i in pts.size():
				pts[i] += shift
			g.surf[m][0] = pts
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = g.surf[m][0]
		arrays[Mesh.ARRAY_NORMAL] = g.surf[m][1]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		names.append(m)
	_parts[key] = {"mesh": mesh, "names": names, "count": g.count()}
	return _parts[key]


# ------------------------------------------------------------------ the parts
static func _thigh(d: float) -> Dictionary:
	var key := "thigh %.2f" % d
	if _parts.has(key):
		return _parts[key]
	var g = Shapes.Geo.new()
	var rows := _rings([[0.03, 0.070, 0.082], [0.0, 0.089, 0.102], [-0.10, 0.095, 0.107], [-0.25, 0.086, 0.094], [-0.38, 0.073, 0.080],
		[-THIGH, 0.068, 0.074], [-THIGH - 0.03, 0.060, 0.066]], _n(44, d), _s(6, d))
	g.skin(rows, true, "jeans")
	g.cap("jeans", rows[0], Vector3.UP)
	return _keep(key, g)


static func _shin(d: float) -> Dictionary:
	var key := "shin %.2f" % d
	if _parts.has(key):
		return _parts[key]
	var h = Shapes.Geo.new()
	# the calf behind, the trouser leg lying in folds on the boot
	var rows2 := _rings([[0.03, 0.060, 0.066, 0.0], [0.0, 0.068, 0.074, 0.0], [-0.09, 0.066, 0.079, 0.008], [-0.20, 0.058, 0.065, 0.004],
		[-0.285, 0.056, 0.059, 0.0], [-0.305, 0.063, 0.065, 0.0], [-0.318, 0.058, 0.061, 0.0], [-0.332, 0.064, 0.066, 0.0], [-0.340, 0.050, 0.052, 0.0]], _n(44, d), _s(6, d))
	h.skin(rows2, true, "jeans")
	return _keep(key, h)


## The boot: wheat nubuck with a padded dark collar, laced, on a thick honey-and-black lug sole. Drawn in the
## shin's measures (the ankle it hangs on is at -SHIN + 0.01).
static func _boot(d: float) -> Dictionary:
	var key := "boot %.2f" % d
	if _parts.has(key):
		return _parts[key]
	var boot = Shapes.Geo.new()
	var lower := SHIN
	var sole_y := -lower - 0.046                           # (the underside of the lugs stands on the ground)
	var collar := _rings([[-0.322, 0.050, 0.054], [-0.330, 0.062, 0.066], [-0.345, 0.064, 0.068], [-0.358, 0.058, 0.063]], _n(40, d), _s(6, d))
	boot.skin(collar, true, "boot_dark")
	var shaft := _rings([[-0.352, 0.056, 0.062], [-0.375, 0.055, 0.061], [-lower + 0.02, 0.057, 0.064], [-lower + 0.005, 0.059, 0.066]], _n(40, d), _s(6, d))
	boot.skin(shaft, true, "boot")
	var foot := []
	var keys := [[0.082, 0.034, 0.050], [0.066, 0.054, 0.058], [0.02, 0.060, 0.060], [-0.05, 0.064, 0.056], [-0.12, 0.066, 0.050], [-0.18, 0.064, 0.046],
		[-0.22, 0.056, 0.040], [-0.245, 0.040, 0.032], [-0.256, 0.020, 0.020]]
	var sub := _s(6, d)
	var round_n := _n(36, d)
	for i in keys.size() - 1:
		var q0: Array = keys[maxi(i - 1, 0)]
		var q3: Array = keys[mini(i + 2, keys.size() - 1)]
		for st in sub:
			var t := float(st) / float(sub)
			var z := lerpf(keys[i][0], keys[i + 1][0], t)
			var rx := maxf(0.5 * (2.0 * keys[i][1] + (-q0[1] + keys[i + 1][1]) * t + (2.0 * q0[1] - 5.0 * keys[i][1] + 4.0 * keys[i + 1][1] - q3[1]) * t * t
				+ (-q0[1] + 3.0 * keys[i][1] - 3.0 * keys[i + 1][1] + q3[1]) * t * t * t), 0.004)
			var ry := maxf(0.5 * (2.0 * keys[i][2] + (-q0[2] + keys[i + 1][2]) * t + (2.0 * q0[2] - 5.0 * keys[i][2] + 4.0 * keys[i + 1][2] - q3[2]) * t * t
				+ (-q0[2] + 3.0 * keys[i][2] - 3.0 * keys[i + 1][2] + q3[2]) * t * t * t), 0.004)
			var ring := PackedVector3Array()
			for k in round_n:
				var a := TAU * float(k) / float(round_n)
				var sn := sin(a)
				var cs := cos(a)
				# round over the top, square underneath: the upper stands on the sole with its full width
				ring.append(Vector3(rx * (cs if sn > 0.0 else signf(cs) * pow(absf(cs), 0.4)), sole_y + ry + ry * (sn if sn > 0.0 else sn * 0.95), z))
			foot.append(ring)
	boot.skin(foot, true, "boot")
	boot.cap("boot", foot[0], Vector3.BACK)
	boot.cap("boot", foot[-1], Vector3.FORWARD)
	# the sole, following the outline of the boot: a honey-coloured midsole, the black lug sole under it, and
	# the lugs across it (a gap under the instep, where the heel begins)
	var edge := PackedVector2Array()                                      # the outline of the foot from above: (x, z)
	for i in foot.size():
		edge.append(Vector2((foot[i][0] as Vector3).x, (foot[i][0] as Vector3).z))
	for i in range(foot.size() - 1, -1, -1):
		edge.append(Vector2(-(foot[i][0] as Vector3).x, (foot[i][0] as Vector3).z))
	var layers := [[sole_y + 0.014, 1.03, "sole_tan"], [sole_y - 0.002, 1.07, "sole_tan"], [sole_y - 0.002, 1.08, "sole"], [sole_y - 0.016, 1.08, "sole"]]
	var levels := []
	for q in layers:
		var ring2 := PackedVector3Array()
		for e in edge:
			ring2.append(Vector3(e.x * float(q[1]), q[0], -0.085 + (e.y + 0.085) * (1.0 + (float(q[1]) - 1.0) * 0.5)))
		levels.append(ring2)
	boot.skin([levels[0], levels[1]], true, "sole_tan")
	boot.cap("sole_tan", levels[0], Vector3.UP)
	boot.skin([levels[2], levels[3]], true, "sole")
	boot.cap("sole", levels[3], Vector3.DOWN)
	if d >= 0.5:
		for k in 7:
			if k == 4:
				continue
			var lz := -0.225 + 0.046 * float(k)
			var half_w := 0.0
			for e in edge:
				if absf(e.y - lz) < 0.02:
					half_w = maxf(half_w, absf(e.x))
			boot.box("sole", Vector3(0, sole_y - 0.020, lz), Vector3(half_w * 1.05, 0.004, 0.014))
		# laces over the instep, with their eyelets (those up the shaft are under the trouser leg)
		for q in [[0.110, -0.090], [0.103, -0.114], [0.099, -0.138], [0.096, -0.160]]:
			boot.box("lace", Vector3(0, sole_y + float(q[0]), q[1]), Vector3(0.022, 0.003, 0.003))
			for e in [-1.0, 1.0]:
				boot.cyl("metal", Vector3(0.023 * float(e), sole_y + float(q[0]), float(q[1]) + 0.001), Vector3.BACK, 0.004, 0.003, 8)
		boot.tube("boot_dark", [Vector3(0, sole_y + 0.170, 0.060), Vector3(0, sole_y + 0.196, 0.068), Vector3(0, sole_y + 0.170, 0.072)], 0.004, 6)   # the pull loop
	return _keep(key, boot, Vector3(0, SHIN - 0.01, 0))            # (drawn in the shin's measures; it hangs on the ankle)


## The arm in the sleeve of the jacket: a full upper arm, rounded over the shoulder.
static func _upper_arm(d: float) -> Dictionary:
	var key := "upper arm %.2f" % d
	if _parts.has(key):
		return _parts[key]
	var g = Shapes.Geo.new()
	var rows4 := _rings([[0.052, 0.004, 0.004], [0.046, 0.032, 0.034], [0.028, 0.058, 0.062], [0.0, 0.071, 0.076], [-0.12, 0.069, 0.071], [-0.24, 0.058, 0.061],
		[-UPPER_ARM, 0.052, 0.056], [-UPPER_ARM - 0.025, 0.046, 0.050]], _n(40, d), _s(6, d))
	g.skin(rows4, true, "jacket")
	return _keep(key, g)


static func _forearm(d: float, side: float) -> Dictionary:
	var key := "forearm %.2f %d" % [d, int(side)]
	if _parts.has(key):
		return _parts[key]
	var h = Shapes.Geo.new()
	var lower := FOREARM
	var rows5 := _rings([[0.025, 0.046, 0.050], [0.0, 0.052, 0.056], [-0.12, 0.051, 0.054], [-lower + 0.06, 0.043, 0.046], [-lower + 0.045, 0.047, 0.049],
		[-lower + 0.008, 0.046, 0.048], [-lower + 0.006, 0.030, 0.032]], _n(40, d), _s(6, d))
	h.skin(rows5, true, "jacket")
	if d >= 0.5:
		h.lathe("jacket_dark", Vector3(0, -lower + 0.048, 0), Vector3.UP, [Vector2(0.0478, -0.002), Vector2(0.0478, 0.002)], _n(40, d))       # the seam of the cuff
	# the hand: a palm, four fingers a little curled, and the thumb forward of them
	h.ball("skin", Vector3(0, -lower - 0.038, 0), Vector3(0.020, 0.046, 0.042), _n(28, d), maxi(4, int(18.0 * d)))
	var round_f := maxi(4, int(14.0 * d))
	if d >= 0.5:
		for k in 4:
			var fz := -0.027 + 0.018 * float(k)
			var fl: float = [0.050, 0.058, 0.054, 0.042][k]
			h.tube("skin", [Vector3(0, -lower - 0.070, fz), Vector3(-0.004 * side, -lower - 0.070 - fl * 0.5, fz), Vector3(-0.016 * side, -lower - 0.070 - fl, fz * 0.9)],
				0.0092 if k < 3 else 0.008, round_f)
		h.tube("skin", [Vector3(0, -lower - 0.030, -0.036), Vector3(-0.006 * side, -lower - 0.058, -0.054), Vector3(-0.012 * side, -lower - 0.085, -0.052)], 0.0105, round_f)
	else:
		h.ball("skin", Vector3(-0.006 * side, -lower - 0.095, -0.004), Vector3(0.016, 0.036, 0.036), 8, 4)                  # the fingers as one
	return _keep(key, h)


## The trunk: the seat of the trousers under the hem of the jacket, the jacket round over the belly and broad
## over chest and shoulders up to the collar; the shoulders are part of it (the arms turn inside them).
## A woman's is narrower in the shoulders and the waist and fuller in the chest; a slim one is flat in front,
## a heavy one round.
static func _torso(d: float, sex: String, build: int, vest: bool) -> Dictionary:
	var key := "torso %.2f %s %d %s" % [d, sex, build, vest]
	if _parts.has(key):
		return _parts[key]
	var f := sex == "f"
	var chest: float = (0.86 if f else 1.0) * float([0.96, 1.0, 1.05][build])
	var waist: float = (0.84 if f else 1.0) * float([0.93, 1.0, 1.10][build])
	var belly: float = float([0.35, 1.0, 1.7][build]) * (0.5 if f else 1.0)        # how far the front stands out
	var deep: float = [-0.012, 0.0, 0.026][build]
	var hips: float = (1.03 if f else 1.0) * float([0.96, 1.0, 1.06][build])
	var g = Shapes.Geo.new()
	var seat := _rings([[-0.175, 0.090 * hips, 0.085, 0.0, 0.9], [-0.13, 0.160 * hips, 0.112, 0.0, 0.9], [-0.06, 0.180 * hips, 0.120, -0.004, 0.88],
		[0.0, 0.182 * hips, 0.122, -0.008, 0.88]], _n(56, d), _s(6, d))
	g.skin(seat, true, "jeans")
	g.cap("jeans", seat[0], Vector3.DOWN)
	for sgn in [-1.0, 1.0]:
		g.box("jeans_dark", Vector3(0.085 * float(sgn), -0.085, 0.1115), Vector3(0.055, 0.05, 0.002))                        # back pockets
	var hem := maxf(waist, hips * 0.97)
	var keys := [[-0.082, 0.200 * hem, 0.146 + deep * 0.5, -0.006 * belly, 0.88], [-0.070, 0.205 * hem, 0.150 + deep * 0.5, -0.007 * belly, 0.88],
		[0.0, 0.204 * waist, 0.153 + deep, -0.014 * belly, 0.87], [0.10, 0.199 * waist, 0.154 + deep, -0.027 * belly, 0.87],
		[0.20, 0.195 * waist, 0.149 + deep, -0.023 * belly, 0.87], [0.30, 0.202 * (waist + chest) * 0.5, 0.143 + deep * 0.6, -0.013 * belly, 0.86],
		[0.40, 0.214 * chest, 0.142 + (0.016 if f else 0.0), -0.007 - (0.014 if f else 0.0), 0.85], [0.48, 0.224 * chest, 0.139 + (0.010 if f else 0.0), 0.0 - (0.010 if f else 0.0), 0.84],
		[0.545, 0.232 * chest, 0.130, 0.004, 0.84], [0.592, 0.233 * chest, 0.123, 0.006, 0.86], [0.614, 0.210 * chest, 0.112, 0.008, 0.88],
		[0.628, 0.140 * (0.92 if f else 1.0), 0.095, 0.010, 0.92], [0.637, 0.092 * (0.92 if f else 1.0), 0.086 * (0.94 if f else 1.0), 0.010, 0.96]]
	var rows := _rings(keys, _n(64, d), _s(9, d))
	g.skin(rows, true, "jacket")
	g.cap("jacket_dark", rows[0], Vector3.DOWN)
	g.cap("shirt", rows[-1], Vector3.UP)
	# where the front of the jacket lies at a height (for what is sewn on it), and how wide the jacket is there
	var front := func(y: float) -> float:
		for i in keys.size() - 1:
			if y <= keys[i + 1][0]:
				var t: float = clampf((y - keys[i][0]) / (keys[i + 1][0] - keys[i][0]), 0.0, 1.0)
				return lerpf(keys[i][3] - keys[i][2], keys[i + 1][3] - keys[i + 1][2], t)
		return -0.08
	if d >= 0.5:
		for k in 30:                                                                                     # the brass zip, following the front
			var zy := -0.07 + 0.70 * float(k) / 30.0
			g.box("metal", Vector3(0, zy + 0.012, front.call(zy + 0.012) - 0.003), Vector3(0.004, 0.0125, 0.003))
		for k in 60:                                                                                     # the seam round the hem
			var a := TAU * float(k) / 60.0
			g.box("jacket_dark", Vector3((float(keys[1][1]) + 0.001) * signf(cos(a)) * pow(absf(cos(a)), 0.88), -0.062,
				float(keys[1][3]) + (float(keys[1][2]) + 0.001) * signf(sin(a)) * pow(absf(sin(a)), 0.88)), Vector3(0.012, 0.0025, 0.003), Basis(Vector3.UP, -a + PI * 0.5))
		# the chest pocket on the left with the square label on it, and a slanting hand pocket low on each side
		var px: float = 0.118 * chest
		g.box("jacket_dark", Vector3(-px, 0.415, front.call(0.415) - 0.0005), Vector3(0.056 * chest, 0.060, 0.003))
		g.box("jacket", Vector3(-px, 0.412, front.call(0.412) - 0.004), Vector3(0.053 * chest, 0.055, 0.003))
		g.box("jacket_dark", Vector3(-px, 0.468, front.call(0.468) - 0.007), Vector3(0.056 * chest, 0.004, 0.003))
		g.box("patch", Vector3(-px - 0.024, 0.385, front.call(0.385) - 0.008), Vector3(0.016, 0.016, 0.002))
		g.box("orange", Vector3(-px - 0.027, 0.388, front.call(0.388) - 0.0105), Vector3(0.008, 0.008, 0.001))
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		if d >= 0.5:
			g.box("jacket_dark", Vector3(0.128 * waist * sx, 0.10, front.call(0.10) + 0.016), Vector3(0.006, 0.062, 0.004), Basis(Vector3.BACK, 0.32 * sx) * Basis(Vector3.UP, -0.5 * sx))
		# the shoulder: the jacket carried out round over the top of the arm, one piece with the body (the arm turns inside it)
		g.ball("jacket", Vector3(0.214 * chest * sx, 0.556, 0.004), Vector3(0.078, 0.056, 0.080), _n(40, d), maxi(4, int(24.0 * d)))
	if vest:
		# a work vest's reflecting bands: two round the body and one over each shoulder
		for by in [0.06, 0.24]:
			var i0 := 0
			for i in keys.size() - 1:
				if by >= float(keys[i][0]):
					i0 = i
			var t2: float = clampf((by - float(keys[i0][0])) / (float(keys[i0 + 1][0]) - float(keys[i0][0])), 0.0, 1.0)
			var brx: float = lerpf(keys[i0][1], keys[i0 + 1][1], t2) + 0.004
			var brz: float = lerpf(keys[i0][2], keys[i0 + 1][2], t2) + 0.004
			var bcz: float = lerpf(keys[i0][3], keys[i0 + 1][3], t2)
			g.skin([_oval(by - 0.022, brx, brz, _n(48, d), bcz, 0.87), _oval(by + 0.022, brx, brz, _n(48, d), bcz, 0.87)], true, "band")
		for sgn2 in [-1.0, 1.0]:
			for face in [-1.0, 1.0]:
				g.box("band", Vector3(0.105 * chest * float(sgn2), 0.43, (front.call(0.43) - 0.003) if face < 0.0 else 0.142), Vector3(0.020, 0.17, 0.003))
	# the corduroy collar: a soft band round the neck
	g.lathe("cord", Vector3(0, 0.624, 0.008), Vector3.UP, [Vector2(0.086, 0.0), Vector2(0.101, 0.008), Vector2(0.105, 0.024), Vector2(0.100, 0.029),
		Vector2(0.095, 0.024), Vector2(0.086, 0.004)], _n(64, d))
	return _keep(key, g)


## The head is one surface, from under the chin to the crown: rings round it at each height, pushed out where
## the nose, the brow, the cheekbones, the lips and the chin are and in at the eyes; the hair, the eyebrows,
## the stubble and the lips are parts of that surface in their own colours (the hair stands a little proud).
## Angles round the head are measured from straight ahead (-Z), toward the figure's right (+X).
## Hair: "short" (cropped), "bald" (a ring of it round the back), "bob" (to the jaw), "long" (down the back),
## "tail" (drawn back into a knot and a tail), "cap" (a knitted cap). A helmet goes over any of them.
static func _head(d: float, sex: String, hair: String, helmet: bool) -> Dictionary:
	var key := "head %.2f %s %s %s" % [d, sex, hair, helmet]
	if _parts.has(key):
		return _parts[key]
	var f := sex == "f"
	var hd = Shapes.Geo.new()
	hd.tube("skin", [Vector3(0, -0.075, 0.012), Vector3(0, -0.01, 0.008), Vector3(0, 0.055, 0.006)], 0.046 if f else 0.050, _n(36, d))   # neck
	if not f and d >= 0.5:
		hd.ball("skin", Vector3(0, -0.012, -0.042), Vector3(0.011, 0.015, 0.011), 14, 8)                      # Adam's apple
	var jaw := 0.93 if f else 1.0
	var shape := [[0.000, -0.058, 0.022, 0.020], [0.012, -0.049, 0.039 * jaw, 0.039], [0.030, -0.034, 0.050 * jaw, 0.061], [0.050, -0.022, 0.058 * jaw, 0.077],
		[0.075, -0.012, 0.064 * jaw, 0.089], [0.100, -0.004, 0.070, 0.097], [0.125, 0.002, 0.075, 0.103], [0.150, 0.004, 0.078, 0.105], [0.176, 0.004, 0.077, 0.103],
		[0.198, 0.004, 0.071, 0.095], [0.217, 0.004, 0.056, 0.075], [0.229, 0.004, 0.036, 0.047], [0.236, 0.004, 0.003, 0.003]]     # height: middle (z), half width, half depth
	var at_height := func(y: float) -> Vector3:
		for i in shape.size() - 1:
			if y <= shape[i + 1][0]:
				var k0: Array = shape[maxi(i - 1, 0)]
				var k1: Array = shape[i]
				var k2: Array = shape[i + 1]
				var k3: Array = shape[mini(i + 2, shape.size() - 1)]
				var t: float = clampf((y - k1[0]) / (k2[0] - k1[0]), 0.0, 1.0)
				var v := Vector3.ZERO
				for c in 3:
					v[c] = 0.5 * ((2.0 * k1[c + 1]) + (-k0[c + 1] + k2[c + 1]) * t + (2.0 * k0[c + 1] - 5.0 * k1[c + 1] + 4.0 * k2[c + 1] - k3[c + 1]) * t * t
						+ (-k0[c + 1] + 3.0 * k1[c + 1] - 3.0 * k2[c + 1] + k3[c + 1]) * t * t * t)
				return Vector3(v.x, maxf(v.y, 0.003), maxf(v.z, 0.003))
		return Vector3(0.004, 0.004, 0.004)
	# [angle, height, how wide round the head, how tall, how far out (m)]; those not at the middle are made on both sides.
	# In order: the nose (bridge, tip, wings, nostrils), the brow, the eye sockets, the cheekbones, the hollow of the
	# cheeks, the upper lip, the lower lip, the line between them, the chin, the dip under the nose.
	var nose := 0.82 if f else 1.0
	var lips := 1.12 if f else 1.0
	var bumps := [[0.0, 0.138, 0.085, 0.030, 0.008 * nose], [0.0, 0.110, 0.105, 0.022, 0.017 * nose], [0.0, 0.097, 0.125, 0.009, 0.009 * nose], [0.15, 0.093, 0.065, 0.007, 0.0045 * nose],
		[0.42, 0.159, 0.32, 0.008, 0.0045 * (0.35 if f else 1.0)], [0.44, 0.141, 0.19, 0.011, -0.0085], [0.92, 0.110, 0.30, 0.024, 0.0035 * (1.3 if f else 1.0)], [0.62, 0.075, 0.30, 0.020, -0.002],
		[0.0, 0.068, 0.24, 0.0055, 0.0038 * lips], [0.0, 0.0565, 0.21, 0.0065, 0.0040 * lips], [0.0, 0.0622, 0.27, 0.0016, -0.0026], [0.0, 0.021, 0.32, 0.016, 0.0055 * (0.55 if f else 1.0)],
		[0.0, 0.083, 0.10, 0.006, -0.0015]]
	var covers := hair == "bob" or hair == "long" or hair == "tail"          # hair that comes down over the ears and the neck
	var hairline := func(a: float) -> float:                    # how far down the hair comes at an angle round the head
		if hair == "bald" and a < 1.25:
			return 9.0
		if covers:
			if a < 0.62:
				return 0.198 - 0.016 * (a / 0.62) * (a / 0.62)
			if a < 1.10:
				return lerpf(0.182, 0.052 if hair != "tail" else 0.120, smoothstep(0.62, 1.10, a))
			return 0.030 if hair != "tail" else lerpf(0.120, 0.045, smoothstep(1.6, 2.4, a))
		if a < 0.75:
			return 0.196 - 0.010 * (a / 0.75) * (a / 0.75)
		if a < 1.30:
			return lerpf(0.186, 0.128, smoothstep(0.75, 1.30, a))
		if a < 1.95:
			return lerpf(0.128, 0.150, sin((a - 1.30) / 0.65 * PI))           # up over the ear
		return lerpf(0.128, 0.040, smoothstep(1.95, 2.55, a))
	var hair_top := func(a: float) -> float:                    # and how far up it goes (a bald head has it only round the back)
		return (0.150 + 0.022 * smoothstep(1.25, 2.6, a)) if hair == "bald" else 9.0
	var cap_line := func(a: float) -> float:                    # the edge of a knitted cap: over the brow, down over the ears, low at the back
		return 9.0 if hair != "cap" else lerpf(0.168, 0.118, smoothstep(0.5, 1.5, a)) - 0.020 * smoothstep(1.9, 2.8, a)
	var n_rows := _n(104, d)
	var n_cols := _n(144, d)
	var thick := 0.012 if covers else 0.007
	var rows_h := []
	for i in n_rows + 1:
		var y := 0.236 * (1.0 - cos(PI * float(i) / float(n_rows))) * 0.5          # (closer together at the chin and at the crown)
		var sh: Vector3 = at_height.call(y)
		var ring := PackedVector3Array()
		for k in n_cols:
			var th := TAU * float(k) / float(n_cols) - PI
			var a := absf(th)
			var e := Vector2(sh.y * sin(th), -sh.z * cos(th))
			var out := e.normalized() if e.length() > 0.0001 else Vector2(sin(th), -cos(th))
			var push := 0.0
			for bq in bumps:
				for mirror in ([1.0] if bq[0] == 0.0 else [1.0, -1.0]):
					var da: float = (th - bq[0] * float(mirror)) / bq[2]
					var dy: float = (y - bq[1]) / bq[3]
					push += bq[4] * exp(-0.5 * (da * da + dy * dy))
			if y > cap_line.call(a):
				push += 0.013 + 0.006 * smoothstep(0.185, 0.225, y)
			elif y > hairline.call(a) and y < hair_top.call(a):
				push += thick + 0.010 * smoothstep(0.185, 0.225, y) + 0.008 * exp(-0.5 * (pow((th - 0.15) / 0.5, 2.0) + pow((y - 0.200) / 0.016, 2.0)))
			e += out * push
			ring.append(Vector3(e.x, y, sh.x + e.y))
		rows_h.append(ring)
	var part := func(i: int, k: int) -> String:
		var y := 0.236 * (1.0 - cos(PI * (float(i) + 0.5) / float(n_rows))) * 0.5
		var a := absf(TAU * (float(k) + 0.5) / float(n_cols) - PI)
		if y > cap_line.call(a):
			return "hat"
		var line: float = hairline.call(a)
		if y > line and y < hair_top.call(a):
			return "hair"
		if y > line - 0.0035 and y < hair_top.call(a):
			return "hair_edge"                                      # the hair thins out at its edge: not a cut line
		var across: float = (a - 0.42) / 0.23
		if absf(across) < 1.0 and y > 0.1580 and y < 0.1580 + (0.0048 if f else 0.0070) * (1.0 - across * across * 0.75):
			return "hair"                                           # eyebrows, thinning toward their ends
		if absf(across) < 0.95 and y > 0.1345 and y < 0.1372:
			return "shade"                                          # the fold under each eye
		var up: float = (y - 0.0622) / (0.0095 * (1.05 if f else 1.0))
		if absf(up) < 1.0 and a < 0.235 * sqrt(1.0 - up * up):
			return "dark" if (absf(y - 0.0622) < 0.0011 and a < 0.19) else "lip"
		# the stubble: over the upper lip, the chin and the jaw, lower on the cheeks, up to the hair in front of the ears
		var beard := 0.087 if a < 0.34 else (lerpf(0.060, 0.100, smoothstep(0.36, 1.40, a)) if a < 1.40 else 0.130)
		if y < beard and a < 1.95 and not (a < 0.22 and y > 0.0825):
			return "stubble" if y < beard - 0.004 else "shade"       # (fading out at its upper edge)
		return "skin"
	hd.skin(rows_h, true, part)
	hd.cap("stubble", rows_h[0], Vector3.DOWN)
	hd.cap("hat" if hair == "cap" else ("skin" if hair == "bald" else "hair"), rows_h[-1], Vector3.UP)       # the crown, closed
	var fine := d >= 0.5
	for sgn in [-1.0, 1.0]:
		var sx3: float = sgn
		var eye := Vector3(0.0315 * sx3, 0.1410, -0.0790)
		hd.ball("white", eye, Vector3(0.0112, 0.0080, 0.0105), _n(30, d), maxi(4, int(18.0 * d)))                        # eyes
		hd.ball("blue", eye + Vector3(0, 0.0004, -0.0094), Vector3(0.0050, 0.0050, 0.0020), _n(26, d), maxi(3, int(10.0 * d)))
		if fine:
			hd.ball("dark", eye + Vector3(0, 0.0004, -0.0107), Vector3(0.0022, 0.0022, 0.0011), 16, 8)
			hd.ball("skin", eye + Vector3(0, 0.0058, 0.0008), Vector3(0.0136, 0.0052, 0.0122), _n(28, d), 12)           # the upper lid, over the top of the eye
			hd.ball("skin", eye + Vector3(0, -0.0068, 0.0012), Vector3(0.0128, 0.0040, 0.0112), _n(28, d), 12)          # and the lower
		if not covers:
			hd.ball("skin", Vector3(0.0790 * sx3, 0.122, 0.012), Vector3(0.0095, 0.029, 0.0175), _n(24, d), maxi(4, int(14.0 * d)))       # ears, with their lobes
			if fine:
				hd.ball("skin", Vector3(0.0770 * sx3, 0.098, 0.008), Vector3(0.0070, 0.0100, 0.0092), 16, 10)
	var around := _n(40, d)
	var up_n := maxi(5, int(24.0 * d))
	if hair == "bob":
		hd.ball("hair", Vector3(0, 0.060, 0.036), Vector3(0.094, 0.082, 0.078), around, up_n)                 # the hair hanging round the neck to the jaw
	elif hair == "long":
		hd.ball("hair", Vector3(0, 0.070, 0.038), Vector3(0.094, 0.080, 0.078), around, up_n)
		hd.ball("hair", Vector3(0, -0.060, 0.062), Vector3(0.088, 0.150, 0.048), around, up_n)                # and on down the back
	elif hair == "tail":
		hd.ball("hair", Vector3(0, 0.168, 0.100), Vector3(0.036, 0.036, 0.034), _n(28, d), maxi(4, int(16.0 * d)))      # the knot at the back of the head
		hd.tube("hair", [Vector3(0, 0.160, 0.118), Vector3(0, 0.090, 0.132), Vector3(0, 0.000, 0.118), Vector3(0, -0.060, 0.104)], 0.020, _n(20, d))
	elif hair == "cap":
		pass
		hd.ball("hat", Vector3(0, 0.250, 0.004), Vector3(0.020, 0.018, 0.020), 14, 8)                          # and the bobble
	if helmet:
		hd.ball("helmet", Vector3(0, 0.196, 0.006), Vector3(0.106, 0.070, 0.124), around, up_n)
		hd.lathe("helmet", Vector3(0, 0.172, 0.006), Vector3.UP, [Vector2(0.100, 0.0), Vector2(0.118, -0.004), Vector2(0.118, 0.004), Vector2(0.100, 0.010)], around)
		hd.box("helmet", Vector3(0, 0.174, -0.128), Vector3(0.070, 0.004, 0.030), Basis(Vector3.RIGHT, -0.18))             # the peak
		hd.box("helmet", Vector3(0, 0.250, 0.006), Vector3(0.012, 0.016, 0.100))                                          # the ridge over the top
	return _keep(key, hd)


# ------------------------------------------------------------------ a figure
static func _show(parent: Node3D, part: Dictionary, far_part, mats: Dictionary, lod: float, at := Vector3.ZERO) -> void:
	for q in [[part, true], [far_part, false]]:
		if q[0] == null:
			continue
		var p: Dictionary = q[0]
		var mi := MeshInstance3D.new()
		mi.mesh = p["mesh"]
		for i in (p["names"] as Array).size():
			mi.set_surface_override_material(i, mats[p["names"][i]])
		mi.position = at
		if far_part != null:
			if q[1]:
				mi.visibility_range_end = lod
			else:
				mi.visibility_range_begin = lod
		parent.add_child(mi)


## Build the parts a spec needs, without making a figure (so that the first figure of a shape does not hold up a frame).
## The same a piece at a time, so that no one frame waits for a whole figure: step 0, 1, 2… until it returns
## true. (Sixteen pieces; the first figure's take a few milliseconds each, later ones mostly share them.)
static func prepare_step(spec: Dictionary, step: int) -> bool:
	var ds := [float(spec.get("detail", 1.0)), float(spec.get("far", 0.0))]
	if step >= 16:
		return true
	var d: float = ds[step / 8]
	if d > 0.0:
		match step % 8:
			0: _thigh(d)
			1: _shin(d)
			2: _boot(d)
			3: _upper_arm(d)
			4: _forearm(d, -1.0)
			5: _forearm(d, 1.0)
			6: _torso(d, spec.get("sex", "m"), spec.get("build", 1), spec.get("vest", false))
			7: _head(d, spec.get("sex", "m"), spec.get("hair", "short"), spec.get("helmet", false))
	return step >= 15


static func prepare(spec: Dictionary) -> void:
	for d in [float(spec.get("detail", 1.0)), float(spec.get("far", 0.0))]:
		if d <= 0.0:
			continue
		_thigh(d); _shin(d); _boot(d); _upper_arm(d); _forearm(d, -1.0); _forearm(d, 1.0)
		_torso(d, spec.get("sex", "m"), spec.get("build", 1), spec.get("vest", false))
		_head(d, spec.get("sex", "m"), spec.get("hair", "short"), spec.get("helmet", false))


## A figure. Returns its joints: {"root", "torso", "head", "leg_l", "knee_l", "ankle_l", "leg_r", "knee_r",
## "ankle_r", "arm_l", "elbow_l", "arm_r", "elbow_r"}, and "shoulder" (where the right arm hangs from),
## "triangles" (how many it is drawn with, close up).
static func make(spec: Dictionary, mats: Dictionary) -> Dictionary:
	var d: float = spec.get("detail", 1.0)
	var far: float = spec.get("far", 0.0)
	var lod: float = spec.get("lod", 28.0)
	var sex: String = spec.get("sex", "m")
	var f := sex == "f"
	var out := {}
	var count := 0
	var root := Node3D.new()
	out["root"] = root
	var torso := Node3D.new()
	torso.position = Vector3(0, 0.95, 0)
	root.add_child(torso)
	out["torso"] = torso
	var tp := _torso(d, sex, spec.get("build", 1), spec.get("vest", false))
	_show(torso, tp, _torso(far, sex, spec.get("build", 1), spec.get("vest", false)) if far > 0.0 else null, mats, lod)
	var head := Node3D.new()
	head.position = Vector3(0, 0.655, 0)
	if f:
		head.scale = Vector3.ONE * 0.95
	torso.add_child(head)
	out["head"] = head
	var hp := _head(d, sex, spec.get("hair", "short"), spec.get("helmet", false))
	_show(head, hp, _head(far, sex, spec.get("hair", "short"), spec.get("helmet", false)) if far > 0.0 else null, mats, lod)
	count += int(tp["count"]) + int(hp["count"])
	var sh := shoulder(spec)
	out["shoulder"] = sh
	var limb := Vector3(0.90, 1.0, 0.90) if f else Vector3.ONE
	var girth: float = [0.93, 1.0, 1.08][int(spec.get("build", 1))]
	limb *= Vector3(girth, 1.0, girth)
	for side in [-1.0, 1.0]:
		var sd: float = side
		var tag := "_l" if sd < 0.0 else "_r"
		# a leg: thigh, shin, and the boot on its ankle
		var hip := Node3D.new()
		hip.position = HIP * Vector3(sd * (0.96 if f else 1.0), 1, 1)
		hip.scale = limb
		root.add_child(hip)
		var knee := Node3D.new()
		knee.position = Vector3(0, -THIGH, 0)
		hip.add_child(knee)
		var ankle := Node3D.new()
		ankle.position = Vector3(0, -SHIN + 0.01, 0)
		knee.add_child(ankle)
		_show(hip, _thigh(d), _thigh(far) if far > 0.0 else null, mats, lod)
		_show(knee, _shin(d), _shin(far) if far > 0.0 else null, mats, lod)
		_show(ankle, _boot(d), _boot(far) if far > 0.0 else null, mats, lod)
		out["leg" + tag] = hip
		out["knee" + tag] = knee
		out["ankle" + tag] = ankle
		# an arm: upper arm, and the forearm with its hand
		var arm := Node3D.new()
		arm.position = sh * Vector3(sd, 1, 1)
		arm.scale = limb * (Vector3(0.94, 1.0, 0.94) if f else Vector3.ONE)
		root.add_child(arm)
		var elbow := Node3D.new()
		elbow.position = Vector3(0, -UPPER_ARM, 0)
		arm.add_child(elbow)
		_show(arm, _upper_arm(d), _upper_arm(far) if far > 0.0 else null, mats, lod)
		_show(elbow, _forearm(d, sd), _forearm(far, sd) if far > 0.0 else null, mats, lod)
		out["arm" + tag] = arm
		out["elbow" + tag] = elbow
		count += int(_thigh(d)["count"]) + int(_shin(d)["count"]) + int(_boot(d)["count"]) + int(_upper_arm(d)["count"]) + int(_forearm(d, sd)["count"])
	out["triangles"] = count
	return out


## Set a figure walking: where it is in its stride (0 to 1), and how much of a walk it is (0 standing, 1 walking).
static func pose_walk(b: Dictionary, gait: float, amount: float) -> void:
	for q in [["_l", 0.0], ["_r", 0.5]]:
		var tag: String = q[0]
		var t: float = gait + float(q[1])
		(b["leg" + tag] as Node3D).rotation.x = stride(WALK["hip"], t) * amount
		(b["knee" + tag] as Node3D).rotation.x = -stride(WALK["knee"], t) * amount
		(b["ankle" + tag] as Node3D).rotation.x = clampf(stride(WALK["ankle"], t) * amount, -0.6, 0.5)
	var sl := stride(WALK["hip"], gait + 0.5) * 0.6 * amount - 0.10 * amount       # each arm with the leg of the other side
	var sr := stride(WALK["hip"], gait) * 0.6 * amount - 0.10 * amount
	(b["arm_l"] as Node3D).rotation.x = sl
	(b["arm_r"] as Node3D).rotation.x = sr
	(b["elbow_l"] as Node3D).rotation.x = 0.10 + (0.20 + 0.30 * maxf(0.0, sl)) * amount
	(b["elbow_r"] as Node3D).rotation.x = 0.10 + (0.20 + 0.30 * maxf(0.0, sr)) * amount
	var torso: Node3D = b["torso"]
	torso.position.y = 0.95 - cos(gait * TAU * 2.0) * 0.014 * amount
	torso.rotation = Vector3(-0.04 * amount, sin(gait * TAU) * 0.06 * amount, sin(gait * TAU) * 0.02 * amount)
	var at: Vector3 = (b["shoulder"] as Vector3) - Vector3(0, 0.95, 0)
	(b["arm_r"] as Node3D).position = torso.transform * at
	(b["arm_l"] as Node3D).position = torso.transform * (at * Vector3(-1, 1, 1))


## Seated: the thighs out along the seat, the shins hanging from the knees, the hands on the thighs.
static func pose_sit(b: Dictionary) -> void:
	for tag in ["_l", "_r"]:
		(b["leg" + tag] as Node3D).rotation.x = 1.50
		(b["knee" + tag] as Node3D).rotation.x = -1.46
		(b["ankle" + tag] as Node3D).rotation.x = 0.0
		(b["arm" + tag] as Node3D).rotation.x = 0.55
		(b["elbow" + tag] as Node3D).rotation.x = 0.75
