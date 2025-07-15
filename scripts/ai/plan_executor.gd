# PlanExecutor.gd
class_name PlanExecutor
extends Node

# Load shared constants
const GameConstants = preload("res://scripts/shared/constants/game_constants.gd")

# Load ActionValidator
const ActionValidatorClass = preload("res://scripts/ai/action_validator.gd")

# Plan step class
class PlanStep:
    var action: String
    var params: Dictionary
    var duration_ms: int = 0
    var trigger: String = ""
    var speech: String = ""
    var start_time: float = 0.0
    var conditions: Dictionary = {}
    var completed: bool = false
    var unit_id: String = ""
    var step_index: int = 0
    var retry_count: int = 0
    var max_retries: int = 3
    
    func _init(data: Dictionary):
        action = data.get("action", "")
        params = data.get("params", {})
        duration_ms = data.get("duration_ms", 0)
        trigger = data.get("trigger", "")
        speech = data.get("speech", "")
        conditions = data.get("conditions", {})

# Enhanced trigger evaluation constants
const TRIGGER_EVALUATION_INTERVAL = 0.1  # seconds
const MAX_TRIGGER_RETRIES = 5
const TRIGGER_TIMEOUT = 30.0  # seconds

# Active plan tracking
var active_plans: Dictionary = {}  # unit_id -> Array[PlanStep]
var step_timers: Dictionary = {}   # unit_id -> float
var current_steps: Dictionary = {} # unit_id -> PlanStep
var plan_contexts: Dictionary = {} # unit_id -> Dictionary
var trigger_last_evaluated: Dictionary = {}  # unit_id -> float
var plan_start_times: Dictionary = {}  # unit_id -> float

# Validation
var action_validator = null

# Performance tracking
var execution_stats: Dictionary = {
    "plans_executed": 0,
    "plans_completed": 0,
    "plans_failed": 0,
    "steps_executed": 0,
    "average_execution_time": 0.0
}

# Signals
signal plan_started(unit_id: String, plan: Array)
signal plan_completed(unit_id: String, success: bool)
signal plan_interrupted(unit_id: String, reason: String)
signal step_executed(unit_id: String, step: PlanStep)
signal step_failed(unit_id: String, step: PlanStep, error: String)
signal trigger_evaluated(unit_id: String, trigger: String, result: bool)

func _ready() -> void:
    # Create action validator
    action_validator = ActionValidatorClass.new()
    add_child(action_validator)
    
    # Add to plan executors group for easy discovery
    add_to_group("plan_executors")
    
    # Process plans every frame
    set_process(true)
    
    print("PlanExecutor: Enhanced plan executor initialized")

func _process(delta: float) -> void:
    # Process all active plans
    for unit_id in active_plans:
        _process_unit_plan(unit_id, delta)

func execute_plan(unit_id: String, plan_data: Dictionary) -> bool:
    """
    Execute a multi-step plan for a unit
    
    Args:
        unit_id: ID of the unit to execute the plan
        plan_data: Plan data with steps array
        
    Returns:
        bool: True if plan was started successfully
    """
    
    # Validate plan
    var validation_result = action_validator.validate_plan(plan_data)
    if not validation_result.valid:
        print("PlanExecutor: Plan validation failed for unit %s: %s" % [unit_id, validation_result.error])
        execution_stats.plans_failed += 1
        return false
    
    # Log warnings
    for warning in validation_result.warnings:
        print("PlanExecutor: Plan warning for unit %s: %s" % [unit_id, warning])
    
    # Convert plan data to PlanStep objects
    var plan_steps = []
    for i in range(plan_data.get("steps", []).size()):
        var step_data = plan_data.get("steps", [])[i]
        var step = PlanStep.new(step_data)
        step.unit_id = unit_id
        step.step_index = i
        plan_steps.append(step)
    
    # Cancel any existing plan for this unit
    if unit_id in active_plans:
        interrupt_plan(unit_id, "new_plan_started")
    
    # Start plan execution
    active_plans[unit_id] = plan_steps
    current_steps[unit_id] = null
    step_timers[unit_id] = 0.0
    trigger_last_evaluated[unit_id] = 0.0
    plan_start_times[unit_id] = Time.get_ticks_msec() / 1000.0
    plan_contexts[unit_id] = plan_data.get("context", {})
    
    # Update stats
    execution_stats.plans_executed += 1
    
    plan_started.emit(unit_id, plan_steps)
    _start_next_step(unit_id)
    
    print("PlanExecutor: Started enhanced plan for unit %s with %d steps" % [unit_id, plan_steps.size()])
    return true

func interrupt_plan(unit_id: String, reason: String) -> void:
    """Interrupt an active plan with enhanced cleanup"""
    if unit_id in active_plans:
        print("PlanExecutor: Interrupting plan for unit %s: %s" % [unit_id, reason])
        
        # Update stats
        execution_stats.plans_failed += 1
        
        # Clean up
        active_plans.erase(unit_id)
        current_steps.erase(unit_id)
        step_timers.erase(unit_id)
        trigger_last_evaluated.erase(unit_id)
        plan_start_times.erase(unit_id)
        plan_contexts.erase(unit_id)
        
        plan_interrupted.emit(unit_id, reason)

func _process_unit_plan(unit_id: String, delta: float) -> void:
    """Process a unit's active plan with enhanced error handling"""
    if not current_steps.has(unit_id):
        _start_next_step(unit_id)
        return
    
    var step = current_steps[unit_id]
    var unit = _get_unit(unit_id)
    
    if not unit:
        interrupt_plan(unit_id, "unit_not_found")
        return
    
    # Check for plan timeout
    var plan_elapsed = Time.get_ticks_msec() / 1000.0 - plan_start_times[unit_id]
    if plan_elapsed > TRIGGER_TIMEOUT:
        interrupt_plan(unit_id, "plan_timeout")
        return
    
    # Update step timer
    step_timers[unit_id] += delta
    
    # Check for step completion with enhanced evaluation
    if _is_step_complete_enhanced(unit_id, step, unit):
        _complete_step(unit_id)

func _is_step_complete_enhanced(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Enhanced step completion check with better trigger evaluation"""
    
    # Check trigger conditions with throttling
    if step.trigger != "":
        var current_time = Time.get_ticks_msec() / 1000.0
        var last_eval = trigger_last_evaluated.get(unit_id, 0.0)
        
        if current_time - last_eval >= TRIGGER_EVALUATION_INTERVAL:
            trigger_last_evaluated[unit_id] = current_time
            var trigger_result = _evaluate_trigger_enhanced(step.trigger, unit, unit_id)
            trigger_evaluated.emit(unit_id, step.trigger, trigger_result)
            return trigger_result
        
        # Return previous evaluation result if within throttle window
        return false
    
    # Check duration with more precision
    if step.duration_ms > 0:
        var elapsed_ms = step_timers[unit_id] * 1000.0
        return elapsed_ms >= step.duration_ms
    
    # Check action completion with retry logic
    var action_complete = _is_action_complete(step.action, unit)
    if not action_complete and step.retry_count < step.max_retries:
        # Retry failed actions
        step.retry_count += 1
        print("PlanExecutor: Retrying action %s for unit %s (attempt %d/%d)" % [step.action, unit_id, step.retry_count, step.max_retries])
        _execute_step_action(unit_id, step)
        return false
    
    return action_complete

func _evaluate_trigger_enhanced(trigger: String, unit: Node, unit_id: String) -> bool:
    """Enhanced trigger evaluation with compound conditions and better error handling"""
    
    # Handle compound conditions (AND/OR)
    if " AND " in trigger:
        var conditions = trigger.split(" AND ")
        for condition in conditions:
            if not _evaluate_single_trigger(condition.strip_edges(), unit, unit_id):
                return false
        return true
    
    if " OR " in trigger:
        var conditions = trigger.split(" OR ")
        for condition in conditions:
            if _evaluate_single_trigger(condition.strip_edges(), unit, unit_id):
                return true
        return false
    
    # Single condition
    return _evaluate_single_trigger(trigger, unit, unit_id)

func _evaluate_single_trigger(trigger: String, unit: Node, unit_id: String) -> bool:
    """Evaluate a single trigger condition with enhanced error handling"""
    
    # Parse trigger conditions like "health_pct < 20", "enemy_dist < 10"
    var parts = trigger.split(" ")
    if parts.size() < 3:
        print("PlanExecutor: Invalid trigger format: %s" % trigger)
        return false
    
    var condition = parts[0]
    var operator = parts[1]
    var threshold = float(parts[2])
    
    match condition:
        "health_pct":
            if unit.has_method("get_health_percentage"):
                var health_pct = unit.get_health_percentage() * 100
                return _compare_values(health_pct, operator, threshold)
            else:
                print("PlanExecutor: Unit %s doesn't have get_health_percentage method" % unit_id)
                return false
        
        "enemy_dist":
            var enemy_dist = _get_nearest_enemy_distance(unit)
            return _compare_values(enemy_dist, operator, threshold)
        
        "ally_dist":
            var ally_dist = _get_nearest_ally_distance(unit)
            return _compare_values(ally_dist, operator, threshold)
        
        "time":
            var elapsed_time = step_timers.get(unit_id, 0.0)
            return _compare_values(elapsed_time, operator, threshold)
        
        "energy":
            if unit.has_method("get_energy"):
                var energy = unit.get_energy()
                return _compare_values(energy, operator, threshold)
            else:
                print("PlanExecutor: Unit %s doesn't have get_energy method" % unit_id)
                return false
        
        "ammo":
            if unit.has_method("get_ammo"):
                var ammo = unit.get_ammo()
                return _compare_values(ammo, operator, threshold)
            else:
                print("PlanExecutor: Unit %s doesn't have get_ammo method" % unit_id)
                return false
        
        "enemy_count":
            var enemy_count = _get_enemy_count_in_range(unit, threshold)
            return _compare_values(enemy_count, operator, threshold)
        
        "ally_count":
            var ally_count = _get_ally_count_in_range(unit, threshold)
            return _compare_values(ally_count, operator, threshold)
        
        "morale":
            if unit.has_method("get") and unit.get("morale") != null:
                var morale = unit.get("morale")
                return _compare_values(morale, operator, threshold)
            else:
                print("PlanExecutor: Unit %s doesn't have morale property" % unit_id)
                return false
        
        _:
            print("PlanExecutor: Unknown trigger condition: %s" % condition)
            return false
    
    return false

func _compare_values(value: float, operator: String, threshold: float) -> bool:
    """Compare values with operator"""
    match operator:
        "<":
            return value < threshold
        ">":
            return value > threshold
        "<=":
            return value <= threshold
        ">=":
            return value >= threshold
        "==":
            return abs(value - threshold) < 0.01
        "!=":
            return abs(value - threshold) >= 0.01
        _:
            return false

func _is_action_complete(action: String, unit: Node) -> bool:
    """Check if an action is complete"""
    
    match action:
        "move_to":
            if unit.has_method("get_current_state"):
                var state = unit.get_current_state()
                return state != "moving"
            return true
        
        "attack":
            if unit.has_method("get_current_state"):
                var state = unit.get_current_state()
                return state != "attacking"
            return true
        
        "retreat":
            # Retreat is instant
            return true
        
        "formation":
            # Formation change is instant
            return true
        
        "stance":
            # Stance change is instant
            return true
        
        _:
            return true

func _complete_step(unit_id: String) -> void:
    """Complete the current step and move to next with enhanced stats tracking"""
    var step = current_steps[unit_id]
    step.completed = true
    
    # Update stats
    execution_stats.steps_executed += 1
    
    step_executed.emit(unit_id, step)
    
    # Show speech bubble if specified
    if step.speech != "":
        _show_speech_bubble(unit_id, step.speech)
    
    # Remove completed step
    active_plans[unit_id].pop_front()
    current_steps.erase(unit_id)
    step_timers[unit_id] = 0.0
    
    # Check if plan is complete
    if active_plans[unit_id].is_empty():
        _complete_plan(unit_id)
    else:
        _start_next_step(unit_id)

func _start_next_step(unit_id: String) -> void:
    """Start the next step in the plan"""
    if not active_plans.has(unit_id) or active_plans[unit_id].is_empty():
        return
    
    var next_step = active_plans[unit_id][0]
    current_steps[unit_id] = next_step
    next_step.start_time = Time.get_ticks_msec() / 1000.0
    
    # Execute the step action
    if not _execute_step_action(unit_id, next_step):
        step_failed.emit(unit_id, next_step, "failed_to_execute")
        _complete_step(unit_id)  # Skip failed step

func _execute_step_action(unit_id: String, step: PlanStep) -> bool:
    """Execute a step action"""
    var unit = _get_unit(unit_id)
    if not unit:
        return false
    
    print("PlanExecutor: Executing step for unit %s: %s" % [unit_id, step.action])
    
    # Dispatch action to unit or command system
    match step.action:
        "move_to":
            if step.params.has("position"):
                var pos = step.params.position
                var target_pos = Vector3(pos[0], pos[1], pos[2])
                if unit.has_method("move_to"):
                    unit.move_to(target_pos)
                    return true
                else:
                    # Use signal system if EventBus is available
                    if has_node("/root/EventBus"):
                        var event_bus = get_node("/root/EventBus")
                        if event_bus.has_signal("unit_command_issued"):
                            event_bus.unit_command_issued.emit(unit_id, "move_to:%s,%s,%s" % [pos[0], pos[1], pos[2]])
                            return true
                    print("PlanExecutor: Move command executed (simulated)")
                    return true
        
        "attack":
            if step.params.has("target_id"):
                var target_id = step.params.target_id
                if unit.has_method("attack_target"):
                    var target = _get_unit(target_id)
                    if target:
                        unit.attack_target(target)
                        return true
                else:
                    # Use signal system if EventBus is available
                    if has_node("/root/EventBus"):
                        var event_bus = get_node("/root/EventBus")
                        if event_bus.has_signal("unit_command_issued"):
                            event_bus.unit_command_issued.emit(unit_id, "attack:%s" % target_id)
                            return true
                    print("PlanExecutor: Attack command executed (simulated)")
                    return true
        
        "retreat":
            if unit.has_method("retreat"):
                unit.retreat()
                return true
            else:
                # Use signal system if EventBus is available
                if has_node("/root/EventBus"):
                    var event_bus = get_node("/root/EventBus")
                    if event_bus.has_signal("unit_command_issued"):
                        event_bus.unit_command_issued.emit(unit_id, "retreat")
                        return true
                print("PlanExecutor: Retreat command executed (simulated)")
                return true
        
        "formation":
            if step.params.has("formation"):
                var formation = step.params.formation
                # Use signal system if EventBus is available
                if has_node("/root/EventBus"):
                    var event_bus = get_node("/root/EventBus")
                    if event_bus.has_signal("unit_command_issued"):
                        event_bus.unit_command_issued.emit(unit_id, "formation:%s" % formation)
                        return true
                print("PlanExecutor: Formation command executed (simulated)")
                return true
        
        "stance":
            if step.params.has("stance"):
                var stance = step.params.stance
                # Use signal system if EventBus is available
                if has_node("/root/EventBus"):
                    var event_bus = get_node("/root/EventBus")
                    if event_bus.has_signal("unit_command_issued"):
                        event_bus.unit_command_issued.emit(unit_id, "stance:%s" % stance)
                        return true
                print("PlanExecutor: Stance command executed (simulated)")
                return true
        
        _:
            print("PlanExecutor: Unknown action: %s" % step.action)
            return false
    
    return false

func _complete_plan(unit_id: String) -> void:
    """Complete the entire plan with enhanced stats tracking"""
    var plan_duration = Time.get_ticks_msec() / 1000.0 - plan_start_times[unit_id]
    
    print("PlanExecutor: Plan completed for unit %s in %.2f seconds" % [unit_id, plan_duration])
    
    # Update stats
    execution_stats.plans_completed += 1
    var total_plans = execution_stats.plans_executed
    var current_avg = execution_stats.average_execution_time
    execution_stats.average_execution_time = (current_avg * (total_plans - 1) + plan_duration) / total_plans
    
    # Clean up
    active_plans.erase(unit_id)
    current_steps.erase(unit_id)
    step_timers.erase(unit_id)
    trigger_last_evaluated.erase(unit_id)
    plan_start_times.erase(unit_id)
    plan_contexts.erase(unit_id)
    
    plan_completed.emit(unit_id, true)

func _get_unit(unit_id: String) -> Node:
    """Get unit by ID"""
    # Try to find unit in scene
    var units = get_tree().get_nodes_in_group("units")
    for unit in units:
        if unit.has_method("get") and unit.get("unit_id") == unit_id:
            return unit
        elif unit.name == unit_id:
            return unit
    
    return null

func _get_nearest_enemy_distance(unit: Node) -> float:
    """Get distance to nearest enemy"""
    if not unit.has_method("get_team_id"):
        return 999.0
    
    var unit_team = unit.get_team_id()
    var unit_pos = unit.global_position
    var min_distance = 999.0
    
    var all_units = get_tree().get_nodes_in_group("units")
    for other_unit in all_units:
        if other_unit == unit:
            continue
        
        if other_unit.has_method("get_team_id") and other_unit.get_team_id() != unit_team:
            var distance = unit_pos.distance_to(other_unit.global_position)
            min_distance = min(min_distance, distance)
    
    return min_distance

func _get_nearest_ally_distance(unit: Node) -> float:
    """Get distance to nearest ally unit"""
    if not unit.has_method("get_team_id"):
        return 999.0
    
    var unit_team = unit.get_team_id()
    var unit_pos = unit.global_position
    var min_distance = 999.0
    
    var all_units = get_tree().get_nodes_in_group("units")
    for other_unit in all_units:
        if other_unit == unit:
            continue
        
        if other_unit.has_method("get_team_id") and other_unit.get_team_id() == unit_team:
            var distance = unit_pos.distance_to(other_unit.global_position)
            min_distance = min(min_distance, distance)
    
    return min_distance

func _get_enemy_count_in_range(unit: Node, range: float) -> int:
    """Get number of enemy units within range"""
    if not unit.has_method("get_team_id"):
        return 0
    
    var unit_team = unit.get_team_id()
    var unit_pos = unit.global_position
    var count = 0
    
    var all_units = get_tree().get_nodes_in_group("units")
    for other_unit in all_units:
        if other_unit == unit:
            continue
        
        if other_unit.has_method("get_team_id") and other_unit.get_team_id() != unit_team:
            var distance = unit_pos.distance_to(other_unit.global_position)
            if distance <= range:
                count += 1
    
    return count

func _get_ally_count_in_range(unit: Node, range: float) -> int:
    """Get number of ally units within range"""
    if not unit.has_method("get_team_id"):
        return 0
    
    var unit_team = unit.get_team_id()
    var unit_pos = unit.global_position
    var count = 0
    
    var all_units = get_tree().get_nodes_in_group("units")
    for other_unit in all_units:
        if other_unit == unit:
            continue
        
        if other_unit.has_method("get_team_id") and other_unit.get_team_id() == unit_team:
            var distance = unit_pos.distance_to(other_unit.global_position)
            if distance <= range:
                count += 1
    
    return count

func _show_speech_bubble(unit_id: String, speech: String) -> void:
    """Show speech bubble for unit using the SpeechBubbleManager"""
    
    # Try to find SpeechBubbleManager
    var speech_bubble_manager = _get_speech_bubble_manager()
    if speech_bubble_manager:
        var unit = _get_unit(unit_id)
        var team_id = unit.get_team_id() if unit and unit.has_method("get_team_id") else 0
        speech_bubble_manager.show_speech_bubble(unit_id, speech, team_id)
        return
    
    # Fallback: use EventBus if available
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("unit_command_issued"):
            event_bus.unit_command_issued.emit(unit_id, "speech:%s" % speech)
            return
    
    # Final fallback: console output
    print("PlanExecutor: Unit %s says: %s" % [unit_id, speech])

func _get_speech_bubble_manager() -> Node:
    """Get the SpeechBubbleManager instance"""
    
    # Try to find in scene tree
    var managers = get_tree().get_nodes_in_group("speech_bubble_managers")
    if managers.size() > 0:
        return managers[0]
    
    # Try to find by name
    var scene_root = get_tree().current_scene
    if scene_root:
        var manager = scene_root.find_child("SpeechBubbleManager", true, false)
        if manager:
            return manager
    
    # Try to find as autoload
    if has_node("/root/SpeechBubbleManager"):
        return get_node("/root/SpeechBubbleManager")
    
    return null

# Public interface
func get_active_plans() -> Dictionary:
    """Get all active plans"""
    return active_plans.duplicate()

func has_active_plan(unit_id: String) -> bool:
    """Check if unit has an active plan"""
    return unit_id in active_plans

func get_current_step(unit_id: String) -> PlanStep:
    """Get current step for unit"""
    return current_steps.get(unit_id, null)

func get_plan_progress(unit_id: String) -> Dictionary:
    """Get plan progress information"""
    if not unit_id in active_plans:
        return {}
    
    var total_steps = active_plans[unit_id].size()
    var completed_steps = 0
    
    for step in active_plans[unit_id]:
        if step.completed:
            completed_steps += 1
    
    return {
        "total_steps": total_steps,
        "completed_steps": completed_steps,
        "current_step": current_steps.get(unit_id, null),
        "progress": float(completed_steps) / float(total_steps) if total_steps > 0 else 0.0
    } 

# Enhanced public interface
func get_execution_stats() -> Dictionary:
    """Get execution statistics"""
    return execution_stats.duplicate()

func get_plan_progress(unit_id: String) -> Dictionary:
    """Get detailed plan progress for a unit"""
    if not unit_id in active_plans:
        return {}
    
    var total_steps = active_plans[unit_id].size()
    var current_step_index = 0
    if unit_id in current_steps:
        current_step_index = current_steps[unit_id].step_index
    
    var plan_duration = Time.get_ticks_msec() / 1000.0 - plan_start_times.get(unit_id, 0.0)
    
    return {
        "unit_id": unit_id,
        "total_steps": total_steps,
        "current_step": current_step_index,
        "progress_percent": (current_step_index / float(total_steps)) * 100.0,
        "plan_duration": plan_duration,
        "current_step_action": current_steps[unit_id].action if unit_id in current_steps else "",
        "current_step_trigger": current_steps[unit_id].trigger if unit_id in current_steps else ""
    }

func get_active_plan_count() -> int:
    """Get number of active plans"""
    return active_plans.size()

func get_units_with_plans() -> Array:
    """Get list of unit IDs with active plans"""
    return active_plans.keys()

func force_complete_step(unit_id: String) -> bool:
    """Force complete the current step (for debugging/testing)"""
    if unit_id in current_steps:
        _complete_step(unit_id)
        return true
    return false

func get_trigger_evaluation_history(unit_id: String) -> Array:
    """Get history of trigger evaluations for debugging"""
    # This would need to be implemented with a history buffer
    # For now, return empty array
    return [] 