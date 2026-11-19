extends CanvasLayer
## The in-game menu. Esc opens and closes it (a click beside it closes it too); the game keeps running behind
## it, so the time and the weather can be watched as they are changed.
##
## - A clock face for the time of day: 24 hours round, noon at the top. Drag the hand to set the time (the
##   light, the sky, the lamps and the windows follow as it turns; past midnight is the next day); the wheel
##   steps a quarter of an hour. Under it, how fast time runs: stopped, normal (a day in 40 minutes), fast (4).
## - A button for each weather, and one that lets it change by itself; a slider for the wind.
## - Settings: volume and mute, traffic, grass, ripples on the water. Kept between visits in user://settings.cfg,
##   with the time and the weather as they were left.
## - Reset (F5 outside the menu): asks first, then puts the player back on Rådhusplassen and every vehicle
##   back where it starts (main.gd, reset_game).

const FILE := "user://settings.cfg"
const PANEL_W := 560.0

var main
var world
var player
var daytime
var weather
var sound
var is_open := false
var traffic := 2                         # 0 none, 1 little, 2 normal (part 10 reads it)
var grass := 2                           # 0 none, 1 some, 2 full (part 12 reads it)

var _root: Control
var _panel: Panel
var _dial: Control
var _time_label: Label
var _rate_buttons: Array = []
var _weather_buttons := {}
var _wind: HSlider
var _wind_auto: Button
var _volume: HSlider
var _mute: CheckBox
var _ripples: CheckBox
var _traffic_buttons: Array = []
var _grass_buttons: Array = []
var _confirm: Panel
var _season_buttons: Array = []
var _occasion_buttons: Array = []
var _slippery: CheckBox
var occasion := 0                        # 0 an ordinary day, 1 the jazz festival, 2 a match at the stadium


func _apply_occasion() -> void:
	if occasion == 1:
		daytime.day = 198                                   # the middle of the festival week in July
	elif daytime.day >= 196 and daytime.day <= 202:
		daytime.day = 258
	main.molde.match_day = occasion == 2
	daytime.apply()
var _dragging := false
var _drag_last := 0.0
var _save_in := -1.0
var _was_captured := false


class Dial:
	extends Control
	var menu

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 16.0
		var font := get_theme_default_font()
		# the rim: light for the hours the sun is up on this date, dark for the night
		for i in 96:
			var h := i * 0.25
			var up: bool = menu.daytime.sun_at(h + 0.125, menu.daytime.day).x > -0.8
			var a0: float = menu.angle_of(h)
			var a1: float = menu.angle_of(h + 0.25)
			draw_arc(c, r, a0, a1 + 0.004, 4, Color(0.95, 0.80, 0.45, 0.9) if up else Color(0.22, 0.27, 0.42, 0.9), 7.0, true)
		draw_circle(c, r - 5.0, Color(0.05, 0.06, 0.07, 0.72))
		for h in 24:
			var a: float = menu.angle_of(float(h))
			var d := Vector2(cos(a), sin(a))
			var big := h % 6 == 0
			draw_line(c + d * (r - (16.0 if big else 10.0)), c + d * (r - 6.0), Color(1, 1, 1, 0.85 if big else 0.4), 2.0 if big else 1.0, true)
			if h % 3 == 0:
				var txt := "%d" % h
				var fs := 15 if big else 12
				var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
				draw_string(font, c + d * (r - 30.0) - Vector2(ts.x * 0.5, -ts.y * 0.3), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.9 if big else 0.55))
		# the hand, with the sun at its tip by day; the moon stands across from it
		var a: float = menu.angle_of(menu.daytime.hours)
		var d := Vector2(cos(a), sin(a))
		draw_line(c, c + d * (r - 34.0), Color(1.0, 0.86, 0.55), 3.0, true)
		draw_circle(c, 5.0, Color(1.0, 0.86, 0.55))
		var night: float = menu.daytime.night
		draw_circle(c + d * (r + 1.0), 9.0, Color(1.0, 0.85, 0.35).lerp(Color(0.55, 0.45, 0.35), night))
		for k in 8:
			var q := Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0))
			draw_line(c + d * (r + 1.0) + q * 11.0, c + d * (r + 1.0) + q * 15.0, Color(1.0, 0.85, 0.35, 1.0 - night), 1.5, true)
		var m := c - d * (r + 1.0)
		draw_circle(m, 7.0, Color(0.80, 0.84, 0.95, 0.35 + 0.65 * night))
		draw_circle(m + Vector2(3.5, -2.0), 6.0, Color(0.22, 0.27, 0.42))


class Sign:
	extends Control
	var kind := ""

	func _draw() -> void:
		var c := size * 0.5
		var sun := Color(1.0, 0.85, 0.35)
		var cloud := Color(0.86, 0.88, 0.90)
		var rain := Color(0.60, 0.78, 0.95)
		if kind == "clear":
			draw_circle(c, 7.0, sun)
			for k in 8:
				var q := Vector2(cos(k * TAU / 8.0), sin(k * TAU / 8.0))
				draw_line(c + q * 9.5, c + q * 13.0, sun, 1.5, true)
		elif kind == "changing":
			draw_arc(c, 9.0, 0.6, TAU - 0.6, 20, cloud, 2.0, true)
			draw_colored_polygon(PackedVector2Array([c + Vector2(9, -9), c + Vector2(13, -1), c + Vector2(4, -3)]), cloud)
		else:
			var low := 5.0 if kind == "low cloud" else 0.0
			if kind == "cloudy":
				draw_circle(c + Vector2(7, -6), 5.0, sun)
			for q in [Vector2(-7, 0), Vector2(0, -4), Vector2(7, 0), Vector2(0, 1)]:
				draw_circle(c + q + Vector2(0, low - 2.0), 6.0, cloud)
			if kind == "low cloud":
				draw_line(c + Vector2(-13, 12), c + Vector2(13, 12), Color(0.7, 0.72, 0.74), 2.0)
			var n := 3 if kind == "rain" else (5 if kind == "heavy rain" else 0)
			for k in n:
				var x := -10.0 + 20.0 * (k + 0.5) / n
				draw_line(c + Vector2(x, 7), c + Vector2(x - 3, 14), rain, 1.6, true)


## Where an hour sits on the dial, as an angle for drawing: noon at the top, going round clockwise.
func angle_of(h: float) -> float:
	return (h - 12.0) / 24.0 * TAU - PI * 0.5


func setup(m, w, p, d, wt, s) -> void:
	main = m
	world = w
	player = p
	daytime = d
	weather = wt
	sound = s
	layer = 20
	_build()
	_load()
	_root.visible = false


func _label(text: String, size := 15, alpha := 0.9) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", Color(1, 1, 1, alpha))
	return l


func _button(text: String, min_w := 0.0) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = false
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_size_override("font_size", 14)
	b.custom_minimum_size = Vector2(min_w, 34)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(1, 1, 1, 0.07 if state == "normal" else (0.14 if state == "hover" else 0.22))
		sb.set_corner_radius_all(5)
		sb.set_content_margin_all(7)
		b.add_theme_stylebox_override(state, sb)
	return b


func _light(b: Button, on: bool) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.95, 0.80, 0.45, 0.85) if on else Color(1, 1, 1, 0.07)
	sb.set_corner_radius_all(5)
	sb.set_content_margin_all(7)
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_color_override("font_color", Color(0.08, 0.08, 0.08) if on else Color(1, 1, 1, 0.9))
	b.add_theme_color_override("font_hover_color", Color(0.08, 0.08, 0.08) if on else Color(1, 1, 1, 1))


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			close())                                   # a click beside the panel
	add_child(_root)
	_panel = Panel.new()
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.04, 0.05, 0.06, 0.80)
	back.set_corner_radius_all(10)
	back.border_color = Color(1, 1, 1, 0.10)
	back.set_border_width_all(1)
	_panel.add_theme_stylebox_override("panel", back)
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	box.position = Vector2(22, 16)
	box.custom_minimum_size = Vector2(PANEL_W - 44.0, 0)
	_panel.add_child(box)
	_panel.set_meta("box", box)

	var head := HBoxContainer.new()
	head.add_child(_label("Molde", 22, 0.95))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(sp)
	head.add_child(_label("Esc  close", 13, 0.5))
	box.add_child(head)

	# the clock
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	box.add_child(row)
	_dial = Dial.new()
	_dial.menu = self
	_dial.custom_minimum_size = Vector2(230, 230)
	_dial.mouse_filter = Control.MOUSE_FILTER_STOP
	_dial.gui_input.connect(_on_dial)
	row.add_child(_dial)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(side)
	side.add_child(_label("Time of day", 13, 0.55))
	_time_label = _label("17:00", 40, 1.0)
	side.add_child(_time_label)
	side.add_child(_label("Drag the hand round. The wheel steps a quarter of an hour.", 12, 0.5))
	var rates := HBoxContainer.new()
	rates.add_theme_constant_override("separation", 6)
	for pair in [["Stopped", 0.0], ["Normal", 1.0], ["Fast", 10.0]]:
		var b := _button(pair[0], 78)
		b.pressed.connect(func():
			daytime.rate = pair[1]
			_later())
		b.set_meta("rate", pair[1])
		rates.add_child(b)
		_rate_buttons.append(b)
	side.add_child(rates)
	side.add_child(_label("Normal: a day in 40 minutes. Fast: in 4.", 12, 0.5))

	# the weather
	box.add_child(_label("Weather", 13, 0.55))
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 6)
	box.add_child(wrow)
	for k in weather.KINDS + ["changing"]:
		var b := _button("", 80)
		b.custom_minimum_size = Vector2(80, 62)
		var sign := Sign.new()
		sign.kind = k
		sign.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sign.position = Vector2(0, 4)
		sign.size = Vector2(80, 34)
		b.add_child(sign)
		var name := _label(k.capitalize(), 12, 0.9)
		name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name.position = Vector2(0, 40)
		name.size = Vector2(80, 18)
		b.add_child(name)
		b.set_meta("name_label", name)
		b.pressed.connect(func():
			if k == "changing":
				weather.changing = true
			else:
				weather.changing = false
				weather.set_weather(k, 6.0)
			_later())
		wrow.add_child(b)
		_weather_buttons[k] = b
	var wind_row := HBoxContainer.new()
	wind_row.add_theme_constant_override("separation", 10)
	box.add_child(wind_row)
	wind_row.add_child(_label("Wind", 14, 0.85))
	wind_row.add_child(_label("calm", 12, 0.5))
	_wind = HSlider.new()
	_wind.min_value = 0.0
	_wind.max_value = 1.0
	_wind.step = 0.01
	_wind.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_wind.focus_mode = Control.FOCUS_NONE
	_wind.value_changed.connect(func(v):
		if not _wind.has_meta("quiet"):
			weather.wind_set = v
			_later())
	wind_row.add_child(_wind)
	wind_row.add_child(_label("storm", 12, 0.5))
	_wind_auto = _button("As the weather", 120)
	_wind_auto.pressed.connect(func():
		weather.wind_set = -1.0
		_later())
	wind_row.add_child(_wind_auto)

	# settings
	box.add_child(_label("Settings", 13, 0.55))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 8)
	box.add_child(grid)
	grid.add_child(_label("Sound", 14, 0.85))
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	_volume = HSlider.new()
	_volume.min_value = 0.0
	_volume.max_value = 1.0
	_volume.step = 0.01
	_volume.custom_minimum_size = Vector2(220, 0)
	_volume.focus_mode = Control.FOCUS_NONE
	_volume.value_changed.connect(func(v):
		sound.volume = v
		_later())
	srow.add_child(_volume)
	_mute = CheckBox.new()
	_mute.text = "Mute (M)"
	_mute.focus_mode = Control.FOCUS_NONE
	_mute.toggled.connect(func(on):
		sound.muted = on
		_later())
	srow.add_child(_mute)
	grid.add_child(srow)
	grid.add_child(_label("Traffic", 14, 0.85))
	var trow := HBoxContainer.new()
	trow.add_theme_constant_override("separation", 6)
	for i in 3:
		var b := _button(["None", "Little", "Normal"][i], 74)
		b.pressed.connect(func():
			traffic = i
			main.traffic.amount = i
			_later())
		trow.add_child(b)
		_traffic_buttons.append(b)
	grid.add_child(trow)
	grid.add_child(_label("Grass", 14, 0.85))
	var grow := HBoxContainer.new()
	grow.add_theme_constant_override("separation", 6)
	for i in 3:
		var b := _button(["None", "Some", "Full"][i], 74)
		b.pressed.connect(func():
			grass = i
			main.grass.amount = i
			_later())
		grow.add_child(b)
		_grass_buttons.append(b)
	grid.add_child(grow)
	grid.add_child(_label("Water", 14, 0.85))
	_ripples = CheckBox.new()
	_ripples.text = "Ripples and wakes"
	_ripples.focus_mode = Control.FOCUS_NONE
	_ripples.toggled.connect(func(on):
		world.ripples.enabled = on
		_later())
	grid.add_child(_ripples)
	# the season and the occasion (the plan of 18 November, part 6)
	grid.add_child(_label("Season", 14, 0.85))
	var zrow := HBoxContainer.new()
	zrow.add_theme_constant_override("separation", 6)
	for i in 2:
		var b := _button(["Summer", "Winter"][i], 74)
		b.pressed.connect(func():
			weather.winter = i == 1
			_later())
		zrow.add_child(b)
		_season_buttons.append(b)
	_slippery = CheckBox.new()
	_slippery.text = "Slippery roads"
	_slippery.focus_mode = Control.FOCUS_NONE
	_slippery.toggled.connect(func(on):
		weather.slippery = on
		_later())
	zrow.add_child(_slippery)
	grid.add_child(zrow)
	grid.add_child(_label("Today is", 14, 0.85))
	var orow := HBoxContainer.new()
	orow.add_theme_constant_override("separation", 6)
	for i in 3:
		var b := _button(["An ordinary day", "Moldejazz", "A match day"][i], 74)
		b.pressed.connect(func():
			occasion = i
			_apply_occasion()
			_later())
		orow.add_child(b)
		_occasion_buttons.append(b)
	grid.add_child(orow)
	grid.add_child(_label("To do", 14, 0.85))
	var jb := _button("Jobs and sights  (J)", 170)
	jb.pressed.connect(func():
		close()
		main.jobs.toggle_journal())
	grid.add_child(jb)

	# reset
	var foot := HBoxContainer.new()
	var gap := Control.new()
	gap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(gap)
	var reset := _button("Reset  (F5)", 130)
	reset.pressed.connect(ask_reset)
	foot.add_child(reset)
	box.add_child(foot)

	# "Start again at Rådhusplassen?"
	_confirm = Panel.new()
	var cb := StyleBoxFlat.new()
	cb.bg_color = Color(0.04, 0.05, 0.06, 0.94)
	cb.set_corner_radius_all(10)
	cb.border_color = Color(0.95, 0.80, 0.45, 0.6)
	cb.set_border_width_all(1)
	_confirm.add_theme_stylebox_override("panel", cb)
	_confirm.size = Vector2(400, 150)
	_confirm.visible = false
	_root.add_child(_confirm)
	var q := _label("Start again at Rådhusplassen?", 19, 1.0)
	q.position = Vector2(26, 22)
	_confirm.add_child(q)
	var note := _label("You and every vehicle go back to where the game starts.\nThe time, the weather and the settings stay as they are.", 12, 0.6)
	note.position = Vector2(26, 54)
	_confirm.add_child(note)
	var yes := _button("Yes", 100)
	yes.position = Vector2(150, 100)
	yes.pressed.connect(func():
		_confirm.visible = false
		main.reset_game()
		close())
	_confirm.add_child(yes)
	var no := _button("No", 100)
	no.position = Vector2(266, 100)
	no.pressed.connect(func(): _confirm.visible = false)
	_confirm.add_child(no)


func _on_dial(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		if e.button_index == MOUSE_BUTTON_LEFT:
			_dragging = e.pressed
			if e.pressed:
				_drag_last = _hours_at(e.position)
				set_hours(_drag_last)
			else:
				_later()
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_UP:
			turn_by(0.25)
		elif e.pressed and e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			turn_by(-0.25)
	elif e is InputEventMouseMotion and _dragging:
		var h := _hours_at(e.position)
		var step := fposmod(h - _drag_last + 12.0, 24.0) - 12.0      # the short way round
		_drag_last = h
		turn_by(step)


func _hours_at(at: Vector2) -> float:
	var d := at - _dial.size * 0.5
	return fposmod((atan2(d.y, d.x) + PI * 0.5) / TAU * 24.0 + 12.0, 24.0)


## Turn the clock on (or back) by so many hours; past midnight is the next day (or the one before).
func turn_by(h: float) -> void:
	var t: float = daytime.hours + h
	while t >= 24.0:
		t -= 24.0
		daytime.day = daytime.day % 365 + 1
	while t < 0.0:
		t += 24.0
		daytime.day = (daytime.day + 363) % 365 + 1
	daytime.hours = t


func set_hours(h: float) -> void:
	turn_by(fposmod(h - daytime.hours + 12.0, 24.0) - 12.0)


func open() -> void:
	if is_open:
		return
	is_open = true
	_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_root.visible = true
	_confirm.visible = false
	_refresh()
	# with a gamepad the buttons are stepped through with the cross or the stick, and A presses one
	var pad := not Input.get_connected_joypads().is_empty()
	var first: Button = null
	for b in _root.find_children("*", "Button", true, false):
		(b as Button).focus_mode = Control.FOCUS_ALL if pad else Control.FOCUS_NONE
		if first == null and not (b is CheckBox):
			first = b
	if pad and first != null:
		first.grab_focus()


func close() -> void:
	if not is_open:
		return
	is_open = false
	_dragging = false
	_root.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	save()


func ask_reset() -> void:
	open()
	_confirm.visible = true


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _confirm.visible:
			_confirm.visible = false
		elif is_open:
			close()
		else:
			open()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("reset"):
		ask_reset()
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	# In a browser Esc first lets the mouse go, and the game never hears of it: so a mouse let go is the menu asked for.
	if not is_open and OS.has_feature("web") and _was_captured and Input.mouse_mode == Input.MOUSE_MODE_VISIBLE:
		open()
	if not is_open:
		_was_captured = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	if _save_in > 0.0:
		_save_in -= delta
		if _save_in <= 0.0:
			save()
	if is_open:
		_refresh()


func _later() -> void:
	_save_in = 1.0


## Lay the panel out for the window and show how things stand.
func _refresh() -> void:
	var vs := _root.get_viewport_rect().size
	var box: VBoxContainer = _panel.get_meta("box")
	var want := Vector2(maxf(PANEL_W, box.get_combined_minimum_size().x + 44.0), box.get_combined_minimum_size().y + 34.0)
	var scale := minf(1.0, minf((vs.x - 24.0) / want.x, (vs.y - 24.0) / want.y))      # a small window gets a smaller menu
	_panel.size = want
	_panel.scale = Vector2(scale, scale)
	_panel.position = Vector2(28.0, maxf(12.0, (vs.y - want.y * scale) * 0.5))
	_confirm.position = (vs - _confirm.size) * 0.5
	var h: float = daytime.hours
	_time_label.text = "%02d:%02d" % [int(h), int(fposmod(h, 1.0) * 60.0)]
	_dial.queue_redraw()
	for b in _rate_buttons:
		_light(b, is_equal_approx(b.get_meta("rate"), daytime.rate))
	for k in _weather_buttons:
		var on: bool = weather.changing if k == "changing" else (not weather.changing and weather.kind == k)
		_light(_weather_buttons[k], on)
		(_weather_buttons[k].get_meta("name_label") as Label).add_theme_color_override("font_color", Color(0.08, 0.08, 0.08) if on else Color(1, 1, 1, 0.9))
	_wind.set_meta("quiet", true)
	_wind.value = weather.wind_set if weather.wind_set >= 0.0 else float(weather.now["wind"])
	_wind.remove_meta("quiet")
	_light(_wind_auto, weather.wind_set < 0.0)
	_volume.set_value_no_signal(sound.volume)
	_mute.set_pressed_no_signal(sound.muted)
	_ripples.set_pressed_no_signal(world.ripples.enabled)
	for i in 3:
		_light(_traffic_buttons[i], traffic == i)
		_light(_grass_buttons[i], grass == i)
		_light(_occasion_buttons[i], occasion == i)
	for i in 2:
		_light(_season_buttons[i], weather.winter == (i == 1))
	_slippery.set_pressed_no_signal(weather.slippery)


func save() -> void:
	_save_in = -1.0
	if not OS.get_cmdline_user_args().is_empty():
		return                                              # (a check, not a game: leave the player's settings alone)
	var cf := ConfigFile.new()
	cf.set_value("sound", "volume", sound.volume)
	cf.set_value("sound", "muted", sound.muted)
	cf.set_value("world", "traffic", traffic)
	cf.set_value("world", "grass", grass)
	cf.set_value("world", "ripples", world.ripples.enabled)
	cf.set_value("time", "hours", daytime.hours)
	cf.set_value("time", "day", daytime.day)
	cf.set_value("time", "rate", daytime.rate)
	cf.set_value("weather", "kind", weather.kind)
	cf.set_value("weather", "changing", weather.changing)
	cf.set_value("weather", "wind", weather.wind_set)
	cf.set_value("world", "winter", weather.winter)
	cf.set_value("world", "slippery", weather.slippery)
	cf.set_value("world", "occasion", occasion)
	cf.save(FILE)


func _load() -> void:
	var cf := ConfigFile.new()
	if not OS.get_cmdline_user_args().is_empty() or cf.load(FILE) != OK:
		return
	sound.volume = cf.get_value("sound", "volume", sound.volume)
	sound.muted = cf.get_value("sound", "muted", false)
	traffic = cf.get_value("world", "traffic", traffic)
	main.traffic.amount = traffic
	grass = cf.get_value("world", "grass", grass)
	main.grass.amount = grass
	world.ripples.enabled = cf.get_value("world", "ripples", true)
	weather.winter = cf.get_value("world", "winter", false)
	weather.slippery = cf.get_value("world", "slippery", false)
	occasion = cf.get_value("world", "occasion", 0)
	if occasion == 2:
		main.molde.match_day = true
	var args := " ".join(OS.get_cmdline_user_args())
	if not "--time=" in args:                                 # (a check that sets the time or the weather keeps what it set)
		daytime.hours = cf.get_value("time", "hours", daytime.hours)
		daytime.day = cf.get_value("time", "day", daytime.day)
		if args == "":
			daytime.rate = cf.get_value("time", "rate", daytime.rate)
	if not "--weather=" in args:
		var k: String = cf.get_value("weather", "kind", weather.kind)
		if weather.SET.has(k):
			weather.kind = k
			weather.now = weather.SET[k].duplicate()
			weather._from = weather.now.duplicate()
			weather._turn = 1.0
		weather.changing = cf.get_value("weather", "changing", true)
		weather.wind_set = cf.get_value("weather", "wind", -1.0)
