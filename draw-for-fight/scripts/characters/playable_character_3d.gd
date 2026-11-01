class_name PlayableCharacter3D
extends CharacterBody3D
## 3D physics competitor for custom player-drawn characters.
## Extrudes 2D strokes into a 3D mesh, attaches simplified Jolt collision shapes,
## applies balanced physics stats, and supports running, jumping, shoving, and knockbacks.

signal checkpoint_reached(peer_id: int, checkpoint_index: int)
signal eliminated(peer_id: int, killer_peer_id: int, reason: String)
signal shove_performed(peer_id: int, direction: Vector3)

const BASE_MOVE_SPEED := 8.8
const BASE_ACCEL := 26.0
const BASE_JUMP_VELOCITY := 9.2
const BASE_GRAVITY := 22.0
const SHOVE_COOLDOWN_TIME := 1.15
const SHOVE_RADIUS := 3.2
const SHOVE_BASE_FORCE := 14.5

var peer_id: int = 1
var player_name: String = "Player"
var is_local_controlled: bool = false
var is_bot: bool = false
var creation_data: CreationData

var current_checkpoint: int = 0
var laps_completed: int = 0
var is_eliminated: bool = false
var last_hit_by_peer: int = -1
var last_hit_timer: float = 0.0
var external_impulse: Vector3 = Vector3.ZERO
var shove_cooldown: float = 0.0
var lives_remaining: int = 3

var gravity_scale: float = 1.0
var mass_kg: float = 75.0
var speed_mult: float = 1.0
var accel_mult: float = 1.0
var jump_mult: float = 1.0
var grip_mult: float = 1.0
var bounce_mult: float = 0.25
var knockback_resist: float = 1.0

var _mesh_instance: MeshInstance3D
var _nametag: Label3D
var _anim_phase: float = 0.0
var _facing_yaw: float = 0.0
var _coyote_timer: float = 0.0


func _ready() -> void:
	floor_max_angle = deg_to_rad(52.0)
	floor_snap_length = 0.35
	add_to_group("competitors")


func setup_from_creation(creation: CreationData, p_peer_id: int, p_name: String) -> void:
	peer_id = p_peer_id
	player_name = p_name if not p_name.is_empty() else ("Player %d" % p_peer_id)
	creation_data = creation if creation != null else CreationData.create_default_stickman()

	var stats := creation_data.physics_stats
	if stats.is_empty():
		stats = PhysicsConfigurator.compute_balanced_stats(creation_data)

	mass_kg = float(stats.get("mass", 75.0))
	speed_mult = float(stats.get("speed_mult", 1.0))
	accel_mult = float(stats.get("accel_mult", 1.0))
	jump_mult = float(stats.get("jump_mult", 1.0))
	grip_mult = float(stats.get("grip", 1.0))
	bounce_mult = float(stats.get("bounce", 0.25))
	knockback_resist = maxf(0.4, float(stats.get("knockback_resist", 1.0)))

	# Clear previous children generated during setup
	for child in get_children():
		child.queue_free()

	# Build 3D extruded mesh
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "CharacterExtrudedMesh"
	_mesh_instance.mesh = MeshExtruder3D.build_extruded_mesh_from_creation(creation_data)
	add_child(_mesh_instance)

	# Build collision shapes
	var shapes := MeshExtruder3D.build_collision_shapes_from_creation(creation_data)
	var aabb := MeshExtruder3D.compute_creation_aabb(creation_data)
	var idx := 0
	for shape in shapes:
		var col := CollisionShape3D.new()
		col.name = "CollisionShape_%d" % idx
		col.shape = shape
		col.position = Vector3(0.0, maxf(0.9, aabb.size.y * 0.5), 0.0)
		add_child(col)
		idx += 1

	# Floating 3D nametag
	_nametag = Label3D.new()
	_nametag.name = "NameTag3D"
	_nametag.text = player_name
	_nametag.font_size = 36
	_nametag.outline_size = 10
	_nametag.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_nametag.no_depth_test = true
	_nametag.modulate = Color(0.35, 1.0, 0.55) if is_local_controlled else Color(1.0, 0.92, 0.45)
	_nametag.position = Vector3(0.0, maxf(2.25, aabb.size.y + 0.45), 0.0)
	add_child(_nametag)


func apply_movement_input(move_dir: Vector2, jump_pressed: bool, shove_pressed: bool, delta: float) -> void:
	if is_eliminated:
		return

	if shove_cooldown > 0.0:
		shove_cooldown = maxf(0.0, shove_cooldown - delta)
	if last_hit_timer > 0.0:
		last_hit_timer -= delta
		if last_hit_timer <= 0.0:
			last_hit_by_peer = -1

	# Gravity & Coyote Time
	if is_on_floor():
		_coyote_timer = 0.14
	else:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
		velocity.y -= BASE_GRAVITY * gravity_scale * delta

	# Jump
	if jump_pressed and _coyote_timer > 0.0:
		velocity.y = BASE_JUMP_VELOCITY * jump_mult
		_coyote_timer = 0.0

	# Horizontal movement
	var clamped_dir := move_dir.limit_length(1.0)
	var target_vel_xz := Vector3(clamped_dir.x, 0.0, clamped_dir.y) * (BASE_MOVE_SPEED * speed_mult)
	var current_xz := Vector3(velocity.x, 0.0, velocity.z)
	var control_rate := BASE_ACCEL * accel_mult * grip_mult * (1.0 if is_on_floor() else 0.55)
	var new_xz := current_xz.move_toward(target_vel_xz, control_rate * delta)

	# Blend external knockback impulse
	new_xz += Vector3(external_impulse.x, 0.0, external_impulse.z)
	velocity.x = new_xz.x
	velocity.z = new_xz.z
	if absf(external_impulse.y) > 0.05:
		velocity.y += external_impulse.y
		external_impulse.y = 0.0
	external_impulse = external_impulse.move_toward(Vector3.ZERO, 18.0 * delta)

	# Shove / melee wave
	if shove_pressed and shove_cooldown <= 0.0:
		_perform_shove(clamped_dir)

	move_and_slide()
	_handle_slide_collisions()
	_animate_character_mesh(clamped_dir, delta)

	if global_position.y < D4FConstants.ARENA_ELIMINATION_Y:
		trigger_elimination("fell_out_of_arena")


func _perform_shove(move_dir: Vector2) -> void:
	shove_cooldown = SHOVE_COOLDOWN_TIME
	var forward := Vector3(sin(_facing_yaw), 0.0, cos(_facing_yaw)).normalized()
	if move_dir.length_squared() > 0.04:
		forward = Vector3(move_dir.x, 0.0, move_dir.y).normalized()

	velocity += forward * 4.2
	shove_performed.emit(peer_id, forward)

	if not is_inside_tree():
		return
	var power_scale := clampf(mass_kg / 75.0, 0.75, 1.45)
	for node in get_tree().get_nodes_in_group("competitors"):
		if node == self or not (node is Node3D):
			continue
		var other := node as Node3D
		var diff := other.global_position - global_position
		diff.y = 0.0
		var dist := diff.length()
		if dist <= SHOVE_RADIUS and dist > 0.001:
			var push_dir := diff.normalized()
			var force := (SHOVE_BASE_FORCE * power_scale) * (1.0 - (dist / (SHOVE_RADIUS + 0.8)))
			var impulse := push_dir * force + Vector3(0.0, 4.2, 0.0)
			if other.has_method("apply_knockback"):
				other.call("apply_knockback", impulse, peer_id)
			elif other.has_method("apply_collision_bump"):
				other.call("apply_collision_bump", impulse, peer_id)


func _handle_slide_collisions() -> void:
	var count := get_slide_collision_count()
	for i in range(count):
		var col := get_slide_collision(i)
		if col == null:
			continue
		var collider := col.get_collider()
		if collider != null and collider != self and collider.is_in_group("competitors"):
			var normal := -col.get_normal()
			normal.y = 0.15
			var bump := normal.normalized() * (3.5 + bounce_mult * 4.0)
			if collider.has_method("apply_knockback"):
				collider.call("apply_knockback", bump, peer_id)


func apply_knockback(impulse: Vector3, attacker_peer_id: int) -> void:
	if is_eliminated:
		return
	var scaled_impulse := impulse / maxf(0.45, knockback_resist)
	external_impulse += Vector3(scaled_impulse.x, 0.0, scaled_impulse.z)
	velocity.y = maxf(velocity.y, scaled_impulse.y)
	if attacker_peer_id > 0 and attacker_peer_id != peer_id:
		last_hit_by_peer = attacker_peer_id
		last_hit_timer = 6.0


func trigger_elimination(reason: String = "hazard") -> void:
	if is_eliminated:
		return
	is_eliminated = true
	eliminated.emit(peer_id, last_hit_by_peer, reason)


func respawn_at(spawn_pos: Vector3) -> void:
	is_eliminated = false
	velocity = Vector3.ZERO
	external_impulse = Vector3.ZERO
	last_hit_by_peer = -1
	last_hit_timer = 0.0
	global_position = spawn_pos + Vector3(0.0, 0.8, 0.0)


func _animate_character_mesh(move_dir: Vector2, delta: float) -> void:
	if _mesh_instance == null:
		return
	var speed_xz := Vector2(velocity.x, velocity.z).length()
	if move_dir.length_squared() > 0.02:
		var target_yaw := atan2(move_dir.x, move_dir.y)
		_facing_yaw = lerp_angle(_facing_yaw, target_yaw, minf(1.0, 12.0 * delta))

	_mesh_instance.rotation.y = _facing_yaw
	if is_on_floor() and speed_xz > 0.4:
		_anim_phase += delta * speed_xz * 1.9
		_mesh_instance.position.y = absf(sin(_anim_phase)) * 0.12
		_mesh_instance.rotation.z = sin(_anim_phase) * 0.09
		_mesh_instance.rotation.x = clampf(speed_xz * 0.02, 0.0, 0.18)
	else:
		_mesh_instance.position.y = lerpf(_mesh_instance.position.y, 0.0, minf(1.0, 10.0 * delta))
		_mesh_instance.rotation.z = lerpf(_mesh_instance.rotation.z, 0.0, minf(1.0, 10.0 * delta))
		_mesh_instance.rotation.x = lerpf(_mesh_instance.rotation.x, 0.0, minf(1.0, 10.0 * delta))
