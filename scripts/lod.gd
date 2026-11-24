extends RefCounted
## Fewer triangles for what is small on the screen. The models built in code (cars, lorries, wheels) had every
## triangle drawn however far off they stood: a traffic car is 32 000 of them. `levels()` works out coarser
## versions of a mesh once (the same simplifier Godot runs on imported models); `mesh_of()` gives the mesh with
## those in it, which the renderer then picks from by the mesh's size on the screen; `surfaces_at()` gives one
## fixed coarser version, for things drawn many at a time (a MultiMesh has one size for all its copies, so it
## cannot pick) and for shadows.

## The mesh's surfaces with their coarser levels worked out. Materials are kept.
static func levels(mesh: Mesh) -> ImporterMesh:
	var im := ImporterMesh.new()
	for sf in mesh.get_surface_count():
		var st := SurfaceTool.new()
		st.create_from(mesh, sf)
		st.index()
		im.add_surface(Mesh.PRIMITIVE_TRIANGLES, st.commit_to_arrays(), [], {}, mesh.surface_get_material(sf))
	im.generate_lods(25.0, 60.0, [])
	return im


static func mesh_of(im: ImporterMesh) -> ArrayMesh:
	return im.get_mesh()


## Each surface at the coarsest level that still has `share` of its triangles: [[arrays, material], ...].
static func surfaces_at(im: ImporterMesh, share: float) -> Array:
	var out := []
	for sf in im.get_surface_count():
		var arrays := im.get_surface_arrays(sf)
		var best: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var full := best.size()
		for l in im.get_surface_lod_count(sf):
			var idx := im.get_surface_lod_indices(sf, l)
			if float(idx.size()) < float(full) * share or idx.is_empty():
				break
			best = idx
		arrays[Mesh.ARRAY_INDEX] = best
		out.append([arrays, im.get_surface_material(sf)])
	return out


## Many surfaces as one: a bag to pour them into (`add`), and the mesh of it (`arrays`). Each keeps its own
## colour, roughness, metal and glow, carried in the texture coordinates for shaders/car_far.gdshader (the
## colour channel cannot be used: in a MultiMesh it is multiplied by the colour of each copy).
class Bag:
	var v := PackedVector3Array()
	var n := PackedVector3Array()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	func add(arrays: Array, mat: Material, xf := Transform3D.IDENTITY) -> void:
		var col := Color(0.5, 0.5, 0.5)
		var rough := 0.6
		var metal := 0.0
		var glow := 0.0
		if mat is BaseMaterial3D:
			col = (mat as BaseMaterial3D).albedo_color
			rough = (mat as BaseMaterial3D).roughness
			metal = (mat as BaseMaterial3D).metallic
			glow = 1.0 if (mat as BaseMaterial3D).emission_enabled else 0.0
		var av: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var an = arrays[Mesh.ARRAY_NORMAL]
		var ai = arrays[Mesh.ARRAY_INDEX]
		var first := v.size()
		var a := Vector2(col.r, col.g)
		var b := Vector2(col.b + 2.0 * glow, floorf(clampf(metal, 0.0, 0.95) * 10.0) + clampf(rough, 0.0, 1.0) * 0.99)
		for i in av.size():
			v.append(xf * av[i])
			n.append((xf.basis * (an[i] as Vector3)).normalized() if an != null else Vector3.UP)
			uv.append(a)
			uv2.append(b)
		if ai == null:
			for i in av.size():
				idx.append(first + i)
		else:
			for i in (ai as PackedInt32Array):
				idx.append(first + i)

	func arrays() -> Array:
		var out := []
		out.resize(Mesh.ARRAY_MAX)
		out[Mesh.ARRAY_VERTEX] = v
		out[Mesh.ARRAY_NORMAL] = n
		out[Mesh.ARRAY_TEX_UV] = uv
		out[Mesh.ARRAY_TEX_UV2] = uv2
		out[Mesh.ARRAY_INDEX] = idx
		return out
