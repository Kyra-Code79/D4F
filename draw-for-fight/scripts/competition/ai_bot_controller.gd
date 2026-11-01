class_name AIBotController
extends RefCounted
## Steers NPC Bot competitors across Race, Obstacle Survival, Physics Battle,
## and Custom Challenge modes. Computes waypoint navigation, hazard avoidance,
## edge recovery, and melee shove / vehicle boost decisions.

var _wander_timers: Dictionary = {}
var _wander_offsets: Dictionary = {}


func compute_bot_input(
	bot_node: Node3D,
	map_data: MapData,
	all_competitors: Dictionary,
	mode: int,
	delta: float
) -> Dictionary:
	var default_out := {
		"move_dir": Vector2.ZERO,
		"throttle": 0.0,
		"steering": 0.0,
		"brake": false,
		"jump": false,
		"shove": false,
		"boost": false
	}

	if bot_node == null or not is_instance_valid(bot_node):
		return default_out
	if bool(bot_node.get("is_eliminated")):
		return default_out

	var peer_id := int(bot_node.get("peer_id"))
	var bot_pos := bot_node.global_position

	# Update subtle per-bot personality offset so bots don't stack on a single line
	var t_left := float(_wander_timers.get(peer_id, 0.0)) - delta
	if t_left <= 0.0:
		_wander_timers[peer_id] = randf_range(1.2, 2.8)
		_wander_offsets[peer_id] = Vector3(randf_range(-2.2, 2.2), 0.0, randf_range(-2.2, 2.2))
	else:
		_wander_timers[peer_id] = t_left
	var lane_offset: Vector3 = _wander_offsets.get(peer_id, Vector3.ZERO)

	var target_pos := Vector3.ZERO
	var should_shove := false
	var should_jump := false
	var should_boost := false

	if mode == D4FConstants.CompetitionMode.PHYSICS_BATTLE:
		var combat_info := _select_physics_battle_target(bot_node, all_competitors, map_data)
		target_pos = combat_info["target_pos"]
		should_shove = bool(combat_info["should_shove"])
		should_jump = bool(combat_info["should_jump"])
	else:
		var nav_info := _select_course_waypoint(bot_node, map_data, lane_offset)
		target_pos = nav_info["target_pos"]
		should_jump = bool(nav_info["should_jump"])
		should_boost = bool(nav_info["should_boost"])
		# Also shove if an opponent is right in front of the bot
		should_shove = _has_adjacent_opponent(bot_node, all_competitors, 2.35)

	# Hazard avoidance nudge
	var avoidance := _compute_hazard_avoidance(bot_pos, map_data)
	var to_target := (target_pos - bot_pos)
	var vertical_gap := to_target.y
	to_target.y = 0.0
	var horiz_dist := to_target.length()

	var desired_dir_3d := Vector3.FORWARD
	if horiz_dist > 0.25:
		desired_dir_3d = (to_target.normalized() + avoidance * 0.65).normalized()
	elif avoidance.length_squared() > 0.05:
		desired_dir_3d = avoidance.normalized()

	if vertical_gap > 1.35 and horiz_dist < 8.5:
		should_jump = true

	var move_dir_2d := Vector2(desired_dir_3d.x, desired_dir_3d.z).limit_length(1.0)

	# Vehicle throttle & steering computation relative to bot's forward (-Z) basis
	var fwd := -bot_node.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	else:
		fwd = fwd.normalized()

	var right := bot_node.global_transform.basis.x
	right.y = 0.0
	right = right.normalized() if right.length_squared() > 0.001 else Vector3.RIGHT

	var forward_dot := fwd.dot(desired_dir_3d)
	var right_dot := right.dot(desired_dir_3d)
	var steering := clampf(-right_dot * 1.85, -1.0, 1.0)
	var throttle := clampf(forward_dot, 0.35, 1.0)
	if forward_dot < -0.35 and horiz_dist > 4.0:
		steering = -1.0 if right_dot >= 0.0 else 1.0
		throttle = 0.55

	if should_boost and forward_dot > 0.82 and horiz_dist > 12.0:
		should_boost = true
	else:
		should_boost = false

	return {
		"move_dir": move_dir_2d,
		"throttle": throttle,
		"steering": steering,
		"brake": false,
		"jump": should_jump,
		"shove": should_shove,
		"boost": should_boost
	}


func _select_course_waypoint(bot_node: Node3D, map_data: MapData, lane_offset: Vector3) -> Dictionary:
	var bot_pos := bot_node.global_position
	var cur_cp := int(bot_node.get("current_checkpoint"))
	var checkpoints: Array[Dictionary] = []
	var finish_pos := Vector3(0.0, 0.5, -45.0)
	var has_finish := false

	if map_data != null:
		for raw_obj in map_data.objects:
			if not (raw_obj is Dictionary):
				continue
			var obj: Dictionary = raw_obj
			var t := str(obj.get("type", "")).to_lower()
			if t == "checkpoint":
				checkpoints.append(obj)
			elif t in ["finish_line", "finish", "goal"]:
				finish_pos = MapValidator._vec3_from_var(obj.get("position", [0.0, 0.5, -45.0]))
				has_finish = true

	checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Dictionary = a.get("properties", {}) if a.get("properties") is Dictionary else {}
		var pb: Dictionary = b.get("properties", {}) if b.get("properties") is Dictionary else {}
		return int(pa.get("order", 0)) < int(pb.get("order", 0))
	)

	var wp := finish_pos
	if cur_cp < checkpoints.size():
		wp = MapValidator._vec3_from_var(checkpoints[cur_cp].get("position", [0.0, 0.5, -20.0]))
	elif not has_finish and not checkpoints.is_empty():
		wp = MapValidator._vec3_from_var(checkpoints[checkpoints.size() - 1].get("position", [0.0, 0.5, -20.0]))

	wp += lane_offset * 0.65
	var dist := bot_pos.distance_to(wp)
	var jump_chance := (wp.y - bot_pos.y > 1.1 and dist < 7.0)
	var boost_chance := (dist > 14.0)

	return {
		"target_pos": wp,
		"should_jump": jump_chance,
		"should_boost": boost_chance
	}


func _select_physics_battle_target(bot_node: Node3D, all_competitors: Dictionary, map_data: MapData) -> Dictionary:
	var bot_pos := bot_node.global_position
	var arena_center := Vector3.ZERO
	var safe_radius := 22.0
	if map_data != null and map_data.arena_size != Vector3.ZERO:
		safe_radius = minf(map_data.arena_size.x, map_data.arena_size.z) * 0.35

	# If near the arena edge, prioritize returning toward center
	var dist_from_center := Vector2(bot_pos.x, bot_pos.z).length()
	if dist_from_center > safe_radius:
		return {
			"target_pos": arena_center,
			"should_shove": _has_adjacent_opponent(bot_node, all_competitors, 2.8),
			"should_jump": true
		}

	var nearest_enemy_pos := arena_center
	var best_dist := INF
	for pid in all_competitors.keys():
		var other: Variant = all_competitors[pid]
		if other == null or other == bot_node or not is_instance_valid(other):
			continue
		if not (other is Node3D) or bool(other.get("is_eliminated")):
			continue
		var enemy_node := other as Node3D
		var d := bot_pos.distance_to(enemy_node.global_position)
		if d < best_dist:
			best_dist = d
			nearest_enemy_pos = enemy_node.global_position

	return {
		"target_pos": nearest_enemy_pos,
		"should_shove": best_dist <= 2.9,
		"should_jump": best_dist < 4.5 and randf() < 0.04
	}


func _has_adjacent_opponent(bot_node: Node3D, all_competitors: Dictionary, radius: float) -> bool:
	var bot_pos := bot_node.global_position
	for pid in all_competitors.keys():
		var other: Variant = all_competitors[pid]
		if other == null or other == bot_node or not is_instance_valid(other):
			continue
		if not (other is Node3D) or bool(other.get("is_eliminated")):
			continue
		if bot_pos.distance_to((other as Node3D).global_position) <= radius:
			return true
	return false


func _compute_hazard_avoidance(bot_pos: Vector3, map_data: MapData) -> Vector3:
	if map_data == null:
		return Vector3.ZERO
	var repel := Vector3.ZERO
	for raw_obj in map_data.objects:
		if not (raw_obj is Dictionary):
			continue
		var obj: Dictionary = raw_obj
		var t := str(obj.get("type", "")).to_lower()
		if MapValidator._is_hazard_type(t):
			var h_pos := MapValidator._vec3_from_var(obj.get("position", [0.0, 0.0, 0.0]))
			var diff := bot_pos - h_pos
			diff.y = 0.0
			var d := diff.length()
			if d < 5.5 and d > 0.01:
				repel += diff.normalized() * ((5.5 - d) / 5.5)
	return repel
