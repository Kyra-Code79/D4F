class_name CustomChallengeMode
extends CompetitionModeBase
## Mode D: Custom Challenge Mode.
## Host configures custom_rules: gravity_scale, time_limit, max_lives,
## use_vehicles, points_per_kill, points_per_checkpoint, sudden_death_shrink.

var gravity_scale: float = 1.0
var points_per_kill: int = 100
var points_per_checkpoint: int = 35
var sudden_death_shrink: bool = false
var current_arena_scale: float = 1.0


func _init() -> void:
	mode_id = D4FConstants.CompetitionMode.CUSTOM_CHALLENGE
	mode_name = "Custom Challenge"
	time_limit = 180.0
	allow_respawn = true
	max_lives = 3
	use_vehicles = false


func setup_mode(participants: Array, p_custom_rules: Dictionary = {}) -> void:
	super.setup_mode(participants, p_custom_rules)
	gravity_scale = clampf(float(p_custom_rules.get("gravity_scale", 1.0)), 0.25, 3.0)
	points_per_kill = clampi(int(p_custom_rules.get("points_per_kill", 100)), 0, 500)
	points_per_checkpoint = clampi(int(p_custom_rules.get("points_per_checkpoint", 35)), 0, 250)
	sudden_death_shrink = bool(p_custom_rules.get("sudden_death_shrink", false))
	allow_respawn = max_lives > 1
	current_arena_scale = 1.0


func tick_mode(delta: float, competitors: Dictionary) -> Dictionary:
	if is_match_over:
		return get_mode_status_snapshot()

	if sudden_death_shrink and time_limit > 0.0:
		var progress := clampf(elapsed_time / time_limit, 0.0, 1.0)
		if progress > 0.5:
			var shrink_t := (progress - 0.5) * 2.0
			current_arena_scale = lerpf(1.0, 0.45, shrink_t)

	var snap := super.tick_mode(delta, competitors)
	snap["gravity_scale"] = gravity_scale
	snap["current_arena_scale"] = snappedf(current_arena_scale, 0.01)

	var alive_count := 0
	for pid in participant_ids:
		if not eliminated_peers.has(pid):
			alive_count += 1
	if participant_ids.size() > 1 and alive_count <= 1 and max_lives < 50:
		is_match_over = true
		snap["is_match_over"] = true

	return snap


func on_player_checkpoint(peer_id: int, checkpoint_idx: int, total_checkpoints: int) -> void:
	if is_match_over or eliminated_peers.has(peer_id):
		return
	var prev_cp := int(checkpoints_reached.get(peer_id, 0))
	if checkpoint_idx > prev_cp:
		var gained := checkpoint_idx - prev_cp
		checkpoints_reached[peer_id] = checkpoint_idx
		add_score(peer_id, gained * points_per_checkpoint)
		if total_checkpoints > 0 and checkpoint_idx > total_checkpoints:
			on_player_finished(peer_id)


func on_player_eliminated(peer_id: int, killer_peer_id: int, reason: String) -> void:
	if is_match_over or eliminated_peers.has(peer_id):
		return
	if killer_peer_id > 0 and killer_peer_id != peer_id and scores.has(killer_peer_id):
		add_score(killer_peer_id, points_per_kill)
	super.on_player_eliminated(peer_id, killer_peer_id, reason)


func on_player_finished(peer_id: int) -> void:
	if is_match_over or finish_times.has(peer_id):
		return
	super.on_player_finished(peer_id)
	add_score(peer_id, 150)
