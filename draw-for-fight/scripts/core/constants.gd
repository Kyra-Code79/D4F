class_name D4FConstants
extends RefCounted

const GAME_TITLE := "Draw for Fight"
const GAME_VERSION := "1.0.0"
const PROTOCOL_VERSION := "D4F_NET_V1"
const DEFAULT_PORT := 24800
const LAN_BROADCAST_PORT := 24801
const MAX_PLAYERS := 8
const MIN_PLAYERS := 1
const MAX_STROKES_PER_CREATION := 64
const MAX_POINTS_PER_STROKE := 128
const MAX_VERTICES_PER_MESH := 2048
const MAX_MAP_OBJECTS := 200
const MAX_OBJECTS_PER_PLAYER := 40
const MAX_PACKET_BYTES := 65536
const DEFAULT_PREP_TIME_SEC := 90.0
const DEFAULT_MATCH_TIME_SEC := 180.0
const ARENA_ELIMINATION_Y := -18.0

enum GameState {
	MAIN_MENU,
	CHARACTER_WORKSHOP,
	VEHICLE_WORKSHOP,
	CREATE_LOBBY,
	JOIN_LOBBY,
	WAITING_ROOM,
	MAP_EDITOR,
	COMPETITION_PREP,
	ARENA_COMPETITION,
	RESULTS_RANKINGS,
	SETTINGS
}

enum CompetitionMode {
	RACE,
	OBSTACLE_SURVIVAL,
	PHYSICS_BATTLE,
	CUSTOM_CHALLENGE
}

enum CreationType {
	CHARACTER,
	VEHICLE
}

const ALLOWED_MAP_OBJECT_TYPES: Array[String] = [
	"start_spawn",
	"finish_line",
	"checkpoint",
	"ramp",
	"platform",
	"wall",
	"spinner",
	"bumper",
	"hazard_zone",
	"boost_pad",
	"pillar",
	"bridge"
]

const ALLOWED_SURFACE_TYPES: Array[String] = [
	"road",
	"platform",
	"ice",
	"bouncy",
	"boost",
	"hazard"
]

static func mode_to_string(mode: int) -> String:
	match mode:
		CompetitionMode.RACE:
			return "Race"
		CompetitionMode.OBSTACLE_SURVIVAL:
			return "Obstacle Survival"
		CompetitionMode.PHYSICS_BATTLE:
			return "Physics Battle"
		CompetitionMode.CUSTOM_CHALLENGE:
			return "Custom Challenge"
		_:
			return "Unknown Mode"

static func state_to_string(state: int) -> String:
	match state:
		GameState.MAIN_MENU:
			return "Main Menu"
		GameState.CHARACTER_WORKSHOP:
			return "Character Workshop"
		GameState.VEHICLE_WORKSHOP:
			return "Vehicle Workshop"
		GameState.CREATE_LOBBY:
			return "Create Lobby"
		GameState.JOIN_LOBBY:
			return "Join Lobby"
		GameState.WAITING_ROOM:
			return "Waiting Room"
		GameState.MAP_EDITOR:
			return "Map Editor"
		GameState.COMPETITION_PREP:
			return "Competition Prep"
		GameState.ARENA_COMPETITION:
			return "Arena Competition"
		GameState.RESULTS_RANKINGS:
			return "Results & Rankings"
		GameState.SETTINGS:
			return "Settings"
		_:
			return "Unknown State"

static func creation_type_to_string(creation_type: int) -> String:
	match creation_type:
		CreationType.CHARACTER:
			return "Character"
		CreationType.VEHICLE:
			return "Vehicle"
		_:
			return "Unknown"
