# AICommandProcessor.gd
class_name AICommandProcessor
extends Node

# Dependencies
var logger
var action_validator: ActionValidator
var langsmith_client: Node
var plan_executor: Node

# Internal variables
var command_queue: Array[Dictionary] = []
var processing_command: bool = false

# Signals
signal plan_processed(plans: Array, message: String)
signal command_failed(error: String)
signal processing_started()
signal processing_finished()

func _ready() -> void:
    print("AICommandProcessor initialized, waiting for setup.")

func setup(p_logger, _game_constants, p_action_validator, p_plan_executor, p_langsmith_client) -> void:
    logger = p_logger
    action_validator = p_action_validator
    plan_executor = p_plan_executor
    langsmith_client = p_langsmith_client
    
    var server_game_state = get_node_or_null("/root/DependencyContainer/GameState")
    if server_game_state:
        if not plan_processed.is_connected(server_game_state._on_ai_plan_processed):
            plan_processed.connect(server_game_state._on_ai_plan_processed)
        if not command_failed.is_connected(server_game_state._on_ai_command_failed):
            command_failed.connect(server_game_state._on_ai_command_failed)
        logger.info("AICommandProcessor", "Explicitly connected signals to ServerGameState.")
    
    logger.info("AICommandProcessor", "AI command processor setup complete.")

func process_command(command_text: String, unit_ids: Array[String] = [], _game_state: Dictionary = {}) -> void:
    if processing_command:
        command_queue.append({"text": command_text, "unit_ids": unit_ids})
        return
    
    processing_command = true
    processing_started.emit()
    
    logger.info("AICommandProcessor", "Processing command: '%s' for units: %s" % [command_text, unit_ids])

    # Resolve unit nodes from IDs
    var server_game_state = get_node("/root/DependencyContainer").get_game_state()
    if not server_game_state:
        command_failed.emit("ServerGameState not found.")
        _process_next_command()
        return

    var selected_units = []
    for unit_id in unit_ids:
        if server_game_state.units.has(unit_id):
            selected_units.append(server_game_state.units[unit_id])
    
    if selected_units.is_empty():
        command_failed.emit("No valid units found for command.")
        _process_next_command()
        return

    # --- Per-Unit Prompt Generation ---
    var base_system_prompt = """
You are an AI assistant for a 2v2 cooperative RTS game.
Your task is to translate natural language commands into a structured JSON plan for a specific unit.
The plan should be a list of steps.

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
          "trigger": "A condition to start this step. Examples: 'health_pct < 50', 'elapsed_ms > 2000'.",
          "speech": "optional_unit_dialogue"
        }
      ]
    }
  ],
  "message": "A confirmation message for the player."
}

You will be given a detailed context object. Use it to make tactical decisions.
When asked to act autonomously, you should decide the best course of action based on your personality and the game context. When given a direct command, you should follow it while adhering to your personality.
Available actions: %s
Available triggers: health_pct, ammo_pct, morale, under_fire, target_dead, enemy_in_range, enemy_dist, ally_health_low, nearby_enemies, is_moving, elapsed_ms.

UNIT PERSONALITY:
""" % str(action_validator.get_allowed_actions())

    for unit in selected_units:
        var unit_specific_prompt = base_system_prompt + unit.system_prompt
        var context = server_game_state.get_context_for_ai(unit)
        
        var user_prompt: String
        if command_text == "autonomously decide next action":
            user_prompt = "You are acting autonomously. Analyze the following context and generate the best plan based on your personality. Context: %s" % JSON.stringify(context)
        else:
            user_prompt = "Command: '%s'\nContext: %s" % [command_text, JSON.stringify(context)]

        var messages = [
            {"role": "system", "content": unit_specific_prompt},
            {"role": "user", "content": user_prompt}
        ]
        
        if langsmith_client:
            langsmith_client.traced_chat_completion(messages, Callable(self, "_on_openai_response"), Callable(self, "_on_openai_error"))
        else:
            logger.error("AICommandProcessor", "LangSmith client not available.")
            command_failed.emit("AI service not configured.")
            _process_next_command()
            return # Stop if client is missing

func _on_openai_response(response: Dictionary) -> void:
    var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
    if content.is_empty():
        command_failed.emit("Empty response from AI")
        _process_next_command()
        return
    
    var json = JSON.new()
    var error = json.parse(content)
    if error != OK:
        command_failed.emit("Invalid JSON response from AI: " + json.get_error_message())
        _process_next_command()
        return
    
    var ai_response = json.data
    if not ai_response is Dictionary or not ai_response.has("plans"):
        command_failed.emit("Invalid plan structure from AI")
        _process_next_command()
        return
        
    _process_multi_step_plans(ai_response)
    _process_next_command()

func _on_openai_error(error_type: int, error_message: String) -> void:
    logger.error("AICommandProcessor", "OpenAI API Error [%d]: %s" % [error_type, error_message])
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

func _process_next_command() -> void:
    # This logic needs to be aware that multiple requests might be in flight.
    # For now, we assume a simple sequential model for processing.
    # A more robust system would track active requests.
    if command_queue.size() > 0:
        var next_command = command_queue.pop_front()
        processing_command = false # Allow next command to start
        process_command(next_command.text, next_command.unit_ids)
    else:
        processing_command = false
        processing_finished.emit()