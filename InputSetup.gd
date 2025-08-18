extends Node

# Analog/D-pad actions used by your movement code
const GP_LEFT  := &"gp_left"
const GP_RIGHT := &"gp_right"
const GP_UP    := &"gp_up"
const GP_DOWN  := &"gp_down"

# SNES-style kart actions
const ACT_ACCEL := &"kart_accel"
const ACT_BRAKE := &"kart_brake"
const ACT_HOP   := &"kart_hop"

@export var device_id: int = 0  # set to the gamepad index you want to target

func _ready() -> void:
	# (1) Ensure actions exist and are empty
	for name in [GP_LEFT, GP_RIGHT, GP_UP, GP_DOWN, ACT_ACCEL, ACT_BRAKE, ACT_HOP]:
		if not InputMap.has_action(name):
			InputMap.add_action(name)
		for ev in InputMap.action_get_events(name):
			InputMap.action_erase_event(name, ev)

	# (2) Left stick (analog)
	_add_axis(GP_LEFT,  JOY_AXIS_LEFT_X, -1.0)
	_add_axis(GP_RIGHT, JOY_AXIS_LEFT_X,  1.0)
	_add_axis(GP_UP,    JOY_AXIS_LEFT_Y, -1.0)
	_add_axis(GP_DOWN,  JOY_AXIS_LEFT_Y,  1.0)

	# (3) D-pad (digital buttons)
	_add_button(GP_LEFT,  JOY_BUTTON_DPAD_LEFT)
	_add_button(GP_RIGHT, JOY_BUTTON_DPAD_RIGHT)
	_add_button(GP_UP,    JOY_BUTTON_DPAD_UP)
	_add_button(GP_DOWN,  JOY_BUTTON_DPAD_DOWN)

	# (4) Keyboard fallbacks (arrow keys)
	_add_key(GP_LEFT,  KEY_LEFT)
	_add_key(GP_RIGHT, KEY_RIGHT)
	_add_key(GP_UP,    KEY_UP)
	_add_key(GP_DOWN,  KEY_DOWN)

	# (5) SNES-style driving:
	# Accelerate = B (South) + W/Up
	_add_button(ACT_ACCEL, JOY_BUTTON_A)
	_add_key(ACT_ACCEL, KEY_W)
	_add_key(ACT_ACCEL, KEY_UP)

	# Brake/Reverse = A (East) + S/Down
	_add_button(ACT_BRAKE, JOY_BUTTON_X)
	_add_key(ACT_BRAKE, KEY_S)
	_add_key(ACT_BRAKE, KEY_DOWN)

	# Hop/Drift = L or R shoulder + Space
	_add_button(ACT_HOP, JOY_BUTTON_LEFT_SHOULDER)
	_add_button(ACT_HOP, JOY_BUTTON_RIGHT_SHOULDER)
	_add_key(ACT_HOP, KEY_SPACE)

	print("InputSetup ready: left stick + D-pad + SNES controls bound (device_id=%d)." % device_id)

# ---------- helpers ----------
func _add_axis(action: StringName, axis: int, value: float) -> void:
	var e := InputEventJoypadMotion.new()
	e.device = device_id
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)

func _add_button(action: StringName, button_index: int) -> void:
	var e := InputEventJoypadButton.new()
	e.device = device_id
	e.button_index = button_index
	InputMap.action_add_event(action, e)

func _add_key(action: StringName, keycode: int) -> void:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	InputMap.action_add_event(action, e)
