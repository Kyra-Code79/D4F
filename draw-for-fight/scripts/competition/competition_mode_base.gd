class_name CompetitionModeBase
extends RefCounted
## Base interface and deterministic scoring/tie-breaker engine for all D4F competition modes.

var mode_id: int = D4FConstants.CompetitionMode.RACE
var mode_name: String = "Competition"
var time_limit: float = 180.0
var elapsed_time: float = 0.0
var allow_respawn: bool = true
var max_lives: int = 3
var use_vehicles: bool = false

var scores: Dictionary = {}
var eliminated_peers: Array = []
var finish_times: Dictionary = {}
var is_match_over: bool = false

var participant_ids: Array[int] = []
var participant_names: Dictionary = {}
var survival_times: Dictionary = {}
var checkpoints_reached: Dictionary = {}
var knockouts: Dictionary = {}
var lives_left: Dictionary = {}
var custom_rules: Dictionary = {}


func setup_mode(participants: Array, p_custom_rules: Dictionary = {}) -> void:
	custom_rules = p_custom_rules.duplicate(true)
	elapsed_time = 0.0
	is_match_over = false
	scores.clear()
	eliminated_peers.clear()
	finish_times.clear()
	participant_ids.clear()
	participant_names.clear()
	survival_times.clear()
	checkpoints_reached.clear()
	knockouts.clear()
	lives_left.clear()

	if custom_rules.has("time_limit"):
		time_limit = clampf(float(custom_rules["time_limit"]), 20.0, 900.0)
	if custom_rules.has("max_lives"):
		max_lives = maxi(1, int(custom_rules["max_lives"]))
	if custom_rules.has("use_vehicles"):
		use_vehicles = bool(custom_rules["use_vehicles"])

	for entry in participants:
		var pid := 1
		var pname := "Player"
		if entry is int:
			pid = entry
			pname = "Player %d" % pid
		elif entry is Dictionary:
			pid = int(entry.get("peer_id", entry.get("id", 1)))
			pname = str(entry.get("name", "Player %d" % pid))
		if not participant_ids.has(pid):
			participant_ids.append(pid)
		participant_names[pid] = pname
		scores[pid] = 0
		survival_times[pid] = 0.0
		checkpoints_reached[pid] = 0
		knockouts[pid] = 0
		lives_left[pid] = max_lives


func tick_mode(delta: float, _competitors: Dictionary) -> Dictionary:
	if is_match_over:
		return get_mode_status_snapshot()

	elapsed_time += delta
	for pid in participant_ids:
		if not eliminated_peers.has(pid) and not finish_times.has(pid):
			survival_times[pid] = float(survival_times.get(pid, 0.0)) + delta

	if elapsed_time >= time_limit:
		is_match_over = true

	return get_mode_status_snapshot()


func on_player_checkpoint(peer_id: int, checkpoint_idx: int, _total_checkpoints: int) -> void:
	if is_match_over or eliminated_peers.has(peer_id):
		return
	var prev_cp := int(checkpoints_reached.get(peer_id, 0))
	if checkpoint_idx > prev_cp:
		checkpoints_reached[peer_id] = checkpoint_idx


func on_player_eliminated(peer_id: int, killer_peer_id: int, _reason: String) -> void:
	if is_match_over or eliminated_peers.has(peer_id):
		return
	if killer_peer_id > 0 and killer_peer_id != peer_id and knockouts.has(killer_peer_id):
		knockouts[killer_peer_id] = int(knockouts.get(killer_peer_id, 0)) + 1

	var rem := int(lives_left.get(peer_id, 1)) - 1
	lives_left[peer_id] = maxi(0, rem)
	if not allow_respawn or rem <= 0:
		if not eliminated_peers.has(peer_id):
			eliminated_peers.append(peer_id)


func on_player_finished(peer_id: int) -> void:
	if is_match_over or finish_times.has(peer_id) or eliminated_peers.has(peer_id):
		return
	finish_times[peer_id] = snappedf(elapsed_time, 0.01)


func add_score(peer_id: int, delta_points: int) -> void:
	scores[peer_id] = int(scores.get(peer_id, 0)) + delta_points


func compute_rankings() -> Array:
	var rows: Array = []
	for pid in participant_ids:
		var fin_t := float(finish_times.get(pid, -1.0))
		rows.append({
			"peer_id": pid,
			"name": str(participant_names.get(pid, "Player %d" % pid)),
			"score": int(scores.get(pid, 0)),
			"finish_time": fin_t,
			"has_finished": finish_times.has(pid),
			"survival_time": snappedf(float(survival_times.get(pid, 0.0)), 0.01),
			"checkpoints": int(checkpoints_reached.get(pid, 0)),
			"knockouts": int(knockouts.get(pid, 0)),
			"lives_remaining": int(lives_left.get(pid, 0)),
			"eliminated": eliminated_peers.has(pid)
		})

	# Deterministic tie-breaking:
	# 1. score (DESC)
	# 2. finish_time (finished players beat unfinished; lower finish_time wins)
	# 3. survival_time (DESC)
	# 4. checkpoints (DESC)
	# 5. knockouts (DESC)
	# 6. peer_id (ASC)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if int(a["score"]) != int(b["score"]):
			return int(a["score"]) > int(b["score"])
		var a_fin := bool(a["has_finished"])
		var b_fin := bool(b["has_finished"])
		if a_fin != b_fin:
			return a_fin
		if a_fin and b_fin and not is_equal_approx(float(a["finish_time"]), float(b["finish_time"])):
			return float(a["finish_time"]) < float(b["finish_time"])
		if not is_equal_approx(float(a["survival_time"]), float(b["survival_time"])):
			return float(a["survival_time"]) > float(b["survival_time"])
		if int(a["checkpoints"]) != int(b["checkpoints"]):
			return int(a["checkpoints"]) > int(b["checkpoints"])
		if int(a["knockouts"]) != int(b["knockouts"]):
			return int(a["knockouts"]) > int(b["knockouts"])
		return int(a["peer_id"]) < int(b["peer_id"])
	)

	for i in range(rows.size()):
		rows[i]["rank"] = i + 1

	return rows


func get_mode_status_snapshot() -> Dictionary:
	return {
		"mode_id": mode_id,
		"mode_name": mode_name,
		"elapsed_time": snappedf(elapsed_time, 0.05),
		"time_remaining": maxf(0.0, snappedf(time_limit - elapsed_time, 0.05)),
		"is_match_over": is_match_over,
		"scores": scores.duplicate(),
		"eliminated_peers": eliminated_peers.duplicate(),
		"finish_times": finish_times.duplicate(),
		"lives_left": lives_left.duplicate(),
		"rankings": compute_rankings()
	}
