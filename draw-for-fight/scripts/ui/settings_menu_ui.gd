extends Control
## Screen 11: Settings (`res://scenes/menus/settings_menu.tscn`)
## Configures graphics presets for low-to-mid-range Windows 10/11 PCs,
## audio volumes, mouse/keyboard controls, and optional AI features.

var _preset_opt: OptionButton = null
var _fullscreen_check: CheckButton = null
var _vsync_check: CheckButton = null
var _fps_spin: SpinBox = null
var _master_slider: HSlider = null
var _sfx_slider: HSlider = null
var _sens_slider: HSlider = null
var _ai_design_check: CheckButton = null
var _ai_bots_check: CheckButton = null

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_current_settings()

func _build_ui() -> void:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(680, 520)
	D4FUITheme.style_panel(panel)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	panel.add_child(vbox)

	vbox.add_child(D4FUITheme.create_header_label("SETTINGS — GRAPHICS, AUDIO, CONTROLS & AI", 24, D4FUITheme.COLOR_ACCENT_BLUE))
	vbox.add_child(D4FUITheme.create_body_label(
		"Optimized for Windows 10 x64 & Windows 11 low-to-mid-range PCs (GL Compatibility + Jolt 3D Physics).",
		13, D4FUITheme.COLOR_TEXT_MUTED
	))
	vbox.add_child(HSeparator.new())

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 10)
	vbox.add_child(grid)

	grid.add_child(D4FUITheme.create_body_label("Graphics Quality Preset:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_preset_opt = OptionButton.new()
	_preset_opt.add_item("low")
	_preset_opt.add_item("medium")
	_preset_opt.add_item("high")
	_preset_opt.item_selected.connect(func(idx: int):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").apply_graphics_preset(_preset_opt.get_item_text(idx))
	)
	grid.add_child(_preset_opt)

	grid.add_child(D4FUITheme.create_body_label("Display Mode:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_fullscreen_check = CheckButton.new()
	_fullscreen_check.text = "Fullscreen Window"
	_fullscreen_check.toggled.connect(func(v: bool):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("graphics", "fullscreen", v)
	)
	grid.add_child(_fullscreen_check)

	grid.add_child(D4FUITheme.create_body_label("Vertical Sync (VSync):", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_vsync_check = CheckButton.new()
	_vsync_check.text = "Enable VSync"
	_vsync_check.toggled.connect(func(v: bool):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("graphics", "vsync", v)
	)
	grid.add_child(_vsync_check)

	grid.add_child(D4FUITheme.create_body_label("Max Frame Rate Cap:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_fps_spin = SpinBox.new()
	_fps_spin.min_value = 30
	_fps_spin.max_value = 240
	_fps_spin.step = 15
	_fps_spin.value = 60
	_fps_spin.value_changed.connect(func(v: float):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("graphics", "max_fps", int(v))
	)
	grid.add_child(_fps_spin)

	grid.add_child(D4FUITheme.create_body_label("Master Audio Volume:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_master_slider = HSlider.new()
	_master_slider.min_value = 0.0
	_master_slider.max_value = 1.0
	_master_slider.step = 0.05
	_master_slider.value = 0.85
	_master_slider.value_changed.connect(func(v: float):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("audio", "master_volume", v)
	)
	grid.add_child(_master_slider)

	grid.add_child(D4FUITheme.create_body_label("Sound Effects (SFX) Volume:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_sfx_slider = HSlider.new()
	_sfx_slider.min_value = 0.0
	_sfx_slider.max_value = 1.0
	_sfx_slider.step = 0.05
	_sfx_slider.value = 0.90
	_sfx_slider.value_changed.connect(func(v: float):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("audio", "sfx_volume", v)
	)
	grid.add_child(_sfx_slider)

	grid.add_child(D4FUITheme.create_body_label("Camera Mouse Sensitivity:", 15, D4FUITheme.COLOR_TEXT_MAIN))
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.1
	_sens_slider.max_value = 1.0
	_sens_slider.step = 0.05
	_sens_slider.value = 0.35
	_sens_slider.value_changed.connect(func(v: float):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("controls", "mouse_sensitivity", v)
	)
	grid.add_child(_sens_slider)

	vbox.add_child(HSeparator.new())
	vbox.add_child(D4FUITheme.create_header_label("OPTIONAL AI ASSISTANT FEATURES (100% OFFLINE / NO API KEYS)", 16, D4FUITheme.COLOR_ACCENT_GOLD))

	_ai_design_check = CheckButton.new()
	_ai_design_check.text = "Enable AI Character, Vehicle & Map Design Suggestions"
	_ai_design_check.button_pressed = true
	_ai_design_check.toggled.connect(func(v: bool):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("ai", "enable_design_suggestions", v)
	)
	vbox.add_child(_ai_design_check)

	_ai_bots_check = CheckButton.new()
	_ai_bots_check.text = "Enable AI NPC Bot Competitors for Unfilled Lobby Slots"
	_ai_bots_check.button_pressed = true
	_ai_bots_check.toggled.connect(func(v: bool):
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").set_setting("ai", "enable_bot_competitors", v)
	)
	vbox.add_child(_ai_bots_check)

	vbox.add_child(HSeparator.new())
	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var save_btn := Button.new()
	save_btn.text = "Save & Return to Main Menu"
	save_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(save_btn, D4FUITheme.COLOR_ACCENT_GREEN)
	save_btn.pressed.connect(func():
		if has_node("/root/SettingsManager"):
			get_node("/root/SettingsManager").save_settings()
		get_node("/root/GameManager").notify_toast("Settings saved!", "success")
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAIN_MENU)
	)
	btn_row.add_child(save_btn)

func _load_current_settings() -> void:
	if not has_node("/root/SettingsManager"):
		return
	var sm := get_node("/root/SettingsManager")
	var preset := String(sm.get_setting("graphics", "quality_preset", "medium"))
	for i in range(_preset_opt.item_count):
		if _preset_opt.get_item_text(i) == preset:
			_preset_opt.selected = i
			break
	_fullscreen_check.button_pressed = bool(sm.get_setting("graphics", "fullscreen", false))
	_vsync_check.button_pressed = bool(sm.get_setting("graphics", "vsync", true))
	_fps_spin.value = float(sm.get_setting("graphics", "max_fps", 60))
	_master_slider.value = float(sm.get_setting("audio", "master_volume", 0.85))
	_sfx_slider.value = float(sm.get_setting("audio", "sfx_volume", 0.90))
	_sens_slider.value = float(sm.get_setting("controls", "mouse_sensitivity", 0.35))
	_ai_design_check.button_pressed = bool(sm.get_setting("ai", "enable_design_suggestions", true))
	_ai_bots_check.button_pressed = bool(sm.get_setting("ai", "enable_bot_competitors", true))
