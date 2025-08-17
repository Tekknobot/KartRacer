extends Sprite2D

@export var shader_path := "res://mode7_material.gdshader"
@export var track_tex_path := "res://track.png"
@export var track_size := Vector2(2048, 2048)
@export var horizon := 0.48
@export var zoom := 130.0

@export var player: Node2D        # OPTIONAL: drag your Kart here; if left empty we auto-animate

var _mat: ShaderMaterial

func _ready() -> void:
	# Fullscreen 1×1 canvas
	var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	texture = ImageTexture.create_from_image(img)
	centered = false
	z_index = -100
	position = Vector2.ZERO
	scale = get_viewport_rect().size
	get_viewport().size_changed.connect(func(): scale = get_viewport_rect().size)

	# Material + shader
	_mat = ShaderMaterial.new()
	var sh := load(shader_path)
	_mat.shader = sh
	material = _mat

	# Static params
	var road := load(track_tex_path)
	if road: _mat.set_shader_parameter("track_tex", road)
	_mat.set_shader_parameter("track_size", track_size)

func _process(t: float) -> void:
	var p: Vector2
	var r: float

	if player:
		p = player.global_position
		r = player.rotation
	else:
		# 🔁 Self-animation so you can SEE it move even with no kart wired up
		var time := float(Time.get_ticks_msec()) * 0.001
		var radius := 200.0
		p = Vector2(1024.0, 1600.0) + Vector2(cos(time), sin(time)) * radius
		r = 0.2 * sin(time * 0.7)

	_mat.set_shader_parameter("cam_pos", p)
	_mat.set_shader_parameter("cam_rot", r)
	_mat.set_shader_parameter("horizon", horizon)
	_mat.set_shader_parameter("zoom", zoom)
