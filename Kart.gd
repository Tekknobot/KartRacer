extends Node3D
#
# SNES-style arcade kart controller (no real physics):
# - Moves only along forward heading; no lateral velocity or sliding.
# - Digital-friendly steering (D-pad), optional analog fallback.
# - Hop is visual; Drift is a control state (extra yaw while holding hop).
# - Mini-boost on drift release.
# - Engine shake + lean on a visual child.
#

# ---------- Feel ----------
@export var max_speed: float = 24.0          # top speed (m/s) - a bit quicker
@export var accel_rate: float = 34.0         # forward accel
@export var brake_rate: float = 52.0         # braking / reverse accel
@export var drag: float = 2.6                # simple linear damping (no slide)

# Steering
@export var steer_deg_low: float = 150.0     # deg/s steering at low speed
@export var steer_deg_high: float = 82.0     # deg/s steering near top speed
@export var steer_speed_curve_pow: float = 0.65  # shaping 0..1 (lower = more authority at speed)
@export var dpad_snap: float = 1.0           # 1=full digital; 0.5=softer; affects d-pad steer strength

# Drift / hop (visual + control)
@export var hop_height: float = 0.22         # meters, visual only
@export var hop_time: float = 0.16           # seconds up+down
@export var drift_min_time: float = 0.10     # hold hop this long before drift can engage
@export var drift_yaw_gain: float = 1.55     # multiplier on steering yaw while drifting
@export var drift_boost_small: float = 2.2   # m/s added on short drift
@export var drift_boost_big: float = 3.8     # m/s added on long drift
@export var drift_big_time: float = 1.0      # threshold for big boost (s)

# Input
@export var stick_deadzone: float = 0.18
const GP_LEFT  := &"gp_left"
const GP_RIGHT := &"gp_right"
const GP_UP    := &"gp_up"
const GP_DOWN  := &"gp_down"

# Visuals (engine shake / lean / hop)
@export var visual_path: NodePath = ^"Visual"   # your mesh/sprite Node3D
@export var lean_max_deg: float = 10.0
@export var pitch_under_accel_deg: float = 5.0
@export var engine_shake_amp: float = 0.014
@export var engine_shake_rot_deg: float = 0.55
@export var engine_shake_freq_hz: float = 38.0

# Plane lock (Mode-7 vibe)
@export var lock_y: bool = true
var _start_y: float = 0.0

# ---------- State ----------
var speed := 0.0
var steer_input := 0.0            # -1..1
var accel_pressed := false
var brake_pressed := false
var hop_pressed := false
var hop_just_pressed := false
var hop_just_released := false

# Drift/hop
var hop_t := 0.0
var hopping := false
var hop_held := false
var drifting := false
var drift_timer := 0.0
var drift_dir := 0.0              # -1 left, +1 right

# Visual
var _visual: Node3D
var _vis_base: Transform3D
var _shake_t := 0.0

# --- Visual sprite driving (steer → frames) ---
@export var sprite_is_visual := true                 # set true if `Visual` is an AnimatedSprite3D
@export var anim_straight: StringName = &"straight"  # idle/straight anim name
@export var anim_turn_right: StringName = &"turn"    # right-turn anim name (used for both sides)
@export var steer_anim_threshold: float = 0.2       # below this = use straight
@export var turn_max_frame: int = 4                  # clamp to frames 0..4

@export var sprite: AnimatedSprite3D
var _checked_anims := false

@export var debug_sprite_drive := true

@export var turn_in_time: float = 0.25   # seconds to go 0 -> 4 while holding steer
@export var turn_out_time: float = 0.20  # seconds to fall back 4 -> 0 when released
var _turn_prog := 0.0    # 0..1 across frames 0..4
var _turn_sign := 0      # -1 left, 0 none, +1 right (for reset on dir change)


func _ready() -> void:
	_start_y = global_position.y
	_visual = get_node_or_null(visual_path)
	if _visual:
		_vis_base = _visual.transform
	_init_sprite_links()

func _physics_process(delta: float) -> void:
	_read_inputs(delta)
	_handle_hop_and_drift(delta)
	_integrate_speed(delta)
	_apply_steering(delta)
	_move_forward(delta)
	_update_visual(delta)
	_drive_sprite_from_steer(delta)  # <-- moved here so it always runs

# ---------- Input ----------
func _read_inputs(delta: float) -> void:
	# analog vector with deadzone shaping
	var v: Vector2 = Input.get_vector(GP_LEFT, GP_RIGHT, GP_UP, GP_DOWN)
	if v.length() < stick_deadzone:
		v = Vector2.ZERO
	else:
		var t := (v.length() - stick_deadzone) / (1.0 - stick_deadzone)
		t = clamp(t, 0.0, 1.0)
		# cube for finer center control
		v = v.normalized() * pow(t, 3.0)

	var dpad := Input.get_action_strength(GP_RIGHT) - Input.get_action_strength(GP_LEFT)
	var analog_x := v.x

	# If dpad pressed, use crisp digital steer; else analog
	var raw := 0.0
	if abs(dpad) > 0.0:
		raw = clamp(dpad, -1.0, 1.0) * dpad_snap
	else:
		raw = analog_x

	# No smoothing (SNES feel). If you want tiny smoothing, use move_toward here.
	steer_input = clamp(raw, -1.0, 1.0)

	accel_pressed = Input.is_action_pressed(&"kart_accel")
	brake_pressed = Input.is_action_pressed(&"kart_brake")
	hop_pressed = Input.is_action_pressed(&"kart_hop")
	hop_just_pressed = Input.is_action_just_pressed(&"kart_hop")
	hop_just_released = Input.is_action_just_released(&"kart_hop")

	if debug_sprite_drive and abs(steer_input) > 0.0:
		print("[steer] ", steer_input)

# ---------- Hop/Drift state machine ----------
func _handle_hop_and_drift(delta: float) -> void:
	# Start hop (visual only)
	if hop_just_pressed and not hopping:
		hopping = true
		hop_held = true
		hop_t = 0.0
		drifting = false
		drift_timer = 0.0
		drift_dir = signf(steer_input)  # remember initial direction hint

	# While holding hop, accrue drift time; engage drift if steering and moving
	if hop_held:
		drift_timer += delta
		if not drifting and drift_timer >= drift_min_time and abs(steer_input) > 0.15 and speed > 2.0:
			drifting = true
			drift_dir = signf(steer_input)

	# Release hop -> end drift & apply boost
	if hop_just_released:
		hop_held = false
		if drifting:
			var boost := drift_boost_small
			if drift_timer >= drift_big_time:
				boost = drift_boost_big
			speed = min(max_speed * 1.15, speed + boost)  # small overcap ok
		drifting = false
		drift_timer = 0.0

# ---------- Speed (1D) ----------
func _integrate_speed(delta: float) -> void:
	var a := 0.0
	if accel_pressed: a += accel_rate
	if brake_pressed: a -= brake_rate

	# Simple linear damping, always opposes motion
	speed -= drag * speed * delta
	speed += a * delta

	# Clamp and simple reverse rule
	if speed >= 0.0:
		speed = clamp(speed, 0.0, max_speed)
	else:
		if brake_pressed or not accel_pressed:
			speed = clamp(speed, -8.0, 0.0)
		else:
			speed = move_toward(speed, 0.0, brake_rate * delta)

	if abs(speed) < 0.02:
		speed = 0.0

# ---------- Steering / yaw ----------
func _apply_steering(delta: float) -> void:
	# Blend between low/high steering based on speed fraction with shaping
	var s = clamp(abs(speed) / max_speed, 0.0, 1.0)
	var shaped := pow(1.0 - s, steer_speed_curve_pow)
	var steer_deg = lerp(steer_deg_high, steer_deg_low, shaped)

	# Extra yaw while drifting in the chosen direction (don’t flip if you cross zero)
	if drifting:
		var dir := drift_dir
		if drift_dir == 0.0:
			dir = signf(steer_input)

		if signf(steer_input) == dir and abs(steer_input) > 0.0:
			steer_deg *= drift_yaw_gain

	var yaw_rate := deg_to_rad(steer_deg) * steer_input
	rotate_y(-yaw_rate * delta)

# ---------- Translate along forward ----------
func _move_forward(delta: float) -> void:
	var fwd: Vector3 = -global_transform.basis.z
	global_position += fwd * speed * delta
	if lock_y:
		global_position.y = _start_y

# ---------- Visuals ----------
func _update_visual(delta: float) -> void:
	if not _visual:
		return
	_visual.transform = _vis_base

	# --- Hop parabola ---
	if hopping:
		hop_t += delta
		var t = hop_t / max(0.001, hop_time)
		if t >= 1.0:
			t = 1.0
			hopping = false
		var k := 0.0
		if t <= 0.5:
			k = t / 0.5
		else:
			k = 1.0 - (t - 0.5) / 0.5
		var yoff := hop_height * (1.0 - pow(1.0 - k, 2.0))
		var tx := _visual.transform
		tx.origin.y += yoff
		_visual.transform = tx

	# --- Lean & engine shake ---
	var roll_deg := -steer_input * lean_max_deg
	var accel_intent := 0.0
	if accel_pressed: accel_intent += 1.0
	if brake_pressed: accel_intent -= 1.0
	var pitch_deg := -accel_intent * pitch_under_accel_deg

	var t2 := _visual.transform   # <--- declare it here
	var engine_on = accel_pressed or abs(speed) > 0.2
	if engine_on:
		_shake_t += delta
		var w := engine_shake_freq_hz * TAU
		var sp = clamp(abs(speed) / max_speed, 0.0, 1.0)
		var amp = engine_shake_amp * (0.6 + 0.7 * sp)

		var off_y = sin(_shake_t * w) * amp
		var off_x = sin(_shake_t * w * 0.53 + 1.1) * amp * 0.5
		var off_z = sin(_shake_t * w * 0.61 + 2.3) * amp * 0.5

		var rot_roll  := deg_to_rad(roll_deg + sin(_shake_t * w * 0.77) * engine_shake_rot_deg)
		var rot_pitch := deg_to_rad(pitch_deg + sin(_shake_t * w * 0.71 + 0.8) * engine_shake_rot_deg * 0.8)
		var rot_yaw   := deg_to_rad(sin(_shake_t * w * 0.67 + 1.6) * engine_shake_rot_deg * 0.6)

		t2.origin += Vector3(off_x, off_y, off_z)
		t2.basis = Basis(Vector3(0,1,0), rot_yaw) * Basis(Vector3(1,0,0), rot_pitch) * Basis(Vector3(0,0,1), rot_roll) * t2.basis
	else:
		t2.basis = Basis(Vector3(1,0,0), deg_to_rad(pitch_deg)) * Basis(Vector3(0,0,1), deg_to_rad(roll_deg)) * t2.basis

	_visual.transform = t2   # assign once here

func _drive_sprite_from_steer(delta: float) -> void:
	if sprite == null or sprite.sprite_frames == null:
		return

	# Names may be auto-mapped earlier; just guard existence
	var has_straight := sprite.sprite_frames.has_animation(anim_straight)
	var has_turn := sprite.sprite_frames.has_animation(anim_turn_right)

	# How many frames can we use from the turn anim?
	var total := 0
	if has_turn:
		total = sprite.sprite_frames.get_frame_count(anim_turn_right)
	if total <= 1:
		# Nothing to animate; just play straight and bail
		if has_straight:
			if StringName(sprite.animation) != anim_straight:
				sprite.play(anim_straight)
			else:
				sprite.play()
		return

	var frames_to_use = min(turn_max_frame + 1, total)  # e.g. min(5, total)
	var s := steer_input
	var mag = abs(s)
	var turning = mag >= steer_anim_threshold

	# ----- choose / manage clip -----
	if turning:
		# Ensure turn clip is selected, then hard-stop so manual frame sticks
		if StringName(sprite.animation) != anim_turn_right:
			sprite.play(anim_turn_right)
		sprite.stop()
		sprite.speed_scale = 0.0
	else:
		# Straight: play normally
		if has_straight:
			if StringName(sprite.animation) != anim_straight:
				sprite.play(anim_straight)
			else:
				sprite.play()
		sprite.speed_scale = 1.0
		sprite.flip_h = false

	# ----- progress phase -----
	if turning:
		# reset phase when direction flips so it plays 0->4 again
		var sign := 0
		if s > 0.0:
			sign = 1
		elif s < 0.0:
			sign = -1
		if sign != 0 and sign != _turn_sign:
			_turn_prog = 0.0
			_turn_sign = sign

		# advance toward 1.0 over turn_in_time
		var rate_in := 1.0
		if turn_in_time > 0.0:
			rate_in = delta / turn_in_time
		_turn_prog += rate_in
		if _turn_prog > 1.0:
			_turn_prog = 1.0
	else:
		# decay back toward 0 over turn_out_time
		var rate_out := 1.0
		if turn_out_time > 0.0:
			rate_out = delta / turn_out_time
		_turn_prog -= rate_out
		if _turn_prog < 0.0:
			_turn_prog = 0.0
		_turn_sign = 0

	# ----- pick frame from phase -----
	# phase 0..1 → frame 0..frames_to_use-1
	var idx := int(floor(_turn_prog * float(frames_to_use - 1)))
	if idx < 0:
		idx = 0
	if idx > frames_to_use - 1:
		idx = frames_to_use - 1

	# apply frame and mirror for left
	if turning:
		sprite.set_frame_and_progress(idx, 0.0)
		sprite.flip_h = (s < 0.0)

func _init_sprite_links() -> void:
	if sprite == null:
		if debug_sprite_drive: print("[sprite] not assigned")
		return
	if sprite.sprite_frames and sprite.sprite_frames.has_animation(anim_straight):
		sprite.play(anim_straight)
	else:
		if debug_sprite_drive: print("[sprite] straight anim missing: ", anim_straight)
	# Signals so we always push the correct texture to the override
	if sprite.has_signal("frame_changed"):
		sprite.connect("frame_changed", Callable(self, "_sync_sprite_material_to_frame"))
	if sprite.has_signal("animation_changed"):
		sprite.connect("animation_changed", Callable(self, "_sync_sprite_material_to_frame"))
	_sync_sprite_material_to_frame()
	if debug_sprite_drive:
		var names: PackedStringArray
		if sprite.sprite_frames != null:
			names = sprite.sprite_frames.get_animation_names()
		else:
			names = PackedStringArray()
		print("[sprite] init ok. anims=", names)

func _sync_sprite_material_to_frame() -> void:
	# Auto-map export names if they don't exist in SpriteFrames
	if sprite != null and sprite.sprite_frames != null:
		var names: PackedStringArray
		if sprite.sprite_frames != null:
			names = sprite.sprite_frames.get_animation_names()
		else:
			names = PackedStringArray()

		# fix straight name
		if not sprite.sprite_frames.has_animation(anim_straight):
			# prefer a name containing "straight", else first anim
			for n in names:
				if "straight" in String(n).to_lower():
					anim_straight = n
					break
			if not sprite.sprite_frames.has_animation(anim_straight) and names.size() > 0:
				anim_straight = names[0]

		# fix turn name
		if not sprite.sprite_frames.has_animation(anim_turn_right):
			for n in names:
				if "turn" in String(n).to_lower():
					anim_turn_right = n
					break
			if not sprite.sprite_frames.has_animation(anim_turn_right) and names.size() > 1:
				# pick a different anim than straight if possible
				for n in names:
					if n != anim_straight:
						anim_turn_right = n
						break
