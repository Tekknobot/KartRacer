extends Node3D

@export var kart_scene: PackedScene        # your kart scene with the script you posted
@export var path: NodePath                 # Path3D (racing line)
@export var spawns_root: NodePath          # Node3D that has SpawnPoint* children
@export var total_karts := 8               # including player if you add one later
@export var random_seed := 1337
@export var ai_lane_spread := 0.6          # stagger AI lane offsets

var _rng := RandomNumberGenerator.new()
var _karts: Array[Node3D] = []

func _ready() -> void:
	_rng.seed = random_seed
	_spawn_grid()

func _spawn_grid() -> void:
	if kart_scene == null: 
		push_error("kart_scene not set"); return
	var spawns := _collect_spawns()
	if spawns.size() == 0:
		push_error("No spawn points under spawns_root"); return

	for i in range(total_karts):
		var inst: Node3D = kart_scene.instantiate()
		add_child(inst)

		# place at spawn (wrap around if more karts than spawns)
		var sp := spawns[i % spawns.size()]
		inst.global_transform = sp.global_transform

		# tiny random yaw jitter so they don’t overlap exactly
		var b := inst.transform.basis
		var yaw_jit := deg_to_rad(_rng.randf_range(-2.0, 2.0))
		b = Basis(Vector3.UP, yaw_jit) * b
		inst.transform.basis = b

		# give each an AI driver
		var driver := AIDriver.new()
		driver.path = path
		# stagger lanes left/right so they don’t stack on the same line
		var lane_sign := (1 if (i % 2 == 0) else -1)
		driver.lane_offset = lane_sign * _rng.randf_range(0.0, ai_lane_spread)
		# slight speed diversity
		driver.target_speed = 0.75 + _rng.randf_range(-0.06, 0.08)
		inst.add_child(driver)

		# ensure AI drives it
		if "external_input" in inst:
			inst.external_input = true

		_karts.append(inst)

func _collect_spawns() -> Array[Node3D]:
	if spawns_root == NodePath("") or not has_node(spawns_root):
		return []
	var root := get_node(spawns_root) as Node3D
	var pts: Array[Node3D] = []
	for c in root.get_children():
		if c is Node3D: pts.append(c)
	# sort by name for stable ordering
	pts.sort_custom(func(a, b): return a.name < b.name)
	return pts

func deg_to_rad(d: float) -> float:
	return d * PI / 180.0
