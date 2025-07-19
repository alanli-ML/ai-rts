# PlanExecutor.gd
class_name PlanExecutor
extends Node

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

func execute_plan(unit_id: String, plan_data: Dictionary) -> bool:
    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        logger.warning("PlanExecutor", "Unit not found in game state: %s" % unit_id)
        return false

    if not plan_data.has("behavior_matrix") or not plan_data.has("control_point_attack_sequence"):
        logger.warning("PlanExecutor", "Plan for unit %s is missing 'behavior_matrix' or 'control_point_attack_sequence'." % unit_id)
        return false

    # The unit is now fully autonomous. We just give it its personality and strategic goals.
    var behavior_matrix = plan_data.get("behavior_matrix", {})
    var attack_sequence = plan_data.get("control_point_attack_sequence", [])
    
    if unit.has_method("set_behavior_plan"):
        unit.set_behavior_plan(behavior_matrix, attack_sequence)
        plan_started.emit(unit_id, plan_data)
        logger.info("PlanExecutor", "Sent behavior plan to unit %s" % unit_id)
        return true
    else:
        logger.error("PlanExecutor", "Unit %s does not have set_behavior_plan method." % unit_id)
        return false

func interrupt_plan(unit_id: String, reason: String, _from_trigger: bool = false) -> void:
    # This function is now mainly for logging and signaling.
    # The unit manages its own state interruptions.
    plan_interrupted.emit(unit_id, reason)