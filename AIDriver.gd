extends Node
class_name AIDriver

@export var path: NodePath           # Path3D in the scene (the race line)
@export var look_ahead := 8.0        # meters ahead on the curve
@export var target_speed := 0.80     # % of that kart’s max_speed as cruise
@export var max_speed_boost := 1.10  # rubber-band: raise target when behind
@export var drift_enable := true
@export var drift_angle_thresh := 0.35  # radians (~20°)
@export var drift_min_speed := 0.35     # fraction of max_speed
@export var lane_offset := 0.0          # -1..+1 to stagger lanes (optional)

var _kart: Node = null
var _curve: Curve3D = null
var _len := 0.0
var _s := 0.0                 # progress (distance) along curve
var _drift_hold := 0.0
var _drift_max_hold := 0.9
var _last_pos := Vector3.ZERO

func _ready() -> void:
	_kart = get_parent()
	if _kart == null:
		push_error("AIDriver: parent must be the kart Node3D.")
		set_physics_process(false)
		return
	_kart.external_input = true
	_last_pos = _kart.global_transform.origin

	# Resolve the Path3D safely
	var node := get_node_or_null(path)
	var p := node as Path3D
	if p == null:
		push_error("AIDriver: 'path' is not assigned or does not point to a Path3D. Set it in the Inspector or from RaceManager.")
		set_physics_process(false)
		return

	# Ensure the curve exists and has points
	_curve = p.curve
	if _curve == null or _curve.get_point_count() < 2:
		push_error("AIDriver: Path3D.curve is null or has < 2 points.")
		set_physics_process(false)
		return

	_len = _curve.get_baked_length()
	if _len <= 0.0:
		push_error("AIDriver: curve baked length is 0. Add points or increase curve detail.")
		set_physics_process(false)
		return

	# Start at the closest baked position along the path to the kart
	_s = _closest_offset_baked(_kart.global_transform.origin)

func _closest_offset_baked(world_pos: Vector3, samples: int = 256) -> float:
	var best_s := 0.0
	var best_d2 := INF
	var L := _curve.get_baked_length()
	if L <= 0.0:
		return 0.0
	for i in range(samples + 1):
		var s := (L * float(i)) / float(samples)
		var p := _curve.sample_baked(s)
		var d2 := p.distance_squared_to(world_pos)
		if d2 < best_d2:
			best_d2 = d2
			best_s = s
	return best_s

func _physics_process(dt: float) -> void:
	if _curve == null or _len <= 0.0: return

	# Estimate progress by distance traveled along path direction
	var pos = _kart.global_transform.origin
	var v_dir = (pos - _last_pos)
	_last_pos = pos

	# Advance along curve by forward speed projection
	var spd = (_kart.v) # already in world units/sec in your kart
	_s = fposmod(_s + spd * dt, _len)

	# Sample look-ahead target
	var ahead_s := fposmod(_s + look_ahead, _len)
	var target := _curve.sample_baked(ahead_s)

	# Optional lane offset (use path’s local right)
	if abs(lane_offset) > 0.001:
		var here := _curve.sample_baked(_s)
		# approximate tangent for a side offset
		var next := _curve.sample_baked(fposmod(_s + 0.5, _len))
		var fwd := (next - here); fwd.y = 0.0
		if fwd.length() > 0.0001:
			fwd = fwd.normalized()
			var right := Vector3(fwd.z, 0.0, -fwd.x)
			target += right * lane_offset * 1.2

	# Compute steering toward target on XZ plane
	var fwd3 = -_kart.transform.basis.z
	var fwd := Vector3(fwd3.x, 0.0, fwd3.z).normalized()
	var to = (target - pos); to.y = 0.0
	if to.length() < 0.001: to = fwd
	to = to.normalized()

	var dotv = clamp(fwd.dot(to), -1.0, 1.0)
	var crossy := fwd.cross(to).y
	var ang := atan2(crossy, dotv)  # +left / -right

	# Digital steer (match your kart: steer_raw = -1 left, +1 right)
	var want_left := ang > 0.03
	var want_right := ang < -0.03

	# Target speed with mild rubber-banding: if we’re turning hard, lower it a bit;
	# if we’re “behind” (slow), allow small boost
	var turn_penalty = clamp(abs(ang) * 0.6, 0.0, 0.25)
	var cruise = target_speed * (1.0 - turn_penalty)

	var speed_frac = clamp(_kart.v / _kart.max_speed, 0.0, 2.0)
	var want_boost = speed_frac < (cruise * 0.9)
	var cruise_final = cruise * (max_speed_boost if want_boost else 1.0)

	var press_accel = speed_frac < cruise_final
	var press_brake = (speed_frac > cruise_final + 0.15) and (abs(ang) < 0.1)

	# Drift logic (hold while cornering enough and fast enough)
	var press_drift := false
	if drift_enable:
		if abs(ang) > drift_angle_thresh and speed_frac > drift_min_speed:
			_drift_hold = min(_drift_hold + dt, _drift_max_hold)
			press_drift = true
		else:
			_drift_hold = max(_drift_hold - dt, 0.0)
			press_drift = _drift_hold > 0.08

	# Send to kart (digital)
	_kart.set_external_input_state(
		want_left and not want_right,
		want_right and not want_left,
		press_accel,
		press_brake,
		press_drift
	)
