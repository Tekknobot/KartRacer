extends Node

# Analog stick actions for left stick
const GP_LEFT  := &"gp_left"
const GP_RIGHT := &"gp_right"
const GP_UP    := &"gp_up"
const GP_DOWN  := &"gp_down"

@export var device_id: int = 0

func _ready() -> void:
	for name in [GP_LEFT, GP_RIGHT, GP_UP, GP_DOWN]:
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		for ev in InputMap.action_get_events(name):
			InputMap.action_erase_event(name, ev)

	var e_left  := InputEventJoypadMotion.new()
	e_left.device = device_id;  e_left.axis = JOY_AXIS_LEFT_X; e_left.axis_value = -1.0
	var e_right := InputEventJoypadMotion.new()
	e_right.device = device_id; e_right.axis = JOY_AXIS_LEFT_X; e_right.axis_value =  1.0
	var e_up    := InputEventJoypadMotion.new()
	e_up.device = device_id;    e_up.axis    = JOY_AXIS_LEFT_Y; e_up.axis_value    = -1.0
	var e_down  := InputEventJoypadMotion.new()
	e_down.device = device_id;  e_down.axis  = JOY_AXIS_LEFT_Y; e_down.axis_value  =  1.0

	InputMap.action_add_event(GP_LEFT,  e_left)
	InputMap.action_add_event(GP_RIGHT, e_right)
	InputMap.action_add_event(GP_UP,    e_up)
	InputMap.action_add_event(GP_DOWN,  e_down)

	print("InputSetup ready (left stick bound).")
