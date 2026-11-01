class_name RelayConnector
extends RefCounted

enum RelayState {
	DISCONNECTED = 0,
	ALLOCATING = 1,
	READY = 2,
	FORWARDING = 3,
	ERROR = 4
}

var state: int = RelayState.DISCONNECTED
var relay_endpoint: String = "127.0.0.1:24899"
var allocation_code: String = ""
var bound_lobby_id: String = ""
var registered_peers: Array[int] = []
var forwarded_packet_count: int = 0

func allocate_relay_session(lobby_id: String, host_peer_id: int = 1, custom_endpoint: String = "") -> Dictionary:
	state = RelayState.ALLOCATING
	if not custom_endpoint.is_empty():
		relay_endpoint = custom_endpoint
	bound_lobby_id = lobby_id
	var hash_hex := D4FSerializer.compute_sha256_hex("%s|%d|%d" % [lobby_id, host_peer_id, Time.get_ticks_msec()])
	allocation_code = "RLY-" + hash_hex.substr(0, 8).to_upper()
	registered_peers = [host_peer_id]
	state = RelayState.READY
	return {
		"ok": true,
		"state": state,
		"relay_endpoint": relay_endpoint,
		"allocation_code": allocation_code,
		"lobby_id": bound_lobby_id
	}

func bind_client_to_relay(alloc_code: String, client_peer_id: int) -> Dictionary:
	if alloc_code.is_empty() or (not allocation_code.is_empty() and alloc_code != allocation_code):
		state = RelayState.ERROR
		return {
			"ok": false,
			"error": "Relay allocation code mismatch."
		}
	if allocation_code.is_empty():
		allocation_code = alloc_code
	if not registered_peers.has(client_peer_id):
		registered_peers.append(client_peer_id)
	state = RelayState.FORWARDING
	return {
		"ok": true,
		"state": state,
		"allocation_code": allocation_code,
		"client_peer_id": client_peer_id
	}

func wrap_relay_envelope(source_peer: int, target_peer: int, encrypted_envelope: Dictionary) -> Dictionary:
	forwarded_packet_count += 1
	state = RelayState.FORWARDING
	return {
		"relay_version": D4FConstants.PROTOCOL_VERSION,
		"allocation_code": allocation_code,
		"source_peer": source_peer,
		"target_peer": target_peer,
		"hop_timestamp_ms": Time.get_ticks_msec(),
		"envelope": encrypted_envelope
	}

func unwrap_relay_envelope(relay_packet: Dictionary) -> Dictionary:
	if String(relay_packet.get("relay_version", "")) != D4FConstants.PROTOCOL_VERSION:
		return {"ok": false, "error": "Unsupported relay protocol version."}
	var alloc := String(relay_packet.get("allocation_code", ""))
	if not allocation_code.is_empty() and alloc != allocation_code:
		return {"ok": false, "error": "Invalid relay allocation code on packet."}
	var inner: Variant = relay_packet.get("envelope", {})
	if typeof(inner) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Malformed inner encrypted envelope in relay frame."}
	return {
		"ok": true,
		"source_peer": int(relay_packet.get("source_peer", 0)),
		"target_peer": int(relay_packet.get("target_peer", 0)),
		"envelope": inner
	}

func close_relay() -> void:
	state = RelayState.DISCONNECTED
	allocation_code = ""
	bound_lobby_id = ""
	registered_peers.clear()

func get_status() -> Dictionary:
	return {
		"state": state,
		"relay_endpoint": relay_endpoint,
		"allocation_code": allocation_code,
		"bound_lobby_id": bound_lobby_id,
		"registered_peers": registered_peers.duplicate(),
		"forwarded_packet_count": forwarded_packet_count
	}
