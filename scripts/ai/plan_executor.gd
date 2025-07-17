# PlanExecutor.gd
class_name PlanExecutor
extends Node

var game_state: Node
var logger: Node

var active_plans: Dictionary = {}  # unit_id -> Array of steps (sequential plan)
var active_triggered_actions: Dictionary = {} # unit_id -> Array of triggered actions
var trigger_last_states: Dictionary = {} # unit_id -> { trigger_description -> bool }
var current_steps: Dictionary = {} # unit_id -> current step
var step_timers: Dictionary = {}   # unit_id -> float for step duration
var trigger_contexts: Dictionary = {} # unit_id -> Dictionary from last trigger

signal plan_started(unit_id: String, plan: Dictionary)
signal plan_completed(unit_id: String, success: bool)
signal plan_interrupted(unit_id: String, reason: String)
signal step_executed(unit_id: String, step: Dictionary)
signal speech_triggered(unit_id: String, speech: String)
signal trigger_evaluated(unit_id: String, trigger: String, result: bool) # For PlanProgressManager
signal unit_became_idle(unit_id: String)

func _get_team_transform(team_id: int) -> Transform3D:
    var home_base_manager = get_tree().get_first_node_in_group("home_base_managers")
    if not home_base_manager:
        logger.error("PlanExecutor", "HomeBaseManager not found!")
        return Transform3D.IDENTITY

    var my_base_pos = home_base_manager.get_home_base_position(team_id)
    var enemy_team_id = 2 if team_id == 1 else 1
    var enemy_base_pos = home_base_manager.get_home_base_position(enemy_team_id)

    if my_base_pos == Vector3.ZERO or enemy_base_pos == Vector3.ZERO:
        logger.error("PlanExecutor", "Home base positions not set up correctly.")
        return Transform3D.IDENTITY
        
    var forward_vec = (enemy_base_pos - my_base_pos).normalized()
    var right_vec = forward_vec.cross(Vector3.UP).normalized()
    var up_vec = right_vec.cross(forward_vec).normalized()

    return Transform3D(right_vec, up_vec, forward_vec, my_base_pos)

func setup(p_logger, p_game_state):
    logger = p_logger
    game_state = p_game_state

func _process(delta: float) -> void:
    # Process units with active sequential plans
    for unit_id in active_plans.keys():
        _process_unit_plan(unit_id, delta)
    
    # Also process units that only have triggered actions (no active sequential plans)
    for unit_id in active_triggered_actions.keys():
        if not active_plans.has(unit_id):
            _process_triggered_actions_only(unit_id, delta)

func _process_triggered_actions_only(unit_id: String, delta: float) -> void:
    """Process only triggered actions for units that have completed their sequential plans"""
    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        # Unit no longer exists, clean up triggered actions
        active_triggered_actions.erase(unit_id)
        return
    
    # Check and execute triggered actions
    _check_and_execute_triggered_action(unit_id, unit)

func execute_plan(unit_id: String, plan_data: Dictionary) -> bool:
    if not plan_data.has("steps") and not plan_data.has("triggered_actions"):
        logger.warning("PlanExecutor", "Plan for unit %s is missing 'steps' or 'triggered_actions'." % unit_id)
        return false

    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        logger.warning("PlanExecutor", "Unit not found in game state: %s" % unit_id)
        return false

    # Reset trigger states for the new plan
    if trigger_last_states.has(unit_id):
        trigger_last_states.erase(unit_id)

    active_plans[unit_id] = plan_data.get("steps", [])
    active_triggered_actions[unit_id] = plan_data.get("triggered_actions", [])
    current_steps[unit_id] = null
    step_timers[unit_id] = 0.0
    
    plan_started.emit(unit_id, plan_data)
    
    if not active_plans[unit_id].is_empty():
        call_deferred("_start_next_step", unit_id)
    else:
        # No sequential steps, unit is effectively idle
        unit_became_idle.emit(unit_id)
        
    return true

func interrupt_plan(unit_id: String, reason: String) -> void:
    if unit_id in active_plans:
        active_plans.erase(unit_id)
        if unit_id in active_triggered_actions:
            active_triggered_actions.erase(unit_id)
        if trigger_last_states.has(unit_id):
            trigger_last_states.erase(unit_id)
        current_steps.erase(unit_id)
        step_timers.erase(unit_id)
        plan_interrupted.emit(unit_id, reason)
        unit_became_idle.emit(unit_id)

func _process_unit_plan(unit_id: String, delta: float) -> void:
    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        interrupt_plan(unit_id, "unit_not_found")
        return

    # First, check triggered actions. They have priority and can interrupt the main plan.
    if _check_and_execute_triggered_action(unit_id, unit):
        return # A triggered action was executed, so we skip the sequential plan for this frame.

    # If no triggered action, process the sequential plan.
    if not current_steps.has(unit_id) or current_steps[unit_id] == null:
        if active_plans.has(unit_id) and not active_plans[unit_id].is_empty():
            call_deferred("_start_next_step", unit_id)
        return

    var step = current_steps[unit_id]
    step_timers[unit_id] += delta

    if step.get("action") == "patrol":
        _process_patrol_action(unit_id, step, unit)

    if _is_step_complete(unit_id, step, unit):
        _complete_step(unit_id)

func _is_step_complete(unit_id: String, step: Dictionary, unit: Node) -> bool:
    var action = step.get("action")
    
    if action == "move_to":
        if is_instance_valid(unit) and unit.navigation_agent:
            return unit.navigation_agent.is_navigation_finished()
        return true # Failsafe if unit or agent is gone
    
    if action == "attack":
        var params = step.get("params", {})
        if params == null: params = {}
        var target_id = params.get("target_id", "")
        if target_id.is_empty(): return true # No target, action is void
        
        var target = game_state.units.get(target_id)
        # The step is complete if the target is invalid or dead.
        return not is_instance_valid(target) or target.is_dead
    
    if step.has("duration_ms") and step.duration_ms > 0:
        return step_timers[unit_id] * 1000.0 >= step.duration_ms

    if action == "patrol":
        return false # Patrol is indefinite unless a duration is set (handled above).

    # For actions without duration or trigger, assume they are complete after one frame
    return true

func _process_patrol_action(unit_id: String, step: Dictionary, unit: Unit) -> void:
    if not step.has("patrol_waypoints"):
        # Waypoints are generated in _execute_step_action. If they don't exist, something is wrong
        # or the step has just started. We'll wait for them to be created.
        return

    var waypoints = step.patrol_waypoints
    var current_index = step.get("patrol_waypoint_index", 0)

    if unit.navigation_agent.is_navigation_finished():
        # Reached a waypoint, move to the next one in the loop.
        current_index = (current_index + 1) % waypoints.size()
        step["patrol_waypoint_index"] = current_index
        var next_waypoint = waypoints[current_index]
        if unit.has_method("move_to"):
            unit.move_to(next_waypoint)

func _evaluate_trigger(trigger_string: String, unit: Node, unit_context: Dictionary) -> Dictionary:
    if trigger_string.is_empty():
        return {"result": false, "context": {}}

    # Support both simple boolean triggers and comparison triggers
    var parts = trigger_string.split(" ", false, 2)
    
            # Handle simple triggers (now numeric: enemies_in_range, under_fire, nearby_enemies)
    if parts.size() == 1:
        var metric = parts[0].strip_edges()
        var metric_result = _get_metric_value(metric, unit, unit_context)
        
        if metric_result is Dictionary and metric_result.has("result"):
            # Metric returned a complex result with context
            return metric_result
        elif metric_result is bool:
            return {"result": metric_result, "context": {}}
        elif metric_result is float or metric_result is int:
            return {"result": metric_result > 0, "context": {}}
        else:
            logger.warning("PlanExecutor", "Invalid simple trigger metric: '%s'" % metric)
            return {"result": false, "context": {}}

    # Handle comparison triggers (e.g., "health_pct < 50")
    if parts.size() != 3:
        logger.warning("PlanExecutor", "Invalid trigger format: '%s'" % trigger_string)
        return {"result": false, "context": {}}

    var metric = parts[0].strip_edges()
    var op = parts[1].strip_edges()
    var value_str = parts[2].strip_edges()
    var value

    # Convert value to the correct type (float or bool)
    if value_str == "true":
        value = true
    elif value_str == "false":
        value = false
    else:
        value = float(value_str)

    var current_value_result = _get_metric_value(metric, unit, unit_context)
    var current_value

    var metric_context = {}
    if current_value_result is Dictionary:
        current_value = current_value_result.get("value")
        metric_context = current_value_result.get("context", {})
    else:
        current_value = current_value_result

    var comparison_result = false
    match op:
        "==": comparison_result = current_value == value
        "!=": comparison_result = current_value != value
        "<": comparison_result = current_value < value
        "<=": comparison_result = current_value <= value
        ">": comparison_result = current_value > value
        ">=": comparison_result = current_value >= value
        _:
            logger.warning("PlanExecutor", "Unknown operator in trigger: '%s'" % op)
            return {"result": false, "context": {}}
            
    if comparison_result:
        return {"result": true, "context": metric_context}
    else:
        return {"result": false, "context": {}}

func _check_and_execute_triggered_action(unit_id: String, unit: Node) -> bool:
    if not active_triggered_actions.has(unit_id):
        return false

    var context = game_state.get_context_for_ai(unit)
    
    if not trigger_last_states.has(unit_id):
        trigger_last_states[unit_id] = {}
    
    for triggered_action in active_triggered_actions[unit_id]:
        var trigger_result
        var trigger_description = ""
        
        # Check for new structured trigger format
        if triggered_action.has("trigger_source") and triggered_action.has("trigger_comparison") and triggered_action.has("trigger_value"):
            var source = triggered_action.get("trigger_source")
            var comparison = triggered_action.get("trigger_comparison")
            var value = triggered_action.get("trigger_value")
            trigger_description = "%s %s %s" % [source, comparison, str(value)]
            trigger_result = _evaluate_structured_trigger(source, comparison, value, unit, context)
        elif triggered_action.has("trigger"):
            # Legacy trigger format
            var trigger_string = triggered_action.get("trigger", "")
            if trigger_string.is_empty():
                continue
            trigger_description = trigger_string
            trigger_result = _evaluate_trigger(trigger_string, unit, context)
        else:
            continue
        
        var current_trigger_state = trigger_result["result"]
        var last_trigger_state = trigger_last_states[unit_id].get(trigger_description, false)
        
        # Update the last known state for this trigger
        trigger_last_states[unit_id][trigger_description] = current_trigger_state
            
        # A trigger only fires on a "rising edge" (when it becomes true after being false)
        if current_trigger_state and not last_trigger_state:
            # Trigger fired! Execute this action.
            logger.info("PlanExecutor", "Unit %s: Trigger '%s' fired. Executing action '%s'." % [unit_id, trigger_description, triggered_action.get("action")])
            
            # Set the trigger context so the action can use it (e.g., to get target_id)
            trigger_contexts[unit_id] = trigger_result.context
            
            # Execute the action. This interrupts the sequential plan for this frame.
            _execute_step_action(unit_id, triggered_action)
            
            # Let the UI know a trigger was evaluated
            trigger_evaluated.emit(unit_id, trigger_description, true)
            
            return true # A trigger was fired and action executed.
            
    return false

func _evaluate_structured_trigger(source: String, comparison: String, value: Variant, unit: Node, unit_context: Dictionary) -> Dictionary:
    """Evaluate a structured trigger with separate source, comparison, and value"""
    var metric_result = _get_metric_value(source, unit, unit_context)
    var metric_context = {}
    var current_value
    
    # Handle special case metrics that return dictionaries with context
    if metric_result is Dictionary:
        if metric_result.has("result"):
            # Boolean result with context
            current_value = metric_result.result
            metric_context = metric_result.get("context", {})
        elif metric_result.has("value"):
            # Value result with context (like enemy_dist, enemies_in_range, ally_health_pct)
            current_value = metric_result.value
            metric_context = metric_result.get("context", {})
        else:
            current_value = metric_result
    else:
        current_value = metric_result
    
    # Note: enemies_in_range, incoming_fire_count, and nearby_enemies now return counts (numbers)
    # so they go through normal numeric comparison logic below
    
    # Convert value to appropriate type for comparison
    var comparison_value = value
    if value is String:
        if value == "true":
            comparison_value = true
        elif value == "false":
            comparison_value = false
        elif value.is_valid_float():
            comparison_value = float(value)
        elif value.is_valid_int():
            comparison_value = int(value)
    
    # Perform comparison
    var comparison_result = false
    
    # Type checking to prevent bool/number comparison errors
    if comparison in ["<", "<=", ">", ">="]:
        # Numeric comparisons - ensure both values are numbers
        if not (current_value is float or current_value is int) or not (comparison_value is float or comparison_value is int):
            logger.warning("PlanExecutor", "Numeric comparison '%s' requires number values for source '%s'. Got current: %s (%s), comparison: %s (%s)" % [comparison, source, current_value, typeof(current_value), comparison_value, typeof(comparison_value)])
            return {"result": false, "context": {}}
    
    match comparison:
        "=", "==": comparison_result = current_value == comparison_value
        "!=": comparison_result = current_value != comparison_value
        "<": comparison_result = current_value < comparison_value
        "<=": comparison_result = current_value <= comparison_value
        ">": comparison_result = current_value > comparison_value
        ">=": comparison_result = current_value >= comparison_value
        _:
            logger.warning("PlanExecutor", "Unknown comparison operator in structured trigger: '%s'" % comparison)
            return {"result": false, "context": {}}
            
    if comparison_result:
        return {"result": true, "context": metric_context}
    else:
        return {"result": false, "context": {}}

func _get_metric_value(metric: String, unit: Node, unit_context: Dictionary) -> Variant:
    match metric:
        "elapsed_ms":
            return step_timers.get(unit.unit_id, 0.0) * 1000.0
        "health_pct":
            return unit.get_health_percentage() * 100.0 if unit.has_method("get_health_percentage") else 0.0
        "ammo_pct":
            return (float(unit.ammo) / unit.max_ammo) * 100.0 if unit.max_ammo > 0 else 0.0
        "morale":
            return unit.morale
        "incoming_fire_count":
            # Return count of enemies attacking this unit
            var is_under_fire = unit_context.get("unit_state", {}).get("is_under_fire", false)
            var attackers = unit_context.get("unit_state", {}).get("attackers", [])
            if is_under_fire and attackers is Array:
                return attackers.size()
            elif is_under_fire:
                return 1  # Fallback if under fire but no attackers array
            else:
                return 0
        "target_health_pct":
            if is_instance_valid(unit.target_unit):
                return unit.target_unit.get_health_percentage() * 100.0
            return 0.0 # No target or dead target, health is 0%
        "enemies_in_range":
            # Return count of enemies within attack range
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            var count = 0
            var closest_enemy_id = ""
            for enemy in enemies:
                if enemy.get("dist", 9999.0) <= unit.attack_range:
                    count += 1
                    if closest_enemy_id.is_empty():
                        closest_enemy_id = enemy.get("id", "")
            
            # Return count with context for the closest enemy (for targeting)
            if count > 0:
                return {"value": count, "context": {"target_id": closest_enemy_id}}
            else:
                return {"value": 0, "context": {}}
        "enemy_dist":
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            if enemies.is_empty():
                return {"value": 9999.0, "context": {}}
            var closest_enemy = enemies[0]
            # Ensure dist is a number
            var dist_value = closest_enemy.get("dist", 9999.0)
            if not (dist_value is float or dist_value is int):
                logger.warning("PlanExecutor", "enemy_dist metric: expected numeric dist, got %s (%s)" % [dist_value, typeof(dist_value)])
                dist_value = 9999.0
            return {"value": float(dist_value), "context": {"target_id": closest_enemy.get("id", "")}}
        "ally_health_pct":
            var allies = unit_context.get("sensor_data", {}).get("visible_allies", [])
            var lowest_health_ally = null
            var lowest_health_pct = 100.0
            for ally in allies:
                if ally.health_pct < lowest_health_pct:
                    lowest_health_ally = ally
                    lowest_health_pct = ally.health_pct
            
            if lowest_health_ally:
                return {"value": lowest_health_pct, "context": {"target_id": lowest_health_ally.id}}
            return {"value": 100.0, "context": {}} # No allies, or all full health
        "nearby_enemies":
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            return enemies.size() if enemies is Array else 0
        "move_speed":
            if unit.has_method("get") and unit.has("velocity"):
                return unit.velocity.length()
            return 0.0
        _:
            logger.warning("PlanExecutor", "Unknown metric in trigger: '%s'" % metric)
            return null

func _complete_step(unit_id: String) -> void:
    step_executed.emit(unit_id, current_steps[unit_id])
    
    if active_plans.has(unit_id):
        active_plans[unit_id].pop_front()
        current_steps[unit_id] = null
        step_timers[unit_id] = 0.0
        
        if active_plans[unit_id].is_empty():
            _complete_plan(unit_id)
        else:
            call_deferred("_start_next_step", unit_id)

func _start_next_step(unit_id: String) -> void:
    if not active_plans.has(unit_id) or active_plans[unit_id].is_empty():
        return
        
    var next_step = active_plans[unit_id][0]
    current_steps[unit_id] = next_step
    
    _execute_step_action(unit_id, next_step)

func _execute_step_action(unit_id: String, step: Dictionary) -> void:
    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit): return

    var action = step.get("action")
    var params = step.get("params", {})
    if params == null: params = {}
    params = params.duplicate()

    # NEW: Check for and merge trigger context
    if trigger_contexts.has(unit_id):
        var trigger_context = trigger_contexts[unit_id]
        for key in trigger_context:
            if not params.has(key): # Don't override params from plan
                params[key] = trigger_context[key]
        trigger_contexts.erase(unit_id) # Consume context

    if step.has("speech") and step.speech != null and not step.speech.is_empty():
        speech_triggered.emit(unit_id, step.speech)

    match action:
        "move_to":
            if params.has("position") and params.position != null:
                var pos_arr = params.position
                var relative_pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
                var team_transform = _get_team_transform(unit.team_id)
                var world_pos = team_transform * relative_pos
                if unit.has_method("move_to"): unit.move_to(world_pos)
        "attack":
            if params.has("target_id") and params.target_id != null:
                var target = game_state.units.get(params.target_id)
                if is_instance_valid(target) and unit.has_method("attack_target"):
                    unit.attack_target(target)
        "retreat":
            if unit.has_method("retreat"): unit.retreat()
        "patrol":
            # Automatically generate waypoints around the unit's current location if they don't exist.
            if not step.has("patrol_waypoints"):
                var patrol_radius = 15.0
                var num_waypoints = 4
                var waypoints = []
                var center_pos = unit.global_position
                
                for i in range(num_waypoints):
                    var angle = (float(i) / num_waypoints) * TAU
                    var offset = Vector3(cos(angle), 0, sin(angle)) * patrol_radius
                    waypoints.append(center_pos + offset)
                
                step["patrol_waypoints"] = waypoints
                step["patrol_waypoint_index"] = 0

            # Start moving to the current waypoint
            var waypoints = step.patrol_waypoints
            var current_index = step.get("patrol_waypoint_index", 0)
            var target_waypoint = waypoints[current_index]
            if unit.has_method("move_to"):
                unit.move_to(target_waypoint)


        "follow":
            if params.has("target_id") and params.target_id != null:
                var target = game_state.units.get(params.target_id)
                if is_instance_valid(target) and unit.has_method("follow"):
                    unit.follow(target)
        "activate_stealth":
            if unit.has_method("activate_stealth"): unit.activate_stealth(params)
        "activate_shield":
            if unit.has_method("activate_shield"): unit.activate_shield(params)
        "taunt_enemies":
            if unit.has_method("taunt_enemies"): unit.taunt_enemies(params)
        "charge_shot":
            if params.has("target_id") and params.target_id != null and unit.has_method("charge_shot"):
                var target = game_state.units.get(params.target_id)
                if is_instance_valid(target):
                    unit.charge_shot(target)
            elif not params.has("target_id") and unit.has_method("charge_shot"):
                # Charge shot without specific target
                unit.charge_shot(params)
        "find_cover":
            if unit.has_method("find_cover"): unit.find_cover(params)
        "heal_target":
            if params.has("target_id") and params.target_id != null and unit.has_method("heal_target"):
                var target = game_state.units.get(params.target_id)
                if is_instance_valid(target):
                    unit.heal_target(target)
        "construct":
            if params.has("position") and params.position != null and unit.has_method("construct"):
                var pos_arr = params.position
                var relative_pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
                var team_transform = _get_team_transform(unit.team_id)
                var world_pos = team_transform * relative_pos
                
                var world_params = params.duplicate()
                world_params["position"] = [world_pos.x, world_pos.y, world_pos.z]
                unit.construct(world_params)
        "repair":
            if params.has("target_id") and params.target_id != null and unit.has_method("repair"):
                var target = game_state.units.get(params.target_id)
                if is_instance_valid(target):
                    unit.repair(target)
        "lay_mines":
            if unit.has_method("lay_mines"): unit.lay_mines(params)

func _complete_plan(unit_id: String) -> void:
    active_plans.erase(unit_id)
    # NOTE: Do NOT erase active_triggered_actions here!
    # Triggered actions should persist even after sequential steps complete
    # They should only be cleared when a new plan is assigned or plan is interrupted
    # The unit will continue to be processed via _process_triggered_actions_only()
    current_steps.erase(unit_id)
    step_timers.erase(unit_id)
    plan_completed.emit(unit_id, true)
    unit_became_idle.emit(unit_id)