extends Node
## Checks that run the game by themselves and quit (`./run.sh -- --bench` and so on). The older ones are in
## main.gd; the ones added with the plan of 18 November are here. tools/check.sh runs them all in turn.

const KNOWN := ["--bench", "--jobs", "--winter"]

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
		if j["id"] != "taxi" and j["id"] != "bus" and j["id"] != "varden":
			continue
		var veh: Node3D = car if j["id"] == "taxi" else (m.bus if j["id"] == "bus" else player.vehicles[5])
		if player.driving:
			player._toggle_atv(true)
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
