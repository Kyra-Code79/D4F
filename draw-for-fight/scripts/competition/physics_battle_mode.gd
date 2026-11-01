class_name PhysicsBattleMode
extends CompetitionModeBase
## Mode C: Physics Battle Mode.
## Push, collide, and knock opponents out of the arena.
## +100 pts per elimination attributed to killer_peer_id, +10 pts per 5 seconds survived,
## 3 lives per player (max_lives = 3). Last player standing or highest points at timer end wins.

const POINTS_PER_KNOCKOUT := 100
const SURVIVAL_TICK_INTERVAL := 5.0
const SURVIVAL_TICK_POINTS := 10
const LAST_STANDING_BONUS := 125

var _survival_bonus_timer: float = 0.0
var _awarded_last_standing: bool = false


func _init() -> void:
	mode_id = D4FConstants.CompetitionMode.PHYSICS_BATTLE
	mode_name = "Physics Battle"
	time_limit = 150.0
	allow_respawn = true
	max_lives = 3
	use_vehicles = false


func setup_mode(participants: Array, p_custom_rules: Dictionary = {}) -> void:
	super.setup_mode(participants, p_custom_rules)
	if not p_custom_rules.has("max_lives"):
		max_lives = 3
	allow_respawn = true
	_survival_bonus_timer = 0.0
	_awarded_last_standing = false
	for pid in participant_ids:
		lives_left[pid] = max_lives


func tick_mode(delta: float, competitors: Dictionary) -> Dictionary:
	if is_match_over:
		return get_mode_status_snapshot()

	_survival_bonus_timer += delta
	while _survival_bonus_timer >= SURVIVAL_TICK_INTERVAL:
		_survival_bonus_timer -= SURVIVAL_TICK_INTERVAL
		for pid in participant_ids:
			if not eliminated_peers.has(pid):
				add_score(pid, SURVIVAL_TICK_POINTS)

	var snap := super.tick_mode(delta, competitors)
	_check_battle_end_condition()
	snap["is_match_over"] = is_match_over
	snap["rankings"] = compute_rankings()
	return snap


func on_player_eliminated(peer_id: int, killer_peer_id: int, reason: String) -> void:
	if is_match_over or eliminated_peers.has(peer_id):
		return

	if killer_peer_id > 0 and killer_peer_id != peer_id and scores.has(killer_peer_id):
		add_score(killer_peer_id, POINTS_PER_KNOCKOUT)

	super.on_player_eliminated(peer_id, killer_peer_id, reason)
	_check_battle_end_condition()


func _check_battle_end_condition() -> void:
	var alive_peers: Array[int] = []
	for pid in participant_ids:
		if not eliminated_peers.has(pid):
			alive_peers.append(pid)

	if participant_ids.size() > 1 and alive_peers.size() <= 1:
		if alive_peers.size() == 1 and not _awarded_last_standing:
			_awarded_last_standing = true
			add_score(alive_peers[0], LAST_STANDING_BONUS)
		is_match_over = true
	elif participant_ids.size() == 1 and alive_peers.is_empty():
		is_match_over = true
