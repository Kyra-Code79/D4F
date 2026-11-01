class_name CollaborativeMapEditor
extends Node3D
## Manages the live 3D arena editor & top-down 2D terrain sketch extrusion.
## Supports real-time collaborative object placement, ownership rules, top-down
## road/platform extrusion, timed preparation phase, and host finalization with
## automatic repair for missing spawns or finish lines.

signal map_modified(version: int)
signal validation_updated(result: Dictionary)
signal prep_timer_tick(seconds_left: float)
signal map_finalized(map_data: MapData)

var current_map: MapData
var prep_time_remaining: float = 90.0
var is_timer_running: bool = false

var _objects_root: Node3D
var _terrain_root: Node3D
var _spawned_object_nodes: Dictionary = {}
var _spawned_terrain_nodes: Dictionary = {}
var _tick_accumulator: float = 0.0


func _ready() -> void:
	_ensure_containers()
	if current_map == null:
		current_map = MapData.create_default_race_map()
		load_map(current_map)


func _ensure_containers() -> void:
	if _objects_root == null:
		_objects_root = Node3D.new()
		_objects_root.name = "EditorObjectsRoot"
		add_child(_objects_root)
	if _terrain_root == null:
		_terrain_root = Node3D.new()
		_terrain_root.name = "EditorTerrainRoot"
		add_child(_terrain_root)


func _process(delta: float) -> void:
	if not is_timer_running or current_map == null or current_map.is_finalized:
		return

	prep_time_remaining = maxf(0.0, prep_time_remaining - delta)
	_tick_accumulator += delta
	if _tick_accumulator >= 0.25 or prep_time_remaining <= 0.0:
		_tick_accumulator = 0.0
		prep_timer_tick.emit(prep_time_remaining)

	if prep_time_remaining <= 0.0:
		is_timer_running = false
		finalize_map_by_host(true)


func start_prep_timer(duration: float = 90.0) -> void:
	prep_time_remaining = maxf(5.0, duration)
	_tick_accumulator = 0.0
	is_timer_running = true
	prep_timer_tick.emit(prep_time_remaining)


func load_map(map_data: MapData) -> void:
	_ensure_containers()
	current_map = map_data if map_data != null else MapData.create_default_race_map()
	prep_time_remaining = current_map.prep_time_limit if current_map.prep_time_limit > 0.0 else 90.0

	for child in _objects_root.get_children():
		child.queue_free()
	for child in _terrain_root.get_children():
		child.queue_free()
	_spawned_object_nodes.clear()
	_spawned_terrain_nodes.clear()

	for obj_dict in current_map.objects:
		if obj_dict is Dictionary:
			_instantiate_object_node(obj_dict)

	for stroke_dict in current_map.terrain_strokes:
		if stroke_dict is Dictionary:
			_instantiate_terrain_stroke_node(stroke_dict)

	validate_current_map()


func place_object(
	type: String,
	pos: Vector3,
	rot: Vector3,
	scale_vec: Vector3,
	color_hex: String,
	peer_id: int,
	is_host: bool,
	properties: Dictionary = {}
) -> Dictionary:
	if current_map == null:
		current_map = MapData.new()
	if current_map.is_finalized and not is_host:
		return {"ok": false, "error": "Map is already finalized."}
	if current_map.objects.size() >= MapValidator.MAX_OBJECT_QUOTA:
		return {"ok": false, "error": "Arena object quota (%d) reached." % MapValidator.MAX_OBJECT_QUOTA}

	var obj_id := "obj_%d_%d" % [peer_id, Time.get_ticks_usec()]
	var clamped_scale := Vector3(
		clampf(scale_vec.x, 0.25, 45.0),
		clampf(scale_vec.y, 0.20, 25.0),
		clampf(scale_vec.z, 0.25, 45.0)
	)
	var obj_dict := {
		"id": obj_id,
		"type": type,
		"owner_id": peer_id,
		"position": [snappedf(pos.x, 0.05), snappedf(pos.y, 0.05), snappedf(pos.z, 0.05)],
		"rotation": [snappedf(rot.x, 0.1), snappedf(rot.y, 0.1), snappedf(rot.z, 0.1)],
		"scale": [snappedf(clamped_scale.x, 0.05), snappedf(clamped_scale.y, 0.05), snappedf(clamped_scale.z, 0.05)],
		"color": color_hex if not color_hex.is_empty() else "#44aaff",
		"properties": properties.duplicate(true)
	}

	current_map.objects.append(obj_dict)
	current_map.version += 1
	_instantiate_object_node(obj_dict)

	map_modified.emit(current_map.version)
	var val := validate_current_map()
	return {"ok": true, "object": obj_dict, "validation": val}


func move_or_edit_object(obj_id: String, updates: Dictionary, peer_id: int, is_host: bool) -> Dictionary:
	if current_map == null:
		return {"ok": false, "error": "No map loaded."}
	if current_map.is_finalized and not is_host:
		return {"ok": false, "error": "Map is finalized."}

	for i in range(current_map.objects.size()):
		var obj: Dictionary = current_map.objects[i]
		if str(obj.get("id", "")) == obj_id:
			var owner_id := int(obj.get("owner_id", 1))
			if owner_id != peer_id and not is_host:
				return {"ok": false, "error": "Only the object creator or Host can modify this object."}

			if updates.has("position"):
				var p := MapValidator._vec3_from_var(updates["position"])
				obj["position"] = [snappedf(p.x, 0.05), snappedf(p.y, 0.05), snappedf(p.z, 0.05)]
			if updates.has("rotation"):
				var r := MapValidator._vec3_from_var(updates["rotation"])
				obj["rotation"] = [snappedf(r.x, 0.1), snappedf(r.y, 0.1), snappedf(r.z, 0.1)]
			if updates.has("scale"):
				var s := MapValidator._vec3_from_var(updates["scale"], Vector3.ONE)
				obj["scale"] = [
					clampf(s.x, 0.25, 45.0),
					clampf(s.y, 0.20, 25.0),
					clampf(s.z, 0.25, 45.0)
				]
			if updates.has("color"):
				obj["color"] = str(updates["color"])
			if updates.has("properties") and updates["properties"] is Dictionary:
				var props: Dictionary = obj.get("properties", {})
				props.merge(updates["properties"], true)
				obj["properties"] = props

			current_map.objects[i] = obj
			current_map.version += 1
			_refresh_object_node(obj)
			map_modified.emit(current_map.version)
			var val := validate_current_map()
			return {"ok": true, "object": obj, "validation": val}

	return {"ok": false, "error": "Object ID '%s' not found." % obj_id}


func delete_object(obj_id: String, peer_id: int, is_host: bool) -> Dictionary:
	if current_map == null:
		return {"ok": false, "error": "No map loaded."}
	if current_map.is_finalized and not is_host:
		return {"ok": false, "error": "Map is finalized."}

	for i in range(current_map.objects.size()):
		var obj: Dictionary = current_map.objects[i]
		if str(obj.get("id", "")) == obj_id:
			var owner_id := int(obj.get("owner_id", 1))
			if owner_id != peer_id and not is_host:
				return {"ok": false, "error": "Only the object creator or Host can delete this object."}

			current_map.objects.remove_at(i)
			current_map.version += 1
			if _spawned_object_nodes.has(obj_id):
				var node: Node = _spawned_object_nodes[obj_id]
				if is_instance_valid(node):
					node.queue_free()
				_spawned_object_nodes.erase(obj_id)

			map_modified.emit(current_map.version)
			var val := validate_current_map()
			return {"ok": true, "deleted_id": obj_id, "validation": val}

	return {"ok": false, "error": "Object ID '%s' not found." % obj_id}


func add_topdown_2d_stroke(
	points_xz: Array,
	width: float,
	height: float,
	y_offset: float,
	color_hex: String,
	peer_id: int,
	is_host: bool
) -> Dictionary:
	if current_map == null:
		current_map = MapData.new()
	if current_map.is_finalized and not is_host:
		return {"ok": false, "error": "Map is finalized."}
	if points_xz.is_empty():
		return {"ok": false, "error": "Stroke points are empty."}

	var serialized_pts: Array = []
	for pt in points_xz:
		var v2 := MeshExtruder3D._to_vec2(pt)
		serialized_pts.append([snappedf(v2.x, 0.1), snappedf(v2.y, 0.1)])

	var stroke_id := "stroke_%d_%d" % [peer_id, Time.get_ticks_usec()]
	var stroke_dict := {
		"id": stroke_id,
		"owner_id": peer_id,
		"points": serialized_pts,
		"width": clampf(width, 1.5, 18.0),
		"height": clampf(height, 0.25, 6.0),
		"y_offset": clampf(y_offset, -10.0, 35.0),
		"color": color_hex if not color_hex.is_empty() else "#557799"
	}

	current_map.terrain_strokes.append(stroke_dict)
	current_map.version += 1
	_instantiate_terrain_stroke_node(stroke_dict)

	map_modified.emit(current_map.version)
	var val := validate_current_map()
	return {"ok": true, "stroke": stroke_dict, "validation": val}


func validate_current_map() -> Dictionary:
	var mode := current_map.target_mode if current_map != null else 0
	var result := MapValidator.validate_map(current_map, mode)
	validation_updated.emit(result)
	return result


func finalize_map_by_host(is_host: bool) -> Dictionary:
	if not is_host:
		return {"ok": false, "error": "Only the Host can finalize the map."}
	if current_map == null:
		current_map = MapData.create_default_race_map()

	var check := validate_current_map()
	if not bool(check.get("valid", false)):
		_auto_repair_critical_map_issues()
		check = validate_current_map()

	current_map.is_finalized = true
	current_map.version += 1
	is_timer_running = false
	map_finalized.emit(current_map)
	return {
		"ok": true,
		"map_data": current_map,
		"validation": check
	}


func _auto_repair_critical_map_issues() -> void:
	if current_map == null:
		return

	# Ensure at least 1 start_spawn exists
	var has_spawn := false
	var has_finish := false
	for obj in current_map.objects:
		if not (obj is Dictionary):
			continue
		var t := str(obj.get("type", "")).to_lower()
		if t == "start_spawn" or t == "spawn":
			has_spawn = true
		elif t == "finish_line" or t == "finish" or t == "goal":
			has_finish = true

	if not has_spawn:
		place_object("start_spawn", Vector3(0.0, 0.5, 0.0), Vector3.ZERO, Vector3(4.0, 0.5, 4.0), "#33ff88", 1, true)
	if current_map.target_mode == D4FConstants.CompetitionMode.RACE and not has_finish:
		place_object("finish_line", Vector3(0.0, 0.5, -24.0), Vector3.ZERO, Vector3(6.0, 3.0, 1.5), "#ffcc22", 1, true)


func _instantiate_object_node(obj_dict: Dictionary) -> void:
	_ensure_containers()
	var obj_id := str(obj_dict.get("id", "obj_%d" % _spawned_object_nodes.size()))
	var obj_type := str(obj_dict.get("type", "platform")).to_lower()
	var pos := MapValidator._vec3_from_var(obj_dict.get("position", [0.0, 0.0, 0.0]))
	var rot := MapValidator._vec3_from_var(obj_dict.get("rotation", [0.0, 0.0, 0.0]))
	var scl := MapValidator._vec3_from_var(obj_dict.get("scale", [1.0, 1.0, 1.0]), Vector3.ONE)
	var col := Color.from_string(str(obj_dict.get("color", "#44aaff")), Color(0.27, 0.67, 1.0))

	var body := StaticBody3D.new()
	body.name = obj_id
	body.position = pos
	body.rotation_degrees = rot

	var mesh_inst := MeshInstance3D.new()
	var box_mesh := BoxMesh.new()
	box_mesh.size = scl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.55
	if obj_type in ["checkpoint", "finish_line", "start_spawn"]:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(col.r, col.g, col.b, 0.55)
	box_mesh.material = mat
	mesh_inst.mesh = box_mesh
	body.add_child(mesh_inst)

	if not (obj_type in ["checkpoint", "finish_line", "start_spawn"]):
		var shape_node := CollisionShape3D.new()
		var box_shape := BoxShape3D.new()
		box_shape.size = scl
		shape_node.shape = box_shape
		body.add_child(shape_node)

	_objects_root.add_child(body)
	_spawned_object_nodes[obj_id] = body


func _refresh_object_node(obj_dict: Dictionary) -> void:
	var obj_id := str(obj_dict.get("id", ""))
	if _spawned_object_nodes.has(obj_id):
		var old_node: Node = _spawned_object_nodes[obj_id]
		if is_instance_valid(old_node):
			old_node.queue_free()
		_spawned_object_nodes.erase(obj_id)
	_instantiate_object_node(obj_dict)


func _instantiate_terrain_stroke_node(stroke_dict: Dictionary) -> void:
	_ensure_containers()
	var stroke_id := str(stroke_dict.get("id", "stroke_%d" % _spawned_terrain_nodes.size()))
	var mesh := MeshExtruder3D.build_terrain_stroke_mesh(stroke_dict)
	var body := StaticBody3D.new()
	body.name = stroke_id

	var mesh_inst := MeshInstance3D.new()
	mesh_inst.mesh = mesh
	body.add_child(mesh_inst)

	var col_shape := CollisionShape3D.new()
	col_shape.shape = MeshExtruder3D.build_terrain_stroke_collision(mesh)
	body.add_child(col_shape)

	_terrain_root.add_child(body)
	_spawned_terrain_nodes[stroke_id] = body
