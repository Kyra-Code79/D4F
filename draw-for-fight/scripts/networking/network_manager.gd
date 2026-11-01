extends Node
# NOTE: No class_name here because NetworkManager is registered as an Autoload singleton.

const SecurityManagerScript := preload("res://scripts/security/security_manager.gd")

signal lobby_created(lobby_id: String, port: int)
signal lobby_joined(lobby_id: String)
signal connection_failed(reason: String)
signal player_joined(peer_id: int, player_info: Dictionary)
signal player_left(peer_id: int, reason: String)
signal player_updated(peer_id: int, player_info: Dictionary)
signal map_sync_received(map_dict: Dictionary)
signal map_delta_received(delta_dict: Dictionary)
signal match_state_received(state_dict: Dictionary)
signal authoritative_scores_received(scores: Dictionary)
signal lan_lobbies_updated(lobbies: Array)

var is_host: bool = true
var local_peer_id: int = 1
var local_player_name: String = "Host Sketcher"
var active_lobby_id: String = ""
var active_lobby_name: String = "Draw for Fight Arena"
var active_invite_code: String = "D4F-2026"
var active_port: int = D4FConstants.DEFAULT_PORT
var max_lobby_players: int = D4FConstants.MAX_PLAYERS

var players: Dictionary = {}
var interpolator := StateInterpolator.new()
var relay := RelayConnector.new()

var _enet_peer: ENetMultiplayerPeer = null
var _lan_broadcaster: PacketPeerUDP = null
var _lan_listener: PacketPeerUDP = null
var _lan_broadcast_enabled: bool = false
var _lan_broadcast_timer: float = 0.0
var _discovered_lan_lobbies: Dictionary = {}
var _reconnect_tokens: Dictionary = {}
var _fallback_security_manager: Node = null
var _bot_counter: int = 100

const BOT_NAMES: Array[String] = [
	"InkBlazer",
	"DoodleKnight",
	"GraphiteRex",
	"VectorViper",
	"ChalkStorm",
	"SketchTitan",
	"PixelPhantom",
	"MarkerMage"
]

const BOT_COLORS: Array[String] = [
	"#ff5533",
	"#33dd88",
	"#ffaa22",
	"#aa55ff",
	"#22ccff",
	"#ff44aa",
	"#88ee22",
	"#ffdd33"
]

func _ready() -> void:
	set_process(true)

func _process(delta: float) -> void:
	if _lan_broadcast_enabled and is_host and not active_lobby_id.is_empty():
		_lan_broadcast_timer += delta
		if _lan_broadcast_timer >= 1.5:
			_lan_broadcast_timer = 0.0
			_broadcast_lan_beacon()

	if _lan_listener != null and _lan_listener.is_bound():
		_poll_lan_listener()

func _get_security_manager() -> Node:
	if is_inside_tree():
		var autoload_sec := get_node_or_null("/root/SecurityManager")
		if autoload_sec != null:
			return autoload_sec
	if _fallback_security_manager == null:
		_fallback_security_manager = SecurityManagerScript.new()
		add_child(_fallback_security_manager)
	return _fallback_security_manager

func host_lobby(
	lobby_name: String,
	port: int,
	invite_code: String,
	max_players: int = 8,
	use_lan_broadcast: bool = true
) -> Dictionary:
	close_lobby()

	is_host = true
	local_peer_id = 1
	active_lobby_name = lobby_name.strip_edges() if not lobby_name.strip_edges().is_empty() else "Draw for Fight Lobby"
	active_port = clampi(port, 1024, 65535)
	active_invite_code = invite_code if not invite_code.is_empty() else "D4F-OPEN"
	max_lobby_players = clampi(max_players, D4FConstants.MIN_PLAYERS, D4FConstants.MAX_PLAYERS)
	active_lobby_id = "D4F-%d-%04d" % [active_port, randi() % 10000]

	var sec := _get_security_manager()
	sec.call("configure_lobby_security", active_lobby_id, active_invite_code, true)

	var enet_started := false
	_enet_peer = ENetMultiplayerPeer.new()
	var err := _enet_peer.create_server(active_port, max_lobby_players)
	if err == OK:
		enet_started = true
		if is_inside_tree() and multiplayer != null:
			multiplayer.multiplayer_peer = _enet_peer
			_connect_multiplayer_signals()
	else:
		_enet_peer = null

	# Authenticate local host peer (peer_id = 1) through all 8 security layers
	sec.call("complete_full_handshake_simulation", 1, active_lobby_id, active_invite_code)

	var default_char := CreationData.create_default_stickman("Host Stickman", "#33aaff")
	var default_veh := CreationData.create_default_vehicle("Host Racer", "#33aaff")
	var host_info := {
		"peer_id": 1,
		"name": local_player_name,
		"is_host": true,
		"is_bot": false,
		"ready": true,
		"color": "#33aaff",
		"score": 0,
		"character_creation": default_char.to_dict(),
		"vehicle_creation": default_veh.to_dict(),
		"reconnect_token": issue_reconnect_token(1)
	}
	players[1] = host_info

	_lan_broadcast_enabled = use_lan_broadcast
	if _lan_broadcast_enabled:
		_setup_lan_broadcaster()

	lobby_created.emit(active_lobby_id, active_port)
	player_joined.emit(1, host_info)

	return {
		"ok": true,
		"lobby_id": active_lobby_id,
		"lobby_name": active_lobby_name,
		"port": active_port,
		"max_players": max_lobby_players,
		"enet_active": enet_started,
		"host_peer_id": 1
	}

func join_lobby(
	host_address: String,
	port: int,
	lobby_id: String,
	invite_code: String,
	player_name: String
) -> Dictionary:
	close_lobby()

	var clean_addr := host_address.strip_edges() if not host_address.strip_edges().is_empty() else "127.0.0.1"
	active_port = clampi(port, 1024, 65535)
	active_lobby_id = lobby_id if not lobby_id.is_empty() else ("D4F-%d" % active_port)
	active_invite_code = invite_code if not invite_code.is_empty() else "D4F-OPEN"
	local_player_name = player_name.strip_edges() if not player_name.strip_edges().is_empty() else "Challenger"
	is_host = false

	var sec := _get_security_manager()
	sec.call("configure_lobby_security", active_lobby_id, active_invite_code, true)

	_enet_peer = ENetMultiplayerPeer.new()
	var err := _enet_peer.create_client(clean_addr, active_port)
	var enet_connected := (err == OK)
	if enet_connected and is_inside_tree() and multiplayer != null:
		multiplayer.multiplayer_peer = _enet_peer
		_connect_multiplayer_signals()
		local_peer_id = _enet_peer.get_unique_id()
	else:
		_enet_peer = null
		local_peer_id = 2

	var hs_res: Dictionary = sec.call("complete_full_handshake_simulation", local_peer_id, active_lobby_id, active_invite_code)
	if not bool(hs_res.get("ok", false)):
		var fail_reason := String(hs_res.get("error", "Security handshake failed"))
		connection_failed.emit(fail_reason)
		return {"ok": false, "error": fail_reason}

	var default_char := CreationData.create_default_stickman(local_player_name + " Fighter", "#44dd88")
	var default_veh := CreationData.create_default_vehicle(local_player_name + " Kart", "#44dd88")
	var client_info := {
		"peer_id": local_peer_id,
		"name": local_player_name,
		"is_host": false,
		"is_bot": false,
		"ready": true,
		"color": "#44dd88",
		"score": 0,
		"character_creation": default_char.to_dict(),
		"vehicle_creation": default_veh.to_dict(),
		"reconnect_token": issue_reconnect_token(local_peer_id)
	}
	players[local_peer_id] = client_info

	lobby_joined.emit(active_lobby_id)
	player_joined.emit(local_peer_id, client_info)

	return {
		"ok": true,
		"lobby_id": active_lobby_id,
		"peer_id": local_peer_id,
		"enet_connected": enet_connected,
		"handshake": hs_res
	}

func close_lobby() -> void:
	_lan_broadcast_enabled = false
	if _lan_broadcaster != null:
		_lan_broadcaster.close()
		_lan_broadcaster = null
	if _enet_peer != null:
		_enet_peer.close()
		_enet_peer = null
	if is_inside_tree() and multiplayer != null:
		multiplayer.multiplayer_peer = null
	players.clear()
	interpolator.clear_all()
	relay.close_relay()
	active_lobby_id = ""

func add_bot_players(count: int) -> Array:
	if active_lobby_id.is_empty():
		host_lobby("Solo & Bot Practice Lobby", D4FConstants.DEFAULT_PORT, "D4F-BOTS", D4FConstants.MAX_PLAYERS, false)

	var added: Array = []
	var sec := _get_security_manager()
	var slots_available := maxi(0, max_lobby_players - players.size())
	var to_add := mini(maxi(0, count), slots_available)

	for i in range(to_add):
		_bot_counter += 1
		var bot_peer_id := _bot_counter
		var idx := (players.size() - 1) % BOT_NAMES.size()
		var bot_name := BOT_NAMES[idx]
		var bot_color := BOT_COLORS[idx]

		sec.call("complete_full_handshake_simulation", bot_peer_id, active_lobby_id, active_invite_code)

		var char_c := CreationData.create_default_stickman(bot_name + " Stick", bot_color)
		var veh_c := CreationData.create_default_vehicle(bot_name + " Wheeler", bot_color)
		var bot_info := {
			"peer_id": bot_peer_id,
			"name": bot_name,
			"is_host": false,
			"is_bot": true,
			"ready": true,
			"color": bot_color,
			"score": 0,
			"character_creation": char_c.to_dict(),
			"vehicle_creation": veh_c.to_dict(),
			"reconnect_token": issue_reconnect_token(bot_peer_id)
		}
		players[bot_peer_id] = bot_info
		added.append(bot_info)
		player_joined.emit(bot_peer_id, bot_info)

	return added

func simulate_multiplayer_session(player_count: int, lobby_id: String, invite_code: String) -> Dictionary:
	var target_count := clampi(player_count, D4FConstants.MIN_PLAYERS, D4FConstants.MAX_PLAYERS)
	var sec := _get_security_manager()
	sec.call("configure_lobby_security", lobby_id, invite_code, true)

	var test_map := MapData.create_default_arena(D4FConstants.CompetitionMode.RACE)
	sec.call("set_active_map_reference", test_map)

	var authenticated_peers: Array[int] = []
	var verified_packets := 0

	for p_idx in range(target_count):
		var pid := p_idx + 1
		var hs_res: Dictionary = sec.call("complete_full_handshake_simulation", pid, lobby_id, invite_code)
		if not bool(hs_res.get("ok", false)):
			return {
				"ok": false,
				"failed_peer": pid,
				"error": String(hs_res.get("error", "Handshake failed"))
			}
		authenticated_peers.append(pid)

		# Seal & verify a physics input packet (Layers 6, 7, 8)
		var input_payload := {
			"move_x": 0.5,
			"move_z": -1.0,
			"throttle": 1.0,
			"steer": -0.25,
			"jump": false,
			"boost": true,
			"input_seq": p_idx + 1
		}
		var sealed_in: Dictionary = sec.call("seal_packet", pid, "player_input", input_payload, "input")
		var opened_in: Dictionary = sec.call("open_and_validate_packet", pid, pid == 1, sealed_in, "input")
		if not bool(opened_in.get("ok", false)):
			return {
				"ok": false,
				"failed_peer": pid,
				"error": String(opened_in.get("error", "Input packet validation failed"))
			}
		verified_packets += 1

		# Seal & verify a collaborative map object placement packet
		var map_obj_payload := {
			"type": "bumper",
			"position": [float(p_idx) * 3.0 - 9.0, 1.5, -5.0],
			"rotation": [0.0, 0.0, 0.0],
			"scale": [2.5, 2.0, 2.5],
			"color": BOT_COLORS[p_idx % BOT_COLORS.size()]
		}
		var sealed_map: Dictionary = sec.call("seal_packet", pid, "map_add_object", map_obj_payload, "map_edit")
		var opened_map: Dictionary = sec.call("open_and_validate_packet", pid, pid == 1, sealed_map, "map_edit")
		if not bool(opened_map.get("ok", false)):
			return {
				"ok": false,
				"failed_peer": pid,
				"error": String(opened_map.get("error", "Map edit validation failed"))
			}
		test_map.add_object(opened_map["payload"], pid, pid == 1)
		verified_packets += 1

	# Verify reconnect token flow for peer 2 (or peer 1 if solo)
	var test_peer := 2 if target_count >= 2 else 1
	var tok := issue_reconnect_token(test_peer)
	var recon_res := attempt_reconnect(test_peer, test_peer + 50, tok)

	return {
		"ok": true,
		"lobby_id": lobby_id,
		"player_count": target_count,
		"authenticated_peers": authenticated_peers,
		"packets_verified": verified_packets,
		"map_version": test_map.version,
		"reconnect_verified": bool(recon_res.get("ok", false))
	}

func issue_reconnect_token(peer_id: int) -> String:
	var raw := "%s|peer=%d|ts=%d|salt=%d" % [
		active_lobby_id,
		peer_id,
		Time.get_ticks_msec(),
		randi()
	]
	var token := D4FSerializer.compute_sha256_hex(raw)
	_reconnect_tokens[peer_id] = {
		"token": token,
		"issued_at_ms": Time.get_ticks_msec(),
		"player_snapshot": players.get(peer_id, {}).duplicate(true)
	}
	return token

func attempt_reconnect(previous_peer_id: int, new_peer_id: int, token: String) -> Dictionary:
	if not _reconnect_tokens.has(previous_peer_id):
		return {"ok": false, "error": "No reconnect record found for peer %d." % previous_peer_id}

	var entry: Dictionary = _reconnect_tokens[previous_peer_id]
	var expected_token := String(entry.get("token", ""))
	if expected_token.is_empty() or token.is_empty():
		return {"ok": false, "error": "Empty reconnect token."}

	var crypto := Crypto.new()
	var exp_bytes := expected_token.to_utf8_buffer()
	var rec_bytes := token.to_utf8_buffer()
	if exp_bytes.size() != rec_bytes.size() or not crypto.constant_time_compare(exp_bytes, rec_bytes):
		return {"ok": false, "error": "Invalid reconnect token."}

	var restored_info: Dictionary = entry.get("player_snapshot", {}).duplicate(true)
	restored_info["peer_id"] = new_peer_id
	players.erase(previous_peer_id)
	players[new_peer_id] = restored_info

	var sec := _get_security_manager()
	sec.call("remove_peer", previous_peer_id)
	sec.call("complete_full_handshake_simulation", new_peer_id, active_lobby_id, active_invite_code)
	issue_reconnect_token(new_peer_id)

	player_updated.emit(new_peer_id, restored_info)
	return {
		"ok": true,
		"previous_peer_id": previous_peer_id,
		"new_peer_id": new_peer_id,
		"player_info": restored_info
	}

func send_secure_action(target_peer: int, action: String, payload: Dictionary, category: String = "sync") -> Dictionary:
	var sec := _get_security_manager()
	var sender_id := local_peer_id
	if not bool(sec.call("is_peer_authenticated", sender_id)):
		sec.call("complete_full_handshake_simulation", sender_id, active_lobby_id, active_invite_code)

	var envelope: Dictionary = sec.call("seal_packet", sender_id, action, payload, category)
	if not bool(envelope.get("ok", false)):
		return envelope

	if _enet_peer != null and is_inside_tree() and multiplayer != null and multiplayer.has_multiplayer_peer():
		rpc_id(target_peer, "_rpc_receive_secure_envelope", envelope)
	else:
		# Local/loopback dispatch
		_handle_incoming_envelope(sender_id, envelope)

	return envelope

func broadcast_secure_action(action: String, payload: Dictionary, category: String = "sync") -> void:
	for pid in players.keys():
		send_secure_action(int(pid), action, payload, category)

@rpc("any_peer", "call_local", "reliable")
func _rpc_receive_secure_envelope(envelope: Dictionary) -> void:
	var sender_id := 1
	if is_inside_tree() and multiplayer != null and multiplayer.has_multiplayer_peer():
		sender_id = multiplayer.get_remote_sender_id()
		if sender_id == 0:
			sender_id = local_peer_id
	_handle_incoming_envelope(sender_id, envelope)

func _handle_incoming_envelope(sender_id: int, envelope: Dictionary) -> void:
	var sec := _get_security_manager()
	var sender_is_host := (sender_id == 1)
	var opened: Dictionary = sec.call(
		"open_and_validate_packet",
		sender_id,
		sender_is_host,
		envelope,
		String(envelope.get("category", "sync"))
	)
	if not bool(opened.get("ok", false)):
		return

	var action := String(opened.get("action", ""))
	var payload: Dictionary = opened.get("payload", {}) if typeof(opened.get("payload")) == TYPE_DICTIONARY else {}

	match action:
		"map_full_sync":
			map_sync_received.emit(payload)
		"map_add_object", "map_update_object", "map_remove_object", "map_add_stroke":
			map_delta_received.emit({"action": action, "peer_id": sender_id, "payload": payload})
		"match_state", "start_match":
			match_state_received.emit(payload)
		"score_update", "authoritative_scores":
			authoritative_scores_received.emit(payload)
		"submit_creation":
			if players.has(sender_id):
				var p_info: Dictionary = players[sender_id]
				var c_type := int(payload.get("creation_type", D4FConstants.CreationType.CHARACTER))
				if c_type == D4FConstants.CreationType.CHARACTER:
					p_info["character_creation"] = payload
				else:
					p_info["vehicle_creation"] = payload
				players[sender_id] = p_info
				player_updated.emit(sender_id, p_info)
		"ready_state":
			if players.has(sender_id):
				var p_info: Dictionary = players[sender_id]
				p_info["ready"] = bool(payload.get("ready", true))
				players[sender_id] = p_info
				player_updated.emit(sender_id, p_info)

func get_player_list() -> Array:
	var list: Array = []
	var ids := players.keys()
	ids.sort()
	for pid in ids:
		list.append(players[pid])
	return list

func set_local_player_ready(is_ready: bool) -> void:
	if players.has(local_peer_id):
		var info: Dictionary = players[local_peer_id]
		info["ready"] = is_ready
		players[local_peer_id] = info
		player_updated.emit(local_peer_id, info)

func set_local_player_creation(creation: CreationData) -> void:
	if creation == null:
		return
	var budgeted := MeshBudgetLimiter.enforce_creation_budget(creation)
	if players.has(local_peer_id):
		var info: Dictionary = players[local_peer_id]
		if budgeted.creation_type == D4FConstants.CreationType.CHARACTER:
			info["character_creation"] = budgeted.to_dict()
		else:
			info["vehicle_creation"] = budgeted.to_dict()
		players[local_peer_id] = info
		player_updated.emit(local_peer_id, info)

func _setup_lan_broadcaster() -> void:
	_lan_broadcaster = PacketPeerUDP.new()
	_lan_broadcaster.set_broadcast_enabled(true)
	_lan_broadcaster.set_dest_address("255.255.255.255", D4FConstants.LAN_BROADCAST_PORT)

func _broadcast_lan_beacon() -> void:
	if _lan_broadcaster == null:
		return
	var beacon := {
		"protocol": D4FConstants.PROTOCOL_VERSION,
		"lobby_id": active_lobby_id,
		"lobby_name": active_lobby_name,
		"port": active_port,
		"players": players.size(),
		"max_players": max_lobby_players
	}
	var json_str := D4FSerializer.to_json_safe(beacon)
	_lan_broadcaster.put_packet(json_str.to_utf8_buffer())

func start_lan_listener() -> bool:
	stop_lan_listener()
	_lan_listener = PacketPeerUDP.new()
	var err := _lan_listener.bind(D4FConstants.LAN_BROADCAST_PORT)
	if err != OK:
		_lan_listener = null
		return false
	return true

func stop_lan_listener() -> void:
	if _lan_listener != null:
		_lan_listener.close()
		_lan_listener = null

func _poll_lan_listener() -> void:
	var updated := false
	while _lan_listener.get_available_packet_count() > 0:
		var pkt := _lan_listener.get_packet()
		var sender_ip := _lan_listener.get_packet_ip()
		var parsed: Variant = D4FSerializer.from_json_safe(pkt.get_string_from_utf8(), 2048)
		if typeof(parsed) == TYPE_DICTIONARY:
			var d: Dictionary = parsed
			if String(d.get("protocol", "")) == D4FConstants.PROTOCOL_VERSION:
				var lid := String(d.get("lobby_id", ""))
				if not lid.is_empty():
					d["host_ip"] = sender_ip if not sender_ip.is_empty() else "127.0.0.1"
					d["last_seen_ms"] = Time.get_ticks_msec()
					_discovered_lan_lobbies[lid] = d
					updated = true
	if updated:
		lan_lobbies_updated.emit(get_discovered_lan_lobbies())

func get_discovered_lan_lobbies() -> Array:
	var out: Array = []
	for k in _discovered_lan_lobbies.keys():
		out.append(_discovered_lan_lobbies[k])
	return out

func _connect_multiplayer_signals() -> void:
	if multiplayer == null:
		return
	if not multiplayer.peer_connected.is_connected(_on_enet_peer_connected):
		multiplayer.peer_connected.connect(_on_enet_peer_connected)
	if not multiplayer.peer_disconnected.is_connected(_on_enet_peer_disconnected):
		multiplayer.peer_disconnected.connect(_on_enet_peer_disconnected)

func _on_enet_peer_connected(peer_id: int) -> void:
	var sec := _get_security_manager()
	sec.call("complete_full_handshake_simulation", peer_id, active_lobby_id, active_invite_code)
	var p_info := {
		"peer_id": peer_id,
		"name": "Player %d" % peer_id,
		"is_host": peer_id == 1,
		"is_bot": false,
		"ready": false,
		"color": BOT_COLORS[peer_id % BOT_COLORS.size()],
		"score": 0,
		"character_creation": CreationData.create_default_stickman("Fighter %d" % peer_id).to_dict(),
		"vehicle_creation": CreationData.create_default_vehicle("Racer %d" % peer_id).to_dict(),
		"reconnect_token": issue_reconnect_token(peer_id)
	}
	players[peer_id] = p_info
	player_joined.emit(peer_id, p_info)

func _on_enet_peer_disconnected(peer_id: int) -> void:
	players.erase(peer_id)
	interpolator.clear_peer(peer_id)
	player_left.emit(peer_id, "Peer disconnected")
