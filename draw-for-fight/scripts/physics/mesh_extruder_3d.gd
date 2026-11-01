class_name MeshExtruder3D
extends RefCounted
## Converts 2D strokes from CreationData or MapData.terrain_strokes into a Godot 4 ArrayMesh
## using SurfaceTool, and builds optimized 3D collision shapes for stable Jolt 3D physics.

const CANVAS_CENTER := Vector2(256.0, 256.0)
const CANVAS_SIZE := 512.0
const TARGET_WORLD_HEIGHT := 2.0
const SCALE_2D_TO_3D := TARGET_WORLD_HEIGHT / CANVAS_SIZE


static func _to_vec2(pt: Variant) -> Vector2:
	if pt is Vector2:
		return pt
	elif pt is Array and pt.size() >= 2:
		return Vector2(float(pt[0]), float(pt[1]))
	elif pt is Dictionary:
		return Vector2(float(pt.get("x", 0.0)), float(pt.get("y", 0.0)))
	return Vector2.ZERO


static func canvas_point_to_3d(pt_2d: Vector2) -> Vector3:
	var x := (pt_2d.x - CANVAS_CENTER.x) * SCALE_2D_TO_3D
	var y := (CANVAS_CENTER.y - pt_2d.y) * SCALE_2D_TO_3D + (TARGET_WORLD_HEIGHT * 0.5)
	return Vector3(x, y, 0.0)


static func estimate_vertex_count(strokes: Array) -> int:
	var total := 0
	for stroke in strokes:
		if not (stroke is Dictionary):
			continue
		var pts: Array = stroke.get("points", [])
		if pts.size() == 1:
			total += 24
		elif pts.size() >= 2:
			total += (pts.size() - 1) * 24 + 12
	return total


static func build_extruded_mesh_from_creation(creation: CreationData) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var depth := 0.22
	var strokes: Array = []
	if creation != null:
		depth = clampf(creation.extrusion_depth if creation.extrusion_depth > 0.0 else 0.22, 0.06, 0.8)
		strokes = creation.strokes

	var half_z := depth * 0.5
	var vertex_budget := D4FConstants.MAX_VERTICES_PER_MESH
	var current_vertices := 0
	var added_any_geometry := false

	var raw_estimate := estimate_vertex_count(strokes)
	var subsample_step := 1
	if raw_estimate > vertex_budget and vertex_budget > 0:
		subsample_step = maxi(1, int(ceil(float(raw_estimate) / float(vertex_budget))))

	for stroke in strokes:
		if not (stroke is Dictionary):
			continue
		var raw_pts: Array = stroke.get("points", [])
		if raw_pts.is_empty():
			continue

		var color_str: String = str(stroke.get("color", "#33aaff"))
		var color := Color.from_string(color_str, Color.DODGER_BLUE)
		var thickness_px: float = clampf(float(stroke.get("thickness", 8.0)), 2.0, 48.0)
		var half_w: float = maxf(0.025, (thickness_px * SCALE_2D_TO_3D) * 0.5)
		var part_tag: String = str(stroke.get("part_tag", "body"))
		var stroke_half_z := half_z
		if part_tag == "wheel":
			stroke_half_z = half_z * 1.25
		elif part_tag == "weapon" or part_tag == "bumper":
			stroke_half_z = half_z * 1.15

		var pts_3d: Array[Vector3] = []
		for i in range(0, raw_pts.size(), subsample_step):
			pts_3d.append(canvas_point_to_3d(_to_vec2(raw_pts[i])))
		if raw_pts.size() > 1 and (raw_pts.size() - 1) % subsample_step != 0:
			pts_3d.append(canvas_point_to_3d(_to_vec2(raw_pts[raw_pts.size() - 1])))

		if pts_3d.size() == 1:
			# Single dot stroke: extrude a small cube around the point
			var c := pts_3d[0]
			_add_oriented_box(
				st,
				c - Vector3(half_w, 0.0, 0.0),
				c + Vector3(half_w, 0.0, 0.0),
				half_w,
				stroke_half_z,
				color,
				true,
				true
			)
			current_vertices += 24
			added_any_geometry = true
			continue

		for seg_idx in range(pts_3d.size() - 1):
			if current_vertices + 24 > vertex_budget:
				break
			var p0 := pts_3d[seg_idx]
			var p1 := pts_3d[seg_idx + 1]
			if p0.distance_squared_to(p1) < 0.00001:
				continue
			var cap_start := (seg_idx == 0)
			var cap_end := (seg_idx == pts_3d.size() - 2)
			_add_oriented_box(st, p0, p1, half_w, stroke_half_z, color, cap_start, cap_end)
			current_vertices += 24
			added_any_geometry = true

	if not added_any_geometry:
		# Fallback default silhouette block so mesh is always valid
		_add_oriented_box(
			st,
			Vector3(0.0, 0.2, 0.0),
			Vector3(0.0, 1.6, 0.0),
			0.25,
			half_z,
			Color.DODGER_BLUE,
			true,
			true
		)

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.45
	mat.metallic = 0.08
	st.set_material(mat)

	var mesh := st.commit()
	return mesh


static func _add_oriented_box(
	st: SurfaceTool,
	p0: Vector3,
	p1: Vector3,
	half_w: float,
	half_z: float,
	color: Color,
	cap_start: bool,
	cap_end: bool
) -> void:
	var dir := (p1 - p0)
	var len := dir.length()
	if len < 0.0001:
		dir = Vector3.RIGHT
	else:
		dir /= len

	var perp := Vector3(-dir.y, dir.x, 0.0).normalized() * half_w
	var z_off := Vector3(0.0, 0.0, half_z)
	var ext_start := p0 - dir * (half_w * 0.35)
	var ext_end := p1 + dir * (half_w * 0.35)

	# 8 corners of the ribbon segment prism
	var f_tl := ext_start + perp + z_off
	var f_bl := ext_start - perp + z_off
	var f_tr := ext_end + perp + z_off
	var f_br := ext_end - perp + z_off

	var b_tl := ext_start + perp - z_off
	var b_bl := ext_start - perp - z_off
	var b_tr := ext_end + perp - z_off
	var b_br := ext_end - perp - z_off

	var n_front := Vector3(0.0, 0.0, 1.0)
	var n_back := Vector3(0.0, 0.0, -1.0)
	var n_top := perp.normalized()
	var n_bottom := -n_top
	var n_start := -dir
	var n_end := dir

	# Front (+Z)
	_add_quad(st, f_bl, f_br, f_tr, f_tl, n_front, color)
	# Back (-Z)
	_add_quad(st, b_br, b_bl, b_tl, b_tr, n_back, color.darkened(0.08))
	# Top (+perp)
	_add_quad(st, f_tl, f_tr, b_tr, b_tl, n_top, color.lightened(0.08))
	# Bottom (-perp)
	_add_quad(st, b_bl, b_br, f_br, f_bl, n_bottom, color.darkened(0.14))

	if cap_start:
		_add_quad(st, b_bl, f_bl, f_tl, b_tl, n_start, color.darkened(0.05))
	if cap_end:
		_add_quad(st, f_br, b_br, b_tr, f_tr, n_end, color.lightened(0.04))


static func _add_quad(
	st: SurfaceTool,
	v0: Vector3,
	v1: Vector3,
	v2: Vector3,
	v3: Vector3,
	normal: Vector3,
	color: Color
) -> void:
	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v0)

	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(Vector2(1.0, 0.0))
	st.add_vertex(v1)

	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(v2)

	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(Vector2(0.0, 0.0))
	st.add_vertex(v0)

	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(Vector2(1.0, 1.0))
	st.add_vertex(v2)

	st.set_normal(normal)
	st.set_color(color)
	st.set_uv(Vector2(0.0, 1.0))
	st.add_vertex(v3)


static func compute_creation_aabb(creation: CreationData) -> AABB:
	var min_v := Vector3(INF, INF, -0.15)
	var max_v := Vector3(-INF, -INF, 0.15)
	var found := false

	if creation != null:
		var half_z := clampf(creation.extrusion_depth if creation.extrusion_depth > 0.0 else 0.22, 0.06, 0.8) * 0.5
		min_v.z = -half_z
		max_v.z = half_z
		for stroke in creation.strokes:
			if not (stroke is Dictionary):
				continue
			var pts: Array = stroke.get("points", [])
			var pad := clampf(float(stroke.get("thickness", 8.0)), 2.0, 48.0) * SCALE_2D_TO_3D * 0.5
			for raw_pt in pts:
				var p3 := canvas_point_to_3d(_to_vec2(raw_pt))
				min_v.x = minf(min_v.x, p3.x - pad)
				min_v.y = minf(min_v.y, p3.y - pad)
				max_v.x = maxf(max_v.x, p3.x + pad)
				max_v.y = maxf(max_v.y, p3.y + pad)
				found = true

	if not found:
		return AABB(Vector3(-0.4, 0.0, -0.2), Vector3(0.8, 1.8, 0.4))

	var size := (max_v - min_v).max(Vector3(0.35, 0.5, 0.2))
	return AABB(min_v, size)


static func build_collision_shapes_from_creation(creation: CreationData) -> Array[Shape3D]:
	var shapes: Array[Shape3D] = []
	var aabb := compute_creation_aabb(creation)

	if creation != null and creation.creation_type == D4FConstants.CreationType.VEHICLE:
		# Stable chassis BoxShape3D + rounded bumper CapsuleShape3D approximation
		var box := BoxShape3D.new()
		box.size = Vector3(
			clampf(aabb.size.x, 0.9, 2.8),
			clampf(aabb.size.y, 0.45, 1.8),
			clampf(aabb.size.z * 2.5, 0.7, 1.8)
		)
		shapes.append(box)
		return shapes

	# Character or general creation: primary CapsuleShape3D or BoxShape3D bounded to stroke AABB
	var capsule := CapsuleShape3D.new()
	capsule.radius = clampf(maxf(aabb.size.x, aabb.size.z) * 0.32, 0.25, 0.65)
	capsule.height = clampf(aabb.size.y, maxf(capsule.radius * 2.1, 0.9), 2.4)
	shapes.append(capsule)

	# Secondary simplified BoxShape3D for upper torso/arms if wide drawing
	if aabb.size.x > 0.95:
		var limb_box := BoxShape3D.new()
		limb_box.size = Vector3(
			clampf(aabb.size.x * 0.85, 0.6, 1.9),
			clampf(aabb.size.y * 0.45, 0.3, 1.1),
			clampf(aabb.size.z * 1.4, 0.25, 0.6)
		)
		shapes.append(limb_box)

	return shapes


static func build_terrain_stroke_mesh(stroke_dict: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var raw_pts: Array = stroke_dict.get("points", [])
	var road_width: float = clampf(float(stroke_dict.get("width", 4.0)), 1.0, 18.0)
	var road_height: float = clampf(float(stroke_dict.get("height", 0.6)), 0.2, 6.0)
	var y_offset: float = float(stroke_dict.get("y_offset", 0.0))
	var color := Color.from_string(str(stroke_dict.get("color", "#557799")), Color(0.35, 0.48, 0.6))

	var pts_xz: Array[Vector2] = []
	for pt in raw_pts:
		pts_xz.append(_to_vec2(pt))

	var half_w := road_width * 0.5
	var half_h := road_height * 0.5

	if pts_xz.size() == 1:
		var p := pts_xz[0]
		pts_xz.append(p + Vector2(road_width, 0.0))

	for i in range(pts_xz.size() - 1):
		var p0_2d := pts_xz[i]
		var p1_2d := pts_xz[i + 1]
		var diff := p1_2d - p0_2d
		var seg_len := diff.length()
		if seg_len < 0.01:
			continue
		var dir_2d := diff / seg_len
		var perp_2d := Vector2(-dir_2d.y, dir_2d.x) * half_w

		var top_y := y_offset + half_h
		var bot_y := y_offset - half_h

		var t_l0 := Vector3(p0_2d.x + perp_2d.x, top_y, p0_2d.y + perp_2d.y)
		var t_r0 := Vector3(p0_2d.x - perp_2d.x, top_y, p0_2d.y - perp_2d.y)
		var t_l1 := Vector3(p1_2d.x + perp_2d.x, top_y, p1_2d.y + perp_2d.y)
		var t_r1 := Vector3(p1_2d.x - perp_2d.x, top_y, p1_2d.y - perp_2d.y)

		var b_l0 := Vector3(p0_2d.x + perp_2d.x, bot_y, p0_2d.y + perp_2d.y)
		var b_r0 := Vector3(p0_2d.x - perp_2d.x, bot_y, p0_2d.y - perp_2d.y)
		var b_l1 := Vector3(p1_2d.x + perp_2d.x, bot_y, p1_2d.y + perp_2d.y)
		var b_r1 := Vector3(p1_2d.x - perp_2d.x, bot_y, p1_2d.y - perp_2d.y)

		var n_left := Vector3(perp_2d.x, 0.0, perp_2d.y).normalized()
		var n_right := -n_left
		var n_fwd := Vector3(dir_2d.x, 0.0, dir_2d.y).normalized()

		# Top driving surface
		_add_quad(st, t_l0, t_r0, t_r1, t_l1, Vector3.UP, color)
		# Bottom surface
		_add_quad(st, b_r0, b_l0, b_l1, b_r1, Vector3.DOWN, color.darkened(0.2))
		# Left & Right walls
		_add_quad(st, b_l0, t_l0, t_l1, b_l1, n_left, color.darkened(0.1))
		_add_quad(st, t_r0, b_r0, b_r1, t_r1, n_right, color.darkened(0.1))

		if i == 0:
			_add_quad(st, b_r0, b_l0, t_l0, t_r0, -n_fwd, color.darkened(0.08))
		if i == pts_xz.size() - 2:
			_add_quad(st, b_l1, b_r1, t_r1, t_l1, n_fwd, color.darkened(0.08))

	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 0.65
	st.set_material(mat)

	return st.commit()


static func build_terrain_stroke_collision(mesh: ArrayMesh) -> ConcavePolygonShape3D:
	var shape := ConcavePolygonShape3D.new()
	if mesh != null and mesh.get_surface_count() > 0:
		var faces := mesh.get_faces()
		if not faces.is_empty():
			shape.set_faces(faces)
	return shape
