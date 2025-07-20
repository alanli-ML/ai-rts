# PlanExecutor.gd
class_name PlanExecutor
extends Node

const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

var game_state: Node
var logger: Node

signal plan_started(unit_id: String, plan: Dictionary)
signal plan_completed(unit_id: String, success: bool) # Kept for potential future use
signal plan_interrupted(unit_id: String, reason: String)
signal speech_triggered(unit_id: String, speech: String) # Kept for potential future use
signal trigger_evaluated(unit_id: String, trigger: String, result: bool) # Kept for UI
signal unit_became_idle(unit_id: String)

func setup(p_logger, p_game_state):
    logger = p_logger
    game_state = p_game_state

func _process(_delta: float):
    # The new design moves all execution logic to the Unit itself.
    # The PlanExecutor is now just a goal-setter. It no longer needs to process anything per frame.
    pass

func execute_plan(plan_data: Dictionary) -> bool:
    var unit_id = plan_data.get("unit_id", "")
    if unit_id.is_empty():
        logger.warning("PlanExecutor", "Plan data has no unit_id.")
        return false

    var priority_list = plan_data.get("primary_state_priority_list", [])
    var attack_sequence = plan_data.get("control_point_attack_sequence", [])
    var goal = plan_data.get("goal", "Following strategic orders.")

    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        logger.warning("PlanExecutor", "Unit not found in game state: %s" % unit_id)
        return false

    # 1. Get base matrix for the unit's archetype.
    var base_matrix = GameConstants.get_default_behavior_matrix(unit.archetype).duplicate(true)
    
    # 2. Generate the tuned matrix with adjusted biases.
    var tuned_matrix = _generate_tuned_matrix(base_matrix, priority_list)

    if unit.has_method("set_behavior_plan"):
        # Update unit's strategic goal first
        unit.strategic_goal = goal
        
        # Mark this unit for goal update broadcast to clients
        var game_state = get_node_or_null("/root/DependencyContainer/GameState")
        if game_state and game_state.has_method("mark_unit_goal_changed"):
            game_state.mark_unit_goal_changed(unit.unit_id)
        
        # Set the tuned matrix on the unit (this will also refresh the status bar)
        unit.set_behavior_plan(tuned_matrix, attack_sequence)
        
        # 4. Broadcast the static plan data to all clients via a reliable RPC.
        var unified_main = get_node_or_null("/root/UnifiedMain")
        if unified_main:
            unified_main.rpc("update_unit_behavior_plan_rpc", unit_id, tuned_matrix, attack_sequence, goal)
        
        plan_started.emit(unit_id, plan_data)
        logger.info("PlanExecutor", "Sent tuned behavior plan to unit %s and broadcast to clients." % unit_id)
    else:
        logger.error("PlanExecutor", "Unit %s does not have set_behavior_plan method." % unit_id)
        return false
    
    return true

func _generate_tuned_matrix(base_matrix: Dictionary, priority_list: Array) -> Dictionary:
    """
    Adjusts the biases of the primary states in a behavior matrix based on an ordered priority list.
    """
    if priority_list.is_empty() or base_matrix.is_empty():
        return base_matrix # Return base if no priority is given.

    var tuned_matrix = base_matrix.duplicate(true)
    var validator = ActionValidator.new()

    # Define bias values based on priority. Higher priority gets a higher bias.
    const BIAS_VALUES = [0.3, 0.2, 0.1, 0.0]

    for i in range(priority_list.size()):
        var state = priority_list[i]
        if i < BIAS_VALUES.size() and state in validator.MUTUALLY_EXCLUSIVE_REACTIVE_ACTIONS:
            if tuned_matrix.has(state):
                tuned_matrix[state]["bias"] = BIAS_VALUES[i]
                logger.info("PlanExecutor", "Set bias for state '%s' to %.1f" % [state, BIAS_VALUES[i]])

    return tuned_matrix

func interrupt_plan(unit_id: String, reason: String, _from_trigger: bool = false) -> void:
    # This function is now mainly for logging and signaling.
    # The unit manages its own state interruptions.
    plan_interrupted.emit(unit_id, reason)