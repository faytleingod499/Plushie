extends SceneTree
const Main = preload("res://mods/Plushie/main.gd")
const Plush = preload("res://mods/Plushie/plush.gd")
var n = 0
var frames = 0
var main

func ok(cond, what):
	if not cond:
		n += 1
		print("FAIL: ", what)
	else:
		print("ok: ", what)

func _init():
	main = Main.new()
	root.add_child(main)

func _idle(delta):
	frames += 1
	if frames < 3:
		return false
	var outfit = Plush.sanitize({"species": "species_dog", "hat": "hat_cowboy", "accessory": []})
	var rec = {"id": "abc123", "name": "Bob|~<x>", "size": 0.8, "pose": "wave", "outfit": outfit}
	var e = {"id": "abc123", "rec": rec, "feet": Vector3(1.5, 2.25, -3.0), "yaw": 0.5, "owner": 5}
	var text = main._encode(e)
	print(text)
	ok(not ("~" in text.split("|")[1]) , "name stripped of separators")
	var d = main._decode(text)
	ok(d != null, "decodes")
	ok(d["rec"]["name"] == "Bob" or d["rec"]["name"] == "Bobx", "name " + d["rec"]["name"])
	ok(abs(d["rec"]["size"] - 0.8) < 0.01 and d["rec"]["pose"] == "wave", "size+pose")
	ok(d["feet"].distance_to(Vector3(1.5, 2.25, -3.0)) < 0.01, "feet")
	ok(d["rec"]["outfit"].get("species") == "species_dog", "outfit species")
	# hostile input
	ok(main._decode("x") == null, "short rejected")
	var acc = main._decode("abc|n|1|sit|0|0|0|0|accessory=weed+tunesmetics.hat_x;accessory_glasses;")
	ok(acc != null and acc["rec"]["outfit"]["accessory"] == ["weed+tunesmetics.hat_x", "accessory_glasses"], "accessory ids with + survive")
	var acc2 = main._decode("abc|n|1|sit|0|0|0|0|accessory=a+b")
	ok(acc2["rec"]["outfit"]["accessory"] == ["a", "b"], "old + format still reads")
	var longid = main._decode("abc|n|1|sit|0|0|0|0|primary_color=colorsexpandedpluspatterns.pcolor_pride_rainbow_2,secondary_color=colorsexpandedpluspatterns.scolor_pride_rainbow_3")
	ok(longid != null and longid["rec"]["outfit"].get("primary_color", "") == "colorsexpandedpluspatterns.pcolor_pride_rainbow_2" and longid["rec"]["outfit"].has("secondary_color"), "49-char colour ids survive decode")
	ok(main._decode("BAD ID!|n|1|sit|0|0|0|0|") == null, "bad id rejected")
	var h = main._decode("abc|n|99999|nopose|1e30|abc|nan|inf|species=../../x,junk,=,accessory=" + "a+".repeat(50))
	ok(h != null and h["rec"]["size"] <= Plush.MAX_SIZE and h["rec"]["pose"] == "sit", "clamped size, bad pose -> sit")
	ok(abs(h["feet"].x) <= 100000.0, "feet clamped")
	var clean = Plush.sanitize(h["rec"]["outfit"])
	ok(clean["species"] == "species_cat", "bad species falls back")
	# cap on name length
	ok(main._clean_name("x".repeat(60)).length() == 20, "name capped")
	# save/load
	main.collection = [rec]
	main.selected = "abc123"
	main._save_config()
	var m2 = Main.new()
	root.add_child(m2)
	ok(m2.collection.size() == 1 and m2.collection[0]["pose"] == "wave" and m2.selected == "abc123", "config roundtrip")
	# hug math sanity
	ok(main._yaw_facing(Vector3(0, 0, -1)) == 0.0 or abs(main._yaw_facing(Vector3(0, 0, -1))) < 0.001, "yaw facing -z = 0")
	print("failures: ", n)
	quit()
	return false
