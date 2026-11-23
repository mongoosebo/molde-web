extends Node
## Checks that run the game by themselves and quit (`./run.sh -- --bench` and so on). The older ones are in
## main.gd; the ones added with the plan of 18 November are here. tools/check.sh runs them all in turn.

const KNOWN := ["--bench", "--jobs", "--winter", "--lamps", "--film", "--indoors", "--bridges", "--standing", "--edges"]

var m                               # main.gd


func run(main, what: String) -> void:
	m = main
	m.hud.start(m.world, m.player)
	match what:
		"--bench":
			await _bench()
		"--jobs":
			await _jobs()
		"--winter":
			await _winter()
		"--lamps":
			await _lamps()
		"--film":
			await _film()
		"--indoors":
			await _indoors()
		"--bridges":
			await _bridges()
		"--standing":
			await _standing()
		"--edges":
			await _edges()
	get_tree().quit()


func _arg(name: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(name + "="):
			return a.substr(name.length() + 1)
	return fallback


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


## `--bench`: how smoothly the game runs. The camera is taken along a fixed route on the roads through the
## centre (the town hall, along Storgata, the bus square, out Fannestrandvegen) at 50 km/h, at noon and at 23:00,
## with traffic and townspeople on. data/bench.json gets, for each: the mean frame time, the slowest 1 %, the
## longest frame, and the ten worst places with what was being drawn there. Nothing limits the frame rate
## during a check, so the numbers are what the machine can do, not what the screen asks for.
func _bench() -> void:
	var world = m.world
	var player = m.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	var route := PackedVector2Array()
	var stops := [Vector2(-560, 60), Vector2(-8, -30), Vector2(120, 35), Vector2(700, -60), Vector2(1750, -230), Vector2(2600, -480)]
	for i in stops.size() - 1:
		route.append_array(m.traffic.route_points(stops[i], stops[i + 1]))
	if route.size() < 20:
		print("BENCH no route")
		return
	var length := 0.0
	for i in route.size() - 1:
		length += route[i].distance_to(route[i + 1])
	var speed := float(_arg("--speed", "13.9"))
	var out := {"route_m": snappedf(length, 1.0), "speed": speed, "renderer": str(ProjectSettings.get_setting("rendering/renderer/rendering_method")), "runs": {}}
	if OS.get_cmdline_args().has("gl_compatibility"):
		out["renderer"] = "gl_compatibility"
	for hour in [12.0, 23.0]:
		m.daytime.hours = hour
		m.daytime.rate = 0.0
		m.daytime.apply()
		var p0 := route[0]
		player.global_position = Vector3(p0.x, world.height_at(p0.x, p0.y) + 0.6, p0.y)
		world.update_streaming(player.global_position)
		world.flush(player.global_position)
		await _frames(90)
		var times := PackedFloat32Array()
		var where := PackedVector2Array()
		var draws := PackedInt32Array()
		var what: Array = []
		var late := 0                                      # frames in which the cell the camera is in was not built yet
		var before: Dictionary = world.spent.duplicate()
		var i := 0
		var along := 0.0
		var last := Time.get_ticks_usec()
		while i < route.size() - 1:
			await get_tree().process_frame
			var now := Time.get_ticks_usec()
			var dt := float(now - last) / 1000.0
			last = now
			along += speed * minf(dt, 50.0) / 1000.0
			while i < route.size() - 1 and along > route[i].distance_to(route[i + 1]):
				along -= route[i].distance_to(route[i + 1])
				i += 1
			if i >= route.size() - 1:
				break
			var seg := route[i + 1] - route[i]
			var q := route[i] + seg.normalized() * along
			var y: float = world.detail.top_at(q.x, q.y)
			if is_nan(y):
				y = world.height_at(q.x, q.y)
			player.global_position = Vector3(q.x, y + 0.6, q.y)
			player.yaw = lerp_angle(player.yaw, atan2(-seg.x, -seg.y), 0.08)
			world.update_streaming(player.global_position)
			times.append(dt)
			var here: Vector2i = world.detail.cell_of(q.x, q.y)
			if not world.detail._cells.has(here) and (world.detail.buildings.has(here) or world.detail.paved.has(here)):
				late += 1
			where.append(q)
			draws.append(int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
			var parts := {}
			if dt > 12.0:                                  # a slow frame: which of the jobs had the time
				for key in world.spent:
					var ms := float(int(world.spent[key]) - int(before.get(key, 0))) / 1000.0
					if ms > 1.0:
						parts[key] = snappedf(ms, 0.1)
			what.append(parts)
			before = world.spent.duplicate()
		var order := range(times.size())
		order.sort_custom(func(a, b): return times[a] > times[b])
		var total := 0.0
		for t in times:
			total += t
		var over20 := 0
		var over83 := 0
		for t in times:
			if t > 20.0:
				over20 += 1
			if t > 8.34:
				over83 += 1
		var worst := []
		for k in order:
			var far := true
			for w in worst:
				if Vector2(w["x"], w["z"]).distance_to(where[k]) < 60.0:
					far = false
			if far:
				worst.append({"ms": snappedf(times[k], 0.01), "x": snappedf(where[k].x, 1.0), "z": snappedf(where[k].y, 1.0), "street": world.locate(where[k].x, where[k].y)["street"], "draw_calls": draws[k], "in": what[k]})
			if worst.size() >= 10:
				break
		var sorted := times.duplicate()
		sorted.sort()
		var mean_draws := 0
		for d in draws:
			mean_draws += d
		var run := {"frames": times.size(), "mean_ms": snappedf(total / times.size(), 0.01), "median_ms": snappedf(sorted[sorted.size() / 2], 0.01),
			"p99_ms": snappedf(sorted[int(sorted.size() * 0.99)], 0.01), "max_ms": snappedf(sorted[sorted.size() - 1], 0.01),
			"frames_over_20ms": over20, "share_over_8_3ms": snappedf(float(over83) / times.size(), 0.0001), "frames_ahead_of_the_map": late, "mean_draw_calls": mean_draws / maxi(draws.size(), 1), "worst": worst}
		out["runs"]["%02d:00" % int(hour)] = run
		print("BENCH %02d:00  frames %d  mean %.2f ms  p99 %.2f  max %.2f  over 20 ms: %d  over 8.3 ms: %.2f %%  draw calls %d  ahead of the map: %d" % [int(hour), run["frames"], run["mean_ms"], run["p99_ms"], run["max_ms"], over20, 100.0 * run["share_over_8_3ms"], run["mean_draw_calls"], late])
		for w in worst.slice(0, 5):
			print("   ", w)
	var f := FileAccess.open("res://data/" + _arg("--out", "bench.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  "))
	f.close()


func _shot(name: String) -> void:
	await _frames(3)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://data/" + name)


func _go(at: Vector2, lift := 0.6) -> void:
	m.player.global_position = Vector3(at.x, m.jobs.ground(at) + lift, at.y)
	m.player.velocity = Vector3.ZERO
	m.player.reset_physics_interpolation()
	m.world.update_streaming(m.player.global_position)
	m.world.flush(m.player.global_position)
	await _frames(4)


## `--jobs`: the jobs, the sights and the ferry (scripts/jobs.gd). Says where each job starts and whether there is
## ground to stand on there, where each sight is, then runs a taxi shift, the bus line and a run against the clock
## by putting the vehicle at each goal in turn, boards the ferry, and saves pictures of the panel, a sight's card,
## the journal and the bus (data/jobs_*.png). Nothing is written to the player's own progress.
func _jobs() -> void:
	var jobs = m.jobs
	var player = m.player
	jobs.set("FILE_OFF", true)
	var bad := 0
	for j in jobs.jobs:
		var at: Vector2 = j["at"]
		var h: float = m.world.height_at(at.x, at.y)
		var wet: bool = not m.world.water_at(at.x, at.y).is_empty() and float(m.world.water_at(at.x, at.y)["depth"]) > 0.5
		print("JOB %-34s at %7.0f %7.0f  ground %6.1f  %s  needs %s" % [j["title"], at.x, at.y, h, "IN WATER" if wet else "ok", j["needs"]])
		if wet and not j.has("swim"):
			bad += 1
	var line: Dictionary = m.traffic.line_points(1 if m.traffic.buses.size() > 1 else 0)
	print("JOBS bus line: ", (line["stops"] as Array).size(), " stops, ", (line["way"] as PackedVector2Array).size() * 5, " m; the bus stands at ", m.bus.global_position)
	for s in jobs.sights:
		var at2: Vector2 = s["at"]
		var where: Dictionary = m.world.locate(at2.x, at2.y)
		print("SIGHT %-22s %7.0f %7.0f  ground %6.1f  %s, %s" % [s["name"], at2.x, at2.y, m.world.height_at(at2.x, at2.y), where["street"], where["district"]])
	print("JOBS places to drive between: ", jobs._places.size())
	# a sight found by going there
	jobs.found.clear()
	await _go(Vector2(-10.6, -11.0))
	await _frames(20)
	print("JOBS sights found after standing by Rosepiken: ", jobs.found.keys())
	await _shot("jobs_sight.png")
	# a taxi shift: into the Volvo, to the rank, three fares
	var car: Node3D = player.vehicles[1]
	for j in jobs.jobs:
		var veh: Node3D = null
		for v in player.vehicles:
			if (j["needs"] as Array).has(str(v.LABEL)) and (veh == null or v == car):
				veh = v
		if player.driving:
			player._toggle_atv(true)
		if veh != null:
			await _go(Vector2(veh.global_position.x, veh.global_position.z) + Vector2(1.5, 0))
			player.global_position = veh.global_position + Vector3(0.8, 0.3, 0)
			player._toggle_atv()
			await _frames(5)
		if j["id"] != "bus":
			await _go(j["at"], 0.3)
		await _frames(10)
		print("JOBS at the start of '", j["title"], "': near job ", jobs._near_job, ", driving ", player.vehicle_label())
		jobs.press_job()
		if jobs.active.is_empty():
			print("JOBS FAILED to start ", j["id"])
			bad += 1
			continue
		var steps := 0
		var shot := false
		while not jobs.active.is_empty() and steps < 80:
			var marks: Array = jobs.active["marks"]
			var mk: Vector2 = marks[int(jobs.active["step"])]
			await _go(mk, 0.3)
			if not shot and steps == 1:
				shot = true
				await _shot("jobs_%s.png" % j["id"])
			var waited := 0
			if jobs.active.is_empty():
				break
			var step_was: int = jobs.active["step"]
			var fares_was: int = jobs.active.get("fares", 0)
			while not jobs.active.is_empty() and int(jobs.active["step"]) == step_was and int(jobs.active.get("fares", 0)) == fares_was and waited < 600:
				player.velocity = Vector3.ZERO
				player.set("_drive_speed", 0.0)
				# (held at the goal: put down crosswise on a road along a steep bank, the 12 m bus stood half on the
				# bank and slid away from the stop at Bekkevollvegen, and the stop was never counted: 20 Nov)
				if Vector2(player.global_position.x, player.global_position.z).distance_to(mk) > 4.0:
					player.global_position = Vector3(mk.x, jobs.ground(mk) + 0.3, mk.y)
					player.reset_physics_interpolation()
				await get_tree().physics_frame
				waited += 1
			steps += 1
		print("JOBS '", j["title"], "' ended after ", steps, " goals: ", jobs.last_result)
		if not jobs.active.is_empty() or not jobs.done.has(j["id"]):
			bad += 1
	if player.driving:
		player._toggle_atv(true)
	# the bus as it stands
	var bp: Vector3 = m.bus.global_position
	await _go(Vector2(bp.x, bp.z) + Vector2(9.0, 9.0))
	player.yaw = atan2(9.0, 9.0)
	await _shot("jobs_bus_parked.png")
	# the journal
	jobs.toggle_journal()
	await _shot("jobs_journal.png")
	jobs.toggle_journal()
	# the ferry
	if not jobs._ferry.is_empty():                       # (alongside, whatever it was doing)
		jobs._ferry["t"] = 0.0
		jobs._ferry["going"] = true
		jobs._ferry["wait"] = 30.0
		jobs._ferry["v"] = 0.0
	print("JOBS ferry quay at ", jobs._ferry_quay, ", ferry lies at ", jobs._ferry.get("a", "none"), ", driving ", player.driving)
	await _go(jobs._ferry_quay)
	await _frames(10)
	print("JOBS player at ", player.global_position)
	print("JOBS at the ferry quay: can board ", jobs._can_board(), ", ferry waits ", snappedf(float(jobs._ferry.get("wait", -1.0)), 0.1), " s")
	jobs.press_job()
	await _frames(30)
	print("JOBS aboard: ", jobs.aboard, ", at ", player.global_position)
	await _shot("jobs_ferry.png")
	if jobs.aboard:
		jobs._ferry["wait"] = 0.0
		for i in 600:
			m.traffic.hurry_ferry(0.5)
			await get_tree().physics_frame
		print("JOBS after sailing a while: ferry t ", snappedf(float(jobs._ferry["t"]), 1.0), " going ", jobs._ferry["going"], ", player at ", player.global_position)
	print("JOBS ", "OK" if bad == 0 else "PROBLEMS: %d" % bad)


## `--winter`: the season, the occasions and the view from the seat. Pictures of the square in summer and in
## winter with snow falling, of the stadium on a match day at night, of the menu with its new rows, and from
## the driver's seat of the Volvo and the bus (data/winter_*.png, data/seat_*.png).
func _winter() -> void:
	var player = m.player
	m.daytime.hours = 13.0
	m.daytime.rate = 0.0
	m.daytime.apply()
	await _go(Vector2(-8.5, -20.0))
	player.yaw = 0.3
	await _frames(30)
	await _shot("winter_0_summer.png")
	m.weather.winter = true
	m.weather.kind = "rain"
	m.weather.now = m.weather.SET["rain"].duplicate()
	for i in 400:
		await get_tree().process_frame
	print("WINTER snow ", snappedf(m.weather.snow, 0.01), "  falling ", m.weather._rain.emitting)
	await _shot("winter_1_square.png")
	await _go(Vector2(300.0, -330.0))
	player.yaw = 0.0
	player.pitch = -0.1
	await _frames(40)
	await _shot("winter_2_town.png")
	m.menu.open()
	await _shot("winter_3_menu.png")
	m.menu.occasion = 2
	m.menu._apply_occasion()
	m.menu.close()
	m.daytime.hours = 21.5
	m.daytime.apply()
	await _go(Vector2(-380.0, 420.0))
	player.yaw = PI * 0.5
	player.pitch = 0.05
	for i in 200:
		await get_tree().process_frame
	print("WINTER match day: lights ", m.molde._match_root != null, "  crowd going to ", m.people.crowd_at)
	await _shot("winter_4_match.png")
	await _go(Vector2(-560.0, 455.0))
	player.yaw = PI * 0.5
	player.pitch = 0.25
	await _frames(30)
	await _shot("winter_5_pitch.png")
	await _go(Vector2(-150.0, 250.0))
	player.yaw = PI * 0.5
	player.pitch = 0.1
	await _frames(30)
	await _shot("winter_6_afar.png")
	m.weather.winter = false
	m.daytime.hours = 13.0
	m.daytime.apply()
	for which in [1, 6]:
		var v: Node3D = player.vehicles[which]
		await _go(Vector2(v.global_position.x, v.global_position.z) + Vector2(1.5, 0))
		player.global_position = v.global_position + Vector3(0.8, 0.3, 0)
		player._toggle_atv()
		await _frames(20)
		player.set_seat_view(true)
		await _frames(20)
		await _shot("seat_%d.png" % which)
		print("WINTER seat view in ", player.vehicle_label(), ": ", player.seat_view)
		player._toggle_atv(true)
		await _frames(5)
	print("WINTER OK")


## `--lamps`: do the street lamps flicker at night? The camera goes along the bench route at 23:00 at 50 km/h
## in even steps, and after every frame each lit lamp's strength is read (scripts/daytime.gd gives the nearest
## lamps a light each). A lamp flickers if its light jumps by more than a fifth of full strength from one
## frame to the next, or goes out and comes back within a second. (Comparing pictures was tried first: the
## camera's own small movements drowned everything else.)
func _lamps() -> void:
	var world = m.world
	var player = m.player
	var day = m.daytime
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	day.hours = 23.0
	day.rate = 0.0
	day.apply()
	var route := PackedVector2Array()
	var stops := [Vector2(-560, 60), Vector2(-8, -30), Vector2(120, 35)]
	for k in stops.size() - 1:
		route.append_array(m.traffic.route_points(stops[k], stops[k + 1]))
	if route.size() < 10:
		print("LAMPS FAILED: no route")
		return
	var p0 := route[0]
	player.global_position = Vector3(p0.x, world.height_at(p0.x, p0.y) + 0.6, p0.y)
	world.update_streaming(player.global_position)
	world.flush(player.global_position)
	await _frames(120)
	var full: float = 2.2
	var was := {}                  # lamp -> strength last frame
	var went_out := {}             # lamp -> frame it went out
	var jumps := 0
	var blinks := 0
	var worst := 0.0
	var worst_at := Vector2.ZERO
	var most_lit := 0
	var i := 0
	var along := 0.0
	var n := 0
	while i < route.size() - 1:
		along += 13.9 / 144.0
		while i < route.size() - 1 and along > route[i].distance_to(route[i + 1]):
			along -= route[i].distance_to(route[i + 1])
			i += 1
		if i >= route.size() - 1:
			break
		var seg := route[i + 1] - route[i]
		var q := route[i] + seg.normalized() * along
		if Vector2(player.global_position.x, player.global_position.z).distance_to(q) > 1.0:
			went_out.clear()                               # (where two legs of the route meet the camera is moved: not a blink)
		player.global_position = Vector3(q.x, world.height_at(q.x, q.y) + 0.6, q.y)
		world.update_streaming(player.global_position)
		await get_tree().process_frame
		n += 1
		var now := {}
		for lamp in day._light_of:
			var l: OmniLight3D = day._lights[day._light_of[lamp]]
			now[lamp] = l.light_energy if l.visible else 0.0
		most_lit = maxi(most_lit, now.size())
		for lamp in now:
			var before: float = was.get(lamp, 0.0)
			var d: float = absf(float(now[lamp]) - before)
			if d > worst and n > 150:
				worst = d
				worst_at = q
			if d > 0.2 * full and n > 150:               # (not the first second, when they all come on)
				jumps += 1
			# (out and back at the very edge of reach, where it is too faint to see, is not a blink)
			if float(now[lamp]) > 0.1 * full and went_out.has(lamp) and n - int(went_out[lamp]) < 40:      # (within a quarter of a second: slower is a fade, as when turning round)
				blinks += 1
				print("LAMPS blink: lamp ", lamp, " at ", day._lamp_at[lamp], " camera ", q, " ", snappedf(q.distance_to(Vector2(day._lamp_at[lamp].x, day._lamp_at[lamp].z)), 0.1), " m off, out for ", n - int(went_out[lamp]), " frames; route point ", i, " of ", route.size(), ", step to next ", snappedf(route[i].distance_to(route[i + 1]), 0.1))
				went_out.erase(lamp)
		for lamp in was:
			if float(was[lamp]) > 0.01 and float(now.get(lamp, 0.0)) <= 0.01:
				went_out[lamp] = n
				if float(was[lamp]) > 0.2 * full:
					jumps += 1                                 # (put out at a stroke)
					if float(was[lamp]) > worst:
						worst = float(was[lamp])
						worst_at = q
		was = now
	print("LAMPS %d frames over %d m at 23:00, up to %d lamps lit: jumps of over a fifth in one frame: %d; out and on again within a quarter of a second: %d; the largest change in one frame %.0f %% of full, at %.0f %.0f (%s)" % [n, int(n * 13.9 / 144.0), most_lit, jumps, blinks, 100.0 * worst / full, worst_at.x, worst_at.y, world.locate(worst_at.x, worst_at.y)["street"]])
	print("LAMPS ", "OK" if jumps == 0 and blinks == 0 else "PROBLEMS: the lamps flicker")


## `--film`: movement seen moving. Three short strips of pictures a tenth of a second apart, each put side by
## side in one file: the player's breaststroke and crawl from the side (data/film_breast.png, film_crawl.png),
## and a townsperson walking past (data/film_walker.png).
func _film() -> void:
	var player = m.player
	var world = m.world
	m.daytime.hours = 13.0
	m.daytime.rate = 0.0
	m.daytime.apply()
	# the fjord off the shore by the stadium: deep water
	var at := Vector2(-640.0, 600.0)
	for k in 100:
		var wa: Dictionary = world.water_at(at.x, at.y)
		if not wa.is_empty() and float(wa["depth"]) > 2.5:
			break
		at.y += 6.0
	player.global_position = Vector3(at.x, 0.0, at.y)
	world.update_streaming(player.global_position)
	world.flush(player.global_position)
	await _frames(60)
	for stroke in ["breast", "crawl"]:
		player.stamina = 1.0
		player.yaw = 0.0                                  # swimming north-south, the camera looking from the side
		Input.action_press("move_forward")
		if stroke == "crawl":
			Input.action_press("sprint")
		for k in 90:
			await get_tree().physics_frame
		var strip: Array = []
		for shot in 8:
			for k in 6:
				await get_tree().physics_frame
			var cam: Camera3D = get_viewport().get_camera_3d()
			# (the picture is taken by a camera of our own from the side, 4 m off)
			var side := Camera3D.new()
			add_child(side)
			var pp: Vector3 = player.global_position
			side.global_position = pp + Vector3(4.0, 0.9, 0.0)
			side.look_at(pp + Vector3(0, 0.1, 0))
			side.fov = 40.0
			side.current = true
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			strip.append(get_viewport().get_texture().get_image())
			cam.current = true
			side.queue_free()
		Input.action_release("move_forward")
		Input.action_release("sprint")
		_strip(strip, "film_%s.png" % stroke)
		print("FILM %s: swimming %s, crawling %s, 8 pictures" % [stroke, player.swimming, player.crawling])
	# a townsperson walking: the first walker found in the centre
	await _go(Vector2(40.0, -15.0))
	var who = null
	for tries in 900:
		await get_tree().physics_frame
		for f in m.people.people:
			if f["kind"] == "walker" and not f.has("shop") and (f["node"] as Node3D).global_position.distance_to(player.global_position) < 45.0:
				who = f
		if who != null:
			break
	if who == null:
		print("FILM no walker came by")
		return
	var strip2: Array = []
	for shot in 8:
		for k in 6:
			await get_tree().physics_frame
		var node: Node3D = who["node"]
		if not is_instance_valid(node):
			break
		var cam2: Camera3D = get_viewport().get_camera_3d()
		var side2 := Camera3D.new()
		add_child(side2)
		var right: Vector3 = node.global_transform.basis.x.normalized()
		side2.global_position = node.global_position + right * 3.6 + Vector3(0, 1.0, 0)
		side2.look_at(node.global_position + Vector3(0, 0.9, 0))
		side2.fov = 40.0
		side2.current = true
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		strip2.append(get_viewport().get_texture().get_image())
		cam2.current = true
		side2.queue_free()
	_strip(strip2, "film_walker.png")
	print("FILM walker: ", strip2.size(), " pictures")


func _strip(pics: Array, name: String) -> void:
	if pics.is_empty():
		return
	var w := 300
	var h := 300
	var out := Image.create(w * pics.size(), h, false, Image.FORMAT_RGB8)
	for k in pics.size():
		var im: Image = pics[k]
		im.convert(Image.FORMAT_RGB8)
		var s := mini(im.get_width(), im.get_height())
		var cut := im.get_region(Rect2i((im.get_width() - s) / 2, (im.get_height() - s) / 2, s, s))
		cut.resize(w, h, Image.INTERPOLATE_BILINEAR)
		out.blit_rect(cut, Rect2i(0, 0, w, h), Vector2i(k * w, 0))
	out.save_png("res://data/" + name)


## `--indoors`: the way into Molde Storsenter (scripts/indoors.gd). Walks the player at the building from four
## sides until a wall is met, says whether the way in is offered there, goes in, takes pictures down the hall
## and back toward the way out (data/indoors_*.png), walks to the way out and leaves; says where the player
## came out.
func _indoors() -> void:
	var player = m.player
	var ind = m.indoors
	if ind.places.is_empty():
		print("INDOORS FAILED: no place with a way in")
		return
	var place: Dictionary = ind.places[0]
	var at: Vector2 = place["at"]
	print("INDOORS ", place["name"], " at ", at, ", shops: ", place["shops"])
	var offered := 0
	var from_where := Vector3.ZERO
	for a in [0.0, PI * 0.5, PI, PI * 1.5]:
		var dir := Vector2(cos(a), sin(a))
		await _go(at + dir * 110.0)
		var met := false
		for step in 1500:
			var pp: Vector3 = player.global_position
			var to := (at - Vector2(pp.x, pp.z)).normalized()
			player.velocity = Vector3(to.x * 4.0, player.velocity.y, to.y * 4.0)
			player.yaw = atan2(-to.x, -to.y)
			await get_tree().physics_frame
			if ind._at_door() >= 0:
				met = true
				break
		player.velocity = Vector3.ZERO
		for w in 40:
			await get_tree().physics_frame
		await _frames(3)
		var d := Vector2(player.global_position.x, player.global_position.z).distance_to(at)
		print("INDOORS from %3d degrees: wall met %s, %.0f m from the middle, way in offered: %s; walls known: %d" % [int(rad_to_deg(a)), met, d, ind._prompt.visible, (place.get("walls", []) as Array).size()])
		if ind._prompt.visible:
			offered += 1
			from_where = player.global_position
			if offered == 1:
				await _shot("indoors_0_door.png")
	if offered == 0:
		print("INDOORS FAILED: the way in was offered from no side")
		return
	ind.enter(0)
	await _frames(40)
	print("INDOORS inside: ", ind.inside, ", on the floor: ", player.is_on_floor(), ", at ", player.global_position)
	await _shot("indoors_1_hall.png")
	var room: Vector3 = ind._room.global_position
	player.global_position = room + Vector3(8.0, 0.3, 2.0)
	player.yaw = PI * 0.5
	player.reset_physics_interpolation()
	await _frames(40)
	await _shot("indoors_2_back.png")
	var fell: bool = player.global_position.y < room.y - 0.5
	player.global_position = room + Vector3(-ind.HALL.x * 0.5 + 2.0, 0.3, 0.0)
	await _frames(40)
	print("INDOORS at the way out: offered ", ind._prompt.visible, " '", ind._prompt.text, "'")
	var ok_out: bool = ind._prompt.visible
	ind.leave()
	await _frames(20)
	print("INDOORS out again at ", player.global_position, ", ", snappedf(player.global_position.distance_to(from_where), 0.1), " m from where they went in")
	print("INDOORS ", "OK" if not fell and ok_out and not ind.inside else "PROBLEMS")


## `--bridges`: is the road whole where it goes onto a bridge and off it? At both ends of every bridge (road
## bridges and footbridges), rays are sent down across the whole width at steps from 1 m on the deck to 2.5 m
## beyond its end. Each says what it met first (the deck or paving: good; the bare ground or nothing: a gap) and
## how high. Counted per end: places where the ground shows, and the largest step in height from one ray to
## the next along the road. The worst ends are photographed from above (data/bridge_*.png).
func _bridges() -> void:
	var world = m.world
	var player = m.player
	var ends: Array = []
	for w in world.detail.ways.size():
		var way: Array = world.detail.ways[w]
		if int(way[1]) != 4:
			continue
		var pts: PackedVector2Array = way[3]
		var hs: PackedFloat32Array = way[8]
		if pts.size() < 2:
			continue
		for e in 2:
			var at: Vector2 = pts[0] if e == 0 else pts[pts.size() - 1]
			var inner: Vector2 = pts[1] if e == 0 else pts[pts.size() - 2]
			if at.length() > float(_arg("--within", "100000")) or float(way[0]) * 2.0 < float(_arg("--wider", "0")):
				continue
			ends.append({"way": w, "half": float(way[0]), "at": at, "out": (at - inner).normalized(), "y": hs[0] if e == 0 else hs[hs.size() - 1],
				"walk": float(maxi(int(float(way[10 if e == 0 else 11])) / 1000, int(float(way[10 if e == 0 else 11])) % 1000)) / 10.0})
	print("BRIDGES ", ends.size(), " ends of bridges")
	var bad: Array = []
	for en in ends:
		var at: Vector2 = en["at"]
		var out: Vector2 = en["out"]
		var side := Vector2(out.y, -out.x)
		var half: float = en["half"]
		await _go(at - out * 2.0, 0.4)
		player.global_position.y = float(en["y"]) + 0.5
		await _frames(6)
		for k in 4:
			await get_tree().physics_frame
		var space: PhysicsDirectSpaceState3D = player.get_world_3d().direct_space_state
		var gaps := 0
		var step := 0.0
		var where := ""
		var road: bool = half > 2.0
		# (a road bridge is judged over its carriageway, clear of the parapets and of a sidewalk beside it; a
		# footbridge that goes on as a gravel path has bare ground beyond it by right, and is only told of)
		var reach: float = (half - 1.2) if road else (half - 0.15)
		var rows := maxi(3, int(reach / 0.5) * 2 + 1)
		var wet_end := false
		for r in rows:
			var off := lerpf(-reach, reach, float(r) / float(rows - 1))
			var deck_y := NAN
			var last_y := NAN
			for d in [-1.0, -0.3, 0.05, 0.25, 0.5, 0.8, 1.2, 1.8, 2.5]:
				var q: Vector2 = at + out * float(d) + side * off
				var ray := PhysicsRayQueryParameters3D.create(Vector3(q.x, float(en["y"]) + 2.5, q.y), Vector3(q.x, float(en["y"]) - 6.0, q.y))
				ray.exclude = [player.get_rid()]
				var hit := space.intersect_ray(ray)
				var what := "nothing"
				var y := NAN
				if not hit.is_empty():
					y = hit["position"].y
					var path := str((hit["collider"] as Node).get_path())
					what = "ground" if path.contains("Terrain") else "paved"
				if OS.get_cmdline_user_args().has("--profile") and (r == rows / 2 or r == 0 or r == rows - 1):
					print("   off %5.1f  %5.2f m beyond: %-7s %s" % [off, d, what, ("%+.2f" % (y - float(en["y"]))) if not is_nan(y) else ""])
				if float(d) < 0.0:
					if what == "paved":
						deck_y = y
						last_y = y
					continue
				if r == rows / 2 and is_equal_approx(float(d), 1.2) and (what == "nothing" or (not is_nan(y) and y < float(en["y"]) - 1.5)):
					wet_end = true
				if what != "paved":
					if at.distance_to(Vector2(5200.9, -1188.6)) < 1.0 and absf(off) < 2.0:
						continue                                   # (Fannefjordsvegen: the grass of the island between the lanes)
					gaps += 1
					if where == "":
						where = "%s %.1f m beyond, %.1f m off the middle" % [what, d, off]
				else:
					# a step is a jump from one point to the next, 20 to 40 cm on (a road that climbs away from the
					# bridge is not one), judged where cars go
					if not is_nan(last_y) and float(d) <= 1.2 and absf(off) < half - float(en["walk"]) - 0.5 and absf(y - last_y) > step:
						step = absf(y - last_y)
						if OS.get_cmdline_user_args().has("--profile"):
							print("   step %.2f at off %.1f, %.2f m beyond (walk %.1f)" % [step, off, d, float(en["walk"])])
					last_y = y
		en["gaps"] = gaps
		en["step"] = step
		if wet_end:
			print("BRIDGES end at %7.1f %7.1f (%s): ends over the water, not judged" % [at.x, at.y, world.locate(at.x, at.y)["street"]])
			continue
		var paved_road: bool = road and gaps < rows * 4                 # (a gravel road has no paving to be whole)
		if paved_road and (gaps > 0 or step > 0.08):
			bad.append(en)
			print("BRIDGES end at %7.1f %7.1f (%s, %.1f m wide): ground showing at %d points (%s); the road within 1.2 m stands up to %.2f m off the deck" % [at.x, at.y, world.locate(at.x, at.y)["street"], half * 2.0, gaps, where, step])
		elif not road and step > 0.25:
			print("BRIDGES footbridge end at %7.1f %7.1f: the path within 1.2 m stands up to %.2f m off the deck (told of, not counted)" % [at.x, at.y, step])
	bad.sort_custom(func(a, b): return int(a["gaps"]) * 10.0 + float(a["step"]) * 100.0 > int(b["gaps"]) * 10.0 + float(b["step"]) * 100.0)
	var shots := 0
	for en in bad.slice(0, 12):
		var at2: Vector2 = en["at"]
		var out2: Vector2 = en["out"]
		await _go(at2 + out2 * 6.0, 0.4)
		await _frames(10)
		var cam: Camera3D = get_viewport().get_camera_3d()
		var top := Camera3D.new()
		add_child(top)
		top.global_position = Vector3(at2.x + out2.x * 9.0, float(en["y"]) + 9.0, at2.y + out2.y * 9.0)
		top.look_at(Vector3(at2.x, float(en["y"]), at2.y))
		top.fov = 60.0
		top.current = true
		m.hud.visible = false
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png("res://data/bridge_%02d.png" % shots)
		print("BRIDGES picture bridge_%02d.png: %.1f %.1f %s" % [shots, at2.x, at2.y, world.locate(at2.x, at2.y)["street"]])
		cam.current = true
		top.queue_free()
		shots += 1
	print("BRIDGES ends of paved road bridges with a gap or a step: %d (of %d ends of all bridges)" % [bad.size(), ends.size()])
	print("BRIDGES ", "OK" if bad.is_empty() else "PROBLEMS: %d" % bad.size())


## The top of what one sees at a point: the paving where there is some, else the ground.
func _top(x: float, z: float) -> float:
	var t: float = m.world.detail.top_at(x, z)
	return m.world.height_at(x, z) if is_nan(t) else t


## `--standing`: does everything stand on the ground? For each bench, shelter, parked car, sign and so on
## (world/props.bin), and each thing built by scripts/molde.gd, the corners of its foot are held against the
## ground or paving under them. A corner more than 25 cm in the air, or a wide thing more than 45 cm into the
## ground, is counted, by kind, with the worst of each named. `--shots` photographs the worst of each kind.
func _standing() -> void:
	var P = m.world.props
	var names := {P.LAMP: "lamp", P.SHELTER: "bus shelter", P.BUS_SIGN: "bus sign", P.BENCH: "bench", P.FLAGPOLE: "flagpole", P.CAR: "parked car",
		P.GIVE_WAY: "give-way sign", P.ROUND_SIGN: "round sign", P.CROSSING_SIGN: "crossing sign", P.SIGNAL: "signal", P.POST_BOX: "post box",
		P.PICNIC: "picnic table", P.SWINGS: "swings", P.VIEWPOINT: "viewpoint railing", P.GIVE_WAY_ROUND: "give-way with roundabout sign",
		P.NAME_SIGN: "street-name sign", P.PLANTER: "flower tub", P.AIRLINER: "airliner", P.PYLON: "pylon"}
	var found := {}                 # name -> [count, in the air, sunk, worst gap, where]
	var things: Array = []          # [name, Transform3D, half x, half z]
	for ck in P.cells:
		for e in P.cells[ck]:
			var kind: int = e[0]
			if not names.has(kind) or not (P.SOLID[kind] is Vector3):
				continue
			var sz: Vector3 = P.SOLID[kind]
			var o: Vector3 = e[1].origin
			if kind in P.LEVEL or kind == P.PYLON:
				continue                    # stands level on concrete, or with its legs in the slope: as meant
			things.append([names[kind], e[1], sz.x * (0.85 if kind == P.CAR else 1.0), sz.z * (0.65 if kind == P.CAR else 1.0)])
	for child in m.molde.get_children():
		if child is MeshInstance3D and child.mesh != null:
			var bb: AABB = child.mesh.get_aabb()
			if child.name == "RoseBed":                         # stands on the town hall's terrace, which is not the ground
				continue
			if child.has_meta("on_wall"):                       # a name board hung on a wall
				continue
			if bb.size.x > 8.0 or bb.size.z > 8.0:              # (a lane, a building site: not one thing on one spot)
				continue
			var xf: Transform3D = child.global_transform * Transform3D(Basis(), Vector3(bb.get_center().x, bb.position.y, bb.get_center().z))
			things.append(["built: " + String(child.name), xf, bb.size.x * 0.5, bb.size.z * 0.5])
	var worst := {}
	for t in things:
		var xf: Transform3D = t[1]
		var hx: float = maxf(float(t[2]), 0.05)
		var hz: float = maxf(float(t[3]), 0.05)
		var up := -1000.0             # the highest any corner stands over the ground
		var down := 1000.0            # the lowest
		for c in [Vector3(-hx, 0, -hz), Vector3(hx, 0, -hz), Vector3(-hx, 0, hz), Vector3(hx, 0, hz), Vector3.ZERO]:
			var q: Vector3 = xf * (c as Vector3)
			var gap := q.y - _top(q.x, q.z)
			up = maxf(up, gap)
			down = minf(down, gap)
		var name: String = t[0]
		if not found.has(name):
			found[name] = [0, 0, 0, 0.0, Vector3.ZERO, 0.0, Vector3.ZERO]
		var f: Array = found[name]
		f[0] += 1
		var wide := hx > 0.3 or hz > 0.3
		if up > 0.25:                 # (a kerb is 23 cm: a thing at the edge of one is not in the air)
			f[1] += 1
		if wide and down < -0.45:
			f[2] += 1
		if up > float(f[3]):
			f[3] = up
			f[4] = xf.origin
		if wide and down < float(f[5]):
			f[5] = down
			f[6] = xf.origin
	var bad := 0
	var keys := found.keys()
	keys.sort()
	for name in keys:
		var f: Array = found[name]
		bad += int(f[1]) + int(f[2])
		print("STANDING %-32s %6d  in the air: %5d  sunk: %5d  worst up %.2f at (%.0f, %.0f)  worst down %.2f at (%.0f, %.0f)" % [name, f[0], f[1], f[2], f[3], f[4].x, f[4].z, f[5], f[6].x, f[6].z])
		if "--shots" in OS.get_cmdline_user_args() and (int(f[1]) > 0 or int(f[2]) > 0):
			var at: Vector3 = f[4] if int(f[1]) > 0 else f[6]
			await _go(Vector2(at.x + 5.0, at.z + 5.0))
			m.player.yaw = PI * 0.25
			m.player.pitch = -0.15
			m.player._arm.spring_length = 3.0
			await _frames(30)
			await _shot("standing_%s.png" % String(name).replace(" ", "_").replace(":", ""))
	print("STANDING ", "OK" if bad == 0 else "PROBLEMS", ": ", bad, " things in the air or sunk, of ", things.size())


## `--edges`: a ride along the roads out of town, which are looked at least: the main road west to the tunnel,
## east to the airport, and from there to the tunnel south. A picture every `--every=` metres (250) from over the
## road, looking along it (data/edges_NNN.png), and for each the height of the asphalt under the camera against
## the one 2 m on: a step of more than 15 cm is counted.
func _edges() -> void:
	var player = m.player
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	var every := float(_arg("--every", "250"))
	var legs := [[Vector2(-560, 60), Vector2(-5800, 480)], [Vector2(2600, -480), Vector2(5600, -700)], [Vector2(5200, -1190), Vector2(5760, -3410)]]
	var n := 0
	var steps := 0
	for leg in legs:
		var route := PackedVector2Array()                 # (the way-finder reaches about a kilometre: in hops of 600 m)
		var hops := maxi(1, int((leg[1] as Vector2).distance_to(leg[0]) / 600.0))
		for h in hops:
			route.append_array(m.traffic.route_points((leg[0] as Vector2).lerp(leg[1], float(h) / float(hops)), (leg[0] as Vector2).lerp(leg[1], float(h + 1) / float(hops))))
		if route.size() < 4:
			print("EDGES no route from ", leg[0], " to ", leg[1])
			continue
		var gone := every
		for i in route.size() - 1:
			var seg: Vector2 = route[i + 1] - route[i]
			var ya: float = _top(route[i].x, route[i].y)
			var yb: float = _top(route[i + 1].x, route[i + 1].y)
			if seg.length() < 4.0 and absf(yb - ya) > 0.15 + seg.length() * 0.2:
				steps += 1
				print("EDGES step of %.2f m at (%.0f, %.0f)" % [yb - ya, route[i].x, route[i].y])
			gone += seg.length()
			if gone < every:
				continue
			gone = 0.0
			var q := route[i]
			player.global_position = Vector3(q.x, _top(q.x, q.y) + 0.6, q.y)
			player.reset_physics_interpolation()
			player.yaw = atan2(-seg.x, -seg.y)
			player.pitch = -0.28
			player._arm.spring_length = 11.0
			m.world.update_streaming(player.global_position)
			m.world.flush(player.global_position)
			await _frames(12)
			await _shot("edges_%03d.png" % n)
			print("EDGES picture %03d at (%.0f, %.0f) %s" % [n, q.x, q.y, m.world.locate(q.x, q.y)["street"]])
			n += 1
	print("EDGES ", n, " pictures; steps along the road: ", steps)
