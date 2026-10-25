extends SceneTree
const Main = preload("res://mods/Plushie/main.gd")
const Plush = preload("res://mods/Plushie/plush.gd")
var frames = 0
var main
var bg
func _init():
	bg = ColorRect.new()
	bg.color = Color(0.3, 0.45, 0.6)
	bg.rect_size = Vector2(2000, 1200)
	root.add_child(bg)
	main = Main.new()
	root.add_child(main)
func _idle(delta):
	frames += 1
	if frames == 2:
		for c in root.get_children():
			if c != main and c != bg and c.get("visible") != null:
				c.set("visible", false)
				print("hid ", c.name)
		var o = Plush.sanitize({})
		main.collection = [{"id": "a1", "name": "Mochi", "size": 0.45, "pose": "wave", "outfit": o}, {"id": "b2", "name": "Big Bear", "size": 1.2, "pose": "sit", "outfit": o}]
		main.selected = "a1"
		main.button.visible = true
		main.set_process(false)
		main._set_menu(true)
		var b = Button.new(); b.text = "Fayt"; main._glass_button(b); main.maker_box.add_child(b)
	if frames == 8:
		main.button.visible = true
		var img = root.get_viewport().get_texture().get_data()
		img.flip_y()
		img.save_png("/home/claude/shots/menu.png")
		quit()
	main.button.visible = true
	return false
