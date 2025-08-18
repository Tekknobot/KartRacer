@tool
extends Node3D

# --- Pieces ---
@export var straight_scene: PackedScene
@export var right_turn_scene: PackedScene

# --- Layout ---
@export var tile_size: float = 200.0
@export var y_offset: float = 0.0
@export var start_heading: int = 0                  # 0:N(-Z), 1:E(+X), 2:S(+Z), 3:W(-X)
@export var path: String = "FFFFRFFFFRFFFFRFFFFR"

# Mesh pivot mode
@export_enum("Center","BottomLeft") var pivot_mode: int = 0

# --- Orientation helpers ---
@export var straight_base_yaw_deg: float = 0.0      # straight runs -Z when yaw=0
@export var turn_base_yaw_deg: float = 0.0          # base for the turn mesh
@export var turn_yaw_offset_deg: float = -90.0      # <--- NOTE: first turn will get -90°
@export var accumulate_turn_rotation: bool = false  # optional: each successive R adds another 90°

# Editor behavior
@export var auto_build_in_editor: bool = true
@export var clear_before_build: bool = true

# --- Internals ---
const DIRS := [
	Vector3(0,0,-1),  # 0: N (-Z)
	Vector3(1,0, 0),  # 1: E (+X)
	Vector3(0,0, 1),  # 2: S (+Z)
	Vector3(-1,0,0)   # 3: W (-X)
]
const YAW_DEG := [0.0, -90.0, 180.0, 90.0]

var _built_once := false

func _ready() -> void:
	if not Engine.is_editor_hint():
		build_track()
	elif auto_build_in_editor and not _built_once:
		build_track()
		_built_once = true

func build_track() -> void:
	if clear_before_build:
		_clear_children()

	if straight_scene == null or right_turn_scene == null:
		push_warning("TrackBuilder: assign both straight_scene and right_turn_scene.")
		return

	var heading := clampi(start_heading, 0, 3)
	var grid := Vector3i(0,0,0)
	var turn_count := 0

	var container := Node3D.new()
	container.name = "Pieces"
	add_child(container)
	if Engine.is_editor_hint():
		container.owner = get_tree().edited_scene_root

	var cmds := path.strip_edges()
	for i in cmds.length():
		var c := cmds[i]
		match c:
			'F', 'S':
				_place_straight(container, grid, heading)
				grid += Vector3i(DIRS[heading].x, 0, DIRS[heading].z)
			'R':
				_place_right_turn(container, grid, heading, turn_count)
				turn_count += 1
				heading = (heading + 1) % 4
				grid += Vector3i(DIRS[heading].x, 0, DIRS[heading].z)
			' ', '\t', '\n', '\r':
				pass
			_:
				push_warning("TrackBuilder: unknown command '%s' at %d" % [str(c), i])

func _place_straight(parent: Node, grid_pos: Vector3i, heading: int) -> void:
	var inst := straight_scene.instantiate()
	parent.add_child(inst)
	if Engine.is_editor_hint():
		inst.owner = get_tree().edited_scene_root
	var yaw = straight_base_yaw_deg + YAW_DEG[heading]
	inst.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(yaw)),
		global_transform.origin + _grid_to_world(grid_pos)
	)

func _place_right_turn(parent: Node, grid_pos: Vector3i, heading: int, turn_index: int) -> void:
	var inst := right_turn_scene.instantiate()
	parent.add_child(inst)
	if Engine.is_editor_hint():
		inst.owner = get_tree().edited_scene_root

	var extra := turn_yaw_offset_deg
	if accumulate_turn_rotation:
		extra += float(turn_index) * 90.0

	var yaw = turn_base_yaw_deg + YAW_DEG[heading] + extra
	inst.transform = Transform3D(
		Basis(Vector3.UP, deg_to_rad(yaw)),
		global_transform.origin + _grid_to_world(grid_pos)
	)

func _grid_to_world(grid_pos: Vector3i) -> Vector3:
	var base := Vector3(grid_pos.x * tile_size, y_offset, grid_pos.z * tile_size)
	if pivot_mode == 0:
		return base + Vector3(0.5 * tile_size, 0.0, 0.5 * tile_size)
	else:
		return base

func _clear_children() -> void:
	for c in get_children():
		if c is Node3D:
			c.queue_free()
