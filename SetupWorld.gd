extends Node3D

func _ready() -> void:
	# Simple safety defaults so nothing starts inside the ground
	if has_node("Kart"):
		var kart := $"Kart"
		kart.global_position = Vector3(0, 0.8, 0)
	if has_node("Track/MeshInstance3D"):
		$"Track/MeshInstance3D".transform.origin = Vector3(0, 0, 0)
