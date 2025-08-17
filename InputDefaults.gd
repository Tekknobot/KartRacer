extends Node

const DEFAULT_BINDINGS := {
	"accelerate":[KEY_W, KEY_UP],
	"brake":[KEY_S, KEY_DOWN],
	"left":[KEY_A, KEY_LEFT],
	"right":[KEY_D, KEY_RIGHT],
	"drift":[KEY_SPACE],
}

func _ready() -> void:
	for action in DEFAULT_BINDINGS.keys():
		_ensure_action(action, DEFAULT_BINDINGS[action])
	_add_gamepad_bindings()

func _ensure_action(name: String, keys: Array) -> void:
	if not InputMap.has_action(name):
		InputMap.add_action(name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		if not InputMap.action_has_event(name, ev):
			InputMap.action_add_event(name, ev)

func _add_gamepad_bindings() -> void:
	var ev_btn := InputEventJoypadButton.new()
	ev_btn.button_index = JOY_BUTTON_B
	if not InputMap.action_has_event("drift", ev_btn):
		InputMap.action_add_event("drift", ev_btn)

	var ev_rt := InputEventJoypadMotion.new()
	ev_rt.axis = JOY_AXIS_TRIGGER_RIGHT
	ev_rt.axis_value = 1.0
	if not InputMap.action_has_event("accelerate", ev_rt):
		InputMap.action_add_event("accelerate", ev_rt)

	var ev_lt := InputEventJoypadMotion.new()
	ev_lt.axis = JOY_AXIS_TRIGGER_LEFT
	ev_lt.axis_value = 1.0
	if not InputMap.action_has_event("brake", ev_lt):
		InputMap.action_add_event("brake", ev_lt)

	var ev_left := InputEventJoypadMotion.new()
	ev_left.axis = JOY_AXIS_LEFT_X
	ev_left.axis_value = -1.0
	if not InputMap.action_has_event("left", ev_left):
		InputMap.action_add_event("left", ev_left)

	var ev_right := InputEventJoypadMotion.new()
	ev_right.axis = JOY_AXIS_LEFT_X
	ev_right.axis_value = 1.0
	if not InputMap.action_has_event("right", ev_right):
		InputMap.action_add_event("right", ev_right)
