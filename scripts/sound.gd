extends Node
## The game's sound. Looped background layers that fade in and out by where the player is (waves by the fjord,
## a hum of traffic in town, wind and birds in the forest, a river's rush by running water, rain); footsteps
## that follow the walk and change with the ground; an engine for each vehicle, pitched by its speed; and
## one-shot sounds at a place in the world, with a cap on how many play at once.
##
## Every sound is made by tools/make_sounds.py (sounds/*.ogg, sounds/CREDITS.md). They are read straight from
## the files, so nothing has to be imported first. M mutes.

const DIR := "res://sounds/"
const VOICES := 12                       # one-shots at a time; a new one takes the place of the oldest

var world
var player
var volume := 0.8: set = set_volume
var muted := false: set = set_muted
var rain := 0.0                          # set by the weather (scripts/weather.gd): 0 dry to 1 pouring
var gale := 0.0                          # and how hard it blows, 0 to 1
var night := 0.0                         # set by the clock: birds are quiet at night
var levels := {}                         # what each background layer is at (for the checks)
var played := {}                         # how many times each one-shot has been played (for the checks)

var _streams := {}
var _loops := {}                         # name -> AudioStreamPlayer
var _voices: Array = []
var _next_voice := 0
var _sense := 0.0
var _place := {"surf": 0.0, "sea": 0.0, "town": 0.0, "forest": 0.0, "river": 0.0, "sea_dir": Vector2.ZERO}
var _gull_in := 5.0
var _bird_in := 3.0
var _step_at := 0.0
var _was_driving := false
var _was_air := 0.0
var _stroke_up := false
var _rng := RandomNumberGenerator.new()


func setup(w, p) -> void:
	world = w
	player = p
	for name in ["sea", "town", "wind", "river", "rain", "engine", "roll", "skid", "rotor", "freewheel", "chain"]:
		var pl := AudioStreamPlayer.new()
		pl.volume_db = -80.0
		add_child(pl)
		_loops[name] = pl
		if name != "engine":
			pl.stream = _stream(name, true)
			pl.play()
	for i in VOICES:
		var v := AudioStreamPlayer3D.new()
		v.unit_size = 6.0
		v.max_distance = 220.0
		v.attenuation_filter_cutoff_hz = 20500.0
		add_child(v)
		_voices.append(v)
	set_volume(volume)


func _stream(name: String, loop := false) -> AudioStream:
	if not _streams.has(name):
		var s := AudioStreamOggVorbis.load_from_file(DIR + name + ".ogg")
		if s != null:
			s.loop = loop
		_streams[name] = s
	return _streams[name]


func set_volume(v: float) -> void:
	volume = clampf(v, 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.0001)))


func set_muted(m: bool) -> void:
	muted = m
	AudioServer.set_bus_mute(0, m)


## A sound at a place in the world. `loudness` 0 to 1, `pitch` 1 is as made; a little chance in both.
func play_at(name: String, at: Vector3, loudness := 1.0, pitch := 1.0) -> void:
	var s := _stream(name)
	if s == null:
		return
	var v: AudioStreamPlayer3D = _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	v.stream = s
	v.global_position = at
	v.volume_db = linear_to_db(clampf(loudness, 0.01, 2.0)) + _rng.randf_range(-1.5, 0.5)
	v.pitch_scale = pitch * _rng.randf_range(0.94, 1.06)
	v.play()
	played[name] = int(played.get(name, 0)) + 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("mute"):
		set_muted(not muted)


func _set_loop(name: String, level: float, delta: float, pitch := 1.0) -> void:
	var pl: AudioStreamPlayer = _loops[name]
	var now := db_to_linear(pl.volume_db)
	now = move_toward(now, clampf(level, 0.0, 1.0), delta * 0.8)
	pl.volume_db = linear_to_db(maxf(now, 0.0001))
	pl.pitch_scale = clampf(pitch, 0.3, 3.5)
	pl.stream_paused = now < 0.0005 and level < 0.0005
	levels[name] = snappedf(now, 0.01)


func _process(delta: float) -> void:
	if player == null:
		return
	var pos: Vector3 = player.global_position
	_sense -= delta
	if _sense <= 0.0:
		_sense = 0.4
		_look_around(pos)
	var sea: float = _place["sea"]
	var forest: float = _place["forest"]
	var high := clampf(pos.y / 400.0, 0.0, 1.0)
	_set_loop("sea", 0.35 * float(_place["surf"]), delta)        # (quiet, and only at the water's edge: note of 17 Nov)
	_set_loop("town", 0.45 * float(_place["town"]) * (1.0 - 0.5 * forest), delta)
	_set_loop("wind", clampf(0.10 + 0.22 * forest + 0.3 * high + 0.7 * gale, 0.0, 1.0), delta, 0.85 + 0.4 * gale)
	_set_loop("river", 0.8 * float(_place["river"]), delta)
	_set_loop("rain", 0.9 * rain, delta, 0.9 + 0.25 * rain)

	# gulls over the fjord, small birds in the trees (not at night, not in rain)
	_gull_in -= delta
	if _gull_in <= 0.0:
		_gull_in = _rng.randf_range(5.0, 18.0)
		if sea > 0.25 and night < 0.7:
			var d: Vector2 = _place["sea_dir"]
			var off := Vector3(d.x, 0, d.y).rotated(Vector3.UP, _rng.randf_range(-0.9, 0.9)) * _rng.randf_range(25.0, 80.0)
			play_at("gull%d" % _rng.randi_range(1, 3), pos + off + Vector3(0, _rng.randf_range(8.0, 25.0), 0), 0.9 * sea)
	_bird_in -= delta
	if _bird_in <= 0.0:
		_bird_in = _rng.randf_range(2.0, 8.0)
		if forest > 0.25 and night < 0.5 and rain < 0.4:
			var a := _rng.randf() * TAU
			play_at("bird%d" % _rng.randi_range(1, 4), pos + Vector3(cos(a), 0.4, sin(a)) * _rng.randf_range(8.0, 30.0), 0.5 * forest)

	_feet(pos)
	_vehicle(delta, pos)
	_swimmer(pos)


## What is around the player: how near the sea is, how built up it is, how wooded, how near running water.
func _look_around(pos: Vector3) -> void:
	var sea_d := 1e9
	var sea_dir := Vector2.ZERO
	var river_d := 1e9
	for k in 12:
		var d := Vector2(cos(k * TAU / 12.0), sin(k * TAU / 12.0))
		for r in [3.0, 6.0, 10.0, 12.0, 35.0, 80.0, 160.0, 320.0]:
			if r < sea_d and world.height_at(pos.x + d.x * r, pos.z + d.y * r) < world.SEA_BED:
				sea_d = r
				sea_dir = d
		for r in [3.0, 9.0, 20.0, 38.0]:
			if r < river_d:
				var w: Dictionary = world.water_at(pos.x + d.x * r, pos.z + d.y * r)
				if not w.is_empty() and w["flow"].length() > 0.25:
					river_d = r
	var here: Dictionary = world.water_at(pos.x, pos.z)
	if not here.is_empty():
		if here["flow"].length() > 0.25:
			river_d = 0.0
		elif here["level"] == 0.0:
			sea_d = 0.0
	_place["sea"] = pow(clampf(1.0 - sea_d / 340.0, 0.0, 1.0), 1.6)      # how near the fjord is (gulls)
	_place["surf"] = clampf(1.0 - (sea_d - 3.0) / 7.0, 0.0, 1.0)         # the water itself is heard within 10 m of it
	_place["sea_dir"] = sea_dir
	_place["river"] = clampf(1.0 - river_d / 42.0, 0.0, 1.0)
	var c: Vector2i = world.detail.cell_of(pos.x, pos.z)
	var houses := 0
	for dz in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			houses += (world.detail.buildings.get(Vector2i(c.x + dx, c.y + dz), []) as Array).size()
	_place["town"] = clampf(houses / 70.0, 0.0, 1.0)
	var trees := 0.0
	for k in 8:
		var q := Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0)) * 22.0
		trees += world.cover_at(pos.x + q.x, pos.z + q.y)["trees"]
	trees += world.cover_at(pos.x, pos.z)["trees"]
	_place["forest"] = clampf(trees / 9.0 * 1.5, 0.0, 1.0)
	levels["place"] = {"sea": snappedf(_place["sea"], 0.01), "town": snappedf(_place["town"], 0.01), "forest": snappedf(_place["forest"], 0.01), "river": snappedf(_place["river"], 0.01)}


## What the walker stands on: asphalt, slab (sidewalks and squares), wood (quays, piers, bridges), gravel,
## grass, or water (wading).
func ground_kind(pos: Vector3) -> String:
	if player.wading > 0.08:
		return "water"
	var ground: float = world.height_at(pos.x, pos.z)
	if not is_nan(world.detail.surface_at(pos.x, pos.z)) and pos.y - ground < 0.45:
		return "asphalt"
	if pos.y - ground > 0.7:
		return "wood"
	if pos.y - ground > 0.14:
		return "slab"
	var c: Dictionary = world.cover_at(pos.x, pos.z)
	if c["road"] > 0.3 and c["road"] < 0.8:
		return "slab"                                       # paving laid on the ground: a square, a yard
	if c["road"] >= 0.8 and float(_place["town"]) > 0.35:
		return "slab"                                       # the ground itself is the surface, in town: a paved square
	if c["path"] > 0.4 or c["road"] >= 0.8 or c["rock"] > 0.5:
		return "gravel"
	return "grass"


func _feet(pos: Vector3) -> void:
	if player.driving or player.swimming or not (player.is_on_floor() or player.wading > 0.08):
		_step_at = floor(player._phase / PI)
		return
	var at: float = floor(player._phase / PI)                   # the walk cycle: a foot comes down every half turn
	if at != _step_at:
		_step_at = at
		var speed := Vector2(player.velocity.x, player.velocity.z).length()
		if speed > 0.6:
			play_at("step_%s%d" % [ground_kind(pos), _rng.randi_range(1, 3)], pos + Vector3(0, 0.1, 0), 0.35 + 0.05 * speed, 0.95 + 0.02 * speed)


func _vehicle(delta: float, pos: Vector3) -> void:
	var driving: bool = player.driving
	if driving != _was_driving:
		_was_driving = driving
		if player.atv != null and player.atv.name in ["Volvo", "Integra", "Mercedes", "Helicopter"]:
			play_at("door", pos + Vector3(0, 0.8, 0), 0.7)
	var engine: AudioStreamPlayer = _loops["engine"]
	var e_level := 0.0
	var e_pitch := 1.0
	var roll := 0.0
	var skid := 0.0
	var rotor := 0.0
	var rotor_pitch := 1.0
	var free := 0.0
	var chain := 0.0
	var speed := absf(player._drive_speed)
	if driving and player.atv != null:
		var name: String = player.atv.name
		var fast: float = maxf(float(player._spec.get("fast", 30.0)), 1.0)
		if name == "Helicopter":
			var r: float = player.atv.rotor
			rotor = 0.15 + 0.85 * r if r > 0.01 else 0.0
			rotor_pitch = 0.45 + 0.6 * r
		elif name == "Bicycle":
			var pedalling: bool = player.atv.get("_pedalling") == true
			chain = 0.5 if pedalling else 0.0
			free = clampf(speed / 6.0, 0.0, 0.6) if not pedalling and speed > 0.8 else 0.0
			roll = clampf(speed / 14.0, 0.0, 0.35)
		else:
			var key := "engine_" + ("atv" if name == "ATV" else name.to_lower())
			var s := _stream(key, true)
			if engine.stream != s:
				engine.stream = s
				engine.play()
			var throttle := Input.get_action_strength("move_forward") + Input.get_action_strength("move_back")
			e_level = 0.30 + 0.25 * throttle + 0.25 * speed / fast
			# through the gears: the pitch climbs with speed, dropping back a little at each change
			var gear := speed / fast * 4.0
			e_pitch = 0.8 + 0.55 * fposmod(gear, 1.0) + 0.28 * floor(gear) + 0.15 * throttle
			roll = clampf(speed / 30.0, 0.0, 0.7) if player.wheels_down() else 0.0
			skid = 0.6 if player.atv.get("_smoking") == true else 0.0
		# a landing
		if _was_air > 0.35 and player._air_time == 0.0 and speed > 3.0:
			play_at("thump", pos, clampf(_was_air * 1.2, 0.4, 1.4))
		_was_air = player._air_time
	_set_loop("engine", e_level, delta * 3.0, e_pitch)
	_set_loop("roll", roll, delta * 3.0, 0.7 + speed / 40.0)
	_set_loop("skid", skid, delta * 6.0, 0.9 + speed / 80.0)
	_set_loop("rotor", rotor, delta * 2.0, rotor_pitch)
	_set_loop("freewheel", free, delta * 5.0, 0.5 + speed / 9.0)
	_set_loop("chain", chain, delta * 5.0, 0.8 + speed / 20.0)


func _swimmer(pos: Vector3) -> void:
	if not player.swimming:
		_stroke_up = false
		return
	var up: bool = sin(player._stroke) > 0.9
	if up and not _stroke_up and Vector2(player.velocity.x, player.velocity.z).length() > 0.5:
		play_at("stroke2" if player.crawling else "stroke1", pos + Vector3(0, 1.2, 0), 0.5 if player.crawling else 0.35)
	_stroke_up = up
