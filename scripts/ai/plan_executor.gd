# PlanExecutor.gd
class_name PlanExecutor
extends Node

var game_state: Node
var logger: Node

# Constants for action limits
const MAX_TRIGGERED_ACTIONS = 3
const MAX_SEQUENTIAL_ACTIONS = 5

var active_plans: Dictionary = {}  # unit_id -> Array of steps (sequential plan)
var current_step_indices: Dictionary = {} # unit_id -> int

signal plan_started(unit_id: String, plan: Dictionary)
signal plan_completed(unit_id: String, success: bool)
signal plan_interrupted(unit_id: String, reason: String)
signal step_executed(unit_id: String, step: Dictionary)
signal speech_triggered(unit_id: String, speech: String)
signal trigger_evaluated(unit_id: String, trigger: String, result: bool) # For PlanProgressManager
signal unit_became_idle(unit_id: String)

func setup(p_logger, p_game_state):
    logger = p_logger
    game_state = p_game_state

func _process(_delta: float):
    # The new design moves all execution logic to the Unit itself.
    # The PlanExecutor is now just a goal-setter and sequence manager.
    for unit_id in active_plans.keys():
        var unit = game_state.units.get(unit_id)
        if not is_instance_valid(unit):
            interrupt_plan(unit_id, "unit_not_found")
            continue

        # If the unit has finished its current action, advance the plan.
        if unit.action_complete:
            _advance_plan(unit_id)

func execute_plan(unit_id: String, plan_data: Dictionary) -> bool:
    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        logger.warning("PlanExecutor", "Unit not found in game state: %s" % unit_id)
        return false

    if not plan_data.has("steps") and not plan_data.has("triggered_actions"):
        logger.warning("PlanExecutor", "Plan for unit %s is missing 'steps' or 'triggered_actions'." % unit_id)
        return false

    active_plans[unit_id] = plan_data.get("steps", [])
    unit.set_triggered_actions(plan_data.get("triggered_actions", {}))
    current_step_indices[unit_id] = -1 # Start before the first step
    
    plan_started.emit(unit_id, plan_data)
    
    # Start the plan immediately
    _advance_plan(unit_id)
    
    return true

func interrupt_plan(unit_id: String, reason: String, from_trigger: bool = false) -> void:
    if active_plans.has(unit_id):
        active_plans.erase(unit_id)
        current_step_indices.erase(unit_id)
        
        plan_interrupted.emit(unit_id, reason)

        # If the interruption is NOT from a trigger, the unit should become idle.
        # If it IS from a trigger, the unit will handle its own next action, and
        # will emit `unit_became_idle` itself once that action is complete.
        if not from_trigger:
            var unit = game_state.units.get(unit_id)
            if is_instance_valid(unit):
                # Tell unit to stop what it's doing and go idle.
                unit.set_current_action({"action": "idle"})
            unit_became_idle.emit(unit_id)

func _advance_plan(unit_id: String):
    if not active_plans.has(unit_id): return

    current_step_indices[unit_id] += 1
    var step_index = current_step_indices[unit_id]
    
    var plan = active_plans[unit_id]
    if step_index >= plan.size():
        # Plan is complete
        _complete_plan(unit_id)
    else:
        # Execute the next step
        var step = plan[step_index]
        var unit = game_state.units.get(unit_id)
        
        if is_instance_valid(unit):
            if step.has("speech") and step.speech != null and not step.speech.is_empty():
                speech_triggered.emit(unit_id, step.speech)
                
            unit.set_current_action(step)
            step_executed.emit(unit_id, step) # For UI
        else:
            interrupt_plan(unit_id, "unit_not_found_during_advance")

func _complete_plan(unit_id: String):
    if active_plans.has(unit_id):
        active_plans.erase(unit_id)
    if current_step_indices.has(unit_id):
        current_step_indices.erase(unit_id)
    
    plan_completed.emit(unit_id, true)
    unit_became_idle.emit(unit_id)