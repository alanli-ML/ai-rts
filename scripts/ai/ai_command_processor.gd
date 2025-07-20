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

# Model configuration
# Recommended: gpt-4o-mini for speed, gpt-4o for complex strategy
var command_model: String = "gpt-4o-mini"

func _get_base_system_prompt_template(team_id: int) -> String:
    """Generate team-specific system prompt with correct base locations"""
    var my_base_location: String
    var enemy_base_location: String
    var enemy_team_id: int
    
    if team_id == 1:
        my_base_location = "Far Northwest"
        enemy_base_location = "Far Southeast"
        enemy_team_id = 2
    else:  # team_id == 2
        my_base_location = "Far Southeast"
        enemy_base_location = "Far Northwest"
        enemy_team_id = 1
    
    return """
You are an AI commander for a 2v2 cooperative RTS game.
Your task is to translate a player's natural language command into a high-level strategic plan by assigning objectives to EACH unit.

The map has nine control points in a 3x3 grid: `Northwest`, `North`, `Northeast`, `West`, `Center`, `East`, `Southwest`, `South`, `Southeast`.
Your base (Team %d) is located in the %s. The enemy base (Team %d) is in the %s.

Based on the player's command and the provided game context, you must create a plan for EACH unit listed in `allied_units`. For each unit, you must define:
1.  **Goal**: A high-level `goal` describing the unit's objective (e.g., "Lead the main assault", "Support the tank").
2.  **Objectives**: A `control_point_attack_sequence` using the available control point names. This is the ordered list of objectives for the unit.
3.  **Tactical Personality**: A `primary_state_priority_list`. This is an ordered list of the four primary states: `attack`, `defend`, `retreat`, `follow`. The order determines the unit's behavior.

**TACTICAL PERSONALITY EXAMPLES:**
- **Aggressive Assault**: `["attack", "defend", "follow", "retreat"]` (Prioritizes attacking enemies and objectives).
- **Cautious Defense**: `["defend", "retreat", "follow", "attack"]` (Prioritizes holding ground and retreating from danger).
- **Support & Follow**: `["follow", "defend", "retreat", "attack"]` (Prioritizes sticking with allies).

Your response must be valid JSON containing a list of plans, one for each unit.

**EXAMPLE JSON RESPONSE:**
```json
{
  "plans": [
    {
      "unit_id": "tank_t%d_01",
      "goal": "Lead the main assault on the central control points.",
      "control_point_attack_sequence": ["Center", "East", "Southeast"],
      "primary_state_priority_list": ["attack", "defend", "follow", "retreat"]
    },
    {
      "unit_id": "medic_t%d_01",
      "goal": "Support the tank in the main assault.",
      "control_point_attack_sequence": ["Center", "East", "Southeast"],
      "primary_state_priority_list": ["follow", "defend", "retreat", "attack"]
    },
    {
      "unit_id": "scout_t%d_01",
      "goal": "Flank west to capture weakly defended points.",
      "control_point_attack_sequence": ["West", "Southwest"],
      "primary_state_priority_list": ["attack", "follow", "defend", "retreat"]
    }
  ],
  "message": "Assaulting the center with the main force while the scout flanks west.",
  "summary": "Main assault and west flank."
}
```

**STRATEGIC GUIDANCE:**
- Your primary goal is to interpret the player's intent and translate it into an effective tactical personality and objective sequence for EACH unit.
- You do not control unit abilities like shields or stealth; they are activated automatically. Your focus is on the four primary states.
- The `control_point_attack_sequence` should be a logical path for the unit to follow to achieve its goal. Units working together should have similar sequences.

**GAME CONTEXT PROVIDED:**
You will receive a `game_context` object with the following information:
- `global_state`: Contains `controlled_nodes` (e.g., {"ours": ["Center", "West"], "enemy": ["East", "Southeast"], "neutral": ["North", "Northeast", "Southwest"]} listing the actual node names controlled by each team) and current `game_time_sec`.
- `allied_units`: A list of all units you are commanding, including their `id`, `archetype`, `health_pct`, `position` (world coordinates), and current `strategic_goal`.
- `sensor_data`: A combined view of all `visible_enemies` and `visible_control_points` from your units' perspectives.

Use this context to make informed strategic decisions. For example, a tank should have an aggressive personality (`attack` first), while a medic supporting it should have a supportive personality (`follow` first). If a unit is low on health, its personality should prioritize `retreat` or `defend`.
""" % [team_id, my_base_location, enemy_team_id, enemy_base_location, team_id, team_id, team_id]

#EXAMPLE PLAN STRUCTURE{example_suffix}:
#- unit_id: Unique identifier for the unit
#- goal: High-level objective like "Secure the northern sector and provide overwatch"
#- steps: Sequential actions like move_to, patrol, attack
#- triggered_actions: A dictionary of pre-defined conditional responses, like `"on_health_critical": "retreat"`.

# Signals
signal plan_processed(plans: Array, message: String, originating_peer_id: int)
signal command_failed(error: String, unit_ids: Array, originating_peer_id: int)
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
func set_command_model(model: String) -> void:
    """Set the model to use for commands"""
    command_model = model

func get_model_configuration() -> Dictionary:
    """Get current model configuration"""
    return {
        "command_model": command_model
    }

func _build_source_info(units: Array) -> String:
    """Build source information for LangSmith tracing (e.g., 'player1/Tank' or 'player2/Group_3units')"""
    if units.is_empty():
        return "unknown"
    
    var first_unit = units[0]
    var team_name = "player%d" % first_unit.team_id
    
    if units.size() > 1:
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
        # For single unit commands, show specific unit archetype
        var archetype = first_unit.archetype.capitalize()
        return "%s/%s" % [team_name, archetype]

func process_command(command_text: String, unit_ids: Array = [], peer_id: int = -1) -> void:
    if active_requests.size() >= max_concurrent_requests:
        logger.warning("AICommandProcessor", "Max concurrent requests reached (%d). Dropping new command for units %s." % [max_concurrent_requests, str(unit_ids)])
        command_failed.emit("AI service is busy. Please try again.", unit_ids, peer_id)
        return

    if active_requests.is_empty():
        processing_started.emit()

    request_id_counter += 1
    var request_id = "req_%d" % request_id_counter
    
    var server_game_state = get_node("/root/DependencyContainer").get_game_state()
    if not server_game_state:
        logger.error("AICommandProcessor", "ServerGameState not found - command failed")
        command_failed.emit("ServerGameState not found.", [], peer_id)
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
        command_failed.emit("No valid units found for command.", [], peer_id)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    var unit_list = []
    for unit in selected_units:
        unit_list.append(unit.unit_id)
    
    logger.info("AICommandProcessor", "Processing command for units %s: '%s'" % [str(unit_list), command_text])
    
    var context = {"expected_unit_ids": unit_list, "originating_peer_id": peer_id}
    var start_time = Time.get_ticks_msec() / 1000.0
    active_requests[request_id] = {
        "context": context,
        "timestamp": start_time
    }
    
    logger.info("AICommandProcessor", "Starting request %s at %f for units %s" % [request_id, start_time, str(unit_list)])
    
    # All commands are now processed as group commands to allow the LLM to decide on groupings.
    _process_group_command(command_text, selected_units, server_game_state, request_id)

func _process_group_command(command_text: String, units: Array, server_game_state: Node, request_id: String) -> void:
    # Determine the team ID from the units
    var team_id = 1  # Default to team 1
    if not units.is_empty() and is_instance_valid(units[0]):
        team_id = units[0].team_id
    
    # Generate team-specific system prompt
    var system_prompt = _get_base_system_prompt_template(team_id)
    
    var game_context = server_game_state.get_group_context_for_ai(units)
    
    # The user prompt is now concise, containing only the command and the context data.
    var user_prompt = """
Player Command: "%s"

Game Context:
%s
""" % [command_text, JSON.stringify({"game_context": game_context}, "  ")] # Use indentation for readability

    var messages = [
        {"role": "system", "content": system_prompt},
        {"role": "user", "content": user_prompt}
    ]
    
    # Define callbacks
    var on_response = func(response):
        _on_openai_response(response, request_id)
    var on_error = func(error_type, error_message):
        _on_openai_error(error_type, error_message, request_id)
        
    # Create source metadata for tracing
    var source_info = _build_source_info(units)
    var metadata = {"source": source_info}
    
    if langsmith_client:
        # The schema is now defined directly in the prompt, so we don't pass a response_format.
        langsmith_client.traced_chat_completion(messages, on_response, on_error, metadata, command_model)
    else:
        logger.error("AICommandProcessor", "LangSmith client not available.")
        var unit_ids = active_requests[request_id].context.get("expected_unit_ids", [])
        var peer_id_for_error = active_requests[request_id].context.get("originating_peer_id", -1)
        active_requests.erase(request_id)
        command_failed.emit("AI service not configured.", unit_ids, peer_id_for_error)
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
        var originating_peer_id = context.get("originating_peer_id", -1)
        command_failed.emit(error_message, unit_ids, originating_peer_id)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
    
    if content.is_empty():
        logger.error("AICommandProcessor", "Empty response from AI - check API connectivity and rate limits")
        var unit_ids = context.get("expected_unit_ids", [])
        var originating_peer_id = context.get("originating_peer_id", -1)
        command_failed.emit("Empty response from AI - please try again or check service status", unit_ids, originating_peer_id)
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
        var originating_peer_id = context.get("originating_peer_id", -1)
        command_failed.emit("JSON parsing error: " + json.get_error_message(), unit_ids, originating_peer_id)
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
        var originating_peer_id = context.get("originating_peer_id", -1)
        command_failed.emit("Invalid plan structure from AI", unit_ids, originating_peer_id)
        if active_requests.is_empty():
            processing_finished.emit()
        return
    
    # Validate that all units in the command received a plan.
    var received_unit_ids = []
    for plan_data in ai_response.plans:
        var unit_id = plan_data.get("unit_id", "")
        if not unit_id.is_empty() and not received_unit_ids.has(unit_id):
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
            var originating_peer_id = context.get("originating_peer_id", -1)
            command_failed.emit("Received plans for fewer units than expected. Missing plans for: %s" % str(missing_unit_ids), unit_ids, originating_peer_id)
            if active_requests.is_empty():
                processing_finished.emit()
            return
    
    logger.info("AICommandProcessor", "Response received successfully for units %s" % str(received_unit_ids))
    logger.info("AICommandProcessor", "Plans count: %d, Message: '%s', Summary: '%s'" % [ai_response.plans.size(), ai_response.get("message", ""), ai_response.get("summary", "")])
    
    var originating_peer_id = context.get("originating_peer_id", -1)
    _process_behavior_plans(ai_response, originating_peer_id)
    
    if active_requests.is_empty():
        processing_finished.emit()

func _on_openai_error(error_type: int, error_message: String, request_id: String) -> void:
    if not active_requests.has(request_id):
        return # Request already timed out or handled
    
    var context = active_requests[request_id].context
    var unit_ids = context.get("expected_unit_ids", [])
    var originating_peer_id = context.get("originating_peer_id", -1)
    active_requests.erase(request_id)
    
    var error_msg = "AI service error for units %s: %s" % [str(unit_ids), error_message]
    logger.error("AICommandProcessor", "%s (%s)" % [error_msg, str(error_type)])
    command_failed.emit(error_msg, unit_ids, originating_peer_id)

    if active_requests.is_empty():
        processing_finished.emit()

func _process_behavior_plans(ai_response: Dictionary, originating_peer_id: int = -1) -> void:
    var plans = ai_response.get("plans", [])
    var message = ai_response.get("message", "Executing tactical plans")
    var summary = ai_response.get("summary", "")
    
    if plans.is_empty():
        command_failed.emit("No plans provided", [], originating_peer_id)
        return
    
    var processed_plans = []
    var game_state = get_node("/root/DependencyContainer").get_game_state()
    if not game_state:
        logger.error("AICommandProcessor", "Cannot process plans, game_state not found.")
        return

    for plan_data in plans:
        # The plan is now for a group, so we don't need a unit archetype for validation
        var validation_result = action_validator.validate_plan(plan_data)
        if validation_result.valid:
            # Add summary to plan data for UI display
            if not summary.is_empty():
                plan_data["summary"] = summary

            # The new execute_plan handles the group
            if plan_executor.execute_plan(plan_data):
                processed_plans.append(plan_data)
            else:
                var unit_ids_str = str(plan_data.get("unit_ids", []))
                if logger: logger.warning("AICommandProcessor", "Plan execution failed for units %s" % unit_ids_str)
        else:
            var unit_ids_str = str(plan_data.get("unit_ids", "N/A"))
            if logger: logger.warning("AICommandProcessor", "Plan validation failed for units %s: %s" % [unit_ids_str, validation_result.error])

    if not processed_plans.is_empty():
        # Create response with summary for UI
        var enhanced_message = message
        if not summary.is_empty():
            enhanced_message = summary  # Use summary as the primary message for UI
        
        plan_processed.emit(processed_plans, enhanced_message, originating_peer_id)

func _on_request_timeout(request_id: String) -> void:
    if not active_requests.has(request_id):
        return # Request already handled

    var request_data = active_requests[request_id]
    var context = request_data.context
    var unit_ids = context.get("expected_unit_ids", [])
    var originating_peer_id = context.get("originating_peer_id", -1)
    var actual_duration = (Time.get_ticks_msec() / 1000.0) - request_data.timestamp
    
    logger.error("AICommandProcessor", "=== REQUEST TIMEOUT ===")
    logger.error("AICommandProcessor", "Request %s for units %s timed out after %.2f seconds (limit: %.2f)" % [request_id, str(unit_ids), actual_duration, max_request_timeout])
    
    active_requests.erase(request_id)
    
    var error_msg = "Request timed out for units %s. Check API connectivity." % str(unit_ids)
    command_failed.emit(error_msg, unit_ids, originating_peer_id)
    
    if active_requests.is_empty():
        processing_finished.emit()