# AICommandProcessor.gd
class_name AICommandProcessor
extends Node

# Dependencies
var logger = null
var game_constants = null
var action_validator = null
var openai_client = null
var selection_manager: SelectionManager = null
# var plan_executor: PlanExecutor = null

# Command processing settings
@export var system_prompt_template: String = """
You are an AI assistant for a cooperative Real-Time Strategy (RTS) game. 
Players can give you natural language commands to control units.

GAME CONTEXT:
- This is a 2v2 cooperative RTS where teammates share control of 5 units
- Unit types: scout, sniper, medic, engineer, tank
- Players can select units and give movement, attack, and ability commands
- Units have different capabilities and roles

COMMAND MODES:
You can respond with either DIRECT COMMANDS or MULTI-STEP PLANS.

DIRECT COMMANDS (for simple actions):
{
    "type": "direct_commands",
    "commands": [
        {
            "action": "MOVE|ATTACK|FOLLOW|PATROL|STOP|USE_ABILITY|FORMATION|STANCE",
            "target_units": ["selected"|"all"|"type:scout"|"unit_id"],
            "parameters": {
                "position": [x, y, z],
                "target_id": "unit_id",
                "formation": "line|column|wedge|scattered",
                "stance": "aggressive|defensive|passive"
            }
        }
    ],
    "message": "Confirmation message"
}

MULTI-STEP PLANS (for complex tactical sequences):
{
    "type": "multi_step_plan",
    "plans": [
        {
            "unit_id": "unit_id",
            "steps": [
                {
                    "action": "move_to|attack|peek_and_fire|lay_mines|retreat|formation|stance",
                    "params": {
                        "position": [x, y, z],
                        "target_id": "unit_id",
                        "formation": "line|column|wedge|scattered"
                    },
                    "duration_ms": 2000,
                    "trigger": "health_pct < 20|enemy_dist < 10|time > 3",
                    "speech": "Moving to cover (max 12 words)",
                    "conditions": {}
                }
            ]
        }
    ],
    "message": "Plan description"
}

CURRENT GAME STATE:
{game_state}

SELECTED UNITS:
{selected_units}

Use DIRECT COMMANDS for simple actions like "attack that unit" or "move here".
Use MULTI-STEP PLANS for complex tactical sequences like "scout ahead, then attack if safe" or "retreat if health is low".

Parse the following command:
"""

# Internal variables
var command_queue: Array[Dictionary] = []
var processing_command: bool = false
var last_game_state: Dictionary = {}
var command_history: Array[String] = []

# Signals
signal command_processed(commands: Array, message: String)
signal plan_processed(plans: Array, message: String)
signal command_failed(error: String)
signal processing_started()
signal processing_finished()

func _ready() -> void:
    # Create OpenAI client
    var OpenAIClientScript = load("res://scripts/ai/openai_client.gd")
    openai_client = OpenAIClientScript.new()
    openai_client.name = "OpenAIClient"
    add_child(openai_client)
    
    # Create plan executor
    # plan_executor = PlanExecutor.new()
    # plan_executor.name = "PlanExecutor"
    # add_child(plan_executor)
    
    # Connect signals
    openai_client.request_completed.connect(_on_openai_response)
    openai_client.request_failed.connect(_on_openai_error)
    
    # Connect plan executor signals
    # plan_executor.plan_started.connect(_on_plan_started)
    # plan_executor.plan_completed.connect(_on_plan_completed)
    # plan_executor.plan_interrupted.connect(_on_plan_interrupted)
    # plan_executor.step_executed.connect(_on_step_executed)
    
    # Logger.info("AICommandProcessor", "AI command processor initialized with plan execution")
    if logger:
        logger.info("AICommandProcessor", "AI command processor initialized with plan execution")
    else:
        print("AI command processor initialized")

func setup(logger_instance, game_constants_instance, action_validator_instance, plan_executor_instance) -> void:
    """Setup the AI command processor with dependencies"""
    logger = logger_instance
    game_constants = game_constants_instance
    action_validator = action_validator_instance
    # plan_executor = plan_executor_instance

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
    # Logger.info("AICommandProcessor", "Processing command: " + command_text)
    openai_client.send_chat_completion(messages, _on_openai_response)

func _on_openai_response(response: Dictionary) -> void:
    """Handle OpenAI response"""
    processing_command = false
    processing_finished.emit()
    
    if not response.has("choices") or response.choices.size() == 0:
        _handle_error("Invalid OpenAI response format")
        return
    
    var content = response.choices[0].message.content
    var parsed_response = _parse_ai_response(content)
    
    if not parsed_response.success:
        _handle_error("Failed to parse AI response: " + parsed_response.error)
        return
    
    var ai_data = parsed_response.data
    var response_type = ai_data.get("type", "direct_commands")
    
    match response_type:
        "direct_commands":
            _handle_direct_commands(ai_data)
        "multi_step_plan":
            _handle_multi_step_plans(ai_data)
        _:
            _handle_error("Unknown response type: " + response_type)
    
    # Process next command in queue
    _process_next_command()

func _handle_direct_commands(ai_data: Dictionary) -> void:
    """Handle direct command execution"""
    var commands = ai_data.get("commands", [])
    var message = ai_data.get("message", "Executing commands")
    
                    if logger:
            logger.info("AICommandProcessor", "Processing %d direct commands" % commands.size())
        else:
            print("Processing %d direct commands" % commands.size())
    
    # Emit for command translator to handle
    command_processed.emit(commands, message)

func _handle_multi_step_plans(ai_data: Dictionary) -> void:
    """Handle multi-step plan execution"""
    var plans = ai_data.get("plans", [])
    var message = ai_data.get("message", "Executing tactical plans")
    
                    if logger:
            logger.info("AICommandProcessor", "Processing %d multi-step plans" % plans.size())
        else:
            print("Processing %d multi-step plans" % plans.size())
    
    # Execute each plan
    var successful_plans = []
    for plan in plans:
        var unit_id = plan.get("unit_id", "")
        if unit_id == "" and plan.has("steps"):
            # Try to assign to first selected unit
            var selected_units = _get_selected_units()
            if selected_units.size() > 0:
                unit_id = selected_units[0].get("unit_id", selected_units[0].name)
        
        if unit_id != "":
            # if plan_executor.execute_plan(unit_id, plan): # Temporarily commented out
            #     successful_plans.append(plan)
            # else:
            #     Logger.warning("AICommandProcessor", "Failed to execute plan for unit: %s" % unit_id)
            Logger.warning("AICommandProcessor", "Plan execution temporarily disabled. Skipping plan for unit: %s" % unit_id)
    
    if successful_plans.size() > 0:
        plan_processed.emit(successful_plans, message)
    else:
        _handle_error("No plans could be executed")

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
                "archetype": unit.get("archetype", "unknown"),
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
    Logger.error("AICommandProcessor", error_message)
    processing_command = false
    processing_finished.emit()
    command_failed.emit(error_message)
    _process_next_command()

func _on_openai_error(error: String) -> void:
    """Handle OpenAI error"""
    _handle_error("OpenAI request failed: " + error)

# Plan executor signal handlers
func _on_plan_started(unit_id: String, plan: Array) -> void:
    """Handle plan start"""
    if logger:
        logger.info("AICommandProcessor", "Plan started for unit %s with %d steps" % [unit_id, plan.size()])
    else:
        print("Plan started for unit %s with %d steps" % [unit_id, plan.size()])

func _on_plan_completed(unit_id: String, success: bool) -> void:
    """Handle plan completion"""
    var status = "successfully" if success else "with errors"
    if logger:
        logger.info("AICommandProcessor", "Plan completed %s for unit %s" % [status, unit_id])
    else:
        print("Plan completed %s for unit %s" % [status, unit_id])

func _on_plan_interrupted(unit_id: String, reason: String) -> void:
    """Handle plan interruption"""
    if logger:
        logger.info("AICommandProcessor", "Plan interrupted for unit %s: %s" % [unit_id, reason])
    else:
        print("Plan interrupted for unit %s: %s" % [unit_id, reason])

func _on_step_executed(unit_id: String, step) -> void: # step: PlanExecutor.PlanStep
    """Handle step execution"""
    if logger:
        logger.info("AICommandProcessor", "Step executed for unit %s: %s" % [unit_id, step.action])
    else:
        print("Step executed for unit %s: %s" % [unit_id, step.action])
    
    # Show speech bubble if specified
    if step.speech != "":
        if logger:
            logger.info("AICommandProcessor", "Unit %s says: %s" % [unit_id, step.speech])
        else:
            print("Unit %s says: %s" % [unit_id, step.speech])

func _process_next_command() -> void:
    """Process next command in queue"""
    if command_queue.is_empty():
        return
    
    var next_command = command_queue.pop_front()
    process_command(next_command.text, next_command.units, next_command.state)

# Public interface
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
    # if plan_executor: # Temporarily commented out
    #     return plan_executor.get_active_plans()
    return {}

func interrupt_plan(unit_id: String, reason: String = "user_interrupt") -> bool:
    """Interrupt an active plan"""
    # if plan_executor and plan_executor.has_active_plan(unit_id): # Temporarily commented out
    #     plan_executor.interrupt_plan(unit_id, reason)
    #     return true
    return false

func get_plan_progress(unit_id: String) -> Dictionary:
    """Get plan progress for a unit"""
    # if plan_executor: # Temporarily commented out
    #     return plan_executor.get_plan_progress(unit_id)
    return {} 