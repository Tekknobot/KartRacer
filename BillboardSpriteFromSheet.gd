extends AnimatedSprite3D
## Build animations directly from individual cell textures (no sprite sheet).
## Exposes a single anim "turn_right" with N frames; the kart script will scrub frames.

# Provide your frames here (drag & drop in order: full-left .. straight .. full-right)
@export var cells: Array[Texture2D] = []

# Playback & rendering
@export var anim_name: StringName = &"turn_right"
@export var default_fps: float = 12.0
@export var loop_anim: bool = false   # we scrub frames manually, no looping needed

# Billboard / size controls
@export var billboard_mode: int = BaseMaterial3D.BILLBOARD_FIXED_Y
@export var use_fixed_size := true
@export var pixel_size_value := 0.03
@export var force_nearest_at_runtime := true

var _frames: SpriteFrames

func _ready() -> void:
	visible = true
	modulate = Color(1, 1, 1, 1)
	billboard = billboard_mode
	fixed_size = use_fixed_size
	pixel_size = pixel_size_value
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	if force_nearest_at_runtime:
		texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST

	if cells.is_empty():
		push_error("No cells provided. Drag textures into 'cells' (AnimatedSprite3D).")
		return

	_frames = SpriteFrames.new()
	sprite_frames = _frames

	_add_anim_from_cells(anim_name, cells, default_fps)
	sprite_frames.set_animation_loop(anim_name, loop_anim)

	# start at the center (straight-looking frame)
	animation = anim_name
	var center := (cells.size() - 1) / 2
	frame = center

func _add_anim_from_cells(name: StringName, list: Array[Texture2D], fps: float) -> void:
	if not sprite_frames.has_animation(name):
		sprite_frames.add_animation(name)
	sprite_frames.set_animation_speed(name, fps)

	for tex in list:
		if tex == null:
			continue
		sprite_frames.add_frame(name, tex)
