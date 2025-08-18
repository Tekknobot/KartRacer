extends Node3D

@export var target_path: NodePath = ^"../Kart"
@export var height := 20.0
@export var distance := 15.0
@export var tilt_degrees := 60.0
@export var smooth := 6.0

var target: Node3D

func _ready() -> void:
	target = get_node_or_null(target_path)
	if target == null:
		push_error("CameraRig: target not found at %s" % [target_path])
		return

	# Set initial camera tilt
	$SpringArm3D.spring_length = distance
	$SpringArm3D/Camera3D.rotation_degrees.x = -tilt_degrees
	$SpringArm3D/Camera3D.make_current()

func _process(delta: float) -> void:
	if target == null: return

	var yaw := target.rotation.y
	var back := -Vector3.FORWARD.rotated(Vector3.UP, yaw)
	var desired := target.global_transform.origin + back * distance
	desired.y = target.global_transform.origin.y + height

	global_position = global_position.lerp(desired, 1.0 - pow(0.001, smooth * delta))

	var to_target := (target.global_transform.origin - global_position).normalized()
	var desired_basis := Basis.looking_at(to_target, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(desired_basis, 1.0 - pow(0.001, smooth * delta))
