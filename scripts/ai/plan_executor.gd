# PlanExecutor.gd
class_name PlanExecutor
extends Node

var game_state: Node
var logger: Node

var active_plans: Dictionary = {}  # unit_id -> Array of steps
var current_steps: Dictionary = {} # unit_id -> current step
var step_timers: Dictionary = {}   # unit_id -> float for step duration

signal plan_started(unit_id: String, plan: Array)
signal plan_completed(unit_id: String, success: bool)
signal plan_interrupted(unit_id: String, reason: String)
signal step_executed(unit_id: String, step: Dictionary)
signal speech_triggered(unit_id: String, speech: String)
signal trigger_evaluated(unit_id: String, trigger: String, result: bool) # For PlanProgressManager

func setup(p_logger, p_game_state):
    logger = p_logger
    game_state = p_game_state

func _process(delta: float) -> void:
    for unit_id in active_plans.keys():
        _process_unit_plan(unit_id, delta)

func execute_plan(unit_id: String, plan_data: Dictionary) -> bool:
    if not plan_data.has("steps") or plan_data.steps.is_empty():
        return false

    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        logger.warning("PlanExecutor", "Unit not found in game state: %s" % unit_id)
        return false

    active_plans[unit_id] = plan_data.steps
    current_steps[unit_id] = null
    step_timers[unit_id] = 0.0
    
    plan_started.emit(unit_id, plan_data.steps)
    call_deferred("_start_next_step", unit_id)
    return true

func interrupt_plan(unit_id: String, reason: String) -> void:
    if unit_id in active_plans:
        active_plans.erase(unit_id)
        current_steps.erase(unit_id)
        step_timers.erase(unit_id)
        plan_interrupted.emit(unit_id, reason)

func _process_unit_plan(unit_id: String, delta: float) -> void:
    if not current_steps.has(unit_id) or current_steps[unit_id] == null:
        if active_plans.has(unit_id) and not active_plans[unit_id].is_empty():
            call_deferred("_start_next_step", unit_id)
        return

    var step = current_steps[unit_id]
    var unit = game_state.units.get(unit_id)
    if not is_instance_valid(unit):
        interrupt_plan(unit_id, "unit_not_found")
        return

    step_timers[unit_id] += delta

    if _is_step_complete(unit_id, step, unit):
        _complete_step(unit_id)

func _is_step_complete(unit_id: String, step: Dictionary, unit: Node) -> bool:
    var action = step.get("action")
    
    if action == "move_to":
        if is_instance_valid(unit) and unit.navigation_agent:
            return unit.navigation_agent.is_navigation_finished()
        return true # Failsafe if unit or agent is gone
    
    if action == "attack":
        var target_id = step.get("params", {}).get("target_id", "")
        if target_id.is_empty(): return true # No target, action is void
        
        var target = game_state.units.get(target_id)
        # The step is complete if the target is invalid or dead.
        return not is_instance_valid(target) or target.is_dead

    if step.has("trigger") and not step.trigger.is_empty():
        # We need the full context to evaluate triggers now.
        var context = game_state.get_context_for_ai(unit)
        return _evaluate_trigger(step.trigger, unit, context)
    
    if step.has("duration_ms") and step.duration_ms > 0:
        return step_timers[unit_id] * 1000.0 >= step.duration_ms

    # For actions without duration or trigger, assume they are complete after one frame
    return true

func _evaluate_trigger(trigger_string: String, unit: Node, unit_context: Dictionary) -> bool:
    if trigger_string.is_empty():
        return false

    # For now, we only support simple triggers. Complex parsing (AND/OR) can be added later.
    var parts = trigger_string.split(" ", false, 2)
    if parts.size() != 3:
        logger.warning("PlanExecutor", "Invalid trigger format: '%s'" % trigger_string)
        return false

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

    var current_value = _get_metric_value(metric, unit, unit_context)

    match op:
        "==": return current_value == value
        "!=": return current_value != value
        "<": return current_value < value
        "<=": return current_value <= value
        ">": return current_value > value
        ">=": return current_value >= value
        _:
            logger.warning("PlanExecutor", "Unknown operator in trigger: '%s'" % op)
            return false

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
        "under_fire":
            return unit_context.get("unit_state", {}).get("is_under_fire", false)
        "target_dead":
            return not is_instance_valid(unit.target_unit) or unit.target_unit.is_dead
        "enemy_in_range":
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            for enemy in enemies:
                if enemy.dist <= unit.attack_range:
                    return true
            return false
        "enemy_dist":
            var enemies = unit_context.get("sensor_data", {}).get("visible_enemies", [])
            if enemies.is_empty(): return 9999.0
            return enemies[0].dist # Assumes enemies are sorted by distance
        "ally_health_low":
            var allies = unit_context.get("sensor_data", {}).get("visible_allies", [])
            for ally in allies:
                if ally.health_pct < 50.0:
                    return true
            return false
        "nearby_enemies":
            return unit_context.get("sensor_data", {}).get("visible_enemies", []).size()
        "is_moving":
            return unit.velocity.length_squared() > 0.1
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

    if step.has("speech") and not step.speech.is_empty():
        speech_triggered.emit(unit_id, step.speech)

    match action:
        "move_to":
            if params.has("position"):
                var pos_arr = params.position
                var target_pos = Vector3(pos_arr[0], pos_arr[1], pos_arr[2])
                if unit.has_method("move_to"): unit.move_to(target_pos)
        "attack":
            if params.has("target_id"):
                var target = game_state.units.get(params.target_id)
                if is_instance_valid(target) and unit.has_method("attack_target"):
                    unit.attack_target(target)
        "retreat":
            if unit.has_method("retreat"): unit.retreat()
        "patrol":
            if unit.has_method("start_patrol") and params.has("waypoints"):
                unit.start_patrol(params.waypoints)
        "use_ability":
            if unit.has_method("use_ability") and params.has("ability_name"):
                unit.use_ability(params.ability_name)
        "formation":
            if unit.has_method("set_formation") and params.has("formation"):
                unit.set_formation(params.formation)
        "stance":
            if unit.has_method("set_stance") and params.has("stance"):
                unit.set_stance(params.stance)
        "follow":
            if params.has("target_id"):
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
            if unit.has_method("charge_shot"): unit.charge_shot(params)
        "find_cover":
            if unit.has_method("find_cover"): unit.find_cover(params)
        "heal_target":
            if unit.has_method("heal_target"): unit.heal_target(params)
        "construct":
            if unit.has_method("construct"): unit.construct(params)
        "repair":
            if unit.has_method("repair"): unit.repair(params)
        "lay_mines":
            if unit.has_method("lay_mines"): unit.lay_mines(params)

func _complete_plan(unit_id: String) -> void:
    active_plans.erase(unit_id)
    current_steps.erase(unit_id)
    step_timers.erase(unit_id)
    plan_completed.emit(unit_id, true)