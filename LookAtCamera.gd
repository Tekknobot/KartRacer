extends AnimatedSprite3D

func _process(delta: float) -> void:
	if get_viewport().get_camera_3d():
		look_at(get_viewport().get_camera_3d().global_transform.origin, Vector3.UP)
