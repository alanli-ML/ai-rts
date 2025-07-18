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
var max_request_timeout: float = 60.0  # 60 second timeout

# Model configuration for different prompt types
# o1-mini: Best for complex reasoning, group coordination, strategic planning (slower but smarter)
# gpt-4o: Fast and capable for individual commands and real-time responses
# gpt-4o-mini: Fastest option for simple autonomous decisions (if speed is critical)
var group_command_model: String = "gpt-4o-mini"  # Slower but more capable for complex group coordination
var individual_command_model: String = "gpt-4o-mini"  # Faster for simple individual commands
var autonomous_command_model: String = "gpt-4o-mini"  # Fast for autonomous decision making

# Universal base prompt shared between group and individual commands
var base_system_prompt_template = """
You are an AI assistant for a 2v2 cooperative RTS game.
Your task is to translate natural language commands into a structured plan for {target_description}.
The plan defines a unit's reactive "personality" and high-level strategy.

Your response must be valid JSON in this exact format:
```json
{
  "plans": [
    {
      "unit_id": "exact_unit_id_from_context",
      "goal": "High-level tactical objective for this unit",
      "control_point_attack_sequence": ["Node1", "Node5", "Node9"],
              "behavior_matrix": {
            "attack": {"enemies_in_range": 0.8, "current_health": 0.2, "under_attack": 0.1, "allies_in_range": 0.3, "ally_low_health": 0.1, "enemy_nodes_controlled": 0.4, "ally_nodes_controlled": -0.2, "bias": -0.2},
            "retreat": {"enemies_in_range": 0.4, "current_health": -0.9, "under_attack": 0.8, "allies_in_range": -0.3, "ally_low_health": -0.5, "enemy_nodes_controlled": 0.1, "ally_nodes_controlled": 0.0, "bias": -0.8},
            "defend": {"enemies_in_range": -0.5, "current_health": 0.5, "under_attack": -0.6, "allies_in_range": 0.2, "ally_low_health": 0.2, "enemy_nodes_controlled": -0.3, "ally_nodes_controlled": 0.5, "bias": -0.5},
            "follow": {"enemies_in_range": -0.3, "current_health": 0.0, "under_attack": -0.4, "allies_in_range": 0.7, "ally_low_health": 0.3, "enemy_nodes_controlled": 0.0, "ally_nodes_controlled": 0.0, "bias": -0.6},
            "activate_stealth": {"enemies_in_range": 0.6, "current_health": -0.3, "under_attack": 0.7, "allies_in_range": -0.2, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0, "ally_nodes_controlled": 0.0, "bias": -0.7},
            "find_cover": {"enemies_in_range": 0.3, "current_health": -0.5, "under_attack": 0.7, "allies_in_range": 0.0, "ally_low_health": 0.0, "enemy_nodes_controlled": 0.0, "ally_nodes_controlled": 0.0, "bias": -0.6}
      }
    }
  ],
  "message": "Confirmation message for the player",
  "summary": "Brief tactical summary"
}
```

**BEHAVIOR MATRIX EXPLANATION:**
The behavior_matrix determines how a unit reacts in real-time. Each weight can be any numeric value:
- Positive weights make an action MORE likely as the state variable increases
- Negative weights make it LESS likely  
- Zero means no influence
- Higher absolute values create stronger influence

**STATE VARIABLES (Inputs):**
- `enemies_in_range`: Normalized count of enemies within weapon range (0.0-1.0)
- `current_health`: Unit's health percentage (1.0=full, 0.0=dead)
- `under_attack`: 1.0 if recently took damage, 0.0 otherwise
- `allies_in_range`: Normalized count of friendly units in vision range (0.0-1.0)
- `ally_low_health`: Highest missing health percentage of nearby ally (0.0-1.0)
- `enemy_nodes_controlled`: Normalized count of enemy-held control points (0.0-1.0)
- `ally_nodes_controlled`: Normalized count of friendly-held control points (0.0-1.0)
- `bias`: Constant 1.0 value for baseline activation levels

**ACTIONS (Outputs):**

**Primary States (Mutually Exclusive):**
- `attack`: Aggressive combat, move toward enemies and control points
- `retreat`: Defensive withdrawal, move away from threats toward safety
- `defend`: Capture uncontrolled nodes, then patrol around friendly territory
- `follow`: Follow nearest ally in range, fallback to next best state if no allies available

**Independent Abilities (Can activate alongside primary states):**
- `activate_stealth`: Become invisible to enemies (Scout specialty)
- `activate_shield`: Absorb incoming damage (Tank specialty)  
- `taunt_enemies`: Draw enemy fire to protect allies (Tank specialty)
- `charge_shot`: Powerful long-range attack (Sniper specialty)
- `heal_ally`: Restore ally health (Medic specialty)
- `lay_mines`: Deploy explosive traps (Engineer specialty)
- `construct_turret`: Build an automated turret that attacks enemies (Engineer specialty)
- `repair`: Fix damaged buildings/units (Engineer specialty)
- `find_cover`: Move to protected position during combat

**TACTICAL EXAMPLES:**
- **Aggressive Tank**: High attack bias, shield when under fire: {"attack": {"bias": 0.3}, "activate_shield": {"under_attack": 0.8}}
- **Defensive Medic**: Prioritize healing, retreat when threatened: {"heal_ally": {"ally_low_health": 0.9}, "retreat": {"enemies_in_range": 0.7}}
- **Scout Infiltrator**: Use stealth when enemies near: {"activate_stealth": {"enemies_in_range": 0.8}, "attack": {"bias": 0.2}}

**CONTROL POINT SEQUENCE:**
Create logical attack routes through control points Node1-Node9. Consider map layout and strategic value.

{additional_content}
"""

#EXAMPLE PLAN STRUCTURE{example_suffix}:
#- unit_id: Unique identifier for the unit
#- goal: High-level objective like "Secure the northern sector and provide overwatch"
#- steps: Sequential actions like move_to, patrol, attack
#- triggered_actions: A dictionary of pre-defined conditional responses, like `"on_health_critical": "retreat"`.

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
    var additional_content = ""
    
    # Use safer string building approach
    var template = base_system_prompt_template
    template = template.replace("{target_description}", target_description)
    template = template.replace("{specific_requirements}", specific_requirements)
    template = template.replace("{additional_content}", additional_content)
    
    return template

func _get_archetype_specific_actions_info(unit_archetypes: Array) -> String:
    """Generate archetype-specific action information for the prompt"""
    var info_lines = []
    
    # Get unique archetypes
    var unique_archetypes = {}
    for archetype in unit_archetypes:
        unique_archetypes[archetype] = true
    
    info_lines.append("**ARCHETYPE-SPECIFIC ACTIONS:**")
    for archetype in unique_archetypes.keys():
        var valid_actions = action_validator.get_valid_actions_for_archetype(archetype)
        var primary_actions = []
        var ability_actions = []
        
        for action in valid_actions:
            if action in action_validator.MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS:
                primary_actions.append(action)
            elif action in action_validator.INDEPENDENT_REACTIVE_ACTIONS:
                ability_actions.append(action)
        
        info_lines.append("- **%s**: Primary states: %s | Special abilities: %s" % [
            archetype.capitalize(),
            ", ".join(primary_actions) if not primary_actions.is_empty() else "none",
            ", ".join(ability_actions) if not ability_actions.is_empty() else "none"
        ])
    
    info_lines.append("\n**CRITICAL**: Only include actions that are valid for each unit's archetype in the behavior_matrix!")
    return "\n".join(info_lines)

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
Your generated plan should define the unit's behavior matrix and attack sequence to achieve this `strategic_goal`."""
    # Simply add unit personality without % escaping
    var additional_content = "\nUNIT PERSONALITY:\n" + unit_personality
    
    # Use safer string building approach
    var template = base_system_prompt_template
    template = template.replace("{target_description}", target_description)
    template = template.replace("{specific_requirements}", specific_requirements)
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
    var start_time = Time.get_ticks_msec() / 1000.0
    active_requests[request_id] = {
        "context": context,
        "timestamp": start_time
    }
    
    logger.info("AICommandProcessor", "Starting request %s at %f for units %s" % [request_id, start_time, str(unit_list)])
    
    if is_group_command:
        _process_group_command(command_text, selected_units, server_game_state, request_id)
    else:
        _process_individual_command(command_text, selected_units[0], server_game_state, request_id)

func _process_group_command(command_text: String, units: Array, server_game_state: Node, request_id: String) -> void:
    var group_system_prompt = _build_group_prompt()
    var game_context = server_game_state.get_group_context_for_ai(units)
        
    var unit_count = game_context.allied_units.size()
    var unit_list = []
    var present_archetypes = []
    for unit_state in game_context.allied_units:
        unit_list.append(unit_state.get("id", "unknown"))
        var archetype = unit_state.get("archetype", "general")
        if archetype not in present_archetypes:
            present_archetypes.append(archetype)
    
    # Generate archetype-specific action information
    var archetype_info = _get_archetype_specific_actions_info(present_archetypes)
        
    var user_prompt = """Command: '%s'\n
    
You are coordinating the entire team. Analyze the current battlefield situation and define a behavior matrix and control point attack sequence for EACH unit to accomplish the above goal.

CRITICAL REQUIREMENT: You MUST provide a plan (matrix and sequence) for ALL %d units specified in the `allied_units` list below. Do not skip any units.
Units requiring plans: %s

%s

Focus on:
- Creating complementary behavior matrices for team synergy (e.g., have tanks be aggressive while medics are defensive).
- Defining a coordinated `control_point_attack_sequence` for the group.
- Role-based tactics (scout reconnaissance, tank frontline, sniper overwatch, medic support, engineer fortification).

Context: %s""" % [command_text, unit_count, str(unit_list), archetype_info, JSON.stringify({"game_context": game_context})]

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
        
        # No longer using structured JSON schema - relying on prompt instructions instead
        langsmith_client.traced_chat_completion(messages, on_response, on_error, metadata, model_to_use)
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
    
    # Generate archetype-specific action information for this unit
    var unit_archetype = unit.archetype if "archetype" in unit else "general"
    var archetype_info = _get_archetype_specific_actions_info([unit_archetype])
    
    var user_prompt: String
    if command_text == "autonomously decide next action":
        user_prompt = "You are acting autonomously. Analyze the following context and generate the best behavior_matrix and control_point_attack_sequence based on your personality and strategic goal.\n\n%s\n\nContext: %s" % [archetype_info, JSON.stringify(context)]
    else:
        user_prompt = "Command: '%s'\n\n%s\n\nContext: %s" % [command_text, archetype_info, JSON.stringify(context)]

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
        
        # No longer using structured JSON schema - relying on prompt instructions instead
        langsmith_client.traced_chat_completion(messages, on_response, on_error, metadata, model_to_use)
    else:
        logger.error("AICommandProcessor", "LangSmith client not available.")
        var unit_ids = active_requests[request_id].context.get("expected_unit_ids", [])
        active_requests.erase(request_id)
        command_failed.emit("AI service not configured.", unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()

func _on_openai_response(response: Dictionary, request_id: String) -> void:
    if not active_requests.has(request_id):
        logger.warning("AICommandProcessor", "Response received for unknown/timed-out request: %s" % request_id)
        return # Request already timed out or handled
    
    var request_data = active_requests[request_id]
    var context = request_data.context
    var request_duration = (Time.get_ticks_msec() / 1000.0) - request_data.timestamp
    logger.info("AICommandProcessor", "Response received for request %s after %.2f seconds" % [request_id, request_duration])
    
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
    
    # Parse the JSON response from prompt-based instructions
    logger.info("AICommandProcessor", "Received response length: %d characters" % content.length())
    logger.info("AICommandProcessor", "Response content preview: %s" % content.substr(0, min(200, content.length())))
    
    # Strip markdown code block delimiters if present
    var cleaned_content = content.strip_edges()
    
    # Remove leading ```json and trailing ```
    if cleaned_content.begins_with("```json"):
        cleaned_content = cleaned_content.substr(7).strip_edges()
    elif cleaned_content.begins_with("```"):
        cleaned_content = cleaned_content.substr(3).strip_edges()
    
    if cleaned_content.ends_with("```"):
        cleaned_content = cleaned_content.substr(0, cleaned_content.length() - 3).strip_edges()
    
    logger.info("AICommandProcessor", "Cleaned content preview: %s" % cleaned_content.substr(0, min(200, cleaned_content.length())))
    
    # Parse the JSON response
    var json = JSON.new()
    var error = json.parse(cleaned_content)
    if error != OK:
        logger.error("AICommandProcessor", "JSON parsing error: %s" % json.get_error_message())
        logger.error("AICommandProcessor", "Failed content: %s" % cleaned_content.substr(0, min(500, cleaned_content.length())))
        var unit_ids = context.get("expected_unit_ids", [])
        command_failed.emit("JSON parsing error: " + json.get_error_message(), unit_ids)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    var ai_response = json.data
    
    # Debug: Show the parsed response structure
    logger.info("AICommandProcessor", "Parsed JSON successfully, structure: %s" % str(ai_response.keys()) if ai_response is Dictionary else "Not a dictionary")
    
    if not ai_response is Dictionary or not ai_response.has("plans"):
        logger.error("AICommandProcessor", "Invalid plan structure - missing 'plans' key")
        logger.error("AICommandProcessor", "Received structure: %s" % str(ai_response))
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
    logger.info("AICommandProcessor", "Plans count: %d, Message: '%s', Summary: '%s'" % [ai_response.plans.size(), ai_response.get("message", ""), ai_response.get("summary", "")])
    
    # Set initial_group_command_given flag only after successful group command response
    if expected_unit_ids.size() >= 2:  # This was a group command
        var server_game_state = get_node_or_null("/root/DependencyContainer/GameState")
        if server_game_state and server_game_state.has_method("set_initial_group_command_given"):
            server_game_state.set_initial_group_command_given()
            logger.info("AICommandProcessor", "Set initial_group_command_given flag after successful group command response")
    
    _process_behavior_plans(ai_response)
    
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

func _process_behavior_plans(ai_response: Dictionary) -> void:
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
        # Get unit archetype for validation
        var unit_id = plan_data.get("unit_id", "")
        var unit_archetype = ""
        if game_state.units.has(unit_id):
            var unit = game_state.units[unit_id]
            if is_instance_valid(unit) and "archetype" in unit:
                unit_archetype = unit.archetype
        
        var validation_result = action_validator.validate_plan(plan_data, unit_archetype)
        if validation_result.valid:
            
            # Set the strategic goal on the unit
            var goal = plan_data.get("goal", "") # Goal is still useful for high-level context
            if game_state.units.has(unit_id):
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
            if logger: logger.warning("AICommandProcessor", "Plan validation failed for unit %s: %s" % [plan_data.get("unit_id", "N/A"), validation_result.error])

    if processed_plans.size() > 0:
        # Create response with summary for UI
        var enhanced_message = message
        if not summary.is_empty():
            enhanced_message = summary  # Use summary as the primary message for UI
        
        plan_processed.emit(processed_plans, enhanced_message)

func _on_request_timeout(request_id: String) -> void:
    if not active_requests.has(request_id):
        return # Request already handled

    var request_data = active_requests[request_id]
    var context = request_data.context
    var unit_ids = context.get("expected_unit_ids", [])
    var actual_duration = (Time.get_ticks_msec() / 1000.0) - request_data.timestamp
    
    logger.error("AICommandProcessor", "=== REQUEST TIMEOUT ===")
    logger.error("AICommandProcessor", "Request %s for units %s timed out after %.2f seconds (limit: %.2f)" % [request_id, str(unit_ids), actual_duration, max_request_timeout])
    
    active_requests.erase(request_id)
    
    var error_msg = "Request timed out for units %s. Check API connectivity." % str(unit_ids)
    command_failed.emit(error_msg, unit_ids)
    
    if active_requests.is_empty():
        processing_finished.emit()