extends Node
## The water moving around whatever goes through it. A small picture (256 x 256, 64 m across) follows the
## player; each physics step a shader moves the wave equation on in it (shaders/ripple_step.gdshader), and the
## player, the vehicle being driven and anything else that calls push() press the surface down where they
## are. The water shaders read the picture (shaders/water_common.gdshaderinc) and bend, lighten and foam the
## surface by it. Cheap: one small picture drawn a step, no simulation of the water itself.
##
## The picture is drawn in two SubViewports in turn, each reading the other (a shader cannot read the picture
## it is drawing). It moves with the player in whole texels, so the ripples do not swim; in a river the pattern
## is carried downstream by the flow, which is kept in a second small picture.

const N := 256
const SIZE := 64.0
const TEXEL := SIZE / N

var enabled := true: set = set_enabled
var world
var _vps: Array = []
var _mats: Array = []
var _turn := 0
var _origin := Vector2.ZERO           # the world x, z of the picture's first corner, on whole texels
var _queued: Array = []               # pushes waiting for the next step: [place, radius, strength, foam]
var _flow_img: Image
var _flow_tex: ImageTexture
var _flow_at := Vector2(1e9, 1e9)
var _flowing := false


func setup(w) -> void:
	world = w
	var shader: Shader = load("res://shaders/ripple_step.gdshader")
	_flow_img = Image.create(64, 64, false, Image.FORMAT_RG8)
	_flow_img.fill(Color(0.5, 0.5, 0.0))
	_flow_tex = ImageTexture.create_from_image(_flow_img)
	for i in 2:
		var vp := SubViewport.new()
		vp.size = Vector2i(N, N)
		vp.disable_3d = true
		vp.use_hdr_2d = true                       # heights as real numbers where the renderer can (finer ripples)
		vp.transparent_bg = false
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
		vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		add_child(vp)
		var rect := ColorRect.new()
		rect.size = Vector2(N, N)
		rect.color = Color(0.5, 0.5, 0.0)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("flow_tex", _flow_tex)
		mat.set_shader_parameter("texel", 1.0 / N)
		rect.material = mat
		vp.add_child(rect)
		_vps.append(vp)
		_mats.append(mat)
	for i in 2:
		_mats[i].set_shader_parameter("prev", _vps[1 - i].get_texture())
	RenderingServer.global_shader_parameter_set("ripple_size", SIZE)
	RenderingServer.global_shader_parameter_set("ripple_on", 1.0)
	RenderingServer.global_shader_parameter_set("ripple_tex", _vps[0].get_texture().get_rid())


func set_enabled(on: bool) -> void:
	enabled = on
	RenderingServer.global_shader_parameter_set("ripple_on", 1.0 if on else 0.0)


## Something presses the water down at a place (world x, z): `radius` metres wide, `strength` metres deep a
## step (a walker wading is about 0.004, a car at speed 0.03), and `foam` from 0 to 1 left on the surface.
func push(place: Vector2, radius: float, strength: float, foam := 0.0) -> void:
	if enabled and _queued.size() < 12:
		_queued.append([place, radius, strength, foam])


## One step, with the area centred on a place (the player). Called once a physics step.
func step(centre: Vector3, delta: float) -> void:
	if not enabled or _vps.is_empty():
		return
	var want := Vector2(snappedf(centre.x - SIZE * 0.5, TEXEL), snappedf(centre.z - SIZE * 0.5, TEXEL))
	var moved := (want - _origin) / SIZE
	if absf(moved.x) > 1.0 or absf(moved.y) > 1.0:
		moved = Vector2(4.0, 4.0)                      # a jump (a teleport): everything is outside, the water starts still
	_origin = want
	_update_flow(centre)
	_turn = 1 - _turn
	var mat: ShaderMaterial = _mats[_turn]
	mat.set_shader_parameter("shift", moved)
	mat.set_shader_parameter("carry", delta / SIZE if _flowing else 0.0)
	var arr := PackedVector4Array()
	var foam := PackedFloat32Array()
	for q in _queued:
		var uv: Vector2 = (q[0] - _origin) / SIZE
		arr.append(Vector4(uv.x, uv.y, q[1] / SIZE, q[2]))
		foam.append(q[3])
	var n := arr.size()
	arr.resize(12)
	foam.resize(12)
	mat.set_shader_parameter("push", arr)
	mat.set_shader_parameter("push_foam", foam)
	mat.set_shader_parameter("pushes", n)
	_queued.clear()
	_vps[_turn].render_target_update_mode = SubViewport.UPDATE_ONCE
	RenderingServer.global_shader_parameter_set("ripple_origin", _origin)
	RenderingServer.global_shader_parameter_set("ripple_tex", _vps[_turn].get_texture().get_rid())


## The flow of the water under the rippled area, as a picture the step shader reads. Looked up again when the
## player has moved a few metres; all still unless there is running water near.
func _update_flow(centre: Vector3) -> void:
	var here := Vector2(centre.x, centre.z)
	if here.distance_to(_flow_at) < 6.0:
		return
	_flow_at = here
	var any := false
	for iz in 64:
		for ix in 64:
			var w: Dictionary = world.water_at(_origin.x + (ix + 0.5) * SIZE / 64.0, _origin.y + (iz + 0.5) * SIZE / 64.0)
			var f: Vector2 = w.get("flow", Vector2.ZERO)
			if f.length_squared() > 0.01:
				any = true
			_flow_img.set_pixel(ix, iz, Color(clampf(0.5 + f.x / 16.0, 0.0, 1.0), clampf(0.5 + f.y / 16.0, 0.0, 1.0), 0.0))
	if any or _flowing:
		_flow_tex.update(_flow_img)
	_flowing = any
