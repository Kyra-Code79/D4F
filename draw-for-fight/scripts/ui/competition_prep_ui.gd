extends Control
## Screen 8: Competition Preparation (`res://scenes/competition/competition_prep.tscn`)
## Final pre-match briefing screen where Host confirms competition mode,
## custom challenge rules, creation loadout, and starts the 3D Arena match.

var _mode_option: OptionButton = null
var _use_vehicles_check: CheckButton = null
var _lives_spin: SpinBox = null
var _time_limit_spin: SpinBox = null
var _gravity_spin: SpinBox = null
var _summary_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_summary()

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(720, 520)
	D4FUITheme.style_panel(panel)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(D4FUITheme.create_header_label("COMPETITION PREPARATION & BRIEFING", 26, D4FUITheme.COLOR_ACCENT_GOLD))
	vbox.add_child(D4FUITheme.create_body_label(
		"Review mode rules, competitor creations, and arena parameters before entering the 3D Competition Arena.",
		14, D4FUITheme.COLOR_TEXT_MUTED
	))
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	grid.add_child(D4FUITheme.create_body_label("Competition Mode:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_mode_option = OptionButton.new()
	_mode_option.add_item("Mode A: Race Competition (Reach Finish First)")
	_mode_option.add_item("Mode B: Obstacle Survival (Last Standing Wins)")
	_mode_option.add_item("Mode C: Physics Battle (Knockout Sumo Arena)")
	_mode_option.add_item("Mode D: Custom Challenge (Host Rules)")
	if has_node("/root/GameManager"):
		_mode_option.selected = get_node("/root/GameManager").selected_mode
	_mode_option.item_selected.connect(func(idx: int):
		if has_node("/root/GameManager"):
			get_node("/root/GameManager").selected_mode = idx
		_use_vehicles_check.button_pressed = (idx == D4FConstants.CompetitionMode.RACE)
		_refresh_summary()
	)
	grid.add_child(_mode_option)

	grid.add_child(D4FUITheme.create_body_label("Competitor Loadout Type:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_use_vehicles_check = CheckButton.new()
	_use_vehicles_check.text = "Use Custom 3D Vehicles (Off = 3D Stickman Characters)"
	_use_vehicles_check.button_pressed = (_mode_option.selected == D4FConstants.CompetitionMode.RACE)
	grid.add_child(_use_vehicles_check)

	grid.add_child(D4FUITheme.create_body_label("Match Time Limit (seconds):", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_time_limit_spin = SpinBox.new()
	_time_limit_spin.min_value = 30
	_time_limit_spin.max_value = 600
	_time_limit_spin.step = 15
	_time_limit_spin.value = 180
	grid.add_child(_time_limit_spin)

	grid.add_child(D4FUITheme.create_body_label("Lives per Player (Physics/Custom):", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_lives_spin = SpinBox.new()
	_lives_spin.min_value = 1
	_lives_spin.max_value = 10
	_lives_spin.value = 3
	grid.add_child(_lives_spin)

	grid.add_child(D4FUITheme.create_body_label("3D Gravity Multiplier:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_gravity_spin = SpinBox.new()
	_gravity_spin.min_value = 0.4
	_gravity_spin.max_value = 2.5
	_gravity_spin.step = 0.1
	_gravity_spin.value = 1.0
	grid.add_child(_gravity_spin)

	vbox.add_child(HSeparator.new())
	_summary_label = D4FUITheme.create_body_label("", 14, D4FUITheme.COLOR_ACCENT_GREEN)
	vbox.add_child(_summary_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 14)
	vbox.add_child(btn_row)

	var editor_btn := Button.new()
	editor_btn.text = "← Map Editor"
	editor_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(editor_btn, Color("#3d4a66"))
	editor_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAP_EDITOR)
	)
	btn_row.add_child(editor_btn)

	var start_btn := Button.new()
	start_btn.text = "LAUNCH 3D COMPETITION ARENA →"
	start_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(start_btn, D4FUITheme.COLOR_ACCENT_GREEN)
	start_btn.pressed.connect(_on_launch_arena)
	btn_row.add_child(start_btn)

func _refresh_summary() -> void:
	if _summary_label == null or not has_node("/root/GameManager"):
		return
	var gm := get_node("/root/GameManager")
	var nm := get_node_or_null("/root/NetworkManager")
	var p_count := nm.players.size() if (nm != null and not nm.players.is_empty()) else 8
	var map_name := gm.active_map.map_name if gm.active_map else "Collaborative Arena"
	_summary_label.text = (
		"Arena Map: %s (Validated) | Competitors Ready: %d / 8\nControls: WASD / Arrows to Move/Steer • SPACE to Jump/Brake • SHIFT/E to Shove/Boost" % [
			map_name, p_count
		]
	)

func _on_launch_arena() -> void:
	var gm := get_node("/root/GameManager")
	var mm := get_node("/root/MatchManager")
	var nm := get_node_or_null("/root/NetworkManager")

	var mode_id := _mode_option.selected
	gm.selected_mode = mode_id
	if gm.active_map == null:
		gm.active_map = MapData.create_default_arena(mode_id)

	var plist: Array = []
	if nm != null and not nm.players.is_empty():
		plist = nm.players.values()
	else:
		plist.append({
			"id": 1,
			"name": gm.player_profile.get("player_name", "HostPlayer"),
			"is_host": true,
			"is_bot": false,
			"creation": gm.get_active_creation_for_mode(mode_id).to_dict()
		})
		if has_node("/root/AIAssistantManager"):
			var ai := get_node("/root/AIAssistantManager")
			for b in range(1, 8):
				plist.append(ai.create_bot_participant(b, _use_vehicles_check.button_pressed))

	var rules := {
		"time_limit": float(_time_limit_spin.value),
		"max_lives": int(_lives_spin.value),
		"gravity_scale": float(_gravity_spin.value),
		"use_vehicles": _use_vehicles_check.button_pressed,
		"points_per_kill": 100,
		"points_per_checkpoint": 25
	}
	mm.setup_match(mode_id, plist, rules, true)
	gm.navigate_to(D4FConstants.GameState.ARENA_COMPETITION)
