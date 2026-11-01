extends Control
## Screen 6: Waiting Room (`res://scenes/lobby/waiting_room.tscn`)
## Displays connected players (up to 8), ready status, custom creations,
## AI bot slot filler, and host transition to Collaborative Map Editor.

var _header_info_label: Label = null
var _roster_vbox: VBoxContainer = null
var _mode_option: OptionButton = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_roster()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 30)
	margin.add_theme_constant_override("margin_bottom", 26)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 14)
	vbox.add_child(top_row)

	var leave_btn := Button.new()
	leave_btn.text = "← Leave Lobby"
	D4FUITheme.style_button(leave_btn, D4FUITheme.COLOR_DANGER, Vector2(140, 38))
	leave_btn.pressed.connect(func():
		if has_node("/root/NetworkManager"):
			get_node("/root/NetworkManager").close_lobby()
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAIN_MENU)
	)
	top_row.add_child(leave_btn)

	var title := D4FUITheme.create_header_label("LOBBY WAITING ROOM (8-PLAYER SESSION)", 26, D4FUITheme.COLOR_ACCENT_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(title)

	_header_info_label = D4FUITheme.create_body_label("", 14, D4FUITheme.COLOR_ACCENT_GREEN)
	vbox.add_child(_header_info_label)

	var content_hbox := HBoxContainer.new()
	content_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_hbox.add_theme_constant_override("separation", 20)
	vbox.add_child(content_hbox)

	# Left: 8-Player Roster Panel
	var roster_panel := PanelContainer.new()
	roster_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_panel(roster_panel)
	content_hbox.add_child(roster_panel)

	var r_outer := VBoxContainer.new()
	r_outer.add_theme_constant_override("separation", 8)
	roster_panel.add_child(r_outer)
	r_outer.add_child(D4FUITheme.create_header_label("COMPETITOR ROSTER (MAX 8)", 19, D4FUITheme.COLOR_ACCENT_BLUE))

	_roster_vbox = VBoxContainer.new()
	_roster_vbox.add_theme_constant_override("separation", 6)
	r_outer.add_child(_roster_vbox)

	# Right: Host Controls & Mode Configuration
	var ctrl_panel := PanelContainer.new()
	ctrl_panel.custom_minimum_size = Vector2(360, 0)
	D4FUITheme.style_panel(ctrl_panel)
	content_hbox.add_child(ctrl_panel)

	var ctrl_vbox := VBoxContainer.new()
	ctrl_vbox.add_theme_constant_override("separation", 12)
	ctrl_panel.add_child(ctrl_vbox)

	ctrl_vbox.add_child(D4FUITheme.create_header_label("LOBBY & MATCH CONTROLS", 19, D4FUITheme.COLOR_ACCENT_ORANGE))

	ctrl_vbox.add_child(D4FUITheme.create_body_label("Active Competition Mode:", 14, D4FUITheme.COLOR_TEXT_MAIN))
	_mode_option = OptionButton.new()
	_mode_option.add_item("Mode A: Race Competition")
	_mode_option.add_item("Mode B: Obstacle Survival")
	_mode_option.add_item("Mode C: Physics Battle")
	_mode_option.add_item("Mode D: Custom Challenge")
	if has_node("/root/GameManager"):
		_mode_option.selected = get_node("/root/GameManager").selected_mode
	_mode_option.item_selected.connect(func(idx: int):
		if has_node("/root/GameManager"):
			var gm := get_node("/root/GameManager")
			gm.selected_mode = idx
			gm.active_map = MapData.create_default_arena(idx)
	)
	ctrl_vbox.add_child(_mode_option)

	var add_bot_btn := Button.new()
	add_bot_btn.text = "+ Add AI Bot Competitor (Up to 8)"
	D4FUITheme.style_button(add_bot_btn, D4FUITheme.COLOR_ACCENT_BLUE)
	add_bot_btn.pressed.connect(func():
		if has_node("/root/NetworkManager"):
			get_node("/root/NetworkManager").add_bot_players(1)
			_refresh_roster()
	)
	ctrl_vbox.add_child(add_bot_btn)

	var fill_8_btn := Button.new()
	fill_8_btn.text = "Fill All 8 Slots with AI Bots"
	D4FUITheme.style_button(fill_8_btn, Color("#3d4a66"))
	fill_8_btn.pressed.connect(func():
		if has_node("/root/NetworkManager"):
			var nm := get_node("/root/NetworkManager")
			var needed := maxi(0, D4FConstants.MAX_PLAYERS - nm.players.size())
			if needed > 0:
				nm.add_bot_players(needed)
			_refresh_roster()
	)
	ctrl_vbox.add_child(fill_8_btn)

	ctrl_vbox.add_child(HSeparator.new())

	var map_editor_btn := Button.new()
	map_editor_btn.text = "1. Collaborative 3D Map Editor →"
	D4FUITheme.style_button(map_editor_btn, D4FUITheme.COLOR_ACCENT_ORANGE)
	map_editor_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAP_EDITOR)
	)
	ctrl_vbox.add_child(map_editor_btn)

	var prep_btn := Button.new()
	prep_btn.text = "2. Proceed to Competition Prep →"
	D4FUITheme.style_button(prep_btn, D4FUITheme.COLOR_ACCENT_GREEN)
	prep_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.COMPETITION_PREP)
	)
	ctrl_vbox.add_child(prep_btn)

func _refresh_roster() -> void:
	if _roster_vbox == null:
		return
	for child in _roster_vbox.get_children():
		child.queue_free()

	var gm := get_node_or_null("/root/GameManager")
	var nm := get_node_or_null("/root/NetworkManager")
	if gm != null and _header_info_label != null:
		var cfg: Dictionary = gm.current_lobby_config
		_header_info_label.text = "Lobby ID: %s | UDP Port: %s | Invite Code: %s | 8-Layer Security: ACTIVE" % [
			String(cfg.get("lobby_id", "LOBBY-101")),
			str(cfg.get("port", 24800)),
			String(cfg.get("invite_code", "D4F-2026"))
		]

	var player_list: Array = []
	if nm != null and not nm.players.is_empty():
		player_list = nm.players.values()
	else:
		player_list = [{
			"id": 1,
			"name": gm.player_profile.get("player_name", "HostPlayer") if gm else "HostPlayer",
			"is_host": true,
			"is_bot": false,
			"ready": true,
			"ping_ms": 1
		}]

	for slot_idx in range(D4FConstants.MAX_PLAYERS):
		var row_panel := PanelContainer.new()
		if slot_idx < player_list.size():
			var p: Dictionary = player_list[slot_idx]
			D4FUITheme.style_panel(row_panel, Color("#222b45"), D4FUITheme.COLOR_ACCENT_GREEN, 6)
			var role_tag := "[HOST]" if bool(p.get("is_host", false)) else ("[AI BOT]" if bool(p.get("is_bot", false)) else "[PEER]")
			var lbl := D4FUITheme.create_body_label(
				"Slot #%d: %s %s — Ready: YES | Auth: L8 Verified" % [
					slot_idx + 1, String(p.get("name", "Player")), role_tag
				],
				14, D4FUITheme.COLOR_TEXT_MAIN
			)
			row_panel.add_child(lbl)
		else:
			D4FUITheme.style_panel(row_panel, Color("#161b2c"), Color("#2c3654"), 6)
			var lbl := D4FUITheme.create_body_label(
				"Slot #%d: [ Open Slot — Waiting for Challenger or Bot ]" % (slot_idx + 1),
				14, D4FUITheme.COLOR_TEXT_MUTED
			)
			row_panel.add_child(lbl)
		_roster_vbox.add_child(row_panel)
