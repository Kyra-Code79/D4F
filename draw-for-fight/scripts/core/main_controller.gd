extends Control
## Root shell controller for `res://scenes/main/main.tscn`.
## Manages dynamic screen switching across all 11 required UI/3D screens,
## toast notifications, and the F3 performance/security telemetry overlay.

var _screen_container: Control = null
var _active_screen_node: Node = null
var _toast_label: Label = null
var _toast_panel: PanelContainer = null
var _toast_timer: float = 0.0
var _telemetry_label: Label = null
var _show_telemetry: bool = true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_root_layers()

	if has_node("/root/GameManager"):
		var gm := get_node("/root/GameManager")
		gm.game_state_changed.connect(_on_game_state_changed)
		gm.toast_requested.connect(_on_toast_requested)
		_load_screen_by_path(gm.SCREEN_SCENE_PATHS[D4FConstants.GameState.MAIN_MENU])
	else:
		_load_screen_by_path("res://scenes/menus/main_menu.tscn")

func _build_root_layers() -> void:
	var bg := ColorRect.new()
	bg.name = "RootBackground"
	bg.color = D4FUITheme.COLOR_BG_DARK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	_screen_container = Control.new()
	_screen_container.name = "ScreenContainer"
	_screen_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_container)

	_toast_panel = PanelContainer.new()
	_toast_panel.name = "ToastBanner"
	_toast_panel.visible = false
	D4FUITheme.style_panel(_toast_panel, Color("#1e272e"), D4FUITheme.COLOR_ACCENT_GOLD, 8)
	_toast_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast_panel.offset_top = 18.0
	_toast_panel.offset_left = -220.0
	_toast_panel.offset_right = 220.0
	_toast_label = D4FUITheme.create_body_label("", 15, Color.WHITE)
	_toast_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast_panel.add_child(_toast_label)
	add_child(_toast_panel)

	_telemetry_label = Label.new()
	_telemetry_label.name = "TelemetryOverlay"
	_telemetry_label.position = Vector2(12, 6)
	_telemetry_label.add_theme_font_size_override("font_size", 12)
	_telemetry_label.add_theme_color_override("font_color", Color(0.65, 0.85, 1.0, 0.8))
	add_child(_telemetry_label)

func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0 and _toast_panel != null:
			_toast_panel.visible = false

	if _show_telemetry and _telemetry_label != null:
		var fps := Engine.get_frames_per_second()
		var state_str := "MAIN_MENU"
		if has_node("/root/GameManager"):
			state_str = D4FConstants.state_to_string(get_node("/root/GameManager").current_state)
		var peer_count := 1
		if has_node("/root/NetworkManager"):
			peer_count = maxi(1, get_node("/root/NetworkManager").players.size())
		_telemetry_label.text = "D4F v%s | FPS: %d | Screen: %s | Players: %d/8 | Security: 8-Layer Active (F3 toggle)" % [
			D4FConstants.GAME_VERSION, fps, state_str, peer_count
		]

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F3:
			_show_telemetry = not _show_telemetry
			if _telemetry_label:
				_telemetry_label.visible = _show_telemetry

func _on_game_state_changed(_old_state: int, _new_state: int, scene_path: String) -> void:
	_load_screen_by_path(scene_path)

func _load_screen_by_path(scene_path: String) -> void:
	if _active_screen_node != null:
		_active_screen_node.queue_free()
		_active_screen_node = null

	if not ResourceLoader.exists(scene_path):
		push_warning("MainController: Scene not found: " + scene_path)
		return

	var packed: PackedScene = load(scene_path)
	if packed == null:
		return
	_active_screen_node = packed.instantiate()
	_screen_container.add_child(_active_screen_node)

func _on_toast_requested(message: String, severity: String) -> void:
	if _toast_panel == null or _toast_label == null:
		return
	var border_col := D4FUITheme.COLOR_ACCENT_BLUE
	if severity == "error":
		border_col = D4FUITheme.COLOR_DANGER
	elif severity == "success":
		border_col = D4FUITheme.COLOR_ACCENT_GREEN
	elif severity == "warning":
		border_col = D4FUITheme.COLOR_ACCENT_GOLD
	D4FUITheme.style_panel(_toast_panel, Color("#1e272e"), border_col, 8)
	_toast_label.text = message
	_toast_panel.visible = true
	_toast_timer = 3.5
