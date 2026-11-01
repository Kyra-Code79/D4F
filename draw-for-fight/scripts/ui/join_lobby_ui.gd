extends Control
## Screen 5: Join Lobby (`res://scenes/lobby/join_lobby.tscn`)
## Allows joining players to connect via Host IP/LAN broadcast, Lobby ID,
## and Invitation Passcode using the 8-Layer Security Handshake.

var _address_input: LineEdit = null
var _port_spin: SpinBox = null
var _lobby_id_input: LineEdit = null
var _invite_input: LineEdit = null
var _player_name_input: LineEdit = null
var _handshake_status_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 500)
	D4FUITheme.style_panel(panel)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(D4FUITheme.create_header_label("JOIN MULTIPLAYER LOBBY", 24, D4FUITheme.COLOR_ACCENT_BLUE))
	vbox.add_child(D4FUITheme.create_body_label(
		"Enter the Host PC's IP address (or 127.0.0.1 for local loopback), Lobby ID, and Invitation Passcode.",
		14, D4FUITheme.COLOR_TEXT_MUTED
	))
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	grid.add_child(D4FUITheme.create_body_label("Your Competitor Name:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_player_name_input = LineEdit.new()
	_player_name_input.text = "Challenger_" + str(randi_range(10, 99))
	_player_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_player_name_input)

	grid.add_child(D4FUITheme.create_body_label("Host IP / Address:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_address_input = LineEdit.new()
	_address_input.text = "127.0.0.1"
	grid.add_child(_address_input)

	grid.add_child(D4FUITheme.create_body_label("Host UDP Port:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_port_spin = SpinBox.new()
	_port_spin.min_value = 1024
	_port_spin.max_value = 65535
	_port_spin.value = D4FConstants.DEFAULT_PORT
	grid.add_child(_port_spin)

	grid.add_child(D4FUITheme.create_body_label("Lobby ID:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_lobby_id_input = LineEdit.new()
	_lobby_id_input.text = "LOBBY-101"
	grid.add_child(_lobby_id_input)

	grid.add_child(D4FUITheme.create_body_label("Invitation Passcode:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_invite_input = LineEdit.new()
	_invite_input.text = "D4F-2026"
	grid.add_child(_invite_input)

	vbox.add_child(HSeparator.new())
	_handshake_status_label = D4FUITheme.create_body_label(
		"Security Status: Ready for 8-Layer Handshake (L1 Lobby Auth → L2 DTLS → L3 Mutual → L4 Challenge → L5 HKDF → L6 AES-GCM/CBC+HMAC → L7 Anti-Replay → L8 RBAC)",
		13, D4FUITheme.COLOR_ACCENT_GOLD
	)
	vbox.add_child(_handshake_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)

	var back_btn := Button.new()
	back_btn.text = "← Back"
	back_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(back_btn, Color("#3d4a66"))
	back_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAIN_MENU)
	)
	btn_row.add_child(back_btn)

	var verify_btn := Button.new()
	verify_btn.text = "Test 8-Layer Handshake"
	verify_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(verify_btn, D4FUITheme.COLOR_ACCENT_ORANGE)
	verify_btn.pressed.connect(_on_test_handshake)
	btn_row.add_child(verify_btn)

	var join_btn := Button.new()
	join_btn.text = "Authenticate & Join Lobby →"
	join_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(join_btn, D4FUITheme.COLOR_ACCENT_BLUE)
	join_btn.pressed.connect(_on_join_pressed)
	btn_row.add_child(join_btn)

func _on_test_handshake() -> void:
	if has_node("/root/SecurityManager"):
		var sm := get_node("/root/SecurityManager")
		var lid := _lobby_id_input.text.strip_edges()
		var code := _invite_input.text.strip_edges()
		sm.configure_lobby_security(lid, code, true)
		var res: Dictionary = sm.complete_full_handshake_simulation(2, lid, code)
		if bool(res.get("authenticated", false)):
			_handshake_status_label.text = "8-Layer Handshake VERIFIED: Session Keys Derived & Encrypted Channel Ready!"
			get_node("/root/GameManager").notify_toast("8-Layer Security Handshake Verified!", "success")
		else:
			_handshake_status_label.text = "Handshake Rejected: " + String(res.get("error", "Invalid credentials"))

func _on_join_pressed() -> void:
	var gm := get_node("/root/GameManager")
	var nm := get_node("/root/NetworkManager")
	var addr := _address_input.text.strip_edges()
	var port := int(_port_spin.value)
	var lid := _lobby_id_input.text.strip_edges()
	var code := _invite_input.text.strip_edges()
	var pname := _player_name_input.text.strip_edges()

	var res: Dictionary = nm.join_lobby(addr, port, lid, code, pname)
	if bool(res.get("ok", false)):
		gm.notify_toast("Connected to " + addr + ":" + str(port) + " (" + lid + ")", "success")
		gm.navigate_to(D4FConstants.GameState.WAITING_ROOM)
	else:
		_handshake_status_label.text = "Connection error: " + String(res.get("error", "Could not reach host"))
		gm.notify_toast("Join failed: " + String(res.get("error", "Host unreachable")), "error")
