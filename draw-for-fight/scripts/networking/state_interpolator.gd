class_name StateInterpolator
extends RefCounted

const MAX_SNAPSHOTS_PER_PEER := 24
const MAX_PREDICTED_INPUTS := 64

var interpolation_delay_sec: float = 0.08
var max_extrapolation_sec: float = 0.15
var snap_threshold_distance: float = 3.0

var _peer_snapshots: Dictionary = {}
var _predicted_inputs: Array = []

func push_snapshot(
	peer_id: int,
	timestamp_sec: float,
	position: Vector3,
	rotation_deg: Vector3,
	velocity: Vector3 = Vector3.ZERO
) -> void:
	if not _peer_snapshots.has(peer_id):
		_peer_snapshots[peer_id] = []

	var buffer: Array = _peer_snapshots[peer_id]
	var snap := {
		"timestamp": timestamp_sec,
		"position": position,
		"rotation_deg": rotation_deg,
		"velocity": velocity
	}

	if not buffer.is_empty() and float((buffer.back() as Dictionary)["timestamp"]) > timestamp_sec:
		# Out-of-order snapshot ignored
		return

	buffer.append(snap)
	while buffer.size() > MAX_SNAPSHOTS_PER_PEER:
		buffer.pop_front()

func sample_interpolated_state(peer_id: int, render_time_sec: float) -> Dictionary:
	if not _peer_snapshots.has(peer_id):
		return {
			"valid": false,
			"position": Vector3.ZERO,
			"rotation_deg": Vector3.ZERO,
			"velocity": Vector3.ZERO
		}

	var buffer: Array = _peer_snapshots[peer_id]
	if buffer.is_empty():
		return {
			"valid": false,
			"position": Vector3.ZERO,
			"rotation_deg": Vector3.ZERO,
			"velocity": Vector3.ZERO
		}

	if buffer.size() == 1:
		var only: Dictionary = buffer[0]
		return {
			"valid": true,
			"position": only["position"],
			"rotation_deg": only["rotation_deg"],
			"velocity": only["velocity"]
		}

	var target_time := render_time_sec - interpolation_delay_sec
	var oldest: Dictionary = buffer[0]
	var newest: Dictionary = buffer[buffer.size() - 1]

	if target_time <= float(oldest["timestamp"]):
		return {
			"valid": true,
			"position": oldest["position"],
			"rotation_deg": oldest["rotation_deg"],
			"velocity": oldest["velocity"]
		}

	if target_time >= float(newest["timestamp"]):
		var dt := clampf(target_time - float(newest["timestamp"]), 0.0, max_extrapolation_sec)
		var extrap_pos: Vector3 = (newest["position"] as Vector3) + (newest["velocity"] as Vector3) * dt
		return {
			"valid": true,
			"position": extrap_pos,
			"rotation_deg": newest["rotation_deg"],
			"velocity": newest["velocity"]
		}

	for i in range(buffer.size() - 1):
		var s0: Dictionary = buffer[i]
		var s1: Dictionary = buffer[i + 1]
		var t0 := float(s0["timestamp"])
		var t1 := float(s1["timestamp"])
		if target_time >= t0 and target_time <= t1:
			var span := maxf(0.0001, t1 - t0)
			var alpha := clampf((target_time - t0) / span, 0.0, 1.0)
			var pos0: Vector3 = s0["position"]
			var pos1: Vector3 = s1["position"]
			var rot0: Vector3 = s0["rotation_deg"]
			var rot1: Vector3 = s1["rotation_deg"]
			var vel0: Vector3 = s0["velocity"]
			var vel1: Vector3 = s1["velocity"]
			return {
				"valid": true,
				"position": pos0.lerp(pos1, alpha),
				"rotation_deg": Vector3(
					rad_to_deg(lerp_angle(deg_to_rad(rot0.x), deg_to_rad(rot1.x), alpha)),
					rad_to_deg(lerp_angle(deg_to_rad(rot0.y), deg_to_rad(rot1.y), alpha)),
					rad_to_deg(lerp_angle(deg_to_rad(rot0.z), deg_to_rad(rot1.z), alpha))
				),
				"velocity": vel0.lerp(vel1, alpha)
			}

	return {
		"valid": true,
		"position": newest["position"],
		"rotation_deg": newest["rotation_deg"],
		"velocity": newest["velocity"]
	}

func record_predicted_input(input_seq: int, input_vec: Vector3, predicted_pos: Vector3, dt: float) -> void:
	_predicted_inputs.append({
		"input_seq": input_seq,
		"input_vec": input_vec,
		"predicted_pos": predicted_pos,
		"dt": clampf(dt, 0.001, 0.25)
	})
	while _predicted_inputs.size() > MAX_PREDICTED_INPUTS:
		_predicted_inputs.pop_front()

func reconcile_with_authoritative_state(
	ack_input_seq: int,
	auth_pos: Vector3,
	auth_vel: Vector3,
	move_speed: float = 14.0
) -> Dictionary:
	var remaining: Array = []
	var last_predicted_pos := auth_pos
	for item in _predicted_inputs:
		var entry: Dictionary = item
		var seq := int(entry["input_seq"])
		if seq == ack_input_seq:
			last_predicted_pos = entry["predicted_pos"]
		elif seq > ack_input_seq:
			remaining.append(entry)
	_predicted_inputs = remaining

	var replayed_pos := auth_pos
	var cur_vel := auth_vel
	for item in _predicted_inputs:
		var entry: Dictionary = item
		var in_vec: Vector3 = entry["input_vec"]
		var dt := float(entry["dt"])
		var horiz_vel := Vector3(in_vec.x * move_speed, cur_vel.y, in_vec.z * move_speed)
		replayed_pos += horiz_vel * dt

	var error_dist := auth_pos.distance_to(last_predicted_pos)
	var snapped := error_dist >= snap_threshold_distance

	return {
		"reconciled_position": replayed_pos,
		"error_distance": error_dist,
		"pending_inputs": _predicted_inputs.size(),
		"snapped": snapped
	}

func clear_peer(peer_id: int) -> void:
	_peer_snapshots.erase(peer_id)

func clear_all() -> void:
	_peer_snapshots.clear()
	_predicted_inputs.clear()
