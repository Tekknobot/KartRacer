@tool
extends Node3D
class_name TrackPathBuilder

@export var track_plane: MeshInstance3D
@export var path_node: Path3D            # optional; if empty, one will be created as child
@export var samples_per_edge := 16       # straight segment samples
@export var samples_per_corner := 24     # arc samples per 90°
@export var auto_rebuild := false        # rebuild every editor frame (handy while tuning)
@export var Rebuild := false : set = _set_rebuild

# Optional small offset (meters) to push centerline inward/outward (+ = toward inner)
@export var center_offset := 0.0

func _set_rebuild(v: bool) -> void:
	Rebuild = false
	rebuild()

func _process(_dt: float) -> void:
	if Engine.is_editor_hint() and auto_rebuild:
		rebuild()

func rebuild() -> void:
	if track_plane == null:
		push_error("TrackPathBuilder: assign 'track_plane' (MeshInstance3D using your shader).")
		return
	var mat := track_plane.get_active_material(0)
	var sm := mat as ShaderMaterial
	if sm == null:
		push_error("TrackPathBuilder: 'track_plane' must use a ShaderMaterial (your track shader).")
		return

	# ---- Read shader params (names match your shader) ----
	var he : Vector2 = sm.get_shader_parameter("track_half_extents")    # vec2
	var r  : float   = sm.get_shader_parameter("corner_radius")         # float
	var tw : float   = sm.get_shader_parameter("track_width")           # float
	var uv_scale : Vector2 = Vector2.ONE
	var uv_offset: Vector2 = Vector2.ZERO
	if sm.get_shader_parameter("uv_scale") != null:
		uv_scale = sm.get_shader_parameter("uv_scale")
	if sm.get_shader_parameter("uv_offset") != null:
		uv_offset = sm.get_shader_parameter("uv_offset")

	# Centerline is the outer rect inset by half the track width (+ optional center_offset)
	var inset := (tw * 0.5) + center_offset
	var he_c := he - Vector2(inset, inset)
	var r_c  = max(r - inset, 0.0)
	he_c.x = max(he_c.x, 0.001)
	he_c.y = max(he_c.y, 0.001)

	# Build centerline in shader p-space ([-1,1]^2)
	var pts_p := _rounded_rect_loop(he_c, r_c, samples_per_edge, samples_per_corner)

	# Map p -> uv -> local -> world
	var aabb := track_plane.get_aabb()  # local-space bounds of the mesh
	var pts_world : Array[Vector3] = []
	pts_world.resize(pts_p.size())
	for i in range(pts_p.size()):
		var p: Vector2 = pts_p[i]  # p in [-1,1]
		# Invert shader mapping: p = (uv*uv_scale + uv_offset - 0.5)*2
		# => uv = ((p/2) + 0.5 - uv_offset) / uv_scale
		var uv := ((p * 0.5) + Vector2(0.5, 0.5) - uv_offset) / uv_scale

		# UV -> local on plane (assumes standard plane UVs 0..1 over local AABB)
		var lx := aabb.position.x + uv.x * aabb.size.x
		var lz := aabb.position.z + uv.y * aabb.size.z
		var local := Vector3(lx, 0.0, lz)

		pts_world[i] = track_plane.global_transform * local

	# Ensure there’s a Path3D to write to
	var path := path_node
	if path == null:
		path = Path3D.new()
		path.name = "TrackPath"
		add_child(path)
		path_node = path

	# Build the Curve3D
	var curve := Curve3D.new()
	curve.closed = true
	for p3 in pts_world:
		curve.add_point(p3)
	path.curve = curve

	# Optional: add a PathFollow3D for quick visualization
	if Engine.is_editor_hint():
		if path.get_node_or_null("PreviewFollow") == null:
			var pf := PathFollow3D.new()
			pf.name = "PreviewFollow"
			pf.loop = true
			path.add_child(pf)

	# Done
	print("TrackPathBuilder: rebuilt path with %d points." % pts_world.size())

# Build a CCW loop of points around a rounded rectangle (centered at 0)
func _rounded_rect_loop(he: Vector2, r: float, edge_samp: int, corner_samp: int) -> Array[Vector2]:
	var pts: Array[Vector2] = []
	edge_samp = max(edge_samp, 1)
	corner_samp = max(corner_samp, 1)
	r = clamp(r, 0.0, min(he.x, he.y))

	var xR := he.x
	var yT := he.y
	var xL := -he.x
	var yB := -he.y

	var ex := xR - r
	var ey := yT - r
	var wx := xL + r
	var wy := yB + r

	# Top edge: (ex,yT) -> (wx,yT)
	for i in range(edge_samp + 1):
		var t := float(i) / float(edge_samp)
		pts.append(Vector2(lerp(ex, wx, t), yT))

	# Top-left arc (center at (xL+r, yT-r)) from 90° to 180°
	var c_tl := Vector2(xL + r, yT - r)
	_append_arc(pts, c_tl, r, PI * 0.5, PI * 1.0, corner_samp)

	# Left edge: (xL, ey) -> (xL, wy)
	for i in range(edge_samp + 1):
		var t := float(i) / float(edge_samp)
		pts.append(Vector2(xL, lerp(ey, wy, t)))

	# Bottom-left arc (center at (xL+r, yB+r)) from 180° to 270°
	var c_bl := Vector2(xL + r, yB + r)
	_append_arc(pts, c_bl, r, PI * 1.0, PI * 1.5, corner_samp)

	# Bottom edge: (wx,yB) -> (ex,yB)
	for i in range(edge_samp + 1):
		var t := float(i) / float(edge_samp)
		pts.append(Vector2(lerp(wx, ex, t), yB))

	# Bottom-right arc (center at (xR-r, yB+r)) from 270° to 360°
	var c_br := Vector2(xR - r, yB + r)
	_append_arc(pts, c_br, r, PI * 1.5, PI * 2.0, corner_samp)

	# Right edge: (xR, wy) -> (xR, ey)
	for i in range(edge_samp + 1):
		var t := float(i) / float(edge_samp)
		pts.append(Vector2(xR, lerp(wy, ey, t)))

	# Top-right arc (center at (xR-r, yT-r)) from 0° to 90°
	var c_tr := Vector2(xR - r, yT - r)
	_append_arc(pts, c_tr, r, 0.0, PI * 0.5, corner_samp)

	return pts

func _append_arc(arr: Array, c: Vector2, r: float, a0: float, a1: float, n: int) -> void:
	if r <= 0.0:
		arr.append(c)
		return
	for i in range(1, n + 1):
		var t := float(i) / float(n)
		var a = lerp(a0, a1, t)   # was mix()
		arr.append(c + Vector2(cos(a), sin(a)) * r)
