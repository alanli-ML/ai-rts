# AICommandProcessor.gd
class_name AICommandProcessor
extends Node

# Dependencies
var logger
var action_validator: ActionValidator
var openai_client: Node
var plan_executor: Node

# Internal variables
var command_queue: Array[Dictionary] = []
var processing_command: bool = false
var last_game_state: Dictionary = {}

# Signals
signal plan_processed(plans: Array, message: String)
signal command_failed(error: String)
signal processing_started()
signal processing_finished()

func _ready() -> void:
    var OpenAIClientScript = load("res://scripts/ai/openai_client.gd")
    openai_client = OpenAIClientScript.new()
    openai_client.name = "OpenAI_Client"
    add_child(openai_client)

    openai_client.request_completed.connect(_on_openai_response)
    openai_client.request_failed.connect(_on_openai_error)

    print("AICommandProcessor initialized, waiting for setup.")

func setup(p_logger, _game_constants, p_action_validator, p_plan_executor) -> void:
    logger = p_logger
    action_validator = p_action_validator
    plan_executor = p_plan_executor
    
    var server_game_state = get_node_or_null("/root/DependencyContainer/GameState")
    if server_game_state:
        if not plan_processed.is_connected(server_game_state._on_ai_plan_processed):
            plan_processed.connect(server_game_state._on_ai_plan_processed)
        if not command_failed.is_connected(server_game_state._on_ai_command_failed):
            command_failed.connect(server_game_state._on_ai_command_failed)
        logger.info("AICommandProcessor", "Explicitly connected signals to ServerGameState.")
    
    logger.info("AICommandProcessor", "AI command processor setup complete.")

func process_command(command_text: String, unit_ids: Array[String] = [], game_state: Dictionary = {}) -> void:
    if processing_command:
        command_queue.append({"text": command_text, "unit_ids": unit_ids, "state": game_state})
        return
    
    processing_command = true
    processing_started.emit()
    
    last_game_state = game_state
    
    if logger:
        logger.info("AICommandProcessor", "Processing command: '%s' for units: %s" % [command_text, unit_ids])
    else:
        print("Processing command: '%s' for units: %s" % [command_text, unit_ids])

    # Resolve unit nodes from IDs
    var selected_units = []
    var server_game_state = get_node("/root/DependencyContainer").get_game_state()
    if server_game_state:
        for unit_id in unit_ids:
            if server_game_state.units.has(unit_id):
                selected_units.append(server_game_state.units[unit_id])
    
    if selected_units.is_empty():
        command_failed.emit("No valid units found for command.")
        _process_next_command()
        return

    var system_prompt = """
You are an AI assistant for a 2v2 cooperative RTS game.
Your task is to translate natural language commands into a structured JSON plan that the game can execute.
The plan should be a list of steps for a specific unit.

You MUST respond with a JSON object in the following format:
{
  "type": "multi_step_plan",
  "plans": [
    {
      "unit_id": "id_of_unit_to_command",
      "steps": [
        {
          "action": "action_name",
          "params": { "param1": "value1" },
          "trigger": "optional_condition_to_start_step",
          "speech": "optional_unit_dialogue"
        }
      ]
    }
  ],
  "message": "A confirmation message for the player."
}

Available actions: %s
""" % str(action_validator.get_allowed_actions())

    var context = _build_context(selected_units, game_state)
    var user_prompt = "Command: '%s'\nContext: %s" % [command_text, JSON.stringify(context)]

    var messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt}
    ]
    
    openai_client.send_chat_completion(messages, Callable(self, "_on_openai_response"))

func _on_openai_response(response: Dictionary) -> void:
    processing_command = false
    processing_finished.emit()
    
    var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
    if content.is_empty():
        command_failed.emit("Empty response from AI")
        return
    
    var json = JSON.new()
    var error = json.parse(content)
    if error != OK:
        command_failed.emit("Invalid JSON response from AI: " + json.get_error_message())
        return
    
    var ai_response = json.data
    if not ai_response is Dictionary or not ai_response.has("plans"):
        command_failed.emit("Invalid plan structure from AI")
        return
        
    _process_multi_step_plans(ai_response)
    _process_next_command()

func _on_openai_error(error_type: int, error_message: String) -> void:
    processing_command = false
    processing_finished.emit()
    
    if logger:
        logger.error("AICommandProcessor", "OpenAI API Error [%d]: %s" % [error_type, error_message])
    else:
        print("AICommandProcessor Error [%d]: %s" % [error_type, error_message])

    command_failed.emit("AI service error: " + error_message)
    _process_next_command()

func _process_multi_step_plans(ai_response: Dictionary) -> void:
    var plans = ai_response.get("plans", [])
    var message = ai_response.get("message", "Executing tactical plans")
    
    if plans.is_empty():
        command_failed.emit("No plans provided")
        return
    
    var processed_plans = []
    for plan_data in plans:
        var validation_result = action_validator.validate_plan(plan_data)
        if validation_result.valid:
            var unit_id = plan_data.get("unit_id", "")
            if plan_executor.execute_plan(unit_id, plan_data):
                processed_plans.append(plan_data)
            else:
                if logger: logger.warning("AICommandProcessor", "Plan execution failed for unit %s" % unit_id)
        else:
            if logger: logger.warning("AICommandProcessor", "Plan validation failed: %s" % validation_result.error)

    if processed_plans.size() > 0:
        plan_processed.emit(processed_plans, message)

func _build_context(selected_units: Array, game_state: Dictionary) -> Dictionary:
    var context = {
        "game_state": {
            "match_time": game_state.get("match_time", 0),
            "controlled_nodes": game_state.get("controlled_nodes", 0),
            "resources": game_state.get("resources", {})
        },
        "selected_units": []
    }
    
    for unit in selected_units:
        if unit and unit.has_method("get_unit_info"):
            context.selected_units.append(unit.get_unit_info())
    
    return context

func _process_next_command() -> void:
    if command_queue.size() > 0 and not processing_command:
        var next_command = command_queue.pop_front()
        process_command(next_command.text, next_command.unit_ids, next_command.state)