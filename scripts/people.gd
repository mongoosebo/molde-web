extends Node3D
## People. Thirty characters, fifteen men and fifteen women, built the way the player's own body is (scripts/body.gd)
## with 30 % fewer triangles: slim, medium or heavy, in their own hair, skin, clothes and height. Beyond 28 m each is
## drawn as a coarse cut of the same figure. They walk the sidewalks and footpaths (hips, knees and ankles bending
## through the same stride as the player's), wait at bus stops, sit on benches with their knees bent, and stand on
## Rådhusplassen and along the waterfront. There are more of them in the centre and few in the forest, fewer
## at night and in rain. They exist only near the player; walkers step aside for the player and for each other,
## and keep to the sidewalk, off the carriageway.

const Body := preload("res://scripts/body.gd")
const MOST := 26
# (in a browser the figures are cut coarser and the coarse cut takes over sooner: WebGL has far less to give)
var DETAIL := 0.45 if OS.has_feature("web") else 0.84       # 0.84 x 0.84: seven tenths of the player's triangles
var FAR_DETAIL := 0.16 if OS.has_feature("web") else 0.22
const SEAT := 0.50                       # how high a bench's seat is (scripts/props.gd)
const NEAR := 30.0                       # made no nearer than this (so they do not pop up beside the player)
const FAR := 95.0
const COATS := [Color(0.20, 0.24, 0.32), Color(0.48, 0.14, 0.12), Color(0.16, 0.30, 0.22), Color(0.62, 0.55, 0.42), Color(0.12, 0.12, 0.13),
	Color(0.70, 0.60, 0.20), Color(0.35, 0.36, 0.40), Color(0.55, 0.30, 0.45), Color(0.24, 0.42, 0.55)]
const LEGS := [Color(0.13, 0.16, 0.24), Color(0.10, 0.10, 0.11), Color(0.30, 0.28, 0.25), Color(0.20, 0.22, 0.26)]
const HAIR := [Color(0.20, 0.14, 0.09), Color(0.08, 0.07, 0.06), Color(0.62, 0.50, 0.30), Color(0.50, 0.50, 0.50), Color(0.40, 0.20, 0.10)]

var world
var player
var daytime
var weather
var festival := false                    # Moldejazz: more people about, and a crowd at the stage (scripts/molde.gd)
var people: Array = []                   # each: {node, legs, arms, kind, ...}
var stats := {"made": 0, "walkers": 0, "waiting": 0, "sitting": 0, "standing": 0, "stepped_aside": 0}

var _walks: Array = []                   # ways people walk along: [way, side offset]
var _walk_cells := {}                    # 100 m cell -> indices into _walks
var _spots: Array = []                   # places to wait, sit or stand: [Vector3 place, facing (radians), kind]
var _spot_cells := {}
var _taken := {}
var _near_ok := {}
var _rng := RandomNumberGenerator.new()
var _tick := 0.0
var _town := 0.0
var characters: Array = []               # the thirty: {"spec", "mats", "tall", "sex"}
var _worker_kinds: Array = []            # and three in work clothes, for the building site
var _workers: Array = []                 # those standing at their work: {"body", "node", "at", "job", "phase"}
var _unready: Array = []                 # characters whose parts are not built yet (one is built each step)
var _ready_chars: Array = []
var _next_char := 0


func setup(w, p, d, wt) -> void:
	world = w
	player = p
	daytime = d
	weather = wt
	_rng.seed = 11
	_cast()
	# where to walk: beside every road that has a sidewalk, and along the footpaths
	for way in world.detail.ways:
		var pts: PackedVector2Array = way[3]
		if pts.size() < 6:
			continue
		var kind: int = way[1]
		if kind == 0:
			var fl: PackedByteArray = way[5]
			var fr: PackedByteArray = way[6]
			if fl[fl.size() / 2] == 1:
				_add_walk(way, float(way[0]) + 1.1)
			if fr[fr.size() / 2] == 1:
				_add_walk(way, -(float(way[0]) + 1.1))
		elif kind == 1 or kind == 2 or kind == 7:
			_add_walk(way, 0.0)
	# where to wait, sit and stand
	for key in world.props.cells:
		for rec in world.props.cells[key]:
			var xf: Transform3D = rec[1]
			var face := atan2(-xf.basis.z.x, -xf.basis.z.z)
			if rec[0] == world.props.SHELTER:
				_add_spot(xf * Vector3(-0.7, 0, 0.1), face, "waiting")
				_add_spot(xf * Vector3(0.8, 0, -0.9), face, "waiting")
			elif rec[0] == world.props.BUS_SIGN:
				_add_spot(xf * Vector3(0.9, 0, 0.6), face, "waiting")
			elif rec[0] == world.props.BENCH:
				# (a figure faces its own -z: turned to look out from the bench, its back to the bench's back)
				_add_spot(xf * Vector3(-0.35, 0, 0.06), atan2(xf.basis.z.x, xf.basis.z.z), "sitting")
			elif rec[0] == world.props.VIEWPOINT:
				_add_spot(xf * Vector3(0.6, 0, 0.8), face, "standing")
	var plaza: Array = world.meta.get("plaza", [])
	if plaza.size() >= 6:
		var poly := PackedVector2Array()
		for i in range(0, plaza.size(), 2):
			poly.append(Vector2(plaza[i], plaza[i + 1]))
		for i in 40:
			var q := Vector2(_rng.randf_range(-26.0, 15.0), _rng.randf_range(-55.0, -8.0))
			if Geometry2D.is_point_in_polygon(q, poly):
				_add_spot(Vector3(q.x, 0, q.y), _rng.randf() * TAU, "standing")
	for q in world.meta.get("quays", []):                # along the waterfront, looking out
		var a := Vector2(q[0], q[1])
		var b := Vector2(q[2], q[3])
		var n := Vector2(q[4], q[5])
		var k := 0.15
		while k < 1.0:
			var p2 := a.lerp(b, k) - n * 1.6
			_add_spot(Vector3(p2.x, 0, p2.y), atan2(n.x, n.y) + PI, "standing")
			k += 22.0 / maxf(a.distance_to(b), 22.0)


func _add_walk(way: Array, side: float) -> void:
	var i := _walks.size()
	_walks.append([way, side])
	var pts: PackedVector2Array = way[3]
	for k in range(0, pts.size(), 8):
		var key: Vector2i = world.detail.cell_of(pts[k].x, pts[k].y)
		if not _walk_cells.has(key):
			_walk_cells[key] = PackedInt32Array()
		if not i in _walk_cells[key]:
			_walk_cells[key].append(i)


func add_spot(at: Vector3, face: float, kind: String) -> void:
	_add_spot(at, face, kind)
	_near_ok[_spots.size() - 1] = true                 # (a crowd may stand near the player from the start)


func _add_spot(at: Vector3, face: float, kind: String) -> void:
	var key: Vector2i = world.detail.cell_of(at.x, at.z)
	if not _spot_cells.has(key):
		_spot_cells[key] = PackedInt32Array()
	_spot_cells[key].append(_spots.size())
	_spots.append([at, face, kind])


# ------------------------------------------------------------------ a figure
## The thirty characters, and the workers. Their parts are built a character at a time over the first frames.
func _cast() -> void:
	var skins := [Color(0.88, 0.72, 0.62), Color(0.84, 0.68, 0.57), Color(0.92, 0.77, 0.68), Color(0.74, 0.56, 0.44), Color(0.56, 0.39, 0.29), Color(0.80, 0.63, 0.50)]
	var hairs := [Color(0.20, 0.14, 0.09), Color(0.08, 0.07, 0.06), Color(0.66, 0.54, 0.32), Color(0.52, 0.52, 0.52), Color(0.42, 0.22, 0.11), Color(0.82, 0.80, 0.76),
		Color(0.34, 0.24, 0.15), Color(0.76, 0.66, 0.42)]
	var eyes := [Color(0.22, 0.48, 0.80), Color(0.30, 0.22, 0.14), Color(0.32, 0.46, 0.34), Color(0.40, 0.52, 0.62)]
	var boots := [Color(0.74, 0.55, 0.29), Color(0.08, 0.08, 0.08), Color(0.32, 0.20, 0.12), Color(0.55, 0.56, 0.58), Color(0.86, 0.86, 0.84)]
	var man_hair := ["short", "short", "bald", "cap", "short", "bob", "short", "bald", "short", "cap", "short", "short", "bob", "short", "bald"]
	var man_build := [1, 0, 2, 1, 1, 0, 2, 1, 0, 1, 2, 1, 0, 1, 2]
	var woman_hair := ["long", "bob", "tail", "long", "cap", "bob", "tail", "long", "bob", "long", "tail", "bob", "cap", "long", "tail"]
	var woman_build := [1, 0, 1, 2, 0, 1, 1, 0, 2, 1, 0, 1, 1, 2, 0]
	for i in 30:
		var woman := i >= 15
		var k := i - 15 if woman else i
		var coat: Color = COATS[(i * 4 + (3 if woman else 0)) % COATS.size()]
		if woman and k % 4 == 1:
			coat = [Color(0.70, 0.22, 0.30), Color(0.86, 0.80, 0.70), Color(0.30, 0.50, 0.52), Color(0.60, 0.40, 0.62)][(k / 4) % 4]
		var trousers: Color = LEGS[(i * 3 + 1) % LEGS.size()]
		var hair: Color = hairs[(i * 5 + 2) % hairs.size()]
		var skin: Color = skins[(i * 7 + 1) % skins.size()]
		var boot: Color = boots[(i * 2 + (1 if woman else 0)) % boots.size()]
		var stubble := not woman and k % 3 == 0
		var own := {"jacket": coat, "jacket_dark": coat.darkened(0.28), "cord": coat.darkened(0.5) if k % 2 == 0 else Color(0.20, 0.18, 0.16), "shirt": [Color(0.20, 0.21, 0.23), Color(0.85, 0.85, 0.82), Color(0.45, 0.20, 0.18)][i % 3],
			"jeans": trousers, "jeans_dark": trousers.darkened(0.3), "skin": skin, "stubble": skin.lerp(hair, 0.30) if stubble else skin, "shade": skin.darkened(0.10),
			"lip": skin.lerp(Color(0.72, 0.22, 0.26), 0.38 if woman else 0.18), "hair": hair, "hair_edge": hair.lerp(skin, 0.5), "boot": boot, "boot_dark": boot.darkened(0.6),
			"sole_tan": boot.darkened(0.25), "lace": boot.darkened(0.2), "blue": eyes[(i * 3) % eyes.size()], "hat": [Color(0.20, 0.22, 0.30), Color(0.55, 0.12, 0.12), Color(0.80, 0.78, 0.70), Color(0.15, 0.32, 0.22)][i % 4],
			"patch": coat, "orange": coat, "metal": Color(0.55, 0.56, 0.58)}
		var spec := {"sex": "f" if woman else "m", "build": (woman_build if woman else man_build)[k], "hair": (woman_hair if woman else man_hair)[k], "detail": DETAIL, "far": FAR_DETAIL, "lod": 12.0 if OS.has_feature("web") else 28.0}
		var tall := (0.87 + 0.085 * float((k * 5) % 7) / 6.0) if woman else (0.94 + 0.10 * float((k * 3) % 7) / 6.0)
		characters.append({"spec": spec, "mats": Body.materials(own), "tall": tall, "sex": spec["sex"]})
		_unready.append(characters[i])
	for i in 3:
		var skin2: Color = skins[i * 2]
		var hair2: Color = hairs[i]
		var own2 := {"jacket": Color(0.86, 0.84, 0.10), "jacket_dark": Color(0.60, 0.58, 0.08), "cord": Color(0.60, 0.58, 0.08), "jeans": Color(0.10, 0.13, 0.20), "jeans_dark": Color(0.07, 0.09, 0.14),
			"skin": skin2, "stubble": skin2.lerp(hair2, 0.3) if i != 1 else skin2, "shade": skin2.darkened(0.1), "lip": skin2.lerp(Color(0.72, 0.22, 0.26), 0.2), "hair": hair2, "hair_edge": hair2.lerp(skin2, 0.5),
			"boot": Color(0.10, 0.09, 0.08), "boot_dark": Color(0.05, 0.05, 0.05), "sole_tan": Color(0.12, 0.11, 0.10), "lace": Color(0.25, 0.22, 0.18), "patch": Color(0.86, 0.84, 0.10), "orange": Color(0.86, 0.84, 0.10),
			"helmet": [Color(0.95, 0.80, 0.10), Color(0.93, 0.93, 0.91), Color(0.92, 0.45, 0.10)][i], "metal": Color(0.55, 0.56, 0.58)}
		var spec2 := {"sex": "f" if i == 1 else "m", "build": [1, 1, 2][i], "hair": "tail" if i == 1 else "short", "helmet": true, "vest": true, "detail": DETAIL, "far": FAR_DETAIL, "lod": 12.0 if OS.has_feature("web") else 28.0}
		_worker_kinds.append({"spec": spec2, "mats": Body.materials(own2), "tall": [1.0, 0.90, 0.97][i], "sex": spec2["sex"]})


func _figure(who: Dictionary = {}) -> Dictionary:
	if who.is_empty():
		who = _ready_chars[_next_char % _ready_chars.size()]
		_next_char += 7                                  # (seven is prime to thirty: every character gets its turn)
	var b: Dictionary = Body.make(who["spec"], who["mats"])
	var node: Node3D = b["root"]
	node.scale = Vector3.ONE * float(who["tall"])
	add_child(node)
	return {"node": node, "body": b, "legs": [b["leg_l"], b["leg_r"]], "arms": [b["arm_l"], b["arm_r"]], "phase": _rng.randf() * TAU, "gait": _rng.randf(),
		"pace": _rng.randf_range(1.15, 1.6) * (0.94 if who["sex"] == "f" else 1.0), "tall": float(who["tall"])}


## Somebody at work on a building site, in a yellow vest and a helmet: stays where they are put.
func add_worker(at: Vector3, face: float, job: int) -> void:
	_workers.append({"at": at, "face": face, "job": job, "who": _worker_kinds[_workers.size() % _worker_kinds.size()], "phase": _rng.randf() * TAU})


func _work(delta: float, pp: Vector3) -> void:
	for w in _workers:
		var near: bool = (w["at"] as Vector3).distance_to(pp) < 140.0
		if not w.has("node"):
			if not near:
				continue
			Body.prepare(w["who"]["spec"])
			var f := _figure(w["who"])
			w["node"] = f["node"]
			w["body"] = f["body"]
			(w["node"] as Node3D).position = w["at"]
			(w["node"] as Node3D).rotation.y = w["face"]
		var node: Node3D = w["node"]
		node.visible = near
		if not near:
			continue
		w["phase"] += delta
		var b: Dictionary = w["body"]
		var t: float = w["phase"]
		match int(w["job"]):
			0:                                              # hammering: bent over a little, the right arm going up and down
				(b["torso"] as Node3D).rotation.x = -0.45
				(b["arm_r"] as Node3D).rotation.x = 1.15 + 0.45 * sin(t * 7.0)
				(b["elbow_r"] as Node3D).rotation.x = 0.9 + 0.35 * sin(t * 7.0 + 0.6)
				(b["arm_l"] as Node3D).rotation.x = 0.8
				(b["elbow_l"] as Node3D).rotation.x = 0.5
			1:                                              # looking at the work with the hands on the hips, turning the head
				(b["arm_l"] as Node3D).rotation.z = -0.45
				(b["arm_r"] as Node3D).rotation.z = 0.45
				(b["elbow_l"] as Node3D).rotation.x = 1.3
				(b["elbow_r"] as Node3D).rotation.x = 1.3
				(b["head"] as Node3D).rotation.y = 0.5 * sin(t * 0.4)
			_:                                              # carrying: both forearms held out, shifting from foot to foot
				(b["arm_l"] as Node3D).rotation.x = 0.35
				(b["arm_r"] as Node3D).rotation.x = 0.35
				(b["elbow_l"] as Node3D).rotation.x = 1.2
				(b["elbow_r"] as Node3D).rotation.x = 1.2
				(b["torso"] as Node3D).rotation.z = 0.03 * sin(t * 1.1)
		var at2: Vector3 = (b["shoulder"] as Vector3) - Vector3(0, 0.95, 0)
		(b["arm_r"] as Node3D).position = (b["torso"] as Node3D).transform * at2
		(b["arm_l"] as Node3D).position = (b["torso"] as Node3D).transform * (at2 * Vector3(-1, 1, 1))


## The ground under a figure: what a ray straight down meets (a sidewalk, a quay, a step), or the bare ground.
func _floor(x: float, z: float, near_y: float) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(x, near_y + 1.6, z), Vector3(x, near_y - 2.5, z))
	q.exclude = [player.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit["position"].y if not hit.is_empty() else world.height_at(x, z)


# ------------------------------------------------------------------ living
func _physics_process(delta: float) -> void:
	if world == null:
		return
	var pp: Vector3 = player.global_position
	if not _unready.is_empty():                          # one more character's parts built (the first ones take longest: the rest share theirs)
		var who: Dictionary = _unready.pop_front()
		Body.prepare(who["spec"])
		_ready_chars.append(who)
	_work(delta, pp)
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.4
		var c: Vector2i = world.detail.cell_of(pp.x, pp.z)
		var houses := 0
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				houses += (world.detail.buildings.get(Vector2i(c.x + dx, c.y + dz), []) as Array).size()
		_town = clampf(houses / 70.0, 0.0, 1.0)
		var want := int((2.0 + (MOST - 2.0) * _town) * (1.0 - 0.65 * daytime.night) * (1.0 - 0.6 * float(weather.now["rain"])))
		if festival:
			want += 24
		if people.size() < want and not _ready_chars.is_empty():
			_make(pp, c)
	var i := people.size() - 1
	while i >= 0:
		var f: Dictionary = people[i]
		var node: Node3D = f["node"]
		if node.global_position.distance_to(pp) > FAR + 15.0:
			if f.has("spot"):
				_taken.erase(f["spot"])
			node.queue_free()
			people.remove_at(i)
			i -= 1
			continue
		if f["kind"] == "walker":
			_walk(f, delta, pp)
		else:
			# standing, waiting or sitting: a little life (a sway, a look round now and then)
			f["phase"] += delta
			node.rotation.y = f["face"] + 0.25 * sin(f["phase"] * 0.23) * (1.0 if f["kind"] != "sitting" else 0.3)
			if f["kind"] != "sitting":
				for arm in f["arms"]:
					arm.rotation.x = 0.04 * sin(f["phase"] * 0.9)
			(f["body"]["head"] as Node3D).rotation.y = 0.35 * sin(f["phase"] * 0.31)
		i -= 1


func _make(pp: Vector3, c: Vector2i) -> void:
	var here := Vector2(pp.x, pp.z)
	# somebody at a stop, on a bench or standing about, where there is such a place free
	if _rng.randf() < (0.45 if not festival else 0.75):
		var options := []
		for dz in [-1, 0, 1]:
			for dx in [-1, 0, 1]:
				var list = _spot_cells.get(Vector2i(c.x + dx, c.y + dz))
				if list != null:
					for s in list:
						var d: float = Vector2(_spots[s][0].x, _spots[s][0].z).distance_to(here)
						if (d > NEAR or (_near_ok.has(s) and d > 6.0)) and d < FAR and not _taken.has(s) and (not _near_ok.has(s) or festival) and (_spots[s][2] != "sitting" or (s * 7 + 3) % 10 < 3):       # (most benches stand empty)
							options.append(s)
		if not options.is_empty():
			var s: int = options[_rng.randi_range(0, options.size() - 1)]
			var spot: Array = _spots[s]
			var f := _figure()
			var at: Vector3 = spot[0]
			at.y = _floor(at.x, at.z, world.height_at(at.x, at.z) + 0.6)
			f["kind"] = spot[2]
			f["face"] = spot[1]
			f["spot"] = s
			_taken[s] = true
			var node: Node3D = f["node"]
			node.position = at
			node.rotation.y = spot[1]
			if spot[2] == "sitting":
				node.position.y = (spot[0] as Vector3).y                # (from the foot of the bench, not from the top of its solid box: they sat in the air)
				# on the seat: the hips at the height of the seat and half a thigh, the knees bent over its edge
				node.position.y += SEAT + 0.085 * node.scale.y - Body.HIP.y * node.scale.y
				Body.pose_sit(f["body"])
			people.append(f)
			stats["made"] += 1
			stats[spot[2]] += 1
			return
	# or somebody walking
	for attempt in 5:
		var a := _rng.randf() * TAU
		var q := here + Vector2(cos(a), sin(a)) * _rng.randf_range(NEAR + 8.0, FAR - 15.0)
		var list = _walk_cells.get(world.detail.cell_of(q.x, q.y))
		if list == null:
			continue
		var wi: int = list[_rng.randi_range(0, list.size() - 1)]
		var way: Array = _walks[wi][0]
		var pts: PackedVector2Array = way[3]
		var best := 0
		for k in pts.size():
			if pts[k].distance_squared_to(q) < pts[best].distance_squared_to(q):
				best = k
		if pts[best].distance_to(here) < NEAR or pts[best].distance_to(here) > FAR:
			continue
		var f := _figure()
		f["kind"] = "walker"
		f["walk"] = wi
		f["s"] = (way[7] as PackedFloat32Array)[best]
		f["dir"] = 1 if _rng.randf() < 0.5 else -1
		f["aside"] = 0.0
		f["y"] = world.height_at(pts[best].x, pts[best].y)
		people.append(f)
		stats["made"] += 1
		stats["walkers"] += 1
		_walk(f, 0.0, pp)
		return


func _walk(f: Dictionary, delta: float, pp: Vector3) -> void:
	var way: Array = _walks[f["walk"]][0]
	var side: float = _walks[f["walk"]][1]
	var pts: PackedVector2Array = way[3]
	var dist: PackedFloat32Array = way[7]
	var length := dist[dist.size() - 1]
	var node: Node3D = f["node"]
	var k := clampi(dist.bsearch(f["s"]) - 1, 0, pts.size() - 2)
	var t := clampf((f["s"] - dist[k]) / maxf(dist[k + 1] - dist[k], 0.001), 0.0, 1.0)
	var along := (pts[k + 1] - pts[k]).normalized()
	var left := Vector2(along.y, -along.x)
	var fwd: Vector2 = along * float(f["dir"])
	var p: Vector2 = pts[k].lerp(pts[k + 1], t) + left * (side + f["aside"])
	# the player or someone else right ahead: step to the side, and wait if there is no room
	var speed: float = f["pace"]
	var push := 0.0
	var rel := Vector2(pp.x, pp.z) - p
	if rel.dot(fwd) > -0.3 and rel.dot(fwd) < 2.2 and absf(rel.dot(left)) < 0.9 and absf(pp.y - node.position.y) < 2.0:
		push = -signf(rel.dot(left)) if absf(rel.dot(left)) > 0.05 else 1.0
		if rel.length() < 0.9:
			speed = 0.0
		if not f.get("dodging", false):
			stats["stepped_aside"] += 1
		f["dodging"] = true
	else:
		f["dodging"] = false
		for o in people:
			if o == f:
				continue
			var ro := Vector2((o["node"] as Node3D).position.x, (o["node"] as Node3D).position.z) - p
			if ro.dot(fwd) > 0.0 and ro.dot(fwd) < 1.6 and absf(ro.dot(left)) < 0.6:
				push = -signf(ro.dot(left)) if absf(ro.dot(left)) > 0.05 else -1.0
	f["aside"] = clampf(move_toward(f["aside"], push * 0.8, 1.5 * delta), -0.9, 0.9)
	f["s"] += speed * f["dir"] * delta
	if f["s"] <= 0.5 or f["s"] >= length - 0.5:
		f["dir"] = -f["dir"]                                   # the end of the walk: back again
		f["s"] = clampf(f["s"], 0.6, length - 0.6)
	f["y"] = lerpf(f["y"], _floor(p.x, p.y, f["y"]), minf(1.0, 10.0 * delta)) if delta > 0.0 else _floor(p.x, p.y, f["y"] + 0.6)
	node.position = Vector3(p.x, f["y"], p.y)
	node.rotation.y = lerp_angle(node.rotation.y, atan2(-fwd.x, -fwd.y), minf(1.0, 8.0 * delta) if delta > 0.0 else 1.0)
	# legs and arms swing with the stride
	f["gait"] = fposmod(float(f["gait"]) + speed * delta / (1.5 * float(f["tall"])), 1.0)
	f["moving"] = move_toward(float(f.get("moving", 1.0)), 1.0 if speed > 0.1 else 0.0, 4.0 * delta)
	Body.pose_walk(f["body"], f["gait"], f["moving"])
