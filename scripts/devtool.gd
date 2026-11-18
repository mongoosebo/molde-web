extends CanvasLayer
## Development tool: a crosshair, and a way to leave notes on things in the world.
##
## Point the crosshair at something and press the right mouse button: the thing is lit up in yellow and a
## text box opens. What is written there is saved (Ctrl+Enter or the Save button; Esc cancels) to
## notes/notes.jsonl, one line per note, with what was pointed at, where it is, where the player stood and a
## picture of the view (notes/shots/). The notes are read and acted on after the game is closed.

const REACH := 600.0
const YELLOW := Color(1.0, 0.85, 0.1)
const PROP_NAMES := ["lamp", "bus shelter", "bus stop sign", "bench", "fence", "hedge", "wall", "guard rail", "flagpole",
	"parked car", "give-way sign", "round sign (speed limit)", "pedestrian crossing sign", "traffic signal", "post box",
	"picnic table", "swings", "pylon", "power line", "picket fence", "retaining wall", "boat", "ferry", "airliner",
	"viewpoint railing", "give-way sign with roundabout sign", "street-name sign", "flower tub", "cruise ship", "gravestone"]
const LINEAR := [4, 5, 6, 7, 18, 19, 20]
const WAY_NAMES := {0: "road", 1: "sidewalk", 2: "pedestrian crossing", 3: "paved path", 4: "bridge", 5: "runway paint",
	6: "give-way line", 7: "gravel walk or trail", 8: "steps"}
const STYLE_NAMES := ["villa", "1960s house", "modern house", "row house", "old apartment block", "new apartment block",
	"shop", "big box store", "industry", "outbuilding or garage", "public building", "barn", "old timber house", "main street building"]

var world
var player

var _cross: Control
var _panel: PanelContainer
var _title: Label
var _edit: TextEdit
var _toast: Label
var _count: Label
var _mark: MeshInstance3D
var _mat: StandardMaterial3D
var _props := PackedFloat32Array()
var _prop_grid := {}             # Vector2i (20 m) -> PackedInt32Array of prop numbers
var _trees := PackedFloat32Array()
var _tree_grid := {}             # Vector2i (20 m) -> PackedInt32Array of tree numbers
var _pending := {}
var _saved := 0
var _toast_time := 0.0
var _dir := ""
# The patch tool (P): squares of asphalt, of paving, or of bare ground laid where the crosshair points. Each is
# written to tools/patches.jsonl, which tools/build_map.py reads: the patch is real after the next build of the
# map. Until then it is shown as a flat square of the colour it will be.
const PATCH_KINDS := ["asphalt", "paving", "none"]
const PATCH_NAMES := ["asphalt", "paving", "remove (bare ground)"]
const PATCH_SIZES := [2.0, 4.0, 8.0, 16.0, 32.0]
const PATCH_COLOURS := [Color(0.13, 0.13, 0.14), Color(0.55, 0.55, 0.54), Color(0.30, 0.42, 0.20)]
var patching := false
var _patch_kind := 0
var _patch_size := 1
var _patch_made: Array = []          # the squares laid this session: [line in the file, the node that shows it]
var _patch_frame: MeshInstance3D
var _patch_line: Label
var _patch_path := ""


class Cross extends Control:
	func _draw() -> void:
		var c := size * 0.5
		for d in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]:
			draw_line(c + d * 5.0, c + d * 13.0, Color(0, 0, 0, 0.7), 4.0)
			draw_line(c + d * 5.0, c + d * 13.0, Color(1, 1, 1, 0.95), 2.0)
		draw_circle(c, 1.6, Color(1, 1, 1, 0.95))


func start(w, p) -> void:
	world = w
	player = p
	layer = 5
	_dir = ProjectSettings.globalize_path("res://notes")
	DirAccess.make_dir_recursive_absolute(_dir + "/shots")
	if FileAccess.file_exists(_dir + "/notes.jsonl"):
		_saved = FileAccess.get_file_as_string(_dir + "/notes.jsonl").count("\n")

	_patch_path = ProjectSettings.globalize_path("res://tools/patches.jsonl")
	_patch_frame = MeshInstance3D.new()
	_patch_frame.visible = false
	_patch_frame.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_patch_frame.top_level = true
	world.add_child(_patch_frame)
	_patch_line = Label.new()
	_patch_line.add_theme_font_size_override("font_size", 16)
	_patch_line.add_theme_color_override("font_color", Color(1.0, 0.85, 0.1))
	_patch_line.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_patch_line.add_theme_constant_override("outline_size", 5)
	_patch_line.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)
	_patch_line.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_patch_line.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_patch_line)

	_cross = Cross.new()
	_cross.set_anchors_preset(Control.PRESET_FULL_RECT)
	_cross.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_cross)

	_count = Label.new()
	_count.add_theme_font_size_override("font_size", 13)
	_count.add_theme_color_override("font_color", Color(1, 1, 1, 0.6))
	_count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, 28)
	_count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	add_child(_count)
	_toast = Label.new()
	_toast.add_theme_font_size_override("font_size", 18)
	_toast.add_theme_color_override("font_color", YELLOW)
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_toast.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP, Control.PRESET_MODE_MINSIZE, 70)
	_toast.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_toast)
	_show_count()

	_panel = PanelContainer.new()
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM, Control.PRESET_MODE_MINSIZE, 60)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_panel.custom_minimum_size = Vector2(720, 0)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	_panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	_title = Label.new()
	_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_title.add_theme_color_override("font_color", YELLOW)
	box.add_child(_title)
	_edit = TextEdit.new()
	_edit.custom_minimum_size = Vector2(0, 150)
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.placeholder_text = "What should change here?"
	box.add_child(_edit)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var hint := Label.new()
	hint.text = "Ctrl+Enter saves  ·  Esc cancels"
	hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.5))
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(hint)
	var cancel := Button.new()
	cancel.text = "Cancel"
	cancel.pressed.connect(_close.bind(false))
	row.add_child(cancel)
	var save := Button.new()
	save.text = "Save note"
	save.pressed.connect(_close.bind(true))
	row.add_child(save)
	_panel.visible = false
	add_child(_panel)

	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.albedo_color = Color(YELLOW.r, YELLOW.g, YELLOW.b, 0.2)
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mat.no_depth_test = true
	_mark = MeshInstance3D.new()
	_mark.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_mark.visible = false
	world.add_child(_mark)

	# everything placed by the map that has no shape to hit: looked up by where the line of sight passes
	_props = FileAccess.get_file_as_bytes("res://world/props.bin").to_float32_array()
	for i in _props.size() / 8:
		var o := i * 8
		var x := _props[o + 1]
		var z := _props[o + 3]
		if int(_props[o]) in LINEAR:
			x += _props[o + 4] * 0.5
			z += _props[o + 6] * 0.5
		_grid_add(_prop_grid, x, z, i)
	_trees = FileAccess.get_file_as_bytes("res://world/trees.bin").to_float32_array()
	for i in _trees.size() / 5:
		_grid_add(_tree_grid, _trees[i * 5], _trees[i * 5 + 1], i)


func _grid_add(grid: Dictionary, x: float, z: float, i: int) -> void:
	var k := Vector2i(int(floor(x / 20.0)), int(floor(z / 20.0)))
	if not grid.has(k):
		grid[k] = PackedInt32Array()
	grid[k].append(i)


func _show_count() -> void:
	_count.text = "Right mouse button: leave a note on what the crosshair points at  ·  P: patch tool (asphalt, paving)  ·  notes waiting: %d" % _saved


## Where the crosshair meets the ground, or null.
func _patch_point():
	var cam: Camera3D = get_viewport().get_camera_3d()
	var centre := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(centre)
	var q := PhysicsRayQueryParameters3D.create(from, from + cam.project_ray_normal(centre) * 250.0)
	var exclude: Array[RID] = [player.get_rid()]
	q.exclude = exclude
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	return null if hit.is_empty() else hit["position"]


## A flat square lying on the ground as the ground lies, a little over it: of one colour, or only its edge.
func _patch_square(at: Vector3, size: float, yaw: float, col: Color, only_edge: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := clampi(int(size / 2.0), 2, 16)
	var bs := Basis(Vector3.UP, yaw)
	var pts := []
	for j in n + 1:
		var row := []
		for i in n + 1:
			var p: Vector3 = at + bs * Vector3((float(i) / float(n) - 0.5) * size, 0, (float(j) / float(n) - 0.5) * size)
			var y: float = world.detail.surface_at(p.x, p.z)
			p.y = (world.height_at(p.x, p.z) if is_nan(y) else y + 0.10) + (0.30 if only_edge else 0.27)
			row.append(p - at)
		pts.append(row)
	if only_edge:
		# a narrow band along each side, following the ground
		var inward := 0.18 / (size / float(n))
		for i in n:
			for side in 4:
				var a: Vector3 = [pts[0][i], pts[n][i], pts[i][0], pts[i][n]][side]
				var b: Vector3 = [pts[0][i + 1], pts[n][i + 1], pts[i + 1][0], pts[i + 1][n]][side]
				var a2: Vector3 = [pts[1][i], pts[n - 1][i], pts[i][1], pts[i][n - 1]][side]
				var b2: Vector3 = [pts[1][i + 1], pts[n - 1][i + 1], pts[i + 1][1], pts[i + 1][n - 1]][side]
				_quad(st, a, b, b.lerp(b2, inward), a.lerp(a2, inward))
	else:
		for j in n:
			for i in n:
				_quad(st, pts[j][i], pts[j][i + 1], pts[j + 1][i + 1], pts[j + 1][i])
	st.generate_normals()
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if only_edge:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.surface_set_material(0, mat)
	return mesh


func _patch_text() -> void:
	_patch_line.text = "" if not patching else "PATCH TOOL   1 asphalt · 2 paving · 3 remove   [%s]      4–8 size   [%d m]      left mouse: lay it · Z: undo · P: done      laid: %d (real after the next map build)" % [
		PATCH_NAMES[_patch_kind], int(PATCH_SIZES[_patch_size]), _patch_made.size()]


func _patch_lay() -> void:
	var at = _patch_point()
	if at == null:
		return
	var size: float = PATCH_SIZES[_patch_size]
	var rec := {"kind": PATCH_KINDS[_patch_kind], "x": snappedf(at.x, 0.1), "z": snappedf(at.z, 0.1), "size": size, "yaw": snappedf(player.yaw, 0.01),
		"time": Time.get_datetime_string_from_system()}
	var line := JSON.stringify(rec)
	var f := FileAccess.open(_patch_path, FileAccess.READ_WRITE if FileAccess.file_exists(_patch_path) else FileAccess.WRITE)
	f.seek_end()
	f.store_line(line)
	f.close()
	var mi := MeshInstance3D.new()
	mi.mesh = _patch_square(at, size, player.yaw, PATCH_COLOURS[_patch_kind], false)
	mi.position = at
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	world.add_child(mi)
	_patch_made.append([line, mi])
	_patch_text()


func _patch_undo() -> void:
	if _patch_made.is_empty():
		return
	var last: Array = _patch_made.pop_back()
	(last[1] as Node).queue_free()
	var lines := FileAccess.get_file_as_string(_patch_path).split("\n", false)
	for i in range(lines.size() - 1, -1, -1):
		if lines[i] == last[0]:
			lines.remove_at(i)
			break
	var f := FileAccess.open(_patch_path, FileAccess.WRITE)
	for l in lines:
		f.store_line(l)
	f.close()
	_patch_text()


func _process(delta: float) -> void:
	if patching and world != null and not _panel.visible:
		var at = _patch_point()
		_patch_frame.visible = at != null
		if at != null:
			_patch_frame.mesh = _patch_square(at, PATCH_SIZES[_patch_size], player.yaw, Color(1.0, 0.85, 0.1), true)
			_patch_frame.global_position = at
	if _toast_time > 0.0:
		_toast_time -= delta
		if _toast_time <= 0.0:
			_toast.text = ""


func _input(event: InputEvent) -> void:
	if world == null:
		return
	if _panel.visible:
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_ESCAPE:
				get_viewport().set_input_as_handled()
				_close(false)
			elif (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER) and event.ctrl_pressed:
				get_viewport().set_input_as_handled()
				_close(true)
		return
	if event is InputEventKey and event.pressed and not event.echo and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if event.keycode == KEY_P:
			patching = not patching
			_patch_frame.visible = false
			_patch_text()
			get_viewport().set_input_as_handled()
			return
		if patching:
			var k: int = event.keycode
			if k >= KEY_1 and k <= KEY_3:
				_patch_kind = k - KEY_1
			elif k >= KEY_4 and k <= KEY_8:
				_patch_size = k - KEY_4
			elif k == KEY_Z:
				_patch_undo()
			else:
				k = -1
			if k != -1:
				_patch_text()
				get_viewport().set_input_as_handled()
				return
	if patching and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		get_viewport().set_input_as_handled()
		_patch_lay()
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT \
			and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		get_viewport().set_input_as_handled()
		_pick()


# ------------------------------------------------------------------ what is under the crosshair
func _pick() -> void:
	var cam: Camera3D = get_viewport().get_camera_3d()
	var centre := get_viewport().get_visible_rect().size * 0.5
	var from := cam.project_ray_origin(centre)
	var dir := cam.project_ray_normal(centre)
	var q := PhysicsRayQueryParameters3D.create(from, from + dir * REACH)
	var exclude: Array[RID] = [player.get_rid()]
	q.exclude = exclude
	var hit: Dictionary = player.get_world_3d().direct_space_state.intersect_ray(q)
	var reach := REACH
	var at := from + dir * 60.0
	var note := {"kind": "nothing", "what": "nothing (open air)"}
	if not hit.is_empty():
		at = hit["position"]
		reach = from.distance_to(at)
		note = _describe_hit(hit, at)
	elif dir.y < -0.001 and from.y / -dir.y < 20000.0:
		at = from + dir * (from.y / -dir.y)
		reach = minf(REACH, from.distance_to(at))
		note = {"kind": "sea", "what": "the sea"}
	# a tree, a sign, a fence… standing in the line of sight before that?
	var thing := _thing_on_ray(from, dir, reach)
	if not thing.is_empty():
		note = thing
		at = thing["at"]
	elif note["kind"] == "ground" or note["kind"] == "other":
		var near := _prop_near(at, 1.3)
		if not near.is_empty():
			note = near
	note.erase("at")
	var here: Dictionary = world.locate(at.x, at.z)
	note["x"] = snappedf(at.x, 0.1)
	note["y"] = snappedf(at.y, 0.1)
	note["z"] = snappedf(at.z, 0.1)
	note["street"] = here.get("street", "")
	note["district"] = here.get("district", "")
	note["player"] = [snappedf(player.global_position.x, 0.1), snappedf(player.global_position.z, 0.1)]
	note["view"] = [snappedf(player.yaw, 0.01), snappedf(player.pitch, 0.01), snappedf(from.distance_to(player.global_position), 0.1)]
	note["riding"] = player.driving
	note["id"] = Time.get_datetime_string_from_system().replace(":", "").replace("-", "") + "_%03d" % (_saved + 1)
	_pending = note
	# a picture of the view as it is — before the highlight and the text box cover it; the crosshair stays in
	_mark.visible = false
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	img.resize(1280, int(1280.0 * img.get_height() / img.get_width()), Image.INTERPOLATE_BILINEAR)
	img.save_jpg(_dir + "/shots/" + note["id"] + ".jpg", 0.85)
	note["shot"] = "notes/shots/" + note["id"] + ".jpg"
	_highlight(note, at)
	_open()


func _describe_hit(hit: Dictionary, at: Vector3) -> Dictionary:
	var col: Node = hit["collider"]
	var path := str(col.get_path())
	var ground: float = world.height_at(at.x, at.z)
	var normal: Vector3 = hit["normal"]
	var b := _building_at(at, at.y > ground + 0.4 or normal.y < 0.7)
	if not b.is_empty():
		var rec: Dictionary = b["rec"]
		var style: int = rec["style"]
		var nm := str(rec.get("name", ""))
		var part := "roof" if normal.y > 0.3 and at.y > rec["ymax"] + 1.5 else "wall"
		return {"kind": "building", "what": "building%s — %s, %d m², %s" % [(" “" + nm + "”") if nm != "" else "",
			STYLE_NAMES[style] if style < STYLE_NAMES.size() else "style %d" % style, int(absf(rec["area"])), part],
			"osm_id": rec.get("id", 0), "name": nm, "style": style, "part": part, "node": path, "rec": rec}
	for vn in ["ATV", "Volvo", "Integra", "Helicopter", "Mercedes", "Bicycle"]:
		if path.contains("/" + vn):
			return {"kind": "vehicle", "what": "the " + vn, "node": path}
	var way := _way_at(at)
	if not way.is_empty() and at.y < ground + 0.6 + (30.0 if way["way_kind"] == 4 else 0.0):
		way["node"] = path
		return way
	if at.y < ground + 0.35 and normal.y > 0.5:
		return {"kind": "ground", "what": "the ground", "node": path}
	var mark := ""
	for lm in world.meta.get("landmarks", []):
		var pts: Array = lm.get("pts", [])
		for i in range(0, pts.size() - 1, 2):
			if Vector2(pts[i], pts[i + 1]).distance_to(Vector2(at.x, at.z)) < 12.0:
				mark = str(lm.get("key", ""))
				break
		if mark != "":
			break
	return {"kind": "other", "what": "something built by hand (%s%s)" % [(mark + ", ") if mark != "" else "", _short(path)],
		"landmark": mark, "node": path}


func _short(path: String) -> String:
	var parts := path.split("/", false)
	var keep := []
	for p in parts:
		if p != "root" and not p.begins_with("@"):
			keep.append(p)
	return "/".join(keep.slice(maxi(0, keep.size() - 3)))


func _building_at(at: Vector3, built: bool) -> Dictionary:
	var p := Vector2(at.x, at.z)
	var best := {}
	var best_d := 0.9 if built else 0.0
	for key in world.detail.buildings:
		for rec in world.detail.buildings[key]:
			var poly: PackedVector2Array = rec["poly"]
			if p.distance_squared_to(poly[0]) > 160000.0:
				continue
			if Geometry2D.is_point_in_polygon(p, poly):
				return {"rec": rec}
			if not built:
				continue
			for i in poly.size():
				var d := Geometry2D.get_closest_point_to_segment(p, poly[i], poly[(i + 1) % poly.size()]).distance_to(p)
				if d < best_d:
					best_d = d
					best = {"rec": rec}
	return best


func _way_at(at: Vector3) -> Dictionary:
	var det = world.detail
	var best := {}
	var best_d := 1e9
	var c: Vector2i = det.cell_of(at.x, at.z)
	var p := Vector2(at.x, at.z)
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var arr = det.road_cells.get(c + Vector2i(dx, dz))
			if arr == null:
				continue
			for j in range(0, arr.size(), 2):
				var w: Array = det.ways[arr[j]]
				var pts: PackedVector2Array = w[3]
				var k: int = arr[j + 1]
				var half: float = w[0]
				var d := Geometry2D.get_closest_point_to_segment(p, pts[k], pts[mini(k + 1, pts.size() - 1)]).distance_to(p)
				var wk: int = w[1]
				var slack := d - half - (0.3 if wk != 0 else 0.8)
				if slack < 0.0 and (best.is_empty() or wk > best["way_kind"] or (wk == best["way_kind"] and d < best_d)):
					best_d = d
					best = {"kind": "way", "way_kind": wk, "what": "%s, %.1f m wide" % [WAY_NAMES.get(wk, "way"), half * 2.0],
						"way": arr[j], "station": k, "width": snappedf(half * 2.0, 0.1), "from_middle": snappedf(d, 0.1)}
	return best


func _prop_record(i: int, at: Vector3) -> Dictionary:
	var o := i * 8
	var kind := int(_props[o])
	return {"kind": "prop", "prop_kind": kind, "what": PROP_NAMES[kind] if kind < PROP_NAMES.size() else "prop %d" % kind,
		"prop": i, "prop_at": [snappedf(_props[o + 1], 0.01), snappedf(_props[o + 2], 0.01), snappedf(_props[o + 3], 0.01)],
		"prop_abc": [snappedf(_props[o + 4], 0.01), snappedf(_props[o + 5], 0.01), snappedf(_props[o + 6], 0.01)], "at": at}


func _prop_distance(i: int, p: Vector3) -> float:
	var o := i * 8
	var a := Vector2(_props[o + 1], _props[o + 3])
	if int(_props[o]) in LINEAR:
		a = Geometry2D.get_closest_point_to_segment(Vector2(p.x, p.z), a, a + Vector2(_props[o + 4], _props[o + 6]))
	return a.distance_to(Vector2(p.x, p.z))


func _prop_near(at: Vector3, radius: float) -> Dictionary:
	var best := -1
	var best_d := radius
	var c := Vector2i(int(floor(at.x / 20.0)), int(floor(at.z / 20.0)))
	for dx in [-1, 0, 1]:
		for dz in [-1, 0, 1]:
			var arr = _prop_grid.get(c + Vector2i(dx, dz))
			if arr == null:
				continue
			for i in arr:
				if int(_props[i * 8]) == 18:
					continue
				var d := _prop_distance(i, at)
				if d < best_d and at.y > _props[i * 8 + 2] - 1.0 and at.y < _props[i * 8 + 2] + 7.0:
					best_d = d
					best = i
	return _prop_record(best, at) if best >= 0 else {}


## Walk along the line of sight and stop at the first tree or piece of street furniture it passes through.
func _thing_on_ray(from: Vector3, dir: Vector3, reach: float) -> Dictionary:
	var s := 0.6
	var limit := minf(reach - 0.3, 320.0)
	while s < limit:
		var p := from + dir * s
		var c := Vector2i(int(floor(p.x / 20.0)), int(floor(p.z / 20.0)))
		for dx in [-1, 0, 1]:
			for dz in [-1, 0, 1]:
				var k := c + Vector2i(dx, dz)
				var arr = _prop_grid.get(k)
				if arr != null:
					for i in arr:
						var o: int = i * 8
						var kind := int(_props[o])
						if kind == 18 or (kind >= 21 and kind <= 23) or kind == 28:
							continue
						var tall := 1.6 if kind in LINEAR else (5.5 if kind in [0, 8, 13] else 3.0)
						var wide := 0.35 if kind in LINEAR or kind in [0, 2, 8, 10, 11, 12, 13, 25, 26] else 1.3
						if p.y > _props[o + 2] - 0.2 and p.y < _props[o + 2] + tall and _prop_distance(i, p) < wide:
							return _prop_record(i, p)
				arr = _tree_grid.get(k)
				if arr != null:
					for i in arr:
						var o: int = i * 5
						var sc := _trees[o + 2]
						var y := _trees[o + 4]
						if p.y < y or p.y > y + 8.5 * sc:
							continue
						var r := (0.3 if p.y < y + 1.6 * sc else 1.5 * sc)
						if Vector2(p.x - _trees[o], p.z - _trees[o + 1]).length() < r:
							return {"kind": "tree", "what": "%s, about %d m tall" % ["spruce" if _trees[o + 3] < 0.5 else "leafy tree", int(8.0 * sc)],
								"tree": i, "tree_at": [snappedf(_trees[o], 0.01), snappedf(_trees[o + 1], 0.01)], "scale": snappedf(sc, 0.01),
								"at": p}
		s += 0.3 if s < 60.0 else 0.6
	return {}


# ------------------------------------------------------------------ lighting it up
func _highlight(note: Dictionary, at: Vector3) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	match note["kind"]:
		"building":
			var rec: Dictionary = note["rec"]
			var poly: PackedVector2Array = rec["poly"]
			var y0: float = rec["ymin"] - 0.3
			var y1: float = float(rec["rf"].get("top", rec["ymax"] + rec["h"] + 2.5)) + 0.3
			for i in poly.size():
				var a := poly[i]
				var b := poly[(i + 1) % poly.size()]
				_quad(st, Vector3(a.x, y0, a.y), Vector3(b.x, y0, b.y), Vector3(b.x, y1, b.y), Vector3(a.x, y1, a.y))
			var tris := Geometry2D.triangulate_polygon(poly)
			for i in range(0, tris.size(), 3):
				for j in 3:
					var v := poly[tris[i + j]]
					st.add_vertex(Vector3(v.x, y1, v.y))
			note.erase("rec")
		"prop":
			var o: int = int(note["prop"]) * 8
			var kind := int(_props[o])
			var base := Vector3(_props[o + 1], _props[o + 2], _props[o + 3])
			if kind in LINEAR:
				var e := Vector3(_props[o + 4], _props[o + 5], _props[o + 6])
				var side := Vector3(-e.z, 0, e.x).normalized() * 0.3
				_slab(st, base - side, base + side, base + e + side, base + e - side, 1.5)
			else:
				var r := 0.45 if kind in [0, 2, 8, 10, 11, 12, 13, 25, 26] else 1.6
				_post(st, base, r, 5.5 if kind in [0, 8, 13] else 3.0)
		"tree":
			var o: int = int(note["tree"]) * 5
			var sc := _trees[o + 2]
			_post(st, Vector3(_trees[o], _trees[o + 4], _trees[o + 1]), 1.6 * sc, 8.5 * sc)
		"way":
			var w: Array = world.detail.ways[note["way"]]
			var pts: PackedVector2Array = w[3]
			var nrm: PackedVector2Array = w[4]
			var half: float = w[0]
			var k: int = note["station"]
			for i in range(maxi(k - 2, 0), mini(k + 3, pts.size() - 1)):
				var a := pts[i]
				var b := pts[i + 1]
				var ya: float = (w[8][i] if w[1] == 4 else world.height_at(a.x, a.y)) + 0.25
				var yb: float = (w[8][i + 1] if w[1] == 4 else world.height_at(b.x, b.y)) + 0.25
				_quad(st, Vector3(a.x + nrm[i].x * half, ya, a.y + nrm[i].y * half), Vector3(a.x - nrm[i].x * half, ya, a.y - nrm[i].y * half),
					Vector3(b.x - nrm[i + 1].x * half, yb, b.y - nrm[i + 1].y * half), Vector3(b.x + nrm[i + 1].x * half, yb, b.y + nrm[i + 1].y * half))
		_:
			_post(st, at - Vector3(0, 0.1, 0), 1.0, 0.25)
	_mark.mesh = st.commit()
	_mark.material_override = _mat
	_mark.global_transform = Transform3D.IDENTITY
	_mark.visible = true


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	for v in [a, b, c, a, c, d]:
		st.add_vertex(v)


func _slab(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, h: float) -> void:
	var up := Vector3(0, h, 0)
	_quad(st, a + up, b + up, c + up, d + up)
	_quad(st, a, b, b + up, a + up)
	_quad(st, b, c, c + up, b + up)
	_quad(st, c, d, d + up, c + up)
	_quad(st, d, a, a + up, d + up)


func _post(st: SurfaceTool, base: Vector3, r: float, h: float) -> void:
	var ring := []
	for i in 12:
		ring.append(base + Vector3(cos(i * TAU / 12.0) * r, 0, sin(i * TAU / 12.0) * r))
	var up := Vector3(0, h, 0)
	for i in 12:
		var a: Vector3 = ring[i]
		var b: Vector3 = ring[(i + 1) % 12]
		_quad(st, a, b, b + up, a + up)
		for v in [base + up, a + up, b + up]:
			st.add_vertex(v)


# ------------------------------------------------------------------ the text box
func _open() -> void:
	var n: Dictionary = _pending
	var where_ := str(n.get("street", ""))
	_title.text = "Note on: %s%s   (%.0f, %.0f)" % [n["what"], ("  ·  " + where_) if where_ != "" else "", n["x"], n["z"]]
	_edit.text = ""
	_panel.visible = true
	player.set_physics_process(false)
	player.set_process_unhandled_input(false)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_edit.grab_focus()


func _close(save: bool) -> void:
	var text := _edit.text.strip_edges()
	if save and text != "":
		_pending["note"] = text
		_pending["time"] = Time.get_datetime_string_from_system()
		var path := _dir + "/notes.jsonl"
		var f := FileAccess.open(path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE)
		f.seek_end()
		f.store_line(JSON.stringify(_pending))
		f.close()
		_saved += 1
		_toast.text = "Note %d saved" % _saved
	else:
		if _pending.has("shot"):
			DirAccess.remove_absolute(_dir + "/shots/" + str(_pending["id"]) + ".jpg")
		_toast.text = "No note saved"
	_toast_time = 2.5
	_show_count()
	_pending = {}
	_panel.visible = false
	_mark.visible = false
	_edit.release_focus()
	player.set_physics_process(true)
	player.set_process_unhandled_input(true)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
