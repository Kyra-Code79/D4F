class_name PlayableVehicle3D
extends CharacterBody3D
## Arcade 3D physics vehicle built on CharacterBody3D for 100% deterministic
## cross-network synchronization, slope alignment, drift/grip physics, ramp jumping,
## and rotating custom 3D wheel child meshes.

signal checkpoint_reached(peer_id: int, checkpoint_index: int)
signal eliminated(peer_id: int, killer_peer_id: int, reason: String)
signal boost_activated(peer_id: int)

const BASE_TOP_SPEED := 21.0
const BASE_REVERSE_SPEED := 8.5
const BASE_ACCEL := 19.5
const BASE_BRAKE_DECEL := 28.0
const BASE_COAST_DECEL := 6.5
const BASE_STEER_RATE := 2.45
const BASE_GRAVITY := 24.0
const BOOST_DURATION := 1.4
const BOOST_COOLDOWN_TIME := 4.0
const BOOST_SPEED_BONUS := 9.5

var peer_id: int = 1
var player_name: String = "Driver"
var is_local_controlled: bool = false
var is_bot: bool = false
var creation_data: CreationData

var current_speed: float = 0.0
var steer_angle: float = 0.0
var current_checkpoint: int = 0
var laps_completed: int = 0
var is_eliminated: bool = false
var last_hit_by_peer: int = -1
var last_hit_timer: float = 0.0
var external_impulse: Vector3 = Vector3.ZERO
var boost_timer: float = 0.0
var boost_cooldown: float = 0.0
var lives_remaining: int = 3

var gravity_scale: float = 1.0
var mass_kg: float = 85.0
var speed_mult: float = 1.0
var accel_mult: float = 1.0
var jump_mult: float = 1.0
var grip_mult: float = 1.0
var bounce_mult: float = 0.30
var knockback_resist: float = 1.0

var _chassis_pivot: Node3D
var _mesh_instance: MeshInstance3D
var _wheels: Array[MeshInstance3D] = []
var _nametag: Label3D
var _wheel_spin_angle: float = 0.0


func _ready() -> void:
	floor_max_angle = deg_to_rad(55.0)
	floor_snap_length = 0.45
	add_to_group("competitors")


func setup_from_creation(creation: CreationData, p_peer_id: int, p_name: String) -> void:
	peer_id = p_peer_id
	player_name = p_name if not p_name.is_empty() else ("Driver %d" % p_peer_id)
	creation_data = creation if creation != null else CreationData.create_default_vehicle()

	var stats := creation_data.physics_stats
	if stats.is_empty():
		stats = PhysicsConfigurator.compute_balanced_stats(creation_data)

	mass_kg = float(stats.get("mass", 85.0))
	speed_mult = float(stats.get("speed_mult", 1.0))
	accel_mult = float(stats.get("accel_mult", 1.0))
	jump_mult = float(stats.get("jump_mult", 1.0))
	grip_mult = float(stats.get("grip", 1.0))
	bounce_mult = float(stats.get("bounce", 0.30))
	knockback_resist = maxf(0.4, float(stats.get("knockback_resist", 1.0)))

	for child in get_children():
		child.queue_free()
	_wheels.clear()

	_chassis_pivot = Node3D.new()
	_chassis_pivot.name = "ChassisPivot"
	add_child(_chassis_pivot)

	# Extruded custom chassis mesh oriented so 2D +X points along vehicle forward (-Z)
	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "VehicleExtrudedMesh"
	_mesh_instance.mesh = MeshExtruder3D.build_extruded_mesh_from_creation(creation_data)
	_mesh_instance.rotation.y = PI * 0.5
	_mesh_instance.position.y = 0.18
	_chassis_pivot.add_child(_mesh_instance)

	# Build 4 arcade 3D wheels around chassis
	_build_arcade_wheels()

	# Build collision shapes
	var shapes := MeshExtruder3D.build_collision_shapes_from_creation(creation_data)
	var idx := 0
	for shape in shapes:
		var col := CollisionShape3D.new()
		col.name = "VehicleCol_%d" % idx
		col.shape = shape
		col.position = Vector3(0.0, 0.75, 0.0)
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
	_nametag.modulate = Color(0.35, 1.0, 0.55) if is_local_controlled else Color(0.45, 0.85, 1.0)
	_nametag.position = Vector3(0.0, 2.35, 0.0)
	add_child(_nametag)


func _build_arcade_wheels() -> void:
	var wheel_mesh := CylinderMesh.new()
	wheel_mesh.top_radius = 0.32
	wheel_mesh.bottom_radius = 0.32
	wheel_mesh.height = 0.22
	wheel_mesh.radial_segments = 16

	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.14, 0.15, 0.18)
	tire_mat.roughness = 0.85
	wheel_mesh.material = tire_mat

	var offsets := [
		Vector3(-0.62, 0.32, -0.78),
		Vector3(0.62, 0.32, -0.78),
		Vector3(-0.62, 0.32, 0.78),
		Vector3(0.62, 0.32, 0.78)
	]

	for i in range(offsets.size()):
		var w := MeshInstance3D.new()
		w.name = "Wheel_%d" % i
		w.mesh = wheel_mesh
		w.position = offsets[i]
		w.rotation.z = PI * 0.5
		_chassis_pivot.add_child(w)
		_wheels.append(w)


func apply_vehicle_input(throttle: float, steering: float, brake_pressed: bool, boost_pressed: bool, delta: float) -> void:
	if is_eliminated:
		return

	if boost_cooldown > 0.0:
		boost_cooldown = maxf(0.0, boost_cooldown - delta)
	if boost_timer > 0.0:
		boost_timer = maxf(0.0, boost_timer - delta)
	if last_hit_timer > 0.0:
		last_hit_timer -= delta
		if last_hit_timer <= 0.0:
			last_hit_by_peer = -1

	if boost_pressed and boost_cooldown <= 0.0:
		boost_timer = BOOST_DURATION
		boost_cooldown = BOOST_COOLDOWN_TIME
		current_speed = maxf(current_speed, BASE_TOP_SPEED * speed_mult * 0.85) + 5.0
		boost_activated.emit(peer_id)

	var max_fwd := BASE_TOP_SPEED * speed_mult + (BOOST_SPEED_BONUS if boost_timer > 0.0 else 0.0)
	var max_rev := -BASE_REVERSE_SPEED * speed_mult

	if brake_pressed:
		current_speed = move_toward(current_speed, 0.0, BASE_BRAKE_DECEL * grip_mult * delta)
	elif absf(throttle) > 0.02:
		var target_spd := max_fwd * throttle if throttle > 0.0 else max_rev * (-throttle)
		var rate := BASE_ACCEL * accel_mult * (1.35 if boost_timer > 0.0 else 1.0)
		current_speed = move_toward(current_speed, target_spd, rate * delta)
	else:
		current_speed = move_toward(current_speed, 0.0, BASE_COAST_DECEL * delta)

	# Steering scales with speed & reverses when backing up
	steer_angle = clampf(steering, -1.0, 1.0) * deg_to_rad(28.0)
	var speed_factor := clampf(absf(current_speed) / 4.5, 0.15, 1.0)
	var dir_sign := -1.0 if current_speed < -0.2 else 1.0
	rotation.y += clampf(steering, -1.0, 1.0) * BASE_STEER_RATE * grip_mult * speed_factor * dir_sign * delta

	var forward_dir := -global_transform.basis.z.normalized()
	var desired_vel_xz := forward_dir * current_speed

	# Drift / lateral grip blending
	var current_xz := Vector3(velocity.x, 0.0, velocity.z)
	var lateral_grip := clampf(9.5 * grip_mult * (1.0 if is_on_floor() else 0.25) * delta, 0.0, 1.0)
	var blended_xz := current_xz.lerp(desired_vel_xz, lateral_grip)
	blended_xz += Vector3(external_impulse.x, 0.0, external_impulse.z)

	velocity.x = blended_xz.x
	velocity.z = blended_xz.z

	if is_on_floor():
		if external_impulse.y > 0.1:
			velocity.y = external_impulse.y
			external_impulse.y = 0.0
	else:
		velocity.y -= BASE_GRAVITY * gravity_scale * delta

	external_impulse = external_impulse.move_toward(Vector3.ZERO, 16.0 * delta)

	move_and_slide()
	_handle_vehicle_collisions()
	_update_visual_suspension_and_wheels(delta)

	if global_position.y < D4FConstants.ARENA_ELIMINATION_Y:
		trigger_elimination("fell_out_of_arena")


func _handle_vehicle_collisions() -> void:
	var count := get_slide_collision_count()
	for i in range(count):
		var col := get_slide_collision(i)
		if col == null:
			continue
		var collider := col.get_collider()
		if collider != null and collider != self and collider.is_in_group("competitors"):
			var normal := -col.get_normal()
			normal.y = 0.18
			var impact_speed := maxf(4.5, absf(current_speed) * 0.75)
			var power := clampf(mass_kg / 80.0, 0.75, 1.45)
			var impulse := normal.normalized() * impact_speed * power * (1.0 + bounce_mult)
			if collider.has_method("apply_collision_bump"):
				collider.call("apply_collision_bump", impulse, peer_id)
			elif collider.has_method("apply_knockback"):
				collider.call("apply_knockback", impulse, peer_id)
			current_speed *= 0.72


func apply_collision_bump(impulse: Vector3, attacker_peer_id: int) -> void:
	if is_eliminated:
		return
	var scaled := impulse / maxf(0.45, knockback_resist)
	external_impulse += Vector3(scaled.x, 0.0, scaled.z)
	velocity.y = maxf(velocity.y, scaled.y)
	if attacker_peer_id > 0 and attacker_peer_id != peer_id:
		last_hit_by_peer = attacker_peer_id
		last_hit_timer = 6.0


func trigger_elimination(reason: String = "hazard") -> void:
	if is_eliminated:
		return
	is_eliminated = true
	eliminated.emit(peer_id, last_hit_by_peer, reason)


func respawn_at(spawn_pos: Vector3, yaw_rad: float = 0.0) -> void:
	is_eliminated = false
	current_speed = 0.0
	velocity = Vector3.ZERO
	external_impulse = Vector3.ZERO
	last_hit_by_peer = -1
	last_hit_timer = 0.0
	rotation = Vector3(0.0, yaw_rad, 0.0)
	global_position = spawn_pos + Vector3(0.0, 0.85, 0.0)


func _update_visual_suspension_and_wheels(delta: float) -> void:
	if _chassis_pivot == null:
		return
	# Align chassis pitch/roll smoothly with floor slope + steering body roll
	var target_pitch := 0.0
	var target_roll := -steer_angle * clampf(current_speed / 15.0, -1.0, 1.0) * 0.35
	if is_on_floor():
		var n := get_floor_normal()
		var local_n := global_transform.basis.inverse() * n
		target_pitch = atan2(local_n.z, local_n.y)
		target_roll += -atan2(local_n.x, local_n.y) * 0.65
	else:
		target_pitch = clampf(velocity.y * 0.035, -0.35, 0.35)

	_chassis_pivot.rotation.x = lerpf(_chassis_pivot.rotation.x, target_pitch, minf(1.0, 10.0 * delta))
	_chassis_pivot.rotation.z = lerpf(_chassis_pivot.rotation.z, target_roll, minf(1.0, 10.0 * delta))

	# Spin wheels
	_wheel_spin_angle += (current_speed / 0.32) * delta
	for i in range(_wheels.size()):
		var w := _wheels[i]
		if w == null:
			continue
		w.rotation.x = _wheel_spin_angle
		if i < 2:
			w.rotation.y = steer_angle
