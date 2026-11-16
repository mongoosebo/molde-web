extends RefCounted
## Close-up dress for the ordinary buildings: recessed windows with frames and sills, doors, plinths,
## corner boards, eaves and proper roofs, generated from each building's real footprint, measured
## height and roof shape, and its type on the map. The look is a guess by type, not a survey.

const TEX_DIR := "res://world/textures/"

# g_h / f_h: storey heights. win / gwin: [width, height, sill] of upper and ground-floor windows.
# pane: 0 a transom, 1 a centre post in wide windows, 2 a cross, 3 one sheet of glass.
# unit: a door for every so many metres of the door wall (row houses, stairwells of a block).
# The numbers match the styles chosen in tools/build_map.py.
const STYLES := [
	# 0 older timber villa: steep roof, small cross-barred windows, white trim
	{"wall": "clad", "g_h": 2.8, "f_h": 2.6, "bay": 2.6, "margin": 0.7, "win": [1.0, 1.3, 0.85], "gwin": [1.0, 1.3, 0.85],
		"depth": 0.09, "sills": true, "corners": true, "door": [0.95, 2.05], "pane": 2, "roof_m": "tiles"},
	# 1 house of the 1960s-80s: low roof, wide picture windows, trim in the wall's own colour
	{"wall": "clad", "g_h": 2.6, "f_h": 2.5, "bay": 3.4, "margin": 0.8, "win": [1.9, 1.15, 0.9], "gwin": [1.9, 1.15, 0.9],
		"depth": 0.08, "sills": false, "corners": false, "door": [0.95, 2.05], "pane": 1, "roof_m": "tiles", "soft_trim": true},
	# 2 newer house: upright boards, tall windows without bars, dark frames
	{"wall": "cladv", "g_h": 2.8, "f_h": 2.7, "bay": 3.2, "margin": 0.6, "win": [1.5, 1.9, 0.3], "gwin": [1.8, 2.1, 0.15],
		"depth": 0.1, "sills": false, "corners": false, "door": [1.0, 2.1], "pane": 3, "roof_m": "sheet", "dark_trim": true},
	# 3 row houses and semi-detached: a door per home
	{"wall": "clad", "g_h": 2.6, "f_h": 2.5, "bay": 3.2, "margin": 0.6, "win": [1.5, 1.2, 0.9], "gwin": [1.5, 1.2, 0.9],
		"depth": 0.08, "sills": true, "corners": true, "door": [0.95, 2.05], "pane": 1, "roof_m": "tiles", "unit": 6.4},
	# 4 post-war block of flats: render, small balconies on the long side
	{"wall": "plaster", "g_h": 2.9, "f_h": 2.8, "bay": 3.1, "margin": 0.8, "win": [1.3, 1.35, 0.85], "gwin": [1.3, 1.35, 0.85],
		"depth": 0.16, "sills": true, "corners": false, "door": [1.3, 2.15], "pane": 1, "roof_m": "tiles", "balconies": true, "unit": 13.0},
	# 5 newer block of flats: big glazing, a glass-fronted balcony to every bay
	{"wall": "plaster", "g_h": 3.0, "f_h": 2.9, "bay": 3.6, "margin": 0.6, "win": [2.2, 2.0, 0.25], "gwin": [2.2, 2.0, 0.25],
		"depth": 0.14, "sills": false, "corners": false, "door": [1.6, 2.2], "pane": 3, "roof_m": "sheet", "balconies": true,
		"glass_rail": true, "every_bay": true, "dark_trim": true, "unit": 16.0},
	# 6 shops and offices in the centre: shopfronts under a band, windows above
	{"wall": "plaster", "g_h": 3.8, "f_h": 3.2, "bay": 3.4, "margin": 0.5, "win": [2.5, 1.6, 0.9], "gwin": [2.8, 2.6, 0.35],
		"depth": 0.2, "sills": false, "corners": false, "door": [1.8, 2.3], "pane": 1, "roof_m": "tiles", "band": true, "dark_trim": true},
	# 7 big store or modern office: sheet walls, a glazed front
	{"wall": "metal", "g_h": 4.4, "f_h": 3.6, "bay": 5.0, "margin": 0.6, "win": [3.6, 1.2, 1.2], "gwin": [4.2, 3.0, 0.2],
		"depth": 0.12, "sills": false, "corners": false, "door": [2.4, 2.5], "pane": 1, "roof_m": "sheet", "band": true, "dark_trim": true},
	# 8 industry and warehouses: sheet cladding, high strip windows, a big door
	{"wall": "metal", "g_h": 4.6, "f_h": 4.0, "bay": 6.0, "margin": 1.0, "win": [3.4, 0.9, 2.6], "gwin": [3.4, 0.9, 2.9],
		"depth": 0.08, "sills": false, "corners": false, "door": [3.4, 3.6], "pane": 1, "roof_m": "sheet", "dark_trim": true, "big_door": true},
	# 9 garages and sheds
	{"wall": "clad", "g_h": 2.4, "f_h": 2.4, "bay": 99.0, "margin": 0.4, "win": [0.7, 0.6, 1.2], "gwin": [0.7, 0.6, 1.2],
		"depth": 0.07, "sills": false, "corners": true, "door": [2.3, 2.0], "pane": 3, "roof_m": "tiles", "garage": true},
	# 10 schools, halls, churches
	{"wall": "plaster", "g_h": 3.5, "f_h": 3.3, "bay": 3.0, "margin": 0.7, "win": [1.6, 1.9, 0.85], "gwin": [1.6, 1.9, 0.85],
		"depth": 0.18, "sills": true, "corners": false, "door": [1.9, 2.4], "pane": 2, "roof_m": "tiles", "band": true},
	# 11 barns, boathouses and cabins: upright boards, a few small windows, a wide door at the low side
	{"wall": "cladv", "g_h": 2.6, "f_h": 2.5, "bay": 4.5, "margin": 0.8, "win": [0.8, 0.8, 1.1], "gwin": [0.8, 0.8, 1.1],
		"depth": 0.07, "sills": false, "corners": true, "door": [2.2, 2.2], "pane": 2, "roof_m": "sheet", "garage": true, "big_door": true},
	# 12 old timber houses of the open-air museum: dark logs, small panes, turf on the roof
	{"wall": "clad", "g_h": 2.3, "f_h": 2.2, "bay": 3.0, "margin": 0.7, "win": [0.7, 0.7, 1.0], "gwin": [0.7, 0.7, 1.0],
		"depth": 0.1, "sills": false, "corners": true, "door": [0.9, 1.8], "pane": 2, "roof_m": "roof", "soft_trim": true},
	# 13 the rendered post-war blocks of the main street: shop windows under a canopy, plain windows above
	{"wall": "plaster", "g_h": 3.9, "f_h": 3.0, "bay": 3.3, "margin": 0.5, "win": [1.5, 1.5, 0.9], "gwin": [2.8, 2.7, 0.3],
		"depth": 0.2, "sills": true, "corners": false, "door": [1.8, 2.4], "pane": 1, "roof_m": "tiles", "band": true, "dark_trim": false, "shops": true},
]

const GLASS := Color(0.05, 0.07, 0.09)
const PLINTH := Color(0.42, 0.42, 0.41)
const WHITE := Color(0.90, 0.90, 0.87)
const DARK := Color(0.16, 0.17, 0.19)
const DOORS := [Color(0.33, 0.19, 0.11), Color(0.14, 0.24, 0.20), Color(0.42, 0.10, 0.09), Color(0.16, 0.20, 0.30), Color(0.85, 0.85, 0.82)]

var mats := {}
var _tex_cache := {}


## Collects coloured triangles per material.
class MB:
	var surf := {}

	func _s(m: String) -> Array:
		var s = surf.get(m)
		if s == null:
			s = [PackedVector3Array(), PackedVector3Array(), PackedColorArray(), PackedVector2Array()]
			surf[m] = s
		return s

	func tri(m: String, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
		var s := _s(m)
		if (c - a).cross(b - a).dot(nrm) < 0.0:
			var t := b
			b = c
			c = t
		s[0].append(a); s[0].append(b); s[0].append(c)
		s[1].append(nrm); s[1].append(nrm); s[1].append(nrm)
		s[2].append(col); s[2].append(col); s[2].append(col)
		s[3].append(Vector2.ZERO); s[3].append(Vector2.ZERO); s[3].append(Vector2.ZERO)

	## A triangle of a sloping roof: texture coordinates in metres along the eave and down the slope.
	func roof_tri(m: String, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, col: Color) -> void:
		var s := _s(m)
		if (c - a).cross(b - a).dot(nrm) < 0.0:
			var t := b
			b = c
			c = t
		var e := nrm.cross(Vector3.UP)
		if e.length_squared() < 1e-6:
			e = Vector3.RIGHT
		e = e.normalized()
		var d := nrm.cross(e)
		s[0].append(a); s[0].append(b); s[0].append(c)
		s[1].append(nrm); s[1].append(nrm); s[1].append(nrm)
		s[2].append(col); s[2].append(col); s[2].append(col)
		s[3].append(Vector2(a.dot(e), a.dot(d))); s[3].append(Vector2(b.dot(e), b.dot(d))); s[3].append(Vector2(c.dot(e), c.dot(d)))

	func quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, col: Color) -> void:
		var s := _s(m)
		if (c - a).cross(b - a).dot(nrm) < 0.0:
			var t := b
			b = d
			d = t
		var v: PackedVector3Array = s[0]
		var n: PackedVector3Array = s[1]
		var k: PackedColorArray = s[2]
		var u: PackedVector2Array = s[3]
		v.append(a); v.append(b); v.append(c); v.append(a); v.append(c); v.append(d)
		n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm); n.append(nrm)
		k.append(col); k.append(col); k.append(col); k.append(col); k.append(col); k.append(col)
		u.append(Vector2.ZERO); u.append(Vector2.ZERO); u.append(Vector2.ZERO); u.append(Vector2.ZERO); u.append(Vector2.ZERO); u.append(Vector2.ZERO)

	## Quad with the normal worked out from the corners; `hint` picks the side.
	func quad_auto(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, hint: Vector3, col: Color) -> void:
		var nrm := (b - a).cross(d - a)
		if nrm.length_squared() < 1e-10:
			nrm = (c - a).cross(d - a)
		if nrm.length_squared() < 1e-10:
			nrm = (b - a).cross(c - a)
		if nrm.length_squared() < 1e-10:
			return
		nrm = nrm.normalized()
		if nrm.dot(hint) < 0.0:
			nrm = -nrm
		quad(m, a, b, c, d, nrm, col)

	func box(m: String, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, h: Vector3, col: Color) -> void:
		var x := ax * h.x
		var y := ay * h.y
		var z := az * h.z
		quad(m, c + x - y - z, c + x + y - z, c + x + y + z, c + x - y + z, ax, col)
		quad(m, c - x - y - z, c - x + y - z, c - x + y + z, c - x - y + z, -ax, col)
		quad(m, c - x + y - z, c + x + y - z, c + x + y + z, c - x + y + z, ay, col)
		quad(m, c - x - y - z, c + x - y - z, c + x - y + z, c - x - y + z, -ay, col)
		quad(m, c - x - y + z, c + x - y + z, c + x + y + z, c - x + y + z, az, col)
		quad(m, c - x - y - z, c + x - y - z, c + x + y - z, c - x + y - z, -az, col)

	func is_empty() -> bool:
		return surf.is_empty()


## One wall: a is the start corner, t runs along it, n points outward. `top` is where its lowest
## stretch ends; `prof` is the line its top follows (tools/roofs.py: pieces of
## [from, height, to, height, 1 if a sloping roof rests on it, heights of the roof edge out past the wall]).
class Face:
	var a: Vector3
	var t: Vector3
	var n: Vector3
	var length: float
	var top: float
	var prof: Array
	var ga: float              # ground at the start, at the end, and the lowest along the wall
	var gb: float
	var glow: float

	func ground(s: float) -> float:
		return lerpf(ga, gb, clampf(s / length, 0.0, 1.0))

	func p(s: float, y: float, depth: float = 0.0) -> Vector3:
		return Vector3(a.x + t.x * s - n.x * depth, y, a.z + t.z * s - n.z * depth)


func _init() -> void:
	mats = {
		"clad": _textured("cladding", 2.0, 0.85),
		"plaster": _textured("plaster", 2.0, 0.92),
		"roof": _textured("gravel", 1.5, 0.85),
		"cladv": _textured("cladv", 2.0, 0.85),
		"tiles": _mapped("rooftile", 2.0, 0.8, 0.0),
		"sheet": _mapped("sheet", 2.0, 0.45, 0.35),
		"asphalt": _textured("asphalt", 2.0, 0.9),
		"sidewalk": _textured("slabs", 2.0, 0.9),
		"path": _textured("path", 2.0, 0.95),
		"metal": _plain(0.45, 0.35),
		"trim": _plain(0.6, 0.0),
		"mark": _plain(0.7, 0.0),
		"glass": _plain(0.07, 0.85),
	}


func _tex(name: String) -> ImageTexture:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(TEX_DIR + name + ".png"))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[name] = tex
	return tex


func _textured(tex: String, tile_m: float, rough: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tex + "_albedo")
	m.normal_enabled = true
	m.normal_texture = _tex(tex + "_normal")
	m.roughness = rough
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


## Textured by the mesh's own coordinates (roofs: along the eave and down the slope).
func _mapped(tex: String, tile_m: float, rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tex + "_albedo")
	m.normal_enabled = true
	m.normal_texture = _tex(tex + "_normal")
	m.roughness = rough
	m.metallic = metallic
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	m.uv1_scale = Vector3.ONE / tile_m
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m


func _plain(rough: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.roughness = rough
	m.metallic = metallic
	m.vertex_color_use_as_albedo = true
	m.vertex_color_is_srgb = true
	return m


func commit(mb: MB) -> ArrayMesh:
	var mesh := ArrayMesh.new()
	for m in mb.surf:
		var s: Array = mb.surf[m]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_COLOR] = s[2]
		arrays[Mesh.ARRAY_TEX_UV] = s[3]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, mats[m])
	return mesh


# ------------------------------------------------------------------ one building
const EAVE := 0.45


## rec: poly, h, ymin, ymax, wall, roof, style, area, seed, rf (the measured roof: faces, walls, steps)
func build(mb: MB, rec: Dictionary) -> void:
	var st: Dictionary = STYLES[rec["style"]]
	var wall_m: String = st["wall"]
	var wall: Color = rec["wall"]
	wall.a = 1.0
	var roof: Color = rec["roof"]
	roof.a = 1.0
	var seed: int = rec["seed"]
	var lum := wall.r * 0.3 + wall.g * 0.6 + wall.b * 0.1
	var trim := WHITE
	if st.get("dark_trim", false):
		trim = DARK
	elif st.get("soft_trim", false) and lum < 0.6:
		trim = wall.darkened(0.3)
	elif lum > 0.72:
		trim = Color(0.34, 0.36, 0.39)
	var roof_m: String = st["roof_m"]
	var rf: Dictionary = rec["rf"]
	var shop_fronts := []
	for v in rf.get("sf", []):
		shop_fronts.append(int(v))
	var ymax: float = rec["ymax"]
	var garage: bool = st.get("garage", false)

	# walls, in the order they run round the building (anticlockwise on the map, so outward is to the right)
	var faces: Array = []
	var longest := -1
	var second := -1
	for w in rf["w"]:
		var wa: Array = w
		var a := Vector2(wa[0], wa[1])
		var b := Vector2(wa[2], wa[3])
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var t2 := (b - a) / length
		var f := Face.new()
		f.a = Vector3(a.x, 0.0, a.y)
		f.t = Vector3(t2.x, 0.0, t2.y)
		f.n = Vector3(t2.y, 0.0, -t2.x)
		f.length = length
		f.prof = wa
		f.ga = wa[4]
		f.gb = wa[5]
		f.glow = wa[6]
		f.top = INF
		var i := 7
		while i + 6 < wa.size():
			f.top = minf(f.top, minf(wa[i + 1], wa[i + 3]))
			i += 7
		faces.append(f)
		if longest < 0 or length > faces[longest].length:
			second = longest
			longest = faces.size() - 1
		elif second < 0 or length > faces[second].length:
			second = faces.size() - 1
	if faces.is_empty():
		return
	# The floor everything is measured from. A house stands with its main floor just above the ground on
	# its uphill side, so on a slope a basement storey shows downhill; a garage has its floor at the wall
	# where the ground is lowest, and backs into the hill.
	var eave: float = ymax + rec["h"]
	var datum := ymax + 0.4
	var door_face := longest
	if garage:
		var lowest := INF
		for k in faces.size():
			var fg: Face = faces[k]
			if fg.length >= 2.4 and maxf(fg.ga, fg.gb) < lowest:
				lowest = maxf(fg.ga, fg.gb)
				door_face = k
		datum = (lowest if lowest < INF else ymax) + 0.1
	datum = maxf(minf(datum, eave - 2.3), rec["ymin"] + 0.1)
	if not garage:
		# the door goes in a wall that stands on the ground at floor level, a long one for preference
		var best := INF
		for k in faces.size():
			var fd: Face = faces[k]
			if fd.length < 2.6 or fd.top < datum + 2.2:
				continue
			var score := absf(datum - 0.3 - fd.ground(fd.length * 0.5)) - 0.04 * fd.length + (0.0 if k == (longest + seed % 2) % faces.size() else 0.25)
			if score < best:
				best = score
				door_face = k
	# the wall that shows most of the basement gets a garage door in it
	var low_face := -1
	if rec["style"] <= 2:
		var deepest := 2.4
		for k in faces.size():
			var fl: Face = faces[k]
			if fl.length >= 4.0 and k != door_face and datum - maxf(fl.ga, fl.gb) > deepest:
				deepest = datum - maxf(fl.ga, fl.gb)
				low_face = k
	var door_col: Color = DOORS[seed % DOORS.size()]
	if garage or st.get("big_door", false):
		door_col = Color(0.80, 0.80, 0.78) if lum < 0.6 else Color(0.36, 0.38, 0.40)

	for k in faces.size():
		var f: Face = faces[k]
		var base := f.glow - 0.8
		var yg := minf(datum, f.top - 1.2)
		if f.top - base < 1.0 or yg <= base:
			mb.quad(wall_m, f.p(0, base), f.p(f.length, base), f.p(f.length, f.top), f.p(0, f.top), f.n, wall)
		else:
			# storeys of this wall
			var g_h: float = st["g_h"]
			var f_h: float = st["f_h"]
			var avail := f.top - yg
			var floors := 1
			if avail > g_h + f_h * 0.7:
				floors = 1 + int((avail - g_h) / f_h + 0.3)
			if floors == 1:
				g_h = avail
			else:
				g_h *= minf(avail / (g_h + float(floors - 1) * f_h), 1.25)
				f_h = (avail - g_h) / float(floors - 1)
			var windows: bool = not garage or k == second
			_facade(mb, f, base, yg, f.top, floors, g_h, f_h, st, wall_m, wall, trim, door_col, k == door_face or k in shop_fronts, windows, k == longest, k == low_face, k in shop_fronts)
			if st["corners"] and faces.size() <= 14:
				var prev: Face = faces[(k + faces.size() - 1) % faces.size()]
				if absf(prev.t.dot(f.n)) > 0.3:
					var ct := minf(f.top, prev.top)
					mb.box("trim", f.p(0.0, (yg + ct) * 0.5, -0.02), f.t, Vector3.UP, f.n, Vector3(0.07, (ct - yg) * 0.5, 0.07), trim)
		_wall_top(mb, f, wall_m, wall, roof, trim, roof_m)

	# the roof itself
	var peak := Vector3(0, -INF, 0)
	var peak_in := Vector3.ZERO
	for face in rf["f"]:
		var fa: Array = face
		var m := (fa.size() - 1) / 3
		if m < 3:
			continue
		var flat2 := PackedVector2Array()
		var pts := PackedVector3Array()
		var nrm := Vector3.ZERO
		var mid := Vector3.ZERO
		for i in m:
			var q := Vector3(fa[1 + i * 3], fa[2 + i * 3], fa[3 + i * 3])
			pts.append(q)
			flat2.append(Vector2(q.x, q.z))
			mid += q / float(m)
		for i in m:
			nrm += pts[i].cross(pts[(i + 1) % m])
		if nrm.length_squared() < 1e-8:
			continue
		nrm = nrm.normalized()
		if nrm.y < 0.0:
			nrm = -nrm
		var tris := Geometry2D.triangulate_polygon(flat2)
		var t := 0
		while t + 2 < tris.size():
			if fa[0] == 0:
				mb.roof_tri(roof_m, pts[tris[t]], pts[tris[t + 1]], pts[tris[t + 2]], nrm, roof)
			else:
				mb.tri("roof", pts[tris[t]], pts[tris[t + 1]], pts[tris[t + 2]], nrm, roof)
			t += 3
		if fa[0] == 0:
			for q in pts:
				if q.y > peak.y:
					peak = q
					peak_in = mid
	# upright faces where a higher part of the roof stands over a lower one
	for step in rf["s"]:
		var sa: Array = step
		var a3 := Vector3(sa[0], 0, sa[1])
		var b3 := Vector3(sa[2], 0, sa[3])
		var up_a := Vector3(0, sa[4], 0)
		var up_b := Vector3(0, sa[5], 0)
		var lowy := Vector3(0, sa[6] - 0.05, 0)
		mb.quad(wall_m, a3 + lowy, b3 + lowy, b3 + up_b, a3 + up_a, Vector3(sa[7], 0, sa[8]), wall)
	if (rec["style"] <= 1 or rec["style"] == 3) and rec["area"] > 50.0 and peak.y > -1e9:
		# chimney just off the ridge
		var d := peak_in - peak
		d.y = 0.0
		if d.length() > 1.2:
			var c := peak + d.normalized() * 0.8
			mb.box("plaster", Vector3(c.x, peak.y - 0.1, c.z), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.3, 0.85, 0.3), Color(0.5, 0.33, 0.27))


## The part of a wall above its lowest stretch (gables, steps), and what sits on it: the roof carried
## out past the wall with a fascia board, or a coping on a flat roof.
func _wall_top(mb: MB, f: Face, wall_m: String, wall: Color, roof: Color, trim: Color, roof_m: String) -> void:
	var w := f.prof
	var i := 7
	while i + 6 < w.size():
		var s0: float = w[i]
		var y0: float = w[i + 1]
		var s1: float = w[i + 2]
		var y1: float = w[i + 3]
		if y0 > f.top + 0.02 or y1 > f.top + 0.02:
			mb.quad(wall_m, f.p(s0, f.top), f.p(s1, f.top), f.p(s1, y1), f.p(s0, y0), f.n, wall)
		if int(w[i + 4]) == 1:
			var o0 := f.p(s0, w[i + 5], -EAVE)
			var o1 := f.p(s1, w[i + 6], -EAVE)
			var dn := Vector3(0, 0.14, 0)
			var e0 := f.p(s0, y0)
			var e1 := f.p(s1, y1)
			var rn := (e1 - e0).cross(o0 - e0)
			if rn.length_squared() > 1e-8:
				rn = rn.normalized()
				if rn.y < 0.0:
					rn = -rn
				mb.roof_tri(roof_m, e0, e1, o1, rn, roof)
				mb.roof_tri(roof_m, e0, o1, o0, rn, roof)
			mb.quad_auto("trim", o0, o1, o1 - dn, o0 - dn, f.n, trim)
			mb.quad_auto("trim", f.p(s0, y0) - dn, f.p(s1, y1) - dn, o1 - dn, o0 - dn, Vector3.DOWN, trim)
		elif absf(y1 - y0) < 0.05 and s1 - s0 > 0.2:
			mb.box("trim", f.p((s0 + s1) * 0.5, y0 - 0.08, -0.1), f.t, Vector3.UP, f.n, Vector3((s1 - s0) * 0.5 + 0.1, 0.09, 0.12), trim)
		i += 7


func _facade(mb: MB, f: Face, base: float, yg: float, top: float, floors: int, g_h: float, f_h: float, st: Dictionary,
		wall_m: String, wall: Color, trim: Color, door_col: Color, with_door: bool, windows: bool, is_long: bool, low_door: bool, shop: bool = false) -> void:
	var length := f.length
	var margin: float = st["margin"]
	var bay: float = st["bay"]
	var bays := 0
	if windows and length > 2.0:
		bays = maxi(0, int((length - 2.0 * margin) / bay))
		if bays == 0 and (with_door or length > 2.4):
			bays = 1
	# basement storeys, where the ground falls away below the main floor
	var levels := 0
	if bays > 0 and not st.get("garage", false):
		levels = clampi(int((yg - f.glow - 0.15) / BASEMENT), 0, 3)
	var yb := yg - BASEMENT * float(levels)
	mb.quad("plaster", f.p(0, base), f.p(length, base), f.p(length, yb), f.p(0, yb), f.n, PLINTH)
	if bays == 0:
		mb.quad(wall_m, f.p(0, yg), f.p(length, yg), f.p(length, top), f.p(0, top), f.n, wall)
		return
	var bw := (length - 2.0 * margin) / float(bays)
	for lv in levels:
		_basement(mb, f, yb + BASEMENT * float(lv), bays, margin, bw, trim, door_col, low_door and lv == 0)
	var depth: float = st["depth"]
	var door: Array = st["door"]
	var door_bays := {bays / 2: true}
	if st.has("unit"):
		var units := maxi(1, int(round(length / float(st["unit"]))))
		door_bays = {}
		for un in units:
			door_bays[int((float(un) + 0.5) * float(bays) / float(units))] = true
	var y := yg
	for fl in floors:
		var fh := g_h if fl == 0 else f_h
		var op: Array = st["gwin"] if fl == 0 else st["win"]
		var ow := minf(op[0], bw - 0.35)
		var sill: float = minf(op[2], fh * 0.4)
		var oh := minf(op[1], fh - sill - 0.25)
		var y0 := y + sill
		var y1 := y0 + oh
		if ow < 0.4 or oh < 0.35:
			mb.quad(wall_m, f.p(0, y), f.p(length, y), f.p(length, y + fh), f.p(0, y + fh), f.n, wall)
			y += fh
			continue
		var has_door := with_door and fl == 0
		var dw := minf(door[0], bw - 0.2)
		var dh := minf(door[1], fh - 0.2)
		# wall below, above and between the openings
		mb.quad(wall_m, f.p(0, y1), f.p(length, y1), f.p(length, y + fh), f.p(0, y + fh), f.n, wall)
		var prev := 0.0
		for b in bays:
			var mid := margin + (float(b) + 0.5) * bw
			var is_door := has_door and door_bays.has(b)
			var s0 := mid - (dw if is_door else ow) * 0.5
			var s1 := mid + (dw if is_door else ow) * 0.5
			mb.quad(wall_m, f.p(prev, y), f.p(s0, y), f.p(s0, y1), f.p(prev, y1), f.n, wall)
			if is_door:
				var dt := y + dh
				if dt < y1:
					mb.quad(wall_m, f.p(s0, dt), f.p(s1, dt), f.p(s1, y1), f.p(s0, dt + (y1 - dt)), f.n, wall)
				else:
					dt = y1
				_reveal(mb, f, s0, s1, y, dt, depth + 0.05, wall_m, wall)
				mb.quad("trim", f.p(s0, y, depth + 0.05), f.p(s1, y, depth + 0.05), f.p(s1, dt, depth + 0.05), f.p(s0, dt, depth + 0.05), f.n, door_col)
				if st.get("garage", false) or dw > 3.0:
					for r in range(1, 4):                # panel joints of an up-and-over door
						var yy := lerpf(y, dt, float(r) / 4.0)
						mb.quad("trim", f.p(s0, yy - 0.02, depth + 0.03), f.p(s1, yy - 0.02, depth + 0.03), f.p(s1, yy + 0.02, depth + 0.03), f.p(s0, yy + 0.02, depth + 0.03), f.n, door_col.darkened(0.35))
				else:
					_steps(mb, f, mid, y, dw)
					mb.box("trim", f.p(s1 - 0.13, y + 1.02, depth - 0.02), f.t, Vector3.UP, f.n, Vector3(0.02, 0.07, 0.04), DARK)   # handle
					if dw > 1.5 or st.get("band", false):
						mb.box("trim", f.p(mid, dt + 0.12, -0.45), f.t, Vector3.UP, f.n, Vector3(dw * 0.5 + 0.35, 0.05, 0.5), trim)  # canopy
			else:
				mb.quad(wall_m, f.p(s0, y), f.p(s1, y), f.p(s1, y0), f.p(s0, y0), f.n, wall)
				var pane: int = st["pane"]
				if pane == 1 and ow <= 1.3:
					pane = 0
				_window(mb, f, s0, s1, y0, y1, depth, wall_m, wall, trim, st["sills"] and fl >= 0, pane)
				if fl > 0 and is_long and st.get("balconies", false) and (b % 2 == 0 or st.get("every_bay", false)):
					mb.box("trim", f.p(mid, y + 0.02, -0.7), f.t, Vector3.UP, f.n, Vector3(bw * 0.46, 0.07, 0.7), PLINTH)
					if st.get("glass_rail", false):
						mb.box("glass", f.p(mid, y + 0.6, -1.38), f.t, Vector3.UP, f.n, Vector3(bw * 0.46, 0.5, 0.015), Color(0.42, 0.52, 0.56))
						mb.box("trim", f.p(mid, y + 1.12, -1.38), f.t, Vector3.UP, f.n, Vector3(bw * 0.46, 0.025, 0.03), DARK)
						mb.box("glass", f.p(mid - bw * 0.46, y + 0.6, -0.7), f.n, Vector3.UP, f.t, Vector3(0.68, 0.5, 0.015), Color(0.42, 0.52, 0.56))
						mb.box("glass", f.p(mid + bw * 0.46, y + 0.6, -0.7), f.n, Vector3.UP, f.t, Vector3(0.68, 0.5, 0.015), Color(0.42, 0.52, 0.56))
					else:
						mb.box("trim", f.p(mid, y + 0.55, -1.37), f.t, Vector3.UP, f.n, Vector3(bw * 0.46, 0.5, 0.03), trim)
			prev = s1
		mb.quad(wall_m, f.p(prev, y), f.p(length, y), f.p(length, y1), f.p(prev, y1), f.n, wall)
		y += fh
		if fl == 0 and shop and length > 5.0:
			# a canopy over the shop windows
			var deep := 1.3
			mb.box("trim", f.p(length * 0.5, y - 0.32, -deep * 0.5), f.t, Vector3.UP, f.n, Vector3(length * 0.5, 0.13, deep * 0.5), DARK)
		if fl == 0 and st.get("band", false) and floors > 1:
			mb.box("trim", f.p(length * 0.5, y - 0.05, -0.05), f.t, Vector3.UP, f.n, Vector3(length * 0.5 + 0.05, 0.1, 0.07), trim)


const BASEMENT := 2.5


## One basement storey of a wall: rendered concrete with a small window in every bay where the
## ground lies low enough, and a garage door where asked and where the ground is at its floor.
func _basement(mb: MB, f: Face, y: float, bays: int, margin: float, bw: float, trim: Color, door_col: Color, garage_door: bool) -> void:
	var length := f.length
	var y1 := y + BASEMENT
	var door_bay := -1
	if garage_door:
		var lowest := y + 0.35
		for b in bays:
			var g := f.ground(margin + (float(b) + 0.5) * bw)
			if g < lowest:
				lowest = g
				door_bay = b
	var prev := 0.0
	for b in bays:
		var mid := margin + (float(b) + 0.5) * bw
		var g := maxf(f.ground(mid - bw * 0.3), f.ground(mid + bw * 0.3))
		var ow := minf(0.95, bw - 0.4)
		var y0 := y + 1.25
		var yt := y + 2.0
		if b == door_bay:
			ow = minf(2.4, bw - 0.3)
			y0 = y
			yt = y + 2.05
		elif g > y0 - 0.3 or ow < 0.4:
			continue
		var s0 := mid - ow * 0.5
		var s1 := mid + ow * 0.5
		mb.quad("plaster", f.p(prev, y), f.p(s0, y), f.p(s0, y1), f.p(prev, y1), f.n, PLINTH)
		mb.quad("plaster", f.p(s0, yt), f.p(s1, yt), f.p(s1, y1), f.p(s0, y1), f.n, PLINTH)
		if b == door_bay:
			_reveal(mb, f, s0, s1, y0, yt, 0.12, "plaster", PLINTH)
			mb.quad("trim", f.p(s0, y0, 0.12), f.p(s1, y0, 0.12), f.p(s1, yt, 0.12), f.p(s0, yt, 0.12), f.n, door_col.lerp(WHITE, 0.5))
			for r in range(1, 4):
				var yy := lerpf(y0, yt, float(r) / 4.0)
				mb.quad("trim", f.p(s0, yy - 0.02, 0.1), f.p(s1, yy - 0.02, 0.1), f.p(s1, yy + 0.02, 0.1), f.p(s0, yy + 0.02, 0.1), f.n, door_col.darkened(0.3))
		else:
			mb.quad("plaster", f.p(s0, y), f.p(s1, y), f.p(s1, y0), f.p(s0, y0), f.n, PLINTH)
			_window(mb, f, s0, s1, y0, yt, 0.12, "plaster", PLINTH, trim, false, 3)
		prev = s1
	mb.quad("plaster", f.p(prev, y), f.p(length, y), f.p(length, y1), f.p(prev, y1), f.n, PLINTH)


## The step at a door, or a flight of stairs down to the ground where the door stands above it.
func _steps(mb: MB, f: Face, mid: float, y: float, dw: float) -> void:
	var g := f.ground(mid)
	var drop := y - g
	var hw := dw * 0.5 + 0.25
	if drop < 0.3 or drop > 2.6:
		mb.box("trim", f.p(mid, y - 0.09, -0.35), f.t, Vector3.UP, f.n, Vector3(hw, 0.09, 0.4), PLINTH)
		return
	var n := int(ceil(drop / 0.18))
	var rise := drop / float(n)
	# a landing in front of the door, then the steps running down along the wall
	var deep := g - 0.4
	mb.box("trim", f.p(mid, (y - 0.02 + deep) * 0.5, -0.55), f.t, Vector3.UP, f.n, Vector3(hw, (y - 0.02 - deep) * 0.5, 0.55), PLINTH)
	var dir := 1.0 if mid + hw + float(n) * 0.28 < f.length else -1.0
	for k in range(1, n):
		var top := y - 0.02 - rise * float(k)
		var s := mid + dir * (hw + (float(k) - 0.5) * 0.28)
		mb.box("trim", f.p(s, (top + deep) * 0.5, -0.55), f.t, Vector3.UP, f.n, Vector3(0.14, (top - deep) * 0.5, 0.55), PLINTH)
	# railing on the outer side
	var rail := Color(0.12, 0.12, 0.13)
	var s_end := mid + dir * (hw + float(n - 1) * 0.28)
	mb.box("trim", f.p(mid - dir * hw, y + 0.5, -1.07), f.t, Vector3.UP, f.n, Vector3(0.025, 0.5, 0.025), rail)
	mb.box("trim", f.p(mid + dir * hw, y + 0.5, -1.07), f.t, Vector3.UP, f.n, Vector3(0.025, 0.5, 0.025), rail)
	mb.box("trim", f.p(s_end, g + rise + 0.5, -1.07), f.t, Vector3.UP, f.n, Vector3(0.025, 0.5, 0.025), rail)
	mb.quad_auto("trim", f.p(mid - dir * hw, y + 0.95, -1.07), f.p(mid + dir * hw, y + 0.95, -1.07), f.p(mid + dir * hw, y + 1.0, -1.07), f.p(mid - dir * hw, y + 1.0, -1.07), f.n, rail)
	mb.quad_auto("trim", f.p(mid + dir * hw, y + 0.95, -1.07), f.p(s_end, g + rise + 0.95, -1.07), f.p(s_end, g + rise + 1.0, -1.07), f.p(mid + dir * hw, y + 1.0, -1.07), f.n, rail)


func _reveal(mb: MB, f: Face, s0: float, s1: float, y0: float, y1: float, d: float, wall_m: String, wall: Color) -> void:
	mb.quad(wall_m, f.p(s0, y0), f.p(s0, y1), f.p(s0, y1, d), f.p(s0, y0, d), f.t, wall)
	mb.quad(wall_m, f.p(s1, y0), f.p(s1, y1), f.p(s1, y1, d), f.p(s1, y0, d), -f.t, wall)
	mb.quad(wall_m, f.p(s0, y1), f.p(s1, y1), f.p(s1, y1, d), f.p(s0, y1, d), Vector3.DOWN, wall)
	mb.quad(wall_m, f.p(s0, y0), f.p(s1, y0), f.p(s1, y0, d), f.p(s0, y0, d), Vector3.UP, wall)


func _window(mb: MB, f: Face, s0: float, s1: float, y0: float, y1: float, d: float, wall_m: String, wall: Color, trim: Color, sill: bool, pane: int) -> void:
	_reveal(mb, f, s0, s1, y0, y1, d, wall_m, wall)
	mb.quad("glass", f.p(s0, y0, d), f.p(s1, y0, d), f.p(s1, y1, d), f.p(s0, y1, d), f.n, GLASS)
	var fw := 0.06
	var e := d - 0.03
	mb.quad("trim", f.p(s0, y0, e), f.p(s0 + fw, y0, e), f.p(s0 + fw, y1, e), f.p(s0, y1, e), f.n, trim)
	mb.quad("trim", f.p(s1 - fw, y0, e), f.p(s1, y0, e), f.p(s1, y1, e), f.p(s1 - fw, y1, e), f.n, trim)
	mb.quad("trim", f.p(s0, y0, e), f.p(s1, y0, e), f.p(s1, y0 + fw, e), f.p(s0, y0 + fw, e), f.n, trim)
	mb.quad("trim", f.p(s0, y1 - fw, e), f.p(s1, y1 - fw, e), f.p(s1, y1, e), f.p(s0, y1, e), f.n, trim)
	var sm := (s0 + s1) * 0.5
	if pane == 1 or pane == 2:
		mb.quad("trim", f.p(sm - fw * 0.5, y0, e), f.p(sm + fw * 0.5, y0, e), f.p(sm + fw * 0.5, y1, e), f.p(sm - fw * 0.5, y1, e), f.n, trim)
	if pane == 0 or pane == 2:
		var ty := lerpf(y0, y1, 0.66 if pane == 0 else 0.5)
		mb.quad("trim", f.p(s0, ty - fw * 0.4, e), f.p(s1, ty - fw * 0.4, e), f.p(s1, ty + fw * 0.4, e), f.p(s0, ty + fw * 0.4, e), f.n, trim)
	if sill:
		mb.box("trim", f.p(sm, y0 - 0.03, -0.04), f.t, Vector3.UP, f.n, Vector3((s1 - s0) * 0.5 + 0.06, 0.03, 0.08), trim)
