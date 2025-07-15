# PlanExecutorEntityIntegration.gd - Entity-integrated action implementations
extends Node

# This file provides updated implementations for entity-related actions
# It should be integrated into the existing plan_executor.gd

# Enhanced entity action implementations
func _execute_lay_mines_enhanced(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Enhanced lay mines tactical action with entity manager integration"""
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
        
        # Deploy mines in a pattern
        var mines_deployed = 0
        var mine_pattern = _get_mine_pattern(mine_count)
        
        for offset in mine_pattern:
            var deploy_tile = tile_pos + offset
            
            # Deploy mine through entity manager
            var mine_id = entity_manager.deploy_mine(deploy_tile, mine_type, unit.team_id, unit_id)
            
            if mine_id != "":
                mines_deployed += 1
                print("PlanExecutor: Mine %s deployed at tile %s" % [mine_id, deploy_tile])
            else:
                print("PlanExecutor: Failed to deploy mine at tile %s" % deploy_tile)
        
        print("PlanExecutor: %s successfully deployed %d/%d mines" % [unit_id, mines_deployed, mine_count])
        return mines_deployed > 0
    
    return false

func _execute_build_turret_enhanced(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Enhanced build turret tactical action with entity manager integration"""
    if not step.params.has("position"):
        return false
    
    # Check if unit is an engineer
    if unit.has_method("get") and unit.get("archetype") == "engineer":
        var pos = step.params.position
        var turret_pos = Vector3(pos[0], pos[1], pos[2])
        var turret_type = step.params.get("type", "basic")
        
        # Get entity manager
        var entity_manager = get_tree().get_first_node_in_group("entity_managers")
        if not entity_manager:
            print("PlanExecutor: No entity manager found for turret construction")
            return false
        
        # Get tile system for position conversion
        var tile_system = _get_tile_system()
        if not tile_system:
            print("PlanExecutor: No tile system found for turret placement")
            return false
        
        # Convert world position to tile position
        var tile_pos = tile_system.world_to_tile(turret_pos)
        
        # Move to position first
        unit.move_to(turret_pos)
        
        # Set up timed turret construction
        await get_tree().create_timer(TURRET_BUILD_DURATION).timeout
        
        # Build turret through entity manager
        var turret_id = entity_manager.build_turret(tile_pos, turret_type, unit.team_id, unit_id)
        
        if turret_id != "":
            print("PlanExecutor: Turret %s construction started at tile %s" % [turret_id, tile_pos])
            return true
        else:
            print("PlanExecutor: Failed to build turret at tile %s" % tile_pos)
            return false
    
    return false

func _execute_hijack_spire_enhanced(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Enhanced hijack spire tactical action with entity manager integration"""
    if not step.params.has("spire_id"):
        return false
    
    var spire_id = step.params.spire_id
    
    # Check if unit is an engineer
    if unit.has_method("get") and unit.get("archetype") == "engineer":
        # Get entity manager
        var entity_manager = get_tree().get_first_node_in_group("entity_managers")
        if not entity_manager:
            print("PlanExecutor: No entity manager found for spire hijacking")
            return false
        
        # Get the spire entity
        var spire = entity_manager.get_spire(spire_id)
        if not spire:
            print("PlanExecutor: Spire %s not found" % spire_id)
            return false
        
        # Check if spire can be hijacked
        if spire.team_id == unit.team_id:
            print("PlanExecutor: Cannot hijack own spire %s" % spire_id)
            return false
        
        if spire.is_being_hijacked:
            print("PlanExecutor: Spire %s is already being hijacked" % spire_id)
            return false
        
        # Move to spire
        var spire_pos = spire.global_position
        unit.move_to(spire_pos)
        
        # Wait for unit to reach spire
        await get_tree().create_timer(2.0).timeout
        
        # Check if unit is close enough to hijack
        var distance = unit.global_position.distance_to(spire_pos)
        if distance > spire.hijack_range:
            print("PlanExecutor: Unit %s too far from spire %s for hijacking" % [unit_id, spire_id])
            return false
        
        # The spire's hijack system will automatically detect the engineer unit
        # and start the hijack process. We just need to wait for completion.
        print("PlanExecutor: %s starting hijack of spire %s" % [unit_id, spire_id])
        
        # Connect to hijack completion signal
        var hijack_completed = false
        var hijack_failed = false
        
        var complete_handler = func(completed_spire_id: String, new_team: int, hijacker: Unit):
            if completed_spire_id == spire_id:
                hijack_completed = true
        
        var failed_handler = func(failed_spire_id: String, reason: String):
            if failed_spire_id == spire_id:
                hijack_failed = true
        
        spire.spire_hijack_completed.connect(complete_handler)
        spire.spire_hijack_failed.connect(failed_handler)
        
        # Wait for hijack to complete or fail
        var wait_time = 0.0
        var max_wait_time = spire.hijack_time + 5.0  # Add buffer time
        
        while not hijack_completed and not hijack_failed and wait_time < max_wait_time:
            await get_tree().create_timer(0.1).timeout
            wait_time += 0.1
        
        # Disconnect signals
        spire.spire_hijack_completed.disconnect(complete_handler)
        spire.spire_hijack_failed.disconnect(failed_handler)
        
        if hijack_completed:
            print("PlanExecutor: Spire %s successfully hijacked by %s" % [spire_id, unit_id])
            return true
        else:
            print("PlanExecutor: Spire %s hijack failed for %s" % [spire_id, unit_id])
            return false
    
    return false

func _execute_repair_enhanced(unit_id: String, step: PlanStep, unit: Node) -> bool:
    """Enhanced repair action with entity manager integration"""
    if not step.params.has("target_id"):
        return false
    
    var target_id = step.params.target_id
    
    # Check if unit is an engineer
    if unit.has_method("get") and unit.get("archetype") == "engineer":
        # Get entity manager
        var entity_manager = get_tree().get_first_node_in_group("entity_managers")
        if not entity_manager:
            print("PlanExecutor: No entity manager found for repair")
            return false
        
        # Try to find target as turret first
        var target_turret = entity_manager.get_turret(target_id)
        if target_turret:
            return _repair_turret(unit_id, unit, target_turret)
        
        # Try to find target as regular unit
        var target_unit = _get_unit(target_id)
        if target_unit:
            return _repair_unit(unit_id, unit, target_unit)
        
        print("PlanExecutor: Repair target %s not found" % target_id)
        return false
    
    return false

func _repair_turret(unit_id: String, unit: Node, target_turret: Node) -> bool:
    """Repair a turret entity"""
    
    # Move to turret
    unit.move_to(target_turret.global_position)
    
    # Wait for movement
    await get_tree().create_timer(REPAIR_DURATION).timeout
    
    # Check if turret needs repair
    if target_turret.current_health >= target_turret.max_health:
        print("PlanExecutor: Turret %s doesn't need repair" % target_turret.turret_id)
        return true
    
    # Repair turret
    var repair_amount = 50.0  # Default repair amount
    var new_health = min(target_turret.max_health, target_turret.current_health + repair_amount)
    target_turret.current_health = new_health
    
    # Emit health change signal
    target_turret.turret_health_changed.emit(target_turret.turret_id, new_health, target_turret.max_health)
    
    print("PlanExecutor: %s repaired turret %s for %.1f health" % [unit_id, target_turret.turret_id, repair_amount])
    return true

func _repair_unit(unit_id: String, unit: Node, target_unit: Node) -> bool:
    """Repair a unit"""
    
    # Move to target
    var repair_distance = 2.0
    var direction = (target_unit.global_position - unit.global_position).normalized()
    var repair_pos = target_unit.global_position - direction * repair_distance
    unit.move_to(repair_pos)
    
    # Wait for movement
    await get_tree().create_timer(REPAIR_DURATION).timeout
    
    # Apply repair
    if target_unit.has_method("heal"):
        var repair_amount = 20.0
        target_unit.heal(repair_amount)
        print("PlanExecutor: %s repaired unit %s for %.1f health" % [unit_id, target_unit.unit_id, repair_amount])
        return true
    
    return false

func _get_mine_pattern(mine_count: int) -> Array[Vector2i]:
    """Get mine deployment pattern based on count"""
    
    match mine_count:
        1:
            return [Vector2i.ZERO]
        2:
            return [Vector2i.ZERO, Vector2i(1, 0)]
        3:
            return [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0)]
        4:
            return [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1)]
        5:
            return [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
        _:
            # For more than 5 mines, create a grid pattern
            var pattern = []
            var side_length = int(sqrt(mine_count)) + 1
            
            for i in range(mine_count):
                var x = i % side_length - side_length / 2
                var y = i / side_length - side_length / 2
                pattern.append(Vector2i(x, y))
            
            return pattern

func _get_tile_system() -> Node:
    """Get tile system reference"""
    
    var map_generator = get_tree().get_first_node_in_group("map_generators")
    if map_generator and map_generator.has_method("get_tile_system"):
        return map_generator.get_tile_system()
    
    return null

# Constants for timing
const MINE_LAY_DURATION = 2.0
const TURRET_BUILD_DURATION = 1.0
const REPAIR_DURATION = 1.5
const HIJACK_DURATION = 5.0 