extends RefCounted
## The player's own model: a character with a skeleton and animations, made outside the game (models/player.glb,
## brought in by tools/player_model.py; a Mixamo skeleton, as Meshy rigs it), shown in place of the figure that
## scripts/body.gd builds. The figure's joints are still there and still moved by scripts/player.gd; they are
## only not drawn. This lays the model's bones after them, so every movement the game knows carries over
## (swimming, jumping, sitting on the ATV, the bike, reaching for handlebars), and when he simply walks or runs
## on the ground the model's own Walking and Running animations are played instead, in step with the ground
## covered. Between the two it changes over smoothly.

const TALL := 1.84
## bone of the skeleton -> the figure's joints whose turns, one after another from the body out, make up its own
const MAP := {
	"Spine": ["torso"], "Head": ["torso", "head"],
	"LeftArm": ["arm_l"], "LeftForeArm": ["arm_l", "elbow_l"], "RightArm": ["arm_r"], "RightForeArm": ["arm_r", "elbow_r"],
	"LeftUpLeg": ["leg_l"], "LeftLeg": ["leg_l", "knee_l"], "LeftFoot": ["leg_l", "knee_l", "ankle_l"],
	"RightUpLeg": ["leg_r"], "RightLeg": ["leg_r", "knee_r"], "RightFoot": ["leg_r", "knee_r", "ankle_r"],
}

var root: Node3D
var skel: Skeleton3D
var triangles := 0
var _joints := {}
var _order: Array = []                 # the bones, a parent always before its children
var _parent: Array = []
var _rest: Array = []                  # each bone at rest, in its parent
var _rest_q: Array = []
var _rest_g: Array = []                # and its turn at rest in the skeleton as a whole
var _mapped := {}                      # bone -> the joints it follows
var _hips := -1
var _unit := 1.0                       # how many of the skeleton's own units make a metre
var _clips := {}                       # "walk", "run": {anim, len, t0, rot: {bone: track}, pos: {bone: track}}
var _w := 0.0                          # 0: laid after the figure's joints, 1: the model's own animation
var _turn := Basis(Vector3.UP, PI)     # the model faces +Z, the game's figures -Z


static func _short(bone: String) -> String:
	return bone.replace("mixamorig:", "").replace("mixamorig_", "")


## Load the model and hang it on the figure. False if there is no model, or it has no skeleton: the built figure stays.
func setup(figure: Node3D, joints: Dictionary, path: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return false
	var scene: Node = doc.generate_scene(state)
	if scene == null:
		return false
	var found := scene.find_children("*", "Skeleton3D", true, false)
	if found.is_empty():
		scene.free()
		return false
	skel = found[0]
	_joints = joints
	var height := 1.70
	for mi in scene.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = (mi as MeshInstance3D).mesh
		if mesh != null:
			height = maxf(mesh.get_aabb().size.y, 0.5)
			for s in mesh.get_surface_count():
				triangles += mesh.surface_get_array_index_len(s) / 3
	root = Node3D.new()
	root.name = "Model"
	root.basis = _turn.scaled(Vector3.ONE * (TALL / height))
	figure.add_child(root)
	root.add_child(scene)
	var s := 1.0
	var n: Node = skel
	while n != figure and n is Node3D:
		s *= (n as Node3D).scale.y
		n = n.get_parent()
	_unit = 1.0 / s
	# the bones: parents first, each one's rest
	var count := skel.get_bone_count()
	_parent.resize(count)
	_rest.resize(count)
	_rest_q.resize(count)
	_rest_g.resize(count)
	var depth := []
	for b in count:
		_parent[b] = skel.get_bone_parent(b)
		_rest[b] = skel.get_bone_rest(b)
		_rest_q[b] = (_rest[b] as Transform3D).basis.get_rotation_quaternion()
		_rest_g[b] = skel.get_bone_global_rest(b).basis.orthonormalized()
		var d := 0
		var p: int = _parent[b]
		while p >= 0:
			d += 1
			p = skel.get_bone_parent(p)
		depth.append([d, b])
		var short := _short(skel.get_bone_name(b))
		if MAP.has(short):
			_mapped[b] = MAP[short]
		if short == "Hips":
			_hips = b
	depth.sort_custom(func(x, y): return x[0] < y[0] or (x[0] == y[0] and x[1] < y[1]))
	for q in depth:
		_order.append(q[1])
	# its animations: which track turns and which moves which bone; the player that came with them is not used
	for ap in scene.find_children("*", "AnimationPlayer", true, false):
		for an in (ap as AnimationPlayer).get_animation_list():
			var key := "walk" if String(an).to_lower().contains("walk") else ("run" if String(an).to_lower().contains("run") else "")
			if key == "" or _clips.has(key):
				continue
			var anim: Animation = (ap as AnimationPlayer).get_animation(an)
			anim.loop_mode = Animation.LOOP_LINEAR
			var clip := {"anim": anim, "len": maxf(anim.length, 0.05), "t0": 0.0, "rot": {}, "pos": {}}
			for t in anim.get_track_count():
				var bone := skel.find_bone(anim.track_get_path(t).get_concatenated_subnames())
				if bone < 0:
					continue
				if anim.track_get_type(t) == Animation.TYPE_ROTATION_3D:
					clip["rot"][bone] = t
				elif anim.track_get_type(t) == Animation.TYPE_POSITION_3D and bone == _hips:
					clip["pos"][bone] = t
			_clips[key] = clip
		(ap as AnimationPlayer).active = false
	# where in each animation the left heel comes down (the left foot farthest forward): the game's stride starts there
	var foot := -1
	for b in count:
		if _short(skel.get_bone_name(b)) == "LeftFoot":
			foot = b
	for key in _clips:
		var clip: Dictionary = _clips[key]
		var best := -INF
		for k in 48:
			var t := float(clip["len"]) * float(k) / 48.0
			var at := Transform3D()
			var chain := []
			var b2 := foot
			while b2 >= 0:
				chain.push_front(b2)
				b2 = _parent[b2]
			for b3 in chain:
				var loc: Transform3D = _rest[b3]
				if clip["rot"].has(b3):
					loc.basis = Basis((clip["anim"] as Animation).rotation_track_interpolate(clip["rot"][b3], t))
				at = at * loc
			if foot >= 0 and at.origin.z > best:
				best = at.origin.z
				clip["t0"] = t
	return true


## Lay the bones for this frame. `own` says whether he is simply walking or running on the ground (then the model's
## animations are used): `gait` where in the stride (0 to 1), `run` from 0 a walk to 1 a sprint, `amount` from 0
## standing to 1 moving.
func update(delta: float, own: bool, gait: float, run: float, amount: float) -> void:
	if skel == null:
		return
	if _clips.is_empty():
		own = false
	_w = move_toward(_w, 1.0 if own else 0.0, delta * 5.0)
	var count := _order.size()
	var glob := []
	glob.resize(skel.get_bone_count())
	var torso: Node3D = _joints["torso"]
	var lift := (torso.position.y - 0.95) * _unit
	var walk: Dictionary = _clips.get("walk", _clips.get("run", {}))
	var runc: Dictionary = _clips.get("run", walk)
	var tw := 0.0
	var tr := 0.0
	if _w > 0.001:
		tw = fposmod(float(walk["t0"]) + gait * float(walk["len"]), float(walk["len"]))
		tr = fposmod(float(runc["t0"]) + gait * float(runc["len"]), float(runc["len"]))
	for k in count:
		var b: int = _order[k]
		var p: int = _parent[b]
		var gp: Basis = glob[p] if p >= 0 else Basis()
		# after the figure's joints
		var q: Quaternion = _rest_q[b]
		if _mapped.has(b):
			var turn := Basis()
			for name in _mapped[b]:
				turn = turn * (_joints[name] as Node3D).basis.orthonormalized()
			q = (gp.inverse() * (_turn.inverse() * turn * _turn) * (_rest_g[b] as Basis)).get_rotation_quaternion()
		var pos: Vector3 = (_rest[b] as Transform3D).origin
		if b == _hips:
			pos.y += lift
		# the model's own stride
		if _w > 0.001:
			var qc: Quaternion = _rest_q[b]
			if walk["rot"].has(b):
				qc = (walk["anim"] as Animation).rotation_track_interpolate(walk["rot"][b], tw)
				if runc["rot"].has(b) and run > 0.001:
					qc = qc.slerp((runc["anim"] as Animation).rotation_track_interpolate(runc["rot"][b], tr), run)
				qc = (_rest_q[b] as Quaternion).slerp(qc, amount)
			q = q.slerp(qc, _w)
			if b == _hips and walk["pos"].has(b):
				var pc: Vector3 = (walk["anim"] as Animation).position_track_interpolate(walk["pos"][b], tw)
				if runc["pos"].has(b) and run > 0.001:
					pc = pc.lerp((runc["anim"] as Animation).position_track_interpolate(runc["pos"][b], tr), run)
				var rest_at: Vector3 = (_rest[b] as Transform3D).origin
				pc = Vector3(rest_at.x, lerpf(rest_at.y, pc.y, amount), rest_at.z)       # (up and down only: he stays over his feet)
				pos = pos.lerp(pc, _w)
		skel.set_bone_pose_rotation(b, q)
		if b == _hips:
			skel.set_bone_pose_position(b, pos)
		glob[b] = gp * Basis(q)
