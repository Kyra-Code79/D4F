class_name RaceCompetitionMode
extends CompetitionModeBase
## Mode A: Race Competition Mode.
## Reach the finish line first using custom vehicles or characters. Awards points
## for reaching checkpoints (+25 pts) and finish order (1st: 200, 2nd: 150, 3rd: 120,
## 4th: 90, 5th+: 60). Players respawn at their last checkpoint if they fall.

const CHECKPOINT_POINTS := 25
const FINISH_BONUSES := [200, 150, 120, 90, 60, 50, 40, 30]


func _init() -> void:
	mode_id = D4FConstants.CompetitionMode.RACE
	mode_name = "Race Mode"
	time_limit = 150.0
	allow_respawn = true
	max_lives = 99
	use_vehicles = true


func setup_mode(participants: Array, p_custom_rules: Dictionary = {}) -> void:
	super.setup_mode(participants, p_custom_rules)
	allow_respawn = true
	if not p_custom_rules.has("use_vehicles"):
		use_vehicles = true


func on_player_checkpoint(peer_id: int, checkpoint_idx: int, total_checkpoints: int) -> void:
	if is_match_over or finish_times.has(peer_id):
		return
	var prev_cp := int(checkpoints_reached.get(peer_id, 0))
	if checkpoint_idx > prev_cp:
		var newly_cleared := checkpoint_idx - prev_cp
		checkpoints_reached[peer_id] = checkpoint_idx
		add_score(peer_id, newly_cleared * CHECKPOINT_POINTS)
		if total_checkpoints > 0 and checkpoint_idx > total_checkpoints:
			on_player_finished(peer_id)


func on_player_eliminated(peer_id: int, killer_peer_id: int, _reason: String) -> void:
	if is_match_over or finish_times.has(peer_id):
		return
	# In Race Mode, falling off respawns the racer at their last checkpoint without permanent elimination
	if killer_peer_id > 0 and killer_peer_id != peer_id and knockouts.has(killer_peer_id):
		knockouts[killer_peer_id] = int(knockouts.get(killer_peer_id, 0)) + 1
		add_score(killer_peer_id, 15)


func on_player_finished(peer_id: int) -> void:
	if is_match_over or finish_times.has(peer_id):
		return
	super.on_player_finished(peer_id)
	var finish_order_idx := finish_times.size() - 1
	var bonus := FINISH_BONUSES[mini(finish_order_idx, FINISH_BONUSES.size() - 1)]
	add_score(peer_id, bonus)

	if finish_times.size() >= participant_ids.size():
		is_match_over = true


func tick_mode(delta: float, competitors: Dictionary) -> Dictionary:
	var snap := super.tick_mode(delta, competitors)
	if not is_match_over and participant_ids.size() > 0 and finish_times.size() >= participant_ids.size():
		is_match_over = true
		snap["is_match_over"] = true
	return snap
