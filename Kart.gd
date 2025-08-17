extends Node3D
## Minimal SMK-flavored kart: accel, basic steer, hop→drift, tiny trails, spawn.
## Now tuned for ~SNES 150cc feel + subtle engine shake, with hop+drift integration.

# ---------- Tunables ----------
var accel := 205.0
var max_speed := 210.0
var drag := 6.0
var turn_rate := 2.10
var invert_steer := false
var invert_forward := false

# Steering feel
var steer_response := 32.0
var steer_return := 5.0
var max_steer := 1.0
var low_speed_turn_boost := 1.05
var high_speed_turn_scale := 0.32
var speed_curve_pow := 2.2
var lateral_grip := 15.0
var yaw_floor := 1.6

# Braking
var brake_strength := 280.0
var brake_extra_drag := 3.0

# ---- Camera / Sprite ----
@onready var cam: Camera3D = $KartCam
@onready var sprite: AnimatedSprite3D = $AnimatedSprite3D
var sprite_height := 0.6
var camera_push := 0.82
var cam_fov := 54.0
var cam_height_offset := 19.0
var use_fixed_size := true
var sprite_pixel_size := 0.0072
var use_billboard := true

# >>> Sprite turning animation controls (angle-driven)
var sprite_turn_anim := "turn_right"   # animation name in SpriteFrames
var turn_frames_regular := 3           # max frame for normal turning
var turn_frames_drift := 5             # max frame for full drift
var turn_smooth := 8.0                # smoothing toward target frame
var turn_flip_hysteresis := 0.25       # must pass near neutral before flipping sides
var drift_turn_bias := 1.35            # extra visual lean while drifting
# Angle→frame mapping (degrees at which we hit max frame)
var anim_max_angle_deg_regular := 20.0
var anim_max_angle_deg_drift := 35.0

# --- Steering/turn gating (new) ---
var steer_requires_accel := true       # turning only allowed while accelerating
var accel_turn_gate := 0.05            # throttle threshold to count as "accelerating"

# --- Visual helpers to show turn frames on normal turns (new) ---
var anim_steer_to_deg := 22.0          # full steer ≈ this many degrees visually
var anim_yawrate_deg_gain := 12.0      # deg contributed per rad/s of yaw-rate

# -------------- Hop / Drift (SNES-like, no mini-turbo) --------------
var gravity := 980.0
var hop_force := 96.0
var hop_vy := 0.0
var hop_y := 0.0
var grounded := true
var drifting := false
var drift_dir := 0                     # -1 / +1
var drift_enter_delay := 0.03
var min_speed_for_drift := 18.0
var drift_threshold := 0.22
var drift_turn_gain := 2.00
var hopping := false
var drift_timer := 0.0

# >>> Drift/hop integration tunables
var air_turn_scale := 0.80
var air_brake_scale := 0.55
var land_speed_damp := 0.06
var drift_side_force := 18.0
var drift_speed_bleed := 0.92
var drift_exit_counter_steer := 0.24
# >>> New feel helpers
var drift_min_time := 0.18
var drift_yaw_bias := 0.90
var drift_grip_boost := 1.35
var drift_latch_steer := 0.18
var drift_land_snap := 0.35
var drift_air_keep := true
var drift_auto_steer := 0.35

# -------------- Trails (tiny & optional) --------------
var trail_enabled := true
var trail_width := 2.0
var trail_wheel_half := 6.0
var trail_lifetime := 0.35
var trail_min_segment := 0.12
var trail_height := -4.0
var trail_color := Color(0.08, 0.08, 0.10, 0.95)
var _trail_left_points := []
var _trail_right_points := []
var _trail_left_mesh := ImmediateMesh.new()
var _trail_right_mesh := ImmediateMesh.new()
var _trail_mat := StandardMaterial3D.new()
var _trail_left_node := MeshInstance3D.new()
var _trail_right_node := MeshInstance3D.new()

# -------------- Spawn (optional) --------------
@export var spawn_point: NodePath
@export var snap_to_floor := true
@export var floor_snap_distance := 200.0
@export var floor_offset_y := 0.5
@export var use_spawn_forward := true

# -------------- State --------------
var v := 0.0
var yaw := 0.0
var last_yaw := 0.0
var yaw_rate_smooth := 0.0
var yaw_smooth := 12.0
var yaw_deadzone := 0.010
var steer_smoothed := 0.0
var steer_deadzone := 0.05
var _base_y := 0.0
var _landed_this_frame := false

# >>> Sprite turn animation state
var _turn_frame := 0.0                 # current frame (continuous)
var _turn_side := 1                    # +1 = right, -1 = left
var _steer_vis := 0.0                  # cached steer for visuals
var _drift_vis := false                # cached drift flag

# >>> Angle-driven visuals state
var _prev_pos := Vector3.ZERO
var _vis_turn_angle := 0.0             # signed radians (+right / -left)

# -------------- Engine shake --------------
var engine_shake_enabled := true
var engine_shake_base := 0.011
var engine_shake_speed := 42.0
var engine_shake_steer_amp := 0.004
var engine_shake_fov_jitter := 0.0
var _engine_t := 0.0
var _cam_origin := Vector3.ZERO

# ---- sprite drift framing gates ----
var anim_right_is_default := true   # set to false if your art's base frames lean LEFT when not flipped
var sprite_side_swap := 1
var anim_frame_gain := 4         # nudges angles to reach higher frames easier
var drift_full_frame_gate_deg := 26.0  # need at least this slip angle (deg) to go past frame 4 while drifting
var ai_sprite_scale := 1.8   # try 1.8–2.4 for SNES-y readability

# regular (non-drift) turning gates
var turn_half_frame_gate_deg := 10.0   # < this → cap frames to 2
var turn_full_frame_gate_deg := 18.0   # < this → cap frames to 3 ; ≥ this → allow up to 4

# --- accel visual cache (new) ---
var _accel_on := false
var _throttle_vis := 0.0

# --- Discrete step & lookup tables (SNES-ish) ---
const FIXED_DT := 1.0 / 60.0
var _accum_dt := 0.0

# Speed fraction t = v / max_speed ∈ [0..1]  → table buckets 0..10
# Tables are tuned “arcade style”: bigger low-speed steering, tighter at high-speed,
# accel fades with speed, yaw cap tightens with speed.
var LUT_ACCEL := [205.0, 180.0, 160.0, 140.0, 120.0, 100.0, 80.0, 60.0, 45.0, 32.0, 20.0]
var LUT_STEER_GAIN := [1.10, 1.00, 0.92, 0.84, 0.75, 0.66, 0.58, 0.50, 0.43, 0.37, 0.32]
var LUT_YAW_CAP_DEG := [9.0, 8.5, 8.0, 7.5, 7.0, 6.5, 6.0, 5.5, 5.0, 4.6, 4.2] # per frame hard cap
var LUT_YAW_FLOOR_DEG := [2.6, 2.4, 2.2, 2.0, 1.8, 1.6, 1.4, 1.3, 1.2, 1.1, 1.0]

# Quantization steps (hard caps)
var Q_SPEED_STEP := 0.25       # speed quantization (units)
var Q_YAW_STEP_DEG := 0.25     # yaw step quantization (deg per frame)
var Q_SLIP_STEP := 0.05        # lateral slip step multiplier

# Digital input only (discrete reads)
var _btn_left := false
var _btn_right := false
var _btn_accel := false
var _btn_brake := false
var _btn_drift := false

# ---------- Audio (procedural) ----------
var eng_enabled := true
var eng_mix_rate := 44100.0
var eng_buffer_seconds := 0.08
var eng_base_pitch := 52.0          # Hz at idle-ish
var eng_max_pitch := 440.0          # Hz at max speed
var eng_idle_gain := 0.12
var eng_drive_gain := 0.35
var eng_harm2 := 0.40               # mix of 2nd harmonic
var eng_harm3 := 0.22               # mix of 3rd harmonic
var eng_noise := 0.08               # broadband noise bed
var eng_wobble := 0.35              # light FM wobble by yaw-rate

var drift_enabled := true
var drift_mix_rate := 44100.0
var drift_buffer_seconds := 0.06
var drift_base_pitch := 420.0       # Hz at tiny slip
var drift_max_pitch := 2600.0       # Hz at big slip
var drift_gain := 0.32
var drift_noise := 0.22             # hiss mixed into squeal
var drift_attack := 0.025
var drift_release := 0.085

# ---- Audio generators ----
var _eng_player: AudioStreamPlayer
var _eng_stream: AudioStreamGenerator
var _eng_pb: AudioStreamGeneratorPlayback
var _eng_phase := 0.0

var _drift_player: AudioStreamPlayer
var _drift_stream: AudioStreamGenerator
var _drift_pb: AudioStreamGeneratorPlayback
var _drift_phase := 0.0
var _drift_env := 0.0  # envelope for squeal (attack/release)
var _rng := RandomNumberGenerator.new()

# ---- Add near other state vars ----
var external_input := false
var _ext_left := false
var _ext_right := false
var _ext_accel := false
var _ext_brake := false
var _ext_drift := false

# --- AI sprite sizing ---
# 0 = fixed (always screen-sized), 1 = hybrid (near = perspective, far = fixed), 2 = perspective
var ai_sprite_mode := 1
var ai_pixel_size := 0.0115            # fixed-size pixel size for AI when fixed
var ai_hybrid_switch_dist := 36.0      # meters: beyond this, AI uses fixed-size
var ai_hybrid_hysteresis := 4.0        # meters: prevents flicker around the switch

var _ai_fixed_now := true             # runtime latch for hybrid switching

func set_external_input_state(left: bool, right: bool, accel: bool, brake: bool, drift: bool) -> void:
	_ext_left = left
	_ext_right = right
	_ext_accel = accel
	_ext_brake = brake
	_ext_drift = drift

# ============================ Lifecycle ============================
func _ready() -> void:
	_setup_camera_and_sprite()
	_setup_trails()
	_ensure_inputs()
	_place_at_spawn()
	_base_y = global_position.y
	_prev_pos = global_position
	_init_audio()  # <<< add this


func _process(dt: float) -> void:
	_update_sprite_pose()
	_update_engine_shake(dt)
	_update_trails(dt)
	_update_sprite_turn_anim(dt)
	_update_audio(dt)  # <<< add this
	if cam: cam.current = not external_input

func _init_audio() -> void:
	_rng.randomize()
	if eng_enabled:
		_eng_stream = AudioStreamGenerator.new()
		_eng_stream.mix_rate = eng_mix_rate
		_eng_stream.buffer_length = eng_buffer_seconds
		_eng_player = AudioStreamPlayer.new()
		_eng_player.stream = _eng_stream
		_eng_player.bus = "Master"
		add_child(_eng_player)
		_eng_player.play()
		_eng_pb = _eng_player.get_stream_playback()

	if drift_enabled:
		_drift_stream = AudioStreamGenerator.new()
		_drift_stream.mix_rate = drift_mix_rate
		_drift_stream.buffer_length = drift_buffer_seconds
		_drift_player = AudioStreamPlayer.new()
		_drift_player.stream = _drift_stream   # << fixed
		_drift_player.bus = "Master"
		add_child(_drift_player)
		_drift_player.play()
		_drift_pb = _drift_player.get_stream_playback()

func _update_audio(dt: float) -> void:
	if eng_enabled and _eng_pb:
		_engine_audio_fill(dt)
	if drift_enabled and _drift_pb:
		_drift_audio_fill(dt)

func _engine_audio_fill(dt: float) -> void:
	if _eng_pb == null: return
	var frames_to_push := _eng_pb.get_frames_available()   # << was _eng_stream
	if frames_to_push <= 0: return

	var rpm = clamp(v / max_speed, 0.0, 1.0)
	var throttle_amt := _throttle_vis
	var base_f = lerp(eng_base_pitch, eng_max_pitch, rpm)
	var wob = clamp(abs(yaw_rate_smooth) * eng_wobble, 0.0, 0.45)
	var f = base_f * (1.0 + wob * sin(_engine_t * 4.7))

	var g_idle := eng_idle_gain * (1.0 - throttle_amt)
	var g_drive := eng_drive_gain * (0.35 + 0.65 * throttle_amt)
	var g_noise = eng_noise * (0.25 + 0.75 * rpm)

	var sr := eng_mix_rate
	for i in range(frames_to_push):
		_eng_phase = fmod(_eng_phase + 2.0 * PI * f / sr, 2.0 * PI)
		var s1 := sin(_eng_phase)
		var s2 := sin(_eng_phase * 2.0)
		var s3 := sin(_eng_phase * 3.0)
		var tone := tanh((s1 + s2 * eng_harm2 + s3 * eng_harm3) * 0.9)
		var n := (_rng.randf() * 2.0 - 1.0)
		var out = clamp(tone * (g_idle + g_drive) + n * g_noise, -1.0, 1.0)
		_eng_pb.push_frame(Vector2(out, out))

func _drift_audio_fill(dt: float) -> void:
	if _drift_pb == null: return
	var frames_to_push := _drift_pb.get_frames_available()  # << was _drift_stream
	if frames_to_push <= 0: return

	var slip := 0.0
	if _drift_vis and grounded:
		var steer_mag = abs(_steer_vis)
		slip = clamp(steer_mag * (0.4 + 0.6 * (v / max_speed)), 0.0, 1.0)
		if _landed_this_frame:
			slip = max(slip, 0.65)

	var atk = max(drift_attack, 1.0 / drift_mix_rate)
	var rel = max(drift_release, 1.0 / drift_mix_rate)
	var target := slip
	var env_rate = (1.0 / atk) if target > _drift_env else (1.0 / rel)
	_drift_env = clamp(_drift_env + (target - _drift_env) * env_rate * (frames_to_push / drift_mix_rate), 0.0, 1.0)

	var f = lerp(drift_base_pitch, drift_max_pitch, _drift_env)
	var g := drift_gain * _drift_env
	var g_hiss := drift_noise * _drift_env

	var sr := drift_mix_rate
	for i in range(frames_to_push):
		_drift_phase = fmod(_drift_phase + 2.0 * PI * f / sr, 2.0 * PI)
		var fm := 0.012 * sin(_drift_phase * 0.5)
		var s := sin(_drift_phase + fm)
		var rect = abs(s) * 2.0 - 1.0
		var tone = 0.65 * s + 0.35 * rect
		var hiss := (_rng.randf() * 2.0 - 1.0)
		var out = clamp(tone * g + hiss * g_hiss, -1.0, 1.0)
		_drift_pb.push_frame(Vector2(out, out))

func _physics_process(dt: float) -> void:
	# Accumulate and tick at 60 Hz for discrete behavior
	_accum_dt += dt
	while _accum_dt >= FIXED_DT:
		_fixed_step(FIXED_DT)
		_accum_dt -= FIXED_DT

func _fixed_step(dt: float) -> void:
	# ------ Discrete input reads (digital only) ------
	if external_input:
		_btn_left  = _ext_left
		_btn_right = _ext_right
		_btn_accel = _ext_accel
		_btn_brake = _ext_brake
		_btn_drift = _ext_drift
	else:
		_btn_left  = Input.is_action_pressed("left")
		_btn_right = Input.is_action_pressed("right")
		_btn_accel = Input.is_action_pressed("accelerate")
		_btn_brake = Input.is_action_pressed("brake")
		_btn_drift = Input.is_action_pressed("drift")


	var steer_raw := 0.0
	if _btn_left and not _btn_right: steer_raw = -1.0
	elif _btn_right and not _btn_left: steer_raw = 1.0
	if invert_steer:
		steer_raw = -steer_raw

	var throttle := 1.0 if _btn_accel else 0.0
	var brake_amt := 1.0 if _btn_brake else 0.0

	# ------ Accel/turn gate ------
	_throttle_vis = throttle
	_accel_on = (_throttle_vis > accel_turn_gate)

	# ------ Speed fraction & lookup values ------
	var t_speed = clamp(v / max_speed, 0.0, 1.0)
	var accel_lut := _lut_sample(LUT_ACCEL, t_speed)
	var steer_gain := _lut_sample(LUT_STEER_GAIN, t_speed)

	# ------ Longitudinal (discrete + caps) ------
	var drag_eff := drag + (brake_extra_drag * brake_amt)
	if throttle > 0.0:
		# use table accel
		v += accel_lut * dt
	# drag & brake
	v = move_toward(v, 0.0, drag_eff * dt)
	if brake_amt > 0.0 and v > 0.0:
		var bscale: float = 1.0 if grounded else air_brake_scale
		v = move_toward(v, 0.0, brake_strength * brake_amt * bscale * dt)
	# hard cap & quantize speed
	v = clamp(v, 0.0, max_speed)
	v = _q(v, Q_SPEED_STEP)

	# ------ Drift enter/exit (kept, but uses discrete steer_now) ------
	_update_hop_and_drift(dt, _btn_drift, steer_raw, t_speed)

	# Optionally bias steer toward drift direction while drifting
	var steer_used := steer_raw
	if drifting and drift_auto_steer > 0.0:
		steer_used = clamp(lerp(steer_raw, float(drift_dir), drift_auto_steer), -1.0, 1.0)

	# Gate steering when not accelerating
	if steer_requires_accel and not _accel_on:
		steer_used = 0.0

	# ------ Yaw command (discrete, table-capped, quantized) ------
	var air_factor: float = 1.0 if grounded else air_turn_scale
	var yaw_cmd := steer_used * turn_rate * steer_gain * air_factor

	if drifting:
		yaw_cmd *= drift_turn_gain
		yaw_cmd += float(drift_dir) * drift_yaw_bias * t_speed

	# Convert LUT caps (deg/frame) → rad/s for this step
	var yaw_cap_deg := _lut_sample(LUT_YAW_CAP_DEG, t_speed)
	var yaw_floor_deg := _lut_sample(LUT_YAW_FLOOR_DEG, t_speed)
	var yaw_cap := _deg_to_rad(yaw_cap_deg) / dt
	var yaw_floor := _deg_to_rad(yaw_floor_deg) / dt

	# Apply floor behavior similar to your original yaw_floor idea
	var desired = clamp(yaw_cmd, -yaw_cap, yaw_cap)
	if abs(desired) < yaw_floor:
		desired = sign(desired) * yaw_floor if desired != 0.0 else 0.0

	# Quantize yaw command to step (deg/frame → rad/s)
	var desired_deg_per_frame = clamp(_rad_to_deg(desired) * dt, -yaw_cap_deg, yaw_cap_deg)
	desired_deg_per_frame = _q(desired_deg_per_frame, Q_YAW_STEP_DEG)
	var yaw_per_sec := _deg_to_rad(desired_deg_per_frame) / dt

	# Integrate yaw discretely
	yaw -= yaw_per_sec * dt
	rotation.y = yaw

	# Update yaw rate smoothed (still useful for visuals)
	var yaw_rate = (yaw - last_yaw) / max(dt, 0.000001)
	last_yaw = yaw
	yaw_rate_smooth = lerp(yaw_rate_smooth, yaw_rate, clamp(yaw_smooth * dt, 0.0, 1.0))

	# ------ Movement (discrete + quantized slip) ------
	var fwd := -transform.basis.z
	var flat := Vector3(fwd.x, 0.0, fwd.z).normalized()
	if invert_forward:
		flat = -flat
	var move := flat * v * dt

	if drifting and v > 0.1:
		var right_flat := Vector3(transform.basis.x.x, 0.0, transform.basis.x.z).normalized()
		if grounded:
			var slip_mag := drift_side_force * (v / max_speed) * dt
			# quantize slip for SNES-ish chunkiness
			slip_mag = _q(slip_mag, Q_SLIP_STEP)
			var slip := right_flat * float(drift_dir) * slip_mag
			move += slip
			v *= pow(drift_speed_bleed, dt)
		if _landed_this_frame:
			var snap_mag := drift_side_force * drift_land_snap * dt
			snap_mag = _q(snap_mag, Q_SLIP_STEP)
			move += right_flat * float(drift_dir) * snap_mag

	# Apply hop height to body, discretely
	global_position += move
	global_position.y = _base_y + hop_y
	_landed_this_frame = false

	# Cache for visuals (use the *discrete* steer_used)
	_steer_vis = steer_used
	_drift_vis = drifting

	# Angle for visuals (from discrete movement)
	var vel = (global_position - _prev_pos) / max(dt, 0.000001)
	_prev_pos = global_position
	var vel_flat := Vector3(vel.x, 0.0, vel.z)
	var fwd3 := -transform.basis.z
	var fwd_flat := Vector3(fwd3.x, 0.0, fwd3.z)
	var angle := 0.0
	if vel_flat.length() > 0.001 and fwd_flat.length() > 0.001:
		vel_flat = vel_flat.normalized()
		fwd_flat = fwd_flat.normalized()
		var dotv = clamp(fwd_flat.dot(vel_flat), -1.0, 1.0)
		var crossy := fwd_flat.cross(vel_flat).y
		angle = atan2(crossy, dotv)
	else:
		angle = 0.0
	_vis_turn_angle = angle

# ============================ Hop/Drift ============================
func _update_hop_and_drift(dt: float, drift_pressed: bool, steer_now: float, speed_factor: float) -> void:
	if Input.is_action_just_pressed("drift"):
		_start_hop()
		var spd = clamp(v / max_speed, 0.0, 1.0)
		hop_vy = hop_force * (0.75 + 0.25 * spd)
		if v >= min_speed_for_drift and abs(steer_now) >= drift_threshold:
			drift_dir = sign(steer_now)
			drifting = true
			drift_timer = 0.0
		else:
			drift_dir = 0

	if Input.is_action_just_released("drift"):
		if drift_timer >= drift_min_time:
			drifting = false
			drift_dir = 0
			drift_timer = 0.0

	if hopping:
		hop_vy -= gravity * dt
		hop_y += hop_vy * dt
		if hop_y <= 0.0:
			hop_y = 0.0
			hopping = false
			v *= (1.0 - land_speed_damp)
			_landed_this_frame = true
	grounded = (hop_y <= 0.001)

	if hopping:
		drift_timer += dt
		if not drifting and drift_timer >= drift_enter_delay and v >= min_speed_for_drift and abs(steer_now) >= drift_threshold:
			drifting = true
			drift_dir = sign(steer_now)
	else:
		if drift_pressed and not drifting and v >= min_speed_for_drift and abs(steer_now) >= drift_threshold:
			drifting = true
			drift_dir = sign(steer_now)

	if drifting:
		drift_timer += dt
		if drift_air_keep and not grounded:
			pass
		else:
			if abs(steer_now) < drift_latch_steer and drift_timer >= drift_min_time:
				drifting = false
				drift_dir = 0
				drift_timer = 0.0

	if drifting and drift_timer >= drift_min_time and sign(steer_now) == -drift_dir and abs(steer_now) >= drift_exit_counter_steer:
		drifting = false
		drift_dir = 0
		drift_timer = 0.0

func _start_hop() -> void:
	if hopping: return
	hopping = true
	hop_vy = hop_force

# ============================ Visuals ============================
func _update_sprite_pose() -> void:
	if not sprite: return

	var base := global_position + Vector3(0.0, sprite_height + hop_y, 0.0)
	sprite.global_position = base

	# Y-billboard only
	if "billboard" in sprite:
		sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y

	if external_input:
		# -------- AI sizing modes --------
		var mode := ai_sprite_mode
		var view_cam := get_viewport().get_camera_3d()
		if view_cam == null: view_cam = cam

		if mode == 0:
			# Always fixed on screen
			sprite.fixed_size = true
			sprite.pixel_size = ai_pixel_size
			sprite.scale = Vector3.ONE
		elif mode == 2:
			# Always perspective
			sprite.fixed_size = false
			sprite.scale = Vector3(ai_sprite_scale, ai_sprite_scale, ai_sprite_scale)
		else:
			# Hybrid (near = perspective, far = fixed)
			var dist := 1e9
			if view_cam != null:
				dist = (base - view_cam.global_transform.origin).length()

			if (not _ai_fixed_now) and (dist > (ai_hybrid_switch_dist + ai_hybrid_hysteresis)):
				_ai_fixed_now = true
			elif _ai_fixed_now and (dist < (ai_hybrid_switch_dist - ai_hybrid_hysteresis)):
				_ai_fixed_now = false

			if _ai_fixed_now:
				sprite.fixed_size = true
				sprite.pixel_size = ai_pixel_size
				sprite.scale = Vector3.ONE     # IMPORTANT: scale must be 1 in fixed-size mode
			else:
				sprite.fixed_size = false
				sprite.scale = Vector3(ai_sprite_scale, ai_sprite_scale, ai_sprite_scale)
	else:
		# -------- Player sprite --------
		sprite.fixed_size = use_fixed_size
		sprite.pixel_size = sprite_pixel_size
		sprite.scale = Vector3.ONE

# >>> Smooth left/right turn animation driving — ANGLE-BASED
func _update_sprite_turn_anim(dt: float) -> void:
	if not sprite: return
	if not sprite.sprite_frames: return
	if not sprite.sprite_frames.has_animation(sprite_turn_anim): return

	# manual control
	sprite.play(sprite_turn_anim)
	sprite.speed_scale = 0.0

	# use all frames that exist in the sheet
	var total_frames := sprite.sprite_frames.get_frame_count(sprite_turn_anim)
	if total_frames <= 0: return
	var total_idx := total_frames - 1

	var max_idx_reg = min(turn_frames_regular, total_idx)   # 0..4
	var max_idx_drift = min(turn_frames_drift, total_idx)   # 0..7

	# slip/turn angle → degrees (base)
	var ang_deg = abs(rad_to_deg(_vis_turn_angle))

	# blend in steer and yaw-rate so normal turns animate too
	var steer_deg = abs(_steer_vis) * anim_steer_to_deg
	var yaw_deg = abs(yaw_rate_smooth) * anim_yawrate_deg_gain
	ang_deg = max(ang_deg, steer_deg, yaw_deg)

	# drift visual boost + general frame gain
	if _drift_vis:
		ang_deg *= drift_turn_bias
	ang_deg *= anim_frame_gain

	# if turning requires accel and we aren't accelerating, neutralize visuals
	if steer_requires_accel and not _accel_on:
		ang_deg = 0.0

	# side (same logic for drift & non-drift): steer → drift_dir → slip angle
	var desired_side := 0
	if abs(_steer_vis) > 0.001:
		desired_side = sprite_side_swap * sign(_steer_vis)
	elif _drift_vis and drift_dir != 0:
		desired_side = sprite_side_swap * drift_dir
	elif abs(_vis_turn_angle) > 0.0005:
		desired_side = sprite_side_swap * sign(_vis_turn_angle)

	# gated targets
	var target_max_idx: float
	var max_deg := anim_max_angle_deg_regular

	if _drift_vis:
		if ang_deg < drift_full_frame_gate_deg:
			target_max_idx = float(min(4, total_idx))      # drifting but not “full” → 0..4
			max_deg = anim_max_angle_deg_regular
		else:
			target_max_idx = float(max_idx_drift)          # full drift → allow up to 7
			max_deg = anim_max_angle_deg_drift
	else:
		# regular (non-drift) turning tiers
		if ang_deg < turn_half_frame_gate_deg:
			target_max_idx = float(min(2, max_idx_reg))    # tiny angles → 0..2
		elif ang_deg < turn_full_frame_gate_deg:
			target_max_idx = float(min(3, max_idx_reg))    # medium angles → 0..3
		else:
			target_max_idx = float(max_idx_reg)            # big angles → 0..4
		max_deg = anim_max_angle_deg_regular

	# map angle→[0..1] with chosen clamp
	var ang_mag = clamp(ang_deg / max(max_deg, 0.001), 0.0, 1.0)

	# don’t snap sides: pass near neutral before flipping
	var target_frame_mag = ang_mag * target_max_idx
	if desired_side != 0 and desired_side != _turn_side:
		target_frame_mag = 0.0
		if _turn_frame <= turn_flip_hysteresis:
			_turn_side = desired_side

	# smooth toward target frame
	var rate = clamp(turn_smooth * dt, 0.0, 1.0)
	_turn_frame = lerp(_turn_frame, target_frame_mag, rate)

	# set integer frame
	var frame_idx := int(round(_turn_frame))
	frame_idx = clamp(frame_idx, 0, int(target_max_idx))
	
	sprite.frame = frame_idx

	# exact left/right mirror based on how your sheet is authored
	var want_right := (_turn_side == 1) # +1 = physically turning right
	var flip_for_left_when_default_right := (not want_right) if anim_right_is_default else want_right

	if "flip_h" in sprite:
		sprite.flip_h = flip_for_left_when_default_right
	else:
		var sx = abs(sprite.scale.x)
		sprite.scale.x = -sx if flip_for_left_when_default_right else sx

func _setup_camera_and_sprite() -> void:
	if cam:
		# Only the player kart owns an active camera
		cam.current = not external_input
		cam.transform.origin = Vector3(0, cam_height_offset, 64.0)
		_cam_origin = cam.transform.origin
		cam.look_at(global_position + Vector3(0, sprite_height, 0), Vector3.UP)
		cam.near = 0.016
		cam.far = 2000.0
		cam.fov = cam_fov
	if sprite:
		sprite.visible = true
		# Neutral init; final mode is chosen in _update_sprite_pose()
		sprite.fixed_size = false
		sprite.pixel_size = sprite_pixel_size
		sprite.scale = Vector3.ONE

		if "texture_filter" in sprite:
			sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

# ============================ Engine Shake ============================
func _update_engine_shake(dt: float) -> void:
	if not engine_shake_enabled: return
	if not (cam and sprite): return
	_engine_t += dt
	var rpm = clamp(v / max_speed, 0.0, 1.0)
	var amp = engine_shake_base * (0.35 + 1.65 * rpm)
	var sx := sin(_engine_t * engine_shake_speed)
	var sy := sin(_engine_t * (engine_shake_speed * 0.77) + 1.7)
	var steer_wag := steer_smoothed * engine_shake_steer_amp
	var offset := Vector3((sx + steer_wag) * amp, 0.0, sy * amp)
	sprite.global_position += offset
	var f_jit = engine_shake_fov_jitter * rpm
	if cam and cam.current:
		cam.fov = cam_fov + sx * f_jit
		var cam_off := Vector3(0.0, 0.0, 0.0)
		cam_off.x = 0.25 * amp * sy
		cam_off.y = 0.18 * amp * sx
		var c := cam.transform
		c.origin = _cam_origin + cam_off
		cam.transform = c

# ============================ Trails (tiny) ============================
func _setup_trails() -> void:
	if not trail_enabled: return
	_trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_trail_mat.vertex_color_use_as_albedo = true
	_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_trail_left_node.mesh = _trail_left_mesh
	_trail_right_node.mesh = _trail_right_mesh
	_trail_left_node.material_override = _trail_mat
	_trail_right_node.material_override = _trail_mat
	_trail_left_node.top_level = true
	_trail_right_node.top_level = true
	add_child(_trail_left_node)
	add_child(_trail_right_node)

func _update_trails(dt: float) -> void:
	if not trail_enabled: return
	for arr in [_trail_left_points, _trail_right_points]:
		var i := 0
		while i < arr.size():
			arr[i]["age"] += dt
			if arr[i]["age"] > trail_lifetime: arr.remove_at(i)
			else: i += 1
	if drifting and hop_y <= 0.001:
		var r := transform.basis.x
		var right_flat := Vector3(r.x, 0.0, r.z).normalized()
		if right_flat.length() < 0.0001: right_flat = Vector3(1,0,0)
		var base := Vector3(global_position.x, trail_height, global_position.z)
		_trail_try_add_point(_trail_left_points,  base - right_flat * trail_wheel_half)
		_trail_try_add_point(_trail_right_points, base + right_flat * trail_wheel_half)
	_rebuild_trail_mesh(_trail_left_points, _trail_left_mesh)
	_rebuild_trail_mesh(_trail_right_points, _trail_right_mesh)

func _trail_try_add_point(arr: Array, p: Vector3) -> void:
	var can_add := true
	if arr.size() > 0:
		var d := (arr.back()["p"] as Vector3).distance_to(p)
		if d < trail_min_segment: can_add = false
	if can_add: arr.push_back({"p": p, "age": 0.0})

func _rebuild_trail_mesh(arr: Array, mesh: ImmediateMesh) -> void:
	mesh.clear_surfaces()
	if arr.size() < 2:
		return
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP, _trail_mat)
	for i in range(arr.size()):
		var p: Vector3 = arr[i]["p"]
		var dir := Vector3.ZERO
		if i == 0:
			dir = arr[i + 1]["p"] - p
		elif i == arr.size() - 1:
			dir = p - arr[i - 1]["p"]
		else:
			dir = arr[i + 1]["p"] - arr[i - 1]["p"]
		dir.y = 0.0
		if dir.length() < 0.0001:
			dir = Vector3(0, 0, 1)
		else:
			dir = dir.normalized()
		var side := Vector3(-dir.z, 0.0, dir.x)
		var halfw := trail_width * 0.5
		var vL := p - side * halfw
		var vR := p + side * halfw
		var t = clamp(1.0 - (arr[i]["age"] / trail_lifetime), 0.0, 1.0)
		var col := Color(trail_color.r, trail_color.g, trail_color.b, trail_color.a * t)
		mesh.surface_set_color(col); mesh.surface_add_vertex(vL)
		mesh.surface_set_color(col); mesh.surface_add_vertex(vR)
	mesh.surface_end()

# ============================ Spawn ============================
func _place_at_spawn() -> void:
	var t := global_transform
	var had_spawn := false
	if spawn_point != NodePath("") and has_node(spawn_point):
		var sp: Node3D = get_node(spawn_point)
		t = sp.global_transform
		had_spawn = true
	if use_spawn_forward and had_spawn:
		var f := -t.basis.z
		var flat_f := Vector3(f.x, 0.0, f.z).normalized()
		if flat_f.length() < 0.001: flat_f = Vector3.FORWARD
		var y_only := Basis(); y_only = y_only.looking_at(flat_f, Vector3.UP)
		t.basis = y_only
	if snap_to_floor:
		var hit := _raycast_floor(t.origin + Vector3(0, floor_snap_distance * 0.5, 0), floor_snap_distance)
		if hit and hit.has("position"): t.origin = hit.position + Vector3(0, floor_offset_y, 0)
		else: t.origin.y = floor_offset_y
	global_transform = t
	yaw = rotation.y; last_yaw = yaw; v = 0.0; hop_y = 0.0; grounded = true; drifting = false; drift_dir = 0
	_base_y = global_position.y

func _raycast_floor(from: Vector3, dist: float) -> Dictionary:
	var state := get_world_3d().direct_space_state
	return state.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -abs(dist), 0)))

# ============================ Inputs ============================
func _ensure_inputs() -> void:
	var map := {
		"accelerate": [KEY_W, KEY_UP],
		"brake":      [KEY_S, KEY_DOWN],
		"left":       [KEY_A, KEY_LEFT],
		"right":      [KEY_D, KEY_RIGHT],
		"drift":      [KEY_SPACE],
	}
	# Add or confirm keyboard binds
	for action in map.keys():
		if not InputMap.has_action(action): InputMap.add_action(action)
		for keycode in map[action]:
			var e := InputEventKey.new(); e.physical_keycode = keycode
			if not InputMap.action_has_event(action, e):
				InputMap.action_add_event(action, e)

	# Add D-pad binds (joypad “hat” treated as buttons in Godot)
	var dpad := {
		"accelerate": [JOY_BUTTON_DPAD_UP],
		"brake":      [JOY_BUTTON_DPAD_DOWN],
		"left":       [JOY_BUTTON_DPAD_LEFT],
		"right":      [JOY_BUTTON_DPAD_RIGHT],
	}
	for action in dpad.keys():
		if not InputMap.has_action(action): InputMap.add_action(action)
		for btn in dpad[action]:
			var jb := InputEventJoypadButton.new()
			jb.button_index = btn
			if not InputMap.action_has_event(action, jb):
				InputMap.action_add_event(action, jb)


func _lut_sample(lut: Array, t: float) -> float:
	var n := lut.size()
	if n <= 1: return lut[0]
	var i = clamp(int(round(t * float(n - 1))), 0, n - 1)
	return float(lut[i])

func _q(x: float, step: float) -> float:
	if step <= 0.0: return x
	return step * floor(x / step + 0.5)

func _deg_to_rad(d: float) -> float:
	return d * PI / 180.0

func _rad_to_deg(r: float) -> float:
	return r * 180.0 / PI
