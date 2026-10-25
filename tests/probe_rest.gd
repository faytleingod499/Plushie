extends SceneTree
const Plush = preload("res://mods/Plushie/plush.gd")
func _init():
	var pl = Plush.new()
	root.add_child(pl)
	pl.setup({"id":"t","size":1.0,"pose":"stand","outfit":{}})
	var sk = pl.skeleton
	# rest global transforms, direction of each limb bone to its child
	var g = []
	for i in range(sk.get_bone_count()):
		var par = sk.get_bone_parent(i)
		var pg = Transform() if par < 0 else g[par]
		g.append(pg * sk.get_bone_rest(i))
	for i in range(sk.get_bone_count()):
		var kids = []
		for j in range(sk.get_bone_count()):
			if sk.get_bone_parent(j) == i:
				kids.append(j)
		var line = sk.get_bone_name(i) + " at " + str(g[i].origin)
		for j in kids:
			var dv = (g[j].origin - g[i].origin)
			line += "  -> " + sk.get_bone_name(j) + " dir " + str(dv.normalized()) + " len " + str(dv.length())
		print(line)
	quit()
