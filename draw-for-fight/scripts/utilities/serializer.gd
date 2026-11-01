class_name D4FSerializer
extends RefCounted

const MAX_RECURSION_DEPTH := 12
const MAX_STRING_LENGTH := 32768

static func sanitize_variant(val: Variant, depth: int = 0) -> Variant:
	if depth > MAX_RECURSION_DEPTH:
		return null

	var t := typeof(val)
	match t:
		TYPE_NIL, TYPE_BOOL, TYPE_INT:
			return val
		TYPE_FLOAT:
			var f: float = val
			if is_nan(f) or is_inf(f):
				return 0.0
			return f
		TYPE_STRING, TYPE_STRING_NAME:
			var s := String(val)
			if s.length() > MAX_STRING_LENGTH:
				return s.substr(0, MAX_STRING_LENGTH)
			return s
		TYPE_VECTOR2, TYPE_VECTOR2I:
			var v2 := Vector2(val)
			var x := 0.0 if (is_nan(v2.x) or is_inf(v2.x)) else v2.x
			var y := 0.0 if (is_nan(v2.y) or is_inf(v2.y)) else v2.y
			return [x, y]
		TYPE_VECTOR3, TYPE_VECTOR3I:
			var v3 := Vector3(val)
			var x := 0.0 if (is_nan(v3.x) or is_inf(v3.x)) else v3.x
			var y := 0.0 if (is_nan(v3.y) or is_inf(v3.y)) else v3.y
			var z := 0.0 if (is_nan(v3.z) or is_inf(v3.z)) else v3.z
			return [x, y, z]
		TYPE_COLOR:
			var c: Color = val
			return "#" + c.to_html(false)
		TYPE_PACKED_VECTOR2_ARRAY:
			var pv2: PackedVector2Array = val
			var out_v2: Array = []
			for pt in pv2:
				out_v2.append(sanitize_variant(pt, depth + 1))
			return out_v2
		TYPE_PACKED_VECTOR3_ARRAY:
			var pv3: PackedVector3Array = val
			var out_v3: Array = []
			for pt in pv3:
				out_v3.append(sanitize_variant(pt, depth + 1))
			return out_v3
		TYPE_PACKED_BYTE_ARRAY:
			var pba: PackedByteArray = val
			return pba.hex_encode()
		TYPE_ARRAY:
			var arr: Array = val
			var sanitized_arr: Array = []
			for item in arr:
				sanitized_arr.append(sanitize_variant(item, depth + 1))
			return sanitized_arr
		TYPE_DICTIONARY:
			var dict: Dictionary = val
			var sanitized_dict: Dictionary = {}
			var keys: Array = dict.keys()
			for k in keys:
				var clean_key := String(k)
				if clean_key.length() > 256:
					clean_key = clean_key.substr(0, 256)
				sanitized_dict[clean_key] = sanitize_variant(dict[k], depth + 1)
			return sanitized_dict
		_:
			# Reject unsafe types such as Object, Callable, Signal, RID
			return null

static func to_json_safe(data: Variant) -> String:
	var sanitized: Variant = sanitize_variant(data, 0)
	return JSON.stringify(sanitized, "", true, false)

static func from_json_safe(json_str: String, max_bytes: int = 65536) -> Variant:
	if json_str.is_empty():
		return null
	if json_str.length() > max_bytes:
		return null
	var utf8_bytes := json_str.to_utf8_buffer()
	if utf8_bytes.size() > max_bytes:
		return null

	var json := JSON.new()
	var err := json.parse(json_str)
	if err != OK:
		return null
	return sanitize_variant(json.data, 0)

static func compute_sha256_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	var digest: PackedByteArray = ctx.finish()
	return digest.hex_encode()

static func compute_sha256_bytes(data: PackedByteArray) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(data)
	return ctx.finish()

static func sanitize_float(val: Variant, default_val: float = 0.0, min_val: float = -100000.0, max_val: float = 100000.0) -> float:
	if typeof(val) != TYPE_FLOAT and typeof(val) != TYPE_INT:
		return default_val
	var f := float(val)
	if is_nan(f) or is_inf(f):
		return default_val
	return clampf(f, min_val, max_val)

static func array_to_vec2(arr: Variant, fallback: Vector2 = Vector2.ZERO) -> Vector2:
	if typeof(arr) == TYPE_VECTOR2:
		var v: Vector2 = arr
		return Vector2(sanitize_float(v.x, fallback.x), sanitize_float(v.y, fallback.y))
	if typeof(arr) == TYPE_ARRAY and (arr as Array).size() >= 2:
		var a: Array = arr
		return Vector2(sanitize_float(a[0], fallback.x), sanitize_float(a[1], fallback.y))
	return fallback

static func array_to_vec3(arr: Variant, fallback: Vector3 = Vector3.ZERO) -> Vector3:
	if typeof(arr) == TYPE_VECTOR3:
		var v: Vector3 = arr
		return Vector3(
			sanitize_float(v.x, fallback.x),
			sanitize_float(v.y, fallback.y),
			sanitize_float(v.z, fallback.z)
		)
	if typeof(arr) == TYPE_ARRAY and (arr as Array).size() >= 3:
		var a: Array = arr
		return Vector3(
			sanitize_float(a[0], fallback.x),
			sanitize_float(a[1], fallback.y),
			sanitize_float(a[2], fallback.z)
		)
	return fallback

static func vec2_to_array(v: Vector2) -> Array:
	return [
		sanitize_float(v.x, 0.0),
		sanitize_float(v.y, 0.0)
	]

static func vec3_to_array(v: Vector3) -> Array:
	return [
		sanitize_float(v.x, 0.0),
		sanitize_float(v.y, 0.0),
		sanitize_float(v.z, 0.0)
	]
