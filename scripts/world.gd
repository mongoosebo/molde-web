extends Node3D
## Builds Molde from the files in res://world/ (made by tools/build_map.py):
## terrain, sea, buildings, trees and street names.

const Paths := preload("res://scripts/paths.gd")
var DIR: String = Paths.world      # res://world/, or /world/ in a browser
const FCELL := 100            # the 1 m terrain is handled in cells this many metres across
const FN := 103               # heights along the side of a cell: 101, plus one more all round
const TR := 3                 # 1 m terrain cells kept around the player, in each direction
const BCHUNK := 100.0         # building mesh chunk, metres (the same cells as scripts/detail.gd)
const TREE_CHUNK := 320.0
const TREE_RANGE := 2600.0    # how far trees are drawn at all
const TREE_NEAR := 420.0      # and how far in full; beyond that each is a plain cone or ball

var x0 := 0.0
var z0 := 0.0
var x1 := 0.0
var z1 := 0.0
var cell := 10.0
var gw := 0
var gh := 0
var heights := PackedFloat32Array()
var meta := {}
var spawn := Vector2.ZERO
var lat0 := 0.0
var lon0 := 0.0

var _noise_tex: NoiseTexture2D
var _fw := 0                  # the 1 m grid: size, strips of columns on disk, 16-bit steps
var _fh := 0
var _strip := 1000
var _fscale := 0.02
var _foffset := -40.0
var _fine_files: Array = []
var _fine_cache := {}         # cell -> PackedFloat32Array (FN x FN)
var _fine_range := {}         # cell -> Vector2(lowest, highest)
var _hk := Vector2i(-99999, -99999)
var _hc := PackedFloat32Array()
var _water_mat: ShaderMaterial
var _water_normal: NoiseTexture2D
var _terrain_mat: ShaderMaterial
var _near_mat: ShaderMaterial
var _near_mesh: ArrayMesh
var _near_root: Node3D
var _near := {}               # cell -> Node3D (1 m terrain with collision)
var _near_queue: Array = []
var _near_want := Vector2i(-99999, -99999)
var _street_names := PackedStringArray()
var _street_grid := {}        # Vector2i (50 m cell) -> PackedFloat32Array [x, z, name index, ...]
var _places: Array = []
var _fire_lights: Array = []
var _time := 0.0
var detail                    # scripts/detail.gd: close-up buildings and roads around the player
var props                     # scripts/props.gd: street furniture


class ChunkData:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var c := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()


# ------------------------------------------------------------------ queries
## Height of the ground, from the 1 m terrain.
func height_at(x: float, z: float) -> float:
	x = clampf(x, x0, x1 - 0.01)
	z = clampf(z, z0, z1 - 0.01)
	var kx := int(floor(x / FCELL))
	var kz := int(floor(z / FCELL))
	if kx != _hk.x or kz != _hk.y:
		_hk = Vector2i(kx, kz)
		_hc = _fine_cell(_hk)
	var fx := x - float(kx * FCELL) + 1.0
	var fz := z - float(kz * FCELL) + 1.0
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i := iz * FN + ix
	return lerpf(lerpf(_hc[i], _hc[i + 1], tx), lerpf(_hc[i + FN], _hc[i + FN + 1], tx), tz)


## Height from the 10 m grid of the far terrain: rough, but needs nothing loaded.
func coarse_at(x: float, z: float) -> float:
	var fx := clampf((x - x0) / cell, 0.0, float(gw) - 1.001)
	var fz := clampf((z - z0) / cell, 0.0, float(gh) - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - float(ix)
	var tz := fz - float(iz)
	var i := iz * gw + ix
	return lerpf(lerpf(heights[i], heights[i + 1], tx), lerpf(heights[i + gw], heights[i + gw + 1], tx), tz)


## The 1 m heights of one cell (FN x FN, starting one metre outside its corner), read from disk on
## first use.
func _fine_cell(k: Vector2i) -> PackedFloat32Array:
	var got = _fine_cache.get(k)
	if got != null:
		return got
	var out := PackedFloat32Array()
	out.resize(FN * FN)
	var ix0 := k.x * FCELL - int(x0) - 1
	var iz0 := k.y * FCELL - int(z0) - 1
	var ca := clampi(ix0, 0, _fw - 1)
	var cb := clampi(ix0 + FN - 1, 0, _fw - 1)
	var lo := INF
	var hi := -INF
	var o := 0
	for r in FN:
		var iz := clampi(iz0 + r, 0, _fh - 1)
		var row := PackedByteArray()
		var c := ca
		while c <= cb:
			var si := c / _strip
			var sw := mini(_strip, _fw - si * _strip)
			var c_in := c - si * _strip
			var n := mini(cb - c + 1, sw - c_in)
			var f: FileAccess = _fine_files[si]
			f.seek((iz * sw + c_in) * 2)
			row.append_array(f.get_buffer(n * 2))
			c += n
		for j in FN:
			var h := float(row.decode_u16((clampi(ix0 + j, ca, cb) - ca) * 2)) * _fscale + _foffset
			out[o] = h
			o += 1
			lo = minf(lo, h)
			hi = maxf(hi, h)
	_fine_cache[k] = out
	_fine_range[k] = Vector2(lo, hi)
	return out


func ground_basis(x: float, z: float, yaw: float) -> Basis:
	var up := Vector3(height_at(x - 1.0, z) - height_at(x + 1.0, z), 2.0, height_at(x, z - 1.0) - height_at(x, z + 1.0)).normalized()
	var fwd := Vector3(sin(yaw), 0.0, cos(yaw))
	var bz := (fwd - up * fwd.dot(up)).normalized()
	return Basis(up.cross(bz), up, bz)


## Where am I? Returns {"district": String, "street": String}.
func locate(x: float, z: float) -> Dictionary:
	var street := ""
	var best := 45.0 * 45.0
	var c := Vector2i(int(floor(x / 50.0)), int(floor(z / 50.0)))
	for dz in range(-1, 2):
		for dx in range(-1, 2):
			var k := Vector2i(c.x + dx, c.y + dz)
			if not _street_grid.has(k):
				continue
			var arr: PackedFloat32Array = _street_grid[k]
			var i := 0
			while i < arr.size():
				var d := (arr[i] - x) * (arr[i] - x) + (arr[i + 1] - z) * (arr[i + 1] - z)
				if d < best:
					best = d
					street = _street_names[int(arr[i + 2])]
				i += 3
	var district := ""
	var best_d := 1300.0 * 1300.0
	for p in _places:
		var px: float = p["x"]
		var pz: float = p["z"]
		var d2 := (px - x) * (px - x) + (pz - z) * (pz - z)
		if d2 < best_d:
			best_d = d2
			district = p["name"]
	var h := height_at(x, z)
	if h < 0.0:
		district = "Moldefjorden"
	elif district == "" or (h > 140.0 and best_d > 500.0 * 500.0):
		district = "Moldemarka"
	return {"district": district, "street": street}


func to_latlon(x: float, z: float) -> Vector2:
	return Vector2(lat0 - z / 111430.0, lon0 + x / (111320.0 * cos(deg_to_rad(lat0))))


# ------------------------------------------------------------------ build
func build(hud) -> void:
	hud.set_loading("Reading the map…")
	await get_tree().process_frame
	_load_meta()
	hud.set_loading("Raising the terrain…")
	await get_tree().process_frame
	_build_terrain()
	_build_water()
	_build_backdrop()
	_build_rivers()
	detail = Node3D.new()
	detail.name = "Detail"
	detail.set_script(load("res://scripts/detail.gd"))
	add_child(detail)
	detail.setup(self)
	hud.set_loading("Building the town…")
	await get_tree().process_frame
	_build_buildings()
	var lm := Node3D.new()
	lm.name = "Landmarks"
	lm.set_script(load("res://scripts/monuments.gd"))
	add_child(lm)
	lm.build_all(self, meta)
	hud.set_loading("Planting Moldemarka…")
	await get_tree().process_frame
	_build_trees()
	props = Node3D.new()
	props.name = "Props"
	props.set_script(load("res://scripts/props.gd"))
	add_child(props)
	props.build(self)
	hud.set_loading("Finishing the streets…")
	await get_tree().process_frame
	_build_wrecks()
	_build_fires()
	_build_streets()
	await get_tree().process_frame


func _load_meta() -> void:
	meta = JSON.parse_string(FileAccess.get_file_as_string(DIR + "meta.json"))
	x0 = meta["x0"]
	z0 = meta["z0"]
	x1 = meta["x1"]
	z1 = meta["z1"]
	cell = meta["cell"]
	gw = int(meta["gw"])
	gh = int(meta["gh"])
	lat0 = meta["lat0"]
	lon0 = meta["lon0"]
	var s: Array = meta["spawn"]
	spawn = Vector2(s[0], s[1])
	var fine: Dictionary = meta["fine"]
	_fw = int(fine["w"])
	_fh = int(fine["h"])
	_strip = int(fine["strip"])
	_fscale = fine["scale"]
	_foffset = fine["offset"]
	for i in (_fw + _strip - 1) / _strip:
		_fine_files.append(FileAccess.open(DIR + "h1/x%02d.bin" % i, FileAccess.READ))
	heights = FileAccess.get_file_as_bytes(DIR + "height.bin").to_float32_array()
	assert(heights.size() == gw * gh, "height.bin does not match meta.json")
	for p in meta["places"]:
		if p["kind"] in ["suburb", "quarter", "neighbourhood", "town", "locality"]:
			_places.append(p)

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.seamless = true
	_noise_tex.generate_mipmaps = true
	_noise_tex.noise = noise


func _build_terrain() -> void:
	var himg := Image.create_from_data(gw, gh, false, Image.FORMAT_RF, heights.to_byte_array())
	var htex := ImageTexture.create_from_image(himg)
	var mimg := Image.new()
	mimg.load_png_from_buffer(FileAccess.get_file_as_bytes(DIR + "mask.png"))
	mimg.generate_mipmaps()
	var mtex := ImageTexture.create_from_image(mimg)

	var size := Vector2(x1 - x0, z1 - z0)
	var plane := PlaneMesh.new()
	plane.size = size
	plane.subdivide_width = gw - 2
	plane.subdivide_depth = gh - 2

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/terrain.gdshader")
	mat.set_shader_parameter("height_tex", htex)
	mat.set_shader_parameter("grid_size", Vector2(gw, gh))
	mat.set_shader_parameter("cell", cell)
	_terrain_mat = mat
	_near_mat = ShaderMaterial.new()
	_near_mat.shader = load("res://shaders/terrain_near.gdshader")
	var m2img := Image.new()
	m2img.load_png_from_buffer(FileAccess.get_file_as_bytes(DIR + "mask2.png"))
	m2img.generate_mipmaps()
	var m2tex := ImageTexture.create_from_image(m2img)
	var detail_tex := {}
	for nm in ["turf_albedo", "turf_normal", "stone_albedo", "stone_normal"]:
		var img := Image.new()
		img.load_png_from_buffer(FileAccess.get_file_as_bytes(DIR + "textures/" + nm + ".png"))
		img.generate_mipmaps()
		detail_tex[nm] = ImageTexture.create_from_image(img)
	for m in [mat, _near_mat]:
		m.set_shader_parameter("mask2_tex", m2tex)
		m.set_shader_parameter("turf_tex", detail_tex["turf_albedo"])
		m.set_shader_parameter("turf_nrm", detail_tex["turf_normal"])
		m.set_shader_parameter("stone_tex", detail_tex["stone_albedo"])
		m.set_shader_parameter("stone_nrm", detail_tex["stone_normal"])
		m.set_shader_parameter("mask_tex", mtex)
		m.set_shader_parameter("noise_tex", _noise_tex)
		m.set_shader_parameter("world_origin", Vector2(x0, z0))
		m.set_shader_parameter("world_size", size)

	var mi := MeshInstance3D.new()
	mi.name = "Terrain"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
	mi.custom_aabb = AABB(Vector3(-size.x * 0.5, -40.0, -size.y * 0.5), Vector3(size.x, 760.0, size.y))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)

	_near_root = Node3D.new()
	_near_root.name = "TerrainNear"
	add_child(_near_root)
	_near_mesh = _make_near_mesh()


## The flat 1 m grid every near cell is drawn with, and a skirt along its four edges.
func _make_near_mesh() -> ArrayMesh:
	var n := FCELL + 1
	var v := PackedVector3Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()
	for iz in n:
		for ix in n:
			v.append(Vector3(ix - FCELL * 0.5, 0.0, iz - FCELL * 0.5))
			uv2.append(Vector2.ZERO)
	for iz in FCELL:
		for ix in FCELL:
			var a := iz * n + ix
			idx.append(a); idx.append(a + 1); idx.append(a + n)
			idx.append(a + 1); idx.append(a + n + 1); idx.append(a + n)
	for edge in 4:
		var first := v.size()
		for i in n:
			var g := i if edge == 0 else (FCELL * n + i if edge == 1 else (i * n if edge == 2 else i * n + FCELL))
			v.append(v[g])
			uv2.append(Vector2(1.0, 0.0))
			if i > 0:
				var gp := g - (1 if edge < 2 else n)
				idx.append(gp); idx.append(g); idx.append(first + i - 1)
				idx.append(g); idx.append(first + i); idx.append(first + i - 1)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV2] = uv2
	arrays[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## One cell of 1 m terrain: drawn from its own height texture, solid as a height field.
func _make_near(k: Vector2i) -> Node3D:
	var data := _fine_cell(k)
	var rng: Vector2 = _fine_range[k]
	var node := Node3D.new()
	node.position = Vector3((k.x + 0.5) * FCELL, 0.0, (k.y + 0.5) * FCELL)
	var mat: ShaderMaterial = _near_mat.duplicate()
	mat.set_shader_parameter("height_tex", ImageTexture.create_from_image(
		Image.create_from_data(FN, FN, false, Image.FORMAT_RF, data.to_byte_array())))
	var mi := MeshInstance3D.new()
	mi.mesh = _near_mesh
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-FCELL * 0.5, rng.x - 5.0, -FCELL * 0.5), Vector3(FCELL, rng.y - rng.x + 6.0, FCELL))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	node.add_child(mi)
	var inner := PackedFloat32Array()
	for r in range(1, FCELL + 2):
		inner.append_array(data.slice(r * FN + 1, r * FN + FCELL + 2))
	var shape := HeightMapShape3D.new()
	shape.map_width = FCELL + 1
	shape.map_depth = FCELL + 1
	shape.map_data = inner
	var col := CollisionShape3D.new()
	col.shape = shape
	var body := StaticBody3D.new()
	body.add_child(col)
	node.add_child(body)
	_near_root.add_child(node)
	return node


## Running water (world/water.bin: ribbons along rivers and streams, flowing downstream) and the
## still surfaces of the lakes (world/lakes.bin).
func _build_rivers() -> void:
	var data := FileAccess.get_file_as_bytes(DIR + "water.bin").to_float32_array()
	var v := PackedVector3Array()
	var nrm := PackedVector3Array()
	var uv := PackedVector2Array()
	var col := PackedColorArray()
	var tan := PackedFloat32Array()
	var i := 0
	while i + 3 <= data.size():
		var n := int(data[i])
		var half := data[i + 1]
		i += 3
		var along := 0.0
		var prev_l := Vector3.ZERO
		var prev_r := Vector3.ZERO
		var prev_uv := 0.0
		var prev_steep := 0.0
		for k in n:
			var p := Vector3(data[i + k * 3], data[i + k * 3 + 2], data[i + k * 3 + 1])
			var a := k - 1 if k > 0 else 0
			var b := k + 1 if k < n - 1 else n - 1
			var pa := Vector3(data[i + a * 3], data[i + a * 3 + 2], data[i + a * 3 + 1])
			var pb := Vector3(data[i + b * 3], data[i + b * 3 + 2], data[i + b * 3 + 1])
			var dir := pb - pa
			var flat := Vector3(dir.x, 0, dir.z)
			var run := maxf(flat.length(), 0.01)
			var side := Vector3(flat.z, 0, -flat.x) / run
			var steep := clampf((pa.y - pb.y) / run * 2.5, 0.0, 1.0)
			var l := p + side * (half + 0.35)
			var r := p - side * (half + 0.35)
			if k > 0:
				along += Vector2(p.x - data[i + (k - 1) * 3], p.z - data[i + (k - 1) * 3 + 1]).length()
				var uv1 := along / 3.0
				for q in [[prev_l, 0.0, prev_uv, prev_steep], [prev_r, 1.0, prev_uv, prev_steep], [r, 1.0, uv1, steep],
						[prev_l, 0.0, prev_uv, prev_steep], [r, 1.0, uv1, steep], [l, 0.0, uv1, steep]]:
					v.append(q[0])
					nrm.append(Vector3.UP)
					uv.append(Vector2(q[1], q[2]))
					col.append(Color(q[3], 0, 0))
					tan.append(-side.x); tan.append(0.0); tan.append(-side.z); tan.append(1.0)
			prev_l = l
			prev_r = r
			prev_uv = along / 3.0
			prev_steep = steep
		i += n * 3
	if not v.is_empty():
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = v
		arrays[Mesh.ARRAY_NORMAL] = nrm
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_COLOR] = col
		arrays[Mesh.ARRAY_TANGENT] = tan
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := ShaderMaterial.new()
		mat.shader = load("res://shaders/river.gdshader")
		mat.set_shader_parameter("normal_tex", _water_normal)
		mat.set_shader_parameter("noise_tex", _noise_tex)
		var mi := MeshInstance3D.new()
		mi.name = "Rivers"
		mi.mesh = mesh
		mi.material_override = mat
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	# lakes
	var ld := FileAccess.get_file_as_bytes(DIR + "lakes.bin").to_float32_array()
	var lv := PackedVector3Array()
	var ln := PackedVector3Array()
	var j := 0
	while j + 2 <= ld.size():
		var nt := int(ld[j])
		var level := ld[j + 1]
		j += 2
		for k in nt * 3:
			lv.append(Vector3(ld[j + k * 2], level, ld[j + k * 2 + 1]))
			ln.append(Vector3.UP)
		j += nt * 6
	if not lv.is_empty():
		var arrays2 := []
		arrays2.resize(Mesh.ARRAY_MAX)
		arrays2[Mesh.ARRAY_VERTEX] = lv
		arrays2[Mesh.ARRAY_NORMAL] = ln
		var lmesh := ArrayMesh.new()
		lmesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays2)
		var lmat: ShaderMaterial = _water_mat.duplicate()
		lmat.render_priority = 0
		var li := MeshInstance3D.new()
		li.name = "Lakes"
		li.mesh = lmesh
		li.material_override = lmat
		li.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(li)


## The mountains and coast far outside the map (world/backdrop.bin: a coarse grid of real heights).
func _build_backdrop() -> void:
	if not meta.has("backdrop"):
		return
	var n := int(meta["backdrop"]["n"])
	var half: float = meta["backdrop"]["half"]
	var data := FileAccess.get_file_as_bytes(DIR + "backdrop.bin")
	var tex := ImageTexture.create_from_image(Image.create_from_data(n, n, false, Image.FORMAT_RF, data))
	var plane := PlaneMesh.new()
	plane.size = Vector2(half * 2.0, half * 2.0)
	plane.subdivide_width = n - 2
	plane.subdivide_depth = n - 2
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/backdrop.gdshader")
	mat.set_shader_parameter("height_tex", tex)
	mat.set_shader_parameter("noise_tex", _noise_tex)
	mat.set_shader_parameter("size", half * 2.0)
	mat.set_shader_parameter("grid_n", float(n))
	mat.set_shader_parameter("map_rect", Vector4(x0, z0, x1, z1))
	var mi := MeshInstance3D.new()
	mi.name = "Backdrop"
	mi.mesh = plane
	mi.material_override = mat
	mi.custom_aabb = AABB(Vector3(-half, -40.0, -half), Vector3(half * 2.0, 2200.0, half * 2.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


func _build_water() -> void:
	var noise := FastNoiseLite.new()
	noise.frequency = 0.02
	noise.fractal_octaves = 3
	var ntex := NoiseTexture2D.new()
	ntex.width = 512
	ntex.height = 512
	ntex.seamless = true
	ntex.as_normal_map = true
	ntex.bump_strength = 6.0
	ntex.generate_mipmaps = true
	ntex.noise = noise
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/water.gdshader")
	mat.set_shader_parameter("normal_tex", ntex)
	_water_mat = mat
	_water_normal = ntex
	var plane := PlaneMesh.new()
	plane.size = Vector2(120000.0, 120000.0)
	var mi := MeshInstance3D.new()
	mi.name = "Sea"
	mi.mesh = plane
	mi.material_override = mat
	mi.position = Vector3((x0 + x1) * 0.5, 0.0, (z0 + z1) * 0.5)
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)


# ------------------------------------------------------------------ buildings
func _quad(cd: ChunkData, a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, u0: float, u1: float, ybase: float, flags: Vector2) -> void:
	# a, b on the ground; d above a, c above b.
	var nrm := (c - a).cross(d - a)
	if nrm.length_squared() < 1e-8:
		return
	nrm = nrm.normalized()
	cd.v.append(a); cd.v.append(d); cd.v.append(c)
	cd.v.append(a); cd.v.append(c); cd.v.append(b)
	cd.uv.append(Vector2(u0, a.y - ybase)); cd.uv.append(Vector2(u0, d.y - ybase)); cd.uv.append(Vector2(u1, c.y - ybase))
	cd.uv.append(Vector2(u0, a.y - ybase)); cd.uv.append(Vector2(u1, c.y - ybase)); cd.uv.append(Vector2(u1, b.y - ybase))
	for i in 6:
		cd.n.append(nrm)
		cd.c.append(col)
		cd.uv2.append(flags)


func _tri_up(cd: ChunkData, a: Vector3, b: Vector3, c: Vector3, col: Color) -> void:
	var nrm := (c - a).cross(b - a)
	if nrm.y < 0.0:
		var t := b
		b = c
		c = t
		nrm = -nrm
	if nrm.length_squared() < 1e-8:
		return
	nrm = nrm.normalized()
	cd.v.append(a); cd.v.append(b); cd.v.append(c)
	for p in [a, b, c]:
		cd.n.append(nrm)
		cd.c.append(col)
		cd.uv.append(Vector2(p.x, p.z))
		cd.uv2.append(Vector2(1.0, 0.0))


## An upright quad between two points on the map, from `lo` up to ya / yb, facing `out`.
func _upright(cd: ChunkData, a: Vector2, b: Vector2, lo: float, ya: float, yb: float, out: Vector2, col: Color, ybase: float, flags: Vector2) -> void:
	var t := b - a
	if Vector2(-t.y, t.x).dot(out) < 0.0:
		var sw := a
		a = b
		b = sw
		var sy := ya
		ya = yb
		yb = sy
	_quad(cd, Vector3(a.x, lo, a.y), Vector3(b.x, lo, b.y), Vector3(b.x, yb, b.y), Vector3(a.x, ya, a.y), col, 0.0, t.length(), ybase, flags)


func _build_buildings() -> void:
	# [small, eave height above the uphill ground, lowest and highest ground at the walls, style, outline, roof]
	var data: Array = JSON.parse_string(FileAccess.get_file_as_string(DIR + "buildings.json"))
	var rng := RandomNumberGenerator.new()
	rng.seed = 1940
	var chunks := {}
	for b in data:
		var small: bool = b[0] > 0.5
		var h: float = b[1]
		var ymin: float = b[2]
		var ymax: float = b[3]
		var flat: Array = b[5]
		var rf: Dictionary = b[6]
		var n := flat.size() / 2
		if n < 3:
			continue
		var poly := PackedVector2Array()
		var centre := Vector2.ZERO
		for i in n:
			var p := Vector2(flat[2 * i], flat[2 * i + 1])
			poly.append(p)
			centre += p
		centre /= float(n)
		var area := 0.0
		for i in n:
			var p0 := poly[i]
			var p1 := poly[(i + 1) % n]
			area += p0.x * p1.y - p1.x * p0.y
		area = absf(area) * 0.5

		var key := Vector2i(int(floor(centre.x / BCHUNK)), int(floor(centre.y / BCHUNK)))
		var cd: ChunkData = chunks.get(key)
		if cd == null:
			cd = ChunkData.new()
			chunks[key] = cd

		var wc: Array = b[7]
		var rc: Array = b[8]
		var wall := Color(wc[0] / 255.0, wc[1] / 255.0, wc[2] / 255.0, 0.0)
		var roof := Color(rc[0] / 255.0, rc[1] / 255.0, rc[2] / 255.0, 0.0)
		var flags := Vector2(0.0, 0.0 if small else 1.0)
		detail.add_building({"poly": poly, "h": h, "ymin": ymin, "ymax": ymax, "wall": wall, "roof": roof,
			"style": int(b[4]), "area": area, "seed": rng.randi() & 0xffff, "rf": rf, "name": b[9], "id": b[10]}, key)

		# the plain version seen from afar: walls up to the line of the roof, the roof faces, and the steps in it
		for w in rf["w"]:
			var wa: Array = w
			var a := Vector2(wa[0], wa[1])
			var e := Vector2(wa[2], wa[3])
			var t := (e - a).normalized()
			var out := Vector2(t.y, -t.x)
			var i := 7
			while i + 6 < wa.size():
				_upright(cd, a + t * wa[i], a + t * wa[i + 2], wa[6] - 3.0, wa[i + 1], wa[i + 3], out, wall, ymax, flags)
				i += 7
		for face in rf["f"]:
			var fa: Array = face
			var m := (fa.size() - 1) / 3
			var flat2 := PackedVector2Array()
			for i in m:
				flat2.append(Vector2(fa[1 + i * 3], fa[3 + i * 3]))
			var tris := Geometry2D.triangulate_polygon(flat2)
			var k := 0
			while k + 2 < tris.size():
				var ia := tris[k]
				var ib := tris[k + 1]
				var ic := tris[k + 2]
				_tri_up(cd, Vector3(flat2[ia].x, fa[2 + ia * 3], flat2[ia].y), Vector3(flat2[ib].x, fa[2 + ib * 3], flat2[ib].y),
					Vector3(flat2[ic].x, fa[2 + ic * 3], flat2[ic].y), roof)
				k += 3
		for step in rf["s"]:
			var sa: Array = step
			_upright(cd, Vector2(sa[0], sa[1]), Vector2(sa[2], sa[3]), sa[6] - 0.05, sa[4], sa[5], Vector2(sa[7], sa[8]), wall, ymax, flags)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/building.gdshader")
	mat.set_shader_parameter("noise_tex", _noise_tex)
	var root := Node3D.new()
	root.name = "Buildings"
	add_child(root)
	for key in chunks:
		var cd: ChunkData = chunks[key]
		if cd.v.is_empty():
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = cd.v
		arrays[Mesh.ARRAY_NORMAL] = cd.n
		arrays[Mesh.ARRAY_COLOR] = cd.c
		arrays[Mesh.ARRAY_TEX_UV] = cd.uv
		arrays[Mesh.ARRAY_TEX_UV2] = cd.uv2
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.material_override = mat
		root.add_child(mi)
		detail.far_meshes[key] = mi

		var shape := ConcavePolygonShape3D.new()
		shape.backface_collision = true
		shape.set_faces(cd.v)
		var col := CollisionShape3D.new()
		col.shape = shape
		var body := StaticBody3D.new()
		body.add_child(col)
		root.add_child(body)


# ------------------------------------------------------------------ props
## Merge primitive meshes into one vertex-coloured mesh. parts: [[Mesh, Transform3D, Color], ...]
func _merge(parts: Array) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for part in parts:
		var prim: PrimitiveMesh = part[0]
		var xf: Transform3D = part[1]
		var col: Color = part[2]
		var arr := prim.get_mesh_arrays()
		var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
		for i in idx:
			st.set_color(col)
			st.set_normal((xf.basis * norms[i]).normalized())
			st.add_vertex(xf * verts[i])
	var mesh := st.commit()
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 0.95
	mesh.surface_set_material(0, mat)
	return mesh


func _cyl(top_r: float, bottom_r: float, height: float, segs: int) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = top_r
	c.bottom_radius = bottom_r
	c.height = height
	c.radial_segments = segs
	c.rings = 1
	return c


func _box(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b


func _at(x: float, y: float, z: float) -> Transform3D:
	return Transform3D(Basis(), Vector3(x, y, z))


func _build_trees() -> void:
	var canopy := SphereMesh.new()
	canopy.radius = 1.6
	canopy.height = 3.8
	canopy.radial_segments = 7
	canopy.rings = 4
	var lobe := SphereMesh.new()
	lobe.radius = 1.15
	lobe.height = 2.3
	lobe.radial_segments = 7
	lobe.rings = 4
	var meshes := [
		_merge([
			[_cyl(0.13, 0.2, 2.0, 5), _at(0, 1.0, 0), Color(0.23, 0.17, 0.12)],
			[_cyl(0.0, 1.9, 4.6, 7), _at(0, 3.4, 0), Color(0.12, 0.22, 0.14)],
			[_cyl(0.0, 1.3, 3.8, 7), _at(0, 6.0, 0), Color(0.14, 0.25, 0.16)]]),
		_merge([
			[_cyl(0.10, 0.17, 4.6, 5), _at(0, 2.3, 0), Color(0.30, 0.24, 0.18)],
			[canopy, _at(0, 5.4, 0), Color(0.20, 0.33, 0.13)],
			[lobe, _at(1.0, 4.6, 0.4), Color(0.17, 0.29, 0.12)],
			[lobe, _at(-0.8, 4.9, -0.7), Color(0.23, 0.36, 0.15)],
			[lobe, _at(-0.2, 6.6, 0.6), Color(0.25, 0.38, 0.16)]]),
	]
	var ball := SphereMesh.new()
	ball.radius = 1.6
	ball.height = 3.8
	ball.radial_segments = 5
	ball.rings = 2
	var far_meshes := [
		_merge([[_cyl(0.0, 1.8, 6.9, 5), _at(0, 4.4, 0), Color(0.12, 0.22, 0.14)]]),
		_merge([[ball, _at(0, 5.4, 0), Color(0.20, 0.33, 0.13)]]),
	]
	var data := FileAccess.get_file_as_bytes(DIR + "trees.bin").to_float32_array()
	var groups := {}       # Vector3i(chunk x, chunk z, kind) -> PackedInt32Array of tree indices
	var count := data.size() / 5
	for i in count:
		var key := Vector3i(int(floor(data[i * 5] / TREE_CHUNK)), int(floor(data[i * 5 + 1] / TREE_CHUNK)), int(data[i * 5 + 3]))
		if not groups.has(key):
			groups[key] = PackedInt32Array()
		groups[key].append(i)
	var root := Node3D.new()
	root.name = "Trees"
	add_child(root)
	for key in groups:
		var ids: PackedInt32Array = groups[key]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[key.z]
		mm.instance_count = ids.size()
		var origin := Vector3((key.x + 0.5) * TREE_CHUNK, 0.0, (key.y + 0.5) * TREE_CHUNK)
		origin.y = coarse_at(origin.x, origin.z)
		for j in ids.size():
			var i := ids[j]
			var x := data[i * 5]
			var z := data[i * 5 + 1]
			var s := data[i * 5 + 2]
			var bs := Basis(Vector3.UP, x * 12.9898 + z * 78.233).scaled(Vector3(s, s * (0.9 + 0.2 * sin(x * 3.1)), s))
			mm.set_instance_transform(j, Transform3D(bs, Vector3(x, data[i * 5 + 4] - 0.15, z) - origin))
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.position = origin
		mmi.visibility_range_end = TREE_NEAR
		mmi.visibility_range_end_margin = 30.0
		root.add_child(mmi)
		# the same trees again as plain shapes, for the far view
		var fm := MultiMesh.new()
		fm.transform_format = MultiMesh.TRANSFORM_3D
		fm.mesh = far_meshes[key.z]
		fm.instance_count = ids.size()
		fm.buffer = mm.buffer
		var fmi := MultiMeshInstance3D.new()
		fmi.multimesh = fm
		fmi.position = origin
		fmi.visibility_range_begin = TREE_NEAR
		fmi.visibility_range_begin_margin = 30.0
		fmi.visibility_range_end = TREE_RANGE
		fmi.visibility_range_end_margin = 80.0
		fmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(fmi)


func _build_wrecks() -> void:
	var rust := Color(0.24, 0.14, 0.10)
	var char_ := Color(0.07, 0.065, 0.06)
	var concrete := Color(0.55, 0.54, 0.52)
	var wheel := _cyl(0.32, 0.32, 0.22, 8)
	var side := Basis(Vector3(0, 0, 1), PI * 0.5)
	var car_parts := [
		[_box(Vector3(1.75, 0.55, 4.2)), _at(0, 0.62, 0), rust],
		[_box(Vector3(1.55, 0.5, 2.0)), _at(0, 1.12, 0.25), char_]]
	var van_parts := [
		[_box(Vector3(1.95, 1.5, 3.4)), _at(0, 1.15, 0.8), char_],
		[_box(Vector3(1.9, 0.9, 1.5)), _at(0, 0.85, -1.6), rust]]
	for sx in [-0.85, 0.85]:
		for sz in [-1.3, 1.3]:
			car_parts.append([wheel, Transform3D(side, Vector3(sx, 0.32, sz)), char_])
			van_parts.append([wheel, Transform3D(side, Vector3(sx * 1.1, 0.32, sz * 1.3)), char_])
	var barricade_parts := []
	for i in 3:
		barricade_parts.append([_box(Vector3(0.6, 0.9, 2.5)), Transform3D(Basis(Vector3.UP, (i - 1) * 0.12), Vector3((i - 1) * 0.1, 0.45, (i - 1) * 2.7)), concrete])
	var meshes := [_merge(car_parts), _merge(van_parts), _merge(barricade_parts)]
	var boxes := [Vector3(1.8, 1.4, 4.2), Vector3(2.0, 1.9, 5.0), Vector3(0.9, 0.9, 8.0)]

	var data := FileAccess.get_file_as_bytes(DIR + "wrecks.bin").to_float32_array()
	var count := data.size() / 4
	var per_kind := [[], [], []]
	var body := StaticBody3D.new()
	body.name = "Wrecks"
	add_child(body)
	for i in count:
		var x := data[i * 4]
		var z := data[i * 4 + 1]
		var kind := clampi(int(data[i * 4 + 3]), 0, 2)
		var xf := Transform3D(ground_basis(x, z, data[i * 4 + 2]), Vector3(x, height_at(x, z), z))
		per_kind[kind].append(xf)
		var shape := BoxShape3D.new()
		shape.size = boxes[kind]
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = xf * Transform3D(Basis(), Vector3(0, boxes[kind].y * 0.5, 0))
		body.add_child(col)
	for kind in 3:
		var list: Array = per_kind[kind]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = meshes[kind]
		mm.instance_count = list.size()
		for j in list.size():
			mm.set_instance_transform(j, list[j])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		add_child(mmi)


func _ramp(offsets: Array, colors: Array) -> GradientTexture1D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	var t := GradientTexture1D.new()
	t.gradient = g
	return t


func _puff_material(additive: bool) -> StandardMaterial3D:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 64
	tex.height = 64
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = tex
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.billboard_keep_scale = true
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return mat


func _build_fires() -> void:
	var smoke_quad := QuadMesh.new()
	smoke_quad.material = _puff_material(false)
	var flame_quad := QuadMesh.new()
	flame_quad.material = _puff_material(true)
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	var smoke_ramp := _ramp([0.0, 0.08, 0.6, 1.0], [Color(0.03, 0.03, 0.03, 0.0), Color(0.04, 0.035, 0.03, 0.7), Color(0.16, 0.16, 0.16, 0.4), Color(0.3, 0.3, 0.3, 0.0)])
	var flame_ramp := _ramp([0.0, 0.2, 0.7, 1.0], [Color(1.0, 0.85, 0.4, 0.0), Color(1.0, 0.6, 0.15, 0.9), Color(0.9, 0.2, 0.05, 0.5), Color(0.3, 0.05, 0.0, 0.0)])

	var root := Node3D.new()
	root.name = "Fires"
	add_child(root)
	for f in meta["fires"]:
		var fx: float = f[0]
		var fz: float = f[1]
		var size: float = f[2]
		var node := Node3D.new()
		node.position = Vector3(fx, height_at(fx, fz) + 1.0, fz)
		root.add_child(node)

		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		pm.emission_sphere_radius = 3.0 * size
		pm.direction = Vector3(0, 1, 0)
		pm.spread = 10.0
		pm.initial_velocity_min = 3.5
		pm.initial_velocity_max = 6.0
		pm.gravity = Vector3(1.3, 0.6, 0.5)
		pm.scale_min = 12.0 * size
		pm.scale_max = 22.0 * size
		pm.scale_curve = grow_tex
		pm.color_ramp = smoke_ramp
		pm.angle_min = 0.0
		pm.angle_max = 360.0
		var smoke := GPUParticles3D.new()
		smoke.amount = 56
		smoke.lifetime = 18.0
		smoke.preprocess = 18.0
		smoke.process_material = pm
		smoke.draw_pass_1 = smoke_quad
		smoke.visibility_aabb = AABB(Vector3(-80, -10, -80), Vector3(260, 260, 220))
		smoke.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(smoke)

		var fm := ParticleProcessMaterial.new()
		fm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
		fm.emission_sphere_radius = 2.2 * size
		fm.direction = Vector3(0, 1, 0)
		fm.spread = 18.0
		fm.initial_velocity_min = 1.5
		fm.initial_velocity_max = 3.5
		fm.gravity = Vector3(0.3, 1.5, 0.1)
		fm.scale_min = 1.6 * size
		fm.scale_max = 3.2 * size
		fm.color_ramp = flame_ramp
		var flames := GPUParticles3D.new()
		flames.amount = 28
		flames.lifetime = 1.3
		flames.preprocess = 1.3
		flames.process_material = fm
		flames.draw_pass_1 = flame_quad
		flames.visibility_aabb = AABB(Vector3(-12, -4, -12), Vector3(24, 20, 24))
		flames.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.add_child(flames)

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.55, 0.22)
		light.light_energy = 6.0 * size
		light.omni_range = 34.0 * size
		light.position = Vector3(0, 2.5, 0)
		light.distance_fade_enabled = true
		light.distance_fade_begin = 500.0
		light.distance_fade_length = 100.0
		node.add_child(light)
		_fire_lights.append([light, 6.0 * size, fx * 0.37 + fz * 0.11])


func _build_streets() -> void:
	var names := {}
	for s in meta["streets"]:
		var nm: String = s[0]
		var pts: Array = s[1]
		if not names.has(nm):
			names[nm] = _street_names.size()
			_street_names.append(nm)
		var idx: float = names[nm]
		var i := 0
		while i + 3 < pts.size():
			var a := Vector2(pts[i], pts[i + 1])
			var b := Vector2(pts[i + 2], pts[i + 3])
			var steps := maxi(1, int(ceil(a.distance_to(b) / 15.0)))
			for k in steps + 1:
				var p := a.lerp(b, float(k) / float(steps))
				var key := Vector2i(int(floor(p.x / 50.0)), int(floor(p.y / 50.0)))
				if not _street_grid.has(key):
					_street_grid[key] = PackedFloat32Array()
				_street_grid[key].append(p.x)
				_street_grid[key].append(p.y)
				_street_grid[key].append(idx)
			i += 2


# ------------------------------------------------------------------ runtime
func _process(delta: float) -> void:
	_time += delta
	for entry in _fire_lights:
		var light: OmniLight3D = entry[0]
		var base: float = entry[1]
		var phase: float = entry[2]
		light.light_energy = base * (0.75 + 0.25 * sin(_time * 11.0 + phase) + 0.15 * sin(_time * 23.7 + phase * 2.0))


## Keep the 1 m terrain and the close-up detail loaded around a position (call every physics frame).
## The cell underfoot is made at once; the rest of the window one cell per call. The far terrain
## steps aside for the window only when all of it is there.
func update_streaming(p: Vector3) -> void:
	detail.update(p)
	var c := Vector2i(int(floor(p.x / FCELL)), int(floor(p.z / FCELL)))
	if not _near.has(c):
		_near[c] = _make_near(c)
	if c != _near_want:
		_near_want = c
		_near_queue.clear()
		for dz in range(-TR, TR + 1):
			for dx in range(-TR, TR + 1):
				var k := Vector2i(c.x + dx, c.y + dz)
				if not _near.has(k):
					_near_queue.append([dx * dx + dz * dz, k])
		_near_queue.sort_custom(func(a, b): return a[0] < b[0])
		if _near_queue.is_empty():
			_publish_near()
	if not _near_queue.is_empty():
		var k: Vector2i = _near_queue.pop_front()[1]
		if not _near.has(k):
			_near[k] = _make_near(k)
		if _near_queue.is_empty():
			_publish_near()


func _publish_near() -> void:
	var c := _near_want
	_terrain_mat.set_shader_parameter("near_rect", Vector4((c.x - TR) * FCELL + 0.5, (c.y - TR) * FCELL + 0.5,
		(c.x + TR + 1) * FCELL - 0.5, (c.y + TR + 1) * FCELL - 0.5))
	for k in _near.keys():
		if absi(k.x - c.x) > TR or absi(k.y - c.y) > TR:
			_near[k].queue_free()
			_near.erase(k)
	if _fine_cache.size() > 400:
		for k in _fine_cache.keys():
			if absi(k.x - c.x) > TR + 3 or absi(k.y - c.y) > TR + 3:
				_fine_cache.erase(k)
				_fine_range.erase(k)
		_hk = Vector2i(-99999, -99999)


## Everything around a position, right now (loading screen, screenshots, teleports).
func flush(p: Vector3) -> void:
	_near_want = Vector2i(-99999, -99999)
	update_streaming(p)
	while not _near_queue.is_empty():
		update_streaming(p)
	detail.flush(p)
