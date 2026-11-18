extends Node3D
## Grass and small plants close to the player. The ground is cut into patches of 8 m; the patches within about
## 60 m are filled with tufts wherever the ground is grass (not paving, a path, bare rock or water), drawn as one
## MultiMesh a patch, and dropped again when the player has moved on. What grows where follows the map's ground
## cover (world.cover_at): mown lawn is short and green, fields are taller and yellower, open ground is rough
## grass with heather on the hills, under trees there are ferns and bushes, and reeds stand by the water.
## Tufts bend with the wind (shaders/grass.gdshader). The menu's "Grass" setting says how much is drawn.

const PATCH := 8.0                       # (small patches: filling one is a short job, so no frame waits long for it)
const REACH := 8                         # patches each way; only those within that distance, a circle, are filled

var world
var player
var amount := 2: set = set_amount       # 0 none, 1 some, 2 full
var tufts := 0                           # how many are drawn now (for the checks)

var _patches := {}
var _queue: Array = []
var _at := Vector2i(-99999, -99999)
var _mesh: ArrayMesh
var _mat: ShaderMaterial


func setup(w, p) -> void:
	world = w
	player = p
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/grass.gdshader")
	_mat.set_shader_parameter("far", PATCH * REACH - 4.0)
	_mesh = _tuft()


func set_amount(a: int) -> void:
	if a != amount:
		amount = a
		for key in _patches.keys():
			if _patches[key] != null:
				_patches[key].queue_free()
		_patches.clear()
		_at = Vector2i(-99999, -99999)
		tufts = 0


## One tuft: five blades fanning out from a hand's width of ground, each blade ONE triangle (two corners at the
## foot, one at the tip). A tuft was 36 triangles when its blades were built in two bending pieces; drawn a
## hundred thousand times that cost more than everything else in the picture, and at grass size the bend in the
## blade itself cannot be seen. The wind still bends it: the shader moves the tip.
func _tuft() -> ArrayMesh:
	var v := PackedVector3Array()
	var uv := PackedVector2Array()
	var n := PackedVector3Array()
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for b in 5:
		var a := b * TAU / 5.0 * 2.0 + rng.randf_range(-0.4, 0.4)
		var out := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-out.z, 0, out.x)
		var lean := rng.randf_range(0.08, 0.26)
		var tall := rng.randf_range(0.7, 1.0)
		var foot := out * rng.randf_range(0.02, 0.24)
		for q in [[foot - side * 0.045, 0.0], [foot + side * 0.045, 0.0], [foot + out * lean + Vector3(0, tall, 0), 1.0]]:
			v.append(q[0])
			uv.append(Vector2(0.5, q[1]))
			n.append(Vector3.UP)
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = v
	arrays[Mesh.ARRAY_TEX_UV] = uv
	arrays[Mesh.ARRAY_NORMAL] = n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh.surface_set_material(0, _mat)
	return mesh


func _process(_delta: float) -> void:
	if world == null or amount == 0:
		return
	var pos: Vector3 = player.global_position
	var c := Vector2i(int(floor(pos.x / PATCH)), int(floor(pos.z / PATCH)))
	if c != _at:
		_at = c
		for key in _patches.keys():
			if (key.x - c.x) * (key.x - c.x) + (key.y - c.y) * (key.y - c.y) > (REACH + 1.5) * (REACH + 1.5):
				if _patches[key] != null:
					tufts -= _patches[key].multimesh.instance_count
					_patches[key].queue_free()
				_patches.erase(key)
		_queue.clear()
		for dz in range(-REACH, REACH + 1):
			for dx in range(-REACH, REACH + 1):
				var key := Vector2i(c.x + dx, c.y + dz)
				if dx * dx + dz * dz <= (REACH + 0.5) * (REACH + 0.5) and not _patches.has(key):
					_queue.append([dx * dx + dz * dz, key])
		_queue.sort_custom(func(a, b): return a[0] < b[0])
	var t0 := Time.get_ticks_usec()
	while not _queue.is_empty() and Time.get_ticks_usec() - t0 < 1500:
		var key: Vector2i = _queue.pop_front()[1]
		if not _patches.has(key):
			_patches[key] = _grow(key)


## Fill one patch. Returns its MultiMeshInstance3D, or null where nothing grows.
func _grow(key: Vector2i) -> MultiMeshInstance3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(key)
	var step := 0.36 if amount == 2 else 0.8                 # (the forest floor stays thin: see below)
	var x_at := key.x * PATCH
	var z_at := key.y * PATCH
	var xf: Array = []
	var cols := PackedColorArray()
	var x := x_at + step * 0.5
	while x < x_at + PATCH:
		var z := z_at + step * 0.5
		while z < z_at + PATCH:
			var px := x + rng.randf_range(-0.3, 0.3) * step
			var pz := z + rng.randf_range(-0.3, 0.3) * step
			z += step
			var c: Dictionary = world.cover_at(px, pz)
			if c["road"] > 0.2 or c["path"] > 0.25 or c["rock"] > 0.45:
				continue
			var y: float = world.height_at(px, pz)
			if y < 0.75 or not is_nan(world.detail.surface_at(px, pz)):
				continue
			if absf(world.height_at(px + 0.8, pz) - y) > 0.55 or absf(world.height_at(px, pz + 0.8) - y) > 0.55:
				continue                                            # a bank or a cut: bare
			var w: Dictionary = world.water_at(px, pz)
			var by_water := false
			if not w.is_empty():
				if w["depth"] > 0.35:
					continue
				by_water = true
			# what grows here
			var tall := 0.34
			var wide := 1.0
			var col := Color(0.30, 0.36, 0.16)
			var r := rng.randf()
			if by_water or (r < 0.25 and not world.water_at(px + 1.5, pz + 1.0).is_empty()):
				tall = rng.randf_range(0.9, 1.5)                # reeds
				wide = 0.7
				col = Color(0.42, 0.44, 0.22)
			elif c["mown"] > 0.5:
				tall = rng.randf_range(0.13, 0.22)              # a lawn
				wide = 0.6
				col = Color(0.25, 0.40, 0.15).lerp(Color(0.30, 0.44, 0.17), rng.randf())
			elif c["field"] > 0.5:
				tall = rng.randf_range(0.35, 0.6)
				col = Color(0.50, 0.47, 0.22).lerp(Color(0.36, 0.42, 0.18), rng.randf())
			elif c["bog"] > 0.5:
				tall = rng.randf_range(0.3, 0.5)
				col = Color(0.42, 0.36, 0.18)
			elif c["trees"] > 0.45:
				if r > 0.35:
					continue                                    # the forest floor is mostly bare
				tall = rng.randf_range(0.35, 0.7)               # ferns and small bushes
				wide = 1.9
				col = Color(0.16, 0.30, 0.13)
			else:
				tall = rng.randf_range(0.22, 0.42)              # rough grass; heather on the hills
				col = Color(0.33, 0.36, 0.17).lerp(Color(0.42, 0.40, 0.20), rng.randf())
				if y > 120.0 and r < 0.4:
					tall = rng.randf_range(0.18, 0.3)
					wide = 1.6
					col = Color(0.40, 0.24, 0.36).lerp(Color(0.30, 0.26, 0.20), rng.randf())
			var b := Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(wide, tall, wide))
			xf.append(Transform3D(b, Vector3(px - x_at - PATCH * 0.5, y - 0.02, pz - z_at - PATCH * 0.5)))
			cols.append(col)
		x += step
	if xf.is_empty():
		return null
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _mesh
	mm.instance_count = xf.size()
	var y0 := 1e9
	var y1 := -1e9
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
		mm.set_instance_color(i, cols[i])
		y0 = minf(y0, xf[i].origin.y)
		y1 = maxf(y1, xf[i].origin.y)
	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.position = Vector3(x_at + PATCH * 0.5, 0, z_at + PATCH * 0.5)
	mi.custom_aabb = AABB(Vector3(-PATCH * 0.5 - 1.0, y0 - 1.0, -PATCH * 0.5 - 1.0), Vector3(PATCH + 2.0, y1 - y0 + 3.5, PATCH + 2.0))
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mi)
	tufts += xf.size()
	return mi
