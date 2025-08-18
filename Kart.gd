extends CharacterBody3D

@export var max_speed := 26.0
@export var acceleration := 40.0
@export var brake_power := 48.0
@export var friction := 14.0
@export var steer_sensitivity := 2.3
@export var steer_at_zero_factor := 0.45

var speed := 0.0
var yaw := 0.0
var steer_smooth := 0.0

@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D

func _ready() -> void:
	# Make sure we start visible and “straight”
	if sprite:
		if sprite.has_method("play"):
			sprite.play("turn_right")
			sprite.frame = 0
			sprite.pause()
		# Make the sprite reasonably sized if it’s tiny/huge
		if sprite.has_method("set_pixel_size"):
			sprite.pixel_size = 0.03
			
	autosize_sprite_to_pixels(96)		

func _physics_process(delta: float) -> void:
	var fwd_in := Input.get_action_strength("accelerate")
	var brk_in := Input.get_action_strength("brake")
	var steer_raw := Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")

	# Forward/back
	if fwd_in > 0.0:
		speed += acceleration * fwd_in * delta
	elif brk_in > 0.0:
		speed -= brake_power * brk_in * delta
	else:
		speed = move_toward(speed, 0.0, friction * delta)
	speed = clamp(speed, -max_speed * 0.35, max_speed)

	# Yaw
	var speed_factor = clamp(abs(speed) / max_speed, 0.0, 1.0)
	var steer_power = lerp(steer_at_zero_factor, 1.0, speed_factor)
	yaw += steer_raw * steer_sensitivity * steer_power * delta

	# Move along heading (XZ)
	var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
	velocity = fwd * speed
	move_and_slide()

	_update_sprite(delta, steer_raw)
	_billboard_sprite_to_camera()

func _update_sprite(delta: float, steer_raw: float) -> void:
	if sprite == null: return
	steer_smooth = lerp(steer_smooth, steer_raw, clamp(10.0 * delta, 0.0, 1.0))
	var turning = abs(steer_smooth) > 0.08 and abs(speed) > 0.5

	if turning:
		if sprite.animation != "turn_right" or !sprite.is_playing():
			sprite.play("turn_right")

		# Mirror for left
		if "flip_h" in sprite.get_property_list().map(func(p): return p.name):
			sprite.flip_h = (steer_smooth < 0.0)
		else:
			var s := sprite.scale
			s.x = -abs(s.x) if steer_smooth < 0.0 else abs(s.x)
			sprite.scale = s

		sprite.rotation_degrees.z = -steer_smooth * 10.0
		sprite.position.x = steer_smooth * 0.12
		sprite.speed_scale = 0.8 + 0.7 * clamp(abs(steer_smooth) + abs(speed) / max_speed, 0.0, 1.0)
	else:
		sprite.play("turn_right")
		sprite.frame = 0
		sprite.pause()
		sprite.rotation_degrees.z = 0.0
		sprite.position.x = 0.0
		sprite.speed_scale = 1.0

func _billboard_sprite_to_camera() -> void:
	# Make sprite face active camera (SNES-style billboarding)
	if sprite == null: return
	var cam := get_viewport().get_camera_3d()
	if cam:
		sprite.look_at(cam.global_transform.origin, Vector3.UP)

func autosize_sprite_to_pixels(desired_px: float = 96.0) -> void:
	if sprite == null:
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	# Use current frame height; fallback to 64 if unknown
	var frame_tex := sprite.sprite_frames.get_frame_texture(sprite.animation, 0)
	var tex_h = frame_tex.get_height() if frame_tex else 64.0

	var d := (cam.global_transform.origin - sprite.global_transform.origin).length()
	var fov_rad := deg_to_rad(cam.fov)
	var viewport_h := float(get_viewport().get_visible_rect().size.y)

	# screen_px ≈ world_h / (2*d*tan(fov/2)) * viewport_h
	# world_h = tex_h * pixel_size  => solve for pixel_size
	var pixel_size = (desired_px * 2.0 * d * tan(fov_rad * 0.5)) / (tex_h * viewport_h)
	sprite.pixel_size = max(0.001, pixel_size)
