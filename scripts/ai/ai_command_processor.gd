# AICommandProcessor.gd
class_name AICommandProcessor
extends Node

# Dependencies
var openai_client = null
var selection_manager: SelectionManager = null

# Command processing settings
@export var system_prompt_template: String = """
You are an AI assistant for a cooperative Real-Time Strategy (RTS) game. 
Players can give you natural language commands to control units.

GAME CONTEXT:
- This is a 2v2 cooperative RTS where teammates share control of 5 units
- Unit types: scout, sniper, medic, engineer, tank
- Players can select units and give movement, attack, and ability commands
- Units have different capabilities and roles

AVAILABLE COMMANDS:
1. MOVE - Move units to a location
2. ATTACK - Attack enemy units or buildings
3. FOLLOW - Follow another unit
4. PATROL - Patrol between waypoints
5. STOP - Stop current action
6. USE_ABILITY - Use unit's special ability
7. FORMATION - Change unit formation
8. STANCE - Change combat stance (aggressive, defensive, passive)

RESPONSE FORMAT:
Respond with JSON containing:
{
    "commands": [
        {
            "action": "MOVE|ATTACK|FOLLOW|PATROL|STOP|USE_ABILITY|FORMATION|STANCE",
            "target_units": ["selected"|"all"|"type:scout"|"unit_id"],
            "parameters": {
                "position": [x, y, z],
                "target_id": "unit_id",
                "ability_name": "ability_name",
                "formation": "line|column|wedge|scattered",
                "stance": "aggressive|defensive|passive",
                "waypoints": [[x1,y1,z1], [x2,y2,z2]]
            }
        }
    ],
    "message": "Confirmation message for the player"
}

CURRENT GAME STATE:
{game_state}

SELECTED UNITS:
{selected_units}

Parse the following command:
"""

# Internal variables
var command_queue: Array[Dictionary] = []
var processing_command: bool = false
var last_game_state: Dictionary = {}
var command_history: Array[String] = []

# Signals
signal command_processed(commands: Array, message: String)
signal command_failed(error: String)
signal processing_started()
signal processing_finished()

func _ready() -> void:
	# Create OpenAI client
	var OpenAIClientScript = load("res://scripts/ai/openai_client.gd")
	openai_client = OpenAIClientScript.new()
	openai_client.name = "OpenAIClient"
	add_child(openai_client)
	
	# Connect signals
	openai_client.request_completed.connect(_on_openai_response)
	openai_client.request_failed.connect(_on_openai_error)
	
	Logger.info("AICommandProcessor", "AI command processor initialized")

func process_command(command_text: String, selected_units: Array = [], game_state: Dictionary = {}) -> void:
	"""
	Process a natural language command
	
	Args:
		command_text: The natural language command from the player
		selected_units: Array of currently selected units
		game_state: Current game state information
	"""
	if processing_command:
		Logger.warning("AICommandProcessor", "Command processor busy, queuing command")
		command_queue.append({
			"text": command_text,
			"units": selected_units,
			"state": game_state
		})
		return
	
	processing_command = true
	processing_started.emit()
	
	# Store command in history
	command_history.append(command_text)
	if command_history.size() > 10:
		command_history.pop_front()
	
	# Update game state
	last_game_state = game_state
	
	# Build context
	var context = _build_context(selected_units, game_state)
	
	# Create messages for OpenAI
	var messages = [
		{
			"role": "system",
			"content": system_prompt_template.format({
				"game_state": JSON.stringify(context.game_state),
				"selected_units": JSON.stringify(context.selected_units)
			})
		},
		{
			"role": "user",
			"content": command_text
		}
	]
	
	# Send to OpenAI
	Logger.info("AICommandProcessor", "Processing command: " + command_text)
	openai_client.send_chat_completion(messages, _on_openai_response)

func _build_context(selected_units: Array, game_state: Dictionary) -> Dictionary:
	"""Build context information for AI prompt"""
	var context = {
		"game_state": {
			"match_time": game_state.get("match_time", 0.0),
			"team_id": game_state.get("team_id", 1),
			"enemy_visible": game_state.get("enemy_visible", false),
			"map_bounds": game_state.get("map_bounds", {"min": [-50, -50, -50], "max": [50, 50, 50]})
		},
		"selected_units": []
	}
	
	# Process selected units
	for unit in selected_units:
		if unit and unit.has_method("get_unit_info"):
			var unit_info = unit.get_unit_info()
			context.selected_units.append({
				"id": unit_info.get("id", ""),
				"type": unit_info.get("archetype", "unknown"),
				"health": unit_info.get("health", 100),
				"position": unit_info.get("position", [0, 0, 0]),
				"state": unit_info.get("state", "idle"),
				"abilities": unit_info.get("abilities", [])
			})
	
	return context

func _on_openai_response(response: Dictionary, error: int, error_message: String) -> void:
	"""Handle OpenAI API response"""
	processing_command = false
	processing_finished.emit()
	
	if error != 0:  # 0 is NONE in the APIError enum
		Logger.error("AICommandProcessor", "OpenAI error: " + error_message)
		command_failed.emit("AI service error: " + error_message)
		_process_next_command()
		return
	
	# Parse response
	if not response.has("choices") or response.choices.is_empty():
		Logger.error("AICommandProcessor", "Invalid OpenAI response format")
		command_failed.emit("Invalid AI response format")
		_process_next_command()
		return
	
	var content = response.choices[0].message.content
	Logger.info("AICommandProcessor", "AI response: " + content)
	
	# Parse JSON response
	var json = JSON.new()
	var parse_result = json.parse(content)
	
	if parse_result != OK:
		Logger.error("AICommandProcessor", "Failed to parse AI response JSON")
		command_failed.emit("Failed to parse AI response")
		_process_next_command()
		return
	
	var parsed_response = json.data
	
	# Validate response structure
	if not parsed_response.has("commands") or not parsed_response.has("message"):
		Logger.error("AICommandProcessor", "Invalid AI response structure")
		command_failed.emit("Invalid AI response structure")
		_process_next_command()
		return
	
	# Process commands
	var commands = parsed_response.commands
	var message = parsed_response.message
	
	# Validate and sanitize commands
	var validated_commands = _validate_commands(commands)
	
	Logger.info("AICommandProcessor", "Processed " + str(validated_commands.size()) + " commands")
	command_processed.emit(validated_commands, message)
	
	_process_next_command()

func _on_openai_error(error: int, error_message: String) -> void:
	"""Handle OpenAI API error"""
	processing_command = false
	processing_finished.emit()
	
	Logger.error("AICommandProcessor", "OpenAI error: " + error_message)
	command_failed.emit("AI service error: " + error_message)
	
	_process_next_command()

func _validate_commands(commands: Array) -> Array:
	"""Validate and sanitize AI commands"""
	var validated = []
	
	for command in commands:
		if not command is Dictionary:
			Logger.warning("AICommandProcessor", "Invalid command format, skipping")
			continue
		
		var cmd = command as Dictionary
		
		# Validate required fields
		if not cmd.has("action") or not cmd.has("target_units"):
			Logger.warning("AICommandProcessor", "Command missing required fields, skipping")
			continue
		
		# Validate action type
		var valid_actions = ["MOVE", "ATTACK", "FOLLOW", "PATROL", "STOP", "USE_ABILITY", "FORMATION", "STANCE"]
		if not cmd.action in valid_actions:
			Logger.warning("AICommandProcessor", "Invalid action: " + str(cmd.action))
			continue
		
		# Validate target units
		if not cmd.target_units is Array:
			Logger.warning("AICommandProcessor", "Invalid target_units format")
			continue
		
		# Sanitize parameters
		var parameters = cmd.get("parameters", {})
		parameters = _sanitize_parameters(cmd.action, parameters)
		
		validated.append({
			"action": cmd.action,
			"target_units": cmd.target_units,
			"parameters": parameters
		})
	
	return validated

func _sanitize_parameters(action: String, parameters: Dictionary) -> Dictionary:
	"""Sanitize command parameters"""
	var sanitized = {}
	
	match action:
		"MOVE":
			if parameters.has("position") and parameters.position is Array and parameters.position.size() == 3:
				sanitized.position = parameters.position
		"ATTACK":
			if parameters.has("target_id"):
				sanitized.target_id = str(parameters.target_id)
		"FOLLOW":
			if parameters.has("target_id"):
				sanitized.target_id = str(parameters.target_id)
		"PATROL":
			if parameters.has("waypoints") and parameters.waypoints is Array:
				sanitized.waypoints = parameters.waypoints
		"USE_ABILITY":
			if parameters.has("ability_name"):
				sanitized.ability_name = str(parameters.ability_name)
		"FORMATION":
			var valid_formations = ["line", "column", "wedge", "scattered"]
			if parameters.has("formation") and parameters.formation in valid_formations:
				sanitized.formation = parameters.formation
		"STANCE":
			var valid_stances = ["aggressive", "defensive", "passive"]
			if parameters.has("stance") and parameters.stance in valid_stances:
				sanitized.stance = parameters.stance
	
	return sanitized

func _process_next_command() -> void:
	"""Process next command in queue"""
	if command_queue.is_empty():
		return
	
	var next_command = command_queue.pop_front()
	process_command(next_command.text, next_command.units, next_command.state)

func get_command_history() -> Array[String]:
	"""Get recent command history"""
	return command_history.duplicate()

func clear_command_queue() -> void:
	"""Clear all queued commands"""
	command_queue.clear()
	Logger.info("AICommandProcessor", "Command queue cleared")

func is_command_processing() -> bool:
	"""Check if currently processing a command"""
	return processing_command

func get_queue_size() -> int:
	"""Get number of queued commands"""
	return command_queue.size() 