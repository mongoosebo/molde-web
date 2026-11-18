extends Node3D
const Paths := preload("res://scripts/paths.gd")
## Street furniture from world/props.bin (tools/build_map.py): lamps, bus shelters, benches, signs,
## parked cars, flagpoles, fences, hedges, walls, pylons and their wires. Each kind is one small model
## drawn many times; near the player they are solid as simple boxes (scripts/detail.gd asks for those).

enum {LAMP, SHELTER, BUS_SIGN, BENCH, FENCE, HEDGE, WALL, GUARD_RAIL, FLAGPOLE, CAR, GIVE_WAY, ROUND_SIGN, CROSSING_SIGN,
	SIGNAL, POST_BOX, PICNIC, SWINGS, PYLON, WIRES, PICKET, RETAINING, BOAT, FERRY, AIRLINER, VIEWPOINT, GIVE_WAY_ROUND, NAME_SIGN, PLANTER, CRUISE, GRAVE}

const CHUNK := 320.0
const RANGE := 520.0
const LINEAR := [FENCE, HEDGE, WALL, GUARD_RAIL, WIRES, PICKET, RETAINING]
const CAR_PAINT := [Color(0.80, 0.80, 0.80), Color(0.10, 0.10, 0.11), Color(0.45, 0.46, 0.48), Color(0.55, 0.08, 0.07),
	Color(0.12, 0.20, 0.38), Color(0.92, 0.92, 0.90), Color(0.25, 0.27, 0.29), Color(0.20, 0.33, 0.24)]
# what is solid: standing things [half width, half height, half depth], things along a line [height, half thickness]
const SOLID := {
	LAMP: Vector3(0.1, 3.5, 0.1), SHELTER: Vector3(1.6, 1.15, 0.75), BUS_SIGN: Vector3(0.06, 1.3, 0.06), BENCH: Vector3(0.8, 0.50, 0.28),
	FLAGPOLE: Vector3(0.08, 4.5, 0.08), CAR: Vector3(0.9, 0.72, 2.15), GIVE_WAY: Vector3(0.06, 1.2, 0.06),
	ROUND_SIGN: Vector3(0.06, 1.2, 0.06), CROSSING_SIGN: Vector3(0.06, 1.2, 0.06), SIGNAL: Vector3(0.1, 1.7, 0.1),
	BOAT: Vector3(1.1, 0.7, 3.2), FERRY: Vector3(8.5, 6.0, 39.0), CRUISE: Vector3(12.5, 16.0, 88.0), AIRLINER: Vector3(2.0, 2.4, 17.0), VIEWPOINT: Vector3(2.0, 0.55, 0.1),
	PLANTER: Vector3(0.5, 0.35, 0.5),
	GIVE_WAY_ROUND: Vector3(0.06, 1.3, 0.06), NAME_SIGN: Vector3(0.05, 1.4, 0.05),
	POST_BOX: Vector3(0.24, 0.7, 0.16), PICNIC: Vector3(0.9, 0.4, 0.75), SWINGS: Vector3(1.7, 1.1, 0.9), PYLON: Vector3(1.3, 11.0, 1.3),
	FENCE: Vector2(1.1, 0.05), PICKET: Vector2(1.0, 0.05), HEDGE: Vector2(1.3, 0.4), WALL: Vector2(1.1, 0.15),
	RETAINING: Vector2(1.6, 0.2), GUARD_RAIL: Vector2(0.75, 0.06),
}

var world
var cells := {}                # 100 m cell -> [[kind, Transform3D], ...]


var parked := {}                         # 100 m square -> [[where it stands, colour, its MultiMesh, its number there, its place in that], ...]


func build(w) -> void:
	world = w
	var meshes := _meshes()
	var data := FileAccess.get_file_as_bytes(Paths.world + "props.bin").to_float32_array()
	var groups := {}           # Vector3i(chunk x, chunk z, kind) -> [[Transform3D, Color], ...]
	var n := data.size() / 8
	for i in n:
		var o := i * 8
		var kind := int(data[o])
		if not meshes.has(kind):
			continue
		var pos := Vector3(data[o + 1], data[o + 2], data[o + 3])
		var xf: Transform3D
		var col := Color.WHITE
		if kind in LINEAR:
			var e := Vector3(data[o + 4], data[o + 5], data[o + 6])
			var flat := Vector3(e.x, 0.0, e.z)
			if flat.length() < 0.05:
				continue
			var side := Vector3(-flat.z, 0.0, flat.x).normalized()
			xf = Transform3D(Basis(e, Vector3.UP, side), pos)
		else:
			var s := data[o + 5]
			xf = Transform3D(Basis(Vector3.UP, data[o + 4]).scaled(Vector3(s, s, s)), pos)
			if kind == ROUND_SIGN and data[o + 6] > 0.0:
				_letter(str(int(data[o + 6])), xf * Transform3D(Basis(Vector3.UP, PI), Vector3(0, 2.2, -0.075)), 0.0062, Color(0.05, 0.05, 0.06))
			if kind == CAR or kind == BOAT:
				col = CAR_PAINT[int(data[o + 6]) % CAR_PAINT.size()]
				if kind == BOAT:
					col = col.lerp(Color.WHITE, 0.6)
		var gk := Vector3i(int(floor(pos.x / CHUNK)), int(floor(pos.z / CHUNK)), kind)
		if not groups.has(gk):
			groups[gk] = []
		groups[gk].append([xf, col])
		if SOLID.has(kind):
			var ck := Vector2i(int(floor(pos.x / 100.0)), int(floor(pos.z / 100.0)))
			if not cells.has(ck):
				cells[ck] = []
			cells[ck].append([kind, xf])
	# street-name signs: a plate cut to the length of each name, lettered on both sides. The street you
	# are on runs along its own plate; the plate for the street you are coming to hangs across, under it.
	var plate := BoxMesh.new()
	plate.size = Vector3(1.0, 0.24, 0.03)
	var plate_mat := StandardMaterial3D.new()
	plate_mat.albedo_color = Color(0.05, 0.17, 0.50)
	plate_mat.roughness = 0.5
	plate.material = plate_mat
	for sign in world.meta.get("name_signs", []):
		var at := Transform3D(Basis(Vector3.UP, sign[3]), Vector3(sign[0], sign[1], sign[2]))
		_name_plate(plate, sign[4], at * Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(0, 2.68, 0)))
		_name_plate(plate, sign[5], at * Transform3D(Basis(), Vector3(0, 2.40, 0)))
	for gk in groups:
		var list: Array = groups[gk]
		var origin := Vector3((gk.x + 0.5) * CHUNK, 0.0, (gk.y + 0.5) * CHUNK)
		origin.y = world.coarse_at(origin.x, origin.z)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = gk.z == CAR or gk.z == BOAT
		mm.mesh = meshes[gk.z]
		mm.instance_count = list.size()
		for j in list.size():
			if gk.z == CAR and world.detail != null:
				# a parked car stands on the paving, not in it: its tyres on the asphalt or on the slabs (note of 18 Nov)
				var top: float = world.detail.top_at(list[j][0].origin.x, list[j][0].origin.z)
				if not is_nan(top):
					list[j][0].origin.y = top
			var xf: Transform3D = list[j][0]
			xf.origin -= origin
			mm.set_instance_transform(j, xf)
			if mm.use_colors:
				mm.set_instance_color(j, list[j][1])
			if gk.z == CAR:
				# (scripts/traffic.gd stands a detailed car in the place of each of these while the player is near)
				var pk := Vector2i(int(floor(list[j][0].origin.x / 100.0)), int(floor(list[j][0].origin.z / 100.0)))
				if not parked.has(pk):
					parked[pk] = []
				parked[pk].append([list[j][0], list[j][1], mm, j, xf])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = origin
		mmi.visibility_range_end = 4000.0 if gk.z in [FERRY, AIRLINER, CRUISE] else (1400.0 if gk.z in [PYLON, WIRES, BOAT] else RANGE)
		mmi.visibility_range_end_margin = 40.0
		if gk.z in [WIRES, FENCE, PICKET, GUARD_RAIL]:
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mmi)


## One plate of a street-name sign, hanging from the pole at the origin of `xf` and running along its X:
## as long as the name needs, with the name on both faces.
func _name_plate(plate: BoxMesh, text: String, xf: Transform3D) -> void:
	var letter := 0.085                                     # metres per character at this size
	var width := maxf(0.5, float(text.length()) * letter + 0.18)
	var mid := Vector3(-width * 0.5 - 0.03, 0, 0)
	var mi := MeshInstance3D.new()
	mi.mesh = plate
	mi.transform = xf * Transform3D(Basis().scaled(Vector3(width, 1.0, 1.0)), mid)
	mi.visibility_range_end = 160.0
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	for face in [0.0, PI]:
		var turn: float = face
		var label := Label3D.new()
		label.text = text
		label.font_size = 64
		label.pixel_size = 0.0024
		label.modulate = Color(0.96, 0.96, 0.96)
		label.outline_size = 0
		label.double_sided = false
		label.transform = xf * Transform3D(Basis(Vector3.UP, turn), mid + Vector3(0, 0, 0.018 if turn == 0.0 else -0.018))
		label.visibility_range_end = 70.0
		add_child(label)


## Lettering on a sign: seen from in front only, and only from nearby.
func _letter(text: String, xf: Transform3D, pixel: float, col: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = pixel * minf(1.0, 14.0 / maxf(float(text.length()), 1.0))
	label.modulate = col
	label.outline_size = 0
	label.double_sided = false
	label.transform = xf
	label.visibility_range_end = 110.0
	add_child(label)


## Make the props of one cell solid (called when the close-up detail of that cell is built).
func solid(parent: Node3D, key: Vector2i) -> void:
	var list: Array = cells.get(key, [])
	if list.is_empty():
		return
	var body := StaticBody3D.new()
	body.name = "Props"
	for entry in list:
		var kind: int = entry[0]
		var xf: Transform3D = entry[1]
		var shape := BoxShape3D.new()
		var col := CollisionShape3D.new()
		if kind in LINEAR:
			var hw: Vector2 = SOLID[kind]
			var e := xf.basis.x
			var length := e.length()
			shape.size = Vector3(length, hw.x, hw.y * 2.0)
			var x := e / length
			var z := xf.basis.z
			col.transform = Transform3D(Basis(x, z.cross(x), z), xf.origin + e * 0.5 + Vector3(0, hw.x * 0.5, 0))
		else:
			var h: Vector3 = SOLID[kind]
			shape.size = h * 2.0
			col.transform = Transform3D(xf.basis.orthonormalized(), xf.origin + Vector3(0, h.y, 0))
		col.shape = shape
		body.add_child(col)
	parent.add_child(body)


# ------------------------------------------------------------------ models
func _box(size: Vector3, pos: Vector3, col: Color, basis := Basis()) -> Array:
	var b := BoxMesh.new()
	b.size = size
	return [b, Transform3D(basis, pos), col]


func _cyl(top: float, bottom: float, height: float, segs: int, pos: Vector3, col: Color, basis := Basis()) -> Array:
	var c := CylinderMesh.new()
	c.top_radius = top
	c.bottom_radius = bottom
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return [c, Transform3D(basis, pos), col]


## A flat triangle standing upright, facing -Z: point down (a give-way sign) or point up.
func _tri(width: float, pos: Vector3, col: Color, point_down: bool) -> Array:
	var m := PrismMesh.new()
	m.size = Vector3(width, width * 0.87, 0.03)
	return [m, Transform3D(Basis(Vector3.BACK, PI) if point_down else Basis(), pos), col]


## Models face -Z; things along a line run from x = 0 to x = 1 and are stretched to fit.
func _meshes() -> Dictionary:
	var steel := Color(0.42, 0.44, 0.46)
	var dark := Color(0.12, 0.12, 0.13)
	var wood := Color(0.36, 0.26, 0.18)
	var white := Color(0.90, 0.90, 0.87)
	var glass := Color(0.20, 0.27, 0.30)
	var red := Color(0.72, 0.08, 0.07)
	var face := Basis(Vector3.RIGHT, PI * 0.5)        # a cylinder turned so its flat end faces -Z
	var out := {}
	out[LAMP] = world._merge([
		_cyl(0.05, 0.08, 7.0, 6, Vector3(0, 3.5, 0), steel),
		_box(Vector3(0.07, 0.07, 1.5), Vector3(0, 6.95, -0.7), steel),
		_box(Vector3(0.22, 0.09, 0.55), Vector3(0, 6.9, -1.45), Color(0.93, 0.92, 0.82))])
	out[SHELTER] = world._merge([
		_box(Vector3(3.3, 0.08, 1.6), Vector3(0, 2.34, 0), dark),
		_box(Vector3(3.2, 2.2, 0.03), Vector3(0, 1.2, 0.72), glass),
		_box(Vector3(0.03, 2.2, 1.4), Vector3(-1.6, 1.2, 0.02), glass),
		_box(Vector3(0.03, 2.2, 1.4), Vector3(1.6, 1.2, 0.02), glass),
		_box(Vector3(2.4, 0.06, 0.4), Vector3(0, 0.48, 0.45), wood),
		_cyl(0.035, 0.035, 2.3, 5, Vector3(-1.6, 1.15, -0.7), dark),
		_cyl(0.035, 0.035, 2.3, 5, Vector3(1.6, 1.15, -0.7), dark),
		_cyl(0.035, 0.035, 2.6, 5, Vector3(2.1, 1.3, -0.6), steel),
		_box(Vector3(0.45, 0.45, 0.04), Vector3(2.1, 2.4, -0.6), Color(0.10, 0.25, 0.55))])
	out[BUS_SIGN] = world._merge([
		_cyl(0.035, 0.035, 2.6, 5, Vector3(0, 1.3, 0), steel),
		_box(Vector3(0.45, 0.45, 0.04), Vector3(0, 2.4, 0), Color(0.10, 0.25, 0.55))])
	out[BENCH] = world._merge([
		_box(Vector3(1.6, 0.05, 0.44), Vector3(0, 0.475, 0), wood),                  # (the seat 50 cm up: those who sit on it bend their knees)
		_box(Vector3(1.6, 0.42, 0.05), Vector3(0, 0.80, 0.23), wood),
		_box(Vector3(0.06, 0.50, 0.44), Vector3(-0.7, 0.25, 0), dark),
		_box(Vector3(0.06, 0.50, 0.44), Vector3(0.7, 0.25, 0), dark)])
	out[FENCE] = world._merge([
		_box(Vector3(1.0, 0.09, 0.03), Vector3(0.5, 0.45, 0), wood),
		_box(Vector3(1.0, 0.09, 0.03), Vector3(0.5, 0.75, 0), wood),
		_box(Vector3(1.0, 0.09, 0.03), Vector3(0.5, 1.03, 0), wood),
		_box(Vector3(0.035, 1.12, 0.09), Vector3(0.02, 0.56, 0), wood),
		_box(Vector3(0.035, 1.12, 0.09), Vector3(0.5, 0.56, 0), wood)])
	var pickets := [
		_box(Vector3(1.0, 0.07, 0.03), Vector3(0.5, 0.3, 0.02), white),
		_box(Vector3(1.0, 0.07, 0.03), Vector3(0.5, 0.78, 0.02), white),
		_box(Vector3(0.04, 1.05, 0.1), Vector3(0.02, 0.52, 0), white)]
	for k in 14:
		pickets.append(_box(Vector3(0.03, 0.9, 0.02), Vector3((float(k) + 0.5) / 14.0, 0.5, -0.01), white))
	out[PICKET] = world._merge(pickets)
	out[HEDGE] = world._merge([
		_box(Vector3(1.0, 1.25, 0.8), Vector3(0.5, 0.62, 0), Color(0.10, 0.20, 0.10)),
		_box(Vector3(1.0, 0.2, 0.6), Vector3(0.5, 1.3, 0), Color(0.13, 0.25, 0.12))])
	out[WALL] = world._merge([_box(Vector3(1.0, 1.1, 0.3), Vector3(0.5, 0.55, 0), Color(0.52, 0.51, 0.49))])
	out[RETAINING] = world._merge([_box(Vector3(1.0, 1.9, 0.4), Vector3(0.5, 0.65, 0), Color(0.46, 0.45, 0.44))])
	out[GUARD_RAIL] = world._merge([
		_box(Vector3(1.0, 0.3, 0.05), Vector3(0.5, 0.6, 0), steel),
		_box(Vector3(0.03, 0.75, 0.1), Vector3(0.02, 0.37, 0.05), steel),
		_box(Vector3(0.03, 0.75, 0.1), Vector3(0.5, 0.37, 0.05), steel)])
	out[FLAGPOLE] = world._merge([                      # (its flag waves: scripts/weather.gd, shaders/flag.gdshader)
		_cyl(0.035, 0.06, 9.0, 6, Vector3(0, 4.5, 0), white),
		_cyl(0.06, 0.06, 0.08, 6, Vector3(0, 9.03, 0), Color(0.75, 0.62, 0.25))])
	var car := [
		_box(Vector3(1.78, 0.62, 4.3), Vector3(0, 0.62, 0), Color.WHITE),
		_box(Vector3(1.6, 0.55, 2.3), Vector3(0, 1.2, 0.2), Color(0.16, 0.19, 0.21)),
		_box(Vector3(1.5, 0.08, 0.1), Vector3(0, 0.62, -2.16), Color(0.9, 0.9, 0.8)),
		_box(Vector3(1.5, 0.08, 0.1), Vector3(0, 0.66, 2.16), Color(0.6, 0.05, 0.05))]
	for sx in [-0.86, 0.86]:
		for sz in [-1.35, 1.35]:
			car.append(_cyl(0.32, 0.32, 0.2, 10, Vector3(sx, 0.32, sz), Color(0.05, 0.05, 0.05), Basis(Vector3.BACK, PI * 0.5)))
	out[CAR] = world._merge(car)
	var pole := _cyl(0.03, 0.03, 2.4, 5, Vector3(0, 1.2, 0), steel)
	out[GIVE_WAY] = world._merge([pole,
		_tri(0.9, Vector3(0, 2.2, -0.04), red, true),
		_tri(0.52, Vector3(0, 2.25, -0.055), white, true)])
	out[ROUND_SIGN] = world._merge([pole,
		_cyl(0.36, 0.36, 0.03, 16, Vector3(0, 2.2, -0.04), red, face),
		_cyl(0.27, 0.27, 0.03, 16, Vector3(0, 2.2, -0.055), white, face)])
	out[CROSSING_SIGN] = world._merge([pole,
		_box(Vector3(0.6, 0.6, 0.03), Vector3(0, 2.2, -0.04), Color(0.08, 0.22, 0.60)),
		_tri(0.44, Vector3(0, 2.2, -0.055), white, false)])
	out[SIGNAL] = world._merge([
		_cyl(0.05, 0.06, 3.4, 6, Vector3(0, 1.7, 0), steel),
		_box(Vector3(0.3, 0.9, 0.24), Vector3(0, 2.95, -0.1), dark),
		_box(Vector3(0.16, 0.16, 0.03), Vector3(0, 3.23, -0.23), Color(0.8, 0.1, 0.08)),
		_box(Vector3(0.16, 0.16, 0.03), Vector3(0, 2.95, -0.23), Color(0.85, 0.6, 0.1)),
		_box(Vector3(0.16, 0.16, 0.03), Vector3(0, 2.67, -0.23), Color(0.1, 0.6, 0.2))])
	out[POST_BOX] = world._merge([
		_cyl(0.04, 0.04, 0.9, 5, Vector3(0, 0.45, 0), dark),
		_box(Vector3(0.46, 0.6, 0.3), Vector3(0, 1.15, 0), red)])
	out[PICNIC] = world._merge([
		_box(Vector3(1.8, 0.06, 0.75), Vector3(0, 0.75, 0), wood),
		_box(Vector3(1.8, 0.05, 0.28), Vector3(0, 0.45, -0.62), wood),
		_box(Vector3(1.8, 0.05, 0.28), Vector3(0, 0.45, 0.62), wood),
		_box(Vector3(0.08, 0.75, 1.4), Vector3(-0.7, 0.37, 0), wood),
		_box(Vector3(0.08, 0.75, 1.4), Vector3(0.7, 0.37, 0), wood)])
	var lean := 0.28
	var swings := [_cyl(0.05, 0.05, 3.2, 6, Vector3(0, 2.15, 0), red, Basis(Vector3.BACK, PI * 0.5))]
	for sx in [-1.6, 1.6]:
		swings.append(_cyl(0.045, 0.045, 2.3, 5, Vector3(sx, 1.1, -0.32), red, Basis(Vector3.RIGHT, lean)))
		swings.append(_cyl(0.045, 0.045, 2.3, 5, Vector3(sx, 1.1, 0.32), red, Basis(Vector3.RIGHT, -lean)))
	for sx in [-0.7, 0.7]:
		swings.append(_box(Vector3(0.45, 0.04, 0.18), Vector3(sx, 0.5, 0), dark))
		swings.append(_box(Vector3(0.015, 1.65, 0.015), Vector3(sx - 0.2, 1.33, 0), steel))
		swings.append(_box(Vector3(0.015, 1.65, 0.015), Vector3(sx + 0.2, 1.33, 0), steel))
	out[SWINGS] = world._merge(swings)
	out[PYLON] = world._merge([
		_cyl(0.45, 0.45, 22.0, 12, Vector3(0, 11.0, 0), steel),                 # a round mast, the same width all the way up
		_box(Vector3(9.0, 0.25, 0.25), Vector3(0, 21.0, 0), steel),
		_box(Vector3(5.0, 0.2, 0.2), Vector3(0, 17.0, 0), steel)])
	out[WIRES] = world._merge([
		_box(Vector3(1.0, 0.04, 0.04), Vector3(0.5, 0, -4.2), dark),
		_box(Vector3(1.0, 0.04, 0.04), Vector3(0.5, 0, 0), dark),
		_box(Vector3(1.0, 0.04, 0.04), Vector3(0.5, 0, 4.2), dark)])
	var blue := Color(0.06, 0.20, 0.58)
	out[GIVE_WAY_ROUND] = world._merge([_cyl(0.03, 0.03, 2.9, 5, Vector3(0, 1.45, 0), steel),
		_tri(0.9, Vector3(0, 2.65, -0.04), red, true),
		_tri(0.52, Vector3(0, 2.70, -0.055), white, true),
		_cyl(0.33, 0.33, 0.03, 16, Vector3(0, 1.85, -0.04), blue, face),
		_cyl(0.2, 0.2, 0.03, 12, Vector3(0, 1.85, -0.055), white, face),
		_cyl(0.11, 0.11, 0.03, 12, Vector3(0, 1.85, -0.07), blue, face)])
	out[NAME_SIGN] = world._merge([_cyl(0.03, 0.03, 2.85, 5, Vector3(0, 1.42, 0), steel)])
	var bloom := SphereMesh.new()
	bloom.radius = 0.5
	bloom.height = 0.55
	bloom.radial_segments = 8
	bloom.rings = 3
	var leaves := SphereMesh.new()
	leaves.radius = 0.56
	leaves.height = 0.4
	leaves.radial_segments = 8
	leaves.rings = 3
	out[PLANTER] = world._merge([
		_cyl(0.55, 0.42, 0.6, 10, Vector3(0, 0.3, 0), Color(0.45, 0.44, 0.43)),
		[leaves, Transform3D(Basis(), Vector3(0, 0.66, 0)), Color(0.10, 0.25, 0.10)],
		[bloom, Transform3D(Basis(), Vector3(0, 0.80, 0)), Color(0.75, 0.10, 0.14)]])
	var hull_white := Color(0.93, 0.93, 0.91)
	out[BOAT] = world._merge([
		_box(Vector3(2.1, 0.9, 5.2), Vector3(0, 0.25, 0.3), Color.WHITE),
		_cyl(0.0, 1.05, 1.6, 4, Vector3(0, 0.25, -3.1), Color.WHITE, Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.25)),
		_box(Vector3(1.6, 0.8, 1.6), Vector3(0, 1.05, 0.2), Color(0.85, 0.85, 0.85)),
		_box(Vector3(1.5, 0.35, 0.05), Vector3(0, 1.15, -0.62), Color(0.15, 0.2, 0.25))])
	out[FERRY] = world._merge(_ferry_parts())
	out[CRUISE] = world._merge(_cruise_parts())
	# a gravestone: a plinth and an upright slab of dark granite with a rounded-off top
	var granite := Color(0.23, 0.23, 0.25)
	out[GRAVE] = world._merge([
		_box(Vector3(0.75, 0.10, 0.32), Vector3(0, 0.05, 0), Color(0.42, 0.42, 0.43)),
		_box(Vector3(0.62, 0.62, 0.14), Vector3(0, 0.41, 0), granite),
		_box(Vector3(0.50, 0.10, 0.14), Vector3(0, 0.77, 0), granite),
		_box(Vector3(0.34, 0.06, 0.14), Vector3(0, 0.85, 0), granite)])
	var wing := Color(0.86, 0.87, 0.89)
	var along := Basis(Vector3.RIGHT, PI * 0.5)
	out[AIRLINER] = world._merge([
		_cyl(1.9, 1.9, 28.0, 10, Vector3(0, 3.6, 0), hull_white, along),
		_cyl(1.9, 0.3, 4.5, 10, Vector3(0, 3.6, -16.2), hull_white, along),
		_cyl(0.5, 1.9, 6.5, 10, Vector3(0, 4.0, 17.2), hull_white, along),
		_box(Vector3(32.0, 0.35, 4.2), Vector3(0, 3.0, 0.5), wing),
		_box(Vector3(11.0, 0.25, 2.6), Vector3(0, 4.4, 18.5), wing),
		_box(Vector3(0.3, 5.2, 4.0), Vector3(0, 7.0, 18.2), Color(0.70, 0.08, 0.10)),
		_cyl(0.9, 0.9, 3.6, 8, Vector3(-5.5, 2.2, -0.8), Color(0.35, 0.36, 0.38), along),
		_cyl(0.9, 0.9, 3.6, 8, Vector3(5.5, 2.2, -0.8), Color(0.35, 0.36, 0.38), along),
		_cyl(0.12, 0.12, 2.0, 5, Vector3(0, 1.0, -11.0), dark),
		_cyl(0.14, 0.14, 2.0, 5, Vector3(-2.6, 1.0, 1.5), dark),
		_cyl(0.14, 0.14, 2.0, 5, Vector3(2.6, 1.0, 1.5), dark)])
	var rail := [
		_box(Vector3(4.0, 0.06, 0.06), Vector3(0, 1.05, 0), steel),
		_box(Vector3(4.0, 0.05, 0.05), Vector3(0, 0.55, 0), steel),
		_cyl(0.05, 0.05, 1.5, 6, Vector3(1.2, 0.75, 0.5), dark),
		_box(Vector3(0.22, 0.2, 0.45), Vector3(1.2, 1.55, 0.45), steel)]
	for k in 5:
		rail.append(_box(Vector3(0.06, 1.1, 0.06), Vector3(-2.0 + float(k), 0.55, 0), steel))
	out[VIEWPOINT] = world._merge(rail)
	return out


## A car ferry of the kind that crosses the fjord from Molde: 70 m long and the same at both ends, a dark blue hull
## with a red waterline, the car deck open from end to end under the white house, a ramp at each end, the saloon
## with its rows of windows over the car deck, a sun deck with railings, benches, life rafts and two lifeboats,
## the bridge on top with windows all round, the mast with its radars and lights, a funnel each side, fenders
## along the hull, cars on the deck. Over three hundred parts (it was seven boxes: note of 18 Nov).
func _ferry_parts() -> Array:
	var navy := Color(0.07, 0.13, 0.28)
	var white := Color(0.94, 0.94, 0.92)
	var red := Color(0.72, 0.10, 0.08)
	var glass := Color(0.09, 0.13, 0.17)
	var deck := Color(0.30, 0.32, 0.33)
	var steel := Color(0.55, 0.57, 0.60)
	var orange := Color(0.92, 0.42, 0.08)
	var black := Color(0.04, 0.04, 0.045)
	var p := []
	# the hull: the long middle, and each end drawn in toward the stem in four steps
	p.append(_box(Vector3(16.0, 4.6, 52.0), Vector3(0, 1.4, 0), navy))
	p.append(_box(Vector3(16.1, 0.5, 52.0), Vector3(0, 0.15, 0), red))
	p.append(_box(Vector3(16.15, 0.22, 52.0), Vector3(0, 3.45, 0), white))
	for e in [-1.0, 1.0]:
		var en: float = e
		for k in 4:
			var w := 15.2 - 2.6 * float(k)
			var z := (27.2 + 2.4 * float(k)) * en
			p.append(_box(Vector3(w, 4.6 - 0.25 * float(k), 2.4), Vector3(0, 1.4 + 0.125 * float(k), z), navy))
			p.append(_box(Vector3(w + 0.1, 0.5, 2.4), Vector3(0, 0.15, z), red))
			p.append(_box(Vector3(w + 0.15, 0.22, 2.4), Vector3(0, 3.45, z), white))
		# the ramp, lifted a little, with its side plates, its hoist posts and their stays
		p.append(_box(Vector3(8.6, 0.30, 7.5), Vector3(0, 5.1, 37.6 * en), deck, Basis(Vector3.RIGHT, 0.42 * en)))
		for sx in [-4.4, 4.4]:
			p.append(_box(Vector3(0.25, 0.9, 7.5), Vector3(sx, 5.5, 37.6 * en), red, Basis(Vector3.RIGHT, 0.42 * en)))
			p.append(_box(Vector3(0.45, 6.5, 0.45), Vector3(sx * 1.25, 6.9, 32.4 * en), white))
			p.append(_cyl(0.05, 0.05, 6.4, 5, Vector3(sx * 1.12, 8.3, 35.2 * en), black, Basis(Vector3.RIGHT, (PI * 0.5 - 0.55) * en)))
			p.append(_box(Vector3(0.5, 0.5, 0.5), Vector3(sx * 1.25, 10.3, 32.4 * en), orange))
		p.append(_box(Vector3(11.4, 0.4, 0.4), Vector3(0, 10.1, 32.4 * en), white))
		# bollards and a winch on the fore deck, the anchor in its pocket
		for sx2 in [-5.2, -3.6, 3.6, 5.2]:
			p.append(_cyl(0.16, 0.16, 0.6, 8, Vector3(sx2, 4.1, 30.2 * en), black))
		p.append(_box(Vector3(1.6, 0.9, 1.2), Vector3(0.0, 4.25, 29.8 * en), steel))
		p.append(_box(Vector3(0.9, 1.1, 0.2), Vector3(6.4 - 0.0, 2.6, 30.6 * en), black))
		# navigation lights
		p.append(_box(Vector3(0.25, 0.25, 0.25), Vector3(-8.6, 13.4, 3.0 * en), Color(0.9, 0.1, 0.1)))
		p.append(_box(Vector3(0.25, 0.25, 0.25), Vector3(8.6, 13.4, 3.0 * en), Color(0.1, 0.8, 0.2)))
	# the car deck, and the casings each side of it that carry the house: windows and doors along them
	p.append(_box(Vector3(15.6, 0.2, 66.0), Vector3(0, 3.78, 0), deck))
	for k in 12:
		p.append(_box(Vector3(0.12, 0.02, 3.0), Vector3(-2.4 if k % 2 == 0 else 2.4, 3.89, -27.0 + 5.0 * float(k)), Color(0.85, 0.85, 0.80)))      # lane lines
	for sgn in [-1.0, 1.0]:
		var sx3: float = sgn
		p.append(_box(Vector3(2.3, 4.6, 50.0), Vector3(6.85 * sx3, 6.1, 0), white))
		p.append(_box(Vector3(0.06, 0.18, 50.0), Vector3(8.02 * sx3, 4.2, 0), navy))
		for k in 14:
			p.append(_box(Vector3(0.06, 0.9, 1.6), Vector3(8.01 * sx3, 6.6, -21.5 + 3.3 * float(k)), glass))
		for k in 3:
			p.append(_box(Vector3(0.06, 2.0, 0.9), Vector3(8.01 * sx3, 5.0, -18.0 + 18.0 * float(k)), steel))
			p.append(_box(Vector3(0.06, 2.0, 0.9), Vector3(5.69 * sx3, 5.0, -15.0 + 15.0 * float(k)), steel))
		# fenders along the hull: old tyres on chains
		for k in 9:
			p.append(_cyl(0.42, 0.42, 0.22, 10, Vector3(8.15 * sx3, 2.6, -24.0 + 6.0 * float(k)), black, Basis(Vector3.BACK, PI * 0.5)))
			p.append(_box(Vector3(0.04, 0.9, 0.04), Vector3(8.12 * sx3, 3.2, -24.0 + 6.0 * float(k)), steel))
		# portholes low in the hull
		for k in 10:
			p.append(_cyl(0.22, 0.22, 0.06, 8, Vector3(8.03 * sx3, 2.3, -22.5 + 5.0 * float(k)), glass, Basis(Vector3.BACK, PI * 0.5)))
		# the company's colours on the side: a red and a blue slanting bar
		p.append(_box(Vector3(0.06, 2.2, 1.0), Vector3(8.03 * sx3, 6.3, -24.2), red, Basis(Vector3.RIGHT, 0.35)))
		p.append(_box(Vector3(0.06, 2.2, 1.0), Vector3(8.03 * sx3, 6.3, -22.9), Color(0.10, 0.30, 0.65), Basis(Vector3.RIGHT, 0.35)))
	# the saloon deck over the cars: its floor is the car deck's roof; windows all the way along, and across the ends
	p.append(_box(Vector3(16.0, 0.35, 52.0), Vector3(0, 8.55, 0), white))
	p.append(_box(Vector3(15.4, 2.7, 42.0), Vector3(0, 10.1, 0), white))
	for sgn2 in [-1.0, 1.0]:
		var sx4: float = sgn2
		p.append(_box(Vector3(0.06, 1.1, 40.0), Vector3(7.71 * sx4, 10.4, 0), glass))
		for k in 21:
			p.append(_box(Vector3(0.08, 1.1, 0.16), Vector3(7.72 * sx4, 10.4, -20.0 + 2.0 * float(k)), white))
		p.append(_box(Vector3(13.6, 1.1, 0.06), Vector3(0, 10.4, 21.01 * sx4), glass))
		for k in 8:
			p.append(_box(Vector3(0.16, 1.1, 0.08), Vector3(-6.8 + 1.94 * float(k), 10.4, 21.02 * sx4), white))
		p.append(_box(Vector3(0.9, 2.0, 0.08), Vector3(5.2 * sx4, 9.9, 21.03), steel))                       # a door out to each end
		p.append(_box(Vector3(0.9, 2.0, 0.08), Vector3(5.2 * sx4, 9.9, -21.03), steel))
		# the walkway outside the saloon at each end, railed
		for e2 in [-1.0, 1.0]:
			p.append(_box(Vector3(0.05, 0.05, 5.0), Vector3(7.9 * sx4, 9.75, 23.5 * float(e2)), steel))
			p.append(_box(Vector3(0.05, 0.05, 5.0), Vector3(7.9 * sx4, 9.25, 23.5 * float(e2)), steel))
			for k in 4:
				p.append(_box(Vector3(0.05, 1.05, 0.05), Vector3(7.9 * sx4, 9.25, (21.2 + 1.6 * float(k)) * float(e2)), steel))
	for e3 in [-1.0, 1.0]:
		p.append(_box(Vector3(15.8, 0.05, 0.05), Vector3(0, 9.75, 26.0 * float(e3)), steel))
		p.append(_box(Vector3(15.8, 0.05, 0.05), Vector3(0, 9.25, 26.0 * float(e3)), steel))
		for k in 9:
			p.append(_box(Vector3(0.05, 1.05, 0.05), Vector3(-7.9 + 1.975 * float(k), 9.25, 26.0 * float(e3)), steel))
	# the sun deck: the saloon's roof, railed all round, with benches, rafts in their canisters, two lifeboats in davits
	p.append(_box(Vector3(15.8, 0.25, 42.6), Vector3(0, 11.55, 0), Color(0.36, 0.44, 0.40)))
	for sgn3 in [-1.0, 1.0]:
		var sx5: float = sgn3
		for h in [12.2, 12.7]:
			p.append(_box(Vector3(0.05, 0.05, 42.4), Vector3(7.8 * sx5, h, 0), steel))
			p.append(_box(Vector3(15.6, 0.05, 0.05), Vector3(0, h, 21.2 * sx5), steel))
		for k in 15:
			p.append(_box(Vector3(0.05, 1.1, 0.05), Vector3(7.8 * sx5, 12.2, -21.0 + 3.0 * float(k)), steel))
		for k in 7:
			p.append(_box(Vector3(0.05, 1.1, 0.05), Vector3(-7.5 + 2.5 * float(k), 12.2, 21.2 * sx5), steel))
		for k in 4:
			p.append(_cyl(0.42, 0.42, 1.3, 10, Vector3(7.0 * sx5, 12.25, (11.5 + 2.0 * float(k)) * 1.0), white, Basis(Vector3.RIGHT, PI * 0.5)))    # life rafts
			p.append(_box(Vector3(0.9, 0.12, 0.3), Vector3(7.0 * sx5, 11.75, 11.5 + 2.0 * float(k)), steel))
		for k in 3:
			p.append(_box(Vector3(2.2, 0.08, 0.5), Vector3(4.2 * sx5, 12.1, -19.0 + 2.2 * float(k)), Color(0.50, 0.33, 0.18)))                     # benches
			p.append(_box(Vector3(2.2, 0.5, 0.08), Vector3(4.2 * sx5, 12.4, -18.72 + 2.2 * float(k)), Color(0.50, 0.33, 0.18)))
			for leg in [-0.9, 0.9]:
				p.append(_box(Vector3(0.08, 0.42, 0.45), Vector3(4.2 * sx5 + float(leg), 11.88, -19.0 + 2.2 * float(k)), steel))
		# a lifeboat: an orange hull under a cover, hanging from two davits
		p.append(_box(Vector3(2.2, 1.1, 6.4), Vector3(6.6 * sx5, 12.75, -9.5), orange))
		p.append(_cyl(0.0, 1.1, 1.2, 4, Vector3(6.6 * sx5, 12.75, -13.3), orange, Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.25)))
		p.append(_box(Vector3(2.3, 0.35, 6.2), Vector3(6.6 * sx5, 13.45, -9.5), white))
		for dz in [-12.0, -7.0]:
			p.append(_box(Vector3(0.22, 2.6, 0.22), Vector3(5.2 * sx5, 13.0, dz), white))
			p.append(_box(Vector3(1.9, 0.22, 0.22), Vector3(6.05 * sx5, 14.25, dz), white))
			p.append(_box(Vector3(0.04, 0.9, 0.04), Vector3(6.8 * sx5, 13.8, dz), black))
		# a funnel each side: white, with the red and blue bands and a black top, the pipes standing out of it
		p.append(_box(Vector3(1.7, 4.4, 3.4), Vector3(6.3 * sx5, 13.85, 6.0), white))
		p.append(_box(Vector3(1.75, 0.7, 3.45), Vector3(6.3 * sx5, 14.6, 6.0), red))
		p.append(_box(Vector3(1.75, 0.5, 3.45), Vector3(6.3 * sx5, 15.25, 6.0), Color(0.10, 0.30, 0.65)))
		p.append(_box(Vector3(1.75, 0.35, 3.45), Vector3(6.3 * sx5, 15.9, 6.0), black))
		for dz2 in [5.2, 6.8]:
			p.append(_cyl(0.20, 0.20, 0.9, 8, Vector3(6.3 * sx5, 16.4, dz2), black))
		for k in 5:
			p.append(_box(Vector3(0.05, 0.12, 2.6), Vector3(7.16 * sx5, 12.4 + 0.3 * float(k), 6.0), steel))         # louvres
		# a ventilator and a deck locker
		p.append(_cyl(0.3, 0.3, 1.1, 8, Vector3(3.0 * sx5, 12.2, 14.0), white))
		p.append(_cyl(0.45, 0.3, 0.3, 8, Vector3(3.0 * sx5, 12.9, 14.0), white))
		p.append(_box(Vector3(1.6, 0.8, 0.8), Vector3(2.6 * sx5, 12.05, -3.0), Color(0.80, 0.80, 0.78)))
	# the bridge: over the middle, wider than the ship (the wings stand out over the sides), windows all round
	p.append(_box(Vector3(11.0, 1.4, 8.0), Vector3(0, 12.35, 0), white))
	p.append(_box(Vector3(18.4, 2.5, 6.6), Vector3(0, 14.3, 0), white))
	p.append(_box(Vector3(18.8, 0.25, 7.2), Vector3(0, 15.65, 0), white))
	for e4 in [-1.0, 1.0]:
		p.append(_box(Vector3(18.0, 1.15, 0.06), Vector3(0, 14.6, 3.31 * float(e4)), glass, Basis(Vector3.RIGHT, -0.12 * float(e4))))
		for k in 13:
			p.append(_box(Vector3(0.12, 1.15, 0.08), Vector3(-9.0 + 1.5 * float(k), 14.6, 3.33 * float(e4)), white, Basis(Vector3.RIGHT, -0.12 * float(e4))))
		p.append(_box(Vector3(0.06, 1.15, 6.2), Vector3(9.21 * float(e4), 14.6, 0), glass))
		for k in 4:
			p.append(_box(Vector3(0.08, 1.15, 0.12), Vector3(9.22 * float(e4), 14.6, -2.4 + 1.6 * float(k)), white))
		# wipers, a searchlight, a horn
		for k in 4:
			p.append(_box(Vector3(0.04, 0.7, 0.04), Vector3(-5.2 + 3.5 * float(k), 14.5, 3.42 * float(e4)), black, Basis(Vector3.BACK, 0.4)))
		p.append(_cyl(0.28, 0.22, 0.4, 10, Vector3(4.0 * float(e4), 16.1, 2.6 * float(e4)), steel, Basis(Vector3.RIGHT, PI * 0.5)))
		p.append(_box(Vector3(0.12, 0.6, 0.12), Vector3(4.0 * float(e4), 15.9, 2.6 * float(e4)), steel))
		p.append(_cyl(0.10, 0.22, 0.7, 8, Vector3(-3.0 * float(e4), 15.95, 3.0 * float(e4)), red, Basis(Vector3.RIGHT, PI * 0.5)))
	# the mast: a lattice of four legs with a platform, two radar scanners, aerials, the lights, a flag at the stern
	for q in [[-0.5, -0.5], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.5]]:
		p.append(_box(Vector3(0.12, 5.2, 0.12), Vector3(q[0], 18.3, q[1]), white))
	for h2 in [17.0, 18.6, 20.2]:
		p.append(_box(Vector3(1.15, 0.08, 1.15), Vector3(0, h2, 0), white))
	p.append(_box(Vector3(2.4, 0.12, 1.6), Vector3(0, 20.9, 0), white))
	p.append(_box(Vector3(3.0, 0.22, 0.35), Vector3(0, 21.3, -0.4), white))
	p.append(_cyl(0.18, 0.18, 0.35, 8, Vector3(0, 21.1, -0.4), steel))
	p.append(_box(Vector3(1.8, 0.18, 0.28), Vector3(0, 19.5, 0.75), white, Basis(Vector3.UP, 0.7)))
	p.append(_cyl(0.14, 0.14, 0.3, 8, Vector3(0, 19.3, 0.75), steel))
	p.append(_box(Vector3(0.10, 2.6, 0.10), Vector3(0, 22.2, 0.3), white))
	p.append(_box(Vector3(2.2, 0.08, 0.08), Vector3(0, 22.6, 0.3), white))
	for q2 in [[-1.0, 23.6], [1.0, 23.6], [-0.6, 22.9], [0.6, 22.9]]:
		p.append(_cyl(0.02, 0.02, 1.8 if absf(float(q2[0])) > 0.8 else 0.6, 4, Vector3(q2[0], q2[1], 0.3), black))
	for q3 in [[23.3, Color(1, 1, 0.9)], [22.0, Color(1, 1, 0.9)], [21.6, Color(0.9, 0.1, 0.1)]]:
		p.append(_box(Vector3(0.2, 0.2, 0.2), Vector3(0, q3[0], 0.12), q3[1]))
	p.append(_cyl(0.04, 0.04, 3.0, 5, Vector3(0, 13.2, 20.8), white))
	p.append(_box(Vector3(0.04, 0.9, 1.3), Vector3(0, 14.2, 21.5), red))
	p.append(_box(Vector3(0.05, 0.9, 0.22), Vector3(0, 14.2, 21.2), Color(0.05, 0.15, 0.50)))
	p.append(_box(Vector3(0.05, 0.22, 1.3), Vector3(0, 14.2, 21.5), Color(0.05, 0.15, 0.50)))
	# cars and a lorry on the deck
	var paint := [Color(0.70, 0.10, 0.10), Color(0.85, 0.85, 0.86), Color(0.12, 0.12, 0.14), Color(0.15, 0.30, 0.55), Color(0.55, 0.56, 0.58), Color(0.20, 0.40, 0.25)]
	for k in 12:
		var cx := -2.4 if k % 2 == 0 else 2.4
		var cz := -24.0 + 4.6 * float(k)
		p.append(_box(Vector3(1.75, 0.75, 4.2), Vector3(cx, 4.45, cz), paint[k % 6]))
		p.append(_box(Vector3(1.6, 0.6, 2.2), Vector3(cx, 5.10, cz + 0.2), glass))
		p.append(_box(Vector3(1.62, 0.08, 2.0), Vector3(cx, 5.42, cz + 0.2), paint[k % 6]))
	p.append(_box(Vector3(2.5, 2.9, 9.5), Vector3(0.0, 5.6, 8.0), Color(0.85, 0.85, 0.83)))
	p.append(_box(Vector3(2.4, 2.4, 2.2), Vector3(0.0, 5.2, 1.8), Color(0.10, 0.30, 0.60)))
	p.append(_box(Vector3(2.3, 0.9, 0.1), Vector3(0.0, 5.7, 0.72), glass))
	return p


## A cruise ship, 180 m long, as they lie at Storkaia in summer: a dark hull with a red line and rows of portholes,
## the stem drawn out to a bow, seven white decks stepping back toward the top, each with its band of cabin windows
## and balconies divided cabin by cabin, lifeboats in a row along each side, the bridge with its wings, a pool on
## the top deck with rows of sunbeds, a funnel with a coloured band, masts, radar and satellite domes, railings.
## Over six hundred parts (it was nineteen: note of 18 Nov).
func _cruise_parts() -> Array:
	var navy := Color(0.07, 0.09, 0.16)
	var white := Color(0.94, 0.94, 0.92)
	var glass := Color(0.10, 0.14, 0.19)
	var red := Color(0.80, 0.12, 0.10)
	var orange := Color(0.92, 0.42, 0.08)
	var steel := Color(0.60, 0.62, 0.65)
	var teak := Color(0.55, 0.40, 0.24)
	var p := []
	# the hull: the long body, the bow in five steps to the stem, a rounded stern in three
	p.append(_box(Vector3(24.0, 9.0, 150.0), Vector3(0, 2.5, 4.0), navy))
	p.append(_box(Vector3(24.2, 0.5, 150.0), Vector3(0, 6.8, 4.0), red))
	p.append(_box(Vector3(24.15, 0.9, 150.0), Vector3(0, -0.2, 4.0), Color(0.45, 0.10, 0.08)))
	for k in 5:
		var w := 21.5 - 4.3 * float(k)
		var z := -73.5 - 3.6 * float(k)
		p.append(_box(Vector3(w, 9.0 + 0.5 * float(k), 3.6), Vector3(0, 2.5 + 0.25 * float(k), z), navy))
		p.append(_box(Vector3(w + 0.2, 0.5, 3.6), Vector3(0, 6.8 + 0.5 * float(k), z), red))
	for k in 3:
		p.append(_box(Vector3(22.5 - 2.6 * float(k), 9.0, 2.4), Vector3(0, 2.5, 80.2 + 2.4 * float(k)), navy))
	p.append(_cyl(1.4, 1.4, 0.6, 12, Vector3(0, 1.0, -92.0), navy, Basis(Vector3.RIGHT, PI * 0.5)))             # the bulb of the bow, at the water
	for sgn in [-1.0, 1.0]:
		var sx: float = sgn
		for row in 2:                                                                                       # portholes in two rows
			for k in 44:
				p.append(_cyl(0.26, 0.26, 0.08, 8, Vector3(12.03 * sx, 3.2 + 1.9 * float(row), -66.0 + 3.3 * float(k)), glass, Basis(Vector3.BACK, PI * 0.5)))
		p.append(_box(Vector3(0.3, 1.6, 1.2), Vector3(9.2 * sx, 5.2, -80.5), Color(0.03, 0.03, 0.03)))            # the anchor in its pocket
		p.append(_box(Vector3(0.08, 2.2, 3.2), Vector3(12.05 * sx, 2.4, 20.0), Color(0.16, 0.18, 0.24)))          # a shell door for the tenders
		p.append(_box(Vector3(0.08, 2.2, 3.2), Vector3(12.05 * sx, 2.4, -20.0), Color(0.16, 0.18, 0.24)))
	# the decks: seven, each a little shorter and narrower than the one under it
	for d in 7:
		var inset := float(d) * 0.35
		var front := -74.0 + float(d) * 3.2
		var rear := 82.0 - float(d) * 4.0
		var y := 8.5 + float(d) * 3.0
		var half_w := (23.6 - inset * 2.0) * 0.5
		p.append(_box(Vector3(half_w * 2.0, 3.0, rear - front), Vector3(0, y, (front + rear) * 0.5), white))
		p.append(_box(Vector3(half_w * 2.0 + 0.5, 0.18, rear - front + 0.6), Vector3(0, y + 1.5, (front + rear) * 0.5), white))            # the deck's edge standing out
		for sgn2 in [-1.0, 1.0]:
			var sx2: float = sgn2
			p.append(_box(Vector3(0.08, 1.5, rear - front - 5.0), Vector3((half_w + 0.02) * sx2, y + 0.25, (front + rear) * 0.5), glass))   # the band of cabin windows
			var cabins := int((rear - front - 5.0) / 3.4)
			for k in cabins + 1:                                                                               # a white divider between each two cabins
				p.append(_box(Vector3(0.5, 2.0, 0.10), Vector3((half_w + 0.22) * sx2, y + 0.3, front + 2.5 + 3.4 * float(k)), white))
			if d >= 1 and d <= 5:                                                                              # balconies: a glass front along the deck's edge
				p.append(_box(Vector3(0.05, 0.95, rear - front - 5.0), Vector3((half_w + 0.46) * sx2, y - 0.95, (front + rear) * 0.5), Color(0.55, 0.68, 0.75)))
				p.append(_box(Vector3(0.07, 0.06, rear - front - 5.0), Vector3((half_w + 0.46) * sx2, y - 0.45, (front + rear) * 0.5), steel))
		# the front of each deck: windows looking ahead; the back: an open terrace with a rail
		p.append(_box(Vector3(half_w * 2.0 - 3.0, 1.4, 0.08), Vector3(0, y + 0.25, front - 0.02), glass))
		for k in 7:
			p.append(_box(Vector3(0.18, 1.4, 0.10), Vector3(-half_w + 1.5 + (half_w * 2.0 - 3.0) * float(k) / 6.0, y + 0.25, front - 0.04), white))
		p.append(_box(Vector3(half_w * 2.0, 0.06, 0.06), Vector3(0, y + 2.6, rear + 3.6), steel))
		p.append(_box(Vector3(half_w * 2.0, 0.2, 3.8), Vector3(0, y + 1.5, rear + 1.9), teak))
		for k in 9:
			p.append(_box(Vector3(0.06, 1.0, 0.06), Vector3(-half_w + half_w * 2.0 * float(k) / 8.0, y + 2.1, rear + 3.6), steel))
	# the promenade deck under the lifeboats, and the boats: eight a side, orange under white covers, in davits
	for sgn3 in [-1.0, 1.0]:
		var sx3: float = sgn3
		p.append(_box(Vector3(1.4, 0.2, 120.0), Vector3(12.4 * sx3, 10.0, 6.0), teak))
		p.append(_box(Vector3(0.06, 0.06, 120.0), Vector3(13.05 * sx3, 11.0, 6.0), steel))
		for k in 31:
			p.append(_box(Vector3(0.06, 1.0, 0.06), Vector3(13.05 * sx3, 10.5, -54.0 + 4.0 * float(k)), steel))
		for k in 8:
			var bz := -42.0 + 13.0 * float(k)
			p.append(_box(Vector3(3.0, 1.9, 9.2), Vector3(13.0 * sx3, 13.3, bz), orange))
			p.append(_box(Vector3(3.1, 0.9, 8.6), Vector3(13.0 * sx3, 14.6, bz), white))
			p.append(_box(Vector3(0.06, 0.5, 6.0), Vector3(14.52 * sx3, 14.6, bz), glass))
			p.append(_cyl(0.0, 1.5, 1.6, 4, Vector3(13.0 * sx3, 13.3, bz - 5.4), orange, Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.25)))
			for dz in [-3.6, 3.6]:
				p.append(_box(Vector3(0.35, 3.4, 0.35), Vector3(11.9 * sx3, 14.6, bz + float(dz)), white))
				p.append(_box(Vector3(2.2, 0.35, 0.35), Vector3(12.9 * sx3, 16.2, bz + float(dz)), white))
		# the bridge wing, standing out over the side
		p.append(_box(Vector3(4.0, 2.4, 5.0), Vector3(13.0 * sx3, 30.0, -58.0), white))
		p.append(_box(Vector3(4.1, 1.0, 5.1), Vector3(13.0 * sx3, 30.3, -58.0), glass))
		p.append(_box(Vector3(0.4, 0.4, 0.4), Vector3(14.8 * sx3, 31.5, -58.0), Color(0.9, 0.1, 0.1) if sx3 < 0.0 else Color(0.1, 0.8, 0.2)))
	# the bridge: across the front of the top decks, a band of windows leaning forward, its roof with the mast
	p.append(_box(Vector3(22.0, 2.4, 10.0), Vector3(0, 30.0, -58.0), white))
	p.append(_box(Vector3(21.0, 1.1, 0.1), Vector3(0, 30.3, -63.05), glass, Basis(Vector3.RIGHT, 0.14)))
	for k in 15:
		p.append(_box(Vector3(0.14, 1.1, 0.12), Vector3(-10.5 + 1.5 * float(k), 30.3, -63.08), white, Basis(Vector3.RIGHT, 0.14)))
	p.append(_box(Vector3(22.6, 0.3, 10.8), Vector3(0, 31.35, -58.0), white))
	for q in [[-1.2, -56.0], [1.2, -56.0], [0.0, -54.0]]:
		p.append(_box(Vector3(0.3, 9.0, 0.3), Vector3(q[0], 36.0, q[1]), white))
	p.append(_box(Vector3(5.0, 0.3, 1.2), Vector3(0, 38.5, -55.5), white))
	p.append(_box(Vector3(4.2, 0.4, 0.5), Vector3(0, 39.2, -56.0), white))
	p.append(_box(Vector3(2.6, 0.3, 0.4), Vector3(0, 36.6, -56.6), white, Basis(Vector3.UP, 0.6)))
	p.append(_box(Vector3(0.2, 4.0, 0.2), Vector3(0, 42.0, -55.0), white))
	for k in 3:
		p.append(_box(Vector3(0.3, 0.3, 0.3), Vector3(0, 40.4 + 1.4 * float(k), -55.3), Color(1.0, 1.0, 0.9) if k != 1 else Color(0.9, 0.1, 0.1)))
	for q2 in [[-7.0, -52.0, 1.5], [7.0, -52.0, 1.5], [-5.0, 46.0, 1.2], [5.0, 46.0, 1.2], [0.0, -48.0, 1.0]]:      # satellite domes
		var ball := SphereMesh.new()
		ball.radius = q2[2]
		ball.height = float(q2[2]) * 2.0
		ball.radial_segments = 12
		ball.rings = 6
		p.append([ball, Transform3D(Basis(), Vector3(q2[0], 32.6 + float(q2[2]), q2[1])), white])
		p.append(_cyl(0.5, 0.7, 1.2, 8, Vector3(q2[0], 32.0, q2[1]), white))
	# the top deck: teak, a pool with a blue floor, sunbeds in rows, a windbreak of glass, a bar under a canopy
	p.append(_box(Vector3(19.0, 0.2, 84.0), Vector3(0, 31.2, -4.0), teak))
	p.append(_box(Vector3(8.0, 0.25, 14.0), Vector3(0, 31.3, -18.0), white))
	p.append(_box(Vector3(6.8, 0.2, 12.8), Vector3(0, 31.38, -18.0), Color(0.15, 0.55, 0.75)))
	p.append(_cyl(1.6, 1.6, 0.3, 12, Vector3(-6.0, 31.4, -6.0), Color(0.15, 0.55, 0.75)))
	p.append(_cyl(1.6, 1.6, 0.3, 12, Vector3(6.0, 31.4, -6.0), Color(0.15, 0.55, 0.75)))
	for sgn4 in [-1.0, 1.0]:
		var sx4: float = sgn4
		p.append(_box(Vector3(0.06, 1.8, 84.0), Vector3(9.5 * sx4, 32.2, -4.0), Color(0.55, 0.68, 0.75)))
		for k in 22:
			p.append(_box(Vector3(0.10, 1.9, 0.10), Vector3(9.5 * sx4, 32.2, -46.0 + 4.0 * float(k)), steel))
		for k in 16:
			var lz := -40.0 + 2.2 * float(k)
			if lz > -26.5 and lz < -9.5:
				continue
			p.append(_box(Vector3(0.7, 0.12, 1.9), Vector3(7.6 * sx4, 31.55, lz), white))
			p.append(_box(Vector3(0.7, 0.5, 0.1), Vector3(7.6 * sx4, 31.8, lz + 0.9), white, Basis(Vector3.RIGHT, 0.5)))
			p.append(_box(Vector3(0.6, 0.06, 1.2), Vector3(7.6 * sx4, 31.63, lz - 0.2), [Color(0.15, 0.35, 0.65), Color(0.85, 0.75, 0.2), red][k % 3]))
		for k in 5:
			p.append(_box(Vector3(0.7, 0.12, 1.9), Vector3(5.2 * sx4, 31.55, -30.0 + 2.2 * float(k) if k < 2 else 2.0 + 2.2 * float(k)), white))
	p.append(_box(Vector3(9.0, 0.25, 6.0), Vector3(0, 34.2, 12.0), white))
	for q3 in [[-4.2, 9.4], [4.2, 9.4], [-4.2, 14.6], [4.2, 14.6]]:
		p.append(_box(Vector3(0.2, 2.9, 0.2), Vector3(q3[0], 32.7, q3[1]), steel))
	p.append(_box(Vector3(6.0, 1.1, 1.2), Vector3(0, 31.85, 13.5), teak))
	# the funnel: raked, navy with a red band and a white one, the pipes in its top; a second mast behind it
	p.append(_cyl(2.6, 3.4, 9.5, 12, Vector3(0, 35.8, 30.0), navy, Basis(Vector3.RIGHT, 0.10)))
	p.append(_cyl(2.95, 3.05, 1.3, 12, Vector3(0, 37.4, 30.15), red, Basis(Vector3.RIGHT, 0.10)))
	p.append(_cyl(2.82, 2.9, 0.5, 12, Vector3(0, 38.6, 30.25), white, Basis(Vector3.RIGHT, 0.10)))
	for q4 in [[-0.9, 0.0], [0.9, 0.0], [0.0, 1.0]]:
		p.append(_cyl(0.35, 0.35, 1.6, 8, Vector3(q4[0], 41.2, 30.5 + float(q4[1])), Color(0.05, 0.05, 0.05)))
	p.append(_box(Vector3(9.0, 4.0, 12.0), Vector3(0, 32.8, 30.0), white))
	for k in 6:
		p.append(_box(Vector3(9.1, 0.25, 0.4), Vector3(0, 31.6 + 0.6 * float(k), 24.2), steel))
	p.append(_box(Vector3(0.3, 7.0, 0.3), Vector3(0, 36.0, 44.0), white))
	p.append(_box(Vector3(4.0, 0.25, 0.25), Vector3(0, 38.6, 44.0), white))
	# the bow deck: winches, bollards, the breakwater; and the ship's name in a dark band (letters are not drawn)
	for q5 in [[-5.0, -80.0], [5.0, -80.0], [0.0, -84.0]]:
		p.append(_cyl(0.9, 0.9, 1.2, 10, Vector3(q5[0], 8.4, q5[1]), steel, Basis(Vector3.BACK, PI * 0.5)))
		p.append(_box(Vector3(1.6, 0.8, 1.6), Vector3(q5[0], 7.7, q5[1]), Color(0.30, 0.31, 0.33)))
	for k in 6:
		p.append(_cyl(0.25, 0.25, 0.8, 8, Vector3(-7.5 + 3.0 * float(k), 7.7, -76.0), Color(0.05, 0.05, 0.05)))
	p.append(_box(Vector3(14.0, 1.2, 0.3), Vector3(0, 7.9, -74.8), white, Basis(Vector3.UP, 0.0)))
	p.append(_box(Vector3(0.1, 4.0, 0.1), Vector3(0, 9.5, -90.5), white))
	p.append(_box(Vector3(0.06, 1.0, 1.5), Vector3(0, 11.0, -89.7), red))
	p.append(_box(Vector3(0.1, 5.0, 0.1), Vector3(0, 10.0, 85.5), white))
	p.append(_box(Vector3(0.06, 1.2, 1.9), Vector3(0, 11.8, 86.5), red))
	p.append(_box(Vector3(0.07, 1.2, 0.3), Vector3(0, 11.8, 86.1), Color(0.05, 0.15, 0.50)))
	p.append(_box(Vector3(0.07, 0.3, 1.9), Vector3(0, 11.8, 86.5), Color(0.05, 0.15, 0.50)))
	return p
