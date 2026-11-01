class_name PhysicsConfigurator
extends RefCounted
## Calculates fair, balanced physics properties from a player's 2D drawing
## so that total competitive budget remains constant and scribbling the entire
## canvas trades speed and jump height for weight and knockback resistance.

const CANVAS_DIM := 512.0
const REFERENCE_INK_LENGTH := 950.0
const MAX_EFFECTIVE_INK_LENGTH := 2600.0


static func compute_balanced_stats(creation: CreationData) -> Dictionary:
	var total_ink_length := 0.0
	var weighted_sum := Vector2.ZERO
	var total_weight := 0.0
	var min_pt := Vector2(CANVAS_DIM, CANVAS_DIM)
	var max_pt := Vector2.ZERO
	var has_points := false
	var wheel_ink := 0.0
	var leg_ink := 0.0
	var bumper_ink := 0.0

	var strokes: Array = []
	if creation != null:
		strokes = creation.strokes

	for stroke in strokes:
		if not (stroke is Dictionary):
			continue
		var pts: Array = stroke.get("points", [])
		var thickness: float = clampf(float(stroke.get("thickness", 8.0)), 2.0, 48.0)
		var part_tag: String = str(stroke.get("part_tag", "body"))
		var thick_factor := clampf(thickness / 8.0, 0.5, 2.5)

		if pts.size() == 1:
			var p := MeshExtruder3D._to_vec2(pts[0])
			var seg_w := 8.0 * thick_factor
			total_ink_length += seg_w
			weighted_sum += p * seg_w
			total_weight += seg_w
			min_pt = min_pt.min(p)
			max_pt = max_pt.max(p)
			has_points = true
		elif pts.size() >= 2:
			for i in range(pts.size() - 1):
				var p0 := MeshExtruder3D._to_vec2(pts[i])
				var p1 := MeshExtruder3D._to_vec2(pts[i + 1])
				var seg_len := p0.distance_to(p1)
				var weighted_len := seg_len * thick_factor
				total_ink_length += weighted_len
				var mid := (p0 + p1) * 0.5
				weighted_sum += mid * maxf(weighted_len, 1.0)
				total_weight += maxf(weighted_len, 1.0)
				min_pt = min_pt.min(p0).min(p1)
				max_pt = max_pt.max(p0).max(p1)
				has_points = true

				if part_tag == "wheel":
					wheel_ink += weighted_len
				elif part_tag == "leg":
					leg_ink += weighted_len
				elif part_tag == "weapon" or part_tag == "bumper":
					bumper_ink += weighted_len

	# Normalized ink ratio in [0.0, 1.0]
	var ink_t := clampf(total_ink_length / MAX_EFFECTIVE_INK_LENGTH, 0.0, 1.0)

	# Bounding box coverage ratio in [0.0, 1.0]
	var bbox_size := Vector2(128.0, 180.0)
	if has_points:
		bbox_size = (max_pt - min_pt).max(Vector2(24.0, 24.0))
	var coverage_ratio := clampf((bbox_size.x * bbox_size.y) / (CANVAS_DIM * CANVAS_DIM), 0.02, 1.0)

	# Combined heaviness factor t in [0.0, 1.0]
	var heaviness_t := clampf(ink_t * 0.68 + coverage_ratio * 0.32, 0.0, 1.0)

	# Center of mass in 3D local coordinates
	var com_2d := Vector2(256.0, 256.0)
	if total_weight > 0.001:
		com_2d = weighted_sum / total_weight
	var com_3d := MeshExtruder3D.canvas_point_to_3d(com_2d)
	# Clamp center of mass offset so extreme asymmetric drawings don't flip uncontrollably
	com_3d.x = clampf(com_3d.x, -0.45, 0.45)
	com_3d.y = clampf(com_3d.y, 0.25, 1.65)
	com_3d.z = 0.0

	# Specialization bonuses within fixed budget
	var wheel_bonus := clampf(wheel_ink / 400.0, 0.0, 0.08)
	var leg_bonus := clampf(leg_ink / 400.0, 0.0, 0.07)
	var bumper_bonus := clampf(bumper_ink / 400.0, 0.0, 0.08)

	# Balanced attributes:
	# Heavy drawings get high mass & knockback_resist, light drawings get high speed, accel & jump
	var mass := clampf(lerpf(40.0, 130.0, heaviness_t), 40.0, 130.0)
	var speed_mult := clampf(lerpf(1.22, 0.82, heaviness_t) + wheel_bonus * 0.5, 0.82, 1.22)
	var accel_mult := clampf(lerpf(1.25, 0.80, heaviness_t) + wheel_bonus * 0.5, 0.80, 1.25)
	var jump_mult := clampf(lerpf(1.18, 0.88, heaviness_t) + leg_bonus, 0.88, 1.18)
	var knockback_resist := clampf(lerpf(0.75, 1.35, heaviness_t) + bumper_bonus, 0.75, 1.35)

	# Lower center of mass and wider stance increase grip; compact shapes increase bounce
	var stance_width_t := clampf(bbox_size.x / 360.0, 0.0, 1.0)
	var grip := clampf(lerpf(0.85, 1.20, stance_width_t * 0.6 + heaviness_t * 0.4), 0.85, 1.20)
	var bounce := clampf(lerpf(0.55, 0.15, heaviness_t * 0.7 + stance_width_t * 0.3), 0.15, 0.55)

	var stats := {
		"mass": snappedf(mass, 0.1),
		"speed_mult": snappedf(speed_mult, 0.01),
		"accel_mult": snappedf(accel_mult, 0.01),
		"jump_mult": snappedf(jump_mult, 0.01),
		"knockback_resist": snappedf(knockback_resist, 0.01),
		"grip": snappedf(grip, 0.01),
		"bounce": snappedf(bounce, 0.01),
		"center_of_mass": [snappedf(com_3d.x, 0.01), snappedf(com_3d.y, 0.01), snappedf(com_3d.z, 0.01)],
		"ink_length": snappedf(total_ink_length, 1.0),
		"coverage_ratio": snappedf(coverage_ratio, 0.01),
		"vertex_estimate": MeshExtruder3D.estimate_vertex_count(strokes),
		"competitive_budget_score": 100.0
	}

	if creation != null:
		creation.physics_stats = stats.duplicate(true)

	return stats
