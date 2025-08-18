extends Node3D
@export var target_path: NodePath = ^"../Kart"
@export var smooth: float = 6.0
var target: Node3D
var _offset: Vector3

func _ready() -> void:
	target = get_node_or_null(target_path)
	if target == null:
		push_error("CameraRig: target not found"); set_process(false); return
	_offset = global_position - target.global_position
	var cam: Camera3D = get_node_or_null("Camera3D")
	if cam: cam.make_current()

func _process(delta: float) -> void:
	var a := _exp_smooth(smooth, delta)
	var desired := target.global_position + _offset
	global_position = global_position.lerp(desired, a)

func _exp_smooth(speed: float, dt: float) -> float:
	return 1.0 if speed <= 0.0 else 1.0 - exp(-speed * dt)
