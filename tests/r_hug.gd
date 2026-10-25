extends SceneTree

# Renders a hug: a stand-in hugger (a plush body) and a plushie, mid-hug.
# env: PS=0.45 (plushie size) HS=1.0 (hugger size) VIEW=side|front|three OUT=path T=1.0 POSE=sit
const Plush = preload("res://mods/Plushie/plush.gd")
const Main = preload("res://mods/Plushie/main.gd")
var frames = 0
var out = ""
var hugger
var plush
var main
var s
var tmax = 1.0

func _init():
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.9)
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.8
	var we = WorldEnvironment.new()
	we.environment = env
	root.add_child(we)
	var light = DirectionalLight.new()
	light.rotation_degrees = Vector3(-50, -30, 0)
	root.add_child(light)
	var fm = MeshInstance.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(60, 60)
	fm.mesh = plane
	var mat = SpatialMaterial.new()
	mat.albedo_color = Color(0.45, 0.6, 0.35)
	fm.material_override = mat
	root.add_child(fm)

	var hs = float(OS.get_environment("HS")) if OS.get_environment("HS") != "" else 1.0
	var ps = float(OS.get_environment("PS")) if OS.get_environment("PS") != "" else 0.45
	tmax = float(OS.get_environment("T")) if OS.get_environment("T") != "" else 1.0
	hugger = Plush.new()
	root.add_child(hugger)
	hugger.setup({"id": "h", "name": "h", "size": hs, "pose": "stand", "outfit": {"species": "species_cat", "primary_color": "pcolor_blue"}})
	hugger.place(Vector3(0, 0, 0), 0.0)   # faces -z
	plush = Plush.new()
	root.add_child(plush)
	var pose = OS.get_environment("POSE") if OS.get_environment("POSE") != "" else "sit"
	plush.setup({"id": "p", "name": "p", "size": ps, "pose": pose, "outfit": {"species": "species_cat", "primary_color": "pcolor_orange", "hat": "hat_cowboy"}})
	var home = Vector3(0, 0, -2.0)
	plush.place(home, 0.0)
	main = Main.new()
	root.add_child(main)
	var e = {"key": "1:p", "node": plush, "owner": 1, "id": "p", "feet": home, "yaw": 0.0}
	main.entries["1:p"] = e
	s = {"hugger": hugger, "entry": e, "t": 0.0, "w": 0.0, "ending": false, "squeaked": true, "start": hugger.translation, "mine": true, "home_feet": home, "home_yaw": 0.0}
	if OS.get_environment("NOH") != "":
		hugger.visible = false
	var cam = Camera.new()
	cam.fov = 40
	root.add_child(cam)
	var view = OS.get_environment("VIEW")
	var mid = Vector3(0, 1.0 * hs, -0.6 * hs)
	var cd = float(OS.get_environment("CAMD")) if OS.get_environment("CAMD") != "" else 4.5
	var cy = float(OS.get_environment("CAMY")) if OS.get_environment("CAMY") != "" else 0.9
	match view:
		"front":
			cam.translation = Vector3(0.0, cy + 0.3, -cd)
			cam.look_at(Vector3(0, cy, 0), Vector3.UP)
		"top":
			cam.translation = Vector3(0, cd, 0.01)
			cam.look_at(Vector3(0, 0, -0.2), Vector3(0, 0, -1))
		"three":
			cam.translation = Vector3(cd * 0.7, cy + 0.8, -cd * 0.7)
			cam.look_at(Vector3(0, cy, -0.2), Vector3.UP)
		_:
			cam.translation = Vector3(cd, cy + 0.1, -0.2)
			cam.look_at(Vector3(0, cy, -0.2), Vector3.UP)
	cam.current = true
	out = OS.get_environment("OUT") if OS.get_environment("OUT") != "" else "/tmp/hug.png"

func _idle(delta):
	frames += 1
	if s["t"] < tmax:
		s["t"] += 1.0 / 30.0
		s["w"] = min(1.0, s["t"] / main.HUG_BLEND)
		main._pose_hug(s)
		return false
	if frames % 1 == 0:
		hugger._process(0.033)
		plush._process(0.033)
		main._pose_hug(s)
	if frames > 1000 + 0 and false:
		pass
	if s.has("shot") == false:
		s["shot"] = frames + 6
	if frames >= s["shot"]:
		var img = root.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png(out)
		var hk = hugger.skeleton; for hn in ["arm.l","elbow.l","hand.l","hand.r"]: print(hn, " world=", hk.global_transform.xform(hk.get_bone_global_pose(hk.find_bone(hn)).origin), " no_override=", hk.global_transform.xform(hk.get_bone_global_pose_no_override(hk.find_bone(hn)).origin)); print("torso=", plush.skeleton.global_transform.xform(plush.skeleton.get_bone_global_pose_no_override(plush.skeleton.find_bone("torso")).origin)); print("goal0=", plush.goal[0], " floor=", plush.cur_floor, " goalfloor=", plush.goal_floor, " mesh vis=", plush.body_mesh.visible, " species=", plush.species_mesh); print("plush held=", plush.held, " vis=", plush.visible, " pos=", plush.global_transform.origin, " scale=", plush.scale, " sh=", hugger.skeleton.global_transform.xform(hugger.skeleton.get_bone_global_pose_no_override(hugger.skeleton.find_bone("arm.l")).origin)); print("hugger built=", hugger.built, " vis=", hugger.visible, " scale=", hugger.scale, " pos=", hugger.translation, " body=", hugger.body, " aabb=", hugger.body_mesh.get_aabb() if hugger.body_mesh else null); print("saved ", out, " plush y=", plush.translation, " hugger y=", hugger.translation)
		quit()
	return false
