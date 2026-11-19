extends Node
## Checks that run the game by themselves and quit (`./run.sh -- --bench` and so on). The older ones are in
## main.gd; the ones added with the plan of 18 November are here. tools/check.sh runs them all in turn.

const KNOWN := ["--bench", "--jobs", "--winter", "--lamps", "--film", "--indoors"]

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
