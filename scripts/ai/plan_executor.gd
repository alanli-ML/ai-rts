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
    var priority: int = 0  # Higher priority steps execute first
    var prerequisites: Array = []  # Required conditions before execution
    var cooldown: float = 0.0  # Cooldown before this step can be executed
    
    func _init(data: Dictionary):
        action = data.get("action", "")
        params = data.get("params", {})
        duration_ms = data.get("duration_ms", 0)
        trigger = data.get("trigger", "")
        speech = data.get("speech", "")
        conditions = data.get("conditions", {})
        priority = data.get("priority", 0)
        prerequisites = data.get("prerequisites", [])
        cooldown = data.get("cooldown", 0.0)

# Enhanced trigger evaluation constants
const TRIGGER_EVALUATION_INTERVAL = 0.1  # seconds
const MAX_TRIGGER_RETRIES = 5
const TRIGGER_TIMEOUT = 60.0  # Increased timeout for complex plans
const PLAN_STEP_TIMEOUT = 30.0  # Per-step timeout

# Action execution constants
const PEEK_DURATION = 2.0  # seconds
const MINE_LAY_DURATION = 3.0  # seconds
const HIJACK_DURATION = 5.0  # seconds
const HEAL_DURATION = 2.0  # seconds
const REPAIR_DURATION = 3.0  # seconds

# Active plan tracking
var active_plans: Dictionary = {}  # unit_id -> Array[PlanStep]
var step_timers: Dictionary = {}   # unit_id -> float
var current_steps: Dictionary = {} # unit_id -> PlanStep
var plan_contexts: Dictionary = {} # unit_id -> Dictionary
var trigger_last_evaluated: Dictionary = {}  # unit_id -> float
var plan_start_times: Dictionary = {}  # unit_id -> float
var step_cooldowns: Dictionary = {}  # unit_id -> Dictionary[action_name -> float]
var parallel_actions: Dictionary = {}  # unit_id -> Array[PlanStep] (for parallel execution)

# Validation
var action_validator = null

# Enhanced performance tracking
var execution_stats: Dictionary = {
    "plans_executed": 0,
    "plans_completed": 0,
    "plans_failed": 0,
    "steps_executed": 0,
    "steps_failed": 0,
    "average_execution_time": 0.0,
    "actions_by_type": {},
    "most_failed_action": "",
    "success_rate": 0.0
}

# Signals
signal plan_started(unit_id: String, plan: Array)
signal plan_completed(unit_id: String, success: bool)
signal plan_interrupted(unit_id: String, reason: String)
signal step_executed(unit_id: String, step: PlanStep)
signal step_failed(unit_id: String, step: PlanStep, error: String)
signal trigger_evaluated(unit_id: String, trigger: String, result: bool)
signal ability_used(unit_id: String, ability: String, success: bool)
signal speech_triggered(unit_id: String, speech: String)

func _ready() -> void:
    # Create action validator
    action_validator = ActionValidatorClass.new()
    add_child(action_validator)
    
    # Add to plan executors group for easy discovery
    add_to_group("plan_executors")
    
    # Process plans every frame
    set_process(true)
    
    # Initialize step cooldowns
    step_cooldowns = {}
    
    print("PlanExecutor: Enhanced plan executor with advanced actions initialized")

func _process(delta: float) -> void:
    # Process all active plans
    for unit_id in active_plans:
        _process_unit_plan(unit_id, delta)
    
    # Process cooldowns
    _process_cooldowns(delta)

func _process_cooldowns(delta: float) -> void:
    """Process action cooldowns for all units"""
    for unit_id in step_cooldowns:
        var unit_cooldowns = step_cooldowns[unit_id]
        for action_name in unit_cooldowns:
            if unit_cooldowns[action_name] > 0:
                unit_cooldowns[action_name] -= delta
                if unit_cooldowns[action_name] <= 0:
                    print("PlanExecutor: Cooldown finished for %s action on unit %s" % [action_name, unit_id])

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
        speech_triggered.emit(unit_id, step.speech)
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
    """Execute a step action with enhanced unit integration"""
    var unit = _get_unit(unit_id)
    if not unit:
        return false
    
    # Check cooldown
    if _is_action_on_cooldown(unit_id, step.action):
        print("PlanExecutor: Action %s on cooldown for unit %s" % [step.action, unit_id])
        return false
    
    # Check prerequisites
    if not _check_prerequisites(unit_id, step):
        print("PlanExecutor: Prerequisites not met for action %s on unit %s" % [step.action, unit_id])
        return false
    
    print("PlanExecutor: Executing enhanced action for unit %s: %s" % [unit_id, step.action])
    
    # Update action statistics
    if not execution_stats.actions_by_type.has(step.action):
        execution_stats.actions_by_type[step.action] = 0
    execution_stats.actions_by_type[step.action] += 1
    
    # Execute action with enhanced integration
    var result = _execute_enhanced_action(unit_id, step, unit)
    
    if result:
        # Set cooldown for this action
        _set_action_cooldown(unit_id, step.action, step.cooldown)
        
        # Show speech bubble if specified
        if step.speech != "":
            speech_triggered.emit(unit_id, step.speech)
            _show_speech_bubble(unit_id, step.speech)
    
    return result

func _execute_enhanced_action(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Execute enhanced actions with full unit integration"""
    
    match step.action:
        "move_to":
            return _execute_move_to(unit_id, step, unit)
        
        "attack":
            return _execute_attack(unit_id, step, unit)
        
        "peek_and_fire":
            return _execute_peek_and_fire(unit_id, step, unit)
        
        "lay_mines":
            return _execute_lay_mines(unit_id, step, unit)
        
        "hijack_spire":
            return _execute_hijack_spire(unit_id, step, unit)
        
        "retreat":
            return _execute_retreat(unit_id, step, unit)
        
        "heal":
            return _execute_heal(unit_id, step, unit)
        
        "repair":
            return _execute_repair(unit_id, step, unit)
        
        "stealth":
            return _execute_stealth(unit_id, step, unit)
        
        "overwatch":
            return _execute_overwatch(unit_id, step, unit)
        
        "mark_target":
            return _execute_mark_target(unit_id, step, unit)
        
        "build_turret":
            return _execute_build_turret(unit_id, step, unit)
        
        "shield":
            return _execute_shield(unit_id, step, unit)
        
        "charge":
            return _execute_charge(unit_id, step, unit)
        
        "formation":
            return _execute_formation(unit_id, step, unit)
        
        "stance":
            return _execute_stance(unit_id, step, unit)
        
        "patrol":
            return _execute_patrol(unit_id, step, unit)
        
        "follow":
            return _execute_follow(unit_id, step, unit)
        
        "guard":
            return _execute_guard(unit_id, step, unit)
        
        "scan_area":
            return _execute_scan_area(unit_id, step, unit)
        
        _:
            print("PlanExecutor: Unknown enhanced action: %s" % step.action)
            return false

# Enhanced action implementations
func _execute_move_to(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Enhanced move command with formation awareness"""
    if not step.params.has("position"):
        return false
    
    var pos = step.params.position
    var target_pos = Vector3(pos[0], pos[1], pos[2])
    
    # Check for formation movement
    if step.params.has("formation") and step.params.formation != "":
        var formation = step.params.formation
        var formation_offset = _calculate_formation_offset(unit_id, formation)
        target_pos += formation_offset
    
    if unit.has_method("move_to"):
        unit.move_to(target_pos)
        return true
    else:
        # Fallback to signal system
        if has_node("/root/EventBus"):
            var event_bus = get_node("/root/EventBus")
            if event_bus.has_signal("unit_command_issued"):
                event_bus.unit_command_issued.emit(unit_id, "move_to:%s,%s,%s" % [pos[0], pos[1], pos[2]])
                return true
    
    return false

func _execute_attack(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Enhanced attack command"""
    if not step.params.has("target_id"):
        return false
    
    var target_id = step.params.target_id
    var target = _get_unit(target_id)
    if not target:
        return false
    
    if unit.has_method("attack_target"):
        unit.attack_target(target)
        return true
    else:
        # Fallback to signal system
        if has_node("/root/EventBus"):
            var event_bus = get_node("/root/EventBus")
            if event_bus.has_signal("unit_command_issued"):
                event_bus.unit_command_issued.emit(unit_id, "attack:%s" % target_id)
                return true
    
    return false

func _execute_peek_and_fire(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Peek and fire tactical action"""
    if not step.params.has("target_id"):
        return false
    
    var target_id = step.params.target_id
    var target = _get_unit(target_id)
    if not target:
        return false
    
    # Check if unit is a sniper (this action is sniper-specific)
    if unit.has_method("get") and unit.get("archetype") == "sniper":
        if unit.has_method("peek_and_fire"):
            unit.peek_and_fire(target)
            return true
        else:
            # Simulate peek and fire behavior
            print("PlanExecutor: %s peeking and firing at %s" % [unit_id, target_id])
            
            # Move to cover position first
            var cover_pos = _find_cover_position(unit, target)
            if cover_pos != Vector3.ZERO:
                unit.move_to(cover_pos)
                
                # Set up timed attack after peek duration
                await get_tree().create_timer(PEEK_DURATION).timeout
                
                if unit.has_method("attack_target"):
                    unit.attack_target(target)
                    return true
    
    return false

func _execute_lay_mines(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Lay mines tactical action (Engineer specific)"""
    if not step.params.has("position"):
        return false
    
    # Check if unit is an engineer
    if unit.has_method("get") and unit.get("archetype") == "engineer":
        var pos = step.params.position
        var mine_pos = Vector3(pos[0], pos[1], pos[2])
        var mine_count = step.params.get("count", 1)
        var mine_type = step.params.get("type", "proximity")
        
        # Get entity manager
        var entity_manager = get_tree().get_first_node_in_group("entity_managers")
        if not entity_manager:
            print("PlanExecutor: No entity manager found for mine deployment")
            return false
        
        # Get tile system for position conversion
        var tile_system = _get_tile_system()
        if not tile_system:
            print("PlanExecutor: No tile system found for mine placement")
            return false
        
        # Convert world position to tile position
        var tile_pos = tile_system.world_to_tile(mine_pos)
        
        # Move to position first
        unit.move_to(mine_pos)
        
        # Set up timed mine placement
        await get_tree().create_timer(MINE_LAY_DURATION).timeout
        
        # Deploy mines
        var mines_deployed = 0
        for i in range(mine_count):
            # Calculate offset position for multiple mines
            var offset_tile = tile_pos + Vector2i(i % 3 - 1, i / 3 - 1)
            
            # Deploy mine through entity manager
            var mine_id = entity_manager.deploy_mine(offset_tile, mine_type, unit.team_id, unit_id)
            
            if mine_id != "":
                mines_deployed += 1
                print("PlanExecutor: Mine %s deployed at tile %s" % [mine_id, offset_tile])
            else:
                print("PlanExecutor: Failed to deploy mine at tile %s" % offset_tile)
        
        print("PlanExecutor: %s successfully deployed %d/%d mines" % [unit_id, mines_deployed, mine_count])
        return mines_deployed > 0
    
    return false

func _execute_hijack_spire(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Hijack enemy spire tactical action"""
    if not step.params.has("spire_id"):
        return false
    
    var spire_id = step.params.spire_id
    var spire = _get_building(spire_id)
    if not spire:
        return false
    
    # Check if unit is an engineer (hijacking is engineer-specific)
    if unit.has_method("get") and unit.get("archetype") == "engineer":
        if unit.has_method("hijack_spire"):
            unit.hijack_spire(spire)
            return true
        else:
            # Simulate hijacking behavior
            print("PlanExecutor: %s hijacking spire %s" % [unit_id, spire_id])
            
            # Move to spire first
            unit.move_to(spire.global_position)
            
            # Set up timed hijack
            await get_tree().create_timer(HIJACK_DURATION).timeout
            
            # Signal hijack completion
            if has_node("/root/EventBus"):
                var event_bus = get_node("/root/EventBus")
                if event_bus.has_signal("unit_command_issued"):
                    event_bus.unit_command_issued.emit(unit_id, "hijack_spire:%s" % spire_id)
            
            return true
    
    return false

func _execute_heal(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Heal action (Medic specific)"""
    if not step.params.has("target_id"):
        return false
    
    var target_id = step.params.target_id
    var target = _get_unit(target_id)
    if not target:
        return false
    
    # Check if unit is a medic
    if unit.has_method("get") and unit.get("archetype") == "medic":
        if unit.has_method("heal_unit"):
            unit.heal_unit(target)
            return true
        else:
            # Simulate healing
            print("PlanExecutor: %s healing %s" % [unit_id, target_id])
            
            # Move to target first
            var heal_distance = 2.0
            var direction = (target.global_position - unit.global_position).normalized()
            var heal_pos = target.global_position - direction * heal_distance
            unit.move_to(heal_pos)
            
            # Set up timed heal
            await get_tree().create_timer(HEAL_DURATION).timeout
            
            # Apply healing
            if target.has_method("heal"):
                var heal_amount = GameConstants.UNIT_CONFIGS.get("medic", {}).get("heal_rate", 10.0)
                target.heal(heal_amount)
            
            return true
    
    return false

func _execute_stealth(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Stealth action (Scout specific)"""
    if unit.has_method("get") and unit.get("archetype") == "scout":
        if unit.has_method("activate_stealth"):
            var duration = step.params.get("duration", 10.0)
            unit.activate_stealth(duration)
            ability_used.emit(unit_id, "stealth", true)
            return true
        else:
            # Simulate stealth
            print("PlanExecutor: %s activating stealth" % unit_id)
            
            # Signal stealth activation
            if has_node("/root/EventBus"):
                var event_bus = get_node("/root/EventBus")
                if event_bus.has_signal("unit_command_issued"):
                    event_bus.unit_command_issued.emit(unit_id, "stealth")
            
            ability_used.emit(unit_id, "stealth", true)
            return true
    
    ability_used.emit(unit_id, "stealth", false)
    return false

func _execute_overwatch(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Overwatch action (Sniper specific)"""
    if unit.has_method("get") and unit.get("archetype") == "sniper":
        if unit.has_method("activate_overwatch"):
            var duration = step.params.get("duration", 15.0)
            unit.activate_overwatch(duration)
            ability_used.emit(unit_id, "overwatch", true)
            return true
        else:
            # Simulate overwatch
            print("PlanExecutor: %s activating overwatch" % unit_id)
            
            # Signal overwatch activation
            if has_node("/root/EventBus"):
                var event_bus = get_node("/root/EventBus")
                if event_bus.has_signal("unit_command_issued"):
                    event_bus.unit_command_issued.emit(unit_id, "overwatch")
            
            ability_used.emit(unit_id, "overwatch", true)
            return true
    
    ability_used.emit(unit_id, "overwatch", false)
    return false

func _execute_charge(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Charge action (Tank specific)"""
    if not step.params.has("target_position"):
        return false
    
    if unit.has_method("get") and unit.get("archetype") == "tank":
        var pos = step.params.target_position
        var target_pos = Vector3(pos[0], pos[1], pos[2])
        
        if unit.has_method("charge_to"):
            unit.charge_to(target_pos)
            ability_used.emit(unit_id, "charge", true)
            return true
        else:
            # Simulate charge
            print("PlanExecutor: %s charging to %s" % [unit_id, target_pos])
            
            # Enhanced movement speed for charge
            if unit.has_method("set_movement_speed"):
                var original_speed = unit.movement_speed
                unit.set_movement_speed(original_speed * 2.0)
                unit.move_to(target_pos)
                
                # Restore speed after charge
                await get_tree().create_timer(3.0).timeout
                unit.set_movement_speed(original_speed)
            else:
                unit.move_to(target_pos)
            
            ability_used.emit(unit_id, "charge", true)
            return true
    
    ability_used.emit(unit_id, "charge", false)
    return false

func _execute_repair(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Repair action (Engineer specific)"""
    if not step.params.has("target_id"):
        return false
    
    var target_id = step.params.target_id
    var target = _get_unit(target_id)
    if not target:
        return false
    
    # Check if unit is an engineer
    if unit.has_method("get") and unit.get("archetype") == "engineer":
        if unit.has_method("repair_unit"):
            unit.repair_unit(target)
            return true
        else:
            # Simulate repair
            print("PlanExecutor: %s repairing %s" % [unit_id, target_id])
            
            # Move to target first
            var repair_distance = 2.0
            var direction = (target.global_position - unit.global_position).normalized()
            var repair_pos = target.global_position - direction * repair_distance
            unit.move_to(repair_pos)
            
            # Set up timed repair
            await get_tree().create_timer(REPAIR_DURATION).timeout
            
            # Apply repair
            if target.has_method("repair"):
                var repair_amount = GameConstants.UNIT_CONFIGS.get("engineer", {}).get("repair_rate", 10.0)
                target.repair(repair_amount)
            
            return true
    
    return false

func _execute_formation(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Formation change action"""
    if not step.params.has("formation"):
        return false
    
    var formation = step.params.formation
    # Use signal system if EventBus is available
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("unit_command_issued"):
            event_bus.unit_command_issued.emit(unit_id, "formation:%s" % formation)
            return true
    print("PlanExecutor: Formation command executed (simulated)")
    return true

func _execute_stance(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Stance change action"""
    if not step.params.has("stance"):
        return false
    
    var stance = step.params.stance
    # Use signal system if EventBus is available
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("unit_command_issued"):
            event_bus.unit_command_issued.emit(unit_id, "stance:%s" % stance)
            return true
    print("PlanExecutor: Stance command executed (simulated)")
    return true

func _execute_patrol(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Patrol action"""
    if not step.params.has("position"):
        return false
    
    var pos = step.params.position
    if unit.has_method("patrol_to"):
        unit.patrol_to(Vector3(pos[0], pos[1], pos[2]))
        return true
    else:
        # Fallback to signal system
        if has_node("/root/EventBus"):
            var event_bus = get_node("/root/EventBus")
            if event_bus.has_signal("unit_command_issued"):
                event_bus.unit_command_issued.emit(unit_id, "patrol:%s,%s,%s" % [pos[0], pos[1], pos[2]])
                return true
    
    return false

func _execute_follow(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Follow action"""
    if not step.params.has("target_id"):
        return false
    
    var target_id = step.params.target_id
    var target = _get_unit(target_id)
    if not target:
        return false
    
    if unit.has_method("follow_unit"):
        unit.follow_unit(target)
        return true
    else:
        # Fallback to signal system
        if has_node("/root/EventBus"):
            var event_bus = get_node("/root/EventBus")
            if event_bus.has_signal("unit_command_issued"):
                event_bus.unit_command_issued.emit(unit_id, "follow:%s" % target_id)
                return true
    
    return false

func _execute_guard(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Guard action"""
    if not step.params.has("target_id"):
        return false
    
    var target_id = step.params.target_id
    var target = _get_unit(target_id)
    if not target:
        return false
    
    if unit.has_method("guard_unit"):
        unit.guard_unit(target)
        return true
    else:
        # Fallback to signal system
        if has_node("/root/EventBus"):
            var event_bus = get_node("/root/EventBus")
            if event_bus.has_signal("unit_command_issued"):
                event_bus.unit_command_issued.emit(unit_id, "guard:%s" % target_id)
                return true
    
    return false

func _execute_scan_area(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Scan area action (Scout specific)"""
    if unit.has_method("get") and unit.get("archetype") == "scout":
        if unit.has_method("scan_area"):
            var range = step.params.get("range", 10.0)
            unit.scan_area(range)
            ability_used.emit(unit_id, "scan_area", true)
            return true
        else:
            # Simulate scanning
            print("PlanExecutor: %s scanning area" % unit_id)
            
            # Signal scanning
            if has_node("/root/EventBus"):
                var event_bus = get_node("/root/EventBus")
                if event_bus.has_signal("unit_command_issued"):
                    event_bus.unit_command_issued.emit(unit_id, "scan_area")
            
            ability_used.emit(unit_id, "scan_area", true)
            return true
    
    ability_used.emit(unit_id, "scan_area", false)
    return false

func _execute_mark_target(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Mark target action (Scout specific)"""
    if unit.has_method("get") and unit.get("archetype") == "scout":
        if unit.has_method("mark_target"):
            var target_id = step.params.get("target_id")
            var target = _get_unit(target_id)
            if target:
                unit.mark_target(target)
                return true
            else:
                print("PlanExecutor: Mark target %s not found" % target_id)
                return false
        else:
            # Simulate marking
            print("PlanExecutor: %s marking target" % unit_id)
            
            # Signal marking
            if has_node("/root/EventBus"):
                var event_bus = get_node("/root/EventBus")
                if event_bus.has_signal("unit_command_issued"):
                    event_bus.unit_command_issued.emit(unit_id, "mark_target")
            
            ability_used.emit(unit_id, "mark_target", true)
            return true
    
    ability_used.emit(unit_id, "mark_target", false)
    return false

func _execute_build_turret(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Build turret action (Engineer specific)"""
    if not step.params.has("position"):
        return false
    
    # Check if unit is an engineer
    if unit.has_method("get") and unit.get("archetype") == "engineer":
        var pos = step.params.position
        if unit.has_method("build_turret"):
            unit.build_turret(Vector3(pos[0], pos[1], pos[2]))
            return true
        else:
            # Simulate turret building
            print("PlanExecutor: %s building turret at %s" % [unit_id, pos])
            
            # Move to position first
            unit.move_to(Vector3(pos[0], pos[1], pos[2]))
            
            # Set up timed turret build
            await get_tree().create_timer(REPAIR_DURATION).timeout # Assuming turret build is similar to repair
            
            # Signal turret build completion
            if has_node("/root/EventBus"):
                var event_bus = get_node("/root/EventBus")
                if event_bus.has_signal("unit_command_issued"):
                    event_bus.unit_command_issued.emit(unit_id, "build_turret:%s,%s,%s" % [pos[0], pos[1], pos[2]])
            
            return true
    
    return false

func _execute_shield(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Shield action (Tank specific)"""
    if not step.params.has("duration"):
        return false
    
    if unit.has_method("get") and unit.get("archetype") == "tank":
        var duration = step.params.duration
        if unit.has_method("activate_shield"):
            unit.activate_shield(duration)
            ability_used.emit(unit_id, "shield", true)
            return true
        else:
            # Simulate shielding
            print("PlanExecutor: %s activating shield for %f seconds" % [unit_id, duration])
            
            # Signal shielding
            if has_node("/root/EventBus"):
                var event_bus = get_node("/root/EventBus")
                if event_bus.has_signal("unit_command_issued"):
                    event_bus.unit_command_issued.emit(unit_id, "shield:%f" % duration)
            
            ability_used.emit(unit_id, "shield", true)
            return true
    
    ability_used.emit(unit_id, "shield", false)
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

func _is_action_on_cooldown(unit_id: String, action: String) -> bool:
    """Check if an action is on cooldown"""
    if not step_cooldowns.has(unit_id):
        return false
    
    var unit_cooldowns = step_cooldowns[unit_id]
    if not unit_cooldowns.has(action):
        return false
    
    return unit_cooldowns[action] > 0

func _set_action_cooldown(unit_id: String, action: String, cooldown: float) -> void:
    """Set cooldown for an action"""
    if not step_cooldowns.has(unit_id):
        step_cooldowns[unit_id] = {}
    
    step_cooldowns[unit_id][action] = cooldown

func _check_prerequisites(unit_id: String, step: PlanStep) -> bool:
    """Check if step prerequisites are met"""
    if step.prerequisites.is_empty():
        return true
    
    var unit = _get_unit(unit_id)
    if not unit:
        return false
    
    for prerequisite in step.prerequisites:
        if not _evaluate_single_trigger(prerequisite, unit, unit_id):
            return false
    
    return true

func _calculate_formation_offset(unit_id: String, formation: String) -> Vector3:
    """Calculate formation offset for unit"""
    # This would integrate with the formation system
    # For now, return zero offset
    return Vector3.ZERO

func _find_cover_position(unit: Node, target: Node) -> Vector3:
    """Find cover position for peek and fire"""
    if not unit or not target:
        return Vector3.ZERO
    
    # Simple cover finding - move perpendicular to target
    var direction = (target.global_position - unit.global_position).normalized()
    var perpendicular = Vector3(-direction.z, 0, direction.x)
    return unit.global_position + perpendicular * 3.0

func _get_building(building_id: String) -> Node:
    """Get building by ID"""
    var buildings = get_tree().get_nodes_in_group("buildings")
    for building in buildings:
        if building.has_method("get") and building.get("building_id") == building_id:
            return building
        elif building.name == building_id:
            return building
    return null

func _show_speech_bubble(unit_id: String, speech: String) -> void:
    """Show speech bubble above unit"""
    if has_node("/root/EventBus"):
        var event_bus = get_node("/root/EventBus")
        if event_bus.has_signal("unit_speech"):
            event_bus.unit_speech.emit(unit_id, speech)

func get_execution_stats() -> Dictionary:
    """Get enhanced execution statistics"""
    var stats = execution_stats.duplicate()
    
    # Calculate success rate
    var total_actions = execution_stats.steps_executed + execution_stats.steps_failed
    if total_actions > 0:
        stats.success_rate = float(execution_stats.steps_executed) / float(total_actions) * 100.0
    
    # Find most failed action
    var max_failures = 0
    for action in execution_stats.actions_by_type:
        if execution_stats.actions_by_type[action] > max_failures:
            max_failures = execution_stats.actions_by_type[action]
            stats.most_failed_action = action
    
    return stats

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