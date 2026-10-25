extends SceneTree

# Renders plushies in poses on a floor so they can be looked at.
# env: POSES=sit,stand  VIEW=front|side|top|three  OUT=/path.png  SIZE=1.0  ROW=1 (all in a row)
const Plush = preload("res://mods/Plushie/plush.gd")
const Poses = preload("res://mods/Plushie/poses.gd")
var frames = 0
var out = ""

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
	light.light_energy = 0.9
	root.add_child(light)
	var floor_mesh = MeshInstance.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(60, 60)
	floor_mesh.mesh = plane
	var fm = SpatialMaterial.new()
	fm.albedo_color = Color(0.45, 0.6, 0.35)
	floor_mesh.material_override = fm
	root.add_child(floor_mesh)
	# a few marks on the floor every metre
	for i in range(-6, 7):
		var m = MeshInstance.new()
		var q = QuadMesh.new()
		q.size = Vector2(0.02, 40)
		m.mesh = q
		m.rotation_degrees = Vector3(-90, 0, 0)
		m.translation = Vector3(i, 0.002, 0)
		var mm = SpatialMaterial.new()
		mm.albedo_color = Color(0.3, 0.45, 0.25)
		m.material_override = mm
		root.add_child(m)

	var ids = OS.get_environment("POSES").split(",") if OS.get_environment("POSES") != "" else Poses.ORDER
	var size = float(OS.get_environment("SIZE")) if OS.get_environment("SIZE") != "" else 1.0
	var outfit = {}
	if OS.get_environment("OUTFIT") == "fancy":
		outfit = _fancy()
	var x = -(ids.size() - 1) * 1.6 / 2.0
	for id in ids:
		var pl = Plush.new()
		root.add_child(pl)
		var rec = {"id": "t", "name": "t", "size": size, "pose": id, "outfit": outfit}
		pl.setup(rec)
		pl.place(Vector3(x, 0, 0), 0.0)
		x += 1.6
		print(id, " floor=", pl.cur_floor, " origin=", pl.translation)
	var view = OS.get_environment("VIEW")
	var cam = Camera.new()
	cam.fov = 40
	root.add_child(cam)
	var span = max(2.5, (ids.size()) * 1.6 + 1.0) * size
	var dist = span * 1.1 + 2.0
	match view:
		"side":
			cam.translation = Vector3(dist, 1.2 * size, 0)
			cam.look_at(Vector3(0, 0.9 * size, 0), Vector3.UP)
		"top":
			cam.translation = Vector3(0, dist, 0.01)
			cam.look_at(Vector3(0, 0, 0), Vector3(0, 0, -1))
		"three":
			cam.translation = Vector3(dist * 0.6, dist * 0.45, dist * 0.7)
			cam.look_at(Vector3(0, 0.8 * size, 0), Vector3.UP)
		_:
			cam.translation = Vector3(0, 1.3 * size, -dist)
			cam.look_at(Vector3(0, 0.9 * size, 0), Vector3.UP)
	cam.current = true
	out = OS.get_environment("OUT")
	if out == "":
		out = "/tmp/shot.png"

func _fancy():
	var g = root.get_node("Globals")
	var pick = {}
	var cats = {}
	for k in g.cosmetic_data.keys():
		var parts = k.split("_")
		cats[parts[0]] = cats.get(parts[0], []) + [k]
	print("cosmetic prefixes: ", cats.keys())
	for key in ["hat", "undershirt", "overshirt", "legs", "eye", "mouth", "nose", "tail", "pattern", "species"]:
		pass
	var o = {"species": "species_dog", "pattern": "pattern_spots" if g.cosmetic_data.has("pattern_spots") else "pattern_none"}
	for prefix in [["hat", "hat"], ["undershirt", "shirt"], ["overshirt", "overshirt"], ["legs", "legs"]]:
		var list = cats.get(prefix[1], [])
		if list.size() > 3:
			o[prefix[0]] = list[3]
	var pcs = cats.get("pcolor", [])
	if pcs.size() > 4:
		o["primary_color"] = pcs[4]
	var scs = cats.get("scolor", [])
	if scs.size() > 2:
		o["secondary_color"] = scs[2]
	print("fancy: ", o)
	return o

func _idle(delta):
	frames += 1
	if frames == 12:
		var img = root.get_texture().get_data()
		img.flip_y()
		img.save_png(out)
		print("saved ", out)
		quit()
		return true
	return false
