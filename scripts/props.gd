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
	LAMP: Vector3(0.1, 3.5, 0.1), SHELTER: Vector3(1.6, 1.15, 0.75), BUS_SIGN: Vector3(0.06, 1.3, 0.06), BENCH: Vector3(0.8, 0.45, 0.28),
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
			var xf: Transform3D = list[j][0]
			xf.origin -= origin
			mm.set_instance_transform(j, xf)
			if mm.use_colors:
				mm.set_instance_color(j, list[j][1])
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
		_box(Vector3(1.6, 0.05, 0.42), Vector3(0, 0.45, 0), wood),
		_box(Vector3(1.6, 0.4, 0.05), Vector3(0, 0.72, 0.22), wood),
		_box(Vector3(0.06, 0.45, 0.42), Vector3(-0.7, 0.225, 0), dark),
		_box(Vector3(0.06, 0.45, 0.42), Vector3(0.7, 0.225, 0), dark)])
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
	out[FLAGPOLE] = world._merge([
		_cyl(0.035, 0.06, 9.0, 6, Vector3(0, 4.5, 0), white),
		_box(Vector3(0.02, 0.22, 1.6), Vector3(0, 8.6, 0.85), red),
		_box(Vector3(0.025, 0.07, 1.6), Vector3(0, 8.6, 0.85), Color(0.08, 0.15, 0.45))])
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
	out[FERRY] = world._merge([
		_box(Vector3(16.0, 5.0, 70.0), Vector3(0, 1.2, 0), Color(0.08, 0.14, 0.30)),
		_cyl(0.0, 8.0, 8.0, 4, Vector3(0, 1.2, -39.0), Color(0.08, 0.14, 0.30), Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.25)),
		_box(Vector3(15.0, 3.0, 56.0), Vector3(0, 5.2, 2.0), hull_white),
		_box(Vector3(13.0, 2.6, 34.0), Vector3(0, 8.0, -4.0), hull_white),
		_box(Vector3(12.0, 2.4, 7.0), Vector3(0, 10.5, -17.0), hull_white),
		_box(Vector3(12.2, 0.9, 0.1), Vector3(0, 10.7, -20.55), Color(0.10, 0.14, 0.18)),
		_cyl(1.3, 1.6, 5.0, 8, Vector3(0, 11.8, 6.0), Color(0.75, 0.10, 0.08))])
	# a cruise ship, 180 m long: dark hull, white decks stepping back toward the top, rows of windows, a funnel
	var navy := Color(0.07, 0.09, 0.16)
	var glass_band := Color(0.10, 0.14, 0.19)
	var parts := [
		_box(Vector3(24.0, 9.0, 160.0), Vector3(0, 2.5, 4.0), navy),
		_cyl(0.0, 12.0, 9.0, 4, Vector3(0, 2.5, -84.0), navy, Basis(Vector3.RIGHT, -PI * 0.5) * Basis(Vector3.UP, PI * 0.25)),
		_box(Vector3(24.2, 0.5, 160.0), Vector3(0, 6.8, 4.0), Color(0.80, 0.12, 0.10)),
		_cyl(2.6, 3.2, 9.0, 10, Vector3(0, 34.5, 30.0), navy),
		_box(Vector3(18.0, 2.2, 10.0), Vector3(0, 30.0, -58.0), hull_white)]
	for d in 7:
		var inset := float(d) * 0.35
		var front := -74.0 + float(d) * 3.2
		var rear := 82.0 - float(d) * 4.0
		var y := 8.5 + float(d) * 3.0
		parts.append(_box(Vector3(23.6 - inset * 2.0, 3.0, rear - front), Vector3(0, y, (front + rear) * 0.5), hull_white))
		parts.append(_box(Vector3(23.7 - inset * 2.0, 1.1, rear - front - 4.0), Vector3(0, y + 0.3, (front + rear) * 0.5), glass_band))
	out[CRUISE] = world._merge(parts)
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
