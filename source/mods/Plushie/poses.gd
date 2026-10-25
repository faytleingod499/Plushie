extends Reference

# The poses a plushie can be put in.
#
# A pose turns the bones of the player's own skeleton. Every bone entry is [x, y, z] in degrees, turned about
# that bone's own joint, using the model's axes: x = the plushie's left, y = up, z = forward (the way it
# faces). Children follow their parent. For the arms and legs a plain name ("arm") means both sides: the
# right side is the mirror image of the left one. "arm.l" / "arm.r" set one side only (they win over "arm").
# "move" shifts the pelvis (and so the whole body) in model units, "tail" is the tail's tilt, and
# "wave" makes one hand wave (animated in plush.gd).

const ORDER = ["sit", "stand", "slump", "hugme", "wave", "cheer", "back", "belly", "sleep"]

# Arms are given as directions to point the upper arm ("arm") and the forearm ("elbow") in, because the
# game's resting arms are not symmetrical. Legs, torso, head and pelvis are given as turns in degrees.
const POSES = {
	# sitting upright, legs out in front, hands in its lap
	"sit": {
		"label": "Sit",
		"bones": {
			"leg": [-88, 8, 0], "foot": [8, 0, 0],
			"arm": Vector3(0.25, -1, 0.2), "elbow": Vector3(-0.1, -0.45, 1.0),
		},
	},
	# standing, arms down at its sides
	"stand": {
		"label": "Stand",
		"bones": {
			"arm": Vector3(0.3, -1, 0.1), "elbow": Vector3(0.12, -1, 0.25),
		},
	},
	# sitting, slumped forward, head down, arms limp
	"slump": {
		"label": "Slump",
		"bones": {
			"torso": [25, 0, 0], "head": [25, 0, 0],
			"leg": [-88, 10, 0], "foot": [8, 0, 0],
			"arm": Vector3(0.3, -1, 0.3), "elbow": Vector3(0.1, -1, 0.4),
		},
	},
	# sitting with both arms held out: "hug me"
	"hugme": {
		"label": "Hug me",
		"bones": {
			"leg": [-88, 8, 0], "foot": [8, 0, 0],
			"arm": Vector3(0.7, 0.05, 0.7), "elbow": Vector3(0.45, 0.1, 0.9),
		},
	},
	# sitting, one hand up, waving
	"wave": {
		"label": "Wave",
		"wave": "elbow.r",
		"bones": {
			"leg": [-88, 8, 0], "foot": [8, 0, 0],
			"arm.l": Vector3(0.25, -1, 0.2), "elbow.l": Vector3(-0.1, -0.45, 1.0),
			"arm.r": Vector3(-0.85, 0.5, 0.1), "elbow.r": Vector3(-0.35, 1.0, 0.1),
			"head": [0, 0, -6],
		},
	},
	# standing with both arms up
	"cheer": {
		"label": "Hands up",
		"bones": {
			"arm": Vector3(1.0, 0.35, 0.1), "elbow": Vector3(0.7, 0.9, 0.1),
			"head": [-10, 0, 0],
		},
	},
	# lying on its back, looking up
	"back": {
		"label": "Lie on back",
		"bones": {
			"pelvis": [-90, 0, 0],
			"head": [63, 0, 0],
			"leg": [0, 12, 0],
			"arm": Vector3(0.9, 0, 0.45), "elbow": Vector3(0.9, 0, 0.2),
		},
	},
	# lying on its tummy, arms out
	"belly": {
		"label": "Lie on tummy",
		"bones": {
			"pelvis": [90, 0, 0],
			"head": [-52, 0, 0],
			"leg": [0, 12, 0],
			"arm": Vector3(0.9, 0, 0.3), "elbow": Vector3(1.0, 0, 0.2),
		},
	},
	# curled up on its side, asleep
	"sleep": {
		"label": "Sleep",
		"bones": {
			"pelvis": [0, 0, 90],
			"leg": [-60, 0, 0], "foot": [40, 0, 0],
			"arm": Vector3(0.1, -0.4, 1.0), "elbow": Vector3(-0.4, -0.2, 1.0),
			"head": [0, 0, -35],
		},
	},
}


static func has(id):
	return POSES.has(id)


static func label(id):
	return POSES[id]["label"] if POSES.has(id) else id


# the three angles for one bone in a pose, or null when the pose leaves it alone
static func angles(pose_id, bone_name):
	if not POSES.has(pose_id):
		return null
	var bones = POSES[pose_id]["bones"]
	if bones.has(bone_name):
		return bones[bone_name]
	var side = ""
	var base = bone_name
	if bone_name.ends_with(".l") or bone_name.ends_with(".r"):
		side = bone_name.right(bone_name.length() - 1)
		base = bone_name.left(bone_name.length() - 2)
	if side != "" and bones.has(base):
		var a = bones[base]
		if side == "r":
			if typeof(a) == TYPE_VECTOR3:
				return Vector3(-a.x, a.y, a.z)   # the mirror image
			return [a[0], -a[1], -a[2]]
		return a
	return null
