extends Control
## Screen 3: Vehicle Workshop (`res://scenes/vehicles/vehicle_workshop.tscn`)
## Custom Vehicle 2D-to-3D Drawing Workshop with wheeled template guide,
## live 3D extrusion preview, grip/torque physics configuration, and AI suggestions.

var _canvas: DrawingCanvas = null
var _name_input: LineEdit = null
var _depth_slider: HSlider = null
var _stats_label: Label = null
var _ai_feedback_label: Label = null
var _preview_mesh_instance: MeshInstance3D = null

const PALETTE_COLORS: Array[String] = [
	"#ff6622", "#1e90ff", "#2ed573", "#ffd32a",
	"#ff4757", "#a55eea", "#f1f2f6", "#2f3542"
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_initial_vehicle()

func _process(delta: float) -> void:
	if _preview_mesh_instance != null:
		_preview_mesh_instance.rotate_y(delta * 0.85)

func _build_ui() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 28)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var root_vbox := VBoxContainer.new()
	root_vbox.add_theme_constant_override("separation", 12)
	margin.add_child(root_vbox)

	# Top Bar
	var top_bar := HBoxContainer.new()
	top_bar.add_theme_constant_override("separation", 14)
	root_vbox.add_child(top_bar)

	var back_btn := Button.new()
	back_btn.text = "← Main Menu"
	D4FUITheme.style_button(back_btn, Color("#3d4a66"), Vector2(135, 38))
	back_btn.pressed.connect(func():
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.MAIN_MENU)
	)
	top_bar.add_child(back_btn)

	var title := D4FUITheme.create_header_label("VEHICLE WORKSHOP — CUSTOM RACER 2D-TO-3D", 24, D4FUITheme.COLOR_ACCENT_ORANGE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Vehicle Name"
	_name_input.text = "Turbo Sketch"
	_name_input.custom_minimum_size = Vector2(200, 38)
	top_bar.add_child(_name_input)

	var equip_btn := Button.new()
	equip_btn.text = "Save & Equip Vehicle"
	D4FUITheme.style_button(equip_btn, D4FUITheme.COLOR_ACCENT_GREEN, Vector2(190, 38))
	equip_btn.pressed.connect(_on_save_and_equip)
	top_bar.add_child(equip_btn)

	# Main 3-Column Body
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(body_hbox)

	# Left Tools Panel
	var tools_panel := PanelContainer.new()
	tools_panel.custom_minimum_size = Vector2(250, 0)
	D4FUITheme.style_panel(tools_panel)
	body_hbox.add_child(tools_panel)

	var tools_vbox := VBoxContainer.new()
	tools_vbox.add_theme_constant_override("separation", 10)
	tools_panel.add_child(tools_vbox)

	tools_vbox.add_child(D4FUITheme.create_header_label("CHASSIS & WHEEL TOOLS", 17, D4FUITheme.COLOR_ACCENT_ORANGE))

	var swatch_grid := GridContainer.new()
	swatch_grid.columns = 4
	swatch_grid.add_theme_constant_override("h_separation", 6)
	swatch_grid.add_theme_constant_override("v_separation", 6)
	tools_vbox.add_child(swatch_grid)

	for hex in PALETTE_COLORS:
		var c_btn := Button.new()
		D4FUITheme.style_button(c_btn, Color(hex), Vector2(46, 32))
		c_btn.pressed.connect(func():
			if _canvas:
				_canvas.eraser_active = false
				_canvas.brush_color = Color(hex)
		)
		swatch_grid.add_child(c_btn)

	var size_lbl := D4FUITheme.create_body_label("Brush Size: 10 px", 14, D4FUITheme.COLOR_TEXT_MAIN)
	tools_vbox.add_child(size_lbl)
	var size_slider := HSlider.new()
	size_slider.min_value = 3.0
	size_slider.max_value = 26.0
	size_slider.step = 1.0
	size_slider.value = 10.0
	size_slider.value_changed.connect(func(val: float):
		size_lbl.text = "Brush Size: %d px" % int(val)
		if _canvas:
			_canvas.brush_size = val
	)
	tools_vbox.add_child(size_slider)

	tools_vbox.add_child(D4FUITheme.create_body_label("Vehicle Component Layer:", 14, D4FUITheme.COLOR_TEXT_MAIN))
	var part_opt := OptionButton.new()
	for part in ["chassis", "cabin", "front_wheel", "rear_wheel", "spoiler", "bumper"]:
		part_opt.add_item(part)
	part_opt.item_selected.connect(func(idx: int):
		if _canvas:
			_canvas.active_part_tag = part_opt.get_item_text(idx)
	)
	tools_vbox.add_child(part_opt)

	var mode_row := HBoxContainer.new()
	mode_row.add_theme_constant_override("separation", 6)
	tools_vbox.add_child(mode_row)

	var draw_btn := Button.new()
	draw_btn.text = "Brush"
	draw_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(draw_btn, D4FUITheme.COLOR_ACCENT_BLUE, Vector2(90, 36))
	draw_btn.pressed.connect(func():
		if _canvas:
			_canvas.eraser_active = false
	)
	mode_row.add_child(draw_btn)

	var erase_btn := Button.new()
	erase_btn.text = "Eraser"
	erase_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(erase_btn, D4FUITheme.COLOR_ACCENT_ORANGE, Vector2(90, 36))
	erase_btn.pressed.connect(func():
		if _canvas:
			_canvas.eraser_active = true
	)
	mode_row.add_child(erase_btn)

	var hist_row := HBoxContainer.new()
	hist_row.add_theme_constant_override("separation", 6)
	tools_vbox.add_child(hist_row)

	var undo_btn := Button.new()
	undo_btn.text = "Undo"
	undo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(undo_btn, Color("#3d4a66"), Vector2(90, 36))
	undo_btn.pressed.connect(func():
		if _canvas:
			_canvas.undo()
			_rebuild_3d_preview()
	)
	hist_row.add_child(undo_btn)

	var redo_btn := Button.new()
	redo_btn.text = "Redo"
	redo_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_button(redo_btn, Color("#3d4a66"), Vector2(90, 36))
	redo_btn.pressed.connect(func():
		if _canvas:
			_canvas.redo()
			_rebuild_3d_preview()
	)
	hist_row.add_child(redo_btn)

	var tpl_btn := Button.new()
	tpl_btn.text = "Reset Vehicle Template"
	D4FUITheme.style_button(tpl_btn, D4FUITheme.COLOR_ACCENT_BLUE, Vector2(180, 36))
	tpl_btn.pressed.connect(func():
		var def_veh := CreationData.create_default_vehicle(_name_input.text, "#ff6622")
		_canvas.load_from_creation(def_veh)
		_rebuild_3d_preview()
	)
	tools_vbox.add_child(tpl_btn)

	var clear_btn := Button.new()
	clear_btn.text = "Clear Canvas"
	D4FUITheme.style_button(clear_btn, D4FUITheme.COLOR_DANGER, Vector2(180, 36))
	clear_btn.pressed.connect(func():
		if _canvas:
			_canvas.clear_canvas()
			_rebuild_3d_preview()
	)
	tools_vbox.add_child(clear_btn)

	# Center 2D Canvas
	var canvas_panel := PanelContainer.new()
	canvas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_panel(canvas_panel, Color("#151928"), D4FUITheme.COLOR_ACCENT_ORANGE)
	body_hbox.add_child(canvas_panel)

	var canvas_center := CenterContainer.new()
	canvas_panel.add_child(canvas_center)

	_canvas = DrawingCanvas.new()
	_canvas.template_mode = "wheeled_vehicle"
	_canvas.active_part_tag = "chassis"
	_canvas.brush_color = Color("#ff6622")
	_canvas.brush_size = 10.0
	_canvas.custom_minimum_size = Vector2(512, 512)
	_canvas.stroke_committed.connect(_rebuild_3d_preview)
	canvas_center.add_child(_canvas)

	# Right 3D Preview & Vehicle Physics
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(310, 0)
	D4FUITheme.style_panel(right_panel)
	body_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_vbox)

	right_vbox.add_child(D4FUITheme.create_header_label("3D VEHICLE PREVIEW", 17, D4FUITheme.COLOR_ACCENT_GREEN))

	var sub_vp_container := SubViewportContainer.new()
	sub_vp_container.custom_minimum_size = Vector2(280, 210)
	sub_vp_container.stretch = true
	right_vbox.add_child(sub_vp_container)

	var sub_vp := SubViewport.new()
	sub_vp.size = Vector2i(280, 210)
	sub_vp.own_world_3d = true
	sub_vp_container.add_child(sub_vp)

	var preview_root := Node3D.new()
	sub_vp.add_child(preview_root)

	var cam := Camera3D.new()
	cam.look_at_from_position(Vector3(0.0, 1.1, 3.4), Vector3(0.0, 0.8, 0.0), Vector3.UP)
	preview_root.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	light.light_energy = 1.4
	preview_root.add_child(light)

	_preview_mesh_instance = MeshInstance3D.new()
	_preview_mesh_instance.position = Vector3(0.0, 0.8, 0.0)
	preview_root.add_child(_preview_mesh_instance)

	var depth_lbl := D4FUITheme.create_body_label("Chassis Width (Extrusion): 0.55m", 13, D4FUITheme.COLOR_TEXT_MAIN)
	right_vbox.add_child(depth_lbl)
	_depth_slider = HSlider.new()
	_depth_slider.min_value = 0.25
	_depth_slider.max_value = 0.95
	_depth_slider.step = 0.05
	_depth_slider.value = 0.55
	_depth_slider.value_changed.connect(func(v: float):
		depth_lbl.text = "Chassis Width (Extrusion): %.2fm" % v
		_rebuild_3d_preview()
	)
	right_vbox.add_child(_depth_slider)

	right_vbox.add_child(HSeparator.new())
	right_vbox.add_child(D4FUITheme.create_header_label("DRIVETRAIN & TELEMETRY", 16, D4FUITheme.COLOR_ACCENT_GOLD))
	_stats_label = D4FUITheme.create_body_label("", 13, D4FUITheme.COLOR_TEXT_MAIN)
	right_vbox.add_child(_stats_label)

	right_vbox.add_child(HSeparator.new())
	var ai_btn := Button.new()
	ai_btn.text = "AI Engineer: Check Wheelbase"
	D4FUITheme.style_button(ai_btn, D4FUITheme.COLOR_ACCENT_ORANGE, Vector2(240, 34))
	ai_btn.pressed.connect(_on_request_ai_suggestions)
	right_vbox.add_child(ai_btn)

	_ai_feedback_label = D4FUITheme.create_body_label("Click AI Engineer to analyze ramp stability.", 12, D4FUITheme.COLOR_TEXT_MUTED)
	right_vbox.add_child(_ai_feedback_label)

func _load_initial_vehicle() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var initial: CreationData = gm.active_vehicle if (gm != null and gm.active_vehicle != null) else CreationData.create_default_vehicle()
	_name_input.text = initial.creation_name
	_canvas.load_from_creation(initial)
	_rebuild_3d_preview()

func _export_current_vehicle() -> CreationData:
	var c := _canvas.export_to_creation(_name_input.text.strip_edges(), "LocalPlayer")
	c.creation_type = D4FConstants.CreationType.VEHICLE
	c.template_id = "wheeled_vehicle"
	c.extrusion_depth = float(_depth_slider.value) if _depth_slider != null else 0.55
	MeshBudgetLimiter.enforce_creation_budget(c)
	PhysicsConfigurator.compute_balanced_stats(c)
	c.compute_checksum()
	return c

func _rebuild_3d_preview() -> void:
	if _canvas == null:
		return
	var c := _export_current_vehicle()
	if _preview_mesh_instance != null:
		_preview_mesh_instance.mesh = MeshExtruder3D.build_extruded_mesh_from_creation(c)
	var v_est := MeshBudgetLimiter.estimate_vertex_count(c.strokes)
	var ps: Dictionary = c.physics_stats
	if _stats_label != null:
		_stats_label.text = (
			"Strokes: %d / %d | Vertices: ~%d / %d\nMass: %.1f kg | Top Speed: %.2fx\nTorque/Accel: %.2fx | Tire Grip: %.2fx" % [
				c.strokes.size(), D4FConstants.MAX_STROKES_PER_CREATION,
				v_est, D4FConstants.MAX_VERTICES_PER_MESH,
				float(ps.get("mass", 85.0)),
				float(ps.get("speed_mult", 1.0)),
				float(ps.get("accel_mult", 1.0)),
				float(ps.get("grip", 1.0))
			]
		)

func _on_request_ai_suggestions() -> void:
	var c := _export_current_vehicle()
	if has_node("/root/AIAssistantManager"):
		var res: Dictionary = get_node("/root/AIAssistantManager").suggest_vehicle_improvements(c)
		var lines: Array = res.get("suggestions", [])
		_ai_feedback_label.text = String(res.get("summary", "")) + "\n• " + "\n• ".join(lines)

func _on_save_and_equip() -> void:
	var c := _export_current_vehicle()
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set_active_creation(c)
		gm.save_creation_to_disk(c)
		gm.notify_toast("Vehicle '" + c.creation_name + "' saved & equipped!", "success")
