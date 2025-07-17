# AICommandProcessor.gd
class_name AICommandProcessor
extends Node

# Import schemas for structured outputs
const AIResponseSchemas = preload("res://scripts/ai/ai_response_schemas.gd")

# Dependencies
var logger
var action_validator: ActionValidator
var langsmith_client: Node
var plan_executor: Node

# Internal variables for concurrent request handling
var active_requests: Dictionary = {} # request_id -> { "context": Dictionary, "timestamp": float }
var request_id_counter: int = 0
var max_concurrent_requests: int = 10 # Allow up to 10 concurrent requests
var max_request_timeout: float = 30.0  # 30 second timeout

# Model configuration for different prompt types
# o1-mini: Best for complex reasoning, group coordination, strategic planning (slower but smarter)
# gpt-4o: Fast and capable for individual commands and real-time responses
# gpt-4o-mini: Fastest option for simple autonomous decisions (if speed is critical)
var group_command_model: String = "gpt-4.1-nano"  # Slower but more capable for complex group coordination
var individual_command_model: String = "gpt-4.1-nano"  # Faster for simple individual commands  
var autonomous_command_model: String = "gpt-4.1-nano"  # Fast for autonomous decision making

# Universal base prompt shared between group and individual commands
var base_system_prompt_template = """
You are an AI assistant for a 2v2 cooperative RTS game.
Your task is to translate natural language commands into a structured plan for {target_description}.
The plan for each unit should consist of a sequential list of "steps" and a list of "triggered_actions".

Your response will automatically follow the required JSON format. Focus on creating tactical plans that make strategic sense.

{specific_requirements}

CRITICAL STRUCTURE REQUIREMENTS:
- "steps" is a sequential plan. Actions are executed in order.
- "triggered_actions" are conditional and interrupt the main plan.
- You MUST provide at least one action in the "steps" array.
- You MUST provide at least one action in "triggered_actions" with 'enemies_in_range' as the trigger for self-defense.
- You can add other triggered actions, like retreating on low health.
- Limit to a maximum of 3 triggered actions per unit.
- Keep "speech" text brief (under 50 characters each).

IMPORTANT: You may ONLY use actions from the following list. Do not invent new actions.
Available actions: {actions_list}

Action Parameter Examples:
- "move_to": {"position": [x: float, y: float, z: float]}
- "attack": {"target_id": "string_unit_id"}
- "follow": {"target_id": "string_unit_id"}
- "heal_target": {"target_id": "string_unit_id"}
- "repair": {"target_id": "string_building_or_unit_id"}
- "construct": {"position": [x: float, y: float, z: float]} // Always builds power_spire
- For actions with no parameters like "activate_shield" or "lay_mines", use {}.

Your response will use structured triggers with three separate fields:
- trigger_source: The metric to check (health_pct, ammo_pct, morale, incoming_fire_count, target_health_pct, enemies_in_range, enemy_dist, ally_health_pct, nearby_enemies, move_speed, elapsed_ms)
- trigger_comparison: The comparison operator (<, =, >, !=)
- trigger_value: The value to compare against (number)

Examples:
- For "health below 50%": trigger_source="health_pct", trigger_comparison="<", trigger_value=50
- For "enemy in range": trigger_source="enemies_in_range", trigger_comparison=">", trigger_value=0
- For "elapsed time over 2 seconds": trigger_source="elapsed_ms", trigger_comparison=">", trigger_value=2000

TEAM-RELATIVE DATA EXPLANATION:
All data in your context uses team-relative values from YOUR team's perspective:
- `team_id` fields: +1 = your team, -1 = enemy team, 0 = neutral
- `controlling_team` (control points): +1 = controlled by your team, -1 = controlled by enemy team, 0 = neutral
- `capture_value` (control points): +1.0 = fully controlled by your team, -1.0 = fully controlled by enemy, 0.0 = neutral
  Values between 0 and ±1 indicate capture progress (e.g., 0.5 = 50 percent captured by your team)
  All numeric values are rounded to 2 decimal places and relative to YOUR team perspective.

COORDINATE SYSTEM:
All `position` fields in the context have been transformed into a team-relative coordinate system.
- Your team's home base is ALWAYS at the origin `[0, 0, 0]`.
- The enemy team's home base is ALWAYS in the positive Z direction.
- The X-axis is to the right of the Z-axis.
When you provide a `position` for an action, you MUST use this same relative coordinate system.


{additional_content}
"""

#EXAMPLE PLAN STRUCTURE{example_suffix}:
#- unit_id: Unique identifier for the unit
#- goal: High-level objective like "Secure the northern sector and provide overwatch"
#- steps: Sequential actions like move_to, patrol, attack
#- triggered_actions: Conditional responses like "attack when enemies_in_range" or "retreat when health_pct < 25"

# Signals
signal plan_processed(plans: Array, message: String)
signal command_failed(error: String, unit_ids: Array)
signal processing_started()
signal processing_finished()

func _ready() -> void:
    print("AICommandProcessor initialized, waiting for setup.")
    set_process(true) # Enable _process for checking timeouts

func _process(_delta: float) -> void:
    # Check for request timeouts
    var current_time = Time.get_ticks_msec() / 1000.0
    var timed_out_requests = []
    for request_id in active_requests:
        var request_data = active_requests[request_id]
        if current_time - request_data.timestamp > max_request_timeout:
            timed_out_requests.append(request_id)
    
    for request_id in timed_out_requests:
        _on_request_timeout(request_id)

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
    
    logger.info("AICommandProcessor", "AI command processor setup complete.")

# Model configuration functions
func set_group_command_model(model: String) -> void:
    """Set the model to use for group commands"""
    group_command_model = model

func set_individual_command_model(model: String) -> void:
    """Set the model to use for individual commands"""
    individual_command_model = model

func set_autonomous_command_model(model: String) -> void:
    """Set the model to use for autonomous commands"""
    autonomous_command_model = model

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
    var specific_requirements = """MANDATORY REQUIREMENT: You MUST include a plan for EVERY unit in the `allied_units` list.
If there are N units in `allied_units`, you MUST return exactly N plans in your response.
For each plan, you MUST define a high-level `goal` for the unit to follow.

You will be given a single consolidated `game_context` object. It contains:
- `global_state`: Overall game information.
- `allied_units`: A list of states for all units in your group.
- `sensor_data`: A combined view of all enemies and control points visible to your group.
Use this to make coordinated, high-level tactical decisions."""
    var actions_list = str(action_validator.get_allowed_actions())
    var example_suffix = " PER UNIT"
    var example_unit_id = "unit_123"
    var example_speech_1 = "Moving to position"
    var example_speech_2 = "Engaging target"
    var example_speech_3 = "Falling back"
    var additional_content = ""
    
    # Use safer string building approach
    var template = base_system_prompt_template
    template = template.replace("{target_description}", target_description)
    template = template.replace("{specific_requirements}", specific_requirements)
    template = template.replace("{actions_list}", actions_list)
    template = template.replace("{example_suffix}", example_suffix)
    template = template.replace("{example_unit_id}", example_unit_id)
    template = template.replace("{example_speech_1}", example_speech_1)
    template = template.replace("{example_speech_2}", example_speech_2)
    template = template.replace("{example_speech_3}", example_speech_3)
    template = template.replace("{additional_content}", additional_content)
    
    return template

func _build_source_info(units: Array, command_type: String) -> String:
    """Build source information for LangSmith tracing (e.g., 'player1/Tank' or 'player2/Group_3units')"""
    if units.is_empty():
        return "unknown"
    
    var first_unit = units[0]
    var team_name = "player%d" % first_unit.team_id
    
    if command_type == "group" and units.size() > 1:
        # For group commands, show unit count and primary archetype
        var archetype_counts = {}
        for unit in units:
            var archetype = unit.archetype.capitalize()
            archetype_counts[archetype] = archetype_counts.get(archetype, 0) + 1
        
        # Find the most common archetype
        var primary_archetype = ""
        var max_count = 0
        for archetype in archetype_counts:
            if archetype_counts[archetype] > max_count:
                max_count = archetype_counts[archetype]
                primary_archetype = archetype
        
        return "%s/Group_%dunits_%s" % [team_name, units.size(), primary_archetype]
    else:
        # For individual commands, show specific unit archetype
        var archetype = first_unit.archetype.capitalize()
        return "%s/%s" % [team_name, archetype]

func _build_individual_prompt(unit_personality: String) -> String:
    """Build the system prompt for individual unit commands"""
    var target_description = "a specific unit"
    var plan_description = ""
    var unit_id_example = "id_of_unit_to_command"
    var specific_requirements = """You will be given a detailed context object. Your `unit_state` contains a `strategic_goal`.
Your generated plan should be a series of concrete actions to achieve this `strategic_goal`.
When generating a new plan, you MUST also output a new `goal` field. If you are continuing the same overall objective, this can be the same as your input `strategic_goal`. If you are changing tactics, provide a new descriptive goal."""
    var actions_list = str(action_validator.get_allowed_actions())
    var example_suffix = ""
    var example_unit_id = "your_unit_id"
    var example_speech_1 = "Moving to engage"
    var example_speech_2 = "Attacking target"
    var example_speech_3 = "Retreating to safety"
    # Simply add unit personality without % escaping
    var additional_content = "\nUNIT PERSONALITY:\n" + unit_personality
    
    # Use safer string building approach
    var template = base_system_prompt_template
    template = template.replace("{target_description}", target_description)
    template = template.replace("{specific_requirements}", specific_requirements)
    template = template.replace("{actions_list}", actions_list)
    template = template.replace("{example_suffix}", example_suffix)
    template = template.replace("{example_unit_id}", example_unit_id)
    template = template.replace("{example_speech_1}", example_speech_1)
    template = template.replace("{example_speech_2}", example_speech_2)
    template = template.replace("{example_speech_3}", example_speech_3)
    template = template.replace("{additional_content}", additional_content)
    
    return template

func process_command(command_text: String, unit_ids: Array = [], peer_id: int = -1) -> void:
    if active_requests.size() >= max_concurrent_requests:
        logger.warning("AICommandProcessor", "Max concurrent requests reached (%d). Dropping new command for units %s." % [max_concurrent_requests, str(unit_ids)])
        command_failed.emit("AI service is busy. Please try again.", unit_ids)
        return

    if active_requests.is_empty():
        processing_started.emit()

    request_id_counter += 1
    var request_id = "req_%d" % request_id_counter
    
    var server_game_state = get_node("/root/DependencyContainer").get_game_state()
    if not server_game_state:
        logger.error("AICommandProcessor", "ServerGameState not found - command failed")
        command_failed.emit("ServerGameState not found.", [])
        if active_requests.is_empty():
            processing_finished.emit()
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
    
    if selected_units.is_empty():
        logger.warning("AICommandProcessor", "No valid units found for command")
        command_failed.emit("No valid units found for command.", [])
        if active_requests.is_empty():
            processing_finished.emit()
        return
        
    var is_group_command = unit_ids.is_empty() or selected_units.size() >= 2
    var prompt_type = "group" if is_group_command else ("autonomous" if command_text == "autonomously decide next action" else "individual")
    var unit_list = []
    for unit in selected_units:
        unit_list.append(unit.unit_id)
    
    logger.info("AICommandProcessor", "Processing %s command for units %s: '%s'" % [prompt_type, str(unit_list), command_text])
    
    var context = {"expected_unit_ids": unit_list}
    active_requests[request_id] = {
        "context": context,
        "timestamp": Time.get_ticks_msec() / 1000.0
    }
    
    if is_group_command:
        _process_group_command(command_text, selected_units, server_game_state, request_id)
    else:
        _process_individual_command(command_text, selected_units[0], server_game_state, request_id)

func _process_group_command(command_text: String, units: Array, server_game_state: Node, request_id: String) -> void:
    var group_system_prompt = _build_group_prompt()
    var game_context = server_game_state.get_group_context_for_ai(units)
   
    # Notify game state that the first group command has been issued.
    #if server_game_state and server_game_state.has_method("set_initial_group_command_given"):
    #    server_game_state.set_initial_group_command_given()
        
    var unit_count = game_context.allied_units.size()
    var unit_list = []
    for unit_state in game_context.allied_units:
        unit_list.append(unit_state.get("id", "unknown"))
        
    var user_prompt = """Command: '%s'\n
    
You are coordinating the entire team. Analyze the current battlefield situation and coordinate tactical actions for your entire squad to accomplish the above goal.

CRITICAL REQUIREMENT: You MUST provide plans for ALL %d units specified in the `allied_units` list below. Do not skip any units.
Units requiring plans: %s

Focus on:
- Team synergy and coordinated maneuvers
- Control point capture strategy  
- Strategic positioning across the battlefield
- Role-based tactics (scout reconnaissance, tank frontline, sniper overwatch, medic support, engineer fortification)

Context: %s""" % [command_text, unit_count, str(unit_list), JSON.stringify({"game_context": game_context})]

    var messages = [
        {"role": "system", "content": group_system_prompt},
        {"role": "user", "content": user_prompt}
    ]
    
    if langsmith_client:
        var on_response = func(response):
            _on_openai_response(response, request_id)
        var on_error = func(error_type, error_message):
            _on_openai_error(error_type, error_message, request_id)
        
        # Create source metadata for tracing
        var source_info = _build_source_info(units, "group")
        var metadata = {"source": source_info}
        
        var model_to_use = group_command_model
        # Collect unit archetypes for schema generation
        var unit_archetypes = []
        for unit in units:
            if unit.archetype not in unit_archetypes:
                unit_archetypes.append(unit.archetype)
        
        var response_format = AIResponseSchemas.get_schema_for_command(true, unit_archetypes)  # true = group command
        langsmith_client.traced_chat_completion(messages, on_response, on_error, metadata, model_to_use, response_format)
    else:
        logger.error("AICommandProcessor", "LangSmith client not available.")
        var unit_ids = active_requests[request_id].context.get("expected_unit_ids", [])
        active_requests.erase(request_id)
        command_failed.emit("AI service not configured.", unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()

func _process_individual_command(command_text: String, unit: Node, server_game_state: Node, request_id: String) -> void:
    var unit_specific_prompt = _build_individual_prompt(unit.system_prompt)
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
        var on_response = func(response):
            _on_openai_response(response, request_id)
        var on_error = func(error_type, error_message):
            _on_openai_error(error_type, error_message, request_id)
        
        # Create source metadata for tracing
        var source_info = _build_source_info([unit], "individual")
        var metadata = {"source": source_info}
        
        var model_to_use = individual_command_model
        if command_text == "autonomously decide next action":
            model_to_use = autonomous_command_model
        
        var response_format = AIResponseSchemas.get_schema_for_command(false, [unit.archetype])  # false = individual command
        langsmith_client.traced_chat_completion(messages, on_response, on_error, metadata, model_to_use, response_format)
    else:
        logger.error("AICommandProcessor", "LangSmith client not available.")
        var unit_ids = active_requests[request_id].context.get("expected_unit_ids", [])
        active_requests.erase(request_id)
        command_failed.emit("AI service not configured.", unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()

func _on_openai_response(response: Dictionary, request_id: String) -> void:
    if not active_requests.has(request_id):
        return # Request already timed out or handled
    
    var context = active_requests[request_id].context
    active_requests.erase(request_id)
    
    # Check for network/API errors from OpenAI client
    if response.has("error"):
        var error_info = response.error
        var error_message = error_info.get("message", "Unknown API error")
        logger.error("AICommandProcessor", "OpenAI API error: %s" % error_message)
        var unit_ids = context.get("expected_unit_ids", [])
        command_failed.emit(error_message, unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
    
    if content.is_empty():
        logger.error("AICommandProcessor", "Empty response from AI - check API connectivity and rate limits")
        var unit_ids = context.get("expected_unit_ids", [])
        command_failed.emit("Empty response from AI - please try again or check service status", unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    # With structured outputs, the response is guaranteed to be properly formatted
    logger.info("AICommandProcessor", "Received structured response length: %d characters" % content.length())
    
    # Parse the guaranteed valid JSON
    var json = JSON.new()
    var error = json.parse(content)
    if error != OK:
        # This should never happen with structured outputs
        logger.error("AICommandProcessor", "Unexpected JSON parsing error with structured outputs: %s" % json.get_error_message())
        var unit_ids = context.get("expected_unit_ids", [])
        command_failed.emit("Unexpected parsing error: " + json.get_error_message(), unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    var ai_response = json.data
    
    if not ai_response is Dictionary or not ai_response.has("plans"):
        logger.error("AICommandProcessor", "Invalid plan structure - missing 'plans' key")
        var unit_ids = context.get("expected_unit_ids", [])
        command_failed.emit("Invalid plan structure from AI", unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    # Validate that we received plans for all expected units
    var received_unit_ids = []
    for plan_data in ai_response.plans:
        var unit_id = plan_data.get("unit_id", "")
        received_unit_ids.append(unit_id)
    
    var expected_unit_ids = context.get("expected_unit_ids", [])
    if not expected_unit_ids.is_empty():
        var missing_unit_ids = []
        for expected_id in expected_unit_ids:
            if not received_unit_ids.has(expected_id):
                missing_unit_ids.append(expected_id)
        
        if not missing_unit_ids.is_empty():
            logger.warning("AICommandProcessor", "Missing plans for units: %s" % str(missing_unit_ids))
            var unit_ids = context.get("expected_unit_ids", [])
            command_failed.emit("Received plans for fewer units than expected. Missing plans for: %s" % str(missing_unit_ids), unit_ids)
            if active_requests.is_empty():
                processing_finished.emit()
            return
    
    logger.info("AICommandProcessor", "Response received successfully for units %s" % str(received_unit_ids))
    
    _process_multi_step_plans(ai_response)
    
    if active_requests.is_empty():
        processing_finished.emit()

func _on_openai_error(error_type: int, error_message: String, request_id: String) -> void:
    if not active_requests.has(request_id):
        return # Request already timed out or handled
    
    var context = active_requests[request_id].context
    var unit_ids = context.get("expected_unit_ids", [])
    active_requests.erase(request_id)
    
    var error_msg = "AI service error for units %s: %s" % [str(unit_ids), error_message]
    logger.error("AICommandProcessor", "%s (%s)" % [error_msg, str(error_type)])
    command_failed.emit(error_msg, unit_ids)

    if active_requests.is_empty():
        processing_finished.emit()

func _process_multi_step_plans(ai_response: Dictionary) -> void:
    var plans = ai_response.get("plans", [])
    var message = ai_response.get("message", "Executing tactical plans")
    var summary = ai_response.get("summary", "")
    
    if plans.is_empty():
        command_failed.emit("No plans provided", [])
        return
    
    var processed_plans = []
    var game_state = get_node("/root/DependencyContainer").get_game_state()
    if not game_state:
        logger.error("AICommandProcessor", "Cannot process plans, game_state not found.")
        return

    for plan_data in plans:
        var validation_result = action_validator.validate_plan(plan_data)
        if validation_result != null and validation_result.valid:
            var unit_id = plan_data.get("unit_id", "")
            
            # Set the strategic goal on the unit
            var goal = plan_data.get("goal", "")
            if not goal.is_empty() and game_state.units.has(unit_id):
                var unit = game_state.units[unit_id]
                if is_instance_valid(unit):
                    unit.strategic_goal = goal
                    logger.info("AICommandProcessor", "Set goal for unit %s: '%s'" % [unit_id, goal])

            # Add summary to plan data for UI display
            if not summary.is_empty():
                plan_data["summary"] = summary

            if plan_executor.execute_plan(unit_id, plan_data):
                processed_plans.append(plan_data)
            else:
                if logger: logger.warning("AICommandProcessor", "Plan execution failed for unit %s" % unit_id)
        else:
            if logger: logger.warning("AICommandProcessor", "Plan validation failed: %s" % validation_result.error)

    if processed_plans.size() > 0:
        # Create response with summary for UI
        var enhanced_message = message
        if not summary.is_empty():
            enhanced_message = summary  # Use summary as the primary message for UI
        
        plan_processed.emit(processed_plans, enhanced_message)

func _on_request_timeout(request_id: String) -> void:
    if not active_requests.has(request_id):
        return # Request already handled

    var context = active_requests[request_id].context
    var unit_ids = context.get("expected_unit_ids", [])
    
    logger.error("AICommandProcessor", "=== REQUEST TIMEOUT ===")
    logger.error("AICommandProcessor", "Request %s for units %s timed out after %f seconds" % [request_id, str(unit_ids), max_request_timeout])
    
    active_requests.erase(request_id)
    
    var error_msg = "Request timed out for units %s. Check API connectivity." % str(unit_ids)
    command_failed.emit(error_msg, unit_ids)
    
    if active_requests.is_empty():
        processing_finished.emit()