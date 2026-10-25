extends Area

# The spot on a plushie the game's own "interact" key finds: walking up to one shows the game's usual
# prompt, and pressing it asks the Plushie mod to start a hug.

var text = "Hug plushie"
var plush = null
var mod = null


func _ready():
	add_to_group("interactable")


func _activate(actor):
	if mod != null and is_instance_valid(mod) and plush != null and is_instance_valid(plush):
		mod._on_plush_activated(plush, actor)
