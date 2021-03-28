extends Node

#internal vars
var fading_out : bool = false
var fading_in : bool = false
var muted_tracks = []

#external properties
export(int) var tempo
export(int) var bars
export(int) var beats_in_bar
export(float) var transition_beats # transition in seconds?
export(bool) var auto_transition # toggle to activate auto_signal_node logic
export(NodePath) var auto_signal_node # the controller node, which can trigger this Song; use the set transition type
export(String) var auto_signal # the auto signal nodes's signal we should listen to
export(String, "Beat", "Bar") var transition_type
export(String) var bus = "Music" # set same bus as for MDM, oder define different one

# Auto Transition:
# * auto_transition and the rest auto_signal* stuff needs to be defined, before this node is ready
func _ready():
	if auto_transition:
		var sig_node = get_node(auto_signal_node)
		sig_node.connect(auto_signal, self, "_transition", [transition_type])
	
	# if specified bus does not exist, throw error and abort
	var busnum = AudioServer.get_bus_index(bus)
	if busnum < 0:
		print("bus %s is undefined" % bus)
		return

	for container in get_children():
		for track in container.get_children():
			track.set_bus(bus)


# start this Song by given transition type
func _transition(type):
	match type:
		"Beat":
			get_parent().queue_beat_transition(name)
		"Bar":
			get_parent().queue_bar_transition(name)


# return first core container (needs to be an immediate child)
func _get_core():
	for i in get_children():
		if i.cont == "core":
			return i
