class_name DrawingCanvas
extends Control
## Interactive 2D drawing widget used in both Character Workshop and Vehicle Workshop.
## Supports freehand strokes, part tags, undo/redo stacks, eraser, template silhouettes,
## and live physics/vertex budget estimation.

signal strokes_changed(stroke_count: int, vertex_estimate: int, physics_stats: Dictionary)
signal stroke_committed()

const LOGICAL_SIZE := Vector2(512.0, 512.0)
const MIN_POINT_SPACING := 5.5
const MAX_UNDO_STEPS := 40

var template_mode: String = "stickman":
	set(value):
		template_mode = value
		queue_redraw()

var brush_color: Color = Color("#33aaff")
var brush_size: float = 8.0
var active_part_tag: String = "body"
var eraser_active: bool = false
var show_template_guide: bool = true:
	set(value):
		show_template_guide = value
		queue_redraw()

var extrusion_depth: float = 0.22
var strokes: Array = []

var _undo_stack: Array = []
var _redo_stack: Array = []
var _active_stroke_points: PackedVector2Array = PackedVector2Array()
var _is_drawing: bool = false
var _is_erasing: bool = false
var _hover_pos: Vector2 = Vector2(-100.0, -100.0)


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if custom_minimum_size == Vector2.ZERO:
		custom_minimum_size = Vector2(384.0, 384.0)
	_emit_stats_changed()


func _to_logical(local_pos: Vector2) -> Vector2:
	var rect_sz := size.max(Vector2(1.0, 1.0))
	return Vector2(
		clampf(local_pos.x / rect_sz.x * LOGICAL_SIZE.x, 8.0, LOGICAL_SIZE.x - 8.0),
		clampf(local_pos.y / rect_sz.y * LOGICAL_SIZE.y, 8.0, LOGICAL_SIZE.y - 8.0)
	)


func _to_local_canvas(logical_pos: Vector2) -> Vector2:
	var rect_sz := size.max(Vector2(1.0, 1.0))
	return Vector2(
		logical_pos.x / LOGICAL_SIZE.x * rect_sz.x,
		logical_pos.y / LOGICAL_SIZE.y * rect_sz.y
	)


func _scale_factor() -> float:
	var rect_sz := size.max(Vector2(1.0, 1.0))
	return minf(rect_sz.x / LOGICAL_SIZE.x, rect_sz.y / LOGICAL_SIZE.y)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				var logical_pt := _to_logical(mb.position)
				if eraser_active:
					_push_undo_snapshot()
					_is_erasing = true
					erase_at_point(logical_pt, maxf(brush_size * 1.8, 16.0))
				else:
					_start_stroke(logical_pt)
				accept_event()
			else:
				if _is_drawing:
					_finish_stroke()
				elif _is_erasing:
					_is_erasing = false
					stroke_committed.emit()
				accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			var logical_pt := _to_logical(mb.position)
			_push_undo_snapshot()
			erase_at_point(logical_pt, maxf(brush_size * 1.8, 18.0))
			stroke_committed.emit()
			accept_event()

	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_hover_pos = mm.position
		var logical_pt := _to_logical(mm.position)
		if _is_drawing:
			_append_stroke_point(logical_pt)
			accept_event()
		elif _is_erasing:
			erase_at_point(logical_pt, maxf(brush_size * 1.8, 16.0))
			accept_event()
		queue_redraw()


func _start_stroke(logical_pt: Vector2) -> void:
	if MeshExtruder3D.estimate_vertex_count(strokes) >= D4FConstants.MAX_VERTICES_PER_MESH:
		return
	_push_undo_snapshot()
	_is_drawing = true
	_active_stroke_points = PackedVector2Array([logical_pt])
	queue_redraw()


func _append_stroke_point(logical_pt: Vector2) -> void:
	if _active_stroke_points.is_empty():
		_active_stroke_points.append(logical_pt)
		queue_redraw()
		return
	var last_pt := _active_stroke_points[_active_stroke_points.size() - 1]
	if last_pt.distance_to(logical_pt) >= MIN_POINT_SPACING:
		var current_verts := MeshExtruder3D.estimate_vertex_count(strokes) + (_active_stroke_points.size() * 24)
		if current_verts < D4FConstants.MAX_VERTICES_PER_MESH:
			_active_stroke_points.append(logical_pt)
			queue_redraw()


func _finish_stroke() -> void:
	_is_drawing = false
	if _active_stroke_points.is_empty():
		return
	var serialized_pts: Array = []
	for pt in _active_stroke_points:
		serialized_pts.append([snappedf(pt.x, 0.5), snappedf(pt.y, 0.5)])
	if serialized_pts.size() == 1:
		var p0: Array = serialized_pts[0]
		serialized_pts.append([float(p0[0]) + 1.0, float(p0[1])])

	strokes.append({
		"points": serialized_pts,
		"color": "#" + brush_color.to_html(false),
		"thickness": clampf(brush_size, 2.0, 48.0),
		"part_tag": active_part_tag
	})
	_active_stroke_points = PackedVector2Array()
	_emit_stats_changed()
	stroke_committed.emit()
	queue_redraw()


func _push_undo_snapshot() -> void:
	_undo_stack.append(strokes.duplicate(true))
	if _undo_stack.size() > MAX_UNDO_STEPS:
		_undo_stack.pop_front()
	_redo_stack.clear()


func undo() -> bool:
	if _undo_stack.is_empty():
		return false
	_redo_stack.append(strokes.duplicate(true))
	strokes = _undo_stack.pop_back()
	_emit_stats_changed()
	stroke_committed.emit()
	queue_redraw()
	return true


func redo() -> bool:
	if _redo_stack.is_empty():
		return false
	_undo_stack.append(strokes.duplicate(true))
	strokes = _redo_stack.pop_back()
	_emit_stats_changed()
	stroke_committed.emit()
	queue_redraw()
	return true


func clear_canvas() -> void:
	if not strokes.is_empty():
		_push_undo_snapshot()
	strokes.clear()
	_active_stroke_points = PackedVector2Array()
	_emit_stats_changed()
	stroke_committed.emit()
	queue_redraw()


func add_programmatic_stroke(points: PackedVector2Array, color: Color, thickness: float, part_tag: String = "body") -> void:
	if points.is_empty():
		return
	_push_undo_snapshot()
	var serialized_pts: Array = []
	for pt in points:
		serialized_pts.append([snappedf(pt.x, 0.5), snappedf(pt.y, 0.5)])
	strokes.append({
		"points": serialized_pts,
		"color": "#" + color.to_html(false),
		"thickness": clampf(thickness, 2.0, 48.0),
		"part_tag": part_tag
	})
	_emit_stats_changed()
	stroke_committed.emit()
	queue_redraw()


func erase_at_point(pos: Vector2, radius: float = 16.0) -> int:
	var removed_count := 0
	var r_sq := radius * radius
	var remaining_strokes: Array = []

	for stroke in strokes:
		if not (stroke is Dictionary):
			continue
		var pts: Array = stroke.get("points", [])
		var hit := false
		for raw_pt in pts:
			var p := MeshExtruder3D._to_vec2(raw_pt)
			if p.distance_squared_to(pos) <= r_sq:
				hit = true
				break
		if hit:
			removed_count += 1
		else:
			remaining_strokes.append(stroke)

	if removed_count > 0:
		strokes = remaining_strokes
		_emit_stats_changed()
		queue_redraw()

	return removed_count


func load_from_creation(creation: CreationData) -> void:
	_undo_stack.clear()
	_redo_stack.clear()
	if creation == null:
		strokes.clear()
	else:
		strokes = creation.strokes.duplicate(true)
		extrusion_depth = creation.extrusion_depth
		if creation.creation_type == D4FConstants.CreationType.VEHICLE or creation.template_id == "wheeled_vehicle":
			template_mode = "wheeled_vehicle"
		else:
			template_mode = "stickman"
	_emit_stats_changed()
	queue_redraw()


func export_to_creation(creation_name: String, author_name: String = "Player") -> CreationData:
	var creation := CreationData.new()
	creation.creation_name = creation_name.strip_edges() if not creation_name.strip_edges().is_empty() else "Custom Creation"
	creation.author_name = author_name
	creation.creation_type = (
		D4FConstants.CreationType.VEHICLE
		if template_mode == "wheeled_vehicle"
		else D4FConstants.CreationType.CHARACTER
	)
	creation.template_id = template_mode
	creation.extrusion_depth = extrusion_depth
	creation.strokes = strokes.duplicate(true)
	if creation.strokes.is_empty():
		if creation.creation_type == D4FConstants.CreationType.VEHICLE:
			creation = CreationData.create_default_vehicle()
		else:
			creation = CreationData.create_default_stickman()
		creation.creation_name = creation_name if not creation_name.is_empty() else creation.creation_name
	PhysicsConfigurator.compute_balanced_stats(creation)
	return creation


func _emit_stats_changed() -> void:
	var temp := CreationData.new()
	temp.strokes = strokes
	temp.extrusion_depth = extrusion_depth
	temp.creation_type = (
		D4FConstants.CreationType.VEHICLE
		if template_mode == "wheeled_vehicle"
		else D4FConstants.CreationType.CHARACTER
	)
	var stats := PhysicsConfigurator.compute_balanced_stats(temp)
	var vert_est := int(stats.get("vertex_estimate", 0))
	strokes_changed.emit(strokes.size(), vert_est, stats)


func _draw() -> void:
	# Background fill & grid
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.09, 0.11, 0.15, 1.0), true)
	var grid_col := Color(0.18, 0.22, 0.29, 0.55)
	var step := 64.0
	var y := step
	while y < LOGICAL_SIZE.y:
		var p0 := _to_local_canvas(Vector2(0.0, y))
		var p1 := _to_local_canvas(Vector2(LOGICAL_SIZE.x, y))
		draw_line(p0, p1, grid_col, 1.0)
		y += step
	var x := step
	while x < LOGICAL_SIZE.x:
		var p0 := _to_local_canvas(Vector2(x, 0.0))
		var p1 := _to_local_canvas(Vector2(x, LOGICAL_SIZE.y))
		draw_line(p0, p1, grid_col, 1.0)
		x += step

	# Center axes
	var center_local := _to_local_canvas(Vector2(256.0, 256.0))
	draw_line(Vector2(center_local.x, 0.0), Vector2(center_local.x, size.y), Color(0.28, 0.35, 0.45, 0.6), 1.5)
	draw_line(Vector2(0.0, center_local.y), Vector2(size.x, center_local.y), Color(0.28, 0.35, 0.45, 0.6), 1.5)

	if show_template_guide:
		_draw_template_silhouette()

	var sf := _scale_factor()

	# Committed strokes
	for stroke in strokes:
		if not (stroke is Dictionary):
			continue
		var raw_pts: Array = stroke.get("points", [])
		if raw_pts.is_empty():
			continue
		var col := Color.from_string(str(stroke.get("color", "#33aaff")), Color.DODGER_BLUE)
		var thick := maxf(2.0, float(stroke.get("thickness", 8.0)) * sf)
		if raw_pts.size() == 1:
			var p := _to_local_canvas(MeshExtruder3D._to_vec2(raw_pts[0]))
			draw_circle(p, thick * 0.5, col)
		else:
			var poly := PackedVector2Array()
			for pt in raw_pts:
				poly.append(_to_local_canvas(MeshExtruder3D._to_vec2(pt)))
			draw_polyline(poly, col, thick, true)
			draw_circle(poly[0], thick * 0.5, col)
			draw_circle(poly[poly.size() - 1], thick * 0.5, col)

	# Active stroke in progress
	if _is_drawing and not _active_stroke_points.is_empty():
		var thick := maxf(2.0, brush_size * sf)
		if _active_stroke_points.size() == 1:
			draw_circle(_to_local_canvas(_active_stroke_points[0]), thick * 0.5, brush_color)
		else:
			var poly := PackedVector2Array()
			for pt in _active_stroke_points:
				poly.append(_to_local_canvas(pt))
			draw_polyline(poly, brush_color, thick, true)

	# Brush cursor preview
	if Rect2(Vector2.ZERO, size).has_point(_hover_pos):
		var cursor_r := (maxf(brush_size * 1.8, 16.0) if eraser_active else brush_size * 0.5) * sf
		var cursor_col := Color(1.0, 0.35, 0.35, 0.8) if eraser_active else Color(brush_color.r, brush_color.g, brush_color.b, 0.7)
		draw_arc(_hover_pos, maxf(3.0, cursor_r), 0.0, TAU, 24, cursor_col, 1.5)


func _draw_template_silhouette() -> void:
	var guide_col := Color(0.45, 0.75, 1.0, 0.18)
	var sf := _scale_factor()
	if template_mode == "wheeled_vehicle":
		# Vehicle chassis & wheel guide zones
		var chassis_rect := Rect2(_to_local_canvas(Vector2(110.0, 210.0)), Vector2(292.0 * sf, 110.0 * sf))
		draw_rect(chassis_rect, guide_col, false, 2.0)
		var cabin_pts := PackedVector2Array([
			_to_local_canvas(Vector2(165.0, 210.0)),
			_to_local_canvas(Vector2(210.0, 145.0)),
			_to_local_canvas(Vector2(315.0, 145.0)),
			_to_local_canvas(Vector2(355.0, 210.0))
		])
		draw_polyline(cabin_pts, guide_col, 2.0)
		draw_arc(_to_local_canvas(Vector2(170.0, 340.0)), 42.0 * sf, 0.0, TAU, 28, guide_col, 2.5)
		draw_arc(_to_local_canvas(Vector2(342.0, 340.0)), 42.0 * sf, 0.0, TAU, 28, guide_col, 2.5)
	else:
		# Stickman character guide
		draw_arc(_to_local_canvas(Vector2(256.0, 115.0)), 38.0 * sf, 0.0, TAU, 28, guide_col, 2.5)
		draw_line(_to_local_canvas(Vector2(256.0, 153.0)), _to_local_canvas(Vector2(256.0, 310.0)), guide_col, 3.0)
		draw_line(_to_local_canvas(Vector2(170.0, 210.0)), _to_local_canvas(Vector2(342.0, 210.0)), guide_col, 2.5)
		draw_line(_to_local_canvas(Vector2(256.0, 310.0)), _to_local_canvas(Vector2(195.0, 435.0)), guide_col, 2.5)
		draw_line(_to_local_canvas(Vector2(256.0, 310.0)), _to_local_canvas(Vector2(317.0, 435.0)), guide_col, 2.5)
