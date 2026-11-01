extends Control
## Screen 2: Character Workshop (`res://scenes/characters/character_workshop.tscn`)
## Stickman 2D-to-3D Drawing Workshop with live 3D extruded mesh preview,
## undo/redo, eraser, physics balance calculator, AI design suggestions, and save/load.

var _canvas: DrawingCanvas = null
var _name_input: LineEdit = null
var _depth_slider: HSlider = null
var _stats_label: Label = null
var _ai_feedback_label: Label = null
var _preview_mesh_instance: MeshInstance3D = null
var _saved_list: OptionButton = null
var _last_ai_strokes: Array = []

const PALETTE_COLORS: Array[String] = [
	"#33aaff", "#ff4757", "#2ed573", "#ffa502",
	"#ffd32a", "#a55eea", "#ffffff", "#2f3542"
]

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	_load_initial_character()

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

	var title := D4FUITheme.create_header_label("CHARACTER WORKSHOP — STICKMAN 2D-TO-3D", 24, D4FUITheme.COLOR_ACCENT_GOLD)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_bar.add_child(title)

	_name_input = LineEdit.new()
	_name_input.placeholder_text = "Character Name"
	_name_input.text = "Hero Stickman"
	_name_input.custom_minimum_size = Vector2(200, 38)
	top_bar.add_child(_name_input)

	var equip_btn := Button.new()
	equip_btn.text = "Save & Equip Character"
	D4FUITheme.style_button(equip_btn, D4FUITheme.COLOR_ACCENT_GREEN, Vector2(190, 38))
	equip_btn.pressed.connect(_on_save_and_equip)
	top_bar.add_child(equip_btn)

	# Main 3-Column Body: Left Tool Palette | Center 2D Drawing Canvas | Right 3D Preview & Physics
	var body_hbox := HBoxContainer.new()
	body_hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_hbox.add_theme_constant_override("separation", 16)
	root_vbox.add_child(body_hbox)

	# Left Column: Brush, Colors, Part Tags, Undo/Redo, Templates
	var tools_panel := PanelContainer.new()
	tools_panel.custom_minimum_size = Vector2(250, 0)
	D4FUITheme.style_panel(tools_panel)
	body_hbox.add_child(tools_panel)

	var tools_vbox := VBoxContainer.new()
	tools_vbox.add_theme_constant_override("separation", 10)
	tools_panel.add_child(tools_vbox)

	tools_vbox.add_child(D4FUITheme.create_header_label("DRAWING TOOLS", 17, D4FUITheme.COLOR_ACCENT_BLUE))

	# Color Swatches
	var swatch_grid := GridContainer.new()
	swatch_grid.columns = 4
	swatch_grid.add_theme_constant_override("h_separation", 6)
	swatch_grid.add_theme_constant_override("v_separation", 6)
	tools_vbox.add_child(swatch_grid)

	for hex in PALETTE_COLORS:
		var c_btn := Button.new()
		c_btn.custom_minimum_size = Vector2(46, 32)
		D4FUITheme.style_button(c_btn, Color(hex), Vector2(46, 32))
		c_btn.pressed.connect(func():
			if _canvas:
				_canvas.eraser_active = false
				_canvas.brush_color = Color(hex)
		)
		swatch_grid.add_child(c_btn)

	# Brush Size
	var size_lbl := D4FUITheme.create_body_label("Brush Size: 8 px", 14, D4FUITheme.COLOR_TEXT_MAIN)
	tools_vbox.add_child(size_lbl)
	var size_slider := HSlider.new()
	size_slider.min_value = 3.0
	size_slider.max_value = 24.0
	size_slider.step = 1.0
	size_slider.value = 8.0
	size_slider.value_changed.connect(func(val: float):
		size_lbl.text = "Brush Size: %d px" % int(val)
		if _canvas:
			_canvas.brush_size = val
	)
	tools_vbox.add_child(size_slider)

	# Part Tag Selector
	tools_vbox.add_child(D4FUITheme.create_body_label("Body Part Layer:", 14, D4FUITheme.COLOR_TEXT_MAIN))
	var part_opt := OptionButton.new()
	for part in ["head", "torso", "left_arm", "right_arm", "left_leg", "right_leg", "accessory"]:
		part_opt.add_item(part)
	part_opt.item_selected.connect(func(idx: int):
		if _canvas:
			_canvas.active_part_tag = part_opt.get_item_text(idx)
	)
	tools_vbox.add_child(part_opt)

	# Brush vs Eraser Toggle
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

	# Undo / Redo Row
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

	# Template & Clear Buttons
	var tpl_btn := Button.new()
	tpl_btn.text = "Reset Stickman Template"
	D4FUITheme.style_button(tpl_btn, D4FUITheme.COLOR_ACCENT_BLUE, Vector2(180, 36))
	tpl_btn.pressed.connect(func():
		var def_char := CreationData.create_default_stickman(_name_input.text, "#33aaff")
		_canvas.load_from_creation(def_char)
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

	# Saved Creations Loader
	tools_vbox.add_child(HSeparator.new())
	tools_vbox.add_child(D4FUITheme.create_body_label("Load Saved Creation:", 13, D4FUITheme.COLOR_TEXT_MUTED))
	_saved_list = OptionButton.new()
	tools_vbox.add_child(_saved_list)
	var load_btn := Button.new()
	load_btn.text = "Load Selected"
	D4FUITheme.style_button(load_btn, Color("#3d4a66"), Vector2(160, 34))
	load_btn.pressed.connect(_on_load_selected_creation)
	tools_vbox.add_child(load_btn)
	_refresh_saved_creations_dropdown()

	# Center Column: 2D Drawing Canvas
	var canvas_panel := PanelContainer.new()
	canvas_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	D4FUITheme.style_panel(canvas_panel, Color("#151928"), D4FUITheme.COLOR_ACCENT_BLUE)
	body_hbox.add_child(canvas_panel)

	var canvas_center := CenterContainer.new()
	canvas_panel.add_child(canvas_center)

	_canvas = DrawingCanvas.new()
	_canvas.template_mode = "stickman"
	_canvas.custom_minimum_size = Vector2(512, 512)
	_canvas.stroke_committed.connect(_rebuild_3d_preview)
	canvas_center.add_child(_canvas)

	# Right Column: 3D Preview, Physics Config & AI Suggestions
	var right_panel := PanelContainer.new()
	right_panel.custom_minimum_size = Vector2(310, 0)
	D4FUITheme.style_panel(right_panel)
	body_hbox.add_child(right_panel)

	var right_vbox := VBoxContainer.new()
	right_vbox.add_theme_constant_override("separation", 10)
	right_panel.add_child(right_vbox)

	right_vbox.add_child(D4FUITheme.create_header_label("3D EXTRUDED PREVIEW", 17, D4FUITheme.COLOR_ACCENT_GREEN))

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
	cam.position = Vector3(0.0, 1.1, 3.2)
	cam.look_at_from_position(Vector3(0.0, 1.1, 3.2), Vector3(0.0, 0.9, 0.0), Vector3.UP)
	preview_root.add_child(cam)

	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, 35.0, 0.0)
	light.light_energy = 1.4
	preview_root.add_child(light)

	_preview_mesh_instance = MeshInstance3D.new()
	_preview_mesh_instance.position = Vector3(0.0, 0.9, 0.0)
	preview_root.add_child(_preview_mesh_instance)

	# Extrusion Depth Slider
	var depth_lbl := D4FUITheme.create_body_label("3D Extrusion Depth: 0.35m", 13, D4FUITheme.COLOR_TEXT_MAIN)
	right_vbox.add_child(depth_lbl)
	_depth_slider = HSlider.new()
	_depth_slider.min_value = 0.15
	_depth_slider.max_value = 0.75
	_depth_slider.step = 0.05
	_depth_slider.value = 0.35
	_depth_slider.value_changed.connect(func(v: float):
		depth_lbl.text = "3D Extrusion Depth: %.2fm" % v
		_rebuild_3d_preview()
	)
	right_vbox.add_child(_depth_slider)

	right_vbox.add_child(HSeparator.new())
	right_vbox.add_child(D4FUITheme.create_header_label("PHYSICS & MESH BUDGET", 16, D4FUITheme.COLOR_ACCENT_GOLD))
	_stats_label = D4FUITheme.create_body_label("", 13, D4FUITheme.COLOR_TEXT_MAIN)
	right_vbox.add_child(_stats_label)

	right_vbox.add_child(HSeparator.new())
	var ai_btn := Button.new()
	ai_btn.text = "AI Coach: Analyze Design"
	D4FUITheme.style_button(ai_btn, D4FUITheme.COLOR_ACCENT_ORANGE, Vector2(240, 34))
	ai_btn.pressed.connect(_on_request_ai_suggestions)
	right_vbox.add_child(ai_btn)

	_ai_feedback_label = D4FUITheme.create_body_label("Click AI Coach for proportion & balance tips.", 12, D4FUITheme.COLOR_TEXT_MUTED)
	right_vbox.add_child(_ai_feedback_label)

func _load_initial_character() -> void:
	var gm := get_node_or_null("/root/GameManager")
	var initial: CreationData = gm.active_character if (gm != null and gm.active_character != null) else CreationData.create_default_stickman()
	_name_input.text = initial.creation_name
	_canvas.load_from_creation(initial)
	_rebuild_3d_preview()

func _export_current_creation() -> CreationData:
	var c := _canvas.export_to_creation(_name_input.text.strip_edges(), "LocalPlayer")
	c.creation_type = D4FConstants.CreationType.CHARACTER
	c.template_id = "stickman"
	c.extrusion_depth = float(_depth_slider.value) if _depth_slider != null else 0.35
	MeshBudgetLimiter.enforce_creation_budget(c)
	PhysicsConfigurator.compute_balanced_stats(c)
	c.compute_checksum()
	return c

func _rebuild_3d_preview() -> void:
	if _canvas == null:
		return
	var c := _export_current_creation()
	if _preview_mesh_instance != null:
		_preview_mesh_instance.mesh = MeshExtruder3D.build_extruded_mesh_from_creation(c)
	var v_est := MeshBudgetLimiter.estimate_vertex_count(c.strokes)
	var ps: Dictionary = c.physics_stats
	if _stats_label != null:
		_stats_label.text = (
			"Strokes: %d / %d | Vertices: ~%d / %d\nMass: %.1f kg | Speed: %.2fx\nAccel: %.2fx | Knockback Resist: %.2fx" % [
				c.strokes.size(), D4FConstants.MAX_STROKES_PER_CREATION,
				v_est, D4FConstants.MAX_VERTICES_PER_MESH,
				float(ps.get("mass", 70.0)),
				float(ps.get("speed_mult", 1.0)),
				float(ps.get("accel_mult", 1.0)),
				float(ps.get("knockback_resist", 1.0))
			]
		)

func _on_request_ai_suggestions() -> void:
	var c := _export_current_creation()
	if has_node("/root/AIAssistantManager"):
		var res: Dictionary = get_node("/root/AIAssistantManager").suggest_character_improvements(c)
		var lines: Array = res.get("suggestions", [])
		_ai_feedback_label.text = String(res.get("summary", "")) + "\n• " + "\n• ".join(lines)
		_last_ai_strokes = res.get("recommended_strokes", [])
		if not _last_ai_strokes.is_empty():
			for s in _last_ai_strokes:
				var pts := PackedVector2Array()
				for p in s.get("points", []):
					pts.append(Vector2(float(p[0]), float(p[1])))
				_canvas.add_programmatic_stroke(pts, Color(String(s.get("color", "#ffd32a"))), float(s.get("thickness", 8.0)), String(s.get("part_tag", "body")))
			_rebuild_3d_preview()

func _on_save_and_equip() -> void:
	var c := _export_current_creation()
	var gm := get_node_or_null("/root/GameManager")
	if gm != null:
		gm.set_active_creation(c)
		gm.save_creation_to_disk(c)
		gm.notify_toast("Character '" + c.creation_name + "' saved & equipped in 3D!", "success")
		_refresh_saved_creations_dropdown()

func _refresh_saved_creations_dropdown() -> void:
	if _saved_list == null or not has_node("/root/GameManager"):
		return
	_saved_list.clear()
	var files: Array[String] = get_node("/root/GameManager").list_saved_creations()
	for f in files:
		_saved_list.add_item(f)

func _on_load_selected_creation() -> void:
	if _saved_list == null or _saved_list.item_count == 0:
		return
	var fname := _saved_list.get_item_text(_saved_list.selected)
	var loaded: CreationData = get_node("/root/GameManager").load_creation_from_disk(fname)
	if loaded != null:
		_name_input.text = loaded.creation_name
		_canvas.load_from_creation(loaded)
		_rebuild_3d_preview()
		get_node("/root/GameManager").notify_toast("Loaded '" + loaded.creation_name + "'", "info")
