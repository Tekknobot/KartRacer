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
	# Validate scene & path
	if kart_scene == null:
		push_error("kart_scene not set"); return
	var p := get_node_or_null(path) as Path3D
	if p == null or p.curve == null or p.curve.get_point_count() < 2:
		push_error("RaceManager: 'path' must point to a Path3D with a valid Curve3D."); return

	var curve := p.curve
	var L := curve.get_baked_length()
	if L <= 0.0:
		push_error("RaceManager: Path3D.curve baked length is 0."); return

	# Choose spaced random offsets along the path
	var offsets := _random_spaced_offsets(L, total_karts, 3.5) # 3.5m min gap

	for i in range(total_karts):
		var inst: Node3D = kart_scene.instantiate()

		# >>> IMPORTANT: mark as AI BEFORE adding to the scene so _ready() uses AI branch
		if "external_input" in inst:
			inst.external_input = true

		add_child(inst)

		# Pose from path (position + yaw from tangent)
		var s := offsets[i]
		var xform := _sample_pose_on_path(curve, s)
		# tiny random yaw jitter so they don’t overlap exactly
		var yaw_jit := deg_to_rad(_rng.randf_range(-2.0, 2.0))
		xform.basis = Basis(Vector3.UP, yaw_jit) * xform.basis
		inst.global_transform = xform

		# give each an AI driver configured for this path
		var driver := AIDriver.new()
		driver.path = path
		# stagger lanes left/right so they don’t stack on the same line
		var lane_sign := (1 if (i % 2 == 0) else -1)
		driver.lane_offset = lane_sign * _rng.randf_range(0.0, ai_lane_spread)
		# slight speed diversity
		driver.target_speed = 0.75 + _rng.randf_range(-0.06, 0.08)
		inst.add_child(driver)

		_karts.append(inst)

func _random_spaced_offsets(L: float, count: int, min_gap: float) -> Array[float]:
	_rng.randomize()
	var chosen: Array[float] = []
	var tries_per := 64
	for i in range(count):
		var picked := -1.0
		for t in range(tries_per):
			var s := _rng.randf() * L
			var ok := true
			for c in chosen:
				if _circular_dist(s, c, L) < min_gap:
					ok = false; break
			if ok:
				picked = s; break
		if picked < 0.0:
			# fallback: place after last with min_gap
			picked = ( (chosen.back() if chosen.size()>0 else 0.0) + min_gap ) % L
		chosen.append(picked)
	# sort for nicer grid-ish order
	chosen.sort()
	return chosen

func _circular_dist(a: float, b: float, L: float) -> float:
	var d = abs(a - b)
	return min(d, L - d)

func _sample_pose_on_path(curve: Curve3D, s: float) -> Transform3D:
	var p0 := curve.sample_baked(s)
	var ds = max(0.5, curve.get_baked_length() * 0.002) # ~0.5m step
	var p1 := curve.sample_baked(fposmod(s + ds, curve.get_baked_length()))

	# flatten to XZ for yaw
	var fwd := p1 - p0
	fwd.y = 0.0
	if fwd.length() < 1e-3:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()

	# Build a transform that faces along the path (Godot forward is -Z)
	var xform := Transform3D()
	xform.origin = p0
	xform = xform.looking_at(p0 + fwd, Vector3.UP)
	return xform

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
