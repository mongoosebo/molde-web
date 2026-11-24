extends Node
## The time of day. A clock moves the sun along its real path over Molde (62.7° N) for a date, and sets from it
## the sun's colour and strength, the sky, the ambient light and the fog. At night: moonlight, a darker and
## bluer town, stars, the street lamps lit (a glowing head on every lamp, real light from the nearest few
## dozen), windows glowing (shaders/building.gdshader and the close-up fronts read how many are lit), and the
## lights of the vehicles.
##
## A day takes 40 minutes of play. `[` and `]` step an hour back and forward; `./run.sh -- --time=21:30` starts
## at a time. The weather (scripts/weather.gd) dims and greys what this sets, through `cover`, `haze` and `gloom`.

const LATITUDE := 62.74
const DAY_SECONDS := 2400.0              # a day in 40 minutes
const LAMP_LIGHTS := 28
var _light_of := {}                 # lamp number -> which light of the pool stands at it
var _free_lights: Array = []

var world
var player
var hours := 17.0                        # the time of day, 0 to 24 (clock time in Molde)
var day := 258                           # day of the year: mid-September
var rate := 1.0                          # how fast time runs: 0 stopped, 1 a day in 40 minutes, 10 a day in 4
var night := 0.0                         # 0 by day, 1 in the dark
var lit_share := 0.015                   # how many of the windows are lit
var sun_height := 0.0                    # degrees over the horizon
var cover := 0.0                         # from the weather: how much of the sky is cloud, 0 to 1
var haze := 1.0                          # from the weather: how thick the air is (1 is the usual light haze)
var gloom := 0.0                         # from the weather: how much light the cloud takes, 0 to 1
var cloud := 0.0                          # from the weather: how far cloud has come down on the hills, 0 to 1

var no_shadows := false                  # the benchmark's price list: the sun casts none

var _env: Environment
var _sky: ProceduralSkyMaterial
var _sun: DirectionalLight3D
var _moon: DirectionalLight3D
var _moon_disc: MeshInstance3D
var _lamp_heads: MultiMeshInstance3D
var _lamp_mat: StandardMaterial3D
var _lamp_at := PackedVector3Array()     # every lamp head in the map
var _lamp_cells := {}                    # 100 m cell -> indices into _lamp_at
var _lights: Array = []
var _lights_tick := 0.0
var _beams: Array = []                   # the headlights of the vehicle being driven
var _beams_on: Node3D
var _fog_base := 0.00075
var _applied := Vector4(-99, 0, 0, 0)

# the sky by the sun's height (degrees): [height, top, horizon, sun colour, sun strength, ambient]
const KEYS := [
	[-14.0, Color(0.006, 0.008, 0.018), Color(0.014, 0.020, 0.036), Color(1.0, 0.5, 0.3), 0.0, 0.5],
	[-6.0, Color(0.03, 0.04, 0.09), Color(0.12, 0.10, 0.12), Color(1.0, 0.5, 0.3), 0.0, 0.6],
	[-1.0, Color(0.11, 0.14, 0.26), Color(0.62, 0.36, 0.22), Color(1.0, 0.48, 0.25), 0.05, 0.8],
	[3.0, Color(0.22, 0.27, 0.40), Color(0.72, 0.50, 0.34), Color(1.0, 0.62, 0.36), 0.75, 1.0],
	[12.0, Color(0.30, 0.35, 0.44), Color(0.66, 0.58, 0.50), Color(1.0, 0.80, 0.62), 1.2, 1.0],
	[24.0, Color(0.27, 0.40, 0.60), Color(0.62, 0.66, 0.70), Color(1.0, 0.92, 0.82), 1.3, 1.0],
	[50.0, Color(0.20, 0.38, 0.68), Color(0.58, 0.68, 0.78), Color(1.0, 0.96, 0.90), 1.35, 1.0],
]


func setup(w, p, env: Environment, sun: DirectionalLight3D) -> void:
	world = w
	player = p
	_env = env
	_sun = sun
	_sky = env.sky.sky_material
	_fog_base = env.fog_density
	_moon = DirectionalLight3D.new()
	_moon.light_color = Color(0.55, 0.66, 0.95)
	_moon.light_energy = 0.0
	_moon.shadow_enabled = false
	_moon.light_angular_distance = 0.5
	add_child(_moon)
	# stars: a sky full of points, shown as the sky darkens
	var stars := Image.create(2048, 1024, false, Image.FORMAT_RGB8)
	stars.fill(Color(0, 0, 0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 62
	for i in 2600:
		var b := pow(rng.randf(), 3.0) * 0.9 + 0.1
		var tint := Color(b, b * rng.randf_range(0.88, 1.0), b * rng.randf_range(0.8, 1.0))
		var x := rng.randi_range(0, 2046)
		var y := int(acos(rng.randf_range(0.0, 1.0)) / PI * 1023.0)      # evenly over the upper half of the sky
		stars.set_pixel(x, y, tint)
		if b > 0.6:
			stars.set_pixel(x + 1, y, tint * 0.5)
	_sky.sky_cover = ImageTexture.create_from_image(stars)
	_sky.sky_cover_modulate = Color(1, 1, 1, 0)
	_setup_lamps()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--time="):
			var t := arg.substr(7).split(":")
			hours = float(t[0]) + (float(t[1]) / 60.0 if t.size() > 1 else 0.0)
			rate = 0.0                                      # (a check at a set time: the clock stands still)
		if arg.begins_with("--date="):
			day = int(arg.substr(7))
	apply()


## The street lamps: a glowing head for every one in the map (one mesh, drawn many times), and a few real lights
## that are moved to the lamps nearest the player.
func _setup_lamps() -> void:
	var kind_lamp: int = world.props.LAMP
	for key in world.props.cells:
		for rec in world.props.cells[key]:
			if rec[0] == kind_lamp:
				var at: Vector3 = (rec[1] as Transform3D) * Vector3(0, 6.83, -1.45)
				if not _lamp_cells.has(key):
					_lamp_cells[key] = PackedInt32Array()
				_lamp_cells[key].append(_lamp_at.size())
				_lamp_at.append(at)
	_lamp_mat = StandardMaterial3D.new()
	_lamp_mat.albedo_color = Color(0.95, 0.9, 0.75)
	_lamp_mat.emission_enabled = true
	_lamp_mat.emission = Color(1.0, 0.80, 0.52)
	_lamp_mat.emission_energy_multiplier = 0.0
	var head := BoxMesh.new()
	head.size = Vector3(0.20, 0.05, 0.50)
	head.material = _lamp_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = head
	mm.instance_count = _lamp_at.size()
	var k := 0
	for key in world.props.cells:
		for rec in world.props.cells[key]:
			if rec[0] == kind_lamp:
				var xf: Transform3D = rec[1]
				mm.set_instance_transform(k, Transform3D(xf.basis.orthonormalized(), _lamp_at[k]))
				k += 1
	_lamp_heads = MultiMeshInstance3D.new()
	_lamp_heads.name = "LampHeads"
	_lamp_heads.multimesh = mm
	_lamp_heads.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_lamp_heads.visible = false
	add_child(_lamp_heads)
	for i in LAMP_LIGHTS:
		var l := OmniLight3D.new()
		l.light_color = Color(1.0, 0.78, 0.50)
		l.omni_range = 17.0
		l.omni_attenuation = 1.3
		l.shadow_enabled = false
		l.visible = false
		add_child(l)
		_lights.append(l)
		_free_lights.append(i)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("time_back"):
		hours = fposmod(hours - 1.0, 24.0)
	elif event.is_action_pressed("time_on"):
		hours = fposmod(hours + 1.0, 24.0)


func _process(delta: float) -> void:
	var t0_ := Time.get_ticks_usec()
	_run(delta)
	if world != null:
		world.took("daytime", t0_)


func _run(delta: float) -> void:
	hours += delta * rate * 24.0 / DAY_SECONDS
	if hours >= 24.0:
		hours -= 24.0
		day = day % 365 + 1
	# (the sky is worked out again each time it changes, which costs: so only when the clock or the weather has moved)
	var mark := Vector4(hours, cover, haze, gloom + cloud)
	if absf(hours - _applied.x) > 0.004 or absf(cover - _applied.y) > 0.004 or absf(haze - _applied.z) > 0.004 or absf(gloom + cloud - _applied.w) > 0.004:
		_applied = mark
		apply()
	_lights_tick -= delta
	if _lights_tick <= 0.0:
		_lights_tick = 0.1
		_place_lights()
	# each lamp's light goes toward what it should be over a third of a second, every frame: set ten times a
	# second in steps, it could be seen stepping (./run.sh -- --lamps counted jumps of over a fifth)
	for k in _light_goal:
		var l: OmniLight3D = _lights[k]
		l.light_energy = move_toward(l.light_energy, float(_light_goal[k]), delta * 6.6)
		l.visible = l.light_energy > 0.01
	_headlights()


## Where the sun stands: [height over the horizon, bearing clockwise from north], degrees.
func sun_at(h: float, d: int) -> Vector2:
	var decl := deg_to_rad(23.44) * sin(TAU * (284.0 + d) / 365.0)
	var summer_time := d > 86 and d < 300                       # the clocks are an hour on from the end of March to the end of October
	var solar := h - (1.0 if summer_time else 0.0) - 1.0 + 7.16 / 15.0      # Molde lies at 7.16° E; its clock is that of 15° E
	var ha := deg_to_rad(15.0 * (solar - 12.0))
	var lat := deg_to_rad(LATITUDE)
	var el := asin(sin(lat) * sin(decl) + cos(lat) * cos(decl) * cos(ha))
	var az := atan2(-sin(ha), tan(decl) * cos(lat) - sin(lat) * cos(ha))
	return Vector2(rad_to_deg(el), fposmod(rad_to_deg(az), 360.0))


func _toward(height: float, bearing: float) -> Vector3:
	var el := deg_to_rad(height)
	var az := deg_to_rad(bearing)
	return Vector3(cos(el) * sin(az), sin(el), -cos(el) * cos(az))          # east is +x, north is -z


## Set everything from the clock (and what the weather says).
func apply() -> void:
	var s := sun_at(hours, day)
	sun_height = s.x
	var to_sun := _toward(s.x, s.y)
	_sun.look_at_from_position(to_sun * 100.0, Vector3.ZERO, Vector3.UP if absf(to_sun.y) < 0.99 else Vector3.RIGHT)
	# between the keys
	var a: Array = KEYS[0]
	var b: Array = KEYS[KEYS.size() - 1]
	for i in KEYS.size() - 1:
		if s.x >= KEYS[i][0]:
			a = KEYS[i]
			b = KEYS[i + 1]
	var t := smoothstep(0.0, 1.0, clampf((s.x - a[0]) / (b[0] - a[0]), 0.0, 1.0))
	var top: Color = (a[1] as Color).lerp(b[1], t)
	var horizon: Color = (a[2] as Color).lerp(b[2], t)
	var sun_col: Color = (a[3] as Color).lerp(b[3], t)
	var sun_e: float = lerpf(a[4], b[4], t)
	var amb: float = lerpf(a[5], b[5], t)
	night = 1.0 - smoothstep(-9.0, 1.0, s.x)
	# cloud takes the colour out of the sky and the strength out of the sun
	var grey := Color(0.5, 0.5, 0.5) * (top.get_luminance() * 0.6 + horizon.get_luminance() * 0.9)
	top = top.lerp(grey * 0.8, cover * 0.9)
	horizon = horizon.lerp(grey * 1.05, cover * 0.85)
	sun_e *= 1.0 - 0.97 * smoothstep(0.0, 0.75, gloom)                # (under thick cloud there is no sun to cast shadows)
	_sky.sky_top_color = top
	_sky.sky_horizon_color = horizon
	_sky.ground_horizon_color = horizon
	_sky.ground_bottom_color = horizon * 0.25
	_sky.sky_cover_modulate = Color(1, 1, 1, clampf(night * 1.4 - 0.4, 0.0, 1.0) * (1.0 - cover))
	_sun.light_color = sun_col
	_sun.light_energy = sun_e
	_sun.shadow_enabled = sun_e > 0.03 and not no_shadows
	# the moon stands across the sky from the sun, a quarter up, when the sun is down
	_moon.look_at_from_position(_toward(28.0, s.y + 160.0) * 100.0, Vector3.ZERO)
	_moon.light_energy = 0.22 * night * (1.0 - 0.7 * cover)
	_moon.visible = night > 0.02                         # (a light of no strength still shows in the sky, as a dark disc)
	# the moon itself, where its glow is: a pale disc of its real size (half a degree across), far off
	if _moon_disc == null:
		_moon_disc = MeshInstance3D.new()
		var ball := SphereMesh.new()
		# The moon is half a degree across. Drawn so on a screen that shows 70 degrees and more it is a dot (as a
		# wide-angle photograph makes it), not the moon one remembers: it is drawn three times that, 1.6 degrees.
		ball.radius = 20000.0 * tan(deg_to_rad(0.8))
		ball.height = ball.radius * 2.0
		ball.radial_segments = 32
		ball.rings = 16
		var mm := StandardMaterial3D.new()
		mm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mm.albedo_color = Color(0.93, 0.92, 0.86)
		mm.disable_fog = true
		ball.material = mm
		_moon_disc.mesh = ball
		_moon_disc.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(_moon_disc)
	var cam := get_viewport().get_camera_3d()
	_moon_disc.visible = night > 0.15 and cover < 0.8
	if cam != null:
		_moon_disc.global_position = cam.global_position + _toward(28.0, s.y + 160.0) * 20000.0
	_env.ambient_light_energy = amb * (1.0 + 2.2 * night) * (1.0 + 0.5 * gloom)      # (the cloud's own even light)
	_env.fog_light_color = horizon.lerp(Color(0.5, 0.5, 0.5) * horizon.get_luminance(), 0.3) * (1.0 - 0.3 * night)
	_env.fog_density = _fog_base * haze
	# low cloud: the air thickens above a height, which comes down as the cloud does
	_env.fog_height = lerpf(420.0, 150.0, cloud)
	_env.fog_height_density = -0.012 * cloud
	var back = world.get_node_or_null("Backdrop")
	if back != null:
		var fog_col: Color = _env.fog_light_color
		(back.material_override as ShaderMaterial).set_shader_parameter("haze", Vector3(fog_col.r, fog_col.g, fog_col.b) * 0.5)
		(back.material_override as ShaderMaterial).set_shader_parameter("thick", haze)
	# how many windows are lit: few by day, most in the evening, a handful after midnight
	var lit := 0.015
	if night > 0.02 or s.x < 6.0:
		var dusk := 1.0 - smoothstep(-4.0, 6.0, s.x)
		var late := smoothstep(22.5, 24.5, hours if hours > 12.0 else hours + 24.0)       # going to bed
		var early := smoothstep(5.5, 7.0, hours) * (1.0 - smoothstep(7.5, 9.0, hours)) if hours < 12.0 else 0.0
		lit = maxf(0.015, dusk * lerpf(0.55, 0.07, late) + 0.25 * early * dusk)
	RenderingServer.global_shader_parameter_set("night", night)
	lit_share = lit
	RenderingServer.global_shader_parameter_set("lit_share", lit)
	if world.detail != null and world.detail.fac != null:
		var mats: Dictionary = world.detail.fac.mats
		if mats.has("glass_eve"):
			mats["glass_eve"].emission_energy_multiplier = 1.5 * night * smoothstep(0.10, 0.30, lit)
			mats["glass_late"].emission_energy_multiplier = 1.5 * night
	_lamp_mat.emission_energy_multiplier = 3.5 * smoothstep(0.25, 0.6, night)
	_lamp_heads.visible = night > 0.2
	# vehicle lamps glow harder in the dark
	for v in player.vehicles:
		var m = v.get("_mats")
		if m is Dictionary:
			for key in ["lamp", "tail", "red"]:
				if m.has(key) and m[key] is StandardMaterial3D and m[key].emission_enabled:
					if not m[key].has_meta("day"):
						m[key].set_meta("day", m[key].emission_energy_multiplier)
					m[key].emission_energy_multiplier = float(m[key].get_meta("day")) * (1.0 + 5.0 * night)
	if player.sound != null:
		player.sound.night = night


## Real light from the lamps nearest the player (only so many, to stay cheap).
var _light_goal := {}          # light -> the strength it is on its way to


func _place_lights() -> void:
	var on := night > 0.3
	if not on:
		_light_goal.clear()
		for l in _lights:
			l.visible = false
		for lamp in _light_of.keys():
			_free_lights.append(_light_of[lamp])
		_light_of.clear()
		return
	var pos: Vector3 = player.global_position
	var c := Vector2i(int(floor(pos.x / 100.0)), int(floor(pos.z / 100.0)))
	var near := []
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var list = _lamp_cells.get(Vector2i(c.x + dx, c.y + dz))
			if list != null:
				for i in list:
					# (only those within 100 m: nearer than that the nine cells hold every lamp there is, so the
					# set does not change at a stroke when the player crosses into another cell)
					if _lamp_at[i].distance_squared_to(pos) < 10000.0:
						near.append([_lamp_at[i].distance_squared_to(pos), i])
	near.sort_custom(func(p, q): return p[0] < q[0])
	var e := 2.2 * smoothstep(0.3, 0.7, night)
	# Each lamp keeps the light it has for as long as it is among the nearest (a light that hopped from lamp to
	# lamp as the order changed, and lamps coming into reach at full strength, made the lights flicker when
	# driving: note of 18 Nov). A lamp's light comes up as it comes nearer than the farthest one that is lit.
	var edge: float = sqrt(near[_lights.size() - 1][0]) if near.size() >= _lights.size() else 100.0
	var wanted := {}
	for k in mini(near.size(), _lights.size()):
		wanted[near[k][1]] = sqrt(near[k][0])
	for lamp in _light_of.keys():
		if not wanted.has(lamp):
			_free_lights.append(_light_of[lamp])
			(_lights[_light_of[lamp]] as OmniLight3D).visible = false
			_light_goal.erase(_light_of[lamp])
			_light_of.erase(lamp)
	for lamp in wanted:
		if not _light_of.has(lamp):
			if _free_lights.is_empty():
				continue
			_light_of[lamp] = _free_lights.pop_back()
			(_lights[_light_of[lamp]] as OmniLight3D).global_position = _lamp_at[lamp] - Vector3(0, 0.25, 0)
			(_lights[_light_of[lamp]] as OmniLight3D).light_energy = 0.0
		_light_goal[_light_of[lamp]] = e * (1.0 - smoothstep(edge * 0.72, edge * 0.98, float(wanted[lamp])))


## Two beams ahead of the vehicle being driven, at dusk and at night.
func _headlights() -> void:
	var want: Node3D = player.atv if player.driving and night > 0.25 else null
	if want != _beams_on:
		for b in _beams:
			b.queue_free()
		_beams.clear()
		_beams_on = want
		if want != null:
			var bike: bool = want.name == "Bicycle"
			var heli: bool = want.name == "Helicopter"
			var half := 0.0 if bike else (0.22 if want.name == "ATV" or heli else 0.62)
			var front := -0.9 if bike or want.name == "ATV" else -2.2
			for sx in ([0.0] if half == 0.0 else [-half, half]):
				var sp := SpotLight3D.new()
				sp.light_color = Color(1.0, 0.95, 0.82)
				sp.spot_range = 20.0 if bike else 60.0
				sp.spot_angle = 30.0 if not heli else 38.0
				sp.spot_attenuation = 0.8
				sp.shadow_enabled = false
				sp.position = Vector3(sx, 0.75 if not bike else 0.95, front)
				sp.rotation_degrees = Vector3(-4.0 if not heli else -38.0, 0.0, 0.0)
				var holder: Node = want.get("_chassis") if want.get("_chassis") is Node3D else want
				holder.add_child(sp)
				_beams.append(sp)
	for b in _beams:
		b.light_energy = (2.0 if _beams_on != null and _beams_on.name == "Bicycle" else 5.0) * smoothstep(0.25, 0.6, night)
