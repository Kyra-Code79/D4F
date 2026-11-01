class_name MapValidator
extends RefCounted
## Safeguards against impossible, out-of-bounds, or unfair custom maps before
## competition starts. Validates spawn safety, mode requirements, reachability,
## slope angles, arena bounds, and object quota.

const MAX_OBJECT_QUOTA := 200
const MIN_SPAWN_HAZARD_CLEARANCE := 3.5
const MAX_VERTICAL_STEP_WITHOUT_RAMP := 8.5
const MAX_HORIZONTAL_GAP_WITHOUT_SUPPORT := 38.0
const MAX_SLOPE_DEGREES := 62.0


static func _vec3_from_var(v: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if v is Vector3:
		return v
	elif v is Array and v.size() >= 3:
		return Vector3(float(v[0]), float(v[1]), float(v[2]))
	elif v is Dictionary:
		return Vector3(float(v.get("x", fallback.x)), float(v.get("y", fallback.y)), float(v.get("z", fallback.z)))
	return fallback


static func _is_hazard_type(obj_type: String) -> bool:
	var t := obj_type.to_lower()
	return t in ["hazard", "spinner", "bumper", "spike", "lava", "pusher", "wrecking_ball"]


static func _is_support_type(obj_type: String) -> bool:
	var t := obj_type.to_lower()
	return t in ["platform", "road", "ramp", "bridge", "wall", "floor", "block"]


static func validate_map(map_data: MapData, mode: int = 0) -> Dictionary:
	var errors: Array[String] = []
	var warnings: Array[String] = []

	if map_data == null:
		errors.append("MapData is null.")
		return {
			"valid": false,
			"errors": errors,
			"warnings": warnings,
			"metrics": {}
		}

	var effective_mode := mode if mode >= 0 else map_data.target_mode
	var arena_bounds := map_data.arena_size if map_data.arena_size != Vector3.ZERO else Vector3(120.0, 50.0, 120.0)
	var objects: Array = map_data.objects
	var terrain_strokes: Array = map_data.terrain_strokes

	# 5. Object quota check
	if objects.size() > MAX_OBJECT_QUOTA:
		errors.append("Object count (%d) exceeds maximum limit of %d." % [objects.size(), MAX_OBJECT_QUOTA])
	elif objects.size() > int(MAX_OBJECT_QUOTA * 0.85):
		warnings.append("Object count (%d/%d) is approaching the arena quota." % [objects.size(), MAX_OBJECT_QUOTA])

	var spawns: Array[Dictionary] = []
	var checkpoints: Array[Dictionary] = []
	var finishes: Array[Dictionary] = []
	var hazards: Array[Dictionary] = []
	var supports: Array[Dictionary] = []
	var ramps: Array[Dictionary] = []

	for raw_obj in objects:
		if not (raw_obj is Dictionary):
			continue
		var obj: Dictionary = raw_obj
		var obj_type := str(obj.get("type", "platform")).to_lower()
		var pos := _vec3_from_var(obj.get("position", [0.0, 0.0, 0.0]))
		var rot := _vec3_from_var(obj.get("rotation", [0.0, 0.0, 0.0]))

		# 4. Slope & Bounds check
		if absf(pos.x) > arena_bounds.x or absf(pos.z) > arena_bounds.z or pos.y < -15.0 or pos.y > arena_bounds.y:
			errors.append("Object '%s' (%s) at (%.1f, %.1f, %.1f) is outside arena bounds." % [
				str(obj.get("id", "?")), obj_type, pos.x, pos.y, pos.z
			])

		# Handle rotation in degrees or radians
		var pitch_deg := absf(rot.x) if absf(rot.x) > TAU else rad_to_deg(absf(rot.x))
		var roll_deg := absf(rot.z) if absf(rot.z) > TAU else rad_to_deg(absf(rot.z))
		if obj_type in ["ramp", "platform", "road", "bridge"]:
			if pitch_deg > MAX_SLOPE_DEGREES or roll_deg > MAX_SLOPE_DEGREES:
				errors.append("Surface '%s' (%s) has extreme tilt (%.1f deg > %.1f deg max)." % [
					str(obj.get("id", "?")), obj_type, maxf(pitch_deg, roll_deg), MAX_SLOPE_DEGREES
				])

		if obj_type == "start_spawn" or obj_type == "spawn":
			spawns.append(obj)
		elif obj_type == "checkpoint":
			checkpoints.append(obj)
		elif obj_type == "finish_line" or obj_type == "finish" or obj_type == "goal":
			finishes.append(obj)
		elif _is_hazard_type(obj_type):
			hazards.append(obj)

		if _is_support_type(obj_type):
			supports.append(obj)
		if obj_type == "ramp":
			ramps.append(obj)

	# 1. Spawn validation
	if spawns.is_empty():
		errors.append("Map requires at least 1 'start_spawn' point.")
	else:
		for sp in spawns:
			var sp_pos := _vec3_from_var(sp.get("position", [0.0, 0.0, 0.0]))
			for hz in hazards:
				var hz_pos := _vec3_from_var(hz.get("position", [0.0, 0.0, 0.0]))
				var dist := sp_pos.distance_to(hz_pos)
				if dist < MIN_SPAWN_HAZARD_CLEARANCE:
					errors.append("Hazard '%s' is too close (%.1fm < %.1fm) to spawn '%s'." % [
						str(hz.get("id", "hazard")), dist, MIN_SPAWN_HAZARD_CLEARANCE, str(sp.get("id", "spawn"))
					])

	# 2. Mode requirements
	if effective_mode == D4FConstants.CompetitionMode.RACE:
		if finishes.is_empty():
			errors.append("Race Mode requires at least 1 'finish_line' object.")
		if checkpoints.is_empty():
			warnings.append("Race map has no intermediate checkpoints; adding checkpoints is recommended.")
	elif effective_mode == D4FConstants.CompetitionMode.PHYSICS_BATTLE:
		if supports.is_empty() and terrain_strokes.is_empty():
			warnings.append("Physics Battle map has no custom platforms; default arena floor will be used.")

	# Sort checkpoints by order property if present
	checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var props_a: Dictionary = a.get("properties", {}) if a.get("properties") is Dictionary else {}
		var props_b: Dictionary = b.get("properties", {}) if b.get("properties") is Dictionary else {}
		return int(props_a.get("order", 0)) < int(props_b.get("order", 0))
	)

	# 3. Reachability & Fairness check along ordered route
	var route_points: Array[Vector3] = []
	if not spawns.is_empty():
		route_points.append(_vec3_from_var(spawns[0].get("position", [0.0, 0.0, 0.0])))
	for cp in checkpoints:
		route_points.append(_vec3_from_var(cp.get("position", [0.0, 0.0, 0.0])))
	if not finishes.is_empty():
		route_points.append(_vec3_from_var(finishes[0].get("position", [0.0, 0.0, 0.0])))

	var total_route_distance := 0.0
	var max_step_gap := 0.0
	var max_vertical_climb := 0.0

	for i in range(route_points.size() - 1):
		var p0 := route_points[i]
		var p1 := route_points[i + 1]
		var dy := p1.y - p0.y
		var horiz_dist := Vector2(p0.x, p0.z).distance_to(Vector2(p1.x, p1.z))
		total_route_distance += p0.distance_to(p1)
		max_step_gap = maxf(max_step_gap, horiz_dist)
		max_vertical_climb = maxf(max_vertical_climb, dy)

		if dy > MAX_VERTICAL_STEP_WITHOUT_RAMP:
			var has_bridging_ramp := _has_intermediate_support(p0, p1, ramps, terrain_strokes)
			if not has_bridging_ramp:
				errors.append("Unreachable vertical climb of %.1fm between route nodes %d and %d without a ramp." % [
					dy, i, i + 1
				])

		if horiz_dist > MAX_HORIZONTAL_GAP_WITHOUT_SUPPORT:
			var has_intermediate := _has_intermediate_support(p0, p1, supports, terrain_strokes)
			if not has_intermediate:
				errors.append("Unreachable horizontal gap of %.1fm between route nodes %d and %d without platforms or terrain." % [
					horiz_dist, i, i + 1
				])

	var metrics := {
		"object_count": objects.size(),
		"terrain_stroke_count": terrain_strokes.size(),
		"spawn_count": spawns.size(),
		"checkpoint_count": checkpoints.size(),
		"finish_count": finishes.size(),
		"hazard_count": hazards.size(),
		"route_distance": snappedf(total_route_distance, 0.1),
		"max_horizontal_gap": snappedf(max_step_gap, 0.1),
		"max_vertical_climb": snappedf(max_vertical_climb, 0.1)
	}

	return {
		"valid": errors.is_empty(),
		"errors": errors,
		"warnings": warnings,
		"metrics": metrics
	}


static func _has_intermediate_support(
	p0: Vector3,
	p1: Vector3,
	support_objects: Array[Dictionary],
	terrain_strokes: Array
) -> bool:
	var mid := (p0 + p1) * 0.5
	var seg_len := p0.distance_to(p1)
	var search_radius := maxf(18.0, seg_len * 0.48)

	for sup in support_objects:
		var pos := _vec3_from_var(sup.get("position", [0.0, 0.0, 0.0]))
		if pos.distance_to(mid) <= search_radius:
			return true

	for stroke in terrain_strokes:
		if not (stroke is Dictionary):
			continue
		var pts: Array = stroke.get("points", [])
		var y_off := float(stroke.get("y_offset", 0.0))
		for raw_pt in pts:
			var p2 := MeshExtruder3D._to_vec2(raw_pt)
			var p3 := Vector3(p2.x, y_off, p2.y)
			if p3.distance_to(mid) <= search_radius:
				return true

	return false
