extends SceneTree
# the mouse ray hits a floor and the plushie follows it
const Main = preload("res://mods/Plushie/main.gd")
const Plush = preload("res://mods/Plushie/plush.gd")
var frames = 0
var main
var plush
func _init():
	var body = StaticBody.new()
	var shape = CollisionShape.new()
	var box = BoxShape.new()
	box.extents = Vector3(50, 0.5, 50)
	shape.shape = box
	body.add_child(shape)
	body.translation = Vector3(0, -0.5, 0)
	root.add_child(body)
	var cam = Camera.new()
	cam.translation = Vector3(0, 5, 5)
	cam.look_at(Vector3(0, 0, 0), Vector3.UP)
	root.add_child(cam)
	cam.current = true
	main = Main.new()
	root.add_child(main)
	plush = Plush.new()
	root.add_child(plush)
	plush.setup({"id": "p", "name": "p", "size": 0.5, "pose": "sit", "outfit": {}})
func _idle(d):
	frames += 1
	if frames == 40:
		var view = plush.get_viewport()
		var camx = view.get_camera()
		print("cam=", camx, " world=", plush.get_world(), " mouse=", root.get_mouse_position(), " vsize=", view.size)
		if camx != null:
			var at = root.get_mouse_position()
			var from = camx.project_ray_origin(at)
			var to = from + camx.project_ray_normal(at) * 150.0
			print("ray ", from, " -> ", to, " direct hit: ", plush.get_world().direct_space_state.intersect_ray(from, to, [], 1 | 2))
			print("down ray: ", plush.get_world().direct_space_state.intersect_ray(Vector3(0, 5, 0), Vector3(0, -5, 0), [], 1 | 2))
		var p = main._mouse_ground(plush, Vector2(800, 700))
		print("hit: ", p)
		print("PASS" if p != null and abs(p.y) < 0.01 else "FAIL")
		var e = {"key": "1:p", "node": plush, "rec": {}, "feet": Vector3(), "yaw": 0.0, "owner": 1, "id": "p"}
		main.entries["1:p"] = e
		main.moving = e
		main.move_from = Vector3(9, 0, 9)
		main._finish_move(false)
		print("cancel restores: ", e["feet"], " moving=", main.moving)
		quit()
	return false
