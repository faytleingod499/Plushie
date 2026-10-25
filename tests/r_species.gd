extends SceneTree
# one plushie per species (and with/without a pattern), coloured red, to check the skin colour shows
const Plush = preload("res://mods/Plushie/plush.gd")
var frames = 0
func _init():
	var env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.62, 0.78, 0.9)
	env.ambient_light_color = Color(0.7, 0.7, 0.75)
	env.ambient_light_energy = 0.8
	var we = WorldEnvironment.new(); we.environment = env; root.add_child(we)
	var light = DirectionalLight.new(); light.rotation_degrees = Vector3(-50, -30, 0); root.add_child(light)
	var g = root.get_node("Globals")
	var sp = []
	for k in g.cosmetic_data.keys():
		if k.begins_with("species_"): sp.append(k)
	print("species: ", sp)
	var pats = []
	for k in g.cosmetic_data.keys():
		if k.begins_with("pattern_"): pats.append(k)
	print("patterns: ", pats)
	var x = -(sp.size() * 2 - 1) * 0.8
	for s in sp:
		for pat in ["pattern_none", pats[1] if pats.size() > 1 else "pattern_none"]:
			var pl = Plush.new()
			root.add_child(pl)
			pl.setup({"id": "t", "name": "t", "size": 1.0, "pose": "stand", "outfit": {"species": s, "primary_color": "pcolor_red", "secondary_color": "scolor_blue" if g.cosmetic_data.has("scolor_blue") else "scolor_tan", "pattern": pat}})
			pl.place(Vector3(x, 0, 0), 0.0)
			x += 1.6
	var cam = Camera.new(); cam.fov = 40; root.add_child(cam)
	cam.translation = Vector3(0, 1.3, -9); cam.look_at(Vector3(0, 0.9, 0), Vector3.UP); cam.current = true
func _idle(d):
	frames += 1
	if frames == 8:
		var img = root.get_viewport().get_texture().get_data(); img.flip_y(); img.save_png("/home/claude/shots/species.png"); quit()
	return false
