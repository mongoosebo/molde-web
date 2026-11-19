extends Node3D
## Molde itself: the things people know the town by.
##
## - Roses, the town's symbol ("Rosenes by"): beds of roses along Storgata and round Rådhusplassen, the same
##   planters as on the square and the town hall's roof.
## - A sign for the coastal steamer where it comes alongside (scripts/traffic.gd sails it in at its times).
## - Varden: a board at the viewpoint naming the mountains across the fjord, the Molde panorama.
## - Moldejazz: in the festival week in July (days 196 to 202 of the year) banners in the centre, a stage on
##   Rådhusplassen and a crowd in front of it. `./run.sh -- --date=198` starts in that week.

const JAZZ_FROM := 196
const JAZZ_TO := 202

var world
var player
var daytime
var people
var roses := 0                           # how many beds were set out (for the checks)
var festival := false
var _jazz: Node3D
var _tick := 0.0
var _crowd_added := false


func setup(w, p, d, pe, meshes: Dictionary, steamer_berth) -> void:
	world = w
	player = p
	daytime = d
	people = pe
	_roses(meshes[world.props.PLANTER])
	_raised_beds()
	_sites()
	if steamer_berth != null:
		var berth: Vector2 = steamer_berth
		# on the nearest dry ground to where the ship lies
		for r in range(10, 200, 5):
			var found := false
			for k in 24:
				var q := berth + Vector2(cos(k * TAU / 24.0), sin(k * TAU / 24.0)) * float(r)
				if world.water_at(q.x, q.y).is_empty() and world.height_at(q.x, q.y) > 1.0 and not found:
					var to := berth - q
					_board(Vector3(q.x, world.height_at(q.x, q.y), q.y), atan2(to.x, to.y),
						"Hurtigruten", "Kystruten Bergen – Kirkenes\nSørgående  09:30 – 10:15\nNordgående  21:00 – 22:00", Color(0.10, 0.10, 0.12))
					found = true
			if found:
				break
	# Varden: the highest viewpoint in the map
	var top = null
	for key in world.props.cells:
		for rec in world.props.cells[key]:
			if rec[0] == world.props.VIEWPOINT and (top == null or (rec[1] as Transform3D).origin.y > (top as Transform3D).origin.y):
				top = rec[1]
	if top != null:
		var xf: Transform3D = top
		var at := xf * Vector3(-2.6, 0, 0.6)
		at.y = world.height_at(at.x, at.z)
		_board(at, atan2(-xf.basis.z.x, -xf.basis.z.z) + PI, "Varden  407 moh.",
			"Moldepanoramaet: fjorden, øyene og Romsdalsalpene\nVengetindene · Romsdalshorn · Trolltindene\nBispen · Kongen · Dronninga · Finnan\nBlåstolen · Lauparen · Skåla", Color(0.16, 0.22, 0.18))


## Raised beds of roses where someone who knows the town says there is one (tools/overrides.py, ROSE_BEDS): a box
## of concrete waist high, earth in it, a low bush of leaves and the roses on top. Solid.
func _raised_beds() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1911
	for bed in world.meta.get("rose_beds", []):
		var length: float = bed[2]
		var width: float = bed[3]
		var y: float = world.detail.surface_at(bed[0], bed[1])
		if is_nan(y):
			y = world.height_at(bed[0], bed[1])
		var concrete := Color(0.50, 0.39, 0.31)                        # the town hall's own brown concrete (note of 18 Nov)
		var walls := [
			world.props._box(Vector3(length, 0.90, 0.10), Vector3(0, 0.45, -width * 0.5 + 0.05), concrete),
			world.props._box(Vector3(length, 0.90, 0.10), Vector3(0, 0.45, width * 0.5 - 0.05), concrete),
			world.props._box(Vector3(0.10, 0.90, width - 0.2), Vector3(-length * 0.5 + 0.05, 0.45, 0), concrete),
			world.props._box(Vector3(0.10, 0.90, width - 0.2), Vector3(length * 0.5 - 0.05, 0.45, 0), concrete)]
		var parts := [
			world.props._box(Vector3(length - 0.2, 0.06, width - 0.2), Vector3(0, 0.82, 0), Color(0.16, 0.12, 0.09)),      # earth
			world.props._box(Vector3(length - 0.35, 0.26, width - 0.35), Vector3(0, 0.97, 0), Color(0.13, 0.30, 0.12))]    # leaves
		var n := int(length * width * 14.0)
		for i in n:                                                                                              # the roses: red, a few pink and white
			var r := rng.randf()
			var col := Color(0.72, 0.05, 0.08) if r < 0.7 else (Color(0.90, 0.45, 0.55) if r < 0.88 else Color(0.93, 0.90, 0.84))
			var s := rng.randf_range(0.07, 0.11)
			parts.append(world.props._box(Vector3(s, s * 0.8, s), Vector3(rng.randf_range(-0.5, 0.5) * (length - 0.5), 1.10 + rng.randf_range(0.0, 0.10),
				rng.randf_range(-0.5, 0.5) * (width - 0.5)), col))
		var mi := MeshInstance3D.new()
		mi.name = "RoseBed"
		mi.mesh = world._merge(parts)
		mi.position = Vector3(bed[0], y - 0.12, bed[1])                 # (sunk a little: the ground under it is not level)
		mi.rotation.y = deg_to_rad(bed[4])
		add_child(mi)
		# its walls in the town hall's own concrete: the same texture and colour (note of 18 Nov)
		var wall := MeshInstance3D.new()
		wall.mesh = world._merge(walls)
		var hall = world.get_node_or_null("Landmarks")
		if hall != null and hall.get("_mats") is Dictionary and (hall.get("_mats") as Dictionary).has("concrete_brown"):
			wall.material_override = hall._mats["concrete_brown"]
		mi.add_child(wall)
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(length, 1.0, width)
		shape.shape = box
		shape.position = Vector3(0, 0.5, 0)
		body.add_child(shape)
		mi.add_child(body)


func _ground(x: float, z: float) -> float:
	var y: float = world.detail.surface_at(x, z)
	return world.height_at(x, z) if is_nan(y) else y


## A thing built of boxes, standing in the world as one solid object.
func _stand(parts: Array, at: Vector3, basis: Basis, title: String, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = title
	mi.mesh = world._merge(parts)
	mi.transform = Transform3D(basis, at)
	add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		shape.shape = mi.mesh.create_trimesh_shape()
		body.add_child(shape)
		mi.add_child(body)
	return mi


func _words(text: String, at: Vector3, facing: Vector3, size: float, col: Color, parent: Node3D = null) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 96
	label.pixel_size = size / 96.0
	label.outline_size = 0
	label.modulate = col
	label.shaded = false
	label.double_sided = false
	label.transform = Transform3D(Basis(Vector3.UP.cross(facing).normalized(), Vector3.UP, facing), at)
	(parent if parent != null else self).add_child(label)


## Places set up by hand (tools/overrides.py SITES; worked out against the buildings by tools/build_map.py).
func _sites() -> void:
	var sites: Dictionary = world.meta.get("sites", {})
	var B: Callable = world.props._box
	var concrete := Color(0.66, 0.65, 0.62)
	var steel := Color(0.30, 0.31, 0.33)
	var white := Color(0.93, 0.93, 0.91)
	var yellow := Color(0.98, 0.76, 0.05)
	var red := Color(0.80, 0.08, 0.06)
	for s in sites.get("drive_through", []):
		# the lane round the building: a white line along each side of it, arrows on the asphalt
		var lane: Array = s["lane"]
		var marks := []
		var n := lane.size() / 2
		for i in n:
			var a := Vector2(lane[2 * i], lane[2 * i + 1])
			var b := Vector2(lane[(2 * i + 2) % lane.size()], lane[(2 * i + 3) % lane.size()])
			var d := (b - a)
			var ln := d.length()
			if ln < 0.05:
				continue
			d /= ln
			var side := Vector2(-d.y, d.x)
			var yaw := atan2(d.x, d.y)
			for off in [-1.75, 1.75]:
				var m: Vector2 = (a + b) * 0.5 + side * float(off)
				marks.append(B.call(Vector3(0.10, 0.012, ln * 1.25), Vector3(m.x, _ground(m.x, m.y) + 0.135, m.y), white, Basis(Vector3.UP, yaw)))
			if i % 8 == 3:                                      # an arrow along the lane
				var m2 := (a + b) * 0.5
				var y2 := _ground(m2.x, m2.y) + 0.135
				marks.append(B.call(Vector3(0.14, 0.012, 1.3), Vector3(m2.x, y2, m2.y), white, Basis(Vector3.UP, yaw)))
				for sg in [-1.0, 1.0]:
					var tip := m2 + d * 0.65
					var wing: Vector2 = tip - d * 0.28 + side * 0.20 * float(sg)
					marks.append(B.call(Vector3(0.14, 0.012, 0.62), Vector3(wing.x, y2, wing.y), white, Basis(Vector3.UP, yaw - 0.62 * float(sg))))
		_stand(marks, Vector3.ZERO, Basis.IDENTITY, "DriveThroughLane", false)
		# where the order is given: a menu board under a little roof, and the post one talks to (to look at only)
		var post: Array = s["post"]
		var out := Vector3(post[2], 0, post[3])
		var along := Vector3.UP.cross(out)
		var at := Vector3(post[0], _ground(post[0], post[1]), post[1])
		var bs := Basis(along, Vector3.UP, out)
		var parts := [
			B.call(Vector3(0.9, 0.12, 0.9), Vector3(0, 0.06, 0), concrete),                        # the plinth
			B.call(Vector3(0.32, 1.25, 0.22), Vector3(-1.5, 0.62, 0.15), steel),                   # the post one talks to
			B.call(Vector3(0.24, 0.20, 0.03), Vector3(-1.5, 1.02, 0.275), Color(0.05, 0.05, 0.06)),    # its grille
			B.call(Vector3(0.24, 0.14, 0.03), Vector3(-1.5, 0.76, 0.275), Color(0.10, 0.35, 0.16)),    # the little screen
			B.call(Vector3(0.05, 0.03, 0.03), Vector3(-1.5, 1.18, 0.275), red),
			B.call(Vector3(0.12, 2.5, 0.12), Vector3(-0.72, 1.25, 0), steel), B.call(Vector3(0.12, 2.5, 0.12), Vector3(0.72, 1.25, 0), steel),
			B.call(Vector3(1.9, 1.35, 0.10), Vector3(0, 1.75, 0.02), Color(0.10, 0.10, 0.11)),     # the board
			B.call(Vector3(2.5, 0.10, 1.5), Vector3(0, 2.62, 0.45), red),                          # its roof, out over the car window
			B.call(Vector3(2.5, 0.05, 1.5), Vector3(0, 2.69, 0.45), yellow)]
		for col_ in 3:
			for row_ in 3:                                                                       # nine panels of pictures and prices
				parts.append(B.call(Vector3(0.56, 0.38, 0.02), Vector3(-0.6 + 0.6 * float(col_), 2.16 - 0.42 * float(row_), 0.08),
					[Color(0.85, 0.62, 0.25), Color(0.75, 0.25, 0.15), Color(0.90, 0.85, 0.70), Color(0.55, 0.35, 0.18), Color(0.30, 0.55, 0.25)][(col_ * 2 + row_) % 5]))
		var board := _stand(parts, at, bs, "OrderPoint")
		_words("ORDER HERE", Vector3(0, 2.50, 0.09), Vector3.BACK, 0.11, white, board)
		# the sign on its mast by the road: the yellow M on red
		var sg2: Array = s["sign"]
		var mast := [B.call(Vector3(0.28, 9.0, 0.28), Vector3(0, 4.5, 0), steel), B.call(Vector3(2.6, 2.6, 0.36), Vector3(0, 10.2, 0), red)]
		for face in [-1.0, 1.0]:
			for k in 4:                                                                          # an M of four slanted bars, on both faces
				var x := -0.72 + 0.48 * float(k)
				mast.append(B.call(Vector3(0.26, 1.75, 0.04), Vector3(x, 10.2, 0.19 * face), yellow, Basis(Vector3.BACK, 0.16 * (-1.0 if k % 2 == 0 else 1.0))))
			mast.append(B.call(Vector3(0.7, 0.3, 0.04), Vector3(-0.48, 10.95, 0.19 * face), yellow))
			mast.append(B.call(Vector3(0.7, 0.3, 0.04), Vector3(0.48, 10.95, 0.19 * face), yellow))
		_stand(mast, Vector3(sg2[0], _ground(sg2[0], sg2[1]), sg2[1]), Basis(Vector3.UP, 0.6), "McDonaldsSign")
	for s in sites.get("forecourt", []):
		# a petrol station's forecourt: a flat roof on four columns over two islands of pumps
		var c: Array = s["at"]
		var al := Vector3(s["along"][0], 0, s["along"][1])
		var bs2 := Basis(al, Vector3.UP, al.cross(Vector3.UP))
		var at2 := Vector3(c[0], _ground(c[0], c[2]), c[2])
		var parts2 := [B.call(Vector3(16.0, 0.55, 9.0), Vector3(0, 5.0, 0), white), B.call(Vector3(16.1, 0.22, 9.1), Vector3(0, 4.80, 0), red),
			B.call(Vector3(16.1, 0.10, 9.1), Vector3(0, 5.22, 0), yellow)]
		for sx in [-5.5, 5.5]:
			for sz in [-2.6, 2.6]:
				parts2.append(B.call(Vector3(0.35, 4.75, 0.35), Vector3(sx, 2.37, sz), white))
		for sz2 in [-2.6, 2.6]:
			parts2.append(B.call(Vector3(9.5, 0.16, 1.2), Vector3(0, 0.08, sz2), concrete))                # the island
			for px in [-3.0, 0.0, 3.0]:
				parts2.append(B.call(Vector3(1.0, 1.55, 0.55), Vector3(px, 0.93, sz2), white))             # a pump
				parts2.append(B.call(Vector3(1.02, 0.30, 0.57), Vector3(px, 1.55, sz2), red))
				for face2 in [-1.0, 1.0]:
					parts2.append(B.call(Vector3(0.62, 0.34, 0.02), Vector3(px, 1.18, sz2 + 0.285 * face2), Color(0.06, 0.07, 0.08)))      # the display
					parts2.append(B.call(Vector3(0.07, 0.42, 0.07), Vector3(px + 0.40, 0.80, sz2 + 0.31 * face2), Color(0.05, 0.05, 0.05)))   # the nozzle in its holster
					parts2.append(B.call(Vector3(0.07, 0.42, 0.07), Vector3(px - 0.40, 0.80, sz2 + 0.31 * face2), Color(0.10, 0.40, 0.15)))
			parts2.append(B.call(Vector3(0.5, 0.9, 0.5), Vector3(4.4, 0.61, sz2), Color(0.12, 0.25, 0.50)))   # the bin and the bucket for the windscreen
		var roof := _stand(parts2, at2, bs2, "Forecourt")
		for face3 in [-1.0, 1.0]:
			_words(str(s["name"]).to_upper(), Vector3(0, 5.0, 4.52 * face3), Vector3(0, 0, face3), 0.40, red, roof)
		# the price sign on its mast
		var mast2 := [B.call(Vector3(0.3, 6.0, 0.3), Vector3(0, 3.0, 0), white), B.call(Vector3(1.8, 1.4, 0.3), Vector3(0, 6.6, 0), yellow), B.call(Vector3(1.8, 2.2, 0.28), Vector3(0, 4.7, 0), Color(0.08, 0.08, 0.09))]
		for row2 in 3:
			for face4 in [-1.0, 1.0]:
				mast2.append(B.call(Vector3(1.4, 0.42, 0.02), Vector3(0, 5.4 - 0.65 * float(row2), 0.15 * face4), Color(0.85, 0.20, 0.10) if row2 == 0 else white))
		_stand(mast2, at2 + bs2 * Vector3(10.5, 0, 6.5), bs2, "PriceSign")
	for s in sites.get("doors", []):
		# the tall doors of a fire station: ribbed, with a row of windows across each
		var colr := Color(s["colour"][0], s["colour"][1], s["colour"][2])
		var wide: float = s["wide"]
		var tall: float = s["tall"]
		for dq in s["doors"]:
			var nn := Vector3(dq[3], 0, dq[4])
			var bs3 := Basis(Vector3.UP.cross(nn), Vector3.UP, nn)
			var parts3 := [B.call(Vector3(wide + 0.3, tall + 0.15, 0.30), Vector3(0, (tall + 0.15) * 0.5, 0.03), Color(0.25, 0.25, 0.26)), B.call(Vector3(wide, tall, 0.30), Vector3(0, tall * 0.5, 0.06), colr)]      # (standing out past the band between the storeys: it ran across the doors)
			for k2 in 7:
				parts3.append(B.call(Vector3(wide, 0.03, 0.02), Vector3(0, tall * (float(k2) + 1.0) / 8.0, 0.215), colr.darkened(0.35)))
			for w2 in 4:
				parts3.append(B.call(Vector3(wide / 4.0 - 0.18, tall / 8.0 - 0.14, 0.02), Vector3(-wide * 0.375 + wide * 0.25 * float(w2), tall * 5.5 / 8.0, 0.22), Color(0.10, 0.13, 0.16)))
			parts3.append(B.call(Vector3(wide + 1.0, 0.04, 3.0), Vector3(0, 0.03, 1.6), Color(0.45, 0.45, 0.46)))            # the apron in front
			_stand(parts3, Vector3(dq[0], dq[1], dq[2]), bs3, "FireDoor", false)
		if not (s["doors"] as Array).is_empty():
			var d0: Array = s["doors"][(s["doors"] as Array).size() / 2]
			var n0 := Vector3(d0[3], 0, d0[4])
			_words("BRANNSTASJON", Vector3(d0[0], float(d0[1]) + tall + 1.0, d0[2]) + n0 * 0.14, n0, 0.75, red)
	for s in sites.get("tower", []):
		# a fire station's hose tower: tall and square, louvres under its flat cap, a door at its foot
		var tc: Array = s["at"]
		var to := Vector3(s["out"][0], 0, s["out"][1])
		var tb := Basis(Vector3.UP.cross(to), Vector3.UP, to)
		var sd: float = s["side"]
		var th: float = s["tall"]
		var tcol := Color(s["colour"][0], s["colour"][1], s["colour"][2])
		var tparts := [B.call(Vector3(sd, th, sd), Vector3(0, th * 0.5, 0), tcol), B.call(Vector3(sd + 0.5, 0.25, sd + 0.5), Vector3(0, th + 0.12, 0), Color(0.25, 0.25, 0.26)),
			B.call(Vector3(sd + 0.06, 0.5, sd + 0.06), Vector3(0, 0.25, 0), Color(0.40, 0.40, 0.41)), B.call(Vector3(1.0, 2.1, 0.08), Vector3(0, 1.05, sd * 0.5 + 0.02), red.darkened(0.2)),
			B.call(Vector3(0.10, 3.0, 0.10), Vector3(0.8, th + 1.7, 0.8), steel)]
		for face in 4:
			var fb := Basis(Vector3.UP, PI * 0.5 * float(face))
			for k3 in 6:
				tparts.append(B.call(Vector3(sd * 0.62, 0.10, 0.06), fb * Vector3(0, th - 0.8 - 0.28 * float(k3), sd * 0.5 + 0.02), Color(0.30, 0.31, 0.33), fb))
			for k4 in 3:
				tparts.append(B.call(Vector3(0.7, 1.1, 0.05), fb * Vector3(0, 4.0 + 3.2 * float(k4), sd * 0.5 + 0.01), Color(0.10, 0.13, 0.16), fb))
		_stand(tparts, Vector3(tc[0], tc[1], tc[2]), tb, "HoseTower")
	for s in sites.get("wall_sign", []):
		# a name on a wall: letters, on a coloured board if it has one; over a way in, glass doors under a canopy
		var wc: Array = s["at"]
		var wo := Vector3(s["out"][0], 0, s["out"][1])
		var wb := Basis(Vector3.UP.cross(wo), Vector3.UP, wo)
		var letters: float = s["tall"]
		var ink := Color(s["ink"][0], s["ink"][1], s["ink"][2])
		var text: String = s["text"]
		var wide2 := letters * 0.62 * float(text.length()) + letters * 0.9
		var wparts := []
		if s["back"] != null:
			wparts.append(B.call(Vector3(wide2, letters * 1.7, 0.16), Vector3(0, float(s["up"]), 0.10), Color(s["back"][0], s["back"][1], s["back"][2])))
		if s["door"]:
			wparts.append(B.call(Vector3(wide2 + 1.0, 0.22, 2.6), Vector3(0, 3.3, 1.3), Color(0.30, 0.31, 0.33)))                 # the canopy
			wparts.append(B.call(Vector3(4.4, 3.0, 0.14), Vector3(0, 1.5, 0.08), Color(0.22, 0.23, 0.25)))                        # the door frame
			for leaf in [-1.05, 1.05]:
				wparts.append(B.call(Vector3(1.95, 2.7, 0.06), Vector3(leaf, 1.4, 0.17), Color(0.10, 0.14, 0.17)))
			wparts.append(B.call(Vector3(0.06, 2.7, 0.08), Vector3(0, 1.4, 0.19), Color(0.75, 0.76, 0.78)))
			for post in [-wide2 * 0.5 - 0.3, wide2 * 0.5 + 0.3]:
				wparts.append(B.call(Vector3(0.16, 3.2, 0.16), Vector3(post, 1.6, 2.4), Color(0.30, 0.31, 0.33)))
			wparts.append(B.call(Vector3(4.6, 0.04, 2.6), Vector3(0, 0.03, 1.3), Color(0.45, 0.45, 0.46)))
		var wmi: MeshInstance3D = null
		if not wparts.is_empty():
			wmi = _stand(wparts, Vector3(wc[0], wc[1], wc[2]), wb, "WallSign", s["door"])
		_words(text, Vector3(wc[0], float(wc[1]) + float(s["up"]), wc[2]) + wo * (0.20 if s["back"] != null else 0.12), wo, letters, ink)
	for s in sites.get("construction", []):
		_building_site(s)
	for s in sites.get("rose_round", []):
		# a round bed of roses, flat on the ground (the island of a roundabout)
		var rng := RandomNumberGenerator.new()
		rng.seed = 2611
		var rr: float = s[2]
		var y0 := _ground(s[0], s[1])
		var bed := [world.props._cyl(rr, rr + 0.05, 0.16, 28, Vector3(0, 0.08, 0), Color(0.16, 0.12, 0.09)), world.props._cyl(rr - 0.25, rr - 0.1, 0.34, 28, Vector3(0, 0.30, 0), Color(0.13, 0.30, 0.12))]
		for i2 in int(rr * rr * 3.14 * 14.0):
			var ang := rng.randf() * TAU
			var rad := sqrt(rng.randf()) * (rr - 0.35)
			var pick := rng.randf()
			var colb := Color(0.72, 0.05, 0.08) if pick < 0.7 else (Color(0.90, 0.45, 0.55) if pick < 0.88 else Color(0.93, 0.90, 0.84))
			var sz3 := rng.randf_range(0.07, 0.11)
			bed.append(B.call(Vector3(sz3, sz3 * 0.8, sz3), Vector3(cos(ang) * rad, 0.50 + rng.randf_range(0.0, 0.10), sin(ang) * rad), colb))
		_stand(bed, Vector3(s[0], y0, s[1]), Basis.IDENTITY, "RoseRound", false)


## A building going up: so far its concrete floors on their columns, three storeys, a stair between them, props
## under the newest slab, a fence along the street with a board on it. People in yellow vests work there
## (scripts/people.gd reads `work_spots`).
var work_spots: Array = []
func _building_site(s: Dictionary) -> void:
	var B: Callable = world.props._box
	var box: Array = s["box"]
	var x0: float = box[0]
	var z0: float = box[1]
	var x1: float = box[2]
	var z1: float = box[3]
	var y: float = s["y"]
	var raw := Color(0.63, 0.63, 0.61)
	var parts := [B.call(Vector3(x1 - x0, 0.5, z1 - z0), Vector3((x0 + x1) * 0.5, y - 0.10, (z0 + z1) * 0.5), raw)]     # the ground slab
	var floors: int = s["floors"]
	var nx := maxi(2, int(round((x1 - x0) / 5.0)) + 1)
	var nz := maxi(2, int(round((z1 - z0) / 5.0)) + 1)
	for f in floors:
		var top := y + 0.15 + 3.3 * float(f + 1)
		var hole := f < floors            # a stair well in the corner
		parts.append(B.call(Vector3(x1 - x0 - 3.2, 0.26, z1 - z0), Vector3((x0 + x1) * 0.5 + 1.6, top - 0.13, (z0 + z1) * 0.5), raw))
		parts.append(B.call(Vector3(3.2, 0.26, z1 - z0 - 5.0), Vector3(x0 + 1.6, top - 0.13, (z0 + z1) * 0.5 - 2.5), raw))
		for i in nx:
			for j in nz:
				var cx := lerpf(x0 + 0.35, x1 - 0.35, float(i) / float(nx - 1))
				var cz := lerpf(z0 + 0.35, z1 - 0.35, float(j) / float(nz - 1))
				parts.append(B.call(Vector3(0.38, 3.04, 0.38), Vector3(cx, top - 0.26 - 1.52, cz), raw))
				if f == floors - 1:                                                      # reinforcing bars standing out of the top, for the next storey
					for q in 4:
						parts.append(B.call(Vector3(0.025, 1.1, 0.025), Vector3(cx + (0.12 if q % 2 == 0 else -0.12), top + 0.55, cz + (0.12 if q < 2 else -0.12)), Color(0.42, 0.22, 0.14)))
		# the stair up to this floor: twelve concrete steps along the front in the well
		for k in 12:
			parts.append(B.call(Vector3(1.2, 0.275 * float(k + 1), 0.30), Vector3(x0 + 0.9, top - 3.3 + 0.1375 * float(k + 1), z1 - 0.6 - 0.30 * float(k)), raw))
		# an edge rail of timber round each floor
		for side in [[Vector3((x0 + x1) * 0.5, top + 1.0, z1 - 0.06), Vector3(x1 - x0, 0.10, 0.04)], [Vector3((x0 + x1) * 0.5, top + 0.5, z1 - 0.06), Vector3(x1 - x0, 0.10, 0.04)]]:
			parts.append(B.call(side[1], side[0], Color(0.72, 0.58, 0.36)))
		for i3 in nx * 2 - 1:
			parts.append(B.call(Vector3(0.06, 1.05, 0.06), Vector3(lerpf(x0 + 0.1, x1 - 0.1, float(i3) / float(nx * 2 - 2)), top + 0.52, z1 - 0.06), Color(0.72, 0.58, 0.36)))
	# steel props under the top slab, a stack of formwork boards, a pallet of blocks, a cement mixer's worth of clutter
	var top2 := y + 0.15 + 3.3 * float(floors)
	for i4 in 6:
		parts.append(B.call(Vector3(0.07, 3.0, 0.07), Vector3(lerpf(x0 + 4.5, x1 - 1.5, float(i4) / 5.0), top2 - 0.26 - 1.52, (z0 + z1) * 0.5 + (1.2 if i4 % 2 == 0 else -1.4)), Color(0.75, 0.20, 0.12)))
	parts.append(B.call(Vector3(2.4, 0.5, 1.2), Vector3(x1 - 2.2, y + 0.40, z1 - 2.0), Color(0.80, 0.66, 0.40)))
	parts.append(B.call(Vector3(1.2, 0.9, 1.0), Vector3(x1 - 2.4, y + 0.60, z0 + 2.0), Color(0.55, 0.55, 0.54)))
	parts.append(B.call(Vector3(1.2, 0.14, 1.0), Vector3(x1 - 2.4, y + 0.22, z0 + 2.0), Color(0.60, 0.48, 0.30)))
	_stand(parts, Vector3.ZERO, Basis.IDENTITY, "BuildingSite")
	# the fence along the street: mesh panels on concrete feet, a gap for the gate; a board
	var fence := []
	var count := int((x1 - x0) / 2.2)
	for i5 in count:
		if i5 == count / 2:
			continue                                                                    # the gate stands open
		var fx := x0 + 1.1 + 2.2 * float(i5) + ((x1 - x0) - 2.2 * float(count)) * 0.5
		fence.append(B.call(Vector3(2.1, 1.9, 0.03), Vector3(fx, y + 1.15, z1 + 0.9), Color(0.62, 0.64, 0.66)))
		fence.append(B.call(Vector3(0.6, 0.14, 0.24), Vector3(fx - 1.05, y + 0.20, z1 + 0.9), raw))
		fence.append(B.call(Vector3(0.05, 2.0, 0.05), Vector3(fx - 1.05, y + 1.15, z1 + 0.9), Color(0.45, 0.47, 0.50)))
	fence.append(B.call(Vector3(1.6, 1.0, 0.04), Vector3(x0 + 2.2, y + 1.3, z1 + 0.93), Color(0.96, 0.80, 0.10)))
	var fmi := _stand(fence, Vector3.ZERO, Basis.IDENTITY, "SiteFence")
	_words("BYGGEPLASS", Vector3(x0 + 2.2, y + 1.48, z1 + 0.96), Vector3.BACK, 0.20, Color(0.05, 0.05, 0.05), fmi)
	_words("Adgang forbudt", Vector3(x0 + 2.2, y + 1.14, z1 + 0.96), Vector3.BACK, 0.13, Color(0.05, 0.05, 0.05), fmi)
	# where the workers stand: on the ground slab, on the first floor, by the gate
	for q2 in [Vector3(lerpf(x0, x1, 0.45), y + 0.15, lerpf(z0, z1, 0.6)), Vector3(lerpf(x0, x1, 0.7), y + 0.15, lerpf(z0, z1, 0.35)), Vector3(lerpf(x0, x1, 0.6), y + 3.45, lerpf(z0, z1, 0.7)),
			Vector3(lerpf(x0, x1, 0.35), y + 3.45, lerpf(z0, z1, 0.4)), Vector3(lerpf(x0, x1, 0.8), y + 6.75, lerpf(z0, z1, 0.5)), Vector3((x0 + x1) * 0.5 + 1.5, y + 0.15, z1 + 0.3)]:
		work_spots.append(q2)
		people.add_worker(q2, float(work_spots.size()) * 1.9, (work_spots.size() - 1) % 3)


## Rose beds: along Storgata, on the sidewalk every 30 m or so, one side and then the other.
func _roses(mesh: Mesh) -> void:
	var at: Array = []
	var side := 1.0
	for way in world.detail.ways:
		if way[1] != 0:
			continue
		var pts: PackedVector2Array = way[3]
		var mid := pts[pts.size() / 2]
		if world.locate(mid.x, mid.y)["street"] != "Storgata":
			continue
		var nrm: PackedVector2Array = way[4]
		var k := 5
		while k < pts.size() - 2:
			var has_walk: bool = (way[5] as PackedByteArray)[k] == 1 if side > 0.0 else (way[6] as PackedByteArray)[k] == 1
			if has_walk:
				var p: Vector2 = pts[k] + nrm[k] * side * (float(way[0]) + 0.75)
				at.append(Vector3(p.x, 0, p.y))
			side = -side
			k += 10
	# (none round Rådhusplassen any more: they stood scattered about the square. Note of 18 Nov.)
	var keep: Array = []
	var space := get_world_3d().direct_space_state if is_inside_tree() else null
	for p in at:
		var y: float = world.height_at(p.x, p.z)
		if y < 1.0 or not is_nan(world.detail.surface_at(p.x, p.z)):
			continue                                            # not in the water, not on the carriageway
		keep.append(Vector3(p.x, y + 0.23 if world.cover_at(p.x, p.z)["road"] < 0.8 else y, p.z))
	if keep.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = keep.size()
	for i in keep.size():
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, i * 1.7), keep[i]))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Roses"
	mi.multimesh = mm
	add_child(mi)
	roses = keep.size()


## A board on two posts, with a heading and a few lines.
func _board(at: Vector3, face: float, title: String, text: String, colour: Color, parent: Node3D = null) -> void:
	var root := Node3D.new()
	root.position = at
	root.rotation.y = face
	(parent if parent != null else self).add_child(root)
	var mesh: ArrayMesh = world._merge([
		world.props._box(Vector3(3.7, 1.3, 0.06), Vector3(0, 1.75, 0), colour),
		world.props._box(Vector3(0.08, 2.4, 0.08), Vector3(-1.65, 1.2, 0.02), Color(0.3, 0.3, 0.32)),
		world.props._box(Vector3(0.08, 2.4, 0.08), Vector3(1.65, 1.2, 0.02), Color(0.3, 0.3, 0.32))])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	root.add_child(mi)
	var head := Label3D.new()
	head.text = title
	head.font_size = 56
	head.pixel_size = 0.0042
	head.position = Vector3(0, 2.18, -0.04)
	head.rotation.y = PI
	head.modulate = Color(1.0, 0.86, 0.5)
	head.outline_size = 0
	root.add_child(head)
	var body := Label3D.new()
	body.text = text
	body.font_size = 30
	body.pixel_size = 0.0042
	body.position = Vector3(0, 1.62, -0.04)
	body.rotation.y = PI
	body.outline_size = 0
	root.add_child(body)


func _process(delta: float) -> void:
	var t0_ := Time.get_ticks_usec()
	_run(delta)
	if world != null:
		world.took("molde", t0_)


func _run(delta: float) -> void:
	_tick -= delta
	if _tick > 0.0 or daytime == null:
		return
	_tick = 2.0
	_match(match_day)
	var on: bool = daytime.day >= JAZZ_FROM and daytime.day <= JAZZ_TO
	if on != festival:
		festival = on
		if on and _jazz == null:
			_build_jazz()
		if _jazz != null:
			_jazz.visible = on
		people.festival = on


## A match day at Aker Stadion (the menu): the floodlights on over the pitch, more people about near the
## stadium, and the sound of the crowd, heard from far across the town.
var match_day := false
var _match_on := false
var _match_root: Node3D


func _match(on: bool) -> void:
	if on == _match_on:
		return
	_match_on = on
	var st: Dictionary = world.meta.get("stadium", {})
	var outline: Array = st.get("outline", [])
	if outline.size() < 6:
		return
	var lo := Vector2(1e9, 1e9)
	var hi := Vector2(-1e9, -1e9)
	for i in outline.size() / 2:
		lo = lo.min(Vector2(outline[2 * i], outline[2 * i + 1]))
		hi = hi.max(Vector2(outline[2 * i], outline[2 * i + 1]))
	var mid := (lo + hi) * 0.5
	people.crowd_at = mid if on else null
	if _match_root == null and on:
		_match_root = Node3D.new()
		_match_root.name = "MatchDay"
		add_child(_match_root)
		var y: float = float(st.get("y", world.height_at(mid.x, mid.y)))
		for corner in [Vector2(lo.x, lo.y), Vector2(hi.x, lo.y), Vector2(lo.x, hi.y), Vector2(hi.x, hi.y)]:
			var c: Vector2 = corner
			var lamp := SpotLight3D.new()
			lamp.light_energy = 28.0
			lamp.spot_range = 190.0
			lamp.spot_angle = 48.0
			lamp.light_color = Color(0.92, 0.96, 1.0)
			lamp.shadow_enabled = false
			lamp.position = Vector3(c.x, y + 34.0, c.y)
			_match_root.add_child(lamp)
			lamp.look_at(Vector3(mid.x, y, mid.y))
			var glow := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(7.0, 3.0, 0.6)
			var gm := StandardMaterial3D.new()
			gm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			gm.albedo_color = Color(1.0, 1.0, 0.95)
			gm.emission_enabled = true
			gm.emission = Color(1.0, 1.0, 0.95)
			gm.emission_energy_multiplier = 6.0
			bm.material = gm
			glow.mesh = bm
			glow.position = lamp.position
			_match_root.add_child(glow)
			glow.look_at(Vector3(mid.x, y, mid.y))
		var main_snd = get_parent().get("sound")
		if main_snd != null:
			var voice := AudioStreamPlayer3D.new()
			voice.stream = main_snd._stream("crowd", true)
			voice.unit_size = 60.0
			voice.max_distance = 1800.0
			voice.volume_db = 4.0
			voice.position = Vector3(mid.x, y + 12.0, mid.y)
			voice.name = "Crowd"
			_match_root.add_child(voice)
	if _match_root != null:
		_match_root.visible = on
		var v = _match_root.get_node_or_null("Crowd")
		if v != null:
			if on:
				(v as AudioStreamPlayer3D).play()
			else:
				(v as AudioStreamPlayer3D).stop()


## The festival on Rådhusplassen: a stage at the town hall end, banners round the square, and bunting.
func _build_jazz() -> void:
	_jazz = Node3D.new()
	_jazz.name = "Moldejazz"
	add_child(_jazz)
	var s: Vector2 = world.spawn
	var c := Vector3(s.x + 2.0, world.height_at(s.x + 2.0, s.y - 9.0), s.y - 9.0)        # north of the spawn point, toward the town hall
	var black := Color(0.06, 0.06, 0.07)
	var blue := Color(0.07, 0.16, 0.42)
	var parts := [
		world.props._box(Vector3(11.0, 1.1, 6.0), Vector3(0, 0.55, 0), black),
		world.props._box(Vector3(11.4, 0.25, 6.6), Vector3(0, 6.2, 0), black),
		world.props._box(Vector3(11.0, 5.0, 0.12), Vector3(0, 3.6, -2.9), blue)]
	for sx in [-5.4, 5.4]:
		for sz in [-2.9, 2.9]:
			parts.append(world.props._box(Vector3(0.22, 6.2, 0.22), Vector3(sx, 3.1, sz), Color(0.55, 0.56, 0.58)))
	for k in 4:                                             # speakers and a drum riser
		parts.append(world.props._box(Vector3(0.9, 1.5, 0.8), Vector3(-4.6 + 3.07 * k, 1.85, 2.2), black))
	parts.append(world.props._box(Vector3(2.4, 0.4, 2.0), Vector3(0, 1.3, -1.4), Color(0.2, 0.2, 0.22)))
	var stage := MeshInstance3D.new()
	stage.mesh = world._merge(parts)
	stage.position = c
	_jazz.add_child(stage)
	var body := StaticBody3D.new()
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(11.0, 1.1, 6.0)
	shape.shape = box
	shape.position = Vector3(0, 0.55, 0)
	body.add_child(shape)
	stage.add_child(body)
	var name := Label3D.new()
	name.text = "MOLDEJAZZ"
	name.font_size = 220
	name.pixel_size = 0.006
	name.position = c + Vector3(0, 4.4, -2.8)
	name.modulate = Color(1.0, 0.86, 0.5)
	name.outline_size = 0
	_jazz.add_child(name)
	# banners round the square, and bunting from the stage to two masts
	for q in [Vector2(-9.0, 4.0), Vector2(11.0, 4.0), Vector2(-10.0, 16.0), Vector2(12.0, 16.0), Vector2(-9.0, 27.0), Vector2(11.0, 27.0)]:
		var at := Vector3(c.x + q.x, 0, c.z + q.y)
		at.y = world.height_at(at.x, at.z)
		var banner := MeshInstance3D.new()
		banner.mesh = world._merge([
			world.props._box(Vector3(0.07, 5.0, 0.07), Vector3(0, 2.5, 0), Color(0.5, 0.5, 0.52)),
			world.props._box(Vector3(0.9, 3.0, 0.03), Vector3(0.5, 3.4, 0), blue)])
		banner.position = at
		_jazz.add_child(banner)
		var txt := Label3D.new()
		txt.text = "M\nO\nL\nD\nE\nJ\nA\nZ\nZ"
		txt.font_size = 44
		txt.line_spacing = -16.0
		txt.pixel_size = 0.0065
		txt.position = at + Vector3(0.5, 3.4, 0.03)
		txt.modulate = Color(1.0, 0.86, 0.5)
		txt.outline_size = 0
		txt.double_sided = true
		_jazz.add_child(txt)
	var flags := []
	var cols := [Color(0.85, 0.15, 0.15), Color(0.95, 0.80, 0.25), Color(0.15, 0.35, 0.75), Color(0.92, 0.92, 0.9)]
	for side in [-1.0, 1.0]:
		for k in 22:
			var t := (k + 0.5) / 22.0
			var p := Vector3(side * 5.4, 6.3, 3.0).lerp(Vector3(side * 11.0, 5.0, 30.0), t) - Vector3(0, sin(t * PI) * 1.2, 0)
			flags.append(world.props._box(Vector3(0.02, 0.38, 0.30), p, cols[k % 4]))
	var bunting := MeshInstance3D.new()
	bunting.mesh = world._merge(flags)
	bunting.position = c
	_jazz.add_child(bunting)
	if not _crowd_added:
		_crowd_added = true
		var rng := RandomNumberGenerator.new()
		rng.seed = 5
		for i in 46:                                        # the crowd: in front of the stage, facing it
			var q := Vector3(c.x + rng.randf_range(-7.0, 7.0), 0, c.z + rng.randf_range(5.0, 17.0))
			var clear := true
			for v in player.vehicles:                           # (not on top of what is parked on the square)
				if Vector2(v.global_position.x - q.x, v.global_position.z - q.z).length() < 3.2:
					clear = false
			if clear:
				people.add_spot(q, PI + rng.randf_range(-0.2, 0.2), "standing")
