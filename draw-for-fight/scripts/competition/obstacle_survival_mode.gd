class_name ObstacleSurvivalMode
extends CompetitionModeBase
## Mode B: Obstacle Survival Mode.
## Navigate a hazardous obstacle course without falling (`allow_respawn = false`, 1 life).
## Tracks survival_times, awards survival points per second alive, and grants +150 bonus
## to the last surviving player.

const POINTS_PER_SECOND_ALIVE := 5
const LAST_SURVIVOR_BONUS := 150
const CHECKPOINT_SURVIVAL_BONUS := 30

var _second_accumulator: float = 0.0
var _last_survivor_awarded: bool = false


func _init() -> void:
	mode_id = D4FConstants.CompetitionMode.OBSTACLE_SURVIVAL
	mode_name = "Obstacle Survival"
	time_limit = 120.0
	allow_respawn = false
	max_lives = 1
	use_vehicles = false


func setup_mode(participants: Array, p_custom_rules: Dictionary = {}) -> void:
	super.setup_mode(participants, p_custom_rules)
	allow_respawn = false
	max_lives = 1
	_second_accumulator = 0.0
	_last_survivor_awarded = false
	for pid in participant_ids:
		lives_left[pid] = 1


func tick_mode(delta: float, competitors: Dictionary) -> Dictionary:
	if is_match_over:
		return get_mode_status_snapshot()

	_second_accumulator += delta
	while _second_accumulator >= 1.0:
		_second_accumulator -= 1.0
		for pid in participant_ids:
			if not eliminated_peers.has(pid):
				add_score(pid, POINTS_PER_SECOND_ALIVE)

	var snap := super.tick_mode(delta, competitors)
	_check_survival_end_condition()
	snap["is_match_over"] = is_match_over
	snap["rankings"] = compute_rankings()
	return snap


func on_player_checkpoint(peer_id: int, checkpoint_idx: int, _total_checkpoints: int) -> void:
	if is_match_over or eliminated_peers.has(peer_id):
		return
	var prev_cp := int(checkpoints_reached.get(peer_id, 0))
	if checkpoint_idx > prev_cp:
		checkpoints_reached[peer_id] = checkpoint_idx
		add_score(peer_id, (checkpoint_idx - prev_cp) * CHECKPOINT_SURVIVAL_BONUS)


func on_player_eliminated(peer_id: int, killer_peer_id: int, reason: String) -> void:
	if is_match_over or eliminated_peers.has(peer_id):
		return
	super.on_player_eliminated(peer_id, killer_peer_id, reason)
	_check_survival_end_condition()


func on_player_finished(peer_id: int) -> void:
	if is_match_over or eliminated_peers.has(peer_id) or finish_times.has(peer_id):
		return
	super.on_player_finished(peer_id)
	add_score(peer_id, LAST_SURVIVOR_BONUS)
	if participant_ids.size() <= 1:
		is_match_over = true


func _check_survival_end_condition() -> void:
	var alive_peers: Array[int] = []
	for pid in participant_ids:
		if not eliminated_peers.has(pid):
			alive_peers.append(pid)

	if participant_ids.size() > 1 and alive_peers.size() <= 1:
		if alive_peers.size() == 1 and not _last_survivor_awarded:
			_last_survivor_awarded = true
			add_score(alive_peers[0], LAST_SURVIVOR_BONUS)
		is_match_over = true
	elif participant_ids.size() == 1 and alive_peers.is_empty():
		is_match_over = true
