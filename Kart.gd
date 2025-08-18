extends CharacterBody3D

@export var gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity") as float
@export var floor_snap_len: float = 0.6
@export var floor_max_angle_deg: float = 55
@export var safe_margin_value: float = 0.08
@export var move_speed: float = 10.0
@export var damping: float = 12.0
@export var stick_deadzone: float = 0.18

const GP_LEFT  := &"gp_left"
const GP_RIGHT := &"gp_right"
const GP_UP    := &"gp_up"
const GP_DOWN  := &"gp_down"

func _ready() -> void:
	motion_mode       = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction      = Vector3.UP
	floor_snap_length = floor_snap_len
	floor_max_angle   = deg_to_rad(floor_max_angle_deg)
	self.safe_margin  = safe_margin_value
	max_slides        = 6
	global_position.y += 0.05  # tiny lift so we don't start intersecting

func _physics_process(delta: float) -> void:
	# Read left stick (analog)
	var v: Vector2 = Input.get_vector(GP_LEFT, GP_RIGHT, GP_UP, GP_DOWN)

	# Extra deadzone shaping
	if v.length() < stick_deadzone:
		v = Vector2.ZERO
	else:
		v = v.normalized() * ((v.length() - stick_deadzone) / (1.0 - stick_deadzone))

	# Desired horizontal velocity (local X/Z)
	var desired_h: Vector3 = (global_transform.basis.x * v.x +
							  -global_transform.basis.z * v.y) * move_speed

	# Dampen to zero when stick is centered
	var horiz := velocity
	horiz.y = 0.0
	horiz = horiz.lerp(desired_h, 1.0 - exp(-damping * delta))

	# Gravity + strong ground stick
	var vy: float = velocity.y
	if is_on_floor():
		vy = min(vy, -2.0)  # tiny downward bias to keep snap
	else:
		vy -= gravity * delta

	velocity = Vector3(horiz.x, vy, horiz.z)
	move_and_slide()

	# Clean tiny upward jitter when grounded
	if is_on_floor() and velocity.y > 0.0:
		velocity.y = 0.0
