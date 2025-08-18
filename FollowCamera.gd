# FollowCamera.gd  (attach to Camera3D)
extends Camera3D

@export var target_path: NodePath        # leave empty if you want auto-find
@export var height := 22.0               # how high above the kart
@export var distance := 18.0             # how far behind
@export var tilt_degrees := 60.0         # camera tilt downwards
@export var smooth := 8.0                # follow smoothing

var target: Node3D

func _ready() -> void:
	# 1) Pick a target
	target = get_node_or_null(target_path)
	if target == null:
		# Auto-find a node named "Kart" anywhere in the scene
		target = get_tree().get_root().find_child("Kart", true, false)
	if target == null:
		push_error("FollowCamera: couldn't find target. Set target_path or name your kart 'Kart'.")
	# 2) Become the active camera
	make_current()
	# 3) Apply tilt now so you see something even before follow kicks in
	rotation_degrees.x = -tilt_degrees

func _process(delta: float) -> void:
	if target == null:
		return

	# Compute a point behind the kart based on its yaw
	var yaw := target.rotation.y
	var back := -Vector3.FORWARD.rotated(Vector3.UP, yaw)

	var desired := target.global_transform.origin + back * distance
	desired.y = target.global_transform.origin.y + height

	# Smoothly move & aim
	global_position = global_position.lerp(desired, 1.0 - pow(0.001, smooth * delta))

	var to_target := (target.global_transform.origin - global_position).normalized()
	var desired_basis := Basis.looking_at(to_target, Vector3.UP)
	global_transform.basis = global_transform.basis.slerp(desired_basis, 1.0 - pow(0.001, smooth * delta))
