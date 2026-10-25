extends SceneTree
# prints the lowest point of the body and of the head for a pose, with head turns tried
const Plush = preload("res://mods/Plushie/plush.gd")
const Poses = preload("res://mods/Plushie/poses.gd")
func _init():
	var pl = Plush.new()
	root.add_child(pl)
	pl.setup({"id":"t","size":1.0,"pose":"sit","outfit":{}})
	var ids = OS.get_environment("POSES").split(",") if OS.get_environment("POSES") != "" else Poses.ORDER
	for id in ids:
		var r = pl.solve(id)
		var g = r["globals"]
		print(id, " body low ", pl.lowest_of(pl.body_mesh, g), " head low ", pl.lowest_of(pl.species_mesh, g))
	# try head turns for the lying poses
	for id in ["back", "belly", "sleep"]:
		var def = Poses.POSES[id]
		for hr in [-90, -60, -30, 0, 20, 40, 60, 80]:
			var hold = {"head": [hr, 0, 0]} if id != "sleep" else {"head": [0, 0, hr]}
			var r2 = pl.solve(id, hold)
			print(id, " head ", hold["head"], " body low ", stepify(pl.lowest_of(pl.body_mesh, r2["globals"]), 0.001), " head low ", stepify(pl.lowest_of(pl.species_mesh, r2["globals"]), 0.001))
	quit()
