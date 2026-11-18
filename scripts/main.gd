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
const Paths := preload("res://scripts/paths.gd")

var world
var player
var daytime                         # scripts/daytime.gd: the clock, the sun, the town at night
var _env: Environment
var _sun: DirectionalLight3D
var weather                         # scripts/weather.gd
var menu                            # scripts/menu.gd
var grass                           # scripts/grass.gd
var traffic                         # scripts/traffic.gd
var people                          # scripts/people.gd
var molde                           # scripts/molde.gd
var sound                           # scripts/sound.gd
var hud
var devtool

const HELI_AT := Vector2(14.0, 50.0)


func _ready() -> void:
	if not OS.get_cmdline_user_args().is_empty():      # a check, not a game: do not wait for the screen
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_physics_steps_per_frame = 24
	else:
		# A steady 120 pictures a second. With variable refresh on an OLED screen the brightness follows the
		# frame rate, so a rate that swings (60 one moment, 200 the next) shows as flicker; a rate the
		# machine can always hold does not.
		Engine.max_fps = 120
	_setup_input()
	hud = HudScript.new()
	add_child(hud)
	hud.set_loading("")
	_setup_environment()

	if OS.has_feature("web"):          # the page has put the map in /world/ before starting (web/shell.html)
		if not FileAccess.file_exists("/world/meta.json"):
			hud.set_loading("The map is missing.\nReload the page to try again.")
			return
		Paths.world = "/world/"

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

	# What can be driven: an ATV, a white Volvo 740, a Honda Integra, a helicopter, a Mercedes estate and a
	# bicycle. Where each stands is in place_vehicles(), which the reset uses too.
	var made := []
	for pair in [["ATV", AtvScript], ["Volvo", CarScript], ["Integra", IntegraScript], ["Helicopter", HeliScript], ["Mercedes", MercedesScript], ["Bicycle", BikeScript]]:
		var v := Node3D.new()
		v.name = pair[0]
		v.set_script(pair[1])
		add_child(v)
		made.append(v)
	var atv: Node3D = made[0]
	var car: Node3D = made[1]
	var integra: Node3D = made[2]
	var heli: Node3D = made[3]
	var merc: Node3D = made[4]
	var bike: Node3D = made[5]
	player.atv = atv
	player.vehicles = [atv, car, integra, heli, merc, bike]
	place_vehicles()
	sound = Node.new()
	sound.name = "Sound"
	sound.set_script(load("res://scripts/sound.gd"))
	add_child(sound)
	sound.setup(world, player)
	player.sound = sound
	daytime = Node.new()
	daytime.name = "Daytime"
	daytime.set_script(load("res://scripts/daytime.gd"))
	add_child(daytime)
	daytime.setup(world, player, _env, _sun)
	weather = Node.new()
	weather.name = "Weather"
	weather.set_script(load("res://scripts/weather.gd"))
	add_child(weather)
	weather.setup(world, player, daytime)
	traffic = Node3D.new()
	traffic.name = "Traffic"
	traffic.set_script(load("res://scripts/traffic.gd"))
	add_child(traffic)
	traffic.setup(world, player, daytime)
	people = Node3D.new()
	people.name = "People"
	people.set_script(load("res://scripts/people.gd"))
	add_child(people)
	people.setup(world, player, daytime, weather)
	molde = Node3D.new()
	molde.name = "Molde"
	molde.set_script(load("res://scripts/molde.gd"))
	add_child(molde)
	var berth = null
	for b in traffic._boats:
		if b["kind"] == "steamer":
			berth = b["berth"]
	molde.setup(world, player, daytime, people, traffic._meshes, berth)
	grass = Node3D.new()
	grass.name = "Grass"
	grass.set_script(load("res://scripts/grass.gd"))
	add_child(grass)
	grass.setup(world, player)
	menu = CanvasLayer.new()
	menu.name = "Menu"
	menu.set_script(load("res://scripts/menu.gd"))
	add_child(menu)
	menu.setup(self, world, player, daytime, weather, sound)
	if "--perf" in OS.get_cmdline_user_args():
		_perf_and_quit()
		return
	if "--jumps" in OS.get_cmdline_user_args():
		_jumps_and_quit()
		return
	if "--drive" in OS.get_cmdline_user_args():
		_drive_and_quit()
		return
	if "--sweep-street" in OS.get_cmdline_user_args():
		_sweep_street_and_quit()
		return
	if "--sweep" in OS.get_cmdline_user_args():
		_sweep_and_quit()
		return
	if "--look" in OS.get_cmdline_user_args():
		hud.start(world, player)
		hud.visible = false
		_look_and_quit()
		return
	if "--wheels" in OS.get_cmdline_user_args():
		hud.start(world, player)
		hud.visible = false
		_wheel_shots_and_quit()
		return
	if "--shot" in OS.get_cmdline_user_args():
		_screenshot_and_quit()
	elif not OS.has_feature("web"):                   # notes are written into the project folder, which a browser does not have
		devtool = DevtoolScript.new()                 # crosshair and notes (right mouse button)
		add_child(devtool)
		devtool.start(world, player)
		if "--patchtest" in OS.get_cmdline_user_args():
			_patchtest_and_quit()
		if "--notetest" in OS.get_cmdline_user_args():
			_notetest_and_quit()
		if "--car" in OS.get_cmdline_user_args():
			_car_test_and_quit()
		if "--count" in OS.get_cmdline_user_args():
			print("COUNT character ", _count_triangles(player._body), "  ATV ", _count_triangles(player.vehicles[0]))
			get_tree().quit()
		if "--molde" in OS.get_cmdline_user_args():
			_molde_test_and_quit()
		if "--people" in OS.get_cmdline_user_args():
			_people_test_and_quit()
		if "--traffic" in OS.get_cmdline_user_args():
			_traffic_test_and_quit()
		if "--models" in OS.get_cmdline_user_args():
			_models_shot_and_quit()
		if "--garage" in OS.get_cmdline_user_args():
			_garage_shot_and_quit()
		if "--cast" in OS.get_cmdline_user_args():
			_cast_shot_and_quit()
		if "--body" in OS.get_cmdline_user_args():
			_body_shot_and_quit()
		if "--menu" in OS.get_cmdline_user_args():
			_menu_test_and_quit()
		if "--sound" in OS.get_cmdline_user_args():
			_sound_test_and_quit()
		if "--swim" in OS.get_cmdline_user_args():
			_swim_test_and_quit()
		if "--bike" in OS.get_cmdline_user_args():
			_bike_test_and_quit()
		if "--heli" in OS.get_cmdline_user_args():
			_heli_test_and_quit()
	hud.start(world, player)


## Every vehicle where it starts and as it starts, parked and still: the ATV beside the spawn point, the Volvo
## on the other side and the Integra behind it (clear of the fence), the helicopter on the lower part of
## Torget across Storgata, the Mercedes in its drive on Langmyrvegen, the bicycle on the square.
func place_vehicles() -> void:
	var s: Vector2 = world.spawn
	var v: Array = player.vehicles
	_stand(v[0], s.x + 2.4, s.y - 0.5, 0.0)
	_stand(v[1], s.x - 4.5, s.y + 1.0, 0.0)
	_stand(v[2], s.x - 4.5, s.y + 8.0, 0.0)
	_stand(v[3], HELI_AT.x, HELI_AT.y, PI)
	var mm: Array = world.meta.get("mercedes", [])
	if mm.size() == 3:
		_stand(v[4], mm[0], mm[1], mm[2])
	var bb: Array = world.meta.get("bicycle", [])
	if bb.size() == 2:
		_stand(v[5], bb[0], bb[1], 0.0, 0.07)


func _stand(v: Node3D, x: float, z: float, turn: float, lift := 0.0) -> void:
	v.global_transform = Transform3D(Basis(Vector3.UP, turn), Vector3(x, world.height_at(x, z) + lift, z))
	v.reset_physics_interpolation()
	if v.get("rotor") != null:
		v.set("rotor", 0.0)
	if v.has_method("park"):
		v.park()
	if v.has_method("set_parked"):
		v.set_parked(true)


## Start again at Rådhusplassen: the player out of any vehicle and back at the spawn point, facing north toward
## the town hall, standing still with full breath; every vehicle back where it starts. The time of day, the
## weather and the settings stay as they are.
func reset_game() -> void:
	if player.driving:
		player._toggle_atv(true)
	var s: Vector2 = world.spawn
	player.global_position = Vector3(s.x, world.height_at(s.x, s.y) + 0.5, s.y)
	player.velocity = Vector3.ZERO
	player.yaw = 0.0
	player.pitch = -0.22
	player.stamina = 1.0
	player.swimming = false
	player._climb = 0.0
	player._body.rotation = Vector3.ZERO
	player.reset_physics_interpolation()
	place_vehicles()
	# the ground and the paving there before anyone can move, so nobody falls through
	world.update_streaming(player.global_position)
	world.flush(player.global_position)


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
	_key("mute", [KEY_M])
	_key("weather", [KEY_V])
	_key("reset", [KEY_F5])
	_key("time_back", [KEY_BRACKETLEFT])
	_key("time_on", [KEY_BRACKETRIGHT])
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
	_env = env

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-22.0, -50.0, 0.0)      # low in the south-west
	sun.light_color = Color(1.0, 0.84, 0.68)
	sun.light_energy = 1.25
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 380.0
	add_child(sun)
	_sun = sun


## `./run.sh -- --molde`: the things the town is known by. Reports the rose beds, the signs and whether the
## festival is on, and saves a picture of each sign and of the square (data/molde_*.png). With --date=198 the
## square is dressed for Moldejazz.
func _molde_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	player.visible = false
	await get_tree().create_timer(3.0).timeout
	print("MOLDE rose beds set out: ", molde.roses, "; festival on: ", molde.festival, " (day ", daytime.day, ")")
	var cam := Camera3D.new()
	cam.fov = 60.0
	cam.far = 70000.0
	add_child(cam)
	cam.make_current()
	var n := 0
	for child in molde.get_children():
		if child is Node3D and child.get_child_count() >= 3 and child.get_child(1) is Label3D:
			var at: Vector3 = child.global_position
			player.global_position = at + Vector3(0, 0.5, 0)
			world.flush(player.global_position)
			cam.global_position = at + child.global_transform.basis * Vector3(0, 2.0, -6.5)
			cam.look_at(at + Vector3(0, 1.8, 0))
			for i in 40:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://data/molde_sign%d.png" % n)
			print("MOLDE sign '", (child.get_child(1) as Label3D).text, "' at ", at.snappedf(1.0))
			n += 1
	var s: Vector2 = world.spawn
	player.global_position = Vector3(s.x, world.height_at(s.x, s.y) + 0.5, s.y + 12.0)
	world.flush(player.global_position)
	Engine.time_scale = 4.0
	await get_tree().create_timer(40.0).timeout
	Engine.time_scale = 1.0
	cam.global_position = Vector3(s.x + 3.0, world.height_at(s.x, s.y) + 7.0, s.y + 26.0)
	cam.look_at(Vector3(s.x + 2.0, world.height_at(s.x, s.y) + 2.0, s.y - 9.0))
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/molde_square.png")
	print("MOLDE people on the square: ", people.people.size(), " ", people.stats)
	get_tree().quit()


## `./run.sh -- --people`: stand on Rådhusplassen, on Storgata and in the forest for half a minute each and report
## who is about: how many, doing what, whether any walker is in the carriageway or inside a building. Saves
## data/people.png.
func _people_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	await get_tree().create_timer(1.0).timeout
	for spot in [["Rådhusplassen", world.spawn], ["Storgata", Vector2(104.0, -8.0)], ["the forest", Vector2(-600.0, -2200.0)]]:
		var p: Vector2 = spot[1]
		player.global_position = Vector3(p.x, world.height_at(p.x, p.y) + 0.5, p.y)
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		Engine.time_scale = 4.0
		await get_tree().create_timer(30.0).timeout
		Engine.time_scale = 1.0
		var kinds := {}
		var on_road := 0
		var indoors := 0
		var space := get_world_3d().direct_space_state
		for f in people.people:
			kinds[f["kind"]] = int(kinds.get(f["kind"], 0)) + 1
			var at: Vector3 = (f["node"] as Node3D).global_position
			if f["kind"] == "walker" and not is_nan(world.detail.surface_at(at.x, at.z)) and at.y - world.height_at(at.x, at.z) < 0.18:
				on_road += 1
			var q := PhysicsRayQueryParameters3D.create(at + Vector3(0, 1.0, 0), at + Vector3(0, 30.0, 0))
			if not space.intersect_ray(q).is_empty():
				indoors += 1
		print("PEOPLE at %s: %d about %s; walkers on the carriageway %d; under a roof %d" % [spot[0], people.people.size(), kinds, on_road, indoors])
		if spot[0] != "the forest":                         # a picture toward the nearest few
			var near: Node3D = null
			for f in people.people:
				var n: Node3D = f["node"]
				if near == null or n.global_position.distance_to(player.global_position) < near.global_position.distance_to(player.global_position):
					near = n
			if near != null:
				var to: Vector3 = near.global_position - player.global_position
				player.yaw = atan2(-to.x, -to.z)
				player.pitch = -0.08
				player._arm.spring_length = 2.0
				for i in 20:
					await get_tree().process_frame
				get_viewport().get_texture().get_image().save_png("res://data/people_%s.png" % ("square" if spot[0] != "Storgata" else "street"))
	print("PEOPLE in all: ", people.stats)
	get_tree().quit()


## `./run.sh -- --traffic`: stand by Storgata for three minutes of traffic (run fast) and report: how many cars
## there are, whether they are on asphalt, how fast they go, what they did at junctions, whether they stop for
## `./run.sh -- --body`: photograph the player's figure from the front, the side, behind, and the face close up,
## to data/body_<view>.png, and say how tall it stands and how many triangles it is drawn with.
func _body_shot_and_quit() -> void:
	player.set_process_unhandled_input(false)
	hud.visible = false
	traffic.amount = 0
	var at := Vector3(-4.0, world.detail.surface_at(-4.0, 30.0), 30.0)
	if is_nan(at.y):
		at.y = world.height_at(-4.0, 30.0)
	player.global_position = at + Vector3(0, 0.02, 0)
	player.reset_physics_interpolation()
	world.flush(player.global_position)
	for i in 90:                                               # let him land and stand still
		await get_tree().physics_frame
	at = player.global_position
	var facing: Basis = player._body.global_transform.basis.orthonormalized()
	var cam := Camera3D.new()
	cam.near = 0.02
	add_child(cam)
	cam.make_current()
	var views := {"front": [Vector3(0.5, 1.15, -3.3), Vector3(0, 0.95, 0), 36.0], "side": [Vector3(3.3, 1.15, -0.3), Vector3(0, 0.95, 0), 36.0],
		"back": [Vector3(-0.6, 1.2, 3.3), Vector3(0, 0.95, 0), 36.0], "face": [Vector3(0.16, 1.74, -0.62), Vector3(0, 1.70, 0), 30.0],
		"boots": [Vector3(0.7, 0.35, -1.0), Vector3(0, 0.12, 0), 30.0]}
	for name in views:
		cam.fov = views[name][2]
		cam.global_position = at + facing * (views[name][0] as Vector3)
		cam.look_at(at + facing * (views[name][1] as Vector3))
		for i in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/body_%s.png" % name)
	var top := -1e9
	var low := 1e9
	for mi in player._body.find_children("*", "MeshInstance3D", true, false):
		var box: AABB = (mi as MeshInstance3D).global_transform * (mi as MeshInstance3D).get_aabb()
		top = maxf(top, box.end.y)
		low = minf(low, box.position.y)
	print("BODY stands ", snappedf(top - low, 0.01), " m tall, drawn with ", player.body_triangles, " triangles")
	# the stride and the jump, held still at a few moments each and seen from the side
	player.set_physics_process(false)
	cam.fov = 40.0
	for pose in [["walk_a", 4.6, true, 0.0, 0.05], ["walk_b", 4.6, true, 0.0, 0.30], ["sprint_a", 7.8, true, 0.0, 0.05], ["sprint_b", 7.8, true, 0.0, 0.62],
			["jump_up", 4.6, false, 4.0, 0.0], ["jump_top", 4.6, false, 0.0, 0.0], ["jump_down", 4.6, false, -5.0, 0.0], ["landing", 0.0, true, 0.0, 0.0]]:
		player.velocity = Vector3(0, pose[3], 0)
		if pose[0] == "landing":
			player._air = 1.0
		for i in 40:
			player._gait = pose[4]
			player._animate(1.0 / 60.0, 0.0001 if pose[0] == "landing" else pose[1], pose[2])
			if pose[0] == "landing" and i == 6:
				break
		player._gait = pose[4]
		cam.global_position = at + facing * Vector3(3.6, 1.0, -0.2)
		cam.look_at(at + facing * Vector3(0, 0.95, 0))
		for i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/body_%s.png" % pose[0])
	# swimming, held at moments of each stroke (on land, to see the whole body: in the water half of it is under)
	player.velocity = Vector3.ZERO
	player.swimming = true
	for pose in [["crawl_a", true, 0.6], ["crawl_b", true, 3.6], ["breast_pull", false, 0.9], ["breast_draw", false, 2.4], ["breast_glide", false, 5.3], ["tread", false, -1.0]]:
		player.crawling = pose[1]
		for i in 60:
			if float(pose[2]) >= 0.0:
				player._stroke = float(pose[2])
			player._animate(1.0 / 60.0, 0.0 if float(pose[2]) < 0.0 else 2.0, false)
		cam.global_position = at + facing * Vector3(3.9, 1.3, -0.2)
		cam.look_at(at + facing * Vector3(0, 1.15, 0))
		for i in 3:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/body_%s.png" % pose[0])
	get_tree().quit()


## `./run.sh -- --models`: stand the traffic's twenty car models in two rows on Torget and photograph them from
## the front and from behind, five at a time, to data/models_<n>.png (to check each against the real car).
func _models_shot_and_quit() -> void:
	traffic.amount = 0
	player.set_process_unhandled_input(false)
	player.visible = false
	player.global_position = Vector3(20, 6, 70)
	player.reset_physics_interpolation()
	world.flush(player.global_position)
	var shown := []
	for i in traffic._models.size():
		var c := {"model": i, "col": (traffic._models[i]["paints"] as Array)[i % 5]}
		traffic._show(c)
		var at := Vector2(-7.0 + 5.7 * float(i % 5), 40.0 + 7.0 * float(i / 5))
		(c["node"] as Node3D).global_position = Vector3(at.x, traffic._height(at) - 0.08, at.y)
		(c["node"] as Node3D).rotation.y = PI * 0.5                 # nose to the west: seen side-on from the south
		for q in 2:
			(c["hubs"][q][0] as Node3D).rotation.y = 0.35
		shown.append(c)
	hud.visible = false
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	for row in 4:
		for view in 3:
			var mid := Vector3(4.4, 2.0, 40.0 + 7.0 * float(row))
			cam.fov = 30.0 if view == 0 else 42.0
			cam.global_position = mid + [Vector3(0, 0.6, 30.0), Vector3(-19.0, 3.0, 6.0), Vector3(21.0, 3.0, 6.0)][view]
			cam.look_at(mid + Vector3(0, -1.3, 0))
			for i in 30:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://data/models_%d%s.png" % [row, ["s", "f", "b"][view]])
	for i in traffic._models.size():
		var m: Dictionary = traffic._models[i]
		var tris := 0
		for q in (m["body"] as ArrayMesh).get_surface_count():
			tris += (m["body"] as ArrayMesh).surface_get_arrays(q)[Mesh.ARRAY_VERTEX].size() / 3
		var wt := 0
		for q in (m["wheel"] as ArrayMesh).get_surface_count():
			wt += (m["wheel"] as ArrayMesh).surface_get_arrays(q)[Mesh.ARRAY_VERTEX].size() / 3
		print("MODEL ", m["name"], ": body ", tris, " triangles, each wheel ", wt)
	get_tree().quit()


## `--cast`: the thirty townspeople in two rows (men behind, women in front) with the three workers, one walking
## and one seated, in data/cast_<a|b|c|d>.png; prints how long their parts took to build and their triangles.
func _cast_shot_and_quit() -> void:
	traffic.amount = 0
	player.set_process_unhandled_input(false)
	player.visible = false
	hud.visible = false
	daytime.hours = 13.0
	var t0 := Time.get_ticks_msec()
	for who in people.characters + people._worker_kinds:
		people.Body.prepare(who["spec"])
	print("CAST parts built in ", Time.get_ticks_msec() - t0, " ms")
	people._ready_chars = people.characters.duplicate()
	people._unready.clear()
	people.set_physics_process(false)
	var base := Vector3(-4.0, world.height_at(-4.0, 30.0), 30.0)
	var y: float = world.detail.surface_at(base.x, base.z)
	if not is_nan(y):
		base.y = y
	var tris := 0
	var list: Array = people.characters + people._worker_kinds
	for i in list.size():
		var f: Dictionary = people._figure(list[i])
		var row := 0 if i < 15 else (1 if i < 30 else 2)
		var col := i % 15 if i < 30 else (i - 30) * 2 + 16
		(f["node"] as Node3D).position = base + Vector3(-7.0 + 1.0 * float(col), 0, -2.2 * float(row) if i < 30 else -1.1)
		tris += int(f["body"]["triangles"])
		if i == 3 or i == 20:
			people.Body.pose_walk(f["body"], 0.12, 1.0)
		if i == 7 or i == 24:
			people.Body.pose_sit(f["body"])
			(f["node"] as Node3D).position.y += 0.5 + 0.085 - 0.95 * float(list[i]["tall"])
	print("CAST ", list.size(), " figures, on average ", tris / list.size(), " triangles each close up")
	var cam := Camera3D.new()
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	var views := [[Vector3(-3.5, 1.5, -9.5), Vector3(-3.5, 0.9, -1.0), 34.0], [Vector3(3.5, 1.5, -9.5), Vector3(3.5, 0.9, -1.0), 34.0],
		[Vector3(-5.0, 1.55, -5.4), Vector3(-5.0, 1.45, -2.2), 30.0], [Vector3(12.0, 1.2, -7.0), Vector3(10.5, 0.9, -1.1), 34.0],
		[Vector3(0.0, 9.0, -60.0), Vector3(0.0, 0.9, -1.0), 12.0]]
	for k in views.size():
		cam.fov = views[k][2]
		cam.global_position = base + (views[k][0] as Vector3)
		cam.look_at(base + (views[k][1] as Vector3))
		for i in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/cast_%s.png" % ["a", "b", "c", "d", "far"][k])
	get_tree().quit()


## `--garage`: pictures of the player's own vehicles, each from the front quarter, the rear quarter low down
## and from underneath-ish, in data/garage_<n><a|b|c>.png.
func _garage_shot_and_quit() -> void:
	traffic.amount = 0
	player.set_process_unhandled_input(false)
	player.visible = false
	hud.visible = false
	daytime.hours = 13.0
	var cam := Camera3D.new()
	add_child(cam)
	cam.make_current()
	cam.fov = 35.0
	for n in player.vehicles.size():
		var v: Node3D = player.vehicles[n]
		var big := 9.0 if n == 3 else (3.2 if n == 0 or n == 5 else 6.5)
		var f := -v.global_transform.basis.z
		var r := v.global_transform.basis.x
		var mid := v.global_position + Vector3(0, 0.25 * big * 0.5, 0)
		var views := [f * big + r * big * 0.7 + Vector3(0, big * 0.35, 0), -f * big - r * big * 0.6 + Vector3(0, big * 0.10, 0), r * big * 1.1 + Vector3(0, -0.02 * big, 0)]
		for k in 3:
			cam.global_position = mid + views[k]
			cam.look_at(mid)
			for i in 20:
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://data/garage_%d%s.png" % [n, ["a", "b", "c"][k]])
	# and a bus, set down on Torget
	var bus: Dictionary = traffic.BusModel.make()
	var at := Vector3(10.0, 0.0, 62.0)
	at.y = traffic._height(Vector2(at.x, at.z))
	(bus["node"] as Node3D).position = at
	(bus["node"] as Node3D).rotation.y = 0.5
	add_child(bus["node"])
	for h in bus["steer"]:
		(h as Node3D).rotation.y = 0.3
	print("BUS drawn with ", traffic.BusModel.triangles, " triangles")
	var k2 := 0
	for v in [Vector3(9.0, 3.0, -12.0), Vector3(-10.0, 2.2, 11.0), Vector3(13.0, 1.6, 2.0), Vector3(-13.0, 1.6, -3.0)]:
		cam.fov = 40.0
		cam.global_position = at + Vector3(0, 1.2, 0) + v
		cam.look_at(at + Vector3(0, 1.4, 0))
		for i in 20:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/bus_%d.png" % k2)
		k2 += 1
	get_tree().quit()


## someone standing in the road, where the buses, the boats and the plane are. Saves data/traffic.png.
func _traffic_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	await get_tree().create_timer(1.0).timeout
	player.global_position = Vector3(104.0, world.height_at(104.0, -8.0) + 0.5, -8.0)      # on the sidewalk of Storgata
	player.reset_physics_interpolation()
	world.flush(player.global_position)
	Engine.time_scale = 6.0
	Engine.physics_ticks_per_second = 360
	Engine.max_physics_steps_per_frame = 60
	var on_road := 0
	var seen := 0
	var fastest := 0.0
	for round in 18:
		await get_tree().create_timer(10.0).timeout
		for c in traffic.cars:
			var pose: Array = traffic._pose(traffic._ways[c["w"]], c["s"], c["dir"], 1.7)
			if (pose[0] as Vector3).distance_to(player.global_position) < 230.0:
				seen += 1
				if not is_nan(world.detail.surface_at(pose[0].x, pose[0].z)):
					on_road += 1
			fastest = maxf(fastest, c["v"])
	var linked := 0
	for st in traffic._stations:
		linked += st.size() - 2
	print("TRAFFIC roads: ", traffic._ways.size(), ", joined at ", linked, " places along them and ", traffic._links.size(), " stations in all")
	print("TRAFFIC after 3 minutes: ", traffic.cars.size(), " cars; of ", seen, " looked at near by, ", on_road, " were on asphalt; fastest ", snappedf(fastest * 3.6, 1.0), " km/h; ", traffic.stats)
	for b in traffic.buses:
		print("TRAFFIC bus: route of ", (b["path"] as Array).size(), " roads, ", snappedf(b["total"], 1.0), " m, ", (b["stops"] as Array).size(), " stops; now on road ", b["leg"], ", going back ", b["back"], ", waiting ", snappedf(b["wait"], 0.1))
	for b in traffic._boats:
		print("TRAFFIC ", b["kind"], " at ", (b["node"] as Node3D).global_position.snappedf(1.0), " shown ", (b["node"] as Node3D).visible)
	Engine.time_scale = 1.0
	Engine.physics_ticks_per_second = 60
	get_viewport().get_texture().get_image().save_png("res://data/traffic.png")
	# stand in the road in front of the nearest car coming and see it stop
	var best = null
	for c in traffic.cars:
		var pose: Array = traffic._pose(traffic._ways[c["w"]], c["s"], c["dir"], 1.7)
		if c["v"] > 4.0 and (best == null or (pose[0] as Vector3).distance_to(player.global_position) < best[0]):
			best = [(pose[0] as Vector3).distance_to(player.global_position), c, pose]
	if best != null:
		var pose: Array = best[2]
		var ahead: Vector3 = pose[0] + Vector3(pose[1].x, 0, pose[1].y) * 14.0
		player.global_position = ahead + Vector3(0, 0.6, 0)
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		for i in 240:
			await get_tree().physics_frame
		var now: Array = traffic._pose(traffic._ways[best[1]["w"]], best[1]["s"], best[1]["dir"], 1.7)
		print("TRAFFIC stood 14 m in front of a car doing ", snappedf(best[1]["v"] * 3.6, 1.0), " km/h: four seconds on it does ", snappedf(best[1]["v"] * 3.6, 1.0), " km/h, ", snappedf((now[0] as Vector3).distance_to(player.global_position), 0.1), " m away")
	get_tree().quit()


## `./run.sh -- --menu`: open the menu and save a picture of it (data/menu.png), turn the clock by its hand and
## report what the light does, push each weather button, and try the reset from inside a vehicle far away.
func _menu_test_and_quit() -> void:
	await get_tree().create_timer(1.0).timeout
	menu.open()
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/menu.png")
	print("MENU open: ", menu.is_open, ", mouse free: ", Input.mouse_mode == Input.MOUSE_MODE_VISIBLE, ", panel ", menu._panel.size)
	daytime.rate = 0.0
	menu.set_hours(12.0)
	var line := ""
	for k in 25:                                          # a whole day round by the hand, an hour at a time
		for i in 4:
			await get_tree().process_frame
		line += "%02d:%02d sun %.0f night %.2f lit %.2f | " % [int(daytime.hours), int(fposmod(daytime.hours, 1.0) * 60.0), daytime.sun_height, daytime.night, daytime.lit_share]
		menu.turn_by(1.0)
	print("MENU the day round: ", line)
	print("MENU day of the year after passing midnight: ", daytime.day)
	menu.set_hours(21.5)
	for i in 30:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/menu_night.png")
	for k in weather.KINDS:
		menu._weather_buttons[k].pressed.emit()
		for i in 30:
			await get_tree().process_frame
		print("MENU weather button '%s': turning to %s, by itself %s, turn %.2f" % [k, weather.kind, weather.changing, weather._turn])
	menu._weather_buttons["changing"].pressed.emit()
	print("MENU 'changing': by itself ", weather.changing)
	menu.close()
	print("MENU closed: ", not menu.is_open, ", mouse taken: ", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED, )
	# reset from the Volvo, 600 m away
	player.global_position = player.vehicles[1].global_position + Vector3(1.6, 0.3, 0)
	for i in 10:
		await get_tree().physics_frame
	player._toggle_atv()
	player.global_position = Vector3(-600.0, world.height_at(-600.0, -420.0) + 1.0, -420.0)
	world.flush(player.global_position)
	for i in 30:
		await get_tree().physics_frame
	print("MENU before reset: driving ", player.driving, " at ", player.global_position.snappedf(1.0))
	menu.ask_reset()
	await get_tree().process_frame
	print("MENU asks first: ", menu._confirm.visible)
	menu._confirm.get_child(2).pressed.emit()
	for i in 30:
		await get_tree().physics_frame
	var at := []
	for v in player.vehicles:
		at.append("%s (%d, %d)" % [v.name, v.global_position.x, v.global_position.z])
	print("MENU after reset: driving ", player.driving, ", player at ", player.global_position.snappedf(0.1), " on the floor ", player.is_on_floor(), ", menu open ", menu.is_open, "; ", ", ".join(at))
	get_tree().quit()


## `./run.sh -- --sound`: stand in a few kinds of place and report what each background layer is at, then walk,
## drive and swim a little and report which sounds were played. (It cannot hear; it checks that the right sounds
## are asked for in the right places.)
func _sound_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	await get_tree().create_timer(1.0).timeout
	var spots := {"the fjord's edge": Vector2(30.0, 100.0), "the middle of town": Vector2(60.0, -60.0), "the forest": Vector2(-426.0, -3600.0)}
	for key in world._water_blocks:                      # and beside a river
		var p := Vector2((key.x * 50 + 25.5) * 2.0, (key.y * 50 + 25.5) * 2.0)
		var w: Dictionary = world.water_at(p.x, p.y)
		if not w.is_empty() and w["flow"].length() > 0.3:
			spots["a river"] = p + Vector2(4.0, 0.0)
			break
	for name in spots:
		var p: Vector2 = spots[name]
		player.global_position = Vector3(p.x, world.height_at(p.x, p.y) + 0.5, p.y)
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		for i in 240:
			await get_tree().process_frame
		print("SOUND %s (ground: %s): %s" % [name, sound.ground_kind(player.global_position), sound.levels])
	# walking on the square, then the Volvo, then the sea
	var s: Vector2 = world.spawn
	player.global_position = Vector3(s.x, world.height_at(s.x, s.y) + 0.5, s.y)
	player.reset_physics_interpolation()
	world.flush(player.global_position)
	sound.played.clear()
	Input.action_press("move_forward")
	for i in 150:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	print("SOUND walking 2.5 s: ", sound.played, " on ", sound.ground_kind(player.global_position), " cover ", world.cover_at(player.global_position.x, player.global_position.z),
		" over the ground ", snappedf(player.global_position.y - world.height_at(player.global_position.x, player.global_position.z), 0.01))
	sound.played.clear()
	player.global_position = player.vehicles[1].global_position + Vector3(1.6, 0.3, 0)
	for i in 10:
		await get_tree().physics_frame
	player._toggle_atv()
	Input.action_press("move_forward")
	for i in 150:
		await get_tree().physics_frame
	print("SOUND driving the Volvo 2.5 s: engine ", sound.levels.get("engine"), " pitch ", snappedf(sound._loops["engine"].pitch_scale, 0.01), ", roll ", sound.levels.get("roll"), "; played ", sound.played)
	Input.action_release("move_forward")
	player._toggle_atv()
	sound.played.clear()
	player.global_position = Vector3(s.x + 40.0, 3.0, s.y + 260.0)
	player.reset_physics_interpolation()
	world.flush(player.global_position)
	Input.action_press("move_forward")
	for i in 240:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	print("SOUND dropped in the sea and swimming 4 s: ", sound.played, " sea ", sound.levels.get("sea"))
	sound.muted = true
	print("SOUND muted: ", AudioServer.is_bus_mute(0))
	get_tree().quit()


## `./run.sh -- --swim`: the walker in the water. In the sea off the piers, in the largest lake and in the widest
## river it is put in and swims: breaststroke, then the crawl on Shift until out of breath, then lets the water
## carry it; then it swims for the shore and climbs out. Reports what happened and saves data/swim_*.png.
func _swim_test_and_quit() -> void:
	player.set_process_unhandled_input(false)
	await get_tree().create_timer(1.0).timeout
	# places: the sea 60 m off the shore south of the square; a lake and a river from the water grid
	var spots := {"sea": Vector2(world.spawn.x + 40.0, world.spawn.y + 260.0)}
	var best_lake := 0.0
	var best_river := 0.0
	for key in world._water_blocks:
		for iz in range(2, 50, 6):
			for ix in range(2, 50, 6):
				var p := Vector2((key.x * 50 + ix + 0.5) * 2.0, (key.y * 50 + iz + 0.5) * 2.0)
				var w: Dictionary = world.water_at(p.x, p.y)
				if w.is_empty():
					continue
				if w["flow"].length() < 0.01 and w["depth"] > best_lake:
					best_lake = w["depth"]
					spots["lake"] = p
				if w["flow"].length() > 0.3 and w["depth"] > best_river:
					best_river = w["depth"]
					spots["river"] = p
	for name in spots:
		var p: Vector2 = spots[name]
		var w: Dictionary = world.water_at(p.x, p.y)
		if w.is_empty():
			print("SWIM ", name, ": no water at ", p)
			continue
		player.global_position = Vector3(p.x, w["level"] + 1.5, p.y)
		player.velocity = Vector3.ZERO
		player.reset_physics_interpolation()
		player.stamina = 1.0
		player.yaw = 0.0
		player.pitch = -0.35
		player._arm.spring_length = 5.0
		world.flush(player.global_position)
		for i in 50:
			await get_tree().physics_frame
		print("SWIM %s at (%d, %d): level %.2f, depth %.2f, flow %.2f m/s; swimming %s, wading %.2f, head %.2f m over the water" % [name, p.x, p.y,
			w["level"], w["depth"], w["flow"].length(), player.swimming, player.wading, player.global_position.y + 1.75 - w["level"]])
		var from: Vector3 = player.global_position
		for i in 120:                                   # two seconds of nothing: carried by the flow
			await get_tree().physics_frame
		print("SWIM %s   left alone for 2 s it was carried %.1f m" % [name, Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length()])
		Input.action_press("move_forward")
		from = player.global_position
		for i in 180:
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png("res://data/swim_%s_breast.png" % name)
		print("SWIM %s   breaststroke 3 s: %.1f m, swimming %s" % [name, Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length(), player.swimming])
		Input.action_press("sprint")
		from = player.global_position
		for i in 180:
			await get_tree().physics_frame
		get_viewport().get_texture().get_image().save_png("res://data/swim_%s_crawl.png" % name)
		print("SWIM %s   crawl 3 s: %.1f m, crawling %s, breath left %.2f" % [name, Vector2(player.global_position.x - from.x, player.global_position.z - from.z).length(), player.crawling, player.stamina])
		var t := 0
		while player.crawling and t < 1200:
			await get_tree().physics_frame
			t += 1
		print("SWIM %s   out of breath after %.1f s more: crawling %s, swimming %s" % [name, t / 60.0, player.crawling, player.swimming])
		Input.action_release("sprint")
		Input.action_release("move_forward")
		# and out again: swim toward the nearest dry ground
		var shore := Vector2.ZERO
		var found := false
		for r in range(4, 400, 4):
			for a in 24:
				var q := Vector2(player.global_position.x, player.global_position.z) + Vector2(cos(a * TAU / 24.0), sin(a * TAU / 24.0)) * r
				if world.water_at(q.x, q.y).is_empty() and not found:
					shore = q
					found = true
			if found:
				break
		if found:
			var to := shore - Vector2(player.global_position.x, player.global_position.z)
			player.yaw = atan2(-to.x, -to.y)
			Input.action_press("move_forward")
			t = 0
			while (player.swimming or player.wading > 0.05 or player._climb > 0.0) and t < 3600:
				await get_tree().physics_frame
				t += 1
			Input.action_release("move_forward")
			var wn: Dictionary = world.water_at(player.global_position.x, player.global_position.z)
			print("SWIM %s   to the shore %.0f m off: out of the water %s after %.1f s, on the floor %s" % [name, to.length(), wn.is_empty() or player.wading < 0.05, t / 60.0, player.is_on_floor()])
			if t >= 3600:
				var pp: Vector3 = player.global_position
				print("SWIM %s   stuck at (%.1f, %.2f, %.1f): ground %.2f, water %s, swimming %s, wading %.2f, climbing %.2f, on a wall %s; shore aimed at (%.1f, %.1f) ground %.2f" % [name, pp.x, pp.y, pp.z,
					world.height_at(pp.x, pp.z), wn, player.swimming, player.wading, player._climb, player.is_on_wall(), shore.x, shore.y, world.height_at(shore.x, shore.y)])
			get_viewport().get_texture().get_image().save_png("res://data/swim_%s_out.png" % name)
	get_tree().quit()


## `./run.sh -- --look --from=x,z,height over the ground,yaw degrees,pitch degrees,field of view` saves what a
## free camera sees from there to data/look0.png (any number of --from; the walker is hidden).
func _look_and_quit() -> void:
	player.set_process_unhandled_input(false)
	player.visible = false
	var cam := Camera3D.new()
	cam.near = 0.1
	cam.far = 70000.0
	cam.rotation_order = EULER_ORDER_YXZ
	add_child(cam)
	cam.make_current()
	if "--no-ground" in OS.get_cmdline_user_args():       # (to see what lies under or behind the ground)
		world.get_node("Terrain").visible = false
		world._near_root.visible = false
	var n := 0
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--from="):
			continue
		var f := arg.substr(7).split_floats(",")
		var y: float = world.detail.surface_at(f[0], f[1])
		if is_nan(y):
			y = world.height_at(f[0], f[1])
		player.global_position = Vector3(f[0], y + 0.3, f[1])
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		cam.global_position = Vector3(f[0], y + 0.1 + f[2], f[1])
		cam.rotation = Vector3(deg_to_rad(f[4]), deg_to_rad(f[3]), 0.0)
		cam.fov = f[5] if f.size() > 5 else 75.0
		for i in 40:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png("res://data/look%d.png" % n)
		n += 1
	get_tree().quit()


## `./run.sh -- --wheels` photographs a wheel of every vehicle close up, from the side, from 45 degrees behind,
## from 45 degrees in front and from the inside, to data/wheel_<vehicle>_<view>.png (to check tyres are whole).
func _wheel_shots_and_quit() -> void:
	player.set_process_unhandled_input(false)
	var cam := Camera3D.new()
	cam.fov = 32.0
	cam.near = 0.05
	add_child(cam)
	cam.make_current()
	var lamp := OmniLight3D.new()                      # a lamp at the camera: tyres are black and often in shadow
	lamp.light_energy = 2.5
	lamp.omni_range = 8.0
	cam.add_child(lamp)
	var names := ["atv", "volvo", "integra", "heli", "mercedes", "bike"]
	# where a rear wheel is in each vehicle's own frame (to the left, up, back)
	var at := [Vector3(-0.47, 0.30, 0.62), Vector3(-0.78, 0.32, 1.35), Vector3(-0.74, 0.30, 1.28), Vector3(-1.0, 0.3, 0.5), Vector3(-0.76, 0.32, 1.40), Vector3(0.0, 0.35, 0.53)]
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wheel-at="):                 # --wheel-at=vehicle number,x,y,z to aim somewhere else
			var f := arg.substr(11).split_floats(",")
			at[int(f[0])] = Vector3(f[1], f[2], f[3])
	for k in names.size():
		var v: Node3D = player.vehicles[k]
		world.update_streaming(v.global_position)
		world.flush(v.global_position)
		var aim: Vector3 = v.global_transform * at[k]
		var views := {"side": Vector3(-1.9, 0.25, 0.0), "behind": Vector3(-1.35, 0.45, 1.35), "front": Vector3(-1.35, 0.3, -1.35), "inside": Vector3(1.2, -0.05, 1.5),
			"low": Vector3(-1.2, -0.22, 0.9)}
		for name in views:
			cam.global_position = aim + v.global_transform.basis * views[name]
			cam.look_at(aim)
			for i in (40 if name == "side" else 6):
				await get_tree().process_frame
			get_viewport().get_texture().get_image().save_png("res://data/wheel_%s_%s.png" % [names[k], name])
	get_tree().quit()


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
	print("BIKE jumped ", snappedf(top, 0.01), " m, back on the ground: ", player.wheels_down(), ", still going ", snappedf(player._drive_speed * 3.6, 0.1), " km/h")
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
## `./run.sh -- --patchtest`: lay a patch of each kind with the patch tool on Torget, photograph them
## (data/patches.png), then undo all three and check that tools/patches.jsonl is as it was.
func _patchtest_and_quit() -> void:
	player.set_process_unhandled_input(false)
	player.global_position = Vector3(8.0, world.height_at(8.0, 60.0) + 0.5, 60.0)
	player.reset_physics_interpolation()
	player.yaw = 0.4
	player.pitch = -0.5
	world.flush(player.global_position)
	for i in 60:
		await get_tree().physics_frame
	var path: String = devtool._patch_path
	var before := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	devtool.patching = true
	for k in 3:
		devtool._patch_kind = k
		devtool._patch_size = k
		player.yaw = 0.4 + 0.5 * float(k)
		for i in 10:
			await get_tree().process_frame
		devtool._patch_lay()
	devtool._patch_text()
	var after := FileAccess.get_file_as_string(path)
	print("PATCH laid 3: the file grew by ", after.count("\n") - before.count("\n"), " lines; last: ", after.strip_edges().split("\n")[-1])
	player.yaw = 0.9
	player.pitch = -0.35
	for i in 20:
		await get_tree().process_frame
	get_viewport().get_texture().get_image().save_png("res://data/patches.png")
	for k in 3:
		devtool._patch_undo()
	print("PATCH undone: file as before ", FileAccess.get_file_as_string(path) == before)
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
	# the longest roads within 2.5 km of the centre, a mix of main roads and residential streets; with
	# --roads=N that many, from all over the map; with --car in the Volvo; --quick runs the clock three times as fast
	var n_roads := 10
	var reach := 2500.0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--roads="):
			n_roads = 1000000 if arg.substr(8) == "all" else int(arg.substr(8))       # all: every road of 25 m and more
			reach = 1e9
	if "--car" in OS.get_cmdline_user_args():
		player.atv = player.vehicles[1]
	if "--quick" in OS.get_cmdline_user_args():
		Engine.physics_ticks_per_second = 180
		Engine.time_scale = 3.0
	if n_roads > 100000 or DisplayServer.get_name() == "headless":      # the whole map, or no window: as fast as the machine goes
		Engine.physics_ticks_per_second = 960
		Engine.time_scale = 16.0
		Engine.max_physics_steps_per_frame = 240
		world.detail.budget_usec = 400000
		world.detail.sweep = true                        # (no house fronts: only what is driven on)
	var picks := []
	for w in world.detail.ways:
		if w[1] != 0:
			continue
		var pts: PackedVector2Array = w[3]
		if pts[0].length() > reach or pts.size() < (60 if reach < 1e8 else (40 if n_roads < 100000 else 9)):
			continue
		picks.append([pts.size(), w])
	picks.sort_custom(func(a, b): return a[0] > b[0])
	var chosen := []
	for i in picks.size():
		if i % maxi(1, picks.size() / n_roads) == 0 and chosen.size() < n_roads:
			chosen.append(picks[i][1])
	print("DRIVE roads chosen: ", chosen.size())
	var total_stalls := 0
	var total_flights := 0
	var total_m := 0
	for w in chosen:
		var pts: PackedVector2Array = w[3]
		var a: Node3D = player.atv
		if player.driving:
			player._toggle_atv()
		var start := pts[1]
		var dir := (pts[3] - pts[1]).normalized()
		a.global_position = Vector3(start.x, world.height_at(start.x, start.y) + 0.3, start.y)
		a.global_rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
		a.reset_physics_interpolation()
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
		var flying := false
		var flights := 0
		while k < pts.size() - 2 and t < maxf(90.0, pts.size() * 3.0 / 7.0):
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
			if (absf(diff) > 0.35 and player._drive_speed > 9.0) or (n_roads != 10 and player._drive_speed > 16.0):
				Input.action_release("move_forward")                    # (the long test keeps to 60 km/h, as in town)
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
				print("DRIVE   stopped at (%d, %d) road point %d of %d, against: %s; under the wheels: %s" % [p.x, p.z, k, pts.size(), what, player.blocked_by])
			max_air = maxf(max_air, p.y - world.height_at(p.x, p.z))
			if player._air_time > 0.2 and not flying:
				flying = true
				flights += 1
				print("DRIVE   left the road at (%d, %d), %d km/h" % [p.x, p.z, int(player._drive_speed * 3.6)])
			elif player._air_time == 0.0:
				flying = false
		Input.action_release("move_forward")
		Input.action_release("move_left")
		Input.action_release("move_right")
		total_stalls += stalls
		total_flights += flights
		total_m += k * 3
		var ended := "yes" if k >= pts.size() - 2 else "NO, left at (%d, %d) heading for point %d at (%d, %d)" % [player.global_position.x, player.global_position.z, k, pts[k].x, pts[k].y]
		print("DRIVE %d m of road (width %.1f) from (%d, %d) in %.0f s: reached the end %s, top %d km/h, stopped %d times, highest off the ground %.1f m" % [
			pts.size() * 3, w[0] * 2.0, start.x, start.y, t, ended, int(top * 3.6), stalls, max_air])
	print("DRIVE total: ", total_m, " m driven, stops: ", total_stalls, ", times in the air: ", total_flights)
	get_tree().quit()


## `./run.sh -- --sweep`: photograph every 200 m tile that has paving, straight down, with the asphalt,
## the sidewalks, the paint and the bridge decks in flat signal colours on the real ground. The pictures go
## to data/sweep/<tile x>_<tile z>.png (10 cm a pixel; tools/sweep.py reads them). --tiles=x:z,x:z picks tiles.
func _sweep_and_quit() -> void:
	hud.start(world, player)
	player.set_process_unhandled_input(false)
	var d = world.detail
	d.sweep = true
	for k in d._cells.keys():
		d._drop(k)
	for pair in [["asphalt", Color(1, 0, 1)], ["sidewalk", Color(0, 1, 1)], ["mark", Color(0, 0, 1)], ["trim", Color(1, 1, 0)],
			["clad", Color(1, 1, 0)], ["plaster", Color(1, 1, 0)]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = pair[1]
		m.cull_mode = BaseMaterial3D.CULL_DISABLED
		d.fac.mats[pair[0]] = m
	var vp := SubViewport.new()
	vp.size = Vector2i(2000, 2000)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	var cam := Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 200.0
	cam.near = 1.0
	cam.far = 3000.0
	cam.cull_mask = 2
	cam.rotation = Vector3(-PI * 0.5, 0, 0)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	cam.environment = env
	vp.add_child(cam)
	cam.current = true
	var tiles := {}
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--tiles="):
			for t in arg.substr(8).split(","):
				var f := t.split(":")
				tiles[Vector2i(int(f[0]), int(f[1]))] = true
	if tiles.is_empty():
		for k in d.paved.keys():
			tiles[Vector2i(int(floor(k.x / 2.0)), int(floor(k.y / 2.0)))] = true
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://data/sweep"))
	var keys := tiles.keys()
	keys.sort()
	var n := 0
	for t in keys:
		var cx: float = t.x * 200.0 + 100.0
		var cz: float = t.y * 200.0 + 100.0
		player.global_position = Vector3(cx, world.height_at(cx, cz) + 0.3, cz)
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		cam.global_position = Vector3(cx, 1500.0, cz)
		for i in 4:
			await get_tree().process_frame
		vp.get_texture().get_image().save_png("res://data/sweep/%d_%d.png" % [t.x, t.y])
		n += 1
		if n % 20 == 0:
			print("SWEEP ", n, " / ", keys.size())
	print("SWEEP done: ", n, " tiles")
	get_tree().quit()


## `./run.sh -- --sweep-street`: look around from the street. Every 25 m along every road, and across the paved
## squares, sixteen small pictures are taken: in eight directions, from 1.7 m (a person) and from 1.2 m (in a
## car), with the asphalt, the sidewalks and the paint in flat signal colours and the empty sky in green. Each
## is taken twice: as the game draws it, and with the ground taken away, which shows the paving that should have
## been in view. The two sets go side by side into data/sweep_street/<number>.png, and index.json says where
## each was taken (tools/sweep.py --street reads them). --every=N takes every Nth place; --around=x,z,r only
## places within r of a point.
func _sweep_street_and_quit() -> void:
	hud.start(world, player)
	hud.visible = false
	player.set_process_unhandled_input(false)
	get_viewport().disable_3d = true
	player.visible = false                              # (it stands where each picture is taken, to keep the map loaded there)
	var d = world.detail
	d.budget_usec = 400000
	for k in d._cells.keys():
		d._drop(k)
	for pair in [["asphalt", Color(1, 0, 1)], ["sidewalk", Color(0, 1, 1)], ["mark", Color(0, 0, 1)]]:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = pair[1]
		d.fac.mats[pair[0]] = m
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.2, 0.9, 0.6)         # (an odd colour that nothing lit comes out as; the sheet shows it as green)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(1, 1, 1)
	env.ambient_light_energy = 0.6
	env.reflected_light_source = Environment.REFLECTION_SOURCE_DISABLED     # (or glass and chrome mirror the sky colour)
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	const W := 256
	const H := 160
	const FOV := 75.0
	const PITCH := -8.0
	var eyes := [1.7, 1.2]
	var cams := []
	var vps := []
	for e in eyes.size():
		for k in 8:
			var vp := SubViewport.new()
			vp.size = Vector2i(W, H)
			vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
			vp.msaa_3d = Viewport.MSAA_DISABLED
			add_child(vp)
			var cam := Camera3D.new()
			cam.fov = FOV
			cam.near = 0.1
			cam.far = 70000.0
			cam.environment = env
			cam.rotation_order = EULER_ORDER_YXZ
			cam.rotation = Vector3(deg_to_rad(PITCH), -TAU * float(k) / 8.0, 0.0)
			vp.add_child(cam)
			cam.current = true
			cams.append(cam)
			vps.append(vp)
	# The sixteen pictures are laid side by side on one sheet and boiled down to what matters: asphalt, sidewalk,
	# paint, empty sky, and black for everything else. (That also keeps the files small.)
	var atlas := SubViewport.new()
	atlas.size = Vector2i(W * 8, H * 2)
	atlas.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	atlas.disable_3d = true
	add_child(atlas)
	var sorter := Shader.new()
	sorter.code = "shader_type canvas_item;\nvoid fragment() {\n\tvec3 c = texture(TEXTURE, UV).rgb;\n\tvec3 o = vec3(0.0);\n\tif (c.r > 0.75 && c.g < 0.27 && c.b > 0.75) { o = vec3(1.0, 0.0, 1.0); }\n\telse if (c.r < 0.27 && c.g > 0.75 && c.b > 0.75) { o = vec3(0.0, 1.0, 1.0); }\n\telse if (c.r < 0.27 && c.g < 0.27 && c.b > 0.75) { o = vec3(0.0, 0.0, 1.0); }\n\telse if (abs(c.r - 0.2) < 0.02 && abs(c.g - 0.9) < 0.02 && abs(c.b - 0.6) < 0.02) { o = vec3(0.0, 1.0, 0.0); }\n\tCOLOR = vec4(o, 1.0);\n}\n"
	for c in vps.size():
		var tr := TextureRect.new()
		tr.texture = vps[c].get_texture()
		tr.position = Vector2((c % 8) * W, (c / 8) * H)
		tr.size = Vector2(W, H)
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var sm := ShaderMaterial.new()
		sm.shader = sorter
		tr.material = sm
		atlas.add_child(tr)
	# the places: along the roads, and on a 25 m lattice wherever there is asphalt that no road place is near
	var every := 1
	var around := Vector3(0, 0, 1e9)
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--every="):
			every = maxi(1, int(arg.substr(8)))
		if arg.begins_with("--around="):
			var f := arg.substr(9).split_floats(",")
			around = Vector3(f[0], f[1], f[2])
	var places := PackedVector2Array()
	var taken := {}
	for w in d.ways:
		if w[1] != 0:
			continue
		var pts: PackedVector2Array = w[3]
		var k := 4
		while k < pts.size():
			var key := Vector2i(int(floor(pts[k].x / 12.0)), int(floor(pts[k].y / 12.0)))
			if not taken.has(key):
				taken[key] = true
				places.append(pts[k])
			k += 8                                          # (road points are 3 m apart)
	var on_roads := places.size()
	for key in d.paved.keys():
		for ix in 4:
			for iz in 4:
				var p := Vector2(key.x * 100.0 + 12.5 + 25.0 * ix, key.y * 100.0 + 12.5 + 25.0 * iz)
				if is_nan(d.surface_at(p.x, p.y)):
					continue
				var near := false
				for ox in [-1, 0, 1]:
					for oz in [-1, 0, 1]:
						if taken.has(Vector2i(int(floor(p.x / 12.0)) + ox, int(floor(p.y / 12.0)) + oz)):
							near = true
				if not near:
					places.append(p)
	print("SWEEP-STREET places: ", places.size(), " (", on_roads, " along roads)")
	var dir := ProjectSettings.globalize_path("res://data/sweep_street")
	DirAccess.make_dir_recursive_absolute(dir)
	var terrain: Node3D = world.get_node("Terrain")
	var index := []
	var sheet := Image.create(W * 8, H * 4, false, Image.FORMAT_RGB8)
	var n := 0
	for i in range(0, places.size(), every):
		var p := places[i]
		if Vector2(p.x - around.x, p.y - around.y).length() > around.z:
			continue
		var y: float = d.surface_at(p.x, p.y)
		if is_nan(y):
			y = world.height_at(p.x, p.y)
		if y < 0.6:
			continue
		player.global_position = Vector3(p.x, y + 0.3, p.y)
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		for c in cams.size():
			cams[c].global_position = Vector3(p.x, y + 0.1 + eyes[c / 8], p.y)
		for pass_ in 2:
			terrain.visible = pass_ == 0
			world._near_root.visible = pass_ == 0
			for fr in 3:
				await RenderingServer.frame_post_draw
			var im: Image = atlas.get_texture().get_image()
			im.convert(Image.FORMAT_RGB8)
			if "--raw" in OS.get_cmdline_user_args() and pass_ == 0:      # the untouched pictures too, to see what a patch is
				for c in vps.size():
					vps[c].get_texture().get_image().save_png("res://data/sweep_street/raw_%05d_%02d.png" % [i, c])
			sheet.blit_rect(im, Rect2i(0, 0, W * 8, H * 2), Vector2i(0, pass_ * 2 * H))
		terrain.visible = true
		world._near_root.visible = true
		sheet.save_png("res://data/sweep_street/%05d.png" % i)
		index.append([i, snappedf(p.x, 0.01), snappedf(y + 0.1, 0.01), snappedf(p.y, 0.01)])
		n += 1
		if n % 200 == 0:
			print("SWEEP-STREET ", n, " taken, place ", i, " of ", places.size())
	var f := FileAccess.open("res://data/sweep_street/index.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"w": W, "h": H, "fov": FOV, "pitch": PITCH, "eyes": eyes, "places": index}))
	f.close()
	print("SWEEP-STREET done: ", n, " places")
	get_tree().quit()


## `./run.sh -- --jumps`: drive the Volvo flat out over the sharpest crests of the road network and report how
## high and how long it flies at each (to compare the feel of jumps between versions). `--jumps --find` only
## lists the crests; `--spots=x:z,x:z` picks the places; `--vehicle=N` takes another vehicle.
func _jumps_and_quit() -> void:
	hud.start(world, player)
	player.set_process_unhandled_input(false)
	var spots := []
	var vehicle := 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--spots="):
			for s in arg.substr(8).split(","):
				spots.append(Vector2(float(s.split(":")[0]), float(s.split(":")[1])))
		if arg.begins_with("--vehicle="):
			vehicle = int(arg.substr(10))
	# the crests: where the road, 3 m a point, bends downward most after climbing
	var found := []
	for w in world.detail.ways:
		if w[1] != 0:
			continue
		var pts: PackedVector2Array = w[3]
		if pts.size() < 90:
			continue
		var h := PackedFloat32Array()
		for p in pts:
			h.append(world.height_at(p.x, p.y))
		for i in range(60, pts.size() - 25):
			var bend := (h[i - 3] - 2.0 * h[i] + h[i + 3]) / 81.0
			for dirn in [1, -1]:
				var climb: float = h[i] - h[i - 4 * dirn]
				if bend < -0.004 and climb > 0.5:
					found.append([bend, w, i, dirn])
	found.sort_custom(func(a, b): return a[0] < b[0])
	var runs := []
	if spots.is_empty():
		for f in found:
			var p: Vector2 = f[1][3][f[2]]
			var near := false
			for r in runs:
				if (r[1][3][r[2]] as Vector2).distance_to(p) < 150.0:
					near = true
			if not near:
				runs.append(f)
			if runs.size() >= 12:
				break
	else:
		for s in spots:
			var best = null
			for f in found:
				var d: float = (f[1][3][f[2]] as Vector2).distance_to(s)
				if d < 40.0 and (best == null or f[0] < best[0]):
					best = f
			if best != null:
				runs.append(best)
			else:
				print("JUMP no crest found near ", s)
	for r in runs:
		var p: Vector2 = r[1][3][r[2]]
		print("JUMP crest at (%d, %d): bend %.4f per m, direction %d" % [p.x, p.y, r[0], r[3]])
	if "--find" in OS.get_cmdline_user_args():
		get_tree().quit()
		return
	if DisplayServer.get_name() == "headless":
		Engine.physics_ticks_per_second = 240
		Engine.time_scale = 4.0
		Engine.max_physics_steps_per_frame = 60
	player.atv = player.vehicles[vehicle]
	var total_air := 0.0
	var total_high := 0.0
	for r in runs:
		var pts: PackedVector2Array = r[1][3]
		var i0: int = r[2]
		var dirn: int = r[3]
		var k: int = i0 - 55 * dirn                      # 165 m of run-up
		k = clampi(k, 2, pts.size() - 3)
		var a: Node3D = player.atv
		if player.driving:
			player._toggle_atv()
		var start := pts[k]
		var dir := (pts[k + 2 * dirn] - pts[k]).normalized()
		a.global_position = Vector3(start.x, world.height_at(start.x, start.y) + 0.3, start.y)
		a.global_rotation = Vector3(0, atan2(-dir.x, -dir.y), 0)
		a.reset_physics_interpolation()
		player.global_position = a.global_position + Vector3(0.3, 0.3, 0)
		player.reset_physics_interpolation()
		world.flush(player.global_position)
		for i in 5:
			await get_tree().physics_frame
		player._toggle_atv()
		Input.action_press("move_forward")
		var t := 0.0
		var high := 0.0
		var air := 0.0
		var longest := 0.0
		var speed_at := 0.0
		var last := k + 25 * dirn
		var goal: int = clampi(i0 + 22 * dirn, 2, pts.size() - 3)
		k += dirn
		while k != goal and t < 40.0:
			await get_tree().physics_frame
			t += 1.0 / float(Engine.physics_ticks_per_second)
			var p: Vector3 = player.global_position
			var here := Vector2(p.x, p.z)
			while k != goal and here.distance_to(pts[k]) < 9.0:
				k += dirn
			var want := pts[k] - here
			var diff := angle_difference(player._heading, atan2(-want.x, -want.y))
			Input.action_release("move_left")
			Input.action_release("move_right")
			if diff > 0.04:
				Input.action_press("move_left", clampf(diff * 3.0, 0.0, 1.0))
			elif diff < -0.04:
				Input.action_press("move_right", clampf(-diff * 3.0, 0.0, 1.0))
			if here.distance_to(pts[i0]) < 70.0:
				var up: float = p.y - world.height_at(p.x, p.z)
				high = maxf(high, up)
				if up > 0.7:
					air += 1.0 / float(Engine.physics_ticks_per_second)
					longest = maxf(longest, air)
				else:
					air = 0.0
				if here.distance_to(pts[i0]) < 6.0:
					speed_at = player._drive_speed
		Input.action_release("move_forward")
		Input.action_release("move_left")
		Input.action_release("move_right")
		total_air += longest
		total_high += high
		print("JUMP at (%d, %d): %d km/h at the crest, highest off the ground %.2f m, in the air %.2f s" % [pts[i0].x, pts[i0].y, int(speed_at * 3.6), high, longest])
	print("JUMP total over %d crests: height %.2f m, air %.2f s" % [runs.size(), total_high, total_air])
	get_tree().quit()
