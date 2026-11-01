extends Node
## Autoload Singleton: SettingsManager
## Manages graphics, audio, controls, network, and optional AI settings.
## Optimized for low-to-mid-range Windows 10/11 x64 PCs.

signal settings_changed(section: String, key: String, value: Variant)
signal graphics_preset_applied(preset_name: String)

const SETTINGS_PATH := "user://settings.cfg"

var _settings: Dictionary = {
	"graphics": {
		"quality_preset": "medium", # "low", "medium", "high"
		"fullscreen": false,
		"vsync": true,
		"max_fps": 60,
		"msaa_3d": 1, # 0 = Disabled, 1 = 2x, 2 = 4x
		"shadow_enabled": true,
		"mesh_vertex_limit": 2048,
		"render_scale": 1.0
	},
	"audio": {
		"master_volume": 0.85,
		"sfx_volume": 0.90,
		"music_volume": 0.70,
		"mute_when_unfocused": true
	},
	"controls": {
		"mouse_sensitivity": 0.35,
		"invert_y": false,
		"camera_distance": 8.5
	},
	"network": {
		"player_name": "Sketcher",
		"default_port": 24800,
		"enable_lan_broadcast": true,
		"enable_relay_fallback": false,
		"relay_endpoint": "wss://relay.drawforfight.example/v1",
		"interpolation_delay_ms": 80
	},
	"ai": {
		"enable_design_suggestions": true,
		"enable_map_validation_hints": true,
		"enable_bot_competitors": true,
		"default_bot_fill_count": 3,
		"external_ai_provider": "offline_heuristic" # Never embeds private API keys
	}
}

func _ready() -> void:
	load_settings()
	apply_all_settings()

func get_setting(section: String, key: String, default_val: Variant = null) -> Variant:
	if _settings.has(section) and _settings[section].has(key):
		return _settings[section][key]
	return default_val

func set_setting(section: String, key: String, value: Variant, auto_save: bool = true) -> void:
	if not _settings.has(section):
		_settings[section] = {}
	_settings[section][key] = value
	if section == "graphics":
		_apply_graphics_settings()
	elif section == "audio":
		_apply_audio_settings()
	settings_changed.emit(section, key, value)
	if auto_save:
		save_settings()

func apply_graphics_preset(preset: String) -> void:
	var p := preset.to_lower()
	_settings["graphics"]["quality_preset"] = p
	match p:
		"low":
			_settings["graphics"]["msaa_3d"] = 0
			_settings["graphics"]["shadow_enabled"] = false
			_settings["graphics"]["mesh_vertex_limit"] = 1024
			_settings["graphics"]["render_scale"] = 0.85
			_settings["graphics"]["max_fps"] = 60
		"high":
			_settings["graphics"]["msaa_3d"] = 2
			_settings["graphics"]["shadow_enabled"] = true
			_settings["graphics"]["mesh_vertex_limit"] = 2048
			_settings["graphics"]["render_scale"] = 1.0
			_settings["graphics"]["max_fps"] = 120
		_: # "medium" default for mid-range PCs
			_settings["graphics"]["msaa_3d"] = 1
			_settings["graphics"]["shadow_enabled"] = true
			_settings["graphics"]["mesh_vertex_limit"] = 1536
			_settings["graphics"]["render_scale"] = 1.0
			_settings["graphics"]["max_fps"] = 60
	_apply_graphics_settings()
	graphics_preset_applied.emit(p)
	save_settings()

func apply_all_settings() -> void:
	_apply_graphics_settings()
	_apply_audio_settings()

func _apply_graphics_settings() -> void:
	var g: Dictionary = _settings.get("graphics", {})
	Engine.max_fps = int(g.get("max_fps", 60))
	var vp := get_viewport()
	if vp:
		var msaa_idx := clampi(int(g.get("msaa_3d", 1)), 0, 3)
		vp.msaa_3d = msaa_idx as Viewport.MSAA
		vp.scaling_3d_scale = clampf(float(g.get("render_scale", 1.0)), 0.5, 1.0)
	if DisplayServer.get_name() != "headless":
		var vsync_on := bool(g.get("vsync", true))
		DisplayServer.window_set_vsync_mode(
			DisplayServer.VSYNC_ENABLED if vsync_on else DisplayServer.VSYNC_DISABLED
		)
		var fullscreen := bool(g.get("fullscreen", false))
		var current_mode := DisplayServer.window_get_mode()
		if fullscreen and current_mode != DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
		elif not fullscreen and current_mode == DisplayServer.WINDOW_MODE_FULLSCREEN:
			DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)

func _apply_audio_settings() -> void:
	var a: Dictionary = _settings.get("audio", {})
	var master_vol := clampf(float(a.get("master_volume", 0.85)), 0.0, 1.0)
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx >= 0:
		AudioServer.set_bus_volume_db(master_idx, linear_to_db(maxf(master_vol, 0.0001)))
		AudioServer.set_bus_mute(master_idx, master_vol <= 0.001)

func save_settings() -> bool:
	var cfg := ConfigFile.new()
	for section in _settings.keys():
		var sec_dict: Dictionary = _settings[section]
		for key in sec_dict.keys():
			cfg.set_value(section, key, sec_dict[key])
	var err := cfg.save(SETTINGS_PATH)
	return err == OK

func load_settings() -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		return false
	for section in cfg.get_sections():
		if not _settings.has(section):
			_settings[section] = {}
		for key in cfg.get_section_keys(section):
			_settings[section][key] = cfg.get_value(section, key)
	return true

func get_all_settings() -> Dictionary:
	return _settings.duplicate(true)
