extends Node
## Autoload Singleton: GameManager
## Central game state machine, screen router, persistent player profile,
## and creation/map storage manager (`user://`).

signal game_state_changed(old_state: int, new_state: int, scene_path: String)
signal profile_updated(profile: Dictionary)
signal active_creation_changed(creation_type: int, creation: CreationData)
signal active_map_changed(map_data: MapData)
signal toast_requested(message: String, severity: String)

const PROFILE_PATH := "user://profile.json"
const CREATIONS_DIR := "user://creations"
const MAPS_DIR := "user://maps"

const SCREEN_SCENE_PATHS: Dictionary = {
	D4FConstants.GameState.MAIN_MENU: "res://scenes/menus/main_menu.tscn",
	D4FConstants.GameState.CHARACTER_WORKSHOP: "res://scenes/characters/character_workshop.tscn",
	D4FConstants.GameState.VEHICLE_WORKSHOP: "res://scenes/vehicles/vehicle_workshop.tscn",
	D4FConstants.GameState.CREATE_LOBBY: "res://scenes/lobby/create_lobby.tscn",
	D4FConstants.GameState.JOIN_LOBBY: "res://scenes/lobby/join_lobby.tscn",
	D4FConstants.GameState.WAITING_ROOM: "res://scenes/lobby/waiting_room.tscn",
	D4FConstants.GameState.MAP_EDITOR: "res://scenes/map_editor/map_editor.tscn",
	D4FConstants.GameState.COMPETITION_PREP: "res://scenes/competition/competition_prep.tscn",
	D4FConstants.GameState.ARENA_COMPETITION: "res://scenes/arenas/competition_arena.tscn",
	D4FConstants.GameState.RESULTS_RANKINGS: "res://scenes/competition/results_rankings.tscn",
	D4FConstants.GameState.SETTINGS: "res://scenes/menus/settings_menu.tscn"
}

var current_state: int = D4FConstants.GameState.MAIN_MENU
var previous_state: int = D4FConstants.GameState.MAIN_MENU

var player_profile: Dictionary = {
	"player_id": "local_player",
	"player_name": "SketchChampion",
	"career_points": 0,
	"matches_played": 0,
	"matches_won": 0,
	"eliminations_total": 0,
	"rank_title": "Rookie Sketcher"
}

var active_character: CreationData = null
var active_vehicle: CreationData = null
var active_map: MapData = null
var selected_mode: int = D4FConstants.CompetitionMode.RACE
var current_lobby_config: Dictionary = {
	"lobby_id": "LOBBY-101",
	"lobby_name": "D4F Arena #1",
	"port": 24800,
	"invite_code": "D4F-2026",
	"max_players": 8,
	"prep_time_sec": 90.0,
	"match_time_sec": 180.0,
	"bot_fill_count": 3
}

func _ready() -> void:
	_ensure_user_directories()
	load_profile()
	active_character = CreationData.create_default_stickman("Hero Stickman", "#33aaff")
	active_vehicle = CreationData.create_default_vehicle("Turbo Sketch", "#ff6622")
	active_map = MapData.create_default_arena(selected_mode)

func _ensure_user_directories() -> void:
	DirAccess.make_dir_recursive_absolute(CREATIONS_DIR)
	DirAccess.make_dir_recursive_absolute(MAPS_DIR)

func navigate_to(new_state: int) -> String:
	if not SCREEN_SCENE_PATHS.has(new_state):
		push_warning("GameManager: Unknown GameState " + str(new_state))
		return ""
	previous_state = current_state
	current_state = new_state
	var path: String = SCREEN_SCENE_PATHS[new_state]
	if has_node("/root/AudioManager"):
		get_node("/root/AudioManager").play_sfx("ui_click")
	game_state_changed.emit(previous_state, current_state, path)
	return path

func navigate_back() -> String:
	return navigate_to(previous_state)

func notify_toast(message: String, severity: String = "info") -> void:
	toast_requested.emit(message, severity)

func get_active_creation_for_mode(mode: int = -1) -> CreationData:
	var m := selected_mode if mode < 0 else mode
	if m == D4FConstants.CompetitionMode.RACE:
		return active_vehicle if active_vehicle != null else CreationData.create_default_vehicle()
	return active_character if active_character != null else CreationData.create_default_stickman()

func set_active_creation(creation: CreationData) -> void:
	if creation == null:
		return
	if creation.creation_type == D4FConstants.CreationType.VEHICLE:
		active_vehicle = creation
	else:
		active_character = creation
	active_creation_changed.emit(creation.creation_type, creation)

func save_creation_to_disk(creation: CreationData) -> bool:
	if creation == null:
		return false
	_ensure_user_directories()
	var safe_id := creation.creation_id.validate_filename()
	if safe_id.is_empty():
		safe_id = "creation_" + str(Time.get_unix_time_from_system())
	var file_path := CREATIONS_DIR + "/" + safe_id + ".json"
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(D4FSerializer.to_json_safe(creation.to_dict()))
	f.close()
	return true

func load_creation_from_disk(file_name: String) -> CreationData:
	var full_path := file_name if file_name.begins_with("user://") or file_name.begins_with("res://") else (CREATIONS_DIR + "/" + file_name)
	if not FileAccess.file_exists(full_path):
		return null
	var f := FileAccess.open(full_path, FileAccess.READ)
	if f == null:
		return null
	var text := f.get_as_text()
	f.close()
	var parsed: Variant = D4FSerializer.from_json_safe(text)
	if parsed is Dictionary:
		return CreationData.from_dict(parsed)
	return null

func list_saved_creations() -> Array[String]:
	_ensure_user_directories()
	var list: Array[String] = []
	var dir := DirAccess.open(CREATIONS_DIR)
	if dir == null:
		return list
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".json"):
			list.append(fname)
		fname = dir.get_next()
	dir.list_dir_end()
	return list

func save_map_to_disk(map_data: MapData) -> bool:
	if map_data == null:
		return false
	_ensure_user_directories()
	var safe_id := map_data.map_id.validate_filename()
	if safe_id.is_empty():
		safe_id = "map_" + str(Time.get_unix_time_from_system())
	var file_path := MAPS_DIR + "/" + safe_id + ".json"
	var f := FileAccess.open(file_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(D4FSerializer.to_json_safe(map_data.to_dict()))
	f.close()
	return true

func load_map_from_disk(file_name: String) -> MapData:
	var full_path := file_name if file_name.begins_with("user://") or file_name.begins_with("res://") else (MAPS_DIR + "/" + file_name)
	if not FileAccess.file_exists(full_path):
		return null
	var f := FileAccess.open(full_path, FileAccess.READ)
	if f == null:
		return null
	var parsed: Variant = D4FSerializer.from_json_safe(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		return MapData.from_dict(parsed)
	return null

func record_match_outcome(points_earned: int, won_match: bool, eliminations: int = 0) -> void:
	player_profile["matches_played"] = int(player_profile.get("matches_played", 0)) + 1
	if won_match:
		player_profile["matches_won"] = int(player_profile.get("matches_won", 0)) + 1
	player_profile["career_points"] = int(player_profile.get("career_points", 0)) + maxi(0, points_earned)
	player_profile["eliminations_total"] = int(player_profile.get("eliminations_total", 0)) + maxi(0, eliminations)
	player_profile["rank_title"] = _compute_rank_title(int(player_profile["career_points"]))
	save_profile()
	profile_updated.emit(player_profile)

func _compute_rank_title(pts: int) -> String:
	if pts >= 5000:
		return "Grandmaster Architect"
	elif pts >= 2500:
		return "Diamond Illustrator"
	elif pts >= 1200:
		return "Gold Draftsman"
	elif pts >= 500:
		return "Silver Inkling"
	elif pts >= 150:
		return "Bronze Contender"
	return "Rookie Sketcher"

func save_profile() -> bool:
	var f := FileAccess.open(PROFILE_PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(D4FSerializer.to_json_safe(player_profile))
	f.close()
	return true

func load_profile() -> bool:
	if not FileAccess.file_exists(PROFILE_PATH):
		return false
	var f := FileAccess.open(PROFILE_PATH, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = D4FSerializer.from_json_safe(f.get_as_text())
	f.close()
	if parsed is Dictionary:
		for k in parsed.keys():
			player_profile[k] = parsed[k]
		return true
	return false
