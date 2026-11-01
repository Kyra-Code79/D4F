class_name CreationData
extends RefCounted

var creation_id: String = ""
var creation_name: String = "Stick Fighter"
var author_name: String = "Player"
var creation_type: int = D4FConstants.CreationType.CHARACTER
var template_id: String = "stickman"
var strokes: Array = []
var extrusion_depth: float = 0.35
var physics_stats: Dictionary = {
	"mass": 70.0,
	"speed_mult": 1.0,
	"accel_mult": 1.0,
	"jump_mult": 1.0,
	"grip": 1.0,
	"bounce": 0.2,
	"knockback_resist": 1.0
}
var created_at: int = 0
var checksum: String = ""

func _init() -> void:
	created_at = int(Time.get_unix_time_from_system())
	creation_id = "crt_%d_%d" % [created_at, randi() % 1000000]

func to_dict() -> Dictionary:
	var clean_strokes: Array = []
	for s in strokes:
		if typeof(s) != TYPE_DICTIONARY:
			continue
		var sd: Dictionary = s
		var pts_out: Array = []
		var raw_pts: Variant = sd.get("points", [])
		if typeof(raw_pts) == TYPE_ARRAY:
			for pt in (raw_pts as Array):
				var v2 := D4FSerializer.array_to_vec2(pt)
				pts_out.append([snappedf(v2.x, 0.01), snappedf(v2.y, 0.01)])
		elif typeof(raw_pts) == TYPE_PACKED_VECTOR2_ARRAY:
			for pt in (raw_pts as PackedVector2Array):
				pts_out.append([snappedf(pt.x, 0.01), snappedf(pt.y, 0.01)])
		clean_strokes.append({
			"points": pts_out,
			"color": String(sd.get("color", "#33aaff")),
			"thickness": D4FSerializer.sanitize_float(sd.get("thickness", 8.0), 8.0, 2.0, 28.0),
			"part_tag": String(sd.get("part_tag", "body"))
		})

	var dict := {
		"creation_id": creation_id,
		"creation_name": creation_name,
		"author_name": author_name,
		"creation_type": creation_type,
		"template_id": template_id,
		"strokes": clean_strokes,
		"extrusion_depth": D4FSerializer.sanitize_float(extrusion_depth, 0.35, 0.1, 1.5),
		"physics_stats": D4FSerializer.sanitize_variant(physics_stats),
		"created_at": created_at,
		"checksum": checksum if not checksum.is_empty() else compute_checksum()
	}
	return dict

static func from_dict(data: Dictionary) -> CreationData:
	var c := CreationData.new()
	var sanitized_data: Variant = D4FSerializer.sanitize_variant(data)
	if typeof(sanitized_data) != TYPE_DICTIONARY:
		return c
	var d: Dictionary = sanitized_data

	c.creation_id = String(d.get("creation_id", c.creation_id))
	c.creation_name = String(d.get("creation_name", "Stick Fighter")).substr(0, 48)
	c.author_name = String(d.get("author_name", "Player")).substr(0, 32)
	c.creation_type = clampi(int(d.get("creation_type", D4FConstants.CreationType.CHARACTER)), 0, 1)
	c.template_id = String(d.get("template_id", "stickman" if c.creation_type == D4FCanonicalType(0) else "wheeled_vehicle"))
	c.extrusion_depth = D4FSerializer.sanitize_float(d.get("extrusion_depth", 0.35), 0.35, 0.1, 1.5)
	c.created_at = int(d.get("created_at", c.created_at))

	if typeof(d.get("physics_stats")) == TYPE_DICTIONARY:
		var ps: Dictionary = d["physics_stats"]
		c.physics_stats = {
			"mass": D4FSerializer.sanitize_float(ps.get("mass", 70.0), 70.0, 15.0, 500.0),
			"speed_mult": D4FSerializer.sanitize_float(ps.get("speed_mult", 1.0), 1.0, 0.4, 2.5),
			"accel_mult": D4FSerializer.sanitize_float(ps.get("accel_mult", 1.0), 1.0, 0.4, 2.5),
			"jump_mult": D4FSerializer.sanitize_float(ps.get("jump_mult", 1.0), 1.0, 0.4, 2.5),
			"grip": D4FSerializer.sanitize_float(ps.get("grip", 1.0), 1.0, 0.1, 3.0),
			"bounce": D4FSerializer.sanitize_float(ps.get("bounce", 0.2), 0.2, 0.0, 1.2),
			"knockback_resist": D4FSerializer.sanitize_float(ps.get("knockback_resist", 1.0), 1.0, 0.2, 3.0)
		}

	c.strokes = []
	var raw_strokes: Variant = d.get("strokes", [])
	if typeof(raw_strokes) == TYPE_ARRAY:
		for s in (raw_strokes as Array):
			if c.strokes.size() >= D4FConstants.MAX_STROKES_PER_CREATION:
				break
			if typeof(s) != TYPE_DICTIONARY:
				continue
			var sd: Dictionary = s
			var pts_list: Array = []
			var raw_pts: Variant = sd.get("points", [])
			if typeof(raw_pts) == TYPE_ARRAY:
				for p in (raw_pts as Array):
					if pts_list.size() >= D4FConstants.MAX_POINTS_PER_STROKE:
						break
					var v2 := D4FSerializer.array_to_vec2(p, Vector2(256.0, 256.0))
					pts_list.append([
						clampf(v2.x, 0.0, 512.0),
						clampf(v2.y, 0.0, 512.0)
					])
			if pts_list.size() >= 2:
				c.strokes.append({
					"points": pts_list,
					"color": String(sd.get("color", "#33aaff")),
					"thickness": D4FSerializer.sanitize_float(sd.get("thickness", 8.0), 8.0, 2.0, 28.0),
					"part_tag": String(sd.get("part_tag", "body"))
				})

	c.checksum = c.compute_checksum()
	return c

static func D4FCanonicalType(val: int) -> int:
	return val

func compute_checksum() -> String:
	var payload := {
		"creation_id": creation_id,
		"creation_type": creation_type,
		"template_id": template_id,
		"extrusion_depth": snappedf(extrusion_depth, 0.001),
		"strokes": strokes
	}
	var canonical := D4FSerializer.to_json_safe(payload)
	checksum = D4FSerializer.compute_sha256_hex(canonical)
	return checksum

func add_stroke(points: PackedVector2Array, color: Color, thickness: float, part_tag: String = "body") -> void:
	if points.size() < 2:
		return
	if strokes.size() >= D4FConstants.MAX_STROKES_PER_CREATION:
		return

	var serialized_pts: Array = []
	var count := mini(points.size(), D4FConstants.MAX_POINTS_PER_STROKE)
	for i in range(count):
		var pt := points[i]
		var cx := clampf(D4FSerializer.sanitize_float(pt.x, 256.0), 0.0, 512.0)
		var cy := clampf(D4FSerializer.sanitize_float(pt.y, 256.0), 0.0, 512.0)
		serialized_pts.append([snappedf(cx, 0.01), snappedf(cy, 0.01)])

	var color_hex := "#" + color.to_html(false)
	strokes.append({
		"points": serialized_pts,
		"color": color_hex,
		"thickness": clampf(thickness, 2.0, 28.0),
		"part_tag": part_tag
	})
	compute_checksum()

func clear_strokes() -> void:
	strokes.clear()
	compute_checksum()

func undo_last_stroke() -> void:
	if not strokes.is_empty():
		strokes.pop_back()
		compute_checksum()

func get_total_point_count() -> int:
	var total := 0
	for s in strokes:
		if typeof(s) == TYPE_DICTIONARY and typeof(s.get("points")) == TYPE_ARRAY:
			total += (s["points"] as Array).size()
	return total

func validate() -> Dictionary:
	var errors: Array = []
	if creation_name.strip_edges().is_empty():
		errors.append("Creation name cannot be empty.")
	if strokes.is_empty():
		errors.append("Creation must contain at least 1 stroke.")
	if strokes.size() > D4FConstants.MAX_STROKES_PER_CREATION:
		errors.append("Stroke count (%d) exceeds limit (%d)." % [strokes.size(), D4FConstants.MAX_STROKES_PER_CREATION])

	var total_pts := 0
	for i in range(strokes.size()):
		var s: Variant = strokes[i]
		if typeof(s) != TYPE_DICTIONARY:
			errors.append("Stroke %d is not a valid Dictionary." % i)
			continue
		var sd: Dictionary = s
		var pts: Variant = sd.get("points", [])
		if typeof(pts) != TYPE_ARRAY or (pts as Array).size() < 2:
			errors.append("Stroke %d must have at least 2 points." % i)
			continue
		if (pts as Array).size() > D4FConstants.MAX_POINTS_PER_STROKE:
			errors.append("Stroke %d exceeds MAX_POINTS_PER_STROKE (%d)." % [i, D4FConstants.MAX_POINTS_PER_STROKE])
		total_pts += (pts as Array).size()

	var estimated_verts := total_pts * 4 + strokes.size() * 8
	if estimated_verts > D4FConstants.MAX_VERTICES_PER_MESH:
		errors.append("Estimated vertex count (%d) exceeds budget (%d)." % [estimated_verts, D4FConstants.MAX_VERTICES_PER_MESH])

	return {
		"valid": errors.is_empty(),
		"errors": errors
	}

static func create_default_stickman(custom_name: String = "Default Stickman", primary_color: String = "#33aaff") -> CreationData:
	var c := CreationData.new()
	c.creation_name = custom_name
	c.creation_type = D4FConstants.CreationType.CHARACTER
	c.template_id = "stickman"
	c.extrusion_depth = 0.35
	c.physics_stats = {
		"mass": 72.0,
		"speed_mult": 1.05,
		"accel_mult": 1.1,
		"jump_mult": 1.05,
		"grip": 1.0,
		"bounce": 0.2,
		"knockback_resist": 1.0
	}

	var head_pts: Array = []
	var head_center := Vector2(256.0, 118.0)
	var head_radius := 36.0
	for i in range(13):
		var angle := (TAU * float(i)) / 12.0
		head_pts.append([
			snappedf(head_center.x + cos(angle) * head_radius, 0.01),
			snappedf(head_center.y + sin(angle) * head_radius, 0.01)
		])

	c.strokes = [
		{
			"points": head_pts,
			"color": primary_color,
			"thickness": 10.0,
			"part_tag": "head"
		},
		{
			"points": [[256.0, 154.0], [256.0, 225.0], [256.0, 302.0]],
			"color": primary_color,
			"thickness": 12.0,
			"part_tag": "torso"
		},
		{
			"points": [[256.0, 182.0], [202.0, 216.0], [164.0, 254.0]],
			"color": "#ffdd44",
			"thickness": 9.0,
			"part_tag": "left_arm"
		},
		{
			"points": [[256.0, 182.0], [310.0, 216.0], [348.0, 254.0]],
			"color": "#ffdd44",
			"thickness": 9.0,
			"part_tag": "right_arm"
		},
		{
			"points": [[256.0, 302.0], [220.0, 376.0], [198.0, 444.0]],
			"color": primary_color,
			"thickness": 10.0,
			"part_tag": "left_leg"
		},
		{
			"points": [[256.0, 302.0], [292.0, 376.0], [314.0, 444.0]],
			"color": primary_color,
			"thickness": 10.0,
			"part_tag": "right_leg"
		}
	]
	c.compute_checksum()
	return c

static func create_default_vehicle(custom_name: String = "Sketch Racer", primary_color: String = "#ff6622") -> CreationData:
	var c := CreationData.new()
	c.creation_name = custom_name
	c.creation_type = D4FConstants.CreationType.VEHICLE
	c.template_id = "wheeled_vehicle"
	c.extrusion_depth = 0.55
	c.physics_stats = {
		"mass": 145.0,
		"speed_mult": 1.35,
		"accel_mult": 1.2,
		"jump_mult": 0.85,
		"grip": 1.25,
		"bounce": 0.15,
		"knockback_resist": 1.35
	}

	var front_wheel_pts: Array = []
	var rear_wheel_pts: Array = []
	var wheel_radius := 38.0
	var front_center := Vector2(352.0, 336.0)
	var rear_center := Vector2(164.0, 336.0)
	for i in range(13):
		var angle := (TAU * float(i)) / 12.0
		front_wheel_pts.append([
			snappedf(front_center.x + cos(angle) * wheel_radius, 0.01),
			snappedf(front_center.y + sin(angle) * wheel_radius, 0.01)
		])
		rear_wheel_pts.append([
			snappedf(rear_center.x + cos(angle) * wheel_radius, 0.01),
			snappedf(rear_center.y + sin(angle) * wheel_radius, 0.01)
		])

	c.strokes = [
		{
			"points": [[104.0, 316.0], [180.0, 320.0], [340.0, 320.0], [418.0, 306.0], [392.0, 276.0], [118.0, 276.0], [104.0, 316.0]],
			"color": primary_color,
			"thickness": 14.0,
			"part_tag": "chassis"
		},
		{
			"points": [[174.0, 276.0], [212.0, 218.0], [308.0, 218.0], [352.0, 276.0]],
			"color": "#55ddff",
			"thickness": 10.0,
			"part_tag": "cabin"
		},
		{
			"points": front_wheel_pts,
			"color": "#2b2f36",
			"thickness": 12.0,
			"part_tag": "front_wheel"
		},
		{
			"points": rear_wheel_pts,
			"color": "#2b2f36",
			"thickness": 12.0,
			"part_tag": "rear_wheel"
		},
		{
			"points": [[118.0, 276.0], [92.0, 232.0], [134.0, 232.0]],
			"color": "#ffcc22",
			"thickness": 9.0,
			"part_tag": "spoiler"
		}
	]
	c.compute_checksum()
	return c
