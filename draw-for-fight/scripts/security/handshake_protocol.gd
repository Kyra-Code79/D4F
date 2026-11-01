class_name HandshakeProtocol
extends RefCounted

enum HandshakeState {
	STATE_NONE = 0,
	STATE_L1_LOBBY_AUTH = 1,
	STATE_L2_TRANSPORT = 2,
	STATE_L3_MUTUAL_AUTH = 3,
	STATE_L4_CHALLENGE = 4,
	STATE_L5_SESSION_KEY = 5,
	STATE_ESTABLISHED = 6,
	STATE_FAILED = 7
}

const STATE_NONE := HandshakeState.STATE_NONE
const STATE_L1_LOBBY_AUTH := HandshakeState.STATE_L1_LOBBY_AUTH
const STATE_L2_TRANSPORT := HandshakeState.STATE_L2_TRANSPORT
const STATE_L3_MUTUAL_AUTH := HandshakeState.STATE_L3_MUTUAL_AUTH
const STATE_L4_CHALLENGE := HandshakeState.STATE_L4_CHALLENGE
const STATE_L5_SESSION_KEY := HandshakeState.STATE_L5_SESSION_KEY
const STATE_ESTABLISHED := HandshakeState.STATE_ESTABLISHED
const STATE_FAILED := HandshakeState.STATE_FAILED

var peer_id: int = 0
var state: int = STATE_NONE
var fail_reason: String = ""
var failed_layer: int = 0

var lobby_id: String = ""
var invite_code_hash: PackedByteArray = PackedByteArray()
var transport_binding: Dictionary = {}

var host_ephemeral_secret: PackedByteArray = PackedByteArray()
var host_identity_fingerprint: String = ""
var client_ephemeral_secret: PackedByteArray = PackedByteArray()
var client_identity_fingerprint: String = ""

var host_nonce: PackedByteArray = PackedByteArray()
var client_nonce: PackedByteArray = PackedByteArray()
var transcript_hash: PackedByteArray = PackedByteArray()

var enc_key: PackedByteArray = PackedByteArray()
var mac_key: PackedByteArray = PackedByteArray()
var iv_seed: PackedByteArray = PackedByteArray()

var _crypto := Crypto.new()

func _init(p_peer_id: int = 0, p_lobby_id: String = "", p_invite_code: String = "") -> void:
	peer_id = p_peer_id
	lobby_id = p_lobby_id
	invite_code_hash = _sha256_bytes(("D4F_INVITE_SALT::" + p_invite_code).to_utf8_buffer())
	var ephem := generate_ephemeral_identity(p_peer_id)
	client_ephemeral_secret = ephem["secret"]
	client_identity_fingerprint = ephem["fingerprint"]
	var host_ephem := generate_ephemeral_identity(1)
	host_ephemeral_secret = host_ephem["secret"]
	host_identity_fingerprint = host_ephem["fingerprint"]

static func _sha256_bytes(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()

static func _hmac_sha256(key: PackedByteArray, data: PackedByteArray) -> PackedByteArray:
	var safe_key := key
	if safe_key.is_empty():
		safe_key = PackedByteArray()
		safe_key.resize(32)
		safe_key.fill(0)
	var hmac := HMACContext.new()
	var err := hmac.start(HashingContext.HASH_SHA256, safe_key)
	if err != OK:
		return PackedByteArray()
	hmac.update(data)
	return hmac.finish()

static func constant_time_equals(a: PackedByteArray, b: PackedByteArray) -> bool:
	if a.is_empty() or b.is_empty() or a.size() != b.size():
		return false
	var c := Crypto.new()
	return c.constant_time_compare(a, b)

# ============================================================================
# LAYER 1: Lobby Authentication (Lobby ID, Invite Code Hash, Protocol Version)
# ============================================================================
func build_layer1_request(p_lobby_id: String, p_invite_code: String) -> Dictionary:
	lobby_id = p_lobby_id
	invite_code_hash = _sha256_bytes(("D4F_INVITE_SALT::" + p_invite_code).to_utf8_buffer())
	client_nonce = _crypto.generate_random_bytes(32)
	state = STATE_L1_LOBBY_AUTH
	var auth_token := _hmac_sha256(
		invite_code_hash,
		(D4FConstants.PROTOCOL_VERSION + "|" + lobby_id + "|" + str(peer_id)).to_utf8_buffer() + client_nonce
	)
	return {
		"step": "L1_CLIENT_HELLO",
		"protocol_version": D4FConstants.PROTOCOL_VERSION,
		"lobby_id": lobby_id,
		"peer_id": peer_id,
		"client_nonce_hex": client_nonce.hex_encode(),
		"client_identity": client_identity_fingerprint,
		"l1_auth_token_hex": auth_token.hex_encode()
	}

func verify_layer1_lobby_auth(msg: Dictionary, expected_lobby_id: String, expected_invite_code: String) -> Dictionary:
	state = STATE_L1_LOBBY_AUTH
	var proto := String(msg.get("protocol_version", ""))
	if proto != D4FConstants.PROTOCOL_VERSION:
		return _fail(1, "Protocol version mismatch: %s" % proto)

	var recv_lobby := String(msg.get("lobby_id", ""))
	if recv_lobby.is_empty() or recv_lobby != expected_lobby_id:
		return _fail(1, "Lobby ID mismatch.")

	var c_nonce_hex := String(msg.get("client_nonce_hex", ""))
	if c_nonce_hex.length() != 64:
		return _fail(1, "Invalid client nonce length in L1.")
	client_nonce = c_nonce_hex.hex_decode()
	client_identity_fingerprint = String(msg.get("client_identity", ""))
	if client_identity_fingerprint.length() != 64:
		return _fail(1, "Invalid client identity fingerprint in L1.")

	lobby_id = expected_lobby_id
	invite_code_hash = _sha256_bytes(("D4F_INVITE_SALT::" + expected_invite_code).to_utf8_buffer())
	var recv_peer_id := int(msg.get("peer_id", peer_id))
	var expected_token := _hmac_sha256(
		invite_code_hash,
		(D4FConstants.PROTOCOL_VERSION + "|" + expected_lobby_id + "|" + str(recv_peer_id)).to_utf8_buffer() + client_nonce
	)
	var recv_token := String(msg.get("l1_auth_token_hex", "")).hex_decode()
	if not constant_time_equals(expected_token, recv_token):
		return _fail(1, "Invalid invite code authentication token.")

	return {"ok": true, "layer": 1}

# ============================================================================
# LAYER 2: Secure Transport Configuration (DTLS / Channel Endpoint Binding)
# ============================================================================
func configure_layer2_transport(use_dtls: bool = true, channel_id: int = 0) -> Dictionary:
	state = STATE_L2_TRANSPORT
	var binding_payload := "%s|lobby=%s|peer=%d|dtls=%s|ch=%d" % [
		D4FConstants.PROTOCOL_VERSION,
		lobby_id,
		peer_id,
		str(use_dtls),
		channel_id
	]
	var binding_hash := _sha256_bytes(binding_payload.to_utf8_buffer()).hex_encode()
	transport_binding = {
		"dtls_enabled": use_dtls,
		"cipher_suite": "TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384_OR_ENET_PACKET_CIPHER",
		"channel_id": channel_id,
		"endpoint_binding_hash": binding_hash
	}
	return {"ok": true, "layer": 2, "transport": transport_binding}

func verify_layer2_transport(transport_dict: Dictionary) -> Dictionary:
	state = STATE_L2_TRANSPORT
	var binding_hash := String(transport_dict.get("endpoint_binding_hash", ""))
	if binding_hash.length() != 64:
		return _fail(2, "Missing or malformed Layer 2 endpoint binding hash.")
	transport_binding = transport_dict.duplicate(true)
	return {"ok": true, "layer": 2}

# ============================================================================
# LAYER 3: Mutual Authentication (Host & Client Ephemeral Identity Binding)
# ============================================================================
func generate_ephemeral_identity(actor_id: int) -> Dictionary:
	var secret: PackedByteArray = _crypto.generate_random_bytes(32)
	var label := ("D4F_L3_ID|" + str(actor_id) + "|").to_utf8_buffer() + secret
	var fingerprint := _sha256_bytes(label).hex_encode()
	return {
		"secret": secret,
		"fingerprint": fingerprint
	}

func compute_layer3_mutual_signature(role_label: String, local_fp: String, remote_fp: String) -> PackedByteArray:
	var msg_bytes := ("%s|%s|%s|%s" % [role_label, lobby_id, local_fp, remote_fp]).to_utf8_buffer()
	msg_bytes.append_array(client_nonce)
	msg_bytes.append_array(host_nonce)
	return _hmac_sha256(invite_code_hash, msg_bytes)

func verify_layer3_mutual_auth(role_label: String, local_fp: String, remote_fp: String, signature_hex: String) -> Dictionary:
	state = STATE_L3_MUTUAL_AUTH
	if local_fp.length() != 64 or remote_fp.length() != 64:
		return _fail(3, "Invalid Layer 3 identity fingerprint format.")
	var expected_sig := compute_layer3_mutual_signature(role_label, local_fp, remote_fp)
	var received_sig := signature_hex.hex_decode()
	if not constant_time_equals(expected_sig, received_sig):
		return _fail(3, "Mutual authentication signature verification failed for %s." % role_label)
	return {"ok": true, "layer": 3}

# ============================================================================
# LAYER 4: Random Challenge-Response (32-Byte Nonces + Constant-Time HMAC)
# ============================================================================
func generate_layer4_host_challenge() -> PackedByteArray:
	state = STATE_L4_CHALLENGE
	host_nonce = _crypto.generate_random_bytes(32)
	return host_nonce

func compute_layer4_challenge_solution(solver_role: String) -> PackedByteArray:
	var material := ("D4F_L4_CHALLENGE|" + solver_role + "|" + str(peer_id)).to_utf8_buffer()
	material.append_array(host_nonce)
	material.append_array(client_nonce)
	material.append_array( client_identity_fingerprint.to_utf8_buffer() )
	material.append_array( host_identity_fingerprint.to_utf8_buffer() )
	return _hmac_sha256(invite_code_hash, material)

func verify_layer4_challenge_response(solver_role: String, response_hex: String) -> Dictionary:
	state = STATE_L4_CHALLENGE
	if host_nonce.size() != 32 or client_nonce.size() != 32:
		return _fail(4, "Missing 32-byte cryptographic nonces in Layer 4.")
	var expected := compute_layer4_challenge_solution(solver_role)
	var received := response_hex.hex_decode()
	if not constant_time_equals(expected, received):
		return _fail(4, "Layer 4 challenge-response verification failed for %s." % solver_role)
	return {"ok": true, "layer": 4}

# ============================================================================
# LAYER 5: Authenticated Session Key Establishment (HKDF-SHA256)
# ============================================================================
static func hkdf_extract(salt: PackedByteArray, ikm: PackedByteArray) -> PackedByteArray:
	return _hmac_sha256(salt, ikm)

static func hkdf_expand(prk: PackedByteArray, info: PackedByteArray, length: int) -> PackedByteArray:
	var okm := PackedByteArray()
	var prev := PackedByteArray()
	var counter: int = 1
	while okm.size() < length:
		var input := PackedByteArray()
		input.append_array(prev)
		input.append_array(info)
		input.append(counter & 0xFF)
		prev = _hmac_sha256(prk, input)
		okm.append_array(prev)
		counter += 1
	return okm.slice(0, length)

func derive_layer5_session_keys() -> Dictionary:
	state = STATE_L5_SESSION_KEY
	if host_nonce.size() != 32 or client_nonce.size() != 32 or invite_code_hash.size() != 32:
		return _fail(5, "Cannot derive session keys without verified L1-L4 material.")

	var transcript_buf := (
		D4FConstants.PROTOCOL_VERSION + "|" +
		lobby_id + "|" +
		str(peer_id) + "|" +
		host_identity_fingerprint + "|" +
		client_identity_fingerprint
	).to_utf8_buffer()
	transcript_buf.append_array(host_nonce)
	transcript_buf.append_array(client_nonce)
	transcript_hash = _sha256_bytes(transcript_buf)

	var salt := PackedByteArray()
	salt.append_array(host_nonce)
	salt.append_array(client_nonce)

	var ikm := PackedByteArray()
	ikm.append_array(invite_code_hash)
	ikm.append_array(transcript_hash)

	var prk := hkdf_extract(salt, ikm)
	enc_key = hkdf_expand(prk, ("D4F_L5_ENC_KEY|" + str(peer_id)).to_utf8_buffer(), 32)
	mac_key = hkdf_expand(prk, ("D4F_L5_MAC_KEY|" + str(peer_id)).to_utf8_buffer(), 32)
	iv_seed = hkdf_expand(prk, ("D4F_L5_IV_SEED|" + str(peer_id)).to_utf8_buffer(), 16)

	var confirm_mac := _hmac_sha256(mac_key, ("D4F_L5_CONFIRM|" + transcript_hash.hex_encode()).to_utf8_buffer())
	state = STATE_ESTABLISHED
	return {
		"ok": true,
		"layer": 5,
		"enc_key": enc_key,
		"mac_key": mac_key,
		"iv_seed": iv_seed,
		"transcript_hash_hex": transcript_hash.hex_encode(),
		"key_confirm_hex": confirm_mac.hex_encode()
	}

func verify_layer5_key_confirmation(confirm_hex: String) -> Dictionary:
	if state != STATE_ESTABLISHED and state != STATE_L5_SESSION_KEY:
		return _fail(5, "Session keys not derived before L5 confirmation.")
	var expected := _hmac_sha256(mac_key, ("D4F_L5_CONFIRM|" + transcript_hash.hex_encode()).to_utf8_buffer())
	var received := confirm_hex.hex_decode()
	if not constant_time_equals(expected, received):
		return _fail(5, "Layer 5 session key confirmation MAC mismatch.")
	state = STATE_ESTABLISHED
	return {"ok": true, "layer": 5}

# ============================================================================
# FULL MULTI-STEP MESSAGE HANDLERS (HOST & CLIENT)
# ============================================================================
func host_process_client_hello(msg: Dictionary, expected_lobby_id: String, expected_invite_code: String, use_dtls: bool = true) -> Dictionary:
	var l1 := verify_layer1_lobby_auth(msg, expected_lobby_id, expected_invite_code)
	if not bool(l1.get("ok", false)):
		return l1

	var l2 := configure_layer2_transport(use_dtls, 0)
	generate_layer4_host_challenge()
	var host_l3_sig := compute_layer3_mutual_signature("HOST", host_identity_fingerprint, client_identity_fingerprint)
	var host_l4_sol := compute_layer4_challenge_solution("HOST")

	return {
		"ok": true,
		"response": {
			"step": "L2_L3_L4_HOST_CHALLENGE",
			"lobby_id": lobby_id,
			"peer_id": peer_id,
			"transport": l2["transport"],
			"host_identity": host_identity_fingerprint,
			"host_nonce_hex": host_nonce.hex_encode(),
			"host_l3_sig_hex": host_l3_sig.hex_encode(),
			"host_l4_solution_hex": host_l4_sol.hex_encode()
		}
	}

func client_process_host_challenge(msg: Dictionary) -> Dictionary:
	var transport_dict: Dictionary = msg.get("transport", {}) if typeof(msg.get("transport")) == TYPE_DICTIONARY else {}
	var l2 := verify_layer2_transport(transport_dict)
	if not bool(l2.get("ok", false)):
		return l2

	host_identity_fingerprint = String(msg.get("host_identity", ""))
	var h_nonce_hex := String(msg.get("host_nonce_hex", ""))
	if h_nonce_hex.length() != 64:
		return _fail(4, "Invalid host nonce in challenge.")
	host_nonce = h_nonce_hex.hex_decode()

	var l3 := verify_layer3_mutual_auth(
		"HOST",
		host_identity_fingerprint,
		client_identity_fingerprint,
		String(msg.get("host_l3_sig_hex", ""))
	)
	if not bool(l3.get("ok", false)):
		return l3

	var l4_host := verify_layer4_challenge_response("HOST", String(msg.get("host_l4_solution_hex", "")))
	if not bool(l4_host.get("ok", false)):
		return l4_host

	var client_l3_sig := compute_layer3_mutual_signature("CLIENT", client_identity_fingerprint, host_identity_fingerprint)
	var client_l4_sol := compute_layer4_challenge_solution("CLIENT")
	var l5 := derive_layer5_session_keys()
	if not bool(l5.get("ok", false)):
		return l5

	return {
		"ok": true,
		"response": {
			"step": "L3_L4_L5_CLIENT_RESPONSE",
			"peer_id": peer_id,
			"client_identity": client_identity_fingerprint,
			"client_l3_sig_hex": client_l3_sig.hex_encode(),
			"client_l4_solution_hex": client_l4_sol.hex_encode(),
			"key_confirm_hex": l5["key_confirm_hex"]
		}
	}

func host_process_client_response(msg: Dictionary) -> Dictionary:
	var l3 := verify_layer3_mutual_auth(
		"CLIENT",
		client_identity_fingerprint,
		host_identity_fingerprint,
		String(msg.get("client_l3_sig_hex", ""))
	)
	if not bool(l3.get("ok", false)):
		return l3

	var l4 := verify_layer4_challenge_response("CLIENT", String(msg.get("client_l4_solution_hex", "")))
	if not bool(l4.get("ok", false)):
		return l4

	var l5 := derive_layer5_session_keys()
	if not bool(l5.get("ok", false)):
		return l5

	var l5_confirm := verify_layer5_key_confirmation(String(msg.get("key_confirm_hex", "")))
	if not bool(l5_confirm.get("ok", false)):
		return l5_confirm

	return {
		"ok": true,
		"response": {
			"step": "L5_HOST_ESTABLISHED",
			"peer_id": peer_id,
			"transcript_hash_hex": transcript_hash.hex_encode(),
			"key_confirm_hex": l5["key_confirm_hex"]
		}
	}

func _fail(layer_num: int, reason: String) -> Dictionary:
	state = STATE_FAILED
	failed_layer = layer_num
	fail_reason = reason
	return {
		"ok": false,
		"layer": layer_num,
		"error": reason
	}
