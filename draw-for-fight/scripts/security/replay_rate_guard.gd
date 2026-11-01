class_name ReplayRateGuard
extends RefCounted

const WINDOW_SIZE := 64

const DEFAULT_RATE_LIMITS := {
	"handshake": {"burst": 12.0, "refill_per_sec": 4.0},
	"input": {"burst": 120.0, "refill_per_sec": 90.0},
	"map_edit": {"burst": 30.0, "refill_per_sec": 12.0},
	"chat": {"burst": 8.0, "refill_per_sec": 2.0},
	"sync": {"burst": 80.0, "refill_per_sec": 50.0}
}

var _peer_windows: Dictionary = {}
var _peer_buckets: Dictionary = {}
var _rate_configs: Dictionary = DEFAULT_RATE_LIMITS.duplicate(true)

func configure_category_limit(category: String, burst: float, refill_per_sec: float) -> void:
	_rate_configs[category] = {
		"burst": maxf(1.0, burst),
		"refill_per_sec": maxf(0.1, refill_per_sec)
	}

func check_and_record_sequence(peer_id: int, seq_num: int) -> Dictionary:
	if seq_num <= 0:
		return {
			"ok": false,
			"layer": 7,
			"error": "Invalid non-positive sequence number: %d" % seq_num
		}

	if not _peer_windows.has(peer_id):
		_peer_windows[peer_id] = {
			"max_seq": 0,
			"window_mask": 0,
			"seen": {}
		}

	var state: Dictionary = _peer_windows[peer_id]
	var max_seq: int = int(state["max_seq"])
	var window_mask: int = int(state["window_mask"])
	var seen: Dictionary = state["seen"]

	if max_seq == 0:
		max_seq = seq_num
		window_mask = 1
		seen[seq_num] = true
		state["max_seq"] = max_seq
		state["window_mask"] = window_mask
		return {
			"ok": true,
			"layer": 7,
			"max_seq": max_seq,
			"window_mask": window_mask
		}

	if seq_num > max_seq:
		var delta := seq_num - max_seq
		if delta >= 62:
			window_mask = 1
		else:
			window_mask = ((window_mask << delta) | 1) & 0x7FFFFFFFFFFFFFFF
		max_seq = seq_num
		seen[seq_num] = true

		# Prune sequence entries older than WINDOW_SIZE
		var cutoff := max_seq - WINDOW_SIZE
		for k in seen.keys():
			if int(k) <= cutoff:
				seen.erase(k)

		state["max_seq"] = max_seq
		state["window_mask"] = window_mask
		return {
			"ok": true,
			"layer": 7,
			"max_seq": max_seq,
			"window_mask": window_mask
		}

	var age := max_seq - seq_num
	if age >= WINDOW_SIZE:
		return {
			"ok": false,
			"layer": 7,
			"error": "Sequence %d is older than replay window (%d - %d)." % [seq_num, max_seq, WINDOW_SIZE]
		}

	var bit_already_set := false
	if seen.has(seq_num):
		bit_already_set = true
	elif age < 62 and ((window_mask >> age) & 1) == 1:
		bit_already_set = true

	if bit_already_set:
		return {
			"ok": false,
			"layer": 7,
			"error": "Replay attack detected: duplicate sequence number %d." % seq_num
		}

	if age < 62:
		window_mask = (window_mask | (1 << age)) & 0x7FFFFFFFFFFFFFFF
	seen[seq_num] = true
	state["window_mask"] = window_mask

	return {
		"ok": true,
		"layer": 7,
		"max_seq": max_seq,
		"window_mask": window_mask
	}

func check_rate_limit(peer_id: int, category: String, now_ms: int = -1) -> Dictionary:
	var current_ms := now_ms if now_ms >= 0 else Time.get_ticks_msec()
	var cfg: Dictionary = _rate_configs.get(category, _rate_configs["sync"])
	var burst: float = float(cfg.get("burst", 60.0))
	var refill: float = float(cfg.get("refill_per_sec", 30.0))

	if not _peer_buckets.has(peer_id):
		_peer_buckets[peer_id] = {}

	var peer_cats: Dictionary = _peer_buckets[peer_id]
	if not peer_cats.has(category):
		peer_cats[category] = {
			"tokens": burst - 1.0,
			"last_ms": current_ms
		}
		return {
			"ok": true,
			"layer": 7,
			"category": category,
			"tokens_remaining": burst - 1.0
		}

	var bucket: Dictionary = peer_cats[category]
	var last_ms: int = int(bucket["last_ms"])
	var elapsed_sec := maxf(0.0, float(current_ms - last_ms) / 1000.0)
	var tokens := minf(burst, float(bucket["tokens"]) + elapsed_sec * refill)
	bucket["last_ms"] = current_ms

	if tokens < 1.0:
		bucket["tokens"] = tokens
		return {
			"ok": false,
			"layer": 7,
			"category": category,
			"tokens_remaining": tokens,
			"error": "Rate limit exceeded for peer %d on category '%s'." % [peer_id, category]
		}

	tokens -= 1.0
	bucket["tokens"] = tokens
	return {
		"ok": true,
		"layer": 7,
		"category": category,
		"tokens_remaining": tokens
	}

func reset_peer(peer_id: int) -> void:
	_peer_windows.erase(peer_id)
	_peer_buckets.erase(peer_id)
