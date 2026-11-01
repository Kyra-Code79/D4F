extends Control
## Screen 4: Create Lobby (`res://scenes/lobby/create_lobby.tscn`)
## Configures self-hosted authoritative server parameters, 8-layer security
## invitation passcode, competition mode, and launches the lobby.

var _lobby_name_input: LineEdit = null
var _port_input: SpinBox = null
var _invite_code_input: LineEdit = null
var _max_players_spin: SpinBox = null
var _mode_option: OptionButton = null
var _prep_time_spin: SpinBox = null
var _match_time_spin: SpinBox = null
var _lan_check: CheckButton = null
var _relay_check: CheckButton = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(640, 520)
	D4FUITheme.style_panel(panel)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(D4FUITheme.create_header_label("CREATE SELF-HOSTED MULTIPLAYER LOBBY", 24, D4FUITheme.COLOR_ACCENT_GREEN))
	vbox.add_child(D4FUITheme.create_body_label(
		"Your PC acts as the authoritative competition host while you play locally. Protected by the 8-Layer Security Handshake.",
		14, D4FUITheme.COLOR_TEXT_MUTED
	))
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	grid.add_child(D4FUITheme.create_body_label("Lobby Name:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_lobby_name_input = LineEdit.new()
	_lobby_name_input.text = "D4F Championship Lobby"
	_lobby_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(_lobby_name_input)

	grid.add_child(D4FUITheme.create_body_label("ENet UDP Port:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_port_input = SpinBox.new()
	_port_input.min_value = 1024
	_port_input.max_value = 65535
	_port_input.value = D4FConstants.DEFAULT_PORT
	grid.add_child(_port_input)

	grid.add_child(D4FUITheme.create_body_label("Invitation Passcode (Layer 1 & 5 Auth):", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_invite_code_input = LineEdit.new()
	_invite_code_input.text = "D4F-" + str(randi_range(1000, 9999))
	grid.add_child(_invite_code_input)

	grid.add_child(D4FUITheme.create_body_label("Max Players (up to 8):", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_max_players_spin = SpinBox.new()
	_max_players_spin.min_value = 2
	_max_players_spin.max_value = 8
	_max_players_spin.value = 8
	grid.add_child(_max_players_spin)

	grid.add_child(D4FUITheme.create_body_label("Competition Mode:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_mode_option = OptionButton.new()
	_mode_option.add_item("Mode A: Race Competition (Vehicles / Finish Line)")
	_mode_option.add_item("Mode B: Obstacle Survival (Last Standing Wins)")
	_mode_option.add_item("Mode C: Physics Battle (Knockout Arena)")
	_mode_option.add_item("Mode D: Custom Challenge (Host Configurable)")
	grid.add_child(_mode_option)

	grid.add_child(D4FUITheme.create_body_label("Map Preparation Timer (sec):", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_prep_time_spin = SpinBox.new()
	_prep_time_spin.min_value = 15
	_prep_time_spin.max_value = 300
	_prep_time_spin.step = 15
	_prep_time_spin.value = 90
	grid.add_child(_prep_time_spin)

	grid.add_child(D4FUITheme.create_body_label("Match Duration Limit (sec):", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_match_time_spin = SpinBox.new()
	_match_time_spin.min_value = 60
	_match_time_spin.max_value = 600
	_match_time_spin.step = 30
	_match_time_spin.value = 180
	grid.add_child(_match_time_spin)

	_lan_check = CheckButton.new()
	_lan_check.text = "Enable LAN UDP Discovery Broadcast"
	_lan_check.button_pressed = true
	vbox.add_child(_lan_check)

	_relay_check = CheckButton.new()
	_relay_check.text = "Enable Optional NAT Relay Bridge Fallback"
	_relay_check.button_pressed = false
	vbox.add_child(_relay_check)

	vbox.add_child(HSeparator.new())

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var cancel_btn := Button.new()
	cancel_btn.text = "← Cancel"
	cancel_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(cancel_btn, Color("#3d4a66"))
	cancel_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAIN_MENU)
	)
	btn_row.add_child(cancel_btn)

	var host_btn := Button.new()
	host_btn.text = "Launch Host Server & Enter Waiting Room →"
	host_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(host_btn, D4FUITheme.COLOR_ACCENT_GREEN)
	host_btn.pressed.connect(_on_launch_lobby)
	btn_row.add_child(host_btn)

func _on_launch_lobby() -> void:
	var gm := get_node("/root/GameManager")
	var nm := get_node("/root/NetworkManager")
	var lobby_name := _lobby_name_input.text.strip_edges()
	if lobby_name.is_empty():
		lobby_name = "D4F Arena"
	var port := int(_port_input.value)
	var invite := _invite_code_input.text.strip_edges()
	if invite.is_empty():
		invite = "D4F-OPEN"
	var max_p := int(_max_players_spin.value)
	var mode_idx := _mode_option.selected

	gm.selected_mode = mode_idx
	gm.active_map = MapData.create_default_arena(mode_idx)
	gm.active_map.prep_time_limit = float(_prep_time_spin.value)
	gm.current_lobby_config = {
		"lobby_name": lobby_name,
		"port": port,
		"invite_code": invite,
		"max_players": max_p,
		"prep_time_sec": float(_prep_time_spin.value),
		"match_time_sec": float(_match_time_spin.value)
	}

	var res: Dictionary = nm.host_lobby(lobby_name, port, invite, max_p, _lan_check.button_pressed)
	if bool(res.get("ok", false)):
		gm.current_lobby_config["lobby_id"] = String(res.get("lobby_id", "LOBBY-101"))
		gm.notify_toast("Hosted Lobby '" + lobby_name + "' on UDP port " + str(port), "success")
		gm.navigate_to(D4FConstants.GameState.WAITING_ROOM)
	else:
		gm.notify_toast("Failed to bind port: " + String(res.get("error", "Unknown error")), "error")
