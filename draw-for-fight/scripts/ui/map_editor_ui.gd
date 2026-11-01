extends Control
## Screen 7: Collaborative Map Editor (`res://scenes/map_editor/map_editor.tscn`)
## Supports simultaneous 2D top-down terrain drawing -> 3D extrusion AND
## direct 3D object placement with ownership permissions, preparation countdown,
## live MapValidator checks, versioning, and Host finalization.

var _editor_3d: CollaborativeMapEditor = null
var _selected_obj_type: String = "platform"
var _pos_x_spin: SpinBox = null
var _pos_y_spin: SpinBox = null
var _pos_z_spin: SpinBox = null
var _rot_y_spin: SpinBox = null
var _validation_label: Label = null
var _timer_label: Label = null
var _version_label: Label = null
var _object_list: ItemList = null
var _topdown_sketch_points: Array = []

const PLACEABLE_TYPES: Array[String] = [
	"road", "platform", "ramp", "wall", "bridge",
	"obstacle_spinner", "bumper", "checkpoint",
	"start_spawn", "finish_line", "hazard_lava", "hazard_ice"
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_init_editor_map()

func _process(delta: float) -> void:
	if _editor_3d != null and _editor_3d.is_timer_running:
		if _timer_label != null:
			_timer_label.text = "Prep Timer: %ds | Version: v%d" % [
				ceili(_editor_3d.prep_time_remaining),
				_editor_3d.current_map.version if _editor_3d.current_map else 1
			]
	elif _editor_3d != null and _editor_3d.current_map != null and _timer_label != null:
		_timer_label.text = "Map Version: v%d | Objects: %d/%d" % [
			_editor_3d.current_map.version,
			_editor_3d.current_map.objects.size(),
			D4FConstants.MAX_MAP_OBJECTS
		]

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 22)
	margin.add_theme_constant_override("margin_right", 22)
	margin.add_theme_constant_override("margin_top", 26)
	margin.add_theme_constant_override("margin_bottom", 18)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 10)
	margin.add_child(root_vbox)

	# Top Bar
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 12)
	root_vbox.add_child(top_bar)

	var back_btn := Button.new()
	back_btn.text = "← Waiting Room"
	D4FUITheme.style_button(back_btn, Color("#3d4a66"), Vector2(145, 38))
	back_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.WAITING_ROOM)
	)
	top_bar.add_child(back_btn)

	var title := D4FUITheme.create_header_label("COLLABORATIVE 3D MAP EDITOR", 23, D4FUITheme.COLOR_ACCENT_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)

	_timer_label = D4FUITheme.create_header_label("Prep Timer: 90s | v1", 17, D4FUITheme.COLOR_ACCENT_GREEN)
	top_bar.add_child(_timer_label)

	var finalize_btn := Button.new()
	finalize_btn.text = "Host: Finalize Map & Start Prep →"
	D4FUITheme.style_button(finalize_btn, D4FUITheme.COLOR_ACCENT_GREEN, Vector2(240, 38))
	finalize_btn.pressed.connect(_on_finalize_map)
	top_bar.add_child(finalize_btn)

	# Main 3-Column Layout: Left Object Palette | Center 3D Viewport + Top-Down 2D Extruder | Right Inspector & Validator
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 14)
	root_vbox.add_child(body_hbox)

	# Left Column: Object Palette & 2D Top-Down Extrusion Controls
	var left_panel := PanelContainer.new()
	left_panel.custom_minimum_size = Vector2(260, 0)
	D4FUITheme.style_panel(left_panel)
	body_hbox.add_child(left_panel)

	var left_vbox := VBoxContainer.new()
	left_vbox.add_theme_constant_override("separation", 8)
	left_panel.add_child(left_vbox)

	left_vbox.add_child(D4FUITheme.create_header_label("3D OBJECT PALETTE", 16, D4FUITheme.COLOR_ACCENT_BLUE))

	var type_opt := OptionButton.new()
	for t in PLACEABLE_TYPES:
		type_opt.add_item(t)
	type_opt.item_selected.connect(func(idx: int):
		_selected_obj_type = PLACEABLE_TYPES[idx]
	)
	left_vbox.add_child(type_opt)

	var coord_grid := GridContainer.new()
	coord_grid.columns = 2
	coord_grid.add_theme_constant_override("h_separation", 8)
	coord_grid.add_theme_constant_override("v_separation", 6)
	left_vbox.add_child(coord_grid)

	coord_grid.add_child(D4FUITheme.create_body_label("Pos X:", 13, D4FUITheme.COLOR_TEXT_MAIN))
	_pos_x_spin = SpinBox.new()
	_pos_x_spin.min_value = -55.0
	_pos_x_spin.max_value = 55.0
	_pos_x_spin.step = 2.0
	_pos_x_spin.value = 0.0
	coord_grid.add_child(_pos_x_spin)

	coord_grid.add_child(D4FUITheme.create_body_label("Pos Y (Height):", 13, D4FUITheme.COLOR_TEXT_MAIN))
	_pos_y_spin = SpinBox.new()
	_pos_y_spin.min_value = -5.0
	_pos_y_spin.max_value = 25.0
	_pos_y_spin.step = 0.5
	_pos_y_spin.value = 1.0
	coord_grid.add_child(_pos_y_spin)

	coord_grid.add_child(D4FUITheme.create_body_label("Pos Z:", 13, D4FUITheme.COLOR_TEXT_MAIN))
	_pos_z_spin = SpinBox.new()
	_pos_z_spin.min_value = -55.0
	_pos_z_spin.max_value = 55.0
	_pos_z_spin.step = 2.0
	_pos_z_spin.value = -10.0
	coord_grid.add_child(_pos_z_spin)

	coord_grid.add_child(D4FUITheme.create_body_label("Yaw Angle (deg):", 13, D4FUITheme.COLOR_TEXT_MAIN))
	_rot_y_spin = SpinBox.new()
	_rot_y_spin.min_value = -180.0
	_rot_y_spin.max_value = 180.0
	_rot_y_spin.step = 15.0
	_rot_y_spin.value = 0.0
	coord_grid.add_child(_rot_y_spin)

	var place_btn := Button.new()
	place_btn.text = "+ Place 3D Object in Arena"
	D4FUITheme.style_button(place_btn, D4FUITheme.COLOR_ACCENT_BLUE, Vector2(210, 38))
	place_btn.pressed.connect(_on_place_3d_object)
	left_vbox.add_child(place_btn)

	left_vbox.add_child(HSeparator.new())
	left_vbox.add_child(D4FUITheme.create_header_label("2D-TO-3D TERRAIN EXTRUDER", 16, D4FUITheme.COLOR_ACCENT_ORANGE))
	left_vbox.add_child(D4FUITheme.create_body_label(
		"Extrude a top-down 2D drawn road or bridge path directly into 3D arena geometry:",
		12, D4FUITheme.COLOR_TEXT_MUTED
	))

	var extrude_road_btn := Button.new()
	extrude_road_btn.text = "Draw & Extrude 3D Curved Road"
	D4FUITheme.style_button(extrude_road_btn, D4FUITheme.COLOR_ACCENT_ORANGE, Vector2(210, 36))
	extrude_road_btn.pressed.connect(_on_extrude_sample_2d_road)
	left_vbox.add_child(extrude_road_btn)

	left_vbox.add_child(HSeparator.new())
	var ai_suggest_btn := Button.new()
	ai_suggest_btn.text = "AI Architect: Add Obstacles"
	D4FUITheme.style_button(ai_suggest_btn, D4FUITheme.COLOR_ACCENT_GOLD, Vector2(210, 36))
	ai_suggest_btn.pressed.connect(_on_ai_suggest_obstacles)
	left_vbox.add_child(ai_suggest_btn)

	var save_map_btn := Button.new()
	save_map_btn.text = "Save Map to Disk"
	D4FUITheme.style_button(save_map_btn, Color("#3d4a66"), Vector2(210, 34))
	save_map_btn.pressed.connect(func():
		if _editor_3d and _editor_3d.current_map:
			get_node("/root/GameManager").save_map_to_disk(_editor_3d.current_map)
			get_node("/root/GameManager").notify_toast("Saved map '" + _editor_3d.current_map.map_name + "' (v" + str(_editor_3d.current_map.version) + ")", "success")
	)
	left_vbox.add_child(save_map_btn)

	# Center Column: Live 3D Arena Preview Viewport
	var vp_panel := PanelContainer.new()
	vp_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_panel(vp_panel, Color("#101420"), D4FUITheme.COLOR_ACCENT_BLUE)
	body_hbox.add_child(vp_panel)

	var sub_vp_container := SubViewportContainer.new()
	sub_vp_container.stretch = true
	sub_vp_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sub_vp_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vp_panel.add_child(sub_vp_container)

	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(640, 480)
	sub_vp.own_world_3d = true
	sub_vp_container.add_child(sub_vp)

	_editor_3d = CollaborativeMapEditor.new()
	sub_vp.add_child(_editor_3d)

	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(0.0, 38.0, 48.0), Vector3(0.0, 0.0, -10.0), Vector3.UP)
	_editor_3d.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-55.0, 25.0, 0.0)
	light.light_energy = 1.3
	_editor_3d.add_child(light)

	# Right Column: Object Hierarchy, Ownership Permissions & MapValidator Status
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(290, 0)
	D4FUITheme.style_panel(right_panel)
	body_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 8)
	right_panel.add_child(right_vbox)

	right_vbox.add_child(D4FUITheme.create_header_label("PLACED OBJECTS & OWNERSHIP", 16, D4FUITheme.COLOR_ACCENT_GOLD))
	_object_list = ItemList.new()
	_object_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right_vbox.add_child(_object_list)

	var del_btn := Button.new()
	del_btn.text = "Delete Selected Object"
	D4FUITheme.style_button(del_btn, D4FUITheme.COLOR_DANGER, Vector2(220, 34))
	del_btn.pressed.connect(_on_delete_selected_object)
	right_vbox.add_child(del_btn)

	var perm_check := CheckButton.new()
	perm_check.text = "Host: Allow Client Editing"
	perm_check.button_pressed = true
	perm_check.toggled.connect(func(enabled: bool):
		if _editor_3d and _editor_3d.current_map:
			_editor_3d.current_map.allow_client_editing = enabled
	)
	right_vbox.add_child(perm_check)

	right_vbox.add_child(HSeparator.new())
	right_vbox.add_child(D4FUITheme.create_header_label("MAP VALIDATION SAFEGUARDS", 16, D4FUITheme.COLOR_ACCENT_GREEN))
	_validation_label = D4FUITheme.create_body_label("", 12, D4FUITheme.COLOR_TEXT_MAIN)
	right_vbox.add_child(_validation_label)

func _init_editor_map() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var map_to_load: MapData = gm.active_map if (gm != null and gm.active_map != null) else MapData.create_default_arena()
	_editor_3d.load_map(map_to_load)
	_editor_3d.start_prep_timer(map_to_load.prep_time_limit)
	_refresh_object_list_and_validation()

func _on_place_3d_object() -> void:
	if _editor_3d == null:
		return
	var pos := Vector3(float(_pos_x_spin.value), float(_pos_y_spin.value), float(_pos_z_spin.value))
	var rot := Vector3(0.0, float(_rot_y_spin.value), 0.0)
	var scale_vec := Vector3(6.0, 1.0, 6.0)
	if _selected_obj_type == "wall":
		scale_vec = Vector3(8.0, 3.5, 1.0)
	elif _selected_obj_type == "ramp":
		scale_vec = Vector3(6.0, 2.0, 8.0)
		rot.x = 18.0
	elif _selected_obj_type == "obstacle_spinner":
		scale_vec = Vector3(7.0, 1.2, 1.2)

	var res: Dictionary = _editor_3d.place_object(_selected_obj_type, pos, rot, scale_vec, "#33aaff", 1, true)
	if bool(res.get("ok", false)):
		if has_node("/root/NetworkManager"):
			get_node("/root/NetworkManager").broadcast_secure_action("map_add_object", res.get("object", {}), "map_edit")
		_refresh_object_list_and_validation()

func _on_extrude_sample_2d_road() -> void:
	if _editor_3d == null:
		return
	var z_base := float(_pos_z_spin.value)
	var pts := [
		[-12.0, z_base + 10.0],
		[-4.0, z_base + 3.0],
		[4.0, z_base - 4.0],
		[12.0, z_base - 12.0]
	]
	_editor_3d.add_topdown_2d_stroke(pts, 5.0, 0.6, float(_pos_y_spin.value), "#2ed573", 1, true)
	_refresh_object_list_and_validation()
	get_node("/root/GameManager").notify_toast("Extruded 2D top-down stroke into 3D road geometry!", "success")

func _on_delete_selected_object() -> void:
	if _editor_3d == null or _object_list == null:
		return
	var sel := _object_list.get_selected_items()
	if sel.is_empty():
		return
	var idx := sel[0]
	if idx >= 0 and idx < _editor_3d.current_map.objects.size():
		var obj_id := String(_editor_3d.current_map.objects[idx].get("id", ""))
		_editor_3d.delete_object(obj_id, 1, true)
		_refresh_object_list_and_validation()

func _on_ai_suggest_obstacles() -> void:
	if _editor_3d == null or _editor_3d.current_map == null:
		return
	if has_node("/root/AIAssistantManager"):
		var ai := get_node("/root/AIAssistantManager")
		var res: Dictionary = ai.suggest_map_obstacles(_editor_3d.current_map)
		for prop in res.get("proposed_objects", []):
			var pos_arr: Array = prop.get("position", [0.0, 1.0, -15.0])
			var rot_arr: Array = prop.get("rotation", [0.0, 0.0, 0.0])
			var scl_arr: Array = prop.get("scale", [6.0, 1.5, 6.0])
			_editor_3d.place_object(
				String(prop.get("type", "ramp")),
				Vector3(float(pos_arr[0]), float(pos_arr[1]), float(pos_arr[2])),
				Vector3(float(rot_arr[0]), float(rot_arr[1]), float(rot_arr[2])),
				Vector3(float(scl_arr[0]), float(scl_arr[1]), float(scl_arr[2])),
				String(prop.get("color", "#ffa502")),
				1,
				true,
				prop.get("properties", {})
			)
		_refresh_object_list_and_validation()
		get_node("/root/GameManager").notify_toast("AI Architect added suggested obstacles & checkpoints!", "info")

func _refresh_object_list_and_validation() -> void:
	if _editor_3d == null or _editor_3d.current_map == null:
		return
	if _object_list != null:
		_object_list.clear()
		for obj in _editor_3d.current_map.objects:
			var pos_arr: Array = obj.get("position", [0, 0, 0])
			_object_list.add_item("%s [Owner P%d] (%d,%d,%d)" % [
				String(obj.get("type", "obj")),
				int(obj.get("owner_id", 1)),
				int(pos_arr[0]), int(pos_arr[1]), int(pos_arr[2])
			])

	var val_res: Dictionary = _editor_3d.validate_current_map()
	if _validation_label != null:
		if bool(val_res.get("valid", false)):
			_validation_label.text = "Status: VALID & FAIR ARENA\nSpawns, Reachability, Slope & Quotas Verified!"
			_validation_label.add_theme_color_override("font_color", D4FUITheme.COLOR_ACCENT_GREEN)
		else:
			var errs: Array = val_res.get("errors", [])
			_validation_label.text = "Status: INVALID MAP\n• " + "\n• ".join(errs)
			_validation_label.add_theme_color_override("font_color", D4FUITheme.COLOR_DANGER)

func _on_finalize_map() -> void:
	if _editor_3d == null:
		return
	var fin_res: Dictionary = _editor_3d.finalize_map_by_host(true)
	if bool(fin_res.get("ok", false)):
		var gm := get_node("/root/GameManager")
		gm.active_map = _editor_3d.current_map
		gm.notify_toast("Map finalized (v" + str(gm.active_map.version) + ")! Entering Competition Prep...", "success")
		gm.navigate_to(D4FConstants.GameState.COMPETITION_PREP)
	else:
		get_node("/root/GameManager").notify_toast("Map validation failed: " + String(fin_res.get("error", "")), "error")
