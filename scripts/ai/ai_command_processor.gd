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
var current_request_timeout: Timer = null
var max_request_timeout: float = 30.0  # 30 second timeout

# Model configuration for different prompt types
# o1-mini: Best for complex reasoning, group coordination, strategic planning (slower but smarter)
# gpt-4o: Fast and capable for individual commands and real-time responses
# gpt-4o-mini: Fastest option for simple autonomous decisions (if speed is critical)
var group_command_model: String = "o4-mini"  # Slower but more capable for complex group coordination
var individual_command_model: String = "gpt-4.1-nano"  # Faster for simple individual commands  
var autonomous_command_model: String = "gpt-4.1-nano"  # Fast for autonomous decision making

# Universal base prompt shared between group and individual commands
var base_system_prompt_template = """
You are an AI assistant for a 2v2 cooperative RTS game.
Your task is to translate natural language commands into a structured JSON plan for %s.
The plan for each unit should consist of a sequential list of "steps" and a list of "triggered_actions".

You MUST respond with a JSON object in the following format:
{
  "type": "multi_step_plan",
  "plans": [
    {
      "unit_id": "string_unit_id",
      "steps": [
        {
          "action": "action_name",
          "params": { "param1": "value1" },
          "speech": "optional_unit_dialogue"
        }
      ],
      "triggered_actions": [
        {
          "action": "action_name",
          "params": { "param1": "value1" },
          "trigger": "A condition to run this action. Examples: 'health_pct < 50', 'enemy_in_range'.",
          "speech": "optional_unit_dialogue"
        }
      ]
    }
  ],
  "message": "A confirmation message for the player."
}

%s

CRITICAL STRUCTURE REQUIREMENTS:
- "steps" is a sequential plan. Actions are executed in order.
- "triggered_actions" are conditional and interrupt the main plan.
- You MUST provide at least one action in the "steps" array.
- You MUST provide at least one action in "triggered_actions" with 'enemy_in_range' as the trigger for self-defense.
- You can add other triggered actions, like retreating on low health.

IMPORTANT: You may ONLY use actions from the following list. Do not invent new actions.
Available actions: %s

Action Parameter Examples:
- "move_to": {"position": [x: float, y: float, z: float]}
- "attack": {"target_id": "string_unit_id"}
- "follow": {"target_id": "string_unit_id"}
- "heal_target": {"target_id": "string_unit_id"}
- "repair": {"target_id": "string_building_or_unit_id"}
- "construct": {"building_type": "string_building_name", "position": [x: float, y: float, z: float]}
- For actions with no parameters like "activate_shield" or "lay_mines", use {}.

Available triggers for 'triggered_actions': health_pct, ammo_pct, morale, under_fire, target_dead, enemy_in_range, enemy_dist, ally_health_low, nearby_enemies, is_moving, elapsed_ms.
Trigger format examples: "health_pct < 50", "enemy_in_range" (simple boolean), "elapsed_ms > 2000".

EXAMPLE REQUIRED STRUCTURE%s:
{
  "unit_id": "%s",
  "steps": [
    {
      "action": "move_to",
      "params": {"position": [10, 0, 20]},
      "speech": "%s"
    },
    {
      "action": "patrol",
      "params": {},
      "speech": "Securing the area."
    }
  ],
  "triggered_actions": [
    {
      "action": "attack",
      "params": {},
      "trigger": "enemy_in_range",
      "speech": "%s"
    },
    {
      "action": "retreat",
      "params": {},
      "trigger": "health_pct < 25",
      "speech": "%s"
    }
  ]
}

%s
"""

# Signals
signal plan_processed(plans: Array, message: String)
signal command_failed(error: String)
signal processing_started()
signal processing_finished()

func _ready() -> void:
    print("AICommandProcessor initialized, waiting for setup.")
    
    # Create timeout timer
    current_request_timeout = Timer.new()
    current_request_timeout.name = "RequestTimeoutTimer"
    current_request_timeout.wait_time = max_request_timeout
    current_request_timeout.one_shot = true
    current_request_timeout.timeout.connect(_on_request_timeout)
    add_child(current_request_timeout)

func setup(p_logger, _game_constants, p_action_validator, p_plan_executor, p_langsmith_client) -> void:
    logger = p_logger
    action_validator = p_action_validator
    plan_executor = p_plan_executor
    langsmith_client = p_langsmith_client
    
    # Add diagnostic logging
    logger.info("AICommandProcessor", "=== AI SYSTEM DIAGNOSTIC ===")
    logger.info("AICommandProcessor", "LangSmith client available: %s" % str(langsmith_client != null))
    if langsmith_client:
        logger.info("AICommandProcessor", "LangSmith API key configured: %s" % str(not langsmith_client.api_key.is_empty()))
        logger.info("AICommandProcessor", "LangSmith tracing enabled: %s" % str(langsmith_client.enable_tracing))
        if langsmith_client.openai_client:
            logger.info("AICommandProcessor", "OpenAI client available: %s" % str(langsmith_client.openai_client != null))
            logger.info("AICommandProcessor", "OpenAI API key configured: %s" % str(not langsmith_client.openai_client.api_key.is_empty()))
        else:
            logger.warning("AICommandProcessor", "OpenAI client not found in LangSmith client")
    logger.info("AICommandProcessor", "=== END DIAGNOSTIC ===")
    
    var server_game_state = get_node_or_null("/root/DependencyContainer/GameState")
    if server_game_state:
        if not plan_processed.is_connected(server_game_state._on_ai_plan_processed):
            plan_processed.connect(server_game_state._on_ai_plan_processed)
        if not command_failed.is_connected(server_game_state._on_ai_command_failed):
            command_failed.connect(server_game_state._on_ai_command_failed)
        logger.info("AICommandProcessor", "Explicitly connected signals to ServerGameState.")
    
    logger.info("AICommandProcessor", "AI command processor setup complete.")

# Model configuration functions
func set_group_command_model(model: String) -> void:
    """Set the model to use for group commands"""
    group_command_model = model
    logger.info("AICommandProcessor", "Group command model set to: %s" % model)

func set_individual_command_model(model: String) -> void:
    """Set the model to use for individual commands"""
    individual_command_model = model
    logger.info("AICommandProcessor", "Individual command model set to: %s" % model)

func set_autonomous_command_model(model: String) -> void:
    """Set the model to use for autonomous commands"""
    autonomous_command_model = model
    logger.info("AICommandProcessor", "Autonomous command model set to: %s" % model)

func get_model_configuration() -> Dictionary:
    """Get current model configuration"""
    return {
        "group_command_model": group_command_model,
        "individual_command_model": individual_command_model,
        "autonomous_command_model": autonomous_command_model
    }

func _build_group_prompt() -> String:
    """Build the system prompt for group commands"""
    var target_description = "a group of units"
    var plan_description = " for each unit in the group"
    var unit_id_example = "id_of_unit_1\", \"id_of_unit_2"
    var specific_requirements = """MANDATORY REQUIREMENT: You MUST include a plan for EVERY unit provided in the group context. 
If you receive context for N units, you MUST return exactly N plans in your response.
Failure to provide plans for all units will result in some units being left without actions.

You will be given a detailed context object. The context will contain information for ALL units in the group under the `group_context` key. Use it to make tactical decisions and coordinate the units.
When given a direct command, you should create a coordinated plan for the group."""
    var actions_list = str(action_validator.get_allowed_actions())
    var example_suffix = " PER UNIT"
    var example_unit_id = "unit_123"
    var example_speech_1 = "Moving to position"
    var example_speech_2 = "Engaging target"
    var example_speech_3 = "Falling back"
    var additional_content = ""
    
    return base_system_prompt_template % [
        target_description,
        specific_requirements,
        actions_list,
        example_suffix,
        example_unit_id,
        example_speech_1,
        example_speech_2,
        example_speech_3,
        additional_content
    ]

func _build_individual_prompt(unit_personality: String) -> String:
    """Build the system prompt for individual unit commands"""
    var target_description = "a specific unit"
    var plan_description = ""
    var unit_id_example = "id_of_unit_to_command"
    var specific_requirements = """You will be given a detailed context object. Use it to make tactical decisions.
The context includes `visible_control_points`, which are strategic locations to capture. Capturing points is key to victory.
When asked to act autonomously, you should decide the best course of action based on your personality and the game context. When given a direct command, you should follow it while adhering to your personality."""
    var actions_list = str(action_validator.get_allowed_actions())
    var example_suffix = ""
    var example_unit_id = "your_unit_id"
    var example_speech_1 = "Moving to engage"
    var example_speech_2 = "Attacking target"
    var example_speech_3 = "Retreating to safety"
    var additional_content = "\nUNIT PERSONALITY:\n" + unit_personality
    
    return base_system_prompt_template % [
        target_description,
        specific_requirements,
        actions_list,
        example_suffix,
        example_unit_id,
        example_speech_1,
        example_speech_2,
        example_speech_3,
        additional_content
    ]

func process_command(command_text: String, unit_ids: Array[String] = [], peer_id: int = -1) -> void:
    if processing_command:
        command_queue.append({"text": command_text, "unit_ids": unit_ids, "peer_id": peer_id})
        return
    
    processing_command = true
    processing_started.emit()
    
    logger.info("AICommandProcessor", "=== PROCESSING COMMAND ===")
    logger.info("AICommandProcessor", "Command: '%s'" % command_text)
    logger.info("AICommandProcessor", "Unit IDs: %s" % str(unit_ids))
    logger.info("AICommandProcessor", "Peer ID: %d" % peer_id)
    logger.info("AICommandProcessor", "LangSmith client status: %s" % ("available" if langsmith_client else "NOT AVAILABLE"))
    
    var server_game_state = get_node("/root/DependencyContainer").get_game_state()
    if not server_game_state:
        logger.error("AICommandProcessor", "ServerGameState not found - command failed")
        command_failed.emit("ServerGameState not found.")
        _process_next_command()
        return

    var selected_units = []
    if not unit_ids.is_empty():
        for unit_id in unit_ids:
            if server_game_state.units.has(unit_id):
                selected_units.append(server_game_state.units[unit_id])
    elif peer_id != -1:
        # No units selected, get all units for the player's team
        var session_manager = get_node("/root/DependencyContainer").get_node_or_null("SessionManager")
        if session_manager:
            var session_id = session_manager.get_player_session(peer_id)
            if not session_id.is_empty():
                var session = session_manager.get_session(session_id)
                var player_team_id = -1
                for p_id in session.players:
                    if session.players[p_id].peer_id == peer_id:
                        player_team_id = session.players[p_id].team_id
                        break
                
                if player_team_id != -1:
                    for unit_id in server_game_state.units:
                        var unit = server_game_state.units[unit_id]
                        if is_instance_valid(unit) and unit.team_id == player_team_id:
                            selected_units.append(unit)
    
    logger.info("AICommandProcessor", "Selected units: %d" % selected_units.size())
    
    if selected_units.is_empty():
        logger.warning("AICommandProcessor", "No valid units found for command")
        command_failed.emit("No valid units found for command.")
        _process_next_command()
        return
        
    var is_group_command = unit_ids.is_empty() or selected_units.size() >= 2
    
    logger.info("AICommandProcessor", "Command type: %s" % ("group" if is_group_command else "individual"))
    
    if is_group_command:
        _process_group_command(command_text, selected_units, server_game_state)
    else:
        _process_individual_command(command_text, selected_units[0], server_game_state)

func _process_group_command(command_text: String, units: Array, server_game_state: Node) -> void:
    logger.info("AICommandProcessor", "Processing group command for %d units." % units.size())
    
    # Store expected unit IDs for validation
    var expected_unit_ids = []
    for unit in units:
        expected_unit_ids.append(unit.unit_id)
    
    logger.info("AICommandProcessor", "Expected plans for units: %s" % str(expected_unit_ids))
    
    var group_system_prompt = _build_group_prompt()

    var group_context = []
    for unit in units:
        group_context.append(server_game_state.get_context_for_ai(unit))
    
    var user_prompt: String
    if command_text == "autonomously decide next action":
        user_prompt = "You are acting autonomously. Analyze the following group context and generate the best coordinated plan based on the situation. Context: %s" % JSON.stringify({"group_context": group_context})
    elif command_text == "autonomously coordinate team tactics":
        var unit_count = group_context.size()
        var unit_list = []
        for unit_context in group_context:
            unit_list.append(unit_context.get("unit_state", {}).get("id", "unknown"))
        
        user_prompt = """You are acting autonomously as a team. Analyze the current battlefield situation and coordinate tactical actions for your entire squad.

CRITICAL REQUIREMENT: You MUST provide plans for ALL %d units specified below. Do not skip any units.
Units requiring plans: %s

Focus on:
- Team synergy and coordinated maneuvers
- Control point capture strategy  
- Strategic positioning across the battlefield
- Role-based tactics (scout reconnaissance, tank frontline, sniper overwatch, medic support, engineer fortification)

Context: %s""" % [unit_count, str(unit_list), JSON.stringify({"group_context": group_context})]
    else:
        user_prompt = "Command: '%s'\nGroup Context: %s" % [command_text, JSON.stringify({"group_context": group_context})]

    var messages = [
        {"role": "system", "content": group_system_prompt},
        {"role": "user", "content": user_prompt}
    ]
    
    # Store expected unit IDs for validation in response processing
    if not has_meta("expected_unit_ids"):
        set_meta("expected_unit_ids", expected_unit_ids)
    
    if langsmith_client:
        logger.info("AICommandProcessor", "Sending request to LangSmith client...")
        logger.info("AICommandProcessor", "Messages prepared: %d entries" % messages.size())
        
        # Start timeout timer
        current_request_timeout.start()
        logger.info("AICommandProcessor", "Request timeout timer started (%f seconds)" % max_request_timeout)
        
        # Determine model based on command type for group commands
        var model_to_use = group_command_model
        if command_text == "autonomously decide next action" or command_text == "autonomously coordinate team tactics":
            model_to_use = autonomous_command_model
        
        logger.info("AICommandProcessor", "Using model for group command: %s" % model_to_use)
        langsmith_client.traced_chat_completion(messages, Callable(self, "_on_openai_response"), Callable(self, "_on_openai_error"), {}, model_to_use)
        logger.info("AICommandProcessor", "LangSmith request sent - waiting for response...")
    else:
        logger.error("AICommandProcessor", "LangSmith client not available.")
        command_failed.emit("AI service not configured.")
        _process_next_command()

func _process_individual_command(command_text: String, unit: Node, server_game_state: Node) -> void:
    logger.info("AICommandProcessor", "Processing individual command for unit %s." % unit.unit_id)
    
    # Store expected unit ID for validation
    var expected_unit_ids = [unit.unit_id]
    logger.info("AICommandProcessor", "Expected plan for unit: %s" % unit.unit_id)
    
    var unit_specific_prompt = _build_individual_prompt(unit.system_prompt)
    var context = server_game_state.get_context_for_ai(unit)
    
    var user_prompt: String
    if command_text == "autonomously decide next action":
        user_prompt = "You are acting autonomously. Analyze the following context and generate the best plan based on your personality. Context: %s" % JSON.stringify(context)
    elif command_text == "autonomously coordinate team tactics":
        user_prompt = "You are acting autonomously as part of a team coordination effort. Analyze the current situation and generate your tactical contribution to the team strategy. Context: %s" % JSON.stringify(context)
    else:
        user_prompt = "Command: '%s'\nContext: %s" % [command_text, JSON.stringify(context)]

    var messages = [
        {"role": "system", "content": unit_specific_prompt},
        {"role": "user", "content": user_prompt}
    ]
    
    # Store expected unit ID for validation in response processing
    set_meta("expected_unit_ids", expected_unit_ids)
    
    if langsmith_client:
        logger.info("AICommandProcessor", "Sending request to LangSmith client...")
        logger.info("AICommandProcessor", "Messages prepared: %d entries" % messages.size())
        
        # Start timeout timer
        current_request_timeout.start()
        logger.info("AICommandProcessor", "Request timeout timer started (%f seconds)" % max_request_timeout)
        
        # Determine model based on command type for individual commands
        var model_to_use = individual_command_model
        if command_text == "autonomously decide next action" or command_text == "autonomously coordinate team tactics":
            model_to_use = autonomous_command_model
        
        logger.info("AICommandProcessor", "Using model for individual command: %s" % model_to_use)
        langsmith_client.traced_chat_completion(messages, Callable(self, "_on_openai_response"), Callable(self, "_on_openai_error"), {}, model_to_use)
        logger.info("AICommandProcessor", "LangSmith request sent - waiting for response...")
    else:
        logger.error("AICommandProcessor", "LangSmith client not available.")
        command_failed.emit("AI service not configured.")
        _process_next_command()

func _on_openai_response(response: Dictionary) -> void:
    logger.info("AICommandProcessor", "=== LLM RESPONSE RECEIVED ===")
    logger.info("AICommandProcessor", "Response keys: %s" % str(response.keys()))
    
    # Stop timeout timer
    if current_request_timeout and current_request_timeout.time_left > 0:
        current_request_timeout.stop()
        logger.info("AICommandProcessor", "Request timeout timer stopped")
    
    var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
    
    logger.info("AICommandProcessor", "Content length: %d characters" % content.length())
    if content.length() > 0:
        logger.info("AICommandProcessor", "Content preview: %s..." % content.substr(0, min(100, content.length())))
    
    if content.is_empty():
        logger.error("AICommandProcessor", "Empty response from AI")
        # Clear metadata on error
        if has_meta("expected_unit_ids"):
            remove_meta("expected_unit_ids")
        command_failed.emit("Empty response from AI")
        _process_next_command()
        return
    
    logger.info("AICommandProcessor", "Parsing JSON response...")
    
    # Strip markdown code block markers if present
    var cleaned_content = content.strip_edges()
    if cleaned_content.begins_with("```json"):
        cleaned_content = cleaned_content.substr(7)  # Remove "```json"
    if cleaned_content.begins_with("```"):
        cleaned_content = cleaned_content.substr(3)  # Remove "```"
    if cleaned_content.ends_with("```"):
        cleaned_content = cleaned_content.substr(0, cleaned_content.length() - 3)  # Remove ending "```"
    cleaned_content = cleaned_content.strip_edges()
    
    var json = JSON.new()
    var error = json.parse(cleaned_content)
    if error != OK:
        logger.error("AICommandProcessor", "JSON parsing failed: %s" % json.get_error_message())
        logger.error("AICommandProcessor", "Raw content: %s" % content)
        logger.error("AICommandProcessor", "Cleaned content: %s" % cleaned_content)
        # Clear metadata on error
        if has_meta("expected_unit_ids"):
            remove_meta("expected_unit_ids")
        command_failed.emit("Invalid JSON response from AI: " + json.get_error_message())
        _process_next_command()
        return
    
    var ai_response = json.data
    logger.info("AICommandProcessor", "JSON parsed successfully, type: %s" % str(type_string(typeof(ai_response))))
    
    if not ai_response is Dictionary or not ai_response.has("plans"):
        logger.error("AICommandProcessor", "Invalid plan structure - missing 'plans' key")
        logger.error("AICommandProcessor", "Response structure: %s" % ai_response)
        # Clear metadata on error
        if has_meta("expected_unit_ids"):
            remove_meta("expected_unit_ids")
        command_failed.emit("Invalid plan structure from AI")
        _process_next_command()
        return
    
    logger.info("AICommandProcessor", "Plan structure valid, processing %d plans..." % ai_response.plans.size())
    
    # Validate that we received plans for all expected units
    var received_unit_ids = []
    for plan_data in ai_response.plans:
        var unit_id = plan_data.get("unit_id", "")
        received_unit_ids.append(unit_id)
    
    var expected_unit_ids = get_meta("expected_unit_ids")
    if expected_unit_ids.is_empty():
        logger.warning("AICommandProcessor", "No expected unit IDs found for validation.")
    else:
        var missing_unit_ids = []
        for expected_id in expected_unit_ids:
            if not received_unit_ids.has(expected_id):
                missing_unit_ids.append(expected_id)
        
        if not missing_unit_ids.is_empty():
            logger.warning("AICommandProcessor", "Received plans for fewer units than expected. Missing plans for: %s" % str(missing_unit_ids))
            # Clear metadata on error
            if has_meta("expected_unit_ids"):
                remove_meta("expected_unit_ids")
            command_failed.emit("Received plans for fewer units than expected. Missing plans for: %s" % str(missing_unit_ids))
            _process_next_command()
            return
    
    _process_multi_step_plans(ai_response)
    
    # Clear metadata after processing
    if has_meta("expected_unit_ids"):
        remove_meta("expected_unit_ids")
    
    _process_next_command()

func _on_openai_error(error_type: int, error_message: String) -> void:
    logger.error("AICommandProcessor", "=== LLM ERROR RECEIVED ===")
    logger.error("AICommandProcessor", "Error type: %d" % error_type)
    logger.error("AICommandProcessor", "Error message: %s" % error_message)
    
    # Stop timeout timer
    if current_request_timeout and current_request_timeout.time_left > 0:
        current_request_timeout.stop()
        logger.info("AICommandProcessor", "Request timeout timer stopped (error)")
    
    # Clear metadata to prevent state leakage
    if has_meta("expected_unit_ids"):
        remove_meta("expected_unit_ids")
    
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
        if validation_result != null and validation_result.valid:
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
        process_command(next_command.text, next_command.unit_ids, next_command.get("peer_id", -1))
    else:
        processing_command = false
        processing_finished.emit()

func _on_request_timeout() -> void:
    logger.error("AICommandProcessor", "=== REQUEST TIMEOUT ===")
    logger.error("AICommandProcessor", "Request timed out after %f seconds" % max_request_timeout)
    logger.error("AICommandProcessor", "This suggests API connectivity issues or very slow responses")
    
    # Clear metadata to prevent state leakage
    if has_meta("expected_unit_ids"):
        remove_meta("expected_unit_ids")
    
    command_failed.emit("Request timed out after %f seconds. Check API connectivity." % max_request_timeout)
    _process_next_command()