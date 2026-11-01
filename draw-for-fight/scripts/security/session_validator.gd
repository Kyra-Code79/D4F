class_name SessionValidator
extends RefCounted

const HOST_ONLY_ACTIONS: Array[String] = [
	"start_match",
	"finalize_map",
	"score_update",
	"kick_player",
	"set_mode",
	"match_state",
	"map_full_sync",
	"authoritative_scores"
]

const AUTHENTICATED_PEER_ACTIONS: Array[String] = [
	"player_input",
	"map_add_object",
	"map_update_object",
	"map_remove_object",
	"map_add_stroke",
	"submit_creation",
	"ready_state",
	"chat_message",
	"ping"
]

const MAX_PLAUSIBLE_SPEED := 75.0
const MAX_TELEPORT_DELTA := 28.0

var _last_peer_positions: Dictionary = {}

func validate_action_permission(peer_id: int, is_host: bool, is_authenticated: bool, action: String) -> Dictionary:
	if not is_authenticated:
		return {
			"ok": false,
			"layer": 8,
			"error": "Peer %d is not authenticated for action '%s'." % [peer_id, action]
		}

	if HOST_ONLY_ACTIONS.has(action):
		if not is_host:
			return {
				"ok": false,
				"layer": 8,
				"error": "RBAC violation: Peer %d attempted host-only action '%s'." % [peer_id, action]
			}
		return {"ok": true, "layer": 8}

	if AUTHENTICATED_PEER_ACTIONS.has(action):
		return {"ok": true, "layer": 8}

	return {
		"ok": false,
		"layer": 8,
		"error": "Unrecognized or disallowed action '%s' from peer %d." % [action, peer_id]
	}

func validate_movement_input(peer_id: int, input_dict: Dictionary, dt: float = 0.05) -> Dictionary:
	var raw_move_x: Variant = input_dict.get("move_x", 0.0)
	var raw_move_z: Variant = input_dict.get("move_z", 0.0)
	var raw_throttle: Variant = input_dict.get("throttle", 0.0)
	var raw_steer: Variant = input_dict.get("steer", 0.0)

	if _is_bad_number(raw_move_x) or _is_bad_number(raw_move_z) or _is_bad_number(raw_throttle) or _is_bad_number(raw_steer):
		return {
			"ok": false,
			"layer": 8,
			"error": "Physics input contains NaN or Inf values."
		}

	var sanitized_input := {
		"move_x": clampf(float(raw_move_x), -1.0, 1.0),
		"move_z": clampf(float(raw_move_z), -1.0, 1.0),
		"throttle": clampf(float(raw_throttle), -1.0, 1.0),
		"steer": clampf(float(raw_steer), -1.0, 1.0),
		"jump": bool(input_dict.get("jump", false)),
		"boost": bool(input_dict.get("boost", false)),
		"attack": bool(input_dict.get("attack", false)),
		"input_seq": maxi(0, int(input_dict.get("input_seq", 0)))
	}

	if input_dict.has("reported_position"):
		var pos := D4FSerializer.array_to_vec3(input_dict["reported_position"], Vector3.ZERO)
		if _last_peer_positions.has(peer_id):
			var prev_pos: Vector3 = _last_peer_positions[peer_id]
			var dist := pos.distance_to(prev_pos)
			var safe_dt := maxf(0.016, dt)
			var speed := dist / safe_dt
			if dist > MAX_TELEPORT_DELTA and speed > MAX_PLAUSIBLE_SPEED:
				return {
					"ok": false,
					"layer": 8,
					"error": "Impossible movement delta detected (dist=%.2f, speed=%.2f)." % [dist, speed]
				}
		_last_peer_positions[peer_id] = pos
		sanitized_input["reported_position"] = D4FSerializer.vec3_to_array(pos)

	return {
		"ok": true,
		"layer": 8,
		"sanitized_payload": sanitized_input
	}

func validate_creation_submission(creation_dict: Dictionary) -> Dictionary:
	var c := CreationData.from_dict(creation_dict)
	c = MeshBudgetLimiter.enforce_creation_budget(c)
	var v := c.validate()
	if not bool(v.get("valid", false)):
		return {
			"ok": false,
			"layer": 8,
			"error": "Invalid creation submission: " + ", ".join(v.get("errors", []))
		}
	return {
		"ok": true,
		"layer": 8,
		"sanitized_payload": c.to_dict()
	}

func validate_map_action(peer_id: int, is_host: bool, action: String, payload: Dictionary, map_data: MapData = null) -> Dictionary:
	if map_data != null:
		var obj_owner := int(payload.get("owner_id", -1))
		if not map_data.can_peer_edit(peer_id, is_host, obj_owner):
			return {
				"ok": false,
				"layer": 8,
				"error": "Map editing locked or unauthorized for peer %d." % peer_id
			}

	var sanitized: Variant = D4FSerializer.sanitize_variant(payload)
	if typeof(sanitized) != TYPE_DICTIONARY:
		return {
			"ok": false,
			"layer": 8,
			"error": "Malformed map edit payload."
		}

	return {
		"ok": true,
		"layer": 8,
		"sanitized_payload": sanitized
	}

func validate_action_payload(
	peer_id: int,
	is_host: bool,
	is_authenticated: bool,
	action: String,
	payload: Dictionary,
	map_data: MapData = null
) -> Dictionary:
	var perm := validate_action_permission(peer_id, is_host, is_authenticated, action)
	if not bool(perm.get("ok", false)):
		return perm

	match action:
		"player_input":
			return validate_movement_input(peer_id, payload)
		"submit_creation":
			return validate_creation_submission(payload)
		"map_add_object", "map_update_object", "map_remove_object", "map_add_stroke":
			return validate_map_action(peer_id, is_host, action, payload, map_data)
		_:
			var sanitized: Variant = D4FSerializer.sanitize_variant(payload)
			if typeof(sanitized) != TYPE_DICTIONARY:
				return {
					"ok": false,
					"layer": 8,
					"error": "Payload failed structural sanitization."
				}
			return {
				"ok": true,
				"layer": 8,
				"sanitized_payload": sanitized
			}

func reset_peer(peer_id: int) -> void:
	_last_peer_positions.erase(peer_id)

static func _is_bad_number(val: Variant) -> bool:
	if typeof(val) == TYPE_FLOAT:
		return is_nan(float(val)) or is_inf(float(val))
	if typeof(val) != TYPE_INT:
		return true
	return false
