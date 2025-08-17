# File: MarioCircuitBuilder.gd
@tool
extends Node3D

# ----- Tile / track scale (SMK-ish) -----
@export var tile_size: float = 12.0
@export var track_width: float = 8.0
@export var curb_width: float = 0.5
@export var y_height: float = 0.0

@export var track_material_template: ShaderMaterial

# ----- Default Mario-Circuit-like layout (rounded rectangle) -----
@export var straight_A: int = 6
@export var straight_B: int = 9
@export var straight_C: int = 6
@export var straight_D: int = 9
@export var start_grid_tiles: int = 2

@export var rebuild_now: bool = false:
	set(v):
		rebuild_now = false
		rebuild()

const PIECE_STRAIGHT: int = 0
const PIECE_CURVE: int = 1
const PIECE_GRID: int = 2

# Direction (quarter turns): 0=up (-Z), 1=left (-X), 2=down (+Z), 3=right (+X)
var _dir: int = 0
var _gx: int = 0
var _gz: int = 0

func _ready() -> void:
	rebuild()

func rebuild() -> void:
	_clear_children()

	_dir = 0
	_gx = 0
	_gz = 0

	# Front straight (start area at the beginning)
	_place_straight(straight_A, true)

	# Four 90° corners (rounded rectangle, clockwise)
	_place_curve(true)
	_place_straight(straight_B, false)

	_place_curve(true)
	_place_straight(straight_C, false)

	_place_curve(true)
	_place_straight(straight_D, false)

	_place_curve(true)

# ------------------------------------------------------------
# Placement helpers (grid turtle)
# ------------------------------------------------------------
func _place_straight(count_tiles: int, mark_grid: bool) -> void:
	var i: int = 0
	while i < count_tiles:
		var piece_kind: int = PIECE_STRAIGHT
		if mark_grid and i < start_grid_tiles:
			piece_kind = PIECE_GRID
		_spawn_tile(piece_kind, _dir, 1) # cw_flag ignored for straight/grid
		_advance()
		i += 1

func _place_curve(clockwise: bool) -> void:
	var cw_flag: int = 1
	if not clockwise:
		cw_flag = 0
	# Pass the current entry direction to the shader so it can rotate the curve tile
	_spawn_tile(PIECE_CURVE, _dir, cw_flag)

	# Update heading: CW = -1 mod 4, CCW = +1 mod 4
	if clockwise:
		_dir = (_dir + 3) % 4   # -1 mod 4
	else:
		_dir = (_dir + 1) % 4   # +1 mod 4

	# Move one tile forward in the new direction
	_advance()

func _advance() -> void:
	if _dir == 0:
		_gz = _gz - 1
	elif _dir == 1:
		_gx = _gx - 1
	elif _dir == 2:
		_gz = _gz + 1
	else:
		_gx = _gx + 1

# ------------------------------------------------------------
# Tile instancing
# ------------------------------------------------------------
func _spawn_tile(kind: int, rot_quarters: int, cw_flag: int) -> void:
	var pos: Vector3 = Vector3(float(_gx) * tile_size, y_height, float(_gz) * tile_size)

	# Godot 4: PlaneMesh is already on XZ (flat). Do NOT rotate!
	var plane: PlaneMesh = PlaneMesh.new()
	plane.size = Vector2(tile_size, tile_size)
	plane.subdivide_width = 1
	plane.subdivide_depth = 1

	var mi: MeshInstance3D = MeshInstance3D.new()
	mi.mesh = plane
	mi.position = pos  # 4.x property; sets transform.origin

	# Per-tile material instance (so each tile has its own uniforms)
	if track_material_template != null and track_material_template.shader != null:
		var sh: ShaderMaterial = track_material_template.duplicate() as ShaderMaterial
		sh.set_shader_parameter("tile_kind", kind)
		sh.set_shader_parameter("rot_quarters", rot_quarters)
		sh.set_shader_parameter("curve_cw", cw_flag)
		sh.set_shader_parameter("tile_meters", tile_size)
		sh.set_shader_parameter("road_width_m", track_width)
		sh.set_shader_parameter("curb_width_m", curb_width)
		mi.material_override = sh

	add_child(mi)

# ------------------------------------------------------------
# Utils
# ------------------------------------------------------------
func _clear_children() -> void:
	var i: int = 0
	while i < get_child_count():
		var n: Node = get_child(i)
		remove_child(n)
		n.queue_free()
		i += 1
