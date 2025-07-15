# AICommandProcessor.gd
class_name AICommandProcessor
extends Node

# Dependencies
var logger = null
var game_constants = null
var action_validator = null
var openai_client = null
var langsmith_client = null
var selection_manager: EnhancedSelectionSystem = null
var plan_executor: Node = null
var tier_selector: TierSelector = null
var prompt_generator: PromptGenerator = null

# Internal variables
var command_queue: Array[Dictionary] = []
var processing_command: bool = false
var last_game_state: Dictionary = {}
var command_history: Array[String] = []

# Plan execution tracking
var active_plans: Dictionary = {}  # unit_id -> plan_data
var plan_statistics: Dictionary = {
    "total_plans": 0,
    "successful_plans": 0,
    "failed_plans": 0,
    "most_used_actions": {}
}

# Signals
signal command_processed(commands: Array, message: String)
signal plan_processed(plans: Array, message: String)
signal command_failed(error: String)
signal processing_started()
signal processing_finished()
signal plan_execution_started(unit_id: String, plan: Dictionary)
signal plan_execution_completed(unit_id: String, success: bool)

func _ready() -> void:
    # Create AI system components
    var OpenAIClientScript = load("res://scripts/ai/openai_client.gd")
    openai_client = OpenAIClientScript.new()
    openai_client.name = "OpenAI_Client"
    add_child(openai_client)

    # Create tier selector and prompt generator
    var TierSelectorClass = load("res://scripts/ai/tier_selector.gd")
    tier_selector = TierSelectorClass.new()
    var PromptGeneratorClass = load("res://scripts/ai/prompt_generator.gd")
    prompt_generator = PromptGeneratorClass.new()
    
    # Setup LangSmith client if available (defer to ensure DependencyContainer is ready)
    call_deferred("_setup_langsmith_client")
    
    # Create plan executor
    var PlanExecutorScript = load("res://scripts/ai/plan_executor.gd")
    plan_executor = PlanExecutorScript.new()
    plan_executor.name = "PlanExecutor"
    add_child(plan_executor)
    
    # Connect signals
    openai_client.request_completed.connect(_on_openai_response)
    openai_client.request_failed.connect(_on_openai_error)
    
    # Connect plan executor signals
    plan_executor.plan_started.connect(_on_plan_started)
    plan_executor.plan_completed.connect(_on_plan_completed)
    plan_executor.plan_interrupted.connect(_on_plan_interrupted)
    plan_executor.step_executed.connect(_on_step_executed)
    plan_executor.ability_used.connect(_on_ability_used)
    plan_executor.speech_triggered.connect(_on_speech_triggered)
    
    # Logger initialization
    if logger:
        logger.info("AICommandProcessor", "AI command processor initialized with enhanced plan execution")
    else:
        print("AICommandProcessor initialized with enhanced plan execution")

func _setup_langsmith_client() -> void:
    """Setup LangSmith client for observability"""
    # Get LangSmith client from dependency container
    var dependency_container = get_node("/root/DependencyContainer")
    if dependency_container and dependency_container.has_method("get_langsmith_client"):
        langsmith_client = dependency_container.get_langsmith_client()
        if langsmith_client:
            langsmith_client.setup_openai_client(openai_client)
            print("AICommandProcessor: LangSmith observability enabled")
            return
        else:
            print("AICommandProcessor: LangSmith client not ready yet, retrying in 1 second...")
            # Retry after a short delay to allow DependencyContainer to finish initialization
            await get_tree().create_timer(1.0).timeout
            _setup_langsmith_client()
            return
    else:
        print("AICommandProcessor: DependencyContainer not found - LangSmith disabled")

func _collect_game_context_for_tracing(command_text: String, selected_units: Array, game_state: Dictionary) -> Dictionary:
    """Collect comprehensive game context for LangSmith tracing"""
    var context = {
        "command_text": command_text,
        "selected_units_count": selected_units.size(),
        "game_phase": game_state.get("phase", "unknown"),
        "timestamp": Time.get_ticks_msec() / 1000.0
    }
    
    # Add unit information
    if selected_units.size() > 0:
        var unit_types = []
        var unit_ids = []
        for unit in selected_units:
            if unit and unit.has_method("get_unit_type"):
                unit_types.append(unit.get_unit_type())
            if unit and unit.has("name"):
                unit_ids.append(unit.name)
        
        context["unit_types"] = unit_types
        context["unit_ids"] = unit_ids
    
    # Add game state information
    if game_state.has("resources"):
        context["resources"] = game_state.resources
    
    if game_state.has("control_points"):
        context["control_points_controlled"] = game_state.control_points
    
    if game_state.has("match_time"):
        context["match_time"] = game_state.match_time
    
    return context

func setup(logger_instance, game_constants_instance, action_validator_instance, plan_executor_instance) -> void:
    """Setup the AI command processor with dependencies"""
    logger = logger_instance
    game_constants = game_constants_instance
    action_validator = action_validator_instance
    plan_executor = plan_executor_instance

func process_command(command_text: String, selected_units: Array = [], game_state: Dictionary = {}) -> void:
    """
    Process a natural language command
    
    Args:
        command_text: The natural language command from the player
        selected_units: Array of currently selected units
        game_state: Current game state information
    """
    if processing_command:
        print("AICommandProcessor WARNING: Command processor busy, queuing command")
        command_queue.append({
            "text": command_text,
            "units": selected_units,
            "state": game_state
        })
        return
    
    if not processing_command:
        processing_command = true
        processing_started.emit()
        
        # Store game state for context
        last_game_state = game_state
        
        # logger.info("AICommandProcessor", "Processing command: " + command_text)
        if logger:
            logger.info("AICommandProcessor", "Processing command: " + command_text)
        else:
            print("Processing command: " + command_text)
    
    # Store command in history
    command_history.append(command_text)
    if command_history.size() > 10:
        command_history.pop_front()
    
    # Update game state
    last_game_state = game_state
    
    # Determine control tier
    var control_tier = tier_selector.determine_control_tier(selected_units)
    
    # Build context for prompt generator
    var prompt_context = {
        "squad_composition": _build_context(selected_units, game_state).selected_units,
        "game_state": game_state,
        "user_command": command_text
    }

    # Generate the prompt
    var system_prompt = prompt_generator.generate_prompt(control_tier, prompt_context)
    
    # Create messages for OpenAI
    var messages = [
        {
            "role": "system",
            "content": system_prompt
        }
        # The user command is now part of the system prompt context for better LLM performance.
    ]
    
    # Send to OpenAI with LangSmith tracing
    # Logger.info("AICommandProcessor", "Processing command: " + command_text)
    var trace_metadata = _collect_game_context_for_tracing(command_text, selected_units, game_state)
    
    if langsmith_client:
        var trace_id = langsmith_client.traced_chat_completion(messages, _on_openai_response, trace_metadata)
        print("AICommandProcessor: Started LLM call with trace ID: " + trace_id)
    else:
        # Fallback to direct OpenAI call
        openai_client.send_chat_completion(messages, _on_openai_response)

func _on_openai_response(response: Dictionary) -> void:
    """Handle OpenAI API response with enhanced plan processing"""
    processing_command = false
    processing_finished.emit()
    
    # Parse response
    var content = response.get("choices", [{}])[0].get("message", {}).get("content", "")
    
    if content.is_empty():
        command_failed.emit("Empty response from AI")
        return
    
    # Parse JSON response
    var json = JSON.new()
    var parse_result = json.parse(content)
    
    if parse_result != OK:
        command_failed.emit("Invalid JSON response from AI")
        return
    
    var ai_response = json.data
    
    # Handle different response types with enhanced processing
    match ai_response.get("type", ""):
        "direct_commands":
            _process_direct_commands(ai_response)
        "multi_step_plan":
            _process_multi_step_plans(ai_response)
        _:
            command_failed.emit("Unknown response type: " + str(ai_response.get("type", "")))
    
    # Process next command from queue if available
    _process_next_command()

func _on_openai_error(error_type: int, error_message: String) -> void:
    """Handle OpenAI API errors gracefully"""
    processing_command = false
    processing_finished.emit()
    
    # Log error details
    if logger:
        logger.error("AICommandProcessor", "OpenAI API Error [%d]: %s" % [error_type, error_message])
    else:
        print("AICommandProcessor Error [%d]: %s" % [error_type, error_message])
    
    # Emit command failed with user-friendly message
    var user_message = _format_user_error_message(error_type, error_message)
    command_failed.emit(user_message)
    
    # Process next command from queue if available
    _process_next_command()

func _format_user_error_message(error_type: int, error_message: String) -> String:
    """Format error messages for user display"""
    match error_type:
        1: # INVALID_API_KEY
            return "AI service configuration error. Please check API key settings."
        2: # RATE_LIMITED  
            return "AI service is temporarily busy. Please try again in a moment."
        3: # QUOTA_EXCEEDED
            return "AI service quota exceeded. Please contact administrator."
        4: # NETWORK_ERROR
            return "Network error connecting to AI service. Please check connection."
        _: # UNKNOWN_ERROR
            if "API key" in error_message:
                return "AI service configuration error. Please check API key settings."
            else:
                return "AI service error: %s" % error_message

func _process_direct_commands(ai_response: Dictionary) -> void:
    """Process direct commands"""
    var commands = ai_response.get("commands", [])
    var message = ai_response.get("message", "Executing commands")
    
    if commands.is_empty():
        command_failed.emit("No commands provided")
        return
    
    var processed_commands = []
    var failed_commands = []
    
    for command_data in commands:
        var action = command_data.get("action", "")
        var target_units = command_data.get("target_units", [])
        var params = command_data.get("parameters", {})
        
        if action.is_empty() or target_units.is_empty():
            failed_commands.append(command_data)
            continue
        
        # Validate and enhance command
        var enhanced_command = _enhance_command_data(command_data)
        
        # Execute command using enhanced action validator
        if action_validator.validate_command(enhanced_command):
            processed_commands.append(enhanced_command)
            # if plan_executor: # Temporarily commented out
            #     plan_executor.execute_command(enhanced_command)
            # else:
            #     Logger.warning("AICommandProcessor", "Plan executor not available, skipping command execution.")
            print("AICommandProcessor INFO: Command validated and executed: " + str(enhanced_command))
        else:
            failed_commands.append(command_data)
    
    if processed_commands.size() > 0:
        command_processed.emit(processed_commands, message)
        
        if logger:
            logger.info("AICommandProcessor", "Started %d direct commands" % processed_commands.size())
    
    if failed_commands.size() > 0:
        command_failed.emit("Failed to execute %d commands" % failed_commands.size())

func _enhance_command_data(command_data: Dictionary) -> Dictionary:
    """Enhance command data with additional context and validation"""
    var enhanced_command = command_data.duplicate(true)
    
    # Add command metadata
    enhanced_command["command_id"] = "cmd_" + str(Time.get_ticks_msec())
    enhanced_command["created_at"] = Time.get_ticks_msec() / 1000.0
    enhanced_command["context"] = last_game_state.duplicate()
    
    # Validate action-specific parameters
    _validate_action_parameters(enhanced_command)
    
    return enhanced_command

func _process_multi_step_plans(ai_response: Dictionary) -> void:
    """Process multi-step plans with enhanced validation and execution"""
    var plans = ai_response.get("plans", [])
    var message = ai_response.get("message", "Executing tactical plans")
    
    if plans.is_empty():
        command_failed.emit("No plans provided")
        return
    
    var processed_plans = []
    var failed_plans = []
    
    for plan_data in plans:
        var unit_id = plan_data.get("unit_id", "")
        var steps = plan_data.get("steps", [])
        
        if unit_id.is_empty() or steps.is_empty():
            failed_plans.append(plan_data)
            continue
        
        # Validate and enhance plan
        var enhanced_plan = _enhance_plan_data(plan_data)
        
        # Execute plan using enhanced plan executor
        if plan_executor.execute_plan(unit_id, enhanced_plan):
            processed_plans.append(enhanced_plan)
            active_plans[unit_id] = enhanced_plan
            plan_statistics.total_plans += 1
            plan_execution_started.emit(unit_id, enhanced_plan)
        else:
            failed_plans.append(plan_data)
    
    if processed_plans.size() > 0:
        plan_processed.emit(processed_plans, message)
        
        if logger:
            logger.info("AICommandProcessor", "Started %d enhanced tactical plans" % processed_plans.size())
    
    if failed_plans.size() > 0:
        command_failed.emit("Failed to execute %d plans" % failed_plans.size())

func _enhance_plan_data(plan_data: Dictionary) -> Dictionary:
    """Enhance plan data with additional context and validation"""
    var enhanced_plan = plan_data.duplicate(true)
    
    # Add plan metadata
    enhanced_plan["plan_id"] = "plan_" + str(Time.get_ticks_msec())
    enhanced_plan["created_at"] = Time.get_ticks_msec() / 1000.0
    enhanced_plan["context"] = last_game_state.duplicate()
    
    # Enhance individual steps
    var enhanced_steps = []
    for i in range(plan_data.get("steps", []).size()):
        var step = plan_data.get("steps", [])[i]
        var enhanced_step = _enhance_step_data(step, i)
        enhanced_steps.append(enhanced_step)
    
    enhanced_plan["steps"] = enhanced_steps
    
    return enhanced_plan

func _enhance_step_data(step_data: Dictionary, index: int) -> Dictionary:
    """Enhance individual step data with validation and defaults"""
    var enhanced_step = step_data.duplicate(true)
    
    # Add step metadata
    enhanced_step["step_id"] = "step_%d_%d" % [index, Time.get_ticks_msec()]
    enhanced_step["step_index"] = index
    
    # Ensure required fields have defaults
    if not enhanced_step.has("duration_ms"):
        enhanced_step["duration_ms"] = 0
    
    if not enhanced_step.has("trigger"):
        enhanced_step["trigger"] = ""
    
    if not enhanced_step.has("speech"):
        enhanced_step["speech"] = ""
    
    if not enhanced_step.has("priority"):
        enhanced_step["priority"] = 0
    
    if not enhanced_step.has("prerequisites"):
        enhanced_step["prerequisites"] = []
    
    if not enhanced_step.has("cooldown"):
        enhanced_step["cooldown"] = 0.0
    
    # Validate action-specific parameters
    _validate_action_parameters(enhanced_step)
    
    return enhanced_step

func _validate_action_parameters(step: Dictionary) -> void:
    """Validate and set defaults for action-specific parameters"""
    var action = step.get("action", "")
    var params = step.get("params", {})
    
    match action:
        "peek_and_fire":
            # Ensure sniper-specific cooldown
            if step.get("cooldown", 0.0) == 0.0:
                step["cooldown"] = 3.0
        
        "lay_mines":
            # Ensure mine count parameter
            if not params.has("count"):
                params["count"] = 1
        
        "stealth":
            # Ensure stealth duration
            if not params.has("duration"):
                params["duration"] = 10.0
        
        "overwatch":
            # Ensure overwatch duration
            if not params.has("duration"):
                params["duration"] = 15.0
        
        "heal":
            # Ensure heal prerequisites
            if step.get("prerequisites", []).is_empty():
                step["prerequisites"] = ["health_pct > 10"]
        
        "charge":
            # Ensure charge cooldown
            if step.get("cooldown", 0.0) == 0.0:
                step["cooldown"] = 8.0
        
        "hijack_spire":
            # Ensure hijack duration and cooldown
            if step.get("cooldown", 0.0) == 0.0:
                step["cooldown"] = 20.0
    
    step["params"] = params

func _parse_ai_response(content: String) -> Dictionary:
    """Parse AI response JSON"""
    var json = JSON.new()
    var parse_result = json.parse(content)
    
    if parse_result != OK:
        return {"success": false, "error": "Invalid JSON: " + content}
    
    var data = json.data
    if not data is Dictionary:
        return {"success": false, "error": "Response is not a dictionary"}
    
    return {"success": true, "data": data}

func _build_context(selected_units: Array, game_state: Dictionary) -> Dictionary:
    """Build context for AI processing"""
    var context = {
        "game_state": game_state,
        "selected_units": [],
        "all_units": []
    }
    
    # Add selected units info
    for unit in selected_units:
        if unit and unit.has_method("get_unit_id"):
            context.selected_units.append({
                "unit_id": unit.get_unit_id(),
                "archetype": unit.get("archetype", "unknown"),
                "position": unit.global_position,
                "health": unit.get_health_percentage(),
                "state": unit.get_current_state() if unit.has_method("get_current_state") else "unknown"
            })
    
    # Add all units info (for tactical awareness)
    var all_units = get_tree().get_nodes_in_group("units")
    for unit in all_units:
        if unit and unit.has_method("get_unit_id"):
            context.all_units.append({
                "unit_id": unit.get_unit_id(),
                "archetype": unit.get("archetype") if unit.has_method("get") and "archetype" in unit else "unknown",
                "team_id": unit.get_team_id(),
                "position": unit.global_position,
                "health": unit.get_health_percentage(),
                "state": unit.get_current_state() if unit.has_method("get_current_state") else "unknown"
            })
    
    return context

func _get_selected_units() -> Array:
    """Get currently selected units"""
    if selection_manager:
        return selection_manager.get_selected_units()
    else:
        # Try to find selection manager
        var game_controller = get_tree().get_first_node_in_group("game_controller")
        if game_controller and game_controller.has_method("get_selection_manager"):
            selection_manager = game_controller.get_selection_manager()
            if selection_manager:
                return selection_manager.get_selected_units()
    
    return []

func _handle_error(error_message: String) -> void:
    """Handle processing error"""
    print("AICommandProcessor ERROR: " + error_message)
    processing_command = false
    processing_finished.emit()
    command_failed.emit(error_message)
    _process_next_command()

func _process_next_command() -> void:
    """Process next command from queue if available"""
    if command_queue.size() > 0 and not processing_command:
        var next_command = command_queue.pop_front()
        process_command(next_command.text, next_command.units, next_command.state)

# Plan execution event handlers
func _on_plan_started(unit_id: String, plan: Array) -> void:
    """Handle plan execution started"""
    if logger:
        logger.info("AICommandProcessor", "Plan execution started for unit %s with %d steps" % [unit_id, plan.size()])

func _on_plan_completed(unit_id: String, success: bool) -> void:
    """Handle plan execution completed"""
    if active_plans.has(unit_id):
        active_plans.erase(unit_id)
    
    if success:
        plan_statistics.successful_plans += 1
    else:
        plan_statistics.failed_plans += 1
    
    plan_execution_completed.emit(unit_id, success)
    
    if logger:
        logger.info("AICommandProcessor", "Plan execution completed for unit %s (success: %s)" % [unit_id, success])

func _on_plan_interrupted(unit_id: String, reason: String) -> void:
    """Handle plan execution interrupted"""
    if active_plans.has(unit_id):
        active_plans.erase(unit_id)
    
    plan_statistics.failed_plans += 1
    
    if logger:
        logger.warning("AICommandProcessor", "Plan execution interrupted for unit %s: %s" % [unit_id, reason])

func _on_step_executed(unit_id: String, step) -> void:
    """Handle individual step execution"""
    var action = step.action if step.has("action") else "unknown"
    
    # Update action statistics
    if not plan_statistics.most_used_actions.has(action):
        plan_statistics.most_used_actions[action] = 0
    plan_statistics.most_used_actions[action] += 1
    
    if logger:
        logger.debug("AICommandProcessor", "Step executed for unit %s: %s" % [unit_id, action])

func _on_ability_used(unit_id: String, ability: String, success: bool) -> void:
    """Handle ability usage"""
    if logger:
        logger.info("AICommandProcessor", "Ability '%s' used by unit %s (success: %s)" % [ability, unit_id, success])

func _on_speech_triggered(unit_id: String, speech: String) -> void:
    """Handle speech bubble triggered"""
    if logger:
        logger.debug("AICommandProcessor", "Unit %s says: %s" % [unit_id, speech])

# Enhanced public interface
func get_command_history() -> Array[String]:
    """Get recent command history"""
    return command_history.duplicate()

func clear_command_queue() -> void:
    """Clear all queued commands"""
    command_queue.clear()
    if logger:
        logger.info("AICommandProcessor", "Command queue cleared")
    else:
        print("Command queue cleared")

func is_command_processing() -> bool:
    """Check if currently processing a command"""
    return processing_command

func get_queue_size() -> int:
    """Get number of queued commands"""
    return command_queue.size()

func get_active_plans() -> Dictionary:
    """Get all active plans"""
    return active_plans.duplicate()

func get_plan_statistics() -> Dictionary:
    """Get plan execution statistics"""
    var stats = plan_statistics.duplicate()
    
    # Calculate success rate
    var total_plans = plan_statistics.total_plans
    if total_plans > 0:
        stats["success_rate"] = float(plan_statistics.successful_plans) / float(total_plans) * 100.0
    else:
        stats["success_rate"] = 0.0
    
    return stats

func interrupt_plan(unit_id: String, reason: String = "user_requested") -> bool:
    """Interrupt an active plan"""
    if active_plans.has(unit_id) and plan_executor:
        plan_executor.interrupt_plan(unit_id, reason)
        return true
    return false

func interrupt_all_plans() -> void:
    """Interrupt all active plans"""
    for unit_id in active_plans:
        interrupt_plan(unit_id, "all_plans_interrupted")

func get_plan_progress(unit_id: String) -> Dictionary:
    """Get detailed progress information for a unit's plan"""
    if plan_executor:
        return plan_executor.get_plan_progress(unit_id)
    return {}

func get_execution_stats() -> Dictionary:
    """Get detailed execution statistics from plan executor"""
    if plan_executor:
        return plan_executor.get_execution_stats()
    return {} 