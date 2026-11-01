extends Node
## Autoload Singleton: AIAssistantManager
## Provides optional, modular AI-assisted features:
## 1. Character design suggestions
## 2. Vehicle design suggestions
## 3. Map design & obstacle placement suggestions
## 4. Automatic map validation assistance & auto-repair
## 5. NPC competitor generation
##
## SECURITY POLICY: Never embeds private API keys in the executable.
## Operates 100% offline via deterministic geometry heuristics by default.

signal suggestion_ready(category: String, result: Dictionary)

const BOT_NAMES: Array[String] = [
	"InkBot_Alpha",
	"DoodleKnight",
	"SketchVortex",
	"VectorValkyrie",
	"ChalkCharger",
	"GraphiteGhost",
	"PixelPhantom"
]

const BOT_COLORS: Array[String] = [
	"#ff4757", "#2ed573", "#1e90ff", "#ffa502",
	"#a55eea", "#00d2d3", "#ff6b81"
]

func is_ai_enabled(feature_key: String = "enable_design_suggestions") -> bool:
	if has_node("/root/SettingsManager"):
		return bool(get_node("/root/SettingsManager").get_setting("ai", feature_key, true))
	return true

## 1. Character Design Suggestions
func suggest_character_improvements(creation: CreationData) -> Dictionary:
	var suggestions: Array[String] = []
	var recommended_strokes: Array = []
	if creation == null or creation.strokes.is_empty():
		suggestions.append("Canvas is empty. Start with a central torso line from (256, 170) to (256, 310), then add a head circle and four limbs.")
		return {
			"summary": "Add core Stickman structure",
			"suggestions": suggestions,
			"score_rating": 20,
			"recommended_strokes": recommended_strokes
		}

	var tags_found: Dictionary = {}
	var total_points := 0
	var min_y := 9999.0
	var max_y := -9999.0
	for s in creation.strokes:
		var tag := String(s.get("part_tag", "body"))
		tags_found[tag] = true
		var pts: Array = s.get("points", [])
		total_points += pts.size()
		for p in pts:
			if p is Array and p.size() >= 2:
				min_y = minf(min_y, float(p[1]))
				max_y = maxf(max_y, float(p[1]))
			elif p is Vector2:
				min_y = minf(min_y, p.y)
				max_y = maxf(max_y, p.y)

	var height_span := maxf(0.0, max_y - min_y)
	var rating := 70
	if height_span < 120.0:
		suggestions.append("Your character is quite compact vertically. Extending legs downward improves ground stride and jump visual clarity.")
		rating -= 10
	else:
		suggestions.append("Good vertical proportion (" + str(int(height_span)) + "px span) for stable 3D extrusion.")
		rating += 10

	if creation.strokes.size() < 4:
		suggestions.append("Add distinct arm and leg strokes so your stickman has wider lateral balance during Physics Battle collisions.")
		recommended_strokes.append({
			"part_tag": "left_arm",
			"color": "#ffd32a",
			"thickness": 8.0,
			"points": [[256.0, 200.0], [190.0, 235.0], [165.0, 255.0]]
		})
		recommended_strokes.append({
			"part_tag": "right_arm",
			"color": "#ffd32a",
			"thickness": 8.0,
			"points": [[256.0, 200.0], [322.0, 235.0], [347.0, 255.0]]
		})
	else:
		rating += 10

	var mass := float(creation.physics_stats.get("mass", 70.0))
	if mass > 105.0:
		suggestions.append("Heavy ink build (" + str(int(mass)) + " kg): High knockback resistance for Physics Battle, but slower acceleration in Race mode.")
	elif mass < 55.0:
		suggestions.append("Lightweight build (" + str(int(mass)) + " kg): Fast agility for Obstacle Survival, but vulnerable to heavy shoves.")
	else:
		suggestions.append("Balanced weight class (" + str(int(mass)) + " kg): Well-suited for all competition modes.")

	var res := {
		"summary": "Character Balance Rating: " + str(clampi(rating, 0, 100)) + "/100",
		"suggestions": suggestions,
		"score_rating": clampi(rating, 0, 100),
		"recommended_strokes": recommended_strokes
	}
	suggestion_ready.emit("character", res)
	return res

## 2. Vehicle Design Suggestions
func suggest_vehicle_improvements(creation: CreationData) -> Dictionary:
	var suggestions: Array[String] = []
	var recommended_strokes: Array = []
	if creation == null or creation.strokes.is_empty():
		suggestions.append("Draw a low horizontal chassis between X=120 and X=390, plus two circular wheels near the bottom guide markers.")
		return {
			"summary": "Add chassis and wheels",
			"suggestions": suggestions,
			"score_rating": 25,
			"recommended_strokes": recommended_strokes
		}

	var min_x := 9999.0
	var max_x := -9999.0
	var has_wheels := false
	for s in creation.strokes:
		var tag := String(s.get("part_tag", "body"))
		if tag.contains("wheel"):
			has_wheels = true
		for p in s.get("points", []):
			var px: float = float(p[0]) if (p is Array and p.size() >= 1) else (p.x if p is Vector2 else 256.0)
			min_x = minf(min_x, px)
			max_x = maxf(max_x, px)

	var wheelbase := maxf(0.0, max_x - min_x)
	var rating := 75
	if wheelbase < 160.0:
		suggestions.append("Short wheelbase (" + str(int(wheelbase)) + "px): Lengthening the chassis reduces pitch flipping on steep ramps.")
		rating -= 12
	else:
		suggestions.append("Wide wheelbase (" + str(int(wheelbase)) + "px): Strong stability when landing off high ramps.")
		rating += 10

	if not has_wheels:
		suggestions.append("Tip: Tag or draw front and rear wheels in the lower wheel zones for animated 3D wheel rotation.")
		recommended_strokes.append({
			"part_tag": "front_wheel",
			"color": "#2f3542",
			"thickness": 10.0,
			"points": [[340.0, 340.0], [360.0, 340.0], [360.0, 360.0], [340.0, 360.0], [340.0, 340.0]]
		})

	var res := {
		"summary": "Vehicle Stability Rating: " + str(clampi(rating, 0, 100)) + "/100",
		"suggestions": suggestions,
		"score_rating": clampi(rating, 0, 100),
		"recommended_strokes": recommended_strokes
	}
	suggestion_ready.emit("vehicle", res)
	return res

## 3. Map Design & Obstacle Placement Suggestions
func suggest_map_obstacles(map_data: MapData) -> Dictionary:
	var suggestions: Array[String] = []
	var proposed_objects: Array[Dictionary] = []
	if map_data == null:
		return {"suggestions": ["Create or load a map first."], "proposed_objects": []}

	var counts: Dictionary = {}
	for obj in map_data.objects:
		var t := String(obj.get("type", "platform"))
		counts[t] = int(counts.get(t, 0)) + 1

	if int(counts.get("checkpoint", 0)) < 2:
		suggestions.append("Add at least 2 Checkpoints between Start and Finish to guide players and provide fair respawn anchors.")
		proposed_objects.append({
			"type": "checkpoint",
			"position": [0.0, 1.0, -25.0],
			"rotation": [0.0, 0.0, 0.0],
			"scale": [8.0, 4.0, 1.5],
			"color": "#2ed573",
			"properties": {"checkpoint_index": int(counts.get("checkpoint", 0)) + 1}
		})

	if int(counts.get("ramp", 0)) < 2:
		suggestions.append("Place angled Ramps before elevated platforms or hazard gaps to create high-risk shortcut jumps.")
		proposed_objects.append({
			"type": "ramp",
			"position": [0.0, 0.5, -15.0],
			"rotation": [18.0, 0.0, 0.0],
			"scale": [6.0, 1.5, 8.0],
			"color": "#ffa502",
			"properties": {"boost": 1.2}
		})

	if int(counts.get("obstacle_spinner", 0)) == 0:
		suggestions.append("Add a rotating Obstacle Spinner in the mid-section to test timing and physics knockback recovery.")
		proposed_objects.append({
			"type": "obstacle_spinner",
			"position": [0.0, 1.4, -35.0],
			"rotation": [0.0, 0.0, 0.0],
			"scale": [7.0, 1.2, 1.2],
			"color": "#ff4757",
			"properties": {"spin_speed": 2.4}
		})

	var res := {
		"suggestions": suggestions,
		"proposed_objects": proposed_objects
	}
	suggestion_ready.emit("map_design", res)
	return res

## 4. Automatic Map Validation Assistance & Auto-Fix
func assist_map_validation(map_data: MapData, validation_report: Dictionary) -> Dictionary:
	var fixes_applied: Array[String] = []
	if map_data == null:
		return {"fixed": false, "fixes_applied": fixes_applied}

	var has_spawn := false
	var has_finish := false
	for obj in map_data.objects:
		var t := String(obj.get("type", ""))
		if t == "start_spawn":
			has_spawn = true
		elif t == "finish_line":
			has_finish = true

	if not has_spawn:
		map_data.add_object({
			"type": "start_spawn",
			"position": [0.0, 1.0, 35.0],
			"rotation": [0.0, 0.0, 0.0],
			"scale": [12.0, 1.0, 6.0],
			"color": "#1e90ff"
		}, 1, true)
		fixes_applied.append("Added missing Start Spawn pad at (0, 1, 35).")

	if not has_finish and map_data.target_mode == D4FConstants.CompetitionMode.RACE:
		map_data.add_object({
			"type": "finish_line",
			"position": [0.0, 1.0, -55.0],
			"rotation": [0.0, 0.0, 0.0],
			"scale": [12.0, 4.0, 2.0],
			"color": "#ffd32a"
		}, 1, true)
		fixes_applied.append("Added missing Finish Line arch at (0, 1, -55).")

	return {
		"fixed": not fixes_applied.is_empty(),
		"fixes_applied": fixes_applied,
		"previous_errors": validation_report.get("errors", [])
	}

## 5. Generate NPC Bot Competitor Profile
func create_bot_participant(bot_index: int, use_vehicle: bool = false) -> Dictionary:
	var idx := posmod(bot_index, BOT_NAMES.size())
	var b_name := BOT_NAMES[idx]
	var b_color := BOT_COLORS[idx]
	var creation: CreationData
	if use_vehicle:
		creation = CreationData.create_default_vehicle(b_name + " Kart", b_color)
	else:
		creation = CreationData.create_default_stickman(b_name + " Fighter", b_color)
	return {
		"id": 100 + bot_index,
		"name": b_name,
		"is_host": false,
		"is_bot": true,
		"ready": true,
		"score": 0,
		"ping_ms": 0,
		"creation": creation.to_dict()
	}
