extends Node3D
## Entry point: input map, sky and light, then the world, the player and the HUD.

const WorldScript := preload("res://scripts/world.gd")
const PlayerScript := preload("res://scripts/player.gd")
const HudScript := preload("res://scripts/hud.gd")
const AtvScript := preload("res://scripts/atv.gd")
const CarScript := preload("res://scripts/car.gd")
const IntegraScript := preload("res://scripts/integra.gd")
const HeliScript := preload("res://scripts/heli.gd")
const MercedesScript := preload("res://scripts/mercedes.gd")
const BikeScript := preload("res://scripts/bike.gd")
const DevtoolScript := preload("res://scripts/devtool.gd")

var world
var player
var hud
var devtool

const HELI_AT := Vector2(14.0, 50.0)


func _ready() -> void:
	_setup_input()
	hud = HudScript.new()
	add_child(hud)
	hud.set_loading("")
	_setup_environment()

	world = WorldScript.new()
	world.name = "World"
	add_child(world)
	await world.build(hud)

	player = PlayerScript.new()
	player.name = "Player"
	player.world = world
	var s: Vector2 = world.spawn
	player.position = Vector3(s.x, world.height_at(s.x, s.y) + 0.5, s.y)
	player.yaw = 0.0                # facing north across Rådhusplassen, toward the town hall
	world.update_streaming(player.position)
	world.flush(player.position)
	add_child(player)

	# An ATV parked right beside the spawn point.
	var atv := Node3D.new()
	atv.name = "ATV"
	atv.set_script(AtvScript)
	atv.position = Vector3(s.x + 2.4, world.height_at(s.x + 2.4, s.y - 0.5), s.y - 0.5)
	add_child(atv)
	player.atv = atv
	# and a white Volvo 740 on the other side
	var car := Node3D.new()
	car.name = "Volvo"
	car.set_script(CarScript)
	car.position = Vector3(s.x - 4.5, world.height_at(s.x - 4.5, s.y + 1.0), s.y + 1.0)
	add_child(car)
	# and a Honda Integra beside it
	var integra := Node3D.new()
	integra.name = "Integra"
	integra.set_script(IntegraScript)
	integra.position = Vector3(s.x - 4.5, world.height_at(s.x - 4.5, s.y + 8.0), s.y + 8.0)        # behind the Volvo, clear of the fence
	add_child(integra)
	# a helicopter on the lower part of Torget, across Storgata from the square
	var heli := Node3D.new()
	heli.name = "Helicopter"
	heli.set_script(HeliScript)
	heli.position = Vector3(HELI_AT.x, world.height_at(HELI_AT.x, HELI_AT.y), HELI_AT.y)
	heli.rotation.y = PI
	add_child(heli)
	# a Mercedes estate in a drive on Langmyrvegen
	var mm: Array = world.meta.get("mercedes", [])
	var merc := Node3D.new()
	merc.name = "Mercedes"
	merc.set_script(MercedesScript)
	if mm.size() == 3:
		merc.position = Vector3(mm[0], world.height_at(mm[0], mm[1]), mm[1])
		merc.rotation.y = mm[2]
	add_child(merc)
	# a bicycle on the square
	var bb: Array = world.meta.get("bicycle", [])
	var bike := Node3D.new()
	bike.name = "Bicycle"
	bike.set_script(BikeScript)
	if bb.size() == 2:
		bike.position = Vector3(bb[0], world.height_at(bb[0], bb[1]) + 0.07, bb[1])
	add_child(bike)
	player.vehicles = [atv, car, integra, heli, merc, bike]
	if "--perf" in OS.get_cmdline_user_args():
		_perf_and_quit()
		return
	if "--drive" in OS.get_cmdline_user_args():
		_drive_and_quit()
		return
	if "--shot" in OS.get_cmdline_user_args():
		_screenshot_and_quit()
	elif not OS.has_feature("web"):                   # notes are written into the project folder, which a browser does not have
		devtool = DevtoolScript.new()                 # crosshair and notes (right mouse button)
		add_child(devtool)
		devtool.start(world, player)
		if "--notetest" in OS.get_cmdline_user_args():
			_notetest_and_quit()
		if "--car" in OS.get_cmdline_user_args():
			_car_test_and_quit()
		if "--count" in OS.get_cmdline_user_args():
			print("COUNT character ", _count_triangles(player._body), "  ATV ", _count_triangles(player.vehicles[0]))
			get_tree().quit()
		if "--bike" in OS.get_cmdline_user_args():
			_bike_test_and_quit()
		if "--heli" in OS.get_cmdline_user_args():
			_heli_test_and_quit()
	hud.start(world, player)


func _key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


func _axis(action: String, axis: JoyAxis, value: float) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action, 0.25)
	var ev := InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)


func _pad(action: String, button: JoyButton) -> void:
	var ev := InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _setup_input() -> void:
	_key("move_forward", [KEY_W, KEY_UP])
	_key("move_back", [KEY_S, KEY_DOWN])
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE])
	_key("sprint", [KEY_SHIFT])
	_key("fullscreen", [KEY_F11])
	_key("interact", [KEY_F])
	_key("descend", [KEY_CTRL, KEY_C])    # C as well: in a browser Ctrl+W closes the tab
	_pad("interact", JOY_BUTTON_Y)
	_axis("move_forward", JOY_AXIS_LEFT_Y, -1.0)
	_axis("move_back", JOY_AXIS_LEFT_Y, 1.0)
	_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_axis("move_right", JOY_AXIS_LEFT_X, 1.0)
	_axis("look_up", JOY_AXIS_RIGHT_Y, -1.0)
	_axis("look_down", JOY_AXIS_RIGHT_Y, 1.0)
	_axis("look_left", JOY_AXIS_RIGHT_X, -1.0)
	_axis("look_right", JOY_AXIS_RIGHT_X, 1.0)
	_pad("jump", JOY_BUTTON_A)
	_pad("sprint", JOY_BUTTON_LEFT_STICK)


func _setup_environment() -> void:
	# A low, smoke-stained autumn afternoon over the fjord.
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.33, 0.36, 0.41)
	sky_mat.sky_horizon_color = Color(0.66, 0.58, 0.50)
	sky_mat.ground_horizon_color = Color(0.66, 0.58, 0.50)
	sky_mat.ground_bottom_color = Color(0.10, 0.10, 0.10)
	sky_mat.sun_angle_max = 25.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color(0.56, 0.52, 0.48)
	env.fog_density = 0.00075
	env.fog_aerial_perspective = 0.5
	env.fog_sky_affect = 0.25
	env.glow_enabled = true
	env.ssao_enabled = true
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22.0, -50.0, 0.0)      # low in the south-west
	sun.light_color = Color(1.0, 0.84, 0.68)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 380.0
	add_child(sun)


## `./run.sh -- --shot` saves a set of fixed views to data/shot0..N.png and exits (for checking changes).
func _screenshot_and_quit() -> void:
	player.set_process_unhandled_input(false)
	# [x, z, yaw, pitch, camera distance]
	var views := [
		[-8.5, -37.7, 0.0, 0.15, 4.6],           # the town hall from the square
		[-8.5, -30.0, PI * 0.5, 0.1, 4.6],       # Storgata 31
		[-8.5, -30.0, -PI * 0.5, 0.1, 4.6],      # Storgata 33
		[47.0, -8.0, 0.0, 0.2, 4.6],             # Aandahls from Storgata
		[-8.5, -20.0, 0.0, -0.75, 75.0],         # from above
		[20.0, -12.0, 0.6, 0.0, 2.0],            # close-up of a facade
		[-600.0, -420.0, 0.3, -0.5, 110.0],      # a residential hillside from above
		[-600.0, -420.0, 0.3, 0.05, 6.0],        # and from the street
		[55.0, -75.0, 0.0, -0.3, 65.0],          # the cathedral and bell tower from the square side
		[60.0, -90.0, 0.5, -0.6, 90.0],          # the cathedral from above
		[-700.0, 495.0, 1.57, -0.3, 110.0],       # Scandic Seilet from the stadium side
		[-562.0, 455.0, 0.2, -0.45, 150.0],      # Aker Stadion from above
		[-562.0, 455.0, 1.2, 0.05, 5.0],         # on the pitch
		[30.0, 95.0, 2.6, -0.3, 60.0],           # the piers below the square
		[-5860.0, 470.0, 1.75, 0.05, 9.0],       # the rubble in Haukabøtunnelen, the western edge
		[-5800.0, 480.0, 1.6, -0.5, 120.0],      # the western edge from above
		[5760.0, -3410.0, -0.75, 0.0, 12.0],     # Tussentunnelen's south mouth
		[5600.0, -700.0, -1.57, -0.4, 300.0],    # Årø airport toward the eastern edge
		[-426.0, -3848.0, PI, -0.25, 40.0],      # Frænavarden, looking south over the town
		[-300.0, -330.0, 0.4, -0.05, 5.0],       # a residential street close up
		[-300.0, -330.0, 0.4, -0.6, 60.0],       # and from above
		[120.0, 20.0, -1.4, -0.1, 6.0],          # Storgata, shops and sidewalks
		[120.0, 20.0, -1.4, -0.7, 70.0],         # and from above
		[1200.0, -60.0, 1.5, -0.12, 6.0],        # the main road east of the centre
	]
	if "--only" in OS.get_cmdline_user_args():       # quick look: just the last few views
		views = [
			[-300.0, -352.0, 1.57, -0.3, 22.0],
			[-300.0, -352.0, 1.57, -0.05, 3.0],
			[60.0, 14.0, -1.57, -0.25, 16.0],
			[-150.0, -200.0, 0.0, -0.45, 45.0],
		]
	if "--atv" in OS.get_cmdline_user_args():
		views = []
	var custom := []                                 # --view=x,z,yaw,pitch,distance (any number of them)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			var f := arg.substr(7).split_floats(",")
			custom.append([f[0], f[1], f[2], f[3], f[4]])
	if not custom.is_empty():
		views = custom
	for k in views.size():
		var v: Array = views[k]
		player.global_position = Vector3(v[0], world.height_at(v[0], v[1]) + 0.3, v[1])
		player.reset_physics_interpolation()
		player.yaw = v[2]
		player.pitch = v[3]
		player._arm.spring_length = v[4]
		world.flush(player.global_position)
		for i in (90 if k == 0 else 30):
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/shot%d.png" % k)
	if "--only" in OS.get_cmdline_user_args() or not custom.is_empty():
		get_tree().quit()
		return
	if "--atv" in OS.get_cmdline_user_args():
		pass
	# ATV check: walk up, get on, drive off across the square, get off again.
	var a: Node3D = player.atv
	player.global_position = a.global_position + Vector3(-1.5, 0.3, 0.0)
	player.reset_physics_interpolation()
	player.yaw = 0.6
	player.pitch = -0.2
	player._arm.spring_length = 5.0
	for i in 20:
		await get_tree().process_frame
	print("ATV near: ", player.near_atv())
	player._toggle_atv()
	var from: Vector3 = player.global_position
	Input.action_press("move_forward")
	for i in 90:
		await get_tree().process_frame
	Input.action_press("move_left")
	for i in 40:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_atv.png")
	# side and front views while turning, to see the arms on the bars and the body leaning
	player.yaw = player._heading - PI * 0.5
	player.pitch = -0.1
	player._arm.spring_length = 3.2
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_atv_side.png")
	player.yaw = player._heading + PI
	player.pitch = -0.25
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_atv_front.png")
	print("ATV body: roll ", snappedf(player.atv._roll, 0.001), " pitch ", snappedf(player.atv._pitch, 0.001), " heave ", snappedf(player.atv._heave, 0.001), " wheels ", player.atv._offsets)
	print("ATV driving: ", player.driving, "  moved ", snappedf(from.distance_to(player.global_position), 0.1), " m  speed ", snappedf(player._drive_speed, 0.1))
	Input.action_release("move_forward")
	Input.action_release("move_left")
	player._toggle_atv()
	for i in 20:
		await get_tree().process_frame
	print("ATV parked again: ", not player.driving, "  player to ATV ", snappedf(player.global_position.distance_to(a.global_position), 0.1), " m")
	get_viewport().get_texture().get_image().save_png("res://data/shot_atv_off.png")
	Input.action_press("move_forward")
	Input.action_press("sprint")
	player.yaw = 2.2
	player.pitch = -0.1
	player._arm.spring_length = 3.0
	for i in 47:
		await get_tree().process_frame
	player.yaw = 2.2 - PI * 0.5
	for i in 3:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_walk.png")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	get_tree().quit()


func _count_triangles(node: Node) -> int:
	var total := 0
	if node is MeshInstance3D and node.mesh != null:
		for k in node.mesh.get_surface_count():
			var arrays: Array = node.mesh.surface_get_arrays(k)
			var idx = arrays[Mesh.ARRAY_INDEX]
			total += (idx.size() if idx != null and idx.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3
	for c in node.get_children():
		total += _count_triangles(c)
	return total
## `./run.sh -- --heli`: get into the helicopter, wait for the rotor, climb, fly off, come down, land.
func _heli_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	var heli: Node3D = player.vehicles[3]
	player.global_position = heli.global_position + Vector3(-2.6, 0.3, 0.5)
	player.reset_physics_interpolation()
	player.yaw = -1.2
	player.pitch = -0.2
	player._arm.spring_length = 9.0
	world.flush(player.global_position)
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_heli0.png")
	print("HELI near: ", player.near_atv(), " — ", player.vehicle_label(), ", triangles ", _count_triangles(heli))
	player._toggle_atv()
	# the pilot in the seat, seen through the glass from in front and to the right
	player.yaw = heli.global_rotation.y + PI - 0.7
	player.pitch = -0.12
	player._arm.spring_length = 6.5
	for i in 12:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_heli_in.png")
	player._arm.spring_length = 12.0
	player.yaw = 0.0
	Input.action_press("jump")
	for i in 120:
		await get_tree().physics_frame
	print("HELI after 2 s of Space: rotor ", snappedf(heli.rotor, 0.01), ", height above start ", snappedf(player.global_position.y - world.height_at(player.global_position.x, player.global_position.z), 0.1), " m")
	for i in 420:
		await get_tree().physics_frame
	print("HELI after 9 s: rotor ", snappedf(heli.rotor, 0.01), ", height ", snappedf(player.global_position.y, 0.1), " m, climbing ", snappedf(player.velocity.y, 0.1), " m/s")
	Input.action_release("jump")
	Input.action_press("move_forward")
	player.yaw = 0.9
	for i in 300:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_heli1.png")
	print("HELI after 5 s forward: speed ", snappedf(Vector3(player.velocity.x, 0, player.velocity.z).length() * 3.6, 1.0), " km/h, height ", snappedf(player.global_position.y, 0.1),
		" m, heading ", snappedf(player._heading, 0.01), " (mouse ", snappedf(player.yaw, 0.01), "), lean ", player._lean)
	Input.action_release("move_forward")
	for i in 240:
		await get_tree().physics_frame
	print("HELI hands off 4 s: speed ", snappedf(Vector3(player.velocity.x, 0, player.velocity.z).length() * 3.6, 1.0), " km/h, sinking ", snappedf(player.velocity.y, 0.1), " m/s")
	Input.action_press("descend")
	var t := 0
	while not player.is_on_floor() and t < 2400:
		await get_tree().physics_frame
		t += 1
	Input.action_release("descend")
	for i in 60:
		await get_tree().physics_frame
	print("HELI landed: ", player.is_on_floor(), " after ", snappedf(t / 60.0, 0.1), " s, at ", snappedf(player.global_position.y - world.height_at(player.global_position.x, player.global_position.z), 0.1), " m over the ground, speed ", snappedf(player.velocity.length(), 0.1))
	player._toggle_atv()
	for i in 20:
		await get_tree().process_frame
	print("HELI out: ", not player.driving)
	get_viewport().get_texture().get_image().save_png("res://data/shot_heli2.png")
	get_tree().quit()
## `./run.sh -- --bike`: get on the bicycle, ride off, wind up a jump and let it go, get off.
func _bike_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	var bike: Node3D = player.vehicles[5]
	bike.global_position = Vector3(5000.0, world.height_at(5000.0, -718.3) + 0.05, -718.3)
	bike.global_rotation = Vector3(0, -1.238, 0)
	player.global_position = bike.global_position + Vector3(-0.9, 0.3, -0.6)
	player.reset_physics_interpolation()
	player.yaw = 2.2
	player.pitch = -0.2
	player._arm.spring_length = 3.2
	world.flush(player.global_position)
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_bike0.png")
	print("BIKE near: ", player.near_atv(), " — ", player.vehicle_label(), ", triangles ", _count_triangles(bike))
	player._toggle_atv()
	Input.action_press("move_forward")
	var a0: float = bike._crank_a
	for i in 150:
		await get_tree().physics_frame
	print("BIKE after 2.5 s: ", snappedf(player._drive_speed * 3.6, 0.1), " km/h, cranks turned ", snappedf(absf(bike._crank_a - a0) / TAU, 0.1), " times")
	player.yaw = player._heading - 1.2
	player.pitch = -0.1
	for i in 6:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_bike1.png")
	Input.action_press("jump")
	for i in 45:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_bike2.png")
	print("BIKE wound up: ", snappedf(player._hop, 0.01))
	Input.action_release("jump")
	var top := 0.0
	var y0: float = player.global_position.y
	for i in 90:
		await get_tree().physics_frame
		top = maxf(top, player.global_position.y - y0)
		if i == 14:
			await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://data/shot_bike3.png")
	print("BIKE jumped ", snappedf(top, 0.01), " m, back on the ground: ", player.is_on_floor(), ", still going ", snappedf(player._drive_speed * 3.6, 0.1), " km/h")
	Input.action_release("move_forward")
	Input.action_press("move_back")
	for i in 120:
		await get_tree().physics_frame
	Input.action_release("move_back")
	player._toggle_atv()
	for i in 20:
		await get_tree().process_frame
	print("BIKE off: ", not player.driving)
	get_tree().quit()


## `./run.sh -- --car`: get into the Volvo, drive off, drift, get out; pictures to data/shot_car*.png.
func _car_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	var car: Node3D = player.vehicles[4 if "--mercedes" in OS.get_cmdline_user_args() else (2 if "--integra" in OS.get_cmdline_user_args() else 1)]
	# out on the runway, where there is room
	car.global_position = Vector3(5000.0, world.height_at(5000.0, -718.3) + 0.05, -718.3)
	car.global_rotation = Vector3(0, -1.238, 0)
	player.global_position = car.global_position + Vector3(-1.2, 0.3, -2.4)
	player.reset_physics_interpolation()
	player.yaw = 2.3
	player.pitch = -0.25
	player._arm.spring_length = 6.0
	world.flush(player.global_position)
	for i in 60:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_car0.png")
	player.yaw = -0.9
	for i in 10:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_car1.png")
	print("CAR triangles: ", _count_triangles(car))
	print("CAR near: ", player.near_atv(), " — ", player.vehicle_label())
	player._toggle_atv()
	Input.action_press("move_forward")
	Input.action_press("sprint")
	for i in 150:
		await get_tree().physics_frame
	# a close look at the rear wheels while driving straight (the driver is not drawn, so nothing is in the way)
	player.yaw = player._heading + 0.5
	player.pitch = -0.08
	player._arm.spring_length = 3.4
	for i in 4:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_car_rear.png")
	player._arm.spring_length = 6.6
	print("CAR speed after 2.5 s: ", snappedf(player._drive_speed * 3.6, 1.0), " km/h")
	player.yaw = player._heading - 0.9
	player.pitch = -0.3
	Input.action_press("jump")
	Input.action_press("move_left")
	for i in 55:
		await get_tree().physics_frame
	var slip: float = angle_difference(player._course, player._heading)
	print("CAR drifting: slip ", snappedf(slip, 0.01), " rad, speed ", snappedf(player._drive_speed * 3.6, 1.0), " km/h, smoke ", car._smoking)
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_car2.png")
	for i in 50:
		await get_tree().physics_frame
	await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/shot_car3.png")
	Input.action_release("jump")
	Input.action_release("move_left")
	Input.action_release("move_forward")
	Input.action_release("sprint")
	Input.action_press("move_back")
	for i in 120:
		await get_tree().physics_frame
	Input.action_release("move_back")
	for i in 30:
		await get_tree().physics_frame
	print("CAR stopped: ", snappedf(player._drive_speed, 0.1), " m/s, smoke ", car._smoking, ", tail length ", snappedf(car._tail[0].distance_to(car._tail[-1]), 0.01))
	player._toggle_atv()
	for i in 20:
		await get_tree().process_frame
	print("CAR parked: ", not player.driving, ", rider shown: ", player._torso.visible)
	get_viewport().get_texture().get_image().save_png("res://data/shot_car4.png")
	get_tree().quit()
## `./run.sh -- --notetest`: point at a few things, leave a note on each, print what was recognised.
func _notetest_and_quit() -> void:
	player.set_process_unhandled_input(false)
	var views := []
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--view="):
			views.append(arg.substr(7).split_floats(","))
	for v in views:
		player.global_position = Vector3(v[0], world.height_at(v[0], v[1]) + 0.3, v[1])
		player.reset_physics_interpolation()
		player.yaw = v[2]
		player.pitch = v[3]
		player._arm.spring_length = v[4]
		world.flush(player.global_position)
		for i in 40:
			await get_tree().process_frame
		await devtool._pick()
		print("NOTE ", devtool._title.text)
		devtool._edit.text = "test note"
		for i in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/shot_note%d.png" % views.find(v))
		devtool._close(true)
	get_tree().quit()


## `./run.sh -- --perf`: ride through the centre at ATV top speed and report frame times.
func _perf_and_quit() -> void:
	hud.start(world, player)
	player.set_process_unhandled_input(false)
	player.set_physics_process(false)
	for i in 60:
		await get_tree().process_frame
	var times: Array = []
	var x := -900.0
	var last := Time.get_ticks_usec()
	while x < 900.0:
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		var dt := float(now - last) / 1000.0
		last = now
		times.append(dt)
		x += 38.0 * dt / 1000.0
		var z := -60.0 + 60.0 * sin(x / 150.0)
		player.global_position = Vector3(x, world.height_at(x, z) + 0.5, z)
		player.yaw = -PI * 0.5
		world.update_streaming(player.global_position)
	times.sort()
	var total := 0.0
	for t in times:
		total += t
	print("PERF frames ", times.size(), "  avg ms ", snappedf(total / times.size(), 0.01), "  median ", snappedf(times[times.size() / 2], 0.01),
		"  p99 ", snappedf(times[int(times.size() * 0.99)], 0.01), "  max ", snappedf(times[-1], 0.01), "  cells ", world.detail._cells.size())
	get_tree().quit()


## `./run.sh -- --drive`: ride the ATV along real roads at full throttle under the game's own physics,
## steering along each road, and report how often something stopped it and how high it left the ground.
func _drive_and_quit() -> void:
	hud.start(world, player)
	player.set_process_unhandled_input(false)
	# the longest roads within 2.5 km of the centre, a mix of main roads and residential streets
	var picks := []
	for w in world.detail.ways:
		if w[1] != 0:
			continue
		var pts: PackedVector2Array = w[3]
		if pts[0].length() > 2500.0 or pts.size() < 60:
			continue
		picks.append([pts.size(), w])
	picks.sort_custom(func(a, b): return a[0] > b[0])
	var chosen := []
	for i in picks.size():
		if i % maxi(1, picks.size() / 10) == 0 and chosen.size() < 10:
			chosen.append(picks[i][1])
	var total_stalls := 0
	for w in chosen:
		var pts: PackedVector2Array = w[3]
		var a: Node3D = player.atv
		if player.driving:
			player._toggle_atv()
		var start := pts[1]
		var dir := (pts[3] - pts[1]).normalized()
		a.global_position = Vector3(start.x, world.height_at(start.x, start.y) + 0.3, start.y)
		a.global_rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
		player.global_position = a.global_position + Vector3(0.3, 0.3, 0)
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		for i in 5:
			await get_tree().physics_frame
		player._toggle_atv()
		Input.action_press("move_forward")
		var k := 2
		var t := 0.0
		var stalls := 0
		var max_air := 0.0
		var top := 0.0
		var was_fast := false
		while k < pts.size() - 2 and t < 60.0:
			await get_tree().physics_frame
			t += 1.0 / 60.0
			var p: Vector3 = player.global_position
			var here := Vector2(p.x, p.z)
			while k < pts.size() - 2 and here.distance_to(pts[k]) < 9.0:
				k += 1
			var want := pts[k] - here
			var diff := angle_difference(player._heading, atan2(-want.x, -want.y))
			Input.action_release("move_left")
			Input.action_release("move_right")
			if diff > 0.04:
				Input.action_press("move_left", clampf(diff * 3.0, 0.0, 1.0))
			elif diff < -0.04:
				Input.action_press("move_right", clampf(-diff * 3.0, 0.0, 1.0))
			# ease off for bends, as a rider would
			if absf(diff) > 0.35 and player._drive_speed > 9.0:
				Input.action_release("move_forward")
			else:
				Input.action_press("move_forward")
			top = maxf(top, player._drive_speed)
			if player._drive_speed > 12.0:
				was_fast = true
			elif was_fast and player._drive_speed < 4.0:
				stalls += 1
				was_fast = false
				var what := "nothing"
				for ci in player.get_slide_collision_count():
					var col: KinematicCollision3D = player.get_slide_collision(ci)
					if absf(col.get_normal().y) < 0.6:
						what = "%s (%s), wall normal y %.2f" % [col.get_collider().get_parent().name, col.get_collider().get_parent().get_parent().name, col.get_normal().y]
				print("DRIVE   stopped at (%d, %d) road point %d of %d, against: %s" % [p.x, p.z, k, pts.size(), what])
			max_air = maxf(max_air, p.y - world.height_at(p.x, p.z))
		Input.action_release("move_forward")
		Input.action_release("move_left")
		Input.action_release("move_right")
		total_stalls += stalls
		print("DRIVE %d m of road (width %.1f) in %.0f s: reached the end %s, top %d km/h, stopped %d times, highest off the ground %.1f m" % [
			pts.size() * 3, w[0] * 2.0, t, "yes" if k >= pts.size() - 2 else "NO", int(top * 3.6), stalls, max_air])
	print("DRIVE total stops: ", total_stalls)
	get_tree().quit()
