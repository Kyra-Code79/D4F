extends Node
## Autoload Singleton: MatchManager
## Authoritative competition coordinator on the Host PC.
## Manages countdown, match timer, mode rules, scoring, eliminations, respawns,
## deterministic tie-breaking, final rankings, and rematch voting.

signal countdown_tick(seconds_remaining: int)
signal match_started(mode: int, time_limit: float)
signal match_timer_updated(seconds_remaining: float, elapsed: float)
signal player_scored(peer_id: int, delta_points: int, new_total: int, reason: String)
signal player_checkpoint_updated(peer_id: int, checkpoint_idx: int)
signal player_eliminated(peer_id: int, killer_peer_id: int, reason: String)
signal player_respawn_scheduled(peer_id: int, delay_sec: float)
signal match_ended(rankings: Array, winner: Dictionary)
signal rematch_initiated(match_number: int)

enum MatchPhase {
	IDLE,
	PREP_COUNTDOWN,
	ACTIVE,
	OVERTIME_TIEBREAKER,
	FINISHED
}

var current_phase: int = MatchPhase.IDLE
var active_mode_id: int = D4FConstants.CompetitionMode.RACE
var active_mode_instance: CompetitionModeBase = null
var custom_rules: Dictionary = {
	"time_limit": 180.0,
	"max_lives": 3,
	"gravity_scale": 1.0,
	"use_vehicles": false,
	"points_per_kill": 100,
	"points_per_checkpoint": 25,
	"sudden_death_shrink": true
}

var countdown_remaining: float = 3.0
var match_time_limit: float = 180.0
var match_elapsed: float = 0.0
var match_number: int = 1
var is_authoritative_host: bool = true

var participants: Dictionary = {} # peer_id -> participant state dict
var last_match_rankings: Array = []
var last_match_winner: Dictionary = {}
var rematch_votes: Dictionary = {}

func _process(delta: float) -> void:
	if current_phase == MatchPhase.PREP_COUNTDOWN:
		var prev_ceil := ceili(countdown_remaining)
		countdown_remaining -= delta
		var new_ceil := ceili(countdown_remaining)
		if new_ceil != prev_ceil and new_ceil > 0:
			countdown_tick.emit(new_ceil)
			if has_node("/root/AudioManager"):
				get_node("/root/AudioManager").play_sfx("countdown_tick")
		if countdown_remaining <= 0.0:
			_begin_active_competition()
	elif current_phase == MatchPhase.ACTIVE or current_phase == MatchPhase.OVERTIME_TIEBREAKER:
		match_elapsed += delta
		var remaining := maxf(0.0, match_time_limit - match_elapsed)
		match_timer_updated.emit(remaining, match_elapsed)
		if is_authoritative_host:
			_tick_authoritative_mode(delta, remaining)

func setup_match(mode_id: int, player_list: Array, rules: Dictionary = {}, is_host: bool = true) -> void:
	active_mode_id = mode_id
	is_authoritative_host = is_host
	for k in rules.keys():
		custom_rules[k] = rules[k]

	match_time_limit = float(custom_rules.get("time_limit", D4FConstants.DEFAULT_MATCH_TIME_SEC))
	match_elapsed = 0.0
	countdown_remaining = 3.0
	rematch_votes.clear()
	participants.clear()

	for p in player_list:
		var pid := int(p.get("id", 1))
		participants[pid] = {
			"id": pid,
			"name": String(p.get("name", "Player_" + str(pid))),
			"is_bot": bool(p.get("is_bot", false)),
			"score": 0,
			"checkpoints": 0,
			"eliminations": 0,
			"deaths": 0,
			"lives": int(custom_rules.get("max_lives", 3)),
			"eliminated": false,
			"finished": false,
			"finish_time": 999999.0,
			"survival_time": 0.0,
			"creation": p.get("creation", {})
		}

	active_mode_instance = _instantiate_mode(mode_id)
	if active_mode_instance != null:
		active_mode_instance.setup_mode(participants.values(), custom_rules)
		match_time_limit = active_mode_instance.time_limit

func start_countdown(seconds: float = 3.0) -> void:
	countdown_remaining = maxf(0.5, seconds)
	current_phase = MatchPhase.PREP_COUNTDOWN
	countdown_tick.emit(ceili(countdown_remaining))

func _begin_active_competition() -> void:
	current_phase = MatchPhase.ACTIVE
	match_elapsed = 0.0
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("countdown_go")
	match_started.emit(active_mode_id, match_time_limit)

func _instantiate_mode(mode_id: int) -> CompetitionModeBase:
	match mode_id:
		D4FConstants.CompetitionMode.RACE:
			return RaceCompetitionMode.new()
		D4FConstants.CompetitionMode.OBSTACLE_SURVIVAL:
			return ObstacleSurvivalMode.new()
		D4FConstants.CompetitionMode.PHYSICS_BATTLE:
			return PhysicsBattleMode.new()
		D4FConstants.CompetitionMode.CUSTOM_CHALLENGE:
			return CustomChallengeMode.new()
		_:
			return RaceCompetitionMode.new()

func _tick_authoritative_mode(delta: float, remaining_sec: float) -> void:
	for pid in participants.keys():
		var p: Dictionary = participants[pid]
		if not bool(p.get("eliminated", false)) and not bool(p.get("finished", false)):
			p["survival_time"] = float(p.get("survival_time", 0.0)) + delta

	if active_mode_instance != null:
		var status: Dictionary = active_mode_instance.tick_mode(delta, participants)
		if bool(status.get("match_over", false)):
			finalize_match()
			return

	if remaining_sec <= 0.0:
		finalize_match()

## Authoritative event handlers (never trust unvalidated client scores)
func record_checkpoint(peer_id: int, checkpoint_index: int, total_checkpoints: int = 3) -> void:
	if not is_authoritative_host or current_phase != MatchPhase.ACTIVE:
		return
	if not participants.has(peer_id):
		return
	var p: Dictionary = participants[peer_id]
	if bool(p.get("eliminated", false)) or bool(p.get("finished", false)):
		return
	if checkpoint_index <= int(p.get("checkpoints", 0)):
		return # Already reached this checkpoint

	p["checkpoints"] = checkpoint_index
	var pts := int(custom_rules.get("points_per_checkpoint", 25))
	add_authoritative_score(peer_id, pts, "Checkpoint #" + str(checkpoint_index))
	if active_mode_instance != null:
		active_mode_instance.on_player_checkpoint(peer_id, checkpoint_index, total_checkpoints)
	player_checkpoint_updated.emit(peer_id, checkpoint_index)

func record_finish_line(peer_id: int) -> void:
	if not is_authoritative_host or current_phase != MatchPhase.ACTIVE:
		return
	if not participants.has(peer_id):
		return
	var p: Dictionary = participants[peer_id]
	if bool(p.get("finished", false)) or bool(p.get("eliminated", false)):
		return

	p["finished"] = true
	p["finish_time"] = match_elapsed
	var finished_count := 0
	for other in participants.values():
		if bool(other.get("finished", false)):
			finished_count += 1

	var placement_bonus: Array[int] = [200, 150, 120, 95, 75, 60, 45, 30]
	var bonus := placement_bonus[clampi(finished_count - 1, 0, placement_bonus.size() - 1)]
	add_authoritative_score(peer_id, bonus, "Finished #" + str(finished_count))

	if active_mode_instance != null:
		active_mode_instance.on_player_finished(peer_id)

	# In Race mode, if all active players have finished, end match immediately
	var all_done := true
	for other in participants.values():
		if not bool(other.get("finished", false)) and not bool(other.get("eliminated", false)):
			all_done = false
			break
	if all_done:
		finalize_match()

func record_elimination(victim_peer_id: int, killer_peer_id: int = -1, reason: String = "ring_out") -> Dictionary:
	if not is_authoritative_host or current_phase != MatchPhase.ACTIVE:
		return {"eliminated_permanently": false, "respawn": false}
	if not participants.has(victim_peer_id):
		return {"eliminated_permanently": false, "respawn": false}

	var victim: Dictionary = participants[victim_peer_id]
	if bool(victim.get("eliminated", false)):
		return {"eliminated_permanently": true, "respawn": false}

	victim["deaths"] = int(victim.get("deaths", 0)) + 1
	victim["lives"] = max(0, int(victim.get("lives", 1)) - 1)

	if killer_peer_id > 0 and killer_peer_id != victim_peer_id and participants.has(killer_peer_id):
		var killer: Dictionary = participants[killer_peer_id]
		killer["eliminations"] = int(killer.get("eliminations", 0)) + 1
		var kill_pts := int(custom_rules.get("points_per_kill", 100))
		add_authoritative_score(killer_peer_id, kill_pts, "Eliminated " + String(victim.get("name", "Opponent")))

	if active_mode_instance != null:
		active_mode_instance.on_player_eliminated(victim_peer_id, killer_peer_id, reason)

	var can_respawn := should_respawn(victim_peer_id)
	if not can_respawn:
		victim["eliminated"] = true
		victim["survival_time"] = match_elapsed
		player_eliminated.emit(victim_peer_id, killer_peer_id, reason)
		_check_last_survivor_win()
		return {"eliminated_permanently": true, "respawn": false}
	else:
		player_respawn_scheduled.emit(victim_peer_id, 2.0)
		return {"eliminated_permanently": false, "respawn": true}

func should_respawn(peer_id: int) -> bool:
	if not participants.has(peer_id):
		return false
	if active_mode_id == D4FConstants.CompetitionMode.RACE:
		return true
	if active_mode_id == D4FConstants.CompetitionMode.OBSTACLE_SURVIVAL:
		return false
	var lives_left := int(participants[peer_id].get("lives", 0))
	return lives_left > 0

func add_authoritative_score(peer_id: int, delta_points: int, reason: String = "") -> void:
	if not is_authoritative_host or not participants.has(peer_id):
		return
	var p: Dictionary = participants[peer_id]
	p["score"] = int(p.get("score", 0)) + delta_points
	if active_mode_instance != null:
		active_mode_instance.scores[peer_id] = p["score"]
	player_scored.emit(peer_id, delta_points, int(p["score"]), reason)

func _check_last_survivor_win() -> void:
	if active_mode_id != D4FConstants.CompetitionMode.OBSTACLE_SURVIVAL and active_mode_id != D4FConstants.CompetitionMode.PHYSICS_BATTLE:
		return
	var alive_ids: Array[int] = []
	for pid in participants.keys():
		if not bool(participants[pid].get("eliminated", false)):
			alive_ids.append(int(pid))
	if participants.size() > 1 and alive_ids.size() == 1:
		var survivor_id := alive_ids[0]
		add_authoritative_score(survivor_id, 150, "Last Survivor Bonus")
		finalize_match()
	elif alive_ids.is_empty():
		finalize_match()

## Deterministic Ranking & Tie-Breaker System
## Tie-break order:
## 1. Total Score (higher is better)
## 2. Finish Status & Finish Time (earlier finish_time wins in Race)
## 3. Eliminations scored (higher wins in Physics Battle)
## 4. Checkpoints reached (higher wins)
## 5. Survival Time (longer wins in Survival)
## 6. Fewest Deaths (lower wins)
## 7. Peer ID deterministic fallback
func compute_rankings() -> Array:
	var list: Array = participants.values().duplicate(true)
	list.sort_custom(Callable(self, "_compare_competitors"))
	for i in range(list.size()):
		list[i]["rank"] = i + 1
	return list

func _compare_competitors(a: Dictionary, b: Dictionary) -> bool:
	var score_a := int(a.get("score", 0))
	var score_b := int(b.get("score", 0))
	if score_a != score_b:
		return score_a > score_b

	var fin_a := bool(a.get("finished", false))
	var fin_b := bool(b.get("finished", false))
	if fin_a != fin_b:
		return fin_a

	var ftime_a := float(a.get("finish_time", 999999.0))
	var ftime_b := float(b.get("finish_time", 999999.0))
	if not is_equal_approx(ftime_a, ftime_b):
		return ftime_a < ftime_b

	var elim_a := int(a.get("eliminations", 0))
	var elim_b := int(b.get("eliminations", 0))
	if elim_a != elim_b:
		return elim_a > elim_b

	var cp_a := int(a.get("checkpoints", 0))
	var cp_b := int(b.get("checkpoints", 0))
	if cp_a != cp_b:
		return cp_a > cp_b

	var surv_a := float(a.get("survival_time", 0.0))
	var surv_b := float(b.get("survival_time", 0.0))
	if not is_equal_approx(surv_a, surv_b):
		return surv_a > surv_b

	var deaths_a := int(a.get("deaths", 0))
	var deaths_b := int(b.get("deaths", 0))
	if deaths_a != deaths_b:
		return deaths_a < deaths_b

	return int(a.get("id", 0)) < int(b.get("id", 0))

func finalize_match() -> Array:
	if current_phase == MatchPhase.FINISHED:
		return last_match_rankings
	current_phase = MatchPhase.FINISHED
	last_match_rankings = compute_rankings()
	last_match_winner = last_match_rankings[0] if not last_match_rankings.is_empty() else {}
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("victory")
	match_ended.emit(last_match_rankings, last_match_winner)
	return last_match_rankings

func vote_rematch(peer_id: int) -> Dictionary:
	rematch_votes[peer_id] = true
	var human_count := 0
	for p in participants.values():
		if not bool(p.get("is_bot", false)):
			human_count += 1
	var needed := maxi(1, ceili(float(human_count) * 0.5))
	var ready_for_rematch := rematch_votes.size() >= needed
	return {
		"votes": rematch_votes.size(),
		"needed": needed,
		"ready": ready_for_rematch
	}

func trigger_rematch() -> void:
	match_number += 1
	var prev_players: Array = participants.values().duplicate(true)
	setup_match(active_mode_id, prev_players, custom_rules, is_authoritative_host)
	rematch_initiated.emit(match_number)
	start_countdown(3.0)
