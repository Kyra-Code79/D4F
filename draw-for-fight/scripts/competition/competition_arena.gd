class_name CompetitionArena3D
extends Node3D
## Orchestrates the 3D Competition Arena scene at runtime:
## - Builds the 3D environment (sky/lighting, arena geometry from MapData, dynamic spinning
##   obstacles, checkpoint triggers, finish line trigger, elimination killplane).
## - Spawns up to 8 competitors (PlayableCharacter3D or PlayableVehicle3D, local player +
##   remote network peers + AI bots).
## - Runs follow-camera (Camera3D) behind the local player with mouse/keyboard orbit &
##   spectator switching when eliminated.
## - Feeds authoritative checkpoint/elimination/finish events to the active CompetitionModeBase
##   and MatchManager.

signal competitor_checkpoint(peer_id: int, checkpoint_index: int)
signal competitor_eliminated(peer_id: int, killer_peer_id: int, reason: String)
signal competitor_finished(peer_id: int)
signal match_state_updated(status_snapshot: Dictionary)
signal match_finished(rankings: Array)

const MAX_COMPETITORS := 8

var current_map: MapData
var mode_controller: CompetitionModeBase
var bot_controller: AIBotController = AIBotController.new()
var competitors: Dictionary = {} # peer_id -> PlayableCharacter3D or PlayableVehicle3D
var spawn_transforms: Array[Transform3D] = []
var checkpoint_positions: Array[Vector3] = []
var local_peer_id: int = 1
var spectated_peer_id: int = 1
var is_arena_active: bool = false

var _env_root: Node3D
var _geometry_root: Node3D
var _competitors_root: Node3D
var _spinning_hazards: Array[Node3D] = []
var _camera_rig: Node3D
var _camera: Camera3D
var _cam_yaw: float = 0.0
var _cam_pitch: float = -0.32
var _cam_distance: float = 7.5
var _hud_layer: CanvasLayer
var _hud_timer_label: Label
var _hud_scores_label: Label
var _hud_countdown_label: Label


func _ready() -> void:
	_setup_scene_roots()
	_setup_lighting_and_environment()
	_setup_follow_camera()
	_setup_arena_hud()
	_auto_initialize_from_managers()


func _setup_arena_hud() -> void:
	_hud_layer = CanvasLayer.new()
	_hud_layer.name = "ArenaHUD"
	add_child(_hud_layer)

	var top_bar := PanelContainer.new()
	D4FUITheme.style_panel(top_bar, Color(0.08, 0.10, 0.18, 0.88), D4FUITheme.COLOR_ACCENT_BLUE, 8)
	top_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top_bar.offset_left = 18.0
	top_bar.offset_right = -18.0
	top_bar.offset_top = 28.0
	top_bar.offset_bottom = 86.0
	_hud_layer.add_child(top_bar)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 18)
	top_bar.add_child(hbox)

	_hud_timer_label = D4FUITheme.create_header_label("TIME: 180.0s", 20, D4FUITheme.COLOR_ACCENT_GOLD)
	hbox.add_child(_hud_timer_label)

	_hud_scores_label = D4FUITheme.create_body_label("WASD/Arrows: Move/Steer | SPACE: Jump/Brake | SHIFT: Shove/Boost | TAB: Spectate", 14, D4FUITheme.COLOR_TEXT_MAIN)
	_hud_scores_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(_hud_scores_label)

	var end_btn := Button.new()
	end_btn.text = "End Match & View Rankings →"
	D4FUITheme.style_button(end_btn, D4FUITheme.COLOR_ACCENT_GREEN, Vector2(210, 36))
	end_btn.pressed.connect(_finish_and_go_to_results)
	hbox.add_child(end_btn)

	_hud_countdown_label = D4FUITheme.create_header_label("", 44, D4FUITheme.COLOR_ACCENT_GOLD)
	_hud_countdown_label.set_anchors_preset(Control.PRESET_CENTER)
	_hud_layer.add_child(_hud_countdown_label)


func _auto_initialize_from_managers() -> void:
	if is_arena_active:
		return
	var gm := get_node_or_null("/root/GameManager")
	var mm := get_node_or_null("/root/MatchManager")
	if gm == null:
		return
	var map_to_use: MapData = gm.active_map if gm.active_map != null else MapData.create_default_arena(gm.selected_mode)
	var plist: Array = []
	var rules: Dictionary = {}
	if mm != null and not mm.participants.is_empty():
		plist = mm.participants.values()
		rules = mm.custom_rules
	else:
		plist = [{"id": 1, "name": gm.player_profile.get("player_name", "Player 1"), "is_bot": false, "creation": gm.get_active_creation_for_mode(gm.selected_mode)}]
		if has_node("/root/AIAssistantManager"):
			var ai := get_node("/root/AIAssistantManager")
			for b in range(1, 8):
				plist.append(ai.create_bot_participant(b, gm.selected_mode == D4FConstants.CompetitionMode.RACE))
	initialize_competition(map_to_use, gm.selected_mode, plist, rules, 1)
	if mm != null:
		mm.start_countdown(3.0)


func _finish_and_go_to_results() -> void:
	is_arena_active = false
	var final_rankings: Array = mode_controller.compute_rankings() if mode_controller != null else []
	if has_node("/root/MatchManager"):
		var mm := get_node("/root/MatchManager")
		for r in final_rankings:
			var pid := int(r.get("peer_id", r.get("id", 1)))
			if mm.participants.has(pid):
				mm.participants[pid]["score"] = int(r.get("score", 0))
				mm.participants[pid]["checkpoints"] = int(r.get("checkpoints", 0))
				mm.participants[pid]["eliminations"] = int(r.get("eliminations", r.get("knockouts", 0)))
				mm.participants[pid]["survival_time"] = float(r.get("survival_time", 0.0))
				mm.participants[pid]["finished"] = bool(r.get("finished", false))
				mm.participants[pid]["finish_time"] = float(r.get("finish_time", 999999.0))
		mm.finalize_match()
	match_finished.emit(final_rankings)
	if has_node("/root/GameManager"):
		get_node("/root/GameManager").navigate_to(D4FConstants.GameState.RESULTS_RANKINGS)


func _setup_scene_roots() -> void:
	if _env_root == null:
		_env_root = Node3D.new()
		_env_root.name = "EnvironmentRoot"
		add_child(_env_root)
	if _geometry_root == null:
		_geometry_root = Node3D.new()
		_geometry_root.name = "ArenaGeometryRoot"
		add_child(_geometry_root)
	if _competitors_root == null:
		_competitors_root = Node3D.new()
		_competitors_root.name = "CompetitorsRoot"
		add_child(_competitors_root)


func _setup_lighting_and_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.name = "ArenaWorldEnvironment"
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.12, 0.20)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.65, 0.75, 0.92)
	env.ambient_light_energy = 0.75
	world_env.environment = env
	_env_root.add_child(world_env)

	var sun := DirectionalLight3D.new()
	sun.name = "SunLight3D"
	sun.light_energy = 1.35
	sun.light_color = Color(1.0, 0.97, 0.90)
	sun.shadow_enabled = true
	sun.rotation_degrees = Vector3(-52.0, 35.0, 0.0)
	_env_root.add_child(sun)


func _setup_follow_camera() -> void:
	_camera_rig = Node3D.new()
	_camera_rig.name = "FollowCameraRig"
	add_child(_camera_rig)

	_camera = Camera3D.new()
	_camera.name = "ArenaCamera3D"
	_camera.fov = 68.0
	_camera.current = true
	_camera_rig.add_child(_camera)


func initialize_competition(
	map_data: MapData,
	mode_id: int,
	participants: Array,
	custom_rules: Dictionary = {},
	p_local_peer_id: int = 1
) -> void:
	_setup_scene_roots()
	local_peer_id = p_local_peer_id
	spectated_peer_id = local_peer_id
	current_map = map_data if map_data != null else MapData.create_default_race_map()

	mode_controller = _create_mode_controller(mode_id)
	var capped_participants := participants.slice(0, MAX_COMPETITORS)
	if capped_participants.is_empty():
		capped_participants = [{"peer_id": 1, "name": "Player 1", "is_bot": false}]
	mode_controller.setup_mode(capped_participants, custom_rules)

	build_arena_from_map(current_map)
	spawn_competitors(capped_participants)
	is_arena_active = true


func _create_mode_controller(mode_id: int) -> CompetitionModeBase:
	match mode_id:
		D4FConstants.CompetitionMode.RACE:
			return RaceCompetitionMode.new()
		D4FConstants.CompetitionMode.OBSTACLE_SURVIVAL:
			return ObstacleSurvivalMode.new()
		D4FConstants.CompetitionMode.PHYSICS_BATTLE:
			return PhysicsBattleMode.new()
		D4FConstants.CompetitionMode.CUSTOM_CHALLENGE:
			return CustomChallengeMode.new()
		_:
			return RaceCompetitionMode.new()


func build_arena_from_map(map_data: MapData) -> void:
	for child in _geometry_root.get_children():
		child.queue_free()
	_spinning_hazards.clear()
	spawn_transforms.clear()
	checkpoint_positions.clear()

	if map_data == null:
		return

	var has_floor_surface := false
	var raw_checkpoints: Array[Dictionary] = []

	for raw_obj in map_data.objects:
		if not (raw_obj is Dictionary):
			continue
		var obj: Dictionary = raw_obj
		var obj_type := str(obj.get("type", "platform")).to_lower()
		if obj_type in ["platform", "road", "floor", "bridge"]:
			has_floor_surface = true
		if obj_type == "checkpoint":
			raw_checkpoints.append(obj)
		else:
			_build_arena_object(obj, -1)

	raw_checkpoints.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		var pa: Dictionary = a.get("properties", {}) if a.get("properties") is Dictionary else {}
		var pb: Dictionary = b.get("properties", {}) if b.get("properties") is Dictionary else {}
		return int(pa.get("order", 0)) < int(pb.get("order", 0))
	)
	for idx in range(raw_checkpoints.size()):
		var cp_obj := raw_checkpoints[idx]
		checkpoint_positions.append(MapValidator._vec3_from_var(cp_obj.get("position", [0.0, 0.5, 0.0])))
		_build_arena_object(cp_obj, idx + 1)

	for stroke_dict in map_data.terrain_strokes:
		if stroke_dict is Dictionary:
			has_floor_surface = true
			var mesh := MeshExtruder3D.build_terrain_stroke_mesh(stroke_dict)
			var body := StaticBody3D.new()
			var mi := MeshInstance3D.new()
			mi.mesh = mesh
			body.add_child(mi)
			var cs := CollisionShape3D.new()
			cs.shape = MeshExtruder3D.build_terrain_stroke_collision(mesh)
			body.add_child(cs)
			_geometry_root.add_child(body)

	# Ensure a fallback base platform exists if map has no custom floor or terrain
	if not has_floor_surface:
		_create_static_platform(Vector3(0.0, -0.5, 0.0), Vector3.ZERO, Vector3(38.0, 1.0, 38.0), Color(0.22, 0.28, 0.36))

	if spawn_transforms.is_empty():
		spawn_transforms.append(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)))


func _build_arena_object(obj: Dictionary, checkpoint_order: int) -> void:
	var obj_type := str(obj.get("type", "platform")).to_lower()
	var pos := MapValidator._vec3_from_var(obj.get("position", [0.0, 0.0, 0.0]))
	var rot := MapValidator._vec3_from_var(obj.get("rotation", [0.0, 0.0, 0.0]))
	var scl := MapValidator._vec3_from_var(obj.get("scale", [4.0, 1.0, 4.0]), Vector3(4.0, 1.0, 4.0))
	var col := Color.from_string(str(obj.get("color", "#4488cc")), Color(0.27, 0.53, 0.80))

	if obj_type in ["start_spawn", "spawn"]:
		var basis := Basis.from_euler(Vector3(deg_to_rad(rot.x), deg_to_rad(rot.y), deg_to_rad(rot.z)))
		spawn_transforms.append(Transform3D(basis, pos))
		_create_static_platform(pos - Vector3(0.0, 0.25, 0.0), rot, Vector3(maxf(scl.x, 4.0), 0.4, maxf(scl.z, 4.0)), Color(0.2, 0.75, 0.45))
	elif obj_type == "checkpoint":
		_create_checkpoint_trigger(pos, rot, scl, checkpoint_order, col)
	elif obj_type in ["finish_line", "finish", "goal"]:
		_create_finish_line_trigger(pos, rot, scl, col)
	elif MapValidator._is_hazard_type(obj_type):
		_create_hazard_node(obj_type, pos, rot, scl, col)
	else:
		_create_static_platform(pos, rot, scl, col)


func _create_static_platform(pos: Vector3, rot_deg: Vector3, scl: Vector3, col: Color) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.position = pos
	body.rotation_degrees = rot_deg

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = scl
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.6
	bm.material = mat
	mi.mesh = bm
	body.add_child(mi)

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = scl
	cs.shape = bs
	body.add_child(cs)

	_geometry_root.add_child(body)
	return body


func _create_checkpoint_trigger(pos: Vector3, rot_deg: Vector3, scl: Vector3, order_idx: int, col: Color) -> void:
	var area := Area3D.new()
	area.name = "Checkpoint_%d" % order_idx
	area.position = pos
	area.rotation_degrees = rot_deg

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = scl.max(Vector3(4.5, 3.5, 1.5))
	cs.shape = bs
	area.add_child(cs)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(col.r, col.g, col.b, 0.28)
	mat.emission_enabled = true
	mat.emission = col * 0.5
	bm.material = mat
	mi.mesh = bm
	area.add_child(mi)

	area.body_entered.connect(func(body: Node3D) -> void:
		if body != null and body.is_in_group("competitors"):
			_on_competitor_touched_checkpoint(body, order_idx)
	)
	_geometry_root.add_child(area)


func _create_finish_line_trigger(pos: Vector3, rot_deg: Vector3, scl: Vector3, col: Color) -> void:
	var area := Area3D.new()
	area.name = "FinishLineTrigger"
	area.position = pos
	area.rotation_degrees = rot_deg

	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = scl.max(Vector3(6.0, 4.0, 2.0))
	cs.shape = bs
	area.add_child(cs)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(1.0, 0.85, 0.2, 0.38)
	mat.emission_enabled = true
	mat.emission = col
	bm.material = mat
	mi.mesh = bm
	area.add_child(mi)

	area.body_entered.connect(func(body: Node3D) -> void:
		if body != null and body.is_in_group("competitors"):
			_on_competitor_touched_finish(body)
	)
	_geometry_root.add_child(area)


func _create_hazard_node(hazard_type: String, pos: Vector3, rot_deg: Vector3, scl: Vector3, col: Color) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation_degrees = rot_deg

	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = scl.max(Vector3(1.5, 1.0, 1.5))
	cs.shape = bs
	area.add_child(cs)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = bs.size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.95, 0.25, 0.25) if col == Color.WHITE else col
	mat.emission_enabled = true
	mat.emission = mat.albedo_color * 0.35
	bm.material = mat
	mi.mesh = bm
	area.add_child(mi)

	area.body_entered.connect(func(body: Node3D) -> void:
		if body != null and body.is_in_group("competitors"):
			var push_dir := (body.global_position - root.global_position).normalized()
			push_dir.y = 0.35
			var impulse := push_dir.normalized() * 16.0
			if hazard_type in ["lava", "spike"]:
				if body.has_method("trigger_elimination"):
					body.call("trigger_elimination", hazard_type)
			elif body.has_method("apply_knockback"):
				body.call("apply_knockback", impulse, -1)
			elif body.has_method("apply_collision_bump"):
				body.call("apply_collision_bump", impulse, -1)
	)

	root.add_child(area)
	_geometry_root.add_child(root)
	if hazard_type in ["spinner", "wrecking_ball", "hazard"]:
		_spinning_hazards.append(root)


func spawn_competitors(participants: Array) -> void:
	for child in _competitors_root.get_children():
		child.queue_free()
	competitors.clear()

	var base_spawn := spawn_transforms[0] if not spawn_transforms.is_empty() else Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0))

	for i in range(mini(participants.size(), MAX_COMPETITORS)):
		var entry: Variant = participants[i]
		var pid := i + 1
		var pname := "Player %d" % pid
		var is_bot := false
		var creation: CreationData = null

		if entry is Dictionary:
			pid = int(entry.get("peer_id", entry.get("id", pid)))
			pname = str(entry.get("name", pname))
			is_bot = bool(entry.get("is_bot", false))
			if entry.get("creation") is CreationData:
				creation = entry["creation"]
		elif entry is int:
			pid = entry

		var use_vehicle := mode_controller.use_vehicles if mode_controller != null else false
		if creation != null:
			use_vehicle = (creation.creation_type == D4FConstants.CreationType.VEHICLE)
		else:
			creation = CreationData.create_default_vehicle() if use_vehicle else CreationData.create_default_stickman()

		var comp_node: CharacterBody3D
		if use_vehicle:
			var veh := PlayableVehicle3D.new()
			veh.is_local_controlled = (pid == local_peer_id and not is_bot)
			veh.is_bot = is_bot
			veh.setup_from_creation(creation, pid, pname)
			veh.eliminated.connect(_on_competitor_eliminated_signal)
			comp_node = veh
		else:
			var ch := PlayableCharacter3D.new()
			ch.is_local_controlled = (pid == local_peer_id and not is_bot)
			ch.is_bot = is_bot
			ch.setup_from_creation(creation, pid, pname)
			ch.eliminated.connect(_on_competitor_eliminated_signal)
			comp_node = ch

		if mode_controller is CustomChallengeMode:
			comp_node.set("gravity_scale", (mode_controller as CustomChallengeMode).gravity_scale)

		# Grid offset around spawn point so up to 8 competitors don't overlap on start
		var row := int(i / 4)
		var col_idx := i % 4
		var offset := Vector3((col_idx - 1.5) * 2.2, 0.8, row * 2.4)
		comp_node.global_position = base_spawn.origin + offset
		_competitors_root.add_child(comp_node)
		competitors[pid] = comp_node


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		var mm := event as InputEventMouseMotion
		_cam_yaw -= mm.relative.x * 0.006
		_cam_pitch = clampf(_cam_pitch - mm.relative.y * 0.005, -1.1, -0.08)
	elif event is InputEventKey and event.pressed and not event.echo:
		var ke := event as InputEventKey
		if ke.keycode == KEY_TAB:
			cycle_spectator_target()


func _physics_process(delta: float) -> void:
	if not is_arena_active or mode_controller == null:
		return

	# Spin dynamic obstacles
	for spinner in _spinning_hazards:
		if is_instance_valid(spinner):
			spinner.rotate_y(2.2 * delta)

	# Drive local player & AI bots
	for pid in competitors.keys():
		var node: Node3D = competitors[pid]
		if node == null or not is_instance_valid(node) or bool(node.get("is_eliminated")):
			continue

		if bool(node.get("is_local_controlled")):
			_apply_local_player_input(node, delta)
		elif bool(node.get("is_bot")):
			var bot_in := bot_controller.compute_bot_input(node, current_map, competitors, mode_controller.mode_id, delta)
			if node is PlayableVehicle3D:
				(node as PlayableVehicle3D).apply_vehicle_input(
					float(bot_in["throttle"]),
					float(bot_in["steering"]),
					bool(bot_in["brake"]),
					bool(bot_in["boost"]),
					delta
				)
			elif node is PlayableCharacter3D:
				(node as PlayableCharacter3D).apply_movement_input(
					bot_in["move_dir"] as Vector2,
					bool(bot_in["jump"]),
					bool(bot_in["shove"]),
					delta
				)

	var snap := mode_controller.tick_mode(delta, competitors)
	match_state_updated.emit(snap)

	if mode_controller.is_match_over:
		is_arena_active = false
		var final_rankings := mode_controller.compute_rankings()
		match_finished.emit(final_rankings)

	_update_follow_camera(delta)


func _apply_local_player_input(node: Node3D, delta: float) -> void:
	var raw_x := Input.get_axis("move_left", "move_right")
	var raw_y := Input.get_axis("move_forward", "move_backward")
	var jump_pressed := Input.is_action_just_pressed("jump")
	var action_pressed := Input.is_action_just_pressed("action_primary") or Input.is_key_pressed(KEY_SHIFT)

	if node is PlayableVehicle3D:
		var throttle := -raw_y
		var steer := -raw_x
		var brake := Input.is_key_pressed(KEY_SPACE)
		(node as PlayableVehicle3D).apply_vehicle_input(throttle, steer, brake, action_pressed, delta)
	elif node is PlayableCharacter3D:
		var cam_basis := Basis(Vector3.UP, _cam_yaw)
		var move_3d := cam_basis * Vector3(raw_x, 0.0, raw_y)
		var move_2d := Vector2(move_3d.x, move_3d.z)
		(node as PlayableCharacter3D).apply_movement_input(move_2d, jump_pressed, action_pressed, delta)


func _on_competitor_touched_checkpoint(body: Node3D, order_idx: int) -> void:
	var pid := int(body.get("peer_id"))
	var cur_cp := int(body.get("current_checkpoint"))
	if order_idx == cur_cp + 1:
		body.set("current_checkpoint", order_idx)
		if mode_controller != null:
			mode_controller.on_player_checkpoint(pid, order_idx, checkpoint_positions.size())
		competitor_checkpoint.emit(pid, order_idx)


func _on_competitor_touched_finish(body: Node3D) -> void:
	var pid := int(body.get("peer_id"))
	var cur_cp := int(body.get("current_checkpoint"))
	if cur_cp >= checkpoint_positions.size():
		if mode_controller != null:
			mode_controller.on_player_finished(pid)
		competitor_finished.emit(pid)


func _on_competitor_eliminated_signal(peer_id: int, killer_peer_id: int, reason: String) -> void:
	if mode_controller != null:
		mode_controller.on_player_eliminated(peer_id, killer_peer_id, reason)
	competitor_eliminated.emit(peer_id, killer_peer_id, reason)

	var still_has_lives := false
	if mode_controller != null and mode_controller.allow_respawn:
		still_has_lives = not mode_controller.eliminated_peers.has(peer_id)

	if still_has_lives and competitors.has(peer_id):
		var node: Node3D = competitors[peer_id]
		var respawn_pos := _get_respawn_position_for_competitor(node)
		if node.has_method("respawn_at"):
			node.call_deferred("respawn_at", respawn_pos)
	elif peer_id == spectated_peer_id:
		cycle_spectator_target()


func _get_respawn_position_for_competitor(node: Node3D) -> Vector3:
	var cp_idx := int(node.get("current_checkpoint")) - 1
	if cp_idx >= 0 and cp_idx < checkpoint_positions.size():
		return checkpoint_positions[cp_idx]
	if not spawn_transforms.is_empty():
		return spawn_transforms[0].origin
	return Vector3(0.0, 2.0, 0.0)


func cycle_spectator_target() -> void:
	var alive_ids: Array[int] = []
	for pid in competitors.keys():
		var n: Node3D = competitors[pid]
		if n != null and is_instance_valid(n) and not bool(n.get("is_eliminated")):
			alive_ids.append(pid)
	if alive_ids.is_empty():
		return
	var cur_idx := alive_ids.find(spectated_peer_id)
	spectated_peer_id = alive_ids[(cur_idx + 1) % alive_ids.size()]


func _update_follow_camera(delta: float) -> void:
	if _camera_rig == null or _camera == null:
		return
	var target_node: Node3D = competitors.get(spectated_peer_id, null)
	if target_node == null or not is_instance_valid(target_node):
		return

	var target_pos := target_node.global_position + Vector3(0.0, 1.35, 0.0)
	_camera_rig.global_position = _camera_rig.global_position.lerp(target_pos, minf(1.0, 10.0 * delta))

	var rot_basis := Basis.from_euler(Vector3(_cam_pitch, _cam_yaw, 0.0))
	var cam_offset := rot_basis * Vector3(0.0, 0.0, _cam_distance)
	_camera.global_position = _camera_rig.global_position + cam_offset
	_camera.look_at(_camera_rig.global_position, Vector3.UP)
