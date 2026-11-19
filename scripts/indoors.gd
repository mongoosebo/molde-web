extends Node
## A way in (the plan of 18 November, 7.3). At the wall of Molde Storsenter, E takes the walker inside: one
## hall with the centre's shops along both sides, benches and planters down the middle, and the way out at the
## end. The hall is not inside the building's block on the map (that is solid): it is a room of its own, built
## the first time it is entered and kept high over the place, out of sight, and the walker is put there and
## back. Rain, snow and breath stop at the door (scripts/weather.gd reads `inside`).
## The other two ways in the plan names need no room: the stadium has open gates in the middle of each side,
## and the ferry is boarded from the quay (scripts/jobs.gd).

const UP := 420.0                        # how high over the ground the hall is kept
const HALL := Vector3(36.0, 5.2, 15.0)   # long, high, wide

var main
var world
var player
var inside := false
var places: Array = []                   # {"name", "at": Vector2 (the middle of the building), "reach", "shops": [names]}
var _room: Node3D
var _room_of := -1
var _near := -1
var _came_from := Vector3.ZERO
var _layer: CanvasLayer
var _prompt: Label
var _tick := 0.0


func setup(m) -> void:
	main = m
	world = m.world
	player = m.player
	# Molde Storsenter: where the map has its shops
	var mid := Vector2.ZERO
	var n := 0
	var shops: Array = []
	var points: Array = []
	for p in world.meta.get("pois", []):
		if String(p["name"]).to_lower().contains("storsenter"):
			mid += Vector2(p["x"], p["z"])
			n += 1
	if n > 0:
		mid /= float(n)
		for p in world.meta.get("pois", []):
			var nm := String(p["name"])
			if nm != "" and Vector2(p["x"], p["z"]).distance_to(mid) < 70.0 and not ["bench", "parking", "bicycle_parking", "waste_basket", "post_box", "recycling", "toilets", "vending_machine", "atm", "charging_station"].has(String(p["kind"])):
				nm = nm.replace(" Molde Storsenter", "").replace(" storsenter", "").replace(" Molde", "").replace(" Molde storsenter", "").replace(" Molde, Storsenter", "").replace(", Storsenter", "")
				if String(p["name"]).to_lower().contains("storsenter"):
					points.append(Vector2(p["x"], p["z"]))
				if not shops.has(nm):
					shops.append(nm)
		places.append({"name": "Molde Storsenter", "at": mid, "points": points, "shops": shops})
	_layer = CanvasLayer.new()
	_layer.layer = 2
	add_child(_layer)
	_prompt = Label.new()
	_prompt.add_theme_font_size_override("font_size", 20)
	_prompt.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_prompt.add_theme_constant_override("shadow_offset_x", 1)
	_prompt.add_theme_constant_override("shadow_offset_y", 1)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	_layer.add_child(_prompt)


## Standing at the wall of a place with a way in? Its index, or -1. The place's walls are the outlines of the
## buildings its shops lie in (found the first time it is asked for).
func _at_door() -> int:
	if player.driving:
		return -1
	var pp := Vector2(player.global_position.x, player.global_position.z)
	for k in places.size():
		var pl: Dictionary = places[k]
		if pp.distance_to(pl["at"]) > 200.0:
			continue
		if not pl.has("walls"):
			var walls: Array = []
			var c: Vector2i = world.detail.cell_of((pl["at"] as Vector2).x, (pl["at"] as Vector2).y)
			for dz in [-1, 0, 1]:
				for dx in [-1, 0, 1]:
					for rec in world.detail.buildings.get(Vector2i(c.x + dx, c.y + dz), []):
						var poly: PackedVector2Array = rec["poly"]
						for q in pl["points"]:
							if Geometry2D.is_point_in_polygon(q, poly):
								if not walls.has(poly):
									walls.append(poly)
								break
			pl["walls"] = walls
		for poly in pl["walls"]:
			var ring: PackedVector2Array = poly
			if Geometry2D.is_point_in_polygon(pp, ring):
				continue
			for i in ring.size():
				var near := Geometry2D.get_closest_point_to_segment(pp, ring[i], ring[(i + 1) % ring.size()])
				if near.distance_to(pp) < 2.2:
					return k
	return -1


func _physics_process(delta: float) -> void:
	if player == null:
		return
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		_near = -1 if inside else _at_door()
	if inside:
		# (the hall is the whole world while in it: nothing of the map needs to follow)
		var exit_at: Vector3 = _room.global_position + Vector3(-HALL.x * 0.5 + 1.5, 0.0, 0.0)
		_near = 0 if player.global_position.distance_to(exit_at) < 4.5 else -1
		if player.global_position.y < _room.global_position.y - 3.0:          # (fell out of it somehow: out)
			leave()


func _process(_delta: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	_prompt.position = Vector2(0.0, vs.y * 0.775)
	_prompt.size = Vector2(vs.x, 30.0)
	var busy: bool = main.jobs != null and (main.jobs._prompt.visible or main.jobs.journal_open() or not main.jobs.active.is_empty())
	var text := ""
	if inside and _near >= 0:
		text = "E  —  go out"
	elif not inside and _near >= 0 and not busy:
		text = "E  —  go into %s" % places[_near]["name"]
	_prompt.text = text
	_prompt.visible = text != ""
	if text != "" and Input.is_action_just_pressed("job"):
		if inside:
			leave()
		else:
			enter(_near)


func enter(k: int) -> void:
	if inside or k < 0 or k >= places.size():
		return
	_came_from = player.global_position
	if _room == null or _room_of != k:
		if _room != null:
			_room.queue_free()
		_room = _build(places[k])
		_room_of = k
		add_child(_room)
	var at: Vector2 = places[k]["at"]
	_room.global_position = Vector3(at.x, world.height_at(at.x, at.y) + UP, at.y)
	_room.visible = true
	inside = true
	if main.weather != null:
		main.weather.indoors = true
	player.global_position = _room.global_position + Vector3(-HALL.x * 0.5 + 3.0, 0.3, 0.0)
	player.velocity = Vector3.ZERO
	player.yaw = -PI * 0.5                           # looking down the hall
	player.reset_physics_interpolation()
	_near = -1
	_tick = 0.5


func leave() -> void:
	if not inside:
		return
	inside = false
	if main.weather != null:
		main.weather.indoors = false
	player.global_position = _came_from + Vector3(0, 0.2, 0)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	world.update_streaming(player.global_position)
	if _room != null:
		_room.visible = false
	_near = -1
	_tick = 0.5


# ------------------------------------------------------------------ the hall
func _mat(color: Color, rough := 0.8, glow := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	if glow > 0.0:
		m.emission_enabled = true
		m.emission = color
		m.emission_energy_multiplier = glow
	return m


func _slab(root: Node3D, size: Vector3, at: Vector3, mat: Material, solid := true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = at
	root.add_child(mi)
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var sh := BoxShape3D.new()
		sh.size = size
		cs.shape = sh
		body.add_child(cs)
		body.position = at
		root.add_child(body)
	return mi


func _sign(root: Node3D, text: String, at: Vector3, turn: float, size: float, color: Color) -> void:
	var l := Label3D.new()
	l.text = text
	l.font_size = 64
	l.pixel_size = size / 64.0
	l.modulate = color
	l.outline_size = 0
	l.shaded = false
	l.double_sided = false
	l.position = at
	l.rotation.y = turn
	root.add_child(l)


func _build(place: Dictionary) -> Node3D:
	var root := Node3D.new()
	root.name = "Hall"
	var L := HALL.x
	var H := HALL.y
	var W := HALL.z
	var floor_m := _mat(Color(0.74, 0.72, 0.68), 0.35)
	var wall_m := _mat(Color(0.90, 0.89, 0.86))
	var ceil_m := _mat(Color(0.95, 0.95, 0.94))
	var dark_m := _mat(Color(0.16, 0.16, 0.17), 0.5)
	_slab(root, Vector3(L + 2.0, 0.4, W + 2.0), Vector3(0, -0.2, 0), floor_m)
	_slab(root, Vector3(L + 2.0, 0.4, W + 2.0), Vector3(0, H + 0.2, 0), ceil_m)
	_slab(root, Vector3(0.4, H, W + 2.0), Vector3(-L * 0.5 - 0.2, H * 0.5, 0), wall_m)
	_slab(root, Vector3(0.4, H, W + 2.0), Vector3(L * 0.5 + 0.2, H * 0.5, 0), wall_m)
	_slab(root, Vector3(L + 2.0, H, 0.4), Vector3(0, H * 0.5, -W * 0.5 - 0.2), wall_m)
	_slab(root, Vector3(L + 2.0, H, 0.4), Vector3(0, H * 0.5, W * 0.5 + 0.2), wall_m)
	# a darker band of tiles down the middle of the floor
	_slab(root, Vector3(L - 4.0, 0.02, 2.4), Vector3(0, 0.01, 0), _mat(Color(0.52, 0.50, 0.47), 0.35), false)
	# light: panels in the ceiling, and a lamp under every other one
	var panel_m := _mat(Color(1.0, 0.97, 0.90), 0.5, 2.2)
	var count := 6
	for i in count:
		var x := -L * 0.5 + (i + 0.5) * L / count
		_slab(root, Vector3(3.2, 0.06, 1.2), Vector3(x, H - 0.03, 0), panel_m, false)
		var lamp := OmniLight3D.new()
		lamp.position = Vector3(x, H - 0.8, 0)
		lamp.omni_range = 13.0
		lamp.light_energy = 1.5
		lamp.light_color = Color(1.0, 0.96, 0.88)
		lamp.shadow_enabled = false
		root.add_child(lamp)
	# the shops: a front of glass with a sign over it, along both long walls
	var shops: Array = (place["shops"] as Array).duplicate()
	for more in ["Kaffebar", "Blomster", "Bokhandel", "Sport", "Frisør", "Klær"]:
		if shops.size() < 10:
			shops.append(more)
	var bays := 5
	var bay := (L - 6.0) / bays
	var tints := [Color(0.80, 0.16, 0.16), Color(0.12, 0.35, 0.62), Color(0.15, 0.45, 0.30), Color(0.85, 0.55, 0.10), Color(0.35, 0.22, 0.50),
		Color(0.10, 0.10, 0.12), Color(0.75, 0.20, 0.45), Color(0.10, 0.45, 0.50), Color(0.55, 0.35, 0.18), Color(0.25, 0.30, 0.38)]
	for side in 2:
		var z := (-W * 0.5 if side == 0 else W * 0.5)
		var inward := (1.0 if side == 0 else -1.0)
		for i in bays:
			var k := side * bays + i
			var x := -L * 0.5 + 4.5 + (i + 0.5) * bay
			var tint: Color = tints[k % tints.size()]
			# the lit shop behind the glass, the glass, the sign band, and a pier between two shops
			_slab(root, Vector3(bay - 0.5, 3.0, 0.05), Vector3(x, 1.55, z + inward * 0.03), _mat(tint.lerp(Color(1, 0.96, 0.88), 0.72), 0.6, 0.55), false)
			_slab(root, Vector3(bay - 0.5, 0.25, 0.3), Vector3(x, 0.125, z + inward * 0.15), dark_m)
			_slab(root, Vector3(bay - 0.4, 0.8, 0.14), Vector3(x, 3.5, z + inward * 0.07), _mat(tint, 0.6), false)
			_slab(root, Vector3(0.5, H, 0.5), Vector3(x - bay * 0.5, H * 0.5, z + inward * 0.25), wall_m)
			# a doorway in the glass: its frame
			_slab(root, Vector3(0.08, 2.3, 0.08), Vector3(x - 0.8, 1.15, z + inward * 0.09), dark_m, false)
			_slab(root, Vector3(0.08, 2.3, 0.08), Vector3(x + 0.8, 1.15, z + inward * 0.09), dark_m, false)
			_slab(root, Vector3(1.68, 0.08, 0.08), Vector3(x, 2.3, z + inward * 0.09), dark_m, false)
			# shelves seen through the glass
			for s in 3:
				_slab(root, Vector3(1.6, 0.06, 0.04), Vector3(x + (bay * 0.5 - 1.6) * (1.0 if (k + s) % 2 == 0 else -1.0) * 0.8, 0.8 + 0.6 * s, z + inward * 0.07), _mat(tint.darkened(0.25), 0.7), false)
			if k < shops.size():
				var light: bool = tint.get_luminance() < 0.45
				_sign(root, String(shops[k]), Vector3(x, 3.5, z + inward * 0.16), 0.0 if side == 0 else PI, 0.42, Color(1, 1, 1) if light else Color(0.08, 0.08, 0.08))
	# down the middle: benches and planters
	var wood := _mat(Color(0.55, 0.38, 0.22), 0.7)
	var leaf := _mat(Color(0.16, 0.36, 0.16), 0.9)
	for i in 3:
		var x := -L * 0.5 + 9.0 + i * 9.0
		_slab(root, Vector3(2.2, 0.08, 0.5), Vector3(x, 0.46, 0.0), wood)
		_slab(root, Vector3(0.12, 0.42, 0.4), Vector3(x - 0.9, 0.21, 0.0), dark_m, false)
		_slab(root, Vector3(0.12, 0.42, 0.4), Vector3(x + 0.9, 0.21, 0.0), dark_m, false)
		_slab(root, Vector3(1.1, 0.6, 1.1), Vector3(x + 3.2, 0.3, 0.0), dark_m)
		var bush := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.62
		sm.height = 1.1
		sm.radial_segments = 10
		sm.rings = 6
		sm.material = leaf
		bush.mesh = sm
		bush.position = Vector3(x + 3.2, 1.05, 0.0)
		root.add_child(bush)
	# the way out, at the near end: glass doors with the daylight behind them, and the sign over them
	var x0 := -L * 0.5
	_slab(root, Vector3(0.05, 2.6, 4.2), Vector3(x0 + 0.03, 1.3, 0.0), _mat(Color(0.80, 0.90, 1.0), 0.2, 1.2), false)
	for zz in [-2.1, 0.0, 2.1]:
		_slab(root, Vector3(0.1, 2.6, 0.1), Vector3(x0 + 0.08, 1.3, zz), dark_m, false)
	_slab(root, Vector3(0.1, 0.1, 4.3), Vector3(x0 + 0.08, 2.6, 0.0), dark_m, false)
	_slab(root, Vector3(0.06, 0.34, 1.5), Vector3(x0 + 0.1, 3.0, 0.0), _mat(Color(0.05, 0.50, 0.22), 0.6, 0.8), false)
	_sign(root, "UTGANG", Vector3(x0 + 0.15, 3.0, 0.0), PI * 0.5, 0.24, Color(1, 1, 1))
	# and the centre's name on the far wall
	_sign(root, String(place["name"]).to_upper(), Vector3(L * 0.5 - 0.05, 3.6, 0.0), -PI * 0.5, 0.7, Color(0.15, 0.15, 0.16))
	return root
