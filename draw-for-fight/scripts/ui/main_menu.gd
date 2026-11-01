extends Control
## Screen 1: Main Menu (`res://scenes/menus/main_menu.tscn`)
## Provides navigation to Character/Vehicle Workshops, Host/Join Lobby,
## Collaborative Map Editor, Quick Solo/Bot Competition, and Settings.

var _profile_label: Label = null
var _active_creations_label: Label = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_refresh_summary()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 48)
	margin.add_theme_constant_override("margin_right", 48)
	margin.add_theme_constant_override("margin_top", 36)
	margin.add_theme_constant_override("margin_bottom", 36)
	add_child(margin)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 20)
	margin.add_child(main_vbox)

	# Title Banner
	var header_box := VBoxContainer.new()
	header_box.add_theme_constant_override("separation", 4)
	var title := D4FUITheme.create_header_label("DRAW FOR FIGHT", 42, D4FUITheme.COLOR_ACCENT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var subtitle := D4FUITheme.create_body_label(
		"Draw Your Fighter or Vehicle • Build the 3D Arena Together • Compete in Real-Time Physics Battles!",
		16, D4FUITheme.COLOR_TEXT_MAIN
	)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	header_box.add_child(title)
	header_box.add_child(subtitle)
	main_vbox.add_child(header_box)

	# Main Content Split: Left Navigation Column + Right Profile & Mode Card
	var hbox := HBoxContainer.new()
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_theme_constant_override("separation", 28)
	main_vbox.add_child(hbox)

	# Left Column: Primary Navigation Buttons
	var nav_panel := PanelContainer.new()
	nav_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_panel(nav_panel)
	hbox.add_child(nav_panel)

	var nav_vbox := VBoxContainer.new()
	nav_vbox.add_theme_constant_override("separation", 12)
	nav_panel.add_child(nav_vbox)

	nav_vbox.add_child(D4FUITheme.create_header_label("COMPETE & MULTIPLAYER", 20, D4FUITheme.COLOR_ACCENT_BLUE))

	_add_nav_button(nav_vbox, "Create Multiplayer Lobby (Host Server)", D4FUITheme.COLOR_ACCENT_GREEN, func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.CREATE_LOBBY)
	)
	_add_nav_button(nav_vbox, "Join Multiplayer Lobby (LAN / Invite Code)", D4FUITheme.COLOR_ACCENT_BLUE, func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.JOIN_LOBBY)
	)
	_add_nav_button(nav_vbox, "Quick Match vs AI Bots (Instant 8-Player Arena)", D4FUITheme.COLOR_ACCENT_ORANGE, func():
		_start_quick_bot_match()
	)

	nav_vbox.add_child(HSeparator.new())
	nav_vbox.add_child(D4FUITheme.create_header_label("CREATIVE WORKSHOPS", 20, D4FUITheme.COLOR_ACCENT_GOLD))

	_add_nav_button(nav_vbox, "Character Workshop (Stickman 2D-to-3D)", D4FUITheme.COLOR_ACCENT_BLUE, func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.CHARACTER_WORKSHOP)
	)
	_add_nav_button(nav_vbox, "Vehicle Workshop (Custom Racer 2D-to-3D)", D4FUITheme.COLOR_ACCENT_BLUE, func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.VEHICLE_WORKSHOP)
	)
	_add_nav_button(nav_vbox, "Collaborative 3D Map Editor", D4FUITheme.COLOR_ACCENT_BLUE, func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAP_EDITOR)
	)

	nav_vbox.add_child(HSeparator.new())
	var bottom_row := HBoxContainer.new()
	bottom_row.add_theme_constant_override("separation", 12)
	nav_vbox.add_child(bottom_row)

	var settings_btn := Button.new()
	settings_btn.text = "Settings & Graphics"
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(settings_btn, Color("#3d4a66"))
	settings_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.SETTINGS)
	)
	bottom_row.add_child(settings_btn)

	var quit_btn := Button.new()
	quit_btn.text = "Exit Game"
	quit_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(quit_btn, D4FUITheme.COLOR_DANGER)
	quit_btn.pressed.connect(func():
		get_tree().quit()
	)
	bottom_row.add_child(quit_btn)

	# Right Column: Player Profile, Active Creations & Mode Selector
	var info_panel := PanelContainer.new()
	info_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_panel(info_panel)
	hbox.add_child(info_panel)

	var info_vbox := VBoxContainer.new()
	info_vbox.add_theme_constant_override("separation", 14)
	info_panel.add_child(info_vbox)

	info_vbox.add_child(D4FUITheme.create_header_label("COMPETITOR PROFILE", 20, D4FUITheme.COLOR_ACCENT_GOLD))
	_profile_label = D4FUITheme.create_body_label("", 16, D4FUITheme.COLOR_TEXT_MAIN)
	info_vbox.add_child(_profile_label)

	info_vbox.add_child(HSeparator.new())
	info_vbox.add_child(D4FUITheme.create_header_label("ACTIVE 3D CREATIONS", 20, D4FUITheme.COLOR_ACCENT_GREEN))
	_active_creations_label = D4FUITheme.create_body_label("", 15, D4FUITheme.COLOR_TEXT_MAIN)
	info_vbox.add_child(_active_creations_label)

	info_vbox.add_child(HSeparator.new())
	info_vbox.add_child(D4FUITheme.create_header_label("COMPETITION MODES", 20, D4FUITheme.COLOR_ACCENT_BLUE))
	var modes_desc := D4FUITheme.create_body_label(
		"• Mode A — Race Competition: Reach the finish line first in custom vehicles.\n" +
		"• Mode B — Obstacle Survival: Survive spinners, gaps & hazards; last standing wins.\n" +
		"• Mode C — Physics Battle: Collide & shove opponents off the arena for KO points.\n" +
		"• Mode D — Custom Challenge: Host-configured gravity, lives & scoring rules.",
		14, D4FUITheme.COLOR_TEXT_MUTED
	)
	info_vbox.add_child(modes_desc)

func _add_nav_button(parent: Node, label_text: String, color: Color, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = label_text
	D4FUITheme.style_button(btn, color, Vector2(240, 44))
	btn.pressed.connect(callback)
	parent.add_child(btn)
	return btn

func _refresh_summary() -> void:
	if not has_node("/root/GameManager"):
		return
	var gm := get_node("/root/GameManager")
	var p: Dictionary = gm.player_profile
	if _profile_label != null:
		_profile_label.text = (
			"Competitor: %s\nRank Tier: %s\nCareer Points: %d pts\nMatches Won: %d / %d\nTotal Knockouts: %d" % [
				String(p.get("player_name", "Sketcher")),
				String(p.get("rank_title", "Rookie")),
				int(p.get("career_points", 0)),
				int(p.get("matches_won", 0)),
				int(p.get("matches_played", 0)),
				int(p.get("eliminations_total", 0))
			]
		)
	if _active_creations_label != null:
		var char_name := gm.active_character.creation_name if gm.active_character != null else "Default Stickman"
		var veh_name := gm.active_vehicle.creation_name if gm.active_vehicle != null else "Default Vehicle"
		var map_name := gm.active_map.map_name if gm.active_map != null else "Default Arena"
		_active_creations_label.text = (
			"Active Character: %s (3D Extruded)\nActive Vehicle: %s (3D Extruded)\nActive Arena Map: %s" % [
				char_name, veh_name, map_name
			]
		)

func _start_quick_bot_match() -> void:
	var gm := get_node("/root/GameManager")
	if has_node("/root/NetworkManager"):
		var nm := get_node("/root/NetworkManager")
		nm.host_lobby("Quick Bot Arena", 24800, "QUICK-BOT", 8, false)
		nm.add_bot_players(7) # 1 local host + 7 AI bots = 8 competitors
	gm.navigate_to(D4FConstants.GameState.COMPETITION_PREP)
