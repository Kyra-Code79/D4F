extends Control
## Screen 10: Results and Rankings (`res://scenes/competition/results_rankings.tscn`)
## Displays authoritative match results, winner banner, 8-player ranking breakdown,
## tie-breaker verification, career progression, and Rematch voting.

var _winner_label: Label = null
var _rankings_vbox: VBoxContainer = null
var _rematch_status_label: Label = null
var _career_Recorded: bool = false

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_populate_results()

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 42)
	margin.add_theme_constant_override("margin_right", 42)
	margin.add_theme_constant_override("margin_top", 32)
	margin.add_theme_constant_override("margin_bottom", 28)
	add_child(margin)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)

	var title := D4FUITheme.create_header_label("MATCH RESULTS & AUTHORITATIVE RANKINGS", 30, D4FUITheme.COLOR_ACCENT_GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	_winner_label = D4FUITheme.create_header_label("", 22, D4FUITheme.COLOR_ACCENT_GREEN)
	_winner_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_winner_label)

	var table_panel := PanelContainer.new()
	table_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_panel(table_panel)
	vbox.add_child(table_panel)

	var scroll := ScrollContainer.new()
	table_panel.add_child(scroll)

	_rankings_vbox = VBoxContainer.new()
	_rankings_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rankings_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_rankings_vbox)

	_rematch_status_label = D4FUITheme.create_body_label(
		"Tie-Breaker Policy: Total Points → Finish Time → Eliminations → Checkpoints → Survival Time → Peer ID",
		13, D4FUITheme.COLOR_TEXT_MUTED
	)
	_rematch_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_rematch_status_label)

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var menu_btn := Button.new()
	menu_btn.text = "← Main Menu"
	menu_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(menu_btn, Color("#3d4a66"))
	menu_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAIN_MENU)
	)
	btn_row.add_child(menu_btn)

	var edit_map_btn := Button.new()
	edit_map_btn.text = "Modify Arena in Map Editor"
	edit_map_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(edit_map_btn, D4FUITheme.COLOR_ACCENT_BLUE)
	edit_map_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAP_EDITOR)
	)
	btn_row.add_child(edit_map_btn)

	var rematch_btn := Button.new()
	rematch_btn.text = "Instant Rematch (Vote & Start) →"
	rematch_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(rematch_btn, D4FUITheme.COLOR_ACCENT_GREEN)
	rematch_btn.pressed.connect(_on_rematch_pressed)
	btn_row.add_child(rematch_btn)

func _populate_results() -> void:
	var mm := get_node_or_null("/root/MatchManager")
	var gm := get_node_or_null("/root/GameManager")
	if mm == null:
		return

	var rankings: Array = mm.last_match_rankings
	if rankings.is_empty():
		rankings = mm.compute_rankings()

	if not rankings.is_empty():
		var win: Dictionary = rankings[0]
		_winner_label.text = "CHAMPION: %s — %d Points!" % [
			String(win.get("name", "Player 1")),
			int(win.get("score", 0))
		]
	else:
		_winner_label.text = "Match Complete!"

	for child in _rankings_vbox.get_children():
		child.queue_free()

	for i in range(rankings.size()):
		var r: Dictionary = rankings[i]
		var card := PanelContainer.new()
		var border_col := D4FUITheme.COLOR_ACCENT_GOLD if i == 0 else D4FUITheme.COLOR_PANEL_BORDER
		D4FUITheme.style_panel(card, Color("#202842") if i == 0 else Color("#181e31"), border_col, 6)

		var ftime := float(r.get("finish_time", 999999.0))
		var time_str := ("Finished %.1fs" % ftime) if bool(r.get("finished", false)) else ("Survived %.1fs" % float(r.get("survival_time", 0.0)))
		var line := "#%d  |  %s  |  Score: %d pts  |  Checkpoints: %d  |  KOs: %d  |  %s" % [
			i + 1,
			String(r.get("name", "Competitor")),
			int(r.get("score", 0)),
			int(r.get("checkpoints", 0)),
			int(r.get("eliminations", 0)),
			time_str
		]
		var lbl := D4FUITheme.create_body_label(line, 15, D4FUITheme.COLOR_TEXT_MAIN)
		card.add_child(lbl)
		_rankings_vbox.add_child(card)

		if not _career_Recorded and gm != null and int(r.get("id", 0)) == 1:
			_career_Recorded = true
			gm.record_match_outcome(int(r.get("score", 0)), i == 0, int(r.get("eliminations", 0)))

func _on_rematch_pressed() -> void:
	var mm := get_node_or_null("/root/MatchManager")
	var gm := get_node_or_null("/root/GameManager")
	if mm != null and gm != null:
		var vote_res: Dictionary = mm.vote_rematch(1)
		_rematch_status_label.text = "Rematch Votes: %d / %d — Launching Rematch #%d!" % [
			int(vote_res.get("votes", 1)),
			int(vote_res.get("needed", 1)),
			mm.match_number + 1
		]
		mm.trigger_rematch()
		gm.navigate_to(D4FConstants.GameState.ARENA_COMPETITION)
