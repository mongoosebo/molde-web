extends RefCounted
## What takes seconds to work out at the start and comes out the same every time is kept on disk between runs
## (user://cache/): the traffic's car models with their coarser levels, and the height of the ground under every
## bench, lamp and parked car. Each file's name carries a stamp made from the dates of every script and shader
## and of the map's files, so anything changed makes new ones (the old are removed). Not in a browser, which has
## no disk of its own worth the name; MOLDE_NO_CACHE=1 in the environment turns it off.
const DIR := "user://cache/"
static var _stamp := ""


static func on() -> bool:
	return not OS.has_feature("web") and OS.get_environment("MOLDE_NO_CACHE") == ""


static func stamp() -> String:
	if _stamp == "":
		var parts := PackedStringArray([OS.get_executable_path(), str(FileAccess.get_modified_time(OS.get_executable_path())), Engine.get_version_info()["string"]])
		for dir in ["res://scripts/", "res://shaders/", "res://world/"]:
			for f in DirAccess.get_files_at(dir):
				parts.append(f + str(FileAccess.get_modified_time(dir + f)))
		_stamp = "%x" % hash("|".join(parts))
		DirAccess.make_dir_recursive_absolute(DIR)
		for f in DirAccess.get_files_at(DIR):
			if not f.contains("_" + _stamp + "."):
				DirAccess.remove_absolute(DIR + f)
	return _stamp


static func _path(name: String, ext: String) -> String:
	return DIR + name + "_" + stamp() + "." + ext


## A Resource kept under a name, or null.
static func resource(name: String) -> Resource:
	if not on() or not FileAccess.file_exists(_path(name, "res")):
		return null
	return ResourceLoader.load(_path(name, "res"), "", ResourceLoader.CACHE_MODE_IGNORE)


static func keep_resource(name: String, res: Resource) -> void:
	if on():
		ResourceSaver.save(res, _path(name, "res"), ResourceSaver.FLAG_COMPRESS)


## A list of numbers kept under a name, or an empty one.
static func floats(name: String) -> PackedFloat32Array:
	if not on() or not FileAccess.file_exists(_path(name, "f32")):
		return PackedFloat32Array()
	return FileAccess.get_file_as_bytes(_path(name, "f32")).to_float32_array()


static func keep_floats(name: String, values: PackedFloat32Array) -> void:
	if on():
		var f := FileAccess.open(_path(name, "f32"), FileAccess.WRITE)
		if f != null:
			f.store_buffer(values.to_byte_array())
			f.close()
