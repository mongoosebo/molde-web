extends Node3D
## Hand-detailed buildings around Rådhusplassen: Molde rådhus, Storgata 31 and 33, Aandahls.
## Real footprints from the map; facades are modelled with recessed windows, frames, sills,
## shopfronts, roofs and textured materials (textures made by tools/make_textures.py).

const TEX_DIR := "res://world/textures/"

const SPECS := {
	# Modernist town hall (1966): board-formed concrete and gold-tinted glass, rose garden on the roof.
	"radhus": {
		"floors": 3, "g_h": 3.6, "f_h": 3.1, "bay": 3.2, "margin": 0.5,
		"g_open": [2.7, 2.6, 0.35], "u_open": [2.7, 1.7, 0.85],
		"wall": "concrete", "plinth": "concrete_dark", "glass": "glass_gold", "frame": "bronze",
		"top": 0.8, "roof": "garden", "sign": "MOLDE RÅDHUS", "sign_color": Color(0.80, 0.62, 0.22), "sign_out": 0.80},
	# Post-war reconstruction blocks on Storgata: painted plaster, shops at street level, tiled hip roofs.
	"storgata31": {
		"floors": 3, "g_h": 3.8, "f_h": 3.0, "bay": 3.0, "margin": 0.7,
		"g_open": [2.3, 2.6, 0.45], "u_open": [1.25, 1.5, 0.9],
		"wall": "plaster_terracotta", "plinth": "concrete_dark", "glass": "glass", "frame": "white",
		"top": 0.35, "roof": "hip", "roof_mat": "tile_red", "sills": true, "band": true},
	"storgata33": {
		"floors": 3, "g_h": 3.8, "f_h": 3.0, "bay": 3.0, "margin": 0.7,
		"g_open": [2.3, 2.6, 0.45], "u_open": [1.25, 1.5, 0.9],
		"wall": "plaster_terracotta", "plinth": "concrete_dark", "glass": "glass", "frame": "white",
		"top": 0.35, "roof": "hip", "roof_mat": "tile_slate", "sills": true, "band": true},
	# Department store: pale render, long shop windows under a canopy, ribbon windows above.
	"aandahls": {
		"floors": 3, "g_h": 4.2, "f_h": 3.4, "bay": 3.4, "margin": 0.5,
		"g_open": [3.0, 3.0, 0.3], "u_open": [3.0, 1.6, 1.0],
		"wall": "plaster_white", "plinth": "concrete_dark", "glass": "glass", "frame": "dark",
		"top": 0.9, "roof": "flat", "canopy": true, "sign": "AANDAHLS", "sign_color": Color(0.08, 0.08, 0.09)},
}

var world
var _mats := {}
var _tex_cache := {}


## Collects triangles per material, with the winding chosen from the wanted normal.
class MB:
	var surf := {}

	func tri(m: String, a: Vector3, b: Vector3, c: Vector3, nrm: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO) -> void:
		if not surf.has(m):
			surf[m] = [PackedVector3Array(), PackedVector3Array(), PackedVector2Array()]
		if (c - a).cross(b - a).dot(nrm) < 0.0:
			var t := b
			b = c
			c = t
			var tu := ub
			ub = uc
			uc = tu
		var s: Array = surf[m]
		s[0].append(a); s[0].append(b); s[0].append(c)
		s[1].append(nrm); s[1].append(nrm); s[1].append(nrm)
		s[2].append(ua); s[2].append(ub); s[2].append(uc)

	func quad(m: String, a: Vector3, b: Vector3, c: Vector3, d: Vector3, nrm: Vector3, ua := Vector2.ZERO, ub := Vector2.ZERO, uc := Vector2.ZERO, ud := Vector2.ZERO) -> void:
		tri(m, a, b, c, nrm, ua, ub, uc)
		tri(m, a, c, d, nrm, ua, uc, ud)

	## Box with half-extents h along the axes ax, ay, az.
	func box(m: String, c: Vector3, ax: Vector3, ay: Vector3, az: Vector3, h: Vector3) -> void:
		var x := ax * h.x
		var y := ay * h.y
		var z := az * h.z
		quad(m, c + x - y - z, c + x + y - z, c + x + y + z, c + x - y + z, ax)
		quad(m, c - x - y - z, c - x + y - z, c - x + y + z, c - x - y + z, -ax)
		quad(m, c - x + y - z, c + x + y - z, c + x + y + z, c - x + y + z, ay)
		quad(m, c - x - y - z, c + x - y - z, c + x - y + z, c - x - y + z, -ay)
		quad(m, c - x - y + z, c + x - y + z, c + x + y + z, c - x + y + z, az)
		quad(m, c - x - y - z, c + x - y - z, c + x + y - z, c - x + y - z, -az)


## One wall of a building: a is the start corner, t runs along the wall, n points outward.
class Face:
	var a: Vector3
	var t: Vector3
	var n: Vector3
	var length: float

	func p(s: float, y: float, depth: float = 0.0) -> Vector3:
		return Vector3(a.x, y, a.z) + t * s - n * depth


# ------------------------------------------------------------------ materials
func _tex(name: String) -> ImageTexture:
	if _tex_cache.has(name):
		return _tex_cache[name]
	var img := Image.new()
	img.load_png_from_buffer(FileAccess.get_file_as_bytes(TEX_DIR + name + ".png"))
	img.generate_mipmaps()
	var tex := ImageTexture.create_from_image(img)
	_tex_cache[name] = tex
	return tex


func _textured(tex: String, tint: Color, tile_m: float, rough: float, triplanar := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = _tex(tex + "_albedo")
	m.albedo_color = tint
	m.roughness = rough
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	if triplanar:
		m.normal_enabled = true
		m.normal_texture = _tex(tex + "_normal")
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE / tile_m
	return m


func _plain(color: Color, rough: float, metallic := 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = rough
	m.metallic = metallic
	return m


func _make_materials() -> void:
	_mats = {
		"concrete": _textured("concrete", Color(1, 1, 1), 3.0, 0.9),
		"concrete_dark": _textured("concrete", Color(0.55, 0.54, 0.53), 3.0, 0.92),
		"plaster_ochre": _textured("plaster", Color(0.80, 0.63, 0.33), 2.0, 0.93),
		"plaster_terracotta": _textured("plaster", Color(0.72, 0.36, 0.25), 2.0, 0.93),
		"plaster_sage": _textured("plaster", Color(0.66, 0.72, 0.64), 2.0, 0.93),
		"plaster_white": _textured("plaster", Color(0.90, 0.89, 0.85), 2.0, 0.9),
		"paving": _textured("paving", Color(1, 1, 1), 2.0, 0.85),
		"gravel": _textured("gravel", Color(0.75, 0.75, 0.75), 2.0, 0.97),
		"tile_red": _textured("rooftile", Color(0.60, 0.27, 0.19), 2.0, 0.8, false),
		"tile_slate": _textured("rooftile", Color(0.30, 0.32, 0.35), 2.0, 0.75, false),
		"glass": _plain(Color(0.07, 0.10, 0.12), 0.06, 0.85),
		"glass_gold": _plain(Color(0.62, 0.45, 0.17), 0.10, 0.95),
		"white": _plain(Color(0.88, 0.88, 0.85), 0.6),
		"dark": _plain(Color(0.10, 0.10, 0.11), 0.5, 0.3),
		"bronze": _plain(Color(0.23, 0.17, 0.10), 0.4, 0.7),
		"door": _plain(Color(0.25, 0.15, 0.09), 0.6),
		"soil": _plain(Color(0.10, 0.08, 0.06), 1.0),
		"lawn": _plain(Color(0.16, 0.26, 0.10), 1.0),
		"leaf": _plain(Color(0.10, 0.22, 0.09), 0.9),
		"rose": _plain(Color(0.70, 0.07, 0.12), 0.7),
		"rose_pink": _plain(Color(0.88, 0.45, 0.52), 0.7),
		"water": _plain(Color(0.05, 0.12, 0.14), 0.05, 0.6),
		"statue": _plain(Color(0.085, 0.075, 0.065), 0.42, 0.8),       # dark bronze
		"fin": _plain(Color(0.36, 0.26, 0.15), 0.45, 0.75),
		"plaza": _textured("slabs", Color(0.60, 0.44, 0.40), 4.4, 0.75),
	}
	_mats["tile_red"].uv1_scale = Vector3(0.5, 0.5, 0.5)
	_mats["tile_slate"].uv1_scale = Vector3(0.5, 0.5, 0.5)


# ------------------------------------------------------------------ entry
func build(w, landmarks: Array, plaza: Array) -> void:
	world = w
	_make_materials()
	var plaza_poly := PackedVector2Array()
	for i in plaza.size() / 2:
		plaza_poly.append(Vector2(plaza[2 * i], plaza[2 * i + 1]))
	var plaza_centre := Vector2.ZERO
	for p in plaza_poly:
		plaza_centre += p
	if plaza_poly.size() > 0:
		plaza_centre /= float(plaza_poly.size())
		_build_plaza(plaza_poly, plaza_centre)
	for lm in landmarks:
		var key: String = lm["key"]
		if not SPECS.has(key):
			continue
		var flat: Array = lm["pts"]
		var poly := PackedVector2Array()
		for i in flat.size() / 2:
			poly.append(Vector2(flat[2 * i], flat[2 * i + 1]))
		_build_landmark(key, SPECS[key], poly, lm["ymin"], lm["ymax"], plaza_centre, lm.get("h", 0.0), lm.get("rise", 0.0))


func _commit(mb: MB, node_name: String) -> MeshInstance3D:
	var mesh := ArrayMesh.new()
	for m in mb.surf:
		var s: Array = mb.surf[m]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = s[0]
		arrays[Mesh.ARRAY_NORMAL] = s[1]
		arrays[Mesh.ARRAY_TEX_UV] = s[2]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _mats[m])
	var mi := MeshInstance3D.new()
	mi.name = node_name
	mi.mesh = mesh
	add_child(mi)
	return mi


# ------------------------------------------------------------------ facades
func _faces(poly: PackedVector2Array) -> Array:
	var out := []
	var n := poly.size()
	for i in n:
		var a := poly[i]
		var b := poly[(i + 1) % n]
		var length := a.distance_to(b)
		if length < 0.05:
			continue
		var t2 := (b - a) / length
		var n2 := Vector2(t2.y, -t2.x)
		if Geometry2D.is_point_in_polygon((a + b) * 0.5 + n2 * 0.15, poly):
			n2 = -n2
		var f := Face.new()
		f.a = Vector3(a.x, 0.0, a.y)
		f.t = Vector3(t2.x, 0.0, t2.y)
		f.n = Vector3(n2.x, 0.0, n2.y)
		f.length = length
		out.append(f)
	return out


func _opening(mb: MB, f: Face, s0: float, s1: float, y0: float, y1: float, spec: Dictionary, upper: bool, door: bool) -> void:
	var wall: String = spec["wall"]
	var frame: String = spec["frame"]
	var d := 0.24
	mb.quad(wall, f.p(s0, y0), f.p(s0, y1), f.p(s0, y1, d), f.p(s0, y0, d), f.t)
	mb.quad(wall, f.p(s1, y0), f.p(s1, y1), f.p(s1, y1, d), f.p(s1, y0, d), -f.t)
	mb.quad(wall, f.p(s0, y1), f.p(s1, y1), f.p(s1, y1, d), f.p(s0, y1, d), Vector3.DOWN)
	mb.quad(wall, f.p(s0, y0), f.p(s1, y0), f.p(s1, y0, d), f.p(s0, y0, d), Vector3.UP)
	var pane: String = spec["glass"]
	mb.quad(pane, f.p(s0, y0, d), f.p(s1, y0, d), f.p(s1, y1, d), f.p(s0, y1, d), f.n)
	if door:
		var mid := (s0 + s1) * 0.5
		mb.quad("door", f.p(mid - 0.95, y0, d - 0.03), f.p(mid + 0.95, y0, d - 0.03), f.p(mid + 0.95, y0 + 2.25, d - 0.03), f.p(mid - 0.95, y0 + 2.25, d - 0.03), f.n)

	# Frame: border, mullions, and a transom on the upper-floor windows.
	var fw := 0.075
	var e := d - 0.05
	var strips := [[s0, s0 + fw, y0, y1], [s1 - fw, s1, y0, y1], [s0, s1, y0, y0 + fw], [s0, s1, y1 - fw, y1]]
	var panes := maxi(1, int(round((s1 - s0) / (0.75 if upper else 1.4))))
	for k in range(1, panes):
		var sm := lerpf(s0, s1, float(k) / float(panes))
		strips.append([sm - fw * 0.5, sm + fw * 0.5, y0, y1])
	var ty := lerpf(y0, y1, 0.72 if upper else 0.8)
	strips.append([s0, s1, ty - fw * 0.5, ty + fw * 0.5])
	for st in strips:
		var a0: float = st[0]
		var a1: float = st[1]
		var b0: float = st[2]
		var b1: float = st[3]
		mb.quad(frame, f.p(a0, b0, e), f.p(a1, b0, e), f.p(a1, b1, e), f.p(a0, b1, e), f.n)
		# give the bars some depth
		mb.quad(frame, f.p(a0, b0, e), f.p(a0, b1, e), f.p(a0, b1, d), f.p(a0, b0, d), -f.t)
		mb.quad(frame, f.p(a1, b0, e), f.p(a1, b1, e), f.p(a1, b1, d), f.p(a1, b0, d), f.t)

	if spec.get("sills", false) and upper:
		mb.box(frame, f.p((s0 + s1) * 0.5, y0 - 0.035, -0.05), f.t, Vector3.UP, f.n, Vector3((s1 - s0) * 0.5 + 0.06, 0.035, 0.1))


func _facade(mb: MB, f: Face, ybase: float, yg: float, ytop: float, spec: Dictionary, with_door: bool) -> void:
	var wall: String = spec["wall"]
	var plinth: String = spec["plinth"]
	var length := f.length
	var floors: int = spec["floors"]
	var margin: float = spec["margin"]
	var bay: float = spec["bay"]
	var bays := int((length - 2.0 * margin) / bay)
	if length < 2.2:
		bays = 0
	var bw := (length - 2.0 * margin) / float(maxi(bays, 1))

	mb.quad(plinth, f.p(0, ybase), f.p(length, ybase), f.p(length, yg), f.p(0, yg), f.n)
	var y := yg
	for fl in floors:
		var fh: float = spec["g_h"] if fl == 0 else spec["f_h"]
		var op: Array = spec["g_open"] if fl == 0 else spec["u_open"]
		var ow: float = minf(op[0], bw - 0.3)
		var oh: float = op[1]
		var sill: float = op[2]
		var y0 := y + sill
		var y1 := y0 + oh
		if bays == 0:
			mb.quad(wall, f.p(0, y), f.p(length, y), f.p(length, y + fh), f.p(0, y + fh), f.n)
		else:
			mb.quad(plinth if fl == 0 else wall, f.p(0, y), f.p(length, y), f.p(length, y0), f.p(0, y0), f.n)
			mb.quad(wall, f.p(0, y1), f.p(length, y1), f.p(length, y + fh), f.p(0, y + fh), f.n)
			var prev := 0.0
			for b in bays:
				var s0 := margin + b * bw + (bw - ow) * 0.5
				var s1 := s0 + ow
				mb.quad(wall, f.p(prev, y0), f.p(s0, y0), f.p(s0, y1), f.p(prev, y1), f.n)
				_opening(mb, f, s0, s1, y0, y1, spec, fl > 0, with_door and fl == 0 and b == bays / 2)
				prev = s1
			mb.quad(wall, f.p(prev, y0), f.p(length, y0), f.p(length, y1), f.p(prev, y1), f.n)
		y += fh
		if fl == 0 and spec.get("band", false):
			mb.box(spec["frame"], f.p(length * 0.5, y - 0.02, -0.04), f.t, Vector3.UP, f.n, Vector3(length * 0.5 + 0.08, 0.09, 0.08))
		if fl == 0 and spec.get("canopy", false) and length > 6.0:
			mb.box(spec["frame"], f.p(length * 0.5, y - 0.25, -0.7), f.t, Vector3.UP, f.n, Vector3(length * 0.5 + 0.7, 0.1, 0.75))
	mb.quad(wall, f.p(0, y), f.p(length, y), f.p(length, ytop), f.p(0, ytop), f.n)
	if spec["roof"] == "hip":
		# eaves cornice
		mb.box(spec["frame"], f.p(length * 0.5, ytop - 0.12, -0.06), f.t, Vector3.UP, f.n, Vector3(length * 0.5 + 0.12, 0.12, 0.1))


## The town hall, after photographs of it: raw concrete piers at the ends of every wall, and between
## them gold-tinted glass behind a close row of upright bronze fins that run on above the roof line.
## The wall on the square has the glazed entrance under a heavy concrete beam that carries the name.
func _radhus_facade(mb: MB, f: Face, ybase: float, yg: float, ytop: float, front: bool) -> void:
	var length := f.length
	mb.quad("concrete", f.p(0, ybase), f.p(length, ybase), f.p(length, yg), f.p(0, yg), f.n)
	if length < 5.0:
		mb.quad("concrete", f.p(0, yg), f.p(length, yg), f.p(length, ytop), f.p(0, ytop), f.n)
		return
	var pier := clampf(length * 0.12, 1.2, 2.8)
	for s in [pier * 0.5, length - pier * 0.5]:
		var sc: float = s
		mb.box("concrete", f.p(sc, (yg + ytop) * 0.5 + 0.3, -0.12), f.t, Vector3.UP, f.n, Vector3(pier * 0.5, (ytop - yg) * 0.5 + 0.3, 0.3))
	var s0 := pier
	var s1 := length - pier
	var back := 0.4                                   # the glass stands back from the piers
	var glass_lo := yg + 0.5
	if front:
		# entrance: dark glass and doors, the beam with the name, steps down to the square
		var g_top := yg + 3.3
		var beam_top := yg + 4.6
		mb.quad("glass", f.p(s0, yg, back), f.p(s1, yg, back), f.p(s1, g_top, back), f.p(s0, g_top, back), f.n)
		var doors := maxi(2, int((s1 - s0) / 1.7))
		for k in doors + 1:
			var sm := lerpf(s0, s1, float(k) / float(doors))
			mb.box("fin", f.p(sm, (yg + g_top) * 0.5, back - 0.05), f.t, Vector3.UP, f.n, Vector3(0.045, (g_top - yg) * 0.5, 0.07))
		mb.box("concrete", f.p((s0 + s1) * 0.5, (g_top + beam_top) * 0.5, -0.35), f.t, Vector3.UP, f.n, Vector3((s1 - s0) * 0.5 + 0.4, (beam_top - g_top) * 0.5, 0.42))
		for k in 3:
			mb.box("concrete", f.p((s0 + s1) * 0.5, yg - 0.08 - 0.16 * float(k), -0.6 - 0.4 * float(k)), f.t, Vector3.UP, f.n,
				Vector3((s1 - s0) * 0.5 - 0.5 + 0.4 * float(k), 0.08, 0.6 + 0.4 * float(k)))
		glass_lo = beam_top
	else:
		mb.quad("concrete", f.p(s0, yg, back), f.p(s1, yg, back), f.p(s1, glass_lo, back), f.p(s0, glass_lo, back), f.n)
	mb.quad("glass_gold", f.p(s0, glass_lo, back), f.p(s1, glass_lo, back), f.p(s1, ytop, back), f.p(s0, ytop, back), f.n)
	# floor edges showing behind the glass, then the fins
	var yf := glass_lo + 3.1
	while yf < ytop - 1.0:
		mb.box("fin", f.p((s0 + s1) * 0.5, yf, back - 0.03), f.t, Vector3.UP, f.n, Vector3((s1 - s0) * 0.5, 0.16, 0.04))
		yf += 3.1
	var count := maxi(2, int((s1 - s0) / (0.75 if front else 0.55)))
	for k in count + 1:
		var sf := lerpf(s0, s1, float(k) / float(count))
		mb.box("fin", f.p(sf, (glass_lo + ytop) * 0.5 + 0.3, 0.12), f.t, Vector3.UP, f.n, Vector3(0.04, (ytop - glass_lo) * 0.5 + 0.3, 0.3))
	mb.quad("concrete", f.p(s0, ytop, back), f.p(s1, ytop, back), f.p(s1, ytop, -0.02), f.p(s0, ytop, -0.02), Vector3.UP)


# ------------------------------------------------------------------ roofs
func _flat_roof(mb: MB, poly: PackedVector2Array, faces: Array, ytop: float, cover: String, wall: String) -> float:
	var yr := ytop - 0.75
	var tris := Geometry2D.triangulate_polygon(poly)
	var i := 0
	while i + 2 < tris.size():
		var a := poly[tris[i]]
		var b := poly[tris[i + 1]]
		var c := poly[tris[i + 2]]
		mb.tri(cover, Vector3(a.x, yr, a.y), Vector3(b.x, yr, b.y), Vector3(c.x, yr, c.y), Vector3.UP)
		i += 3
	for f in faces:
		var fc: Face = f
		# inside of the parapet and its coping
		mb.quad(wall, fc.p(0, yr, 0.3), fc.p(fc.length, yr, 0.3), fc.p(fc.length, ytop, 0.3), fc.p(0, ytop, 0.3), -fc.n)
		mb.quad(wall, fc.p(0, ytop, -0.04), fc.p(fc.length, ytop, -0.04), fc.p(fc.length, ytop, 0.3), fc.p(0, ytop, 0.3), Vector3.UP)
	return yr


func _hip_roof(mb: MB, poly: PackedVector2Array, ytop: float, cover: String, soffit: String) -> void:
	# Oriented bounding box along the longest wall, then a hipped roof over it with eaves.
	var best := 0.0
	var u := Vector2.RIGHT
	for i in poly.size():
		var e := poly[(i + 1) % poly.size()] - poly[i]
		if e.length() > best:
			best = e.length()
			u = e.normalized()
	var v := Vector2(-u.y, u.x)
	var umin := INF
	var umax := -INF
	var vmin := INF
	var vmax := -INF
	for p in poly:
		umin = minf(umin, p.dot(u)); umax = maxf(umax, p.dot(u))
		vmin = minf(vmin, p.dot(v)); vmax = maxf(vmax, p.dot(v))
	var eave := 0.55
	umin -= eave; umax += eave; vmin -= eave; vmax += eave
	if vmax - vmin > umax - umin:       # make u the long axis
		var tv := u
		u = v
		v = tv
		var a0 := umin
		var a1 := umax
		umin = vmin; umax = vmax; vmin = a0; vmax = a1
	var half := (vmax - vmin) * 0.5
	var rise := half * tan(deg_to_rad(33.0))
	var vm := (vmin + vmax) * 0.5
	var c00 := _uv3(u, v, umin, vmin, ytop)
	var c10 := _uv3(u, v, umax, vmin, ytop)
	var c11 := _uv3(u, v, umax, vmax, ytop)
	var c01 := _uv3(u, v, umin, vmax, ytop)
	var r0 := _uv3(u, v, umin + half, vm, ytop + rise)
	var r1 := _uv3(u, v, umax - half, vm, ytop + rise)
	var slope := sqrt(half * half + rise * rise)
	var ulen := umax - umin
	var u3 := Vector3(u.x, 0, u.y)
	var v3 := Vector3(v.x, 0, v.y)
	var up_n := cos(deg_to_rad(33.0))
	var out_n := sin(deg_to_rad(33.0))
	# long slopes (texture: u along the eave, v from ridge down to eave)
	mb.quad(cover, c00, c10, r1, r0, (Vector3.UP * up_n - v3 * out_n), Vector2(0, slope), Vector2(ulen, slope), Vector2(ulen - half, 0), Vector2(half, 0))
	mb.quad(cover, c01, c11, r1, r0, (Vector3.UP * up_n + v3 * out_n), Vector2(0, slope), Vector2(ulen, slope), Vector2(ulen - half, 0), Vector2(half, 0))
	# hipped ends
	mb.tri(cover, c00, c01, r0, (Vector3.UP * up_n - u3 * out_n), Vector2(0, slope), Vector2(2.0 * half, slope), Vector2(half, 0))
	mb.tri(cover, c10, c11, r1, (Vector3.UP * up_n + u3 * out_n), Vector2(0, slope), Vector2(2.0 * half, slope), Vector2(half, 0))
	# soffit under the eaves
	mb.quad(soffit, c00, c10, c11, c01, Vector3.DOWN)
	# ridge cap
	mb.box("dark", (r0 + r1) * 0.5 + Vector3(0, 0.03, 0), u3, Vector3.UP, v3, Vector3((r1 - r0).length() * 0.5, 0.07, 0.12))


func _uv3(u: Vector2, v: Vector2, a: float, b: float, y: float) -> Vector3:
	var p := u * a + v * b
	return Vector3(p.x, y, p.y)


func _roof_garden(poly: PackedVector2Array, yr: float) -> void:
	# The town hall's roof terrace is a rose garden: planters of roses, lawn, and a small pool.
	var mb := MB.new()
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = Vector2(minf(lo.x, p.x), minf(lo.y, p.y))
		hi = Vector2(maxf(hi.x, p.x), maxf(hi.y, p.y))
	var bush := SphereMesh.new()
	bush.radius = 0.38
	bush.height = 0.7
	bush.radial_segments = 8
	bush.rings = 4
	bush.material = _mats["leaf"]
	var bloom := SphereMesh.new()
	bloom.radius = 0.09
	bloom.height = 0.18
	bloom.radial_segments = 6
	bloom.rings = 3
	var bushes := []
	var blooms := [[], []]
	var rng := RandomNumberGenerator.new()
	rng.seed = 1966
	var x := lo.x + 3.0
	while x < hi.x - 3.0:
		var z := lo.y + 3.0
		while z < hi.y - 3.0:
			var c := Vector2(x, z)
			var ok := true
			for off in [Vector2(3.2, 0), Vector2(-3.2, 0), Vector2(0, 3.2), Vector2(0, -3.2)]:
				if not Geometry2D.is_point_in_polygon(c + off, poly):
					ok = false
			if ok:
				var cell := int(round(x / 5.5)) + int(round(z / 5.5))
				if cell % 3 == 0:
					mb.box("lawn", Vector3(x, yr + 0.04, z), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(2.3, 0.04, 2.3))
				else:
					mb.box("concrete", Vector3(x, yr + 0.22, z), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1.7, 0.22, 0.75))
					mb.box("soil", Vector3(x, yr + 0.45, z), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(1.6, 0.02, 0.65))
					for k in 4:
						var bp := Vector3(x - 1.2 + k * 0.8, yr + 0.72, z + rng.randf_range(-0.15, 0.15))
						bushes.append(Transform3D(Basis().scaled(Vector3.ONE * rng.randf_range(0.85, 1.2)), bp))
						for j in 6:
							var dirv := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.1, 1), rng.randf_range(-1, 1)).normalized()
							blooms[(k + int(x)) % 2].append(Transform3D(Basis(), bp + dirv * 0.36))
			z += 5.5
		x += 5.5
	_commit(mb, "RoofGarden")
	_multimesh(bush, bushes)
	for i in 2:
		var bm: SphereMesh = bloom.duplicate()
		bm.material = _mats["rose" if i == 0 else "rose_pink"]
		_multimesh(bm, blooms[i])


func _multimesh(mesh: Mesh, xforms: Array) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	add_child(mmi)


# ------------------------------------------------------------------ one building
func _build_landmark(key: String, spec: Dictionary, poly: PackedVector2Array, ymin: float, ymax: float, plaza_centre: Vector2, measured_h: float, measured_rise: float) -> void:
	var mb := MB.new()
	var faces := _faces(poly)
	var ybase := ymin - 1.0
	var yg := ymin + 0.25
	var floors: int = spec["floors"]
	var g_h: float = spec["g_h"]
	var f_h: float = spec["f_h"]
	var top: float = spec["top"]
	if measured_h > 0.0:
		# Height above the lowest ground, from Kartverket's laser data. Where a pitched roof was not
		# resolved, the measurement is an average over the roof, so take a little off for the eaves.
		var wall_h := measured_h
		if spec["roof"] == "hip" and measured_rise <= 0.0:
			wall_h -= 1.3
		floors = maxi(1, int(round((wall_h - g_h - top) / f_h)) + 1)
		spec = spec.duplicate()
		spec["floors"] = floors
	var ytop := yg + g_h + float(floors - 1) * f_h + top

	# The entrance and the sign go on the wall that faces the square.
	var front: Face = null
	var best := INF
	for f in faces:
		var fc: Face = f
		if fc.length < 7.0:
			continue
		var mid := fc.p(fc.length * 0.5, 0)
		var to_plaza := Vector2(plaza_centre.x - mid.x, plaza_centre.y - mid.z)
		var score := to_plaza.length() - fc.length * 0.6
		if key == "aandahls":       # the store fronts Storgata, to the south
			score = -fc.n.z * 100.0 - fc.length
		elif to_plaza.dot(Vector2(fc.n.x, fc.n.z)) <= 0.0:
			continue
		if score < best:
			best = score
			front = fc
	for f in faces:
		if key == "radhus":
			_radhus_facade(mb, f, ybase, yg, ytop, f == front)
		else:
			_facade(mb, f, ybase, yg, ytop, spec, f == front)

	for d in world.meta.get("doors", {}).get(key, []):
		# a glazed double door where someone who knows the building says there is one, with its sign over it
		var at := Vector3(d[0], 0, d[1])
		var wall: Face = null
		var near := 6.0
		var s_at := 0.0
		for f in faces:
			var fc: Face = f
			var rel := at - Vector3(fc.a.x, 0, fc.a.z)
			var sd := clampf(rel.dot(fc.t), 1.4, fc.length - 1.4)
			var off := (Vector3(fc.a.x, 0, fc.a.z) + fc.t * sd).distance_to(at)
			if fc.length > 3.2 and off < near:
				near = off
				wall = fc
				s_at = sd
		if wall == null:
			continue
		var dh := 2.35
		mb.box(spec["frame"], wall.p(s_at, yg + dh * 0.5 + 0.1, -0.06), wall.t, Vector3.UP, wall.n, Vector3(1.15, dh * 0.5 + 0.1, 0.07))
		for sgn in [-1.0, 1.0]:
			var sg: float = sgn
			mb.box("glass", wall.p(s_at + sg * 0.5, yg + dh * 0.5, -0.11), wall.t, Vector3.UP, wall.n, Vector3(0.44, dh * 0.5 - 0.08, 0.03))
			mb.box("dark", wall.p(s_at + sg * 0.1, yg + 1.05, -0.16), wall.t, Vector3.UP, wall.n, Vector3(0.02, 0.22, 0.02))
		mb.box("dark", wall.p(s_at, yg + dh + 0.55, -0.1), wall.t, Vector3.UP, wall.n, Vector3(1.25, 0.26, 0.05))
		var sign_label := Label3D.new()
		sign_label.text = str(d[2])
		sign_label.font_size = 96
		sign_label.pixel_size = 0.0036
		sign_label.outline_size = 0
		sign_label.modulate = Color(0.95, 0.95, 0.93)
		sign_label.shaded = false
		sign_label.double_sided = false
		sign_label.transform = Transform3D(Basis(Vector3.UP.cross(wall.n), Vector3.UP, wall.n), wall.p(s_at, yg + dh + 0.55, -0.16))
		add_child(sign_label)
	var roof: String = spec["roof"]
	if roof == "hip":
		_hip_roof(mb, poly, ytop, spec["roof_mat"], spec["frame"])
	else:
		var yr := _flat_roof(mb, poly, faces, ytop, "gravel", spec["wall"])
		if roof == "garden":
			_roof_garden(poly, yr)
	_commit(mb, key)

	if spec.has("sign") and front != null:
		var label := Label3D.new()
		label.text = spec["sign"]
		label.font_size = 160
		label.pixel_size = 0.0042
		label.outline_size = 0
		label.modulate = spec["sign_color"]
		label.shaded = not spec.has("sign_out")
		label.double_sided = false
		var pos := front.p(front.length * 0.5, yg + g_h + 0.47, -(spec.get("sign_out", 0.06) as float))
		label.transform = Transform3D(Basis(Vector3.UP.cross(front.n), Vector3.UP, front.n), pos)
		add_child(label)

	# Collision: the plain prism.
	var cv := PackedVector3Array()
	for f in faces:
		var fc: Face = f
		cv.append(fc.p(0, ybase)); cv.append(fc.p(fc.length, ybase)); cv.append(fc.p(fc.length, ytop))
		cv.append(fc.p(0, ybase)); cv.append(fc.p(fc.length, ytop)); cv.append(fc.p(0, ytop))
	var tris := Geometry2D.triangulate_polygon(poly)
	for idx in tris:
		cv.append(Vector3(poly[idx].x, ytop - 0.75, poly[idx].y))
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(cv)
	var col := CollisionShape3D.new()
	col.shape = shape
	var body := StaticBody3D.new()
	body.add_child(col)
	add_child(body)


# ------------------------------------------------------------------ the square
func _build_plaza(poly: PackedVector2Array, centre: Vector2) -> void:
	var mb := MB.new()
	var tris: Array = world.meta.get("plaza_tris", [])
	for i in range(0, tris.size() - 5, 6):
		var a := Vector3(tris[i], world.height_at(tris[i], tris[i + 1]) + 0.07, tris[i + 1])
		var b := Vector3(tris[i + 2], world.height_at(tris[i + 2], tris[i + 3]) + 0.07, tris[i + 3])
		var c := Vector3(tris[i + 4], world.height_at(tris[i + 4], tris[i + 5]) + 0.07, tris[i + 5])
		mb.tri("plaza", a, b, c, Vector3.UP)

	# the long steps from the square up to the terrace in front of the town hall
	var rs = world.meta.get("radhus_steps")
	if rs != null:
		var wa := Vector3(rs["a"][0], 0, rs["a"][1])
		var wb := Vector3(rs["b"][0], 0, rs["b"][1])
		var along := (wb - wa).normalized()
		var outw := Vector3(rs["n"][0], 0, rs["n"][1])
		var length := wa.distance_to(wb)
		var count: int = rs["steps"]
		var tread: float = rs["tread"]
		var rise: float = (rs["top"] - rs["low"]) / float(count)
		var mid := (wa + wb) * 0.5 + outw * float(rs["out"])
		for k in count:
			# step k: its top one rise lower than the one before, its front edge one tread further out
			var top_y: float = rs["top"] + 0.07 - rise * float(k)
			var c := mid + outw * (tread * (float(k) - 0.5)) + Vector3(0, top_y - 0.6, 0)
			mb.box("concrete", c, along, Vector3.UP, outw, Vector3(length * 0.5 - 0.5, 0.6, tread * 0.5))
	# Rosepiken — the Rose Maiden — in her fountain basin.
	var at := centre + Vector2(7.0, -9.0)
	var spot: Array = world.meta.get("rosepiken", [])
	if spot.size() == 2:
		at = Vector2(spot[0], spot[1])                        # where she really stands
	var y: float = world.height_at(at.x, at.y)
	var o := Vector3(at.x, y, at.y)
	var segs := 20
	for i in segs:
		var a0 := TAU * float(i) / segs
		var a1 := TAU * float(i + 1) / segs
		var d0 := Vector3(cos(a0), 0, sin(a0))
		var d1 := Vector3(cos(a1), 0, sin(a1))
		var nm := (d0 + d1).normalized()
		mb.quad("concrete", o + d0 * 2.0, o + d1 * 2.0, o + d1 * 2.0 + Vector3(0, 0.55, 0), o + d0 * 2.0 + Vector3(0, 0.55, 0), nm)
		mb.quad("concrete", o + d0 * 1.75 + Vector3(0, 0.3, 0), o + d1 * 1.75 + Vector3(0, 0.3, 0), o + d1 * 1.75 + Vector3(0, 0.55, 0), o + d0 * 1.75 + Vector3(0, 0.55, 0), -nm)
		mb.quad("concrete", o + d0 * 1.75 + Vector3(0, 0.55, 0), o + d1 * 1.75 + Vector3(0, 0.55, 0), o + d1 * 2.0 + Vector3(0, 0.55, 0), o + d0 * 2.0 + Vector3(0, 0.55, 0), Vector3.UP)
		mb.tri("water", o + Vector3(0, 0.4, 0), o + d0 * 1.75 + Vector3(0, 0.4, 0), o + d1 * 1.75 + Vector3(0, 0.4, 0), Vector3.UP)
	mb.box("concrete", o + Vector3(0, 0.75, 0), Vector3.RIGHT, Vector3.UP, Vector3.BACK, Vector3(0.3, 0.75, 0.3))
	_commit(mb, "Raadhusplassen")
	# the figure: a girl carrying a basket of roses
	var skirt := CylinderMesh.new()
	skirt.top_radius = 0.13
	skirt.bottom_radius = 0.27
	skirt.height = 0.85
	skirt.radial_segments = 10
	_prim(skirt, o + Vector3(0, 1.93, 0), "statue")
	_prim(_capsule(0.15, 0.62), o + Vector3(0, 2.62, 0), "statue")          # body
	_prim(_sphere(0.125), o + Vector3(0, 3.05, 0), "statue")                # head
	_prim(_capsule(0.05, 0.5), o + Vector3(0.2, 2.6, 0.06), "statue")       # the arm round the basket
	_prim(_capsule(0.05, 0.5), o + Vector3(-0.2, 2.58, 0.0), "statue")
	_prim(_sphere(0.19), o + Vector3(0.27, 2.42, 0.14), "statue")           # the basket of roses on her hip
	_prim(_sphere(0.075), o + Vector3(0.27, 2.57, 0.14), "statue")
	_prim(_sphere(0.07), o + Vector3(0.36, 2.54, 0.08), "statue")
	_prim(_sphere(0.07), o + Vector3(0.2, 2.55, 0.22), "statue")
	var shape := CylinderShape3D.new()
	shape.radius = 2.0
	shape.height = 1.2
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = o + Vector3(0, 0.3, 0)
	var body := StaticBody3D.new()
	body.add_child(col)
	add_child(body)


func _capsule(r: float, h: float) -> CapsuleMesh:
	var m := CapsuleMesh.new()
	m.radius = r
	m.height = h
	m.radial_segments = 10
	m.rings = 4
	return m


func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * 2.0
	m.radial_segments = 10
	m.rings = 5
	return m


func _prim(mesh: PrimitiveMesh, pos: Vector3, mat: String) -> void:
	mesh.material = _mats[mat]
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	add_child(mi)
