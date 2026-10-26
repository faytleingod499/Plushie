extends Node

# Plushie: turn a player you see into a plushie that wears their outfit. Name it, make it bigger or smaller,
# sit it in a pose, and hug it (E): it squeaks, is pulled in to you and, if you are bigger than it, is lifted
# up to your chest. Other players with the mod see your plushies and can hug them too.
#
# Everything here is client side. A plushie is only ever a copy of a body (plush.gd) that the mod draws; the
# only thing sent to other players is a short line in the Steam lobby (like Hugs and More does).
#
# Lobby member data, written by each player for themself:
#   plushie     "1~<plushie>~<plushie>..." the plushies I have put out (at most 3), each
#               "<id>|<name>|<size>|<pose>|<x>|<y>|<z>|<yaw>|<outfit>"
#               outfit = "species=species_cat,hat=hat_none,...,accessory=a+b"
#   plushie_h   "1|<seq>|<owner steam id>|<plushie id>"  I started hugging that plushie
#   plushie_v   the mod's version (so the others know I have it)

const VERSION = "1.4.4"
const Plush = preload("res://mods/Plushie/plush.gd")
const Poses = preload("res://mods/Plushie/poses.gd")

const SYNC_KEY = "plushie"
const HUG_KEY = "plushie_h"
const VER_KEY = "plushie_v"
const CONFIG_PATH = "user://plushie.json"
const SKELETON_PATH = "body/player_body/Armature/Skeleton"
const POPUP_ID = "PLUSHIE"
const HEARTS = "res://Scenes/Particles/kiss.tscn"
const OPEN_KEY = KEY_O

const MAX_COLLECTION = 30
const MAX_LIFT = 5.0          # how far a plushie can be moved from where it was put, each way, on each axis (metres)
const LIST_WIDTH = 200       # the pop-out list; the menu itself is 250 wide, the list is never wider or taller
const MAX_PLACED = 3
const MAX_NAME = 20
const DEFAULT_SIZE = 0.45
const SEE_RANGE = 40.0       # players further than this aren't offered
const SHOW_RANGE = 45.0      # names are hidden past this
const PUT_DISTANCE = 1.4     # where a plushie is put, in front of me (times my size)

const PROMPT_RANGE = 0.4     # how close you have to be (plus an eighth of the plushie's size) for the tag
const HUG_TIME = 3.2
const HUG_BLEND = 0.4
const HUG_MOVE = 0.8         # walking further than this ends a hug
const SQUEAK_AT = 0.42
const HUG_COOLDOWN = 1.0
# the plushie's arms go forward and in, round whoever is holding it
const HOLD = {"arm.l": Vector3(0.5, 0.0, 0.9), "arm.r": Vector3(-0.5, 0.0, 0.9),
	"elbow.l": Vector3(-0.5, 0.1, 0.95), "elbow.r": Vector3(0.5, 0.1, 0.95)}
const BIGGER = 0.9           # I lift a plushie when it is smaller than this times my size

var steam = null
var clock = 0.0
var squeaks = []
var hearts_scene = null

var collection = []          # my plushies (records): {id, name, size, pose, outfit}
var selected = ""
var entries = {}             # "<owner>:<id>" -> {key, owner, id, rec, node, feet, yaw, label}
var sessions = {}            # hugger steam id -> a running hug
var hug_seen = {}            # hugger steam id -> last hug seq seen
var remote_text = {}         # owner steam id -> the last plushie line read
var my_hug_seq = 0
var my_hug_text = ""
var sync_dirty = true
var announced_lobby = 0
var next_check = 0.0
var read_timer = 0.0
var hug_ready_at = 0.0
var last_lobby = -1
var last_world = null

# interface
var layer
var name_layer
var button
var menu
var menu_open = false
var menu_title
var maker_box
var maker_ids = ""
var list_box
var list_title
var list_panel
var list_scroll
var lift_slider
var grab_button
var moving = null          # the plushie being dragged with the mouse
var move_from = Vector3()
var move_sync_at = 0.0
var move_labels = {}
var all_away_button
var lift_label
var detail
var name_field
var size_slider
var size_label
var pose_buttons = {}
var put_button
var toast
var prompt_layer
var prompt
var prompt_word
var prompt_entry = null
var turn_slider
var turn_label
var toast_until = 0.0
var btn_hover = false
var btn_pressed = false
var btn_dragging = false
var press_pos = Vector2()
var drag_offset = Vector2()
var locked_hud = null
var theme_applied = false
var refresh_timer = 0.0
var updating_ui = false


func _ready():
	if Engine.has_singleton("Steam"):
		steam = Engine.get_singleton("Steam")
	for i in range(1, 4):
		var s = _load_wav("res://mods/Plushie/squeak" + str(i) + ".wav")
		if s != null:
			squeaks.append(s)
	if ResourceLoader.exists(HEARTS):
		hearts_scene = load(HEARTS)
	_build_ui()
	_load_config()
	_refresh_all()
	print("[Plushie] ", VERSION, " loaded")


func _exit_tree():
	for key in sessions.keys():
		_end_session(key)
	_unlock_hud()
	for key in entries.keys():
		_free_entry(entries[key])
	entries.clear()
	_write_member(HUG_KEY, "")
	_write_member(SYNC_KEY, "")


# --- every frame ---

func _process(delta):
	clock += delta
	var net = get_node_or_null("/root/Network")
	var lobby = 0
	lobby = _lobby_of(net)
	var me = _my_id()
	var local = _local_player()

	_update_button(local)
	if local != last_world:
		# a new world (or none): the old plushies went with it
		last_world = local
		_drop_all_nodes()
	if lobby != last_lobby:
		last_lobby = lobby
		sync_dirty = true
		hug_seen.clear()
		remote_text.clear()

	if local != null:
		_sync(lobby, me, delta)
		_update_entries(local, me)
		_update_sessions(delta, me)
		_update_prompt(local, me)
		_follow_mouse()
		_update_labels()
	if menu_open:
		refresh_timer += delta
		if refresh_timer >= 0.5:
			refresh_timer = 0.0
			_refresh_makers()
	toast.visible = clock < toast_until


func _local_player():
	var list = get_tree().get_nodes_in_group("controlled_player")
	if list.empty() or not is_instance_valid(list[0]):
		return null
	return list[0]


func _players():
	var out = {}
	for player in get_tree().get_nodes_in_group("player"):
		if not is_instance_valid(player) or player.get("dead_actor") == true or player.get("NPC_body") == true:
			continue
		var id = player.get("owner_id")
		if id != null and int(id) > 0:
			out[int(id)] = player
	return out


# --- sharing with the lobby ---

func _write_member(key, text):
	var lobby = _lobby_of(get_node_or_null("/root/Network"))
	if steam == null or lobby <= 0:
		return
	if steam.has_method("setLobbyMemberData"):
		steam.setLobbyMemberData(lobby, key, text)


func _read_member(lobby, id, key):
	if steam == null or lobby <= 0 or not steam.has_method("getLobbyMemberData"):
		return ""
	return str(steam.getLobbyMemberData(lobby, int(id), key))


func _sync(lobby, me, delta):
	# a write made while still joining a lobby is lost, so what I wrote is read back every few seconds
	if lobby > 0 and steam != null and clock >= next_check:
		next_check = clock + 3.0
		if _read_member(lobby, me, VER_KEY) != VERSION:
			_write_member(VER_KEY, VERSION)
			if lobby != announced_lobby:
				print("[Plushie] ", VERSION, " announced in lobby ", lobby)
			announced_lobby = lobby
			sync_dirty = true
		elif _read_member(lobby, me, SYNC_KEY) != _my_text():
			sync_dirty = true
		if my_hug_text != "" and _read_member(lobby, me, HUG_KEY) != my_hug_text:
			_write_member(HUG_KEY, my_hug_text)
	if sync_dirty:
		sync_dirty = false
		_write_member(SYNC_KEY, _my_text())

	read_timer += delta
	if read_timer >= 0.25:
		read_timer = 0.0
		_read_others(lobby, me)


func _my_text():
	var parts = []
	for key in entries.keys():
		var e = entries[key]
		if e["owner"] == _my_id():
			parts.append(_encode(e))
	if parts.empty():
		return ""
	var text = "1~" + "~".join(parts)
	return text if text.length() < 3500 else ""


func _my_id():
	var net = get_node_or_null("/root/Network")
	var id = net.get("STEAM_ID") if net != null else null
	return int(id) if id != null else 0


func _lobby_of(net):
	if net == null or net.get("PLAYING_OFFLINE") == true:
		return 0
	var l = net.get("STEAM_LOBBY_ID")
	return int(l) if l != null and int(l) > 0 else 0


func _clean_name(text):
	var out = ""
	for i in range(str(text).length()):
		var c = str(text)[i]
		var code = c.ord_at(0)
		if code >= 32 and code != 127 and not (c in ["|", "~", "<", ">"]):
			out += c
	return out.strip_edges().left(MAX_NAME)


func _encode(e):
	var rec = e["rec"]
	var bits = []
	var outfit = rec.get("outfit", {})
	for k in outfit.keys():
		if k == "accessory":
			# "+" between accessories, as older versions read it; an id that has a "+" in it (a mod's name) is
			# sent with ";" instead, with one on the end so the reader knows
			var plus = false
			for a in outfit[k]:
				if "+" in str(a):
					plus = true
			bits.append("accessory=" + (";".join(PoolStringArray(outfit[k])) + ";" if plus else "+".join(PoolStringArray(outfit[k]))))
		else:
			bits.append(str(k) + "=" + str(outfit[k]))
	var f = e["feet"]
	return "|".join([e["id"], _clean_name(rec.get("name", "")), "%.2f" % float(rec.get("size", DEFAULT_SIZE)), rec.get("pose", "sit"),
		"%.2f" % f.x, "%.2f" % f.y, "%.2f" % f.z, "%.2f" % e["yaw"], ",".join(bits), "%.2f" % float(rec.get("lift", 0.0)),
		"%.2f" % float(rec.get("ox", 0.0)), "%.2f" % float(rec.get("oz", 0.0))])


func _valid_id(id):
	var text = str(id)
	if text.length() < 1 or text.length() > 12:
		return false
	for i in range(text.length()):
		var c = text[i]
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9")):
			return false
	return true


func _num(text, low, high, fallback):
	if not str(text).is_valid_float():
		return fallback
	return clamp(float(text), low, high)


# anything that came from another player is checked here before it is used
func _decode(text):
	var f = str(text).split("|")
	if f.size() < 9 or not _valid_id(f[0]):
		return null
	var outfit = {}
	for item in str(f[8]).split(","):
		var kv = item.split("=")
		if kv.size() != 2 or kv[0].length() > 24:
			continue
		if kv[0] == "accessory":
			var list = []
			for a in kv[1].split(";" if ";" in kv[1] else "+"):
				if a != "" and a.length() <= 96:
					list.append(a)
			outfit["accessory"] = list
		elif kv[1].length() <= 96:
			outfit[kv[0]] = kv[1]
	var pose = f[3] if Poses.has(f[3]) else "sit"
	var lim = 100000.0
	return {"id": f[0], "rec": {"id": f[0], "name": _clean_name(f[1]), "size": _num(f[2], Plush.MIN_SIZE, Plush.MAX_SIZE, DEFAULT_SIZE),
			"pose": pose, "outfit": outfit, "lift": _num(f[9] if f.size() > 9 else "0", -MAX_LIFT, MAX_LIFT, 0.0),
			"ox": _num(f[10] if f.size() > 10 else "0", -MAX_LIFT, MAX_LIFT, 0.0), "oz": _num(f[11] if f.size() > 11 else "0", -MAX_LIFT, MAX_LIFT, 0.0)},
		"feet": Vector3(_num(f[4], -lim, lim, 0.0), _num(f[5], -lim, lim, 0.0), _num(f[6], -lim, lim, 0.0)),
		"yaw": _num(f[7], -20.0, 20.0, 0.0)}


func _read_others(lobby, me):
	var players = _players()
	# plushies of players who have left go away
	for key in entries.keys():
		var e = entries[key]
		if e["owner"] != me and not players.has(e["owner"]):
			_remove_entry(key)
	if lobby <= 0 or steam == null:
		return
	for id in players.keys():
		if id == me:
			continue
		var text = _read_member(lobby, id, SYNC_KEY)
		if remote_text.get(id, null) != text:
			remote_text[id] = text
			_apply_remote(id, text)
		_read_hug(lobby, id, players[id])


func _apply_remote(owner, text):
	var wanted = {}
	if text.begins_with("1~"):
		var records = text.substr(2).split("~")
		for r in records:
			if wanted.size() >= MAX_PLACED:
				break
			var d = _decode(r)
			if d != null:
				wanted[d["id"]] = d
	for key in entries.keys():
		if entries[key]["owner"] == owner and not wanted.has(entries[key]["id"]):
			_remove_entry(key)
	for id in wanted.keys():
		var d = wanted[id]
		var key = str(owner) + ":" + id
		if entries.has(key):
			var e = entries[key]
			var changed = e["rec"].get("outfit", {}) != d["rec"]["outfit"] or float(e["rec"]["size"]) != float(d["rec"]["size"])
			e["rec"] = d["rec"]
			e["feet"] = d["feet"]
			e["yaw"] = d["yaw"]
			if changed:
				_rebuild_entry(e)
			else:
				e["node"].set_pose(d["rec"]["pose"])
		else:
			_add_entry(owner, d["rec"], d["feet"], d["yaw"])


func _read_hug(lobby, id, player):
	var text = _read_member(lobby, id, HUG_KEY)
	var f = text.split("|")
	if f.size() < 4 or f[0] != "1":
		return
	var seq = int(f[1])
	if not hug_seen.has(id):
		hug_seen[id] = seq     # a hug that was already there when I arrived isn't replayed
		return
	if seq == hug_seen[id]:
		return
	hug_seen[id] = seq
	var key = f[2] + ":" + f[3]
	if entries.has(key) and not sessions.has(id):
		_start_session(id, player, entries[key], false)


# --- the plushies in the world ---

# where a plushie stands: the spot it was put plus the x and z the sliders moved it
func _spot(e):
	var rec = e["rec"]
	return e["feet"] + Vector3(float(rec.get("ox", 0.0)), 0, float(rec.get("oz", 0.0)))


func _hug_text(rec):
	var n = str(rec.get("name", ""))
	return "Hug " + (n if n != "" else "plushie")


func _add_entry(owner, rec, feet, yaw):
	var local = _local_player()
	if local == null:
		return null
	var parent = local.get_parent()
	if parent == null:
		return null
	var node = Plush.new()
	parent.add_child(node)
	if not node.setup(rec):
		node.queue_free()
		return null
	node.place(feet, yaw)
	var e = {"key": str(owner) + ":" + rec["id"], "owner": owner, "id": rec["id"], "rec": rec, "node": node,
		"feet": feet, "yaw": yaw, "label": _make_label()}
	entries[e["key"]] = e
	return e


func _rebuild_entry(e):
	if is_instance_valid(e["node"]):
		e["node"].queue_free()
	var local = _local_player()
	if local == null:
		return
	var node = Plush.new()
	local.get_parent().add_child(node)
	if not node.setup(e["rec"]):
		node.queue_free()
		return
	node.place(_spot(e), e["yaw"])
	e["node"] = node


func _free_entry(e):
	if e.has("label") and is_instance_valid(e["label"]):
		e["label"].queue_free()
	if is_instance_valid(e["node"]):
		e["node"].queue_free()


func _remove_entry(key):
	if not entries.has(key):
		return
	for hugger in sessions.keys():
		if sessions[hugger]["entry"] == entries[key]:
			_end_session(hugger)
	_free_entry(entries[key])
	entries.erase(key)
	sync_dirty = true


# the world went away: the nodes are gone with it. Mine can be put out again from the menu.
func _drop_all_nodes():
	for hugger in sessions.keys():
		sessions.erase(hugger)
	for key in entries.keys():
		var e = entries[key]
		if e.has("label") and is_instance_valid(e["label"]):
			e["label"].queue_free()
	entries.clear()
	remote_text.clear()
	sync_dirty = true
	_refresh_all()


func _update_entries(local, me):
	for key in entries.keys():
		var e = entries[key]
		if not is_instance_valid(e["node"]):
			_remove_entry(key)
			continue
		var busy = false
		for hugger in sessions.keys():
			if sessions[hugger]["entry"] == e:
				busy = true
		if not busy:
			e["node"].lift_extra = float(e["rec"].get("lift", 0.0))
			e["node"].place(_spot(e), e["yaw"])


# the floor under a spot
func _ground(node, pos, fallback_y):
	var space = node.get_world().direct_space_state if node.get_world() != null else null
	if space == null:
		return Vector3(pos.x, fallback_y, pos.z)
	var hit = space.intersect_ray(Vector3(pos.x, max(pos.y, fallback_y) + 1.5, pos.z), Vector3(pos.x, min(pos.y, fallback_y) - 4.0, pos.z), [], 1 | 2)
	if hit.empty():
		return Vector3(pos.x, fallback_y, pos.z)
	return Vector3(pos.x, hit["position"].y, pos.z)


func _facing(node):
	var f = -node.global_transform.basis.z
	f.y = 0
	return f.normalized() if f.length() > 0.001 else Vector3(0, 0, -1)


func _player_size(player):
	var sk = player.get_node_or_null(SKELETON_PATH)
	if sk != null:
		return sk.global_transform.basis.get_scale().y
	return player.global_transform.basis.get_scale().y


func _yaw_facing(dir):
	# the yaw that makes a plushie face along dir (its front is -z)
	return atan2(-dir.x, -dir.z)


func _put_out(rec):
	var local = _local_player()
	if local == null:
		_toast("Join a game first")
		return
	var key = str(_my_id()) + ":" + rec["id"]
	if not entries.has(key):
		var count = 0
		for k in entries.keys():
			if entries[k]["owner"] == _my_id():
				count += 1
		if count >= MAX_PLACED:
			_toast("Put one away first (" + str(MAX_PLACED) + " out at a time)")
			return
	var s = _player_size(local)
	var f = _facing(local)
	var spot = local.global_transform.origin + f * PUT_DISTANCE * max(s, 0.5)
	var feet = _ground(local, spot, local.global_transform.origin.y - 1.0 * s)
	var yaw = _yaw_facing(-f)   # facing me
	rec["ox"] = 0.0     # a fresh spot: the sliders start from zero again
	rec["oz"] = 0.0
	rec["lift"] = 0.0
	if entries.has(key):
		var e = entries[key]
		e["feet"] = feet
		e["yaw"] = yaw
		e["rec"] = rec
	else:
		_add_entry(_my_id(), rec, feet, yaw)
	sync_dirty = true
	_refresh_all()


func _put_away(rec):
	_remove_entry(str(_my_id()) + ":" + rec["id"])
	_refresh_all()


func _is_out(rec):
	return entries.has(str(_my_id()) + ":" + rec["id"])


# --- hugging ---

func _hug_entry(found):
	var me = _my_id()
	var actor = _local_player()
	if actor == null or found == null or clock < hug_ready_at or sessions.has(me):
		return
	for hugger in sessions.keys():
		if sessions[hugger]["entry"] == found:
			return   # someone else is hugging it
	hug_ready_at = clock + HUG_COOLDOWN
	my_hug_seq += 1
	my_hug_text = "1|" + str(my_hug_seq) + "|" + str(found["owner"]) + "|" + found["id"]
	_write_member(HUG_KEY, my_hug_text)
	_start_session(me, actor, found, true)


# the small "E  Hug <name>" tag on the nearest plushie within reach, in the same glass as the other mods
func _update_prompt(local, me):
	prompt_entry = null
	if local != null and _hud_free() and not sessions.has(me) and clock >= hug_ready_at:
		var here = local.global_transform.origin
		var best = 1e9
		for key in entries.keys():
			var e = entries[key]
			var node = e["node"]
			if not is_instance_valid(node) or _taken_by_hug(e):
				continue
			var reach = PROMPT_RANGE + 0.125 * node.size
			var d = Vector3(node.global_transform.origin.x - here.x, 0, node.global_transform.origin.z - here.z).length()
			if d < reach and d < best:
				best = d
				prompt_entry = e
	if prompt_entry == null:
		prompt.visible = false
		return
	var nm = str(prompt_entry["rec"].get("name", ""))
	var text = "Hug " + (nm if nm != "" else "plushie")
	if prompt_word.text != text:
		prompt_word.text = text
	_place_on(prompt, prompt_entry["node"])


func _taken_by_hug(e):
	for hugger in sessions.keys():
		if sessions[hugger]["entry"] == e:
			return true
	return false


# nothing of the game's is open (my own menu can be)
func _hud_free():
	var hud = _get_hud()
	if hud == null:
		return false
	if hud.get("menu") != 0 or hud.get("hud_hidden") == true or hud.get("using_chat") == true:
		return false
	var popups = hud.get("popups")
	if typeof(popups) == TYPE_ARRAY and not popups.empty():
		return false
	return true


# puts a small box on screen over the middle of a plushie's body
func _place_on(control, node):
	var view = node.get_viewport()
	var camera = view.get_camera() if view != null else null
	if camera == null or not node.is_visible_in_tree():
		control.visible = false
		return
	var at3 = node.global_transform.origin
	var sk = node.skeleton
	if sk != null and sk.find_bone("torso") >= 0:
		at3 = sk.global_transform.xform(sk.get_bone_global_pose(sk.find_bone("torso")).origin)
	if camera.is_position_behind(at3):
		control.visible = false
		return
	var at = camera.unproject_position(at3)
	var holder = view.get_parent()
	if holder is ViewportContainer and view.size.x > 0 and view.size.y > 0:
		var box = holder.get_global_rect()
		at = box.position + at * (box.size / view.size)
	control.visible = true
	control.rect_size = Vector2()
	var size = control.get_combined_minimum_size()
	control.rect_position = Vector2(at.x - size.x / 2.0, at.y - size.y / 2.0)


func _start_session(hugger_id, hugger, entry, mine):
	if not is_instance_valid(hugger) or not is_instance_valid(entry["node"]):
		return
	for h in sessions.keys():
		if sessions[h]["entry"] == entry:
			return
	sessions[hugger_id] = {"hugger": hugger, "entry": entry, "t": 0.0, "w": 0.0, "ending": false, "squeaked": false,
		"start": hugger.global_transform.origin, "mine": mine,
		"home_feet": _spot(entry), "home_yaw": entry["yaw"]}


func _end_session(hugger_id):
	if not sessions.has(hugger_id):
		return
	var s = sessions[hugger_id]
	if is_instance_valid(s["hugger"]):
		_clear_arms(s["hugger"])
	var e = s["entry"]
	if is_instance_valid(e["node"]):
		e["node"].set_held(false)
		e["node"].lift_extra = float(e["rec"].get("lift", 0.0))
		e["node"].place(_spot(e), e["yaw"])
	sessions.erase(hugger_id)


func _update_sessions(delta, me):
	for hugger_id in sessions.keys():
		var s = sessions[hugger_id]
		var e = s["entry"]
		if not is_instance_valid(s["hugger"]) or not is_instance_valid(e["node"]) or not entries.has(e["key"]):
			_end_session(hugger_id)
			continue
		s["t"] += delta
		var moved = (s["hugger"].global_transform.origin - s["start"]).length()
		if s["t"] > HUG_TIME or moved > HUG_MOVE:
			s["ending"] = true
		if s["ending"]:
			s["w"] = max(0.0, s["w"] - delta / HUG_BLEND)
			if s["w"] <= 0.0:
				_end_session(hugger_id)
				continue
		else:
			s["w"] = min(1.0, s["t"] / HUG_BLEND)
		_pose_hug(s)


func _ease(w):
	return w * w * (3.0 - 2.0 * w)


func _bone_world(sk, name, fallback):
	var i = sk.find_bone(name)
	if i < 0:
		return fallback
	return sk.global_transform.xform(sk.get_bone_global_pose_no_override(i).origin)


# What a hug looks like: the plushie is pulled in to the hugger (lifted to their chest when the hugger is the
# bigger one), sits up and puts its arms round them, and the hugger's arms reach round the plushie.
func _pose_hug(s):
	var hugger = s["hugger"]
	var e = s["entry"]
	var plush = e["node"]
	var w = _ease(s["w"])
	var hs = _player_size(hugger)
	var sp = plush.size
	var hp = hugger.global_transform.origin
	var f = _facing(hugger)
	var left = Vector3.UP.cross(f).normalized()
	var lifted = sp < hs * BIGGER
	var gap = 0.30 * (hs + sp) / 2.0 + 0.04
	var spot = hp + f * gap
	var hfeet = hp.y - 1.0 * hs
	var hsk = hugger.get_node_or_null(SKELETON_PATH)
	var shoulder = _bone_world(hsk, "arm.l", hp + Vector3.UP * 0.5 * hs).y if hsk != null else hp.y + 0.5 * hs

	plush.set_held(w > 0.02 and (not s["ending"] or w > 0.3), HOLD)
	var home = s["home_feet"]
	var target_feet = Vector3(spot.x, hfeet, spot.z)
	if not lifted:
		target_feet = _ground(hugger, spot, hfeet)
	var yaw_target = _yaw_facing(-f)
	var yaw = lerp_angle(s["home_yaw"], yaw_target, w)
	var feet = home.linear_interpolate(target_feet, w)
	plush.lift_extra = lerp(float(e["rec"].get("lift", 0.0)), 0.0, w)
	plush.place(feet, yaw)
	if lifted:
		# its middle (the torso) level with the hugger's chest, where their arms reach
		var rest_y = plush.translation.y
		var torso_off = rest_y
		if plush.skeleton != null and plush.skeleton.find_bone("torso") >= 0:
			var tb = plush.skeleton.get_bone_global_pose_no_override(plush.skeleton.find_bone("torso")).origin
			torso_off = rest_y - plush.skeleton.global_transform.xform(tb).y
		var held_y = shoulder - 0.2 * hs + torso_off
		plush.translation.y = lerp(rest_y, max(held_y, rest_y), w)

	# the hugger's arms round the plushie
	if hsk != null:
		var middle = plush.global_transform.origin
		var torso = plush.skeleton.find_bone("torso") if plush.skeleton != null else -1
		if torso >= 0:
			middle = plush.skeleton.global_transform.xform(plush.skeleton.get_bone_global_pose_no_override(torso).origin)
		var radius = max(0.24 * sp, 0.10 * hs)
		var centre = middle + f * radius * 0.45
		var body = {"sk": hsk, "W": hsk.global_transform, "Winv": hsk.global_transform.affine_inverse(),
			"rebase": Transform(), "spot": Vector3(hp.x, 0, hp.z)}
		_reach(body, [centre, left * radius * 0.6], [Vector3.DOWN * 0.6 - f * 0.2, left], left, w)

	if not s["squeaked"] and s["t"] >= SQUEAK_AT and not s["ending"]:
		s["squeaked"] = true
		_squeak(plush)
		_hearts(hugger, middle_of(plush) + Vector3.UP * (0.7 * sp + 0.3 * hs))


func middle_of(plush):
	return plush.global_transform.origin


func _squeak(plush):
	if squeaks.empty() or not is_instance_valid(plush):
		return
	var p = AudioStreamPlayer3D.new()
	p.stream = squeaks[randi() % squeaks.size()]
	p.pitch_scale = rand_range(0.9, 1.15) * clamp(1.0 / pow(max(plush.size, 0.15) / DEFAULT_SIZE, 0.35), 0.7, 1.4)
	p.unit_db = 2.0
	p.unit_size = 2.6
	p.max_distance = 30.0
	if AudioServer.get_bus_index("SFX") >= 0:
		p.bus = "SFX"
	plush.add_child(p)
	p.connect("finished", p, "queue_free")
	p.play()


func _hearts(node, at):
	if hearts_scene == null or not is_instance_valid(node):
		return
	var fx = hearts_scene.instance()
	node.add_child(fx)
	fx.set_as_toplevel(true)
	fx.global_transform.origin = at
	fx.emitting = true
	get_tree().create_timer(fx.lifetime + 0.3).connect("timeout", fx, "queue_free")


func _flat(v):
	return Vector3(v.x, 0, v.z)


# reaches both arms so the fingertips end at points round the plushie (same two-bone reach as Hugs and More)
func _reach(body, target_w, pole_w, left, w):
	var sk = body["sk"]
	for side in [["arm.l", "elbow.l", "hand.l"], ["arm.r", "elbow.r", "hand.r"]]:
		var arm = sk.find_bone(side[0])
		var elbow = sk.find_bone(side[1])
		var hand = sk.find_bone(side[2])
		if arm < 0 or elbow < 0 or hand < 0:
			continue
		var g_arm = sk.get_bone_global_pose_no_override(arm)
		var g_elbow = sk.get_bone_global_pose_no_override(elbow)
		var a = body["rebase"] * g_arm
		var s = sign(_flat(body["W"].xform(a.origin) - body["spot"]).dot(left))
		if s == 0:
			s = 1.0
		var t = target_w[0] + target_w[1] * s
		var pole = pole_w[0] + pole_w[1] * s
		_two_bone(sk, arm, elbow, hand, a, body["rebase"] * g_elbow, body["rebase"] * sk.get_bone_global_pose_no_override(hand),
			body["Winv"].xform(t), body["Winv"].basis.xform(pole).normalized(), g_arm, g_elbow, w)


func _two_bone(sk, arm, elbow, hand, a, e, hnd, target, pole, g_arm, g_elbow, w):
	var finger = 0.08
	var S = a.origin
	var E0 = e.origin
	var H0 = hnd.origin + (hnd.origin - e.origin).normalized() * finger
	var la = S.distance_to(E0)
	var lb = E0.distance_to(H0)
	var to = target - S
	var d = clamp(to.length(), abs(la - lb) + 0.001, la + lb - 0.001)
	var u = to.normalized()
	var cos_a = clamp((la * la + d * d - lb * lb) / (2.0 * la * d), -1.0, 1.0)
	var p = pole - u * pole.dot(u)
	if p.length() < 0.001:
		p = Vector3.DOWN - u * Vector3.DOWN.dot(u)
	p = p.normalized()
	var E = S + u * la * cos_a + p * la * sqrt(max(0.0, 1.0 - cos_a * cos_a))
	var T = S + u * d

	var arm_new = Transform(_turn(E0 - S, E - S) * a.basis, S)
	var elbow_mid = arm_new * (g_arm.affine_inverse() * g_elbow)
	var tip_local = g_elbow.affine_inverse().xform(sk.get_bone_global_pose_no_override(hand).origin)
	var tip_dir = (sk.get_bone_global_pose_no_override(hand).origin - g_elbow.origin).normalized()
	var hand_now = elbow_mid.xform(tip_local) + elbow_mid.basis.xform(g_elbow.basis.inverse().xform(tip_dir)) * finger
	var elbow_new = Transform(_turn(hand_now - elbow_mid.origin, T - elbow_mid.origin) * elbow_mid.basis, elbow_mid.origin)
	sk.set_bone_global_pose_override(arm, arm_new, w, true)
	sk.set_bone_global_pose_override(elbow, elbow_new, w, true)


func _turn(v, d):
	v = v.normalized()
	d = d.normalized()
	var c = v.cross(d)
	if c.length() < 0.00001:
		return Basis()
	return Basis(c.normalized(), acos(clamp(v.dot(d), -1.0, 1.0)))


func _clear_arms(player):
	var sk = player.get_node_or_null(SKELETON_PATH)
	if sk == null:
		return
	for name in ["arm.l", "elbow.l", "arm.r", "elbow.r"]:
		var bone = sk.find_bone(name)
		if bone >= 0:
			sk.set_bone_global_pose_override(bone, Transform(), 0.0, true)


# --- names over the plushies ---

func _make_label():
	var label = Label.new()
	label.align = Label.ALIGN_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.visible = false
	label.add_color_override("font_color", Color(1, 1, 1))
	label.add_color_override("font_color_shadow", Color(0.05, 0.1, 0.15, 0.9))
	label.add_constant_override("shadow_as_outline", 1)
	label.add_constant_override("shadow_offset_x", 1)
	label.add_constant_override("shadow_offset_y", 1)
	name_layer.add_child(label)
	return label


func _update_labels():
	var hud = _get_hud()
	for key in entries.keys():
		var e = entries[key]
		var label = e["label"]
		var node = e["node"]
		var text = str(e["rec"].get("name", ""))
		if text == "" or not is_instance_valid(node) or (hud != null and hud.get("hud_hidden") == true):
			label.visible = false
			continue
		var view = node.get_viewport()
		var camera = view.get_camera() if view != null else null
		if camera == null or not node.is_visible_in_tree():
			label.visible = false
			continue
		var top = node.global_transform.origin + Vector3.UP * 1.25 * node.size
		var sk = node.skeleton
		if sk != null and sk.find_bone("head") >= 0:
			top = sk.global_transform.xform(sk.get_bone_global_pose(sk.find_bone("head")).origin) + Vector3.UP * 0.8 * node.size
		var dist = camera.global_transform.origin.distance_to(top)
		if camera.is_position_behind(top) or dist > SHOW_RANGE:
			label.visible = false
			continue
		if label.text != text:
			label.text = text
			label.rect_size = Vector2()
		var sc = clamp(8.0 / max(dist, 0.1), 0.45, 1.0)
		label.rect_scale = Vector2(sc, sc)
		var size = label.get_combined_minimum_size()
		label.rect_size = size
		var at = camera.unproject_position(top)
		var holder = view.get_parent()
		if holder is ViewportContainer and view.size.x > 0 and view.size.y > 0:
			var box = holder.get_global_rect()
			at = box.position + at * (box.size / view.size)
		label.rect_position = at - Vector2(size.x * sc / 2.0, size.y * sc)
		label.visible = true


# --- making a plushie ---

# players I can see right now (in front of the camera and not too far)
func _visible_players(local):
	var list = []
	var view = local.get_viewport()
	var camera = view.get_camera() if view != null else null
	for id in _players().keys():
		var p = _players()[id]
		var outfit = p.get("cosmetic_data")
		if typeof(outfit) != TYPE_DICTIONARY or outfit.empty():
			continue
		var at = p.global_transform.origin
		if camera != null:
			if camera.is_position_behind(at) or camera.global_transform.origin.distance_to(at) > SEE_RANGE:
				continue
		list.append([id, p])
	return list


func _make_plushie(player, id):
	if collection.size() >= MAX_COLLECTION:
		_toast("You have " + str(MAX_COLLECTION) + " plushies, delete one first")
		return
	var outfit = player.get("cosmetic_data")
	if typeof(outfit) != TYPE_DICTIONARY:
		return
	var clean = Plush.sanitize(outfit)
	if clean.empty():
		return
	var nm = _clean_name(_name_of(id))
	print("[Plushie] captured outfit of ", nm, ": species=", clean.get("species"), " primary=", clean.get("primary_color"), " secondary=", clean.get("secondary_color"), " pattern=", clean.get("pattern"), " (game sent ", outfit.get("primary_color"), ")")
	var rec = {"id": _new_id(), "name": nm, "size": DEFAULT_SIZE, "pose": "sit", "outfit": clean}
	collection.append(rec)
	selected = rec["id"]
	_save_config()
	_put_out(rec)
	_refresh_all()
	_toast("Made a plushie of " + (nm if nm != "" else "them"))


func _new_id():
	var chars = "abcdefghijklmnopqrstuvwxyz0123456789"
	var out = ""
	randomize()
	for i in range(8):
		out += chars[randi() % chars.length()]
	return out


func _name_of(id):
	var net = get_node_or_null("/root/Network")
	if net != null:
		var members = net.get("LOBBY_MEMBERS")
		if members != null:
			for member in members:
				if int(member.get("steam_id", 0)) == int(id):
					return str(member.get("steam_name", ""))
	if steam != null and steam.has_method("getFriendPersonaName"):
		return str(steam.getFriendPersonaName(int(id)))
	return ""


func _record(id):
	for rec in collection:
		if rec["id"] == id:
			return rec
	return null


# --- saving ---

func _save_config():
	var data = {"x": button.rect_position.x, "y": button.rect_position.y, "selected": selected, "plushies": collection}
	var file = File.new()
	if file.open(CONFIG_PATH, File.WRITE) == OK:
		file.store_string(to_json(data))
		file.close()


func _load_config():
	var file = File.new()
	if not file.file_exists(CONFIG_PATH) or file.open(CONFIG_PATH, File.READ) != OK:
		return
	var data = parse_json(file.get_as_text())
	file.close()
	if typeof(data) != TYPE_DICTIONARY:
		return
	if data.has("x") and data.has("y"):
		button.rect_position = Vector2(float(data["x"]), float(data["y"]))
	var list = data.get("plushies", [])
	if typeof(list) == TYPE_ARRAY:
		for r in list:
			if typeof(r) != TYPE_DICTIONARY or collection.size() >= MAX_COLLECTION:
				continue
			var id = str(r.get("id", ""))
			if not _valid_id(id):
				id = _new_id()
			collection.append({"id": id, "name": _clean_name(r.get("name", "")),
				"size": clamp(float(r.get("size", DEFAULT_SIZE)), Plush.MIN_SIZE, Plush.MAX_SIZE),
				"pose": str(r.get("pose", "sit")) if Poses.has(str(r.get("pose", "sit"))) else "sit",
				"outfit": r.get("outfit", {}) if typeof(r.get("outfit", {})) == TYPE_DICTIONARY else {},
				"lift": clamp(float(r.get("lift", 0.0)), -MAX_LIFT, MAX_LIFT),
				"ox": clamp(float(r.get("ox", 0.0)), -MAX_LIFT, MAX_LIFT), "oz": clamp(float(r.get("oz", 0.0)), -MAX_LIFT, MAX_LIFT)})
	selected = str(data.get("selected", ""))
	if _record(selected) == null:
		selected = collection[0]["id"] if not collection.empty() else ""


# --- the button and the menu ---

func _build_ui():
	name_layer = CanvasLayer.new()
	name_layer.layer = 0
	add_child(name_layer)
	# the hug tag sits under the game's own windows, the menu on top
	prompt_layer = CanvasLayer.new()
	prompt_layer.layer = 1
	add_child(prompt_layer)
	layer = CanvasLayer.new()
	layer.layer = 3
	add_child(layer)

	prompt = PanelContainer.new()
	prompt.visible = false
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_stylebox_override("panel", _glass(Color(0.06, 0.12, 0.18, 0.55), Color(0.55, 1.0, 1.0, 0.45), 8, 3))
	prompt_layer.add_child(prompt)
	var prow = HBoxContainer.new()
	prow.add_constant_override("separation", 6)
	prow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prompt.add_child(prow)
	var pkey = Label.new()
	pkey.text = "E"
	pkey.add_color_override("font_color", Color(0.55, 1.0, 1.0))
	pkey.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prow.add_child(pkey)
	prompt_word = Label.new()
	prompt_word.text = "Hug"
	prompt_word.add_color_override("font_color", Color(1, 1, 1, 0.9))
	prompt_word.mouse_filter = Control.MOUSE_FILTER_IGNORE
	prow.add_child(prompt_word)
	prompt.rect_scale = Vector2(0.85, 0.85)

	button = Control.new()
	button.rect_size = Vector2(34, 34)
	button.rect_min_size = Vector2(34, 34)
	button.rect_position = Vector2(56, 330)
	button.mouse_filter = Control.MOUSE_FILTER_STOP
	button.visible = false
	button.connect("draw", self, "_draw_button")
	button.connect("gui_input", self, "_on_button_input")
	button.connect("mouse_entered", self, "_on_button_hover", [true])
	button.connect("mouse_exited", self, "_on_button_hover", [false])
	layer.add_child(button)
	_add_tooltip(button, "Plushies", "Click (or press O) to make plushies. Drag to move this button")

	toast = Label.new()
	toast.visible = false
	toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toast.add_color_override("font_color", Color(1, 1, 1))
	toast.add_color_override("font_color_shadow", Color(0.05, 0.1, 0.15, 0.9))
	toast.add_constant_override("shadow_as_outline", 1)
	toast.set_anchors_and_margins_preset(Control.PRESET_CENTER_TOP)
	toast.margin_top = 90
	toast.align = Label.ALIGN_CENTER
	layer.add_child(toast)

	menu = PanelContainer.new()
	menu.visible = false
	menu.mouse_filter = Control.MOUSE_FILTER_STOP
	menu.add_stylebox_override("panel", _glass(Color(0.06, 0.12, 0.18, 0.75), Color(0.55, 1.0, 1.0, 0.45), 10, 6))
	layer.add_child(menu)

	var margin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_constant_override("margin_" + side, 8)
	menu.add_child(margin)
	var column = VBoxContainer.new()
	column.add_constant_override("separation", 6)
	column.rect_min_size = Vector2(250, 0)
	margin.add_child(column)

	var head = HBoxContainer.new()
	column.add_child(head)
	menu_title = Label.new()
	menu_title.text = "Plushies"
	menu_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	menu_title.add_color_override("font_color", Color(0.75, 0.95, 1.0))
	head.add_child(menu_title)
	var close = Button.new()
	close.text = "x"
	close.focus_mode = Control.FOCUS_NONE
	close.connect("pressed", self, "_set_menu", [false])
	_glass_button(close)
	head.add_child(close)

	column.add_child(_small_label("Make a plushie of a player you can see"))
	maker_box = VBoxContainer.new()
	maker_box.add_constant_override("separation", 3)
	column.add_child(maker_box)

	# the list of plushies pops out beside the menu, never taller than the menu, with a scroll bar when long
	list_panel = PanelContainer.new()
	list_panel.visible = false
	list_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	list_panel.add_stylebox_override("panel", _glass(Color(0.06, 0.12, 0.18, 0.75), Color(0.55, 1.0, 1.0, 0.45), 10, 6))
	layer.add_child(list_panel)
	var lmargin = MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		lmargin.add_constant_override("margin_" + side, 8)
	list_panel.add_child(lmargin)
	var lcol = VBoxContainer.new()
	lcol.add_constant_override("separation", 6)
	lcol.rect_min_size = Vector2(LIST_WIDTH, 0)
	lmargin.add_child(lcol)
	list_title = _small_label("Your plushies")
	lcol.add_child(list_title)
	list_scroll = ScrollContainer.new()
	list_scroll.scroll_horizontal_enabled = false
	lcol.add_child(list_scroll)
	list_box = VBoxContainer.new()
	list_box.add_constant_override("separation", 3)
	list_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_scroll.add_child(list_box)

	detail = VBoxContainer.new()
	detail.add_constant_override("separation", 5)
	column.add_child(detail)

	name_field = LineEdit.new()
	name_field.placeholder_text = "name"
	name_field.max_length = MAX_NAME
	name_field.connect("text_entered", self, "_on_name_entered")
	name_field.connect("focus_exited", self, "_on_name_done")
	detail.add_child(name_field)

	var size_row = HBoxContainer.new()
	size_row.add_constant_override("separation", 8)
	detail.add_child(size_row)
	var size_name = Label.new()
	size_name.text = "Size"
	size_name.add_color_override("font_color", Color(1, 1, 1))
	size_row.add_child(size_name)
	size_slider = HSlider.new()
	size_slider.min_value = Plush.MIN_SIZE
	size_slider.max_value = Plush.MAX_SIZE
	size_slider.step = 0.05
	size_slider.value = DEFAULT_SIZE
	size_slider.focus_mode = Control.FOCUS_NONE
	size_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_slider.connect("value_changed", self, "_on_size_changed")
	size_row.add_child(size_slider)
	size_label = Label.new()
	size_label.rect_min_size = Vector2(46, 0)
	size_label.align = Label.ALIGN_RIGHT
	size_label.add_color_override("font_color", Color(1, 1, 1))
	size_row.add_child(size_label)

	var turn_row = HBoxContainer.new()
	turn_row.add_constant_override("separation", 8)
	detail.add_child(turn_row)
	var turn_name = Label.new()
	turn_name.text = "Turn"
	turn_name.add_color_override("font_color", Color(1, 1, 1))
	turn_row.add_child(turn_name)
	turn_slider = HSlider.new()
	turn_slider.min_value = 0
	turn_slider.max_value = 360
	turn_slider.step = 5
	turn_slider.focus_mode = Control.FOCUS_NONE
	turn_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	turn_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	turn_slider.connect("value_changed", self, "_on_turn_changed")
	turn_row.add_child(turn_slider)
	turn_label = Label.new()
	turn_label.rect_min_size = Vector2(46, 0)
	turn_label.align = Label.ALIGN_RIGHT
	turn_label.add_color_override("font_color", Color(1, 1, 1))
	turn_row.add_child(turn_label)

	# up and down: 0 in the middle, up to MAX_LIFT metres each way (below zero it sinks into the ground)
	lift_slider = _move_row("Up/down", "_on_lift_changed")

	grab_button = Button.new()
	grab_button.text = "Grab and move"
	grab_button.focus_mode = Control.FOCUS_NONE
	grab_button.connect("pressed", self, "_on_grab")
	_glass_button(grab_button)
	detail.add_child(grab_button)

	var grid = GridContainer.new()
	grid.columns = 3
	grid.add_constant_override("hseparation", 4)
	grid.add_constant_override("vseparation", 4)
	detail.add_child(grid)
	for id in Poses.ORDER:
		var b = Button.new()
		b.text = Poses.label(id)
		b.focus_mode = Control.FOCUS_NONE
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.connect("pressed", self, "_on_pose", [id])
		_glass_button(b)
		grid.add_child(b)
		pose_buttons[id] = b

	var row = HBoxContainer.new()
	row.add_constant_override("separation", 4)
	detail.add_child(row)
	put_button = Button.new()
	put_button.focus_mode = Control.FOCUS_NONE
	put_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	put_button.connect("pressed", self, "_on_put")
	_glass_button(put_button)
	row.add_child(put_button)
	var away = Button.new()
	away.text = "Put away"
	away.focus_mode = Control.FOCUS_NONE
	away.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	away.connect("pressed", self, "_on_away")
	_glass_button(away)
	row.add_child(away)
	var del = Button.new()
	del.text = "Delete"
	del.focus_mode = Control.FOCUS_NONE
	del.connect("pressed", self, "_on_delete")
	_glass_button(del)
	row.add_child(del)

	all_away_button = Button.new()
	all_away_button.text = "Put all away"
	all_away_button.focus_mode = Control.FOCUS_NONE
	all_away_button.connect("pressed", self, "_on_all_away")
	_glass_button(all_away_button)
	column.add_child(all_away_button)


func _move_row(title, callback):
	var row = HBoxContainer.new()
	row.add_constant_override("separation", 8)
	detail.add_child(row)
	var name = Label.new()
	name.text = title
	name.rect_min_size = Vector2(70, 0)
	name.add_color_override("font_color", Color(1, 1, 1))
	row.add_child(name)
	var slider = HSlider.new()
	slider.min_value = -MAX_LIFT
	slider.max_value = MAX_LIFT
	slider.step = 0.05
	slider.focus_mode = Control.FOCUS_NONE
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.connect("value_changed", self, callback)
	row.add_child(slider)
	var label = Label.new()
	label.rect_min_size = Vector2(52, 0)
	label.align = Label.ALIGN_RIGHT
	label.add_color_override("font_color", Color(1, 1, 1))
	row.add_child(label)
	move_labels[slider] = label
	return slider


func _small_label(text):
	var l = Label.new()
	l.text = text
	l.add_color_override("font_color", Color(0.75, 0.95, 1.0))
	return l


func _draw_button():
	var box = button.rect_size
	var fill = Color(0.3, 1.0, 1.0, 0.30 if btn_hover else 0.16)
	if menu_open:
		fill = Color(0.3, 1.0, 1.0, 0.45)
	button.draw_style_box(_glass(fill, Color(0.55, 1.0, 1.0, 0.8 if btn_hover else 0.5), 8, 0), Rect2(Vector2(), box))
	var c = Color(1, 1, 1, 0.95)
	var dark = Color(0.06, 0.12, 0.18, 0.95)
	var mid = box / 2.0 + Vector2(0, 2)
	button.draw_circle(mid + Vector2(-8.5, -8.5), 4.5, c)    # ears
	button.draw_circle(mid + Vector2(8.5, -8.5), 4.5, c)
	button.draw_circle(mid, 11.5, c)                         # head
	button.draw_circle(mid + Vector2(-4.2, -2.0), 1.7, dark) # eyes
	button.draw_circle(mid + Vector2(4.2, -2.0), 1.7, dark)
	button.draw_circle(mid + Vector2(0, 3.8), 4.0, Color(0.75, 0.95, 1.0, 0.95))   # snout
	button.draw_circle(mid + Vector2(0, 2.6), 1.5, dark)     # nose


func _on_button_hover(inside):
	btn_hover = inside
	button.update()


func _on_button_input(event):
	if event is InputEventMouseButton and event.button_index == BUTTON_LEFT and event.pressed:
		btn_pressed = true
		btn_dragging = false
		press_pos = event.global_position
		drag_offset = button.rect_position - press_pos
		button.accept_event()


# --- grab and move: the plushie follows the mouse over the ground; click to put it down, Esc to cancel ---

func _on_grab():
	var rec = _record(selected)
	if rec == null:
		return
	var key = str(_my_id()) + ":" + rec["id"]
	if not entries.has(key):
		return
	moving = entries[key]
	move_from = moving["feet"]
	rec["ox"] = 0.0
	rec["oz"] = 0.0
	menu.visible = false
	list_panel.visible = false


func _finish_move(commit):
	if moving == null:
		return
	if not commit:
		moving["feet"] = move_from
	moving = null
	sync_dirty = true
	if menu_open:
		menu.visible = true
		list_panel.visible = true
		_refresh_detail()
		call_deferred("_place_menu")


# the point of the ground under the mouse
func _mouse_ground(node, point = null):
	var view = node.get_viewport()
	var camera = view.get_camera() if view != null else null
	if camera == null or node.get_world() == null:
		return null
	var at = get_viewport().get_mouse_position() if point == null else point
	var holder = view.get_parent()
	if holder is ViewportContainer and view.size.x > 0 and view.size.y > 0:
		var box = holder.get_global_rect()
		at = (at - box.position) * (view.size / box.size)
	var from = camera.project_ray_origin(at)
	var to = from + camera.project_ray_normal(at) * 150.0
	var hit = node.get_world().direct_space_state.intersect_ray(from, to, [], 1 | 2)
	return null if hit.empty() else hit["position"]


func _follow_mouse():
	var e = moving
	if e == null:
		return
	if not is_instance_valid(e["node"]) or not entries.has(e["key"]) or _local_player() == null:
		_finish_move(false)
		return
	toast.text = "Click to put it down, Esc to cancel"
	toast.rect_size = Vector2()
	toast_until = clock + 0.3
	var p = _mouse_ground(e["node"])
	if p != null:
		e["feet"] = p
		if clock >= move_sync_at:
			move_sync_at = clock + 0.25
			sync_dirty = true


func _input(event):
	if moving != null:
		if event is InputEventMouseButton and event.pressed:
			_finish_move(event.button_index == BUTTON_LEFT)
			get_tree().set_input_as_handled()
		elif event is InputEventKey and event.pressed and event.scancode == KEY_ESCAPE:
			_finish_move(false)
			get_tree().set_input_as_handled()
		return
	if btn_pressed:
		if event is InputEventMouseMotion:
			if not btn_dragging and event.position.distance_to(press_pos) > 4.0:
				btn_dragging = true
			if btn_dragging:
				var area = get_viewport().get_visible_rect().size
				var pos = event.position + drag_offset
				pos.x = clamp(pos.x, 0, max(0, area.x - button.rect_size.x))
				pos.y = clamp(pos.y, 0, max(0, area.y - button.rect_size.y))
				button.rect_position = pos
				_place_menu()
		elif event is InputEventMouseButton and event.button_index == BUTTON_LEFT and not event.pressed:
			btn_pressed = false
			if btn_dragging:
				btn_dragging = false
				_save_config()
			else:
				_set_menu(not menu_open)
		return
	if event is InputEventKey and event.pressed and not event.echo and event.is_action("interact") and prompt != null and prompt.visible and prompt_entry != null and not _typing():
		_hug_entry(prompt_entry)
		get_tree().set_input_as_handled()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.scancode == OPEN_KEY and not _typing() and (button.visible or menu_open):
			_set_menu(not menu_open)
			get_tree().set_input_as_handled()
		elif event.scancode == KEY_ESCAPE and menu_open:
			_set_menu(false)
			get_tree().set_input_as_handled()


func _typing():
	var hud = _get_hud()
	if hud != null and hud.get("using_chat") == true:
		return true
	var focus = button.get_focus_owner()
	return focus != null and focus is LineEdit


func _get_hud():
	var list = get_tree().get_nodes_in_group("controlled_player")
	if list.empty():
		return null
	var hud = list[0].get("hud")
	if hud == null or not is_instance_valid(hud):
		return null
	return hud


func _update_button(local):
	var hud = _get_hud()
	var show = hud != null and local != null
	if show:
		if hud.get("menu") != 0 or hud.get("hud_hidden") == true:
			show = false
		var popups = hud.get("popups")
		if typeof(popups) == TYPE_ARRAY:
			for entry in popups:
				if entry != POPUP_ID:
					show = false
		var options = get_node_or_null("/root/OptionsMenu")
		if options != null and options.get("open") == true:
			show = false
	if show and not theme_applied:
		theme_applied = true
		var main = hud.get_node_or_null("main")
		if main != null and main.theme != null:
			button.theme = main.theme
			menu.theme = main.theme
	if not show and menu_open:
		_set_menu(false)
	if not show:
		btn_pressed = false
		btn_dragging = false
	button.visible = show


func _set_menu(open):
	if menu_open == open:
		return
	menu_open = open
	menu.visible = open
	list_panel.visible = open
	button.update()
	if open:
		_refresh_all()
		_place_menu()
		call_deferred("_place_menu")
		_lock_hud()
	else:
		_on_name_done()
		_unlock_hud()
		_save_config()


func _place_menu():
	if not menu.visible:
		return
	var area = get_viewport().get_visible_rect().size
	menu.rect_size = Vector2()
	var size = menu.get_combined_minimum_size()
	menu.rect_size = size
	var lsize = _size_list(size)
	var gap = 6.0
	var bx = button.rect_position.x
	var pos = button.rect_position + Vector2(button.rect_size.x + gap, 0)
	var list_x
	if pos.x + size.x > area.x:
		# the menu opens on the button's left, and the list on the menu's left
		pos.x = bx - size.x - gap
		list_x = pos.x - lsize.x - gap
	else:
		# the menu opens on the button's right, so the list goes left of the button...
		list_x = bx - lsize.x - gap
		if list_x < 0:
			# ...unless there is no room there: then it sits between the button and the menu
			list_x = pos.x
			pos.x += lsize.x + gap
	pos.x = clamp(pos.x, 0, max(0, area.x - size.x))
	pos.y = clamp(pos.y, 0, max(0, area.y - size.y))
	menu.rect_position = pos
	list_x = clamp(list_x, 0, max(0, area.x - lsize.x))
	list_panel.rect_position = Vector2(list_x, clamp(pos.y, 0, max(0, area.y - lsize.y)))


# the list is as tall as its contents but never taller than the menu, and scrolls when there are more
# plushies than fit; returns its size
func _size_list(menu_size):
	var inner = list_box.get_combined_minimum_size().y
	var head = list_title.get_combined_minimum_size().y + 6 + 16     # title, gap, margins
	var room = max(60.0, menu_size.y - head)
	list_scroll.rect_min_size = Vector2(0, min(inner, room))
	list_panel.rect_size = Vector2()
	var size = list_panel.get_combined_minimum_size()
	list_panel.rect_size = size
	return size


# while the menu is open the game ignores its keys (so typing a name doesn't move or fish)
func _lock_hud():
	var hud = _get_hud()
	if hud == null:
		return
	var popups = hud.get("popups")
	if typeof(popups) == TYPE_ARRAY and not popups.has(POPUP_ID):
		popups.append(POPUP_ID)
	locked_hud = hud


func _unlock_hud():
	if locked_hud != null and is_instance_valid(locked_hud):
		var popups = locked_hud.get("popups")
		if typeof(popups) == TYPE_ARRAY:
			popups.erase(POPUP_ID)
	locked_hud = null


func _refresh_all():
	maker_ids = ""
	_refresh_makers()
	_refresh_list()
	_refresh_detail()
	call_deferred("_place_menu")


func _clear_children(node):
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


func _refresh_makers():
	var local = _local_player()
	var found = _visible_players(local) if local != null else []
	var ids = ""
	for p in found:
		ids += str(p[0]) + ","
	if ids == maker_ids:
		return
	maker_ids = ids
	_clear_children(maker_box)
	if found.empty():
		maker_box.add_child(_small_label("(nobody in view)"))
	for p in found:
		var nm = _clean_name(_name_of(p[0]))
		var b = Button.new()
		b.text = (nm if nm != "" else "Player") + (" (me)" if p[0] == _my_id() else "")
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.connect("pressed", self, "_on_make", [p[0]])
		_glass_button(b)
		maker_box.add_child(b)
	call_deferred("_place_menu")


func _on_make(id):
	var players = _players()
	if players.has(id):
		_make_plushie(players[id], id)


func _refresh_list():
	_clear_children(list_box)
	list_title.text = "Your plushies (" + str(collection.size()) + "/" + str(MAX_COLLECTION) + ")"
	if collection.empty():
		list_box.add_child(_small_label("(none yet)"))
	for rec in collection:
		var b = Button.new()
		var nm = rec["name"] if rec["name"] != "" else "Plushie"
		b.text = nm + ("  *" if _is_out(rec) else "")
		b.focus_mode = Control.FOCUS_NONE
		b.clip_text = true
		b.connect("pressed", self, "_on_select", [rec["id"]])
		_glass_button(b)
		if rec["id"] == selected:
			b.add_stylebox_override("normal", _glass(Color(0.3, 1.0, 1.0, 0.45), Color(0.8, 1.0, 1.0, 0.9), 8, 0))
		list_box.add_child(b)


func _refresh_detail():
	var any_out = false
	for k in entries.keys():
		if entries[k]["owner"] == _my_id():
			any_out = true
	all_away_button.disabled = not any_out
	var rec = _record(selected)
	detail.visible = rec != null
	if rec == null:
		return
	updating_ui = true
	name_field.text = rec["name"]
	size_slider.value = rec["size"]
	size_label.text = "%d%%" % int(round(rec["size"] / DEFAULT_SIZE * 100.0))
	updating_ui = false
	for id in pose_buttons.keys():
		var b = pose_buttons[id]
		if id == rec["pose"]:
			b.add_stylebox_override("normal", _glass(Color(0.3, 1.0, 1.0, 0.45), Color(0.8, 1.0, 1.0, 0.9), 8, 0))
		else:
			_glass_button(b)
	put_button.text = "Move here" if _is_out(rec) else "Put out"
	var out_key = str(_my_id()) + ":" + rec["id"]
	updating_ui = true
	turn_slider.editable = entries.has(out_key)
	var deg = fposmod(rad2deg(entries[out_key]["yaw"]), 360.0) if entries.has(out_key) else 0.0
	turn_slider.value = round(deg / 5.0) * 5.0
	turn_label.text = str(int(turn_slider.value)) + "\u00b0" if entries.has(out_key) else "-"
	grab_button.disabled = not entries.has(out_key)
	for pair in [[lift_slider, "lift"]]:
		pair[0].editable = entries.has(out_key)
		pair[0].value = float(rec.get(pair[1], 0.0)) if entries.has(out_key) else 0.0
		move_labels[pair[0]].text = ("%+.2f m" % float(rec.get(pair[1], 0.0))) if entries.has(out_key) else "-"
	updating_ui = false


func _on_select(id):
	_on_name_done()
	selected = id
	_refresh_list()
	_refresh_detail()
	call_deferred("_place_menu")


func _on_name_entered(text):
	_on_name_done()
	name_field.release_focus()


func _on_name_done():
	var rec = _record(selected)
	if rec == null or updating_ui:
		return
	var nm = _clean_name(name_field.text)
	if nm == rec["name"]:
		return
	rec["name"] = nm
	_changed(rec)
	_refresh_list()


# something about a plushie that is out changed: show it and tell the others
func _changed(rec):
	_save_config()
	var key = str(_my_id()) + ":" + rec["id"]
	if entries.has(key):
		var e = entries[key]
		e["rec"] = rec
		sync_dirty = true


func _on_size_changed(value):
	if updating_ui:
		return
	var rec = _record(selected)
	if rec == null:
		return
	rec["size"] = clamp(float(value), Plush.MIN_SIZE, Plush.MAX_SIZE)
	size_label.text = "%d%%" % int(round(rec["size"] / DEFAULT_SIZE * 100.0))
	var key = str(_my_id()) + ":" + rec["id"]
	if entries.has(key):
		var e = entries[key]
		e["rec"] = rec
		if is_instance_valid(e["node"]):
			e["node"].size = rec["size"]
			e["node"].scale = Vector3.ONE * rec["size"]
			e["node"].place(_spot(e), e["yaw"])
		sync_dirty = true
	_save_config()


# turns a plushie that is out, about where it stands
func _on_turn_changed(value):
	if updating_ui:
		return
	var rec = _record(selected)
	if rec == null:
		return
	var key = str(_my_id()) + ":" + rec["id"]
	if entries.has(key):
		entries[key]["yaw"] = deg2rad(float(value))
		sync_dirty = true
	turn_label.text = str(int(value)) + "\u00b0"


# lifts a plushie that is out (negative goes down into the ground)
func _on_lift_changed(value):
	_move(lift_slider, "lift", value)


func _move(slider, key, value):
	if updating_ui:
		return
	var rec = _record(selected)
	if rec == null:
		return
	rec[key] = clamp(float(value), -MAX_LIFT, MAX_LIFT)
	move_labels[slider].text = "%+.2f m" % rec[key]
	_changed(rec)


func _on_pose(id):
	var rec = _record(selected)
	if rec == null:
		return
	rec["pose"] = id
	var key = str(_my_id()) + ":" + rec["id"]
	if entries.has(key) and is_instance_valid(entries[key]["node"]):
		entries[key]["node"].set_pose(id)
	_changed(rec)
	_refresh_detail()


func _on_put():
	var rec = _record(selected)
	if rec != null:
		_put_out(rec)


func _on_away():
	var rec = _record(selected)
	if rec != null:
		_put_away(rec)


func _on_all_away():
	for key in entries.keys():
		if entries[key]["owner"] == _my_id():
			_remove_entry(key)
	_refresh_all()


func _on_delete():
	var rec = _record(selected)
	if rec == null:
		return
	_put_away(rec)
	collection.erase(rec)
	selected = collection[0]["id"] if not collection.empty() else ""
	_save_config()
	_refresh_all()


func _toast(text):
	toast.text = text
	toast.rect_size = Vector2()
	toast_until = clock + 3.0


# --- helpers ---

func _load_wav(path):
	var file = File.new()
	if file.open(path, File.READ) != OK:
		return null
	var bytes = file.get_buffer(file.get_len())
	file.close()
	if bytes.size() < 44:
		return null
	var rate = bytes[24] | (bytes[25] << 8) | (bytes[26] << 16) | (bytes[27] << 24)
	var channels = bytes[22] | (bytes[23] << 8)
	var i = 12
	while i + 8 <= bytes.size():
		var id = bytes.subarray(i, i + 3).get_string_from_ascii()
		var size = bytes[i + 4] | (bytes[i + 5] << 8) | (bytes[i + 6] << 16) | (bytes[i + 7] << 24)
		if id == "data":
			var sample = AudioStreamSample.new()
			sample.format = AudioStreamSample.FORMAT_16_BITS
			sample.mix_rate = rate
			sample.stereo = channels == 2
			sample.data = bytes.subarray(i + 8, min(i + 8 + size, bytes.size()) - 1)
			return sample
		i += 8 + size + (size % 2)
	return null


func _add_tooltip(control, header, body):
	var scene = load("res://Scenes/Singletons/Tooltips/tooltip_node.tscn") if ResourceLoader.exists("res://Scenes/Singletons/Tooltips/tooltip_node.tscn") else null
	if scene == null or get_node_or_null("/root/Tooltip") == null:
		control.hint_tooltip = header
		return
	var tip = scene.instance()
	tip.header = "[color=#6a4420]" + header + "[/color]"
	tip.body = body
	tip.mouse_filter = Control.MOUSE_FILTER_PASS
	control.add_child(tip)


func _glass(fill, edge, radius, shadow):
	var box = StyleBoxFlat.new()
	box.bg_color = fill
	box.border_color = edge
	box.set_border_width_all(1)
	box.set_corner_radius_all(radius)
	box.shadow_color = Color(0, 0, 0, 0.3)
	box.shadow_size = shadow
	box.content_margin_left = 8
	box.content_margin_right = 8
	box.content_margin_top = 3
	box.content_margin_bottom = 3
	return box


func _glass_button(button):
	var edge = Color(0.55, 1.0, 1.0, 0.5)
	button.add_stylebox_override("normal", _glass(Color(0.2, 0.9, 0.95, 0.16), edge, 8, 0))
	button.add_stylebox_override("hover", _glass(Color(0.3, 1.0, 1.0, 0.30), Color(0.8, 1.0, 1.0, 0.8), 8, 0))
	button.add_stylebox_override("pressed", _glass(Color(0.3, 1.0, 1.0, 0.45), Color(0.8, 1.0, 1.0, 0.9), 8, 0))
	button.add_stylebox_override("disabled", _glass(Color(0.5, 0.5, 0.5, 0.12), Color(0.7, 0.7, 0.7, 0.25), 8, 0))
	button.add_stylebox_override("focus", StyleBoxEmpty.new())
	button.add_color_override("font_color", Color(1, 1, 1))
	button.add_color_override("font_color_hover", Color(1, 1, 1))
	button.add_color_override("font_color_pressed", Color(1, 1, 1))
	button.add_color_override("font_color_disabled", Color(1, 1, 1, 0.4))
