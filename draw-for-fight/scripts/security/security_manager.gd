extends Node
# NOTE: No class_name here because SecurityManager is registered as an Autoload singleton.

signal peer_handshake_completed(peer_id: int)
signal peer_handshake_failed(peer_id: int, layer: int, reason: String)
signal security_violation_detected(peer_id: int, layer: int, details: String)

var _active_lobby_id: String = "lobby_default"
var _active_invite_code: String = "D4F-OPEN"
var _use_dtls: bool = true

var _peer_sessions: Dictionary = {}
var _peer_outbound_seq: Dictionary = {}
var _replay_guard := ReplayRateGuard.new()
var _session_validator := SessionValidator.new()
var _active_map: MapData = null
var _audit_log: Array = []

func configure_lobby_security(lobby_id: String, invite_code: String, use_dtls: bool = true) -> void:
	_active_lobby_id = lobby_id if not lobby_id.is_empty() else "lobby_default"
	_active_invite_code = invite_code if not invite_code.is_empty() else "D4F-OPEN"
	_use_dtls = use_dtls
	_peer_sessions.clear()
	_peer_outbound_seq.clear()
	_log_event(0, 1, "CONFIG", "Configured 8-layer security for lobby '%s' (DTLS=%s)." % [_active_lobby_id, str(_use_dtls)])

func set_active_map_reference(map_data: MapData) -> void:
	_active_map = map_data

func initiate_client_handshake(peer_id: int, lobby_id: String, invite_code: String) -> Dictionary:
	var hs := HandshakeProtocol.new(peer_id, lobby_id, invite_code)
	_peer_sessions[peer_id] = hs
	_peer_outbound_seq[peer_id] = 0
	_replay_guard.reset_peer(peer_id)
	_session_validator.reset_peer(peer_id)
	var hello_msg := hs.build_layer1_request(lobby_id, invite_code)
	_log_event(peer_id, 1, "HANDSHAKE_INIT", "Client initiated L1 handshake for lobby '%s'." % lobby_id)
	return hello_msg

func handle_handshake_message(peer_id: int, msg: Dictionary, is_host: bool) -> Dictionary:
	var rate_chk := _replay_guard.check_rate_limit(peer_id, "handshake")
	if not bool(rate_chk.get("ok", false)):
		var reason := String(rate_chk.get("error", "Handshake rate limit exceeded"))
		_record_violation(peer_id, 7, reason)
		peer_handshake_failed.emit(peer_id, 7, reason)
		return rate_chk

	var step := String(msg.get("step", ""))
	if is_host:
		if step == "L1_CLIENT_HELLO":
			var hs := HandshakeProtocol.new(peer_id, _active_lobby_id, _active_invite_code)
			_peer_sessions[peer_id] = hs
			_peer_outbound_seq[peer_id] = 0
			var res := hs.host_process_client_hello(msg, _active_lobby_id, _active_invite_code, _use_dtls)
			if not bool(res.get("ok", false)):
				var l := int(res.get("layer", 1))
				var err := String(res.get("error", "L1 failed"))
				_log_event(peer_id, l, "HANDSHAKE_FAIL", err)
				peer_handshake_failed.emit(peer_id, l, err)
			return res
		elif step == "L3_L4_L5_CLIENT_RESPONSE":
			if not _peer_sessions.has(peer_id):
				return {"ok": false, "layer": 3, "error": "No active handshake session for peer %d." % peer_id}
			var hs: HandshakeProtocol = _peer_sessions[peer_id]
			var res := hs.host_process_client_response(msg)
			if bool(res.get("ok", false)):
				_log_event(peer_id, 5, "HANDSHAKE_OK", "Host completed 5-layer handshake with peer %d." % peer_id)
				peer_handshake_completed.emit(peer_id)
			else:
				var l := int(res.get("layer", 5))
				var err := String(res.get("error", "Handshake verification failed"))
				_log_event(peer_id, l, "HANDSHAKE_FAIL", err)
				peer_handshake_failed.emit(peer_id, l, err)
			return res
	else:
		if not _peer_sessions.has(peer_id):
			return {"ok": false, "layer": 2, "error": "Client has no active handshake session."}
		var hs: HandshakeProtocol = _peer_sessions[peer_id]
		if step == "L2_L3_L4_HOST_CHALLENGE":
			var res := hs.client_process_host_challenge(msg)
			if not bool(res.get("ok", false)):
				var l := int(res.get("layer", 3))
				var err := String(res.get("error", "Client failed host challenge"))
				_log_event(peer_id, l, "HANDSHAKE_FAIL", err)
				peer_handshake_failed.emit(peer_id, l, err)
			return res
		elif step == "L5_HOST_ESTABLISHED":
			var res := hs.verify_layer5_key_confirmation(String(msg.get("key_confirm_hex", "")))
			if bool(res.get("ok", false)):
				_log_event(peer_id, 5, "HANDSHAKE_OK", "Client verified L5 key confirmation.")
				peer_handshake_completed.emit(peer_id)
			else:
				var l := int(res.get("layer", 5))
				var err := String(res.get("error", "L5 key confirmation failed"))
				_log_event(peer_id, l, "HANDSHAKE_FAIL", err)
				peer_handshake_failed.emit(peer_id, l, err)
			return res

	return {"ok": false, "layer": 1, "error": "Unexpected handshake step: %s" % step}

func complete_full_handshake_simulation(peer_id: int, lobby_id: String, invite_code: String) -> Dictionary:
	if _active_lobby_id.is_empty():
		configure_lobby_security(lobby_id, invite_code, true)

	var client_hs := HandshakeProtocol.new(peer_id, lobby_id, invite_code)
	var host_hs := HandshakeProtocol.new(peer_id, lobby_id, invite_code)

	# Step 1: Client builds L1 Hello
	var l1_hello := client_hs.build_layer1_request(lobby_id, invite_code)

	# Step 2: Host verifies L1, configures L2, signs L3 & L4 challenge
	var host_challenge := host_hs.host_process_client_hello(l1_hello, lobby_id, invite_code, _use_dtls)
	if not bool(host_challenge.get("ok", false)):
		var fail_l := int(host_challenge.get("layer", 1))
		var fail_r := String(host_challenge.get("error", "Host rejected L1"))
		peer_handshake_failed.emit(peer_id, fail_l, fail_r)
		return host_challenge

	# Step 3: Client verifies L2, L3, L4 from Host and derives L5 keys
	var client_resp := client_hs.client_process_host_challenge(host_challenge["response"])
	if not bool(client_resp.get("ok", false)):
		var fail_l := int(client_resp.get("layer", 3))
		var fail_r := String(client_resp.get("error", "Client rejected host challenge"))
		peer_handshake_failed.emit(peer_id, fail_l, fail_r)
		return client_resp

	# Step 4: Host verifies Client L3, L4 and derives/confirms L5 session keys
	var host_final := host_hs.host_process_client_response(client_resp["response"])
	if not bool(host_final.get("ok", false)):
		var fail_l := int(host_final.get("layer", 4))
		var fail_r := String(host_final.get("error", "Host rejected client response"))
		peer_handshake_failed.emit(peer_id, fail_l, fail_r)
		return host_final

	# Step 5: Client verifies Host L5 key confirmation
	var client_final := client_hs.verify_layer5_key_confirmation(String(host_final["response"]["key_confirm_hex"]))
	if not bool(client_final.get("ok", false)):
		var fail_l := int(client_final.get("layer", 5))
		var fail_r := String(client_final.get("error", "Client L5 confirmation failed"))
		peer_handshake_failed.emit(peer_id, fail_l, fail_r)
		return client_final

	_peer_sessions[peer_id] = host_hs
	_peer_outbound_seq[peer_id] = 0
	_replay_guard.reset_peer(peer_id)
	_session_validator.reset_peer(peer_id)

	_log_event(peer_id, 5, "HANDSHAKE_ESTABLISHED", "Peer %d authenticated across Layers 1-5 (transcript=%s)." % [
		peer_id,
		host_hs.transcript_hash.hex_encode().substr(0, 16)
	])
	peer_handshake_completed.emit(peer_id)

	return {
		"ok": true,
		"peer_id": peer_id,
		"lobby_id": lobby_id,
		"state": HandshakeProtocol.STATE_ESTABLISHED,
		"layers_verified": [1, 2, 3, 4, 5],
		"transcript_hash_hex": host_hs.transcript_hash.hex_encode(),
		"host_identity": host_hs.host_identity_fingerprint,
		"client_identity": client_hs.client_identity_fingerprint
	}

func is_peer_authenticated(peer_id: int) -> bool:
	if not _peer_sessions.has(peer_id):
		return false
	var hs: HandshakeProtocol = _peer_sessions[peer_id]
	return hs.state == HandshakeProtocol.STATE_ESTABLISHED

func seal_packet(peer_id: int, action: String, payload: Dictionary, category: String = "sync") -> Dictionary:
	if not is_peer_authenticated(peer_id):
		return {
			"ok": false,
			"layer": 5,
			"error": "Cannot seal packet: Peer %d does not have an established session key." % peer_id
		}

	var hs: HandshakeProtocol = _peer_sessions[peer_id]
	var next_seq: int = int(_peer_outbound_seq.get(peer_id, 0)) + 1
	_peer_outbound_seq[peer_id] = next_seq

	var inner_frame := {
		"action": action,
		"category": category,
		"peer_id": peer_id,
		"timestamp_ms": Time.get_ticks_msec(),
		"payload": D4FSerializer.sanitize_variant(payload)
	}
	var json_str := D4FSerializer.to_json_safe(inner_frame)
	var plaintext_bytes := json_str.to_utf8_buffer()
	if plaintext_bytes.size() > D4FConstants.MAX_PACKET_BYTES:
		return {
			"ok": false,
			"layer": 6,
			"error": "Serialized payload exceeds MAX_PACKET_BYTES (%d)." % D4FConstants.MAX_PACKET_BYTES
		}

	var encrypted := PacketCipher.encrypt_payload(
		plaintext_bytes,
		next_seq,
		hs.enc_key,
		hs.mac_key,
		hs.iv_seed
	)
	if not bool(encrypted.get("ok", false)):
		return encrypted

	encrypted["peer_id"] = peer_id
	encrypted["category"] = category
	return encrypted

func open_and_validate_packet(peer_id: int, is_host: bool, envelope: Dictionary, category: String = "sync") -> Dictionary:
	# Layer 5 check: Active authenticated session
	if not is_peer_authenticated(peer_id):
		var err := "Unauthenticated packet from peer %d rejected." % peer_id
		_record_violation(peer_id, 5, err)
		return {"ok": false, "layer": 5, "error": err}

	# Layer 7 check (Part A): Token-bucket rate limit before expensive crypto
	var pkt_category := String(envelope.get("category", category))
	var rate_res := _replay_guard.check_rate_limit(peer_id, pkt_category)
	if not bool(rate_res.get("ok", false)):
		var err := String(rate_res.get("error", "Rate limit exceeded"))
		_record_violation(peer_id, 7, err)
		return rate_res

	# Layer 6 check: Constant-time HMAC verification + AES-256-CBC decryption
	var hs: HandshakeProtocol = _peer_sessions[peer_id]
	var dec_res := PacketCipher.decrypt_payload(envelope, hs.enc_key, hs.mac_key, hs.iv_seed)
	if not bool(dec_res.get("ok", false)):
		var err := String(dec_res.get("error", "Packet integrity/decryption failure"))
		_record_violation(peer_id, 6, err)
		return dec_res

	# Layer 7 check (Part B): Sliding-window anti-replay verification
	var seq_num := int(dec_res.get("seq_num", -1))
	var replay_res := _replay_guard.check_and_record_sequence(peer_id, seq_num)
	if not bool(replay_res.get("ok", false)):
		var err := String(replay_res.get("error", "Replay detected"))
		_record_violation(peer_id, 7, err)
		return replay_res

	# Safe JSON parsing & sanitization
	var plaintext_bytes: PackedByteArray = dec_res["plaintext_bytes"]
	var json_str := plaintext_bytes.get_string_from_utf8()
	var parsed: Variant = D4FSerializer.from_json_safe(json_str, D4FConstants.MAX_PACKET_BYTES)
	if typeof(parsed) != TYPE_DICTIONARY:
		var err := "Decrypted packet payload is not a valid JSON Dictionary."
		_record_violation(peer_id, 8, err)
		return {"ok": false, "layer": 8, "error": err}

	var frame: Dictionary = parsed
	var action := String(frame.get("action", ""))
	var raw_payload: Variant = frame.get("payload", {})
	var payload_dict: Dictionary = raw_payload if typeof(raw_payload) == TYPE_DICTIONARY else {}

	# Layer 8 check: Role-based authorization & physics/schema validation
	var val_res := _session_validator.validate_action_payload(
		peer_id,
		is_host,
		true,
		action,
		payload_dict,
		_active_map
	)
	if not bool(val_res.get("ok", false)):
		var err := String(val_res.get("error", "Session validation failed"))
		_record_violation(peer_id, 8, err)
		return val_res

	return {
		"ok": true,
		"layer": 8,
		"peer_id": peer_id,
		"seq_num": seq_num,
		"action": action,
		"category": pkt_category,
		"payload": val_res.get("sanitized_payload", payload_dict)
	}

func remove_peer(peer_id: int) -> void:
	_peer_sessions.erase(peer_id)
	_peer_outbound_seq.erase(peer_id)
	_replay_guard.reset_peer(peer_id)
	_session_validator.reset_peer(peer_id)

func get_peer_security_summary(peer_id: int) -> Dictionary:
	if not _peer_sessions.has(peer_id):
		return {"authenticated": false, "peer_id": peer_id, "state": HandshakeProtocol.STATE_NONE}
	var hs: HandshakeProtocol = _peer_sessions[peer_id]
	return {
		"authenticated": hs.state == HandshakeProtocol.STATE_ESTABLISHED,
		"peer_id": peer_id,
		"state": hs.state,
		"transcript_hash_hex": hs.transcript_hash.hex_encode(),
		"client_identity": hs.client_identity_fingerprint,
		"host_identity": hs.host_identity_fingerprint,
		"outbound_seq": int(_peer_outbound_seq.get(peer_id, 0))
	}

func get_audit_log() -> Array:
	return _audit_log.duplicate(true)

func _record_violation(peer_id: int, layer: int, details: String) -> void:
	_log_event(peer_id, layer, "VIOLATION", details)
	security_violation_detected.emit(peer_id, layer, details)

func _log_event(peer_id: int, layer: int, event_type: String, details: String) -> void:
	_audit_log.append({
		"timestamp_ms": Time.get_ticks_msec(),
		"peer_id": peer_id,
		"layer": layer,
		"type": event_type,
		"details": details
	})
	if _audit_log.size() > 256:
		_audit_log.pop_front()
