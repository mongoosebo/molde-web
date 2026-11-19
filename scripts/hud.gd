extends CanvasLayer
## Loading screen, where-am-I readout (district and street from the real map), compass, stamina.

var world
var player

var _loading: ColorRect
var _under: ColorRect
var _loading_label: Label
var _district: Label
var _street: Label
var _coords: Label
var _intro: Label
var _help: Label
var _prompt: Label
var _compass: Compass
var _stamina_bg: ColorRect
var _stamina_fill: ColorRect
var _tick := 0.0
var _age := 0.0


class Compass extends Control:
	var bearing := 0.0
	var mark := NAN         # the bearing of where a job wants the player to go (scripts/jobs.gd), or NAN for none
	var mark_far := 0.0     # and how far it is, in metres
	const SPAN := 110.0     # degrees shown across the strip
	const NAMES := {0: "N", 45: "NØ", 90: "Ø", 135: "SØ", 180: "S", 225: "SV", 270: "V", 315: "NV"}   # Norwegian: nord, øst, sør, vest

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var w := size.x
		draw_rect(Rect2(0, 0, w, 30), Color(0, 0, 0, 0.28))
		for deg in range(0, 360, 15):
			var d := wrapf(float(deg) - bearing, -180.0, 180.0)
			if absf(d) > SPAN * 0.5:
				continue
			var x := w * 0.5 + d / SPAN * w
			var fade := 1.0 - absf(d) / (SPAN * 0.5)
			if NAMES.has(deg):
				var txt: String = NAMES[deg]
				var fs := 17 if deg % 90 == 0 else 13
				var tw := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
				draw_string(font, Vector2(x - tw * 0.5, 21), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, 0.35 + 0.65 * fade))
			else:
				draw_line(Vector2(x, 10), Vector2(x, 20), Color(1, 1, 1, 0.5 * fade), 1.0)
		draw_line(Vector2(w * 0.5, 30), Vector2(w * 0.5, 36), Color(1.0, 0.8, 0.4), 2.0)
		if not is_nan(mark):
			# the goal: a green wedge under the strip, held at the edge when it is off to one side, with the distance
			var dm := clampf(wrapf(mark - bearing, -180.0, 180.0), -SPAN * 0.5, SPAN * 0.5)
			var mx := w * 0.5 + dm / SPAN * w
			var green := Color(0.40, 1.0, 0.50)
			draw_colored_polygon(PackedVector2Array([Vector2(mx, 31), Vector2(mx - 7, 43), Vector2(mx + 7, 43)]), green)
			var far := ("%d m" % int(mark_far)) if mark_far < 1000.0 else ("%.1f km" % (mark_far / 1000.0))
			var fw := font.get_string_size(far, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
			draw_string(font, Vector2(clampf(mx - fw * 0.5, 0.0, w - fw), 58), far, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, green)


func _label(font_size: int, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 1)
	l.add_theme_constant_override("shadow_offset_y", 1)
	add_child(l)
	return l


func _ready() -> void:
	_district = _label(26, Color(1, 1, 1, 0.95))
	_district.position = Vector2(28, 22)
	_street = _label(17, Color(1, 1, 1, 0.75))
	_street.position = Vector2(28, 56)
	_coords = _label(12, Color(1, 1, 1, 0.5))
	_coords.position = Vector2(28, 80)

	_compass = Compass.new()
	_compass.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_compass)

	_stamina_bg = ColorRect.new()
	_stamina_bg.color = Color(0, 0, 0, 0.4)
	add_child(_stamina_bg)
	_stamina_fill = ColorRect.new()
	_stamina_fill.color = Color(0.92, 0.85, 0.62, 0.9)
	add_child(_stamina_fill)

	_help = _label(13, Color(1, 1, 1, 0.6))
	_help.text = "WASD move  ·  Mouse look  ·  Shift sprint (swim faster)  ·  Space jump  ·  F get in/out of a vehicle  ·  Space in a car: drift  ·  Bicycle: hold Space and let go to jump  ·  Helicopter: mouse turns, Space up, Ctrl down, WASD lean  ·  Wheel zoom  ·  F11 fullscreen  ·  [ ] time of day  ·  V weather  ·  M mute  ·  E take a job  ·  J jobs and sights  ·  Q view from the seat  ·  Esc menu  ·  F5 start again  ·  Right mouse: leave a note"
	if OS.has_feature("web"):
		_help.text = "WASD move  ·  Mouse look  ·  Shift sprint (swim faster)  ·  Space jump  ·  F get in/out of a vehicle  ·  Space in a car: drift  ·  Bicycle: hold Space and let go to jump  ·  Helicopter: mouse turns, Space up, C down, WASD lean  ·  Wheel zoom  ·  F11 fullscreen  ·  [ ] time of day  ·  V weather  ·  M mute  ·  E take a job  ·  J jobs and sights  ·  Q view from the seat  ·  Esc menu  ·  F5 start again"

	_intro = _label(22, Color(1, 1, 1, 1))
	_intro.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_intro.text = "Molde\nRosenes by"
	_intro.visible = false
	_prompt = _label(18, Color(1, 1, 1, 0.95))
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.visible = false

	_under = ColorRect.new()                       # the view under water: dark green-blue
	_under.color = Color(0.02, 0.16, 0.19, 0.72)
	_under.set_anchors_preset(Control.PRESET_FULL_RECT)
	_under.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_under.visible = false
	add_child(_under)
	_loading = ColorRect.new()
	_loading.color = Color(0.03, 0.035, 0.04)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_loading)
	_loading_label = Label.new()
	_loading_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_loading_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_loading_label.add_theme_font_size_override("font_size", 22)
	_loading.add_child(_loading_label)
	_layout()


func set_loading(text: String) -> void:
	_loading_label.text = "MOLDE\n\n" + text


func start(w, p) -> void:
	world = w
	player = p
	_loading.visible = false
	_intro.visible = true
	_age = 0.0


func _layout() -> void:
	var vs := get_viewport().get_visible_rect().size
	_compass.position = Vector2(vs.x * 0.5 - 230.0, 18.0)
	_compass.size = Vector2(460.0, 62.0)
	_stamina_bg.position = Vector2(28.0, vs.y - 44.0)
	_stamina_bg.size = Vector2(180.0, 6.0)
	_stamina_fill.position = _stamina_bg.position
	_help.position = Vector2(28.0, vs.y - 30.0)
	_intro.position = Vector2(0.0, vs.y * 0.68)
	_intro.size = Vector2(vs.x, 80.0)
	_prompt.position = Vector2(0.0, vs.y * 0.82)
	_prompt.size = Vector2(vs.x, 30.0)


func _process(delta: float) -> void:
	_layout()
	if player == null:
		return
	_age += delta
	_under.visible = player.under_water
	_intro.modulate.a = clampf(minf(_age / 1.5, (9.0 - _age) / 2.0), 0.0, 1.0)
	_help.modulate.a = clampf((40.0 - _age) / 3.0, 0.0, 1.0)

	_prompt.visible = player.near_atv() or (player.driving and _age < 60.0 and player._drive_speed == 0.0)
	_prompt.text = "F  —  get out" if player.driving else "F  —  get in or on %s" % player.vehicle_label()
	_compass.bearing = player.bearing()
	_compass.queue_redraw()
	var st: float = player.stamina
	_stamina_fill.size = Vector2(180.0 * st, 6.0)
	_stamina_bg.modulate.a = 1.0 if st < 0.995 else 0.0
	_stamina_fill.modulate.a = _stamina_bg.modulate.a

	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.25
		var pos: Vector3 = player.global_position
		var where: Dictionary = world.locate(pos.x, pos.z)
		_district.text = where["district"]
		_street.text = where["street"]
		var ll: Vector2 = world.to_latlon(pos.x, pos.z)
		_coords.text = "%.4f° N  %.4f° Ø  ·  %d moh." % [ll.x, ll.y, int(maxf(pos.y, 0.0))]
