class_name MapData
extends RefCounted

var map_id: String = ""
var map_name: String = "Collaborative Arena"
var version: int = 1
var target_mode: int = D4FConstants.CompetitionMode.RACE
var arena_size: Vector3 = Vector3(120.0, 40.0, 120.0)
var terrain_strokes: Array = []
var objects: Array = []
var prep_time_limit: float = D4FConstants.DEFAULT_PREP_TIME_SEC
var is_finalized: bool = false
var allow_client_editing: bool = true
var locked_owners: Array = []

func _init() -> void:
	map_id = "map_%d_%d" % [int(Time.get_unix_time_from_system()), randi() % 1000000]

func to_dict() -> Dictionary:
	return {
		"map_id": map_id,
		"map_name": map_name,
		"version": version,
		"target_mode": target_mode,
		"arena_size": D4FSerializer.vec3_to_array(arena_size),
		"terrain_strokes": D4FSerializer.sanitize_variant(terrain_strokes),
		"objects": D4FSerializer.sanitize_variant(objects),
		"prep_time_limit": D4FSerializer.sanitize_float(prep_time_limit, 90.0, 15.0, 600.0),
		"is_finalized": is_finalized,
		"allow_client_editing": allow_client_editing,
		"locked_owners": D4FSerializer.sanitize_variant(locked_owners)
	}

static func from_dict(data: Dictionary) -> MapData:
	var m := MapData.new()
	var sanitized: Variant = D4FSerializer.sanitize_variant(data)
	if typeof(sanitized) != TYPE_DICTIONARY:
		return m
	var d: Dictionary = sanitized

	m.map_id = String(d.get("map_id", m.map_id))
	m.map_name = String(d.get("map_name", "Collaborative Arena")).substr(0, 64)
	m.version = maxi(1, int(d.get("version", 1)))
	m.target_mode = clampi(int(d.get("target_mode", D4FConstants.CompetitionMode.RACE)), 0, 3)
	m.arena_size = D4FSerializer.array_to_vec3(d.get("arena_size"), Vector3(120.0, 40.0, 120.0))
	m.prep_time_limit = D4FSerializer.sanitize_float(d.get("prep_time_limit", 90.0), 90.0, 15.0, 600.0)
	m.is_finalized = bool(d.get("is_finalized", false))
	m.allow_client_editing = bool(d.get("allow_client_editing", true))

	m.locked_owners = []
	if typeof(d.get("locked_owners")) == TYPE_ARRAY:
		for owner_val in (d["locked_owners"] as Array):
			m.locked_owners.append(int(owner_val))

	m.terrain_strokes = []
	if typeof(d.get("terrain_strokes")) == TYPE_ARRAY:
		for ts in (d["terrain_strokes"] as Array):
			if typeof(ts) == TYPE_DICTIONARY:
				m.terrain_strokes.append(_sanitize_terrain_stroke(ts as Dictionary, int((ts as Dictionary).get("owner_id", 1))))

	m.objects = []
	if typeof(d.get("objects")) == TYPE_ARRAY:
		for obj in (d["objects"] as Array):
			if m.objects.size() >= D4FConstants.MAX_MAP_OBJECTS:
				break
			if typeof(obj) == TYPE_DICTIONARY:
				m.objects.append(_sanitize_map_object(obj as Dictionary, int((obj as Dictionary).get("owner_id", 1))))

	return m

func can_peer_edit(peer_id: int, is_host: bool, obj_owner_id: int = -1) -> bool:
	if is_finalized:
		return false
	if is_host:
		return true
	if not allow_client_editing:
		return false
	if locked_owners.has(peer_id):
		return false
	if obj_owner_id != -1 and obj_owner_id != peer_id:
		return false
	return true

func get_peer_object_count(peer_id: int) -> int:
	var count := 0
	for obj in objects:
		if typeof(obj) == TYPE_DICTIONARY and int((obj as Dictionary).get("owner_id", -1)) == peer_id:
			count += 1
	return count

static func _sanitize_map_object(obj_dict: Dictionary, owner_id: int) -> Dictionary:
	var obj_id := String(obj_dict.get("id", ""))
	if obj_id.is_empty():
		obj_id = "obj_%d_%d" % [owner_id, randi() % 10000000]

	var obj_type := String(obj_dict.get("type", "platform"))
	if not D4FConstants.ALLOWED_MAP_OBJECT_TYPES.has(obj_type):
		obj_type = "platform"

	var pos := D4FSerializer.array_to_vec3(obj_dict.get("position"), Vector3.ZERO)
	pos.x = clampf(pos.x, -120.0, 120.0)
	pos.y = clampf(pos.y, -15.0, 60.0)
	pos.z = clampf(pos.z, -120.0, 120.0)

	var rot := D4FSerializer.array_to_vec3(obj_dict.get("rotation"), Vector3.ZERO)
	rot.x = clampf(rot.x, -360.0, 360.0)
	rot.y = clampf(rot.y, -360.0, 360.0)
	rot.z = clampf(rot.z, -360.0, 360.0)

	var scl := D4FSerializer.array_to_vec3(obj_dict.get("scale"), Vector3.ONE)
	scl.x = clampf(scl.x, 0.25, 40.0)
	scl.y = clampf(scl.y, 0.25, 25.0)
	scl.z = clampf(scl.z, 0.25, 40.0)

	var props: Dictionary = {}
	if typeof(obj_dict.get("properties")) == TYPE_DICTIONARY:
		var san_props: Variant = D4FSerializer.sanitize_variant(obj_dict["properties"])
		if typeof(san_props) == TYPE_DICTIONARY:
			props = san_props

	return {
		"id": obj_id,
		"type": obj_type,
		"owner_id": owner_id,
		"position": D4FSerializer.vec3_to_array(pos),
		"rotation": D4FSerializer.vec3_to_array(rot),
		"scale": D4FSerializer.vec3_to_array(scl),
		"color": String(obj_dict.get("color", "#44bbff")),
		"properties": props
	}

static func _sanitize_terrain_stroke(stroke_dict: Dictionary, owner_id: int) -> Dictionary:
	var stroke_id := String(stroke_dict.get("id", ""))
	if stroke_id.is_empty():
		stroke_id = "ter_%d_%d" % [owner_id, randi() % 10000000]

	var pts_out: Array = []
	var raw_pts: Variant = stroke_dict.get("points", [])
	if typeof(raw_pts) == TYPE_ARRAY:
		for p in (raw_pts as Array):
			if pts_out.size() >= D4FConstants.MAX_POINTS_PER_STROKE:
				break
			var v2 := D4FSerializer.array_to_vec2(p, Vector2.ZERO)
			pts_out.append([
				clampf(v2.x, -120.0, 120.0),
				clampf(v2.y, -120.0, 120.0)
			])

	var surface := String(stroke_dict.get("surface_type", "road"))
	if not D4FConstants.ALLOWED_SURFACE_TYPES.has(surface):
		surface = "road"

	return {
		"id": stroke_id,
		"owner_id": owner_id,
		"points": pts_out,
		"width": D4FSerializer.sanitize_float(stroke_dict.get("width", 8.0), 8.0, 2.0, 32.0),
		"height": D4FSerializer.sanitize_float(stroke_dict.get("height", 1.0), 1.0, 0.25, 10.0),
		"y_offset": D4FSerializer.sanitize_float(stroke_dict.get("y_offset", 0.0), 0.0, -10.0, 40.0),
		"color": String(stroke_dict.get("color", "#556677")),
		"surface_type": surface
	}

func add_object(obj_dict: Dictionary, peer_id: int, is_host: bool) -> Dictionary:
	if not can_peer_edit(peer_id, is_host, -1):
		return {"ok": false, "object": {}, "error": "Editing not permitted for peer %d." % peer_id}
	if objects.size() >= D4FConstants.MAX_MAP_OBJECTS:
		return {"ok": false, "object": {}, "error": "Map object budget (%d) reached." % D4FConstants.MAX_MAP_OBJECTS}
	if not is_host and get_peer_object_count(peer_id) >= D4FConstants.MAX_OBJECTS_PER_PLAYER:
		return {"ok": false, "object": {}, "error": "Per-player object limit (%d) reached." % D4FConstants.MAX_OBJECTS_PER_PLAYER}

	var clean_obj := _sanitize_map_object(obj_dict, peer_id)
	objects.append(clean_obj)
	version += 1
	return {"ok": true, "object": clean_obj, "error": ""}

func update_object(obj_id: String, updates: Dictionary, peer_id: int, is_host: bool) -> Dictionary:
	for i in range(objects.size()):
		var cur: Dictionary = objects[i]
		if String(cur.get("id", "")) == obj_id:
			var owner_id := int(cur.get("owner_id", 1))
			if not can_peer_edit(peer_id, is_host, owner_id):
				return {"ok": false, "object": {}, "error": "Permission denied to update object %s." % obj_id}
			var merged := cur.duplicate(true)
			for k in updates.keys():
				if k != "id" and k != "owner_id":
					merged[k] = updates[k]
			var sanitized := _sanitize_map_object(merged, owner_id)
			sanitized["id"] = obj_id
			objects[i] = sanitized
			version += 1
			return {"ok": true, "object": sanitized, "error": ""}
	return {"ok": false, "object": {}, "error": "Object %s not found." % obj_id}

func remove_object(obj_id: String, peer_id: int, is_host: bool) -> Dictionary:
	for i in range(objects.size()):
		var cur: Dictionary = objects[i]
		if String(cur.get("id", "")) == obj_id:
			var owner_id := int(cur.get("owner_id", 1))
			if not can_peer_edit(peer_id, is_host, owner_id):
				return {"ok": false, "object": {}, "error": "Permission denied to remove object %s." % obj_id}
			var removed: Dictionary = objects[i]
			objects.remove_at(i)
			version += 1
			return {"ok": true, "object": removed, "error": ""}
	return {"ok": false, "object": {}, "error": "Object %s not found." % obj_id}

func add_terrain_stroke(stroke_dict: Dictionary, peer_id: int, is_host: bool) -> Dictionary:
	if not can_peer_edit(peer_id, is_host, -1):
		return {"ok": false, "stroke": {}, "error": "Editing not permitted for peer %d." % peer_id}
	if terrain_strokes.size() >= D4FConstants.MAX_STROKES_PER_CREATION:
		return {"ok": false, "stroke": {}, "error": "Terrain stroke limit reached."}

	var clean_stroke := _sanitize_terrain_stroke(stroke_dict, peer_id)
	if (clean_stroke["points"] as Array).size() < 2:
		return {"ok": false, "stroke": {}, "error": "Terrain stroke requires at least 2 points."}

	terrain_strokes.append(clean_stroke)
	version += 1
	return {"ok": true, "stroke": clean_stroke, "error": ""}

func get_spawn_positions() -> Array[Vector3]:
	var spawns: Array[Vector3] = []
	for obj in objects:
		if typeof(obj) == TYPE_DICTIONARY and String((obj as Dictionary).get("type", "")) == "start_spawn":
			spawns.append(D4FSerializer.array_to_vec3((obj as Dictionary).get("position"), Vector3(0.0, 2.0, 0.0)))
	if spawns.is_empty():
		for i in range(D4FConstants.MAX_PLAYERS):
			var row := i / 4
			var col := i % 4
			spawns.append(Vector3(-9.0 + float(col) * 6.0, 2.5, 42.0 + float(row) * 5.0))
	return spawns

static func create_default_arena(mode: int = D4FConstants.CompetitionMode.RACE) -> MapData:
	var m := MapData.new()
	m.target_mode = mode
	m.version = 1
	m.arena_size = Vector3(120.0, 40.0, 120.0)

	match mode:
		D4FConstants.CompetitionMode.RACE:
			m.map_name = "Skyline Sketch Circuit"
		D4FConstants.CompetitionMode.OBSTACLE_SURVIVAL:
			m.map_name = "Sweeper Survival Citadel"
		D4FConstants.CompetitionMode.PHYSICS_BATTLE:
			m.map_name = "Knockout Sketch Colosseum"
		_:
			m.map_name = "Custom Sandbox Arena"

	# Base extruded road/platform stroke
	m.terrain_strokes.append({
		"id": "ter_base_track",
		"owner_id": 1,
		"points": [[0.0, 48.0], [0.0, 15.0], [-12.0, -10.0], [0.0, -45.0]],
		"width": 22.0,
		"height": 1.2,
		"y_offset": 0.0,
		"color": "#3d4b5c",
		"surface_type": "road"
	})

	# Secondary elevated platform stroke
	m.terrain_strokes.append({
		"id": "ter_side_bridge",
		"owner_id": 1,
		"points": [[14.0, 20.0], [18.0, -5.0], [8.0, -32.0]],
		"width": 10.0,
		"height": 1.0,
		"y_offset": 2.0,
		"color": "#4f6278",
		"surface_type": "boost"
	})

	# 8 Start Spawns
	for i in range(D4FConstants.MAX_PLAYERS):
		var col := i % 4
		var row := i / 4
		var sx := -9.0 + float(col) * 6.0
		var sz := 40.0 + float(row) * 5.0
		m.objects.append({
			"id": "spawn_%d" % (i + 1),
			"type": "start_spawn",
			"owner_id": 1,
			"position": [sx, 1.5, sz],
			"rotation": [0.0, 0.0, 0.0],
			"scale": [2.0, 0.5, 2.0],
			"color": "#33ff88",
			"properties": {"spawn_index": i}
		})

	# Main arena floor platform
	m.objects.append({
		"id": "obj_main_deck",
		"type": "platform",
		"owner_id": 1,
		"position": [0.0, -0.6, 0.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [44.0, 1.2, 108.0],
		"color": "#2d3748",
		"properties": {"friction": 1.0}
	})

	# Ramps
	m.objects.append({
		"id": "obj_center_ramp",
		"type": "ramp",
		"owner_id": 1,
		"position": [0.0, 1.2, 16.0],
		"rotation": [14.0, 0.0, 0.0],
		"scale": [10.0, 1.5, 8.0],
		"color": "#f6ad55",
		"properties": {"boost": 1.25}
	})

	# Checkpoints
	m.objects.append({
		"id": "obj_checkpoint_1",
		"type": "checkpoint",
		"owner_id": 1,
		"position": [0.0, 3.0, 10.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [16.0, 6.0, 1.5],
		"color": "#63b3ed",
		"properties": {"checkpoint_index": 0}
	})
	m.objects.append({
		"id": "obj_checkpoint_2",
		"type": "checkpoint",
		"owner_id": 1,
		"position": [-6.0, 3.0, -18.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [16.0, 6.0, 1.5],
		"color": "#63b3ed",
		"properties": {"checkpoint_index": 1}
	})

	# Obstacle spinners
	m.objects.append({
		"id": "obj_spinner_1",
		"type": "spinner",
		"owner_id": 1,
		"position": [0.0, 1.6, -4.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [12.0, 1.2, 1.4],
		"color": "#fc8181",
		"properties": {"spin_speed": 2.4, "knockback": 18.0}
	})
	m.objects.append({
		"id": "obj_spinner_2",
		"type": "spinner",
		"owner_id": 1,
		"position": [-4.0, 1.6, -26.0],
		"rotation": [0.0, 45.0, 0.0],
		"scale": [11.0, 1.2, 1.4],
		"color": "#f56565",
		"properties": {"spin_speed": -2.8, "knockback": 22.0}
	})

	# Bumpers
	m.objects.append({
		"id": "obj_bumper_left",
		"type": "bumper",
		"owner_id": 1,
		"position": [-8.0, 1.5, 4.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [3.2, 2.5, 3.2],
		"color": "#ecc94b",
		"properties": {"bounce_force": 24.0}
	})
	m.objects.append({
		"id": "obj_bumper_right",
		"type": "bumper",
		"owner_id": 1,
		"position": [8.0, 1.5, -12.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [3.2, 2.5, 3.2],
		"color": "#ecc94b",
		"properties": {"bounce_force": 24.0}
	})

	# Boost pad
	m.objects.append({
		"id": "obj_boost_pad_1",
		"type": "boost_pad",
		"owner_id": 1,
		"position": [0.0, 0.2, 26.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [6.0, 0.3, 6.0],
		"color": "#48bb78",
		"properties": {"boost_impulse": 28.0}
	})

	# Finish Line
	m.objects.append({
		"id": "obj_finish_line",
		"type": "finish_line",
		"owner_id": 1,
		"position": [0.0, 3.5, -44.0],
		"rotation": [0.0, 0.0, 0.0],
		"scale": [20.0, 7.0, 2.0],
		"color": "#ffd700",
		"properties": {"goal": true}
	})

	return m
