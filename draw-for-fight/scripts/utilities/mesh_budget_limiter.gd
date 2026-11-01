class_name MeshBudgetLimiter
extends RefCounted

static func simplify_polyline_rdp(points: PackedVector2Array, epsilon: float = 2.5) -> PackedVector2Array:
	var n := points.size()
	if n <= 2:
		return points

	var start_pt := points[0]
	var end_pt := points[n - 1]
	var max_dist := -1.0
	var max_idx := 0

	for i in range(1, n - 1):
		var d := _perpendicular_distance(points[i], start_pt, end_pt)
		if d > max_dist:
			max_dist = d
			max_idx = i

	if max_dist > epsilon and max_idx > 0 and max_idx < n - 1:
		var left_slice := points.slice(0, max_idx + 1)
		var right_slice := points.slice(max_idx, n)
		var left_res := simplify_polyline_rdp(left_slice, epsilon)
		var right_res := simplify_polyline_rdp(right_slice, epsilon)

		var combined := PackedVector2Array()
		for i in range(left_res.size() - 1):
			combined.append(left_res[i])
		for i in range(right_res.size()):
			combined.append(right_res[i])
		return combined
	else:
		var result := PackedVector2Array()
		result.append(start_pt)
		result.append(end_pt)
		return result

static func _perpendicular_distance(pt: Vector2, line_start: Vector2, line_end: Vector2) -> float:
	var seg := line_end - line_start
	var len_sq := seg.length_squared()
	if len_sq < 0.0001:
		return pt.distance_to(line_start)
	var t := clampf((pt - line_start).dot(seg) / len_sq, 0.0, 1.0)
	var proj := line_start + seg * t
	return pt.distance_to(proj)

static func estimate_vertex_count(strokes: Array) -> int:
	var total_vertices := 0
	for s in strokes:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s
		var pts: Variant = sd.get("points", [])
		var pt_count := 0
		if typeof(pts) == TYPE_ARRAY:
			pt_count = (pts as Array).size()
		elif typeof(pts) == TYPE_PACKED_VECTOR2_ARRAY:
			pt_count = (pts as PackedVector2Array).size()
		if pt_count >= 2:
			# 4 vertices per polyline point along the extruded tube + 8 cap vertices
			total_vertices += pt_count * 4 + 8
	return total_vertices

static func enforce_creation_budget(creation: CreationData) -> CreationData:
	if creation == null:
		return CreationData.create_default_stickman()

	if creation.strokes.size() > D4FConstants.MAX_STROKES_PER_CREATION:
		creation.strokes = creation.strokes.slice(0, D4FConstants.MAX_STROKES_PER_CREATION)

	var cleaned_strokes: Array = []
	for s in creation.strokes:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s
		var raw_pts: Variant = sd.get("points", [])
		var pv2 := PackedVector2Array()

		if typeof(raw_pts) == TYPE_ARRAY:
			for p in (raw_pts as Array):
				var v := D4FSerializer.array_to_vec2(p, Vector2(256.0, 256.0))
				pv2.append(Vector2(clampf(v.x, 0.0, 512.0), clampf(v.y, 0.0, 512.0)))
		elif typeof(raw_pts) == TYPE_PACKED_VECTOR2_ARRAY:
			for v in (raw_pts as PackedVector2Array):
				pv2.append(Vector2(clampf(v.x, 0.0, 512.0), clampf(v.y, 0.0, 512.0)))

		if pv2.size() < 2:
			continue

		if pv2.size() > D4FConstants.MAX_POINTS_PER_STROKE:
			pv2 = simplify_polyline_rdp(pv2, 2.0)
			if pv2.size() > D4FConstants.MAX_POINTS_PER_STROKE:
				pv2 = pv2.slice(0, D4FConstants.MAX_POINTS_PER_STROKE)

		var out_pts: Array = []
		for pt in pv2:
			out_pts.append([snappedf(pt.x, 0.01), snappedf(pt.y, 0.01)])

		cleaned_strokes.append({
			"points": out_pts,
			"color": String(sd.get("color", "#33aaff")),
			"thickness": clampf(D4FSerializer.sanitize_float(sd.get("thickness", 8.0), 8.0), 2.0, 28.0),
			"part_tag": String(sd.get("part_tag", "body"))
		})

	creation.strokes = cleaned_strokes

	var epsilons: Array[float] = [2.5, 5.0, 9.0, 15.0, 24.0]
	for eps in epsilons:
		if estimate_vertex_count(creation.strokes) <= D4FConstants.MAX_VERTICES_PER_MESH:
			break
		for i in range(creation.strokes.size()):
			var sd: Dictionary = creation.strokes[i]
			var arr_pts: Array = sd.get("points", [])
			var pv := PackedVector2Array()
			for p in arr_pts:
				pv.append(D4FSerializer.array_to_vec2(p))
			var simplified := simplify_polyline_rdp(pv, eps)
			var new_arr: Array = []
			for pt in simplified:
				new_arr.append([snappedf(pt.x, 0.01), snappedf(pt.y, 0.01)])
			sd["points"] = new_arr
			creation.strokes[i] = sd

	creation.compute_checksum()
	return creation
