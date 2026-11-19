extends Node
## The weather: clear, cloudy, rain, heavy rain or low cloud. It changes slowly by itself (every few minutes,
## over most of a minute), or is set with V, with `./run.sh -- --weather=rain`, or from the menu. Each weather
## sets how much of the sky is cloud, how much light that takes, how thick the air is, how hard it blows and how
## hard it rains; the clock (scripts/daytime.gd) colours the sky and the light from that.
##
## Rain falls as streaks around the camera only, rings the water (scripts/ripples.gd) and splashes on the
## ground near the player. The ground, the roads and the roofs get darker and shinier as it goes on and dry
## slowly after (a wetness the shaders and materials read), and puddles stand in the hollows of the asphalt.
## Low cloud hangs on the mountains across the fjord and on the tops of Moldemarka.

const KINDS := ["clear", "cloudy", "rain", "heavy rain", "low cloud"]
# cover: cloud in the sky; gloom: light taken; haze: thickness of the air (1 is the usual); wind and rain 0 to 1;
# cloud: how far the cloud has come down on the hills (0 not at all)
const SET := {
	"clear": {"cover": 0.0, "gloom": 0.0, "haze": 0.35, "wind": 0.15, "rain": 0.0, "cloud": 0.0},
	"cloudy": {"cover": 0.75, "gloom": 0.45, "haze": 1.0, "wind": 0.35, "rain": 0.0, "cloud": 0.0},
	"rain": {"cover": 0.95, "gloom": 0.7, "haze": 1.8, "wind": 0.5, "rain": 0.45, "cloud": 0.25},
	"heavy rain": {"cover": 1.0, "gloom": 0.85, "haze": 3.0, "wind": 0.8, "rain": 1.0, "cloud": 0.5},
	"low cloud": {"cover": 1.0, "gloom": 0.72, "haze": 2.2, "wind": 0.2, "rain": 0.0, "cloud": 1.0},
}
# what tends to follow what, when the weather changes by itself
const NEXT := {
	"clear": ["clear", "cloudy", "cloudy", "low cloud"],
	"cloudy": ["clear", "clear", "rain", "low cloud", "cloudy"],
	"rain": ["cloudy", "heavy rain", "rain", "low cloud"],
	"heavy rain": ["rain", "rain", "cloudy"],
	"low cloud": ["cloudy", "rain", "clear"],
}

var world
var player
var daytime
var kind := "cloudy"                     # the weather it is, or is turning into
var changing := true                     # whether it changes by itself
var now := {}                            # the values at this moment (between two weathers while it turns)
var wetness := 0.0                       # how wet everything is, 0 dry to 1 soaked
var winter := false: set = set_winter    # the season (the menu): snow on the ground and the roofs, and what falls is snow
var snow := 0.0                          # how much snow lies, 0 to 1: follows `winter` over a few seconds
var indoors := false                     # the walker is inside a building (scripts/indoors.gd): no rain, snow or breath there
var slippery := false                    # winter roads that are slippery to drive on (the menu; scripts/player.gd reads it)


## In winter the rain falls as snow: slow, drifting flakes instead of streaks.
func set_winter(on: bool) -> void:
	winter = on
	if _rain == null:
		return
	var pm := _rain.process_material as ParticleProcessMaterial
	pm.initial_velocity_min = 1.6 if on else 15.0
	pm.initial_velocity_max = 2.6 if on else 19.0
	pm.gravity = Vector3(0, -0.2, 0) if on else Vector3(0, -4.0, 0)
	pm.spread = 25.0 if on else 2.0
	_rain.lifetime = 6.0 if on else 1.0
	(_rain.draw_pass_1 as QuadMesh).size = Vector2(0.045, 0.045) if on else Vector2(0.014, 0.7)
	var m := (_rain.draw_pass_1 as QuadMesh).material as StandardMaterial3D
	m.albedo_color = Color(0.95, 0.96, 0.98, 0.85) if on else Color(0.78, 0.82, 0.86, 0.32)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED if on else BaseMaterial3D.BILLBOARD_FIXED_Y
	_rain.restart()
var wind := 0.3                          # how hard it blows now, 0 calm to 1 storm (with gusts)
var wind_set := -1.0                     # the menu's slider: under 0, the weather decides
var wind_dir := Vector2(0.94, 0.34)      # the way it blows (down the fjord, as the waves run)

var flags := 0                           # how many flags fly (for the checks)
var _from := {}
var _turn := 1.0                         # 0 to 1 through a change
var _turn_time := 45.0
var _next_in := 240.0
var _rain: GPUParticles3D
var _drops: GPUParticles3D
var _rng := RandomNumberGenerator.new()
var _mats_tick := 0.0
var _puddles := {}                       # cell -> MultiMeshInstance3D
var _puddle_mat: StandardMaterial3D
var _puddle_tick := 0.0
var _gust := 0.0


func setup(w, p, d) -> void:
	world = w
	player = p
	daytime = d
	now = SET[kind].duplicate()
	_from = now.duplicate()
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--weather="):
			var k := arg.substr(10).replace("_", " ").replace("-", " ")
			if SET.has(k):
				kind = k
				now = SET[k].duplicate()
				_from = now.duplicate()
				changing = false
				wetness = 1.0 if now["rain"] > 0.0 else 0.0
	_setup_rain()
	_setup_flags()
	_puddle_mat = StandardMaterial3D.new()
	_puddle_mat.albedo_color = Color(0.03, 0.035, 0.04, 0.0)
	_puddle_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_puddle_mat.roughness = 0.03
	_puddle_mat.metallic_specular = 0.9
	_puddle_mat.metallic = 0.2
	_apply(0.0)


## Turn to another weather, over `seconds` (not in a jump).
func set_weather(k: String, seconds := 6.0) -> void:
	if not SET.has(k):
		return
	_from = now.duplicate()
	kind = k
	_turn = 0.0
	_turn_time = maxf(seconds, 0.1)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("weather"):
		changing = false
		set_weather(KINDS[(KINDS.find(kind) + 1) % KINDS.size()])


func _setup_rain() -> void:
	# the streaks: thin upright cards in a box that follows the camera
	_rain = GPUParticles3D.new()
	_rain.amount = 5000
	_rain.lifetime = 1.0
	_rain.local_coords = false
	_rain.visibility_aabb = AABB(Vector3(-30, -30, -30), Vector3(60, 60, 60))
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(16.0, 1.0, 16.0)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 2.0
	pm.initial_velocity_min = 15.0
	pm.initial_velocity_max = 19.0
	pm.gravity = Vector3(0, -4.0, 0)
	_rain.process_material = pm
	var card := QuadMesh.new()
	card.size = Vector2(0.014, 0.7)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.78, 0.82, 0.86, 0.32)
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	card.material = m
	_rain.draw_pass_1 = card
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.emitting = false
	add_child(_rain)
	# where the drops land near the player: small flecks springing up off the ground
	_drops = GPUParticles3D.new()
	_drops.amount = 500
	_drops.lifetime = 0.22
	_drops.local_coords = false
	_drops.visibility_aabb = AABB(Vector3(-20, -5, -20), Vector3(40, 10, 40))
	var dm := ParticleProcessMaterial.new()
	dm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	dm.emission_box_extents = Vector3(9.0, 0.02, 9.0)
	dm.direction = Vector3(0, 1, 0)
	dm.spread = 50.0
	dm.initial_velocity_min = 0.6
	dm.initial_velocity_max = 1.5
	dm.gravity = Vector3(0, -9.0, 0)
	_drops.process_material = dm
	var fleck := QuadMesh.new()
	fleck.size = Vector2(0.02, 0.02)
	var fm := StandardMaterial3D.new()
	fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fm.albedo_color = Color(0.80, 0.84, 0.88, 0.30)
	fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	fleck.material = fm
	_drops.draw_pass_1 = fleck
	_drops.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_drops.emitting = false
	add_child(_drops)


## A flag on every flagpole in the map: one strip of cloth, drawn once for each pole, put in the wind by its shader.
func _setup_flags() -> void:
	var at := []
	for key in world.props.cells:
		for rec in world.props.cells[key]:
			if rec[0] == world.props.FLAGPOLE:
				var xf: Transform3D = rec[1]
				at.append(xf.origin + Vector3(0, 8.95 * xf.basis.y.length(), 0))
	if at.is_empty():
		return
	var cloth := PlaneMesh.new()
	cloth.size = Vector2(1.0, 1.0)
	cloth.subdivide_width = 14
	cloth.subdivide_depth = 3
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flag.gdshader")
	cloth.material = mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = cloth
	mm.instance_count = at.size()
	for i in at.size():
		mm.set_instance_transform(i, Transform3D(Basis(), at[i]))
	var mi := MultiMeshInstance3D.new()
	mi.name = "Flags"
	mi.multimesh = mm
	mi.custom_aabb = AABB(Vector3(world.x0, -10, world.z0), Vector3(world.x1 - world.x0, 900, world.z1 - world.z0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	flags = at.size()


func _process(delta: float) -> void:
	var t0_ := Time.get_ticks_usec()
	_run(delta)
	if world != null:
		world.took("weather", t0_)


func _run(delta: float) -> void:
	# changing by itself
	if changing:
		_next_in -= delta
		if _next_in <= 0.0:
			_next_in = _rng.randf_range(180.0, 480.0)
			var choices: Array = NEXT[kind]
			set_weather(choices[_rng.randi_range(0, choices.size() - 1)], 50.0)
	if _turn < 1.0:
		_turn = minf(1.0, _turn + delta / _turn_time)
		var t := smoothstep(0.0, 1.0, _turn)
		for key in now:
			now[key] = lerpf(_from[key], SET[kind][key], t)
	_apply(delta)


var _breath: CPUParticles3D
var _breath_t := 1.0


## Breath in the cold: a small white puff from the walker's mouth every few seconds, faster when winded.
func _breathe(delta: float) -> void:
	if not winter or indoors or player.driving or player.under_water or player.swimming:
		return
	_breath_t -= delta
	if _breath_t > 0.0:
		return
	_breath_t = 1.2 if player.stamina < 0.6 else 3.4
	if _breath == null:
		_breath = CPUParticles3D.new()
		_breath.one_shot = true
		_breath.emitting = false
		_breath.amount = 7
		_breath.lifetime = 1.5
		_breath.explosiveness = 0.75
		_breath.local_coords = false
		_breath.spread = 16.0
		_breath.gravity = Vector3(0, 0.12, 0)
		_breath.initial_velocity_min = 0.25
		_breath.initial_velocity_max = 0.5
		_breath.damping_min = 0.5
		_breath.damping_max = 0.8
		_breath.scale_amount_min = 0.5
		_breath.scale_amount_max = 1.0
		var grow := Curve.new()
		grow.add_point(Vector2(0.0, 0.25))
		grow.add_point(Vector2(1.0, 1.0))
		_breath.scale_amount_curve = grow
		var fade := Gradient.new()
		fade.set_color(0, Color(1, 1, 1, 0.08))
		fade.set_color(1, Color(1, 1, 1, 0.0))
		_breath.color_ramp = fade
		var q := QuadMesh.new()
		q.size = Vector2(0.15, 0.15)
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
		m.vertex_color_use_as_albedo = true
		m.albedo_texture = _puff_texture()
		q.material = m
		_breath.mesh = q
		add_child(_breath)
	var ahead := Vector3(-sin(player.rotation.y), 0.0, -cos(player.rotation.y))
	var head: Node3D = player.get("_head")
	var at: Vector3 = head.global_position if head != null else player.global_position + Vector3(0, 1.62, 0)
	if head != null:
		ahead = -head.global_transform.basis.z
		ahead.y = 0.0
		ahead = ahead.normalized()
	_breath.global_position = at + ahead * 0.14 + Vector3(0, -0.04, 0)
	_breath.direction = ahead + Vector3(0, 0.15, 0)
	_breath.restart()


func _puff_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(0.5, 0.0)
	t.width = 32
	t.height = 32
	return t


func _apply(delta: float) -> void:
	var rain: float = now["rain"]
	# wet in under a minute of heavy rain, dry again in a few
	if rain > 0.02 and not winter:
		wetness = minf(1.0, wetness + delta * (0.012 + 0.03 * rain))
	else:
		wetness = maxf(0.0, wetness - delta / 200.0)
	# the wind, in gusts
	_gust += delta
	var base: float = wind_set if wind_set >= 0.0 else float(now["wind"])
	wind = clampf(base * (0.75 + 0.35 * sin(_gust * 0.37) + 0.2 * sin(_gust * 1.13 + 1.0)), 0.0, 1.0)
	RenderingServer.global_shader_parameter_set("wetness", wetness)
	# the season (the menu sets `winter`): the snow comes and goes over a few seconds, not at a stroke
	snow = move_toward(snow, 1.0 if winter else 0.0, delta / 4.0)
	RenderingServer.global_shader_parameter_set("snow", snow)
	_breathe(delta)
	RenderingServer.global_shader_parameter_set("wind", Vector3(wind_dir.x, wind_dir.y, wind))
	RenderingServer.global_shader_parameter_set("cloud_down", float(now["cloud"]))
	if daytime != null:
		daytime.cover = now["cover"]
		daytime.gloom = now["gloom"]
		daytime.haze = now["haze"]
		daytime.cloud = now["cloud"]
	if player.sound != null:
		player.sound.rain = rain
		player.sound.gale = wind
	# the rain itself, around the camera
	var cam := get_viewport().get_camera_3d()
	if cam != null and _rain != null:
		var on := rain > 0.02 and not indoors
		_rain.emitting = on
		_drops.emitting = on and not player.under_water and not winter
		if on:
			_rain.amount_ratio = clampf(0.15 + 0.85 * rain, 0.0, 1.0)
			_drops.amount_ratio = clampf(0.2 + 0.8 * rain, 0.0, 1.0)
			var slant := Vector3(wind_dir.x, 0, wind_dir.y) * wind * 6.0
			_rain.global_position = cam.global_position + Vector3(0, 9.0, 0) - slant * 0.5 + (-cam.global_transform.basis.z * Vector3(1, 0, 1)) * 6.0
			(_rain.process_material as ParticleProcessMaterial).direction = (Vector3(0, -17.0 if not winter else -2.0, 0) + slant * (0.25 if winter else 1.0)).normalized()
			var pp: Vector3 = player.global_position
			_drops.global_position = Vector3(pp.x, pp.y + 0.03, pp.z)
			# rings on the water near the player
			for i in int(1.0 + 3.0 * rain):
				var q := Vector2(pp.x, pp.z) + Vector2(_rng.randf_range(-28.0, 28.0), _rng.randf_range(-28.0, 28.0))
				world.ripples.push(q, 0.35, 0.012 + 0.012 * rain, 0.0)
	# what is wet looks it: darker and shinier
	_mats_tick -= delta
	if _mats_tick <= 0.0:
		_mats_tick = 0.25
		_wet_materials()
	_puddle_tick -= delta
	if _puddle_tick <= 0.0:
		_puddle_tick = 1.0
		_lay_puddles()
	_puddle_mat.albedo_color.a = 0.78 * smoothstep(0.45, 0.95, wetness)


func _wet_materials() -> void:
	if world.detail == null or world.detail.fac == null:
		return
	var mats: Dictionary = world.detail.fac.mats
	for pair in [["asphalt", 0.9, 0.42, 0.68], ["sidewalk", 0.9, 0.5, 0.7], ["path", 0.95, 0.6, 0.7], ["roof", 0.85, 0.45, 0.7], ["tiles", 0.8, 0.35, 0.72],
			["sheet", 0.45, 0.2, 0.8], ["clad", 0.85, 0.7, 0.9], ["cladv", 0.85, 0.7, 0.9], ["plaster", 0.92, 0.75, 0.88]]:
		var m = mats.get(pair[0])
		if m is StandardMaterial3D:
			m.roughness = lerpf(pair[1], pair[2], wetness)
			var dark: float = lerpf(1.0, pair[3], wetness)
			m.albedo_color = Color(dark, dark, dark)


## Puddles: where the asphalt has a hollow (a corner of its 2.5 m squares lower than all the corners around
## it), water stands when it has rained a while. Worked out once for each cell of paving near the player.
func _lay_puddles() -> void:
	if wetness < 0.4:
		for key in _puddles.keys():
			_puddles[key].queue_free()
		_puddles.clear()
		return
	var pos: Vector3 = player.global_position
	var c: Vector2i = world.detail.cell_of(pos.x, pos.z)
	for key in _puddles.keys():
		if absi(key.x - c.x) > 2 or absi(key.y - c.y) > 2:
			_puddles[key].queue_free()
			_puddles.erase(key)
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var key := Vector2i(c.x + dx, c.y + dz)
			if _puddles.has(key) or not world.detail.paved.has(key):
				continue
			_puddles[key] = _puddles_of(key)
			add_child(_puddles[key])
			return                                              # one cell a second is plenty


func _puddles_of(key: Vector2i) -> MultiMeshInstance3D:
	var arr: PackedFloat32Array = world.detail.paved[key][0]
	var low := {}                                           # corner of a 2.5 m square -> height of the asphalt there
	var i := 0
	while i + 3 <= arr.size():
		var gx := arr[i] / 2.5
		var gz := arr[i + 2] / 2.5
		if absf(gx - roundf(gx)) < 0.01 and absf(gz - roundf(gz)) < 0.01:
			low[Vector2i(int(roundf(gx)), int(roundf(gz)))] = arr[i + 1]
		i += 3
	var spots := []
	for g in low:
		var y: float = low[g]
		if y < 0.7:
			continue
		var n := 0
		var is_low := true
		var rim := 1e9
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var q = low.get(g + o)
			if q != null:
				n += 1
				rim = minf(rim, q)
				if q <= y + 0.004:
					is_low = false
		if is_low and n == 8:
			spots.append([Vector3(g.x * 2.5, y + 0.108, g.y * 2.5), clampf(0.5 + (rim - y) * 14.0, 0.5, 1.7)])
	var disc := CylinderMesh.new()
	disc.top_radius = 1.0
	disc.bottom_radius = 1.0
	disc.height = 0.002
	disc.radial_segments = 14
	disc.rings = 0
	disc.cap_bottom = false
	disc.material = _puddle_mat
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = disc
	mm.instance_count = spots.size()
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	for k in spots.size():
		var r: float = spots[k][1]
		var b := Basis(Vector3.UP, rng.randf() * TAU) * Basis.from_scale(Vector3(r * rng.randf_range(0.8, 1.3), 1.0, r * rng.randf_range(0.7, 1.1)))
		mm.set_instance_transform(k, Transform3D(b, spots[k][0]))
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi
