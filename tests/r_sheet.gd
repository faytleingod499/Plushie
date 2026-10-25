extends SceneTree

# Renders each pose from several angles into OUT_DIR/<pose>_<view>.png
# env: POSES=a,b  VIEWS=front,side,back,top  OUT_DIR=/path  SIZE=1.0  OUTFIT=fancy|default|cat|dog
const Plush = preload("res://mods/Plushie/plush.gd")
const Poses = preload("res://mods/Plushie/poses.gd")
var jobs = []
var job = 0
var wait = 0
var phase = 0
var cur_job = null
var pl = null
var cam = null
var out_dir = ""

func _init():
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.9)
	env.ambient_light_color = Color(0.75, 0.75, 0.8)
	env.ambient_light_energy = 0.9
	var we = WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var light = DirectionalLight.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	light.light_energy = 0.8
	root.add_child(light)
	var fl = MeshInstance.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(60, 60)
	fl.mesh = plane
	var fm = SpatialMaterial.new()
	fm.albedo_color = Color(0.5, 0.65, 0.4)
	fl.material_override = fm
	root.add_child(fl)
	for i in range(-5, 6):
		for axis in [0, 1]:
			var m = MeshInstance.new()
			var q = QuadMesh.new()
			q.size = Vector2(0.02, 40)
			m.mesh = q
			m.rotation_degrees = Vector3(-90, 0 if axis == 0 else 90, 0)
			m.translation = Vector3(i if axis == 0 else 0, 0.002, i if axis == 1 else 0)
			var mm = SpatialMaterial.new()
			mm.albedo_color = Color(0.35, 0.5, 0.3)
			m.material_override = mm
			root.add_child(m)
	cam = Camera.new()
	cam.fov = 35
	root.add_child(cam)
	cam.current = true
	var ids = OS.get_environment("POSES").split(",") if OS.get_environment("POSES") != "" else Poses.ORDER
	var views = OS.get_environment("VIEWS").split(",") if OS.get_environment("VIEWS") != "" else ["front", "side"]
	out_dir = OS.get_environment("OUT_DIR") if OS.get_environment("OUT_DIR") != "" else "/home/claude/shots/sheet"
	for id in ids:
		for v in views:
			jobs.append([id, v])
	var d = Directory.new()
	d.make_dir_recursive(out_dir)

func _outfit():
	var kind = OS.get_environment("OUTFIT")
	var g = root.get_node("Globals")
	if kind == "dog":
		return {"species": "species_dog"}
	if kind == "fancy":
		var cats = {}
		for k in g.cosmetic_data.keys():
			var parts = k.split("_")
			cats[parts[0]] = cats.get(parts[0], []) + [k]
		var o = {"species": "species_cat"}
		var pick = {"hat": "hat", "undershirt": "shirt", "overshirt": "overshirt", "legs": "legs", "pattern": "pattern", "primary_color": "pcolor", "secondary_color": "scolor"}
		for key in pick.keys():
			var list = cats.get(pick[key], [])
			if list.size() > 4:
				o[key] = list[4]
		return o
	return {}

func _cam_for(view, size, centre):
	var d = 6.2 * max(size, 0.6)
	var h = centre.y
	match view:
		"side":
			return [Vector3(d, h, 0), centre]
		"back":
			return [Vector3(0, h, d), centre]
		"top":
			return [Vector3(0.01, d * 1.15, 0.0), centre]
		"three":
			return [Vector3(-d * 0.62, h + d * 0.28, -d * 0.7), centre]
		_:
			return [Vector3(0, h, -d), centre]

func _idle(delta):
	if wait > 0:
		wait -= 1
		return false
	if phase == 1:
		# aim the camera at the middle of the plushie's bones, then give it a few frames to draw
		var sk = pl.skeleton
		var lo = Vector3(1000, 1000, 1000)
		var hi = Vector3(-1000, -1000, -1000)
		for i in range(sk.get_bone_count()):
			var w = sk.global_transform.xform(sk.get_bone_global_pose(i).origin)
			lo = Vector3(min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z))
			hi = Vector3(max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z))
		var mid = (lo + hi) / 2.0
		mid.y = max(mid.y, 0.35 * pl.size) + 0.25 * pl.size
		var c = _cam_for(cur_job[1], pl.size, mid)
		cam.translation = c[0]
		cam.look_at(c[1], Vector3.UP if cur_job[1] != "top" else Vector3(0, 0, -1))
		phase = 2
		wait = 3
		return false
	if phase == 2:
		var img = root.get_texture().get_data()
		img.flip_y()
		var path = out_dir + "/" + cur_job[0] + "_" + cur_job[1] + ".png"
		img.save_png(path)
		print("saved ", path, " floor=", pl.cur_floor)
		pl.queue_free()
		pl = null
		phase = 0
	if job >= jobs.size():
		quit()
		return true
	cur_job = jobs[job]
	job += 1
	var size = float(OS.get_environment("SIZE")) if OS.get_environment("SIZE") != "" else 1.0
	pl = Plush.new()
	root.add_child(pl)
	pl.setup({"id": "t", "name": "t", "size": size, "pose": cur_job[0], "outfit": _outfit()})
	pl.place(Vector3(0, 0, 0), 0.0)
	phase = 1
	wait = 2
	return false
