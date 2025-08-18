# AnimatedSprite3D_NoZ_CullSafeBillboard.gd
extends AnimatedSprite3D

# --- subtle, recentring yaw ---
@export var enable_yaw := true
@export var yaw_lerp := 0.25
@export var follow_strength := 0.35   # how much we try to face camera (0..1)
@export var max_yaw_deg: float = 12.0 # clamp deviation from base
@export var recenter_lerp := 0.08     # gentle pull-to-base each frame

var _mat: StandardMaterial3D
var _base_yaw := 0.0                  # cached yaw at spawn
var _last_anim := ""
var _last_frame := -1

func _ready() -> void:
	set_process_priority(100)          # compose after controller visuals

	# ---- RENDER GUARDRAILS (code-only) ----
	# 1) Material: two-sided, alpha, no depth test, no depth write
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED   # don't write depth
	_mat.disable_depth_test = true                               # don't test depth
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED                # two-sided
	_mat.render_priority = 127                                   # draw late among transparents
	material_override = _mat

	# 2) Node-side flags to prevent culling surprises
	double_sided = true
	ignore_occlusion_culling = true        # <- important on large occluders
	extra_cull_margin = 1.0                # grow AABB a bit so we don't pop out

	# 3) Feed the current frame into material (so it’s not a white quad)
	_update_albedo_from_spriteframe()
	if has_signal("frame_changed"):
		connect("frame_changed", Callable(self, "_update_albedo_from_spriteframe"))
	if has_signal("animation_changed"):
		connect("animation_changed", Callable(self, "_update_albedo_from_spriteframe"))

	# 4) Cache base yaw at spawn (we’ll rotate *relative* to this)
	var fwd := -global_transform.basis.z
	_base_yaw = atan2(fwd.x, fwd.z)

func _process(_dt: float) -> void:
	# Defensive: refresh frame if anim/frame changed
	if animation != _last_anim or frame != _last_frame:
		_update_albedo_from_spriteframe()

	if enable_yaw:
		_apply_subtle_yaw()

func _update_albedo_from_spriteframe() -> void:
	var sf: SpriteFrames = sprite_frames
	if sf == null:
		return

	var anim := animation
	if anim == "":
		if sf.get_animation_names().size() > 0:
			anim = sf.get_animation_names()[0]
		else:
			return

	var tex: Texture2D = sf.get_frame_texture(anim, frame)
	if tex == null and sf.get_animation_names().size() > 0:
		anim = sf.get_animation_names()[0]
		tex = sf.get_frame_texture(anim, 0)

	if tex != null:
		_mat.albedo_texture = tex
		_last_anim = anim
		_last_frame = frame

func _apply_subtle_yaw() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	# current yaw from basis (forward is -Z)
	var fwd_now := -global_transform.basis.z
	var current_yaw := atan2(fwd_now.x, fwd_now.z)

	# target = base yaw nudged toward camera, clamped, with recenter bias
	var to_cam := cam.global_transform.origin - global_transform.origin
	var cam_yaw := atan2(to_cam.x, to_cam.z)
	var target := lerp_angle(_base_yaw, cam_yaw, clamp(follow_strength, 0.0, 1.0))

	var max_off := deg_to_rad(max_yaw_deg)
	var off := wrapf(target - _base_yaw, -PI, PI)
	off = clamp(off, -max_off, max_off)
	target = _base_yaw + off

	var back := wrapf(_base_yaw - target, -PI, PI)
	target += back * clamp(recenter_lerp, 0.0, 1.0)

	# blend from current toward *target*, then SET rotation.y relative to base
	var new_yaw := current_yaw + lerp_angle(0.0, wrapf(target - current_yaw, -PI, PI), clamp(yaw_lerp, 0.0, 1.0))

	# --- Important: compute RELATIVE yaw from base and apply cleanly ---
	var rel := wrapf(new_yaw - _base_yaw, -PI, PI)
	var t := global_transform
	# rebuild basis with the same up axis but with base_yaw + rel; preserves position & scale
	var yaw_basis := Basis(Vector3.UP, _base_yaw + rel)
	# keep existing roll/pitch? (If your controller adds those on a parent visual, this is fine.
	# If you *also* roll/pitch this node elsewhere, prefer to put this billboard on a child rig.)
	t.basis = yaw_basis
	global_transform = t
