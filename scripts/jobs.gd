extends Node
## Something to do in the town (the plan of 18 November, part 4). None of it is needed to enjoy Molde: the jobs
## stand as yellow beams of light where they start, and are taken with E.
##
## - A job has a place to start, something it needs (the bus, a car, the bicycle…), a goal with a clock or a
##   count, and an end with a result. One runs at a time. The panel at the top right says what to do next; the
##   compass shows the way with a green mark, and a green beam stands at the place.
## - The FRAM bus: line 701 out from the bus square, stopping at every stop. Scored on keeping time and on
##   driving gently.
## - A taxi shift by car, deliveries by ATV or bicycle: fetch at one address, set down at another.
## - Three runs against the clock: Varden up and down by bicycle, a swim round two buoys, the helicopter onto
##   the stadium.
## - Sights of Molde: thirty places to find, each with two lines about it. They are found by going there; J
##   opens the card that fills up (and the list of jobs, with a way shown to each).
## - The ferry to Vestnes sails by the clock and can be boarded at the ferry quay, on foot or in a vehicle.
## - Where the player was is remembered between visits (user://progress.cfg, with the best results).

const FILE := "user://progress.cfg"
const CARS := ["the Volvo", "the Integra", "the Mercedes"]

var main
var world
var player
var traffic
var daytime
var hud
var sights: Array = []                   # {"name", "at": Vector2, "r", "text"}
var jobs: Array = []                     # {"id", "title", "about", "at": Vector2, "kind", "needs": [labels] or []}
var active := {}                         # the job that is running: its record and its state
var found := {}                          # names of sights found
var best := {}                           # job id -> best result (seconds, or points for the bus)
var done := {}                           # job id -> how many times finished
var guide = null                         # a place the player asked to be shown the way to (Vector2), or null
var aboard := false                      # on the ferry
var last_result := ""

var _layer: CanvasLayer
var _panel: Panel
var _title: Label
var _line: Label
var _clock: Label
var _prompt: Label
var _card: Panel
var _card_title: Label
var _card_text: Label
var _card_age := 99.0
var _journal: Panel
var _journal_box: VBoxContainer
var _beams: Array = []                   # one for each job's start
var _goal: MeshInstance3D
var _save_in := 20.0
var _near_job := -1
var _ferry := {}
var _ferry_quay := Vector2.ZERO
var _ferry_deck := Vector3(3.0, 8.76, -23.8)        # the railed walkway outside the saloon, at the end that leads
var _was_captured := false
var _rng := RandomNumberGenerator.new()
var _places: Array = []                  # addresses to drive between: {"name", "at"}


func setup(m) -> void:
	main = m
	world = m.world
	player = m.player
	traffic = m.traffic
	daytime = m.daytime
	hud = m.hud
	_rng.randomize()
	_load()
	_make_sights()
	_make_places()
	_make_jobs()
	_build_ui()
	_build_markers()
	for b in traffic._boats:
		if b["kind"] == "ferry":
			_ferry = b
	for p in world.meta.get("pois", []):
		if p["kind"] == "ferry_terminal" and str(p["name"]) == "Molde ferjekai":
			_ferry_quay = Vector2(p["x"], p["z"])


# ------------------------------------------------------------------ what there is
func _sight(name: String, x: float, z: float, r: float, text: String) -> void:
	sights.append({"name": name, "at": Vector2(x, z), "r": r, "text": text})


func _make_sights() -> void:
	# (the places are the map's own: its named buildings and points; the lines are what the town says of itself)
	_sight("Rådhuset", -25, -48, 45, "Molde's town hall, opened in 1966.\nRoses grow on its roof: the town calls itself Rosenes by, the town of roses.")
	_sight("Rosepiken", -10.6, -14.4, 14, "The rose maiden, in bronze by Ragnhild Butenschøn, 1971.\nShe stands with her basket in front of the town hall.")
	_sight("Molde domkirke", 46, -73, 45, "The cathedral, consecrated in 1957, with a bell tower that stands by itself.\nThe church before it burned when the town was bombed in April 1940.")
	_sight("Torget", -22, 25, 30, "The market square, between Storgata and the harbour.\nIn July it is the middle of Moldejazz.")
	_sight("Aker Stadion", -486, 460, 90, "Home of Molde FK since 1998, on the edge of the fjord.\nIt holds about 11 000.")
	_sight("Scandic Seilet", -766, 495, 60, "The hotel shaped like a sail, opened in 2002.\nIt is seen from far out on the fjord.")
	_sight("Moldebadet", -753, 416, 45, "The town's swimming hall, between the stadium and the sail.")
	_sight("Plassen", -199, 149, 45, "The culture house, opened in 2012: library, theatre and the jazz festival under one roof.\nThe roof is a stair and a square at once.")
	_sight("Storkaia", 0, 0, 60, "The quay where the coastal steamer calls, morning and evening.\nNorthbound to Kristiansund, southbound to Ålesund.")
	_sight("Molde ferjekai", 510, 68, 50, "The ferry to Vestnes leaves from here, across the Moldefjord.\nThe crossing takes about 35 minutes.")
	_sight("Reknesparken", -552, -65, 45, "The town's old park, with its music pavilion.\nRomsdalsmuseet lies just above it.")
	_sight("Romsdalsmuseet", -600, -160, 70, "An open-air museum, founded in 1912: old houses, barns and storehouses from all over Romsdal.")
	_sight("Krona", -425, -234, 40, "The museum's new building, opened in 2016.\nIts pointed roofs answer the mountains across the fjord.")
	_sight("Kongebjørka", -1583, -257, 80, "At Glomstua. In April 1940 King Haakon and Crown Prince Olav took cover by a birch here while Molde was bombed.\nThe photograph of them became a sign of Norway's resistance.")
	_sight("Varden", -1640, -1201, 80, "407 metres over the town. From here the Molde panorama:\n222 peaks, many with snow on them, across the fjord.")
	_sight("Storlihytta", -815, -1163, 50, "A cabin in Moldemarka, the forest and hills behind the town.")
	_sight("Molde sjukehus", -453, 169, 60, "The hospital at Lundavang, the town's own for generations.")
	_sight("Fylkeshuset", -415, 315, 50, "The county hall of Møre og Romsdal.")
	_sight("St. Sunniva kirke", -265, -46, 35, "The Catholic church of Molde.")
	_sight("Høgskolen i Molde", -2646, 99, 90, "Molde University College, known for logistics.\nIt looks down on the fjord from Kvam.")
	_sight("Moldegård", 1360, 22, 90, "The old manor of Molde. Henrik Ibsen stayed here in the summer of 1885;\nit is said to have given him Rosmersholm.")
	_sight("Molde Storsenter", 1396, -72, 70, "The shopping centre at Moldegård.")
	_sight("Glamox", 1509, -162, 60, "Lighting, founded in Molde in 1947 by Birger Hatlebakk.\nThe street outside carries his name.")
	_sight("Molde brannstasjon", 1655, -30, 50, "The fire station, with its hose tower.")
	_sight("Molde Mølle", 1190, 121, 50, "The mill and its silo at the harbour.")
	_sight("Retiro", 2938, -428, 70, "A summer estate from the 1870s with a park by the fjord.")
	_sight("Brunvoll", 4820, -954, 80, "Thrusters for ships all over the world, made in Molde.\nThe firm began in 1912.")
	_sight("Molde lufthavn, Årø", 5207, -1006, 110, "The airport, opened in 1972, on the shore east of town.")
	_sight("Nordbyen kirke", 3392, -1956, 50, "The church of Nordbyen, the part of town up behind Årø.")
	_sight("Hjertøya", 537, 2249, 140, "The island in the fjord, with the fisheries museum.\nThe artist Kurt Schwitters spent his summers in a hut here in the 1930s.")
	for b in traffic._boats:
		if b["kind"] == "steamer":
			for s in sights:
				if s["name"] == "Storkaia":
					var q: Vector2 = b["berth"]                    # (the quay beside the berth: the first dry ground to the north)
					for k in 60:
						if world.height_at(q.x, q.y) > 1.0:
							break
						q.y -= 5.0
					s["at"] = q + Vector2(0, -8.0)


func _make_places() -> void:
	var seen := {}
	for p in world.meta.get("pois", []):
		var name: String = p["name"]
		if name == "" or seen.has(name) or p["kind"] in ["bench", "waste_basket", "post_box", "recycling", "toilets", "hunting_stand", "vending_machine", "atm", "bicycle_parking", "shelter", "drinking_water", "parking", "parking_entrance", "charging_station", "ferry_terminal"]:
			continue
		var at := Vector2(p["x"], p["z"])
		if world.height_at(at.x, at.y) < 1.0 or world.height_at(at.x, at.y) > 160.0:
			continue
		seen[name] = true
		_places.append({"name": name, "at": at})


func _job(id: String, title: String, kind: String, at: Vector2, needs: Array, about: String) -> void:
	jobs.append({"id": id, "title": title, "kind": kind, "at": at, "needs": needs, "about": about})


func _make_jobs() -> void:
	if main.bus != null:
		var bp: Vector3 = main.bus.global_position
		_job("bus", "Drive the FRAM bus: line 701", "bus", Vector2(bp.x, bp.z), ["the FRAM bus"], "Out from the bus square, stopping at every stop. Keep time, and drive gently.")
	var rank := Vector2(120.0, 20.0)
	var rank_far := 600.0
	var pizza := Vector2(-8.5, -20.0)
	for p in world.meta.get("pois", []):
		if p["kind"] == "taxi" and Vector2(p["x"], p["z"]).length() < rank_far:      # (the rank nearest the middle of town)
			rank = Vector2(p["x"], p["z"])
			rank_far = rank.length()
		if p["name"] == "Pizza Art":
			pizza = Vector2(p["x"], p["z"])
	_job("taxi", "A taxi shift", "fares", rank, CARS, "Three fares by car: fetch at one address, set down at another.")
	_job("delivery", "Deliveries", "fares", pizza, ["the ATV", "the bicycle"], "Three deliveries by ATV or bicycle, while they are warm.")
	_job("varden", "Varden up and down by bicycle", "trial", Vector2(-492.0, -380.0), ["the bicycle"], "From Træffhuset up to Vardestua, 400 metres higher, and down again.")
	_job("heli", "Onto the stadium by helicopter", "trial", Vector2(main.HELI_AT.x, main.HELI_AT.y), ["the helicopter"], "Take off from Torget and set down inside Aker Stadion.")
	# a swim round two buoys, from the first shore west of the stadium where the water is deep enough
	var shore := Vector2(-640.0, 430.0)
	for k in 200:
		if not world.water_at(shore.x, shore.y + 6.0).is_empty() and float(world.water_at(shore.x, shore.y + 6.0)["depth"]) > 1.2:
			break
		shore.y += 4.0
	_job("swim", "A swim in the fjord", "trial", shore, [], "Out round two buoys and back to the shore. On foot: the water is cold.")
	for j in jobs:
		match j["id"]:
			"varden":
				j["marks"] = [Vector2(-1640.0, -1185.0), j["at"]]
				j["names"] = ["Vardestua", "Træffhuset"]
			"heli":
				j["marks"] = [Vector2(-486.0, 462.0)]
				j["names"] = ["Aker Stadion"]
				j["land"] = true
			"swim":
				j["marks"] = [shore + Vector2(-60.0, 140.0), shore + Vector2(80.0, 150.0), shore]
				j["names"] = ["the first buoy", "the second buoy", "the shore"]
				j["swim"] = true


# ------------------------------------------------------------------ what is seen
func _label(parent: Node, size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(l)
	return l


func _box(color: Color) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(6)
	sb.set_content_margin_all(12)
	return sb


func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 2
	add_child(_layer)
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", _box(Color(0, 0, 0, 0.42)))
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_panel.visible = false
	_layer.add_child(_panel)
	_title = _label(_panel, 18, Color(1.0, 0.86, 0.45))
	_title.position = Vector2(14, 10)
	_title.size = Vector2(352, 24)
	_line = _label(_panel, 15, Color(1, 1, 1, 0.92))
	_line.position = Vector2(14, 38)
	_line.size = Vector2(352, 68)
	_clock = _label(_panel, 15, Color(1, 1, 1, 0.75))
	_clock.position = Vector2(14, 112)
	_clock.size = Vector2(352, 22)
	_prompt = _label(_layer, 18, Color(1, 1, 1, 0.95))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false
	_card = Panel.new()
	_card.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.08, 0.80)))
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.visible = false
	_layer.add_child(_card)
	_card_title = _label(_card, 22, Color(1.0, 0.86, 0.45))
	_card_title.position = Vector2(18, 12)
	_card_title.size = Vector2(604, 30)
	_card_text = _label(_card, 16, Color(1, 1, 1, 0.92))
	_card_text.position = Vector2(18, 46)
	_card_text.size = Vector2(604, 80)
	_journal = Panel.new()
	_journal.add_theme_stylebox_override("panel", _box(Color(0.05, 0.06, 0.08, 0.93)))
	_journal.visible = false
	_layer.add_child(_journal)
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20, 16)
	scroll.name = "Scroll"
	_journal.add_child(scroll)
	_journal_box = VBoxContainer.new()
	_journal_box.add_theme_constant_override("separation", 6)
	_journal_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_journal_box)


func _beam(color: Color, radius: float, height: float) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.55
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 16
	mesh.cap_top = false
	mesh.cap_bottom = false
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = Color(color.r, color.g, color.b, 0.30)
	mat.disable_fog = true
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.visible = false
	add_child(mi)
	return mi


func _build_markers() -> void:
	for j in jobs:
		var b := _beam(Color(1.0, 0.80, 0.25), 1.3, 26.0)
		var at: Vector2 = j["at"]
		b.position = Vector3(at.x, maxf(world.height_at(at.x, at.y), 0.0) + 13.0, at.y)
		var name := Label3D.new()
		name.text = j["title"]
		name.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		name.font_size = 48
		name.pixel_size = 0.008
		name.position = Vector3(0, -9.6, 0)
		name.modulate = Color(1.0, 0.9, 0.6)
		name.no_depth_test = true
		name.visibility_range_end = 70.0
		b.add_child(name)
		_beams.append(b)
	_goal = _beam(Color(0.35, 1.0, 0.45), 2.2, 60.0)


func ground(p: Vector2) -> float:
	var y: float = world.detail.top_at(p.x, p.y)
	return y if not is_nan(y) else maxf(world.height_at(p.x, p.y), 0.0)


# ------------------------------------------------------------------ the journal (J)
func journal_open() -> bool:
	return _journal.visible


func toggle_journal() -> void:
	if _journal.visible:
		_journal.visible = false
		if _was_captured:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		return
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	for c in _journal_box.get_children():
		c.queue_free()
	var head := _label(_journal_box, 22, Color(1.0, 0.86, 0.45))
	head.text = "Jobs"
	var first: Button = null
	for j in jobs:
		var b := Button.new()
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		var res := ""
		if best.has(j["id"]):
			res = "   ·   best: " + (("%d points" % int(best[j["id"]])) if j["kind"] != "trial" else _mmss(float(best[j["id"]])))
		b.text = "%s%s\n     %s   (needs %s)" % [j["title"], res, j["about"], "nothing" if (j["needs"] as Array).is_empty() else " or ".join(j["needs"])]
		b.add_theme_font_size_override("font_size", 15)
		b.pressed.connect(_show_way.bind(j["at"]))
		_journal_box.add_child(b)
		if first == null:
			first = b
	var tip := _label(_journal_box, 13, Color(1, 1, 1, 0.6))
	tip.text = "Choose a job to be shown the way to where it starts (a green mark on the compass). E starts it there. J or Esc closes this."
	var sh := _label(_journal_box, 22, Color(1.0, 0.86, 0.45))
	sh.text = "\nSights of Molde: %d of %d found" % [found.size(), sights.size()]
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 4)
	_journal_box.add_child(grid)
	for s in sights:
		var l := _label(grid, 15, Color(1, 1, 1, 0.92) if found.has(s["name"]) else Color(1, 1, 1, 0.35))
		l.autowrap_mode = TextServer.AUTOWRAP_OFF
		l.custom_minimum_size = Vector2(250, 0)
		l.text = ("✓  " + str(s["name"])) if found.has(s["name"]) else "·  ?  ?  ?"
	_journal.visible = true
	_place_ui()
	if first != null:
		first.grab_focus()


func _show_way(at: Vector2) -> void:
	guide = at
	toggle_journal()


# ------------------------------------------------------------------ keys
func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("journal"):
		toggle_journal()
		get_viewport().set_input_as_handled()
	elif _journal.visible and event.is_action_pressed("ui_cancel"):
		toggle_journal()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("job"):
		press_job()
		get_viewport().set_input_as_handled()


## E: start the job one is standing at, give up the one that is running, or go on board or ashore.
func press_job() -> void:
	if aboard:
		if _ferry_alongside():
			_ashore()
	elif not active.is_empty():
		_end("Given up.", false)
	elif _near_job >= 0:
		start(jobs[_near_job])
	elif _can_board():
		_board()


func _vehicle() -> String:
	return str(player.atv.LABEL) if player.driving else ""


func _fits(j: Dictionary) -> bool:
	var needs: Array = j["needs"]
	return (needs.is_empty() and not player.driving) or needs.has(_vehicle())


# ------------------------------------------------------------------ a job
func start(j: Dictionary) -> void:
	if not _fits(j):
		return
	active = {"job": j, "t": 0.0, "step": 0, "dwell": 0.0, "jolts": 0, "late": 0.0, "v": 0.0, "jolt_wait": 0.0, "note": ""}
	guide = null
	match j["kind"]:
		"bus":
			var line: Dictionary = traffic.line_points(1 if traffic.buses.size() > 1 else 0)
			active["marks"] = line["stops"]
			active["plan"] = _plan(Vector2(player.global_position.x, player.global_position.z), line["stops"], 8.5, 8.0)
		"fares":
			active["fares"] = 0
			_next_fare()
		"trial":
			active["marks"] = j["marks"]
	_say()


## When each stop should be reached: the way there at `pace` metres a second, and `halt` seconds at each.
func _plan(from: Vector2, marks: Array, pace: float, halt: float) -> Array:
	var out := []
	var t := 0.0
	var at := from
	for mk in marks:
		t += at.distance_to(mk) * 1.25 / pace
		out.append(t)
		t += halt
		at = mk
	return out


func _next_fare() -> void:
	var here := Vector2(player.global_position.x, player.global_position.z)
	var a := {}
	var b := {}
	for attempt in 200:
		a = _places[_rng.randi_range(0, _places.size() - 1)]
		var da: float = (a["at"] as Vector2).distance_to(here)
		if da < 150.0 or da > 900.0:
			continue
		b = _places[_rng.randi_range(0, _places.size() - 1)]
		var db: float = (b["at"] as Vector2).distance_to(a["at"])
		if db > 500.0 and db < 2200.0:
			break
	active["marks"] = [a["at"], b["at"]]
	active["names"] = [a["name"], b["name"]]
	active["step"] = 0
	active["due"] = float(active["t"]) + (here.distance_to(a["at"]) + (a["at"] as Vector2).distance_to(b["at"])) * 1.35 / 9.0 + 25.0


func _mmss(t: float) -> String:
	return "%d:%02d" % [int(t) / 60, int(t) % 60]


func _say() -> void:
	var j: Dictionary = active["job"]
	var marks: Array = active["marks"]
	var i: int = active["step"]
	_title.text = j["title"]
	match j["kind"]:
		"bus":
			_line.text = "Stop %d of %d: pull in at the green light and stand still.%s" % [i + 1, marks.size(), str(active["note"])]
		"fares":
			var names: Array = active["names"]
			var taxi: bool = j["id"] == "taxi"
			if i == 0:
				_line.text = ("Fare %d of 3: fetch at %s." if taxi else "Delivery %d of 3: fetch at %s.") % [int(active["fares"]) + 1, names[0]]
			else:
				_line.text = ("To %s." if taxi else "Deliver to %s.") % names[1]
		"trial":
			_line.text = "To %s." % (j["names"] as Array)[i]


func _ding(name: String) -> void:
	if main.sound != null:
		main.sound.play_at(name, player.global_position + Vector3(0, 1.5, 0), 0.8)


func _end(text: String, finished: bool) -> void:
	var j: Dictionary = active["job"]
	if finished:
		_ding("chime")
	if finished:
		done[j["id"]] = int(done.get(j["id"], 0)) + 1
	last_result = text
	_card_title.text = j["title"]
	_card_text.text = text
	_card_age = 0.0
	active = {}
	save()


func _record(id: String, value: float, lower_is_better: bool) -> String:
	var had: bool = best.has(id)
	if not had or (lower_is_better and value < float(best[id])) or (not lower_is_better and value > float(best[id])):
		best[id] = value
		return "  A new best." if had else ""
	return ""


func _run_job(delta: float) -> void:
	var j: Dictionary = active["job"]
	if not _fits(j) and not (j["kind"] == "trial" and j.has("swim")):
		active["away"] = float(active.get("away", 0.0)) + delta
		_line.text = "Back to %s to go on (%d s)." % [" or ".join(j["needs"]), int(20.0 - float(active["away"]))]
		if float(active["away"]) > 20.0:
			_end("Left the job.", false)
		return
	if active.has("away"):
		active.erase("away")
		_say()
	active["t"] += delta
	var marks: Array = active["marks"]
	var i: int = active["step"]
	var pp: Vector3 = player.global_position
	var here := Vector2(pp.x, pp.z)
	var mark: Vector2 = marks[i]
	var d := here.distance_to(mark)
	var speed: float = Vector2(player.velocity.x, player.velocity.z).length()
	# how gently: a jolt is the speed changing by more than 6 m/s in a second (a kerb hit, a hard stop)
	active["jolt_wait"] = maxf(float(active["jolt_wait"]) - delta, 0.0)
	if delta > 0.0 and absf(speed - float(active["v"])) / delta > 6.0 and float(active["jolt_wait"]) <= 0.0 and float(active["t"]) > 1.0:
		active["jolts"] += 1
		active["jolt_wait"] = 1.5
	active["v"] = speed
	_goal.visible = true
	_goal.position = Vector3(mark.x, ground(mark) + 30.0, mark.y)
	match j["kind"]:
		"bus":
			var plan: Array = active["plan"]
			_clock.text = "%s   ·   due at this stop %s   ·   jolts %d" % [_mmss(active["t"]), _mmss(plan[i]), int(active["jolts"])]
			if d < 14.0 and speed < 0.4:
				active["dwell"] += delta
				if float(active["dwell"]) > 3.0:
					active["late"] += maxf(float(active["t"]) - float(plan[i]) - 20.0, 0.0)
					var on := _rng.randi_range(0, 5)
					var off := _rng.randi_range(0, 3) if i > 0 else 0
					active["note"] = " At the last one %d got on and %d off." % [on, off]
					active["dwell"] = 0.0
					active["step"] += 1
					_ding("tick")
					if int(active["step"]) >= marks.size():
						var points := clampi(100 - int(float(active["late"]) / 6.0) - 4 * int(active["jolts"]), 0, 100)
						_end("The end of the line in %s. Late by %d s in all, %d jolts: %d points of 100.%s" % [_mmss(active["t"]), int(active["late"]), int(active["jolts"]), points, _record("bus", points, false)], true)
						return
					_say()
			else:
				active["dwell"] = 0.0
		"fares":
			_clock.text = "%s   ·   %s" % [_mmss(active["t"]), ("%d s to spare" % int(float(active["due"]) - float(active["t"]))) if float(active["due"]) > float(active["t"]) else "late"]
			if d < 12.0 and speed < 0.5:
				active["dwell"] += delta
				if float(active["dwell"]) > 1.5:
					active["dwell"] = 0.0
					_ding("tick")
					if i == 0:
						active["step"] = 1
					else:
						active["points"] = int(active.get("points", 0)) + (34 if float(active["due"]) >= float(active["t"]) else 20) - mini(2 * int(active["jolts"]), 12)
						active["jolts"] = 0
						active["fares"] += 1
						if int(active["fares"]) >= 3:
							var pts: int = mini(int(active["points"]), 100)
							_end("Three done in %s: %d points of 100.%s" % [_mmss(active["t"]), pts, _record(j["id"], pts, false)], true)
							return
						_next_fare()
					_say()
			else:
				active["dwell"] = 0.0
		"trial":
			_clock.text = _mmss(active["t"]) + (("   ·   best " + _mmss(float(best[j["id"]]))) if best.has(j["id"]) else "")
			var reached := d < 20.0
			if j.has("land") and i == marks.size() - 1:
				reached = d < 75.0 and speed < 0.4 and absf(player.velocity.y) < 0.2 and float(active["t"]) > 5.0
			if reached:
				active["step"] += 1
				_ding("tick")
				if int(active["step"]) >= marks.size():
					_end("Done in %s.%s" % [_mmss(active["t"]), _record(j["id"], active["t"], true)], true)
					return
				_say()


# ------------------------------------------------------------------ the ferry
func _ferry_alongside() -> bool:
	return not _ferry.is_empty() and float(_ferry["wait"]) > 0.0 and float(_ferry["t"]) < 1.0


func _can_board() -> bool:
	if _ferry.is_empty() or not _ferry_alongside():
		return false
	return Vector2(player.global_position.x, player.global_position.z).distance_to(_ferry_quay) < 45.0


func _board() -> void:
	aboard = true
	_ferry["wait"] = minf(float(_ferry["wait"]), 12.0)
	_card_title.text = "The ferry to Vestnes"
	_card_text.text = "On board. Vestnes lies beyond this map: the ferry sails to the far side of it, turns, and comes back to Molde.\nHold E to pass the time on the way."
	_card_age = 0.0


func _ashore() -> void:
	aboard = false
	var q := _ferry_quay
	player.global_position = Vector3(q.x, ground(q) + 0.6, q.y)
	player.velocity = Vector3.ZERO
	player.reset_physics_interpolation()
	world.update_streaming(player.global_position)
	world.flush(player.global_position)


## Held on the ferry's deck while it sails (called before the player's own step, so nothing else moves them).
func _ride(delta: float) -> void:
	var node: Node3D = _ferry["node"]
	player.global_position = node.global_transform * (_ferry_deck / node.scale.x)
	player.velocity = Vector3.ZERO
	if Input.is_action_pressed("job") and float(_ferry["wait"]) <= 0.0:
		traffic.hurry_ferry(delta * 7.0)
	world.update_streaming(player.global_position)


# ------------------------------------------------------------------ each frame
func _place_ui() -> void:
	var vs := get_viewport().get_visible_rect().size
	_panel.position = Vector2(vs.x - 400.0, 70.0)
	_panel.size = Vector2(380.0, 144.0)
	_prompt.position = Vector2(0.0, vs.y * 0.775)
	_prompt.size = Vector2(vs.x, 30.0)
	_card.position = Vector2(vs.x * 0.5 - 320.0, vs.y * 0.60)
	_card.size = Vector2(640.0, 136.0)
	_journal.position = Vector2(vs.x * 0.5 - 430.0, vs.y * 0.08)
	_journal.size = Vector2(860.0, vs.y * 0.84)
	var scroll: ScrollContainer = _journal.get_node("Scroll")
	scroll.size = _journal.size - Vector2(40, 32)
	_journal_box.custom_minimum_size = Vector2(scroll.size.x - 16.0, 0)


func _physics_process(delta: float) -> void:
	if world == null or player == null:
		return
	if aboard:
		_ride(delta)
	var pp: Vector3 = player.global_position
	var here := Vector2(pp.x, pp.z)
	# sights
	for s in sights:
		if not found.has(s["name"]) and here.distance_to(s["at"]) < float(s["r"]) and absf(pp.y - maxf(world.height_at(pp.x, pp.z), 0.0)) < 40.0:
			found[s["name"]] = true
			_ding("chime")
			_card_title.text = "%s      (%d of %d sights)" % [s["name"], found.size(), sights.size()]
			_card_text.text = s["text"]
			_card_age = 0.0
			save()
	# jobs
	_near_job = -1
	if active.is_empty():
		_goal.visible = guide != null
		if guide != null:
			var g: Vector2 = guide
			_goal.position = Vector3(g.x, ground(g) + 30.0, g.y)
			if here.distance_to(g) < 12.0:
				guide = null
		for k in jobs.size():
			var at: Vector2 = jobs[k]["at"]
			(_beams[k] as Node3D).visible = here.distance_to(at) < 900.0
			if here.distance_to(at) < (9.0 if not player.driving else 14.0):
				_near_job = k
	else:
		for b in _beams:
			(b as Node3D).visible = false
		_run_job(delta)
	_save_in -= delta
	if _save_in <= 0.0:
		_save_in = 20.0
		save()


func _process(delta: float) -> void:
	_place_ui()
	_panel.visible = not active.is_empty()
	_card_age += delta
	_card.visible = _card_age < 9.0
	_card.modulate.a = clampf(minf(_card_age / 0.4, (9.0 - _card_age) / 1.5), 0.0, 1.0)
	var text := ""
	if aboard:
		text = "E  —  go ashore" if _ferry_alongside() else "On the ferry  ·  hold E to pass the time"
	elif not active.is_empty():
		text = ""
	elif _near_job >= 0:
		var j: Dictionary = jobs[_near_job]
		text = ("E  —  %s" % j["title"]) if _fits(j) else "%s: come with %s" % [j["title"], " or ".join(j["needs"])]
	elif _can_board():
		text = "E  —  board the ferry to Vestnes" + ((" (leaves %s)" % _ferry["leaves"]) if _ferry.has("leaves") else "")
	elif not _ferry.is_empty() and Vector2(player.global_position.x, player.global_position.z).distance_to(_ferry_quay) < 45.0:
		text = "The ferry to Vestnes is out on the fjord. It will be back."
	_prompt.text = text
	_prompt.visible = text != "" and not _journal.visible
	# the way to the goal, on the compass
	var to = null
	if not active.is_empty() and active.has("marks"):
		to = (active["marks"] as Array)[mini(int(active["step"]), (active["marks"] as Array).size() - 1)]
	elif guide != null:
		to = guide
	if hud != null and hud.get("_compass") != null:
		if to == null:
			hud._compass.mark = NAN
		else:
			var dv: Vector2 = (to as Vector2) - Vector2(player.global_position.x, player.global_position.z)
			hud._compass.mark = fposmod(rad_to_deg(atan2(dv.x, -dv.y)), 360.0)
			hud._compass.mark_far = dv.length()


# ------------------------------------------------------------------ kept between visits
var FILE_OFF := false                    # a check is running: leave the player's own progress alone


func save() -> void:
	if FILE_OFF:
		return
	var cf := ConfigFile.new()
	cf.set_value("progress", "found", found.keys())
	cf.set_value("progress", "best", best)
	cf.set_value("progress", "done", done)
	if player != null and player.is_inside_tree() and not aboard:
		var p: Vector3 = player.global_position
		cf.set_value("place", "at", [p.x, p.y, p.z])
		cf.set_value("place", "yaw", player.yaw)
	cf.save(FILE)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(FILE) != OK:
		return
	for n in cf.get_value("progress", "found", []):
		found[n] = true
	best = cf.get_value("progress", "best", {})
	done = cf.get_value("progress", "done", {})


## Where the player was when the game was last left: [Vector3, yaw], or an empty list.
static func last_place() -> Array:
	var cf := ConfigFile.new()
	if cf.load(FILE) != OK or not cf.has_section_key("place", "at"):
		return []
	var a: Array = cf.get_value("place", "at")
	return [Vector3(a[0], a[1], a[2]), float(cf.get_value("place", "yaw", 0.0))]


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and player != null and is_instance_valid(player) and player.is_inside_tree():
		save()
