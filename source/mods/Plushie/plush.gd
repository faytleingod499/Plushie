extends Spatial

# One plushie in the world: a frozen copy of a player's body, dressed in the outfit the player had when the
# plushie was made. It is built from the game's own player scene (the same skeleton, face and tail) and
# dressed with the game's own cosmetic code, so it looks exactly like them, just stuffed.
#
# The node's origin sits 1.0 x size above the feet, like a player's, so it can be treated like a player
# (the hug code reads its size and its skeleton the same way). "feet" is the spot on the ground under it.

const Poses = preload("res://mods/Plushie/poses.gd")

const PLAYER_SCENE = "res://Scenes/Entities/Player/player.tscn"
const COSMETIC_NODE = "res://Scenes/Entities/Player/cosmetic_node.tscn"
const SKINS = "res://Assets/Shaders/player_skins.tres"
const SKELETON_PATH = "body/player_body/Armature/Skeleton"
const BLEND_SPEED = 9.0        # how fast one pose eases into the next
const MIN_SIZE = 0.15
const MAX_SIZE = 2.5

var rec = {}                   # id, name, size, pose, outfit ...
var size = 0.45
var body = null
var skeleton = null
var face = null
var tail = null
var body_mesh = null
var species_mesh = null
var interact = null           # the Area that makes the game show "[E] HUG"

var pose_id = "sit"
var goal = []                  # Transform per bone, where the pose wants it
var cur = []                   # Transform per bone, where it is now
var goal_floor = 0.0           # lowest point of the body in the goal pose (model units, 0 = the soles)
var cur_floor = 0.0
var lift_extra = 0.0           # extra height while being carried
var hug_pose = null            # bone angles that win over the pose while held (arms around), null when not
var held = false               # being hugged: sits, whatever pose it was put in
var goal_globals = []
var clock = 0.0
var built = false
var feet = Vector3()
var yaw = 0.0


func _ready():
	set_process(true)


# builds the body and dresses it; call after the node is in the tree
func setup(record):
	rec = record
	size = clamp(float(rec.get("size", 0.45)), MIN_SIZE, MAX_SIZE)
	body = _fresh_body()
	if body == null:
		return false
	add_child(body)
	skeleton = body.get_node_or_null("player_body/Armature/Skeleton")
	if skeleton == null:
		return false
	face = skeleton.get_node_or_null("face/player_face")
	tail = skeleton.get_node_or_null("tail/holder/tail")
	body_mesh = skeleton.get_node_or_null("body_main")
	# a plushie isn't animated: it only holds the pose it is put in
	var tree = body.get_node_or_null("AnimationTree")
	if tree != null:
		tree.active = false
		tree.queue_free()
	var ap = body.get_node_or_null("player_body/AnimationPlayer")
	if ap != null:
		ap.stop()
		ap.queue_free()
	for name in ["head_alert", "tool_placeholder", "head_cat", "head_dog"]:
		var n = skeleton.get_node_or_null(name)
		if n != null:
			n.visible = false
	var hand = skeleton.get_node_or_null("BoneAttachment")
	if hand != null:
		hand.visible = false
	_dress(rec.get("outfit", {}))
	_repair_skins()
	_make_area()
	scale = Vector3.ONE * size
	var n = skeleton.get_bone_count()
	cur = []
	for i in range(n):
		cur.append(Transform())
	set_pose(rec.get("pose", "sit"), true)
	built = true
	_freeze_tail()
	return true


# the spot the game's interact key finds: walking up shows "[E] <text>" and E calls the mod
func _make_area():
	var script = load("res://mods/Plushie/plush_area.gd")
	if script == null:
		return
	interact = Area.new()
	interact.set_script(script)
	var shape = CollisionShape.new()
	var sphere = SphereShape.new()
	sphere.radius = 0.8
	shape.shape = sphere
	shape.translation = Vector3(0, 0.1, 0)
	interact.add_child(shape)
	add_child(interact)


func _fresh_body():
	var scene = load(PLAYER_SCENE)
	if scene == null:
		return null
	var p = scene.instance()
	var b = p.get_node_or_null("body")
	if b == null:
		p.free()
		return null
	p.remove_child(b)
	p.free()
	return b


func _root():
	return Engine.get_main_loop().root


func _dress(outfit):
	var globals = _root().get_node_or_null("Globals")
	var data = sanitize(outfit)
	if globals == null or data.empty():
		return
	var cd = globals.cosmetic_data
	if face != null:
		face.call("_setup_face", data)
	var species_id = cd[data["species"]]["file"].cos_internal_id
	species_mesh = _cosmetic(data["species"], species_id)
	_cosmetic(data["undershirt"], species_id)
	_cosmetic(data["overshirt"], species_id)
	_cosmetic(data["legs"], species_id)
	_cosmetic(data["hat"], species_id)
	for misc in data["accessory"]:
		_cosmetic(misc, species_id)

	var pattern = cd[data["pattern"]]["file"]
	var primary = cd[data["primary_color"]]["file"]
	var secondary = cd[data["secondary_color"]]["file"] if pattern.body_pattern[0] else primary
	if body_mesh != null and body_mesh.material_override != null:
		var mat = body_mesh.material_override.duplicate()
		body_mesh.material_override = mat
		mat.set_shader_param("texture_albedo", pattern.body_pattern[0])
		mat.set_shader_param("albedo", primary.main_color)
		mat.set_shader_param("albedo_secondary", secondary.main_color)
	if tail != null:
		tail._load_tail(cd[data["tail"]]["file"].mesh, primary.main_color)

	if species_mesh != null and not ["species_cat", "species_dog"].has(data["species"]):
		# a species added by a mod: the game's own code only colours cat and dog, the mod colours its own,
		# and that code isn't running here, so tint its body with the colours the same way
		_tint_modded(species_mesh, primary.main_color, secondary.main_color, pattern, species_id)
	elif species_mesh != null and species_mesh is MeshInstance:
		species_mesh.material_override = null
		var which = -1
		match data["species"]:
			"species_cat":
				which = 1
			"species_dog":
				which = 2
		if which > 0:
			var skin_mat = load(SKINS).duplicate()
			species_mesh.set_surface_material(0, skin_mat)
			skin_mat.set_shader_param("albedo", primary.main_color)
			skin_mat.set_shader_param("albedo_secondary", secondary.main_color)
			skin_mat.set_shader_param("texture_albedo", pattern.body_pattern[which])


# Colours the first surface of every mesh in a modded species with the skin shader (or its own material's
# colour), so the plushie isn't left in whatever plain material the model came with.
func _tint_modded(node, primary, secondary, pattern, species_id):
	var meshes = []
	_collect_meshes(node, meshes)
	print("[Plushie] modded species: ", node.name, " meshes=", meshes.size())
	for mi in meshes:
		if mi.mesh == null or mi.mesh.get_surface_count() == 0:
			continue
		var old = mi.get_surface_material(0)
		if old == null:
			old = mi.material_override
		if old == null:
			old = mi.mesh.surface_get_material(0)
		print("[Plushie]   ", mi.name, " surface0 material: ", old.get_class() if old != null else "none", " ", old.shader.resource_path if old is ShaderMaterial and old.shader != null else "")
		var tex = null
		if pattern != null and pattern.body_pattern.size() > 1:
			var bp = pattern.body_pattern
			var pick = species_id if (species_id > 0 and species_id < bp.size()) else (2 if bp.size() > 2 else bp.size() - 1)
			tex = bp[pick]
			var have = []
			for t in bp:
				have.append(t != null)
			print("[Plushie]   pattern slots=", bp.size(), " filled=", have, " species cos_internal_id=", species_id, " using slot ", pick)
		# without a pattern picture the shader would paint everything with the second colour
		var second = secondary if tex != null else primary
		if old is SpatialMaterial:
			var m = old.duplicate()
			m.albedo_color = primary
			mi.material_override = null
			mi.set_surface_material(0, m)
		elif old is ShaderMaterial and old.shader != null and old.shader.code.find("albedo") >= 0:
			# its own skin shader: keep it (and its markings), just give it the colours
			var m2 = old.duplicate()
			m2.set_shader_param("albedo", primary)
			if old.shader.code.find("albedo_secondary") >= 0:
				m2.set_shader_param("albedo_secondary", second)
			if tex != null and old.shader.code.find("texture_albedo") >= 0:
				m2.set_shader_param("texture_albedo", tex)
			mi.material_override = null
			mi.set_surface_material(0, m2)
		else:
			var skin_mat = load(SKINS).duplicate()
			skin_mat.set_shader_param("albedo", primary)
			skin_mat.set_shader_param("albedo_secondary", second)
			skin_mat.set_shader_param("texture_albedo", tex)
			mi.material_override = null
			mi.set_surface_material(0, skin_mat)


func _collect_meshes(node, out):
	if node is MeshInstance:
		out.append(node)
	for c in node.get_children():
		_collect_meshes(c, out)


# the game's own way of putting one cosmetic on a player (player.gd _create_cosmetic)
func _cosmetic(id, species_id = 0):
	if id == "":
		return null
	var globals = _root().get_node_or_null("Globals")
	if globals == null or not globals.cosmetic_data.has(id):
		return null
	var data = globals.cosmetic_data[id]["file"]
	if data.scene_replace:
		var attach = BoneAttachment.new()
		skeleton.add_child(attach)
		attach.bone_name = "pelvis"
		attach.add_to_group("cosmetic")
		var inst = data.scene_replace.instance()
		attach.add_child(inst)
		return inst
	var cosm = load(COSMETIC_NODE).instance()
	cosm.mesh = data.mesh
	if data.species_alt_mesh.size() > species_id and data.species_alt_mesh.size() > 0:
		cosm.mesh = data.species_alt_mesh[species_id]
	cosm.skin = data.mesh_skin
	if not data.material:
		cosm.material_override = load(SKINS).duplicate()
		cosm.material_override.set_shader_param("albedo", data.main_color)
		cosm.material_override.set_shader_param("albedo_secondary", data.main_color)
		cosm.material_override.set_shader_param("texture_albedo", null)
	else:
		cosm.material_override = null
		cosm.set_surface_material(0, data.material)
		if data.secondary_material:
			cosm.set_surface_material(1, data.secondary_material)
	skeleton.add_child(cosm)
	cosm.skeleton = cosm.get_path_to(skeleton)
	cosm.add_to_group("cosmetic")
	return cosm


# an outfit with only things that exist in this game, missing parts filled from the game's default
static func sanitize(outfit):
	var root = Engine.get_main_loop().root
	var globals = root.get_node_or_null("Globals")
	var pdata = root.get_node_or_null("PlayerData")
	if globals == null or pdata == null:
		return {}
	var fallback = pdata.FALLBACK_COSM
	var out = {}
	if typeof(outfit) != TYPE_DICTIONARY:
		outfit = {}
	for key in fallback.keys():
		if key == "title" or key == "bobber":
			continue
		if key == "accessory":
			var list = []
			var src = outfit.get("accessory", [])
			if typeof(src) == TYPE_ARRAY:
				for a in src:
					if typeof(a) == TYPE_STRING and globals._cosmetic_exists(a) and list.size() < 8:
						list.append(a)
			out["accessory"] = list
			continue
		var v = outfit.get(key, fallback[key])
		if typeof(v) != TYPE_STRING or not globals._cosmetic_exists(v):
			v = fallback[key]
		out[key] = v
	return out


# A skin that names a bone the skeleton doesn't have (an import that dropped the dots from "arm.l") would
# leave that part of the body unmoving. Every named bind that doesn't match is pointed at the bone with the
# same name minus its dots. In the real game nothing needs changing.
func _repair_skins():
	var plain = {}
	for i in range(skeleton.get_bone_count()):
		plain[skeleton.get_bone_name(i).replace(".", "")] = i
	for node in skeleton.get_children():
		if not (node is MeshInstance) or node.skin == null:
			continue
		var skin = node.skin
		for b in range(skin.get_bind_count()):
			var nm = skin.get_bind_name(b)
			if nm != "" and skeleton.find_bone(nm) < 0 and plain.has(nm):
				skin.set_bind_bone(b, plain[nm])


# the tail only hangs: the game's script that swings it is switched off and it follows its bone
func _freeze_tail():
	if tail == null:
		return
	tail.set_physics_process(false)
	var rot = tail.get_node_or_null("rot_point")
	if rot != null:
		rot.rotation_degrees = Vector3(140, 0, -6)
	_follow_tail()


func _follow_tail():
	if tail == null:
		return
	var rot = tail.get_node_or_null("rot_point")
	var swish = tail.get_node_or_null("rot_point/swish_point")
	if rot != null and swish != null and rot.is_inside_tree():
		swish.global_transform = rot.global_transform


# --- poses ---

# Works out where every bone goes for a pose (turning each about its own joint, children following)
# and how high the lowest point of the body is. Returns {"pose": [Transform per bone], "floor": float}.
func solve(id, hold = null):
	var n = skeleton.get_bone_count()
	var def = Poses.POSES.get(id, Poses.POSES["sit"])
	var locals = []
	var globals = []
	for i in range(n):
		var rest = skeleton.get_bone_rest(i)
		var par = skeleton.get_bone_parent(i)
		var par_g = Transform() if par < 0 else globals[par]
		var base = par_g * rest
		var name = skeleton.get_bone_name(i)
		var a = Poses.angles(id, name)
		if hold != null and hold.has(name):
			a = hold[name]
		var d = Basis()
		if typeof(a) == TYPE_VECTOR3:
			# aim: turn the bone so it points that way (it keeps its twist as far as it can)
			var child = _axis_child(i)
			if child >= 0 and a.length() > 0.001:
				var now = base.basis.xform(skeleton.get_bone_rest(child).origin)
				d = turn(now, a)
		elif a != null:
			d = Basis(Vector3(1, 0, 0), deg2rad(a[0])) * Basis(Vector3(0, 1, 0), deg2rad(a[1])) * Basis(Vector3(0, 0, 1), deg2rad(a[2]))
		var origin = base.origin
		if name == "pelvis":
			origin += def.get("move", Vector3())
		var target = Transform(d * base.basis, origin)
		locals.append(base.affine_inverse() * target)
		globals.append(target)
	return {"pose": locals, "floor": _lowest(globals, id), "globals": globals}


# the bone this one points at (its first child that is part of the same limb), -1 if none
func _axis_child(i):
	var name = skeleton.get_bone_name(i)
	var chain = {"arm.l": "elbow.l", "arm.r": "elbow.r", "elbow.l": "hand.l", "elbow.r": "hand.r",
		"leg.l": "foot.l", "leg.r": "foot.r", "shoulder.l": "arm.l", "shoulder.r": "arm.r"}
	if chain.has(name):
		return skeleton.find_bone(chain[name])
	return -1


# the rotation that turns direction v onto direction d
static func turn(v, d):
	v = v.normalized()
	d = d.normalized()
	var c = v.cross(d)
	if c.length() < 0.00001:
		if v.dot(d) < 0.0:
			var any = Vector3(1, 0, 0) if abs(v.x) < 0.9 else Vector3(0, 1, 0)
			return Basis(v.cross(any).normalized(), PI)
		return Basis()
	return Basis(c.normalized(), acos(clamp(v.dot(d), -1.0, 1.0)))


# the lowest point of the skinned body (and the head) for a set of bone transforms
func _lowest(globals, id):
	var key = str(rec.get("outfit", {}).get("species", "")) + "|" + id
	var cache = Engine.get_meta("plushie_floor") if Engine.has_meta("plushie_floor") else {}
	if cache.has(key):
		return cache[key]
	var low = min(lowest_of(body_mesh, globals), lowest_of(species_mesh, globals))
	if low > 999.0:
		low = 0.0
	cache[key] = low
	Engine.set_meta("plushie_floor", cache)
	return low


# the lowest point (model units) of one skinned mesh for a set of bone transforms; 1000 if it has none
func lowest_of(node, globals):
	var low = 1000.0
	if node == null or not (node is MeshInstance) or node.mesh == null or node.skin == null:
		return low
	var skin = node.skin
	var mats = []
	for b in range(skin.get_bind_count()):
		var bone = skin.get_bind_bone(b)
		if bone < 0 and skin.get_bind_name(b) != "":
			bone = skeleton.find_bone(skin.get_bind_name(b))
		if bone < 0:
			mats.append(Transform())
		else:
			mats.append(globals[bone] * skin.get_bind_pose(b))
	for s in range(node.mesh.get_surface_count()):
		var arrays = node.mesh.surface_get_arrays(s)
		var verts = arrays[Mesh.ARRAY_VERTEX]
		var bones = arrays[Mesh.ARRAY_BONES]
		var weights = arrays[Mesh.ARRAY_WEIGHTS]
		if verts == null or bones == null or weights == null:
			continue
		for v in range(verts.size()):
			var p = Vector3()
			for k in range(4):
				var w = weights[v * 4 + k]
				if w > 0.0:
					var bi = int(bones[v * 4 + k])
					if bi < mats.size():
						p += mats[bi].xform(verts[v]) * w
			low = min(low, p.y)
	return low


func set_pose(id, instant = false):
	if skeleton == null:
		return
	if not Poses.has(id):
		id = "sit"
	pose_id = id
	_apply_goal(instant)


# held: it sits up and puts its arms round whoever is hugging it; released: back to its own pose
func set_held(on, hold = null):
	if held == on and hug_pose == hold:
		return
	held = on
	hug_pose = hold if on else null
	_apply_goal(false)


func _apply_goal(instant):
	var solved = solve("sit" if held else pose_id, hug_pose)
	goal = solved["pose"]
	goal_globals = solved["globals"]
	goal_floor = solved["floor"]
	if instant:
		cur = goal.duplicate()
		cur_floor = goal_floor
		_write_pose()


func _write_pose(shown = null):
	if shown == null:
		shown = cur
	for i in range(shown.size()):
		skeleton.set_bone_pose(i, shown[i])


func _process(delta):
	if not built:
		return
	clock += delta
	var k = clamp(delta * BLEND_SPEED, 0.0, 1.0)
	var moving = false
	for i in range(cur.size()):
		cur[i] = cur[i].interpolate_with(goal[i], k)
	cur_floor = lerp(cur_floor, goal_floor, k)
	_write_pose(_wave())
	_follow_tail()


# the waving pose swings its forearm from side to side (about the forward axis, the forearm points up)
func _wave():
	var out = cur.duplicate()
	var def = Poses.POSES.get(pose_id, {})
	if held or not def.has("wave"):
		return out
	var i = skeleton.find_bone(def["wave"])
	if i < 0 or i >= goal_globals.size():
		return out
	var par = skeleton.get_bone_parent(i)
	var gp = goal_globals[par].basis if par >= 0 else Basis()
	var g = goal_globals[i].basis
	var r = Basis(Vector3(0, 0, 1), sin(clock * 7.0) * 0.45)
	out[i] = Transform(gp.inverse() * r * g, goal[i].origin)
	return out


# where the node's origin goes for the feet at a spot: 1.0 x size above the soles, less how far the body
# hangs below (or floats above) them in this pose, plus any lift
func origin_for(feet_pos):
	return feet_pos + Vector3.UP * size * (1.0 - cur_floor) + Vector3.UP * lift_extra


func place(feet_pos, yaw_rad):
	feet = feet_pos
	yaw = yaw_rad
	rotation = Vector3(0, yaw_rad, 0)
	translation = origin_for(feet_pos)
