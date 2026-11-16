extends Node
## In a browser: download the map into user://world/ before the world is built.
## The site has the map next to the page, in world/, with world/files.json listing every file with its size
## and a hash (made by tools/web_site.py). user:// is kept by the browser between visits, so a file is only
## downloaded again when its hash changes.

const DEST := "user://world/"
const STAMPS := "user://world/stamps.json"
const PARALLEL := 4
const TRIES := 3

var _hud
var _base := ""
var _queue: Array = []
var _active: Array = []        # jobs: {"req": HTTPRequest, "file": {...}}
var _stamps := {}              # file name -> hash of the copy in user://world/
var _total := 0                # bytes to download
var _done := 0                 # bytes of the files finished so far
var _failed := ""


func run(hud) -> bool:
	_hud = hud
	var href := str(JavaScriptBridge.eval("location.origin + location.pathname", true))
	_base = href.substr(0, href.rfind("/") + 1) + "world/"
	_hud.set_loading("Looking for the map")

	var req := HTTPRequest.new()
	add_child(req)
	var err := req.request(_base + "files.json?t=%d" % int(Time.get_unix_time_from_system()))
	var res: Array = [HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray()]
	if err == OK:
		res = await req.request_completed
	req.queue_free()
	if res[0] != HTTPRequest.RESULT_SUCCESS or res[1] != 200:
		_hud.set_loading("Could not reach the map (%d / %d).\nReload the page to try again." % [res[0], res[1]])
		return false
	var files = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	if not (files is Array):
		_hud.set_loading("The map list is broken.\nReload the page to try again.")
		return false

	DirAccess.make_dir_recursive_absolute(DEST)
	if FileAccess.file_exists(STAMPS):
		var s = JSON.parse_string(FileAccess.get_file_as_string(STAMPS))
		if s is Dictionary:
			_stamps = s
	for f in files:
		var path: String = DEST + str(f["name"])
		if _stamps.get(f["name"], "") == f["hash"] and _size_of(path) == int(f["size"]):
			continue                                   # kept from an earlier visit
		_stamps.erase(f["name"])
		f["tries"] = 0
		_queue.append(f)
		_total += int(f["size"])

	while not _queue.is_empty() or not _active.is_empty():
		while _active.size() < PARALLEL and not _queue.is_empty():
			_start(_queue.pop_front())
		_show()
		await get_tree().process_frame
		if _failed != "":
			for job in _active:
				job["req"].cancel_request()
			_hud.set_loading("Could not download %s.\nReload the page to try again." % _failed)
			return false
	_hud.set_loading("")
	return true


func _size_of(path: String) -> int:
	if not FileAccess.file_exists(path):
		return -1
	var f := FileAccess.open(path, FileAccess.READ)
	return -1 if f == null else int(f.get_length())


func _start(f: Dictionary) -> void:
	var path: String = DEST + str(f["name"])
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var req := HTTPRequest.new()
	req.download_file = path
	add_child(req)
	var job := {"req": req, "file": f}
	_active.append(job)
	req.request_completed.connect(_finished.bind(job))
	# the hash in the address keeps the browser from handing back an old copy after the map changes
	if req.request(_base + str(f["name"]).uri_encode().replace("%2F", "/") + "?" + str(f["hash"])) != OK:
		_finished.call_deferred(HTTPRequest.RESULT_CANT_CONNECT, 0, PackedStringArray(), PackedByteArray(), job)


func _finished(result: int, code: int, _headers: PackedStringArray, _body: PackedByteArray, job: Dictionary) -> void:
	if not _active.has(job):
		return
	_active.erase(job)
	job["req"].queue_free()
	var f: Dictionary = job["file"]
	var path: String = DEST + str(f["name"])
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and _size_of(path) == int(f["size"]):
		_done += int(f["size"])
		_stamps[f["name"]] = f["hash"]
		var out := FileAccess.open(STAMPS, FileAccess.WRITE)
		if out:
			out.store_string(JSON.stringify(_stamps))
	elif int(f["tries"]) + 1 < TRIES:
		f["tries"] = int(f["tries"]) + 1
		_queue.append(f)
	else:
		_failed = str(f["name"])


func _show() -> void:
	var got := _done
	for job in _active:
		got += maxi(0, job["req"].get_downloaded_bytes())
	_hud.set_loading("Downloading the map  %d / %d MB\n(only the first time)" % [got / 1048576, maxi(1, _total / 1048576)])
